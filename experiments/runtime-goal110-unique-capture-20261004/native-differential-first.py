#!/usr/bin/env python3
"""Untimed paired native capture checks, with exact streams/status/trap records."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = Path(__file__).with_name('native-fixture.my')
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--before-compiler', type=Path, required=True)
parser.add_argument('--after-compiler', type=Path, required=True)
parser.add_argument('--before-receipt', type=Path, required=True)
parser.add_argument('--after-receipt', type=Path, required=True)
parser.add_argument('--qbe', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)


def artifact(path):
    path = Path(path).resolve()
    return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'bytes': path.stat().st_size}


def execute(command, environment):
    done = subprocess.run(command, env=environment, cwd=ROOT, capture_output=True, timeout=300)
    return {'command': command, 'status': done.returncode, 'stdout': done.stdout.decode(),
            'stderr': done.stderr.decode()}


def expected(case):
    kind, index, count = case
    normalized = index + 2 if index < 0 else index
    if kind in (0, 1) or (kind in (2, 3, 8) and count > 0):
        if not 0 <= normalized < 2:
            return {'failure': 'R_INDEX_OUT_OF_BOUNDS'}
    values = [7, 11]
    if kind == 0:
        values[normalized] = count
        value = sum(values) + 1
        if not -(1 << 63) <= value < (1 << 63):
            return {'failure': 'R_INTEGER_OVERFLOW'}
    elif kind == 1:
        value = values[normalized] * 100 + 13
    elif kind in (2, 3, 8):
        total = 0
        for at in range(max(0, count)):
            old = values[normalized]
            values[normalized] += at + 1
            if kind != 8:
                values[normalized] %= 1000003
                total += values[normalized] + (old if kind == 3 else 0)
        value = sum(values) + total
    else:
        value = {4: 13, 5: 33, 6: 13, 7: 36}[kind]
    return {'value': value, 'status': value & 255, 'stdout': f'41\n{value}\n'}


spec = importlib.util.spec_from_file_location('compiler_receipt', ROOT / 'benchmarks/runtime/build_compiler.py')
compiler_receipt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler_receipt)
receipts = {}
for label, host, path in (('before', args.before_compiler, args.before_receipt),
                          ('after', args.after_compiler, args.after_receipt)):
    receipt = json.loads(path.read_text())
    compiler_receipt.validate_receipt(receipt, host, artifacts=True)
    receipts[label] = {'artifact': artifact(path), 'receipt': receipt}


configs = [('rc-v5', backend, accounted) for backend in ('qbe', 'llvm') for accounted in (False, True)]
configs += [(runtime, 'llvm', False) for runtime in ('rc-v5-counting', 'rc-v5-sites', 'gc-v1')]
cases = [(0, index, count) for index in (-3, -2, -1, 0, 1, 2)
         for count in (-19, 0, 13, 9223372036854775807)]
cases += [(1, index, 0) for index in (-3, -2, -1, 0, 1, 2)]
cases += [(kind, index, count) for kind in (2, 3, 8) for index in (-3, -2, -1, 0, 1, 2)
          for count in (-1, 0, 1, 3, 7)]
cases += [(kind, 0, 0) for kind in (4, 5, 6, 7)]
report = {'kind': 'untimed-paired-native-unique-capture-differential',
          'source_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
          'production_source_hashes': {name: artifact(ROOT / name)['sha256'] for name in
              ('src/qbe_rc_unique_capture.zig', 'src/qbe_rc_locals.zig')},
          'compilers': {label: artifact(host) for label, host in
              (('before', args.before_compiler), ('after', args.after_compiler))},
          'compiler_receipts': receipts,
          'tools': {'qbe': artifact(args.qbe), 'zig': artifact(shutil.which('zig'))},
          'fixture': artifact(FIXTURE), 'runner': artifact(Path(__file__)),
          'builds': [], 'comparisons': [], 'limits': 'Correctness only; no runtime timing or acceptance claim.'}
try:
    for runtime, backend, accounted in configs:
        key = f'{runtime}-{backend}-accounted{int(accounted)}'
        binaries = {}
        for label, host in (('before', args.before_compiler), ('after', args.after_compiler)):
            work = output / key / label
            work.mkdir(parents=True, exist_ok=True)
            (work / 'tmp').mkdir(exist_ok=True)
            binary = work / 'guest'
            environment = {**os.environ, 'MYLANG_RUNTIME': runtime, 'TMPDIR': str(work / 'tmp'),
                           'ZIG_LOCAL_CACHE_DIR': str(work / 'zig-local'),
                           'ZIG_GLOBAL_CACHE_DIR': str(output / 'zig-global')}
            environment.pop('MYLANG_OPTIONS', None)
            command = [str(ROOT / 'scripts/build-slot.sh'), 'build', str(host.resolve()), 'build',
                       str(FIXTURE), '-o', str(binary), '--cache-dir', str(work / 'cache'),
                       '--zig', shutil.which('zig'), '--qbe', str(args.qbe.resolve()),
                       '--mode', 'ReleaseFast', '--backend', backend, '--keep-symbols']
            if backend == 'llvm':
                command += ['--llvm-opt', '3', '--lto']
            if accounted:
                command += ['--step-accounting', '--max-frames=10000']
            result = execute(command, environment)
            (work / 'build.json').write_text(json.dumps(result, indent=2) + '\n')
            assert result['status'] == 0, result
            report['builds'].append({'config': key, 'arm': label, 'result': result,
                                     'binary': artifact(binary)})
            binaries[label] = binary
        for case in cases:
            outcomes = {}
            for label, binary in binaries.items():
                environment = {**os.environ, 'MYLANG_OPTIONS': '--print-result'}
                if runtime == 'gc-v1':
                    environment['MYLANG_OPTIONS'] += ' --gc-stress'
                outcomes[label] = execute([str(binary), *map(str, case)], environment)
            before, after = outcomes['before'], outcomes['after']
            assert all(before[field] == after[field] for field in ('status', 'stdout', 'stderr')), (key, case, outcomes)
            assert after['stdout'].startswith('41\n'), (key, case, after)
            oracle = expected(case)
            if 'failure' in oracle:
                assert after['status'] != 0 and after['stdout'] == '41\n', (key, case, oracle, after)
            else:
                assert all(after[field] == oracle[field] for field in ('status', 'stdout')), (key, case, oracle, after)
            if case[0] == 5:
                assert after['status'] == 33 and after['stdout'] == '41\n33\n', after
                if runtime in ('rc-v5-counting', 'rc-v5-sites'):
                    counts = next(line for line in after['stderr'].splitlines() if line.startswith('MYLANG_RC_COUNTS '))
                    assert json.loads(counts.split(' ', 1)[1])['hold_acquire'] > 0, counts
            report['comparisons'].append({'config': key, 'case': case, 'oracle': oracle, 'outcomes': outcomes})
        if accounted:
            for options in ('--print-result --max-steps=1', '--print-result --max-frames=1'):
                outcomes = {label: execute([str(binary), '0', '0', '13'],
                                           {**os.environ, 'MYLANG_OPTIONS': options})
                            for label, binary in binaries.items()}
                assert all(outcomes['before'][field] == outcomes['after'][field]
                           for field in ('status', 'stdout', 'stderr')), (key, options, outcomes)
                report['comparisons'].append({'config': key, 'runtime_options': options, 'outcomes': outcomes})
    report['status'] = 'passed'
finally:
    report['comparison_count'] = len(report['comparisons'])
    report['execution_count'] = 2 * len(report['comparisons'])
    (output / 'native-differential.json').write_text(json.dumps(report, indent=2) + '\n')
print(f"{report['comparison_count']} paired comparisons / {report['execution_count']} native executions passed")
