#!/bin/bash
# Sweep one ini iteration variable and collect every run.
#
#   bash sweep_param.sh <config> <itervar> <output.csv> [seconds]
#
# Examples:
#   bash sweep_param.sh Sweep_Confirmations conf results/sweep_confirmations.csv
#   bash sweep_param.sh Sweep_Cost          cost results/sweep_cost.csv
#
# The iteration variable is read back out of each result file, so every row
# carries the value it actually ran with rather than one inferred from order.
#
CFG="${1:?config name required}"
VAR="${2:?iteration variable name required}"
OUTREL="${3:?output csv path required}"
LIMIT="${4:-60s}"

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RES="$PROJ/simulations/results"
OUT="$PROJ/$OUTREL"
mkdir -p "$(dirname "$OUT")"

pick() { grep -m1 -E "[[:space:]]$2 " "$1" 2>/dev/null | awk '{print $NF}'; }

n=$(bash "$PROJ/run.sh" "$CFG" Cmdenv "$LIMIT" -q numruns 2>/dev/null \
    | grep -oE '^Number of runs: [0-9]+' | grep -oE '[0-9]+$')
n="${n:-20}"
echo "$CFG expands to $n runs" >&2

echo "$VAR,rep,tp,fp,tn,fn,recall,precision,fpr,detection_latency,victim_rcvd,blocked" > "$OUT"

for r in $(seq 0 $((n - 1))); do
    bash "$PROJ/run.sh" "$CFG" Cmdenv "$LIMIT" -r "$r" > /dev/null 2>&1
    f="$RES/$CFG-$r.sca"
    [ -f "$f" ] || { echo "  !! missing run $r" >&2; continue; }

    val=$(grep -m1 "^itervar $VAR " "$f" | awk '{print $3}' | tr -d '"')
    rep=$(grep -m1 '^attr repetition ' "$f" | awk '{print $3}' | tr -d '"')
    rcvd=$(grep -m1 'victim.udpApp\[0\] rcvdPk:count' "$f" | awk '{print $NF}')

    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
        "${val:-?}" "${rep:-$r}" \
        "$(pick "$f" truePositives)" "$(pick "$f" falsePositives)" \
        "$(pick "$f" trueNegatives)" "$(pick "$f" falseNegatives)" \
        "$(pick "$f" recall)" "$(pick "$f" precision)" \
        "$(pick "$f" falsePositiveRate)" "$(pick "$f" detectionLatency)" \
        "${rcvd:-0}" "$(pick "$f" framesDroppedByBlock)" >> "$OUT"
done

echo "wrote $OUT"
