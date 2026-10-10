#!/usr/bin/env python3
"""Require all 199 counting cells and preserve M0's qualified plain outputs."""
import argparse
import hashlib
import json
from pathlib import Path

AREA = Path(__file__).resolve().parents[1]
SIZES = {'lox': 74, 'eda': 34, 'parity': 45, 'rows': 46}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tag', required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    result = {'complete': False, 'tag': args.tag, 'cells': 0, 'groups': {}}
    for group, expected in SIZES.items():
        base = json.loads((AREA / 'results/base' / (group + '.json')).read_text())
        path = AREA / 'results' / args.tag / (group + '.json')
        cells = json.loads(path.read_text())
        assert len(cells) == expected and set(cells) == set(base), group
        for name, cell in cells.items():
            assert cell['status'] == cell['plain_status'] == 0 and cell['same_output'] and cell['counts'], name
            if group == 'rows':
                # Native-clock elapsed time is not part of the row checksum.
                assert cell['stdout'].split()[0] == base[name]['stdout'].split()[0], name
            else:
                assert cell['stdout_sha256'] == base[name]['stdout_sha256'], name
            if group == 'parity':
                assert cell['matches_expected'], name
            if group == 'eda':
                assert cell['golden_mismatch'] == [], name
        result['groups'][group] = {'cells': expected, 'all_status_zero': True, 'all_same_output': True,
                                   'all_counts_present': True, 'all_match_m0': True,
                                   'receipt': str(path.relative_to(AREA)),
                                   'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        result['cells'] += len(cells)
    assert result['cells'] == 199
    result['complete'] = True
    args.out.write_text(json.dumps(result, indent=1) + '\n')
    print('199/199 counting cells: outputs match on/off and M0; 45 parity expected and 34 EDA goldens pass')


if __name__ == '__main__':
    main()
