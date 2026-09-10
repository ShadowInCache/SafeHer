#!/usr/bin/env python3
"""READ-ONLY analysis: TASK 3 (TWISTING error analysis), TASK 4 (NORMAL -> FALL/
TWISTING resemblance analysis), TASK 5 (new-vs-old data comparison). Uses the
CURRENT PRODUCTION V5 model and development recordings only (V5's own 22-
recording locked test set is excluded and never touched). Does not modify the
model, firmware, dataset, or feature extractor.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
import xgboost as xgb

PROJECT_ROOT = Path(__file__).resolve().parent.parent  # glove/ml
FEATURES_PATH = PROJECT_ROOT / "features" / "glove_7class_features_expanded_v2.csv"
V5_MODEL_PATH = PROJECT_ROOT / "models" / "safeher_glove_7class_v5_xgboost.json"
V5_FEATURE_COLUMNS_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_feature_columns.json"
V5_SPLIT_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_train_test_split.json"

OUT_DIR = PROJECT_ROOT / "models" / "false_fall_temporal_analysis"
OUT_DIR.mkdir(parents=True, exist_ok=True)

LABELS = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]
LABEL_TO_ID = {l: i for i, l in enumerate(LABELS)}
METADATA_COLUMNS = ["recording_id", "source_file", "label"]

KEY_FEATURES = ["acc_mag_mean", "acc_mag_max", "acc_mag_range", "acc_mag_rms", "acc_mag_std",
                 "gyro_mag_mean", "gyro_mag_max", "gyro_mag_range", "gyro_mag_rms",
                 "jerk_mean", "jerk_std", "jerk_max"]


def main():
    v5_split = json.loads(V5_SPLIT_PATH.read_text())
    locked_test_recordings = set()
    for recs in v5_split["test_recordings"].values():
        locked_test_recordings.update(recs)
    assert len(locked_test_recordings) == 22

    v5_train_recs = set()
    for recs in v5_split.get("train_recordings", {}).values():
        v5_train_recs.update(recs)
    v5_seen_recs = v5_train_recs | locked_test_recordings  # recordings V5's own training run ever touched (train OR its own test)

    full_features = pd.read_csv(FEATURES_PATH)
    feature_cols = json.loads(V5_FEATURE_COLUMNS_PATH.read_text())
    assert feature_cols == [c for c in full_features.columns if c not in METADATA_COLUMNS]

    devset = full_features[~full_features["recording_id"].isin(locked_test_recordings)].reset_index(drop=True)
    assert set(devset["recording_id"]).isdisjoint(locked_test_recordings), "LEAKAGE"
    print(f"Development set: {devset['recording_id'].nunique()} recordings, {len(devset)} windows")

    bst = xgb.Booster()
    bst.load_model(str(V5_MODEL_PATH))
    X = devset[feature_cols].astype(float).to_numpy()
    proba = bst.inplace_predict(X)
    pred_id = np.argmax(proba, axis=1)

    df = devset[METADATA_COLUMNS].copy()
    df["pred_label"] = [LABELS[i] for i in pred_id]
    for i, cls in enumerate(LABELS):
        df[f"proba_{cls}"] = proba[:, i]
    df["correct"] = df["label"] == df["pred_label"]
    df["v5_never_saw_this_recording"] = ~df["recording_id"].isin(v5_seen_recs)

    # ================= TASK 3: TWISTING ERROR ANALYSIS =================
    print("\n" + "=" * 70)
    print("TASK 3: TWISTING ERROR ANALYSIS")
    print("=" * 70)

    twisting = df[df["label"] == "TWISTING"]
    twist_rows = []
    for rid, g in twisting.groupby("recording_id"):
        n = len(g)
        pred_counts = g["pred_label"].value_counts()
        twist_rows.append({
            "recording_id": rid,
            "n_windows": n,
            "pct_TWISTING": 100.0 * pred_counts.get("TWISTING", 0) / n,
            "pct_NORMAL": 100.0 * pred_counts.get("NORMAL", 0) / n,
            "pct_FALL": 100.0 * pred_counts.get("FALL", 0) / n,
            "pct_JERK": 100.0 * pred_counts.get("JERK", 0) / n,
            "pct_other": 100.0 * (n - pred_counts.get("TWISTING", 0) - pred_counts.get("NORMAL", 0)
                                   - pred_counts.get("FALL", 0) - pred_counts.get("JERK", 0)) / n,
            "avg_TWISTING_proba": float(g["proba_TWISTING"].mean()),
            "avg_FALL_proba": float(g["proba_FALL"].mean()),
            "max_FALL_proba": float(g["proba_FALL"].max()),
            "v5_never_saw_this_recording": bool(g["v5_never_saw_this_recording"].iloc[0]),
        })
    twist_df = pd.DataFrame(twist_rows).sort_values("pct_TWISTING")

    print(f"\n{len(twist_df)} development TWISTING recordings (2 locked-test TWISTING recordings excluded)")
    print("\nWorst 10 (lowest pct_TWISTING):")
    print(twist_df.head(10).to_string(index=False))

    old_twist = twist_df[~twist_df["v5_never_saw_this_recording"]]
    new_twist = twist_df[twist_df["v5_never_saw_this_recording"]]
    print(f"\nOld (V5 saw) TWISTING: n={len(old_twist)}, mean pct_TWISTING={old_twist['pct_TWISTING'].mean():.1f}%")
    print(f"New (V5 never saw) TWISTING: n={len(new_twist)}, mean pct_TWISTING={new_twist['pct_TWISTING'].mean():.1f}%")

    # duration/intensity context, straight from raw feature stats already computed
    rec_level_feats = devset.groupby(["recording_id", "label"])[KEY_FEATURES].mean().reset_index()
    twist_df = twist_df.merge(rec_level_feats[rec_level_feats["label"] == "TWISTING"][["recording_id"] + KEY_FEATURES],
                               on="recording_id", how="left")

    # ================= TASK 4: NORMAL -> FALL/TWISTING RESEMBLANCE =================
    print("\n" + "=" * 70)
    print("TASK 4: NORMAL RECORDINGS RESEMBLING FALL/TWISTING")
    print("=" * 70)

    rec_level = devset.groupby(["recording_id", "label"])[feature_cols].mean().reset_index()
    scale_mu = rec_level[KEY_FEATURES].mean()
    scale_sigma = rec_level[KEY_FEATURES].std(ddof=1).replace(0, 1)

    def centroid(cls):
        sub = rec_level[rec_level["label"] == cls]
        return ((sub[KEY_FEATURES] - scale_mu) / scale_sigma).mean()

    normal_centroid = centroid("NORMAL")
    fall_centroid = centroid("FALL")
    twisting_centroid = centroid("TWISTING")
    # "existing difficult NORMAL" reference = the 8 recordings already flagged POSSIBLE_MISLABEL
    # in the prior data-quality audit (read here as a fixed reference list, not re-derived)
    KNOWN_DIFFICULT_NORMAL = ["normal_039", "normal_043", "normal_045", "normal_050",
                               "normal_051", "normal_057", "normal_058", "normal_059"]
    difficult_normal_rows = rec_level[(rec_level["label"] == "NORMAL") & (rec_level["recording_id"].isin(KNOWN_DIFFICULT_NORMAL))]
    if len(difficult_normal_rows):
        difficult_normal_centroid = ((difficult_normal_rows[KEY_FEATURES] - scale_mu) / scale_sigma).mean()
    else:
        difficult_normal_centroid = normal_centroid

    normal_summary = df[df["label"] == "NORMAL"].groupby("recording_id").agg(
        n_windows=("correct", "count"), pct_correct=("correct", "mean"),
    ).reset_index()
    pred_dist = df[df["label"] == "NORMAL"].groupby("recording_id")["pred_label"].value_counts(normalize=True).unstack(fill_value=0) * 100
    normal_summary = normal_summary.merge(pred_dist.add_prefix("pct_pred_"), on="recording_id", how="left")
    fall_stats = df[df["label"] == "NORMAL"].groupby("recording_id")["proba_FALL"].agg(["mean", "max"]).rename(
        columns={"mean": "avg_FALL_proba", "max": "max_FALL_proba"})
    normal_summary = normal_summary.merge(fall_stats, on="recording_id", how="left")

    proximity_rows = []
    for _, r in rec_level[rec_level["label"] == "NORMAL"].iterrows():
        std_vec = (r[KEY_FEATURES] - scale_mu) / scale_sigma
        d_normal = float(np.sqrt(((std_vec - normal_centroid) ** 2).sum()))
        d_fall = float(np.sqrt(((std_vec - fall_centroid) ** 2).sum()))
        d_twisting = float(np.sqrt(((std_vec - twisting_centroid) ** 2).sum()))
        d_difficult_normal = float(np.sqrt(((std_vec - difficult_normal_centroid) ** 2).sum()))
        nearest = min(
            [("NORMAL", d_normal), ("FALL", d_fall), ("TWISTING", d_twisting), ("DIFFICULT_NORMAL_CLUSTER", d_difficult_normal)],
            key=lambda t: t[1],
        )
        proximity_rows.append({
            "recording_id": r["recording_id"], "dist_NORMAL": d_normal, "dist_FALL": d_fall,
            "dist_TWISTING": d_twisting, "dist_DIFFICULT_NORMAL_CLUSTER": d_difficult_normal,
            "nearest_region": nearest[0],
        })
    proximity_df = pd.DataFrame(proximity_rows)
    normal_summary = normal_summary.merge(proximity_df, on="recording_id", how="left")
    normal_summary = normal_summary.merge(
        df[df["label"] == "NORMAL"][["recording_id", "v5_never_saw_this_recording"]].drop_duplicates(),
        on="recording_id", how="left"
    )

    def categorize(row):
        # A/B/C/D categorization per the task spec
        if row["nearest_region"] == "FALL":
            return "A_resembles_FALL_training"
        if row["nearest_region"] == "TWISTING":
            return "B_resembles_TWISTING_training"
        if row["nearest_region"] == "DIFFICULT_NORMAL_CLUSTER":
            return "C_resembles_existing_difficult_NORMAL"
        if row["max_FALL_proba"] > 0.5 and row["nearest_region"] == "NORMAL":
            return "D_unrepresented_region_model_still_confused"
        return "NO_ISSUE"

    normal_summary["category"] = normal_summary.apply(categorize, axis=1)
    normal_summary = normal_summary.sort_values("max_FALL_proba", ascending=False)

    print("\nTop 15 NORMAL recordings by max FALL probability, with A/B/C/D category:")
    show_cols = ["recording_id", "pct_correct", "max_FALL_proba", "nearest_region", "category", "v5_never_saw_this_recording"]
    print(normal_summary[show_cols].head(15).to_string(index=False))
    print("\nCategory counts:")
    print(normal_summary["category"].value_counts())

    # ================= TASK 5: NEW VS OLD =================
    print("\n" + "=" * 70)
    print("TASK 5: NEW VS OLD DATA - FALSE FALL/TWISTING BEHAVIOR")
    print("=" * 70)

    for cls in ["NORMAL", "TWISTING"]:
        sub = df[df["label"] == cls]
        rec_flags = sub.groupby("recording_id").agg(
            flagged=("pred_label", lambda s: (s != cls).mean() > 0.2),
            v5_never_saw=("v5_never_saw_this_recording", "first"),
        )
        old = rec_flags[~rec_flags["v5_never_saw"]]
        new = rec_flags[rec_flags["v5_never_saw"]]
        print(f"\n{cls}: OLD (V5 saw) n={len(old)} flagged={int(old['flagged'].sum())} ({100*old['flagged'].mean():.1f}%) | "
              f"NEW (V5 never saw) n={len(new)} flagged={int(new['flagged'].sum())} ({100*new['flagged'].mean():.1f}%)")

    # ============================ WRITE OUTPUTS (append to same report dir) ============================
    report_path = OUT_DIR / "temporal_analysis_report.json"
    existing = json.loads(report_path.read_text()) if report_path.exists() else {}
    existing["task3_twisting_error_analysis"] = twist_df.to_dict(orient="records")
    existing["task4_normal_fall_twisting_resemblance"] = normal_summary.drop(
        columns=[c for c in normal_summary.columns if c.startswith("pct_pred_")], errors="ignore"
    ).to_dict(orient="records")
    existing["task4_category_counts"] = normal_summary["category"].value_counts().to_dict()
    existing["task5_new_vs_old_note"] = "See printed output; NORMAL and TWISTING flag-rate comparison old vs new computed above."
    existing["known_difficult_normal_reference_list"] = KNOWN_DIFFICULT_NORMAL

    with open(report_path, "w") as f:
        json.dump(existing, f, indent=2, default=str)

    txt_path = OUT_DIR / "temporal_analysis_report.txt"
    with open(txt_path, "a") as f:
        f.write("\n\nTASK 3 - TWISTING ERROR ANALYSIS\n")
        f.write("-" * 70 + "\n")
        for _, r in twist_df.head(10).iterrows():
            f.write(f"{r['recording_id']}: pct_TWISTING={r['pct_TWISTING']:.1f}% pct_NORMAL={r['pct_NORMAL']:.1f}% "
                     f"pct_FALL={r['pct_FALL']:.1f}% max_FALL_proba={r['max_FALL_proba']:.3f} "
                     f"new={r['v5_never_saw_this_recording']}\n")

        f.write("\nTASK 4 - NORMAL RESEMBLANCE CATEGORIES\n")
        f.write("-" * 70 + "\n")
        f.write(str(normal_summary["category"].value_counts().to_dict()) + "\n")
        for _, r in normal_summary.head(15).iterrows():
            f.write(f"{r['recording_id']}: max_FALL_proba={r['max_FALL_proba']:.3f} category={r['category']} "
                     f"nearest={r['nearest_region']} new={r['v5_never_saw_this_recording']}\n")

    print(f"\nReports updated in {OUT_DIR}")


if __name__ == "__main__":
    main()
