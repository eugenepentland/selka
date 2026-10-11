#!/usr/bin/env python3
"""Paired identical-source Stage 4 versus Stage 6 runtime and compile timings."""
import argparse
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import time

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent / 'zero-rc-20261011'))
from measure import command, digest, save


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'before', 'zig', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--iterations', type=int, default=5000000)
    a = parser.parse_args()
    for name in ('compiler', 'before', 'zig', 'output'):
        setattr(a, name, getattr(a, name).resolve())
    env = dict(os.environ, MYLANG_ZIG=str(a.zig), ZIG=str(a.zig))
    for name in ('MYLANG_COUNTERS', 'MYL_CORE_LEAKCHECK'):
        env.pop(name, None)
    result = {'host': platform.platform(), 'iterations': a.iterations,
              'method': '9 alternating paired runs after 2 warmups; taskset CPU 2; GNU time RSS; counters/leak checks disabled; shared host; compile cold project cache then 9 warm stage builds (--emit-llvm prevents whole-build replay); native runtime/toolchain caches shared',
              'harness_sha256': digest(__file__), 'cases': {},
              'tools': {name: {'path': str(getattr(a, name)), 'sha256': digest(getattr(a, name))}
                        for name in ('compiler', 'before', 'zig')}}
    for kind in ('text', 'bytes', 'text_large', 'owned_text'):
        family = 'text' if kind in ('text_large', 'owned_text') else kind
        stem = 'owned' if kind == 'owned_text' else 'borrowed'
        iterations = max(1, a.iterations // 10) if kind == 'text_large' else a.iterations
        lanes = {}
        for lane, compiler in (('before', a.before), ('after', a.compiler)):
            directory = a.output / kind / lane
            directory.mkdir(parents=True, exist_ok=True)
            path, binary = directory / 'sample.my', directory / 'program'
            source = (HERE.parent / 'zero-rc-views-20261011' / f'samples/{stem}_{family}.my').read_text().replace('* 1000', f'* {iterations}')
            if kind == 'text_large':
                source = source.replace('abcdefghijklmnopqrstuvwxyz0123456789', 'abcdefghijklmnopqrstuvwxyz0123456789' * 64)
            path.write_text(source)
            base = [compiler, 'build', path, '--release', '--experimental-zero-rc', '--zig', a.zig,
                    '--cache-dir', directory / 'cache', '-o', binary, '--report', '--emit-llvm', directory / 'program.ll']
            for state in ('cold', *('warm-' + str(i) for i in range(9))):
                command(base, directory / f'build-{state}', env)
            lanes[lane] = {'source_sha256': digest(path), 'binary_sha256': digest(binary), 'runs': [],
                           'compile_ns': {state: json.loads((directory / f'build-{state}.command.json').read_text())['elapsed_ns'] for state in ('cold', *('warm-' + str(i) for i in range(9)))}}
        for i in range(11):
            answers = []
            for lane in (('before', 'after') if i % 2 == 0 else ('after', 'before')):
                directory = a.output / kind / lane
                rss = directory / f'rss-{i}.txt'
                start = time.perf_counter_ns()
                ran = subprocess.run(['/usr/bin/time', '-f', '%M', '-o', str(rss), 'taskset', '-c', '2', str(directory / 'program')],
                                     cwd=ROOT, env=env, capture_output=True, timeout=120)
                elapsed = time.perf_counter_ns() - start
                assert ran.returncode == 0 and not ran.stderr, (lane, ran.stderr)
                answers.append(ran.stdout.decode())
                if i >= 2:
                    lanes[lane]['runs'].append({'elapsed_ns': elapsed, 'max_rss_kib': int(rss.read_text()), 'stdout': answers[-1]})
            assert answers[0] == answers[1]
        for lane, data in lanes.items():
            values = [run['elapsed_ns'] for run in data['runs']]
            data['median_ns'], data['min_ns'], data['max_ns'] = statistics.median(values), min(values), max(values)
            data['median_max_rss_kib'] = statistics.median(run['max_rss_kib'] for run in data['runs'])
        result['cases'][kind] = {'iterations': iterations, 'lanes': lanes, 'elapsed_ratio': lanes['after']['median_ns'] / lanes['before']['median_ns']}
        save(HERE / 'performance.json', result)
        print(kind, result['cases'][kind]['elapsed_ratio'], flush=True)
    for entry in result['tools'].values():
        assert digest(entry['path']) == entry['sha256']


if __name__ == '__main__':
    main()
