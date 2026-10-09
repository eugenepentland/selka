#!/usr/bin/env python3
"""Compare fixed-corpus work counts and code size; never infer elapsed-time tax.

Run after ce.py build/run for both tags. Archived raw counters are also accepted.
This is diagnostic evidence under the user's final timing waiver, not a new gate.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[3]
AREA = Path(__file__).resolve().parents[1]
# Memory placement and instrumentation semantics can affect these independently
# of the number of guest allocations/copies. Keep every difference in the output.
CONTEXTUAL = {'realloc_moves', 'realloc_moved_bytes', 'peak_live_bytes',
              'runtime_retains', 'runtime_releases',
              'shared_retains', 'shared_releases', 'share_marks', 'share_bytes'}


def counters(tags):
    found = {}
    for tag in tags:
        for path in (AREA / 'raw' / tag).glob('*.json.gz'):
            found[tag, path.name.removesuffix('.json.gz')] = gzip.decompress(path.read_bytes())
    archive = AREA / 'raw/r3-counter-history.tar.xz'
    with tarfile.open(archive) as stream:
        for member in stream:
            parts = Path(member.name).parts
            if len(parts) == 3 and parts[0] == 'raw' and parts[1] in tags:
                key = parts[1], Path(parts[2]).stem
                found.setdefault(key, stream.extractfile(member).read())
    return found


def differences(before, after):
    return {key: {'base': before.get(key, 0), 'package': after.get(key, 0)}
            for key in sorted(before.keys() | after.keys())
            if before.get(key, 0) != after.get(key, 0)}


def sections(binary):
    text = subprocess.check_output(['size', '-A', str(binary)], text=True)
    values = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0] in {'.text', '.rodata', '.data', '.bss', '.tdata', '.tbss'}:
            values[parts[0]] = int(parts[1])
    return values


def symbols(binary):
    names = {'block_alloc', 'myl_core_free_block', 'core_children', 'core_release_child',
             'core_dict_children', 'core_thread_register_slow'}
    text = subprocess.check_output(['nm', '-S', '--defined-only', str(binary)], text=True)
    result = {}
    for line in text.splitlines():
        parts = line.split(maxsplit=3)
        if len(parts) == 4 and (parts[3] in names or ('json' in parts[3] and 'read_value' in parts[3])):
            result[parts[3]] = int(parts[1], 16)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--package', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    raw = counters([args.base, args.package])
    report = {'kind': 'deterministic work/code-size proxy; elapsed-time overhead UNVERIFIED',
              'base_tag': args.base, 'package_tag': args.package, 'cells': {}, 'binaries': {},
              'contextual_metrics': sorted(CONTEXTUAL), 'correctness_pass': False}
    for group, expected in [('lox', 48), ('eda', 34), ('parity', 4), ('rows', 46)]:
        datasets = [json.loads((AREA / 'results' / tag / (group + '.json')).read_text())
                    for tag in (args.base, args.package)]
        assert datasets[0].keys() == datasets[1].keys() and len(datasets[0]) == expected
        for label in datasets[0]:
            records = [d[label] for d in datasets]
            for r in records:
                assert r['status'] == r['plain_status'] == 0 and r['same_output'] and r['counts'], (group, label, r)
                assert r.get('matches_expected', True) and not r.get('golden_mismatch', []), (group, label, r)
            # Runtime row programs include their own elapsed nanoseconds as a
            # second field. Only the first checksum field is semantic output.
            output_equal = (records[0]['stdout'].split()[:1] == records[1]['stdout'].split()[:1]
                            if group == 'rows' else records[0]['stdout_sha256'] == records[1]['stdout_sha256'])
            assert output_equal and records[0]['stderr'] == records[1]['stderr'], (group, label)
            blobs = [raw[tag, label] for tag in (args.base, args.package)]
            counts = list(map(json.loads, blobs))
            delta = differences(counts[0]['totals'], counts[1]['totals'])
            kind_delta = differences(counts[0]['kinds'], counts[1]['kinds'])
            report['cells'][label] = {'corpus': group, 'output_equal': output_equal,
                'raw_sha256': [hashlib.sha256(b).hexdigest() for b in blobs],
                'totals_differences': delta, 'kind_differences': kind_delta,
                'work_count_differences': {k: v for k, v in delta.items() if k not in CONTEXTUAL}}
    bins = ROOT / '.mylang-cache/concurrency-p1/ce/bin'
    base_binaries = sorted((bins / args.base).glob('*-plain'))
    assert len(base_binaries) == 52
    for binary in base_binaries:
        other = bins / args.package / binary.name
        report['binaries'][binary.name] = {
            'base': {'sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                     'section_bytes': sections(binary), 'selected_symbol_bytes': symbols(binary)},
            'package': {'sha256': hashlib.sha256(other.read_bytes()).hexdigest(),
                        'section_bytes': sections(other), 'selected_symbol_bytes': symbols(other)}}
    report['correctness_pass'] = True
    report['summary'] = {'cells': len(report['cells']), 'plain_binaries': len(report['binaries']),
        'cells_with_work_count_differences': [k for k, v in report['cells'].items() if v['work_count_differences']],
        'cells_with_kind_differences': [k for k, v in report['cells'].items() if v['kind_differences']],
        'cells_with_any_totals_differences': [k for k, v in report['cells'].items() if v['totals_differences']]}
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report['summary'], indent=2))


if __name__ == '__main__':
    main()
