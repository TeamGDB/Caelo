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
  "$OUT/$NAME-$VERSION-macos.dmg"

echo "==> pkg"
# An installer package is signed by a different identity from the application:
# Developer ID Installer rather than Developer ID Application. Signed when one is
# present, and plainly unsigned when not, because a .pkg that looks official and
# is not is the worse of the two outcomes.
PKG_IDENTITY="${MACOS_INSTALLER_IDENTITY:-}"
if [[ -z "$PKG_IDENTITY" ]]; then
  PKG_IDENTITY="$(security find-identity -v 2>/dev/null |
    sed -n 's/.*"\(Developer ID Installer[^"]*\)".*/\1/p' | head -1)"
fi

PKG_SIGNING=()
if [[ -n "$PKG_IDENTITY" ]]; then
  echo "    signing with: $PKG_IDENTITY"
  PKG_SIGNING=(--sign "$PKG_IDENTITY")
else
  echo "!! no Developer ID Installer identity; the .pkg will be unsigned" >&2
fi

pkgbuild --quiet \
  --component "$APP" \
  --install-location /Applications \
  --identifier team.gdb.caelo \
  --version "$VERSION" \
  "${PKG_SIGNING[@]+"${PKG_SIGNING[@]}"}" \
  "$OUT/$NAME-$VERSION-macos.pkg"

echo "==> Done"
ls -1sh "$OUT"
