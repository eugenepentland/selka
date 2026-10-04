#!/usr/bin/env python3
"""Prepare an independent eight-row native positive/negative control repeat."""
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
specs = [(length, mode, views, wide) for length in (64, 128) for mode in (0, 2)
         for views, wide in ((0, 0), (1, 1))]
report = {'status': 'incomplete', 'kind': 'independent native positive/negative control repeat',
          'session_id': str(uuid.uuid4()), 'started_utc': datetime.now(timezone.utc).isoformat(),
          'source_revision': '3dcbe723da4036fb7d69046e77e9f8cd16d7512f',
          'cpu': 2, 'rounds': 15, 'warmups': 3,
          'binaries': {arm: str(path) for arm, path in binaries.items()},
          'binary_hashes_before': hashes, 'script_sha256': runner.digest(Path(__file__)),
          'calibration_target_ns': 30000000, 'iteration_cap': 10000000, 'rows': [],
          'limitations': ['Standalone native timing cannot establish generated guest/goal acceptance.',
                         'The10M cap can stop calibration below nominal30ms; all actual durations retained.']}
cpu_before = runner.cpu_snapshot()


def invoke(arm, length, mode, views, wide, count):
    command = ['taskset', '-c', '2', str(binaries[arm]), str(length), str(mode), str(views), str(wide), str(count)]
    with runner.timing_lock():
        done = subprocess.run(command, capture_output=True, text=True, timeout=120, env=runner.runtime_environment())
    fields = done.stdout.split()
    assert done.returncode == 0 and not done.stderr and len(fields) == 2
    checksum, elapsed = map(int, fields)
    expected = count if mode == 0 else 0
    assert checksum == expected and elapsed > 0
    return {'command': command, 'exit_status': done.returncode, 'stdout': done.stdout, 'stderr': done.stderr,
            'checksum': checksum, 'expected_checksum': expected, 'elapsed_ns': elapsed, 'ns_per_call': elapsed / count}


for length, mode, views, wide in specs:
    count, pilots = 10000, []
    while True:
        results = {arm: invoke(arm, length, mode, views, wide, count) for arm in binaries}
        pilots.append({'iterations': count, 'results': results})
        duration = min(result['elapsed_ns'] for result in results.values())
        if duration >= 30000000 or count >= 10000000:
            break
        count = min(10000000, max(count + 1, int(count * 1.1 * 30000000 / duration)))
    samples = []
    for round_index in range(-3, 15):
        arms = list(binaries)
        random.Random(f'repeat/{length}/{mode}/{views}/{wide}/{round_index}').shuffle(arms)
        results = {arm: invoke(arm, length, mode, views, wide, count) for arm in arms}
        samples.append({'round': round_index, 'arm_order': arms, 'results': results})
    measured = [sample for sample in samples if sample['round'] >= 0]
    medians = {arm: statistics.median(sample['results'][arm]['ns_per_call'] for sample in measured) for arm in binaries}
    report['rows'].append({'length': length, 'distribution': 'equal' if mode == 0 else 'middle',
                           'views': bool(views), 'unicode': bool(wide), 'iterations': count, 'pilots': pilots,
                           'samples': samples, 'medians_ns_per_call': medians,
                           'after_before_ratio': medians['after'] / medians['before']})
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(length, mode, views, wide, round(medians['after'] / medians['before'], 5), flush=True)
assert hashes == {arm: runner.digest(path) for arm, path in binaries.items()}
report.update(status='complete', finished_utc=datetime.now(timezone.utc).isoformat(),
              binary_hashes_after=hashes, environment=runner.cpu_environment(2, cpu_before, runner.cpu_snapshot()))
args.output.write_text(json.dumps(report, indent=2) + '\n')
print('PASS eight-row15r3w repeat; every status/checksum/process stream retained', flush=True)
