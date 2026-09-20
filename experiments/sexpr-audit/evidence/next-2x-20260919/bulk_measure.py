#!/usr/bin/env python3
"""Compare bulk output to the same emitted-IR control and check rendering goldens."""
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import sys
import time

work = Path(sys.argv[1]).resolve()
root = Path(__file__).resolve().parents[4]
os.sched_setaffinity(0, {6})
commands = {name: [str(work / name), str(work / 'input.sexp'), '--render']
            for name in ['census', 'census_il', 'census_bulk']}
outputs = {name: subprocess.check_output(command) for name, command in commands.items()}
assert len(set(outputs.values())) == 1
samples = {name: [] for name in commands}
wall = {name: [] for name in commands}
rng = random.Random(20)
for _ in range(21):
    names = list(commands)
    rng.shuffle(names)
    for name in names:
        start = time.perf_counter_ns()
        result = subprocess.run(commands[name], capture_output=True, check=True)
        wall[name].append((time.perf_counter_ns() - start) / 1e6)
        assert result.stdout == outputs[name]
for _ in range(7):
    names = list(commands)
    rng.shuffle(names)
    for name in names:
        result = subprocess.run(['perf', 'stat', '-x,', '-e', 'instructions:u,cycles:u',
                                 '--', *commands[name]], capture_output=True, text=True, check=True)
        values = {}
        for line in result.stderr.splitlines():
            fields = line.split(',')
            if len(fields) > 2 and fields[0].strip().replace('.', '', 1).isdigit():
                values[fields[2]] = float(fields[0])
        assert values, 'No hardware counters; check perf permissions'
        samples[name].append(values)
summary = {name: {'median_ms': statistics.median(wall[name]),
                  **{key: statistics.median(v[key] for v in samples[name])
                     for key in samples[name][0]}} for name in commands}
gold = root / 'experiments/sexpr-port/golden'
counts = {}
for binary in ['census', 'census_scalar', 'census_bulk']:
    count = 0
    for line in (gold / 'manifest.tsv').read_text().splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        label, source = line.split('\t')
        path = Path(source)
        path = path if path.is_absolute() else root / path
        result = subprocess.run([str(work / binary), str(path), '--render'],
                                capture_output=True, check=True)
        assert result.stdout == (gold / f'{label}.txt').read_bytes() + b'\n', (binary, label)
        count += 1
    counts[binary] = count
path = work / 'unicode.sexp'
path.write_text('(a "λ😀é" "a\\nb")\n')
expected = subprocess.run([str(work / 'census'), str(path), '--render'], capture_output=True)
actual = subprocess.run([str(work / 'census_bulk'), str(path), '--render'], capture_output=True)
assert (expected.returncode, expected.stdout, expected.stderr) == (actual.returncode, actual.stdout, actual.stderr)
report = {'counters': samples, 'wall_ms': wall, 'summary': summary,
          'validation': {'goldens': counts, 'unicode_matches': True, 'benchmark_matches': True}}
(work / 'bulk-print.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(summary, indent=2))
print(report['validation'])
