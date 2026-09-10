#!/usr/bin/env python3
"""Recording-level 5-fold StratifiedGroupKFold CV on the PUSH/PULL-expanded (v2)
feature set. Locked test recordings are excluded entirely. Same XGBoost config
as the existing expanded baseline. Read-only investigation: no model is saved
as a production artifact, only diagnostic reports.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score, precision_recall_fscore_support
from xgboost import XGBClassifier

PROJECT_ROOT = Path(__file__).resolve().parent.parent
FEATURES_PATH = PROJECT_ROOT / "features" / "glove_7class_features_expanded_v2.csv"
EXPANDED_SPLIT_PATH = PROJECT_ROOT / "models" / "glove_7class_expanded" / "glove_7class_expanded_split.json"
OUT_DIR = PROJECT_ROOT / "models" / "glove_7class_expanded_v2"
OUT_DIR.mkdir(parents=True, exist_ok=True)

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


def main():
    split_json = json.loads(EXPANDED_SPLIT_PATH.read_text())
    test_recordings = set()
    for recs in split_json["test_recordings"].values():
        test_recordings.update(recs)
    print(f"Locked TEST recordings excluded ({len(test_recordings)}): {sorted(test_recordings)}")

    full = pd.read_csv(FEATURES_PATH)
    feature_cols = [c for c in full.columns if c not in METADATA_COLUMNS]
    assert len(feature_cols) == 51

    devset = full[~full["recording_id"].isin(test_recordings)].reset_index(drop=True)
    n_dev_recordings = devset["recording_id"].nunique()
    print(f"Devset (test excluded): {len(devset)} windows, {n_dev_recordings} recordings")
    assert set(devset["recording_id"]).isdisjoint(test_recordings), "TEST LEAKAGE DETECTED"

    X_all = devset[feature_cols].astype(float)
    y_all = devset["label"].map(LABEL_TO_ID).astype(int).to_numpy()
    groups = devset["recording_id"].to_numpy()

    sgkf = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=42)

    fold_results = []
    for fold_idx, (train_idx, val_idx) in enumerate(sgkf.split(X_all, y_all, groups), start=1):
        train_recs = set(groups[train_idx])
        val_recs = set(groups[val_idx])
        assert train_recs.isdisjoint(val_recs), f"fold {fold_idx}: recording leakage!"
        assert train_recs.isdisjoint(test_recordings) and val_recs.isdisjoint(test_recordings), f"fold {fold_idx}: TEST LEAKAGE"

        X_train, y_train = X_all.iloc[train_idx], y_all[train_idx]
        X_val, y_val = X_all.iloc[val_idx], y_all[val_idx]

        model = XGBClassifier(**XGB_PARAMS)
        model.fit(X_train, y_train, eval_set=[(X_val, y_val)], verbose=False)
        y_pred = model.predict(X_val)

        labels_range = list(range(len(LABELS)))
        cm = confusion_matrix(y_val, y_pred, labels=labels_range)
        precision, recall, f1, support = precision_recall_fscore_support(y_val, y_pred, labels=labels_range, average=None, zero_division=0)

        accuracy = accuracy_score(y_val, y_pred)
        macro_f1 = f1_score(y_val, y_pred, labels=labels_range, average="macro", zero_division=0)
        weighted_f1 = f1_score(y_val, y_pred, labels=labels_range, average="weighted", zero_division=0)

        normal_idx, fall_idx = LABEL_TO_ID["NORMAL"], LABEL_TO_ID["FALL"]
        fall_to_normal = int(cm[fall_idx, normal_idx])
        normal_to_fall = int(cm[normal_idx, fall_idx])

        per_class = {LABELS[i]: {"precision": float(precision[i]), "recall": float(recall[i]), "f1": float(f1[i]), "support": int(support[i])} for i in range(len(LABELS))}

        fold_results.append({
            "fold": fold_idx,
            "best_iteration": int(model.best_iteration),
            "best_val_mlogloss": float(model.best_score),
            "n_train_recordings": len(train_recs),
            "n_val_recordings": len(val_recs),
            "train_windows": int(len(train_idx)),
            "val_windows": int(len(val_idx)),
            "accuracy": float(accuracy),
            "macro_f1": float(macro_f1),
            "weighted_f1": float(weighted_f1),
            "fall_precision": per_class["FALL"]["precision"],
            "fall_recall": per_class["FALL"]["recall"],
            "fall_f1": per_class["FALL"]["f1"],
            "push_recall": per_class["PUSH"]["recall"],
            "push_f1": per_class["PUSH"]["f1"],
            "pull_recall": per_class["PULL"]["recall"],
            "pull_f1": per_class["PULL"]["f1"],
            "fall_to_normal": fall_to_normal,
            "normal_to_fall": normal_to_fall,
            "per_class": per_class,
            "confusion_matrix": cm.tolist(),
            "confusion_matrix_label_order": LABELS,
            "val_recordings": sorted(val_recs),
        })

        print(f"Fold {fold_idx}: train_recs={len(train_recs)} val_recs={len(val_recs)} "
              f"acc={accuracy:.4f} macroF1={macro_f1:.4f} PUSH_recall={per_class['PUSH']['recall']:.4f} "
              f"PULL_recall={per_class['PULL']['recall']:.4f} FALL_recall={per_class['FALL']['recall']:.4f} best_iter={model.best_iteration}")

    # ---- summary ----
    df_folds = pd.DataFrame(fold_results)
    summary = {}
    for m in ["accuracy", "macro_f1", "weighted_f1", "fall_precision", "fall_recall", "fall_f1",
              "push_recall", "push_f1", "pull_recall", "pull_f1"]:
        summary[m] = {"mean": float(df_folds[m].mean()), "std": float(df_folds[m].std(ddof=1)), "values": df_folds[m].round(4).tolist()}

    per_class_summary = {}
    for cls in LABELS:
        for metric in ["precision", "recall", "f1"]:
            vals = [fr["per_class"][cls][metric] for fr in fold_results]
            per_class_summary.setdefault(cls, {})[metric] = {"mean": float(np.mean(vals)), "std": float(np.std(vals, ddof=1)), "values": [round(v, 4) for v in vals]}

    report = {
        "experiment": "glove_7class_expanded_v2_pushpull_cv",
        "description": "5-fold recording-level StratifiedGroupKFold CV on PUSH/PULL-expanded (30 recordings each) dataset, test set excluded.",
        "test_recordings_excluded": sorted(test_recordings),
        "devset_recordings": int(n_dev_recordings),
        "devset_windows": int(len(devset)),
        "feature_count": len(feature_cols),
        "feature_columns": feature_cols,
        "class_order": LABELS,
        "xgboost_params": XGB_PARAMS,
        "fold_results": fold_results,
        "summary": summary,
        "per_class_summary": per_class_summary,
        "test_set_used": False,
    }

    with open(OUT_DIR / "glove_7class_expanded_v2_cv_report.json", "w") as f:
        json.dump(report, f, indent=2)

    print("\n" + "=" * 70)
    print("SUMMARY ACROSS 5 FOLDS")
    print("=" * 70)
    for m, s in summary.items():
        print(f"{m}: mean={s['mean']:.4f} std={s['std']:.4f} values={s['values']}")

    print("\nPer-class RECALL mean/std:")
    for cls in LABELS:
        s = per_class_summary[cls]["recall"]
        print(f"  {cls:10s}: mean={s['mean']:.4f} std={s['std']:.4f} values={s['values']}")

    print(f"\nReport saved: {OUT_DIR / 'glove_7class_expanded_v2_cv_report.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
