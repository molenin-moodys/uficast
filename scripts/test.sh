#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
# Command Line Tools includes Swift Testing but SwiftPM may not discover its
# framework directory automatically. Full Xcode normally supplies this itself.
framework_dir="$(xcode-select -p)/Library/Developer/Frameworks"
extra_flags=()
if [ -d "$framework_dir/Testing.framework" ]; then
    extra_flags=(-Xswiftc -F -Xswiftc "$framework_dir" -Xlinker -rpath -Xlinker "$framework_dir")
fi
swift test --disable-xctest --enable-swift-testing --cache-path "$PWD/.build/cache" "${extra_flags[@]}" "$@"
