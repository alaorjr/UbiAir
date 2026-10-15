#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY_FILE="$ROOT/Sources/UbiAirMenuBar/AppIdentity.swift"
PROJECT="$ROOT/UbiAir.xcodeproj"
SCHEME="UbiAir"
DERIVED_DATA="$ROOT/build/XcodeSandbox"

if [[ ! -f "$PROJECT/project.pbxproj" ]]; then
  echo "Erro: projeto Xcode não encontrado em $PROJECT" >&2
  exit 1
fi
if [[ ! -f "$ROOT/Resources/Info.plist" || ! -f "$ROOT/Resources/PrivacyInfo.xcprivacy" || ! -d "$ROOT/Resources/Assets.xcassets" ]]; then
  echo "Erro: recursos do app ainda não estão completos em Resources/." >&2
  exit 1
fi

read_identity_value() {
  local key="$1"
  python3 - "$IDENTITY_FILE" "$key" <<'PY'
import pathlib, re, sys
source = pathlib.Path(sys.argv[1]).read_text()
match = re.search(rf'^\s*static let {re.escape(sys.argv[2])} = "([^"]+)"', source, re.M)
if not match:
    raise SystemExit(f"Não foi possível ler {sys.argv[2]} de AppIdentity.swift")
print(match.group(1))
PY
}

VERSION="$(read_identity_value version)"
BUILD="$(read_identity_value build)"

xcodebuild \
  -quiet \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$DERIVED_DATA/SourcePackages" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  DEVELOPMENT_TEAM= \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS="arm64 x86_64" \
  build

APP="$DERIVED_DATA/Build/Products/Release/UbiAir.app"
if [[ ! -d "$APP" ]]; then
  echo "Erro: xcodebuild terminou sem gerar $APP" >&2
  exit 1
fi

python3 "$ROOT/Scripts/verify-distribution.py" "$APP"
echo "App sandbox local criado em: $APP"
