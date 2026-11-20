//! H2 (lane OC, plan Part B stage O3): a `const` option local of `Some(place)` is an option of a borrow, as a record of one is
//! (1A). Its escapes are refused where the option goes, with the code and rule a borrowed `const` gets: a return without
//! `from` (R4), a store into a returned record, an `own` argument or a list that leaves (B9), and a change or move of the lender
//! while the option is live (R2). Guest behaviour is `tests/lang/lent_option_locals.selka`. The tests assert codes, rules and
//! lines, not message text, which lane OD's O2 shapes.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");

const prelude =
    \\record Shelf:
    \\    label: str
    \\    n: int
    \\
    \\record Holder:
    \\    value: str?
    \\
    \\func keep(own value: str?) -> int:
    \\    return 0
    \\
    \\func read(value: str?) -> int:
    \\    return 0
    \\
    \\func my_take(own shelf: Shelf) -> int:
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

test "H2 a const Some(place) local borrows a field, an owner or a parameter, and returns under from" {
    try accepts(std.testing.allocator,
        \\func of_field(shelf: Shelf) -> int:
        \\    const s: str? = Some(shelf.label)
        \\    return read(s)
        \\
        \\func of_owner(n: int) -> int:
        \\    const label = f"a{n}"
        \\    const s: str? = Some(label)
        \\    return read(s)
        \\
        \\func of_text(label: str) -> int:
        \\    const s: str? = Some(label)
        \\    return read(s)
        \\
        \\func lent(shelf: Shelf) -> str? from shelf:
        \\    const s: str? = Some(shelf.label)
        \\    return s
        \\
        \\func main() -> int:
        \\    const shelf = Shelf(label="ab", n=1)
        \\    return of_field(shelf) + of_owner(2) + of_text("x") + read(lent(shelf))
        \\
    );
}

test "H2 a lent option returned without from is refused at the return (R4)" {
    try refuses(std.testing.allocator,
        \\func f(shelf: Shelf) -> str?:
        \\    const s: str? = Some(shelf.label)
        \\    return s
    , "E_BORROW_UNDECLARED", .R4, 3);
}

test "H2 a lent option stored in a returned record, given to an own parameter or appended to a list that leaves is refused there (B9)" {
    try refuses(std.testing.allocator,
        \\func f(shelf: Shelf) -> Holder:
        \\    const s: str? = Some(shelf.label)
        \\    return Holder(value=s)
    , "E_OWN_MARKER", .B9, 3);
    try refuses(std.testing.allocator,
        \\func f(shelf: Shelf) -> int:
        \\    const s: str? = Some(shelf.label)
        \\    return keep(s)
    , "E_OWN_MARKER", .B9, 3);
    try refuses(std.testing.allocator,
        \\func f(shelf: Shelf) -> int:
        \\    const s: str? = Some(shelf.label)
        \\    return keep(own s)
    , "E_OWN_MARKER", .B9, 3);
    try refuses(std.testing.allocator,
        \\func f(shelf: Shelf, mut out: str?[]) -> int:
        \\    const s: str? = Some(shelf.label)
        \\    append(mut out, s)
        \\    return len(out)
    , "E_OWN_MARKER", .B9, 3);
}

test "H2 the lender of a lent option cannot change or move while the option is live (R2)" {
    try refuses(std.testing.allocator,
        \\func f(n: int) -> int:
        \\    mut shelf = Shelf(label=f"a{n}", n=n)
        \\    const s: str? = Some(shelf.label)
        \\    shelf.label = "x"
        \\    return read(s)
    , "E_SINGLE_OWNER_OVERLAP", .R2, 4);
    try refuses(std.testing.allocator,
        \\func f(n: int) -> int:
        \\    const shelf = Shelf(label=f"a{n}", n=n)
        \\    const s: str? = Some(shelf.label)
        \\    const gone = my_take(own shelf)
        \\    return read(s) + gone
    , "E_SINGLE_OWNER_OVERLAP", .R2, 4);
}

test "H2 a capability is a shared handle, not a lent payload: an option local of one keeps its copy and lowers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\import filesystem
        \\
        \\func main() -> int:
        \\    const fs = filesystem.memory()
        \\    const held: Filesystem? = Some(fs)
        \\    match held:
        \\        case Some(inner):
        \\            if inner.exists("ready"):
        \\                return 1
        \\        case None:
        \\            return 2
        \\    return 0
    ;
    const checked = try support.checkedProgram(a, source);
    var failure: unique.Failure = .{};
    try unique.check(a, checked, &failure);
    try std.testing.expectEqualStrings("", failure.code);
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    var text: std.ArrayList(u8) = .empty;
    try @import("verify_ir.zig").check(a, &module, &.{}, &text);
    try std.testing.expectEqualStrings("", text.items);
}
