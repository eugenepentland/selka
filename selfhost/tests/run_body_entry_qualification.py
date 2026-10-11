#!/usr/bin/env python3
"""B7 preparation: real entry-source compilation, not a compiler bootstrap claim."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import tempfile
import run_body_check_qualification as D

F = D.F
SCHEMA = 7
FIXTURES = Path(__file__).with_name('fixtures') / 'body_entry_candidate'
ENTRIES = {
    'test-index': 'test_index/main.my', 'cache-plan': 'cache_plan/main.my',
    'lexer-pilot': 'lexer_pilot/main.my', 'parser-pilot': 'parser_pilot/full_adapter.my',
    'declaration-index': 'declaration_index/main.my', 'type-interface': 'type_interface/main.my',
    'body-check': 'body_check/main.my',
}
EXPECTED_OPERATIONS = 349


def require(value, message):
    F.require(value, message)


def manifest():
    value = json.loads((FIXTURES / 'manifest.json').read_text())
    cases = value['cases']
    require(value['schema'] == SCHEMA and len(cases) == 24, 'incomplete B7 fixture selection')
    require({name for name in cases} == {p.with_suffix('.my').name for p in FIXTURES.glob('*.input')}, 'unselected/missing B7 fixture')
    require([sum(s['class'] == kind for s in cases.values()) for kind in ('success', 'diagnostic', 'profile')] == [14, 8, 2], 'B7 classes changed')
    for name, spec in cases.items():
        require(spec['source'] == str(Path(name).with_suffix('.input')), 'B7 source/name association changed')
        require(type(spec['native_status']) is int and type(spec['selected_status']) is int, 'noninteger verdict')
        require(spec['native_status'] == (1 if spec['class'] == 'diagnostic' else 0), 'invalid native verdict')
        require(spec['selected_status'] == (2 if spec['class'] == 'profile' else spec['native_status']), 'invalid selected verdict')
        require(F.digest(FIXTURES / spec['source']) == spec['source_sha256'], 'B7 source changed: ' + name)
    require(set(value['donors']) == {'helper.my'}, 'B7 donor inventory changed')
    require(F.digest(FIXTURES / 'helper.my') == value['donors']['helper.my'], 'B7 donor changed')
    return value


def source_identity(root):
    components = root / 'selfhost/components'
    result = {str(p.relative_to(root)): F.digest(p) for p in sorted(components.rglob('*'))
              if p.is_file() and not any(part.startswith('.') or part == '__pycache__' for part in p.relative_to(components).parts)}
    result['selfhost/component-seed.json'] = F.digest(root / 'selfhost/component-seed.json')
    require(all('selfhost/components/' + name in result for name in ENTRIES.values()), 'missing actual entry source')
    return result


def request_inventory(directory):
    inventory = json.loads((directory / 'requests.json').read_text())
    require(inventory.get('schema') == 1 and set(inventory.get('packages', {})) == set(ENTRIES), 'seven authentic requests required')
    for name, spec in inventory['packages'].items():
        path = Path(spec['file'])
        require(not path.is_absolute() and '..' not in path.parts and spec['arguments'] in (['--request'], ['--exchange']), 'unsafe replay request')
        require(F.digest(directory / path) == spec['sha256'] and (directory / path).stat().st_size > 0, 'changed/empty authentic request: ' + name)
        require(spec.get('provenance') == 'authentic-native-request', 'synthetic request cannot stand for entry generation')
    return inventory


def bound_capture(request, reply):
    for data, direction, magic in ((request, 0, b'SLKBKI01'), (reply, 1, b'SLKBKR01')):
        require(80 <= len(data) <= 67108864 and data[:8] == b'SLKBCK01', 'missing/bounded body exchange')
        import struct
        require(struct.unpack('<IIII', data[8:24]) == (1, SCHEMA, direction, len(data)-64), 'wrong captured body frame')
        require(data[64:72] == magic, 'wrong captured body graph')
        count, root = struct.unpack('<II', data[72:80])
        require(0 < count <= 2097152 and root < count, 'captured body table exceeded profile')
    require(request[32:64] == hashlib.sha256(request[64:]).digest() and request[24:64] == reply[24:64], 'unbound body capture')
    return {'request_sha256': hashlib.sha256(request).hexdigest(), 'reply_sha256': hashlib.sha256(reply).hexdigest(),
            'request_bytes': len(request), 'reply_bytes': len(reply), 'request_values': int.from_bytes(request[72:76], 'little')}



def require_capture_inventory(captures):
    expected = {(name + phase, mode) for name in ENTRIES
                for phase, modes in (('-source-check', ('shadow', 'component')),
                                     ('-generation1', ('shadow', 'component')),
                                     ('-generation2', ('component',))) for mode in modes}
    actual = [(capture['phase'], capture['mode']) for capture in captures]
    require(len(actual) == 35 and len(set(actual)) == 35 and set(actual) == expected,
            'incomplete/duplicate actual entry capture inventory')


def retained_capture(work, ordinal, request, reply):
    paths = {}
    for name, payload in (('request', request), ('reply', reply)):
        path = work / ('capture-' + str(ordinal).zfill(2) + '-' + name + '.bin.gz')
        with path.open('xb') as stream:
            with gzip.GzipFile(filename='', mode='wb', fileobj=stream, mtime=0, compresslevel=1) as compressed:
                compressed.write(payload)
        paths[name + '_path'] = str(path)
        paths[name + '_archive_sha256'] = F.digest(path)
    return paths


def descriptor_limit():
    F.process_limits()
    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    resource.setrlimit(resource.RLIMIT_NOFILE, (32 if soft == resource.RLIM_INFINITY else min(soft, 32), hard))


def guest(binary, arguments, env, cwd, limit=False):
    # Descriptor limits apply only to the generated guest, never its toolchain.
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        process = subprocess.run([str(binary), *map(str, arguments)], cwd=cwd, env=env,
                                 stdout=out, stderr=err, timeout=60,
                                 preexec_fn=descriptor_limit if limit else F.process_limits)
        out.seek(0); err.seek(0)
        stdout, stderr = out.read(F.OUTPUT_LIMIT + 1), err.read(F.OUTPUT_LIMIT + 1)
    require(len(stdout) <= F.OUTPUT_LIMIT and len(stderr) <= F.OUTPUT_LIMIT, 'unbounded generated output')
    return process.returncode, stdout, stderr


def private_deployment(source, destination, replacements, recipe):
    shutil.copytree(source, destination)
    for name, binary in replacements.items():
        path = destination / (name + '.json')
        value = json.loads(path.read_text())
        digest = F.digest(binary)
        artifact = name + '-' + digest
        shutil.copyfile(binary, destination / artifact)
        (destination / artifact).chmod(0o700)
        value.update(artifact=artifact, sha256=digest,
                     key=hashlib.sha256(json.dumps(recipe, sort_keys=True).encode()).hexdigest())
        path.write_text(json.dumps(value) + '\n')
    D.packages(destination, body_schema=SCHEMA)


class Qualification:
    def __init__(self, args):
        self.args = args
        self.spec = manifest()
        self.requests = request_inventory(args.requests_dir)
        self.identity = {'host': F.digest(args.compiler), 'packages': D.packages(args.component_dir, body_schema=SCHEMA),
                         'sources': source_identity(args.source_root)}
        self.work = args.work_dir
        self.work.mkdir(parents=True, exist_ok=False)
        self.empty = self.work / 'empty-path'; self.empty.mkdir()
        self.records = []
        self.captures = []
        self.generations = []
        self.wrapper = self.work / 'capture-wrapper'

    def checkpoint(self, complete=False):
        report = {'complete': complete, 'scope': 'seven component sources; native catalog/backend/driver retained; not compiler bootstrap',
                  'selected_admission': 'passed' if complete else 'pending', 'identity': self.identity,
                  'guest_release': getattr(self.args, 'release', False), 'guest_facts': getattr(self.args, 'release', False),
                  'guest_leaks': True, 'other_six_boundary_modes': 'reference',
                  'cases': 24, 'success': 14, 'diagnostics': 8, 'profile': 2,
                  'operations': len(self.records), 'expected_operations': EXPECTED_OPERATIONS,
                  'records': self.records, 'captures': self.captures, 'generations': self.generations}
        if complete:report.update(failed=0, skipped=0)
        self.args.report.parent.mkdir(parents=True, exist_ok=True)
        self.args.report.write_text(json.dumps(report, indent=2) + '\n')

    def record(self, phase, mode, command, result):
        self.records.append({'phase': phase, 'mode': mode, 'command': list(map(str, command)), 'status': result[0],
                             'stdout_hex': result[1].hex(), 'stderr_hex': result[2].hex()})
        self.checkpoint()
        return result

    def host(self, mode, command, deployment, cwd, phase, capture=False):
        env = D.environment(mode, deployment, self.empty)
        if capture:
            wrapped = self.work / 'active-capture'
            if wrapped.exists():shutil.rmtree(wrapped)
            private_deployment(deployment, wrapped, {'body-check': self.wrapper}, {'developer_capture': F.digest(self.wrapper)})
            real = deployment / D.packages(deployment, body_schema=SCHEMA)['body-check']['artifact']
            request, reply = self.work / 'request.bin', self.work / 'reply.bin'
            request.unlink(missing_ok=True); reply.unlink(missing_ok=True)
            env = D.environment(mode, wrapped, self.empty)
            env.update(BODY_REAL=str(real), BODY_REQUEST=str(request), BODY_CAPTURE=str(reply))
        require('--no-cache' in command, 'claimed host operation may reuse a verdict')
        result = self.record(phase, mode, [self.args.compiler, *command], F.execute([self.args.compiler, *command], env, cwd, 600))
        if capture:
            require(request.is_file() and reply.is_file(), 'selected body checker did not execute')
            request_bytes, reply_bytes = request.read_bytes(), reply.read_bytes()
            capture = bound_capture(request_bytes, reply_bytes)
            archives = retained_capture(self.work, len(self.captures), request_bytes, reply_bytes)
            self.captures.append({'phase': phase, 'mode': mode, **capture, **archives})
            self.checkpoint()
        return result

    def runtime(self, mode, binary, arguments, cwd, phase, limit=False):
        env = D.environment(mode, self.args.component_dir, self.empty)
        return self.record(phase, mode, [binary, *arguments], guest(binary, arguments, env, cwd, limit))

    def build_flags(self):
        return ['--release', '--verify-facts'] if self.args.release else []

    def fixtures(self):
        for name, spec in self.spec['cases'].items():
            cwd = self.work / Path(name).stem; cwd.mkdir()
            entry = cwd / 'main.my'; shutil.copyfile(FIXTURES / spec['source'], entry)
            shutil.copyfile(FIXTURES / 'helper.my', cwd / 'helper.my')
            for file, hex_data in self.spec['data_files'].items():(cwd / file).write_bytes(bytes.fromhex(hex_data))
            command = ['check-project', entry, '--no-cache', '--diagnostics=json']
            native = self.host('reference', command, self.args.component_dir, cwd, name)
            require(native[0] == spec['native_status'] and not native[1], 'native source contract changed: ' + name)
            if spec['class'] == 'diagnostic':
                diagnostics = [D.diagnostic_contract(json.loads(line)['diagnostic']) for line in native[2].splitlines()]
                require(diagnostics == spec['diagnostics'], 'native ordered diagnostics/repairs changed: ' + name)
            for mode in ('shadow', 'component'):
                result = self.host(mode, command, self.args.component_dir, cwd, name)
                if spec['class'] == 'profile':
                    require(result[0] == 2 and not result[1] and b'ComponentProfile' in result[2], 'explicit profile refusal missing: ' + name)
                else:require(result == native, 'full shadow/diagnostic parity failed: ' + name)
            if spec['class'] != 'diagnostic':
                for mode in (('reference',) if spec['class'] == 'profile' else ('reference', 'shadow', 'component')):
                    binary = cwd / ('program-' + mode)
                    built = self.host(mode, ['build', entry, '--project', '--no-cache', *self.build_flags(), '-o', binary, '--zig=' + str(self.args.zig)], self.args.component_dir, cwd, name + '-build')
                    require(built[0] == 0 and binary.is_file(), 'generated resource build failed: ' + name)
                    result = self.runtime(mode, binary, [], cwd, name + '-runtime', spec.get('descriptor_limit') == 32)
                    require(result == (7, bytes.fromhex(spec['runtime_stdout_hex']), bytes.fromhex(spec['runtime_stderr_hex'])), 'resource runtime/cleanup failed: ' + name)

    def probes(self, binary, package, mode):
        spec = self.requests['packages'][package]
        request = self.args.requests_dir / spec['file']
        invalid = self.work / 'malformed.bin'; invalid.write_bytes(b'\xffBAD')
        missing = self.work / 'does-not-exist'
        results = [self.runtime(mode, binary, arguments, self.work, package + '-exchange')
                   for arguments in ([], ['--request', missing], ['--request', invalid], spec['arguments'] + [request])]
        require(results[0][0] == 2 and not results[0][1] and results[0][2], 'entry usage refusal missing')
        require(results[1][0] == 2 and not results[1][1] and results[1][2], 'entry missing-file refusal missing')
        require(results[3][0] == 0 and results[3][1] and not results[3][2], 'authentic successful entry exchange missing')
        return results

    def entries(self):
        baseline = {}
        original = self.identity['packages']
        for name in ENTRIES:
            baseline[name] = self.probes(self.args.component_dir / original[name]['artifact'], name, 'reference')
        generation = {}
        for name, relative in ENTRIES.items():
            entry = self.args.source_root / 'selfhost/components' / relative
            expected = self.host('reference', ['check', entry, '--no-cache'], self.args.component_dir, self.work, name + '-source-check')
            require(expected[0] == 0, 'native actual entry rejected: ' + name)
            for mode in ('shadow', 'component'):
                require(self.host(mode, ['check', entry, '--no-cache'], self.args.component_dir, self.work, name + '-source-check', True) == expected, 'actual entry full typed/catalog shadow failed: ' + name)
            for mode in ('reference', 'shadow', 'component'):
                binary = self.work / (name + '-generation1-' + mode)
                result = self.host(mode, ['build', entry, '--no-cache', *self.build_flags(), '-o', binary, '--zig=' + str(self.args.zig)], self.args.component_dir, self.work, name + '-generation1', mode != 'reference')
                require(result[0] == 0 and binary.is_file(), 'actual entry selected build failed: ' + name)
                require(self.probes(binary, name, mode) == baseline[name], 'first generation behavior differs: ' + name)
                if mode == 'component':generation[name] = binary
        recipe = {'host': self.identity['host'], 'sources': self.identity['sources'], 'parent_packages': self.identity['packages'],
                  'body_mode': 'component', 'flags': ['--no-cache', *self.build_flags()], 'seed_used_for_compilation': False}
        deployment = self.work / 'generation1'
        private_deployment(self.args.component_dir, deployment, generation, recipe)
        self.generations.append({'generation': 1, 'packages': D.packages(deployment, body_schema=SCHEMA), 'recipe': recipe})
        second = {}
        for name, relative in ENTRIES.items():
            entry = self.args.source_root / 'selfhost/components' / relative
            binary = self.work / (name + '-generation2')
            result = self.host('component', ['build', entry, '--no-cache', *self.build_flags(), '-o', binary, '--zig=' + str(self.args.zig)], deployment, self.work, name + '-generation2', True)
            require(result[0] == 0 and binary.is_file(), 'second generation selected build failed: ' + name)
            require(self.probes(binary, name, 'component') == baseline[name], 'second generation behavior differs: ' + name)
            second[name] = binary
        private_deployment(deployment, self.work / 'generation2', second, dict(recipe, parent_packages=D.packages(deployment, body_schema=SCHEMA)))
        self.generations.append({'generation': 2, 'packages': D.packages(self.work / 'generation2', body_schema=SCHEMA)})

    def run(self):
        self.checkpoint()
        seed = F.execute([self.args.builder, '--root', self.args.source_root, '--zig', self.args.zig, '--seed-only'], D.coordinator_environment(), self.args.source_root, 600)
        lines = seed[1].decode().strip().splitlines()
        require(seed[0] == 0 and len(lines) == 1 and Path(lines[0]).is_file(), 'qualified seed receipt verification failed')
        self.identity['qualified_seed_sha256'] = F.digest(Path(lines[0]))
        self.identity['seed_receipt_verification'] = {'command': list(map(str, [self.args.builder, '--root', self.args.source_root, '--zig', self.args.zig, '--seed-only'])), 'verified_binary': lines[0]}
        compiled = F.execute([self.args.zig, 'cc', FIXTURES / 'exchange_capture.c', '-O2', '-o', self.wrapper], D.coordinator_environment(), self.work, 180)
        require(compiled[0] == 0, 'bounded native capture fixture failed to compile')
        self.fixtures(); self.entries()
        require(len(self.records) == EXPECTED_OPERATIONS and len(self.captures) == 35 and len(self.generations) == 2, 'incomplete B7 operations/captures/generations')
        require_capture_inventory(self.captures)
        require(F.digest(self.args.compiler) == self.identity['host'] and D.packages(self.args.component_dir, body_schema=SCHEMA) == self.identity['packages'], 'installed deployment changed')
        require(source_identity(self.args.source_root) == self.identity['sources'], 'component source changed')
        require(request_inventory(self.args.requests_dir) == self.requests, 'authentic replay inventory changed')
        self.checkpoint(True)
        print('body entry qualification: 24 fixtures, 7 actual entries, 2 generations, 349 operations; 0 failed, 0 skipped')


def main():
    ap = argparse.ArgumentParser()
    for name in ('compiler', 'builder', 'component-dir', 'zig', 'source-root', 'requests-dir', 'work-dir', 'report'):
        ap.add_argument('--' + name, type=Path, required=True)
    ap.add_argument('--release', action='store_true', help='generated guest release/fact/leak lane; run both lanes for qualification')
    args = ap.parse_args()
    for name in ('compiler', 'builder', 'component_dir', 'zig', 'source_root', 'requests_dir', 'work_dir', 'report'):
        setattr(args, name, getattr(args, name).resolve())
    Qualification(args).run()


if __name__ == '__main__':main()
