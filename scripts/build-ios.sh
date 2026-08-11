#!/usr/bin/env bash
#
# Builds the core for iOS, puts it where the Xcode project expects it, and
# builds the app.
#
#   ./scripts/build-ios.sh [release|debug]
#
# Debug builds of Flutter use a JIT and refuse to launch unless the tooling is
# attached, so release is the default: it is the one that can be handed to a
# phone and opened.
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
flutter build ios "--$MODE"

echo "==> Done. Install with:"
echo "    flutter install -d <device-id>"
