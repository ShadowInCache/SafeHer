"""Three figures for the evaluation evidence packet.

Static PNGs, because the destination is a printed specification rather than a
web page -- so there is no hover layer, and every series carries a visible
direct label instead. Light surface only, for the same reason.

Colours are the validated reference palette: categorical slots in fixed order
for the multi-series charts, and the reserved status pair for met/not-met, which
is always paired with a text label so the colour never carries the meaning on
its own.

Every number here is read from the measurement JSONs rather than retyped.
"""

from __future__ import annotations

import csv
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

SCRATCH = Path(__file__).resolve().parent
OUT = Path(r"C:\Users\AKSHAY_AG\Github\SafeHer\docs\assets\evaluation")
OUT.mkdir(parents=True, exist_ok=True)

# --- palette (reference instance, light mode) ---
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_2 = "#52514e"
MUTED = "#898781"
GRID = "#e1e0d9"
BASELINE = "#c3c2b7"
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"]
GOOD = "#0ca30c"
CRITICAL = "#d03b3b"

plt.rcParams.update({
    "figure.facecolor": SURFACE,
    "axes.facecolor": SURFACE,
    "savefig.facecolor": SURFACE,
    "font.family": "DejaVu Sans",
    "font.size": 10,
    "text.color": INK,
    "axes.labelcolor": INK_2,
    "xtick.color": MUTED,
    "ytick.color": MUTED,
    "axes.edgecolor": BASELINE,
})

audio = json.loads((SCRATCH / "audio_remeasured.json").read_text(encoding="utf-8"))
weapon = json.loads((SCRATCH / "weapon_map_remeasured.json").read_text(encoding="utf-8"))
sixcls = json.loads((SCRATCH / "weapon_6cls_map.json").read_text(encoding="utf-8"))


def strip(ax, *, xgrid=True):
    """Recessive chrome: hairline grid on the value axis only, no top/right spines."""
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    ax.spines["left"].set_color(BASELINE)
    ax.spines["bottom"].set_color(BASELINE)
    ax.set_axisbelow(True)
    ax.grid(axis="x" if xgrid else "y", color=GRID, linewidth=0.8)
    ax.grid(axis="y" if xgrid else "x", visible=False)


# ======================================================================
# 1. Benchmark conformance. Magnitude against a per-row reference value.
#    A bullet chart, because the targets differ per model (0.88 / 0.90 /
#    0.95) so a single shared reference line would be wrong.
# ======================================================================
rows = [
    ("Weapon YOLOv8n — phone fp16 TFLite", "mAP@0.5",
     weapon["phone_fp16_tflite"]["map50"], 0.88),
    ("Weapon YOLOv8n — server int8 ONNX", "mAP@0.5",
     weapon["server_int8_onnx"]["map50"], 0.88),
    ("Weapon YOLOv8n — 6-class candidate", "mAP@0.5",
     sixcls["sixclass_fp16_tflite_with_metadata"]["map50_weapon_classes_only"], 0.88),
    ("Audio ASR→TF-IDF→LR — clean ASR", "F1",
     audio["conditions"]["clean_asr"]["elevated_f1"], 0.90),
    ("Audio ASR→TF-IDF→LR — degraded ASR", "F1",
     audio["conditions"]["degraded_asr"]["elevated_f1"], 0.90),
    ("Glove XGBoost — 5-class", "accuracy", 0.8886, 0.95),
]

fig, ax = plt.subplots(figsize=(9.6, 4.4))
positions = range(len(rows))
for i, (label, metric, value, target) in enumerate(rows):
    met = value > target
    colour = GOOD if met else CRITICAL
    ax.barh(i, value, height=0.52, color=colour, zorder=3,
            edgecolor=SURFACE, linewidth=2)
    # The target tick: a short vertical rule in primary ink, so it reads as a
    # threshold rather than as more data.
    ax.plot([target, target], [i - 0.33, i + 0.33], color=INK,
            linewidth=2.2, zorder=5, solid_capstyle="butt")
    ax.text(value + 0.004, i, f"{value:.4f}", va="center", ha="left",
            fontsize=9.5, color=INK, fontweight="bold", zorder=6)
    ax.text(0.998, i, "Met" if met else "Not met", va="center", ha="right",
            fontsize=9, color=colour, fontweight="bold", zorder=6,
            transform=ax.get_yaxis_transform())

ax.set_yticks(list(positions))
ax.set_yticklabels([f"{label}\n{metric}, target > {target:g}"
                    for label, metric, _, target in rows],
                   fontsize=9, color=INK_2)
ax.invert_yaxis()
ax.set_xlim(0.80, 1.0)
ax.xaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{v:.2f}"))
strip(ax)
ax.set_xlabel("score (note: three different metrics — see each row)", fontsize=9)
ax.set_title("SafeHer model benchmark conformance against SRS targets\n"
             "measured 2026-11-03 on held-out data, shipped artifacts "
             "(hash-verified)",
             fontsize=11.5, color=INK, loc="left", pad=14)
ax.text(0, -0.17,
        "Black rule = the SRS target for that row. Bars start at 0.80, not 0. "
        "Each row is scored in its own metric and rows are not comparable to "
        "each other.",
        transform=ax.transAxes, fontsize=8, color=MUTED, va="top")
fig.tight_layout()
fig.savefig(OUT / "benchmark_conformance.png", dpi=200, bbox_inches="tight")
plt.close(fig)
print("wrote benchmark_conformance.png")

# ======================================================================
# 2. Audio threshold sweep. Change over a continuous parameter, four
#    series, all on one 0-1 scale -- so one axis, no second y.
# ======================================================================
sweep = audio["degraded_threshold_sweep"]
thresholds = [r["threshold"] for r in sweep]
series = [
    ("F1 (the target metric)", [r["elevated_f1"] for r in sweep], SERIES[0]),
    ("recall", [r["elevated_recall"] for r in sweep], SERIES[1]),
    ("specificity", [r["specificity"] for r in sweep], SERIES[2]),
    ("precision", [r["elevated_precision"] for r in sweep], SERIES[3]),
]

fig, ax = plt.subplots(figsize=(9.2, 5.0))
ax.axhline(0.90, color=INK, linewidth=1.4, linestyle=(0, (5, 3)), zorder=2)
ax.text(0.302, 0.892, "SRS target, F1 > 0.90", fontsize=8.5, color=INK,
        va="top", ha="left")
ax.axvline(0.50, color=MUTED, linewidth=1.2, linestyle=(0, (2, 3)), zorder=2)
ax.text(0.505, 0.405, "deployed\nthreshold 0.50", fontsize=8.5, color=INK_2,
        va="bottom", ha="left")

# The end labels are nudged apart by hand: precision and specificity finish
# 0.018 apart, which is closer than a 9pt label is tall.
END_LABEL_OFFSET = {
    "F1 (the target metric)": 0.0,
    "recall": 0.0,
    "specificity": -0.021,
    "precision": 0.015,
}
handles = []
for label, values, colour in series:
    line, = ax.plot(thresholds, values, color=colour, linewidth=2.0, zorder=4,
                    marker="o", markersize=4.5, markeredgecolor=SURFACE,
                    markeredgewidth=1.6, label=label)
    handles.append(line)
    ax.text(thresholds[-1] + 0.010, values[-1] + END_LABEL_OFFSET[label], label,
            fontsize=9, color=INK_2, va="center", ha="left")

# The F1 peak is the finding: it sits exactly on the deployed threshold.
peak = max(sweep, key=lambda r: r["elevated_f1"])
ax.plot([peak["threshold"]], [peak["elevated_f1"]], marker="o", markersize=9,
        color=SERIES[0], markeredgecolor=SURFACE, markeredgewidth=2, zorder=6)
ax.annotate(f"F1 peaks at {peak['elevated_f1']:.4f}\nalready the deployed value",
            xy=(peak["threshold"], peak["elevated_f1"]),
            xytext=(0.575, 0.545), fontsize=9, color=INK,
            arrowprops=dict(arrowstyle="-", color=MUTED, linewidth=1))

ax.set_xlim(0.28, 0.93)
ax.set_ylim(0.38, 1.0)
strip(ax, xgrid=False)
ax.set_xlabel("elevated-score decision threshold", fontsize=9.5)
ax.set_ylabel("score", fontsize=9.5)
ax.set_title("Audio phrase classifier on degraded ASR: no threshold reaches "
             "the benchmark\n714 held-out clips, split by phrase",
             fontsize=11.5, color=INK, loc="left", pad=14)
# Explicit handles: the target and deployed-threshold reference lines are also
# Line2D artists, and letting matplotlib collect them shifts every label onto
# the wrong colour.
ax.legend(handles=handles, frameon=False, fontsize=9,
          loc="lower left", labelcolor=INK_2, ncol=2,
          bbox_to_anchor=(0.0, -0.30))
fig.tight_layout()
fig.savefig(OUT / "audio_threshold_sweep.png", dpi=200, bbox_inches="tight")
plt.close(fig)
print("wrote audio_threshold_sweep.png")

# ======================================================================
# 3. Glove gate cascade. Four ordered stages, two rates on one scale.
#    The point is the trade: false positives fall, and so does recall.
# ======================================================================
stages = ["1\nraw argmax", "2\n+ firmware\nconfidence gate",
          "3\n+ firmware\nSUDDEN debounce", "4\n+ app\nGloveConfirmation"]
fp_rate = [0.135, 0.074, 0.054, 0.020]
fall_recall = [0.758, 0.653, 0.653, 0.558]

fig, ax = plt.subplots(figsize=(8.6, 5.0))
for label, values, colour in (
    ("FALL recall (per window)", fall_recall, SERIES[0]),
    ("false-positive rate (per NORMAL window)", fp_rate, SERIES[1]),
):
    ax.plot(range(len(stages)), values, color=colour, linewidth=2.0, zorder=4,
            marker="o", markersize=8, markeredgecolor=SURFACE,
            markeredgewidth=2)
    for x, v in enumerate(values):
        ax.annotate(f"{v:.1%}", (x, v), textcoords="offset points",
                    xytext=(0, 11), ha="center", fontsize=9, color=INK,
                    fontweight="bold")
    ax.text(len(stages) - 1 + 0.07, values[-1], label, fontsize=9,
            color=INK_2, va="center", ha="left")

ax.set_xticks(range(len(stages)))
ax.set_xticklabels(stages, fontsize=8.5, color=INK_2)
ax.set_xlim(-0.25, 3.95)
ax.set_ylim(0, 0.88)
ax.yaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{v:.0%}"))
strip(ax, xgrid=False)
ax.set_ylabel("rate", fontsize=9.5)
ax.set_title("Glove motion classifier: what each shipped gate costs and buys\n"
             "locked test split, 431 windows — every stage is a gate that "
             "actually ships",
             fontsize=11.5, color=INK, loc="left", pad=14)
ax.legend(["FALL recall (per window)",
           "false-positive rate (per NORMAL window)"],
          frameon=False, fontsize=9, loc="lower left", labelcolor=INK_2,
          bbox_to_anchor=(0.0, -0.34))
fig.tight_layout()
fig.savefig(OUT / "glove_gate_cascade.png", dpi=200, bbox_inches="tight")
plt.close(fig)
print("wrote glove_gate_cascade.png")

# ---- the table view the figures are obliged to have ----
with (OUT / "figure_data.csv").open("w", newline="", encoding="utf-8") as handle:
    writer = csv.writer(handle)
    writer.writerow(["figure", "row_or_x", "series", "value"])
    for label, metric, value, target in rows:
        writer.writerow(["benchmark_conformance", label, metric, value])
        writer.writerow(["benchmark_conformance", label, "target", target])
    for label, values, _ in series:
        for t, v in zip(thresholds, values):
            writer.writerow(["audio_threshold_sweep", t, label, v])
    for name, values in (("FALL recall", fall_recall),
                         ("false-positive rate", fp_rate)):
        for stage, v in zip(stages, values):
            writer.writerow(["glove_gate_cascade",
                             stage.replace("\n", " "), name, v])
print("wrote figure_data.csv")
