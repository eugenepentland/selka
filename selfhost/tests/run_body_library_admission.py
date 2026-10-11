#!/usr/bin/env python3
"""Explicit admission of real compiler libraries; never a bootstrap shortcut."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile
import run_body_check_qualification as D

F = D.F
FIXTURES = Path(__file__).with_name('fixtures') / 'body_library_followup'
LIBRARIES = (
    'body_check/graph.my', 'body_check/codec.my', 'body_check/checking.my',
    'parser_pilot/syntax_codec.my', 'lexer_pilot/wire.my', 'cache_plan/graph.my',
    'cache_plan/incremental.my', 'declaration_index/codec.my', 'type_interface/codec.my',
)
TESTS = (
    'declaration_index/tests.my', 'declaration_index/indexed_tests.my',
    'type_interface/tests.my', 'parser_pilot/value_tests.my',
    'cache_plan/tests.my', 'test_index/tests.my',
)


def require_manifest(manifest):
    F.require(len(manifest) == 16 and sum(s['status'] == 0 for s in manifest.values()) == 10
              and sum(s['status'] == 1 for s in manifest.values()) == 6,
              'incomplete pure-library followup selection')
    F.require(all(type(s['status']) is int and s['status'] in (0, 1) for s in manifest.values()), 'profile refusal is not library admission')


def test_selection(path):
    names = re.findall(r'^public func (test_\w+)\(', path.read_text(), re.M)
    F.require(names and len(names) == len(set(names)), 'empty/duplicate actual library test selection')
    return names


def require_tests(result, expected):
    F.test_counts(result, len(expected))
    report = json.loads(result[1])
    names = [test['name'].split('::')[-1].split('.')[-1] for test in report['tests']]
    F.require(set(names) == set(expected), 'actual test identities differ from source inventory')
    return [{'name': test['name'], 'status': test['status']} for test in report['tests']]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--compiler', type=Path, required=True)
    ap.add_argument('--zig', type=Path, required=True)
    ap.add_argument('--builder', type=Path, help='required for selected qualified-seed verification')
    ap.add_argument('--source-root', type=Path, default=D.ROOT)
    ap.add_argument('--component-dir', type=Path, required=True)
    ap.add_argument('--native-controls', action='store_true', help='only native fixture controls; selected/library admission remains pending')
    ap.add_argument('--report', type=Path, required=True)
    args = ap.parse_args()
    manifest = json.loads((FIXTURES / 'manifest.json').read_text())
    require_manifest(manifest)
    records = []
    modes = ['reference'] if args.native_controls else ['reference', 'shadow', 'component']
    packages = None if args.native_controls else D.packages(args.component_dir)
    seed_sha256 = None
    if not args.native_controls:
        F.require(args.builder is not None, 'selected library admission requires qualified-seed builder')
        result = F.execute([args.builder, '--root', args.source_root, '--zig', args.zig, '--seed-only'],
                           D.coordinator_environment(), args.source_root, 600)
        lines = result[1].decode().strip().splitlines()
        F.require(result[0] == 0 and len(lines) == 1 and Path(lines[0]).is_file(),
                  'qualified seed receipt verification failed')
        seed_sha256 = F.digest(Path(lines[0]))
    with tempfile.TemporaryDirectory(prefix='body-library-admission-') as temporary:
        work = Path(temporary)
        source = work / 'sources'
        source.mkdir()
        empty = work / 'empty-path'
        empty.mkdir()
        def execute(mode, command, phase):
            env = D.environment(mode, args.component_dir, empty)
            result = F.execute([args.compiler, *command], env, work, 600)
            records.append({'mode': mode, 'phase': phase, 'command': list(map(str, [args.compiler, *command])),
                            'source_sha256': F.digest(Path(command[1])),
                            'status': result[0], 'stdout_sha256': hashlib.sha256(result[1]).hexdigest(),
                            'stderr': result[2].decode('utf-8', 'replace')})
            return result
        for name, spec in manifest.items():
            entry = source / name
            original = FIXTURES / Path(name).with_suffix('.input')
            F.require(F.digest(original) == spec['source_sha256'], 'fixture source digest changed: ' + name)
            shutil.copyfile(original, entry)
            command = ['check-project', entry, '--diagnostics=json']
            native = execute('reference', command, name)
            F.require(native[0] == spec['status'] and not native[1], 'native fixture status changed: ' + name)
            if 'diagnostics' in spec:
                diagnostics = [D.diagnostic_contract(json.loads(line)['diagnostic']) for line in native[2].splitlines()]
                F.require(diagnostics == spec['diagnostics'], 'native diagnostic precedence/repair changed: ' + name)
            for mode in modes[1:]:
                F.require(execute(mode, command, name) == native, 'selected body fixture differs: ' + name)
            if spec['status'] == 0:
                for mode in modes:
                    command = ['run-project', entry, '--release', '--verify-facts', '--print-result',
                               '--cache-dir', work / ('cache-' + mode), f'--zig={args.zig}']
                    F.require(execute(mode, command, name + '-runtime') == (7, b'7\n', b''), 'generated runtime differs: ' + name)
        if not args.native_controls:
            components = args.source_root / 'selfhost/components'
            for relative in LIBRARIES:
                command = ['check', components / relative, '--diagnostics=json']
                native = execute('reference', command, relative)
                F.require(native == (0, b'', b''), 'native actual library admission failed: ' + relative)
                for mode in modes[1:]:
                    # Runtime shadow checks full typed batch/catalog, not dump text alone.
                    F.require(execute(mode, command, relative) == native, 'actual selected library rejected/differed: ' + relative)
            for relative in TESTS:
                entry = components / relative
                expected = test_selection(entry)
                for release in (False, True):
                    flags = ['--release', '--verify-facts'] if release else []
                    command = ['test', entry, '--json', '--force', '--no-cache', '--max-steps=100000000', f'--zig={args.zig}', *flags]
                    for mode in modes:
                        verdict = require_tests(execute(mode, command, relative + ('-release' if release else '-normal')), expected)
                        records[-1]['tests'] = verdict
    report = {'scope': 'native fixture controls' if args.native_controls else 'nine libraries and six test roots; seven package entries not admitted',
              'selected_admission': 'pending' if args.native_controls else 'passed',
              'compiler_sha256': F.digest(args.compiler), 'packages': packages, 'qualified_seed_sha256': seed_sha256,
              'fixtures': len(manifest), 'library_roots': 9, 'test_roots': 6,
              'helper_runs': 0 if args.native_controls else 63, 'records': records,
              'failed': 0, 'skipped': 0}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(f'body library {report["selected_admission"]}: 16 fixtures; {report["helper_runs"]} helper runs; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
