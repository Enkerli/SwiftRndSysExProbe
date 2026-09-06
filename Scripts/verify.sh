#!/bin/bash
#
# Checks the parts of SwiftRndSysExProbe that Xcode's test targets can't reach.
#
#   Scripts/verify.sh          # all suites
#   Scripts/verify.sh probe    # one suite
#
# Suites:
#   identity — the audio component triple is unique across every sibling
#              checkout, JUCE and Swift alike, and matches the host app's
#              lookup. First, because codes are forever and this project was
#              scaffolded from another one's.
#   probe    — what the plug-in CONCLUDES, and more importantly what it refuses
#              to conclude. The thing this plug-in measures is a property of a
#              host, and this runs in no host — so what is checkable is the
#              reasoning, not the answer.
#   kernel   — the foundation package's own check, run from here. It carries the
#              SysEx harness, which is the half of this plug-in that could
#              produce a wrong answer silently.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT="$REPO/SwiftRndSysExProbeExtension"
PACKAGE="${ENKERLI_SWIFT:-$REPO/../enkerli-swift}"
MUSIC_SUITE="${MUSIC_SUITE:-$REPO/../music-suite}"

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

which="${1:-all}"
status=0

PKG_BIN=""
build_package() {
    [ -n "$PKG_BIN" ] && return 0
    if [ ! -f "$PACKAGE/Package.swift" ]; then
        echo "FAIL: no foundation package at $PACKAGE"
        echo "      git clone https://github.com/Enkerli/enkerli-swift ../enkerli-swift"
        echo "      (or set ENKERLI_SWIFT=/path/to/enkerli-swift)"
        status=1
        return 1
    fi
    swift build --package-path "$PACKAGE" >/dev/null || {
        echo "FAIL: the foundation package did not build"; status=1; return 1; }
    PKG_BIN="$(swift build --package-path "$PACKAGE" --show-bin-path)"
}

# UI and Shell are left out — these suites are headless — and so are the
# package's own test targets, whose objects carry a second `main`.
# Shell is linked here, unlike in the other plug-ins' scripts: `NoteMap` lives
# in it and it is the thing this plug-in is about. That drags in `Kernel`, which
# is a C++ target — no .swiftmodule, just a module map SwiftPM generates beside
# its objects — so Swift has to be pointed at that and told to speak C++. This
# is the first of these scripts to link the shell at all, and therefore the
# first to need any of it.
package_flags() {
    build_package || return 1
    echo "-I $PKG_BIN/Modules"
    echo "-Xcc -fmodule-map-file=$PKG_BIN/Kernel.build/module.modulemap"
    echo "-Xcc -I$PACKAGE/Sources/Kernel/include"
    echo "-cxx-interoperability-mode=default"
    find "$PKG_BIN" -name "*.o" ! -path "*/UI.build/*" ! -path "*Tests.build/*" | sort
}

# Every extension source that does not need the AU shell: the session and what
# it derives. The two AU subclasses and the view need CoreAudioKit and a host,
# and are checked by building the schemes.
headless_sources() {
    find "$EXT/Probe" -name "*.swift" 2>/dev/null | sort
}

run_identity() {
    echo "── identity ───────────────────────────────────────"
    python3 "$REPO/Scripts/tests/component-identity.py" || status=1
}

run_probe() {
    echo "── probe ──────────────────────────────────────────"
    cp "$REPO/Scripts/tests/probe-main.swift" "$BUILD/main.swift"
    swiftc -Onone $(package_flags) $(headless_sources) "$BUILD/main.swift" \
        -o "$BUILD/probe" || { status=1; return 0; }
    "$BUILD/probe" || status=1
}

# The render-thread half, from the package that owns it. It matters more here
# than anywhere: a SysEx frame that is truncated or wrongly framed has no
# musical symptom at all, so the only thing standing between "the probe says
# OUT: not proven" and "the kernel mangled it on the way out" is that harness.
# The gaps register, from the package that holds it. A plug-in whose gaps are
# not written down has them anyway, and this repo is exactly the kind that would
# acquire some quietly: it was built in an afternoon.
run_gaps() {
    echo "── gaps (from the foundation package) ─────────────"
    if [ ! -x "$PACKAGE/Scripts/check-gaps.sh" ]; then
        echo "FAIL: no gaps check at $PACKAGE/Scripts/check-gaps.sh"
        status=1
        return 0
    fi
    "$PACKAGE/Scripts/check-gaps.sh" || status=1
}

run_kernel() {
    echo "── kernel (from the foundation package) ───────────"
    if [ ! -x "$PACKAGE/Scripts/check-kernel.sh" ]; then
        echo "FAIL: no kernel check at $PACKAGE/Scripts/check-kernel.sh"
        status=1
        return 0
    fi
    "$PACKAGE/Scripts/check-kernel.sh" || status=1
}

case "$which" in
    identity) run_identity ;;
    probe) run_probe ;;
    kernel) run_kernel ;;
    gaps) run_gaps ;;
    all) run_identity; run_probe; run_kernel; run_gaps ;;
    *) echo "unknown suite: $which"; exit 2 ;;
esac

echo
if [ $status -eq 0 ]; then echo "verify: OK"; else echo "verify: FAILURES"; fi
exit $status
