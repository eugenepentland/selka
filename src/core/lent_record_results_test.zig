//! H3 for records (lane OC, plan Part B stage O3): the record a `from` function returns is lent where the field it returns
//! would be, so a local record, list, dictionary or option may hold it with the call's sources as its owners. Its escapes keep
//! the refusals a borrowed record has: a return without `from` (R4), a store into a list or a `mut` parameter that leaves or
//! into an owning record (R3), and a change of an owner while the record is live (R3, reported at the constructor as for any
//! borrowed record). Guest behaviour is `tests/lang/lent_record_results.selka`. The tests assert codes, rules and lines, not
//! message text, which lane OD's O2 shapes.
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
    \\    first: Item
    \\    n: int
    \\
    \\record ItemBox:
    \\    value: Item
    \\
    \\func first_of(shelf: Shelf) -> Item from shelf:
    \\    return shelf.first
    \\
    \\func keep(own box: ItemBox) -> int:
    \\    return 0
    \\
    \\
;

/// The line the prelude ends on: a refusal's line in a case is this plus its line in the case.
const prelude_lines = std.mem.count(u8, prelude, "\n");

/// `source` is refused with `code` under `rule` at line `line` of the case (1-based).
fn refuses(backing: std.mem.Allocator, source: []const u8, code: []const u8, rule: language.ownership_rules.Rule, line: usize) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    const text = try std.mem.concat(a, u8, &.{ prelude, source, "\nfunc main() -> int:\n    return 0\n" });
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expectEqual(rule, failure.rule.?);
    try std.testing.expectEqual(prelude_lines + line, std.mem.count(u8, text[0..failure.span.start], "\n") + 1);
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

test "H3 a from function's record result is lent into a local record, list, dictionary or option, and returns under from" {
    try accepts(std.testing.allocator,
        \\func local_uses(shelf: Shelf) -> int:
        \\    const box = ItemBox(value=first_of(shelf))
        \\    mut list: Item[] = []
        \\    append(mut list, first_of(shelf))
        \\    mut table: dict[int, Item] = {}
        \\    table[1] = first_of(shelf)
        \\    const held: Item? = Some(first_of(shelf))
        \\    return box.value.count + len(list) + len(table)
        \\
        \\func boxed(shelf: Shelf) -> ItemBox from shelf:
        \\    return ItemBox(value=first_of(shelf))
        \\
        \\func main() -> int:
        \\    const shelf = Shelf(first=Item(name="a", count=1), n=1)
        \\    return local_uses(shelf) + boxed(shelf).value.count
        \\
    );
}

test "H3 a record of a from result returned without from is refused at the return (R4)" {
    try refuses(std.testing.allocator,
        \\func f(shelf: Shelf) -> ItemBox:
        \\    const box = ItemBox(value=first_of(shelf))
        \\    return box
    , "E_BORROW_UNDECLARED", .R4, 3);
}

test "H3 a from result stored into a list that leaves, a mut parameter, or an owning argument is refused (R3)" {
    try refuses(std.testing.allocator,
        \\func f(shelf: Shelf) -> Item[]:
        \\    mut held: Item[] = []
        \\    append(mut held, first_of(shelf))
        \\    return held
    , "E_SINGLE_OWNER_BORROW", .R3, 3);
    try refuses(std.testing.allocator,
        \\func f(shelf: Shelf, mut out: Item[]) -> int:
        \\    append(mut out, first_of(shelf))
        \\    return len(out)
    , "E_SINGLE_OWNER_BORROW", .R3, 2);
    try refuses(std.testing.allocator,
        \\func f(shelf: Shelf, mut mr: ItemBox) -> int:
        \\    mr.value = first_of(shelf)
        \\    return 0
    , "E_SINGLE_OWNER_BORROW", .R3, 2);
    try refuses(std.testing.allocator,
        \\func f(shelf: Shelf) -> int:
        \\    const box = ItemBox(value=first_of(shelf))
        \\    return keep(box)
    , "E_SINGLE_OWNER_BORROW", .R3, 2);
}

test "H3 an owner of a lent from result cannot change while the record that holds it is live (R3 at the constructor)" {
    try refuses(std.testing.allocator,
        \\func f(n: int) -> int:
        \\    mut shelf = Shelf(first=Item(name=f"a{n}", count=n), n=n)
        \\    const box = ItemBox(value=first_of(shelf))
        \\    shelf.first = Item(name="x", count=1)
        \\    return box.value.count
    , "E_SINGLE_OWNER_BORROW", .R3, 3);
}
