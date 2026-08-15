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

ARCHIVE="${1:-build/ios/archive/Runner.xcarchive}"
TEAM_ID="${IOS_TEAM_ID:-BM4788UD8M}"
METHOD="${IOS_EXPORT_METHOD:-app-store-connect}"
PROFILE_APP="${IOS_PROFILE_APP:-Caelo App Store}"
PROFILE_TUNNEL="${IOS_PROFILE_TUNNEL:-Caelo Tunnel App Store}"
OUTPUT="${CAELO_IPA_DIR:-build/ios/ipa}"

[[ -d "$ARCHIVE" ]] || {
  echo "error: no archive at $ARCHIVE" >&2
  echo "       build one first: ./scripts/build-ios.sh archive" >&2
  exit 1
}

WORK="$(mktemp -d)"
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

# Written rather than committed, because the profile names are the part that
# changes when somebody regenerates them in the portal, and a file in the tree
# that has to be edited in step with an external system is a file that will
# disagree with it.
#
# The profiles these names refer to have to be created by hand in the developer
# portal. The ones Xcode manages for itself cannot be used, whatever they are
# called: exporting with manual signing against one fails with "is Xcode
# managed, but signing settings require a manually managed profile", on Xcode 16
# and 26 alike. Automatic signing would take them, and needs an Xcode signed
# into an Apple ID, which is the thing a runner does not have.
cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>$METHOD</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>team.gdb.caelo</key><string>$PROFILE_APP</string>
    <key>team.gdb.caelo.PacketTunnel</key><string>$PROFILE_TUNNEL</string>
  </dict>
  <key>uploadSymbols</key><true/>
  <key>stripSwiftSymbols</key><true/>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

echo "==> Exporting a signed build ($METHOD)"
rm -rf "$OUTPUT"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -exportPath "$OUTPUT" \
  -allowProvisioningUpdates=NO

IPA="$(find "$OUTPUT" -maxdepth 1 -name '*.ipa' -print -quit)"
[[ -n "$IPA" ]] || { echo "error: the export produced no .ipa" >&2; exit 1; }

# Proof rather than assumption, and cheap: an export can succeed and still leave
# the extension signed by something else, which App Store Connect rejects long
# after the job has gone green.
echo "==> What signed it"
unzip -qo "$IPA" -d "$WORK/unpacked"
for target in "$WORK/unpacked/Payload/"*.app "$WORK/unpacked/Payload/"*.app/PlugIns/*.appex; do
  [[ -e "$target" ]] || continue
  authority="$(codesign -dvvv "$target" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
  echo "    $(basename "$target"): ${authority:-unsigned}"
  [[ -n "$authority" ]] || { echo "error: $(basename "$target") came out unsigned" >&2; exit 1; }
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
