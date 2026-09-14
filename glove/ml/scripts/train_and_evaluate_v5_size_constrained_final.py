#!/usr/bin/env python3
"""Train the SIZE-CONSTRAINED candidate (Config A: same depth/estimators as
V5, but min_child_weight=30 to prune weakly-justified splits) on all 208
development recordings, then perform EXACTLY ONE official evaluation on the
locked 22-recording test set, compared against the ORIGINAL frozen
production V5 model evaluated on that same set.

Why this candidate exists: the fall-complete candidate (same investigation,
trained with the exact V5 config) does not fit the ESP32-C3 flash budget
(155,446 nodes -> compiled sketch was 152% of the 2,097,152-byte maximum).
A node-count/CV grid search (check_node_count_grid.py, cv_v5_size_constrained.py)
found that adding min_child_weight=30 (all else identical to V5's config)
shrinks the model to 50,176 nodes (~82% of flash budget) while keeping
FALL recall essentially unchanged in CV (0.7335 vs 0.7338 baseline) and
actually reducing fall-to-normal misses in CV (80 vs 90 baseline).

Per this project's standing rule: the locked test set is evaluated exactly
once per genuinely distinct final candidate, and the result is reported
honestly, not used to tune anything further.

Does NOT modify, retrain, or overwrite the original V5 model file - it is
loaded fresh, read-only, purely for the comparison.
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
    precision_recall_fscore_support, precision_score, recall_score,
)
from xgboost import XGBClassifier

PROJECT_ROOT = Path(__file__).resolve().parent.parent  # glove/ml
FEATURES_PATH = PROJECT_ROOT / "features" / "glove_7class_features_v7_fall_complete.csv"
V5_SPLIT_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_train_test_split.json"
V5_MODEL_PATH = PROJECT_ROOT / "models" / "safeher_glove_7class_v5_xgboost.json"
V5_FEATURE_COLUMNS_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_feature_columns.json"
DATASET_ROOT = PROJECT_ROOT / "dataset"

OUT_DIR = PROJECT_ROOT / "models" / "glove_7class_v5_size_constrained_final"
OUT_DIR.mkdir(parents=True, exist_ok=True)

CANDIDATE_MODEL_PATH = OUT_DIR / "safeher_glove_7class_v5_size_constrained_candidate_xgboost.json"
TRAINING_REPORT_PATH = OUT_DIR / "v5_size_constrained_candidate_training_report.json"
LOCKED_TEST_EVAL_PATH = OUT_DIR / "v5_size_constrained_candidate_locked_test_evaluation.json"
COMPARISON_PATH = OUT_DIR / "v5_size_constrained_candidate_vs_original_v5_comparison.json"
COMPARISON_TXT_PATH = OUT_DIR / "v5_size_constrained_candidate_vs_original_v5_comparison.txt"

LABELS = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]
LABEL_TO_ID = {l: i for i, l in enumerate(LABELS)}
METADATA_COLUMNS = ["recording_id", "source_file", "label"]

# Config A from the CV grid search: identical to V5's exact config, plus
# min_child_weight=30 to prune weakly-justified splits (reduces node count).
SIZE_CONSTRAINED_XGB_PARAMS = dict(
    n_estimators=600,
    max_depth=6,
    min_child_weight=30,
    gamma=0.0,
    learning_rate=0.05,
    subsample=0.9,
    colsample_bytree=0.9,
    random_state=42,
    objective="multi:softprob",
    num_class=len(LABELS),
    eval_metric="mlogloss",
    n_jobs=1,
)


def sha256_of_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def evaluate_on(booster_or_model, X, y_true_id, feature_cols, use_booster_predict=False):
    if use_booster_predict:
        proba = booster_or_model.inplace_predict(X[feature_cols].astype(float).to_numpy())
    else:
        proba = booster_or_model.predict_proba(X[feature_cols].astype(float))
    y_pred = np.argmax(proba, axis=1)

    labels_range = list(range(len(LABELS)))
    accuracy = float(accuracy_score(y_true_id, y_pred))
    macro_precision = float(precision_score(y_true_id, y_pred, labels=labels_range, average="macro", zero_division=0))
    macro_recall = float(recall_score(y_true_id, y_pred, labels=labels_range, average="macro", zero_division=0))
    macro_f1 = float(f1_score(y_true_id, y_pred, labels=labels_range, average="macro", zero_division=0))
    weighted_f1 = float(f1_score(y_true_id, y_pred, labels=labels_range, average="weighted", zero_division=0))

    precision, recall, f1, support = precision_recall_fscore_support(y_true_id, y_pred, labels=labels_range, average=None, zero_division=0)
    cm = confusion_matrix(y_true_id, y_pred, labels=labels_range)

    per_class = {LABELS[i]: {"precision": float(precision[i]), "recall": float(recall[i]),
                              "f1": float(f1[i]), "support": int(support[i])} for i in range(len(LABELS))}

    idx = LABEL_TO_ID
    def cm_count(a, b):
        return int(cm[idx[a], idx[b]])

    return {
        "accuracy": accuracy, "macro_precision": macro_precision, "macro_recall": macro_recall,
        "macro_f1": macro_f1, "weighted_f1": weighted_f1,
        "per_class": per_class,
        "confusion_matrix": cm.tolist(), "confusion_matrix_label_order": LABELS,
        "fall_to_normal": cm_count("FALL", "NORMAL"), "normal_to_fall": cm_count("NORMAL", "FALL"),
        "push_to_pull": cm_count("PUSH", "PULL"), "pull_to_push": cm_count("PULL", "PUSH"),
        "push_to_jerk": cm_count("PUSH", "JERK"), "pull_to_jerk": cm_count("PULL", "JERK"),
        "total_windows": int(len(y_true_id)), "misclassified_windows": int((y_pred != y_true_id).sum()),
    }


def main():
    v5_split = json.loads(V5_SPLIT_PATH.read_text())
    locked_test_recordings = set()
    for recs in v5_split["test_recordings"].values():
        locked_test_recordings.update(recs)
    assert len(locked_test_recordings) == 22, f"expected 22 locked test recordings, found {len(locked_test_recordings)}"

    for rid in locked_test_recordings:
        cls_guess = next((label.lower() for label in LABELS if rid.startswith(label.lower())), None)
        assert cls_guess is not None
        fp = DATASET_ROOT / cls_guess / f"{rid}.csv"
        assert fp.exists() and fp.stat().st_size > 0, f"locked test recording missing/empty: {fp}"
    print("[OK] All 22 locked test recordings present and non-empty on disk.")

    full_features = pd.read_csv(FEATURES_PATH)
    feature_cols = [c for c in full_features.columns if c not in METADATA_COLUMNS]
    assert len(feature_cols) == 51

    devset = full_features[~full_features["recording_id"].isin(locked_test_recordings)].reset_index(drop=True)
    testset = full_features[full_features["recording_id"].isin(locked_test_recordings)].reset_index(drop=True)

    n_dev_recordings = devset["recording_id"].nunique()
    n_test_recordings = testset["recording_id"].nunique()
    assert n_dev_recordings == 208, f"expected 208 dev recordings, got {n_dev_recordings}"
    assert n_test_recordings == 22, f"expected 22 test recordings, got {n_test_recordings}"
    assert set(devset["recording_id"]).isdisjoint(set(testset["recording_id"])), "DEV/TEST OVERLAP DETECTED"
    assert set(testset["recording_id"]) == locked_test_recordings, "test set does not exactly match locked set"

    print(f"Development: {n_dev_recordings} recordings / {len(devset)} windows")
    print(f"Locked test (NOT touched until after training): {n_test_recordings} recordings / {len(testset)} windows")

    X_train = devset[feature_cols].astype(float)
    y_train = devset["label"].map(LABEL_TO_ID).astype(int)

    print("\nTraining size-constrained candidate on ALL 208 development recordings...")
    print(json.dumps(SIZE_CONSTRAINED_XGB_PARAMS, indent=2))

    model = XGBClassifier(**SIZE_CONSTRAINED_XGB_PARAMS)
    start = time.time()
    model.fit(X_train, y_train)
    duration_s = time.time() - start
    print(f"Training complete in {duration_s:.2f}s.")

    model.save_model(str(CANDIDATE_MODEL_PATH))
    candidate_sha256 = sha256_of_file(CANDIDATE_MODEL_PATH)

    booster = model.get_booster()
    tree_df = booster.trees_to_dataframe()
    n_nodes = len(tree_df)
    print(f"Candidate node count: {n_nodes:,} (node_bytes={n_nodes*14:,})")

    training_report = {
        "experiment": "v5_size_constrained_candidate_final",
        "description": "Size-constrained candidate (Config A: V5 config + min_child_weight=30) trained after the fall-complete candidate proved too large for ESP32-C3 flash. Selected via CV grid search prioritizing FALL recall preservation over raw accuracy.",
        "train_recordings": n_dev_recordings,
        "train_windows": int(len(devset)),
        "locked_test_recordings_excluded": sorted(locked_test_recordings),
        "feature_count": len(feature_cols),
        "feature_columns": feature_cols,
        "class_order": LABELS,
        "xgboost_params": SIZE_CONSTRAINED_XGB_PARAMS,
        "node_count": int(n_nodes),
        "estimated_node_table_bytes": int(n_nodes * 14),
        "no_eval_set": True,
        "no_early_stopping": True,
        "no_validation_split": True,
        "training_duration_seconds": duration_s,
        "model_path": str(CANDIDATE_MODEL_PATH),
        "model_sha256": candidate_sha256,
        "test_data_used_for_training_or_selection": False,
    }
    with open(TRAINING_REPORT_PATH, "w") as f:
        json.dump(training_report, f, indent=2)
    print(f"Candidate model saved: {CANDIDATE_MODEL_PATH}")
    print(f"Candidate SHA-256: {candidate_sha256}")

    print("\n" + "=" * 70)
    print("PRE-EVALUATION ASSERTIONS")
    print("=" * 70)
    assert set(testset["recording_id"]) == locked_test_recordings
    print("[OK] test recordings match the locked set exactly")
    assert set(testset["recording_id"]).isdisjoint(set(devset["recording_id"]))
    print("[OK] no test recording occurs in training")
    X_test = testset[feature_cols].astype(float)
    assert list(X_test.columns) == list(X_train.columns) == feature_cols
    print("[OK] feature order exactly matches training")
    y_test = testset["label"].map(LABEL_TO_ID).astype(int)
    print("[OK] class order exactly matches training")

    original_sha256 = sha256_of_file(V5_MODEL_PATH)
    original_feature_cols = json.loads(V5_FEATURE_COLUMNS_PATH.read_text())
    assert original_feature_cols == feature_cols, "feature order mismatch between original V5 and candidate feature set"

    original_bst = xgb.Booster()
    original_bst.load_model(str(V5_MODEL_PATH))

    original_sha256_after = sha256_of_file(V5_MODEL_PATH)
    assert original_sha256 == original_sha256_after, "original V5 model file changed during this script - ABORT"

    print("\nRunning locked test evaluation (single pass each, no tuning)...")
    candidate_eval = evaluate_on(model, testset, y_test.to_numpy(), feature_cols, use_booster_predict=False)
    original_eval = evaluate_on(original_bst, testset, y_test.to_numpy(), feature_cols, use_booster_predict=True)

    with open(LOCKED_TEST_EVAL_PATH, "w") as f:
        json.dump({"candidate": candidate_eval, "original_v5": original_eval}, f, indent=2)

    original_sha256_final = sha256_of_file(V5_MODEL_PATH)
    assert original_sha256 == original_sha256_final, "original V5 model file changed after evaluation - ABORT"
    print(f"[OK] original V5 model file unchanged throughout (SHA-256: {original_sha256})")

    comparison = {
        "locked_test_recordings": sorted(locked_test_recordings),
        "total_test_windows": candidate_eval["total_windows"],
        "candidate_node_count": int(n_nodes),
        "original_v5": {
            "model_path": str(V5_MODEL_PATH), "sha256": original_sha256,
            "accuracy": original_eval["accuracy"], "macro_f1": original_eval["macro_f1"],
            "weighted_f1": original_eval["weighted_f1"],
            "fall_precision": original_eval["per_class"]["FALL"]["precision"],
            "fall_recall": original_eval["per_class"]["FALL"]["recall"],
            "fall_f1": original_eval["per_class"]["FALL"]["f1"],
            "normal_precision": original_eval["per_class"]["NORMAL"]["precision"],
            "normal_recall": original_eval["per_class"]["NORMAL"]["recall"],
            "fall_to_normal": original_eval["fall_to_normal"], "normal_to_fall": original_eval["normal_to_fall"],
        },
        "candidate": {
            "model_path": str(CANDIDATE_MODEL_PATH), "sha256": candidate_sha256,
            "accuracy": candidate_eval["accuracy"], "macro_f1": candidate_eval["macro_f1"],
            "weighted_f1": candidate_eval["weighted_f1"],
            "fall_precision": candidate_eval["per_class"]["FALL"]["precision"],
            "fall_recall": candidate_eval["per_class"]["FALL"]["recall"],
            "fall_f1": candidate_eval["per_class"]["FALL"]["f1"],
            "normal_precision": candidate_eval["per_class"]["NORMAL"]["precision"],
            "normal_recall": candidate_eval["per_class"]["NORMAL"]["recall"],
            "fall_to_normal": candidate_eval["fall_to_normal"], "normal_to_fall": candidate_eval["normal_to_fall"],
        },
        "delta_candidate_minus_original": {
            "accuracy": candidate_eval["accuracy"] - original_eval["accuracy"],
            "macro_f1": candidate_eval["macro_f1"] - original_eval["macro_f1"],
            "weighted_f1": candidate_eval["weighted_f1"] - original_eval["weighted_f1"],
            "fall_recall": candidate_eval["per_class"]["FALL"]["recall"] - original_eval["per_class"]["FALL"]["recall"],
            "fall_precision": candidate_eval["per_class"]["FALL"]["precision"] - original_eval["per_class"]["FALL"]["precision"],
            "normal_recall": candidate_eval["per_class"]["NORMAL"]["recall"] - original_eval["per_class"]["NORMAL"]["recall"],
        },
        "per_class_both": {
            cls: {"original": original_eval["per_class"][cls], "candidate": candidate_eval["per_class"][cls]}
            for cls in LABELS
        },
    }
    with open(COMPARISON_PATH, "w") as f:
        json.dump(comparison, f, indent=2)

    with open(COMPARISON_TXT_PATH, "w") as f:
        f.write("V5 SIZE-CONSTRAINED CANDIDATE vs ORIGINAL V5 - LOCKED TEST EVALUATION (22 recordings)\n")
        f.write("=" * 70 + "\n\n")
        f.write(f"Original V5 SHA-256:   {original_sha256}\n")
        f.write(f"Candidate SHA-256:     {candidate_sha256}\n")
        f.write(f"Candidate node count:  {n_nodes:,}\n\n")
        f.write(f"{'Metric':<20} {'Original V5':>15} {'Candidate':>15} {'Delta':>10}\n")
        for label, key in [("Accuracy", "accuracy"), ("Macro F1", "macro_f1"), ("Weighted F1", "weighted_f1")]:
            o, c = comparison["original_v5"][key], comparison["candidate"][key]
            f.write(f"{label:<20} {o:>15.4f} {c:>15.4f} {c-o:>+10.4f}\n")
        f.write(f"{'FALL precision':<20} {comparison['original_v5']['fall_precision']:>15.4f} {comparison['candidate']['fall_precision']:>15.4f} {comparison['delta_candidate_minus_original']['fall_precision']:>+10.4f}\n")
        f.write(f"{'FALL recall':<20} {comparison['original_v5']['fall_recall']:>15.4f} {comparison['candidate']['fall_recall']:>15.4f} {comparison['delta_candidate_minus_original']['fall_recall']:>+10.4f}\n")
        f.write(f"{'NORMAL recall':<20} {comparison['original_v5']['normal_recall']:>15.4f} {comparison['candidate']['normal_recall']:>15.4f} {comparison['delta_candidate_minus_original']['normal_recall']:>+10.4f}\n")
        f.write(f"\nFALL->NORMAL: original={comparison['original_v5']['fall_to_normal']} candidate={comparison['candidate']['fall_to_normal']}\n")
        f.write(f"NORMAL->FALL: original={comparison['original_v5']['normal_to_fall']} candidate={comparison['candidate']['normal_to_fall']}\n")

    print("\n" + "=" * 70)
    print("LOCKED TEST COMPARISON")
    print("=" * 70)
    print(json.dumps(comparison, indent=2))

    print(f"\nReports written to {OUT_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
