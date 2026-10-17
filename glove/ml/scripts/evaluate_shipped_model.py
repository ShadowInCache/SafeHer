#!/usr/bin/env python3
"""Measure the glove model as it is actually deployed, not as it was trained.

The training reports in `glove/ml/models/` give per-window argmax metrics. That
is the right way to compare candidate models, but it is not what runs on the
wrist. Between the model and the fusion engine sit three gates:

  1. firmware confidence gate  -- a FALL or SUDDEN_MOVEMENT below
     FALL_CONFIDENCE_THRESHOLD (0.65) is downgraded to NORMAL
  2. firmware debounce         -- SUDDEN_MOVEMENT must hold for
     SUDDEN_MOVEMENT_CONFIRMATION_WINDOWS (2) consecutive windows
  3. app GloveConfirmation     -- any threatening class must repeat before it
     is reported to fusion at all

None of those appear in the published accuracy. This script applies them in
order and reports what each one costs and buys, so the false-positive rate can
be quoted for the shipped system rather than for the bare classifier.

Two modes:

  * locked test set (default) -- reproduces the held-out evaluation, and
    checks it still matches the published figures before reporting anything
    new. If the reproduction check fails, the model or the features have moved
    and no number below should be trusted.

  * --raw-dir DIR -- windows raw recordings (timestamp_ms,Ax..Gz,label) with
    the same extractor used in training. This is the mode for measuring a
    field false-positive rate: record ordinary wear, label it NORMAL, and any
    threatening report is a false positive.

Usage:
    python glove/ml/scripts/evaluate_shipped_model.py
    python glove/ml/scripts/evaluate_shipped_model.py --raw-dir path/to/wear
    python glove/ml/scripts/evaluate_shipped_model.py --json
"""
from __future__ import annotations

import argparse
import json
import sys
import types
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[3]
MODEL_DIR = ROOT / "glove/ml/models/glove_5class_v7_merged_pushpulljerk_final"
MODEL = MODEL_DIR / "safeher_glove_5class_v7_merged_pushpulljerk_candidate_xgboost.json"
COMPARISON = MODEL_DIR / "v7_merged_pushpulljerk_candidate_vs_original_v5_comparison.json"
REPORT = MODEL_DIR / "v7_merged_pushpulljerk_candidate_training_report.json"
FEATURES = ROOT / "glove/ml/features/glove_5class_features_v1_merged_pushpull_jerk.csv"

META_COLUMNS = {"recording_id", "source_file", "label"}

# Mirrors the firmware constants. Keep in step with
# SafeHer_Glove_V5_OnDevice.ino and features/safety/domain/glove_confirmation.dart.
FALL_CONFIDENCE_THRESHOLD = 0.65
SUDDEN_MOVEMENT_CONFIRMATION_WINDOWS = 2
APP_CONFIRMATION_HITS = 2

WINDOW_SIZE_SAMPLES = 100
STEP_SIZE_SAMPLES = 50
# PUSH/PULL/JERK were merged into SUDDEN_MOVEMENT for the 5-class model.
MERGED = {"PUSH": "SUDDEN_MOVEMENT", "PULL": "SUDDEN_MOVEMENT", "JERK": "SUDDEN_MOVEMENT"}


def _feature_extractor():
    """The training-time extractor, imported without its serial dependency.

    `safeher_realtime_inference` imports pyserial for live capture. Nothing in
    the feature path needs it, and requiring a serial library to score a CSV
    would be a reason not to run this script.
    """
    for name in ("serial", "serial.tools", "serial.tools.list_ports"):
        sys.modules.setdefault(name, types.ModuleType(name))
    sys.path.insert(0, str(ROOT / "glove/ml/scripts"))
    from safeher_realtime_inference import extract_glove_7class_features

    return extract_glove_7class_features


def load_locked_test(feature_cols: list[str]) -> pd.DataFrame:
    locked = set(json.loads(COMPARISON.read_text())["locked_test_recordings"])
    df = pd.read_csv(FEATURES)
    return df[df["recording_id"].isin(locked)].reset_index(drop=True)


def window_raw_dir(raw_dir: Path, feature_cols: list[str]) -> pd.DataFrame:
    """Window raw recordings the way training did."""
    extract = _feature_extractor()
    rows = []
    for path in sorted(raw_dir.rglob("*.csv")):
        df = pd.read_csv(path)
        missing = {"Ax", "Ay", "Az", "Gx", "Gy", "Gz"} - set(df.columns)
        if missing:
            print(f"  skipped {path.name}: missing columns {sorted(missing)}")
            continue
        label = str(df["label"].iloc[0]).upper() if "label" in df.columns else "NORMAL"
        label = MERGED.get(label, label)
        for start in range(0, len(df) - WINDOW_SIZE_SAMPLES + 1, STEP_SIZE_SAMPLES):
            feats = extract(df.iloc[start : start + WINDOW_SIZE_SAMPLES])
            row = {c: feats[c] for c in feature_cols}
            row["recording_id"] = path.stem
            row["label"] = label
            rows.append(row)
    if not rows:
        raise SystemExit(f"no usable recordings under {raw_dir}")
    return pd.DataFrame(rows)


def gated_stream(proba: np.ndarray, classes: list[str], order: np.ndarray,
                 confidence: bool, firmware_debounce: bool, app_confirm: bool) -> list[str]:
    """What fusion is told, window by window, for one recording in order."""
    sudden_streak = 0
    app_streak = 0
    told = []
    for i in order:
        p = proba[i]
        cls = classes[int(p.argmax())]
        if confidence and cls in ("FALL", "SUDDEN_MOVEMENT") and float(p.max()) < FALL_CONFIDENCE_THRESHOLD:
            cls = "NORMAL"
        if firmware_debounce:
            if cls == "SUDDEN_MOVEMENT":
                sudden_streak += 1
                if sudden_streak < SUDDEN_MOVEMENT_CONFIRMATION_WINDOWS:
                    cls = "NORMAL"
            else:
                sudden_streak = 0
        reported = cls
        if app_confirm:
            if cls == "NORMAL":
                app_streak = 0
            else:
                app_streak += 1
                if app_streak < APP_CONFIRMATION_HITS:
                    reported = "NORMAL"  # withheld from fusion
        told.append(reported)
    return told


def evaluate(df: pd.DataFrame, proba: np.ndarray, classes: list[str], stages) -> dict:
    out = {}
    for name, flags in stages:
        told_all, truth_all = [], []
        for _, grp in df.groupby("recording_id", sort=False):
            order = grp.index.to_numpy()
            told_all.extend(gated_stream(proba, classes, order, *flags))
            truth_all.extend(grp["label"].tolist())
        normals = [(t, r) for t, r in zip(truth_all, told_all) if t == "NORMAL"]
        falls = [(t, r) for t, r in zip(truth_all, told_all) if t == "FALL"]
        fp = sum(1 for _, r in normals if r != "NORMAL")
        out[name] = {
            "normal_windows": len(normals),
            "false_positives": fp,
            "false_positive_rate": (fp / len(normals)) if normals else None,
            "false_as_fall": sum(1 for _, r in normals if r == "FALL"),
            "fall_windows": len(falls),
            "fall_recall": (sum(1 for _, r in falls if r == "FALL") / len(falls)) if falls else None,
        }
    return out


def per_event(df: pd.DataFrame, proba: np.ndarray, classes: list[str]) -> dict:
    """A fall spans many windows; missing some is not missing the fall."""
    detected = total_falls = alarmed = total_normal = 0
    rows = []
    for rec, grp in df.groupby("recording_id", sort=True):
        order = grp.index.to_numpy()
        told = gated_stream(proba, classes, order, True, True, True)
        truth = grp["label"].iloc[0]
        n_fall = sum(1 for t in told if t == "FALL")
        n_threat = sum(1 for t in told if t != "NORMAL")
        rows.append((rec, truth, len(order), n_fall, n_threat))
        if truth == "FALL":
            total_falls += 1
            detected += 1 if n_fall else 0
        if truth == "NORMAL":
            total_normal += 1
            alarmed += 1 if n_threat else 0
    return {"rows": rows, "falls_detected": detected, "total_falls": total_falls,
            "normal_alarmed": alarmed, "total_normal": total_normal}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--raw-dir", type=Path, help="score raw recordings instead of the locked test set")
    ap.add_argument("--model", type=Path, default=MODEL)
    ap.add_argument("--json", action="store_true", help="emit machine-readable results")
    args = ap.parse_args()

    from xgboost import XGBClassifier  # imported late so --help works without it

    classes = json.loads(REPORT.read_text())["class_order"]
    model = XGBClassifier()
    model.load_model(str(args.model))

    feature_cols = [c for c in pd.read_csv(FEATURES, nrows=1).columns if c not in META_COLUMNS]
    if args.raw_dir:
        df = window_raw_dir(args.raw_dir, feature_cols)
        source = str(args.raw_dir)
    else:
        df = load_locked_test(feature_cols)
        source = "locked test set"

    proba = model.predict_proba(df[feature_cols].values)
    pred = np.array([classes[i] for i in proba.argmax(1)])

    results = {"source": source, "windows": len(df), "model": args.model.name}

    if not args.raw_dir:
        # Refuse to report anything new unless the published evaluation still
        # reproduces -- otherwise the model or the features have moved.
        from sklearn.metrics import accuracy_score, f1_score

        published = json.loads(COMPARISON.read_text())["candidate"]
        acc = accuracy_score(df["label"], pred)
        mf1 = f1_score(df["label"], pred, average="macro")
        ok = (abs(acc - published["accuracy"]) < 1e-6
              and abs(mf1 - published["macro_f1"]) < 1e-6
              and len(df) == json.loads(COMPARISON.read_text())["total_test_windows"])
        results["reproduction"] = {"accuracy": acc, "macro_f1": mf1,
                                   "published_accuracy": published["accuracy"],
                                   "published_macro_f1": published["macro_f1"], "matches": bool(ok)}
        if not args.json:
            mark = "OK" if ok else "MISMATCH"
            print(f"reproduction check [{mark}]  accuracy={acc:.4f} "
                  f"(published {published['accuracy']:.4f})  macro-F1={mf1:.4f} "
                  f"(published {published['macro_f1']:.4f})  windows={len(df)}")
        if not ok:
            print("\nrefusing to report gated metrics: the evaluation no longer reproduces.")
            return 1

    stages = [
        ("1 raw argmax", (False, False, False)),
        ("2 + firmware confidence gate", (True, False, False)),
        ("3 + firmware SUDDEN debounce", (True, True, False)),
        ("4 + app GloveConfirmation", (True, True, True)),
    ]
    results["stages"] = evaluate(df, proba, classes, stages)
    results["per_event"] = {k: v for k, v in per_event(df, proba, classes).items() if k != "rows"}

    if args.json:
        print(json.dumps(results, indent=2))
        return 0

    print(f"\n{'pipeline stage':<32}{'FP':>5}{'FP rate':>10}{'as FALL':>9}{'FALL recall':>13}")
    print("-" * 69)
    for name, _ in stages:
        s = results["stages"][name]
        rate = f"{s['false_positive_rate']*100:.1f}%" if s["false_positive_rate"] is not None else "n/a"
        rec = f"{s['fall_recall']*100:.1f}%" if s["fall_recall"] is not None else "n/a"
        print(f"{name:<32}{s['false_positives']:>5}{rate:>10}{s['false_as_fall']:>9}{rec:>13}")

    pe = results["per_event"]
    print(f"\nper-event, all shipped gates applied:")
    print(f"  real falls detected              : {pe['falls_detected']}/{pe['total_falls']}")
    print(f"  NORMAL recordings raising alarms : {pe['normal_alarmed']}/{pe['total_normal']}")
    if pe["total_falls"] < 10 or pe["total_normal"] < 10:
        print("\n  NOTE: small sample -- these ratios carry wide confidence intervals")
        print("        and must not be quoted as a field false-positive rate.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
