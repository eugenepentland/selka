#!/usr/bin/env python3
"""Exercise real installed guest discovery, providers, receipts and private shared evidence."""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_admission import admission

APP = '''import dep

public func test_answer() -> bool:
    return dep.answer() == 1

public func test_independent() -> bool:
    return True

public func test_fixture() -> bool:
    return embed_str("expected.txt") == "ready"
'''
DEP = 'public func answer() -> int:\n    return 1\n'
EXTRA = 'public func test_extra() -> bool:\n    return True\n'
BASE = {'app_test::test_answer', 'app_test::test_independent', 'app_test::test_fixture'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources(root):
    return {p.relative_to(root).as_posix(): sha(p) for p in sorted(root.rglob('*')) if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--telemetry-root', type=Path, required=True)
    parser.add_argument('--scratch', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    scratch, output = args.scratch.resolve(), args.output.resolve()
    if scratch.exists() or output.exists():
        parser.error('scratch/output must be new private directories')
    scratch.mkdir(parents=True)
    output.mkdir(parents=True)
    compiler, zig = args.compiler.resolve(), args.zig.resolve()
    sys.path.insert(0, str(args.telemetry_root.resolve() / 'scripts'))
    import verification_report
    if not hasattr(verification_report, 'guest_test_timings'):
        raise RuntimeError('supported S01 guest adapter unavailable')
    project = scratch / 'tree-a'
    project.mkdir()
    (project / 'app_test.my').write_text(APP)
    (project / 'dep.my').write_text(DEP)
    (project / 'expected.txt').write_text('ready')
    shared = scratch / 'guest-success-store'
    caches = {project: scratch / 'cache-a'}
    manifest = {'version': 1, 'scope': 'actual guest native actions; bounded fixture project, not repository gate',
        'compiler': {'path': str(compiler), 'sha256': sha(compiler)}, 'zig': {'path': str(zig), 'sha256': sha(zig)},
        'adapter': {'path': verification_report.__file__, 'sha256': sha(Path(verification_report.__file__))},
        'cache_scope': 'private per-tree guest caches plus private experiment shared evidence; global Zig cache remains available',
        'per_test_timing': 'unknown; no timing inferred from raw verdict output', 'rows': []}
    environment = dict(os.environ)
    environment.pop('MYL_CORE_LEAKCHECK', None)
    environment['MYLANG_CORE_RUNTIME_CACHE'] = str(scratch / 'runtime-cache')
    environment['TMPDIR'] = str(scratch / 'tmp')
    Path(environment['TMPDIR']).mkdir()
    with admission('build'):
        def run(label, *, tree=project, flags=(), expected=BASE, failures=(), all_fresh=False, leak=False):
            command = [str(compiler), 'test', str(tree), '--json', '--zig', str(zig), '--jobs', '2',
                       '--cache-dir', str(caches[tree]), '--shared-cache-dir', str(shared), *flags]
            env = dict(environment)
            if leak:
                env['MYL_CORE_LEAKCHECK'] = '1'
            start = time.monotonic_ns()
            result = subprocess.run(command, env=env, cwd=ROOT, capture_output=True, timeout=600)
            capture = output / label
            capture.mkdir()
            stdout = capture / 'stdout.json'
            stdout.write_bytes(result.stdout)
            (capture / 'stderr.log').write_bytes(result.stderr)
            record = json.loads(result.stdout)
            telemetry = verification_report.guest_test_timings(stdout, action_id='language', member=0)
            row = {'label': label, 'command': command, 'status': result.returncode,
                'source_files': sources(tree), 'report_sha256': sha(stdout), 'sources_reported': record.get('sources'),
                'counts': {name: record.get(name) for name in ('passed', 'cached', 'failed', 'skipped', 'unsupported')},
                'test_receipt_keys': {test['name']: test.get('cache', {}).get('key') for test in record['tests']},
                'test_cache_decisions': {test['name']: test.get('cache') for test in record['tests']},
                'environment_mode': {'MYL_CORE_LEAKCHECK': env.get('MYL_CORE_LEAKCHECK'), 'MYLANG_CORE_RUNTIME_CACHE': env.get('MYLANG_CORE_RUNTIME_CACHE'),
                    'ZIG_LOCAL_CACHE_DIR': env.get('ZIG_LOCAL_CACHE_DIR'), 'ZIG_GLOBAL_CACHE_DIR': env.get('ZIG_GLOBAL_CACHE_DIR'), 'TMPDIR': env.get('TMPDIR')},
                'telemetry': telemetry, 'action_elapsed_ns': time.monotonic_ns() - start,
                'qualification': 'operational correctness only; no isolated latency claim'}
            manifest['rows'].append(row)
            (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
            print(json.dumps({'label': label, 'status': result.returncode, 'counts': row['counts']}), flush=True)
            tests = {test['name']: test['status'] for test in record['tests']}
            if set(tests) != set(expected) or len(tests) != len(record['tests']):
                raise RuntimeError('actual guest selected inventory mismatch: ' + label)
            if {name for name, state in tests.items() if state == 'failed'} != set(failures):
                raise RuntimeError('actual guest failed unexpected tests: ' + label)
            if result.returncode != int(bool(failures)) or record.get('unsupported') or record.get('skipped'):
                raise RuntimeError('actual guest verdict/status mismatch: ' + label)
            if telemetry.get('status') != 'observed' or telemetry['selected'] != len(expected):
                raise RuntimeError('supported guest adapter did not observe exact inventory')
            if all_fresh and record['cached']:
                raise RuntimeError('fresh control reused a guest verdict: ' + label)
            return row
        run('01-cold')
        run('02-warm')
        (project / 'dep.my').write_text(DEP.replace('return 1', 'return 2'))
        run('03-helper-failure', failures={'app_test::test_answer'})
        run('04-helper-failure-repeat', failures={'app_test::test_answer'})
        (project / 'dep.my').write_text(DEP)
        run('05-helper-revert')
        (project / 'expected.txt').write_text('changed')
        run('06-embedded-fixture-failure', failures={'app_test::test_fixture'})
        run('07-embedded-fixture-failure-repeat', failures={'app_test::test_fixture'})
        (project / 'expected.txt').write_text('ready')
        run('08-embedded-fixture-revert')
        (project / 'app_test.cases.json').write_text(json.dumps({'app_test::test_answer': {'providers': {'dep.my': DEP.replace('return 1', 'return 2')}}}))
        run('09-provider-failure', failures={'app_test::test_answer'})
        run('10-provider-failure-repeat', failures={'app_test::test_answer'})
        (project / 'app_test.cases.json').write_text(json.dumps({'app_test::test_answer': {'providers': {'dep.my': DEP}}}))
        run('11-provider-revert')
        (project / 'app_test.cases.json').unlink()
        run('12-negative-cases-revert')
        (project / 'extra_test.my').write_text(EXTRA)
        run('13-source-add', expected=BASE | {'extra_test::test_extra'})
        (project / 'extra_test.my').rename(project / 'renamed_test.my')
        run('14-source-rename', expected=BASE | {'renamed_test::test_extra'})
        (project / 'renamed_test.my').unlink()
        run('15-source-delete')
        run('16-force', flags=('--force',), all_fresh=True)
        run('17-no-cache', flags=('--no-cache',), all_fresh=True)
        run('18-facts-leaks', flags=('--release', '--verify-facts'), all_fresh=True, leak=True)
        second = scratch / 'tree-b'
        shutil.copytree(project, second)
        caches[second] = scratch / 'cache-b'
        run('19-compatible-second-tree', tree=second)
        run('20-second-tree-warm', tree=second)
    manifest['complete'] = True
    manifest['second_tree_reuse'] = 'recorded actual cached/fresh decisions; no root identity is erased by the harness'
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
