#!/bin/bash
# Baut Rotorwacht und legt die App unter "Programme" ab, danach startet sie per Doppelklick (oder Spotlight).
# Usage: scripts/install.sh [--open]
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh
DEST=/Applications
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"
rm -rf "$DEST/Rotorwacht.app"
cp -R build/Rotorwacht.app "$DEST/Rotorwacht.app"
xattr -dr com.apple.quarantine "$DEST/Rotorwacht.app" 2>/dev/null || true
echo "✓ Rotorwacht liegt in $DEST. Start: Doppelklick, Spotlight (Cmd+Leertaste, \"Rotorwacht\") oder ins Dock ziehen."
[ "${1:-}" = "--open" ] && open "$DEST/Rotorwacht.app"
exit 0
