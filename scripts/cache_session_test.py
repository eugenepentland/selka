#!/usr/bin/env python3
"""Cheap persistent coordinator protocol and live-authority adversarial tests."""
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import cache_session
from verification_snapshot import RetainedSession, Snapshot


class CleanGuard:
    def check(self):
        pass


class CacheSession(unittest.TestCase):
    def setUp(self):
        scratch = cache_session.ROOT / '.tmp'
        scratch.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='cache-session-', dir=scratch)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.path = self.root / 'input'
        self.path.write_bytes(b'original')

    def run_requests(self, requests, dispatch, guard=None, session=None):
        output = io.StringIO()
        stream = io.BytesIO(b''.join(json.dumps(value).encode() + b'\n' for value in requests))
        with session or RetainedSession() as pool:
            code = cache_session.serve(stream, output, dispatch, pool, guard or CleanGuard())
        return code, [json.loads(line) for line in output.getvalue().splitlines()]

    def test_protocol_status_failure_recovery_and_control(self):
        calls = []
        def dispatch(args):
            calls.append(args)
            return 7 if args else 0
        code, rows = self.run_requests([
            {'id':'fail', 'command':'verify', 'args':['--force']},
            {'id':'pass', 'command':'fuzz'},
            {'id':'reset', 'command':'reset'},
            {'id':'stop', 'command':'stop'},
            {'id':'ignored', 'command':'perf'},
        ], dict.fromkeys(cache_session.COMMANDS, dispatch))
        self.assertEqual(code, 0)
        self.assertEqual([row['status'] for row in rows], [7, 0, 0, 0])
        self.assertEqual(calls, [['--force'], []])
        self.assertFalse(rows[0]['ok'])
        self.assertTrue(rows[1]['ok'])

    def test_sequential_actual_snapshots_edit_and_reset_work(self):
        owners = []
        def dispatch(args):
            if args:
                self.path.write_bytes(b'changed')
            with Snapshot(self.root, ['input']) as snapshot:
                owners.append(snapshot._lease[1])
                self.assertTrue(snapshot.unchanged())
            return 0
        code, rows = self.run_requests([
            {'id':1, 'command':'verify'}, {'id':2, 'command':'fuzz'},
            {'id':3, 'command':'perf', 'args':['edit']},
            {'id':4, 'command':'reset'}, {'id':5, 'command':'verify'},
        ], dict.fromkeys(cache_session.COMMANDS, dispatch))
        self.assertEqual(code, 0)
        self.assertEqual([row['snapshot_work']['files_hashed'] for row in rows], [1, 0, 1, 0, 1])
        self.assertEqual([row['snapshot_work']['snapshot_reuses'] for row in rows], [0, 1, 0, 0, 0])
        self.assertIs(owners[0], owners[1])
        self.assertTrue(all(owner._watcher is None for owner in owners))
        self.assertGreater(rows[1]['snapshot_work']['metadata_observations'], 0)

    def test_invalid_requests_and_private_abbreviations_recover(self):
        output = io.StringIO()
        values = [
            b'{bad}\n', b'{"id":1,"id":2,"command":"stop"}\n',
            json.dumps({'id':1, 'command':'arbitrary'}).encode() + b'\n',
            json.dumps({'id':2, 'command':'verify', 'args':['--worker=x']}).encode() + b'\n',
            json.dumps({'id':3, 'command':'fuzz', 'args':['--admitted']}).encode() + b'\n',
            json.dumps({'id':4, 'command':'perf', 'args':['--work']}).encode() + b'\n',
            json.dumps({'id':5, 'command':'verify', 'args':['--admit=true']}).encode() + b'\n',
            json.dumps({'id':6, 'command':'stop'}).encode() + b'\n',
        ]
        with RetainedSession() as session:
            code = cache_session.serve(io.BytesIO(b''.join(values)), output, {}, session, CleanGuard())
        rows = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(code, 0)
        self.assertEqual([row['status'] for row in rows], [2] * 7 + [0])
        self.assertTrue(all(not row['ok'] for row in rows[:-1]))

    def test_request_bounds_and_oversized_line_stops(self):
        self.assertRaises(ValueError, cache_session.request, json.dumps({'id':'x' * 257, 'command':'stop'}).encode())
        self.assertRaises(ValueError, cache_session.request, json.dumps({'id':1, 'command':'verify', 'args':['x'] * 257}).encode())
        self.assertRaises(ValueError, cache_session.request, json.dumps({'id':1, 'command':'verify', 'args':['x' * 4097]}).encode())
        self.assertRaises(ValueError, cache_session.request, json.dumps({'id':1, 'command':'reset', 'args':['x']}).encode())
        output = io.StringIO()
        with RetainedSession() as session:
            code = cache_session.serve(io.BytesIO(b'x' * (cache_session.MAX_LINE + 2) + b'\n'), output, {}, session, CleanGuard())
        self.assertEqual(code, 75)
        self.assertTrue(json.loads(output.getvalue())['restart_required'])

    def test_argument_systemexit_failure_and_exceptions_recover(self):
        def dispatch(args):
            if args == ['parse']:
                raise SystemExit(2)
            if args == ['exception']:
                raise ValueError('failed')
            return 0
        code, rows = self.run_requests([
            {'id':1, 'command':'verify', 'args':['parse']},
            {'id':2, 'command':'verify', 'args':['exception']},
            {'id':3, 'command':'verify'},
        ], {'verify':dispatch})
        self.assertEqual(code, 0)
        self.assertEqual([row['status'] for row in rows], [2, 2, 0])

    def test_invalid_dispatch_status_cannot_grant_success(self):
        code, rows = self.run_requests([{'id':1, 'command':'verify'}], {'verify':lambda _: True})
        self.assertEqual(code, 0)
        self.assertEqual(rows[0]['status'], 2)
        self.assertFalse(rows[0]['ok'])

    def test_cancellation_stops_and_owners_close(self):
        owners = []
        def dispatch(args):
            with Snapshot(self.root, ['input']) as snapshot:
                owners.append(snapshot._lease[1])
                raise KeyboardInterrupt
        code, rows = self.run_requests([
            {'id':1, 'command':'verify'}, {'id':2, 'command':'verify'},
        ], {'verify':dispatch})
        self.assertEqual(code, 130)
        self.assertEqual(len(rows), 1)
        self.assertIsNone(owners[0]._watcher)
        code, rows = self.run_requests([
            {'id':1, 'command':'verify'}, {'id':2, 'command':'verify'},
        ], {'verify':lambda _: 143})
        self.assertEqual(code, 143)
        self.assertEqual(len(rows), 1)

    def test_runtime_mutation_discards_success_and_stops(self):
        class Guard:
            dirty = False
            def check(self):
                if self.dirty:
                    raise cache_session.RestartRequired('runtime changed')
        guard = Guard()
        def dispatch(_args):
            guard.dirty = True
            return 0
        code, rows = self.run_requests([
            {'id':1, 'command':'verify'}, {'id':2, 'command':'verify'},
        ], {'verify':dispatch}, guard=guard)
        self.assertEqual(code, 75)
        self.assertEqual(len(rows), 1)
        self.assertFalse(rows[0]['ok'])
        self.assertTrue(rows[0]['restart_required'])

    def test_preloaded_coordinator_and_helper_are_rejected(self):
        with patch.dict(sys.modules, {'verify_cache': object()}):
            guard = cache_session.RuntimeGuard(self.root)
            self.assertRaises(cache_session.RestartRequired, guard.__enter__)
            self.assertIsNone(guard.snapshot)
        with patch.dict(sys.modules, {'juice_tool.common': object()}):
            self.assertRaises(cache_session.RestartRequired, cache_session.RuntimeGuard(self.root).__enter__)
        with patch.dict(sys.modules, {'fuzz_campaign_store': object()}):
            self.assertRaises(cache_session.RestartRequired, cache_session.RuntimeGuard(self.root).__enter__)
        with patch.dict(sys.modules, {'verification_process': object()}):
            self.assertRaises(cache_session.RestartRequired, cache_session.RuntimeGuard(self.root).__enter__)
        with patch.dict(sys.modules, {'verification_report': object()}):
            self.assertRaises(cache_session.RestartRequired, cache_session.RuntimeGuard(self.root).__enter__)
        with patch.dict(sys.modules, {'verification_budgets': object()}):
            self.assertRaises(cache_session.RestartRequired, cache_session.RuntimeGuard(self.root).__enter__)

    def test_real_runtime_guard_source_mutation_and_reset_independence(self):
        scripts = self.root / 'scripts'
        scripts.mkdir()
        implementation = scripts / 'helper.py'
        implementation.write_text('value = 1\n')
        with cache_session.RuntimeGuard(self.root) as guard, RetainedSession() as pool:
            pool.reset()
            guard.check()
            implementation.write_text('value = 2\n')
            self.assertRaises(cache_session.RestartRequired, guard.check)

    def test_runtime_guard_lost_watcher_requires_restart(self):
        (self.root / 'scripts').mkdir()
        with cache_session.RuntimeGuard(self.root) as guard:
            guard.snapshot._watcher.failure = 'injected event loss'
            self.assertRaises(cache_session.RestartRequired, guard.check)

    def test_mapping_identity_replacement_and_deleted_files_reject(self):
        metadata = self.path.stat()
        device = f'{os.major(metadata.st_dev):02x}:{os.minor(metadata.st_dev):02x}'
        mapping = f'1000-2000 r-xp 0000 {device} {metadata.st_ino} {self.path}\n'
        with patch('builtins.open', return_value=io.StringIO(mapping)):
            self.assertEqual(cache_session.RuntimeGuard._mapped_libraries(), {self.path})
        replaced = f'1000-2000 r-xp 0000 {device} {metadata.st_ino + 1} {self.path}\n'
        with patch('builtins.open', return_value=io.StringIO(replaced)):
            self.assertRaises(cache_session.RestartRequired, cache_session.RuntimeGuard._mapped_libraries)
        deleted = f'1000-2000 r-xp 0000 {device} {metadata.st_ino} {self.path} (deleted)\n'
        with patch('builtins.open', return_value=io.StringIO(deleted)):
            self.assertRaises(cache_session.RestartRequired, cache_session.RuntimeGuard._mapped_libraries)

    def test_post_import_library_guard_and_new_mapping_fail_closed(self):
        (self.root / 'scripts').mkdir()
        with cache_session.RuntimeGuard(self.root) as guard:
            libraries = guard._libraries | {self.path}
            with patch.object(guard, '_mapped_libraries', return_value=libraries):
                guard.seal_runtime()
                guard.check()
                self.assertIsNotNone(guard.library_snapshot)
                self.path.write_bytes(b'library changed')
                self.assertRaises(cache_session.RestartRequired, guard.check)
        with cache_session.RuntimeGuard(self.root) as guard:
            guard.seal_runtime()
            with patch.object(guard, '_mapped_libraries', return_value=guard._libraries | {self.path}):
                self.assertRaises(cache_session.RestartRequired, guard.check)

    def test_real_coordinator_help_has_json_only_stdout(self):
        requests = [{'id':command, 'command':command, 'args':['--help']} for command in cache_session.COMMANDS]
        requests.append({'id':'done', 'command':'stop'})
        result = subprocess.run([sys.executable, str(Path(cache_session.__file__).resolve())],
                                input=''.join(json.dumps(row) + '\n' for row in requests),
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(rows), 4)
        self.assertTrue(all(row['ok'] for row in rows))
        self.assertIn('usage:', result.stderr)

    def test_fd_subprocess_output_stays_out_of_protocol(self):
        script = """
import io, json, sys, subprocess
from cache_session import serve
from verification_snapshot import RetainedSession
class Guard:
    def check(self): pass
def run(args):
    print('python output')
    subprocess.run([sys.executable, '-c', "import os; os.write(1,b'child output\\\\n')"], check=True)
    return 0
with RetainedSession() as pool:
    serve(io.BytesIO(b'{"id":1,"command":"verify"}\\n'),sys.stdout,{'verify':run},pool,Guard())
"""
        result = subprocess.run([sys.executable, '-c', script], cwd=cache_session.ROOT / 'scripts',
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)['ok'])
        self.assertIn('python output', result.stderr)
        self.assertIn('child output', result.stderr)


if __name__ == '__main__':
    unittest.main()
