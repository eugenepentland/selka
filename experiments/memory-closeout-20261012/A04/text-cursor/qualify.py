#!/usr/bin/env python3
"""Compare actual Unicode lookup walks and counters on the unchanged scan source."""
import argparse
import hashlib
import importlib.util
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
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compiler', type=Path, required=True)
parser.add_argument('--zig', type=Path, required=True)
parser.add_argument('--phase', required=True)
parser.add_argument('--source-commit', required=True)
parser.add_argument('--expect-cursor', action='store_true')
args = parser.parse_args()
args.compiler = args.compiler.resolve()
args.zig = args.zig.resolve()
output = ROOT / '.tmp/memory-closeout/A04/text-cursor' / args.phase
evidence = HERE / args.phase
assert not evidence.exists(), 'use a new phase'
evidence.mkdir()
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
spec = importlib.util.spec_from_file_location('prior_qualification', ROOT / 'experiments/zero-rc-closeout-20261011/qualify.py')
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
source = HERE / 'moving-scans.my'
report = {'compiler': str(args.compiler), 'compiler_sha256': digest(args.compiler), 'source_commit': args.source_commit,
          'fixture_sha256': digest(source), 'harness_sha256': digest(Path(__file__)), 'expect_cursor_bound': args.expect_cursor, 'lanes': {},
          'limitations': 'Instrumented correctness and walked-octet/allocation counts only; no runtime or RSS claim.'}
env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK='1', MYL_CORE_TEXTWALK='1',
           MYLANG_CORE_RUNTIME_CACHE=str(output / 'runtime-cache'))
for key in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
    env.pop(key, None)
failures = 0
lanes = [('ordinary-default', []), ('ordinary-release', ['--release'])]
lanes += [('checked-' + mode, ['--experimental-zero-rc', *flags]) for mode, flags in q.common.MODES.items()]
for start in range(0, len(lanes), 4):
    with admission('build'):
        for name, flags in lanes[start:start + 4]:
            directory = output / name
            directory.mkdir(parents=True)
            binary, llvm, counts = (directory / name for name in ('program', 'program.ll', 'counts.json'))
            row = {}
            try:
                built = q.call([args.compiler, 'build', source, '--zig', args.zig, '--cache-dir', output / 'cache', *flags, '--counters', '-o', binary, '--emit-llvm', llvm], env, directory, 'build')
                assert 'error(SafeAllocator)' not in built['stderr']
                ran = q.call([binary], dict(env, MYLANG_COUNTERS=str(counts)), directory, 'run')
                assert ran['stdout'] == '404706899 286015030\n', ran
                match = re.fullmatch(r'myl-core textwalk: (\d+) octets\n', ran['stderr'])
                assert match, ran
                walked = int(match.group(1))
                audit = q.common.audit.audit(counts)
                assert audit['managed_leak_free'], audit
                if name.startswith('checked-'):
                    q.prior.clean_ir(llvm)
                    symbols = subprocess.check_output(['nm', str(binary)], text=True)
                    assert not any(symbol in symbols for symbol in ('myl_core_retain', 'myl_core_release', 'myl_core_share'))
                    assert audit['observed_rc_free'], audit
                row = {'walked_octets': walked, 'under_original_bound': walked < 4000000, 'audit': audit,
                       'memory': q.common.census.summarize(json.loads(counts.read_text()))['whole_program'],
                       'binary_sha256': digest(binary), 'llvm_sha256': digest(llvm)}
                if args.expect_cursor:
                    assert walked < 4000000, row
                row['status'] = 'passed'
            except (AssertionError, subprocess.SubprocessError, OSError) as error:
                row.update(status='failed', error=str(error))
                failures += 1
            target = evidence / 'raw' / name
            target.mkdir(parents=True)
            for pattern in ('*.json', '*.stdout', '*.stderr'):
                for artifact in directory.glob(pattern):
                    shutil.copyfile(artifact, target / artifact.name)
            report['lanes'][name] = row
            (evidence / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
            print(name, row['status'], row.get('walked_octets'), flush=True)
assert digest(args.compiler) == report['compiler_sha256']
report['summary'] = {'failed': failures, 'lanes': len(lanes)}
(evidence / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
raise SystemExit(bool(failures))
