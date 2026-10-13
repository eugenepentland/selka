#!/usr/bin/env python3
"""Run the pinned measurer within one admitted lease; kill only owned guest groups."""
import json
from pathlib import Path
import runpy
import signal
import subprocess
import sys

HERE = Path(__file__).resolve().parent
children = []
original_popen = subprocess.Popen


def tracked_popen(*args, **kwargs):
    child = original_popen(*args, **kwargs)
    children.append(child)
    return child


def stop(signum, frame):
    for child in children:
        if child.poll() is None:
            try:
                import os
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()
    raise SystemExit(124)


spec, output = sys.argv[1:]
plan_path = HERE.parent / 'followup-004/held-timing-plan.json'
plan = json.loads(plan_path.read_text())
row = next(r for r in plan['cases'] if r['command'][5] == spec)
command = row['command']
assert command[6] == output
subprocess.Popen = tracked_popen
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGALRM, stop)
signal.alarm(55)
sys.argv = command[4:]
try:
    runpy.run_path(command[4], run_name='__main__')
finally:
    signal.alarm(0)
    for child in children:
        assert child.poll() is not None, child.pid
