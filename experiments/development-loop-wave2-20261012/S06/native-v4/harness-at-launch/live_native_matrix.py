#!/usr/bin/env python3
"""Real Zig native cohort through the unchanged production dispatcher/provider/store."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
GROUPS = {'text_scalar_unit', 'tooling_unit', 'fixtures', 'format'}
SCALAR = ('text_scalar_root_test.zig', 'number_text_test.zig', 'number_text.zig',
          'format_spec_test.zig', 'format_spec.zig', 'number_grammar.txt', 'format_spec_cases.tsv')
TOOLING = ('tooling_root_test.zig', 'doc_coverage_test.zig', 'doc_coverage.zig',
           'input_probe_test.zig', 'input_probe.zig', 'fix_plan_test.zig', 'fix_plan.zig',
           'timings_test.zig', 'timings.zig', 'invalidation_test.zig', 'invalidation.zig')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def initialize(root, source, frozen, compiler):
    root.mkdir()
    (root / 'src').mkdir()
    for directory in ('tests', 'selfhost', 'docs', 'benchmarks/runtime/ports'):
        (root / directory).mkdir(parents=True)
    for name in ('build.zig.zon', 'guardian.toml', 'README.md', 'SPEC.md', 'src/user_docs.zig', 'benchmarks/runtime/ports/native_clock.c'):
        shutil.copy2(source / name, root / name)
    shutil.copytree(source / 'scripts', root / 'scripts', ignore=shutil.ignore_patterns('__pycache__'))
    (root / 'test/membership').mkdir(parents=True)
    for name in (*SCALAR, *TOOLING):
        shutil.copy2(source / 'src' / name, root / 'src' / name)
    shutil.copy2(HERE / 'membership_cases.py', root / 'scripts/membership_cases.py')
    shutil.copy2(HERE / 'cohort_build.zig', root / 'build.zig')
    shutil.copy2(source / 'build_verification.zig', root / 'build_verification.zig')
    shutil.copy2(source / '.zigversion', root / '.zigversion')
    lists = {'text_scalar_unit': ['src/' + name for name in SCALAR],
             'tooling_unit': ['src/' + name for name in TOOLING],
             'fixtures': ['scripts/membership_cases.py', 'test/membership/'],
             'format': ['src/*.zig', 'build.zig', 'build_verification.zig', 'build_test_inputs.zig', 'support.zig']}
    (root / 'build_test_inputs.zig').write_text(''.join(
        f'pub const {name} = [_][]const u8{{' + ','.join(json.dumps(value) for value in values) + '};\n'
        for name, values in lists.items()))
    artifacts = json.loads((frozen / 'zig-out/verification/artifacts.json').read_text())['artifacts']
    support = dict((name, compiler if name == 'mylang' else Path(artifacts[name])) for name in ('mylang', 'units', 'cli', 'core'))
    lines = [f'pub const {name} = {json.dumps(str(path))};' for name, path in support.items()]
    components = []
    package = frozen / 'zig-out/libexec/mylang/components'
    for label in ('test-index', 'cache-plan'):
        manifest = package / (label + '.json')
        artifact = package / json.loads(manifest.read_text())['artifact']
        for path in (manifest, artifact):
            components.append('.{ .source = ' + json.dumps(str(path)) + ', .name = ' + json.dumps(path.name) + ' }')
    lines.append('pub const components = .{' + ','.join(components) + '};')
    (root / 'support.zig').write_text('\n'.join(lines) + '\n')
    (root / 'test/membership/a.txt').write_text('1\n')
    (root / 'test/membership/stable.txt').write_text('1\n')
    return {name: dict(path=str(path), sha256=digest(path)) for name, path in support.items()}


def environment(root):
    env = dict(os.environ)
    env['ZIG_LOCAL_CACHE_DIR'] = str(root / '.zig-cache')
    env['TMPDIR'] = str(root / '.tmp')
    (root / '.tmp').mkdir(exist_ok=True)
    return env


def latest_report(root):
    paths = list((root / '.mylang-cache').glob('verification-*/last-run.json'))
    if len(paths) != 1:
        raise RuntimeError('expected exactly one explicit verification report namespace: ' + str(paths))
    return paths[0], json.loads(paths[0].read_text())


class Session:
    def __init__(self, root):
        self.root = root
        self.error = (root.parent / (root.name + '-session.stderr')).open('wb')
        self.process = subprocess.Popen([sys.executable, '-B', str(root / 'scripts/cache_session.py')],
            cwd=root, env=environment(root), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.error, text=True)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.sequence = 0

    def request(self, args=None, command='verify'):
        self.sequence += 1
        self.process.stdin.write(json.dumps(dict(id=self.sequence, command=command, args=args or [])) + '\n')
        self.process.stdin.flush()
        if not self.selector.select(600):
            raise TimeoutError('real cache-session request exceeded capture bound')
        line = self.process.stdout.readline()
        if not line:
            raise RuntimeError('real cache-session stopped; inspect session stderr')
        result = json.loads(line)
        if result['id'] != self.sequence:
            raise RuntimeError('response identifier mismatch')
        return result

    def close(self):
        try:
            if self.process.poll() is None:
                try:
                    self.request(command='stop')
                    self.process.wait(timeout=10)
                except (BrokenPipeError, RuntimeError):
                    pass
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait()
            self.selector.close()
            try:
                self.process.stdin.close()
            except BrokenPipeError:
                pass
            self.process.stdout.close()
            self.error.close()


def capture(root, output, label, response, expected_success, expected_execute, expected_reused):
    report_path, report = latest_report(root)
    directory = output / label
    directory.mkdir()
    (directory / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    (directory / 'response.json').write_text(json.dumps(response, indent=2) + '\n')
    actions = {item['id']: item for item in report['actions']}
    if set(actions) != GROUPS or set(expected_execute) | set(expected_reused) != GROUPS:
        raise RuntimeError('cohort action inventory mismatch: ' + label)
    if (response['status'] == 0) != expected_success or report['success'] != expected_success:
        raise RuntimeError('live outcome mismatch: ' + label)
    for name in expected_execute:
        if actions[name]['state'] not in ('execute', 'fresh'):
            raise RuntimeError('affected action skipped/reused: ' + label + '/' + name)
    for name in expected_reused:
        if actions[name]['state'] != 'reused':
            raise RuntimeError('proven unrelated action did not reuse: ' + label + '/' + name)
    if report.get('inputs_stable') is not True:
        raise RuntimeError('capture did not retain valid source authority: ' + label)
    for action in actions.values():
        receipt = report_path.parent / 'actions' / (action['action_key'] + '.json')
        if not expected_success and action['id'] in expected_execute and receipt.exists():
            raise RuntimeError('failed selected action retained a local success: ' + label)
    if expected_execute:
        logs = report_path.parent / 'last-logs'
        if logs.exists():
            shutil.copytree(logs, directory / 'logs')
    inventory = json.loads((root / 'zig-out/verification/inventory.json').read_text())
    if inventory['coverage'] != dict(required_actions=4, registered_actions=4, unknown_actions=[]):
        raise RuntimeError('real exported gate registration incomplete')
    producers = json.loads((root / 'zig-out/verification/artifacts.json').read_text())['producers']
    if set(producers) != {'text-scalar-units', 'tooling-units'}:
        raise RuntimeError('real writer did not authenticate both native producers')
    row = dict(label=label, root=str(root), report_namespace=report_path.parent.name,
        status=response['status'], success=report['success'], executed=sorted(expected_execute), reused=sorted(expected_reused),
        action_keys={name: item['action_key'] for name, item in actions.items()},
        snapshot_statistics=report['snapshot_statistics'], elapsed_seconds=report['elapsed_seconds'],
        phase='operational live correctness; no isolated latency claim')
    (directory / 'inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
    (directory / 'producer-metadata.json').write_text(json.dumps(producers, indent=2) + '\n')
    print(json.dumps(row), flush=True)
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, default=ROOT)
    parser.add_argument('--frozen-root', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--scratch', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--resume-native-v4', action='store_true', help='Continue the known complete oracle/revert prefix on its private restored tree')
    args = parser.parse_args()
    source, frozen, compiler, zig = [p.resolve() for p in (args.source_root, args.frozen_root, args.compiler, args.zig)]
    scratch, output = args.scratch.resolve(), args.output.resolve()
    if not args.resume_native_v4 and (scratch.exists() or output.exists()):
        parser.error('scratch and output must be new private directories')
    if args.resume_native_v4:
        for path in (scratch / 'tree-a', output / 'manifest.json', output / '05-oracle-revert/report.json'):
            if not path.exists():
                parser.error('resume requires the captured real native-v4 prefix')
    else:
        scratch.mkdir(parents=True)
        output.mkdir(parents=True)
    guardian_root = scratch / 'guardian-zig'
    if not args.resume_native_v4:
        shutil.copytree(source.parent / 'guardian-zig/src', guardian_root / 'src', ignore=shutil.ignore_patterns('__pycache__'))
        for path in (source.parent / 'guardian-zig').glob('*.zig*'):
            if path.is_file():
                shutil.copy2(path, guardian_root / path.name)
    guardian = guardian_root / 'src'
    roots = [scratch / 'tree-a', scratch / 'tree-b']
    support = None
    if not args.resume_native_v4:
        support = initialize(roots[0], source, frozen, compiler)
        # Format only disposable configuration, before installing source authority.
        subprocess.run([str(zig), 'fmt', 'build.zig', 'build_test_inputs.zig', 'support.zig'], cwd=roots[0], check=True, capture_output=True)
    shared = scratch / 'success-store'
    request_args = ['--zig', str(zig), '--shared-cache-dir', str(shared), '--', '-j4', '--maxrss', '8589934592']
    manifest = dict(version=1, source_root=str(source), source_sha=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip(),
        scope='bounded real native cohort, not complete repository verification', zig=dict(path=str(zig), sha256=digest(zig)), support=support,
        dispatcher_sha256=digest(source / 'scripts/verify_cache.py'), registry_sha256=digest(source / 'build_verification.zig'),
        guardian_inputs={p.relative_to(guardian_root).as_posix(): digest(p) for p in guardian_root.rglob('*') if p.is_file()}, request_args=request_args, rows=[])
    if args.resume_native_v4:
        manifest = json.loads((output / 'manifest.json').read_text())
        if [row['label'] for row in manifest['rows']] != ['01-cold', '02-warm', '03-oracle-failure', '04-oracle-failure-repeat']:
            raise RuntimeError('resume prefix does not match its explicit checkpoint')
        previous = json.loads((output / '05-oracle-revert/report.json').read_text())
        if not previous.get('success') or previous.get('inputs_stable') is not True:
            raise RuntimeError('checkpoint revert execution was not a stable success')
        manifest['rows'].append(dict(label='05-oracle-revert', status=0, success=True, executed=['text_scalar_unit'], reused=sorted(GROUPS - {'text_scalar_unit'}),
            action_keys={row['id']: row['action_key'] for row in previous['actions']}, snapshot_statistics=previous['snapshot_statistics'],
            note='Real revert executes because exact native implementation changed; original overly strict reuse expectation corrected'))
        manifest['resume'] = {'prefix': 'native-v4', 'harness_sha256': digest(Path(__file__)), 'no_receipts_or_keys_modified': True}
    original = {name: (roots[0] / 'src' / name).read_text() for name in SCALAR}
    session = Session(roots[0])
    try:
        def row(label, success=True, execute=(), reuse=()):
            response = session.request(request_args)
            manifest['rows'].append(capture(roots[0], output, label, response, success, set(execute), set(reuse)))
            (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        if not args.resume_native_v4:
            row('01-cold', execute=GROUPS)
            row('02-warm', reuse=GROUPS)
            oracle = roots[0] / 'src/number_grammar.txt'
            if 'int|42|42' not in original['number_grammar.txt']:
                raise RuntimeError('actual oracle mutation anchor changed')
            oracle.write_text(original['number_grammar.txt'].replace('int|42|42', 'int|42|43', 1))
            row('03-oracle-failure', False, {'text_scalar_unit'}, GROUPS - {'text_scalar_unit'})
            row('04-oracle-failure-repeat', False, {'text_scalar_unit'}, GROUPS - {'text_scalar_unit'})
            oracle.write_text(original['number_grammar.txt'])
            row('05-oracle-revert', execute={'text_scalar_unit'}, reuse=GROUPS - {'text_scalar_unit'})
        tests = roots[0] / 'src/number_text_test.zig'
        tests.write_text(original['number_text_test.zig'] + '\ntest "S06 live added failing case" {\n    try std.testing.expect(false);\n}\n')
        row('06-test-add-failure', False, {'text_scalar_unit', 'format'}, {'tooling_unit', 'fixtures'})
        tests.write_text(original['number_text_test.zig'])
        row('07-test-revert', execute={'text_scalar_unit'}, reuse=GROUPS - {'text_scalar_unit'})
        helper = roots[0] / 'src/number_text.zig'
        helper.write_text(original['number_text.zig'].replace('return integerOf(u32, points);', 'return integerOf(u32, points[0..0]);', 1))
        row('08-helper-semantic-failure', False, {'text_scalar_unit', 'format'}, {'tooling_unit', 'fixtures'})
        helper.write_text(original['number_text.zig'])
        row('09-helper-revert', execute={'text_scalar_unit'}, reuse=GROUPS - {'text_scalar_unit'})
        members = roots[0] / 'test/membership'
        added = members / 'added.txt'
        added.write_text('1\n')
        row('10-member-add', execute={'fixtures'}, reuse=GROUPS - {'fixtures'})
        added.rename(members / 'renamed.txt')
        row('11-member-rename', execute={'fixtures'}, reuse=GROUPS - {'fixtures'})
        (members / 'renamed.txt').unlink()
        row('12-member-delete-revert', reuse=GROUPS)
        (members / 'a.txt').write_text('0\n')
        row('13-member-cached-pass-to-failure', False, {'fixtures'}, GROUPS - {'fixtures'})
        row('14-member-failure-repeat', False, {'fixtures'}, GROUPS - {'fixtures'})
        (members / 'a.txt').write_text('1\n')
        row('15-member-revert', reuse=GROUPS)
    finally:
        session.close()
    # A separate real source copy uses the same private success store. Root/env
    # authority intentionally remains worktree-local, so it must execute safely.
    shutil.copytree(roots[0], roots[1], ignore=shutil.ignore_patterns('.zig-cache', '.mylang-cache', 'zig-out', '.tmp', '__pycache__'))
    second = Session(roots[1])
    try:
        response = second.request(request_args)
        manifest['rows'].append(capture(roots[1], output, '16-compatible-second-tree', response, True, GROUPS, set()))
        response = second.request(request_args)
        manifest['rows'].append(capture(roots[1], output, '17-second-tree-warm', response, True, set(), GROUPS))
    finally:
        second.close()
    manifest['second_tree_reuse'] = 'unavailable by explicit root/environment/loaded-location context; conservative execution expected'
    manifest['complete'] = True
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
