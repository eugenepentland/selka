#!/usr/bin/env python3
"""Audit every existing row against the exact application foundation compiler."""
import argparse
import difflib
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
SPEC = importlib.util.spec_from_file_location('rows', ROOT / 'experiments/new-core-s3-20261006/wave-c/s3-a/measure_all40.py')
ROWS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ROWS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--area', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    for path in (args.area, args.evidence):
        if not path.resolve().is_relative_to(ROOT) or path.exists():
            raise RuntimeError(f'use a fresh private path: {path}')
        path.mkdir(parents=True)
    report = dict(before_sha256=hashlib.sha256(args.before.read_bytes()).hexdigest(),
                  after_sha256=hashlib.sha256(args.after.read_bytes()).hexdigest(), rows={})
    for row in ROWS.UNITS:
        if row in ROWS.APPLICATIONS:
            continue
        stem = ROWS.stem(row)
        definitions = {}
        for name, compiler in (('before', args.before), ('after', args.after)):
            llvm = args.area / f'{stem}-{name}.ll'
            command = list(map(str, [compiler, 'build', ROOT / f'test/core/{stem}.my', '-o', args.area / f'{stem}-{name}',
                        '--release', '--emit-llvm', llvm, '--cache-dir', args.area / f'cache-{name}',
                        '--link', ROOT / 'benchmarks/runtime/ports/native_clock.c']))
            done = subprocess.run(command, capture_output=True, text=True)
            (args.evidence / f'{row}-{name}.json').write_text(json.dumps(dict(command=command, status=done.returncode,
                                                           stdout=done.stdout, stderr=done.stderr), indent=2) + '\n')
            if done.returncode or not llvm.exists():
                raise RuntimeError(f'{row}/{name}: status={done.returncode} {done.stdout}{done.stderr}')
            definitions[name] = '\n'.join(re.findall(r'^define .*?^\}', llvm.read_text(), re.M | re.S))
        same = definitions['before'] == definitions['after']
        if not same:
            (args.evidence / f'{row}.diff').write_text(''.join(difflib.unified_diff(
                definitions['before'].splitlines(True), definitions['after'].splitlines(True), fromfile='ac81831bd', tofile='byte-index-inline')))
        report['rows'][row] = dict(identical=same)
        print(f'{row}: {"identical" if same else "changed"}', flush=True)
    report['changed'] = [row for row, value in report['rows'].items() if not value['identical']]
    print(f"35 definitions; changed={report['changed']}", flush=True)
    (args.evidence / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
