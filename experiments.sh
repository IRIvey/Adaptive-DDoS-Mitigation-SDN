#!/bin/bash
# Run every experiment configuration across all repetitions and collect the
# results into one tidy CSV for plotting.
#
#   bash experiments.sh [reps] [seconds]
#
# One run tells you nothing - traffic timing, attack start and packet sizes are
# all random. This sweeps the repetitions so the comparison can be reported as
# a mean with spread rather than a single anecdote.
#
REPS="${1:-5}"
LIMIT="${2:-60s}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RES="$PROJ/simulations/results"
OUT="$PROJ/results/experiments.csv"

mkdir -p "$PROJ/results"

CONFIGS="NoProtection DecisionTree KMeans LowRateFlood LowRate_DT LowRate_KMeans"

pick() {   # pick <file> <scalar name>  -> value or empty
    grep -m1 -E "[[:space:]]$2 " "$1" 2>/dev/null | awk '{print $NF}'
}

echo "config,attack,detector,rep,victim_rcvd,blocked,tp,fp,fn,precision,recall,f1,fpr,detection_latency" > "$OUT"

for cfg in $CONFIGS; do
    # Split the config name into the two things that actually vary, so the
    # plots can group by them instead of parsing labels.
    case "$cfg" in
        LowRate*) attack="low-rate" ;;
        *)        attack="full-rate" ;;
    esac
    case "$cfg" in
        *DT|DecisionTree) detector="DecisionTree" ;;
        *KMeans)          detector="KMeans" ;;
        *)                detector="none" ;;
    esac

    for r in $(seq 0 $((REPS - 1))); do
        echo "  running $cfg rep $r ..." >&2
        bash "$PROJ/run.sh" "$cfg" Cmdenv "$LIMIT" -r "$r" > /dev/null 2>&1
        f="$RES/$cfg-$r.sca"
        if [ ! -f "$f" ]; then
            echo "  !! no results for $cfg rep $r" >&2
            continue
        fi
        rcvd=$(grep -m1 'victim.udpApp\[0\] rcvdPk:count' "$f" | awk '{print $NF}')
        printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
            "$cfg" "$attack" "$detector" "$r" \
            "${rcvd:-0}" \
            "$(pick "$f" framesDroppedByBlock)" \
            "$(pick "$f" truePositives)" \
            "$(pick "$f" falsePositives)" \
            "$(pick "$f" falseNegatives)" \
            "$(pick "$f" precision)" \
            "$(pick "$f" recall)" \
            "$(pick "$f" f1)" \
            "$(pick "$f" falsePositiveRate)" \
            "$(pick "$f" detectionLatency)" >> "$OUT"
    done
done

echo "wrote $OUT"
