#!/usr/bin/env bash
#
# Turns a built Windows app into the two things people download.
#
#   ./packaging/windows/package.sh <version> [runner-dir] [output-dir]
#
# A portable zip and an installer. The zip matters more than usual here: it
# runs from a USB stick without touching the machine, which is the point for
# some of the people this is for.
set -euo pipefail

VERSION="${1:?usage: package.sh <version> [runner-dir] [out]}"
SOURCE="${2:-build/windows/x64/runner/Release}"
OUT="${3:-dist}"

NAME=Caelo
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# The privileged half, and the driver it needs. Both live beside the app rather
# than inside it: the service is a separate executable because it runs as
# LocalSystem, and wintun.dll is a separate program that it loads.
SERVICE="${CAELO_SERVICE:-core/build/caelo-service.exe}"

[[ -d "$SOURCE" ]] || { echo "error: nothing built at $SOURCE" >&2; exit 1; }
mkdir -p "$OUT"

# Resolved before anything changes directory. A relative path is relative to
# wherever the shell happens to be standing, and this script stands in three
# places.
SOURCE="$(cd "$SOURCE" && pwd)"
OUT="$(cd "$OUT" && pwd)"
SOURCE_WIN="$(cygpath -w "$SOURCE")"
OUT_WIN="$(cygpath -w "$OUT")"

# The zip is made before the service is staged, and deliberately does not
# contain it. A portable build that unpacks onto a USB stick cannot register a
# service, and shipping the binary anyway would leave a driver and a privileged
# executable lying in a directory where nothing will ever run them.
echo "==> portable zip"
powershell -NoProfile -Command \
  "Compress-Archive -Path '$SOURCE_WIN\\*' -DestinationPath '$OUT_WIN\\$NAME-$VERSION-windows-x64-portable.zip' -Force"

have_service=no
if [[ -f "$SERVICE" ]]; then
  echo "==> service and driver"
  install -m 0755 "$SERVICE" "$SOURCE/caelo-service.exe"
  # Fetched rather than committed: a signed kernel driver from someone else,
  # pinned by version and hash. See wintun.pin.
  "$ROOT/packaging/windows/fetch-wintun.sh" amd64 "$SOURCE"
  have_service=yes
else
  echo "!! no service at $SERVICE; the installer will route only the app itself" >&2
fi

ISCC="$(command -v iscc || echo "/c/Program Files (x86)/Inno Setup 6/ISCC.exe")"
if [[ -x "$ISCC" ]]; then
  echo "==> installer"
  # Git Bash treats an argument with a lone leading slash as a path and
  # rewrites it into a Windows one, so /DSourceDir=... would arrive as a
  # directory and Inno Setup would report being handed several script names.
  # Turning the conversion off is the fix; doubling the slash is the other one,
  # and doing both leaves // in the argument for the compiler to reject.
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$ISCC" \
    "/DAppVersion=$VERSION" \
    $([[ "$have_service" == yes ]] && echo "/DWithService=1") \
    "/DSourceDir=$SOURCE_WIN" \
    "/DOutputDir=$OUT_WIN" \
    "$(cygpath -w "$ROOT/packaging/windows/caelo.iss")"
else
  echo "!! Inno Setup not found; skipping the installer" >&2
fi

echo "==> Done"
ls -1s "$OUT"
