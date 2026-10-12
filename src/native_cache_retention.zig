//! Cooperative, bounded retention for versioned native shared caches.
const std = @import("std");
const storage = @import("shared_artifact_io.zig");
const partial_suffix = ".partial";
const lease_leaf = ".retention.lock";
const policy_leaf = "retention-policy";
const last_leaf = "retention-last";
const mismatch_leaf = "mismatches.log";
/// Native storage errors, including malformed policy or namespace metadata.
pub const Error = storage.Error;
/// Independent cooperative namespaces; legacy writers never enter these roots.
pub const Kind = enum {
    compiler,
    tests,
    /// Return the dedicated directory beneath a configured shared root.
    pub fn namespace(self: Kind) []const u8 {
        return switch (self) {
            .compiler => "compiler-artifacts-v2",
            .tests => "native-tests-v2",
        };
    }
    /// Return the exact namespace marker accepted by retention.
    pub fn format(self: Kind) []const u8 {
        return switch (self) {
            .compiler => "selka-compiler-artifact-store-v2\n",
            .tests => "selka-native-test-store-v2\n",
        };
    }
};
/// Soft quotas applied at collection time, with age expiration disabled by default.
pub const Policy = struct {
    max_bytes: u64,
    max_entries: usize,
    max_age_seconds: u64 = 0,
    interval_seconds: u64 = 3600,
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
/// Collection evidence, including busy leases and deliberately incomplete inventories.
pub const Report = struct {
    skipped_active: bool = false,
    dry_run: bool = false,
    inventory: Counts = .{},
    removed: Counts = .{},
    retained: Counts = .{},
    unmet_budget: bool = false,
    inventory_complete: bool = true,
};
const hard_limit = 1000000;
const Entry = struct { path: []u8, size: u64, mtime: i96, transient: bool };
const Inventory = struct { entries: std.ArrayList(Entry) = .empty, foreign: bool = false, complete: bool = true, visited: usize = 0 };
/// Borrowed namespace context; callers retain the root path for its lifetime.
pub const Context = struct {
    scratch: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    kind: Kind,
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
    /// Refresh verified-hit recency without affecting record validity.
    pub fn touch(self: Context, file: std.Io.File) void {
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
    pub fn automatic(self: Context) void {
        _ = self.sweep(null, false, true) catch return;
    }
    /// Force collection or preview it without initializing absent or legacy roots.
    pub fn collect(self: Context, override: ?Policy, dry_run: bool) Error!Report {
        return self.sweep(override, dry_run, false);
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
        const guard = try self.exclusive(!dry_run) orelse return .{ .skipped_active = true, .dry_run = dry_run };
        defer guard.close(self.io);
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
        var report: Report = .{ .dry_run = dry_run, .inventory_complete = inventory.complete, .unmet_budget = inventory.foreign or !inventory.complete };
        for (inventory.entries.items) |entry| add(&report.inventory, entry.size);
        report.retained = report.inventory;
        if (!inventory.complete) return report;
        std.mem.sort(Entry, inventory.entries.items, {}, older);
        for (inventory.entries.items) |entry| {
            const aged = value.max_age_seconds != 0 and now -| entry.mtime >= @as(i96, value.max_age_seconds) * std.time.ns_per_s;
            const under_budget = report.retained.bytes <= value.max_bytes and report.retained.entries <= value.max_entries;
            const obsolete = entry.transient or aged;
            if (!obsolete and under_budget) continue;
            if (!dry_run) std.Io.Dir.cwd().deleteFile(self.io, entry.path) catch return error.WriteFailed;
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
    fn scan(self: Context, result: *Inventory) Error!void {
        var root = std.Io.Dir.cwd().openDir(self.io, self.root, .{ .iterate = true, .follow_symlinks = false }) catch return error.ReadFailed;
        defer root.close(self.io);
        var iterator = root.iterate();
        while (iterator.next(self.io) catch return error.ReadFailed) |entry| {
            result.visited += 1;
            if (result.visited > hard_limit) {
                result.complete = false;
                return;
            }
            if (control(entry.name)) {
                if (std.mem.endsWith(u8, entry.name, partial_suffix)) {
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
            if (!result.complete) return;
        }
    }
    fn knownTierEntry(self: Context, path: []const u8, name: []const u8) bool {
        if (std.mem.eql(u8, std.fs.path.basename(path), "work")) return workLock(name);
        return known(self.kind, name);
    }
    fn scanTier(self: Context, path: []const u8, result: *Inventory) Error!void {
        var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true, .follow_symlinks = false }) catch return error.ReadFailed;
        defer dir.close(self.io);
        var iterator = dir.iterate();
        while (iterator.next(self.io) catch return error.ReadFailed) |entry| {
            result.visited += 1;
            if (result.visited > hard_limit) {
                result.complete = false;
                return;
            }
            if (!self.knownTierEntry(path, entry.name) or entry.kind != .file) {
                result.foreign = true;
                continue;
            }
            if (result.entries.items.len >= hard_limit) {
                result.complete = false;
                return;
            }
            const full = try std.fs.path.join(self.scratch, &.{ path, entry.name });
            errdefer self.scratch.free(full);
            const info = dir.statFile(self.io, entry.name, .{ .follow_symlinks = false }) catch return error.ReadFailed;
            if (info.kind != .file) {
                self.scratch.free(full);
                result.foreign = true;
                continue;
            }
            const transient = std.mem.endsWith(u8, entry.name, partial_suffix) or std.mem.endsWith(u8, entry.name, ".lock");
            try result.entries.append(self.scratch, .{ .path = full, .size = if (std.mem.endsWith(u8, entry.name, ".lock")) 0 else info.size, .mtime = info.mtime.nanoseconds, .transient = transient });
        }
    }
};
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
    return if (kind == .tests) std.mem.eql(u8, name, "receipts") else std.mem.eql(u8, name, "syntax") or std.mem.eql(u8, name, "typed") or std.mem.eql(u8, name, "program");
}
fn control(name: []const u8) bool {
    for ([_][]const u8{ "format", ".lock", lease_leaf, policy_leaf, last_leaf, mismatch_leaf, "format.partial", "retention-policy.partial", "retention-last.partial" }) |item| {
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
fn known(kind: Kind, name: []const u8) bool {
    const suffix = if (kind == .compiler) ".blob" else ".pass";
    if (name.len == 64 + suffix.len and std.mem.endsWith(u8, name, suffix)) return hexKey(name[0..64]);
    if (std.mem.endsWith(u8, name, ".lock")) return kind == .compiler and name.len == 64 + suffix.len + 5 and hexKey(name[0..64]) and std.mem.eql(u8, name[64 .. name.len - 5], suffix);
    if (!std.mem.endsWith(u8, name, partial_suffix)) return false;
    if (kind == .tests) return name.len == 64 + suffix.len + 8 and hexKey(name[0..64]) and std.mem.eql(u8, name[64 .. name.len - 8], suffix);
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
        var arena = std.heap.ArenaAllocator.init(backing);
        errdefer arena.deinit();
        var temporary = std.testing.tmpDir(.{});
        errdefer temporary.cleanup();
        const a = arena.allocator();
        const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
        const context = Context.init(backing, std.testing.io, root, .compiler);
        try temporary.dir.createDir(std.testing.io, "syntax", .default_dir);
        try put(temporary.dir, "format", Kind.compiler.format());
        try put(temporary.dir, lease_leaf, "");
        return .{ .temporary = temporary, .arena = arena, .context = context };
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
test "native retention deterministic LRU quota dry run and leases" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const old = try fixture.entry('a', 5, 1);
    const new = try fixture.entry('b', 5, 2);
    const quota: Policy = .{ .max_bytes = 5, .max_entries = 1 };
    const preview = try fixture.context.collect(quota, true);
    try std.testing.expectEqual(@as(usize, 1), preview.removed.entries);
    try std.testing.expect(exists(fixture.temporary.dir, old));
    const lease = try fixture.context.lease();
    const busy = try fixture.context.collect(quota, false);
    try std.testing.expect(busy.skipped_active);
    try std.testing.expect(!(try fixture.context.configure(quota)));
    lease.close(std.testing.io);
    const swept = try fixture.context.collect(quota, false);
    try std.testing.expectEqual(@as(u64, 5), swept.retained.bytes);
    try std.testing.expect(!exists(fixture.temporary.dir, old));
    try std.testing.expect(exists(fixture.temporary.dir, new));
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
test "native retention visited bound aborts inventory without deleting and preview needs permanent lock" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const blob = try fixture.entry('a', 5, 1);
    var inventory: Inventory = .{ .visited = hard_limit };
    defer inventory.entries.deinit(std.testing.allocator);
    try fixture.context.scan(&inventory);
    try std.testing.expect(!inventory.complete);
    try std.testing.expectEqual(@as(usize, 0), inventory.entries.items.len);
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
