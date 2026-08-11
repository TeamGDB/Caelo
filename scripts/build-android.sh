#!/usr/bin/env bash
#
# Builds the Go core for every Android ABI, puts it where Gradle will pack it
# into the APK, and builds the app.
#
#   ./scripts/build-android.sh [debug|release]
#
# The libraries land in android/app/src/main/jniLibs/<abi>/libcaelo.so, which
# Gradle packages automatically. The dynamic loader then finds libcaelo.so by
# name, which is why nothing on the Dart side ever builds a path.
#
# jniLibs is not committed: it is build output, and a checked-in binary is one
# nobody can tell you the provenance of.
set -euo pipefail

MODE="${1:-debug}"
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_ROOT="${CAELO_CORE_ROOT:-$APP_ROOT/../caelo-core}"
JNI_LIBS="$APP_ROOT/android/app/src/main/jniLibs"

if [[ ! -d "$CORE_ROOT" ]]; then
  echo "error: caelo-core not found at $CORE_ROOT" >&2
  echo "Clone https://github.com/TeamGDB/caelo-core beside this repository," >&2
  echo "or set CAELO_CORE_ROOT to where it lives." >&2
  exit 1
fi

# Work out where the NDK is rather than making everyone export two variables.
# Flutter already knows the SDK path, so ask it, and take the newest NDK there.
if [[ -z "${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}" ]]; then
  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -z "$SDK" ]]; then
    SDK="$(flutter config --list 2>/dev/null | sed -n 's/^ *android-sdk: *//p' | head -1)"
  fi

  if [[ -n "$SDK" && -d "$SDK/ndk" ]]; then
    # Version-sorted, so 27 wins over 9 — a plain sort would not.
    ANDROID_NDK_HOME="$SDK/ndk/$(ls "$SDK/ndk" | sort -V | tail -1)"
    export ANDROID_NDK_HOME
    echo "==> Using NDK at $ANDROID_NDK_HOME"
  else
    echo "error: no NDK found. Set ANDROID_NDK_HOME, or install one with:" >&2
    echo "  sdkmanager --install 'ndk;27.0.12077973'" >&2
    exit 1
  fi
fi

echo "==> Building the core for Android"
"$CORE_ROOT/deploy/android/build-so.sh" "$JNI_LIBS"

echo "==> Building the app ($MODE)"
cd "$APP_ROOT"
flutter build apk "--$MODE"

echo "==> Done"
find build/app/outputs -name "*.apk" -maxdepth 4 2>/dev/null || true
