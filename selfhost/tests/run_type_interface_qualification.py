#!/usr/bin/env python3
"""Installed type-interface workflow qualification; native coordinator only."""
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
FIXTURES = Path(__file__).with_name('fixtures') / 'type_interface'
COMPONENT = 'type-interface'


def frame(payload):
    identity = b'tyiftest' + F.hashlib.sha256(payload).digest()
    return b'SLKTIF01' + struct.pack('<IIII', 1, 1, 0, len(payload)) + identity + payload


def blob(value):
    return struct.pack('<I', len(value)) + value


def coordinator_environment():
    return {key: value for key, value in os.environ.items()
            if not key.startswith(('MYLANG_', 'PILOT_')) or key == 'MYLANG_COMPONENT_CACHE'}


def transport(binary, work, env):
    context = struct.pack('<I', 0) + blob(b'input') + blob(b'input.my') + struct.pack('<II', 0, 0) + blob(b'')
    payload = b'SLKTYI01' + struct.pack('<III', 1, 0, 1) + context + struct.pack('<' + 'I' * 14, *([0] * 14))
    valid = frame(payload)
    request = work / 'type-interface-exchange.bin'
    request.write_bytes(valid)
    status, stdout, stderr = F.execute([binary, '--exchange', request], env, work, 15)
    F.require(status == 0 and not stderr, 'valid type-interface exchange failed')
    F.require(stdout[:8] == b'SLKTIF01' and stdout[24:64] == valid[24:64] and
              struct.unpack('<IIII', stdout[8:24]) == (1, 1, 1, len(stdout)-64), 'unbound type-interface reply')
    F.require(stdout[64:] == b'SLKTYR01' + struct.pack('<IIIIII', 0, 1, 0, 1, 0, 0), 'empty catalog batch reply differs')
    malformed = [b'', valid[:63], valid[:-1], valid + b'X', b'BADMAGIC' + valid[8:],
                 frame(b'BADMAGIC' + payload[8:]),
                 valid[:8] + struct.pack('<I', 2) + valid[12:],
                 valid[:12] + struct.pack('<I', 2) + valid[16:],
                 valid[:16] + struct.pack('<I', 1) + valid[20:],
                 valid[:20] + struct.pack('<I', 67108864) + valid[24:]]
    for offset, value in ((8,4097),(12,1),(16,4097),(20,1)):
        changed=bytearray(payload);struct.pack_into('<I',changed,offset,value);malformed.append(frame(changed))
    # Each admitted slice has a distinct bound and must reject before reading rows.
    for position in range(14):
        changed=bytearray(payload)
        struct.pack_into('<I',changed,len(payload)-56+4*position,4097 if position==0 else 65537)
        malformed.append(frame(changed))
    for name,path,source in ((b'input',b'x'*16385,b''),(b'input',b'input.my',b' '*1048577),(b'x'*8388609,b'input.my',b'')):
        oversized=struct.pack('<I',0)+blob(name)+blob(path)+struct.pack('<II',0,0)+blob(source)
        malformed.append(frame(b'SLKTYI01'+struct.pack('<III',1,0,1)+oversized+struct.pack('<'+'I'*14,*([0]*14))))
    for index,value in enumerate(malformed):
        request.write_bytes(value)
        status,stdout,stderr=F.execute([binary,'--exchange',request],env,work,15)
        F.require(status==2 and not stdout and stderr, f'malformed type-interface request {index} escaped refusal')
    return {'valid':1,'malformed':len(malformed),'failed':0,'skipped':0}


def environment(mode, components, empty):
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('PILOT_', 'MYLANG_'))}
    env.update(PATH=str(empty), MYLANG_COMPONENT_DIR=str(components),
               MYLANG_LEXER_MODE='reference', MYLANG_PARSER_MODE='reference',
               MYLANG_DECLARATION_MODE='reference', MYLANG_TYPE_INTERFACE_MODE=mode, MYLANG_TEST_INDEX_MODE='reference',
               MYLANG_CACHE_PLAN_MODE='reference', MYL_CORE_LEAKCHECK='1')
    return env


def packages(directory):
    result = {}
    versions = {'test-index': (1, 1), 'cache-plan': (2, 2),
                'lexer-pilot': (1, 2), 'parser-pilot': (1, 2), 'declaration-index': (1, 1), COMPONENT: (1, 1)}
    for name, (protocol, schema) in versions.items():
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
def type_interface_boundary():
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
            env.update(MYLANG_LEXER_MODE=mode, MYLANG_PARSER_MODE=mode, MYLANG_DECLARATION_MODE=mode)
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
                        F.require(F.session_command(child, 'check').get('status') == 2, 'live type_interface mutation hid host failure')
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
        F.require(len(manifest) >= 20, 'empty/incomplete type_interface fixture selection')
        for name, spec in manifest.items():
            F.require(spec['status'] in (0, 1), 'unsupported fixture verdict')
            result = self.compare(name, ['check-project', self.source / name, '--diagnostics=json'], spec['status'])
            self.records[-1]['boundary'] = spec.get('boundary', 'type_interface or native consumer')
            if 'code' in spec:
                diagnostics = [json.loads(line)['diagnostic'] for line in result[2].splitlines()]
                F.require(any(value['code'] == spec['code'] for value in diagnostics), 'expected type_interface diagnostic missing')
            if spec.get('interfaces'):
                self.compare(name + '-interfaces', ['list-interfaces', self.source / name])
        for entry in ('test_index/main.my', 'cache_plan/main.my', 'lexer_pilot/main.my',
                      'parser_pilot/full_adapter.my', 'declaration_index/main.my', 'type_interface/main.my'):
            source = ROOT / 'selfhost/components' / entry
            F.require(source.is_file(), 'missing installed component entry source')
            self.compare('component-source-' + entry, ['check', source, '--diagnostics=json'])
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
    path = source / 'selfhost/components/type_interface/checking.my'
    marker = 'public func check(request: model.Request) -> model.Outcome fails model.Problem:\n'
    text = path.read_text()
    F.require(text.count(marker) == 1, 'type_interface implementation edit hook missing/ambiguous')
    path.write_text(text.replace(marker, marker + '    if len(request.modules) > 0 and request.modules[0].context.name == b"type_interface_edit_marker":\n        fail model.Problem(code="P_EDIT", message="private qualification edit", site=model.absent_site(), related=model.absent_site())\n'))
    F.require(F.execute(command, env, q.work, 600)[0] == 0, 'private type_interface rebuild failed')
    after = packages(installation)
    F.require(before[COMPONENT]['key'] != after[COMPONENT]['key'] and
              before[COMPONENT]['sha256'] != after[COMPONENT]['sha256'], 'implementation edit did not rebuild type_interface artifact')
    F.require(all(before[name] == after[name] for name in before if name != COMPONENT), 'unrelated packages changed')
    q.components, q.phase = installation, 'coordinator-edit'
    q.matrix()
    return {'before': before[COMPONENT], 'after': after[COMPONENT], 'other_packages_unchanged': 5}


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
                      f'{mode}: forged type_interface reply case {case} escaped host rejection: {result!r}')
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
    with tempfile.TemporaryDirectory(prefix='type_interface-qualification-') as temporary, type_interface_boundary():
        q = Qualification(args.compiler, args.zig, args.component_dir, Path(temporary), ['shadow', 'component'], args.release)
        for source in FIXTURES.rglob('*.input'):
            target = q.source / source.relative_to(FIXTURES).with_suffix('.my')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
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
    print(f'type_interface qualification: {workflows} workflows, {q.comparisons} comparisons, {q.deployment} warm deployment checks, {q.sessions} live session checks; 0 failed, 0 skipped')
    print(f'type_interface transport: {protocol["valid"]} valid, {protocol["malformed"]} malformed; 0 failed, 0 skipped')
    print(f'type_interface forged replies: {forged} rejected; 0 failed, 0 skipped')


if __name__ == '__main__':
    main()
