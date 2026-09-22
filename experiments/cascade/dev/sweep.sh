#!/usr/bin/env bash
# Sweep helper: run a list of "arm task run" triples, N at a time.
#
#   printf 'B T1 1\nP1 T1 1\n' | dev/sweep.sh 3
#
# Each `run.py` process forces its own compiler cache, so the sessions running at
# once never share one; the list goes through a temporary file because xargs
# needs a real stdin.
set -uo pipefail
ROOT=/home/epentland/ai/canopy/mylang
JOBS=${1:-3}
cd "$ROOT"
LIST=$(mktemp /tmp/cascade-sweep.XXXXXX)
cat > "$LIST"
xargs -P "$JOBS" -n 3 sh -c 'cd /home/epentland/ai/canopy/mylang && python3 experiments/cascade/run.py --arm "$0" --task "$1" --n "$2"' < "$LIST"
STATUS=$?
rm -f "$LIST"
exit "$STATUS"
