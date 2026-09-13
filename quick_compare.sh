#!/bin/bash
# Run a short side-by-side comparison using the standard configurations.
#
#   bash quick_compare.sh
#   bash quick_compare.sh 15s
#
# This keeps the workflow fast while staying close to the project's intended
# comparison structure, but lowers the time and default repetition count.

LIMIT="${1:-15s}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RES="$PROJ/simulations/results"

pick() {   # pick <file> <scalar name>
    grep -m1 -E "[[:space:]]$2 " "$1" 2>/dev/null | awk '{print $NF}'
}

row() {   # row <label> <config>
    bash "$PROJ/run.sh" "$2" Cmdenv "$LIMIT" -r 0 > /dev/null 2>&1
    local f="$RES/$2-0.sca"
    [ -f "$f" ] || { printf "%-18s  (no results)\n" "$1"; return; }

    local rcvd
    rcvd=$(grep -m1 'victim.udpApp\[0\] rcvdPk:count' "$f" | awk '{print $NF}')
    printf "%-18s %12s %12s %8s %8s %8s %10s\n" \
        "$1" "${rcvd:-0}" \
        "$(pick "$f" framesDroppedByBlock)" \
        "$(pick "$f" truePositives)" \
        "$(pick "$f" falsePositives)" \
        "$(pick "$f" falseNegatives)" \
        "$(pick "$f" recall)"
}

printf "%-18s %12s %12s %8s %8s %8s %10s\n" \
       "config" "victim_rcvd" "blocked" "TP" "FP" "FN" "recall"
printf -- "---------------------------------------------------------------------\n"
row "No protection" NoProtection
row "DecisionTree" DecisionTree
row "KMeans" KMeans
row "Hybrid" Hybrid
row "CostRule" CostRule
