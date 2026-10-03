#!/usr/bin/env python3
"""Independently verify a complete runtime baseline, without running guests."""
import argparse
import hashlib
import json
import math
import random
from pathlib import Path
import statistics
import sys
from oracle import CASES, checksum

ARMS = ('my-llvm', 'my-qbe', 'rust', 'go', 'zig-safe', 'zig-fast')
REVISION = '6df58b02554401f9d37564cceffd14277a835ae1'
HERE = Path(__file__).resolve().parent


def require(condition, message):
    if not condition:
        raise ValueError(message)


def integer(value, minimum, name):
    require(type(value) is int and value >= minimum, f'invalid {name}: {value!r}')
    return value


def positive(value, name):
    require(type(value) in (int, float) and math.isfinite(value) and value > 0,
            f'invalid {name}: {value!r}')


def result(row, expected):
    require(type(row.get('checksum')) is int and row['checksum'] == expected,
            f'checksum mismatch: {row.get("checksum")} != {expected}')
    require('exit_status' in row, 'missing exit_status')
    positive(row.get('kernel_ns'), 'kernel_ns')
    if 'process_wall_ns' in row:
        positive(row['process_wall_ns'], 'process_wall_ns')
    for key in ('exit_status', 'returncode', 'status_code'):
        if key in row:
            require(type(row[key]) is int and row[key] == 0, f'failed {key}')
    if 'stderr' in row:
        require(row['stderr'] == '', 'unexpected stderr')
    if 'peak_rss_kib' in row:
        positive(row['peak_rss_kib'], 'peak_rss_kib')


def check_hash(path, expected):
    require(isinstance(expected, str) and len(expected) == 64, f'invalid hash for {path}')
    actual = hashlib.sha256(Path(path).read_bytes()).hexdigest()
    require(actual == expected, f'artifact hash mismatch: {path}')


def verify(report, check_artifacts=False):
    require(report.get('schema') == 'mylang-runtime-v1', 'unsupported report schema')
    require(report.get('status') == 'complete' and report.get('profile') == 'baseline',
            'smoke/subset/incomplete report cannot qualify as baseline')
    coverage = report.get('coverage', [])
    require(len(coverage) == len(CASES) and set(coverage) == set(CASES), 'incomplete/duplicate case coverage')
    rounds = integer(report.get('rounds'), 1, 'rounds')
    warmups = integer(report.get('warmup_rounds'), 0, 'warmup_rounds')
    plans = {}
    wanted_plans = {(case, size) for case in CASES for size in (64, 1024 if case.startswith('mutate') else 4096)}
    for plan in report.get('plans', []):
        key = (plan['case'], plan['size'])
        require(key in wanted_plans and key not in plans, f'unknown/duplicate plan {key}')
        iterations = integer(plan.get('iterations'), 1, 'iterations')
        require(plan.get('seed') == 42, f'invalid baseline seed {key}')
        require(plan.get('profile') == ('small' if key[1] == 64 else 'large'), f'invalid size profile {key}')
        expected = checksum(key[0], key[1], iterations, 42)
        require(plan.get('expected') == expected, f'plan oracle mismatch {key}')
        plans[key] = (plan, expected)
    require(set(plans) == wanted_plans, 'missing plans')
    groups = {}
    for field, round_range in (('samples', range(rounds)), ('warmups', range(-warmups, 0)), ('memory', (None,))):
        expected_keys = {(arm, case, size, rnd) for case, size in wanted_plans for arm in ARMS for rnd in round_range}
        seen = set()
        for row in report.get(field, []):
            key = (row['arm'], row['case'], row['size'], row.get('round') if field != 'memory' else None)
            require(key in expected_keys and key not in seen, f'unknown/duplicate {field} cell {key}')
            seen.add(key)
            plan, expected = plans[(row['case'], row['size'])]
            for name in ('iterations', 'seed', 'profile', 'expected'):
                require(row.get(name) == plan[name], f'{field} plan mismatch: {name} {key}')
            result(row, expected)
            if field == 'samples':
                groups.setdefault(key[:3], []).append(row['kernel_ns'])
        require(seen == expected_keys, f'missing {field} cells: {len(expected_keys - seen)}')
    qualification = set()
    expected_qualification = {(arm, case, size, seed, count) for arm in ARMS for case in CASES for size, seed, count in ((2, 1, 1), (3, 42, 7), (17, 999983, 31))}
    for row in report.get('qualification', []):
        key = tuple(row[name] for name in ('arm', 'case', 'size', 'seed', 'iterations'))
        require(key in expected_qualification and key not in qualification, f'unknown/duplicate qualification {key}')
        qualification.add(key)
        result(row, checksum(row['case'], row['size'], row['iterations'], row['seed']))
    require(qualification == expected_qualification, 'missing qualification probes')
    for pilot in report.get('pilots', []):
        key = (pilot['case'], pilot['size'])
        require(key in plans, f'unknown pilot {key}')
        count = integer(pilot.get('iterations'), 1, 'pilot iterations')
        require(set(pilot['arms']) == set(ARMS), f'incomplete pilot {key}')
        expected = checksum(key[0], key[1], count, 42)
        for row in pilot['arms'].values():
            result(row, expected)
    if 'summary' in report:
        seen_summary = set()
        for row in report['summary']:
            size = 64 if row['profile'] == 'small' else (1024 if row['case'].startswith('mutate') else 4096)
            require(row.get('size', size) == size, 'summary size/profile mismatch')
            key = (row['arm'], row['case'], size)
            require(key in groups and key not in seen_summary, f'unknown/duplicate summary {key}')
            seen_summary.add(key)
            plan = plans[key[1:]][0]
            require(row['profile'] == plan['profile'], f'summary profile mismatch {key}')
            require(row['iterations'] == plan['iterations'], f'summary iteration mismatch {key}')
            chosen = [sample for sample in report['samples'] if (sample['arm'], sample['case'], sample['size']) == key]
            go = {sample['round']: sample['kernel_ns'] for sample in report['samples'] if sample['arm'] == 'go' and (sample['case'], sample['size']) == key[1:]}
            operations = [sample['kernel_ns'] / plan['iterations'] for sample in chosen]
            ratios = [sample['kernel_ns'] / go[sample['round']] for sample in chosen]
            # Random.choices uses floating-point draws; reproduce that documented
            # resampling protocol independently, without importing the runner.
            generator = random.Random(f'{key[1]}/{size}/{key[0]}/bootstrap')
            bootstrap = sorted(statistics.median([ratios[int(generator.random() * len(ratios))] for _ in ratios]) for _ in range(2000))
            expected_stats = {'median_ns_per_op': statistics.median(operations), 'min_ns_per_op': min(operations), 'max_ns_per_op': max(operations), 'median_paired_ratio_to_go': statistics.median(ratios)}
            for name, expected in expected_stats.items():
                positive(row.get(name), name)
                require(math.isclose(row[name], expected, rel_tol=1e-12, abs_tol=1e-12), f'summary mismatch {name} {key}')
            interval = row.get('paired_bootstrap_95_interval')
            require(isinstance(interval, list) and len(interval) == 2, f'invalid summary interval {key}')
            require(all(type(value) in (int, float) and math.isfinite(value) and math.isclose(value, expected, rel_tol=1e-12, abs_tol=1e-12) for value, expected in zip(interval, (bootstrap[49], bootstrap[1949]))), f'summary interval mismatch {key}')
        require(seen_summary == set(groups), 'missing summary rows')
    identity = report['identity']
    require(identity.get('pinned_revision') == REVISION, 'wrong compiler revision')
    hashes = report.get('binary_hashes', {})
    require(set(hashes) in (set(ARMS), set(ARMS) | {'native_clock.o'}), 'missing/unknown binary identities')
    require(report.get('identity_after') == identity, 'missing/changed identities after measurements')
    require(report.get('binary_hashes_after') == hashes, 'missing/changed binaries after measurements')
    if check_artifacts:
        for path, expected in identity['sources'].items():
            check_hash(HERE / path, expected)
        for tool in identity['tools'].values():
            check_hash(tool.get('compiler_path', tool['path']), tool['sha256'])
            if 'invocation_sha256' in tool:
                check_hash(tool['path'], tool['invocation_sha256'])
        for path, expected in identity['installed_assets'].items():
            check_hash(path, expected)
        check_hash(identity['build_wrapper'], identity['wrapper_sha256'])
        for arm, expected in report['binary_hashes'].items():
            command = identity['clock_build'] if arm == 'native_clock.o' else identity['commands'][arm]
            if '-o' in command:
                path = command[command.index('-o') + 1]
            else:
                path = next(arg.split('=', 1)[1] for arg in command if arg.startswith('-femit-bin='))
            check_hash(path, expected)
    return groups


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('--check-artifacts', action='store_true')
    args = parser.parse_args()
    try:
        report = json.loads(args.report.read_text())
        groups = verify(report, args.check_artifacts)
        print(f'PASS complete baseline: {len(groups)} groups, {len(report["samples"])} samples, {len(report["warmups"])} warmups')
        return 0
    except (ValueError, KeyError, TypeError, OSError, StopIteration) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
