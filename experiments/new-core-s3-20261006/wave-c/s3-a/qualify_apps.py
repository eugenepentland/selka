#!/usr/bin/env python3
"""Strictly compare split apps with the unchanged old-core benchmark programs.

Build debug, release and fact-verifying new apps from this worktree. Each native
run must exit zero, print exactly the checksum/elapsed record, and have empty
stderr even with MYL_CORE_LEAKCHECK=1. Original, split old and all three new modes
must agree. Build logs and native process records are retained under --evidence.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[4]
SPEC = importlib.util.spec_from_file_location('rows40', Path(__file__).with_name('measure_all40.py'))
ROWS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ROWS)
APPLICATIONS = ('word_count', 'csv_aggregate', 'json_transform', 'packet_decode', 'lox_eval')


def build(compiler, source, output, cache, mode, evidence, name):
    command = [str(compiler), 'build', str(source), '-o', str(output), '--cache-dir', str(cache),
               '--link', str(ROOT / 'benchmarks/runtime/ports/native_clock.c')]
    if mode != 'debug':
        command.append('--release')
    if mode == 'verify':
        command.append('--verify-facts')
    started = time.monotonic()
    done = subprocess.run(command, capture_output=True, text=True)
    record = {'command': command, 'status': done.returncode, 'seconds': time.monotonic() - started,
              'stdout': done.stdout, 'stderr': done.stderr}
    (evidence / f'build-{name}.json').write_text(json.dumps(record, indent=2) + '\n')
    if done.returncode or not output.is_file():
        raise ROWS.InvalidMeasurement(f'build failed: {name}: {record}')
    print(f'build {name}: pass ({record["seconds"]:.3f}s)', flush=True)
    return record


def run(binary, argv, leakcheck=False):
    command = [str(binary), *map(str, argv)]
    env = {**os.environ, 'LC_ALL': 'C'}
    if leakcheck:
        env['MYL_CORE_LEAKCHECK'] = '1'
    done = subprocess.run(command, capture_output=True, text=True, env=env)
    record = {'command': command, 'status': done.returncode, 'stdout': done.stdout, 'stderr': done.stderr,
              'leakcheck': leakcheck}
    if done.returncode or done.stderr:
        raise ROWS.InvalidMeasurement(f'native failed, crashed, leaked or violated a fact: {record}')
    record['checksum'], record['elapsed_ns'] = ROWS.parse_stdout(done.stdout)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bin', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--mylang', type=Path, default=ROOT / '.mylang-cache/s3-a/oracle/mylang')
    parser.add_argument('--core', type=Path, default=ROOT / 'zig-out/bin/mylang-core')
    args = parser.parse_args()
    args.bin = ROWS.inside(args.bin)
    args.evidence = ROWS.inside(args.evidence)
    if args.evidence.exists():
        raise SystemExit('use a fresh evidence directory; prior evidence is never overwritten')
    args.bin.mkdir(parents=True, exist_ok=True)
    args.evidence.mkdir(parents=True)
    report = {'qualified': False, 'source_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
              'builds': {}, 'rows': {}, 'stdlib': [], 'native_executions': 0, 'error': None}
    try:
        suites = ('text', 'compute', 'collections')
        for suite in suites:
            report['builds'][f'original-{suite}'] = build(
                args.mylang, ROOT / f'benchmarks/runtime/expanded/{suite}/main.my',
                args.bin / f'original-{suite}', args.bin / 'cache-old', 'release', args.evidence, f'original-{suite}')
        # The unchanged text entry reaches strings.repeat and the complete JSON
        # module. Exercise both imports explicitly, including in verified mode.
        for mode in ('debug', 'release', 'verify'):
            name = f'original-text-new-{mode}'
            report['builds'][name] = build(args.core, ROOT / 'benchmarks/runtime/expanded/text/main.my',
                args.bin / name, args.bin / 'cache-new', mode, args.evidence, name)
            for row in ('string_equal', 'json_transform'):
                original = run(args.bin / 'original-text', [row, 64, 3, 7])
                checked = run(args.bin / name, [row, 64, 3, 7], True)
                report['native_executions'] += 2
                if original['checksum'] != checked['checksum']:
                    raise ROWS.InvalidMeasurement(f'standard-library mismatch {row}/{mode}: {original}, {checked}')
                report['stdlib'].append({'row': row, 'mode': mode, 'old': original, 'new': checked})
        print('unchanged text entry: import strings and import json match old with strict leaks in all three modes', flush=True)
        for row in APPLICATIONS:
            source = ROOT / f'test/core/row_{row}.my'
            for mode in ('old', 'debug', 'release', 'verify'):
                name = f'{row}-{mode}'
                report['builds'][name] = build(args.mylang if mode == 'old' else args.core, source,
                    args.bin / name, args.bin / ('cache-old' if mode == 'old' else 'cache-new'),
                    'release' if mode == 'old' else mode, args.evidence, name)
            records = []
            for size, iterations, seed in ((2, 1, 7), (64, 3, 7), (65, 1, 17), (4096, 1, 7), (4100, 3, 17)):
                original = run(args.bin / f'original-{ROWS.UNITS[row][0]}', [row, size, iterations, seed])
                values = {'original-old': original}
                for mode in ('old', 'debug', 'release', 'verify'):
                    values[mode] = run(args.bin / f'{row}-{mode}', [size, iterations, seed], mode != 'old')
                report['native_executions'] += len(values)
                if len({value['checksum'] for value in values.values()}) != 1:
                    raise ROWS.InvalidMeasurement(f'original/split/mode checksum disagreement {row}/{size}: {values}')
                records.append({'size': size, 'iterations': iterations, 'seed': seed, 'runs': values})
            report['rows'][row] = records
            print(f'{row}: original/split old and debug/release/verify agree; strict leak/status/stdout checks pass', flush=True)
        report['qualified'] = True
        print(f'qualified {len(report["rows"])} apps; {report["native_executions"]} native executions', flush=True)
        return 0
    except (ROWS.InvalidMeasurement, OSError, ValueError) as error:
        report['error'] = str(error)
        print(f'application qualification FAILED: {error}', file=sys.stderr, flush=True)
        return 1
    finally:
        (args.evidence / 'summary.json').write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())
