#!/usr/bin/env bash
#
# Signs, notarises and staples something for macOS.
#
#   ./scripts/notarize-macos.sh [path/to/Caelo.app]
#   ./scripts/notarize-macos.sh dist/Caelo-0.1.0-macos.dmg
#
# A system extension will not load on a machine with SIP enabled unless the app
# carrying it has been through this. There is no development shortcut that does
# not involve turning SIP off, which is not a thing to ask of anyone.
#
# Credentials come from one of two places and never from an argument, so no
# password is ever in a process list or a log.
#
# On a developer machine, a keychain profile:
#
#   xcrun notarytool store-credentials caelo --apple-id <id> --team-id BM4788UD8M
#
# On CI, an App Store Connect API key in the environment -- MACOS_NOTARY_KEY as
# base64 of the .p8, plus MACOS_NOTARY_KEY_ID and MACOS_NOTARY_ISSUER. A key
# rather than an Apple ID and app-specific password because it carries only the
# authority to notarise, and can be revoked without touching the account.
set -euo pipefail

TARGET="${1:-build/macos/Build/Products/Release/Caelo.app}"
PROFILE="${CAELO_NOTARY_PROFILE:-caelo}"

[[ -e "$TARGET" ]] || { echo "error: nothing at $TARGET" >&2; exit 1; }

WORK="$(mktemp -d)"
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

# How to authenticate, decided once. An array so that the key path stays a
# single argument even if the temporary directory ever contains a space.
if [[ -n "${MACOS_NOTARY_KEY:-}" ]]; then
  base64 --decode <<< "$MACOS_NOTARY_KEY" > "$WORK/notary.p8"
  chmod 600 "$WORK/notary.p8"
  CREDENTIALS=(--key "$WORK/notary.p8"
               --key-id "${MACOS_NOTARY_KEY_ID:?MACOS_NOTARY_KEY needs MACOS_NOTARY_KEY_ID}"
               --issuer "${MACOS_NOTARY_ISSUER:?MACOS_NOTARY_KEY needs MACOS_NOTARY_ISSUER}")
else
  CREDENTIALS=(--keychain-profile "$PROFILE")
fi

# An app has to be zipped to be submitted; a disk image or an installer package
# is submitted as it is. All three can be stapled afterwards.
if [[ "$TARGET" == *.app ]]; then
  echo "==> Checking the signature"
  codesign --verify --deep --strict --verbose=1 "$TARGET"

  SUBMIT="$WORK/upload.zip"
  echo "==> Packing"
  ditto -c -k --keepParent "$TARGET" "$SUBMIT"
else
  SUBMIT="$TARGET"
fi

echo "==> Submitting $(basename "$TARGET"), and waiting"
# --wait exits zero even when the verdict is Invalid, so the verdict has to be
# read rather than inferred from the exit status. Without this the script
# cheerfully staples a rejected build and fails one step later, describing the
# wrong problem.
submission="$(xcrun notarytool submit "$SUBMIT" "${CREDENTIALS[@]}" --wait --output-format json)"
echo "$submission"

id="$(echo "$submission" | plutil -extract id raw -o - - 2>/dev/null || true)"
status="$(echo "$submission" | plutil -extract status raw -o - - 2>/dev/null || true)"

if [[ "$status" != "Accepted" ]]; then
  echo
  echo "error: notarisation returned $status. What Apple objected to:" >&2
  xcrun notarytool log "$id" "${CREDENTIALS[@]}" 2>&1 | head -60 >&2
  exit 1
fi

# Stapling writes the ticket into the bundle so it validates without asking
# Apple -- which matters for exactly the people this is for.
echo "==> Stapling"
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"

echo "==> Done"
