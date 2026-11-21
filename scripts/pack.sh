#!/bin/bash
# Baut Rotorwacht und packt eine fertige ZIP zum Weitergeben: build/Rotorwacht-<Version>-mac.zip
# Usage: scripts/pack.sh
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh
VERSION=$(grep -m1 '^## \[' CHANGELOG.md | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "0.0.0")
STAGE=build/pack/Rotorwacht
ZIP="build/Rotorwacht-$VERSION-mac.zip"
rm -rf build/pack "$ZIP"
mkdir -p "$STAGE"
cp -R build/Rotorwacht.app "$STAGE/Rotorwacht.app"
cat > "$STAGE/LIES MICH.txt" <<TXT
Rotorwacht $VERSION (Mac)
Ein Hubschrauber-Rettungsspiel von luro (lurohome.de)

Voraussetzung: Mac mit Apple-Chip (M1 oder neuer), macOS 14 oder neuer.

So startest du es:
1. Ziehe "Rotorwacht.app" in den Ordner "Programme".
2. Rechtsklick auf die App, dann "Öffnen", dann im Fenster noch einmal "Öffnen".
   Das ist nur beim ersten Mal nötig, weil die App nicht über Apple notarisiert ist.
   Falls macOS sie trotzdem blockiert: Systemeinstellungen, Datenschutz & Sicherheit,
   unten bei Rotorwacht auf "Trotzdem öffnen" klicken.
   Falls "beschädigt" erscheint, im Terminal einmal eingeben:
   xattr -dr com.apple.quarantine /Applications/Rotorwacht.app

Steuerung: Pfeiltasten fliegen, Leertaste löscht, Esc pausiert. Controller geht auch.

Lizenz: Code MIT, Grafik und Ton CC BY 4.0, Schriften OFL.
Der Spielstand wird nur auf deinem Mac gespeichert.
TXT
ditto -c -k --keepParent "$STAGE" "$ZIP"
echo "✓ $ZIP ($(du -h "$ZIP" | cut -f1))"
