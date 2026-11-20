#!/usr/bin/env python3
"""Service refresh contracts use private repositories and never contact systemd."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import shutil
import shlex
import sys
import tempfile
import time
import unittest
from unittest import mock

import service_worktree as service


class ServiceWorktree(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="service-worktree-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.main = self.directory / "main"
        self.main.mkdir()
        self.call("init", "-b", "main")
        self.call("config", "user.name", "Service fixture")
        self.call("config", "user.email", "fixture@example.invalid")
        (self.main / ".gitignore").write_text("__pycache__/\n")
        self.runner("printf old > \"$1\"\n")
        self.commit()
        self.tree = self.directory / "service"
        self.call("worktree", "add", "--detach", str(self.tree))
        service.register(self.tree)

    def call(self, *arguments):
        return service.git(self.main, *arguments).stdout.strip()

    def runner(self, text):
        for relative in service.RUNNERS.values():
            path = self.main / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + text)

    def commit(self):
        self.call("add", ".")
        self.call("-c", "core.hooksPath=/dev/null", "commit", "-m", "fixture")

    def test_refresh_executes_new_main_runner_not_the_old_loaded_source(self):
        self.runner("printf fresh > \"$1\"\n")
        self.commit()
        target = self.directory / "result"
        self.assertEqual(service.run(self.tree, "core", [str(target)]), 0)
        self.assertEqual(target.read_text(), "fresh")
        self.assertEqual(service.git(self.tree, "rev-parse", "HEAD").stdout.strip(), self.call("rev-parse", "main"))
        self.assertEqual(service.git(self.tree, "symbolic-ref", "-q", "HEAD", check=False).returncode, 1)

    def test_the_wrapper_prints_the_runners_lines_itself_and_stays_until_the_journal_has_them(self):
        # The nightly's `nightly: exit N: ...` line is written by a script that exits at once, which journald cannot
        # attribute to the unit. The wrapper is alive for the whole run: it relays the line and outlives it.
        self.runner('if [ -p /dev/stdout ]; then printf pipe > "$1"; else printf file > "$1"; fi\n'
                    'printf "nightly: exit 1: verification: integration FAIL (status 1): the verdict\\n"\n'
                    'exit 3\n')
        self.commit()
        kind = self.directory / "kind"
        output = self.directory / "wrapper-output"
        script = str(Path(service.__file__).resolve())
        began = time.monotonic()
        with output.open("w") as stream:
            completed = subprocess.run(["python3", script, "--worktree", str(self.tree), "--service", "nightly",
                                        "--", str(kind)], stdout=stream, stderr=subprocess.PIPE, text=True, timeout=120,
                                       env=dict(os.environ, SELKA_SERVICE_SETTLE_SECONDS="1.5"))
        self.assertEqual(completed.returncode, 3, completed.stderr)
        self.assertEqual(kind.read_text(), "pipe", "the runner wrote to the wrapper, not to the unit's own stream")
        lines = output.read_text().splitlines()
        self.assertTrue(lines[0].startswith("service=nightly worktree="))
        self.assertEqual(lines[1:], ["nightly: exit 1: verification: integration FAIL (status 1): the verdict"])
        self.assertGreaterEqual(time.monotonic() - began, 1.5)

    def test_a_background_process_holding_the_runners_output_does_not_keep_the_service_running(self):
        # The old wrapper inherited the runner's output and waited for the runner only; the relay must not wait for a
        # process the runner left behind with the pipe open.
        self.runner('printf "last line\\n"\n(sleep 30 >&1 2>/dev/null &)\nexit 0\n')
        self.commit()
        script = str(Path(service.__file__).resolve())
        began = time.monotonic()
        completed = subprocess.run(["python3", script, "--worktree", str(self.tree), "--service", "nightly"],
                                   capture_output=True, text=True, timeout=120,
                                   env=dict(os.environ, SELKA_SERVICE_RELAY_DRAIN_SECONDS="1",
                                            SELKA_SERVICE_SETTLE_SECONDS="0"))
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("last line\n", completed.stdout)
        self.assertLess(time.monotonic() - began, 25)

    def test_a_runner_that_prints_nothing_is_not_waited_for(self):
        self.runner('printf quiet > "$1"\n')
        self.commit()
        target = self.directory / "quiet"
        with mock.patch.object(service.time, "sleep") as slept, \
                mock.patch.dict(os.environ, {"SELKA_SERVICE_SETTLE_SECONDS": "60"}), \
                mock.patch("sys.stdout"):
            self.assertEqual(service.run(self.tree, "core", [str(target)]), 0)
        slept.assert_not_called()

    def test_non_service_branch_and_dirty_worktrees_are_refused_without_checkout(self):
        head = service.git(self.tree, "rev-parse", "HEAD").stdout
        (self.tree / "untracked.txt").write_text("keep")
        with self.assertRaisesRegex(ValueError, "dirty"):
            service.run(self.tree, "nightly")
        self.assertEqual(service.git(self.tree, "rev-parse", "HEAD").stdout, head)
        with self.assertRaisesRegex(ValueError, "registered"):
            service.run(self.main, "nightly")
        with self.assertRaisesRegex(ValueError, "detached"):
            service.register(self.main)
        self.assertEqual(self.call("symbolic-ref", "--short", "HEAD"), "main")

    def test_a_missing_checkout_fails_with_one_clear_line(self):
        missing = self.directory / "missing-checkout"
        completed = subprocess.run([sys.executable, str(Path(service.__file__)),
                                    "--worktree", str(missing), "--service", "core"],
                                   capture_output=True, text=True, timeout=60)
        self.assertEqual(completed.returncode, 1)
        self.assertIn(f"service checkout {missing} is missing", completed.stderr)
        self.assertIn("reinstall the timer", completed.stderr)
        self.assertEqual(len(completed.stderr.strip().splitlines()), 1)

    def test_a_branch_switch_after_registration_is_refused(self):
        service.git(self.tree, "checkout", "-b", "another-session")
        with self.assertRaisesRegex(ValueError, "detached"):
            service.run(self.tree, "core")
        self.assertEqual(service.git(self.tree, "symbolic-ref", "--short", "HEAD").stdout.strip(), "another-session")

    def test_source_mutation_after_refresh_before_spawn_is_refused(self):
        original = service.git

        def replacing(root, *arguments, **options):
            result = original(root, *arguments, **options)
            if arguments[:2] == ("checkout", "--detach"):
                (self.tree / service.RUNNERS["core"]).write_text("exit 99\n")
            return result

        with mock.patch.object(service, "git", replacing):
            with self.assertRaisesRegex(ValueError, "dirty"):
                service.run(self.tree, "core")

    def test_both_services_serialize_checkout_and_entire_child_run(self):
        self.runner('printf started > "$1"\nread -r answer < "$2"\nprintf done > "$1"\n')
        self.commit()
        first = self.directory / "first"
        second = self.directory / "second"
        fifo = self.directory / "release"
        os.mkfifo(fifo)
        script = str(Path(service.__file__).resolve())
        command = ["python3", script, "--worktree", str(self.tree)]
        release = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)
        children = []
        try:
            active = subprocess.Popen([*command, "--service", "core", "--", str(first), str(fifo)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            children.append(active)
            self.wait_file(first)
            self.runner('printf refreshed > "$1"\n')
            self.commit()
            waiting = subprocess.Popen([*command, "--service", "nightly", "--", str(second)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            children.append(waiting)
            time.sleep(0.1)
            self.assertFalse(second.exists())
            self.assertIsNone(waiting.poll())
            os.write(release, b"continue\n")
            self.assertEqual(active.wait(timeout=10), 0)
            self.assertEqual(waiting.wait(timeout=10), 0)
        finally:
            os.write(release, b"continue\n")
            os.close(release)
            for child in children:
                if child.poll() is None:
                    child.terminate()
                child.communicate(timeout=10)
        self.assertEqual(first.read_text(), "done")
        self.assertEqual(second.read_text(), "refreshed")

    def wait_file(self, path):
        deadline = time.monotonic() + 10
        while not path.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(path.exists(), "service did not start")

    def test_installer_preview_routes_both_services_through_same_refresh_helper(self):
        root = Path(__file__).resolve().parents[1]
        spec = importlib.util.spec_from_file_location("nightly_installer", root / "scripts/install-nightly-integration-timer.py")
        installer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(installer)
        nightly = installer.render_units(root)["selka-nightly-integration.service"]
        core = subprocess.run(["bash", str(root / "scripts/systemd/install-core-store-timer.sh"), "--dry-run"], check=True, text=True, capture_output=True).stdout
        for rendered in (nightly, core):
            self.assertIn(f"WorkingDirectory={root}", rendered)
            self.assertIn("service_worktree.py", rendered)
            self.assertIn("--worktree", rendered)
        self.assertIn("--service core -- --apply", core)
        self.assertIn("--service nightly", nightly)
        self.assertEqual(json.loads(service.marker_path(self.tree).read_text())["worktree"], str(self.tree))

    def test_both_installers_register_detached_tree_and_write_durable_working_directory(self):
        root = Path(__file__).resolve().parents[1]
        files = ["scripts/service_worktree.py", "scripts/install-nightly-integration-timer.py",
                 "scripts/systemd/install-core-store-timer.sh",
                 "scripts/systemd/selka-core-store.service", "scripts/systemd/selka-core-store.timer",
                 "scripts/systemd/selka-nightly-integration.service", "scripts/systemd/selka-nightly-integration.timer"]
        for relative in files:
            shutil.copyfile(root / relative, self.main / relative)
        (self.main / "scripts/verify_cache.py").write_text("# fixture coordinator\n")
        self.commit()
        service.git(self.tree, "checkout", "--detach", "main")
        fake_bin = self.directory / "fake-bin"
        fake_bin.mkdir()
        calls = self.directory / "systemctl-calls"
        fake = fake_bin / "systemctl"
        fake.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> " + shlex.quote(str(calls)) + "\n")
        fake.chmod(0o755)
        config = self.directory / "configuration"
        environment = dict(os.environ, XDG_CONFIG_HOME=str(config), PATH=str(fake_bin) + os.pathsep + os.environ["PATH"])
        for command in (["bash", str(self.tree / files[2]), "--apply"],
                        [sys.executable, str(self.tree / files[1]), "--worktree", str(self.tree), "--apply"]):
            result = subprocess.run(command, capture_output=True, text=True, env=environment)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name in ("core-store", "nightly-integration"):
            text = (config / "systemd/user" / f"selka-{name}.service").read_text()
            self.assertIn(f"WorkingDirectory={self.tree}\n", text)
            self.assertIn("service_worktree.py", text)
        self.assertEqual(calls.read_text().count("daemon-reload"), 2)
        self.assertIn("enable --now selka-core-store.timer", calls.read_text())
        self.assertIn("enable --now selka-nightly-integration.timer", calls.read_text())
        self.assertEqual(json.loads(service.marker_path(self.tree).read_text())["worktree"], str(self.tree))


if __name__ == "__main__":
    unittest.main()
