#!/usr/bin/env python3
"""Controlled ablation: does removing normal_043 / normal_066 / normal_068
(individually or together) recover the FALL/TWISTING/accuracy regression seen
when retraining V5's exact configuration on the NORMAL-expanded 230-recording
dataset?

Experiments (dev set built from the 230-recording feature file, minus V5's
own 22-recording locked test set = 208 development recordings, exactly as in
the prior "normal expanded candidate" experiment):
  A. reference = the already-trained/evaluated normal-expanded candidate (not
     retrained here - reused for a clean side-by-side comparison only).
  B. exclude normal_043 from development.
  C. exclude normal_066 from development.
  D. exclude normal_068 from development.
  E. exclude all three from development.

For B-E: same 5-fold StratifiedGroupKFold CV methodology already used, then
ONE final candidate trained on the full (ablated) development set, then
EXACTLY ONE locked-test evaluation per experiment - no repeated peeking, no
tuning based on test results.

Does not modify: the locked test set, the production V5 model, the raw
dataset, the feature extractor, or any existing experiment's saved model.
"""

from __future__ import annotations

import json
import time
import hashlib
from pathlib import Path

import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.metrics import (
    accuracy_score, confusion_matrix, f1_score, precision_recall_fscore_support,
)
from xgboost import XGBClassifier

PROJECT_ROOT = Path(__file__).resolve().parent.parent  # glove/ml
FEATURES_PATH = PROJECT_ROOT / "features" / "glove_7class_features_expanded_v3.csv"
V5_SPLIT_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_train_test_split.json"
V5_MODEL_PATH = PROJECT_ROOT / "models" / "safeher_glove_7class_v5_xgboost.json"
V5_FEATURE_COLUMNS_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_feature_columns.json"
REFERENCE_CANDIDATE_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_normal_expanded_cv" / "safeher_glove_7class_v5_normal_expanded_candidate_xgboost.json"

OUT_DIR = PROJECT_ROOT / "models" / "glove_7class_normal_ablation"
OUT_DIR.mkdir(parents=True, exist_ok=True)

LABELS = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]
LABEL_TO_ID = {l: i for i, l in enumerate(LABELS)}
METADATA_COLUMNS = ["recording_id", "source_file", "label"]

V5_XGB_PARAMS = dict(
    n_estimators=600, max_depth=6, learning_rate=0.05, subsample=0.9, colsample_bytree=0.9,
    random_state=42, objective="multi:softprob", num_class=len(LABELS), eval_metric="mlogloss", n_jobs=1,
)

EXPERIMENTS = {
    "A_reference_full_expanded": [],
    "B_exclude_normal_043": ["normal_043"],
    "C_exclude_normal_066": ["normal_066"],
    "D_exclude_normal_068": ["normal_068"],
    "E_exclude_all_three": ["normal_043", "normal_066", "normal_068"],
}


def sha256_of_file(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def run_cv(devset, feature_cols):
    X_all = devset[feature_cols].astype(float)
    y_all = devset["label"].map(LABEL_TO_ID).astype(int).to_numpy()
    groups = devset["recording_id"].to_numpy()

    sgkf = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=42)
    fold_results = []
    for fold_idx, (tr, va) in enumerate(sgkf.split(X_all, y_all, groups), 1):
        train_recs, val_recs = set(groups[tr]), set(groups[va])
        assert train_recs.isdisjoint(val_recs)
        Xtr, ytr = X_all.iloc[tr], y_all[tr]
        Xva, yva = X_all.iloc[va], y_all[va]
        model = XGBClassifier(**V5_XGB_PARAMS)
        model.fit(Xtr, ytr)
        pred = model.predict(Xva)
        labels_range = list(range(len(LABELS)))
        cm = confusion_matrix(yva, pred, labels=labels_range)
        precision, recall, f1, support = precision_recall_fscore_support(yva, pred, labels=labels_range, average=None, zero_division=0)
        acc = accuracy_score(yva, pred)
        macro_f1 = f1_score(yva, pred, labels=labels_range, average="macro", zero_division=0)
        weighted_f1 = f1_score(yva, pred, labels=labels_range, average="weighted", zero_division=0)
        per_class = {LABELS[i]: {"precision": float(precision[i]), "recall": float(recall[i]), "f1": float(f1[i]), "support": int(support[i])} for i in range(len(LABELS))}
        fold_results.append({"fold": fold_idx, "n_train": len(train_recs), "n_val": len(val_recs),
                              "accuracy": float(acc), "macro_f1": float(macro_f1), "weighted_f1": float(weighted_f1),
                              "per_class": per_class})
        print(f"    fold {fold_idx}: acc={acc:.4f} macroF1={macro_f1:.4f} FALL_R={per_class['FALL']['recall']:.4f} "
              f"NORMAL_R={per_class['NORMAL']['recall']:.4f} TWISTING_R={per_class['TWISTING']['recall']:.4f}")

    df_folds = pd.DataFrame(fold_results)
    summary = {"accuracy": {"mean": float(df_folds["accuracy"].mean()), "std": float(df_folds["accuracy"].std(ddof=1))},
               "macro_f1": {"mean": float(df_folds["macro_f1"].mean()), "std": float(df_folds["macro_f1"].std(ddof=1))}}
    for cls in LABELS:
        vals = [fr["per_class"][cls]["recall"] for fr in fold_results]
        summary[f"{cls}_recall"] = {"mean": float(np.mean(vals)), "std": float(np.std(vals, ddof=1))}
    return fold_results, summary


def evaluate(proba, y_true):
    pred = np.argmax(proba, axis=1)
    labels_range = list(range(len(LABELS)))
    acc = float(accuracy_score(y_true, pred))
    macro_f1 = float(f1_score(y_true, pred, labels=labels_range, average="macro", zero_division=0))
    weighted_f1 = float(f1_score(y_true, pred, labels=labels_range, average="weighted", zero_division=0))
    precision, recall, f1, support = precision_recall_fscore_support(y_true, pred, labels=labels_range, average=None, zero_division=0)
    cm = confusion_matrix(y_true, pred, labels=labels_range)
    per_class = {LABELS[i]: {"precision": float(precision[i]), "recall": float(recall[i]), "f1": float(f1[i]), "support": int(support[i])} for i in range(len(LABELS))}
    idx = LABEL_TO_ID
    return {"accuracy": acc, "macro_f1": macro_f1, "weighted_f1": weighted_f1, "per_class": per_class,
            "confusion_matrix": cm.tolist(), "confusion_matrix_label_order": LABELS,
            "fall_to_normal": int(cm[idx["FALL"], idx["NORMAL"]]), "normal_to_fall": int(cm[idx["NORMAL"], idx["FALL"]])}


def main():
    v5_split = json.loads(V5_SPLIT_PATH.read_text())
    locked = set()
    for recs in v5_split["test_recordings"].values():
        locked.update(recs)
    assert len(locked) == 22

    full = pd.read_csv(FEATURES_PATH)
    feature_cols = json.loads(V5_FEATURE_COLUMNS_PATH.read_text())
    assert feature_cols == [c for c in full.columns if c not in METADATA_COLUMNS]

    devset_full = full[~full["recording_id"].isin(locked)].reset_index(drop=True)
    testset = full[full["recording_id"].isin(locked)].reset_index(drop=True)
    assert devset_full["recording_id"].nunique() == 208
    assert testset["recording_id"].nunique() == 22
    assert set(devset_full["recording_id"]).isdisjoint(set(testset["recording_id"]))

    X_test = testset[feature_cols].astype(float)
    y_test = testset["label"].map(LABEL_TO_ID).astype(int).to_numpy()

    orig_sha_before = sha256_of_file(V5_MODEL_PATH)

    all_results = {}

    for exp_name, exclude_ids in EXPERIMENTS.items():
        print(f"\n{'='*70}\nEXPERIMENT {exp_name} (excluding: {exclude_ids or 'none'})\n{'='*70}")
        exp_dir = OUT_DIR / exp_name
        exp_dir.mkdir(parents=True, exist_ok=True)

        if exp_name == "A_reference_full_expanded":
            # reuse already-trained reference candidate, do not retrain (deterministic anyway)
            assert REFERENCE_CANDIDATE_PATH.exists(), "reference candidate model not found"
            bst = xgb.Booster()
            bst.load_model(str(REFERENCE_CANDIDATE_PATH))
            proba = bst.inplace_predict(X_test.to_numpy())
            test_eval = evaluate(proba, y_test)
            model_sha = sha256_of_file(REFERENCE_CANDIDATE_PATH)
            cv_summary = None  # reuse prior CV report if present
            prior_cv_path = PROJECT_ROOT / "models" / "glove_7class_v5_normal_expanded_cv" / "cv_report.json"
            if prior_cv_path.exists():
                prior_cv = json.loads(prior_cv_path.read_text())
                cv_summary = {"note": "reused from prior experiment (glove_7class_v5_normal_expanded_cv/cv_report.json), not rerun"}
            print(f"  Reused reference candidate: {REFERENCE_CANDIDATE_PATH}")
            n_dev_recordings = devset_full["recording_id"].nunique()
            n_dev_windows = len(devset_full)
        else:
            devset = devset_full[~devset_full["recording_id"].isin(exclude_ids)].reset_index(drop=True)
            n_dev_recordings = devset["recording_id"].nunique()
            n_dev_windows = len(devset)
            assert set(devset["recording_id"]).isdisjoint(locked)
            for rid in exclude_ids:
                assert rid not in set(devset["recording_id"]), f"{rid} was not actually excluded!"
            print(f"  Development: {n_dev_recordings} recordings / {n_dev_windows} windows")

            print("  Running 5-fold CV...")
            fold_results, cv_summary = run_cv(devset, feature_cols)
            with open(exp_dir / "cv_report.json", "w") as f:
                json.dump({"fold_results": fold_results, "summary": cv_summary,
                           "development_recordings": n_dev_recordings, "development_windows": n_dev_windows,
                           "excluded_recordings": exclude_ids}, f, indent=2, default=str)

            print("  Training final candidate on full (ablated) development set...")
            X_train = devset[feature_cols].astype(float)
            y_train = devset["label"].map(LABEL_TO_ID).astype(int)
            model = XGBClassifier(**V5_XGB_PARAMS)
            start = time.time()
            model.fit(X_train, y_train)
            dur = time.time() - start
            print(f"    done in {dur:.1f}s")

            model_path = exp_dir / f"safeher_glove_7class_ablation_{exp_name}_xgboost.json"
            model.save_model(str(model_path))
            model_sha = sha256_of_file(model_path)

            proba = model.predict_proba(X_test)
            test_eval = evaluate(proba, y_test)

        with open(exp_dir / "locked_test_evaluation.json", "w") as f:
            json.dump(test_eval, f, indent=2)

        all_results[exp_name] = {
            "excluded_recordings": exclude_ids,
            "development_recordings": n_dev_recordings,
            "development_windows": n_dev_windows,
            "model_sha256": model_sha,
            "cv_summary": cv_summary,
            "locked_test": test_eval,
        }

        print(f"  LOCKED TEST: acc={test_eval['accuracy']:.4f} macroF1={test_eval['macro_f1']:.4f} "
              f"FALL_R={test_eval['per_class']['FALL']['recall']:.4f} "
              f"NORMAL_R={test_eval['per_class']['NORMAL']['recall']:.4f} "
              f"TWISTING_R={test_eval['per_class']['TWISTING']['recall']:.4f} "
              f"PUSH_R={test_eval['per_class']['PUSH']['recall']:.4f} "
              f"PULL_R={test_eval['per_class']['PULL']['recall']:.4f} "
              f"FALL->NORMAL={test_eval['fall_to_normal']} NORMAL->FALL={test_eval['normal_to_fall']}")

    orig_sha_after = sha256_of_file(V5_MODEL_PATH)
    assert orig_sha_before == orig_sha_after, "ORIGINAL V5 MODEL FILE CHANGED - ABORT"
    print(f"\n[OK] Original V5 model file unchanged throughout (SHA-256: {orig_sha_after})")

    # ============ comparison table (delta vs A) ============
    ref = all_results["A_reference_full_expanded"]["locked_test"]
    comparison = {}
    for exp_name, res in all_results.items():
        te = res["locked_test"]
        comparison[exp_name] = {
            "accuracy": te["accuracy"], "macro_f1": te["macro_f1"], "weighted_f1": te["weighted_f1"],
            "fall_precision": te["per_class"]["FALL"]["precision"], "fall_recall": te["per_class"]["FALL"]["recall"], "fall_f1": te["per_class"]["FALL"]["f1"],
            "normal_recall": te["per_class"]["NORMAL"]["recall"], "twisting_recall": te["per_class"]["TWISTING"]["recall"],
            "push_recall": te["per_class"]["PUSH"]["recall"], "pull_recall": te["per_class"]["PULL"]["recall"],
            "fall_to_normal": te["fall_to_normal"], "normal_to_fall": te["normal_to_fall"],
            "delta_vs_A": {
                "accuracy": te["accuracy"] - ref["accuracy"],
                "macro_f1": te["macro_f1"] - ref["macro_f1"],
                "fall_recall": te["per_class"]["FALL"]["recall"] - ref["per_class"]["FALL"]["recall"],
                "normal_recall": te["per_class"]["NORMAL"]["recall"] - ref["per_class"]["NORMAL"]["recall"],
                "twisting_recall": te["per_class"]["TWISTING"]["recall"] - ref["per_class"]["TWISTING"]["recall"],
                "push_recall": te["per_class"]["PUSH"]["recall"] - ref["per_class"]["PUSH"]["recall"],
                "pull_recall": te["per_class"]["PULL"]["recall"] - ref["per_class"]["PULL"]["recall"],
            } if exp_name != "A_reference_full_expanded" else None,
        }

    full_report = {"experiments": all_results, "comparison_vs_A": comparison,
                   "original_v5_model_unchanged": True, "original_v5_sha256": orig_sha_after}
    with open(OUT_DIR / "ablation_full_report.json", "w") as f:
        json.dump(full_report, f, indent=2, default=str)

    print("\n" + "=" * 70)
    print("SUMMARY TABLE (locked test, 401 windows)")
    print("=" * 70)
    print(f"{'Experiment':<28} {'Acc':>7} {'MacroF1':>8} {'FALL_R':>7} {'NORM_R':>7} {'TWIST_R':>7} {'PUSH_R':>7} {'PULL_R':>7} {'F->N':>5} {'N->F':>5}")
    for exp_name, c in comparison.items():
        print(f"{exp_name:<28} {c['accuracy']:>7.4f} {c['macro_f1']:>8.4f} {c['fall_recall']:>7.4f} "
              f"{c['normal_recall']:>7.4f} {c['twisting_recall']:>7.4f} {c['push_recall']:>7.4f} {c['pull_recall']:>7.4f} "
              f"{c['fall_to_normal']:>5} {c['normal_to_fall']:>5}")

    print(f"\nFull report: {OUT_DIR / 'ablation_full_report.json'}")
    return full_report


if __name__ == "__main__":
    main()
