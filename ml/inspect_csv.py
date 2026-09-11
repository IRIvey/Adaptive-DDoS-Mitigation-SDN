"""Summarise a flow dataset per class.

Run this on every freshly collected dataset before training anything. It is
how you catch a feature that carries no information - a column with the same
value in both classes cannot help, and a column that separates them perfectly
usually means the traffic model is too clean to be interesting.

    python inspect_csv.py ../data/flows_sim.csv
"""
import sys

import pandas as pd

from schema import FEATURES, LABEL


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "../data/flows_sim.csv"
    df = pd.read_csv(path)

    n_norm = int((df[LABEL] == 0).sum())
    n_atk = int((df[LABEL] == 1).sum())
    print(f"{path}: {len(df)} rows  ({n_norm} normal, {n_atk} attack)\n")

    if n_norm == 0 or n_atk == 0:
        print("!! only one class present - nothing can be learned from this")
        return

    hdr = f"{'feature':<16}{'normal mean':>14}{'attack mean':>14}" \
          f"{'normal range':>22}{'attack range':>22}"
    print(hdr)
    print("-" * len(hdr))

    dead = []
    for f in FEATURES:
        a = df.loc[df[LABEL] == 0, f]
        b = df.loc[df[LABEL] == 1, f]
        print(f"{f:<16}{a.mean():>14.2f}{b.mean():>14.2f}"
              f"{f'[{a.min():.2f}, {a.max():.2f}]':>22}"
              f"{f'[{b.min():.2f}, {b.max():.2f}]':>22}")
        if df[f].nunique() <= 1:
            dead.append(f)

    if dead:
        print(f"\n!! constant across the whole dataset, so useless: "
              f"{', '.join(dead)}")
        print("   fix the traffic model rather than dropping the feature.")
    else:
        print("\nevery feature varies - none is dead weight")


if __name__ == "__main__":
    main()
