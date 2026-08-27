#!/usr/bin/env python3
"""Extract sliding-window features from SafeHer glove recordings."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATASET_ROOT = PROJECT_ROOT / "dataset"
FEATURES_DIR = PROJECT_ROOT / "features"
OUTPUT_PATH = FEATURES_DIR / "glove_7class_features.csv"

LABELS = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]
WINDOW_SIZE = 100
STEP_SIZE = 50
SENSOR_COLUMNS = ["Ax", "Ay", "Az", "Gx", "Gy", "Gz"]
METADATA_COLUMNS = ["recording_id", "source_file", "label"]


def list_recordings():
    files = []
    for label in LABELS:
        folder = DATASET_ROOT / label.lower()
        if not folder.exists():
            continue
        for csv_file in sorted(folder.glob("*.csv")):
            files.append((label, csv_file))
    return files


def compute_stats(values: np.ndarray) -> dict[str, float]:
    if values.size == 0:
        return {
            "mean": 0.0,
            "std": 0.0,
            "min": 0.0,
            "max": 0.0,
            "range": 0.0,
            "rms": 0.0,
        }

    values = values.astype(float)
    return {
        "mean": float(np.mean(values)),
        "std": float(np.std(values, ddof=0)),
        "min": float(np.min(values)),
        "max": float(np.max(values)),
        "range": float(np.max(values) - np.min(values)),
        "rms": float(np.sqrt(np.mean(np.square(values)))),
    }


def build_window_feature_row(window_df: pd.DataFrame, label: str, source_file: Path, recording_id: str):
    features = {}

    for col in SENSOR_COLUMNS:
        stats = compute_stats(window_df[col].to_numpy())
        for stat_name, stat_value in stats.items():
            features[f"{col}_{stat_name}"] = stat_value

    acc_mag = np.sqrt(
        np.square(window_df["Ax"].to_numpy(dtype=float))
        + np.square(window_df["Ay"].to_numpy(dtype=float))
        + np.square(window_df["Az"].to_numpy(dtype=float))
    )
    gyro_mag = np.sqrt(
        np.square(window_df["Gx"].to_numpy(dtype=float))
        + np.square(window_df["Gy"].to_numpy(dtype=float))
        + np.square(window_df["Gz"].to_numpy(dtype=float))
    )

    for name, values in {"acc_mag": acc_mag, "gyro_mag": gyro_mag}.items():
        stats = compute_stats(values)
        for stat_name, stat_value in stats.items():
            features[f"{name}_{stat_name}"] = stat_value

    jerk = np.diff(acc_mag)
    if jerk.size > 0:
        features["jerk_mean"] = float(np.mean(jerk))
        features["jerk_std"] = float(np.std(jerk, ddof=0))
        features["jerk_max"] = float(np.max(jerk))
    else:
        features["jerk_mean"] = 0.0
        features["jerk_std"] = 0.0
        features["jerk_max"] = 0.0

    row = {
        "recording_id": recording_id,
        "source_file": str(source_file.relative_to(PROJECT_ROOT)),
        "label": label,
    }
    row.update(features)
    return row


def validate_dataframe(frame: pd.DataFrame, source_file: Path, label: str):
    errors = []

    if frame.empty:
        errors.append(f"{source_file}: empty dataframe")
        return errors

    expected_columns = ["timestamp_ms", "Ax", "Ay", "Az", "Gx", "Gy", "Gz", "label"]
    missing_columns = [col for col in expected_columns if col not in frame.columns]
    if missing_columns:
        errors.append(f"{source_file}: missing columns {missing_columns}")

    if frame.isnull().values.any():
        errors.append(f"{source_file}: contains NaN values")

    if not np.isfinite(frame["Ax"].astype(float).to_numpy()).all():
        errors.append(f"{source_file}: invalid finite values in Ax")
    if not np.isfinite(frame["Ay"].astype(float).to_numpy()).all():
        errors.append(f"{source_file}: invalid finite values in Ay")
    if not np.isfinite(frame["Az"].astype(float).to_numpy()).all():
        errors.append(f"{source_file}: invalid finite values in Az")
    if not np.isfinite(frame["Gx"].astype(float).to_numpy()).all():
        errors.append(f"{source_file}: invalid finite values in Gx")
    if not np.isfinite(frame["Gy"].astype(float).to_numpy()).all():
        errors.append(f"{source_file}: invalid finite values in Gy")
    if not np.isfinite(frame["Gz"].astype(float).to_numpy()).all():
        errors.append(f"{source_file}: invalid finite values in Gz")

    if str(frame["label"].iloc[0]).upper() != label:
        errors.append(f"{source_file}: label mismatch: file label is {frame['label'].iloc[0]} but expected {label}")

    return errors


def build_feature_dataframe():
    recordings = list_recordings()
    rows = []
    errors = []

    for label, file_path in recordings:
        try:
            df = pd.read_csv(file_path)
        except Exception as exc:  # pragma: no cover - runtime dataset validation error path
            errors.append(f"{file_path}: failed to read CSV ({exc})")
            continue

        per_file_errors = validate_dataframe(df, file_path, label)
        errors.extend(per_file_errors)

        if per_file_errors:
            continue

        if len(df) < WINDOW_SIZE:
            errors.append(f"{file_path}: too short for a window ({len(df)} < {WINDOW_SIZE})")
            continue

        recording_id = file_path.stem
        for start_index in range(0, len(df) - WINDOW_SIZE + 1, STEP_SIZE):
            window_df = df.iloc[start_index : start_index + WINDOW_SIZE].copy()
            row = build_window_feature_row(window_df, label, file_path, recording_id)
            rows.append(row)

    feature_df = pd.DataFrame(rows)
    if feature_df.empty:
        raise ValueError(f"No usable windows created. Errors: {errors}")

    return feature_df, errors


def verify_feature_matrix(feature_df: pd.DataFrame):
    if feature_df.empty:
        raise ValueError("Feature dataframe is empty.")

    metadata_ok = all(col in feature_df.columns for col in METADATA_COLUMNS)
    if not metadata_ok:
        raise ValueError(f"Metadata columns missing. Required: {METADATA_COLUMNS}")

    feature_columns = [col for col in feature_df.columns if col not in METADATA_COLUMNS]
    if not feature_columns:
        raise ValueError("No feature columns generated.")

    if feature_df[feature_columns].isnull().values.any():
        raise ValueError("NaN values detected in feature matrix.")

    if not np.isfinite(feature_df[feature_columns].to_numpy(dtype=float)).all():
        raise ValueError("Infinite values detected in feature matrix.")

    if not all(pd.api.types.is_numeric_dtype(feature_df[col]) for col in feature_columns):
        raise ValueError("Feature columns contain non-numeric values.")

    label_set = set(feature_df["label"].unique())
    expected = set(LABELS)
    missing_labels = sorted(expected - label_set)
    if missing_labels:
        raise ValueError(f"Missing classes in feature data: {missing_labels}")


def print_summary(feature_df: pd.DataFrame, errors: list[str]):
    print("SAFEHER GLOVE FEATURE EXTRACTION SUMMARY")
    print("-" * 50)
    print(f"Total recordings processed: {feature_df['recording_id'].nunique()}")
    print(f"Total windows: {len(feature_df)}")

    class_counts = feature_df["label"].value_counts().sort_index()
    print("Windows per class:")
    for label in LABELS:
        print(f"  {label}: {int(class_counts.get(label, 0))}")

    feature_count = len([col for col in feature_df.columns if col not in METADATA_COLUMNS])
    print(f"Feature column count: {feature_count}")

    print("Rows per class:")
    for label in LABELS:
        print(f"  {label}: {int(class_counts.get(label, 0))}")

    if errors:
        print("Errors:")
        for error in errors:
            print(f"  - {error}")
    else:
        print("Errors: none")


def main():
    FEATURES_DIR.mkdir(parents=True, exist_ok=True)

    try:
        feature_df, errors = build_feature_dataframe()
        verify_feature_matrix(feature_df)
        feature_df.to_csv(OUTPUT_PATH, index=False)
        print_summary(feature_df, errors)
        print(f"\nOutput file: {OUTPUT_PATH}")
        return 0
    except Exception as exc:  # pragma: no cover - top-level validation/reporting path
        print(f"ERROR: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
