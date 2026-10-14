#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="UbiAir"
EXECUTABLE="UbiAirMenuBar"
APP_BUNDLE="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"

cd "$ROOT"
swift build --configuration release --product "$EXECUTABLE"

BIN_PATH="$(swift build --configuration release --show-bin-path)"
BUILT_EXECUTABLE="$BIN_PATH/$EXECUTABLE"
if [[ ! -x "$BUILT_EXECUTABLE" ]]; then
  echo "Erro: o executável de release não foi encontrado em $BUILT_EXECUTABLE" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BUILT_EXECUTABLE" "$CONTENTS/MacOS/$EXECUTABLE"

/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ai.ubiquu" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $EXECUTABLE" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1.2" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 3" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$CONTENTS/Info.plist"

SIGN_IDENTITY="${UBIAIR_CODESIGN_IDENTITY:-${LGTHINQ_CODESIGN_IDENTITY:-}}"
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
  if [[ -n "${UBIAIR_CODESIGN_IDENTITY:-}" ]]; then
    echo "Assinado com a identidade configurada em UBIAIR_CODESIGN_IDENTITY."
  else
    echo "Assinado com a identidade legada configurada em LGTHINQ_CODESIGN_IDENTITY."
  fi
else
  codesign --force --deep --sign - "$APP_BUNDLE"
  echo "Aviso: bundle assinado ad hoc para desenvolvimento; alterações de assinatura ou identidade podem impedir o acesso a PATs já salvos no Chaves." >&2
fi

codesign --verify --deep --strict "$APP_BUNDLE"
echo "App criado em: $APP_BUNDLE"
