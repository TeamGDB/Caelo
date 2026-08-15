#!/usr/bin/env bash
#
# Prints the ExportOptions.plist that turns the archive into a shippable IPA.
#
#   ./scripts/ios-export-options.sh > ExportOptions.plist
#
# Its own script because two callers need the same answer and disagreeing would
# be silent: scripts/build-ios.sh hands it to Flutter, which archives and
# exports in one step, and scripts/upload-testflight.sh uses it when it is
# exporting an archive somebody built earlier.
#
# Written rather than committed, because the profile names are the part that
# changes when somebody regenerates them in the portal, and a file in the tree
# that has to be edited in step with an external system is a file that will
# disagree with it.
#
#   IOS_TEAM_ID        defaults to the team the project is already set to
#   IOS_PROFILE_APP    profile name for team.gdb.caelo
#   IOS_PROFILE_TUNNEL profile name for team.gdb.caelo.PacketTunnel
#   IOS_EXPORT_METHOD  app-store-connect, or development for a build that only
#                      installs on registered devices
#
# The profiles have to be manually managed. The ones Xcode manages for itself
# cannot be used, whatever they are called: exporting with manual signing
# against one fails with "is Xcode managed, but signing settings require a
# manually managed profile", on Xcode 16 and 26 alike. Automatic signing would
# take them, and wants an Xcode signed into an Apple ID, which is the thing a
# hosted runner does not have.
set -euo pipefail

cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>${IOS_EXPORT_METHOD:-app-store-connect}</string>
  <key>teamID</key><string>${IOS_TEAM_ID:-BM4788UD8M}</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>team.gdb.caelo</key><string>${IOS_PROFILE_APP:-Caelo App Store}</string>
    <key>team.gdb.caelo.PacketTunnel</key><string>${IOS_PROFILE_TUNNEL:-Caelo Tunnel App Store}</string>
  </dict>
  <key>uploadSymbols</key><true/>
  <key>stripSwiftSymbols</key><true/>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST
