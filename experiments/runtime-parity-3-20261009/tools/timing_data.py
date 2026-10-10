#!/usr/bin/env python3
"""Read complete timing receipts without silently dropping failed or missing cells."""
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics


def read(path):
    path = Path(path)
    if not path.exists() and path.suffix != '.gz':
        path = path.with_suffix(path.suffix + '.gz')
    with (gzip.open(path, 'rt') if path.suffix == '.gz' else path.open()) as stream:
        return json.load(stream)


def identity(path):
    path = Path(path)
    if not path.exists() and path.suffix != '.gz':
        path = path.with_suffix(path.suffix + '.gz')
    return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def gm(values):
    return math.exp(statistics.mean(math.log(value) for value in values))


def positive(value):
    return isinstance(value, (int, float)) and math.isfinite(value) and value > 0


def lox(data, paired):
    assert data['cpu'] == 10 and data['rounds'] == 3 and not data['failures']
    expected = {'mylang:release', 'zig:release', 'zig:release-safe', 'rust:release', 'go:release'}
    if paired:
        expected.add('mylang-base:release')
    assert len(data['summary']) == 26 and set(data['summary']) == set(data['samples'])
    assert len(data['loadavg_per_round']) == 4
    for name, arms in data['summary'].items():
        assert set(arms) == expected and set(data['samples'][name]) == expected, name
        for label, arm in arms.items():
            samples = data['samples'][name][label]
            assert len(samples) == 3 and all(positive(sample['wall']) for sample in samples), (name, label)
            assert statistics.median(sample['wall'] for sample in samples) == arm['median_s'], (name, label)
    return data['summary']


def eda(data, paired):
    assert data['cpu'] == 10 and data['rounds'] == 10 and data['warmup_rounds'] == 1
    assert data['all_outputs_verified'] and len(data['per_case']) == 34
    expected = {'mylang-base', 'zig-safe', 'zig-fast', 'rust', 'go'}
    if paired:
        expected.add('mylang-final')
    assert set(data['binaries']) == expected
    assert set(data['load_avg']) == {'before', 'after'}
    for name, arms in data['per_case'].items():
        assert set(arms) == expected, name
        for label, arm in arms.items():
            assert len(arm['samples_s']) == 10 and all(map(positive, arm['samples_s'])), (name, label)
            # The native EDA writer rounds both samples and medians to microseconds.
            assert abs(statistics.median(arm['samples_s']) - arm['median_s']) <= 1.000001e-6, (name, label)
    return data['per_case']


def row_ratios(batches):
    assert len(batches) == 3
    assert all(batch['valid'] and batch['rounds'] == 7 and batch['cpu'] == 10 for batch in batches)
    assert all(len(batch['rows']) == 46 and set(batch['rows']) == set(batches[0]['rows']) for batch in batches)
    names = {'zig-safe': 'Zig ReleaseSafe', 'zig-fast': 'Zig ReleaseFast', 'rust': 'Rust', 'go': 'Go'}
    result = {}
    for name in sorted(batches[0]['rows']):
        assert all(set(batch['rows'][name]['sizes']) == {'64', '4096'} for batch in batches)
        for size in ('4096', '64'):
            cells = [batch['rows'][name]['sizes'][size] for batch in batches]
            configs = [cell['configurations'] for cell in cells]
            assert all(set(config) == set(configs[0]) for config in configs)
            expected = {'old core --release', 'new core release', 'Rust', 'Zig ReleaseSafe', 'Go'}
            if name not in {'tree_build_walk', 'record_pass', 'grid_dp', 'union_find', 'float_format', 'buffer_write'}:
                expected.add('Zig ReleaseFast')
            assert set(configs[0]) == expected, (name, size)
            for cell, config in zip(cells, configs):
                for label, arm in config.items():
                    assert positive(arm['cycles_per_unit']) and len(arm['runs']) == 7 and len(arm['startup']) == 3
                    assert all(run['status'] == 0 and positive(run['cycles']) and run['checksum'] == cell['checksum']
                               for run in arm['runs']), (name, size, label)
                    assert all(run['status'] == 0 and positive(run['cycles']) for run in arm['startup'])
            ratios = {}
            for own, label in [('base', 'old core --release'), ('final', 'new core release')]:
                ratios[own] = {short: statistics.median(config[label]['cycles_per_unit'] / config[ref]['cycles_per_unit']
                                                       for config in configs)
                               for short, ref in names.items() if ref in configs[0]}
            paired = [config['new core release']['cycles_per_unit'] / config['old core --release']['cycles_per_unit']
                      for config in configs]
            result[name + '/' + size] = {**ratios, 'final_over_base': statistics.median(paired), 'batch_ratios': paired}
    assert len(result) == 92
    return result
