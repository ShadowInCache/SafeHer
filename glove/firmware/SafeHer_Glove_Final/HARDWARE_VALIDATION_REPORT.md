# SafeHer Glove — Real-Time ESP32-C3 Hardware Validation Report

## FINAL STATUS

**HARDWARE VALIDATION PASS WITH ISSUES**

An ESP32-C3 was connected mid-session (COM3, Espressif USB VID:PID `303A:1001`,
confirming genuine hardware, not a virtual/simulated port). This enabled real,
non-fabricated hardware evidence: passive serial capture of the live data stream,
and — once an Arduino IDE install with `arduino-cli` and the ESP32 core was
located on this machine — actual compilation (verify-only, **no upload was
performed without explicit confirmation**) of the production sketch and both new
diagnostic sketches. See Section 0 for what was actually measured/verified on
real hardware and toolchain, and Section 3 for what still requires flashing +
physical motion testing, which has not been done.

**Headline finding: the production firmware's actual inference code path — the
one that classifies motion and detects FALL — cannot currently be built at all**
with the board's default flash partition scheme (see 0.3). This is a genuine,
previously-undetected firmware/build-configuration bug, found by actually
compiling the code rather than reading it. A fix was identified and verified
(see 0.3) but **not applied** to any file, pending your confirmation.

---

## 0. Real Hardware & Toolchain Findings (this session)

### 0.1 Device confirmed
`COM3`, USB VID:PID `303A:1001` (Espressif Systems) — genuine ESP32-C3 hardware, not simulated.

### 0.2 Passive serial capture — sampling timing (real data, DATA_COLLECTION_MODE=1 path)
The device was already running (whatever was flashed before this session) and streaming
continuously. Listening confirmed it is currently executing `SafeHer_Glove_Final.ino`'s
`DATA_COLLECTION_MODE=1` branch: raw CSV rows `timestamp_ms,Ax,Ay,Az,Gx,Gy,Gz`, exactly
matching the static audit's Section 1.12 finding.

This also **implicitly confirms `WHO_AM_I` passed**: that branch halts in an infinite loop
before any output if the check fails, so continuous well-formed data proves the check
succeeded (device identified as `0x70` as expected) without needing new firmware.

Two capture attempts were made:
- First attempt (`sleep(15)` then one bulk `read()`) showed 559 rows with one 11,420ms gap
  in the device's own `millis()` timestamp sequence. Investigated rather than reported
  at face value: this pattern (sleep-then-bulk-read) can overflow the OS's serial receive
  buffer and silently drop bytes — the surviving rows would still show the real elapsed
  device time across the loss window, exactly matching what was seen.
- Second attempt used continuous small-chunk reads (no sleep-then-bulk-read) to rule this
  out. Result: **2,011 consecutive samples over 20.1s, zero gaps, zero parse errors.**

**Real measured sampling timing (steady-state, continuous-read capture):**
| Metric | Value |
|---|---|
| Samples | 2,011 |
| Mean interval | 10.00 ms |
| Median interval | 10.00 ms |
| Std deviation | 0.122 ms |
| Min interval | 7 ms |
| Max interval | 13 ms |
| Intervals > 15ms | 0 |
| Intervals > 20ms | 0 |
| Effective frequency | 100.00 Hz |

This is excellent, tightly-controlled timing — essentially no jitter. **Caveat:** this
validates the simple single-loop `DATA_COLLECTION_MODE=1` sampling path, not yet the
two-FreeRTOS-task inference-mode sampling path (same 10ms deadline-scheduling logic,
but not identical code, and not yet exercised under the added load of feature
extraction + forest evaluation + BLE running concurrently).

Sensor sanity from the same capture: accel magnitude ≈0.97g (Az-dominant, consistent
with the glove resting roughly level), gyro means near zero with realistic motion
variance (device was being handled, not perfectly still) — physically plausible, no
sign of a stuck/saturated sensor.

### 0.3 ⚠ CRITICAL — inference-mode firmware does not fit in flash (default partition scheme)

An Arduino IDE install with a bundled `arduino-cli` (v1.5.1) and the `esp32:esp32` core
(v3.3.7) was found on this machine, enabling real (verify-only) compilation:

| Sketch | Result |
|---|---|
| `SafeHer_Glove_Final.ino` as-is (`DATA_COLLECTION_MODE=1`) | **Compiles.** 310,268 bytes (23%) flash, 14,364 bytes (4%) RAM |
| `SafeHer_Glove_Hardware_Diagnostic.ino` | **Compiles.** 304,848 bytes (23%) flash, 14,260 bytes (4%) RAM |
| `SafeHer_Glove_Inference_Diagnostic.ino` (default partition scheme) | **FAILS: "Sketch too big."** 1,696,235 bytes (**129%**) of the 1,310,720-byte app partition |

**Root cause, confirmed rather than guessed:** the production sketch only compiles small
because in `DATA_COLLECTION_MODE=1`, nothing calls `evaluate_forest()`, so the linker
strips the entire unused 4,200-tree model data array (`tree_nodes[62804]`) as dead code.
The instant the inference path is actually exercised — which is required for any
classification, FALL detection, or BLE result — the linker must include the full
embedded model, and the binary jumps to 1,696,235 bytes, blowing past the default
"Default 4MB with spiffs (1.2MB APP/1.5MB SPIFFS)" partition's 1,310,720-byte limit by
~385KB.

**This means: as currently structured, the real-time inference firmware cannot be
built and flashed at all with the board's default settings** — not a timing problem,
not a sensor problem, a **flash-space build failure** that would have blocked every
one of Steps 4–9 even after fixing `DATA_COLLECTION_MODE`.

**Verified fix (build configuration only, no source/model changes):** selecting the
"Huge APP (3MB No OTA/1MB SPIFFS)" partition scheme resolves it —

```
arduino-cli compile --fqbn esp32:esp32:esp32c3:PartitionScheme=huge_app <sketch folder>
```

recompiles successfully: 1,696,267 bytes (53% of the 3,145,728-byte huge_app partition).
In the Arduino IDE this is **Tools → Partition Scheme → "Huge APP (3MB No OTA/1MB SPIFFS)"**.
This is a board-menu setting, not a code change — nothing in any `.ino`/`.h`/`.cpp` was
modified to achieve this. **Not yet applied/flashed — flagging for your confirmation
before uploading anything to your device**, since flashing overwrites its current
firmware and I don't know if the current `DATA_COLLECTION_MODE=1` build needs to be
preserved for anything else you're doing with it.

### 0.4 ⚠ SECOND critical finding — "USB CDC On Boot" must be Enabled for this board

After uploading with default board options, **every sketch tested — including a
literally trivial "print a counter once a second" sketch with no I2C/BLE/model at
all — produced zero serial output**, across multiple reset methods (software RTS
reset via upload, `esptool` reset, the board's physical RESET button, and a full
physical USB unplug/replug requested from and performed by the user). `esptool`
itself always worked throughout (chip responsive, MAC `48:f6:ee:30:d1:90`, correct
flash size) — this narrowed the problem to the *application's* use of `Serial`,
not a dead board, bad cable, or bad upload.

Root cause, confirmed by fix, not guessed: `arduino-cli board details -b
esp32:esp32:esp32c3 --full` shows a board option **`USB CDC On Boot`, defaulting to
`Disabled`**. On an ESP32-C3 that only has the native USB-Serial/JTAG peripheral (no
separate UART bridge chip — confirmed via `esptool`'s `USB mode: USB-Serial/JTAG`),
leaving this Disabled means the Arduino `Serial` object never attaches to the USB
endpoint at boot, while the ROM bootloader (which `esptool` talks to) uses that same
USB hardware independently of this setting — exactly matching everything observed.
Recompiling the same minimal test sketch with `CDCOnBoot=cdc` immediately produced
working output.

**This means: `esp32:esp32:esp32c3:CDCOnBoot=cdc` (or in the Arduino IDE: Tools →
USB CDC On Boot → Enabled) is required for every build of every sketch on this
board** — production firmware included — or `Serial` (status output, diagnostics,
everything) will silently do nothing, even though the board runs and I2C/BLE would
otherwise work fine. This was previously undocumented; recommend adding it to the
firmware's build notes so it isn't rediscovered the hard way again. Not applied to
any source file — this is a board-menu/compile-flag setting, not a code change.

### 0.5 Hardware Diagnostic sketch — REAL results (flashed with the two fixes above: `CDCOnBoot=cdc`)

**Part A — MPU-6500 connection check:**
| Item | Result |
|---|---|
| I2C ping | ACK (0) |
| WHO_AM_I | `0x70` (exact match) |
| Post-init test read | OK |
| Sample values | Ax=520 Ay=276 Az=15828 Gx=-270 Gy=371 Gz=49 (physically plausible: Az-dominant ≈0.97g, near-zero gyro) |
| **Result** | **MPU-6500 DETECTED AND INITIALIZED** |

**Part B — sampling timing (1,000 real samples):**
| Metric | Value |
|---|---|
| Samples collected | 1,000 |
| I2C read failures | 0 |
| Total elapsed | 9,991 ms |
| Avg interval | 9,999 µs |
| Min interval | 9,991 µs |
| Max interval | 10,002 µs |
| **Spread (max−min)** | **11 µs** |
| Approx frequency | **100.01 Hz** |
| Intervals > 15ms | 0 |
| Intervals > 20ms | 0 |

This is essentially perfect — sub-11-microsecond total jitter across 1,000 samples. Even tighter than the earlier passive-listen capture (which included some `DATA_COLLECTION_MODE` CSV-print overhead interleaved into the loop); this diagnostic's tighter single-purpose loop shows the sampling logic itself has negligible jitter.

**Part D — buffering / lost-sample check (500 samples, 9 window handoffs):**
All 9 windows contiguous (`seq[0..99]`, `seq[50..149]`, `seq[100..199]`, ... `seq[400..499]`), **zero gaps detected**. Confirms the 100-sample-window/50-sample-step ping-pong buffering logic (identical to production's) loses no samples on real hardware.

### 0.6 Inference Diagnostic sketch — REAL results (flashed with `CDCOnBoot=cdc,PartitionScheme=huge_app`)

Compiled at 1,712,929 bytes (54% of the 3,145,728-byte huge_app partition), uploaded, and run live.

**One transient issue observed then not reproduced:** on the very first boot after flashing, `WHO_AM_I` read `0xFF` (I2C read failure) and the sketch correctly halted rather than proceeding with bad data. A subsequent reset succeeded (`WHO_AM_I = 0x70`) and ran cleanly through 25+ inference cycles with zero further I2C errors. Logged under Section 3 as an open item — worth watching for recurrence during the longer stability run, but not treated as resolved just because it didn't repeat once.

**Real per-window inference timing** (device stationary on a desk, connected via USB — this is why every window classified NORMAL; no motion tests performed yet):

| Window | class | confidence | feature_us | forest_us | total_us | interval_since_last_ms |
|---|---|---|---|---|---|---|
| 1 | NORMAL | 0.995 | 6,269 | 24,804 | 31,073 | 1,023 (first, includes startup) |
| 2–25 | NORMAL | 0.993–0.995 | 6,263–6,355 | 24,773–24,922 | 31,045–31,191 | 500 (steady-state, every one) |

**Consistent, real measurements across 25 windows:**
- Feature extraction: **~6.3 ms**
- Forest evaluation (4,200 trees): **~24.8 ms**
- Total inference: **~31.1 ms**
- Time between inference outputs: **exactly 500 ms**, matching the 50-sample step at 100Hz — confirms inference throughput easily keeps up with the ~500ms window cadence (31ms used out of a 500ms budget, ~6% duty cycle).

**Sampling-during-inference (the critical question):**
```
SAMPLING: samples=500 avg_dt_us=10000 min_dt_us=9833 max_dt_us=10191 close=500 late=0
late_samples_during_inference=0
SAMPLING: samples=500 avg_dt_us=9999  min_dt_us=9833 max_dt_us=10234 close=500 late=0
late_samples_during_inference=0
```
**Zero late samples, and zero of those coincided with an in-flight inference, across 1,000 samples spanning ten full inference cycles.** This directly confirms the two-FreeRTOS-task design achieves its goal: even though forest evaluation takes a real, non-trivial ~25ms on this single-core chip, the higher-priority sampling task is never delayed by it. **Sampling stays at 100Hz during inference — no synchronous-inference sampling-gap problem was found.**

Confidence for NORMAL while stationary (0.993–0.995) is very high and stable — no unexpected class or FALL prediction seen at rest, though this alone doesn't test the false-FALL question (Step 6) properly, since it's only one static posture; see Section 3 for the still-needed varied-motion NORMAL testing.

### 0.7 Still not done
Steps 5–9 (per-class motion tests including JERK/PUSH/PULL/SHAKING/TWISTING, varied NORMAL activities, simulated FALL, BLE-connected behavior, long-duration stability) require physically moving the glove while it runs — not something that can be done without a person handling the device. In progress with the user.

---

## 1. Static Code Audit (Step 1 & Step 2) — completed

Full read of `firmware/SafeHer_Glove_Final/SafeHer_Glove_Final.ino` (794 lines).

### 1.1 MPU-6500 / I2C
| Item | Finding |
|---|---|
| I2C address | `0x68` (`MPU_ADDR`) — matches spec |
| WHO_AM_I register | `0x75`, expected value `0x70` — matches spec |
| Initialization | `initializeMPU6500()`: `PWR_MGMT_1=0x00` (wake), 100ms delay, `ACCEL_CONFIG=0x00` (±2g, 16384 LSB/g), `GYRO_CONFIG=0x00` (±250°/s, 131 LSB/(°/s)), 100ms delay |
| WHO_AM_I verification | Read before init; if ≠ `0x70`, firmware halts in an infinite `delay(1000)` loop (both in `DATA_COLLECTION_MODE` and inference-mode branches of `setup()`) |
| Raw read | Burst-reads 14 bytes from `ACCEL_XOUT_H`: AxH/L, AyH/L, AzH/L, TempH/L (read and discarded), GxH/L, GyH/L, GzH/L |

### 1.2 Sampling mechanism
- `SAMPLE_INTERVAL_US = 10000` (10ms → 100Hz target).
- **Inference-mode path** (`DATA_COLLECTION_MODE=0`): a dedicated high-priority FreeRTOS task (`samplingTask`, priority 3) runs a deadline-scheduled loop — sleeps via `vTaskDelay(1)` while slack > 1ms, then busy-polls the final <1ms for precision — and reads the sensor only when the 10ms deadline has passed. This task does **no** feature extraction, model inference, or Serial I/O, by design, so nothing on that path can delay the next sample.
- **Data-collection-mode path** (`DATA_COLLECTION_MODE=1`): the same deadline-scheduling pattern runs directly in `loop()` (no FreeRTOS task split needed since nothing else runs concurrently), streaming raw CSV rows.

### 1.3 Window buffering / 50-sample stride
- Live arrays `axWindow..gzWindow[100]` filled sample-by-sample by the sampling task.
- On reaching `WINDOW_SIZE=100`, the window is `memcpy`'d into one of two ping-pong `SensorWindow` snapshot buffers and handed to `inferenceTask` via a depth-2 FreeRTOS queue; the sampling task then shifts the last `OVERLAP=50` samples to the front and continues filling from index 50 — implementing the 50-sample step correctly. A new inference becomes due every 50 new samples (~500ms at 100Hz).
- Non-blocking handoff: if the inference task hasn't yet consumed a slot (shouldn't happen given forest evaluation is expected to take single-digit-to-tens of ms against a 500ms window period), that window's handoff is skipped rather than corrupting a buffer still being read — sampling itself is never blocked either way.

### 1.4 Feature calculation
`extractWindowFeatures()` — **re-verified in this session, unchanged from the prior model/firmware audit**: computes `[mean, std, min, max, range, rms]` for Ax, Ay, Az, Gx, Gy, Gz (36 values), then the same 6 stats for `acc_mag=sqrt(Ax²+Ay²+Az²)` and `gyro_mag=sqrt(Gx²+Gy²+Gz²)` (12 values), then `jerk = diff(acc_mag)` reduced to `[jerk_mean, jerk_std, jerk_max]` (3 values) = **51 features**, in the exact order Python's `extract_glove_features.py` produces. Variance is population variance (`/= len`, matching numpy's `ddof=0` default); RMS = `sqrt(mean(x²))`; range = max−min.

### 1.5 Model inference
- `SafeHer::V5Embedded::evaluate_forest(features, scores)` — the 4,200-tree embedded model. Previously verified node-for-node (all 62,804 nodes) as an exact structural match to `safeher_glove_7class_v5_xgboost.json`, with matching base scores and round-robin class ordering (`tree_id % 7`) confirmed against the JSON's own `tree_info` array. This audit did not re-run that check (out of scope here) but re-confirms the `.ino` calls it exactly as previously documented, with no wrapper/threshold logic inserted between feature extraction and the model call.
- `predict_class(scores)` — plain argmax.
- `predict_confidence(scores)` — softmax probability of the argmax class only (not the full 7-class vector).

### 1.6 FALL decision logic
- `FALL_CONFIDENCE_THRESHOLD = 0.65f`.
- `applyFallConfirmation()`: if predicted class ≠ FALL (index 6), the debounce counter resets to 0 and the function returns `"SAFE"` (NORMAL) or `"ABNORMAL"`. If predicted class == FALL: counter increments only when confidence ≥ 0.65, else resets to 0. Escalates to `"HIGH_RISK"` only after **2 consecutive qualifying hits**; a single hit (or a hit below threshold) reports `"ABNORMAL"`.

### 1.7 BLE
Only initialized when `DATA_COLLECTION_MODE=0`. Two characteristics: a classification-result characteristic (`"<CLASS>,<confidence>"`, notified after every inference) and a telemetry characteristic (`"<accelMagG>,<gyroMagDps>"`, notified every 500ms). Telemetry values are computed cheaply inside the sampling task (no I/O there); the actual `notify()` calls run from the lower-priority inference/output task, keeping BLE I/O off the sampling-critical path. Auto-restarts advertising on disconnect.

### 1.8 Serial output
Inference mode: startup banner, WHO_AM_I hex, `printStatus()` per inference (`SAFEHER STATUS: NORMAL` / `ABNORMAL` + `Motion: <class>`), plus a sampling-diagnostics dump every 500 samples (~5s) — all printed only from the (low-priority) inference task, never the sampling task. `VERBOSE_DEBUG=0` by default (suppresses an extra raw-feature/RAW+SAFETY debug dump). Data-collection mode: continuous raw CSV rows, plus `SENSOR_BAD,...`/`SENSOR_BAD_TOTAL,...` lines whenever a raw reading hits an int16 endpoint (0x8000/0x7FFF — typically indicates an I2C glitch).

### 1.9 Vibration / buzzer output
**Not present.** No motor, buzzer, or dedicated GPIO alert output exists anywhere in this file. `HIGH_RISK`/`FALL` states are only surfaced via Serial print and BLE notify — there is no local physical alert on the glove itself.

### 1.10 MAX30102 (heart-rate/SpO2)
**Not present.** No driver, I2C handling, or related code found anywhere in this file.

### 1.11 ML pipeline consistency (Step 2)
| Item | Python (reference) | Firmware | Match |
|---|---|---|---|
| Sampling rate | 100Hz | `SAMPLE_INTERVAL_US=10000` → 100Hz | ✓ |
| Window size | 100 | `WINDOW_SIZE=100` | ✓ |
| Step size | 50 | `OVERLAP=50` | ✓ |
| Feature count | 51 | `FEATURE_COUNT=51` | ✓ |
| Feature order/formulas | canonical | verified identical | ✓ |
| Class order | NORMAL,JERK,PUSH,PULL,SHAKING,TWISTING,FALL | `CLASS_NAMES[]` identical | ✓ |
| Model | V5, 4,200 trees | embedded, previously verified exact | ✓ |
| New features/filtering/normalization/thresholds | — | none added | ✓ (nothing changed) |

**No changes were made to any of these.**

### 1.12 ⚠ Critical finding not previously flagged: production firmware is currently in DATA-COLLECTION mode

`SafeHer_Glove_Final.ino` line 46: **`#define DATA_COLLECTION_MODE 1`**.

With this value, `setup()` only verifies `WHO_AM_I` and initializes the MPU — it does **not** initialize BLE and does **not** create the sampling/inference FreeRTOS tasks. `loop()` under this mode streams raw CSV rows (`timestamp_ms,Ax,Ay,Az,Gx,Gy,Gz`), exactly like the original dataset-collection sketches. **As currently configured, flashing this exact file will not run any classification, FALL detection, or BLE — it is a raw data logger.**

This was left unchanged per the "do not modify the frozen model/firmware" instruction — it is not something I should silently flip on production. **You must change `DATA_COLLECTION_MODE` to `0` yourself and reflash before any of the Steps 4–9 physical inference/BLE/FALL tests are possible on `SafeHer_Glove_Final.ino`.** (The two new diagnostic sketches below are unaffected by this — the hardware-only one has no such mode, and the inference diagnostic defaults to inference mode.)

---

## 2. New Diagnostic Sketches Created (Step 3 & Step 4)

Two new, self-contained Arduino sketches — each in its **own** sketch folder, because Arduino's toolchain concatenates every `.ino` file inside a folder into one compilation unit; putting a second `setup()`/`loop()` inside `SafeHer_Glove_Final/` would have broken that sketch's build.

1. **`firmware/SafeHer_Glove_Hardware_Diagnostic/SafeHer_Glove_Hardware_Diagnostic.ino`**
   Sensor/timing only — no model, no BLE. Checks I2C ping + WHO_AM_I + a post-init test read; collects 1,000 samples measuring avg/min/max interval, approximate Hz, and counts of intervals >15ms / >20ms; prints raw IMU values every 50th sample (not every sample, to avoid perturbing timing); runs a 500-sample buffering/no-lost-samples check using the same 100/50 window-and-overlap logic as production, verifying window sequence numbers are contiguous with no gaps.

2. **`firmware/SafeHer_Glove_Inference_Diagnostic/SafeHer_Glove_Inference_Diagnostic.ino`**
   Full inference pipeline — same two-FreeRTOS-task architecture, same MPU-6500 setup, same 51-feature extraction, same embedded model, same FALL debounce as production, always in inference mode. Adds per-inference `SAFEHER INFERENCE window=<n> class=<c> confidence=<f> safety=<s> feature_us=<t> forest_us=<t> total_us=<t> interval_since_last_ms=<t>` output, and reuses the same sampling-timing counters as production plus a new `late_samples_during_inference` counter that specifically flags whether a late sample ever coincided with an in-flight inference — the direct test of whether inference causes sampling gaps.
   Model files (`safeher_glove_final_model.h`/`.cpp`) were **copied verbatim** into this new folder (SHA-256 verified identical to the originals before writing this report) so the sketch compiles standalone, without touching the production copies.

**Neither sketch has been compiled.** No `arduino-cli`/PlatformIO toolchain was available in this environment (checked). Only a brace/parenthesis balance check was run (both files balanced) — this is not a substitute for an actual build. **Compile and verify both before flashing.**

---

## 3. Sections requiring physical hardware — NOT PERFORMED

Per your explicit instruction, these are not fabricated. Each needs the real ESP32-C3 + MPU-6500 running the sketches above (with `DATA_COLLECTION_MODE=0` on the production file, or either new diagnostic sketch).

| # | Item | Status |
|---|---|---|
| 2 | MPU-6500 communication result | HARDWARE TEST NOT PERFORMED |
| 3 | WHO_AM_I result (actual read value) | HARDWARE TEST NOT PERFORMED |
| 4 | Actual sampling frequency | HARDWARE TEST NOT PERFORMED |
| 5 | Sampling jitter | HARDWARE TEST NOT PERFORMED |
| 6 | Dropped/late samples | HARDWARE TEST NOT PERFORMED |
| 7 | Feature extraction timing | HARDWARE TEST NOT PERFORMED |
| 8 | XGBoost (forest evaluation) timing | HARDWARE TEST NOT PERFORMED |
| 9 | Total inference timing | HARDWARE TEST NOT PERFORMED |
| 10 | Inference frequency | HARDWARE TEST NOT PERFORMED |
| 11 | Memory usage (heap/stack) | HARDWARE TEST NOT PERFORMED |
| 12 | Stability test duration | HARDWARE TEST NOT PERFORMED |
| 13 | BLE stability | HARDWARE TEST NOT PERFORMED |
| 14–20 | Per-class (NORMAL/JERK/PUSH/PULL/SHAKING/TWISTING/FALL) behavior | HARDWARE TEST NOT PERFORMED |
| 21 | False FALL observations | HARDWARE TEST NOT PERFORMED |
| 22 | HIGH_RISK confirmation observations | HARDWARE TEST NOT PERFORMED |
| 23 | Firmware errors (crashes, Guru Meditation, I2C errors, BLE disconnects) | HARDWARE TEST NOT PERFORMED |

## 4. Category breakdown, once hardware testing is done

To keep future findings easy to triage, classify anything observed under:
- **ML/model issues** — wrong class predicted given a clearly-labeled motion, confidence behaving inconsistently with training-time expectations.
- **Firmware timing issues** — sampling interval drifting from 10ms, inference blocking sampling, missed windows.
- **Sensor issues** — WHO_AM_I mismatch, I2C NACKs, raw values stuck at int16 endpoints (`SENSOR_BAD` in data-collection mode).
- **BLE issues** — failed connects, dropped notifications, advertising not resuming after disconnect.
- **Hardware/power issues** — resets, brownouts, Guru Meditation errors, watchdog triggers.

Static audit alone found no code path that obviously conflates these categories, but only real hardware runs can populate this table.
