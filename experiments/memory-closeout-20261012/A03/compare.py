#!/usr/bin/env python3
"""Compare pinned census observations; do not infer RSS or timing from counters."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path


def read(path):
    raw = path.read_bytes()
    return json.loads(gzip.decompress(raw) if path.suffix == '.gz' else raw)


def identity(path, data):
    return {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'compiler': data['identities']['compiler'], 'ownership': data['identities']['ownership']}


def observations(run):
    result = {}
    for scope in ('workload', 'whole_program'):
        counters = run.get(scope)
        if counters is None:
            continue
        result[scope] = {key: counters[key] for key in
                         ('allocs', 'reallocs', 'alloc_bytes', 'realloc_added_bytes',
                          'peak_live_bytes', 'live_bytes_at_exit', 'list_copies', 'list_copy_bytes')
                         if key in counters}
        result[scope]['cumulative_allocation_bytes'] = counters['alloc_bytes'] + counters['realloc_added_bytes']
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    before, after = read(args.baseline), read(args.candidate)
    result = {'schema': 'memory-closeout-census-comparison-v1',
              'baseline': identity(args.baseline, before), 'candidate': identity(args.candidate, after),
              'baseline_summary': before['summary'], 'candidate_summary': after['summary'],
              'limitations': [
                  'Only identical source, linked-provider identity, input, environment and expected output contracts are paired.',
                  'Peaks are separate observations; no peak subtraction estimates allocation traffic or RSS.',
                  'List-copy telemetry can change from A09 instrumentation correction 8ba337fd6 without new allocation work.',
                  'These instrumented runs provide no runtime or compiler speed comparison.'],
              'cases': {}}
    for name in sorted(set(before['cases']) | set(after['cases'])):
        old, new = before['cases'].get(name), after['cases'].get(name)
        entry = {'baseline_present': old is not None, 'candidate_present': new is not None, 'modes': {}}
        result['cases'][name] = entry
        if old is None or new is None:
            continue
        entry['same_source'] = old['manifest']['source']['sha256'] == new['manifest']['source']['sha256']
        entry['same_linked_provider'] = old['manifest'].get('link') == new['manifest'].get('link')
        entry['same_run_contracts'] = old['manifest']['runs'] == new['manifest']['runs']
        for mode in sorted(set(old['modes']) | set(new['modes'])):
            left, right = old['modes'].get(mode), new['modes'].get(mode)
            row = {'baseline_status': left['status'] if left else 'unmeasured',
                   'candidate_status': right['status'] if right else 'unmeasured', 'runs': {}}
            entry['modes'][mode] = row
            if not left or not right:
                continue
            for sample in sorted(set(left.get('runs', {})) | set(right.get('runs', {}))):
                a, b = left.get('runs', {}).get(sample), right.get('runs', {}).get(sample)
                paired = bool(a and b and a.get('passed') and b.get('passed') and
                              entry['same_source'] and entry['same_linked_provider'] and entry['same_run_contracts'])
                item = {'paired': paired, 'baseline': observations(a or {}), 'candidate': observations(b or {})}
                row['runs'][sample] = item
                if paired:
                    # Subtract traffic only. Peak and live memory remain the two explicit observations above.
                    item['allocation_traffic_delta'] = {}
                    for scope in item['baseline'].keys() & item['candidate'].keys():
                        item['allocation_traffic_delta'][scope] = {
                            key: item['candidate'][scope][key] - item['baseline'][scope][key]
                            for key in ('allocs', 'reallocs', 'cumulative_allocation_bytes')}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(args.output)


if __name__ == '__main__':
    main()
