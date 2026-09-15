#!/usr/bin/env python3
"""Recording-level 5-fold CV (same protocol/config as the 5-class candidate),
but tracking out-of-fold predictions per recording so we can see exactly
which NORMAL recordings are responsible for NORMAL->SUDDEN_MOVEMENT
confusion - honestly, not the optimistic in-sample view.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
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

full_features = pd.read_csv(FEATURES_PATH)
feature_cols = [c for c in full_features.columns if c not in METADATA_COLUMNS]
devset = full_features[~full_features["recording_id"].isin(locked_test_recordings)].reset_index(drop=True)

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
devset = devset.copy()
devset["oof_pred"] = None

for fold_idx, (train_idx, val_idx) in enumerate(skf.split(X, y, groups)):
    X_train, X_val = X.iloc[train_idx], X.iloc[val_idx]
    y_train = y.iloc[train_idx]
    model = XGBClassifier(**params)
    model.fit(X_train, y_train)
    y_pred = model.predict(X_val)
    devset.loc[devset.index[val_idx], "oof_pred"] = [LABELS[p] for p in y_pred]
    print(f"fold {fold_idx} done")

normal_df = devset[devset["label"] == "NORMAL"].copy()
normal_df["num"] = normal_df["recording_id"].str.extract(r"normal_(\d+)").astype(int)

for lo, hi, tag in [(1, 40, "original 001-040"), (41, 70, "expanded 041-070")]:
    subset = normal_df[(normal_df["num"] >= lo) & (normal_df["num"] <= hi)]
    n_sm = (subset["oof_pred"] == "SUDDEN_MOVEMENT").sum()
    print(f"{tag}: {subset['recording_id'].nunique()} recordings, {len(subset)} windows, "
          f"{n_sm} misclassified as SUDDEN_MOVEMENT ({100*n_sm/len(subset):.1f}%)")

per_rec = normal_df[normal_df["oof_pred"] == "SUDDEN_MOVEMENT"].groupby("recording_id").size().sort_values(ascending=False)
print(f"\nTotal NORMAL recordings with >=1 out-of-fold SUDDEN_MOVEMENT misclassification: {len(per_rec)} / {normal_df['recording_id'].nunique()}")
print("\nPer-recording breakdown:")
print(per_rec.to_string())
