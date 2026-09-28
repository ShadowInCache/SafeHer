# Where weapon detection runs, and why not on the glasses

**Short answer: on the phone.** The glasses stream frames; the phone runs the
model. This is not a compromise forced by a large model — no amount of
compression puts YOLOv8n on an ESP32, and the gap is not close.

## The arithmetic

An ESP32-CAM (AI-Thinker, the common board) has **520 KB of SRAM and 4 MB of
PSRAM**. An ESP32-S3 improves on this but stays in the same order of magnitude.

| What YOLOv8n needs | Size |
|---|---|
| INT8 weights | 3.36 MB |
| Input tensor, 640×640×3 | 1.23 MB |
| One stride-8 feature map, 80×80×64 | 410 KB |
| …and dozens more, concurrently | tens of MB |

The weights alone consume most of the PSRAM before a single frame is loaded.
Activation memory — the intermediate feature maps a convolutional network
holds while computing a forward pass — is what actually breaks it, and it is
the part compression does not touch.

Then there is compute. The classic ESP32 is a 240 MHz dual-core with **no
neural accelerator**. YOLOv8n is 8.1 GFLOPs per frame. Even granting a
generous 50 MFLOPs/s of usable throughput, that is minutes per frame, not
milliseconds.

**This is a two-orders-of-magnitude gap, not a tuning problem.** Shrinking the
model further — smaller input, deeper quantisation, pruning — reaches a model
too weak to detect a knife long before it reaches one an ESP32 can hold.

## Why the glove is different

The glove *does* run its model on-device, and that is not a contradiction. Its
XGBoost forest compiles to a few thousand float comparisons over 51 scalar
features — kilobytes of C arrays, microseconds per window. A decision-tree
ensemble over hand-computed features and a convolutional network over a
409,600-pixel image are not the same kind of workload, and the glove's success
says nothing about the glasses' prospects.

## The architecture that works

```
SMART GLASSES                 PHONE                        BACKEND
─────────────                 ─────                        ───────
camera ──► frame stream ──►   sample ~2 fps
                              ONNX YOLOv8n int8  (3.36 MB)
                              weapon_score ──► fusion engine
                                                  │
mic ─────► audio stream ──►   CNN+LSTM            │
                              audio_score ────────┤
                                                  │
glove ───► BLE classification ─────────────────►  │
                              glove_score         │
                                                  ▼
                                            threat level
                                                  │
                              raw streams ──► evidence buffer ──► incident
```

Three properties this preserves, all of which matter:

**No server before the alarm.** A dead backend, no signal, or an untrained
server-side model all leave weapon detection working. Routing frames to a
server for inference would make the most important detection in the system
depend on connectivity, at exactly the moment connectivity is least reliable.

**The phone is already the hub.** It holds the glove's BLE link, runs the
fusion engine's client half, owns the evidence buffer and keeps a foreground
service alive. Adding frame inference puts the work where the process already
is.

**Bandwidth stays local.** Glasses-to-phone is a short link. Streaming video
to a backend for inference would cost mobile data continuously, and the
battery to push it.

## What the glasses firmware actually has to do

Capture and transmit. No inference, no model, no TensorFlow. That is well
within an ESP32-CAM's abilities and is what the hardware is for.

Concretely, and pending the hardware answers still outstanding:

- MJPEG over HTTP, or chunked frames over WiFi, to the phone on the local
  network. **Not WebRTC** — an ESP32 will not do it.
- Whatever resolution and frame rate the board sustains. The phone samples for
  inference at roughly 2 fps regardless; the rest of the stream goes to the
  evidence buffer.
- Audio as a separate stream, so the inference path never blocks the recording
  path.

## If on-device screening becomes necessary

There is a legitimate version of "run something on the glasses", and it is a
**cascade**, not a smaller YOLO. A very small quantised classifier — the scale
of ESP-DL's person-detection examples, around 250 KB — could answer a much
easier question: *is anything in this frame worth the phone's attention?* The
phone then confirms with the real model.

That saves radio power and phone wake-ups. It is a battery optimisation, not a
detection strategy, and it needs its own model, its own dataset and its own
validation. It is not on the critical path and should not be treated as one.

## Status

The model is bundled and validated — see the README there. **It now has a
producer** (as of 2026-09-11): on Android, `ultralytics_weapon_detector.dart`
runs it on-device via `ultralytics_yolo` (LiteRT fp16); on web, where that
plugin has no implementation, `remote_weapon_detector.dart` samples a frame to
`POST /alerts/weapon-frame` and scores it server-side. `weapon_scorer.dart`
votes over a window and `DetectionSources` reports which path is live.

The frame transport now exists too — `mjpeg_client.dart` parses the glasses'
MJPEG stream and the pairing sheet verifies a device answers as a SafeHer
camera. What remains unproven is the end-to-end path against **real** glasses
hardware: the video path has only been exercised against a synthetic MJPEG
stream.
