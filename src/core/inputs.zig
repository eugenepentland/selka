//! The inputs handle (T1 and T2 of the provable-cache plan): the one way a cached
//! step reads what its result depends on, and the record that later says whether
//! the result may be served again.
//!
//! A step that takes a `Handle` reads files, probes for files that might be there,
//! lists directories and looks up environment variables through it, and the
//! handle writes down each input with what was seen. The list is the step's
//! record. A record is served only while `unchanged` finds every input as it was:
//! a file with its digest, a file that was looked for and absent still absent, a
//! directory with the same listing, a variable with the same value.
//!
//! The vocabulary is closed on purpose, so that a rule can forbid raw file and
//! environment access in the modules of a step (K5) and everything such a module
//! needs is still expressible:
//! - `file`: bytes read, by digest (absent when the path was looked for and missing);
//! - `exists`: only whether a path is there, for a test that never reads its bytes;
//! - `listing`: a directory's entry names (all of them or the ones a named filter
//!   keeps), by digest, so a file appearing or disappearing is a change;
//! - `variable`: an environment variable's value, or its absence.
//!
//! The stat fast path of decision E2 stays: a `file` input carries the stat tuple
//! seen around a successful hash, and an unchanged tuple stands for unchanged bytes.
const std = @import("std");
const product = @import("selka").product;
const fast_blake3 = @import("fast_blake3.zig");
const unit_cache = @import("unit_cache.zig");
const language = @import("selka");
const Digest = unit_cache.Digest;

/// How a directory listing is narrowed before it is digested, so a record depends
/// only on the names that can change its result. The rule of each filter is part
/// of the compiler's identity, which every record already keys.
pub const Filter = enum {
    /// Every entry.
    all,
    /// The `.selka` files named like a module of the embedded standard library.
    standard_modules,

    /// Whether a directory entry called `name` stays in a listing under this filter.
    pub fn keeps(self: Filter, name: []const u8) bool {
        return switch (self) {
            .all => true,
            .standard_modules => product.isSource(name) and language.standard_library.source(name) != null,
        };
    }
};

/// A path whose existence alone was tested.
pub const Existence = struct { path: []const u8, present: bool };

/// A directory listing: the digest of the sorted names `filter` keeps, or null when
/// the directory could not be opened.
pub const Listing = struct { path: []const u8, filter: Filter, digest: ?Digest };

/// An environment variable: its value, or null when it was not set.
pub const Variable = struct { name: []const u8, value: ?[]const u8 };

/// One recorded input. `file` is `unit_cache.Dependency`: a null digest records a
/// path that was looked for and was not there.
pub const Input = union(enum) {
    file: unit_cache.Dependency,
    exists: Existence,
    listing: Listing,
    variable: Variable,
};

/// What a recorded input needs to be checked again.
pub const Live = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    /// A handle that has just looked at the directories and variables a record lists, if any:
    /// what it saw moments ago stands for looking again.
    observed: ?*const Handle = null,
};

/// The inputs of one step as it reads them. `torn` is set when the same path gave
/// different bytes twice; such a step has no trustworthy record.
pub const Handle = struct {
    live: Live,
    recorded: std.ArrayList(Input) = .empty,
    index: std.StringHashMapUnmanaged(usize) = .empty,
    torn: bool = false,
    /// The inputs of the newest earlier record, whose file stamps `seal` may inherit (`inherit`).
    earlier: []const Input = &.{},

    /// A handle that reads through `io` and `environment` and keeps its notes in `arena`.
    pub fn init(arena: std.mem.Allocator, io: std.Io, environment: *const std.process.Environ.Map) Handle {
        return .{ .live = .{ .arena = arena, .io = io, .environment = environment } };
    }

    /// Everything recorded so far, in the order it was first read.
    pub fn inputs(self: *const Handle) []const Input {
        return self.recorded.items;
    }

    /// The bytes of the file at `path`, recorded by digest. An absent file is
    /// `error.ReadFailed` and is not recorded: use `digest` to look for one.
    pub fn read(self: *Handle, path: []const u8, limit: usize) error{ OutOfMemory, ReadFailed }![]const u8 {
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.live.io, path, self.live.arena, .limited(limit)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.ReadFailed,
        };
        try self.pin(path, bytes);
        return bytes;
    }

    /// Record that the build used `bytes` for the file at `path`, when the caller
    /// read them itself (the front end loads module sources before any handle exists).
    pub fn pin(self: *Handle, path: []const u8, bytes: []const u8) error{OutOfMemory}!void {
        var digest_bytes: Digest = undefined;
        fast_blake3.hash(bytes, &digest_bytes);
        try self.record(.{ .file = .{ .path = path, .digest = digest_bytes } });
    }

    /// The digest of the file at `path`, or null when it is not there; either
    /// answer is recorded, so a file that appears later is a change.
    pub fn digest(self: *Handle, path: []const u8) error{ OutOfMemory, ReadFailed }!?Digest {
        const found = try unit_cache.fileDigest(self.live.arena, self.live.io, path);
        try self.record(.{ .file = .{ .path = path, .digest = found } });
        return found;
    }

    /// Whether anything is at `path`, recorded as only that.
    pub fn exists(self: *Handle, path: []const u8) error{OutOfMemory}!bool {
        const present = presence(self.live.io, path);
        try self.record(.{ .exists = .{ .path = path, .present = present } });
        return present;
    }

    /// The names in the directory `path` that `filter` keeps, in directory order;
    /// the sorted names are recorded by digest. A directory that cannot be opened
    /// lists nothing and is recorded as such.
    pub fn listing(self: *Handle, path: []const u8, filter: Filter) error{OutOfMemory}![]const []const u8 {
        const names = try listNames(self.live.arena, self.live.io, path, filter);
        try self.record(.{ .listing = .{ .path = path, .filter = filter, .digest = if (names) |kept| try namesDigest(self.live.arena, kept) else null } });
        return names orelse &.{};
    }

    /// The value of the environment variable `name`, recorded with its absence.
    pub fn variable(self: *Handle, name: []const u8) error{OutOfMemory}!?[]const u8 {
        const value = self.live.environment.get(name);
        try self.record(.{ .variable = .{ .name = name, .value = value } });
        return value;
    }

    /// Every set variable the environment identity contract keys (the `keyed`
    /// class of `environment_identity.zon`), by name order, each recorded. Anything
    /// else in the environment (a terminal's size, a job count, a cache location)
    /// cannot change what a step produces, so it is neither read nor recorded.
    pub fn keyedEnvironment(self: *Handle) error{OutOfMemory}![]const Variable {
        var found: std.ArrayList(Variable) = .empty;
        var entries = self.live.environment.iterator();
        while (entries.next()) |entry| {
            if (!language.environment_identity.keyed(entry.key_ptr.*)) continue;
            try found.append(self.live.arena, .{ .name = entry.key_ptr.*, .value = entry.value_ptr.* });
        }
        std.mem.sort(Variable, found.items, {}, variableBefore);
        for (found.items) |item| try self.record(.{ .variable = item });
        return found.items;
    }

    /// The real path of the process's working directory, the base of every relative
    /// path a step was given, or "" when it cannot be resolved.
    pub fn workingDirectory(self: *const Handle) []const u8 {
        return std.Io.Dir.cwd().realPathFileAlloc(self.live.io, ".", self.live.arena) catch "";
    }

    /// What this handle recorded for the same thing as `probe` (a directory listing, a variable or an
    /// existence test; a file is never answered from notes), or null.
    pub fn observation(self: *const Handle, probe: Input) ?Input {
        if (probe == .file) return null;
        const key = identity(self.live.arena, probe) catch return null;
        const at = self.index.get(key) orelse return null;
        return self.recorded.items[at];
    }

    /// Take over what another step already read and recorded, as part of this one.
    pub fn merge(self: *Handle, other: []const Input) error{OutOfMemory}!void {
        for (other) |input| try self.record(input);
    }

    /// Offer the inputs of the newest earlier record of this build's settings (a replay that missed loaded it) to `seal`. The first
    /// offer stands; later ones are ignored.
    pub fn inherit(self: *Handle, recorded: []const Input) void {
        if (self.earlier.len == 0) self.earlier = recorded;
    }

    /// The record, ready to store: every file pinned with the stat tuple seen
    /// around a rehash. Null when a file changed since the step read it, or was
    /// read twice with different bytes.
    ///
    /// A file the earlier record (`inherit`) lists with the same digest and a stamp, whose status still equals that stamp, keeps the stamp
    /// without a rehash: the earlier seal verified the bytes under that stamp, and a status that has not moved is what a replay takes for
    /// unchanged bytes. A file whose status moved, or that the earlier record does not list, is rehashed as before.
    pub fn seal(self: *const Handle) error{OutOfMemory}!?[]const Input {
        if (self.torn) return null;
        const sealed = try self.live.arena.alloc(Input, self.recorded.items.len);
        var earlier: std.StringHashMapUnmanaged(unit_cache.Dependency) = .empty;
        for (self.earlier) |input| switch (input) {
            .file => |file| if (file.stamp != null and file.digest != null) try earlier.put(self.live.arena, file.path, file),
            else => {},
        };
        for (self.recorded.items, sealed) |input, *slot| switch (input) {
            .file => |file| {
                if (earlier.get(file.path)) |before| {
                    if (file.digest != null and std.mem.eql(u8, &file.digest.?, &before.digest.?) and unit_cache.statusIs(self.live.io, file.path, before.stamp.?)) {
                        slot.* = .{ .file = .{ .path = file.path, .digest = file.digest, .stamp = before.stamp } };
                        continue;
                    }
                }
                slot.* = .{ .file = (try unit_cache.observed(self.live.arena, self.live.io, file)) orelse return null };
            },
            else => slot.* = input,
        };
        return sealed;
    }

    fn record(self: *Handle, input: Input) error{OutOfMemory}!void {
        const key = try identity(self.live.arena, input);
        const found = try self.index.getOrPut(self.live.arena, key);
        if (!found.found_existing) {
            found.value_ptr.* = self.recorded.items.len;
            try self.recorded.append(self.live.arena, input);
            return;
        }
        if (!sameObservation(self.recorded.items[found.value_ptr.*], input)) self.torn = true;
    }
};

/// Whether every recorded input is still as it was seen. A file is compared by
/// stat tuple and then by digest; a directory is listed again; a variable is read
/// again. Nothing is written.
pub fn unchanged(live: Live, recorded: []const Input) error{OutOfMemory}!bool {
    for (recorded) |input| if (!try same(live, input)) return false;
    return true;
}

fn same(live: Live, input: Input) error{OutOfMemory}!bool {
    if (live.observed) |handle| if (handle.observation(input)) |seen| return sameObservation(seen, input);
    switch (input) {
        .file => |file| return unit_cache.unchanged(live.arena, live.io, &.{file}),
        .exists => |probe| return presence(live.io, probe.path) == probe.present,
        .listing => |seen| {
            const names = try listNames(live.arena, live.io, seen.path, seen.filter);
            const now: ?Digest = if (names) |kept| try namesDigest(live.arena, kept) else null;
            if (now == null or seen.digest == null) return now == null and seen.digest == null;
            return std.mem.eql(u8, &now.?, &seen.digest.?);
        },
        .variable => |seen| {
            const now = live.environment.get(seen.name);
            if (now == null or seen.value == null) return now == null and seen.value == null;
            return std.mem.eql(u8, now.?, seen.value.?);
        },
    }
}

fn presence(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

/// The names `filter` keeps in the directory `path`, or null when it cannot be opened.
pub fn listNames(arena: std.mem.Allocator, io: std.Io, path: []const u8, filter: Filter) error{OutOfMemory}!?[]const []const u8 {
    var directory = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return null;
    defer directory.close(io);
    var kept: std.ArrayList([]const u8) = .empty;
    var iterator = directory.iterate();
    while (iterator.next(io) catch return null) |item| {
        if (filter.keeps(item.name)) try kept.append(arena, try arena.dupe(u8, item.name));
    }
    return kept.items;
}

/// The digest of a listing: the names in byte order, each length-delimited.
fn namesDigest(arena: std.mem.Allocator, names: []const []const u8) error{OutOfMemory}!Digest {
    const sorted = try arena.dupe([]const u8, names);
    defer arena.free(sorted);
    std.mem.sort([]const u8, sorted, {}, nameBefore);
    var hash = fast_blake3.Blake3.init(.{});
    unit_cache.field(&hash, "core-inputs-listing-v1");
    for (sorted) |name| unit_cache.field(&hash, name);
    var result: Digest = undefined;
    hash.final(&result);
    return result;
}

fn nameBefore(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn variableBefore(_: void, left: Variable, right: Variable) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

/// What names one input within a record: its kind and path or name, plus the
/// filter of a listing, which makes two listings of one directory distinct.
fn identity(arena: std.mem.Allocator, input: Input) error{OutOfMemory}![]const u8 {
    return switch (input) {
        .file => |file| std.fmt.allocPrint(arena, "f\x00{s}", .{file.path}),
        .exists => |probe| std.fmt.allocPrint(arena, "e\x00{s}", .{probe.path}),
        .listing => |seen| std.fmt.allocPrint(arena, "l\x00{s}\x00{s}", .{ @tagName(seen.filter), seen.path }),
        .variable => |seen| std.fmt.allocPrint(arena, "v\x00{s}", .{seen.name}),
    };
}

/// Whether two sightings of one input agree.
fn sameObservation(left: Input, right: Input) bool {
    switch (left) {
        .file => |a| {
            const b = right.file;
            if (a.digest == null or b.digest == null) return a.digest == null and b.digest == null;
            return std.mem.eql(u8, &a.digest.?, &b.digest.?);
        },
        .exists => |a| return a.present == right.exists.present,
        .listing => |a| {
            const b = right.listing;
            if (a.digest == null or b.digest == null) return a.digest == null and b.digest == null;
            return std.mem.eql(u8, &a.digest.?, &b.digest.?);
        },
        .variable => |a| {
            const b = right.variable;
            if (a.value == null or b.value == null) return a.value == null and b.value == null;
            return std.mem.eql(u8, a.value.?, b.value.?);
        },
    }
}

/// A digest of what a record saw, without the status tuples that only speed up checking it,
/// so the same inputs give the same digest in any checkout on any machine.
pub fn identityDigest(recorded: []const Input) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    unit_cache.field(&hash, "core-inputs-identity-v1");
    for (recorded) |input| switch (input) {
        .file => |file| {
            unit_cache.field(&hash, "file");
            unit_cache.field(&hash, file.path);
            unit_cache.field(&hash, if (file.digest) |*found| found else "absent");
        },
        .exists => |probe| {
            unit_cache.field(&hash, "exists");
            unit_cache.field(&hash, probe.path);
            unit_cache.field(&hash, if (probe.present) "present" else "absent");
        },
        .listing => |seen| {
            unit_cache.field(&hash, "listing");
            unit_cache.field(&hash, seen.path);
            unit_cache.field(&hash, @tagName(seen.filter));
            unit_cache.field(&hash, if (seen.digest) |*found| found else "absent");
        },
        .variable => |seen| {
            unit_cache.field(&hash, "variable");
            unit_cache.field(&hash, seen.name);
            unit_cache.field(&hash, if (seen.value) |value| value else "unset");
        },
    };
    var result: Digest = undefined;
    hash.final(&result);
    return result;
}

/// The stored form of an input: one flat shape for every kind, with the fields a
/// kind does not use left out of the JSON.
pub const Wire = struct {
    kind: std.meta.Tag(Input),
    name: []const u8,
    digest: ?[]const u8 = null,
    stamp: ?unit_cache.Stamp = null,
    present: ?bool = null,
    filter: ?Filter = null,
    value: ?[]const u8 = null,
};

/// The stored form of `recorded`.
pub fn toWire(arena: std.mem.Allocator, recorded: []const Input) error{OutOfMemory}![]const Wire {
    const wire = try arena.alloc(Wire, recorded.len);
    for (recorded, wire) |input, *slot| slot.* = switch (input) {
        .file => |file| .{ .kind = .file, .name = file.path, .digest = if (file.digest) |found| try hex(arena, found) else null, .stamp = file.stamp },
        .exists => |probe| .{ .kind = .exists, .name = probe.path, .present = probe.present },
        .listing => |seen| .{ .kind = .listing, .name = seen.path, .filter = seen.filter, .digest = if (seen.digest) |found| try hex(arena, found) else null },
        .variable => |seen| .{ .kind = .variable, .name = seen.name, .value = seen.value },
    };
    return wire;
}

/// The inputs a stored form describes; null when any entry is malformed.
pub fn fromWire(arena: std.mem.Allocator, wire: []const Wire) error{OutOfMemory}!?[]const Input {
    const recorded = try arena.alloc(Input, wire.len);
    for (wire, recorded) |entry, *slot| {
        const parsed: ?Digest = if (entry.digest) |text| parseDigest(text) orelse return null else null;
        slot.* = switch (entry.kind) {
            .file => .{ .file = .{ .path = entry.name, .digest = parsed, .stamp = entry.stamp } },
            .exists => .{ .exists = .{ .path = entry.name, .present = entry.present orelse return null } },
            .listing => .{ .listing = .{ .path = entry.name, .filter = entry.filter orelse return null, .digest = parsed } },
            .variable => .{ .variable = .{ .name = entry.name, .value = entry.value } },
        };
    }
    return recorded;
}

/// A record as text, for a store that keeps it beside an object. The same inputs
/// always give the same text.
pub fn manifest(arena: std.mem.Allocator, recorded: []const Input) error{OutOfMemory}![]const u8 {
    const wire = try toWire(arena, recorded);
    return std.json.Stringify.valueAlloc(arena, wire, .{ .emit_null_optional_fields = false });
}

/// The inputs `manifest` wrote; null for anything else.
pub fn parseManifest(arena: std.mem.Allocator, text: []const u8) error{OutOfMemory}!?[]const Input {
    const wire = std.json.parseFromSliceLeaky([]const Wire, arena, text, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    return fromWire(arena, wire);
}

fn hex(arena: std.mem.Allocator, value: Digest) error{OutOfMemory}![]const u8 {
    return arena.dupe(u8, &std.fmt.bytesToHex(value, .lower));
}

fn parseDigest(text: []const u8) ?Digest {
    if (text.len != 64) return null;
    var value: Digest = undefined;
    _ = std.fmt.hexToBytes(&value, text) catch return null;
    return value;
}

const Fixture = struct {
    temporary: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    environment: std.process.Environ.Map,
    root: []const u8 = "",

    fn init(allocator: std.mem.Allocator) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        self.* = .{ .temporary = std.testing.tmpDir(.{}), .arena = .init(allocator), .environment = .init(allocator) };
        errdefer self.release();
        self.root = try self.temporary.dir.realPathFileAlloc(std.testing.io, ".", self.arena.allocator());
        return self;
    }

    fn release(self: *Fixture) void {
        self.environment.deinit();
        self.arena.deinit();
        self.temporary.cleanup();
    }

    fn deinit(self: *Fixture, allocator: std.mem.Allocator) void {
        self.release();
        allocator.destroy(self);
    }

    fn handle(self: *Fixture) Handle {
        return Handle.init(self.arena.allocator(), std.testing.io, &self.environment);
    }

    fn live(self: *Fixture) Live {
        return .{ .arena = self.arena.allocator(), .io = std.testing.io, .environment = &self.environment };
    }

    fn path(self: *Fixture, name: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena.allocator(), &.{ self.root, name });
    }

    fn write(self: *Fixture, name: []const u8, bytes: []const u8) !void {
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = bytes });
    }
};

test "a file input is unchanged until its bytes change, however the edit is made" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    try fixture.write("source.txt", "first");
    var handle = fixture.handle();
    const bytes = try handle.read(try fixture.path("source.txt"), 1 << 20);
    try std.testing.expectEqualStrings("first", bytes);
    const sealed = (try handle.seal()).?;
    try std.testing.expect(sealed[0].file.stamp != null);
    try std.testing.expect(try unchanged(fixture.live(), sealed));
    // Same size, same modification time put back: the change time still moves.
    const before = try fixture.temporary.dir.statFile(std.testing.io, "source.txt", .{});
    try fixture.write("source.txt", "other");
    try fixture.temporary.dir.setTimestamps(std.testing.io, "source.txt", .{ .modify_timestamp = .init(before.mtime) });
    try std.testing.expect(!try unchanged(fixture.live(), sealed));
    try fixture.write("source.txt", "first");
    try std.testing.expect(try unchanged(fixture.live(), sealed));
}

test "a seal keeps the stamp of an earlier record for a file whose status has not moved and takes a fresh one for a file that was rewritten" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    try fixture.write("kept.txt", "kept");
    try fixture.write("edited.txt", "before");
    const kept = try fixture.path("kept.txt");
    const edited = try fixture.path("edited.txt");
    var first = fixture.handle();
    try first.pin(kept, "kept");
    try first.pin(edited, "before");
    const earlier = (try first.seal()).?;
    try fixture.write("edited.txt", "after, longer");
    var second = fixture.handle();
    second.inherit(earlier);
    try second.pin(kept, "kept");
    try second.pin(edited, "after, longer");
    const sealed = (try second.seal()).?;
    try std.testing.expectEqual(earlier[0].file.stamp, sealed[0].file.stamp);
    try std.testing.expect(sealed[1].file.stamp != null);
    try std.testing.expect(!std.meta.eql(earlier[1].file.stamp, sealed[1].file.stamp));
    try std.testing.expect(try unchanged(fixture.live(), sealed));
}

test "an earlier stamp is never inherited for bytes the file no longer holds" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    try fixture.write("source.txt", "before");
    const file = try fixture.path("source.txt");
    var first = fixture.handle();
    try first.pin(file, "before");
    const earlier = (try first.seal()).?;
    try fixture.write("source.txt", "after!");
    // The step used the old bytes (the earlier digest) but the status moved: the rehash finds the file holds others, and there is no record.
    var stale = fixture.handle();
    stale.inherit(earlier);
    try stale.pin(file, "before");
    try std.testing.expectEqual(@as(?[]const Input, null), try stale.seal());
    // A first offer stands: a later one cannot replace it.
    var offered = fixture.handle();
    offered.inherit(earlier);
    offered.inherit(&.{});
    try std.testing.expectEqual(@as(usize, 1), offered.earlier.len);
}

test "a status is the stamp it was taken as until the file is rewritten" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    try fixture.write("source.txt", "first");
    const file = try fixture.path("source.txt");
    const stamp = unit_cache.Stamp.from(try fixture.temporary.dir.statFile(std.testing.io, "source.txt", .{}));
    try std.testing.expect(unit_cache.statusIs(std.testing.io, file, stamp));
    try fixture.write("source.txt", "second");
    try std.testing.expect(!unit_cache.statusIs(std.testing.io, file, stamp));
    try std.testing.expect(!unit_cache.statusIs(std.testing.io, try fixture.path("missing.txt"), stamp));
}

test "a file that was looked for and absent is a change when it appears" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    var handle = fixture.handle();
    try std.testing.expectEqual(@as(?Digest, null), try handle.digest(try fixture.path("header.h")));
    const sealed = (try handle.seal()).?;
    try std.testing.expect(try unchanged(fixture.live(), sealed));
    try fixture.write("header.h", "#define X 1\n");
    try std.testing.expect(!try unchanged(fixture.live(), sealed));
    var present = fixture.handle();
    try std.testing.expect((try present.digest(try fixture.path("header.h"))) != null);
    const kept = (try present.seal()).?;
    try fixture.temporary.dir.deleteFile(std.testing.io, "header.h");
    try std.testing.expect(!try unchanged(fixture.live(), kept));
}

test "an existence input changes with the path appearing or going and ignores its bytes" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    var handle = fixture.handle();
    try std.testing.expect(!try handle.exists(try fixture.path("probe")));
    const absent = (try handle.seal()).?;
    try std.testing.expect(try unchanged(fixture.live(), absent));
    try fixture.write("probe", "one");
    try std.testing.expect(!try unchanged(fixture.live(), absent));
    var seen = fixture.handle();
    try std.testing.expect(try seen.exists(try fixture.path("probe")));
    const present = (try seen.seal()).?;
    try fixture.write("probe", "two, longer");
    try std.testing.expect(try unchanged(fixture.live(), present));
    try fixture.temporary.dir.deleteFile(std.testing.io, "probe");
    try std.testing.expect(!try unchanged(fixture.live(), present));
}

test "a listing input sees names appear and go, and a filter keeps it blind to the rest" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    try fixture.write("main.selka", "");
    var handle = fixture.handle();
    const shadowed = try handle.listing(fixture.root, .standard_modules);
    try std.testing.expectEqual(@as(usize, 0), shadowed.len);
    const everything = try handle.listing(fixture.root, .all);
    try std.testing.expectEqual(@as(usize, 1), everything.len);
    const sealed = (try handle.seal()).?;
    try std.testing.expectEqual(@as(usize, 2), sealed.len);
    try std.testing.expect(try unchanged(fixture.live(), sealed));
    // A file no standard module is named like changes the full listing only.
    var narrow = fixture.handle();
    _ = try narrow.listing(fixture.root, .standard_modules);
    const filtered = (try narrow.seal()).?;
    try fixture.write("helpers.selka", "");
    try std.testing.expect(try unchanged(fixture.live(), filtered));
    try std.testing.expect(!try unchanged(fixture.live(), sealed));
    // A local file named like a standard module changes both.
    try fixture.write("strings.selka", "");
    try std.testing.expect(!try unchanged(fixture.live(), filtered));
    var after = fixture.handle();
    try std.testing.expectEqual(@as(usize, 1), (try after.listing(fixture.root, .standard_modules)).len);
    const shadow_record = (try after.seal()).?;
    try fixture.temporary.dir.deleteFile(std.testing.io, "strings.selka");
    try std.testing.expect(!try unchanged(fixture.live(), shadow_record));
    var gone = fixture.handle();
    try std.testing.expectEqual(@as(usize, 0), (try gone.listing(try fixture.path("no-such-directory"), .all)).len);
    const missing = (try gone.seal()).?;
    try std.testing.expect(try unchanged(fixture.live(), missing));
    try fixture.temporary.dir.createDirPath(std.testing.io, "no-such-directory");
    try std.testing.expect(!try unchanged(fixture.live(), missing));
}

test "a variable input compares the value and the absence" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    try fixture.environment.put("SOURCE_DATE_EPOCH", "1");
    var handle = fixture.handle();
    try std.testing.expectEqualStrings("1", (try handle.variable("SOURCE_DATE_EPOCH")).?);
    try std.testing.expectEqual(@as(?[]const u8, null), try handle.variable("ZERO_AR_DATE"));
    const sealed = (try handle.seal()).?;
    try std.testing.expect(try unchanged(fixture.live(), sealed));
    try fixture.environment.put("SOURCE_DATE_EPOCH", "2");
    try std.testing.expect(!try unchanged(fixture.live(), sealed));
    try fixture.environment.put("SOURCE_DATE_EPOCH", "1");
    try fixture.environment.put("ZERO_AR_DATE", "1");
    try std.testing.expect(!try unchanged(fixture.live(), sealed));
}

test "keyedEnvironment holds the contract's keyed variables and nothing a terminal or a placement sets" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    try fixture.environment.put("TERM", "xterm");
    try fixture.environment.put("COLUMNS", "80");
    try fixture.environment.put("LANG", "C");
    try fixture.environment.put("PATH", "/bin");
    try fixture.environment.put("SELKA_JOBS", "4");
    try fixture.environment.put("SELKA_CORE_SANITIZE", "address");
    try fixture.environment.put("SOURCE_DATE_EPOCH", "7");
    var handle = fixture.handle();
    const keyed = try handle.keyedEnvironment();
    try std.testing.expectEqual(@as(usize, 2), keyed.len);
    try std.testing.expectEqualStrings("SELKA_CORE_SANITIZE", keyed[0].name);
    try std.testing.expectEqualStrings("SOURCE_DATE_EPOCH", keyed[1].name);
    try std.testing.expectEqual(@as(usize, 2), handle.inputs().len);
}

test "a path read twice with different bytes leaves the step without a record" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    try fixture.write("source.txt", "first");
    var handle = fixture.handle();
    const file = try fixture.path("source.txt");
    try handle.pin(file, "first");
    try handle.pin(file, "first");
    try std.testing.expectEqual(@as(usize, 1), handle.inputs().len);
    try std.testing.expect((try handle.seal()) != null);
    try handle.pin(file, "second");
    try std.testing.expect(handle.torn);
    try std.testing.expectEqual(@as(?[]const Input, null), try handle.seal());
    // Bytes that no longer match the disk cannot be sealed either.
    var stale = fixture.handle();
    try stale.pin(file, "not what is on disk");
    try std.testing.expectEqual(@as(?[]const Input, null), try stale.seal());
}

test "a record survives its stored form and refuses damaged ones" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    const a = fixture.arena.allocator();
    try fixture.write("main.c", "int x;");
    try fixture.environment.put("SOURCE_DATE_EPOCH", "9");
    var handle = fixture.handle();
    _ = try handle.read(try fixture.path("main.c"), 1 << 20);
    _ = try handle.digest(try fixture.path("main.h"));
    _ = try handle.exists(fixture.root);
    _ = try handle.listing(fixture.root, .standard_modules);
    _ = try handle.variable("SOURCE_DATE_EPOCH");
    _ = try handle.variable("ZERO_AR_DATE");
    const sealed = (try handle.seal()).?;
    const text = try manifest(a, sealed);
    try std.testing.expectEqualStrings(text, try manifest(a, sealed));
    const parsed = (try parseManifest(a, text)).?;
    try std.testing.expectEqual(sealed.len, parsed.len);
    try std.testing.expect(try unchanged(fixture.live(), parsed));
    try std.testing.expectEqualStrings(text, try manifest(a, parsed));
    // The identity ignores the status tuples, and moves with any observation.
    try std.testing.expectEqual(identityDigest(sealed), identityDigest(parsed));
    var stampless = try a.dupe(Input, sealed);
    stampless[0].file.stamp = null;
    try std.testing.expectEqual(identityDigest(sealed), identityDigest(stampless));
    stampless[0].file.digest = @splat(1);
    try std.testing.expect(!std.mem.eql(u8, &identityDigest(sealed), &identityDigest(stampless)));
    try std.testing.expectEqual(@as(?[]const Input, null), try parseManifest(a, text[0 .. text.len - 1]));
    try std.testing.expectEqual(@as(?[]const Input, null), try parseManifest(a, "[{\"kind\":\"file\",\"name\":\"x\",\"digest\":\"short\"}]"));
    try std.testing.expectEqual(@as(?[]const Input, null), try parseManifest(a, "[{\"kind\":\"exists\",\"name\":\"x\"}]"));
    try std.testing.expectEqual(@as(?[]const Input, null), try parseManifest(a, "[{\"kind\":\"listing\",\"name\":\"x\"}]"));
    try std.testing.expectEqual(@as(?[]const Input, null), try parseManifest(a, "not json"));
}

test "a record is checked against what the handle has just seen of its directories and variables, not read again" {
    const fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit(std.testing.allocator);
    try fixture.environment.put("SOURCE_DATE_EPOCH", "1");
    var recorder = fixture.handle();
    _ = try recorder.listing(fixture.root, .standard_modules);
    _ = try recorder.variable("SOURCE_DATE_EPOCH");
    try recorder.pin(try fixture.path("main.selka"), "bytes");
    const sealed = recorder.inputs();
    // The directory and the variable change, but the handle below has already looked: its notes decide.
    try fixture.write("strings.selka", "");
    try fixture.environment.put("SOURCE_DATE_EPOCH", "2");
    var looked = fixture.handle();
    _ = try looked.listing(fixture.root, .standard_modules);
    _ = try looked.variable("SOURCE_DATE_EPOCH");
    var live = fixture.live();
    live.observed = &looked;
    const listing_and_variable = sealed[0..2];
    try std.testing.expect(!try unchanged(live, listing_and_variable));
    // Looked at the old state, the same notes agree with the record.
    try fixture.temporary.dir.deleteFile(std.testing.io, "strings.selka");
    try fixture.environment.put("SOURCE_DATE_EPOCH", "1");
    var before = fixture.handle();
    _ = try before.listing(fixture.root, .standard_modules);
    _ = try before.variable("SOURCE_DATE_EPOCH");
    try fixture.write("strings.selka", "");
    try fixture.environment.put("SOURCE_DATE_EPOCH", "2");
    live.observed = &before;
    try std.testing.expect(try unchanged(live, listing_and_variable));
    // A file is never answered from notes.
    try std.testing.expectEqual(@as(?Input, null), looked.observation(sealed[2]));
    try std.testing.expect(looked.observation(sealed[0]) != null);
}
