"""One-time migration of the paused PCB checkout; refuses occupied destinations."""
from pathlib import Path
import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import time

stage = Path('/tmp/pcb-shared-cache-20260921/stage')
legacy = Path('/home/epentland/ai/canopy/pcb-workbench/.workbench')
store = Path(subprocess.check_output([str(stage/'tools/workbench-store.py'), 'state'], text=True).strip())
pin = json.loads((stage/'workbench.json').read_text())['toolchain']
start = time.monotonic()
report = []
with (store/'.migration.lock').open('a') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    for source, destination in [(legacy/'snapshots', store/'snapshots'),
                                (legacy/'builds', store/'builds'),
                                (legacy/'cache/build', store/'cache'/pin/'build'),
                                (legacy/'cache/tests', store/'cache'/pin/'tests')]:
        if not source.exists():
            continue
        assert not destination.exists(), f'will not replace an existing shared namespace: {destination}'
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = Path(tempfile.mkdtemp(prefix='.seed-', dir=destination.parent))
        try:
            shutil.copytree(source, temporary/'data', symlinks=False)
            os.rename(temporary/'data', destination)
        finally:
            shutil.rmtree(temporary)
        report.append({'source':str(source), 'destination':str(destination)})
print(json.dumps({'seconds':time.monotonic()-start,'copied':report}, indent=2))
