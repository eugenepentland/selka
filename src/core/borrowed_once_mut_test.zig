//! H1 (D4, lane OC, plan Part B stage O3): a `mut` local stored once from a place borrows it, as a `const` does. A write through
//! it (an append, a field or element write, a `mut` argument) is refused at the write, with the code, rule and certain repair
//! the binding had as an owner before D4 (here B8, a field of a plain parameter, and `copy(...)` at the binding). A `mut` local assigned more than once and
//! written keeps its refusal at the store that needs `copy(...)`; `own`, `copy(...)` and fresh initializers are owners as
//! before. Guest behaviour is `tests/lang/borrowed_once_mut_locals.selka`; `selka fix` is `test/fix_cli_test.zig`. The tests
//! assert codes, rules, lines and the repair's place, not message text.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");

const prelude =
    \\record Item:
    \\    name: str
    \\    count: int
    \\
    \\record Shelf:
    \\    item: Item
    \\    counts: int[]
    \\
    \\func grow(mut values: int[]) -> Unit:
    \\    append(mut values, 1)
    \\
    \\
;

/// The line the prelude ends on: a refusal's line in a case is this plus its line in the case.
const prelude_lines = std.mem.count(u8, prelude, "\n");

/// What a refusal must be: its code and rule, its line in the case, and the line of its `copy(...)` repair (0: none).
const Expected = struct { code: []const u8, rule: language.ownership_rules.Rule, line: usize, copy_line: usize };

fn lineOf(text: []const u8, at: usize) usize {
    return std.mem.count(u8, text[0..at], "\n") + 1;
}

/// `source` is refused as `expected` says.
fn refuses(backing: std.mem.Allocator, source: []const u8, expected: Expected) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    const text = try std.mem.concat(a, u8, &.{ prelude, source, "\nfunc main() -> int:\n    return 0\n" });
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(expected.code, failure.code);
    try std.testing.expectEqual(expected.rule, failure.rule.?);
    try std.testing.expectEqual(prelude_lines + expected.line, lineOf(text, failure.span.start));
    const copy_line = if (failure.copy.span) |span| lineOf(text, span.start) - prelude_lines else 0;
    try std.testing.expectEqual(expected.copy_line, copy_line);
}

/// `source` checks clean.
fn accepts(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    const checked = try support.checkedProgram(a, try std.mem.concat(a, u8, &.{ prelude, source }));
    try unique.check(a, checked, &failure);
    try std.testing.expectEqualStrings("", failure.code);
}

test "H1 a mut local stored once from a place borrows it while it is only read, and returns under from" {
    try accepts(std.testing.allocator,
        \\func read(shelf: Shelf) -> int:
        \\    mut counts = shelf.counts
        \\    mut item = shelf.item
        \\    return len(counts) + item.count
        \\
        \\func lent(shelf: Shelf) -> int[] from shelf:
        \\    mut counts = shelf.counts
        \\    return counts
        \\
        \\func main() -> int:
        \\    const shelf = Shelf(item=Item(name="a", count=1), counts=[1])
        \\    return read(shelf) + len(lent(shelf))
        \\
    );
}

test "H1 own, copy and fresh mut locals and a mut local assigned twice and only read behave as before" {
    try accepts(std.testing.allocator,
        \\func owned(shelf: Shelf, n: int) -> int:
        \\    mut copied = copy(shelf.counts)
        \\    append(mut copied, 2)
        \\    mut fresh = [n]
        \\    append(mut fresh, 3)
        \\    const owner = [n]
        \\    mut given = own owner
        \\    append(mut given, 4)
        \\    mut twice = shelf.counts
        \\    if n > 3:
        \\        twice = shelf.counts
        \\    return len(copied) + len(fresh) + len(given) + len(twice)
        \\
        \\func main() -> int:
        \\    return owned(Shelf(item=Item(name="a", count=1), counts=[1]), 2)
        \\
    );
}

test "H1 a write through a mut local stored once from a place is refused at the write, with the copy at the binding" {
    try refuses(std.testing.allocator,
        \\func f(shelf: Shelf) -> int:
        \\    mut counts = shelf.counts
        \\    append(mut counts, 4)
        \\    return len(counts)
    , .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .B8, .line = 3, .copy_line = 2 });
    try refuses(std.testing.allocator,
        \\func f(shelf: Shelf) -> int:
        \\    mut item = shelf.item
        \\    item.count = 2
        \\    return item.count
    , .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .B8, .line = 3, .copy_line = 2 });
    try refuses(std.testing.allocator,
        \\func f(shelf: Shelf) -> int:
        \\    mut counts = shelf.counts
        \\    counts[0] = 9
        \\    return counts[0]
    , .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .B8, .line = 3, .copy_line = 2 });
    try refuses(std.testing.allocator,
        \\func f(shelf: Shelf) -> int:
        \\    mut counts = shelf.counts
        \\    grow(mut counts)
        \\    return len(counts)
    , .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .B8, .line = 3, .copy_line = 2 });
}

test "H1 a mut local assigned twice and written keeps its refusal at the store that needs the copy" {
    try refuses(std.testing.allocator,
        \\func f(shelf: Shelf, n: int) -> int:
        \\    mut counts = shelf.counts
        \\    if n > 3:
        \\        counts = shelf.counts
        \\    append(mut counts, 1)
        \\    return len(counts)
    , .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .B8, .line = 2, .copy_line = 2 });
}

test "H4 a mut local stored from slices of places borrows them, rebound or once, text, bytes and lists" {
    try accepts(std.testing.allocator,
        \\func text(p: str, item: Item, n: int) -> int:
        \\    mut c = p[0:2]
        \\    if n > 3:
        \\        c = item.name
        \\    mut once = item.name[1:]
        \\    return len(c) + len(once)
        \\
        \\func raw(p: bytes, q: bytes, n: int) -> int:
        \\    mut c = p[0:2]
        \\    if n > 3:
        \\        c = q[1:]
        \\    return len(c)
        \\
        \\func tail(shelf: Shelf) -> int:
        \\    mut c = shelf.counts[0:]
        \\    mut total = 0
        \\    while len(c) > 0:
        \\        total = total + c[0]
        \\        c = c[1:]
        \\    return total
        \\
        \\func lent(shelf: Shelf, n: int) -> int[] from shelf:
        \\    mut c = shelf.counts[1:]
        \\    if n > 3:
        \\        c = shelf.counts
        \\    return c
        \\
        \\func main() -> int:
        \\    const shelf = Shelf(item=Item(name="abc", count=1), counts=[1, 2])
        \\    return text("abc", shelf.item, 2) + raw(b"ab", b"cd", 5) + tail(shelf) + len(lent(shelf, 1))
        \\
    );
}

test "H4 a slice-holding mut local that is written, stored or outlives its owner's change keeps the slice's refusal and copy" {
    try refuses(std.testing.allocator,
        \\func f(p: int[], n: int) -> int:
        \\    mut c = p[0:2]
        \\    if n > 3:
        \\        c = p[1:]
        \\    c[0] = 9
        \\    return len(c)
    , .{ .code = "E_SLICE_ESCAPES", .rule = .V2, .line = 2, .copy_line = 2 });
    try refuses(std.testing.allocator,
        \\func f(p: str, n: int) -> int:
        \\    mut c = p[0:2]
        \\    if n > 3:
        \\        c = p[1:]
        \\    mut out: str[] = []
        \\    append(mut out, c)
        \\    return len(out)
    , .{ .code = "E_SLICE_ESCAPES", .rule = .V2, .line = 2, .copy_line = 2 });
    try refuses(std.testing.allocator,
        \\func f(n: int) -> int:
        \\    mut text = f"abc{n}"
        \\    mut c = text[0:2]
        \\    if n > 3:
        \\        c = text[1:]
        \\    text = "x"
        \\    return len(c)
    , .{ .code = "E_SLICE_ESCAPES", .rule = .V2, .line = 3, .copy_line = 3 });
}

test "H4 a list slice stored into a borrowed mut local lowers to a view of the elements, with no copy loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a,
        \\func pick(p: int[], q: int[], n: int) -> int:
        \\    mut c = p[0:2]
        \\    if n > 3:
        \\        c = q[1:]
        \\    return len(c)
        \\func main() -> int:
        \\    return pick([1, 2, 3], [4, 5, 6], 7)
    , &refusal);
    try std.testing.expectEqual(@as(usize, 2), operations(&module, "pick", .list_slice_view));
    try std.testing.expectEqual(@as(usize, 0), operations(&module, "pick", .list_new));
    try std.testing.expectEqual(@as(usize, 0), operations(&module, "pick", .list_copy));
    _ = try @import("own.zig").run(a, &module, .{});
    try support.verified(a, &module, &.{});
}

/// How many instructions with `op` the functions named `name` hold.
fn operations(module: *const @import("ir.zig").Module, name: []const u8, op: @import("ir.zig").Op) usize {
    var count: usize = 0;
    for (module.functions.items) |function| {
        const local = if (std.mem.lastIndexOf(u8, function.name, "::")) |at| function.name[at + 2 ..] else function.name;
        if (!std.mem.eql(u8, local, name)) continue;
        for (function.insts.items) |inst| if (inst.op == op) {
            count += 1;
        };
    }
    return count;
}
