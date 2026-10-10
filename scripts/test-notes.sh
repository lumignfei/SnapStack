#!/bin/bash
set -euo pipefail
SNAPSTACK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$SNAPSTACK_ROOT/.build/module-cache"
swiftc -swift-version 6 -parse-as-library -module-cache-path "$SNAPSTACK_ROOT/.build/module-cache" \
    "$SNAPSTACK_ROOT/Sources/SnapStack/ImageMarkup.swift" \
    "$SNAPSTACK_ROOT/Sources/SnapStack/CaptureState.swift" \
    "$SNAPSTACK_ROOT/Sources/SnapStack/ScreenshotNote.swift" \
    "$SNAPSTACK_ROOT/Sources/SnapStack/NoteEditor.swift" \
    "$SNAPSTACK_ROOT/Sources/SnapStack/PasteManager.swift" \
    "$SNAPSTACK_ROOT/Sources/SnapStack/PermissionGuide.swift" \
    "$SNAPSTACK_ROOT/Sources/SnapStack/InterfaceStyle.swift" \
    "$SNAPSTACK_ROOT/Tests/NotesChecks.swift" \
    -o "$SNAPSTACK_ROOT/.build/notes-checks"
"$SNAPSTACK_ROOT/.build/notes-checks"
