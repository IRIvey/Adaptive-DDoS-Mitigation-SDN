#!/bin/bash
# Sweep the attack intensity for both detectors and collect every run.
#
#   bash sweep.sh [seconds]
#
# Runs every (intensity x repetition) combination the ini defines. The models
# are never retrained - they saw the full-rate attack once and everything
# quieter is an attack they have not met.
#
LIMIT="${1:-60s}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RES="$PROJ/simulations/results"
OUT="$PROJ/results/sweep.csv"

mkdir -p "$PROJ/results"

pick() {   # pick <file> <scalar name>
    grep -m1 -E "[[:space:]]$2 " "$1" 2>/dev/null | awk '{print $NF}'
}

echo "detector,interval,rep,tp,fp,tn,fn,recall,precision,fpr,victim_rcvd,blocked" > "$OUT"

for cfg in Sweep_DT Sweep_KMeans; do
    case "$cfg" in
        Sweep_DT) det="DecisionTree" ;;
        *)        det="KMeans" ;;
    esac

    # Ask the simulator how many runs this config expands to, rather than
    # hardcoding intensities x repetitions in two places.
    n=$(bash "$PROJ/run.sh" "$cfg" Cmdenv "$LIMIT" -q numruns 2>/dev/null \
        | grep -oE '^Number of runs: [0-9]+' | grep -oE '[0-9]+$')
    n="${n:-25}"
    echo "$cfg expands to $n runs" >&2

    for r in $(seq 0 $((n - 1))); do
        bash "$PROJ/run.sh" "$cfg" Cmdenv "$LIMIT" -r "$r" > /dev/null 2>&1
        f="$RES/$cfg-$r.sca"
        [ -f "$f" ] || { echo "  !! missing $cfg-$r" >&2; continue; }

        # The iteration variable is recorded in the results file, so each row
        # carries the intensity it actually ran at.
        iv=$(grep -m1 '^itervar interval ' "$f" | awk '{print $3}' | tr -d '"')
        rep=$(grep -m1 '^attr repetition ' "$f" | awk '{print $3}' | tr -d '"')

        rcvd=$(grep -m1 'victim.udpApp\[0\] rcvdPk:count' "$f" | awk '{print $NF}')
        printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
            "$det" "${iv:-?}" "${rep:-$r}" \
            "$(pick "$f" truePositives)" \
            "$(pick "$f" falsePositives)" \
            "$(pick "$f" trueNegatives)" \
            "$(pick "$f" falseNegatives)" \
            "$(pick "$f" recall)" \
            "$(pick "$f" precision)" \
            "$(pick "$f" falsePositiveRate)" \
            "${rcvd:-0}" \
            "$(pick "$f" framesDroppedByBlock)" >> "$OUT"
    done
done

echo "wrote $OUT"
