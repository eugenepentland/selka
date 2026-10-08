#!/usr/bin/env python3
"""Untimed native floor-result range qualification with complete paired streams."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import random
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = Path(__file__).with_name('native-fixture.my')
MINIMUM, MAXIMUM, MODULUS = -(1 << 63), (1 << 63) - 1, 1000000007
parser = argparse.ArgumentParser(description=__doc__)
for name in ('before-compiler', 'after-compiler', 'before-receipt', 'after-receipt', 'output'):
    parser.add_argument('--' + name, type=Path, required=True)
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)


def artifact(path):
    path = Path(path).resolve()
    return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'bytes': path.stat().st_size}


def environment(**updates):
    result = {key: value for key, value in os.environ.items()
              if key not in ('MYLANG_OPTIONS', 'MYLANG_MEMORY_LIMIT', 'MYLANG_RUNTIME', 'MYLANG_LLVM_DUMP')}
    result.update(updates)
    return result


def execute(command, env):
    done = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=600)
    return {'command': command, 'status': done.returncode, 'stdout': done.stdout, 'stderr': done.stderr}


def checked(value):
    if not MINIMUM <= value <= MAXIMUM:
        raise OverflowError
    return value


def oracle(case):
    kind, value, other, phase = case
    try:
        if kind <= 4:
            result = value % (1, 2, 3, MODULUS, MAXIMUM)[kind]
        elif kind == 5:
            result = abs(value) % 3 * (-1 if value < 0 else 1)
        elif kind == 6:
            result = value % -3
        elif kind == 7:
            result = value % other
        elif kind in (8, 9, 10):
            result = 0 if kind == 8 else value
            for at in range(max(0, other)):
                increment = (-17 if at % 3 == 0 else 23) if kind == 10 else int(at % 2 == phase)
                result = checked(result + increment) % MODULUS
        elif kind == 11:
            result = checked(value + other) % 3
        elif kind == 12:
            raise ZeroDivisionError
        elif kind == 13:
            result = 0
        else:
            result = value
            for _ in range(max(0, other)):
                result = checked(result - 17) % MODULUS
        return {'value': result, 'status': 0, 'stdout': f'41\n{result}\n43\n0\n'}
    except OverflowError:
        return {'failure': 'R_OVERFLOW'}
    except ZeroDivisionError:
        return {'failure': 'R_DIVISION_BY_ZERO'}


spec = importlib.util.spec_from_file_location('compiler_receipt', ROOT / 'benchmarks/runtime/build_compiler.py')
receipt_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(receipt_module)
hosts, receipts = {}, {}
for label in ('before', 'after'):
    hosts[label] = getattr(args, label + '_compiler').resolve()
    path = getattr(args, label + '_receipt').resolve()
    receipt = json.loads(path.read_text())
    receipt_module.validate_receipt(receipt, hosts[label], artifacts=True)
    receipts[label] = {'artifact': artifact(path), 'receipt': receipt}

values = [MINIMUM, MINIMUM + 1, -2 * MODULUS, -MODULUS - 1, -MODULUS, -MODULUS + 1,
          -7, -3, -2, -1, 0, 1, 2, 3, 7, MODULUS - 1, MODULUS, MODULUS + 1, MAXIMUM - 1, MAXIMUM]
randomizer = random.Random(20261004)
values += [randomizer.randrange(MINIMUM, MAXIMUM + 1) for _ in range(8)]
cases = [(kind, value, 0, 0) for kind in range(7) for value in values]
cases += [(7, value, divisor, 0) for value in (MINIMUM, -7, 0, 7, MAXIMUM)
          for divisor in (MINIMUM, -3, -1, 0, 1, 3, MAXIMUM)]
cases += [(8, 0, count, phase) for count in (-1, 0, 1, 2, 17) for phase in (-1, 0, 1, 2)]
cases += [(kind, seed, count, phase) for kind in (9, 10)
          for seed in (MINIMUM, -MODULUS - 1, -1, 0, MODULUS - 1, MAXIMUM)
          for count in (-1, 0, 1, 17) for phase in (0, 1)]
cases += [(11, value, increment, 0) for value in (MINIMUM, -1, 0, 1, MAXIMUM)
          for increment in (-1, 0, 1)]
cases += [(kind, value, 0, 0) for kind in (12, 13) for value in (MINIMUM, -7, 0, 7, MAXIMUM)]
cases += [(14, value, depth, 0) for value in (MINIMUM, -MODULUS - 1, -1, 0, MAXIMUM)
          for depth in (-1, 0, 1, 7)]
configs = [('rc-v5', backend, accounted) for backend in ('llvm', 'qbe') for accounted in (False, True)]
configs += [(runtime, 'llvm', False) for runtime in ('rc-v5-counting', 'rc-v5-sites', 'gc-v1')]
report = {'kind': 'untimed-floor-result-range-native-differential', 'started_utc': datetime.now(timezone.utc).isoformat(),
          'source_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
          'fixture': artifact(FIXTURE), 'runner': artifact(Path(__file__)), 'compiler_receipts': receipts,
          'tools': {'zig': artifact(shutil.which('zig')), 'wrapper': artifact(ROOT / 'scripts/build-slot.sh')},
          'builds': [], 'comparisons': [], 'status': 'running', 'limitation': 'Untimed diagnostic Debug host; ReleaseFast O3 full-LTO guests. No runtime performance acceptance.'}


def paired(key, binaries, case, updates, expected=None):
    outcomes = {label: execute([str(binary), *map(str, case)], environment(**updates))
                for label, binary in binaries.items()}
    record = {'config': key, 'case': case, 'environment': updates, 'oracle': expected, 'outcomes': outcomes}
    report['comparisons'].append(record)
    before, after = outcomes['before'], outcomes['after']
    assert all(before[field] == after[field] for field in ('status', 'stdout', 'stderr')), record
    if expected and 'failure' in expected:
        assert after['status'] != 0 and after['stdout'] == '41\n', record
        assert 'error[' + expected['failure'] + ']' in after['stderr'], record
    elif expected:
        assert all(after[field] == expected[field] for field in ('status', 'stdout')), record
    elif updates.get('MYLANG_MEMORY_LIMIT') == '1':
        assert after['status'] == 1 and after['stdout'] == '', record
        assert after['stderr'].endswith('R_MEMORY_BUDGET: memory budget exhausted\n'), record
    else:
        assert after['status'] != 0 and 'error[' in after['stderr'], record


try:
    for runtime, backend, accounted in configs:
        key = f'{runtime}-{backend}-accounted{int(accounted)}'
        binaries = {}
        for label, host in hosts.items():
            work = output / key / label
            for name in ('tmp', 'dump'):
                (work / name).mkdir(parents=True, exist_ok=True)
            binary = work / 'guest'
            env = environment(MYLANG_RUNTIME=runtime, TMPDIR=str(work / 'tmp'),
                              ZIG_LOCAL_CACHE_DIR=str(work / 'zig-local'), ZIG_GLOBAL_CACHE_DIR=str(output / 'zig-global'))
            if backend == 'llvm':
                env['MYLANG_LLVM_DUMP'] = str(work / 'dump')
            command = [str(ROOT / 'scripts/build-slot.sh'), 'build', str(host), 'build', str(FIXTURE),
                       '-o', str(binary), '--cache-dir', str(work / 'cache'), '--zig', shutil.which('zig'),
                       '--qbe', str(host.parent / 'qbe'), '--mode', 'ReleaseFast', '--backend', backend, '--keep-symbols']
            if backend == 'llvm':
                command += ['--llvm-opt', '3', '--lto']
            if accounted:
                command += ['--step-accounting', '--max-frames=10000']
            result = execute(command, env)
            (work / 'build.json').write_text(json.dumps(result, indent=2) + '\n')
            assert result['status'] == 0, result
            manifest_path = Path(str(binary) + '.qbe-manifest.json')
            manifest = json.loads(manifest_path.read_text())
            assert manifest['backend'] == backend, manifest
            if backend == 'llvm':
                assert manifest['optimization'] == '3' and manifest['lto'] and not manifest['thin_lto'], manifest
            report['builds'].append({'config': key, 'arm': label, 'result': result, 'binary': artifact(binary),
                                     'manifest': artifact(manifest_path), 'environment': {name: env[name] for name in
                                     ('MYLANG_RUNTIME', 'TMPDIR', 'ZIG_LOCAL_CACHE_DIR', 'ZIG_GLOBAL_CACHE_DIR')}})
            binaries[label] = binary
        updates = {'MYLANG_OPTIONS': '--print-result' + (' --gc-stress' if runtime == 'gc-v1' else '')}
        for case in cases:
            paired(key, binaries, case, updates, oracle(case))
        if accounted:
            for steps in (1, 40, 120):
                paired(key, binaries, (9, -7, 17, 1), {'MYLANG_OPTIONS': f'--print-result --max-steps={steps}'})
            for frames in (1, 2, 4):
                paired(key, binaries, (14, -7, 7, 0), {'MYLANG_OPTIONS': f'--print-result --max-frames={frames}'})
        paired(key, binaries, (3, -7, 0, 0), {**updates, 'MYLANG_MEMORY_LIMIT': '1'})
        print(f'PASS {key}: {len(cases)} oracle pairs plus boundary probes', flush=True)
    for label, host in hosts.items():
        receipt_module.validate_receipt(receipts[label]['receipt'], host, artifacts=True)
    report['status'] = 'passed'
finally:
    report['finished_utc'] = datetime.now(timezone.utc).isoformat()
    report['comparison_count'] = len(report['comparisons'])
    report['execution_count'] = 2 * len(report['comparisons'])
    (output / 'native-differential.json').write_text(json.dumps(report, indent=2) + '\n')
print(f"PASS {report['comparison_count']} pairs / {report['execution_count']} executions")
