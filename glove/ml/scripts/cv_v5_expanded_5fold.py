#!/usr/bin/env python3
"""5-fold recording-level CV: does the SAME V5 training configuration benefit
from the complete 220-recording dataset? Development/CV only - the locked
V5 test set is read only to identify and exclude it; it is never fit on,
evaluated on, or used for any decision in this script.

Configuration is copied EXACTLY from train_glove_7class_xgboost_v5.py's
XGBClassifier call (read directly from that file before writing this
script - see the report for the verbatim parameters). No early stopping,
no eval_set, no tree_method override, no class weights, no thresholds -
matching that script precisely, not the separate 500-tree/early-stopping
configuration used in earlier experiments in this project.

Does not modify: the raw dataset, the feature extractor, the production V5
model, the locked test set, or any existing script/report file.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.metrics import (
    accuracy_score, confusion_matrix, f1_score,
    precision_recall_fscore_support, precision_score, recall_score,
)
from xgboost import XGBClassifier

PROJECT_ROOT = Path(__file__).resolve().parent.parent  # glove/ml
FEATURES_PATH = PROJECT_ROOT / "features" / "glove_7class_features_expanded_v2.csv"
V5_SPLIT_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_train_test_split.json"
DATASET_ROOT = PROJECT_ROOT / "dataset"

OUT_DIR = PROJECT_ROOT / "models" / "glove_7class_v5_expanded_cv"
OUT_DIR.mkdir(parents=True, exist_ok=True)

LABELS = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]
LABEL_TO_ID = {l: i for i, l in enumerate(LABELS)}
METADATA_COLUMNS = ["recording_id", "source_file", "label"]

# ============================================================================
# EXACT V5 configuration, copied verbatim from train_glove_7class_xgboost_v5.py
# lines 435-446 (read immediately before writing this script). Deliberately
# does NOT include early_stopping_rounds, eval_set, or tree_method - the
# actual V5 script does not set any of those; inventing them here would not
# be "the actual V5 training configuration."
# ============================================================================
V5_XGB_PARAMS = dict(
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


def main():
    # ================= STEP 1: IDENTIFY LOCKED TEST RECORDINGS =================
    print("=" * 70)
    print("STEP 1: LOCKED TEST SET IDENTIFICATION")
    print("=" * 70)

    v5_split = json.loads(V5_SPLIT_PATH.read_text())
    locked_test_recordings = set()
    for recs in v5_split["test_recordings"].values():
        locked_test_recordings.update(recs)

    print(f"Locked test recordings ({len(locked_test_recordings)}):")
    for rid in sorted(locked_test_recordings):
        print(f"  {rid}")
    # NOTE: V5's own original split has 22 test recordings (88 train / 22 test,
    # matching glove/docs/DEPLOYMENT_STATUS_V5.md), NOT 20. This differs from the
    # separate 20-recording "expanded" locked test set used in every other
    # experiment/audit this session (glove_7class_expanded_split.json) - the two
    # sets barely overlap. User was asked and confirmed: use V5's own 22-recording
    # split for this experiment, as originally specified.
    assert len(locked_test_recordings) == 22, f"expected 22 locked test recordings (V5's own split), found {len(locked_test_recordings)}"

    # verify all 20 exist as raw files and are unchanged (content check via
    # presence + non-empty; byte-level immutability was separately verified
    # via git diff in earlier audits and is not repeated here)
    for rid in locked_test_recordings:
        cls_guess = None
        for label in LABELS:
            if rid.startswith(label.lower()):
                cls_guess = label.lower()
                break
        assert cls_guess is not None, f"could not infer class folder for {rid}"
        fp = DATASET_ROOT / cls_guess / f"{rid}.csv"
        assert fp.exists(), f"locked test recording file missing: {fp}"
        assert fp.stat().st_size > 0, f"locked test recording file is empty: {fp}"
    print(f"\n[OK] All {len(locked_test_recordings)} locked test recordings exist on disk and are non-empty.")

    full_features = pd.read_csv(FEATURES_PATH)
    feature_cols = [c for c in full_features.columns if c not in METADATA_COLUMNS]
    assert len(feature_cols) == 51

    all_recording_ids = set(full_features["recording_id"].unique())
    assert locked_test_recordings.issubset(all_recording_ids), "some locked test recordings missing from feature file"

    devset = full_features[~full_features["recording_id"].isin(locked_test_recordings)].reset_index(drop=True)
    testset_check = full_features[full_features["recording_id"].isin(locked_test_recordings)]

    dev_recording_ids = set(devset["recording_id"].unique())
    assert dev_recording_ids.isdisjoint(locked_test_recordings), "LEAKAGE: a locked test recording is present in the development set!"
    print(f"[OK] Development set ({len(dev_recording_ids)} recordings) is fully disjoint from the locked test set.")

    n_dev_recordings = devset["recording_id"].nunique()
    assert n_dev_recordings == 198, f"expected 198 development recordings (220 - 22), got {n_dev_recordings}"
    print(f"[OK] Development set has exactly {n_dev_recordings} recordings (220 - 22 locked test).")

    # ================= STEP 2: DEVELOPMENT DATASET (in-memory only) =================
    print("\n" + "=" * 70)
    print("STEP 2: DEVELOPMENT DATASET")
    print("=" * 70)
    print(f"Development windows: {len(devset)}")
    print(devset.groupby("label")["recording_id"].nunique().reindex(LABELS))

    # ================= STEP 3/4: 5-FOLD RECORDING-LEVEL CV, V5 CONFIG =================
    print("\n" + "=" * 70)
    print("STEP 3/4: 5-FOLD STRATIFIEDGROUPKFOLD CV, EXACT V5 TRAINING CONFIG")
    print("=" * 70)
    print("XGBoost params (verbatim from train_glove_7class_xgboost_v5.py):")
    print(json.dumps(V5_XGB_PARAMS, indent=2))
    print("No early_stopping_rounds, no eval_set, no tree_method override - matches the script exactly.")

    X_all = devset[feature_cols].astype(float)
    y_all = devset["label"].map(LABEL_TO_ID).astype(int).to_numpy()
    groups = devset["recording_id"].to_numpy()

    sgkf = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=42)

    fold_results = []
    for fold_idx, (train_idx, val_idx) in enumerate(sgkf.split(X_all, y_all, groups), start=1):
        train_recs = set(groups[train_idx])
        val_recs = set(groups[val_idx])

        # CRITICAL programmatic leakage assertions
        assert train_recs.isdisjoint(val_recs), f"fold {fold_idx}: a recording appears in both train and validation!"
        assert train_recs.isdisjoint(locked_test_recordings), f"fold {fold_idx}: locked test recording leaked into train!"
        assert val_recs.isdisjoint(locked_test_recordings), f"fold {fold_idx}: locked test recording leaked into validation!"

        X_train, y_train = X_all.iloc[train_idx], y_all[train_idx]
        X_val, y_val = X_all.iloc[val_idx], y_all[val_idx]

        model = XGBClassifier(**V5_XGB_PARAMS)
        model.fit(X_train, y_train)  # exactly as in the V5 script: no eval_set, no early stopping
        y_pred = model.predict(X_val)

        labels_range = list(range(len(LABELS)))
        cm = confusion_matrix(y_val, y_pred, labels=labels_range)
        precision, recall, f1, support = precision_recall_fscore_support(y_val, y_pred, labels=labels_range, average=None, zero_division=0)

        accuracy = accuracy_score(y_val, y_pred)
        macro_precision = precision_score(y_val, y_pred, labels=labels_range, average="macro", zero_division=0)
        macro_recall = recall_score(y_val, y_pred, labels=labels_range, average="macro", zero_division=0)
        macro_f1 = f1_score(y_val, y_pred, labels=labels_range, average="macro", zero_division=0)
        weighted_f1 = f1_score(y_val, y_pred, labels=labels_range, average="weighted", zero_division=0)

        idx = LABEL_TO_ID
        def cm_count(a, b):
            return int(cm[idx[a], idx[b]])

        per_class = {LABELS[i]: {"precision": float(precision[i]), "recall": float(recall[i]),
                                  "f1": float(f1[i]), "support": int(support[i])} for i in range(len(LABELS))}

        fold_result = {
            "fold": fold_idx,
            "n_train_recordings": len(train_recs),
            "n_val_recordings": len(val_recs),
            "train_windows": int(len(train_idx)),
            "val_windows": int(len(val_idx)),
            "accuracy": float(accuracy),
            "macro_precision": float(macro_precision),
            "macro_recall": float(macro_recall),
            "macro_f1": float(macro_f1),
            "weighted_f1": float(weighted_f1),
            "per_class": per_class,
            "confusion_matrix": cm.tolist(),
            "confusion_matrix_label_order": LABELS,
            "fall_to_normal": cm_count("FALL", "NORMAL"),
            "normal_to_fall": cm_count("NORMAL", "FALL"),
            "push_to_pull": cm_count("PUSH", "PULL"),
            "pull_to_push": cm_count("PULL", "PUSH"),
            "push_to_jerk": cm_count("PUSH", "JERK"),
            "pull_to_jerk": cm_count("PULL", "JERK"),
            "val_recordings": sorted(val_recs),
        }
        fold_results.append(fold_result)

        print(f"\nFold {fold_idx}: train_recs={len(train_recs)} val_recs={len(val_recs)} "
              f"train_win={len(train_idx)} val_win={len(val_idx)}")
        print(f"  accuracy={accuracy:.4f} macro_f1={macro_f1:.4f} weighted_f1={weighted_f1:.4f}")
        print(f"  PUSH: P={per_class['PUSH']['precision']:.4f} R={per_class['PUSH']['recall']:.4f} F1={per_class['PUSH']['f1']:.4f}")
        print(f"  PULL: P={per_class['PULL']['precision']:.4f} R={per_class['PULL']['recall']:.4f} F1={per_class['PULL']['f1']:.4f}")
        print(f"  FALL: P={per_class['FALL']['precision']:.4f} R={per_class['FALL']['recall']:.4f} F1={per_class['FALL']['f1']:.4f}")

    # ================= STEP 6: MEAN +- STD =================
    print("\n" + "=" * 70)
    print("STEP 6: MEAN +- STD ACROSS 5 FOLDS")
    print("=" * 70)

    df_folds = pd.DataFrame(fold_results)
    summary = {}
    for m in ["accuracy", "macro_precision", "macro_recall", "macro_f1", "weighted_f1"]:
        vals = df_folds[m]
        summary[m] = {"mean": float(vals.mean()), "std": float(vals.std(ddof=1)), "values": vals.round(4).tolist()}
        print(f"{m}: {summary[m]['mean']:.4f} +- {summary[m]['std']:.4f}  {summary[m]['values']}")

    for cls in LABELS:
        for metric in ["precision", "recall", "f1"]:
            vals = [fr["per_class"][cls][metric] for fr in fold_results]
            key = f"{cls}_{metric}"
            summary[key] = {"mean": float(np.mean(vals)), "std": float(np.std(vals, ddof=1)), "values": [round(v, 4) for v in vals]}

    print("\nPer-class RECALL mean +- std:")
    for cls in LABELS:
        s = summary[f"{cls}_recall"]
        print(f"  {cls:10s}: {s['mean']:.4f} +- {s['std']:.4f}  {s['values']}")

    print("\nFALL->NORMAL / NORMAL->FALL / PUSH<->PULL / PUSH,PULL->JERK per fold:")
    for fr in fold_results:
        print(f"  fold {fr['fold']}: FALL->NORMAL={fr['fall_to_normal']} NORMAL->FALL={fr['normal_to_fall']} "
              f"PUSH->PULL={fr['push_to_pull']} PULL->PUSH={fr['pull_to_push']} "
              f"PUSH->JERK={fr['push_to_jerk']} PULL->JERK={fr['pull_to_jerk']}")

    # ================= STEP 7/8: COMPARISON CONTEXT (data only, no file changes) ============
    previous_20_20_cv = {
        "accuracy": {"mean": 0.7407, "std": 0.0234}, "macro_f1": {"mean": 0.7138, "std": 0.0328},
        "weighted_f1": {"mean": 0.7321, "std": 0.0260}, "fall_recall": {"mean": 0.6857, "std": 0.1110},
        "fall_f1": {"mean": 0.6769, "std": 0.0530}, "push_recall": {"mean": 0.5665, "std": 0.1510},
        "pull_recall": {"mean": 0.4524, "std": 0.2287},
    }
    previous_30_30_cv = {
        "accuracy": {"mean": 0.7458, "std": 0.0403}, "macro_f1": {"mean": 0.7455, "std": 0.0431},
        "weighted_f1": {"mean": 0.7440, "std": 0.0415}, "fall_recall": {"mean": 0.7227, "std": 0.1486},
        "push_recall": {"mean": 0.6290, "std": 0.0994}, "pull_recall": {"mean": 0.6080, "std": 0.0582},
    }
    historical_v5_documented = {
        "source": "glove/docs/DEPLOYMENT_STATUS_V5.md",
        "test_set": "V5's OWN original 22-recording/401-window test set (NOT the same test set as the 20-recording locked set used elsewhere in this project) - NOT directly comparable to this CV's numbers, reported for context only",
        "accuracy": 0.8554,
        "fall_recall": 0.7385,
        "false_fall_rate_normal_to_fall": 0.1081,
        "per_class": {
            "NORMAL": {"precision": 0.924, "recall": 0.885, "f1": 0.904, "support": 148},
            "JERK": {"precision": 0.667, "recall": 0.333, "f1": 0.444, "support": 6},
            "PUSH": {"precision": 0.500, "recall": 0.500, "f1": 0.500, "support": 4},
            "PULL": {"precision": 0.500, "recall": 0.500, "f1": 0.500, "support": 4},
            "SHAKING": {"precision": 1.000, "recall": 1.000, "f1": 1.000, "support": 4},
            "TWISTING": {"precision": 0.500, "recall": 1.000, "f1": 0.667, "support": 2},
            "FALL": {"precision": 0.793, "recall": 0.738, "f1": 0.765, "support": 65},
        },
        "caveat": "PUSH/PULL/JERK/SHAKING/TWISTING supports are 2-6 windows each - far too small to be statistically meaningful; NORMAL/FALL supports (148/65) are more reliable.",
    }

    # ================= STEP 9: FOLD STABILITY ANALYSIS =================
    print("\n" + "=" * 70)
    print("STEP 9: FOLD STABILITY / DOMINANT-FOLD CHECK")
    print("=" * 70)
    for cls in LABELS:
        vals = summary[f"{cls}_recall"]["values"]
        spread = max(vals) - min(vals)
        print(f"  {cls:10s}: recall range {min(vals):.4f}-{max(vals):.4f} (spread={spread:.4f}), values={vals}")

    # ============================ WRITE OUTPUTS ============================
    report = {
        "experiment": "v5_expanded_5fold_cv",
        "description": "5-fold recording-level StratifiedGroupKFold CV using the EXACT V5 training configuration (read from train_glove_7class_xgboost_v5.py) on the complete 220-recording dataset, locked test set excluded and never touched.",
        "locked_test_set_note": "Uses V5's OWN original 22-recording test split (glove_7class_v5_train_test_split.json / 88-train-22-test, matching DEPLOYMENT_STATUS_V5.md), per explicit user confirmation - NOT the separate 20-recording 'expanded' locked test set used in other experiments this session. The two sets barely overlap; see report text for the full recording-id lists of both.",
        "locked_test_recordings": sorted(locked_test_recordings),
        "development_recordings": int(n_dev_recordings),
        "development_windows": int(len(devset)),
        "feature_count": len(feature_cols),
        "feature_columns": feature_cols,
        "class_order": LABELS,
        "xgboost_params_v5_exact": V5_XGB_PARAMS,
        "no_early_stopping": True,
        "no_eval_set": True,
        "no_class_weights": True,
        "no_thresholds_applied": True,
        "fold_results": fold_results,
        "summary_mean_std": summary,
        "comparison_previous_20_20_cv": previous_20_20_cv,
        "comparison_previous_30_30_cv": previous_30_30_cv,
        "comparison_historical_v5_documented": historical_v5_documented,
        "locked_test_set_used": False,
        "final_candidate_trained": False,
    }
    with open(OUT_DIR / "v5_expanded_5fold_cv_report.json", "w") as f:
        json.dump(report, f, indent=2, default=str)

    confusion_matrices = {
        f"fold_{fr['fold']}": {
            "confusion_matrix": fr["confusion_matrix"],
            "label_order": fr["confusion_matrix_label_order"],
        } for fr in fold_results
    }
    with open(OUT_DIR / "v5_expanded_5fold_confusion_matrices.json", "w") as f:
        json.dump(confusion_matrices, f, indent=2)

    with open(OUT_DIR / "v5_expanded_5fold_cv_report.txt", "w") as f:
        f.write("SAFEHER V5-CONFIGURATION 5-FOLD CV ON COMPLETE 220-RECORDING DATASET\n")
        f.write("=" * 70 + "\n\n")
        f.write("Locked test set: EXCLUDED, NEVER EVALUATED IN THIS EXPERIMENT.\n")
        f.write(f"Development: {n_dev_recordings} recordings / {len(devset)} windows.\n\n")
        f.write("XGBoost config (exact V5 script values):\n")
        f.write(json.dumps(V5_XGB_PARAMS, indent=2) + "\n\n")

        f.write("PER-FOLD RESULTS:\n")
        f.write("-" * 70 + "\n")
        for fr in fold_results:
            f.write(f"Fold {fr['fold']}: acc={fr['accuracy']:.4f} macroF1={fr['macro_f1']:.4f} "
                     f"weightedF1={fr['weighted_f1']:.4f}\n")
            f.write(f"  PUSH R={fr['per_class']['PUSH']['recall']:.4f} "
                     f"PULL R={fr['per_class']['PULL']['recall']:.4f} "
                     f"FALL R={fr['per_class']['FALL']['recall']:.4f}\n")

        f.write("\nMEAN +- STD ACROSS 5 FOLDS:\n")
        f.write("-" * 70 + "\n")
        for m in ["accuracy", "macro_f1", "weighted_f1"]:
            s = summary[m]
            f.write(f"{m}: {s['mean']:.4f} +- {s['std']:.4f}\n")
        for cls in LABELS:
            s = summary[f"{cls}_recall"]
            f.write(f"{cls} recall: {s['mean']:.4f} +- {s['std']:.4f}\n")

        f.write("\nCOMPARISON (previous 20/20 CV / previous 30/30 CV / this run):\n")
        f.write(f"Accuracy:  {previous_20_20_cv['accuracy']['mean']:.4f} / {previous_30_30_cv['accuracy']['mean']:.4f} / {summary['accuracy']['mean']:.4f}\n")
        f.write(f"Macro F1:  {previous_20_20_cv['macro_f1']['mean']:.4f} / {previous_30_30_cv['macro_f1']['mean']:.4f} / {summary['macro_f1']['mean']:.4f}\n")
        f.write(f"FALL recall: {previous_20_20_cv['fall_recall']['mean']:.4f} / {previous_30_30_cv['fall_recall']['mean']:.4f} / {summary['FALL_recall']['mean']:.4f}\n")
        f.write(f"PUSH recall: {previous_20_20_cv['push_recall']['mean']:.4f} / {previous_30_30_cv['push_recall']['mean']:.4f} / {summary['PUSH_recall']['mean']:.4f}\n")
        f.write(f"PULL recall: {previous_20_20_cv['pull_recall']['mean']:.4f} / {previous_30_30_cv['pull_recall']['mean']:.4f} / {summary['PULL_recall']['mean']:.4f}\n")

        f.write("\nHistorical documented V5 result (DIFFERENT test set, NOT directly comparable):\n")
        f.write(f"  {historical_v5_documented['accuracy']*100:.2f}% accuracy on its own 401-window test set (source: {historical_v5_documented['source']})\n")

        f.write("\nlocked_test_set_used: False\n")
        f.write("final_candidate_trained: False\n")

    print(f"\nReports written to {OUT_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
