"""Exercise real namespace boundaries; unsupported isolation is a test failure."""
import json
from pathlib import Path
import sys
import subprocess
import os
import signal
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from experiments.application_comparison.isolation import Limits, run

PYTHON = ['/usr/bin/python3', '-I', '-S', '-c']


class IsolationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.work = self.root / 'work'
        self.work.mkdir()

    def execute(self, source, **options):
        result = run(self.work, [*PYTHON, source], **options)
        self.assertTrue(result['isolated'], result['stderr'].decode(errors='replace'))
        return result

    def test_filesystem_process_network_and_capabilities(self):
        secret = self.root / 'coordinator-answer'
        secret.write_text('not participant data')
        source = '''import json, os, pathlib, socket
p = pathlib.Path
status = p('/proc/self/status').read_text()
s = socket.socket(); s.settimeout(.1)
try:
    s.connect(('1.1.1.1', 443)); network = True
except OSError:
    network = False
p('/work/result').write_text('editable')
print(json.dumps({'secret': p(SECRET).exists(), 'host_home': p('/home/epentland').exists(),
 'local_software': p('/usr/local').exists(),
 'parent_root': p('/proc/1/root' + SECRET).exists(), 'network': network,
 'caps': [line for line in status.splitlines() if line.startswith(('CapEff:', 'CapBnd:', 'NoNewPrivs:'))]}))
'''.replace('SECRET', repr(str(secret)))
        result = self.execute(source)
        self.assertEqual(result['returncode'], 0, result['stderr'])
        data = json.loads(result['stdout'])
        self.assertFalse(data['secret'])
        self.assertFalse(data['host_home'])
        self.assertFalse(data['local_software'])
        self.assertNotIn('/usr', result['system_mounts'])
        self.assertIn('/usr/bin', result['system_mounts'])
        self.assertFalse(data['parent_root'])
        self.assertFalse(data['network'])
        self.assertEqual(data['caps'], ['CapEff:\t0000000000000000', 'CapBnd:\t0000000000000000', 'NoNewPrivs:\t1'])
        self.assertEqual((self.work / 'result').read_text(), 'editable')

    def test_tools_readonly_and_no_remount(self):
        tool = self.root / 'frozen'
        tool.write_text('pinned')
        result = self.execute('''import pathlib, subprocess
p = pathlib.Path('/tools/frozen')
assert p.read_text() == 'pinned'
try:
    p.write_text('changed')
except OSError:
    pass
else:
    raise AssertionError('tool writable')
r = subprocess.run(['/usr/bin/mount','-o','remount,rw','/tools/frozen'], capture_output=True)
assert r.returncode != 0
''', tools={'frozen': tool})
        self.assertEqual(result['returncode'], 0, result['stderr'])
        self.assertEqual(tool.read_text(), 'pinned')

    def test_output_budget_and_input(self):
        result = self.execute('import sys; print(sys.stdin.buffer.read().hex())', input_bytes=b'\x00abc')
        self.assertEqual(result['stdout'], b'00616263\n')
        result = self.execute('import os;\nwhile True: os.write(1,b"x"*65536)', limits=Limits(output_bytes=1024))
        self.assertEqual(result['outcome'], 'output-limit')
        self.assertLessEqual(len(result['stdout']) + len(result['stderr']), 1024)

    def test_timeout_kills_detached_descendants(self):
        result = self.execute('''import os, time
if os.fork() == 0:
    os.setsid()
    time.sleep(2)
    open('/work/escaped','w').write('bad')
while True: time.sleep(1)
''', limits=Limits(wall_seconds=.7))
        self.assertEqual(result['outcome'], 'timeout')
        time.sleep(2)
        self.assertFalse((self.work / 'escaped').exists())

    def test_coordinator_death_terminates_namespace(self):
        # A worker that detached its own session must still die with its coordinator.
        worker = "import time;open('/work/started','w').write('yes');time.sleep(2);open('/work/escaped','w').write('bad')"
        source = "from experiments.application_comparison.isolation import run;run(" + repr(str(self.work)) + "," + repr([*PYTHON, worker]) + ")"
        process = subprocess.Popen([sys.executable, '-c', source], cwd=Path(__file__).resolve().parents[2],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 5
            while not (self.work / 'started').exists() and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertTrue((self.work / 'started').exists())
            process.kill()
            process.wait(timeout=5)
            time.sleep(2.1)
            self.assertFalse((self.work / 'escaped').exists())
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)

    def test_invalid_configuration_is_rejected_before_launch(self):
        with self.assertRaises(ValueError):
            run(self.work, ['/bin/true'], limits=Limits(wall_seconds=float('nan')))
        with self.assertRaises(ValueError):
            run(self.work, ['/bin/true'], tools={'../escape': self.root})


if __name__ == '__main__':
    unittest.main()
