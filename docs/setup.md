# Setup

## Version pinning - important

Do **not** install the newest OMNeT++ / INET. The OpenFlow model we depend on
is older than both, and newer versions will not compile against it.

| Component | Version | Why this one |
|---|---|---|
| OMNeT++ | **6.0.2** | Version the OpenFlow model's quick start targets |
| INET | **3.8.5** | Required by the OpenFlow model (NOT 4.x) |
| OpenFlow | CoRE-RG/OpenFlow | Provides switch + controller modules |
| Python | 3.13 | Model training only, runs outside the simulator |

Known limitation: the model implements **OpenFlow 1.0**, not 1.3. This means
hard DROP rules only, no meters / rate limiting. Acceptable for this project.

### Why not 6.2.0 / 6.3.0

6.2.0 and later ship a **clang64** toolchain. 6.0.2 ships **mingw64 (GCC)**.
INET 3.8.5 is older code and clang is stricter about it, so the newer bundles
raise the risk of compile failures. 6.0.2 is what the OpenFlow model was
actually tested against.

## Actual install locations on this machine

| Thing | Path |
|---|---|
| OMNeT++ | `D:\omnetpp-6.0.2` |
| Project | `D:\IUT\3-2\DP2\SDN-DDoS-ML` |

OMNeT++ was moved out of `Downloads` to a short path - deep paths blow past
Windows' 260-character limit once build artifacts start nesting.

## Step 1 - Unpack the MinGW toolchain

The bundle ships the compiler as `.7z` archives that must be extracted before
anything will build:

- `tools\opp-tools-win32-x86_64-mingw64-toolchain.7z` (410 MB)
- `tools\opp-tools-win32-x86_64-mingw64-dependencies.7z` (52 MB)

Normally `mingwenv.cmd` does this automatically on first launch.

**Gotcha:** the `7za.exe` bundled with 6.0.2 is an older build that does *not*
support the `-bb0 -bso0 -bsp0` quiet flags. Using them fails with
"Incorrect command line" (exit 7). Use only `x -aos -y -o<dir> <archive>`.

After extraction, run `qtbinpatcher.exe --qt-dir=<...>\opt\mingw64` to fix the
Qt binary paths.

## Step 2 - Build OMNeT++

From `D:\omnetpp-6.0.2`, launch `mingwenv.cmd`, then inside that shell:

```
./configure
make -j4
```

First build takes 20-40 minutes.

## Step 3 - INET 3.8.5    [DONE]

Extracted to `D:\omnetpp-workspace\inet`, built with:

```
make makefiles && make -j4 MODE=release
```

The `opp_featuretool` "NED package not found" messages for tutorials and
showcases are harmless - the core library builds fine (994 objects, 21.6 MB
`libINET.dll`).

## Step 4 - OpenFlow model    [DONE]

```
git clone https://github.com/CoRE-RG/OpenFlow.git openflow
cd openflow && make makefiles && make -j4 MODE=release
```

Its Makefile expects INET at `../../inet`, which our layout already satisfies.

`modifiedInetFiles/openflow-inet-hack.patch` was **not** applied - it targets
INET 2.x paths (`src/networklayer/...`) while 3.8.5 uses `src/inet/...`. It is
not needed to compile. If IP auto-configuration misbehaves on switch
interfaces later, that patch is the thing to revisit.

## Step 5 - Verify    [DONE]

Working run command (see `D:\omnetpp-workspace\run_example.sh`):

```
source /d/omnetpp-6.0.2/setenv -q
export PATH="$WS/inet/out/clang-release/src:$WS/openflow/out/clang-release/src:$PATH"
opp_run -u Cmdenv \
  -n "$WS/openflow/src:$WS/openflow/scenarios:$WS/inet/src:." \
  -l "$WS/openflow/out/clang-release/src/libopenflow.dll" \
  -f example.ini --sim-time-limit=2s
```

Two things that cost time here:
- The NED path needs **both** `openflow/src` and `openflow/scenarios`
  (`.nedfolders` lists both; `scenarios/package.ned` declares
  `package openflow.scenarios`).
- The DLL directories must be on `PATH` or Windows cannot resolve
  `libINET.dll` at load time.

## Building the network: four things that silently break it

These all produce a simulation that *runs* while delivering zero packets, so
none of them announce themselves. Recorded in the order they were hit.

**1. Addressing.** `IPv4NetworkConfigurator` does not recognise an OpenFlow
switch as a bridge, so it treats every host-to-switch cable as its own link
and gives each a separate `/30`. Hosts then sit in different subnets behind a
layer-2 switch and cannot reach each other. Fix:

```
*.configurator.assignDisjunctSubnetAddresses = false
*.configurator.addStaticRoutes = false
```

plus an explicit `192.168.1.x / 255.255.255.0` block in `ipv4config.xml`.
Without the first line the configurator refuses to reuse one subnet across
links and dies with "failed to find address prefix".

**2. Per-host address rules do not work.** `hosts='**.normalHost[0]'` is not
matched per index - every client claims the same address and the configurator
fails with "failed to configure unique address". Use one rule with
`address='192.168.1.x'` and let it assign the host part.

**3. `LearningSwitch` segfaults.** It looks like the obvious controller app
for a single switch, but it is referenced by **no** scenario in the model and
crashes when paired with `ARPResponder`: the ARP app drops the packet-in that
`LearningSwitch` then dereferences. Use the stack every working scenario uses:
`LLDPForwarding` + `LLDPAgent` + `ARPResponder`.

**4. "It ran" is not "it worked".** The first version completed 133,635 events
cleanly with `victim.udpApp[0] rcvdPk:count 0`. Always check the victim's
received count, not just the exit status.

## Layout on this machine

| Thing | Path |
|---|---|
| OMNeT++ | `D:\omnetpp-6.0.2` |
| INET + OpenFlow | `D:\omnetpp-workspace` |
| Project | `D:\IUT\3-2\DP2\SDN-DDoS-ML` |

## Python side

```
python -m pip install scikit-learn pandas numpy matplotlib joblib
```
