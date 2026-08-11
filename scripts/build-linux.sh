#!/usr/bin/env bash
#
# Builds the core for Linux, then the app. CMake picks the library up from
# core/build/ and bundles it beside Flutter's own.
#
#   ./scripts/build-linux.sh [debug|release]
set -euo pipefail

MODE="${1:-release}"
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_ROOT="${CAELO_CORE_ROOT:-$APP_ROOT/core}"

if [[ ! -d "$CORE_ROOT" ]]; then
  echo "error: the core is missing at $CORE_ROOT" >&2
  exit 1
fi

echo "==> Building the core"
make -C "$CORE_ROOT" linux

# The privileged half. Built here rather than by the packaging script so that
# a plain `build-linux.sh` produces everything an installable package needs,
# and so a failure to build it stops the build rather than quietly producing
# packages that route only the application.
echo "==> Building the service"
make -C "$CORE_ROOT" service

echo "==> Building the app ($MODE)"
cd "$APP_ROOT"
flutter build linux "--$MODE"

echo "==> Done"
