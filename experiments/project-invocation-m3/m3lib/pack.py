#!/usr/bin/env python3
"""The frozen pack: tools, application snapshots, descriptions and public manifests.

An M3 session must be reproducible from bytes that no live repository can move
underneath it. This module copies the chosen compiler, the workflow scripts and
the two candidate applications into coordinator storage, records a content hash
for every file, and refuses to silently replace a snapshot that already exists
with different bytes. A frozen pack is the input to `preflight`, `freeze` and
`run`; changing one is changing the cohort identity.

Nothing here runs a participant command; the launcher does that, and it reads
only the snapshot this module produced.
"""

from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
M3 = HERE.parent
REPO = M3.parents[1]
TOOLS = M3 / "pack" / "tools"
APPS = M3 / "pack" / "apps"

IGNORED = ("__pycache__", ".mylang-cache", ".cache", ".zig-cache", "zig-out", ".git", "_verify")

# The two candidate applications, named by the runbook. `include` is the
# snapshot's file set: the sources, the tests and the documentation a
# participant needs, and nothing that is a build artifact. `host` is an
# additional frozen tool the application's own checks must invoke explicitly.
APP_SPECS: dict[str, dict] = {
    "sexpr-port": {
        "source": REPO / "experiments" / "sexpr-port",
        "include": ("main.my", "sexpr/*.my", "tests/*.my", "CONTRACT.md", "README.md"),
        "entry": "main.my",
        "manifest": "verify.json",
        "host": None,
        "description": (
            "The mylang port of the EDA S-expression reader: `sexpr/` holds the "
            "tokenizer, parser, printer and AST, `tests/` holds the guest suite and "
            "`main.my` is the CLI."
        ),
    },
    "planner": {
        "source": REPO / "experiments" / "application_comparison" / "baselines" / "planner" / "my",
        "include": ("*.my", "README.md", "test_cli.py", "stress_cli.py"),
        "entry": "main.my",
        "manifest": "verify.json",
        # The byte-I/O host: the planner reads one JSON request on stdin and
        # writes one response on stdout, so its checks must run through it.
        "host": "mylang-io",
        "description": (
            "The workflow dependency planner: `main.my` plus json/schema/planner/"
            "output modules, driven as a byte-I/O program that reads one JSON "
            "request on stdin and writes one response on stdout."
        ),
    },
}

# Frozen tools: the compiler that runs the applications, its QBE backend and the
# byte-I/O host. `optional` tools are recorded when present and reported when
# absent instead of failing the whole pack.
TOOL_SPECS = (
    {"name": "mylang", "source": REPO / "zig-out" / "bin" / "mylang", "optional": False},
    {"name": "qbe", "source": REPO / "zig-out" / "bin" / "qbe", "optional": False},
    {"name": "mylang-io", "source": REPO / "zig-out" / "bin" / "mylang-io", "optional": True},
)

# The workflow scripts the launcher drives. They are vendored so that editing
# `scripts/` in the working checkout cannot change a running cohort.
SCRIPT_FILES = ("project.py", "navigate.py", "verify.py")
SCRIPT_TREES = ("verification",)


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_hashes(root: Path) -> dict[str, str]:
    """Relative path -> sha256 for every regular file under `root`."""
    entries: dict[str, str] = {}
    for path in sorted(root.rglob("*")):
        if not path.is_file() or any(part in IGNORED for part in path.parts):
            continue
        entries[path.relative_to(root).as_posix()] = file_hash(path)
    return entries


def tree_digest(entries: dict[str, str]) -> str:
    return hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def write_once(path: Path, content: str) -> None:
    """Write a pack file, refusing to change bytes an existing cohort may have hashed."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and path.read_text() != content:
        raise SystemExit(f"frozen pack file already exists with different content: {path}")
    path.write_text(content)


def copy_file_once(source: Path, destination: Path) -> None:
    if destination.is_file():
        if file_hash(destination) != file_hash(source):
            raise SystemExit(f"frozen pack file already exists with different bytes: {destination}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def materialize_tools() -> dict:
    """Copy the compiler, backend, host and workflow scripts into `pack/tools/`."""
    bin_directory = TOOLS / "bin"
    bin_directory.mkdir(parents=True, exist_ok=True)
    tools: dict[str, dict] = {}
    for spec in TOOL_SPECS:
        source = spec["source"]
        record = {"name": spec["name"], "source": str(source), "optional": spec["optional"]}
        if not source.is_file():
            record.update(present=False, sha256=None,
                          note="absent in the checkout; a run that needs it must stop before participants")
            tools[spec["name"]] = record
            continue
        destination = bin_directory / spec["name"]
        copy_file_once(source, destination)
        destination.chmod(0o755)
        record.update(present=True, path=f"bin/{spec['name']}", sha256=file_hash(destination))
        tools[spec["name"]] = record
    scripts = TOOLS / "scripts"
    script_records: dict[str, str] = {}
    for name in SCRIPT_FILES:
        source = REPO / "scripts" / name
        if not source.is_file():
            raise SystemExit(f"workflow script missing from the checkout: {source}")
        copy_file_once(source, scripts / name)
        script_records[name] = file_hash(scripts / name)
    for tree in SCRIPT_TREES:
        for source in sorted((REPO / "scripts" / tree).rglob("*")):
            if not source.is_file() or any(part in IGNORED for part in source.parts):
                continue
            relative = source.relative_to(REPO / "scripts")
            copy_file_once(source, scripts / relative)
            script_records[relative.as_posix()] = file_hash(scripts / relative)
    # The event schema and parser are the M1 measurement module; M3 measures the
    # same unit (one compiler process) rather than inventing a second one. Its
    # identity is recorded so a cohort can prove which accounting it used.
    events_source = REPO / "experiments" / "diagnostic-feedback" / "events.py"
    copy_file_once(events_source, TOOLS / "events.py")
    record = {
        "version": "m3-tools-v1",
        "captured_utc": now(),
        "tools": tools,
        "scripts": script_records,
        "scripts_digest": tree_digest(script_records),
        "events_module": {"path": "events.py", "sha256": file_hash(TOOLS / "events.py"),
                          "source": str(events_source)},
    }
    _record(TOOLS / "identity.json", record)
    return record


def _record(path: Path, record: dict) -> None:
    """Write an identity record; an equal identity (ignoring its capture time) is a no-op.

    Re-materializing the same checkout must be idempotent — the record's own
    timestamp is not part of what it identifies — while different bytes under an
    existing identity are fatal.
    """
    def stable(value: dict) -> dict:
        return {key: item for key, item in value.items() if key != "captured_utc"}

    if path.is_file():
        existing = json.loads(path.read_text())
        if stable(existing) != stable(record):
            raise SystemExit(
                f"{path} already records a different identity; a frozen pack is not rewritten in place.\n"
                "Delete the snapshot deliberately (only before any cohort has been frozen) if this "
                "is a new preflight."
            )
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(record, indent=2) + "\n")


# Files the experiment authors into a snapshot rather than copying from the
# application: the public fixtures the public manifest names, and — where an
# application's own launcher resolves a host by search — a launcher that names
# the frozen host explicitly instead. Both arms receive these identical bytes.
AUTHORED_FILES: dict[str, dict[str, str]] = {
    "sexpr-port": {
        "fixtures/public/scaling.sexp": "(dims (width 2.5mm) (height 10mil) (tol 5%))\n",
        "fixtures/public/render.sexp": "(cap-0402 100nF 10% 4.7k 2.5)\n",
        "fixtures/public/nesting.sexp": "(a () (b ()))\n",
        "fixtures/public/escapes.sexp": '(note "trailing backslash \\\\")\n',
    },
    "planner": {
        "bin/planner-checks": """#!/bin/sh
# Run the planner's own contract suite against the frozen byte-I/O host.
# Both arms get this identical launcher: the host is named explicitly so a
# checkout that happens to sit nearby can never be used instead.
set -eu
cd "$(dirname "$0")/.."
MYLANG_IO="$M3_FROZEN_IO" exec /usr/bin/python3 -B test_cli.py
""",
    },
}

# Public checks whose expected output is measured from the pristine reference
# snapshot with the frozen compiler. The value is part of the frozen manifest:
# preflight re-measures it, and a change is a different cohort identity.
MEASURED_PUBLIC_CHECKS: dict[str, list[dict]] = {
    "sexpr-port": [
        {"id": "cli-scaling", "args": ["main.my", "--", "fixtures/public/scaling.sexp"], "timeout": 300},
        {"id": "cli-render", "args": ["main.my", "--", "fixtures/public/render.sexp", "--render"],
         "timeout": 300},
        {"id": "cli-nesting", "args": ["main.my", "--", "fixtures/public/nesting.sexp", "--render"],
         "timeout": 300},
        {"id": "cli-escapes", "args": ["main.my", "--", "fixtures/public/escapes.sexp", "--render"],
         "timeout": 300},
    ],
}


def run_pristine(app: str, snapshot: Path, args: list[str]) -> dict:
    """Run the frozen compiler over a scratch copy of the pristine snapshot.

    The reference oracle is measured in scratch space: compiling writes cache
    directories into the working directory, and the frozen snapshot's bytes are
    an identity that nothing may mutate.
    """
    import subprocess
    compiler = TOOLS / "bin" / "mylang"
    if not compiler.is_file():
        raise SystemExit("the frozen compiler is not materialized yet")
    scratch = M3 / "work" / "materialize" / app
    if scratch.exists():
        shutil.rmtree(scratch)
    shutil.copytree(snapshot, scratch, ignore=shutil.ignore_patterns("__pycache__", ".mylang-cache", ".cache"))
    environment = dict(os.environ)
    environment["MYLANG_MEMORY_LIMIT"] = "2G"
    completed = subprocess.run([str(compiler), "run", *args], cwd=scratch, capture_output=True,
                               text=True, timeout=600, env=environment)
    shutil.rmtree(scratch, ignore_errors=True)
    return {"argv": args, "exit": completed.returncode, "stdout": completed.stdout,
            "stderr": completed.stderr[-400:]}


def app_public_manifest(app: str, snapshot: Path) -> dict:
    """The public verification manifest authored for one application.

    It is a genuine `verify.py` version 1 manifest: real step keys, real kinds
    and real commands. The compiler is named as `bin/mylang` because every
    workspace and every grading staging directory installs the frozen compiler
    there; the workload is therefore identical in both arms and in grading.
    """
    if app == "sexpr-port":
        steps = [{"id": "guest-suite", "kind": "test", "timeout": 900,
                  "commands": [["bin/mylang", "test", "tests"]]}]
        for check in MEASURED_PUBLIC_CHECKS["sexpr-port"]:
            measured = run_pristine(app, snapshot, check["args"])
            if measured["exit"] != 0:
                raise SystemExit(f"the pristine reference fails {check['id']}: {measured['stderr']}")
            steps.append({"id": check["id"], "kind": "test", "timeout": check["timeout"],
                          "expect_stdout": measured["stdout"],
                          "commands": [["bin/mylang", "run", *check["args"]]]})
        return {"version": 1, "steps": steps}
    if app == "planner":
        # The planner is a byte-I/O application: its checks run through the
        # frozen host explicitly, via the authored launcher, because the
        # application's own test driver searches for a host if not told.
        return {
            "version": 1,
            "steps": [
                {"id": "cli-contract", "kind": "test", "timeout": 600,
                 "commands": [["bin/planner-checks"]]},
            ],
        }
    raise SystemExit(f"no public manifest authored for {app!r}")


APP_NOTE = """# Frozen M3 application: {app}

This directory is a byte-for-byte snapshot taken by the M3 coordinator, plus the
public project description (`project.json`) and the public verification manifest
(`verify.json`) authored for the experiment. It is read-only material: neither
arm may edit it, and no participant session ever writes here.

{description}

- entry: `{entry}` (relative to this directory)
- manifest: `{manifest}` (relative to this directory)
- snapshot digest: `{digest}`

The description is the *active project*: both arms read it through the same
environment variable, so root/entry/manifest selection does not depend on the
session's current working directory.
"""


def materialize_app(app: str) -> dict:
    """Snapshot one application plus its description and public manifest."""
    spec = APP_SPECS[app]
    source = spec["source"]
    if not source.is_dir():
        raise SystemExit(f"application source is missing: {source}")
    root = APPS / app
    snapshot = root / "snapshot"
    files: list[Path] = []
    for pattern in spec["include"]:
        files.extend(sorted(source.glob(pattern)))
    if not files:
        raise SystemExit(f"application snapshot matched no files under {source}")
    for path in files:
        relative = path.relative_to(source)
        copy_file_once(path, snapshot / relative)
    for relative, content in AUTHORED_FILES.get(app, {}).items():
        write_once(snapshot / relative, content)
        if relative.startswith("bin/"):
            (snapshot / relative).chmod(0o755)
    description = {"version": "m3-project-description-v1", "name": app,
                   "entry": spec["entry"], "manifest": spec["manifest"],
                   "host": spec["host"], "note": spec["description"]}
    write_once(root / "project.json", json.dumps(description, indent=2) + "\n")
    # The description the launcher reads lives beside the sources it describes,
    # so relative entry/manifest resolution is anchored at the application root.
    write_once(snapshot / "project.json", json.dumps(description, indent=2) + "\n")
    write_once(snapshot / "verify.json", json.dumps(app_public_manifest(app, snapshot), indent=2) + "\n")
    entries = tree_hashes(snapshot)
    record = {
        "version": "m3-app-snapshot-v1",
        "app": app,
        "captured_utc": now(),
        "source": str(source),
        "files": {name: {"sha256": value} for name, value in entries.items()},
        "digest": tree_digest(entries),
        "entry": spec["entry"],
        "manifest": spec["manifest"],
        "host": spec["host"],
    }
    _record(root / "snapshot.json", record)
    write_once(root / "SNAPSHOT.md", APP_NOTE.format(app=app, description=spec["description"],
                                                      entry=spec["entry"], manifest=spec["manifest"],
                                                      digest=record["digest"]))
    return record


def load_app(app: str) -> dict:
    path = APPS / app / "snapshot.json"
    if not path.is_file():
        raise SystemExit(f"application {app!r} has not been materialized; run `m3.py materialize` first")
    return json.loads(path.read_text())


def verify_app(app: str) -> dict:
    """Re-hash a snapshot and report every deviation from its recorded identity."""
    record = load_app(app)
    snapshot = APPS / app / "snapshot"
    observed = tree_hashes(snapshot)
    expected = {name: value["sha256"] for name, value in record["files"].items()}
    missing = sorted(set(expected) - set(observed))
    added = sorted(set(observed) - set(expected))
    changed = sorted(name for name in set(observed) & set(expected) if observed[name] != expected[name])
    return {"app": app, "ok": not (missing or added or changed), "missing": missing, "added": added,
            "changed": changed, "digest": record["digest"],
            "observed_digest": tree_digest(observed)}


def load_tools() -> dict:
    path = TOOLS / "identity.json"
    if not path.is_file():
        raise SystemExit("frozen tools have not been materialized; run `m3.py materialize` first")
    return json.loads(path.read_text())


def tool_path(name: str) -> Path:
    return TOOLS / "bin" / name
