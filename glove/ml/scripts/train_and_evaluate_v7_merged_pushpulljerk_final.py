#!/usr/bin/env python3
"""Train the 5-class SIZE-CONSTRAINED candidate (PUSH+PULL+JERK merged into
SUDDEN_MOVEMENT, Config A hyperparameters: V5 config + min_child_weight=30
so it fits the ESP32-C3 flash budget) on all 208 development recordings,
then perform EXACTLY ONE official evaluation on the locked 22-recording
test set (same 22 recording_ids as always - jerk_002/jerk_009/push_003/
push_006/pull_008/pull_010 are now scored as SUDDEN_MOVEMENT). Compared
against the ORIGINAL frozen production V5 model (7-class) evaluated on the
same set, with its PUSH/PULL/JERK predictions collapsed to SUDDEN_MOVEMENT
for a fair comparison.

Does NOT modify, retrain, or overwrite the original V5 model file - loaded
fresh, read-only, purely for comparison. Does NOT touch the 7-class dataset,
feature files, or prior reports - all outputs go to a new directory.
"""

from __future__ import annotations

import hashlib
import json
import time
from pathlib import Path

import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.metrics import (
    accuracy_score, confusion_matrix, f1_score,
    precision_recall_fscore_support,
)
from xgboost import XGBClassifier

PROJECT_ROOT = Path(__file__).resolve().parent.parent
FEATURES_PATH = PROJECT_ROOT / "features" / "glove_5class_features_v1_merged_pushpull_jerk.csv"
V5_SPLIT_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_train_test_split.json"
V5_MODEL_PATH = PROJECT_ROOT / "models" / "safeher_glove_7class_v5_xgboost.json"
V5_FEATURE_COLUMNS_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_feature_columns.json"

OUT_DIR = PROJECT_ROOT / "models" / "glove_5class_v7_merged_pushpulljerk_final"
OUT_DIR.mkdir(parents=True, exist_ok=True)

CANDIDATE_MODEL_PATH = OUT_DIR / "safeher_glove_5class_v7_merged_pushpulljerk_candidate_xgboost.json"
TRAINING_REPORT_PATH = OUT_DIR / "v7_merged_pushpulljerk_candidate_training_report.json"
COMPARISON_TXT_PATH = OUT_DIR / "v7_merged_pushpulljerk_candidate_vs_original_v5_comparison.txt"
COMPARISON_JSON_PATH = OUT_DIR / "v7_merged_pushpulljerk_candidate_vs_original_v5_comparison.json"

LABELS_5 = ["NORMAL", "SUDDEN_MOVEMENT", "SHAKING", "TWISTING", "FALL"]
LABEL_TO_ID_5 = {l: i for i, l in enumerate(LABELS_5)}
LABELS_7 = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]
METADATA_COLUMNS = ["recording_id", "source_file", "label"]

SIZE_CONSTRAINED_XGB_PARAMS = dict(
    n_estimators=600, max_depth=6, min_child_weight=30, gamma=0.0,
    learning_rate=0.05, subsample=0.9, colsample_bytree=0.9,
    random_state=42, objective="multi:softprob", num_class=len(LABELS_5),
    eval_metric="mlogloss", n_jobs=1,
)


def sha256_of_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    v5_split = json.loads(V5_SPLIT_PATH.read_text())
    locked_test_recordings = set()
    for recs in v5_split["test_recordings"].values():
        locked_test_recordings.update(recs)
    assert len(locked_test_recordings) == 22

    full_features = pd.read_csv(FEATURES_PATH)
    feature_cols = [c for c in full_features.columns if c not in METADATA_COLUMNS]
    assert len(feature_cols) == 51

    devset = full_features[~full_features["recording_id"].isin(locked_test_recordings)].reset_index(drop=True)
    testset = full_features[full_features["recording_id"].isin(locked_test_recordings)].reset_index(drop=True)
    assert devset["recording_id"].nunique() == 208
    assert testset["recording_id"].nunique() == 22
    assert set(devset["recording_id"]).isdisjoint(set(testset["recording_id"]))

    print(f"Development: {devset['recording_id'].nunique()} recordings / {len(devset)} windows")
    print(f"Locked test: {testset['recording_id'].nunique()} recordings / {len(testset)} windows")

    X_train = devset[feature_cols].astype(float)
    y_train = devset["label"].map(LABEL_TO_ID_5).astype(int)

    print("\nTraining 5-class size-constrained candidate on ALL 208 dev recordings...")
    print(json.dumps(SIZE_CONSTRAINED_XGB_PARAMS, indent=2))

    model = XGBClassifier(**SIZE_CONSTRAINED_XGB_PARAMS)
    start = time.time()
    model.fit(X_train, y_train)
    duration_s = time.time() - start
    print(f"Training complete in {duration_s:.2f}s.")

    model.save_model(str(CANDIDATE_MODEL_PATH))
    candidate_sha256 = sha256_of_file(CANDIDATE_MODEL_PATH)

    booster = model.get_booster()
    n_nodes = len(booster.trees_to_dataframe())
    print(f"Candidate node count: {n_nodes:,} (node_bytes={n_nodes*14:,})")

    training_report = {
        "experiment": "v7_merged_pushpulljerk_candidate_final",
        "description": "5-class candidate: PUSH+PULL+JERK merged into SUDDEN_MOVEMENT. NORMAL, SHAKING, TWISTING, FALL unchanged. Config A hyperparameters (V5 config + min_child_weight=30) for ESP32-C3 flash fit.",
        "class_order": LABELS_5,
        "xgboost_params": SIZE_CONSTRAINED_XGB_PARAMS,
        "node_count": int(n_nodes),
        "model_sha256": candidate_sha256,
        "training_duration_seconds": duration_s,
        "train_recordings": int(devset["recording_id"].nunique()),
        "train_windows": int(len(devset)),
    }
    with open(TRAINING_REPORT_PATH, "w") as f:
        json.dump(training_report, f, indent=2)
    print(f"Candidate saved: {CANDIDATE_MODEL_PATH}")
    print(f"SHA-256: {candidate_sha256}")

    # ---- ONE official locked-test evaluation ----
    X_test = testset[feature_cols].astype(float)
    y_test_true_labels = testset["label"].to_numpy()

    original_sha256 = sha256_of_file(V5_MODEL_PATH)
    original_feature_cols = json.loads(V5_FEATURE_COLUMNS_PATH.read_text())
    assert original_feature_cols == feature_cols

    original_bst = xgb.Booster()
    original_bst.load_model(str(V5_MODEL_PATH))
    assert sha256_of_file(V5_MODEL_PATH) == original_sha256, "original V5 model changed - ABORT"

    print("\nRunning locked test evaluation (single pass each)...")
    cand_proba = model.predict_proba(X_test)
    cand_pred_id = np.argmax(cand_proba, axis=1)
    cand_pred_labels = np.array([LABELS_5[i] for i in cand_pred_id])

    orig_proba = original_bst.inplace_predict(X_test.to_numpy())
    orig_pred_id7 = np.argmax(orig_proba, axis=1)
    orig_pred_labels7 = np.array([LABELS_7[i] for i in orig_pred_id7])
    # Collapse original's PUSH/PULL/JERK predictions to SUDDEN_MOVEMENT for fair comparison
    orig_pred_labels5 = np.array(
        ["SUDDEN_MOVEMENT" if l in ("PUSH", "PULL", "JERK") else l for l in orig_pred_labels7]
    )

    assert sha256_of_file(V5_MODEL_PATH) == original_sha256, "original V5 model changed after eval - ABORT"
    print(f"[OK] original V5 model unchanged (SHA-256: {original_sha256})")

    def eval_5class(pred_labels, true_labels):
        labels_range = LABELS_5
        acc = float(accuracy_score(true_labels, pred_labels))
        macro_f1 = float(f1_score(true_labels, pred_labels, labels=labels_range, average="macro", zero_division=0))
        precision, recall, f1c, support = precision_recall_fscore_support(
            true_labels, pred_labels, labels=labels_range, average=None, zero_division=0)
        cm = confusion_matrix(true_labels, pred_labels, labels=labels_range)
        per_class = {labels_range[i]: {"precision": float(precision[i]), "recall": float(recall[i]),
                                        "f1": float(f1c[i]), "support": int(support[i])} for i in range(len(labels_range))}
        idx = LABEL_TO_ID_5
        return {
            "accuracy": acc, "macro_f1": macro_f1, "per_class": per_class,
            "confusion_matrix": cm.tolist(), "label_order": labels_range,
            "normal_to_sudden": int(cm[idx["NORMAL"], idx["SUDDEN_MOVEMENT"]]),
            "sudden_to_normal": int(cm[idx["SUDDEN_MOVEMENT"], idx["NORMAL"]]),
            "fall_to_normal": int(cm[idx["FALL"], idx["NORMAL"]]),
            "normal_to_fall": int(cm[idx["NORMAL"], idx["FALL"]]),
        }

    candidate_eval = eval_5class(cand_pred_labels, y_test_true_labels)
    original_eval_collapsed = eval_5class(orig_pred_labels5, y_test_true_labels)

    comparison = {
        "locked_test_recordings": sorted(locked_test_recordings),
        "total_test_windows": int(len(testset)),
        "candidate_node_count": int(n_nodes),
        "original_v5_sha256": original_sha256,
        "candidate_sha256": candidate_sha256,
        "note": "original_v5 evaluated as its native 7-class model, then PUSH/PULL/JERK predictions collapsed to SUDDEN_MOVEMENT for a fair comparison against the 5-class candidate.",
        "original_v5_collapsed": {
            "accuracy": original_eval_collapsed["accuracy"], "macro_f1": original_eval_collapsed["macro_f1"],
            "per_class": original_eval_collapsed["per_class"],
            "normal_to_sudden": original_eval_collapsed["normal_to_sudden"],
            "sudden_to_normal": original_eval_collapsed["sudden_to_normal"],
            "fall_to_normal": original_eval_collapsed["fall_to_normal"],
            "normal_to_fall": original_eval_collapsed["normal_to_fall"],
        },
        "candidate": {
            "accuracy": candidate_eval["accuracy"], "macro_f1": candidate_eval["macro_f1"],
            "per_class": candidate_eval["per_class"],
            "normal_to_sudden": candidate_eval["normal_to_sudden"],
            "sudden_to_normal": candidate_eval["sudden_to_normal"],
            "fall_to_normal": candidate_eval["fall_to_normal"],
            "normal_to_fall": candidate_eval["normal_to_fall"],
        },
    }
    with open(COMPARISON_JSON_PATH, "w") as f:
        json.dump(comparison, f, indent=2)

    with open(COMPARISON_TXT_PATH, "w") as f:
        f.write("V7 MERGED PUSH/PULL/JERK CANDIDATE vs ORIGINAL V5 (collapsed) - LOCKED TEST (22 recordings)\n")
        f.write("=" * 70 + "\n\n")
        f.write(f"Original V5 SHA-256: {original_sha256}\n")
        f.write(f"Candidate SHA-256:   {candidate_sha256}\n")
        f.write(f"Candidate nodes:     {n_nodes:,}\n\n")
        f.write(f"Accuracy:  original={original_eval_collapsed['accuracy']:.4f}  candidate={candidate_eval['accuracy']:.4f}\n")
        f.write(f"Macro F1:  original={original_eval_collapsed['macro_f1']:.4f}  candidate={candidate_eval['macro_f1']:.4f}\n\n")
        f.write("SUDDEN_MOVEMENT:\n")
        o_sm, c_sm = original_eval_collapsed["per_class"]["SUDDEN_MOVEMENT"], candidate_eval["per_class"]["SUDDEN_MOVEMENT"]
        f.write(f"  precision: original={o_sm['precision']:.4f} candidate={c_sm['precision']:.4f}\n")
        f.write(f"  recall:    original={o_sm['recall']:.4f} candidate={c_sm['recall']:.4f}\n")
        f.write(f"  f1:        original={o_sm['f1']:.4f} candidate={c_sm['f1']:.4f}\n\n")
        f.write(f"NORMAL->SUDDEN_MOVEMENT: original={original_eval_collapsed['normal_to_sudden']} candidate={candidate_eval['normal_to_sudden']}\n")
        f.write(f"SUDDEN_MOVEMENT->NORMAL: original={original_eval_collapsed['sudden_to_normal']} candidate={candidate_eval['sudden_to_normal']}\n")
        f.write(f"FALL->NORMAL: original={original_eval_collapsed['fall_to_normal']} candidate={candidate_eval['fall_to_normal']}\n")
        f.write(f"NORMAL->FALL: original={original_eval_collapsed['normal_to_fall']} candidate={candidate_eval['normal_to_fall']}\n")

    print("\n" + "=" * 70)
    print("LOCKED TEST COMPARISON")
    print("=" * 70)
    print(json.dumps(comparison, indent=2))
    print(f"\nReports written to {OUT_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
