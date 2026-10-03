"""Host fixtures exercise actual archive discovery/inventory; no compiler or guest runs."""
from pathlib import Path
import copy
import importlib.util
import io
import json
import shutil
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

import runtime_bindings as rt

HERE = Path(__file__).resolve().parent


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def file(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return path


class Fixture:
    def __init__(self, root, layout):
        self.repo, self.work = root / 'repo', root / 'trial'
        self.work.mkdir()
        self.protocol = self.repo / 'experiments/lox-compiler-runtime-protocol-20261003'
        self.protocol.mkdir(parents=True)
        descriptor = {'files': {}, 'reused': {}}
        for name in rt.BASE_FILES:
            original = file(root / 'legacy' / name, (HERE / 'base' / name).read_bytes())
            file(self.protocol / 'base' / name, original.read_bytes())
            descriptor['files'][name] = {'original_path': str(original), 'sha256': rt.sha(original)}
        save(self.protocol / 'protocol-base.json', descriptor)
        for name in rt.HELPERS:
            file(self.protocol / name, (HERE / name).read_bytes())
        file(self.protocol / 'README.md', b'synthetic host fixture, no performance claim\n')
        for name in rt.LEGACY:
            data = (HERE / 'base/reused' / name).read_bytes()
            live = file(self.repo / name, data)
            file(self.protocol / 'base/reused' / name, data)
            descriptor['reused'][name] = {'original_path': str(live), 'sha256': rt.sha(live)}
        save(self.protocol / 'protocol-base.json', descriptor)
        for name in ('baseline', 'candidate', 'reference', 'inputs', 'bin'):
            (self.work / name).mkdir()
        for name in ('baseline', 'candidate', 'reference', 'inputs'):
            file(self.work / name / 'fixture.txt', name.encode())
        compiler = file(root / 'compiler/bin/mylang', b'synthetic compiler identity')
        qbe = file(root / 'compiler/bin/qbe', b'synthetic QBE identity')
        runtimes = {}
        for backend in rt.BACKENDS:
            path = root / 'compiler/lib' / (backend + '.a') if layout == 'preinstalled' else self.work / ('cache-rebuilt-' + backend) / 'objects' / (backend + '.a')
            runtimes[backend] = file(path, ('synthetic RC archive ' + backend).encode())
        self.runtimes = runtimes
        self.measured = {backend: (runtimes[backend] if layout == 'preinstalled' else file(root / 'qualified-runtime' / (backend + '.a'), ('qualified RC ' + backend).encode())) for backend in rt.BACKENDS}
        qualified = {}
        controls = {'binaries': {}, 'binary_sha256': {}}
        for backend in rt.BACKENDS:
            for kind, target in [('qualified', qualified), ('control', controls['binaries'])]:
                binary = file(root / kind / backend, ('synthetic ELF ' + backend).encode())
                meta = {'backend': backend, 'runtime_object': str(self.measured[backend])}
                save(Path(str(binary) + '.qbe-manifest.json'), meta)
                file(Path(str(binary) + '.qbe-receipt'), b'synthetic native build receipt')
                target[backend if kind == 'qualified' else 'ast-' + backend] = str(binary)
        for arm in ('rust', 'go'):
            controls['binaries'][arm] = str(file(root / 'control' / arm, ('synthetic ' + arm).encode()))
        controls['binary_sha256'] = {name: rt.sha(path) for name, path in controls['binaries'].items()}
        control_manifest = root / 'control/binaries.json'
        save(control_manifest, controls)
        binary_map, digests, rows = {}, {}, []
        for backend in rt.BACKENDS:
            for prefix in ('baseline', 'candidate', 'rebuilt'):
                binary = file(self.work / 'bin' / (prefix + '-' + backend), ('synthetic ELF ' + backend).encode())
                runtime = runtimes[backend] if prefix == 'rebuilt' else self.measured[backend]
                sidecar = Path(str(binary) + '.qbe-manifest.json')
                save(sidecar, {'backend': backend, 'runtime_object': str(runtime)})
                file(Path(str(binary) + '.qbe-receipt'), b'synthetic native build receipt')
                if prefix == 'rebuilt':
                    rows.append({'status': 0, 'argv': ['compiler', '--backend', backend, '--rc-runtime', '-o', str(binary)], 'cwd': str(self.repo),
                                 'binary_sha256': rt.sha(binary), 'manifest_sha256': rt.sha(sidecar),
                                 'runtime_object': str(runtime), 'runtime_object_sha256': rt.sha(runtime)})
                else:
                    binary_map[prefix + '-' + backend] = str(binary)
                    digests[prefix + '-' + backend] = rt.sha(binary)
        save(self.work / 'binaries.json', {'binaries': binary_map, 'binary_sha256': digests})
        save(self.work / 'rebuilt-build.json', {'runtime': 'rc', 'builds': rows})
        source_map, qualification = root / 'sources.json', root / 'qualification.json'
        save(source_map, {'synthetic': True}); save(qualification, {'synthetic': True})
        save(self.work / 'preparation-inputs.json', {'protocol': rt.VERSION, 'compiler': str(compiler), 'qbe': str(qbe), 'candidate_map': str(source_map), 'qualification': str(qualification), 'qualified': qualified, 'control_binaries': str(control_manifest)})
        for name in rt.META:
            path = self.work / name
            if not path.exists():
                save(path, {'synthetic': True})
        self.seal()

    def seal(self):
        save(self.work / 'runtime-bindings.json', rt.derive(self.work))
        guards = rt.guard_inventory(self.work, self.repo)
        save(self.work / 'guards.json', guards)
        save(self.work / 'prepared.json', {'runtime_guard_protocol': rt.VERSION, 'guards': len(guards),
             'guards_sha256': rt.sha(self.work / 'guards.json'), 'manifest_sha256': rt.sha(self.work / 'binaries.json'),
             'runtime_bindings_sha256': rt.sha(self.work / 'runtime-bindings.json')})
        return guards


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='runtime-protocol-host-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def make(self, layout='bin-only'):
        return Fixture(self.root, layout)

    def test_bin_only_fresh_runtime_archives_are_exact_guards(self):
        f = self.make()
        self.assertFalse((self.root / 'compiler/lib').exists())
        guards = rt.verify_preparation(f.work, f.repo)
        binding = rt.load(f.work / 'runtime-bindings.json')
        self.assertEqual(set(binding['bindings']), rt.ROLES)
        for backend in rt.BACKENDS:
            self.assertEqual(guards[str(f.runtimes[backend])], rt.sha(f.runtimes[backend]))
            self.assertNotEqual(f.runtimes[backend], f.measured[backend])
        self.assertEqual(len({x['runtime_object'] for x in binding['bindings'].values()}), 4)

    def test_preinstalled_shared_archives_deduplicate_without_losing_roles(self):
        f = self.make('preinstalled')
        guards = rt.verify_preparation(f.work, f.repo)
        bindings = rt.load(f.work / 'runtime-bindings.json')['bindings']
        self.assertEqual(len(bindings), 6)
        self.assertEqual(len({x['runtime_object'] for x in bindings.values()}), 2)
        for backend in rt.BACKENDS:
            self.assertEqual(guards[str(f.runtimes[backend])], rt.sha(f.runtimes[backend]))

    def test_missing_rebuilt_guard_cannot_be_replaced_by_extra_guard(self):
        f = self.make();guards = rt.load(f.work / 'guards.json')
        del guards[str(f.runtimes['qbe'])]
        extra = file(self.root / 'irrelevant.a', b'not used by any guest')
        guards[str(extra)] = rt.sha(extra)
        save(f.work / 'guards.json', guards)
        prepared = rt.load(f.work / 'prepared.json');prepared['guards_sha256'] = rt.sha(f.work / 'guards.json');save(f.work / 'prepared.json', prepared)
        with self.assertRaisesRegex(ValueError, 'inventory differs'):
            rt.verify_preparation(f.work, f.repo)

    def test_unexpected_extra_runtime_guard_refused(self):
        f = self.make();guards = rt.load(f.work / 'guards.json')
        extra = file(self.root / 'unrelated.a', b'unrelated');guards[str(extra)] = rt.sha(extra)
        save(f.work / 'guards.json', guards)
        with self.assertRaisesRegex(ValueError, 'inventory differs'):
            rt.verify_preparation(f.work, f.repo)

    def test_missing_and_extra_role_bindings_refused(self):
        f = self.make();original = rt.load(f.work / 'runtime-bindings.json')
        for role in ('missing', 'extra'):
            broken = copy.deepcopy(original)
            if role == 'missing':del broken['bindings']['rebuilt-qbe']
            else:broken['bindings']['unexpected-qbe'] = broken['bindings']['rebuilt-qbe']
            save(f.work / 'runtime-bindings.json', broken)
            with self.subTest(role=role), self.assertRaisesRegex(ValueError, 'runtime bindings'):
                rt.verify_preparation(f.work, f.repo)

    def test_runtime_body_mutation_refused(self):
        f = self.make();f.runtimes['llvm'].write_bytes(b'changed reproduction archive')
        with self.assertRaisesRegex(ValueError, 'runtime binding differs'):
            rt.verify_preparation(f.work, f.repo)

    def test_missing_archive_and_manifest_refused(self):
        f = self.make();archive = f.runtimes['qbe'];body = archive.read_bytes();archive.unlink()
        with self.assertRaisesRegex(ValueError, 'archive missing'):rt.derive(f.work)
        archive.write_bytes(body)
        (f.work / 'bin/rebuilt-qbe.qbe-manifest.json').unlink()
        with self.assertRaisesRegex(ValueError, 'manifest missing'):rt.derive(f.work)

    def test_missing_relative_and_mismatched_runtime_binding_refused(self):
        f = self.make();sidecar = f.work / 'bin/rebuilt-qbe.qbe-manifest.json';original = rt.load(sidecar)
        for value in (None, 'relative.a', str(f.runtimes['llvm'])):
            broken = dict(original)
            if value is None:del broken['runtime_object']
            else:broken['runtime_object'] = value
            save(sidecar, broken)
            with self.subTest(value=value), self.assertRaises(ValueError):rt.derive(f.work)

    def test_duplicate_backend_and_boolean_success_refused(self):
        f = self.make();original = rt.load(f.work / 'rebuilt-build.json')
        for change in ('duplicate', 'boolean'):
            broken = copy.deepcopy(original)
            if change == 'duplicate':broken['builds'][1] = copy.deepcopy(broken['builds'][0])
            else:broken['builds'][0]['status'] = False
            save(f.work / 'rebuilt-build.json', broken)
            with self.subTest(change=change), self.assertRaises(ValueError):rt.derive(f.work)

    def test_legacy_preparation_cannot_be_retrospectively_accepted(self):
        f = self.make();prepared = rt.load(f.work / 'prepared.json');del prepared['runtime_guard_protocol'];save(f.work / 'prepared.json', prepared)
        with self.assertRaisesRegex(ValueError, 'prospectively prepared'):rt.verify_preparation(f.work, f.repo)

    def test_declared_count_is_not_an_inventory_certificate(self):
        f = self.make();prepared = rt.load(f.work / 'prepared.json');prepared['guards'] += 1;save(f.work / 'prepared.json', prepared)
        with self.assertRaisesRegex(ValueError, 'guard count differs'):rt.verify_preparation(f.work, f.repo)

    def test_changed_legacy_helper_and_new_input_keys_refused(self):
        f = self.make();base = f.protocol / 'base/build.py';body = base.read_bytes();base.write_bytes(body + b'\n# mutation\n')
        with self.assertRaisesRegex(ValueError, 'immutable legacy helper changed'):rt.verify_preparation(f.work, f.repo)
        base.write_bytes(body);inputs = rt.load(f.work / 'preparation-inputs.json');inputs['extra_runtime'] = str(f.runtimes['qbe']);save(f.work / 'preparation-inputs.json', inputs)
        with self.assertRaisesRegex(ValueError, 'input inventory differs'):rt.verify_preparation(f.work, f.repo)

    def test_cache_archive_survives_content_archive_exclusions(self):
        from archive import create, verify
        f = self.make();guards = rt.verify_preparation(f.work, f.repo)
        report = {'synthetic_host_fixture': True, 'performance_selection_inferred': False}
        result = create(f.work, guards, [], report, self.root / 'sealed', [])
        self.assertTrue(result['original_identities_checked'])
        index = rt.load(self.root / 'sealed/MANIFEST.json')
        for backend in rt.BACKENDS:self.assertIn(str(f.runtimes[backend]), index['files'])
        verify(self.root / 'sealed', originals=True)

    def analysis_fixture(self, f):
        manifest = rt.load(f.work / 'binaries.json')
        manifest['candidate_sources'] = {'baseline': {'path': str(f.work / 'baseline')}}
        cases, samples = [], []
        for number in range(13):
            name = 'case' + str(number)
            script = file(f.work / 'reference/benchmarks/lox/bench/scripts' / (name + '.lox'), b'print 1;\n')
            expected = file(f.work / 'reference/benchmarks/lox/bench/expected' / (name + '.out'), b'1\n')
            for engine in ('vm', 'tree'):
                case = engine + '/' + name
                cases.append({'id': case, 'name': name, 'engine': engine, 'expected': str(expected)})
                for arm in sorted(manifest['binary_sha256']):
                    sample = {'case': case, 'arm': arm, 'round': 0, 'status': 0, 'stderr': '', 'stdout_sha256': rt.sha(expected), 'wall_s': 1.0}
                    for event in ('instructions', 'cycles', 'branches', 'branch-misses'):
                        sample[event] = 100; sample[event + '_running_pct'] = 100
                    samples.append(sample)
        save(f.work / 'binaries.json', manifest)
        f.seal()
        receipt = f.work / 'synthetic-screen.json'
        save(receipt, {'manifest': manifest, 'phase': 'counters', 'rounds': 1, 'verified_after': True,
                       'cases': cases, 'samples': samples, 'binary_sha256': manifest['binary_sha256']})
        spec = importlib.util.spec_from_file_location('prospective_analysis', f.protocol / 'analyze.py')
        module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        output = f.work / 'synthetic-analysis.json'
        argv = ['analyze.py', str(receipt), '--metric', 'instructions', '--screen', '--out', str(output)]
        return module, output, argv

    def test_prospective_analysis_accepts_actual_reconstructed_inventory(self):
        f = self.make();module, output, argv = self.analysis_fixture(f)
        with patch('sys.argv', argv), redirect_stdout(io.StringIO()):module.main()
        result = rt.load(output)
        self.assertEqual(result['runtime_guard_protocol'], rt.VERSION)
        self.assertEqual(result['stable_guards_after'], len(rt.verify_preparation(f.work, f.repo)))
        self.assertEqual(result['samples'], 104)

    def test_analysis_refuses_unguarded_fresh_reproduction_archive(self):
        f = self.make();module, output, argv = self.analysis_fixture(f)
        guards = rt.load(f.work / 'guards.json');del guards[str(f.runtimes['qbe'])];save(f.work / 'guards.json', guards)
        with patch('sys.argv', argv), self.assertRaisesRegex(ValueError, 'inventory differs'):module.main()
        self.assertFalse(output.exists())

    def test_strict_closeout_refuses_unguarded_reproduction_before_metrics(self):
        import validation
        f = self.make();guards = rt.load(f.work / 'guards.json');del guards[str(f.runtimes['llvm'])];save(f.work / 'guards.json', guards)
        with patch.object(validation, '__file__', str(f.protocol / 'validation.py')), self.assertRaisesRegex(ValueError, 'inventory differs'):
            validation.validate(f.work)


if __name__ == '__main__':
    unittest.main()
