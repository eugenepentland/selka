#!/usr/bin/env python3
"""Measure full-size allocation counters separately, with one lease per case."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OLD = ROOT / 'experiments/lox-eda-zero-rc-20261012/bench'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--group', choices=('eda', 'tree', 'vm'), required=True)
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    app = 'eda' if args.group == 'eda' else 'lox'
    path = HERE / ('build/eda-2/build-receipt.json' if app == 'eda' else 'build/lox/build-receipt.json')
    manifest = json.loads(path.read_text())
    binaries = {}
    for arm in ('original-rc', 'migrated-rc', 'zero-rc'):
        binary = manifest['binaries'][arm + '-counted']
        assert hashlib.sha256(Path(binary['path']).read_bytes()).hexdigest() == binary['sha256']
        binaries['mylang-' + arm] = binary['path']
    output = HERE / 'counted'
    output.mkdir(exist_ok=True)
    specs = sorted((HERE / 'specs').glob(args.group + '-*.json'))
    assert len(specs) == (34 if app == 'eda' else 13)
    for spec in specs:
        suffix = '.r0-9.w2.rss3.json' if app == 'eda' else '.r9-9.w0.rss3.json'
        runtime = HERE / 'runtime' / (spec.stem + suffix)
        runtime_data = json.loads(runtime.read_text())
        checked_status = runtime_data['arm_status']['mylang-zero-rc']
        skip_checked = checked_status['status'] != 'ok'
        arms = []
        for name, binary in binaries.items():
            if name != 'mylang-zero-rc' or not skip_checked:
                arms += ['--arm', name + '=' + binary]
        summary = output / (spec.stem + '.counted.spec.summary.json')
        if summary.exists():
            assert args.resume
        else:
            print('counting', spec.stem, flush=True)
            command = [str(ROOT / 'scripts/build-slot.sh'), 'timing', sys.executable, '-B', str(OLD / 'run-counted.py'),
                       '--output', str(output), '--cpu', '8', '--guest-timeout', '120', *arms, str(spec)]
            with (output / (spec.stem + '.log')).open('w') as log:
                subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        data = json.loads(summary.read_text())
        expected = {'mylang-original-rc', 'mylang-migrated-rc'}
        if not skip_checked:
            expected.add('mylang-zero-rc')
        assert set(data['arms']) == expected
        # Keep the underlying executed-arm receipt unchanged. The coverage record
        # explicitly represents unavailable metrics for an unexecuted arm.
        coverage = {**data, 'raw_summary': str(summary),
                    'raw_summary_sha256': hashlib.sha256(summary.read_bytes()).hexdigest(),
                    'runtime_receipt': str(runtime),
                    'runtime_receipt_sha256': hashlib.sha256(runtime.read_bytes()).hexdigest()}
        coverage['arms'] = dict(data['arms'])
        if skip_checked:
            coverage['arms']['mylang-zero-rc'] = {
                'status': {'status': 'skipped_runtime_failure', 'runtime_status': checked_status},
                'metrics': None, 'executed': False}
        coverage_path = output / (spec.stem + '.coverage.json')
        encoded = json.dumps(coverage, indent=2) + '\n'
        if coverage_path.exists():
            assert args.resume and coverage_path.read_text() == encoded
        else:
            coverage_path.write_text(encoded)
        for name, arm in data['arms'].items():
            if arm['metrics'] is None:
                continue
            assert arm['metrics']['live_bytes_at_exit'] == 0, (spec.stem, name, 'managed leak')
            if name == 'mylang-zero-rc':
                totals = arm['counters']['totals']
                kinds = arm['counters']['kinds']
                assert all(totals[k] == 0 for k in ('runtime_retains', 'runtime_releases', 'shared_retains', 'shared_releases', 'share_marks'))
                assert all(kinds[k]['count'] == 0 for k in ('retain', 'release', 'unique_test'))
        print('counted', data['cell'], {k: v['status']['status'] for k, v in coverage['arms'].items()}, flush=True)


if __name__ == '__main__':
    main()
