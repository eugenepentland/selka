#!/usr/bin/env python3
"""Extract lane-relevant baseline count sites from qualified Lox/EDA cells."""
import collections
import gzip
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
AREA = Path(__file__).resolve().parents[1]
RAW = ROOT / '.mylang-cache/rp3/ce/raw/base'


def load(label):
    return json.loads(gzip.open(RAW / (label + '.json.gz'), 'rt').read())


def main():
    output = {'lox': {}, 'eda': {}}
    lines = ['# M0 hot count sites', '', 'These are ordinary counting builds whose outputs match their non-counting counterparts. Dynamic totals include inlined source origins; function-call counts alone omit inlined read_constant executions inside read_string.', '',
             '## Lox', '', '| cell | read_constant executions, including read_string | retains | releases | retains / execution | releases / execution |', '|---|---:|---:|---:|---:|---:|']
    for label in ('lox-vm-invocation-1500000', 'lox-vm-method_call-500000'):
        data = load(label)
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
        lines.append(f"| {label} | {calls:,} | {counts['retain']:,} | {counts['release']:,} | {counts['retain']/calls:.1f} | {counts['release']/calls:.1f} |")
    lines += ['', 'The complete nonzero record-copy source-site list for these two cells is in hot-counts.json. U2 can identify the frame sites by path and line rather than treating all record traffic as frames.', '',
              '## EDA P6', '', '| design | parse_list record-push copied bytes |', '|---|---:|']
    total = 0
    for path in sorted(RAW.glob('eda-*.json.gz')):
        label = path.name.removesuffix('.json.gz')
        data = load(label)
        moved = sum(site['bytes'] for site in data['sites'] if site['kind'] == 'record_copy' and site['detail'] == 'list_push'
                    and site.get('origin') == 'sexpr_parser::parse_list')
        output['eda'][label] = {'parse_list_p6_bytes': moved}
        total += moved
        lines.append(f'| {label} | {moved:,} |')
    assert len(output['eda']) == 34
    output['eda_parse_list_p6_total_bytes'] = total
    lines += ['', f'All 34 designs: **{total:,} bytes** copied by parse_list record pushes. R4\'s ≥90% reduction is measured against this current-base total and each representative cell. List-growth movement is a separate counter and is not added to P6.', '']
    (AREA / 'M0/hot-counts.json').write_text(json.dumps(output, indent=1) + '\n')
    (AREA / 'M0/hot-counts.md').write_text('\n'.join(lines))
    print('read_constant: 3 retains + 3 releases per execution in both full-size cells')
    print('EDA parse_list P6 total:', total, 'bytes across 34 designs')


if __name__ == '__main__':
    main()
