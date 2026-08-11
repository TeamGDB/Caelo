#!/usr/bin/env bash
#
# Builds the core for Windows, then the app. CMake copies the DLL next to the
# executable, where Windows looks for it by name.
#
#   ./scripts/build-windows.sh [debug|release]
#
# Bash rather than PowerShell so that one script serves a developer's Git Bash
# and CI alike. Windows runners have no make, so the core is built directly.
set -euo pipefail

MODE="${1:-release}"
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_ROOT="${CAELO_CORE_ROOT:-$APP_ROOT/core}"

if [[ ! -d "$CORE_ROOT" ]]; then
  echo "error: the core is missing at $CORE_ROOT" >&2
  exit 1
fi

VERSION="$(git -C "$APP_ROOT" describe --tags --always --dirty 2>/dev/null || echo dev)"

echo "==> Building the core"
cd "$CORE_ROOT"
CGO_ENABLED=1 go build -buildmode=c-shared \
  -ldflags "-X github.com/TeamGDB/Caelo/core/internal/version.Version=$VERSION" \
  -o build/caelo.dll ./libcaelo

# The privileged half. A separate executable because it runs as LocalSystem,
# and built here so that a failure stops the build rather than quietly
# producing an installer that routes only the application.
echo "==> Building the service"
go build -ldflags "-X github.com/TeamGDB/Caelo/core/internal/version.Version=$VERSION" \
  -o build/caelo-service.exe ./cmd/caelo-service

echo "==> Building the app ($MODE)"
cd "$APP_ROOT"
flutter build windows "--$MODE"

echo "==> Done"
