#!/bin/bash
# Runs the unit tests with Swift Testing. Works with only the Command Line Tools installed
# (no Xcode, no SwiftPM needed). With a full toolchain `swift test` does the same.
set -euo pipefail
cd "$(dirname "$0")/.."
DEV=/Library/Developer/CommandLineTools/Library/Developer
OUT=build/tests
mkdir -p "$OUT"
cat > "$OUT/main.swift" <<'SWIFT'
import Testing
await Testing.__swiftPMEntryPoint() as Never
SWIFT
# 1. The game logic as its own module (so `@testable import RotorwachtCore` works).
swiftc -O -parse-as-library -wmo -enable-testing -target arm64-apple-macos14.0 -module-name RotorwachtCore \
  -emit-module -emit-module-path "$OUT/RotorwachtCore.swiftmodule" \
  -c Sources/RotorwachtCore/*.swift -o "$OUT/RotorwachtCore.o"
# 2. The tests, linked against it.
swiftc -O -target arm64-apple-macos14.0 -F "$DEV/Frameworks" -framework Testing -I "$OUT" \
  -Xlinker -rpath -Xlinker "$DEV/Frameworks" -Xlinker -rpath -Xlinker "$DEV/usr/lib" \
  -plugin-path /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -module-name RotorwachtTests \
  "$OUT/RotorwachtCore.o" Tests/RotorwachtCoreTests/*.swift "$OUT/main.swift" \
  -o "$OUT/run-tests" 2>&1 | grep -v "SPIImportIgnored" || true
"$OUT/run-tests" 2>&1
