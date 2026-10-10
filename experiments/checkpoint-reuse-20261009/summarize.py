#!/usr/bin/env python3
"""Summarize checkpoint reuse without hiding intermediate artifact decoding."""
import argparse
import gzip
import json
from pathlib import Path
from statistics import median


def summarize(path):
    text = gzip.decompress(path.read_bytes()).decode() if path.suffix == '.gz' else path.read_text()
    report = json.loads(text)
    result = {}
    for size in report['sizes']:
        for variant in ('baseline', 'candidate'):
            for phase in ('entry_edit', 'helper_edit', 'three_file_edit'):
                rows = [r for r in report['records']
                        if (str(r['copies']), r['variant'], r['phase']) == (size, variant, phase)]
                if not rows:
                    continue
                stages = [r['cache']['stages'] for r in rows]
                profiles = [s['nanoseconds'].get('frontend_phases', []) for s in stages]
                result[f'{size}/{variant}/{phase}'] = {
                    'lines': report['sizes'][size]['physical_lines'],
                    'wall_s': {'median': median(r['seconds'] for r in rows),
                               'min': min(r['seconds'] for r in rows),
                               'max': max(r['seconds'] for r in rows)},
                    'peak_rss_gib': median(r['peak_rss_kb'] / 1048576 for r in rows),
                    'raw_bodies_materialized': [s['lowering'].get('materialized', s['lowering']['reused'] + s['lowering']['lowered']) for s in stages],
                    'final_bodies_materialized': [s['optimizer'].get('final_loaded', s['optimizer']['hits'][5] + s['optimizer']['misses'][5]) for s in stages],
                    'checkpoint_records_decoded': [s['optimizer'].get('restores', {}).get('checkpoints', 0) for s in stages],
                    'fresh_optimizer_functions': [s['optimizer'].get('fresh_work') for s in stages],
                    'llvm_keys_built': [s['emission'].get('work', {}).get('keys_built', s['emission']['units']) for s in stages],
                    'native_units_compiled': [r['cache']['compiled'] for r in rows],
                    'fallbacks': [s['lowering'].get('fallbacks', 0) for s in stages],
                    'stage_median_s': {name: median(s['nanoseconds'][name] / 1e9 for s in stages)
                                       for name in ('frontend', 'lowering', 'optimizer', 'emission', 'native', 'linker')},
                    'frontend_phase_median_s': {name: median(p['nanoseconds'] / 1e9 for profile in profiles
                                                           for p in profile if p['name'] == name)
                                                for name in sorted({p['name'] for profile in profiles for p in profile})},
                    'paired_binaries_identical': all(r['paired_binary_identical'] for r in rows),
                    'paired_allocated_sections_identical': all(r['paired_executable_audit']['allocated_sections_identical'] for r in rows),
                    'paired_edited_objects_identical': all(p['byte_identical'] for r in rows for p in r['paired_native_audit']),
                    'execution_checks_passed': all(r['execution_check'].startswith('passed:') for r in rows),
                }
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('results', type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(args.results), indent=2))
