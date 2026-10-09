#!/usr/bin/env python3
"""Require complete parity build/output/timing coverage, independently of speed targets."""
import argparse
import gzip
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'bench/parity'))
import bench_parity as bp


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('receipt', type=Path)
    parser.add_argument('--pair', action='store_true')
    args = parser.parse_args()
    with (gzip.open(args.receipt, 'rt') if args.receipt.suffix == '.gz' else args.receipt.open()) as source:
        data = json.load(source)
    assert data['rounds'] == 9 and data['warmups'] == 2
    expected = {}
    for bench in bp.discover([]):
        arms = bp.arms_for(bench['ports'])
        names = {arm['arm'] for arm in arms}
        if args.pair:
            names.update('base-' + arm['arm'] for arm in arms if arm['lang'] == 'my')
        expected[bench['name']] = names
    assert set(data['benchmarks']) == set(expected)
    for name, names in expected.items():
        bench = data['benchmarks'][name]
        assert set(bench['arms']) == names, name
        for label, arm in bench['arms'].items():
            assert arm['build']['ok'] and arm['status'] == 0 and arm['matches_expected'], (name, label)
            assert 'failure' not in arm and arm['wall_median'] > 0 and len(arm['wall']) == 9, (name, label)
    print('qualified:', len(expected), 'benchmarks,', sum(map(len, expected.values())), 'arms; speed targets reported separately')


if __name__ == '__main__':
    main()
