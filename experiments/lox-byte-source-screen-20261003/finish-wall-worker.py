#!/usr/bin/env python3
"""Wait for this frozen wall command, validate it, and retain a private closeout."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

work = Path(__file__).resolve().parent
repo = work.parent
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
guard_path = work / 'guards.json'
guard_hash = sha(guard_path)
screen = json.loads((work / 'guard-after-screen.json').read_text())
assert guard_hash == screen['guards_sha256']
guards = json.loads(guard_path.read_text())
assert all(sha(Path(p)) == digest for p, digest in guards.items())
receipt = {'started_utc': datetime.now(timezone.utc).isoformat(),
           'worker_sha256': sha(Path(__file__)), 'guards_sha256': guard_hash,
           'guarded_inputs': len(guards), 'complete': False}
out = work / 'wall-closeout.json'
assert not out.exists()
out.write_text(json.dumps(receipt, indent=2) + '\n')
command = work / 'measurements/wall.command.json'
deadline = time.monotonic() + 1800
while True:
    status = json.loads(command.read_text()).get('status')
    if status is not None:
        break
    if time.monotonic() > deadline:
        receipt['monitor_timeout'] = True
        out.write_text(json.dumps(receipt, indent=2) + '\n')
        raise SystemExit('wall command has not completed; no performance conclusion')
    time.sleep(10)
assert status == 0, status
argv = [sys.executable, str(repo / 'experiments/lox-byte-source-screen-20261003/analyze.py'),
        str(work / 'measurements/wall.json'), '--metric', 'wall_s',
        '--out', str(work / 'wall-analysis.json')]
with (work / 'wall-analysis.log').open('w') as log:
    result = subprocess.run(argv, cwd=repo, stdout=log, stderr=subprocess.STDOUT)
receipt['analysis_command'] = argv
receipt['analysis_status'] = result.returncode
assert result.returncode == 0
assert sha(guard_path) == guard_hash
assert all(sha(Path(p)) == digest for p, digest in guards.items())
assert sha(Path(__file__)) == receipt['worker_sha256']
doc = json.loads((work / 'measurements/wall.json').read_text())
receipt.update(complete=True, wall_rows=len(doc['samples']), all_inputs_unchanged=True,
               command_sha256=sha(command), raw_sha256=sha(work / 'measurements/wall.json'),
               analysis_sha256=sha(work / 'wall-analysis.json'),
               finished_utc=datetime.now(timezone.utc).isoformat())
out.write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt), flush=True)
