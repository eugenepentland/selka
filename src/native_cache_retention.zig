//! Cooperative, bounded retention for versioned native shared caches.
const std = @import("std");
const storage = @import("shared_artifact_io.zig");
const partial_suffix = ".partial";
const lease_leaf = ".retention.lock";
/// Held by the one sweep that runs while builders hold shared leases (`Context.sweep`).
const sweeper_leaf = ".sweep.lock";
const policy_leaf = "retention-policy";
const last_leaf = "retention-last";
const mismatch_leaf = "mismatches.log";
/// How long a file touched by a hit is left alone before another hit refreshes it again (`Context.touch`).
pub const touch_interval_ns: i64 = 3600 * std.time.ns_per_s;
/// Native storage errors, including malformed policy or namespace metadata.
pub const Error = storage.Error;
/// The retention clock: Unix-epoch nanoseconds, read only to space and age disposable entries.
pub fn retentionNanoseconds(io: std.Io) i96 {
    return @import("infra/clock.zig").retentionNow(io);
}
/// How many times opening a store attempts namespace creation before a failure
/// is final (SHARED-STORE-6).
pub const initialization_attempts = 4;

/// Run `step(context)` until it succeeds or `initialization_attempts` attempts
/// have failed, returning the last failure; running out of memory is final at
/// once. Concurrent first openers of one namespace use it so that an attempt
/// that lost a race to a peer re-reads what the peer published.
pub fn retried(context: anytype, comptime step: anytype) @typeInfo(@TypeOf(step)).@"fn".return_type.? {
    var attempt: usize = 1;
    while (true) : (attempt += 1) {
        if (step(context)) |_| return else |err| {
            if (err == error.OutOfMemory or attempt == initialization_attempts) return err;
        }
    }
}
/// Independent cooperative namespaces; legacy writers never enter these roots.
pub const Kind = enum {
    compiler,
    tests,
    /// Return the dedicated directory beneath a configured shared root.
    pub fn namespace(self: Kind) []const u8 {
        return switch (self) {
            .compiler => "compiler-artifacts-v2",
            .tests => "native-tests-v3",
        };
    }
    /// Return the exact namespace marker accepted by retention.
    pub fn format(self: Kind) []const u8 {
        return switch (self) {
            .compiler => "selka-compiler-artifact-store-v2\n",
            .tests => "selka-native-test-store-v3\n",
        };
    }
};
/// What a namespace directory is, judged without writing anything: why it can or cannot be opened.
pub const Condition = enum {
    /// Absent, or holding only control files: opening it initializes it.
    fresh,
    /// Carries this kind's current format marker.
    initialized,
    /// Has a `format` entry that is not this kind's marker (another version's, damaged, empty or not a file).
    /// Never overwritten: only a person knows whether its contents may be read.
    bad_marker,
    /// No marker, but every entry is a control file or one of this kind's own directories: a namespace that lost its marker.
    unmarked,
    /// No marker and entries that are not this cache's: not a namespace this tool may adopt.
    foreign,
};

/// Soft quotas applied at collection time, with age expiration disabled by default.
pub const Policy = struct {
    max_bytes: u64,
    max_entries: usize,
    max_age_seconds: u64 = 0,
    interval_seconds: u64 = 1800,
    /// Return namespace-specific bounded retention defaults.
    pub fn defaults(kind: Kind) Policy {
        return .{ .max_bytes = if (kind == .compiler) 10 * 1024 * 1024 * 1024 else 256 * 1024 * 1024, .max_entries = 100000 };
    }
    /// Reject durations that cannot be represented by the clock boundary.
    pub fn validate(self: Policy) Error!void {
        if (self.max_age_seconds > std.math.maxInt(i64) or self.interval_seconds > std.math.maxInt(i64)) return error.ReadFailed;
    }
};
/// One determinism mismatch: a verified record and an attempted publication disagree.
pub const Mismatch = struct { kind: []const u8, key: [32]u8, existing: [32]u8, attempted: [32]u8 };
/// Counted artifact inventory; lock and policy overhead is excluded.
pub const Counts = struct { entries: usize = 0, bytes: u64 = 0 };
/// How far one inventory got through a namespace: the directory entries it inspected, the ones
/// past the visit bound that it only counted, and whether it reached the end.
pub const Walk = struct {
    visited: usize = 0,
    unvisited: usize = 0,
    complete: bool = true,
    /// The sweep ran beside builders that held shared leases, so it evicted only the entries that need no exclusive lease.
    leased: bool = false,
};
/// Collection evidence, including busy leases and incomplete inventories. `inventory` counts the
/// records inspected, `removed` those evicted (or proposed, in a preview) and `retained` those
/// kept. When `walk` is incomplete these describe only the visited window: the namespace also holds
/// whatever `walk.unvisited` counted, which the sweep did not inspect.
pub const Report = struct {
    skipped_active: bool = false,
    dry_run: bool = false,
    inventory: Counts = .{},
    removed: Counts = .{},
    retained: Counts = .{},
    unmet_budget: bool = false,
    walk: Walk = .{},
};
/// How many directory entries one inventory inspects: the memory bound of a sweep, and the most
/// records one sweep can evict. Entries past it are counted, not inspected.
const hard_limit = 1000000;
/// The suffix of the file a test receipt keeps its work counts in, beside the receipt
/// (`core/test_work.zig`, which a test there checks against this).
const sidecar_suffix = ".work";
/// How many records one automatic sweep evicts at most, so that a store far past its policy is
/// trimmed over several sweeps rather than by one that holds the store for minutes. Lock files and staging files go
/// beside the records and do not count: a record brings its lock, and a batch spent on locks would evict none.
const automatic_batch = 250000;
/// How long a staging file must have been idle before a sweep that runs beside publishers removes it: a publication
/// stages, renames and ends within milliseconds, so an older one was abandoned.
const abandoned_seconds = 600;
/// `leasable` entries need no exclusive lease to be removed: they are immutable and checked on every read, so a reader holds one
/// whole through its open handle or misses it, and a publisher of the same key is kept out by the key's lock file.
const Entry = struct { path: []u8, size: u64, mtime: i96, transient: bool, leasable: bool = false };
const Inventory = struct {
    entries: std.ArrayList(Entry) = .empty,
    foreign: bool = false,
    walk: Walk = .{},
    /// Count one more directory entry against `limit`. False once the bound is passed: the entry
    /// is only tallied as unvisited, and the walk is incomplete.
    fn visit(self: *Inventory, limit: usize) bool {
        if (self.walk.visited >= limit) {
            self.walk.complete = false;
            self.walk.unvisited += 1;
            return false;
        }
        self.walk.visited += 1;
        return true;
    }
};
/// Borrowed namespace context; callers retain the root path for its lifetime.
pub const Context = struct {
    scratch: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    kind: Kind,
    /// Directory entries an inventory may inspect; past it the inventory is incomplete and the
    /// sweep works on the entries it inspected.
    visit_limit: usize = hard_limit,
    /// Records one automatic sweep may evict; a forced collection is not capped.
    batch_limit: usize = automatic_batch,
    /// Bind an existing or caller-created namespace without initializing its format.
    pub fn init(a: std.mem.Allocator, io: std.Io, root: []const u8, kind: Kind) Context {
        return .{ .scratch = a, .io = io, .root = root, .kind = kind };
    }
    /// Hold the permanent cooperative shared inode through the entire operation.
    pub fn lease(self: Context) Error!std.Io.File {
        const file = try self.lockFile(true);
        errdefer file.close(self.io);
        file.lock(self.io, .shared) catch return error.WriteFailed;
        return file;
    }
    /// Take the exclusive lease only when no process holds the namespace at all (no shared lease and no
    /// sweep); null means one does and the caller skips its work instead of waiting.
    pub fn tryExclusive(self: Context) Error!?std.Io.File {
        return self.exclusive(true);
    }
    /// Take the shared lease only when no collection holds the namespace; null
    /// means a sweep is running and the caller skips its write instead of waiting.
    pub fn tryLease(self: Context) Error!?std.Io.File {
        const file = try self.lockFile(true);
        errdefer file.close(self.io);
        if (!(file.tryLock(self.io, .shared) catch return error.WriteFailed)) {
            file.close(self.io);
            return null;
        }
        return file;
    }
    /// Append one line to `<root>/mismatches.log` with a single append write; no
    /// timestamp. Best effort: a log failure never turns the miss into an error.
    pub fn mismatch(self: Context, found: Mismatch) void {
        var buffer: [384]u8 = undefined;
        const hex = .{ std.fmt.bytesToHex(found.key, .lower), std.fmt.bytesToHex(found.existing, .lower), std.fmt.bytesToHex(found.attempted, .lower) };
        const line = std.fmt.bufPrint(&buffer, "mismatch {s} {s} existing={s} attempted={s}\n", .{ found.kind, hex[0], hex[1], hex[2] }) catch return;
        const path = self.joinPath(mismatch_leaf) catch return;
        defer self.scratch.free(path);
        const name = self.scratch.dupeSentinel(u8, path, 0) catch return;
        defer self.scratch.free(name);
        const linux = std.os.linux;
        const fd = linux.open(name, .{ .ACCMODE = .WRONLY, .APPEND = true, .CREAT = true, .CLOEXEC = true, .NOFOLLOW = true, .NONBLOCK = true }, 0o600);
        if (linux.errno(fd) != .SUCCESS) return;
        const file: std.Io.File = .{ .handle = @intCast(fd), .flags = .{ .nonblocking = true } };
        defer file.close(self.io);
        file.writeStreamingAll(self.io, line) catch return;
    }
    /// Refresh verified-hit recency without affecting record validity. A file touched within `touch_interval_ns` stays as it is: retention
    /// counts days, and the touch is a metadata write (a journal commit) that a fresh build pays once for every shared record it reads, about
    /// 1,100 at the 99k port, where each costs 0.3 ms on a quiet disk and several milliseconds on a loaded one (G4c-2c-2).
    pub fn touch(self: Context, file: std.Io.File) void {
        if (file.stat(self.io)) |status| {
            const clock: i64 = @truncate(std.Io.Timestamp.now(self.io, .real).nanoseconds);
            if (clock - @as(i64, @truncate(status.mtime.nanoseconds)) < touch_interval_ns) return;
        } else |_| {}
        file.setTimestamps(self.io, .{ .modify_timestamp = .now }) catch return;
    }
    /// Refresh a verified path without following its final symlink.
    pub fn touchPath(self: Context, name: []const u8) void {
        const file = (storage.regular(self.scratch, self.io, name) catch return) orelse return;
        defer file.close(self.io);
        self.touch(file);
    }
    /// Read an exact bounded policy, using defaults only when no policy exists.
    pub fn policy(self: Context) Error!Policy {
        const path = try self.joinPath(policy_leaf);
        defer self.scratch.free(path);
        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{ .follow_symlinks = false }) catch |err| {
            if (err == error.FileNotFound) return Policy.defaults(self.kind);
            return error.ReadFailed;
        };
        if (stat.kind != .file) return error.ReadFailed;
        const bytes = try storage.bounded(self.scratch, self.io, path, 1024) orelse return error.ReadFailed;
        defer self.scratch.free(bytes);
        const parsed = std.json.parseFromSlice(Policy, self.scratch, bytes, .{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.ReadFailed,
        };
        defer parsed.deinit();
        try parsed.value.validate();
        return parsed.value;
    }
    /// Persist policy atomically under exclusive admission; return false when busy.
    pub fn configure(self: Context, value: Policy) Error!bool {
        try value.validate();
        try self.validate();
        const guard = try self.exclusive(true) orelse return false;
        defer guard.close(self.io);
        try self.validate();
        const bytes = std.json.Stringify.valueAlloc(self.scratch, value, .{}) catch return error.OutOfMemory;
        defer self.scratch.free(bytes);
        try self.writeControl(policy_leaf, bytes);
        return true;
    }
    /// Perform a throttled best-effort sweep; callers must first release their lease.
    /// The sweep builds its inventory (a path for every receipt, a million at most)
    /// in an arena of its own that it releases on return, whatever allocator the
    /// caller bound: a caller whose allocator only grows, such as a test root's
    /// arena, would otherwise keep a whole inventory for every store it opened.
    pub fn automatic(self: Context) void {
        // allocator-ok: the callers bind arenas that never free, so the sweep needs a backing of its own
        var inventory_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer inventory_arena.deinit();
        var private = self;
        private.scratch = inventory_arena.allocator();
        _ = private.sweep(null, false, true) catch return;
    }
    /// Force collection or preview it without initializing absent or legacy roots.
    pub fn collect(self: Context, override: ?Policy, dry_run: bool) Error!Report {
        return self.sweep(override, dry_run, false);
    }

    /// Classify the namespace directory without writing anything (`Condition`).
    pub fn condition(self: Context) Error!Condition {
        const marker = try self.joinPath("format");
        defer self.scratch.free(marker);
        const info = std.Io.Dir.cwd().statFile(self.io, marker, .{ .follow_symlinks = false }) catch |err| {
            if (err == error.FileNotFound or err == error.NotDir) return self.layout();
            return error.ReadFailed;
        };
        if (info.kind != .file) return .bad_marker;
        const bytes = try storage.bounded(self.scratch, self.io, marker, 128) orelse return .bad_marker;
        defer self.scratch.free(bytes);
        return if (std.mem.eql(u8, bytes, self.kind.format())) .initialized else .bad_marker;
    }

    /// The condition of a directory with no marker: by what it holds.
    fn layout(self: Context) Error!Condition {
        var root = std.Io.Dir.cwd().openDir(self.io, self.root, .{ .iterate = true, .follow_symlinks = false }) catch |err| {
            return if (err == error.FileNotFound or err == error.NotDir) .fresh else error.ReadFailed;
        };
        defer root.close(self.io);
        var iterator = root.iterate();
        var ours: usize = 0;
        while (iterator.next(self.io) catch return error.ReadFailed) |entry| {
            if (control(entry.name)) continue;
            if (entry.kind != .directory or !(tier(self.kind, entry.name) or std.mem.eql(u8, entry.name, "work"))) return .foreign;
            ours += 1;
        }
        return if (ours == 0) .fresh else .unmarked;
    }

    /// Write the format marker of a namespace that has none: a fresh one, or one that lost its marker but holds only this
    /// cache's own directories. The creation lock is held and the condition read again under it; nothing but the marker
    /// is written. A present marker is never replaced and a directory with foreign entries is refused (`error.ReadFailed`),
    /// before anything is created in it. Returns the condition found.
    pub fn adopt(self: Context) Error!Condition {
        switch (try self.condition()) {
            .bad_marker, .foreign => return error.ReadFailed,
            .fresh, .unmarked, .initialized => {},
        }
        std.Io.Dir.cwd().createDirPath(self.io, self.root) catch return error.WriteFailed;
        const lock_path = try self.joinPath(".lock");
        defer self.scratch.free(lock_path);
        const guard = try storage.lock(self.scratch, self.io, lock_path);
        defer guard.close(self.io);
        const found = try self.condition();
        switch (found) {
            .initialized => {},
            .fresh, .unmarked => try self.writeControl("format", self.kind.format()),
            .bad_marker, .foreign => return error.ReadFailed,
        }
        return found;
    }

    fn joinPath(self: Context, leaf: []const u8) Error![]u8 {
        return std.fs.path.join(self.scratch, &.{ self.root, leaf });
    }
    fn validate(self: Context) Error!void {
        const name = try self.joinPath("format");
        defer self.scratch.free(name);
        const bytes = try storage.bounded(self.scratch, self.io, name, 128) orelse return error.ReadFailed;
        defer self.scratch.free(bytes);
        if (!std.mem.eql(u8, bytes, self.kind.format())) return error.ReadFailed;
    }
    fn lockFile(self: Context, create: bool) Error!std.Io.File {
        const path = try self.joinPath(lease_leaf);
        defer self.scratch.free(path);
        const name = try self.scratch.dupeSentinel(u8, path, 0);
        defer self.scratch.free(name);
        const linux = std.os.linux;
        const fd = linux.open(name, .{ .ACCMODE = .RDWR, .CREAT = create, .CLOEXEC = true, .NOFOLLOW = true, .NONBLOCK = true }, 0o600);
        if (linux.errno(fd) != .SUCCESS) return if (create) error.WriteFailed else error.ReadFailed;
        const file: std.Io.File = .{ .handle = @intCast(fd), .flags = .{ .nonblocking = true } };
        errdefer file.close(self.io);
        if ((file.stat(self.io) catch return error.WriteFailed).kind != .file) return error.WriteFailed;
        return file;
    }
    fn exclusive(self: Context, create: bool) Error!?std.Io.File {
        const file = try self.lockFile(create);
        errdefer file.close(self.io);
        if (!(file.tryLock(self.io, .exclusive) catch return error.WriteFailed)) {
            file.close(self.io);
            return null;
        }
        return file;
    }
    fn writeControl(self: Context, leaf: []const u8, bytes: []const u8) Error!void {
        const target = try self.joinPath(leaf);
        defer self.scratch.free(target);
        const staging = try std.fmt.allocPrint(self.scratch, "{s}.partial", .{target});
        defer self.scratch.free(staging);
        storage.remove(self.io, staging);
        defer storage.remove(self.io, staging);
        const file = std.Io.Dir.cwd().createFile(self.io, staging, .{ .exclusive = true }) catch return error.WriteFailed;
        defer file.close(self.io);
        file.writeStreamingAll(self.io, bytes) catch return error.WriteFailed;
        std.Io.Dir.cwd().rename(staging, std.Io.Dir.cwd(), target, self.io) catch return error.WriteFailed;
    }
    fn due(self: Context, value: Policy, now: i96) Error!bool {
        const path = try self.joinPath(last_leaf);
        defer self.scratch.free(path);
        const bytes = try storage.bounded(self.scratch, self.io, path, 64) orelse return true;
        defer self.scratch.free(bytes);
        const last = std.fmt.parseInt(i96, bytes, 10) catch return error.ReadFailed;
        return last > now or now -| last >= @as(i96, value.interval_seconds) * std.time.ns_per_s;
    }
    fn sweep(self: Context, override: ?Policy, dry_run: bool, automatic_run: bool) Error!Report {
        try self.validate();
        if (automatic_run) {
            // Most opens find the store not due: read that without taking any lock.
            const value = override orelse try self.policy();
            try value.validate();
            if (!(try self.due(value, @import("infra/clock.zig").retentionNow(self.io)))) return .{};
        }
        if (try self.exclusive(!dry_run)) |guard| {
            defer guard.close(self.io);
            return self.sweepHeld(override, dry_run, automatic_run, false);
        }
        if (dry_run) return .{ .skipped_active = true, .dry_run = true };
        // Builders hold a shared lease for as long as they build (a program's work claim lasts the whole build), so with a few
        // of them at work no moment has none, and a sweep that waited for the exclusive lease never ran. Beside them the sweep
        // removes what needs no exclusive lease; one sweep at a time, and not beside a forced collection.
        const only = try self.sweeper() orelse return .{ .skipped_active = true };
        defer only.close(self.io);
        const lease_guard = try self.tryLease() orelse return .{ .skipped_active = true };
        defer lease_guard.close(self.io);
        return self.sweepHeld(override, dry_run, automatic_run, true);
    }
    /// The mutex of the sweep that runs beside shared leases; null while another process is that sweep.
    fn sweeper(self: Context) Error!?std.Io.File {
        const path = try self.joinPath(sweeper_leaf);
        defer self.scratch.free(path);
        const file = (storage.openLock(self.scratch, self.io, path, true) catch return error.WriteFailed) orelse return error.WriteFailed;
        errdefer file.close(self.io);
        if (!(file.tryLock(self.io, .exclusive) catch return error.WriteFailed)) {
            file.close(self.io);
            return null;
        }
        return file;
    }
    /// The sweep itself, with the lease it needs held: the exclusive one, or (`leased`) a shared one and the sweeper mutex.
    fn sweepHeld(self: Context, override: ?Policy, dry_run: bool, automatic_run: bool, leased: bool) Error!Report {
        try self.validate();
        const value = override orelse try self.policy();
        try value.validate();
        const now = @import("infra/clock.zig").retentionNow(self.io);
        if (automatic_run and !(try self.due(value, now))) return .{};
        var inventory: Inventory = .{};
        defer {
            for (inventory.entries.items) |entry| self.scratch.free(entry.path);
            inventory.entries.deinit(self.scratch);
        }
        try self.scan(&inventory);
        // An automatic sweep that fails while evicting still records its attempt, so a namespace
        // whose files cannot be removed is walked once per interval and not at every open.
        errdefer if (automatic_run) self.recordSweep(now);
        var report: Report = .{ .dry_run = dry_run, .walk = inventory.walk, .unmet_budget = inventory.foreign or !inventory.walk.complete };
        report.walk.leased = leased;
        for (inventory.entries.items) |entry| add(&report.inventory, entry.size);
        report.retained = report.inventory;
        // The policy keeps the newest records that fit its budget, so records that fit among all of
        // a namespace's also fit among any part of them: applied to the records an incomplete
        // inventory visited, it evicts nothing that a complete inventory would keep. A namespace
        // past the visit bound is therefore trimmed a window at a time. Each sweep shrinks it by
        // the visited records beyond the policy (or, for an automatic sweep, by one batch of them),
        // and the sweeps end with a complete inventory and the records a single sweep of the whole
        // namespace would have kept.
        std.mem.sort(Entry, inventory.entries.items, {}, older);
        const batch = if (automatic_run) self.batch_limit else std.math.maxInt(usize);
        var evicted: usize = 0;
        for (inventory.entries.items) |entry| {
            if (leased and !entry.leasable) continue;
            const aged = value.max_age_seconds != 0 and now -| entry.mtime >= @as(i96, value.max_age_seconds) * std.time.ns_per_s;
            const under_budget = report.retained.bytes <= value.max_bytes and report.retained.entries <= value.max_entries;
            const obsolete = entry.transient or aged;
            if (!obsolete and under_budget) continue;
            if (!entry.transient and evicted >= batch) {
                report.unmet_budget = true;
                break;
            }
            if (!dry_run) {
                if (leased) {
                    if (!self.removeBesideBuilders(entry, now)) continue;
                } else {
                    std.Io.Dir.cwd().deleteFile(self.io, entry.path) catch return error.WriteFailed;
                    if (!entry.transient) self.removeSidecar(entry.path);
                }
            }
            if (!entry.transient) evicted += 1;
            add(&report.removed, entry.size);
            report.retained.entries -= 1;
            report.retained.bytes -= entry.size;
        }
        report.unmet_budget = report.unmet_budget or report.retained.bytes > value.max_bytes or report.retained.entries > value.max_entries;
        if (!dry_run) {
            const timestamp = try std.fmt.allocPrint(self.scratch, "{d}", .{now});
            defer self.scratch.free(timestamp);
            try self.writeControl(last_leaf, timestamp);
        }
        return report;
    }
    /// Remove one entry while builders hold shared leases. A lock file goes only if the sweep can take the lock itself, so nobody
    /// is publishing under it; a record goes under its own key lock, and only if nobody touched it since the inventory (a hit
    /// refreshes its time); a staging file goes only once it has been idle longer than any publication takes. False when the
    /// entry was busy or changed: it stays for a later sweep.
    fn removeBesideBuilders(self: Context, entry: Entry, now: i96) bool {
        const cwd = std.Io.Dir.cwd();
        if (std.mem.endsWith(u8, entry.path, partial_suffix)) {
            const info = cwd.statFile(self.io, entry.path, .{ .follow_symlinks = false }) catch return false;
            if (now -| info.mtime.nanoseconds < @as(i96, abandoned_seconds) * std.time.ns_per_s) return false;
            cwd.deleteFile(self.io, entry.path) catch return false;
            return true;
        }
        const is_lock = std.mem.endsWith(u8, entry.path, ".lock");
        const lock_path = if (is_lock) entry.path else (if (self.kind == .compiler) std.fmt.allocPrint(self.scratch, "{s}.lock", .{entry.path}) catch return false else null);
        defer if (!is_lock) if (lock_path) |owned| self.scratch.free(owned);
        var held: ?std.Io.File = null;
        defer if (held) |file| file.close(self.io);
        if (lock_path) |path| {
            held = storage.openLock(self.scratch, self.io, path, !is_lock) catch return false;
            if (held == null) return is_lock; // an absent lock is as good as removed
            if (!(held.?.tryLock(self.io, .exclusive) catch return false)) return false;
        }
        if (!is_lock) {
            const info = cwd.statFile(self.io, entry.path, .{ .follow_symlinks = false }) catch return true;
            if (info.mtime.nanoseconds != entry.mtime) return false;
        }
        cwd.deleteFile(self.io, entry.path) catch return false;
        if (!is_lock) if (lock_path) |path| cwd.deleteFile(self.io, path) catch return true;
        return true;
    }
    /// Record `now` as the last sweep's time; best effort, because the next sweep
    /// merely finds itself due again when the record cannot be written.
    fn recordSweep(self: Context, now: i96) void {
        var buffer: [32]u8 = undefined;
        const timestamp = std.fmt.bufPrint(&buffer, "{d}", .{now}) catch return;
        self.writeControl(last_leaf, timestamp) catch return;
    }
    fn scan(self: Context, result: *Inventory) Error!void {
        var root = std.Io.Dir.cwd().openDir(self.io, self.root, .{ .iterate = true, .follow_symlinks = false }) catch return error.ReadFailed;
        defer root.close(self.io);
        var iterator = root.iterate();
        while (iterator.next(self.io) catch return error.ReadFailed) |entry| {
            const inspect = result.visit(self.visit_limit);
            if (control(entry.name)) {
                if (inspect and std.mem.endsWith(u8, entry.name, partial_suffix)) {
                    if (entry.kind != .file) {
                        result.foreign = true;
                        continue;
                    }
                    const info = root.statFile(self.io, entry.name, .{ .follow_symlinks = false }) catch return error.ReadFailed;
                    if (info.kind != .file) {
                        result.foreign = true;
                        continue;
                    }
                    const partial = try self.joinPath(entry.name);
                    errdefer self.scratch.free(partial);
                    try result.entries.append(self.scratch, .{ .path = partial, .size = info.size, .mtime = info.mtime.nanoseconds, .transient = true });
                }
                continue;
            }
            const known_directory = tier(self.kind, entry.name) or std.mem.eql(u8, entry.name, "work");
            if (!known_directory or entry.kind != .directory) {
                result.foreign = true;
                continue;
            }
            const path = try self.joinPath(entry.name);
            defer self.scratch.free(path);
            try self.scanTier(path, result);
        }
    }
    /// Whether the receipt that sidecar `name` sits beside is there. Only a receipt that is
    /// certainly absent frees its sidecar: any other answer keeps it.
    fn receiptPresent(self: Context, dir: std.Io.Dir, name: []const u8) bool {
        _ = dir.statFile(self.io, name[0 .. name.len - sidecarSuffix(self.kind).len], .{ .follow_symlinks = false }) catch |err| return err != error.FileNotFound;
        return true;
    }
    /// Remove the sidecar of the record at `record`, if it has one. Best effort: a sidecar
    /// left behind is an orphan, which the next sweep reclaims.
    fn removeSidecar(self: Context, record: []const u8) void {
        const path = std.fmt.allocPrint(self.scratch, "{s}{s}", .{ record, sidecarSuffix(self.kind) }) catch return;
        defer self.scratch.free(path);
        std.Io.Dir.cwd().deleteFile(self.io, path) catch return;
    }
    /// Whether the entries of the tier directory `name` can be removed beside shared leases. The compiler's artifacts and the engine's
    /// records and objects are immutable and checked by their readers; its linked programs are hard-linked into place and their
    /// sidecars are written after them, and a test receipt has a sidecar read after it, so those wait for an exclusive lease.
    fn leasableTier(self: Context, name: []const u8) bool {
        if (self.kind == .tests) return std.mem.eql(u8, name, engine_tier);
        for ([_][]const u8{ "syntax", "typed", "engine_record", "engine_object", "frontend", "work" }) |leasable| {
            if (std.mem.eql(u8, name, leasable)) return true;
        }
        return false;
    }
    fn knownTierEntry(self: Context, path: []const u8, name: []const u8) bool {
        if (std.mem.eql(u8, std.fs.path.basename(path), "work")) return workLock(name);
        if (self.kind == .tests and std.mem.eql(u8, std.fs.path.basename(path), engine_tier)) return engineRecord(name);
        return known(self.kind, name);
    }
    fn scanTier(self: Context, path: []const u8, result: *Inventory) Error!void {
        var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true, .follow_symlinks = false }) catch return error.ReadFailed;
        defer dir.close(self.io);
        var iterator = dir.iterate();
        while (iterator.next(self.io) catch return error.ReadFailed) |entry| {
            if (!result.visit(self.visit_limit)) continue;
            // A work sidecar belongs to the receipt beside it and goes with it. One whose
            // receipt is gone belongs to nobody, and is reclaimed like any abandoned staging file.
            const sidecar = entry.kind == .file and (if (self.kind == .tests) workSidecar(entry.name) else self.kind == .compiler and blobSidecar(entry.name));
            if (sidecar and self.receiptPresent(dir, entry.name)) continue;
            if (!(sidecar or self.knownTierEntry(path, entry.name)) or entry.kind != .file) {
                result.foreign = true;
                continue;
            }
            const full = try std.fs.path.join(self.scratch, &.{ path, entry.name });
            errdefer self.scratch.free(full);
            const info = dir.statFile(self.io, entry.name, .{ .follow_symlinks = false }) catch return error.ReadFailed;
            if (info.kind != .file) {
                self.scratch.free(full);
                result.foreign = true;
                continue;
            }
            const transient = sidecar or std.mem.endsWith(u8, entry.name, partial_suffix) or std.mem.endsWith(u8, entry.name, ".lock");
            const leasable = !sidecar and self.leasableTier(std.fs.path.basename(path));
            try result.entries.append(self.scratch, .{ .path = full, .size = if (std.mem.endsWith(u8, entry.name, ".lock")) 0 else info.size, .mtime = info.mtime.nanoseconds, .transient = transient, .leasable = leasable });
        }
    }
};
/// What a command says when the per-user default store of `kind` under `shared_root` exists but cannot be opened (`err` is
/// why): one line, ending in the command that repairs it. Null when nothing is there to repair, the store only could not be
/// created (a read-only or absent home), which a command skips quietly. The text is owned by `a`.
pub fn unusableWarning(a: std.mem.Allocator, io: std.Io, shared_root: []const u8, kind: Kind, err: anyerror) Error!?[]u8 {
    const namespace = try std.fs.path.join(a, &.{ shared_root, kind.namespace() });
    defer a.free(namespace);
    const found = (Context.init(a, io, namespace, kind)).condition() catch .initialized;
    const label = if (kind == .compiler) "compiler" else "test";
    return switch (found) {
        .fresh => null,
        .unmarked => try std.fmt.allocPrint(
            a,
            "warning: shared {s} cache disabled: {s} has no format marker but holds this cache's directories; `selka cache init --shared-cache-dir {s} --kind {s}` writes the marker and nothing else\n",
            .{ label, namespace, shared_root, @tagName(kind) },
        ),
        .bad_marker => try std.fmt.allocPrint(
            a,
            "warning: shared {s} cache disabled: {s}/format is not this cache's marker; move the directory aside (`mv {s} {s}.old`), or delete the file if you know it is damaged\n",
            .{ label, namespace, namespace, namespace },
        ),
        .foreign => try std.fmt.allocPrint(
            a,
            "warning: shared {s} cache disabled: {s} holds files that are not this cache's; move it aside (`mv {s} {s}.old`)\n",
            .{ label, namespace, namespace, namespace },
        ),
        .initialized => try std.fmt.allocPrint(a, "warning: shared {s} cache disabled: {s}: {s}\n", .{ label, namespace, @errorName(err) }),
    };
}

/// Print `unusableWarning` to standard error, once per call. Best effort: a command never fails because its warning could not
/// be written.
pub fn warnUnusable(a: std.mem.Allocator, io: std.Io, shared_root: []const u8, kind: Kind, err: anyerror) void {
    const text = (unusableWarning(a, io, shared_root, kind, err) catch return) orelse return;
    defer a.free(text);
    std.Io.File.stderr().writeStreamingAll(io, text) catch return;
}

fn add(count: *Counts, size: u64) void {
    count.entries += 1;
    count.bytes +|= size;
}
fn older(_: void, left: Entry, right: Entry) bool {
    if (left.transient != right.transient) return left.transient;
    if (left.mtime != right.mtime) return left.mtime < right.mtime;
    return std.mem.lessThan(u8, left.path, right.path);
}
fn tier(kind: Kind, name: []const u8) bool {
    if (kind == .tests) return std.mem.eql(u8, name, "receipts") or std.mem.eql(u8, name, engine_tier);
    // The compiler namespace's tiers: the artifacts of the front end and the linker, and the engine's records and their objects.
    for ([_][]const u8{ "syntax", "typed", "program", "engine_record", "engine_object", "frontend" }) |known_tier| {
        if (std.mem.eql(u8, name, known_tier)) return true;
    }
    return false;
}
/// The tests namespace's tier of incremental-engine records (`core/engine/shared_records.zig`): `<64 hex>.rec`, one file
/// per record, swept and evicted with the receipts by the same policy.
const engine_tier = "engine";
/// `<64 hex>.rec` or the staging file of one.
fn engineRecord(name: []const u8) bool {
    const suffix = ".rec";
    if (name.len == 64 + suffix.len) return std.mem.endsWith(u8, name, suffix) and hexKey(name[0..64]);
    return name.len == 64 + suffix.len + partial_suffix.len and std.mem.endsWith(u8, name, suffix ++ partial_suffix) and hexKey(name[0..64]);
}
fn control(name: []const u8) bool {
    for ([_][]const u8{ "format", ".lock", lease_leaf, sweeper_leaf, policy_leaf, last_leaf, mismatch_leaf, "format.partial", "retention-policy.partial", "retention-last.partial" }) |item| {
        if (std.mem.eql(u8, name, item)) return true;
    }
    return false;
}
fn hexKey(name: []const u8) bool {
    if (name.len != 64) return false;
    for (name) |byte| {
        const decimal = byte >= '0' and byte <= '9';
        const letter = byte >= 'a' and byte <= 'f';
        if (!decimal and !letter) return false;
    }
    return true;
}
/// The suffix of the sidecar a record of `kind` keeps beside it: a test receipt's work counts, or a
/// program record's size and digest (`shared_artifact_store.zig`).
fn sidecarSuffix(kind: Kind) []const u8 {
    return if (kind == .tests) sidecar_suffix else ".sum";
}
/// `<64 hex>.blob.sum`: the sidecar of a compiler program record.
fn blobSidecar(name: []const u8) bool {
    return name.len == 64 + ".blob.sum".len and std.mem.endsWith(u8, name, ".blob.sum") and hexKey(name[0..64]);
}
/// `<64 hex>.pass.work`: the work sidecar of a test receipt.
fn workSidecar(name: []const u8) bool {
    return name.len == 64 + ".pass".len + sidecar_suffix.len and std.mem.endsWith(u8, name, ".pass" ++ sidecar_suffix) and hexKey(name[0..64]);
}
fn known(kind: Kind, name: []const u8) bool {
    const suffix = if (kind == .compiler) ".blob" else ".pass";
    if (name.len == 64 + suffix.len and std.mem.endsWith(u8, name, suffix)) return hexKey(name[0..64]);
    if (std.mem.endsWith(u8, name, ".lock")) return kind == .compiler and name.len == 64 + suffix.len + 5 and hexKey(name[0..64]) and std.mem.eql(u8, name[64 .. name.len - 5], suffix);
    if (!std.mem.endsWith(u8, name, partial_suffix)) return false;
    if (kind == .tests) {
        // The staging file of a receipt, or of its sidecar.
        const stem = name[0 .. name.len - partial_suffix.len];
        const staged = stem.len == 64 + ".pass".len or stem.len == 64 + ".pass".len + sidecar_suffix.len;
        return staged and hexKey(stem[0..64]) and (std.mem.eql(u8, stem[64..], ".pass") or std.mem.eql(u8, stem[64..], ".pass" ++ sidecar_suffix));
    }
    if (name.len < 10 or name[0] != '.') return false;
    var parts = std.mem.splitScalar(u8, name[1 .. name.len - 8], '-');
    const pid = parts.next() orelse return false;
    const pointer = parts.next() orelse return false;
    const serial = parts.next() orelse return false;
    if (parts.next() != null) return false;
    _ = std.fmt.parseInt(u64, pid, 10) catch return false;
    _ = std.fmt.parseInt(usize, pointer, 16) catch return false;
    _ = std.fmt.parseInt(u64, serial, 10) catch return false;
    return true;
}

const Fixture = struct {
    temporary: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    context: Context,
    fn init(backing: std.mem.Allocator) !Fixture {
        return initKind(backing, .compiler);
    }
    fn initKind(backing: std.mem.Allocator, kind: Kind) !Fixture {
        var arena = std.heap.ArenaAllocator.init(backing);
        errdefer arena.deinit();
        var temporary = std.testing.tmpDir(.{});
        errdefer temporary.cleanup();
        const a = arena.allocator();
        const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
        const context = Context.init(backing, std.testing.io, root, kind);
        try temporary.dir.createDir(std.testing.io, if (kind == .compiler) "syntax" else "receipts", .default_dir);
        try put(temporary.dir, "format", kind.format());
        try put(temporary.dir, lease_leaf, "");
        return .{ .temporary = temporary, .arena = arena, .context = context };
    }
    /// A test receipt named by `byte`, modified at `timestamp`, with its work sidecar when `work` is set.
    fn receipt(self: *Fixture, byte: u8, timestamp: i96, work: bool) ![]const u8 {
        const name = try std.fmt.allocPrint(self.arena.allocator(), "receipts/{s}.pass", .{@as([64]u8, @splat(byte))});
        try put(self.temporary.dir, name, "success\n");
        try self.temporary.dir.setTimestamps(std.testing.io, name, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = timestamp } } });
        if (work) try put(self.temporary.dir, try self.sidecarOf(name), "steps 1\npeak_bytes 2\n");
        return name;
    }
    fn sidecarOf(self: *Fixture, record: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.arena.allocator(), "{s}{s}", .{ record, sidecar_suffix });
    }
    fn deinit(self: *Fixture) void {
        self.temporary.cleanup();
        self.arena.deinit();
    }
    fn entry(self: *Fixture, byte: u8, size: usize, timestamp: i96) ![]const u8 {
        const name = try std.fmt.allocPrint(self.arena.allocator(), "syntax/{s}.blob", .{@as([64]u8, @splat(byte))});
        const bytes = try self.arena.allocator().alloc(u8, size);
        @memset(bytes, byte);
        try put(self.temporary.dir, name, bytes);
        try self.temporary.dir.setTimestamps(std.testing.io, name, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = timestamp } } });
        return name;
    }
};
fn put(dir: std.Io.Dir, name: []const u8, bytes: []const u8) !void {
    const file = try dir.createFile(std.testing.io, name, .{});
    defer file.close(std.testing.io);
    try file.writeStreamingAll(std.testing.io, bytes);
}
fn exists(dir: std.Io.Dir, path: []const u8) bool {
    _ = dir.statFile(std.testing.io, path, .{ .follow_symlinks = false }) catch return false;
    return true;
}
// spec: NATIVE-CACHE-RETENTION-1
test "native retention deterministic LRU quota dry run, and a sweep beside a held lease removes what needs no exclusive lease" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const old = try fixture.entry('a', 5, 1);
    const new = try fixture.entry('b', 5, 2);
    const quota: Policy = .{ .max_bytes = 5, .max_entries = 1 };
    const preview = try fixture.context.collect(quota, true);
    try std.testing.expectEqual(@as(usize, 1), preview.removed.entries);
    try std.testing.expect(exists(fixture.temporary.dir, old));
    const lease = try fixture.context.lease();
    // A preview and a policy change still need the store to themselves.
    try std.testing.expect((try fixture.context.collect(quota, true)).skipped_active);
    try std.testing.expect(!(try fixture.context.configure(quota)));
    // A builder's lease does not keep the sweep from the immutable records: it evicts the oldest and reports how it ran.
    const beside = try fixture.context.collect(quota, false);
    try std.testing.expect(beside.walk.leased and !beside.skipped_active);
    try std.testing.expectEqual(@as(usize, 1), beside.removed.entries);
    try std.testing.expect(!exists(fixture.temporary.dir, old));
    try std.testing.expect(exists(fixture.temporary.dir, new));
    lease.close(std.testing.io);
    const swept = try fixture.context.collect(quota, false);
    try std.testing.expect(!swept.walk.leased);
    try std.testing.expectEqual(@as(u64, 5), swept.retained.bytes);
    try std.testing.expect(exists(fixture.temporary.dir, new));
}
// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention sweeps the engine record tier of the tests namespace with its receipts" {
    var fixture = try Fixture.initKind(std.testing.allocator, .tests);
    defer fixture.deinit();
    try fixture.temporary.dir.createDir(std.testing.io, "engine", .default_dir);
    const old = try std.fmt.allocPrint(fixture.arena.allocator(), "engine/{s}.rec", .{@as([64]u8, @splat('a'))});
    const new = try std.fmt.allocPrint(fixture.arena.allocator(), "engine/{s}.rec", .{@as([64]u8, @splat('b'))});
    const staged = try std.fmt.allocPrint(fixture.arena.allocator(), "engine/{s}.rec.partial", .{@as([64]u8, @splat('c'))});
    for ([_]struct { name: []const u8, at: i96 }{ .{ .name = old, .at = 1 }, .{ .name = new, .at = 2 }, .{ .name = staged, .at = 3 } }) |item| {
        try put(fixture.temporary.dir, item.name, "record");
        try fixture.temporary.dir.setTimestamps(std.testing.io, item.name, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = item.at } } });
    }
    try put(fixture.temporary.dir, "engine/foreign", "keep");
    const swept = try fixture.context.collect(.{ .max_bytes = 1 << 20, .max_entries = 1 }, false);
    try std.testing.expect(swept.unmet_budget);
    try std.testing.expect(!exists(fixture.temporary.dir, staged));
    try std.testing.expect(!exists(fixture.temporary.dir, old));
    try std.testing.expect(exists(fixture.temporary.dir, new));
    try std.testing.expect(exists(fixture.temporary.dir, "engine/foreign"));
}
// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention sweeps the engine record and object tiers of the compiler namespace with its other artifacts" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try fixture.temporary.dir.createDir(std.testing.io, "engine_record", .default_dir);
    try fixture.temporary.dir.createDir(std.testing.io, "engine_object", .default_dir);
    const old = try std.fmt.allocPrint(fixture.arena.allocator(), "engine_record/{s}.blob", .{@as([64]u8, @splat('a'))});
    const object = try std.fmt.allocPrint(fixture.arena.allocator(), "engine_object/{s}.blob", .{@as([64]u8, @splat('b'))});
    const lock = try std.fmt.allocPrint(fixture.arena.allocator(), "{s}.lock", .{old});
    for ([_]struct { name: []const u8, at: i96 }{ .{ .name = old, .at = 1 }, .{ .name = object, .at = 2 } }) |item| {
        try put(fixture.temporary.dir, item.name, "entry");
        try fixture.temporary.dir.setTimestamps(std.testing.io, item.name, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = item.at } } });
    }
    try put(fixture.temporary.dir, lock, "");
    const kept = try fixture.entry('c', 5, 3);
    // Nothing the engine's tiers hold makes the namespace foreign, and the oldest entry goes first whichever tier it is in.
    const swept = try fixture.context.collect(.{ .max_bytes = 1 << 20, .max_entries = 2 }, false);
    try std.testing.expect(!swept.unmet_budget);
    try std.testing.expect(!exists(fixture.temporary.dir, old));
    try std.testing.expect(exists(fixture.temporary.dir, object));
    try std.testing.expect(exists(fixture.temporary.dir, kept));
}
// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention crash remnants preserve foreign and symlinks" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const blob = try fixture.entry('a', 5, 1);
    const lock = try std.fmt.allocPrint(fixture.arena.allocator(), "{s}.lock", .{blob});
    try put(fixture.temporary.dir, lock, "");
    try put(fixture.temporary.dir, "syntax/.123-abc-0.partial", "partial");
    try put(fixture.temporary.dir, "retention-policy.partial", "partial");
    try put(fixture.temporary.dir, "syntax/foreign", "keep");
    try put(fixture.temporary.dir, ".lock", "");
    const symlink = try std.fmt.allocPrint(fixture.arena.allocator(), "syntax/{s}.blob", .{@as([64]u8, @splat('b'))});
    try fixture.temporary.dir.symLink(std.testing.io, "foreign", symlink, .{});
    const report = try fixture.context.collect(Policy.defaults(.compiler), false);
    try std.testing.expect(report.unmet_budget);
    try std.testing.expectEqual(@as(usize, 3), report.removed.entries);
    try std.testing.expect(exists(fixture.temporary.dir, "syntax/foreign"));
    try std.testing.expect(exists(fixture.temporary.dir, symlink));
    try std.testing.expect(exists(fixture.temporary.dir, ".lock"));
    try std.testing.expect(exists(fixture.temporary.dir, lease_leaf));
}
// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention persisted policy throttle and invalid configuration" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try std.testing.expect(try fixture.context.configure(.{ .max_bytes = 0, .max_entries = 0 }));
    fixture.context.automatic();
    const blob = try fixture.entry('a', 5, 1);
    fixture.context.automatic();
    try std.testing.expect(exists(fixture.temporary.dir, blob));
    const forced = try fixture.context.collect(null, false);
    try std.testing.expectEqual(@as(usize, 1), forced.removed.entries);
    try put(fixture.temporary.dir, policy_leaf, "invalid");
    try std.testing.expectError(error.ReadFailed, fixture.context.policy());
    try std.testing.expectError(error.ReadFailed, (Policy{ .max_bytes = 0, .max_entries = 0, .max_age_seconds = std.math.maxInt(u64) }).validate());
}
// spec: G4C-2C-2
test "a hit refreshes a file's recency once an hour: a stale file is touched, a file touched a minute ago is left alone" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const clock: i64 = @truncate(std.Io.Timestamp.now(std.testing.io, .real).nanoseconds);
    const stale = try fixture.entry('a', 5, clock - 2 * touch_interval_ns);
    const recent = try fixture.entry('b', 5, clock - 60 * std.time.ns_per_s);
    for ([_][]const u8{ stale, recent }) |name| {
        const file = try fixture.temporary.dir.openFile(std.testing.io, name, .{});
        defer file.close(std.testing.io);
        fixture.context.touch(file);
    }
    const stale_after = try fixture.temporary.dir.statFile(std.testing.io, stale, .{});
    const recent_after = try fixture.temporary.dir.statFile(std.testing.io, recent, .{});
    try std.testing.expect(@as(i64, @truncate(stale_after.mtime.nanoseconds)) > clock - touch_interval_ns);
    try std.testing.expectEqual(clock - 60 * std.time.ns_per_s, @as(i64, @truncate(recent_after.mtime.nanoseconds)));
}
// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention age expiry touches and validates namespace without adopting roots" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const old = try fixture.entry('a', 5, 1);
    const current = try fixture.entry('b', 5, 2);
    const full = try fixture.context.joinPath(current);
    defer fixture.context.scratch.free(full);
    fixture.context.touchPath(full);
    const report = try fixture.context.collect(.{ .max_bytes = 100, .max_entries = 100, .max_age_seconds = 3600 }, false);
    try std.testing.expectEqual(@as(usize, 1), report.removed.entries);
    try std.testing.expect(!exists(fixture.temporary.dir, old));
    try std.testing.expect(exists(fixture.temporary.dir, current));
    try put(fixture.temporary.dir, "format", "selka-compiler-artifact-store-v1\n");
    try std.testing.expectError(error.ReadFailed, fixture.context.collect(null, false));
    try fixture.temporary.dir.deleteFile(std.testing.io, "format");
    try std.testing.expectError(error.ReadFailed, fixture.context.collect(null, false));
    try std.testing.expect(!exists(fixture.temporary.dir, "format"));
}
// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention scan inspects nothing past the visited bound and preview needs permanent lock" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const blob = try fixture.entry('a', 5, 1);
    var inventory: Inventory = .{ .walk = .{ .visited = hard_limit } };
    defer inventory.entries.deinit(std.testing.allocator);
    try fixture.context.scan(&inventory);
    try std.testing.expect(!inventory.walk.complete);
    try std.testing.expectEqual(@as(usize, 0), inventory.entries.items.len);
    // Past the bound every entry is counted, none inspected: the root's own and the tier's.
    try std.testing.expectEqual(@as(usize, 4), inventory.walk.unvisited);
    try std.testing.expect(exists(fixture.temporary.dir, blob));
    try fixture.temporary.dir.deleteFile(std.testing.io, lease_leaf);
    try std.testing.expectError(error.ReadFailed, fixture.context.collect(null, true));
    try std.testing.expect(!exists(fixture.temporary.dir, lease_leaf));
    try fixture.temporary.dir.symLink(std.testing.io, "format", lease_leaf, .{});
    try std.testing.expectError(error.WriteFailed, fixture.context.lease());
    try std.testing.expectError(error.WriteFailed, fixture.context.lockFile(true));
    const missing = try fixture.context.joinPath("missing-tier");
    defer fixture.context.scratch.free(missing);
    try std.testing.expectError(error.ReadFailed, fixture.context.scanTier(missing, &inventory));
    const absent = Context.init(std.testing.allocator, std.testing.io, missing, .compiler);
    try std.testing.expectError(error.ReadFailed, absent.scan(&inventory));
}

fn workLock(name: []const u8) bool {
    return name.len == 69 and std.mem.endsWith(u8, name, ".lock") and hexKey(name[0..64]);
}

// spec-case: NATIVE-WORK-CLAIM-1
test "native retention reclaims idle exact work claim inodes" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try fixture.temporary.dir.createDir(std.testing.io, "work", .default_dir);
    const path = try std.fmt.allocPrint(fixture.arena.allocator(), "work/{s}.lock", .{@as([64]u8, @splat('a'))});
    try put(fixture.temporary.dir, path, "");
    const preview = try fixture.context.collect(Policy.defaults(.compiler), true);
    try std.testing.expectEqual(@as(usize, 1), preview.removed.entries);
    try std.testing.expect(exists(fixture.temporary.dir, path));
    const applied = try fixture.context.collect(Policy.defaults(.compiler), false);
    try std.testing.expectEqual(@as(usize, 1), applied.removed.entries);
    try std.testing.expect(!exists(fixture.temporary.dir, path));
}
// spec-case: SHARED-STORE-5
test "native retention tryLease yields to collection and mismatch appends without following links" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const io = std.testing.io;
    const held = (try fixture.context.exclusive(true)).?;
    try std.testing.expect((try fixture.context.tryLease()) == null);
    held.close(io);
    const lease = (try fixture.context.tryLease()).?;
    try std.testing.expect((try fixture.context.collect(null, true)).skipped_active);
    lease.close(io);
    fixture.context.mismatch(.{ .kind = "syntax", .key = @splat(1), .existing = @splat(2), .attempted = @splat(3) });
    fixture.context.mismatch(.{ .kind = "syntax", .key = @splat(1), .existing = @splat(2), .attempted = @splat(4) });
    const log = try fixture.temporary.dir.readFileAlloc(io, mismatch_leaf, fixture.arena.allocator(), .limited(4096));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, log, "\n"));
    try std.testing.expect(std.mem.startsWith(u8, log, "mismatch syntax 0101"));
    try std.testing.expect(!(try fixture.context.collect(null, true)).unmet_budget);
    try fixture.temporary.dir.deleteFile(io, mismatch_leaf);
    try fixture.temporary.dir.symLink(io, "format", mismatch_leaf, .{});
    fixture.context.mismatch(.{ .kind = "syntax", .key = @splat(1), .existing = @splat(2), .attempted = @splat(3) });
    try std.testing.expectEqualStrings(Kind.compiler.format(), try fixture.temporary.dir.readFileAlloc(io, "format", fixture.arena.allocator(), .limited(128)));
    try fixture.temporary.dir.deleteFile(io, lease_leaf);
    try fixture.temporary.dir.symLink(io, "format", lease_leaf, .{});
    try std.testing.expectError(error.WriteFailed, fixture.context.tryLease());
}

// Counts the attempts of a step that fails until `succeed_at`.
const Attempts = struct {
    made: usize = 0,
    succeed_at: usize,
    failure: Error = error.WriteFailed,

    fn step(self: *Attempts) Error!void {
        self.made += 1;
        if (self.made < self.succeed_at) return self.failure;
    }
};

// spec-case: SHARED-STORE-6
test "namespace creation retries a lost race a bounded number of times and stops at once on exhaustion of memory" {
    var recovers: Attempts = .{ .succeed_at = initialization_attempts };
    try retried(&recovers, Attempts.step);
    try std.testing.expectEqual(@as(usize, initialization_attempts), recovers.made);
    var unusable: Attempts = .{ .succeed_at = initialization_attempts + 1, .failure = error.ReadFailed };
    try std.testing.expectError(error.ReadFailed, retried(&unusable, Attempts.step));
    try std.testing.expectEqual(@as(usize, initialization_attempts), unusable.made);
    var exhausted: Attempts = .{ .succeed_at = initialization_attempts, .failure = error.OutOfMemory };
    try std.testing.expectError(error.OutOfMemory, retried(&exhausted, Attempts.step));
    try std.testing.expectEqual(@as(usize, 1), exhausted.made);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "an automatic sweep keeps its inventory out of the allocator the caller bound" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const doomed = try fixture.entry('a', 5, 1);
    try std.testing.expect(try fixture.context.configure(.{ .max_bytes = 0, .max_entries = 0 }));
    // A scratch that refuses every allocation: the sweep must not ask it for any,
    // or a root's arena would keep one inventory for each store the root opens.
    Context.init(std.testing.failing_allocator, std.testing.io, fixture.context.root, .compiler).automatic();
    try std.testing.expect(!exists(fixture.temporary.dir, doomed));
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "an automatic sweep of a namespace past the visit bound records its attempt and waits for the interval" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const kept = try fixture.entry('a', 5, 1);
    _ = try fixture.entry('b', 5, 2);
    var bounded = fixture.context;
    bounded.visit_limit = 1;
    bounded.automatic();
    // The inventory was incomplete, so nothing was deleted, yet the attempt is on record.
    try std.testing.expect(exists(fixture.temporary.dir, kept));
    const first = try fixture.temporary.dir.readFileAlloc(std.testing.io, last_leaf, fixture.arena.allocator(), .limited(64));
    try std.testing.expect(first.len != 0);
    // Not due again within the interval, so the second run walks nothing and leaves the record alone.
    bounded.automatic();
    const second = try fixture.temporary.dir.readFileAlloc(std.testing.io, last_leaf, fixture.arena.allocator(), .limited(64));
    try std.testing.expectEqualStrings(first, second);
    // A preview reports the incomplete inventory, and what is left past it, and deletes nothing.
    const preview = try bounded.collect(.{ .max_bytes = 0, .max_entries = 0 }, true);
    try std.testing.expect(!preview.walk.complete);
    try std.testing.expectEqual(@as(usize, 1), preview.walk.visited);
    try std.testing.expect(preview.walk.unvisited > 0);
    try std.testing.expect(exists(fixture.temporary.dir, kept));
}

/// Put `count` distinct blobs in the fixture's `syntax` tier. Blob `index` is modified at time
/// `index + 1`, so a higher index is more recent.
fn populate(fixture: *Fixture, count: usize) !void {
    var name: [96]u8 = undefined;
    for (0..count) |index| {
        const path = try std.fmt.bufPrint(&name, "syntax/{x:0>64}.blob", .{index});
        try put(fixture.temporary.dir, path, "bytes");
        try fixture.temporary.dir.setTimestamps(std.testing.io, path, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = @intCast(index + 1) } } });
    }
}
/// How many of the first `count` blobs `populate` made are still there.
fn remaining(fixture: *Fixture, count: usize) !usize {
    var name: [96]u8 = undefined;
    var found: usize = 0;
    for (0..count) |index| {
        const path = try std.fmt.bufPrint(&name, "syntax/{x:0>64}.blob", .{index});
        found += @intFromBool(exists(fixture.temporary.dir, path));
    }
    return found;
}
/// Whether the blobs still there out of the first `count` are exactly the `kept` most recent.
fn onlyNewestRemain(fixture: *Fixture, count: usize, kept: usize) !bool {
    var name: [96]u8 = undefined;
    for (0..count) |index| {
        const path = try std.fmt.bufPrint(&name, "syntax/{x:0>64}.blob", .{index});
        if (exists(fixture.temporary.dir, path) != (index >= count - kept)) return false;
    }
    return true;
}
/// Sweep with `context` under `policy` until the first `count` blobs fit it, requiring each sweep
/// that finds them over it to remove some; return how many sweeps that took.
fn sweepsToFit(fixture: *Fixture, context: Context, policy: Policy, count: usize) !usize {
    var sweeps: usize = 0;
    var before = count;
    while (before > policy.max_entries) {
        _ = try context.collect(policy, false);
        const after = try remaining(fixture, count);
        try std.testing.expect(after < before);
        before = after;
        sweeps += 1;
        try std.testing.expect(sweeps <= count);
    }
    return sweeps;
}
const trim: Policy = .{ .max_bytes = 1 << 20, .max_entries = 20 };

// spec-case: NATIVE-CACHE-RETENTION-1
test "sweeps of a namespace past the visit bound shrink it every time to its policy and keep the newest records" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try populate(&fixture, 300);
    var bounded = fixture.context;
    bounded.visit_limit = 100;
    // The first sweep cannot see the whole namespace, and says so.
    const first = try bounded.collect(trim, true);
    try std.testing.expect(!first.walk.complete);
    try std.testing.expectEqual(@as(usize, 100), first.walk.visited);
    try std.testing.expectEqual(@as(usize, 303), first.walk.visited + first.walk.unvisited);
    try std.testing.expect(first.unmet_budget);
    const sweeps = try sweepsToFit(&fixture, bounded, trim, 300);
    try std.testing.expect(sweeps > 1);
    try std.testing.expectEqual(@as(usize, 20), try remaining(&fixture, 300));
    // The window never evicted a record that a sweep of the whole namespace would have kept.
    try std.testing.expect(try onlyNewestRemain(&fixture, 300, 20));
    const settled = try bounded.collect(trim, false);
    try std.testing.expect(settled.walk.complete);
    try std.testing.expectEqual(@as(usize, 0), settled.removed.entries);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "a preview past the visit bound proposes exactly the eviction the sweep makes and deletes nothing" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try populate(&fixture, 300);
    var bounded = fixture.context;
    bounded.visit_limit = 100;
    const preview = try bounded.collect(trim, true);
    try std.testing.expect(preview.dry_run);
    try std.testing.expect(preview.removed.entries > 0);
    try std.testing.expect(preview.retained.entries + preview.removed.entries == preview.inventory.entries);
    try std.testing.expectEqual(@as(usize, 300), try remaining(&fixture, 300));
    try std.testing.expect(!exists(fixture.temporary.dir, last_leaf));
    const applied = try bounded.collect(trim, false);
    try std.testing.expectEqual(preview.removed, applied.removed);
    try std.testing.expectEqual(300 - applied.removed.entries, try remaining(&fixture, 300));
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "a sweep past the visit bound runs beside a process lease and still shrinks the namespace to its policy" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try populate(&fixture, 300);
    var bounded = fixture.context;
    bounded.visit_limit = 100;
    const lease = try bounded.lease();
    const beside = try bounded.collect(trim, false);
    try std.testing.expect(beside.walk.leased and !beside.skipped_active);
    try std.testing.expect((try remaining(&fixture, 300)) < 300);
    lease.close(std.testing.io);
    const released = try bounded.collect(trim, false);
    try std.testing.expect(!released.skipped_active and !released.walk.leased);
    try std.testing.expect((try remaining(&fixture, 300)) < 300);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "sweeps past the visit bound never delete a foreign entry or a symlink" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try populate(&fixture, 300);
    // Older than every record, so an inventory that took it for one would evict it first.
    try put(fixture.temporary.dir, "syntax/foreign", "keep");
    try fixture.temporary.dir.setTimestamps(std.testing.io, "syntax/foreign", .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 0 } } });
    try put(fixture.temporary.dir, "notes.txt", "keep");
    const link = try std.fmt.allocPrint(fixture.arena.allocator(), "syntax/{x:0>64}.blob", .{@as(usize, 1000)});
    try fixture.temporary.dir.symLink(std.testing.io, "foreign", link, .{});
    var bounded = fixture.context;
    bounded.visit_limit = 100;
    _ = try sweepsToFit(&fixture, bounded, trim, 300);
    try std.testing.expect(exists(fixture.temporary.dir, "syntax/foreign"));
    try std.testing.expect(exists(fixture.temporary.dir, "notes.txt"));
    try std.testing.expect(exists(fixture.temporary.dir, link));
    // Foreign entries keep the budget reported as unmet, as they do for a complete inventory.
    try std.testing.expect((try bounded.collect(trim, true)).unmet_budget);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "an automatic sweep removes at most one batch and still shrinks a namespace past the visit bound every time" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try populate(&fixture, 300);
    try std.testing.expect(try fixture.context.configure(.{ .max_bytes = 1 << 20, .max_entries = 20, .interval_seconds = 0 }));
    var bounded = fixture.context;
    bounded.visit_limit = 100;
    bounded.batch_limit = 30;
    bounded.automatic();
    try std.testing.expectEqual(@as(usize, 270), try remaining(&fixture, 300));
    bounded.automatic();
    try std.testing.expectEqual(@as(usize, 240), try remaining(&fixture, 300));
    // A forced collection is not held to the batch: it drains the window it visited.
    const forced = try bounded.collect(null, false);
    try std.testing.expect(forced.removed.entries > 30);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "the memory of a sweep is set by the visit bound, not by the size of the namespace" {
    var small = try Fixture.init(std.testing.allocator);
    defer small.deinit();
    var large = try Fixture.init(std.testing.allocator);
    defer large.deinit();
    try populate(&small, 120);
    try populate(&large, 1200);
    var small_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer small_arena.deinit();
    var large_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer large_arena.deinit();
    // Count the bytes each sweep asks for, not the arena's capacity: capacity grows in steps
    // whose size depends on where earlier requests happened to fall, which no sweep controls.
    var small_count = std.testing.FailingAllocator.init(small_arena.allocator(), .{});
    var large_count = std.testing.FailingAllocator.init(large_arena.allocator(), .{});
    var narrow = small.context;
    narrow.scratch = small_count.allocator();
    narrow.visit_limit = 64;
    var wide = large.context;
    wide.scratch = large_count.allocator();
    wide.visit_limit = 64;
    const one = try narrow.collect(trim, true);
    const ten = try wide.collect(trim, true);
    // Both stopped inspecting at the bound, so the larger namespace needed no more memory.
    try std.testing.expect(!one.walk.complete and !ten.walk.complete);
    try std.testing.expectEqual(one.walk.visited, ten.walk.visited);
    try std.testing.expect(ten.walk.unvisited > one.walk.unvisited);
    try std.testing.expect(large_count.allocated_bytes <= small_count.allocated_bytes + 2048);
    // Far less than a path for each of its 1200 records, which a whole inventory would hold.
    try std.testing.expect(large_count.allocated_bytes < 64 * 1024);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "a test receipt's work sidecar is evicted with its receipt and is not a record of its own" {
    var fixture = try Fixture.initKind(std.testing.allocator, .tests);
    defer fixture.deinit();
    const oldest = try fixture.receipt('a', 1, true);
    const middle = try fixture.receipt('b', 2, true);
    const newest = try fixture.receipt('c', 3, false);
    const swept = try fixture.context.collect(.{ .max_bytes = 1 << 20, .max_entries = 2 }, false);
    // Three receipts and two sidecars: only the receipts are records, and the oldest goes with its sidecar.
    try std.testing.expectEqual(@as(usize, 3), swept.inventory.entries);
    try std.testing.expectEqual(@as(usize, 1), swept.removed.entries);
    try std.testing.expect(!exists(fixture.temporary.dir, oldest));
    try std.testing.expect(!exists(fixture.temporary.dir, try fixture.sidecarOf(oldest)));
    try std.testing.expect(exists(fixture.temporary.dir, middle));
    try std.testing.expect(exists(fixture.temporary.dir, try fixture.sidecarOf(middle)));
    try std.testing.expect(exists(fixture.temporary.dir, newest));
    // A sidecar is no longer a foreign entry that leaves the budget unmet.
    try std.testing.expect(!swept.unmet_budget);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "an orphaned work sidecar and an interrupted sidecar write are reclaimed, and look-alikes are not" {
    var fixture = try Fixture.initKind(std.testing.allocator, .tests);
    defer fixture.deinit();
    const kept = try fixture.receipt('a', 1, true);
    const orphan = try fixture.arena.allocator().dupe(u8, "receipts/dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd.pass.work");
    const crashed = try fixture.arena.allocator().dupe(u8, "receipts/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee.pass.work.partial");
    const other = try fixture.arena.allocator().dupe(u8, "receipts/ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff.fail.work");
    const upper = try fixture.arena.allocator().dupe(u8, "receipts/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.pass.work");
    const linked = try fixture.arena.allocator().dupe(u8, "receipts/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.pass.work");
    for ([_][]const u8{ orphan, crashed, other, upper }) |name| try put(fixture.temporary.dir, name, "x");
    try fixture.temporary.dir.symLink(std.testing.io, "foreign", linked, .{});
    const policy = Policy.defaults(.tests);
    const preview = try fixture.context.collect(policy, true);
    try std.testing.expectEqual(@as(usize, 2), preview.removed.entries);
    try std.testing.expect(exists(fixture.temporary.dir, orphan));
    const applied = try fixture.context.collect(policy, false);
    try std.testing.expectEqual(@as(usize, 2), applied.removed.entries);
    try std.testing.expect(!exists(fixture.temporary.dir, orphan));
    try std.testing.expect(!exists(fixture.temporary.dir, crashed));
    try std.testing.expect(exists(fixture.temporary.dir, kept));
    try std.testing.expect(exists(fixture.temporary.dir, try fixture.sidecarOf(kept)));
    // A suffix of another kind, a key that is not lower-case hex and a link are foreign, so kept.
    try std.testing.expect(exists(fixture.temporary.dir, other));
    try std.testing.expect(exists(fixture.temporary.dir, upper));
    try std.testing.expect(exists(fixture.temporary.dir, linked));
    try std.testing.expect(applied.unmet_budget);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "a compiler namespace does not take a work file for a sidecar" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const blob = try fixture.entry('a', 5, 1);
    const stray = try fixture.sidecarOf(blob);
    try put(fixture.temporary.dir, stray, "x");
    const swept = try fixture.context.collect(.{ .max_bytes = 0, .max_entries = 0 }, false);
    try std.testing.expectEqual(@as(usize, 1), swept.removed.entries);
    try std.testing.expect(exists(fixture.temporary.dir, stray));
    try std.testing.expect(swept.unmet_budget);
}

/// A namespace directory `compiler-artifacts-v2` (or `native-tests-v3`) inside a fresh temporary root, for the marker tests.
const Bare = struct {
    temporary: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    root: []const u8,
    namespace: []const u8,
    kind: Kind,
    fn init(backing: std.mem.Allocator, kind: Kind) !Bare {
        var arena = std.heap.ArenaAllocator.init(backing);
        errdefer arena.deinit();
        var temporary = std.testing.tmpDir(.{});
        errdefer temporary.cleanup();
        const a = arena.allocator();
        const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
        const namespace = try std.fs.path.join(a, &.{ root, kind.namespace() });
        return .{ .temporary = temporary, .arena = arena, .root = root, .namespace = namespace, .kind = kind };
    }
    /// The retention context of the namespace, on this fixture's arena (bound where the fixture now lives).
    fn context(self: *Bare) Context {
        return Context.init(self.arena.allocator(), std.testing.io, self.namespace, self.kind);
    }
    fn deinit(self: *Bare) void {
        self.temporary.cleanup();
        self.arena.deinit();
    }
    /// A file or directory of the namespace, by its leaf name.
    fn path(self: *Bare, leaf: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena.allocator(), &.{ self.kind.namespace(), leaf });
    }
    fn marker(self: *Bare) ![]u8 {
        return self.temporary.dir.readFileAlloc(std.testing.io, try self.path("format"), self.arena.allocator(), .limited(128));
    }
};

// spec-case: NATIVE-CACHE-RETENTION-1
test "a namespace with no marker is fresh, unmarked or foreign by what it holds" {
    var bare = try Bare.init(std.testing.allocator, .compiler);
    defer bare.deinit();
    try std.testing.expectEqual(Condition.fresh, try bare.context().condition());
    try put(bare.temporary.dir, bare.kind.namespace(), "a file where the namespace belongs");
    try std.testing.expectEqual(Condition.fresh, try bare.context().condition());
    try bare.temporary.dir.deleteFile(std.testing.io, bare.kind.namespace());
    try bare.temporary.dir.createDirPath(std.testing.io, try bare.path("syntax"));
    try std.testing.expectEqual(Condition.unmarked, try bare.context().condition());
    try bare.temporary.dir.createDirPath(std.testing.io, try bare.path("program"));
    try put(bare.temporary.dir, try bare.path("retention-last"), "1");
    try std.testing.expectEqual(Condition.unmarked, try bare.context().condition());
    try put(bare.temporary.dir, try bare.path("notes.txt"), "someone else's file");
    try std.testing.expectEqual(Condition.foreign, try bare.context().condition());
    try bare.temporary.dir.deleteFile(std.testing.io, try bare.path("notes.txt"));
    try bare.temporary.dir.createDirPath(std.testing.io, try bare.path("receipts"));
    try std.testing.expectEqual(Condition.foreign, try bare.context().condition());
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "control files alone leave a namespace fresh, and an empty tests namespace is fresh too" {
    var bare = try Bare.init(std.testing.allocator, .compiler);
    defer bare.deinit();
    try bare.temporary.dir.createDirPath(std.testing.io, try bare.path("."));
    try put(bare.temporary.dir, try bare.path(".lock"), "");
    try put(bare.temporary.dir, try bare.path(lease_leaf), "");
    try std.testing.expectEqual(Condition.fresh, try bare.context().condition());
    var tests = try Bare.init(std.testing.allocator, .tests);
    defer tests.deinit();
    try tests.temporary.dir.createDirPath(std.testing.io, try tests.path("work"));
    try std.testing.expectEqual(Condition.unmarked, try tests.context().condition());
    try tests.temporary.dir.createDirPath(std.testing.io, try tests.path("syntax"));
    try std.testing.expectEqual(Condition.foreign, try tests.context().condition());
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "a marker that is not this kind's current one is bad, whatever it holds, and a current one is initialized" {
    var bare = try Bare.init(std.testing.allocator, .compiler);
    defer bare.deinit();
    try bare.temporary.dir.createDirPath(std.testing.io, try bare.path("syntax"));
    try put(bare.temporary.dir, try bare.path("format"), "selka-compiler-artifact-store-v1\n");
    try std.testing.expectEqual(Condition.bad_marker, try bare.context().condition());
    try put(bare.temporary.dir, try bare.path("format"), "");
    try std.testing.expectEqual(Condition.bad_marker, try bare.context().condition());
    try put(bare.temporary.dir, try bare.path("format"), Kind.tests.format());
    try std.testing.expectEqual(Condition.bad_marker, try bare.context().condition());
    try bare.temporary.dir.deleteFile(std.testing.io, try bare.path("format"));
    try bare.temporary.dir.createDir(std.testing.io, try bare.path("format"), .default_dir);
    try std.testing.expectEqual(Condition.bad_marker, try bare.context().condition());
    try bare.temporary.dir.deleteDir(std.testing.io, try bare.path("format"));
    try put(bare.temporary.dir, try bare.path("format"), Kind.compiler.format());
    try std.testing.expectEqual(Condition.initialized, try bare.context().condition());
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "adopting an unmarked namespace writes the marker and nothing else, and then collection works" {
    var bare = try Bare.init(std.testing.allocator, .compiler);
    defer bare.deinit();
    const blob = "syntax/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef.blob";
    try bare.temporary.dir.createDirPath(std.testing.io, try bare.path("syntax"));
    try put(bare.temporary.dir, try bare.path(blob), "an artifact of the namespace that lost its marker");
    try put(bare.temporary.dir, try bare.path(lease_leaf), "");
    try std.testing.expectError(error.ReadFailed, bare.context().collect(null, true));
    try std.testing.expectEqual(Condition.unmarked, try bare.context().adopt());
    try std.testing.expectEqualStrings(Kind.compiler.format(), try bare.marker());
    try std.testing.expect(exists(bare.temporary.dir, try bare.path(blob)));
    try std.testing.expectEqual(Condition.initialized, try bare.context().adopt());
    const preview = try bare.context().collect(null, true);
    try std.testing.expectEqual(@as(usize, 1), preview.inventory.entries);
    try std.testing.expect(!preview.unmet_budget);
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "adopting a fresh namespace creates it, and a wrong marker or a foreign entry is refused without a trace" {
    var fresh = try Bare.init(std.testing.allocator, .tests);
    defer fresh.deinit();
    try std.testing.expectEqual(Condition.fresh, try fresh.context().adopt());
    try std.testing.expectEqualStrings(Kind.tests.format(), try fresh.marker());
    var wrong = try Bare.init(std.testing.allocator, .compiler);
    defer wrong.deinit();
    try wrong.temporary.dir.createDirPath(std.testing.io, try wrong.path("syntax"));
    try put(wrong.temporary.dir, try wrong.path("format"), "selka-compiler-artifact-store-v1\n");
    try std.testing.expectError(error.ReadFailed, wrong.context().adopt());
    try std.testing.expectEqualStrings("selka-compiler-artifact-store-v1\n", try wrong.marker());
    try std.testing.expect(!exists(wrong.temporary.dir, try wrong.path(".lock")));
    var foreign = try Bare.init(std.testing.allocator, .compiler);
    defer foreign.deinit();
    try foreign.temporary.dir.createDirPath(std.testing.io, try foreign.path("syntax"));
    try put(foreign.temporary.dir, try foreign.path("notes.txt"), "not ours");
    try std.testing.expectError(error.ReadFailed, foreign.context().adopt());
    try std.testing.expect(!exists(foreign.temporary.dir, try foreign.path("format")));
    try std.testing.expect(!exists(foreign.temporary.dir, try foreign.path(".lock")));
}

// spec-case: SHARED-STORE-4
test "an unusable default store warns once with the command that repairs it, and one that was never created does not" {
    var bare = try Bare.init(std.testing.allocator, .compiler);
    defer bare.deinit();
    const a = bare.arena.allocator();
    try std.testing.expectEqual(@as(?[]u8, null), try unusableWarning(a, std.testing.io, bare.root, .compiler, error.WriteFailed));
    try bare.temporary.dir.createDirPath(std.testing.io, try bare.path("program"));
    const unmarked = (try unusableWarning(a, std.testing.io, bare.root, .compiler, error.ReadFailed)).?;
    try std.testing.expect(std.mem.startsWith(u8, unmarked, "warning: shared compiler cache disabled: "));
    try std.testing.expect(std.mem.indexOf(u8, unmarked, "has no format marker") != null);
    const repair = try std.fmt.allocPrint(a, "`selka cache init --shared-cache-dir {s} --kind compiler`", .{bare.root});
    try std.testing.expect(std.mem.indexOf(u8, unmarked, repair) != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, unmarked, "\n"));
    try put(bare.temporary.dir, try bare.path("format"), "damaged");
    const damaged = (try unusableWarning(a, std.testing.io, bare.root, .compiler, error.ReadFailed)).?;
    try std.testing.expect(std.mem.indexOf(u8, damaged, "is not this cache's marker") != null);
    try std.testing.expect(std.mem.indexOf(u8, damaged, "mv ") != null);
    try bare.temporary.dir.deleteFile(std.testing.io, try bare.path("format"));
    try put(bare.temporary.dir, try bare.path("stray"), "x");
    const foreign = (try unusableWarning(a, std.testing.io, bare.root, .compiler, error.ReadFailed)).?;
    try std.testing.expect(std.mem.indexOf(u8, foreign, "holds files that are not this cache's") != null);
    try bare.temporary.dir.deleteFile(std.testing.io, try bare.path("stray"));
    try put(bare.temporary.dir, try bare.path("format"), Kind.compiler.format());
    const other = (try unusableWarning(a, std.testing.io, bare.root, .compiler, error.ReadFailed)).?;
    try std.testing.expect(std.mem.indexOf(u8, other, "ReadFailed") != null);
}

/// The name of the entry `byte` makes in `tier` (`<tier>/<64 times byte><suffix>`), in the fixture's arena.
fn named(fixture: *Fixture, tier_name: []const u8, byte: u8, suffix: []const u8) ![]const u8 {
    return std.fmt.allocPrint(fixture.arena.allocator(), "{s}/{s}{s}", .{ tier_name, @as([64]u8, @splat(byte)), suffix });
}
/// Put the compiler namespace's records of every tier a sweep tells apart: an old (`b`) and a new (`c`) blob in each of `syntax`,
/// `typed`, `engine_record` and `engine_object`, each with its key lock, and an oldest (`a`) linked program with its sidecar.
fn compilerTiers(fixture: *Fixture) !void {
    try fixture.temporary.dir.createDirPath(std.testing.io, "program");
    const program = try named(fixture, "program", 'a', ".blob");
    try put(fixture.temporary.dir, program, "executable");
    try put(fixture.temporary.dir, try named(fixture, "program", 'a', ".blob.sum"), "sum");
    try fixture.temporary.dir.setTimestamps(std.testing.io, program, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 1 } } });
    for ([_][]const u8{ "syntax", "typed", "engine_record", "engine_object" }) |tier_name| {
        try fixture.temporary.dir.createDirPath(std.testing.io, tier_name);
        for ([_]struct { byte: u8, at: i96 }{ .{ .byte = 'b', .at = 2 }, .{ .byte = 'c', .at = 9 } }) |one| {
            const blob = try named(fixture, tier_name, one.byte, ".blob");
            try put(fixture.temporary.dir, blob, "record");
            try put(fixture.temporary.dir, try named(fixture, tier_name, one.byte, ".blob.lock"), "");
            try fixture.temporary.dir.setTimestamps(std.testing.io, blob, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = one.at } } });
        }
    }
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "F31 a sweep beside builders trims the engine's tiers with the others, leaves a linked program and a busy key, and later gets them" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try compilerTiers(&fixture);
    const program = try named(&fixture, "program", 'a', ".blob");
    const busy = try named(&fixture, "typed", 'b', ".blob");
    // Keep two files: fewer than the sweep can reach, because the program and the busy record with its lock stay.
    const quota: Policy = .{ .max_bytes = 1 << 20, .max_entries = 2 };
    {
        // A builder is publishing the key of the old typed record, and holds the namespace as builders do.
        const busy_lock = try std.fmt.allocPrint(fixture.arena.allocator(), "{s}/{s}.lock", .{ fixture.context.root, busy });
        const publishing = (try storage.openLock(std.testing.allocator, std.testing.io, busy_lock, true)).?;
        defer publishing.close(std.testing.io);
        try std.testing.expect(try publishing.tryLock(std.testing.io, .exclusive));
        const lease = try fixture.context.lease();
        defer lease.close(std.testing.io);
        const beside = try fixture.context.collect(quota, false);
        try std.testing.expect(beside.walk.leased);
        try std.testing.expect(exists(fixture.temporary.dir, program)); // linked programs need the exclusive lease
        try std.testing.expect(exists(fixture.temporary.dir, busy)); // its key is being published
        try std.testing.expect(!exists(fixture.temporary.dir, try named(&fixture, "engine_record", 'b', ".blob")));
        try std.testing.expect(!exists(fixture.temporary.dir, try named(&fixture, "engine_record", 'b', ".blob.lock")));
        try std.testing.expect(!exists(fixture.temporary.dir, try named(&fixture, "engine_object", 'b', ".blob")));
        try std.testing.expect(!exists(fixture.temporary.dir, try named(&fixture, "syntax", 'b', ".blob")));
        try std.testing.expect(!exists(fixture.temporary.dir, try named(&fixture, "engine_record", 'c', ".blob")));
        try std.testing.expect(beside.unmet_budget); // the program and the busy record keep it over its quota
    }
    // Once the builders are gone the next sweep has the store to itself: it takes the lock files and then the oldest, the program.
    const alone = try fixture.context.collect(quota, false);
    try std.testing.expect(!alone.walk.leased);
    try std.testing.expect(exists(fixture.temporary.dir, program));
    try std.testing.expect(!alone.unmet_budget);
    const smaller = try fixture.context.collect(.{ .max_bytes = 1 << 20, .max_entries = 1 }, false);
    try std.testing.expect(!smaller.walk.leased and !smaller.unmet_budget);
    try std.testing.expect(!exists(fixture.temporary.dir, program));
    try std.testing.expect(exists(fixture.temporary.dir, busy));
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "F31 lock files and staging files do not spend an automatic sweep's batch" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try populate(&fixture, 60);
    // Every record brings its key lock, as a publication leaves them; two thirds of the files are locks.
    var name: [96]u8 = undefined;
    for (0..60) |index| {
        const path = try std.fmt.bufPrint(&name, "syntax/{x:0>64}.blob.lock", .{index});
        try put(fixture.temporary.dir, path, "");
    }
    try std.testing.expect(try fixture.context.configure(.{ .max_bytes = 1 << 20, .max_entries = 20, .interval_seconds = 0 }));
    var bounded = fixture.context;
    bounded.batch_limit = 15;
    bounded.automatic();
    // The batch is fifteen records, not fifteen files: sixty locks went, and so did fifteen records.
    try std.testing.expectEqual(@as(usize, 45), try remaining(&fixture, 60));
    const lock = try std.fmt.bufPrint(&name, "syntax/{x:0>64}.blob.lock", .{@as(usize, 0)});
    try std.testing.expect(!exists(fixture.temporary.dir, lock));
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "F31 a sweep beside builders spares a staging file a publication may still be writing, and takes an abandoned one" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try populate(&fixture, 3);
    const live = "syntax/.7-5f-1.partial";
    const abandoned = "syntax/.7-5f-2.partial";
    try put(fixture.temporary.dir, live, "staging");
    try put(fixture.temporary.dir, abandoned, "staging");
    try fixture.temporary.dir.setTimestamps(std.testing.io, abandoned, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 5 } } });
    const lease = try fixture.context.lease();
    defer lease.close(std.testing.io);
    const beside = try fixture.context.collect(.{ .max_bytes = 1 << 20, .max_entries = 100 }, false);
    try std.testing.expect(beside.walk.leased);
    try std.testing.expect(exists(fixture.temporary.dir, live));
    try std.testing.expect(!exists(fixture.temporary.dir, abandoned));
    try std.testing.expectEqual(@as(usize, 3), try remaining(&fixture, 3));
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "F31 one sweep runs beside builders at a time, and none beside a collection that holds the store" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try populate(&fixture, 10);
    const lease = try fixture.context.lease();
    const only = (try fixture.context.sweeper()).?;
    const second = try fixture.context.collect(trim, false);
    try std.testing.expect(second.skipped_active);
    try std.testing.expectEqual(@as(usize, 10), try remaining(&fixture, 10));
    only.close(std.testing.io);
    lease.close(std.testing.io);
    const exclusive_guard = (try fixture.context.tryExclusive()).?;
    defer exclusive_guard.close(std.testing.io);
    try std.testing.expect((try fixture.context.collect(trim, false)).skipped_active);
    try std.testing.expectEqual(@as(usize, 10), try remaining(&fixture, 10));
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "F31 beside builders the test namespace gives up its engine records and keeps its receipts for an exclusive sweep" {
    var fixture = try Fixture.initKind(std.testing.allocator, .tests);
    defer fixture.deinit();
    try fixture.temporary.dir.createDir(std.testing.io, "engine", .default_dir);
    const record = try std.fmt.allocPrint(fixture.arena.allocator(), "engine/{s}.rec", .{@as([64]u8, @splat('a'))});
    try put(fixture.temporary.dir, record, "record");
    try fixture.temporary.dir.setTimestamps(std.testing.io, record, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 1 } } });
    const receipt = try fixture.receipt('b', 2, true);
    const lease = try fixture.context.lease();
    const quota: Policy = .{ .max_bytes = 1 << 20, .max_entries = 0 };
    const beside = try fixture.context.collect(quota, false);
    try std.testing.expect(beside.walk.leased);
    try std.testing.expect(!exists(fixture.temporary.dir, record));
    try std.testing.expect(exists(fixture.temporary.dir, receipt)); // a receipt is read with its sidecar: it waits
    try std.testing.expect(beside.unmet_budget);
    lease.close(std.testing.io);
    try std.testing.expect(!(try fixture.context.collect(quota, false)).unmet_budget);
    try std.testing.expect(!exists(fixture.temporary.dir, receipt));
}
