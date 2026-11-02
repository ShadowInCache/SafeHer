# SafeHer — Model Test Report

**Date of report:** 2 November 2026
**Measurements generated:** 27 October – 2 November 2026
**Machine-readable record:** [`docs/model_evaluation_results.json`](model_evaluation_results.json) (schema 1.0)

SafeHer is a wearable personal-safety system: an ESP32 glove, ESP32-S3 glasses, a
Flutter application and a FastAPI backend. Five machine-learning artifacts
contribute to its threat assessment. This report states what each one was
measured to do, on what data, and what the measurement does not establish.

---

## 1. Scope

### 1.1 What was tested

Every figure in this report comes from running a shipped artifact over data that
artifact did not train on, and comparing its output against ground-truth labels.
Where a figure could not be obtained that way, it is graded accordingly and
labelled as not tested.

### 1.2 What was not tested

This is **model-level accuracy testing, not system or integration testing.** The
distinction is load-bearing and is stated here rather than in a footnote:

- **No run on the physical devices.** No weapon was held in front of the real
  glasses camera. No speech went through the real phone microphone.
- **Audio has never produced a reading on hardware.** The APK carrying the
  foreground-service microphone fix has not been installed, on any build, in any
  journey.
- **No alert was dispatched in any test.** No false positive was observed end to
  end. The auto-SOS exposure in §5 is arithmetic over measured scores, not a
  reproduced failure.
- **Latency, battery, thermal behaviour and frame rate on the devices are
  unmeasured.**
- **The emotion model was not re-measured** (§4.5), and cannot be: its three
  test corpora are no longer on disk. Its 65.5% is now labelled in source as the
  training run's own unverified figure.

The accuracy figures are real. Operational consequences drawn from them are
grounded predictions, and are marked as such.

---

## 2. Method

### 2.1 Evidence grades

Every result in the JSON record carries one of these grades. They exist because
the useful question about a number is not whether it is high but what would have
to be true for it to be wrong.

| Grade | Meaning |
|---|---|
| `measured` | Real inference over real data with real ground-truth labels. Reproducible. |
| `simulated` | Real inference, but over inputs synthesised to stand in for data that was unavailable. Describes the model under that approximation, not the field. |
| `derived` | Not an observed event. Measured values fed through formulas read from the deployed source. Sound only insofar as those formulas are what runs. |
| `documented_not_verified` | Copied from a code comment or training log and **not** re-measured here. |
| `measured_but_methodologically_weak` | Real inference over inputs that cannot support the conclusion drawn. Retained with the reason it fails, so the mistake is not repeated. |

### 2.2 Operating points, not sweeps

Detector metrics are reported at the confidence floor the application actually
applies (`WeaponScorer.confidenceFloor = 0.55`), not at the mAP sweep. A
detection below that floor never reaches the threat signal, so a swept average
describes a system that does not exist.

Likewise the audio classifier is scored on the rule that ships —
`elevated = P(threat) + P(distress) >= 0.5` — and not on argmax, which gives
different and inapplicable numbers.

### 2.3 Environment

```
python 3.12.5          onnxruntime 1.29.0      ai_edge_litert 2.3.0
numpy  2.3.5           pillow 12.3.0           platform win32
execution provider: CPUExecutionProvider
```

Artifacts are pinned by SHA-256 in the JSON record, so a silent model swap
invalidates the file rather than quietly invalidating the numbers.

---

## 3. Summary of results

| Artifact | Task | Headline | Verdict |
|---|---|---|---|
| `weapon_yolov8n_fp16.tflite` | Weapon detection, phone | P 0.932 / R 0.805 @0.55 | Pass on the task measured |
| `weapon_yolov8n_int8.onnx` | Weapon detection, server | P 0.931 / R 0.798 @0.55 | Pass on the task measured |
| `phrase_classifier.json` | Audio phrase classification | Acc 0.831 / R 0.883 (degraded ASR) | Pass; verified against APK bytes |
| `glove_5class_v7…xgboost.json` | Motion classification | Falls 94.3% (CI 81.4–98.4) | Pass on detection, qualified on false alarms |
| `emotion_mobilenetv3_fp16.onnx` | Facial expression | 65.5%, **not verified** | Out of scope for safety claims |

**The principal finding of this evaluation is not in that table.** It is that the
weapon detector fires on **20.3% of real weapon-free frames** at its deployed
floor, which no accuracy metric above reveals (§5).

---

## 4. Per-artifact results

### 4.1 Weapon detector — phone (`weapon_yolov8n_fp16.tflite`)

YOLOv8n, 2 classes, fp16. LiteRT via the `ultralytics_yolo` plugin. Input
`[1,640,640,3]` NHWC; output `[1,6,8400]`; boxes `cx cy w h` normalised 0–1;
letterbox to 640 with pad 114, divide by 255.

The asset is 6,129,672 bytes: a 6,129,244-byte graph plus a 428-byte appended
class-name archive added on 2026-11-02 (§7.2). Every figure below was measured
on that graph, whose SHA-256 is unchanged by the addition.

**Test set:** 658 held-out images, 783 instances (pistol 433, knife 350), match
IoU 0.5. Instance counts reconciled exactly against the label files, which
validates the ground-truth parsing.

| Confidence | Pistol P/R | Knife P/R | Overall P/R/F1 |
|---|---|---|---|
| 0.35 | 0.9422 / 0.8661 | 0.8468 / 0.8371 | 0.8978 / 0.8531 / 0.8749 |
| 0.45 | 0.9529 / 0.8406 | 0.8750 / 0.8200 | 0.9169 / 0.8314 / 0.8721 |
| **0.55 (deployed)** | **0.9673 / 0.8199** | **0.8900 / 0.7857** | **0.9320 / 0.8046 / 0.8636** |
| 0.65 | 0.9742 / 0.7852 | 0.9039 / 0.7257 | 0.9429 / 0.7586 / 0.8408 |

**Verdict:** pass on the task measured. fp16 quantisation cost nothing; this
artifact is marginally stronger than the int8 one.

### 4.2 Weapon detector — server (`weapon_yolov8n_int8.onnx`)

YOLOv8n, 2 classes, int8, 3,355,730 bytes. Input `[1,3,640,640]` NCHW; boxes in
640-pixel space.

At the deployed 0.55 floor: pistol 352 TP / 12 FP / 81 FN (P 0.9670, R 0.8129);
knife 273 / 34 / 77 (P 0.8893, R 0.7800); overall 625 / 46 / 158 (P 0.9314,
R 0.7982, F1 0.8597).

**Verdict:** pass on the task measured. int8 quantisation cost nothing
measurable.

### 4.3 Audio phrase classifier (`phrase_classifier.json`)

TF-IDF (word n-grams unioned with `char_wb` n-grams) into logistic regression,
7,611 features, 387,427 bytes, executed in pure Dart on the phone. The
transcript is classified and discarded. **Byte-identical to the training
export**, so these figures describe the bytes in the APK.

**Test set:** 714 clips, held out **by phrase** rather than by clip, so every
voice saying a given phrase falls on the same side of the split.

| Condition | Accuracy | Recall | Precision | Specificity | 3-class acc | Missed | False alarms |
|---|---|---|---|---|---|---|---|
| Clean ASR | 0.9202 | 0.9675 | 0.9141 | 0.8333 | 0.8571 | 15/462 | 42/252 |
| **Degraded ASR (realistic)** | **0.8305** | **0.8831** | 0.8589 | **0.7341** | 0.7423 | 54/462 | 67/252 |

The degraded figure reproduces the published 0.8305 / 0.8831 exactly, confirming
the export is lossless.

**Specificity 0.7341 is the significant number.** Roughly a quarter of ordinary
speech reads as elevated, and audio ≥ 0.50 is what opens the camera — which is
what makes the weapon false-positive path in §5 reachable in normal use.

**Can the threshold fix it?** No. The threshold was swept against a target of
specificity ≥ 0.85 at recall ≥ 0.80:

| Threshold | Accuracy | Recall | Specificity | Missed | False alarms |
|---|---|---|---|---|---|
| 0.40 | 0.7885 | 0.8961 | 0.5913 | 48 | 103 |
| **0.50 (deployed)** | **0.8305** | **0.8831** | 0.7341 | 54 | 67 |
| 0.60 | 0.8193 | 0.8398 | 0.7817 | 74 | 55 |
| 0.70 | 0.7899 | 0.7511 | 0.8611 | 115 | 35 |
| 0.80 | 0.7871 | 0.7078 | 0.9325 | 135 | 17 |

No threshold satisfies both constraints. The lowest reaching 0.85 specificity is
0.70, costing recall 0.7511 — missing 115 elevated clips to avoid 35 false
alarms, the wrong trade for a safety feature. **The corpus is the cause, not the
constant.** Peak accuracy sits at the deployed 0.50, so the constant is well
chosen for accuracy; accuracy is simply the wrong objective, being dominated by
462 elevated clips against 252 normal.

**Root cause.** The written corpus runs roughly 226 elevated phrases to 128
normal. "Normal" means everything a person might say that is not an emergency —
almost everything anyone ever says — and it had the smallest share. Real speech
is overwhelmingly ordinary; the training prior was the opposite.

**Disclosed limitations.**

- The corpus is **synthetic TTS speech** (neural voices reading calmly), not real
  distress speech. Recording real distress audio was deliberately descoped.
  These figures describe the classifier on synthesised phrasings and their
  degraded variants, **not on a frightened human voice.**
- Specificity rests on only **18 distinct held-out normal phrases**
  (252 clips = 18 phrases × 14 voices). One of them — *"Can you help me with
  this"* — is a benign sentence containing a distress trigger, so the failure
  mode is real rather than hypothetical. But 18 phrases is a narrow basis for a
  claim about ordinary speech.
- Gibberish scores above the camera trigger: `"zxqv blorptang mimsy"` gives
  elevated 0.594. The `char_wb` vectoriser produces signal from unseen character
  patterns — which is exactly what noisy ASR emits.

### 4.4 Glove motion classifier

XGBoost on the ESP32 over MPU6050 accelerometer and gyroscope windows.
100 Hz, 100-sample windows, 50-sample overlap, a reading every 0.5 s.

**Reproduction check:** 431 windows, accuracy 0.8886, macro-F1 0.9001 — an exact
match to the published figures, confirming the shipped model is the measured
model.

#### Gate cascade

Each stage is a gate that actually ships. Cross-validated over the development
set:

| Stage | Normal-window FP rate | Falls detected (of 35) | Normal recordings alarming (of 63) |
|---|---|---|---|
| 1 — raw argmax | 0.1398 | 35 | 45 |
| 2 — + firmware confidence gate | 0.0811 | 34 | 32 |
| 3 — + firmware SUDDEN debounce | 0.0554 | 34 | 25 |
| 4 — + app `GloveConfirmation` | **0.0174** | **33** | **9** |

The cascade is monotonic: each gate removes false positives faster than it
removes falls.

#### Statistical power

The locked test split holds only 5 FALL and 7 NORMAL recordings, which cannot
support a claim. A further 208 recordings existed in the dataset as training
material and had never been scored as evaluation. Recording-level
cross-validation makes them usable — every recording gets a prediction from a
model that never saw it.

**Protocol:** `StratifiedGroupKFold(5, shuffle=True, random_state=42)`,
`group=recording_id`, the locked 22 excluded from all folds. 208 recordings,
3,585 windows.

Grouping by recording is not a detail. Windows overlap by 50 of 100 samples, so
a random window split would place near-identical windows from one recording on
both sides of a fold and report a fantasy.

| Measure | Value | 95% CI |
|---|---|---|
| Fall detection | 33/35 = **94.3%** | 81.4 – 98.4% |
| Normal recordings raising a confirmed alert | 9/63 = **14.3%** | 7.7 – 25.0% |
| Gated false-positive window rate | 1.74% | — |

**Agreement with the locked split.** The locked 22 gave 5/5 falls and 1/7
normals — 14.3%, the same point estimate as 9/63 here — and the gated window
rate agrees too (2.0% locked against 1.7% cross-validated). Two near-independent
estimates landing together is stronger evidence than either alone.

#### Solo auto-SOS exposure

14.3% of normal recordings raise a fully confirmed glove alert. The question that
decides whether that matters: does such an alert, with nothing corroborating it,
reach `DEFAULT_THREAT_THRESHOLD = 0.75`?

**Yes, in 3 of 63 normal recordings — 4.76% (95% CI 1.63–13.09%).** All three
were classified FALL, with peak single-reading scores 0.981, 0.952 and 0.959.

Three mechanisms combine, and none of them is a bug:

1. `fuse()` renormalises over *reporting* signals, so a solo glove reading **is**
   the fused score.
2. `smooth()` takes the first posted reading as-is.
3. On a NORMAL window the pipeline calls `retractGlove()`, after which
   `buildPayload()` returns null and nothing is posted — so the calm windows
   between false hits do not decay the EMA.

**A structural protection was found and is now pinned by tests.** Only FALL can
trigger alone. The weight table maps FALL→danger→1.0, SUDDEN_MOVEMENT→0.7,
SHAKING/TWISTING→0.3, so the six non-FALL false-alarming recordings peak at
0.676, 0.609, 0.275, 0.267 and 0.189 — all below 0.75. SUDDEN_MOVEMENT would
need confidence above 1.07 to trigger unaided. The exposure is entirely a
false-FALL problem.

**A correction made during this evaluation.** The harness had modelled the app
gate as 2 consecutive hits. The deployed `GloveConfirmation` is density-based —
3 hits within a rolling 5 s, where an intervening NORMAL does not reset the
count. The consecutive rule had been replaced after hardware observation (the
glove alternates FALL, NORMAL, FALL, so requiring consecutive hits withheld every
reading and nothing reached fusion). The previously published gated
false-positive rate of 1.4% therefore described a gate that is no longer
deployed; re-measured against the real gate it is 2.0%, with 5/5 falls still
detected. Caught by the drift guard in `tests/test_glove_model_metrics.py`.

**Disclosed limitation.** These 208 recordings are one data-collection campaign.
Cross-validation removes the sample-size objection, not the diversity
objection — it cannot stand in for falls recorded by different people, on
different floors, with different glove fits.

### 4.5 Emotion classifier (`emotion_mobilenetv3_fp16.onnx`)

**Not verified. Its stated 65.5% must not be quoted as a tested figure.**

The accuracy originates in a code comment in
`fastapi_app/services/threat_models.py`. Its provenance was upgraded during this
evaluation from a comment to a training artifact
(`D:/SafeHer-ML/emotion_recognition/runs/metrics.json`, which also records
`best_val_accuracy 0.6392`), but it could not be re-measured: the test corpora
(AffectNet, FER+, RAFDB) are not present — the dataset directories exist and are
empty.

Documented, unverified per-class recall: happy 0.818, sad 0.839, disgust 0.764,
surprise 0.687, angry 0.591, **fear 0.470**, neutral 0.460.

The model is **barred from the fused score** by design and contributes only
supporting context on the incident record. That bar is enforced by
`tests/test_fusion_architecture.py`. Its accuracy therefore gates no alarm, which
is why an unverified figure here is a disclosure problem rather than a safety
one.

**One export-fidelity check is retracted as evidence.** fp16 was compared against
fp32 over 40 seeded pseudo-random inputs: max probability divergence 0.003786,
0/40 argmax disagreements. This project has already been burned by exactly that
test — INT8 quantisation once took this classifier from 65.5% to 16.9% while the
random-tensor check reported 100% agreement, because random noise does not
exercise the activation ranges quantisation distorts. The check is retained in
the record with the reason it fails, not deleted.

---

## 5. Principal finding: weapon false positives

### 5.1 Why this was investigated

**All 7,539 images** in the weapon dataset's train, val and test splits contain a
weapon. **There are zero background images.** The precision in §4.1 is therefore
*precision given a weapon is present*, and nothing in the dataset measures what
the detector does on the ordinary frames the glasses spend almost all their time
looking at.

### 5.2 Hard-negative crops — 3,218 images

Source: OD-WeaponDetection "Weapons and similar handled objects", built by its
authors as hard negatives — objects held in the hand that are not weapons.
Composition: smartphone 1,182, wallet/purse 813, banknote 777, card 446. Any file
whose name marks a weapon in the source image was dropped, so every image scored
is weapon-free **by construction**. Zero basenames shared with any of the 7,539
training images.

Fraction of weapon-free images producing at least one detection:

| Confidence | Smartphone | Wallet/purse | Banknote | Card | All |
|---|---|---|---|---|---|
| 0.35 | 0.310 | 0.394 | 0.194 | 0.231 | 0.292 |
| 0.45 | 0.240 | 0.295 | 0.125 | 0.137 | 0.212 |
| **0.55 (deployed)** | 0.173 | 0.207 | 0.077 | 0.083 | **0.146** |
| 0.65 | 0.120 | 0.129 | 0.042 | 0.054 | 0.094 |
| 0.75 | 0.081 | 0.084 | 0.015 | 0.018 | 0.057 |

At the deployed floor: 248 false detections claiming *pistol*, 223 claiming
*knife*. 2,748 of 3,218 images (85.4%) never reached 0.55 at all — the errors are
concentrated, not diffuse. Worst cases include a wallet at 0.929 confidence as a
pistol and a smartphone at 0.904 as a knife.

### 5.3 Real full frames — 2,072 images

The crop measurement carried a caveat that it could not speak for real frames,
with a guess that the rate there was "probably lower". **That guess was wrong in
direction**, which is recorded here because the correction matters more than the
original estimate.

OD-WeaponDetection also ships 5,859 real 1920×1090 frames labelled over six
classes. Selecting frames that carry a hand-held object and **no** pistol and
**no** knife gives real full frames that are weapon-free *by annotation* rather
than by assumption. 2,072 qualify. None appears in any training split, checked by
stem and by embedded name.

**20.3% of real weapon-free full frames produce a weapon detection at the
deployed floor** — against 14.6% on crops. The crop proxy understated the
problem.

| Object | Frames | False positives | Rate |
|---|---|---|---|
| Wallet/purse | 601 | 182 | 0.303 |
| Smartphone | 715 | 131 | 0.183 |
| Banknote | 477 | 68 | 0.143 |
| Card | 279 | 40 | 0.143 |

By confidence: 0.358 @0.35 → 0.280 @0.45 → **0.203 @0.55** → 0.137 @0.65 →
0.069 @0.75. At the deployed floor, 300 detections claimed *pistol* and 125
claimed *knife*. 1,651 of 2,072 frames (79.7%) never reached it.

### 5.4 Does frame-to-frame voting suppress these? — `simulated`

> ### ⚠ The numbers in this section model the wrong window — retracted 2026-11-03
>
> This probe used **window 5**, taken from `WeaponScorer`'s own default. A
> wiring audit found that the default is not what runs: `ThreatPipeline` builds
> `WeaponDetectionService` without passing a scorer, so that service's
> `_defaultScorer()` applies — **window 15, frameTimeout 5 s**. Persistence is
> `hits / window`, so every score below is computed with a denominator three
> times too small.
>
> **Direction of the error: this section overstates the exposure.** Under the
> deployed window the probe's worst case — a wallet at 0.908 on 5 of 5
> frames — scores 0.908 × 5/15 ≈ 0.30, not 0.908, and lands below the 0.55
> floor rather than above the 0.75 alarm threshold.
>
> The headline percentages (13.8% ≥ 0.55, 4.2% ≥ 0.75) are therefore **not
> valid for the deployed configuration and must not be quoted.** They are left
> in place, rather than deleted or quietly recomputed, because the correction
> favours the system and that is exactly when a number most needs to stay
> auditable.
>
> **What survives is the mechanism, which is the part that mattered:** the
> errors are *correlated*, not independent, so the window vote does not
> attenuate them the way an independence assumption predicts. That finding does
> not depend on the window size. What it predicts at window 15 is unmeasured,
> because modelling a 15-frame window needs 15 jittered frames per still and
> this probe generated 5. See §11.
>
> Scaling 5 frames to 15 by arithmetic would assume the independence this
> section exists to disprove, so it is not done here.

`WeaponScorer` scores `meanConfidence × (hits/window)`, so one bad frame in five
becomes 0.18 **at the default window of 5**. **That defence assumes false
positives are independent between frames.** This tests whether they are.

Method: each still was expanded into 5 frames by jittering it the way a camera
differs frame to frame — translate ±3%, scale ±3%, brightness ±8%, fresh JPEG at
quality 70–90 — then the real `WeaponScorer` arithmetic was applied. 500 images
(300 smartphone, 200 wallet), seed 20261027, window 5, floor 0.55.

**Result: bimodal, not independent.**

| Hits in window | 0/5 | 1/5 | 2/5 | 3/5 | 4/5 | 5/5 |
|---|---|---|---|---|---|---|
| Share | 0.696 | 0.066 | 0.048 | 0.038 | 0.034 | **0.118** |

When the model is wrong about an object it is **reliably** wrong, so five
agreeing frames score the full confidence and the window vote passes the error
through at full strength. 13.8% of objects reach a weapon score ≥ 0.55 and 4.2%
reach ≥ 0.75; the worst was a wallet at 0.908 on 5 of 5 frames.

**This is the weakest link in the chain and says so.** The frames are
synthesised. Real hand motion over a second is larger than the jitter applied,
so this measures stability of the error under small perturbation, not behaviour
on real glasses footage. It is the first thing real footage should replace.

### 5.5 Auto-SOS exposure — `derived`

> **Affected by the §5.4 retraction.** This chain is arithmetic over §5.4's
> weapon scores, so the weapon-driven path through it inherits the wrong
> window and overstates the exposure. The glove and audio paths are unaffected,
> as is the §5.5 finding that a *solo* signal is the fused score — that follows
> from `fuse()` renormalising, not from any window.

**No alert was dispatched in any test.** This is arithmetic over measured scores
using constants read from the deployed source.

Constants: `DEFAULT_THREAT_THRESHOLD 0.75`, `EMA_ALPHA 0.30`,
`SOLO_SIGNAL_RETENTION 0.50`, camera dwell 45 s, signal max age 10 s, analyze
post interval 1 s.

The chain:

1. `fuse()` renormalises over reporting signals, so a weapon reading with nothing
   else reporting **is** the fused score. The solo floor of 0.50 × max is a
   floor and cannot pull it down.
2. The camera opens on audio ≥ 0.50 or glove ≥ 0.70, then stays open for a 45 s
   dwell. The audio signal that opened it goes stale after 10 s and is dropped
   from the payload — so roughly **35 s of weapon-only reporting is the normal
   case**, not an edge case.
3. Audio specificity on degraded ASR is 0.7341, so about a quarter of ordinary
   speech suffices to open the camera.
4. 4.2% of weapon-free hand-held objects sustain a weapon score ≥ 0.75.
5. `auto_sos` compares the EMA-smoothed score against 0.75.

**21 of 500 objects (4.2%) would eventually cross the threshold.** Fastest: 5
posts, 5 seconds (a wallet scoring 0.908). Median: 7 posts. Those figures seed
the EMA from 0.0, which is the harder case — `smooth()` takes the first reading
of a journey as-is, so a cold start would cross on post one.

**Conclusion:** a phone or purse in view during an already-elevated moment could
drive an automatic SOS with no weapon present. The only mitigation in the path is
`kDefaultCountdownSeconds = 5`, a cancellable countdown. Grounded prediction, not
an observed failure.

### 5.6 Root cause

**The training set, not the threshold.** A YOLO model trained without background
images has never been shown what "no weapon" looks like.

Raising `confidenceFloor` to 0.75 cuts the false-positive rate to 5.7% but drops
recall to 0.6616 — rejected as the wrong trade.

---

## 6. Remediation attempts

Work undertaken after the measurements above, on the principle that for a patent
filing the only honest route to a better number is to fix the model and
re-measure, not to re-frame the measurement. **Four attempts; one succeeded.**

### 6.1 Weapon 2-class + background images — REJECTED

Fine-tuned with 542 background frames carrying **empty** label files, the
standard Ultralytics remedy.

Hypothesis confirmed: holdout false positives fell **20.6% → 4.7%**, a 4.4×
reduction. But knife precision collapsed **0.8900 → 0.6898** and overall recall
fell to 0.7778.

Diagnosis: an empty label file tells the model only that a phone, wallet,
banknote or card is *nothing*. Those are flat, hand-held, elongated objects —
which is also what a knife is.

### 6.2 Weapon 6-class — SUCCEEDED

Instead of labelling the distractors "nothing", label them as what they are:
`pistol, knife, smartphone, monedero, billete, tarjeta`. Collapse to
pistol/knife at inference by **argmax over all six**, keeping the box only when
the argmax is a weapon.

**Single-variable design.** Built from the same dataset by changing **only the
labels** — identical images (hard-linked), identical splits, identical
membership. Recipe copied verbatim from the shipped model's `args.yaml` (same
seed 20260830, lr0 0.01, 120 epochs, patience 30, batch 8, mosaic 1.0,
close_mosaic 10, shear 3.0, same `yolov8n.pt` init). The dataset is the only
variable, which is what makes the result attributable — and is precisely what
§6.1 lacked.

**Leakage control.** The 1,385 held-out negatives come from the same source
directory that supplies the 6-class boxes, so building naively would have
trained on them and destroyed the only honest false-positive comparison in this
evaluation. The build asserts non-membership per image. *The first version of
that assertion was broken* — negatives are renamed `bg_<type>_<original>`, so it
compared prefixed names against raw stems, matched nothing, and would have passed
vacuously while a leak went through. Fixed before the build ran.

**Results at the deployed 0.55 floor:**

| Metric | Shipped | 2-class + bg | **6-class** | Target | Met |
|---|---|---|---|---|---|
| Pistol precision | 0.9673 | 0.9590 | 0.9597 | — | — |
| Pistol recall | 0.8199 | 0.8106 | 0.8245 | — | — |
| Knife precision | 0.8900 | 0.6898 | **0.8893** | ≥ 0.89 | ✗ by 0.0007 |
| Knife recall | 0.7857 | 0.7371 | 0.7800 | — | — |
| Overall precision | 0.9320 | 0.8230 | 0.9278 | — | — |
| Overall recall | 0.8046 | 0.7778 | **0.8046** | ≥ 0.80 | ✓ |
| Holdout FP rate | 0.2060 | 0.0470 | **0.0253** | ≤ 0.02 | ✗ |

An **8.1× reduction** in false positives, at recall identical to the shipped
model to four decimals. Both target misses are narrow.

**The mechanism was made visible rather than inferred.** On the 1,385 held-out
negatives the model emits **10,960 boxes whose best class is a distractor**; on
the 658 weapon test images it emits **zero**. The model recognises phones,
wallets, banknotes and cards as what they are, and does not apply that
suppression to frames containing real weapons — which is why the false-positive
reduction costs no recall.

**Training run.** 120/120 epochs; best checkpoint epoch 96; epochs 97–120 never
beat it. The run was interrupted twice by unexpected machine shutdowns
(Kernel-Power 41, no bugcheck), the second of which corrupted `last.pt` —
`torch.load` raised `KeyError: 'storages'` and the file was not a valid zip,
because it was mid-write when power cut. `best.pt` survived and the run was
resumed from it. Completion was achieved by adding two **time-only** levers
through Ultralytics callbacks — a 2 s pause above 72 °C and a wait for 66 °C
between epochs — which touch no gradients, data order, seeds, learning rate or
batch composition. 437 of 493 thermal readings sat above the soft limit;
16.4 minutes paused in total.

Because completion stripped `best.pt` from 17.51 MB to 5.95 MB by discarding
optimiser state, the evaluation was **re-run from the final artifact** rather
than assuming the weights matched. It reproduced every figure identically.

**Per-class validation (1,603 val images)** explains why the 6-class mean was
uninformative mid-run:

| Class | mAP50 | Precision | Recall |
|---|---|---|---|
| knife | 0.919 | 0.884 | 0.859 |
| pistol | 0.881 | 0.873 | 0.817 |
| monedero | 0.791 | 0.814 | 0.667 |
| tarjeta | 0.772 | 0.773 | 0.750 |
| smartphone | 0.770 | 0.673 | 0.780 |
| **billete** | **0.461** | 0.631 | **0.303** |

The weapon classes are the *strongest* in the model; the 6-class mean of 0.766 is
dragged down by `billete`. The aggregate was consistent with both healthy and
degraded weapon classes, so it discriminated nothing.

**Residual risk.** `billete` is the one distractor the model largely fails to
name (recall 0.303, 158 training instances). Suppression only occurs when the
distractor *wins* the argmax, so a banknote the model fails to name can still be
called a weapon. Banknote frames were already the second-worst negatives for the
shipped model, making them the most likely source of the remaining 2.5%.

#### Deployable artifact: fp16 TFLite

The figures above are from the ONNX artifact. The application loads TFLite, so
the model was converted and **re-measured on the same 2,043 images, through the
same decode code** — only the inference backend was replaced, so any difference
is the conversion rather than new analysis code.

Route: PyTorch → ONNX (opset 13, slimmed) → SavedModel via `onnx2tf` →
fp16 TFLite via TensorFlow's own converter. Ultralytics' exporter refuses to run
on Windows, so this takes the same path by hand. fp16 with **fp32 in and out**,
because the GPU delegate wants an fp32 entry point and `onnx2tf`'s own
`*_float16.tflite` has an fp16 *input* tensor. Boxes are divided by 640 to match
Ultralytics' normalised convention. Artifact: 6.13 MB.

| Metric @0.55 | ONNX int8 | **TFLite fp16** | Δ |
|---|---|---|---|
| Pistol P / R | 0.9597 / 0.8245 | 0.9596 / 0.8222 | −0.0001 / −0.0023 |
| Knife P / R | 0.8893 / 0.7800 | 0.9007 / 0.7771 | +0.0114 / −0.0029 |
| Overall P / R | 0.9278 / 0.8046 | 0.9331 / 0.8020 | +0.0053 / −0.0026 |
| Holdout FP (1,385 negatives) | 0.0253 | 0.0260 | +0.0007 |
| Distractor boxes suppressed | 10,960 | 10,938 | −22 |
| Distractors suppressed on weapon test split | 0 | 0 | — |

**The conversion preserved the model.** Every metric moved by less than 0.012
against a 0.03 tolerance, and the suppression still never fires on frames
containing a real weapon.

> **Knife precision reads 0.9007 here, which clears the ≥0.89 target the ONNX
> artifact missed by 0.0007. That is not recorded as the target being met.** The
> difference is 4 fewer false positives out of roughly 300 — quantisation noise,
> not the approach performing better than measured. The target line simply falls
> between two artifacts that differ by less than their own measurement noise.
> The honest statement is that knife precision sits *at* the 0.89 line. Reading a
> +0.011 conversion difference as clearing a target would be re-framing a
> measurement rather than improving a model.

**Independent cross-check.** The decode above multiplies boxes by 640 because the
graph divided by 640 — correct, but circular as evidence, since the same
assumption is on both sides. The artifact was therefore also validated through
**Ultralytics' own LiteRT backend**, which applies the same denormalisation the
Flutter plugin does:

| | mAP@0.5 | mAP@0.5:0.95 | pistol | knife |
|---|---|---|---|---|
| 6-class TFLite fp16 | **0.8938** | 0.6260 | 0.9313 | 0.8563 |

For comparison, the shipped 2-class TFLite measures mAP@0.5 0.9056. A convention
mismatch does not produce a slightly lower number — it produces **0.0**, as this
project has already seen once on a provably healthy model. 0.8938 through
Ultralytics' own code is the evidence that the box convention is right.

**A compatibility defect found by that cross-check.** The first attempt failed
with `KeyError: 'batch'` *after* loading the model for inference. The two
consumers of the same metadata archive want different keys: the Flutter plugin
reads `task`/`description`/`stride`/`channels`/`end2end`/`imgsz`/`names`, while
Ultralytics' Python `AutoBackend` additionally indexes `metadata["batch"]`
unconditionally. Without it, the artifact is one the phone reads perfectly and
`YOLO(path).val()` refuses to open — so anyone reaching for the standard
validation tool would conclude the export was broken. The metadata now carries
both key sets, at a cost of 14 bytes.

**Status: strong candidate, not shipped.** The export is now measured and the
§7.2 metadata defect is fixed, so what remains before shipping is a decision and
a device test, not an open technical question. See §7 and §11.

### 6.3 Audio corpus rebalance — REJECTED by the project's own gate

| Metric (degraded ASR) | Shipped | Candidate | Δ |
|---|---|---|---|
| Accuracy | 0.8305 | 0.8350 | +0.0045 |
| Recall | 0.8831 | 0.8460 | **−0.0371** |
| Specificity | 0.7341 | 0.8130 | **+0.0789** |

Clean accuracy rose 3.5 points (0.905 → 0.940), which is the rebalancing
working.

`train_robust_classifier.py` states the ship gate in its own docstring: ship only
if degraded accuracy **and** recall both improve — a gate written that way
because one watching recall alone had approved a worse model once before. Recall
falls, so the gate fails. **The shipped `phrase_classifier.json` is untouched**
and remains the measured model.

Two caveats recorded against the candidate's own figures: the script's internal
baseline (0.814/0.818/0.806) is the wrong comparison, since the question is
whether to replace the *shipped* model; and selecting the best of 12
configurations on the same 714 clips makes 0.835 optimistically biased.

Accepting this trade — +0.079 specificity for −0.037 recall — remains open, but
would be a **conscious override of a pre-committed gate** and must be recorded
as one.

### 6.4 Glove statistical power — SUCCEEDED

Reported in §4.4. Seven times the fall evidence and nine times the normal
evidence, with confidence intervals, and both estimates agree with the locked
test split.

---

## 7. Integration defects found

Six findings sit in the code around the models rather than in them —
in the path from a model's output to the alarm, in the evidence handling beside
it, and in the tests meant to watch both. **None is visible in any accuracy
metric**, which is the point of this section: the models were not the risk.

They are not of equal weight. §7.1–§7.3 could each have affected a real
incident; §7.4 concealed whether anything worked; §7.5 is hygiene, recorded
because it is the same mistake in miniature — a handler that catches an
exception class the code cannot raise. §7.6 is not a defect at all but an
undecided consequence of three numbers chosen independently, and it is the only
one here left open.

### 7.1 The scorer counted every class as a weapon

`UltralyticsWeaponDetector.parseDetections` accepted every detection whatever its
label, and `WeaponScorer.observe` filtered on `confidence >= confidenceFloor` and
nothing else. **Neither looked at the class.**

Harmless for the shipped 2-class model, where both classes are weapons. For the
6-class model it is the opposite of harmless: all 10,960 distractor boxes would
have counted as weapon hits, and the model built to cut false positives would
have multiplied them.

**Fixed** with `WeaponDetection.nonWeaponLabels` and an `isWeaponClass`
predicate, applied in `WeaponScorer.observe` — the single choke point both
detectors funnel through, since `UltralyticsWeaponDetector` and
`RemoteWeaponDetector` each build `WeaponDetection` from their own wire format,
so filtering in either one would have left the other open.

Deliberately a **reject** list, not an allow list. An allow list of
`{pistol, knife}` would mean a plugin upgrade that renamed its classes silently
produced "no weapons anywhere" — the failure mode where a safety feature keeps
running and always reports calm. An unrecognised label still counts.

### 7.2 The model carried no class names — so §7.1 would have governed nothing

**Found, then fixed.** The defect is described first and the fix recorded at the
end of this section.

The bundled `.tflite` contained **no class-name metadata**: no "pistol", no
"knife", no `TFLITE_METADATA` — only TensorFlow's own conversion record. The
hand-built converter never wrote any, because Ultralytics' exporter does that and
it refuses to run on Windows.

`mobile/assets/models/weapon_labels.txt` does not cover this. Nothing on the
device reads it; its only reader is `fastapi_app/services/weapon_detector.py`, a
different code path. The file's existence is part of why the gap went unnoticed.

The plugin's fallback, from its own source:

```kotlin
// ultralytics_yolo-0.6.14 — Predictor.kt
return labels.getOrNull(index)?.takeIf { it.isNotBlank() } ?: "class $index"
```

So on a phone, detections arrived labelled `"class 0"`, `"class 1"`.

- **Shipped 2-class model:** survivable. Both classes are weapons, so the reject
  list's deliberate fail-open gave the right answer by the wrong route. One real
  consequence: an incident recorded `strongestLabel: "class 0"` rather than
  `"pistol"` — evidence attached to a real emergency not naming what was seen.
- **6-class model:** fatal. The reject list screens
  `{smartphone, monedero, billete, tarjeta}`; the plugin would hand it
  `{"class 2" … "class 5"}`. Nothing matches, every distractor counts as a weapon
  hit, and **all 10,960 suppressed boxes return** — while the filter, its tests
  and its documentation all look correct.

The metadata contract was read off the plugin's reader rather than guessed: a ZIP
appended at EOF holding one entry named `TFLITE_ULTRALYTICS_METADATA.json`, with
`names` as an index→name **object** (an array reads as absent), and a single
entry because the reader seeks to the *last* local file header.

#### Fix applied — 2026-11-02

Metadata is now attached to the shipped asset. **428 bytes appended**, read back
through the plugin's own algorithm as `['pistol', 'knife']`, interpreter still
loading, output `[1, 6, 8400]` unchanged. The same step is applied to the 6-class
artifact (§6.2).

Patching a safety-critical artifact needs more than the claim that trailing bytes
are inert, so that claim was measured. The original and patched files were run on
**9 identical fixed inputs** — eight seeded random frames plus one flat grey, since
noise alone is a weak exercise of a detector — and all 50,400 output values were
**bitwise identical** on every probe. The patch script aborts rather than
overwriting if a single bit differs, and the patched file's first 6,129,244 bytes
are byte-for-byte the original.

That is what lets the measurements in §4.1 stand unchanged: the graph's SHA-256
is the same hash that produced them. **The SHA-256 pin in
`tests/test_weapon_model_metrics.py` fired on the change, exactly as designed**
(*"the APK TFLite changed — re-measure before trusting this file"*). Bumping the
hash to make a red test green is the move this report exists to avoid, so the
pin was corrected instead of silenced: it now pins the **graph** — hash
unchanged from the measured run — and pins the whole file in a second test. The
two failures now say different things. A whole-file failure with the graph pin
intact means the metadata moved and no measurement is affected; a graph-pin
failure means the detector itself changed and every number here is stale.

Two residual limitations, neither resolved by this fix:

- **The phone has not read this file.** Verification is through a
  re-implementation of the plugin's reader and through Ultralytics' own loader.
  Both exercise the documented contract; neither is an APK on a device.
- `labelName()` still returns `"class $index"` whenever metadata is missing, so
  the *next* hand-built export reintroduces the defect. That is what the
  regression test in §8 is for, not the metadata itself.

**This is the sixth time in this project that a control has looked like
protection while governing nothing**, which is why it was checked rather than
assumed. §7.1 and §7.2 are both necessary; neither alone was sufficient.

### 7.3 Evidence upload signing was broken on any non-UTC server

`routers/media.py` signed Cloudinary direct uploads with:

```python
timestamp = int(datetime.utcnow().timestamp())
```

This reads correctly and is not. `datetime.utcnow()` returns a **naive**
datetime holding the UTC wall clock, and `.timestamp()` interprets a naive
datetime as **local** time. The result is wrong by the host's UTC offset.

Measured on the development machine (IST, +05:30):

| | Epoch seconds |
|---|---|
| True time | 1793644902 |
| `datetime.utcnow().timestamp()` | 1793625102 |
| **Error** | **−19,800 s (−5.5 h)** |

Cloudinary rejects a signed upload whose timestamp is more than about an hour
from its own clock. So **evidence upload signing failed on any server not
running in UTC**, and worked perfectly on one that was — a defect that passes
every test on a UTC CI box and breaks in the one place it matters. For a system
whose purpose is to preserve evidence of an assault, silently failing to sign
uploads is not a cosmetic bug.

The mechanism was already understood in this codebase. `time_utils.py` exists
precisely because naive timestamps are ambiguous, and its docstring explains the
client-side version of the same trap. It simply had no helper for *producing*
the value, so five modules had each written their own private `_utcnow` — and
two of the five were still built on the deprecated call while three were not.
That inconsistency is what let the broken one survive.

**Fixed** by giving `time_utils` the two canonical producers it was missing —
`naive_utc_now()` for storage and `utc_epoch_seconds()` for epoch arithmetic —
and routing all 5 helper definitions and 7 remaining call sites through them,
plus 5 more in test fixtures. `datetime.utcnow()` no longer appears in
`fastapi_app/` or `tests/`.

A side effect worth recording as corroboration: the suite's total warning count
fell **1,898 → 12 → 7** across the two passes, and `utcnow` deprecations
specifically went to **zero**. The warnings had been there all along, in the
output of every run, naming the broken line. Nobody read them, which is the
practical argument for not letting a suite accumulate 1,898 of anything.

The 7 that remain are a different deprecation — FastAPI's `@app.on_event`,
superseded by lifespan handlers — plus one from `starlette`. That is left
deliberately: migrating app lifecycle is a behavioural change to startup and
shutdown ordering, not a one-line substitution, and it is listed in §11 rather
than done hastily alongside a safety fix.

### 7.4 An end-to-end test skipped on the failure it existed to catch

The integration suite's `setUpClass` logged in a freshly registered user and
stored the token. Both "no server" and "the server rejected the login" produced
`access_token = None`, and every dependent test then called
`skipTest("Authentication failed")`.

So a genuine regression in registration or login was **indistinguishable from
nobody having started the backend** — reported as a skip, in a green suite. These
are the only tests in the project that exercise the assembled system, which
makes them the worst place for a silent pass.

**Fixed.** `setUpClass` now records *why* there is no token, and `_require_auth`
separates the two: it skips when the server is unreachable and **fails** when the
server answered but login did not work. Verified against a local stub that is
reachable and returns 401, where it now fails with
`login returned 401: {"detail":"Invalid credentials"}` instead of skipping.

### 7.5 A shutdown handler that caught nothing it could catch

`main.py` cancels its background workers on shutdown:

```python
task.cancel()
try:
    await task
except Exception:          # catches none of the cancellations
    pass
```

`asyncio.CancelledError` derives from **`BaseException`, not `Exception`**, so
the one exception this code provably raises was never caught, while any genuine
failure in a worker's teardown was silently discarded. Verified directly:
cancelling a task and awaiting it escapes `except Exception` on Python 3.12.

No safety impact — it runs only as the process exits. Recorded because it is
§7.2's pattern in miniature: a handler that reads as protection and governs
nothing. **Fixed** by catching `CancelledError` explicitly and logging real
exceptions instead of swallowing them.

### 7.6 On the web path, a weapon cannot raise the alarm

Found by the same wiring audit, and **not fixed** — it is a design question, not
a bug to patch quietly.

`ThreatPipeline` picks the detector by platform. On Android the phone scores
frames locally every **200 ms**; elsewhere it uploads a sample every **2 s**.
Both feed the same scorer, deployed with `window: 15, frameTimeout: 5 s`.

Those three numbers interact. Frames older than 5 s are dropped, so at a 2 s
cadence **at most three frames can ever be in the window at once**. Persistence
is `hits / window`, so it cannot exceed `3/15 = 0.20`, and the weapon score
cannot exceed about **0.20** however certain the model is. Verified by test: 20
consecutive detections at confidence 1.0 on a 2 s cadence leave
`framesConsidered ≤ 3` and `value ≤ 0.21`.

Against a `DEFAULT_THREAT_THRESHOLD` of 0.75 — and with a solo signal becoming
the fused score outright — **the weapon signal is structurally incapable of
reaching auto-SOS on the web path.** It can still contribute context and raise
the score alongside other signals, but on its own it is capped at roughly a
quarter of the threshold.

This may well be the right behaviour: a sampled, off-device detector is a
weaker promise, and the code says so. What makes it worth recording is that
nobody appears to have chosen it. It is an emergent property of a frame
timeout, a window length and a polling interval picked in three different files
for three unrelated reasons. A cap on a safety signal should be a decision with
a number attached, not a coincidence — so it is listed in §11 as a decision.

---

## 8. Regression tests added

| File | Tests | Purpose |
|---|---|---|
| `tests/test_weapon_model_metrics.py` | 12 | Pins the ONNX by SHA-256 and the TFLite twice over — its graph and the whole asset, separately, so a metadata change and a detector change fail with different messages (§7.2) — plus the class list, the deployed constants (floor 0.55, window 5, threshold 0.75, EMA alpha 0.30, solo retention 0.50), the scorer arithmetic, that a lone weapon reading is the fused score, and false-positive counts on fixed negative slices |
| `tests/test_glove_model_metrics.py` | 13 | Drift guard on the confirmation gate; `test_only_a_fall_can_reach_auto_sos_unaided`; `test_fall_is_the_only_class_mapped_to_danger` |
| `tests/test_weapon_model_metadata.py` | 3 | The §7.2 invariant: *either the model names its classes, or every class it emits is a weapon* |
| `tests/test_time_utils.py` | 6 | The §7.3 defect. Asserts `utc_epoch_seconds()` is real epoch time, that the naive storage convention holds, and that exactly one definition of the helper remains where five existed. Its load-bearing test is a **source guard** — `datetime.utcnow()` must not reappear in `fastapi_app/` or `tests/` — because the direct assertion is *vacuous on a UTC host*, where the broken and correct expressions return the same number |
| `mobile/test/.../weapon_detection_service_test.dart` | 13 (4 added) | The §9.1 gap: what the **deployed** scorer parameters imply, not the declared defaults — that persistence divides by 15, that 15 frames at 200 ms is the three seconds the rule was designed around, and the §7.6 cap on the web path |
| `mobile/test/.../weapon_scorer_test.dart` | 15 | Four added for the distractor filter, including that a weapon is still scored when a distractor outranks it (proving the filter runs before the sort) |

Both new guards were checked against the failure they exist to catch, not only
against the healthy case. The `utcnow` source guard was verified by planting a
file containing the broken call: it fails and names the offending line, and
passes once the file is removed. The timezone-dependent test that *demonstrates*
the bug skips on a UTC host and says so — which is exactly why the source guard,
not that test, is the one CI relies on.

**The metadata test was checked against the failure it exists to catch**, rather
than only against the healthy case. Pointed at the 6-class artifact *before*
metadata was attached, it fails with the actionable message it was written to
produce (`…exposes no class names to the Ultralytics plugin … That is only safe
while every class is a weapon, but this model emits 6`). A test that passes on
the good case but cannot fail on the bad one is precisely the pattern described
in §7.2, so it is demonstrated here rather than asserted.

Two further tests deserve comment, because they pin *structural* protections
that are easy to remove by accident:

- `test_only_a_fall_can_reach_auto_sos_unaided` asserts every non-danger weight
  stays below 0.75. The measurement found the two highest non-FALL scores at
  0.676 and 0.609 — right under the cap — so raising that weight would convert
  near-misses into triggers.
- `test_fall_is_the_only_class_mapped_to_danger` exists because `gloveScore` keys
  off `threatLevel`, not the label. Promoting another class to danger in
  `glove_protocol.dart` would hand it weight 1.0 without touching the pipeline.
  Both files must change together for the protection to hold.

**Suite status:** 583 Python passed / 7 skipped (17 subtests passed, 408 s);
451 Dart passed across `test/core/audio`, `test/features/safety` and
`test/features/devices`; `flutter analyze` clean on all changed files.

**Release build verified.** `flutter build apk --release` succeeds against the
configured release keystore, and the APK was opened and inspected rather than
assumed: the bundled `weapon_yolov8n_fp16.tflite` is 6,129,672 bytes with the
same SHA-256 as the repository asset, and its appended archive reads
`{"0": "pistol", "1": "knife"}`. The §7.2 fix therefore reaches the device, which
is the one thing a re-implementation of the plugin's reader could not establish.

Both counts moved since the previous run, and in each case the delta is
accounted for rather than assumed. Python went **572 → 574 → 580 → 583**. The first
step added one test when the TFLite pin was split into graph and whole-file
(§7.2), and resolved one that had been skipping, because
`test_every_named_non_weapon_is_on_the_dart_reject_list` skips when the model
exposes no class names and the model now exposes them — which is also why the
skip count fell from 8 to 7. The second step is the six tests in
`test_time_utils.py` (§7.3), and the third is three added pins on the
**deployed** scorer constants (§9.1). Dart went 443 → 447 → 451: the four
distractor-filter tests in the table above, counted before they landed, then
the four deployed-wiring tests.

**All 7 skips are end-to-end tests that did not run**, and this correction
matters more than the count. They were previously described here as
`pytest.importorskip` guards on the ML stack — that was wrong. The ML guards
exist, but every one of them resolves locally, so none of them skipped. The
actual 7, enumerated with `-rs`:

| Count | Reason | File |
|---|---|---|
| 4 | `API Gateway not running` | `test_api_gateway.py` (3), `test_integration.py` (1) |
| 3 | `API Gateway not running (ConnectionError: …)` | `test_integration.py` |

All seven are the same underlying condition: no backend was running on this
machine. These are the **only tests in the suite that exercise the assembled
system** rather than a model or a unit, so the thing this report is weakest on
(§12) is also the thing whose tests are inactive. They are not hidden failures —
they are not evidence of anything either, and a green suite summary conceals
that.

The three in the second row previously read `Authentication failed`, and that
wording was hiding a real defect: the same skip covered a missing service *and*
a genuine regression in login. It is fixed — see §7.4 — and those tests now
fail rather than skip when the server is reachable and login is broken. The
remaining skips are honest: there is genuinely no server here.

---

## 9. Corrections made to project documentation

Nine published figures or statements were wrong and are now corrected in source.
They are listed because a report that only adds findings, and never retracts
them, is not a reliable record.

| File | Was | Problem |
|---|---|---|
| `threat_models.py` | weapon mAP@0.5 0.906 on 658 held-out images | Computed on the **val** split (1,458 images) and is 0.8949 at the final epoch. 0.906 appears in neither training run. |
| `threat_models.py` | audio 0.905 accuracy at 0.968 recall | Clean-ASR only, with no indication the realistic degraded condition is materially worse |
| `weapon_scorer.dart` | precision 0.901, recall 0.827 | Measured 0.932 / 0.805 at the deployed floor; added that the window vote does **not** suppress a correlated false positive |
| ~~`camera_activation_policy.dart`~~ | ~~"votes over 15 frames, roughly three seconds"~~ | **This "correction" was itself wrong and is retracted — see below.** |
| `threat_signal_aggregator.dart` | diagnostic printed `fused_score` | That is the **raw** fusion output, while auto-SOS decides on the EMA-smoothed score. A log could read "fused 0.91 … normal", which looks like a banding bug and is really two different scores side by side. This made the hardware logs misleading. Now prints both, labelled. |
| `assets/models/README.md` | results column headed "v2 INT8 (**this file**)", 3.36 MB | The shipped asset is **fp16 at 6.13 MB**; the INT8 artifact is the server-side ONNX. No column in that table described the file it sat next to, so the headline accuracy figures for the on-device detector were being read off a different artifact. |
| `assets/models/README.md` | classes "see `weapon_labels.txt`" | Implies that file governs on-device class names. It does not — nothing on the device reads it (§7.2). Harmless-looking wording that helped a real defect stay hidden. |
| `ARCHITECTURE.md` | emotion `fear` at "47% recall and **56% precision**" | The training artifact records `per_class_recall` only. The 47% is in it; the 56% precision is in no artifact this evaluation could find, so it is **removed rather than restated**. The conclusion it supported — that `fear` is too weak to gate anything — rests on the recall figure and is unaffected. |
| `ARCHITECTURE.md`, `mobile/pubspec.yaml` | emotion model at `mobile/assets/models/…`, bundled at 3.09 MB | It is **not in the app at all**. The file lives in `ml_models/` and runs server-side on frames already uploaded. The asset directory has never contained it. A reader auditing what ships on the device would have looked for 3 MB of model that is not there — and, worse, would have concluded a facial-expression model runs on the phone. |

Two further corrections sit inside the findings above: the crop false-positive
caveat was **wrong in direction** (§5.3), and the published gated glove
false-positive rate described a gate no longer deployed (§4.4).

### 9.1 A correction in this report that was wrong, now retracted

One row above is struck through. An earlier pass "corrected"
`camera_activation_policy.dart`, which said the scorer *"votes over 15 frames,
roughly three seconds"*, to say the window was 5 and the span about a second —
on the strength of `WeaponScorer`'s declared default.

**The original comment was right.** `ThreatPipeline` constructs
`WeaponDetectionService` without passing a scorer, so the service's
`_defaultScorer()` governs: `window: 15, frameTimeout: 5 s`. At the deployed
on-device interval of 200 ms, that is 15 frames over three seconds — exactly
what the comment said. The "correction" replaced a true statement with a false
one, and it has been reverted in source.

Two things made this possible, and both are now closed:

- **The pin read the default, not the deployment.** `test_weapon_model_metrics.py`
  asserted `this.window = 5` in `weapon_scorer.dart` under a test named
  *the deployed constants match what was measured*. The deployed window lives
  in a different file and was pinned by nothing, so it could have been changed
  to any value without a single test failing. It is now pinned where it is
  actually set, alongside the frame timeout and the inference interval.
- **Nothing tested the composed behaviour.** Four tests in
  `weapon_detection_service_test.dart` now assert what the deployed parameters
  imply, including that `0.90` on one frame scores `0.90/15` rather than
  `0.90/5`.

This is the seventh instance in this project of a control that reads as
protection and governs nothing — and the first where the thing it failed to
govern was a correction made *by this report*. Reading a default and calling it
a deployed value is the same error as reading a reject list and calling it a
filter.

---

## 10. Data provenance

**Weapon.** Open Images V7 (annotations CC BY 4.0, images CC BY 2.0) and
OD-WeaponDetection (Universidad de Granada). Split 70/20/10 by image, seed
20260830: train 5,423 / val 1,458 / test 658 = 7,539. **Background images: 0.**
The `data.yaml` comment records 4,598/1,313/658, which is stale relative to the
directories on disk.

> **Licence conflict, unresolved.** The OD-WeaponDetection README states
> CC BY-SA 4.0 while its LICENSE file states CC BY 4.0. Treated as ShareAlike
> until the maintainers confirm. See `datasets/od_weapondetection/LICENCE-CONFLICT.md`.

**Audio.** 2,436 clips of synthetic TTS phrases (neural voices), transcribed by
ASR, plus degraded variants. Recording real distress speech was deliberately
descoped.

**Glove.** 230 recordings in one data-collection campaign; 208 development
(cross-validated) and 22 locked.

---

## 11. Open items

### 11.1 Measurement still outstanding

1. **Re-measure the emotion model** — *blocked on data, not effort.* The second
   half of this item, "or stop quoting 65.5%", is **done**: the figure is now
   marked as the training run's own unverified number in
   `threat_models.py`, `weapon_detector.py` and `ARCHITECTURE.md`, with the
   unsourced companion precision figure removed (§9). Re-measuring needs the
   AffectNet, FER+ and RAFDB test corpora, and all three directories are
   present and empty. Historic entries in `CHANGELOG.md` are deliberately left
   as written — a changelog records what was believed on its date, and editing
   it retroactively would destroy the thing that makes it evidence.
2. **Re-run the persistence probe at the deployed window of 15** (§5.4), which
   is now **required, not optional**: its published percentages model a window
   of 5 and are retracted. It needs 15 jittered frames per still rather than 5.
   The arithmetic cannot be rescaled from the existing run, because scaling 5
   frames to 15 would assume the frame independence the probe exists to
   disprove.
3. **Replace the simulated persistence probe (§5.4) with real glasses footage.**
   Still the weakest evidence in the report and the cheapest to upgrade once the
   glasses are paired. Doing this supersedes item 2 — real footage at 5 fps
   gives 15 real frames and answers both at once.

*The fp16 TFLite export, previously listed here, is complete and measured —
see §6.2. The §7.2 metadata defect, also previously open, is fixed.*

### 11.2 Requires hardware

4. Install the APK carrying the foreground-service microphone fix and confirm
   audio produces a reading at all.
5. Verify the detector fires on a real weapon through the real glasses camera,
   and that the detection arrives labelled `pistol` or `knife` rather than
   `class 0`. The §7.2 fix is verified through a re-implementation of the
   plugin's reader and through Ultralytics' own loader; neither is the phone.
   This is a one-glance check once the APK is installed.
6. One journey with both wearables paired. **This single item converts most of
   the `derived` grades in this report to `measured`.**
7. A glove recording session for subject, surface and fit diversity — no longer a
   sample-size question, now a generalisation one.

### 11.3 Decisions, not measurements

8. **May a single visual signal reach auto-SOS unaided?** Tightening this would
   block the §5.5 path but weakens the lone-weapon case the solo floor was built
   for.
9. **May a solo confirmed glove FALL reach auto-SOS unaided?** The same decision,
   now that the exposure is measured at 4.76% of normal recordings.
10. **Accept the audio trade (§6.3)?** The pre-committed gate rejects it.
    Acceptance must be recorded as a conscious override.
11. **Is the web path's weapon cap (§7.6) intended?** At a 2 s cadence against a
    5 s frame timeout the weapon score cannot exceed ~0.20, so it can never
    reach auto-SOS alone on that path. Either confirm the cap deliberately and
    document the number, or change the cadence or the timeout. Right now it is
    an accident of three independent choices.

### 11.4 Infrastructure

12. Redeploy the backend so the timestamp fix is live. **This now also carries
    the §7.3 evidence-signing fix**, which is the strongest reason yet to
    redeploy: until it ships, signed uploads keep failing on any non-UTC host.
13. Migrate `@app.on_event` to a lifespan handler. Deprecated and scheduled for
    removal, the last remaining deprecation in the suite, and deliberately not
    done in this pass: it changes startup and shutdown ordering, which is where
    the §7.5 fix lives, and it deserves its own change rather than riding along
    with a safety fix.
14. Credential rotation.
15. Machine stability: eight unexpected shutdowns since early September, two
    during the 6-class training run, Kernel-Power 41 with no bugcheck. 74 °C mean
    is not dangerous for the GPU in question, and with 55 W average draw against
    an 80 W limit and no bugcheck on any crash, power delivery is a better suspect
    than heat. This blocks any long training run and is a hardware question, not a
    SafeHer one.

    **A second, independent symptom on the same machine**, found while clearing
    build artifacts: five JVM crash dumps in `mobile/android/`, dated 2026-08-15
    through 2026-09-16, every one of them *"insufficient memory for the Java
    Runtime Environment to continue … The system is out of physical RAM or swap
    space"*, failing to map between 226 MB and 1.14 GB. These are Gradle build
    crashes, **not** the Kernel-Power shutdowns, and they do not explain them.
    What they do is corroborate memory-and-pagefile exhaustion from a second
    tool on five separate occasions — the same mechanism already suspected
    behind the silent training deaths, where the constraint was free space on
    `C:` backing the pagefile rather than RAM itself. Worth checking pagefile
    sizing and free space on `C:` before suspecting the power supply. The dumps
    themselves have been deleted; this note is the record.

---

## 12. Conclusion

The four shipped models that gate an alarm all pass on the tasks they were
measured on, and quantisation cost nothing measurable in any of them.

That was not the risk. Every substantive finding in this evaluation concerns what
the system does with a model's output rather than how accurate the model is:

- A solo signal **is** the fused score, because `fuse()` renormalises over
  reporting signals. One sensor can reach the auto-SOS threshold on a single
  post, with a 5-second cancellable countdown as the only thing in the way.
- The weapon detector fires on **20.3% of real weapon-free frames** at its
  deployed floor — a defect invisible to every accuracy metric, because the
  training set contains no weapon-free images.
- **4.76% of normal glove recordings** reach the auto-SOS threshold unaided,
  mitigated only structurally by a weight table that makes non-FALL classes
  incapable of triggering alone.
- **Six findings sat around the models rather than in them**, none visible to
  any accuracy metric (§7). The second would have made the fix for the first
  govern nothing, and proving that fix safe required showing it did not disturb
  the §4.1 measurements — which it does not, bitwise. The third broke evidence
  upload signing on any server not running in UTC. The fourth was an end-to-end
  test that skipped on precisely the failure it existed to catch. Five are
  fixed; the sixth (§7.6) is a decision, not a bug.

  Four of them share one shape: **a control that reads as protection and
  governs nothing** — a name-based filter with no names to match, a handler for
  an exception that cannot be raised, a skip that covers both a missing
  environment and a real regression, and a constant pinned where it is
  *declared* rather than where it is *set*. That shape, not model accuracy, is
  what this evaluation kept finding.

- **This report got one wrong, and §9.1 says so.** An earlier pass read
  `WeaponScorer`'s declared default of 5 frames, concluded that a source comment
  saying 15 was mistaken, and "corrected" a true statement into a false one. The
  deployed window is 15, set in a different file that no test was pinning. The
  §5.4 persistence percentages inherit that error and are **retracted**; they
  overstate the exposure, and the correction is left visible precisely because
  it flatters the system. The mechanism §5.4 established — that these errors are
  correlated rather than independent — does not depend on the window and stands.

Of four remediation attempts, **two were rejected** — one for destroying knife
precision, one by the project's own pre-committed ship gate. That ratio is itself
a finding: it is the reason the one that worked is worth believing.

**For the patent filing specifically.** The accuracy figures here are
defensible, and the false-positive analysis is defensible as a grounded
prediction. The system-level claim — that this assembly detects threats in the
field — is **not** supported by this report, and no amount of model-level testing
will support it. One hardware journey with both wearables is what closes that
gap.
