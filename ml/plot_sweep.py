"""Plot detection quality against attack intensity.

    python plot_sweep.py ../results/sweep.csv

Both models are trained once, on the loudest attack. Every quieter point is an
attack they have never met, so the curve shows where each approach stops
working rather than how well it memorised its training set.
"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

SERIES = {"DecisionTree": "#2a78d6", "KMeans": "#eb6834"}
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_SECOND = "#52514e"
INK_MUTED = "#898781"
GRID = "#e1e0d9"
AXIS = "#c3c2b7"

plt.rcParams.update({
    "font.family": ["Segoe UI", "DejaVu Sans", "sans-serif"],
    "figure.facecolor": SURFACE,
    "axes.facecolor": SURFACE,
    "axes.edgecolor": AXIS,
    "axes.labelcolor": INK_SECOND,
    "text.color": INK,
    "xtick.color": INK_MUTED,
    "ytick.color": INK_MUTED,
    "axes.spines.top": False,
    "axes.spines.right": False,
})

# The interval the models were trained at; everything else is a fraction of it.
TRAINED_INTERVAL = 0.0008
LABELS = {1.0: "1x\n(trained)", 0.2: "1/5", 0.1: "1/10",
          0.04: "1/25", 0.02: "1/50"}


def style_axes(ax):
    ax.set_axisbelow(True)
    ax.yaxis.grid(True, color=GRID, linewidth=1)
    ax.xaxis.grid(False)
    ax.spines["left"].set_color(AXIS)
    ax.spines["bottom"].set_color(AXIS)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "../results/sweep.csv"
    df = pd.read_csv(path)
    outdir = os.path.dirname(os.path.abspath(path))

    df["rel"] = (TRAINED_INTERVAL / df["interval"]).round(4)
    levels = sorted(df["rel"].unique(), reverse=True)   # loudest first

    print(df.groupby(["detector", "rel"])[["recall", "fp", "victim_rcvd"]]
            .mean().round(3).to_string(), "\n")

    fig, ax = plt.subplots(figsize=(7.6, 4.6))
    xs = range(len(levels))

    for name, color in SERIES.items():
        means, errs = [], []
        for lv in levels:
            s = df[(df.detector == name) & (df.rel == lv)]["recall"].dropna()
            means.append(s.mean() if len(s) else 0.0)
            errs.append(s.std() if len(s) > 1 else 0.0)
        ax.errorbar(xs, means, yerr=errs, label=name, color=color,
                    linewidth=2, marker="o", markersize=8,
                    markeredgecolor=SURFACE, markeredgewidth=1.5,
                    capsize=3, ecolor=INK_MUTED, elinewidth=1)
        # Label the endpoints only - a number on every point is noise.
        # Offset by where the point sits, not by which series it belongs to:
        # a value at zero labelled downwards lands on top of the axis.
        for i in (0, len(levels) - 1):
            below = means[i] > 0.5 and name == "DecisionTree"
            ax.annotate(f"{means[i]:.2f}", (i, means[i]),
                        textcoords="offset points",
                        xytext=(0, -18 if below else 12),
                        ha="center", fontsize=9, color=INK_SECOND)

    ax.set_xticks(list(xs))
    ax.set_xticklabels([LABELS.get(lv, f"{lv:g}x") for lv in levels], fontsize=10)
    ax.set_xlabel("Attack rate, as a fraction of the rate the models were trained on")
    ax.set_ylabel("Recall  (share of attack flows caught)")
    ax.set_ylim(-0.08, 1.15)
    ax.set_yticks([0, 0.25, 0.5, 0.75, 1.0])
    ax.set_title("Where the supervised model stops working",
                 fontsize=12, color=INK, loc="left", pad=34)
    ax.legend(frameon=False, fontsize=10, ncol=2,
              loc="lower left", bbox_to_anchor=(0, 1.005))
    style_axes(ax)
    fig.tight_layout()

    out = os.path.join(outdir, "recall_vs_intensity.png")
    fig.savefig(out, dpi=200)
    print("wrote", out)


if __name__ == "__main__":
    main()
