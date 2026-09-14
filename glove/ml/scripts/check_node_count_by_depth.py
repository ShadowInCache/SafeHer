#!/usr/bin/env python3
"""Quick diagnostic (NOT an official evaluation): fit one model per candidate
max_depth on the full 208-recording dev set (same set used for the
fall-complete candidate) and report resulting tree/node count, so we know
which depth actually fits the ESP32-C3 flash budget before spending time on
a full recording-level CV run. Does not touch the locked 22-recording test
set at all.
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

# ESP32-C3 budget context (from the actual compile error):
# Max program storage = 2,097,152 bytes. The rest of the sketch (BLE stack,
# feature extraction, etc, estimated from the original working build) takes
# roughly ~1.02 MB, leaving a working budget for the model's node table.
MAX_SKETCH_BYTES = 2_097_152
ESTIMATED_NON_MODEL_BYTES = 1_021_717
NODE_STRUCT_BYTES = 14
TARGET_MARGIN = 0.85  # aim to use at most 85% of program storage for safety margin

v5_split = json.loads(V5_SPLIT_PATH.read_text())
locked_test_recordings = set()
for recs in v5_split["test_recordings"].values():
    locked_test_recordings.update(recs)
assert len(locked_test_recordings) == 22

full_features = pd.read_csv(FEATURES_PATH)
feature_cols = [c for c in full_features.columns if c not in METADATA_COLUMNS]
devset = full_features[~full_features["recording_id"].isin(locked_test_recordings)].reset_index(drop=True)
assert devset["recording_id"].nunique() == 208

X_train = devset[feature_cols].astype(float)
y_train = devset["label"].map(LABEL_TO_ID).astype(int)

max_budget_node_bytes = MAX_SKETCH_BYTES * TARGET_MARGIN - ESTIMATED_NON_MODEL_BYTES
max_budget_nodes = int(max_budget_node_bytes // NODE_STRUCT_BYTES)
print(f"Target max nodes for ~{TARGET_MARGIN:.0%} flash budget: ~{max_budget_nodes:,}")
print()

for depth in [5, 4, 3]:
    params = dict(
        n_estimators=600,
        max_depth=depth,
        learning_rate=0.05,
        subsample=0.9,
        colsample_bytree=0.9,
        random_state=42,
        objective="multi:softprob",
        num_class=len(LABELS),
        eval_metric="mlogloss",
        n_jobs=1,
    )
    model = XGBClassifier(**params)
    model.fit(X_train, y_train)

    booster = model.get_booster()
    df = booster.trees_to_dataframe()
    n_nodes = len(df)
    n_leaves = (df["Feature"] == "Leaf").sum()
    node_bytes = n_nodes * NODE_STRUCT_BYTES
    est_sketch_bytes = node_bytes + ESTIMATED_NON_MODEL_BYTES
    fits = est_sketch_bytes <= max_budget_node_bytes + ESTIMATED_NON_MODEL_BYTES
    print(f"max_depth={depth}: nodes={n_nodes:,} leaves={n_leaves:,} "
          f"node_bytes={node_bytes:,} est_sketch_bytes={est_sketch_bytes:,} "
          f"est_pct_of_max={est_sketch_bytes/MAX_SKETCH_BYTES:.1%} "
          f"{'FITS' if fits else 'TOO BIG'}")
