#!/usr/bin/env python3
"""Summarize the paired demand-artifact builds without conflating reuse with body loads."""
import argparse
import json
import statistics
from pathlib import Path


def summary(path):
    data = json.loads(path.read_text())
    output = {}
    for size in data['sizes']:
        for variant in ('baseline', 'candidate'):
            for phase in ('entry_edit', 'helper_edit', 'three_file_edit'):
                rows = [r for r in data['records']
                        if (str(r['copies']), r['variant'], r['phase']) == (size, variant, phase)]
                if not rows:
                    continue
                stages = [r['cache']['stages'] for r in rows]
                raw = [s['lowering'].get('materialized', s['lowering']['lowered'] + s['lowering']['reused']) for s in stages]
                final = [s['optimizer'].get('final_loaded', s['optimizer']['hits'][5] + s['optimizer']['misses'][5]) for s in stages]
                exact_keys = [s['emission'].get('work', {}).get('keys_built', s['emission']['units']) for s in stages]
                key = f'{size}/{variant}/{phase}'
                output[key] = {
                    'wall_s': {'median': statistics.median(r['seconds'] for r in rows),
                               'min': min(r['seconds'] for r in rows), 'max': max(r['seconds'] for r in rows)},
                    'peak_rss_gib': statistics.median(r['peak_rss_kb'] / 1048576 for r in rows),
                    'raw_bodies_materialized': raw, 'final_bodies_materialized': final,
                    'full_emission_keys_built': exact_keys,
                    'llvm_bytes_materialized_by_emission': [s['emission'].get('work', {}).get('llvm_loaded_bytes') for s in stages],
                    'native_artifact_handles': [s['emission'].get('work', {}).get('native_handles') for s in stages],
                    'native_units_compiled': [r['cache']['compiled'] for r in rows],
                    'frontend_checked': [s['frontend']['checked'] for s in stages],
                    'fallbacks': [s['lowering'].get('fallbacks', 0) for s in stages],
                    'all_paired_binaries_identical': all(r.get('paired_binary_identical', False) for r in rows),
                    'all_allocated_executable_sections_identical': all(
                        r.get('paired_executable_audit', {}).get('allocated_sections_identical') for r in rows),
                    'all_edited_native_objects_identical': all(
                        pair['byte_identical'] for r in rows for pair in r.get('paired_native_audit', [])),
                    'all_execution_checks_passed': all(r.get('execution_check', '').startswith('passed:') for r in rows),
                    'median_stage_seconds': {name: statistics.median(s['nanoseconds'][name] / 1e9 for s in stages)
                                             for name in ('frontend', 'lowering', 'optimizer', 'emission', 'native')},
                }
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('results', type=Path)
    args = parser.parse_args()
    print(json.dumps(summary(args.results), indent=2))
