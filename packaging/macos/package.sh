#!/usr/bin/env bash
#
# Turns a built macOS app into the two things people expect to download.
#
#   ./packaging/macos/package.sh <version> [app-path] [output-dir]
#
# A .dmg for dragging into Applications, and a .pkg for anyone installing
# across a fleet. Neither is signed or notarised here; that belongs to release,
# with the identity, and an unsigned build must never be handed out as one.
set -euo pipefail

VERSION="${1:?usage: package.sh <version> [app] [out]}"
APP="${2:-build/macos/Build/Products/Release/Caelo.app}"
OUT="${3:-dist}"

NAME=Caelo
[[ -d "$APP" ]] || { echo "error: no app at $APP" >&2; exit 1; }
mkdir -p "$OUT"

echo "==> dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
# The symlink is what makes the window a drag-and-drop instruction rather than
# a folder someone has to work out.
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO \
  "$OUT/$NAME-macos.dmg"

echo "==> pkg"
pkgbuild --quiet \
  --component "$APP" \
  --install-location /Applications \
  --identifier team.gdb.caelo \
  --version "$VERSION" \
  "$OUT/$NAME-macos.pkg"

echo "==> Done"
ls -1sh "$OUT"
