#!/usr/bin/env python3
"""Record one dictionary fact repair check with build admission and private caches."""
import argparse
import os
from pathlib import Path
import shlex
import subprocess
import time

ROOT = Path(__file__).resolve().parents[4]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--gate', action='store_true')
    parser.add_argument('--allow-exit', type=int, default=0)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    assert command
    cache = ROOT / '.mylang-cache/wave-b/s2-d/fact-repair'
    evidence = ROOT / 'experiments/new-core-s2-20261005/wave-b/s2-d/fact-repair'
    (cache / 'tmp').mkdir(parents=True, exist_ok=True)
    evidence.mkdir(parents=True, exist_ok=True)
    duration = cache / f'{args.name}-time.txt'
    duration.unlink(missing_ok=True)
    wrapped = ['scripts/build-slot.sh', 'build', '--', '/usr/bin/time', '-f', '%e %M %x',
               '-o', str(duration), *command]
    if args.gate:
        wrapped = ['scripts/build-slot.sh', 'gate', '--', 'bash', '-c',
                   '"$@"; result=$?; exit "$result"', '--', *wrapped]
    env = dict(os.environ, TMPDIR=str(cache / 'tmp'), ZIG_LOCAL_CACHE_DIR=str(ROOT / '.zig-cache'),
               ZIG_GLOBAL_CACHE_DIR='/home/epentland/ai/canopy/.zig-global-cache')
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    log = evidence / f'{args.name}.txt'
    with log.open('w') as output:
        output.write(f'source_base={source}\n$ {shlex.join(wrapped)}\n')
        output.flush()
        start = time.monotonic()
        result = subprocess.run(wrapped, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT)
        elapsed = time.monotonic() - start
        output.write(f'\nexit={result.returncode} time_rss_exit={duration.read_text().strip()} '
                     f'wall_including_admission={elapsed:.2f}\n')
    print(f'{args.name}: exit={result.returncode}; {duration.read_text().strip()}; {log}', flush=True)
    assert result.returncode == args.allow_exit, log


if __name__ == '__main__':
    main()
