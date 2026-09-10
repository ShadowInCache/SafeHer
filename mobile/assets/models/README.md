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
