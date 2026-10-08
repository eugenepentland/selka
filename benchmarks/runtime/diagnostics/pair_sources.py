#!/usr/bin/env python3
"""Rerun unchanged cases with main, candidate and original winner in one session."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import random
import re
import statistics
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'expanded'))
from registry import checksum, inventory
from verify import verify
sys.path.insert(0, str(HERE.parent))
import runner as common
from build_compiler import validate_receipt
from compare_candidate import bootstrap


def stamp():
    return datetime.now(timezone.utc).isoformat()


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def check_inputs(documents, paths, hashes):
    for label, report in documents.items():
        if sha(paths[label]) != hashes[label]:
            raise ValueError('source report changed')
        entry = report['identity']['compiler_build_receipt']
        if sha(entry['path']) != entry['sha256']:
            raise ValueError('compiler receipt changed')
        validate_receipt(entry['receipt'], report['identity']['tools']['mylang']['path'], artifacts=True)
        for name, path in report['identity']['binary_paths'].items():
            if sha(path) != report['binary_hashes'][name]:
                raise ValueError('source executable changed')
        for row in report.get('frozen_reference', {}).get('plans', []):
            if sha(row['binary_path']) != row['binary_sha256']:
                raise ValueError('original reference changed')


def helper_inputs():
    return {str(path.resolve()): sha(path) for path in
            (Path(__file__), HERE.parent / 'runner.py', HERE.parent / 'build_compiler.py',
             HERE.parent / 'compare_candidate.py', HERE.parent / 'expanded/verify.py',
             HERE.parent / 'expanded/registry.py')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--main', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--cases', nargs='+', required=True)
    parser.add_argument('--extra-manifest', action='append', default=[], metavar='LABEL=PATH',
                        help='additional compiled source, explicitly unmeasured; qualifies all40 MyLang cases')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cpu', type=int, default=2)
    args = parser.parse_args()
    generator_before = sha(__file__)
    helpers_before = helper_inputs()
    if args.cpu not in os.sched_getaffinity(0):
        raise ValueError('timing CPU unavailable')
    if len(set(args.cases)) != len(args.cases) or not set(args.cases) <= set(inventory()):
        raise ValueError('duplicate or unknown source comparison case')
    paths = {'main': args.main.resolve(), 'candidate': args.candidate.resolve()}
    if args.output.resolve() in paths.values() or 'results' in args.output.resolve().parts:
        raise ValueError('source comparison output must preserve input evidence')
    kinds = {'main': 'verified_expanded_report', 'candidate': 'verified_expanded_report'}
    for entry in args.extra_manifest:
        label, path = entry.split('=', 1)
        if re.fullmatch(r'[A-Za-z0-9_-]+', label) is None or label in paths or label == 'original':
            raise ValueError('invalid or duplicate compiled-source label')
        paths[label] = Path(path).resolve()
        kinds[label] = 'unmeasured_compiler_manifest'
    if args.output.resolve() in paths.values():
        raise ValueError('source comparison output must preserve compiled-source inputs')
    hashes = {label: sha(path) for label, path in paths.items()}
    documents = {label: json.loads(path.read_text()) for label, path in paths.items()}
    for label, document in documents.items():
        if kinds[label] == 'verified_expanded_report':
            verify(document, artifacts=False, focused=True)
        else:
            wanted = {meta['group'] + '/' + arm for meta in inventory().values() for arm in common.ARMS}
            if set(document['identity']['binary_paths']) != wanted or set(document['binary_hashes']) != wanted | {'native_clock.o'}:
                raise ValueError('compiled source lacks all24 guests')
            if len(document['build_logs']) != 25 or any(row['exit_status'] != 0 for row in document['build_logs']):
                raise ValueError('compiled source lacks successful build receipts')
    check_inputs(documents, paths, hashes)
    # Every validated expanded input binds all24 binaries and all40 edge probes,
    # even when its selected timing plans were focused. A new session may time
    # another case from those same binaries without inventing a prior timing.
    plans = {label: {(case, size): {'group': meta['group']} for case, meta in inventory().items() for size in meta['sizes']}
             for label in documents}
    references = {(row['case'], row['size']): row for row in documents['main']['frozen_reference']['plans']}
    report = {'schema': 'mylang-runtime-same-session-sources-v1', 'status': 'in_progress', 'started_utc': stamp(),
              'inputs': {label: {'path': str(paths[label]), 'sha256': hashes[label], 'identity': doc['identity'], 'kind': kinds[label],
                                'previously_measured_plans': [[row['case'], row['size']] for row in doc.get('plans', [])]}
                         for label, doc in documents.items()}, 'rounds': 15, 'warmup_rounds': 3,
              'helper_inputs': helpers_before,
              'qualification': [], 'pilots': [], 'plans': [], 'samples': [], 'warmups': [], 'memory': [],
              'limitations': ['Focused source comparison reruns unchanged contracts with two guests per source and the original winner; it is not the full six-arm acceptance report.',
                              'Historical absolute targets stay fixed; source ratios and original-reference ratios use only these new rounds.',
                              'Compiler build modes differ as recorded: no RF/Debug guest equivalence is assumed.',
                              'Paired ratio-of-medians intervals are exploratory and uncorrected for repeated tuning or multiple comparisons.',
                              'One session is not independent confirmation of a faster-than-reference claim.']}
    selected = []
    report['new_source_qualification'] = []
    for label, document in documents.items():
        if kinds[label] != 'unmeasured_compiler_manifest':
            continue
        for case, meta in inventory().items():
            for size, seed, count in ((2, 1, 1), (3, 42, 7), (17, 999983, 31)):
                for arm in ('my-llvm', 'my-qbe'):
                    binary = document['identity']['binary_paths'][meta['group'] + '/' + arm]
                    row = common.invoke(Path(binary), case, size, count, seed, args.cpu, checksum(case, size, count, seed))
                    report['new_source_qualification'].append({'source': label, 'case': case, 'size': size,
                        'iterations': count, 'seed': seed, 'arm': arm, **row})
    for case in args.cases:
        for profile, size in zip(('small', 'large'), inventory()[case]['sizes']):
            key = (case, size)
            if not all(key in entries for entries in plans.values()):
                raise ValueError('missing measured source plan')
            if documents['main']['frozen_reference']['baseline_sha256'] != documents['candidate']['frozen_reference']['baseline_sha256']:
                raise ValueError('different original reference baselines')
            reference = references[key]
            guests = [(label + '/' + arm, doc['identity']['binary_paths'][plans[label][key]['group'] + '/' + arm])
                      for label, doc in documents.items() for arm in ('my-llvm', 'my-qbe')]
            guests.append(('original/' + reference['arm'], reference['binary_path']))
            selected.append((case, size, profile, guests))
            for probe_size, seed, count in ((2, 1, 1), (3, 42, 7), (17, 999983, 31)):
                for label, binary in guests:
                    row = common.invoke(Path(binary), case, probe_size, count, seed, args.cpu, checksum(case, probe_size, count, seed))
                    report['qualification'].append({'case': case, 'size': probe_size, 'iterations': count, 'seed': seed, 'arm': label, **row})
            count = 31
            while True:
                rows = [(label, common.invoke(Path(binary), case, size, count, 42, args.cpu, checksum(case, size, count, 42)))
                        for label, binary in guests]
                report['pilots'].append({'case': case, 'size': size, 'iterations': count, 'arms': dict(rows)})
                fastest, slowest = min(row['kernel_ns'] for _, row in rows), max(row['kernel_ns'] for _, row in rows)
                if fastest >= 50000000 or slowest >= 1000000000 or count >= 10000000:
                    reason = 'target' if fastest >= 50000000 else 'slowest_cap' if slowest >= 1000000000 else 'iteration_cap'
                    break
                growth = min(20, 50000000 / fastest, 1000000000 / slowest)
                if growth < 1.05:
                    reason = 'growth_below_5_percent'
                    break
                count = min(10000000, max(count + 1, int(count * growth)))
            report['plans'].append({'case': case, 'size': size, 'profile': profile, 'iterations': count,
                                     'original_reference': reference, 'guests': dict(guests),
                                     'calibration': {'fastest_ns': fastest, 'slowest_ns': slowest, 'reason': reason,
                                                     'limited': fastest < 50000000, 'target_ns': 50000000,
                                                     'slowest_cap_ns': 1000000000, 'iteration_cap': 10000000}})
    before = common.cpu_snapshot()
    report['measurement_started_utc'] = stamp()
    for plan, (case, size, profile, guests) in zip(report['plans'], selected):
        count = plan['iterations']
        print('Measuring source comparison ' + case + '/' + profile, flush=True)
        for rnd in range(-3, 15):
            order = list(guests)
            random.Random(f'source-pair-v1/{case}/{size}/{rnd}').shuffle(order)
            for label, binary in order:
                row = common.invoke(Path(binary), case, size, count, 42, args.cpu, checksum(case, size, count, 42))
                report['warmups' if rnd < 0 else 'samples'].append({'case': case, 'size': size, 'profile': profile,
                    'iterations': count, 'seed': 42, 'arm': label, 'round': rnd, 'order': [name for name, _ in order], **row})
        for label, binary in guests:
            row = common.invoke(Path(binary), case, size, count, 42, args.cpu, checksum(case, size, count, 42), rss=True)
            report['memory'].append({'case': case, 'size': size, 'iterations': count, 'seed': 42, 'arm': label, **row})
    report['environment'] = common.cpu_environment(args.cpu, before, common.cpu_snapshot())
    check_inputs(documents, paths, hashes)
    report['comparisons'] = []
    for plan in report['plans']:
        case, size = plan['case'], plan['size']
        rows = [row for row in report['samples'] if row['case'] == case and row['size'] == size]
        values = {label: [row['kernel_ns'] for row in sorted(rows, key=lambda row: row['round']) if row['arm'] == label]
                  for label in plan['guests']}
        original = 'original/' + plan['original_reference']['arm']
        earlier = ['main']
        for label in documents:
            if label == 'main':
                continue
            for arm in ('my-llvm', 'my-qbe'):
                for denominator in [*(name + '/' + arm for name in earlier), original]:
                    numerator = label + '/' + arm
                    ratio = statistics.median(values[numerator]) / statistics.median(values[denominator])
                    interval = bootstrap(values[numerator], values[denominator], f'source-pair-v1/{case}/{size}/{numerator}/{denominator}')
                    report['comparisons'].append({'case': case, 'size': size, 'profile': plan['profile'],
                                                  'numerator': numerator, 'denominator': denominator,
                                                  'ratio_of_medians': ratio, 'paired_bootstrap_95_interval': interval})
            earlier.append(label)
    if sha(__file__) != generator_before:
        raise ValueError('source comparison generator changed while running')
    if helper_inputs() != helpers_before:
        raise ValueError('source comparison helper inputs changed while running')
    report.update(status='focused_complete', finished_utc=stamp(), generator_sha256=generator_before)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    print('PASS source comparison: ' + str(args.output))


if __name__ == '__main__':
    main()
