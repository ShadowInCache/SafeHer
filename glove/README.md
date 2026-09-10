# SafeHer Smart Glove

An ESP32-C3 and an MPU-6500 that classify hand motion **on the device** and
tell the phone what they saw over BLE. No server is in the path.

This matters more than it sounds. Every other detection modality in SafeHer
depends on a backend model that is not trained, so nothing produces a score.
The glove is the one detector that actually works today — which is why the
app treats a connected glove as active detection even when the backend
reports that none of its own models are ready.

```text
glove/
├── firmware/
│   ├── SafeHer_Glove_Final/                The production sketch, hardware-validated
│   │   ├── SafeHer_Glove_Final.ino         Sampling, windowing, inference, BLE
│   │   ├── safeher_glove_final_model.h     Generated — do not hand-edit
│   │   ├── safeher_glove_final_model.cpp   Generated — do not hand-edit
│   │   ├── FALL_CONFIRMATION_3HIT_EXPERIMENT.md
│   │   └── HARDWARE_VALIDATION_REPORT.md   Real ESP32-C3 findings (2026-09-10)
│   ├── SafeHer_Glove_Hardware_Diagnostic/  Sensor + timing only, no model/BLE
│   ├── SafeHer_Glove_Inference_Diagnostic/ Full pipeline, per-window timing
│   ├── SafeHer_Glove_Failure_Capture/      Captures the raw stream around a fault
│   └── SafeHer_Glove_V5_OnDevice/          Earlier on-device sketch (superseded)
├── ml/
│   ├── dataset/          Raw labelled recordings, one folder per class
│   ├── features/         glove_7class_features.csv — 51 features per window
│   ├── models/           Trained XGBoost model + column/label/split metadata
│   └── scripts/          Collect → extract → train → evaluate → convert
└── requirements.txt      Python deps for the ML pipeline
```

The embedded model is still the V5 7-class XGBoost (4,200 trees, 51 features);
`safeher_glove_final_model.{h,cpp}` is that same model compiled into C arrays,
verified node-for-node against `safeher_glove_7class_v5_xgboost.json`.

---

## How it works

| | |
|---|---|
| **Sensor** | MPU-6500 over I²C, `WHO_AM_I` = `0x70` |
| **Sampling** | 100 Hz |
| **Window** | 100 samples (1 s), 50-sample overlap → a classification every 0.5 s |
| **Features** | 51 per window — mean, std, min, max, range, RMS across six axes |
| **Model** | XGBoost, 7 classes, converted to C arrays and compiled into the sketch |
| **Output** | BLE notify, `"<LABEL>,<confidence>"` — e.g. `FALL,0.93` |

The seven classes, in the order the firmware indexes them:

```
NORMAL  JERK  PUSH  PULL  SHAKING  TWISTING  FALL
```

**That order is part of the wire contract**, not a presentation detail. The
firmware notifies a label by indexing `CLASS_NAMES` with the model's predicted
class, so reordering the array would silently deliver a fall to the app under
another word.

### What the app does with it

Only `FALL` maps to danger. `PUSH` and `PULL` are elevated; `JERK`, `SHAKING`
and `TWISTING` stay at caution, because all three happen constantly in
ordinary life — a bag lifted, a hand dried, a jar opened.

The app raises an alarm on **two qualifying FALLs within five seconds**, each
at or above the user's confidence threshold (default 0.75). One `FALL` alone
is a glove dropped on a table or a sleeve caught on a door. Firing on it would
make the feature cry wolf, and a feature that cries wolf gets switched off — at
which point it protects nobody.

Even then it does not dispatch. It opens the same cancellable countdown a
manual SOS gets. An automatic trigger must never be faster, quieter, or harder
to stop than one the user asked for.

The firmware's own `FALL_CONFIDENCE_THRESHOLD` (0.65) gates only the serial
`FALL CONFIRMED` message. **It does not gate the BLE notification** — the app
receives raw predictions and applies its own threshold and vote.

---

## The two modes

`DATA_COLLECTION_MODE` at the top of the sketch decides which firmware you have.

| Mode | BLE | Serial | Use |
|---|---|---|---|
| `0` | Initialised, advertises, notifies | Diagnostics | Normal operation, and anything involving the app |
| `1` | **Never initialised** | Raw CSV at 100 Hz | Recording training data |

Leave it at `1` and the glove will never advertise. The app will scan forever
with nothing visibly wrong, which is a confusing hour if you don't know to
check this first.

---

## The pipeline

```bash
pip install -r glove/requirements.txt
pip install pyserial          # needed by the collector, not in requirements.txt

python glove/ml/scripts/collect_glove_dataset.py      # DATA_COLLECTION_MODE 1
python glove/ml/scripts/extract_glove_features.py
python glove/ml/scripts/train_glove_7class_xgboost_v5.py
python glove/ml/scripts/evaluate_v5.py
python glove/ml/scripts/convert_v5_to_embedded_arrays.py
```

`evaluate_v5.py` is the one that matters. Per-window accuracy is not the
product; the product is whether a fall raises an alarm and an ordinary
afternoon doesn't. It simulates the app's real rule against held-out
**recordings** — never held-out windows, because consecutive windows overlap by
50 samples and splitting on them would report a score the model has not
earned — and prints three things:

- FALL recordings that would be **missed** → someone hurt with no alarm raised
- non-FALL recordings that would **false alarm** → contacts phoned for nothing
- **which recordings** produce confident FALL windows → your next collection list

That third section closes the loop. A recording misread at 0.9-plus confidence
cannot be fixed by moving a threshold; it needs more data of that kind.

### Two traps in the pipeline

**The scripts disagree about where the model lives.** Training writes to
`ml/models/glove_7class/`. Evaluation reads from `ml/models/`. The converter
reads `glove_7class/` again. Retrain and evaluate without copying the four
artifacts up a level and you will score the *old* model and never know.

**The converter does not write into the firmware folder.** It writes to
`ml/models/glove_7class/esp32_v5_compact/`, and nothing picks the files up for
you — copy `safeher_v5_model.h` and `.cpp` into the sketch directory yourself.

A full bench procedure, including what to record and how to verify the glove
against the app end to end, is in the runbook rather than here.

---

## Dataset

| Class | Recordings |
|---|---|
| normal | 40 |
| fall | 25 |
| jerk, pull, push, shaking, twisting | 15 each |

Each file is `timestamp_ms,Ax,Ay,Az,Gx,Gy,Gz,label` at 100 Hz, holding **raw
int16 sensor counts** — not values converted to g and dps. The firmware feeds
the model raw counts too, so the two agree; converting on one side only would
silently ruin every prediction.

Known gaps, named by the evaluation harness rather than guessed at:

- `normal_020` produces 7 of 38 windows as `FALL` at up to 0.987 confidence.
- `fall_018` is marginal — it only just clears the vote at 2 qualifying
  windows out of 9.

More `NORMAL` resembling the first, and more falls resembling the second, is
what the model needs next.

---

## Status

**Working:** on-device inference, BLE classification, BLE telemetry, the app's
subscription and vote, and the foreground service that keeps all of it alive
with the phone in a pocket.

**Validated on real hardware (2026-09-10):** an ESP32-C3 was exercised directly
— MPU-6500 detected (`WHO_AM_I` `0x70`), sampling holds 100 Hz with sub-11µs
jitter, and on-device 7-class inference runs at ~31 ms/window (feature ~6.3 ms +
forest ~24.8 ms) with the sampling task never starved during inference. Full
evidence and method in
[`firmware/SafeHer_Glove_Final/HARDWARE_VALIDATION_REPORT.md`](firmware/SafeHer_Glove_Final/HARDWARE_VALIDATION_REPORT.md).

**Two build settings that report as software faults** (found by actually
compiling): the inference build overflows the default flash partition — select
**Huge APP (3MB No OTA)** — and **USB CDC On Boot** must be **Enabled** or
`Serial` is silent on this board. The production sketch also still ships in
`DATA_COLLECTION_MODE=1` (raw logger); set it to `0` and reflash before any
classification/FALL/BLE test.

**Not implemented:** heart rate and battery. The firmware has no pulse sensor
and no battery monitoring.

**Still never verified:** physical motion/FALL behaviour, BLE-connected
behaviour, and pairing with the app. No physical glove has been paired with the
phone; every app-side test runs against a fake BLE service. Bench procedure:
[`docs/HARDWARE_BRINGUP.md`](../docs/HARDWARE_BRINGUP.md).

---

## Open issue

`sendTelemetry` sends four fields with `heartRateBpm` and `batteryPercent`
hardcoded to `0`, under a comment explaining that it is *avoiding* fabricating
unverified sensor data. The intent is right and the encoding defeats it: on
this wire, omitting a field means "I don't measure this", while a literal `0`
means "I measured zero" — which for a heart is a claim nobody should make by
accident.

The fix is to send only the two fields it measures:

```c
snprintf(telem, sizeof(telem), "%.2f,%.1f", accelMagnitudeG, gyroMagnitudeDps);
```

The app already parses a short payload as "unknown" and renders an em dash, so
no app change is needed when this lands. In the meantime the app also treats a
zero heart rate and a zero battery as absent on its own account — it does not
get to choose what firmware it meets, and no wearer has a heart rate of zero.

---

## The UUIDs are not private

The service and classification UUIDs are the stock ones from the Arduino
`BLE_notify` example, so any other project built from that sample advertises
the same service. Generated replacements are recorded in
`GloveBle.suggestedPrivateServiceUuid` for whenever the firmware is being
reflashed anyway. Changing them is a coordinated change on both sides, which is
why it is written down rather than quietly swapped.
