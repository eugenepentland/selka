//! Recursive Core type names remain finite without abbreviating shared siblings.
const std = @import("std");
const ir = @import("ir.zig");
const print = @import("print.zig");

// spec: NEW-CORE-PRINT-RECURSIVE-1
test "Core type text terminates on recursive records through lists and dictionaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m: ir.Module = .{};
    const node: ir.Type = @fromBackingInt(ir.Type.first_compound);
    const children: ir.Type = @fromBackingInt(ir.Type.first_compound + 1);
    try m.compounds.appendSlice(a, &.{ .{ .record = &.{ .i64, children } }, .{ .list = node } });
    try std.testing.expectEqualStrings("record{i64, list[#15]}", try print.typeName(a, &m, node));
    try std.testing.expectEqualStrings("list[record{i64, #16}]", try print.typeName(a, &m, children));
    m.compounds.items[1] = .{ .dict = .{ .key = .str, .value = node } };
    try std.testing.expectEqualStrings("record{i64, dict[str, #15]}", try print.typeName(a, &m, node));
}

// spec-case: NEW-CORE-PRINT-RECURSIVE-1
test "Core type text expands shared siblings and preserves boxed nominal identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m: ir.Module = .{};
    const leaf = try m.intern(a, .{ .record = &.{ .i64, .bool } });
    const pair = try m.intern(a, .{ .record = &.{ leaf, leaf } });
    const boxed = try m.intern(a, .{ .box = leaf });
    try std.testing.expectEqualStrings("record{record{i64, bool}, record{i64, bool}}", try print.typeName(a, &m, pair));
    try std.testing.expectEqualStrings("box[#15]", try print.typeName(a, &m, boxed));
}
