"""Pin the shipped glove model's measured behaviour.

The model on the wrist is an XGBoost forest exported to embedded C. Nothing
stopped someone retraining it, regenerating the arrays and flashing a model
that was worse in exactly the way that matters -- more NORMAL windows called
FALL -- because the only published figure was overall accuracy, which barely
moves when one class degrades.

These tests run the shipped model over the locked held-out test set and assert
the numbers that decide whether a woman's glove wakes her contacts at 3am for
nothing. They are deliberately asserted as bounds rather than exact values, so
a genuine improvement passes and a regression fails.

Skipped where the ML dependencies are not installed: the backend CI image is
slim by design, and requiring xgboost to run the API suite would be the wrong
trade. Run locally, or in a job that installs `requirements.txt`.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import pytest

pytest.importorskip("xgboost", reason="ML extras not installed")
pytest.importorskip("sklearn", reason="ML extras not installed")
pd = pytest.importorskip("pandas", reason="ML extras not installed")

import numpy as np  # noqa: E402  (after the skips, by design)

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "glove/ml/scripts"
MODEL_DIR = ROOT / "glove/ml/models/glove_5class_v7_merged_pushpulljerk_final"
COMPARISON = MODEL_DIR / "v7_merged_pushpulljerk_candidate_vs_original_v5_comparison.json"
FIRMWARE = ROOT / "glove/firmware/SafeHer_Glove_V5_OnDevice/SafeHer_Glove_V5_OnDevice.ino"
DART_CONFIRMATION = ROOT / "mobile/lib/features/safety/domain/glove_confirmation.dart"

pytestmark = pytest.mark.skipif(
    not COMPARISON.is_file(), reason="glove evaluation artefacts not present"
)


@pytest.fixture(scope="module")
def harness():
    sys.path.insert(0, str(SCRIPTS))
    import evaluate_shipped_model as esm

    return esm


@pytest.fixture(scope="module")
def scored(harness):
    """Score the locked test set once; every assertion reads from this."""
    from xgboost import XGBClassifier

    classes = json.loads(harness.REPORT.read_text())["class_order"]
    model = XGBClassifier()
    model.load_model(str(harness.MODEL))
    cols = [c for c in pd.read_csv(harness.FEATURES, nrows=1).columns
            if c not in harness.META_COLUMNS]
    df = harness.load_locked_test(cols)
    proba = model.predict_proba(df[cols].values)
    return harness, df, proba, classes


def test_the_locked_evaluation_still_reproduces(scored):
    """Everything below is meaningless if the published run no longer matches."""
    from sklearn.metrics import accuracy_score, f1_score

    harness, df, proba, classes = scored
    published = json.loads(COMPARISON.read_text())
    pred = [classes[i] for i in proba.argmax(1)]

    assert len(df) == published["total_test_windows"], "locked test set changed size"
    assert accuracy_score(df["label"], pred) == pytest.approx(
        published["candidate"]["accuracy"], abs=1e-6)
    assert f1_score(df["label"], pred, average="macro") == pytest.approx(
        published["candidate"]["macro_f1"], abs=1e-6)


def test_the_firmware_model_is_the_evaluated_one(scored):
    """The embedded arrays must come from the model these metrics describe."""
    firmware_cpp = ROOT / "glove/firmware/SafeHer_Glove_V5_OnDevice/safeher_v5_model.cpp"
    trained_cpp = MODEL_DIR / "esp32_compact/safeher_v5_model.cpp"
    if not (firmware_cpp.is_file() and trained_cpp.is_file()):
        pytest.skip("embedded model artefacts not present")
    import hashlib

    def sha(p):
        return hashlib.sha256(p.read_bytes()).hexdigest()

    assert sha(firmware_cpp) == sha(trained_cpp), (
        "the flashed model is not the evaluated model -- regenerate the embedded "
        "arrays or re-run the evaluation before trusting any metric here")


def test_fall_precision_has_not_regressed(scored):
    """A FALL the wearer did not have is what wakes her contacts for nothing."""
    from sklearn.metrics import precision_recall_fscore_support

    harness, df, proba, classes = scored
    pred = [classes[i] for i in proba.argmax(1)]
    p, r, _, _ = precision_recall_fscore_support(
        df["label"], pred, labels=classes, zero_division=0)
    fall = classes.index("FALL")
    assert p[fall] >= 0.84, f"FALL precision fell to {p[fall]:.4f} (was 0.8471)"
    assert r[fall] >= 0.74, f"FALL recall fell to {r[fall]:.4f} (was 0.7579)"


def test_the_shipped_gates_hold_false_positives_under_the_srs_target(scored):
    """Measured end of the pipeline, not the bare classifier.

    SRS NFR puts the false-positive rate below 3%. Raw argmax is 13.5%; the
    confidence gate, the firmware debounce and the app's confirmation bring it
    to 1.4%. This asserts the gated figure, because that is what ships.
    """
    harness, df, proba, classes = scored
    stages = [("gated", (True, True, True))]
    result = harness.evaluate(df, proba, classes, stages)["gated"]
    assert result["false_positive_rate"] <= 0.03, (
        f"gated false-positive rate rose to {result['false_positive_rate']*100:.1f}% "
        "-- above the 3% the SRS allows")


def test_every_gate_reduces_false_positives(scored):
    """Each gate must earn its place; one that costs recall for nothing is a bug."""
    harness, df, proba, classes = scored
    stages = [("raw", (False, False, False)),
              ("conf", (True, False, False)),
              ("debounce", (True, True, False)),
              ("app", (True, True, True))]
    r = harness.evaluate(df, proba, classes, stages)
    rates = [r[k]["false_positive_rate"] for k, _ in stages]
    assert rates == sorted(rates, reverse=True), f"a gate increased false positives: {rates}"
    assert rates[0] > rates[-1], "the gates together achieve nothing"


def test_no_real_fall_is_lost_once_the_gates_are_applied(scored):
    """Per-event, not per-window: a fall spans ~19 windows.

    The gates cost per-window recall by design. What must not happen is a fall
    that produces no confirmed report at all.
    """
    harness, df, proba, classes = scored
    pe = harness.per_event(df, proba, classes)
    assert pe["total_falls"] > 0, "no FALL recordings in the locked test set"
    assert pe["falls_detected"] == pe["total_falls"], (
        f"{pe['total_falls'] - pe['falls_detected']} of {pe['total_falls']} falls "
        "produced no confirmed report after gating")


@pytest.mark.parametrize(
    "source, pattern, expected, label",
    [
        # `[\s=]+` so both `#define X 0.65f` and `const float X = 0.65f` match.
        (FIRMWARE, r"FALL_CONFIDENCE_THRESHOLD[\s=]+([0-9.]+)f?", 0.65, "firmware FALL gate"),
        (FIRMWARE, r"SUDDEN_MOVEMENT_CONFIDENCE_THRESHOLD[\s=]+([0-9.]+)f?", 0.65,
         "firmware SUDDEN gate"),
        (FIRMWARE, r"SUDDEN_MOVEMENT_CONFIRMATION_WINDOWS[\s=]+(\d+)", 2, "firmware debounce"),
        (DART_CONFIRMATION, r"requiredHits[\s=]+(\d+)", 3, "app confirmation hits"),
        (DART_CONFIRMATION, r"window\s*=\s*const Duration\(seconds:\s*(\d+)\)", 5,
         "app confirmation window seconds"),
    ],
)
def test_the_harness_models_the_gates_that_are_actually_deployed(
        source, pattern, expected, label):
    """Guards the measurement against drift in the thing being measured.

    Change a threshold in the firmware and forget this script, and it goes on
    reporting a false-positive rate for a pipeline that no longer exists.
    """
    if not source.is_file():
        pytest.skip(f"{source.name} not present")
    m = re.search(pattern, source.read_text(encoding="utf-8", errors="ignore"))
    assert m, f"could not find {label} in {source.name}"
    assert float(m.group(1)) == float(expected), (
        f"{label} is {m.group(1)} in {source.name} but the evaluation harness "
        f"assumes {expected} -- update evaluate_shipped_model.py")


# --------------------------------------------------------------------------
# The weight table is load-bearing in a way that is not obvious from reading it.

DART_PIPELINE = ROOT / "mobile/lib/features/safety/data/threat_pipeline.dart"
DART_PROTOCOL = ROOT / "mobile/lib/features/devices/domain/glove_protocol.dart"

# threat_fusion.DEFAULT_THREAT_THRESHOLD. Duplicated deliberately: the point of
# the test is to fail if the relationship between the two files changes.
AUTO_SOS_THRESHOLD = 0.75


def _glove_weights() -> dict[str, float]:
    """The `ThreatLevel -> weight` table out of `ThreatPipeline.gloveScore`."""
    text = DART_PIPELINE.read_text(encoding="utf-8", errors="ignore")
    block = re.search(
        r"final weight = switch \(classification\.threatLevel\) \{(.+?)\};",
        text, re.S)
    assert block, "could not find the weight switch in threat_pipeline.dart"
    found = dict(re.findall(r"ThreatLevel\.(\w+)\s*=>\s*([0-9.]+)", block.group(1)))
    assert found, "weight switch matched but no arms parsed"
    return {k: float(v) for k, v in found.items()}


def test_only_a_fall_can_reach_auto_sos_unaided():
    """Pins the structural protection measured in glove_persistence_probe.py.

    `fuse()` renormalises over reporting signals, so a glove reading arriving
    alone becomes the fused score outright, and `should_trigger` is a single
    post at or above the threshold. The only thing stopping a confident
    SUDDEN_MOVEMENT from raising an unaided alarm is that its weight of 0.7
    caps the score below 0.75 even at confidence 1.0.

    That is not written down anywhere it would be noticed. Raise the weight to
    1.0 for a plausible-sounding reason -- "someone shoving you is as urgent as
    a fall" -- and every confident SUDDEN_MOVEMENT false positive becomes a
    potential auto-SOS. Measured: 14.3% of normal recordings raise a confirmed
    glove alert, and the two highest non-FALL scores sit at 0.676 and 0.609,
    right under the cap.
    """
    weights = _glove_weights()
    assert weights.get("danger") == 1.0, (
        f"danger weight is {weights.get('danger')}; a FALL must report its own "
        "confidence")
    for level in ("elevated", "caution", "safe"):
        weight = weights.get(level)
        assert weight is not None, f"no weight for ThreatLevel.{level}"
        assert weight < AUTO_SOS_THRESHOLD, (
            f"ThreatLevel.{level} weighs {weight}, so at confidence 1.0 it scores "
            f"{weight} and can reach the {AUTO_SOS_THRESHOLD} auto-SOS threshold "
            "with nothing corroborating it. Only FALL is meant to be able to do "
            "that. If this change is intended, re-run glove_persistence_probe.py "
            "and update the measured exposure in docs/model_evaluation_results.json")


def test_fall_is_the_only_class_mapped_to_danger():
    """The weight table above is only a protection if FALL alone is `danger`.

    `gloveScore` keys off `threatLevel`, not the label, so promoting another
    class to `danger` in glove_protocol.dart would hand it weight 1.0 without
    touching the pipeline at all.
    """
    text = DART_PROTOCOL.read_text(encoding="utf-8", errors="ignore")
    block = re.search(r"ThreatLevel get threatLevel => switch \(label\) \{(.+?)\};",
                      text, re.S)
    assert block, "could not find the threatLevel switch in glove_protocol.dart"
    danger = [
        line for line in block.group(1).splitlines()
        if "ThreatLevel.danger" in line
    ]
    assert len(danger) == 1, f"expected exactly one danger arm, got {danger}"
    assert "'FALL'" in danger[0], (
        f"a class other than FALL is mapped to danger: {danger[0].strip()}")
