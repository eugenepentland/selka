#!/usr/bin/env python3
"""Rebuild only the 35 new rows and compare complete measured LLVM modules.

Run under the build slot. Writable artifacts remain in this integration worktree.
No measurements or optimized-IR/assembly audit are rerun. Reuse requires exact
module bytes and unchanged runtime/emitter/driver/clock sources from the measured
commit. Differences retain complete unified diffs and classify changed entities.
"""
import argparse
import difflib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[4]
SPEC = importlib.util.spec_from_file_location('all35_rows', Path(__file__).with_name('measure_all35.py'))
ROWS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ROWS)
DEFAULT_BIN = ROOT / '.mylang-cache/s2-x/rows-after-fact'
DEFAULT_JSON = Path(__file__).with_name('rows-after-fact.json')
TOKEN = r'(?:"[^"\n]+"|[-A-Za-z$._0-9]+)'


def git(*arguments):
    return subprocess.check_output(['git', *arguments], cwd=ROOT, text=True).strip()


def entities(source):
    result = {}
    function_spans = []
    for match in re.finditer(r'^define[^\n]*@(' + TOKEN + r')[^\n]*\{\n.*?^\}', source, re.M | re.S):
        result['function:' + match[1]] = match[0]
        function_spans.append(match.span())
    for match in re.finditer(r'^(?:@' + TOKEN + r'\s*=.*|![-A-Za-z0-9.]+\s*=.*|%' + TOKEN + r'\s*=\s*type.*|declare[^\n]*)$', source, re.M):
        if any(begin <= match.start() < end for begin, end in function_spans):
            continue
        line = match[0]
        category = 'global' if line.startswith('@') else 'metadata' if line.startswith('!') else 'type' if line.startswith('%') else 'declaration'
        key = re.search(r'@(' + TOKEN + r')', line)[1] if category == 'declaration' else line.split('=', 1)[0].strip()
        result[category + ':' + key] = line
    return result


def difference(before, after):
    original, rebuilt = entities(before), entities(after)
    changed = sorted(key for key in original.keys() | rebuilt.keys() if original.get(key) != rebuilt.get(key))
    return {'changed_entities': changed,
            'ordering_or_other_lines_only': not changed and before != after,
            'unified_diff': ''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                                       fromfile='measured LLVM', tofile='rebuilt LLVM'))}


def source_is_frozen(commit):
    if git('rev-parse', 'HEAD') != commit:
        raise ValueError('integration HEAD changed during row reuse proof')
    changes = git('diff', '--name-only', 'HEAD', '--', 'src/core', 'test/core', 'SPEC.md')
    if changes:
        raise ValueError('native inputs differ from committed source: ' + changes)


def smoke():
    before = '''@value = constant i64 1
define i64 @main() {
entry:
  ret i64 1
}
!0 = !{!"measured"}
'''
    assert not difference(before, before)['changed_entities']
    assert difference(before, before.replace('ret i64 1', 'ret i64 2'))['changed_entities'] == ['function:main']
    assert difference(before, before.replace('constant i64 1', 'constant i64 2'))['changed_entities'] == ['global:@value']
    assert difference(before, before.replace('measured', 'rebuilt'))['changed_entities'] == ['metadata:!0']
    assert difference(before, '; header changed\n' + before)['ordering_or_other_lines_only']
    assert ROOT == ROWS.ROOT and DEFAULT_BIN.is_relative_to(ROOT) and DEFAULT_JSON.is_relative_to(ROOT)
    print('rows-after-fact Python smoke: complete-module entity changes and integration-local defaults pass; no native builds')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-commit')
    parser.add_argument('--measured-commit', default='090dabd5a6932a7c3beaec68248f9a35d4c637d7')
    parser.add_argument('--measured', type=Path, default=ROOT / '.mylang-cache/s2-x/all35/llvm')
    parser.add_argument('--bin', type=Path, default=DEFAULT_BIN)
    parser.add_argument('--core', type=Path, default=ROOT / 'zig-out/bin/mylang-core')
    parser.add_argument('--json', type=Path, default=DEFAULT_JSON)
    parser.add_argument('--smoke-test', action='store_true')
    args = parser.parse_args(argv)
    if args.smoke_test:
        smoke()
        return 0
    report = {'valid': False, 'reuse_qualified': False, 'rows': {}, 'error': None,
              'native_samples_rerun': 0, 'optimized_audits_rerun': 0}
    output = None
    try:
        if not args.source_commit:
            raise ValueError('--source-commit is required for a source-bound proof')
        commit = git('rev-parse', args.source_commit + '^{commit}')
        measured_commit = git('rev-parse', args.measured_commit + '^{commit}')
        report.update(source_commit=commit, measured_commit=measured_commit)
        source_is_frozen(commit)
        args.bin = ROWS.inside(args.bin)
        args.measured = args.measured.resolve()
        output = ROWS.inside(args.json)
        if args.measured.is_relative_to(args.bin) or args.bin.is_relative_to(args.measured):
            raise ValueError('rebuilt and measured artifacts must use separate directories')
        protected = ['src/core/emit*.zig', 'src/core/runtime', 'src/core/driver.zig',
                     'benchmarks/runtime/ports/native_clock.c']
        report['runtime_emitter_driver_clock_diff'] = git('diff', '--name-only', measured_commit, commit, '--', *protected).splitlines()
        paths = [f'test/core/{ROWS.stem(row)}.my' for row in ROWS.UNITS]
        report['row_source_diff'] = git('diff', '--name-only', measured_commit, commit, '--', *paths).splitlines()
        llvm = args.bin / 'llvm'
        llvm.mkdir(parents=True, exist_ok=True)
        for row in ROWS.UNITS:
            stem = ROWS.stem(row)
            baseline = args.measured / (stem + '.ll')
            if not baseline.is_file():
                raise ValueError('measured module missing: ' + str(baseline))
            native = args.bin / (stem + '_new')
            emitted = llvm / (stem + '.ll')
            native.unlink(missing_ok=True)
            emitted.unlink(missing_ok=True)
            command = [str(args.core), 'build', str(ROOT / f'test/core/{stem}.my'), '-o', str(native),
                       '--release', '--cache-dir', str(args.bin / 'cache/new'),
                       '--link', str(ROOT / 'benchmarks/runtime/ports/native_clock.c'), '--emit-llvm', str(emitted)]
            started = time.monotonic()
            done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            result = {'command': command, 'status': done.returncode, 'stdout': done.stdout, 'stderr': done.stderr,
                      'duration_s': time.monotonic() - started, 'complete_module_identical': False}
            report['rows'][row] = result
            if done.returncode or not native.is_file() or not emitted.is_file():
                raise ValueError(f'{row}: build status={done.returncode}\n{done.stdout}{done.stderr}')
            original, rebuilt = baseline.read_bytes(), emitted.read_bytes()
            result.update(complete_module_identical=original == rebuilt, measured_bytes=len(original), rebuilt_bytes=len(rebuilt))
            print(f'{row}: build status=0; complete module ' + ('IDENTICAL' if original == rebuilt else 'DIFFERS'), flush=True)
            if original != rebuilt:
                delta = difference(original.decode(), rebuilt.decode())
                patch = args.bin / 'diffs' / (stem + '.diff')
                patch.parent.mkdir(parents=True, exist_ok=True)
                patch.write_text(delta.pop('unified_diff'))
                result.update(**delta, diff_path=str(patch))
                print('  changed entities: ' + repr(result['changed_entities']), flush=True)
        source_is_frozen(commit)
        report['identical_modules'] = sum(value['complete_module_identical'] for value in report['rows'].values())
        report['differing_rows'] = [row for row, value in report['rows'].items() if not value['complete_module_identical']]
        report['valid'] = True
        report['reuse_qualified'] = report['identical_modules'] == 35 and not report['runtime_emitter_driver_clock_diff'] and not report['row_source_diff']
        print('identical_modules=' + str(report['identical_modules']) + '/35; reuse_qualified=' + str(report['reuse_qualified']), flush=True)
        print('runtime/emitter/driver/clock diff=' + repr(report['runtime_emitter_driver_clock_diff']), flush=True)
        print('differing rows=' + repr(report['differing_rows']), flush=True)
        return 0 if report['reuse_qualified'] else 1
    except (OSError, ValueError, subprocess.CalledProcessError, ROWS.InvalidMeasurement) as error:
        report['error'] = str(error)
        print('row reuse proof INVALID: ' + str(error), file=sys.stderr)
        return 1
    finally:
        if output is not None:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())
