//! Generations of the optimizer's demand state. A build reads the demand state its entry and flags name under the current
//! generation, and writes a fresh one past the highest published; it publishes that generation as current once the state is
//! flushed. A replayed build publishes the generation its record names, so the next reader sees the state of the tree the
//! replay served rather than the tree last built. A pointer file names the current and the highest generation of one scope.
//! The highest one is the last full build's: a lookup consults it as a second candidate, and an entry is used only when its
//! own key matches (`optimizer_shortcut.zig`). Generations are hints: a missing or damaged pointer reads as generation 0, and
//! a state a reader does not find is a miss. Lowering and ownership receipts are not generational: each is a record keyed by
//! its own inputs, so no pointer names them.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const stage = @import("stage_store.zig");
const unit_cache = @import("unit_cache.zig");

/// The generations of one scope: the one its readers use, and the highest one ever published.
pub const Pointer = struct { current: u64 = 0, high: u64 = 0 };

/// One scope of demand generations: the entry and the flags it is built with, under the cache directory `cache`.
pub const Scope = struct { cache: []const u8, entry: []const u8, flags: []const u8 };

const header = "selka-demand-generation-v3";

/// The demand-state scope of `entry` built with `flags` under the cache directory `cache`.
pub fn demandScope(cache: []const u8, entry: []const u8, flags: []const u8) Scope {
    return .{ .cache = cache, .entry = entry, .flags = flags };
}

/// The generations a writer of `scope` reads (the current one), writes (past the highest published) and names as the
/// last full build's (the highest published one).
pub fn begin(a: std.mem.Allocator, io: std.Io, scope: Scope) std.mem.Allocator.Error!stage.Generations {
    const pointer = try read(a, io, scope);
    return .{ .read = pointer.current, .write = pointer.high + 1, .last = pointer.high };
}

/// Publish the generation a writer of `scope` wrote as the current one. Call it once that state is flushed.
pub fn publish(a: std.mem.Allocator, io: std.Io, scope: Scope, generations: stage.Generations) std.mem.Allocator.Error!void {
    const old = try read(a, io, scope);
    try write(a, io, scope, .{ .current = generations.write, .high = @max(old.high, generations.write) });
}

/// Make a replayed build's generation the current one of `scope`, so the next reader finds the state that build
/// wrote. Generation 0 names no state a build wrote, and an unchanged scope already names the generation: then
/// nothing is written.
pub fn adopt(a: std.mem.Allocator, io: std.Io, scope: Scope, generation: u64) std.mem.Allocator.Error!void {
    if (generation == 0) return;
    const old = try read(a, io, scope);
    if (old.current == generation) return;
    try write(a, io, scope, .{ .current = generation, .high = @max(old.high, generation) });
}

/// The pointer of the scope; a missing or damaged file reads as the zero pointer.
fn read(a: std.mem.Allocator, io: std.Io, scope: Scope) std.mem.Allocator.Error!Pointer {
    const path = try pointerPath(a, scope);
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(256)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{};
    };
    return parse(bytes) orelse .{};
}

/// Replace the scope's pointer. A failed write keeps the old pointer, which costs a miss at most.
fn write(a: std.mem.Allocator, io: std.Io, scope: Scope, pointer: Pointer) std.mem.Allocator.Error!void {
    const path = try pointerPath(a, scope);
    const bytes = try std.fmt.allocPrint(a, "{s} {d} {d}\n", .{ header, pointer.current, pointer.high });
    const partial = try std.fmt.allocPrint(a, "{s}.partial", .{path});
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, std.fs.path.dirname(path).?) catch return;
    cwd.writeFile(io, .{ .sub_path = partial, .data = bytes }) catch return;
    cwd.rename(partial, cwd, path, io) catch return;
}

/// Parse the pointer file's header, current and high generations; anything else is null.
fn parse(bytes: []const u8) ?Pointer {
    var words = std.mem.tokenizeAny(u8, bytes, " \n");
    if (!std.mem.eql(u8, words.next() orelse return null, header)) return null;
    const current = std.fmt.parseInt(u64, words.next() orelse return null, 10) catch return null;
    const high = std.fmt.parseInt(u64, words.next() orelse return null, 10) catch return null;
    if (words.next() != null or high < current) return null;
    return .{ .current = current, .high = high };
}

/// The name of `scope`: the hex of its pointer file's digest. The manifests of its generations are named by it (`stage_roots.zig`).
pub fn scopeName(a: std.mem.Allocator, scope: Scope) std.mem.Allocator.Error![]const u8 {
    return std.fs.path.basename(try pointerPath(a, scope));
}

/// A scope the pointer directory names, with its pointer.
pub const Listed = struct { scope: []const u8, pointer: Pointer };

/// Every scope the pointer directory of `cache` names, with its pointer; a damaged pointer reads as the zero pointer.
pub fn listed(a: std.mem.Allocator, io: std.Io, cache: []const u8) std.mem.Allocator.Error![]const Listed {
    var found: std.ArrayList(Listed) = .empty;
    const directory = try std.fs.path.join(a, &.{ cache, "demand-generation-v3" });
    var dir = std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true }) catch return found.items;
    defer dir.close(io);
    var entries = dir.iterate();
    while (entries.next(io) catch return found.items) |entry| {
        if (entry.kind != .file or std.mem.endsWith(u8, entry.name, ".partial")) continue;
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, try std.fs.path.join(a, &.{ directory, entry.name }), a, .limited(256)) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            continue;
        };
        try found.append(a, .{ .scope = try a.dupe(u8, entry.name), .pointer = parse(bytes) orelse .{} });
    }
    return found.items;
}

/// The pointer file of `scope`: one file per entry and flags under the demand directory of the cache.
fn pointerPath(a: std.mem.Allocator, scope: Scope) std.mem.Allocator.Error![]const u8 {
    var hash = fast_blake3.Blake3.init(.{});
    unit_cache.field(&hash, header);
    unit_cache.field(&hash, scope.entry);
    unit_cache.field(&hash, scope.flags);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    const name: []const u8 = &hex;
    return std.fs.path.join(a, &.{ scope.cache, "demand-generation-v3", name });
}

test "a pointer round-trips and a damaged one reads as the zero pointer" {
    const parsed = parse("selka-demand-generation-v3 3 5\n") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 3), parsed.current);
    try std.testing.expectEqual(@as(u64, 5), parsed.high);
    try std.testing.expect(parse("selka-demand-generation-v3 4 3\n") == null);
    try std.testing.expect(parse("selka-demand-generation-v2 1 1\n") == null);
    try std.testing.expect(parse("selka-demand-generation-v3 1\n") == null);
}

test "a writer begins past the published generation, and a replay adopts the generation it names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const cache = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const scope = demandScope(cache, "src/main.selka", "");
    const first = try begin(a, std.testing.io, scope);
    try std.testing.expectEqual(@as(u64, 0), first.read);
    try std.testing.expectEqual(@as(u64, 1), first.write);
    try std.testing.expectEqual(@as(u64, 0), first.last);
    try publish(a, std.testing.io, scope, first);
    const second = try begin(a, std.testing.io, scope);
    try std.testing.expectEqual(@as(u64, 1), second.read);
    try std.testing.expectEqual(@as(u64, 2), second.write);
    try std.testing.expectEqual(@as(u64, 1), second.last);
    try publish(a, std.testing.io, scope, second);
    try adopt(a, std.testing.io, scope, 1);
    const after = try begin(a, std.testing.io, scope);
    try std.testing.expectEqual(@as(u64, 1), after.read);
    try std.testing.expectEqual(@as(u64, 3), after.write);
    try std.testing.expectEqual(@as(u64, 2), after.last);
}
