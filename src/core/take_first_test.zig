//! Takes before views (`take_first.zig`): a view nobody reads is dropped when a take repeats it with nothing observable between,
//! and kept otherwise; the lowering of `append(mut rows[i], 9)` leaves one read, the take.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");
const take_first = @import("take_first.zig");
const support = @import("test_support.zig");
const Hand = support.Hand;

/// The types of the exercises: `rows` is a list of lists of integers.
const Types = struct { row: ir.Type, rows: ir.Type };

fn types(a: std.mem.Allocator, module: *ir.Module) !Types {
    const row = try module.intern(a, .{ .list = .i64 });
    return .{ .row = row, .rows = try module.intern(a, .{ .list = row }) };
}

/// How many `list_get` reads block 0 holds.
fn reads(function: *const ir.Function) usize {
    var n: usize = 0;
    for (function.blocks.items[0].insts.items) |ref| n += @intFromBool(function.inst(ref).op == .list_get);
    return n;
}

/// Which instruction lies between a view of `rows[0]` and the take of the same slot.
const Between = enum { nothing, constant, call, checked_read, plain_add };

/// `rows[0]` read as a view nobody reads, `between` made to lie after it, then the take of `rows[0]`; the number of reads the
/// pass leaves.
fn left(a: std.mem.Allocator, between: Between) !usize {
    var module: ir.Module = .{};
    const t = try types(a, &module);
    var h = try Hand.init(a, &module, "f", .{ .params = try a.dupe(ir.Type, &.{t.rows}), .ret = .void });
    const input = try h.param(0);
    const zero = try h.int(.i64, 0);
    _ = try h.emit(.{ .op = .list_get, .ty = t.row, .a = input, .b = zero, .check = .exact });
    switch (between) {
        .nothing => {},
        .constant => _ = try h.emit(.{ .op = .iconst, .ty = .i64, .data = 9 }),
        .call => _ = try h.emit(.{ .op = .call, .ty = .void, .a = @fromBackingInt(0), .data = try h.extra(&.{}) }),
        .checked_read => _ = try h.emit(.{ .op = .list_get, .ty = t.row, .a = input, .b = zero, .data = 1, .check = .exact }),
        .plain_add => _ = try h.emit(.{ .op = .add, .ty = .i64, .a = zero, .b = zero }),
    }
    _ = try h.emit(.{ .op = .list_get, .ty = t.row, .a = input, .b = zero, .data = flags.place_read, .check = .exact });
    _ = try h.emit(.{ .op = .ret, .ty = .void });
    _ = try take_first.run(a, &h.function);
    return reads(&h.function);
}

test "a view nobody reads goes when the take of its slot follows with nothing observable between" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(usize, 1), try left(a, .nothing));
    try std.testing.expectEqual(@as(usize, 1), try left(a, .constant));
    try std.testing.expectEqual(@as(usize, 1), try left(a, .plain_add));
}

test "a view stays when a call or a read that can trap lies between it and the take" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(usize, 2), try left(a, .call));
    // the read between has another `data`, so it is not the take; it is a read that can trap, which must keep its place
    try std.testing.expectEqual(@as(usize, 3), try left(a, .checked_read));
}

test "a view something reads stays, and so does one whose slot the take does not repeat" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const t = try types(a, &module);
    var h = try Hand.init(a, &module, "f", .{ .params = try a.dupe(ir.Type, &.{t.rows}), .ret = .i64 });
    const input = try h.param(0);
    const zero = try h.int(.i64, 0);
    const one = try h.int(.i64, 1);
    const view = try h.emit(.{ .op = .list_get, .ty = t.row, .a = input, .b = zero, .check = .exact });
    const length = try h.emit(.{ .op = .list_len, .ty = .u64, .a = view });
    _ = try h.emit(.{ .op = .list_get, .ty = t.row, .a = input, .b = zero, .data = flags.place_read, .check = .exact });
    // an unread view of another slot is not repeated by the take of this one
    _ = try h.emit(.{ .op = .list_get, .ty = t.row, .a = input, .b = one, .check = .exact });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = length });
    try std.testing.expectEqual(@as(u32, 0), try take_first.run(a, &h.function));
    try std.testing.expectEqual(@as(usize, 3), reads(&h.function));
}

/// A path `rows[0][1]`: views of both levels, `between` after them, then the takes of both; the reads the pass leaves.
fn path(a: std.mem.Allocator, checked_between: bool) !usize {
    var module: ir.Module = .{};
    const t = try types(a, &module);
    var h = try Hand.init(a, &module, "f", .{ .params = try a.dupe(ir.Type, &.{t.rows}), .ret = .void });
    const input = try h.param(0);
    const zero = try h.int(.i64, 0);
    const one = try h.int(.i64, 1);
    const outer = try h.emit(.{ .op = .list_get, .ty = t.row, .a = input, .b = zero, .check = .exact });
    _ = try h.emit(.{ .op = .list_get, .ty = .i64, .a = outer, .b = one, .check = .exact });
    if (checked_between) _ = try h.emit(.{ .op = .list_get, .ty = .i64, .a = outer, .b = zero, .data = 1, .check = .exact });
    const taken = try h.emit(.{ .op = .list_get, .ty = t.row, .a = input, .b = zero, .data = flags.place_read, .check = .exact });
    _ = try h.emit(.{ .op = .list_get, .ty = .i64, .a = taken, .b = one, .data = flags.place_read, .check = .exact });
    _ = try h.emit(.{ .op = .ret, .ty = .void });
    _ = try take_first.run(a, &h.function);
    return reads(&h.function);
}

test "a path of views goes whole or stays whole" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(usize, 2), try path(a, false));
    try std.testing.expectEqual(@as(usize, 5), try path(a, true));
}

test "a take of an equal read of the container repeats the view" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const t = try types(a, &module);
    const holder = try module.intern(a, .{ .record = &.{t.rows} });
    var h = try Hand.init(a, &module, "f", .{ .params = try a.dupe(ir.Type, &.{holder}), .ret = .void });
    const input = try h.param(0);
    const zero = try h.int(.i64, 0);
    // the container is read twice from the same record: the view's and the take's are one value
    const first = try h.emit(.{ .op = .record_get, .ty = t.rows, .a = input, .data = 0 });
    // something else reads the container, so only the leaf view is unread
    _ = try h.emit(.{ .op = .list_len, .ty = .u64, .a = first });
    _ = try h.emit(.{ .op = .list_get, .ty = t.row, .a = first, .b = zero, .check = .exact });
    const again = try h.emit(.{ .op = .record_get, .ty = t.rows, .a = input, .data = 0 });
    _ = try h.emit(.{ .op = .list_get, .ty = t.row, .a = again, .b = zero, .data = flags.place_read, .check = .exact });
    _ = try h.emit(.{ .op = .ret, .ty = .void });
    try std.testing.expectEqual(@as(u32, 1), try take_first.run(a, &h.function));
    try std.testing.expectEqual(@as(usize, 1), reads(&h.function));
}

test "the lowering of a mut element argument reads the slot once, as the take" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try support.irText(a,
        \\func push(mut rows: int[][], i: int) -> int:
        \\    append(mut rows[i], 9)
        \\    return len(rows)
        \\
        \\func main(args: str[], out: Stream) -> int:
        \\    mut rows: int[][] = [[1], [2]]
        \\    print(out, push(mut rows, len(args)))
        \\    return 0
        \\
    );
    const start = std.mem.indexOf(u8, text, "fn push(").?;
    const end = std.mem.indexOfPos(u8, text, start + 1, "\nfn ") orelse text.len;
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text[start..end], "list_get"));
}
