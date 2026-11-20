//! `const x = f() else FAILURE:`: what it refuses and how. The accepted forms are the guest tests in `tests/lang/bind_or_else.selka`.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

const header =
    \\func read(n: int) -> int[] fails str:
    \\    if n < 0:
    \\        fail "negative"
    \\    return [n]
    \\
    \\
    \\func lookup(n: int) -> int?:
    \\    if n == 0:
    \\        return None
    \\    return Some(n)
    \\
    \\
    \\enum Shade:
    \\    light
    \\    dark
    \\    grey
    \\
    \\
;

/// The first diagnostic of `header` followed by `body`, and the source text its span covers.
fn first(arena: std.mem.Allocator, body: []const u8) !struct { []const u8, []const u8, []const u8 } {
    const text = try std.fmt.allocPrint(arena, "{s}{s}\n\n\nfunc main() -> int:\n    return 0\n", .{ header, body });
    const report = try fixture.check(arena, text);
    const found = report.firstError() orelse return error.TestUnexpectedResult;
    return .{ found.code, found.message, report.text(found.span) };
}

// spec-case: BIND-OR-ELSE-1
test "an else block that can continue is refused at its last statement" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const falls = try first(a, "func f(n: int) -> int:\n    const items = read(n) else Err(message):\n        const size = len(message)\n    return len(items)");
    try t.expectEqualStrings("E_ELSE_FALLTHROUGH", falls[0]);
    try t.expect(std.mem.indexOf(u8, falls[1], "must leave the enclosing block") != null);
    try t.expect(std.mem.indexOf(u8, falls[1], "to handle the failure and go on, write `if CALL is Err(e):` (`is None` for an Option) or a `match` with an arm for each case") != null);
    try t.expectEqualStrings("const size = len(message)", falls[2]);
    const half = try first(a, "func f(n: int) -> int:\n    const value = lookup(n) else:\n        if n > 5:\n            return 1\n    return value");
    try t.expectEqualStrings("E_ELSE_FALLTHROUGH", half[0]);
    const empty = try first(a, "func f(n: int) -> int:\n    const value = lookup(n) else:\n        pass\n    return value");
    try t.expectEqualStrings("E_ELSE_FALLTHROUGH", empty[0]);
}

// The message of a block that can continue names the two ways to handle a failure and go on; they are accepted for a call that
// gives nothing back (`store` below), for a Result and for an Option.
test "the forms that the else-fallthrough message names to handle a failure and go on are accepted" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const body = "func store(n: int) fails str:\n    if n < 0:\n        fail \"negative\"\n\n\nfunc f(n: int, mut failed: bool) -> int:\n";
    const forms = [_][]const u8{
        "    if store(n) is Err(e):\n        failed = len(e) > 0\n    return 0",
        "    match store(n):\n        case Ok(_):\n            failed = False\n        case Err(_):\n            failed = True\n    return 0",
        "    if lookup(n) is None:\n        failed = True\n    return 0",
    };
    for (forms) |form| {
        const text = try std.fmt.allocPrint(a, "{s}{s}{s}\n\n\nfunc main() -> int:\n    return 0\n", .{ header, body, form });
        try t.expect((try fixture.check(a, text)).firstError() == null);
    }
}

// spec-case: BIND-OR-ELSE-2
test "only an Option or a Result can be unwrapped, and only by its failing case" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const number = try first(a, "func f(n: int) -> int:\n    const value = n else:\n        return 1\n    return value");
    try t.expectEqualStrings("E_ELSE_OPERAND", number[0]);
    const shade = try first(a, "func f(s: Shade) -> int:\n    const value = s else:\n        return 1\n    return 0");
    try t.expectEqualStrings("E_ELSE_OPERAND", shade[0]);
    const ok = try first(a, "func f(n: int) -> int:\n    const items = read(n) else Ok(items):\n        return 1\n    return 0");
    try t.expectEqualStrings("E_ELSE_PATTERN", ok[0]);
    const some = try first(a, "func f(n: int) -> int:\n    const value = lookup(n) else Some(value):\n        return 1\n    return 0");
    try t.expectEqualStrings("E_ELSE_PATTERN", some[0]);
    const bare_err = try first(a, "func f(n: int) -> int:\n    const items = read(n) else Err:\n        return 1\n    return 0");
    try t.expectEqualStrings("E_ELSE_PATTERN", bare_err[0]);
    const two = try first(a, "func f(n: int) -> int:\n    const items = read(n) else Err(a, b):\n        return 1\n    return 0");
    try t.expectEqualStrings("E_ELSE_PATTERN", two[0]);
    const rest = try first(a, "func f(n: int) -> int:\n    const items = read(n) else Err(..):\n        return 1\n    return 0");
    try t.expectEqualStrings("E_ELSE_PATTERN", rest[0]);
    try t.expect(std.mem.indexOf(u8, rest[1], "`Err(e)`, `Err(_)` or `None`") != null);
}

// spec-case: BIND-OR-ELSE-3
test "the success name is not visible in the else block and the failure name is not visible after it" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const success = try first(a, "func f(n: int) -> int:\n    const items = read(n) else Err(message):\n        return len(items)\n    return 0");
    try t.expectEqualStrings("E_UNKNOWN_NAME", success[0]);
    const failure = try first(a, "func f(n: int) -> int:\n    const items = read(n) else Err(message):\n        return 1\n    return len(message)");
    try t.expectEqualStrings("E_UNKNOWN_NAME", failure[0]);
    const operand = try first(a, "func f(n: int) -> int:\n    const items = read(len(items)) else Err(_):\n        return 1\n    return 0");
    try t.expectEqualStrings("E_UNKNOWN_NAME", operand[0]);
    const shadow = try first(a, "func f(n: int) -> int:\n    const items = [1]\n    const items = read(n) else Err(_):\n        return 1\n    return 0");
    try t.expectEqualStrings("E_SHADOWING", shadow[0]);
    const failure_shadow = try first(a, "func f(n: int) -> int:\n    const message = 1\n    const items = read(n) else Err(message):\n        return 1\n    return 0");
    try t.expectEqualStrings("E_SHADOWING", failure_shadow[0]);
}

// spec-case: BIND-OR-ELSE-4
test "a diagnostic in a later statement keeps its own span" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const later = try first(a, "func f(n: int) -> int:\n    const items = read(n) else Err(_):\n        return 1\n    const text: str = len(items)\n    return 0");
    try t.expectEqualStrings("E_TYPE", later[0]);
    try t.expectEqualStrings("str", later[2]);
    const after_second = try first(a, "func f(n: int) -> int:\n    const items = read(n) else Err(_):\n        return 1\n    const value = lookup(n) else:\n        return 2\n    return undefined_name");
    try t.expectEqualStrings("E_UNKNOWN_NAME", after_second[0]);
    try t.expectEqualStrings("undefined_name", after_second[2]);
}

// spec-case: BIND-OR-ELSE-5
test "an unused name warns once, at its own declaration, and the failure name is the else block's" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const plain = "func plain(n: int) -> int:\n    const items = read(n) else Err(message):\n        return len(message)\n    return 0\n\n\n";
    const writable = "func writable(n: int) -> int:\n    mut items = read(n) else Err(_):\n        return 1\n    return 0\n\n\n";
    const entry = "func main() -> int:\n    return plain(1) + writable(2)\n";
    const text = try std.mem.concat(a, u8, &.{ header, plain, writable, entry });
    const report = try fixture.check(a, text);
    var spans: std.ArrayList([]const u8) = .empty;
    for (report.diagnostics) |item| {
        if (std.mem.eql(u8, item.code, "W_UNUSED_BINDING")) try spans.append(a, report.text(item.span));
    }
    try t.expectEqual(@as(usize, 2), spans.items.len);
    try t.expectEqualStrings("items", spans.items[0]);
    try t.expectEqualStrings("items", spans.items[1]);
}

/// `count` declarations in a row, each with a failing `else` block, then the sum of what they unwrapped.
fn chainSource(allocator: std.mem.Allocator, count: usize) ![]u8 {
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(allocator);
    try text.appendSlice(allocator, header);
    try text.appendSlice(allocator, "func chain(n: int) -> int:\n    mut total = 0\n");
    for (0..count) |index| {
        try text.print(allocator, "    const v{d} = lookup(n + {d}) else:\n        return -{d}\n    total += v{d}\n", .{ index, index, index + 1, index });
    }
    try text.appendSlice(allocator, "    return total\n\n\nfunc main() -> int:\n    return chain(1) % 100\n");
    return text.toOwnedSlice(allocator);
}

// spec-case: BIND-OR-ELSE-6
test "a long chain of declarations in one block checks and runs" {
    const text = try chainSource(t.allocator, 120);
    defer t.allocator.free(text);
    // Every term is n + index, so the total is 120 * 1 + (0 + 1 + ... + 119) = 7260.
    try fixture.run(t.allocator, text, 7260 % 100);
}

// spec-case: BIND-OR-ELSE-7
test "a refused pattern does not swallow the statements after it" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const broken = "func broken(n: int) -> int:\n    const items = read(n) else Err(a, b):\n        return 1\n" ++
        "    const more = read(n) else Ok(more):\n        return 2\n    return 0\n\n\nfunc main() -> int:\n    return 0\n";
    const text = try std.mem.concat(a, u8, &.{ header, broken });
    const report = try fixture.check(a, text);
    var patterns: usize = 0;
    for (report.diagnostics) |item| {
        if (std.mem.eql(u8, item.code, "E_ELSE_PATTERN")) patterns += 1;
    }
    try t.expectEqual(@as(usize, 2), patterns);
}

// F-60: a bare `else:` (or `else None:`) over a Result says that the operand can fail and names the two patterns,
// in an ordinary function and in a generic one, at the `else` (or the `None`) it refuses.
test "a bare else over a call that fails names the failure and the patterns that handle it" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const tail = ", so the `else` must say what it does with the failure: `else Err(_):` drops it and `else Err(reason):` binds it to use (";
    const bare = try first(a, "func f(n: int) -> int:\n    const items = read(n) else:\n        return 1\n    return len(items)");
    try t.expectEqualStrings("E_PATTERN_PAYLOAD", bare[0]);
    try t.expectEqualStrings("`read(n)` can fail with str" ++ tail ++ "a bare `else:` takes only an Option's `None`)", bare[1]);
    try t.expectEqualStrings("else", bare[2]);
    const none = try first(a, "func f(n: int) -> int:\n    const items = read(n) else None:\n        return 1\n    return len(items)");
    try t.expectEqualStrings("`read(n)` can fail with str" ++ tail ++ "`else None:` takes an Option's absent value)", none[1]);
    try t.expectEqualStrings("None", none[2]);
    const held = try first(a, "func f(n: int) -> int:\n    const r = read(n)\n    const items = r else:\n        return 1\n    return len(items)");
    try t.expectEqualStrings("`r` is a Result whose failure carries str" ++ tail ++ "a bare `else:` takes only an Option's `None`)", held[1]);
    const generic = try first(a, "func halve(n: int) -> int fails str:\n    return n // 2\n\n\nfunc g[T](x: T, n: int) -> T:\n" ++
        "    const h = halve(n) else:\n        return x\n    _ = h\n    return x");
    try t.expectEqualStrings("`halve(n)` can fail with str" ++ tail ++ "a bare `else:` takes only an Option's `None`)", generic[1]);
}

// F-57: `try` on an Option outside a function that returns an Option says what is true for the function's result: one
// that can fail and has an Option as its success (`-> T? fails E`), one that can fail, and one that does neither; in
// a generic function the same.
test "try on an Option in a function that does not return an Option names its result" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const both = try first(a, "func f(n: int) -> int? fails str:\n    const value = try lookup(n)\n    return Some(value)");
    try t.expectEqualStrings("E_TRY_RETURN", both[0]);
    try t.expectEqualStrings("`try` on an Option is refused in a function that can also fail: there `try` passes on a failure, " ++
        "not an absent value; write `const x = CALL else:` with `return None` in its block", both[1]);
    try t.expectEqualStrings("try lookup(n)", both[2]);
    const fails = try first(a, "func f(n: int) -> int fails str:\n    const value = try lookup(n)\n    return value");
    try t.expectEqualStrings("`try` on an Option returns `None`, which this function cannot return: its result is a value that can " ++
        "fail, not an Option; write `const x = CALL else:` with a block that leaves", fails[1]);
    const plain = try first(a, "func f(n: int) -> int:\n    const value = try lookup(n)\n    return value");
    try t.expectEqualStrings("`try` on an Option returns `None` from the function, so the function must return an Option " ++
        "(`-> T?`); otherwise write `const x = CALL else:` with a block that leaves", plain[1]);
    const generic = try first(a, "func g[T](x: T, n: int) -> int? fails str:\n    const value = try lookup(n)\n    _ = x\n    return Some(value)");
    try t.expectEqualStrings(both[1], generic[1]);
}

// F-76: a call written as a statement with `else` has no value to bind; the refusal names the form that tests a call
// that gives nothing back, with the pattern written after the `else`, and a bare `else:` names both cases.
test "else after a call statement says what to write" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lead = "`else` needs a value to bind, and a statement that is only ";
    const err = try first(a, "func f(n: int) -> int:\n    read(n) else Err(reason):\n        return 1\n    return 0");
    try t.expectEqualStrings("E_SYNTAX", err[0]);
    try t.expectEqualStrings(lead ++ "`read(n)` has none: write `if read(n) is Err(reason):` when the call gives nothing back, " ++
        "or drop or keep its value with `_ = read(n) else Err(reason):` or `const NAME = read(n) else Err(reason):`", err[1]);
    try t.expectEqualStrings("else", err[2]);
    const dropped = try first(a, "func f(n: int) -> int:\n    read(n) else Err(_):\n        return 1\n    return 0");
    try t.expectEqualStrings(lead ++ "`read(n)` has none: write `if read(n) is Err(_):` when the call gives nothing back, " ++
        "or drop or keep its value with `_ = read(n) else Err(_):` or `const NAME = read(n) else Err(_):`", dropped[1]);
    const none = try first(a, "func f(n: int) -> int:\n    lookup(n) else None:\n        return 1\n    return 0");
    try t.expectEqualStrings(lead ++ "`lookup(n)` has none: write `if lookup(n) is None:` when the call gives nothing back, " ++
        "or drop or keep its value with `_ = lookup(n) else None:` or `const NAME = lookup(n) else None:`", none[1]);
    const bare = try first(a, "func f(n: int) -> int:\n    lookup(n) else:\n        return 1\n    return 0");
    try t.expectEqualStrings(lead ++ "`lookup(n)` has none: write `if lookup(n) is Err(e):` (a call that can fail) or `if lookup(n) is None:` " ++
        "(an Option) when it gives nothing back, or drop or keep its value with `_ = lookup(n) else:` or `const NAME = lookup(n) else:`", bare[1]);
    const held = try first(a, "func f(n: int) -> int:\n    const r = read(n)\n    r else Err(reason):\n        return 1\n    return 0");
    try t.expectEqualStrings(lead ++ "`r` has none: write `if r is Err(reason):` when the call gives nothing back, " ++
        "or drop or keep its value with `_ = r else Err(reason):` or `const NAME = r else Err(reason):`", held[1]);
    const long = try first(a, "func f(n: int) -> int:\n    read(n + n + n + n + n + n + n + n + n + n) else Err(reason):\n        return 1\n    return 0");
    try t.expectEqualStrings(lead ++ "`CALL` has none: write `if CALL is Err(reason):` when the call gives nothing back, " ++
        "or drop or keep its value with `_ = CALL else Err(reason):` or `const NAME = CALL else Err(reason):`", long[1]);
}

// F-76: the neighbours keep their own answers: `_ =` and a declaration take the value, and an assignment through a
// place is no statement-else.
test "the bind forms and an assignment before else keep their messages" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const dropped = try fixture.check(a, header ++ "func f(n: int) -> int:\n    _ = read(n) else Err(reason):\n        return 1\n    return 0\n\n\nfunc main() -> int:\n    return 0\n");
    try t.expect(dropped.firstError() == null);
    const bound = try fixture.check(a, header ++ "func f(n: int) -> int:\n    const items = read(n) else Err(_):\n        return 1\n    return len(items)\n\n\nfunc main() -> int:\n    return 0\n");
    try t.expect(bound.firstError() == null);
    const stored = try first(a, "func f(n: int, mut xs: int[]) -> int:\n    xs[0] = n else Err(reason):\n        return 1\n    return 0");
    try t.expectEqualStrings("E_SYNTAX", stored[0]);
    try t.expect(std.mem.startsWith(u8, stored[1], "`else Err(reason):` unwraps the value into a new name"));
    const tried = try first(a, "func f(n: int, mut xs: int[]) -> int fails str:\n    xs[0] = try lookup(n) else None:\n        return 1\n    return 0");
    try t.expectEqualStrings("unexpected token; expected a newline", tried[1]);
}

// SP1-F-5: `x = f() else Err(m):` writes the unwrapping `else` after an assignment. The refusal says the form unwraps into
// a new name, so it belongs to a declaration, and writes the declaration that is assigned afterwards and the `match`. It
// stays at the `else`, carries no repair, and a bare `else:`, a compound operator and a long value are worded the same way.
test "else after an assignment says the form unwraps into a new name" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const tail = "unwraps the value into a new name, so it belongs to a declaration and not to an assignment to the existing ";
    const named = try first(a, "func f(n: int) -> int:\n    mut x = 0\n    x = read(n) else Err(m):\n        return 1\n    return x");
    try t.expectEqualStrings("E_SYNTAX", named[0]);
    try t.expectEqualStrings("`else Err(m):` " ++ tail ++ "`x`: write `const value = read(n) else Err(m):` and then `x = value`, " ++
        "or `match read(n):` with an arm for each case", named[1]);
    try t.expectEqualStrings("else", named[2]);
    const dropped = try first(a, "func f(n: int) -> int:\n    mut x = 0\n    x = lookup(n) else None:\n        return 1\n    return x");
    try t.expectEqualStrings("`else None:` " ++ tail ++ "`x`: write `const value = lookup(n) else None:` and then `x = value`, " ++
        "or `match lookup(n):` with an arm for each case", dropped[1]);
    const bare = try first(a, "func f(n: int) -> int:\n    mut x = 0\n    x = lookup(n) else:\n        return 1\n    return x");
    try t.expectEqualStrings("`else:` " ++ tail ++ "`x`: write `const value = lookup(n) else:` and then `x = value`, " ++
        "or `match lookup(n):` with an arm for each case", bare[1]);
    const added = try first(a, "func f(n: int) -> int:\n    mut total = 0\n    total += lookup(n) else None:\n        return 1\n    return total");
    try t.expectEqualStrings("`else None:` " ++ tail ++ "`total`: write `const value = lookup(n) else None:` and then `total += value`, " ++
        "or `match lookup(n):` with an arm for each case", added[1]);
    const long = try first(a, "func f(n: int) -> int:\n    mut x = 0\n    x = read(n + n + n + n + n + n + n + n + n + n) else Err(m):\n        return 1\n    return x");
    try t.expectEqualStrings("`else Err(m):` " ++ tail ++ "`x`: write `const value = VALUE else Err(m):` and then `x = value`, " ++
        "or `match VALUE:` with an arm for each case", long[1]);
}

// SP1-F-5: the refusal has no repair, since either form needs the reader's choice of a name or of the arms; and the
// declaration form it points at is accepted.
test "the else after an assignment carries no repair and the declaration it names checks" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try std.fmt.allocPrint(a, "{s}func f(n: int) -> int:\n    mut x = 0\n    x = read(n) else Err(m):\n        return 1\n    return x\n\n\nfunc main() -> int:\n    return 0\n", .{header});
    const report = try fixture.check(a, text);
    try t.expect(report.firstError().?.provenance.fix == null);
    const declared = try fixture.check(a, header ++ "func f(n: int) -> int:\n    mut x = 0\n    const value = read(n) else Err(m):\n        return 1\n    x = len(value)\n    return x\n\n\nfunc main() -> int:\n    return 0\n");
    try t.expect(declared.firstError() == null);
}

// SP1B-F-3: `pax.size = f() else:` writes the unwrapping `else` after an assignment to a field or an element. The refusal is
// in the voice of the one for a local and names the three forms that do the job for a place: the declaration and the
// assignment after it, `try` in a function that can fail (or returns an Option), and `if CALL is Ok(value):` (`Some(value)`)
// with the assignment inside. It stays at the `else`, as the old `expected a newline` did.
test "else after an assignment to a field or an element names the forms that work" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const tail = "unwraps the value into a new name, so it belongs to a declaration and not to an assignment to the ";
    const record = "record Pax:\n    size: int\n\n\nfunc f(n: int, mut pax: Pax, mut xs: int[]) -> int:\n";
    const field = try first(a, record ++ "    pax.size = read(n) else Err(m):\n        return 1\n    return 0");
    try t.expectEqualStrings("E_SYNTAX", field[0]);
    try t.expectEqualStrings("`else Err(m):` " ++ tail ++ "field `pax.size`: write `const value = read(n) else Err(m):` and then " ++
        "`pax.size = value`, `pax.size = try read(n)` in a function that can fail, or `if read(n) is Ok(value):` with " ++
        "`pax.size = value` inside", field[1]);
    try t.expectEqualStrings("else", field[2]);
    const option = try first(a, record ++ "    pax.size = lookup(n) else:\n        return 1\n    return 0");
    try t.expectEqualStrings("`else:` " ++ tail ++ "field `pax.size`: write `const value = lookup(n) else:` and then " ++
        "`pax.size = value`, `pax.size = try lookup(n)` in a function that returns an Option, or `if lookup(n) is Some(value):` " ++
        "with `pax.size = value` inside", option[1]);
    const element = try first(a, record ++ "    xs[0] = lookup(n) else None:\n        return 1\n    return 0");
    try t.expectEqualStrings("`else None:` " ++ tail ++ "element `xs[0]`: write `const value = lookup(n) else None:` and then " ++
        "`xs[0] = value`, `xs[0] = try lookup(n)` in a function that returns an Option, or `if lookup(n) is Some(value):` " ++
        "with `xs[0] = value` inside", element[1]);
    const added = try first(a, record ++ "    pax.size += read(n) else Err(_):\n        return 1\n    return 0");
    try t.expectEqualStrings("`else Err(_):` " ++ tail ++ "field `pax.size`: write `const value = read(n) else Err(_):` and then " ++
        "`pax.size += value`, `pax.size += try read(n)` in a function that can fail, or `if read(n) is Ok(value):` with " ++
        "`pax.size += value` inside", added[1]);
    const named = try first(a, record ++ "    pax.size = lookup(value) else:\n        return 1\n    return 0");
    try t.expectEqualStrings("`else:` " ++ tail ++ "field `pax.size`: write `const item = lookup(value) else:` and then " ++
        "`pax.size = item`, `pax.size = try lookup(value)` in a function that returns an Option, or `if lookup(value) is Some(item):` " ++
        "with `pax.size = item` inside", named[1]);
    const long = try first(a, record ++ "    pax.size = read(n + n + n + n + n + n + n + n + n + n) else Err(m):\n        return 1\n    return 0");
    try t.expectEqualStrings("`else Err(m):` " ++ tail ++ "field `pax.size`: write `const value = VALUE else Err(m):` and then " ++
        "`pax.size = value`, `pax.size = try VALUE` in a function that can fail, or `if VALUE is Ok(value):` with " ++
        "`pax.size = value` inside", long[1]);
}

// SP1B-F-3: each form the refusal names is accepted, for a field and for an element, and the refusal has no repair.
test "the forms the place refusal names check and the refusal carries no repair" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const refused = try fixture.check(a, "record Pax:\n    size: int\n\n\nfunc lookup(n: int) -> int?:\n    if n == 0:\n        return None\n    return Some(n)\n\n\n" ++
        "func f(n: int, mut pax: Pax) -> int:\n    pax.size = lookup(n) else:\n        return 1\n    return 0\n\n\nfunc main() -> int:\n    return 0\n");
    try t.expect(refused.firstError().?.provenance.fix == null);
    const accepted = try fixture.check(a, "record Pax:\n    size: int\n\n\nfunc count(n: int) -> int fails str:\n    if n < 0:\n        fail \"negative\"\n    return n\n\n\n" ++
        "func lookup(n: int) -> int?:\n    if n == 0:\n        return None\n    return Some(n)\n\n\n" ++
        "func declared(n: int, mut pax: Pax, mut xs: int[]) -> int:\n    const value = lookup(n) else:\n        return 1\n    pax.size = value\n    xs[0] = value\n    return 0\n\n\n" ++
        "func tried(n: int, mut pax: Pax, mut xs: int[]) -> int fails str:\n    pax.size = try count(n)\n    xs[0] += try count(n)\n    return 0\n\n\n" ++
        "func tried_option(n: int, mut pax: Pax) -> int?:\n    pax.size = try lookup(n)\n    return Some(0)\n\n\n" ++
        "func tested(n: int, mut pax: Pax, mut xs: int[]) -> int:\n    if lookup(n) is Some(value):\n        pax.size = value\n        xs[0] = value\n" ++
        "    if count(n) is Ok(item):\n        pax.size += item\n    return 0\n\n\nfunc main() -> int:\n    return 0\n");
    try t.expect(accepted.firstError() == null);
}
