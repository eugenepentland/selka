#!/usr/bin/env python3
"""Summarize paired raw/zlib timings, one-build capacity and actual work."""
import argparse
import gzip
import json
from pathlib import Path
from statistics import median


def summarize(path):
    encoded = path.read_bytes()
    report = json.loads(gzip.decompress(encoded) if path.suffix == '.gz' else encoded)
    assert 'completed_utc' in report
    assert report['cache_compression'] == {'baseline': 'zlib', 'candidate': 'none'}
    assert report['compilers']['baseline'] == report['compilers']['candidate']
    result = {'compiler': report['compilers']['baseline'], 'timings': [],
              'one_build_cache': [], 'validation': {}}
    records = report['records']
    paired = 0
    identical = 0
    for row in records:
        assert row['execution_check']
        assert row['cache']['storage']['flush_succeeded']
        assert row['cache']['storage']['compression'] == report['cache_compression'][row['variant']]
        if row['variant'] != 'baseline':
            continue
        mate, = [r for r in records if r['variant'] == 'candidate' and
                 (r['copies'], r['phase'], r['sample']) == (row['copies'], row['phase'], row['sample'])]
        # Timings and physical block I/O may differ; semantic work must not.
        for key in ('units', 'reused', 'compiled', 'verified', 'processes'):
            assert row['cache'][key] == mate['cache'][key], (key, row['phase'])
        for key in ('frontend', 'lowering', 'optimizer', 'emission', 'frontend_misses'):
            assert row['cache']['stages'][key] == mate['cache']['stages'][key], (key, row['phase'])
        paired += 1
        identical += int(row['paired_binary_identical'])
    for copies, size in report['sizes'].items():
        setup = {r['variant']: r['setup_disk'] for r in records
                 if str(r['copies']) == copies and r['phase'] == 'setup'}
        result['one_build_cache'].append({
            'lines': size['physical_lines'], 'zlib': setup['baseline'], 'none': setup['candidate'],
            'compression_allocated_saving_percent': 100 * (1 - setup['baseline']['total']['allocated_bytes'] /
                                                          setup['candidate']['total']['allocated_bytes'])})
        for phase in ('entry_edit', 'helper_edit', 'three_file_edit'):
            policies = {}
            for variant, policy in report['cache_compression'].items():
                rows = [r for r in records if (str(r['copies']), r['variant'], r['phase']) == (copies, variant, phase)]
                summary = dict(report['summary'][f'{copies}/{variant}'][phase])
                stages = rows[0]['cache']['stages']
                summary['counts'] = {k: stages[k] for k in ('frontend', 'lowering', 'optimizer', 'emission')}
                summary['native_compiled'] = rows[0]['cache']['compiled']
                summary['median_storage_reads'] = {k: median(r['cache']['storage']['reads'][k] for r in rows)
                                                   for k in rows[0]['cache']['storage']['reads']}
                summary['median_flush_s'] = median(r['cache']['storage']['flush_nanoseconds'] / 1e9 for r in rows)
                policies[policy] = summary
            result['timings'].append({'lines': size['physical_lines'], 'phase': phase, **policies,
                                      'none_time_change_percent': 100 * (policies['none']['median_s'] /
                                                                         policies['zlib']['median_s'] - 1)})
    result['validation'] = {'builds': len(records), 'paired_comparisons': paired,
                            'identical_work_counts': True, 'byte_identical_binary_pairs': identical,
                            'golden_and_leak_checks': len(records), 'flush_succeeded': True,
                            'native_and_executable_audits': 'Passed by benchmark harness before completion'}
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('results', type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(args.results), indent=2))
