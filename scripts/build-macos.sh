#!/usr/bin/env bash
#
# Builds the Go core, builds the macOS app, and places the core inside the app
# bundle.
#
# The dylib is copied in after the fact rather than by an Xcode build phase.
# That is deliberate for now: release packaging has to deal with signing,
# hardened runtime and notarisation anyway, and wiring a half-measure into
# project.pbxproj first would only have to be unpicked. Until then, this script
# is the supported way to get a bundle with a working core in it.
set -euo pipefail

MODE="${1:-debug}"
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_ROOT="${CAELO_CORE_ROOT:-$APP_ROOT/../caelo-core}"

if [[ ! -d "$CORE_ROOT" ]]; then
  echo "error: caelo-core not found at $CORE_ROOT" >&2
  echo "Clone https://github.com/TeamGDB/caelo-core beside this repository," >&2
  echo "or set CAELO_CORE_ROOT to where it lives." >&2
  exit 1
fi

echo "==> Building the core"
make -C "$CORE_ROOT" dylib

echo "==> Building the app ($MODE)"
cd "$APP_ROOT"
flutter build macos "--$MODE"

case "$MODE" in
  debug)   BUILD_DIR="Debug" ;;
  profile) BUILD_DIR="Profile" ;;
  release) BUILD_DIR="Release" ;;
  *) echo "error: unknown mode '$MODE' (expected debug, profile or release)" >&2; exit 2 ;;
esac

APP="$APP_ROOT/build/macos/Build/Products/$BUILD_DIR/Caelo.app"
FRAMEWORKS="$APP/Contents/Frameworks"

echo "==> Bundling the core into $(basename "$APP")"
mkdir -p "$FRAMEWORKS"
cp "$CORE_ROOT/build/libcaelo.dylib" "$FRAMEWORKS/"

# Go emits an absolute install name. Left alone, the loader would look for the
# library at the path it happened to be built at, which stops working the moment
# the bundle moves to another machine.
install_name_tool -id "@rpath/libcaelo.dylib" "$FRAMEWORKS/libcaelo.dylib"

# Ad-hoc signature, because install_name_tool invalidates the one Go left and
# macOS will refuse to load a dylib whose signature no longer matches. Release
# builds get a real Developer ID signature during packaging.
codesign --force --sign - "$FRAMEWORKS/libcaelo.dylib"

echo "==> Done: $APP"
