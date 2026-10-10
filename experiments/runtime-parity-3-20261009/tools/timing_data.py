#!/usr/bin/env python3
"""Read complete timing receipts without silently dropping failed or missing cells."""
import gzip
import importlib.util
import hashlib
import json
import math
from pathlib import Path
import statistics
from functools import cache


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


@cache
def row_runner():
    """Read the unchanged 46-row registry and strict receipt parsers, without running it."""
    root = Path(__file__).resolve().parents[3]
    source = root / 'experiments/new-core-s4-20261006/integration/measure_all46.py'
    spec = importlib.util.spec_from_file_location('rp3_timing_row_registry', source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.rows


def row_samples(runner, arm, size, iterations, start_checksum, work_checksum):
    for field, count, repeat, checksum in [('startup', 3, 1, start_checksum),
                                           ('runs', 7, iterations, work_checksum)]:
        assert len(arm[field]) == count
        for run in arm[field]:
            assert run['status'] == 0 and positive(run['cycles'])
            assert run['checksum'] == checksum
            assert run['command'][:8] == ['taskset', '-c', '10', 'perf', 'stat', '-x,', '-e', runner.EVENT]
            assert run['command'][-3:] == [size, str(repeat), str(runner.SEED)]
            assert runner.parse_stdout(run['stdout']) == (run['checksum'], run['elapsed_ns'])
            assert runner.parse_perf(run['stderr']) == run['cycles']


def row_ratios(batches):
    runner = row_runner()
    assert len(batches) == 3
    assert all(batch['valid'] and batch['rounds'] == 7 and batch['cpu'] == 10 for batch in batches)
    assert len(runner.UNITS) == 46
    assert all(set(batch['rows']) == set(runner.UNITS) for batch in batches)
    names = {'zig-safe': 'Zig ReleaseSafe', 'zig-fast': 'Zig ReleaseFast', 'rust': 'Rust', 'go': 'Go'}
    result = {}
    for name in sorted(batches[0]['rows']):
        suite, unit, big, small = runner.UNITS[name]
        assert all(batch['rows'][name]['suite'] == suite and batch['rows'][name]['unit'] == unit
                   and batch['rows'][name]['reference_name'] == runner.REFERENCE_NAMES.get(name, name) for batch in batches)
        assert all(set(batch['rows'][name]['sizes']) == {'64', '4096'} for batch in batches)
        for size in ('4096', '64'):
            cells = [batch['rows'][name]['sizes'][size] for batch in batches]
            iterations = big if size == '4096' else small
            assert all(cell['iterations'] == iterations for cell in cells), (name, size)
            work_checksum = cells[0]['checksum']
            assert all(cell['checksum'] == work_checksum for cell in cells), (name, size)
            configs = [cell['configurations'] for cell in cells]
            assert all(set(config) == set(configs[0]) for config in configs)
            expected = {'old core --release', 'new core release', 'Rust', 'Zig ReleaseSafe', 'Go'}
            if name not in {'tree_build_walk', 'record_pass', 'grid_dp', 'union_find', 'float_format', 'buffer_write'}:
                expected.add('Zig ReleaseFast')
            assert set(configs[0]) == expected, (name, size)
            start_checksum = configs[0]['old core --release']['startup'][0]['checksum']
            per = int(size) * iterations if unit == 'element' else iterations
            for config in configs:
                for label, arm in config.items():
                    row_samples(runner, arm, size, iterations, start_checksum, work_checksum)
                    normalized = (statistics.median(run['cycles'] for run in arm['runs']) -
                                  statistics.median(run['cycles'] for run in arm['startup'])) / per
                    assert positive(normalized) and positive(arm['cycles_per_unit']), (name, size, label)
                    assert math.isclose(arm['cycles_per_unit'], normalized, rel_tol=1e-12, abs_tol=1e-12), (name, size, label)
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
