#!/usr/bin/env python3
"""Read qualified base/final journals for U2 exits; never execute guests or infer frame wins.

All 37 VM journals must already pass counting-on/off and output qualification.
Origin paths/lines refer to the frozen Lox source. Inspect unclassified_vm_copies
if later lowering moves attribution; this tool must not silently relabel them.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path

FRAME_READ_LINES = {430, 496, 503, 510, 525}
HEADLINES = ('lox-vm-invocation-1500000', 'lox-vm-method_call-500000')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def origin(site):
    return site.get('origin') or site['function']


def journal(path):
    raw = path.read_bytes()
    return json.loads(gzip.decompress(raw)), {'path': str(path), 'sha256': digest(raw), 'bytes': len(raw)}


def traffic(data):
    counts = {kind: sum(site['count'] for site in data['sites']
                        if origin(site) == 'vm::read_constant' and site['kind'] == kind)
              for kind in ('retain', 'release')}
    calls = sum(f['calls'] for f in data['functions'] if f['name'] in ('vm::read_constant', 'vm::read_string'))
    return {**counts, 'executions_from_retained_call_boundaries': calls,
            'per_execution': {kind: value / calls if calls else None for kind, value in counts.items()}}


def frames(data):
    selected, unclassified, excluded = [], [], []
    for site in data['sites']:
        if site['kind'] != 'record_copy' or not site['bytes']:
            continue
        who, path = origin(site), Path(site['path']).name
        if who == 'heap::function_obj' and site['line'] == 144:
            excluded.append(site)
            continue
        width = None
        if path == 'vm.my' and who == 'vm::run' and site['line'] in FRAME_READ_LINES and site['detail'] == 'list_get':
            width = 88
        elif path == 'vm.my' and who == 'vm::call' and site['line'] == 135 and site['detail'] == 'list_set':
            width = 48
        if width is not None:
            assert site['count'] > 0 and site['bytes'] == width * site['count'], ('Unexpected frame layout/site', site, width)
            selected.append({**site, 'bytes_per_copy': width})
        elif who in ('vm::run', 'vm::call') or site['function'] in ('vm::run', 'vm::call'):
            unclassified.append(site)
    return {'bytes': sum(site['bytes'] for site in selected), 'sites': selected,
            'unclassified_vm_copies': unclassified, 'excluded_heap_function_obj_144': excluded,
            'all_record_copy_bytes': sum(site['bytes'] for site in data['sites'] if site['kind'] == 'record_copy')}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base-tag', default='base')
    parser.add_argument('--candidate-tag', required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[3],
                        help='worktree root; override when running the scratch proposal')
    args = parser.parse_args()
    raw = args.root.resolve() / '.mylang-cache/rp3/ce/raw'
    paths = {tag: {p.name.removesuffix('.json.gz'): p for p in (raw / tag).glob('lox-vm-*.json.gz')}
             for tag in (args.base_tag, args.candidate_tag)}
    assert args.base_tag != args.candidate_tag
    base_paths, candidate_paths = paths[args.base_tag], paths[args.candidate_tag]
    assert len(base_paths) == 37 and set(base_paths) == set(candidate_paths), ('Missing or extra VM cells', sorted(base_paths), sorted(candidate_paths))
    assert set(HEADLINES) <= set(base_paths)
    cells, headlines = {}, {}
    for label in sorted(base_paths):
        base, base_id = journal(base_paths[label])
        candidate, candidate_id = journal(candidate_paths[label])
        before, after = traffic(base), traffic(candidate)
        cells[label] = {'base': before, 'candidate': after,
                        'delta': {kind: after[kind] - before[kind] for kind in ('retain', 'release')},
                        'candidate_zero': after['retain'] == 0 and after['release'] == 0,
                        'journals': {'base': base_id, 'candidate': candidate_id}}
        if label in HEADLINES:
            a, b = frames(base), frames(candidate)
            ratio = b['bytes'] / a['bytes'] if a['bytes'] else None
            headlines[label] = {'base': a, 'candidate': b, 'candidate_over_base': ratio,
                                'measured_reduction': 1 - ratio if ratio is not None else None,
                                'required_reduction': 0.80}
    result = {'complete': True, 'base_tag': args.base_tag, 'candidate_tag': args.candidate_tag,
              'precondition': 'Both tags passed the separate complete counting/output qualification.',
              'read_constant_denominator_note': 'Execution denominator sums read_constant and read_string retained function-call counters, matching M0. If call boundaries change, verify the denominator against IR; absolute zero traffic does not depend on it.',
              'frame_method': 'Origin-aware frozen vm.my sites only: vm::run list_get 430/496/503/510/525 at88B and vm::call list_set135 at48B; validate bytes/count. Heap function_obj144 excluded. Inspect every unclassified VM record-copy site for attribution changes.',
              'vm_cells': len(cells), 'candidate_zero_all_vm_cells': all(cell['candidate_zero'] for cell in cells.values()),
              'read_constant': cells, 'headline_frames': headlines}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=1) + '\n')
    print('VM cells',len(cells),'zero traffic in all',result['candidate_zero_all_vm_cells'])
    for label, cell in headlines.items():
        print(label, 'base bytes',cell['base']['bytes'],'candidate bytes',cell['candidate']['bytes'],'reduction',cell['measured_reduction'])


if __name__ == '__main__':
    main()
