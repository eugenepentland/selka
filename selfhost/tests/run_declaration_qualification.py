#!/usr/bin/env python3
"""Installed declaration-index workflow qualification; native coordinator only."""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import run_frontend_qualification as F

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).with_name('fixtures') / 'declaration_index'
COMPONENT = 'declaration-index'


def frame(payload):
    identity = b'decltest' + F.hashlib.sha256(payload).digest()
    return b'SLKDIX01' + struct.pack('<IIII', 1, 1, 0, len(payload)) + identity + payload


def blob(value):
    return struct.pack('<I', len(value)) + value


def coordinator_environment():
    return {key: value for key, value in os.environ.items()
            if not key.startswith(('MYLANG_', 'PILOT_')) or key == 'MYLANG_COMPONENT_CACHE'}


def transport(binary, work, env):
    payload = (b'SLKDCL01' + struct.pack('<II', 0, 0) + blob(b'input') +
               blob(b'input.my') + struct.pack('<I', 0) + blob(b'') + struct.pack('<IIIII', 0, 0, 0, 0, 0))
    valid = frame(payload)
    request = work / 'declaration-exchange.bin'
    request.write_bytes(valid)
    result = F.execute([binary, '--exchange', request], env, work, 15)
    F.require(result[0] == 0 and not result[2], 'valid declaration exchange failed')
    reply = result[1]
    F.require(len(reply) >= 84 and reply[:8] == b'SLKDIX01' and
              struct.unpack('<IIII', reply[8:24]) == (1, 1, 1, len(reply) - 64) and
              reply[24:64] == valid[24:64] and reply[64:72] == b'SLKDCR01', 'unbound declaration reply')
    F.require(reply[72:] == struct.pack('<III', 0, 0, 0), 'empty module declaration reply is not empty/successful')
    malformed = [b'', valid[:63], valid[:-1], valid + b'X',
                 b'BADMAGIC' + valid[8:], frame(b'BADMAGIC' + payload[8:]),
                 valid[:8] + struct.pack('<I', 2) + valid[12:],
                 valid[:12] + struct.pack('<I', 2) + valid[16:],
                 valid[:16] + struct.pack('<I', 1) + valid[20:],
                 valid[:20] + struct.pack('<I', 33554432) + valid[24:],
                 frame(payload[:12] + struct.pack('<I', 2) + payload[16:])]
    for position, count in enumerate((65537, 4097, 65537, 65537, 4097)):
        changed = bytearray(payload)
        struct.pack_into('<I', changed, len(payload) - 20 + position * 4, count)
        malformed.append(frame(changed))
    for name, path, source in ((b'input', b'x' * 16385, b''),
                               (b'input', b'input.my', b' ' * 1048577),
                               (b'x' * 1048577, b'input.my', b'')):
        malformed.append(frame(b'SLKDCL01' + struct.pack('<II', 0, 0) + blob(name) +
                               blob(path) + struct.pack('<I', 0) + blob(source) + struct.pack('<IIIII', 0, 0, 0, 0, 0)))
    for index, value in enumerate(malformed):
        request.write_bytes(value)
        status, stdout, stderr = F.execute([binary, '--exchange', request], env, work, 15)
        F.require(status == 2 and not stdout and stderr, f'malformed declaration request {index} escaped refusal')
    return {'valid': 1, 'malformed': len(malformed), 'failed': 0, 'skipped': 0}


def environment(mode, components, empty):
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('PILOT_', 'MYLANG_'))}
    env.update(PATH=str(empty), MYLANG_COMPONENT_DIR=str(components),
               MYLANG_LEXER_MODE='reference', MYLANG_PARSER_MODE='reference',
               MYLANG_TYPE_INTERFACE_MODE='reference', MYLANG_BODY_CHECK_MODE='reference', MYLANG_DECLARATION_MODE=mode, MYLANG_TEST_INDEX_MODE='reference',
               MYLANG_CACHE_PLAN_MODE='reference', MYL_CORE_LEAKCHECK='1')
    return env


def packages(directory, include_declaration=True, include_type_interface=True, include_body=True):
    result = {}
    versions = {'test-index': (1, 1), 'cache-plan': (2, 2),
                'lexer-pilot': (1, 2), 'parser-pilot': (1, 2), COMPONENT: (1, 1), 'type-interface': (1, 1), 'body-check': (1, 4)}
    for name, (protocol, schema) in versions.items():
        if name == 'body-check' and not include_body:
            continue  # Explicit historical package inventory.
        if name == 'type-interface' and not include_type_interface:
            continue  # Explicit historical measurement package inventory.
        if name == COMPONENT and not include_declaration:
            continue  # Explicit frozen pre-boundary measurement profile only.
        value = json.loads((directory / f'{name}.json').read_text())
        F.require(all(type(value.get(k)) is int for k in ('format', 'protocol', 'schema')), 'noninteger package identity')
        F.require(all(value.get(k) == v for k, v in
                      {'format': 1, 'component': name, 'protocol': protocol, 'schema': schema}.items()),
                  f'{name}: invalid qualified identity')
        artifact = value.get('artifact', '')
        F.require(artifact and Path(artifact).name == artifact and artifact not in ('.', '..'), 'unsafe artifact')
        F.require(F.digest(directory / artifact) == value.get('sha256'), 'artifact digest mismatch')
        result[name] = value
    return result


@contextmanager
def declaration_boundary():
    # Reuse the established same-path warm/live algorithms with one explicitly
    # selected boundary, restoring imported helpers even when a check fails.
    previous = F.FRONTENDS, F.environment, F.packages
    F.FRONTENDS, F.environment, F.packages = (COMPONENT,), environment, packages
    try:
        yield
    finally:
        F.FRONTENDS, F.environment, F.packages = previous


class Qualification(F.Qualification):
    mixed = False

    def run(self, mode, args, components=None, leakcheck=True):
        self.calls += 1
        env = environment(mode, components or self.components, self.empty_path)
        if self.mixed:
            env.update(MYLANG_LEXER_MODE=mode, MYLANG_PARSER_MODE=mode)
        if not leakcheck:
            env['MYL_CORE_LEAKCHECK'] = '0'
        return F.execute([self.compiler, *args], env, self.work)

    def compare(self, name, args, expected=0):
        reference = super().compare(name, args, expected)
        for mode in ('reference', *self.modes):
            F.require(self.run(mode, args) == reference, f'{name}/{mode}: ordering or diagnostics are nondeterministic')
        return reference

    def live_sessions(self):
        private = self.work / 'session-deployment'
        manifests = packages(self.components)
        for mode in self.modes:
            for variant in ('missing', 'digest'):
                F.restore_deployment(self.components, private)
                with tempfile.TemporaryFile() as errors:
                    child = subprocess.Popen([str(self.compiler), 'check-session', str(self.source / 'main.my')],
                                             cwd=self.work, env=environment(mode, private, self.empty_path),
                                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors,
                                             bufsize=0, preexec_fn=F.process_limits)
                    self.calls += 1
                    try:
                        for _ in range(2):
                            F.require(F.session_command(child, 'check').get('status') == 0, 'warm live check failed')
                        if variant == 'missing':
                            (private / f'{COMPONENT}.json').unlink()
                        else:
                            artifact = private / manifests[COMPONENT]['artifact']
                            artifact.chmod(0o700)
                            with artifact.open('ab') as file:
                                file.write(b'corruption')
                        F.require(F.session_command(child, 'check').get('status') == 2, 'live declaration mutation hid host failure')
                        F.require(F.session_command(child, 'quit').get('status') == 0, 'session did not survive failure')
                        F.require(child.wait(timeout=30) == 0, 'session exit failed')
                    finally:
                        if child.poll() is None:
                            child.kill()
                            child.wait()
                        child.stdin.close()
                        child.stdout.close()
                self.sessions += 1
        return self.sessions

    def matrix(self):
        main = self.source / 'main.my'
        for command in ('check', 'check-project', 'list-declarations', 'list-modules',
                        'schema-project', 'list-interfaces'):
            self.compare(command, [command, main])
        manifest = json.loads((FIXTURES / 'manifest.json').read_text())
        F.require(len(manifest) >= 15, 'empty/incomplete declaration fixture selection')
        for name, spec in manifest.items():
            F.require(spec['status'] in (0, 1), 'unsupported fixture verdict')
            result = self.compare(name, ['check-project', self.source / name, '--diagnostics=json'], spec['status'])
            self.records[-1]['boundary'] = spec.get('boundary', 'declaration or native consumer')
            if 'code' in spec:
                diagnostics = [json.loads(line)['diagnostic'] for line in result[2].splitlines()]
                F.require(any(value['code'] == spec['code'] for value in diagnostics), 'expected declaration diagnostic missing')
            if spec.get('interfaces'):
                self.compare(name + '-interfaces', ['list-interfaces', self.source / name])
        helper = self.source / 'helper.my'
        original = helper.read_bytes()
        replacement = original.replace(b'public func value(', b'public func renamed(')
        F.require(replacement != original, 'source edit marker missing')
        try:
            helper.write_bytes(replacement)
            self.compare('interface-source-edit', ['check-project', main, '--diagnostics=json'], 1)
        finally:
            helper.write_bytes(original)
        self.compare('interface-source-restored', ['check-project', main])
        self.mixed = True
        try:
            for command in ('check-project', 'list-interfaces', 'schema-project'):
                self.compare('mixed-' + command, [command, main])
        finally:
            self.mixed = False
        for mode in ('reference', *self.modes):
            cache = self.work / f'application-{mode}'
            common = ['--cache-dir', cache, f'--zig={self.zig}']
            flags = ['--release', '--verify-facts'] if self.release else []
            output = self.work / 'program'
            F.require(self.run(mode, ['build', main, '--project', '-o', output, *common, *flags]) == (0, b'', b''), 'build failed')
            F.require(F.execute([output], environment(mode, self.components, self.empty_path), self.work) == (7, b'', b''), 'native artifact differs')
            F.require(self.run(mode, ['run-project', main, '--print-result', *common, *flags]) == (7, b'7\n', b''), 'run differs')
            F.test_counts(self.run(mode, ['test', main, '--json', '--force', '--no-cache', f'--zig={self.zig}', *flags]))
            self.comparisons += 3 if mode != 'reference' else 0
        return len(self.records) + 3


def coordinator_edit(args, q):
    source = q.work / 'coordinator-source'
    (source / 'selfhost').mkdir(parents=True)
    shutil.copyfile(ROOT / 'selfhost/component-seed.json', source / 'selfhost/component-seed.json')
    shutil.copytree(ROOT / 'selfhost/components', source / 'selfhost/components', symlinks=True)
    installation = q.work / 'coordinator-install'
    command = [args.builder, '--root', source, '--zig', args.zig, '--install-dir', installation]
    env = coordinator_environment()
    F.require(F.execute(command, env, q.work, 600)[0] == 0, 'private coordinator initial install failed')
    before = packages(installation)
    path = source / 'selfhost/components/declaration_index/indexing.my'
    marker = 'public func index(request: model.Request) -> model.Outcome fails indexed.Problem:\n'
    text = path.read_text()
    F.require(text.count(marker) == 1, 'declaration implementation edit hook missing/ambiguous')
    path.write_text(text.replace(marker, marker + '    if request.context.name == b"declaration_edit_marker":\n        fail indexed.Problem(code="P_EDIT", message="private qualification edit")\n'))
    F.require(F.execute(command, env, q.work, 600)[0] == 0, 'private declaration rebuild failed')
    after = packages(installation)
    F.require(before[COMPONENT]['key'] != after[COMPONENT]['key'] and
              before[COMPONENT]['sha256'] != after[COMPONENT]['sha256'], 'implementation edit did not rebuild declaration artifact')
    F.require(all(before[name] == after[name] for name in before if name != COMPONENT), 'unrelated packages changed')
    q.components, q.phase = installation, 'coordinator-edit'
    q.matrix()
    return {'before': before[COMPONENT], 'after': after[COMPONENT], 'other_packages_unchanged': 6}


def forged_replies(args, q):
    private = q.work / 'forged-deployment'
    checked = 0
    for case in range(4):
        binary = q.work / f'forged-reply-{case}'
        compile_result = F.execute([args.zig, 'cc', FIXTURES / 'forged_reply.c', '-O2',
                                    f'-DFORGE_CASE={case}', '-o', binary],
                                   coordinator_environment(), q.work, 180)
        F.require(compile_result[0] == 0, 'native hostile-reply fixture compilation failed')
        F.restore_deployment(args.component_dir, private)
        manifest_path = private / f'{COMPONENT}.json'
        manifest = json.loads(manifest_path.read_text())
        artifact = private / manifest['artifact']
        artifact.chmod(0o700)
        shutil.copyfile(binary, artifact)
        manifest['sha256'] = F.digest(artifact)
        manifest_path.write_text(json.dumps(manifest))
        packages(private)  # Authentication passes; returned facts must fail.
        for mode in q.modes:
            result = q.run(mode, ['check-project', q.source / 'main.my'], private)
            F.require(result[0] == 2 and not result[1] and result[2],
                      f'{mode}: forged declaration reply case {case} escaped host rejection: {result!r}')
            checked += 1
    return checked


def main():
    ap = argparse.ArgumentParser()
    for name in ('compiler', 'builder', 'component-dir', 'zig'):
        ap.add_argument('--' + name, type=Path, required=True)
    ap.add_argument('--release', action='store_true')
    ap.add_argument('--edit-check', action='store_true')
    ap.add_argument('--report', type=Path)
    args = ap.parse_args()
    for name in ('compiler', 'builder', 'component_dir', 'zig'):
        setattr(args, name, getattr(args, name).resolve())
    manifests = packages(args.component_dir)
    seed_check = F.execute([args.builder, '--root', ROOT, '--zig', args.zig, '--seed-only'], coordinator_environment(), ROOT, 600)
    F.require(seed_check[0] == 0, 'qualified seed receipt verification failed')
    seed_lines = seed_check[1].decode().strip().splitlines()
    F.require(len(seed_lines) == 1 and Path(seed_lines[0]).is_file(), 'missing/ambiguous qualified seed executable')
    seed_sha256 = F.digest(Path(seed_lines[0]))
    host = F.digest(args.compiler)
    with tempfile.TemporaryDirectory(prefix='declaration-qualification-') as temporary, declaration_boundary():
        q = Qualification(args.compiler, args.zig, args.component_dir, Path(temporary), ['shadow', 'component'], args.release)
        for source in FIXTURES.glob('*.input'):
            shutil.copyfile(source, q.source / source.with_suffix('.my').name)
        workflows = q.matrix()
        q.warm_deployments()
        q.live_sessions()
        protocol = transport(args.component_dir / manifests[COMPONENT]['artifact'], q.work,
                             environment('component', args.component_dir, q.empty_path))
        forged = forged_replies(args, q)
        edit = coordinator_edit(args, q) if args.edit_check else None
        report = {'host_sha256': host, 'packages': manifests, 'workflows': workflows,
                  'verified_seed_sha256': seed_sha256, 'release_facts_leaks': args.release,
                  'comparisons': q.comparisons, 'warm_deployment_checks': q.deployment,
                  'live_session_checks': q.sessions, 'cache_enabled_test_receipts': q.receipt_warm,
                  'records': q.records, 'failed': 0, 'skipped': 0}
        report['transport'] = protocol
        report['forged_reply_checks'] = forged
        report['coordinator_edit'] = edit
    F.require(F.digest(args.compiler) == host and packages(args.component_dir) == manifests, 'installed inputs changed')
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(f'declaration qualification: {workflows} workflows, {q.comparisons} comparisons, {q.deployment} warm deployment checks, {q.sessions} live session checks; 0 failed, 0 skipped')
    print(f'declaration transport: {protocol["valid"]} valid, {protocol["malformed"]} malformed; 0 failed, 0 skipped')
    print(f'declaration forged replies: {forged} rejected; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
