#!/usr/bin/env python3
"""Check frozen guests on unseen inputs; discard all elapsed values."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'expanded'))
from registry import checksum, inventory
sys.path.insert(0, str(HERE.parent))
import runner as common
from build_compiler import validate_receipt

LARGER = ('list_scan', 'bytes_scan', 'dict_lookup', 'dict_lookup_str', 'alloc_retained', 'mutate_nested')
ARMS = common.ARMS


def plans():
    selected = []
    for case, meta in inventory().items():
        small, large = meta['sizes']
        for label, size, seed, count in (('near_small', max(3, small - 3), 12347, 7),
                                        ('near_large', large + 5, 65521, 11)):
            while size & (size - 1) == 0:
                size += 1
            selected.append({'label': label, 'case': case, 'size': size, 'seed': seed, 'iterations': count})
        if case in LARGER:
            selected.append({'label': 'larger', 'case': case, 'size': min(65533, large * 4 + 5),
                             'seed': 104729, 'iterations': 3})
    return selected


def helper_inputs():
    return {str(path.resolve()): common.digest(path) for path in
            (Path(__file__), HERE.parent / 'runner.py', HERE.parent / 'build_compiler.py',
             HERE.parent / 'expanded/registry.py')}


def check_manifest(path, before, document):
    if common.digest(path) != before:
        raise ValueError('holdout compiler manifest changed')
    identity = document['identity']
    names = {meta['group'] + '/' + arm for meta in inventory().values() for arm in ARMS}
    if set(identity['binary_paths']) != names or set(document['binary_hashes']) != names | {'native_clock.o'}:
        raise ValueError('holdout source lacks all24 guests and clock')
    receipt = identity['compiler_build_receipt']
    if common.digest(receipt['path']) != receipt['sha256']:
        raise ValueError('holdout compiler receipt changed')
    validate_receipt(receipt['receipt'], identity['tools']['mylang']['path'], artifacts=True)
    for name, binary in identity['binary_paths'].items():
        if common.digest(binary) != document['binary_hashes'][name]:
            raise ValueError('holdout executable changed')
    if common.digest(path.parent / 'native_clock.o') != document['binary_hashes']['native_clock.o']:
        raise ValueError('holdout native clock changed')
    for source, digest in identity['sources'].items():
        # Frozen guest source and dependency files are required; historical
        # harness scripts can legitimately differ from this new diagnostic.
        if source.startswith('expanded/') and Path(source).suffix in ('.my', '.rs', '.go', '.zig', '.toml', '.lock', '.c'):
            if common.digest(HERE.parent / source) != digest:
                raise ValueError('holdout frozen port source changed')


def verify(report):
    if report['schema'] != 'mylang-runtime-holdouts-v1' or report['status'] != 'correctness_complete':
        raise ValueError('incomplete holdout report')
    if report['plans'] != plans() or report['arms'] != list(ARMS):
        raise ValueError('holdout input policy or arms changed')
    expected = {(plan['label'], plan['case'], plan['size'], plan['seed'], plan['iterations'], arm)
                for plan in plans() for arm in ARMS}
    seen = set()
    for row in report['checks']:
        key = tuple(row[name] for name in ('label', 'case', 'size', 'seed', 'iterations', 'arm'))
        if key not in expected or key in seen:
            raise ValueError('unknown or duplicate holdout cell')
        seen.add(key)
        value = checksum(key[1], key[2], key[4], key[3])
        if type(row['checksum']) is not int or row['checksum'] != value or row['expected_checksum'] != value:
            raise ValueError('holdout checksum mismatch')
        if row['exit_status'] != 0 or row['clock_protocol_validated'] is not True:
            raise ValueError('failed holdout guest or clock protocol')
        if any(name in row for name in ('kernel_ns', 'process_wall_ns', 'elapsed_ns')):
            raise ValueError('holdout evidence must discard elapsed values')
    if seen != expected:
        raise ValueError('missing holdout cells')
    return len(seen)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--verify', type=Path)
    parser.add_argument('--cpu', type=int, default=2)
    args = parser.parse_args()
    if args.verify:
        print('PASS holdout replay: ' + str(verify(json.loads(args.verify.read_text()))) + ' cells')
        return
    if args.manifest is None or args.output is None:
        parser.error('--manifest and --output are required for capture')
    args.manifest, args.output = args.manifest.resolve(), args.output.resolve()
    if args.output == args.manifest or 'results' in args.output.parts or args.cpu not in os.sched_getaffinity(0):
        raise ValueError('invalid holdout output or unavailable CPU')
    inputs_before = helper_inputs()
    manifest_hash = common.digest(args.manifest)
    manifest = json.loads(args.manifest.read_text())
    check_manifest(args.manifest, manifest_hash, manifest)
    report = {'schema': 'mylang-runtime-holdouts-v1', 'status': 'correctness_in_progress',
              'purpose': 'correctness and robustness; no acceptance timings',
              'started_utc': datetime.now(timezone.utc).isoformat(), 'manifest_path': str(args.manifest),
              'manifest_sha256': manifest_hash, 'identity': manifest['identity'],
              'binary_hashes': manifest['binary_hashes'], 'helper_inputs': inputs_before,
              'cpu': args.cpu, 'arms': list(ARMS), 'plans': plans(), 'checks': [],
              'limitations': ['These parameters retain the frozen ports and input-generator shapes; they do not change Unicode/error/alias topology.',
                              'Nearby sizes are non-powers of two; larger working sets are selected scans, maps and retained/nested allocation, capped at65533.',
                              'The clock protocol is validated and all elapsed values discarded; this is not performance evidence.',
                              'Empty input and distinct Unicode/error/alias shapes need separately identified semantic tests.']}
    for plan in report['plans']:
        print('Checking holdout ' + plan['case'] + '/' + plan['label'], flush=True)
        for arm in ARMS:
            binary = Path(manifest['identity']['binary_paths'][inventory()[plan['case']]['group'] + '/' + arm])
            expected = checksum(plan['case'], plan['size'], plan['iterations'], plan['seed'])
            result = common.invoke(binary, plan['case'], plan['size'], plan['iterations'], plan['seed'], args.cpu, expected)
            result.pop('kernel_ns')
            result.pop('process_wall_ns')
            report['checks'].append({**plan, 'arm': arm, **result, 'expected_checksum': expected,
                                     'clock_protocol_validated': True,
                                     'command': ['taskset', '-c', str(args.cpu), str(binary), plan['case'],
                                                 str(plan['size']), str(plan['iterations']), str(plan['seed'])]})
    check_manifest(args.manifest, manifest_hash, manifest)
    if helper_inputs() != inputs_before:
        raise ValueError('holdout helpers changed during capture')
    report.update(status='correctness_complete', finished_utc=datetime.now(timezone.utc).isoformat())
    count = verify(report)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    print('PASS correctness holdouts: ' + str(count) + ' cells; elapsed values discarded')


if __name__ == '__main__':
    main()
