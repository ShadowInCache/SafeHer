#!/usr/bin/env python3
"""Recording-level 5-fold StratifiedGroupKFold CV for size-constrained
candidate configs (needed because the fall-complete candidate's node count
does not fit the ESP32-C3 flash budget). Same protocol as every other CV
script in this investigation: group=recording_id, dev set only (208
recordings), locked 22-recording test set is NEVER touched here.

Baseline to compare against (fall-complete candidate CV, exact V5 config,
cv_v5_fall_complete.py): accuracy=0.7573, macro_f1=0.7407, fall_recall=0.7338,
fall_to_normal=90, normal_to_fall=63.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score, confusion_matrix, f1_score,
    precision_recall_fscore_support,
)
from sklearn.model_selection import StratifiedGroupKFold
from xgboost import XGBClassifier

PROJECT_ROOT = Path(__file__).resolve().parent.parent
FEATURES_PATH = PROJECT_ROOT / "features" / "glove_7class_features_v7_fall_complete.csv"
V5_SPLIT_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_train_test_split.json"
METADATA_COLUMNS = ["recording_id", "source_file", "label"]
LABELS = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]
LABEL_TO_ID = {l: i for i, l in enumerate(LABELS)}

v5_split = json.loads(V5_SPLIT_PATH.read_text())
locked_test_recordings = set()
for recs in v5_split["test_recordings"].values():
    locked_test_recordings.update(recs)
assert len(locked_test_recordings) == 22

full_features = pd.read_csv(FEATURES_PATH)
feature_cols = [c for c in full_features.columns if c not in METADATA_COLUMNS]
devset = full_features[~full_features["recording_id"].isin(locked_test_recordings)].reset_index(drop=True)
assert devset["recording_id"].nunique() == 208
assert set(devset["recording_id"]).isdisjoint(locked_test_recordings)

X = devset[feature_cols].astype(float)
y = devset["label"].map(LABEL_TO_ID).astype(int)
groups = devset["recording_id"]

CONFIGS = {
    "A_depth6_mcw30_n600": dict(
        n_estimators=600, max_depth=6, min_child_weight=30, gamma=0.0,
        learning_rate=0.05, subsample=0.9, colsample_bytree=0.9,
        random_state=42, objective="multi:softprob", num_class=len(LABELS),
        eval_metric="mlogloss", n_jobs=1,
    ),
    "B_depth6_mcw10_n200": dict(
        n_estimators=200, max_depth=6, min_child_weight=10, gamma=0.0,
        learning_rate=0.05, subsample=0.9, colsample_bytree=0.9,
        random_state=42, objective="multi:softprob", num_class=len(LABELS),
        eval_metric="mlogloss", n_jobs=1,
    ),
}

skf = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=42)

for name, params in CONFIGS.items():
    print("=" * 70)
    print(name, params)
    print("=" * 70)

    fold_accs, fold_f1s = [], []
    all_y_true, all_y_pred = [], []

    for fold_idx, (train_idx, val_idx) in enumerate(skf.split(X, y, groups)):
        X_train, X_val = X.iloc[train_idx], X.iloc[val_idx]
        y_train, y_val = y.iloc[train_idx], y.iloc[val_idx]

        model = XGBClassifier(**params)
        model.fit(X_train, y_train)
        y_pred = model.predict(X_val)

        acc = accuracy_score(y_val, y_pred)
        f1 = f1_score(y_val, y_pred, average="macro", zero_division=0)
        fold_accs.append(acc)
        fold_f1s.append(f1)
        all_y_true.extend(y_val.tolist())
        all_y_pred.extend(y_pred.tolist())
        print(f"  fold {fold_idx}: acc={acc:.4f} macro_f1={f1:.4f} n_val_windows={len(val_idx)}")

    all_y_true = np.array(all_y_true)
    all_y_pred = np.array(all_y_pred)
    overall_acc = accuracy_score(all_y_true, all_y_pred)
    overall_f1 = f1_score(all_y_true, all_y_pred, average="macro", zero_division=0)
    precision, recall, f1c, support = precision_recall_fscore_support(
        all_y_true, all_y_pred, labels=list(range(len(LABELS))), average=None, zero_division=0)
    cm = confusion_matrix(all_y_true, all_y_pred, labels=list(range(len(LABELS))))
    idx = LABEL_TO_ID
    fall_to_normal = int(cm[idx["FALL"], idx["NORMAL"]])
    normal_to_fall = int(cm[idx["NORMAL"], idx["FALL"]])

    print(f"\n  OVERALL (pooled across folds): accuracy={overall_acc:.4f} macro_f1={overall_f1:.4f}")
    print(f"  FALL precision={precision[idx['FALL']]:.4f} recall={recall[idx['FALL']]:.4f} f1={f1c[idx['FALL']]:.4f}")
    print(f"  fall_to_normal={fall_to_normal} normal_to_fall={normal_to_fall}")
    print()
