#!/bin/bash
# Build the project's C++ modules into an executable that links INET and the
# OpenFlow model.
#
#   bash build.sh          incremental
#   bash build.sh clean    from scratch
#
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# See run.sh for why this is not just a fixed path.
case "$(uname -s)" in
    MINGW*|MSYS*) OMNET_DEFAULT=/d/omnetpp-6.0.2;      WS_DEFAULT=/d/omnetpp-workspace ;;
    *)            OMNET_DEFAULT="$HOME/omnetpp-6.0.2"; WS_DEFAULT="$HOME/omnetpp-workspace" ;;
esac
OMNET="${SDNDDOS_OMNET:-$OMNET_DEFAULT}"
WS="${SDNDDOS_WS:-$WS_DEFAULT}"

source "$OMNET/setenv" -q
export PATH="$WS/inet/out/clang-release/src:$WS/openflow/out/clang-release/src:$PATH"

cd "$PROJ/src" || exit 1

if [ "${1:-}" = "clean" ]; then
    rm -rf out Makefile
fi

# Regenerate the makefile whenever it is missing. MODE=release everywhere to
# match how INET and openflow were built - mixing release and debug libraries
# fails to link on Windows.
if [ ! -f Makefile ]; then
    opp_makemake -f --deep -o sdnddos -O out \
        -I. \
        -I"$WS/inet/src" \
        -I"$WS/openflow/src" \
        -L"$WS/inet/out/clang-release/src" \
        -L"$WS/openflow/out/clang-release/src" \
        -lINET -lopenflow || exit 1
fi

make -j4 MODE=release
echo "BUILD_EXIT=$?"
