#!/usr/bin/env python3
"""Mandatory filesystem, ordinary-sequence and generic reply admission."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent / 'tests'))
import run_body_check_qualification as D
import run_body_filesystem_admission as F
import run_body_sequence_admission as S
import run_body_sequence_hostile as H
import run_body_generic_hostile as G
import run_body_library_join as J


def expected(name):
    module = F if name == 'filesystem' else S
    manifest, _ = module.selection()
    rows = set()
    for source, spec in manifest.items():
        phases = ['check'] if name == 'filesystem' else ['syntax', 'check']
        if spec['status'] == 0:
            phases.append('typed')
            if name == 'sequence':
                phases.append('runtime')
            elif spec['runtime']:
                phases += ['runtime-normal', 'runtime-release']
        rows.update((source, mode, phase) for mode in module.MODES for phase in phases)
    return manifest, rows


def require_source(name, report, release=False):
    manifest, required = expected(name)
    D.F.require(report.get('complete') is True and report.get('selected_admission') == 'passed'
                and report.get('body_schema') == D.SCHEMA
                and report.get('failed') == report.get('skipped') == 0,
                name + ' admission incomplete')
    records = report.get('records', [])
    actual = [(row['name'], row['mode'], row['phase']) for row in records]
    D.F.require(len(actual) == len(set(actual)) == len(required) and set(actual) == required
                and report.get('operations') == report.get('expected_operations') == len(required),
                name + ' missing, duplicate or unexpected source work')
    if name == 'sequence':
        D.F.require(report.get('checks_only') is False
                    and report.get('lane') == ('release' if release else 'normal'),
                    'sequence runtime selection differs')
    for row in records:
        D.F.require(row.get('source_sha256') == manifest[row['name']]['source_sha256'],
                    name + ' source identity differs')
        if row['phase'].startswith('runtime'):
            optimized = row['phase'] == 'runtime-release' if name == 'filesystem' else release
            command = row.get('command', [])
            D.F.require(bool(command) and ('--release' in command) is optimized
                        and ('--verify-facts' in command) is optimized,
                        name + ' actual runtime flags differ')


def require_hostile(report, module, count_field):
    D.F.require(report.get('complete') is True and report.get('schema') == D.SCHEMA
                and report.get('failed') == report.get('skipped') == 0
                and report.get(count_field) == len(module.NAMES), 'hostile admission incomplete')
    records = report.get('records', [])
    D.F.require([row['name'] for row in records] == list(module.NAMES), 'hostile inventory differs')
    for row in records:
        J.require_rejection((row['status'], bytes.fromhex(row['stdout_hex']), bytes.fromhex(row['stderr_hex'])))


def require_filesystem_hostile(report):
    captures = report.get('hostile_captures', [])
    D.F.require(report.get('hostile_complete') is True and report.get('hostile_expected') == F.H.EXPECTED
                and [c['name'] for c in captures] == list(F.H.SOURCES), 'filesystem captures incomplete')
    required = set()
    for capture in captures:
        names = capture['mutations']
        D.F.require(len(names) == len(set(names)) == F.H.COUNTS[capture['name']],
                    'filesystem mutation inventory differs')
        required.update((capture['name'], name, mode) for name in ['authentic', *names] for mode in F.H.MODES)
    rows = report.get('hostile_records', [])
    actual = [(r['capture'], r['name'], r['mode']) for r in rows]
    D.F.require(len(actual) == len(set(actual)) == 478 and set(actual) == required,
                'filesystem hostile work incomplete')
    for row in rows:
        result = (row['status'], bytes.fromhex(row['stdout_hex']), bytes.fromhex(row['stderr_hex']))
        if row['name'] == 'authentic':
            D.F.require(result == (0, b'', b''), 'filesystem authentic replay differs')
        else:
            J.require_rejection(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'builder', 'component-dir', 'zig', 'source-root', 'report-dir'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    for name in vars(args):
        setattr(args, name, getattr(args, name).resolve())
    args.report_dir.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='fresh-', dir=args.report_dir))
    before = {'compiler_sha256': D.F.digest(args.compiler), 'packages': D.packages(args.component_dir)}
    common = ['--compiler', args.compiler, '--component-dir', args.component_dir, '--zig', args.zig]
    for name, module, release in [('filesystem', F, False), ('sequence', S, False), ('sequence', S, True)]:
        report_path = work / (name + ('-release' if release else '-normal') + '.json')
        command = [sys.executable, Path(module.__file__).resolve(), *common, '--builder', args.builder,
                   '--source-root', args.source_root, '--report', report_path]
        if release:
            command.append('--release')
        subprocess.run(list(map(str, command)), check=True)
        report = json.loads(report_path.read_text())
        require_source(name, report, release)
        D.F.require({k: report.get(k) for k in before} == before, name + ' deployment differs')
        if name == 'filesystem':
            require_filesystem_hostile(report)
    for name, module, count_field in [('sequence', H, 'operations'), ('generic', G, 'hostile')]:
        report_path = work / (name + '-hostile.json')
        subprocess.run(list(map(str, [sys.executable, Path(module.__file__).resolve(), *common,
            '--report', report_path, '--evidence-dir', work / (name + '-hostile')])), check=True)
        report = json.loads(report_path.read_text())
        require_hostile(report, module, count_field)
        identity = report['identity'] if name == 'sequence' else {
            'compiler_sha256': report['capture']['identity']['host'],
            'packages': report['capture']['identity']['packages']}
        D.F.require(identity == before, name + ' hostile deployment differs')
    D.F.require(before == {'compiler_sha256': D.F.digest(args.compiler),
                           'packages': D.packages(args.component_dir)}, 'operations deployment changed')
    print('body operations: 3048 source operations, 489 malformed replies and 8 authentic replays; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
