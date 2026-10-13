#!/usr/bin/env python3
"""Count eligible application arms separately; this coordinator owns admission."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from receipts import build_path, validate_build
from input_recovery import relocated_spec

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PREVIOUS = ROOT / 'experiments/lox-eda-rerun-20261012'
OLD = ROOT / 'experiments/lox-eda-zero-rc-20261012/bench'
CHECKED = ('mylang-zero-rc', 'mylang-before')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--group', choices=('eda', 'tree', 'vm'), required=True)
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    assert os.environ.get('MYLANG_SLOT_DIR')
    app = 'eda' if args.group == 'eda' else 'lox'
    build = validate_build(build_path(app))
    before = json.loads((PREVIOUS / 'build' / ('eda-2' if app == 'eda' else 'lox') / 'build-receipt.json').read_text())
    entries = {'mylang-' + name: build['binaries'][name + '-counted']
               for name in ('original-rc', 'migrated-rc', 'zero-rc')}
    entries['mylang-before'] = before['binaries']['zero-rc-counted']
    for entry in entries.values():
        assert sha(entry['path']) == entry['sha256']
    output = HERE / 'counted'
    output.mkdir(exist_ok=True)
    specs = sorted((HERE / 'specs').glob(args.group + '-*.json'))
    assert len(specs) == (34 if app == 'eda' else 13)
    for spec in specs:
        suffix = '.r0-9.w2.rss3.json' if app == 'eda' else '.r9-9.w0.rss3.json'
        runtime = HERE / 'runtime' / (spec.stem + suffix)
        statuses = json.loads(runtime.read_text())['arm_status']
        included = [name for name in entries if statuses[name]['status'] == 'ok']
        summary = output / (spec.stem + '.counted.spec.summary.json')
        if summary.exists():
            assert args.resume
        elif included:
            command = [str(ROOT / 'scripts/build-slot.sh'), 'timing', sys.executable,
                       '-B', str(OLD / 'run-counted.py'), '--output', str(output),
                       '--cpu', '8', '--guest-timeout', '120']
            for name in included:
                command += ['--arm', name + '=' + entries[name]['path']]
            command.append(str(relocated_spec(spec)))
            print('counting', spec.stem, flush=True)
            with (output / (spec.stem + '.log')).open('w') as log:
                subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        else:
            summary.write_text(json.dumps({'cell': json.loads(spec.read_text())['cell'],
                'arms': {}, 'executed': False, 'qualification_receipt': None,
                'reason': 'Every instrumented arm was skipped after runtime failure.'}, indent=2) + '\n')
        raw = json.loads(summary.read_text())
        assert set(raw['arms']) == set(included)
        coverage = {**raw, 'arms': dict(raw['arms']), 'raw_summary': str(summary),
                    'raw_summary_sha256': sha(summary), 'runtime_receipt': str(runtime),
                    'runtime_receipt_sha256': sha(runtime)}
        for name in entries:
            if name not in included:
                coverage['arms'][name] = {'status': {'status': 'skipped_runtime_failure',
                    'runtime_status': statuses[name]}, 'metrics': None, 'executed': False}
        for name, row in raw['arms'].items():
            if row['metrics'] is None:
                continue
            assert row['metrics']['live_bytes_at_exit'] == 0, (spec, name)
            assert sha(entries[name]['path']) == entries[name]['sha256']
            if name in CHECKED:
                totals, kinds = row['counters']['totals'], row['counters']['kinds']
                assert all(totals[k] == 0 for k in (
                    'runtime_retains', 'runtime_releases', 'shared_retains', 'shared_releases', 'share_marks', 'share_bytes'))
                assert all(kinds[k]['count'] == 0 for k in ('retain', 'release', 'unique_test'))
        dest = output / (spec.stem + '.coverage.json')
        encoded = json.dumps(coverage, indent=2) + '\n'
        if dest.exists():
            assert args.resume and dest.read_text() == encoded
        else:
            dest.write_text(encoded)
        print('counted', raw['cell'], {n: r['status']['status'] for n, r in coverage['arms'].items()}, flush=True)


if __name__ == '__main__':
    main()
