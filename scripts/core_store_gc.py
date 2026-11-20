#!/usr/bin/env python3
"""Maintain the per-user native object store without ever holding builds off it.

The store (`~/.cache/selka/core-runtime`) holds content-keyed unit objects, `units-v1/ab/<key>.o`
with a checksum record `<key>.o.sum`, hard-linked flat aliases of older ones (`units-v1/<key>.o`),
runtime objects in the root and idle claim files in `work/`. Millions of names, and builders
publish into it all the time, so this program obeys four rules:

* **It never makes a builder wait.** Builds hold a shared flock on `.retention.lock` for as long as
  they build. This program takes no exclusive lease over the unit objects at all, and the one
  window it takes for the runtime objects is a try (no wait) of at most `window_seconds`.
* **A run costs a bounded amount, not the size of the store.** A persistent ledger
  (`.size-ledger-v4.sqlite3`) holds one row per unit object and one per shard directory. A run
  re-inventories only the shards not seen for `rescan_seconds`, for at most `scan_seconds`, and
  evicts from the ledger by an index on last use, so the work is the shards re-read plus the
  objects removed. The ledger is advisory: it chooses candidates and every one is observed again
  (inode and last use) before it goes, so a stale row can mis-count bytes but never remove a file
  that was used, replaced or published since.
* **An object a build is using is never removed.** A hit refreshes the object's modification time
  at most an hour late (`unit_cache.zig` `keepFresh` and `Context.touch` leave a file touched within
  `touch_interval_ns`, one hour, alone; every compiler since the shard layout touched on each hit,
  which is no staler), so an object whose last modification or access is within
  `grace_seconds` (six hours: the hour plus the longest build) is not a candidate however far over
  budget the store is. A candidate
  is renamed to a tombstone `.partial` name, observed once more there, and only then unlinked; a
  touch or a republication that raced the rename puts it back (see `remove_object`).
* **Nothing unknown is touched.** Only names of the forms the compiler writes are read; symlinks,
  directories and foreign files stay.

**The budget is disk, not payload.** Every size here is allocated bytes (`st_blocks` x 512), because the files are small: a
checksum record of 96 bytes holds a 4 KiB block, so on 5 November a store whose payload was 9.96 GB (under the 10 GiB cap) held
15.87 GB of blocks in 2.1 million files. A hard-linked name counts once: the budget reads the shard name's inode.

Runtime objects (`core_rt-*`, `core_number_text-*`) are read by path for the whole build and are
never touched, so they cannot be told from idle by use: they go only when idle for `days`, inside
a try-exclusive window on the root lease (skipped when any build holds it). Claim files are
removed by probing their flock (a held claim is busy and stays); `storage.lock` in the compiler
re-checks the name after locking, so a waiter on a removed claim reopens the new file.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing, contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import resource
import secrets
import sqlite3
import stat
import time

OBJECT = re.compile(r"([0-9a-f]{64})\.o\Z")
RECORD = re.compile(r"([0-9a-f]{64})\.o\.sum\Z")
RUNTIME = re.compile(r"(?:core_rt|core_number_text)-[0-9a-f]+\.(?:o|c)\Z")
PARTIAL = re.compile(r"(?:[0-9a-f]{64}\.o(?:\.sum)?|(?:core_rt|core_number_text)-[0-9a-f]+\.(?:o|c))\.[0-9a-f]{32}\.partial\Z")
CLAIM = re.compile(r"[0-9a-f]{64}\.lock\Z")
# The toolchain identity memos (`core-tools-v1/`, src/core/tool_identity.zig): `<digest>.memo`, `<digest>.inventory`, and the
# `<name>.<32 hex>.pending` file a publication stages before it renames it into place.
TOOL_MEMO = re.compile(r"[0-9a-f]{64}\.(?:memo|inventory)\Z")
TOOL_PENDING = re.compile(r"[0-9a-f]{64}\.(?:memo|inventory)\.[0-9a-f]{32}\.pending\Z")
# `approval-v4` is the toolchain verdict since GH-3b; the older two are collected until their memos age out.
TOOL_DIRECTORIES = ("tool-identity", "approval-v4", "approval-v3", "approval-v2")
TOOLS_MAXIMUM = 64 << 20
SHARDS = tuple("%02x" % number for number in range(256))
SECOND = 1_000_000_000
DAY_NS = 86400 * SECOND
# v4 counts allocated blocks, v3 apparent bytes: the sizes in an old ledger mean something else, so it is not read.
LEDGER = ".size-ledger-v4.sqlite3"
BLOCK = 512
# How long an object that nothing touched may be skipped by a build before it is a candidate. Longer than the hour a hit may
# leave an object's modification time stale plus the longest build.
GRACE_SECONDS = 6 * 3600
# Rows fetched, and objects removed, between two commits of the ledger.
CHUNK = 500


def signature(path):
    """Identity checked again before a file is removed (tool memos)."""
    try:
        value = path.lstat()
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(value.st_mode):
        return None
    return (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns,
            value.st_ctime_ns, value.st_atime_ns)


def allocated(value):
    """Bytes a file holds on disk: its allocated blocks (`st_blocks` counts 512-byte units whatever the file system's block)."""
    return value.st_blocks * BLOCK


def lstat(path):
    """The regular file's or other entry's lstat, or None when the name is absent."""
    try:
        return os.lstat(path)
    except FileNotFoundError:
        return None


def last_use(value):
    """Nanoseconds of the later of a file's modification and access: the recency every rule compares.

    A build's hit refreshes the modification time, and a read moves the access time where the filesystem records it. The
    change time is left out on purpose: it cannot be set back, and a hard link or a rename moves it with no use at all.
    """
    return max(value.st_mtime_ns, value.st_atime_ns)


@contextmanager
def locked(path, operation, wait_seconds=0.0):
    """Hold a flock on a permanent lock file, polling for `wait_seconds`; BlockingIOError when it stays held."""
    descriptor = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise ValueError(f"not a regular lock: {path}")
        deadline = time.monotonic() + max(0.0, wait_seconds)
        while True:
            try:
                fcntl.flock(descriptor, operation | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.05)
        yield
    finally:
        os.close(descriptor)


def open_ledger(path):
    """Open the ledger, creating its tables; a ledger that cannot be read is advisory and is made again from the store."""
    try:
        return _open_ledger(path)
    except sqlite3.DatabaseError:
        for suffix in ("", "-wal", "-shm"):
            Path(str(path) + suffix).unlink(missing_ok=True)
        return _open_ledger(path)


def _open_ledger(path):
    """Tables: `objects` (a row per unit object), `shards` (a row per shard directory), `meta` (when the flat directory was listed)."""
    database = sqlite3.connect(path, timeout=60)
    try:
        database.execute("PRAGMA journal_mode=WAL")
        database.execute("PRAGMA synchronous=NORMAL")
        # size counts the object and its checksum record, osize the object alone, both as allocated bytes; recent is `last_use`
        # when the shard was read.
        database.execute("CREATE TABLE IF NOT EXISTS objects (key TEXT PRIMARY KEY, size INTEGER NOT NULL, osize INTEGER NOT NULL,"
                         " ino INTEGER NOT NULL, recent INTEGER NOT NULL) WITHOUT ROWID")
        database.execute("CREATE INDEX IF NOT EXISTS objects_recent ON objects(recent)")
        database.execute("CREATE TABLE IF NOT EXISTS shards (shard TEXT PRIMARY KEY, objects INTEGER NOT NULL,"
                         " bytes INTEGER NOT NULL, scanned INTEGER NOT NULL)")
        database.execute("CREATE TABLE IF NOT EXISTS meta (name TEXT PRIMARY KEY, value INTEGER NOT NULL)")
        database.commit()
    except sqlite3.DatabaseError:
        database.close()
        raise
    return database


def scan_shard(root, database, shard, apply, now, grace_ns):
    """Make the ledger's rows for one shard directory equal what is on disk; return what the scan saw and removed.

    Names that are not a unit object, its record or a staging file are left alone. A staging file idle for a day, and a record
    whose object is gone and that nothing has used for the grace period, are removed when `apply`. The shard's row keeps
    its object count, its bytes (staging files and kept orphan records included) and when it was read.
    """
    directory = root / "units-v1" / shard
    seen = {}
    other = 0
    removed = 0
    observed = 0
    try:
        scanner = os.scandir(directory)
    except (FileNotFoundError, NotADirectoryError):
        scanner = None
    if scanner is not None:
        with scanner as entries:
            for entry in entries:
                name = entry.name
                if name[:2] != shard:
                    continue
                matched = OBJECT.fullmatch(name)
                record = None if matched else RECORD.fullmatch(name)
                partial = None if matched or record else PARTIAL.fullmatch(name)
                if not (matched or record or partial):
                    continue
                try:
                    value = entry.stat(follow_symlinks=False)
                except FileNotFoundError:
                    continue
                if not stat.S_ISREG(value.st_mode):
                    continue
                observed += 1
                if partial:
                    if apply and last_use(value) < now - DAY_NS and drop(directory / name):
                        removed += 1
                    else:
                        other += allocated(value)
                elif matched:
                    item = seen.setdefault(matched.group(1), {})
                    item.update(osize=allocated(value), ino=value.st_ino, recent=last_use(value))
                else:
                    seen.setdefault(record.group(1), {}).update(rsize=allocated(value), rrecent=last_use(value))
    rows = {}
    for key, item in seen.items():
        if "ino" not in item:
            # A checksum record without its object is useless; keep it until it is idle, then collect it.
            if apply and item["rrecent"] < now - grace_ns and drop(directory / (key + ".o.sum")):
                removed += 1
            else:
                other += item["rsize"]
            continue
        rows[key] = (key, item["osize"] + item.get("rsize", 0), item["osize"], item["ino"], item["recent"])
    existing = {row[0]: row for row in database.execute(
        "SELECT key,size,osize,ino,recent FROM objects WHERE key>=? AND key<?", (shard, shard + "g"))}
    database.executemany("INSERT OR REPLACE INTO objects VALUES (?,?,?,?,?)",
                         [row for key, row in rows.items() if existing.get(key) != row])
    database.executemany("DELETE FROM objects WHERE key=?", [(key,) for key in existing if key not in rows])
    database.execute("INSERT OR REPLACE INTO shards VALUES (?,?,?,?)",
                     (shard, len(rows), sum(row[1] for row in rows.values()) + other, now))
    database.commit()
    return {"observed": observed, "partials_removed": removed}


def drop(path):
    """Unlink a regular file by name; a symlink, a directory or an absent name is left alone. True when it removed one."""
    value = lstat(path)
    if value is None or not stat.S_ISREG(value.st_mode):
        return False
    try:
        os.unlink(path)
    except FileNotFoundError:
        return False
    return True


def scan_due(root, database, apply, now, grace_ns, rescan_ns, deadline, statistics):
    """Read the shards not seen for `rescan_ns`, never-read ones first, until `deadline`; return how many remain unread."""
    known = dict(database.execute("SELECT shard, scanned FROM shards"))
    due = sorted((shard for shard in SHARDS if known.get(shard, 0) < now - rescan_ns), key=lambda shard: known.get(shard, 0))
    done = 0
    for shard in due:
        if time.monotonic() >= deadline:
            break
        result = scan_shard(root, database, shard, apply, now, grace_ns)
        statistics["metadata_observations"] += result["observed"]
        statistics["partials_removed"] += result["partials_removed"]
        done += 1
    statistics["shards_scanned"] += done
    return len(due) - done


def adopt_flat(root, database, now, deadline, statistics):
    """Give each flat-only object (an older compiler's, with no shard name) a shard name, then retire the flat names.

    Compilers read the shard first and then the flat name and write only shards, so a flat name with no shard name is a
    survivor of the layout before 13 October. Listing the flat directory costs a read of every name (a million), so this runs
    once a day (and again at once while a run ended before the listing did). An object that has no shard name is linked to one
    and the shard that gained a name is read again at once. An object that has one no longer needs its flat names: they are
    the same inode, so they hold no bytes, but each is a directory entry in a flat directory that held 1.7 million of them, and
    no compiler since the shard layout reads them. They are unlinked (the record first, so a lookup misses rather than
    verifying a half-removed pair); a compiler older than the layout would rebuild the object.
    """
    flat = root / "units-v1"
    adopted = set()
    keys = []
    complete = True
    with os.scandir(flat) as entries:
        for entry in entries:
            matched = OBJECT.fullmatch(entry.name)
            if matched:
                keys.append(matched.group(1))
            if len(keys) >= 4096:
                adopted |= adopt_batch(root, keys, statistics)
                keys = []
                if time.monotonic() >= deadline:
                    complete = False
                    break
    adopted |= adopt_batch(root, keys, statistics)
    for shard in adopted:
        database.execute("UPDATE shards SET scanned=0 WHERE shard=?", (shard,))
    database.commit()
    statistics["flat_adopted_shards"] = len(adopted)
    return complete


def adopt_batch(root, keys, statistics):
    """Give the flat objects of `keys` a shard name when they lack one, retire their flat names; return the shards that gained one."""
    gained = set()
    units = root / "units-v1"
    for key in keys:
        shard = units / key[:2]
        flat_object = units / (key + ".o")
        value = lstat(flat_object)
        if value is None or not stat.S_ISREG(value.st_mode):
            continue
        twin = lstat(shard / (key + ".o"))
        if twin is None:
            try:
                shard.mkdir(exist_ok=True)
                for suffix in (".o", ".o.sum"):
                    source = units / (key + suffix)
                    if lstat(source) is not None and stat.S_ISREG(lstat(source).st_mode):
                        os.link(source, shard / (key + suffix), follow_symlinks=False)
                gained.add(key[:2])
            except FileExistsError:
                pass
            twin = lstat(shard / (key + ".o"))
        if twin is None or not stat.S_ISREG(twin.st_mode):
            continue
        for suffix in (".o.sum", ".o"):
            if drop(units / (key + suffix)):
                statistics["flat_names_retired"] += 1
    return gained


def remove_object(root, key, row, apply, cutoff):
    """Remove one unit object, its record and its flat aliases, or leave it; return `(outcome, freed bytes)`.

    The outcomes are `removed`, `changed` (used, touched, replaced or published since the ledger saw it), `gone` (no object
    left under either layout) and `foreign` (not a regular file). The steps keep the object a build can still reach whole:

    1. Observe the shard and flat names. The primary must be the ledger's inode and must have been idle since `cutoff`.
    2. Rename every object name to a tombstone `<key>.o.<nonce>.partial` in its own directory. From here a lookup misses
       (its checksum record has no object), and a build that already holds the path keeps reading the open inode.
    3. Observe the tombstones: the same inode, size and modification time as in step 1. A touch (a hit refreshes the time) or
       a replacement that raced the rename puts every name back, unless a build has published a new object under the name.
    4. Unlink the records, then the tombstones.

    The window a build could lose an object to is the microseconds between steps 1 and 3 and only for an object idle past the
    grace period; the loss is a missing object at its link, which the next build repairs by compiling it again.
    """
    units = root / "units-v1"
    names = [units / key[:2] / (key + ".o"), units / (key + ".o")]
    found = [(path, lstat(path)) for path in names]
    present = [(path, value) for path, value in found if value is not None]
    if not present:
        return "gone", 0
    # The shard name is the object; a flat name is an alias only when it is a regular file (a symlink there is someone else's).
    if found[0][1] is not None and not stat.S_ISREG(found[0][1].st_mode):
        return "foreign", 0
    present = [(path, value) for path, value in present if stat.S_ISREG(value.st_mode)]
    if not present:
        return "foreign", 0
    primary = present[0][1]
    if primary.st_ino != row[3] or last_use(primary) >= cutoff:
        return "changed", primary
    if not apply:
        return "removed", row[1]
    staged = []
    nonce = secrets.token_hex(16)
    try:
        for path, value in present:
            tomb = path.with_name(f"{key}.o.{nonce}.partial")
            os.rename(path, tomb)
            staged.append((path, tomb, value))
        moved = all(_same(lstat(tomb), value) for _, tomb, value in staged)
    except OSError:
        moved = False
    if not moved:
        for path, tomb, _ in staged:
            try:
                os.link(tomb, path, follow_symlinks=False)
            except FileExistsError:
                pass
            except OSError:
                continue
            os.unlink(tomb)
        return "changed", lstat(names[0]) or lstat(names[1]) or primary
    for suffix_path in (units / key[:2] / (key + ".o.sum"), units / (key + ".o.sum")):
        drop(suffix_path)
    for _, tomb, _ in staged:
        try:
            os.unlink(tomb)  # this process made the name a moment ago: it is a regular file of ours
        except FileNotFoundError:
            pass
    return "removed", row[1]


def _same(after, before):
    """A tombstone still has the identity, size and modification time its name was observed with."""
    return after is not None and (after.st_ino, after.st_size, after.st_mtime_ns) == (before.st_ino, before.st_size, before.st_mtime_ns)


def attempt(root, row, apply, cutoff):
    """`remove_object` for a ledger row; an OSError (a permission, a full journal) is an outcome, not an exception."""
    try:
        return remove_object(root, row[0], row, apply, cutoff)
    except OSError:
        return "error", None


def settle(pool, root, group, apply, cutoff):
    """The outcomes for a group of candidates, in order. The file system work of a group runs on the pool's threads: it is
    a handful of metadata operations per object waiting on a disk that other builds are using, so threads overlap the waits."""
    if pool is None or len(group) == 1:
        return [attempt(root, row, apply, cutoff) for row in group]
    return list(pool.map(lambda row: attempt(root, row, apply, cutoff), group))


def evict(root, database, options, now, deadline, statistics):
    """Remove unit objects by the ledger's order of last use: those idle past `days`, then, over budget, the oldest.

    Candidates come from the `recent` index, a few hundred at a time, so the cost is the objects visited. Budget eviction
    stops at 90% of the budget and never removes an object used within the grace period (its bytes are reported as
    `fresh_bytes`). Before the ledger has read every shard it counts only some of the store, so only age eviction runs.
    """
    totals = database.execute("SELECT coalesce(sum(bytes),0), count(*) FROM shards WHERE scanned>0").fetchone()
    primed = totals[1] == len(SHARDS)
    retained = totals[0] + statistics["root_bytes"]
    maximum = options["maximum"]
    target = maximum * 9 // 10 if retained > maximum else maximum
    age_cutoff = now - options["days"] * DAY_NS
    grace_cutoff = now - options["grace_ns"]
    apply = options["apply"]
    workers = options["workers"]
    pool = ThreadPoolExecutor(workers) if apply and workers > 1 else None
    group_size = workers * 8 if pool is not None else 1
    if not apply:
        database.execute("SAVEPOINT eviction")
    removed_bytes = removed_entries = 0
    more = False
    stalled = False
    try:
        for phase, cutoff, limit in (("age", age_cutoff, options["batch"]), ("budget", grace_cutoff, None)):
            phase_removed = 0
            while True:
                if phase == "budget" and (not primed or retained <= target):
                    break
                if limit is not None and phase_removed >= limit:
                    more = True
                    break
                if time.monotonic() >= deadline:
                    more = True
                    break
                rows = database.execute("SELECT key,size,osize,ino,recent FROM objects WHERE recent<? ORDER BY recent,key LIMIT ?",
                                        (cutoff, CHUNK)).fetchall()
                if not rows:
                    break
                progress = position = 0
                while position < len(rows):
                    if time.monotonic() >= deadline or (limit is not None and phase_removed >= limit):
                        more = True
                        break
                    if phase == "budget" and retained <= target:
                        break
                    size = group_size if limit is None else max(1, min(group_size, limit - phase_removed))
                    if phase == "budget":
                        # Take no more than the target needs, so a group removes what one object at a time would have.
                        needed, taken = retained - target, 0
                        for row in rows[position:position + size]:
                            taken += 1
                            needed -= row[1]
                            if needed <= 0:
                                break
                        size = taken
                    group = rows[position:position + size]
                    position += len(group)
                    for row, (outcome, detail) in zip(group, settle(pool, root, group, apply, cutoff)):
                        key = row[0]
                        if outcome == "removed":
                            database.execute("DELETE FROM objects WHERE key=?", (key,))
                            database.execute("UPDATE shards SET objects=objects-1, bytes=bytes-? WHERE shard=?", (row[1], key[:2]))
                            retained -= row[1]
                            removed_bytes += row[1]
                            removed_entries += 1
                            phase_removed += 1
                            progress += 1
                        elif outcome == "changed":
                            retained += refresh(database, row, detail, now, cutoff)
                            progress += 1
                        elif outcome == "gone":
                            database.execute("DELETE FROM objects WHERE key=?", (key,))
                            database.execute("UPDATE shards SET objects=objects-1, bytes=bytes-? WHERE shard=?", (row[1], key[:2]))
                            retained -= row[1]
                            progress += 1
                        elif outcome == "error":
                            statistics["errors"] += 1
                        else:
                            # A name that is not a regular file: leave it, and stop asking about the same row this run.
                            database.execute("UPDATE objects SET recent=? WHERE key=?", (now, key))
                            progress += 1
                if apply:
                    database.commit()
                if more:
                    break
                if progress == 0:
                    stalled = True
                    break
    finally:
        if pool is not None:
            pool.shutdown()
    if apply:
        database.commit()
    else:
        database.execute("ROLLBACK TO eviction")
        database.execute("RELEASE eviction")
    fresh = database.execute("SELECT coalesce(sum(size),0) FROM objects WHERE recent>=?", (grace_cutoff,)).fetchone()[0]
    return {"removed_bytes": removed_bytes, "removed_entries": removed_entries, "retained_bytes": retained,
            "target_bytes": target, "more": more, "stalled": stalled, "fresh_bytes": fresh, "inventory_complete": primed,
            "unmet_target": retained > target, "unmet_budget": retained > maximum}


def refresh(database, row, current, now, cutoff):
    """Record what a candidate looks like now (it was used, touched or replaced) so it leaves the old end of the order.

    Returns the change in the object's bytes. A candidate that is still older than `cutoff` after the refresh is pushed to
    `now` so that it is not asked about again in this run; the next read of its shard sets the truth.
    """
    recent = last_use(current)
    if recent < cutoff:
        recent = now
    delta = allocated(current) - row[2]
    database.execute("UPDATE objects SET ino=?, osize=?, size=size+?, recent=? WHERE key=?",
                     (current.st_ino, allocated(current), delta, recent, row[0]))
    database.execute("UPDATE shards SET bytes=bytes+? WHERE shard=?", (delta, row[0][:2]))
    return delta


def reclaim_claims(root, limit, apply, deadline):
    """Remove idle work claims, at most `limit`, until `deadline`.

    A claim is idle when its flock can be taken without waiting. The compiler's `storage.lock` checks after it locks that
    the name still refers to the file it holds and otherwise reopens, so a builder that opened the file just before this
    removal retries on the new one and mutual exclusion holds. A preview counts files without locking any.
    """
    removed = 0
    for namespace in (root, root / "units-v1"):
        directory = namespace / "work"
        if not directory.is_dir() or directory.is_symlink():
            continue
        with os.scandir(directory) as entries:
            for entry in entries:
                if removed >= limit or time.monotonic() >= deadline:
                    return removed
                if not CLAIM.fullmatch(entry.name) or not entry.is_file(follow_symlinks=False):
                    continue
                if not apply:
                    removed += 1
                    continue
                removed += idle_claim_removed(entry.path)
    return removed


def idle_claim_removed(path):
    """1 when `path` was an unheld claim file and is now gone, else 0."""
    try:
        descriptor = os.open(path, os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC)
    except OSError:
        return 0
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        current = lstat(path)
        if current is None or not stat.S_ISREG(current.st_mode) or current.st_ino != os.fstat(descriptor).st_ino:
            return 0
        os.unlink(path)
        return 1
    except OSError:
        return 0
    finally:
        os.close(descriptor)


def root_files(root):
    """The runtime objects and staging files in the root: `(path, lstat)` pairs."""
    found = []
    with os.scandir(root) as entries:
        for entry in entries:
            if not (RUNTIME.fullmatch(entry.name) or PARTIAL.fullmatch(entry.name)):
                continue
            try:
                value = entry.stat(follow_symlinks=False)
            except FileNotFoundError:
                continue
            if stat.S_ISREG(value.st_mode):
                found.append((Path(entry.path), value))
    return found


def trim_root(root, files, options, now, statistics):
    """Remove runtime objects idle for `days` (and staging files for a day) inside a try-exclusive window on the root lease.

    A runtime object is read by path under the shared root lease for a whole build and nothing refreshes it, so it can only be
    removed while no build holds the lease; when one does, the window is skipped and the next run tries again. Whatever is
    removed was observed again under the lease. The lease is held for at most `window_seconds`.
    """
    expired = [(path, value) for path, value in files
               if last_use(value) < now - (DAY_NS if PARTIAL.fullmatch(path.name) else options["days"] * DAY_NS)]
    statistics["root_expired"] = len(expired)
    if not expired:
        return
    if not options["apply"]:
        statistics["root_removed"] = len(expired)
        statistics["root_bytes"] -= sum(allocated(value) for _, value in expired)
        return
    started = time.monotonic()
    try:
        with locked(root / ".retention.lock", fcntl.LOCK_EX, 0.0):
            deadline = started + options["window_seconds"]
            for path, value in expired:
                if time.monotonic() >= deadline:
                    break
                current = lstat(path)
                if current is None or (current.st_ino, last_use(current)) != (value.st_ino, last_use(value)):
                    continue
                if drop(path):
                    statistics["root_removed"] += 1
                    statistics["root_bytes"] -= allocated(value)
        statistics["exclusive_seconds"] = time.monotonic() - started
    except BlockingIOError:
        statistics["root_busy"] = True


def _maintain(root, *, apply=False, maximum=10 << 30, days=14, batch=10000, claims=500000,
              grace_seconds=GRACE_SECONDS, scan_seconds=240.0, evict_seconds=600.0, rescan_seconds=6 * 3600.0,
              flat_seconds=24 * 3600.0, window_seconds=2.0, claim_seconds=60.0, ledger=None, flat_budget=300.0, workers=8):
    """One bounded run: re-read the shards that are due, then evict by the ledger, then tidy claims and the root.

    Nothing here takes a lease builders wait on. `scan_seconds`, `evict_seconds`, `claim_seconds` and `flat_budget` each bound
    one phase; `rescan_seconds` is how stale a shard may get before it is read again, so a store is wholly re-read about every
    `rescan_seconds` and a run reads its share (all of it, the first time, as far as `scan_seconds` allows).
    """
    root = Path(root).absolute()
    report = {"root": str(root), "dry_run": not apply, "skipped_active": False, "skipped_incomplete": False,
              "inventory_complete": False, "maximum_bytes": maximum, "grace_seconds": grace_seconds,
              "exclusive_seconds": 0.0, "shards_scanned": 0, "metadata_observations": 0, "partials_removed": 0,
              "errors": 0, "root_bytes": 0, "root_removed": 0, "root_busy": False, "flat_names_retired": 0}
    if not root.exists():
        return {**report, "inventory_complete": True, "inventory_bytes": 0, "inventory_entries": 0,
                "retained_bytes": 0, "unmet_budget": False}
    if root.is_symlink():
        raise ValueError(f"symlink store: {root}")
    (root / "units-v1").mkdir(exist_ok=True)
    if (root / "units-v1").is_symlink():
        raise ValueError(f"symlink namespace: {root / 'units-v1'}")
    with locked(root / ".store-maintenance.lock", fcntl.LOCK_EX):
        path = Path(ledger) if ledger else root / LEDGER
        if path.is_symlink():
            raise ValueError(f"symlink ledger: {path}")
        now = time.time_ns()
        grace_ns = int(grace_seconds * SECOND)
        with closing(open_ledger(path)) as database:
            started = time.monotonic()
            report["unscanned_shards"] = scan_due(root, database, apply, now, grace_ns, int(rescan_seconds * SECOND),
                                                  started + scan_seconds, report)
            if report["unscanned_shards"] == 0 and apply and flat_budget > 0 and flat_due(database, now, flat_seconds):
                flat_started = time.monotonic()
                complete = adopt_flat(root, database, now, flat_started + flat_budget, report)
                if complete:
                    database.execute("INSERT OR REPLACE INTO meta VALUES ('flat_listed', ?)", (now,))
                    database.commit()
                report["flat_listed"] = complete
                report["unscanned_shards"] = scan_due(root, database, apply, now, grace_ns, int(rescan_seconds * SECOND),
                                                      time.monotonic() + scan_seconds, report)
                report["flat_seconds"] = time.monotonic() - flat_started
            report["scan_seconds"] = time.monotonic() - started
            files = root_files(root)
            report["root_bytes"] = sum(allocated(value) for _, value in files)
            options = {"apply": apply, "maximum": maximum, "days": days, "batch": batch, "grace_ns": grace_ns,
                       "window_seconds": window_seconds, "workers": workers}
            totals = database.execute("SELECT coalesce(sum(objects),0), coalesce(sum(bytes),0) FROM shards").fetchone()
            report["inventory_entries"] = totals[0] * 2 + len(files)
            report["inventory_bytes"] = totals[1] + report["root_bytes"]
            trim_root(root, files, options, now, report)
            started = time.monotonic()
            report.update(evict(root, database, options, now, started + evict_seconds, report))
            report["evict_seconds"] = time.monotonic() - started
            started = time.monotonic()
            report["idle_claims_removed"] = reclaim_claims(root, claims, apply, started + claim_seconds)
            report["claims_seconds"] = time.monotonic() - started
            report["shards_total"] = len(SHARDS)
    return report


def flat_due(database, now, interval):
    """True when the flat directory has not been listed for `interval` seconds."""
    row = database.execute("SELECT value FROM meta WHERE name='flat_listed'").fetchone()
    return row is None or row[0] < now - int(interval * SECOND)


def store_status(report):
    """One line a scheduled run, the pruner and --list-kept can show."""
    retained = report.get("retained_bytes") or 0
    maximum = report.get("maximum_bytes") or 0
    gib = lambda value: value / (1 << 30)
    if report.get("skipped_active"):
        state = "skipped: another maintenance run holds the store"
    elif report.get("skipped_incomplete"):
        state = "INCOMPLETE after %d attempt(s); nothing evicted" % (report.get("incomplete_attempts") or 0)
    elif not report.get("inventory_complete"):
        state = "priming: %d of %d shards read; only idle objects evicted so far (retained %.2f GiB on disk of %.2f GiB)" % (
            max(0, (report.get("shards_total") or 256) - (report.get("unscanned_shards") or 0)),
            report.get("shards_total") or 256, gib(retained), gib(maximum))
    elif report.get("unmet_budget") or report.get("unmet_target"):
        fresh = report.get("fresh_bytes") or 0
        state = "OVER BUDGET: retained %.2f GiB on disk of %.2f GiB (%.2f GiB used within the grace period)" % (
            gib(retained), gib(maximum), gib(fresh))
    else:
        state = "complete; retained %.2f GiB on disk of %.2f GiB" % (gib(retained), gib(maximum))
    return "store: " + state


def record_status(root, report):
    """Persist the last run's verdict for --list-kept without another scan."""
    root = Path(root)
    if not root.is_dir():
        return
    path = root / ".last-maintenance.json"
    temporary = path.with_name(path.name + "." + str(os.getpid()) + ".tmp")
    keys = ("inventory_complete", "skipped_active", "skipped_incomplete", "unmet_budget", "unmet_target", "retained_bytes",
            "maximum_bytes", "incomplete_attempts", "complete_attempts", "fresh_bytes", "unscanned_shards", "shards_total")
    try:
        temporary.write_text(json.dumps({key: report.get(key) for key in keys}) + "\n")
        os.replace(temporary, path)
    except OSError:
        temporary.unlink(missing_ok=True)


def drop_obsolete_ledgers(root):
    """Delete the earlier size ledgers once the current one has read every shard: nothing reads them, and v2 was 1.3 GB."""
    for version in (1, 2, 3):
        for suffix in ("", "-wal", "-shm"):
            old = Path(root) / f".size-ledger-v{version}.sqlite3{suffix}"
            if signature(old) is not None:
                old.unlink(missing_ok=True)


def maintain(root, **options):
    """Attach operational cost to every run."""
    before = resource.getrusage(resource.RUSAGE_SELF)
    started = time.monotonic()
    try:
        result = _maintain(root, **options)
    except BlockingIOError:
        result = {"root": str(root), "dry_run": not options.get("apply"), "skipped_active": True, "unmet_budget": True,
                  "maximum_bytes": options.get("maximum", 10 << 30)}
    apply = options.get("apply")
    if apply and result.get("inventory_complete") and not result.get("skipped_active"):
        drop_obsolete_ledgers(root)
    after = resource.getrusage(resource.RUSAGE_SELF)
    ledger = Path(options["ledger"]) if options.get("ledger") else Path(root) / LEDGER
    ledger_bytes = 0
    for suffix in ("", "-wal", "-shm"):
        entry = signature(Path(str(ledger) + suffix))
        if entry is not None:
            ledger_bytes += entry[2]
    if apply:
        record_status(root, result)
    result.update(ledger_bytes=ledger_bytes, elapsed_seconds=time.monotonic() - started,
                  cpu_seconds=(after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime),
                  input_blocks=after.ru_inblock - before.ru_inblock,
                  output_blocks=after.ru_oublock - before.ru_oublock,
                  process_peak_rss_kib=after.ru_maxrss)
    return result


def collect_tools(tools, *, apply=False, maximum=TOOLS_MAXIMUM, days=14):
    """Bound the toolchain identity memos: no file idle for DAYS days, and at most MAXIMUM bytes.

    The memos are caches: a missing one is derived again (hashing the toolchain closure, seconds), a damaged one is a miss, and
    every publication is a rename, so a reader holds a whole file or none. Nothing here needs a lease. A file's recency is the
    later of its modification and access times, as for the object store; a staged `.pending` file expires after a day. Over the
    byte bound the least recently used files go first, down to 90% of it. Only files with the memo names are touched, symlinks
    and unknown names stay, and a file replaced since the inventory (a different inode, size or time) is kept.
    """
    report = {"tools_root": str(tools), "tools_entries": 0, "tools_bytes": 0, "tools_removed_files": 0,
              "tools_removed_bytes": 0, "tools_retained_bytes": 0, "tools_maximum_bytes": maximum}
    tools = Path(tools)
    if tools.is_symlink() or not tools.is_dir():
        return report
    now = time.time_ns()
    cutoff = now - days * 86400 * 1_000_000_000
    pending_cutoff = now - 86400 * 1_000_000_000
    found = []
    for name in TOOL_DIRECTORIES:
        directory = tools / name
        if directory.is_symlink() or not directory.is_dir():
            continue
        with os.scandir(directory) as entries:
            for entry in entries:
                pending = TOOL_PENDING.fullmatch(entry.name) is not None
                if not pending and not TOOL_MEMO.fullmatch(entry.name):
                    continue
                try:
                    value = entry.stat(follow_symlinks=False)
                except FileNotFoundError:
                    continue
                if stat.S_ISREG(value.st_mode):
                    found.append((max(value.st_mtime_ns, value.st_atime_ns), Path(entry.path), pending, signature(Path(entry.path))))
    found.sort(key=lambda item: item[0])
    total = sum(item[3][2] for item in found if item[3] is not None)
    report.update(tools_entries=len(found), tools_bytes=total)
    expired = [item for item in found if item[0] < (pending_cutoff if item[2] else cutoff)]
    remaining = total - sum(item[3][2] for item in expired if item[3] is not None)
    chosen = list(expired)
    if remaining > maximum:
        target = maximum * 9 // 10
        taken = {id(item) for item in expired}
        for item in found:
            if remaining <= target:
                break
            if id(item) in taken or item[3] is None:
                continue
            chosen.append(item)
            remaining -= item[3][2]
    for _recent, path, _pending, seen in chosen:
        if seen is None or signature(path) != seen:
            continue
        if apply:
            try:
                path.unlink()
            except FileNotFoundError:
                continue
        report["tools_removed_files"] += 1
        report["tools_removed_bytes"] += seen[2]
    report["tools_retained_bytes"] = total - report["tools_removed_bytes"]
    return report


# A harness that must not touch the user's own store names it here (paths joined by os.pathsep): a run that targets one of them
# is refused whatever else it asks. The retention tests do this for the default per-user store, so a gate never collects it.
DENY_ENVIRONMENT = "SELKA_STORE_GC_DENY"


def denied(store):
    """True when `store` is one of the stores `SELKA_STORE_GC_DENY` forbids."""
    listed = [path for path in os.environ.get(DENY_ENVIRONMENT, "").split(os.pathsep) if path]
    resolved = os.path.realpath(store)
    return any(os.path.realpath(path) == resolved for path in listed)


def user_store_roots(environment=None):
    """Where an unset `SELKA_CORE_RUNTIME_CACHE` sends the compiler: under `XDG_CACHE_HOME` when absolute, else under HOME."""
    environment = os.environ if environment is None else environment
    roots = []
    xdg = environment.get("XDG_CACHE_HOME", "")
    if xdg.startswith("/"):
        roots.append(str(Path(xdg) / "selka" / "core-runtime"))
    home = environment.get("HOME", "")
    if home.startswith("/"):
        roots.append(str(Path(home) / ".cache" / "selka" / "core-runtime"))
    return roots


def default_root():
    if "SELKA_CORE_RUNTIME_CACHE" in os.environ:
        return os.environ["SELKA_CORE_RUNTIME_CACHE"]
    xdg = os.environ.get("XDG_CACHE_HOME", "")
    base = Path(xdg) if xdg.startswith("/") else Path.home() / ".cache"
    return str(base / "selka" / "core-runtime")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--store", default=default_root())
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--max-bytes", type=int, default=10 << 30)
    parser.add_argument("--max-age-days", type=int, default=14)
    parser.add_argument("--tools-store", default=None,
                        help="the toolchain identity memos to bound (default: core-tools-v1 beside --store)")
    parser.add_argument("--tools-max-bytes", type=int, default=TOOLS_MAXIMUM,
                        help="bytes the toolchain identity memos may hold (the age bound is --max-age-days)")
    parser.add_argument("--batch-size", type=int, default=10000,
                        help="most objects idle past --max-age-days removed per run; over-budget eviction continues to the 90%% target")
    parser.add_argument("--claim-batch-size", type=int, default=500000,
                        help="idle work-claim files removed per run (cheap unlinks, bounded separately)")
    parser.add_argument("--grace-hours", type=float, default=GRACE_SECONDS / 3600,
                        help="an object used within this many hours is never removed, whatever the budget")
    parser.add_argument("--scan-seconds", type=float, default=240.0, help="time a run may spend re-reading shards")
    parser.add_argument("--evict-seconds", type=float, default=600.0, help="time a run may spend evicting")
    parser.add_argument("--rescan-hours", type=float, default=6.0, help="how stale a shard's ledger rows may get before it is read again")
    parser.add_argument("--workers", type=int, default=8, help="threads that remove objects (their file system waits overlap)")
    parser.add_argument("--ledger", default=None, help="the ledger file (default: inside the store)")
    options = parser.parse_args(argv)
    if min(options.max_bytes, options.max_age_days) < 0 or min(options.batch_size, options.claim_batch_size) < 1:
        parser.error("limits must be nonnegative and batch sizes positive")
    if not options.store:
        print(json.dumps({"disabled": True, "dry_run": not options.apply}))
        return 0
    if denied(options.store):
        print(json.dumps({"error": f"{options.store} is named by {DENY_ENVIRONMENT}: a test must collect a private store",
                          "refused": True, "unmet_budget": True}))
        return 2
    try:
        report = maintain(options.store, apply=options.apply, maximum=options.max_bytes,
                          days=options.max_age_days, batch=options.batch_size,
                          claims=options.claim_batch_size, grace_seconds=options.grace_hours * 3600,
                          scan_seconds=options.scan_seconds, evict_seconds=options.evict_seconds,
                          rescan_seconds=options.rescan_hours * 3600, ledger=options.ledger,
                          workers=max(1, options.workers))
    except (OSError, ValueError, sqlite3.DatabaseError) as error:
        print(json.dumps({"error": str(error), "unmet_budget": True}))
        return 1
    tools = options.tools_store if options.tools_store is not None else str(Path(options.store).absolute().parent / "core-tools-v1")
    try:
        report.update(collect_tools(tools, apply=options.apply, maximum=options.tools_max_bytes, days=options.max_age_days))
    except OSError as error:
        report["tools_error"] = str(error)
    print(json.dumps(report, sort_keys=True))
    print(store_status(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
