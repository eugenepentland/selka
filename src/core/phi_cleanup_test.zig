//! Exact phi identity, ownership escape, and bounded graph work.
const std = @import("std");
const ir = @import("ir.zig");
const cleanup = @import("phi_cleanup.zig");
const support = @import("test_support.zig");
const verify = @import("verify_ir.zig");

const Graph = struct {
    a: std.mem.Allocator,
    f: ir.Function = .{ .name = "graph", .signature = .{ .params = &.{}, .ret = .i64 } },

    fn add(self: *Graph, inst: ir.Inst) !ir.Ref {
        const ref: ir.Ref = @fromBackingInt(@as(u32, @intCast(self.f.insts.items.len)));
        try self.f.insts.append(self.a, inst);
        return ref;
    }

    fn phi(self: *Graph) !ir.Ref {
        return self.add(.{ .op = .phi, .ty = .i64 });
    }

    fn inputs(self: *Graph, node: ir.Ref, values: []const ir.Ref) !void {
        const start: u32 = @intCast(self.f.extra.items.len);
        try self.f.extra.appendSlice(self.a, values);
        self.f.insts.items[node.index()].data = (ir.ExtraSlice{ .start = start, .len = @intCast(values.len) }).pack();
    }
};

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC phi cleanup collapses exact cycles and preserves ambiguous identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var g: Graph = .{ .a = arena.allocator() };
    const a = try g.add(.{ .op = .iconst, .ty = .i64, .data = 7 });
    const b = try g.add(.{ .op = .iconst, .ty = .i64, .data = 7 });
    const direct = try g.phi();
    const left = try g.phi();
    const right = try g.phi();
    const ambiguous_left = try g.phi();
    const ambiguous_right = try g.phi();
    const no_entry = try g.phi();
    try g.inputs(direct, &.{ a, direct, a });
    try g.inputs(left, &.{ a, right });
    try g.inputs(right, &.{ left, direct });
    try g.inputs(ambiguous_left, &.{ a, ambiguous_right });
    try g.inputs(ambiguous_right, &.{ b, ambiguous_left });
    try g.inputs(no_entry, &.{no_entry});
    const stats = try cleanup.run(std.testing.allocator, &g.f);
    try std.testing.expectEqual(@as(usize, 3), stats.rewritten);
    const Expected = struct { ref: ir.Ref, value: ir.Ref, op: ir.Op };
    for ([_]Expected{
        .{ .ref = direct, .value = a, .op = .copy },
        .{ .ref = left, .value = a, .op = .copy },
        .{ .ref = right, .value = a, .op = .copy },
        .{ .ref = ambiguous_left, .value = ambiguous_left, .op = .phi },
        .{ .ref = ambiguous_right, .value = ambiguous_right, .op = .phi },
        .{ .ref = no_entry, .value = no_entry, .op = .phi },
    }) |expected| {
        try std.testing.expectEqual(expected.op, g.f.inst(expected.ref).op);
        try std.testing.expectEqual(expected.value, g.f.resolve(expected.ref));
    }
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC phi cleanup has linear edge work for deep cycles and copy chains" {
    for ([_]usize{ 16, 4096, 16384 }) |count| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var g: Graph = .{ .a = arena.allocator() };
        const value = try g.add(.{ .op = .iconst, .ty = .i64, .data = 9 });
        var alias = value;
        for (0..count) |_| alias = try g.add(.{ .op = .copy, .ty = .i64, .a = alias });
        const phis = try g.a.alloc(ir.Ref, count);
        for (phis) |*phi| phi.* = try g.phi();
        for (phis, 0..) |phi, i| try g.inputs(phi, &.{ alias, phis[(i + 1) % count] });
        const stats = try cleanup.run(std.testing.allocator, &g.f);
        try std.testing.expectEqual(count, stats.phis);
        try std.testing.expectEqual(count, stats.copies);
        try std.testing.expectEqual(count, stats.rewritten);
        try std.testing.expectEqual(4 * count, stats.edges);
        for (phis) |phi| try std.testing.expectEqual(value, g.f.resolve(phi));
    }
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC phi cleanup leaves malformed forwarding cycles untouched" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var g: Graph = .{ .a = arena.allocator() };
    const alias = try g.add(.{ .op = .copy, .ty = .i64 });
    g.f.insts.items[alias.index()].a = alias;
    const phi = try g.phi();
    try g.inputs(phi, &.{ alias, phi });
    try std.testing.expectEqual(@as(usize, 0), (try cleanup.run(std.testing.allocator, &g.f)).rewritten);
    try std.testing.expectEqual(ir.Op.phi, g.f.inst(phi).op);
}

fn irreducible(a: std.mem.Allocator, distinct_dead_edge: bool) !ir.Module {
    var module: ir.Module = .{ .single_owner = true, .zero_rc = true };
    const list = try module.intern(a, .{ .list = .i64 });
    var h = try support.Hand.init(a, &module, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const first = try h.emit(.{ .op = .list_new, .ty = list, .a = try h.int(.u64, 1) });
    const value = try h.emit(.{ .op = .list_push, .ty = list, .a = first, .b = try h.int(.i64, 42) });
    const other = if (distinct_dead_edge) try h.emit(.{ .op = .list_copy, .ty = list, .a = value }) else value;
    const left = try h.newBlock();
    const right = try h.newBlock();
    const exit = try h.newBlock();
    try h.branch(try h.int(.bool, 1), left, right);
    h.block = left;
    const p = try h.emit(.{ .op = .phi, .ty = list });
    try h.branch(try h.int(.bool, 0), right, exit);
    h.block = right;
    const q = try h.emit(.{ .op = .phi, .ty = list, .data = try h.extra(&.{ other, p }) });
    try h.branch(try h.int(.bool, 0), left, exit);
    h.function.insts.items[p.index()].data = try h.extra(&.{ value, q });
    h.block = exit;
    const output = try h.emit(.{ .op = .phi, .ty = list, .data = try h.extra(&.{ p, q }) });
    const element = try h.emit(.{ .op = .list_get, .ty = .i64, .a = output, .b = try h.int(.u64, 0) });
    try h.printValues(try h.param(0), &.{element});
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return module;
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC phi cleanup preserves dead-edge ambiguity and escaping owned storage" {
    for ([_]bool{ false, true }) |distinct| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var module = try irreducible(a, distinct);
        var failure: verify.Failure = .{};
        try verify.verifyModule(a, &module, &failure);
        const stats = try cleanup.run(std.testing.allocator, &module.functions.items[0]);
        try std.testing.expectEqual(@as(usize, if (distinct) 0 else 3), stats.rewritten);
        try verify.verifyModule(a, &module, &failure);
        if (distinct) continue;
        const result = try support.runOwned(a, &module, .{});
        try std.testing.expectEqual(@as(u8, 0), result.status);
        try std.testing.expectEqualStrings("42\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        try std.testing.expect(@import("zero_rc.zig").emittedClean(result.llvm));
    }
}
