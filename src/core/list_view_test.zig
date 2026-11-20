//! List views (wave 3, plan §5.2 / D22): a slice of a list that is only read
//! borrows the list's elements instead of copying them.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const Hand = support.Hand;

/// A three-element list `[10, 20, 30]` built at run time.
fn listOf(a: std.mem.Allocator, m: *ir.Module, h: *Hand, list: ir.Type, values: []const i64) !ir.Ref {
    var container = try h.emit(.{ .op = .list_new, .ty = list, .a = try h.int(.u64, @intCast(values.len)) });
    for (values) |value| container = try h.emit(.{ .op = .list_push, .ty = list, .a = container, .b = try h.int(.i64, value) });
    _ = a;
    _ = m;
    return container;
}

// spec-case: NEW-CORE-S1-VIEW-6
test "a list slice view reads its elements and their count" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    const view = try module.intern(a, .{ .list_view = .i64 });
    var h = try Hand.init(a, &module, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const source = try listOf(a, &module, &h, list, &.{ 10, 20, 30 });
    const first = try h.int(.i64, 1);
    const last = try h.int(.i64, 3);
    const slice = try h.emit(.{ .op = .list_slice_view, .ty = view, .a = source, .b = first, .data = try h.extra(&.{last}) });
    const length = try h.emit(.{ .op = .list_len, .ty = .u64, .a = slice });
    const element = try h.emit(.{ .op = .list_get, .ty = .i64, .a = slice, .b = try h.int(.i64, 0), .check = .exact });
    const count = try h.emit(.{ .op = .convert, .ty = .i64, .a = length });
    try h.printValues(try h.param(0), &.{ count, element });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    module.entry = try h.finish();
    try support.verified(a, &module, &.{});
    const ran = try support.runOwned(a, &module, .{ .release = true });
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("2 20\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

// spec-case: NEW-CORE-S1-VIEW-6
test "a whole-list view counts and reads every element" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    const view = try module.intern(a, .{ .list_view = .i64 });
    var h = try Hand.init(a, &module, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const source = try listOf(a, &module, &h, list, &.{ 10, 20, 30 });
    const whole = try h.emit(.{ .op = .list_view_of, .ty = view, .a = source });
    const length = try h.emit(.{ .op = .list_len, .ty = .u64, .a = whole });
    const last_element = try h.emit(.{ .op = .list_get, .ty = .i64, .a = whole, .b = try h.int(.i64, 2), .check = .exact });
    const count = try h.emit(.{ .op = .convert, .ty = .i64, .a = length });
    try h.printValues(try h.param(0), &.{ count, last_element });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    module.entry = try h.finish();
    try support.verified(a, &module, &.{});
    const ran = try support.runOwned(a, &module, .{ .release = true });
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("3 30\n", ran.stdout);
}

// spec-case: NEW-CORE-S1-VIEW-6
test "reading past a list view traps against the view's own length" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    const view = try module.intern(a, .{ .list_view = .i64 });
    var h = try Hand.init(a, &module, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const source = try listOf(a, &module, &h, list, &.{ 10, 20, 30 });
    const slice = try h.emit(.{ .op = .list_slice_view, .ty = view, .a = source, .b = try h.int(.i64, 1), .data = try h.extra(&.{try h.int(.i64, 2)}) });
    const element = try h.emit(.{ .op = .list_get, .ty = .i64, .a = slice, .b = try h.int(.i64, 5), .check = .exact });
    try h.printValues(try h.param(0), &.{element});
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    module.entry = try h.finish();
    try support.verified(a, &module, &.{});
    const ran = try support.runOwned(a, &module, .{ .release = true });
    try std.testing.expectEqual(@as(u8, 1), ran.status);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "R_LIST_BOUNDS") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "(index 5, length 1)") != null);
}

// spec-case: NEW-CORE-S1-VIEW-6
test "a slice of an immutable list bound to a local is a view" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func width(values: int[]) -> int:
        \\    const piece = values[1:3]
        \\    return len(piece) + piece[0]
        \\func main(out: Stream) -> int:
        \\    print(out, width([10, 20, 30, 40]))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    const width = functionText(a, dumped, "width") catch null orelse "";
    try std.testing.expect(std.mem.indexOf(u8, width, "list_slice_view") != null);
    // The copy loop is gone: the view borrows the parameter's elements.
    try std.testing.expect(std.mem.indexOf(u8, width, "list_push") == null);
    try std.testing.expect(std.mem.indexOf(u8, width, "acquire_buffer") == null);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("22\n", ran.stdout);
}

/// The listing of function `name` in dumped IR.
fn functionText(a: std.mem.Allocator, dumped: []const u8, name: []const u8) !?[]const u8 {
    const header = try std.fmt.allocPrint(a, "fn {s}(", .{name});
    defer a.free(header);
    const start = std.mem.indexOf(u8, dumped, header) orelse return null;
    const next = std.mem.indexOfPos(u8, dumped, start + header.len, "\nfn ") orelse dumped.len;
    return dumped[start..next];
}

// spec-case: NEW-CORE-S1-VIEW-6
test "a stored list slice builds once its binding takes the copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Batch W3 refuses `Held(items=piece)` for a view binding; the repair copies at
    // the binding, and the repaired program lowers with no view and prints 2.
    const source =
        \\record Held:
        \\    items: int[]
        \\func keep(values: int[]) -> int:
        \\    const piece = copy(values[1:3])
        \\    const held = Held(items=own piece)
        \\    return len(held.items)
        \\func main(out: Stream) -> int:
        \\    print(out, keep([10, 20, 30, 40]))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    const keep = functionText(a, dumped, "keep") catch null orelse "";
    try std.testing.expect(std.mem.indexOf(u8, keep, "list_slice_view") == null);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("2\n", ran.stdout);
}

// spec-case: NEW-CORE-S1-VIEW-6
test "iterating a list view borrows the elements and keeps the values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func total(values: int[]) -> int:
        \\    const piece = values[1:3]
        \\    mut sum = 0
        \\    for value in piece:
        \\        sum += value
        \\    return sum
        \\func main(out: Stream) -> int:
        \\    print(out, total([10, 20, 30, 40]))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    const total = functionText(a, dumped, "total") catch null orelse "";
    try std.testing.expect(std.mem.indexOf(u8, total, "list_slice_view") != null);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("50\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

// spec-case: NEW-CORE-S1-VIEW-6
test "a view of managed elements reads them and keeps the source alive" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func joined(words: str[]) -> int:
        \\    const piece = words[1:3]
        \\    mut total = 0
        \\    for word in piece:
        \\        total += strings.char_count(word)
        \\    return total + strings.char_count(piece[0])
        \\func main(out: Stream) -> int:
        \\    print(out, joined(["aa", "béé", "ccc", "dd"]))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("9\n", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}

// spec-case: NEW-CORE-S1-VIEW-6
test "an empty or reversed list range is a view of no elements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func widths(values: int[]) -> int:
        \\    const reversed = values[3:1]
        \\    const beyond = values[2:99]
        \\    return len(reversed) + len(beyond) + beyond[0]
        \\func main(out: Stream) -> int:
        \\    print(out, widths([10, 20, 30, 40]))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("32\n", ran.stdout);
}

// spec-case: NEW-CORE-S1-VIEW-6
test "a noalloc function reads a list slice without allocating" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\@noalloc
        \\func count(values: int[]) -> int:
        \\    const piece = values[1:3]
        \\    return len(piece) + piece[0]
        \\func main() -> int:
        \\    return count([10, 20, 30, 40]) - 22
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("", ran.stderr);
}

// spec-case: NEW-CORE-S1-VIEW-6
test "a list slice written at its use and only read is a view" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func width(values: int[], out: Stream) -> int:
        \\    print(out, len(values[1:3]), values[1:3][0], values[1:3][1])
        \\    return len(values[1:3])
        \\func main(out: Stream) -> int:
        \\    _ = width([10, 20, 30, 40], out)
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    const width = functionText(a, dumped, "width") catch null orelse "";
    try std.testing.expect(std.mem.indexOf(u8, width, "list_slice_view") != null);
    // The append-loop copy is gone: the reads borrow the parameter's elements.
    try std.testing.expect(std.mem.indexOf(u8, width, "list_push") == null);
    try std.testing.expect(std.mem.indexOf(u8, width, "acquire_buffer") == null);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("2 20 30\n", ran.stdout);
}

// spec-case: NEW-CORE-S1-VIEW-6
test "an inline list slice used only as a loop source is a view too" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func total(values: int[]) -> int:
        \\    mut count = 0
        \\    for value in values[1:3]:
        \\        count += value
        \\    return count
        \\func main(out: Stream) -> int:
        \\    print(out, total([10, 20, 30, 40]))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    const total = functionText(a, dumped, "total") catch null orelse "";
    // The loop reads its source's elements, so the slice borrows them and the
    // copy loop (which `slices.loops` used to iterate in place) is never built.
    try std.testing.expect(std.mem.indexOf(u8, total, "list_slice_view") != null);
    try std.testing.expect(std.mem.indexOf(u8, total, "list_push") == null);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("50\n", ran.stdout);
}

// spec-case: NEW-CORE-S1-VIEW-6
test "an inline list slice of a mutable source is a read taken after the write" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Batch W4 makes a list view of a mutable source follow the text rule: the
    // read borrows the elements, and a later write would be refused. The write
    // here happens first, so the read is a view of the current elements.
    const source =
        \\func width(out: Stream) -> int:
        \\    mut values = [10, 20, 30, 40]
        \\    values[0] = 9
        \\    print(out, len(values[1:3]))
        \\    return len(values[1:3])
        \\func main(out: Stream) -> int:
        \\    _ = width(out)
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    const width = functionText(a, dumped, "width") catch null orelse "";
    try std.testing.expect(std.mem.indexOf(u8, width, "list_slice_view") != null);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("2\n", ran.stdout);
}

// spec-case: NEW-CORE-C9-LISTS-1
test "a list slice passed to a plain list parameter is a view with no copy in the caller" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func total_of(values: int[]) -> int:
        \\    mut t = 0
        \\    for x in values:
        \\        t += x
        \\    return t
        \\func main(out: Stream) -> int:
        \\    const data = [10, 20, 30, 40]
        \\    print(out, total_of(data[1:3]))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    // The parameter is a list view, and the caller's slice is one `list_slice_view` with no copy loop.
    const total = functionText(a, dumped, "total_of") catch null orelse "";
    try std.testing.expect(std.mem.indexOf(u8, total, "fn total_of(list_view[i64], list[i64]) -> i64") != null);
    const main = functionText(a, dumped, "main") catch null orelse "";
    try std.testing.expect(std.mem.indexOf(u8, main, "list_slice_view") != null);
    // The only pushes are the literal's four elements: the slice builds no copy loop of its own.
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, main, "list_push"));
    try std.testing.expect(std.mem.indexOf(u8, main, "acquire_buffer") == null);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("50\n", ran.stdout);
}

// spec-case: NEW-CORE-C9-LISTS-1
test "a forwarding hop passes a list view unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func inner(values: int[]) -> int:
        \\    return len(values)
        \\func outer(values: int[]) -> int:
        \\    return inner(values)
        \\func main(out: Stream) -> int:
        \\    const data = [10, 20, 30, 40]
        \\    print(out, outer(data[0:3]))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    const outer = functionText(a, dumped, "outer") catch null orelse "";
    try std.testing.expect(std.mem.indexOf(u8, outer, "fn outer(list_view[i64], list[i64]) -> i64") != null);
    // The hop neither copies nor builds a list: the view it receives is the view it passes on.
    try std.testing.expect(std.mem.indexOf(u8, outer, "list_view_of") == null);
    try std.testing.expect(std.mem.indexOf(u8, outer, "list_copy") == null);
    try std.testing.expect(std.mem.indexOf(u8, outer, "acquire_buffer") == null);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("3\n", ran.stdout);
}

// spec-case: NEW-CORE-C9-LISTS-1
test "an owned list passed to a plain list parameter is lent its view" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\func count_of(values: int[]) -> int:
        \\    return len(values)
        \\func main(out: Stream) -> int:
        \\    mut owned: int[] = []
        \\    append(mut owned, 7)
        \\    append(mut owned, 8)
        \\    print(out, count_of(owned))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const dumped = try @import("print.zig").module(a, &module);
    const main = functionText(a, dumped, "main") catch null orelse "";
    try std.testing.expect(std.mem.indexOf(u8, main, "list_view_of") != null);
    try std.testing.expect(std.mem.indexOf(u8, main, "list_copy") == null);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("2\n", ran.stdout);
}

test "extending a list from a list parameter checks identity through the parameter's owner" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\import lists
        \\record Point:
        \\    x: int
        \\    y: int
        \\func extend_from(mut target: Point[], pts: Point[]):
        \\    lists.extend(mut target, pts)
        \\func main(out: Stream) -> int:
        \\    mut stops: Point[] = []
        \\    extend_from(mut stops, [Point(x=1, y=2), Point(x=3, y=4)])
        \\    extend_from(mut stops, [Point(x=5, y=6)])
        \\    print(out, len(stops))
        \\    return 0
    ;
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const ran = try support.runOwned(a, &module, .{});
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("3\n", ran.stdout);
}
