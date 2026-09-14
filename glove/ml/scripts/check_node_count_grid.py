#!/usr/bin/env python3
"""Quick diagnostic (NOT an official evaluation, CV, or accuracy check):
fit several size-constrained hyperparameter configs on the full 208-recording
dev set and report resulting node count, to find configs worth taking to a
real recording-level CV. Does not touch the locked 22-recording test set.
"""
from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
from xgboost import XGBClassifier

PROJECT_ROOT = Path(__file__).resolve().parent.parent
FEATURES_PATH = PROJECT_ROOT / "features" / "glove_7class_features_v7_fall_complete.csv"
V5_SPLIT_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_train_test_split.json"
METADATA_COLUMNS = ["recording_id", "source_file", "label"]
LABELS = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]
LABEL_TO_ID = {l: i for i, l in enumerate(LABELS)}

MAX_SKETCH_BYTES = 2_097_152
ESTIMATED_NON_MODEL_BYTES = 1_021_717
NODE_STRUCT_BYTES = 14
TARGET_MARGIN = 0.85
max_budget_node_bytes = MAX_SKETCH_BYTES * TARGET_MARGIN - ESTIMATED_NON_MODEL_BYTES
max_budget_nodes = int(max_budget_node_bytes // NODE_STRUCT_BYTES)

v5_split = json.loads(V5_SPLIT_PATH.read_text())
locked_test_recordings = set()
for recs in v5_split["test_recordings"].values():
    locked_test_recordings.update(recs)

full_features = pd.read_csv(FEATURES_PATH)
feature_cols = [c for c in full_features.columns if c not in METADATA_COLUMNS]
devset = full_features[~full_features["recording_id"].isin(locked_test_recordings)].reset_index(drop=True)

X_train = devset[feature_cols].astype(float)
y_train = devset["label"].map(LABEL_TO_ID).astype(int)

print(f"Target max nodes for ~{TARGET_MARGIN:.0%} flash budget: ~{max_budget_nodes:,}\n")

configs = [
    {"n_estimators": 600, "max_depth": 6, "min_child_weight": 10, "gamma": 0.0},
    {"n_estimators": 600, "max_depth": 6, "min_child_weight": 30, "gamma": 0.0},
    {"n_estimators": 300, "max_depth": 6, "min_child_weight": 1, "gamma": 0.0},
    {"n_estimators": 300, "max_depth": 6, "min_child_weight": 10, "gamma": 0.0},
    {"n_estimators": 300, "max_depth": 4, "min_child_weight": 5, "gamma": 0.0},
    {"n_estimators": 200, "max_depth": 6, "min_child_weight": 10, "gamma": 0.0},
]

for extra in configs:
    params = dict(
        learning_rate=0.05,
        subsample=0.9,
        colsample_bytree=0.9,
        random_state=42,
        objective="multi:softprob",
        num_class=len(LABELS),
        eval_metric="mlogloss",
        n_jobs=1,
    )
    params.update(extra)
    model = XGBClassifier(**params)
    model.fit(X_train, y_train)

    booster = model.get_booster()
    df = booster.trees_to_dataframe()
    n_nodes = len(df)
    node_bytes = n_nodes * NODE_STRUCT_BYTES
    est_sketch_bytes = node_bytes + ESTIMATED_NON_MODEL_BYTES
    fits = n_nodes <= max_budget_nodes
    print(f"{extra}: nodes={n_nodes:,} node_bytes={node_bytes:,} "
          f"est_pct_of_max={est_sketch_bytes/MAX_SKETCH_BYTES:.1%} "
          f"{'FITS w/ margin' if fits else 'too big'}")
