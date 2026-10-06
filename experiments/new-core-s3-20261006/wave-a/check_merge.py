#!/usr/bin/env python3
"""Run S3's cheap gates on a committed merge, retaining one log per command.

The core rebuild holds every build slot plus the gate lock to exclude contention.
Output directories must be new; a failed run's evidence is never overwritten.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
RETAIN_GATE = '"$@"; result=$?; exit "$result"'


def git(root, *arguments):
    return subprocess.check_output(['git', *arguments], cwd=root, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--stage', required=True)
    parser.add_argument('--mylang', type=Path, required=True)
    parser.add_argument('--core-shards', type=int, default=8)
    args = parser.parse_args()
    root = args.root.resolve()
    area = root / 'experiments/new-core-s3-20261006/wave-a/integration' / args.stage
    area.mkdir(parents=True, exist_ok=False)
    cache = root / '.zig-cache/s3-wave-a' / args.stage
    (cache / 'tmp').mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, TMPDIR=str(cache / 'tmp'),
               ZIG_LOCAL_CACHE_DIR=str(root / '.zig-cache'),
               ZIG_GLOBAL_CACHE_DIR='/home/epentland/ai/canopy/.zig-global-cache')
    commit = git(root, 'rev-parse', 'HEAD')
    spec = importlib.util.spec_from_file_location(
        'old_gate', root / 'experiments/new-core-s2-20261005/wave-b/integration/full_old_gate.py')
    old_gate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(old_gate)
    old_gate.source_unchanged(root, commit)
    commands = [
        ('core-build', ['zig', 'build', 'core', '--summary', 'all']),
        ('test-core', ['zig', 'build', 'test-core',
                       f'-Dcore-shards={args.core_shards}', '--summary', 'all']),
        ('conformance', ['python3', str(root / 'experiments/new-core-s2-20261005/wave-b/integration/conformance_checked.py'),
                         '--set', 'all', '--jobs', '4', '--why', '--mylang',
                         str(args.mylang.resolve()), '--core', str(root / 'zig-out/bin/mylang-core'),
                         '--cache-dir', str(cache / 'conformance')]),
    ]
    summary = {'source_commit': commit, 'root': str(root), 'core_shards': args.core_shards,
               'results': [], 'qualified': False}
    try:
        for label, command in commands:
            old_gate.source_unchanged(root, commit)
            duration = area / f'{label}-seconds.txt'
            timed = ['/usr/bin/time', '-f', '%e', '-o', str(duration), *command]
            if label == 'core-build':
                timed = ['python3', str(root / 'experiments/new-core-s3-20261006/wave-a/exclusive_core.py'),
                         '--', *timed]
            wrapped = ['scripts/build-slot.sh', 'build', '--', *timed]
            if label in ('core-build', 'test-core'):
                wrapped = ['scripts/build-slot.sh', 'gate', '--', 'bash', '-c',
                           RETAIN_GATE, '--', *wrapped]
            log = area / f'{label}.txt'
            started = time.monotonic()
            print(f'{args.stage}: {label} waiting/running; source={commit}', flush=True)
            with log.open('x') as output:
                output.write(f'source_commit={commit}\n$ {shlex.join(wrapped)}\n')
                output.flush()
                result = subprocess.run(wrapped, cwd=root, env=env, stdout=output,
                                        stderr=subprocess.STDOUT)
                measured = float(duration.read_text().splitlines()[-1]) if duration.exists() else None
                wall = time.monotonic() - started
                output.write(f'\nexit={result.returncode} command_seconds={measured} '
                             f'wall_including_admission={wall:.3f}\n')
            outcome = {'label': label, 'command': wrapped, 'exit': result.returncode,
                       'command_seconds': measured, 'wall_seconds': wall, 'log': str(log)}
            summary['results'].append(outcome)
            if result.returncode or measured is None:
                raise RuntimeError(f'{label} failed; inspect {log}')
            if label == 'core-build' and measured > 10:
                raise RuntimeError('uncontended core rebuild exceeded 10 s')
            if label == 'test-core' and measured > 300:
                raise RuntimeError('held test-core exceeded 300 s')
            report = log.read_text()
            if label != 'conformance':
                inspected = old_gate.inspect(report)
                outcome['build_validation'] = inspected
                if inspected['errors']:
                    raise RuntimeError('; '.join(inspected['errors']))
            if label == 'test-core' and not re.search(r'\d+/\d+ tests passed', report):
                raise RuntimeError('test-core passed-test count is missing')
            if label == 'conformance' and len(re.findall(
                    r'matching \d+, mismatching 0, unsupported \d+', report)) != 2:
                raise RuntimeError('debug/release conformance did not both report zero mismatches')
            old_gate.source_unchanged(root, commit)
            print(f'{args.stage}: {label} pass, command={measured:.2f}s', flush=True)
        summary['qualified'] = True
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as failure:
        summary['error'] = f'{type(failure).__name__}: {failure}'
        print(summary['error'], flush=True)
    finally:
        (area / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    return 0 if summary['qualified'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
