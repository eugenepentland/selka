//! The six idiom warnings (`syntax_hints.zig`): each fires on its shape, its fix gives code that checks, runs
//! the same and draws no warning, and a near miss draws none.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const fixture = @import("stdlib_fixture.zig");
const hints = @import("syntax_hints.zig");

const codes = [_][]const u8{ hints.byte_set_code, hints.range_chain_code, hints.literal_match_code, hints.pattern_shorthand_code, hints.option_try_code, hints.else_is_try_code };

/// One idiom warning as a test reads it: its place, its wording and the edits that repair it.
const Warning = struct { span: language.source.Span, message: []const u8, edits: []const language.diagnostic.Edit };

/// The warnings of `text` carrying `code`, or every idiom warning when `code` is empty; the arena owns them. A
/// program with no `main` is given an empty one.
fn warnings(arena: std.mem.Allocator, text: []const u8, code: []const u8) ![]const Warning {
    // A fixture needs an entry point; one appended after the text leaves every span of the text where it was.
    const program = if (std.mem.indexOf(u8, text, "func main") != null) text else try std.mem.concat(arena, u8, &.{ text, "\n\nfunc main() -> int:\n    return 0\n" });
    const report = try fixture.check(arena, program);
    try report.expectAccepted();
    var found: std.ArrayList(Warning) = .empty;
    for (report.diagnostics) |item| {
        if (code.len != 0 and !std.mem.eql(u8, item.code, code)) continue;
        if (code.len == 0 and !isIdiom(item.code)) continue;
        const fix = item.provenance.fix orelse return error.TestUnexpectedResult;
        const edits = try arena.alloc(language.diagnostic.Edit, fix.count());
        for (edits, 0..) |*edit, index| edit.* = fix.at(index);
        try found.append(arena, .{ .span = item.span, .message = item.message, .edits = edits });
    }
    return found.items;
}

fn isIdiom(code: []const u8) bool {
    for (codes) |known| if (std.mem.eql(u8, known, code)) return true;
    return false;
}

/// `text` with every edit of `item` applied. The fixtures are one module, so a merged-source span is a byte range.
fn repaired(arena: std.mem.Allocator, text: []const u8, item: Warning) ![]u8 {
    const edits = try arena.dupe(language.diagnostic.Edit, item.edits);
    std.mem.sort(language.diagnostic.Edit, edits, {}, later);
    var out = try arena.dupe(u8, text);
    for (edits) |edit| out = try std.mem.concat(arena, u8, &.{ out[0..edit.span.start], edit.text, out[edit.span.end..] });
    return out;
}

fn later(_: void, a: language.diagnostic.Edit, b: language.diagnostic.Edit) bool {
    return a.span.start > b.span.start;
}

/// Check that `text` draws exactly one `code` warning whose repair yields `expected`, that the result checks with
/// no idiom warning left, and return the repaired text.
fn expectRewrite(arena: std.mem.Allocator, text: []const u8, code: []const u8, expected: []const u8) ![]const u8 {
    const found = try warnings(arena, text, code);
    try t.expectEqual(@as(usize, 1), found.len);
    const fixed = try repaired(arena, text, found[0]);
    try t.expectEqualStrings(expected, fixed);
    const remaining = try warnings(arena, fixed, "");
    try t.expectEqual(@as(usize, 0), remaining.len);
    return fixed;
}

/// Check that none of `texts` draws an idiom warning.
fn expectQuiet(texts: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    for (texts) |text| {
        const found = try warnings(arena.allocator(), text, "");
        try t.expectEqual(@as(usize, 0), found.len);
    }
}

const byte_set_source =
    \\func sign(c: int) -> bool:
    \\    return c == 43 or c == 45 or 47 == c
    \\
    \\
    \\func main() -> int:
    \\    mut count = 0
    \\    for c in b"a+b-c/d*":
    \\        if sign(c):
    \\            count += 1
    \\    return count + 39
    \\
;

const byte_set_fixed =
    \\func sign(c: int) -> bool:
    \\    return c in b"+-/"
    \\
    \\
    \\func main() -> int:
    \\    mut count = 0
    \\    for c in b"a+b-c/d*":
    \\        if sign(c):
    \\            count += 1
    \\    return count + 39
    \\
;

// spec-case: SYNTAX-HINTS-1
test "an or-chain of byte equalities is a byte set, and the rewrite runs the same" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const fixed = try expectRewrite(arena.allocator(), byte_set_source, hints.byte_set_code, byte_set_fixed);
    try fixture.run(t.allocator, byte_set_source, 42);
    try fixture.run(t.allocator, fixed, 42);
}

// spec-case: SYNTAX-HINTS-1
test "a byte set run inside a longer chain keeps the other operands, escapes what is not printable and drops repeats" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    _ = try expectRewrite(arena.allocator(),
        \\func word(c: int, open: bool) -> bool:
        \\    return open or c == 32 or c == 10 or c == 34 or c == 92 or c == 10 or c == 0x7f or c > 200
        \\
    , hints.byte_set_code,
        \\func word(c: int, open: bool) -> bool:
        \\    return open or c in b' \n"\\\x7f' or c > 200
        \\
    );
}

// spec-case: SYNTAX-HINTS-1
test "equality tests that are not a plain byte set draw no byte-set warning" {
    try expectQuiet(&.{
        // two tests are below the threshold
        "func f(c: int) -> bool:\n    return c == 43 or c == 45\n",
        // different values are tested
        "func f(c: int, d: int) -> bool:\n    return c == 43 or d == 45 or c == 47\n",
        // an operand that is not a literal comparison separates the run
        "func f(c: int, d: int) -> bool:\n    return c == 43 or c == d or c == 47\n",
        // a literal above a byte
        "func f(c: int) -> bool:\n    return c == 43 or c == 45 or c == 300\n",
        // inequalities, and a call as the value, which is not plain
        "func f(c: int) -> bool:\n    return c != 43 or c != 45 or c != 47\n",
        "func g(c: int) -> int:\n    return c\n\n\nfunc f(c: int) -> bool:\n    return g(c) == 43 or g(c) == 45 or g(c) == 47\n",
        // an `and` chain is not a set
        "func f(c: int) -> bool:\n    return c == 43 and c == 45 and c == 47\n",
    });
}

const range_source =
    \\func digit(c: int) -> bool:
    \\    return c >= 48 and c <= 57
    \\
    \\
    \\func under(c: int, limit: int) -> bool:
    \\    return c > 0 and limit > c
    \\
    \\
    \\func main() -> int:
    \\    mut count = 0
    \\    for c in b"a1b22":
    \\        if digit(c) and under(c, 52):
    \\            count += 1
    \\    return count + 40
    \\
;

const range_fixed =
    \\func digit(c: int) -> bool:
    \\    return 48 <= c <= 57
    \\
    \\
    \\func under(c: int, limit: int) -> bool:
    \\    return 0 < c < limit
    \\
    \\
    \\func main() -> int:
    \\    mut count = 0
    \\    for c in b"a1b22":
    \\        if digit(c) and under(c, 52):
    \\            count += 1
    \\    return count + 40
    \\
;

// spec-case: SYNTAX-HINTS-2
test "two comparisons that bound a value from both sides are one chain, in either spelling" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try warnings(arena.allocator(), range_source, hints.range_chain_code);
    try t.expectEqual(@as(usize, 2), found.len);
    const once = try repaired(arena.allocator(), range_source, found[0]);
    const twice_found = try warnings(arena.allocator(), once, hints.range_chain_code);
    try t.expectEqual(@as(usize, 1), twice_found.len);
    const fixed = try repaired(arena.allocator(), once, twice_found[0]);
    try t.expectEqualStrings(range_fixed, fixed);
    try fixture.run(t.allocator, range_source, 43);
    try fixture.run(t.allocator, fixed, 43);
}

// spec-case: SYNTAX-HINTS-2
test "a lower and an upper bound beside other operands become a chain, keeping strictness" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    _ = try expectRewrite(arena.allocator(),
        \\func f(x: int, n: int, ready: bool) -> bool:
        \\    return ready and x >= n + 1 and x < n * 2 and x != 7
        \\
    , hints.range_chain_code,
        \\func f(x: int, n: int, ready: bool) -> bool:
        \\    return ready and n + 1 <= x < n * 2 and x != 7
        \\
    );
}

// spec-case: SYNTAX-HINTS-2
test "comparisons that do not bound one plain value from both sides draw no range warning" {
    try expectQuiet(&.{
        // two lower bounds
        "func f(x: int) -> bool:\n    return x >= 1 and x > 0\n",
        // two different values
        "func f(x: int, y: int) -> bool:\n    return x >= 1 and y <= 9\n",
        // an `or` is not a range
        "func f(x: int) -> bool:\n    return x < 1 or x > 9\n",
        // the value is a call
        "func g(x: int) -> int:\n    return x\n\n\nfunc f(x: int) -> bool:\n    return g(x) >= 1 and g(x) <= 9\n",
        // the bound is a call
        "func g(x: int) -> int:\n    return x\n\n\nfunc f(x: int) -> bool:\n    return x >= g(1) and x <= 9\n",
        // already a chain
        "func f(x: int) -> bool:\n    return 1 <= x <= 9\n",
        // no integer literal beside the value: a Simd comparison pair is lane-wise `and`, not a chain
        "func f(x: int, low: int, high: int) -> bool:\n    return x >= low and x <= high\n",
        "func f() -> bool:\n    const x = Simd[float, 4]([1.0, 2.0, 3.0, 4.0])\n    const lo = Simd[float, 4]([0.0, 0.0, 0.0, 0.0])\n" ++
            "    const hi = Simd[float, 4]([2.5, 2.5, 2.5, 2.5])\n    const inside: Simd[bool, 4] = (x > lo) and (x < hi)\n" ++
            "    return inside[0]\n",
    });
}

const match_source =
    \\func weight(x: int) -> int:
    \\    if x == 1:
    \\        return 10
    \\    elif x == 2:
    \\        const doubled = x * 10
    \\        return doubled
    \\    elif 3 == x:
    \\        return 30  # three
    \\    else:
    \\        return 0
    \\
    \\
    \\func main() -> int:
    \\    return weight(1) + weight(2) + weight(3) + weight(4) - 18
    \\
;

const match_fixed =
    \\func weight(x: int) -> int:
    \\    match x:
    \\        case 1:
    \\            return 10
    \\        case 2:
    \\            const doubled = x * 10
    \\            return doubled
    \\        case 3:
    \\            return 30  # three
    \\        case _:
    \\            return 0
    \\
    \\
    \\func main() -> int:
    \\    return weight(1) + weight(2) + weight(3) + weight(4) - 18
    \\
;

// spec-case: SYNTAX-HINTS-3
test "an if chain of literal tests is a literal match with the same arms and the same else" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const fixed = try expectRewrite(arena.allocator(), match_source, hints.literal_match_code, match_fixed);
    try fixture.run(t.allocator, match_source, 42);
    try fixture.run(t.allocator, fixed, 42);
}

// spec-case: SYNTAX-HINTS-3
test "a chain with no else gains an empty wildcard arm, and text literals match too" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    _ = try expectRewrite(arena.allocator(),
        \\func f(word: str) -> int:
        \\    mut total = 0
        \\    if word == "a":
        \\        total += 1
        \\    elif word == "b":
        \\        total += 2
        \\    elif word == "c":
        \\        total += 3
        \\    return total
        \\
    , hints.literal_match_code,
        \\func f(word: str) -> int:
        \\    mut total = 0
        \\    match word:
        \\        case "a":
        \\            total += 1
        \\        case "b":
        \\            total += 2
        \\        case "c":
        \\            total += 3
        \\        case _:
        \\            pass
        \\    return total
        \\
    );
}

// spec-case: SYNTAX-HINTS-3
test "chains that are not a plain literal match draw no match warning" {
    try expectQuiet(&.{
        // two tests are below the threshold
        "func f(x: int) -> int:\n    if x == 1:\n        return 1\n    elif x == 2:\n        return 2\n    return 0\n",
        // a second value
        "func f(x: int, y: int) -> int:\n    if x == 1:\n        return 1\n    elif y == 2:\n        return 2\n    elif x == 3:\n        return 3\n    return 0\n",
        // a repeated literal
        "func f(x: int) -> int:\n    if x == 1:\n        return 1\n    elif x == 2:\n        return 2\n    elif x == 1:\n        return 3\n    return 0\n",
        // a test that is not an equality
        "func f(x: int) -> int:\n    if x == 1:\n        return 1\n    elif x == 2:\n        return 2\n    elif x > 3:\n        return 3\n    return 0\n",
        // a comment between a body and the next test would be lost
        "func f(x: int) -> int:\n    if x == 1:\n        return 1\n    # two\n    elif x == 2:\n        return 2\n    elif x == 3:\n        return 3\n    return 0\n",
        // a call as the value
        "func g() -> int:\n    return 1\n\n\nfunc f() -> int:\n    if g() == 1:\n        return 1\n    elif g() == 2:\n        return 2\n    elif g() == 3:\n        return 3\n    return 0\n",
    });
}

// spec-case: SYNTAX-HINTS-3
test "chains on a value a literal arm is refused on draw no match warning: an Option, a str field or element, a float, a generic body" {
    try expectQuiet(&.{
        // `bytes?`, `str?` and `int?` have named cases, so `case b"net":` is E_LITERAL_ARM
        "func f(head: bytes?) -> int:\n    if head == b\"a\":\n        return 1\n    elif head == b\"b\":\n        return 2\n    elif head == b\"c\":\n        return 3\n    return 0\n",
        "func f(word: str?) -> int:\n    if word == \"a\":\n        return 1\n    elif word == \"b\":\n        return 2\n    elif word == \"c\":\n        return 3\n    return 0\n",
        "func f(n: int?) -> int:\n    if n == 1:\n        return 1\n    elif n == 2:\n        return 2\n    elif n == 3:\n        return 3\n    return 0\n",
        // an option record field
        "record Row:\n    tag: bytes?\n\n\nfunc f(row: Row) -> int:\n    if row.tag == b\"a\":\n        return 1\n    elif row.tag == b\"b\":\n        return 2\n    elif row.tag == b\"c\":\n        return 3\n    return 0\n",
        // Core refuses a literal match on a str field or element: it would copy the value
        "record Row:\n    name: str\n\n\nfunc f(row: Row) -> int:\n    if row.name == \"a\":\n        return 1\n    elif row.name == \"b\":\n        return 2\n    elif row.name == \"c\":\n        return 3\n    return 0\n",
        "func f(words: str[], i: int) -> int:\n    if words[i] == \"a\":\n        return 1\n    elif words[i] == \"b\":\n        return 2\n    elif words[i] == \"c\":\n        return 3\n    return 0\n",
        // a float is not matched on
        "func f(x: float) -> int:\n    if x == 1:\n        return 1\n    elif x == 2:\n        return 2\n    elif x == 3:\n        return 3\n    return 0\n",
        // a generic body checks no literal arm
        "func f[T](x: int, other: T) -> int:\n    _ = other\n    if x == 1:\n        return 1\n    elif x == 2:\n        return 2\n    elif x == 3:\n        return 3\n    return 0\n\n\nfunc main() -> int:\n    return f(1, 2)\n",
        // a chain that opens with an identity test is not a literal chain
        "func f(head: bytes?) -> int:\n    if head is None:\n        return 9\n    elif head == b\"a\":\n        return 1\n    elif head == b\"b\":\n        return 2\n    elif head == b\"c\":\n        return 3\n    return 0\n",
    });
}

// spec-case: SYNTAX-HINTS-1
test "an or-chain of byte tests on a float or an Option draws no byte-set warning, one on a byte or an int still does" {
    try expectQuiet(&.{
        // `value in b"..."` is refused on a `float` and on an `int?`
        "func f(c: float) -> bool:\n    return c == 43 or c == 45 or c == 47\n",
        "func f(c: int?) -> bool:\n    return c == 43 or c == 45 or c == 47\n",
        "record Row:\n    c: int?\n\n\nfunc f(row: Row) -> bool:\n    return row.c == 43 or row.c == 45 or row.c == 47\n",
    });
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const small = try warnings(arena.allocator(), "func f(c: u8) -> bool:\n    return c == 43 or c == 45 or c == 47\n", hints.byte_set_code);
    try t.expectEqual(@as(usize, 1), small.len);
}

// spec-case: SYNTAX-HINTS-3
test "a chain on an integer field and on a plain bytes still draws the match warning" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const number = try warnings(arena.allocator(),
        \\record Row:
        \\    kind: int
        \\
        \\
        \\func f(row: Row) -> int:
        \\    if row.kind == 1:
        \\        return 1
        \\    elif row.kind == 2:
        \\        return 2
        \\    elif row.kind == 3:
        \\        return 3
        \\    return 0
        \\
    , hints.literal_match_code);
    try t.expectEqual(@as(usize, 1), number.len);
    const text = try warnings(arena.allocator(),
        \\func f(head: bytes) -> int:
        \\    if head == b"a":
        \\        return 1
        \\    elif head == b"b":
        \\        return 2
        \\    elif head == b"c":
        \\        return 3
        \\    return 0
        \\
    , hints.literal_match_code);
    try t.expectEqual(@as(usize, 1), text.len);
}

const shorthand_source =
    \\enum Node:
    \\    text(value: str)
    \\    pair(left: int, right: int)
    \\    leaf
    \\
    \\
    \\func weight(node: Node) -> int:
    \\    match node:
    \\        case text(value=value):
    \\            return len(value)
    \\        case pair(left=left, right=right):
    \\            return left * 10 + right
    \\        case leaf:
    \\            return 0
    \\
    \\
    \\func main() -> int:
    \\    return weight(Node.text(value="abcd")) + weight(Node.pair(left=3, right=7)) + 1
    \\
;

const shorthand_fixed =
    \\enum Node:
    \\    text(value: str)
    \\    pair(left: int, right: int)
    \\    leaf
    \\
    \\
    \\func weight(node: Node) -> int:
    \\    match node:
    \\        case text(value):
    \\            return len(value)
    \\        case pair(left, right):
    \\            return left * 10 + right
    \\        case leaf:
    \\            return 0
    \\
    \\
    \\func main() -> int:
    \\    return weight(Node.text(value="abcd")) + weight(Node.pair(left=3, right=7)) + 1
    \\
;

// spec-case: SYNTAX-HINTS-4
test "a pattern field bound under its own name drops its label, one warning per arm" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try warnings(arena.allocator(), shorthand_source, hints.pattern_shorthand_code);
    try t.expectEqual(@as(usize, 2), found.len);
    try t.expectEqual(@as(usize, 1), found[0].edits.len);
    try t.expectEqual(@as(usize, 2), found[1].edits.len);
    const once = try repaired(arena.allocator(), shorthand_source, found[0]);
    const again = try warnings(arena.allocator(), once, hints.pattern_shorthand_code);
    const fixed = try repaired(arena.allocator(), once, again[0]);
    try t.expectEqualStrings(shorthand_fixed, fixed);
    try fixture.run(t.allocator, shorthand_source, 42);
    try fixture.run(t.allocator, fixed, 42);
}

// spec-case: SYNTAX-HINTS-4
test "a field bound under another name, discarded or already bare draws no shorthand warning" {
    try expectQuiet(&.{
        "enum Node:\n    pair(left: int, right: int)\n\n\nfunc f(node: Node) -> int:\n    match node:\n        case pair(left=l, right=_):\n            return l\n",
        "enum Node:\n    pair(left: int, right: int)\n\n\nfunc f(node: Node) -> int:\n    match node:\n        case pair(left, right):\n            return left + right\n",
    });
}

const nested_shorthand_source =
    \\enum Item:
    \\    item(value: int, note: str)
    \\    empty
    \\
    \\
    \\enum Stamp:
    \\    stamp(value: int, note: str)
    \\
    \\
    \\enum Wrap:
    \\    one(inner: Stamp, tag: int)
    \\
    \\
    \\func score(found: Item?) -> int:
    \\    match found:
    \\        case Some(item(value=value, note=note)):
    \\            return value + len(note)
    \\        case Some(empty):
    \\            return 0
    \\        case None:
    \\            return -1
    \\
    \\
    \\func weigh(box: Wrap) -> int:
    \\    match box:
    \\        case one(inner=stamp(value=value, note=note), tag=tag):
    \\            return value + len(note) + tag
    \\
    \\
    \\func main() -> int:
    \\    return score(Some(Item.item(value=3, note="ab"))) + weigh(Wrap.one(inner=Stamp.stamp(value=4, note="c"), tag=10))
    \\
;

// spec-case: SYNTAX-HINTS-4
test "a field of a nested pattern keeps its label, the checker refuses the bare form there, and a field of the arm itself still drops it" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    // `case Some(item(value, note))` is `E_NAMED_PATTERN`, so the nested labels are no finding; only `tag=tag` is one.
    const found = try warnings(arena.allocator(), nested_shorthand_source, hints.pattern_shorthand_code);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqual(@as(usize, 1), found[0].edits.len);
    const fixed = try repaired(arena.allocator(), nested_shorthand_source, found[0]);
    try t.expect(std.mem.indexOf(u8, fixed, "case one(inner=stamp(value=value, note=note), tag):") != null);
    try t.expect(std.mem.indexOf(u8, fixed, "case Some(item(value=value, note=note)):") != null);
    const again = try warnings(arena.allocator(), fixed, hints.pattern_shorthand_code);
    try t.expectEqual(@as(usize, 0), again.len);
    try fixture.run(t.allocator, nested_shorthand_source, 20);
    try fixture.run(t.allocator, fixed, 20);
}

const try_source =
    \\func first(values: int[]) -> int?:
    \\    if len(values) == 0:
    \\        return None
    \\    return values[0]
    \\
    \\
    \\func second(values: int[]) -> int?:
    \\    if len(values) < 2:
    \\        return None
    \\    return values[1]
    \\
    \\
    \\func total(values: int[]) -> int?:
    \\    match first(values):
    \\        case Some(a):
    \\            match second(values):
    \\                case Some(b):
    \\                    return a + b
    \\                case None:
    \\                    return None
    \\        case None:
    \\            return None
    \\
    \\
    \\func main() -> int:
    \\    match total([40, 2]):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 1
    \\
;

const try_fixed =
    \\func first(values: int[]) -> int?:
    \\    if len(values) == 0:
    \\        return None
    \\    return values[0]
    \\
    \\
    \\func second(values: int[]) -> int?:
    \\    if len(values) < 2:
    \\        return None
    \\    return values[1]
    \\
    \\
    \\func total(values: int[]) -> int?:
    \\    const a = try first(values)
    \\    const b = try second(values)
    \\    return a + b
    \\
    \\
    \\func main() -> int:
    \\    match total([40, 2]):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 1
    \\
;

// spec-case: SYNTAX-HINTS-5
test "an Option match whose None arm only returns None is a try, and nested ones settle over rounds" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try warnings(arena.allocator(), try_source, hints.option_try_code);
    try t.expectEqual(@as(usize, 2), found.len);
    const once = try repaired(arena.allocator(), try_source, found[0]);
    const fixed = try expectRewrite(arena.allocator(), once, hints.option_try_code, try_fixed);
    try fixture.run(t.allocator, try_source, 42);
    try fixture.run(t.allocator, fixed, 42);
}

// spec-case: SYNTAX-HINTS-5
test "an Option match that does more than return None, or sits elsewhere, draws no try warning" {
    try expectQuiet(&.{
        // the None arm does something first
        "func first(values: int[]) -> int?:\n    return None\n\n\nfunc f(values: int[]) -> int?:\n    match first(values):\n" ++
            "        case Some(a):\n            return a\n        case None:\n            const unused = 1\n            return None\n",
        // the None arm returns another value
        "func first(values: int[]) -> int?:\n    return None\n\n\nfunc f(values: int[]) -> int?:\n    match first(values):\n" ++
            "        case Some(a):\n            return Some(a)\n        case None:\n            return Some(0)\n",
        // code follows the match
        "func first(values: int[]) -> int?:\n    return None\n\n\nfunc f(values: int[]) -> int?:\n    mut total = 0\n" ++
            "    match first(values):\n        case Some(a):\n            total = a\n        case None:\n            return None\n" ++
            "    return Some(total)\n",
        // the function does not return an Option
        "func first(values: int[]) -> int?:\n    return None\n\n\nfunc f(values: int[]) -> int:\n    match first(values):\n" ++
            "        case Some(a):\n            return a\n        case None:\n            return 0\n",
        // the value is a local, not a fresh result
        "func f(values: int?) -> int?:\n    match values:\n        case Some(a):\n            return Some(a + 1)\n        case None:\n            return None\n",
    });
}

// spec-case: SYNTAX-HINTS-6
test "a reasoned waiver comment above a site silences its idiom warning" {
    try expectQuiet(&.{
        "func f(c: int) -> bool:\n    # lint: allow byte-set reason=\"the tests mirror the grammar's alternatives\"\n    return c == 43 or c == 45 or c == 47\n",
        "func f(c: int) -> bool:\n    # lint: allow range-chain reason=\"two separate conditions in the spec\"\n    return c >= 48 and c <= 57\n",
    });
}

// spec-case: SYNTAX-HINTS-6
test "a file-level waiver silences a rule for the whole file and no other rule" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text =
        \\# lint: allow-file byte-set reason="the tests mirror the grammar's alternatives"
        \\func a(c: int) -> bool:
        \\    return c == 43 or c == 45 or c == 47
        \\
        \\
        \\func b(c: int) -> bool:
        \\    return c == 1 or c == 2 or c == 3
        \\
        \\
        \\func d(c: int) -> bool:
        \\    return c >= 48 and c <= 57
        \\
    ;
    try t.expectEqual(@as(usize, 0), (try warnings(arena.allocator(), text, hints.byte_set_code)).len);
    try t.expectEqual(@as(usize, 1), (try warnings(arena.allocator(), text, hints.range_chain_code)).len);
}

/// `text` with the first `code` warning repaired, over and over until none is left.
fn repairedAll(arena: std.mem.Allocator, text: []const u8, code: []const u8) ![]const u8 {
    var fixed = text;
    for (0..8) |_| {
        const left = try warnings(arena, fixed, code);
        if (left.len == 0) return fixed;
        fixed = try repaired(arena, fixed, left[0]);
    }
    return error.TestUnexpectedResult;
}

const else_source =
    \\func read(n: int) -> int[] fails str:
    \\    if n < 0:
    \\        fail "negative"
    \\    return [n, n + 1]
    \\
    \\
    \\func lookup(n: int) -> int?:
    \\    if n == 0:
    \\        return None
    \\    return Some(n)
    \\
    \\
    \\func total(n: int) -> int[] fails str:
    \\    const items = read(n) else Err(message):
    \\        fail message
    \\    return items
    \\
    \\
    \\func twice(n: int) -> int?:
    \\    mut value = lookup(n) else:
    \\        return None
    \\    value += 1
    \\    return value
    \\
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

const else_fixed =
    \\func read(n: int) -> int[] fails str:
    \\    if n < 0:
    \\        fail "negative"
    \\    return [n, n + 1]
    \\
    \\
    \\func lookup(n: int) -> int?:
    \\    if n == 0:
    \\        return None
    \\    return Some(n)
    \\
    \\
    \\func total(n: int) -> int[] fails str:
    \\    const items = try read(n)
    \\    return items
    \\
    \\
    \\func twice(n: int) -> int?:
    \\    mut value = try lookup(n)
    \\    value += 1
    \\    return value
    \\
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

// spec-case: SYNTAX-HINTS-8
test "a bind-or-else whose else block only passes the failure on is a try, and the rewrite checks" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const found = try warnings(a, else_source, hints.else_is_try_code);
    try t.expectEqual(@as(usize, 2), found.len);
    try t.expect(std.mem.indexOf(u8, found[0].message, "`try read(n)`") != null);
    const fixed = try repairedAll(a, else_source, hints.else_is_try_code);
    try t.expectEqualStrings(else_fixed, fixed);
    try t.expectEqual(@as(usize, 0), (try warnings(a, fixed, "")).len);
}

// spec-case: SYNTAX-HINTS-8
test "a bind-or-else that does anything else in its else block draws no try hint" {
    try expectQuiet(&.{
        \\func read(n: int) -> int[] fails str:
        \\    if n < 0:
        \\        fail "negative"
        \\    return [n]
        \\
        \\
        \\func report(n: int) -> int[] fails str:
        \\    const items = read(n) else Err(message):
        \\        fail "read failed"
        \\    return items
        \\
        \\
        \\func discard(n: int) -> int[] fails str:
        \\    const items = read(n) else Err(_):
        \\        fail "read failed"
        \\    return items
        \\
        \\
        \\func status(n: int) -> int:
        \\    const items = read(n) else Err(message):
        \\        return len(message)
        \\    return len(items)
        \\
        ,
        \\func lookup(n: int) -> int?:
        \\    if n == 0:
        \\        return None
        \\    return Some(n)
        \\
        \\
        \\func zero(n: int) -> int:
        \\    const value = lookup(n) else:
        \\        return 0
        \\    return value
        \\
        \\
        \\func both(n: int) -> int?:
        \\    const value = lookup(n) else:
        \\        # nothing to add here
        \\        return None
        \\    return value
        \\
    });
}

/// `text` with the first warning of any of `wanted` repaired, over and over until none is left, as rounds of
/// `selka fix` would apply them one statement at a time.
fn flattened(arena: std.mem.Allocator, text: []const u8, wanted: []const []const u8) ![]const u8 {
    var fixed = text;
    for (0..12) |_| {
        var next: ?Warning = null;
        for (wanted) |code| {
            const left = try warnings(arena, fixed, code);
            if (left.len != 0) {
                next = left[0];
                break;
            }
        }
        fixed = try repaired(arena, fixed, next orelse return fixed);
    }
    return error.TestUnexpectedResult;
}

const unwrap_codes = [_][]const u8{ hints.match_else_code, hints.match_is_code, hints.else_is_try_code };

/// Check that `text` flattens to `expected` and that both programs exit with `status`.
fn expectFlat(text: []const u8, expected: []const u8, status: i64) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const fixed = try flattened(arena.allocator(), text, &unwrap_codes);
    try t.expectEqualStrings(expected, fixed);
    try fixture.run(t.allocator, text, status);
    try fixture.run(t.allocator, fixed, status);
}

/// Check that none of `texts` draws `W_MATCH_ELSE` or `W_MATCH_IS`.
fn expectNoUnwrap(texts: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    for (texts) |text| {
        try t.expectEqual(@as(usize, 0), (try warnings(arena.allocator(), text, hints.match_else_code)).len);
        try t.expectEqual(@as(usize, 0), (try warnings(arena.allocator(), text, hints.match_is_code)).len);
    }
}

const unwrap_prelude =
    \\func half(n: int) -> int?:
    \\    if n % 2 != 0:
    \\        return None
    \\    return Some(n // 2)
    \\
    \\
    \\func names(n: int) -> str[]?:
    \\    if n == 0:
    \\        return None
    \\    return Some(["a", "b"])
    \\
    \\
    \\func parse(n: int) -> int fails str:
    \\    if n < 0:
    \\        fail "negative"
    \\    return n
    \\
    \\
;

// spec-case: SYNTAX-HINTS-9
test "an unwrapping match in a loop, in a match mut arm, over a method call and moving its payload flattens and runs the same" {
    // The call the match reads is `strings.decode` now (W13-S5), which needs `import strings`.
    try expectFlat("import strings\n\n" ++ unwrap_prelude ++
        \\func loop(limit: int) -> int:
        \\    mut found = 0
        \\    mut n = 0
        \\    while n < limit:
        \\        n += 1
        \\        match half(n):
        \\            case Some(h):
        \\                found += h
        \\            case None:
        \\                continue
        \\        if found > 6:
        \\            break
        \\    return found
        \\
        \\
        \\func inner(mut slot: int?) -> int:
        \\    mut total = 0
        \\    match mut slot:
        \\        case Some(v):
        \\            v += 1
        \\            match half(v):
        \\                case Some(h):
        \\                    total = h
        \\                case None:
        \\                    return -1
        \\        case None:
        \\            pass
        \\    return total
        \\
        \\
        \\func moved(n: int) -> int:
        \\    mut kept: str[][] = []
        \\    match names(n):
        \\        case Some(items):
        \\            append(mut kept, own items)
        \\        case None:
        \\            return 0
        \\    const text = strings.encode("ab")
        \\    match strings.decode(text):
        \\        case Ok(value):
        \\            return len(kept) + len(value)
        \\        case Err(_):
        \\            return -1
        \\
        \\
        \\func main() -> int:
        \\    mut slot: int? = Some(3)
        \\    return loop(9) + inner(mut slot) * 10 + moved(1) * 100
        \\
    , "import strings\n\n" ++ unwrap_prelude ++
        \\func loop(limit: int) -> int:
        \\    mut found = 0
        \\    mut n = 0
        \\    while n < limit:
        \\        n += 1
        \\        const h = half(n) else:
        \\            continue
        \\        found += h
        \\        if found > 6:
        \\            break
        \\    return found
        \\
        \\
        \\func inner(mut slot: int?) -> int:
        \\    mut total = 0
        \\    match mut slot:
        \\        case Some(v):
        \\            v += 1
        \\            const h = half(v) else:
        \\                return -1
        \\            total = h
        \\        case None:
        \\            pass
        \\    return total
        \\
        \\
        \\func moved(n: int) -> int:
        \\    mut kept: str[][] = []
        \\    const items = names(n) else:
        \\        return 0
        \\    append(mut kept, own items)
        \\    const text = strings.encode("ab")
        \\    const value = strings.decode(text) else Err(_):
        \\        return -1
        \\    return len(kept) + len(value)
        \\
        \\
        \\func main() -> int:
        \\    mut slot: int? = Some(3)
        \\    return loop(9) + inner(mut slot) * 10 + moved(1) * 100
        \\
    , 10 + 20 + 300);
}

// spec-case: SYNTAX-HINTS-9
test "an unwrapping match in a function that fails flattens to else Err(e) and then to try" {
    try expectFlat(unwrap_prelude ++
        \\func total(n: int) -> int fails str:
        \\    match parse(n):
        \\        case Ok(value):
        \\            return value + 1
        \\        case Err(e):
        \\            fail e
        \\
        \\
        \\func main() -> int:
        \\    const value = total(4) else Err(_):
        \\        return 1
        \\    return value
        \\
    , unwrap_prelude ++
        \\func total(n: int) -> int fails str:
        \\    const value = try parse(n)
        \\    return value + 1
        \\
        \\
        \\func main() -> int:
        \\    const value = total(4) else Err(_):
        \\        return 1
        \\    return value
        \\
    , 5);
}

// spec-case: SYNTAX-HINTS-9
test "a success arm that does nothing tests the failure case, and the arm that leaves keeps its block" {
    try expectFlat(unwrap_prelude ++
        \\func odd(n: int) -> int:
        \\    match half(n):
        \\        case Some(_):
        \\            pass
        \\        case None:
        \\            return 1
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return odd(3) * 10 + odd(4)
        \\
    , unwrap_prelude ++
        \\func odd(n: int) -> int:
        \\    if half(n) is None:
        \\        return 1
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return odd(3) * 10 + odd(4)
        \\
    , 10);
}

// spec-case: SYNTAX-HINTS-9
test "an unwrapping match whose names would collide with the statements after it, or whose text cannot move, draws no warning" {
    try expectNoUnwrap(&.{
        // a later bind-or-else binds the name the success arm binds
        unwrap_prelude ++ "func f(n: int) -> int:\n    mut total = 0\n    match half(n):\n        case Some(h):\n            total = h\n" ++
            "        case None:\n            return 0\n    const h = half(total) else:\n        return 1\n    return h\n",
        // a later inner block declares a name the success arm declares
        unwrap_prelude ++ "func f(n: int) -> int:\n    mut total = 0\n    match half(n):\n        case Some(h):\n            const twice = h * 2\n" ++
            "            total = twice\n        case None:\n            return 0\n    if total > 2:\n        const twice = total\n        total = twice + 1\n    return total\n",
        // the success arm's own bind-or-else declares, after it, a name the statements after the match declare
        unwrap_prelude ++ "func f(n: int) -> int:\n    mut total = 0\n    match half(n):\n        case Some(h):\n            const k = half(h) else:\n" ++
            "                return 2\n            const deeper = k\n            total = deeper\n        case None:\n            return 0\n" ++
            "    for deeper in range(2):\n        total += deeper\n    return total\n",
        // a comment line between the arms would be lost
        unwrap_prelude ++ "func f(n: int) -> int:\n    match half(n):\n        case Some(h):\n            return h\n    # the odd case\n" ++
            "        case None:\n            return 0\n",
        // a body line shallower than the body (a continuation inside brackets)
        unwrap_prelude ++ "func f(n: int) -> int:\n    match half(n):\n        case Some(h):\n            return max(h,\n          1)\n" ++
            "        case None:\n            return 0\n",
        // `match own` cannot become an `is` test, and both arms doing nothing is no shape
        unwrap_prelude ++ "func f(n: int) -> int:\n    const items = names(n)\n    match own items:\n        case Some(value):\n" ++
            "            return len(value)\n        case None:\n            pass\n    return 0\n",
        unwrap_prelude ++ "func f(n: int) -> int:\n    match half(n):\n        case Some(_):\n            pass\n        case None:\n            pass\n    return 0\n",
    });
}

// spec-case: SYNTAX-HINTS-8
test "a bind-or-else over a borrowed place draws no try hint, since try would take the payload (FR20)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text =
        \\func lookup(x: str[]?) -> int?:
        \\    const items = x else:
        \\        return None
        \\    return Some(len(items))
        \\
    ;
    try t.expectEqual(@as(usize, 0), (try warnings(arena.allocator(), text, hints.else_is_try_code)).len);
}
