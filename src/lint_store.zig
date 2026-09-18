//! Baseline and ratchet stores for `mylang lint`, under `.mylang/lint/`.
//!
//! Both stores are line-oriented, committed, keyed on the checker's resolved
//! declaration identity rather than message text, and written only by
//! `lint --accept`. A baseline row makes one existing finding accepted debt so
//! adopting the gate on a large project never breaks on day one; a ratchet row
//! records a per-declaration ceiling that may only shrink.
const std = @import("std");

/// Project-root-relative directory that holds every store file.
pub const directory = ".mylang/lint";
/// Longest store file read; a larger file is a host failure.
pub const max_bytes = 4 * 1024 * 1024;
/// Marker that refuses a store file with unresolved merge conflict content.
const conflict_marker = "<<<<<<<";

/// Failures returned while reading or writing a store file.
pub const Error = error{
    ConflictMarkers,
    OutOfMemory,
    ReadFailed,
    WriteFailed,
};

/// One rule's accepted-debt baseline: the set of `<module>|<qualified>` rows.
pub const Baseline = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMapUnmanaged(void) = .empty,

    /// Release every owned row.
    pub fn deinit(self: *Baseline) void {
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| self.allocator.free(entry.key_ptr.*);
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    /// Whether one row is already accepted debt.
    pub fn contains(self: *const Baseline, row: []const u8) bool {
        return self.entries.contains(row);
    }

    /// Add one row unless it is already recorded, taking a copy.
    pub fn record(self: *Baseline, row: []const u8) std.mem.Allocator.Error!void {
        if (self.entries.contains(row)) return;
        const owned = try self.allocator.dupe(u8, row);
        errdefer self.allocator.free(owned);
        try self.entries.put(self.allocator, owned, {});
    }
};

/// One rule's per-declaration ceilings, keyed by the declared qualified name.
pub const Ratchet = struct {
    allocator: std.mem.Allocator,
    ceilings: std.StringHashMapUnmanaged(usize) = .empty,

    /// Release every owned key.
    pub fn deinit(self: *Ratchet) void {
        var iterator = self.ceilings.iterator();
        while (iterator.next()) |entry| self.allocator.free(entry.key_ptr.*);
        self.ceilings.deinit(self.allocator);
        self.* = undefined;
    }

    /// The stored ceiling for one declaration, or null when it has no row.
    pub fn ceiling(self: *const Ratchet, qualified: []const u8) ?usize {
        return self.ceilings.get(qualified);
    }

    /// Store (or raise) one declaration's ceiling. A row may only grow when
    /// `--accept` explicitly writes a fresh measurement.
    pub fn record(self: *Ratchet, qualified: []const u8, value: usize) std.mem.Allocator.Error!void {
        const gop = try self.ceilings.getOrPut(self.allocator, qualified);
        if (gop.found_existing) {
            gop.value_ptr.* = value;
            return;
        }
        const owned = try self.allocator.dupe(u8, qualified);
        errdefer self.allocator.free(owned);
        gop.key_ptr.* = owned;
        gop.value_ptr.* = value;
    }
};

/// Build the on-disk path for one store file.
fn pathFor(allocator: std.mem.Allocator, root: []const u8, prefix: []const u8, rule: []const u8, suffix: []const u8) std.mem.Allocator.Error![]u8 {
    const name = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ prefix, rule, suffix });
    defer allocator.free(name);
    return std.fs.path.join(allocator, &.{ root, directory, name });
}

/// Read a store file, or return an empty slice when it does not exist.
fn readStore(allocator: std.mem.Allocator, io: std.Io, path: []const u8) Error![]u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_bytes + 1)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileNotFound => return allocator.alloc(u8, 0) catch error.OutOfMemory,
        else => return error.ReadFailed,
    };
    if (bytes.len > max_bytes) {
        allocator.free(bytes);
        return error.ReadFailed;
    }
    if (std.mem.indexOf(u8, bytes, conflict_marker) != null) {
        allocator.free(bytes);
        return error.ConflictMarkers;
    }
    return bytes;
}

/// Load one rule's baseline. A missing file is an empty baseline.
pub fn loadBaseline(allocator: std.mem.Allocator, io: std.Io, root: []const u8, rule: []const u8) Error!Baseline {
    const path = try pathFor(allocator, root, "baseline-", rule, ".txt");
    defer allocator.free(path);
    const bytes = try readStore(allocator, io, path);
    defer allocator.free(bytes);
    var baseline: Baseline = .{ .allocator = allocator };
    errdefer baseline.deinit();
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const row = std.mem.trim(u8, line, " \t\r");
        if (row.len == 0) continue;
        try baseline.record(row);
    }
    return baseline;
}

/// Load one rule's ratchet. A missing file is an empty ratchet.
pub fn loadRatchet(allocator: std.mem.Allocator, io: std.Io, root: []const u8, rule: []const u8) Error!Ratchet {
    const path = try pathFor(allocator, root, "ratchet-", rule, ".txt");
    defer allocator.free(path);
    const bytes = try readStore(allocator, io, path);
    defer allocator.free(bytes);
    var ratchet: Ratchet = .{ .allocator = allocator };
    errdefer ratchet.deinit();
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const row = std.mem.trim(u8, line, " \t\r");
        if (row.len == 0) continue;
        const split = std.mem.lastIndexOfScalar(u8, row, ' ') orelse continue;
        const value = std.fmt.parseUnsigned(usize, row[split + 1 ..], 10) catch continue;
        try ratchet.record(row[0..split], value);
    }
    return ratchet;
}

/// Write one baseline, sorted by row so the store is stable and merge-friendly.
pub fn saveBaseline(baseline: *Baseline, allocator: std.mem.Allocator, io: std.Io, root: []const u8, rule: []const u8) Error!void {
    var rows: std.ArrayList([]const u8) = .empty;
    defer rows.deinit(allocator);
    var iterator = baseline.entries.keyIterator();
    while (iterator.next()) |key| try rows.append(allocator, key.*);
    std.mem.sort([]const u8, rows.items, {}, lessThan);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    for (rows.items) |row| {
        try out.appendSlice(allocator, row);
        try out.append(allocator, '\n');
    }
    return writeStore(allocator, io, root, "baseline-", rule, out.items);
}

/// Write one ratchet, sorted by qualified name.
pub fn saveRatchet(ratchet: *Ratchet, allocator: std.mem.Allocator, io: std.Io, root: []const u8, rule: []const u8) Error!void {
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(allocator);
    var iterator = ratchet.ceilings.keyIterator();
    while (iterator.next()) |key| try names.append(allocator, key.*);
    std.mem.sort([]const u8, names.items, {}, lessThan);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    for (names.items) |name| {
        const line = try std.fmt.allocPrint(allocator, "{s} {d}\n", .{ name, ratchet.ceilings.get(name).? });
        defer allocator.free(line);
        try out.appendSlice(allocator, line);
    }
    return writeStore(allocator, io, root, "ratchet-", rule, out.items);
}

fn writeStore(allocator: std.mem.Allocator, io: std.Io, root: []const u8, prefix: []const u8, rule: []const u8, bytes: []const u8) Error!void {
    const path = try pathFor(allocator, root, prefix, rule, ".txt");
    defer allocator.free(path);
    const parent = try std.fs.path.join(allocator, &.{ root, directory });
    defer allocator.free(parent);
    std.Io.Dir.cwd().createDirPath(io, parent) catch return error.WriteFailed;
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes }) catch return error.WriteFailed;
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}
