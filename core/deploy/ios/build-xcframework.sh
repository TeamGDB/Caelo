#!/usr/bin/env bash
#
# Builds the core as an xcframework for iOS.
#
#   ./deploy/ios/build-xcframework.sh [output-dir]
#
# Static archives rather than dynamic libraries. iOS will load an embedded
# dynamic framework, but a static archive linked straight into the binary is
# one fewer thing to sign, embed and get wrong at submission time — and the
# packet tunnel extension will have to link the same code separately anyway.
#
# Because it is static, the linker will discard every symbol nothing appears to
# reference, and nothing does: Dart looks them up at runtime. Whatever links
# this needs -force_load. See ios/Flutter/Base.xcconfig in the app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-$ROOT/build/ios}"

# Matches the app's deployment target. A slice built against a newer one fails
# to link for the oldest devices the app still claims to support.
MIN=13.0

VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo dev)}"
LDFLAGS="-X github.com/TeamGDB/Caelo/core/internal/version.Version=$VERSION"

rm -rf "$OUT"
mkdir -p "$OUT"

build() {
  local name="$1" sdk="$2" target="$3"

  local sysroot clang
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  clang="$(xcrun --sdk "$sdk" -f clang)"

  echo "==> $name ($sdk)"
  env \
    CGO_ENABLED=1 \
    GOOS=ios \
    GOARCH=arm64 \
    CC="$clang" \
    CGO_CFLAGS="-target $target -isysroot $sysroot" \
    CGO_LDFLAGS="-target $target -isysroot $sysroot" \
    go build -buildmode=c-archive -trimpath \
      -ldflags "$LDFLAGS" \
      -o "$OUT/$name/libcaelo.a" "$ROOT/libcaelo"
}

cd "$ROOT"

build device    iphoneos        "arm64-apple-ios$MIN"
build simulator iphonesimulator "arm64-apple-ios$MIN-simulator"

# The generated header is identical for both slices and belongs beside each of
# them, which is what xcodebuild expects of a headers directory.
for slice in device simulator; do
  mkdir -p "$OUT/$slice/include"
  mv "$OUT/$slice/libcaelo.h" "$OUT/$slice/include/"
done

echo "==> Assembling the xcframework"
rm -rf "$OUT/caelo.xcframework"
xcodebuild -create-xcframework \
  -library "$OUT/device/libcaelo.a"    -headers "$OUT/device/include" \
  -library "$OUT/simulator/libcaelo.a" -headers "$OUT/simulator/include" \
  -output "$OUT/caelo.xcframework" >/dev/null

echo "==> Done: $OUT/caelo.xcframework"
