"""Evaluate the v5 glove model, and the decision rule the app actually uses.

Two things get measured here, and the second matters more.

**The model.** Per-class precision and recall on the held-out recordings, so
there is a number to put in the report instead of an accuracy figure that a
99%-NORMAL dataset would flatter.

**The deployed rule.** The app does not act on one window. `GloveThreatDetector`
raises an alarm when it sees `required_hits` FALL classifications, each at or
above the user's threshold, inside a sliding window of `window_seconds`. That
rule is what decides whether someone's contacts get called, so this simulates
it over each held-out recording end to end and reports:

  * how many FALL recordings would have raised an alarm  (detection)
  * how many non-FALL recordings would have raised one   (false alarms)

A model with excellent per-window recall can still be unusable if ordinary
movement trips the rule twice in five seconds, and a model with mediocre
per-window recall can be fine if falls reliably produce a burst. Only the
second measurement can tell them apart.

Timing comes from the firmware: SAMPLE_INTERVAL_US 10000 (100 Hz), WINDOW_SIZE
100, OVERLAP 50 -- so a classification lands every 0.5 s.

Usage:
    python ml/scripts/evaluate_v5.py
    python ml/scripts/evaluate_v5.py --threshold 0.80 --required-hits 3
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

import numpy as np
import pandas as pd
import xgboost as xgb
from sklearn.metrics import classification_report, confusion_matrix

ROOT = Path(__file__).resolve().parents[2]
FEATURES = ROOT / "ml" / "features" / "glove_7class_features.csv"
MODEL = ROOT / "ml" / "models" / "safeher_glove_7class_v5_xgboost.json"
LABEL_MAP = ROOT / "ml" / "models" / "glove_7class_v5_label_mapping.json"
FEATURE_COLS = ROOT / "ml" / "models" / "glove_7class_v5_feature_columns.json"
SPLIT = ROOT / "ml" / "models" / "glove_7class_v5_train_test_split.json"

# From the firmware. A new classification every STEP/RATE seconds.
SECONDS_PER_WINDOW = 50 / 100.0


def load():
    features = pd.read_csv(FEATURES)
    labels = json.loads(LABEL_MAP.read_text())
    columns = json.loads(FEATURE_COLS.read_text())
    split = json.loads(SPLIT.read_text())

    model = xgb.XGBClassifier()
    model.load_model(str(MODEL))
    return features, labels, columns, split, model


def held_out(features: pd.DataFrame, split: dict) -> pd.DataFrame:
    """Rows belonging to test recordings.

    Split by *recording*, never by window: consecutive windows overlap by 50
    samples, so splitting on windows would put near-identical rows on both
    sides and report a score the model has not earned.
    """
    test_ids = {rec for recs in split["test_recordings"].values() for rec in recs}
    keyed = features["recording_id"].astype(str)
    return features[keyed.isin(test_ids)].copy()


def simulate_detector(
    fall_flags: np.ndarray, *, required_hits: int, window_windows: int
) -> bool:
    """Would the app have raised an alarm during this recording?

    Mirrors GloveThreatDetector: a sliding window of `window_windows`
    consecutive classifications, firing the moment it contains `required_hits`
    qualifying ones. Deliberately not "N consecutive": a real fall reports
    FALL, then NORMAL from the floor, and requiring an unbroken run would miss
    the event the rule exists to catch.
    """
    for end in range(len(fall_flags)):
        start = max(0, end - window_windows + 1)
        if fall_flags[start : end + 1].sum() >= required_hits:
            return True
    return False


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--threshold", type=float, default=0.75,
                        help="confidence a FALL must reach to count (app default 0.75)")
    parser.add_argument("--required-hits", type=int, default=2,
                        help="qualifying FALLs needed inside the window (app default 2)")
    parser.add_argument("--window-seconds", type=float, default=5.0,
                        help="sliding window length (app default 5s)")
    args = parser.parse_args()

    window_windows = max(1, round(args.window_seconds / SECONDS_PER_WINDOW))

    features, labels, columns, split, model = load()
    inverse = {v: k for k, v in labels.items()}
    fall_index = labels["FALL"]

    test = held_out(features, split)
    if test.empty:
        raise SystemExit("No held-out rows matched the split file.")

    X = test[columns]
    y_true = test["label"].map(labels).to_numpy()
    proba = model.predict_proba(X)
    y_pred = proba.argmax(axis=1)

    names = [inverse[i] for i in range(len(labels))]

    print("=" * 70)
    print("SafeHer glove v5 -- held-out evaluation")
    print("=" * 70)
    print(f"test recordings: {test['recording_id'].nunique()}   windows: {len(test)}")
    print(f"decision rule:   {args.required_hits} FALL >= {args.threshold:.2f} "
          f"within {args.window_seconds:g}s ({window_windows} windows @ "
          f"{SECONDS_PER_WINDOW:g}s each)")
    print()

    print("-- per-window performance " + "-" * 44)
    print(classification_report(y_true, y_pred, target_names=names, zero_division=0, digits=3))

    print("-- confusion matrix (rows = truth, cols = predicted) " + "-" * 17)
    matrix = confusion_matrix(y_true, y_pred, labels=list(range(len(labels))))
    header = "".join(f"{n[:6]:>8}" for n in names)
    print(f"{'':>10}{header}")
    for i, name in enumerate(names):
        print(f"{name:>10}" + "".join(f"{v:>8}" for v in matrix[i]))
    print()

    # The number that matters most: a missed FALL is someone hurt with no
    # alarm raised.
    fall_rows = y_true == fall_index
    if fall_rows.any():
        fall_recall = float((y_pred[fall_rows] == fall_index).mean())
        print(f"FALL per-window recall: {fall_recall:.1%} "
              f"({int((y_pred[fall_rows] == fall_index).sum())}/{int(fall_rows.sum())} windows)")
    print()

    print("-- what the app would actually do " + "-" * 36)
    triggered_true, triggered_false = [], []
    for recording_id, group in test.groupby("recording_id", sort=True):
        rows = group.index
        p = proba[[test.index.get_loc(i) for i in rows]]
        qualifies = (p.argmax(axis=1) == fall_index) & (p[:, fall_index] >= args.threshold)
        fired = simulate_detector(
            qualifies.astype(int),
            required_hits=args.required_hits,
            window_windows=window_windows,
        )
        truth = group["label"].iloc[0]
        (triggered_true if truth == "FALL" else triggered_false).append((recording_id, fired))

    caught = sum(1 for _, fired in triggered_true if fired)
    missed = len(triggered_true) - caught
    false_alarms = [r for r, fired in triggered_false if fired]

    print(f"FALL recordings that would raise an alarm : {caught}/{len(triggered_true)}")
    print(f"FALL recordings that would be MISSED      : {missed}")
    print(f"non-FALL recordings that would FALSE ALARM: {len(false_alarms)}/{len(triggered_false)}")
    if false_alarms:
        by_class = Counter(
            test[test["recording_id"] == r]["label"].iloc[0] for r in false_alarms
        )
        print(f"  false alarms by class: {dict(by_class)}")
    print()

    # The most actionable output: which recordings the model is confidently
    # wrong about. Threshold tuning cannot help a 0.98-confidence mistake, so
    # naming the recording tells whoever collects data exactly what to collect
    # more of.
    print("-- where the confusion actually is " + "-" * 35)
    marked = test.assign(fall_p=proba[:, fall_index], pred=y_pred)
    noisy = []
    for recording_id, group in marked[marked["label"] != "FALL"].groupby("recording_id"):
        flagged = group[(group["pred"] == fall_index) & (group["fall_p"] >= args.threshold)]
        if len(flagged):
            noisy.append((recording_id, group["label"].iloc[0], len(flagged), len(group),
                          float(flagged["fall_p"].max())))
    if noisy:
        print("non-FALL recordings producing FALL windows above threshold:")
        for rid, truth, hits, total, top in sorted(noisy, key=lambda r: -r[2]):
            verdict = "TRIPS the rule" if hits >= args.required_hits else "filtered by the vote"
            print(f"  {rid:<14} {truth:<9} {hits}/{total} windows, max {top:.3f}  -> {verdict}")
    else:
        print("no non-FALL recording produced a qualifying FALL window.")
    print()
    print("FALL recordings, for contrast:")
    for recording_id, group in marked[marked["label"] == "FALL"].groupby("recording_id"):
        flagged = group[(group["pred"] == fall_index) & (group["fall_p"] >= args.threshold)]
        margin = "MARGINAL" if len(flagged) <= args.required_hits else ""
        print(f"  {recording_id:<14} {len(flagged)}/{len(group)} windows, "
              f"max {float(group['fall_p'].max()):.3f}  {margin}")
    print()

    print("-" * 70)
    print("READ THIS BEFORE QUOTING ANY NUMBER ABOVE")
    print("-" * 70)
    counts = Counter(test["label"])
    smallest = min(counts.values())
    print(f"The held-out set is {test['recording_id'].nunique()} recordings; the "
          f"smallest class has {smallest} windows.")
    print("Per-class figures from this few recordings move by large amounts if a")
    print("single recording changes, so treat them as a direction, not a")
    print("measurement. A missed FALL here is one recording, not one percent.")
    print()
    print("The false-alarm count is the number to watch: each one is a real")
    print("person's emergency contacts being called because a glove was set down")
    print("firmly. It is also the number that decides whether people leave the")
    print("feature switched on.")


if __name__ == "__main__":
    main()
