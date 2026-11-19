#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="${1:-dist/Uficast.app}"
binary="$bundle/Contents/MacOS/Uficast"
if [[ ! -x "$binary" ]]; then
    echo "Build Uficast first with scripts/build.sh (or pass a built .app path)." >&2
    exit 1
fi
mkdir -p docs/screenshots
"$binary" --preview-launcher docs/screenshots/launcher.png
"$binary" --preview-launcher docs/screenshots/argument.png --argument --dark
"$binary" --preview-settings docs/screenshots/commands.png
"$binary" --preview-launcher docs/screenshots/error.png --argument --failure
