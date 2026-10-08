#!/usr/bin/env python3
"""Strict S3 fuzz qualification; launch through scripts/build-slot.sh build.

Extend the S2 qualification accounting with explicit oracle identity, retained
sources, raw native outcomes and one append-only command journal per fresh run.
"""
import argparse
import base64
from contextlib import redirect_stdout
import hashlib
import importlib.util
import json
import locale
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[4]
S2_WRAPPER = ROOT / "experiments/new-core-s2-20261005/wave-a/integration/fuzz_qualification.py"
spec = importlib.util.spec_from_file_location("s2_qualification", S2_WRAPPER)
s2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s2)
HARNESSES = {
    **s2.HARNESSES,
    "text": "experiments/new-core-s3-20261006/wave-b/s3-t1/fuzz_text.py",
}
MODES = {"debug", "release", "verify"}


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def oracle(path):
    path = path.resolve()
    if not path.is_file() or not os.access(path, os.X_OK):
        raise ValueError(f"oracle must be an executable file: {path}")
    return {"path": str(path), "sha256": digest(path)}


def encoded(value):
    return base64.b64encode(value or b"").decode("ascii")


class Monitor(s2.Monitor):
    def __init__(self, args, original_run):
        super().__init__(args, original_run)
        self.outcomes = {}
        self.comparisons = 0
        self.retained = {}
        self.journal = (args.evidence / "commands.jsonl").open("x")
        self.command_count = 0

    def save(self, source):
        if source not in self.retained:
            destination = self.args.evidence / "sources" / f"{source.stem}-{digest(source)[:12]}.my"
            shutil.copyfile(source, destination)
            self.retained[source] = str(destination)

    def native(self, source, role, argv, result):
        self.native_runs += 1
        stderr = result.stderr or b""
        if b"leakcheck" in stderr or re.search(rb"leak: \d+ blocks live", stderr):
            self.fail(source, "leak", argv, returncode=result.returncode, stderr_b64=encoded(stderr))
        if b"R_CORE_FACT" in stderr:
            self.fail(source, "fact_failure", argv, returncode=result.returncode, stderr_b64=encoded(stderr))
        if result.returncode > 6:
            self.fail(source, "unexpected_native_exit", argv, returncode=result.returncode, stderr_b64=encoded(stderr))
        trap = re.search(rb"\bR_[A-Z_0-9]+\b", stderr)
        outcome = {"status": result.returncode, "stdout_b64": encoded(result.stdout),
                   "trap": trap.group().decode("ascii") if trap else ""}
        key = (source, tuple(argv[1:]))
        outcomes = self.outcomes.setdefault(key, {})
        if role == "old":
            if "old" in outcomes and outcomes["old"] != outcome:
                self.fail(source, "old_nondeterminism", argv, expected=outcomes["old"], actual=outcome)
        else:
            if "old" not in outcomes:
                self.fail(source, "missing_native_oracle", argv)
            if outcomes["old"] != outcome:
                self.fail(source, "native_outcome_mismatch", argv, expected=outcomes["old"], actual=outcome)
            self.comparisons += 1
        outcomes[role] = outcome

    def run(self, argv, *arguments, **options):
        argv = list(map(str, argv))
        building = len(argv) > 2 and argv[1] == "build"
        if building:
            compiler = Path(argv[0]).resolve()
            source = Path(argv[2]).resolve()
            if compiler == self.args.old:
                role = "old"
            elif compiler == self.args.new:
                role = "verify" if "--verify-facts" in argv else "release" if "--release" in argv else "debug"
            else:
                self.fail(source, "unexpected_compiler", argv)
            if source not in self.cases:
                self.cases[source] = {"old": False, "core": set()}
                self.save(source)
                if len(self.cases) % 25 == 0:
                    print(f"qualification progress: {self.args.kind}: seen={len(self.cases)} elapsed={time.monotonic() - self.started:.2f}s", flush=True)
            if "-o" not in argv:
                self.fail(source, "missing_build_output", argv)
            output = str(Path(argv[argv.index("-o") + 1]).resolve())
            if "--cache-dir" not in argv:
                argv += ["--cache-dir", str(self.args.cache_root / f"frontend-{'old' if role == 'old' else 'core'}")]
        else:
            executable = self.executables.get(str(Path(argv[0]).resolve()))
            if executable is None:
                self.fail(None, "unknown_native_executable", argv)
            source, role = executable
        timeout = 60 if building else 30
        options["timeout"] = min(options.get("timeout") or timeout, timeout)
        # Harnesses request text mode. Capture bytes first so newline decoding
        # cannot hide a stdout mismatch, then return their expected text result.
        text_flag = options.pop("text", False)
        text_mode = options.pop("universal_newlines", False) or text_flag
        encoding = options.pop("encoding", None)
        errors = options.pop("errors", None)
        text_mode = text_mode or encoding is not None or errors is not None
        began = time.monotonic()
        try:
            result = self.original_run(argv, *arguments, **options)
        except subprocess.TimeoutExpired as error:
            self.fail(source, "compile_timeout" if building else "native_timeout", argv,
                      timeout=options["timeout"], stdout_b64=encoded(error.stdout), stderr_b64=encoded(error.stderr))
        except OSError as error:
            self.fail(source, "child_launch_failed", argv, reason=str(error))
        self.command_count += 1
        self.journal.write(json.dumps({"command_id": self.command_count, "command": argv,
                                      "source": self.retained.get(source), "role": role,
                                      "building": building, "status": result.returncode,
                                      "stdout_b64": encoded(result.stdout), "stderr_b64": encoded(result.stderr),
                                      "elapsed_seconds": time.monotonic() - began}) + "\n")
        self.journal.flush()
        if result.returncode < 0:
            self.fail(source, "compiler_crash" if building else "native_crash", argv, returncode=result.returncode)
        if building:
            if result.returncode:
                kind = "old_rejected" if role == "old" else "core_refused" if b"E_CORE_UNSUPPORTED" in (result.stderr or b"") else "core_build_failed"
                self.fail(source, kind, argv, returncode=result.returncode, stderr_b64=encoded(result.stderr))
            self.executables[output] = (source, role)
            if role == "old":
                self.cases[source]["old"] = True
            else:
                self.cases[source]["core"].add(role)
        else:
            self.native(source, role, argv, result)
        if text_mode:
            def decode(value):
                return value.decode(encoding or locale.getpreferredencoding(False), errors or "strict").replace("\r\n", "\n").replace("\r", "\n") if value is not None else None
            return subprocess.CompletedProcess(argv, result.returncode, decode(result.stdout), decode(result.stderr))
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", choices=HARNESSES, required=True)
    parser.add_argument("--harness", type=Path, help="Override this kind's generator")
    parser.add_argument("--old", type=Path, required=True, help="Explicit qualified old oracle")
    parser.add_argument("--new", type=Path, required=True, help="Explicit qualified integrated new oracle")
    parser.add_argument("--cases", type=int, default=200)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--cache-root", type=Path, required=True)
    args = parser.parse_args()
    if args.cases <= 0:
        parser.error("--cases must be positive")
    args.old, args.new = args.old.resolve(), args.new.resolve()
    try:
        identities = {"old": oracle(args.old), "new": oracle(args.new)}
        if os.path.samefile(args.old, args.new):
            raise ValueError("--old and --new must name distinct oracle files")
    except (OSError, ValueError) as error:
        parser.error(str(error))
    args.evidence, args.cache_root = args.evidence.resolve(), args.cache_root.resolve()
    if args.evidence.exists() or args.cache_root.exists():
        parser.error("evidence and cache roots must both be fresh; previous runs cannot be reused")
    if set(os.sched_getaffinity(0)) & {2, 3, 10, 11}:
        parser.error("launch through scripts/build-slot.sh build; reserved CPUs must be excluded")
    args.evidence.mkdir(parents=True)
    args.cache_root.mkdir(parents=True)
    (args.evidence / "sources").mkdir()
    for directory in ("tmp", "zig", "sources"):
        (args.cache_root / directory).mkdir()
    os.environ.update(TMPDIR=str(args.cache_root / "tmp"),
                      ZIG_LOCAL_CACHE_DIR=str(args.cache_root / "zig"),
                      ZIG_GLOBAL_CACHE_DIR="/home/epentland/ai/canopy/.zig-global-cache",
                      MYL_CORE_LEAKCHECK="1")
    harness_path = args.harness.resolve() if args.harness else ROOT / HARNESSES[args.kind]
    spec = importlib.util.spec_from_file_location("s3_fuzz_harness", harness_path)
    harness = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(harness)
    original_run, original_argv = subprocess.run, sys.argv
    monitor = Monitor(args, original_run)
    sys.argv = [str(harness_path), "--cases", str(args.cases), "--seed", str(args.seed),
                "--keep", str(args.cache_root / "sources"), "--mylang", str(args.old), "--core", str(args.new)]
    if args.kind in ("s1", "rebinding", "iteration"):
        sys.argv += ["--features", "all" if args.kind == "s1" else "mut,records,alias"]
    output = s2.Tee(sys.stdout)
    status, error = 1, None
    subprocess.run = monitor.run
    try:
        with redirect_stdout(output):
            status = harness.main()
    except (Exception, SystemExit) as failure:
        error = f"{type(failure).__name__}: {failure}"
        print(f"qualification failed: {error}", file=sys.stderr)
    finally:
        subprocess.run, sys.argv = original_run, original_argv
        monitor.journal.close()
    report = s2.qualify(args, monitor, status, output.getvalue(), error)
    arguments_per_case = 3 if args.kind == "rc" else 5
    native_complete = all(sum(source == case for source, _ in monitor.outcomes) == arguments_per_case
                          for case in monitor.cases) and all(
        set(outcomes) == {"old", *MODES} for outcomes in monitor.outcomes.values())
    try:
        oracle_unchanged = all(digest(Path(identity["path"])) == identity["sha256"] for identity in identities.values())
    except OSError:
        oracle_unchanged = False
    report.update(oracles=identities, oracle_unchanged=oracle_unchanged,
                  harness_path=str(harness_path), harness_sha256=digest(harness_path),
                  native_comparisons=monitor.comparisons, native_complete=native_complete,
                  command_count=monitor.command_count, saved_sources=str(args.evidence / "sources"))
    report["qualified"] = report["qualified"] and native_complete and oracle_unchanged and monitor.comparisons == report["comparisons_expected"]
    (args.evidence / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    (args.evidence / "harness.txt").write_text(output.getvalue())
    print("qualification " + json.dumps({key: report[key] for key in ("kind", "qualified", "accepted", "native_comparisons", "elapsed_seconds")}))
    return 0 if report["qualified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
