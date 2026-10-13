//! Raw IR exercises one-use pairing independently of frontend SSA versioning.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");
const transfers = @import("transfers.zig");

fn check(allocator: std.mem.Allocator, instructions: []const ir.Inst, blocks: []const []const u32, expected: []const u32) !void {
    var function: ir.Function = .{ .name = "transfer", .signature = .{ .params = &.{}, .ret = .void } };
    try function.insts.appendSlice(allocator, instructions);
    for (blocks) |indices| {
        var block: ir.Block = .{};
        for (indices) |index| try block.insts.append(allocator, @fromBackingInt(index));
        try function.blocks.append(allocator, block);
    }
    const taken = try transfers.slots(allocator, &function);
    for (taken, 0..) |actual, index| {
        var wanted = false;
        for (expected) |selected| wanted = wanted or selected == index;
        try std.testing.expectEqual(wanted, actual);
    }
}

const owner: ir.Inst = .{ .op = .undef, .ty = .u64 };
const slot_index: ir.Inst = .{ .op = .iconst, .ty = .u64 };
const read: ir.Inst = .{ .op = .list_get, .ty = .u64, .a = @fromBackingInt(0), .b = @fromBackingInt(1), .data = flags.place_read };
const write: ir.Inst = .{ .op = .list_set, .ty = .u64, .a = @fromBackingInt(0), .b = @fromBackingInt(1) };
const ret: ir.Inst = .{ .op = .ret, .ty = .void };

// spec-case: OWNED-LIST-EXCHANGE-1
test "transfer pairing consumes once and excludes dictionary key projection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try check(a, &.{ owner, slot_index, read, write, write, ret }, &.{&.{ 0, 1, 2, 3, 4, 5 }}, &.{3});
    var key = read;
    key.op = .dict_entry_key;
    key.data = flags.dict_take_key;
    var value_write = write;
    value_write.op = .dict_set_value;
    try check(a, &.{ owner, slot_index, key, value_write, ret }, &.{&.{ 0, 1, 2, 3, 4 }}, &.{});
}

// spec-case: OWNED-LIST-EXCHANGE-1
test "transfer pairing respects sibling branches cross block updates and loop turns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const branch: ir.Inst = .{ .op = .branch, .ty = .void, .data = ir.packTargets(@fromBackingInt(1), @fromBackingInt(2)) };
    const join: ir.Inst = .{ .op = .jump, .ty = .void, .data = 3 };
    try check(a, &.{ owner, slot_index, branch, read, write, join, write, join, ret }, &.{ &.{ 0, 1, 2 }, &.{ 3, 4, 5 }, &.{ 6, 7 }, &.{8} }, &.{4});
    const jump: ir.Inst = .{ .op = .jump, .ty = .void, .data = 1 };
    try check(a, &.{ owner, slot_index, read, jump, write, ret }, &.{ &.{ 0, 1, 2, 3 }, &.{ 4, 5 } }, &.{4});
    try check(a, &.{ owner, slot_index, read, jump, write, jump }, &.{ &.{ 0, 1, 2, 3 }, &.{ 4, 5 } }, &.{});
    try check(a, &.{ owner, slot_index, jump, read, write, jump }, &.{ &.{ 0, 1, 2 }, &.{ 3, 4, 5 } }, &.{4});
}

// spec-case: OWNED-LIST-EXCHANGE-1
test "transfer pairing scaling keeps 512 distinct slots one use each" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const function = try manySlots(a);
    const taken = try transfers.slots(a, &function);
    for (0..512) |slot| {
        try std.testing.expect(taken[1 + slot * 4 + 2]);
        try std.testing.expect(!taken[1 + slot * 4 + 3]);
    }
}

fn manySlots(allocator: std.mem.Allocator) !ir.Function {
    var function: ir.Function = .{ .name = "many", .signature = .{ .params = &.{}, .ret = .void } };
    try function.insts.append(allocator, slot_index);
    var block: ir.Block = .{};
    try block.insts.append(allocator, @fromBackingInt(0));
    for (0..512) |_| {
        const base: u32 = @intCast(function.insts.items.len);
        var take = read;
        take.a = @fromBackingInt(base);
        take.b = @fromBackingInt(0);
        var put = write;
        put.a = take.a;
        put.b = take.b;
        try function.insts.appendSlice(allocator, &.{ owner, take, put, put });
        for (0..4) |offset| try block.insts.append(allocator, @fromBackingInt(base + @as(u32, @intCast(offset))));
    }
    try function.insts.append(allocator, ret);
    try block.insts.append(allocator, @fromBackingInt(@as(u32, @intCast(function.insts.items.len - 1))));
    try function.blocks.append(allocator, block);
    return function;
}
