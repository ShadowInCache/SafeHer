#!/usr/bin/env python3
"""Train the FIRST BASELINE model for the expanded (200-recording) SafeHer glove dataset.

Controlled experiment: same XGBoost configuration as the frozen v5 baseline,
trained on the new recording-level train/validation/test split
(glove/ml/models/glove_7class_expanded/). Test split is loaded only to record
its size — it is never used for fitting or model selection here.

This script does not modify the raw dataset, the feature extractor, the old
feature CSV, the old baseline split/model, or firmware.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    confusion_matrix,
    f1_score,
    precision_recall_fscore_support,
)
from xgboost import XGBClassifier

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SPLIT_DIR = PROJECT_ROOT / "models" / "glove_7class_expanded"
TRAIN_PATH = SPLIT_DIR / "glove_7class_expanded_train.csv"
VAL_PATH = SPLIT_DIR / "glove_7class_expanded_validation.csv"
TEST_PATH = SPLIT_DIR / "glove_7class_expanded_test.csv"

MODEL_PATH = SPLIT_DIR / "safeher_glove_7class_expanded_baseline_xgboost.json"
REPORT_PATH = SPLIT_DIR / "glove_7class_expanded_baseline_training_report.json"
VAL_EVAL_PATH = SPLIT_DIR / "glove_7class_expanded_baseline_validation_evaluation.json"

LABELS = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]
LABEL_TO_ID = {label: idx for idx, label in enumerate(LABELS)}
METADATA_COLUMNS = ["recording_id", "source_file", "label"]

XGB_PARAMS = dict(
    n_estimators=500,
    max_depth=6,
    learning_rate=0.05,
    subsample=0.9,
    colsample_bytree=0.9,
    tree_method="hist",
    objective="multi:softprob",
    num_class=len(LABELS),
    eval_metric="mlogloss",
    random_state=42,
    early_stopping_rounds=30,
    n_jobs=1,
)


def load_split(path: Path, feature_columns: list[str] | None):
    df = pd.read_csv(path)
    cols = feature_columns or [c for c in df.columns if c not in METADATA_COLUMNS]
    X = df[cols].astype(float)
    y = df["label"].map(LABEL_TO_ID).astype(int)
    return df, X, y, cols


def confusion_and_class_metrics(y_true, y_pred):
    labels = list(range(len(LABELS)))
    cm = confusion_matrix(y_true, y_pred, labels=labels)
    precision, recall, f1, support = precision_recall_fscore_support(
        y_true, y_pred, labels=labels, average=None, zero_division=0
    )
    return cm, precision, recall, f1, support


def main():
    train_df, X_train, y_train, feature_columns = load_split(TRAIN_PATH, None)
    val_df, X_val, y_val, _ = load_split(VAL_PATH, feature_columns)
    test_df, X_test, y_test, _ = load_split(TEST_PATH, feature_columns)

    assert len(feature_columns) == 51, f"expected 51 features, got {len(feature_columns)}"
    assert list(X_train.columns) == list(X_val.columns) == list(X_test.columns), "feature order mismatch across splits"

    print(f"Feature count: {len(feature_columns)}")
    print(f"Train windows: {len(train_df)} | Validation windows: {len(val_df)} | Test windows (not used): {len(test_df)}")

    model = XGBClassifier(**XGB_PARAMS)

    start = time.time()
    model.fit(
        X_train, y_train,
        eval_set=[(X_val, y_val)],
        verbose=False,
    )
    duration_s = time.time() - start

    best_iteration = int(model.best_iteration)
    best_score = float(model.best_score)
    print(f"Training duration: {duration_s:.2f}s | best_iteration={best_iteration} | best_val_mlogloss={best_score:.6f}")

    # ---- Validation-only evaluation (test set untouched) ----
    y_val_pred = model.predict(X_val)
    cm, precision, recall, f1, support = confusion_and_class_metrics(y_val.to_numpy(), y_val_pred)

    accuracy = float(accuracy_score(y_val.to_numpy(), y_val_pred))
    macro_f1 = float(f1_score(y_val.to_numpy(), y_val_pred, labels=list(range(len(LABELS))), average="macro", zero_division=0))
    weighted_f1 = float(f1_score(y_val.to_numpy(), y_val_pred, labels=list(range(len(LABELS))), average="weighted", zero_division=0))

    normal_idx = LABEL_TO_ID["NORMAL"]
    fall_idx = LABEL_TO_ID["FALL"]
    fall_to_normal = int(cm[fall_idx, normal_idx])
    normal_to_fall = int(cm[normal_idx, fall_idx])

    per_class = {
        LABELS[i]: {
            "precision": float(precision[i]),
            "recall": float(recall[i]),
            "f1": float(f1[i]),
            "support": int(support[i]),
        }
        for i in range(len(LABELS))
    }

    val_eval = {
        "accuracy": accuracy,
        "macro_f1": macro_f1,
        "weighted_f1": weighted_f1,
        "per_class": per_class,
        "fall_precision": per_class["FALL"]["precision"],
        "fall_recall": per_class["FALL"]["recall"],
        "fall_f1": per_class["FALL"]["f1"],
        "fall_to_normal_errors": fall_to_normal,
        "normal_to_fall_errors": normal_to_fall,
        "confusion_matrix": cm.tolist(),
        "confusion_matrix_label_order": LABELS,
        "validation_windows": int(len(val_df)),
        "validation_recordings": int(val_df["recording_id"].nunique()),
    }

    with open(VAL_EVAL_PATH, "w") as f:
        json.dump(val_eval, f, indent=2)

    # ---- Save model ----
    SPLIT_DIR.mkdir(parents=True, exist_ok=True)
    model.save_model(str(MODEL_PATH))

    # ---- Training report ----
    report = {
        "experiment": "glove_7class_expanded_baseline",
        "description": "First baseline model trained on expanded 200-recording dataset, same XGBoost config as frozen v5 baseline.",
        "train_windows": int(len(train_df)),
        "train_recordings": int(train_df["recording_id"].nunique()),
        "validation_windows": int(len(val_df)),
        "validation_recordings": int(val_df["recording_id"].nunique()),
        "test_windows_recorded_only_not_used": int(len(test_df)),
        "test_recordings_recorded_only_not_used": int(test_df["recording_id"].nunique()),
        "feature_count": len(feature_columns),
        "feature_columns": feature_columns,
        "class_order": LABELS,
        "xgboost_params": {k: v for k, v in XGB_PARAMS.items()},
        "best_iteration": best_iteration,
        "best_validation_mlogloss": best_score,
        "training_duration_seconds": duration_s,
        "test_data_used_for_training_or_selection": False,
        "test_data_note": "Test split was loaded ONLY to record its window/recording counts. It was not passed to .fit(), not used in eval_set, and no metric was computed on it in this step.",
    }
    with open(REPORT_PATH, "w") as f:
        json.dump(report, f, indent=2)

    print(json.dumps({"val_eval": val_eval, "report_summary": {k: report[k] for k in ('train_windows','validation_windows','test_windows_recorded_only_not_used','best_iteration','best_validation_mlogloss')}}, indent=2))


if __name__ == "__main__":
    raise SystemExit(main())
