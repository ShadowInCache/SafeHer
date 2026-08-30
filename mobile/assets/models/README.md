# On-device models

## `weapon_yolov8n_int8.onnx`

YOLOv8-nano, two classes, INT8-quantised. **3.36 MB.**

| | |
|---|---|
| Classes | `0 pistol`, `1 knife` — order matters, see `weapon_labels.txt` |
| Input | `1×3×640×640`, RGB, float32, normalised 0–1 |
| Output | `1×6×8400` — `[cx, cy, w, h, pistol_conf, knife_conf]` per anchor |
| Trained | 2026-08-30, 120 epochs, RTX 3050 |
| Data | 6,569 images / 7,616 boxes — Open Images V7 + OD-WeaponDetection |

### Measured on a held-out test split

Never trained on, never used to pick a checkpoint. 658 images, 783 boxes.

| | fp32 `.pt` | **INT8 (this file)** |
|---|---|---|
| Size | 6.22 MB | **3.36 MB** |
| mAP@0.5 | 0.895 | **0.885** |
| mAP@0.5:0.95 | 0.644 | **0.622** |
| Precision | 0.897 | **0.913** |
| Recall | 0.806 | **0.787** |
| pistol AP@0.5 | 0.929 | 0.924 |
| knife AP@0.5 | 0.859 | 0.846 |

Quantisation cost **one point of mAP@0.5 and two points of recall** for a 46%
size reduction. That trade was measured rather than assumed — a quantised
detector that had lost ten points of recall would still load, still run and
still draw boxes; it would simply miss more knives.

### The number to watch

**Recall 0.787.** Roughly one weapon in five is missed, and for knives closer
to one in four. Knives are thin, frequently occluded by the hand holding them,
and far more variable in shape than a handgun.

Precision (0.913) sits well above recall, which means the default confidence
threshold is tuned conservative. For SafeHer that is probably the wrong
direction — a missed knife is a woman with no alarm, while a false positive is
absorbed downstream by the weapon scorer's persistence rule and the fusion
engine's own smoothing. **Lowering the confidence threshold to trade precision
for recall is a deliberate product decision that has not been made yet.**

### Not yet wired up

Nothing in `lib/` loads this file. It is bundled and validated; there is no
inference code, no ONNX runtime dependency in `pubspec.yaml`, and
`weapon_score` still has no producer. The app does not claim otherwise —
`DetectionSources` reports what is genuinely detecting, and this is not part
of that yet.

### Attribution required

Both training sources carry conditions that travel with the weights:

- **Open Images V7** (Google) — annotations CC BY 4.0, images CC BY 2.0.
- **OD-WeaponDetection** (Universidad de Granada, ari-dasci) — **the repository
  states two different licences.** Its `LICENSE` file is CC BY 4.0; its README
  badge and text say CC BY-**SA** 4.0. ShareAlike would plausibly reach a
  dataset merged from it, and arguably these weights. Treated as ShareAlike
  until the maintainers confirm. **Resolve before any commercial release** —
  it is 5,078 of the 6,569 training images.

Training pipeline, dataset scripts and the full run live outside this repo at
`D:\SafeHer-ML\weapon_detection\`.
