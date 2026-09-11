#!/bin/bash
# Build the project's C++ modules into an executable that links INET and the
# OpenFlow model.
#
#   bash build.sh          incremental
#   bash build.sh clean    from scratch
#
WS=/d/omnetpp-workspace
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source /d/omnetpp-6.0.2/setenv -q
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
