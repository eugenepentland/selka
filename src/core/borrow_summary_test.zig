//! Strict borrow-only call summaries: stack inputs must neither escape nor acquire
//! even a temporary owner when the callee's RC instructions are inserted.
const std = @import("std");
const ir = @import("ir.zig");
const effects = @import("effects.zig");
const Hand = @import("test_support.zig").Hand;

fn unary(a: std.mem.Allocator, module: *ir.Module, name: []const u8, list: ir.Type) !Hand {
    return Hand.init(a, module, name, .{ .params = try a.dupe(ir.Type, &.{list}), .ret = .u64 });
}

fn reader(a: std.mem.Allocator, module: *ir.Module, name: []const u8, list: ir.Type, op: ir.Op) !u32 {
    var h = try unary(a, module, name, list);
    const xs = try h.param(0);
    const alias = try h.emit(.{ .op = .copy, .ty = list, .a = xs });
    const ty: ir.Type = if (op == .list_len) .u64 else if (op == .list_get_field) .i64 else module.compound(list).list;
    h.function.signature.ret = ty;
    const value = try h.emit(.{
        .op = op,
        .ty = ty,
        .a = alias,
        .b = if (op == .list_len) .none else try h.int(.i64, 0),
        .data = if (op == .list_get_field) ir.FieldPath.init(&.{0}).?.pack() else 0,
    });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = value });
    return h.finish();
}

fn relay(a: std.mem.Allocator, module: *ir.Module, name: []const u8, list: ir.Type, target: u32) !u32 {
    var h = try unary(a, module, name, list);
    const xs = try h.param(0);
    const value = try h.emit(.{ .op = .call, .ty = .u64, .a = @fromBackingInt(target), .data = try h.extra(&.{xs}) });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = value });
    return h.finish();
}

// spec-case: NEW-CORE-STACK-2
test "borrow-only summaries admit resolved copies, scalar reads and unmanaged field reads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const ints = try module.intern(a, .{ .list = .i64 });
    const pair = try module.intern(a, .{ .record = try a.dupe(ir.Type, &.{ .i64, .bool }) });
    const pairs = try module.intern(a, .{ .list = pair });
    _ = try reader(a, &module, "length", ints, .list_len);
    _ = try reader(a, &module, "element", ints, .list_get);
    _ = try reader(a, &module, "field", pairs, .list_get_field);
    const summaries = try effects.analyze(a, &module);
    for (summaries.params) |params| {
        try std.testing.expect(params[0].borrow_only);
        // Reading values is compatible with borrowing; this is not an empty-read test.
        try std.testing.expect(params[0].reads.whole);
    }
}

// spec-case: NEW-CORE-STACK-2
test "borrow-only summaries revisit callers after a later leaf and relay are proved" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const ints = try module.intern(a, .{ .list = .i64 });
    _ = try relay(a, &module, "caller", ints, 1);
    _ = try relay(a, &module, "relay", ints, 2);
    _ = try reader(a, &module, "leaf", ints, .list_len);
    const summaries = try effects.analyze(a, &module);
    for (summaries.params) |params| try std.testing.expect(params[0].borrow_only);
}

fn twoArguments(a: std.mem.Allocator, module: *ir.Module, list: ir.Type, copies_second: bool) !void {
    var h = try Hand.init(a, module, "two", .{ .params = try a.dupe(ir.Type, &.{ list, list }), .ret = .u64 });
    const first = try h.param(0);
    const second = try h.param(1);
    const left = try h.emit(.{ .op = .list_len, .ty = .u64, .a = first });
    const source = if (copies_second) try h.emit(.{ .op = .list_copy, .ty = list, .a = second }) else second;
    const right = try h.emit(.{ .op = .list_len, .ty = .u64, .a = source });
    const total = try h.emit(.{ .op = .add, .ty = .u64, .a = left, .b = right });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = total });
    _ = try h.finish();
    var caller = try unary(a, module, "caller", list);
    const xs = try caller.param(0);
    const alias = try caller.emit(.{ .op = .copy, .ty = list, .a = xs });
    const called = try caller.emit(.{ .op = .call, .ty = .u64, .a = @fromBackingInt(0), .data = try caller.extra(&.{ xs, alias }) });
    _ = try caller.emit(.{ .op = .ret, .ty = .void, .a = called });
    _ = try caller.finish();
}

// spec-case: NEW-CORE-STACK-2
test "borrow-only forwarding checks every occurrence of a repeated argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]bool{ false, true }) |copies_second| {
        var module: ir.Module = .{};
        const ints = try module.intern(a, .{ .list = .i64 });
        try twoArguments(a, &module, ints, copies_second);
        const summaries = try effects.analyze(a, &module);
        try std.testing.expect(summaries.of(0, 0).borrow_only);
        try std.testing.expectEqual(!copies_second, summaries.of(0, 1).borrow_only);
        try std.testing.expectEqual(!copies_second, summaries.of(1, 0).borrow_only);
    }
}

fn forbiddenUse(a: std.mem.Allocator, module: *ir.Module, list: ir.Type, op: ir.Op) !u32 {
    var h = try unary(a, module, @tagName(op), list);
    const xs = try h.param(0);
    const length = try h.emit(.{ .op = .list_len, .ty = .u64, .a = xs });
    const ty: ir.Type = switch (op) {
        .retain, .release => .void,
        .is_unique => .bool,
        else => list,
    };
    _ = try h.emit(.{ .op = op, .ty = ty, .a = xs, .b = if (op == .list_push) try h.int(.i64, 1) else .none });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = length });
    return h.finish();
}

fn forbiddenUses(a: std.mem.Allocator, module: *ir.Module, list: ir.Type) !void {
    for ([_]ir.Op{ .retain, .release, .is_unique, .list_copy, .list_push }) |op| _ = try forbiddenUse(a, module, list, op);
}

// spec-case: NEW-CORE-STACK-2
test "borrow-only summaries reject count operations, copying and mutation even without escapes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const ints = try module.intern(a, .{ .list = .i64 });
    try forbiddenUses(a, &module, ints);
    const summaries = try effects.analyze(a, &module);
    for (summaries.params) |params| {
        try std.testing.expect(!params[0].borrow_only);
        try std.testing.expect(!params[0].writes.whole and params[0].writes.items.items.len == 0);
    }
}

fn parameterAliases(a: std.mem.Allocator, module: *ir.Module, ints: ir.Type) !void {
    const record = try module.intern(a, .{ .record = try a.dupe(ir.Type, &.{ints}) });
    for ([_]ir.Op{ .ret, .record_make, .phi }) |op| {
        var h = try unary(a, module, @tagName(op), ints);
        const xs = try h.param(0);
        var value = xs;
        if (op == .record_make) {
            _ = try h.emit(.{ .op = .record_make, .ty = record, .data = try h.extra(&.{xs}) });
        } else if (op == .phi) {
            const join = try h.newBlock();
            try h.jump(join);
            h.block = join;
            value = try h.emit(.{ .op = .phi, .ty = ints, .data = try h.extra(&.{xs}) });
        }
        if (op == .ret) {
            h.function.signature.ret = ints;
        } else value = try h.emit(.{ .op = .list_len, .ty = .u64, .a = value });
        _ = try h.emit(.{ .op = .ret, .ty = .void, .a = value });
        _ = try h.finish();
    }
}

// spec-case: NEW-CORE-STACK-2
test "borrow-only summaries reject returned, stored and phi-owned parameter aliases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const ints = try module.intern(a, .{ .list = .i64 });
    try parameterAliases(a, &module, ints);
    const summaries = try effects.analyze(a, &module);
    for (summaries.params) |params| try std.testing.expect(!params[0].borrow_only);
}

fn opaqueParameters(a: std.mem.Allocator, module: *ir.Module, ints: ir.Type) !void {
    for ([_]ir.Linkage{ .extern_c, .runtime_c, .internal }) |linkage| {
        try module.functions.append(a, .{ .name = @tagName(linkage), .signature = .{ .params = try a.dupe(ir.Type, &.{ints}), .ret = .u64, .linkage = linkage } });
        _ = try relay(a, module, "opaque_caller", ints, @intCast(module.functions.items.len - 1));
    }
}

// spec-case: NEW-CORE-STACK-2
test "borrow-only summaries require ordinary internal parameters and unmanaged list elements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const ints = try module.intern(a, .{ .list = .i64 });
    const strings = try module.intern(a, .{ .list = .str });
    const managed = try reader(a, &module, "managed", strings, .list_len);
    const owned = try reader(a, &module, "owned", ints, .list_len);
    module.functions.items[owned].signature.owned = 1;
    try opaqueParameters(a, &module, ints);
    const summaries = try effects.analyze(a, &module);
    try std.testing.expect(!summaries.of(managed, 0).borrow_only);
    for (summaries.params) |params| try std.testing.expect(!params[0].borrow_only);
}

// spec-case: NEW-CORE-STACK-2
test "borrow-only summaries keep indirect and recursive forwarding conservative" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const ints = try module.intern(a, .{ .list = .i64 });
    const target = try reader(a, &module, "leaf", ints, .list_len);
    const callback = try module.intern(a, .{ .@"fn" = module.functions.items[target].signature });
    var indirect = try unary(a, &module, "indirect", ints);
    const xs = try indirect.param(0);
    const function = try indirect.loose(.{ .op = .func_ref, .ty = callback, .data = target });
    const called = try indirect.emit(.{ .op = .call_indirect, .ty = .u64, .a = function, .data = try indirect.extra(&.{xs}) });
    _ = try indirect.emit(.{ .op = .ret, .ty = .void, .a = called });
    _ = try indirect.finish();
    _ = try relay(a, &module, "recursive", ints, 2);
    _ = try relay(a, &module, "ping", ints, 4);
    _ = try relay(a, &module, "pong", ints, 3);
    const summaries = try effects.analyze(a, &module);
    try std.testing.expect(summaries.of(target, 0).borrow_only);
    for (summaries.params[1..]) |params| try std.testing.expect(!params[0].borrow_only);
}

// spec-case: NEW-CORE-STACK-2
test "borrow-only summaries survive validated reuse while an unloaded body stays unknown" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const ints = try module.intern(a, .{ .list = .i64 });
    _ = try relay(a, &module, "caller", ints, 1);
    const leaf = try reader(a, &module, "leaf", ints, .list_len);
    const eager = try effects.analyze(a, &module);
    const retained = try effects.retain(a, .{ .params = eager.params[leaf], .may = eager.may[leaf] });
    eager.params[leaf][0].borrow_only = false;
    try std.testing.expect(retained.params[0].borrow_only);
    module.functions.items[leaf].blocks = .empty;
    module.functions.items[leaf].insts = .empty;
    const missing = try effects.analyze(a, &module);
    try std.testing.expect(!missing.of(leaf, 0).borrow_only);
    try std.testing.expect(!missing.of(0, 0).borrow_only);
    const seeded = try effects.analyzeReused(a, &module, &.{ null, retained });
    try std.testing.expect(seeded.of(leaf, 0).borrow_only);
    try std.testing.expect(seeded.of(0, 0).borrow_only);
}
