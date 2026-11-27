#!/bin/bash
# Photographs fixed places of every Einsatz (developer aid, see DebugShots.swift). Usage: scripts/shots.sh <folder> [mission …]
# Build first (scripts/build.sh). Opens the app window for a few seconds per Einsatz; progress is not touched.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$1; shift
places() {
  case $1 in
    hochwasser) echo 1450,3275,4950 ;;
    waldbrand) echo 1300,3050,4500 ;;
    kueste) echo 1125,3800,5150 ;;
    altstadt) echo 1300,3100,5930 ;;
    vulkan) echo 1300,5900,6300,6660 ;;
    gebirge) echo 1200,5800,6175,6550 ;;
    bohrinsel) echo 1250,2400,4500 ;;
    staudamm) echo 1900,2440,4440 ;;
    pass) echo 900,5750,6125,6500 ;;
    wueste) echo 900,2100,5300 ;;
  esac
}
for m in ${@:-hochwasser waldbrand kueste altstadt vulkan gebirge bohrinsel staudamm pass wueste}; do
  echo "• $m"
  ROTORWACHT_SHOTS="$OUT" ROTORWACHT_MISSION=$m ROTORWACHT_UNLOCK_ALL=1 ROTORWACHT_CAMERA=$(places $m) build/Rotorwacht.app/Contents/MacOS/Rotorwacht >/dev/null 2>&1 || echo "✗ $m"
done
rm -f "$OUT"/ui-*.png "$OUT"/0-start*.png "$OUT"/*-scene.png
