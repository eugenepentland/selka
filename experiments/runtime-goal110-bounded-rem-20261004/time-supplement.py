#!/usr/bin/env python3
"""Supplementary matched endpoint timing; never a frozen goal target."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import random
import statistics
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
import runner
from compare_candidate import bootstrap
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts

ARMS = ('before-llvm', 'before-qbe', 'after-llvm', 'after-qbe')
ITERATION_CAP = 100000
NEGATIVE_SEED = -1048576
DIVISOR = 1009


def stamp():
    return datetime.now(timezone.utc).isoformat()


def checksum(size, iterations, seed):
    assert 2 <= size <= 4096 and 1 <= iterations <= ITERATION_CAP
    cycles, remainder = divmod(iterations, DIVISOR)
    # This oracle uses Python mathematical integers and flooring remainder.
    parts = [sum((j + 1) * ((seed + batch + j * 13) % DIVISOR) for j in range(size))
             for batch in range(min(iterations, DIVISOR))]
    return (sum(parts) * cycles + sum(parts[:remainder])) % 1000000007


def check_plan(plan):
    assert plan['case'] == 'append_endpoint' and plan['size'] in (64, 4096)
    assert 1 <= plan['iterations'] <= ITERATION_CAP
    assert plan['seed'] in (NEGATIVE_SEED, 42)
    maximum = plan['seed'] + plan['iterations'] - 1 + (plan['size'] - 1) * 13
    if plan['seed'] == NEGATIVE_SEED:
        assert maximum <= -895342 < 0
    assert plan['maximum_dividend'] == maximum
    assert plan['expected'] == checksum(plan['size'], plan['iterations'], plan['seed'])


def replay(report):
    assert report['schema'] == 'mylang-goal110-bounded-rem-supplement-timing-v1'
    assert report['status'] == 'complete' and report['cpu'] == 2
    assert report['rounds'] == 5 and report['warmups'] == 1
    seen = set()
    for row in report['rows']:
        plan = row['plan']; check_plan(plan)
        key = plan['size'], plan['seed']
        assert key not in seen
        seen.add(key)
        samples = {}
        for sample in row['samples']:
            pair = sample['round'], sample['arm']
            assert pair not in samples and pair[0] in range(-1, 5) and pair[1] in ARMS
            assert sample['checksum'] == plan['expected'] and sample['exit_status'] == 0
            assert sample['kernel_ns'] > 0 and sample['process_wall_ns'] > 0
            samples[pair] = sample['kernel_ns'] / plan['iterations']
        assert set(samples) == {(rnd, arm) for rnd in range(-1, 5) for arm in ARMS}
        medians = {arm: statistics.median(samples[rnd, arm] for rnd in range(5)) for arm in ARMS}
        assert row['medians_ns_per_op'] == medians
        for backend in ('llvm', 'qbe'):
            assert row['after_before_ratios'][backend] == medians['after-' + backend] / medians['before-' + backend]
            assert row['paired_bootstrap_95'][backend] == bootstrap(
                [samples[rnd, 'after-' + backend] for rnd in range(5)],
                [samples[rnd, 'before-' + backend] for rnd in range(5)], str(key) + '/' + backend)
    assert seen == {(size, seed) for size in (64, 4096) for seed in (NEGATIVE_SEED, 42)}
    return sum(len(row['samples']) for row in report['rows'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--verify', type=Path)
    args = parser.parse_args()
    if args.verify:
        print('PASS supplementary timing replay: ' + str(replay(json.loads(args.verify.read_text()))) + ' outcomes')
        return
    if args.build is None or args.output is None:
        parser.error('--build and --output required')
    build_hash = runner.digest(args.build)
    build = json.loads(args.build.read_text())
    assert build['schema'] == 'mylang-goal110-bounded-rem-supplement-build-v1' and build['status'] == 'complete'
    bindings = {**build['source_and_helper_sha256'], str(Path(__file__)): runner.digest(__file__),
                str(ROOT / 'benchmarks/runtime/compare_candidate.py'): runner.digest(ROOT / 'benchmarks/runtime/compare_candidate.py')}
    binaries = {arm: Path(build['builds'][arm]['binary']) for arm in ARMS}
    hashes = {arm: runner.digest(path) for arm, path in binaries.items()}
    assert hashes == {arm: build['builds'][arm]['binary_sha256'] for arm in ARMS}
    for label, binding in build['manifests'].items():
        path = Path(binding['path'])
        holdouts.check_manifest(path, binding['sha256'], json.loads(path.read_text()))
    assert bindings == {path: runner.digest(path) for path in bindings}
    report = {'schema': 'mylang-goal110-bounded-rem-supplement-timing-v1', 'status': 'in_progress',
              'session_id': str(uuid.uuid4()), 'started_utc': stamp(), 'build_receipt': str(args.build.resolve()),
              'build_receipt_sha256': build_hash, 'binary_hashes': hashes, 'source_and_helper_sha256': bindings,
              'rounds': 5, 'warmups': 1, 'cpu': 2, 'iteration_cap': ITERATION_CAP,
              'maximum_negative_dividend_at_limits': -895342, 'pilots': [], 'rows': [],
              'limitations': ['Supplementary separate kernel; outside frozen80 and never a goal confirmation.',
                              'Five exploratory rounds do not establish a small stable performance effect.',
                              'Iteration cap is100000 to retain strictly negative endpoints; cap-limited durations are explicit.',
                              'Control host is ReleaseFast; candidate host is Debug; all guests use ordinary ReleaseFast backend policy.']}
    cpu_before = runner.cpu_snapshot()
    for size in (64, 4096):
        for seed in (NEGATIVE_SEED, 42):
            count = 31
            while True:
                expected = checksum(size, count, seed)
                pilot = {arm: runner.invoke(binary, 'append_endpoint', size, count, seed, 2, expected)
                         for arm, binary in binaries.items()}
                report['pilots'].append({'size': size, 'seed': seed, 'iterations': count, 'arms': pilot})
                fastest = min(value['kernel_ns'] for value in pilot.values())
                slowest = max(value['kernel_ns'] for value in pilot.values())
                if fastest >= 50000000 or slowest >= 500000000 or count == ITERATION_CAP:
                    break
                growth = min(20, 50000000 / fastest, 500000000 / slowest)
                new_count = min(ITERATION_CAP, max(count + 1, int(count * growth)))
                if new_count <= count:
                    break
                count = new_count
            plan = {'case': 'append_endpoint', 'profile': 'small' if size == 64 else 'large', 'size': size,
                    'seed': seed, 'iterations': count, 'expected': expected,
                    'maximum_dividend': seed + count - 1 + (size - 1) * 13,
                    'calibration': {'fastest_ns': fastest, 'slowest_ns': slowest, 'target_ns': 50000000,
                                    'slowest_cap_ns': 500000000, 'iteration_cap': ITERATION_CAP,
                                    'iteration_cap_limited': count == ITERATION_CAP and fastest < 50000000}}
            check_plan(plan)
            samples = []
            for rnd in range(-1, 5):
                order = list(ARMS)
                random.Random(f'{size}/{seed}/{rnd}').shuffle(order)
                for arm in order:
                    samples.append({'round': rnd, 'arm': arm,
                                    **runner.invoke(binaries[arm], 'append_endpoint', size, count, seed, 2, expected)})
            medians = {arm: statistics.median(sample['kernel_ns'] / count for sample in samples
                       if sample['round'] >= 0 and sample['arm'] == arm) for arm in ARMS}
            ratios = {backend: medians['after-' + backend] / medians['before-' + backend] for backend in ('llvm', 'qbe')}
            report['rows'].append({'plan': plan, 'samples': samples, 'medians_ns_per_op': medians,
                                   'after_before_ratios': ratios})
            print(size, seed, ratios, flush=True)
    print('Supplementary guest timing complete; computing paired intervals', flush=True)
    for row in report['rows']:
        plan = row['plan']; key = plan['size'], plan['seed']
        values = {arm: [sample['kernel_ns'] / plan['iterations'] for sample in row['samples']
                       if sample['round'] >= 0 and sample['arm'] == arm] for arm in ARMS}
        row['paired_bootstrap_95'] = {backend: bootstrap(values['after-' + backend], values['before-' + backend],
                                     str(key) + '/' + backend) for backend in ('llvm', 'qbe')}
    assert hashes == {arm: runner.digest(path) for arm, path in binaries.items()}
    assert bindings == {path: runner.digest(path) for path in bindings}
    assert build_hash == runner.digest(args.build)
    for binding in build['manifests'].values():
        path = Path(binding['path'])
        holdouts.check_manifest(path, binding['sha256'], json.loads(path.read_text()))
    report.update(status='complete', finished_utc=stamp(), environment=runner.cpu_environment(2, cpu_before, runner.cpu_snapshot()))
    replay(report)
    with args.output.open('x') as target:
        target.write(json.dumps(report, indent=2) + '\n')
    print('PASS96 supplementary outcomes: negative old-admitted population and positive controls')


if __name__ == '__main__':
    main()
