#!/usr/bin/env python3
"""Collect per-test coverage with the edit check's coverage variant (EC1).

Runs every test of the instrumented Zig test roots in a process of its own and
leaves, per test, the hit sets written by the test process and by every compiler
process it started (`SELKA_COVERAGE_DIR/SELKA_COVERAGE_TEST/<pid>.cov`).

    python3 scripts/edit_check_collect.py --coverage zig-out/coverage --out DIR \
        [--roots units,cli,core] [--jobs N] [--limit N] [--match SUBSTRING]
    python3 scripts/edit_check_collect.py --coverage zig-out/coverage --out DIR --guests [--jobs N]

`--guests` runs only the guest phase (E2): each guest file under `tests/lang` alone with the instrumented
`selka`, cold (a private empty cache, forced) and then warm (the same cache, receipts hitting). Both phases
write into one hit set per file, so the map holds their union. It writes `tests-guests.json` and
`results-guests.jsonl` next to the Zig roots' files, so `edit-check-tool map` reads it as a root.

Each test runs under strace (`exec/<token>-<attempt>.strace`, every execve), and the run ends by writing
`unrecorded.json`: the tokens whose test started an instrumented process that left no hit set (it was killed, or
exited without the runtime's exit hook), or whose trace is missing. The map refuses a run without it, and the edit
check selects those tests whatever the edit (EC1's partly covered tests, lane F's G1).

    python3 scripts/edit_check_collect.py --self-test

Developer tool: not part of the install graph, not run by the gate.
"""
import argparse
import concurrent.futures
import glob
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOTS = {"units": "unit-tests", "cli": "cli-tests", "core": "core-tests"}

# std.zig.Client.Message.Tag / std.zig.Server.Message.Tag values.
CLIENT_EXIT, CLIENT_QUERY = 0, 4
SERVER_TEST_METADATA = 3
# The instrumented executables: the compiler and the three test roots, and copies of them a test makes.
INSTRUMENTED_NAMES = {"selka", "cli-tests", "unit-tests", "core-tests"}
EXEC_LINE = re.compile(r'^(\d+)\s+execve\("((?:[^"\\]|\\.)*)".*\)\s*=\s*(-?\d+)\s*$')
EXEC_START = re.compile(r'^(\d+)\s+execve\("((?:[^"\\]|\\.)*)".*<unfinished \.\.\.>\s*$')
EXEC_RESUMED = re.compile(r'^(\d+)\s+<\.\.\. execve resumed>.*\)\s*=\s*(-?\d+)\s*$')


def parse_trace(lines):
    """The successful execs of a strace log as (pid, path), in order; unfinished and resumed lines pair by pid."""
    pending = {}
    out = []
    for line in lines:
        line = line.rstrip("\n")
        match = EXEC_LINE.match(line)
        if match:
            if int(match.group(3)) == 0:
                out.append((int(match.group(1)), match.group(2)))
            continue
        start = EXEC_START.match(line)
        if start:
            pending[int(start.group(1))] = start.group(2)
            continue
        resumed = EXEC_RESUMED.match(line)
        if resumed:
            path = pending.pop(int(resumed.group(1)), None)
            if path is not None and int(resumed.group(2)) == 0:
                out.append((int(resumed.group(1)), path))
    return out


def unrecorded_pids(trace, cov_dir):
    """The pids whose final image is an instrumented executable and that left no `<pid>.cov` in `cov_dir`."""
    with open(trace, errors="replace") as handle:
        last = dict(parse_trace(handle))
    cov = set(os.listdir(cov_dir)) if os.path.isdir(cov_dir) else set()
    return sorted(pid for pid, path in last.items() if os.path.basename(path) in INSTRUMENTED_NAMES and "%d.cov" % pid not in cov)


UNRECORDED_FILE = "unrecorded.json"


def unrecorded_tokens(out, root=None):
    """The tokens of the results in `out` (of ROOT only, when given) that need the conservative selection: an instrumented
    process with no hit set, or no trace for an attempt that counts. A Zig root's count is its last attempt; a guest
    file's are both phases (cold and warm write into one hit set, and each phase has its own trace)."""
    tokens = set()
    for results in glob.glob(os.path.join(out, "results-%s.jsonl" % root if root else "results-*.jsonl")):
        with open(results) as handle:
            for line in handle:
                if not line.strip():
                    continue
                row = json.loads(line)
                counted = range(len(row["attempts"])) if row["root"] == GUEST_ROOT else [len(row["attempts"]) - 1]
                for number in counted:
                    trace = os.path.join(out, "exec", "%s-%d.strace" % (row["token"], number))
                    if not os.path.exists(trace) or unrecorded_pids(trace, os.path.join(out, "cov", row["token"])):
                        tokens.add(row["token"])
                        break
    return sorted(tokens)


def write_unrecorded(out, tokens):
    """Write the traced run's list to `out/unrecorded.json`, merged with a list already there (the guest phase adds to
    the first run's list, which the refresh merged from its batches). The list of an untraced run is `{"traced": false}`."""
    path = os.path.join(out, UNRECORDED_FILE)
    merged = set(tokens)
    if os.path.exists(path):
        with open(path) as handle:
            existing = json.load(handle)
        if isinstance(existing, list):
            merged.update(existing)
    with open(path, "w") as handle:
        json.dump(sorted(merged), handle)


def write_untraced(out):
    """Mark `out` as untraced (`{"traced": false}`), unless it already holds a traced list."""
    path = os.path.join(out, UNRECORDED_FILE)
    if not os.path.exists(path):
        with open(path, "w") as handle:
            json.dump({"traced": False}, handle)


def list_tests(binary, cwd):
    """The test names of a Zig test binary, in registration order, over the build protocol."""
    cache = tempfile.mkdtemp(prefix="cov-list-")
    proc = subprocess.Popen([binary, "--listen=-", "--cache-dir=" + cache], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, cwd=cwd)
    proc.stdin.write(struct.pack("<II", CLIENT_QUERY, 0))
    proc.stdin.flush()
    names = None
    while names is None:
        header = proc.stdout.read(8)
        if len(header) < 8:
            break
        tag, length = struct.unpack("<II", header)
        body = proc.stdout.read(length)
        if tag == SERVER_TEST_METADATA:
            string_bytes_len, tests_len = struct.unpack_from("<II", body, 0)
            offsets = struct.unpack_from("<%dI" % tests_len, body, 8)
            strings = body[8 + 8 * tests_len:8 + 8 * tests_len + string_bytes_len]
            names = [strings[o:strings.index(b"\0", o)].decode() for o in offsets]
    try:
        proc.stdin.write(struct.pack("<II", CLIENT_EXIT, 0))
        proc.stdin.flush()
        proc.stdin.close()
    except BrokenPipeError:
        pass
    proc.wait(timeout=60)
    if names is None:
        raise SystemExit("could not list the tests of " + binary)
    return names


GUEST_ROOT = "guests"
GUEST_EXIT_NO_TESTS = 3  # `selka test FILE` exits 3 when the file has no entry to run (a helper module)


def guest_files(root=ROOT):
    """The guest files: every `.selka` file under `tests/lang`, as paths relative to the checkout, sorted.

    `selka test FILE` run on each of them gives the same test names as `selka test tests/lang` (checked on 434
    files, 2,213 tests), so one file is the unit of guest selection."""
    found = []
    for directory, _, names in os.walk(os.path.join(root, "tests", "lang")):
        for name in names:
            if name.endswith(".selka"):
                found.append(os.path.relpath(os.path.join(directory, name), root))
    return sorted(found)


def guest_environment(coverage, out, token, scratch):
    """The environment one guest file runs in: the edit check's guest environment, the coverage hooks and private caches."""
    env = {k: v for k, v in os.environ.items() if k in ("PATH", "HOME", "LANG", "USER", "ZIG_GLOBAL_CACHE_DIR")}
    env.update({
        "SELKA_TEST_COMPILER": os.path.join(coverage, "bin", "selka"),
        "SELKA_ZIG": os.environ.get("ZIG", "zig"),
        "SELKA_COMPONENT_DIR": os.path.join(ROOT, "zig-out", "libexec", "selka", "components"),
        "SELKA_TEST_COMPONENT_BUILDER": os.path.join(ROOT, "zig-out", "tools", "selka-components"),
        "SELKA_COMPILER_SHARED_CACHE": "",
        "SELKA_TEST_SHARED_CACHE": "",
        "SELKA_STAGE_SHARED_CACHE": "",
        "SELKA_COVERAGE_DIR": os.path.abspath(os.path.join(out, "cov")),
        "SELKA_COVERAGE_TEST": token,
        "SELKA_COVERAGE_SAMPLE_MS": "5",
        "TMPDIR": scratch,
        "ZIG_LOCAL_CACHE_DIR": os.path.join(scratch, "zig-local"),
    })
    return env


def run_guest(args, index, path):
    """One guest file: a cold run (empty private cache, forced) and a warm run on that cache, hit sets unioned."""
    token = "%s-%05d" % (GUEST_ROOT, index)
    wait_for_memory(args)
    started = time.monotonic()
    scratch = tempfile.mkdtemp(prefix="guest-cov-", dir=args.scratch)
    cache = os.path.join(scratch, "cache")
    coverage = os.path.abspath(args.coverage)
    statuses = []
    try:
        env = guest_environment(coverage, args.out, token, scratch)
        for number, phase in enumerate(("cold", "warm")):
            command = [os.path.join(coverage, "bin", "selka"), "test", path, "--cache-dir", cache]
            if phase == "cold":
                command.append("--force")
            if args.trace_exec:
                # The phase's execs, as the Zig roots' attempts keep theirs (`unrecorded_tokens` reads both phases).
                trace = os.path.join(args.out, "exec", "%s-%d.strace" % (token, number))
                command = ["strace", "-f", "-qq", "-s", "256", "-e", "trace=execve", "-o", trace] + command
            try:
                proc = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                      timeout=args.timeout, start_new_session=True)
                statuses.append(proc.returncode)
            except subprocess.TimeoutExpired:
                statuses.append("timeout")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    ok = all(status in (0, GUEST_EXIT_NO_TESTS) for status in statuses)
    return {"root": GUEST_ROOT, "index": index, "name": path, "token": token, "status": 0 if ok else statuses[-1],
            "attempts": statuses, "seconds": round(time.monotonic() - started, 3), "tail": ""}


def collect_guests(args):
    """The guest phase (E2): every guest file alone, cold and warm, into `--out` (see the module docstring)."""
    os.makedirs(os.path.join(args.out, "cov"), exist_ok=True)
    if args.trace_exec:
        os.makedirs(os.path.join(args.out, "exec"), exist_ok=True)
    names = guest_files(ROOT)
    with open(os.path.join(args.out, "tests-%s.json" % GUEST_ROOT), "w") as handle:
        json.dump(names, handle)
    started = time.monotonic()
    with open(os.path.join(args.out, "results-%s.jsonl" % GUEST_ROOT), "w") as results, \
            concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        futures = [pool.submit(run_guest, args, index, name) for index, name in enumerate(names)]
        for done, future in enumerate(concurrent.futures.as_completed(futures), 1):
            row = future.result()
            results.write(json.dumps(row) + "\n")
            results.flush()
            if done % 100 == 0:
                print("  guests %d/%d (%.0f s)" % (done, len(names), time.monotonic() - started), flush=True)
    if args.trace_exec:
        write_unrecorded(args.out, unrecorded_tokens(args.out, root=GUEST_ROOT))
    else:
        write_untraced(args.out)
    print("guest collection took %.1f s for %d files" % (time.monotonic() - started, len(names)))
    return 0


def test_environment(args, root, token, scratch):
    """The environment one test runs in: the gate's, with private caches and the coverage hooks."""
    coverage = os.path.abspath(args.coverage)
    env = {k: v for k, v in os.environ.items() if k in ("PATH", "HOME", "LANG", "USER", "ZIG_GLOBAL_CACHE_DIR")}
    env.update({
        "SELKA_TEST_COMPILER": os.path.join(coverage, "bin", "selka"),
        "SELKA_ZIG": os.environ.get("ZIG", "zig"),
        "SELKA_COMPONENT_DIR": os.path.join(ROOT, "zig-out", "libexec", "selka", "components"),
        "SELKA_TEST_COMPONENT_BUILDER": os.path.join(ROOT, "zig-out", "tools", "selka-components"),
        "SELKA_UNIT_JOBS": "1",
        "SELKA_JOBS": "1",
        "SELKA_COMPILER_SHARED_CACHE": "",
        "SELKA_TEST_SHARED_CACHE": "",
        "SELKA_STAGE_SHARED_CACHE": "",
        "SELKA_COVERAGE_DIR": os.path.abspath(os.path.join(args.out, "cov")),
        "SELKA_COVERAGE_TEST": token,
        "SELKA_COVERAGE_SAMPLE_MS": str(args.sample_ms),
        "TMPDIR": scratch,
        "ZIG_LOCAL_CACHE_DIR": os.path.join(scratch, "zig-local"),
        "SELKA_CORE_TEST_CACHE": os.path.join(scratch, "core-tests"),
    })
    return env


def prepare_workdir(scratch):
    """A directory that looks like the checkout, with caches of its own: the coverage of a
    test must not depend on what an earlier test left in `.selka-cache`."""
    work = os.path.join(scratch, "tree")
    os.makedirs(os.path.join(work, ".zig-cache"))
    for entry in os.listdir(ROOT):
        if entry in (".selka-cache", ".zig-cache", "zig-out", ".tmp", ".selka-work"):
            continue
        os.symlink(os.path.join(ROOT, entry), os.path.join(work, entry))
    os.makedirs(os.path.join(work, "zig-out"))
    for sub in ("libexec", "tools", "bin"):
        os.symlink(os.path.join(ROOT, "zig-out", sub), os.path.join(work, "zig-out", sub))
    return work


def available_memory_gb():
    """MemAvailable in GiB, so a worker can wait instead of pushing the machine into earlyoom."""
    with open("/proc/meminfo") as handle:
        for line in handle:
            if line.startswith("MemAvailable:"):
                return int(line.split()[1]) / (1 << 20)
    return 0.0


def wait_for_memory(args):
    while available_memory_gb() < args.min_available_gb:
        time.sleep(2)


# The unnamed `test {}` blocks of a root cannot be selected by name; shard 0 of a huge shard
# count runs all of them and a single named test.
UNNAMED = "unnamed"


def run_one(args, root, index, name):
    """Run one test alone: first in a private tree under an address-space cap; if it fails, once
    without the cap (sanitizer tests need far more address space than any cap allows); if it
    fails again, once in the checkout itself (a test that counts allocations across repeated
    runs of cache-using code needs a warm cache)."""
    token = "%s-%05d" % (root, index) if index is not None else "%s-%s" % (root, UNNAMED)
    wait_for_memory(args)
    started = time.monotonic()
    attempts = []
    trace_on = args.trace_exec
    for capped, shared in ((True, args.shared_tree), (False, args.shared_tree), (False, True)):
        scratch = tempfile.mkdtemp(prefix="cov-", dir=args.scratch)
        try:
            work = ROOT if shared else prepare_workdir(scratch)
            binary = os.path.join(os.path.abspath(args.coverage), "bin", ROOTS[root])
            selection = "--test-filter=" + name if index is not None else "--test-shard=0/1000000"
            cmd = [binary, "--cache-dir=" + os.path.join(scratch, "fuzz-cache"), selection]
            if capped:
                cmd = ["prlimit", "--as=%d" % (args.rlimit_gb << 30)] + cmd
            if trace_on:
                # Every execve the test starts, with the pid it runs under: the inventory of processes (EC1 gap G1).
                trace = os.path.join(args.out, "exec", "%s-%d.strace" % (token, len(attempts)))
                cmd = ["strace", "-f", "-qq", "-s", "256", "-e", "trace=execve", "-o", trace] + cmd
            proc = subprocess.run(cmd, cwd=work, env=test_environment(args, root, token, scratch),
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=args.timeout, start_new_session=True)
            status, tail = proc.returncode, proc.stdout[-400:].decode(errors="replace")
        except subprocess.TimeoutExpired:
            status, tail = "timeout", ""
        finally:
            shutil.rmtree(scratch, ignore_errors=True)
        attempts.append(status)
        if status == 0 or status == "timeout" or (args.shared_tree and not capped):
            break
        # The failed attempt's hit sets are not this test's: drop them before the retry. The retry runs untraced: the
        # tracer itself can make a test fail (LeakSanitizer stops the threads with ptrace), so the retry's processes
        # have no trace and the run lists the test as unrecorded (selected whatever the edit).
        shutil.rmtree(os.path.join(args.out, "cov", token), ignore_errors=True)
        trace_on = False
    return {"root": root, "index": index, "name": name, "token": token, "status": attempts[-1], "attempts": attempts,
            "seconds": round(time.monotonic() - started, 3), "tail": tail if attempts[-1] else ""}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--coverage", default="zig-out/coverage", help="prefix of the coverage variant")
    parser.add_argument("--out", required=True, help="directory for hit sets, the test lists and results")
    parser.add_argument("--roots", default="units,cli,core")
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--limit", type=int, default=0, help="run only the first N tests of each root")
    parser.add_argument("--sample", type=int, default=0, help="run a pseudo-random sample of N tests per root (fixed seed)")
    parser.add_argument("--match", default="", help="run only tests whose name contains this")
    parser.add_argument("--names", help="run only the tests named in this file, one name per line (a rerun of failed tests)")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--sample-ms", type=int, default=5, help="counter sampling interval of the runtime in ms (0 = off)")
    parser.add_argument("--shared-tree", action="store_true", help="run in the checkout itself with its warm caches (to measure what cold costs)")
    parser.add_argument("--min-available-gb", type=float, default=7.0, help="start no test while less memory than this is available")
    parser.add_argument("--unnamed", action="store_true", help="also run each root's unnamed test blocks once")
    parser.add_argument("--no-trace-exec", dest="trace_exec", action="store_false", default=True,
                        help="do not trace each test's execs (the map then has no unrecorded list and the map tool refuses the run)")
    parser.add_argument("--self-test", action="store_true", help="check the trace parser and the unrecorded-process rule, then exit (no other argument needed)")
    parser.add_argument("--rlimit-gb", type=int, default=12)
    parser.add_argument("--scratch", default=os.environ.get("TMPDIR"), required="TMPDIR" not in os.environ, help="per-test scratch (on disk; default $TMPDIR)")
    parser.add_argument("--guests", action="store_true", help="run only the guest phase (E2): every guest file alone, cold and warm")
    if "--self-test" in sys.argv[1:]:
        self_test()
        return 0
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    os.makedirs(os.path.join(args.out, "cov"), exist_ok=True)
    if args.trace_exec:
        os.makedirs(os.path.join(args.out, "exec"), exist_ok=True)
    if args.guests:
        return collect_guests(args)
    started = time.monotonic()
    for root in args.roots.split(","):
        binary = os.path.join(os.path.abspath(args.coverage), "bin", ROOTS[root])
        names = list_tests(binary, ROOT)
        with open(os.path.join(args.out, "tests-%s.json" % root), "w") as handle:
            json.dump(names, handle)
        # Unnamed `test {}` blocks cannot be selected by name; `--unnamed` runs them together.
        chosen = [(i, n) for i, n in enumerate(names) if args.match in n and ".test." in n]
        if args.names:
            with open(args.names) as handle:
                wanted = {line.strip() for line in handle if line.strip()}
            chosen = [(i, n) for i, n in chosen if n in wanted]
            print("%s: %d of the requested names are tests of this binary" % (root, len(chosen)), flush=True)
        if args.sample:
            import random
            chosen = sorted(random.Random(20261025).sample(chosen, min(args.sample, len(chosen))))
        if args.limit:
            chosen = chosen[:args.limit]
        print("%s: %d tests, running %d" % (root, len(names), len(chosen)), flush=True)
        with open(os.path.join(args.out, "results-%s.jsonl" % root), "w") as results, \
                concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
            futures = [pool.submit(run_one, args, root, i, n) for i, n in chosen]
            if args.unnamed:
                futures.append(pool.submit(run_one, args, root, None, ""))
            for done, future in enumerate(concurrent.futures.as_completed(futures), 1):
                row = future.result()
                results.write(json.dumps(row) + "\n")
                results.flush()
                if done % 50 == 0:
                    print("  %s %d/%d (%.0f s)" % (root, done, len(chosen), time.monotonic() - started), flush=True)
    if args.trace_exec:
        tokens = unrecorded_tokens(args.out)
        write_unrecorded(args.out, tokens)
        print("unrecorded: %d tests started an instrumented process with no hit set (see unrecorded.json)" % len(tokens))
    else:
        write_untraced(args.out)
    print("collection took %.1f s" % (time.monotonic() - started))


def self_test():
    """The parser pairs unfinished and resumed execs and drops failed ones; a killed instrumented process is found."""
    lines = [
        '10 execve("/usr/bin/prlimit", ["prlimit"], 0x0) = 0',
        '10 execve("/x/zig-out/coverage/bin/cli-tests", ["cli"], 0x0) = 0',
        '11 execve("/x/zig-out/tools/nope", ["nope"], 0x0) = -1 ENOENT (No such file or directory)',
        '12 execve("/a/selka", ["selka"], 0x0 <unfinished ...>',
        '12 <... execve resumed>) = 0',
        '13 execve("/a/zig", ["zig"], 0x0 <unfinished ...>',
        '13 <... execve resumed>) = -1 ENOENT (No such file or directory)',
    ]
    assert parse_trace(lines) == [(10, "/usr/bin/prlimit"), (10, "/x/zig-out/coverage/bin/cli-tests"), (12, "/a/selka")]
    import tempfile as _tempfile
    with _tempfile.TemporaryDirectory() as scratch:
        trace = os.path.join(scratch, "t.strace")
        with open(trace, "w") as handle:
            handle.write('20 execve("/x/selka", ["selka"], 0x0) = 0\n21 execve("/x/selka", ["selka"], 0x0) = 0\n')
        cov = os.path.join(scratch, "cov")
        os.makedirs(cov)
        open(os.path.join(cov, "21.cov"), "w").close()
        assert unrecorded_pids(trace, cov) == [20], unrecorded_pids(trace, cov)
    print("self-test ok")


if __name__ == "__main__":
    sys.exit(main())
