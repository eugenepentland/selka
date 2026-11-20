//! Projection fusion keeps a place-read flag only when the element read carries it (C1). A plain element read fuses to
//! the bare field path, as it always did; a `match mut` scrutinee's read, which carries the flag, keeps it.
const std = @import("std");
const ir = @import("ir.zig");
const fuse = @import("fuse.zig");
const flags = @import("flags.zig");
const support = @import("test_support.zig");
const Hand = support.Hand;

/// A function returning field 0 of element 0 of `rows`, whose element read carries `read_data`.
fn firstFieldOfElement(a: std.mem.Allocator, module: *ir.Module, read_data: u64) !u32 {
    const row = try module.intern(a, .{ .record = &.{ .i64, .i64 } });
    const rows = try module.intern(a, .{ .list = row });
    var h = try Hand.init(a, module, "project", .{ .params = try a.dupe(ir.Type, &.{rows}), .ret = .i64 });
    const input = try h.param(0);
    const index = try h.int(.i64, 0);
    const element = try h.emit(.{ .op = .list_get, .ty = row, .a = input, .b = index, .data = read_data, .check = .exact });
    const first = try h.emit(.{ .op = .record_get, .ty = .i64, .a = element, .data = 0 });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = first });
    return h.finish();
}

/// The data of the projection that fusion turned into a field read of the element.
fn fusedData(a: std.mem.Allocator, read_data: u64) !u64 {
    var module: ir.Module = .{};
    const index = try firstFieldOfElement(a, &module, read_data);
    const function = &module.functions.items[index];
    _ = try fuse.projections(a, function, &module);
    for (function.insts.items) |inst| if (inst.op == .list_get_field) return inst.data;
    return error.TestUnexpectedResult;
}

// spec-case: NEW-CORE-FUSE-PLACE-1
test "projection fusion of a plain element read keeps the bare field path with no place-read flag" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = ir.FieldPath.init(&.{0}).?.pack();
    try std.testing.expectEqual(path, try fusedData(a, 0));
    try std.testing.expect(try fusedData(a, 0) & flags.place_read == 0);
}

test "projection fusion of a place read keeps the place-read flag on the field read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = ir.FieldPath.init(&.{0}).?.pack();
    try std.testing.expectEqual(path | flags.place_read, try fusedData(a, flags.place_read));
}
