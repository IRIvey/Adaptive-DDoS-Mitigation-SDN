#!/bin/bash
# One-command smoke test for the working DecisionTree setup.
#
#   bash run_fast.sh
#   bash run_fast.sh 25s
#
# Defaults are intentionally short and safe: one repetition, CMdenv, and the
# DecisionTree configuration used for quick validation without disturbing the
# project's main experiment settings.

LIMIT="${1:-25s}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RES="$PROJ/simulations/results"
mkdir -p "$RES"

pick() {   # pick <file> <scalar name>
    grep -m1 -E "[[:space:]]$2 " "$1" 2>/dev/null | awk '{print $NF}'
}

bash "$PROJ/run.sh" DecisionTree Cmdenv "$LIMIT" -r 0 > /dev/null 2>&1

FILE="$RES/DecisionTree-0.sca"
if [ ! -f "$FILE" ]; then
    echo "No simulation results were produced for DecisionTree in $LIMIT." >&2
    exit 1
fi

rcvd=$(grep -m1 'victim.udpApp\[0\] rcvdPk:count' "$FILE" | awk '{print $NF}')
blocked=$(pick "$FILE" framesDroppedByBlock)
tp=$(pick "$FILE" truePositives)
fp=$(pick "$FILE" falsePositives)

printf "config: DecisionTree\n"
printf "mode: Cmdenv\n"
printf "sim-time-limit: %s\n" "$LIMIT"
printf "victim received: %s\n" "${rcvd:-0}"
printf "blocked: %s\n" "${blocked:-0}"
printf "TP: %s\n" "${tp:-0}"
printf "FP: %s\n" "${fp:-0}"

ln -sfn "$RES" "$PROJ/results/latest"
printf "results: %s\n" "$PROJ/results/latest"
