#!/usr/bin/env python3
"""Real session-separated descendants are reaped before admitted work ends."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import juice_worker

WORKER = Path(__file__).with_name('juice_worker.py')
SLEEPER = 'import time; time.sleep(60)'
IGNORE_TERM = 'import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(60)'


class Supervision(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='juice-worker-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.children = []
        self.owned_pidfds = {}
        self.addCleanup(self.cleanup_fixture)

    def cleanup_fixture(self):
        for process in self.children:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=10)
        # Anchored fixture descendants cannot accidentally signal a reused PID.
        for descriptor in self.owned_pidfds.values():
            try:
                signal.pidfd_send_signal(descriptor, signal.SIGKILL)
            except ProcessLookupError:
                pass
            finally:
                os.close(descriptor)

    def start(self, code, *args, startup_delay=False):
        command = [sys.executable, str(WORKER), sys.executable, '-c', code, *map(str, args)]
        if startup_delay:
            wrapper = (
                'import juice_worker,subprocess,time,sys; original=subprocess.Popen\n'
                'def delayed(*args,**kwargs):\n'
                ' p=original(*args,**kwargs); time.sleep(.2); return p\n'
                'juice_worker.subprocess.Popen=delayed\n'
                'sys.exit(juice_worker.run(sys.argv[1:]))\n')
            command = [sys.executable, '-c', wrapper, sys.executable, '-c', code, *map(str, args)]
        env = dict(os.environ, PYTHONPATH=str(WORKER.parent), PYTHONDONTWRITEBYTECODE='1',
                   PYTHONPYCACHEPREFIX='/dev/null')
        process = subprocess.Popen(command, env=env, start_new_session=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.children.append(process)
        return process

    def wait_json(self, path):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                values = json.loads(path.read_text())
                for pid in values.values():
                    if pid not in self.owned_pidfds:
                        try:
                            self.owned_pidfds[pid] = os.pidfd_open(pid, 0)
                        except ProcessLookupError:
                            pass
                return values
            except (FileNotFoundError, json.JSONDecodeError):
                time.sleep(.01)
        self.fail('native fixture did not become ready')

    def assert_reaped(self, pids):
        self.assertTrue(all(not Path(f'/proc/{pid}').exists() for pid in pids.values()), pids)

    def tree(self, path, *, ignore=False, exit_code=None):
        descendant = IGNORE_TERM if ignore else SLEEPER
        middle = (
            'import os,sys,json,subprocess,time,signal\n'
            + ('signal.signal(signal.SIGTERM,signal.SIG_IGN)\n' if ignore else '')
            + f'g=subprocess.Popen([sys.executable,"-c",{descendant!r}],start_new_session=True)\n'
            'open(sys.argv[1],"w").write(json.dumps({"middle":os.getpid(),"leaf":g.pid}))\n'
            'time.sleep(60)\n')
        code = (
            'import os,sys,json,subprocess,time,signal\n'
            + ('signal.signal(signal.SIGTERM,signal.SIG_IGN)\n' if ignore else '')
            + f'p=subprocess.Popen([sys.executable,"-c",{middle!r},sys.argv[1]],start_new_session=True)\n'
            'while not os.path.exists(sys.argv[1]): time.sleep(.01)\n'
            'row=json.load(open(sys.argv[1])); row["native"]=os.getpid()\n'
            'temporary=sys.argv[1]+".tmp"; open(temporary,"w").write(json.dumps(row)); os.replace(temporary,sys.argv[1])\n'
            + (f'sys.exit({exit_code})\n' if exit_code is not None else 'time.sleep(60)\n'))
        process = self.start(code, path)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            pids = self.wait_json(path)
            if 'native' in pids:
                return process, pids
            time.sleep(.01)
        self.fail('native fixture did not publish root PID')

    def test_native_exit_status_and_stdout_preserved(self):
        process = self.start('import sys; print("captured"); sys.exit(7)')
        stdout, stderr = process.communicate(timeout=7)
        self.assertEqual(process.returncode, 7, stderr)
        self.assertEqual(stdout, b'captured\n')

    def test_native_signal_exit_is_failure(self):
        process = self.start('import os,signal; os.kill(os.getpid(),signal.SIGTERM)')
        _, stderr = process.communicate(timeout=7)
        self.assertEqual(process.returncode, 143, stderr)

    def test_outer_group_cancel_reaps_separate_sessions_and_grandchildren(self):
        process, pids = self.tree(self.root / 'cancel.json')
        self.assertNotEqual(os.getpgid(pids['native']), process.pid)
        self.assertNotEqual(os.getpgid(pids['middle']), os.getpgid(pids['native']))
        os.killpg(process.pid, signal.SIGTERM)
        _, stderr = process.communicate(timeout=7)
        self.assertEqual(process.returncode, 143, stderr)
        self.assert_reaped(pids)

    def test_normal_native_completion_cleans_stragglers_and_preserves_status(self):
        process, pids = self.tree(self.root / 'complete.json', exit_code=0)
        _, stderr = process.communicate(timeout=7)
        self.assertEqual(process.returncode, 0, stderr)
        self.assert_reaped(pids)

    def test_ignoring_term_tree_is_killed_and_reaped_within_cleanup_budget(self):
        process, pids = self.tree(self.root / 'ignore.json', ignore=True)
        started = time.monotonic()
        os.killpg(process.pid, signal.SIGTERM)
        _, stderr = process.communicate(timeout=7)
        self.assertEqual(process.returncode, 143, stderr)
        self.assertLess(time.monotonic() - started, juice_worker.CLEANUP_SECONDS + 1)
        self.assert_reaped(pids)

    def test_cancel_during_spawn_startup_cleans_owned_native(self):
        path = self.root / 'startup.json'
        code = 'import os,sys,json,time; open(sys.argv[1],"w").write(json.dumps({"native":os.getpid()})); time.sleep(60)'
        process = self.start(code, path, startup_delay=True)
        pids = self.wait_json(path)
        os.killpg(process.pid, signal.SIGINT)
        _, stderr = process.communicate(timeout=7)
        self.assertEqual(process.returncode, 130, stderr)
        self.assert_reaped(pids)

    def test_cancel_before_startup_never_launches_command(self):
        marker = self.root / 'should-not-exist'
        code = ('import juice_worker,signal,sys; juice_worker._cancel_signal(signal.SIGTERM,None); '
                'sys.exit(juice_worker.run([sys.executable,"-c",'
                '"from pathlib import Path; Path(__import__(\'sys\').argv[1]).touch()",sys.argv[1]]))')
        process = subprocess.Popen([sys.executable, '-c', code, str(marker)],
                                   env=dict(os.environ, PYTHONPATH=str(WORKER.parent)),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.children.append(process)
        _, stderr = process.communicate(timeout=7)
        self.assertEqual(process.returncode, 143, stderr)
        self.assertFalse(marker.exists())

    def test_missing_command_and_usage_are_not_success(self):
        process = self.start('pass')
        _, stderr = process.communicate(timeout=7)
        self.assertEqual(process.returncode, 0, stderr)
        missing = subprocess.run([sys.executable, str(WORKER), str(self.root / 'absent')],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=7)
        self.assertEqual(missing.returncode, 125)
        usage = subprocess.run([sys.executable, str(WORKER)], stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, timeout=7)
        self.assertEqual(usage.returncode, 2)

    def test_continuous_zombie_reap_stream_yields_to_cleanup_deadline(self):
        with patch.object(juice_worker.os, 'waitpid', return_value=(123, 0)) as wait:
            with patch.object(juice_worker.time, 'monotonic', side_effect=[1.0, 1.1, 2.1]):
                juice_worker._reap(None, deadline=2.0)
        self.assertEqual(wait.call_count, 2)

    def test_dead_descendant_burst_and_live_straggler_are_all_reaped(self):
        path = self.root / 'burst.json'
        code = ('import os,sys,json,subprocess,time\n'
                'children=[subprocess.Popen([sys.executable,"-c","pass"],start_new_session=True) for _ in range(8)]\n'
                'live=subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"],start_new_session=True)\n'
                'row={str(i):p.pid for i,p in enumerate(children)}; row["live"]=live.pid; row["native"]=os.getpid()\n'
                'open(sys.argv[1],"w").write(json.dumps(row)); time.sleep(.1); sys.exit(7)\n')
        process = self.start(code, path)
        pids = self.wait_json(path)
        _, stderr = process.communicate(timeout=7)
        self.assertEqual(process.returncode, 7, stderr)
        self.assert_reaped(pids)

    def test_owned_pidfd_check_never_signals_unrelated_process(self):
        unrelated = subprocess.Popen([sys.executable, '-c', SLEEPER])
        self.children.append(unrelated)
        # This test process owns unrelated; a separate supervisor does not.
        code = ('import juice_worker,signal,sys; '
                'juice_worker._signal_owned(int(sys.argv[1]),signal.SIGKILL)')
        process = self.start(code, unrelated.pid)
        _, stderr = process.communicate(timeout=7)
        self.assertEqual(process.returncode, 0, stderr)
        self.assertIsNone(unrelated.poll())


if __name__ == '__main__':
    unittest.main()
