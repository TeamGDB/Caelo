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

[[ -d "$SOURCE" ]] || { echo "error: nothing built at $SOURCE" >&2; exit 1; }
mkdir -p "$OUT"

# Resolved before anything changes directory. A relative path is relative to
# wherever the shell happens to be standing, and this script stands in three
# places.
SOURCE="$(cd "$SOURCE" && pwd)"
OUT="$(cd "$OUT" && pwd)"
SOURCE_WIN="$(cygpath -w "$SOURCE")"
OUT_WIN="$(cygpath -w "$OUT")"

echo "==> portable zip"
powershell -NoProfile -Command \
  "Compress-Archive -Path '$SOURCE_WIN\\*' -DestinationPath '$OUT_WIN\\$NAME-windows-portable.zip' -Force"

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
    "/DSourceDir=$SOURCE_WIN" \
    "/DOutputDir=$OUT_WIN" \
    "$(cygpath -w "$ROOT/packaging/windows/caelo.iss")"
else
  echo "!! Inno Setup not found; skipping the installer" >&2
fi

echo "==> Done"
ls -1s "$OUT"
