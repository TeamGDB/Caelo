#!/usr/bin/env bash
#
# Builds the core as a shared library for each Android ABI.
#
#   ANDROID_NDK_HOME=/path/to/ndk ./deploy/android/build-so.sh [output-dir]
#
# The output is laid out the way Android expects to find it:
#
#   <output>/arm64-v8a/libcaelo.so
#   <output>/armeabi-v7a/libcaelo.so
#   <output>/x86_64/libcaelo.so
#
# Point it at the app's src/main/jniLibs and Gradle packs them into the APK,
# where the dynamic loader finds them by name — which is why nothing on the
# Dart side ever builds a path.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-$ROOT/build/android}"

# API 24 is Android 7.0, the oldest release Caelo supports. It is also the
# lowest Flutter does not warn about, and the app pins the same number.
#
# This must match the app's minSdk exactly. Building against a newer API
# produces a library that fails to load on the oldest devices the app still
# claims to support, and only on those — which is the last place anyone looks.
API=24

NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [[ -z "$NDK" || ! -d "$NDK" ]]; then
  echo "error: set ANDROID_NDK_HOME to your NDK installation" >&2
  echo "  e.g. \$ANDROID_HOME/ndk/<version>" >&2
  exit 1
fi

case "$(uname -s)" in
  Darwin) HOST_TAG=darwin-x86_64 ;;
  Linux)  HOST_TAG=linux-x86_64 ;;
  *) echo "error: unsupported build host $(uname -s)" >&2; exit 1 ;;
esac

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
if [[ ! -d "$TOOLCHAIN" ]]; then
  echo "error: no toolchain at $TOOLCHAIN" >&2
  exit 1
fi

VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo dev)}"
LDFLAGS="-X github.com/TeamGDB/Caelo/core/internal/version.Version=$VERSION"

# abi:goarch:clang-prefix[:goarm]
TARGETS=(
  "arm64-v8a:arm64:aarch64-linux-android"
  "armeabi-v7a:arm:armv7a-linux-androideabi:7"
  "x86_64:amd64:x86_64-linux-android"
)

cd "$ROOT"
for target in "${TARGETS[@]}"; do
  IFS=: read -r abi goarch prefix goarm <<< "$target"

  echo "==> $abi"
  mkdir -p "$OUT/$abi"

  env \
    CGO_ENABLED=1 \
    GOOS=android \
    GOARCH="$goarch" \
    ${goarm:+GOARM=$goarm} \
    CC="$TOOLCHAIN/${prefix}${API}-clang" \
    go build -buildmode=c-shared -trimpath \
      -ldflags "$LDFLAGS -s -w" \
      -o "$OUT/$abi/libcaelo.so" ./libcaelo

  # The generated header is the same for every ABI and Android has no use for
  # it; leaving copies around only invites someone to package one.
  rm -f "$OUT/$abi/libcaelo.h"
done

echo "==> Done: $OUT"
