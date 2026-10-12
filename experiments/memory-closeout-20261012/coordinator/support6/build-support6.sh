#!/usr/bin/env bash
set -euo pipefail
source /home/epentland/.config/mylang/dev-env.sh
MM_PREFIX=/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support6-install
MM_COORDINATOR=/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator
scripts/build-slot.sh build "$ZIG" build seed-compiler component-builder -p "$MM_PREFIX" -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS" > "$MM_COORDINATOR/support6-build.log" 2>&1
python3 - "$MM_PREFIX" "$MM_COORDINATOR" <<'PY'
from pathlib import Path
import hashlib,json,shutil,subprocess,sys
prefix=Path(sys.argv[1]); coordinator=Path(sys.argv[2]); (prefix/'bin').mkdir(exist_ok=True)
shutil.copy2(prefix/'focus/mylang',prefix/'bin/mylang')
shutil.copytree(coordinator/'support5-install/libexec',prefix/'libexec')
files={str(p.relative_to(prefix)):hashlib.sha256(p.read_bytes()).hexdigest() for d in ('bin','tools','libexec') for p in (prefix/d).rglob('*') if p.is_file()}
report=dict(source_revision=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),source_worktree=str(Path.cwd()),compiler=str(prefix/'bin/mylang'),files=files,status='intermediate support6 compiler, not C1',component_boundary='libexec copied byte-for-byte from Support5; historical RC-seed-built components. New compiler includes scalar ownership and numeric ABI fixes, but actual owned installed-component qualification remains pending.',build_command='zig build seed-compiler component-builder -p <support6-install> -j4 --maxrss8589934592',build_log='support6-build.log')
(coordinator/'support6-identity.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ('source_revision','compiler','status')}))
print('compiler_sha256='+files['bin/mylang'])
PY
