#!/usr/bin/env bash
#
# Signs an iOS archive and sends it to TestFlight.
#
#   ./scripts/upload-testflight.sh [build/ios/archive/Runner.xcarchive]
#
# The archive arrives unsigned, from scripts/build-ios.sh archive. Signing
# happens here, at export, against profiles named rather than discovered --
# because the project signs automatically, and automatic signing needs an Xcode
# logged into an Apple ID, which a hosted runner is not. Exporting with manual
# signing is the one path that works with nothing but a certificate and a
# profile on disk.
#
# Credentials come from the environment and never from an argument, so nothing
# ends up in a process list or a log:
#
#   IOS_ASC_KEY        base64 of the App Store Connect .p8
#   IOS_ASC_KEY_ID     the key's ten-character id
#   IOS_ASC_ISSUER     the issuer UUID
#
# App Manager is enough authority for the key; it does not need Admin.
#
# Optional:
#
#   IOS_TEAM_ID        defaults to the team the project is already set to
#   IOS_PROFILE_APP    profile name for team.gdb.caelo
#   IOS_PROFILE_TUNNEL profile name for team.gdb.caelo.PacketTunnel
#   IOS_EXPORT_METHOD  app-store-connect, or development to export a build that
#                      only installs on registered devices
#   IOS_UPLOAD         false to sign and export without sending anything
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE="${1:-build/ios/archive/Runner.xcarchive}"
OUTPUT="${CAELO_IPA_DIR:-build/ios/ipa}"

WORK="$(mktemp -d)"
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

IPA="$(find "$OUTPUT" -maxdepth 1 -name '*.ipa' -print -quit 2>/dev/null || true)"

# Flutter exports as part of building the archive, so on the pipeline's path
# there is already an IPA here and re-exporting would only be a second chance to
# do it differently. Exporting is for the other caller: somebody with an archive
# and no IPA, which is what an archive built before this script existed looks
# like.
if [[ -z "$IPA" ]]; then
  [[ -d "$ARCHIVE" ]] || {
    echo "error: no IPA in $OUTPUT and no archive at $ARCHIVE" >&2
    echo "       build one first: ./scripts/build-ios.sh archive" >&2
    exit 1
  }

  "$HERE/ios-export-options.sh" > "$WORK/ExportOptions.plist"

  echo "==> Exporting a signed build"
  rm -rf "$OUTPUT"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$WORK/ExportOptions.plist" \
    -exportPath "$OUTPUT" \
    -allowProvisioningUpdates=NO

  IPA="$(find "$OUTPUT" -maxdepth 1 -name '*.ipa' -print -quit)"
  [[ -n "$IPA" ]] || { echo "error: the export produced no .ipa" >&2; exit 1; }
fi


# Proof rather than assumption, and cheap. Both of these have gone wrong here
# already: an export can succeed with the extension signed by something else,
# and it can succeed with the entitlements missing entirely, which is what an
# unsigned archive produced -- an app that could not have run a tunnel, signed
# perfectly, rejected on upload with error 90525.
echo "==> What signed it"
unzip -qo "$IPA" -d "$WORK/unpacked"
for target in "$WORK/unpacked/Payload/"*.app "$WORK/unpacked/Payload/"*.app/PlugIns/*.appex; do
  [[ -e "$target" ]] || continue
  authority="$(codesign -dvvv "$target" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
  echo "    $(basename "$target"): ${authority:-unsigned}"
  [[ -n "$authority" ]] || { echo "error: $(basename "$target") came out unsigned" >&2; exit 1; }

  entitlements="$(codesign -d --entitlements :- "$target" 2>/dev/null || true)"
  for required in com.apple.developer.networking.networkextension \
                  com.apple.security.application-groups; do
    grep -q "$required" <<< "$entitlements" || {
      echo "error: $(basename "$target") is missing $required." >&2
      echo "       App Store Connect rejects this as error 90525. An archive" >&2
      echo "       built with --no-codesign carries no entitlements at all." >&2
      exit 1
    }
  done
done

if [[ "${IOS_UPLOAD:-true}" != "true" ]]; then
  echo "==> Not uploading (IOS_UPLOAD is not true). The build is at $IPA"
  exit 0
fi

[[ -n "${IOS_ASC_KEY:-}" ]] || {
  echo "error: IOS_ASC_KEY is not set, so there is nothing to upload with." >&2
  echo "       See docs/signing.md." >&2
  exit 1
}

KEY_ID="${IOS_ASC_KEY_ID:?IOS_ASC_KEY needs IOS_ASC_KEY_ID}"
ISSUER="${IOS_ASC_ISSUER:?IOS_ASC_KEY needs IOS_ASC_ISSUER}"

# altool has no flag for the key's path: it looks in ./private_keys and three
# places under $HOME. Putting it in a temporary directory and running from there
# keeps the key out of the home directory entirely, and the trap removes it even
# if the upload fails.
mkdir -p "$WORK/private_keys"
base64 --decode <<< "$IOS_ASC_KEY" > "$WORK/private_keys/AuthKey_$KEY_ID.p8"
chmod 600 "$WORK/private_keys/AuthKey_$KEY_ID.p8"

IPA="$(cd "$(dirname "$IPA")" && pwd)/$(basename "$IPA")"

# Validation first. It asks App Store Connect the same questions the upload
# does, and answers them in a minute instead of after the transfer -- which is
# where a missing icon or a bundle version that has already been used shows up.
echo "==> Validating"
(cd "$WORK" && xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER")

echo "==> Uploading"
(cd "$WORK" && xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER")

echo "==> Done. It appears in TestFlight once Apple has finished processing it,"
echo "    which is usually minutes and occasionally an hour."
