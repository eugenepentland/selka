#!/usr/bin/env python3
"""Replay diagnostic coverage, checksum and paired-statistic checks without guests."""
import argparse
from collections import Counter
import json
import math
from pathlib import Path
import random
import statistics
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'expanded'))
from registry import checksum as original_checksum, inventory

ARMS = ('my-llvm', 'my-qbe', 'rust', 'go', 'zig-safe', 'zig-fast')
CASES = {'dispatch_outside': 'integer_math', 'arithmetic_only': 'integer_math',
         'collection_only': 'list_scan', 'text_without_score': 'int_format', 'escaped_allocation': 'alloc_short'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def positive(value):
    require(type(value) in (int, float) and math.isfinite(value) and value > 0, 'invalid diagnostic elapsed time')


def result(row, expected):
    require(type(row.get('checksum')) is int and row['checksum'] == expected, 'diagnostic checksum mismatch')
    require(row.get('exit_status') == 0 and row.get('stderr', '') == '', 'failed diagnostic guest')
    positive(row.get('kernel_ns'))
    if 'process_wall_ns' in row:
        positive(row['process_wall_ns'])


def interval(values, references, seed):
    require(len(values) == len(references) and bool(values), 'missing paired diagnostic rounds')
    generator = random.Random(seed)
    samples = []
    for _ in range(2000):
        indexes = [generator.randrange(len(values)) for _ in values]
        samples.append(statistics.median([values[i] for i in indexes]) / statistics.median([references[i] for i in indexes]))
    samples.sort()
    return [samples[49], samples[1949]]


def close(actual, expected, message):
    require(type(actual) in (int, float) and math.isfinite(actual)
            and math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), message)


def component_checksum(variant, role, size, count, seed):
    if role == 'control' or variant in ('dispatch_outside', 'escaped_allocation'):
        return original_checksum(CASES[variant], size, count, seed)
    modulus = 1000000007
    if variant == 'collection_only':
        total = sum((seed + index * 13) % 1009 for index in range(size))
        return total * count % modulus
    if variant == 'arithmetic_only':
        totals = [sum(((index + phase) * 17 + 23) // 7 % 1009 for index in range(size)) for phase in range(17)]
        return (sum(totals) * (count // 17) + sum(totals[:count % 17])) % modulus
    numbers = [(seed + index * 137) % 1000003 for index in range(size)]
    words = [str(-number if index % 3 == 0 else number) for index, number in enumerate(numbers)]
    period = [len(words[(seed + step) % size]) for step in range(size)]
    return (sum(period) * (count // size) + sum(period[:count % size])) % modulus


def verify_components(report):
    require(report['schema'] == 'mylang-runtime-components-v1' and report['status'] == 'diagnostic_complete', 'incomplete component diagnostic')
    require(type(report['rounds']) is int and report['rounds'] >= 1 and type(report['warmup_rounds']) is int and report['warmup_rounds'] >= 0, 'invalid diagnostic rounds')
    plans = {(row['variant'], row['size']): row for row in report['plans']}
    wanted = {(variant, size) for variant, case in CASES.items() for size in inventory()[case]['sizes']}
    require(len(plans) == len(report['plans']) and set(plans) == wanted, 'incomplete or duplicate component plans')
    groups = {}
    for field, rounds in (('samples', range(report['rounds'])), ('warmups', range(-report['warmup_rounds'], 0)), ('memory', (None,))):
        expected_keys = {(variant, size, role, arm, rnd) for variant, size in wanted for role in ('control', 'probe') for arm in ARMS for rnd in rounds}
        seen = set()
        for row in report[field]:
            key = (row['variant'], row['size'], row['role'], row['arm'], row.get('round') if field != 'memory' else None)
            require(key in expected_keys and key not in seen, 'duplicate or unknown component cell')
            seen.add(key)
            plan = plans[key[:2]]
            require(row['iterations'] == plan['iterations'] and row['seed'] == 42, 'component plan drift')
            result(row, component_checksum(key[0], key[2], key[1], row['iterations'], 42))
            if field == 'samples':
                order = row['order']
                require(len(order) == 12 and set(order) == {role + '/' + arm for role in ('control', 'probe') for arm in ARMS}, 'component order lacks all12 guests')
                groups.setdefault(key[:4], {})[key[4]] = row['kernel_ns']
        require(seen == expected_keys, 'missing component cells')
    wanted_probes = {(variant, role, arm, size, seed, count) for variant in CASES for role in ('control', 'probe')
                     for arm in ARMS for size, seed, count in ((2, 1, 1), (3, 42, 7), (17, 999983, 31))}
    seen = set()
    for row in report['qualification']:
        key = tuple(row[name] for name in ('variant', 'role', 'arm', 'size', 'seed', 'iterations'))
        require(key in wanted_probes and key not in seen, 'unknown or duplicate component qualification')
        seen.add(key)
        result(row, component_checksum(key[0], key[1], key[3], key[5], key[4]))
    require(seen == wanted_probes, 'missing component qualification')
    seen = set()
    for row in report['comparisons']:
        key = (row['variant'], row['size'], row['arm'])
        require(key not in seen and key[:2] in plans and key[2] in ARMS, 'invalid component comparison')
        seen.add(key)
        values = {role: [groups[(*key[:2], role, key[2])][rnd] for rnd in range(report['rounds'])] for role in ('control', 'probe')}
        ratio = statistics.median(values['probe']) / statistics.median(values['control'])
        close(row['probe_to_control'], ratio, 'component ratio math mismatch')
        count = plans[key[:2]]['iterations']
        for role in ('control', 'probe'):
            close(row[role + '_ns_per_iteration'], statistics.median(values[role]) / count, 'component median math mismatch')
        expected = interval(values['probe'], values['control'], f'components-v1/{key[0]}/{key[1]}/{key[2]}')
        require(len(row['paired_bootstrap_95_interval']) == 2, 'invalid component interval')
        for actual, value in zip(row['paired_bootstrap_95_interval'], expected):
            close(actual, value, 'component interval math mismatch')
    require(seen == {(variant, size, arm) for variant, size in wanted for arm in ARMS}, 'missing component comparison')
    return len(groups)


def verify_sources(report):
    require(report['schema'] == 'mylang-runtime-same-session-sources-v1' and report['status'] == 'focused_complete', 'incomplete source comparison')
    require(report['rounds'] == 15 and report['warmup_rounds'] == 3, 'source comparison needs milestone rounds')
    plans = {(row['case'], row['size']): row for row in report['plans']}
    require(bool(plans), 'empty source comparison')
    cases = {case for case, _ in plans}
    require(len(plans) == len(report['plans']) and set(plans) == {(case, size) for case in cases for size in inventory()[case]['sizes']}, 'missing or duplicate source plans')
    sources = list(report['inputs'])
    require(sources[:2] == ['main', 'candidate'], 'source labels/order drift')
    groups = {}
    for field, rounds in (('samples', range(15)), ('warmups', range(-3, 0)), ('memory', (None,))):
        wanted = {(case, size, arm, rnd) for (case, size), plan in plans.items() for arm in plan['guests'] for rnd in rounds}
        seen = set()
        for row in report[field]:
            key = (row['case'], row['size'], row['arm'], row.get('round') if field != 'memory' else None)
            require(key in wanted and key not in seen, 'duplicate or unknown source cell')
            seen.add(key)
            plan = plans[key[:2]]
            require(row['iterations'] == plan['iterations'] and row['seed'] == 42, 'source plan drift')
            result(row, original_checksum(key[0], key[1], row['iterations'], 42))
            if field == 'samples':
                require(len(row['order']) == len(plan['guests']) and set(row['order']) == set(plan['guests']), 'source round order drift')
                groups.setdefault(key[:3], {})[key[3]] = row['kernel_ns']
        require(seen == wanted, 'missing source cells')
    probes = Counter()
    for row in report['qualification']:
        key = tuple(row[name] for name in ('case', 'arm', 'size', 'seed', 'iterations'))
        probes[key] += 1
        result(row, original_checksum(key[0], key[2], key[4], key[3]))
    expected_probes = Counter({(case, arm, size, seed, count): 2 for case in cases for arm in plans[(case, inventory()[case]['sizes'][0])]['guests']
                               for size, seed, count in ((2, 1, 1), (3, 42, 7), (17, 999983, 31))})
    require(probes == expected_probes, 'missing or duplicate source qualification')
    # Source controls deliberately requalify the same edge probes before each size.
    wanted_extra = {(label, case, arm, size, seed, count) for label, meta in report['inputs'].items()
                    if meta.get('kind') == 'unmeasured_compiler_manifest' for case in inventory()
                    for arm in ('my-llvm', 'my-qbe') for size, seed, count in ((2, 1, 1), (3, 42, 7), (17, 999983, 31))}
    seen_extra = set()
    for row in report.get('new_source_qualification', []):
        key = tuple(row[name] for name in ('source', 'case', 'arm', 'size', 'seed', 'iterations'))
        require(key in wanted_extra and key not in seen_extra, 'invalid new-source qualification')
        seen_extra.add(key)
        result(row, original_checksum(key[1], key[3], key[5], key[4]))
    require(seen_extra == wanted_extra, 'missing new-source full qualification')
    expected_comparisons = set()
    for (case, size), plan in plans.items():
        wanted_guests = {label + '/' + arm for label in sources for arm in ('my-llvm', 'my-qbe')}
        original = 'original/' + plan['original_reference']['arm']
        require(set(plan['guests']) == wanted_guests | {original}, 'source plan lacks expected guests')
        for index, label in enumerate(sources[1:], 1):
            for arm in ('my-llvm', 'my-qbe'):
                for denominator in [*(name + '/' + arm for name in sources[:index]), original]:
                    expected_comparisons.add((case, size, label + '/' + arm, denominator))
    seen = set()
    for row in report['comparisons']:
        key = tuple(row[name] for name in ('case', 'size', 'numerator', 'denominator'))
        require(key in expected_comparisons and key not in seen, 'invalid source comparison')
        seen.add(key)
        values = [groups[(key[0], key[1], key[2])][rnd] for rnd in range(15)]
        references = [groups[(key[0], key[1], key[3])][rnd] for rnd in range(15)]
        close(row['ratio_of_medians'], statistics.median(values) / statistics.median(references), 'source ratio math mismatch')
        expected = interval(values, references, f'source-pair-v1/{key[0]}/{key[1]}/{key[2]}/{key[3]}')
        require(len(row['paired_bootstrap_95_interval']) == 2, 'invalid source interval')
        for actual, value in zip(row['paired_bootstrap_95_interval'], expected):
            close(actual, value, 'source interval math mismatch')
    require(seen == expected_comparisons, 'missing source comparisons')
    return len(groups)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    args = parser.parse_args()
    report = json.loads(args.report.read_text())
    count = verify_components(report) if report['schema'] == 'mylang-runtime-components-v1' else verify_sources(report)
    print('PASS diagnostic replay: ' + str(count) + ' groups')


if __name__ == '__main__':
    main()
