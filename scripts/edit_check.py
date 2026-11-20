#!/usr/bin/env python3
"""Run the tests a working-tree edit can affect (edit check, EC3). NOT the landing gate.

    python3 scripts/edit_check.py [--map PATH] [--importers direct|closure|reexport|none]
                                  [--select-only] [--no-guests] [--store DIR] [--log DIR] [--chunk-seconds S]

Steps, each through `scripts/build-slot.sh` when it builds:

1. build the compiler, the three Zig test binaries and the impact tool in one
   `zig build install edit-check-binaries edit-check-impact test-verification-registry` (one admission), while the
   gate's cheap checks run beside it (`scripts/gate_cheap_checks.py`: `zig fmt`, `test-inputs-coverage`),
   then the compiler's two (the `.selka` format check, `selka doc-coverage`); a finding is printed when it arrives with
   its `file:line`, the build and the tests still run, and the edit check ends failed with the findings repeated;
2. list the tests of each binary (its current names, which include new tests);
3. choose the newest coverage map whose commit is an ancestor of HEAD (dirty maps are not
   used); with no map, run `scripts/affected_tests.py` instead;
4. run `zig-out/tools/edit-check-impact` against that map and print the selection, and add the build steps the changed
   paths select by name (`affected_tests.DRIVER_STEPS`: `test-goals` for an edit of `docs/goals.md`, of a pinned example under
   `test/fixtures/goals/` or of its driver, which no Zig test reads);
5. run the selected tests of each binary by exact name (`--test-list`), the unnamed
   blocks with the `#unnamed` line, and the selected guest files through `selka test FILE` (E2: one
   process per file; every guest file, as one `selka test tests/lang`, when all of them are selected),
   then the selected steps; `--no-guests` leaves the guest suite out.

The jobs of step 5 run longest first, at most one per job slot (E3). A binary's selection is split into
chunks by expected seconds, and each guest job carries its own expected seconds. The expected seconds
come from the durations store (`durations.json` in the store), which each run rewrites from its own
measurements: a Zig chunk's wide Guardian report, and each guest job's wall time.

Output is at most 20 lines on standard output; the full impact list and each run's output
are written under `--log`, with `run-timeline.tsv` (each job's start and end). The last line says
whether the edit check passed, and that this is not the landing gate.

When the map it would use is more than STALE_COMMITS commits behind main, and main has no map of its own, the first
line says so and (unless --select-only) starts a detached refresh (`scripts/edit_check_refresh.py`).

Developer tool: not part of the install graph, and not run by the gate.
"""
import argparse
import gzip
import json
import math
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import affected_tests  # noqa: E402  (the table of steps an edit selects by path, DRIVER_STEPS)
import gate_cheap_checks  # noqa: E402  (the gate's cheap checks, run before any test as the gate runs them)
import edit_check_collect  # noqa: E402  (test listing protocol, shared with the collector)
import edit_check_refresh  # noqa: E402  (the map's staleness line and its refresh)

BINARIES = {"units": "unit-tests", "cli": "cli-tests", "core": "core-tests"}
GUESTS = "guests"
GUEST_DIRECTORY = "tests/lang"  # the one run of every guest file, when all of them are selected
# `selka test FILE` exits 3 when the file has no entry to run: a helper module with no test.
GUEST_NO_ENTRIES = 3
GATE_LINE = "edit check passed; this is not the landing gate"
FAIL_LINE = "edit check failed; this is not the landing gate"
UNNAMED = "#unnamed"
# The impact tool's status for a map that predates the unrecorded list (`tools/impact.zig`, refused_map_status).
REFUSED_MAP_STATUS = 3
# Scheduling (E3). Expected seconds come from the durations store (DURATIONS_FILE in the store) that earlier runs of
# this check wrote from their jobs; the constants below only apply where nothing is recorded.
DURATIONS_FILE = "durations.json"
DURATIONS_FORMAT = "edit-check-durations-v1"
CHUNK_SECONDS = 7.0  # target expected work per Zig chunk: 50 times the 0.14 s per-process cost measured in lane C
MAX_CHUNKS_PER_SLOT = 4  # a binary never has more chunks than this many times the job slots
DEFAULT_TEST_SECONDS = 1.0  # a test when its binary has no record at all: about the stage edit's mean per test
GUEST_SECONDS = 40.0  # the directory run (every guest file) before any run recorded it (alone 39 to 50 s in lane C)
GUEST_FILE_SECONDS = 1.0  # a guest file before any run recorded it (lane H measures the per-file wall)
FLOOR_SECONDS = 0.001  # a test under the report's 1 ms floor
WIDE_LINES = 100  # Guardian's wide report lists at most this many tests


def git(*args):
    return subprocess.check_output(["git", "-C", ROOT, *args], text=True).strip()


def slot(*command, check=True):
    """Run a build command in a build slot, from the checkout."""
    return subprocess.run([os.path.join(ROOT, "scripts", "build-slot.sh"), "build", *command], cwd=ROOT, check=check)


def changed_paths(commit, root=ROOT):
    """The paths the working tree differs from `commit` in: committed, staged and unstaged edits, and untracked files."""
    tracked = subprocess.check_output(["git", "-C", root, "diff", "--name-only", commit], text=True).splitlines()
    untracked = subprocess.check_output(["git", "-C", root, "ls-files", "--others", "--exclude-standard"], text=True).splitlines()
    return sorted(set(tracked + untracked))


def driver_steps(changed):
    """The build steps the changed paths select that no Zig or guest test stands for (`affected_tests.DRIVER_STEPS`), each with
    the paths that chose it: the goals check for an edit of `docs/goals.md` or of a pinned example."""
    chosen = {}
    for path in changed:
        for prefix, step in affected_tests.DRIVER_STEPS:
            if path.startswith(prefix):
                chosen.setdefault(step, []).append(path)
    return sorted(chosen.items())


def step_line(steps):
    """The selection line for the driver steps: each step and the first path that chose it."""
    return "steps: " + ", ".join("%s (%s%s)" % (step, paths[0], " and %d more" % (len(paths) - 1) if len(paths) > 1 else "")
                                 for step, paths in steps)


def store_dir(args):
    return args.store or os.environ.get("SELKA_EDIT_CHECK_STORE") or os.path.expanduser("~/.cache/selka/edit-check")


def newest_map(store, head):
    """The map (path, commit) whose commit is an ancestor of HEAD and the most recent; dirty maps are skipped."""
    best = None
    if not os.path.isdir(store):
        return None
    for name in os.listdir(store):
        match = re.fullmatch(r"coverage-([0-9a-f]{7,40})\.json\.gz", name)
        if not match:
            continue
        commit = match.group(1)
        if subprocess.run(["git", "-C", ROOT, "merge-base", "--is-ancestor", commit, head]).returncode != 0:
            continue
        when = int(git("log", "-1", "--format=%ct", commit))
        if best is None or when > best[2]:
            best = (os.path.join(store, name), commit, when)
    return (best[0], best[1]) if best else None


def map_refused(map_path):
    """Whether the map predates the unrecorded list: the impact tool refuses it, so it is no usable map (E5's refresh
    rebuilds it). A map that cannot be read at all is refused too."""
    try:
        with gzip.open(map_path, "rt") as handle:
            document = json.load(handle)
    except (OSError, ValueError):
        return True
    return "unrecorded" not in document


def refused_map(store, map_path, select_only):
    """Answer a refused map as no map: one line, a refresh of main when the refresh rules allow one, and the no-map
    path (`scripts/affected_tests.py`). Returns the exit status."""
    running = edit_check_refresh.lock_held(store)
    log = None
    if not running and edit_check_refresh.refresh_allowed(store, select_only):
        log = edit_check_refresh.start_detached(store, edit_check_refresh.DEFAULT_REF)
    if running:
        action = "a refresh is running"
    elif log:
        action = "started a refresh of main (log %s)" % log
    else:
        action = "no refresh is running; python3 scripts/edit_check_refresh.py starts one"
    print("edit check: the coverage map %s predates the unrecorded list and is not used; %s; running scripts/affected_tests.py instead"
          % (os.path.basename(map_path), action), flush=True)
    if select_only:
        return 0
    return subprocess.call([sys.executable, os.path.join(ROOT, "scripts", "affected_tests.py")], cwd=ROOT)


def map_commit(map_path):
    """The commit a coverage map was recorded at (its file name), or None for a name that does not carry one."""
    match = re.fullmatch(r"coverage-([0-9a-f]{7,40})\.json\.gz", os.path.basename(map_path))
    return match.group(1) if match else None


def run_step(step, log):
    """Run one build step through a build slot, with its output under `log`; the exit status."""
    zig = os.environ.get("ZIG") or "zig"
    with open(os.path.join(log, "run-step-%s.log" % step), "w") as handle:
        return subprocess.run([os.path.join(ROOT, "scripts", "build-slot.sh"), "build", zig, "build", step], cwd=ROOT,
                              stdout=handle, stderr=subprocess.STDOUT).returncode


def build(args):
    """Build the compiler, the test binaries and the impact tool, through build slots, with the gate's registry guard
    (`test-verification-registry`, which fails while a gate action is unregistered)."""
    started = time.monotonic()
    zig = os.environ.get("ZIG") or "zig"
    # One invocation: each admission costs a settle interval and each `zig build` its own configure (A-1, A-3).
    slot(zig, "build", "install", "edit-check-binaries", "edit-check-impact", "test-verification-registry")
    return time.monotonic() - started


def finding_line(name, findings):
    """The one line printed when a cheap check's findings arrive: the check, the first finding and how many more."""
    first = findings[0]
    text = first.message if not first.location or first.message.startswith(first.location) \
        else "%s: %s" % (first.location, first.message)
    more = " (and %d more)" % (len(findings) - 1) if len(findings) > 1 else ""
    return ("edit check: cheap check %s failed; the tests still run: %s%s" % (name, text, more))[:300]


def closing_lines(summary, findings, failures, time_line, printed):
    """The edit check's closing lines within its 20-line bound: the selection and run lines, the cheap checks'
    findings again (each check's first), the failures (the cheap checks among them), the times and the verdict line.
    `printed` is how many lines were already printed (the findings as they arrived)."""
    cheap = [] if not findings else gate_cheap_checks.summary_lines(findings, 6)
    if findings:
        failures = ["cheap checks (%s)" % ", ".join(sorted({finding.check for finding in findings}))] + failures
    room = max(0, 20 - printed - len(cheap) - 3)
    return (summary[:min(17, room)] + cheap + ["failures: " + (", ".join(failures) if failures else "none"), time_line,
            FAIL_LINE if failures else GATE_LINE])


def list_names(binary_dir):
    """The current test names of each binary, by root; the guest files are named by their paths."""
    names = {}
    for root, binary in BINARIES.items():
        names[root] = edit_check_collect.list_tests(os.path.join(binary_dir, binary), ROOT)
    names[GUESTS] = edit_check_collect.guest_files(ROOT)
    return names


# The engine's checks in the guest runs (docs/tooling/engine.md): verify mode samples one served query in 16, and the shadow
# appends its disagreements to the per-user log (`@user`), the one the shadow period reads across worktrees. Both are
# placement variables: they change no result. The Zig test binaries do not get them.
ENGINE_GUEST_ENVIRONMENT = {"SELKA_ENGINE_VERIFY": "16", "SELKA_ENGINE_SHADOW_LOG": "@user"}
# A run of the edit check may name itself: the shadow writes this as `tag` on its lines, so a shared log can be read per run.
ENGINE_TAG = "SELKA_ENGINE_SHADOW_TAG"


def test_environment(scratch):
    """The environment the test binaries run in, as the coverage collector sets it, without coverage keys."""
    env = {k: v for k, v in os.environ.items() if k in ("PATH", "HOME", "LANG", "USER", "ZIG_GLOBAL_CACHE_DIR", "TMPDIR")}
    env.update({
        "SELKA_TEST_COMPILER": os.path.join(ROOT, "zig-out", "bin", "selka"),
        "SELKA_ZIG": os.environ.get("ZIG", "zig"),
        "SELKA_COMPONENT_DIR": os.path.join(ROOT, "zig-out", "libexec", "selka", "components"),
        "SELKA_TEST_COMPONENT_BUILDER": os.path.join(ROOT, "zig-out", "tools", "selka-components"),
        "SELKA_COMPILER_SHARED_CACHE": "",
        "SELKA_TEST_SHARED_CACHE": "",
        "SELKA_STAGE_SHARED_CACHE": "",
        "ZIG_LOCAL_CACHE_DIR": os.path.join(scratch, "zig-local"),
    })
    return env


def expected_seconds(names, recorded, unnamed, default=DEFAULT_TEST_SECONDS):
    """The expected seconds of each item of one selection, as {item: seconds}.

    An item's own record from an earlier run wins; otherwise it is the mean of the recorded items among NAMES, or
    DEFAULT when none is recorded. The unnamed blocks are one item, weighed by their own record.
    """
    known = [recorded[name] for name in names if name in recorded]
    fallback = sum(known) / len(known) if known else default
    weights = {name: recorded.get(name, fallback) for name in names}
    if unnamed:
        weights[UNNAMED] = recorded.get(UNNAMED, fallback)
    return weights


def pack_longest_first(weights, count):
    """Split the items of WEIGHTS ({item: seconds}) into at most COUNT non-empty lists, longest processing time first.

    Items go in order of decreasing weight (ties by name), each into the list with the least seconds so far. Returns
    [(seconds, items)] heaviest first; every item appears in exactly one list.
    """
    lists = [[] for _ in range(max(1, min(count, len(weights))))]
    loads = [0.0] * len(lists)
    for item in sorted(weights, key=lambda name: (-weights[name], name)):
        index = loads.index(min(loads))
        lists[index].append(item)
        loads[index] += weights[item]
    packed = [(loads[index], sorted(items)) for index, items in enumerate(lists) if items]
    return sorted(packed, key=lambda entry: -entry[0])


def guest_plan(chosen, every, selka):
    """The guest jobs for the selected guest files: none when none is selected; one directory run when every guest
    file is (or the map has no guest root, so all are new); otherwise one `selka test FILE` process per file.
    A job is (root, label, binary, argv); binary None marks a guest job, whose argv runs as it is."""
    if not chosen:
        return []
    if len(chosen) == len(every):
        return [(GUESTS, "guests", None, [selka, "test", GUEST_DIRECTORY])]
    return [(GUESTS, "guests-%d" % index, None, [selka, "test", name]) for index, name in enumerate(chosen)]


def plan_guests(chosen, every, selka, recorded, directory_seconds):
    """The guest jobs of one run as [(seconds, GUESTS, label, argv)], each with its expected seconds.

    CHOSEN are the selected guest files and EVERY all of them. A file's expected seconds are its record in RECORDED
    ({path: seconds}), or the mean of the recorded selected files, or GUEST_FILE_SECONDS; the directory run takes
    DIRECTORY_SECONDS. The jobs run every selected file exactly once (checked here).
    """
    weights = expected_seconds(chosen, recorded, False, GUEST_FILE_SECONDS)
    planned = []
    covered = []
    for root, label, _binary, argv in guest_plan(chosen, every, selka):
        if argv[-1] == GUEST_DIRECTORY:
            seconds = directory_seconds
            covered.extend(every)
        else:
            seconds = weights[argv[-1]]
            covered.append(argv[-1])
        planned.append((seconds, root, label, argv))
    if sorted(covered) != sorted(chosen):
        raise RuntimeError("guest jobs do not run the selected guest files exactly once")
    return planned


def plan_jobs(chosen, unnamed, recorded, width, chunk_seconds, guests):
    """The jobs of one run as [(seconds, root, label, part)], longest first.

    CHOSEN maps each binary to its sorted named selection and UNNAMED to whether its unnamed blocks run. GUESTS holds
    the guest jobs of plan_guests (their part is the argv). A binary splits into ceil(expected seconds / chunk_seconds)
    chunks, at most MAX_CHUNKS_PER_SLOT per job slot, each chunk packed by pack_longest_first. The chunks of all
    binaries together are their selection, exactly once (checked here).
    """
    jobs_planned = list(guests)
    for root in BINARIES:
        if not chosen[root] and not unnamed[root]:
            continue
        weights = expected_seconds(chosen[root], recorded.get(root, {}), unnamed[root])
        total = sum(weights.values())
        count = min(MAX_CHUNKS_PER_SLOT * width, max(1, math.ceil(total / chunk_seconds)))
        packed = pack_longest_first(weights, count)
        covered = sorted(item for _, part in packed for item in part)
        if covered != sorted(weights):
            raise RuntimeError("chunks of %s do not partition its selection" % root)
        for index, (seconds, part) in enumerate(packed):
            jobs_planned.append((seconds, root, "%s-%d" % (root, index), part))
    return sorted(jobs_planned, key=lambda job: (-job[0], job[2]))


WALL_LINE = re.compile(r"test: test wall (\d+)\.(\d{2})s")
REPORT_ROW = re.compile(r"test: +(\d+)\.(\d{2})s  (.+)$")


def seconds_of(whole, hundredths):
    """Seconds from Guardian's whole seconds and centiseconds."""
    return int(whole) + int(hundredths) / 100


def parse_report(text):
    """(test wall seconds or None, {test name: seconds}) from one binary's log, read from Guardian's wide report.

    The wide report (SELKA_TEST_TIMINGS) lists the slowest tests over 1 ms, after the `test wall` line. Its rows
    are the only per-test times a run prints; a log without the wall line is a run that did not finish its report.
    """
    wall = None
    listed = {}
    for line in text.splitlines():
        if wall is None:
            match = WALL_LINE.match(line)
            if match:
                wall = seconds_of(*match.groups())
            continue
        match = REPORT_ROW.match(line)
        if match:
            listed[match.group(3)] = seconds_of(match.group(1), match.group(2))
    return wall, listed


def record_runs(recorded, finished):
    """Fold the finished Zig chunks into RECORDED ({root: {name: seconds}}, updated in place).

    FINISHED holds (root, part, log_path). A named test the report lists keeps its time; one it does not list ran
    under the 1 ms floor, unless the report is full (WIDE_LINES rows), in which case its old record stays. The unnamed
    blocks take the test wall minus the listed times, when the report is not full.
    """
    for root, part, log_path in finished:
        with open(log_path, errors="replace") as handle:
            wall, listed = parse_report(handle.read())
        if wall is None:
            continue
        table = recorded.setdefault(root, {})
        full = len(listed) >= WIDE_LINES
        named_listed = sum(listed.get(name, 0.0) for name in part if name != UNNAMED)
        for name in part:
            if name == UNNAMED:
                if not full:
                    table[UNNAMED] = max(0.0, wall - named_listed)
            elif name in listed:
                table[name] = listed[name]
            elif not full:
                table[name] = FLOOR_SECONDS
    return recorded


def record_guest_runs(durations, finished):
    """Fold the finished guest jobs into DURATIONS (updated in place); FINISHED holds (argv, seconds) per job.

    A file's job records its wall under tests[GUESTS][path]; the directory run records jobs[GUESTS].
    """
    for argv, seconds in finished:
        if argv[-1] == GUEST_DIRECTORY:
            durations["jobs"][GUESTS] = seconds
        else:
            durations["tests"].setdefault(GUESTS, {})[argv[-1]] = seconds
    return durations


def load_durations(store):
    """The durations store ({"tests": {root: {name: seconds}}, "jobs": {label: seconds}}); empty when absent or unreadable.

    The store only sets the order of the jobs, never which tests run, so an unreadable file falls back to defaults.
    """
    empty = {"tests": {}, "jobs": {}}
    try:
        with open(os.path.join(store, DURATIONS_FILE)) as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return empty
    if not isinstance(data, dict) or data.get("format") != DURATIONS_FORMAT:
        return empty

    def seconds_table(value):
        """The entries of VALUE that are names with numeric seconds; anything else is dropped."""
        if not isinstance(value, dict):
            return {}
        return {key: float(item) for key, item in value.items()
                if isinstance(key, str) and isinstance(item, (int, float)) and not isinstance(item, bool)}

    tests = data.get("tests") if isinstance(data.get("tests"), dict) else {}
    return {"tests": {root: seconds_table(table) for root, table in tests.items() if root in BINARIES or root == GUESTS},
            "jobs": seconds_table(data.get("jobs"))}


def save_durations(store, durations):
    """Write the durations store atomically (a temporary file, then a rename)."""
    os.makedirs(store, exist_ok=True)
    body = dict(durations, format=DURATIONS_FORMAT)
    temporary = os.path.join(store, DURATIONS_FILE + ".%d.tmp" % os.getpid())
    with open(temporary, "w") as handle:
        json.dump(body, handle, sort_keys=True)
    os.replace(temporary, os.path.join(store, DURATIONS_FILE))


def start_selection(binary, names, log_path, env):
    """Start one binary on the exact names (and the unnamed blocks when listed); return the process and its log."""
    listing = log_path + ".list"
    with open(listing, "w") as handle:
        handle.write("\n".join(names) + "\n")
    command = [binary, "--test-list=" + listing, "--cache-dir=" + log_path + ".fuzz-cache"]
    log = open(log_path, "w")
    return subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT), log


def chunk_environment(env, scratch, label):
    """ENV with a TMPDIR and Zig cache of its own, as each gate shard has."""
    own = dict(env)
    for key, leaf in (("TMPDIR", "tmp"), ("ZIG_LOCAL_CACHE_DIR", "zig-local")):
        path = os.path.join(scratch, label, leaf)
        os.makedirs(path, exist_ok=True)
        own[key] = path
    return own


def selka_binary():
    """The compiler the guest files run with: the installed one."""
    return os.path.join(ROOT, "zig-out", "bin", "selka")


def jobs():
    """How many test processes run at once: SELKA_JOBS, else the CPUs this process may use."""
    configured = os.environ.get("SELKA_JOBS", "")
    if configured.isdigit() and int(configured) > 0:
        return int(configured)
    return max(1, len(os.sched_getaffinity(0)))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--map", help="coverage map to use (default: the newest ancestor of HEAD in the store)")
    parser.add_argument("--store", help="map store (default $SELKA_EDIT_CHECK_STORE or ~/.cache/selka/edit-check)")
    parser.add_argument("--importers", choices=("direct", "closure", "reexport", "none"), default="reexport")
    parser.add_argument("--select-only", action="store_true", help="print the selection and run nothing")
    parser.add_argument("--no-guests", action="store_true", help="leave the guest suite out")
    parser.add_argument("--log", help="directory for logs (default: <TMPDIR>/edit-check/<time>)")
    parser.add_argument("--chunk-seconds", type=float, default=CHUNK_SECONDS,
                        help="expected seconds of test work per Zig chunk (default %(default)s)")
    args = parser.parse_args()
    if not args.chunk_seconds > 0:
        parser.error("--chunk-seconds must be positive")

    if "TMPDIR" not in os.environ:
        sys.exit("TMPDIR must name a directory on disk: source ~/.config/selka/dev-env.sh first")
    head = git("rev-parse", "HEAD")
    log = args.log or os.path.join(os.environ["TMPDIR"], "edit-check", time.strftime("%Y%m%d-%H%M%S"))
    os.makedirs(log, exist_ok=True)
    scratch = os.path.join(log, "scratch")
    os.makedirs(scratch, exist_ok=True)

    if args.map:
        map_path = args.map
        if map_refused(map_path):
            return refused_map(store_dir(args), map_path, args.select_only)
    else:
        found = newest_map(store_dir(args), head)
        if found is not None and map_refused(found[0]):
            return refused_map(store_dir(args), found[0], args.select_only)
        note = edit_check_refresh.staleness_note(store_dir(args), found[1] if found else None, args.select_only)
        if note:
            print(note, flush=True)
        if found is None:
            print("edit check: no coverage map at or before HEAD; running scripts/affected_tests.py instead", flush=True)
            if args.select_only:
                return 0
            return subprocess.call([sys.executable, os.path.join(ROOT, "scripts", "affected_tests.py")], cwd=ROOT)
        map_path = found[0]

    # A refresh's prune leaves a map this run holds alone; the handle stays open until the process exits.
    held = edit_check_refresh.hold_map(map_path)  # noqa: F841
    timings = {}
    # The gate's cheap checks (DL-4 item 4a): those that need no compiler beside the build, the compiler's two after
    # it. A finding is printed when it arrives and fails the edit check at its end; the build and the tests still run
    # (D-DL4-8: an agent mid-change keeps its test results), unlike the gate, which stops before any test.
    printed = [0]
    cheap = None
    if not args.select_only:
        cheap = gate_cheap_checks.Runner(gate_cheap_checks.Context(root=gate_cheap_checks.ROOT,
                                                                   zig=os.environ.get("ZIG") or "zig",
                                                                   env=dict(os.environ)))

        def arrived(name, findings):
            print(finding_line(name, findings), flush=True)
            printed[0] += 1
        cheap.on_finding = arrived
        cheap.start([name for name in gate_cheap_checks.CHECKS
                     if name != "registry" and name not in gate_cheap_checks.COMPILER_CHECKS])
    timings["build"] = build(args)
    if cheap is not None:
        cheap.context.compiler = selka_binary()
        cheap.start(gate_cheap_checks.COMPILER_CHECKS)
    if not os.path.exists(os.path.join(ROOT, "zig-out", "edit-check", "test-list-supported")):
        print("edit check: this Guardian runner has no --test-list option (its build marker is missing)", flush=True)
        return 2
    binary_dir = os.path.join(ROOT, "zig-out", "edit-check")
    started = time.monotonic()
    names = list_names(binary_dir)
    timings["list"] = time.monotonic() - started
    tests_dir = os.path.join(log, "tests")
    os.makedirs(tests_dir, exist_ok=True)
    for root, listed in names.items():
        with open(os.path.join(tests_dir, "tests-%s.json" % root), "w") as handle:
            json.dump(listed, handle)

    impact_out = os.path.join(log, "impact.txt")
    selection_path = os.path.join(log, "selection.tsv")
    impact = [os.path.join(ROOT, "zig-out", "tools", "edit-check-impact"), "--map", map_path, "--repo", ROOT,
              "--importers", args.importers, "--tests", tests_dir, "--selection", selection_path]
    started = time.monotonic()
    with open(impact_out, "w") as handle:
        impact_status = subprocess.run(impact, cwd=ROOT, stdout=handle, stderr=subprocess.STDOUT).returncode
    timings["impact"] = time.monotonic() - started
    if impact_status == REFUSED_MAP_STATUS:
        return refused_map(store_dir(args), map_path, args.select_only)
    if impact_status:
        print("edit check: the impact tool failed (exit %d; its output is in %s)" % (impact_status, impact_out), flush=True)
        return 2
    summary = []
    try:
        steps = driver_steps(changed_paths(map_commit(map_path) or head))
    except subprocess.CalledProcessError:
        steps = []
        summary.append("steps: none (the changed paths could not be listed since the map's commit)")
    if steps:
        summary.append(step_line(steps))
    unrouted = 0
    with open(impact_out) as handle:
        for line in handle:
            if line.startswith(("edit-check-impact:", "everything:", "note:", "selected ")):
                summary.append(line.rstrip())
            elif line.startswith("unrouted "):
                unrouted += 1
    if unrouted:
        summary.append("unrouted: %d changed files that no Zig test reads (listed in %s)" % (unrouted, impact_out))
    if args.select_only:
        for line in summary:
            print(line)
        print("selection file: " + selection_path)
        return 0

    selected = {root: {"named": [], "unnamed": False} for root in list(BINARIES) + [GUESTS]}
    with open(selection_path) as handle:
        for line in handle:
            root, kind, name, _reason = (line.rstrip("\n").split("\t") + ["", ""])[:4]
            if root not in selected:
                continue
            if kind == "unnamed":
                selected[root]["unnamed"] = True
            elif name in set(names[root]):
                selected[root]["named"].append(name)
    env = test_environment(scratch)
    failures = []
    started = time.monotonic()
    # Every job (the Zig chunks and the guest jobs) is planned with its expected seconds and run longest first, at
    # most jobs() at a time, so the cores stay busy until the last job ends (E3).
    width = jobs()
    counts = {}
    chosen = {}
    for root in BINARIES:
        chosen[root] = sorted(set(selected[root]["named"]))
        if not chosen[root] and not selected[root]["unnamed"]:
            summary.append("ran %s: none selected" % root)
            continue
        counts[root] = (len(chosen[root]), selected[root]["unnamed"])
    store = store_dir(args)
    durations = load_durations(store)
    guest_names = sorted(set(selected[GUESTS]["named"]))
    guests = [] if args.no_guests else plan_guests(guest_names, names[GUESTS], selka_binary(),
                                                  durations["tests"].get(GUESTS, {}),
                                                  durations["jobs"].get(GUESTS, GUEST_SECONDS))
    if not args.no_guests and not guests:
        summary.append("ran guests: none selected")
    directory_run = any(job[3][-1] == GUEST_DIRECTORY for job in guests)
    planned = plan_jobs(chosen, {root: selected[root]["unnamed"] for root in BINARIES}, durations["tests"], width,
                        args.chunk_seconds, guests)
    pending = [(root, label, None if root == GUESTS else os.path.join(binary_dir, BINARIES[root]), part)
               for _seconds, root, label, part in planned]
    recorded_names = sum(1 for root in counts for name in chosen[root] if name in durations["tests"].get(root, {}))
    summary.append("scheduled %d jobs (%d guest jobs; %d of %d named Zig tests with a recorded time), longest first" % (
        len(pending), len(guests), recorded_names, sum(len(chosen[root]) for root in counts)))
    running = []
    codes = {}
    finished = []
    timeline = []
    while pending or running:
        while pending and len(running) < width:
            root, label, binary, part = pending.pop(0)
            own = chunk_environment(env, scratch, label)
            log_path = os.path.join(log, "run-%s.log" % label)
            if binary is None:
                own.update(ENGINE_GUEST_ENVIRONMENT)
                if os.environ.get(ENGINE_TAG):
                    own[ENGINE_TAG] = os.environ[ENGINE_TAG]
                handle = open(log_path, "w")
                process = subprocess.Popen(part, cwd=ROOT, env=own, stdout=handle, stderr=subprocess.STDOUT)
            else:
                own["SELKA_TEST_TIMINGS"] = "1"  # the wide report: the per-test times the next run schedules by
                process, handle = start_selection(binary, part, log_path, own)
            running.append((root, process, handle, label, part, time.monotonic() - started))
        still = []
        for root, process, handle, label, part, begun in running:
            code = process.poll()
            if code is None:
                still.append((root, process, handle, label, part, begun))
                continue
            handle.close()
            ended = time.monotonic() - started
            if root == GUESTS:
                code = 0 if code == GUEST_NO_ENTRIES else code
            items = (len(names[GUESTS]) if part[-1] == GUEST_DIRECTORY else 1) if root == GUESTS else len(part)
            timeline.append((label, items, begun, ended, code))
            finished.append((root, label, part, begun, ended))
            codes[root] = codes.get(root, 0) or code
        if len(still) == len(running):
            time.sleep(0.05)
        running = still
    with open(os.path.join(log, "run-timeline.tsv"), "w") as handle:
        handle.write("label\titems\tstart_s\tend_s\texit\n")
        for label, size, begun, ended, code in timeline:
            handle.write("%s\t%d\t%.3f\t%.3f\t%d\n" % (label, size, begun, ended, code))
    # The next run schedules by what this one measured: each Zig chunk's wide report and each guest job's wall.
    record_runs(durations["tests"], [(root, part, os.path.join(log, "run-%s.log" % label))
                                     for root, label, part, _begun, _ended in finished if root != GUESTS])
    record_guest_runs(durations, [(part, ended - begun) for root, _label, part, begun, ended in finished
                                  if root == GUESTS])
    try:
        save_durations(store, durations)
    except OSError as error:
        print("edit check: durations not recorded (%s)" % error, file=sys.stderr)
    for step, _paths in steps:
        code = run_step(step, log)
        summary.append("ran step %s: exit %d" % (step, code))
        if code:
            failures.append(step)
    for root, (named, unnamed) in counts.items():
        summary.append("ran %s: %d named, unnamed %s, exit %d" % (root, named, "yes" if unnamed else "no", codes.get(root, 0)))
        if codes.get(root, 0) != 0:
            failures.append(root)
    if guests:
        if directory_run:
            summary.append("ran guests: all %d files, one directory run, exit %d" % (len(names[GUESTS]), codes.get(GUESTS, 0)))
        else:
            summary.append("ran guests: %d of %d files, one process each, exit %d" % (
                len(guest_names), len(names[GUESTS]), codes.get(GUESTS, 0)))
        if codes.get(GUESTS, 0) != 0:
            failures.append(GUESTS)
    timings["guests"] = max([ended for root, _label, _part, _begun, ended in finished if root == GUESTS] or [0.0])
    timings["run"] = time.monotonic() - started

    findings = []
    if cheap is not None:
        findings = cheap.wait()
        if cheap.abandoned:
            summary.append("cheap checks %s passed their deadline and decide nothing" % ", ".join(cheap.abandoned))
    time_line = "time: build %.0f s, list %.0f s, impact %.0f s, run %.0f s (guests done at %.0f s); logs in %s" % (
        timings["build"], timings["list"], timings["impact"], timings["run"], timings["guests"], log)
    for line in closing_lines(summary, findings, failures, time_line, printed[0]):
        print(line)
    return 1 if failures or findings else 0


if __name__ == "__main__":
    sys.exit(main())
