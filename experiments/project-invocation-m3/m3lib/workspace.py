#!/usr/bin/env python3
"""Participant workspaces: the frozen app, the arm's launcher, the brief, the ledgers.

One workspace is one session. It holds the application snapshot with the case's
seeded regression applied, the frozen compiler and byte-I/O host behind counting
shims, the thin `project` launcher, the task brief and the coordinator's ledgers
(`.m3/`). It holds no hidden check, no mutation record and no solution.

Every compiler process the participant starts — through the launcher's manifest
steps or directly — goes through the shim, which appends one event per process to
`MYLANG_EVENT_LOG` and then runs the frozen tool unchanged. Resolution failures
that never reach a compiler go to `MYLANG_M3_RESOLUTION_LOG` instead.
"""

from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

IGNORE = shutil.ignore_patterns("__pycache__", ".mylang-cache", ".cache", ".zig-cache", "_verify")

SHIM = '''#!/usr/bin/env python3
"""Counting shim for the frozen {kind}: one event per compiler/tool process.

The shim is measurement, not treatment: it runs the frozen tool with the same
arguments, streams and exit status, and records what happened. A shell command
containing three tool invocations produces three events; one invocation that
emits three diagnostics produces one.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

sys.path.insert(0, {coordinator!r})
import events

REAL = {real!r}
KIND = {kind!r}
COMPILER_SHA256 = {compiler_sha256!r}

# Commands that accept `--cache-dir`: injecting the session's own cache root
# keeps every build artifact outside the candidate source tree, so a check does
# not make the project inventory look edited. Both arms receive this identical
# shim, and the flag never changes what the command computes.
CACHE_AWARE = ("run", "run-project", "test", "build", "check-project", "index-project")


def with_cache(argv):
    cache = os.environ.get("MYLANG_M3_CACHE", "")
    if not cache or not argv or argv[0] not in CACHE_AWARE:
        return argv
    if any(part.startswith("--cache-dir") for part in argv):
        return argv
    return [argv[0], "--cache-dir=" + cache] + list(argv[1:])


def append(path, event):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as handle:
        handle.write(json.dumps(event, sort_keys=True) + "\\n")
        handle.flush()
        os.fsync(handle.fileno())


def main():
    argv = with_cache(sys.argv[1:])
    log_path = os.environ.get("MYLANG_EVENT_LOG", "")
    app = os.environ.get("MYLANG_M3_APP", "")
    root = Path(app) if app else Path.cwd()
    before = events.inventory(root)[0] if root.is_dir() else ""
    started = time.monotonic_ns()
    completed = subprocess.run([REAL] + argv, capture_output=True)
    finished = time.monotonic_ns()
    after = events.inventory(root)[0] if root.is_dir() else ""
    stderr = completed.stderr.decode(errors="replace")
    diagnostics = events.parse_diagnostics(stderr)
    command = argv[0] if argv else ""
    event = {{"schema": events.SCHEMA,
              "cohort_id": os.environ.get("MYLANG_M3_COHORT", ""),
              "attempt_id": os.environ.get("MYLANG_M3_ATTEMPT", ""),
              "invocation_id": uuid.uuid4().hex,
              "command": command,
              "argv": argv,
              "cwd": os.getcwd(),
              "source_sha256": before,
              "compiler_sha256": COMPILER_SHA256,
              "started_monotonic_ns": started,
              "finished_monotonic_ns": finished,
              "exit_code": completed.returncode,
              "outcome": events.classify(completed.returncode, stderr, diagnostics, command),
              "diagnostic_codes": [diagnostic["code"] for diagnostic in diagnostics],
              "diagnostic_identities": [events.identity(diagnostic) for diagnostic in diagnostics],
              "source_stable": before == after,
              "initial_source_sha256": os.environ.get("MYLANG_M3_INITIAL_HASH", ""),
              "tool": KIND,
              "stdout_sha256": hashlib.sha256(completed.stdout).hexdigest(),
              "stderr_sha256": hashlib.sha256(completed.stderr).hexdigest()}}
    if log_path:
        append(log_path, event)
    sys.stdout.buffer.write(completed.stdout)
    sys.stdout.buffer.flush()
    sys.stderr.buffer.write(completed.stderr)
    sys.stderr.buffer.flush()
    return completed.returncode


if __name__ == "__main__":
    sys.exit(main())
'''

WORKSPACE_NOTE = """# Working copy

- `app/` is the project you are changing. Its public description is
  `app/project.json`; that description is the **active project** for this
  session, and the environment variable `MYLANG_M3_PROJECT` points at it.
- `bin/` holds the frozen tools: `bin/mylang` is the compiler, `bin/project` is
  the project launcher, and the arm's command syntax is in `request.md`.
- `docs/` is the mylang language and tooling documentation.
- `.m3/` is the coordinator's bookkeeping (caches, reports, ledgers). Do not edit
  it; it is not part of your submission.

The active project's entry and verification manifest are named *in the
description*, with paths relative to the description's directory. The working
directory you start in is not the project root, and the correct selection must
work from anywhere.
"""


def shim_source(kind: str, real: Path, coordinator: Path, compiler_sha256: str) -> str:
    return SHIM.format(kind=kind, real=str(real), coordinator=str(coordinator),
                       compiler_sha256=compiler_sha256)


def inventory(root: Path) -> tuple[str, dict[str, str]]:
    entries: dict[str, str] = {}
    for path in sorted(root.rglob("*")):
        if not path.is_file() or any(part in ("__pycache__", ".cache", ".mylang-cache") for part in path.parts):
            continue
        entries[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    digest = hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return digest, entries


def apply_mutation(app_directory: Path, mutation: dict) -> dict:
    """Apply one seeded regression by exact, unique substitution."""
    target = app_directory / mutation["file"]
    if not target.is_file():
        raise SystemExit(f"mutation target is missing: {target}")
    text = target.read_text()
    find = mutation["find"]
    occurrences = text.count(find)
    if occurrences != 1:
        raise SystemExit(f"mutation matches {occurrences} times in {target}; one exact site is required")
    updated = text.replace(find, mutation["replace"])
    target.write_text(updated)
    return {"file": mutation["file"], "find_sha256": hashlib.sha256(find.encode()).hexdigest(),
            "replace_sha256": hashlib.sha256(mutation["replace"].encode()).hexdigest(),
            "occurrences": occurrences}


def copy_docs(destination: Path, repo: Path) -> list[str]:
    """The language documentation both arms receive: language and tooling pages."""
    destination.mkdir(parents=True, exist_ok=True)
    copied: list[str] = []
    sources = sorted((repo / "docs").glob("*.md"))
    sources += sorted((repo / "docs" / "tooling").glob("*.md"))
    workflow = repo / "docs" / "experiments" / "project-workflow.md"
    if workflow.is_file():
        sources.append(workflow)
    for source in sources:
        target = destination / source.relative_to(repo / "docs")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        copied.append(target.relative_to(destination).as_posix())
    return copied


def build(root: Path, *, cohort_id: str, arm: str, case: dict, app_snapshot: Path,
          tools: Path, launcher: Path, request_text: str, docs_repo: Path) -> dict:
    """Materialize one session's workspace. An existing destination is refused."""
    if root.exists():
        raise SystemExit(f"workspace already exists: {root} — a fresh copy is required per session")
    app = root / "app"
    shutil.copytree(app_snapshot, app, ignore=IGNORE)
    mutation_evidence = None
    if case.get("mutation"):
        mutation_evidence = apply_mutation(app, case["mutation"])
    bin_directory = root / "bin"
    bin_directory.mkdir(parents=True)
    app_bin = app / "bin"
    app_bin.mkdir(parents=True, exist_ok=True)
    identities = json.loads((tools / "identity.json").read_text())
    compiler = tools / "bin" / "mylang"
    shims = {"mylang": compiler}
    host = identities["tools"].get("mylang-io") or {}
    if host.get("present"):
        shims["mylang-io"] = tools / "bin" / "mylang-io"
    for kind, real in shims.items():
        source = shim_source(kind, real, tools, identities["tools"][kind]["sha256"])
        for directory in (bin_directory, app_bin):
            path = directory / kind
            path.write_text(source)
            path.chmod(0o755)
    shutil.copy2(launcher, bin_directory / "project")
    (bin_directory / "project").chmod(0o755)
    (root / "request.md").write_text(request_text)
    (root / "WORKSPACE.md").write_text(WORKSPACE_NOTE)
    documents = copy_docs(root / "docs", docs_repo)
    ledger = root / ".m3"
    for name in ("cache", "reports"):
        (ledger / name).mkdir(parents=True, exist_ok=True)
    before, entries = inventory(app)
    environment = {
        "MYLANG_M3_ARM": arm,
        "MYLANG_M3_PROJECT": str(app / "project.json"),
        "MYLANG_M3_TOOLS": str(tools),
        "MYLANG_M3_CACHE": str(ledger / "cache"),
        "MYLANG_M3_REPORTS": str(ledger / "reports"),
        "MYLANG_M3_RESOLUTION_LOG": str(ledger / "resolution.jsonl"),
        "MYLANG_EVENT_LOG": str(ledger / "events.jsonl"),
        "MYLANG_M3_APP": str(app),
        "MYLANG_M3_COHORT": cohort_id,
        "MYLANG_M3_ATTEMPT": f"{arm}/{case['id']}/0",
        "MYLANG_M3_INITIAL_HASH": before,
        # Every cache root lives outside the application source tree: a check
        # must not look like an edit to the coordinator's inventory.
        "MYLANG_FRONTEND_CACHE": str(ledger / "cache" / "frontend"),
        "XDG_CACHE_HOME": str(ledger / "cache" / "xdg"),
    }
    (ledger / "environment.json").write_text(json.dumps(environment, indent=2) + "\n")
    return {"root": str(root), "app": str(app), "environment": environment,
            "initial_source_sha256": before, "source_files": len(entries),
            "mutation": mutation_evidence, "docs": documents,
            "compiler_sha256": identities["tools"]["mylang"]["sha256"]}


def initial_working_directory(workspace: Path, case: dict) -> Path:
    """The session's starting directory: `app`, `app/tests`, `app/sexpr`, or `.`."""
    relative = case.get("working_directory", "app")
    candidate = (workspace / relative).resolve()
    if not candidate.is_dir():
        raise SystemExit(f"case {case['id']}: initial working directory {relative!r} does not exist")
    return candidate


def seal(app_directory: Path, destination: Path) -> str:
    """Copy the candidate source to an immutable snapshot and hash the inventory."""
    shutil.copytree(app_directory, destination, ignore=IGNORE)
    digest, _ = inventory(destination)
    return digest


def now() -> str:
    return datetime.now(timezone.utc).isoformat()
