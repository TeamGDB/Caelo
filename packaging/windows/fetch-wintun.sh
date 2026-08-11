#!/usr/bin/env bash
#
# Fetches wintun.dll for one architecture, verifying it against the pin.
#
#   ./packaging/windows/fetch-wintun.sh <amd64|arm64|x86> <destination-dir>
#
# Runs on any platform: it is a download and an unzip, so a Linux or macOS
# runner can prepare the Windows artefacts.
set -euo pipefail

ARCH="${1:?usage: fetch-wintun.sh <amd64|arm64|x86> <dest>}"
DEST="${2:?}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$HERE/wintun.pin"
: "${version:?the pin has no version}" "${sha256:?the pin has no sha256}"

URL="https://www.wintun.net/builds/wintun-$version.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> wintun $version ($ARCH)"

# Downloaded under a name that says it has not been checked yet, and renamed
# only after it has been. A file that fails the hash is deleted rather than
# left behind: a half-verified driver on disk is one that a later step, or a
# person in a hurry, will eventually use.
curl -fsSL -o "$WORK/wintun.zip.unverified" "$URL"

if command -v sha256sum >/dev/null; then
  echo "$sha256  $WORK/wintun.zip.unverified" | sha256sum -c - >/dev/null
else
  # macOS has shasum instead, and its -c wants the same format.
  echo "$sha256  $WORK/wintun.zip.unverified" | shasum -a 256 -c - >/dev/null
fi
mv "$WORK/wintun.zip.unverified" "$WORK/wintun.zip"

unzip -q -o "$WORK/wintun.zip" -d "$WORK"
install -d "$DEST"
install -m 0644 "$WORK/wintun/bin/$ARCH/wintun.dll" "$DEST/wintun.dll"

# The licence travels with the binary. It forbids removing its own notices,
# and a driver shipped without the terms it arrived under is exactly that.
install -m 0644 "$WORK/wintun/LICENSE.txt" "$DEST/wintun-LICENSE.txt"

echo "==> $DEST/wintun.dll"
