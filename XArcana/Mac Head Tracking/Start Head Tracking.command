#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -x bin/XArcanaHeadBridge ]]; then ./build.sh; fi
printf 'Keep this window open while you play. Close it to stop head tracking.\n'
exec ./bin/XArcanaHeadBridge
