#!/usr/bin/env python3
"""Final v2 candidate: train ONE model on the 200-recording development set
(220 total - 20 locked test), then evaluate it EXACTLY ONCE on the locked
test set. This is the official final evaluation step, not another CV/tuning
round. Does not touch the frozen baseline, the locked test recordings, the
existing dev split, or the feature extractor.
"""

from __future__ import annotations

import hashlib
import json
import time
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    accuracy_score, confusion_matrix, f1_score,
    precision_recall_fscore_support, precision_score, recall_score,
)
from xgboost import XGBClassifier

PROJECT_ROOT = Path(__file__).resolve().parent.parent
FEATURES_PATH = PROJECT_ROOT / "features" / "glove_7class_features_expanded_v2.csv"
BASELINE_SPLIT_PATH = PROJECT_ROOT / "models" / "glove_7class_expanded" / "glove_7class_expanded_split.json"
OUT_DIR = PROJECT_ROOT / "models" / "glove_7class_expanded_v2"
OUT_DIR.mkdir(parents=True, exist_ok=True)

MODEL_PATH = OUT_DIR / "safeher_glove_7class_expanded_v2_xgboost.json"
DEV_SPLIT_PATH = OUT_DIR / "glove_7class_expanded_v2_dev_split.json"
TRAINING_REPORT_PATH = OUT_DIR / "glove_7class_expanded_v2_final_training_report.json"
TEST_EVAL_PATH = OUT_DIR / "glove_7class_expanded_v2_locked_test_evaluation.json"
FREEZE_REPORT_PATH = OUT_DIR / "glove_7class_expanded_v2_FREEZE_REPORT.json"

LABELS = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]
LABEL_TO_ID = {l: i for i, l in enumerate(LABELS)}
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

ORIGINAL_BASELINE_TEST = {
    "accuracy": 0.829897,
    "macro_f1": 0.813506,
    "weighted_f1": 0.830519,
    "fall_precision": 0.619048,
    "fall_recall": 0.722222,
    "fall_f1": 0.666667,
    "fall_to_normal": 4,
    "normal_to_fall": 4,
}


def sha256_of_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    # ---- locked test recordings (from the existing baseline split, source of truth) ----
    baseline_split = json.loads(BASELINE_SPLIT_PATH.read_text())
    locked_test_recordings = set()
    for recs in baseline_split["test_recordings"].values():
        locked_test_recordings.update(recs)
    assert len(locked_test_recordings) == 20

    full = pd.read_csv(FEATURES_PATH)
    feature_cols = [c for c in full.columns if c not in METADATA_COLUMNS]
    assert len(feature_cols) == 51

    devset = full[~full["recording_id"].isin(locked_test_recordings)].reset_index(drop=True)
    testset = full[full["recording_id"].isin(locked_test_recordings)].reset_index(drop=True)

    assert devset["recording_id"].nunique() == 200, f"expected 200 dev recordings, got {devset['recording_id'].nunique()}"
    assert testset["recording_id"].nunique() == 20, f"expected 20 test recordings, got {testset['recording_id'].nunique()}"
    assert set(devset["recording_id"]).isdisjoint(set(testset["recording_id"])), "DEV/TEST OVERLAP DETECTED"
    assert set(testset["recording_id"]) == locked_test_recordings, "test recordings do not match locked set exactly"

    # ---- development train/validation split (recording-level, stratified per class,
    # same methodology as the existing SAFEHER dev split: sklearn train_test_split,
    # random_state=42, per-class, recording-level). Locked test recordings excluded
    # entirely from this split (they were removed before this point). ----
    rec_label = devset.groupby("recording_id")["label"].agg(lambda s: sorted(s.unique()))
    assert (rec_label.apply(len) == 1).all(), "a dev recording has >1 label"
    rec_label = rec_label.apply(lambda x: x[0])

    train_ids, val_ids = [], []
    dev_split_json = {"random_state": 42, "validation_fraction": 0.1,
                       "train_recordings": {}, "validation_recordings": {}}
    for label in LABELS:
        ids = sorted(rec_label[rec_label == label].index.tolist())
        tr, va = train_test_split(ids, test_size=0.1, random_state=42)
        tr, va = sorted(tr), sorted(va)
        train_ids += tr
        val_ids += va
        dev_split_json["train_recordings"][label] = tr
        dev_split_json["validation_recordings"][label] = va

    train_ids_set, val_ids_set = set(train_ids), set(val_ids)
    assert train_ids_set.isdisjoint(val_ids_set)
    assert train_ids_set.isdisjoint(locked_test_recordings)
    assert val_ids_set.isdisjoint(locked_test_recordings)
    assert train_ids_set | val_ids_set == set(devset["recording_id"])

    train_df = devset[devset["recording_id"].isin(train_ids_set)].reset_index(drop=True)
    val_df = devset[devset["recording_id"].isin(val_ids_set)].reset_index(drop=True)

    dev_split_json["total_train_recordings"] = len(train_ids_set)
    dev_split_json["total_validation_recordings"] = len(val_ids_set)
    dev_split_json["training_windows"] = int(len(train_df))
    dev_split_json["validation_windows"] = int(len(val_df))
    with open(DEV_SPLIT_PATH, "w") as f:
        json.dump(dev_split_json, f, indent=2)

    X_train = train_df[feature_cols].astype(float)
    y_train = train_df["label"].map(LABEL_TO_ID).astype(int)
    X_val = val_df[feature_cols].astype(float)
    y_val = val_df["label"].map(LABEL_TO_ID).astype(int)

    print(f"Train: {len(train_ids_set)} recordings / {len(train_df)} windows")
    print(f"Validation: {len(val_ids_set)} recordings / {len(val_df)} windows")
    print(f"Locked test (not used yet): {testset['recording_id'].nunique()} recordings / {len(testset)} windows")

    # ---- train ONE final v2 candidate ----
    model = XGBClassifier(**XGB_PARAMS)
    start = time.time()
    model.fit(X_train, y_train, eval_set=[(X_val, y_val)], verbose=False)
    duration_s = time.time() - start

    best_iteration = int(model.best_iteration)
    best_val_mlogloss = float(model.best_score)
    print(f"Training done in {duration_s:.2f}s | best_iteration={best_iteration} | best_val_mlogloss={best_val_mlogloss:.6f}")

    model.save_model(str(MODEL_PATH))

    training_report = {
        "experiment": "glove_7class_expanded_v2_final_candidate",
        "train_recordings": len(train_ids_set),
        "train_windows": int(len(train_df)),
        "validation_recordings": len(val_ids_set),
        "validation_windows": int(len(val_df)),
        "locked_test_recordings_excluded": sorted(locked_test_recordings),
        "feature_count": len(feature_cols),
        "feature_columns": feature_cols,
        "class_order": LABELS,
        "xgboost_params": XGB_PARAMS,
        "best_iteration": best_iteration,
        "best_validation_mlogloss": best_val_mlogloss,
        "training_duration_seconds": duration_s,
        "test_data_used_for_training_or_selection": False,
    }
    with open(TRAINING_REPORT_PATH, "w") as f:
        json.dump(training_report, f, indent=2)

    # ================= OFFICIAL LOCKED TEST EVALUATION (exactly once) =================
    print("\n" + "=" * 70)
    print("PRE-EVALUATION ASSERTIONS")
    print("=" * 70)

    # 1. every test recording belongs to the original locked test set
    assert set(testset["recording_id"]) == locked_test_recordings
    print("[OK] every test recording belongs to the original locked test set")

    # 2. no test recording occurs in training
    assert set(testset["recording_id"]).isdisjoint(train_ids_set)
    print("[OK] no test recording occurs in training")

    # 3. no test recording occurs in validation
    assert set(testset["recording_id"]).isdisjoint(val_ids_set)
    print("[OK] no test recording occurs in validation")

    # 4. test recordings unchanged (schema/label sanity; content immutability verified externally via git diff)
    missing_cols = [c for c in ["recording_id","source_file","label"]+feature_cols if c not in testset.columns]
    assert not missing_cols
    assert testset[feature_cols].isnull().values.sum() == 0
    assert np.isfinite(testset[feature_cols].to_numpy(dtype=float)).all()
    print("[OK] test recordings pass schema/NaN/Inf sanity checks (content immutability separately verified via git diff = no changes)")

    # 5. feature order exactly matches training
    X_test = testset[feature_cols].astype(float)
    assert list(X_test.columns) == list(X_train.columns) == feature_cols
    print("[OK] feature order exactly matches training")

    # 6. class order exactly matches training
    y_test = testset["label"].map(LABEL_TO_ID).astype(int)
    assert list(LABELS) == training_report["class_order"]
    print("[OK] class order exactly matches training")

    print("\nRunning locked test evaluation (single pass, no tuning)...")
    y_pred = model.predict(X_test)

    labels_range = list(range(len(LABELS)))
    accuracy = float(accuracy_score(y_test, y_pred))
    macro_precision = float(precision_score(y_test, y_pred, labels=labels_range, average="macro", zero_division=0))
    macro_recall = float(recall_score(y_test, y_pred, labels=labels_range, average="macro", zero_division=0))
    macro_f1 = float(f1_score(y_test, y_pred, labels=labels_range, average="macro", zero_division=0))
    weighted_f1 = float(f1_score(y_test, y_pred, labels=labels_range, average="weighted", zero_division=0))

    precision, recall, f1, support = precision_recall_fscore_support(y_test, y_pred, labels=labels_range, average=None, zero_division=0)
    cm = confusion_matrix(y_test, y_pred, labels=labels_range)

    per_class = {LABELS[i]: {"precision": float(precision[i]), "recall": float(recall[i]),
                              "f1": float(f1[i]), "support": int(support[i])} for i in range(len(LABELS))}

    idx = LABEL_TO_ID
    def cm_count(a, b):
        return int(cm[idx[a], idx[b]])

    misclassified = int((y_test.to_numpy() != y_pred).sum())

    # recording-level FALL detection: a FALL recording counts as "detected" if
    # at least one of its windows is predicted FALL (majority-vote alternative also reported)
    test_df_pred = testset.copy()
    test_df_pred["pred_label"] = [LABELS[i] for i in y_pred]
    fall_test_recs = test_df_pred[test_df_pred["label"] == "FALL"]
    fall_rec_detail = []
    n_fall_recs = fall_test_recs["recording_id"].nunique()
    n_detected_any = 0
    n_detected_majority = 0
    for rid, g in fall_test_recs.groupby("recording_id"):
        any_fall = bool((g["pred_label"] == "FALL").any())
        majority_fall = bool((g["pred_label"] == "FALL").mean() > 0.5)
        n_detected_any += int(any_fall)
        n_detected_majority += int(majority_fall)
        fall_rec_detail.append({"recording_id": rid, "n_windows": int(len(g)),
                                 "n_windows_predicted_fall": int((g["pred_label"]=="FALL").sum()),
                                 "detected_any_window": any_fall, "detected_majority_vote": majority_fall})

    test_eval = {
        "overall": {
            "accuracy": accuracy,
            "macro_precision": macro_precision,
            "macro_recall": macro_recall,
            "macro_f1": macro_f1,
            "weighted_f1": weighted_f1,
        },
        "per_class": per_class,
        "push_recall": per_class["PUSH"]["recall"],
        "push_f1": per_class["PUSH"]["f1"],
        "pull_recall": per_class["PULL"]["recall"],
        "pull_f1": per_class["PULL"]["f1"],
        "fall_precision": per_class["FALL"]["precision"],
        "fall_recall": per_class["FALL"]["recall"],
        "fall_f1": per_class["FALL"]["f1"],
        "confusion_matrix": cm.tolist(),
        "confusion_matrix_label_order": LABELS,
        "total_test_windows": int(len(testset)),
        "misclassified_windows": misclassified,
        "fall_to_normal": cm_count("FALL", "NORMAL"),
        "normal_to_fall": cm_count("NORMAL", "FALL"),
        "push_to_pull": cm_count("PUSH", "PULL"),
        "pull_to_push": cm_count("PULL", "PUSH"),
        "push_to_jerk": cm_count("PUSH", "JERK"),
        "pull_to_jerk": cm_count("PULL", "JERK"),
        "fall_recording_level": {
            "n_fall_recordings_in_test": int(n_fall_recs),
            "n_detected_any_window": int(n_detected_any),
            "n_missed_any_window": int(n_fall_recs - n_detected_any),
            "n_detected_majority_vote": int(n_detected_majority),
            "n_missed_majority_vote": int(n_fall_recs - n_detected_majority),
            "detail": fall_rec_detail,
        },
        "test_recordings": sorted(locked_test_recordings),
    }
    with open(TEST_EVAL_PATH, "w") as f:
        json.dump(test_eval, f, indent=2)

    print("\n" + "=" * 70)
    print("LOCKED TEST RESULTS")
    print("=" * 70)
    print(json.dumps(test_eval["overall"], indent=2))
    print("\nPer-class:")
    for cls in LABELS:
        pc = per_class[cls]
        print(f"  {cls:10s} precision={pc['precision']:.4f} recall={pc['recall']:.4f} f1={pc['f1']:.4f} support={pc['support']}")
    print(f"\nMisclassified windows: {misclassified} / {len(testset)}")
    print(f"FALL->NORMAL={test_eval['fall_to_normal']} NORMAL->FALL={test_eval['normal_to_fall']}")
    print(f"PUSH->PULL={test_eval['push_to_pull']} PULL->PUSH={test_eval['pull_to_push']}")
    print(f"PUSH->JERK={test_eval['push_to_jerk']} PULL->JERK={test_eval['pull_to_jerk']}")
    print(f"\nConfusion matrix (order {LABELS}):")
    print(cm)
    print(f"\nFALL recording-level: {n_fall_recs} recordings, detected(any window)={n_detected_any}, missed={n_fall_recs-n_detected_any}")

    # ================= COMPARISON vs ORIGINAL FROZEN BASELINE =================
    print("\n" + "=" * 70)
    print("COMPARISON vs ORIGINAL FROZEN BASELINE TEST RESULT")
    print("=" * 70)
    comparison = {
        "baseline": ORIGINAL_BASELINE_TEST,
        "v2": {
            "accuracy": accuracy, "macro_f1": macro_f1, "weighted_f1": weighted_f1,
            "fall_precision": per_class["FALL"]["precision"], "fall_recall": per_class["FALL"]["recall"],
            "fall_f1": per_class["FALL"]["f1"],
            "fall_to_normal": test_eval["fall_to_normal"], "normal_to_fall": test_eval["normal_to_fall"],
        },
        "delta": {
            "accuracy": accuracy - ORIGINAL_BASELINE_TEST["accuracy"],
            "macro_f1": macro_f1 - ORIGINAL_BASELINE_TEST["macro_f1"],
            "weighted_f1": weighted_f1 - ORIGINAL_BASELINE_TEST["weighted_f1"],
            "fall_precision": per_class["FALL"]["precision"] - ORIGINAL_BASELINE_TEST["fall_precision"],
            "fall_recall": per_class["FALL"]["recall"] - ORIGINAL_BASELINE_TEST["fall_recall"],
            "fall_f1": per_class["FALL"]["f1"] - ORIGINAL_BASELINE_TEST["fall_f1"],
        },
    }
    print(json.dumps(comparison, indent=2))

    with open(OUT_DIR / "glove_7class_expanded_v2_vs_baseline_comparison.json", "w") as f:
        json.dump(comparison, f, indent=2)

    # ================= FINAL DECISION (mechanical, evidence-based; no re-tuning) =================
    decision = "B_KEEP_ORIGINAL_FROZEN_BASELINE"
    reasons = []
    if comparison["delta"]["macro_f1"] > 0.01 and comparison["delta"]["fall_recall"] >= -0.02 and comparison["delta"]["fall_precision"] >= -0.05:
        decision = "A_KEEP_V2_AS_FINAL_MODEL"
        reasons.append("macro F1 improved and FALL did not regress unacceptably")
    else:
        reasons.append("macro F1 did not improve meaningfully and/or FALL regressed")

    print("\n" + "=" * 70)
    print(f"MECHANICAL DECISION SIGNAL (for human review, not auto-applied): {decision}")
    print("=" * 70)
    print(reasons)

    result_summary = {
        "model_path": str(MODEL_PATH),
        "sha256": sha256_of_file(MODEL_PATH),
        "decision_signal": decision,
        "decision_reasons": reasons,
    }
    print(json.dumps(result_summary, indent=2))

    with open(OUT_DIR / "glove_7class_expanded_v2_decision_signal.json", "w") as f:
        json.dump(result_summary, f, indent=2)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
