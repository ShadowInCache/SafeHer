"""The three-model threat pipeline — what each model is, and what it owes.

**Status: no model is trained yet.** This module exists so that the day one
is, dropping it in is a configuration change rather than an archaeology
expedition. Nothing here invents a score. A model that is not loaded reports
itself as unavailable, and its modality is excluded from the fusion rather
than counted as calm — see `threat_fusion.fuse_available` for why that
distinction is a safety property and not a nicety.

The intended pipeline, per the product design and SRS §6:

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

**Where inference runs is deliberately not decided here.** SRS §6.3 puts
YOLOv8 on GPU-enabled Cloud Run and TFLite models in firmware, and an
ESP32-WROOM-32E cannot run YOLOv8 whatever the ambition. This module takes
*scores*, not frames, so a model can move between firmware, phone and
server without the fusion contract changing.

**Two things this pipeline does not do yet**, both recorded so neither gets
assumed:

* No model is trained, so nothing produces these scores in production.
* Notifying a police station or help centre is not implemented. See
  `docs/TRACEABILITY.md` — it needs a real dispatch integration, and a
  safety app must never imply it has called for help when it has not.
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
