#!/usr/bin/env python3
"""Companion to firmware/SafeHer_Glove_Failure_Capture/. Does two things:

1. Prints the recommended physical test protocol (which segments to run, in
   what order, with the exact "LABEL <name>" command to send before each).
2. Parses a captured serial log (WINDOW_ROW / RAW_ROW lines, redirected to a
   text file while running the capture sketch) into two pandas-ready CSVs
   for analysis: one row per window (features+probabilities+label) and one
   row per raw sample (Ax..Gz+label), ready to feed into the same kind of
   analysis already used elsewhere in this project.

Does not touch the model, firmware, dataset, or any existing file. Produces
output only where you explicitly point --out.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pandas as pd

LABELS = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]
FEATURE_COLS = [
    "Ax_mean", "Ax_std", "Ax_min", "Ax_max", "Ax_range", "Ax_rms",
    "Ay_mean", "Ay_std", "Ay_min", "Ay_max", "Ay_range", "Ay_rms",
    "Az_mean", "Az_std", "Az_min", "Az_max", "Az_range", "Az_rms",
    "Gx_mean", "Gx_std", "Gx_min", "Gx_max", "Gx_range", "Gx_rms",
    "Gy_mean", "Gy_std", "Gy_min", "Gy_max", "Gy_range", "Gy_rms",
    "Gz_mean", "Gz_std", "Gz_min", "Gz_max", "Gz_range", "Gz_rms",
    "acc_mag_mean", "acc_mag_std", "acc_mag_min", "acc_mag_max", "acc_mag_range", "acc_mag_rms",
    "gyro_mag_mean", "gyro_mag_std", "gyro_mag_min", "gyro_mag_max", "gyro_mag_range", "gyro_mag_rms",
    "jerk_mean", "jerk_std", "jerk_max",
]

# Order matters only for the printed protocol - the sketch accepts any label
# text; nothing here is enforced by firmware.
PROTOCOL = [
    ("NORMAL_WALK", "Walk normally for ~30-45s, glove worn as intended.", 45),
    ("NORMAL_PICKUP", "Repeatedly pick up and set down a small object, ~30s.", 30),
    ("NORMAL_SIT_STAND", "Sit down and stand up repeatedly, ~30s.", 30),
    ("NORMAL_ARM_MOVEMENT", "Casual/relaxed arm movement, reaching, gesturing, ~30s.", 30),
    ("NORMAL_WRIST_MOVEMENT", "Casual wrist movement only (not full arm), ~30s.", 30),
    ("NORMAL_QUICK_HAND", "Natural but quick hand movements (the kind that plausibly triggered false FALLs before), ~30s.", 30),
    ("TWISTING_SLOW", "Slow wrist twisting, ~20s.", 20),
    ("TWISTING_MEDIUM", "Medium-speed wrist twisting, ~20s.", 20),
    ("TWISTING_FAST", "Fast wrist twisting, ~20s.", 20),
    ("TWISTING_CLOCKWISE", "Twisting, clockwise only, ~20s.", 20),
    ("TWISTING_COUNTERCLOCKWISE", "Twisting, counter-clockwise only, ~20s.", 20),
    ("TWISTING_ORIENTATION_B", "Repeat a twisting variant with the glove/wrist at a different orientation than the above, ~20s.", 20),
]


def print_protocol():
    print("SAFEHER HARDWARE FAILURE-CAPTURE TEST PROTOCOL")
    print("=" * 70)
    print("Flash firmware/SafeHer_Glove_Failure_Capture/ first (compile with")
    print("  --fqbn esp32:esp32:esp32c3:CDCOnBoot=cdc,PartitionScheme=huge_app")
    print("both flags are required - see this session's hardware validation findings).")
    print()
    print("Open a serial terminal at 115200 baud and redirect/log its output to a")
    print("file for the whole session (e.g. in a terminal: `... > capture_log.txt`,")
    print("or your terminal program's own logging feature).")
    print()
    print("Before each segment below, type the shown LABEL command and press enter,")
    print("then perform the described motion for the suggested duration. Segment")
    print("order is not fixed - this is a suggested order, not a required one.")
    print()
    total = 0
    for label, desc, dur in PROTOCOL:
        print(f"  LABEL {label}")
        print(f"    {desc}")
        total += dur
    print(f"\nTotal suggested duration: ~{total}s (~{total/60:.1f} min). Longer is fine if you")
    print("want more windows per segment; shorter risks too few windows to be useful")
    print("(each segment should cover at least a handful of inference windows -")
    print("windows occur every ~500ms, so even 10s gives ~20 windows).")
    print()
    print("After the session, save the logged serial output as a .txt/.log file and run:")
    print("  python prepare_hardware_failure_capture.py --parse <logfile> --out <output_dir>")


def parse_log(log_path: Path, out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)
    window_rows = []
    raw_rows = []

    with open(log_path, "r", errors="replace") as f:
        for line in f:
            line = line.strip()
            if line.startswith("WINDOW_ROW,"):
                parts = line.split(",")
                # WINDOW_ROW,window,label,timestamp_ms,pred_class,confidence,7 probs,51 features
                expected_len = 1 + 5 + len(LABELS) + len(FEATURE_COLS)
                if len(parts) != expected_len:
                    print(f"WARNING: skipping malformed WINDOW_ROW (expected {expected_len} fields, got {len(parts)}): {line[:80]}...", file=sys.stderr)
                    continue
                row = {
                    "window": int(parts[1]), "activity_label": parts[2], "timestamp_ms": int(parts[3]),
                    "pred_class": parts[4], "confidence": float(parts[5]),
                }
                for i, cls in enumerate(LABELS):
                    row[f"proba_{cls}"] = float(parts[6 + i])
                offset = 6 + len(LABELS)
                for i, feat in enumerate(FEATURE_COLS):
                    row[feat] = float(parts[offset + i])
                window_rows.append(row)
            elif line.startswith("RAW_ROW,"):
                parts = line.split(",")
                if len(parts) != 10:
                    continue
                raw_rows.append({
                    "window": int(parts[1]), "activity_label": parts[2], "sample_idx": int(parts[3]),
                    "Ax": float(parts[4]), "Ay": float(parts[5]), "Az": float(parts[6]),
                    "Gx": float(parts[7]), "Gy": float(parts[8]), "Gz": float(parts[9]),
                })

    windows_df = pd.DataFrame(window_rows)
    raw_df = pd.DataFrame(raw_rows)

    windows_path = out_dir / "captured_windows.csv"
    raw_path = out_dir / "captured_raw_samples.csv"
    windows_df.to_csv(windows_path, index=False)
    raw_df.to_csv(raw_path, index=False)

    print(f"Parsed {len(windows_df)} window rows -> {windows_path}")
    print(f"Parsed {len(raw_df)} raw sample rows -> {raw_path}")
    if len(windows_df):
        print("\nWindows per activity label:")
        print(windows_df["activity_label"].value_counts())
        print("\nFALL predictions per activity label:")
        fall_by_label = windows_df[windows_df["pred_class"] == "FALL"]["activity_label"].value_counts()
        print(fall_by_label if len(fall_by_label) else "  none")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--parse", type=str, default=None, help="Path to a captured serial log to parse.")
    parser.add_argument("--out", type=str, default=None, help="Output directory for parsed CSVs.")
    args = parser.parse_args()

    if args.parse:
        if not args.out:
            print("ERROR: --out is required with --parse", file=sys.stderr)
            sys.exit(1)
        parse_log(Path(args.parse), Path(args.out))
    else:
        print_protocol()


if __name__ == "__main__":
    main()
