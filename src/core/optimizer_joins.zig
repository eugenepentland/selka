//! The joins of a program state (part 2, G3p (d), D-G3p-17): what the optimizer's whole-program passes made of every function's
//! stored contribution, kept beside the state so that a build whose recomputed functions contribute what they contributed before
//! need not read the contributions of the others.
//!
//! The field rounds visit every function in callees-first order. Each function adds its writes to a table of record-field
//! intervals (the table of one round is the input of the next), its call sites to the parameter hull of every callee, and its
//! return interval to the dependency digest of its callers. The table, the hulls and the return intervals are joins over all
//! functions: when no function that was recomputed in a build contributes anything different from what its stored row held,
//! each join is the one the stored rows made, and the stored rows of the functions left alone need not be decoded.
//!
//! A `Joins` is the result of those joins for one set of stored rows. It is a content-addressed record of its own, named by
//! the manifest of the state (`optimizer_shortcut.DemandManifest.joins`), so an edit that changes no join writes nothing.
const std = @import("std");
const facts = @import("facts.zig");
const fields = @import("fields.zig");
const fast_blake3 = @import("fast_blake3.zig");
const stage = @import("stage_store.zig");
const codec = @import("selka").persist_codec;

/// The scope of the joins records: keyed by the digest of the record's bytes.
pub const scope = "optimizer-joins-v1";

/// The record-field table at the end of one field round and the digest the dependency inputs of the next round are built from.
pub const Table = struct { digest: [32]u8, types: []const ?[]const ?facts.Interval };

/// The joins of one state, indexed like the function table.
pub const Joins = struct {
    /// The field tables at the end of round 0 and round 1.
    tables: [2]Table,
    /// Each function's return interval as the round left it, after round 0 and after round 1.
    returns: [2][]const ?facts.Interval,
    /// Each function's parameter hull from the call sites of round 1.
    hulls: []const []const ?facts.Interval,
};

/// The key a joins record with digest `digest` is stored under.
pub fn keyOf(storage: *const stage.Store, digest: [32]u8) [32]u8 {
    return storage.key(scope, &.{&digest});
}

/// The bytes of `joins` and their digest, which names the record.
pub fn encode(a: std.mem.Allocator, joins: Joins) std.mem.Allocator.Error!struct { bytes: []const u8, digest: [32]u8 } {
    var writer = codec.Writer.init(a);
    try writer.write(Joins, joins);
    var digest: [32]u8 = undefined;
    fast_blake3.hash(writer.bytes.items, &digest);
    return .{ .bytes = writer.bytes.items, .digest = digest };
}

/// The joins record `digest` names for a program of `count` functions, or null when the store lacks it, it does not decode, or it
/// describes another number of functions.
pub fn load(a: std.mem.Allocator, storage: *const stage.Store, digest: [32]u8, count: usize) std.mem.Allocator.Error!?Joins {
    const bytes = try storage.load(a, keyOf(storage, digest)) orelse return null;
    var reader = codec.Reader.init(a, bytes);
    const joins = reader.read(Joins) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    if (!reader.done()) return null;
    if (joins.returns[0].len != count or joins.returns[1].len != count or joins.hulls.len != count) return null;
    return joins;
}

/// Whether two exploratory contributions are the same evidence: the same writes, opened types and escaping functions.
pub fn sameContribution(left: fields.Contribution, right: fields.Contribution) bool {
    if (left.writes.len != right.writes.len or left.opens.len != right.opens.len or left.references.len != right.references.len) return false;
    for (left.writes, right.writes) |a, b| if (!std.meta.eql(a, b)) return false;
    for (left.opens, right.opens) |a, b| if (a != b) return false;
    return std.mem.eql(u32, left.references, right.references);
}

/// Whether two summaries' call sites contribute the same argument intervals to the same callees, in the same order.
pub fn sameCalls(left: []const @import("optimization_cache.zig").Call, right: []const @import("optimization_cache.zig").Call) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (a.callee != b.callee or a.ranges.len != b.ranges.len) return false;
        for (a.ranges, b.ranges) |x, y| if (!std.meta.eql(x, y)) return false;
    }
    return true;
}

/// Whether two lists name the same functions once duplicates and order are ignored: what an address-taken test reads.
pub fn sameSet(a: std.mem.Allocator, left: []const u32, right: []const u32) std.mem.Allocator.Error!bool {
    if (std.mem.eql(u32, left, right)) return true;
    const sorted = try a.alloc(u32, left.len + right.len);
    defer a.free(sorted);
    @memcpy(sorted[0..left.len], left);
    @memcpy(sorted[left.len..], right);
    std.mem.sort(u32, sorted[0..left.len], {}, std.sort.asc(u32));
    std.mem.sort(u32, sorted[left.len..], {}, std.sort.asc(u32));
    return subsetOf(sorted[0..left.len], sorted[left.len..]) and subsetOf(sorted[left.len..], sorted[0..left.len]);
}

fn subsetOf(small: []const u32, big: []const u32) bool {
    var at: usize = 0;
    for (small) |each| {
        while (at < big.len and big[at] < each) at += 1;
        if (at == big.len or big[at] != each) return false;
    }
    return true;
}

test "a joins record round trips through its bytes and is refused for another function count" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const hull_one = [_]?facts.Interval{ facts.Interval.point(3), null };
    const hulls = [_][]const ?facts.Interval{ &.{}, &hull_one };
    const returns = [_]?facts.Interval{ facts.Interval.point(1), null };
    const joins: Joins = .{
        .tables = .{ .{ .digest = @splat(1), .types = &.{} }, .{ .digest = @splat(2), .types = &.{null} } },
        .returns = .{ &returns, &returns },
        .hulls = &hulls,
    };
    const encoded = try encode(a, joins);
    const again = try encode(a, joins);
    try std.testing.expectEqual(encoded.digest, again.digest);
    var reader = codec.Reader.init(a, encoded.bytes);
    const decoded = try reader.read(Joins);
    try std.testing.expect(reader.done());
    try std.testing.expectEqual(@as(usize, 2), decoded.hulls.len);
    try std.testing.expectEqual(@as(?facts.Interval, facts.Interval.point(3)), decoded.hulls[1][0]);
    try std.testing.expectEqual(@as(u8, 2), decoded.tables[1].digest[0]);
}

test "contributions, call sites and reference lists compare by what they hold" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const write: fields.Write = .{ .record = @fromBackingInt(1), .field = 0, .range = facts.Interval.point(4) };
    const base: fields.Contribution = .{ .writes = &.{write}, .opens = &.{}, .references = &.{ 3, 1 } };
    var other = base;
    try std.testing.expect(sameContribution(base, other));
    other.references = &.{ 3, 2 };
    try std.testing.expect(!sameContribution(base, other));
    try std.testing.expect(try sameSet(a, &.{ 3, 1, 3 }, &.{ 1, 3 }));
    try std.testing.expect(!(try sameSet(a, &.{ 3, 1 }, &.{ 1, 4 })));
    const ranges = [_]?facts.Interval{facts.Interval.point(1)};
    const call: @import("optimization_cache.zig").Call = .{ .callee = 2, .ranges = &ranges };
    try std.testing.expect(sameCalls(&.{call}, &.{call}));
    try std.testing.expect(!sameCalls(&.{call}, &.{}));
}
