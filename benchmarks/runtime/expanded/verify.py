#!/usr/bin/env python3
"""Verify complete expanded evidence independently of runner summary code."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import statistics
import sys

from registry import HERE, GROUPS, EDGE_PROBES, checksum, inventory, plans_for

ARMS = ('my-llvm', 'my-qbe', 'rust', 'go', 'zig-safe', 'zig-fast')
REVISION = '6df58b02554401f9d37564cceffd14277a835ae1'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def positive(value, name):
    require(type(value) in (float, int) and math.isfinite(value) and value > 0, 'invalid ' + name)


def result(row, expected, memory=False):
    require(type(row.get('checksum')) is int and row['checksum'] == expected, 'checksum mismatch')
    require(type(row.get('exit_status')) is int and row['exit_status'] == 0, 'missing/failed exit status')
    positive(row.get('kernel_ns'), 'kernel duration')
    positive(row.get('process_wall_ns'), 'process duration')
    if memory:
        positive(row.get('peak_rss_kib'), 'peak RSS')


def hash_matches(path, expected):
    require(isinstance(expected, str) and len(expected) == 64, 'malformed artifact hash')
    require(hashlib.sha256(Path(path).read_bytes()).hexdigest() == expected, 'changed artifact: ' + str(path))


def verify(report, artifacts=False):
    require(report.get('schema') == 'mylang-runtime-expanded-v1', 'wrong schema')
    require(report.get('status') == 'complete' and report.get('profile') == 'baseline', 'not a complete baseline')
    cases = inventory()
    require(report.get('inventory') == cases, 'case inventory mismatch')
    require(len(report['coverage']) == len(cases) and set(report['coverage']) == set(cases), 'incomplete coverage')
    rounds, warmups = report['rounds'], report['warmup_rounds']
    require(type(rounds) is int and rounds >= 1 and type(warmups) is int and warmups >= 0, 'invalid rounds')
    wanted = {(p['case'], p['size']): p for p in plans_for(cases)}
    plans = {}
    for row in report['plans']:
        key = (row['case'], row['size'])
        require(key in wanted and key not in plans, 'unknown/duplicate plan')
        for field, value in wanted[key].items():
            require(row[field] == value, 'plan metadata mismatch: ' + field)
        n = row['iterations']
        require(type(n) is int and n > 0, 'invalid iteration count')
        require(row['expected'] == checksum(row['case'], row['size'], n, 42), 'invalid plan checksum')
        for field in ('fastest_ns', 'slowest_ns', 'target_ns', 'slowest_cap_ns', 'iteration_cap'):
            positive(row['calibration'][field], 'calibration ' + field)
        plans[key] = row
    require(set(plans) == set(wanted), 'missing plans')
    groups = {}
    for field, rnds in (('samples', range(rounds)), ('warmups', range(-warmups, 0)), ('memory', [None])):
        required = {(case, size, arm, rnd) for case, size in wanted for arm in ARMS for rnd in rnds}
        seen = set()
        for row in report[field]:
            key = (row['case'], row['size'], row['arm'], row.get('round') if field != 'memory' else None)
            require(key in required and key not in seen, 'unknown/duplicate ' + field + ' cell')
            seen.add(key)
            plan = plans[key[:2]]
            for name in ('iterations', 'seed', 'profile', 'group', 'family', 'level', 'unit', 'expected'):
                require(row[name] == plan[name], 'sample plan mismatch: ' + name)
            result(row, plan['expected'], field == 'memory')
            if field == 'samples':
                groups.setdefault(key[:3], []).append(row)
        require(seen == required, 'missing ' + field + ' cells')
    required = {(case, arm, size, seed, count) for case in cases for arm in ARMS for size, seed, count in EDGE_PROBES}
    seen = set()
    for row in report['qualification']:
        key = tuple(row[k] for k in ('case', 'arm', 'size', 'seed', 'iterations'))
        require(key in required and key not in seen, 'unknown/duplicate qualification')
        seen.add(key)
        result(row, checksum(key[0], key[2], key[4], key[3]))
    require(seen == required, 'missing qualification')
    piloted = {}
    for pilot in report['pilots']:
        key = (pilot['case'], pilot['size'])
        require(key in wanted, 'unknown pilot')
        require(set(pilot['arms']) == set(ARMS), 'missing pilot arm')
        n = pilot['iterations']
        require(type(n) is int and n > 0, 'bad pilot iterations')
        expected = checksum(pilot['case'], pilot['size'], n, 42)
        for row in pilot['arms'].values():
            result(row, expected)
        piloted[key] = pilot
    require(set(piloted) == set(wanted), 'missing calibration evidence')
    for key, plan in plans.items():
        last = piloted[key]
        require(plan['iterations'] == last['iterations'], 'plan differs from final pilot count')
        fastest = min(row['kernel_ns'] for row in last['arms'].values())
        slowest = max(row['kernel_ns'] for row in last['arms'].values())
        c = plan['calibration']
        require(c['fastest_ns'] == fastest and c['slowest_ns'] == slowest, 'calibration differs from final pilot durations')
        require(c['target_reached'] == (fastest >= c['target_ns']), 'incorrect calibration target status')
        require(c['limited'] == (fastest < c['target_ns']), 'incorrect calibration limit status')
        require(c['slowest_budget_exceeded'] == (slowest > c['slowest_cap_ns']), 'incorrect calibration budget status')
    seen = set()
    for row in report['summary']:
        key = (row['case'], row['size'], row['arm'])
        require(key in groups and key not in seen, 'unknown/duplicate summary')
        seen.add(key)
        plan = plans[key[:2]]
        require(row['iterations'] == plan['iterations'] and row['profile'] == plan['profile'], 'summary plan mismatch')
        samples = groups[key]
        go = {r['round']: r['kernel_ns'] for r in groups[(*key[:2], 'go')]}
        values = [s['kernel_ns'] / plan['iterations'] for s in samples]
        ratios = [s['kernel_ns'] / go[s['round']] for s in samples]
        rng = random.Random(f'{key[0]}/{key[1]}/{key[2]}/bootstrap')
        bootstrap = sorted(statistics.median([ratios[int(rng.random() * len(ratios))] for _ in ratios]) for _ in range(2000))
        expected = {'median_ns_per_op': statistics.median(values), 'min_ns_per_op': min(values),
                    'max_ns_per_op': max(values), 'median_paired_ratio_to_go': statistics.median(ratios)}
        for name, value in expected.items():
            positive(row[name], name)
            require(math.isclose(row[name], value, rel_tol=1e-12), 'summary arithmetic mismatch: ' + name)
        interval = row['paired_bootstrap_95_interval']
        require(isinstance(interval, list) and len(interval) == 2, 'invalid interval')
        require(all(math.isclose(value, expected, rel_tol=1e-12) for value, expected in zip(interval, (bootstrap[49], bootstrap[1949]))),
                'summary interval mismatch')
    require(seen == set(groups), 'missing summary')
    identity = report['identity']
    require(identity['pinned_revision'] == REVISION, 'wrong compiler revision')
    require(identity['inventory'] == cases, 'identity inventory mismatch')
    require(report['identity_after'] == identity, 'identity changed during measurement')
    require(report['binary_hashes_after'] == report['binary_hashes'], 'binaries changed during measurement')
    names = {group + '/' + arm for group in GROUPS for arm in ARMS}
    require(set(report['binary_hashes']) == names | {'native_clock.o'}, 'missing binary hashes')
    require(set(identity['binary_paths']) == names and set(identity['commands']) == names, 'missing build commands')
    require(len(report['build_logs']) == len(names) + 1 and {log['name'] for log in report['build_logs']} == names | {'clock'},
            'missing build receipts')
    for log in report['build_logs']:
        require(log['exit_status'] == 0, 'failed build receipt')
        command = identity['actual_clock_build'] if log['name'] == 'clock' else identity['actual_build_commands'][log['name']]
        require(log['command'] == command, 'build command mismatch')
    if artifacts:
        for name, digest in identity['sources'].items():
            hash_matches(HERE.parent / name, digest)
        for tool in identity['tools'].values():
            hash_matches(tool.get('compiler_path', tool['path']), tool['sha256'])
            if 'invocation_sha256' in tool:
                hash_matches(tool['path'], tool['invocation_sha256'])
        for name, digest in identity['installed_assets'].items():
            hash_matches(name, digest)
        hash_matches(identity['build_wrapper'], identity['wrapper_sha256'])
        clock = identity['clock_build'][identity['clock_build'].index('-o') + 1]
        for name, digest in report['binary_hashes'].items():
            hash_matches(clock if name == 'native_clock.o' else identity['binary_paths'][name], digest)
    return len(groups)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('--check-artifacts', action='store_true')
    args = parser.parse_args()
    try:
        report = json.loads(args.report.read_text())
        groups = verify(report, args.check_artifacts)
        print(f"PASS complete expanded baseline: {groups} groups, {len(report['samples'])} samples, {len(report['qualification'])} qualifications")
    except (ValueError, KeyError, TypeError, OSError, StopIteration) as error:
        print('FAIL: ' + str(error), file=sys.stderr)
        sys.exit(1)
