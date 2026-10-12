#!/usr/bin/env python3
"""Adversarial verification coordinator tests with a tiny fake build driver."""
import contextlib
import copy
import fcntl
import io
import importlib.util
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
from verification_snapshot import RetainedSession, Snapshot, SnapshotError

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
    values=json.loads((root/'.artifact-values.json').read_text()) if (root/'.artifact-values.json').exists() else {{}}
    for name in ['mylang','units','cli','core']:
        path=root/'zig-out/bin'/name; path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(b'fake-native-'+name.encode()+values.get(name,'').encode()); artifacts[name]=str(path)
    (root/'zig-out/verification/artifacts.json').write_text(json.dumps({{'version':1,'artifacts':artifacts}}))
    package=root/'zig-out/libexec/mylang/components'; package.mkdir(parents=True,exist_ok=True)
    for name in ['test-index','cache-plan']:
        (package/name).write_bytes(b'fake-component'+values.get('component:'+name,'').encode())
        (package/(name+'.json')).write_text(json.dumps({{'artifact':name}}))
elif (root/'.failure').exists():
    raise SystemExit(int((root/'.failure').read_text()))
elif (root/'.hang-gate').exists():
    import time
    (root/'.gate-started').touch()
    time.sleep(30)
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
        self.plan = {'version': coordinator.INVENTORY_VERSION, 'required_targets': ['test', 'fmt-check'],
                     'groups': [group('unit', ['inputs/unit/']), group('docs', ['inputs/docs/'])],
                     'coverage': {'required_actions': 2, 'registered_actions': 2, 'unknown_actions': []}}
        self.save_plan()
        self.before_gate = None
        self.after_gate = None
        self.gate_status = None
        self.admissions = []
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(coordinator, 'CONFIG_INPUTS', ['config.zig', 'build_test_inputs.zig']))
        self.stack.enter_context(patch.object(coordinator, 'PREPARE_INPUTS', ['sources/']))
        self.stack.enter_context(patch.object(coordinator, 'COORDINATOR_INPUTS', ['scripts/build-slot.sh']))
        self.stack.enter_context(patch.object(coordinator, 'tool_contract', return_value=([], [self.zig, self.tool])))
        self.stack.enter_context(patch.object(coordinator, 'run_admitted', side_effect=self.admit))
        with Snapshot(self.root, coordinator.CONFIG_INPUTS) as configuration:
            self.qualified_configuration = copy.deepcopy(configuration.identity)
        candidate = dict(self.qualified_configuration, files=[item for item in self.qualified_configuration['files']
                                                              if item['path'] != 'build_test_inputs.zig'])
        self.stack.enter_context(patch.object(coordinator, 'DECLARATIVE_CONFIG_SHA256', coordinator.key(candidate)))

    def write(self, relative, data):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)
        return path

    def save_plan(self):
        self.plan.setdefault('configuration', {'filtered': False, 'rerun': False, 'optimize': 'Debug'})
        self.plan['configuration'].setdefault('rerun', False)
        self.plan['configuration'].setdefault('optimize', 'Debug')
        self.plan.setdefault('action_metadata', [])
        known = {item['id']: item for item in self.plan['action_metadata']}
        self.plan['action_metadata'] = [known.get(item['id'], {
            'id': item['id'], 'identity_scope': 'group-local-v1',
            'steps': [] if item['id'] == 'unclassified' else [{
                'label': 'verification action ' + item['id'] + ' member 0',
                'original_label': item['label'], 'kind': 'run'}]}) for item in self.plan['groups']]
        self.plan['input_lists'] = [{'name': item['id'], 'inputs': item['inputs']} for item in self.plan['groups']]
        self.write('build_test_inputs.zig', '\n'.join(
            'pub const ' + item['name'].replace('-', '_') + ' = [_][]const u8{' +
            ','.join(json.dumps(recipe) for recipe in item['inputs']) + '};'
            for item in self.plan['input_lists']))
        # This fake build contract is an out-of-band test fixture, not executable
        # build code. Explicit regeneration models the watched declaration edit.
        self.plan['input_lists'] = [{'name': item['name'].replace('-', '_'), 'inputs': item['inputs']}
                                    for item in self.plan['input_lists']]
        (self.cache / 'inventory.json').unlink(missing_ok=True)
        self.write('gate-contract.json', json.dumps(self.plan))

    def admit(self, root, kind, argv, env, unchanged, timings=None, **controls):
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
        if timings is not None:
            timings.append({'kind': kind, 'status': status, 'admitted': True,
                            'admission_wait_seconds': 0.0, 'validation_seconds': 0.0,
                            'worker_seconds': 0.0, 'observed_held_seconds': 0.0, 'elapsed_seconds': 0.0})
        return status, 0.0

    def execute(self, options=None, force=False, shared=None, **controls):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return coordinator.execute(self.root, self.cache, self.zig, options or ['-j3'], force, shared, **controls)

    def test_shared_success_reuses_after_private_action_receipts_removed(self):
        shared = self.root / '.shared-evidence'
        self.plan['groups'][0]['inputs'].append('tools/dependency')
        self.save_plan()
        self.assertEqual(self.execute(shared=shared), 0)
        for path in self.receipts():
            path.unlink()
        self.admissions.clear()
        self.assertEqual(self.execute(shared=shared), 0)
        self.assertEqual(self.admissions, [])
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertGreater(report['snapshot_statistics']['digest_reuses'], 0)
        self.assertTrue(report['evidence_store']['shared'])
        self.assertTrue((self.cache / 'inventory.json').is_file())
        self.assertFalse((shared / 'inventory.json').exists())

    def test_advisory_budget_failure_preserves_success_and_reuse(self):
        with patch.object(coordinator.verification_budgets, 'calibrate', side_effect=ValueError('bad diagnostic')):
            self.assertEqual(self.execute(), 0)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertTrue(report['success'])
        self.assertEqual(report['action_budgets']['status'], 'unknown')
        self.admissions.clear()
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.admissions, [])
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})

    def test_measurement_expiry_during_reporting_revokes_new_publications(self):
        slots = self.root / 'measurement-slots'
        environment = dict(os.environ, MYLANG_SLOT_DIR=str(slots), MYLANG_SLOT_SETTLE='0',
                           MYLANG_SLOT_POLL='1', MYLANG_TIMING_MEM='0')
        environment.pop('MYLANG_ADMISSION_DIR', None)
        environment.pop('MYLANG_ADMISSION_KIND', None)
        def slow_report(*_args, **_kwargs):
            self.assertEqual(len(self.receipts()), 2)
            window.started_at = time.monotonic() - window.seconds
            raise coordinator.verification_measurement.WindowExpired('injected reporting deadline')
        with patch.dict(os.environ, environment, clear=True):
            with patch.object(coordinator.verification_budgets, 'calibrate', side_effect=slow_report):
                with self.assertRaises(coordinator.verification_measurement.WindowExpired):
                    with coordinator.verification_measurement.timing_window(20) as window:
                        self.execute()
        self.assertEqual(self.receipts(), [])
        self.assertFalse(coordinator.read_record(self.cache / 'last-run.json')['success'])
        self.assertEqual(self.execute(), 0)

    def test_measurement_expiry_during_publication_revokes_local_and_shared_receipts(self):
        slots = self.root / 'measurement-slots'
        environment = dict(os.environ, MYLANG_SLOT_DIR=str(slots), MYLANG_SLOT_SETTLE='0',
                           MYLANG_SLOT_POLL='1', MYLANG_TIMING_MEM='0')
        environment.pop('MYLANG_ADMISSION_DIR', None)
        environment.pop('MYLANG_ADMISSION_KIND', None)
        original = coordinator.fuzz_campaign_store.Store.publish_success
        published = []
        def delayed(store, action_key, *args):
            result = original(store, action_key, *args)
            published.append(action_key)
            self.assertTrue(result)
            window.started_at = time.monotonic() - window.seconds
            raise coordinator.verification_measurement.WindowExpired('injected publication deadline')
        shared = self.root / 'shared'
        with patch.dict(os.environ, environment, clear=True):
            with patch.object(coordinator.fuzz_campaign_store.Store, 'publish_success', delayed):
                with self.assertRaises(coordinator.verification_measurement.WindowExpired):
                    with coordinator.verification_measurement.timing_window(20) as window:
                        self.execute(shared=shared)
        self.assertEqual(self.receipts(), [])
        self.assertEqual(len(published), 1)
        self.assertIsNone(coordinator.fuzz_campaign_store.Store(shared).load_success(published[0]))

    def test_deferred_metadata_only_tool_change_is_rejected_without_events(self):
        with RetainedSession() as retained, retained.activate():
            self.assertEqual(self.execute(), 0)
            self.admissions.clear()
            calls = []

            def resolve(_zig, _environment):
                calls.append(True)
                if len(calls) == 2:
                    original = self.tool.read_bytes()
                    self.tool.write_bytes(b'tool mutation during second resolution')
                    self.tool.write_bytes(original)
                return [], [self.zig, self.tool]

            watcher_type = coordinator.verification_snapshot._Inotify
            with patch.object(coordinator, 'tool_contract', side_effect=resolve), \
                 patch.object(watcher_type, '_drain', lambda watcher: not watcher.dirty):
                with self.assertRaises(coordinator.VerificationError) as caught:
                    self.execute()
            self.assertEqual(caught.exception.status, coordinator.RETRY)
            self.assertEqual(self.admissions, [])
            self.assertFalse(coordinator.read_record(self.cache / 'last-run.json')['success'])

    def test_retained_session_warm_request_avoids_hashing_discovery_and_admission(self):
        with RetainedSession() as session, session.activate():
            self.assertEqual(self.execute(), 0)
            self.admissions.clear()
            self.assertEqual(self.execute(), 0)
            report = coordinator.read_record(self.cache / 'last-run.json')
            self.assertEqual(self.admissions, [])
            self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})
            stats = report['snapshot_statistics']
            self.assertEqual(stats['files_hashed'], 0)
            self.assertEqual(stats['directories_enumerated'], 0)
            self.assertGreaterEqual(stats['snapshot_reuses'], 5)
            self.assertGreater(stats['metadata_observations'], 0)

    def test_retained_session_edit_and_forced_failure_still_require_work(self):
        with RetainedSession() as session, session.activate():
            self.assertEqual(self.execute(), 0)
            self.input.write_text('changed fixture')
            self.admissions.clear()
            self.assertEqual(self.execute(), 0)
            self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'reused'})
            self.assertEqual(len(self.admissions), 1)
            self.gate_status = 17
            self.assertEqual(self.execute(force=True), 17)
            self.gate_status = None
            self.assertEqual(self.execute(), 0)
            self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})

    def test_retained_session_does_not_publish_for_edit_after_admission(self):
        with RetainedSession() as session, session.activate():
            self.assertEqual(self.execute(), 0)
            self.after_gate = lambda: self.input.write_text('changed during work')
            self.assertEqual(self.execute(force=True), coordinator.RETRY)
            self.after_gate = None
            self.assertEqual(self.execute(), 0)
            self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})

    def test_shared_changed_tool_path_does_not_reuse_exact_receipt(self):
        shared = self.root / '.shared-evidence'
        self.assertEqual(self.execute(shared=shared), 0)
        changed = self.write('tools/zig-other-path', self.zig.read_text())
        changed.chmod(0o755)
        self.zig = changed
        self.stack.enter_context(patch.object(coordinator, 'tool_contract', return_value=([], [self.zig, self.tool])))
        self.admissions.clear()
        self.assertEqual(self.execute(shared=shared), 0)
        self.assertIn('gate', [kind for kind, _ in self.admissions])
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})

    def test_shared_lease_prevents_collection_across_admission(self):
        shared = self.root / '.shared-evidence'
        observed = []
        self.before_gate = lambda: observed.append(coordinator.fuzz_campaign_store.Store(shared).gc(dry_run=False))
        self.assertEqual(self.execute(shared=shared), 0)
        self.assertTrue(observed[0]['skipped_active'])

    def test_shared_root_workflow_lock_spans_admission_and_publication(self):
        shared = self.root / '.shared-evidence'
        expected = coordinator.key({'domain': 'verification-coordinator-v1', 'root': str(self.root)})
        lock = coordinator.fuzz_campaign_store.Store.coordinator_lock
        publish = coordinator.fuzz_campaign_store.Store.publish_success
        held, publications = [], []
        @contextlib.contextmanager
        def workflow(store, key):
            self.assertEqual(key, expected)
            with lock(store, key):
                held.append(key)
                try:
                    yield
                finally:
                    held.pop()
        def guarded_publish(*args, **kwargs):
            self.assertEqual(held, [expected])
            publications.append(args[1])
            return publish(*args, **kwargs)
        self.before_gate = lambda: self.assertEqual(held, [expected])
        with patch.object(coordinator.fuzz_campaign_store.Store, 'coordinator_lock', new=workflow), \
                patch.object(coordinator.fuzz_campaign_store.Store, 'publish_success', new=guarded_publish):
            self.assertEqual(self.execute(shared=shared), 0)
        self.assertEqual(len(publications), 2)
        self.assertEqual(held, [])

    def test_shared_forced_failure_removes_prior_success(self):
        shared = self.root / '.shared-evidence'
        self.assertEqual(self.execute(shared=shared), 0)
        self.gate_status = 17
        self.assertEqual(self.execute(force=True, shared=shared), 17)
        self.gate_status = None
        self.admissions.clear()
        self.assertEqual(self.execute(shared=shared), 0)
        self.assertIn('gate', [kind for kind, _ in self.admissions])

    def test_shared_rejected_publication_is_not_success(self):
        shared = self.root / '.shared-evidence'
        with patch.object(coordinator.fuzz_campaign_store.Store, 'publish_success', return_value=False):
            with self.assertRaisesRegex(coordinator.VerificationError, 'publication rejected'):
                self.execute(shared=shared)
        self.assertEqual(self.receipts(), [])

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

    def test_quick_then_complete_preserves_receipts_and_reports_exact_remaining_work(self):
        self.assertEqual(self.execute(profile='quick', quick_actions=1), 3)
        partial = coordinator.read_record(self.cache / 'last-run.json')
        self.assertFalse(partial['success'])
        self.assertTrue(partial['selected_success'])
        self.assertFalse(partial['profile_coverage']['complete_verification'])
        self.assertEqual(partial['profile_coverage']['counts']['outstanding'], 1)
        self.assertEqual(len(self.receipts()), 1)
        self.assertEqual(self.execute(profile='complete'), 0)
        complete = coordinator.read_record(self.cache / 'last-run.json')
        self.assertTrue(complete['profile_coverage']['complete_verification'])
        self.assertEqual(complete['profile_coverage']['counts'],
                         {'required': 2, 'reused': 1, 'executed': 1, 'outstanding': 0})
        self.assertEqual(self.execute(profile='quick'), 3)
        self.assertEqual(len(self.receipts()), 2)

    def test_long_profile_cannot_certify_missing_qualification(self):
        def qualification(root, cache, compiler, zig, context, snapshots, **controls):
            self.assertEqual(root, self.root)
            self.assertEqual(compiler, self.root / 'zig-out/bin/mylang')
            self.assertEqual(controls['max_actions'], 4)
            self.assertEqual(controls['targets'], list(coordinator.verification_qualification.OBLIGATIONS))
            return coordinator.verification_qualification.QualificationRun(context, cache, contextlib.ExitStack(), snapshots)
        with patch.object(coordinator.verification_qualification, 'qualify', side_effect=qualification) as run:
            self.assertEqual(self.execute(profile='long-qualification'), 3)
            self.assertEqual(run.call_count, 1)
        coverage = coordinator.read_record(self.cache / 'last-run.json')['profile_coverage']
        self.assertTrue(coverage['complete_verification'])
        self.assertFalse(coverage['complete_qualification'])
        self.assertEqual(coverage['qualification_outstanding'], list(coordinator.verification_qualification.OBLIGATIONS))

    def test_long_qualification_mutation_revokes_new_local_and_shared_gate_successes(self):
        shared = self.root / 'shared'
        published = []
        def qualification(root, cache, compiler, zig, context, snapshots, **controls):
            published.extend(path.stem for path in self.receipts())
            self.assertEqual(len(published), 2)
            self.input.write_text('changed during long qualification')
            return coordinator.verification_qualification.QualificationRun(context, cache, contextlib.ExitStack(), snapshots)
        with patch.object(coordinator.verification_qualification, 'qualify', side_effect=qualification):
            self.assertEqual(self.execute(profile='long-qualification', shared=shared), coordinator.RETRY)
        self.assertEqual(self.receipts(), [])
        store = coordinator.fuzz_campaign_store.Store(shared)
        self.assertTrue(all(store.load_success(key) is None for key in published))
        self.assertFalse(coordinator.read_record(self.cache / 'last-run.json')['success'])

    def test_long_qualification_exception_revokes_new_successes(self):
        def interrupted(*_args, **_kwargs):
            self.assertEqual(len(self.receipts()), 2)
            raise SnapshotError('qualification input disappeared')
        with patch.object(coordinator.verification_qualification, 'qualify', side_effect=interrupted):
            with self.assertRaises(SnapshotError):
                self.execute(profile='long-qualification')
        self.assertEqual(self.receipts(), [])
        self.assertFalse(coordinator.read_record(self.cache / 'last-run.json')['success'])

    def test_invalid_profile_controls_fail_before_preparation(self):
        with self.assertRaises(ValueError):
            self.execute(profile='unsupported')
        with self.assertRaises(ValueError):
            self.execute(quick_actions=0)
        self.assertEqual(self.admissions, [])

    def test_fixture_invalidation_names_changed_dependency(self):
        self.assertEqual(self.execute(), 0)
        first = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual(first['actions'][0]['invalidation']['status'], 'unknown')
        self.input.write_text('changed fixture')
        self.assertEqual(self.execute(), 0)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertIn({'kind': 'file_content_changed', 'name': 'inputs/unit/fixture.txt'},
                      report['actions'][0]['invalidation']['changes'])
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'reused'})

    def test_corrupt_diagnostics_and_advisory_budget_do_not_invalidate_success(self):
        self.assertEqual(self.execute(), 0)
        (self.cache / 'diagnostics/unit.json').write_text('not valid JSON')
        (self.cache / 'diagnostics/docs.json').unlink()
        self.admissions.clear()
        self.assertEqual(self.execute(warn_after=1e-12), 0)
        self.assertEqual(self.admissions, [])
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertTrue(report['loop_budget']['exceeded'])
        self.assertFalse(report['loop_budget']['enforced'])

    def test_advisory_policy_changes_reuse_and_missing_test_telemetry_is_explicit(self):
        policy = self.write('policy.json', json.dumps({'version': 1, 'mode': 'report_only', 'entries': []}))
        self.assertEqual(self.execute(budget_policy=policy), 0)
        first = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual(first['action_coverage']['counts']['executed'], 2)
        self.assertEqual(first['actions'][0]['test_telemetry'][0]['status'], 'unknown')
        policy.write_text('malformed advisory data')
        self.assertEqual(self.execute(budget_policy=policy), 0)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual(report['scoped_policy']['status'], 'unavailable')
        self.assertEqual(report['action_coverage']['counts']['reused'], 2)

    def test_qualified_producer_metadata_narrows_only_with_current_source_and_mode(self):
        helper = coordinator.verification_producers
        label = 'text-scalar-units'
        for name in helper.CLOSURES[label]:
            self.write(name, 'reviewed source fixture')
        binary = self.write('native-scalar', 'binary fixture')
        record = {'version': 2, 'producers': {label: helper.producer_metadata(self.root, label, binary, 'Debug')}}
        pure = group('text_scalar_unit', list(helper.CLOSURES[label]))
        pure['artifacts'] = [label]
        common = {'artifacts': 'whole-artifact-fallback', 'build_configuration': 'a' * 64,
                  'tools': 'b' * 64, 'options': [], 'action_controls': {'optimize': 'Debug'}}
        with Snapshot(self.root, pure['inputs']) as sources, Snapshot(self.root, [], [binary]) as artifact:
            providers = {label: artifact.identity['files']}
            accepted = coordinator.action_payload(pure, sources, common, self.root, providers, producer_manifest=record)
            self.assertIn('producer', accepted['common']['artifacts'][label])
            incomplete = dict(pure, inputs=pure['inputs'][:-1])
            fallback = coordinator.action_payload(incomplete, sources, common, self.root, providers, producer_manifest=record)
            self.assertEqual(fallback['common']['artifacts'], 'whole-artifact-fallback')
            fallback = coordinator.action_payload(pure, sources, common, self.root, providers)
            self.assertEqual(fallback['common']['artifacts'], 'whole-artifact-fallback')
            incompatible = copy.deepcopy(record)
            incompatible['producers'][label]['mode'] = 'ReleaseFast'
            fallback = coordinator.action_payload(pure, sources, common, self.root, providers, producer_manifest=incompatible)
            self.assertEqual(fallback['common']['artifacts'], 'whole-artifact-fallback')
        self.write('src/number_grammar.txt', 'changed embedded semantics')
        with Snapshot(self.root, pure['inputs']) as sources:
            fallback = coordinator.action_payload(pure, sources, common, self.root, providers, producer_manifest=record)
            self.assertEqual(fallback['common']['artifacts'], 'whole-artifact-fallback')

    def test_execution_deadline_change_invalidates_success_and_is_explained(self):
        self.assertEqual(self.execute(gate_timeout=60), 0)
        self.admissions.clear()
        self.assertEqual(self.execute(gate_timeout=30), 0)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertIn({'kind': 'common_changed', 'name': 'execution_limits'},
                      report['actions'][0]['invalidation']['changes'])

    def test_invalid_deadlines_fail_before_admission(self):
        for value in (0, -1, True, float('inf'), float('nan')):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.execute(gate_timeout=value)
        self.assertEqual(self.admissions, [])
        self.assertEqual(self.receipts(), [])

    def test_preparation_timeout_writes_incomplete_report(self):
        with patch.object(coordinator, 'prepare', side_effect=coordinator.VerificationError('timed out', 124)):
            with self.assertRaises(coordinator.VerificationError) as raised:
                self.execute(build_timeout=1)
        self.assertEqual(raised.exception.status, 124)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertFalse(report['success'])
        self.assertEqual(report['stage'], 'preparation')
        self.assertEqual(report['status'], 124)
        self.assertEqual(self.receipts(), [])

    def test_report_storage_failure_preserves_timeout_and_success(self):
        original = coordinator.atomic_record
        def write(path, value):
            if path.name == 'last-run.json':
                raise OSError('diagnostic storage unavailable')
            original(path, value)
        with patch.object(coordinator, 'atomic_record', side_effect=write):
            with patch.object(coordinator, 'prepare', side_effect=coordinator.VerificationError('timed out', 124)):
                with self.assertRaises(coordinator.VerificationError) as raised:
                    self.execute(build_timeout=1)
            self.assertEqual(raised.exception.status, 124)
            self.assertEqual(self.execute(), 0)
            self.assertEqual(len(self.receipts()), 2)
            self.admissions.clear()
            self.assertEqual(self.execute(), 0)
            self.assertEqual(self.admissions, [])

    def test_real_admitted_timeout_never_publishes_and_next_request_recovers(self):
        environment = {'MYLANG_SLOT_DIR': str(self.root / '.private-slots'),
                       'MYLANG_BUILD_MEM': '0', 'MYLANG_GATE_MEM': '0',
                       'MYLANG_SLOT_POLL': '1', 'MYLANG_SLOT_SETTLE': '0', 'MYLANG_TIMING_CPUS': ''}
        self.write('.hang-gate', 'yes')
        with patch.dict(os.environ, environment), patch.object(coordinator, 'run_admitted', REAL_ADMISSION):
            self.assertEqual(self.execute(gate_timeout=.5), 124)
            report = coordinator.read_record(self.cache / 'last-run.json')
            self.assertFalse(report['success'])
            self.assertTrue(report['admissions'][-1]['timed_out'])
            self.assertTrue((self.root / '.gate-started').exists())
            self.assertEqual(self.receipts(), [])
            (self.root / '.hang-gate').unlink()
            self.assertEqual(self.execute(gate_timeout=.5), 0)
            self.assertEqual(len(self.receipts()), 2)

    def test_unrelated_group_addition_removal_preserves_existing_successes(self):
        self.assertEqual(self.execute(), 0)
        before = {item['id']: item['action_key'] for item in coordinator.read_record(self.cache / 'last-run.json')['actions']}
        self.plan['groups'].append(group('added', ['inputs/docs/']))
        self.plan['coverage'].update(required_actions=3, registered_actions=3)
        self.save_plan()
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused', 'added': 'execute'})
        after = {item['id']: item['action_key'] for item in coordinator.read_record(self.cache / 'last-run.json')['actions']}
        self.assertEqual({name: after[name] for name in before}, before)
        self.plan['groups'].pop()
        self.plan['coverage'].update(required_actions=2, registered_actions=2)
        self.save_plan()
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})

    def test_member_change_invalidates_only_its_group(self):
        self.assertEqual(self.execute(), 0)
        member = {'label': 'verification action unit member 1', 'original_label': 'new test', 'kind': 'run'}
        self.plan['action_metadata'][0]['steps'].append(member)
        self.plan['coverage'].update(required_actions=3, registered_actions=3)
        self.save_plan()
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'reused'})

    def test_changed_recipe_invalidates_only_its_group(self):
        self.assertEqual(self.execute(), 0)
        self.plan['groups'][0]['inputs'].append('inputs/docs/')
        self.save_plan()
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'reused'})

    def test_renamed_fixture_invalidates_only_its_group(self):
        self.assertEqual(self.execute(), 0)
        self.input.rename(self.input.with_name('renamed.txt'))
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'reused'})

    def test_unfamiliar_declaration_syntax_keeps_broad_configuration(self):
        self.assertEqual(self.execute(), 0)
        path = self.root / 'build_test_inputs.zig'
        path.write_text(path.read_text() + '\ncomptime { @compileError("unknown semantics"); }')
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})

    def test_declarative_parser_requires_complete_known_data_syntax(self):
        path = self.write('lists.zig', 'pub const one = [_][]const u8{"a//b", "c"};\n'
                                     'pub const two = one ++ [_][]const u8{"d"}; // comment\n')
        self.assertEqual(coordinator.declared_input_lists(path), {'one': ['a//b', 'c'], 'two': ['a//b', 'c', 'd']})
        path.write_text('pub const one = @import("unknown.zig");')
        self.assertIsNone(coordinator.declared_input_lists(path))
        path.write_text('pub const one = [_][]const u8{"a"}; ignored')
        self.assertIsNone(coordinator.declared_input_lists(path))
        path.write_text('pub const one = [_][]const u8{"a"}; pub const one = [_][]const u8{"b"};')
        self.assertIsNone(coordinator.declared_input_lists(path))

    def test_declaration_export_mismatch_and_symlink_keep_full_configuration(self):
        identity = {'files': [{'path': 'config.zig', 'sha256': 'config'},
                              {'path': 'build_test_inputs.zig', 'sha256': 'lists'}]}
        narrow = coordinator.action_configuration(identity, self.plan, self.root, self.qualified_configuration)
        self.assertEqual(narrow['files'], identity['files'][:1])
        mismatch = copy.deepcopy(self.plan)
        mismatch['input_lists'][0]['inputs'] = ['unreviewed/']
        self.assertEqual(coordinator.action_configuration(identity, mismatch, self.root, self.qualified_configuration), identity)
        linked = copy.deepcopy(identity)
        linked['files'][1]['resolved'] = 'elsewhere.zig'
        self.assertEqual(coordinator.action_configuration(linked, self.plan, self.root, self.qualified_configuration), linked)

    def test_consumer_qualification_is_explicit_and_complete(self):
        identity = {'files': [{'path': 'build_test_inputs.zig', 'sha256': 'lists'}]}
        changed = copy.deepcopy(self.qualified_configuration)
        changed['files'].append({'path': 'new-consumer.zig', 'sha256': 'changed'})
        self.assertEqual(coordinator.action_configuration(identity, self.plan, self.root, changed), identity)
        with patch.object(coordinator, 'DECLARATIVE_CONFIG_SHA256', None):
            self.assertEqual(coordinator.action_configuration(identity, self.plan, self.root, self.qualified_configuration), identity)
        self.assertEqual(coordinator.action_configuration(identity, self.plan, self.root), identity)

    def test_configuration_controls_remain_identity_inputs(self):
        self.assertEqual(self.execute(), 0)
        self.plan['configuration']['optimize'] = 'ReleaseSafe'
        self.save_plan()
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})

    def test_metadata_rejects_duplicate_missing_or_changed_member_coverage(self):
        cases = []
        absent = copy.deepcopy(self.plan)
        absent.pop('action_metadata')
        cases.append(absent)
        duplicate = copy.deepcopy(self.plan)
        duplicate['action_metadata'][1] = copy.deepcopy(duplicate['action_metadata'][0])
        cases.append(duplicate)
        uncovered = copy.deepcopy(self.plan)
        uncovered['action_metadata'][0]['steps'].append(copy.deepcopy(uncovered['action_metadata'][0]['steps'][0]))
        cases.append(uncovered)
        bad_count = copy.deepcopy(self.plan)
        bad_count['coverage'].update(required_actions=3, registered_actions=3)
        cases.append(bad_count)
        for index, value in enumerate(cases):
            with self.subTest(case=index):
                path = self.write('metadata-invalid.json', json.dumps(value))
                with self.assertRaises(coordinator.VerificationError):
                    coordinator.inventory(path)

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

    def artifact_cohorts(self):
        self.plan['groups'][0]['artifacts'] = ['units']
        self.plan['groups'][1]['artifacts'] = ['cli']
        self.plan['groups'].extend([dict(group('pure', ['inputs/docs/']), artifacts=[]),
                                    group('conservative', ['inputs/docs/'])])
        self.plan['coverage'].update(required_actions=4, registered_actions=4)
        self.save_plan()

    def test_artifact_change_executes_only_dependent_and_conservative_cohorts(self):
        self.artifact_cohorts()
        self.assertEqual(self.execute(), 0)
        self.write('.artifact-values.json', json.dumps({'units': '-changed'}))
        (self.root / 'zig-out/bin/units').write_bytes(b'fake-native-units-changed')
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'reused', 'pure': 'reused', 'conservative': 'execute'})
        argv = self.events('gate')[-1]['argv']
        self.assertIn('verification-unit', argv)
        self.assertIn('verification-conservative', argv)
        self.assertNotIn('verification-docs', argv)
        self.assertNotIn('verification-pure', argv)
        self.assertEqual(self.execute(), 0)
        self.assertEqual(set(self.states().values()), {'reused'})

    def test_narrowed_cohorts_still_invalidate_for_configuration_change(self):
        self.artifact_cohorts()
        self.assertEqual(self.execute(), 0)
        self.write('config.zig', 'changed configuration')
        self.assertEqual(self.execute(), 0)
        self.assertEqual(set(self.states().values()), {'execute'})

    def test_component_change_invalidates_selected_provider_but_preserves_pure_cohort(self):
        self.artifact_cohorts()
        self.plan['groups'][0]['artifacts'] = ['components']
        self.save_plan()
        self.assertEqual(self.execute(), 0)
        self.write('.artifact-values.json', json.dumps({'component:cache-plan': '-changed'}))
        (self.root / 'zig-out/libexec/mylang/components/cache-plan').write_bytes(b'fake-component-changed')
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'reused', 'pure': 'reused', 'conservative': 'execute'})

    def test_narrowed_cohorts_keep_aba_guard_on_unselected_artifacts(self):
        self.artifact_cohorts()
        artifact = self.root / 'zig-out/bin/core'
        self.after_gate = lambda: artifact.write_bytes(b'changed unrelated provider during execution')
        self.assertEqual(self.execute(), coordinator.RETRY)
        self.assertEqual(self.receipts(), [])

    def test_unknown_artifact_selector_fails_closed_before_gate_execution(self):
        self.plan['groups'][0]['artifacts'] = ['not-a-provider']
        self.save_plan()
        with self.assertRaisesRegex(coordinator.VerificationError, 'unavailable artifact provider'):
            self.execute()
        self.assertEqual(self.events('gate'), [])
        self.assertEqual(self.receipts(), [])

    def test_admission_and_snapshot_phases_are_reported_without_warm_admission(self):
        self.assertEqual(self.execute(), 0)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual([event['kind'] for event in report['admissions']], ['build', 'build', 'gate'])
        for name in ['source_snapshot_seconds', 'action_input_snapshot_seconds',
                     'prepare_lookup_outside_admission_seconds', 'final_validation_seconds', 'publication_seconds']:
            self.assertGreaterEqual(report['timings'][name], 0)
        self.assertEqual(self.execute(), 0)
        warm = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual(warm['admissions'], [])
        self.assertEqual(warm['build_admitted_seconds'], 0)
        self.assertEqual(warm['gate_admitted_seconds'], 0)

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
        timings = []
        status, held = REAL_ADMISSION(self.root, 'gate', command, environment, lambda: True, timings=timings)
        self.assertEqual(status, 0)
        self.assertEqual(completion.read_text(), 'shell-clean')
        self.assertFalse(startup_marker.exists())
        self.assertFalse(function_marker.exists())
        self.assertEqual(len(timings), 1)
        self.assertEqual(timings[0]['observed_held_seconds'], held)
        self.assertGreater(timings[0]['worker_seconds'], 0)
        self.assertGreaterEqual(held, timings[0]['validation_seconds'] + timings[0]['worker_seconds'])
        self.assertAlmostEqual(timings[0]['elapsed_seconds'], timings[0]['admission_wait_seconds'] + held)

    def test_failed_log_open_does_not_report_previous_execution_timings(self):
        logs = self.root / '.logs'
        old_log = self.write('.logs/stdout.log', 'compile exe old Debug native success 7s MaxRSS:90M\n')
        environment = coordinator.normalized_environment(self.root)
        environment.update(MYLANG_SLOT_DIR=str(self.root / '.log-slots'), MYLANG_GATE_SLOTS='1',
                           MYLANG_GATE_MEM='0', MYLANG_SLOT_POLL='1', MYLANG_SLOT_SETTLE='0', MYLANG_TIMING_CPUS='')
        original_open = Path.open
        def open_log(path, mode='r', *args, **kwargs):
            if path == old_log and mode == 'wb':
                raise PermissionError('current log cannot be opened')
            return original_open(path, mode, *args, **kwargs)
        timings = []
        with patch.object(Path, 'open', open_log):
            status, _ = REAL_ADMISSION(self.root, 'gate', [sys.executable, '-c', 'pass'], environment,
                                      lambda: True, timings=timings, log_dir=logs)
        self.assertEqual(status, 0)
        self.assertIn('old Debug', old_log.read_text())
        captured = timings[0]['logs'][0]
        self.assertFalse(captured['capture_available'])
        self.assertEqual(captured['observed_steps']['status'], 'unknown')
        self.assertEqual(captured['observed_steps']['observations'], [])

    def test_admission_settle_survives_worker_success_and_timeout(self):
        for expected, source in ((0, 'pass'), (124, 'import time; time.sleep(30)')):
            slots = self.root / ('.settle-slots-' + str(expected))
            environment = coordinator.normalized_environment(self.root)
            environment.update(MYLANG_SLOT_DIR=str(slots), MYLANG_GATE_SLOTS='1',
                               MYLANG_GATE_MEM='0', MYLANG_SLOT_POLL='1', MYLANG_SLOT_SETTLE='2', MYLANG_TIMING_CPUS='')
            timings = []
            status, _ = REAL_ADMISSION(self.root, 'gate', [sys.executable, '-c', source], environment,
                                      lambda: True, timings=timings,
                                      limits=coordinator.ProcessLimits(.1 if expected else None),
                                      log_dir=self.root / ('.settle-logs-' + str(expected)))
            self.assertEqual(status, expected)
            self.assertEqual(timings[0]['log_errors'], [])
            with (slots / 'gate1.lock').open('a') as slot, (slots / 'admit.lock').open('a') as admission:
                fcntl.flock(slot, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(admission, fcntl.LOCK_EX | fcntl.LOCK_NB)
                # Leave no scheduler helper running when the private fixture ends.
                deadline = time.monotonic() + 10
                while True:
                    try:
                        fcntl.flock(admission, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        break
                    except BlockingIOError:
                        if time.monotonic() >= deadline:
                            self.fail('admission helper did not release its lock')
                        time.sleep(.02)

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
        self.assertEqual(self.execute(), 3)
        self.assertEqual(self.execute(), 3)
        self.assertEqual(self.states(), {'unit': 'fresh', 'docs': 'fresh'})
        self.assertEqual(self.receipts(), [])
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertFalse(report['success'])
        self.assertTrue(report['profile_coverage']['filtered_inventory'])

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
        report = coordinator.read_record(self.cache / 'last-run.json')
        diagnostic = report['stability_diagnostics']
        self.assertEqual(diagnostic['status'], 'observed')
        self.assertTrue(any('fixture.txt' in reason['name'] for reason in diagnostic['reasons']))
        self.assertTrue(any(reason['role'] == 'action_inputs' for reason in diagnostic['reasons']))

    def change_tool_during_resolution(self):
        calls = []
        def resolve(_zig, _environment):
            calls.append(True)
            if len(calls) == 2:
                original = self.tool.read_bytes()
                self.tool.write_bytes(b'changed during provider resolution')
                self.tool.write_bytes(original)
            return [], [self.zig, self.tool]
        self.stack.enter_context(patch.object(coordinator, 'tool_contract', side_effect=resolve))

    def test_tool_aba_during_warm_resolution_rejects_before_execution_or_reuse(self):
        with RetainedSession() as retained, retained.activate():
            self.assertEqual(self.execute(), 0)
            self.admissions.clear()
            self.change_tool_during_resolution()
            with self.assertRaises(coordinator.VerificationError) as caught:
                self.execute()
            self.assertEqual(caught.exception.status, coordinator.RETRY)
            self.assertEqual(self.admissions, [])
            self.assertFalse(coordinator.read_record(self.cache / 'last-run.json')['success'])

    def test_tool_aba_during_cold_resolution_rejects_before_native_work(self):
        self.change_tool_during_resolution()
        with self.assertRaises(coordinator.VerificationError):
            self.execute()
        self.assertEqual(self.events('plan'), [])
        self.assertEqual(self.receipts(), [])

    def test_failed_gate_preserves_failure_and_stability_diagnostics(self):
        self.write('.failure', '17')
        self.after_gate = lambda: self.input.write_text('changed during failed execution')
        self.assertEqual(self.execute(), 17)
        self.assertEqual(self.receipts(), [])
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertFalse(report['inputs_stable'])
        self.assertTrue(any('fixture.txt' in reason['name']
                            for reason in report['stability_diagnostics']['reasons']))

    def test_producer_fixture_closures_are_declared_verification_inputs(self):
        spec = importlib.util.spec_from_file_location(
            'producer_input_coverage', REPOSITORY / 'tests/test_inputs_coverage.py')
        coverage = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(coverage)
        declared = coverage.declared_lists((REPOSITORY / 'build_test_inputs.zig').read_text())
        entries = declared['verification_cache']
        for closure in coordinator.verification_producers.CLOSURES.values():
            for path in closure:
                self.assertTrue(coverage.covered(path, entries), path)
                narrowed = [entry for entry in entries if entry != path]
                self.assertFalse(coverage.covered(path, narrowed), path)

    def test_mutation_during_publication_rolls_back_all_new_success_receipts(self):
        save = coordinator.save_receipt

        def changed_publication(path, action_key):
            save(path, action_key)
            self.input.write_text('changed during publication')

        with patch.object(coordinator, 'save_receipt', side_effect=changed_publication):
            self.assertEqual(self.execute(), coordinator.RETRY)
        self.assertEqual(self.receipts(), [])

    def test_publication_exception_replaces_prior_success_report(self):
        self.assertEqual(self.execute(), 0)
        self.input.write_text('changed source')
        with patch.object(coordinator, 'save_receipt', side_effect=SnapshotError('lost publication authority')):
            with self.assertRaises(SnapshotError):
                self.execute()
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertFalse(report['success'])
        self.assertEqual(report['stage'], 'publication')
        self.assertEqual(report['status'], coordinator.RETRY)

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
        for selection in [True, ['units', 'units'], ['']]:
            invalid_selector = copy.deepcopy(self.plan)
            invalid_selector['groups'][0]['artifacts'] = selection
            cases.append(invalid_selector)
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

    def test_fixture_membership_coverage_cannot_be_declared_cacheable(self):
        self.plan['groups'].append(group('coverage', ['inputs/unit/'], True))
        self.plan['coverage'].update(required_actions=3, registered_actions=3)
        self.save_plan()
        with self.assertRaisesRegex(coordinator.VerificationError, 'coverage must always execute'):
            self.execute()
        self.assertEqual(self.events('gate'), [])
        self.plan['groups'][-1]['cacheable'] = False
        self.save_plan()
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused', 'coverage': 'fresh'})

    def test_coverage_verdict_changes_when_a_negative_fixture_lookup_becomes_present(self):
        specification = importlib.util.spec_from_file_location('coverage_fixture', REPOSITORY / 'tests/test_inputs_coverage.py')
        coverage = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(coverage)
        self.write('coverage-fixture/src/root.zig', 'test "fixture" {\n    _ = "experiments/new.my";\n}\n')
        inputs = self.write('coverage-fixture/build_test_inputs.zig', 'pub const root = [_][]const u8{"src/"};\n')
        fixture = self.root / 'coverage-fixture'
        with patch.object(coverage, 'ROOT', fixture), patch.object(coverage, 'INPUTS', inputs), \
                patch.object(coverage, 'ROOTS', {'src/root.zig': 'root'}):
            self.assertEqual(coverage.gaps(), [])
            self.write('coverage-fixture/experiments/new.my', 'func main() -> int: return 0\n')
            problems = coverage.gaps()
            self.assertEqual(len(problems), 1)
            self.assertIn('experiments/new.my', problems[0])

    def test_private_slot_handshake_revalidates_after_queue_and_never_launches_changed_worker(self):
        slots = self.root / '.slots'
        slots.mkdir()
        environment = dict(os.environ, MYLANG_SLOT_DIR=str(slots), MYLANG_GATE_SLOTS='1',
                           MYLANG_GATE_MEM='0', MYLANG_SLOT_POLL='1', MYLANG_SLOT_SETTLE='0',
                           MYLANG_TIMING_CPUS='')
        marker = self.root / '.worker-started'
        command = [sys.executable, '-c', 'from pathlib import Path; Path(__import__("sys").argv[1]).touch()', str(marker)]
        results, errors, timings = [], [], []
        with (slots / 'gate1.lock').open('w') as lock, Snapshot(self.root, ['inputs/unit/fixture.txt']) as snapshot:
            fcntl.flock(lock, fcntl.LOCK_EX)

            def admitted():
                try:
                    results.append(coordinator.run_admitted(self.root, 'gate', command, environment, snapshot.unchanged, timings=timings))
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
        self.assertEqual(len(timings), 1)
        self.assertEqual(timings[0]['worker_seconds'], 0)
        self.assertTrue(timings[0]['admitted'])
        self.assertGreater(timings[0]['admission_wait_seconds'], 0)
        self.assertEqual(list((slots / 'queue-gate').glob('*.wait')), [])



class CallerAuthentication(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='helper-auth-', dir=REPOSITORY / '.tmp')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / 'helper.py'
        self.source.write_bytes(Path(coordinator.code_identity.__file__).read_bytes())
        spec = importlib.util.spec_from_file_location('helper_auth_fixture', self.source)
        self.helper = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = self.helper
        spec.loader.exec_module(self.helper)
        self.addCleanup(sys.modules.pop, spec.name, None)
        for name, value in [('code_identity', self.helper), ('_CODE_HELPER_SOURCE_PROOF', None)]:
            replacement = patch.object(coordinator, name, value)
            replacement.start()
            self.addCleanup(replacement.stop)
        self.authenticate = coordinator.authenticate_code_identity

    def test_current_source_proof_is_cached_without_warm_file_reads(self):
        with contextlib.ExitStack() as stack:
            watched = stack.enter_context(Snapshot(self.root, [], [self.source]))
            snapshots = [watched]
            self.authenticate(self.root, watched, snapshots, stack)
            with patch.object(Path, 'open', side_effect=AssertionError('warm read')):
                self.authenticate(self.root, watched, snapshots, stack)
            self.assertIs(coordinator._CODE_HELPER_SOURCE_PROOF[0], self.helper._LOADED_CODE_OBJECT)
            self.assertTrue(watched.unchanged())

    def test_fake_root_attaches_actual_provider_authority_until_request_exit(self):
        fake = self.root / 'fake'
        fake.mkdir()
        with contextlib.ExitStack() as stack:
            watched = stack.enter_context(Snapshot(fake, []))
            snapshots = [watched]
            self.authenticate(fake, watched, snapshots, stack)
            self.assertEqual(len(snapshots), 2)
            provider = snapshots[-1]
            self.assertTrue(provider.unchanged())
            self.source.write_bytes(self.source.read_bytes().replace(b'_TEXT_CHUNK = 8192', b'_TEXT_CHUNK = 8193'))
            self.assertFalse(provider.unchanged())
        self.assertRaises(SnapshotError, provider.unchanged)

    def test_stale_helper_before_watch_is_rejected_even_with_fresh_source_capture(self):
        self.source.write_bytes(self.source.read_bytes().replace(b'_TEXT_CHUNK = 8192', b'_TEXT_CHUNK = 8193'))
        with contextlib.ExitStack() as stack:
            watched = stack.enter_context(Snapshot(self.root, [], [self.source]))
            self.assertTrue(watched.unchanged())
            self.assertRaisesRegex(self.helper.CodeIdentityError, 'does not match',
                                   self.authenticate, self.root, watched, [watched], stack)
            self.assertIsNone(coordinator._CODE_HELPER_SOURCE_PROOF)

    def test_proof_cache_compares_code_object_by_identity(self):
        with contextlib.ExitStack() as stack:
            watched = stack.enter_context(Snapshot(self.root, [], [self.source]))
            self.authenticate(self.root, watched, [watched], stack)
            original = self.helper._LOADED_CODE_OBJECT
            self.helper._LOADED_CODE_OBJECT = original.replace()
            self.assertEqual(self.helper._LOADED_CODE_OBJECT, original)
            self.assertIsNot(self.helper._LOADED_CODE_OBJECT, original)
            with patch.object(self.helper, 'authenticate_code_source', wraps=self.helper.authenticate_code_source) as authenticate:
                self.authenticate(self.root, watched, [watched], stack)
            self.assertEqual(authenticate.call_count, 1)
            self.assertIs(coordinator._CODE_HELPER_SOURCE_PROOF[0], self.helper._LOADED_CODE_OBJECT)

    def test_mismatched_watched_bytes_fail_even_when_current_code_would_match(self):
        with contextlib.ExitStack() as stack:
            watched = stack.enter_context(Snapshot(self.root, [], [self.source]))
            record = watched.identity['files'][0]
            record['sha256'] = '0' * 64
            with patch.object(watched, '_identity', {'files': [record]}):
                self.assertRaisesRegex(SnapshotError, 'during', self.authenticate,
                                       self.root, watched, [watched], stack)
            self.assertIsNone(coordinator._CODE_HELPER_SOURCE_PROOF)

    def test_missing_metadata_cannot_use_an_earlier_content_proof(self):
        with contextlib.ExitStack() as stack:
            watched = stack.enter_context(Snapshot(self.root, [], [self.source]))
            self.authenticate(self.root, watched, [watched], stack)
            record = watched.identity['files'][0]
            del record['size']
            with patch.object(watched, '_identity', {'files': [record]}):
                self.assertRaisesRegex(self.helper.CodeIdentityError, 'metadata', self.authenticate,
                                       self.root, watched, [watched], stack)

    def test_cache_never_authorizes_a_closed_or_dirty_request_snapshot(self):
        with contextlib.ExitStack() as stack:
            watched = stack.enter_context(Snapshot(self.root, [], [self.source]))
            self.authenticate(self.root, watched, [watched], stack)
            self.source.write_bytes(self.source.read_bytes() + b'\n')
            # A cached code/source relation cannot make this watch pass.
            self.authenticate(self.root, watched, [watched], stack)
            self.assertFalse(watched.unchanged())
        self.assertRaises(SnapshotError, self.authenticate, self.root, watched, [watched], contextlib.ExitStack())

REAL_ADMISSION = coordinator.run_admitted


if __name__ == '__main__':
    unittest.main()
