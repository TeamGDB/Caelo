#!/usr/bin/env bash
#
# Builds the core for iOS, puts it where the Xcode project expects it, and
# builds the app.
#
#   ./scripts/build-ios.sh [release|debug|archive|archive-unsigned]
#
# Debug builds of Flutter use a JIT and refuse to launch unless the tooling is
# attached, so release is the default: it is the one that can be handed to a
# phone and opened.
#
# `archive` produces a signed .xcarchive for scripts/upload-testflight.sh to
# export and send to TestFlight. It needs the distribution certificate and the
# two App Store profiles named in the project; docs/signing.md says where those
# come from.
#
# Signed here rather than at export, which was tried first and does not work.
# Entitlements are compiled in at the moment of signing, so an unsigned archive
# carries none, and exporting one produces an app with only the four Apple adds
# by default. It signs, it exports, it says EXPORT SUCCEEDED, and App Store
# Connect rejects it: "The bundle 'Runner.app' is missing entitlement
# com.apple.developer.networking.networkextension". Which is to say the app that
# came out could not have run a tunnel.
#
# `archive-unsigned` is the version for a machine with no certificate. It proves
# the archive still compiles and produces nothing that can be shipped.
set -euo pipefail

MODE="${1:-release}"
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_ROOT="${CAELO_CORE_ROOT:-$APP_ROOT/core}"

if [[ ! -d "$CORE_ROOT" ]]; then
  echo "error: the core is missing at $CORE_ROOT" >&2
  exit 1
fi

echo "==> Building the core for iOS"
"$CORE_ROOT/deploy/ios/build-xcframework.sh"

echo "==> Placing it where Xcode looks"
mkdir -p "$APP_ROOT/ios/Frameworks"
rm -rf "$APP_ROOT/ios/Frameworks/caelo.xcframework"
cp -R "$CORE_ROOT/build/ios/caelo.xcframework" "$APP_ROOT/ios/Frameworks/"

echo "==> Building the app ($MODE)"
cd "$APP_ROOT"

if [[ "$MODE" == "archive" || "$MODE" == "archive-unsigned" ]]; then
  if [[ "$MODE" == "archive-unsigned" ]]; then
    flutter build ipa --release --no-codesign
    echo
    echo "==> Done: build/ios/archive/Runner.xcarchive, unsigned and unshippable."
    exit 0
  fi

  # Flutter archives and then exports, and it will export with its own idea of
  # the signing settings unless given ours -- which fails, because its idea is
  # automatic signing and the profiles here are not the ones Xcode manages.
  options="$(mktemp -d)/ExportOptions.plist"
  trap 'rm -rf "$(dirname "$options")"' EXIT
  "$APP_ROOT/scripts/ios-export-options.sh" > "$options"

  flutter build ipa --release --export-options-plist="$options"

  # Checked rather than trusted. The failure this catches -- an archive that
  # signed cleanly without the entitlement the app needs to run a tunnel -- is
  # otherwise found by App Store Connect, ten minutes and one upload later.
  app="build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app"
  for required in com.apple.developer.networking.networkextension \
                  com.apple.security.application-groups; do
    if ! codesign -d --entitlements :- "$app" 2>/dev/null | grep -q "$required"; then
      echo "error: the archive is missing $required." >&2
      echo "       Check ios/Base.xcconfig still points at Runner.entitlements." >&2
      exit 1
    fi
  done

  echo
  echo "==> Done: build/ios/archive/Runner.xcarchive and build/ios/ipa, signed."
  echo "    Send it with: ./scripts/upload-testflight.sh"
  exit 0
fi

flutter build ios "--$MODE"

echo "==> Done. Install with:"
echo "    flutter install -d <device-id>"
