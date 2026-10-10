#!/usr/bin/env python3
"""Compiler-wide frontend qualification. Developer-only; run through build-slot.

An installed host and packages are inputs, never silently rebuilt. --edit-check
explicitly asks the native coordinator to rebuild a private source closure.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import selectors
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
SOURCE_LIMIT = 1048576


def profile_sources():
    suffix = b'func main() -> int:\n    return 0\n'
    boundary = b'#' + b' ' * (SOURCE_LIMIT - len(suffix) - 2) + b'\n' + suffix
    dense = (b'func main() -> int:\n    mut total: int = 0\n' +
             b'    total = total + 1\n' * 16000 + b'    return total\n')
    return {'boundary.my': boundary, 'oversize.my': boundary + b'\n',
            'profile_dense.my': dense,
            'profile_nested.my': b'func main() -> int:\n    return ' + b'(' * 16 + b'0' + b')' * 16 + b'\n',
            'profile_deep_malformed.my': b'func main() -> int:\n    return ' + b'(' * 300 + b'0\n',
            'profile_comments.my': (b'# Unicode ' + 'éλ'.encode() + b'\n') * 25000 + suffix}
FIXTURES = ROOT / 'selfhost/tests/fixtures/frontend_qualification'
FRONTENDS = ('lexer-pilot', 'parser-pilot')
PACKAGES = ('test-index', 'cache-plan', *FRONTENDS)
OUTPUT_LIMIT = (64 << 20) + 4096  # AST profile wire cap plus bounded framing.
ADDRESS_SPACE_BUDGET = 2 << 30


def process_limits():
    # Qualification budget, not a claim about the production launcher. Never
    # relax a caller's stricter soft or hard ceiling; descendants inherit it.
    for kind, budget in ((resource.RLIMIT_FSIZE, OUTPUT_LIMIT),
                         (resource.RLIMIT_AS, ADDRESS_SPACE_BUDGET)):
        soft, hard = resource.getrlimit(kind)
        ceiling = min([budget] + [v for v in (soft, hard) if v != resource.RLIM_INFINITY])
        resource.setrlimit(kind, (ceiling, ceiling))


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def copy_sources(destination):
    # .input keeps intentionally malformed/noncanonical evidence out of the
    # live .my formatter. Every fixture is materialized as real source at run time.
    shutil.copytree(FIXTURES, destination)
    inputs = list(destination.glob('*.input'))
    require(len(inputs) == 8, 'frontend fixture selection changed or empty')
    for path in inputs:
        path.rename(path.with_suffix('.my'))


def execute(argv, env, cwd, timeout=180):
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        result = subprocess.run([str(a) for a in argv], env=env, cwd=cwd,
                                stdout=stdout, stderr=stderr, timeout=timeout,
                                preexec_fn=process_limits)
        stdout.seek(0)
        stderr.seek(0)
        return result.returncode, stdout.read(OUTPUT_LIMIT), stderr.read(OUTPUT_LIMIT)


def environment(mode, components, empty_path):
    # Caller routing, authority and oracle controls cannot contaminate a lane.
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('PILOT_') and not k.startswith('MYLANG_')}
    env.update(PATH=str(empty_path), MYLANG_LEXER_MODE=mode,
               MYLANG_PARSER_MODE=mode, MYLANG_COMPONENT_DIR=str(components),
               MYLANG_TEST_INDEX_MODE='reference', MYLANG_CACHE_PLAN_MODE='reference',
               MYL_CORE_LEAKCHECK='1')
    return env


def packages(directory, frontend_schema=2):
    found = {}
    for name in PACKAGES:
        manifest = json.loads((directory / f'{name}.json').read_text())
        version = 2 if name == 'cache-plan' else 1
        schema = frontend_schema if name in FRONTENDS else version
        require(all(manifest.get(k) == v for k, v in
                    {'format': 1, 'component': name, 'protocol': version, 'schema': schema}.items()),
                f'{name}: invalid manifest identity')
        artifact = manifest.get('artifact', '')
        require(artifact not in ('', '.', '..') and '/' not in artifact and '\\' not in artifact,
                f'{name}: unsafe artifact name')
        require(digest(directory / artifact) == manifest.get('sha256'), f'{name}: digest mismatch')
        found[name] = manifest
    return found


def test_counts(result, expected=2, allow_cached=False):
    require(result[0] == 0 and not result[2], f'guest tests failed: {result!r}')
    report = json.loads(result[1])
    require(report.get('version') == 'native-tests-v1', 'unexpected test report')
    require(len(report.get('tests', [])) == expected, 'empty or changed test selection')
    require(len({t.get('name') for t in report['tests']}) == expected, 'duplicate selected test names')
    require(report.get('passed', 0) + report.get('cached', 0) == expected,
            'not all selected tests passed')
    require(all(report.get(k) == 0 for k in ('failed', 'skipped', 'unsupported')), 'incomplete test verdict')
    require(allow_cached or report.get('cached') == 0, 'forced qualification served cached verdicts')
    require(all(t['status'] in (('passed', 'cached') if allow_cached else ('passed',))
                for t in report['tests']), 'unexpected test status')


class Qualification:
    def __init__(self, compiler, zig, components, work, modes, release=False):
        self.compiler, self.zig, self.components = compiler, zig, components
        self.work, self.modes, self.release = work, modes, release
        self.calls = self.comparisons = self.deployment = 0
        self.sessions = 0
        self.receipt_warm = {}
        self.records = []
        self.phase = 'installed'
        self.empty_path = work / 'empty-path'
        self.empty_path.mkdir()
        self.source = work / 'source'
        copy_sources(self.source)
        (self.source / 'data.bin').write_bytes(b'a\x00b')
        # Increasing bytes and dense ASTs exercise whole-source transport, not
        # only a trivial main. Sizes are under the admitted lexer bound.
        (self.source / 'large_comments.my').write_bytes(
            (b'# UTF-8 ' + 'éλ'.encode() + b'\n') * 12000 + b'func main() -> int:\n    return 0\n')
        (self.source / 'large_nodes.my').write_text(
            ''.join(f'func f{i}() -> int:\n    return {i}\n\n' for i in range(700)) +
            'func main() -> int:\n    return f699() - 699\n')
        (self.source / 'invalid_utf8.my').write_bytes(b'func main() -> int:\n    # \xff\n    return 0\n')
        suffix = b'func main() -> int:\n    return 0\n'
        for name, body in profile_sources().items():
            (self.source / name).write_bytes(body)

    def run(self, mode, args, components=None, leakcheck=True):
        self.calls += 1
        env = environment(mode, components or self.components, self.empty_path)
        if not leakcheck:
            env['MYL_CORE_LEAKCHECK'] = '0'
        result = execute([self.compiler, *args],
                         env, self.work)
        return result

    def compare(self, name, args, expected=0):
        reference = self.run('reference', args)
        require(reference[0] == expected, f'{name}: wrong reference status {reference!r}')
        for mode in self.modes:
            actual = self.run(mode, args)
            require(actual == reference,
                    f'{name}/{mode}: frontend differs: reference={reference!r}, actual={actual!r}')
            self.comparisons += 1
        self.records.append({'workflow': name, 'phase': self.phase, 'status': reference[0],
                             'stdout_sha256': hashlib.sha256(reference[1]).hexdigest(),
                             'stderr_sha256': hashlib.sha256(reference[2]).hexdigest()})
        return reference

    def matrix(self):
        main = self.source / 'main.my'
        shutil.copyfile(FIXTURES / 'format.input', self.source / 'format.my')
        for command in ('check', 'check-project', 'list-declarations', 'list-modules', 'dump-syntax', 'dump-tokens', 'schema-project', 'list-interfaces'):
            self.compare(command, [command, main])
        self.compare('single-unit/check', ['check', self.source / 'standalone.my'])
        self.compare('dependencies', ['project-dependencies', main])
        self.compare('embed/format-hole', ['check', self.source / 'embedded.my'])
        navigation = self.compare('navigation/lexical-fallback', ['index-project', self.source / 'navigation.my', '--full'])
        require(b'lexical-only' in navigation[1], 'navigation did not exercise lexical fallback')
        self.compare('context/qualified', ['context', main, '--symbol=helper::value', '--format=json'])
        self.compare('context/dotted', ['context', main, '--symbol=helper.value', '--format=json'])
        self.compare('check-module', ['check-module', self.source / 'helper.my'])
        for source in ('malformed.my', 'type_error.my'):
            for command in ('check', 'check-project'):
                result = self.compare(f'{command}/{source}', [command, self.source / source, '--diagnostics=json'], 1)
                require(b'"kind":"diagnostic"' in result[2], 'source error lost diagnostics')
        helper = self.source / 'helper.my'
        original_helper = helper.read_bytes()
        try:
            for name, body in [('imported-syntax-error', b'    return 2 ** 3\n'),
                               ('imported-type-error', '    return "éλ"\n'.encode())]:
                helper.write_bytes(b'public func value() -> int:\n' + body)
                result = self.compare(name, ['check-project', main, '--diagnostics=json'], 1)
                require(b'"kind":"diagnostic"' in result[2] and b'helper.my' in result[2],
                        'imported source error lost dependency location')
        finally:
            helper.write_bytes(original_helper)
        # Lexical invalidity is classified by the reference on every run. It may
        # be accepted in comments; qualification asserts exact bytes either way.
        args = ['check', self.source / 'invalid_utf8.my', '--diagnostics=json']
        status = self.run('reference', args)[0]
        require(status in (0, 1), 'invalid UTF-8 reference produced a host failure')
        self.compare('invalid-utf8', args, status)
        for source in ('large_comments.my', 'large_nodes.my'):
            self.compare(source, ['check', self.source / source])
        self.compare('maximum-qualified-source', ['check', self.source / 'boundary.my'])
        for source in ('profile_comments.my', 'profile_dense.my', 'profile_nested.my'):
            self.compare(source, ['check', self.source / source])
        self.compare('profile-dense-tokens', ['dump-tokens', self.source / 'profile_dense.my'])
        self.compare('profile-dense-ast', ['dump-syntax', self.source / 'profile_dense.my'])
        formatted = self.source / 'format.my'
        original = formatted.read_bytes()
        outputs = []
        for mode in ('reference', *self.modes):
            formatted.write_bytes(original)
            result = self.run(mode, ['fmt', formatted])
            require(result[0] == 0 and not result[2], f'fmt/{mode} failed: {result!r}')
            outputs.append(result)
            require(outputs[-1] == outputs[0], f'fmt/{mode}: formatted bytes differ')
            formatted.write_bytes(result[1])
            self.run_check_fmt(mode, formatted)
        require(outputs[0][1] != original, 'fmt did not exercise a formatting edit')
        self.comparisons += len(self.modes)
        for mode in ('reference', *self.modes):
            cache = self.work / f'matrix-{mode}'
            output = self.work / 'program'
            build = ['build', main, '--project', '-o', output, '--cache-dir', cache, f'--zig={self.zig}']
            run = ['run-project', main, '--print-result', '--cache-dir', cache, f'--zig={self.zig}']
            tests = ['test', main, '--json', '--force', '--no-cache', f'--zig={self.zig}']
            if self.release:
                build += ['--release', '--verify-facts']
                run += ['--release', '--verify-facts']
                tests += ['--release', '--verify-facts']
            result = self.run(mode, build)
            require(result == (0, b'', b'') and output.is_file(), f'build/{mode} failed: {result!r}')
            native = execute([output], environment(mode, self.components, self.empty_path), self.work)
            require(native == (7, b'', b''), f'built artifact/{mode} has wrong behavior')
            require(self.run(mode, run) == (7, b'7\n', b''), f'run-project/{mode} differs')
            test_counts(self.run(mode, tests))
            self.comparisons += 3 if mode != 'reference' else 0
        return len(self.records) + 4

    def bounds(self):
        args = ['check', self.source / 'oversize.my']
        require(self.run('reference', args) == (0, b'', b''), 'oversize source is not reference-valid')
        for mode in self.modes:
            first = self.run(mode, args)
            require(first[0] == 2 and not first[1] and first[2], f'{mode}: oversize must be a bounded host failure')
            require(self.run(mode, args) == first, f'{mode}: oversize failure is nondeterministic')
        deep_args = ['check', self.source / 'profile_deep_malformed.my', '--diagnostics=json']
        reference = self.run('reference', deep_args)
        require(reference[0] == 1, 'deep malformed reference must reject as source error')
        deep = {}
        for mode in self.modes:
            first = self.run(mode, deep_args)
            require(first[0] in (1, 2) and (first[1] or first[2]), f'{mode}: deep malformed input escaped rejection')
            require(self.run(mode, deep_args) == first, f'{mode}: deep rejection is nondeterministic')
            if first[0] == 1:
                require(first == reference, f'{mode}: deep source diagnostics differ')
            else:
                require(not first[1] and first[2], f'{mode}: profile host failure published source output')
            deep[mode] = 'native diagnostic parity' if first[0] == 1 else 'explicit profile host rejection'
        return {'qualified_lexer_bytes': SOURCE_LIMIT, 'reference_valid_rejected_bytes': SOURCE_LIMIT + 1,
                'frontend_package_schema': 2, 'protocol': 1,
                'token_limit': 1048833, 'ast_value_limit': 1048576,
                'ast_node_table_limit': 262144, 'ast_statement_table_limit': 262144,
                'ast_edge_limit': 4194304, 'ast_depth_limit': 256,
                'ast_data_and_wire_bytes': 67108864,
                'workload_bytes': {name: len(body) for name, body in profile_sources().items()},
                'deep_malformed': deep,
                'default_adoption_limit': 'component source bound narrower than reference source acceptance'}

    def run_check_fmt(self, mode, path):
        result = self.run(mode, ['fmt', path, '--check'])
        require(result[0] == 0 and not result[2], f'fmt idempotence/{mode} failed')

    def warm_deployments(self):
        manifests = packages(self.components)
        main = self.source / 'main.my'
        private = self.work / 'deployment'
        for mode in self.modes:
            cache = self.work / f'warm-{mode}'
            commands = [
                ['build', main, '--project', '-o', self.work / 'warm-program', '--cache-dir', cache, f'--zig={self.zig}'],
                ['run-project', main, '--print-result', '--cache-dir', cache, f'--zig={self.zig}'],
                ['test', main, '--json', '--cache-dir', cache, f'--zig={self.zig}'],
            ]
            if self.release:
                for command in commands:
                    command += ['--release']
            for command in commands:
                restore_deployment(self.components, private)
                # A different mode has already published into this exact cache.
                # Subsequent frontend authentication cannot trust its verdict.
                native = self.run('reference', command, private, leakcheck=False)
                if command[0] == 'test':
                    test_counts(native, allow_cached=True)
                else:
                    require(native == ((7, b'7\n', b'') if command[0] == 'run-project' else (0, b'', b'')),
                            'reference cache priming failed')
                for _ in range(2):
                    result = self.run(mode, command, private, leakcheck=False)
                    if command[0] == 'test':
                        test_counts(result, allow_cached=True)
                    else:
                        require(result == ((7, b'7\n', b'') if command[0] == 'run-project' else (0, b'', b'')),
                                f'cannot prime {mode}/{command[0]} warm state: {result!r}')
                if command[0] == 'test':
                    receipt = json.loads(result[1])
                    require(receipt['cached'] == (2 if mode == 'component' else 0),
                            f'{mode}: warm test receipt behavior not demonstrated: {receipt!r}')
                    self.receipt_warm[mode] = {'passed': receipt['passed'], 'cached': receipt['cached']}
                for name in FRONTENDS:
                    for variant in ('missing-manifest', 'missing-artifact', 'schema', 'digest', 'replacement'):
                        # The path and every environment value remain exactly
                        # those used to publish the warm replay/receipt above.
                        restore_deployment(self.components, private)
                        manifest = dict(manifests[name])
                        manifest_path = private / f'{name}.json'
                        binary = private / manifest['artifact']
                        binary.chmod(0o700)
                        if variant == 'missing-manifest':
                            manifest_path.unlink()
                        elif variant == 'missing-artifact':
                            binary.unlink()
                        elif variant == 'schema':
                            manifest['schema'] += 1
                            manifest_path.write_text(json.dumps(manifest))
                        elif variant == 'digest':
                            with binary.open('ab') as file:
                                file.write(b'corruption')
                        else:
                            other = manifests['parser-pilot' if name == 'lexer-pilot' else 'lexer-pilot']
                            shutil.copyfile(self.components / other['artifact'], binary)
                            manifest['sha256'] = digest(binary)
                            manifest_path.write_text(json.dumps(manifest))
                        result = self.run(mode, command, private, leakcheck=False)
                        require(result[0] == 2 and not result[1] and result[2],
                                f'warm {mode}/{command[0]}/{name}/{variant} hid failure: {result!r}')
                        self.deployment += 1
        return self.deployment

    def live_sessions(self):
        # Keep one actual host process alive across deployment changes. Disk
        # replay qualification alone cannot exercise retained in-memory syntax.
        private = self.work / 'session-deployment'
        manifests = packages(self.components)
        for mode in self.modes:
            for name in FRONTENDS:
                for variant in ('missing', 'digest'):
                    if private.exists():
                        shutil.rmtree(private)
                    shutil.copytree(self.components, private)
                    env = environment(mode, private, self.empty_path)
                    with tempfile.TemporaryFile() as errors:
                        child = subprocess.Popen([str(self.compiler), 'check-session', str(self.source / 'main.my')],
                                                 cwd=self.work, env=env, stdin=subprocess.PIPE,
                                                 stdout=subprocess.PIPE, stderr=errors, bufsize=0)
                        self.calls += 1
                        try:
                            require(session_command(child, 'check').get('status') == 0, 'session first check failed')
                            require(session_command(child, 'check').get('status') == 0, 'session warm check failed')
                            if variant == 'missing':
                                (private / f'{name}.json').unlink()
                            else:
                                artifact = private / manifests[name]['artifact']
                                artifact.chmod(0o700)
                                with artifact.open('ab') as file:
                                    file.write(b'corruption')
                            actual = session_command(child, 'check')
                            require(actual.get('status') == 2,
                                    f'live session {mode}/{name}/{variant} hid retained-state failure: {actual!r}')
                            require(session_command(child, 'quit').get('status') == 0, 'session did not survive host failure')
                            require(child.wait(timeout=30) == 0, 'session host exit failed')
                        finally:
                            if child.poll() is None:
                                child.kill()
                                child.wait()
                            child.stdin.close()
                            child.stdout.close()
                    self.sessions += 1
        return self.sessions


def restore_deployment(source, target):
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target)


def session_command(child, command):
    child.stdin.write((command + '\n').encode())
    child.stdin.flush()
    deadline = time.monotonic() + 35
    result = bytearray()
    with selectors.DefaultSelector() as selected:
        selected.register(child.stdout, selectors.EVENT_READ)
        while not result.endswith(b'\n'):
            remaining = deadline - time.monotonic()
            require(remaining > 0 and selected.select(remaining), 'session reply timeout')
            chunk = os.read(child.stdout.fileno(), 4096)
            require(chunk, 'session exited before reply')
            result.extend(chunk)
            require(len(result) <= 1048576, 'session reply exceeded bound')
    value = json.loads(result)
    require(value.get('version') == 'check-session-v1', 'unexpected session reply schema')
    return value


def coordinator_edit(args, qualification):
    work = qualification.work / 'coordinator-edit'
    root = work / 'source'
    (root / 'selfhost').mkdir(parents=True)
    shutil.copyfile(args.source_root / 'selfhost/component-seed.json', root / 'selfhost/component-seed.json')
    shutil.copytree(args.source_root / 'selfhost/components', root / 'selfhost/components', symlinks=True)
    installation = work / 'installation'
    command = [args.builder, '--root', root, '--zig', args.zig, '--install-dir', installation]
    env = dict(os.environ, MYLANG_LEXER_MODE='reference', MYLANG_PARSER_MODE='reference')
    host_before = digest(args.compiler)
    require(execute(command, env, work, 600)[0] == 0, 'coordinator baseline private install failed')
    before = packages(installation)
    edited = root / 'selfhost/components/parser_pilot/full_resource.my'
    text = edited.read_text()
    needle = '    mut count = 1\n'
    require(text.count(needle) == 1, 'coordinator implementation edit marker ambiguous')
    edited.write_text(text.replace(needle, needle +
                     '    if tag == "pilot_edit_marker":\n        return Signature(typed=False, owner=False, arguments=0, variadic=False)\n'))
    result = execute(command, env, work, 600)
    require(result[0] == 0, f'coordinator edit rebuild failed: {result!r}')
    after = packages(installation)
    require(before['parser-pilot']['key'] != after['parser-pilot']['key'] and
            before['parser-pilot']['sha256'] != after['parser-pilot']['sha256'],
            'coordinator implementation edit did not change parser identity and artifact')
    require(all(before[n] == after[n] for n in PACKAGES if n != 'parser-pilot'),
            'parser-only edit rebuilt unrelated package identities')
    original = qualification.components
    qualification.components = installation
    qualification.phase = 'coordinator-edit'
    qualification.matrix()
    qualification.phase = 'installed'
    qualification.components = original
    require(digest(args.compiler) == host_before, 'component-only coordinator rebuild changed host')
    return {'host_sha256': host_before, 'before': before['parser-pilot'], 'after': after['parser-pilot']}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--compiler', type=Path, default=ROOT / 'zig-out/bin/mylang')
    ap.add_argument('--builder', type=Path, default=ROOT / 'zig-out/tools/selka-components')
    ap.add_argument('--component-dir', type=Path, default=ROOT / 'zig-out/libexec/mylang/components')
    ap.add_argument('--source-root', type=Path, default=ROOT)
    ap.add_argument('--zig', type=Path, required=True)
    ap.add_argument('--release', action='store_true')
    ap.add_argument('--component', action='store_true', help='require component-only mode, never skip if absent')
    ap.add_argument('--edit-check', action='store_true')
    ap.add_argument('--report', type=Path)
    args = ap.parse_args()
    for key in ('compiler', 'builder', 'component_dir', 'source_root', 'zig'):
        setattr(args, key, getattr(args, key).resolve())
    packages(args.component_dir)
    code, out, err = execute([args.builder, '--root', args.source_root, '--zig', args.zig, '--seed-only'],
                             dict(os.environ), args.source_root, 600)
    require(code == 0, f'qualified seed receipt verification failed: {err!r}')
    seed = Path(out.decode().strip().splitlines()[-1])
    require(seed.is_file(), 'coordinator omitted qualified seed')
    host_before = digest(args.compiler)
    modes = ['shadow'] + (['component'] if args.component else [])
    with tempfile.TemporaryDirectory(prefix='frontend-qualification-') as temporary:
        q = Qualification(args.compiler, args.zig, args.component_dir, Path(temporary), modes, args.release)
        workflows = q.matrix()
        profile_limits = q.bounds()
        q.warm_deployments()
        q.live_sessions()
        edit = coordinator_edit(args, q) if args.edit_check else None
        report = {'host_sha256': host_before, 'seed_sha256': digest(seed),
                  'packages': packages(args.component_dir), 'modes': modes,
                  'release_facts_leaks': args.release, 'workflows': workflows,
                  'comparisons': q.comparisons, 'host_invocations': q.calls,
                  'warm_deployment_checks': q.deployment, 'records': q.records,
                  'live_session_checks': q.sessions,
                  'cache_enabled_test_receipts': q.receipt_warm,
                  'coordinator_edit': edit, 'failed': 0, 'skipped': 0}
        report['profile_limits'] = profile_limits
        report['qualification_address_space_budget_bytes'] = ADDRESS_SPACE_BUDGET
        report['children_peak_rss_kib'] = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
        report['rss_scope'] = 'cumulative child high-water for entire qualification, not per producer; address-space ceiling inherited by descendants'
    require(digest(args.compiler) == host_before, 'qualification changed installed host')
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(f'frontend qualification: {workflows} workflows, {report["comparisons"]} comparisons, '
          f'{report["warm_deployment_checks"]} warm deployment checks, {report["live_session_checks"]} live session checks; 0 failed, 0 skipped')
    print(f'host SHA256 {host_before}; verified seed SHA256 {report["seed_sha256"]}')
    print('runtime commands used empty PATH and explicit native Zig; no runtime Python required')
    print(f'cache-enabled warm test receipts: {json.dumps(report["cache_enabled_test_receipts"], sort_keys=True)}; fact/leak qualification remains in regular matrix')
    if edit:
        print('native coordinator implementation edit: changed parser key/artifact, unrelated packages and host unchanged')


if __name__ == '__main__':
    main()
