//! Type spelling in textual Core IR (`print.zig`): a recursive type terminates by naming a cycle by index.
const std = @import("std");
const ir = @import("ir.zig");
const print = @import("print.zig");

test "print names a record that contains a list of itself by a cycle stop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    // list[record] then record{list}: the record is the list's index plus one.
    const list: ir.Type = @fromBackingInt(ir.Type.first_compound + @as(u32, @intCast(module.compounds.items.len)));
    const record: ir.Type = @fromBackingInt(@backingInt(list) + 1);
    try module.compounds.appendSlice(a, &.{ .{ .list = record }, .{ .record = try a.dupe(ir.Type, &.{list}) } });
    const text = try print.typeName(a, &module, record);
    try std.testing.expectEqualStrings("record{list[#17]}", text);
    try std.testing.expectEqualStrings("list[record{#16}]", try print.typeName(a, &module, list));
}

test "print names a union that contains a dictionary of itself by a cycle stop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    // dict[str, union] then union{i64, dict}: the union is the dictionary's index plus one.
    const dict: ir.Type = @fromBackingInt(ir.Type.first_compound + @as(u32, @intCast(module.compounds.items.len)));
    const union_ty: ir.Type = @fromBackingInt(@backingInt(dict) + 1);
    try module.compounds.appendSlice(a, &.{
        .{ .dict = .{ .key = .str, .value = union_ty } },
        .{ .@"union" = try a.dupe(ir.Type, &.{ .i64, dict }) },
    });
    const text = try print.typeName(a, &module, union_ty);
    try std.testing.expectEqualStrings("union{i64, dict[str, #17]}", text);
}

test "print spells a recursive record through a box by index without expanding it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    // record{box[record]}: the existing box convention names the record by index.
    const record: ir.Type = @fromBackingInt(ir.Type.first_compound + @as(u32, @intCast(module.compounds.items.len)));
    const box: ir.Type = @fromBackingInt(@backingInt(record) + 1);
    try module.compounds.appendSlice(a, &.{ .{ .record = try a.dupe(ir.Type, &.{box}) }, .{ .box = record } });
    try std.testing.expectEqualStrings("record{box[#16]}", try print.typeName(a, &module, record));
}

test "print spells an acyclic type with the same names as before the cycle stop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const inner = try module.intern(a, .{ .record = &.{ .i64, .str } });
    const outer = try module.intern(a, .{ .list = inner });
    try std.testing.expectEqualStrings("list[record{i64, str}]", try print.typeName(a, &module, outer));
    try std.testing.expectEqualStrings("record{i64, str}", try print.typeName(a, &module, inner));
}
