"""Plot the false-positive / recall frontier the hybrid's patience traces out.

    python plot_frontier.py

Reads results/sweep_confirmations.csv for the frontier and results/experiments.csv
for the reference detectors, all on the low-rate attack.

Both axes are real quantities, so this is a connected scatter rather than bars:
each point is one setting of `confirmations`, and the line is the path between
"catches everything, some false alarms" and "never wrong, misses more".
"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

HYBRID = "#1baf7a"
DT = "#2a78d6"
KM = "#eb6834"
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_SECOND = "#52514e"
INK_MUTED = "#898781"
GRID = "#e1e0d9"
AXIS = "#c3c2b7"

plt.rcParams.update({
    "font.family": ["Segoe UI", "DejaVu Sans", "sans-serif"],
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE,
    "axes.edgecolor": AXIS, "axes.labelcolor": INK_SECOND, "text.color": INK,
    "xtick.color": INK_MUTED, "ytick.color": INK_MUTED,
    "axes.spines.top": False, "axes.spines.right": False,
})


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    res = os.path.join(here, "..", "results")
    sweep = pd.read_csv(os.path.join(res, "sweep_confirmations.csv"))

    g = (sweep.groupby("confirmations")[["fp", "recall", "victim_rcvd"]]
              .mean().reset_index().sort_values("confirmations"))
    print("hybrid, by patience:")
    print(g.round(2).to_string(index=False), "\n")

    fig, ax = plt.subplots(figsize=(7.6, 4.8))

    ax.plot(g["fp"], g["recall"], color=HYBRID, linewidth=2, marker="o",
            markersize=9, markeredgecolor=SURFACE, markeredgewidth=1.5,
            label="Hybrid (by patience)", zorder=3)
    for _, row in g.iterrows():
        ax.annotate(f"{int(row['confirmations'])}",
                    (row["fp"], row["recall"]), textcoords="offset points",
                    xytext=(10, -4), fontsize=9.5, color=INK_SECOND, zorder=4)

    # The cost rule traces its own frontier as the false-block penalty varies.
    # Drawn in ink with diamond markers rather than a fourth hue: the palette
    # only validates three categorical colours for a scatter, and shape plus a
    # direct label carries the distinction safely.
    cost_path = os.path.join(res, "sweep_cost.csv")
    if os.path.exists(cost_path):
        c = pd.read_csv(cost_path)
        cg = (c.groupby("cost")[["fp", "recall", "victim_rcvd"]]
                .mean().reset_index().sort_values("cost"))
        print("cost rule, by false-block penalty:")
        print(cg.round(2).to_string(index=False), "\n")
        ax.plot(cg["fp"], cg["recall"], color=INK, linewidth=1.6, marker="D",
                markersize=7, markeredgecolor=SURFACE, markeredgewidth=1.5,
                linestyle="--", label="Cost rule (by penalty)", zorder=3)
        for _, row in cg.iterrows():
            ax.annotate(f"{int(row['cost']) // 1000}k",
                        (row["fp"], row["recall"]), textcoords="offset points",
                        xytext=(8, 7), fontsize=9, color=INK_SECOND, zorder=4)

    # Reference detectors on the same attack, from the main experiment.
    exp_path = os.path.join(res, "experiments.csv")
    if os.path.exists(exp_path):
        exp = pd.read_csv(exp_path)
        low = exp[exp.attack == "low-rate"]
        for det, color, marker in (("DecisionTree", DT, "^"),
                                   ("KMeans", KM, "s")):
            s = low[low.detector == det]
            if s.empty:
                continue
            x, y = s["fp"].mean(), s["recall"].mean()
            ax.plot([x], [y], marker=marker, markersize=9, color=color,
                    markeredgecolor=SURFACE, markeredgewidth=1.5,
                    linestyle="none", label=det, zorder=5)

    ax.set_xlabel("False positives per run  (legitimate flows blocked)")
    ax.set_ylabel("Recall  (share of attack flows caught)")
    ax.set_ylim(-0.08, 1.12)
    ax.set_title("Two ways to trade false alarms against detection "
                 "(low-rate attack)",
                 fontsize=12, color=INK, loc="left", pad=34)
    ax.legend(frameon=False, fontsize=9.5, ncol=4,
              loc="lower left", bbox_to_anchor=(0, 1.005))
    ax.set_axisbelow(True)
    ax.yaxis.grid(True, color=GRID, linewidth=1)
    ax.xaxis.grid(True, color=GRID, linewidth=1)
    ax.spines["left"].set_color(AXIS)
    ax.spines["bottom"].set_color(AXIS)

    fig.tight_layout()
    out = os.path.join(res, "frontier.png")
    fig.savefig(out, dpi=200)
    print("wrote", out)


if __name__ == "__main__":
    main()
