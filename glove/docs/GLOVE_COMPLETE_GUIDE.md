# SafeHer Smart Glove — Complete Guide

Everything about the glove: the hardware, the firmware, the ML model, the
Bluetooth protocol, how the mobile app uses it, how to build/flash/test it,
what is known to work, and what is known to be weak.

Written from the code as it stands on the `glove-ml-integration` branch.
Where something is unverified or has only been checked in tests, it says so.

> **Some older docs are out of date** — see [Section 15](#15-stale-documentation).
> This guide is the current reference.

---

## Contents

1. [What the glove is](#1-what-the-glove-is)
2. [Hardware](#2-hardware)
3. [Firmware](#3-firmware)
4. [The ML model](#4-the-ml-model)
5. [Bluetooth (BLE) protocol](#5-bluetooth-ble-protocol)
6. [What the app does with the glove](#6-what-the-app-does-with-the-glove)
7. [Connection lifecycle](#7-connection-lifecycle-connect-drop-reconnect)
8. [How an alarm is decided](#8-how-an-alarm-is-decided)
9. [Model quality: measured results](#9-model-quality-measured-results)
10. [Known weaknesses](#10-known-weaknesses)
11. [Candidate models (v8, v9)](#11-candidate-models-v8-v9)
12. [Build, flash, run, test](#12-build-flash-run-test)
13. [Retraining the model](#13-retraining-the-model)
14. [Troubleshooting](#14-troubleshooting)
15. [Stale documentation](#15-stale-documentation)
16. [Verification status](#16-verification-status)
17. [Repository map](#17-repository-map)

---

## 1. What the glove is

An ESP32-C3, a motion sensor (MPU-6500) and a heart-rate sensor (MAX30102)
worn on the hand. It classifies hand motion **on the device** with a
machine-learning model and tells the phone what it saw — plus a rough heart
rate — over Bluetooth Low Energy. No server is involved between the glove and
the phone.

```
 MPU-6500 ──┐
 (motion)   ├─I²C─> ESP32-C3 ──BLE notify──> Phone app ──> Alarm countdown
 MAX30102 ──┘       (runs the model)         (votes, shows, alerts)
 (heart rate)
```

Heart rate is display-only: it does not feed the alarm vote, the risk score or
the model.

The five things it can say, in the order the firmware indexes them:

| Index | Label | Meaning |
|---|---|---|
| 0 | `NORMAL` | Ordinary hand movement |
| 1 | `SUDDEN_MOVEMENT` | A sudden push, pull, or jerk (merged from three earlier classes) |
| 2 | `SHAKING` | Shaking motion |
| 3 | `TWISTING` | Twisting motion |
| 4 | `FALL` | A fall |

**That order is part of the contract.** The firmware sends a label by
indexing `CLASS_NAMES` with the model's predicted class number. Reordering
either the array or the model's class order silently delivers a fall to the
app under another name.

The glove is currently the only detector in SafeHer that runs a trained model
end to end without a backend.

---

## 2. Hardware

| Part | Detail |
|---|---|
| Microcontroller | ESP32-C3 (native USB — see [Troubleshooting](#14-troubleshooting)) |
| Motion sensor | MPU-6500 on I²C, address `0x68`, `WHO_AM_I` register (`0x75`) must read `0x70` |
| I²C | `Wire.begin()` with default pins, 100 kHz |
| Accelerometer range | ±2 g (register `0x1C` = `0x00`) → 16384 counts per g |
| Gyroscope range | ±250 °/s (register `0x1B` = `0x00`) → 131 counts per °/s |
| Sampling | 100 Hz (one sample every 10 000 µs) |
| Heart-rate sensor | **MAX30102** on the same I²C bus as the MPU (address `0x57`, no conflict with the MPU's `0x68`), SDA = GPIO 8, SCL = GPIO 9, 3.3 V. Optional: the glove runs without it. |
| Battery monitoring | **None** |

The firmware refuses to run if the sensor does not answer with `0x70`: it
prints `ERROR: MPU-6500 not detected!` and stops.

---

## 3. Firmware

File: `glove/firmware/SafeHer_Glove_V5_OnDevice/SafeHer_Glove_V5_OnDevice.ino`
(plus the generated `safeher_v5_model.h` / `.cpp`, which hold the model).

### 3.1 What runs, in order

1. **`setup()`** — start serial (115200), start I²C, initialise BLE and begin
   advertising, check the sensor, configure it.
2. **`loop()`** — every 10 ms read 14 bytes from the sensor (accel, temp,
   gyro), and hand the six raw values to the windowing code.
3. **Windowing** — samples fill a 100-sample buffer (1 second). When full,
   inference runs, then the newest 50 samples slide to the front. Result: **one
   classification every 0.5 seconds** (50-sample overlap).
4. **Inference** (`runInference`) — extract 51 features, run all trees, pick
   the class with the highest score, compute its confidence, apply the gating
   rules below, then notify the phone.
5. **Telemetry** — every 500 ms, send accel/gyro magnitude.
6. **Heart rate** — every 100 ms drain the MAX30102 FIFO (about 5 samples at 50 Hz), feed the beat detector, and once per second notify the latest BPM. See [3.8](#38-heart-rate-max30102).

### 3.2 Raw counts, not physical units

The model was trained on **raw int16 sensor counts**, so the firmware feeds
raw counts into feature extraction. Only the telemetry stream converts to g
and °/s. Converting on only one side would silently ruin every prediction.

### 3.3 The 51 features

Computed over each 100-sample window:

| Group | Count | Contents |
|---|---|---|
| Six raw axes (Ax Ay Az Gx Gy Gz) | 36 | mean, std, min, max, range, rms — each |
| Accelerometer magnitude | 6 | same six statistics |
| Gyroscope magnitude | 6 | same six statistics |
| Jerk | 3 | mean, std, max of the sample-to-sample change in accel magnitude |
| **Total** | **51** | |

The feature order must match the training CSV column order exactly.

### 3.4 Confidence and how a class is chosen

The model is a forest of decision trees. Each tree adds a score to one class
(trees are interleaved round-robin across classes); the class with the highest
total wins. **Confidence** is a softmax over the five totals — the probability
of the winning class. It answers "how sure is the model which class this is",
**not** "how dangerous is this".

### 3.5 Gating rules applied before anything is sent

Applied in `runInference()`, in this order:

| Rule | Behaviour |
|---|---|
| **Low-confidence `SUDDEN_MOVEMENT`** | Below `SUDDEN_MOVEMENT_CONFIDENCE_THRESHOLD` (0.65) the window is treated as `NORMAL`. |
| **Low-confidence `FALL`** | Below `FALL_CONFIDENCE_THRESHOLD` (0.65) the window is treated as `NORMAL`. |
| **`SUDDEN_MOVEMENT` debounce** | Even above 0.65, `SUDDEN_MOVEMENT` is only sent after **2 consecutive windows** (`SUDDEN_MOVEMENT_CONFIRMATION_WINDOWS`). A single isolated window is held back. |
| **Serial FALL confirmation** | Two consecutive `FALL` windows ≥ 0.65 print `HIGH_RISK - FALL CONFIRMED` on the serial monitor. Serial output only — it does not change what is sent over BLE. |

Everything else (`NORMAL`, `SHAKING`, `TWISTING`) is sent immediately.

> **Important — the two low-confidence rules are recent changes.** They were
> added deliberately to cut false alerts, and they have a cost: a real fall
> the model scores below 0.65 is now reported to the phone as `NORMAL`, so the
> app never sees it. From cross-validation, roughly one real fall in four
> scores below 0.65. Before this change, a low-confidence `FALL` was still
> sent as `FALL` with its true (low) confidence attached and the app decided
> what to do with it. See [Section 10](#10-known-weaknesses) for numbers.
> As of this guide these rules have **not been verified on hardware**.

### 3.6 BLE server behaviour

- Device name `SafeHer-Glove`.
- One service, three characteristics: classification, telemetry, and (optional
  hardware) heart rate — see [Section 5](#5-bluetooth-ble-protocol). The
  service uses 10 of its 15 default attribute handles.
- A flag `blePhoneConnected` is set in the connect callback and cleared in the
  disconnect callback. Notifications are only sent while it is set.
- On disconnect the firmware **restarts advertising** so the phone can find it
  again without a reset.
- Single client: one phone at a time.

### 3.7 Two firmware modes

`DATA_COLLECTION_MODE` at the top of the sketch:

| Value | BLE | Serial output | Use |
|---|---|---|---|
| `0` | Initialised, advertises, notifies | Diagnostics | Normal operation and anything involving the app |
| `1` | **Never initialised** | Raw CSV at 100 Hz | Recording training data |

Left at `1`, the glove never advertises and the app scans forever with
nothing visibly wrong. **Check this first** if a glove cannot be found.

### 3.8 Heart rate (MAX30102)

**Student prototype — not a medical device.** The BPM is an optical estimate
that depends on finger pressure, ambient light and movement. It must never be
presented as medically accurate.

Files: `safeher_max30102.h` (register-level driver, no library, same `Wire`
bus, never calls `Wire.begin()` or changes the clock) and
`safeher_heart_rate.h` (pure C++ beat detector).

- **Sensor setup:** SpO2 (red+IR) mode so the FIFO carries an IR slot, 100
  samples/s averaged by 2 → **50 samples/s**, 18-bit, 4096 nA range, LED
  amplitude `0x1F`.
- **Polling:** one short I²C burst every 100 ms (`HEART_RATE_POLL_INTERVAL_MS`),
  run right after a motion sample so it never delays the 100 Hz motion path.
  FIFO overflow is detected and accounted for.
- **Notification:** once per second (`HEART_RATE_NOTIFY_INTERVAL_MS`). Raw
  samples never go over BLE.
- **Optional hardware:** if the sensor is not found at boot the firmware prints
  `MAX30102 not detected - heart rate disabled.` and carries on; everything else
  is unaffected (unlike the MPU, which halts the sketch).

**How a BPM is decided** (`safeher_heart_rate.h`): two cascaded ~0.5 Hz
high-pass stages remove the DC level and slow drift, a ~4 Hz low-pass removes
noise, and peaks above an adaptive fraction of the recent peak height are
beats. The median of recent beat intervals gives the rate. A BPM is published
only if **all** of these hold:

1. at least 4 intervals are held and all but at most one agree with their
   median to within 20%;
2. the estimate is within 40–180 bpm;
3. the filtered signal correlates with itself one beat later (≥ 0.7) **and**
   two beats later (≥ 0.5). A real pulse repeats; noise does not.

**Validity and timeouts** (never a stale or invented value):

| Situation | Result |
|---|---|
| No finger (raw IR below `kFingerIrThreshold`, 20 000) | no reading |
| Finger briefly lifted (< 5 s) | last BPM held |
| Finger absent ≥ 5 s | cleared → `BPM,NONE` |
| Finger present but no newly validated beat for 20 s | cleared (until then the last validated BPM is held, so brief weak stretches do not flicker to `--`) |
| Sensor delivers nothing for 2 s | reported unavailable |
| Signal too weak / irregular to pass the checks above | no reading (never a guess) |

The app is never sent `0`. Zero, absent and invalid all become `BPM,NONE`.

**Limits, from testing the detector against synthetic pulse signals (a Python
port of the C++ logic — not a real finger):**

- 72–165 bpm: within about ±4 bpm on clean-to-moderately-noisy signals.
- Noise-only input: **0% fabricated BPM** at every noise level tested.
- Below ~60 bpm it more often reports *no reading* than a value (honest, but a
  real limitation).
- A pulse weaker than the noise gives *no reading*, not a wrong number.
- Motion artifacts usually give *no reading*; they can still occasionally
  produce a wrong value. The motion sensor is not used to reject them.
- Time to first BPM after placing a finger: about 5–9 s.
- **All thresholds were chosen on synthetic data.** Expect to retune
  `kFingerIrThreshold` and `kMinPulseAmplitude` on the real glove. Serial prints
  one `HEART_RATE: BPM,74 (finger=1)` line per second (`HEART_RATE_LOG`) to help.

### 3.9 Naming quirks (legacy)

The files and namespace are still called `safeher_v5_model` / `V5Embedded`,
and the startup banner still prints `Classes: 7`. The model actually inside
is the **5-class v7 model** (3000 trees, 37 176 nodes). The names were never
changed, so that the sketch code did not have to change when models were
swapped. When someone says "the v5 model", check which they mean — see
[Section 4.6](#46-which-model-is-which).

---

## 4. The ML model

### 4.1 Type

XGBoost, multi-class (`multi:softprob`), converted to plain C arrays and
compiled into the sketch. No runtime library, no file system.

| Setting | Value |
|---|---|
| Boosting rounds | 600 |
| Trees | 3 000 (600 × 5 classes) |
| Max depth | 6 |
| `min_child_weight` | 30 (chosen so it fits the ESP32-C3's flash) |
| Learning rate | 0.05 |
| Subsample / column sample | 0.9 / 0.9 |
| Nodes (deployed model) | 37 176 (≈ 520 KB) |
| Features | 51 |
| Classes | 5 |

### 4.2 Training data

Raw recordings live in `glove/ml/dataset/<class>/`. Each file is
`timestamp_ms,Ax,Ay,Az,Gx,Gy,Gz,label` at 100 Hz, **raw int16 counts**.

| Class folder | Recordings |
|---|---|
| normal | 70 |
| fall | 40 |
| push | 30 |
| pull | 30 |
| jerk | 20 |
| shaking | 20 |
| twisting | 20 |
| **Total** | **230** |

(`sudden_movement/` holds 80 files — the push, pull and jerk recordings with
their label rewritten to `SUDDEN_MOVEMENT`.)

Feature extraction turns these into **4 016 windows**:

| Class | Windows |
|---|---|
| SUDDEN_MOVEMENT | 1 364 |
| NORMAL | 1 357 |
| FALL | 639 |
| SHAKING | 328 |
| TWISTING | 328 |

Features file: `glove/ml/features/glove_5class_features_v1_merged_pushpull_jerk.csv`.

### 4.3 Why PUSH, PULL and JERK were merged

Trained as separate classes, the model could barely tell them apart from each
other or from other classes (self-recall as low as ~6–18% on some
recordings), and the app already scored all three identically. Merging them
into `SUDDEN_MOVEMENT` lost nothing downstream and raised that class's
held-out recall to about 87%.

### 4.4 The train / test split (do not disturb)

- **208 recordings (3 585 windows)** are the development set. All
  cross-validation and tuning uses only these.
- **22 recordings** are the **locked test set**. They are used **once**, for
  the single official comparison of a candidate against the production model.
  Reusing them for tuning would make every later score meaningless.
- Splits are always by **recording**, never by window: consecutive windows
  overlap by 50%, so splitting on windows leaks near-identical data across
  the split and reports a score the model has not earned. The split file is
  `glove/ml/models/glove_7class_v5_train_test_split.json`.

### 4.5 Where the model files are

| Path | What |
|---|---|
| `glove/ml/models/glove_5class_v7_merged_pushpulljerk_final/` | The deployed 5-class model (JSON) + training report |
| `…/esp32_compact/` | The C++ export of that model |
| `glove/ml/models/safeher_glove_7class_v5_xgboost.json` | The original **frozen 7-class** V5 model. Never modify. |

### 4.6 Which model is which

| Name | Classes | Status |
|---|---|---|
| **V5** | 7 (NORMAL, JERK, PUSH, PULL, SHAKING, TWISTING, FALL) | Original, frozen, kept for comparison only |
| **v7** | 5 | **Currently on the glove** (under the legacy `v5` file names) |
| **v8** | 5 | Candidate — FALL calm-window relabel. Not deployed. |
| **v9** | 5 | Candidate — FALL + SUDDEN_MOVEMENT calm-window relabel. Not deployed. |

---

## 5. Bluetooth (BLE) protocol

The firmware and the app are separate codebases that must agree exactly. The
app-side contract is in one file:
`mobile/lib/features/devices/domain/glove_protocol.dart`.

### 5.1 Identifiers

| | Value |
|---|---|
| Advertised name | `SafeHer-Glove` |
| Service UUID | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` |
| Classification characteristic | `beb5483e-36e1-4688-b7f5-ea07361b26a8` (READ + NOTIFY) |
| Telemetry characteristic | `33b4fb00-9c17-4ad2-8fc9-89ad6dbc76bd` (READ + NOTIFY) |
| Heart-rate characteristic | `7805c91e-4a04-4c87-91df-bc711e39107e` (READ + NOTIFY) — optional |

All three characteristics carry a standard CCCD descriptor (BLE2902) so the phone
can enable notifications.

> The service and classification UUIDs are the stock ones from the Arduino
> `BLE_notify` example, so any other project built from that example
> advertises the same service. Generated private replacements are recorded in
> `GloveBle.suggestedPrivateServiceUuid`. Changing them is a coordinated change
> on both sides, so it has not been done.

### 5.2 Packet formats (plain text)

**Classification** — sent when a window is classified (about every 0.5 s,
subject to the gating rules in 3.5):

```
<LABEL>,<confidence>          e.g.   FALL,0.93     NORMAL,0.99
```

**Telemetry** — sent every 500 ms:

```
<accel_g>,<gyro_dps>          e.g.   1.02,4.3
```

These are the **magnitudes** (√(x²+y²+z²)) of acceleration in g and rotation in
°/s. The app can also parse two further legacy fields (`bpm`, `battery %`), but
the firmware does not send them; heart rate has its own characteristic below,
and there is no battery sensor. A literal `0` for either legacy field is
treated by the app as "no sensor", never as a measurement.

**Heart rate** — its own characteristic, notified about once per second:

```
BPM,<bpm>          e.g.   BPM,74      a valid reading
BPM,NONE                              no valid reading (no finger, weak
                                      signal, or no recent beat)
```

Never `BPM,0`. The app treats `NONE`, `0` and any value outside 30–220 as *no
reading* and clears the display; a garbled packet is dropped and the previous
value stays. The characteristic is **optional**: firmware without the pulse
sensor does not expose it, and the app marks heart rate unsupported without
disturbing the other two.

Adding a characteristic changes the glove's GATT table. If a phone that
connected to older firmware never finds the new characteristic, toggle the
phone's Bluetooth once so Android drops its cached service list.

Plain text rather than JSON so it fits in one small BLE notification and needs
no parser on the ESP32.

### 5.3 How the app parses

`GloveClassification.tryParse` returns `null` (drops the reading) on anything
malformed — never throws. Confidence is clamped to 0–1. Unknown labels are
kept verbatim, so a future sixth class shows up as unknown rather than being
mapped to something wrong.

---

## 6. What the app does with the glove

Location: `mobile/lib/features/devices/` (and `…/safety/`, `core/`).

### 6.1 The pieces

| Piece | File | Job |
|---|---|---|
| BLE wrapper | `data/ble_service_flutter_blue_plus.dart` | The **only** file that imports `flutter_blue_plus`. Scan, connect, discover, subscribe. |
| `BlePairingController` | `data/ble_providers.dart` | Drives the pairing sheet, owns the one GATT connection, and **owns reconnection** after a drop. |
| `GloveAutoConnect` | `data/glove_autoconnect_providers.dart` | On app launch, finds the *registered* glove and connects it with no manual step. |
| `GloveLink` | `data/glove_link_providers.dart` | The **one** subscription to each of the classification, telemetry and heart-rate characteristics. Holds the latest readings, including `heartRateBpm` (never 0; null = no reading). |
| Risk score | `data/motion_data_providers.dart`, `domain/models/motion_risk_score.dart` | Derives a glove-local risk number from the latest reading. |
| Threat detector | `domain/glove_threat_detector.dart` | The vote that decides whether to raise an alarm. |
| Auto-trigger | `safety/data/glove_auto_trigger.dart` | Feeds `GloveLink` readings to the detector; publishes an alarm request. |
| Foreground service | `core/background/safety_foreground_service.dart` | Keeps the process alive with the phone pocketed. |
| Detection status | `core/detection/detection_sources.dart` | Tells the UI whether the glove is genuinely watching. |
| UI | `presentation/widgets/device_expandable_card.dart`, `ble_pairing_sheet.dart`, `home/presentation/home_screen.dart` | Device card, pairing sheet, home status. |

All of `GloveLink`, `GloveAutoConnect` and the pairing controller are
activated from `main.dart` so they run for the whole app session, not only
while a particular screen is open.

### 6.2 What the user sees

- **Devices screen → glove card:** a `CONNECTED` / `OFFLINE` status (from the
  live Bluetooth link state), the current class as a label, a large
  **confidence percentage**, a **Risk Score**, a **Heart Rate** section
  (`76 BPM` with the caption *Estimate, not a medical reading*, or `-- BPM`
  when there is no valid reading — never `0 BPM`), and accel / gyro / heart
  readouts. The Heart Rate section and the "Heart" readout read the same
  value.
- **Home screen:** `Glove live` status, the latest class and confidence, and a
  line with accel, gyro and BPM when available.
- **Pairing sheet:** scan → pick device → connect → register. Reconnection
  attempts show `Reconnecting to SafeHer-Glove…`.
- **Foreground notification:** shown while a glove is being listened to. It is
  the honest signal that the phone is watching, and how the user sees it
  stopped.

### 6.3 The Motion Risk Score

A glove-local number, separate from the app's overall Threat Score:

```
risk score = severity(class) × confidence × 100
```

| Class | Severity |
|---|---|
| NORMAL | 0.00 |
| SUDDEN_MOVEMENT | 0.50 |
| SHAKING | 0.50 |
| TWISTING | 0.50 |
| FALL | 1.00 |

Because NORMAL's severity is 0, a confident NORMAL reads 0, not ~100.
`null` (shown as `--`) means "no live reading", not zero.

### 6.4 Threat mapping

`GloveClassification.threatLevel`: `FALL` → danger; `SUDDEN_MOVEMENT` →
elevated; `SHAKING` / `TWISTING` → caution; everything else → safe. This is a
deliberate product decision: only `FALL` is treated as danger, because
`SHAKING` and `TWISTING` happen constantly in ordinary use, and a feature that
phones contacts for a shaken hand gets switched off.

---

## 7. Connection lifecycle (connect, drop, reconnect)

### 7.1 Normal flow

1. **App launch** — `GloveAutoConnect` looks up the registered glove, scans
   (12-second windows, 8-second cooldown between attempts), matches by
   advertised name, then connects **through `BlePairingController`**.
2. `BlePairingController.connect` → connect → discover services → state
   becomes `connected`.
3. `GloveLink` reacts to that state change and subscribes: discover services
   again, find the service and classification characteristic, enable
   notifications, attach a listener. It then does the same for telemetry and
   for heart rate (both optional).
4. Readings flow into `GloveLink` state → UI, risk score, alarm vote.

### 7.2 Drop and automatic reconnect

1. Power off / out of range → the connection-state stream reports
   disconnected → controller state `disconnected` → `GloveLink` clears its
   readings and drops its subscriptions. The UI shows `OFFLINE`.
2. The controller retries every **2 seconds, indefinitely**, until it
   succeeds or the user unpairs. (A power cycle can take any amount of time.)
3. On success the controller state returns to `connected`, which makes
   `GloveLink` resubscribe from scratch (fresh service discovery, fresh
   characteristic objects) — all three characteristics, once each. Heart rate
   is cleared on the drop, so a BPM from before it cannot survive it.

No app restart, no glove reset and no manual reconnect are needed. This
sequence — connect, stream, power off, power on, stream resumes — was verified
on a real glove and phone.

### 7.3 Rules that keep it correct

- **Exactly one reconnect path.** There used to be two independent ones; they
  raced and the loser left the app in the wrong state.
- **Exactly one notification subscription** per characteristic (`GloveLink`).
- **Only one connect at a time.** `BlePairingController.connect` refuses a
  second call while one is in flight, and `GloveAutoConnect` backs off when the
  controller is busy.
- **Never wait on a dead connection's cleanup.** `GloveLink` starts a new
  subscription without awaiting the old one's cancellation.
- **Never call `setNotifyValue(false)` on cleanup.** A characteristic has one
  notification-enable flag on the device, shared by every Dart-side
  subscription to it.
- **Connection state and data-stream state are different things.** `OFFLINE` /
  `CONNECTED` comes from the live Bluetooth link; whether readings are flowing
  is `GloveLink.isListening` and the presence of a reading.

### 7.4 The three bugs behind "Connected but no data" (history)

Kept here because each looks reasonable in isolation and each will come back
if the rules above are relaxed.

1. **Duplicate reconnect loops.** A separate `GloveConnectionManager`
   reconnected the radio directly, without moving the controller's state, so
   `GloveLink` (which resubscribes on the controller's state) never saw a
   change. It usually won the race, so this happened on nearly every power
   cycle. Removed.
2. **Deadlocked resubscribe.** `GloveLink` awaited cancelling the previous
   subscription before starting a new one. On a disconnected peripheral that
   cancellation never completed, so reconnect blocked forever. Fixed by not
   awaiting it.
3. **Notifications switched off after one packet.** The old subscription's
   delayed cleanup called `setNotifyValue(false)`, which — since the
   characteristic's notify flag is shared — turned off the *new* subscription
   too, leaving exactly one packet delivered. Fixed by removing that call.

Also fixed along the way: `GloveLink` treated the `registered` stage as a
disconnect and cancelled its subscription the moment backend registration
finished.

---

## 8. How an alarm is decided

Two independent layers, both must pass.

**Firmware layer** (Section 3.5): low-confidence `FALL` never leaves the
glove.

**App layer** (`GloveThreatDetector`):

| Rule | Value |
|---|---|
| Qualifying reading | classification maps to *danger* (i.e. `FALL`) **and** confidence ≥ the user's threshold |
| User threshold | default **0.75**, adjustable |
| Votes required | **2** qualifying readings |
| Within | **5 seconds** |
| Cooldown after firing | **2 minutes** |
| Disconnect | clears the vote |

One `FALL` alone is a glove dropped on a table or a sleeve caught on a door;
firing on it would make the feature cry wolf.

Even when the vote passes, **nothing is dispatched automatically**. The app
opens the same cancellable countdown a manual SOS gets. An automatic trigger
is never faster, quieter or harder to stop than one the user asked for.

The vote runs in a provider, not a widget, so it keeps running with the screen
off. The foreground service keeps the process alive.

`SUDDEN_MOVEMENT` does **not** auto-trigger (it is the class most likely to be
produced by ordinary handling).

**Effective FALL path today:** the model must score `FALL` ≥ 0.65 (firmware)
**and** ≥ 0.75 by default (app), on two windows within five seconds. Note the
firmware gate only matters for users who set the app threshold below 0.65.

---

## 9. Model quality: measured results

All numbers are 5-fold cross-validation on the **208-recording development
set**, grouped by recording. The locked test set has not been used for any of
these.

### 9.1 Deployed model (v7)

Overall: **accuracy 82.3%, macro F1 0.80.**

| Class | Precision | Recall | F1 |
|---|---|---|---|
| NORMAL | 0.84 | 0.87 | 0.85 |
| SUDDEN_MOVEMENT | 0.83 | 0.87 | 0.85 |
| SHAKING | 0.88 | 0.73 | 0.80 |
| TWISTING | 0.84 | 0.73 | 0.78 |
| FALL | 0.72 | 0.71 | 0.72 |

### 9.2 The important confusions (window counts)

| Confusion | Count |
|---|---|
| FALL → NORMAL (missed fall) | 77 |
| NORMAL → FALL (false fall) | 61 |
| FALL → SUDDEN_MOVEMENT | 71 |
| NORMAL → SUDDEN_MOVEMENT | 80 |
| SUDDEN_MOVEMENT → NORMAL | 75 |

**These are per-window, not per-event.** Because the app needs two `FALL`
windows within five seconds, a real fall does not need every window caught.
Per-window numbers understate event-level behaviour; they are still the right
measure of the model itself.

### 9.3 Why the errors happen (diagnosed, not assumed)

- **Calm parts of labelled recordings.** A whole FALL (or push/pull/jerk)
  recording gets one label, but only part of it is the dramatic moment. The
  misclassified FALL and SUDDEN_MOVEMENT windows have roughly **half the
  motion intensity** of correctly classified ones and are predicted `NORMAL`
  confidently (median 0.84). The model is reading the window correctly; the
  *label* is too coarse. This is a data-labelling problem, not fixable by more
  hyper-parameter tuning.
- **Genuine overlap.** NORMAL windows called `SUDDEN_MOVEMENT` or `FALL` are
  spread across 26+ different recordings, with **low** model confidence
  (≈0.68–0.70) — the model is unsure, not confidently wrong. A quick hand
  movement or a hand dropping produces a sharp jerk spike that resembles the
  first instant of a fall or a sudden movement, while overall motion stays
  normal. This is real ambiguity in a short window, a known hard problem for
  accelerometer-based fall detection.

---

## 10. Known weaknesses

1. **Quick everyday gestures** (reaching, adjusting a bag, lowering a hand)
   are sometimes classed `SUDDEN_MOVEMENT` or `FALL` at low confidence.
2. **~29% of real fall windows are called something else** by the deployed
   model, most dangerously `NORMAL`.
3. **Confidence thresholds are a trade, not a fix.** Measured on the v9
   relabelled data:

| Min. confidence to alert | FALL caught | False FALL alerts | SUDDEN_MOVEMENT caught | False SUDDEN alerts |
|---|---|---|---|---|
| none | 73.9% | 105 | 88.7% | 197 |
| 0.5 | 70.6% | 81 | 86.7% | 176 |
| 0.6 | 66.5% | 56 | 82.6% | 130 |
| 0.7 | 58.2% | 36 | 78.7% | 92 |
| 0.8 | 47.5% | 21 | 72.7% | 65 |

   For `FALL`, every step that halves false alerts also misses more real
   falls. The firmware currently gates both classes at 0.65.
4. **Heart rate is a rough optical estimate** (MAX30102), tuned on synthetic
   signals only, and often reports no reading below ~60 bpm or during motion.
   **No battery monitoring** — that hardware does not exist.
5. **UUIDs are not private** (Section 5.1).
6. **Never tested with a real fall end to end.** See Section 16.

The lever that actually improves things, per the diagnosis above: **better
labelled data** — trim new fall recordings tightly around the impact, mark the
impact window in existing ones, and add many examples of everyday quick
gestures labelled `NORMAL`.

---

## 11. Candidate models (v8, v9)

Both use the same method to correct labels: a window inside a FALL (or
SUDDEN_MOVEMENT) recording is relabelled `NORMAL` **only if** a model that
never saw that recording predicts `NORMAL` for it with confidence ≥ 0.70
(out-of-fold, "confident learning"). Every relabelled window is listed in each
model's `relabeled_windows.json`. Improvement was re-measured on cross-
validation splits **different from** the one used to pick the windows, to rule
out the fix and the measurement sharing a split.

| | Windows relabelled | Accuracy | FALL F1 | SUDDEN_MOVEMENT F1 |
|---|---|---|---|---|
| v7 (deployed) | 0 | 82.3% | 0.72 | 0.85 |
| v8 | 58 (all FALL) | 84.3–85.3% | 0.76–0.79 | ≈0.85 |
| v9 | 92 (58 FALL + 34 SUDDEN_MOVEMENT) | 84.9–86.0% | 0.76–0.77 | 0.86–0.87 |

Location: `glove/ml/models/glove_5class_v8_fall_calm_window_relabel/` and
`glove/ml/models/glove_5class_v9_calm_window_relabel_all/`.

**Status:**

- **Not evaluated on the locked test set.** Cross-validation gains on relabelled
  data are encouraging but partly rest on the assumption that the relabelled
  windows really are calm segments. Spot-check some of them against the raw
  traces before trusting the numbers.
- **Not deployed.** Test firmware folders exist —
  `glove/firmware/SafeHer_Glove_V8_Candidate_OnDevice/` and
  `…V9_Candidate_OnDevice/` — each identical to the production sketch except
  for the model data.
- The first hardware attempt with v8 showed no serial output; that is a
  known ESP32-C3 USB quirk (Section 14), so it produced **no** comparison.
- In hands-on use the current model was preferred; that was an impression,
  not a measurement.
- The correct next steps are: spot-check relabelled windows, then run the
  locked test set **once**, then decide.

---

## 12. Build, flash, run, test

### 12.1 Flash the glove

1. Open `glove/firmware/SafeHer_Glove_V5_OnDevice/SafeHer_Glove_V5_OnDevice.ino`
   in the Arduino IDE.
2. Confirm `DATA_COLLECTION_MODE` is `0`.
3. Board: an ESP32-C3. In **Tools**, set **USB CDC On Boot: Enabled** so
   `Serial` output reaches the USB port.
4. Verify/compile, then upload.
5. Open the Serial Monitor at **115200** baud. Expect the banner, `BLE:
   Advertising started`, and `MPU-6500 detected and initialized.`

To go back to a known-good state at any time, re-upload the production sketch.
The candidate folders never modify it.

### 12.2 Run the app

```
cd mobile
flutter pub get
flutter run                      # debug build — shows [BLE] logs
flutter build apk --release      # release build — NO [BLE] logs
```

**Phone requirements:** Bluetooth on; Nearby-devices / Bluetooth permissions
granted; **Location switched on** (Android will not deliver BLE scan results
with Location off). On Xiaomi/Redmi phones, installing over USB also needs
*USB debugging*, *Install via USB*, and *USB debugging (Security settings)*
enabled in Developer options.

### 12.3 Pair and test

1. Power the glove; confirm it advertises (serial: `BLE: Advertising started`).
2. App → Devices → pair → scan → `SafeHer-Glove` → connect → register.
3. Card shows `CONNECTED`, and confidence/risk update about twice a second.
4. **Power-cycle test:** power off (card shows `OFFLINE`, readings clear),
   power on — it reconnects and readings resume with no other action.

### 12.4 Reading the logs

Debug builds print `[BLE] …` lines. `adb logcat -s flutter:I` filtered on
`[BLE]` shows, in order: `connecting`, `connected`, `pairing state changed`,
`notification subscription started`, `discovering services`,
`SafeHer service found`, `result characteristic found`, `subscribing to
notifications`, `notifications enabled`, `notification listener attached`,
`first notification received`, then `notification received` per packet. On a
drop: `disconnected`, `reconnect attempt N`, `reconnect successful`, and the
whole subscribe sequence again.

**Release builds print none of these** (they are gated behind debug mode). If
logs are empty, check you installed a debug build.

### 12.5 Tests

```
cd mobile
flutter analyze
flutter test test/features/devices/ test/features/safety/data/glove_auto_trigger_test.dart
```

The BLE layer is tested against a fake (`test/test_utils/fake_ble_service.dart`).
The fake can reproduce a subscription whose cancellation never completes
(`hangNextCancellation`), which is the regression test for bug 2 in 7.4. The
real `flutter_blue_plus` behaviour cannot be exercised in unit tests — only on
a device.

---

## 13. Retraining the model

Scripts are in `glove/ml/scripts/`. In order:

| Step | Script |
|---|---|
| Record data (firmware in `DATA_COLLECTION_MODE 1`) | `collect_glove_dataset.py` |
| Windows → 51 features (5-class) | `extract_glove_features_5class.py` (the original 7-class one is `extract_glove_features.py`) |
| Cross-validate the deployed config | `cv_v7_merged_pushpulljerk.py` |
| Train candidate + CV report (no locked-test use) | `train_and_evaluate_v8_…py`, `train_and_evaluate_v9_…py` |
| Convert model → C++ arrays | `convert_v8_to_embedded_arrays.py` / `convert_v9_…py` |

Rules to keep:

- Split by **recording**, never by window.
- Never touch the locked 22-recording test set except for the one official
  comparison.
- Never overwrite the frozen V5 model or an earlier candidate; write new
  candidates to a new directory and record its SHA-256.
- After converting, **copy the generated `.h`/`.cpp` into a sketch folder
  yourself** — the converter does not write into the firmware directory. The
  namespace and the `#include` filename inside the `.cpp` must match the file
  names you use.
- Do not report a candidate as better without a locked-test result.

---

## 14. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| App scan finds nothing | Phone **Location is off**; or `DATA_COLLECTION_MODE` is `1`; or the glove is connected to another phone / a tool like nRF Connect. |
| Serial Monitor shows only `ESP-ROM:esp32c3-api…` | ESP32-C3 native-USB quirk. Reopen the monitor at 115200, press RESET/EN, replug USB, and set **USB CDC On Boot: Enabled**. Not a model or code problem. |
| `Connected` but no data (older builds) | The three bugs in 7.4. Should not recur while the Section 7.3 rules hold. |
| No `[BLE]` logs | Release build. Install a debug build. |
| Reinstall says `INSTALL_FAILED_USER_RESTRICTED` (Xiaomi) | Turn on *Install via USB* and *USB debugging (Security settings)*; keep the phone unlocked; MIUI may reset these after a reboot. |
| Old behaviour after reinstall | Android kept the old process alive. `adb shell am force-stop io.github.akshayag.safeher`, then reopen. |
| Compile error `safeher_vN_model.h: No such file` | The `.cpp`'s `#include` still names the original file after a rename. |
| Firmware works but classes look wrong | Class order / feature order mismatch between model and sketch (Section 1, 3.3). |
| Glove never re-advertises after a drop | Check serial for `BLE: Advertising restarted` on disconnect. |

---

## 15. Stale documentation

These are older than the code. Trust this guide and the code over them.

| File | What is out of date |
|---|---|
| `glove/README.md` | Describes **7 classes**; says the firmware's FALL threshold "does not gate the BLE notification" (it now does); says the glove "was never verified" with a real device (it has been, for connect/stream/reconnect); the "open issue" about zero heart-rate telemetry is fixed in the firmware (it now sends two fields). |
| `glove/docs/SYSTEM_ARCHITECTURE.md` | Describes an older **PC-based** pipeline (serial → Python, dual fall + glove models, 238 Hz). Not the current on-device design. |
| Firmware startup banner | Prints `Classes: 7`. |
| `glove/ml/models/glove_5class_v7_…/esp32_compact/README.md` | Says 7-class. |

---

## 16. Verification status

| Item | Status |
|---|---|
| Sensor read, windowing, on-device inference | Working (in use) |
| BLE advertise, connect, notify | **Verified on a real glove** |
| App subscription, live confidence/risk display | **Verified on a real glove** |
| Power-off / power-on automatic reconnect with data resuming | **Verified on a real glove** |
| Auto-connect on app launch | Verified on a real glove |
| Firmware low-confidence rules for `FALL` and `SUDDEN_MOVEMENT` (3.5) | Written; **not compiled or tested on hardware** |
| App alarm vote (2 in 5 s), countdown, foreground service | Unit-tested against a fake; **never exercised with a real fall** |
| v8 / v9 candidate models | Cross-validated only; **not on hardware, not on locked test set** |
| MAX30102 heart rate (firmware + app) | Firmware compiles in both modes; app logic and reconnect resubscription unit-tested against a fake; beat detector tested on synthetic signals. **Not yet run on a real finger.** |
| Battery | Not implemented (no hardware) |

---

## 17. Repository map

```
glove/
├── README.md                              (partly stale — Section 15)
├── docs/
│   ├── GLOVE_COMPLETE_GUIDE.md            this file
│   └── SYSTEM_ARCHITECTURE.md             (stale)
├── firmware/
│   ├── SafeHer_Glove_V5_OnDevice/         production sketch + model
│   ├── SafeHer_Glove_V8_Candidate_OnDevice/   test build, v8 model
│   └── SafeHer_Glove_V9_Candidate_OnDevice/   test build, v9 model
└── ml/
    ├── dataset/<class>/*.csv              raw recordings
    ├── features/                          51-feature CSVs
    ├── models/                            trained models, splits, reports
    └── scripts/                           collect → extract → train → convert

mobile/lib/
├── main.dart                              activates GloveLink, GloveAutoConnect, pairing
├── core/background/safety_foreground_service.dart
├── core/detection/detection_sources.dart
└── features/
    ├── devices/
    │   ├── domain/glove_protocol.dart         BLE contract, parsers, threat mapping
    │   ├── domain/glove_threat_detector.dart  the alarm vote
    │   ├── domain/models/motion_risk_score.dart
    │   ├── data/ble_service_flutter_blue_plus.dart
    │   ├── data/ble_providers.dart            pairing controller + reconnect
    │   ├── data/glove_autoconnect_providers.dart
    │   ├── data/glove_link_providers.dart     the single subscription
    │   ├── data/motion_data_providers.dart
    │   └── presentation/…                     device card, pairing sheet
    ├── safety/data/glove_auto_trigger.dart    vote → alarm request
    └── home/presentation/home_screen.dart

mobile/test/
├── test_utils/fake_ble_service.dart
└── features/devices/data/glove_link_test.dart, glove_autoconnect_test.dart, …
```
