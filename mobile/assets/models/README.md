# On-device models

## `weapon_yolov8n_int8.onnx`

YOLOv8-nano, two classes, INT8-quantised. **3.36 MB.**

| | |
|---|---|
| Classes | `0 pistol`, `1 knife` — order matters, see `weapon_labels.txt` |
| Input | `1×3×640×640`, RGB, float32, normalised 0–1 |
| Output | `1×6×8400` — `[cx, cy, w, h, pistol_conf, knife_conf]` per anchor |
| Trained | v2, 2026-08-31, 120 epochs, RTX 3050 |
| Data | 7,539 images / 8,689 boxes — Open Images V7 + OD-WeaponDetection + Sohas |

### Measured on a held-out test split

658 images, 783 boxes. Never trained on, never used to pick a checkpoint, and
**byte-identical between v1 and v2** so the two are directly comparable.

| | v1 fp32 | v2 fp32 | **v2 INT8 (this file)** |
|---|---|---|---|
| Size | 6.22 MB | 6.24 MB | **3.36 MB** |
| mAP@0.5 | 0.8936 | 0.9067 | **0.9013** |
| mAP@0.5:0.95 | 0.6442 | 0.6518 | **0.6226** |
| Precision | 0.9044 | 0.9004 | **0.9009** |
| Recall | 0.7962 | 0.8352 | **0.8268** |
| pistol AP@0.5 | 0.9285 | 0.9296 | **0.9255** |
| knife AP@0.5 | 0.8586 | 0.8838 | **0.8771** |

Quantisation costs about half a point of mAP@0.5 and one point of recall for a
46% size reduction. Measured, not assumed — a quantised detector that had lost
ten points of recall would still load, still run and still draw boxes; it would
simply miss more knives.

### What v2 fixed

v1's knife detection was materially worse than its pistol detection, and the
diagnosis pointed at intra-class variance rather than object size: knife recall
was **flat across box sizes** (85.2% medium, 84.2% large) and worse than pistol
even on large boxes (90.3%). A knife filling the frame was still missed one
time in six, which rules out resolution as the cause.

The cause was a gap in the data. Open Images treats `Knife`, **`Kitchen knife`**
and `Dagger` as three separate boxable classes, and v1 pulled only `Knife`.
Adding the other two, plus Granada's Sohas subset filtered to pistol and knife,
raised knife training boxes 26%.

| | v1 | v2 |
|---|---|---|
| knife recall | 0.763 | **0.827** |
| pistol recall | 0.830 | 0.843 |
| **pistol − knife recall gap** | **6.7 pts** | **1.6 pts** |

Pistol barely moved, which is the right shape for a knife-specific
intervention. New data went to train and val only — the test split was frozen,
and every candidate image was content-hashed against all three existing splits,
which caught 3,541 duplicates that would otherwise have contaminated it.

### The number to watch

**Recall 0.827.** Roughly one weapon in six is still missed. Precision (0.901)
sits above recall, so the default confidence threshold is tuned conservative.
For SafeHer that is probably the wrong direction — a missed knife is a woman
with no alarm, while a false positive is absorbed by the weapon scorer's
persistence rule and the fusion engine's smoothing. **Trading precision for
recall by lowering the confidence threshold is a product decision that has not
been made.**

### Not yet wired up

Nothing in `lib/` loads this file. It is bundled and validated; there is no
inference code, no ONNX runtime dependency in `pubspec.yaml`, and
`weapon_score` still has no producer. `DetectionSources` does not claim
otherwise.

### Attribution required

- **Open Images V7** (Google) — annotations CC BY 4.0, images CC BY 2.0.
- **OD-WeaponDetection / Sohas** (Universidad de Granada, ari-dasci) — **the
  repository states two different licences.** `LICENSE` says CC BY 4.0; the
  README badge and text say CC BY-**SA** 4.0. Treated as ShareAlike until the
  maintainers confirm. **Resolve before any commercial release** — it remains
  the majority of the training images.

Training pipeline and full runs live outside this repo at
`D:\SafeHer-ML\weapon_detection\`.

---

## `emotion_mobilenetv3_fp16.onnx`

MobileNetV3-Small, 7 expression classes, fp16. **3.09 MB.**

| | |
|---|---|
| Classes | see `emotion_labels.txt` — angry, disgust, fear, happy, neutral, sad, surprise |
| Input | `1×3×96×96`, RGB (grayscale replicated), ImageNet normalisation |
| Output | `1×7` logits |
| Trained | 2026-09-01, 40 epochs, RTX 3050 |
| Data | FER2013 — 28,709 train / 3,589 val / 3,589 test, the canonical split |

### Measured on the held-out test split

**Overall accuracy 65.5%.** fp16 is lossless against fp32 (0.6551 vs 0.6545).

| class | recall | precision | support |
|---|---|---|---|
| happy | 81.8% | 88.0% | 879 |
| sad | 83.7% | 74.2% | 416 |
| disgust | 76.4% | 36.8% | 55 |
| surprise | 68.7% | 58.4% | 626 |
| angry | 59.1% | 53.9% | 491 |
| **fear** | **47.0%** | **56.1%** | 528 |
| neutral | 46.1% | 57.9% | 594 |

65.5% is not underperformance. Human agreement on FER2013 sits around 65% and
published models land in the low-to-mid 70s; this is 7-way classification over
48×48 grayscale thumbnails. Treat anything much above 75% on this dataset as a
sign of a leak rather than a better model.

### The finding that matters

**`fear` is the worst-performing class that anyone would care about.** Recall
47.0%, precision 56.1% — it misses more than half of fearful faces, and when it
does fire it is right barely more often than a coin toss. The confusion matrix
scatters fear across angry, sad, surprise and neutral more or less evenly.

The single expression with any conceivable relevance to a safety product is the
least reliable thing this model produces. That is not a defect to be fixed with
more epochs; it is what facial expression recognition is like.

**So this model must never be shown as a finding.** Its output belongs in
`SupportingContext.facial_expression` and cannot reach `ThreatSignals` — three
fields, no room for a fourth, enforced by `tests/test_fusion_architecture.py`.
If it is ever surfaced in the UI, phrase it as a possibility and show the
confidence, never as "Fear detected".

### INT8 destroys this model — do not quantise it further

Dynamic INT8 quantisation drops accuracy from **65.5% to 16.9%**, barely above
the 14.3% random baseline. Per-channel quantisation is no better at 18.7%.
MobileNetV3's hard-swish activations and squeeze-excite blocks over depthwise
separable convolutions have per-channel weight ranges that per-tensor scaling
collapses.

This was caught only by validating on the real test set. A check against random
input reported **100% agreement** between the INT8 and fp32 models, because
noise produces garbage logits that agree by luck. The broken INT8 files have
been deleted so they cannot be picked up by mistake.

fp16 is the right target here: half the size, no measurable loss.

### Not yet wired up

As with the weapon detector, nothing in `lib/` loads this. There is no ONNX
runtime dependency and no inference code. It is bundled and measured, and it
does not run.

### Licence

FER2013 was released for the ICML 2013 Challenges in Representation Learning.
Verify the terms attach to your use before any commercial release. Weights are
initialised from torchvision's ImageNet MobileNetV3-Small.
