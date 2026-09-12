#!/bin/bash
# The four-run presentation sequence, on the compressed demo timeline.
#
#   bash demo.sh          open each run in the GUI, in order
#   bash demo.sh check    run all four headless and print the outcome table
#
# Each run covers 15 simulated seconds: clients start at 1 s, the attack at 5 s.
# In the GUI press Fast (the double arrow) - the whole run then takes a few
# seconds of real time instead of minutes.
#
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIMIT=15s

CONFIGS="Demo_NoProtection Demo_DecisionTree Demo_LowRate_DT Demo_LowRate_Cost"

if [ "${1:-}" = "check" ]; then
    printf "%-22s %12s %10s %8s  %s\n" CONFIG "victim rcvd" "blocked" "blocks" "what it shows"
    printf -- "------------------------------------------------------------------------------\n"
    for c in $CONFIGS; do
        bash "$PROJ/run.sh" "$c" Cmdenv "$LIMIT" > /dev/null 2>&1
        f="$PROJ/simulations/results/$c-0.sca"
        rcvd=$(grep -m1 'victim.udpApp\[0\] rcvdPk:count' "$f" 2>/dev/null | awk '{print $NF}')
        drop=$(grep -m1 '[[:space:]]framesDroppedByBlock ' "$f" 2>/dev/null | awk '{print $NF}')
        blk=$(grep -m1 '[[:space:]]blocksIssued ' "$f" 2>/dev/null | awk '{print $NF}')
        case "$c" in
            *NoProtection)  note="the damage" ;;
            *DecisionTree)  note="supervised works on the familiar attack" ;;
            *LowRate_DT)    note="same model, quieter attack: blind" ;;
            *LowRate_Cost)  note="expected-cost rule catches it" ;;
        esac
        printf "%-22s %12s %10s %8s  %s\n" "$c" "${rcvd:-0}" "${drop:-0}" "${blk:-0}" "$note"
    done
    exit 0
fi

for c in $CONFIGS; do
    echo ">>> $c  - close the window to continue to the next"
    bash "$PROJ/run.sh" "$c" Qtenv "$LIMIT"
done
