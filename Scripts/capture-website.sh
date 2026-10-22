#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build/WebsiteCapture"
CORE_DIR="$BUILD_DIR/ThinQCore"
APP_DIR="$BUILD_DIR/UbiAirMenuBar"
OUTPUT_DIR="$ROOT/Website/assets/screenshots"
mkdir -p "$CORE_DIR" "$APP_DIR" "$OUTPUT_DIR"
MODULE_CACHE="$BUILD_DIR/ModuleCache"
mkdir -p "$MODULE_CACHE"

swiftc -emit-library -emit-module -module-name ThinQCore \
  -module-cache-path "$MODULE_CACHE" \
  -emit-module-path "$CORE_DIR/ThinQCore.swiftmodule" \
  -o "$CORE_DIR/libThinQCore.dylib" "$ROOT"/Sources/ThinQCore/*.swift

# A capture-only copy supplies deterministic disclosure state to the exact
# product view. No product file is modified or reconstructed for marketing.
python3 - "$ROOT" "$BUILD_DIR" <<'PY_CAPTURE'
import sys
from pathlib import Path
root, build = map(Path, sys.argv[1:])
source = (root / 'Sources/UbiAirMenuBar/MenuPanel.swift').read_text()
needle = 'DisclosureGroup("Direção do ar") {'
if source.count(needle) != 1:
    raise SystemExit('A view mudou: revise a fixture de disclosure antes de capturar.')
source = source.replace(needle, 'DisclosureGroup("Direção do ar", isExpanded: .constant(CaptureWebsite.airflowExpanded)) {')
(build / 'MenuPanelCapture.swift').write_text(source)
PY_CAPTURE

MENU_SOURCES=()
for source in "$ROOT"/Sources/UbiAirMenuBar/*.swift; do
  [[ "$(basename "$source")" == "UbiAirApp.swift" ]] && continue
  if [[ "$(basename "$source")" == "MenuPanel.swift" ]]; then
    MENU_SOURCES+=("$BUILD_DIR/MenuPanelCapture.swift")
  else
    MENU_SOURCES+=("$source")
  fi
done

swiftc -module-cache-path "$MODULE_CACHE" -I "$CORE_DIR" -L "$CORE_DIR" \
  -lThinQCore -Xlinker -rpath -Xlinker "$CORE_DIR" \
  -o "$APP_DIR/capture-website" "${MENU_SOURCES[@]}" \
  "$ROOT/Scripts/capture-website.swift"

"$APP_DIR/capture-website" "$OUTPUT_DIR"
