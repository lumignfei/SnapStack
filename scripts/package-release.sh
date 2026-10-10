#!/bin/bash
set -euo pipefail

SNAPSTACK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSTACK_SIGNING_IDENTITY="${SNAPSTACK_SIGNING_IDENTITY:--}"
SNAPSTACK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SNAPSTACK_ROOT/Resources/Info.plist")"
SNAPSTACK_PACKAGE="$SNAPSTACK_ROOT/.build/distribution"
SNAPSTACK_APP="$SNAPSTACK_PACKAGE/SnapStack.app"
SNAPSTACK_RELEASE="$SNAPSTACK_ROOT/dist/release"

mkdir -p "$SNAPSTACK_PACKAGE/module-cache" "$SNAPSTACK_RELEASE"
export CLANG_MODULE_CACHE_PATH="$SNAPSTACK_PACKAGE/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$SNAPSTACK_PACKAGE/module-cache"

for SNAPSTACK_ARCH in arm64 x86_64; do
    SNAPSTACK_ARGS=(--package-path "$SNAPSTACK_ROOT"
        --scratch-path "$SNAPSTACK_PACKAGE/$SNAPSTACK_ARCH"
        --cache-path "$SNAPSTACK_PACKAGE/cache"
        --config-path "$SNAPSTACK_PACKAGE/config"
        --security-path "$SNAPSTACK_PACKAGE/security"
        --disable-sandbox --triple "$SNAPSTACK_ARCH-apple-macosx13.5" -c release)
    swift build "${SNAPSTACK_ARGS[@]}"
    SNAPSTACK_BIN="$(swift build "${SNAPSTACK_ARGS[@]}" --show-bin-path)"
    cp "$SNAPSTACK_BIN/SnapStack" "$SNAPSTACK_PACKAGE/SnapStack-$SNAPSTACK_ARCH"
done

rm -rf "$SNAPSTACK_APP"
mkdir -p "$SNAPSTACK_APP/Contents/MacOS" "$SNAPSTACK_APP/Contents/Resources"
/usr/bin/lipo -create "$SNAPSTACK_PACKAGE/SnapStack-arm64" "$SNAPSTACK_PACKAGE/SnapStack-x86_64" -output "$SNAPSTACK_APP/Contents/MacOS/SnapStack"
cp "$SNAPSTACK_ROOT/Resources/Info.plist" "$SNAPSTACK_APP/Contents/Info.plist"
cp "$SNAPSTACK_ROOT/Resources/AppIcon.icns" "$SNAPSTACK_APP/Contents/Resources/AppIcon.icns"
cp "$SNAPSTACK_ROOT/LICENSE" "$SNAPSTACK_APP/Contents/Resources/LICENSE"
printf 'APPL????' > "$SNAPSTACK_APP/Contents/PkgInfo"
/usr/bin/plutil -lint "$SNAPSTACK_APP/Contents/Info.plist"
/usr/bin/codesign --force --sign "$SNAPSTACK_SIGNING_IDENTITY" --identifier com.yangyaoming.snapstack "$SNAPSTACK_APP"
/usr/bin/codesign --verify --strict --all-architectures --verbose=2 "$SNAPSTACK_APP"
/usr/bin/lipo -info "$SNAPSTACK_APP/Contents/MacOS/SnapStack"

SNAPSTACK_ZIP="SnapStack-$SNAPSTACK_VERSION-macOS-universal.zip"
rm -f "$SNAPSTACK_RELEASE/$SNAPSTACK_ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$SNAPSTACK_APP" "$SNAPSTACK_RELEASE/$SNAPSTACK_ZIP"
(cd "$SNAPSTACK_RELEASE" && /usr/bin/shasum -a 256 "$SNAPSTACK_ZIP" > SHA256SUMS.txt)
echo "Release package: $SNAPSTACK_RELEASE/$SNAPSTACK_ZIP"
