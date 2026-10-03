"""Prospective RC archive bindings and exact permitted guard inventory."""
import hashlib
import json
from pathlib import Path

VERSION = 'lox-compiler-runtime-guards-v2'
BACKENDS = ('llvm', 'qbe')
ROLES = {prefix + '-' + backend for prefix in ('baseline', 'candidate', 'rebuilt') for backend in BACKENDS}
BASE_FILES = {'prepare.py', 'analyze.py', 'build.py', 'elf.py', 'closeout.py', 'validation.py', 'archive.py', 'test_closeout.py'}
HELPERS = ('prepare.py', 'analyze.py', 'build.py', 'elf.py', 'closeout.py', 'validation.py', 'archive.py', 'runtime_bindings.py')
LEGACY = ('experiments/lox-parity-20261003/run.py', 'experiments/lox-performance-audit-20261002/audit.py',
          'experiments/lox-perf-improvements-20261002/analyze.py', 'scripts/build-slot.sh')
META = ('candidate-source37.json', 'author-qualification.json', 'binaries.json', 'rebuilt-build.json',
        'rebuild-equivalence.json', 'prepare-command.json', 'prepare-build.log', 'preparation-inputs.json', 'runtime-bindings.json')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load(path):
    return json.loads(Path(path).read_text())


def absolute(value):
    require(type(value) is str and Path(value).is_absolute(), 'binding requires an absolute path')
    return Path(value)


def option(argv, flag):
    require(argv.count(flag) == 1, 'missing/repeated rebuild option: ' + flag)
    at = argv.index(flag)
    require(at + 1 < len(argv), 'missing rebuild option value: ' + flag)
    return argv[at + 1]


def derive(work):
    """Require all six native roles; derive archives from actual sidecars, not prefix layout."""
    work = work.resolve()
    manifest, builds = load(work / 'binaries.json'), load(work / 'rebuilt-build.json')
    require(builds.get('runtime') == 'rc' and len(builds['builds']) == 2, 'requires two RC rebuilds')
    rows = {}
    for row in builds['builds']:
        require(type(row.get('status')) is int and row['status'] == 0, 'RC rebuild failed or unfinished')
        backend = option(row['argv'], '--backend')
        require(backend in BACKENDS and backend not in rows, 'duplicate/unknown RC rebuild backend')
        rows[backend] = row
    bindings = {}
    for role in sorted(ROLES):
        prefix, backend = role.split('-')
        binary = work / 'bin' / role
        if prefix != 'rebuilt':
            require(absolute(manifest['binaries'][role]) == binary, 'measured native output path differs')
            require(sha(binary) == manifest['binary_sha256'][role], 'measured native ELF identity differs')
        else:
            row = rows[backend]
            output = Path(option(row['argv'], '-o'))
            output = output if output.is_absolute() else absolute(row['cwd']) / output
            require(output.resolve() == binary and sha(binary) == row['binary_sha256'], 'rebuilt native output differs')
            require('--rc-runtime' in row['argv'] and '--gc-runtime' not in row['argv'], 'rebuild is not RC')
        sidecar = Path(str(binary) + '.qbe-manifest.json')
        require(sidecar.is_file(), 'native runtime manifest missing: ' + role)
        metadata = load(sidecar)
        require(metadata.get('backend') == backend, 'native runtime manifest backend differs: ' + role)
        runtime = absolute(metadata.get('runtime_object'))
        require(runtime.is_file(), 'runtime archive missing: ' + role)
        binding = {'binary': str(binary), 'binary_sha256': sha(binary), 'manifest': str(sidecar),
                   'manifest_sha256': sha(sidecar), 'runtime_object': str(runtime), 'runtime_object_sha256': sha(runtime)}
        if prefix == 'rebuilt':
            row = rows[backend]
            require(binding['manifest_sha256'] == row['manifest_sha256'], 'rebuild sidecar binding differs')
            require(binding['runtime_object'] == row['runtime_object'] and
                    binding['runtime_object_sha256'] == row['runtime_object_sha256'], 'rebuild runtime binding differs')
        bindings[role] = binding
    return {'protocol': VERSION, 'bindings': bindings}


def helpers(repo):
    here = repo / 'experiments/lox-compiler-runtime-protocol-20261003'
    descriptor = load(here / 'protocol-base.json')
    require(set(descriptor['files']) == BASE_FILES, 'protocol base helper inventory differs')
    paths = [here / name for name in HELPERS] + [here / 'README.md', here / 'protocol-base.json']
    require(set(descriptor['reused']) == set(LEGACY), 'reused helper inventory differs')
    for name, record in descriptor['reused'].items():
        copied, live = here / 'base/reused' / name, repo / name
        require(sha(copied) == sha(live) == record['sha256'], 'reused immutable helper changed: ' + name)
        paths.extend([copied, live])
    for name, record in descriptor['files'].items():
        copied, original = here / 'base' / name, absolute(record['original_path'])
        require(sha(copied) == sha(original) == record['sha256'], 'immutable legacy helper changed: ' + name)
        paths.extend([copied, original])
    return paths


def guard_inventory(work, repo):
    """Reconstruct exactly allowed guards; unexpected guards cannot replace missing paths."""
    work, repo = work.resolve(), repo.resolve()
    inputs = load(work / 'preparation-inputs.json')
    require(set(inputs) == {'protocol', 'compiler', 'qbe', 'candidate_map', 'qualification', 'qualified', 'control_binaries'}, 'preparation input inventory differs')
    require(inputs['protocol'] == VERSION and set(inputs['qualified']) == set(BACKENDS), 'unsupported preparation inputs')
    paths = set(helpers(repo))
    for name in ('compiler', 'qbe', 'candidate_map', 'qualification', 'control_binaries'):
        paths.add(absolute(inputs[name]))
    qualified = {absolute(value) for value in inputs['qualified'].values()}
    paths.update(qualified)
    controls = load(absolute(inputs['control_binaries']))
    natives = set(qualified)
    for arm in ('ast-llvm', 'ast-qbe', 'rust', 'go'):
        binary = absolute(controls['binaries'][arm])
        require(sha(binary) == controls['binary_sha256'][arm], 'original control ELF differs')
        paths.add(binary)
        if arm.startswith('ast-'):
            natives.add(binary)
    for binary in qualified | {absolute(controls['binaries'][arm]) for arm in ('ast-llvm', 'ast-qbe', 'rust', 'go')}:
        for suffix in ('.qbe-manifest.json', '.qbe-receipt'):
            sidecar = Path(str(binary) + suffix)
            require(binary not in natives or sidecar.is_file(), 'original native sidecar missing')
            if sidecar.is_file():
                paths.add(sidecar)
                if suffix == '.qbe-manifest.json':
                    runtime = absolute(load(sidecar).get('runtime_object'))
                    require(runtime.is_file(), 'original native archive missing')
                    paths.add(runtime)
    for name in ('baseline', 'candidate', 'reference', 'inputs', 'bin'):
        root = work / name
        require(root.is_dir(), 'prepared evidence directory missing: ' + name)
        paths.update(p for p in root.rglob('*') if p.is_file())
    paths.update(work / name for name in META)
    actual = derive(work)
    require(load(work / 'runtime-bindings.json') == actual, 'missing/extra/mismatched runtime bindings')
    for binding in actual['bindings'].values():
        paths.update(absolute(binding[name]) for name in ('binary', 'manifest', 'runtime_object'))
    return {str(path): sha(path) for path in sorted(paths)}


def verify_preparation(work, repo):
    work = work.resolve()
    prepared, guards = load(work / 'prepared.json'), load(work / 'guards.json')
    require(prepared.get('runtime_guard_protocol') == VERSION, 'requires prospectively prepared runtime-guards-v2')
    expected = guard_inventory(work, repo)
    require(guards == expected, 'permitted guard inventory differs (missing, extra or changed)')
    require(type(prepared.get('guards')) is int and prepared['guards'] == len(expected), 'prepared guard count differs')
    require(prepared['guards_sha256'] == sha(work / 'guards.json') and
            prepared['manifest_sha256'] == sha(work / 'binaries.json'), 'preparation identity differs')
    require(prepared.get('runtime_bindings_sha256') == sha(work / 'runtime-bindings.json'), 'prepared runtime binding identity differs')
    return guards
