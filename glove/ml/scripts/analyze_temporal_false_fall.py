#!/usr/bin/env python3
"""READ-ONLY simulation: TASK 1 (alternative FALL confirmation hit-counts) and
TASK 2 (probability smoothing), run against the CURRENT PRODUCTION V5 model's
predictions on development recordings only, in original temporal window order.

Does not modify the model, firmware, dataset, or locked test set. Does not
select or apply any new threshold/debounce rule - this only measures what
each candidate rule WOULD have done, on data already in hand.
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
FALL_ID = LABEL_TO_ID["FALL"]
METADATA_COLUMNS = ["recording_id", "source_file", "label"]
FALL_THRESHOLD = 0.65  # unchanged, matches firmware exactly - not being tuned here


def find_bursts(qualifies: np.ndarray):
    """Return list of (start_idx, length) for maximal runs of True in `qualifies`."""
    bursts = []
    i = 0
    n = len(qualifies)
    while i < n:
        if qualifies[i]:
            j = i
            while j < n and qualifies[j]:
                j += 1
            bursts.append((i, j - i))
            i = j
        else:
            i += 1
    return bursts


def simulate_hitcount(rec_groups, hit_count: int):
    """Simulate the EXACT firmware debounce logic (reset-on-non-qualifying,
    escalate at N consecutive qualifying windows) for a given hit_count N."""
    normal_recordings_with_highrisk = set()
    fall_recordings_detected = set()
    fall_recordings_missed = set()
    highrisk_events = []  # (recording_id, true_label, window_idx)
    false_fall_windows_normal = 0
    false_fall_windows_total = 0

    for rid, g in rec_groups:
        true_label = g["label"].iloc[0]
        pred = g["pred_label"].to_numpy()
        fall_proba = g["proba_FALL"].to_numpy()
        qualifies = (pred == "FALL") & (fall_proba >= FALL_THRESHOLD)

        if true_label != "FALL":
            false_fall_windows_total += int(qualifies.sum())
            if true_label == "NORMAL":
                false_fall_windows_normal += int(qualifies.sum())

        consecutive = 0
        recording_had_highrisk = False
        for w_idx, q in enumerate(qualifies):
            if q:
                consecutive += 1
            else:
                consecutive = 0
            if consecutive == hit_count:  # transition point: fires once per episode
                highrisk_events.append({"recording_id": rid, "true_label": true_label, "window_idx": w_idx})
                recording_had_highrisk = True
                if true_label == "NORMAL":
                    normal_recordings_with_highrisk.add(rid)

        if true_label == "FALL":
            if recording_had_highrisk:
                fall_recordings_detected.add(rid)
            else:
                fall_recordings_missed.add(rid)

    return {
        "hit_count": hit_count,
        "n_normal_recordings_with_highrisk": len(normal_recordings_with_highrisk),
        "normal_recordings_with_highrisk": sorted(normal_recordings_with_highrisk),
        "false_fall_windows_normal": false_fall_windows_normal,
        "false_fall_windows_total": false_fall_windows_total,
        "n_highrisk_events": len(highrisk_events),
        "n_highrisk_events_in_normal": sum(1 for e in highrisk_events if e["true_label"] == "NORMAL"),
        "n_highrisk_events_in_fall": sum(1 for e in highrisk_events if e["true_label"] == "FALL"),
        "n_highrisk_events_in_other": sum(1 for e in highrisk_events if e["true_label"] not in ("NORMAL", "FALL")),
        "n_fall_recordings_detected": len(fall_recordings_detected),
        "n_fall_recordings_missed": len(fall_recordings_missed),
        "fall_recordings_missed_ids": sorted(fall_recordings_missed),
        "highrisk_events_detail": highrisk_events,
    }


def simulate_smoothing(rec_groups, window_size: int):
    """Apply a trailing moving average to the per-class probability vectors
    (not just proba_FALL - also recompute argmax on the smoothed vector, so
    PUSH/PULL/TWISTING effects are measurable too), then apply the SAME
    2-hit@0.65 firmware rule on the smoothed FALL probability/class."""
    proba_cols = [f"proba_{c}" for c in LABELS]

    false_fall_windows_normal = 0
    normal_recordings_with_highrisk = set()
    fall_recordings_detected = set()
    fall_recordings_missed = set()
    n_highrisk_events = 0
    class_change_counts = {c: 0 for c in LABELS}  # how often smoothing changes the argmax vs raw, by TRUE class
    total_windows_by_class = {c: 0 for c in LABELS}

    for rid, g in rec_groups:
        true_label = g["label"].iloc[0]
        raw_proba = g[proba_cols].to_numpy()
        raw_pred = g["pred_label"].to_numpy()

        if window_size <= 1:
            smoothed = raw_proba
        else:
            smoothed = np.zeros_like(raw_proba)
            for i in range(len(raw_proba)):
                lo = max(0, i - window_size + 1)
                smoothed[i] = raw_proba[lo:i + 1].mean(axis=0)

        smoothed_pred_id = np.argmax(smoothed, axis=1)
        smoothed_pred = np.array([LABELS[i] for i in smoothed_pred_id])
        smoothed_fall_proba = smoothed[:, FALL_ID]

        total_windows_by_class[true_label] += len(g)
        changed = (smoothed_pred != raw_pred)
        class_change_counts[true_label] += int(changed.sum())

        qualifies = (smoothed_pred == "FALL") & (smoothed_fall_proba >= FALL_THRESHOLD)
        if true_label == "NORMAL":
            false_fall_windows_normal += int(qualifies.sum())

        consecutive = 0
        recording_had_highrisk = False
        for q in qualifies:
            if q:
                consecutive += 1
            else:
                consecutive = 0
            if consecutive == 2:  # keep the EXISTING 2-hit rule, isolate the smoothing effect only
                n_highrisk_events += 1
                recording_had_highrisk = True
                if true_label == "NORMAL":
                    normal_recordings_with_highrisk.add(rid)

        if true_label == "FALL":
            if recording_had_highrisk:
                fall_recordings_detected.add(rid)
            else:
                fall_recordings_missed.add(rid)

    return {
        "window_size": window_size,
        "n_normal_recordings_with_highrisk": len(normal_recordings_with_highrisk),
        "normal_recordings_with_highrisk": sorted(normal_recordings_with_highrisk),
        "false_fall_windows_normal": false_fall_windows_normal,
        "n_highrisk_events": n_highrisk_events,
        "n_fall_recordings_detected": len(fall_recordings_detected),
        "n_fall_recordings_missed": len(fall_recordings_missed),
        "fall_recordings_missed_ids": sorted(fall_recordings_missed),
        "argmax_change_rate_by_true_class": {
            c: (class_change_counts[c] / total_windows_by_class[c] if total_windows_by_class[c] else None)
            for c in LABELS
        },
    }


def main():
    v5_split = json.loads(V5_SPLIT_PATH.read_text())
    locked_test_recordings = set()
    for recs in v5_split["test_recordings"].values():
        locked_test_recordings.update(recs)
    assert len(locked_test_recordings) == 22

    full_features = pd.read_csv(FEATURES_PATH)
    feature_cols = json.loads(V5_FEATURE_COLUMNS_PATH.read_text())
    assert feature_cols == [c for c in full_features.columns if c not in METADATA_COLUMNS]

    devset = full_features[~full_features["recording_id"].isin(locked_test_recordings)].reset_index(drop=True)
    assert set(devset["recording_id"]).isdisjoint(locked_test_recordings), "LEAKAGE: locked test recording in devset"
    print(f"Development set: {devset['recording_id'].nunique()} recordings, {len(devset)} windows (locked test set excluded, never touched)")

    bst = xgb.Booster()
    bst.load_model(str(V5_MODEL_PATH))
    X = devset[feature_cols].astype(float).to_numpy()
    proba = bst.inplace_predict(X)
    pred_id = np.argmax(proba, axis=1)

    df = devset[METADATA_COLUMNS].copy()
    df["pred_label"] = [LABELS[i] for i in pred_id]
    for i, cls in enumerate(LABELS):
        df[f"proba_{cls}"] = proba[:, i]

    # preserve original (temporal) row order within each recording - no re-sorting
    rec_groups = list(df.groupby("recording_id", sort=False))

    # ================= TASK 1: burst statistics (independent of hit-count) =================
    print("\n" + "=" * 70)
    print("TASK 1: RAW BURST STATISTICS (qualifying FALL windows, threshold=0.65)")
    print("=" * 70)
    burst_records = []
    for rid, g in rec_groups:
        true_label = g["label"].iloc[0]
        pred = g["pred_label"].to_numpy()
        fall_proba = g["proba_FALL"].to_numpy()
        qualifies = (pred == "FALL") & (fall_proba >= FALL_THRESHOLD)
        for start_idx, length in find_bursts(qualifies):
            burst_records.append({"recording_id": rid, "true_label": true_label, "start_idx": int(start_idx), "length": int(length)})
    bursts_df = pd.DataFrame(burst_records)

    burst_len_dist_by_class = {}
    for cls in LABELS:
        sub = bursts_df[bursts_df["true_label"] == cls]
        burst_len_dist_by_class[cls] = sub["length"].value_counts().sort_index().to_dict() if len(sub) else {}

    print("Burst length distribution, NORMAL recordings:", burst_len_dist_by_class.get("NORMAL", {}))
    print("Burst length distribution, FALL recordings:", burst_len_dist_by_class.get("FALL", {}))
    print("Burst length distribution, TWISTING recordings:", burst_len_dist_by_class.get("TWISTING", {}))

    # ================= TASK 1: hit-count simulation (2/3/4) =================
    print("\n" + "=" * 70)
    print("TASK 1: HIT-COUNT SIMULATION (2-hit vs 3-hit vs 4-hit)")
    print("=" * 70)
    hitcount_results = {}
    for n in (2, 3, 4):
        res = simulate_hitcount(rec_groups, n)
        hitcount_results[n] = res
        print(f"\n{n}-hit rule:")
        print(f"  NORMAL recordings producing >=1 HIGH_RISK: {res['n_normal_recordings_with_highrisk']} -> {res['normal_recordings_with_highrisk']}")
        print(f"  False FALL windows (NORMAL): {res['false_fall_windows_normal']}  (all non-FALL classes: {res['false_fall_windows_total']})")
        print(f"  Total HIGH_RISK events: {res['n_highrisk_events']} (in NORMAL={res['n_highrisk_events_in_normal']}, in FALL={res['n_highrisk_events_in_fall']}, in other={res['n_highrisk_events_in_other']})")
        print(f"  FALL recordings detected: {res['n_fall_recordings_detected']}  missed: {res['n_fall_recordings_missed']} -> {res['fall_recordings_missed_ids']}")

    # ================= TASK 2: probability smoothing simulation =================
    print("\n" + "=" * 70)
    print("TASK 2: PROBABILITY SMOOTHING SIMULATION (moving average, existing 2-hit rule)")
    print("=" * 70)
    smoothing_results = {}
    for w in (1, 3, 5):
        res = simulate_smoothing(rec_groups, w)
        smoothing_results[w] = res
        label = "no smoothing (baseline)" if w == 1 else f"{w}-window moving average"
        print(f"\n{label}:")
        print(f"  NORMAL recordings producing >=1 HIGH_RISK: {res['n_normal_recordings_with_highrisk']} -> {res['normal_recordings_with_highrisk']}")
        print(f"  False FALL windows (NORMAL): {res['false_fall_windows_normal']}")
        print(f"  Total HIGH_RISK events: {res['n_highrisk_events']}")
        print(f"  FALL recordings detected: {res['n_fall_recordings_detected']}  missed: {res['n_fall_recordings_missed']} -> {res['fall_recordings_missed_ids']}")
        print(f"  Argmax change rate by true class: {res['argmax_change_rate_by_true_class']}")

    # ============================ WRITE OUTPUTS ============================
    report = {
        "experiment": "false_fall_temporal_analysis",
        "description": "Simulation only - the production V5 model's own predictions on development recordings, replaying the exact firmware debounce rule at alternative hit-counts, and testing probability-smoothing as an alternative to changing hit-count. No model/firmware/dataset changes.",
        "locked_test_recordings_excluded": sorted(locked_test_recordings),
        "development_recordings": int(devset["recording_id"].nunique()),
        "development_windows": int(len(devset)),
        "fall_threshold_unchanged": FALL_THRESHOLD,
        "task1_burst_length_distribution_by_true_class": burst_len_dist_by_class,
        "task1_hitcount_simulation": {str(k): v for k, v in hitcount_results.items()},
        "task2_smoothing_simulation": {str(k): v for k, v in smoothing_results.items()},
        "note_on_window_step": "Windows are 100 samples/50-sample step at 100Hz -> consecutive windows are 500ms apart; a '3-window moving average' spans ~1.5s of wall-clock time, '5-window' spans ~2.5s.",
    }
    with open(OUT_DIR / "temporal_analysis_report.json", "w") as f:
        json.dump(report, f, indent=2, default=str)

    with open(OUT_DIR / "temporal_analysis_report.txt", "w") as f:
        f.write("SAFEHER FALSE-FALL TEMPORAL SIMULATION (READ-ONLY)\n")
        f.write("=" * 70 + "\n\n")
        f.write(f"Development recordings: {devset['recording_id'].nunique()} / windows: {len(devset)}\n")
        f.write("Locked test set: EXCLUDED, NOT USED FOR ANY DECISION\n\n")

        f.write("TASK 1 - HIT-COUNT SIMULATION\n")
        f.write("-" * 70 + "\n")
        for n, res in hitcount_results.items():
            f.write(f"{n}-hit: NORMAL_recs_with_HIGH_RISK={res['n_normal_recordings_with_highrisk']} "
                     f"false_FALL_windows_NORMAL={res['false_fall_windows_normal']} "
                     f"HIGH_RISK_events={res['n_highrisk_events']} "
                     f"FALL_detected={res['n_fall_recordings_detected']} FALL_missed={res['n_fall_recordings_missed']}\n")

        f.write("\nTASK 2 - SMOOTHING SIMULATION\n")
        f.write("-" * 70 + "\n")
        for w, res in smoothing_results.items():
            f.write(f"window={w}: NORMAL_recs_with_HIGH_RISK={res['n_normal_recordings_with_highrisk']} "
                     f"false_FALL_windows_NORMAL={res['false_fall_windows_normal']} "
                     f"HIGH_RISK_events={res['n_highrisk_events']} "
                     f"FALL_detected={res['n_fall_recordings_detected']} FALL_missed={res['n_fall_recordings_missed']}\n")

        f.write("\nBURST LENGTH DISTRIBUTION (NORMAL): " + str(burst_len_dist_by_class.get("NORMAL", {})) + "\n")
        f.write("BURST LENGTH DISTRIBUTION (FALL): " + str(burst_len_dist_by_class.get("FALL", {})) + "\n")

    print(f"\nReports written to {OUT_DIR}")
    return report


if __name__ == "__main__":
    main()
