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

**Whether these clear the targets the SRS commits to is a separate question**,
answered in §13. Three of the stated per-model benchmarks are met and two are
not, and the verdicts in the table above — which say whether a model works, not
whether it hits a number — do not settle it either way.

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
> this probe generated 5. See §12.
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
drive an automatic SOS with no weapon present. Grounded prediction, not an
observed failure.

> **Correction, 2026-11-03.** This section previously said the mitigation in the
> path was `kDefaultCountdownSeconds = 5`, a cancellable countdown. **There is
> no countdown on the automatic path.** The countdown lives in
> `emergency_screen.dart` and gates the *manual* and shake-initiated SOS. An
> automatic dispatch runs server-side in `_auto_dispatch_if_threatened`, which
> notifies every emergency contact as soon as the smoothed score crosses the
> threshold; the comment beside its background fan-out says so outright — *"an
> automatic alert has no countdown absorbing the wait"*. The phone is not
> consulted and cannot cancel: it learns the alarm fired from the `auto_sos`
> block in the response, after dispatch has already started.
>
> This correction runs the dangerous way. It removes a mitigation the report
> claimed, so the exposure described above is **less constrained** than it was
> presented, not more. The mitigations that do exist are the 0.75 threshold, the
> EMA, and the 120-second deduplication window — none of which is a chance for
> her to say "I'm fine". Whether auto-SOS should have a cancellation window is a
> decision, not a defect. **It has since been taken: no cancellation window,
> decided 2026-11-03 on FR-EMG-02's zero-interaction criterion — see §11.**
> The exposure measured in this section is therefore accepted rather than
> pending, and a false alarm raised this way is not recoverable by the user: it
> reaches her contacts.

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
a device test, not an open technical question. See §7 and §12.

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

Eleven findings sit in the code around the models rather than in them —
in the path from a model's output to the alarm, in the evidence handling beside
it, and in the tests meant to watch both. **None is visible in any accuracy
metric**, which is the point of this section: the models were not the risk.

They are not of equal weight. §7.1–§7.3 could each have affected a real
incident; §7.4 concealed whether anything worked; §7.5 is hygiene, recorded
because it is the same mistake in miniature — a handler that catches an
exception class the code cannot raise. §7.7 and §7.8 are both in the auto-SOS
path itself: one called every contact twice, the other could have suppressed a
genuine first alarm. §7.10 is the most serious finding in this report — an
emergency contact who also used SafeHer aborted the entire fan-out, silently,
in priority order. §7.6 and §7.9 are not defects but undecided consequences of
numbers chosen independently; with §7.11 they are the three left open.

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
shutdown ordering, not a one-line substitution, and it is listed in §12 rather
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
a number attached, not a coincidence — so it is listed in §12 as a decision.

### 7.7 Concurrent readings dispatched to every contact twice

The deduplication window is read from the database — correctly, because
in-process state would forget it across a restart and *"forgetting it would mean
alerting every contact twice"*. But nothing held a lock between reading it and
writing the `auto_dispatched` flag that closes it, and several awaits sit in
between. The phone posts to `/analyze` every second, and `/heartbeat` and
`/process-threat` can land alongside it.

**Measured, not reasoned about:** three concurrent readings at a triggering
score produced **two dispatches** and two incident records. Every emergency
contact would have been called twice for one emergency — the precise failure the
window exists to prevent, by a route the window could not see.

**Fixed** with one `asyncio.Lock` per user, held across read-decide-write.
Keyed per user so one woman's emergency never queues behind another's. The
concurrency test fails without it and passes with it.

### 7.8 A stale score could hold a genuine first spike below the threshold

`smooth()` takes a first reading as-is, deliberately: seeding the EMA at zero
would halve the very first sample, the one most likely to be the emergency. That
protection only holds if "first" means first *of this episode*, and the store
had no notion of age.

The phone drops any signal older than 10 s and posts nothing when nothing is
fresh, so gaps are routine rather than exceptional. A smoothed score left from
an abandoned session was therefore used as `previous` however old it was.

**The direction is a missed alarm.** A stale previous of 0.70 turns a genuine
first spike of 0.80 into `0.30×0.80 + 0.70×0.70 = 0.73` — below the 0.75
threshold. The alarm that should have fired on the first sample does not fire.

**Fixed** with `SMOOTHING_STATE_TTL_SECONDS = 30`: past that, the next reading
begins a new episode and is taken at full strength. Thirty seconds is three
times the device's own freshness window, long enough to ride out a retry and
short enough that an abandoned session does not bleed into the next one. Erring
towards an unsmoothed reading errs towards raising an alarm, which is the trade
this codebase already makes for losing the store on restart.

Two tests, because one alone would have been satisfied by deleting the store
entirely: a stale entry must be ignored, **and** a recent one must still damp.

> The first version of the staleness test aged the entry by
> `SMOOTHING_STATE_TTL_SECONDS + 1`, which is stale relative to whatever the
> constant happens to be — it passed with the TTL raised to thirty years. It
> asserted that the comparison worked, not that any bound existed. It now ages
> by a fixed ten minutes and was checked against a disabled TTL before being
> relied on.

### 7.9 Deployment constraint: this is correct for one worker

`_smoothing_state` and the per-user locks are process-local. That is right for
the single uvicorn worker `app.py` starts, and it is a hard limit on scaling:
with two workers a user's readings would split across two independent EMA
states and two independent locks, weakening the smoothing *and* reopening §7.7.
Documented at both definitions. Moving beyond one worker means moving this state
to Redis or Postgres first.

### 7.10 An emergency contact who also uses SafeHer broke the whole fan-out

Found on 2026-11-03 while building the retraction fan-out, which copies the
alarm's push block.

`emergency_dispatch.py` called `fcm_credentials(settings)` in the push branch of
`_notify_contact` **without importing the name**. It is defined in
`fastapi_app/deps.py` and was never imported into this module, so the call is a
`NameError`.

```python
tokens = await _tokens_for_contact(session, contact)
if tokens and fcm_credentials(settings).is_configured:   # NameError
```

**Why it survived.** The line is guarded by `tokens`, which is non-empty only
when a contact's phone or email matches a `User` row that has a registered FCM
token — that is, when one of her emergency contacts *is herself a SafeHer
user*. No test in the suite had ever set that up, so the branch was never
executed and the missing import never surfaced.

**What it would have done.** `_notify_contact` is not wrapped, so the exception
escapes `dispatch_to_contacts` — whose docstring promises it "never raises" —
up to `run_dispatch_in_background`, which catches it and marks the incident
`dispatch_failed`. Contacts are notified in the user's own priority order, so
the fan-out aborts at the first contact who happens to use the app **and every
contact ranked below them is never notified at all.** On the inline path (no
background queue) it surfaces as a 500 from the SOS request.

The likeliest person to install SafeHer on a user's recommendation is a sister,
a mother, a partner — the same people she is most likely to rank first. The
defect therefore selects for exactly the contact lists where it does the most
damage.

**Confirmed, not inferred.** `eval("fcm_credentials", vars(module))` raises
`NameError`, and
`test_a_contact_who_is_also_a_safeher_user_does_not_abort_the_fanout`
reproduces the abort end to end: with the import removed it fails with
`NameError` at `emergency_dispatch.py:399`; with it restored, both contacts are
notified.

**Fixed** by importing the name at module scope, with a comment recording what
the absence cost. The same push block in `retract_to_contacts` is covered by
the same import.

This is a tenth instance of the shape §7.6 names: **a control that reads as
protection and governs nothing.** Here the push channel read as a third
delivery route and was in fact a trapdoor under the other two.

### 7.11 A client-chosen incident id that already belongs to someone else — NOT FIXED

Noticed on 2026-11-03 while hardening the retraction query, and **left alone
deliberately**: fixing it changes the behaviour of the SOS endpoint itself,
which is outside what was asked for here.

`POST /alerts/emergency` lets the client choose `incident_id`, which is what
makes a retry after a timeout idempotent rather than filing a second
emergency. Ownership *is* checked on the replay path:

```python
existing = await session.get(Incident, requested_id)
if existing is not None and existing.user_id == current_user.id:
    return await _incident_response(session, existing)
```

There is no data leak — a stranger's incident is not returned. But when the id
exists and belongs to *someone else*, control falls through to
`incident_id = requested_id or str(uuid4())` and inserts a row with a primary
key that is already taken, which raises `IntegrityError` and surfaces as a 500
on an SOS request.

**Severity: low.** It needs a caller who guesses another user's UUID, and the
worst outcome is a failed alert for that caller rather than any exposure of the
other user's data. It is recorded because the shape matters: the id is
free-form client input that is then used as a database key, and §7.10 is a
reminder that untested branches in this path are where the real failures hide.
The retraction query was written with `startswith(..., autoescape=True)` rather
than a `LIKE` pattern for the same reason — an id containing `_` would
otherwise have matched another of her own incidents' audit rows and sent a
false-alarm message to the contacts of an alert that was still live. That one
*is* fixed and tested; this one is listed in §12.

---

## 8. Regression tests added

| File | Tests | Purpose |
|---|---|---|
| `tests/test_weapon_model_metrics.py` | 12 | Pins the ONNX by SHA-256 and the TFLite twice over — its graph and the whole asset, separately, so a metadata change and a detector change fail with different messages (§7.2) — plus the class list, the deployed constants (floor 0.55, window 5, threshold 0.75, EMA alpha 0.30, solo retention 0.50), the scorer arithmetic, that a lone weapon reading is the fused score, and false-positive counts on fixed negative slices |
| `tests/test_glove_model_metrics.py` | 13 | Drift guard on the confirmation gate; `test_only_a_fall_can_reach_auto_sos_unaided`; `test_fall_is_the_only_class_mapped_to_danger` |
| `tests/test_weapon_model_metadata.py` | 3 | The §7.2 invariant: *either the model names its classes, or every class it emits is a weapon* |
| `tests/test_threat_fusion.py` | 25 (3 added) | The §7.7 race — three concurrent readings must not dispatch more than once — and the §7.8 TTL in both directions: a stale smoothed score is ignored, a recent one still damps |
| `tests/test_time_utils.py` | 6 | The §7.3 defect. Asserts `utc_epoch_seconds()` is real epoch time, that the naive storage convention holds, and that exactly one definition of the helper remains where five existed. Its load-bearing test is a **source guard** — `datetime.utcnow()` must not reappear in `fastapi_app/` or `tests/` — because the direct assertion is *vacuous on a UTC host*, where the broken and correct expressions return the same number |
| `mobile/test/.../weapon_detection_service_test.dart` | 13 (4 added) | The §9.1 gap: what the **deployed** scorer parameters imply, not the declared defaults — that persistence divides by 15, that 15 frames at 200 ms is the three seconds the rule was designed around, and the §7.6 cap on the web path |
| `mobile/test/.../weapon_scorer_test.dart` | 15 | Four added for the distractor filter, including that a weapon is still scored when a distractor outranks it (proving the filter runs before the sort) |
| `tests/test_incident_retraction.py` | 26 | The §11 retraction decision and the §7.10 defect. Covers that the correction reaches exactly the contacts the alarm reached, that retracting mid-fan-out *stops* the remaining alarm messages rather than racing them, that it is idempotent, that a dismissed prompt is not a retraction, that the stand-down is logged distinctly so it is never read back as evidence the alarm got through, and that no server-side deadline is enforced. Includes the cross-language pin tying the Dart prompt constant to `RETRACTION_PROMPT_SECONDS` |
| `mobile/test/.../auto_sos_retraction_test.dart` | 13 | That the app notices its *own* automatic alert at all — the phone learns this only from the `/analyze` response — that a non-triggering verdict reports nothing, that one incident is reported once however many readings name it, and the notifier's failure path |
| `mobile/test/.../auto_sos_retraction_banner_test.dart` | 8 | That the prompt actually appears, that tapping it sends the correction, that a failure says *"your contacts still think you need help"* rather than a soft error, and that hiding the banner does not stand a real emergency down |

Both new guards were checked against the failure they exist to catch, not only
against the healthy case. The `utcnow` source guard was verified by planting a
file containing the broken call: it fails and names the offending line, and
passes once the file is removed. The timezone-dependent test that *demonstrates*
the bug skips on a UTC host and says so — which is exactly why the source guard,
not that test, is the one CI relies on.

**The two retraction tests that carry weight were likewise checked against
their own failure**, because both would otherwise have been vacuous:

- `test_a_contact_who_is_also_a_safeher_user_does_not_abort_the_fanout` — with
  the §7.10 import removed, it fails with `NameError` at
  `emergency_dispatch.py:399`, which is the real defect and not a stand-in for
  it.
- `test_retracting_mid_fanout_stops_the_remaining_contacts` — with the
  `should_continue` check replaced by `if False`, it fails reporting all three
  contacts alarmed instead of one. Without that demonstration the test proves
  only that a predicate *can* be passed, not that it is honoured.

**A third one passed in isolation for the wrong reason, and the full suite
caught it.** `test_a_wildcard_in_an_incident_id_does_not_pull_in_another_alert`
first used fixed incident ids. `tests/conftest.py` points the suite at
`./test_safeher.db`, a **file that is not dropped between runs**, so those ids
accumulated audit rows from every previous run's user and the test passed
alone while failing inside the suite. The ids are now derived from a fresh
`uuid4()` stem per run, and the test was re-checked against the raw `LIKE`
afterwards to confirm the change had not also removed its ability to fail.
Recorded because it is the §7 shape turned on the tests themselves: a green
run that proved nothing. Any new test in this suite that hard-codes a row key
is making the same mistake.

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

**Suite status:** **614 Python passed / 7 skipped** (17 subtests passed, 376 s)
and **1,125 Dart passed**; `flutter analyze` clean on `lib` and `test`.

Two notes on those numbers, because both changed meaning in this pass:

- The Python delta is exactly the 27 new tests in
  `tests/test_incident_retraction.py` (587 → 614), so nothing was lost or
  renamed to get there.
- The Dart figure is now the **whole** suite. Earlier revisions of this report
  quoted 451, which was a scoped run over `test/core/audio`,
  `test/features/safety` and `test/features/devices` — a real number, but not
  the one the label implied. 1,125 is `flutter test` with no path argument.

The 7 skips are not ML-extras guards. Enumerated with `-rs` rather than
described from memory, **all seven now read "API Gateway not running"** —
three in `tests/test_api_gateway.py` and four in `tests/test_integration.py`.

That is a change worth stating precisely, because an earlier revision of this
section said four were reachability and three were "Authentication failed".
Both were true when written. §7.4 turned the authentication case into a
*failure* rather than a skip, so with no gateway listening on port 5000 those
tests now stop at the reachability guard instead — which is the correct
ordering: a server that is absent is a skip, a server that answers and rejects
a valid login is a regression.

**Release build verified.** `flutter build apk --release` succeeds against the
configured release keystore, and the APK was opened and inspected rather than
assumed: the bundled `weapon_yolov8n_fp16.tflite` is 6,129,672 bytes with the
same SHA-256 as the repository asset, and its appended archive reads
`{"0": "pistol", "1": "knife"}`. The §7.2 fix therefore reaches the device, which
is the one thing a re-implementation of the plugin's reader could not establish.

Both counts moved since the previous run, and in each case the delta is
accounted for rather than assumed. Python went **572 → 574 → 580 → 583 → 586 → 587**. The first
step added one test when the TFLite pin was split into graph and whole-file
(§7.2), and resolved one that had been skipping, because
`test_every_named_non_weapon_is_on_the_dart_reject_list` skips when the model
exposes no class names and the model now exposes them — which is also why the
skip count fell from 8 to 7. The second step is the six tests in
`test_time_utils.py` (§7.3), and the third is three added pins on the
**deployed** scorer constants (§9.1), and the fourth is the three auto-SOS
tests for §7.7 and §7.8, and the fifth is the test pinning the §11 decision
that auto-SOS has no cancellation window. Dart went 443 → 447 → 451: the four
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
(§14) is also the thing whose tests are inactive. They are not hidden failures —
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

## 11. Decisions taken

A decision recorded here is a choice someone made on a date, with the cost
named. The alternative — a default that nobody chose, defended afterwards as
though it had been — is how §7.6's web-path cap came about.

### Auto-SOS has no cancellation window — decided 2026-11-03

**Asked explicitly and answered no.** An automatic alert notifies every
emergency contact as soon as the smoothed score crosses the threshold. The
phone is not consulted, there is no hold-off, and there is nothing to dismiss.

**Reasoning.** FR-EMG-02's acceptance criterion is *zero user interaction
required*, and it exists for the situations where she cannot act. A window an
incapacitated woman cannot dismiss only delays help. A window an attacker can
dismiss is worse than none, because it converts a raised alarm into a silenced
one.

**The cost, accepted rather than hidden.** §5.5 measures it: a phone or a purse
in view during an already-elevated moment can drive an automatic dispatch with
no weapon present, and nothing in the path now asks her first. The mitigations
that remain are the 0.75 threshold, the EMA, and the 120-second deduplication
window. A false alarm under this decision is **not recoverable by the user** —
it reaches her contacts.

> **Superseded in part, 2026-11-03.** That last sentence was true when it was
> written and is no longer. The decision below makes a false automatic alarm
> recoverable *after* dispatch rather than before it. The alert still goes out
> with nothing to dismiss, so the decision above stands unchanged; what has
> changed is that it is no longer irreversible. Left in place rather than
> rewritten, because the accepted cost is what justified the decision and
> editing it away would make the decision look cheaper than it was.

That makes two things matter more than they did, and both are already open
items: the §5.4 persistence re-measurement, because the false-positive
behaviour of the visual signal is now the dominant risk in this path; and the
§12 decision on whether a solo visual signal may trigger unaided, which is the
remaining lever on the same exposure.

**Pinned in code**, not just written down:
`test_an_automatic_alert_has_no_cancellation_window` requires the fan-out to be
underway when the request returns. A later change that adds a hold-off fails
that test and has to return to this decision rather than quietly reverse it.

A post-dispatch *retraction* — contacts told immediately, then told it was a
false alarm if she says so within seconds — is a different mechanism, since it
delays nothing. It was not part of this decision. ~~It remains unasked.~~ It
was asked on 2026-11-03 and answered; see the decision below.

### A false automatic alarm is retractable after dispatch — decided 2026-11-03

**Asked because the decision above named an unrecoverable cost, and answered
by choosing the route that does not reintroduce a delay.** Three options were
put: a pre-dispatch cancellation window, a post-dispatch retraction, or leaving
dispatch alone and closing the exposure by re-measuring the visual signal. The
second was chosen.

**What it does.** `POST /alerts/emergency/{id}/retract` stands an alert down
and sends the contacts it reached a stand-down on every channel that alarmed
them. Dispatch timing is untouched: the alert still leaves the instant the
threshold is crossed.

**Why not the pre-dispatch window.** It would have reversed the decision above
for no gain in the cases that matter. If she is grabbed, pinned or unconscious
she cannot cancel either, so in a genuine emergency a window buys nothing and
costs delay; only in a false alarm does it help. A correction after the fact
helps the false alarm *without* charging the genuine one.

**Note on the phrasing "before" in the request that prompted this.** There was
no earlier state to restore. Git history carries no cancellation window in the
automatic path at any commit — the only match for `countdown` in
`fastapi_app/routers/alerts.py` is the comment added in `5833c84` noting that
the path has none. The 5-second countdown gates manual and shake SOS only,
which is what §9.1 corrected. Adding a window would have been new behaviour,
not a rollback, which is why it was put as a decision rather than performed as
one.

**Two ordering properties that the mechanism is worthless without**, both
tested rather than asserted:

1. **The correction must not overtake the alarm.** `retracted_at` is committed
   *before* anything is sent, and the alarm fan-out re-reads it between
   contacts through a new `should_continue` predicate. Retracting during the
   first seconds therefore *stops* the remaining alarm messages. Without this,
   contacts further down the priority list would receive "FALSE ALARM" and
   then "EMERGENCY" — an ordering worse than no retraction at all. Verified by
   disabling the check and watching all three contacts get alarmed.
2. **It must correct the right people.** Who was reached is read from the
   notification log, which commits per contact per channel as the fan-out runs,
   unioned with `incidents.contacts_reached`, which is complete but only
   written at the end. Neither alone is both current and complete. The union
   errs towards over-inclusion deliberately: a contact who gets a stand-down
   for an alarm they never saw is briefly confused, while a contact who got the
   alarm and no stand-down may call the police.

**What it deliberately does not do.** There is no server-side deadline. The
60-second `RETRACTION_PROMPT_SECONDS` is how long the app keeps the action in
front of her, not a window after which the server refuses. A deadline's only
possible effect would be to withhold a correction she has decided to send, and
there is no reading of this product where that is safer. A test asserts the
constant appears in neither the handler nor the service, so a future change
that starts enforcing it fails.

**The cost, named.** Her contacts may receive two messages. SMS is charged per
message, so a retraction is not free — and it is sent on SMS anyway, unlike
the evidence follow-up, which is email-only on exactly those cost grounds.
That trade is different here: a contact holding a text saying she is in danger
has to be corrected on the channel they are holding.

**Pinned in code:** `tests/test_incident_retraction.py` (26 tests),
`mobile/test/features/safety/data/auto_sos_retraction_test.dart` (13), and
`mobile/test/features/safety/presentation/auto_sos_retraction_banner_test.dart`
(8). A cross-language test pins the Dart prompt constant to the Python one, so
the banner and the server cannot drift apart silently.

**Still open:** whether a *contact* should be able to ask her to confirm, and
what happens to evidence already uploaded against a retracted incident. The
recording is kept — a retraction is her saying she is safe, not a request to
erase what was captured — but nothing yet marks it as belonging to a
withdrawn alert.

---

## 12. Open items

### 12.1 Measurement still outstanding

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

### 12.2 Requires hardware

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

### 12.3 Decisions, not measurements

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
12. **Should a retracted incident's evidence be marked as such?** The recording
    is kept — a retraction is her saying she is safe, not a request to erase
    what was captured — but nothing on the media rows says the alert they
    belong to was withdrawn. An incident report generated later reads as a
    live emergency.
13. **Should a contact be able to see that a retraction was sent *to someone
    else*?** Today each contact learns only about their own message. If the
    stand-down reaches two of three contacts, the third is left believing she
    is in danger and the other two have no way to know that.
14. **Fix §7.11, or constrain the client-chosen incident id?** A supplied id
    that already belongs to another user falls through to an insert on a taken
    primary key and 500s an SOS request. Either reject the collision explicitly
    or require the id to be a UUID the caller derives from their own namespace.
    Left unfixed here because it changes the SOS endpoint's behaviour, which is
    outside what this pass was asked to do.

### 12.4 Infrastructure

15. Redeploy the backend so the timestamp fix is live. **This now also carries
    the §7.3 evidence-signing fix**, which is the strongest reason yet to
    redeploy: until it ships, signed uploads keep failing on any non-UTC host.
16. Migrate `@app.on_event` to a lifespan handler. Deprecated and scheduled for
    removal, the last remaining deprecation in the suite, and deliberately not
    done in this pass: it changes startup and shutdown ordering, which is where
    the §7.5 fix lives, and it deserves its own change rather than riding along
    with a safety fix.
17. Credential rotation.
18. Machine stability: eight unexpected shutdowns since early September, two
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

## 13. Benchmark conformance against the SRS targets

Re-measured 2026-11-03. Every earlier section reports what the models *do*;
this one asks the narrower question the SRS actually commits to — whether each
model clears the target written against it in **SRS §1.3** (measurable goals)
and **SRS §6.1** (AI platform specification).

This section exists because the targets are stated in metrics the evaluation
had not always computed. The SRS fixes the weapon detector at **mAP@0.5 > 0.88**
and the voice path at **F1 > 0.90**; §4 reported the weapon detector in
precision and recall at its deployed confidence floor, and the audio classifier
in accuracy, recall, precision and specificity — but never an F1. The benchmark
metric for the audio model had therefore never been computed from the shipped
bytes at all.

### 13.1 Method

Every figure below comes from the bytes that ship. Hashes were verified against
§4 before measuring, and all three matched exactly:

| Artifact | SHA-256 (verified) |
|---|---|
| `mobile/assets/models/weapon_yolov8n_fp16.tflite` | `afcfbe8c…a347b` (graph `b5625bcf…7c338`) |
| `ml_models/weapon_yolov8n_int8.onnx` | `45811e6a…1ff2e` |
| `mobile/assets/models/phrase_classifier.json` | `18221931…b4200` |

The weapon models were measured with `ultralytics.YOLO.val` on the 658-image
locked test split (783 instances), CPU, `imgsz=640`, `batch=1`. The audio model
was measured by importing `classify` from `verify_shipped_json.py` — the harness
that already proved the shipped JSON reproduces its training figures — so the
numbers describe the model rather than a fresh transcription of it. The glove
model was measured with `evaluate_shipped_model.py`.

**No figure here was obtained by re-framing an existing measurement.** The one
metric change that might look like re-framing — reporting the weapon detector in
mAP@0.5 rather than at its operating point — is reporting it in the metric the
SRS names, and §13.3 states plainly why the two differ and which one describes
what a user experiences.

### 13.2 Result

| Model | SRS target | Measured | Met |
|---|---|---|---|
| Weapon YOLOv8n, phone fp16 TFLite | mAP@0.5 > 0.88 | **0.9068** | **Yes** |
| Weapon YOLOv8n, server int8 ONNX | mAP@0.5 > 0.88 | **0.9023** | **Yes** |
| Weapon YOLOv8n, 6-class candidate (not shipped) | mAP@0.5 > 0.88 | **0.8938** | **Yes** |
| Audio ASR→TF-IDF→LR, clean ASR | F1 > 0.90 | **0.9401** | **Yes** |
| Audio ASR→TF-IDF→LR, degraded ASR | F1 > 0.90 | **0.8709** | **No** |
| Glove XGBoost, 5-class | accuracy > 0.95 | **0.8886** | **No** |

Both weapon artifacts reproduce their recorded mAP to within 0.0012, and the
glove model reproduces its published accuracy and macro-F1 exactly
(0.8886 / 0.9001). Nothing has drifted.

Full per-class figures:

| Artifact | mAP@0.5 | mAP@0.5:0.95 | pistol | knife | recorded | drift |
|---|---|---|---|---|---|---|
| phone fp16 TFLite | 0.9068 | 0.6317 | 0.9316 | 0.8820 | 0.9056 | +0.0012 |
| server int8 ONNX | 0.9023 | 0.6269 | 0.9264 | 0.8781 | 0.9013 | +0.0010 |
| 6-class candidate | 0.8938 | 0.6260 | 0.9313 | 0.8563 | — | — |

The six-class candidate's headline mAP and its weapon-only mAP are the same
number because the test split contains no instances of the four distractor
classes, so `ap50` has length 2. Its benchmark figure is therefore directly
comparable to the two shipped artifacts, and it sits **0.0130 below** the
shipped phone model — the cost falling almost entirely on knife
(0.8820 → 0.8563). It still clears 0.88.

### 13.3 The weapon benchmark is met in mAP, and mAP is not the operating point

mAP@0.5 integrates precision over the entire recall curve, including detections
far below `WeaponScorer.confidenceFloor` that the app discards before they ever
reach the weapon signal. The app does not operate at 0.9068. Measured at the
floor it actually applies:

| Artifact | conf | precision | recall | F1 |
|---|---|---|---|---|
| phone fp16 TFLite | 0.55 | 0.9234 | 0.8077 | 0.8617 |
| server int8 ONNX | 0.55 | 0.9229 | 0.7999 | 0.8570 |

These independently reproduce §4's operating-point figures (0.932 / 0.805 and
0.931 / 0.798) to within 0.009, from a different decoder — ultralytics' matcher
rather than the project's own — which is a stronger reproduction than re-running
the same code would have been.

**So: the benchmark is met, and the sentence "the weapon detector achieves
0.9068" must never be written next to a claim about what the app does.** At the
deployed floor roughly one weapon instance in five is still missed. Both
statements are true and the report keeps both.

### 13.4 The audio benchmark is met on clean ASR and missed on degraded

| Condition | acc | precision | recall | **F1** | specificity | 3-class acc |
|---|---|---|---|---|---|---|
| clean ASR | 0.9202 | 0.9141 | 0.9675 | **0.9401** | 0.8333 | 0.8571 |
| degraded ASR | 0.8305 | 0.8589 | 0.8831 | **0.8709** | 0.7341 | 0.7423 |

714 held-out clips, split by phrase. The degraded condition is the realistic
one — §4 already records that — so **the honest headline is that the voice path
misses its benchmark by 0.029 F1.**

**The cheap fix does not exist.** The decision threshold is a constant in three
places, so moving it would have been the zero-cost route. A sweep from 0.30 to
0.80 shows the deployed 0.50 is *already* the F1-optimal point:

| threshold | 0.40 | 0.45 | **0.50** | 0.55 | 0.60 | 0.65 |
|---|---|---|---|---|---|---|
| F1 | 0.8458 | 0.8580 | **0.8709** | 0.8603 | 0.8575 | 0.8345 |

No threshold in the sweep reaches 0.90. The benchmark cannot be reached by
tuning a constant; it requires a better model.

**The rejected retrain candidate does not reach it either.** §6 records that
the corpus-rebalance candidate was rejected by the project's pre-committed ship
gate because recall fell (0.8831 → 0.846). Its F1 had never been computed. It
is **0.8689** at the deployed threshold and **0.8735** at its own best threshold
of 0.45 — a tie with the shipped model within noise, and still 0.027 short.

That is worth stating precisely because it closes a question rather than opening
one: **the ship gate's rejection cost nothing on the benchmark metric.** The
gate and the benchmark agree. The candidate does, however, buy a real
improvement elsewhere — specificity 0.7341 → 0.8135 on degraded ASR, and clean
F1 0.9401 → 0.9530 — which is relevant to §5's false-positive chain even though
it does not move the benchmark.

### 13.5 The glove benchmark is missed, and the gap is large

Measured accuracy **0.8886** against a target of **> 0.95**, an exact
reproduction of the published figure. This is a 6.1-point gap, far outside the
range a threshold or a gate could close, and §4's cross-validated per-event
figures (94.3% fall detection, CI 81.4–98.4) do not change it: that is a
different measurement answering a different question, and quoting it against a
per-window accuracy target would be exactly the re-framing this project has
committed not to do.

### 13.6 The system-level goals in SRS §1.3 are not evidenced

SRS §1.3 states **true positive rate > 95%** and **false positive rate < 3%**
for the assembled system. Neither is evidenced by this report:

- No individual model reaches 95% recall. The best are audio at 0.9675 (clean
  ASR only) and the glove's cross-validated 94.3% fall detection.
- The fused system's TPR has **never been measured end-to-end**, because that
  requires hardware in the loop, which §1 records as absent.
- The 3% false-positive goal sits against §5's finding that 20.6% of real
  weapon-free frames fire at the deployed floor on the shipped model.

These remain the report's weakest claims and §14 says so.

### 13.7 What would actually close the two open gaps

Both are model problems, not measurement problems.

**Audio (0.8709 → > 0.90).** The gap is specificity, not recall: 67 of 252
ordinary clips read as elevated. §4 records that the specificity figure rests on
only **18 distinct held-out normal phrases**, so the first step is not a
retrain but a wider negative corpus — the current estimate is too thinly based
to steer a retrain reliably. The rebalance candidate already shows specificity
is movable (0.7341 → 0.8135) at a cost in recall; a model that moves both needs
more normal speech, which is the cheapest unblocked work on this list.

**Glove (0.8886 → > 0.95).** A 6.1-point gap on a 5-class problem where §4
already identifies the failure as concentrated in false FALL. More labelled
FALL and NORMAL recordings is the route; §12 already carries this.

**Weapon.** Already met. The open decision is whether to ship the six-class
candidate, which trades 0.0130 mAP for an 8× reduction in the false-positive
rate that §5 names as the principal finding. On the benchmark alone the shipped
model is better; on the finding that matters the candidate is better, and both
clear 0.88.

---

## 14. Conclusion

The four shipped models that gate an alarm all pass on the tasks they were
measured on, and quantisation cost nothing measurable in any of them.

That was not the risk. Every substantive finding in this evaluation concerns what
the system does with a model's output rather than how accurate the model is:

- A solo signal **is** the fused score, because `fuse()` renormalises over
  reporting signals. One sensor can reach the auto-SOS threshold on a single
  post. **Nothing in that path asks her first** — the 5-second cancellable
  countdown gates the manual SOS only, and the automatic dispatch notifies
  contacts server-side without consulting the phone (§5.5). That is now a
  recorded decision rather than an accident, and since 2026-11-03 it is no
  longer irreversible: a false automatic alarm can be retracted after the
  fact, which corrects the contacts it reached without delaying the alert
  (§11).
- The weapon detector fires on **20.3% of real weapon-free frames** at its
  deployed floor — a defect invisible to every accuracy metric, because the
  training set contains no weapon-free images.
- **4.76% of normal glove recordings** reach the auto-SOS threshold unaided,
  mitigated only structurally by a weight table that makes non-FALL classes
  incapable of triggering alone.
- **Eleven findings sat around the models rather than in them**, none visible to
  any accuracy metric (§7). The second would have made the fix for the first
  govern nothing. The third broke evidence upload signing on any server not
  running in UTC. The fourth was an end-to-end test that skipped on precisely
  the failure it existed to catch. **Two were in the auto-SOS path itself**: one
  called every emergency contact twice when two readings arrived together, the
  other could have held a genuine first spike below the threshold and suppressed
  the alarm entirely. **The tenth is the worst of them**: an emergency contact
  who also used SafeHer raised a `NameError` in the push branch, which escaped
  a function documented as never raising and aborted the fan-out — so that
  contact *and every contact she had ranked below them* were never notified at
  all. It survived because no test had ever made a contact a user. Eight are
  fixed; §7.6 and §7.9 are decisions and constraints rather than bugs, and §7.11 is a low-severity defect left deliberately unfixed.

  Six of them share one shape: **a control that reads as protection and
  governs nothing** — a name-based filter with no names to match, a handler for
  an exception that cannot be raised, a skip that covers both a missing
  environment and a real regression, a constant pinned where it is *declared*
  rather than where it is *set*, and a third delivery channel that was in fact
  a trapdoor under the other two. That shape, not model accuracy, is what this
  evaluation kept finding.

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
