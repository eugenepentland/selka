#!/usr/bin/env python3
"""Mandatory body-language admission through installed producers."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent / 'tests'))
import run_body_check_qualification as D
import run_body_constant_admission as C
import run_body_structural_admission as S
import run_body_iteration_admission as I
import run_body_chained_admission as K
import run_body_comprehension_admission as P
import run_body_text_methods_admission as T
import run_body_generic_admission as G
import run_body_structural_hostile as H

LANES = {'constants': C, 'structural': S, 'iteration': I, 'chained': K,
         'comprehension': P, 'text': T, 'generic': G}


def expected(name):
    module = LANES[name]
    manifest = module.selection()
    if name != 'constants':
        manifest = manifest[0]
    rows = {(source, mode, phase) for source, spec in manifest.items() for mode in module.MODES
            for phase in ((['syntax'] if name == 'constants' else []) + ['check'] +
                          (['typed', 'runtime'] if spec['status'] == 0 else []))}
    return manifest, rows


def require_source(name, report, release):
    module = LANES[name]
    manifest, required = expected(name)
    D.F.require(report.get('complete') is True and report.get('selected_admission') == 'passed',
                name + ' admission incomplete')
    D.F.require(report.get('body_schema') == D.SCHEMA and not report.get('native_controls'),
                name + ' schema or native-only admission differs')
    D.F.require(report.get('failed') == report.get('skipped') == 0, name + ' failed or skipped work')
    D.F.require(report.get('operations') == len(required), name + ' incomplete operation count')
    records = report.get('records', [])
    actual = [(row['name'], row['mode'], row['phase']) for row in records]
    D.F.require(len(actual) == len(set(actual)) == len(required) and set(actual) == required,
                name + ' absent, duplicate or unexpected work')
    if name == 'constants':
        D.F.require(report.get('runtime_mode') == ('release' if release else 'normal'),
                    'constant runtime mode differs')
    else:
        D.F.require(report.get('modes') == list(module.MODES) and report.get('release_facts_leaks') is release,
                    name + ' modes differ')
    by_phase = {}
    for row in records:
        D.F.require(row.get('source_sha256') == manifest[row['name']]['source_sha256'],
                    name + ' source identity differs')
        if row['phase'] == 'runtime':
            command = row.get('command', [])
            D.F.require(bool(command) and ('--release' in command) is release
                        and ('--verify-facts' in command) is release,
                        name + ' actual runtime flags differ')
        triple = (row['status'], bytes.fromhex(row['stdout_hex']), bytes.fromhex(row['stderr_hex']))
        by_phase.setdefault((row['name'], row['phase']), {})[row['mode']] = triple
    for (source, phase), modes in by_phase.items():
        reference = modes['reference']
        D.F.require(all(value == reference for value in modes.values()), name + ' transcript differs')
        if phase == 'check':
            D.F.require(reference[0] == manifest[source]['status'], name + ' native status differs')
        elif phase in ('syntax', 'typed'):
            D.F.require(reference[0] == 0 and bool(reference[1]), name + ' empty or failed frontend oracle')
        else:
            result = 8 if name == 'constants' and source == 'source_while.my' else 7
            D.F.require(reference == (result, (str(result) + '\n').encode(), b''),
                        name + ' generated runtime differs')


def require_hostile(report):
    D.F.require(report.get('complete') is True and report.get('selected_admission') == 'passed'
                and report.get('schema') == H.SCHEMA and report.get('hostile') == len(H.NAMES),
                'structural hostile admission incomplete')
    D.F.require(report.get('failed') == report.get('skipped') == 0, 'hostile failed or skipped work')
    rows = report.get('records', [])
    D.F.require([row['name'] for row in rows] == list(H.NAMES), 'absent or duplicate hostile work')
    for row in rows:
        H.J.require_rejection((row['status'], bytes.fromhex(row['stdout_hex']), bytes.fromhex(row['stderr_hex'])))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'builder', 'component-dir', 'zig', 'source-root', 'report-dir'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    for name in vars(args):
        setattr(args, name, getattr(args, name).resolve())
    args.report_dir.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='fresh-', dir=args.report_dir))
    common = ['--compiler', args.compiler, '--builder', args.builder, '--component-dir', args.component_dir,
              '--zig', args.zig, '--source-root', args.source_root]
    before = {'compiler_sha256': D.F.digest(args.compiler), 'packages': D.packages(args.component_dir)}
    total = 0
    for name, release in [('constants', False), ('constants', True),
                          ('structural', True), ('iteration', True), ('chained', True),
                          ('comprehension', False), ('comprehension', True),
                          ('text', False), ('text', True), ('generic', False), ('generic', True)]:
        report_path = args.report_dir / (name + ('-release' if release else '-normal') + '.json')
        command = [sys.executable, Path(LANES[name].__file__).resolve(), *common, '--report', report_path]
        if release:
            command.append('--release')
        subprocess.run(list(map(str, command)), check=True)
        report = json.loads(report_path.read_text())
        require_source(name, report, release)
        D.F.require({key: report.get(key) for key in before} == before, name + ' deployment differs')
        total += report['operations']
    hostile = args.report_dir / 'structural-hostile.json'
    subprocess.run(list(map(str, [sys.executable, Path(H.__file__).resolve(), '--compiler', args.compiler,
                   '--component-dir', args.component_dir, '--zig', args.zig, '--report', hostile,
                   '--evidence-dir', work / 'hostile'])), check=True)
    hostile_report = json.loads(hostile.read_text())
    require_hostile(hostile_report)
    capture = hostile_report['capture']['identity']
    D.F.require(capture == {'host': before['compiler_sha256'], 'packages': before['packages']},
                'hostile deployment differs')
    D.F.require(before == {'compiler_sha256': D.F.digest(args.compiler),
                           'packages': D.packages(args.component_dir)}, 'closure deployment changed')
    print(f'body closure gate: {total} source operations and {len(H.NAMES)} hostile refusals; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
