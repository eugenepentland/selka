#!/usr/bin/env python3
"""Capture eighty matched native rows; this is not guest acceptance timing."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import random
import statistics
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
import runner

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('before', type=Path)
parser.add_argument('after', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
assert not args.output.exists()
binaries = {'before': args.before.resolve(), 'after': args.after.resolve()}
hashes = {arm: runner.digest(path) for arm, path in binaries.items()}
specs = [(length, mode, views, wide) for length in (17, 32, 33, 64)
         for mode in range(4) for views, wide in ((0, 0), (1, 0), (0, 1), (1, 1))]
specs += [(length, mode, views, wide) for length in (65, 128, 256, 4096)
          for mode in (0, 2) for views, wide in ((0, 0), (1, 1))]
assert len(specs) == 80
report = {'status': 'incomplete', 'kind': 'exploratory LLVM fullLTO native helper distributions',
          'session_id': str(uuid.uuid4()), 'started_utc': datetime.now(timezone.utc).isoformat(),
          'source_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
          'cpu': 2, 'rounds': 5, 'warmups': 1, 'binaries': {key: str(path) for key, path in binaries.items()},
          'binary_hashes_before': hashes, 'script_sha256': runner.digest(Path(__file__)),
          'compiler_policy': 'zig cc -O3 -flto; identical defaultnative CPU/ISA policy; no ISA override',
          'rows': [], 'limits': ['Standalone native comparator excludes generated guest/ownership work; no goal acceptance.',
                                'Negative controls use equal/middle ownedASCII and viewUTF8; affected widths cover all four distributions and representations.']}
cpu_before = runner.cpu_snapshot()


def invoke(arm, length, mode, views, wide, count):
    command = ['taskset', '-c', '2', str(binaries[arm]), str(length), str(mode), str(views), str(wide), str(count)]
    with runner.timing_lock():
        run = subprocess.run(command, capture_output=True, text=True, timeout=120, env=runner.runtime_environment())
    fields = run.stdout.split()
    assert run.returncode == 0 and not run.stderr and len(fields) == 2, (command, run.returncode, run.stdout, run.stderr)
    checksum, elapsed = map(int, fields)
    expected = count if mode == 0 else 0
    assert checksum == expected and elapsed > 0
    return {'command': command, 'exit_status': run.returncode, 'stdout': run.stdout, 'stderr': run.stderr,
            'checksum': checksum, 'expected_checksum': expected, 'elapsed_ns': elapsed, 'ns_per_call': elapsed / count}


for length, mode, views, wide in specs:
    count, pilots = 10000, []
    while True:
        results = {arm: invoke(arm, length, mode, views, wide, count) for arm in binaries}
        times = {arm: result['ns_per_call'] for arm, result in results.items()}
        pilots.append({'iterations': count, 'results': results})
        if min(times.values()) * count >= 30000000 or count >= 10000000:
            break
        count = min(10000000, max(count + 1, int(count * 1.1 * 30000000 / (min(times.values()) * count))))
    samples = []
    for round_index in range(-1, 5):
        arms = list(binaries)
        random.Random(f'{length}/{mode}/{views}/{wide}/{round_index}').shuffle(arms)
        results = {arm: invoke(arm, length, mode, views, wide, count) for arm in arms}
        samples.append({'round': round_index, 'arm_order': arms, 'results': results})
    measured = [sample for sample in samples if sample['round'] >= 0]
    medians = {arm: statistics.median(sample['results'][arm]['ns_per_call'] for sample in measured) for arm in binaries}
    report['rows'].append({'length': length, 'distribution': ('equal', 'first', 'middle', 'last')[mode],
                           'views': bool(views), 'unicode': bool(wide), 'iterations': count, 'pilots': pilots,
                           'samples': samples, 'medians_ns_per_call': medians,
                           'after_before_ratio': medians['after'] / medians['before']})
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(length, mode, views, wide, round(medians['after'] / medians['before'], 4), flush=True)
assert hashes == {arm: runner.digest(path) for arm, path in binaries.items()}
report.update(status='complete', finished_utc=datetime.now(timezone.utc).isoformat(),
              binary_hashes_after=hashes, environment=runner.cpu_environment(2, cpu_before, runner.cpu_snapshot()))
args.output.write_text(json.dumps(report, indent=2) + '\n')
print('PASS native eighty rows; every pilot/warmup/measurement status, checksum and stream retained', flush=True)
