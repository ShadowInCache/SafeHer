<title>FALL Confirmation 3-Hit Debounce — Controlled Firmware Experiment</title>

## Scope
Firmware-only change. Nothing else touched.

- **Model**: `safeher_glove_7class_v5_xgboost.json` — untouched (not loaded, not read, not re-evaluated by this change).
- **Locked test set**: untouched.
- **FALL confidence threshold**: unchanged, still `0.65` (`FALL_CONFIDENCE_THRESHOLD` in `SafeHer_Glove_Final.ino`, not modified).
- **Sampling, windowing, feature extraction, BLE**: unchanged — no other function in `SafeHer_Glove_Final.ino` was touched.

## File changed
`glove/firmware/SafeHer_Glove_Final/SafeHer_Glove_Final.ino` — one function only, `applyFallConfirmation()`.

## Exact change

**Before (2-hit, current production behavior):**
```cpp
// Unchanged FALL-confirmation algorithm (2-hit debounce at >= threshold).
const char* applyFallConfirmation(int predictedClass, float confidence) {
  if (predictedClass != 6) {
    fallConfirmationCount = 0;
    return (predictedClass == 0) ? "SAFE" : "ABNORMAL";
  }

  if (confidence >= FALL_CONFIDENCE_THRESHOLD) {
    fallConfirmationCount++;
  } else {
    fallConfirmationCount = 0;
  }

  return (fallConfirmationCount >= 2) ? "HIGH_RISK" : "ABNORMAL";
}
```

**After (3-hit, experimental):**
```cpp
// EXPERIMENTAL: 3-hit debounce at >= threshold (was 2-hit). See
// firmware/SafeHer_Glove_Final/FALL_CONFIRMATION_3HIT_EXPERIMENT.md for the
// rationale, the offline simulation this was based on, and how to revert.
const char* applyFallConfirmation(int predictedClass, float confidence) {
  if (predictedClass != 6) {
    fallConfirmationCount = 0;
    return (predictedClass == 0) ? "SAFE" : "ABNORMAL";
  }

  if (confidence >= FALL_CONFIDENCE_THRESHOLD) {
    fallConfirmationCount++;
  } else {
    fallConfirmationCount = 0;
  }

  return (fallConfirmationCount >= 3) ? "HIGH_RISK" : "ABNORMAL";
}
```

**The only change is the literal `2` → `3` on the return line**, plus an updated comment. Every reset condition was already correct and required no change:
- `predictedClass != 6` (not FALL) → resets `fallConfirmationCount` to 0 and returns `SAFE`/`ABNORMAL`. Unchanged.
- `predictedClass == 6` (FALL) but `confidence < FALL_CONFIDENCE_THRESHOLD` → resets `fallConfirmationCount` to 0. Unchanged.
- Only a run of qualifying FALL predictions (class == FALL **and** confidence ≥ 0.65) increments the counter; any non-qualifying prediction breaks the run. This was already true before this change and is unchanged.

No other line, function, constant, or file was modified.

## Current (2-hit) behavior
A single qualifying FALL window (confidence ≥ 0.65) reports `ABNORMAL`. A **second consecutive** qualifying FALL window (the very next inference, ~500ms later) escalates to `HIGH_RISK`. Any non-qualifying window in between resets the count to zero.

## Experimental (3-hit) behavior
Same qualifying rule, but escalation to `HIGH_RISK` now requires **three consecutive** qualifying FALL windows (~1s of sustained ≥0.65-confidence FALL predictions) instead of two. A run of exactly 2 qualifying windows now reports `ABNORMAL` only, where it previously reported `HIGH_RISK`.

## Why 3-hit specifically (not 4-hit, not smoothing)
From the offline temporal simulation performed earlier on 198 development recordings using the actual production V5 model's real predictions (`ml/models/false_fall_temporal_analysis/temporal_analysis_report.json`):

| Rule | NORMAL recordings → false HIGH_RISK | FALL recordings missed entirely |
|---|---|---|
| 2-hit (current) | 6 / 53 | 0 / 35 |
| **3-hit (this experiment)** | **2 / 53** | **3 / 35** |
| 4-hit | 2 / 53 | 5 / 35 |

3-hit was chosen because 4-hit gives no further reduction in false NORMAL alarms over 3-hit (both land at 2/53) while costing two additional missed FALL recordings — 4-hit is strictly dominated by 3-hit and was not worth implementing. Probability smoothing was evaluated as an alternative in the same analysis and rejected for this experiment because, unlike a hit-count change, it also alters ~25–29% of PUSH/PULL and ~15% of TWISTING/JERK predictions (it operates on the full probability vector, not just the FALL decision path) — a much broader intervention than requested here.

Two NORMAL recordings (`normal_043`, `normal_056`) have qualifying-FALL bursts of 8 and 5 consecutive windows respectively and will still trigger `HIGH_RISK` under 3-hit (or any hit-count up to 4) — this experiment does not, and cannot, fully eliminate false HIGH_RISK events by itself.

## Build verification
Compiled (verify only, **not flashed**) with `arduino-cli compile --fqbn esp32:esp32:esp32c3:CDCOnBoot=cdc`:
```
Sketch uses 327156 bytes (24%) of program storage space. Maximum is 1310720 bytes.
Global variables use 15552 bytes (4%) of dynamic memory, leaving 312128 bytes for local variables. Maximum is 327680 bytes.
```
Compiles cleanly, same size class as the unmodified sketch verified earlier this session — as expected for a single-character logic change.

## Model / feature-extraction confirmation
- `safeher_glove_7class_v5_xgboost.json`: not opened, read, or referenced by this change.
- `extractWindowFeatures()`, `computeStats()`, `addStats()`, and every constant governing sampling/window/step (`SAMPLE_INTERVAL_US`, `WINDOW_SIZE`, `OVERLAP`, `FEATURE_COUNT`): byte-identical to before this change (only `applyFallConfirmation()` was edited).
- `FALL_CONFIDENCE_THRESHOLD`: unchanged (`0.65f`).
- BLE (`initializeBLE()`, `notifyClassification()`, `sendTelemetry()`): unchanged.

## Status
**Not flashed.** Compiled and verified only, per instructions. Flash explicitly when ready to test on hardware.

## Revert
Change the `3` back to `2` on the `return (fallConfirmationCount >= 3) ? "HIGH_RISK" : "ABNORMAL";` line (and optionally restore the original comment) to return to the exact original 2-hit behavior.
