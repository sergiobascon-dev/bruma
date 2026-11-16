#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox)"
APP="$PWD/build/Bruma.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Bruma" "$APP/Contents/MacOS/Bruma"
cp Info.plist "$APP/Contents/Info.plist"
cp Sources/Bruma/Frost.metal "$APP/Contents/Resources/Frost.metal"
# Finder can attach these metadata to a previously opened local bundle.
# Remove only signing-incompatible metadata, preserving quarantine attributes.
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
codesign --force --sign "${BRUMA_SIGN_IDENTITY:--}" --identifier dev.sergiobascon.bruma "$APP"
codesign --verify --strict "$APP"
echo "App: $APP"
if [[ "${1:-}" == "--run" ]]; then open "$APP"; fi
