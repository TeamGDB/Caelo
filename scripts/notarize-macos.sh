#!/usr/bin/env bash
#
# Signs, notarises and staples the macOS app.
#
#   ./scripts/notarize-macos.sh [path/to/Caelo.app]
#
# A system extension will not load on a machine with SIP enabled unless the app
# carrying it has been through this. There is no development shortcut that does
# not involve turning SIP off, which is not a thing to ask of anyone.
#
# Credentials come from a keychain profile rather than the environment, so no
# password is ever an argument, a variable, or a line in a log:
#
#   xcrun notarytool store-credentials caelo --apple-id <id> --team-id BM4788UD8M
set -euo pipefail

APP="${1:-build/macos/Build/Products/Release/Caelo.app}"
PROFILE="${CAELO_NOTARY_PROFILE:-caelo}"

[[ -d "$APP" ]] || { echo "error: no app at $APP" >&2; exit 1; }

echo "==> Checking the signature"
codesign --verify --deep --strict --verbose=1 "$APP"

# Notarisation takes a zip; the app itself is stapled afterwards.
ARCHIVE="$(mktemp -d)/Caelo.zip"
echo "==> Packing"
ditto -c -k --keepParent "$APP" "$ARCHIVE"

echo "==> Submitting, and waiting"
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$PROFILE" --wait

# Stapling writes the ticket into the bundle so it validates without asking
# Apple — which matters for exactly the people this is for.
echo "==> Stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Done"
