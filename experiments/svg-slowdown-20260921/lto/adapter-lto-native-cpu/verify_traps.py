#!/usr/bin/env python3
"""Differential trap, accounting and GC-stress verification between the arms.

    verify_traps.py [--work DIR] [--jobs N] [--only NAME]

Reuses the repository's differential trap fixtures
(`experiments/sexpr-audit/evidence/hot-loops/trapdiff`), which exist because a
change to the root protocol or the position stores can move a trap address, drop a
sticky-trap test or reorder a frame chain without changing any value a passing test
would print.  Each fixture is built by both backends in every accounting mode and
the two binaries must agree on stdout, stderr and the exit status byte for byte.

Coverage:

* builds compare the two *backends* in ReleaseFast, with `--max-frames` and
  `--max-steps`, and in Debug with and without the same ceilings;
* the built QBE and LLVM binaries both run with and without `--gc-stress`;
* requested budget accounting is enabled at build time, not merely requested
  from an executable that omitted it. Every failed build is a failed gate.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
MYLANG = REPO / "zig-out" / "bin" / "mylang"
ADAPTER = HERE / "qbe_llvm.py"
FIXTURES = REPO / "experiments" / "sexpr-audit" / "evidence" / "hot-loops" / "trapdiff"
OVERRIDES = HERE / 'tests' / 'traps'

#: label -> (mode, guest arguments) for the built-binary comparison.
BUILDS = (
    ("fast", "ReleaseFast", []),
    ("fast-frames", "ReleaseFast", ["--max-frames=3"]),
    ("fast-steps", "ReleaseFast", ["--max-steps=5"]),
    ("debug", "Debug", []),
    ("debug-steps", "Debug", ["--max-steps=20"]),
    ("debug-frames", "Debug", ["--max-frames=3"]),
)


def build(source, binary, mode, tool, cache, arguments):
    """Build one fixture with one backend."""
    command = [str(MYLANG), "build", str(source), "-o", str(binary),
               "--mode", mode, f"--cache-dir={cache}", "--keep-symbols", *arguments]
    if tool is not None:
        command.append(f"--qbe={tool}")
    return subprocess.run(command, capture_output=True, text=True, timeout=600)


def run(binary, arguments):
    """Run one binary, returning (status, stdout, stderr)."""
    done = subprocess.run([str(binary), *arguments], capture_output=True, text=True,
                          timeout=600)
    return done.returncode, done.stdout, done.stderr


def check_fixture(name, work):
    """Compare both backends on one fixture in every mode."""
    source = OVERRIDES / f"{name}.my"
    if not source.exists():
        source = FIXTURES / f"{name}.my"
    failures = []
    checks = 0
    results = []
    for label, mode, arguments in BUILDS:
        qbe_binary = work / f"{name}.{label}.qbe"
        llvm_binary = work / f"{name}.{label}.llvm"
        # One cache root per fixture and arm: the fixtures run in parallel, and a
        # shared root makes concurrent generations contend for the same directory.
        qbe_build = build(source, qbe_binary, mode, None, work / f"cache-qbe-{name}", arguments)
        llvm_build = build(source, llvm_binary, mode, str(ADAPTER),
                           work / f"cache-llvm-{name}", arguments)
        if qbe_build.returncode != 0 or llvm_build.returncode != 0:
            failures.append((label, "build",
                             f"status {qbe_build.returncode} vs {llvm_build.returncode}",
                             qbe_build.stderr[-1500:], llvm_build.stderr[-1500:]))
            continue
        first = run(qbe_binary, arguments)
        second = run(llvm_binary, arguments)
        first_stress = run(qbe_binary, [*arguments, '--gc-stress'])
        second_stress = run(llvm_binary, [*arguments, '--gc-stress'])
        # Equality of two refusals does not verify that a ceiling was enforced.
        for arm, outcome in [('qbe', first), ('llvm', second)]:
            if 'R_NO_FRAME_ACCOUNTING' in outcome[2] or 'R_NO_STEP_ACCOUNTING' in outcome[2]:
                failures.append((label, 'accounting', arm + ' omitted requested accounting',
                                 outcome[2], ''))
            if name == 'recursion' and label.endswith('frames') and 'R_FRAME_LIMIT' not in outcome[2]:
                failures.append((label, 'frame-limit', arm + ' did not reach R_FRAME_LIMIT',
                                 outcome[2], ''))
            if name == 'recursion' and label.endswith('steps') and 'R_STEP_LIMIT' not in outcome[2]:
                failures.append((label, 'step-limit', arm + ' did not reach R_STEP_LIMIT',
                                 outcome[2], ''))
        for stage, left, right in [('run', first, second),
                                   ('stress-backends', first_stress, second_stress),
                                   ('qbe-stress', first, first_stress),
                                   ('llvm-stress', second, second_stress)]:
            checks += 1
            results.append({'mode': label, 'stage': stage, 'match': left == right,
                            'left': left, 'right': right})
            if left != right:
                failures.append((label, stage, 'stdout/stderr/status differ', repr(left), repr(right)))
    return name, checks, failures, results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", default="/tmp/llvm-backend-traps")
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--only", help="run only this fixture")
    parser.add_argument("--json", dest='out', help='retain all comparison results')
    options = parser.parse_args()
    work = Path(options.work)
    work.mkdir(parents=True, exist_ok=True)
    recipe = hashlib.sha256(MYLANG.read_bytes())
    for path in sorted(HERE.glob('*.py')):
        recipe.update(path.name.encode())
        recipe.update(path.read_bytes())
    work = work / recipe.hexdigest()[:16]
    work.mkdir(exist_ok=True)

    names = sorted(path.stem for path in FIXTURES.glob("*.my"))
    if options.only:
        names = [name for name in names if name == options.only]
    if not names:
        raise SystemExit(f"no fixtures under {FIXTURES}")

    total_checks = 0
    total_failures = 0
    report = {'work': str(work), 'recipe_sha256': recipe.hexdigest(), 'fixtures': {}}
    with concurrent.futures.ThreadPoolExecutor(max_workers=options.jobs) as pool:
        futures = [pool.submit(check_fixture, name, work) for name in names]
        for future in concurrent.futures.as_completed(futures):
            name, checks, failures, results = future.result()
            source = OVERRIDES / f'{name}.my'
            if not source.exists():
                source = FIXTURES / f'{name}.my'
            report['fixtures'][name] = {'source': str(source),
                                        'sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                                        'checks': results, 'failures': failures}
            total_checks += checks
            total_failures += len(failures)
            status = "ok" if not failures else f"{len(failures)} MISMATCH"
            print(f"{name:20s} {checks:2d} comparisons  {status}", flush=True)
            for label, stage, detail, first, second in failures:
                print(f"    [{label}/{stage}] {detail}")
                print(f"      qbe : {first}")
                print(f"      llvm: {second}")

    print(f"\n{total_checks} built-binary comparisons across {len(names)} fixtures, "
          f"including LLVM GC stress, {total_failures} mismatches/build failures")
    report.update({'checks': total_checks, 'failures': total_failures})
    if options.out:
        Path(options.out).write_text(json.dumps(report, indent=2)+'\n')
    return 1 if total_failures else 0


if __name__ == "__main__":
    sys.exit(main())
