#!/bin/bash
set -euo pipefail
SNAPSTACK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$SNAPSTACK_ROOT/.build/module-cache"
swiftc -module-cache-path "$SNAPSTACK_ROOT/.build/module-cache" \
    "$SNAPSTACK_ROOT/Sources/SnapStack/PermissionLaunchPolicy.swift" \
    "$SNAPSTACK_ROOT/Tests/PermissionLaunchPolicyChecks.swift" \
    -o "$SNAPSTACK_ROOT/.build/permission-launch-checks"
"$SNAPSTACK_ROOT/.build/permission-launch-checks"
