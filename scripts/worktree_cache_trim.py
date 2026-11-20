#!/usr/bin/env python3
"""Bound one worktree's own build caches when it requests an admitted job.

Zig cannot drop a single cache entry, so the only safe bound is to rename the
whole `.zig-cache` aside before the job starts and delete it in the background.
The same applies, per directory, to the regenerable tiers of `.selka-cache`;
the `.selka-cache` directory itself is never removed because it can hold
protected evidence.

The test suites' caches (`.selka-cache/unit-tests`, `core-tests`, `lang-tests`
and the others in `TEST_SUITES`, with their `-release` and `-unoptimized`
variants) are bounded together. Each is made of work directories, the
directories that hold the compiler's `.retention.lock`: one per suite, one per
core test, one per unit-test program. The outermost directory that holds a lease
is the unit, so a cache made of several leased parts (the runtime seed's
variants: an object store and a work directory) holds a lease of its own and
goes whole or not at all. Over the bound, whole work directories go, least
recently used first, and one whose lease another process holds is skipped.

An admission does two different things with these caches, and only one of them belongs in the admission:

* **Deciding** whether a cache is over its cap, and renaming it aside. That happens at the admission, under the
  admission lock, before the job starts, and only when no other admitted job of the worktree runs (below). It reads the
  sizes a measurement recorded (`prune-caches.sizes`, and `TEST_SIZES` for the test suites) and walks nothing, except
  that a record which says "over the cap" is confirmed with a bounded `du` before a cache is condemned on it.
* **Measuring**: walking the caches with `du`, scanning for deletions an earlier trim left half done. That costs seconds
  on a worktree with millions of cache entries, so it runs in a detached background process (`--measure-only`), at most
  once in `MEASURE_INTERVAL_SECONDS` per worktree (`request_measure`), holds no admission lock, and never renames or
  moves anything that a job might use: its only deletions are directories an earlier trim already renamed aside.
  An admission of a worktree nobody has measured yet trims nothing; a later one decides on the record.

The caller (a build-slot admission) holds the slot for the job that is starting
and has just written its owner record. Nothing here touches a cache that another
admitted job of the same worktree may still be using, and nothing here ever
visits another worktree.

A running verification coordinator (`scripts/verify_cache.py`) is such a user of `.zig-cache` although it holds no slot
while it waits for admitted work: from `prepare` to the end of its run it watches the artifacts it built, which live
there, and a rename of that directory fails the run with `inputs changed while awaiting admitted work` (F48). It holds
`COORDINATOR_LOCK` for the whole request, so while the lock is held no admission trims `.zig-cache`, the admissions the
coordinator itself makes (the gate's, say) included, which is the case that failed. The other caches are not watched and
are bounded as before. The `.zig-cache` cap would then never fire for a worktree that only runs gates, so the coordinator
applies it itself, once, at the start of its request, before it takes any snapshot (`bound_for_coordinator`); that is one
request, not one admission, so it measures what it needs at once.

A compiler watcher (`build-slot.sh watch`) is such a user too, for its whole life, frozen or not: its incremental
compilers keep `.zig-cache` open. Its `watchN` slot counts as an active job of its worktree, and its daemon's worktree
lock (`WATCH_LOCK`) does the same whatever slot directory the caller was given, on every path that renames or deletes
a cache: an admission's trim, the coordinator's (`bound_for_coordinator`), and the background measurement's deletion
of renamed-aside directories (`finish_asides`).

The slot records prove that for the slot directory the admission uses. A job under
a supervisor (`verification_process.run_supervised`) also exports the directory it
runs in (`SELKA_ADMISSION_SUPERVISED`), and an admission that finds its own worktree
named there trims nothing and starts nothing: it is inside a job that uses these
caches, whatever slot directory it was given (the tests give theirs a private one).
It matters beyond the caches: the background deletion and measurement outlive the
admission, so inside a supervisor they are descendants that outlive its closeout, the
action ends 125 with every step green, and the supervisor kills them half-done. So an
admission inside a supervised action of any worktree (a test's fixture, say) starts no
background process at all (`supervised_anywhere`, `detach`): its measurement waits for the
next admission outside an action, which a gate's own admission and `bound_for_coordinator`
are, so a worktree that only ever runs gates is still measured.
"""
import argparse
from contextlib import contextmanager
import fcntl
import os
from pathlib import Path
import re
import subprocess
import sys
import threading
import time

CACHE = ".zig-cache"
TIERS = ("programs-v2", "programs-v1", "foreign-v1", "replay-v1", "stages-packed-v1", "ownership", "semantic", "frontend")
STAGING = ("native-link-*", "program-*")
TEST_SUITES = ("unit-tests", "core-tests", "guest-tests", "lang-tests", "ported-tests", "value-semantics-tests")
TEST_VARIANTS = ("", "-release", "-unoptimized")
TEST_SIZES = "test-cache-sizes.tsv"
# How long a worktree's caches go unmeasured at most (`request_measure`): the walk is the expensive part of a trim.
MEASURE_INTERVAL_SECONDS = 600
LEASE = ".retention.lock"
ASIDE = re.compile(r"\.trim-\d+$")
ASIDE_GRACE_SECONDS = 900
MEASURE_TIMEOUT_SECONDS = 2.0
# The directory a supervised job runs in; `verification_process.SUPERVISED_ROOT` sets it.
SUPERVISED_ROOT = "SELKA_ADMISSION_SUPERVISED"
# Every slot whose holder may be using its worktree's caches; a watcher (`watchN`, `build_slot_legacy.sh`) holds its
# slot for as long as its incremental compilers keep `.zig-cache` open, frozen or not.
SLOT = re.compile(r"(?:build|gate|timing|watch)[0-9]+$")
# The lock a watcher's daemon (`scripts/dev_loop.py`) holds, exclusively, for its whole life, whatever slot directory it
# was admitted through. Relative to the worktree.
WATCH_LOCK = Path(".selka-cache/dev-loop/daemon.lock")
# The lock a verification coordinator holds, exclusively, for its whole request (`verify_cache.main`). Relative to the worktree.
COORDINATOR_LOCK = Path(".selka-cache/verification-v3/coordinator.lock")
# How long a coordinator waits for the admission lock before it leaves the caps to the next admission.
ADMISSION_WAIT_SECONDS = 15.0


def boot_id():
    try:
        return Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    except OSError:
        return ""


def process_start(pid):
    try:
        text = (Path("/proc") / str(pid) / "stat").read_text()
    except (OSError, FileNotFoundError):
        return None
    rest = text.rsplit(") ", 1)[-1].split()
    return rest[19] if len(rest) > 19 else None


def held(lock):
    try:
        descriptor = os.open(lock, os.O_RDONLY)
    except OSError:
        return False
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        return False
    except BlockingIOError:
        return True
    finally:
        os.close(descriptor)


def owner_active(path, worktree):
    """Whether this slot's recorded owner is alive in the same worktree.

    A busy slot with no valid owner record (an older wrapper) counts as active,
    so a trim never races a job whose identity it cannot prove.
    """
    try:
        pid, start, boot, tree = path.read_text().strip().split(None, 3)
    except (OSError, ValueError):
        return True
    if boot != boot_id() or process_start(int(pid)) != start:
        return False
    return tree == worktree


def lock_holders(lock):
    """Pids recorded in /proc/locks for a held lock file, oldest interface or new."""
    try:
        value = lock.stat()
        target = "%02x:%02x:%d" % (os.major(value.st_dev), os.minor(value.st_dev), value.st_ino)
        lines = Path("/proc/locks").read_text().splitlines()
    except OSError:
        return []
    holders = []
    for line in lines:
        fields = line.split()
        if len(fields) >= 6 and fields[1] in ("FLOCK", "POSIX") and fields[5] == target:
            try:
                holders.append(int(fields[4]))
            except ValueError:
                continue
    return holders


def cwd_is(pid, worktree):
    try:
        return os.readlink("/proc/%d/cwd" % pid) == worktree
    except OSError:
        return None


def open_holders(lock):
    """Pids with this lock file open: inherited descriptors outlive a fork's owner."""
    target = lock.resolve()
    holders = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            descriptors = (entry / "fd").iterdir()
        except OSError:
            continue
        for descriptor in descriptors:
            try:
                if os.path.realpath(descriptor) == str(target):
                    holders.append(int(entry.name))
                    break
            except OSError:
                continue
    return holders


def active_same_worktree(slot_dir, own_slot, worktree):
    for lock in sorted(slot_dir.glob("*.lock")):
        if not SLOT.fullmatch(lock.stem):
            continue
        if lock.stem == own_slot or not held(lock):
            continue
        owner = lock.with_suffix(".owner")
        if owner.exists():
            if owner_active(owner, worktree):
                return True
            continue
        # An older wrapper wrote no owner record: find every process with the
        # lock open, because a forked child may be the one still alive, and read
        # the working directory the kernel records.
        pids = sorted(set(lock_holders(lock)) | set(open_holders(lock)))
        known = [cwd_is(pid, worktree) for pid in pids]
        if any(value is True for value in known):
            return True
        if not any(value is False for value in known):
            return True
    return False


def supervised_anywhere():
    """Whether the caller runs inside a supervised action at all, of any worktree (`SELKA_ADMISSION_SUPERVISED` is set).

    The supervisor counts every process still running when its action ends as a leftover, ends the action 125 and kills
    it, so nothing an admission starts may outlive the action: `detach` starts nothing then, and no measurement is
    requested. An admission outside any action (a gate's own, before its job, and `bound_for_coordinator`) is not
    affected, which is how a worktree that only ever runs gates is still measured.
    """
    return bool(os.environ.get(SUPERVISED_ROOT))


def supervised_here(worktree):
    """Whether the caller runs inside a supervised job of WORKTREE itself, which this module then leaves alone."""
    supervised = os.environ.get(SUPERVISED_ROOT)
    return bool(supervised) and Path(supervised).resolve() == Path(worktree).resolve()


def watcher_running(worktree, slot_dir=None):
    """Whether a compiler watcher of this worktree is alive: its daemon's worktree lock is held, or a held `watchN`
    slot of SLOT_DIR records this worktree. Its compilers keep `.zig-cache` open while it lives, frozen or not."""
    if held(Path(worktree) / WATCH_LOCK):
        return True
    if slot_dir is None:
        return False
    for lock in sorted(Path(slot_dir).glob("watch*.lock")):
        if SLOT.fullmatch(lock.stem) and held(lock) and owner_active(lock.with_suffix(".owner"), str(worktree)):
            return True
    return False


def coordinator_running(worktree):
    """Whether a verification coordinator holds this worktree's lock: it watches `.zig-cache` until its request ends."""
    return held(Path(worktree) / COORDINATOR_LOCK)


@contextmanager
def sizes_lock(path):
    with path.open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def read_sizes(path):
    entries = {}
    try:
        for line in path.read_text().splitlines():
            cache, stamp, kib = line.split("\t")
            entries[cache] = (int(stamp), int(kib))
    except (OSError, ValueError):
        pass
    return entries


def write_sizes(path, entries):
    body = "".join("%s\t%d\t%d\n" % (cache, stamp, kib)
                   for cache, (stamp, kib) in sorted(entries.items()))
    temporary = path.with_name(path.name + ".trim.%d" % os.getpid())
    try:
        temporary.write_text(body)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def update_sizes(sizes, rows=None, drop=(), newer=()):
    """Change the shared sizes record by READING it again under its lock: set ROWS, remove DROP, write it back.

    The record is shared by every worktree of the repository and a walk takes minutes: a record read before the walk
    and written after it would restore a row another worktree's trim just removed and drop the figures it just wrote.
    A row named in NEWER is set only when the record's own row for it is not newer (by its stamp).
    """
    with sizes_lock(sizes.with_name(sizes.name + ".lock")):
        entries = read_sizes(sizes)
        for name, row in (rows or {}).items():
            current = entries.get(name)
            if name in newer and current is not None and current[0] > row[0]:
                continue
            entries[name] = row
        for name in drop:
            entries.pop(str(name), None)
        write_sizes(sizes, entries)


def stamp(path):
    try:
        return int((path / "o").stat().st_mtime)
    except OSError:
        return 0


def measure(path, timeout=MEASURE_TIMEOUT_SECONDS):
    """KiB used, or None when the walk is too slow to hold admission."""
    try:
        completed = subprocess.run(["du", "-sx", "--block-size=1K", str(path)],
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                   text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None
    if completed.returncode != 0 or not completed.stdout.split():
        return None
    return int(completed.stdout.split()[0])


def detach(command):
    """Start COMMAND in a session of its own, so it outlives the caller; a thread reaps it, which a coordinator needs.

    Inside a supervised action it starts nothing (`supervised_anywhere`): a measurement waits for the next admission
    outside one, and a renamed-aside cache for the next measurement, which finishes the deletion.
    """
    if supervised_anywhere():
        return
    process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, start_new_session=True)
    threading.Thread(target=process.wait, daemon=True).start()


def spawn_measure(worktree, sizes, tiers_cap, slot_dir=None):
    """Record this worktree's cache sizes out of band, and finish its half-done deletions; a later admission trims.

    SLOT_DIR (else the caller's SELKA_SLOT_DIR) is where the measurement looks for a watcher of the worktree, which
    leaves the deletions for later."""
    slot_dir = slot_dir or os.environ.get("SELKA_SLOT_DIR")
    detach([sys.executable, "-B", os.path.abspath(__file__), "--measure-only",
            "--worktree", str(worktree), "--sizes", str(sizes),
            "--tiers-cap-gb", str(tiers_cap)] + (["--slot-dir", str(slot_dir)] if slot_dir else []))


def measure_stamp(worktree):
    """The file whose modification time says when this worktree's measurement was last started.

    It lives in the worktree it describes, not beside the shared sizes record: a fixture under a checkout's `.tmp`
    resolves to the checkout's git directory, and a stamp per path piled up there.
    """
    return worktree / ".selka-cache" / "trim-measured"


def request_measure(worktree, sizes, tiers_cap, now=None, slot_dir=None):
    """Start the background measurement unless one started within MEASURE_INTERVAL_SECONDS; whether it started one.

    The stamp is taken under an exclusive lock first, so admissions that arrive together start one measurement
    between them, and an admission that finds the stamp busy leaves the decision to the one that holds it. A stamp
    that is new (empty) means nobody has measured this worktree. This is cheap: it opens, locks and stats one file.
    Nothing is requested inside a supervised action (`supervised_anywhere`), nor for a worktree with no cache.
    """
    if supervised_anywhere() or not ((worktree / CACHE).is_dir() or (worktree / ".selka-cache").is_dir()):
        return False
    stamp_file = measure_stamp(worktree)
    try:
        stamp_file.parent.mkdir(exist_ok=True)
        stream = stamp_file.open("a")
    except OSError:
        return False
    with stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return False
        status = os.fstat(stream.fileno())
        age = (time.time() if now is None else now) - status.st_mtime
        if status.st_size > 0 and age < MEASURE_INTERVAL_SECONDS:
            return False
        try:
            stream.seek(0)
            stream.truncate()
            stream.write("%d\n" % os.getpid())
            stream.flush()
        except OSError:
            return False
        spawn_measure(worktree, sizes, tiers_cap, slot_dir)
    return True


def delete_later(paths):
    """Delete PATHS (directories already renamed aside) in a background session that outlives this admission."""
    detach(["rm", "-rf", "--", *map(str, paths)])


def stale_asides(worktree, now, depth=3):
    """Directories an earlier trim renamed aside whose deletion has not touched them for ASIDE_GRACE_SECONDS.

    A deletion that was cut off (the machine restarted, the process was killed) leaves its aside for good: nothing
    else names it, and `work_directories` skips it as already condemned. Looking again later finishes the job; a
    second `rm` on a tree one is still deleting is harmless, so the grace only keeps it rare.

    An aside is always a sibling of the cache it replaced, and this module renames in three places only, so only
    those are listed: `.zig-cache.trim-N` in the worktree, `TIER.trim-N` in `.selka-cache/core`, and
    `WORKDIR.trim-N` among the work directories of the test suites (down to DEPTH levels, as `work_directories`
    finds them). Nothing is listed inside a work directory or a tier: most of a worktree's millions of cache entries
    are there, none can be an aside, and listing them was most of what an admission cost.
    """
    found = []

    def listing(directory):
        try:
            return list(os.scandir(directory))
        except OSError:
            return []

    def stale(entry):
        status = entry.stat(follow_symlinks=False)
        return now - max(status.st_mtime, status.st_ctime) > ASIDE_GRACE_SECONDS

    for entry in listing(worktree):
        if entry.is_dir(follow_symlinks=False) and entry.name.startswith(CACHE + ".") and ASIDE.search(entry.name):
            if stale(entry):
                found.append(Path(entry.path))
    for entry in listing(worktree / ".selka-cache" / "core"):
        if entry.is_dir(follow_symlinks=False) and ASIDE.search(entry.name) and stale(entry):
            found.append(Path(entry.path))
    for root in test_roots(worktree):
        pending = [(root, 0)]
        while pending:
            directory, level = pending.pop()
            if (directory / LEASE).exists():
                continue
            for entry in listing(directory):
                if not entry.is_dir(follow_symlinks=False):
                    continue
                if ASIDE.search(entry.name):
                    if stale(entry):
                        found.append(Path(entry.path))
                elif level < depth:
                    pending.append((Path(entry.path), level + 1))
    return sorted(found)


def finish_asides(worktree, slot_dir=None):
    """Finish the deletions an earlier trim left half done, unless a watcher of the worktree is alive: a cache renamed
    aside under it (by hand, or by a wrapper that predates watchers) may still be open in its compilers."""
    if watcher_running(worktree, slot_dir):
        return
    found = stale_asides(worktree, time.time())
    if found:
        print("build-slot: finishing %d unfinished cache deletion%s of %s" % (len(found), "" if len(found) == 1 else "s", worktree),
              file=sys.stderr, flush=True)
        delete_later(found)


def size_text(kib):
    return "%.1f GiB" % (kib / 1048576.0) if kib >= 1048576 else "%.0f MiB" % (kib / 1024.0)


def remove_later(path, label, worktree, size_kib, cap_gib):
    aside = path.with_name(path.name + ".trim-%d" % os.getpid())
    try:
        os.rename(path, aside)
    except OSError as error:
        print("build-slot: cannot trim %s %s: %s" % (worktree, label, error), file=sys.stderr)
        return
    print("build-slot: trimming %s %s %s (cap %s)" %
          (worktree, label, size_text(size_kib), size_text(cap_gib * 1048576)), file=sys.stderr, flush=True)
    delete_later([aside])


def test_roots(worktree):
    base = worktree / ".selka-cache"
    names = [suite + variant for suite in TEST_SUITES for variant in TEST_VARIANTS]
    return [base / name for name in names if (base / name).is_dir() and not (base / name).is_symlink()]


def work_directories(root, depth=3):
    """The outermost directories under ROOT (itself included) that hold a work-directory lease."""
    lease = root / LEASE
    if lease.is_file() and not lease.is_symlink():
        return [root]
    if depth == 0:
        return []
    try:
        entries = sorted(os.scandir(root), key=lambda entry: entry.name)
    except OSError:
        return []
    found = []
    for entry in entries:
        # A directory renamed aside by an earlier trim is being deleted: it is no longer a cache.
        if entry.is_dir(follow_symlinks=False) and ".trim-" not in entry.name:
            found += work_directories(Path(entry.path), depth - 1)
    return found


def activity(path):
    """The newest modification time of PATH and its direct entries: a cheap last-use stamp."""
    try:
        newest = path.stat().st_mtime
        for entry in os.scandir(path):
            newest = max(newest, entry.stat(follow_symlinks=False).st_mtime)
    except OSError:
        return 0.0
    return newest


def measure_tests(worktree, timeout):
    """KiB of each test work directory, by one bounded `du` per suite; None when one is too slow."""
    sizes = {}
    for root in test_roots(worktree):
        units = work_directories(root)
        if not units:
            continue
        depth = max(len(unit.relative_to(root).parts) for unit in units)
        try:
            completed = subprocess.run(["du", "-x", "--block-size=1K", "--max-depth=%d" % depth, str(root)],
                                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                                       timeout=timeout)
        except subprocess.TimeoutExpired:
            return None
        listed = {}
        for line in completed.stdout.splitlines():
            kib, _, path = line.partition("\t")
            if kib.isdigit():
                listed[path] = int(kib)
        for unit in units:
            if str(unit) in listed:
                sizes[str(unit)] = listed[str(unit)]
    return sizes


def read_test_sizes(path):
    entries = {}
    try:
        for line in path.read_text().splitlines():
            unit, kib = line.split("\t")
            entries[unit] = int(kib)
    except (OSError, ValueError):
        return {}
    return entries


def write_test_sizes(path, entries):
    temporary = path.with_name(path.name + ".trim.%d" % os.getpid())
    try:
        temporary.write_text("".join("%s\t%d\n" % (unit, kib) for unit, kib in sorted(entries.items())))
        os.replace(temporary, path)
    except OSError:
        pass
    finally:
        temporary.unlink(missing_ok=True)


def claim(unit):
    """Rename UNIT aside under its exclusive lease; the new path, or None when another process holds it."""
    try:
        stream = (unit / LEASE).open("a")
    except OSError:
        return None
    with stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return None
        aside = unit.with_name(unit.name + ".trim-%d" % os.getpid())
        try:
            os.rename(unit, aside)
        except OSError:
            return None
    return aside


def trim_tests(worktree, cap_gib):
    """Bound the test suites' work directories together, least recently used first, on the recorded sizes.

    The record (`TEST_SIZES`) is written by the background measurement. A record within the cap is the whole
    answer: nothing is walked, which matters because a worktree holds thousands of work directories.
    """
    record = worktree / ".selka-cache" / TEST_SIZES
    entries = read_test_sizes(record)
    cap_kib = cap_gib * 1048576
    if sum(entries.values()) <= cap_kib:
        return
    units = [unit for root in test_roots(worktree) for unit in work_directories(root)]
    known = {unit: entries[str(unit)] for unit in units if str(unit) in entries}
    total = sum(known.values())
    if total <= cap_kib:
        return
    removed = []
    freed = 0
    for unit in sorted(known, key=activity):
        if total - freed <= cap_kib:
            break
        aside = claim(unit)
        if aside is None:
            continue
        removed.append(aside)
        freed += known[unit]
        entries.pop(str(unit), None)
    if not removed:
        return
    write_test_sizes(record, entries)
    print("build-slot: trimming %s test caches %s to %s (cap %s, %d work director%s)" %
          (worktree, size_text(total), size_text(total - freed), size_text(cap_kib), len(removed),
           "y" if len(removed) == 1 else "ies"),
          file=sys.stderr, flush=True)
    delete_later(removed)


def tier_paths(worktree):
    """The regenerable directories of `.selka-cache/core` that exist: the tiers and the staging directories."""
    core = worktree / ".selka-cache" / "core"
    paths = [core / tier for tier in TIERS if (core / tier).is_dir()]
    paths += [path for pattern in STAGING for path in core.glob(pattern)
              if path.is_dir() and not ASIDE.search(path.name)]
    return paths


def measure_record(worktree, sizes, tiers_cap, timeout=60.0, tests=False):
    """Walk the caches and record their sizes: what the admissions that follow decide on.

    Run in a background process (`--measure-only`), never at an admission. It renames nothing, and it merges what it
    measured into the record as it stands when it is done (`update_sizes`), not as it was when it began.
    """
    if tests:
        measured = measure_tests(worktree, timeout)
        if measured is not None:
            write_test_sizes(worktree / ".selka-cache" / TEST_SIZES, measured)
    entries = read_sizes(sizes)
    rows = {}
    cache = worktree / CACHE
    if cache.is_dir() and not cache.is_symlink():
        current = stamp(cache)
        if entries.get(str(worktree), (None, None))[0] != current:
            kib = measure(cache, timeout=timeout)
            if kib is not None:
                rows[str(worktree)] = (current, kib)
    core = worktree / ".selka-cache" / "core"
    # A staging directory that has since gone leaves no row behind.
    gone = [name for name in entries if name.startswith(str(core) + os.sep) and not Path(name).exists()]
    for path in tier_paths(worktree):
        kib = measure(path, timeout=timeout)
        if kib is not None:
            rows[str(path)] = (stamp(path), kib)
    update_sizes(sizes, rows, gone, newer=(str(worktree),))


def zig_cache_kib(worktree, sizes, entries, tiers_cap):
    """KiB used by WORKTREE's `.zig-cache`: the sizes record when it is current, else measured and recorded.

    None when the walk was too slow to hold a request; a background measurement is started and a later request
    decides. This is the coordinator's: one request, so it may take the seconds a walk costs. An admission reads the
    record only (`trim`).
    """
    cache = worktree / CACHE
    current = stamp(cache)
    known = entries.get(str(worktree))
    if known is not None and known[0] == current:
        return known[1]
    kib = measure(cache)
    if kib is None:
        spawn_measure(worktree, sizes, tiers_cap)
        return None
    update_sizes(sizes, {str(worktree): (current, kib)}, newer=(str(worktree),))
    return kib


def trim_zig(worktree, sizes, entries, cap_gib, walk):
    """Rename `.zig-cache` aside when it is over the cap; WALK says whether the size may be measured here and now.

    An admission does not walk (WALK false): it decides on the record, and a cache nobody has measured is left for
    a later admission. A record that says "over the cap" for a cache that has changed since is confirmed with a
    bounded walk before the cache is condemned, so a cache emptied by hand is not renamed on an old figure; a walk
    too slow to finish leaves the cache alone, as the walk this replaced did, and a walk that finds it under the cap
    is written back so later admissions do not repeat it.
    """
    cache = worktree / CACHE
    if cap_gib <= 0 or not cache.is_dir() or cache.is_symlink():
        return
    cap_kib = cap_gib * 1048576
    if walk:
        kib = zig_cache_kib(worktree, sizes, entries, 0)
    else:
        known = entries.get(str(worktree))
        if known is None or known[1] <= cap_kib:
            return
        kib = known[1]
        current = stamp(cache)
        if known[0] != current:
            kib = measure(cache)
            if kib is None:
                return
            if kib <= cap_kib:
                update_sizes(sizes, {str(worktree): (current, kib)}, newer=(str(worktree),))
                return
    if kib is not None and kib > cap_kib:
        remove_later(cache, CACHE, worktree, kib, cap_gib)
        update_sizes(sizes, drop=[worktree])


def trim_tiers(worktree, sizes, entries, tiers_cap):
    """Rename the regenerable tiers aside when the recorded sizes of the ones that exist add up past the cap.

    The record is confirmed by a bounded walk of each tier before any is condemned. A tier whose walk is too slow
    counts for nothing and is not renamed (as before); figures that put the total under the cap are written back, so
    the next admission, finding the record under the cap, walks nothing.
    """
    paths = tier_paths(worktree)
    recorded = {path: entries[str(path)][1] for path in paths if str(path) in entries}
    cap_kib = tiers_cap * 1048576
    if sum(recorded.values()) <= cap_kib:
        return
    sizes_kib = {}
    for path in recorded:
        walked = measure(path)
        if walked is not None:
            sizes_kib[path] = walked
    if sum(sizes_kib.values()) <= cap_kib:
        update_sizes(sizes, {str(path): (stamp(path), kib) for path, kib in sizes_kib.items()})
        return
    for path, kib in sizes_kib.items():
        if kib:
            remove_later(path, str(path.relative_to(worktree)), worktree, kib, tiers_cap)
    update_sizes(sizes, drop=sizes_kib)


def trim(worktree, sizes, cap_gib, tiers_cap, walk=False):
    """The caps' decision for one admission: rename over-cap caches aside, from the recorded sizes."""
    if cap_gib <= 0 and tiers_cap <= 0:
        return
    entries = read_sizes(sizes)
    if cap_gib > 0:
        trim_zig(worktree, sizes, entries, cap_gib, walk)
    if tiers_cap > 0:
        trim_tiers(worktree, sizes, read_sizes(sizes), tiers_cap)


def sizes_record(worktree):
    """The shared sizes record `build-slot.sh` names: in the repository's common git directory, else in the worktree."""
    try:
        completed = subprocess.run(["git", "-C", str(worktree), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=10)
        common = completed.stdout.strip() if completed.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        common = ""
    return Path(common or worktree) / "prune-caches.sizes"


@contextmanager
def admission_lock(slot_dir, wait_seconds):
    """Hold SLOT_DIR's admission lock, the one every admission takes before it starts a job; yields whether it is held.

    An admission holds it while it checks and trims, so no job of this worktree can start between a check and a
    rename. It stays busy for the settle delay after each admission and for a whole timing window; past WAIT_SECONDS
    the caller goes without.
    """
    slot_dir.mkdir(parents=True, exist_ok=True)
    with (slot_dir / "admit.lock").open("a") as stream:
        deadline = time.monotonic() + wait_seconds
        while True:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    yield False
                    return
                time.sleep(0.1)
        try:
            yield True
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)


def bound_for_coordinator(worktree, slot_dir, environ, wait_seconds=ADMISSION_WAIT_SECONDS):
    """Apply the `.zig-cache` cap for a coordinator that holds WORKTREE's coordinator lock, before it watches anything.

    The admission does this for a plain build; a coordinator's own admissions cannot (they find the lock held and
    leave `.zig-cache` alone), so it does it once itself, with the same code, the same cap (`SELKA_ZIG_CACHE_CAP_GB`)
    and the same exclusion of other admissions. The other caches are not its to watch and stay with the admissions.
    A request that finds the cache within the cap, which is nearly every one, reads one record and takes no lock.
    Returns None, or the reason the cap was left to the next admission.
    """
    worktree = Path(worktree).resolve()
    cap = environ.get("SELKA_ZIG_CACHE_CAP_GB", "30")
    sizes = sizes_record(worktree)
    cache = worktree / CACHE
    if float(cap) <= 0 or not cache.is_dir() or cache.is_symlink() or supervised_here(worktree):
        return None
    kib = zig_cache_kib(worktree, sizes, read_sizes(sizes), 0)
    if kib is None or kib <= float(cap) * 1048576:
        return None
    argv = ["--worktree", str(worktree), "--slot-dir", str(slot_dir), "--sizes", str(sizes), "--coordinator",
            "--zig-cap-gb", cap, "--tiers-cap-gb", "0", "--tests-cap-gb", "0"]
    with admission_lock(Path(slot_dir), wait_seconds) as acquired:
        if not acquired:
            return "the admission lock stayed busy for %d s" % wait_seconds
        main(argv)
    return None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worktree", type=Path, required=True)
    parser.add_argument("--sizes", type=Path, required=True)
    parser.add_argument("--slot-dir", type=Path)
    parser.add_argument("--own-slot", default="")
    parser.add_argument("--zig-cap-gb", type=float, default=30.0)
    parser.add_argument("--tiers-cap-gb", type=float, default=10.0)
    parser.add_argument("--tests-cap-gb", type=float, default=8.0)
    parser.add_argument("--measure-only", action="store_true")
    parser.add_argument("--coordinator", action="store_true",
                        help="the caller is the verification coordinator that holds this worktree's coordinator lock")
    options = parser.parse_args(argv)
    worktree = options.worktree.resolve()
    if supervised_here(worktree) or not worktree.is_dir():
        return 0
    options.sizes.parent.mkdir(parents=True, exist_ok=True)
    if options.measure_only:
        # The background half: it walks and records, and deletes only what an earlier trim already renamed aside.
        measure_record(worktree, options.sizes, options.tiers_cap_gb, tests=True)
        finish_asides(worktree, options.slot_dir)
        return 0
    if options.zig_cap_gb < 0 or options.tiers_cap_gb < 0 or options.tests_cap_gb < 0:
        parser.error("caps must be non-negative")
    if options.zig_cap_gb == 0 and options.tiers_cap_gb == 0 and options.tests_cap_gb == 0:
        return 0
    if not options.coordinator:
        request_measure(worktree, options.sizes, options.tiers_cap_gb, slot_dir=options.slot_dir)
    if (options.slot_dir is not None and active_same_worktree(options.slot_dir, options.own_slot, str(worktree))) or \
            watcher_running(worktree):
        # Another job of this worktree is running, a watcher among them: never touch a cache it may be using. The
        # measurement above is the only thing started, and it renames nothing.
        return 0
    # A coordinator other than the caller watches the artifacts in `.zig-cache` until its request ends: that cache is
    # not trimmed under it, the caches it does not watch are.
    zig_cap = 0.0 if not options.coordinator and coordinator_running(worktree) else options.zig_cap_gb
    trim(worktree, options.sizes, zig_cap, options.tiers_cap_gb, walk=options.coordinator)
    if options.tests_cap_gb > 0:
        trim_tests(worktree, options.tests_cap_gb)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
