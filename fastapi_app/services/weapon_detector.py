"""Server-side weapon detection, for the platform that cannot do it itself.

**This is the fallback, not the main path.** On Android the detector runs on the
phone against a continuous stream from the glasses, and no video ever leaves the
device. Web has no such option — `ultralytics_yolo` has no web implementation —
so a web client posts occasional frames here instead.

That difference is worth stating plainly rather than smoothing over, because it
is a real difference in what the user is agreeing to:

    Android   continuous, ~5 fps, on-device      nothing leaves the phone
    web       sampled, on demand, server-side    the frame is uploaded

The app must say which one is running. A sampled server-side check is a weaker
promise than a continuous local one, and presenting them as the same thing would
be the kind of claim this codebase keeps having to remove.

## Why ONNX here and LiteRT there

The phone runs `weapon_yolov8n_fp16.tflite` because Android's GPU delegate
executes fp16. This runs the INT8 ONNX export of the same weights, because
`onnxruntime` on a CPU-only server is the opposite trade: INT8 is faster there
and the accuracy cost was measured at about one point of mAP.

## The emotion model rides along, and cannot touch the score

A frame that has already been uploaded can be read twice for free, so the
expression classifier runs on it too. Its output goes into `SupportingContext`
and **never** into `fuse()` — that boundary is a product decision recorded in
`threat_fusion`, and `tests/test_fusion_architecture.py` fails if it drifts.

The model's own numbers are the argument for it. 65.5% overall, and `fear` is
its weakest class at 47% recall — the one expression with safety relevance is
close to a coin toss. It is worth recording on an incident and worthless as a
trigger.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from ..config import PROJECT_ROOT
from .threat_models import ModelStatus

logger = logging.getLogger(__name__)

MODEL_DIR = PROJECT_ROOT / "ml_models"
WEAPON_MODEL = MODEL_DIR / "weapon_yolov8n_int8.onnx"
WEAPON_LABELS = MODEL_DIR / "weapon_labels.txt"
EMOTION_MODEL = MODEL_DIR / "emotion_mobilenetv3_fp16.onnx"
EMOTION_LABELS = MODEL_DIR / "emotion_labels.txt"

INPUT_SIZE = 640
EMOTION_INPUT_SIZE = 96

# Below this a box is not reported at all.
#
# Lower than the phone-side scorer's 0.55 floor on purpose: persistence across
# frames is a better filter than a high per-frame threshold, and the web path
# has fewer frames to work with, so discarding weak-but-real ones costs more
# here than it does on Android.
CONFIDENCE_FLOOR = 0.35
IOU_THRESHOLD = 0.45


@dataclass(frozen=True)
class FrameVerdict:
    """What one uploaded frame contained."""

    weapon_confidence: float
    weapon_label: Optional[str]
    #: Supporting context only. Never an input to the threat score.
    emotion_label: Optional[str] = None
    emotion_confidence: Optional[float] = None


class _Session:
    """One lazily-loaded ONNX model, and an honest account of whether it loaded."""

    def __init__(self, path: Path, labels_path: Path) -> None:
        self._path = path
        self._labels_path = labels_path
        self._session = None
        self._labels: list[str] = []
        self._status = ModelStatus.UNTRAINED if not path.exists() else ModelStatus.UNAVAILABLE
        self._tried = False

    @property
    def status(self) -> ModelStatus:
        return self._status

    @property
    def labels(self) -> list[str]:
        return self._labels

    def get(self):
        """The session, or None. Loads once; a failure is not retried per request."""
        if self._tried:
            return self._session
        self._tried = True

        if not self._path.exists():
            # Deliberately distinct from a load failure. "Nobody deployed the
            # file" and "the file is corrupt" need different responses from an
            # operator, and collapsing them loses the only useful information.
            self._status = ModelStatus.UNTRAINED
            logger.warning("weapon/emotion model missing at %s", self._path)
            return None

        try:
            # Imported lazily, and both of them, so that a deployment without
            # the inference extras starts normally and reports this modality as
            # unavailable rather than failing at the first request. `cv2` is
            # checked here too: without it the model would load and then throw
            # on the first frame, which is a worse place to discover it.
            import cv2  # noqa: F401
            import onnxruntime

            self._session = onnxruntime.InferenceSession(
                str(self._path), providers=["CPUExecutionProvider"]
            )
            if self._labels_path.exists():
                self._labels = [
                    line.strip()
                    for line in self._labels_path.read_text().splitlines()
                    if line.strip()
                ]
            self._status = ModelStatus.READY
        except Exception:
            logger.exception("failed to load %s", self._path)
            self._session = None
            self._status = ModelStatus.UNAVAILABLE
        return self._session


_cascade = None
_cascade_tried = False


def _face_cascade():
    """OpenCV's frontal-face cascade, loaded once."""
    global _cascade, _cascade_tried
    if _cascade_tried:
        return _cascade
    _cascade_tried = True
    try:
        import cv2

        path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
        loaded = cv2.CascadeClassifier(path)
        _cascade = None if loaded.empty() else loaded
    except Exception:
        logger.exception("face cascade unavailable")
        _cascade = None
    return _cascade


_weapon = _Session(WEAPON_MODEL, WEAPON_LABELS)
_emotion = _Session(EMOTION_MODEL, EMOTION_LABELS)


def weapon_status() -> ModelStatus:
    _weapon.get()
    return _weapon.status


def emotion_status() -> ModelStatus:
    _emotion.get()
    return _emotion.status


def _letterbox(image, size: int):
    """Resize preserving aspect ratio, padding the remainder with grey.

    Stretching instead would distort every box the model was trained to expect,
    and a knife is a long thin thing whose aspect ratio is most of what
    identifies it.
    """
    import numpy as np

    height, width = image.shape[:2]
    scale = min(size / height, size / width)
    new_h, new_w = int(round(height * scale)), int(round(width * scale))

    import cv2

    resized = cv2.resize(image, (new_w, new_h), interpolation=cv2.INTER_LINEAR)
    canvas = np.full((size, size, 3), 114, dtype=np.uint8)
    top, left = (size - new_h) // 2, (size - new_w) // 2
    canvas[top : top + new_h, left : left + new_w] = resized
    return canvas


def _iou(a, b) -> float:
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    ix1, iy1 = max(ax1, bx1), max(ay1, by1)
    ix2, iy2 = min(ax2, bx2), min(ay2, by2)
    inter = max(0.0, ix2 - ix1) * max(0.0, iy2 - iy1)
    if inter <= 0:
        return 0.0
    area_a = max(0.0, ax2 - ax1) * max(0.0, ay2 - ay1)
    area_b = max(0.0, bx2 - bx1) * max(0.0, by2 - by1)
    union = area_a + area_b - inter
    return inter / union if union > 0 else 0.0


def _decode(output, labels: list[str]) -> tuple[float, Optional[str]]:
    """YOLOv8 head `(1, 4 + nc, anchors)` to the single strongest detection.

    Only the strongest survives because that is all the caller uses: the score
    is `weapon_confidence`, and a second knife in frame does not make the first
    one more dangerous.
    """
    import numpy as np

    raw = np.asarray(output)
    if raw.ndim == 3:
        raw = raw[0]
    if raw.shape[0] > raw.shape[1]:  # (anchors, 4 + nc)
        raw = raw.T

    boxes_xywh = raw[:4].T
    scores = raw[4:]

    best_class = scores.argmax(axis=0)
    best_score = scores.max(axis=0)
    keep = best_score >= CONFIDENCE_FLOOR
    if not keep.any():
        return 0.0, None

    boxes_xywh = boxes_xywh[keep]
    best_class = best_class[keep]
    best_score = best_score[keep]

    corners = np.stack(
        [
            boxes_xywh[:, 0] - boxes_xywh[:, 2] / 2,
            boxes_xywh[:, 1] - boxes_xywh[:, 3] / 2,
            boxes_xywh[:, 0] + boxes_xywh[:, 2] / 2,
            boxes_xywh[:, 1] + boxes_xywh[:, 3] / 2,
        ],
        axis=1,
    )

    order = best_score.argsort()[::-1]
    kept: list[int] = []
    for index in order:
        if all(_iou(corners[index], corners[k]) <= IOU_THRESHOLD for k in kept):
            kept.append(int(index))
        if len(kept) >= 10:
            break

    if not kept:
        return 0.0, None

    winner = kept[0]
    class_index = int(best_class[winner])
    label = labels[class_index] if class_index < len(labels) else None
    return float(best_score[winner]), label


def _emotion_of(image) -> tuple[Optional[str], Optional[float]]:
    """Supporting context only. Never reaches the threat score.

    ## Two things this has to get right, and got wrong first

    The model wants **96x96** input normalised with ImageNet statistics,
    because it was fine-tuned from torchvision's MobileNetV3 through
    `Grayscale(3) -> Resize(96) -> Normalize([0.485,...], [0.229,...])`. The
    first version here fed 48x48 scaled to 0..1. That threw on the shape
    mismatch, the exception was swallowed, and the field came back null on
    every frame -- the endpoint test passed because it only checked the key
    existed. Only running it over real images surfaced it.

    Second, the model classifies **a face**, not a scene. Handing it a whole
    street returns a confident label about nothing. So a face is located first,
    and no face means no expression rather than a guess.
    """
    session = _emotion.get()
    if session is None:
        return None, None

    try:
        import cv2
        import numpy as np

        grey = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

        cascade = _face_cascade()
        faces = (
            cascade.detectMultiScale(grey, scaleFactor=1.1, minNeighbors=5,
                                     minSize=(48, 48))
            if cascade is not None
            else []
        )
        if len(faces) == 0:
            # The honest answer for a frame with nobody's face in it.
            return None, None

        x, y, w, h = max(faces, key=lambda box: box[2] * box[3])
        face = grey[y : y + h, x : x + w]

        resized = cv2.resize(face, (EMOTION_INPUT_SIZE, EMOTION_INPUT_SIZE))
        tensor = (resized.astype(np.float32) / 255.0)[:, :, None]
        tensor = np.repeat(tensor, 3, axis=2)

        # Same statistics the model was fine-tuned through. Skipping these
        # shifts every activation and the outputs stay plausible while being
        # wrong, which is the failure mode with no symptom.
        mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
        std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
        tensor = (tensor - mean) / std
        tensor = np.transpose(tensor, (2, 0, 1))[None, ...].astype(np.float32)

        name = session.get_inputs()[0].name
        logits = np.asarray(session.run(None, {name: tensor})[0])[0]
        exp = np.exp(logits - logits.max())
        probabilities = exp / exp.sum()
        index = int(probabilities.argmax())
        labels = _emotion.labels
        label = labels[index] if index < len(labels) else None
        return label, float(probabilities[index])
    except Exception:
        logger.exception("emotion inference failed")
        return None, None


def analyse_frame(jpeg_bytes: bytes) -> FrameVerdict:
    """Scores one uploaded JPEG.

    A model that is not loaded yields confidence 0.0 with a null label, and the
    caller must report that modality as *absent* rather than as a zero score.
    The distinction is the same safety property `threat_fusion` is built on: a
    zero claims something looked and saw calm.
    """
    session = _weapon.get()
    if session is None:
        return FrameVerdict(weapon_confidence=0.0, weapon_label=None)

    import cv2
    import numpy as np

    array = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    image = cv2.imdecode(array, cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError("not a decodable image")

    letterboxed = _letterbox(image, INPUT_SIZE)
    rgb = cv2.cvtColor(letterboxed, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    tensor = np.transpose(rgb, (2, 0, 1))[None, ...]

    name = session.get_inputs()[0].name
    confidence, label = _decode(session.run(None, {name: tensor})[0], _weapon.labels)

    emotion_label, emotion_confidence = _emotion_of(image)
    return FrameVerdict(
        weapon_confidence=confidence if not math.isnan(confidence) else 0.0,
        weapon_label=label,
        emotion_label=emotion_label,
        emotion_confidence=emotion_confidence,
    )
