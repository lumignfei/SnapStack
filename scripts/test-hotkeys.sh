#!/bin/bash
set -euo pipefail
SNAPSTACK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$SNAPSTACK_ROOT/.build/module-cache"
swiftc -swift-version 6 -parse-as-library -module-cache-path "$SNAPSTACK_ROOT/.build/module-cache" \
    "$SNAPSTACK_ROOT/Sources/SnapStack/CaptureHotKey.swift" \
    "$SNAPSTACK_ROOT/Tests/HotKeyRegistrationChecks.swift" \
    -o "$SNAPSTACK_ROOT/.build/hotkey-registration-checks"
# Run in the desktop session with SnapStack quit; this registers and releases keys, without sending them.
"$SNAPSTACK_ROOT/.build/hotkey-registration-checks"
