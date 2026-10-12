#!/usr/bin/env python3
"""Recheck candidate ownership against retained, successful C0 cache artifacts.

The original disposable cache stays at the same absolute paths. Its complete
pre-run contents are copied into this run's work directory before any compiler
executes; immutable historical reports are only read. Source edits are restored
even if a compiler or guest fails. This is correctness evidence, not timing.
"""
import argparse
import json
from pathlib import Path
import shutil
from types import SimpleNamespace

import qualify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--baseline-work', type=Path, required=True)
    parser.add_argument('--baseline-report', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--default-zero', action='store_true')
    parser.add_argument('--admission', choices=('build', 'held'), default='build')
    args = parser.parse_args()
    baseline = args.baseline_work.resolve()
    report = json.loads(args.baseline_report.read_text())
    expected_rows = ('valid-owner-restored', 'invalid-under-rc', 'map-abi-replay')
    rows = {row['name']: row for row in report['cases']}
    for name in expected_rows:
        if not rows[name]['passed']:
            raise ValueError('Retained baseline did not pass: ' + name)
    for name, directory in (('valid-owner-restored', 'cache-project'), ('map-abi-replay', 'map-abi')):
        for source, expected in rows[name]['sources'].items():
            if qualify.digest(baseline / directory / source) != expected:
                raise ValueError('Retained source differs from its report: ' + source)
    settings = SimpleNamespace(**vars(args), candidate=None, candidate_revision=None,
                               candidate_default_zero=False, memory_wrapper=None, timeout=120)
    settings.compiler = settings.compiler.resolve()
    settings.zig = settings.zig.resolve()
    run = qualify.Run(settings)
    backup = run.work / 'baseline-snapshot'
    shutil.copytree(baseline, backup)
    manifest = {str(path.relative_to(baseline)): qualify.digest(path)
                for path in baseline.rglob('*') if path.is_file()}
    provenance = dict(harness_sha256=qualify.digest(__file__),
                      baseline_report=str(args.baseline_report.resolve()),
                      baseline_report_sha256=qualify.digest(args.baseline_report),
                      baseline_compiler_sha256=report['compiler_sha256'],
                      baseline_work=str(baseline), snapshot=str(backup), files=manifest,
                      baseline_cases=expected_rows,
                      limitation='No fresh C0 execution: immutable C0 native fallback fails after host loader-cache change. Existing successful artifacts are retained at their original paths.')
    qualify.write(run.out / 'baseline-provenance.json', json.dumps(provenance, indent=2) + '\n')
    run.env['MYLANG_COMPILER_SHARED_CACHE'] = str(baseline / 'shared')
    run.env['MYLANG_CORE_RUNTIME_CACHE'] = str(baseline / 'objects')
    project = baseline / 'cache-project'
    source = project / 'main.my'
    saved = source.read_text()
    try:
        for name, directory, expected in (('old-mixed', project, '3 8\n'),
                                          ('old-map-abi', baseline / 'map-abi', '1 3\n')):
            row = run.build(name + '-first', directory, expected=expected)
            if row['passed']:
                stages = row['report']['stages']
                # Later cases may reuse candidate artifacts from earlier cases;
                # the old module body itself must be lowered with the new ABI.
                row['passed'] &= stages['lowering']['reused'] == 0
                run.save()
            run.build(name + '-receipt', directory, expected=expected, emit=False)
            run.build(name + '-replay', directory, expected=expected, emit=False)
        qualify.write(source, qualify.INVALID)
        expected_sources = rows['invalid-under-rc']['sources']
        if any(qualify.digest(project / name) != value for name, value in expected_sources.items()):
            raise ValueError('Invalid-source probe differs from retained admitted RC artifact')
        run.build('old-rc-admitted-source-refused', project, refuse=True, emit=False)
        run.build('old-rc-admitted-source-refused-warm', project, refuse=True, emit=False)
    finally:
        qualify.write(source, saved)
    run.build('old-source-restored', project, emit=False)
    unchanged = {name: qualify.digest(baseline / name) == value if (baseline / name).is_file() else False
                 for name, value in manifest.items()}
    provenance['old_files_unchanged'] = all(unchanged.values())
    provenance['old_files_changed'] = [name for name, same in unchanged.items() if not same]
    qualify.write(run.out / 'baseline-provenance.json', json.dumps(provenance, indent=2) + '\n')
    raise SystemExit(0 if all(row['passed'] for row in run.rows) else 1)


if __name__ == '__main__':
    main()
