#!/usr/bin/env bash
set -euo pipefail
export TMPDIR="$PWD/.tmp" ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache" RC_QUICK_CPUS=2,3,10,11
phase_b_tag=${1:?tag}
phase_b_source=$(git rev-parse HEAD)
phase_b_dest=$PWD/.tmp/$phase_b_tag
test ! -e "$phase_b_dest"
git diff --quiet HEAD
mkdir -p "$phase_b_dest"
scripts/build-slot.sh build zig build --cache-dir .zig-phase-b-cache -j4 --maxrss 8589934592 --prefix "$phase_b_dest/compiler" --summary all > "$phase_b_dest/install.log" 2>&1
python3 - "$phase_b_tag" "$phase_b_source" <<'PY'
import hashlib,json,sys
from pathlib import Path
p=Path('.tmp')/sys.argv[1]
i={'source':sys.argv[2],'compiler_sha256':hashlib.sha256((p/'compiler/bin/mylang').read_bytes()).hexdigest(),'qbe_sha256':hashlib.sha256((p/'compiler/bin/qbe').read_bytes()).hexdigest(),'scope':'Combined58binary/258output performance check; finalfullgate remains required'}
(p/'identity.json').write_text(json.dumps(i,indent=2)+'\n')
print(json.dumps(i))
PY
python3 experiments/rc-perf-20260927/quick.py build --compiler "$phase_b_dest/compiler/bin/mylang" --tag "$phase_b_tag" --jobs 3 > "$phase_b_dest/corpus-build.log" 2>&1
cat "$phase_b_dest/corpus-build.log"
for phase_b_size in dev full smoke; do
 python3 experiments/rc-perf-20260927/quick.py measure --tag "$phase_b_tag" --size "$phase_b_size" --jobs 4 > "$phase_b_dest/measure-$phase_b_size.log" 2>&1
 cat "$phase_b_dest/measure-$phase_b_size.log"
done
test "$(git rev-parse HEAD)" = "$phase_b_source"
git diff --quiet HEAD
python3 .tmp/compare-phase-b.py "$phase_b_tag"
