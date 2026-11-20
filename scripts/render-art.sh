#!/bin/bash
# Renders all 3D art with Blender (headless) into Sources/Rotorwacht/Renders.
# Usage: scripts/render-art.sh [heli|people|pads|terrain|panorama|all]   (default: all)
# Needs Blender: brew install --cask blender
set -euo pipefail
cd "$(dirname "$0")/.."
BLENDER=${BLENDER:-$(command -v blender || echo /Applications/Blender.app/Contents/MacOS/Blender)}
what=${1:-all}
run() {
  echo "• $1"
  local log; log=$(mktemp)
  # A failing Blender run must stop the script; the log is only shown on errors.
  if ! "$BLENDER" -b -P "art/$1.py" -- "${@:2}" >"$log" 2>&1 || grep -qiE "^Error|Traceback" "$log"; then
    grep -iE "error|traceback|^  File" "$log" || tail -20 "$log"; rm -f "$log"; echo "✗ $1 failed" >&2; exit 1
  fi
  rm -f "$log"
}
[ "$what" = all ] || [ "$what" = heli ] && run helicopter
[ "$what" = all ] || [ "$what" = people ] && run people
[ "$what" = all ] || [ "$what" = pads ] && run pads
[ "$what" = all ] || [ "$what" = terrain ] && run terrain
[ "$what" = all ] || [ "$what" = panorama ] && run panorama
echo "✓ done"
