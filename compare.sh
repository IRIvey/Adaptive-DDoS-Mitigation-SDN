#!/bin/bash
# Run the experiment configurations and print the numbers side by side.
#
#   bash compare.sh [seconds]
#
# The low-rate rows are the interesting ones: the models are trained on the
# full-rate flood only, so those columns show how each approach copes with an
# attack it never saw.
#
LIMIT="${1:-60s}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RES="$PROJ/simulations/results"

pick() {   # pick <file> <scalar name>
    grep -m1 -E "[[:space:]]$2 " "$1" 2>/dev/null | awk '{print $NF}'
}

row() {    # row <label> <config>
    bash "$PROJ/run.sh" "$2" Cmdenv "$LIMIT" > /dev/null 2>&1
    local f="$RES/$2-0.sca"
    [ -f "$f" ] || { printf "%-22s  (no results)\n" "$1"; return; }

    local rcvd
    rcvd=$(grep -m1 'victim.udpApp\[0\] rcvdPk:count' "$f" | awk '{print $NF}')
    printf "%-22s %12s %12s %8s %8s %8s %10s\n" \
        "$1" "${rcvd:-0}" \
        "$(pick "$f" framesDroppedByBlock)" \
        "$(pick "$f" truePositives)" \
        "$(pick "$f" falsePositives)" \
        "$(pick "$f" falseNegatives)" \
        "$(pick "$f" recall)"
}

printf "%-22s %12s %12s %8s %8s %8s %10s\n" \
       CONFIG "flood rcvd" "blocked" TP FP FN recall
printf -- "--------------------------------------------------------------------------------------\n"

echo "-- full-rate attack (what the models were trained on) --"
row "no protection"      NoProtection
row "Decision Tree"      DecisionTree
row "K-Means"            KMeans

echo "-- low-rate attack (never seen in training) --"
row "no protection"      LowRateFlood
row "Decision Tree"      LowRate_DT
row "K-Means"            LowRate_KMeans
