#!/usr/bin/env bash
# Wait for the independent sweep to fill every cell, then run the three chained
# runs (T2 -> T3 -> T7, each step starting from the previous result) in parallel.
#
#   dev/chains.sh [max_wait_minutes]
set -uo pipefail
ROOT=/home/epentland/ai/canopy/mylang
DEADLINE=$(( $(date +%s) + ${1:-120} * 60 ))
cd "$ROOT"
cells() { python3 - <<'PY'
import json
from pathlib import Path
rows = set()
for path in Path('experiments/cascade/runs').glob('*/*/*.json'):
    if not path.stem.isdigit():
        continue
    record = json.loads(path.read_text())
    rows.add((record['arm'], record['task'], record['run']))
print(len(rows))
PY
}
while [ "$(cells)" -lt 63 ] && [ "$(date +%s)" -lt "$DEADLINE" ]; do
  sleep 60
done
echo "independent cells: $(cells)/63 at $(date +%H:%M)"
for arm in B P1 P2; do
  ( python3 experiments/cascade/run.py --arm "$arm" --chain T2,T3,T7 --n 1 > "/tmp/cascade-chain-$arm.log" 2>&1 ) &
done
wait
echo "chains finished at $(date +%H:%M)"
tail -n 3 /tmp/cascade-chain-B.log /tmp/cascade-chain-P1.log /tmp/cascade-chain-P2.log
