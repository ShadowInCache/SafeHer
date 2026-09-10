#!/usr/bin/env python3
"""READ-ONLY investigation of the SAFEHER false-FALL/TWISTING problem.

Does not modify, delete, or replace any raw dataset file. Does not modify the
feature extractor, the production V5 model, or the locked test set. Produces
only new report files under ml/models/dataset_quality_audit/.

Steps implemented (see PR description / task spec for full detail):
  1. Raw file quality check (schema, NaN/Inf, timestamps, duplicates, saturation)
  2. Statistical outlier detection within each class (existing 51 features, unmodified)
  3. Current production V5 model error analysis on all current recordings
  4. Ranked "suspicious NORMAL recordings" report
  5. Per-recording classification (CONFIRMED_BAD_DATA / POSSIBLE_BAD_DATA / ...)
  6. Separate validation of the new PUSH/PULL recordings
"""

from __future__ import annotations

import glob
import hashlib
import json
import os
from pathlib import Path

import numpy as np
import pandas as pd
import xgboost as xgb

PROJECT_ROOT = Path(__file__).resolve().parent.parent  # glove/ml
DATASET_ROOT = PROJECT_ROOT / "dataset"
FEATURES_PATH = PROJECT_ROOT / "features" / "glove_7class_features_expanded_v2.csv"
V5_MODEL_PATH = PROJECT_ROOT / "models" / "safeher_glove_7class_v5_xgboost.json"
V5_FEATURE_COLUMNS_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_feature_columns.json"
V5_LABEL_MAPPING_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_label_mapping.json"
V5_SPLIT_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_train_test_split.json"

OUT_DIR = PROJECT_ROOT / "models" / "dataset_quality_audit"
OUT_DIR.mkdir(parents=True, exist_ok=True)

LABELS = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]
LABEL_TO_ID = {l: i for i, l in enumerate(LABELS)}
REQUIRED_COLS = ["timestamp_ms", "Ax", "Ay", "Az", "Gx", "Gy", "Gz", "label"]
SENSOR_COLS = ["Ax", "Ay", "Az", "Gx", "Gy", "Gz"]
METADATA_COLUMNS = ["recording_id", "source_file", "label"]

INT16_MIN, INT16_MAX = -32768, 32767
SATURATION_MARGIN = 50  # within this many counts of either int16 endpoint = "saturated"


def sha256_of_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ============================================================================
# STEP 1: RAW FILE QUALITY CHECK
# ============================================================================

def list_all_recordings():
    files = []
    for label in LABELS:
        folder = DATASET_ROOT / label.lower()
        for fp in sorted(glob.glob(str(folder / "*.csv"))):
            files.append((label, Path(fp)))
    return files


def step1_raw_quality_check():
    rows = []
    content_hashes = {}  # hash -> list of recording_ids (for duplicate detection)

    for label, fp in list_all_recordings():
        rid = fp.stem
        entry = {
            "recording_id": rid, "class": label, "duration_s": None,
            "sample_count": None, "sampling_rate_hz": None,
            "quality_status": "OK", "problems_found": [],
        }
        problems = []

        size = fp.stat().st_size
        if size == 0:
            problems.append("EMPTY_FILE")
            entry["quality_status"] = "FAIL"
            entry["problems_found"] = problems
            rows.append(entry)
            continue

        try:
            df = pd.read_csv(fp)
        except Exception as exc:
            problems.append(f"UNREADABLE_CSV: {exc}")
            entry["quality_status"] = "FAIL"
            entry["problems_found"] = problems
            rows.append(entry)
            continue

        missing_cols = [c for c in REQUIRED_COLS if c not in df.columns]
        if missing_cols:
            problems.append(f"MISSING_COLUMNS: {missing_cols}")
            entry["quality_status"] = "FAIL"
            entry["problems_found"] = problems
            rows.append(entry)
            continue

        entry["sample_count"] = len(df)

        # non-numeric sensor values
        num_df = df[SENSOR_COLS].apply(pd.to_numeric, errors="coerce")
        nonnumeric = int((num_df.isna() & df[SENSOR_COLS].notna()).sum().sum())
        if nonnumeric:
            problems.append(f"NON_NUMERIC_VALUES:{nonnumeric}")

        nan_count = int(num_df.isna().sum().sum())
        if nan_count:
            problems.append(f"NAN_VALUES:{nan_count}")

        inf_count = int(np.isinf(num_df.to_numpy(dtype=float, na_value=0)).sum())
        if inf_count:
            problems.append(f"INF_VALUES:{inf_count}")

        # timestamp checks
        ts = pd.to_numeric(df["timestamp_ms"], errors="coerce")
        diffs = ts.diff().dropna()
        non_increasing = int((diffs <= 0).sum())
        if non_increasing:
            problems.append(f"NON_INCREASING_OR_DUPLICATE_TIMESTAMPS:{non_increasing}")

        pos_diffs = diffs[diffs > 0]
        if len(pos_diffs):
            median_dt = float(pos_diffs.median())
            hz = 1000.0 / median_dt if median_dt > 0 else None
            entry["sampling_rate_hz"] = hz
            if hz is not None and not (85 <= hz <= 115):
                problems.append(f"ABNORMAL_SAMPLING_RATE:{hz:.1f}Hz")
            abnormal_gaps = int((pos_diffs > 3 * median_dt).sum())
            if abnormal_gaps:
                problems.append(f"ABNORMAL_SAMPLING_INTERVALS:{abnormal_gaps}")

        if len(ts) > 1:
            duration_s = float(ts.iloc[-1] - ts.iloc[0]) / 1000.0
            entry["duration_s"] = duration_s
            if duration_s < 3.0:
                problems.append(f"ABNORMALLY_SHORT_DURATION:{duration_s:.2f}s")
            if duration_s > 25.0:
                problems.append(f"ABNORMALLY_LONG_DURATION:{duration_s:.2f}s")

        # truncated recording: fewer than 100 samples (can't form even one window)
        if entry["sample_count"] is not None and entry["sample_count"] < 100:
            problems.append(f"TRUNCATED_TOO_SHORT_FOR_WINDOW:{entry['sample_count']}samples")

        # Sensor saturation: exact int16 endpoint (matches firmware's own SENSOR_BAD
        # diagnostic). IMPORTANT: calibrated against the whole dataset before setting
        # any threshold (see investigation) - SHAKING/TWISTING recordings routinely
        # hit the +-250deg/s gyro rail for up to ~1s continuously during genuinely
        # vigorous motion (max observed consecutive run: 100 samples in twisting_014,
        # 41.6% of all samples in shaking_008) - that is expected physics for those
        # classes on this hardware's gyro full-scale range, not corruption. So this is
        # recorded as a CONTINUOUS metric here (not a binary pass/fail), and only
        # becomes a "problem" flag for classes where sustained saturation is NOT
        # physically expected (NORMAL/JERK/PUSH/PULL) - see is_calm_class below.
        exact_endpoint_count = 0
        max_consecutive_run = 0
        for c in SENSOR_COLS:
            vals = num_df[c].dropna()
            hits = (vals == INT16_MIN) | (vals == INT16_MAX)
            exact_endpoint_count += int(hits.sum())
            if hits.any():
                run = hits.astype(int).groupby((~hits).cumsum()).cumsum()
                max_consecutive_run = max(max_consecutive_run, int(run.max()))
        entry["saturation_sample_count"] = exact_endpoint_count
        entry["saturation_pct_of_samples"] = 100.0 * exact_endpoint_count / (entry["sample_count"] * 6) if entry["sample_count"] else 0.0
        entry["saturation_max_consecutive_run"] = max_consecutive_run

        is_calm_class = label in ("NORMAL", "JERK", "PUSH", "PULL")
        # Even for calm classes, a handful of isolated hits during a brief real peak
        # is not unusual (confirmed: 25th percentile across the whole dataset is
        # already 35 hits). Flag only sustained saturation: a long consecutive run
        # (>=30 samples = >=300ms continuously pegged) is the meaningful signal of an
        # atypically vigorous, possibly mislabeled-feeling movement inside a
        # supposedly calm recording - not the raw hit count.
        if is_calm_class and max_consecutive_run >= 30:
            problems.append(f"SUSTAINED_SATURATION_IN_CALM_CLASS:{max_consecutive_run}consecutive_samples")

        # suspiciously constant sensor values (near-zero variance across the whole recording)
        const_cols = []
        for c in SENSOR_COLS:
            vals = num_df[c].dropna()
            if len(vals) > 10 and vals.std() < 1.0:
                const_cols.append(c)
        if const_cols:
            problems.append(f"SUSPICIOUSLY_CONSTANT_SENSOR_VALUES:{const_cols}")

        # label mismatch
        file_labels = df["label"].astype(str).str.strip().str.upper().unique().tolist()
        if file_labels != [label]:
            problems.append(f"LABEL_MISMATCH:file_contains={file_labels}_expected={label}")

        # content hash for duplicate detection (sensor columns only, rounded)
        try:
            content_hash = int(pd.util.hash_pandas_object(num_df.round(3)).sum())
            content_hashes.setdefault(content_hash, []).append(rid)
        except Exception:
            pass

        entry["problems_found"] = problems
        entry["quality_status"] = "WARN" if problems else "OK"
        rows.append(entry)

    # duplicate detection pass
    duplicate_groups = {h: recs for h, recs in content_hashes.items() if len(recs) > 1}
    dup_rids = set()
    for recs in duplicate_groups.values():
        dup_rids.update(recs)
    for row in rows:
        if row["recording_id"] in dup_rids:
            row["problems_found"].append("EXACT_DUPLICATE_CONTENT")
            row["quality_status"] = "WARN" if row["quality_status"] == "OK" else row["quality_status"]

    return pd.DataFrame(rows), duplicate_groups


# ============================================================================
# STEP 2: STATISTICAL OUTLIER DETECTION (existing 51 features, unmodified)
# ============================================================================

def step2_statistical_outliers(full_features: pd.DataFrame):
    feature_cols = [c for c in full_features.columns if c not in METADATA_COLUMNS]

    # recording-level representative stats: mean of each window feature across the recording
    rec_level = full_features.groupby(["recording_id", "label"])[feature_cols].mean().reset_index()

    KEY_FEATURES = ["acc_mag_mean", "acc_mag_max", "acc_mag_range", "acc_mag_rms", "acc_mag_std",
                     "gyro_mag_mean", "gyro_mag_max", "gyro_mag_range", "gyro_mag_rms",
                     "jerk_mean", "jerk_std", "jerk_max"]

    outlier_rows = []
    for cls in LABELS:
        sub = rec_level[rec_level["label"] == cls]
        if len(sub) < 3:
            continue
        for f in KEY_FEATURES:
            mu, sigma = sub[f].mean(), sub[f].std(ddof=1)
            if sigma == 0 or np.isnan(sigma):
                continue
            z = (sub[f] - mu) / sigma
            for rid, zval in zip(sub["recording_id"], z):
                if abs(zval) >= 2.5:
                    outlier_rows.append({"recording_id": rid, "class": cls, "feature": f,
                                          "z_score": float(zval), "value": float(sub[sub["recording_id"] == rid][f].iloc[0]),
                                          "class_mean": float(mu), "class_std": float(sigma)})

    outliers_df = pd.DataFrame(outlier_rows)

    # NORMAL recordings' feature-space distance to FALL / TWISTING class centroids,
    # compared to distance to NORMAL's own centroid (in standardized key-feature space)
    normal_rec = rec_level[rec_level["label"] == "NORMAL"].copy()
    fall_rec = rec_level[rec_level["label"] == "FALL"]
    twisting_rec = rec_level[rec_level["label"] == "TWISTING"]

    # standardize using NORMAL's own scale (avoid leaking test-set info; purely descriptive)
    scale_mu = rec_level[KEY_FEATURES].mean()
    scale_sigma = rec_level[KEY_FEATURES].std(ddof=1).replace(0, 1)

    def centroid(df):
        return ((df[KEY_FEATURES] - scale_mu) / scale_sigma).mean()

    normal_centroid = centroid(normal_rec)
    fall_centroid = centroid(fall_rec)
    twisting_centroid = centroid(twisting_rec)

    def dist_to(df_row_std, centroid):
        return float(np.sqrt(((df_row_std - centroid) ** 2).sum()))

    proximity_rows = []
    for _, r in normal_rec.iterrows():
        std_vec = (r[KEY_FEATURES] - scale_mu) / scale_sigma
        d_normal = dist_to(std_vec, normal_centroid)
        d_fall = dist_to(std_vec, fall_centroid)
        d_twisting = dist_to(std_vec, twisting_centroid)
        proximity_rows.append({
            "recording_id": r["recording_id"],
            "dist_to_NORMAL_centroid": d_normal,
            "dist_to_FALL_centroid": d_fall,
            "dist_to_TWISTING_centroid": d_twisting,
            "closer_to_FALL_than_NORMAL": d_fall < d_normal,
            "closer_to_TWISTING_than_NORMAL": d_twisting < d_normal,
        })
    proximity_df = pd.DataFrame(proximity_rows)

    return outliers_df, proximity_df, rec_level


# ============================================================================
# STEP 3: CURRENT V5 MODEL ERROR ANALYSIS
# ============================================================================

def step3_model_error_analysis(full_features: pd.DataFrame):
    feature_cols_v5 = json.loads(V5_FEATURE_COLUMNS_PATH.read_text())
    assert feature_cols_v5 == [c for c in full_features.columns if c not in METADATA_COLUMNS], \
        "feature order mismatch between V5's recorded feature columns and the expanded_v2 feature file"

    bst = xgb.Booster()
    bst.load_model(str(V5_MODEL_PATH))

    X = full_features[feature_cols_v5].astype(float).to_numpy()
    proba = bst.inplace_predict(X)  # (n, 7) softprob
    pred_id = np.argmax(proba, axis=1)

    df = full_features[METADATA_COLUMNS].copy()
    df["pred_label"] = [LABELS[i] for i in pred_id]
    df["pred_confidence"] = proba[np.arange(len(proba)), pred_id]
    for i, cls in enumerate(LABELS):
        df[f"proba_{cls}"] = proba[:, i]
    df["correct"] = df["label"] == df["pred_label"]

    # which recordings were in V5's OWN original train/test split (i.e. it actually trained on them)
    v5_split = json.loads(V5_SPLIT_PATH.read_text())
    v5_train_recs = set()
    for recs in v5_split.get("train_recordings", {}).values():
        v5_train_recs.update(recs)
    v5_test_recs = set()
    for recs in v5_split.get("test_recordings", {}).values():
        v5_test_recs.update(recs)
    df["v5_saw_in_training"] = df["recording_id"].isin(v5_train_recs)
    df["v5_saw_in_its_own_test"] = df["recording_id"].isin(v5_test_recs)
    df["v5_never_saw_this_recording"] = ~df["recording_id"].isin(v5_train_recs | v5_test_recs)

    # per-recording summary
    rec_rows = []
    for rid, g in df.groupby("recording_id"):
        true_label = g["label"].iloc[0]
        n = len(g)
        pred_counts = g["pred_label"].value_counts().to_dict()
        pct_fall = 100.0 * pred_counts.get("FALL", 0) / n
        pct_twisting = 100.0 * pred_counts.get("TWISTING", 0) / n
        rec_rows.append({
            "recording_id": rid,
            "true_label": true_label,
            "n_windows": n,
            "pred_distribution": pred_counts,
            "pct_predicted_FALL": pct_fall,
            "pct_predicted_TWISTING": pct_twisting,
            "pct_correct": 100.0 * g["correct"].sum() / n,
            "avg_FALL_proba": float(g["proba_FALL"].mean()),
            "max_FALL_proba": float(g["proba_FALL"].max()),
            "avg_TWISTING_proba": float(g["proba_TWISTING"].mean()),
            "max_TWISTING_proba": float(g["proba_TWISTING"].max()),
            "v5_saw_in_training": bool(g["v5_saw_in_training"].iloc[0]),
            "v5_saw_in_its_own_test": bool(g["v5_saw_in_its_own_test"].iloc[0]),
            "v5_never_saw_this_recording": bool(g["v5_never_saw_this_recording"].iloc[0]),
        })
    rec_summary = pd.DataFrame(rec_rows)

    return df, rec_summary


def main():
    print("STEP 1: raw file quality check")
    quality_df, duplicate_groups = step1_raw_quality_check()
    print(f"  {len(quality_df)} recordings scanned. Status counts:\n{quality_df['quality_status'].value_counts()}")

    print("\nSTEP 2/3: loading feature data + running production V5 model")
    full_features = pd.read_csv(FEATURES_PATH)
    outliers_df, proximity_df, rec_level = step2_statistical_outliers(full_features)
    window_preds, rec_summary = step3_model_error_analysis(full_features)

    # merge everything onto rec_summary for the ranked suspicious-NORMAL report
    normal_summary = rec_summary[rec_summary["true_label"] == "NORMAL"].copy()
    normal_summary = normal_summary.merge(proximity_df, on="recording_id", how="left")

    outlier_by_rec = outliers_df.groupby("recording_id").apply(
        lambda g: "; ".join(f"{r.feature}(z={r.z_score:.2f})" for r in g.itertuples())
    ).rename("statistical_outlier_features") if len(outliers_df) else pd.Series(dtype=object, name="statistical_outlier_features")
    normal_summary = normal_summary.merge(outlier_by_rec, on="recording_id", how="left")

    quality_by_rec = quality_df.set_index("recording_id")["problems_found"].apply(
        lambda p: "; ".join(p) if isinstance(p, list) and p else ""
    ).rename("raw_quality_problems")
    normal_summary = normal_summary.merge(quality_by_rec, on="recording_id", how="left")

    saturation_by_rec = quality_df.set_index("recording_id")[
        ["saturation_pct_of_samples", "saturation_max_consecutive_run"]
    ]
    normal_summary = normal_summary.merge(saturation_by_rec, on="recording_id", how="left")

    # suspicion score: weighted combination for ranking only (not a verdict)
    normal_summary["suspicion_score"] = (
        normal_summary["pct_predicted_FALL"] * 1.0
        + normal_summary["pct_predicted_TWISTING"] * 0.6
        + normal_summary["max_FALL_proba"] * 40
        + normal_summary["max_TWISTING_proba"] * 20
        + normal_summary["saturation_max_consecutive_run"].fillna(0) * 0.3
    )
    normal_summary = normal_summary.sort_values("suspicion_score", ascending=False)

    # ---- STEP 5 classification (rule-based, evidence-driven, not automatic "bad" verdict) ----
    def classify(row):
        # Reserved for objective, unambiguous FILE/SENSOR-integrity defects only -
        # things that cannot be explained by "this was a genuinely vigorous
        # movement." Sustained saturation is deliberately NOT in this list: the
        # sensor is behaving exactly as configured (just exceeding its +-250deg/s
        # range), which is physically consistent with real fast motion, not a
        # broken sensor or a corrupted file - see the writeup for why this
        # distinction matters here.
        has_hard_quality_problem = any(
            tag in (row["raw_quality_problems"] or "")
            for tag in ["NAN_VALUES", "INF_VALUES", "NON_NUMERIC", "EMPTY_FILE", "UNREADABLE_CSV",
                        "LABEL_MISMATCH", "EXACT_DUPLICATE_CONTENT",
                        "SUSPICIOUSLY_CONSTANT", "NON_INCREASING", "TRUNCATED"]
        )
        has_soft_quality_problem = any(
            tag in (row["raw_quality_problems"] or "")
            for tag in ["ABNORMAL_SAMPLING", "ABNORMALLY_SHORT", "ABNORMALLY_LONG"]
        )
        has_sustained_saturation = "SUSTAINED_SATURATION_IN_CALM_CLASS" in (row["raw_quality_problems"] or "")
        model_flags_it = row["pct_predicted_FALL"] > 20 or row["pct_predicted_TWISTING"] > 20 or row["max_FALL_proba"] > 0.5
        stat_outlier = isinstance(row.get("statistical_outlier_features"), str) and row.get("statistical_outlier_features")
        far_from_normal = row.get("closer_to_FALL_than_NORMAL") or row.get("closer_to_TWISTING_than_NORMAL")

        if has_hard_quality_problem:
            return "CONFIRMED_BAD_DATA"
        if has_soft_quality_problem and model_flags_it:
            return "POSSIBLE_BAD_DATA"
        if model_flags_it and has_sustained_saturation:
            # Objective evidence (sustained gyro-rail event) of a genuinely
            # vigorous, atypical-for-"casual NORMAL" movement inside this
            # recording - but sustained saturation alone does not distinguish
            # "accidentally too vigorous" from "deliberately-collected energetic
            # NORMAL example, correctly labeled." Needs a human to say which.
            return "POSSIBLE_MISLABEL"
        if model_flags_it and far_from_normal and not stat_outlier:
            return "POSSIBLE_MISLABEL"
        if model_flags_it and (stat_outlier or far_from_normal or has_sustained_saturation):
            return "DIFFICULT_BUT_VALID_DATA"
        if model_flags_it:
            return "DIFFICULT_BUT_VALID_DATA"
        return "NO_PROBLEM_FOUND"

    normal_summary["classification"] = normal_summary.apply(classify, axis=1)

    # ---- STEP 6: new PUSH/PULL recordings validated separately ----
    # "new" = not in V5's own train/test split at all (V5 only ever saw 15/15 old push/pull)
    pushpull_summary = rec_summary[rec_summary["true_label"].isin(["PUSH", "PULL"])].copy()
    pushpull_quality = quality_df[quality_df["class"].isin(["PUSH", "PULL"])].copy()
    new_pushpull_quality = pushpull_quality.merge(
        rec_summary[["recording_id", "v5_never_saw_this_recording"]], on="recording_id", how="left"
    )
    new_pushpull_quality = new_pushpull_quality[new_pushpull_quality["v5_never_saw_this_recording"] == True]

    # ---- also report TWISTING/FALL -> NORMAL confusions for context (symmetry check) ----
    other_confusions = rec_summary[
        ((rec_summary["true_label"] == "FALL") & (rec_summary["pct_correct"] < 80)) |
        ((rec_summary["true_label"] == "TWISTING") & (rec_summary["pct_correct"] < 80))
    ][["recording_id", "true_label", "n_windows", "pct_correct", "pred_distribution"]]

    # ============================ WRITE OUTPUTS ============================
    quality_df.to_json(OUT_DIR / "_raw_quality_table.json", orient="records", indent=2)

    normal_summary_out = normal_summary.drop(columns=["pred_distribution"], errors="ignore")
    normal_summary_out.to_csv(OUT_DIR / "suspicious_normal_recordings.csv", index=False)

    possible_bad = rec_summary[
        rec_summary["recording_id"].isin(
            normal_summary[normal_summary["classification"].isin(["CONFIRMED_BAD_DATA", "POSSIBLE_BAD_DATA", "POSSIBLE_MISLABEL"])]["recording_id"]
        )
    ]
    possible_bad_out = possible_bad.drop(columns=["pred_distribution"], errors="ignore")
    possible_bad_out.to_csv(OUT_DIR / "potentially_bad_recordings.csv", index=False)

    full_report = {
        "step1_raw_quality_summary": quality_df["quality_status"].value_counts().to_dict(),
        "step1_recordings_with_problems": quality_df[quality_df["quality_status"] != "OK"][
            ["recording_id", "class", "quality_status", "problems_found"]
        ].to_dict(orient="records"),
        "step1_duplicate_groups": {str(k): v for k, v in duplicate_groups.items()},
        "step2_statistical_outliers": outliers_df.to_dict(orient="records") if len(outliers_df) else [],
        "step2_normal_proximity_to_fall_twisting": proximity_df.to_dict(orient="records"),
        "step3_model_flagged_recordings_all_classes": rec_summary[
            (rec_summary["pct_correct"] < 90)
        ].drop(columns=["pred_distribution"]).to_dict(orient="records"),
        "step3_other_confusions_fall_twisting_to_normal": other_confusions.assign(
            pred_distribution=other_confusions["pred_distribution"].apply(str)
        ).to_dict(orient="records"),
        "step4_ranked_suspicious_normal": normal_summary_out.to_dict(orient="records"),
        "step5_classification_counts": normal_summary["classification"].value_counts().to_dict(),
        "step6_new_pushpull_raw_quality": new_pushpull_quality.drop(columns=["v5_never_saw_this_recording"], errors="ignore").to_dict(orient="records"),
        "step6_new_pushpull_model_performance": pushpull_summary[pushpull_summary["v5_never_saw_this_recording"]].drop(columns=["pred_distribution"]).to_dict(orient="records"),
    }

    with open(OUT_DIR / "dataset_quality_audit_report.json", "w") as f:
        json.dump(full_report, f, indent=2, default=str)

    # ---- human-readable txt summary ----
    with open(OUT_DIR / "dataset_quality_audit_report.txt", "w") as f:
        f.write("SAFEHER TRAINING DATA QUALITY AUDIT\n")
        f.write("=" * 70 + "\n\n")
        f.write(f"Total recordings scanned: {len(quality_df)}\n")
        f.write(f"Quality status: {quality_df['quality_status'].value_counts().to_dict()}\n\n")

        f.write("STEP 5 CLASSIFICATION COUNTS (NORMAL recordings only):\n")
        for k, v in normal_summary["classification"].value_counts().items():
            f.write(f"  {k}: {v}\n")

        f.write("\nTOP 15 MOST SUSPICIOUS NORMAL RECORDINGS:\n")
        f.write("-" * 70 + "\n")
        for _, r in normal_summary.head(15).iterrows():
            f.write(f"{r['recording_id']}: {r['pct_predicted_FALL']:.1f}% FALL, "
                    f"{r['pct_predicted_TWISTING']:.1f}% TWISTING, "
                    f"max_FALL_proba={r['max_FALL_proba']:.3f}, "
                    f"classification={r['classification']}\n")
            if r.get("raw_quality_problems"):
                f.write(f"    raw quality problems: {r['raw_quality_problems']}\n")
            if r.get("statistical_outlier_features"):
                f.write(f"    statistical outliers: {r['statistical_outlier_features']}\n")

        f.write("\nSTEP 6: NEW PUSH/PULL recordings raw quality problems found:\n")
        if len(new_pushpull_quality):
            probs = new_pushpull_quality[new_pushpull_quality["quality_status"] != "OK"]
            if len(probs):
                for _, r in probs.iterrows():
                    f.write(f"  {r['recording_id']}: {r['problems_found']}\n")
            else:
                f.write("  none - all new PUSH/PULL recordings pass raw quality checks\n")

    print(f"\nReports written to {OUT_DIR}")
    print(f"  dataset_quality_audit_report.json")
    print(f"  dataset_quality_audit_report.txt")
    print(f"  suspicious_normal_recordings.csv")
    print(f"  potentially_bad_recordings.csv")

    return quality_df, normal_summary, rec_summary, new_pushpull_quality


if __name__ == "__main__":
    main()
