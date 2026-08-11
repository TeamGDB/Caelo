#!/usr/bin/env bash
#
# Turns a built Linux bundle into the formats people actually install.
#
#   ./packaging/linux/package.sh <arch> <version> [bundle-dir] [output-dir]
#
# Produces a tarball, a .deb, an .rpm and an AppImage. Four formats because
# "Linux" is not one thing: Debian and Fedora each want their own, the
# AppImage runs on distributions that want neither, and the tarball is for
# people who would rather unpack it themselves and can be trusted to.
set -euo pipefail

ARCH="${1:?usage: package.sh <arch> <version> [bundle] [out]}"
VERSION="${2:?}"
BUNDLE="${3:-build/linux/${ARCH}/release/bundle}"
OUT="${4:-dist}"

APP=caelo
NAME=Caelo
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

case "$ARCH" in
  x64)   DEB_ARCH=amd64;  RPM_ARCH=x86_64;  APPIMAGE_ARCH=x86_64 ;;
  arm64) DEB_ARCH=arm64;  RPM_ARCH=aarch64; APPIMAGE_ARCH=aarch64 ;;
  *) echo "error: unknown architecture '$ARCH'" >&2; exit 2 ;;
esac

[[ -d "$BUNDLE" ]] || { echo "error: no bundle at $BUNDLE" >&2; exit 1; }
mkdir -p "$OUT"

# The tree every format is built from: the bundle under /opt, a launcher on
# PATH, and a desktop entry so it appears in menus like anything else.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

install -d "$STAGE/opt/$APP" "$STAGE/usr/bin" "$STAGE/usr/share/applications" \
           "$STAGE/usr/share/icons/hicolor/512x512/apps"
cp -r "$BUNDLE/." "$STAGE/opt/$APP/"
ln -sf "/opt/$APP/$APP" "$STAGE/usr/bin/$APP"

cat > "$STAGE/usr/share/applications/$APP.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$NAME
Comment=A VPN client for subscription links
Exec=/opt/$APP/$APP
Icon=$APP
Terminal=false
Categories=Network;
DESKTOP

if [[ -f "$ROOT/packaging/linux/$APP.png" ]]; then
  cp "$ROOT/packaging/linux/$APP.png" "$STAGE/usr/share/icons/hicolor/512x512/apps/$APP.png"
fi

echo "==> tarball"
tar -C "$BUNDLE" -czf "$OUT/$NAME-$VERSION-linux-$ARCH.tar.gz" .

if command -v fpm >/dev/null; then
  # One description of the package, two formats out of it. Writing a control
  # file and a spec file separately would mean two chances to disagree.
  common=(-s dir -C "$STAGE"
    --name "$APP" --version "$VERSION" --license GPL-3.0-or-later
    --description "A VPN client for subscription links"
    --url https://github.com/TeamGDB/Caelo
    --maintainer "TeamGDB" --vendor "TeamGDB")

  echo "==> deb"
  fpm "${common[@]}" -t deb -a "$DEB_ARCH" \
    -d 'libgtk-3-0' -d 'libayatana-appindicator3-1 | libappindicator3-1' \
    -p "$OUT/$NAME-$VERSION-linux-$ARCH.deb" . >/dev/null

  echo "==> rpm"
  fpm "${common[@]}" -t rpm -a "$RPM_ARCH" \
    -d 'gtk3' \
    -p "$OUT/$NAME-$VERSION-linux-$ARCH.rpm" . >/dev/null
else
  echo "!! fpm not installed; skipping deb and rpm" >&2
fi

if command -v appimagetool >/dev/null; then
  echo "==> AppImage"
  APPDIR="$STAGE/$NAME.AppDir"
  install -d "$APPDIR"
  cp -r "$STAGE/opt/$APP/." "$APPDIR/"
  cp "$STAGE/usr/share/applications/$APP.desktop" "$APPDIR/"
  sed -i "s|^Exec=.*|Exec=$APP|" "$APPDIR/$APP.desktop"
  [[ -f "$ROOT/packaging/linux/$APP.png" ]] && cp "$ROOT/packaging/linux/$APP.png" "$APPDIR/$APP.png"
  ln -sf "$APP" "$APPDIR/AppRun"
  ARCH="$APPIMAGE_ARCH" appimagetool --no-appstream "$APPDIR" \
    "$OUT/$NAME-$VERSION-linux-$ARCH.AppImage" >/dev/null 2>&1
else
  echo "!! appimagetool not installed; skipping AppImage" >&2
fi

echo "==> Done"
ls -1sh "$OUT"
