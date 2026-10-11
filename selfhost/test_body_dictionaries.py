#!/usr/bin/env python3
"""Mandatory schema11 normal/release source and authentic hostile admission."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent / 'tests'))
import run_body_dictionary_admission as A
import run_body_dictionary_hostile as H


def require_complete(source, hostile):
    A.F.require(source.get('complete') is True and source.get('selected_admission') == 'passed',
                'B8 source admission incomplete')
    A.F.require(source.get('body_schema') == A.SCHEMA and source.get('modes') == list(A.MODES),
                'B8 wrong schema or modes')
    A.F.require(source.get('operations') == source.get('expected_operations') == 246,
                'B8 incomplete source operations')
    manifest, _ = A.selection()
    expected = {(name, mode, phase) for name, spec in manifest.items() for mode in A.MODES
                for phase in (('check', 'typed', 'runtime') if spec['status'] == 0 else ('check',))}
    actual = [(r['name'], r['mode'], r['phase']) for r in source.get('records', [])]
    A.F.require(len(actual) == len(set(actual)) == 246 and set(actual) == expected,
                'B8 absent or duplicate source work')
    A.F.require(hostile.get('complete') is True and hostile.get('selected_admission') == 'passed'
                and hostile.get('schema') == H.SCHEMA and hostile.get('hostile') == 27,
                'B8 hostile admission incomplete')
    records = hostile.get('records', [])
    A.F.require([r['name'] for r in records] == list(H.NAMES), 'B8 absent or duplicate hostile work')
    for row in records:
        H.J.require_rejection((row['status'], bytes.fromhex(row['stdout_hex']), bytes.fromhex(row['stderr_hex'])))
    for report in (source, hostile):
        A.F.require(report.get('failed') == report.get('skipped') == 0, 'B8 failed or skipped work')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'builder', 'component-dir', 'zig', 'source-root', 'report-dir'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    for name in vars(args):
        setattr(args, name, getattr(args, name).resolve())
    args.report_dir.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='fresh-', dir=args.report_dir))
    for release in (False, True):
        label = 'release' if release else 'normal'
        source = args.report_dir / (label + '.json')
        hostile = args.report_dir / (label + '-hostile.json')
        command = [sys.executable, str(Path(A.__file__).resolve()), '--compiler', str(args.compiler),
                   '--builder', str(args.builder), '--component-dir', str(args.component_dir),
                   '--zig', str(args.zig), '--source-root', str(args.source_root), '--report', str(source)]
        if release:
            command.append('--release')
        subprocess.run(command, check=True)
        subprocess.run([sys.executable, str(Path(H.__file__).resolve()), '--compiler', str(args.compiler),
                        '--component-dir', str(args.component_dir), '--zig', str(args.zig),
                        '--report', str(hostile), '--evidence-dir', str(work / label)], check=True)
        require_complete(json.loads(source.read_text()), json.loads(hostile.read_text()))
    print('B8 gate: normal and release each 246 workflows/27 hostile refusals; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
