#!/usr/bin/env python3
"""Acquire immutable identities and operational evidence; admission belongs to existing tools."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(os.environ.get('S10_SOURCE_ROOT', Path(__file__).resolve().parents[3])).resolve()
OUT = Path(os.environ.get('S10_OUTPUT_DIR', Path(__file__).resolve().parent / 'raw')).resolve()
OUT.mkdir(parents=True, exist_ok=True)
ZIG = Path('/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig')

def run(name, argv):
    started = time.monotonic()
    with (OUT / (name + '.log')).open('wb') as stream:
        result = subprocess.run(argv, cwd=ROOT, env=os.environ.copy(), stdout=stream, stderr=subprocess.STDOUT)
    value = {'argv': argv, 'cwd': str(ROOT), 'status': result.returncode,
             'elapsed_seconds_including_queue': time.monotonic() - started,
             'cache_environment': {key: os.environ.get(key) for key in ['ZIG_LOCAL_CACHE_DIR', 'ZIG_GLOBAL_CACHE_DIR', 'TMPDIR']}}
    (OUT / (name + '.command.json')).write_text(json.dumps(value, indent=2) + '\n')
    return result.returncode

if sys.argv[1] == 'identity':
    tree = subprocess.check_output(['git', 'ls-tree', '-r', 'HEAD'], cwd=ROOT)
    (OUT / 'C0-tree.txt').write_bytes(tree)
    info = {'C0': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'tree_sha256': hashlib.sha256(tree).hexdigest(), 'zig': str(ZIG),
            'zig_sha256': hashlib.file_digest(ZIG.open('rb'), 'sha256').hexdigest(),
            'zig_version': subprocess.check_output([str(ZIG), 'version'], text=True).strip(),
            'affinity': sorted(os.sched_getaffinity(0)),
            'cache_environment': {key: os.environ.get(key) for key in ['ZIG_LOCAL_CACHE_DIR', 'ZIG_GLOBAL_CACHE_DIR', 'TMPDIR', 'MYLANG_CORE_RUNTIME_CACHE', 'MYLANG_COMPILER_SHARED_CACHE']},
            'cache_state': 'fresh private local/project/verification; shared global/runtime not reset',
            'abi_source': 'C0 tree owns runtime/driver/ABI contract; exact tree archived',
            'baseline_modes': ['Debug', 'ReleaseFast']}
    (OUT / 'C0-identity.json').write_text(json.dumps(info, indent=2) + '\n')
elif sys.argv[1] == 'release':
    sys.exit(run('C0-release-build', ['scripts/build-slot.sh', 'build', str(ZIG), 'build', '-Doptimize=ReleaseFast', '--prefix', str(ROOT / '.tmp-s10/frozen-release')]))
elif sys.argv[1] == 'complete':
    sys.exit(run('C0-complete', [sys.executable, 'scripts/verify_cache.py', '--zig', str(ZIG), '--force']))
elif sys.argv[1] == 'fixture':
    binary = '/home/epentland/ai/canopy/mylang-dl-closeout-20261012-S06/.tmp/S06/discovery-profile-final'
    digest = 'd1cc599a0de7b362c243d9caedb2f73dedacb9d031406d78516bd08776c84f00'
    harness = str(Path(__file__).resolve().parent / 'timing_fixture.py')
    sys.exit(run('S06-discovery-window', ['scripts/build-slot.sh', 'timing', 'timeout', '30s', sys.executable, harness, binary, digest, str(OUT / 'S06-discovery')]))
else:
    raise SystemExit('expected identity/release/complete/fixture')
