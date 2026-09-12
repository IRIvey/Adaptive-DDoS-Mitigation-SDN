#!/bin/bash
# Run a configuration from simulations/omnetpp.ini.
#
#   bash run.sh                      -> NoProtection, Cmdenv, 30s
#   bash run.sh NoAttack             -> a different config
#   bash run.sh NoProtection Qtenv   -> with the GUI
#
CONFIG="${1:-NoProtection}"
UI="${2:-Cmdenv}"
LIMIT="${3:-30s}"

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Where OMNeT++ / INET / OpenFlow live. Windows keeps them at D:\omnetpp-6.0.2
# and D:\omnetpp-workspace (this MSYS2 shell sees those as /d/...); native
# Linux keeps them under $HOME by convention. Override with SDNDDOS_OMNET /
# SDNDDOS_WS in your shell profile if yours are somewhere else.
case "$(uname -s)" in
    MINGW*|MSYS*) OMNET_DEFAULT=/d/omnetpp-6.0.2;      WS_DEFAULT=/d/omnetpp-workspace ;;
    *)            OMNET_DEFAULT="$HOME/omnetpp-6.0.2"; WS_DEFAULT="$HOME/omnetpp-workspace" ;;
esac
OMNET="${SDNDDOS_OMNET:-$OMNET_DEFAULT}"
WS="${SDNDDOS_WS:-$WS_DEFAULT}"

source "$OMNET/setenv" -q
export PATH="$WS/inet/out/clang-release/src:$WS/openflow/out/clang-release/src:$PATH"

NEDPATH="$WS/openflow/src:$WS/openflow/scenarios:$WS/inet/src:$PROJ/src"

# opp_makemake names the binary sdnddos.exe on Windows, sdnddos on Linux -
# take whichever actually exists rather than hardcoding one.
EXE="$PROJ/src/out/clang-release/sdnddos.exe"
[ -x "$EXE" ] || EXE="$PROJ/src/out/clang-release/sdnddos"
if [ ! -x "$EXE" ]; then
    echo "simulator not built - run: bash build.sh" >&2
    exit 1
fi

# omnetpp.ini sets repeat=5, and without -r OMNeT++ executes every repetition
# in turn. A plain `bash run.sh X` should mean one run, so default to run 0 -
# unless the caller picked a run (-r) or is only querying the config (-q).
EXTRA=("${@:4}")
pick_run=1
for a in "${EXTRA[@]}"; do
    case "$a" in -r|-q) pick_run=0 ;; esac
done
[ "$pick_run" -eq 1 ] && EXTRA+=(-r 0)

cd "$PROJ/simulations" || exit 1
"$EXE" -u "$UI" \
  -n "$NEDPATH" \
  -f omnetpp.ini -c "$CONFIG" --sim-time-limit="$LIMIT" "${EXTRA[@]}"
