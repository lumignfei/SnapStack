#!/bin/bash
set -euo pipefail

SNAPSTACK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSTACK_CONFIGURATION="${1:-debug}"
SNAPSTACK_BUILD="$SNAPSTACK_ROOT/.build"
SNAPSTACK_APP="$SNAPSTACK_ROOT/dist/SnapStack.app"
SNAPSTACK_STAGING="$SNAPSTACK_BUILD/package/SnapStack.app"

case "$SNAPSTACK_CONFIGURATION" in
    debug|release) ;;
    *) echo "Usage: bash scripts/build-app.sh [debug|release]" >&2; exit 2 ;;
esac

mkdir -p "$SNAPSTACK_BUILD/module-cache" "$SNAPSTACK_ROOT/dist"
export CLANG_MODULE_CACHE_PATH="$SNAPSTACK_BUILD/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$SNAPSTACK_BUILD/module-cache"

swift build --package-path "$SNAPSTACK_ROOT" \
    --scratch-path "$SNAPSTACK_BUILD" \
    --cache-path "$SNAPSTACK_BUILD/cache" \
    --config-path "$SNAPSTACK_BUILD/config" \
    --security-path "$SNAPSTACK_BUILD/security" \
    --disable-sandbox -c "$SNAPSTACK_CONFIGURATION"

SNAPSTACK_BIN="$(swift build --package-path "$SNAPSTACK_ROOT" \
    --scratch-path "$SNAPSTACK_BUILD" \
    --cache-path "$SNAPSTACK_BUILD/cache" \
    --config-path "$SNAPSTACK_BUILD/config" \
    --security-path "$SNAPSTACK_BUILD/security" \
    --disable-sandbox \
    -c "$SNAPSTACK_CONFIGURATION" --show-bin-path)"

rm -rf "$SNAPSTACK_STAGING"
mkdir -p "$SNAPSTACK_STAGING/Contents/MacOS" "$SNAPSTACK_STAGING/Contents/Resources"
cp "$SNAPSTACK_BIN/SnapStack" "$SNAPSTACK_STAGING/Contents/MacOS/SnapStack"
cp "$SNAPSTACK_ROOT/Resources/Info.plist" "$SNAPSTACK_STAGING/Contents/Info.plist"
printf 'APPL????' > "$SNAPSTACK_STAGING/Contents/PkgInfo"
/usr/bin/plutil -lint "$SNAPSTACK_STAGING/Contents/Info.plist"
/usr/bin/codesign --force --sign - \
    --identifier com.yangyaoming.snapstack "$SNAPSTACK_STAGING"
/usr/bin/codesign --verify --strict --verbose=2 "$SNAPSTACK_STAGING"
if [ -d "$SNAPSTACK_APP" ]; then
    rm -rf "$SNAPSTACK_BUILD/previous-app"
    mkdir -p "$SNAPSTACK_BUILD/previous-app"
    mv "$SNAPSTACK_APP" "$SNAPSTACK_BUILD/previous-app/SnapStack.app"
fi
mv "$SNAPSTACK_STAGING" "$SNAPSTACK_APP"
echo "Built: $SNAPSTACK_APP"
