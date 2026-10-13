#!/usr/bin/env bash
# Builds SK EQ for macOS and packages it as dist/SK-EQ-<version>.dmg.
# Must run on a Mac with Flutter and Xcode installed.
#
#   ./scripts/build_macos_dmg.sh            # build + package
#   ./scripts/build_macos_dmg.sh --no-build # package an existing build
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/p' pubspec.yaml)
APP="build/macos/Build/Products/Release/SK EQ.app"
DMG="dist/SK-EQ-${VERSION}.dmg"

if [[ "${1:-}" != "--no-build" ]]; then
  flutter pub get
  # Update server address (see lib/config.dart); set by CI, optional locally.
  DEFINES=()
  if [[ -n "${PUREEQ_UPDATE_URL:-}" ]]; then
    DEFINES+=("--dart-define=PUREEQ_UPDATE_URL=$PUREEQ_UPDATE_URL")
  fi
  # ${arr[@]+...} form: safe with `set -u` on macOS's bash 3.2 when empty.
  flutter build macos --release ${DEFINES[@]+"${DEFINES[@]}"}
fi

[[ -d "$APP" ]] || { echo "error: $APP not found" >&2; exit 1; }

# Stage the app next to an /Applications shortcut for drag-to-install.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "$DMG"
hdiutil create -volname "SK EQ" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "Created $DMG"
