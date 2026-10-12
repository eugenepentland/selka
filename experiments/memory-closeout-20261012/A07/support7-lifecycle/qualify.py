#!/usr/bin/env python3
"""Counted lifecycle qualification; this is not a timing or RSS measurement."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_admission import admission

COMPILER = Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support7-install/bin/mylang')
EXPECTED_COMPILER = '540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef'
SOURCE_COMMIT = 'bed11cf3bf3102ffec44487e431a1573fdf02ad5'
SOURCE = ROOT / 'src/core/a07_lifecycle_fixture.my'
OUTPUT = ROOT / '.tmp/memory-closeout/A07/support7-lifecycle/native'
EXPECTED = '43 18\nscope-47 36\npayload\nFalse\n'
MODES = {'release': ['--release'], 'debug': ['--unoptimized'],
         'verify': ['--release', '--verify-facts'], 'optimized_debug': ['--optimize-debug'],
         'no_facts': ['--release', '--no-facts']}
FORBIDDEN = ('myl_core_retain', 'myl_core_release', 'myl_core_share', 'myl_core_free_block',
             'count_retain', 'count_release', 'count_is_unique')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def call(argv, env, destination):
    result = subprocess.run(list(map(str, argv)), cwd=ROOT, env=env, capture_output=True, text=True, timeout=300)
    row = {'argv': list(map(str, argv)), 'status': result.returncode,
           'stdout': result.stdout, 'stderr': result.stderr}
    destination.write_text(json.dumps(row, indent=2) + '\n')
    return row


assert sha(COMPILER) == EXPECTED_COMPILER
assert not OUTPUT.exists(), 'preserve existing evidence; choose a new output path'
OUTPUT.mkdir(parents=True)
report = {'source_commit': SOURCE_COMMIT, 'compiler': str(COMPILER), 'compiler_sha256': sha(COMPILER),
          'fixture_sha256': sha(SOURCE), 'harness_sha256': sha(Path(__file__)), 'modes': {},
          'limitations': 'Supplemental semantic/counter/structural check. No timing, RSS, default-mode or retirement qualification.'}
env = dict(os.environ, MYLANG_ZIG=os.environ['ZIG'], MYL_CORE_LEAKCHECK='1')
for key in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
    env.pop(key, None)


def save():
    (HERE / 'results.json').write_text(json.dumps(report, indent=2) + '\n')


with admission('build'):
    for mode, flags in MODES.items():
        directory = OUTPUT / mode
        directory.mkdir()
        archive = HERE / 'raw' / mode
        archive.mkdir(parents=True)
        source = directory / 'main.my'
        shutil.copyfile(SOURCE, source)
        binary = directory / 'program'
        llvm = directory / 'program.ll'
        counts = directory / 'counts.json'
        row = {'status': 'failed', 'source_sha256': sha(source)}
        report['modes'][mode] = row
        try:
            build = call([COMPILER, 'build', source, '--zig', env['ZIG'], '--cache-dir', OUTPUT / 'cache',
                          '--experimental-zero-rc', '--counters', *flags, '-o', binary, '--emit-llvm', llvm],
                         env, archive / 'build.json')
            assert build['status'] == 0 and build['stderr'] == '', build
            run = call([binary], dict(env, MYLANG_COUNTERS=str(counts)), archive / 'run.json')
            assert run['status'] == 0 and run['stdout'] == EXPECTED and run['stderr'] == '', run
            data = json.loads(counts.read_text())
            for name in ('runtime_retains', 'runtime_releases', 'shared_retains', 'shared_releases', 'share_marks', 'live_bytes_at_exit'):
                assert data['totals'][name] == 0, (name, data['totals'][name])
            for name in ('retain', 'release', 'unique_test'):
                assert data['kinds'][name]['count'] == 0, (name, data['kinds'][name])
            assert data['totals']['allocs'] > 0
            assert data['kinds']['release_unique']['count'] > 0
            text = llvm.read_text()
            assert '; mylang-zero-rc-v2\n' in text
            assert not any('@' + name in text for name in FORBIDDEN)
            assert 'load atomic i32' not in text
            assert not re.search(r'store i32[^\n]*!tbaa !3', text)
            symbols = call(['nm', binary], env, archive / 'symbols.json')
            assert symbols['status'] == 0 and not any(name in symbols['stdout'] for name in FORBIDDEN)
            shutil.copyfile(counts, archive / 'counts.json')
            row.update(status='passed', binary_sha256=sha(binary), llvm_sha256=sha(llvm), counts_sha256=sha(counts),
                       totals=data['totals'], release_unique=data['kinds']['release_unique']['count'],
                       llvm_marker='mylang-zero-rc-v2', rc_symbols_absent=True)
        except (AssertionError, OSError, subprocess.SubprocessError) as error:
            row['error'] = str(error)
        save()
        print(mode, row['status'], flush=True)
assert sha(COMPILER) == EXPECTED_COMPILER
report['failed'] = sum(row['status'] != 'passed' for row in report['modes'].values())
save()
raise SystemExit(bool(report['failed']))
