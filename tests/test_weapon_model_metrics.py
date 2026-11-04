"""Pins what the shipped weapon detector actually does.

Two artefacts ship and they are not the same file. `ml_models/
weapon_yolov8n_int8.onnx` runs server-side; `mobile/assets/models/
weapon_yolov8n_fp16.tflite` is what the phone loads, and that one is in the
glasses path. Both were measured on the 658-image held-out test split at the
0.55 floor the app applies:

    artefact                      precision   recall      F1
    weapon_yolov8n_fp16.tflite       0.9320   0.8046  0.8636
    weapon_yolov8n_int8.onnx         0.9314   0.7982  0.8597

Training published precision 0.9112 / recall 0.8277 / mAP50 0.8949, but on the
*val* split, and at a lower confidence. At 0.45 the int8 model scores 0.9153 /
0.8276 -- the published figures, reproduced -- so quantisation cost nothing
measurable. That was the question these artefacts existed to answer, and the
answer is reassuring.

## The finding that is not reassuring

Every image in all three splits contains a weapon. There are no background
images anywhere in the 7,539, so that precision is precision *given a weapon is
present*, and nothing in the dataset measures what the detector does on the
ordinary frames the glasses spend almost all their time looking at.

Measured against 3,218 weapon-free hand-held objects from the OD-WeaponDetection
"similar handled objects" set -- a phone, a purse, a banknote, a card, with any
image naming a weapon excluded -- **14.6% produce a detection at 0.55**. A purse
was called a pistol at 0.929.

`WeaponScorer` is built to survive that: it scores `meanConfidence * hits/5`,
so one bad frame in five becomes 0.18. That defence assumes false positives are
independent between frames. They are not. Expanding each still into five frames
the way a camera differs frame to frame -- small shift, scale, brightness, fresh
JPEG -- the outcome is bimodal: 69.6% never fire, **11.8% fire on all five**,
little in between. When the model is wrong about an object it is reliably wrong,
so persistence passes the error through at full strength.

The consequence, measured: 13.8% of weapon-free objects produce a weapon_score
over 0.55, and **4.2% sustain one at or above 0.75**. `fuse` renormalises over
reporting signals, so a weapon reading alone *is* the fused score, and auto-SOS
compares its EMA against DEFAULT_THREAT_THRESHOLD = 0.75. A purse at 0.908
crosses in five posts; the median is seven. The camera dwell is 45 seconds and
the audio that opened it goes stale after 10, so a weapon-only window of about
35 seconds is the normal case, not an edge one.

The root cause is the training set, not the threshold: a YOLO model trained
without background images has never been shown what "no weapon" looks like. The
negatives are already on disk.

Caveat kept with the number: these are tight crops, not full frames. They
measure whether a hand-held object is mistaken for a weapon, which is the
relevant question when the camera opens on someone holding something. They do
not measure an empty street, and the rate on real glasses footage is unmeasured.
"""
from __future__ import annotations

import hashlib
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
ONNX = ROOT / "ml_models/weapon_yolov8n_int8.onnx"
TFLITE = ROOT / "mobile/assets/models/weapon_yolov8n_fp16.tflite"
LABELS = ROOT / "ml_models/weapon_labels.txt"
SCORER = ROOT / "mobile/lib/features/devices/domain/weapon_scorer.dart"
FUSION = ROOT / "fastapi_app/services/threat_fusion.py"

NEG_BASE = Path(
    "D:/SafeHer-ML/weapon_detection/datasets/od_weapondetection/repo/"
    "Weapons and similar handled objects/Sohas_weapon-Classification"
)
TEST_IMAGES = Path("D:/SafeHer-ML/weapon_detection/datasets/merged/images/test")

CONFIDENCE_FLOOR = 0.55

# `WeaponScorer`'s own default window, which is NOT what runs. `ThreatPipeline`
# builds `WeaponDetectionService` without passing a scorer, so that service's
# `_defaultScorer()` decides -- window 15, frameTimeout 5 s. This file used to
# pin only the default and call it "the deployed constants", so the deployed
# window could have been changed to anything without a single test noticing.
DEFAULT_WINDOW = 5
DEPLOYED_WINDOW = 15
DEPLOYED_FRAME_TIMEOUT_SECONDS = 5
ON_DEVICE_INTERVAL_MS = 200

DETECTION_SERVICE = (
    ROOT / "mobile/lib/features/devices/data/weapon_detection_service.dart"
)
PIPELINE = ROOT / "mobile/lib/features/safety/data/threat_pipeline.dart"

# The arithmetic below models the scorer. It divides by whichever window the
# thing being described actually uses, so name it explicitly at each use rather
# than letting one `WINDOW` stand for both.
WINDOW = DEFAULT_WINDOW

# The TFLite asset is a FlatBuffer followed by an appended Ultralytics metadata
# archive, which is how the plugin learns its class names (see
# `tests/test_weapon_model_metadata.py`). TFLite finds its root table from the
# file header and ignores trailing bytes, so inference reads the FlatBuffer
# only. Every measurement in this file is therefore a property of the graph, and
# the graph is what gets pinned below -- which is why that hash is unchanged
# from the run that produced these numbers even though the file on disk grew by
# 428 bytes when the metadata was attached.
TFLITE_GRAPH_BYTES = 6129244
PK_LOCAL_HEADER = b"PK\x03\x04"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_the_artifacts_are_the_ones_that_were_measured():
    """Every number in this file describes these exact bytes."""
    assert _sha256(ONNX) == (
        "45811e6a65ab995363f9d97e59cd9f77961b5f914cf5bda9e9133f3fa0e1ff2e"
    ), "the server-side ONNX changed -- re-measure before trusting this file"

    data = TFLITE.read_bytes()
    graph, trailer = data[:TFLITE_GRAPH_BYTES], data[TFLITE_GRAPH_BYTES:]
    assert hashlib.sha256(graph).hexdigest() == (
        "b5625bcf6bc1d86f8780e5acbc989f5759efea0c80d6f1e3fe9761625d87c338"
    ), "the APK TFLite graph changed -- re-measure before trusting this file"

    # Splitting at a hard-coded offset is only honest if the split is the real
    # boundary: anything else and a graph change could hide in the 'trailer'.
    assert not trailer or trailer.startswith(PK_LOCAL_HEADER), (
        f"bytes at offset {TFLITE_GRAPH_BYTES} are not the start of an appended "
        f"archive, so TFLITE_GRAPH_BYTES is no longer the graph/metadata "
        f"boundary and the hash above is pinning the wrong span"
    )


def test_the_shipped_asset_is_the_one_that_was_built():
    """Pin the whole file too, so what goes into the APK is still exact.

    Separate from the graph pin above because the two answer different
    questions. A failure here with the graph pin intact means the metadata
    changed, which cannot alter any measurement in this file. A failure of the
    graph pin means the detector itself changed and every number here is stale.
    """
    assert _sha256(TFLITE) == (
        "afcfbe8c8664e2ecf34bd74ff32ac55ca3fdf1f884f7cbc6626fb70cf94a347b"
    ), "the APK TFLite asset changed -- confirm the graph pin above still holds"


def test_the_classes_are_still_only_pistol_and_knife():
    """A pair of scissors held up to the camera scores 0.0, correctly.

    Worth pinning because it caused a real misreading during hardware testing:
    a zero was taken for a broken pipeline when it was the model being right
    about an object it was never trained to find.
    """
    assert LABELS.read_text(encoding="utf-8").split() == ["pistol", "knife"]


@pytest.mark.parametrize(
    "source, pattern, expected, label",
    [
        (SCORER, r"confidenceFloor = ([0-9.]+)", CONFIDENCE_FLOOR, "scorer floor"),
        (SCORER, r"this\.window = (\d+)", DEFAULT_WINDOW, "scorer default window"),
        # The values that actually run. Pinned separately from the defaults
        # above, because they are set somewhere else entirely.
        (DETECTION_SERVICE, r"WeaponScorer\(window: (\d+)", DEPLOYED_WINDOW,
         "DEPLOYED scorer window"),
        (DETECTION_SERVICE, r"frameTimeout: const Duration\(seconds: (\d+)\)",
         DEPLOYED_FRAME_TIMEOUT_SECONDS, "DEPLOYED frame timeout"),
        (PIPELINE, r"Duration\(milliseconds: (\d+)\)\s*:\s*const Duration\(seconds: 2\)",
         ON_DEVICE_INTERVAL_MS, "DEPLOYED on-device inference interval"),
        (FUSION, r"DEFAULT_THREAT_THRESHOLD = ([0-9.]+)", 0.75, "auto-SOS threshold"),
        (FUSION, r"EMA_ALPHA = ([0-9.]+)", 0.30, "EMA alpha"),
        (FUSION, r"SOLO_SIGNAL_RETENTION = ([0-9.]+)", 0.50, "solo retention"),
    ],
)
def test_the_deployed_constants_match_what_was_measured(
        source, pattern, expected, label):
    """Change one of these and the measurements above describe nothing."""
    m = re.search(pattern, source.read_text(encoding="utf-8", errors="ignore"))
    assert m, f"could not find {label} in {source.name}"
    assert float(m.group(1)) == float(expected), (
        f"{label} is {m.group(1)} but the measurements assume {expected} -- "
        "re-run the evaluation before changing this expectation"
    )


def test_persistence_does_not_suppress_a_correlated_false_positive():
    """The arithmetic `WeaponScorer` uses, against the measured failure.

    Pure arithmetic, no model: it pins the *reasoning*, which is where the gap
    was. The docstring on `WeaponScorer` argues that a single bad frame scores
    0.18, and that is true. It does not follow that a bad *object* scores 0.18,
    and 11.8% of weapon-free objects fired on all five frames.
    """
    def scorer_value(confidences: list[float]) -> float:
        hits = [c for c in confidences if c >= CONFIDENCE_FLOOR]
        if not hits:
            return 0.0
        return (sum(hits) / len(hits)) * (len(hits) / WINDOW)

    # One frame in five, the case the rule was designed for.
    assert scorer_value([0.90, 0.0, 0.0, 0.0, 0.0]) == pytest.approx(0.18)
    # Five frames of the same purse, the case that was measured.
    assert scorer_value([0.908] * WINDOW) == pytest.approx(0.908)

    # And that score, alone, is the fused score: `fuse` renormalises over the
    # signals that reported, so a lone weapon reading passes through whole.
    from fastapi_app.services import threat_fusion

    fused = threat_fusion.fuse(
        threat_fusion.ThreatSignals(glove=None, audio=None, weapon=0.908)
    )
    assert fused == pytest.approx(0.908), (
        "a weapon reading on its own is the fused score; if this changed, the "
        "solo path was altered and the risk above needs re-deriving"
    )
    assert fused >= threat_fusion.DEFAULT_THREAT_THRESHOLD, (
        "a purse mistaken for a pistol clears the auto-SOS threshold unaided"
    )


def test_a_sustained_false_detection_crosses_auto_sos_within_the_camera_dwell():
    """How long a mistake has to persist before contacts are called.

    Seeded from 0.0, the harder case: `smooth` takes the first reading of a
    journey as-is, so a cold start crosses on post one.
    """
    from fastapi_app.services import threat_fusion

    raw = 0.908
    smoothed = 0.0
    for post in range(1, 61):
        smoothed = threat_fusion.smooth(raw=raw, previous=smoothed)
        if smoothed >= threat_fusion.DEFAULT_THREAT_THRESHOLD:
            break
    else:
        pytest.fail("expected the EMA to cross; it did not")

    assert post == 5, f"crossed after {post} posts, expected 5"
    # Readings post once a second and the camera dwell is 45 seconds, so there
    # is roughly nine times the exposure needed.
    assert post < 45


# ---------------------------------------------------------------------------
# The measurements below need the dataset, which lives outside the repo.
# ---------------------------------------------------------------------------

requires_dataset = pytest.mark.skipif(
    not (NEG_BASE / "smartphone").is_dir() or not TEST_IMAGES.is_dir(),
    reason="SafeHer-ML dataset not present on this machine",
)


def _onnx_session():
    ort = pytest.importorskip("onnxruntime")
    return ort.InferenceSession(str(ONNX), providers=["CPUExecutionProvider"])


def _peak_score(sess, path: Path) -> float:
    """The strongest class score the model produces on one image."""
    np = pytest.importorskip("numpy")
    image_mod = pytest.importorskip("PIL.Image")

    im = image_mod.open(path).convert("RGB")
    w, h = im.size
    r = min(640 / w, 640 / h)
    nw, nh = round(w * r), round(h * r)
    canvas = image_mod.new("RGB", (640, 640), (114, 114, 114))
    canvas.paste(im.resize((nw, nh), image_mod.BILINEAR),
                 ((640 - nw) // 2, (640 - nh) // 2))
    x = np.asarray(canvas, dtype=np.float32).transpose(2, 0, 1)[None] / 255.0
    out = sess.run(None, {sess.get_inputs()[0].name: x})[0][0]
    return float(out[4:].max())


def _negatives(folder: str, count: int) -> list[Path]:
    """Weapon-free files, in a fixed order, excluding any that name a weapon."""
    paths = sorted(
        p for p in (NEG_BASE / folder).glob("*.jpg")
        if "pis" not in p.name.lower() and "kni" not in p.name.lower()
    )
    return paths[:count]


@requires_dataset
@pytest.mark.parametrize(
    "folder, expected_hits",
    [("smartphone", 16), ("monedero", 19)],
)
def test_false_positive_rate_on_weapon_free_objects_has_not_worsened(
        folder, expected_hits):
    """A fixed 100-file slice, so the number is comparable run to run.

    Pinned rather than asserted away: the point is to notice movement, in
    either direction. A retrain that adds background images should make this
    fall, and that is the fix -- so when it does, update the expectation and
    keep the test.
    """
    sess = _onnx_session()
    paths = _negatives(folder, 100)
    assert len(paths) == 100, f"expected 100 {folder} files, found {len(paths)}"

    hits = sum(1 for p in paths if _peak_score(sess, p) >= CONFIDENCE_FLOOR)
    assert hits == expected_hits, (
        f"{folder}: {hits}/100 weapon-free images produced a detection at "
        f"{CONFIDENCE_FLOOR}, was {expected_hits}. If a retrain lowered this, "
        "update the expectation; if something raised it, the detector got worse "
        "on exactly the frames the glasses mostly see."
    )
