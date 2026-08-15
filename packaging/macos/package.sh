#!/usr/bin/env bash
#
# Turns a built macOS app into the thing people expect to download.
#
#   ./packaging/macos/package.sh <version> [app-path] [output-dir]
#
# A .dmg, and only a .dmg. There was a .pkg as well, for installing across a
# fleet, and it is gone because signing one needs a Developer ID Installer
# certificate -- a second identity, separate from the one that signs the app --
# and Gatekeeper will not install an unsigned package anyway. Shipping one that
# cannot be installed is worse than not shipping it.
#
# Reinstating it is a matter of `git revert` plus that certificate; see
# docs/signing.md. Nothing else in the pipeline depends on it.
#
# Not signed or notarised here; that belongs to release, with the identity, and
# an unsigned build must never be handed out as one.
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

echo "==> Done"
ls -1sh "$OUT"
