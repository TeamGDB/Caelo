#!/usr/bin/env bash
#
# Builds the core for iOS, puts it where the Xcode project expects it, and
# builds the app.
#
#   ./scripts/build-ios.sh [release|debug|archive]
#
# Debug builds of Flutter use a JIT and refuse to launch unless the tooling is
# attached, so release is the default: it is the one that can be handed to a
# phone and opened.
#
# `archive` produces an unsigned .xcarchive, which is what goes to TestFlight
# once scripts/upload-testflight.sh has signed it. Unsigned on purpose: the
# project signs automatically, and automatic signing wants an Xcode account
# session that a hosted runner does not have. Signing happens at export instead,
# against named profiles, which is the one place a runner can do it -- and it
# means this half builds and is worth running on a machine with no certificate
# at all.
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

if [[ "$MODE" == "archive" ]]; then
  flutter build ipa --release --no-codesign
  echo
  echo "==> Done: build/ios/archive/Runner.xcarchive, unsigned."
  echo "    Sign and send it with: ./scripts/upload-testflight.sh"
  exit 0
fi

flutter build ios "--$MODE"

echo "==> Done. Install with:"
echo "    flutter install -d <device-id>"
