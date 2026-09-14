#!/usr/bin/env python3
"""5-fold recording-level CV: after re-recollecting FALL data a SECOND time,
this time using a corrected protocol - 10s duration, 4-6 fall-like motions
spread across the ENTIRE recording (not one single burst near the start).

The first recollection attempt (cv_v5_fall_recollected.py) used a single
brief motion near the start of a 4s clip; per-recording burst analysis
against the raw sensor data showed those recordings had motion concentrated
in one tiny window while the rest of the clip was quiet - structurally
identical to the original 18 mislabeled recordings, just compressed into 4s.
That attempt was fully deleted and redone.

This attempt's raw recordings were spot-checked before running CV: all 16
show motion bursts spread across 8.0-9.9 seconds of the 10-second recording
(15-50 distinct bursts each), matching the burst-scatter pattern of the
original clean recordings (fall_001/003/006), which is the structural
property associated with near-100% frozen-model accuracy.

fall_018 and fall_020 are still missing on disk (same numbering-gap
limitation as before - the collection tool never backfills gaps).

Development/CV only - no locked-test-set evaluation, no final candidate
trained, no decision made here about the frozen production model.

Configuration is copied EXACTLY from train_glove_7class_xgboost_v5.py's
XGBClassifier call - identical V5_XGB_PARAMS to every other CV script in
this series.

Does not modify: the raw dataset, the feature extractor, the production V5
model, the locked test set definition, or any existing script/report file.
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
FEATURES_PATH = PROJECT_ROOT / "features" / "glove_7class_features_v6_fall_multiburst.csv"
V5_SPLIT_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_train_test_split.json"
DATASET_ROOT = PROJECT_ROOT / "dataset"

OUT_DIR = PROJECT_ROOT / "models" / "glove_7class_v5_fall_multiburst_cv"
OUT_DIR.mkdir(parents=True, exist_ok=True)

LABELS = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]
LABEL_TO_ID = {l: i for i, l in enumerate(LABELS)}
METADATA_COLUMNS = ["recording_id", "source_file", "label"]

# ============================================================================
# EXACT V5 configuration, copied verbatim from train_glove_7class_xgboost_v5.py
# (identical to every other CV script in this series). Deliberately does
# NOT include early_stopping_rounds, eval_set, or tree_method.
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
    print("STEP 1: LOCKED TEST SET IDENTIFICATION (excluded from CV, not evaluated)")
    print("=" * 70)

    v5_split = json.loads(V5_SPLIT_PATH.read_text())
    locked_test_recordings = set()
    for recs in v5_split["test_recordings"].values():
        locked_test_recordings.update(recs)
    assert len(locked_test_recordings) == 22, f"expected V5's original 22-recording split, found {len(locked_test_recordings)}"

    missing_locked = []
    for rid in sorted(locked_test_recordings):
        cls_guess = next((label.lower() for label in LABELS if rid.startswith(label.lower())), None)
        assert cls_guess is not None, f"could not infer class folder for {rid}"
        fp = DATASET_ROOT / cls_guess / f"{rid}.csv"
        if not fp.exists():
            missing_locked.append(rid)
    print(f"Locked test recordings (22 total): {sorted(locked_test_recordings)}")
    print(f"Of those, MISSING from disk (numbering gaps never backfilled, not yet re-recorded): {missing_locked}")
    assert missing_locked == ["fall_018", "fall_020"], (
        f"expected exactly fall_018/fall_020 missing, got {missing_locked}"
    )
    print("[OK] Missing set matches exactly the 2 known gap recordings - excluding all 22 IDs from CV regardless.")

    full_features = pd.read_csv(FEATURES_PATH)
    feature_cols = [c for c in full_features.columns if c not in METADATA_COLUMNS]
    assert len(feature_cols) == 51

    devset = full_features[~full_features["recording_id"].isin(locked_test_recordings)].reset_index(drop=True)

    dev_recording_ids = set(devset["recording_id"].unique())
    assert dev_recording_ids.isdisjoint(locked_test_recordings), "LEAKAGE: a locked test recording is present in the development set!"
    print(f"[OK] Development set ({len(dev_recording_ids)} recordings) is fully disjoint from the locked test set.")

    n_dev_recordings = devset["recording_id"].nunique()
    n_total_recordings = full_features["recording_id"].nunique()
    print(f"Total recordings in feature file: {n_total_recordings}")
    print(f"Development recordings: {n_dev_recordings}")

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

        assert train_recs.isdisjoint(val_recs), f"fold {fold_idx}: a recording appears in both train and validation!"
        assert train_recs.isdisjoint(locked_test_recordings), f"fold {fold_idx}: locked test recording leaked into train!"
        assert val_recs.isdisjoint(locked_test_recordings), f"fold {fold_idx}: locked test recording leaked into validation!"

        X_train, y_train = X_all.iloc[train_idx], y_all[train_idx]
        X_val, y_val = X_all.iloc[val_idx], y_all[val_idx]

        model = XGBClassifier(**V5_XGB_PARAMS)
        model.fit(X_train, y_train)
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
            "val_recordings": sorted(val_recs),
        }
        fold_results.append(fold_result)

        print(f"\nFold {fold_idx}: train_recs={len(train_recs)} val_recs={len(val_recs)} "
              f"train_win={len(train_idx)} val_win={len(val_idx)}")
        print(f"  accuracy={accuracy:.4f} macro_f1={macro_f1:.4f} weighted_f1={weighted_f1:.4f}")
        print(f"  NORMAL: P={per_class['NORMAL']['precision']:.4f} R={per_class['NORMAL']['recall']:.4f} F1={per_class['NORMAL']['f1']:.4f}")
        print(f"  FALL:   P={per_class['FALL']['precision']:.4f} R={per_class['FALL']['recall']:.4f} F1={per_class['FALL']['f1']:.4f}")
        print(f"  FALL->NORMAL={fold_result['fall_to_normal']}  NORMAL->FALL={fold_result['normal_to_fall']}")

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

    print("\nFALL->NORMAL / NORMAL->FALL per fold (the exact confusion the user reported):")
    total_fall_to_normal = sum(fr["fall_to_normal"] for fr in fold_results)
    total_normal_to_fall = sum(fr["normal_to_fall"] for fr in fold_results)
    for fr in fold_results:
        print(f"  fold {fr['fold']}: FALL->NORMAL={fr['fall_to_normal']} NORMAL->FALL={fr['normal_to_fall']}")
    print(f"  TOTAL across all folds: FALL->NORMAL={total_fall_to_normal} NORMAL->FALL={total_normal_to_fall}")

    # ================= COMPARISON CONTEXT (previous CV runs, data only) =================
    previous_20_20_cv = {
        "accuracy": {"mean": 0.7407, "std": 0.0234}, "macro_f1": {"mean": 0.7138, "std": 0.0328},
        "fall_recall": {"mean": 0.6857, "std": 0.1110},
    }
    previous_30_30_cv = {
        "accuracy": {"mean": 0.7458, "std": 0.0403}, "macro_f1": {"mean": 0.7455, "std": 0.0431},
        "fall_recall": {"mean": 0.7227, "std": 0.1486},
    }
    previous_post_cleanup_cv_20_fall_only = {
        "accuracy": {"mean": 0.7474, "std": 0.0318}, "macro_f1": {"mean": 0.7159, "std": 0.0373},
        "fall_recall": {"mean": 0.5359, "std": 0.1148},
        "total_fall_to_normal": 87, "total_normal_to_fall": 41,
        "note": "immediately after deleting 18 mislabeled FALL recordings, before recollecting - only 20 FALL recordings in dev set",
    }
    previous_single_burst_4s_cv = {
        "accuracy": {"mean": 0.7576}, "macro_f1": {"mean": 0.7406},
        "fall_recall": {"mean": 0.6100},
        "total_fall_to_normal": 97, "total_normal_to_fall": 77,
        "note": "first recollection attempt: 4s duration, single motion burst near start - burst analysis showed motion concentrated in 1-2 windows per recording, rest of clip quiet-but-labeled-FALL, same structural problem as the originally deleted data. Deleted and redone.",
    }

    # ============================ WRITE OUTPUTS ============================
    report = {
        "experiment": "v5_fall_multiburst_cv",
        "description": "5-fold recording-level StratifiedGroupKFold CV, exact V5 training config, after re-recollecting FALL data with a corrected protocol: 10s duration, 4-6 motions spread across the entire recording (matching the burst-scatter structure of the original clean recordings). Replaces the first recollection attempt, which used a single burst near the start of a 4s clip and was deleted after burst analysis showed it had the same structural flaw as the originally deleted mislabeled data.",
        "multiburst_fall_recordings": [f"fall_0{i}" for i in range(25, 41)],
        "still_missing_fall_recordings": ["fall_018", "fall_020"],
        "locked_test_recordings_all_22": sorted(locked_test_recordings),
        "locked_test_recordings_missing_pending_rerecord": missing_locked,
        "development_recordings": int(n_dev_recordings),
        "development_windows": int(len(devset)),
        "feature_count": len(feature_cols),
        "class_order": LABELS,
        "xgboost_params_v5_exact": V5_XGB_PARAMS,
        "no_early_stopping": True,
        "no_eval_set": True,
        "no_class_weights": True,
        "fold_results": fold_results,
        "summary_mean_std": summary,
        "total_fall_to_normal_across_folds": total_fall_to_normal,
        "total_normal_to_fall_across_folds": total_normal_to_fall,
        "comparison_previous_20_20_cv": previous_20_20_cv,
        "comparison_previous_30_30_cv": previous_30_30_cv,
        "comparison_previous_post_cleanup_cv_20_fall_only": previous_post_cleanup_cv_20_fall_only,
        "comparison_previous_single_burst_4s_cv": previous_single_burst_4s_cv,
        "locked_test_set_used": False,
        "final_candidate_trained": False,
    }
    with open(OUT_DIR / "v5_fall_multiburst_cv_report.json", "w") as f:
        json.dump(report, f, indent=2, default=str)

    with open(OUT_DIR / "v5_fall_multiburst_cv_report.txt", "w") as f:
        f.write("SAFEHER V5-CONFIGURATION 5-FOLD CV AFTER MULTI-BURST FALL RECOLLECTION\n")
        f.write("=" * 70 + "\n\n")
        f.write("Locked test set: EXCLUDED, NEVER EVALUATED IN THIS EXPERIMENT.\n")
        f.write(f"2 of the 22 locked-test recordings (fall_018/fall_020) are still missing (numbering gap).\n")
        f.write(f"Development: {n_dev_recordings} recordings / {len(devset)} windows.\n\n")
        f.write("XGBoost config (exact V5 script values):\n")
        f.write(json.dumps(V5_XGB_PARAMS, indent=2) + "\n\n")

        f.write("PER-FOLD RESULTS:\n")
        f.write("-" * 70 + "\n")
        for fr in fold_results:
            f.write(f"Fold {fr['fold']}: acc={fr['accuracy']:.4f} macroF1={fr['macro_f1']:.4f} "
                     f"weightedF1={fr['weighted_f1']:.4f}\n")
            f.write(f"  FALL R={fr['per_class']['FALL']['recall']:.4f}  "
                     f"FALL->NORMAL={fr['fall_to_normal']}  NORMAL->FALL={fr['normal_to_fall']}\n")

        f.write("\nMEAN +- STD ACROSS 5 FOLDS:\n")
        f.write("-" * 70 + "\n")
        for m in ["accuracy", "macro_f1", "weighted_f1"]:
            s = summary[m]
            f.write(f"{m}: {s['mean']:.4f} +- {s['std']:.4f}\n")
        for cls in LABELS:
            s = summary[f"{cls}_recall"]
            f.write(f"{cls} recall: {s['mean']:.4f} +- {s['std']:.4f}\n")

        f.write(f"\nTOTAL FALL->NORMAL across folds: {total_fall_to_normal}\n")
        f.write(f"TOTAL NORMAL->FALL across folds: {total_normal_to_fall}\n")

        f.write("\nCOMPARISON (20/20 / 30/30 / post-cleanup-20-fall / single-burst-4s / this run):\n")
        f.write(f"Accuracy:    {previous_20_20_cv['accuracy']['mean']:.4f} / {previous_30_30_cv['accuracy']['mean']:.4f} / {previous_post_cleanup_cv_20_fall_only['accuracy']['mean']:.4f} / {previous_single_burst_4s_cv['accuracy']['mean']:.4f} / {summary['accuracy']['mean']:.4f}\n")
        f.write(f"Macro F1:    {previous_20_20_cv['macro_f1']['mean']:.4f} / {previous_30_30_cv['macro_f1']['mean']:.4f} / {previous_post_cleanup_cv_20_fall_only['macro_f1']['mean']:.4f} / {previous_single_burst_4s_cv['macro_f1']['mean']:.4f} / {summary['macro_f1']['mean']:.4f}\n")
        f.write(f"FALL recall: {previous_20_20_cv['fall_recall']['mean']:.4f} / {previous_30_30_cv['fall_recall']['mean']:.4f} / {previous_post_cleanup_cv_20_fall_only['fall_recall']['mean']:.4f} / {previous_single_burst_4s_cv['fall_recall']['mean']:.4f} / {summary['FALL_recall']['mean']:.4f}\n")
        f.write(f"NORMAL->FALL: -- / -- / {previous_post_cleanup_cv_20_fall_only['total_normal_to_fall']} / {previous_single_burst_4s_cv['total_normal_to_fall']} / {total_normal_to_fall}\n")

        f.write("\nlocked_test_set_used: False\n")
        f.write("final_candidate_trained: False\n")
        f.write("NOTE: fall_018/fall_020 still need to be re-recorded (numbering gap) before\n")
        f.write("any final candidate can be evaluated on the complete locked test set.\n")

    print(f"\nReports written to {OUT_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
