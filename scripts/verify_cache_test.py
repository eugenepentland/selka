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
import re
import shutil
import signal
import sqlite3
import select
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
    # .embed-root models DWARF: the bytes name the checkout. .producer holds a
    # version-3 producer declared for every native root.
    embedded=str(root).encode() if (root/'.embed-root').exists() else b''
    for name in ['selka','units','cli','core']:
        path=root/'zig-out/bin'/name; path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(b'fake-native-'+name.encode()+values.get(name,'').encode()+embedded); artifacts[name]=str(path)
    producer=json.loads((root/'.producer').read_text()) if (root/'.producer').exists() else None
    record={{'version':1,'artifacts':artifacts}} if producer is None else {{'version':3,'producers':{{}},
        'artifacts':{{name:{{'path':path,'producer':producer}} for name,path in artifacts.items()}}}}
    package=root/'zig-out/libexec/selka/components'; package.mkdir(parents=True,exist_ok=True)
    # .component-producer declares the components provider beside the others.
    if producer is not None and (root/'.component-producer').exists():
        record['artifacts']['components']={{'path':str(package/'test-index.json'),'producer':producer}}
    (root/'zig-out/verification/artifacts.json').write_text(json.dumps(record))
    for name in ['test-index','cache-plan']:
        (package/name).write_bytes(b'fake-component'+values.get('component:'+name,'').encode())
        (package/(name+'.json')).write_text(json.dumps({{'artifact':name}}))
elif (root/'.failure').exists():
    raise SystemExit(int((root/'.failure').read_text()))
elif (root/'.hold-gate').exists():
    import time
    (root/'.gate-started').touch()
    deadline=time.monotonic()+90
    while not (root/'.gate-release').exists():
        if time.monotonic() >= deadline:
            print('fixture gate release deadline', file=sys.stderr)
            raise SystemExit(25)
        time.sleep(.02)
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
        self.addCleanup(self.cleanup_fixture)
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
        admission_inputs = (
            'scripts/build-slot.sh', 'scripts/build_slot_legacy.sh',
            'scripts/build_admission.py', 'scripts/verification_code_identity.py',
            'scripts/verification/__init__.py', 'scripts/verification/scheduler.py',
        )
        for relative in admission_inputs:
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPOSITORY / relative, destination)
        self.plan = {'version': coordinator.INVENTORY_VERSION, 'required_targets': ['test', 'fmt-check'],
                     'groups': [group('unit', ['inputs/unit/']), group('docs', ['inputs/docs/'])],
                     'coverage': {'required_actions': 2, 'registered_actions': 2, 'unknown_actions': []}}
        self.save_plan()
        self.before_gate = None
        self.after_gate = None
        self.gate_status = None
        self.admissions = []
        self.revised = []
        self.child_diagnostics = []
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        # These fixtures replace coordinator functions in this process only.
        # A launcher's scheduler opt-in must never move mocked work into a real
        # detached interpreter; explicit subscription tests install their own
        # opt-in and transport. Real-process coverage lives separately below.
        self.stack.enter_context(patch.dict(os.environ, SELKA_ADMISSION_BACKEND='legacy'))
        self.addCleanup(self.report_failure_output)
        self.stack.enter_context(patch.object(coordinator, 'CONFIG_INPUTS', ['config.zig', 'build_test_inputs.zig']))
        self.stack.enter_context(patch.object(coordinator, 'PREPARE_INPUTS', ['sources/']))
        self.stack.enter_context(patch.object(coordinator, 'COORDINATOR_INPUTS', list(admission_inputs)))
        self.stack.enter_context(patch.object(coordinator, 'tool_contract', return_value=([], [self.zig, self.tool])))
        self.stack.enter_context(patch.object(coordinator, 'run_admitted', side_effect=self.admit))
        # Fake tools do not watch or authenticate the launcher's component seed
        # cache. Keep that ambient input outside these mock fixtures while
        # allowing tests to select it afterward.
        self.stack.enter_context(patch.dict(os.environ))
        os.environ.pop('SELKA_COMPONENT_CACHE', None)
        with Snapshot(self.root, coordinator.CONFIG_INPUTS) as configuration:
            self.qualified_configuration = copy.deepcopy(configuration.identity)
        # The fixture configuration consumes the lists nowhere: no reviewed sites.
        self.stack.enter_context(patch.object(coordinator, 'DECLARATIVE_CONSUMERS', ()))

    def report_failure_output(self):
        outcome = self._outcome
        result = None if outcome is None else outcome.result
        failed = result is not None and any(
            test is self or getattr(test, 'test_case', None) is self
            for test, _ in (*result.failures, *result.errors))
        if failed:
            for label, stdout, stderr in self.child_diagnostics:
                print(f"\n{self.id()} nested {label} stdout:\n{stdout}", file=sys.stderr)
                print(f"{self.id()} nested {label} stderr:\n{stderr}", file=sys.stderr)

    def cleanup_fixture(self):
        # Real admission intentionally outlives its command with a detached
        # diagnostic observer. Await only this fixture's observers before
        # removing the directory their final shadow log still belongs to.
        admission = coordinator.verification_measurement.build_admission
        script = str((self.root / 'scripts/build_admission.py').resolve()).encode()
        loaded_script = str(Path(admission.__file__).resolve()).encode()
        executable = Path(sys.executable).resolve()
        identity = admission.scheduler_backend.process_identity
        window_environment = {
            b'SELKA_SLOT_DIR': str((self.root / 'measurement-slots').resolve()).encode(),
            b'SELKA_ADMISSION_PARENT_PID': str(os.getpid()).encode(),
            b'SELKA_ADMISSION_PARENT_START': identity(os.getpid()).split(':')[-1].encode(),
        }

        def owned_observer(entry):
            argv = (entry / 'cmdline').read_bytes().rstrip(b'\0').split(b'\0')
            if (len(argv) != 4 or argv[1] != b'-B'
                    or argv[3] not in (b'--shadow-watch', b'--lease-watch')
                    or Path(os.fsdecode(argv[0])).resolve() != executable):
                return None
            if argv[2] == script:
                return tuple(argv), None
            if argv[2] != loaded_script:
                return None
            # Window uses the loaded client; require both this fixture's slot
            # directory and this exact test process's parent identity.
            selected = {}
            for item in (entry / 'environ').read_bytes().split(b'\0'):
                name, separator, value = item.partition(b'=')
                if separator and name in window_environment:
                    selected[name] = value
            if selected != window_environment:
                return None
            return tuple(argv), tuple(sorted(selected.items()))

        deadline = time.monotonic() + 240
        while True:
            found = False
            for entry in Path('/proc').iterdir():
                if not entry.name.isdigit():
                    continue
                try:
                    ownership = owned_observer(entry)
                    if ownership is None:
                        continue
                    pid = int(entry.name)
                    before = identity(pid)
                    if before is None:
                        continue
                    descriptor = os.pidfd_open(pid)
                except (FileNotFoundError, ProcessLookupError, PermissionError):
                    continue
                try:
                    if identity(pid) != before or owned_observer(entry) != ownership:
                        continue
                    found = True
                    remaining = deadline - time.monotonic()
                    self.assertGreater(remaining, 0, f'fixture observer still active: {before}')
                    self.assertTrue(select.select([descriptor], [], [], remaining)[0],
                                    f'fixture observer did not exit: {before}')
                except (FileNotFoundError, ProcessLookupError, PermissionError):
                    pass
                finally:
                    os.close(descriptor)
            if not found:
                break
        self.temporary.cleanup()

    def write(self, relative, data):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)
        return path

    def save_plan(self):
        self.plan.setdefault('configuration', {'filtered': False, 'rerun': False, 'optimize': 'Debug', 'proofs': True})
        self.plan['configuration'].setdefault('rerun', False)
        self.plan['configuration'].setdefault('optimize', 'Debug')
        self.plan['configuration'].setdefault('proofs', True)
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
        if kind == 'gate':
            self.gate_environment, self.gate_controls = env, controls
        if kind == 'gate' and self.before_gate:
            self.before_gate()
        if kind == 'build' and getattr(self, 'on_build', None) is not None:
            ended = self.on_build(argv, controls)
            if ended is not None:
                return ended, 0.0
        if not unchanged():
            if timings is not None:
                timings.append({'kind': kind, 'status': coordinator.RETRY, 'admitted': True, 'worker_started': False,
                                'admission_wait_seconds': 0.0, 'validation_seconds': 0.0, 'worker_seconds': 0.0,
                                'observed_held_seconds': 0.0, 'elapsed_seconds': 0.0})
            return coordinator.RETRY, 0.0
        if controls.get('revise') is not None:
            # As the real handshake does: after revalidation, before any work.
            argv = controls['revise']()
            self.revised.append(argv)
            if argv is None:
                return 0, 0.0
        rerun = any('verification_rerun.py' in str(word) for word in argv)
        if kind == 'gate' and self.gate_status is not None and not rerun:
            if timings is not None:
                timings.append({'kind': kind, 'status': self.gate_status, 'admitted': True, 'worker_started': True,
                                'admission_wait_seconds': 0.0, 'validation_seconds': 0.0, 'worker_seconds': 0.0,
                                'observed_held_seconds': 0.0, 'elapsed_seconds': 0.0})
            return self.gate_status, 0.0
        child = subprocess.run(argv, cwd=root, env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, timeout=60, text=True)
        self.child_diagnostics.append((kind, child.stdout, child.stderr))
        # As the real `run_admitted` does while a sent command runs: poll the input watches (always for a build; for
        # the gate when a test asks), marking a trip as the real one marks it.
        if controls.get('heartbeat') is not None and (kind == 'build' or getattr(self, 'heartbeat_gate', False)):
            if kind == 'gate' and self.after_gate:
                self.after_gate()
            try:
                for _ in range(3):  # the real loop polls every 20 ms while the command runs
                    controls['heartbeat']()
                    time.sleep(.01)
            except BaseException as error:
                coordinator.mark_action_started(error, kind, True)
                raise
        status = child.returncode
        if kind == 'gate' and self.after_gate:
            self.after_gate()
        if controls.get('finalize') is not None:
            status = controls['finalize'](status, lambda: True)
        if timings is not None:
            timings.append({'kind': kind, 'status': status, 'admitted': True, 'worker_started': True,
                            'admission_wait_seconds': 0.0, 'validation_seconds': 0.0,
                            'worker_seconds': 0.0, 'observed_held_seconds': 0.0, 'elapsed_seconds': 0.0})
        return status, 0.0

    def execute(self, options=None, force=False, shared=None, **controls):
        stdout, stderr = io.StringIO(), io.StringIO()
        try:
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                return coordinator.execute(self.root, self.cache, self.zig, options or ['-j3'], force, shared, **controls)
        finally:
            self.child_diagnostics.append(('coordinator', stdout.getvalue(), stderr.getvalue()))

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

    FAILED_TEST_ROW = {'test_id': 'root::lazy.audit', 'state': 'failed', 'elapsed_ns': 5,
                       'elapsed_scope': 'runner-protocol-interval', 'started_monotonic_ns': 1, 'ended_monotonic_ns': 6}
    BEACON = ("error: 'root::lazy.audit' failed\nexpected: nothing\nat src/lazy_readers_test.zig:30\n"
              "failed command: python3 scripts/verification_native_telemetry.py --action-id unit --member 0 --root-id root -- ./t\n")

    def fail_the_gate_early(self):
        """The gate hook of a fail-fast request: a step fails, leaves its beacon and partial rows, and the build is ended."""
        directory = Path(self.gate_environment['SELKA_VERIFICATION_TELEMETRY_DIR'])
        coordinator.verification_telemetry.write_document(directory / 'unit.member.0.json', {
            'version': 1, 'producer': 'zig-test-protocol-v1', 'action_id': 'unit', 'member_id': 'unit/member/0',
            'selected': 1, 'complete': False, 'tests': [self.FAILED_TEST_ROW], 'runner_interval': None,
            'timed_out': False, 'elapsed_scope': 'runner-protocol-interval', 'body_duration_ns': None,
            'selection_scope': 'actual-client-dispatch', 'malformed': False})
        (directory / 'fail-fast.unit.member.0.txt').write_text(self.BEACON)
        log = self.cache / 'last-logs/gate/stderr.log'
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text('BrokenPipeError: the killed build said this before the stop\n')
        stop = self.gate_controls['stop']
        self.assertTrue(stop(), 'the watch sees the beacon')
        stop.killed = True
        self.gate_status = coordinator.verification_process.FAIL_FAST_STATUS

    # ---- a test that fails and then passes alone (item 4d, decision D5) ------------------------------------------
    def flaky_gate(self, tests, *, passes_alone=(), hang=False, log_text=None, skips_alone=(), summary=True, tail=''):
        """A gate whose build fails on `tests` (action `unit`, member 0): its tree marks the member, its build summary
        counts one failed step, its telemetry names the tests, and its launcher's rerun record points at a stand-in test
        launcher that reports each test passed (`passes_alone`), skipped (`skips_alone`) or failed, as the real Python
        launcher does (exit status and telemetry document), or hangs past a 1 s deadline."""
        for name in ('verification_rerun.py', 'verification_telemetry.py'):
            shutil.copy2(REPOSITORY / 'scripts' / name, self.root / 'scripts' / name)
        runner = self.write('scripts/fake_test_runner.py', 'import json, os, sys, time\n'
                            'test = sys.argv[-1]\nopen(%r, "a").write(test + "\\n")\n'
                            'time.sleep(30 if %r else 0)\n'
                            'state = "passed" if test in %r else "skipped" if test in %r else "failed"\n'
                            'folder = os.environ["SELKA_VERIFICATION_TELEMETRY_DIR"]\n'
                            'open(os.path.join(folder, "unit.member.0.json"), "w").write(json.dumps({"tests": '
                            '[{"test_id": test, "state": state}]}))\n'
                            'sys.exit(1 if state == "failed" else 0)\n'
                            % (str(self.root / '.reruns'), hang, sorted(passes_alone), sorted(skips_alone)))
        self.flaky_log = self.root / '.flaky' / 'flaky.jsonl'
        import verification_rerun
        self.stack.enter_context(patch.object(verification_rerun, 'flaky_log_path', return_value=self.flaky_log))
        written = []

        def gate():
            if written:
                return
            written.append(True)
            directory = Path(self.gate_environment['SELKA_VERIFICATION_TELEMETRY_DIR'])
            rows = [dict(self.FAILED_TEST_ROW, test_id=name, state=state) for name, state in tests]
            coordinator.verification_telemetry.write_document(directory / 'unit.member.0.json', {
                'version': 1, 'producer': 'zig-test-protocol-v1', 'action_id': 'unit', 'member_id': 'unit/member/0',
                'selected': len(rows), 'complete': True, 'tests': rows, 'runner_interval': None, 'timed_out': False,
                'elapsed_scope': 'runner-protocol-interval', 'body_duration_ns': None,
                'selection_scope': 'actual-client-dispatch', 'malformed': False})
            env = dict(os.environ, SELKA_TEST_DEADLINE_SECONDS='1') if hang else dict(os.environ)
            coordinator.verification_telemetry.record_rerun(directory, 'unit', 0, 'python',
                                                            argv=[sys.executable, str(runner), 'unit_module'],
                                                            cwd=str(self.root), env=env, extra={'tests': ['unit_module']})
            failed = sum(state != 'passed' for _name, state in tests)
            text = ('test\n+- verification action unit member 0 1 pass, %d fail (%d total)\n' % (failed, failed + 1)
                    + (log_text or ''))
            if summary:
                text += 'Build Summary: 3/4 steps succeeded (1 failed); 1/%d tests passed (%d failed)\n' % (failed + 1, failed)
            text += tail  # what comes after the build's own output: the supervisor's report
            log = self.cache / 'last-logs/gate/stderr.log'
            log.parent.mkdir(parents=True, exist_ok=True)
            log.write_text(text)
        self.before_gate = gate
        self.gate_status = 1

    def reruns(self):
        path = self.root / '.reruns'
        return path.read_text().splitlines() if path.exists() else []

    def test_a_test_that_fails_once_and_passes_alone_passes_the_gate_names_it_and_logs_it(self):
        self.flaky_gate([('root::flaky.one', 'failed')], passes_alone={'root::flaky.one'})
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.reruns(), ['root::flaky.one'])
        self.assertEqual(self.receipts(), [], 'a verdict that needed a second try records no receipt')
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertTrue(report['success'])
        self.assertTrue(report['flaky']['passed'])
        output = self.child_diagnostics[-1][1]
        self.assertIn('verification: PASS', output)
        self.assertIn('1 flaky test(s) passed when rerun alone', output)
        self.assertIn('flaky: unit root::flaky.one failed in the gate and passed alone', output)
        entry = json.loads(self.flaky_log.read_text().splitlines()[-1])
        self.assertEqual((entry['action'], entry['test'], entry['worktree']), ('unit', 'root::flaky.one', str(self.root)))
        for field in ('time', 'head', 'failure', 'rerun_seconds', 'load', 'full_avg60', 'swap_free_kb', 'f22'):
            self.assertIn(field, entry)

    def test_a_memory_overshoot_beside_a_flaky_test_does_not_stop_the_rerun(self):
        # A peak over a step's declared memory bound fails no step (the build counts it as succeeded), so it does not make
        # a gate ineligible: as on main, it changes no verdict (13 November, `unit` member 5).
        overshoot = ('verification-unit\n+- verification action unit member 5 failure\n'
                     'error: memory usage peaked at 1.53GB (1528537088 bytes), exceeding the declared upper bound of 0.40GB '
                     '(402653184 bytes)\nfailed command: cd . && python3 scripts/verification_native_telemetry.py x\n')
        self.flaky_gate([('root::flaky.one', 'failed')], passes_alone={'root::flaky.one'}, log_text=overshoot)
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.reruns(), ['root::flaky.one'])
        self.assertIn('note: unit member 5 exceeded its declared memory bound', self.child_diagnostics[-1][1])

    # D-DL4-19: eligibility is proven, never assumed. The review's reproductions end "not eligible".
    def test_a_crashed_member_beside_a_flake_is_not_eligible(self):
        crashed = ('+- verification action unit member 1 failure\nerror: the test runner crashed\n'
                   'failed command: python3 scripts/verification_native_telemetry.py --action-id unit --member 1 -- x\n')
        self.flaky_gate([('root::flaky.one', 'failed')], passes_alone={'root::flaky.one'}, log_text=crashed, summary=False)
        self.gate_text_extra = 'Build Summary: 2/4 steps succeeded (2 failed); 1/3 tests passed (1 failed)\n'
        before = self.before_gate

        def gate():
            before()
            log = self.cache / 'last-logs/gate/stderr.log'
            log.write_text(log.read_text() + self.gate_text_extra)
        self.before_gate = gate
        self.assertEqual(self.execute(), 1)
        self.assertEqual(self.reruns(), [])
        self.assertIn('no flaky rerun: unit member 1 failed with no failed test of its own', self.child_diagnostics[-1][1])

    def test_a_member_whose_tree_line_counts_a_crash_is_not_eligible(self):
        self.flaky_gate([('root::flaky.one', 'failed')], passes_alone={'root::flaky.one'},
                        log_text='+- verification action unit member 0 3 pass, 1 fail, 1 crash (5 total)\n')
        self.assertEqual(self.execute(), 1)
        self.assertEqual(self.reruns(), [])
        self.assertIn('reports a crash, a timeout or a leak', self.child_diagnostics[-1][1])

    def test_a_log_with_no_build_summary_is_not_eligible(self):
        self.flaky_gate([('root::flaky.one', 'failed')], passes_alone={'root::flaky.one'}, summary=False)
        self.assertEqual(self.execute(), 1)
        self.assertEqual(self.reruns(), [])
        self.assertIn('no flaky rerun: the build printed no summary', self.child_diagnostics[-1][1])

    def test_a_build_runner_that_was_killed_is_not_rerun(self):
        self.flaky_gate([('root::flaky.one', 'failed')], passes_alone={'root::flaky.one'})
        self.gate_status = 137
        self.assertEqual(self.execute(), 137)
        self.assertEqual(self.reruns(), [])

    def test_a_failed_build_step_or_a_leftover_beside_a_flake_is_not_eligible(self):
        for extra, reason in (('+- compile exe selka debug native 1 errors\n', 'a build step that runs no test failed'),
                              ('supervisor: leftover pid=7 ppid=1 sid=7 state=S cmd=sleep 60\n', 'a process outlived its action'),
                              ('test deadline: x ran 301.0 s (limit 300.0 s); killed\n', 'a deadline killed a test or a step')):
            with self.subTest(reason=reason):
                self.input.write_text(reason)
                # The supervisor reports when the build has ended: after its summary. The others are build output.
                where = dict(tail=extra) if extra.startswith('supervisor:') else dict(log_text=extra)
                self.flaky_gate([('root::flaky.one', 'failed')], passes_alone={'root::flaky.one'}, **where)
                self.assertEqual(self.execute(), 1)
                self.assertIn('no flaky rerun: ' + reason, self.child_diagnostics[-1][1])
        self.assertEqual(self.reruns(), [])

    def test_a_leftover_names_its_process_and_the_test_whose_directory_it_runs_in(self):
        leftover = ('supervisor: 1 descendant(s) outlived the closeout\n'
                    'supervisor: leftover pid=7 ppid=1 sid=7 state=D started=01:56:54Z age=14.9s '
                    'cwd=%s/.tmp/slot-test-fkoxuvs3/over cmd=python3 -B build_admission.py --shadow-watch\n' % self.root)
        self.write('scripts/owner_test.py', 'import tempfile\ntempfile.TemporaryDirectory(prefix="slot-test-", dir=None)\n')
        self.input.write_text('owner')
        self.flaky_gate([('root::flaky.one', 'failed')], passes_alone={'root::flaky.one'}, tail=leftover)
        self.assertEqual(self.execute(), 1)
        message = self.child_diagnostics[-1][1]
        self.assertIn('no flaky rerun: a process outlived its action (leftover pid=7 ppid=1', message)
        self.assertIn('--shadow-watch', message)
        self.assertIn('its directory belongs to scripts/owner_test.py', message)
        self.assertEqual(self.reruns(), [])

    def test_a_supervisor_report_quoted_in_a_failing_test_is_not_a_leftover_of_the_action(self):
        # The test that runs a supervisor of its own quotes its report in its failure message. The helper was killed by
        # that supervisor before the test ended: nothing outlived the action, and the failed test is rerun alone.
        quoted = ('AssertionError: 125 != 0 : build-slot: build slot 1, FIFO ticket 1 after 12.418s\n'
                  'supervisor: 1 descendant(s) outlived the closeout\n'
                  'supervisor: leftover pid=7 ppid=1 sid=7 state=D started=01:56:54Z age=14.9s cwd=/x cmd=sleep 60\n')
        self.input.write_text('quoted')
        self.flaky_gate([('root::flaky.one', 'failed')], passes_alone={'root::flaky.one'}, log_text=quoted)
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.reruns(), ['root::flaky.one'])

    def test_a_test_that_skips_when_run_alone_did_not_pass(self):
        self.flaky_gate([('root::flaky.one', 'failed')], skips_alone={'root::flaky.one'})
        self.assertEqual(self.execute(), 1)
        self.assertIn('rerun alone: unit root::flaky.one failed again', self.child_diagnostics[-1][1])

    def test_the_rerun_phase_is_bounded_and_holds_no_per_action_lock(self):
        shared = self.root / '.shared-evidence'
        self.flaky_gate([('root::flaky.one', 'failed')], passes_alone={'root::flaky.one'})
        held = []
        seen = {}
        original = coordinator.fuzz_campaign_store.Store.coordinator_lock

        @contextlib.contextmanager
        def counted(store, family):
            with original(store, family):
                held.append(family)
                try:
                    yield
                finally:
                    held.remove(family)
        self.stack.enter_context(patch.object(coordinator.fuzz_campaign_store.Store, 'coordinator_lock', counted))
        admit = self.admit

        def watching(root, kind, argv, env, unchanged, timings=None, **controls):
            if any('verification_rerun.py' in str(word) for word in argv):
                seen.update(limit=controls['limits'].timeout_seconds, held=list(held))
            return admit(root, kind, argv, env, unchanged, timings, **controls)
        self.stack.enter_context(patch.object(coordinator, 'run_admitted', side_effect=watching))
        self.assertEqual(self.execute(shared=shared), 0)
        self.assertEqual(seen, {'limit': coordinator.FLAKY_PHASE_SECONDS, 'held': []})

    def test_a_flake_is_logged_only_when_the_verdict_stands(self):
        self.flaky_gate([('root::flaky.one', 'failed')], passes_alone={'root::flaky.one'})
        admit = self.admit

        def changing(root, kind, argv, env, unchanged, timings=None, **controls):
            result = admit(root, kind, argv, env, unchanged, timings, **controls)
            if any('verification_rerun.py' in str(word) for word in argv):
                self.input.write_text('edited during the rerun')
            return result
        self.stack.enter_context(patch.object(coordinator, 'run_admitted', side_effect=changing))
        self.assertEqual(self.execute(), coordinator.RETRY)
        self.assertFalse(self.flaky_log.exists(), 'a gate that ends RETRY logs no flake')

    def test_a_test_that_fails_again_alone_fails_the_gate(self):
        self.flaky_gate([('root::real.one', 'failed')])
        self.assertEqual(self.execute(), 1)
        self.assertIn('rerun alone: unit root::real.one failed again', self.child_diagnostics[-1][1])
        self.assertFalse(self.flaky_log.exists())

    def test_two_flaky_tests_and_one_real_failure_fail_the_gate_and_say_which(self):
        self.flaky_gate([('root::a', 'failed'), ('root::b', 'failed'), ('root::c', 'failed')], passes_alone={'root::a', 'root::b'})
        self.assertEqual(self.execute(), 1)
        output = self.child_diagnostics[-1][1]
        self.assertIn('rerun alone: unit root::a passed', output)
        self.assertIn('rerun alone: unit root::c failed again', output)
        self.assertEqual(sorted(self.reruns()), ['root::a', 'root::b', 'root::c'])

    def test_more_failing_tests_than_the_limit_are_not_rerun(self):
        names = [('root::t%d' % index, 'failed') for index in range(coordinator.FLAKY_MAX + 1)]
        self.flaky_gate(names, passes_alone={name for name, _ in names})
        self.assertEqual(self.execute(), 1)
        self.assertEqual(self.reruns(), [])
        self.assertIn('no flaky rerun: 6 failing tests (more than 5)', self.child_diagnostics[-1][1])

    def test_a_timed_out_test_is_not_rerun(self):
        self.flaky_gate([('root::slow', 'timed_out')], passes_alone={'root::slow'})
        self.assertEqual(self.execute(), 1)
        self.assertEqual(self.reruns(), [])
        self.assertIn('no flaky rerun: unit member 0 has a test that timed out', self.child_diagnostics[-1][1])

    def test_a_rerun_that_hangs_ends_at_the_test_s_own_deadline_and_fails(self):
        self.flaky_gate([('root::hangs', 'failed')], passes_alone={'root::hangs'}, hang=True)
        began = time.monotonic()
        self.assertEqual(self.execute(), 1)
        self.assertLess(time.monotonic() - began, 20)
        row = coordinator.read_record(self.cache / 'last-run.json')['flaky']['tests'][0]
        self.assertTrue(row['timed_out'])

    def test_the_option_and_the_switch_keep_the_strict_verdict(self):
        self.flaky_gate([('root::flaky.one', 'failed')], passes_alone={'root::flaky.one'})
        self.assertEqual(self.execute(flaky_rerun=False), 1)
        self.input.write_text('changed')
        with patch.object(coordinator, 'FLAKY_RERUN', False):
            self.assertEqual(self.execute(), 1)
        self.assertEqual(self.reruns(), [])

    def test_a_failure_that_names_no_test_is_not_rerun(self):
        self.gate_status = 1
        self.assertEqual(self.execute(), 1)
        self.assertNotIn('flaky', coordinator.read_record(self.cache / 'last-run.json'))
        self.flaky_gate([('root::flaky.one', 'failed')], passes_alone={'root::flaky.one'},
                        log_text='verification-docs\n+- verification action docs member 0 failure\nerror: boom\n'
                                 'failed command: python3 tests/docs.py\n')
        self.input.write_text('changed')
        self.assertEqual(self.execute(), 1, 'the docs action failed with no failing test, so nothing is rerun')
        self.assertEqual(self.reruns(), [])

    def test_a_failing_guest_test_is_rerun_with_its_file_forced_in_a_private_cache(self):
        self.plan['groups'].append(group('language', ['inputs/unit/']))
        self.plan['groups'][-1]['label'] = 'selka test tests/lang --verify-facts (leak check)'
        self.plan['coverage'].update(required_actions=3, registered_actions=3)
        self.save_plan()
        self.write('tests/lang/a04_area.selka', 'x\n')
        compiler = self.write('tools/fake-selka', '#!%s\nimport json, sys\nopen(%r, "a").write(" ".join(sys.argv[1:]) + "\\n")\n'
                              'print(json.dumps({"version": "native-tests-v1", "tests": [{"name": "a04_area::test_x", '
                              '"status": "passed"}]}))\n' % (sys.executable, str(self.root / '.guest-reruns')))
        compiler.chmod(0o755)
        log = ('verification-language\n+- verification action language member 0 failure\nerror: process exited with code 1\n'
               'failed command: env SELKA_CORE_LEAKCHECK=1 python3 scripts/test_lang.py\n'
               '{"version":"native-tests-v1","tests":[{"name":"a04_area::test_x","status":"failed","reason":"expected true",'
               '"at":""},{"name":"a04_area::test_y","status":"passed"}]}\n'
               'Build Summary: 3/4 steps succeeded (1 failed); 1/2 tests passed (1 failed)\n')
        for name in ('verification_rerun.py', 'verification_telemetry.py'):
            shutil.copy2(REPOSITORY / 'scripts' / name, self.root / 'scripts' / name)
        import verification_rerun
        flaky_log = self.root / '.flaky' / 'flaky.jsonl'
        self.stack.enter_context(patch.object(verification_rerun, 'flaky_log_path', return_value=flaky_log))

        def gate():
            directory = Path(self.gate_environment['SELKA_VERIFICATION_TELEMETRY_DIR'])
            coordinator.verification_telemetry.record_rerun(directory, 'language', 0, 'guest', argv=[], cwd=str(self.root),
                extra={'compiler': str(compiler), 'suite': 'tests/lang',
                       'arguments': ['--verify-facts', '--cache-dir', '.c', '--emit-certificates', 'x', '--force']})
            path = self.cache / 'last-logs/gate/stderr.log'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(log)
            self.before_gate = None
        self.before_gate = gate
        self.gate_status = 1
        self.assertEqual(self.execute(), 0)
        words = (self.root / '.guest-reruns').read_text().split()
        self.assertEqual(words[:5], ['test', 'tests/lang/a04_area.selka', '--filter', 'test_x', '--verify-facts'])
        self.assertIn('--force', words)
        self.assertNotIn('.c', words, 'the gate cache must not answer for the rerun')
        self.assertEqual(json.loads(flaky_log.read_text())['test'], 'a04_area::test_x')

    def fake_shadow(self, sleep=0.0, output='shadow: head abc, selected 3, failed in gate 1, missed 0', code=0):
        """A stand-in `edit_check_shadow.py` in the fixture's tree: it records its arguments at once, then sleeps,
        prints and exits as told."""
        calls = self.root / '.shadow-calls'
        self.write('scripts/edit_check_shadow.py', 'import json, sys, time\n'
                   'open(%r, "a").write(json.dumps(sys.argv[1:]) + "\\n")\ntime.sleep(%r)\n'
                   'sys.stdout.buffer.write(%r)\nopen(%r, "a").write("done\\n")\nsys.exit(%d)\n'
                   % (str(calls), sleep, output.encode() + b'\xff\n', str(calls) + '.done', code))
        # A detached shadow must not outlive its test (the gate's supervisor would report it as a leftover).
        self.addCleanup(self.shadow_done, calls)
        return calls

    def shadow_done(self, calls):
        deadline = time.monotonic() + 60
        while calls.exists() and not Path(str(calls) + '.done').exists() and time.monotonic() < deadline:
            time.sleep(.1)

    def shadow_calls(self, calls, wait=0.0):
        deadline = time.monotonic() + wait
        while not calls.exists() and time.monotonic() < deadline:
            time.sleep(.05)
        return [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []

    def test_a_gate_that_fails_on_a_test_starts_the_shadow_detached_and_does_not_wait_for_it(self):
        calls = self.fake_shadow(sleep=20.0, code=3)
        self.before_gate = self.fail_the_gate_early
        began = time.monotonic()
        self.assertEqual(self.execute_restarting(fail_fast=True, flaky_rerun=False), 1)
        self.assertLess(time.monotonic() - began, 15.0, 'the gate does not wait for its 20 s shadow')
        output = self.child_diagnostics[-1][1]
        self.assertIn('verification: recording whether the edit check would have selected the failing test (1)', output)
        recorded = self.shadow_calls(calls, wait=60.0)
        self.assertEqual(len(recorded), 1)
        self.assertIn('root::lazy.audit', recorded[0])
        self.assertEqual(recorded[0][recorded[0].index('--unlisted') + 1], '0')
        self.assertFalse(coordinator.read_record(self.cache / 'last-run.json')['success'])

    def test_a_passing_gate_and_the_other_failure_kinds_start_no_shadow(self):
        calls = self.fake_shadow()
        self.assertEqual(self.execute_restarting(), 0)
        self.input.write_text('changed')
        self.gate_status = 125
        self.assertEqual(self.execute_restarting(), 125)
        self.input.write_text('changed again')
        self.gate_status = 1  # a failed step that names no test (a driver, a build)
        self.assertEqual(self.execute_restarting(), 1)
        self.assertEqual(self.shadow_calls(calls, wait=1.0), [])
        self.assertNotIn('edit check would have selected', '\n'.join(item[1] for item in self.child_diagnostics))

    def test_more_failed_tests_than_the_list_holds_are_counted(self):
        calls = self.fake_shadow()
        self.stack.enter_context(patch.object(coordinator, 'SHADOW_MAX_NAMES', 0))
        self.before_gate = self.fail_the_gate_early
        self.assertEqual(self.execute_restarting(fail_fast=True, flaky_rerun=False), 1)
        recorded = self.shadow_calls(calls, wait=60.0)[0]
        self.assertEqual((recorded[recorded.index('--unlisted') + 1], '--failed' in recorded), ('1', False))

    # ---- changed inputs restart the request (DL-4 item 4c) --------------------------------------------------------
    def execute_restarting(self, **controls):
        stdout, stderr = io.StringIO(), io.StringIO()
        try:
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                return coordinator.execute_with_restarts(self.root, self.cache, self.zig, ['-j3'], False, None, **controls)
        finally:
            self.child_diagnostics.append(('coordinator', stdout.getvalue(), stderr.getvalue()))

    def change_during_preparation(self, times, path='sources/compiler.txt'):
        """The first `times` preparation builds each change `path` while they run, as an editor would."""
        builds = []

        def build(argv, controls):
            if 'verification-prepare' in argv:
                builds.append(argv)
                if len(builds) <= times:
                    (self.root / path).write_text('edited %d' % len(builds))
            return None
        self.on_build = build
        return builds

    def test_inputs_changed_before_any_action_take_a_new_snapshot_and_the_verdict_is_a_fresh_one(self):
        builds = self.change_during_preparation(1)
        self.assertEqual(self.execute_restarting(), 0)
        self.assertEqual(len(builds), 2, 'the preparation is redone against the new snapshot')
        self.assertEqual(len(self.events('gate')), 1)
        self.assertEqual(len(self.receipts()), 2)
        output = self.child_diagnostics[-1][1]
        self.assertIn('verification: sources/compiler.txt changed before any action started', output)
        self.assertIn('restart 1 of 2', output)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertTrue(report['success'])
        self.assertEqual([item['path'] for item in report['restarts']], ['sources/compiler.txt'])
        self.assertIn('restarted 1 time(s): sources/compiler.txt changed', output)

    def test_inputs_changed_while_the_gate_was_queued_restart_too(self):
        edits = []

        def queued():
            if not edits:
                edits.append(True)
                self.input.write_text('edited while queued')
        self.before_gate = queued
        self.assertEqual(self.execute_restarting(), 0)
        self.assertEqual(len(self.events('gate')), 1, 'the first gate command was never sent')
        self.assertIn('changed before any action started (inputs changed while the gate was queued)',
                      self.child_diagnostics[-1][1])

    def test_the_disk_wait_happens_only_before_an_admission_the_request_needs(self):
        pressure = self.root / '.pressure'
        pressure.write_text('full avg10=1.00 avg60=60.00 avg300=1.00 total=1\n')
        self.stack.enter_context(patch.object(coordinator, 'PRESSURE_FILE', pressure))
        self.stack.enter_context(patch.object(coordinator, 'DISK_WAIT_SECONDS', 0.0))
        first = coordinator.DiskWaiter()
        self.assertEqual(self.execute_restarting(disk_waiter=first), 0)
        self.assertTrue(first.result['gave_up'], 'a request that needs admission waited (bound 0 s here)')
        self.assertIn('starting under disk pressure', self.child_diagnostics[-1][1])
        reused = coordinator.DiskWaiter()
        self.assertEqual(self.execute_restarting(disk_waiter=reused), 0)
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})
        self.assertIsNone(reused.result, 'a fully reused request asks for no admission and waits for nothing')

    def test_a_change_once_the_gate_command_was_sent_never_restarts(self):
        self.heartbeat_gate = True
        self.after_gate = lambda: self.input.write_text('edited while the gate ran')
        with self.assertRaisesRegex(SnapshotError, 'inputs changed while awaiting admitted work') as raised:
            self.execute_restarting()
        self.assertTrue(raised.exception.verification_action_started)
        self.assertEqual(len(self.events('gate')), 1)
        self.assertNotIn('taking a new snapshot', self.child_diagnostics[-1][1])
        self.assertFalse(coordinator.restartable(raised.exception, [{'name': 'inputs/unit/fixture.txt', 'role': 'action_inputs'}],
                                                 self.root))

    def test_a_trip_during_the_cheap_checks_restarts(self):
        mode = ['pass']

        def check(context):
            if mode[0] != 'trip':
                return []
            mode[0] = 'pass'
            time.sleep(1.0)  # past the lookup, so the action inputs' watch is in place
            self.input.write_text('edited while the cheap checks ran')
            return [coordinator.gate_cheap_checks.Finding('zig-format', 'zig fmt would change this line', 'src/x.zig:3')]
        self.plan['groups'].append(group('zig-format', ['inputs/unit/']))
        self.plan['coverage'].update(required_actions=3, registered_actions=3)
        self.save_plan()
        self.stack.enter_context(patch.dict(coordinator.gate_cheap_checks.RUNNERS, {'zig-format': check}))
        self.assertEqual(self.execute_restarting(), 0)
        mode[0] = 'trip'
        self.input.write_text('a new input, so zig-format runs while the preparation is reused')
        self.assertEqual(self.execute_restarting(), 0)
        self.assertIn('changed before any action started (inputs changed during the cheap checks)',
                      self.child_diagnostics[-1][1])

    def test_a_change_to_the_coordinator_s_own_code_or_interpreter_does_not_restart_in_process(self):
        error = coordinator.InputsChanged('inputs changed while the artifacts were prepared')
        self.assertFalse(coordinator.restartable(error, [{'name': 'scripts/verify_cache.py', 'role': 'coordinator'}], REPOSITORY))
        self.assertFalse(coordinator.restartable(error, [{'name': sys.executable, 'role': 'tools'}], REPOSITORY))
        self.assertTrue(coordinator.restartable(error, [{'name': 'tests/lang/README.md', 'role': 'preparation_sources'}], REPOSITORY))

    def test_inputs_changed_twice_restart_twice(self):
        builds = self.change_during_preparation(2)
        self.assertEqual(self.execute_restarting(), 0)
        self.assertEqual(len(builds), 3)
        self.assertIn('restart 2 of 2', self.child_diagnostics[-1][1])

    def test_a_third_change_fails_the_request_with_every_changed_path(self):
        self.change_during_preparation(3)
        with self.assertRaisesRegex(coordinator.VerificationError, 'inputs changed 3 times before any action started '
                                    r'\(sources/compiler.txt, sources/compiler.txt, sources/compiler.txt\)') as raised:
            self.execute_restarting()
        self.assertEqual(raised.exception.status, coordinator.RETRY)
        self.assertEqual(self.events('gate'), [])
        self.assertEqual(self.receipts(), [])
        self.assertEqual(len(coordinator.read_record(self.cache / 'last-run.json')['restarts']), 3)

    def test_inputs_changed_after_an_action_started_fail_as_before_and_name_the_path(self):
        self.after_gate = lambda: self.input.write_text('edited while the gate ran')
        self.assertEqual(self.execute_restarting(), coordinator.RETRY)
        self.assertEqual(len(self.events('gate')), 1)
        self.assertEqual(self.receipts(), [])
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertNotIn('restarts', report)
        self.assertIn('inputs/unit/fixture.txt', self.child_diagnostics[-1][1] + self.child_diagnostics[-1][2])

    def test_a_changed_tool_restarts_like_any_input_and_one_switch_reverses_that(self):
        self.change_during_preparation(1, path='tools/dependency')
        self.assertEqual(self.execute_restarting(), 0)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual([(item['path'], item['role']) for item in report['restarts']], [('tools/dependency', 'tools')])
        self.write('sources/compiler.txt', 'a new source, so the preparation builds again')
        self.change_during_preparation(1, path='tools/dependency')
        with patch.object(coordinator, 'RESTART_ON_TOOL_CHANGE', False):
            with self.assertRaises(coordinator.InputsChanged):
                self.execute_restarting()

    # ---- the cheap checks (DL-4 item 4a) ---------------------------------------------------------------------
    def cheap_plan(self, finding=None, seconds=0.0):
        """Register a `zig-format` action and replace its check with one that answers `finding` after `seconds`."""
        self.plan['groups'].append(group('zig-format', ['inputs/unit/']))
        self.plan['coverage'].update(required_actions=3, registered_actions=3)
        self.save_plan()
        calls = []

        def check(context):
            calls.append(context.compiler)
            time.sleep(seconds)
            return [] if finding is None else [coordinator.gate_cheap_checks.Finding('zig-format', finding, 'src/x.zig:3')]
        self.stack.enter_context(patch.dict(coordinator.gate_cheap_checks.RUNNERS, {'zig-format': check}))
        return calls

    def test_a_cheap_finding_ends_the_gate_before_any_test_action_with_its_file_and_line(self):
        calls = self.cheap_plan('zig fmt would change this line')
        self.assertEqual(self.execute(), 1)
        self.assertEqual(len(calls), 1)
        self.assertEqual(self.events('gate'), [], 'no test action started')
        self.assertEqual([kind for kind, _ in self.admissions if kind == 'gate'], [])
        self.assertEqual(self.receipts(), [])
        output = self.child_diagnostics[-1][1]
        self.assertIn('a cheap check failed before any test action started', output)
        self.assertIn('failure 1/1: zig-format', output)
        self.assertIn('src/x.zig:3: zig fmt would change this line', output)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual((report['success'], report['status'], report['stage']), (False, 1, 'cheap_checks'))
        self.assertEqual(report['cheap_checks']['findings'][0]['location'], 'src/x.zig:3')
        self.assertNotIn('no failing step was found', output)
        # The saved logs say the same to `gate_summary.py`, and the next run does not read them as its own.
        saved = '\n'.join(coordinator.gate_summary.summarize(log_directory=self.cache / 'last-logs'))
        self.assertIn('failure 1/1: zig-format', saved)
        self.assertIn('src/x.zig:3: zig fmt would change this line', saved)
        coordinator.gate_cheap_checks.RUNNERS['zig-format'] = lambda context: []
        self.assertEqual(self.execute(), 0)
        self.assertFalse((self.cache / 'last-logs' / 'cheap').exists())

    def test_a_cheap_finding_ends_a_preparation_build_still_running(self):
        self.cheap_plan('zig fmt would change this line', seconds=0.2)
        stopped = []

        def build(argv, controls):
            if 'verification-prepare' not in argv:
                return None
            stop = controls['stop']
            deadline = time.monotonic() + 20
            while not stop() and time.monotonic() < deadline:
                time.sleep(.01)
            stopped.append(stop())
            stop.killed = True
            return coordinator.verification_process.FAIL_FAST_STATUS
        self.on_build = build
        self.assertEqual(self.execute(), 1)
        self.assertEqual(stopped, [True])
        self.assertEqual(self.events('gate'), [])
        self.assertIn('src/x.zig:3', self.child_diagnostics[-1][1])
        self.assertEqual(coordinator.read_record(self.cache / 'last-run.json')['stage'], 'cheap_checks')

    def test_passing_cheap_checks_leave_the_gate_and_its_receipts_as_they_were(self):
        calls = self.cheap_plan()
        self.assertEqual(self.execute(), 0)
        self.assertEqual(len(calls), 1)
        self.assertEqual(len(self.events('gate')), 1)
        self.assertEqual(len(self.receipts()), 3)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual(report['cheap_checks']['checks']['zig-format']['findings'], 0)
        self.assertTrue(report['success'])

    def test_a_cheap_finding_for_a_reused_action_leaves_its_success_standing(self):
        self.cheap_plan()
        self.assertEqual(self.execute(), 0)
        coordinator.gate_cheap_checks.RUNNERS['zig-format'] = lambda context: [
            coordinator.gate_cheap_checks.Finding('zig-format', 'zig fmt would change this line', 'src/x.zig:3')]
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states()['zig-format'], 'reused')
        self.assertIn('cheap check zig-format fails but its action was reused', self.child_diagnostics[-1][2])

    def test_the_quick_profile_and_a_dry_run_run_no_cheap_check(self):
        calls = self.cheap_plan('zig fmt would change this line')
        self.assertEqual(self.execute(profile='quick', quick_actions=1), 3)
        self.assertEqual(self.execute(dry_run=True), 0)
        self.assertEqual(calls, [])

    def test_a_failed_preparation_build_names_its_step_and_source_line(self):
        fixture = (REPOSITORY / 'test/fixtures/gate-summary/compile-error.log').read_text()

        def build(argv, controls):
            if 'verification-prepare' not in argv:
                return None
            log = self.cache / 'last-logs/preparation/stderr.log'
            log.parent.mkdir(parents=True, exist_ok=True)
            log.write_text(fixture)
            self.admissions_seen = True
            return 1
        self.on_build = build
        with self.assertRaisesRegex(coordinator.VerificationError, 'artifact preparation failed'):
            self.execute()
        output = self.child_diagnostics[-1][1]
        self.assertIn('failure 2/2: compile exe selka debug native', output)
        self.assertIn('src/diagnostic_codes.zig:524:5: error: dl4 probe', output)

    def test_a_finding_for_a_reused_action_passes_even_when_a_sibling_action_runs(self):
        # `coverage` always runs; a `coverage_self` finding must be judged by `coverage_self`'s own reuse.
        self.plan['groups'] += [group('coverage', ['inputs/unit/'], False), group('coverage_self', ['inputs/docs/'])]
        self.plan['coverage'].update(required_actions=4, registered_actions=4)
        self.save_plan()
        found = []
        self.stack.enter_context(patch.dict(coordinator.gate_cheap_checks.RUNNERS, {'coverage': lambda context: list(found)}))
        self.assertEqual(self.execute(), 0)
        found.append(coordinator.gate_cheap_checks.Finding('coverage_self', 'self-test failed', 'tests/test_inputs_coverage.py:9'))
        self.assertEqual(self.execute(), 0)
        self.assertEqual((self.states()['coverage_self'], self.states()['coverage']), ('reused', 'fresh'))
        self.assertIn('cheap check coverage_self fails but its action was reused', self.child_diagnostics[-1][2])

    def test_a_cheap_check_past_the_phase_deadline_is_abandoned_and_decides_nothing(self):
        self.cheap_plan('zig fmt would change this line', seconds=3.0)
        self.stack.enter_context(patch.object(coordinator.gate_cheap_checks, 'PHASE_SECONDS', 0.3))
        self.assertEqual(self.execute(), 0)
        self.assertEqual(len(self.events('gate')), 1)
        self.assertIn('cheap checks zig-format passed their 0 s deadline and were abandoned', self.child_diagnostics[-1][2])
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual(report['cheap_checks']['abandoned'], ['zig-format'])

    def test_a_reused_preparation_empties_an_older_failed_preparation_log(self):
        self.assertEqual(self.execute(), 0)
        stale = self.cache / 'last-logs/preparation/stderr.log'
        stale.parent.mkdir(parents=True, exist_ok=True)
        stale.write_text((REPOSITORY / 'test/fixtures/gate-summary/compile-error.log').read_text())
        self.assertEqual(self.execute(), 0)
        self.assertEqual(stale.read_text(), '')
        lines = coordinator.gate_summary.summarize(log_directory=self.cache / 'last-logs')
        self.assertFalse(lines[0].startswith('verification: FAIL'), lines)
        self.assertNotIn('compile exe selka', '\n'.join(lines))

    def test_the_compiler_checks_get_the_prepared_compiler(self):
        self.plan['groups'].append(group('my_format', ['inputs/unit/']))
        self.plan['coverage'].update(required_actions=3, registered_actions=3)
        self.save_plan()
        seen = []
        self.stack.enter_context(patch.dict(coordinator.gate_cheap_checks.RUNNERS, {
            'my_format': lambda context: seen.append(context.compiler) or []}))
        self.assertEqual(self.execute(), 0)
        self.assertEqual(seen, [self.root / 'zig-out/bin/selka'])

    def test_fail_fast_ends_the_build_at_the_first_failing_step_and_records_no_receipt(self):
        self.before_gate = self.fail_the_gate_early
        self.assertEqual(self.execute(fail_fast=True, flaky_rerun=False), 1)
        self.assertEqual(self.receipts(), [])
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertFalse(report['success'])
        self.assertEqual(report['fail_fast'], {'requested': True, 'stopped': True,
                                               'beacons': ['fail-fast.unit.member.0.txt']})
        self.assertIn('failed command: python3 scripts/verification_native_telemetry.py --action-id unit',
                      (self.cache / 'last-logs/gate/stderr.log').read_text())
        output = self.child_diagnostics[-1][1]
        self.assertIn('verification: FAIL', output)
        self.assertIn('failure 1/1: unit', output)
        self.assertIn('test: root::lazy.audit (failed)', output)
        self.assertIn('at src/lazy_readers_test.zig:30', output)
        self.assertNotIn('BrokenPipeError', output, 'what the killed build printed first is no part of the failure')
        self.assertIn('stopped at the first failing step (--fail-fast)', output)
        self.admissions.clear()
        self.gate_status = None
        self.before_gate = None
        self.assertEqual(self.execute(), 0, 'nothing was recorded, so the next request runs the actions again')
        self.assertEqual([kind for kind, _ in self.admissions if kind == 'gate'], ['gate'])

    def test_fail_fast_without_a_failure_changes_nothing_for_a_passing_run(self):
        self.assertEqual(self.execute(fail_fast=True), 0)
        self.assertEqual(len(self.receipts()), 2)
        self.assertIsNotNone(self.gate_controls['stop'])
        self.assertFalse(self.gate_controls['stop'].killed)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual(report['fail_fast'], {'requested': True, 'stopped': False, 'beacons': []})
        self.admissions.clear()
        self.assertEqual(self.execute(fail_fast=True), 0)
        self.assertEqual(self.admissions, [], 'the receipts a fail-fast run recorded are ordinary ones')

    def test_without_the_option_the_gate_gets_no_stop_request(self):
        self.assertEqual(self.execute(), 0)
        self.assertIsNone(self.gate_controls['stop'])
        self.assertEqual(coordinator.read_record(self.cache / 'last-run.json')['fail_fast'],
                         {'requested': False, 'stopped': False, 'beacons': []})

    def test_the_option_reaches_the_command_line(self):
        with patch.object(coordinator, 'ROOT', self.root), patch.object(coordinator, 'execute', return_value=0) as execute, \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            coordinator.main(['--zig', sys.executable, '--shared-cache-dir', '', '--dry-run'])
            self.assertFalse(execute.call_args.kwargs['fail_fast'])
            coordinator.main(['--zig', sys.executable, '--shared-cache-dir', '', '--dry-run', '--fail-fast'])
            self.assertTrue(execute.call_args.kwargs['fail_fast'])

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
        environment = dict(os.environ, SELKA_SLOT_DIR=str(slots), SELKA_SLOT_SETTLE='0',
                           SELKA_SLOT_POLL='1', SELKA_TIMING_MEM='0')
        environment.pop('SELKA_ADMISSION_DIR', None)
        environment.pop('SELKA_ADMISSION_KIND', None)
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
        environment = dict(os.environ, SELKA_SLOT_DIR=str(slots), SELKA_SLOT_SETTLE='0',
                           SELKA_SLOT_POLL='1', SELKA_TIMING_MEM='0')
        environment.pop('SELKA_ADMISSION_DIR', None)
        environment.pop('SELKA_ADMISSION_KIND', None)
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

    def test_shared_action_workflow_locks_span_admission_and_publication(self):
        shared = self.root / '.shared-evidence'
        lock = coordinator.fuzz_campaign_store.Store.coordinator_lock
        publish = coordinator.fuzz_campaign_store.Store.publish_success
        held, publications = [], []
        @contextlib.contextmanager
        def workflow(store, key):
            with lock(store, key):
                held.append(key)
                try:
                    yield
                finally:
                    held.pop()
        def guarded_publish(*args, **kwargs):
            self.assertIn(args[1], held)
            publications.append(args[1])
            return publish(*args, **kwargs)
        self.before_gate = lambda: self.assertEqual(len(held), 2)
        with patch.object(coordinator.fuzz_campaign_store.Store, 'coordinator_lock', new=workflow), \
                patch.object(coordinator.fuzz_campaign_store.Store, 'publish_success', new=guarded_publish):
            self.assertEqual(self.execute(shared=shared), 0)
        self.assertEqual(len(publications), 2)
        self.assertEqual(held, [])

    def test_peer_publication_between_miss_and_action_lock_is_preserved(self):
        shared = self.root / '.shared-evidence'
        self.assertEqual(self.execute(shared=shared), 0)
        keys = self.unpublish(shared, ['unit', 'docs'])
        lock = coordinator.fuzz_campaign_store.Store.coordinator_lock
        first = []
        @contextlib.contextmanager
        def publish_before_lock(store, action_key):
            if not first:
                first.append(action_key)
                for value in keys.values():
                    self.publish(shared, value)
            with lock(store, action_key):
                yield
        self.admissions.clear()
        with patch.object(coordinator.fuzz_campaign_store.Store, 'coordinator_lock', new=publish_before_lock):
            self.assertEqual(self.execute(shared=shared), 0)
        self.assertEqual(self.admissions, [])
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})
        store = coordinator.fuzz_campaign_store.Store(shared)
        self.assertTrue(all(coordinator.prior_success(store, self.cache, value) for value in keys.values()))

    def test_real_admitted_publication_holds_gate_lock(self):
        environment = {'SELKA_SLOT_DIR': str(self.root / '.publication-slots'),
                       'SELKA_BUILD_MEM': '0', 'SELKA_GATE_MEM': '0',
                       'SELKA_SLOT_POLL': '1', 'SELKA_SLOT_SETTLE': '0', 'SELKA_TIMING_CPUS': ''}
        observed = []
        def publish(status, authority):
            self.assertEqual(status, 0)
            self.assertTrue(authority())
            directory = Path(environment['SELKA_SLOT_DIR'])
            candidates = list(directory.glob('gate[0-9]*.lock'))
            self.assertTrue(candidates)
            locked = []
            for path in candidates:
                with path.open('a') as handle:
                    try:
                        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except BlockingIOError:
                        locked.append(path)
            self.assertTrue(locked, candidates)
            observed.extend(locked)
            return status
        with patch.dict(os.environ, environment):
            status, _ = REAL_ADMISSION(self.root, 'gate', [sys.executable, '-c', 'pass'],
                                      dict(os.environ), lambda: True, finalize=publish)
        self.assertEqual(status, 0)
        self.assertTrue(observed)
        for path in observed:
            with path.open('a') as handle:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_real_admitted_gate_ends_at_the_first_beacon_without_publishing(self):
        self.install_cache_trim()
        environment = {'SELKA_SLOT_DIR': str(self.root / '.fail-fast-slots'),
                       'SELKA_BUILD_MEM': '0', 'SELKA_GATE_MEM': '0',
                       'SELKA_SLOT_POLL': '1', 'SELKA_SLOT_SETTLE': '0', 'SELKA_TIMING_CPUS': ''}
        beacons = self.root / 'beacons'
        beacons.mkdir()
        # A step that fails at once and a sibling that would run for a minute, as one process group.
        command = ('import os,subprocess,sys,time; sub=subprocess.Popen(["sleep","60"]); '
                   'open(sys.argv[1]+"/.fail-fast.partial","w").write("half"); '
                   'open(sys.argv[1]+"/fail-fast.unit.member.0.txt","w").write("error: x\\nfailed command: a --action-id unit\\n"); '
                   'time.sleep(60)')
        published = []
        watch = coordinator.verification_process.FailFast(beacons, interval=0.05)
        timings = []
        started = time.monotonic()
        with patch.dict(os.environ, environment):
            status, _ = REAL_ADMISSION(self.root, 'gate', [sys.executable, '-c', command, str(beacons)],
                                       dict(os.environ), lambda: True, timings=timings, stop=watch,
                                       finalize=lambda status, authority: published.append(status) or status)
        self.assertLess(time.monotonic() - started, 50, 'the minute-long sibling was not waited for')
        self.assertEqual(status, 1)
        self.assertTrue(watch.killed)
        self.assertEqual(published, [], 'an ended gate publishes nothing')
        self.assertTrue(timings[0]['stopped'])
        self.assertEqual(watch.names, ['fail-fast.unit.member.0.txt'])

    def test_real_admitted_gate_with_a_watch_and_no_failure_publishes_as_before(self):
        self.install_cache_trim()
        environment = {'SELKA_SLOT_DIR': str(self.root / '.fail-fast-quiet-slots'),
                       'SELKA_BUILD_MEM': '0', 'SELKA_GATE_MEM': '0',
                       'SELKA_SLOT_POLL': '1', 'SELKA_SLOT_SETTLE': '0', 'SELKA_TIMING_CPUS': ''}
        beacons = self.root / 'quiet-beacons'
        beacons.mkdir()
        watch = coordinator.verification_process.FailFast(beacons, interval=0.05)
        published = []
        with patch.dict(os.environ, environment):
            status, _ = REAL_ADMISSION(self.root, 'gate', [sys.executable, '-c', 'import time; time.sleep(.3)'],
                                       dict(os.environ), lambda: True, stop=watch,
                                       finalize=lambda status, authority: published.append(status) or status)
        self.assertEqual((status, published, watch.killed), (0, [0], False))

    def test_real_admitted_interrupted_publication_releases_gate(self):
        environment = {'SELKA_SLOT_DIR': str(self.root / '.interrupted-slots'),
                       'SELKA_BUILD_MEM': '0', 'SELKA_GATE_MEM': '0',
                       'SELKA_SLOT_POLL': '1', 'SELKA_SLOT_SETTLE': '0', 'SELKA_TIMING_CPUS': ''}
        def interrupted(status, authority):
            self.assertTrue(authority())
            raise KeyboardInterrupt
        with patch.dict(os.environ, environment):
            with self.assertRaises(KeyboardInterrupt):
                REAL_ADMISSION(self.root, 'gate', [sys.executable, '-c', 'pass'],
                               dict(os.environ), lambda: True, finalize=interrupted)
            self.assertEqual(REAL_ADMISSION(self.root, 'gate', [sys.executable, '-c', 'pass'],
                                           dict(os.environ), lambda: True)[0], 0)

    def test_a_real_build_that_sees_an_edit_while_it_runs_restarts_and_a_real_gate_does_not(self):
        # Item 4c with the real `run_admitted`, the real build-slot.sh, a private slot directory and a sleeping command:
        # the heartbeat raises while the command runs; only a gate command counts as an action.
        environment = {'SELKA_SLOT_DIR': str(self.root / '.restart-slots'), 'SELKA_BUILD_MEM': '0',
                       'SELKA_GATE_MEM': '0', 'SELKA_SLOT_POLL': '1', 'SELKA_SLOT_SETTLE': '0', 'SELKA_TIMING_CPUS': ''}
        observed = self.root / 'observed'
        observed.mkdir()
        (observed / 'input.txt').write_text('original')
        command = [sys.executable, '-c', 'import sys,time\nfrom pathlib import Path\ntime.sleep(1)\n'
                   'Path(sys.argv[1]).write_text("edited at 1 s")\ntime.sleep(8)', str(observed / 'input.txt')]
        changed = [{'name': 'observed/input.txt', 'role': 'preparation_sources'}]
        for kind, restarts in (('build', True), ('gate', False)):
            (observed / 'input.txt').write_text('original %s' % kind)
            with self.subTest(kind=kind), Snapshot(observed, ['input.txt']) as snapshot, patch.dict(os.environ, environment):
                began = time.monotonic()
                with self.assertRaisesRegex(SnapshotError, 'inputs changed while awaiting admitted work') as raised:
                    REAL_ADMISSION(self.root, kind, command, dict(os.environ), snapshot.unchanged,
                                   heartbeat=lambda: coordinator.drain_events([snapshot]))
                self.assertGreater(time.monotonic() - began, 0.9, 'the trip came while the command ran')
                self.assertLess(time.monotonic() - began, 8.0, 'the command was ended at the trip')
                self.assertEqual(raised.exception.verification_action_started, not restarts)
                self.assertEqual(coordinator.restartable(raised.exception, changed, self.root), restarts)

    def test_real_admitted_gate_drains_unrelated_events_and_retains_input_aba(self):
        environment = {'SELKA_SLOT_DIR': str(self.root / '.event-drain-slots'),
                       'SELKA_BUILD_MEM': '0', 'SELKA_GATE_MEM': '0',
                       'SELKA_SLOT_POLL': '1', 'SELKA_SLOT_SETTLE': '0', 'SELKA_TIMING_CPUS': ''}
        observed = self.root / 'observed'
        observed.mkdir()
        selected = observed / 'input.txt'
        selected.write_text('original')
        # More events than the ordinary Linux queue can retain across a long
        # gate, paced in batches so a live consumer can drain each batch.
        command = '''import sys,time
from pathlib import Path
root=Path(sys.argv[1]); changed=sys.argv[2]=='changed'
for batch in range(200):
    for index in range(100):
        noise=root/('noise-'+str(index)); noise.touch(); noise.unlink()
    if changed and batch==100:
        (root/'input.txt').write_text('changed')
        (root/'input.txt').write_text('original')
    time.sleep(.01)
'''
        for changed in (False, True):
            with self.subTest(changed=changed), Snapshot(observed, ['input.txt']) as snapshot:
                polls = []
                publications = []
                def poll_inputs():
                    polls.append(None)
                    coordinator.drain_events([snapshot])
                def publish(status, authority):
                    self.assertEqual(status, 0)
                    self.assertTrue(authority())
                    publications.append(status)
                    return status if snapshot.unchanged() else coordinator.RETRY
                def admit():
                    return REAL_ADMISSION(self.root, 'gate',
                        [sys.executable, '-c', command, str(observed), 'changed' if changed else 'stable'],
                        dict(os.environ), snapshot.unchanged, finalize=publish, heartbeat=poll_inputs)
                with patch.dict(os.environ, environment):
                    if changed:
                        with self.assertRaisesRegex(SnapshotError, 'inputs changed while awaiting admitted work'):
                            admit()
                    else:
                        self.assertEqual(admit()[0], 0)
                self.assertGreater(len(polls), 2)
                self.assertEqual(publications, [] if changed else [0])
                self.assertEqual(snapshot.unchanged(), not changed)

    def cap_environment(self, **extra):
        """A private slot directory and a zig-cache cap the fixture's cache is over, for the F48 tests below."""
        return dict(os.environ, SELKA_SLOT_DIR=str(self.root / '.cap-slots'), SELKA_BUILD_MEM='0', SELKA_GATE_MEM='0',
                    SELKA_SLOT_POLL='1', SELKA_SLOT_SETTLE='0', SELKA_TIMING_CPUS='', SELKA_ADMISSION_BACKEND='legacy',
                    SELKA_ZIG_CACHE_CAP_GB='0.001', SELKA_CACHE_TIERS_CAP_GB='0', SELKA_TEST_CACHES_CAP_GB='0', **extra)

    def install_cache_trim(self):
        """The fixture's wrapper trims with the helper that sits beside it; give it the real one."""
        shutil.copy2(REPOSITORY / 'scripts/worktree_cache_trim.py', self.root / 'scripts/worktree_cache_trim.py')

    def test_the_cache_cap_cannot_fail_a_running_coordinator(self):
        # F48. The complete gate failed at once, on a tree nobody touched, with "inputs changed while awaiting admitted
        # work". Its stability diagnostics named inotify:moved-from and move-self on `.zig-cache`, the directory that holds
        # the prepared artifacts the coordinator watches from `prepare` to the end of its run: the admission of its own
        # gate (the wrapper's `worktree_cache_trim.py`) found the cache over SELKA_ZIG_CACHE_CAP_GB, the coordinator
        # held no slot to prove the worktree busy, and the cap renamed the cache aside. The fixture runs `main` the way
        # a request does (its coordinator lock held), watches a cache file as `prepare` does, and admits a real gate.
        self.install_cache_trim()
        artifact = self.root / '.zig-cache/o/prepared/test-binary'
        results = []
        def execute(*_args, **_controls):
            artifact.parent.mkdir(parents=True)
            artifact.write_bytes(b'x' * (3 << 20))  # `prepare` builds it, over the cap
            with Snapshot(self.root, [], [artifact]) as watched:
                status, _ = REAL_ADMISSION(self.root, 'gate', [sys.executable, '-c', 'pass'], self.cap_environment(),
                                           watched.unchanged, heartbeat=lambda: coordinator.drain_events([watched]))
                results.append((status, watched.unchanged(), artifact.is_file()))
            return status
        stderr = io.StringIO()
        with patch.dict(os.environ, self.cap_environment()), patch.object(coordinator, 'ROOT', self.root), \
                patch.object(coordinator, 'execute', execute), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(stderr):
            status = coordinator.main(['--zig', sys.executable, '--shared-cache-dir', ''])
        self.assertEqual((status, results), (0, [(0, True, True)]), stderr.getvalue())
        self.assertEqual([path.name for path in self.root.iterdir() if '.trim-' in path.name], [])

    def test_a_cache_moved_by_anyone_else_still_fails_the_run(self):
        # The fix stops the cap from moving the cache; it does not teach the watcher to ignore a move. An artifact
        # directory renamed under a watching coordinator by another process still rejects the request.
        self.install_cache_trim()
        artifact = self.root / '.zig-cache/o/prepared/test-binary'
        artifact.parent.mkdir(parents=True)
        artifact.write_bytes(b'x' * 1024)
        move = 'import os,sys,time; os.rename(sys.argv[1], sys.argv[1] + ".moved"); time.sleep(1)'
        with Snapshot(self.root, [], [artifact]) as watched, patch.dict(os.environ, self.cap_environment()):
            with self.assertRaisesRegex(SnapshotError, 'inputs changed while awaiting admitted work'):
                REAL_ADMISSION(self.root, 'gate', [sys.executable, '-c', move, str(artifact.parent.parent)],
                               dict(os.environ), watched.unchanged, heartbeat=lambda: coordinator.drain_events([watched]))
            self.assertFalse(watched.unchanged())

    def test_the_coordinator_holds_the_lock_the_cache_cap_reads(self):
        # The cap treats a held coordinator lock as an active job of the worktree. Both name one file.
        trim = importlib.import_module('worktree_cache_trim')
        self.assertEqual(coordinator.CACHE_DIRECTORY / 'coordinator.lock', trim.COORDINATOR_LOCK)

    def test_a_request_applies_the_cache_cap_once_under_its_lock_before_it_executes(self):
        events = []
        lock = self.root / coordinator.CACHE_DIRECTORY / 'coordinator.lock'
        def locked():
            with lock.open('a') as stream:
                try:
                    fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    return True
            return False
        def bound(root):
            events.append(('bound', root, locked()))
        def execute(*_args, **_controls):
            events.append(('execute', locked()))
            return 0
        arguments = ['--zig', sys.executable, '--shared-cache-dir', '']
        with patch.object(coordinator, 'ROOT', self.root), patch.object(coordinator, 'bound_caches', bound), \
                patch.object(coordinator, 'execute', execute), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(coordinator.main(arguments), 0)
            self.assertEqual(coordinator.main(['--dry-run', *arguments]), 0)
        # A dry run changes nothing, so it applies no cap either.
        self.assertEqual(events, [('bound', self.root, True), ('execute', True), ('execute', True)])
        self.assertFalse(locked())

    def test_a_cap_that_cannot_be_applied_warns_and_never_fails_the_request(self):
        trim = importlib.import_module('worktree_cache_trim')
        for outcome in (OSError('disk gone'), SystemExit(2), 'the admission lock stayed busy for 15 s'):
            stderr = io.StringIO()
            failure = outcome if isinstance(outcome, BaseException) else None
            with self.subTest(outcome=str(outcome)), \
                    patch.object(trim, 'bound_for_coordinator', side_effect=failure,
                                 return_value=None if failure else outcome), \
                    contextlib.redirect_stderr(stderr):
                coordinator.bound_caches(self.root)
            self.assertIn('the worktree cache cap was not applied', stderr.getvalue())

    def subscription_fixture(self, shared, publish=True, mutation=None, status=0, stdout="", stderr=""):
        calls = []
        def subscribe(bundle, command, **controls):
            self.assertIsNone(controls['kind'])
            request = coordinator.read_record(Path(command[-1]))
            calls.append(request)
            if publish:
                for action_key in request['action_keys']:
                    self.publish(shared, action_key)
            if mutation is not None:
                mutation()
            return {'returncode': status, 'stdout': stdout, 'stderr': stderr, 'passed': status == 0,
                    'executed': False, 'coalesced': True}
        self.stack.enter_context(patch.dict(os.environ, SELKA_ADMISSION_BACKEND='scheduler'))
        self.stack.enter_context(patch.object(coordinator.verification_measurement.build_admission,
                                            'subscribe', new=subscribe, create=True))
        return calls

    def test_ten_real_process_subscribers_share_one_admitted_keyed_worker(self):
        # Only the fake build driver's configuration/tool declarations are
        # installed explicitly in the detached interpreter. Subscription,
        # admission, execution, publication and receipt validation are real.
        shared = self.root / '.process-keyed-store'
        slots = self.root / '.process-keyed-slots'
        environment = dict(os.environ, SELKA_SLOT_DIR=str(slots),
                           SELKA_ADMISSION_BACKEND='scheduler', SELKA_GATE_MEM='0',
                           SELKA_BUILD_MEM='0', SELKA_SLOT_SETTLE='0', SELKA_SLOT_POLL='1')
        for name in ('SELKA_ADMISSION_DIR', 'SELKA_ADMISSION_KIND',
                     'SELKA_ADMISSION_PARENT_PID', 'SELKA_ADMISSION_PARENT_START'):
            environment.pop(name, None)
        # Mock-only preparation is explicitly isolated even when clients opt in.
        with patch.dict(os.environ, dict(environment, SELKA_ADMISSION_BACKEND='legacy'), clear=True):
            self.assertEqual(self.execute(shared=shared), 0)
        wanted = sorted(self.unpublish(shared, ['unit', 'docs']).values())
        before = len(self.events('gate'))
        request = {'version': 1, 'root': str(self.root), 'cache': str(self.cache),
                   'zig': str(self.zig), 'options': ['-j3'], 'shared': str(shared),
                   'action_keys': wanted, 'build_timeout': None, 'gate_timeout': None}
        request_path = self.write('process-request.json', json.dumps(request))
        runner = self.write('keyed-fixture.py',
            'import sys\nfrom pathlib import Path\n' +
            f'sys.path.insert(0, {str(REPOSITORY / "scripts")!r})\n' +
            'import verify_cache as coordinator\n' +
            f'coordinator.CONFIG_INPUTS = {coordinator.CONFIG_INPUTS!r}\n' +
            f'coordinator.PREPARE_INPUTS = {coordinator.PREPARE_INPUTS!r}\n' +
            f'coordinator.COORDINATOR_INPUTS = {coordinator.COORDINATOR_INPUTS!r}\n' +
            'coordinator.DECLARATIVE_CONSUMERS = ()\n' +
            f'coordinator.tool_contract = lambda zig, env: ([], [zig, Path({str(self.tool)!r})])\n' +
            'raise SystemExit(coordinator.run_keyed_request(Path(sys.argv[2])))\n')
        client = self.write('keyed-client.py',
            'import json, os, sys, time\nfrom pathlib import Path\n' +
            f'sys.path.insert(0, {str(REPOSITORY / "scripts")!r})\n' +
            'import verify_cache as coordinator\n' +
            f'coordinator.__file__ = {str(runner)!r}\n' +
            'request = json.loads(Path(sys.argv[1]).read_text())\n' +
            'result = coordinator.subscribe_gate(request, dict(os.environ))\n' +
            'store = coordinator.fuzz_campaign_store.Store(Path(request["shared"]))\n' +
            'result["validated"] = all(coordinator.prior_success(store, Path(request["cache"]), key) '
            'for key in request["action_keys"])\n' +
            'Path(sys.argv[2]).write_text(json.dumps(result))\n' +
            'raise SystemExit(0 if result["status"] == 0 and result["validated"] else 1)\n')
        self.write('.hold-gate', '')
        processes, outputs = [], []
        try:
            for index in range(10):
                output = self.root / f'client-{index}.log'
                with output.open('wb') as log:
                    process = subprocess.Popen([sys.executable, str(client), str(request_path),
                                                str(self.root / f'client-{index}.json')],
                                               cwd=self.root, env=environment, stdout=log,
                                               stderr=subprocess.STDOUT, start_new_session=True)
                processes.append(process)
                outputs.append(output)
            deadline = time.monotonic() + 90
            while True:
                subscribers = 0
                database = slots / 'keyed.sqlite3'
                if database.exists():
                    with contextlib.closing(sqlite3.connect(database)) as db:
                        try:
                            subscribers = db.execute('SELECT count(*) FROM subscribers').fetchone()[0]
                        except sqlite3.OperationalError:
                            pass  # Concurrent schema initialization has not committed.
                if subscribers == 10 and (self.root / '.gate-started').exists():
                    break
                for process, output in zip(processes, outputs):
                    self.assertIsNone(process.poll(), output.read_text())
                self.assertLess(time.monotonic(), deadline, 'ten subscribers did not reach one held gate')
                time.sleep(.05)
            self.write('.gate-release', '')
            for process, output in zip(processes, outputs):
                self.assertEqual(process.wait(timeout=90), 0, output.read_text())
            results = [json.loads((self.root / f'client-{index}.json').read_text()) for index in range(10)]
            self.assertEqual(sum(result['executed'] for result in results), 1)
            self.assertEqual(sum(result['coalesced'] for result in results), 9)
            self.assertTrue(all(result['validated'] for result in results))
            self.assertEqual(len({result['bundle'] for result in results}), 1)
            report = coordinator.read_record(self.cache / 'last-run.json')
            self.assertEqual([entry['kind'] for entry in report['admissions']], ['gate'])
            self.assertEqual(len(self.events('gate')) - before, 1)
            self.assertEqual({row['state'] for row in report['actions']}, {'execute'})
            with contextlib.closing(sqlite3.connect(slots / 'admission-v2.sqlite3')) as db:
                rows = db.execute("SELECT kind,started FROM jobs").fetchall()
            # Admission leases are cancelled on release; the detached keyed
            # result separately certifies success. There was one admitted job.
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0][0], 'gate')
            self.assertIsNotNone(rows[0][1])
        finally:
            (self.root / '.gate-release').touch()
            for process in processes:
                if process.poll() is None:
                    coordinator.terminate_owned(process)
                process.wait(timeout=60)
            for output in outputs:
                self.child_diagnostics.append(('real subscription client', output.read_text(), ''))

    def test_keyed_worker_failure_retains_nested_stdout_and_stderr(self):
        shared = self.root / '.keyed-store'
        self.subscription_fixture(shared, publish=False, status=19,
                                  stdout='nested child stdout\n', stderr='nested child failed\n')
        with self.assertRaises(coordinator.VerificationError) as failure:
            self.execute(shared=shared)
        self.assertEqual(failure.exception.status, 19)
        report = coordinator.read_record(self.cache / 'last-run.json')
        output = report['subscriptions'][0]['worker_output']
        for stream, text in [('stdout', 'nested child stdout\n'), ('stderr', 'nested child failed\n')]:
            self.assertEqual(output[stream]['tail'], text)
            self.assertEqual(Path(output[stream]['path']).read_text(), text)
            self.assertTrue(output[stream]['capture_available'])
        self.assertIn('nested child failed', self.child_diagnostics[-1][2])
        self.assertNotIn('gate', [kind for kind, _ in self.admissions])

    def test_keyed_subscriber_revalidates_shared_receipts_without_gate_admission(self):
        shared = self.root / '.keyed-store'
        calls = self.subscription_fixture(shared)
        self.assertEqual(self.execute(shared=shared), 0)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]['action_keys'], sorted(self.keys().values()))
        self.assertNotIn('gate', [kind for kind, _ in self.admissions])
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertTrue(report['subscriptions'][0]['coalesced'])
        self.assertFalse(report['subscriptions'][0]['executed'])

    def test_keyed_subscriber_never_treats_scheduler_boolean_as_evidence(self):
        shared = self.root / '.keyed-store'
        self.subscription_fixture(shared, publish=False)
        with self.assertRaises(coordinator.VerificationError) as failure:
            self.execute(shared=shared)
        self.assertEqual(failure.exception.status, coordinator.RETRY)
        self.assertEqual(self.receipts(), [])
        self.assertNotIn('gate', [kind for kind, _ in self.admissions])

    def test_keyed_subscriber_rejects_local_source_mutation(self):
        shared = self.root / '.keyed-store'
        self.subscription_fixture(shared, mutation=lambda: self.input.write_text('changed while subscribed'))
        with self.assertRaises(coordinator.VerificationError) as failure:
            self.execute(shared=shared)
        self.assertEqual(failure.exception.status, coordinator.RETRY)
        self.assertNotIn('gate', [kind for kind, _ in self.admissions])
        self.assertFalse(coordinator.read_record(self.cache / 'last-run.json')['success'])

    def test_keyed_subscription_preserves_fresh_and_force_obligations(self):
        shared = self.root / '.keyed-store'
        self.plan['groups'].append(group('fresh', ['inputs/unit/'], False))
        self.plan['coverage'].update(required_actions=3, registered_actions=3)
        self.save_plan()
        calls = self.subscription_fixture(shared)
        self.assertEqual(self.execute(shared=shared), 0)
        self.assertEqual(len(calls), 1)
        self.assertNotIn(self.keys()['fresh'], calls[0]['action_keys'])
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused', 'fresh': 'fresh'})
        self.assertIn('verification-fresh', self.events('gate')[-1]['argv'])
        self.assertNotIn('verification-unit', self.events('gate')[-1]['argv'])
        self.assertEqual(self.execute(force=True, shared=shared), 0)
        self.assertEqual(len(calls), 1)
        self.assertEqual(len(self.events('gate')), 2)

    def test_overlapping_keyed_subsets_execute_the_shared_action_once(self):
        first, second = self.two_roots(self.producer())
        other = Path(second['evidence_store']['root']).parent.parent
        keys = {row['id']: row['action_key'] for row in first['actions']}
        self.assertEqual(keys, {row['id']: row['action_key'] for row in second['actions']})
        shared = self.root / '.overlap-store'
        entered, contending, release = threading.Event(), threading.Event(), threading.Event()
        results, errors, executed = [], [], []
        original_lock = coordinator.fuzz_campaign_store.Store.coordinator_lock
        @contextlib.contextmanager
        def locking(store, action_key):
            if threading.current_thread().name == 'overlap-peer' and action_key == keys['docs']:
                contending.set()
            with original_lock(store, action_key):
                yield
        def admit(root, kind, argv, env, unchanged, **controls):
            if kind == 'gate':
                executed.append((root, argv))
                if root == self.root:
                    entered.set()
                    self.assertTrue(release.wait(30))
            return self.admit(root, kind, argv, env, unchanged, **controls)
        # The shared Zig path was retained by two_roots' tool-contract fixture.
        zig = coordinator.tool_contract(self.zig, {})[1][0]
        def request(root, wanted):
            try:
                results.append(coordinator.execute(root, root / '.receipts', zig, ['-j3'], False, shared,
                                                   _action_keys=[keys[name] for name in wanted]))
            except BaseException as error:
                errors.append(error)
        # Keep the fixture's keyed launcher identity through both threaded requests,
        # matching two_roots; an inherited component-cache path changes those keys.
        with self.launcher(SELKA_COMPONENT_CACHE=''), \
                patch.object(coordinator.fuzz_campaign_store.Store, 'coordinator_lock', new=locking), \
                patch.object(coordinator, 'run_admitted', side_effect=admit):
            one = threading.Thread(target=request, args=(self.root, ['unit', 'docs']), name='overlap-owner')
            two = threading.Thread(target=request, args=(other, ['docs', 'pure']), name='overlap-peer')
            one.start()
            try:
                self.assertTrue(entered.wait(30), errors)
                two.start()
                self.assertTrue(contending.wait(30), errors)
            finally:
                release.set()
                one.join(30)
                if two.ident is not None:
                    two.join(30)
        self.assertFalse(one.is_alive())
        self.assertFalse(two.is_alive())
        self.assertEqual(errors, [])
        self.assertEqual(results, [3, 3])
        targets = [arg for _, argv in executed for arg in argv if arg.startswith('verification-')]
        self.assertEqual(targets.count('verification-unit'), 1)
        self.assertEqual(targets.count('verification-docs'), 1)
        self.assertEqual(targets.count('verification-pure'), 1)
        report = coordinator.read_record(other / '.receipts/last-run.json')
        self.assertGreater(report['timings']['action_lock_wait_seconds'], 0)

    def test_detached_keyed_worker_executes_only_exact_requested_subset(self):
        shared = self.root / '.keyed-store'
        self.assertEqual(self.execute(shared=shared), 0)
        keys = self.unpublish(shared, ['unit', 'docs'])
        self.admissions.clear()
        request = self.cache / 'keyed-request.json'
        coordinator.atomic_record(request, {'version': 1, 'root': str(self.root), 'cache': str(self.cache),
            'zig': str(self.zig), 'options': ['-j3'], 'shared': str(shared),
            'action_keys': [keys['unit']], 'build_timeout': None, 'gate_timeout': None})
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(coordinator.run_keyed_request(request), 0)
        self.assertEqual(coordinator.read_record(self.cache / 'last-run.json')['status'], 3)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'skipped'})
        self.assertIn('verification-unit', self.events('gate')[-1]['argv'])
        self.assertNotIn('verification-docs', self.events('gate')[-1]['argv'])
        store = coordinator.fuzz_campaign_store.Store(shared)
        self.assertTrue(coordinator.prior_success(store, self.cache, keys['unit']))
        self.assertFalse(coordinator.prior_success(store, self.cache, keys['docs']))
        with self.assertRaises(coordinator.VerificationError):
            self.execute(shared=shared, _action_keys=['0' * 64])

    def test_shared_forced_failure_removes_prior_success(self):
        shared = self.root / '.shared-evidence'
        self.assertEqual(self.execute(shared=shared), 0)
        self.gate_status = 17
        self.assertEqual(self.execute(force=True, shared=shared), 17)
        self.gate_status = None
        self.admissions.clear()
        self.assertEqual(self.execute(shared=shared), 0)
        self.assertIn('gate', [kind for kind, _ in self.admissions])

    def unpublish(self, shared, names):
        """Remove the named actions' successes from both stores, keeping their keys."""
        keys = self.keys()
        store = coordinator.fuzz_campaign_store.Store(shared)
        for name in names:
            store.discard_success(keys[name])
            (self.cache / 'actions' / (keys[name] + '.json')).unlink()
        return keys

    def publish(self, shared, action_key):
        """Publish a success the way another request's coordinator does."""
        value = {'version': coordinator.VERSION, 'kind': 'verification-success', 'key': action_key}
        self.assertTrue(coordinator.fuzz_campaign_store.Store(shared).publish_success(action_key, value, [], lambda: True))

    def test_success_published_while_queued_is_reused_after_admission(self):
        shared = self.root / '.shared-evidence'
        self.assertEqual(self.execute(shared=shared), 0)
        keys = self.unpublish(shared, ['unit', 'docs'])
        # Another request finishes `unit` while this one waits for its gate slot.
        self.before_gate = lambda: self.publish(shared, keys['unit'])
        self.admissions.clear()
        self.assertEqual(self.execute(shared=shared), 0)
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'execute'})
        gate = self.events('gate')[-1]['argv']
        self.assertIn('verification-docs', gate)
        self.assertNotIn('verification-unit', gate)
        self.assertNotIn('test', gate)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual(report['reuse_lookups'], {'pre_queue': 0, 'post_admission': 1})
        self.assertTrue(report['success'])
        self.assertEqual(report['profile_coverage']['counts'], {'required': 2, 'reused': 1, 'executed': 1, 'outstanding': 0, 'prepared': 0, 'qualification_owed': 0})
        self.assertEqual(report['profile_plan']['selected'], ['docs'])
        unit = next(row for row in report['actions'] if row['id'] == 'unit')
        self.assertEqual(unit['reason'], 'valid prior success published while queued')
        self.assertEqual(self.keys(), keys)

    def test_every_action_published_while_queued_withdraws_the_gate(self):
        shared = self.root / '.shared-evidence'
        self.assertEqual(self.execute(shared=shared), 0)
        keys = self.unpublish(shared, ['unit', 'docs'])
        gates = len(self.events('gate'))
        self.before_gate = lambda: [self.publish(shared, keys[name]) for name in ('unit', 'docs')]
        self.revised.clear()
        self.assertEqual(self.execute(shared=shared), 0)
        self.assertEqual(self.revised, [None])
        self.assertEqual(len(self.events('gate')), gates)
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual(report['reuse_lookups'], {'pre_queue': 0, 'post_admission': 2})
        self.assertTrue(report['profile_coverage']['complete_verification'])

    def test_success_for_inputs_changed_while_queued_is_not_reused_after_admission(self):
        shared = self.root / '.shared-evidence'
        self.input.write_text('changed')
        self.assertEqual(self.execute(shared=shared), 0)
        changed = self.keys()['unit']
        self.input.write_text('original')
        self.assertEqual(self.execute(shared=shared), 0)
        self.unpublish(shared, ['unit'])
        # While this request queues, its input becomes the content another
        # request already verified: that success names other inputs than the
        # ones this request keyed, and the request must not take it.
        self.before_gate = lambda: self.input.write_text('changed')
        gates = len(self.events('gate'))
        self.revised.clear()
        self.assertEqual(self.execute(shared=shared), coordinator.RETRY)
        self.assertEqual(self.revised, [])
        self.assertEqual(len(self.events('gate')), gates)
        self.assertNotEqual(self.states()['unit'], 'reused')
        self.assertTrue(coordinator.prior_success(coordinator.fuzz_campaign_store.Store(shared), self.cache, changed))

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
                         {'required': 2, 'reused': 1, 'executed': 1, 'outstanding': 0, 'prepared': 0, 'qualification_owed': 0})
        self.assertEqual(self.execute(profile='quick'), 3)
        self.assertEqual(len(self.receipts()), 2)

    def test_long_profile_cannot_certify_missing_qualification(self):
        def qualification(root, cache, compiler, zig, context, snapshots, **controls):
            self.assertEqual(root, self.root)
            self.assertEqual(compiler, self.root / 'zig-out/bin/selka')
            self.assertEqual(controls['max_actions'], 6)
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

    def test_the_proofs_profile_runs_the_uncapped_proof_step_after_a_passing_gate_and_only_then(self):
        with patch.object(coordinator, 'run_proof_profile', return_value=0) as step:
            self.assertEqual(self.execute(profile='proofs'), 0)
            self.assertEqual(step.call_count, 1)
        coverage = coordinator.read_record(self.cache / 'last-run.json')['profile_coverage']
        self.assertEqual((coverage['profile'], coverage['status']), ('proofs', 'complete'))
        with patch.object(coordinator, 'run_proof_profile', return_value=0) as step:
            self.assertEqual(self.execute(profile='complete'), 0)
            self.assertEqual(step.call_count, 0)

    def test_a_failing_proof_step_fails_the_proofs_profile_and_keeps_the_gate_evidence(self):
        with patch.object(coordinator, 'run_proof_profile', return_value=1):
            self.assertEqual(self.execute(profile='proofs'), 1)
        self.assertEqual(len(self.receipts()), 2)
        self.assertFalse(coordinator.read_record(self.cache / 'last-run.json')['success'])

    def test_the_proof_step_runs_the_driver_without_the_size_cap_on_the_compiler_the_gate_built(self):
        compiler = self.root / 'built-selka'
        compiler.write_text('compiler')
        seen = {}
        def admitted(root, kind, argv, env, unchanged, **kwargs):
            seen.update(root=root, kind=kind, argv=argv)
            (kwargs['log_dir']).mkdir(parents=True, exist_ok=True)
            (kwargs['log_dir'] / 'stdout.log').write_text(
                'ownership-proof: DISAGREEMENT: f [abc] zig=accept lean=reject\n'
                'ownership-proof: lake build ok; 9 functions; 0 skipped on the Lean side\n')
            (kwargs['log_dir'] / 'stderr.log').write_text('')
            return 1, 0.0
        artifacts = {'artifacts': {'selka': {'path': str(compiler)}}}
        with patch.object(coordinator, 'run_admitted', side_effect=admitted):
            status = coordinator.run_proof_profile(self.root, self.cache, artifacts, {'PATH': '/usr/bin'}, lambda: True, [],
                                                   coordinator.ProcessLimits(None))
        self.assertEqual(status, 1)
        self.assertEqual(seen['kind'], 'gate')
        argv = seen['argv']
        self.assertEqual(argv[argv.index('--lean-cap-bytes') + 1], '0')
        self.assertEqual(argv[argv.index('--compiler') + 1], str(compiler))
        for bad in (None, {}, {'artifacts': {'selka': {'path': str(self.root / 'missing')}}}):
            with self.subTest(artifacts=bad), self.assertRaises(coordinator.VerificationError):
                coordinator.run_proof_profile(self.root, self.cache, bad, {}, lambda: True, [], coordinator.ProcessLimits(None))

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

    def test_narrowed_identity_binding_located_artifact_bytes_is_not_path_free(self):
        # A qualified producer identity also binds the artifact's own bytes; a
        # test binary's debug information names the checkout, which no search
        # of the key can see.
        helper = coordinator.verification_producers
        label = 'text-scalar-units'
        for name in helper.CLOSURES[label]:
            self.write(name, 'reviewed source fixture')
        pure = dict(group('text_scalar_unit', list(helper.CLOSURES[label])), artifacts=[label])
        common = {'artifacts': 'whole-artifact-fallback', 'build_configuration': 'a' * 64,
                  'tools': 'b' * 64, 'options': [], 'action_controls': {'optimize': 'Debug'}}
        verdicts = []
        for contents in ('binary fixture', 'binary fixture naming ' + str(self.root) + '/src'):
            binary = self.write('native-scalar', contents)
            record = {'version': 2, 'producers': {label: helper.producer_metadata(self.root, label, binary, 'Debug')}}
            with Snapshot(self.root, pure['inputs']) as sources, Snapshot(self.root, [], [binary]) as artifact:
                providers = {label: artifact.identity['files']}
                payload = coordinator.action_payload(pure, sources, common, self.root, providers, producer_manifest=record)
            self.assertIn('producer', payload['common']['artifacts'][label])
            report = {label: {'identity': 'producer'}}
            coordinator.located_bytes(providers, self.root, report)
            verdicts.append((report[label]['bytes_name_root'], coordinator.path_free(payload, self.root, True, report)))
        self.assertEqual(verdicts, [(False, True), (True, False)])

    def test_timing_window_neither_enters_keys_nor_blocks_reuse(self):
        # F14: a window schedules the request; receipts cross it both ways.
        environment = dict(os.environ, SELKA_SLOT_DIR=str(self.root / 'measurement-slots'), SELKA_SLOT_SETTLE='0',
                           SELKA_SLOT_POLL='1', SELKA_TIMING_MEM='0')
        environment.pop('SELKA_ADMISSION_DIR', None)
        environment.pop('SELKA_ADMISSION_KIND', None)

        def windowed(seconds):
            with patch.dict(os.environ, environment, clear=True):
                with coordinator.verification_measurement.timing_window(seconds):
                    self.assertEqual(self.execute(), 0)
            return coordinator.read_record(self.cache / 'last-run.json')

        self.assertEqual(self.execute(), 0)
        plain_keys = {row['id']: row['action_key'] for row in coordinator.read_record(self.cache / 'last-run.json')['actions']}
        report = windowed(20)
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})
        self.assertEqual({row['id']: row['action_key'] for row in report['actions']}, plain_keys)
        self.assertEqual(report['measurement_window_seconds'], 20)
        self.input.write_text('changed under a window')
        windowed(20)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'reused'})
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})
        self.assertIsNone(coordinator.read_record(self.cache / 'last-run.json')['measurement_window_seconds'])
        windowed(30)
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})

    def test_execution_deadline_change_invalidates_success_and_is_explained(self):
        self.assertEqual(self.execute(gate_timeout=60), 0)
        self.admissions.clear()
        self.assertEqual(self.execute(gate_timeout=30), 0)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertIn({'kind': 'common_changed', 'name': 'execution_limits'},
                      report['actions'][0]['invalidation']['changes'])

    def test_invalid_deadlines_fail_before_admission(self):
        for value in (-1, True, float('inf'), float('nan')):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.execute(gate_timeout=value)
        self.assertEqual(self.admissions, [])
        self.assertEqual(self.receipts(), [])

    def test_zero_deadline_is_the_documented_off_switch(self):
        self.assertEqual(self.execute(build_timeout=0, gate_timeout=0), 0)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})

    def test_initial_watch_failure_replaces_old_success_report(self):
        self.assertEqual(self.execute(), 0)
        before = {path.name for path in self.receipts()}
        self.assertTrue(coordinator.read_record(self.cache / 'last-run.json')['success'])
        with patch.object(coordinator, 'Snapshot', side_effect=SnapshotError('watch capacity exhausted')):
            with self.assertRaisesRegex(SnapshotError, 'watch capacity exhausted'):
                self.execute()
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertFalse(report['success'])
        self.assertEqual(report['stage'], 'preparation')
        self.assertEqual(report['status'], coordinator.RETRY)
        self.assertIn('watch capacity exhausted', report['error'])
        self.assertEqual({path.name for path in self.receipts()}, before)

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
        environment = {'SELKA_SLOT_DIR': str(self.root / '.private-slots'),
                       'SELKA_BUILD_MEM': '0', 'SELKA_GATE_MEM': '0',
                       'SELKA_SLOT_POLL': '1', 'SELKA_SLOT_SETTLE': '0', 'SELKA_TIMING_CPUS': ''}
        self.write('.hang-gate', 'yes')
        with patch.dict(os.environ, environment), patch.object(coordinator, 'run_admitted', REAL_ADMISSION):
            self.assertEqual(self.execute(gate_timeout=4), 124)
            report = coordinator.read_record(self.cache / 'last-run.json')
            self.assertFalse(report['success'])
            self.assertTrue(report['admissions'][-1]['timed_out'])
            self.assertTrue((self.root / '.gate-started').exists())
            self.assertEqual(self.receipts(), [])
            (self.root / '.hang-gate').unlink()
            # Recovery is a correctness check, not a half-second startup budget.
            self.assertEqual(self.execute(gate_timeout=30), 0)
            self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})
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
        notes = {}
        self.assertEqual(coordinator.action_configuration(identity, self.plan, self.root, self.qualified_configuration, notes),
                         {'files': []})
        self.assertEqual(notes, {'declarative_configuration': 'excluded'})
        # A new consumer, wrapped across lines, is one unreviewed site.
        self.write('consumer.zig', 'const lists = @import("build_test_inputs.zig"); // the lists\n'
                                   'const unit = pick(\n    &lists.unit, // wrapped\n    "(",\n);\nconst other = 1;\n')
        with Snapshot(self.root, ['config.zig', 'build_test_inputs.zig', 'consumer.zig']) as configuration:
            changed = copy.deepcopy(configuration.identity)
        sites = [('consumer.zig', 'const lists = @import("build_test_inputs.zig");'),
                 ('consumer.zig', 'const unit = pick( &lists.unit, "(", );')]
        self.assertEqual(coordinator.declarative_consumers(self.root, changed), sites)
        self.assertEqual(coordinator.action_configuration(identity, self.plan, self.root, changed, notes), identity)
        self.assertEqual(notes, {'declarative_configuration': 'unreviewed consumer sites of build_test_inputs.zig'})
        with patch.object(coordinator, 'DECLARATIVE_CONSUMERS', tuple(sites)):
            self.assertEqual(coordinator.action_configuration(identity, self.plan, self.root, changed), {'files': []})
            # An edited reviewed site, and bytes that changed since the snapshot, stay broad.
            self.write('consumer.zig', 'const lists = @import("build_test_inputs.zig");\nconst unit = pick(&lists.docs, "(");\n')
            self.assertEqual(coordinator.action_configuration(identity, self.plan, self.root, changed, notes), identity)
            self.assertEqual(notes, {'declarative_configuration': 'configuration changed while its consumers were read'})
            with Snapshot(self.root, ['config.zig', 'build_test_inputs.zig', 'consumer.zig']) as configuration:
                self.assertEqual(coordinator.action_configuration(identity, self.plan, self.root, configuration.identity), identity)
        with patch.object(coordinator, 'DECLARATIVE_CONSUMERS', None):
            self.assertEqual(coordinator.action_configuration(identity, self.plan, self.root, self.qualified_configuration), identity)
        self.assertEqual(coordinator.action_configuration(identity, self.plan, self.root), identity)

    def test_declarative_exclusion_is_reported_and_keeps_unrelated_actions_reused(self):
        self.assertEqual(self.execute(), 0)
        self.assertEqual(coordinator.read_record(self.cache / 'last-run.json')['declarative_configuration'], 'excluded')
        self.write('inputs/more/fixture.txt', 'more')
        self.plan['groups'][0]['inputs'].append('inputs/more/')
        self.save_plan()
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'reused'})
        self.write('config.zig', 'const lists = @import("build_test_inputs.zig");\n')
        self.assertEqual(self.execute(), 0)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual(report['declarative_configuration'], 'unreviewed consumer sites of build_test_inputs.zig')
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})

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
        (self.root / 'zig-out/libexec/selka/components/cache-plan').write_bytes(b'fake-component-changed')
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

    def shard_plan_options(self, *, relative=False):
        external = tempfile.TemporaryDirectory(prefix='shard-plan-input-', dir=REPOSITORY / '.tmp')
        self.addCleanup(external.cleanup)
        plan = Path(external.name) / 'plan.json'
        plan.write_text('{"version":1,"root":"fixture","shards":2,"tests":[]}')
        path = Path(os.path.relpath(plan, self.root)) if relative else plan
        return coordinator.parse_options(['-Dunit-shard-plan=' + str(path)]), plan

    def test_shard_plan_options_reject_missing_duplicate_and_unknown_controls(self):
        for name in sorted(coordinator.SHARD_PLAN_OPTIONS):
            self.assertIn(name + '=plan.json', coordinator.parse_options([name + '=plan.json']))
            for options in ([name], [name + '='], [name + '=a\x00b'], [name + '=a', name + '=b']):
                with self.subTest(options=options), self.assertRaises(coordinator.VerificationError):
                    coordinator.parse_options(options)
        with self.assertRaises(coordinator.VerificationError):
            coordinator.parse_options(['-Dunknown-shard-plan=plan.json'])

    def test_shard_plan_forwarding_warm_identity_is_private_and_absence_is_unchanged(self):
        self.assertEqual(self.execute(), 0)
        self.assertIsNone(coordinator.read_record(self.cache / 'last-run.json')['shard_plans'])
        self.assertEqual(self.execute(dry_run=True), 0)
        self.assertNotIn('shard_plans', coordinator.read_record(self.cache / 'dry-run.json')['common'])
        options, plan = self.shard_plan_options(relative=True)
        shared = self.root / '.plan-evidence-must-stay-private'
        self.assertEqual(self.execute(options, shared=shared), 0)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertFalse(shared.exists())
        self.assertFalse(report['evidence_store']['shared'])
        self.assertEqual(report['evidence_store']['source'], 'shard-plan-private')
        self.assertEqual(report['shard_plans']['files'][0]['sha256'], coordinator.hashlib.sha256(plan.read_bytes()).hexdigest())
        for phase in ['plan', 'prepare', 'gate']:
            self.assertIn(options[0], self.events(phase)[-1]['argv'])
        self.admissions.clear()
        self.assertEqual(self.execute(options), 0)
        self.assertEqual(self.admissions, [])
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})
        self.assertEqual(self.execute(options, shared=shared, dry_run=True), 0)
        dry = coordinator.read_record(self.cache / 'dry-run.json')
        self.assertEqual(dry['common']['shard_plans'], report['shard_plans'])
        self.assertEqual(dry['evidence_store'], {'shared': False, 'source': 'shard-plan-private'})
        payload = {'common': {'shard_plans': report['shard_plans']}}
        self.assertFalse(coordinator.path_free(payload, self.root, True, {}))

    def test_shard_plan_same_path_content_change_invalidates_preparation_and_receipts(self):
        options, plan = self.shard_plan_options()
        self.assertEqual(self.execute(options), 0)
        before, metadata = plan.read_bytes(), plan.stat()
        plan.write_bytes(before.replace(b'"shards":2', b'"shards":3'))
        os.utime(plan, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
        self.admissions.clear()
        self.assertEqual(self.execute(options), 0)
        self.assertEqual([kind for kind, _ in self.admissions], ['build', 'build', 'gate'])
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})

    def test_shard_plan_missing_or_non_file_never_admits_work(self):
        options, plan = self.shard_plan_options()
        plan.unlink()
        with self.assertRaises(SnapshotError):
            self.execute(options)
        self.assertEqual(self.admissions, [])
        plan.mkdir()
        with self.assertRaises(SnapshotError):
            self.execute(options)
        self.assertEqual(self.admissions, [])

    def test_shard_plan_symlink_retarget_invalidates_identical_bytes(self):
        options, plan = self.shard_plan_options()
        twin, alias = plan.with_name('twin.json'), plan.with_name('selected.json')
        twin.write_bytes(plan.read_bytes())
        alias.symlink_to(plan.name)
        options[0] = '-Dunit-shard-plan=' + str(alias)
        self.assertEqual(self.execute(options), 0)
        alias.unlink()
        alias.symlink_to(twin.name)
        self.admissions.clear()
        self.assertEqual(self.execute(options), 0)
        self.assertEqual([kind for kind, _ in self.admissions], ['build', 'build', 'gate'])
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})

    def test_shard_plan_queued_aba_refuses_before_gate(self):
        options, plan = self.shard_plan_options()
        def mutate_restore():
            original, metadata = plan.read_bytes(), plan.stat()
            plan.write_bytes(b'x' * len(original))
            plan.write_bytes(original)
            os.utime(plan, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
        self.before_gate = mutate_restore
        self.assertEqual(self.execute(options), coordinator.RETRY)
        self.assertEqual(self.events('gate'), [])
        self.assertEqual(self.receipts(), [])

    def test_shard_plan_running_aba_never_publishes_success(self):
        options, plan = self.shard_plan_options()
        def mutate_restore():
            original, metadata = plan.read_bytes(), plan.stat()
            plan.write_bytes(b'x' * len(original))
            plan.write_bytes(original)
            os.utime(plan, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
        self.after_gate = mutate_restore
        self.assertEqual(self.execute(options), coordinator.RETRY)
        self.assertEqual(len(self.events('gate')), 1)
        self.assertEqual(self.receipts(), [])

    def test_build_concurrency_defaults_use_admitted_cpus_and_respect_overrides(self):
        with patch.object(coordinator.os, 'sched_getaffinity', return_value={0, 2, 4}):
            defaults = coordinator.parse_options([])
        self.assertEqual([option for option in defaults if option.startswith('-j')], ['-j2'])
        self.assertEqual(defaults[defaults.index('--maxrss') + 1], '8589934592')
        explicit = coordinator.parse_options(['-j7', '--maxrss', '4294967296'])
        self.assertEqual(explicit.count('-j7'), 1)
        self.assertEqual(explicit[explicit.index('--maxrss') + 1], '4294967296')

    def test_maxrss_budget_reaches_every_phase_and_the_retired_audit_option_is_refused(self):
        options = coordinator.parse_options(['--maxrss', '12884901888'])
        self.assertEqual(self.execute(options), 0)
        for phase in ['plan', 'prepare', 'gate']:
            argv = self.events(phase)[0]['argv']
            self.assertEqual(argv[argv.index('--maxrss') + 1], '12884901888')
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual(report['profile_coverage']['status'], 'complete')
        for value in ['1', '8', '16']:
            with self.subTest(value=value), self.assertRaises(coordinator.VerificationError):
                coordinator.parse_options(['-Daudit-jobs=' + value])

    def test_full_gate_options_refuse_other_controls_and_the_retired_component_sources(self):
        for bad in ['-Dcomponent-owned-compiler-pin=pin.json', '-Dcomponent-seed-source=source.tar',
                    '-Dcomponent-other=path', '--prefix=other', '--cache-dir=other',
                    'verification-unit', 'test', '--maxrss8589934592']:
            with self.subTest(option=bad), self.assertRaises(coordinator.VerificationError):
                coordinator.parse_options([bad])

    def test_golden_shards_forwarded_and_bound_to_verification_identity(self):
        options = coordinator.parse_options(['-Dgolden-shards=4'])
        self.assertEqual(self.execute(options), 0)
        for phase in ['plan', 'prepare', 'gate']:
            self.assertIn('-Dgolden-shards=4', self.events(phase)[0]['argv'])
        self.assertEqual(self.execute(coordinator.parse_options(['-Dgolden-shards=1'])), 0)
        self.assertEqual(len(self.events('gate')), 2)
        for value in ['0', '5', '-1', '4x', '']:
            with self.subTest(value=value), self.assertRaises(coordinator.VerificationError):
                coordinator.parse_options(['-Dgolden-shards=' + value])

    def test_changed_options_environment_and_tool_each_invalidate(self):
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.execute(['-j4']), 0)
        with patch.dict(os.environ, {'SELKA_CORE_LEAKCHECK': '1'}):
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

    def test_zig_command_always_passes_the_proofs_flag_once(self):
        # GH-D10: without -Dproofs=true the four Lean proof actions print "skipped" and exit 0, so the gate's builds always pass it.
        for options, rerun in (([], False), (['-j3'], True), (['-Dproofs=false', '-j3'], False), (['-Dproofs=true', '-Dproofs=false'], True)):
            command = coordinator.zig_command(self.zig, ['verification-unit'], options, rerun=rerun)
            self.assertEqual([arg for arg in command if arg.startswith('-Dproofs')], ['-Dproofs=true'])
        self.assertEqual(coordinator.zig_command(self.zig, ['verification-unit'], ['-j3'])[:3],
                         [str(self.zig), 'build', 'verification-unit'])

    def test_a_user_cannot_turn_the_proofs_off_through_the_options(self):
        for value in ('false', 'true', ''):
            with self.assertRaisesRegex(coordinator.VerificationError, 'unsupported verification build option'):
                coordinator.parse_options(['-Dproofs=' + value])

    def test_every_build_the_coordinator_runs_carries_the_proofs_flag(self):
        self.assertEqual(self.execute(), 0)
        for phase in ('plan', 'prepare', 'gate'):
            self.assertTrue(self.events(phase), phase)
            for event in self.events(phase):
                self.assertIn('-Dproofs=true', event['argv'], phase)

    def test_an_inventory_exported_without_the_proofs_flag_is_refused_and_runs_no_gate(self):
        self.plan['configuration'] = {'filtered': False, 'proofs': False}
        self.save_plan()
        with self.assertRaisesRegex(coordinator.VerificationError, 'without -Dproofs=true'):
            self.execute()
        self.assertEqual(self.events('gate'), [])
        self.assertEqual(self.receipts(), [])
        path = self.write('skipped-proofs-inventory.json', json.dumps(self.plan))
        with self.assertRaisesRegex(coordinator.VerificationError, 'a skipped proof is not a pass'):
            coordinator.inventory(path)

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

    def test_telemetry_placement_is_private_and_preserves_action_reuse(self):
        observed = []
        self.plan['groups'][1]['cacheable'] = False
        self.save_plan()

        def admit(root, kind, argv, env, unchanged, **controls):
            self.assertNotIn('SELKA_TEST_TELEMETRY_DIR', env)
            if kind == 'gate':
                directory = Path(env['SELKA_VERIFICATION_TELEMETRY_DIR'])
                self.assertTrue(directory.is_dir())
                observed.append(directory)
            else:
                self.assertNotIn('SELKA_VERIFICATION_TELEMETRY_DIR', env)
            return self.admit(root, kind, argv, env, unchanged, **controls)

        with patch.dict(os.environ, SELKA_TEST_TELEMETRY_DIR='legacy-caller',
                        SELKA_VERIFICATION_TELEMETRY_DIR='caller', SELKA_MEMORY_LIMIT='512M'):
            environment = coordinator.normalized_environment(self.root)
            self.assertNotIn('SELKA_TEST_TELEMETRY_DIR', environment)
            self.assertNotIn('SELKA_VERIFICATION_TELEMETRY_DIR', environment)
            self.assertEqual(environment['SELKA_MEMORY_LIMIT'], '512M')
            self.assertEqual(os.environ['SELKA_TEST_TELEMETRY_DIR'], 'legacy-caller')
            with patch.object(coordinator, 'run_admitted', side_effect=admit):
                self.assertEqual(self.execute(), 0)
                with patch.dict(os.environ, SELKA_TEST_TELEMETRY_DIR='other-legacy',
                                SELKA_VERIFICATION_TELEMETRY_DIR='other-caller'):
                    self.assertEqual(self.execute(), 0)
        self.assertEqual(len(observed), 2)
        self.assertNotEqual(observed[0], observed[1])
        self.assertTrue(all(not directory.exists() for directory in observed))
        self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'fresh'})

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
            result = subprocess.run(command, cwd=fixture, env=environment, capture_output=True, text=True, timeout=60)
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
        stale = subprocess.run(command, cwd=source.parent, env=control, capture_output=True, text=True, timeout=60)
        self.assertEqual(stale.returncode, 0, stale.stderr)
        self.assertEqual(stale.stdout.strip(), 'old')
        fresh = subprocess.run(command, cwd=source.parent, env=environment, capture_output=True, text=True, timeout=60)
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
        environment.update(SELKA_SLOT_DIR=str(self.root / '.shell-slots'), SELKA_GATE_SLOTS='1',
                           SELKA_GATE_MEM='0', SELKA_SLOT_POLL='1', SELKA_SLOT_SETTLE='0', SELKA_TIMING_CPUS='')
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
        environment.update(SELKA_SLOT_DIR=str(self.root / '.log-slots'), SELKA_GATE_SLOTS='1',
                           SELKA_GATE_MEM='0', SELKA_SLOT_POLL='1', SELKA_SLOT_SETTLE='0', SELKA_TIMING_CPUS='')
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
        real_flock = shutil.which('flock')
        self.assertIsNotNone(real_flock)
        # Replace only the accounting timer, `flock -w SETTLE SLOT true` (it waits for the admitted job and ends
        # with it), by a barrier. Its inherited lock must survive the worker regardless of how long this observer
        # is delayed.
        sleep = self.write('.settle-tools/flock', f'''#!{sys.executable}
import os,sys
from pathlib import Path
if sys.argv[1:3] != ['-w', '2'] or sys.argv[-1] != 'true':
    os.execv({real_flock!r}, [{real_flock!r}, *sys.argv[1:]])
slots = Path(os.environ['SELKA_SLOT_DIR'])
with (slots / 'settle-ready').open('w') as ready:
    ready.write(str(os.getpid()) + '\\n')
with (slots / 'settle-release').open('rb') as release:
    if release.read(1) != b'x':
        raise SystemExit('missing settle release')
''')
        sleep.chmod(0o755)
        for expected, source in ((0, 'pass'), (124, 'import time; time.sleep(30)')):
            with self.subTest(status=expected):
                slots = self.root / ('.settle-slots-' + str(expected))
                slots.mkdir()
                environment = coordinator.normalized_environment(self.root)
                environment.update(SELKA_SLOT_DIR=str(slots), SELKA_GATE_SLOTS='1',
                                   SELKA_GATE_MEM='0', SELKA_SLOT_POLL='1', SELKA_SLOT_SETTLE='2', SELKA_TIMING_CPUS='',
                                   PATH=str(sleep.parent) + os.pathsep + environment['PATH'])
                with contextlib.ExitStack() as controls:
                    channels = []
                    for name in ('settle-ready', 'settle-release'):
                        path = slots / name
                        os.mkfifo(path)
                        channels.append(controls.enter_context(os.fdopen(
                            os.open(path, os.O_RDWR | os.O_NONBLOCK), 'r+b', buffering=0)))
                    ready, release = channels
                    try:
                        timings = []
                        status, _ = REAL_ADMISSION(self.root, 'gate', [sys.executable, '-c', source], environment,
                                                  lambda: True, timings=timings,
                                                  limits=coordinator.ProcessLimits(.1 if expected else None),
                                                  log_dir=self.root / ('.settle-logs-' + str(expected)))
                        self.assertEqual(status, expected)
                        self.assertEqual(timings[0]['log_errors'], [])
                        self.assertTrue(select.select([ready], [], [], 30)[0], 'settle helper did not announce readiness')
                        helper = int(ready.read(64))
                        self.assertEqual(os.getsid(helper), helper, 'settle helper did not detach')
                        with (slots / 'gate1.lock').open('a') as slot, (slots / 'admit.lock').open('a') as admission:
                            fcntl.flock(slot, fcntl.LOCK_EX | fcntl.LOCK_NB)
                            with self.assertRaises(BlockingIOError):
                                fcntl.flock(admission, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    finally:
                        # Also release on assertion failure; no detached fixture
                        # helper should outlive the test's private slot directory.
                        release.write(b'x')
                        with (slots / 'admit.lock').open('a') as admission:
                            deadline = time.monotonic() + 30
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
                               capture_output=True, text=True, timeout=60)
        self.assertEqual(fresh.returncode, 0, fresh.stderr)
        self.assertEqual(fresh.stdout, 'selected-tool')
        control = dict(environment, PATH=os.pathsep.join([str(missing), str(tool.parent)]))
        shadowed = subprocess.run(['identity-tool'], cwd=self.root, env=control,
                                  capture_output=True, text=True, timeout=60)
        self.assertEqual(shadowed.returncode, 0, shadowed.stderr)
        self.assertEqual(shadowed.stdout, 'shadow-tool')

    def test_filtered_inventory_keeps_native_work_fresh_and_cannot_claim_complete_verification(self):
        self.plan['configuration'] = {'filtered': True}
        self.save_plan()
        self.assertEqual(self.execute(), 3)
        self.assertEqual(self.execute(), 3)
        self.assertEqual(self.states(), {'unit': 'fresh', 'docs': 'reused'})
        self.assertEqual(len(self.receipts()), 1)
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

        def changed_publication(path, action_key, commit_blob=None):
            save(path, action_key, commit_blob)
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

        def interrupted_publication(path, action_key, commit_blob=None):
            save(path, action_key, commit_blob)
            self.assertFalse(coordinator.valid_receipt(path, action_key))
            attempted.append(path)
            raise KeyboardInterrupt

        with patch.object(coordinator, 'save_receipt', side_effect=interrupted_publication):
            with self.assertRaises(KeyboardInterrupt):
                self.execute()
        self.assertEqual(len(attempted), 1)
        self.assertFalse(attempted[0].exists())
        self.assertEqual(self.receipts(), [])

    def test_sigkill_mid_batch_leaves_no_authorized_local_or_shared_receipts(self):
        for shared_enabled in (False, True):
            with self.subTest(shared=shared_enabled):
                shared = self.root / '.kill-shared' if shared_enabled else None
                ready, notify = os.pipe()
                slots = self.root / ('.kill-slots-' + str(shared_enabled))
                environment = dict(os.environ, SELKA_SLOT_DIR=str(slots), SELKA_GATE_MEM='0',
                                   SELKA_BUILD_MEM='0', SELKA_SLOT_SETTLE='0', SELKA_TIMING_CPUS='')
                pid = os.fork()
                if pid == 0:
                    os.close(ready)
                    original, written = coordinator.save_receipt, []
                    def pause_mid_batch(path, action_key, commit_blob=None):
                        original(path, action_key, commit_blob)
                        written.append(path)
                        if len(written) == 2:
                            os.write(notify, b'ready')
                            signal.pause()
                    try:
                        with patch.dict(os.environ, environment, clear=True), \
                                patch.object(coordinator, 'run_admitted', REAL_ADMISSION), \
                                patch.object(coordinator, 'save_receipt', side_effect=pause_mid_batch):
                            self.execute(shared=shared)
                    finally:
                        os._exit(1)
                os.close(notify)
                reaped = False
                try:
                    self.assertTrue(select.select([ready], [], [], 30)[0], 'publisher did not reach staged batch')
                    self.assertEqual(os.read(ready, 5), b'ready')
                    os.kill(pid, signal.SIGKILL)
                    status = os.waitpid(pid, 0)[1]
                    reaped = True
                    self.assertEqual(status, signal.SIGKILL)
                finally:
                    os.close(ready)
                    if not reaped:
                        try:
                            os.kill(pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        os.waitpid(pid, 0)
                with patch.dict(os.environ, environment, clear=True):
                    self.assertEqual(REAL_ADMISSION(self.root, 'gate', [sys.executable, '-c', 'pass'],
                                                   environment, lambda: True)[0], 0)
                receipts = self.receipts()
                self.assertGreaterEqual(len(receipts), 2)
                self.assertTrue(all(not coordinator.valid_receipt(path, path.stem) for path in receipts))
                if shared is not None:
                    store = coordinator.fuzz_campaign_store.Store(shared)
                    self.assertTrue(all(store.load_success(path.stem) is None for path in receipts))
        self.assertEqual(self.execute(shared=self.root / '.kill-shared'), 0)
        self.assertEqual(len(self.receipts()), 2)
        self.assertTrue(all(coordinator.valid_receipt(path, path.stem) for path in self.receipts()))

    def test_unknown_action_is_covered_by_always_fresh_fallback(self):
        self.plan['groups'].append(group('unclassified', [], False))
        self.plan['coverage'].update(required_actions=3, unknown_actions=['external-step'])
        self.save_plan()
        # The registry guard every gate root depends on fails while an action is unregistered, so the cheap checks
        # end such a request before its gate; the quick profile (no cheap checks) still covers it with the fallback.
        self.assertEqual(self.execute(), 1)
        self.assertEqual(self.events('gate'), [])
        self.assertIn('unregistered action: external-step', self.child_diagnostics[-1][1])
        # A quick request is partial (status 3) whatever it runs, but it still covers the action with the fallback.
        self.assertEqual(self.execute(profile='quick', quick_actions=3), 3)
        self.assertEqual(self.execute(profile='quick', quick_actions=3), 3)
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
        environment = dict(os.environ, SELKA_SLOT_DIR=str(slots), SELKA_GATE_SLOTS='1',
                           SELKA_GATE_MEM='0', SELKA_SLOT_POLL='1', SELKA_SLOT_SETTLE='0',
                           SELKA_TIMING_CPUS='')
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
                # A loaded machine can take longer than ten seconds to enqueue a
                # private waiter; the wait is for an event, so keep a wide bound.
                deadline = time.monotonic() + 60
                try:
                    while not list((slots / 'queue-gate').glob('*.wait')):
                        self.assertLess(time.monotonic(), deadline, 'private waiter did not enqueue')
                        self.assertTrue(thread.is_alive(), errors)
                        time.sleep(.01)
                    self.input.write_text('changed while blocked behind real slot')
                finally:
                    fcntl.flock(lock, fcntl.LOCK_UN)
                    thread.join(timeout=60)
                self.assertFalse(thread.is_alive(), 'private handshake did not complete')
        self.assertEqual(errors, [])
        self.assertEqual(results[0][0], coordinator.RETRY)
        self.assertFalse(marker.exists())
        self.assertEqual(len(timings), 1)
        self.assertEqual(timings[0]['worker_seconds'], 0)
        self.assertTrue(timings[0]['admitted'])
        self.assertGreater(timings[0]['admission_wait_seconds'], 0)
        self.assertEqual(list((slots / 'queue-gate').glob('*.wait')), [])



    def test_real_handshake_runs_the_revised_command_or_nothing(self):
        slots = self.root / '.slots'
        slots.mkdir()
        environment = dict(os.environ, SELKA_SLOT_DIR=str(slots), SELKA_GATE_SLOTS='1',
                           SELKA_GATE_MEM='0', SELKA_SLOT_POLL='1', SELKA_SLOT_SETTLE='0',
                           SELKA_TIMING_CPUS='')
        planned, revised = self.root / '.planned', self.root / '.revised'
        def touch(path):
            return [sys.executable, '-c', 'from pathlib import Path; Path(__import__("sys").argv[1]).touch()', str(path)]
        timings = []
        with Snapshot(self.root, ['inputs/unit/fixture.txt']) as snapshot:
            ran = REAL_ADMISSION(self.root, 'gate', touch(planned), environment, snapshot.unchanged,
                                 timings=timings, revise=lambda: touch(revised))
            withdrawn = REAL_ADMISSION(self.root, 'gate', touch(planned), environment, snapshot.unchanged,
                                       timings=timings, revise=lambda: None)
        self.assertEqual((ran[0], withdrawn[0]), (0, 0))
        self.assertTrue(revised.exists())
        self.assertFalse(planned.exists())
        self.assertEqual([timing['withdrawn'] for timing in timings], [False, True])
        self.assertEqual(timings[1]['worker_seconds'], 0)

    # Path- and environment-free identities (output-keyed verification plan, Lane D).

    def keys(self, root=None):
        report = coordinator.read_record((root or self.root) / '.receipts/last-run.json')
        return {row['id']: row['action_key'] for row in report['actions']}

    def launcher(self, **values):
        """A launcher environment differing from the current one only in `values`."""
        return patch.dict(os.environ, values)

    def test_dropped_launcher_variables_leave_every_key_unchanged(self):
        self.assertEqual(self.execute(), 0)
        before = self.keys()
        other_tmp = self.root / 'other-tmp'
        other_tmp.mkdir()
        seen = []

        def admit(root, kind, argv, env, unchanged, **controls):
            seen.append(env)
            return self.admit(root, kind, argv, env, unchanged, **controls)
        with self.launcher(CODEX_THREAD_ID='thread-b', TERM='xterm-kitty', PWD='/somewhere/else',
                           TMPDIR=str(other_tmp)), patch.object(coordinator, 'run_admitted', side_effect=admit):
            self.admissions.clear()
            self.assertEqual(self.execute(), 0)
            self.assertEqual(self.keys(), before)
            self.assertEqual(self.states(), {'unit': 'reused', 'docs': 'reused'})
            self.assertEqual(self.admissions, [])
            self.assertEqual(self.execute(force=True), 0)
        self.assertTrue(seen)
        for env in seen:
            self.assertNotIn('CODEX_THREAD_ID', env)
            self.assertNotIn('TERM', env)
            self.assertNotIn('PWD', env)
            self.assertEqual(env['TMPDIR'], str(other_tmp))

    def test_keyed_memory_limit_changes_every_key(self):
        self.assertEqual(self.execute(), 0)
        before = self.keys()
        with self.launcher(SELKA_MEMORY_LIMIT='512M'):
            self.assertEqual(self.execute(), 0)
        after = self.keys()
        self.assertTrue(all(before[name] != after[name] for name in before))
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})

    def test_common_identity_holds_no_root_and_a_host_scope_environment_digest(self):
        env = coordinator.normalized_environment(self.root, {'PATH': os.environ['PATH'], 'PWD': str(self.root),
                                                             'CODEX_THREAD_ID': 'a', 'LANG': 'C.UTF-8',
                                                             'SELKA_VERIFICATION_SHARED_CACHE': '/elsewhere'})
        self.assertNotIn('PWD', env)
        self.assertNotIn('SHLVL', env)
        self.assertNotIn('CODEX_THREAD_ID', env)
        self.assertEqual(env['SELKA_VERIFICATION_SHARED_CACHE'], '/elsewhere')
        self.assertEqual(coordinator.identity_variables(env),
                         ['LANG', 'PYTHONDONTWRITEBYTECODE', 'PYTHONNOUSERSITE', 'PYTHONPYCACHEPREFIX'])
        moved = dict(env, SELKA_VERIFICATION_SHARED_CACHE='/other', TMPDIR='/tmp/x')
        self.assertEqual(coordinator.environment_identity(env, None, [], self.root),
                         coordinator.environment_identity(moved, None, [], self.root))
        self.assertNotEqual(coordinator.environment_identity(env, None, [], self.root),
                            coordinator.environment_identity(dict(env, LANG='C'), None, [], self.root))
        self.assertEqual(self.execute(), 0)
        report = coordinator.read_record(self.cache / 'last-run.json')
        for row in report['actions']:
            self.assertIn('ZIG', row['environment_variables'])
            self.assertIn('PYTHONNOUSERSITE', row['environment_variables'])
            self.assertNotIn('PATH', row['environment_variables'])
            self.assertNotIn('TMPDIR', row['environment_variables'])
            # The fixture's Zig lives inside the checkout, so ZIG names the root.
            self.assertFalse(row['path_free'])

    def test_tool_content_enters_the_environment_digest_by_snapshot_digest(self):
        with Snapshot(self.root, [], [self.zig, self.tool]) as tools:
            env = {'SELKA_ZIG': 'zig'}
            first = coordinator.environment_identity(env, tools, [self.zig, self.tool], self.root)
            only_zig = coordinator.environment_identity(env, tools, [self.zig], self.root)
        self.assertNotEqual(first, only_zig)
        self.tool.write_text('changed tool')
        with Snapshot(self.root, [], [self.zig, self.tool]) as tools:
            self.assertNotEqual(coordinator.environment_identity(env, tools, [self.zig, self.tool], self.root), first)

    def two_roots(self, producer, component_cache=""):
        """Two checkouts with identical contents at different absolute paths, sharing one Zig."""
        self.plan['groups'].extend([dict(group('pure', ['inputs/docs/']), artifacts=[]),
                                    dict(group('native', ['inputs/unit/']), artifacts=['units'])])
        self.plan['coverage'].update(required_actions=4, registered_actions=4)
        self.save_plan()
        self.write('.embed-root', '')
        if producer is not None:
            self.write('.producer', json.dumps(producer))
        shared = Path(self.stack.enter_context(tempfile.TemporaryDirectory(prefix='verification-tools-', dir=REPOSITORY / '.tmp')))
        zig = shared / 'zig'
        shutil.copy2(self.zig, zig)
        other = Path(self.stack.enter_context(tempfile.TemporaryDirectory(prefix='verification-twin-', dir=REPOSITORY / '.tmp'))) / 'checkout'
        shutil.copytree(self.root, other, symlinks=True)
        self.stack.enter_context(patch.object(coordinator, 'tool_contract', return_value=([], [zig])))
        reports = []
        for root in (self.root, other):
            # This fixture proves path-free identities. An inherited keyed
            # component-cache path correctly makes every action
            # location-dependent. Select it explicitly here.
            with self.launcher(SELKA_COMPONENT_CACHE=component_cache), \
                    contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(coordinator.execute(root, root / '.receipts', zig, ['-j3']), 0)
            reports.append(coordinator.read_record(root / '.receipts/last-run.json'))
        return reports

    def producer(self, recipes=('sources/', 'config.zig')):
        return {'recipes': list(recipes), 'optimize': 'Debug', 'zig_version': '0.16.0',
                'test_runner': 'guardian-zig-test-runner-v1'}

    def test_two_roots_with_producers_share_every_action_key(self):
        first, second = self.two_roots(self.producer())
        self.assertNotEqual((self.root / 'zig-out/bin/units').read_bytes(),
                            (Path(second['evidence_store']['root']).parent.parent / 'zig-out/bin/units').read_bytes())
        self.assertEqual({row['id']: row['action_key'] for row in first['actions']},
                         {row['id']: row['action_key'] for row in second['actions']})
        identities = first['artifact_identities']
        for label in ('selka', 'units', 'cli', 'core'):
            self.assertEqual(identities[label]['identity'], 'producer')
            self.assertGreaterEqual(identities[label]['sources'], 2)
        self.assertEqual(identities['components']['identity'], 'bytes')
        self.assertEqual({row['id']: row['path_free'] for row in first['actions']},
                         {'unit': False, 'docs': False, 'pure': True, 'native': True})

    def test_a_components_producer_makes_every_action_path_free_across_roots(self):
        self.write('.component-producer', '')
        first, second = self.two_roots(self.producer())
        self.assertEqual({row['id']: row['action_key'] for row in first['actions']},
                         {row['id']: row['action_key'] for row in second['actions']})
        self.assertEqual(first['artifact_identities']['components']['identity'], 'producer')
        self.assertEqual({row['id']: row['path_free'] for row in first['actions']},
                         {'unit': True, 'docs': True, 'pure': True, 'native': True})

    def test_absolute_component_cache_keeps_every_action_location_dependent(self):
        self.write('.component-producer', '')
        first, second = self.two_roots(self.producer(), component_cache='/private/components')
        for report in (first, second):
            self.assertFalse(any(row['path_free'] for row in report['actions']))
            for row in report['actions']:
                self.assertIn('SELKA_COMPONENT_CACHE', row['environment_variables'])
        self.assertEqual({row['id']: row['action_key'] for row in first['actions']},
                         {row['id']: row['action_key'] for row in second['actions']})

    def test_relocated_loaded_code_digests_make_every_action_location_dependent(self):
        # Format 1 bound each code object's absolute file name. The root search
        # cannot see that inside a digest; the relocation probe does.
        self.write('.component-producer', '')
        # Authenticate the genuine watched helper before simulating the legacy
        # digest format. A cold test must not depend on a prior test's proof,
        # and changing the helper itself must not bypass bootstrap validation.
        with patch.object(coordinator, '_CODE_HELPER_SOURCE_PROOF', None):
            self.assertEqual(self.execute(), 0)
            self.assertIsNotNone(coordinator._CODE_HELPER_SOURCE_PROOF)
            with patch.object(coordinator.code_identity, '_relocatable_filename', lambda filename: filename):
                self.assertIn('verify_cache', coordinator.location_dependent_code())
                first, _ = self.two_roots(self.producer())
        self.assertEqual(first['relocation_dependent_code'],
                         [name for name, _, _ in coordinator.implementation_code()] + ['verification_code_identity'])
        self.assertEqual({row['id']: row['path_free'] for row in first['actions']},
                         {'unit': False, 'docs': False, 'pure': False, 'native': False})
        self.assertEqual(coordinator.location_dependent_code(), [])

    def test_unclassified_common_facet_or_located_inventory_is_not_path_free(self):
        self.write('.component-producer', '')
        with patch.dict(coordinator.COMMON_FACETS):
            del coordinator.COMMON_FACETS['action_controls']
            first, _ = self.two_roots(self.producer())
        self.assertFalse(any(row['path_free'] for row in first['actions']))
        contract = json.loads((self.root / 'gate-contract.json').read_text())
        contract['input_lists'].append({'name': 'located', 'inputs': [str(self.root) + '/fixture']})
        self.write('gate-contract.json', json.dumps(contract))
        self.assertEqual(self.execute(), 0)
        self.assertFalse(any(row['path_free'] for row in coordinator.read_record(self.cache / 'last-run.json')['actions']))

    def test_dry_run_exports_keys_without_gate_or_publication(self):
        self.assertEqual(self.execute(dry_run=True), 0)
        self.assertEqual([kind for kind, _ in self.admissions], ['build', 'build'])
        export = coordinator.read_record(self.cache / 'dry-run.json')
        self.assertFalse((self.cache / 'last-run.json').exists())
        self.assertEqual(list((self.cache / 'actions').glob('*.json')) if (self.cache / 'actions').exists() else [], [])
        self.assertEqual({row['state'] for row in export['actions']}, {'execute'})
        self.assertEqual(export['declarative_configuration'], 'excluded')
        self.assertEqual(set(export['common']) - set(coordinator.COMMON_FACETS), set())
        self.assertEqual(self.execute(), 0)
        keys = {row['id']: row['action_key'] for row in coordinator.read_record(self.cache / 'last-run.json')['actions']}
        self.assertEqual({row['id']: row['action_key'] for row in export['actions']}, keys)
        self.assertEqual(self.execute(dry_run=True), 0)
        self.assertEqual({row['state'] for row in coordinator.read_record(self.cache / 'dry-run.json')['actions']}, {'reused'})
        self.assertRaises(ValueError, self.execute, force=True, dry_run=True)

    def test_missing_producer_falls_back_to_reported_byte_identity(self):
        first, second = self.two_roots(None)
        first_keys = {row['id']: row['action_key'] for row in first['actions']}
        second_keys = {row['id']: row['action_key'] for row in second['actions']}
        self.assertEqual(first_keys['pure'], second_keys['pure'])
        for name in ('unit', 'docs', 'native'):
            self.assertNotEqual(first_keys[name], second_keys[name])
        for label in ('selka', 'units', 'cli', 'core', 'components'):
            self.assertEqual(first['artifact_identities'][label],
                             {'identity': 'bytes', 'reason': 'artifact inventory is not version 3'})
        self.assertEqual({row['id']: row['path_free'] for row in first['actions']},
                         {'unit': False, 'docs': False, 'pure': True, 'native': False})

    def test_producer_recipe_selecting_nothing_is_a_hard_error(self):
        self.write('.producer', json.dumps(self.producer(('sources/', 'missing/'))))
        with self.assertRaisesRegex(coordinator.VerificationError, 'selects no watched input: missing/'):
            self.execute()
        self.assertEqual(self.events('gate'), [])
        self.assertEqual(self.receipts(), [])

    def test_producer_source_change_invalidates_and_bytes_alone_do_not(self):
        self.write('.producer', json.dumps(self.producer()))
        self.plan['groups'].append(dict(group('native', ['inputs/unit/']), artifacts=['units']))
        self.plan['coverage'].update(required_actions=3, registered_actions=3)
        self.save_plan()
        self.assertEqual(self.execute(), 0)
        before = self.keys()
        self.write('sources/compiler.txt', 'changed compiler source')
        self.assertEqual(self.execute(), 0)
        self.assertNotEqual(self.keys()['native'], before['native'])
        self.assertEqual(self.states()['native'], 'execute')

    def test_schema_two_receipts_are_never_read(self):
        self.assertEqual(coordinator.CACHE_DIRECTORY, Path('.selka-cache/verification-v3'))
        self.assertEqual(self.execute(), 0)
        for path in self.receipts():
            path.write_text(json.dumps({'version': 2, 'kind': 'verification-success', 'key': path.stem}))
        self.admissions.clear()
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})
        self.assertEqual(json.loads(self.receipts()[0].read_text())['version'], 3)

    def test_shared_cache_location_switch_and_precedence(self):
        home = {'HOME': '/home/agent'}
        for switch in (False, True):
            with self.subTest(default_sharing=switch), patch.object(coordinator, 'DEFAULT_SHARING', switch):
                expected = (Path('/home/agent/.cache/selka/verification-shared'), 'default') if switch else (None, 'none')
                self.assertEqual(coordinator.shared_cache_location(None, home), expected)
                xdg = dict(home, XDG_CACHE_HOME='/var/cache/agent')
                self.assertEqual(coordinator.shared_cache_location(None, xdg),
                                 (Path('/var/cache/agent/selka/verification-shared'), 'default') if switch else (None, 'none'))
                relative = dict(home, XDG_CACHE_HOME='relative')
                self.assertEqual(coordinator.shared_cache_location(None, relative), expected)
                named = dict(home, SELKA_VERIFICATION_SHARED_CACHE='/srv/evidence')
                self.assertEqual(coordinator.shared_cache_location(None, named), (Path('/srv/evidence'), 'environment'))
                self.assertEqual(coordinator.shared_cache_location(None, dict(home, SELKA_VERIFICATION_SHARED_CACHE='')),
                                 (None, 'environment'))
                self.assertEqual(coordinator.shared_cache_location('/flag', named), (Path('/flag'), 'flag'))
                self.assertEqual(coordinator.shared_cache_location('', named), (None, 'flag'))
        self.assertTrue(coordinator.DEFAULT_SHARING)

    def test_unusable_default_store_warns_and_explicit_store_fails(self):
        blocked = self.write('not-a-directory', 'file')
        stderr = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(stderr):
            status = coordinator.execute(self.root, self.cache, self.zig, ['-j3'], False, blocked,
                                         shared_cache_source='default')
        self.assertEqual(status, 0)
        self.assertEqual(stderr.getvalue().count('default shared evidence store'), 1)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual(report['evidence_store']['shared'], False)
        self.assertEqual(report['evidence_store']['source'], 'default')
        for source in ('flag', 'environment'):
            with self.subTest(source=source), self.assertRaises(OSError):
                with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    coordinator.execute(self.root, self.cache, self.zig, ['-j3'], False, blocked,
                                        shared_cache_source=source)
        shared = self.root / '.default-evidence'
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(coordinator.execute(self.root, self.cache, self.zig, ['-j3'], True, shared,
                                                 shared_cache_source='default'), 0)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertEqual(report['evidence_store']['shared'], True)
        self.assertEqual(report['evidence_store']['source'], 'default')

    def test_retained_session_reuses_across_launchers_differing_in_dropped_variables(self):
        with RetainedSession() as session, session.activate():
            self.assertEqual(self.execute(), 0)
            before = self.keys()
            self.admissions.clear()
            with self.launcher(CODEX_THREAD_ID='another-agent', TERM='screen', SSH_CONNECTION='x', OLDPWD='/'):
                self.assertEqual(self.execute(), 0)
            report = coordinator.read_record(self.cache / 'last-run.json')
            self.assertEqual(self.keys(), before)
            self.assertEqual(self.admissions, [])
            self.assertEqual(report['snapshot_statistics']['files_hashed'], 0)
            with self.launcher(SELKA_CORE_LEAKCHECK='1'):
                self.assertEqual(self.execute(), 0)
            self.assertEqual(self.states(), {'unit': 'execute', 'docs': 'execute'})


class CheapCheckCommands(unittest.TestCase):
    """The cheap checks run the gate actions' own commands (`gate_cheap_checks.py`); these pin each to build.zig and
    read a finding's file and line out of each tool's output."""

    checks = coordinator.gate_cheap_checks

    def build_source(self):
        return (REPOSITORY / 'build.zig').read_text()

    def test_the_zig_format_paths_are_those_build_zig_formats(self):
        call = re.search(r'b\.addFmt\(\.\{(.*?)\}\);', self.build_source(), re.S)
        self.assertIsNotNone(call)
        paths = re.search(r'\.paths = &\.\{([^}]*)\}', call.group(1))
        self.assertEqual(tuple(re.findall(r'b\.path\("([^"]+)"\)', paths.group(1))), self.checks.ZIG_FORMAT_PATHS)
        # The cheap check passes no `--exclude`: build.zig's formatter must exclude nothing, and check only.
        self.assertNotIn('exclude_paths', call.group(1))
        self.assertIn('.check = true', call.group(1))

    def test_the_other_commands_are_those_build_zig_runs(self):
        source = self.build_source()
        self.assertIn('"python3", "scripts/check_my_format.py", "--compiler"', source)
        self.assertIn('addArgs(&.{ "doc-coverage", "." })', source)
        for _action, arguments in self.checks.COVERAGE_COMMANDS:
            self.assertIn('"python3", ' + ', '.join('"%s"' % word for word in arguments) + ' }', source)

    def test_the_my_format_check_calls_the_gate_script_s_own_per_file_check(self):
        calls = []
        sys.path.insert(0, str(REPOSITORY / 'scripts'))
        import check_my_format
        sys.path.pop(0)

        def check_source(compiler, source, root, env=None):
            calls.append(source)
            return None
        with tempfile.TemporaryDirectory(dir=REPOSITORY / '.tmp') as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            shutil.copy2(REPOSITORY / 'scripts' / 'check_my_format.py', root / 'scripts')
            (root / 'scripts' / 'my_format_exclusions.json').write_text('{}')
            (root / 'tests').mkdir()
            (root / 'tests' / 'a.selka').write_text('x\n')
            with patch.object(check_my_format, 'check_source', side_effect=check_source):
                found = self.checks.my_format(self.checks.Context(root=root, zig='zig', compiler=root / 'selka'))
        self.assertEqual((found, calls), ([], ['tests/a.selka']))

    def test_the_input_coverage_commands_run_the_python3_on_path_as_the_action_does(self):
        with tempfile.TemporaryDirectory(dir=REPOSITORY / '.tmp') as directory:
            root = Path(directory)
            (root / 'bin').mkdir()
            marker = root / 'ran'
            python = root / 'bin' / 'python3'
            python.write_text('#!/bin/sh\necho "$@" >> %s\n' % marker)
            python.chmod(0o755)
            (root / 'tests').mkdir()
            for name in ('test_inputs_coverage.py', 'input_manifest.py'):
                (root / 'tests' / name).write_text('')
            env = dict(os.environ, PATH=str(root / 'bin'))
            self.assertEqual(self.checks.inputs_coverage(self.checks.Context(root=root, zig='zig', env=env)), [])
            self.assertEqual(len(marker.read_text().splitlines()), 3)

    def fake_tool(self, directory, body):
        path = Path(directory) / 'tool'
        path.write_text('#!%s\nimport sys\n%s\n' % (sys.executable, body))
        path.chmod(0o755)
        return path

    def test_a_zig_format_finding_names_the_first_line_zig_fmt_would_change(self):
        with tempfile.TemporaryDirectory(dir=REPOSITORY / '.tmp') as directory:
            root = Path(directory)
            (root / 'src').mkdir()
            (root / 'src' / 'a.zig').write_text('const a = 1;\nconst  b = 2;\n')
            zig = self.fake_tool(directory, "if '--stdin' in sys.argv:\n    sys.stdout.write(sys.stdin.read().replace('  ', ' '))\n"
                                            "else:\n    print(%r); sys.exit(1)" % str(root / 'src' / 'a.zig'))
            found = self.checks.zig_format(self.checks.Context(root=root, zig=str(zig)))
        self.assertEqual([(item.check, item.location) for item in found], [('zig-format', 'src/a.zig:2')])

    def test_a_doc_coverage_finding_names_the_feature_and_its_page(self):
        output = ('doc-coverage: 356 documented features across 66 pages\n  docs/bytes.md: 9\n'
                  "  ! declared-borrowed-results: 'docs/managed-memory.md' has no heading with anchor 'x'\n"
                  'doc-coverage: 1 failures\n')
        with tempfile.TemporaryDirectory(dir=REPOSITORY / '.tmp') as directory:
            compiler = self.fake_tool(directory, 'sys.stdout.write(%r); sys.exit(1)' % output)
            found = self.checks.doc_coverage(self.checks.Context(root=Path(directory), zig='zig', compiler=compiler))
        self.assertEqual([(item.location, item.message) for item in found], [(
            'docs/managed-memory.md', "declared-borrowed-results: 'docs/managed-memory.md' has no heading with anchor 'x'")])

    def test_a_my_format_finding_keeps_the_compiler_s_file_line_and_column(self):
        with tempfile.TemporaryDirectory(dir=REPOSITORY / '.tmp') as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            shutil.copy2(REPOSITORY / 'scripts' / 'check_my_format.py', root / 'scripts')
            (root / 'scripts' / 'my_format_exclusions.json').write_text('{}')
            (root / 'tests').mkdir()
            (root / 'tests' / 'good.selka').write_text('x\n')
            (root / 'tests' / 'bad.selka').write_text('y\n')
            compiler = self.fake_tool(directory, "if 'bad' in sys.argv[2]:\n"
                                                 "    print(sys.argv[2] + ':3:7: formatting differs'); sys.exit(1)")
            found = self.checks.my_format(self.checks.Context(root=root, zig='zig', compiler=compiler))
        self.assertEqual([(item.location, item.message) for item in found],
                         [('tests/bad.selka:3', 'tests/bad.selka:3:7: formatting differs')])

    def test_stopping_the_checks_ends_their_running_commands(self):
        with tempfile.TemporaryDirectory(dir=REPOSITORY / '.tmp') as directory:
            pid = Path(directory) / 'pid'
            context = self.checks.Context(root=Path(directory), zig='zig')
            runner = self.checks.Runner(context)
            command = [sys.executable, '-c', 'import os,sys,time\nopen(sys.argv[1],"w").write(str(os.getpid()))\n'
                       'time.sleep(60)', str(pid)]
            with patch.dict(self.checks.RUNNERS, {'zig-format': lambda ctx: self.checks.run(ctx, command) and []}):
                runner.start(['zig-format'])
                deadline = time.monotonic() + 10
                while not pid.exists() and time.monotonic() < deadline:
                    time.sleep(.05)
                began = time.monotonic()
                runner.stop()
                runner.threads[0].join(10)
            self.assertLess(time.monotonic() - began, 5)
            self.assertFalse(runner.threads[0].is_alive())
            state = Path('/proc/%s/stat' % pid.read_text())
            # Gone, or a zombie: the gate runs tests under a subreaper, which reaps orphans later.
            self.assertTrue(not state.exists() or state.read_text().rsplit(') ', 1)[1].split()[0] in ('Z', 'X'),
                            'its process was ended')
            self.assertIn('zig-format', runner.errors)
            with self.assertRaises(OSError):
                self.checks.run(context, ['true'])

    def test_the_summary_names_each_action_and_its_file_line_within_its_budget(self):
        findings = [self.checks.Finding('zig-format', 'zig fmt would change this line', 'src/a.zig:%d' % index)
                    for index in range(1, 7)] + [self.checks.Finding('doc-coverage', 'feature x: no page', 'src/b.zig')]
        lines = self.checks.summary_lines(findings, 8)
        self.assertEqual(lines[0], 'failure 1/2: zig-format (a cheap check, before any test action)')
        self.assertIn('  src/a.zig:1: zig fmt would change this line', lines)
        self.assertLessEqual(len(lines), 8)


class FlakyRerunParts(unittest.TestCase):
    """Item 4d's pieces: a native step's command for one test, the deferred --fail-fast stop, and the log reader."""

    def test_a_native_step_reruns_one_test_by_name_with_the_same_wrapper_binary_and_environment(self):
        import verification_rerun
        record = {'kind': 'native', 'action': 'cli', 'member': 4, 'cwd': '/w', 'env': {'A': '1'},
                  'argv': ['sh', '-c', 'script', 'with-tools', '/b/build-env', 'SELKA_ZIG=/z', '/o/test', '--listen=-',
                           '--test-shard=2/6', '--test-shard-plan', 'plan.json']}
        with tempfile.TemporaryDirectory(dir=REPOSITORY / '.tmp') as directory:
            step = verification_rerun.plan(record, 'test/integration.zig::fix_cli_test.test.CLI fix', Path(directory))
            listing = [word for word in step['argv'] if word.startswith('--test-list=')][0].split('=', 1)[1]
            self.assertEqual(Path(listing).read_text(), 'fix_cli_test.test.CLI fix\n')
        self.assertEqual(step['argv'][:7], record['argv'][:7])
        self.assertNotIn('--listen=-', step['argv'])
        self.assertFalse(any(word.startswith('--test-shard') or word == 'plan.json' for word in step['argv']))
        self.assertEqual((step['cwd'], step['env'], step['timeout']), ('/w', {'A': '1'}, 300.0), 'the idle bound, one test alone')

    def test_fail_fast_waits_for_named_test_beacons_up_to_the_limit_and_stops_for_anything_else(self):
        with tempfile.TemporaryDirectory(dir=REPOSITORY / '.tmp') as directory:
            folder = Path(directory)
            watch = coordinator.verification_process.FailFast(folder, interval=0, defer=coordinator.flaky_beacon, limit=2)
            (folder / 'fail-fast.unit.member.0.txt').write_text("error: 'root::a' failed\nfailed command: x\n")
            self.assertFalse(watch())
            (folder / 'fail-fast.cli.member.1.txt').write_text("error: 'root::b' timed out\nfailed command: x\n")
            self.assertFalse(watch())
            (folder / 'fail-fast.core.member.2.txt').write_text("error: 'root::c' failed\nfailed command: x\n")
            self.assertTrue(watch(), 'more beacons than the limit stop the build')
            other = coordinator.verification_process.FailFast(folder / 'other', interval=0, defer=coordinator.flaky_beacon, limit=5)
            (folder / 'other').mkdir()
            (folder / 'other' / 'fail-fast.driver.7.txt').write_text('FAIL: x\nfailed command: sh scripts/quiet-driver.sh python3 tests/x.py\n')
            self.assertTrue(other(), 'a failure that names no test stops it at once')
        self.assertTrue(coordinator.flaky_beacon('FAIL: t (m.C.t)\nfailed command: sh scripts/quiet-driver.sh python3 -c import '
                                                 'verification_telemetry --action-id verification_cache m\n'))

    def test_the_flaky_log_reader_groups_by_test(self):
        import verification_rerun
        with tempfile.TemporaryDirectory(dir=REPOSITORY / '.tmp') as directory:
            log = Path(directory) / 'flaky.jsonl'
            log.write_text('\n'.join(json.dumps({'action': 'cli', 'test': 't', 'time': '2026-11-13T1%d' % index,
                                                  'f22': index == 1, 'head': 'abc'}) for index in range(3)) + '\n')
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                verification_rerun.main(['--log', str(log)])
        self.assertIn('  3  cli  t  last 2026-11-13T12  F22 1  heads abc', output.getvalue())


class FlakyEligibilityParts(unittest.TestCase):
    """The guest half of D-DL4-19 and the rerun's own proof that its one test ran and passed."""

    def test_a_language_member_with_no_report_beside_one_with_a_failed_test_is_not_eligible(self):
        with tempfile.TemporaryDirectory(dir=REPOSITORY / '.tmp') as directory:
            root = Path(directory)
            (root / 'tests/value_semantics').mkdir(parents=True)
            (root / 'tests/value_semantics/b.selka').write_text('x\n')
            (root / 'tests/lang').mkdir(parents=True)
            metadata = {'language': {'steps': [{'original_label': 'selka test tests/lang --verify-facts (leak check)'},
                                               {'original_label': 'selka test tests/value_semantics --verify-facts (leak check)'}]}}
            text = ('+- verification action language member 0 failure\nerror: process exited with code 134\n'
                    'failed command: x\n+- verification action language member 1 failure\n'
                    '{"version":"native-tests-v1","tests":[{"name":"b::test_y","status":"failed"}]}\nfailed command: y\n'
                    'Build Summary: 2/4 steps succeeded (2 failed)\n')
            found, reason = coordinator.eligible_failures(root, root, [{'id': 'language'}], metadata, text)
            self.assertIsNone(found)
            self.assertEqual(reason, 'language member 0 (tests/lang) has 0 test reports, not one')
            guarded = text.replace('Build Summary', 'test-lang guard: unexpected unsupported verdict\nBuild Summary')
            self.assertEqual(coordinator.eligible_failures(root, root, [{'id': 'language'}], metadata, guarded)[1],
                             'the language guard reported an error')

    def test_a_rerun_passes_only_when_its_runner_says_the_one_test_ran_and_passed(self):
        import verification_rerun
        native = {'expect': {'kind': 'native'}}
        self.assertTrue(verification_rerun.ran_and_passed(native, 0, 'test: RESULT {"passed":1,"failed":0,"skipped":0}')[0])
        self.assertFalse(verification_rerun.ran_and_passed(native, 0, 'test: RESULT {"passed":0,"failed":0,"skipped":1}')[0])
        self.assertFalse(verification_rerun.ran_and_passed(native, 0, 'no result line')[0])
        guest = {'expect': {'kind': 'guest', 'test': 'a::t'}}
        self.assertFalse(verification_rerun.ran_and_passed(guest, 0, '{"version":"native-tests-v1","tests":[{"name":"a::t","status":"cached"}]}')[0])
        self.assertTrue(verification_rerun.ran_and_passed(guest, 0, '{"version":"native-tests-v1","tests":[{"name":"a::t","status":"passed"}]}')[0])
        self.assertEqual(verification_rerun.native_bound({'SELKA_TEST_DEADLINE_SECONDS': '900'}), 300.0)


class DiskWait(unittest.TestCase):
    """Item 4f: a gate waits for a saturated disk before asking for admission, bounded, saying why."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=REPOSITORY / '.tmp')
        self.addCleanup(self.directory.cleanup)
        self.file = Path(self.directory.name) / 'io'
        patcher = patch.object(coordinator, 'PRESSURE_FILE', self.file)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.now = 0.0

    def pressure(self, full):
        self.file.write_text('some avg10=1.00 avg60=%.2f avg300=1.00 total=1\nfull avg10=1.00 avg60=%.2f avg300=1.00 '
                             'total=1\n' % (full, full))

    def wait(self, figures, **options):
        """Run the wait on a fake clock; each poll reads the next figure."""
        figures = list(figures)
        self.pressure(figures.pop(0))

        def sleep(seconds):
            self.now += seconds
            if figures:
                self.pressure(figures.pop(0))
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = coordinator.wait_for_disk(clock=lambda: self.now, sleep=sleep, **options)
        return result, output.getvalue().splitlines()

    def test_a_saturated_disk_makes_the_gate_wait_and_say_why_until_it_calms(self):
        result, lines = self.wait([59.6] * 30 + [12.0])
        self.assertEqual((result['seconds'], result['gave_up'], result['first'], result['last']), (150.0, False, 59.6, 12.0))
        self.assertIn('waiting for the disk before asking for admission: full avg60 59.6% > 25%', lines[0])
        self.assertIn('the disk is calm (full avg60 12.0%) after 150 s', lines[1])
        self.assertEqual(len(lines), 2, 'one line when the wait starts, one when it ends')

    def test_the_wait_is_bounded_and_then_the_gate_starts_under_pressure(self):
        result, lines = self.wait([60.0] * 1000)
        self.assertTrue(result['gave_up'])
        self.assertEqual(result['seconds'], coordinator.DISK_WAIT_SECONDS)
        self.assertIn('starting under disk pressure', lines[-1])
        self.assertEqual(len(lines), 2)

    def test_a_calm_disk_or_no_pressure_accounting_waits_for_nothing(self):
        result, lines = self.wait([3.0])
        self.assertEqual((result['seconds'], lines), (0.0, []))
        self.file.unlink()
        self.assertIsNone(coordinator.disk_pressure())
        self.assertEqual(coordinator.wait_for_disk(clock=lambda: 0.0, sleep=self.fail)['seconds'], 0.0)
        self.file.write_text('some avg10=1.00 avg60=80.00 avg300=1.00 total=1\n')
        self.assertIsNone(coordinator.disk_pressure(), 'only the full line counts')

    def test_the_option_turns_the_wait_off_and_the_summary_says_how_long_a_gate_waited(self):
        calls = []
        root = Path(self.directory.name) / 'root'
        root.mkdir()
        with patch.object(coordinator, 'ROOT', root), patch.object(coordinator, 'bound_caches'), \
                patch.object(coordinator, 'stage_store_root', return_value=None), \
                patch.object(coordinator, 'execute_with_restarts', side_effect=lambda *a, **k: calls.append(k['disk_waiter']) or 0):
            self.assertEqual(coordinator.main(['--zig', sys.executable, '--no-disk-wait']), 0)
            self.assertEqual(coordinator.main(['--zig', sys.executable]), 0)
        self.assertEqual([waiter.enabled for waiter in calls], [False, True])
        self.assertEqual([waiter.result for waiter in calls], [None, None], 'main itself waits for nothing')
        report = {'success': True, 'elapsed_seconds': 400.0, 'actions': [], 'disk_wait': {'seconds': 612.0, 'gave_up': False}}
        self.assertIn('waited 612 s for the disk', coordinator.gate_summary.summarize(report=report)[0])



class IntegrationGate(unittest.TestCase):
    """`--integration` (the nightly): its own stores, D1 forced fact/leak run, D3 mismatch failure, the two-run step and
    the statuses of D-NIGHTLY-1."""

    METADATA = [{'id': 'language', 'steps': [
        {'kind': 'run', 'original_label': 'selka test tests/lang'},
        {'kind': 'run', 'original_label': 'selka test tests/lang --verify-facts (leak check)'},
        {'kind': 'run', 'original_label': 'selka test tests/ported --unoptimized'},
        {'kind': 'run', 'original_label': 'selka test tests/ported --verify-facts (leak check)'},
        {'kind': 'run', 'original_label': 'selka test tests/lang --release --verify-facts (leak check)'}]},
        {'id': 'unit', 'steps': [{'kind': 'run', 'original_label': 'selka test tests/x --release --verify-facts (leak check)'}]}]
    RERUN_OK = 'test-lang-rerun: tests/lang: ok\ntest-lang-rerun: tests/ported: ok\n'

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='integration-', dir=REPOSITORY / '.tmp')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.cache = self.root / 'cache'
        self.cache.mkdir()
        # The "per-user" store of these tests: the store the caller's environment selects.
        self.store = self.root / 'store'
        (self.store / 'compiler-artifacts-v2').mkdir(parents=True)
        self.env = {'SELKA_COMPILER_SHARED_CACHE': str(self.store), 'SELKA_TEST_SHARED_CACHE': ''}
        self.calls, self.admissions = [], []

    @contextlib.contextmanager
    def admission(self, kind):
        self.admissions.append(kind)
        yield

    def run_suite(self, cached=0, failed=0, status=0, rerun=(0, RERUN_OK, ''), own_mismatch=None):
        """A stand-in for subprocess.run: `selka test` prints a report; `zig build test-lang-rerun` prints RERUN. With
        OWN_MISMATCH, the first build writes that line to the own compiler store it was given, as a store would."""
        def run(argv, **options):
            self.calls.append((argv, options))
            if own_mismatch is not None:
                own = Path(options['env']['SELKA_COMPILER_SHARED_CACHE']) / 'compiler-artifacts-v2'
                own.mkdir(exist_ok=True)
                (own / 'mismatches.log').write_text(own_mismatch + '\n')
            if argv[1:3] == ['build', 'test-lang-rerun']:
                return subprocess.CompletedProcess(argv, rerun[0], rerun[1], rerun[2])
            report = {'passed': 3 - cached - failed, 'failed': failed, 'cached': cached, 'skipped': 0, 'unsupported': 0}
            return subprocess.CompletedProcess(argv, status, json.dumps(report) + '\n', '')
        return run

    def log(self, lines, store=None):
        (store or self.store / 'compiler-artifacts-v2').mkdir(parents=True, exist_ok=True)
        ((store or self.store / 'compiler-artifacts-v2') / 'mismatches.log').write_text(
            ''.join('mismatch program %064x existing=%064x attempted=%064x\n' % (n, n, n + 1) for n in range(lines)))

    def write_report(self):
        coordinator.atomic_record(self.cache / 'last-run.json',
                                  {'version': 1, 'success': True, 'status': 0, 'action_metadata': self.METADATA})

    def integrate(self, status=0, before=None, run=None, zig=Path('/bin/zig'), own=None):
        with contextlib.redirect_stdout(io.StringIO()) as out, contextlib.redirect_stderr(io.StringIO()):
            result = coordinator.integrate(self.root, self.cache, status, {} if before is None else before, self.env,
                                           run=run or self.run_suite(), admission=self.admission, own=own, zig=zig)
        self.out = out.getvalue()
        return result

    def record(self):
        return coordinator.read_record(self.cache / 'integration-last-run.json')

    def test_fact_leak_suites_come_from_the_language_inventory(self):
        self.assertEqual(coordinator.fact_leak_suites(self.METADATA), ['tests/lang', 'tests/ported'])
        self.assertEqual(coordinator.fact_leak_suites([]), [])

    def test_forced_run_is_fresh_private_and_admitted_once(self):
        self.write_report()
        own = coordinator.own_stores(self.cache)
        self.assertEqual(self.integrate(own=own), 0)
        self.assertEqual(self.admissions, ['gate', 'gate'], 'one admission for the forced run, one for the two-run step')
        self.assertEqual([call[0][2] for call in self.calls[:2]], ['tests/lang', 'tests/ported'])
        for argv, options in self.calls[:2]:
            self.assertIn('--force', argv)
            self.assertIn('--verify-facts', argv)
            self.assertNotIn('--release', argv)
            self.assertEqual(options['env']['SELKA_CORE_LEAKCHECK'], '1')
            private = Path(argv[argv.index('--cache-dir') + 1])
            self.assertTrue(private.is_relative_to(self.cache / 'integration'))
            self.assertFalse(private.exists())
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertTrue(report['success'])
        self.assertTrue(report['integration']['forced_fact_leak']['passed'])

    def test_every_build_of_the_checks_uses_the_request_s_own_stores_and_a_pass_removes_them(self):
        self.write_report()
        own = coordinator.own_stores(self.cache)
        self.assertEqual(sorted(path.name for path in own.iterdir()), ['compiler', 'tests'])
        self.assertTrue(own.is_relative_to(self.cache / 'integration'))
        self.assertEqual(self.integrate(own=own), 0)
        self.assertEqual(len(self.calls), 3)
        for _, options in self.calls:
            self.assertEqual(options['env']['SELKA_COMPILER_SHARED_CACHE'], str(own / 'compiler'))
            self.assertEqual(options['env']['SELKA_TEST_SHARED_CACHE'], str(own / 'tests'))
            self.assertEqual(options['env']['SELKA_STAGE_SHARED_CACHE'], '', 'no check writes the per-user stage store')
        self.assertFalse(own.exists(), 'a passing request removes its own stores')
        self.assertEqual(self.record()['own_stores']['kept'], False)

    def test_an_earlier_request_s_kept_stores_are_removed_by_the_next_one(self):
        first = coordinator.own_stores(self.cache)
        (first / 'compiler' / 'record').write_text('x')
        second = coordinator.own_stores(self.cache)
        self.assertFalse(first.exists())
        self.assertEqual([path.name for path in (self.cache / 'integration').iterdir()], [second.name])
        self.assertEqual(coordinator.tree_size(second), {'bytes': 0, 'files': 0})
        self.assertEqual(coordinator.own_store_environment(second),
                         {'SELKA_COMPILER_SHARED_CACHE': str(second / 'compiler'),
                          'SELKA_TEST_SHARED_CACHE': str(second / 'tests')})

    def test_a_cached_or_failing_forced_run_fails_with_its_own_status(self):
        for run in (self.run_suite(cached=1), self.run_suite(failed=1, status=1)):
            self.write_report()
            self.assertEqual(self.integrate(run=run), coordinator.INTEGRATION_FORCED_STATUS)
            self.assertFalse(coordinator.read_record(self.cache / 'last-run.json')['success'])
            self.assertIn('the forced fact/leak run failed (tests/lang, tests/ported)', self.record()['summary'])

    def test_the_per_user_log_not_empty_and_own_stores_clean_is_a_pass(self):
        self.log(2)
        before = coordinator.mismatch_counts(self.env)
        self.write_report()
        grows = self.run_suite()

        def run(argv, **options):
            self.log(5)  # another process of the user's logs three more lines during the request
            return grows(argv, **options)
        self.assertEqual(self.integrate(before=before, run=run), 0)
        log = str(self.store / 'compiler-artifacts-v2' / 'mismatches.log')
        self.assertEqual(self.record()['per_user_mismatches'], {log: {'lines': 5, 'during_request': 3, 'since_last_request': None}})
        self.assertTrue(self.record()['shared_mismatches']['passed'])
        self.assertIn('verification: integration PASS (status 0); per-user mismatch logs (a record, not the verdict): '
                      'compiler-artifacts-v2 5 lines (+3 during the request)', self.out)
        self.log(9)
        self.assertEqual(self.integrate(before=coordinator.mismatch_counts(self.env)), 0)
        self.assertEqual(self.record()['per_user_mismatches'][log]['since_last_request'], 4)

    def test_one_mismatch_in_the_request_s_own_store_fails_names_it_and_keeps_the_stores(self):
        self.write_report()
        own = coordinator.own_stores(self.cache)
        line = 'mismatch program %064x existing=%064x attempted=%064x' % (7, 8, 9)
        self.assertEqual(self.integrate(own=own, run=self.run_suite(own_mismatch=line)), coordinator.INTEGRATION_MISMATCH_STATUS)
        log = str(own / 'compiler' / 'compiler-artifacts-v2' / 'mismatches.log')
        record = self.record()
        self.assertEqual(record['shared_mismatches']['nonzero'], {log: 1})
        self.assertEqual(record['own_mismatch_lines'], {log: [line]})
        self.assertEqual((record['own_stores']['root'], record['own_stores']['kept']), (str(own), True))
        self.assertTrue(Path(log).is_file(), 'a failing request keeps its own stores to read')
        self.assertIn('FAIL (status 5): the request\'s own stores logged 1 mismatch lines (compiler-artifacts-v2: ' + line, record['summary'])
        self.assertFalse(coordinator.read_record(self.cache / 'last-run.json')['success'])

    def test_the_two_run_step_failing_is_its_own_status_and_names_the_test(self):
        self.write_report()
        problem = 'test-lang-rerun: tests/lang: lib_test::test_page changed its verdict: passed then unsupported (E_CORE)'
        run = self.run_suite(rerun=(1, 'test-lang-rerun: tests/lang: 1 problems\ntest-lang-rerun: tests/ported: ok\n',
                                    problem + '\nerror: the following command exited with code 1\n'))
        self.assertEqual(self.integrate(run=run), coordinator.INTEGRATION_RERUN_STATUS)
        rerun = self.record()['two_run_step']
        self.assertEqual(rerun['argv'], ['build', 'test-lang-rerun'])
        self.assertEqual(rerun['suites'], {'tests/lang': '1 problems', 'tests/ported': 'ok'})
        self.assertEqual(rerun['problems'], ['tests/lang: lib_test::test_page changed its verdict: passed then unsupported (E_CORE)'])
        self.assertIn('FAIL (status 8): the two-run test step failed: tests/lang: lib_test::test_page changed its verdict',
                      self.record()['summary'])
        broken = self.run_suite(rerun=(2, '', 'error: unable to compile build.zig\n'))
        self.assertEqual(self.integrate(run=broken), coordinator.INTEGRATION_RERUN_STATUS)
        self.assertEqual(self.record()['two_run_step']['problems'],
                         ['`zig build test-lang-rerun` exited 2: error: unable to compile build.zig'])

    def test_the_statuses_name_the_step_that_failed(self):
        clean, dirty = {'passed': True}, {'passed': False}
        good, bad = {'passed': True}, {'passed': False}
        self.assertEqual(coordinator.integration_status(0, good, clean, good), 0)
        self.assertEqual(coordinator.integration_status(0, good, dirty, good), 5)
        self.assertEqual(coordinator.integration_status(1, None, dirty, None), 5, 'a mismatch outranks a failing request')
        self.assertEqual(coordinator.integration_status(1, None, clean, None), 1)
        self.assertEqual(coordinator.integration_status(6, None, clean, None), 6)
        self.assertEqual(coordinator.integration_status(0, bad, clean, bad), 7)
        self.assertEqual(coordinator.integration_status(0, good, clean, bad), 8)
        self.assertEqual(coordinator.integration_status(0, good, clean, None), 0, 'no Zig given: no two-run step')
        self.assertEqual(len({coordinator.INTEGRATION_MISMATCH_STATUS, coordinator.INTEGRATION_FORCED_STATUS,
                              coordinator.INTEGRATION_RERUN_STATUS, coordinator.STAGE_STORE_STATUS, 1, 2, coordinator.RETRY}), 7)

    def test_a_pre_existing_mismatch_fails_the_verdict_and_unused_stores_are_ignored(self):
        self.log(2)
        before = coordinator.mismatch_counts(self.env)
        verdict = coordinator.mismatch_verdict(before, coordinator.mismatch_counts(self.env))
        self.assertEqual((verdict['grew'], verdict['passed']), ({}, False))
        self.assertEqual(coordinator.mismatch_counts({'SELKA_COMPILER_SHARED_CACHE': ''}), {})
        self.assertEqual(coordinator.mismatch_verdict({}, {})['passed'], True)

    def test_the_previous_record_s_per_user_counts(self):
        self.assertIsNone(coordinator.previous_per_user_counts(None))
        self.assertEqual(coordinator.previous_per_user_counts({'shared_mismatches': {'logs': {'/a': 3}}}), {'/a': 3},
                         'a record from before D-NIGHTLY-1 counted the per-user logs')
        self.assertEqual(coordinator.previous_per_user_counts(
            {'per_user_mismatches': {'/a': {'lines': 4}}, 'own_stores': {}, 'shared_mismatches': {'logs': {'/own': 1}}}), {'/a': 4})
        self.assertEqual(coordinator.per_user_mismatch_report({'/a': 1}, {'/a': 5}, {'/a': 2}),
                         {'/a': {'lines': 5, 'during_request': 4, 'since_last_request': 3}})

    def test_store_roots_follow_the_compiler_resolution(self):
        home = {'HOME': '/home/agent'}
        self.assertEqual(coordinator.native_store_roots(home, False), [])
        self.assertEqual(coordinator.native_store_roots(home, True),
                         [Path('/home/agent/.cache/selka/compiler-artifacts'), Path('/home/agent/.cache/selka/native-tests')])
        self.assertEqual(coordinator.native_store_roots(dict(home, XDG_CACHE_HOME='/x', SELKA_TEST_SHARED_CACHE=''), True),
                         [Path('/x/selka/compiler-artifacts')])
        self.assertEqual(coordinator.native_store_roots({'SELKA_COMPILER_SHARED_CACHE': '/s'}, False), [Path('/s')])
        self.assertIs(coordinator.native_default_sharing(REPOSITORY), True)

    def test_a_failed_request_skips_the_forced_run_and_the_two_run_step_but_keeps_its_status(self):
        self.write_report()
        self.assertEqual((self.integrate(status=1), self.calls), (1, []))
        self.assertIn('FAIL (status 1): the complete request failed with status 1', self.record()['summary'])

    def test_a_failed_request_names_its_failed_action_and_first_tests_and_what_the_rerun_said(self):
        # The nightly's line said only "the complete request failed with status 1" on 15 November; the reader had to open
        # the log to learn which action and which tests, and why they were not rerun.
        tests = [{'test_id': 'dev_loop_test.WatchLoop.test_a', 'state': 'failed'},
                 {'test_id': 'build_slot_test.Admission.test_b', 'state': 'timed_out'},
                 {'test_id': 'dev_loop_test.WatchLoop.test_c', 'state': 'failed'}]
        coordinator.atomic_record(self.cache / 'last-run.json', {
            'version': 1, 'success': False, 'status': 1, 'action_metadata': self.METADATA,
            'actions': [{'id': 'verification_cache', 'state': 'execute', 'test_telemetry': [{'tests': tests}]}],
            'flaky': {'passed': False, 'rerun': False, 'reason': 'a process outlived its action (leftover pid=7)', 'tests': []}})
        self.assertEqual(self.integrate(status=1), 1)
        summary = self.record()['summary']
        self.assertIn('the complete request failed with status 1 (verification_cache: dev_loop_test.WatchLoop.test_a; '
                      'verification_cache: build_slot_test.Admission.test_b; 1 more)', summary)
        self.assertIn('no flaky rerun: a process outlived its action (leftover pid=7)', summary)
        self.assertEqual(self.record()['request_failures'][0], ['verification_cache', 'dev_loop_test.WatchLoop.test_a', 'failed'])

    def test_main_runs_the_request_against_its_own_stores_and_restores_the_environment(self):
        root = self.root / 'checkout'
        root.mkdir()
        seen = {}

        def execute(*_arguments, **_options):
            seen['execute'] = {name: os.environ.get(name) for name in coordinator.NATIVE_SHARED_VARIABLES}
            return 0

        def integrate(root_, cache, status, before, environment, **options):
            seen['integrate'] = (environment.get('SELKA_COMPILER_SHARED_CACHE'), options['own'], options['zig'])
            return 0
        with patch.dict(os.environ, self.env), patch.object(coordinator, 'ROOT', root), \
                patch.object(coordinator, 'bound_caches'), patch.object(coordinator, 'stage_store_root', return_value=None), \
                patch.object(coordinator, 'execute_with_restarts', side_effect=execute), \
                patch.object(coordinator, 'integrate', side_effect=integrate):
            self.assertEqual(coordinator.main(['--zig', sys.executable, '--integration']), 0)
            self.assertEqual(os.environ['SELKA_COMPILER_SHARED_CACHE'], str(self.store))
            self.assertEqual(os.environ['SELKA_TEST_SHARED_CACHE'], '')
        own = seen['integrate'][1]
        self.assertTrue(own.is_relative_to(root / coordinator.CACHE_DIRECTORY / 'integration'))
        self.assertEqual(seen['execute'], {'SELKA_COMPILER_SHARED_CACHE': str(own / 'compiler'),
                                           'SELKA_TEST_SHARED_CACHE': str(own / 'tests')})
        self.assertEqual(seen['integrate'][0], str(self.store), 'the per-user counts read the caller\'s stores')
        self.assertEqual(seen['integrate'][2], Path(shutil.which(sys.executable)).absolute())

    def test_integration_rejects_other_profiles_and_timing_windows(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(coordinator.main(['--integration', '--profile', 'quick']), 2)
            self.assertEqual(coordinator.main(['--integration', '--timing-window-seconds', '10']), 2)


class StageStoreGuard(unittest.TestCase):
    """The per-user stage store belongs to the user's own builds: a gate's workers name none, and a gate that changed it fails."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='stage-guard-', dir=REPOSITORY / '.tmp')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.store = self.root / 'xdg' / 'selka' / 'stage-artifacts'
        (self.store / 'stage-artifacts-v1' / 'roots').mkdir(parents=True)
        (self.store / 'stage-artifacts-v1' / 'one.pack').write_bytes(b'pack')
        self.cache = self.root / 'cache'
        self.cache.mkdir()
        self.tree = self.root / 'tree'

    def live_root(self, name, work):
        data = coordinator.LIVE_ROOT_MAGIC + len(work).to_bytes(4, 'little') + work.encode() + (0).to_bytes(8, 'little')
        (self.store / 'stage-artifacts-v1' / 'roots' / (name + '.live')).write_bytes(data)

    def test_workers_name_no_stage_store_unless_the_caller_does(self):
        base = {'PATH': os.environ['PATH']}
        self.assertEqual(coordinator.normalized_environment(self.root, base)[coordinator.STAGE_VARIABLE], '')
        named = coordinator.normalized_environment(self.root, dict(base, SELKA_STAGE_SHARED_CACHE='/stores/stages'))
        self.assertEqual(named[coordinator.STAGE_VARIABLE], '/stores/stages')
        disabled = coordinator.normalized_environment(self.root, dict(base, SELKA_STAGE_SHARED_CACHE=''))
        self.assertEqual(disabled[coordinator.STAGE_VARIABLE], '')

    def test_the_guarded_store_is_the_compilers_default_only_while_the_variable_is_unset(self):
        self.assertEqual(coordinator.stage_store_root({'HOME': '/home/agent'}), Path('/home/agent/.cache/selka/stage-artifacts'))
        self.assertEqual(coordinator.stage_store_root({'HOME': '/home/agent', 'XDG_CACHE_HOME': '/x'}), Path('/x/selka/stage-artifacts'))
        self.assertEqual(coordinator.stage_store_root({'HOME': '/home/agent', 'XDG_CACHE_HOME': 'relative'}),
                         Path('/home/agent/.cache/selka/stage-artifacts'))
        self.assertIsNone(coordinator.stage_store_root({'HOME': '/home/agent', 'SELKA_STAGE_SHARED_CACHE': ''}))
        self.assertIsNone(coordinator.stage_store_root({'HOME': '/home/agent', 'SELKA_STAGE_SHARED_CACHE': '/s'}))
        self.assertIsNone(coordinator.stage_store_root({}))

    def test_an_untouched_store_passes_and_keeps_the_requests_status(self):
        before = coordinator.stage_store_snapshot(self.store)
        self.assertEqual((before['fingerprint']['exists'], before['fingerprint']['files']), (True, 1))
        self.assertEqual(coordinator.stage_store_guard([self.tree], self.store, before, 0, self.cache), 0)
        self.assertEqual(coordinator.stage_store_guard([self.tree], self.store, before, 1, self.cache), 1)
        self.assertEqual(coordinator.stage_store_guard([self.tree], None, None, 0, self.cache), 0)

    def test_a_concurrent_write_by_another_process_during_a_green_request_stays_green(self):
        before = coordinator.stage_store_snapshot(self.store)
        # Another build of the user's, in another checkout, publishes while the request runs: a pack, a rewritten root, a new root.
        (self.store / 'stage-artifacts-v1' / 'two.pack').write_bytes(b'pack')
        self.live_root('a', str(self.root / 'elsewhere' / 'tree' / '.selka-cache'))
        self.live_root('b', str(self.root / 'tree-but-not-quite'))
        coordinator.atomic_record(self.cache / 'last-run.json', {'version': 1, 'success': True, 'status': 0})
        errors = io.StringIO()
        with contextlib.redirect_stderr(errors):
            status = coordinator.stage_store_guard([self.tree], self.store, before, 0, self.cache)
        self.assertEqual(status, 0)
        self.assertIn('another process of yours wrote it', errors.getvalue())
        self.assertTrue(coordinator.read_record(self.cache / 'last-run.json')['success'])

    def test_a_root_of_this_checkout_written_during_a_green_request_fails_it(self):
        self.live_root('old', str(self.tree / 'before'))
        before = coordinator.stage_store_snapshot(self.store)
        (self.store / 'stage-artifacts-v1' / 'two.pack').write_bytes(b'pack')
        self.live_root('a', str(self.tree / '.selka-cache' / 'core-tests' / 'x'))
        self.live_root('b', str(self.root / 'elsewhere'))
        coordinator.atomic_record(self.cache / 'last-run.json', {'version': 1, 'success': True, 'status': 0})
        errors = io.StringIO()
        with contextlib.redirect_stderr(errors):
            status = coordinator.stage_store_guard([self.tree], self.store, before, 0, self.cache)
        self.assertEqual(status, coordinator.STAGE_STORE_STATUS)
        report = coordinator.read_record(self.cache / 'last-run.json')
        self.assertFalse(report['success'])
        self.assertEqual(report['status'], coordinator.STAGE_STORE_STATUS)
        self.assertEqual(report['stage_store_guard']['checkout_writers'], [str(self.tree / '.selka-cache' / 'core-tests' / 'x')])
        self.assertIn('a test reached the per-user stage store', errors.getvalue())
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(coordinator.stage_store_guard([self.tree], self.store, before, 1, self.cache), 1)

    def test_a_root_the_request_rewrote_counts_but_one_it_found_does_not(self):
        self.live_root('found', str(self.tree / 'found'))
        before = coordinator.stage_store_snapshot(self.store)
        self.assertEqual(coordinator.stage_store_writers(self.store, before['roots'], [self.tree]), [])
        os.utime(self.store / 'stage-artifacts-v1' / 'roots' / 'found.live', ns=(1, before['roots']['found.live'] + 1_000_000))
        self.assertEqual(coordinator.stage_store_writers(self.store, before['roots'], [self.tree]), [str(self.tree / 'found')])

    def test_a_store_that_appears_during_the_request_is_a_change(self):
        missing = coordinator.stage_store_fingerprint(self.root / 'absent')
        self.assertEqual((missing['exists'], missing['files']), (False, 0))
        verdict = coordinator.stage_store_verdict(missing, coordinator.stage_store_fingerprint(self.store), [])
        self.assertTrue(verdict['passed'])
        self.assertIn('exists', verdict['changed'])
        self.assertEqual(coordinator.stage_store_verdict(missing, missing, [])['changed'], {})
        self.assertFalse(coordinator.stage_store_verdict(missing, missing, ['/w'])['passed'])


class OwnStoresGuard(unittest.TestCase):
    """GATE3: a gate's workers run against compiler and test stores of the request's own (the default of `--own-stores`), a
    caller's named store stays the caller's, a mismatch in the own stores fails the request with status 5 and a build that
    opened the user's default store instead fails it with status 6. Beside `StageStoreGuard`, which holds the same rule for
    the stage store."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='own-stores-', dir=REPOSITORY / '.tmp')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.cache = self.root / 'cache'
        self.cache.mkdir()
        self.home = self.root / 'home'
        self.user = self.home / '.cache' / 'selka'
        self.children = []
        self.addCleanup(self.stop_children)

    def stop_children(self):
        for child in self.children:
            child.kill()
            child.wait()
            if child.stdout is not None:
                child.stdout.close()

    def user_store(self, leaf, namespace):
        directory = self.user / leaf / namespace
        directory.mkdir(parents=True, exist_ok=True)
        (directory / coordinator.LEASE_FILE).write_bytes(b'')
        return directory

    def holder(self, lease):
        """A process that holds a shared flock on LEASE until it is killed, as a build holds its store's lease."""
        code = ('import fcntl,sys,time\nf=open(sys.argv[1],"rb")\nfcntl.flock(f,fcntl.LOCK_SH)\nprint("held",flush=True)\n'
                'time.sleep(60)\n')
        child = subprocess.Popen([sys.executable, '-c', code, str(lease)], stdout=subprocess.PIPE, text=True)
        self.children.append(child)
        self.assertEqual(child.stdout.readline().strip(), 'held')
        return child

    def plan(self, mode='fresh', caller=None):
        caller = {'HOME': str(self.home)} if caller is None else caller
        return coordinator.prepare_gate_stores(self.cache, mode, caller)

    def last_run(self):
        coordinator.atomic_record(self.cache / 'last-run.json', {'version': 1, 'success': True, 'status': 0})

    def test_workers_get_own_stores_unless_the_caller_named_one(self):
        base = coordinator.own_stores(self.cache, coordinator.GATE_STORES_DIRECTORY)
        self.assertTrue(base.is_relative_to(self.cache / 'gate-stores'))
        self.assertEqual(sorted(path.name for path in base.iterdir()), ['compiler', 'tests'])
        unnamed = coordinator.request_store_environment(base, {'PATH': '/bin'})
        self.assertEqual(unnamed, {'SELKA_COMPILER_SHARED_CACHE': str(base / 'compiler'),
                                   'SELKA_TEST_SHARED_CACHE': str(base / 'tests')})
        named = coordinator.request_store_environment(base, {'SELKA_COMPILER_SHARED_CACHE': '/mine', 'SELKA_TEST_SHARED_CACHE': ''})
        self.assertEqual(named, {}, 'a store the caller named, an empty (disabled) one too, stays the caller\'s')
        half = coordinator.request_store_environment(base, {'SELKA_TEST_SHARED_CACHE': ''})
        self.assertEqual(half, {'SELKA_COMPILER_SHARED_CACHE': str(base / 'compiler')})
        # What a worker sees: the projection keeps both (placement variables), so a gate's child names the own stores.
        with patch.dict(os.environ, unnamed):
            worker = coordinator.normalized_environment(self.root, dict(os.environ))
        self.assertEqual((worker['SELKA_COMPILER_SHARED_CACHE'], worker['SELKA_TEST_SHARED_CACHE']),
                         (str(base / 'compiler'), str(base / 'tests')))
        self.assertEqual(worker[coordinator.STAGE_VARIABLE], '', 'the stage store is still the empty name')

    def test_the_own_stores_are_made_per_request_and_an_earlier_kept_one_is_removed(self):
        first = self.plan('fresh')['base']
        (first / 'compiler' / 'record').write_text('x')
        second = self.plan('fresh')['base']
        self.assertFalse(first.exists())
        self.assertEqual([path.name for path in (self.cache / 'gate-stores').iterdir()], [second.name])
        self.assertIsNone(self.plan('off'))

    def test_the_guarded_stores_are_the_default_ones_of_the_variables_the_caller_left_unset(self):
        self.assertEqual(coordinator.per_user_store_roots({'HOME': '/home/agent'}),
                         {'SELKA_COMPILER_SHARED_CACHE': Path('/home/agent/.cache/selka/compiler-artifacts'),
                          'SELKA_TEST_SHARED_CACHE': Path('/home/agent/.cache/selka/native-tests')})
        self.assertEqual(coordinator.per_user_store_roots({'HOME': '/h', 'XDG_CACHE_HOME': '/x', 'SELKA_COMPILER_SHARED_CACHE': ''}),
                         {'SELKA_TEST_SHARED_CACHE': Path('/x/selka/native-tests')})
        self.assertEqual(coordinator.per_user_store_roots({}), {})

    def test_the_lock_table_is_read_for_flock_posix_and_waiting_rows(self):
        text = ('1: POSIX  ADVISORY  WRITE 4004723 fc:00:136067 0 EOF\n'
                '2: FLOCK  ADVISORY  READ  90 103:05:108016622 0 EOF\n'
                '3: -> FLOCK  ADVISORY  WRITE 91 103:05:108016622 0 EOF\n'
                '4: POSIX  ADVISORY  READ 7 fc:00:163404 1073741826 1073742335\n'
                'garbage\n')
        self.assertEqual(coordinator.lock_holders(text), [(4004723, 136067), (90, 108016622), (91, 108016622), (7, 163404)])

    def test_a_process_descends_from_the_request_by_its_parent_chain(self):
        proc = self.root / 'proc'
        for pid, parent, name in ((10, 1, 'python3'), (11, 10, 'zig (build)'), (12, 11, 'selka'), (20, 1, 'other')):
            (proc / str(pid)).mkdir(parents=True)
            (proc / str(pid) / 'stat').write_text('%d (%s) S %d 0 0 0 0 0 0 0 0 0 0 0 0 0 20 0 1 0 %d 0\n' % (pid, name, parent, pid * 3))
        self.assertTrue(coordinator.descends_from(12, 10, str(proc)))
        self.assertTrue(coordinator.descends_from(10, 10, str(proc)))
        self.assertFalse(coordinator.descends_from(20, 10, str(proc)))
        self.assertFalse(coordinator.descends_from(99, 10, str(proc)), 'a process that is gone')
        self.assertEqual(coordinator.process_identity(11, str(proc)), (10, '33'), 'a name with a space and a parenthesis')

    def test_a_lease_held_by_this_requests_own_process_is_found_and_another_checkouts_is_not(self):
        lease = self.user_store('compiler-artifacts', 'compiler-artifacts-v2') / coordinator.LEASE_FILE
        roots = coordinator.per_user_store_roots({'HOME': str(self.home)})
        watch = coordinator.StoreLeaseWatch(roots, ancestor=os.getpid(), interval=0.05)
        self.assertEqual(watch.sample(), [], 'nothing holds the lease yet')
        child = self.holder(lease)
        found = watch.sample()
        self.assertEqual([(row['pid'], row['variable']) for row in found], [(child.pid, 'SELKA_COMPILER_SHARED_CACHE')])
        self.assertIn('-c', found[0]['command'])
        self.assertFalse(watch.verdict()['passed'])
        stranger = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
        self.children.append(stranger)
        other = coordinator.StoreLeaseWatch(roots, ancestor=stranger.pid)
        self.assertEqual(other.sample(), [], 'a holder that is not a descendant of the request is another checkout\'s')
        self.assertTrue(other.verdict()['passed'])

    def test_the_sampling_thread_finds_a_short_lived_holder_and_stops(self):
        lease = self.user_store('native-tests', 'native-tests-v3') / coordinator.LEASE_FILE
        roots = coordinator.per_user_store_roots({'HOME': str(self.home)})
        with coordinator.StoreLeaseWatch(roots, interval=0.02) as watch:
            self.holder(lease)
            deadline = time.monotonic() + 5
            while not watch.offenders and time.monotonic() < deadline:
                time.sleep(0.02)
        self.assertTrue(watch.stop.is_set())
        self.assertFalse(watch.thread.is_alive())
        self.assertEqual([row['variable'] for row in watch.verdict()['holders']], ['SELKA_TEST_SHARED_CACHE'])

    def finish(self, plan, watch, status=0):
        self.last_run()
        errors = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()) as out, contextlib.redirect_stderr(errors):
            result = coordinator.finish_gate_stores(self.cache, plan, watch, status)
        self.out, self.err = out.getvalue(), errors.getvalue()
        return result, coordinator.read_record(self.cache / 'last-run.json')

    def test_a_clean_request_passes_keeps_its_status_and_removes_a_fresh_store(self):
        plan = self.plan('fresh')
        (plan['base'] / 'compiler' / 'record').write_bytes(b'abc')
        result, report = self.finish(plan, coordinator.StoreLeaseWatch(plan['guarded']))
        self.assertEqual(result, 0)
        self.assertTrue(report['success'])
        self.assertEqual((report['own_stores']['bytes'], report['own_stores']['files'], report['own_stores']['kept']), (3, 1, False))
        self.assertFalse(plan['base'].exists(), 'a passing request removes its own stores')
        self.assertIn('verification: own stores: ', self.out)
        self.assertIn('removed; mismatch lines 0', self.out)

    def test_a_failing_request_with_clean_stores_removes_them_and_one_with_a_finding_keeps_them(self):
        plan = self.plan('fresh')
        (plan['base'] / 'compiler' / 'record').write_bytes(b'x' * 10)
        self.assertEqual(self.finish(plan, coordinator.StoreLeaseWatch({}), status=1)[0], 1)
        self.assertFalse(plan['base'].exists(), 'a failing test leaves no gigabyte behind')
        plan = self.plan('fresh')
        namespace = plan['base'] / 'compiler' / 'compiler-artifacts-v2'
        namespace.mkdir()
        (namespace / 'mismatches.log').write_text('mismatch program k existing=a attempted=b\n')
        self.assertEqual(self.finish(plan, coordinator.StoreLeaseWatch({}), status=1)[0], 1)
        self.assertTrue(plan['base'].exists(), 'a mismatch is kept for reading even when the request failed anyway')

    def test_a_component_builders_seed_compiler_that_opens_a_per_user_store_fails_the_request_like_any_build(self):
        # GATE3B: `selfhost/components.zig` passes the store locations to the seed compilers, so one that still holds a
        # per-user lease is a build of the request that opened the user's store: no directory is exempt any more.
        lease = self.user_store('compiler-artifacts', 'compiler-artifacts-v2') / coordinator.LEASE_FILE
        roots = coordinator.per_user_store_roots({'HOME': str(self.home)})
        seed = self.user / 'components' / 'seeds' / 'key' / 'source' / 'zig-out' / 'focus' / 'selka'
        seed.parent.mkdir(parents=True)
        seed.symlink_to(sys.executable)
        code = ('import fcntl,sys,time\nf=open(sys.argv[1],"rb")\nfcntl.flock(f,fcntl.LOCK_SH)\nprint("held",flush=True)\n'
                'time.sleep(60)\n')
        child = subprocess.Popen([str(seed), '-c', code, str(lease)], stdout=subprocess.PIPE, text=True)
        self.children.append(child)
        self.assertEqual(child.stdout.readline().strip(), 'held')
        plan = self.plan('fresh')
        self.assertNotIn('exempt', plan)
        watch = coordinator.StoreLeaseWatch(roots)
        watch.sample()
        verdict = watch.verdict()
        self.assertEqual((verdict['passed'], len(verdict['holders']), 'noted' in verdict), (False, 1, False))
        self.assertTrue(verdict['holders'][0]['command'].startswith(str(self.user / 'components')))
        result, report = self.finish(plan, watch)
        self.assertEqual(result, coordinator.STAGE_STORE_STATUS)
        self.assertEqual(len(report['own_stores']['lease_guard']['holders']), 1)
        self.assertNotIn('seed compiler', self.err)

    def test_a_mismatch_in_the_own_stores_fails_a_green_request_with_status_5_and_keeps_the_stores(self):
        plan = self.plan('fresh')
        namespace = plan['base'] / 'compiler' / 'compiler-artifacts-v2'
        namespace.mkdir()
        line = 'mismatch program %064x existing=%064x attempted=%064x' % (1, 2, 3)
        (namespace / 'mismatches.log').write_text(line + '\n')
        result, report = self.finish(plan, coordinator.StoreLeaseWatch({}))
        self.assertEqual(result, coordinator.INTEGRATION_MISMATCH_STATUS)
        self.assertEqual(coordinator.INTEGRATION_MISMATCH_STATUS, 5)
        self.assertFalse(report['success'])
        self.assertEqual(report['status'], 5)
        self.assertEqual(report['own_stores']['mismatch_lines'], {str(namespace / 'mismatches.log'): [line]})
        self.assertTrue(plan['base'].exists(), 'kept for reading until the next request removes it')
        self.assertIn("FAIL: the request's own store logged a determinism mismatch", self.err)
        self.assertIn(line, self.err)
        # The next request makes new stores and removes the kept ones.
        self.assertFalse(self.plan('fresh')['base'] == plan['base'] or plan['base'].exists())

    def test_a_build_that_opened_the_users_store_fails_a_green_request_with_status_6(self):
        lease = self.user_store('compiler-artifacts', 'compiler-artifacts-v2') / coordinator.LEASE_FILE
        plan = self.plan('fresh')
        watch = coordinator.StoreLeaseWatch(plan['guarded'], interval=0.05)
        self.holder(lease)
        watch.sample()
        result, report = self.finish(plan, watch)
        self.assertEqual(result, coordinator.STAGE_STORE_STATUS)
        self.assertFalse(report['success'])
        self.assertEqual(report['status'], 6)
        self.assertEqual([row['variable'] for row in report['own_stores']['lease_guard']['holders']], ['SELKA_COMPILER_SHARED_CACHE'])
        self.assertIn('a build of this request opened the per-user store', self.err)
        self.assertTrue(plan['base'].exists())

    def test_a_mismatch_outranks_a_lease_and_a_failing_request_keeps_its_status(self):
        lease = self.user_store('compiler-artifacts', 'compiler-artifacts-v2') / coordinator.LEASE_FILE
        plan = self.plan('fresh')
        namespace = plan['base'] / 'tests' / 'native-tests-v3'
        namespace.mkdir()
        (namespace / 'mismatches.log').write_text('mismatch engine k existing=a attempted=b\n')
        watch = coordinator.StoreLeaseWatch(plan['guarded'])
        self.holder(lease)
        watch.sample()
        self.assertEqual(self.finish(plan, watch)[0], 5)
        self.assertEqual(self.finish(plan, watch, status=1)[0], 1)
        self.assertIn('NOTE', self.err, 'a request that failed already prints the findings as notes')

    def main_run(self, arguments, environment=None):
        """What the request's workers see of the three store variables when `main` runs ARGUMENTS in a checkout of its own
        under a caller whose environment is ENVIRONMENT, and the directory `gate-stores` holds afterwards."""
        checkout = self.root / 'checkout'
        checkout.mkdir(exist_ok=True)
        seen = {}

        def execute(*_arguments, **_options):
            seen['execute'] = {name: os.environ.get(name) for name in coordinator.NATIVE_SHARED_VARIABLES}
            seen['during'] = sorted((checkout / coordinator.CACHE_DIRECTORY / 'gate-stores').glob('stores-*'))
            return 0
        kept = {name: value for name, value in os.environ.items() if name not in coordinator.NATIVE_SHARED_VARIABLES}
        with patch.dict(os.environ, dict(kept, **(environment or {})), clear=True), patch.object(coordinator, 'ROOT', checkout), \
                patch.object(coordinator, 'bound_caches'), patch.object(coordinator, 'stage_store_root', return_value=None), \
                patch.object(coordinator, 'execute_with_restarts', side_effect=execute), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(coordinator.main(['--zig', sys.executable] + arguments), 0)
            seen['after'] = {name: os.environ.get(name) for name in coordinator.NATIVE_SHARED_VARIABLES}
        seen['left'] = sorted((checkout / coordinator.CACHE_DIRECTORY / 'gate-stores').glob('stores-*'))
        return seen

    def test_main_runs_the_request_against_the_gates_own_stores_by_default_and_restores_the_environment(self):
        seen = self.main_run([])
        gate = self.root / 'checkout' / coordinator.CACHE_DIRECTORY / 'gate-stores'
        self.assertEqual(len(seen['during']), 1, 'one set of stores, made for the request')
        base = seen['during'][0]
        self.assertTrue(base.is_relative_to(gate))
        self.assertEqual(seen['execute'], {'SELKA_COMPILER_SHARED_CACHE': str(base / 'compiler'),
                                           'SELKA_TEST_SHARED_CACHE': str(base / 'tests')})
        self.assertEqual(seen['after'], {name: None for name in coordinator.NATIVE_SHARED_VARIABLES}, 'the caller\'s environment is back')
        self.assertEqual(seen['left'], [], 'removed after a pass')
        self.assertEqual(self.main_run(['--own-stores', 'fresh'])['left'], [])

    def test_a_store_the_caller_names_stays_the_callers_and_off_names_none(self):
        named = {'SELKA_COMPILER_SHARED_CACHE': '/the/callers', 'SELKA_TEST_SHARED_CACHE': ''}
        seen = self.main_run([], named)
        self.assertEqual(seen['execute'], named, 'a named store, an empty (disabled) one too, stays the caller\'s')
        half = self.main_run([], {'SELKA_COMPILER_SHARED_CACHE': '/the/callers'})
        self.assertEqual(half['execute']['SELKA_COMPILER_SHARED_CACHE'], '/the/callers')
        self.assertEqual(Path(half['execute']['SELKA_TEST_SHARED_CACHE']).name, 'tests', 'the unnamed one is the request\'s own')
        off = self.main_run(['--own-stores', 'off'])
        self.assertEqual(off['execute'], {name: None for name in coordinator.NATIVE_SHARED_VARIABLES})
        self.assertEqual(off['during'], [])

    def test_a_dry_run_makes_no_gate_stores(self):
        self.assertEqual(self.main_run(['--dry-run'])['during'], [])


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


class AdmittedCpuBudget(unittest.TestCase):
    def test_admitted_child_clamps_to_its_actual_affinity(self):
        available = sorted(os.sched_getaffinity(0))
        for count in sorted({1, min(2, len(available)), min(4, len(available))}):
            with self.subTest(cpus=count):
                code = (
                    'import json, os, sys; '
                    'import verify_cache as coordinator; '
                    f'os.sched_setaffinity(0, {available[:count]!r}); '
                    'print(json.dumps([coordinator.admitted_build_command(argv) for argv in '
                    '[["zig", "build", "-j999"], ["zig", "build", "-j1"], '
                    '["zig", "build"], ["python", "-c", "pass"]]]))')
                result = subprocess.run([sys.executable, '-c', code], cwd=REPOSITORY / 'scripts',
                                        text=True, capture_output=True, check=True)
                maximum = [] if count == 1 else [f'-j{count - 1}']
                minimum = [] if count == 1 else ['-j1']
                self.assertEqual(json.loads(result.stdout), [
                    ['zig', 'build', *maximum], ['zig', 'build', *minimum],
                    ['zig', 'build', *maximum], ['python', '-c', 'pass']])
        with patch.object(os, 'sched_getaffinity', return_value=set()):
            self.assertEqual(coordinator.admitted_build_command(['zig', 'build', '-j9']),
                             ['zig', 'build'])

    def test_nested_output_remains_in_report_when_sidecar_is_unwritable(self):
        with tempfile.TemporaryDirectory(dir=REPOSITORY / '.tmp') as scratch:
            cache = Path(scratch) / 'file'
            cache.write_text('cannot create a directory here')
            output = coordinator.subscription_diagnostics(cache, 'bundle', {
                'stdout': 'first' + 'x' * 20000 + 'last', 'stderr': 'child error'})
            self.assertFalse(output['stdout']['capture_available'])
            self.assertTrue(output['stdout']['tail_truncated'])
            self.assertTrue(output['stdout']['tail'].endswith('last'))
            self.assertEqual(output['stderr']['tail'], 'child error')


class BuildToolIdentity(unittest.TestCase):
    """The build runner and the tools it compiles for the graph (`build-env`,
    the build identity) are prepared infrastructure, not actions, so no action
    key holds their bytes; the coordinator's configuration identity must cover
    every file `build.zig` compiles from, transitively, instead."""

    # Package imports `build.zig` may name: the toolchain's own (it has no
    # `build.zig.zon` dependency since Guardian was turned off, GH-2).
    PACKAGES = {'std', 'builtin'}

    @staticmethod
    def closure(start):
        pending, files, packages = [start], set(), set()
        while pending:
            path = pending.pop()
            if path in files:
                continue
            files.add(path)
            text = (REPOSITORY / path).read_text()
            for name in re.findall(r'@(?:import|embedFile)\(\s*"([^"]+)"\s*\)', text):
                if name.endswith(('.zig', '.zon')) or '/' in name or name.startswith('.'):
                    pending.append(os.path.normpath(os.path.join(os.path.dirname(path), name)))
                else:
                    packages.add((path, name))
        return files, packages

    def test_build_runner_import_closure_is_in_every_action_configuration(self):
        recipes = coordinator.CONFIG_INPUTS + coordinator.COORDINATOR_INPUTS
        files, packages = self.closure('build.zig')
        for expected in ('build_env.zig', 'src/build_env_rules.zig', 'build_identity.zig',
                         'src/build_identity_rules.zig', 'src/semantic_cache_format.zig'):
            self.assertIn(expected, files)
        uncovered = sorted(path for path in files
                           if not any(coordinator.matches_recipe(path, recipe, REPOSITORY) for recipe in recipes))
        self.assertEqual(uncovered, [], 'build.zig compiles these files, which no action configuration identity '
                                        'covers; add them to CONFIG_INPUTS in scripts/verify_cache.py')
        unknown = sorted(entry for entry in packages if entry[1] not in self.PACKAGES)
        self.assertEqual(unknown, [], 'unreviewed package imports in the build runner closure')

    def test_build_runner_closure_stays_out_of_the_compiler_sources(self):
        # Every file here re-keys every action when it changes. Pulling a
        # compiler module into build.zig would make each edit of its closure do so.
        files, _ = self.closure('build.zig')
        self.assertLess(len([path for path in files if path.startswith('src/')]), 12, sorted(files))

    def test_test_runner_sources_are_watched(self):
        # Every custom test root's producer recipe names tools/test_runner/ (`runner_sources` in
        # build_verification.zig). The first gate after Guardian was turned off failed in preparation
        # with "producer recipe of cli selects no watched input: tools/test_runner/".
        recipes = list(coordinator.CONFIG_INPUTS) + list(REAL_PREPARE_INPUTS)
        for path in ('tools/test_runner/test_runner.zig', 'tools/test_runner/test_timing.zig'):
            self.assertTrue((REPOSITORY / path).is_file(), path)
            self.assertTrue(any(coordinator.matches_recipe(path, recipe, REPOSITORY) for recipe in recipes), path)


class DeclarativeConsumers(unittest.TestCase):
    """The declarative list exclusion (F12) must hold on the real tree, and any
    change to how the build consumes `build_test_inputs.zig` must be reviewed."""

    def configuration(self):
        with Snapshot(REPOSITORY, coordinator.CONFIG_INPUTS) as configuration:
            return copy.deepcopy(configuration.identity)

    def test_reviewed_consumer_sites_are_exactly_the_build_configuration_uses(self):
        found = coordinator.declarative_consumers(REPOSITORY, self.configuration())
        self.assertIsNotNone(found)
        reviewed = list(coordinator.DECLARATIVE_CONSUMERS)
        added = [site for site in found if site not in reviewed]
        removed = [site for site in reviewed if site not in found]
        self.assertEqual((added, removed), ([], []),
                         'review these build_test_inputs.zig consumer sites and update DECLARATIVE_CONSUMERS')
        self.assertEqual(sorted(found), sorted(reviewed))

    def test_exclusion_applies_to_the_real_configuration(self):
        configuration = self.configuration()
        lists = coordinator.declared_input_lists(REPOSITORY / coordinator.DECLARATIVE_INPUTS)
        self.assertIsNotNone(lists, 'build_test_inputs.zig is no longer data-only')
        plan = {'input_lists': [{'name': name, 'inputs': inputs} for name, inputs in lists.items()]}
        notes = {}
        narrowed = coordinator.action_configuration(configuration, plan, REPOSITORY, configuration, notes)
        self.assertEqual(notes, {'declarative_configuration': 'excluded'})
        self.assertNotIn(coordinator.DECLARATIVE_INPUTS, [item['path'] for item in narrowed['files']])
        self.assertEqual(len(narrowed['files']), len(configuration['files']) - 1)


class ActionRecipeSelection(unittest.TestCase):
    def setUp(self):
        base = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.root = base / 'repo'
        self.external = base / 'external' / 'tool'
        self.external.parent.mkdir()
        self.external.write_text('external')
        for name in ('src/a.zig', 'src/a.txt', 'src/nested/b.zig', 'src-other/a.zig',
                     'README', '../sibling/c.zig'):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name)
        self.snapshot = self.enterContext(Snapshot(
            self.root, ['src/', 'src-other/', 'README', '../sibling/'], [self.external]))

    def payload(self, recipes):
        return coordinator.action_payload({'id': 'selection', 'inputs': recipes},
                                          self.snapshot, {'compiler': 'unchanged'}, self.root)

    def test_recipe_boundaries_normalization_order_and_overlap(self):
        cases = (
            ([], []),
            (['src/'], ['src/a.txt', 'src/a.zig', 'src/nested/b.zig']),
            (['src/*.zig'], ['src/a.zig']),
            (['src/**/*.zig'], ['src/a.zig', 'src/nested/b.zig']),
            (['src/../README'], ['README']),
            ([str(self.root / 'src/a.zig')], ['src/a.zig']),
            (['../sibling/*.zig'], ['../sibling/c.zig']),
            ([str(self.external)], [str(self.external)]),
            (['src/', 'src/*.zig', 'src/a.zig'], ['src/a.txt', 'src/a.zig', 'src/nested/b.zig']),
        )
        for recipes, expected in cases:
            with self.subTest(recipes=recipes):
                payload = self.payload(recipes)
                self.assertEqual([item['path'] for item in payload['files']], expected)
                self.assertEqual(payload['common'], {'compiler': 'unchanged'})
                self.assertEqual(payload['contract']['inputs'], recipes)
                self.assertTrue(self.snapshot.unchanged())

    def test_recipe_compilation_is_bounded_and_closed_authority_still_refuses(self):
        recipes = ['src/', 'src/*.zig', '../sibling/']
        with patch.object(coordinator, 'recipe_predicate', wraps=coordinator.recipe_predicate) as compile_recipe:
            payload = self.payload(recipes)
        self.assertEqual(compile_recipe.call_count, len(recipes))
        self.assertEqual([call.args for call in compile_recipe.call_args_list],
                         [(recipe, self.root) for recipe in recipes])
        self.assertEqual(len(payload['files']), 4)
        payload['files'][0]['path'] = 'changed returned copy'
        self.assertNotIn('changed returned copy', [item['path'] for item in self.snapshot.identity['files']])
        self.snapshot.__exit__(None, None, None)
        with self.assertRaises(SnapshotError):
            self.payload(recipes)


class CoordinatorRelocation(unittest.TestCase):
    """F3: one commit checked out twice binds one coordinator implementation."""

    def test_two_copies_of_the_coordinator_bind_identical_loaded_code(self):
        scratch = REPOSITORY / '.tmp'
        scratch.mkdir(exist_ok=True)
        base = Path(self.enterContext(tempfile.TemporaryDirectory(prefix='relocation-', dir=scratch)))
        program = ('import json,verify_cache as c\n'
                   'print(json.dumps([[[name,d] for name,d,_ in c.implementation_code()],'
                   'c.code_identity.LOADED_CODE_SHA256,c.location_dependent_code()]))')
        results = []
        for copy_root in (base / 'one', base / 'a' / 'much' / 'longer' / 'two'):
            shutil.copytree(REPOSITORY / 'scripts', copy_root / 'scripts',
                            ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
            (copy_root / 'src').mkdir()
            shutil.copy2(REPOSITORY / 'src/environment_identity.zon', copy_root / 'src/environment_identity.zon')
            environment = dict(os.environ, PYTHONPATH=str(copy_root / 'scripts'),
                               PYTHONDONTWRITEBYTECODE='1', PYTHONPYCACHEPREFIX='/dev/null')
            process = subprocess.run([sys.executable, '-B', '-c', program], cwd=copy_root, env=environment,
                                     capture_output=True, text=True, timeout=60)
            self.assertEqual(process.returncode, 0, process.stderr)
            results.append(json.loads(process.stdout))
        self.assertEqual(results[0], results[1])
        self.assertEqual(results[0][2], [])
        implementations = results[0][0]
        self.assertEqual([name for name, _ in implementations], [
            'verify_cache', 'verification_measurement', 'build_admission',
            'verification_scheduler', 'verification_watch_pool',
            'verification_snapshot', 'fuzz_campaign_store',
            'verification_process', 'verification_producers', 'verification_warm',
            'verification_git_tree', 'verification_profiles', 'verification_qualification',
        ])
        for name, digest in implementations + [('verification_code_identity', results[0][1])]:
            with self.subTest(module=name):
                self.assertRegex(digest, r'\A[0-9a-f]{64}\Z')


if __name__ == '__main__':
    unittest.main()
