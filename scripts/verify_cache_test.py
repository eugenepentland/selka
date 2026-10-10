#!/usr/bin/env python3
"""Adversarial verification coordinator tests with a tiny fake build driver."""
import contextlib
import copy
import fcntl
import io
import json
import os
from pathlib import Path
import py_compile
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import verify_cache as coordinator
from verification_snapshot import Snapshot, SnapshotError

REPOSITORY = Path(__file__).resolve().parents[1]
REAL_PREPARE_INPUTS = tuple(coordinator.PREPARE_INPUTS)
FAKE_ZIG = '''#!{python}
import json,sys
from pathlib import Path
root=Path.cwd(); args=sys.argv[1:]
events=root/'.events.json'
rows=json.loads(events.read_text()) if events.exists() else []
phase='plan' if 'verification-plan' in args else 'prepare' if 'verification-prepare' in args else 'gate'
rows.append({{'phase':phase,'argv':args}}); events.write_text(json.dumps(rows))
if phase=='plan':
    path=root/'zig-out/verification/inventory.json'; path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes((root/'gate-contract.json').read_bytes())
elif phase=='prepare':
    artifacts={{}}
    for name in ['mylang','units','cli','core']:
        path=root/'zig-out/bin'/name; path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(b'fake-native-'+name.encode()); artifacts[name]=str(path)
    (root/'zig-out/verification/artifacts.json').write_text(json.dumps({{'version':1,'artifacts':artifacts}}))
    package=root/'zig-out/libexec/mylang/components'; package.mkdir(parents=True,exist_ok=True)
    for name in ['test-index','cache-plan']:
        (package/name).write_bytes(b'fake-component')
        (package/(name+'.json')).write_text(json.dumps({{'artifact':name}}))
elif (root/'.failure').exists():
    raise SystemExit(int((root/'.failure').read_text()))
'''


def group(name, inputs, cacheable=True):
    return {'id': name, 'target': 'verification-' + name, 'label': name,
            'inputs': inputs, 'cacheable': cacheable,
            'reason': 'registered deterministic action' if cacheable else 'requires freshness'}


class VerificationCoordinator(unittest.TestCase):
    def setUp(self):
        scratch = REPOSITORY / '.tmp'
        scratch.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='verification-test-', dir=scratch)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.cache = self.root / '.receipts'
        self.write('config.zig', 'configuration')
        self.write('sources/compiler.txt', 'source')
        self.input = self.write('inputs/unit/fixture.txt', 'original')
        self.write('inputs/docs/example.md', 'documentation')
        self.tool = self.write('tools/dependency', 'original')
        self.zig = self.write('tools/zig', FAKE_ZIG.format(python=sys.executable))
        self.zig.chmod(0o755)
        (self.root / 'scripts').mkdir()
        shutil.copy2(REPOSITORY / 'scripts/build-slot.sh', self.root / 'scripts/build-slot.sh')
        self.plan = {'version': 1, 'required_targets': ['test', 'fmt-check'],
                     'groups': [group('unit', ['inputs/unit/']), group('docs', ['inputs/docs/'])],
                     'coverage': {'required_actions': 2, 'registered_actions': 2, 'unknown_actions': []}}
        self.save_plan()
        self.before_gate = None
        self.after_gate = None
        self.gate_status = None
        self.admissions = []
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(coordinator, 'CONFIG_INPUTS', ['config.zig', 'gate-contract.json']))
        self.stack.enter_context(patch.object(coordinator, 'PREPARE_INPUTS', ['sources/']))
        self.stack.enter_context(patch.object(coordinator, 'COORDINATOR_INPUTS', ['scripts/build-slot.sh']))
        self.stack.enter_context(patch.object(coordinator, 'tool_contract', return_value=([], [self.zig, self.tool])))
        self.stack.enter_context(patch.object(coordinator, 'run_admitted', side_effect=self.admit))

    def write(self, relative, data):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)
        return path

    def save_plan(self):
        self.write('gate-contract.json', json.dumps(self.plan))

    def admit(self, root, kind, argv, env, unchanged):
        self.admissions.append((kind, argv))
        if kind == 'gate' and self.before_gate:
            self.before_gate()
        if not unchanged():
            return coordinator.RETRY, 0.0
        if kind == 'gate' and self.gate_status is not None:
            return self.gate_status, 0.0
        status = subprocess.run(argv, cwd=root, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=10).returncode
        if kind == 'gate' and self.after_gate:
            self.after_gate()
        return status, 0.0

    def execute(self, options=None, force=False):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return coordinator.execute(self.root, self.cache, self.zig, options or ['-j3'], force)

    def events(self, phase):
        path = self.root / '.events.json'
        return [row for row in json.loads(path.read_text()) if row['phase'] == phase] if path.exists() else []

    def receipts(self):
        return list((self.cache / 'actions').glob('*.json'))

    def states(self):
        return {row['id']: row['state'] for row in coordinator.read_record(self.cache / 'last-run.json')['actions']}

    def test_cold_then_warm_reuses_actions_without_any_admission(self):
        self.assertEqual(self.execute(), 0)
        self.assertEqual([kind for kind, _ in self.admissions], ['build', 'build', 'gate'])
        self.assertEqual(len(self.receipts()), 2)
        self.admissions.clear()
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.admissions, [])
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})
        self.assertEqual([len(self.events(phase)) for phase in ['plan', 'prepare', 'gate']], [1, 1, 1])

    def test_always_fresh_action_runs_on_warm_request_without_reusing_its_success(self):
        self.plan['groups'].append(group('fresh', ['inputs/unit/'], False))
        self.plan['coverage'].update(required_actions=3, registered_actions=3)
        self.save_plan()
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused', 'fresh': 'fresh'})
        self.assertEqual(len(self.receipts()), 2)
        self.assertEqual(self.events('gate')[-1]['argv'][1], 'verification-fresh')

    def test_added_fixture_invalidates_its_action_and_preserves_unrelated_action(self):
        self.assertEqual(self.execute(), 0)
        self.write('inputs/unit/added.txt', 'new fixture')
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'reused'})
        self.assertEqual(len(self.events('prepare')), 1)
        self.assertIn('-Dtest-rerun=true', self.events('gate')[-1]['argv'])

    def test_changed_options_environment_and_tool_each_invalidate(self):
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.execute(['-j4']), 0)
        with patch.dict(os.environ, {'MYL_CORE_LEAKCHECK': '1'}):
            self.assertEqual(self.execute(['-j4']), 0)
            original = self.tool.stat()
            self.tool.write_text('changed!')
            os.utime(self.tool, ns=(original.st_atime_ns, original.st_mtime_ns))
            self.assertEqual(self.execute(['-j4']), 0)
        self.assertEqual(len(self.events('gate')), 4)

    def test_fixed_default_seed_and_explicit_seed_produce_distinct_action_receipts(self):
        defaults = coordinator.parse_options([])
        explicit = coordinator.parse_options(['--seed=123'])
        self.assertEqual([arg for arg in defaults if arg.startswith('--seed=')], ['--seed=0'])
        self.assertEqual([arg for arg in explicit if arg.startswith('--seed=')], ['--seed=123'])
        self.assertEqual(self.execute(defaults), 0)
        original_receipts = set(self.receipts())
        self.assertEqual(self.execute(explicit), 0)
        new_receipts = set(self.receipts()) - original_receipts
        self.assertEqual(len(new_receipts), 2)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})
        self.assertEqual(self.execute(explicit), 0)
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})
        self.assertEqual(len(self.events('gate')), 2)
        self.assertIn('--seed=0', self.events('gate')[0]['argv'])
        self.assertIn('--seed=123', self.events('gate')[1]['argv'])

    def test_changed_host_contract_invalidates_eligible_groups(self):
        with patch.object(coordinator, 'host_contract', return_value={'cpu_features': ['original']}):
            self.assertEqual(self.execute(), 0)
            self.assertEqual(self.execute(), 0)
            self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})
        with patch.object(coordinator, 'host_contract', return_value={'cpu_features': ['changed']}):
            self.assertEqual(self.execute(), 0)
            self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})
            self.assertEqual(self.execute(), 0)
            self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})
        self.assertEqual(len(self.events('gate')), 2)

    def test_zig_command_rerun_replaces_conflicting_options_and_preserves_one_seed(self):
        command = coordinator.zig_command(self.zig, ['verification-unit'],
                                          ['-j3', '-Dtest-rerun=false', '-Dtest-rerun=true', '--seed=42'], rerun=True)
        self.assertEqual([arg for arg in command if arg.startswith('-Dtest-rerun=')], ['-Dtest-rerun=true'])
        self.assertEqual([arg for arg in command if arg.startswith('--seed=')], ['--seed=42'])
        default = coordinator.zig_command(self.zig, ['verification-unit'], ['-j3'])
        self.assertEqual([arg for arg in default if arg.startswith('--seed=')], ['--seed=0'])

    def test_force_and_test_rerun_execute_warm_actions(self):
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.execute(force=True), 0)
        self.assertEqual(self.states(), {'unit': 'fresh', 'docs': 'fresh'})
        self.assertEqual(self.execute(['-j3', '-Dtest-rerun=true']), 0)
        self.assertEqual(len(self.events('gate')), 3)

    def test_failed_explicit_rerun_removes_older_success_and_next_request_executes(self):
        for options, force in [(['-j3'], True), (['-j3', '-Dtest-rerun=true'], False)]:
            with self.subTest(options=options, force=force):
                self.assertEqual(self.execute(), 0)
                self.assertEqual(len(self.receipts()), 2)
                failure = self.write('.failure', '17')
                self.assertEqual(self.execute(options, force), 17)
                self.assertEqual(self.receipts(), [])
                failure.unlink()
                prior = len(self.events('gate'))
                self.assertEqual(self.execute(), 0)
                self.assertEqual(len(self.events('gate')), prior + 1)
                self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})

    def test_embedded_documentation_is_required_preparation_input_and_change_rebuilds(self):
        self.assertIn('docs/', REAL_PREPARE_INPUTS)
        documentation = self.write('docs/compiler-embedded.md', 'original embedded documentation')
        with patch.object(coordinator, 'PREPARE_INPUTS', ['sources/', 'docs/']):
            self.assertEqual(self.execute(), 0)
            self.assertEqual(self.execute(), 0)
            self.assertEqual(len(self.events('prepare')), 1)
            documentation.write_text('changed embedded documentation')
            self.assertEqual(self.execute(), 0)
            self.assertEqual(len(self.events('prepare')), 2)

    def test_normalized_environment_isolates_git_config_templates_and_command_overrides(self):
        git = shutil.which('git')
        self.assertIsNotNone(git, 'git is required by the verification tool contract')
        home = self.root / 'hostile-home'
        marker = self.root / '.hostile-hook-ran'
        hook = self.write('hostile-hooks/pre-commit', '#!/bin/sh\ntouch "' + str(marker) + '"\nexit 91\n')
        hook.chmod(0o755)
        template_hook = self.write('hostile-template/hooks/pre-commit', hook.read_text())
        template_hook.chmod(0o755)
        config = '[commit]\n\tgpgsign = true\n[core]\n\thooksPath = ' + str(hook.parent) + '\n'
        global_config = self.write('hostile-home/.gitconfig', config)
        system_config = self.write('hostile-system.gitconfig', config)
        inherited = {'HOME': str(home), 'GIT_CONFIG_GLOBAL': str(global_config),
                     'GIT_CONFIG_SYSTEM': str(system_config), 'GIT_TEMPLATE_DIR': str(template_hook.parent.parent),
                     'GIT_CONFIG_COUNT': '2', 'GIT_CONFIG_KEY_0': 'commit.gpgsign', 'GIT_CONFIG_VALUE_0': 'true',
                     'GIT_CONFIG_KEY_1': 'core.hooksPath', 'GIT_CONFIG_VALUE_1': str(hook.parent),
                     'GIT_CONFIG_PARAMETERS': "'commit.gpgsign=true'", 'GIT_DIR': str(self.root / 'wrong-repository')}
        with patch.dict(os.environ, inherited):
            environment = coordinator.normalized_environment(self.root)
        self.assertEqual(environment['GIT_CONFIG_GLOBAL'], '/dev/null')
        self.assertEqual(environment['GIT_CONFIG_SYSTEM'], '/dev/null')
        self.assertEqual(environment['GIT_TEMPLATE_DIR'], '')
        for name in ['GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0',
                     'GIT_CONFIG_KEY_1', 'GIT_CONFIG_VALUE_1', 'GIT_CONFIG_PARAMETERS', 'GIT_DIR']:
            self.assertNotIn(name, environment)
        fixture = self.root / 'git-fixture'
        fixture.mkdir()
        for command in [[git, 'init', '-q'], [git, 'commit', '-q', '--allow-empty', '-m', 'isolated fixture']]:
            result = subprocess.run(command, cwd=fixture, env=environment, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker.exists())
        self.assertFalse((fixture / '.git/hooks/pre-commit').exists())

    def test_normalized_python_ignores_stale_timestamp_bytecode_after_same_size_restored_mtime_edit(self):
        source = self.write('python-fixture/identity_probe.py', 'VALUE = "old"\n')
        original = source.stat()
        bytecode = source.parent / '__pycache__' / ('identity_probe.' + sys.implementation.cache_tag + '.pyc')
        bytecode.parent.mkdir()
        py_compile.compile(str(source), cfile=str(bytecode), doraise=True,
                           invalidation_mode=py_compile.PycInvalidationMode.TIMESTAMP)
        source.write_text('VALUE = "new"\n')
        os.utime(source, ns=(original.st_atime_ns, original.st_mtime_ns))
        self.assertEqual(source.stat().st_size, original.st_size)
        self.assertEqual(source.stat().st_mtime_ns, original.st_mtime_ns)
        environment = coordinator.normalized_environment(self.root)
        self.assertEqual(environment['PYTHONPYCACHEPREFIX'], '/dev/null')
        self.assertEqual(environment['PYTHONDONTWRITEBYTECODE'], '1')
        command = [sys.executable, '-c', 'import identity_probe; print(identity_probe.VALUE)']
        # Establish the hazard: disabling writes alone still accepts timestamp pyc.
        control = dict(environment)
        control.pop('PYTHONPYCACHEPREFIX')
        stale = subprocess.run(command, cwd=source.parent, env=control, capture_output=True, text=True, timeout=10)
        self.assertEqual(stale.returncode, 0, stale.stderr)
        self.assertEqual(stale.stdout.strip(), 'old')
        fresh = subprocess.run(command, cwd=source.parent, env=environment, capture_output=True, text=True, timeout=10)
        self.assertEqual(fresh.returncode, 0, fresh.stderr)
        self.assertEqual(fresh.stdout.strip(), 'new')

    def test_normalized_admitted_shell_cannot_run_startup_hooks_or_exported_functions(self):
        startup_marker = self.root / '.startup-hook-ran'
        function_marker = self.root / '.exported-function-ran'
        completion = self.root / '.shell-completed'
        startup = self.write('shell-startup.sh', 'touch "' + str(startup_marker) + '"\n')
        inherited = {'BASH_ENV': str(startup), 'ENV': str(startup),
                     'BASH_FUNC_printf%%': '() { touch "' + str(function_marker) + '"; }'}
        with patch.dict(os.environ, inherited):
            environment = coordinator.normalized_environment(self.root)
        for name in inherited:
            self.assertNotIn(name, environment)
        environment.update(MYLANG_SLOT_DIR=str(self.root / '.shell-slots'), MYLANG_GATE_SLOTS='1',
                           MYLANG_GATE_MEM='0', MYLANG_SLOT_POLL='1', MYLANG_SLOT_SETTLE='0', MYLANG_TIMING_CPUS='')
        bash = shutil.which('bash', path=environment['PATH'])
        self.assertIsNotNone(bash)
        command = [bash, '-c', 'printf shell-clean > "$1"', 'verification-shell', str(completion)]
        status, _ = REAL_ADMISSION(self.root, 'gate', command, environment, lambda: True)
        self.assertEqual(status, 0)
        self.assertEqual(completion.read_text(), 'shell-clean')
        self.assertFalse(startup_marker.exists())
        self.assertFalse(function_marker.exists())

    def test_new_earlier_path_directory_cannot_shadow_normalized_worker_tool(self):
        tool = self.write('tools/existing/identity-tool', '#!/bin/sh\nprintf selected-tool\n')
        tool.chmod(0o755)
        missing = self.root / 'missing-earlier'
        inherited_path = os.pathsep.join([str(missing), 'tools/existing', ''])
        with patch.dict(os.environ, {'PATH': inherited_path}):
            environment = coordinator.normalized_environment(self.root)
        self.assertEqual(environment['PATH'].split(os.pathsep), [str(tool.parent), str(self.root)])
        self.assertEqual(shutil.which('identity-tool', path=environment['PATH']), str(tool))
        shadow = self.write('missing-earlier/identity-tool', '#!/bin/sh\nprintf shadow-tool\n')
        shadow.chmod(0o755)
        self.assertNotIn(str(missing), environment['PATH'].split(os.pathsep))
        self.assertEqual(shutil.which('identity-tool', path=environment['PATH']), str(tool))
        fresh = subprocess.run(['identity-tool'], cwd=self.root, env=environment,
                               capture_output=True, text=True, timeout=10)
        self.assertEqual(fresh.returncode, 0, fresh.stderr)
        self.assertEqual(fresh.stdout, 'selected-tool')
        control = dict(environment, PATH=os.pathsep.join([str(missing), str(tool.parent)]))
        shadowed = subprocess.run(['identity-tool'], cwd=self.root, env=control,
                                  capture_output=True, text=True, timeout=10)
        self.assertEqual(shadowed.returncode, 0, shadowed.stderr)
        self.assertEqual(shadowed.stdout, 'shadow-tool')

    def test_filtered_inventory_never_reuses_or_publishes_complete_action_success(self):
        self.plan['configuration'] = {'filtered': True}
        self.save_plan()
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'fresh', 'docs': 'fresh'})
        self.assertEqual(self.receipts(), [])

    def test_untracked_environment_override_executes_and_does_not_publish(self):
        with patch.dict(os.environ, {'CPATH': str(self.root / 'undeclared-includes')}):
            self.assertEqual(self.execute(), 0)
            self.assertEqual(self.execute(), 0)
        self.assertEqual(self.receipts(), [])
        self.assertEqual(len(self.events('gate')), 2)

    def test_malformed_action_receipt_is_a_miss(self):
        self.assertEqual(self.execute(), 0)
        self.receipts()[0].write_text('{torn')
        self.assertEqual(self.execute(), 0)
        self.assertEqual(sorted(self.states().values()), ['execute', 'reused'])
        self.assertEqual(len(self.events('gate')), 2)

    def test_corrupt_inventory_regenerates_before_accepting_prior_action_receipts(self):
        self.assertEqual(self.execute(), 0)
        (self.root / 'zig-out/verification/inventory.json').write_text('{torn')
        self.assertEqual(self.execute(), 0)
        self.assertEqual(len(self.events('plan')), 2)
        self.assertEqual(len(self.events('gate')), 1)

    def test_failed_worker_does_not_publish_success_and_next_request_retries(self):
        failure = self.write('.failure', '17')
        self.assertEqual(self.execute(), 17)
        self.assertEqual(self.receipts(), [])
        failure.unlink()
        self.assertEqual(self.execute(), 0)
        self.assertEqual(len(self.events('gate')), 2)

    def test_cancelled_worker_status_is_preserved_without_success_publication(self):
        self.gate_status = -signal.SIGTERM
        self.assertEqual(self.execute(), 143)
        self.assertEqual(self.receipts(), [])
        self.assertFalse(coordinator.read_record(self.cache / 'last-run.json')['success'])

    def test_queued_mutation_blocks_worker_and_publishes_no_success(self):
        self.before_gate = lambda: self.input.write_text('changed while queued')
        self.assertEqual(self.execute(), coordinator.RETRY)
        self.assertEqual(self.events('gate'), [])
        self.assertEqual(self.receipts(), [])

    def test_mutation_after_worker_success_prevents_receipt_publication(self):
        self.after_gate = lambda: self.input.write_text('changed after execution')
        self.assertEqual(self.execute(), coordinator.RETRY)
        self.assertEqual(len(self.events('gate')), 1)
        self.assertEqual(self.receipts(), [])

    def test_mutation_during_publication_rolls_back_all_new_success_receipts(self):
        save = coordinator.save_receipt

        def changed_publication(path, action_key):
            save(path, action_key)
            self.input.write_text('changed during publication')

        with patch.object(coordinator, 'save_receipt', side_effect=changed_publication):
            self.assertEqual(self.execute(), coordinator.RETRY)
        self.assertEqual(self.receipts(), [])

    def test_publish_checked_removes_written_receipt_when_snapshot_validation_raises(self):
        receipt = self.root / '.preparation-receipt.json'
        with Snapshot(self.root, ['inputs/unit/fixture.txt']) as snapshot:
            def lost_history():
                self.assertEqual(coordinator.read_record(receipt), {'test': 'atomic write completed'})
                raise SnapshotError('input history unavailable after publication')

            with patch.object(snapshot, 'unchanged', side_effect=lost_history):
                with self.assertRaisesRegex(SnapshotError, 'history unavailable'):
                    coordinator.publish_checked(receipt, {'test': 'atomic write completed'}, [snapshot])
        self.assertFalse(receipt.exists())

    def test_interruption_after_action_receipt_write_removes_attempted_success(self):
        save = coordinator.save_receipt
        attempted = []

        def interrupted_publication(path, action_key):
            save(path, action_key)
            self.assertTrue(coordinator.valid_receipt(path, action_key))
            attempted.append(path)
            raise KeyboardInterrupt

        with patch.object(coordinator, 'save_receipt', side_effect=interrupted_publication):
            with self.assertRaises(KeyboardInterrupt):
                self.execute()
        self.assertEqual(len(attempted), 1)
        self.assertFalse(attempted[0].exists())
        self.assertEqual(self.receipts(), [])

    def test_unknown_action_is_covered_by_always_fresh_fallback(self):
        self.plan['groups'].append(group('unclassified', [], False))
        self.plan['coverage'].update(required_actions=3, unknown_actions=['external-step'])
        self.save_plan()
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused', 'unclassified': 'fresh'})
        self.assertEqual(len(self.receipts()), 2)

    def test_invalid_or_incomplete_inventory_is_rejected(self):
        cases = []
        wrong_target = copy.deepcopy(self.plan)
        wrong_target['groups'][0]['target'] = 'test'
        cases.append(wrong_target)
        duplicate = copy.deepcopy(self.plan)
        duplicate['groups'].append(duplicate['groups'][0])
        cases.append(duplicate)
        uncovered = copy.deepcopy(self.plan)
        uncovered['coverage']['unknown_actions'] = ['external-step']
        uncovered['coverage']['required_actions'] = 3
        cases.append(uncovered)
        unsupported = copy.deepcopy(self.plan)
        unsupported['version'] = 999
        cases.append(unsupported)
        boolean_version = copy.deepcopy(self.plan)
        boolean_version['version'] = True
        cases.append(boolean_version)
        for index, value in enumerate(cases):
            with self.subTest(case=index):
                path = self.write('invalid-inventory.json', json.dumps(value))
                with self.assertRaises(coordinator.VerificationError):
                    coordinator.inventory(path)

    def test_unknown_action_fallback_cannot_be_declared_cacheable(self):
        self.plan['groups'].append(group('unclassified', [], True))
        self.plan['coverage'].update(required_actions=3, unknown_actions=['external-step'])
        path = self.write('invalid-inventory.json', json.dumps(self.plan))
        with self.assertRaises(coordinator.VerificationError):
            coordinator.inventory(path)

    def test_private_slot_handshake_revalidates_after_queue_and_never_launches_changed_worker(self):
        slots = self.root / '.slots'
        slots.mkdir()
        environment = dict(os.environ, MYLANG_SLOT_DIR=str(slots), MYLANG_GATE_SLOTS='1',
                           MYLANG_GATE_MEM='0', MYLANG_SLOT_POLL='1', MYLANG_SLOT_SETTLE='0',
                           MYLANG_TIMING_CPUS='')
        marker = self.root / '.worker-started'
        command = [sys.executable, '-c', 'from pathlib import Path; Path(__import__("sys").argv[1]).touch()', str(marker)]
        results, errors = [], []
        with (slots / 'gate1.lock').open('w') as lock, Snapshot(self.root, ['inputs/unit/fixture.txt']) as snapshot:
            fcntl.flock(lock, fcntl.LOCK_EX)

            def admitted():
                try:
                    results.append(coordinator.run_admitted(self.root, 'gate', command, environment, snapshot.unchanged))
                except BaseException as error:
                    errors.append(error)

            # setUp patches the function for fast flows; restore its real implementation here.
            with patch.object(coordinator, 'run_admitted', REAL_ADMISSION):
                thread = threading.Thread(target=admitted, daemon=True)
                thread.start()
                deadline = time.monotonic() + 10
                try:
                    while not list((slots / 'queue-gate').glob('*.wait')):
                        self.assertLess(time.monotonic(), deadline, 'private waiter did not enqueue')
                        self.assertTrue(thread.is_alive(), errors)
                        time.sleep(.01)
                    self.input.write_text('changed while blocked behind real slot')
                finally:
                    fcntl.flock(lock, fcntl.LOCK_UN)
                    thread.join(timeout=12)
                self.assertFalse(thread.is_alive(), 'private handshake did not complete')
        self.assertEqual(errors, [])
        self.assertEqual(results[0][0], coordinator.RETRY)
        self.assertFalse(marker.exists())
        self.assertEqual(list((slots / 'queue-gate').glob('*.wait')), [])


REAL_ADMISSION = coordinator.run_admitted


if __name__ == '__main__':
    unittest.main()
