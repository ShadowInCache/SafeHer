#!/usr/bin/env python3
"""Read-only validation of the SafeHer glove dataset after the PUSH/PULL expansion
(PUSH/PULL grown from 20 to 30 recordings each). Does not modify any file."""

from __future__ import annotations

import glob
import os
from pathlib import Path

import numpy as np
import pandas as pd

DATASET_ROOT = Path(__file__).resolve().parent.parent / "dataset"
CLASSES = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]
REQUIRED_COLS = ["timestamp_ms", "Ax", "Ay", "Az", "Gx", "Gy", "Gz", "label"]
EXPECTED_COUNTS = {"PUSH": 30, "PULL": 30}


def main():
    print("SAFEHER DATASET VALIDATION (post PUSH/PULL expansion)")
    print("=" * 70)

    critical = []
    warnings = []
    rows = []

    for cls in CLASSES:
        folder = DATASET_ROOT / cls.lower()
        if not folder.exists():
            critical.append(f"Missing class folder: {cls}")
            continue
        files = sorted(glob.glob(str(folder / "*.csv")))
        print(f"{cls:10s}: {len(files)} recordings")
        if cls in EXPECTED_COUNTS and len(files) != EXPECTED_COUNTS[cls]:
            critical.append(f"{cls}: expected {EXPECTED_COUNTS[cls]} recordings, found {len(files)}")

        for fp in files:
            entry = {"class": cls, "file": os.path.basename(fp)}
            size = os.path.getsize(fp)
            if size == 0:
                critical.append(f"{fp}: EMPTY FILE")
                rows.append(entry)
                continue
            try:
                df = pd.read_csv(fp)
            except Exception as exc:
                critical.append(f"{fp}: failed to read ({exc})")
                rows.append(entry)
                continue

            missing_cols = [c for c in REQUIRED_COLS if c not in df.columns]
            if missing_cols:
                critical.append(f"{fp}: missing columns {missing_cols}")
                rows.append(entry)
                continue

            sensor_cols = ["timestamp_ms", "Ax", "Ay", "Az", "Gx", "Gy", "Gz"]
            num_df = df[sensor_cols].apply(pd.to_numeric, errors="coerce")
            nonnumeric = int((num_df.isna() & df[sensor_cols].notna()).sum().sum())
            if nonnumeric:
                critical.append(f"{fp}: {nonnumeric} non-numeric sensor values")

            nan_count = int(num_df.isna().sum().sum())
            if nan_count:
                critical.append(f"{fp}: {nan_count} NaN values")

            inf_count = int(np.isinf(num_df.to_numpy(dtype=float, na_value=0)).sum())
            if inf_count:
                critical.append(f"{fp}: {inf_count} infinite values")

            labels = df["label"].astype(str).str.strip().str.upper().unique().tolist()
            if labels != [cls]:
                critical.append(f"{fp}: label mismatch, found {labels}, expected [{cls}]")

            ts = pd.to_numeric(df["timestamp_ms"], errors="coerce")
            diffs = ts.diff().dropna()
            non_increasing = int((diffs <= 0).sum())
            if non_increasing:
                critical.append(f"{fp}: {non_increasing} non-increasing/duplicate timestamps")

            pos_diffs = diffs[diffs > 0]
            median_dt = float(pos_diffs.median()) if len(pos_diffs) else None
            hz = 1000.0 / median_dt if median_dt else None
            if hz is not None and not (80 <= hz <= 120):
                warnings.append(f"{fp}: sampling rate outlier ({hz:.1f} Hz)")

            duration_s = float(ts.iloc[-1] - ts.iloc[0]) / 1000.0 if len(ts) > 1 else None

            entry.update({
                "n_rows": len(df),
                "median_dt_ms": median_dt,
                "hz": hz,
                "duration_s": duration_s,
            })
            rows.append(entry)

    df_out = pd.DataFrame(rows)

    print("\n" + "=" * 70)
    print("DURATION SUMMARY (seconds)")
    print("=" * 70)
    print(df_out.dropna(subset=["duration_s"]).groupby("class")["duration_s"].agg(["min", "max", "median", "mean", "count"]))

    print("\n" + "=" * 70)
    print("SAMPLING RATE SUMMARY (Hz)")
    print("=" * 70)
    print(df_out.dropna(subset=["hz"]).groupby("class")["hz"].agg(["min", "max", "median"]))

    print("\n" + "=" * 70)
    print("DUPLICATE RECORDING CHECK (content hash within class)")
    print("=" * 70)
    dup_found = []
    for cls in CLASSES:
        folder = DATASET_ROOT / cls.lower()
        files = sorted(glob.glob(str(folder / "*.csv")))
        hashes = {}
        for fp in files:
            try:
                df = pd.read_csv(fp)
                sensor_cols = ["Ax", "Ay", "Az", "Gx", "Gy", "Gz"]
                h = int(pd.util.hash_pandas_object(df[sensor_cols].round(3)).sum())
            except Exception:
                continue
            hashes.setdefault(h, []).append(os.path.basename(fp))
        for h, flist in hashes.items():
            if len(flist) > 1:
                dup_found.append((cls, flist))
    if dup_found:
        for cls, flist in dup_found:
            warnings.append(f"{cls}: possible duplicate recordings {flist}")
        print(dup_found)
    else:
        print("none found")

    print("\n" + "=" * 70)
    print("RESULT")
    print("=" * 70)
    print(f"Total recordings: {len(df_out)}")
    print(f"Critical problems: {len(critical)}")
    for c in critical:
        print("  -", c)
    print(f"Warnings: {len(warnings)}")
    for w in warnings:
        print("  -", w)

    status = "FAIL" if critical else ("PASS WITH WARNINGS" if warnings else "PASS")
    print(f"\nVALIDATION STATUS: {status}")
    return 0 if not critical else 1


if __name__ == "__main__":
    raise SystemExit(main())
