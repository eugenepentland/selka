#!/usr/bin/env python3
"""Harness for the four Lox ports described in ../SPEC.md.

Correctness:
  conformance  run the book's test corpus against one binary (per engine, optional --gc-stress)
  check        run the benchmark scripts, compare stdout with the oracle and --stats across binaries
  expected     regenerate bench/expected/ with the clox oracle

Bookkeeping:
  toolchains   print how {mylang} {zig} {cargo} {go} resolve
  build        build one port's profile into a cache directory and print the binary path
  loc          count a port's source and test lines

Measurement subcommands (runtime, compile, tests) live in measure.py.
"""
from __future__ import annotations

import argparse
import concurrent.futures as futures
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH_ROOT = HERE.parent                       # benchmarks/lox
CORPUS = BENCH_ROOT / "corpus" / "test"
SCRIPTS = BENCH_ROOT / "bench" / "scripts"
EXPECTED = BENCH_ROOT / "bench" / "expected"
SIZES = BENCH_ROOT / "bench" / "sizes.json"
PORTS = BENCH_ROOT / "ports"


def repo_root() -> Path:
    """The mylang checkout that owns .tmp/lox-bench (this file may live in a worktree under it)."""
    for parent in HERE.parents:
        if (parent / ".tmp" / "lox-bench").is_dir():
            return parent
    raise SystemExit("cannot find the mylang checkout containing .tmp/lox-bench")


def lox_bench_dir() -> Path:
    return repo_root() / ".tmp" / "lox-bench"


# --------------------------------------------------------------------------- toolchains

def toolchains() -> dict[str, str]:
    home = Path.home()
    defaults = {
        # Re-pinned 2026-09-23 to a ReleaseFast build of main 26f16e90 (the Lox-port bug fixes);
        # the first ports were written against mylang-install (perf/schematic-integration).
        "mylang": str(lox_bench_dir() / "mylang-main-26f16e90" / "bin" / "mylang"),
        "zig": shutil.which("zig") or str(home / ".local" / "bin" / "zig"),
        "cargo": shutil.which("cargo") or str(home / ".cargo" / "bin" / "cargo"),
        "go": shutil.which("go") or str(home / ".local" / "bin" / "go"),
    }
    return {name: os.environ.get(f"LOX_BENCH_{name.upper()}", path) for name, path in defaults.items()}


def oracle() -> Path:
    return lox_bench_dir() / "craftinginterpreters" / "build" / "clox-oracle"


def substitute(value: str, cache: Path, port_dir: Path) -> str:
    mapping = {"cache": str(cache), "port": str(port_dir), **toolchains()}
    return re.sub(r"\{(\w+)\}", lambda m: mapping.get(m.group(1), m.group(0)), value)


def load_port(port: str) -> tuple[Path, dict]:
    port_dir = PORTS / port
    config = json.loads((port_dir / "bench.json").read_text())
    return port_dir, config


def port_env(config: dict, cache: Path, port_dir: Path) -> dict[str, str]:
    env = dict(os.environ)
    cargo_bin = str(Path(toolchains()["cargo"]).parent)
    env["PATH"] = cargo_bin + os.pathsep + env.get("PATH", "")
    env.setdefault("GOTOOLCHAIN", "local")
    # /tmp is a small quota'd tmpfs on this machine; build scratch goes to disk instead.
    scratch = lox_bench_dir() / "tmp"
    scratch.mkdir(parents=True, exist_ok=True)
    env["TMPDIR"] = env["GOTMPDIR"] = str(scratch)
    for key, value in config.get("env", {}).items():
        env[key] = substitute(value, cache, port_dir)
    return env


def build_port(port: str, profile: str, cache: Path) -> Path:
    port_dir, config = load_port(port)
    spec = config["profiles"][profile]
    cache.mkdir(parents=True, exist_ok=True)
    command = [substitute(part, cache, port_dir) for part in spec["build"]]
    result = subprocess.run(command, cwd=port_dir, env=port_env(config, cache, port_dir))
    if result.returncode != 0:
        raise SystemExit(f"build failed ({result.returncode}): {' '.join(command)}")
    binary = Path(substitute(spec["binary"], cache, port_dir))
    if not binary.is_absolute():
        binary = port_dir / binary
    if not binary.exists():
        raise SystemExit(f"build succeeded but {binary} does not exist")
    return binary


# --------------------------------------------------------------------------- conformance

EXPECT_OUTPUT = re.compile(r"// expect: ?(.*)")
EXPECT_ERROR = re.compile(r"// (Error.*)")
ERROR_LINE = re.compile(r"// \[((java|c) )?line (\d+)\] (Error.*)")
EXPECT_RUNTIME = re.compile(r"// expect runtime error: (.+)")
SYNTAX_ERROR = re.compile(r"\[.*line (\d+)\] (Error.+)")
STACK_TRACE = re.compile(r"\[line (\d+)\]")
NON_TEST = re.compile(r"// nontest")

SKIP_ALWAYS = ("scanning/", "expressions/")
SKIP_TREE = (
    "limit/loop_too_large.lox",
    "limit/no_reuse_constants.lox",
    "limit/too_many_constants.lox",
    "limit/too_many_locals.lox",
    "limit/too_many_upvalues.lox",
)


@dataclass
class Expectations:
    output: list[tuple[int, str]] = field(default_factory=list)
    errors: set[str] = field(default_factory=set)
    runtime_error: str | None = None
    runtime_line: int = 0
    exit_code: int = 0


def skipped(rel: str, engine: str) -> bool:
    if rel.startswith(SKIP_ALWAYS):
        return True
    return engine == "tree" and rel in SKIP_TREE


def parse_expectations(path: Path, language: str) -> Expectations | None:
    exp = Expectations()
    for number, line in enumerate(path.read_text(encoding="utf-8", errors="surrogateescape").split("\n"), 1):
        if NON_TEST.search(line):
            return None
        if m := EXPECT_OUTPUT.search(line):
            exp.output.append((number, m.group(1)))
            continue
        if m := EXPECT_ERROR.search(line):
            exp.errors.add(f"[{number}] {m.group(1)}")
            exp.exit_code = 65
            continue
        if m := ERROR_LINE.search(line):
            if m.group(2) is None or m.group(2) == language:
                exp.errors.add(f"[{m.group(3)}] {m.group(4)}")
                exp.exit_code = 65
            continue
        if m := EXPECT_RUNTIME.search(line):
            exp.runtime_line = number
            exp.runtime_error = m.group(1)
            exp.exit_code = 70
    return exp


def run_lox(binary: Path, args: list[str], script: Path, timeout: float = 60.0) -> subprocess.CompletedProcess:
    return subprocess.run([str(binary), *args, str(script)], capture_output=True, timeout=timeout)


def validate(exp: Expectations, proc: subprocess.CompletedProcess) -> list[str]:
    failures: list[str] = []
    out_lines = proc.stdout.decode("utf-8", "surrogateescape").splitlines()
    err_lines = proc.stderr.decode("utf-8", "surrogateescape").splitlines()

    if exp.runtime_error is not None:
        if len(err_lines) < 2:
            failures.append(f"expected runtime error {exp.runtime_error!r} and got: {err_lines}")
        else:
            if err_lines[0] != exp.runtime_error:
                failures.append(f"expected runtime error {exp.runtime_error!r} and got {err_lines[0]!r}")
            trace = next((m for l in err_lines[1:] if (m := STACK_TRACE.search(l))), None)
            if trace is None:
                failures.append(f"expected a stack trace and got {err_lines[1:]}")
            elif int(trace.group(1)) != exp.runtime_line:
                failures.append(f"expected runtime error on line {exp.runtime_line}, got line {trace.group(1)}")
    else:
        found: set[str] = set()
        for line in err_lines:
            if m := SYNTAX_ERROR.search(line):
                error = f"[{m.group(1)}] {m.group(2)}"
                if error in exp.errors:
                    found.add(error)
                else:
                    failures.append(f"unexpected error: {line}")
            elif line != "":
                failures.append(f"unexpected output on stderr: {line}")
        for missing in sorted(exp.errors - found):
            failures.append(f"missing expected error: {missing}")

    if proc.returncode != exp.exit_code:
        failures.append(f"expected exit {exp.exit_code}, got {proc.returncode}; stderr: {err_lines[:10]}")

    if out_lines and out_lines[-1] == "":
        out_lines.pop()
    for index, line in enumerate(out_lines):
        if index >= len(exp.output):
            failures.append(f"got output {line!r} when none was expected")
        elif exp.output[index][1] != line:
            failures.append(f"expected {exp.output[index][1]!r} (line {exp.output[index][0]}), got {line!r}")
    for number, text in exp.output[len(out_lines):]:
        failures.append(f"missing expected output {text!r} (line {number})")
    return failures


def conformance(binary: Path, engine: str, stress: bool, filt: str | None, jobs: int, verbose: bool) -> bool:
    language = "c" if engine == "vm" else "java"
    args = [f"--engine={engine}"] + (["--gc-stress"] if stress else [])
    tests = []
    for path in sorted(CORPUS.rglob("*.lox")):
        rel = path.relative_to(CORPUS).as_posix()
        if skipped(rel, engine) or (filt and filt not in rel):
            continue
        exp = parse_expectations(path, language)
        if exp is not None:
            tests.append((rel, path, exp))

    def one(item):
        rel, path, exp = item
        try:
            proc = run_lox(binary, args, path)
        except subprocess.TimeoutExpired:
            return rel, ["timed out after 60 s"]
        return rel, validate(exp, proc)

    failed = 0
    with futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        for rel, failures in pool.map(one, tests):
            if failures:
                failed += 1
                print(f"FAIL {rel}")
                for f in failures[: (50 if verbose else 5)]:
                    print(f"     {f}")
    mode = "gc-stress" if stress else "normal"
    print(f"conformance engine={engine} gc={mode}: {len(tests) - failed}/{len(tests)} passed")
    return failed == 0


# --------------------------------------------------------------------------- benchmark scripts

def sizes() -> dict[str, dict[str, int]]:
    return {k: v for k, v in json.loads(SIZES.read_text()).items() if not k.startswith("_")}


def sized_script(name: str, n: int, workdir: Path) -> Path:
    body = (SCRIPTS / f"{name}.lox").read_text()
    first, rest = body.split("\n", 1)
    assert first.startswith("var N = "), name
    out = workdir / f"{name}.{n}.lox"
    out.write_text(f"var N = {n};\n{rest}")
    return out


def expected_path(name: str, tier: str) -> Path:
    return EXPECTED / f"{name}.{tier}.out"


def regenerate_expected() -> None:
    EXPECTED.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for name, tiers in sizes().items():
            for tier, n in tiers.items():
                proc = run_lox(oracle(), [], sized_script(name, n, Path(tmp)), timeout=600)
                if proc.returncode != 0:
                    raise SystemExit(f"oracle failed on {name} {tier}: {proc.stderr.decode()}")
                expected_path(name, tier).write_bytes(proc.stdout)
                print(f"{name}.{tier}: {len(proc.stdout)} bytes")


STATS = re.compile(rb"^\[stats\] engine=(\w+) allocations=(\d+) collections=(\d+) freed=(\d+) live=(\d+)$", re.M)


def check(binaries: dict[str, Path], tier_names: list[str], stress_smoke: bool, filt: str | None, jobs: int) -> bool:
    runs = []  # (script, tier, engine, stress)
    for name, tiers in sizes().items():
        if filt and filt not in name:
            continue
        for tier in tier_names:
            engines = ["vm", "tree"] if tier == "smoke" else [tier]
            for engine in engines:
                runs.append((name, tier, engine, False))
                if tier == "smoke" and stress_smoke:
                    runs.append((name, tier, engine, True))

    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        workdir = Path(tmp)
        scripts = {(name, tier): sized_script(name, sizes()[name][tier], workdir) for name, tier, _, _ in runs}

        def one(job):
            (name, tier, engine, stress), (port, binary) = job
            args = [f"--engine={engine}", "--stats"] + (["--gc-stress"] if stress else [])
            try:
                proc = run_lox(binary, args, scripts[(name, tier)], timeout=900)
            except subprocess.TimeoutExpired:
                return job, None, "timeout"
            return job, proc, None

        jobs_list = [(run, item) for run in runs for item in binaries.items()]
        results: dict[tuple, dict[str, tuple]] = {}
        with futures.ThreadPoolExecutor(max_workers=jobs) as pool:
            for (run, (port, _)), proc, problem in pool.map(one, jobs_list):
                results.setdefault(run, {})[port] = (proc, problem)

    for run in runs:
        name, tier, engine, stress = run
        want = expected_path(name, tier).read_bytes()
        stats_seen = {}
        problems = []
        for port, (proc, problem) in sorted(results[run].items()):
            if problem:
                problems.append(f"{port}: {problem}")
                continue
            if proc.returncode != 0:
                problems.append(f"{port}: exit {proc.returncode}: {proc.stderr[-300:].decode(errors='replace')}")
            if proc.stdout != want:
                problems.append(f"{port}: stdout differs from oracle ({len(proc.stdout)} vs {len(want)} bytes)")
            m = STATS.findall(proc.stderr)
            if len(m) != 1:
                problems.append(f"{port}: expected one [stats] line on stderr")
            else:
                stats_seen[port] = tuple(x.decode() for x in m[0])
        if len(set(stats_seen.values())) > 1:
            problems.append("stats differ: " + "; ".join(f"{p}={s[1:]}" for p, s in stats_seen.items()))
        label = f"{name:16} {tier:5} {engine:4} {'stress' if stress else 'normal':6}"
        stat = next(iter(stats_seen.values()), None)
        summary = f"alloc={stat[1]} gc={stat[2]} freed={stat[3]} live={stat[4]}" if stat else ""
        if problems:
            ok = False
            print(f"FAIL {label} {summary}")
            for p in problems:
                print(f"     {p}")
        else:
            print(f"ok   {label} {summary}")
    return ok


# --------------------------------------------------------------------------- loc

SOURCE_SUFFIX = {"mylang": ".my", "zig": ".zig", "rust": ".rs", "go": ".go"}


def is_test_file(port: str, path: Path) -> bool:
    name = path.name
    return (port == "go" and name.endswith("_test.go")) or "test" in path.parts or name.startswith("test_") or name.endswith("_test" + path.suffix) or name.endswith("_tests" + path.suffix)


def loc(port: str) -> dict:
    port_dir = PORTS / port
    suffix = SOURCE_SUFFIX[port]
    totals = {"files": 0, "lines": 0, "nonblank": 0, "test_files": 0, "test_nonblank": 0}
    for path in sorted(port_dir.rglob(f"*{suffix}")):
        rel = path.relative_to(port_dir)
        if any(part.startswith(".") or part in ("target", "zig-out", "repros") for part in rel.parts):
            continue
        text = path.read_text(errors="replace").split("\n")
        nonblank = sum(1 for l in text if l.strip())
        totals["files"] += 1
        totals["lines"] += len(text)
        totals["nonblank"] += nonblank
        if is_test_file(port, rel):
            totals["test_files"] += 1
            totals["test_nonblank"] += nonblank
    totals["note"] = "test_* counts whole test files only; inline test blocks (Zig test, Rust #[cfg(test)]) are inside nonblank"
    return totals


# --------------------------------------------------------------------------- CLI

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("conformance", help="run the book's corpus against one binary")
    p.add_argument("--binary", type=Path, required=True)
    p.add_argument("--engine", choices=["vm", "tree", "both"], default="both")
    p.add_argument("--stress", action="store_true", help="also run every test with --gc-stress")
    p.add_argument("--only-stress", action="store_true", help="run only the --gc-stress pass")
    p.add_argument("--filter", help="substring of the test path")
    p.add_argument("-j", "--jobs", type=int, default=8)
    p.add_argument("-v", "--verbose", action="store_true")

    p = sub.add_parser("check", help="benchmark scripts vs oracle output, --stats parity across binaries")
    p.add_argument("--binary", action="append", default=[], metavar="PORT=PATH",
                   help="repeatable; e.g. --binary zig=/path/lox --binary rust=/path/lox")
    p.add_argument("--tier", action="append", choices=["smoke", "tree", "vm"],
                   help="repeatable; default smoke only")
    p.add_argument("--no-stress", action="store_true", help="skip the --gc-stress runs at smoke size")
    p.add_argument("--filter", help="substring of the script name")
    p.add_argument("-j", "--jobs", type=int, default=4)

    sub.add_parser("expected", help="regenerate bench/expected with the clox oracle")
    sub.add_parser("toolchains", help="print toolchain resolution")

    p = sub.add_parser("build", help="build a port profile; prints the binary path")
    p.add_argument("--port", required=True)
    p.add_argument("--profile", default="release")
    p.add_argument("--cache", type=Path, help="default: .tmp/lox-bench/cache/<port>-<profile>")

    p = sub.add_parser("loc", help="count a port's lines")
    p.add_argument("--port", required=True)

    args = parser.parse_args()

    if args.cmd == "conformance":
        engines = ["vm", "tree"] if args.engine == "both" else [args.engine]
        modes = [True] if args.only_stress else ([False, True] if args.stress else [False])
        ok = True
        for engine in engines:
            for stress in modes:
                ok &= conformance(args.binary.resolve(), engine, stress, args.filter, args.jobs, args.verbose)
        return 0 if ok else 1
    if args.cmd == "check":
        binaries = {}
        for item in args.binary:
            port, _, path = item.partition("=")
            binaries[port] = Path(path).resolve()
        if not binaries:
            raise SystemExit("give at least one --binary PORT=PATH")
        return 0 if check(binaries, args.tier or ["smoke"], not args.no_stress, args.filter, args.jobs) else 1
    if args.cmd == "expected":
        regenerate_expected()
        return 0
    if args.cmd == "toolchains":
        for name, path in toolchains().items():
            print(f"{{{name}}} = {path}")
        print(f"oracle   = {oracle()}")
        return 0
    if args.cmd == "build":
        cache = args.cache or lox_bench_dir() / "cache" / f"{args.port}-{args.profile}"
        print(build_port(args.port, args.profile, cache.resolve()))
        return 0
    if args.cmd == "loc":
        print(json.dumps(loc(args.port), indent=2))
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
