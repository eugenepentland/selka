#!/usr/bin/env python3
"""MODULE-SCHEDULE-1..3 build differential: after seeded edits, the default
`mylang build` (module by module, over a persistent cache) must build what a
clean whole-program build (`--whole-program`, fresh cache) builds.

usage: module_build_diff.py MYLANG [--project DIR] [--steps N] [--seed S]
                            [--arg-sets FILE] [--run-timeout SECONDS] [--keep DIR]

The project (default `tests/fixtures/module_compile`) is copied to a work
directory and built once. Each step then restores the pristine sources,
applies one or two seeded edits (literals, operators, text literals, record
field order, an added function, a no-op statement, a comment that moves
lines), and builds twice: incrementally with the default build, which
compiles only the modules whose source or read interfaces changed, and cleanly
with the whole-program build. Both must reject the same edited programs; for a
program that builds, the executables must be identical byte for byte and
running them (with no arguments, and with each argument list in
`--arg-sets`, a JSON list of lists) must give the same stdout, stderr and exit
status (a run past --run-timeout, default 20 s, fails the comparison). The summary counts steps, builds, rejections, modules compiled and
reused by the incremental builds, and mismatches; exit status 1 on any mismatch.
"""
import argparse
import hashlib
import json
import random
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

RUNTIMES = {"rc": ["--rc-runtime"], "gc": ["--gc-runtime"], "stats": ["--rc-runtime=stats"], "sites": ["--rc-runtime=sites"]}


def run(cmd, cwd=None, timeout=900):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None


def mutations(rng, text):
    out = []
    for m in re.finditer(r"(?<![\w.\[])(\d+)(?![\w.])", text):
        out.append(("int literal", text[:m.start()] + str(int(m.group(1)) + rng.choice([1, 2, 7])) + text[m.end():]))
    for pat, rep in [(" < ", " <= "), (" > ", " >= "), (" + 1", " + 2"), (" - 1", " - 2"), (" == ", " != "), (" * 2", " * 3")]:
        idx = [m.start() for m in re.finditer(re.escape(pat), text)]
        if idx:
            i = rng.choice(idx)
            out.append((f"op {pat.strip()}->{rep.strip()}", text[:i] + rep + text[i + len(pat):]))
    for m in re.finditer(r'"([^"\\]{2,})"', text):
        out.append(("text literal", text[:m.start()] + '"' + m.group(1)[::-1] + '"' + text[m.end():]))
    lines = text.split("\n")
    for i in range(len(lines) - 1):
        a, b = lines[i], lines[i + 1]
        if re.match(r"^    \w+: [\w\[\]., ]+$", a) and re.match(r"^    \w+: [\w\[\]., ]+$", b):
            out.append(("swap fields", "\n".join(lines[:i] + [b, a] + lines[i + 2:])))
    out.append(("add function", text + "\n\npublic def zz_added_fn(n: int) -> int:\n    return n + 1\n"))
    out.append(("comment", text.replace("\n\n\n", "\n\n\n# an edit that moves lines\n", 1)))
    for m in re.finditer(r"^(public )?def \w+\(.*\)( -> [^:]+)?( effects\([^)]*\))?:\n", text, re.M):
        out.append(("body no-op", text[:m.end()] + "    zz_ok: int = 1\n    _ = zz_ok\n" + text[m.end():]))
    return out


def report_of(proc):
    for line in proc.stdout.decode("utf-8", "replace").splitlines():
        if line.startswith('{"version":"qbe-build-v1"'):
            return json.loads(line)
    return None


class Differential:
    def __init__(self, args, work):
        self.mylang = str(Path(args.mylang).resolve())
        self.work = work
        self.tree = work / "tree"
        self.arg_sets = [[]] + (json.loads(Path(args.arg_sets).read_text()) if args.arg_sets else [])
        self.run_timeout = args.run_timeout
        self.runtime = RUNTIMES[args.runtime]
        self.rows = []
        self.stats = {"steps": 0, "built": 0, "rejected": 0, "compiled": 0, "reused": 0, "mismatches": 0, "runs": 0}

    def build(self, output, cache, *extra):
        return run([self.mylang, "build", "main.my", "-o", str(self.work / output), f"--cache-dir={self.work / cache}"] + self.runtime + list(extra), cwd=self.tree)

    def behaviour(self, program):
        results = []
        for args in self.arg_sets:
            proc = run([str(program)] + [str(a) for a in args], cwd=self.tree, timeout=self.run_timeout)
            results.append("timeout" if proc is None else (proc.returncode, proc.stdout, proc.stderr))
        return results

    def mismatch(self, what, problem):
        self.stats["mismatches"] += 1
        if self.rows:
            self.rows[-1]["problem"] = problem
        print(f"MISMATCH ({what}): {problem}", flush=True)
        shutil.copytree(self.tree, self.work / f"mismatch-{self.stats['steps']}", dirs_exist_ok=True)

    def step(self, what):
        self.rows.append({"case": what})
        inc = self.build("inc", "cache", "--report")
        shutil.rmtree(self.work / "fresh", ignore_errors=True)
        cold = self.build("cold", "fresh", "--whole-program")
        if inc is None or cold is None:
            return self.mismatch(what, "a build timed out")
        self.rows[-1].update(module_status=inc.returncode, whole_status=cold.returncode)
        if inc.returncode != cold.returncode:
            return self.mismatch(what, f"incremental rc={inc.returncode} clean rc={cold.returncode}: {inc.stderr[-300:]} / {cold.stderr[-300:]}")
        if cold.returncode != 0:
            self.stats["rejected"] += 1
            if what == "pristine":
                return self.mismatch(what, "the pristine reference project did not build")
            if inc.stderr != cold.stderr:
                return self.mismatch(what, "the two builds report different diagnostics")
            print(f"ok ({what}): both rejected", flush=True)
            return
        self.stats["built"] += 1
        report = report_of(inc) or {}
        counts = report.get("module_build") or {}
        if not counts:
            return self.mismatch(what, "the incremental build did not take the per-module path")
        self.rows[-1]["module_build"] = counts
        self.stats["compiled"] += counts["compiled"]
        self.stats["reused"] += counts["reused"]
        if (self.work / "inc").read_bytes() != (self.work / "cold").read_bytes():
            return self.mismatch(what, "executables differ")
        self.rows[-1]["executable_sha256"] = hashlib.sha256((self.work / "inc").read_bytes()).hexdigest()
        runs = self.behaviour(self.work / "inc")
        whole_runs = self.behaviour(self.work / "cold")
        self.stats["runs"] += len(runs)
        if "timeout" in runs or "timeout" in whole_runs:
            return self.mismatch(what, "an executable timed out")
        if runs != whole_runs:
            return self.mismatch(what, "runs differ")
        print(f"ok ({what}): {counts['compiled']} module(s) compiled", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mylang")
    parser.add_argument("--project", default="tests/fixtures/module_compile")
    parser.add_argument("--steps", type=int, default=20)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--arg-sets")
    parser.add_argument("--run-timeout", type=float, default=20)
    parser.add_argument("--keep")
    parser.add_argument("--runtime", choices=RUNTIMES, default="rc")
    parser.add_argument("--json")
    args = parser.parse_args()
    if args.steps < 1 or args.run_timeout <= 0:
        parser.error("steps and run-timeout must be positive")
    work = Path(args.keep or tempfile.mkdtemp(prefix="module-build-diff-")).resolve()
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    diff = Differential(args, work)
    shutil.copytree(args.project, diff.tree, ignore=shutil.ignore_patterns(".mylang-cache"))
    # Test modules are not part of the program the entry builds.
    pristine = {str(p.relative_to(diff.tree)): p.read_text() for p in sorted(diff.tree.rglob("*.my")) if not re.search(r"_tests?\.my$", p.name)}
    rng = random.Random(args.seed)
    diff.step("pristine")
    if diff.stats["mismatches"]:
        return 1
    for number in range(1, args.steps + 1):
        diff.stats["steps"] = number
        for name, text in pristine.items():
            (diff.tree / name).write_text(text)
        edits = []
        for _ in range(1 if rng.random() < 0.7 else 2):
            name = rng.choice(sorted(pristine))
            path = diff.tree / name
            label, text = rng.choice(mutations(rng, path.read_text()))
            path.write_text(text)
            edits.append(f"{name}: {label}")
        diff.step(f"step {number}: " + "; ".join(edits))
    if not diff.stats["built"] or not diff.stats["runs"]:
        diff.mismatch("coverage", "no successful executable comparison")
    if args.json:
        Path(args.json).write_text(json.dumps({"runtime": args.runtime, "seed": args.seed, "compiler_sha256": hashlib.sha256(Path(diff.mylang).read_bytes()).hexdigest(), "totals": diff.stats, "results": diff.rows}, indent=1))
    print(json.dumps(diff.stats))
    if not args.keep and diff.stats["mismatches"] == 0:
        shutil.rmtree(work, ignore_errors=True)
    return 1 if diff.stats["mismatches"] else 0


if __name__ == "__main__":
    sys.exit(main())
