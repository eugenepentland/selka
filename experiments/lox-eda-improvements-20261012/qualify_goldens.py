#!/usr/bin/env python3
"""Check all 34 EDA golden trees independently of runtime benchmark admission."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess

from receipts import sha, validate_build

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OLD = ROOT / 'experiments/lox-eda-zero-rc-20261012/bench'


def tree(path):
    path = Path(path)
    return {str(p.relative_to(path)): sha(p) for p in sorted(path.rglob('*')) if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('work', type=Path)
    args = parser.parse_args()
    build = validate_build(args.manifest)
    assert build['application'] == 'eda'
    specs = sorted((OLD / 'frozen-specs').glob('eda-*.json'))
    assert len(specs) == 34
    previous = json.loads((OLD / 'full-final/full-runtime-summary.json').read_text())
    assert not args.output.exists() and not args.work.exists()
    args.work.mkdir(parents=True)
    rows, inputs = [], {}
    for path in specs:
        spec = json.loads(path.read_text())
        files = set(spec['files'])
        for folder in spec.get('identity_dirs', []):
            files.update(str(p) for p in Path(folder).rglob('*') if p.is_file())
        for name in files:
            identity = sha(name)
            assert previous['cells'][spec['cell']]['identities'][name] == identity
            inputs[name] = identity
        expected = tree(spec['golden_dir'])
        assert expected
        out_dir = args.work / spec['cell'].replace('/', '-')
        oracle_stdout = None
        for arm in ('original-rc', 'migrated-rc', 'zero-rc'):
            shutil.rmtree(out_dir, ignore_errors=True)
            command = [build['binaries'][arm]['path'],
                       *[part.replace(spec['out_dir'], str(out_dir)) for part in spec['arms']['zig-safe'][1:]]]
            process = subprocess.Popen(command, cwd=spec.get('cwd'), stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, start_new_session=True)
            status = 'ok'
            try:
                stdout, stderr = process.communicate(timeout=120)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                stdout, stderr = process.communicate()
                status = 'correctness_timeout'
            if status == 'ok' and process.returncode != 0:
                status = 'failed'
            actual = tree(out_dir)
            if status == 'ok' and actual != expected:
                status = 'golden_mismatch'
            stdout_hash = hashlib.sha256(stdout).hexdigest()
            if oracle_stdout is None and status == 'ok':
                oracle_stdout = stdout_hash
            if status == 'ok' and stdout_hash != oracle_stdout:
                status = 'stdout_mismatch'
            rows.append({'cell': spec['cell'], 'arm': arm, 'command': command, 'status': status,
                         'returncode': process.returncode, 'stdout_sha256': stdout_hash,
                         'stderr': stderr.decode(errors='replace'), 'expected': expected, 'actual': actual})
            args.output.write_text(json.dumps({'rows': rows, 'input_identities': inputs,
                'absolute_correctness_timeout_seconds': 120,
                'note': 'Correctness only; no wall-time samples or benchmark ratios.'}, indent=2) + '\n')
        shutil.rmtree(out_dir, ignore_errors=True)
    for name, identity in inputs.items():
        assert sha(name) == identity
    validate_build(args.manifest)
    assert len(rows) == 102
    assert all(row['status'] == 'ok' for row in rows), 'EDA golden failures are retained in the receipt'
    print(json.dumps({'cells': 34, 'arms': 3, 'passed': len(rows), 'failed': 0}))


if __name__ == '__main__':
    main()
