#!/bin/bash
# Builds Rotorwacht.app without Xcode and without SwiftPM (only the Command Line Tools are needed).
# Usage: scripts/build.sh [--run]
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(grep -m1 '^## \[' CHANGELOG.md | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "0.0.0")
OUT=build/app
APP=build/Rotorwacht.app
rm -rf "$OUT" "$APP"
mkdir -p "$OUT" "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "• Core (game logic)"
swiftc -O -parse-as-library -wmo -target arm64-apple-macos14.0 -module-name RotorwachtCore \
  -emit-module -emit-module-path "$OUT/RotorwachtCore.swiftmodule" \
  -c Sources/RotorwachtCore/*.swift -o "$OUT/RotorwachtCore.o"

echo "• App"
swiftc -O -parse-as-library -target arm64-apple-macos14.0 -I "$OUT" -module-name Rotorwacht \
  "$OUT/RotorwachtCore.o" Sources/Rotorwacht/*.swift \
  -o "$APP/Contents/MacOS/Rotorwacht"

echo "• Bundle"
cp -R Sources/Rotorwacht/Fonts Sources/Rotorwacht/Images Sources/Rotorwacht/Renders "$APP/Contents/Resources/"
cp -R Sources/RotorwachtCore/Missions "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Rotorwacht</string>
  <key>CFBundleDisplayName</key><string>Rotorwacht</string>
  <key>CFBundleIdentifier</key><string>de.lurohome.rotorwacht</string>
  <key>CFBundleExecutable</key><string>Rotorwacht</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
</dict></plist>
PLIST

# App icon from the luro seal.
ICONSET="$OUT/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC=Sources/Rotorwacht/Images/siegel-hell.png
for s in 16 32 64 128 256 512; do
  sips -z $s $s "$SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" || true

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "(ad-hoc signing skipped)"
echo "✓ $APP (version $VERSION)"
if [ "${1:-}" = "--run" ]; then open "$APP"; fi
