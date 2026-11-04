"""Re-measure the shipped ASR -> TF-IDF -> LR phrase classifier against the SRS target.

The SRS fixes the benchmark for the voice path in section 6.1 as F1 > 0.90.
The published evaluation reported accuracy, recall, precision and specificity
but never an F1, so the one number the benchmark is actually stated in has not
been computed from these bytes. That is what this adds.

Nothing here re-implements the model. `classify` is imported from
verify_shipped_json.py, the harness that already proved the shipped JSON
reproduces the training figures, so this measures the same code path on the
same split and only derives further metrics from it. Re-implementing the
feature extraction would risk measuring my transcription of the model rather
than the model.

Both conditions are reported because they answer different questions: clean ASR
is the ceiling, degraded ASR is what a phone in a noisy street actually feeds
the classifier. The project has already recorded degraded as the realistic one.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

SCRIPTS = Path(r"D:\SafeHer-ML\audio_threat\scripts")
RUNS = Path(r"D:\SafeHer-ML\audio_threat\runs")
SHIPPED = Path(r"C:\Users\AKSHAY_AG\Github\SafeHer\mobile\assets\models\phrase_classifier.json")
OUT = Path(__file__).resolve().parent

sys.path.insert(0, str(SCRIPTS))

from compare_matchers import phrase_split, slug  # noqa: E402
from verify_shipped_json import ELEVATED, classify  # noqa: E402

SRS_TARGET_F1 = 0.90
THRESHOLD = 0.5  # AudioThreatReading.isElevated / CameraActivationPolicy.audioScore

CONDITIONS = {
    "clean_asr": RUNS / "transcripts.json",
    "degraded_asr": RUNS / "transcripts_degraded.json",
}


def held_out_rows(path: Path) -> list[dict]:
    rows = json.loads(path.read_text(encoding="utf-8"))
    _, test_phrases = phrase_split()
    test_slugs = {slug(p) for items in test_phrases.values() for p in items}
    return [r for r in rows if r["phrase_slug"] in test_slugs]


def evaluate(model: dict, rows: list[dict], threshold: float) -> dict:
    tp = fn = tn = fp = 0
    three_class_correct = 0
    confusion: Counter = Counter()

    for row in rows:
        label, elevated = classify(model, row["transcript"])
        predicted = elevated >= threshold
        actual = row["label"] in ELEVATED
        if label == row["label"]:
            three_class_correct += 1
        confusion[(row["label"], label)] += 1
        if actual and predicted:
            tp += 1
        elif actual:
            fn += 1
        elif predicted:
            fp += 1
        else:
            tn += 1

    total = len(rows)
    # Precision/recall are stated for the ELEVATED class, because that is the
    # class whose errors matter: a missed elevated clip is a missed emergency.
    precision = tp / max(tp + fp, 1)
    recall = tp / max(tp + fn, 1)
    f1 = 2 * precision * recall / max(precision + recall, 1e-12)

    # The normal class gets its own F1 so the macro average below is not just
    # the elevated figure wearing a different label.
    normal_precision = tn / max(tn + fn, 1)
    normal_recall = tn / max(tn + fp, 1)
    normal_f1 = (
        2 * normal_precision * normal_recall / max(normal_precision + normal_recall, 1e-12)
    )

    return {
        "clips": total,
        "threshold": threshold,
        "counts": {"tp": tp, "fp": fp, "tn": tn, "fn": fn},
        "accuracy": round((tp + tn) / max(total, 1), 4),
        "elevated_precision": round(precision, 4),
        "elevated_recall": round(recall, 4),
        "elevated_f1": round(f1, 4),
        "normal_precision": round(normal_precision, 4),
        "normal_recall": round(normal_recall, 4),
        "normal_f1": round(normal_f1, 4),
        "macro_f1_binary": round((f1 + normal_f1) / 2, 4),
        "specificity": round(tn / max(tn + fp, 1), 4),
        "three_class_accuracy": round(three_class_correct / max(total, 1), 4),
        "missed_elevated": f"{fn}/{tp + fn}",
        "false_alarms_on_normal": f"{fp}/{tn + fp}",
        "srs_target_f1": SRS_TARGET_F1,
        "meets_srs_target_on_elevated_f1": f1 > SRS_TARGET_F1,
        "confusion": {f"{t}->{p}": n for (t, p), n in sorted(confusion.items())},
    }


def main() -> None:
    model = json.loads(SHIPPED.read_text(encoding="utf-8"))
    print(f"artifact : {SHIPPED}")
    print(f"size     : {SHIPPED.stat().st_size} bytes")
    print(f"classes  : {model['classes']}")
    print(f"features : {model['n_features']}\n")

    results = {"artifact": str(SHIPPED), "conditions": {}}
    for name, path in CONDITIONS.items():
        rows = held_out_rows(path)
        got = evaluate(model, rows, THRESHOLD)
        results["conditions"][name] = got
        print("=" * 70)
        print(f"{name}  ({got['clips']} held-out clips)")
        print("=" * 70)
        print(f"  accuracy             {got['accuracy']}")
        print(f"  elevated precision   {got['elevated_precision']}")
        print(f"  elevated recall      {got['elevated_recall']}")
        print(f"  elevated F1          {got['elevated_f1']}   "
              f"target > {SRS_TARGET_F1} -> "
              f"{'MET' if got['meets_srs_target_on_elevated_f1'] else 'NOT MET'}")
        print(f"  macro F1 (binary)    {got['macro_f1_binary']}")
        print(f"  specificity          {got['specificity']}")
        print(f"  three-class accuracy {got['three_class_accuracy']}")
        print(f"  missed elevated      {got['missed_elevated']}")
        print(f"  false alarms         {got['false_alarms_on_normal']}\n")

    # A threshold sweep on the realistic condition, so the question "could the
    # target be reached by moving the constant instead of retraining" is
    # answered with numbers rather than left open.
    print("=" * 70)
    print("threshold sweep on degraded ASR (elevated F1 is the target metric)")
    print("=" * 70)
    sweep = []
    rows = held_out_rows(CONDITIONS["degraded_asr"])
    for t in (0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8):
        got = evaluate(model, rows, t)
        sweep.append({k: got[k] for k in (
            "threshold", "accuracy", "elevated_precision", "elevated_recall",
            "elevated_f1", "specificity",
        )})
        marker = "  <- deployed" if t == THRESHOLD else ""
        print(f"  t={t:<5} acc {got['accuracy']:.4f}  P {got['elevated_precision']:.4f}  "
              f"R {got['elevated_recall']:.4f}  F1 {got['elevated_f1']:.4f}  "
              f"spec {got['specificity']:.4f}{marker}")
    results["degraded_threshold_sweep"] = sweep
    best = max(sweep, key=lambda r: r["elevated_f1"])
    print(f"\n  best F1 in sweep: {best['elevated_f1']} at t={best['threshold']}  "
          f"target > {SRS_TARGET_F1} -> "
          f"{'MET' if best['elevated_f1'] > SRS_TARGET_F1 else 'NOT MET'}")
    results["best_degraded_f1_over_threshold"] = best

    (OUT / "audio_remeasured.json").write_text(
        json.dumps(results, indent=2), encoding="utf-8"
    )
    print("\nwrote audio_remeasured.json")


if __name__ == "__main__":
    main()
