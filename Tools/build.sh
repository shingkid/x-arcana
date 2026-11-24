#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mode="${1:-mac}"
shift || true
common=(-project XArcana/XArcana.xcodeproj -scheme XArcana)
python3 XArcana/Tools/SyncProject.py --check
case "$mode" in
  mac)
    xcodebuild "${common[@]}" -configuration Release -destination 'platform=macOS,variant=Mac Catalyst' \
      -derivedDataPath build/mac CODE_SIGNING_ALLOWED=NO "$@" build ;;
  iphone)
    xcodebuild "${common[@]}" -configuration Release -destination 'generic/platform=iOS' \
      -derivedDataPath build/iphone CODE_SIGNING_ALLOWED=NO "$@" build ;;
  test)
    xcodebuild "${common[@]}" -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' \
      -derivedDataPath build/tests '-skip-testing:XArcana UI Tests' \
      '-skip-testing:XArcana Tests/RenderPerformanceTests' CODE_SIGNING_ALLOWED=NO "$@" test ;;
  ui)
    : "${SIMULATOR_ID:?Set SIMULATOR_ID to an available iPhone simulator UUID.}"
    xcodebuild "${common[@]}" -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
      -derivedDataPath build/ui '-only-testing:XArcana UI Tests' CODE_SIGNING_ALLOWED=NO "$@" test ;;
  performance)
    export XARCANA_RENDER_BENCHMARK=1
    export TEST_RUNNER_XARCANA_RENDER_BENCHMARK=1
    export TEST_RUNNER_XARCANA_BENCHMARK_SCENARIO="${XARCANA_BENCHMARK_SCENARIO:-}"
    xcodebuild "${common[@]}" -configuration Release -destination 'platform=macOS,variant=Mac Catalyst' \
      -derivedDataPath build/performance '-only-testing:XArcana Tests/RenderPerformanceTests' \
      ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO "$@" test ;;
  *) printf 'Usage: Tools/build.sh {mac|iphone|test|ui|performance} [xcodebuild options]\n' >&2; exit 2 ;;
esac
