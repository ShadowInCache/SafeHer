#!/usr/bin/env python3
"""Recording-level 5-fold StratifiedGroupKFold CV on the 5-class dataset
(PUSH+PULL+JERK merged into SUDDEN_MOVEMENT). Same protocol as every other
CV script in this investigation: group=recording_id, dev set only (208
recordings), locked 22-recording test set excluded and NEVER touched here.

Tests the size-constrained config (Config A: V5 config + min_child_weight=30)
since that's the one that fits the ESP32-C3 flash budget.
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
FEATURES_PATH = PROJECT_ROOT / "features" / "glove_5class_features_v1_merged_pushpull_jerk.csv"
V5_SPLIT_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_train_test_split.json"
METADATA_COLUMNS = ["recording_id", "source_file", "label"]
LABELS = ["NORMAL", "SUDDEN_MOVEMENT", "SHAKING", "TWISTING", "FALL"]
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

params = dict(
    n_estimators=600, max_depth=6, min_child_weight=30, gamma=0.0,
    learning_rate=0.05, subsample=0.9, colsample_bytree=0.9,
    random_state=42, objective="multi:softprob", num_class=len(LABELS),
    eval_metric="mlogloss", n_jobs=1,
)

skf = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=42)
all_y_true, all_y_pred = [], []

for fold_idx, (train_idx, val_idx) in enumerate(skf.split(X, y, groups)):
    X_train, X_val = X.iloc[train_idx], X.iloc[val_idx]
    y_train, y_val = y.iloc[train_idx], y.iloc[val_idx]

    model = XGBClassifier(**params)
    model.fit(X_train, y_train)
    y_pred = model.predict(X_val)

    acc = accuracy_score(y_val, y_pred)
    f1 = f1_score(y_val, y_pred, average="macro", zero_division=0)
    all_y_true.extend(y_val.tolist())
    all_y_pred.extend(y_pred.tolist())
    print(f"fold {fold_idx}: acc={acc:.4f} macro_f1={f1:.4f} n_val_windows={len(val_idx)}")

all_y_true = np.array(all_y_true)
all_y_pred = np.array(all_y_pred)
overall_acc = accuracy_score(all_y_true, all_y_pred)
overall_f1 = f1_score(all_y_true, all_y_pred, average="macro", zero_division=0)
precision, recall, f1c, support = precision_recall_fscore_support(
    all_y_true, all_y_pred, labels=list(range(len(LABELS))), average=None, zero_division=0)
cm = confusion_matrix(all_y_true, all_y_pred, labels=list(range(len(LABELS))))
idx = LABEL_TO_ID

print(f"\nOVERALL (pooled across folds): accuracy={overall_acc:.4f} macro_f1={overall_f1:.4f}")
for i, lbl in enumerate(LABELS):
    print(f"  {lbl:16s} precision={precision[i]:.4f} recall={recall[i]:.4f} f1={f1c[i]:.4f} support={support[i]}")

sm = idx["SUDDEN_MOVEMENT"]
print(f"\nSUDDEN_MOVEMENT confusion row (what it gets misclassified as):")
for j, lbl in enumerate(LABELS):
    if j != sm:
        print(f"  SUDDEN_MOVEMENT -> {lbl}: {cm[sm, j]}")
print(f"\nWhat gets misclassified AS SUDDEN_MOVEMENT:")
for i, lbl in enumerate(LABELS):
    if i != sm:
        print(f"  {lbl} -> SUDDEN_MOVEMENT: {cm[i, sm]}")

n = idx["NORMAL"]
print(f"\nNORMAL<->SUDDEN_MOVEMENT: NORMAL->SUDDEN_MOVEMENT={cm[n, sm]} SUDDEN_MOVEMENT->NORMAL={cm[sm, n]}")
f_ = idx["FALL"]
print(f"FALL<->NORMAL: FALL->NORMAL={cm[f_, n]} NORMAL->FALL={cm[n, f_]}")
