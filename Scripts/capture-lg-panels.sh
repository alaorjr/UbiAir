#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build/ReviewCapture"
OUTPUT_DIR="$ROOT/Docs/LG-Email-Attachments"
CORE_DIR="$BUILD_DIR/ThinQCore"
APP_DIR="$BUILD_DIR/UbiAirMenuBar"

mkdir -p "$CORE_DIR" "$APP_DIR" "$OUTPUT_DIR"
MODULE_CACHE="$BUILD_DIR/ModuleCache"
mkdir -p "$MODULE_CACHE"

swiftc \
  -emit-library \
  -emit-module \
  -module-name ThinQCore \
  -module-cache-path "$MODULE_CACHE" \
  -emit-module-path "$CORE_DIR/ThinQCore.swiftmodule" \
  -o "$CORE_DIR/libThinQCore.dylib" \
  "$ROOT"/Sources/ThinQCore/*.swift

MENU_SOURCES=()
for source in "$ROOT"/Sources/UbiAirMenuBar/*.swift; do
  [[ "$(basename "$source")" == "UbiAirApp.swift" ]] && continue
  MENU_SOURCES+=("$source")
done

swiftc \
  -module-cache-path "$MODULE_CACHE" \
  -I "$CORE_DIR" \
  -L "$CORE_DIR" \
  -lThinQCore \
  -Xlinker -rpath -Xlinker "$CORE_DIR" \
  -o "$APP_DIR/capture-lg-panels" \
  "${MENU_SOURCES[@]}" \
  "$ROOT/Scripts/capture-lg-panels.swift"

for scenario in connection controls; do
  "$APP_DIR/capture-lg-panels" "$OUTPUT_DIR" "$scenario"
done
