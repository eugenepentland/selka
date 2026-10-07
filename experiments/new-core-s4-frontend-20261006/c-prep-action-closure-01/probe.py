#!/usr/bin/env python3
"""Observational LLVM-only input traces; this is not closure certification."""
import hashlib
import json
import os
import shutil
import signal
import subprocess
from pathlib import Path

ROOT = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-frontend')
EVIDENCE = ROOT / 'experiments/new-core-s4-frontend-20261006/c-prep-action-closure-01'
WORK = ROOT / '.mylang-cache/s4-frontend/c-prep-action-closure-01'
SOURCE = ROOT / 'experiments/new-core-s4-frontend-20261006/c-prep-e-debug-cwd-01/actual-unit.ll'
TOOL = Path('/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig')
EXPECTED = '1c40b584bc71793ebd6e8a1d597b03c65677dd33857bed2370293efed1363e48'
BASENAME = 'canonical-' + EXPECTED + '.ll'
BASE = [str(TOOL), 'cc', '-c', '-O0', '-target', 'x86_64-linux-gnu.2.31',
        '-march=native', '-mllvm', '-x86-experimental-pref-innermost-loop-alignment=6',
        '-Wno-override-module']
TRACE = ['strace', '-f', '-yy', '-s', '4096', '-e',
         'trace=%file,read,pread64,mmap,getdents64,getcwd,close']
ENV_KEYS = ('HOME', 'PATH', 'XDG_CACHE_HOME', 'ZIG_LIB_DIR', 'ZIG_LIBC',
            'CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'LIBRARY_PATH',
            'SDKROOT', 'CLANG_CONFIG_FILE_SYSTEM_DIR', 'CLANG_CONFIG_FILE_USER_DIR')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(name, extra):
    private = WORK / name
    private.mkdir(parents=True)
    shutil.copy2(SOURCE, private / BASENAME)
    env = os.environ.copy()
    env['ZIG_LOCAL_CACHE_DIR'] = str(private / 'zig-local')
    env['ZIG_GLOBAL_CACHE_DIR'] = str(private / 'zig-global')
    command = BASE + extra + ['-o', 'fresh.o', BASENAME]
    traced = TRACE + ['-o', str(EVIDENCE / (name + '.strace'))] + command
    process = subprocess.Popen(traced, cwd=private, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=True)
    timeout = False
    try:
        out, err = process.communicate(timeout=120)
    except subprocess.TimeoutExpired:
        timeout = True
        os.killpg(process.pid, signal.SIGTERM)
        out, err = process.communicate(timeout=10)
    (EVIDENCE / (name + '.stdout')).write_bytes(out)
    (EVIDENCE / (name + '.stderr')).write_bytes(err)
    obj = private / 'fresh.o'
    receipt = {'command': command, 'trace_command': traced, 'cwd': str(private),
               'status': process.returncode, 'timeout': timeout,
               'input_sha256': sha(private / BASENAME), 'tool_sha256': sha(TOOL),
               'object': {'size': obj.stat().st_size, 'sha256': sha(obj)} if obj.exists() else None,
               'environment': {key: env.get(key) for key in ENV_KEYS},
               'native_caches': {key: env[key] for key in ('ZIG_LOCAL_CACHE_DIR', 'ZIG_GLOBAL_CACHE_DIR')},
               'scope': 'Observed filesystem accesses; no timing or complete-closure claim.'}
    (EVIDENCE / (name + '.json')).write_text(json.dumps(receipt, indent=2) + '\n')
    print(name, process.returncode, receipt['object'], flush=True)
    return receipt


if __name__ == '__main__':
    assert sha(SOURCE) == EXPECTED
    rows = [run('baseline', []), run('no-default-config', ['--no-default-config']),
            run('no-header-search', ['-nostdinc', '-nostdinc++']),
            run('depfile', ['-MD', '-MF', 'unit.d']), run('driver-argv', ['-###'])]
    for name in ('depfile',):
        dep = WORK / name / 'unit.d'
        if dep.exists():
            shutil.copy2(dep, EVIDENCE / (name + '.d'))
    (EVIDENCE / 'summary.json').write_text(json.dumps(rows, indent=2) + '\n')
