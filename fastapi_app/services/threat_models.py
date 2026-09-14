"""The three-model threat pipeline — what each model is, and what it owes.

**Status: all three signals are trained and wired.** Nothing here invents a
score. A model that is not loaded reports itself as unavailable, and its
modality is excluded from the fusion rather than counted as calm — see
`threat_fusion.fuse_available` for why that distinction is a safety property
and not a nicety.

Where each one runs, and what it measured:

    glove   MPU6050 accel + gyro ─▶ XGBoost on the ESP32     ─▶ motion_score
            BLE to the phone, which maps the class onto 0..1 and reports it.

    audio   phone microphone ─▶ platform ASR ─▶ TF-IDF + logistic regression
            On the phone, in pure Dart. 0.905 accuracy at 0.968 recall on the
            elevated/normal boundary, over held-out phrasings.

    weapon  glasses camera ─▶ MJPEG over WiFi ─▶ YOLOv8n on the phone
            mAP@0.5 0.906 on 658 held-out images, LiteRT fp16.

    emotion  trained (65.5%) and deliberately NOT a fusion input. It is
             supporting evidence only; `test_fusion_architecture.py` enforces
             that it can never reach the score.

Two things this pipeline still does not do, both recorded so neither gets
assumed:

* Notifying a police station or help centre is not implemented. See
  `docs/TRACEABILITY.md` — it needs a real dispatch integration, and a safety
  app must never imply it has called for help when it has not.
* On web there is no on-device weapon detector; the plugin is Android-only, so
  that signal is absent rather than zero on that platform.

The original design, per the product design and SRS §6:

    glove  MPU6050 accel + gyro  ──▶ XGBoost      ──▶ motion_score
    glove  pulse sensor          ──▶ (booster)    ──▶ heart_rate_bpm
    glasses microphone           ──▶ CNN + LSTM   ──▶ audio_score
    glasses camera               ──▶ YOLOv8       ──▶ vision_score
                                                        + weapon_confidence
                                          │
                                          ▼
                        threat_fusion.fuse_available  (SRS §6.2 weights)
                                          │
                        smooth ▸ boosters ▸ threshold ▸ dedup
                                          │
                                          ▼
                             FR-EMG-02 automatic SOS

**Where inference runs was deliberately not decided here, and that paid off.**
SRS §6.3 put YOLOv8 on GPU-enabled Cloud Run and TFLite models in firmware.
Neither survived contact: an ESP32 cannot run YOLOv8 whatever the ambition
(`docs/WEAPON_INFERENCE_PLACEMENT.md` has the arithmetic), and streaming a
woman's continuous video to a server to be scored is a privacy cost far larger
than the one it saves. Both models ended up on the phone instead.

This module takes *scores*, not frames, which is why that move cost nothing
here. The contract did not change.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Optional


class ModelStatus(str, Enum):
    """Deliberately not a boolean.

    "Untrained" and "trained but failed to load" need different responses
    from an operator, and collapsing them into `available: false` loses the
    only information that distinguishes them.
    """

    UNTRAINED = "untrained"
    UNAVAILABLE = "unavailable"
    READY = "ready"


@dataclass(frozen=True)
class ModelSpec:
    """One model in the fusion pipeline."""

    modality: str
    algorithm: str
    source_device: str
    inputs: str
    produces: str
    status: ModelStatus = ModelStatus.UNTRAINED
    notes: str = ""

    @property
    def is_ready(self) -> bool:
        return self.status is ModelStatus.READY


# The registry. Weights for these modalities live in `threat_fusion` and
# come from SRS §6.2 — they are not repeated here, so there is one place to
# change them and no chance of the two drifting apart.
MODELS: tuple[ModelSpec, ...] = (
    ModelSpec(
        modality="motion",
        algorithm="XGBoost",
        source_device="glove",
        inputs="MPU6050 3-axis accelerometer + gyroscope windows",
        produces="motion_score in [0, 1]",
        notes=(
            "Light enough to run on the ESP32 as a TFLite/native build, "
            "which is what keeps detection working when the phone is out "
            "of reach — the case the glove exists for."
        ),
    ),
    ModelSpec(
        modality="audio",
        algorithm="CNN + LSTM",
        source_device="glasses",
        inputs="microphone stream, windowed spectrogram",
        produces="audio_score in [0, 1] over distress speech",
        notes=(
            "Raw audio must not leave the device for scoring. Evidence is "
            "encrypted at rest under SafeHer's own key (FR-EMG-07), and "
            "sending an assault recording to a third-party transcription "
            "service is a materially different privacy decision that no "
            "module should take quietly."
        ),
    ),
    ModelSpec(
        modality="vision",
        algorithm="YOLOv8",
        source_device="glasses",
        inputs="camera frames",
        produces="vision_score in [0, 1], plus weapon_confidence",
        notes=(
            "Too heavy for the ESP32; SRS §6.3 places it on GPU-enabled "
            "Cloud Run. weapon_confidence feeds §6.2's +0.15 booster above "
            "0.70, separately from vision_score itself."
        ),
    ),
)

MODELS_BY_MODALITY = {spec.modality: spec for spec in MODELS}


def registry_report() -> dict:
    """What an operator needs to know before trusting a threat score.

    Surfaced through the API so "why did nothing trigger?" has an answer
    that does not require reading the source.
    """
    return {
        "models": [
            {
                "modality": spec.modality,
                "algorithm": spec.algorithm,
                "source_device": spec.source_device,
                "produces": spec.produces,
                "status": spec.status.value,
            }
            for spec in MODELS
        ],
        "any_ready": any(spec.is_ready for spec in MODELS),
        "pipeline_live": all(spec.is_ready for spec in MODELS),
        # Stated rather than implied: with no trained model, every score the
        # backend receives came from a caller, not from SafeHer's own
        # inference.
        "scores_are_caller_supplied": not any(spec.is_ready for spec in MODELS),
    }


@dataclass(frozen=True)
class ModalityScores:
    """One synchronised read across whichever sensors reported.

    Every field is optional because partial coverage is the normal case: the
    glasses can be off while the glove is transmitting. `None` means "this
    sensor did not report", which is never the same as 0.0 — a zero would
    claim the sensor looked and found calm.
    """

    motion: Optional[float] = None
    audio: Optional[float] = None
    vision: Optional[float] = None
    weapon_confidence: float = 0.0
    heart_rate_bpm: Optional[float] = None

    @property
    def reporting_modalities(self) -> list[str]:
        return [
            name
            for name, value in (
                ("motion", self.motion),
                ("audio", self.audio),
                ("vision", self.vision),
            )
            if value is not None
        ]

    @property
    def has_any(self) -> bool:
        return bool(self.reporting_modalities)


# Above this, YOLOv8's weapon class is reported as a weapon rather than a
# maybe. Matches SRS §6.2's booster floor so the report and the score agree
# about what counted.
WEAPON_REPORTING_FLOOR = 0.70


def describe(scores: "ModalityScores", *, weapon_label: Optional[str] = None) -> str:
    """What the models saw, in a sentence a frightened person can read.

    An incident report has to answer "why did SafeHer decide I was in
    danger?". "Threat score 0.83" does not answer it. "Sudden violent motion,
    distress in your voice, and a knife detected in view" does — she can
    recognise her own emergency in that, or recognise that it was wrong.

    It matters forensically too: a conclusion offered as evidence has to say
    what produced it, and a number with no provenance is evidence of nothing.

    Absent modalities are named as absent rather than omitted. "The glasses
    were not sending video" is a materially different report from silence,
    which reads as though the camera saw nothing worrying.
    """
    parts: list[str] = []

    def band(value: float, low: str, mid: str, high: str) -> str:
        if value >= 0.75:
            return high
        if value >= 0.4:
            return mid
        return low

    if scores.motion is None:
        parts.append("The glove was not sending motion readings.")
    else:
        parts.append(
            band(
                scores.motion,
                "Movement looked ordinary.",
                "Unusual movement was detected.",
                "Sudden, violent movement was detected.",
            )
        )

    if scores.audio is None:
        parts.append("The glasses were not sending audio.")
    else:
        parts.append(
            band(
                scores.audio,
                "Nothing alarming was heard.",
                "Raised or distressed speech was heard.",
                "Distress and calls for help were heard.",
            )
        )

    if scores.vision is None:
        parts.append("The glasses were not sending video.")
    else:
        parts.append(
            band(
                scores.vision,
                "Nothing alarming was seen.",
                "Something concerning was seen.",
                "A violent scene was seen.",
            )
        )

    if scores.weapon_confidence > WEAPON_REPORTING_FLOOR:
        weapon = weapon_label or "a weapon"
        parts.append(f"{weapon.capitalize()} was detected in view.")

    if scores.heart_rate_bpm is not None and scores.heart_rate_bpm >= 120:
        parts.append(f"Heart rate was raised, at {round(scores.heart_rate_bpm)} bpm.")

    return " ".join(parts)
