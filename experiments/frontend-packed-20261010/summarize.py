#!/usr/bin/env python3
"""Add frontend reuse and physical cache IO to the paired build summary."""
import argparse
import gzip
import importlib.util
import json
from pathlib import Path
from statistics import median


def summarize(path):
    previous = Path(__file__).parents[1] / 'checkpoint-reuse-20261009/summarize.py'
    spec = importlib.util.spec_from_file_location('checkpoint_summary', previous)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    result = module.summarize(path)
    text = gzip.decompress(path.read_bytes()).decode() if path.suffix == '.gz' else path.read_text()
    report = json.loads(text)
    for key, summary in result.items():
        size, variant, phase = key.split('/')
        rows = [r for r in report['records']
                if (str(r['copies']), r['variant'], r['phase']) == (size, variant, phase)]
        summary['frontend_counts'] = {
            name: [r['cache']['stages']['frontend'][name] for r in rows]
            for name in ('checked', 'reused', 'summaries', 'stored')}
        summary['frontend_misses'] = [r['cache']['stages']['frontend_misses'] for r in rows]
        storage = [r['cache'].get('storage') for r in rows]
        if all(storage):
            summary['cache_flush_median_s'] = median(s['flush_nanoseconds'] / 1e9 for s in storage)
            summary['cache_flush_succeeded'] = all(s['flush_succeeded'] for s in storage)
            summary['packed_reads'] = {name: [s['reads'][name] for s in storage]
                                       for name in storage[0]['reads']}
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('results', type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(args.results), indent=2))
