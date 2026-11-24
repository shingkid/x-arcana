#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
DEPS="$ROOT/.build/dependencies"
mkdir -p "$DEPS" "$ROOT/bin"
fetch() {
  local repository="$1" revision="$2" checksum="$3" archive="$DEPS/$2.tgz"
  if [[ ! -f "$archive" ]]; then
    curl --fail --location --silent --show-error "https://codeload.github.com/$repository/tar.gz/$revision" -o "$archive"
  fi
  printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 -c -
  tar -xzf "$archive" -C "$DEPS"
}
fetch adidoes/xrealair-sdk-macos 4ef80286154738dc65044d76f2da0028788cc009 74e7a700db0d2d18f1fcc403c1b77e5989585517d6301a0e38275cef34fcb534
fetch xioTechnologies/Fusion 490ebf1caadcb745dfdf22153f0d630e9b1c7491 8ecfe0ca58226e3b3b294db5558e33fd250df75d065f65a129d7de303e63d086
fetch libusb/hidapi ff67c77daddbd8e61ad3873ac16f8edc005f943f 1dc5a71fc987432292eb04768a100fc6416142f09657a6fea0e79f877b4543dd
fetch json-c/json-c 07148f33a1c24a7159c6a58b091238c444d74e31 e647bebbfd5a2c7e7e029d8abc155dd65439cff0349d228f6cfbb41be3d56f66
patch -d "$DEPS/xrealair-sdk-macos-4ef80286154738dc65044d76f2da0028788cc009" -p1 < "$ROOT/sdk.patch"
CMAKE="${CMAKE:-$(command -v cmake || true)}"
if [[ -z "$CMAKE" ]]; then
  if [[ ! -x "$ROOT/.build/tools/bin/cmake" ]]; then
    python3 -m venv "$ROOT/.build/tools"
    "$ROOT/.build/tools/bin/python" -m pip install 'cmake==3.31.6'
  fi
  CMAKE="$ROOT/.build/tools/bin/cmake"
fi
"$CMAKE" -S "$ROOT" -B "$ROOT/.build/native" -DDEPS="$DEPS" -DCMAKE_BUILD_TYPE=Release
"$CMAKE" --build "$ROOT/.build/native" --target xarcana_sensor -j 6
swiftc -O -module-cache-path "$ROOT/.build/swift-cache" -import-objc-header "$ROOT/Sensor.h" "$ROOT/Bridge.swift" \
  "$ROOT/.build/native/libxarcana_sensor.a" "$ROOT/.build/native/hidapi/src/mac/libhidapi.a" \
  "$ROOT/.build/native/json-c/libjson-c.a" "$ROOT/.build/native/fusion/libFusion.a" \
  -framework IOKit -framework CoreFoundation -o "$ROOT/bin/XArcanaHeadBridge"
printf 'Built %s/bin/XArcanaHeadBridge\n' "$ROOT"
