//! Per-test receipt keys derived from one lowering of every ready test of a program
//! (NEW-CORE-TEST-KEYS-1). Each function gets a canonical digest: what it means, not
//! where the shared lowering placed it or its types and strings. A test's key hashes
//! the digests of the functions it reaches, so it changes exactly when they do.
const std = @import("std");
const ir = @import("ir.zig");
const emit_llvm = @import("emit_llvm.zig");

/// A function digest or a receipt key.
pub const Digest = canonical.Digest;
/// Allocation, or lowering metadata this module does not recognize; on the latter the
/// caller keys each test from its own lowering instead.
pub const Error = canonical.Error;

const equal_prefix = @import("emit_values.zig").equal_prefix;
const canonical = @import("canonical_ir.zig");
const Canon = canonical.Canon;

/// One shared lowering's canonical function digests and call graph.
pub const Shared = struct {
    digests: []const Digest,
    callees: []const []const u32,

    /// Digest every function of `module` (before passes and before the test entry is
    /// added) and record whom each one calls or takes the address of. Everything is
    /// allocated in the caller's arena `a`.
    pub fn build(a: std.mem.Allocator, module: *const ir.Module, locator: emit_llvm.Locator) Error!Shared {
        var canon = try Canon.prepare(a, module, locator);
        const digests = try a.alloc(Digest, module.functions.items.len);
        const callees = try a.alloc([]const u32, module.functions.items.len);
        for (module.functions.items, digests, callees, 0..) |function, *digest, *targets, index| {
            digest.* = try canon.functionDigest(@intCast(index));
            targets.* = try calls(a, function);
            for (targets.*) |target| if (target >= digests.len) return error.UnknownMetadata;
        }
        return .{ .digests = digests, .callees = callees };
    }

    /// Feed `hash` the digests of `roots`, in order, and then of every other function
    /// they reach, sorted, so the key does not depend on the shared module's order.
    pub fn reach(self: Shared, a: std.mem.Allocator, roots: []const u32, hash: *std.crypto.hash.Blake3) Error!void {
        if (self.callees.len != self.digests.len) return error.UnknownMetadata;
        const seen = try a.alloc(bool, self.digests.len);
        @memset(seen, false);
        var queue: std.ArrayList(u32) = .empty;
        for (roots) |root| {
            if (root >= self.digests.len) return error.UnknownMetadata;
            hash.update(&self.digests[root]);
            if (seen[root]) continue;
            seen[root] = true;
            try queue.append(a, root);
        }
        var reached: std.ArrayList(Digest) = .empty;
        var next: usize = 0;
        while (next < queue.items.len) : (next += 1) {
            for (self.callees[queue.items[next]]) |callee| {
                if (callee >= self.digests.len) return error.UnknownMetadata;
                if (seen[callee]) continue;
                seen[callee] = true;
                try queue.append(a, callee);
                try reached.append(a, self.digests[callee]);
            }
        }
        std.mem.sort(Digest, reached.items, {}, before);
        put(hash, u64, reached.items.len);
        for (reached.items) |digest| hash.update(&digest);
    }
};

/// What a test's key binds besides the functions it reaches: the run's settings, the
/// test, its entry's inputs, the type schema when its entry generates or encodes
/// values, and its roots in the shared lowering (the test, then its invariants).
pub const Test = struct { base: Digest, name: []const u8, source_path: []const u8, entry: Digest, schema: ?Digest, roots: []const u32 };

/// A test's receipt key from the shared lowering.
pub fn key(shared: Shared, a: std.mem.Allocator, t: Test) Error!Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    text(&hash, "core-test-keys-v1");
    hash.update(&t.base);
    text(&hash, t.name);
    text(&hash, @import("native_artifact.zig").extension);
    text(&hash, t.source_path);
    hash.update(&t.entry);
    put(&hash, u8, @intFromBool(t.schema != null));
    if (t.schema) |schema| hash.update(&schema);
    try shared.reach(a, t.roots, &hash);
    return final(&hash);
}

/// Hash a verified planner's non-root closure using the established key contract.
/// Roots contribute in their original order, including repeats; equal non-root
/// digests remain separate contributions when they belong to distinct functions.
pub fn plannedKey(shared: Shared, t: Test, reached: []const u32) Error!Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    text(&hash, "core-test-keys-v1");
    hash.update(&t.base);
    text(&hash, t.name);
    text(&hash, @import("native_artifact.zig").extension);
    text(&hash, t.source_path);
    hash.update(&t.entry);
    put(&hash, u8, @intFromBool(t.schema != null));
    if (t.schema) |schema| hash.update(&schema);
    for (t.roots) |root| {
        if (root >= shared.digests.len) return error.UnknownMetadata;
        hash.update(&shared.digests[root]);
    }
    put(&hash, u64, reached.len);
    for (reached) |node| {
        if (node >= shared.digests.len) return error.UnknownMetadata;
        hash.update(&shared.digests[node]);
    }
    return final(&hash);
}

fn before(_: void, left: Digest, right: Digest) bool {
    return std.mem.order(u8, &left, &right) == .lt;
}

/// The distinct functions `function` calls directly or takes the address of.
fn calls(a: std.mem.Allocator, function: ir.Function) Error![]const u32 {
    var targets: std.ArrayList(u32) = .empty;
    for (function.insts.items) |inst| {
        const target: u32 = switch (inst.op) {
            .call => @intCast(inst.a.index()),
            .func_ref => @intCast(inst.data),
            else => continue,
        };
        if (std.mem.indexOfScalar(u32, targets.items, target) == null) try targets.append(a, target);
    }
    return targets.items;
}

fn put(hash: *std.crypto.hash.Blake3, comptime T: type, value: T) void {
    var encoded: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &encoded, value, .little);
    hash.update(&encoded);
}

fn text(hash: *std.crypto.hash.Blake3, bytes: []const u8) void {
    put(hash, u64, bytes.len);
    hash.update(bytes);
}

fn final(hash: *std.crypto.hash.Blake3) Digest {
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

const Lines = struct {
    fn locate(_: *const anyopaque, offset: u32) emit_llvm.Location {
        return .{ .line = offset / 100 + 1, .column = offset % 100 + 1, .path = "app.my" };
    }
};
const lines: u8 = 0;
const test_locator: emit_llvm.Locator = .{ .context = &lines, .locate = Lines.locate };

/// A caller that calls `callee`, reads string `text` and makes a value of type `ty`.
fn caller(a: std.mem.Allocator, callee: u32, text_index: u64, ty: ir.Type) !ir.Function {
    var function: ir.Function = .{ .name = "app::test_one", .signature = .{ .params = &.{}, .ret = .bool }, .span = 100 };
    try function.insts.append(a, .{ .op = .call, .ty = .i64, .a = @fromBackingInt(callee), .span = 110 });
    try function.insts.append(a, .{ .op = .str_const, .ty = .str, .data = text_index, .span = 120 });
    try function.insts.append(a, .{ .op = .undef, .ty = ty, .span = 130 });
    return function;
}

fn helper(a: std.mem.Allocator, value: u64) !ir.Function {
    var function: ir.Function = .{ .name = "app::helper", .signature = .{ .params = &.{}, .ret = .i64 }, .span = 200 };
    try function.insts.append(a, .{ .op = .iconst, .ty = .i64, .data = value, .span = 210 });
    return function;
}

/// The key of root 0 or `root` in `module`, over what it reaches.
fn keyOf(a: std.mem.Allocator, module: *const ir.Module, root: u32) !Digest {
    const shared = try Shared.build(a, module, test_locator);
    return key(shared, a, .{ .base = @splat(1), .name = "app::test_one", .source_path = "app.my", .entry = @splat(2), .schema = null, .roots = &.{root} });
}

// spec: NEW-CORE-TEST-KEYS-1
test "a test's derived key names callees, types and strings by meaning, not by where the shared lowering put them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const list_first: ir.Type = @fromBackingInt(ir.Type.first_compound);
    const list_second: ir.Type = @fromBackingInt(ir.Type.first_compound + 1);
    var first: ir.Module = .{};
    try first.compounds.append(a, .{ .list = .i64 });
    try first.strings.appendSlice(a, &.{ "unused", "hi" });
    try first.functions.appendSlice(a, &.{ try caller(a, 1, 1, list_first), try helper(a, 3) });
    var second: ir.Module = .{};
    try second.compounds.appendSlice(a, &.{ .{ .box = .i64 }, .{ .list = .i64 } });
    try second.strings.append(a, "hi");
    try second.functions.appendSlice(a, &.{ try helper(a, 3), .{ .name = "app::other", .signature = .{ .params = &.{}, .ret = .void } }, try caller(a, 0, 0, list_second) });
    const one = try keyOf(a, &first, 0);
    try std.testing.expectEqualSlices(u8, &one, &try keyOf(a, &second, 2));
    second.functions.items[1] = try helper(a, 9);
    second.functions.items[1].name = "app::other";
    try std.testing.expectEqualSlices(u8, &one, &try keyOf(a, &second, 2));
    second.functions.items[0] = try helper(a, 4);
    try std.testing.expect(!std.mem.eql(u8, &one, &try keyOf(a, &second, 2)));
    second.functions.items[0] = try helper(a, 3);
    second.strings.items[0] = "ho";
    try std.testing.expect(!std.mem.eql(u8, &one, &try keyOf(a, &second, 2)));
    second.strings.items[0] = "hi";
    second.compounds.items[1] = .{ .list = .i32 };
    try std.testing.expect(!std.mem.eql(u8, &one, &try keyOf(a, &second, 2)));
}

// spec-case: NEW-CORE-TEST-KEYS-1
test "recursive types digest by structure, equality adapters by the type they compare, and unknown render metadata is refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const c0: ir.Type = @fromBackingInt(ir.Type.first_compound);
    const c1: ir.Type = @fromBackingInt(ir.Type.first_compound + 1);
    var tree: ir.Module = .{};
    try tree.compounds.appendSlice(a, &.{ .{ .@"union" = &.{ .i64, c1 } }, .{ .box = c0 } });
    try tree.strings.append(a, "hi");
    const equal_first = equal_prefix ++ std.fmt.comptimePrint("{d}", .{ir.Type.first_compound});
    try tree.functions.appendSlice(a, &.{ try caller(a, 1, 0, c0), .{ .name = equal_first, .signature = .{ .params = &.{ c1, c1 }, .ret = .bool, .linkage = .runtime_c } } });
    var swapped: ir.Module = .{};
    try swapped.compounds.appendSlice(a, &.{ .{ .box = c1 }, .{ .@"union" = &.{ .i64, c0 } } });
    try swapped.strings.append(a, "hi");
    const equal_second = equal_prefix ++ std.fmt.comptimePrint("{d}", .{ir.Type.first_compound + 1});
    try swapped.functions.appendSlice(a, &.{ try caller(a, 1, 0, c1), .{ .name = equal_second, .signature = .{ .params = &.{ c0, c0 }, .ret = .bool, .linkage = .runtime_c } } });
    try std.testing.expectEqualSlices(u8, &try keyOf(a, &tree, 0), &try keyOf(a, &swapped, 0));
    tree.functions.items[1].name = "myl_core_show_7";
    try std.testing.expectError(error.UnknownMetadata, keyOf(a, &tree, 0));
}

// spec: NEW-CORE-TEST-KEYS-2
test "a loop's program-wide checker id is outside both kinds of test key; its blocks are inside" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    try module.strings.append(a, "hi");
    var looped = try caller(a, 1, 0, .i64);
    try looped.loops.append(a, .{ .id = 625, .header = @fromBackingInt(0), .body = @fromBackingInt(1), .latch = @fromBackingInt(2), .exit = @fromBackingInt(3) });
    try module.functions.appendSlice(a, &.{ looped, try helper(a, 3) });
    const receipt = @import("test_runner_receipt.zig");
    const program: receipt.Program = .{ .module = &module, .source_path = "app.my", .locator = test_locator };
    const derived = try keyOf(a, &module, 0);
    const whole = receipt.programKey(@splat(1), "app::test_one", program);
    module.functions.items[0].loops.items[0].id = 631;
    try std.testing.expectEqualSlices(u8, &derived, &try keyOf(a, &module, 0));
    try std.testing.expectEqualSlices(u8, &whole, &receipt.programKey(@splat(1), "app::test_one", program));
    module.functions.items[0].loops.items[0].latch = @fromBackingInt(1);
    try std.testing.expect(!std.mem.eql(u8, &derived, &try keyOf(a, &module, 0)));
    try std.testing.expect(!std.mem.eql(u8, &whole, &receipt.programKey(@splat(1), "app::test_one", program)));
}

// spec-case: SELFHOST-CACHE-PLAN-1
test "planned receipt contribution preserves repeated roots cycles and equal nonroot digests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const shared: Shared = .{ .digests = &.{ @splat(5), @splat(7), @splat(7), @splat(9) }, .callees = &.{ &.{ 1, 2 }, &.{0}, &.{1}, &.{} } };
    const t: Test = .{ .base = @splat(1), .name = "app::test", .source_path = "app.my", .entry = @splat(2), .schema = @splat(3), .roots = &.{ 0, 0 } };
    const expected = try key(shared, a, t);
    try std.testing.expectEqual(expected, try plannedKey(shared, t, &.{ 1, 2 }));
    try std.testing.expect(!std.mem.eql(u8, &expected, &try plannedKey(shared, t, &.{1})));
    var reordered = t;
    reordered.roots = &.{ 1, 0 };
    try std.testing.expectEqual(try key(shared, a, reordered), try plannedKey(shared, reordered, &.{2}));
    reordered.roots = &.{ 0, 1 };
    try std.testing.expect(!std.mem.eql(u8, &try key(shared, a, reordered), &try plannedKey(shared, t, &.{ 1, 2 })));
    try std.testing.expectError(error.UnknownMetadata, plannedKey(shared, t, &.{4}));
}
