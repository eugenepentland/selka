#!/usr/bin/env python3
"""Retain unique command logs for S4-V; do not reuse evidence output paths."""
import json, os, shlex, subprocess, sys, time
from pathlib import Path
root = Path(__file__).resolve().parents[2]
logs = Path(os.environ.get('S4_V_COMMAND_LOG_DIR', str(Path(__file__).resolve().parent / 'commands')))
logs.mkdir(parents=True, exist_ok=True)
for index in range(1,100000):
    log = logs / f'command-{index:05d}.log'
    try: output = log.open('x'); break
    except FileExistsError: pass
start = time.monotonic()
metadata = {'command': sys.argv[1:], 'cwd': str(root), 'pid': os.getpid()}
log.with_suffix('.json').write_text(json.dumps(metadata, indent=2)+'\n')
# Zig's positional stdout writes may seek to offset zero. Keep command metadata
# in a separate file and assemble the final log after the child has finished.
raw = log.with_suffix('.stdout')
with output, raw.open('xb') as child:
    result = subprocess.run(sys.argv[1:], cwd=root, stdout=child, stderr=subprocess.STDOUT)
    elapsed = time.monotonic()-start
    output.write('$ ' + shlex.join(sys.argv[1:]) + '\n')
    output.write(raw.read_bytes().decode('utf8', errors='replace'))
    output.write(f'\nexit={result.returncode}\nelapsed_seconds={elapsed:.6f}\n')
metadata.update(status=result.returncode,elapsed_seconds=elapsed)
log.with_suffix('.json').write_text(json.dumps(metadata,indent=2)+'\n')
raw.unlink()
print(log, flush=True)
print(log.read_text()[-12000:], flush=True)
sys.exit(result.returncode)
