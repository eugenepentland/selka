#!/usr/bin/env python3
"""Keep exact count files in owned scratch and commit compact totals and detailed source-site sums for hot cells."""
import argparse
import collections
import gzip
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[3]
AREA = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tag', required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    source = AREA / 'raw' / args.tag
    destination = ROOT / '.mylang-cache/rp3/ce/raw' / args.tag
    destination.mkdir(parents=True, exist_ok=True)
    for path in source.glob('*.json.gz'):
        shutil.move(path, destination / path.name)
    if source.exists() and not list(source.iterdir()):
        source.rmdir()
    result = {'tag': args.tag, 'format': 'rp3-count-sums-v1',
              'method': 'Exact raw gzip files retained in owned cache. Totals and kinds retained for every cell. Hot cells retain functions and summed identical source-site identities; zero sites omitted.',
              'cells': {}}
    for path in sorted(destination.glob('*.json.gz')):
        data = json.loads(gzip.open(path, 'rt').read())
        groups = {}
        for site in data['sites']:
            if not (site['count'] or site['bytes'] or site['extra']):
                continue
            identity = tuple(sorted((key, value) for key, value in site.items() if key not in ('count', 'bytes', 'extra')))
            group = groups.setdefault(identity, {**dict(identity), 'count': 0, 'bytes': 0, 'extra': 0})
            for key in ('count', 'bytes', 'extra'):
                group[key] += site[key]
        for key in ('count', 'bytes', 'extra'):
            assert sum(site[key] for site in groups.values()) == sum(site[key] for site in data['sites'])
        label = path.name.removesuffix('.json.gz')
        detailed = label in {
            'lox-vm-invocation-1500000', 'lox-vm-method_call-500000', 'lox-vm-fib-34',
            'lox-vm-string_equality-100000', 'lox-tree-equality-300000', 'lox-tree-string_equality-10000',
            'eda-rds3+flat', 'eda-labstation', 'parity-text_ops', 'parity-scan_split',
            'parity-knucleotide', 'parity-fannkuch_redux_array', 'parity-fannkuch_redux_tuned',
            'parity-sort_builtin', 'parity-records', 'parity-nbody', 'row-record_pass',
            'row-result_propagate', 'row-option_handle'}
        result['cells'][label] = {
            'raw_sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'raw_scratch': str(path.relative_to(ROOT)),
            'totals': data['totals'], 'kinds': data['kinds'], 'detailed': detailed,
            **({'functions': data['functions'], 'sites': list(groups.values())} if detailed else {})}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(args.out, 'wt', compresslevel=9) as output:
        json.dump(result, output, separators=(',', ':'))
    print(len(result['cells']), 'count cells summarized in', args.out.stat().st_size, 'bytes', flush=True)


if __name__ == '__main__':
    main()
