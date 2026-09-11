"""Plot the experiment results.

    python plot_results.py ../results/experiments.csv

Produces two figures in ../results/:
    recall_by_attack.png    - the headline comparison
    traffic_reaching_victim.png

Bars are means over the repetitions with standard-deviation whiskers; a single
run of a randomised simulation is an anecdote, not a measurement.
"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

# --- design tokens -------------------------------------------------------
# Categorical slots 1 and 2 of the validated default palette. The pair clears
# the CVD and normal-vision floors on this surface; the third slot (aqua) was
# dropped because it sits under 3:1 contrast on a light background.
SERIES = {"DecisionTree": "#2a78d6", "KMeans": "#eb6834"}
BASELINE = "#898781"        # no protection: a reference, not a series
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

ATTACKS = ["full-rate", "low-rate"]
ATTACK_LABEL = {
    "full-rate": "Full-rate flood\n(seen in training)",
    "low-rate": "Low-rate flood\n(never seen in training)",
}


def style_axes(ax):
    ax.set_axisbelow(True)
    ax.yaxis.grid(True, color=GRID, linewidth=1)
    ax.xaxis.grid(False)
    ax.spines["left"].set_color(AXIS)
    ax.spines["bottom"].set_color(AXIS)


def bar_labels(ax, bars, errs=None, fmt="{:.2f}"):
    """Direct labels on every bar - identity never rests on color alone.

    Labels clear the error-bar cap, not just the bar top; anchoring to the bar
    height alone puts the text straight through the whisker.
    """
    for i, b in enumerate(bars):
        h = b.get_height()
        top = h + (errs[i] if errs else 0.0)
        ax.annotate(fmt.format(h),
                    (b.get_x() + b.get_width() / 2, top),
                    textcoords="offset points", xytext=(0, 5),
                    ha="center", va="bottom", fontsize=9, color=INK_SECOND)


def plot_recall(df, out):
    fig, ax = plt.subplots(figsize=(7.2, 4.4))
    width = 0.34

    for i, (name, color) in enumerate(SERIES.items()):
        means, errs = [], []
        for atk in ATTACKS:
            s = df[(df.attack == atk) & (df.detector == name)]["recall"].dropna()
            means.append(s.mean() if len(s) else 0.0)
            errs.append(s.std() if len(s) > 1 else 0.0)
        # 2px visual gap between adjacent bars
        xs = [x + (i - 0.5) * (width + 0.02) for x in range(len(ATTACKS))]
        bars = ax.bar(xs, means, width, label=name, color=color,
                      yerr=errs, capsize=3,
                      error_kw={"ecolor": INK_MUTED, "elinewidth": 1})
        bar_labels(ax, bars, errs)

    ax.set_xticks(range(len(ATTACKS)))
    ax.set_xticklabels([ATTACK_LABEL[a] for a in ATTACKS], fontsize=10)
    ax.set_ylabel("Recall  (share of attack flows caught)")
    ax.set_ylim(0, 1.12)
    ax.set_yticks([0, 0.25, 0.5, 0.75, 1.0])
    ax.set_title("The supervised model does not survive an attack it was not "
                 "trained on",
                 fontsize=12, color=INK, loc="left", pad=34)
    # Legend above the plot: inside it, the upper right sits directly on top of
    # the low-rate K-Means bar.
    ax.legend(frameon=False, fontsize=10, ncol=2,
              loc="lower left", bbox_to_anchor=(0, 1.005))
    style_axes(ax)
    fig.tight_layout()
    fig.savefig(out, dpi=200)
    print("wrote", out)


def plot_traffic(df, out):
    fig, ax = plt.subplots(figsize=(7.2, 4.4))
    width = 0.26
    groups = [("no protection", BASELINE, "none")] + \
             [(n, c, n) for n, c in SERIES.items()]

    for i, (label, color, det) in enumerate(groups):
        means, errs = [], []
        for atk in ATTACKS:
            s = df[(df.attack == atk) & (df.detector == det)]["victim_rcvd"].dropna()
            means.append(s.mean() if len(s) else 0.0)
            errs.append(s.std() if len(s) > 1 else 0.0)
        xs = [x + (i - 1) * (width + 0.02) for x in range(len(ATTACKS))]
        bars = ax.bar(xs, means, width, label=label, color=color,
                      yerr=errs, capsize=3,
                      error_kw={"ecolor": INK_MUTED, "elinewidth": 1})
        bar_labels(ax, bars, errs, fmt="{:,.0f}")

    ax.set_xticks(range(len(ATTACKS)))
    ax.set_xticklabels([ATTACK_LABEL[a] for a in ATTACKS], fontsize=10)
    ax.set_ylabel("Packets reaching the victim's targeted port")
    ax.set_ylim(0, 118000)
    ax.set_title("Traffic that still gets through", fontsize=12, color=INK,
                 loc="left", pad=34)
    ax.legend(frameon=False, fontsize=10, ncol=3,
              loc="lower left", bbox_to_anchor=(0, 1.005))
    style_axes(ax)
    fig.tight_layout()
    fig.savefig(out, dpi=200)
    print("wrote", out)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "../results/experiments.csv"
    df = pd.read_csv(path)
    outdir = os.path.dirname(os.path.abspath(path))

    reps = df.groupby(["attack", "detector"]).size().max()
    print(f"{len(df)} rows, up to {reps} repetitions per configuration\n")

    summary = (df.groupby(["attack", "detector"])
                 [["victim_rcvd", "blocked", "tp", "fp", "fn", "recall"]]
                 .mean(numeric_only=True).round(2))
    print(summary.to_string(), "\n")

    plot_recall(df, os.path.join(outdir, "recall_by_attack.png"))
    plot_traffic(df, os.path.join(outdir, "traffic_reaching_victim.png"))


if __name__ == "__main__":
    main()
