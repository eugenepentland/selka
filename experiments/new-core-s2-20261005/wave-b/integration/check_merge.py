#!/usr/bin/env python3
"""Run the three required checks after a Wave B integration merge."""
import argparse
import os
from pathlib import Path
import re
import shlex
import subprocess
import time

ROOT = Path(__file__).resolve().parents[4]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', required=True)
    args = parser.parse_args()
    area = ROOT / 'experiments/new-core-s2-20261005/wave-b/integration'
    cache = ROOT / '.mylang-cache/wave-b' / args.stage
    (cache / 'tmp').mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, TMPDIR=str(cache / 'tmp'), ZIG_LOCAL_CACHE_DIR=str(ROOT / '.zig-cache'),
               ZIG_GLOBAL_CACHE_DIR='/home/epentland/ai/canopy/.zig-global-cache')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    commands = [
        ('build', ['zig', 'build', 'core', '--summary', 'all']),
        ('test-core', ['zig', 'build', 'test-core', '--summary', 'all']),
        ('conformance', ['python3', str(area / 'conformance_checked.py'), '--set', 'all',
                         '--jobs', '4', '--why', '--mylang', str(ROOT / '.mylang-cache/wave-b/baseline/mylang'), '--core',
                         'zig-out/bin/mylang-core', '--cache-dir', str(cache / 'conformance')]),
    ]
    for label, command in commands:
        duration = cache / (label + '-seconds.txt')
        duration.unlink(missing_ok=True)
        wrapped = ['scripts/build-slot.sh', 'build', '--', '/usr/bin/time', '-f', '%e',
                   '-o', str(duration), *command]
        if label == 'test-core':
            wrapped = ['scripts/build-slot.sh', 'gate', '--', 'bash', '-c',
                       '"$@"; result=$?; exit "$result"', '--', *wrapped]
        log = area / f'{args.stage}-{label}.txt'
        with log.open('w') as output:
            output.write(f'source_commit={commit}\n$ {shlex.join(wrapped)}\n')
            output.flush()
            start = time.monotonic()
            result = subprocess.run(wrapped, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT)
            elapsed = time.monotonic() - start
            measured = float(duration.read_text().splitlines()[-1])
            output.write(f'\nexit={result.returncode} command_seconds={measured:.2f} '
                         f'wall_including_admission={elapsed:.2f}\n')
        print(f'{args.stage} {label}: exit={result.returncode} command_seconds={measured:.2f}', flush=True)
        if result.returncode or (label == 'build' and measured > 10) or (label == 'test-core' and measured > 300):
            raise SystemExit(f'STOP: {label} failed or exceeded its time limit; inspect {log}')
        report = log.read_text()
        if label == 'test-core':
            assert re.search(r'\d+/\d+ tests passed', report), report
            assert not re.search(r'error: memory usage peaked at .*exceeding the declared upper bound', report), report
            for amount, unit in re.findall(r'MaxRSS:(\d+)([KMG])', report):
                assert int(amount) * {'K': 1024, 'M': 1024**2, 'G': 1024**3}[unit] <= 2.5 * 1024**3
        if label == 'conformance':
            assert len(re.findall(r'matching \d+, mismatching 0, unsupported \d+', report)) == 2, report


if __name__ == '__main__':
    main()
