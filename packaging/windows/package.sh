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

echo "==> portable zip"
( cd "$SOURCE" && powershell -NoProfile -Command \
    "Compress-Archive -Path * -DestinationPath '$(cygpath -w "$(cd "$OUT" && pwd)")\\$NAME-windows-portable.zip' -Force" )

ISCC="$(command -v iscc || echo "/c/Program Files (x86)/Inno Setup 6/ISCC.exe")"
if [[ -x "$ISCC" ]]; then
  echo "==> installer"
  "$ISCC" \
    "/DAppVersion=$VERSION" \
    "/DSourceDir=$(cygpath -w "$(cd "$SOURCE" && pwd)")" \
    "/DOutputDir=$(cygpath -w "$(cd "$OUT" && pwd)")" \
    "$(cygpath -w "$ROOT/packaging/windows/caelo.iss")" >/dev/null
else
  echo "!! Inno Setup not found; skipping the installer" >&2
fi

echo "==> Done"
ls -1s "$OUT"
