#!/usr/bin/env python3
"""ThreadSanitizer and determinism check for task groups and parallel.map (E1c, plan 2 section 6.6).

Builds the group and map drivers with SELKA_CORE_SANITIZE=thread, then:
- runs each sanitized binary at 1, 2 and 8 threads, and requires the output at 2 and 8 threads to equal the
  1-thread output;
- runs the 8-thread binary RUNS times under a soft 16 GiB address-space cap (the hard limit stays unlimited, because
  ThreadSanitizer lifts the soft cap itself, E1b-D12), and requires exit 0, the same output, and no ThreadSanitizer report.

Usage: tests/test_concurrency.py SELKA_COMPILER
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DRIVERS = ["test/concurrency/groups_driver.selka", "test/concurrency/maps_driver.selka"]
RUNS = 20
ADDRESS_SPACE = f"--as={16 << 30}:unlimited"
# A finding starts with this line. The address-space notice that ThreadSanitizer prints before it re-execs also names the tool.
REPORT = "WARNING: ThreadSanitizer:"


def run(argv, threads=None, capped=False):
    """Run one command with SELKA_THREADS set when given, under the soft address-space cap when `capped`."""
    environment = dict(os.environ)
    if threads is not None:
        environment["SELKA_THREADS"] = str(threads)
    command = ["prlimit", ADDRESS_SPACE] + argv if capped else argv
    return subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True, timeout=600)


def build(compiler, driver, directory):
    """Build `driver` with ThreadSanitizer; return the binary's path."""
    binary = os.path.join(directory, os.path.basename(driver).replace(".selka", "-tsan"))
    environment = dict(os.environ, SELKA_CORE_SANITIZE="thread")
    built = subprocess.run([compiler, "build", driver, "-o", binary], cwd=ROOT, env=environment, capture_output=True, text=True, timeout=1200)
    if built.returncode != 0:
        sys.stderr.write(built.stdout + built.stderr)
        raise SystemExit(f"concurrency: build of {driver} failed with {built.returncode}")
    return binary


def check(compiler, driver, directory):
    """Check one driver; return a list of failure lines (empty when it passes)."""
    failures = []
    binary = build(compiler, driver, directory)
    reference = None
    for threads in (1, 2, 8):
        result = run([binary], threads=threads)
        if result.returncode != 0 or REPORT in result.stderr:
            failures.append(f"{driver} at {threads} threads: exit {result.returncode}, sanitizer report {REPORT in result.stderr}")
        if reference is None:
            reference = result.stdout
        elif result.stdout != reference:
            failures.append(f"{driver} at {threads} threads: output differs from the 1-thread run")
    reports = clean = 0
    for _ in range(RUNS):
        result = run([binary], threads=8, capped=True)
        if REPORT in result.stderr:
            reports += 1
        if result.returncode == 0 and result.stdout == reference and REPORT not in result.stderr:
            clean += 1
    if reports:
        failures.append(f"{driver}: {reports} of {RUNS} runs at 8 threads reported a ThreadSanitizer finding")
    if clean != RUNS:
        failures.append(f"{driver}: {RUNS - clean} of {RUNS} runs at 8 threads were not clean")
    print(f"concurrency: {driver}: 1/2/8-thread outputs {'equal' if not any('differs' in f for f in failures) else 'DIFFER'}; "
          f"{clean}/{RUNS} runs clean at 8 threads; ThreadSanitizer reports {reports}")
    return failures


def main(argv):
    if len(argv) != 2:
        sys.stderr.write(__doc__)
        return 2
    compiler = os.path.abspath(argv[1])
    failures = []
    with tempfile.TemporaryDirectory(prefix="concurrency-") as directory:
        for driver in DRIVERS:
            failures.extend(check(compiler, driver, directory))
    for line in failures:
        print("concurrency: FAIL " + line)
    print("concurrency: PASS" if not failures else f"concurrency: FAILED ({len(failures)} findings)")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
