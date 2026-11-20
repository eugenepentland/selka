#!/usr/bin/env python3
"""Checks for scripts/patch_gate.py: the path rule, the step order and the JSON record.

    python3 -B scripts/patch_gate_test.py

Steps run through a stub, so no compiler is built. Each case that touches git works in
a throwaway repository under TMPDIR; nothing here reads or writes the real gate record.
"""
import contextlib
import datetime
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import patch_gate  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
NOW = datetime.datetime(2026, 10, 18, 12, 30, 5, tzinfo=datetime.timezone.utc)
EXPECTED_STEPS = [
    ("zig-build", ["zig", "build"]),
    ("affected-tests", ["python3", "scripts/affected_tests.py", "--base", "BASE"]),
    ("test-units", ["zig", "build", "test-units-gate"]),
    ("test-core", ["zig", "build", "test-core-gate"]),
    ("test-cli", ["zig", "build", "test-cli-gate"]),
    ("test-lang", ["zig", "build", "test-lang"]),
    ("test-docs", ["zig", "build", "test-docs"]),
    ("doc-coverage", ["zig-out/bin/selka", "doc-coverage", "."]),
    ("fmt-check", ["zig", "build", "fmt-check"]),
]


def git(root, *args):
    env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null",
               GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
    done = subprocess.run(["git", *args], cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert done.returncode == 0, (args, done.stderr)
    return done.stdout.strip()


def write(root, rel, text="x\n"):
    path = Path(root) / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def commit(root, subject, *files):
    for rel in files:
        write(root, rel, subject + "\n")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", subject)
    return git(root, "rev-parse", "HEAD")


class Repo:
    """A throwaway repository with a `main` branch holding one commit."""

    def __enter__(self):
        parent = os.environ.get("TMPDIR") or None
        self.dir = Path(tempfile.mkdtemp(prefix="patch-gate-test-", dir=parent)).resolve()
        git(self.dir, "init", "-q", "-b", "main")
        write(self.dir, ".gitignore", "ignored/\n")
        write(self.dir, "src/main.zig")
        write(self.dir, "scripts/tool.py")
        self.base = commit(self.dir, "initial", "src/main.zig", "scripts/tool.py")
        self.logs = self.dir.parent / (self.dir.name + "-logs")
        return self

    def __exit__(self, *exc):
        shutil.rmtree(self.dir, ignore_errors=True)
        shutil.rmtree(self.logs, ignore_errors=True)

    def records(self):
        path = self.dir / patch_gate.RECORD_REL
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []


class Stub:
    """A step runner that records what it was asked to run and fails on request.

    With `meet`, every step named there waits at a barrier first, so the call only
    returns when all of them are running at the same time.
    """

    def __init__(self, fail_at=None, wait=0.0, meet=()):
        self.ran = []
        self.fail_at = fail_at
        self.wait = wait
        self.meet = set(meet)
        self.barrier = threading.Barrier(len(self.meet), timeout=10) if self.meet else None

    def __call__(self, step, log_path, root):
        self.ran.append((step.name, list(step.argv), log_path.name))
        if step.name in self.meet:
            self.barrier.wait()
        failing = step.name == self.fail_at
        if failing:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_path.write_text("$ boom\nline one\nthe real failure\n")
        return patch_gate.StepResult(1 if failing else 0, 2.0 + len(self.ran), self.wait)


def gate(repo, *args, runner=None):
    """Run the gate against the throwaway repo; returns (status, output)."""
    out = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
        status = patch_gate.run(["--log-dir", str(repo.logs), *args], root=repo.dir, runner=runner, now=lambda: NOW)
    return status, out.getvalue()


def check_path_rule():
    allowed = ["src/main.zig", "src/core/lower.zig", "docs/language.md", "tests/lang/strings.selka", "test/integration.zig",
               "test/core/b_buffer_values.selka", "examples/hello/main.selka", "SPEC.md",
               "experiments/project-ladder-20261018/P0.2-patch-gate.md", "experiments/project-ladder-20261018/gates.jsonl"]
    refused = ["scripts/patch_gate.py", "build.zig", "build_env.zig", "build_identity.zig", "build_test_inputs.zig",
               "build_verification.zig", "build.zig.zon",
               "selfhost/lexer.selka", "README.md", "CLAUDE.md", ".zigversion", "experiments/other-20261018/notes.md",
               "srcs/main.zig", "src", "tests.py", "SPEC.md.orig", "docs", "zigw"]
    for path in allowed:
        assert patch_gate.is_allowed(path), path
    for path in refused:
        assert not patch_gate.is_allowed(path), path
    for path in sorted(patch_gate.MACHINERY):
        assert patch_gate.is_allowed(path.split("/")[0] + "/other") and not patch_gate.is_allowed(path), path
    assert patch_gate.disallowed(allowed + refused[:3]) == sorted(refused[:3])


def check_machinery_listing():
    """Every src/ file a root build*.zig imports is machinery or a recorded data read, and each exists."""
    imported = set()
    for build_file in REPO.glob("build*.zig"):
        imported.update(re.findall(r'@import\("(src/[^"]+)"\)', build_file.read_text()))
    assert imported, "no build-time src imports found; the scan is stale"
    for path in sorted(imported):
        assert path in patch_gate.MACHINERY or path in patch_gate.BUILD_READ_BUT_NOT_MACHINERY, \
            "{} is imported by a root build*.zig: decide whether it is verification machinery".format(path)
    for path in sorted(patch_gate.MACHINERY | patch_gate.BUILD_READ_BUT_NOT_MACHINERY):
        assert (REPO / path).exists(), "{} is listed but missing".format(path)


def check_step_list():
    steps = patch_gate.steps_for("BASE")
    assert [(s.name, list(s.argv)) for s in steps] == EXPECTED_STEPS
    assert all(s.slot == "build" for s in steps)
    command = steps[2].command(Path("/r"))
    assert command == ["/r/scripts/build-slot.sh", "build", "zig", "build", "test-units-gate"], command


def check_changed_paths():
    with Repo() as repo:
        commit(repo.dir, "committed", "docs/a.md")
        write(repo.dir, "src/main.zig", "edited\n")  # unstaged
        write(repo.dir, "tests/staged.selka")
        git(repo.dir, "add", "tests/staged.selka")  # staged
        write(repo.dir, "scripts/untracked.py")  # untracked
        write(repo.dir, "ignored/skip.txt")  # untracked but ignored
        found = patch_gate.changed_paths(repo.dir, repo.base)
        assert found == ["docs/a.md", "scripts/untracked.py", "src/main.zig", "tests/staged.selka"], found
        assert patch_gate.changed_paths(repo.dir, "HEAD") == ["scripts/untracked.py", "src/main.zig", "tests/staged.selka"]
        git(repo.dir, "rm", "-q", "-f", "scripts/tool.py")
        assert "scripts/tool.py" in patch_gate.changed_paths(repo.dir, "HEAD"), "a deleted path must count"


def check_green_record():
    with Repo() as repo:
        head = commit(repo.dir, "FR-012: fix a thing", "src/main.zig")
        commit(repo.dir, "FR-007, other work", "docs/a.md")
        commit(repo.dir, "FR-012: second part", "tests/a.selka")
        commit(repo.dir, "not FR-099 at the start", "examples/a.selka")
        write(repo.dir, "src/dirty.zig")
        stub = Stub(wait=1.5)
        status, output = gate(repo, "--base", repo.base, runner=stub)
        assert status == 0, output
        assert [(name, argv) for name, argv, _ in stub.ran] == [(n, [repo.base if a == "BASE" else a for a in argv])
                                                               for n, argv in EXPECTED_STEPS]
        assert [log for _, _, log in stub.ran][:2] == ["01-zig-build.log", "02-affected-tests.log"]
        (record,) = repo.records()
        assert record["version"] == "patch-gate-v1"
        assert record["commit"] == git(repo.dir, "rev-parse", "HEAD") != head
        assert record["dirty"] is True and record["base"] == repo.base
        assert record["started_utc"] == "2026-10-18T12:30:05Z"
        assert record["verdict"] == "green" and record["disallowed"] == []
        assert record["fr_ids"] == ["FR-012", "FR-007"], record["fr_ids"]
        assert [s["name"] for s in record["steps"]] == [n for n, _ in EXPECTED_STEPS]
        assert all(s["exit"] == 0 and isinstance(s["wall_s"], float) and s["wait_s"] == 1.5 for s in record["steps"])
        assert record["steps"][1]["argv"][-1] == repo.base
        assert isinstance(record["total_s"], float) and record["total_s"] >= 0
        for key in ("load_avg_start", "load_avg_end"):
            assert record[key] is None or len(record[key]) == 3
        assert "verdict: green (9 of 9 steps run" in output and output.count("] ok ") == 9, output
        assert "(admission wait 1.5s)" in output


# In the --parallel plan the affected tests skip what the suites step reruns in full.
PARALLEL_STEPS = [(name, argv + ["--skip-gate-suites"] if name == "affected-tests" else argv)
                  for name, argv in EXPECTED_STEPS[:2]] + [
    ("suites", ["zig", "build", "test-units-gate", "test-core-gate", "test-cli-gate", "test-lang", "test-docs",
                "test-doc-coverage", "fmt-check"])]


def check_parallel_groups_the_tail_into_one_step():
    with Repo() as repo:
        commit(repo.dir, "FR-020: fix", "src/main.zig")
        # The barrier returns only when the affected tests and the suites step run at the same time.
        stub = Stub(meet=("affected-tests", "suites"))
        status, output = gate(repo, "--base", repo.base, "--parallel", runner=stub)
        assert status == 0, output
        ran = [name for name, _, _ in stub.ran]
        assert ran[:1] == ["zig-build"], "the install first"
        assert sorted(ran[1:]) == ["affected-tests", "suites"], "then the affected tests beside the one suites step"
        (record,) = repo.records()
        assert record["parallel"] is True and record["verdict"] == "green"
        assert [s["name"] for s in record["steps"]] == [n for n, _ in PARALLEL_STEPS]
        assert record["steps"][2]["argv"] == PARALLEL_STEPS[2][1]
        assert record["steps"][1]["argv"] == ["python3", "scripts/affected_tests.py", "--base", repo.base, "--skip-gate-suites"]
        assert "verdict: green (3 of 3 steps run" in output
        logs = {name: log for name, _, log in stub.ran}
        assert logs["suites"] == "03-suites.log"


def check_parallel_plan_covers_every_sequential_check():
    sequential = {target for _, argv in EXPECTED_STEPS[2:] for target in argv[2:3] if argv[:2] == ["zig", "build"]}
    grouped = set(PARALLEL_STEPS[2][1][2:])
    # Every zig-build check of the sequential plan is in the one step (doc-coverage becomes its cached zig step).
    assert sequential <= grouped, (sequential, grouped)
    assert "test-doc-coverage" in grouped


def check_parallel_reports_a_failing_suites_step():
    with Repo() as repo:
        commit(repo.dir, "edit", "src/main.zig")
        stub = Stub(fail_at="suites")
        status, output = gate(repo, "--base", repo.base, "--parallel", runner=stub)
        assert status == 1 and len(stub.ran) == 3, output
        (record,) = repo.records()
        assert record["verdict"] == "red"
        assert [(s["name"], s["exit"]) for s in record["steps"] if s["exit"] != 0] == [("suites", 1)]
        assert "--- suites failed" in output and "the real failure" in output


def check_parallel_affected_failure_still_reports_the_suites():
    with Repo() as repo:
        commit(repo.dir, "edit", "src/main.zig")
        stub = Stub(fail_at="affected-tests")
        status, output = gate(repo, "--base", repo.base, "--parallel", runner=stub)
        assert status == 1 and sorted(name for name, _, _ in stub.ran) == sorted(n for n, _ in PARALLEL_STEPS), output
        (record,) = repo.records()
        assert record["verdict"] == "red"
        assert [s["name"] for s in record["steps"]] == [n for n, _ in PARALLEL_STEPS], "gate order, whatever finished first"
        assert [(s["name"], s["exit"]) for s in record["steps"] if s["exit"] != 0] == [("affected-tests", 1)]
        assert "--- affected-tests failed" in output and "verdict: red (3 of 3 steps run" in output


def check_parallel_prefix_failure_stops_the_run():
    with Repo() as repo:
        commit(repo.dir, "edit", "src/main.zig")
        stub = Stub(fail_at="zig-build")
        status, output = gate(repo, "--base", repo.base, "--parallel", runner=stub)
        assert status == 1 and [name for name, _, _ in stub.ran] == ["zig-build"], output
        assert [s["name"] for s in repo.records()[0]["steps"]] == ["zig-build"]


def check_sequential_record_says_not_parallel():
    with Repo() as repo:
        commit(repo.dir, "edit", "docs/a.md")
        status, _ = gate(repo, "--base", repo.base, runner=Stub())
        assert status == 0 and repo.records()[0]["parallel"] is False and "jobs" not in repo.records()[0]


def check_clean_tree_is_not_dirty():
    with Repo() as repo:
        commit(repo.dir, "docs only", "docs/a.md")
        status, _ = gate(repo, "--base", repo.base, runner=Stub())
        assert status == 0 and repo.records()[0]["dirty"] is False
        # The record itself is an uncommitted change inside the scope; it must not count as dirt.
        status, _ = gate(repo, "--base", repo.base, runner=Stub())
        assert status == 0 and [r["dirty"] for r in repo.records()] == [False, False]


def check_red_stops_at_first_failure():
    with Repo() as repo:
        commit(repo.dir, "FR-001: edit", "src/main.zig")
        stub = Stub(fail_at="affected-tests")
        status, output = gate(repo, "--base", repo.base, runner=stub)
        assert status == 1, output
        assert [name for name, _, _ in stub.ran] == ["zig-build", "affected-tests"]
        (record,) = repo.records()
        assert record["verdict"] == "red"
        assert [(s["name"], s["exit"]) for s in record["steps"]] == [("zig-build", 0), ("affected-tests", 1)]
        assert "--- affected-tests failed" in output and "the real failure" in output
        assert "verdict: red (2 of 9 steps run" in output


def check_complete_required():
    with Repo() as repo:
        commit(repo.dir, "touch the gate", "scripts/tool.py", "docs/a.md")
        write(repo.dir, "build.zig")
        stub = Stub()
        status, output = gate(repo, "--base", repo.base, runner=stub)
        assert status == 3, output
        assert stub.ran == [], "no step may run"
        assert "  build.zig\n" in output and "  scripts/tool.py\n" in output and "docs/a.md" not in output
        assert output.splitlines()[-1] == ("complete verification required: python3 scripts/verify_cache.py "
                                           "--profile complete"), output
        (record,) = repo.records()
        assert record["verdict"] == "complete-required" and record["steps"] == []
        assert record["disallowed"] == ["build.zig", "scripts/tool.py"]


def check_machinery_needs_complete():
    with Repo() as repo:
        commit(repo.dir, "edit the contract", "src/environment_identity.zon", "src/ordinary.zig")
        stub = Stub()
        status, output = gate(repo, "--base", repo.base, runner=stub)
        assert status == 3 and stub.ran == []
        assert "  src/environment_identity.zon\n" in output and "  src/ordinary.zig\n" not in output


def check_default_base_is_merge_base_with_main():
    with Repo() as repo:
        git(repo.dir, "switch", "-q", "-c", "projects/fixes")
        commit(repo.dir, "FR-003: fix", "src/main.zig")
        stub = Stub()
        status, output = gate(repo, runner=stub)
        assert status == 0, output
        assert repo.records()[0]["base"] == repo.base and repo.records()[0]["fr_ids"] == ["FR-003"]


def check_dry_run_writes_nothing():
    with Repo() as repo:
        commit(repo.dir, "ok", "docs/a.md")
        stub = Stub()
        status, output = gate(repo, "--base", repo.base, "--dry-run", runner=stub)
        assert status == 0 and stub.ran == [] and repo.records() == []
        assert "path rule: ok" in output and " 9. fmt-check" in output
        commit(repo.dir, "not ok", "build.zig.zon")
        status, output = gate(repo, "--base", repo.base, "--dry-run", runner=stub)
        assert status == 3 and stub.ran == [] and repo.records() == []
        assert "complete verification required" in output and " 9. fmt-check" in output
        assert not repo.logs.exists()


def check_usage_errors():
    with Repo() as repo:
        status, output = gate(repo, "--base", "no-such-ref", runner=Stub())
        assert status == 2 and "does not name a commit" in output and repo.records() == []
    with Repo() as repo:
        git(repo.dir, "branch", "-m", "main", "trunk")
        status, output = gate(repo, runner=Stub())
        assert status == 2 and "merge-base" in output
    try:
        with contextlib.redirect_stderr(io.StringIO()):
            patch_gate.run(["--bogus"], root=REPO, runner=Stub())
    except SystemExit as exit_:
        assert exit_.code == 2
    else:
        raise AssertionError("argparse must reject an unknown flag with status 2")


def check_environment_warnings():
    root = Path("/work/tree")
    good = {"SELKA_SLOT_DIR": "/s", "ZIG_LOCAL_CACHE_DIR": "/work/tree/.zig-cache", "TMPDIR": "/work/tree/.tmp/work"}
    assert patch_gate.environment_warnings(root, good) == []
    assert len(patch_gate.environment_warnings(root, {})) == 1
    shared = dict(good, ZIG_LOCAL_CACHE_DIR="/other/.zig-cache")
    assert any("outside this worktree" in note for note in patch_gate.environment_warnings(root, shared))


def check_admission_wait_parse():
    with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR") or None) as directory:
        log = Path(directory) / "01-x.log"
        log.write_text("$ zig build\nbuild-slot: build slot 2, FIFO ticket 41 after 7.250s\nbuilding\n")
        assert patch_gate.parse_wait(log) == 7.25
        log.write_text("$ zig build\nno admission line\n")
        assert patch_gate.parse_wait(log) == 0.0
        assert patch_gate.parse_wait(Path(directory) / "missing.log") == 0.0


def check_real_runner_logs_output():
    """The real runner, pointed at a stand-in wrapper, writes the log and reports the exit status."""
    with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR") or None) as directory:
        root = Path(directory)
        wrapper = root / "scripts" / "build-slot.sh"
        wrapper.parent.mkdir()
        wrapper.write_text('#!/bin/sh\necho "build-slot: $1 slot 1, FIFO ticket 1 after 0.500s" >&2\nshift\nexec "$@"\n')
        wrapper.chmod(0o755)
        step = patch_gate.Step("probe", ("sh", "-c", "echo out; echo err >&2; exit 7"))
        result = patch_gate.run_step(step, root / "logs" / "01-probe.log", root)
        text = (root / "logs" / "01-probe.log").read_text()
        assert result.exit == 7 and result.wait_s == 0.5 and result.wall_s >= 0
        assert text.startswith("$ sh -c 'echo out; echo err >&2; exit 7'\n") and "out\n" in text and "err\n" in text


def check_terminate_all_stops_running_steps():
    """An interrupt stops every live step's process group instead of leaving it running."""
    with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR") or None) as directory:
        root = Path(directory)
        wrapper = root / "scripts" / "build-slot.sh"
        wrapper.parent.mkdir()
        wrapper.write_text('#!/bin/sh\nshift\nexec "$@"\n')
        wrapper.chmod(0o755)
        results = []
        workers = [threading.Thread(target=lambda n=n: results.append(patch_gate.run_step(
            patch_gate.Step("sleep" + str(n), ("sleep", "60")), root / "logs" / "{}.log".format(n), root))) for n in range(3)]
        for worker in workers:
            worker.start()
        deadline = datetime.datetime.now() + datetime.timedelta(seconds=10)
        while len(patch_gate.LIVE) < 3:
            assert datetime.datetime.now() < deadline, "steps did not start"
            time.sleep(0.01)
        patch_gate.terminate_all()
        for worker in workers:
            worker.join(30)
            assert not worker.is_alive()
        assert len(results) == 3 and all(r.exit < 0 and r.wall_s < 30 for r in results), results
        assert not patch_gate.LIVE


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_") and callable(value)]


def main():
    for check in CHECKS:
        check()
        print("ok  " + check.__name__)
    print("patch_gate_test: {} checks passed".format(len(CHECKS)))


if __name__ == "__main__":
    main()
