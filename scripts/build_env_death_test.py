#!/usr/bin/env python3
"""A killed supervising build-env leaves no command behind (PR_SET_PDEATHSIG)."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


def process_finished(pid):
    """A killed command may stay a zombie until the nearest subreaper reaps it."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    try:
        state = Path('/proc') / str(pid) / 'stat'
        return state.read_text().split(') ', 1)[1].split()[0] == 'Z'
    except (OSError, IndexError):
        return True


def zig():
    return os.environ.get("ZIG") or os.environ.get("SELKA_ZIG") or "zig"


class BuildEnvParentDeath(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix="build-env-death-"))
        self.addCleanup(shutil.rmtree, self.directory, True)
        self.binary = self.directory / "build-env"
        environment = dict(os.environ)
        environment.setdefault("ZIG_GLOBAL_CACHE_DIR", str(self.directory / "global"))
        built = subprocess.run(
            [zig(), "build-exe", "-OReleaseSafe", "-Mroot=build_env.zig", "--name", "build-env",
             "-femit-bin=" + str(self.binary), "--cache-dir", str(self.directory / "zig"),
             "--global-cache-dir", environment["ZIG_GLOBAL_CACHE_DIR"]],
            # A cold ReleaseSafe compile: 24 s at a load of 16 to 25, so 120 s could pass at a load of 50 with swap full and
            # fail the test before it asserts anything (DL-4 item 4e). The bound only stops a hang.
            cwd=Path(__file__).resolve().parents[1], capture_output=True, text=True, timeout=600,
            env=environment)
        self.assertEqual(built.returncode, 0, built.stderr)
        self.assertTrue(self.binary.is_file())

    def wait_for(self, path, seconds=60):
        """Wait for `path` to hold something: the step command creates the file, then writes its pid, and a saturated machine can
        run a reader between the two (the gate of 9 November read an empty file)."""
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if path.exists() and path.stat().st_size > 0:
                return True
            time.sleep(0.02)
        return path.exists() and path.stat().st_size > 0

    def test_killing_the_supervisor_kills_the_step_command(self):
        marker = self.directory / "child-pid"
        environment = dict(os.environ, SELKA_STEP_DEADLINE_SECONDS="60")
        process = subprocess.Popen(
            [str(self.binary), "project", "--", "sh", "-c", 'echo $$ > "$1"; sleep 60', "sh", str(marker)],
            cwd=Path(__file__).resolve().parents[1], env=environment,
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            self.assertTrue(self.wait_for(marker), "step command never started")
            child = int(marker.read_text())
            process.send_signal(signal.SIGKILL)
            process.wait(timeout=60)
            gone = False
            deadline = time.monotonic() + 60
            while time.monotonic() < deadline:
                if process_finished(child):
                    gone = True
                    break
                time.sleep(0.02)
            self.assertTrue(gone, "step command survived its killed supervisor")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == "__main__":
    unittest.main()
