#!/usr/bin/env python3
"""Extract lane-relevant count sites from a qualified Lox/EDA counting tag."""
import argparse
import collections
import gzip
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
AREA = Path(__file__).resolve().parents[1]


def load(raw, label):
    return json.loads(gzip.open(raw / (label + '.json.gz'), 'rt').read())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tag', default='base')
    parser.add_argument('--out', type=Path, default=AREA / 'M0')
    args = parser.parse_args()
    raw = ROOT / '.mylang-cache/rp3/ce/raw' / args.tag
    args.out.mkdir(parents=True, exist_ok=True)
    output = {'lox': {}, 'eda': {}}
    lines = [f'# Hot count sites — {args.tag}', '', 'Use only after the counting/output gate qualifies this tag. Totals include inlined source origins. The read_constant execution denominator sums read_constant and read_string function calls, as at M0; if later inlining changes those call boundaries, inspect LLVM and the full count sites before interpreting a per-call ratio.', '',
             '## Lox', '', '| cell | read_constant executions, including read_string | retains | releases | retains / execution | releases / execution |', '|---|---:|---:|---:|---:|---:|']
    for label in ('lox-vm-invocation-1500000', 'lox-vm-method_call-500000'):
        data = load(raw, label)
        calls = sum(function['calls'] for function in data['functions'] if function['name'] in ('vm::read_constant', 'vm::read_string'))
        counts = {kind: sum(site['count'] for site in data['sites'] if site.get('origin') == 'vm::read_constant' and site['kind'] == kind)
                  for kind in ('retain', 'release')}
        copies = collections.Counter()
        for site in data['sites']:
            if site['kind'] == 'record_copy':
                copies[(site['function'], site.get('origin'), site['path'], site['line'], site['detail'])] += site['bytes']
        output['lox'][label] = {'read_constant_executions': calls, **counts,
                               'record_copy_sites': [{'function': key[0], 'origin': key[1], 'path': key[2], 'line': key[3],
                                                      'detail': key[4], 'bytes': value} for key, value in copies.most_common() if value]}
        per_call = [f'{counts[kind] / calls:.3f}' if calls else 'unavailable' for kind in ('retain', 'release')]
        lines.append(f"| {label} | {calls:,} | {counts['retain']:,} | {counts['release']:,} | {' | '.join(per_call)} |")
    lines += ['', 'The complete nonzero record-copy source-site list for these two cells is in hot-counts.json. U2 can identify the frame sites by path and line rather than treating all record traffic as frames.', '',
              '## EDA P6', '', '| design | parse_list record-push copied bytes |', '|---|---:|']
    total = 0
    for path in sorted(raw.glob('eda-*.json.gz')):
        label = path.name.removesuffix('.json.gz')
        data = load(raw, label)
        moved = sum(site['bytes'] for site in data['sites'] if site['kind'] == 'record_copy' and site['detail'] == 'list_push'
                    and site.get('origin') == 'sexpr_parser::parse_list')
        output['eda'][label] = {'parse_list_p6_bytes': moved}
        total += moved
        lines.append(f'| {label} | {moved:,} |')
    assert len(output['eda']) == 34
    output['eda_parse_list_p6_total_bytes'] = total
    lines += ['', f'All 34 designs: **{total:,} bytes** copied by parse_list record pushes. R4\'s ≥90% reduction is measured against M0/hot-counts.json and each representative cell. List-growth movement is a separate counter and is not added to P6. Inspect attribution when construction moves to a new site.', '']
    (args.out / 'hot-counts.json').write_text(json.dumps(output, indent=1) + '\n')
    (args.out / 'hot-counts.md').write_text('\n'.join(lines))
    for label, cell in output['lox'].items():
        print(label, 'read_constant retains/releases:', cell['retain'], cell['release'])
    print('EDA parse_list P6 total:', total, 'bytes across 34 designs')


if __name__ == '__main__':
    main()
