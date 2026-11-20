#!/usr/bin/env python3
"""Build the edit check's coverage map for the current commit (EC1 step 4).

    python3 scripts/edit_check_map.py [--runs 2] [--jobs 8] [--store DIR] [--keep-runs]

Run it directly, not under `scripts/build-slot.sh`: it takes a build slot for each phase
itself. The phases are

  1. build the map tool (`zig build edit-check-tool`);
  2. build the instrumented compiler and Zig test roots (`zig build coverage`);
  3. run every test of the three roots alone, `--runs` times (the sets of a test are
     unioned; a test whose sets differ is listed as unstable), then the guest phase
     (E2: every guest file alone, cold and warm, into the first run's directory);
  4. write `coverage-<commit>.json.gz` to the store: `$SELKA_EDIT_CHECK_STORE`, else
     `~/.cache/selka/edit-check`.

A tree with uncommitted changes under src/, test/, tools/ or the build files is mapped as
`coverage-<commit>-dirty.json.gz`, because the map digests the sources of the working tree.
"""
import argparse
import gzip
import json
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def slot(*command, check=True):
    """Run a command in a build slot, from the checkout."""
    started = time.monotonic()
    subprocess.run([os.path.join(ROOT, "scripts", "build-slot.sh"), "build", *command], cwd=ROOT, check=check)
    return time.monotonic() - started


def failed_tests(path):
    """The tests a written map lists as failed or timed out alone (a refused map has at least one)."""
    with gzip.open(path, "rt") as handle:
        return json.load(handle).get("failed", [])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--runs", type=int, default=2, help="collection runs to union (default 2)")
    parser.add_argument("--jobs", type=int, default=8, help="tests run at once")
    parser.add_argument("--store", default=os.environ.get("SELKA_EDIT_CHECK_STORE") or os.path.expanduser("~/.cache/selka/edit-check"))
    parser.add_argument("--keep-runs", action="store_true", help="keep the raw hit sets under <store>/runs")
    parser.add_argument("--guests-only", action="store_true", help="collect only the guest phase (a map with a guests root and no Zig tests)")
    args = parser.parse_args()
    commit = subprocess.check_output(["git", "-C", ROOT, "rev-parse", "HEAD"], text=True).strip()
    dirty = subprocess.run(["git", "-C", ROOT, "status", "--porcelain", "--", "src", "test", "tools", "build.zig", "build_coverage.zig"],
                           capture_output=True, text=True).stdout.strip() != ""
    label = commit + ("-dirty" if dirty else "")
    zig = os.environ.get("ZIG") or "zig"
    if "TMPDIR" not in os.environ:
        sys.exit("TMPDIR must name a directory on disk: source ~/.config/selka/dev-env.sh first")
    timings = {}
    timings["tool build"] = slot(zig, "build", "edit-check-tool")
    # The default install too: the tests read zig-out/libexec/selka/components and zig-out/tools, which only an
    # install creates (in a fresh worktree 198 tests failed with ComponentMissing without it, lane E).
    timings["coverage build"] = slot(zig, "build", "install", "coverage")
    runs = os.path.join(args.store, "runs", label)
    shutil.rmtree(runs, ignore_errors=True)
    run_directories = []
    collector = os.path.join(ROOT, "scripts", "edit_check_collect.py")
    coverage = os.path.join(ROOT, "zig-out", "coverage")
    for number in range(1, args.runs + 1):
        out = os.path.join(runs, "run-%d" % number)
        if args.guests_only:
            if number == 1:
                timings["guests"] = slot(sys.executable, collector, "--guests", "--coverage", coverage, "--out", out,
                                         "--jobs", str(args.jobs))
                run_directories.append(out)
            break
        # Only the first run traces its execs (its list is the map's unrecorded list); the second keeps its hit sets only.
        trace = [] if number == 1 else ["--no-trace-exec"]
        timings["collection %d" % number] = slot(sys.executable, collector, "--coverage", coverage, "--out", out,
                                                 "--unnamed", "--jobs", str(args.jobs), *trace)
        if number == 1:
            # The guest phase (E2) writes into the first run's directory: its cold and warm hit sets are unioned there.
            timings["guests"] = slot(sys.executable, collector, "--guests", "--coverage", coverage, "--out", out,
                                     "--jobs", str(args.jobs))
        run_directories.append(out)
    output = os.path.join(args.store, "coverage-%s.json.gz" % label)
    os.makedirs(args.store, exist_ok=True)
    tool = os.path.join(ROOT, "zig-out", "tools", "edit-check-tool")
    started = time.monotonic()
    subprocess.run([tool, "map", ROOT, label, output, *run_directories], check=True)
    timings["map"] = time.monotonic() - started
    # A map with a failed test has no hit set for it, so the edit check could never select it by coverage.
    # Refuse the map instead of storing it (W3: the tool_identity libc fault left 1,509 tests unmapped).
    failed = failed_tests(output)
    if failed:
        sys.exit("map refused: %d tests failed when run alone, first: %s" % (len(failed), failed[0]))
    if not args.keep_runs:
        shutil.rmtree(runs, ignore_errors=True)
    print("map: %s (%.1f MB)" % (output, os.path.getsize(output) / 1e6))
    for name, seconds in timings.items():
        print("  %-16s %7.1f s" % (name, seconds))


if __name__ == "__main__":
    main()
