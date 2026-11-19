#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
case "$configuration" in debug|release) ;; *) echo "Usage: scripts/build.sh [debug|release]" >&2; exit 2 ;; esac
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
swift build -c "$configuration" --cache-path "$PWD/.build/cache"
binary_dir="$(swift build -c "$configuration" --cache-path "$PWD/.build/cache" --show-bin-path)"
bundle="${UFICAST_OUTPUT_ROOT:-$PWD/dist}/Uficast.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/Uficast" "$bundle/Contents/MacOS/Uficast"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
codesign --force --sign "${UFICAST_SIGN_IDENTITY:--}" "$bundle"
codesign --verify --strict "$bundle"
printf 'Built %s\n' "$bundle"
