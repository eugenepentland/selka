#!/usr/bin/env python3
"""Keep the edit check's coverage map current with main (E5).

    python3 scripts/edit_check_refresh.py [--ref REF]   start a detached refresh and return at once
    python3 scripts/edit_check_refresh.py --once         the same work in the foreground
    python3 scripts/edit_check_refresh.py --status       the refresh's state and its recent events
    python3 scripts/edit_check_refresh.py --prune        remove the maps beyond the newest MAPS_KEPT, now

The coordinator runs the first form after each landing. The edit check starts one too when main has no map and
the map it would use is more than STALE_COMMITS commits behind main (`scripts/edit_check.py` prints the line).

A refresh maps REF's head (main by default):

1. checks the head out in the refresh worktree (`<parent of this checkout>/mylang-map-refresh`, claimed with
   `git worktree lock`) and builds the instrumented compiler and the map tool in one `build` admission;
2. lists each root's tests and runs them in batches of about BATCH_SECONDS. Each batch is one short `build`
   admission at low CPU and I/O priority; before a batch the refresh waits while a `gate` or `timing` request is
   queued;
3. merges the batches into one run directory per collection run and runs `edit-check-tool map` on them;
4. publishes the map atomically, unless it has a failed test. A refused or failed refresh leaves the maps as they were.
   A published map is followed by a prune: the store keeps the newest MAPS_KEPT maps (by commit time) and removes the
   rest, except one a running edit check holds (it keeps a shared lock on the file, `hold_map`).

A head that moves during a refresh cancels it at the next batch boundary, and the worker maps the new head. One
worker runs at a time (a lock in the map store). Developer tool: not part of the install graph or the gate.
"""
import argparse
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import edit_check_collect  # noqa: E402  (test listing protocol, shared with the collector)
import edit_check_map  # noqa: E402  (the map's failed-test refusal)

DEFAULT_REF = "main"
ROOTS = tuple(edit_check_collect.ROOTS)
RUNS = 2
# The run whose batches and guest phase trace their execs (its list is the refresh's unrecorded list; see merge_unrecorded).
TRACED_RUN = 1
JOBS = 8
BATCH_SECONDS = 60.0
INITIAL_BATCH = 150
MIN_BATCH = 10
MAX_BATCH = 2000
YIELD_POLL = 5.0
STALE_COMMITS = 5
# Finished maps the store keeps (2.4 to 6.1 MB each): enough for the lanes that branch from the last few landings.
MAPS_KEPT = 5
MAP_NAME = re.compile(r"coverage-([0-9a-f]{7,40})\.json\.gz")
NICE = ["nice", "-n", "19", "ionice", "-c3"]
ADMISSION_LINE = re.compile(r"^build-slot: build slot \d+, FIFO ticket \d+ after ([0-9.]+)s")


class BatchFailed(RuntimeError):
    """A batch's collection process exited with an error."""


class MergeError(RuntimeError):
    """Batches of one run cannot be merged: their test lists differ, or a hit set name repeats."""


def store_dir():
    """The map store: $SELKA_EDIT_CHECK_STORE, else ~/.cache/selka/edit-check."""
    return os.environ.get("SELKA_EDIT_CHECK_STORE") or os.path.expanduser("~/.cache/selka/edit-check")


def state_dir(store):
    """The refresh's own files in the map store: lock, status, events, attempts, logs, the worker log."""
    return os.path.join(store, "refresh")


def refresh_dir():
    """The refresh worktree: $SELKA_MAP_REFRESH_DIR, else a sibling of this checkout named mylang-map-refresh."""
    return os.environ.get("SELKA_MAP_REFRESH_DIR") or os.path.join(os.path.dirname(ROOT), "mylang-map-refresh")


def map_path(store, commit):
    """Where the finished map of COMMIT lives."""
    return os.path.join(store, "coverage-%s.json.gz" % commit)


def hold_map(path):
    """An open handle holding a shared lock on the map at PATH, for as long as the caller keeps it open, or None when the
    map cannot be opened. A running edit check holds its map this way; `prune_maps` leaves a held map alone."""
    try:
        handle = open(path, "rb")
    except OSError:
        return None
    fcntl.flock(handle, fcntl.LOCK_SH)
    return handle


def commit_time(commit, fallback):
    """When COMMIT was made (seconds since the epoch), or FALLBACK when this checkout does not know the commit."""
    found = subprocess.run(["git", "-C", ROOT, "log", "-1", "--format=%ct", commit], capture_output=True, text=True)
    try:
        return int(found.stdout.strip()) if found.returncode == 0 else fallback
    except ValueError:
        return fallback


def remove_unless_held(path):
    """Remove the map at PATH unless a running edit check holds it. True when it was removed."""
    try:
        handle = open(path, "rb")
    except OSError:
        return False
    with handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return False
        try:
            os.remove(path)
        except OSError:
            return False
    return True


def prune_maps(store, keep=MAPS_KEPT, protect=()):
    """Remove the finished maps in STORE beyond the newest KEEP, newest by the time of the commit each was made for (the
    file's own time when the commit is unknown here). The commits in PROTECT stay, and so does a map a running edit check
    holds (`hold_map`). Files that are not finished maps (the refresh's own directory, durations, the shadow log) are never
    touched. Returns the commits whose maps were removed, newest first."""
    found = []
    try:
        names = os.listdir(store)
    except OSError:
        return []
    for name in names:
        match = MAP_NAME.fullmatch(name)
        if not match:
            continue
        path = os.path.join(store, name)
        try:
            stamp = int(os.path.getmtime(path))
        except OSError:
            continue
        found.append((commit_time(match.group(1), stamp), match.group(1), path))
    found.sort(reverse=True)
    removed = []
    for _when, commit, path in found[keep:]:
        if commit in protect:
            continue
        if remove_unless_held(path):
            removed.append(commit)
    return removed


def git(*args, cwd=None):
    """Standard output of a git command in CWD (default: this checkout), stripped; raises when git fails."""
    return subprocess.check_output(["git", "-C", cwd or ROOT, *args], text=True).strip()


def resolve(ref):
    """The full commit id REF names."""
    return git("rev-parse", "--verify", "-q", ref + "^{commit}")


def is_ancestor(older, newer):
    """Whether commit OLDER is an ancestor of (or equal to) NEWER."""
    return subprocess.run(["git", "-C", ROOT, "merge-base", "--is-ancestor", older, newer]).returncode == 0


def commits_behind(map_commit, ref):
    """How many commits REF has after MAP_COMMIT, or None when the map is not an ancestor of REF."""
    if not is_ancestor(map_commit, ref):
        return None
    return int(git("rev-list", "--count", "%s..%s" % (map_commit, ref)))


def try_lock(path):
    """An open file holding an exclusive lock on PATH, or None when another process holds it."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    handle = open(path, "a")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()
        return None
    return handle


def lock_held(store):
    """Whether a refresh worker holds the lock."""
    handle = try_lock(os.path.join(state_dir(store), "refresh.lock"))
    if handle is None:
        return True
    handle.close()
    return False


def write_json(path, value):
    """Replace PATH with VALUE as JSON, atomically."""
    temporary = "%s.tmp-%d" % (path, os.getpid())
    with open(temporary, "w") as handle:
        json.dump(value, handle, indent=1, sort_keys=True)
    os.replace(temporary, path)


def read_json(path, default):
    """The JSON value in PATH, or DEFAULT when it is missing or unreadable."""
    try:
        with open(path) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return default


def loadavg():
    """The one-minute load average, as a string."""
    with open("/proc/loadavg") as handle:
        return handle.read().split()[0]


def record(store, kind, **fields):
    """Append one event to the refresh's events file (the evidence of every admission wait)."""
    os.makedirs(state_dir(store), exist_ok=True)
    row = dict(kind=kind, time=round(time.time(), 3), pid=os.getpid(), load=loadavg(), **fields)
    with open(os.path.join(state_dir(store), "events.jsonl"), "a") as handle:
        handle.write(json.dumps(row, sort_keys=True) + "\n")


def set_status(store, **fields):
    """Merge FIELDS into the refresh's status file."""
    path = os.path.join(state_dir(store), "status.json")
    write_json(path, dict(read_json(path, {}), updated=round(time.time(), 3), **fields))


def note_outcome(store, target, outcome):
    """Remember the outcome of a refresh of TARGET (the last 50), so the edit check does not retry a refused map."""
    path = os.path.join(state_dir(store), "attempts.json")
    attempts = [entry for entry in read_json(path, []) if entry[0] != target]
    write_json(path, (attempts + [[target, outcome]])[-50:])


def refused_before(store, target):
    """Whether a refresh of TARGET ended in a refusal or a failure."""
    return any(entry[0] == target and entry[1] in ("refused", "failed") for entry in read_json(os.path.join(state_dir(store), "attempts.json"), []))


def slot_script():
    """This checkout's admission wrapper."""
    return os.path.join(ROOT, "scripts", "build-slot.sh")


def admission_wait(log_path):
    """The seconds the admission in LOG_PATH waited, from its first `build-slot:` line, or None."""
    with open(log_path, errors="replace") as handle:
        for line in handle:
            match = ADMISSION_LINE.match(line)
            if match:
                return float(match.group(1))
    return None


def output_wrapped(command, output):
    """COMMAND with its standard output and error sent to OUTPUT by a shell that execs it.

    The admission wrapper writes its `build-slot:` line to the log it is given. A command that writes positionally
    (the map tool does) would overwrite that line, so the command writes to a file of its own.
    """
    return ["sh", "-c", 'out=$1; shift; exec "$@" >"$out" 2>&1', "sh", output, *command]


def admitted(repo, command, log_path, env):
    """Run COMMAND in one `build` admission at low priority; the admission's line goes to LOG_PATH.

    Returns (exit code, admission wait in seconds or None, total seconds including the wait).
    """
    started = time.monotonic()
    with open(log_path, "w") as log:
        code = subprocess.run([slot_script(), "build", *NICE, *output_wrapped(command, log_path + ".out")], cwd=repo,
                              env=env, stdout=log, stderr=subprocess.STDOUT).returncode
    return code, admission_wait(log_path), time.monotonic() - started


def busy_lines(status_text):
    """The gate and timing queue lines of `build-slot.sh status`: requests a refresh batch must not delay."""
    return [line for line in status_text.splitlines() if line.startswith(("gate queue", "timing queue"))]


def queued_gate_or_timing():
    """The gate and timing requests waiting for admission right now."""
    out = subprocess.run([slot_script(), "status"], cwd=ROOT, capture_output=True, text=True).stdout
    return busy_lines(out)


def wait_while_queued(store, label):
    """Wait, before a batch is requested, while a gate or timing request is queued; return the seconds waited."""
    waited = 0.0
    queued = queued_gate_or_timing()
    if queued:
        record(store, "yield", label=label, queued=queued)
    while queued:
        time.sleep(YIELD_POLL)
        waited += YIELD_POLL
        queued = queued_gate_or_timing()
    return waited


class BatchSizer:
    """Tests per batch of one root: the count that takes about SECONDS at the smoothed rate of its batches.

    The rate is an average of the batches so far (half the weight on the newest), so one slow batch does not
    dominate. The size may at most double per batch, and shrinks at once, so a batch that ran long is followed by
    a smaller one.
    """

    def __init__(self, seconds=BATCH_SECONDS, initial=INITIAL_BATCH, low=MIN_BATCH, high=MAX_BATCH):
        self.seconds, self.low, self.high = seconds, low, high
        self.count = initial
        self.rate = None

    def size(self):
        """The number of tests the next batch should take."""
        return self.count

    def observe(self, tests, seconds):
        """Adjust the size to a batch that ran TESTS tests in SECONDS."""
        if tests <= 0 or seconds <= 0:
            return
        rate = tests / seconds
        self.rate = rate if self.rate is None else 0.5 * self.rate + 0.5 * rate
        wanted = round(self.rate * self.seconds)
        self.count = max(self.low, min(self.high, 2 * self.count, wanted))


def run_batches(names_by_root, sizer_for, run_batch, cancelled):
    """Hand every root's test names to RUN_BATCH in batches of SIZER_FOR(root)'s size.

    RUN_BATCH(root, batch, first) returns the seconds the batch ran; FIRST is true for a root's first batch of the run,
    which also runs the root's unnamed blocks. Checks CANCELLED() before each batch. Returns "done" or "cancelled".
    """
    for root, names in names_by_root.items():
        sizer = sizer_for(root)
        position, first = 0, True
        while first or position < len(names):
            if cancelled():
                return "cancelled"
            batch = names[position:position + sizer.size()]
            position += len(batch)
            sizer.observe(len(batch), run_batch(root, batch, first))
            first = False
    return "done"


def merge_unrecorded(run_dir, batch_dirs):
    """Write RUN_DIR's unrecorded list: the union of its batches' lists (each batch's tests are its own, so the lists
    do not overlap). A run whose batches are all untraced is marked `{"traced": false}`; a mix is refused, because the
    list of a traced part would not cover the untraced tests."""
    tokens, untraced = set(), 0
    for directory in batch_dirs:
        value = read_json(os.path.join(directory, edit_check_collect.UNRECORDED_FILE), None)
        if isinstance(value, list):
            tokens.update(value)
        else:
            untraced += 1
    if untraced and tokens:
        raise MergeError("some batches of this run are traced and some are not")
    path = os.path.join(run_dir, edit_check_collect.UNRECORDED_FILE)
    write_json(path, {"traced": False} if untraced else sorted(tokens))


def merge_batches(run_dir, batches):
    """Merge BATCHES, (root, directory) pairs of one collection run, into RUN_DIR as one collection would write it.

    Hit sets move (each test is in one batch), results concatenate in batch order, the test list of a root must be
    the same in every batch of that root, and the unrecorded lists are united (`merge_unrecorded`).
    """
    os.makedirs(os.path.join(run_dir, "cov"))
    for root in ROOTS:
        parts = [directory for name, directory in batches if name == root]
        if not parts:
            continue
        listing = None
        with open(os.path.join(run_dir, "results-%s.jsonl" % root), "w") as results:
            for part in parts:
                with open(os.path.join(part, "tests-%s.json" % root)) as handle:
                    names = json.load(handle)
                if listing is not None and names != listing:
                    raise MergeError("the test list of %s differs between batches" % root)
                listing = names
                part_results = os.path.join(part, "results-%s.jsonl" % root)
                if os.path.exists(part_results):
                    with open(part_results) as handle:
                        shutil.copyfileobj(handle, results)
                covered = os.path.join(part, "cov")
                for token in (os.listdir(covered) if os.path.isdir(covered) else []):
                    target = os.path.join(run_dir, "cov", token)
                    if os.path.exists(target):
                        raise MergeError("two batches hold hit sets for %s" % token)
                    os.replace(os.path.join(covered, token), target)
        write_json(os.path.join(run_dir, "tests-%s.json" % root), listing)
    merge_unrecorded(run_dir, [directory for _, directory in batches])


def keep_results(work, logs):
    """Copy the result files of every run in WORK into LOGS, so a refused map's failures can be read afterwards."""
    os.makedirs(logs, exist_ok=True)
    for run in sorted(os.listdir(work)):
        run_dir = os.path.join(work, run)
        if not (run.startswith("run-") and os.path.isdir(run_dir)):
            continue
        for name in os.listdir(run_dir):
            if name.startswith("results-"):
                shutil.copy(os.path.join(run_dir, name), os.path.join(logs, "%s-%s" % (run, name)))


def publish_map(partial, final, failed):
    """Move PARTIAL to FINAL unless the map has failed tests; a refused PARTIAL is removed and FINAL stays as it was."""
    if failed:
        os.remove(partial)
        return False
    os.replace(partial, final)
    return True


def converge(head, has_map, refresh_once):
    """Map the head until a map exists for it; a head that moves during a refresh restarts it at the new head.

    HEAD() is the ref's commit, HAS_MAP(commit) says whether its map exists, REFRESH_ONCE(commit) returns the outcome
    ("published", "cancelled", "refused" or "failed"). Returns (outcome, commit); a refused or failed refresh is not
    retried by this loop.
    """
    while True:
        target = head()
        if has_map(target):
            return "fresh", target
        outcome = refresh_once(target)
        if outcome != "cancelled":
            return outcome, target


def worktree_locked(path):
    """Whether git has the worktree at PATH locked."""
    real = os.path.realpath(path)
    for block in git("worktree", "list", "--porcelain").split("\n\n"):
        lines = block.splitlines()
        if lines and lines[0] == "worktree " + real:
            return any(line == "locked" or line.startswith("locked ") for line in lines)
    return False


def zig_path(repo):
    """The pinned Zig: $ZIG, else the toolchain named by the checkout's .zigversion, else `zig`."""
    if os.environ.get("ZIG"):
        return os.environ["ZIG"]
    with open(os.path.join(repo, ".zigversion")) as handle:
        candidate = os.path.expanduser("~/zig-toolchains/%s/zig" % handle.read().strip())
    return candidate if os.path.exists(candidate) else "zig"


def worker_environment(repo):
    """The environment of the refresh's commands: the refresh worktree's own zig cache and temporary directory."""
    env = dict(os.environ)
    env["ZIG_LOCAL_CACHE_DIR"] = os.path.join(repo, ".zig-cache")
    env["TMPDIR"] = os.path.join(repo, ".tmp", "work")
    env["SELKA_ZIG_CACHE_CAP_GB"] = os.environ.get("SELKA_ZIG_CACHE_CAP_GB") or "20"
    env["ZIG"] = zig_path(repo)
    return env


def checkout(repo, target):
    """Make REPO a detached, locked worktree at TARGET."""
    if not os.path.exists(os.path.join(repo, ".git")):
        git("worktree", "add", "--detach", repo, target)
    if not worktree_locked(repo):
        git("worktree", "lock", "--reason", "E5 map refresh (scripts/edit_check_refresh.py); owned by the refresh", repo)
    git("checkout", "--detach", target, cwd=repo)
    return target


class Worker:
    """One refresh of REF's head, collected in the refresh worktree REPO into the map store STORE."""

    def __init__(self, store, ref, repo):
        self.store, self.ref, self.repo = store, ref, repo
        self.env = worker_environment(repo)
        self.work = os.path.join(repo, ".tmp", "map-refresh")
        self.counter = {}
        self.batches = []

    def head(self):
        """The commit REF names now."""
        return resolve(self.ref)

    def has_map(self, commit):
        """Whether the store holds the map of COMMIT."""
        return os.path.exists(map_path(self.store, commit))

    def finish(self, target, outcome, detail, work, partial):
        """Record the outcome, remove the work directory and any partial map, and return OUTCOME."""
        shutil.rmtree(work, ignore_errors=True)
        if os.path.exists(partial):
            os.remove(partial)
        note_outcome(self.store, target, outcome)
        record(self.store, "finish", target=target, outcome=outcome, detail=detail)
        set_status(self.store, phase="idle", last=[target, outcome, detail])
        return outcome

    def refresh_once(self, target):
        """Map TARGET; return the outcome ("published", "cancelled", "refused" or "failed")."""
        work = os.path.join(self.work, target)
        logs = os.path.join(state_dir(self.store), "logs", target)
        partial = os.path.join(state_dir(self.store), "partial-%s.json.gz" % target)
        record(self.store, "start", target=target, ref=self.ref)
        try:
            set_status(self.store, phase="checkout", target=target, ref=self.ref, pid=os.getpid())
            # The worktree is created before any directory of ours lives in it: git refuses a non-empty path.
            checkout(self.repo, target)
            shutil.rmtree(work, ignore_errors=True)
            os.makedirs(work)
            os.makedirs(self.env["TMPDIR"], exist_ok=True)
            os.makedirs(logs, exist_ok=True)
            set_status(self.store, phase="build", target=target)
            # The default install is part of the build: the tests read libexec/selka/components and the tool
            # directory, which only an install creates (without it 198 tests failed with ComponentMissing).
            code, wait, total = admitted(self.repo, [self.env["ZIG"], "build", "install", "coverage", "edit-check-tool"],
                                         os.path.join(logs, "build.log"), self.env)
            record(self.store, "build", target=target, code=code, admission_wait_s=wait, total_s=round(total, 1))
            if code:
                return self.finish(target, "failed", "build exit %d" % code, work, partial)
            names = self.list_tests(target, logs)
            if names is None:
                return self.finish(target, "failed", "listing the tests failed", work, partial)
            sizers = {}
            run_dirs = []
            for run in range(1, RUNS + 1):
                set_status(self.store, phase="collect", target=target, run=run, runs=RUNS)
                self.batches = []
                outcome = run_batches(names, lambda root: sizers.setdefault(root, BatchSizer()),
                                      lambda root, batch, first: self.run_batch(target, run, root, batch, first, work, logs),
                                      lambda: self.head() != target)
                if outcome == "cancelled":
                    record(self.store, "cancelled", target=target, run=run)
                    return self.finish(target, "cancelled", "head moved during run %d" % run, work, partial)
                run_dir = os.path.join(work, "run-%d" % run)
                merge_batches(run_dir, self.batches)
                if run == 1:
                    # The guest phase (E2) writes into the first run's directory, as edit_check_map.py runs it: without
                    # it the map has no guest root and the edit check runs every guest file.
                    set_status(self.store, phase="guests", target=target)
                    self.collect_guests(target, run_dir, logs)
                run_dirs.append(run_dir)
            set_status(self.store, phase="map", target=target)
            code, wait, total = admitted(self.repo, [os.path.join(self.repo, "zig-out", "tools", "edit-check-tool"), "map",
                                                     self.repo, target, partial, *run_dirs],
                                         os.path.join(logs, "map.log"), self.env)
            record(self.store, "map", target=target, code=code, admission_wait_s=wait, total_s=round(total, 1))
            if code:
                return self.finish(target, "failed", "map tool exit %d" % code, work, partial)
            failed = edit_check_map.failed_tests(partial)
            if publish_map(partial, map_path(self.store, target), failed):
                record(self.store, "published", target=target, map=map_path(self.store, target))
                record(self.store, "pruned", target=target, removed=prune_maps(self.store, MAPS_KEPT, {target}))
                return self.finish(target, "published", "", work, partial)
            keep_results(work, logs)
            return self.finish(target, "refused", "%d failed tests, first %s" % (len(failed), failed[0]), work, partial)
        except (BatchFailed, MergeError, OSError, subprocess.CalledProcessError) as error:
            return self.finish(target, "failed", str(error), work, partial)

    def collect_guests(self, target, run_dir, logs):
        """Collect the guest phase (every guest file alone, cold and warm) into RUN_DIR in one admission."""
        waited = wait_while_queued(self.store, "guests")
        command = [sys.executable, "-B", os.path.join(self.repo, "scripts", "edit_check_collect.py"), "--guests",
                   "--coverage", os.path.join(self.repo, "zig-out", "coverage"), "--out", run_dir, "--jobs", str(JOBS)]
        code, wait, total = admitted(self.repo, command, os.path.join(logs, "guests.log"), self.env)
        record(self.store, "guests", target=target, code=code, admission_wait_s=wait, yield_wait_s=waited,
               total_s=round(total, 1))
        if code:
            raise BatchFailed("guests exit %d" % code)

    def list_tests(self, target, logs):
        """The test names of each root of the refresh's build, from one admitted listing; None on failure."""
        listing = os.path.join(self.work, target, "tests.json")
        code, wait, total = admitted(self.repo, [sys.executable, "-B", os.path.abspath(__file__), "--list", self.repo, listing],
                                     os.path.join(logs, "list.log"), self.env)
        record(self.store, "list", target=target, code=code, admission_wait_s=wait, total_s=round(total, 1))
        return read_json(listing, None) if code == 0 else None

    def run_batch(self, target, run, root, batch, first, work, logs):
        """Collect one batch of ROOT's tests in its own admission; return the seconds it ran (admission excluded)."""
        index = self.counter.get((run, root), 0) + 1
        self.counter[(run, root)] = index
        label = "run%d-%s-%03d" % (run, root, index)
        names_file = os.path.join(work, label + ".names")
        with open(names_file, "w") as handle:
            handle.write("\n".join(batch) + "\n")
        out = os.path.join(work, label)
        waited = wait_while_queued(self.store, label)
        command = [sys.executable, "-B", os.path.join(self.repo, "scripts", "edit_check_collect.py"),
                   "--coverage", os.path.join(self.repo, "zig-out", "coverage"), "--out", out, "--roots", root,
                   "--names", names_file, "--jobs", str(JOBS), "--min-available-gb", "7"]
        if first:
            command.append("--unnamed")
        if run != TRACED_RUN:
            # Only the traced run lists the tests whose processes left no hit set; the other run keeps its hit sets only.
            command.append("--no-trace-exec")
        code, wait, total = admitted(self.repo, command, os.path.join(logs, label + ".log"), self.env)
        if code:
            raise BatchFailed("%s exit %d" % (label, code))
        self.batches.append((root, out))
        run_seconds = total - (wait or 0.0)
        record(self.store, "batch", target=target, run=run, label=label, root=root, tests=len(batch), unnamed=first,
               admission_wait_s=wait, yield_wait_s=waited, run_s=round(run_seconds, 1), total_s=round(total, 1))
        return run_seconds


def run_worker(store, ref, repo):
    """Refresh REF into STORE while holding the refresh lock; return 0 when the map exists afterwards."""
    lock = try_lock(os.path.join(state_dir(store), "refresh.lock"))
    if lock is None:
        print("edit check refresh: another refresh holds the lock; it re-reads %s at each batch" % ref)
        return 0
    try:
        worker = Worker(store, ref, repo)
        set_status(store, phase="starting", ref=ref, pid=os.getpid())
        outcome, target = converge(worker.head, worker.has_map, worker.refresh_once)
        print("edit check refresh: %s for %s" % (outcome, target), flush=True)
        return 0 if outcome in ("fresh", "published") else 1
    finally:
        set_status(store, pid=None)
        lock.close()


def start_detached(store, ref):
    """Start a worker for REF in its own session and return at once; its output goes to the worker log."""
    os.makedirs(state_dir(store), exist_ok=True)
    log = os.path.join(state_dir(store), "worker.log")
    with open(log, "a") as handle:
        subprocess.Popen([sys.executable, "-B", os.path.abspath(__file__), "--worker", "--ref", ref], cwd=ROOT,
                         stdin=subprocess.DEVNULL, stdout=handle, stderr=subprocess.STDOUT, start_new_session=True,
                         env=dict(os.environ, SELKA_EDIT_CHECK_STORE=store))
    return log


def refresh_allowed(store, select_only):
    """Whether a real run may start a refresh of main now: not select-only, not disabled by SELKA_EDIT_CHECK_NO_REFRESH=1,
    no refresh running, and the last refresh of main did not fail (the staleness line's rules)."""
    try:
        head = resolve(DEFAULT_REF)
    except subprocess.CalledProcessError:
        return False
    return (not lock_held(store) and not select_only and os.environ.get("SELKA_EDIT_CHECK_NO_REFRESH") != "1"
            and not refused_before(store, head))


def staleness_note(store, map_commit, select_only):
    """The edit check's staleness line, or None; starts a refresh when main has no map and the map is too old.

    MAP_COMMIT is the map the edit check would use (None when there is none). Nothing is printed while main has its
    own map. A refresh is started only by a real run (not --select-only), when none is running, when the last
    refresh of main did not fail, and not when SELKA_EDIT_CHECK_NO_REFRESH=1.
    """
    try:
        head = resolve(DEFAULT_REF)
    except subprocess.CalledProcessError:
        return None
    if os.path.exists(map_path(store, head)):
        return None
    behind = commits_behind(map_commit, head) if map_commit else None
    if map_commit is not None and behind is not None and behind <= STALE_COMMITS:
        return None
    running = lock_held(store)
    started = False
    if not running and refresh_allowed(store, select_only):
        log = start_detached(store, DEFAULT_REF)
        started = True
    if map_commit is None:
        what = "no coverage map at or before HEAD"
    elif behind is None:
        what = "the coverage map %s is not on main" % map_commit[:9]
    else:
        what = "the coverage map %s is %d commits behind main" % (map_commit[:9], behind)
    if running:
        action = "a refresh is running"
    elif started:
        action = "started a refresh of main (log %s)" % log
    else:
        action = "no refresh is running; python3 scripts/edit_check_refresh.py starts one"
    return "edit check: %s; %s" % (what, action)


def print_status(store):
    """Print the refresh's status, whether a worker runs, and the last events."""
    status = read_json(os.path.join(state_dir(store), "status.json"), {})
    print("refresh: %s" % ("running" if lock_held(store) else "not running"))
    for key in sorted(status):
        print("  %s: %s" % (key, status[key]))
    events = os.path.join(state_dir(store), "events.jsonl")
    if os.path.exists(events):
        with open(events) as handle:
            for line in handle.readlines()[-8:]:
                print("  event " + line.rstrip())
    return 0


def list_mode(repo, out):
    """Write the test names of each root of the coverage build in REPO to OUT (run inside an admission)."""
    binaries = os.path.join(repo, "zig-out", "coverage", "bin")
    names = {root: edit_check_collect.list_tests(os.path.join(binaries, edit_check_collect.ROOTS[root]), repo) for root in ROOTS}
    write_json(out, names)
    return 0


def main(argv=None):
    """Entry point: start a refresh (default), run one in the foreground, print the status, or run a worker."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ref", default=DEFAULT_REF, help="the ref to map (default main)")
    parser.add_argument("--once", action="store_true", help="refresh in the foreground instead of detaching")
    parser.add_argument("--status", action="store_true", help="print the refresh's state")
    parser.add_argument("--prune", action="store_true", help="remove the finished maps beyond the newest %d, now" % MAPS_KEPT)
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--list", nargs=2, metavar=("REPO", "OUT"), help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    store = store_dir()
    if args.list:
        return list_mode(*args.list)
    if args.status:
        return print_status(store)
    if args.prune:
        removed = prune_maps(store, MAPS_KEPT)
        print("edit check refresh: removed %d maps beyond the newest %d%s" % (len(removed), MAPS_KEPT, "".join(" " + c[:9] for c in removed)))
        return 0
    if args.worker or args.once:
        return run_worker(store, args.ref, refresh_dir())
    if lock_held(store):
        print("edit check refresh: a refresh is running; it re-reads %s at each batch boundary" % args.ref)
        return 0
    log = start_detached(store, args.ref)
    print("edit check refresh: started for %s (log %s)" % (args.ref, log))
    return 0


if __name__ == "__main__":
    sys.exit(main())
