#!/usr/bin/env python3
"""Read-only synthesis of a completed parity report; outputs belong to this worker."""
import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import sys
import tempfile

MANAGED = ('allocs', 'reallocs', 'cumulative_allocated_bytes', 'peak_live_bytes',
           'live_bytes_at_exit', 'runtime_retains', 'runtime_releases',
           'compiler_retains', 'compiler_releases', 'list_copy_bytes',
           'dict_copy_bytes', 'buffer_copy_bytes', 'text_copy_bytes',
           'realloc_moves', 'realloc_moved_bytes')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def managed(report):
    groups = {}
    cases = {}
    for name, cell in sorted(report['cells'].items()):
        arms = (cell.get('counters') or {}).get('arms', {})
        cases[name] = {}
        for arm, value in arms.items():
            status = value.get('status', {})
            status = status.get('status') if isinstance(status, dict) else status
            totals = (value.get('counters') or {}).get('totals', {})
            metrics = {**totals, **(value.get('metrics') or {})} if status == 'ok' else {}
            cases[name][arm] = {'status': status, 'metrics': {k: metrics.get(k) for k in MANAGED},
                                'raw_totals': totals, 'counter_path': value.get('counter_path')}
    for group in ('eda', 'tree', 'vm', 'all'):
        subset = {n: v for n, v in cases.items() if group == 'all' or n.startswith(group + '-')}
        result = {'case_denominator': len(subset), 'metrics': {}}
        for label, arm in [('candidate', 'mylang-zero-rc'), ('before', 'mylang-before')]:
            result[label + '_counted'] = sum(v.get(arm, {}).get('status') == 'ok' for v in subset.values())
            result[label + '_incomplete'] = [n for n, v in subset.items() if v.get(arm, {}).get('status') != 'ok']
        for metric in MANAGED:
            positive, zero, unmatched = [], [], []
            for name, values in subset.items():
                new = values.get('mylang-zero-rc', {}).get('metrics', {}).get(metric)
                old = values.get('mylang-before', {}).get('metrics', {}).get(metric)
                if new is None or old is None:
                    unmatched.append(name)
                elif new > 0 and old > 0:
                    positive.append(new / old)
                else:
                    zero.append({'case': name, 'candidate': new, 'before': old})
            result['metrics'][metric] = {'positive_matched_pairs': len(positive),
                'geometric_mean_ratio': math.exp(sum(map(math.log, positive)) / len(positive)) if positive else None,
                'zero_pairs': zero, 'unmatched': unmatched}
        groups[group] = result
    return {'groups': groups, 'cases': cases,
            'method': 'C1 managed-summary positive-pair geometric ratios; zeros and unmatched observations remain explicit. Instrumented managed peak differs from process RSS. Allocator movement observations remain raw; no suppression.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--attempt', default='runtime-003')
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--manifest', type=Path, action='append', default=[])
    p.add_argument('--compilation-receipt', type=Path, action='append', default=[])
    a = p.parse_args()
    worker = Path(__file__).resolve().parents[3]
    output = a.output.resolve()
    assert output.is_relative_to(worker) and not output.is_relative_to(a.root.resolve()), 'worker-only output required'
    assert not output.exists()
    attempt = a.root.resolve() / 'experiments/lox-eda-parity-20261013/attempts' / a.attempt
    report_path = attempt / 'parity-report.json'
    summarize = a.root.resolve() / 'experiments/lox-eda-parity-20261013/summarize.py'
    pins = {}
    snapshots = {}

    def read(path):
        path = path.resolve()
        raw = path.read_bytes()
        h = hashlib.sha256(raw).hexdigest()
        assert str(path) not in pins or pins[str(path)] == h, 'input changed during synthesis'
        pins[str(path)] = h
        return raw

    read(Path(__file__))
    read(summarize)
    report = json.loads(read(report_path))
    assert report['scope'] == 60 and len(report['cells']) == 60
    assert {g: sum(n.startswith(g + '-') for n in report['cells']) for g in ('tree', 'vm', 'eda')} == {'tree': 13, 'vm': 13, 'eda': 34}
    for path in [attempt / 'configuration.json', attempt / 'pins.json', *a.manifest]:
        snapshots[str(path.resolve())] = read(path).decode()
    for cell in report['cells'].values():
        counters = cell.get('counters') or {}
        if counters.get('qualification_receipt'):
            read(Path(counters['qualification_receipt']))
        for value in counters.get('arms', {}).values():
            if value.get('counter_path'):
                raw = json.loads(read(Path(value['counter_path'])))
                if value.get('counters') is not None:
                    assert raw == value['counters'], 'embedded counted observation differs from raw file'
    compilation = [{'path': str(path.resolve()), 'receipt': json.loads(read(path))} for path in a.compilation_receipt]
    module_spec = importlib.util.spec_from_file_location('frozen_summarize', summarize)
    module = importlib.util.module_from_spec(module_spec)
    old_bytecode = sys.dont_write_bytecode
    try:
        sys.dont_write_bytecode = True
        module_spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = old_bytecode
    rows, groups = module.render(report)
    result = {'report_path': str(report_path), 'all_cases_pass': report['all_cases_pass'],
              'runtime_and_rss': {'groups': groups, 'cases': rows}, 'managed': managed(report),
              'compilation_observations': compilation,
              'compilation_note': 'Exact supplied receipts only; unavailable observations remain absent. No runtime attribution follows from compile cost.',
              'method': 'Reuse pinned root summarize.render unchanged; retain all60 cases, censors/statuses and matched-pair denominators. Never infer ratios for incomplete arms.'}
    assert all(digest(path) == h for path, h in pins.items()), 'input changed before publication'
    output.parent.mkdir(parents=True, exist_ok=True)
    private = Path(tempfile.mkdtemp(prefix=output.name + '.pending-', dir=output.parent))
    try:
        (private / 'synthesis.json').write_text(json.dumps(result, indent=2) + '\n')
        (private / 'initial-manifest-snapshots.json').write_text(json.dumps(snapshots, indent=2) + '\n')
        receipt = {'status': 'complete', 'inputs': pins,
                   'outputs': {p.name: digest(p) for p in private.iterdir() if p.is_file()}}
        (private / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        assert all(digest(path) == h for path, h in pins.items()), 'input changed at publication'
        (private / 'COMPLETE').write_text('validated\n')
        assert not output.exists()
        os.rename(private, output)
    except BaseException:
        shutil.rmtree(private, ignore_errors=True)
        raise
    print('Validated synthesis published to', output)


if __name__ == '__main__':
    main()
