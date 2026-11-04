# Evaluation figures

A visual record of the model evaluation, generated 2026-11-04 from the
artifacts that ship. Every figure here is reproducible; none of it is a
screenshot of a session.

Read `../../MODEL_TEST_REPORT.md` §13 for the numbers these figures draw, and
`MANIFEST.json` for the artifact hash, test-split size and per-image detections
behind them.

## Two kinds of file, and the difference matters

**Measurement** — computed over the whole test split. These *are* the result,
drawn:

| File | What it shows |
|---|---|
| `precision_recall_curve.png` | PR curve per class. mAP@0.5 0.907, pistol 0.932, knife 0.882 |
| `f1_vs_confidence_curve.png` | F1 across the confidence range |
| `precision_vs_confidence_curve.png` | Precision across the confidence range |
| `recall_vs_confidence_curve.png` | Recall across the confidence range |
| `confusion_matrix.png`, `confusion_matrix_normalised.png` | Where the errors land |
| `benchmark_conformance.png` | All six model/condition pairs against their SRS targets |
| `audio_threshold_sweep.png` | Why no decision threshold reaches the audio benchmark |
| `glove_gate_cascade.png` | What each shipped glove gate costs in recall and buys in false positives |
| `figure_data.csv` | The numbers behind the three charts above, as a table |

Computed over all **658 test images / 783 instances** (weapon), **714 held-out
clips** (audio), **431 windows** (glove). Nothing in them is a selected example.

**Illustration** — `annotated_detections/` and `val_val_batch*.jpg`. These show
what a detection looks like; they are **not a metric** and must never be
captioned as one. Twelve pictures cannot establish a rate.

## How the illustration sample was chosen

Every `STRIDE`-th image of the sorted test-split listing, not hand-picked, drawn
at the confidence floor the app actually applies (**0.55**) rather than at a
flattering low threshold. The sample therefore includes what the model gets
wrong:

- **11 of 12** produced a correct detection, 0.60–0.93 confidence.
- **`test_000000_e0dc90a20648d735.jpg` produced nothing.** Its ground-truth
  label is a knife occupying about 3.4% of the frame in the top-right corner.
  The model did not reach the floor on it. That is a real false negative and it
  is kept in the sample deliberately — a figure set that only shows successes
  would be worth nothing as evidence.

The `val_val_batch*_pred.jpg` files pair with `val_val_batch*_labels.jpg`:
predictions beside ground truth for the same batch, drawn by ultralytics during
the validation pass.

One incidental confirmation: detections are labelled `pistol` and `knife`
rather than `class 0` / `class 1`, which shows the class-name metadata fix
recorded in the report is live in the shipped `.tflite`.

## What these figures do not show

**No hardware was involved.** No weapon was held in front of the real glasses
camera, no speech went through the real phone microphone, and no alert was
dispatched. These are model-level results on held-out data. The system-level
claim — that this assembly detects threats in the field — is not supported by
anything in this folder, and the report says so in §14.

The weapon figures are drawn on public-dataset images (Open Images V7 and
OD-WeaponDetection), not on footage from the SafeHer glasses.

## Regenerating

```
python scripts/make_evidence_figures.py   # validation plots + annotated detections
python scripts/make_charts.py             # the three summary charts
```

Both read the artifacts straight from the repository and the locked test splits
from `D:\SafeHer-ML\`, and both record the artifact SHA-256 they measured.
