# On-device models

## `weapon_yolov8n_fp16.tflite`

YOLOv8-nano, two classes, LiteRT with fp16 weights. **6.13 MB.**

| | |
|---|---|
| Classes | `0 pistol`, `1 knife` — order matters, see `weapon_labels.txt` |
| Input | `1×640×640×3` (NHWC), RGB, float32, normalised 0–1 |
| Output | `1×6×8400` — `[cx, cy, w, h, pistol_conf, knife_conf]` per anchor, **box coordinates normalised 0–1** |
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

### Wired up

`UltralyticsWeaponDetector` loads it through the `ultralytics_yolo` plugin.
Frames arrive from the glasses over MJPEG (`mjpeg_client.dart`),
`WeaponDetectionService` throttles inference to ~5 fps and votes over a
15-frame window, and the result reaches `ThreatSignals.weapon` via
`ThreatSignalAggregator`.

**Two paths, and they are not the same promise.** The plugin has no web
implementation, so `ThreatPipeline` picks a detector per platform:

| | rate | where | what leaves the device |
|---|---|---|---|
| Android | ~5 fps, continuous | on the phone | nothing — only a score |
| web | 1 frame / 2 s, sampled | `POST /alerts/weapon-frame` | the frame itself |

`ThreatPipelineStatus.weaponOnDevice` publishes which one is running so the UI
can say so. A sampled server-side check is weaker than a continuous local one,
and presenting them as one thing would be the sort of claim this codebase keeps
having to remove.

The server path runs the **INT8 ONNX** export of the same weights from
`ml_models/`, because `onnxruntime` on a CPU-only host is the opposite trade to
Android's GPU delegate: INT8 is faster there. If no model is deployed the
endpoint answers `available: false` and the client reports the modality
**absent** — never zero, which would claim the camera looked and saw calm.

### Why fp16 and not INT8, and the export that had to be re-done

INT8 would be 3.4 MB against 6.13, and it is the wrong trade here. The GPU
delegate executes in fp16; an INT8 graph often falls back to CPU and loses more
to the fallback than it saved in size, and this runs continuously on live video.

The first conversion also had to be thrown away, which is the more useful
lesson. Ultralytics refuses TFLite export on Windows, so the model was
converted by hand via ONNX and `onnx2tf`. It measured **mAP 0.0** — while being
a perfectly healthy model. `diagnose_tflite.py` ran the interpreter directly and
found sensible detections with boxes spanning 4.9 to 635.9 pixels. The problem
was a convention mismatch: ultralytics' own exports normalise box coordinates to
0–1 and its runtime multiplies them back up, so absolute pixels were multiplied
by 640 and every box landed off-frame.

That mattered beyond the test. The Flutter plugin is Ultralytics' own and reads
Ultralytics' convention, so the same file would have failed identically on the
phone — where there is no mAP to notice it with. The export now normalises, and
`export_tflite.py` re-validates on the real 658-image test split and refuses to
ship anything more than 0.03 below the PyTorch baseline.

| | mAP@0.5 | mAP@0.5:0.95 | P | R |
|---|---|---|---|---|
| PyTorch fp32 | 0.907 | 0.653 | 0.896 | 0.833 |
| **LiteRT fp16** | **0.906** | 0.627 | 0.903 | 0.831 |

Per class after conversion: pistol 0.931, knife 0.881.

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

## `emotion_mobilenetv3_fp16.onnx` — moved to `ml_models/`

**No longer bundled in the app.** Nothing in `lib/` ever loaded it, so it was
3.09 MB in every APK doing nothing. It now lives in `ml_models/` beside the
server's weapon ONNX, where it is actually used: it runs on frames already
uploaded by the web fallback, and its output goes into `SupportingContext`.

It still cannot touch the threat score, and `tests/test_fusion_architecture.py`
still fails if that drifts. The rest of this section describes the model as
trained.

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

### Where it runs, and the preprocessing that has to match

Server-side only, in `fastapi_app/services/weapon_detector.py`, on frames the
web fallback has already uploaded. Reading a frame twice is free; uploading one
for this alone would not be worth it.

**It classifies a face, not a scene.** A frame is passed through OpenCV's
frontal-face cascade first, and no face means no expression rather than a
confident label about a street. Input is 96×96, greyscale expanded to three
channels, normalised with ImageNet statistics — the pipeline it was fine-tuned
through.

That contract was got wrong first: the initial version fed 48×48 scaled to
0–1, which threw on every frame, was swallowed by the error handler, and
returned null forever while the endpoint test passed. Only running it over real
images surfaced it. `TestPreprocessingContract` now asserts the module's input
size against the size the model itself declares.

### Licence

FER2013 was released for the ICML 2013 Challenges in Representation Learning.
Verify the terms attach to your use before any commercial release. Weights are
initialised from torchvision's ImageNet MobileNetV3-Small.

---

## `phrase_classifier.json`

TF-IDF into logistic regression, executed in pure Dart. **196 kB.**

| | |
|---|---|
| Classes | `distress`, `normal`, `threat` |
| Input | a transcript string from the platform's speech recogniser |
| Output | three probabilities; the fusion signal is `P(threat) + P(distress)` |
| Features | 1,005 word 1–2 grams + 2,882 `char_wb` 3–5 grams = 3,887 |
| Trained | 2026-09-02, on 348 phrases of text |

### What replaced the CNN+LSTM, and why

`audio_cnnlstm_int8.onnx` used to sit here — a waveform classifier that scored
**98.9%** on Google Speech Commands. It has been removed from the app.

Two things were wrong with it. The first was the task: it spotted the words
`stop`, `no`, `off`, `down`. Nobody being attacked says "down". The second was
that when it was re-measured on the phrases that actually matter, it scored
**54.5%** on unseen phrasings — *below* the 70.5% that a plain fuzzy string
match managed. It was 1.12 MB shipped to every user to do worse than `if`.

The replacement splits the problem in two. The platform's own speech recogniser
turns audio into words, and this model reads the words. That generalises to
phrasings nobody wrote down, which was the whole difficulty: "I'll hurt you"
and "I'm going to hurt you" share `hurt` and `you`, and a model over words
sees that where a model over waveforms does not.

### Measured on held-out phrasings

The test set is 714 clips of phrases **never seen in training** — the split is
by phrase, not by clip, so no wording appears on both sides.

| boundary | accuracy | recall | specificity |
|---|---|---|---|
| **elevated vs normal** | **0.905** | **0.968** | 0.790 |
| three-way label | 0.877 | — | — |

The binary row is the headline because it is the decision the model actually
makes. `ThreatSignals.audio` is a single number; threat and distress both mean
"raise the score", so a distress clip labelled `threat` costs nothing, while a
distress clip labelled `normal` is a woman asking for help and being scored as
small talk. Only 15 of 462 elevated clips were missed, and twelve of those are
the ASR truncating a phrase to the words "this way".

Specificity 0.790 is the real cost: about a fifth of ordinary speech scores
above 0.5. That is survivable only because no signal triggers an alarm alone —
`threat_fusion` weights audio at 0.35 and applies a solo-signal floor, a
threshold, hysteresis and dedup on top.

### What the training data is, and what it is not

`phrases.py` holds 174 phrases synthesised with `edge-tts` across many voices;
`extra_training_phrases.py` adds ~250 more as **text only**, which is free for a
model that reads strings and never sees a waveform.

The additions were chosen from measured errors rather than intuition. The
largest single cluster of misses was "this is an emergency" — wrong on all
seventeen of its clips, because the training vocabulary contained no form of the
word *emergency* at all. `assert_no_leakage()` fails the build if any added
phrase collides verbatim with one in `phrases.py`; it caught eight collisions on
the day it was written, and one (`"I'm being followed"`) that had been inflating
every number measured before it.

**These are TTS voices reading calmly, not people in danger.** ASR quality on
real shouted speech was measured separately on BERSt: `tiny.en` reached 60% word
error rate on *non-shouted* speech and 78% on shouted. That is why the front
half is the platform recogniser rather than a bundled Whisper — and why the
honest next step is recording real speech, not adding more synthetic phrases.

### Preprocessing is a contract

The weights were fitted by scikit-learn and are executed by hand-written Dart,
so the features must be built exactly as scikit-learn builds them. Three details
do the damage if missed: the word analyser drops single-character tokens;
`char_wb` pads each word with spaces before cutting n-grams; and each vectoriser
L2-normalises **its own block** before they are concatenated.

Get any of them wrong and the classifier stays confident and becomes incorrect,
silently. So `export_phrase_classifier.py` also writes 50 fixtures of real
transcripts with the probabilities the Python model produced, and
`threat_phrase_classifier_test.dart` asserts parity to 1e-4. It currently agrees
to **7e-7** — and it earned its place immediately, by catching that the first
version of the exporter fed raw transcripts to `predict_proba` while every other
consumer used the normaliser.

### One deliberate refusal

A transcript containing no known word returns `normal` at 0.0 elevated, rather
than falling through to the model's class prior. `class_weight="balanced"` was
fitted across two elevated classes and one normal one, so an empty input scores
**0.56 elevated** on the intercepts alone — a microphone hearing silence would
report more than halfway to an emergency, continuously. "Nothing heard" and
"nothing wrong" are different claims, and this is the only place that can tell
them apart.

### Licence

The phrases are original to this project. Voices are Microsoft Edge neural TTS,
used to generate training audio only. BERSt (CC BY 4.0) was used for evaluation
and is not redistributed here.

Training pipeline lives outside this repo at `D:\SafeHer-ML\audio_threat\`.
