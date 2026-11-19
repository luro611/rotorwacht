#!/bin/bash
# Renders all 3D art with Blender (headless) into Sources/Rotorwacht/Renders.
# Usage: scripts/render-art.sh [heli|people|pads|terrain|all]   (default: all)
# Needs Blender: brew install --cask blender
set -euo pipefail
cd "$(dirname "$0")/.."
BLENDER=${BLENDER:-$(command -v blender || echo /Applications/Blender.app/Contents/MacOS/Blender)}
what=${1:-all}
run() { echo "• $1"; "$BLENDER" -b -P "art/$1.py" -- "${@:2}" 2>&1 | grep -iE "error|traceback|^  File" || true; }
[ "$what" = all ] || [ "$what" = heli ] && run helicopter
[ "$what" = all ] || [ "$what" = people ] && run people
[ "$what" = all ] || [ "$what" = pads ] && run pads
[ "$what" = all ] || [ "$what" = terrain ] && run terrain
echo "✓ done"
