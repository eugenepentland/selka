#!/usr/bin/env python3
"""Paired helper diagnostic; all guest invocations take the global timing lock."""
from datetime import datetime, timezone
import argparse
import json
from pathlib import Path
import random
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
import runner

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('before', type=Path)
parser.add_argument('after', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--full', action='store_true', help='Expand80 medium-control rows to340 general distribution rows')
args = parser.parse_args()
before, after, output = args.before, args.after, args.output
lengths = (7, 8, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256, 257, 4096) if args.full else (64, 65, 128, 256)
binaries = {'before': before.resolve(), 'after': after.resolve()}
hashes = {key: runner.digest(path) for key, path in binaries.items()}
started = datetime.now(timezone.utc).isoformat()
cpu_before = runner.cpu_snapshot()
rows = []

def invoke(arm, length, mode, views, wide, count):
    command = ['taskset', '-c', '2', str(binaries[arm]), str(length), str(mode),
               str(views), str(wide), str(count)]
    with runner.timing_lock():
        run = subprocess.run(command, check=True, capture_output=True, text=True,
                             timeout=120, env=runner.runtime_environment())
    checksum, elapsed = map(int, run.stdout.split())
    assert checksum == (count if mode == 0 else 0) and not run.stderr
    return elapsed / count

for length in lengths:
    for mode in range(5):
        for views, wide in ((0, 0), (1, 0), (0, 1), (1, 1)):
            count = 10000
            pilots = []
            while True:
                times = {arm: invoke(arm, length, mode, views, wide, count) for arm in binaries}
                pilots.append({'iterations': count, 'ns_per_call': times})
                if min(times.values()) * count >= 30000000 or count >= 10000000:
                    break
                count = min(10000000, max(count + 1, int(count * 1.1 * 30000000 / (min(times.values()) * count))))
            samples = []
            for round_index in range(-1, 5):
                arms = list(binaries)
                random.Random(f'{length}/{mode}/{views}/{wide}/{round_index}').shuffle(arms)
                times = {arm: invoke(arm, length, mode, views, wide, count) for arm in arms}
                samples.append({'round': round_index, 'ns_per_call': times})
            measured = [sample for sample in samples if sample['round'] >= 0]
            medians = {arm: statistics.median(sample['ns_per_call'][arm] for sample in measured) for arm in binaries}
            rows.append({'length': length, 'distribution': ('equal', 'first', 'middle', 'last', 'varying')[mode],
                         'views': bool(views), 'unicode': bool(wide), 'iterations': count,
                         'pilots': pilots, 'samples': samples, 'medians_ns_per_call': medians,
                         'after_before_ratio': medians['after'] / medians['before']})
            output.write_text(json.dumps({'status': 'incomplete', 'rows': rows}, indent=2) + '\n')
            print(length, mode, views, wide, round(medians['after'] / medians['before'], 3), flush=True)
assert hashes == {key: runner.digest(path) for key, path in binaries.items()}
result = {'status': 'complete', 'kind': 'exploratory isolated native-helper distribution diagnostic',
          'compiler': 'cc -O3 default portable target; no LTO; identical flags/harness for both arms',
          'cpu': 2, 'started_utc': started, 'finished_utc': datetime.now(timezone.utc).isoformat(),
          'binary_hashes_before_after': hashes, 'binaries': {key: str(path) for key, path in binaries.items()},
          'environment': runner.cpu_environment(2, cpu_before, runner.cpu_snapshot()),
          'rounds': 5, 'warmups': 1, 'lengths': lengths, 'script_sha256': runner.digest(Path(__file__)), 'rows': rows,
          'limit': 'Helper calls exclude ownership/generated guest work and use cc code generation. This is not end-to-end or goal acceptance evidence.'}
output.write_text(json.dumps(result, indent=2) + '\n')
