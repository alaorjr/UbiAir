#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build/ReadmeCapture"
CORE_DIR="$BUILD_DIR/ThinQCore"
APP_DIR="$BUILD_DIR/UbiAirMenuBar"
FRAME_DIR="$BUILD_DIR/frames"
OUTPUT="$ROOT/Docs/Images/ubiair-demo.gif"
FFMPEG="${FFMPEG:-$(command -v ffmpeg || true)}"

[[ -x "$FFMPEG" ]] || { echo "Instale ffmpeg e adicione-o ao PATH, ou defina FFMPEG=/caminho/ffmpeg" >&2; exit 1; }
mkdir -p "$CORE_DIR" "$APP_DIR" "$FRAME_DIR" "$(dirname "$OUTPUT")"
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
  -o "$APP_DIR/capture-readme-demo" \
  "${MENU_SOURCES[@]}" \
  "$ROOT/Scripts/capture-readme-demo.swift"

rm -f "$FRAME_DIR"/frame-*.png "$OUTPUT"
"$APP_DIR/capture-readme-demo" "$FRAME_DIR"

"$FFMPEG" -hide_banner -loglevel error -y \
  -framerate 1 -i "$FRAME_DIR/frame-%02d.png" \
  -vf "fps=1,scale=360:740:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3" \
  -loop 0 "$OUTPUT"

size="$(stat -f '%z' "$OUTPUT")"
if (( size >= 5 * 1024 * 1024 )); then
  echo "GIF excede 5 MB: $size bytes" >&2
  exit 1
fi
echo "GIF criado: $OUTPUT ($size bytes, 360 × 740 px)"
