#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="UbiAir"
EXECUTABLE="UbiAirMenuBar"
APP_BUNDLE="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"

cd "$ROOT"
swift build --configuration release --product "$EXECUTABLE"

ICONSET_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/ubiair-icon.XXXXXX")"
trap 'rm -rf "$ICONSET_TEMP"' EXIT
ICONSET="$ICONSET_TEMP/AppIcon.iconset"
mkdir -p "$ICONSET"
ICON_SOURCE="$ROOT/Resources/Assets.xcassets/AppIcon.appiconset"
ICON_FILES=(
  icon_16x16.png icon_16x16@2x.png
  icon_32x32.png icon_32x32@2x.png
  icon_128x128.png icon_128x128@2x.png
  icon_256x256.png icon_256x256@2x.png
  icon_512x512.png icon_512x512@2x.png
)
for icon_file in "${ICON_FILES[@]}"; do
  if [[ ! -f "$ICON_SOURCE/$icon_file" ]]; then
    echo "Erro: PNG do ícone ausente: $ICON_SOURCE/$icon_file" >&2
    exit 1
  fi
  sips --setProperty format png "$ICON_SOURCE/$icon_file" --out "$ICONSET/$icon_file" >/dev/null
done
iconutil --convert icns --output "$ICONSET_TEMP/AppIcon.icns" "$ICONSET"

BIN_PATH="$(swift build --configuration release --show-bin-path)"
BUILT_EXECUTABLE="$BIN_PATH/$EXECUTABLE"
if [[ ! -x "$BUILT_EXECUTABLE" ]]; then
  echo "Erro: o executável de release não foi encontrado em $BUILT_EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BUILT_EXECUTABLE" "$CONTENTS/MacOS/$EXECUTABLE"
cp "$ICONSET_TEMP/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ai.ubiquu.UbiAir" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $EXECUTABLE" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1.10" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 11" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$CONTENTS/Info.plist"

SIGN_IDENTITY="${UBIAIR_CODESIGN_IDENTITY:-}"
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
  echo "Assinado com a identidade configurada em UBIAIR_CODESIGN_IDENTITY."
else
  codesign --force --deep --sign - "$APP_BUNDLE"
  echo "Aviso: bundle assinado ad hoc para desenvolvimento; alterações de assinatura ou identidade podem impedir o acesso a PATs já salvos no Chaves." >&2
fi

codesign --verify --deep --strict "$APP_BUNDLE"
echo "App criado em: $APP_BUNDLE"
