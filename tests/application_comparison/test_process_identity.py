import os
import subprocess
import sys
import unittest
from experiments.application_comparison import process_identity as processes


class ProcessIdentityTests(unittest.TestCase):
    def test_real_process_lifecycle_and_mismatched_identity(self):
        child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
        try:
            identity, _ = processes.capture(child.pid)
            self.assertEqual(processes.observe(identity)['status'], 'live')
            self.assertEqual(processes.observe(dict(identity, start_ticks=identity['start_ticks'] + 1))['status'], 'different-process')
            self.assertEqual(processes.observe(dict(identity, pid_namespace='different'))['status'], 'unknown')
            self.assertEqual(processes.observe(None)['status'], 'unknown')
        finally:
            child.terminate()
            child.wait(timeout=5)
        self.assertEqual(processes.observe(identity)['status'], 'not-running')

    def test_parentheses_in_name_do_not_shift_start_field(self):
        identity, _ = processes.capture(os.getpid())
        fields = ['S'] + ['0'] * 18 + [str(identity['start_ticks'])]
        self.assertEqual(processes.stat_fields('123 (a tricky ) name) ' + ' '.join(fields), 123), (identity['start_ticks'], 'S'))
        with self.assertRaises(ValueError):
            processes.stat_fields('bad', 123)


if __name__ == '__main__':
    unittest.main()
