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


def verify(report, artifacts=False, focused=False):
    require(report.get('schema') in ('mylang-runtime-expanded-v1', 'mylang-runtime-expanded-v2'), 'wrong schema')
    require(report.get('status') in (('complete', 'subset') if focused else ('complete',))
            and report.get('profile') == 'baseline', 'not a complete baseline or permitted focused candidate')
    cases = inventory()
    require(report.get('inventory') == cases, 'case inventory mismatch')
    selected = report['coverage']
    require(bool(selected) and len(selected) == len(set(selected)) and set(selected) <= set(cases), 'invalid coverage')
    require(focused or set(selected) == set(cases), 'incomplete coverage')
    require((report['status'] == 'complete') == (set(selected) == set(cases)), 'incorrect full/subset status')
    rounds, warmups = report['rounds'], report['warmup_rounds']
    require(type(rounds) is int and rounds >= 1 and type(warmups) is int and warmups >= 0, 'invalid rounds')
    wanted = {(p['case'], p['size']): p for p in plans_for(selected)}
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
    if report['schema'] == 'mylang-runtime-expanded-v1':
        require(identity['pinned_revision'] == REVISION, 'wrong compiler revision')
    else:
        import re
        require(isinstance(identity.get('candidate_id'), str) and bool(identity['candidate_id']), 'missing candidate ID')
        require(re.fullmatch(r'[0-9a-f]{40}', identity.get('source_revision', '')) is not None, 'invalid compiler revision')
        receipt = identity['compiler_build_receipt']['receipt']
        require(receipt.get('schema') == 'mylang-runtime-compiler-build-v1' and receipt.get('status') == 'complete'
                and receipt.get('exit_status') == 0, 'missing successful compiler build receipt')
        require(receipt['source_revision'] == identity['source_revision']
                and receipt['sources_before'] == receipt['sources_after'] and bool(receipt['sources_after']), 'invalid compiler source receipt')
        require(receipt['compiler_sha256'] == identity['tools']['mylang']['sha256'], 'compiler receipt hash mismatch')
        require(bool(report.get('measurement_session_id')), 'missing measurement session ID')
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
    if report['schema'] == 'mylang-runtime-expanded-v2':
        frozen_path = HERE / 'results/baseline_main_20261003.json'
        frozen_hash = 'b595d9638e243e18692b5cef491c2b5273949c93ebf22a0ae604a08704c1d3f7'
        hash_matches(frozen_path, frozen_hash)
        original = json.loads(frozen_path.read_text())
        frozen = report['frozen_reference']
        require(frozen['baseline_sha256'] == frozen_hash and frozen['original_identity'] == original['identity'],
                'frozen reference identity differs from immutable baseline')
        references = {}
        supplemental = set()
        for reference in frozen['plans']:
            key = (reference['case'], reference['size'])
            require(key in plans and key not in references, 'unknown/duplicate frozen reference plan')
            references[key] = reference
            rows = [row for row in original['summary'] if (row['case'], row['size']) == key]
            fastest = min(rows, key=lambda row: (row['median_ns_per_op'], ARMS.index(row['arm'])))
            name = plans[key]['group'] + '/' + fastest['arm']
            require(reference['arm'] == fastest['arm'] and reference['name'] == name
                    and reference['target_ns_per_iteration'] == fastest['median_ns_per_op']
                    and reference['binary_path'] == original['identity']['binary_paths'][name]
                    and reference['binary_sha256'] == original['binary_hashes'][name], 'incorrect frozen reference receipt')
            if report['binary_hashes'][name] != reference['binary_sha256']:
                supplemental.add((*key, reference['arm']))
            if artifacts:
                hash_matches(reference['binary_path'], reference['binary_sha256'])
        require(set(references) == set(plans), 'missing frozen reference plans')
        for field, rnds in (('frozen_reference_samples', range(rounds)), ('frozen_reference_warmups', range(-warmups, 0))):
            wanted_references = {(*key, rnd) for key in supplemental for rnd in rnds}
            seen_references = set()
            for row in report[field]:
                key = (row['case'], row['size'], row['arm'], row['round'])
                require(key in wanted_references and key not in seen_references, 'unknown/duplicate supplemental reference round')
                seen_references.add(key)
                plan = plans[key[:2]]
                for name in ('iterations', 'seed', 'profile', 'group', 'family', 'level', 'unit', 'expected'):
                    require(row[name] == plan[name], 'supplemental reference plan drift')
                result(row, plan['expected'])
            require(seen_references == wanted_references, 'missing supplemental reference rounds')
    if artifacts:
        if report['schema'] == 'mylang-runtime-expanded-v2':
            sys.path.insert(0, str(HERE.parent))
            from build_compiler import validate_receipt
            entry = identity['compiler_build_receipt']
            hash_matches(entry['path'], entry['sha256'])
            require(json.loads(Path(entry['path']).read_text()) == entry['receipt'], 'compiler receipt content mismatch')
            validate_receipt(entry['receipt'], identity['tools']['mylang']['path'], artifacts=True)
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
    parser.add_argument('--focused', action='store_true', help='verify an explicitly labeled subset candidate')
    args = parser.parse_args()
    try:
        report = json.loads(args.report.read_text())
        groups = verify(report, args.check_artifacts, args.focused)
        print(f"PASS complete expanded baseline: {groups} groups, {len(report['samples'])} samples, {len(report['qualification'])} qualifications")
    except (ValueError, KeyError, TypeError, OSError, StopIteration) as error:
        print('FAIL: ' + str(error), file=sys.stderr)
        sys.exit(1)
