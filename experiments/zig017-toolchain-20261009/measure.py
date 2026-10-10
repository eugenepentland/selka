#!/usr/bin/env python3
"""Measure prebuilt probes and compiler frontend work on a reserved CPU."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time
from build_hashes import HERE, ROOT, WORK

def sibling_ticks():
    line = next(x for x in Path('/proc/stat').read_text().splitlines() if x.startswith('cpu3 '))
    ticks = list(map(int, line.split()[1:9]))
    return sum(ticks), ticks[3] + ticks[4]

def corpus():
    output = ['record Acc:\n    total: int\n    count: int\n']
    for i in range(256):
        previous = f'f{i-1}(k - 1)' if i else 'k'
        output.append(f'''func f{i}(k: int) -> int:
    mut items: int[] = []
    for j in range(k % 17 + 3):
        items.append(j * {i % 7 + 1} + k)
    mut acc = Acc(total=0, count=0)
    for v in items:
        if v % 3 == 0:
            acc = Acc(total=acc.total + v, count=acc.count + 1)
        else:
            acc = Acc(total=acc.total - 1, count=acc.count)
    return acc.total + acc.count + {previous} % 1000
''')
    output.append('func main() -> int:\n    return f255(40)\n')
    dest = HERE / 'frontend.my'
    dest.write_text('\n'.join(output))
    return dest

def once(name, command, rep, kind):
    metric = WORK / 'measurement.time'
    before_total, before_idle = sibling_ticks()
    started = time.perf_counter()
    done = subprocess.run(['/usr/bin/time', '-f', '%e %M %U %S', '-o', str(metric),
                           'taskset', '-c', '2', *map(str, command)], cwd=ROOT,
                          env={**os.environ, 'TMPDIR': str(WORK / 'tmp')}, capture_output=True)
    wall = time.perf_counter() - started
    after_total, after_idle = sibling_ticks()
    values = metric.read_text().splitlines()[-1].split()
    row = {'name': name, 'rep': rep, 'kind': kind, 'exit': done.returncode,
           'wall_s': wall, 'rss_kib': int(values[1]),
           'user_s': float(values[2]), 'sys_s': float(values[3]),
           'stdout_sha256': hashlib.sha256(done.stdout).hexdigest(),
           'load': os.getloadavg(),
           'sibling_busy': 1 - (after_idle - before_idle) / max(1, after_total - before_total),
           'stderr': done.stderr.decode(errors='replace')[:2000]}
    if done.returncode:
        raise RuntimeError(json.dumps(row))
    return row, done.stdout

def main():
    which = sys.argv[1]
    rows = []
    if which == 'hash':
        data = WORK / 'hash-input.bin'
        data.write_bytes(bytes(range(256)) * (16 * 1024 * 1024 // 256))
        expected = hashlib.sha256(data.read_bytes()).hexdigest()
        builds = json.loads((HERE / 'hash-builds.json').read_text())
        cases = [(x['name'], [WORK / 'hash' / x['name'], data]) for x in builds if x['exit'] == 0]
        rounds = 3
    else:
        src = corpus()
        expected = {}
        builds = json.loads((HERE / 'compiler-builds.json').read_text())
        if (HERE / 'compiler-llvm-builds.json').exists():
            builds += json.loads((HERE / 'compiler-llvm-builds.json').read_text())
        names = sorted({x['name'] for x in builds if x['exit'] == 0})
        cases = []
        for name in names:
            binary = WORK / 'compilers' / name / 'bin/mylang'
            cases.extend([(name + '/check', [binary, 'check', src, '--no-cache']),
                          (name + '/ir', [binary, 'dump-ir', src])])
        rounds = 7
    for rep in range(rounds + 1):
        order = cases if rep % 2 == 0 else list(reversed(cases))
        for name, command in order:
            row, out = once(name, command, rep, which)
            if which == 'hash':
                values = out.decode().strip().split()
                assert values[0] == expected, (name, out)
                row['backend'], row['optimize'] = values[1:]
            else:
                workload = name.split('/')[-1]
                if workload not in expected:
                    expected[workload] = out
                assert out == expected[workload], (name, 'compiler outputs differ')
            rows.append(row)
            (HERE / (which + '-measurements.json')).write_text(json.dumps(rows, indent=2) + '\n')
            print(which, name, rep, row['wall_s'], flush=True)
    summary = {name: {'median_s': statistics.median(x['wall_s'] for x in rows if x['name'] == name and x['rep'] > 0),
                     'median_rss_kib': statistics.median(x['rss_kib'] for x in rows if x['name'] == name and x['rep'] > 0)}
               for name, _ in cases}
    (HERE / (which + '-summary.json')).write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2), flush=True)

if __name__ == '__main__':
    with Path('/run/user/1000/mylang-slots/cpu2.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        main()
