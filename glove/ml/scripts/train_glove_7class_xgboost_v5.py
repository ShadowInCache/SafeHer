#!/usr/bin/env python3
"""Train a 7-class SafeHer glove XGBoost model V5 using stratified recording-level splits.

This version ensures:
- Recording-level grouping: entire recordings in either train or test, never both
- Stratification: each class has recordings in both train and test sets
- Deterministic: uses random seed 42 for reproducibility
- Safety focus: tracks NORMAL->FALL false positives and FALL recall carefully
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    precision_recall_fscore_support,
    precision_score,
    recall_score,
)
from xgboost import XGBClassifier

PROJECT_ROOT = Path(__file__).resolve().parent.parent
FEATURES_PATH = PROJECT_ROOT / "features" / "glove_7class_features.csv"
MODEL_DIR = PROJECT_ROOT / "models" / "glove_7class"
MODEL_PATH_V5 = MODEL_DIR / "safeher_glove_7class_v5_xgboost.json"
FEATURE_COLUMNS_PATH_V5 = MODEL_DIR / "glove_7class_v5_feature_columns.json"
LABEL_MAPPING_PATH_V5 = MODEL_DIR / "glove_7class_v5_label_mapping.json"
TRAIN_TEST_SPLIT_PATH_V5 = MODEL_DIR / "glove_7class_v5_train_test_split.json"

# V3 and V4 paths for comparison
MODEL_PATH_V3 = MODEL_DIR / "safeher_glove_7class_v3_xgboost.json"
FEATURE_COLUMNS_PATH_V3 = MODEL_DIR / "glove_7class_v3_feature_columns.json"
LABEL_MAPPING_PATH_V3 = MODEL_DIR / "glove_7class_v3_label_mapping.json"
TRAIN_TEST_SPLIT_PATH_V3 = MODEL_DIR / "glove_7class_v3_train_test_split.json"

MODEL_PATH_V4 = MODEL_DIR / "safeher_glove_7class_v4_xgboost.json"
FEATURE_COLUMNS_PATH_V4 = MODEL_DIR / "glove_7class_v4_feature_columns.json"
LABEL_MAPPING_PATH_V4 = MODEL_DIR / "glove_7class_v4_label_mapping.json"
TRAIN_TEST_SPLIT_PATH_V4 = MODEL_DIR / "glove_7class_v4_train_test_split.json"

LABELS = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]
LABEL_TO_ID = {label: idx for idx, label in enumerate(LABELS)}


def save_json(path: Path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)


def load_feature_data() -> pd.DataFrame:
    if not FEATURES_PATH.exists():
        raise FileNotFoundError(f"Feature file not found: {FEATURES_PATH}")

    df = pd.read_csv(FEATURES_PATH)
    required = ["recording_id", "source_file", "label"]
    missing = [col for col in required if col not in df.columns]
    if missing:
        raise ValueError(f"Feature file missing required metadata columns: {missing}")

    if df.empty:
        raise ValueError("Feature file is empty.")

    return df


def get_numeric_feature_columns(df: pd.DataFrame):
    excluded = {"recording_id", "source_file", "label"}
    columns = [col for col in df.columns if col not in excluded]
    numeric_columns = [col for col in columns if pd.api.types.is_numeric_dtype(df[col])]
    if not numeric_columns:
        raise ValueError("No numeric ML feature columns were found.")
    return numeric_columns


def validate_labels(df: pd.DataFrame):
    missing = [label for label in LABELS if label not in df["label"].unique()]
    if missing:
        raise ValueError(f"Feature dataset missing classes: {missing}")


def stratified_recording_split(df: pd.DataFrame, test_size: float = 0.2, random_state: int = 42):
    """
    Perform a stratified train/test split at the recording level.
    
    Ensures:
    - All windows from a recording go to either train OR test, never both
    - Each class has at least one recording in both train and test
    - Approximately test_size fraction of recordings per class go to test
    """
    rng = np.random.RandomState(random_state)
    
    # Get unique recording per class
    recording_by_class = {}
    for label in LABELS:
        recordings = df[df["label"] == label]["recording_id"].unique().tolist()
        recording_by_class[label] = sorted(recordings)
    
    # Print recording count by class
    print("\n=== Recording inventory by class ===")
    for label in LABELS:
        count = len(recording_by_class[label])
        print(f"{label:10s}: {count} recording(s)")
    
    # Split recordings per class
    train_recordings_per_class = {}
    test_recordings_per_class = {}
    
    for label in LABELS:
        recordings = recording_by_class[label]
        n_recordings = len(recordings)
        n_test = max(1, int(np.ceil(n_recordings * test_size)))
        n_train = n_recordings - n_test
        
        # Shuffle and split
        shuffled = rng.permutation(recordings).tolist()
        test_recs = shuffled[:n_test]
        train_recs = shuffled[n_test:]
        
        train_recordings_per_class[label] = sorted(train_recs)
        test_recordings_per_class[label] = sorted(test_recs)
    
    # Validate: each class must have at least one test recording
    print("\n=== Stratified split target ===")
    for label in LABELS:
        n_train = len(train_recordings_per_class[label])
        n_test = len(test_recordings_per_class[label])
        print(f"{label:10s}: train={n_train:2d}, test={n_test:2d}")
    
    missing_in_test = [label for label in LABELS if len(test_recordings_per_class[label]) == 0]
    if missing_in_test:
        raise ValueError(f"Stratified split failed: classes missing from test set: {missing_in_test}")
    
    # Combine all train and test recordings
    all_train_recordings = []
    all_test_recordings = []
    for label in LABELS:
        all_train_recordings.extend(train_recordings_per_class[label])
        all_test_recordings.extend(test_recordings_per_class[label])
    
    # Validate no overlap
    overlap = set(all_train_recordings) & set(all_test_recordings)
    if overlap:
        raise ValueError(f"Recording leakage: {len(overlap)} recordings appear in both train and test!")
    
    # Filter dataframe
    train_df = df[df["recording_id"].isin(all_train_recordings)].copy().reset_index(drop=True)
    test_df = df[df["recording_id"].isin(all_test_recordings)].copy().reset_index(drop=True)
    
    return train_df, test_df, train_recordings_per_class, test_recordings_per_class


def print_split_summary(train_df: pd.DataFrame, test_df: pd.DataFrame, 
                        train_recs_per_class: dict, test_recs_per_class: dict):
    train_counts = train_df["label"].value_counts().reindex(LABELS, fill_value=0)
    test_counts = test_df["label"].value_counts().reindex(LABELS, fill_value=0)

    print("\n" + "=" * 70)
    print("STRATIFIED RECORDING-LEVEL SPLIT SUMMARY")
    print("=" * 70)
    
    print("\nTraining recordings by class:")
    for label in LABELS:
        count = len(train_recs_per_class[label])
        print(f"  {label:10s}: {count:2d} recording(s)")
    
    print("\nTesting recordings by class:")
    for label in LABELS:
        count = len(test_recs_per_class[label])
        print(f"  {label:10s}: {count:2d} recording(s)")
    
    total_train_recs = sum(len(recs) for recs in train_recs_per_class.values())
    total_test_recs = sum(len(recs) for recs in test_recs_per_class.values())
    
    print(f"\nTotal training recordings: {total_train_recs}")
    print(f"Total testing recordings: {total_test_recs}")
    print(f"Training windows: {len(train_df)}")
    print(f"Testing windows: {len(test_df)}")
    
    print("\nTraining windows per class:")
    for label in LABELS:
        count = train_counts[label]
        print(f"  {label:10s}: {count:4d}")
    
    print("\nTesting windows per class:")
    for label in LABELS:
        count = test_counts[label]
        print(f"  {label:10s}: {count:4d}")
    
    # Verify overlap
    print("\n" + "=" * 70)
    print("OVERLAP VERIFICATION")
    print("=" * 70)
    all_train_recs = set()
    all_test_recs = set()
    for recs in train_recs_per_class.values():
        all_train_recs.update(recs)
    for recs in test_recs_per_class.values():
        all_test_recs.update(recs)
    
    overlap = all_train_recs & all_test_recs
    print(f"Recording overlap count: {len(overlap)}")
    if overlap:
        print(f"ERROR: Recordings appear in both train and test: {overlap}")
    else:
        print("[OK] No recording appears in both train and test")


def compute_metrics(y_true, y_pred, labels):
    accuracy = accuracy_score(y_true, y_pred)
    macro_precision = precision_score(y_true, y_pred, labels=labels, average="macro", zero_division=0)
    macro_recall = recall_score(y_true, y_pred, labels=labels, average="macro", zero_division=0)
    macro_f1 = f1_score(y_true, y_pred, labels=labels, average="macro", zero_division=0)
    weighted_f1 = f1_score(y_true, y_pred, labels=labels, average="weighted", zero_division=0)

    return {
        "accuracy": float(accuracy),
        "macro_precision": float(macro_precision),
        "macro_recall": float(macro_recall),
        "macro_f1": float(macro_f1),
        "weighted_f1": float(weighted_f1),
    }


def print_confusion_details(cm, label_ids):
    normal_id = label_ids["NORMAL"]
    fall_id = label_ids["FALL"]

    print("\n" + "=" * 70)
    print("CONFUSION MATRIX")
    print("=" * 70)
    print("\nConfusion matrix (rows=true, cols=predicted):")
    print("Order: [NORMAL, JERK, PUSH, PULL, SHAKING, TWISTING, FALL]\n")
    
    # Print with labels
    label_names = LABELS
    header = "         " + "  ".join(f"{label:9s}" for label in label_names)
    print(header)
    for i, label in enumerate(label_names):
        row_str = f"{label:9s}"
        for j in range(len(label_names)):
            row_str += f"  {cm[i, j]:7d}"
        print(row_str)
    
    fall_to_normal_errors = int(cm[fall_id, normal_id])
    normal_to_fall_errors = int(cm[normal_id, fall_id])
    
    print(f"\nCritical misclassifications:")
    print(f"  FALL -> NORMAL errors: {fall_to_normal_errors}")
    print(f"  NORMAL -> FALL errors: {normal_to_fall_errors}")


def print_class_metrics(y_true, y_pred, labels, label_names):
    precision, recall, f1, support = precision_recall_fscore_support(
        y_true, y_pred, labels=labels, average=None, zero_division=0
    )

    print("\n" + "=" * 70)
    print("PER-CLASS METRICS")
    print("=" * 70)
    print(f"\n{'Class':12s} {'Precision':>10s} {'Recall':>10s} {'F1':>10s} {'Support':>8s}")
    print("-" * 70)
    for idx, label in enumerate(label_names):
        print(f"{label:12s} {precision[idx]:10.4f} {recall[idx]:10.4f} {f1[idx]:10.4f} {int(support[idx]):8d}")

    normal_idx = LABEL_TO_ID["NORMAL"]
    fall_idx = LABEL_TO_ID["FALL"]
    
    print("\n" + "=" * 70)
    print("CRITICAL METRICS")
    print("=" * 70)
    print(f"NORMAL recall (not missing normal activities):     {recall[normal_idx]:.4f}")
    print(f"FALL recall (catching falls):                      {recall[fall_idx]:.4f}")

    return recall, support


def load_v3_model_and_metrics():
    """Load V3 model and compute its metrics on its own test set for comparison."""
    if not MODEL_PATH_V3.exists():
        print("\n[INFO] V3 model not found. Comparison skipped.")
        return None
    
    try:
        df = load_feature_data()
        features_v3 = json.loads(FEATURE_COLUMNS_PATH_V3.read_text())
        label_mapping_v3 = json.loads(LABEL_MAPPING_PATH_V3.read_text())
        split_v3 = json.loads(TRAIN_TEST_SPLIT_PATH_V3.read_text())
        
        # Load V3 model
        model_v3 = XGBClassifier()
        model_v3.load_model(str(MODEL_PATH_V3))
        
        # Get V3 test set
        test_recs_v3 = set()
        for recs_list in split_v3["test_recordings"].values():
            test_recs_v3.update(recs_list)
        
        df_test_v3 = df[df["recording_id"].isin(test_recs_v3)].copy()
        X_test_v3 = df_test_v3[features_v3].astype(float)
        y_test_v3 = df_test_v3["label"].map({label: idx for label, idx in label_mapping_v3.items()}).astype(int)
        
        # Predict
        y_pred_v3 = model_v3.predict(X_test_v3)
        
        # Compute metrics
        labels = list(range(len(LABELS)))
        cm_v3 = confusion_matrix(y_test_v3.to_numpy(), y_pred_v3, labels=labels)
        precision, recall, f1, support = precision_recall_fscore_support(
            y_test_v3.to_numpy(), y_pred_v3, labels=labels, average=None, zero_division=0
        )
        
        normal_idx = LABEL_TO_ID["NORMAL"]
        fall_idx = LABEL_TO_ID["FALL"]
        
        normal_test_windows = int((y_test_v3 == normal_idx).sum())
        fall_test_windows = int((y_test_v3 == fall_idx).sum())
        
        normal_false_fall = int(cm_v3[normal_idx, fall_idx])
        fall_missed_normal = int(cm_v3[fall_idx, normal_idx])
        
        normal_false_fall_rate = normal_false_fall / normal_test_windows if normal_test_windows > 0 else 0.0
        
        return {
            "accuracy": accuracy_score(y_test_v3.to_numpy(), y_pred_v3),
            "normal_recall": recall[normal_idx],
            "fall_recall": recall[fall_idx],
            "macro_f1": f1_score(y_test_v3.to_numpy(), y_pred_v3, labels=labels, average="macro", zero_division=0),
            "normal_false_fall": normal_false_fall,
            "normal_false_fall_rate": normal_false_fall_rate,
            "fall_missed_normal": fall_missed_normal,
            "normal_test_windows": normal_test_windows,
            "fall_test_windows": fall_test_windows,
        }
    except Exception as e:
        print(f"\n[INFO] Could not load V3 for comparison: {e}")
        return None


def load_v4_model_and_metrics():
    """Load V4 model and compute its metrics on its own test set for comparison."""
    if not MODEL_PATH_V4.exists():
        print("\n[INFO] V4 model not found. Comparison skipped.")
        return None
    
    try:
        df = load_feature_data()
        features_v4 = json.loads(FEATURE_COLUMNS_PATH_V4.read_text())
        label_mapping_v4 = json.loads(LABEL_MAPPING_PATH_V4.read_text())
        split_v4 = json.loads(TRAIN_TEST_SPLIT_PATH_V4.read_text())
        
        # Load V4 model
        model_v4 = XGBClassifier()
        model_v4.load_model(str(MODEL_PATH_V4))
        
        # Get V4 test set
        test_recs_v4 = set()
        for recs_list in split_v4["test_recordings"].values():
            test_recs_v4.update(recs_list)
        
        df_test_v4 = df[df["recording_id"].isin(test_recs_v4)].copy()
        X_test_v4 = df_test_v4[features_v4].astype(float)
        y_test_v4 = df_test_v4["label"].map({label: idx for label, idx in label_mapping_v4.items()}).astype(int)
        
        # Predict
        y_pred_v4 = model_v4.predict(X_test_v4)
        
        # Compute metrics
        labels = list(range(len(LABELS)))
        cm_v4 = confusion_matrix(y_test_v4.to_numpy(), y_pred_v4, labels=labels)
        precision, recall, f1, support = precision_recall_fscore_support(
            y_test_v4.to_numpy(), y_pred_v4, labels=labels, average=None, zero_division=0
        )
        
        normal_idx = LABEL_TO_ID["NORMAL"]
        fall_idx = LABEL_TO_ID["FALL"]
        
        normal_test_windows = int((y_test_v4 == normal_idx).sum())
        fall_test_windows = int((y_test_v4 == fall_idx).sum())
        
        normal_false_fall = int(cm_v4[normal_idx, fall_idx])
        fall_missed_normal = int(cm_v4[fall_idx, normal_idx])
        
        normal_false_fall_rate = normal_false_fall / normal_test_windows if normal_test_windows > 0 else 0.0
        
        return {
            "accuracy": accuracy_score(y_test_v4.to_numpy(), y_pred_v4),
            "normal_recall": recall[normal_idx],
            "fall_recall": recall[fall_idx],
            "macro_f1": f1_score(y_test_v4.to_numpy(), y_pred_v4, labels=labels, average="macro", zero_division=0),
            "normal_false_fall": normal_false_fall,
            "normal_false_fall_rate": normal_false_fall_rate,
            "fall_missed_normal": fall_missed_normal,
            "normal_test_windows": normal_test_windows,
            "fall_test_windows": fall_test_windows,
        }
    except Exception as e:
        print(f"\n[INFO] Could not load V4 for comparison: {e}")
        return None


def main():
    df = load_feature_data()
    validate_labels(df)

    feature_columns = get_numeric_feature_columns(df)
    print(f"\nFeature count: {len(feature_columns)} features")
    if len(feature_columns) != 51:
        print(f"WARNING: Expected 51 features, got {len(feature_columns)}")

    # Perform stratified recording-level split
    train_df, test_df, train_recs_per_class, test_recs_per_class = stratified_recording_split(
        df, test_size=0.2, random_state=42
    )
    
    print_split_summary(train_df, test_df, train_recs_per_class, test_recs_per_class)

    X_train = train_df[feature_columns].astype(float)
    y_train = train_df["label"].map(LABEL_TO_ID).astype(int)

    X_test = test_df[feature_columns].astype(float)
    y_test = test_df["label"].map(LABEL_TO_ID).astype(int)

    print("\n" + "=" * 70)
    print("TRAINING XGBoost 7-CLASS CLASSIFIER (V5)")
    print("=" * 70)
    
    model = XGBClassifier(
        n_estimators=600,
        max_depth=6,
        learning_rate=0.05,
        subsample=0.9,
        colsample_bytree=0.9,
        random_state=42,
        objective="multi:softprob",
        num_class=len(LABELS),
        eval_metric="mlogloss",
        n_jobs=1,
    )

    model.fit(X_train, y_train)
    print("Training complete.\n")
    
    y_pred = model.predict(X_test)

    labels = list(range(len(LABELS)))
    metrics = compute_metrics(y_test.to_numpy(), y_pred, labels)
    cm = confusion_matrix(y_test.to_numpy(), y_pred, labels=labels)

    print("\n" + "=" * 70)
    print("EVALUATION ON HELD-OUT TEST RECORDINGS (V5)")
    print("=" * 70)
    print(f"\nOverall accuracy:  {metrics['accuracy']:.4f} ({metrics['accuracy']*100:.2f}%)")
    print(f"Macro precision:   {metrics['macro_precision']:.4f}")
    print(f"Macro recall:      {metrics['macro_recall']:.4f}")
    print(f"Macro F1:          {metrics['macro_f1']:.4f}")
    print(f"Weighted F1:       {metrics['weighted_f1']:.4f}")

    print_confusion_details(cm, LABEL_TO_ID)
    recall_v5, support = print_class_metrics(y_test.to_numpy(), y_pred, labels, LABELS)

    class_report = classification_report(
        y_test.to_numpy(),
        y_pred,
        labels=labels,
        target_names=LABELS,
        digits=4,
        zero_division=0,
    )
    print("\n" + "=" * 70)
    print("COMPLETE CLASSIFICATION REPORT")
    print("=" * 70)
    print(class_report)

    # Save model and artifacts
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    model.save_model(str(MODEL_PATH_V5))
    save_json(FEATURE_COLUMNS_PATH_V5, feature_columns)
    save_json(LABEL_MAPPING_PATH_V5, {label: idx for label, idx in LABEL_TO_ID.items()})
    
    # Save split metadata
    split_metadata = {
        "random_state": 42,
        "test_size": 0.2,
        "train_recordings": {label: recs for label, recs in train_recs_per_class.items()},
        "test_recordings": {label: recs for label, recs in test_recs_per_class.items()},
        "total_train_recordings": sum(len(recs) for recs in train_recs_per_class.values()),
        "total_test_recordings": sum(len(recs) for recs in test_recs_per_class.values()),
        "training_windows": int(len(train_df)),
        "testing_windows": int(len(test_df)),
        "train_windows_per_class": train_df["label"].value_counts().reindex(LABELS, fill_value=0).to_dict(),
        "test_windows_per_class": test_df["label"].value_counts().reindex(LABELS, fill_value=0).to_dict(),
    }
    save_json(TRAIN_TEST_SPLIT_PATH_V5, split_metadata)

    model_size_bytes = MODEL_PATH_V5.stat().st_size
    model_size_mb = model_size_bytes / (1024 * 1024)
    
    print("\n" + "=" * 70)
    print("MODEL ARTIFACTS")
    print("=" * 70)
    print(f"Model path: {MODEL_PATH_V5}")
    print(f"Model size: {model_size_bytes:,d} bytes ({model_size_mb:.3f} MB)")
    print(f"Feature columns: {FEATURE_COLUMNS_PATH_V5}")
    print(f"Label mapping: {LABEL_MAPPING_PATH_V5}")
    print(f"Split metadata: {TRAIN_TEST_SPLIT_PATH_V5}")

    # Calculate safety metrics
    normal_idx = LABEL_TO_ID["NORMAL"]
    fall_idx = LABEL_TO_ID["FALL"]
    
    normal_test_windows = int((y_test.to_numpy() == normal_idx).sum())
    fall_test_windows = int((y_test.to_numpy() == fall_idx).sum())
    
    normal_false_fall = int(cm[normal_idx, fall_idx])
    fall_missed_normal = int(cm[fall_idx, normal_idx])
    
    normal_false_fall_rate = normal_false_fall / normal_test_windows if normal_test_windows > 0 else 0.0
    fall_recall = recall_v5[fall_idx]
    normal_recall = recall_v5[normal_idx]

    print("\n" + "=" * 70)
    print("V5 SAFETY METRICS SUMMARY")
    print("=" * 70)
    print(f"V5 NORMAL → FALL rate:   {normal_false_fall_rate:.4f} ({normal_false_fall} / {normal_test_windows})")
    print(f"V5 FALL recall:          {fall_recall:.4f} ({int(fall_test_windows * fall_recall):.0f} / {fall_test_windows})")
    print(f"V5 NORMAL recall:        {normal_recall:.4f}")
    print(f"V5 FALL → NORMAL errors: {fall_missed_normal}")

    # Load and display V3 metrics for comparison
    print("\n" + "=" * 70)
    print("COMPARISON: V5 vs V3 vs V4")
    print("=" * 70)
    
    v3_metrics = load_v3_model_and_metrics()
    v4_metrics = load_v4_model_and_metrics()
    
    if v3_metrics:
        print("\nV3 (BASELINE - stratified recording-level split):")
        print(f"  Accuracy:           {v3_metrics['accuracy']*100:.2f}%")
        print(f"  Macro F1:           {v3_metrics['macro_f1']:.4f}")
        print(f"  NORMAL recall:      {v3_metrics['normal_recall']:.4f}")
        print(f"  FALL recall:        {v3_metrics['fall_recall']:.4f}")
        print(f"  NORMAL -> FALL:     {v3_metrics['normal_false_fall']} errors ({v3_metrics['normal_false_fall_rate']:.4f})")
        print(f"  FALL -> NORMAL:     {v3_metrics['fall_missed_normal']} errors")
    else:
        print("\nV3 metrics not available for comparison")
    
    if v4_metrics:
        print("\nV4 (ALTERNATIVE - stratified recording-level split):")
        print(f"  Accuracy:           {v4_metrics['accuracy']*100:.2f}%")
        print(f"  Macro F1:           {v4_metrics['macro_f1']:.4f}")
        print(f"  NORMAL recall:      {v4_metrics['normal_recall']:.4f}")
        print(f"  FALL recall:        {v4_metrics['fall_recall']:.4f}")
        print(f"  NORMAL -> FALL:     {v4_metrics['normal_false_fall']} errors ({v4_metrics['normal_false_fall_rate']:.4f})")
        print(f"  FALL -> NORMAL:     {v4_metrics['fall_missed_normal']} errors")
    else:
        print("\nV4 metrics not available for comparison")
    
    print("\nV5 (NEW - stratified recording-level split):")
    print(f"  Accuracy:           {metrics['accuracy']*100:.2f}%")
    print(f"  Macro F1:           {metrics['macro_f1']:.4f}")
    print(f"  NORMAL recall:      {normal_recall:.4f}")
    print(f"  FALL recall:        {fall_recall:.4f}")
    print(f"  NORMAL -> FALL:     {normal_false_fall} errors ({normal_false_fall_rate:.4f})")
    print(f"  FALL -> NORMAL:     {fall_missed_normal} errors")

    # Safety trade-off analysis
    print("\n" + "=" * 70)
    print("SAFETY TRADE-OFF ANALYSIS")
    print("=" * 70)
    
    if v3_metrics:
        false_fall_delta = normal_false_fall_rate - v3_metrics['normal_false_fall_rate']
        fall_recall_delta = fall_recall - v3_metrics['fall_recall']
        
        print(f"\nV5 vs V3:")
        print(f"  NORMAL → FALL rate change: {false_fall_delta:+.4f} ({false_fall_delta*100:+.2f}%)")
        if false_fall_delta < 0:
            print(f"    ✓ BETTER: V5 has fewer false FALL alarms")
        elif false_fall_delta > 0:
            print(f"    ✗ WORSE: V5 has more false FALL alarms")
        else:
            print(f"    = SAME: V5 has equal false FALL rate")
        
        print(f"  FALL recall change:        {fall_recall_delta:+.4f} ({fall_recall_delta*100:+.2f}%)")
        if fall_recall_delta > 0:
            print(f"    ✓ BETTER: V5 catches more actual FALLs")
        elif fall_recall_delta < 0:
            print(f"    ✗ WORSE: V5 misses more actual FALLs")
        else:
            print(f"    = SAME: V5 has equal FALL recall")
    
    if v4_metrics:
        false_fall_delta_v4 = normal_false_fall_rate - v4_metrics['normal_false_fall_rate']
        fall_recall_delta_v4 = fall_recall - v4_metrics['fall_recall']
        
        print(f"\nV5 vs V4:")
        print(f"  NORMAL → FALL rate change: {false_fall_delta_v4:+.4f} ({false_fall_delta_v4*100:+.2f}%)")
        if false_fall_delta_v4 < 0:
            print(f"    ✓ BETTER: V5 has fewer false FALL alarms")
        elif false_fall_delta_v4 > 0:
            print(f"    ✗ WORSE: V5 has more false FALL alarms")
        else:
            print(f"    = SAME: V5 has equal false FALL rate")
        
        print(f"  FALL recall change:        {fall_recall_delta_v4:+.4f} ({fall_recall_delta_v4*100:+.2f}%)")
        if fall_recall_delta_v4 > 0:
            print(f"    ✓ BETTER: V5 catches more actual FALLs")
        elif fall_recall_delta_v4 < 0:
            print(f"    ✗ WORSE: V5 misses more actual FALLs")
        else:
            print(f"    = SAME: V5 has equal FALL recall")

    print("\n" + "=" * 70)
    print("VALIDATION NOTES")
    print("=" * 70)
    print("[OK] Recording-level grouping enforced: no recording appears in both train/test")
    print("[OK] Stratified by class: all 7 classes represented in test set")
    print("[OK] Deterministic split: random_state=42")
    print("[OK] Test set has at least 1 recording per class")
    print("[OK] NORMAL class represented in test")
    print("[OK] FALL class represented in test")
    
    print("\nArtifacts saved successfully as V5 (V1, V2, V3, V4 are preserved):")
    print(f"  [SAVED] {MODEL_PATH_V5}")
    print(f"  [SAVED] {FEATURE_COLUMNS_PATH_V5}")
    print(f"  [SAVED] {LABEL_MAPPING_PATH_V5}")
    print(f"  [SAVED] {TRAIN_TEST_SPLIT_PATH_V5}")
    
    print("\n" + "=" * 70)
    print("FINAL RECOMMENDATION FOR REAL-TIME TESTING")
    print("=" * 70)
    
    if v3_metrics and v4_metrics:
        # Compare all three models
        if (normal_false_fall_rate <= v3_metrics['normal_false_fall_rate'] and 
            fall_recall >= v3_metrics['fall_recall']):
            print("\n✓ V5 is SAFE to advance to real-time testing")
            print("  - False FALL rate is not worse than V3")
            print("  - FALL recall is not worse than V3")
        else:
            print("\n⚠ V5 shows trade-off vs V3")
            if normal_false_fall_rate > v3_metrics['normal_false_fall_rate']:
                print(f"  - More false FALL alarms: {normal_false_fall_rate:.4f} vs {v3_metrics['normal_false_fall_rate']:.4f}")
            if fall_recall < v3_metrics['fall_recall']:
                print(f"  - Lower FALL recall: {fall_recall:.4f} vs {v3_metrics['fall_recall']:.4f}")
    elif v3_metrics:
        if (normal_false_fall_rate <= v3_metrics['normal_false_fall_rate'] and 
            fall_recall >= v3_metrics['fall_recall']):
            print("\n✓ V5 is SAFE to advance to real-time testing")
            print("  - False FALL rate is not worse than V3")
            print("  - FALL recall is not worse than V3")
        else:
            print("\n⚠ V5 shows trade-off vs V3")
            if normal_false_fall_rate > v3_metrics['normal_false_fall_rate']:
                print(f"  - More false FALL alarms: {normal_false_fall_rate:.4f} vs {v3_metrics['normal_false_fall_rate']:.4f}")
            if fall_recall < v3_metrics['fall_recall']:
                print(f"  - Lower FALL recall: {fall_recall:.4f} vs {v3_metrics['fall_recall']:.4f}")
    
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
