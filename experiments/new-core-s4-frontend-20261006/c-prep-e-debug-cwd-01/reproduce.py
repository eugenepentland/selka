#!/usr/bin/env python3
"""Compare actual E LLVM bytes under identical basenames and different cwd."""
import hashlib
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-frontend')
EVIDENCE = ROOT / 'experiments/new-core-s4-frontend-20261006/c-prep-e-debug-cwd-01'
WORK = ROOT / '.mylang-cache/s4-frontend/c-prep-e-debug-cwd-01'
IDENTITY = json.loads((EVIDENCE / 'input-identity.json').read_text())
SOURCE = EVIDENCE / 'actual-unit.ll'
TOOL = IDENTITY['zig']


def save(name, value):
    (EVIDENCE / name).write_text(json.dumps(value, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(name, command, directory, environment):
    started = time.monotonic()
    result = subprocess.run(command, cwd=directory, env=environment,
                            capture_output=True, timeout=90)
    (EVIDENCE / (name + '.stdout')).write_bytes(result.stdout)
    (EVIDENCE / (name + '.stderr')).write_bytes(result.stderr)
    receipt = {'command': command, 'cwd': str(directory),
               'status': result.returncode, 'seconds': time.monotonic() - started,
               'native_cache_dirs': {key: environment[key] for key in
                   ('ZIG_LOCAL_CACHE_DIR', 'ZIG_GLOBAL_CACHE_DIR')}}
    save(name + '.json', receipt)
    return receipt


def pair(label, extra):
    rows = []
    for side in ('a', 'b'):
        private = WORK / (label + '-' + side)
        private.mkdir()
        unit = private / IDENTITY['canonical_basename']
        shutil.copy2(SOURCE, unit)
        assert digest(unit) == IDENTITY['input_sha256']
        environment = os.environ.copy()
        environment['ZIG_LOCAL_CACHE_DIR'] = str(private / 'zig-local')
        environment['ZIG_GLOBAL_CACHE_DIR'] = str(private / 'zig-global')
        # Preserve every semantic native flag from the actual E object recipe.
        original = json.loads((EVIDENCE / 'original-e-compile-receipt.json').read_text())['command']
        argv = [TOOL] + original[1:original.index('-o')] + extra + [
            '-o', 'fresh.o', unit.name]
        row = run(label + '-' + side, argv, private, environment)
        row['input'] = {'path': str(unit), 'sha256': digest(unit)}
        assert row['status'] == 0
        obj = private / 'fresh.o'
        row['object'] = {'path': str(obj), 'size': obj.stat().st_size,
                         'sha256': digest(obj)}
        inspection = subprocess.run(['readelf', '--debug-dump=info', str(obj)],
                                     capture_output=True, timeout=30)
        (EVIDENCE / (label + '-' + side + '.debug-info')).write_bytes(inspection.stdout)
        assert inspection.returncode == 0
        save(label + '-' + side + '.json', row)
        rows.append(row)
    identical = Path(rows[0]['object']['path']).read_bytes() == Path(rows[1]['object']['path']).read_bytes()
    value = {'identical': identical, 'rows': rows, 'extra_flags': extra}
    save(label + '-summary.json', value)
    print(label, 'identical', identical, [row['object']['sha256'] for row in rows], flush=True)
    return value


assert digest(SOURCE) == IDENTITY['input_sha256']
assert digest(Path(TOOL)) == IDENTITY['zig_sha256']
original = pair('original-flags', [])
summary = {'original_flags': original, 'scope': 'Byte correctness only; no timing qualification.'}
if not original['identical']:
    # The logical compile directory is stable and independent of staging cwd.
    # Keep the real original invocation root, preserving relative source lookup.
    stable = '/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-emission'
    summary['stable_compile_directory'] = pair('stable-debug-directory', [
        '-fdebug-compilation-dir=' + stable])
save('summary.json', summary)
