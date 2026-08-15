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

# Sparkle arrives from CocoaPods with its nested executables signed ad-hoc, and
# Xcode does not re-sign them: it seals the framework it was handed. Apple's
# notary service rejects the result, naming Autoupdate and the nested Updater.app
# as "not signed with a valid Developer ID certificate" and lacking a secure
# timestamp -- which is how this was found, rather than by reading anything.
#
# Signed inside out, because sealing a bundle records the hashes of what it
# contains: doing the app first and the framework after would leave the app
# sealing something that no longer exists.
#
# Not `codesign --deep`, which Apple discourages and which would re-sign the
# system extension with the app's entitlements. Its own are different, and it
# would stop loading.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE" ]]; then
  IDENTITY="$(codesign -dvvv "$APP" 2>&1 |
    sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' | head -1)"

  if [[ -z "$IDENTITY" ]]; then
    echo "!! unsigned build; Sparkle's helpers stay ad-hoc and will not notarise" >&2
  else
    echo "==> Re-signing Sparkle's helpers as $IDENTITY"

    # The app's own entitlements, read back from what Xcode produced. The file
    # in the tree still contains $(PRODUCT_BUNDLE_IDENTIFIER), which nothing
    # outside Xcode expands.
    ENTITLEMENTS="$(mktemp -t caelo-entitlements).plist"
    trap 'rm -f "$ENTITLEMENTS"' EXIT
    codesign -d --entitlements :"$ENTITLEMENTS" "$APP" 2>/dev/null

    while IFS= read -r nested; do
      codesign --force --timestamp --options runtime --sign "$IDENTITY" "$nested"
    done < <(find "$SPARKLE" \( -name '*.xpc' -o -name 'Updater.app' \) -maxdepth 4)

    codesign --force --timestamp --options runtime --sign "$IDENTITY" \
      "$SPARKLE/Versions/B/Autoupdate"
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$SPARKLE"

    # The app last, because its seal covers everything above.
    codesign --force --timestamp --options runtime \
      --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"

    codesign --verify --deep --strict "$APP"
    echo "    signature verified"
  fi
fi

echo "==> Done: $APP"
