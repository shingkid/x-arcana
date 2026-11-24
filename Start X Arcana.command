#!/bin/bash
set -euo pipefail
workspace="$(cd "$(dirname "$0")" && pwd)"
tracker="$workspace/XArcana/Mac Head Tracking"
game_app="/Applications/X Arcana.app"
if [[ ! -d "$game_app" ]]; then
  printf 'Install the Mac version of X Arcana in Applications first.\n'
  exit 1
fi
if [[ ! -x "$tracker/bin/XArcanaHeadBridge" ]]; then
  (cd "$tracker" && ./build.sh)
fi
# The helper uses its existing exclusive lock to prevent duplicate sensor readers.
(cd "$tracker" && nohup ./bin/XArcanaHeadBridge >> "$TMPDIR/xarcana-head-tracker.log" 2>&1 < /dev/null &)
open "$game_app"
printf 'X Arcana is running on the Mac. Open X Arcana on your iPhone.\n'
