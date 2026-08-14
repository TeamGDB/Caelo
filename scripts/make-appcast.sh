#!/usr/bin/env bash
# Builds the update manifests from a directory of release artifacts.
#
# Two files out of one pass. appcast.xml is what Sparkle on macOS and WinSparkle
# on Windows read; latest.json is for the callers that cannot reasonably be asked
# to parse an RSS feed -- the Android updater, and the notice on Linux that says
# a newer version exists and leaves upgrading to the package manager. They are
# generated together so that they cannot disagree about which version is current,
# which is the failure that would send half the installed base to one build and
# half to another.
#
# Signatures are Ed25519 over the bytes of each file, base64 encoded: what
# Sparkle calls sparkle:edSignature. This is deliberately not the code-signing
# identity. That one tells the operating system it may run the file; this one
# tells an already-installed copy of Caelo that the file came from our release
# pipeline. They fail independently and are meant to.
#
# Generate the key once:
#
#   openssl genpkey -algorithm ed25519 -out caelo-appcast.pem
#   openssl pkey -in caelo-appcast.pem -pubout -outform DER | tail -c 32 | base64
#
# The private half becomes a CI secret and lives nowhere else. The public half
# goes into the app. Losing the private half means no installed copy can ever be
# updated again -- there is no recovery path, because the whole point is that
# nothing else can produce a signature it will accept.
set -euo pipefail

VERSION="${1:?usage: make-appcast.sh <version> <artifact-dir> [out-dir]}"
ARTIFACTS="${2:?usage: make-appcast.sh <version> <artifact-dir> [out-dir]}"
OUT="${3:-pages}"

# Where the artifacts will be readable from. Releases rather than an API: asset
# downloads cost nothing against any quota, whereas api.github.com allows sixty
# unauthenticated requests an hour per IP -- and a VPN client checks through its
# own tunnel, so everyone sharing an exit node shares that quota and all but the
# first few are refused.
BASE_URL="${APPCAST_BASE_URL:-https://github.com/TeamGDB/Caelo/releases/download/v$VERSION}"
NOTES_URL="${APPCAST_NOTES_URL:-https://github.com/TeamGDB/Caelo/releases/tag/v$VERSION}"

# The build number, not the marketing version. Sparkle compares this, and it is
# the only number that is guaranteed to increase: 0.1.0 shipped more than once
# while the build number kept moving.
BUILD="$(sed -n 's/^version: .*+//p' pubspec.yaml)"
SHORT="$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)"
[[ -n "$BUILD" && -n "$SHORT" ]] || { echo "!! could not read version from pubspec.yaml" >&2; exit 1; }

# Written once here rather than read from the project, because a manifest that
# quietly claims support for a system the build never ran on is worse than one
# that is conservative. Raise these when the build's own minimum rises.
MIN_MACOS="10.15"
MIN_WINDOWS="10.0.0"

mkdir -p "$OUT"

KEY_FILE=""
if [[ -n "${APPCAST_KEY:-}" ]]; then
  # A file rather than a pipe because openssl wants to seek it, and in a
  # directory only this process can read: the key is in the environment of a CI
  # runner that also runs third-party actions.
  KEY_DIR="$(mktemp -d)"
  chmod 700 "$KEY_DIR"
  trap 'rm -rf "$KEY_DIR"' EXIT
  KEY_FILE="$KEY_DIR/appcast.pem"
  printf '%s\n' "$APPCAST_KEY" > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
else
  echo "!! APPCAST_KEY is not set; the manifests will carry no signatures" >&2
fi

# stat and sha256 spell themselves differently on the two systems this runs on,
# and the packaging scripts are exercised from a developer's Mac as well as from
# the Linux runner.
size() {
  stat -c%s "$1" 2>/dev/null || stat -f%z "$1"
}

digest() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

sign() {
  [[ -n "$KEY_FILE" ]] || return 0
  openssl pkeyutl -sign -rawin -inkey "$KEY_FILE" -in "$1" | openssl base64 -A
}

# The first file matching a pattern, or nothing. A platform that failed to build
# is left out of the manifest entirely rather than published with a broken link:
# an updater that offers a download and then cannot fetch it strands whoever
# accepted it.
find_one() {
  local match
  match="$(find "$ARTIFACTS" -maxdepth 2 -name "$1" -type f 2>/dev/null | sort | head -1)"
  [[ -n "$match" ]] && printf '%s' "$match"
}

xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"

# --- appcast.xml -------------------------------------------------------------

# One item per operating system rather than one item with two enclosures:
# Sparkle picks an item, not an enclosure, and giving both platforms the same
# item makes each of them see the other's file size.
item() {
  local os="$1" file="$2" minimum="$3"
  local name signature
  name="$(basename "$file")"
  signature="$(sign "$file")"

  {
    printf '    <item>\n'
    printf '      <title>%s</title>\n' "$(xml_escape "$SHORT")"
    printf '      <pubDate>%s</pubDate>\n' "$PUB_DATE"
    printf '      <link>%s</link>\n' "$(xml_escape "$NOTES_URL")"
    printf '      <sparkle:version>%s</sparkle:version>\n' "$BUILD"
    printf '      <sparkle:shortVersionString>%s</sparkle:shortVersionString>\n' "$(xml_escape "$SHORT")"
    printf '      <sparkle:minimumSystemVersion>%s</sparkle:minimumSystemVersion>\n' "$minimum"
    printf '      <enclosure url="%s/%s"\n' "$(xml_escape "$BASE_URL")" "$(xml_escape "$name")"
    printf '                 sparkle:os="%s"\n' "$os"
    printf '                 length="%s"\n' "$(size "$file")"
    printf '                 type="application/octet-stream"'
    [[ -n "$signature" ]] && printf '\n                 sparkle:edSignature="%s"' "$signature"
    printf ' />\n'
    printf '    </item>\n'
  } >> "$OUT/appcast.xml"
}

cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Caelo</title>
    <link>https://teamgdb.github.io/Caelo/appcast.xml</link>
    <description>Updates for Caelo.</description>
    <language>en</language>
XML

MACOS="$(find_one "Caelo-$VERSION-macos.dmg" || true)"
WINDOWS="$(find_one "Caelo-$VERSION-windows-x64-setup.exe" || true)"

if [[ -n "$MACOS" ]]; then item macos "$MACOS" "$MIN_MACOS"; else
  echo "!! no macOS disk image for $VERSION; it will not be offered an update" >&2
fi
if [[ -n "$WINDOWS" ]]; then item windows "$WINDOWS" "$MIN_WINDOWS"; else
  echo "!! no Windows installer for $VERSION; it will not be offered an update" >&2
fi

cat >> "$OUT/appcast.xml" <<'XML'
  </channel>
</rss>
XML

# --- latest.json -------------------------------------------------------------

# Same facts, shape a phone can read. Android needs the per-ABI split that
# matches the device it is running on: installing the x86_64 build over an
# arm64-v8a installation fails, and always taking the universal APK means
# downloading roughly three architectures to use one.
json_entry() {
  local key="$1" file="$2" signature
  signature="$(sign "$file")"
  printf '    "%s": {\n' "$key"
  printf '      "url": "%s/%s",\n' "$BASE_URL" "$(basename "$file")"
  printf '      "size": %s,\n' "$(size "$file")"
  printf '      "sha256": "%s"' "$(digest "$file")"
  [[ -n "$signature" ]] && printf ',\n      "ed25519": "%s"' "$signature"
  printf '\n    }'
}

{
  printf '{\n'
  printf '  "version": "%s",\n' "$SHORT"
  printf '  "build": %s,\n' "$BUILD"
  printf '  "published": "%s",\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '  "notes": "%s",\n' "$NOTES_URL"
  printf '  "artifacts": {\n'

  first=1
  for spec in \
    "android-arm64-v8a:Caelo-$VERSION-android7+-arm64-v8a.apk" \
    "android-armeabi-v7a:Caelo-$VERSION-android7+-armeabi-v7a.apk" \
    "android-x86_64:Caelo-$VERSION-android7+-x86_64.apk" \
    "android-universal:Caelo-$VERSION-android7+-universal.apk" \
    "linux-appimage-x64:Caelo-$VERSION-linux-x64.AppImage" \
    "macos-dmg:Caelo-$VERSION-macos.dmg" \
    "windows-setup-x64:Caelo-$VERSION-windows-x64-setup.exe"
  do
    key="${spec%%:*}"
    file="$(find_one "${spec#*:}" || true)"
    [[ -n "$file" ]] || continue
    [[ $first -eq 1 ]] || printf ',\n'
    first=0
    json_entry "$key" "$file"
  done

  printf '\n  }\n}\n'
} > "$OUT/latest.json"

echo "==> $OUT/appcast.xml"
echo "==> $OUT/latest.json"
