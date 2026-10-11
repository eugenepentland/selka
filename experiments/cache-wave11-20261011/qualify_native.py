#!/usr/bin/env python3
"""Real-process Wave 11 qualification. Locks, rather than delays, gate concurrency."""
import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time

DEADLINE = 180


class Qualification:
    def __init__(self, args, root):
        self.compiler = str(Path(args.compiler).resolve())
        self.root = root
        self.children = []
        self.evidence = {}
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("MYLANG_")}
        self.env.update(MYLANG_ZIG=str(Path(args.zig).resolve()), TMPDIR=str(root),
                        MYLANG_CORE_RUNTIME_CACHE=str(root / "objects"),
                        MYLANG_COMPILER_SHARED_CACHE=str(root / "shared"),
                        MYLANG_TEST_SHARED_CACHE=str(root / "shared"))
        self.env.pop("SOURCE_DATE_EPOCH", None)
        self.env.pop("ZERO_AR_DATE", None)
        for name in ("a", "b", "c"):
            project = root / name
            project.mkdir()
            (project / "mylang.json").write_text('{"version":2,"budgets":{}}')
            (project / "app.my").write_text('import dep\nimport other\nfunc main(out: Stream) -> int:\n    out.print(dep.value() + other.value())\n    return 0\n')
            (project / "dep.my").write_text('public func value() -> int effects():\n    return 3\n')
            (project / "other.my").write_text('public func value() -> int effects():\n    return 4\n')
            (project / "tests.my").write_text('public func test_alpha() -> bool:\n    return True\n\npublic func test_beta() -> bool:\n    return 2 + 2 == 4\n')

    def command(self, name, test=False, extra=(), output="program"):
        project = self.root / name
        if test:
            return [self.compiler, "test", str(project / "tests.my"), "--json", "--cache-dir", str(project / "private"), *extra]
        return [self.compiler, "build", str(project / "app.my"), "-o", str(project / output), "--report", "--cache-dir", str(project / "private"), *extra]

    def start(self, name, test=False, extra=(), environment=None, output="program"):
        # Files prevent stdout/stderr pipe saturation from masquerading as lock waits.
        out = tempfile.TemporaryFile(dir=self.root)
        err = tempfile.TemporaryFile(dir=self.root)
        environment_map = dict(self.env)
        for key, value in (environment or {}).items():
            if value is None:
                environment_map.pop(key, None)
            else:
                environment_map[key] = value
        child = subprocess.Popen(self.command(name, test, extra, output), cwd=self.root / name,
                                 env=environment_map, stdout=out, stderr=err, start_new_session=True)
        self.children.append((child, out, err))
        return child

    def finish(self, child, version, status=0):
        child.wait(timeout=DEADLINE)
        _, out, err = next(entry for entry in self.children if entry[0] is child)
        out.seek(0)
        err.seek(0)
        stdout, stderr = out.read().decode(), err.read().decode()
        assert child.returncode == status, (child.returncode, stdout, stderr)
        if version is None:
            return {"status": child.returncode, "stdout": stdout, "stderr": stderr}
        records = []
        for line in (stdout + "\n" + stderr).splitlines():
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict) and value.get("version") == version:
                records.append(value)
        assert len(records) == 1, (version, stdout, stderr)
        return records[0]

    def run(self, name, test=False, extra=(), status=0):
        return self.finish(self.start(name, test, extra), "native-tests-v1" if test else "cache-report-v1", status)

    def reset(self, *names):
        for name in names:
            shutil.rmtree(self.root / name / "private", ignore_errors=True)

    def evict_units(self):
        """Remove completed unit objects before processes start; preserve lock inodes."""
        directory = self.root / "objects/units-v1"
        for path in directory.iterdir():
            if path.is_file() and not path.name.startswith("."):
                path.unlink()

    def gc(self, kind):
        result = subprocess.run([self.compiler, "cache", "gc", "--shared-cache-dir", str(self.root / "shared"), "--kind", kind, "--max-bytes", "0", "--max-entries", "0", "--apply"], env=self.env, capture_output=True, text=True, timeout=DEADLINE)
        assert result.returncode == 0, result.stderr
        return json.loads(result.stdout)["report"]

    def output(self, name, filename="program"):
        result = subprocess.run([str(self.root / name / filename)], capture_output=True, text=True, timeout=DEADLINE, env=self.env)
        assert result.returncode == 0 and result.stdout.strip() == "7", result

    def cleanup(self):
        for child, out, err in self.children:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGKILL)
            child.wait(timeout=10)
            out.close()
            err.close()


def wait_blocked(children):
    """Observe Linux's actual blocked flock records; elapsed time is no evidence."""
    deadline = time.monotonic() + DEADLINE
    wanted = {child.pid for child in children}
    while time.monotonic() < deadline:
        text = Path("/proc/locks").read_text()
        blocked = {int(match.group(1)) for match in re.finditer(r"->\s+FLOCK\s+ADVISORY\s+(?:READ|WRITE)\s+(\d+)\s", text)}
        if wanted <= blocked:
            return sorted(wanted)
        for child in children:
            assert child.poll() is None, f"process {child.pid} exited before reaching held claim"
        time.sleep(0.02)
    raise AssertionError(f"processes did not block on held claims: {wanted}; {text}")


@contextlib.contextmanager
def held(paths):
    files = []
    try:
        for path in sorted(set(paths)):
            path.parent.mkdir(parents=True, exist_ok=True)
            stream = path.open("a+b")
            fcntl.flock(stream, fcntl.LOCK_EX)
            files.append(stream)
        yield
    finally:
        for stream in reversed(files):
            stream.close()


def receipt(q, key):
    return q.root / "shared/native-tests-v2/receipts" / (key.stem + ".pass")


def qualify(q):
    # Warm identities, then remove completed artifacts while preserving claim inodes.
    warm = q.run("a")
    q.output("a")
    unit_root = q.root / "objects/units-v1"
    unit_locks = list((unit_root / "work").glob("*.lock"))
    assert unit_locks, "native unit claims were not created"
    program_root = q.root / "shared/compiler-artifacts-v2/program"
    assert program_root.exists(), "shared linked program artifacts absent"
    q.evict_units()
    for path in program_root.iterdir():
        if path.is_file():
            path.unlink()
    q.reset("a", "b")
    with held(unit_locks):
        first, second = q.start("a"), q.start("b")
        blocked = wait_blocked([first, second])
    builds = [q.finish(child, "cache-report-v1") for child in (first, second)]
    assert builds[0]["units"] == builds[1]["units"] == warm["units"], builds
    assert sum(item["compiled"] for item in builds) == warm["units"], builds
    assert sum(item["program"] == "linked" for item in builds) == 1, builds
    q.output("a")
    q.output("b")
    q.evidence["identical_builds"] = {"blocked_pids": blocked, "reports": builds}

    # Shared-cache selection differs, but both builds must own the same private
    # program claim. Reset before recreating/holding known lock paths so eviction
    # cannot unlink an active claim inode. Distinct outputs avoid output-file races.
    local_locks = list((q.root / "a/private/programs-v1/work").glob("*.lock"))
    assert local_locks, "private linked-program claims were not created"
    q.reset("a")
    for path in program_root.iterdir():
        if path.is_file():
            path.unlink()
    with held(local_locks):
        shared_build = q.start("a", output="program-mixed-shared")
        private_build = q.start("a", environment={"MYLANG_COMPILER_SHARED_CACHE": None}, output="program-mixed-private")
        blocked = wait_blocked([shared_build, private_build])
    mixed = [q.finish(child, "cache-report-v1") for child in (shared_build, private_build)]
    assert sum(item["program"] == "linked" for item in mixed) == 1, mixed
    assert sum(item["program"] == "reused" for item in mixed) == 1, mixed
    assert sum(item["compiled"] for item in mixed) == 0, mixed
    q.output("a", "program-mixed-shared")
    q.output("a", "program-mixed-private")
    q.evidence["mixed_program_sharing"] = {"blocked_pids": blocked, "reports": mixed}

    # Reversing import/source order exercises overlapping sets with differing enumeration.
    (q.root / "b/app.my").write_text('import other\nimport dep\nfunc main(out: Stream) -> int:\n    out.print(dep.value() + other.value())\n    return 0\n')
    q.reset("a", "b")
    q.evict_units()
    with held(unit_locks):
        first, second = q.start("a"), q.start("b")
        wait_blocked([first, second])
    reverse = [q.finish(child, "cache-report-v1") for child in (first, second)]
    q.output("a")
    q.output("b")
    q.evidence["reversed_sources"] = {"reports": reverse, "completed": True}

    warm_test = q.run("a", True, ["--filter", "alpha"])
    assert warm_test["passed"] == 1, warm_test
    test_root = q.root / "shared/native-tests-v2"
    alpha_locks = list((test_root / "work").glob("*.lock"))
    assert len(alpha_locks) == 1, alpha_locks
    alpha = alpha_locks[0]
    receipt(q, alpha).unlink()
    q.reset("a", "b")
    with held([alpha]):
        first, second = q.start("a", True, ["--filter", "alpha"]), q.start("b", True, ["--filter", "alpha"])
        blocked = wait_blocked([first, second])
        busy = q.gc("tests")
        assert busy["skipped_active"], busy
    tests = [q.finish(child, "native-tests-v1") for child in (first, second)]
    assert sum(item["passed"] for item in tests) == 1 and sum(item["cached"] for item in tests) == 1, tests
    q.evidence["same_test"] = {"blocked_pids": blocked, "reports": tests, "gc": busy}

    # One claim remains held while an unrelated test completes.
    q.reset("a", "b")
    with held([alpha]):
        blocked_test = q.start("a", True, ["--filter", "alpha"])
        wait_blocked([blocked_test])
        independent = q.run("b", True, ["--filter", "beta"])
        assert independent["passed"] == 1, independent
        assert blocked_test.poll() is None
    q.finish(blocked_test, "native-tests-v1")
    q.evidence["independent_test"] = independent

    # Corrupt records cannot manufacture success.
    receipt(q, alpha).write_text("corrupt")
    q.reset("a")
    corrupt = q.run("a", True, ["--filter", "alpha"])
    assert corrupt["passed"] == 1 and corrupt["cached"] == 0, corrupt
    q.evidence["corrupt_receipt"] = corrupt

    # Editing a loaded source while its process waits must reject the old snapshot.
    q.reset("b")
    source = q.root / "b/tests.my"
    before = source.read_text()
    with held([alpha]):
        edited = q.start("b", True, ["--filter", "alpha"])
        wait_blocked([edited])
        source.write_text(before.replace("return True", "return 1 == 1"))
    changed = q.finish(edited, None, status=1)
    assert "SourceChanged" in changed["stderr"], changed
    source.write_text(before)
    q.evidence["edit_while_waiting"] = changed

    # A killed real owner releases its test claim and cannot leave an earlier success.
    # Native unit locks park execution after force acquired and invalidated alpha.
    all_units = list((unit_root / "work").glob("*.lock"))
    q.reset("a", "b")
    q.evict_units()
    with held(all_units):
        owner = q.start("a", True, ["--filter", "alpha", "--force"])
        wait_blocked([owner])
        assert not receipt(q, alpha).exists(), "force retained old shared success"
        follower = q.start("b", True, ["--filter", "alpha"])
        wait_blocked([owner, follower])
        gc = q.gc("tests")
        assert gc["skipped_active"], gc
        os.killpg(owner.pid, signal.SIGKILL)
        owner.wait(timeout=10)
        wait_blocked([follower])
    retried = q.finish(follower, "native-tests-v1")
    assert retried["passed"] == 1 and retried["cached"] == 0, retried
    q.evidence["force_owner_killed"] = {"owner_status": owner.returncode, "follower": retried, "gc": gc}

    # A genuine deterministic failure is retried rather than published as success.
    for name in ("a", "b"):
        (q.root / name / "tests.my").write_text('public func test_failure() -> bool:\n    return False\n')
    q.reset("a", "b")
    failed = [q.run(name, True, status=1) for name in ("a", "b")]
    assert all(item["failed"] == 1 and item["cached"] == 0 for item in failed), failed
    q.evidence["failure_retry"] = failed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--zig", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    scratch = Path(".mylang-cache/tmp-wave11").resolve()
    scratch.mkdir(parents=True, exist_ok=True)
    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="native-qualification-", dir=scratch) as directory:
        q = Qualification(args, Path(directory))
        try:
            qualify(q)
            output.write_text(json.dumps({"version": "wave11-native-qualification-v1", "passed": True, "evidence": q.evidence}, sort_keys=True, indent=2) + "\n")
        except BaseException as error:
            output.write_text(json.dumps({"version": "wave11-native-qualification-v1", "passed": False, "error": str(error), "evidence": q.evidence}, sort_keys=True, indent=2) + "\n")
            raise
        finally:
            q.cleanup()
    print(json.dumps({"passed": True, "output": str(output)}))


if __name__ == "__main__":
    main()
