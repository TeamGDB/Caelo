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
CORE_ROOT="${CAELO_CORE_ROOT:-$APP_ROOT/core}"

if [[ ! -d "$CORE_ROOT" ]]; then
  echo "error: the core is missing at $CORE_ROOT" >&2
  echo "The core lives in core/ in this repository — the checkout is incomplete." >&2
  exit 1
fi

echo "==> Building the core"
# Static, and universal. Linked into both the app and the system extension by
# Xcode, so it is signed as part of them: a library copied in afterwards and
# re-signed breaks the app's seal, and notarisation refuses that -- correctly.
make -C "$CORE_ROOT" macos-static

echo "==> Building the app ($MODE)"
cd "$APP_ROOT"

# Xcode builds incrementally and will not remove a library an older build put
# in the bundle. One left behind from when the core was a dylib carries an
# ad-hoc signature, which is enough for the notary to reject the whole archive
# while the app itself is perfectly fine.
find build/macos -name libcaelo.dylib -delete 2>/dev/null || true

flutter build macos "--$MODE"

case "$MODE" in
  debug)   BUILD_DIR="Debug" ;;
  profile) BUILD_DIR="Profile" ;;
  release) BUILD_DIR="Release" ;;
  *) echo "error: unknown mode '$MODE' (expected debug, profile or release)" >&2; exit 2 ;;
esac

APP="$APP_ROOT/build/macos/Build/Products/$BUILD_DIR/Caelo.app"


echo "==> Done: $APP"
