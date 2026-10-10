#!/usr/bin/env python3
"""Report edited-build timing and work without conflating loads with fresh work."""
import argparse
import gzip
import json
from pathlib import Path
from statistics import median


def summarize(path):
    raw = gzip.decompress(path.read_bytes()) if path.suffix == '.gz' else path.read_bytes()
    report = json.loads(raw)
    result = {}
    for size, fixture in report['sizes'].items():
        for variant in ('baseline', 'candidate'):
            for phase in ('entry_edit', 'helper_edit', 'three_file_edit'):
                rows = [r for r in report['records']
                        if (str(r['copies']), r['variant'], r['phase']) == (size, variant, phase)]
                if not rows:
                    continue
                stages = [r['cache']['stages'] for r in rows]
                result[f'{size}/{variant}/{phase}'] = {
                    'lines': fixture['physical_lines'],
                    'wall_s': {'median': median(r['seconds'] for r in rows),
                               'min': min(r['seconds'] for r in rows),
                               'max': max(r['seconds'] for r in rows)},
                    'peak_rss_gib': median(r['peak_rss_kb'] / 1048576 for r in rows),
                    'frontend_bodies_checked': [s['frontend']['checked'] for s in stages],
                    'frontend_bodies_omitted': [s['lowering']['deferred'] for s in stages],
                    'frontend_trees_replayed': [s['frontend']['reused'] - s['lowering']['deferred'] for s in stages],
                    'frontend_phase_median_s': {
                        name: median(next((p['nanoseconds'] for p in s['nanoseconds']['frontend_phases'] if p['name'] == name), 0) / 1e9 for s in stages)
                        for name in sorted({p['name'] for s in stages for p in s['nanoseconds']['frontend_phases'] if not p['inclusive']})},
                    'raw_bodies_materialized': [s['lowering']['materialized'] for s in stages],
                    'raw_bodies_freshly_lowered': [s['lowering']['lowered'] for s in stages],
                    'final_bodies_materialized': [s['optimizer']['final_loaded'] for s in stages],
                    'checkpoint_records_decoded': [s['optimizer']['restores']['checkpoints'] for s in stages],
                    'fusion_checkpoints_restored': [s['optimizer']['restores'].get('fusions', 0) for s in stages],
                    'fresh_optimizer_functions': [s['optimizer']['fresh_work'] for s in stages],
                    'llvm_keys_built': [s['emission']['work']['keys_built'] for s in stages],
                    'native_units_compiled': [r['cache']['compiled'] for r in rows],
                    'fallbacks': [s['lowering']['fallbacks'] for s in stages],
                    'stage_median_s': {
                        name: median(s['nanoseconds'][name] / 1e9 for s in stages)
                        for name in ('frontend', 'lowering', 'optimizer', 'emission', 'native', 'linker')},
                    'execution_checks_passed': all(r.get('execution_check', '').startswith('passed:') for r in rows),
                }
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('results', type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(args.results), indent=2))
