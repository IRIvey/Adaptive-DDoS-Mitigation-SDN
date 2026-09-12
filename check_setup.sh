#!/bin/bash
# Verify every layer of the stack, then prove it works end to end.
#
#   bash check_setup.sh
#
# Checking that files exist is not enough - the first version of this network
# ran 133,635 events cleanly and delivered zero packets. So the last section
# runs a real simulation and checks that traffic flowed and an attacker was
# actually blocked.
#
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# See run.sh for why this is not just a fixed path.
case "$(uname -s)" in
    MINGW*|MSYS*) OMNET_DEFAULT=/d/omnetpp-6.0.2;      WS_DEFAULT=/d/omnetpp-workspace ;;
    *)            OMNET_DEFAULT="$HOME/omnetpp-6.0.2"; WS_DEFAULT="$HOME/omnetpp-workspace" ;;
esac
OMNET="${SDNDDOS_OMNET:-$OMNET_DEFAULT}"
WS="${SDNDDOS_WS:-$WS_DEFAULT}"

# Windows venvs put the interpreter in Scripts\, Linux in bin/.
PY="$PROJ/.venv/Scripts/python.exe"
[ -x "$PY" ] || PY="$PROJ/.venv/bin/python"

pass=0
fail=0
ok()  { printf "  [ OK ]  %s\n" "$1"; pass=$((pass + 1)); }
bad() { printf "  [FAIL]  %s\n" "$1"; [ -n "$2" ] && printf "          fix: %s\n" "$2"; fail=$((fail + 1)); }
have() { [ -e "$1" ]; }

echo
echo "OMNeT++"
if have "$OMNET/Version"; then ok "$(cat "$OMNET/Version") at $OMNET"
else bad "not found at $OMNET" "see docs/setup.md step 1, or set SDNDDOS_OMNET"; fi
have "$OMNET/Makefile.inc" && ok "configured and built" \
    || bad "not built" "in the OMNeT++ shell: cd $OMNET && ./configure && make"
grep -q '^WITH_QTENV = yes' "$OMNET/Makefile.inc" 2>/dev/null && ok "GUI (Qtenv) available" \
    || bad "Qtenv missing - no GUI" "rebuild OMNeT++ with Qt"

source "$OMNET/setenv" -q 2>/dev/null
cxx=$(clang++ --version 2>/dev/null | head -1)
[ -n "$cxx" ] && ok "compiler: $cxx" \
    || bad "no C++ compiler on PATH" "you are not in the OMNeT++ shell - double-click shell.cmd"

# Shared libraries are .dll on Windows, .so on Linux - check for either.
libbuilt() { have "$1.dll" || have "$1.so"; }

echo
echo "INET framework"
have "$WS/inet/Version" && ok "$(cat "$WS/inet/Version")" || bad "INET source missing" "docs/setup.md step 3"
libbuilt "$WS/inet/out/clang-release/src/libINET" && ok "libINET built" \
    || bad "libINET missing" "cd $WS/inet && make makefiles && make MODE=release"

echo
echo "OpenFlow model"
libbuilt "$WS/openflow/out/clang-release/src/libopenflow" && ok "libopenflow built" \
    || bad "libopenflow missing" "cd $WS/openflow && make makefiles && make MODE=release"

echo
echo "This project"
{ have "$PROJ/src/out/clang-release/sdnddos.exe" || have "$PROJ/src/out/clang-release/sdnddos"; } \
    && ok "simulator built" || bad "simulation not built" "bash build.sh"
have "$PROJ/src/DecisionTree.h" && have "$PROJ/src/KMeansModel.h" && ok "trained models exported to C++" \
    || bad "model headers missing" "train the models: see README, 'Retraining'"
have "$PROJ/data/flows_sim.csv" && ok "dataset: $(($(wc -l < "$PROJ/data/flows_sim.csv") - 1)) flow rows" \
    || bad "no collected dataset" "bash run.sh Collect Cmdenv 60s"

echo
echo "Python (training and graphs)"
if have "$PY"; then
    ok "virtual environment at .venv"
    vers=$("$PY" -c "import sklearn, pandas, numpy, matplotlib; print(f'scikit-learn {sklearn.__version__}, pandas {pandas.__version__}, numpy {numpy.__version__}, matplotlib {matplotlib.__version__}')" 2>/dev/null)
    [ -n "$vers" ] && ok "$vers" \
        || bad "packages missing" "$PY -m pip install scikit-learn pandas numpy matplotlib joblib"
else
    bad "no .venv" "python -m venv .venv, then install the packages above"
fi

echo
echo "End-to-end run  (30 s Decision Tree simulation, takes a few seconds)"
SMOKE="$PROJ/simulations/results/smoketest"
rm -rf "$SMOKE"
bash "$PROJ/run.sh" DecisionTree Cmdenv 30s --result-dir="$SMOKE" > "$SMOKE.log" 2>&1
sca="$SMOKE/DecisionTree-0.sca"
if [ ! -f "$sca" ]; then
    bad "simulation produced no results" "see simulations/results/smoketest.log"
else
    val() { grep -m1 -E "$1" "$sca" | awk '{print $NF}'; }
    rcvd=$(val 'victim.udpApp\[0\] rcvdPk:count')
    blocked=$(val '[[:space:]]framesDroppedByBlock ')
    tp=$(val '[[:space:]]truePositives ')
    [ "${rcvd:-0}" -gt 0 ] && ok "traffic reached the victim ($rcvd packets)" \
        || bad "victim received nothing - network is not delivering" "see docs/setup.md, 'four things that silently break it'"
    [ "${tp:-0}" -gt 0 ] && ok "attackers detected ($tp)" \
        || bad "no attackers detected"
    [ "${blocked:-0}" -gt 0 ] && ok "attack traffic blocked at the switch ($blocked frames)" \
        || bad "nothing was blocked - mitigation is not working"
fi
rm -f "$SMOKE.log"

echo
if [ "$fail" -eq 0 ]; then
    echo "All $pass checks passed. The whole stack works."
else
    echo "$fail check(s) failed, $pass passed. Work through the 'fix' lines above, top first."
fi
exit "$fail"
