//! Interpolated `f"..."` literals render once and join multiple pieces into text.
//! The `foundation syntax:` cases at the end cover the token formatter's
//! canonical text for the local-reasoning spellings: `mut` on a parameter and a
//! call argument, a bare `*` keyword-only separator, tuple values and types, and
//! the conditional expression, each of which must survive `mylang fmt` unchanged.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn execute(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "format.my", source);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}

fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "format.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

// spec-case: PY-FSTRING-2
test "malformed format strings and unconvertible values are rejected" {
    const header = "func main() -> int:\n    const x = 1\n    _ = ";
    const capability = "func main(fs: Filesystem) -> int:\n    _ = f\"{fs}\"\n    return 0\n";
    try reject(capability, "E_TEXT_CONVERSION");
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body = "f\"{}\"", .code = "E_FORMAT_STRING" },
        .{ .body = "f\"{x:.2d}\"", .code = "E_FORMAT_STRING" },
        .{ .body = "f\"a}b\"", .code = "E_FORMAT_STRING" },
        .{ .body = "f\"{1 2}\"", .code = "E_FORMAT_STRING" },
        .{ .body = "f\"{x\"", .code = "E_FORMAT_STRING" },
    };
    for (cases) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{ header, case.body, "\n    return 0\n" });
        defer t.allocator.free(text);
        try reject(text, case.code);
    }
}

/// Every kind of value a hole renders, printed beside its own interpolation so
/// the two spellings must agree byte for byte, and scored so the converted text
/// is checked as well.
const rendered_holes =
    \\record Point:
    \\    x: int
    \\    y: int
    \\
    \\enum Colour:
    \\    red
    \\    green
    \\
    \\func pick(n: int) -> Result[int, str]:
    \\    if n < 0:
    \\        return Err("nope")
    \\    return Ok(n)
    \\
    \\func main(out: Stream) -> int:
    \\    mut score = 0
    \\    mut values = [1, 2]
    \\    mut counts: dict[str, int] = {"k": 1}
    \\    mut spot = Point(x=1, y=2)
    \\    mut found: int? = Some(4)
    \\    mut raw = b"ab"
    \\    out.print(values, f"{values}")
    \\    out.print(counts, f"{counts}")
    \\    out.print(spot, f"{spot}")
    \\    out.print(Colour.green, f"{Colour.green}")
    \\    out.print(pick(3), f"{pick(3)}")
    \\    out.print(pick(-1), f"{pick(-1)}")
    \\    out.print(found, f"{found}")
    \\    out.print(raw, f"{raw}")
    \\    if f"{values}" == "[1, 2]":
    \\        score = score + 1
    \\    if f"{counts}" == "{'k': 1}":
    \\        score = score + 2
    \\    if f"{spot} {Colour.green}" == "Point(x=1, y=2) Colour.green":
    \\        score = score + 4
    \\    if f"{pick(3)} {pick(-1)} {found}" == "Ok(3) Err('nope') Some(4)":
    \\        score = score + 8
    \\    if f"{raw}" == "b'ab'":
    \\        score = score + 16
    \\    return score
;

// spec-case: PY-FSTRING-1
test "a native build spells an interpolated aggregate exactly as print writes it" {
    var c = try language.Compilation.init(t.allocator, "format.my", rendered_holes);
    defer c.deinit();
    const outcome = try native.run(&c);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 31), outcome.value);
    try t.expectEqualStrings(
        \\[1, 2] [1, 2]
        \\{'k': 1} {'k': 1}
        \\Point(x=1, y=2) Point(x=1, y=2)
        \\Colour.green Colour.green
        \\Ok(3) Ok(3)
        \\Err('nope') Err('nope')
        \\Some(4) Some(4)
        \\b'ab' b'ab'
        \\
    , outcome.stdout);
}

// spec-case: PY-FSTRING-1
test "a single f-string piece checks under noalloc" {
    var c = try language.Compilation.init(t.allocator, "format.my",
        \\func identity(value: str) -> str noalloc:
        \\    return f"{value}"
        \\func generic[T: integer](value: str, unused: T) -> str noalloc:
        \\    return f"{value}"
        \\func main() -> int:
        \\    return len(generic(identity("hello"), 1)) + len(f"")
    );
    defer c.deinit();
    try c.check();
    try t.expect(c.program != null);
}

// spec-case: PY-FSTRING-1
test "f-string holes still evaluate once from left to right including generic holes" {
    const source =
        \\func mark(out: Stream, value: int) -> int effects(output):
        \\    out.print(value, end="")
        \\    return value
        \\
        \\func generic[T: integer](value: T) -> str:
        \\    return f"{value}"
        \\
        \\func main(out: Stream) -> int:
        \\    mut text = f"{mark(out, 1)}{mark(out, 2)}"
        \\    out.print(text, end="")
        \\    out.print()
        \\    if generic(42) == "42":
        \\        return 42
        \\    return 0
    ;
    var c = try language.Compilation.init(t.allocator, "format.my", source);
    defer c.deinit();
    const outcome = try native.run(&c);
    try t.expectEqual(@as(i64, 42), outcome.value);
    try t.expectEqualStrings("1212\n", outcome.stdout);
}

// spec-case: PY-FSTRING-1
test "a failing later f-string hole writes none of the unfinished result" {
    var c = try language.Compilation.init(t.allocator, "format.my",
        \\func fail(value: int) -> int:
        \\    return 1 // value
        \\
        \\func main(out: Stream) -> int:
        \\    out.print(f"ready {fail(0)}")
        \\    return 0
    );
    defer c.deinit();
    const outcome = try native.run(&c);
    try t.expect(outcome.trap.code.len != 0);
    try t.expectEqualStrings("", outcome.stdout);
}

/// Format one already-canonical source twice and require the bytes back
/// unchanged both times, so a spelling that only looks stable on the first pass
/// fails here.
fn canonical(source: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "canonical.my", source);
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expectEqualStrings(source, formatted);
    var again = try language.Compilation.init(t.allocator, "canonical.my", formatted);
    defer again.deinit();
    const twice = try again.format(t.allocator);
    defer t.allocator.free(twice);
    try t.expectEqualStrings(source, twice);
}

// spec: SYNTAX-FMT-1
test "foundation syntax: fmt round-trips the mut star tuple and conditional spellings unchanged" {
    try canonical("func fill(mut values: int[], count: int) -> Unit:\n    return\n");
    try canonical("func issue(host: int, named code: int, named file: int) -> Unit:\n    return\n");
    try canonical("func main() -> int:\n    push(mut values, 1)\n    return 0\n");
    try canonical("func swap(a: int, b: int) -> Unit:\n    a, b = b, a\n    return\n");
    try canonical("func split(text: str) -> tuple[str, str]:\n    return text, text\n");
    try canonical("func choose(flag: bool) -> int:\n    mut y = if (flag) then (1) else (2)\n    return y\n");
    try canonical("func label(flag: bool) -> int:\n    mut pair = (1, 2)\n    return if (flag) then (pair[0]) else (pair[1])\n");
}

// spec-case: SYNTAX-FMT-1
test "foundation syntax: fmt drops a redundant trailing comma after the last tuple element" {
    try canonical("func main() -> int:\n    mut pair = (1, 2)\n    return pair[0]\n");
    var c = try language.Compilation.init(t.allocator, "canonical.my", "func main() -> int:\n    mut pair = (1, 2,)\n    return pair[0]\n");
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expectEqualStrings("func main() -> int:\n    mut pair = (1, 2)\n    return pair[0]\n", formatted);
}

// spec-case: CONDITIONAL-EXPR-2
test "a nested conditional and one inside a call argument survive fmt unchanged" {
    try canonical("func main() -> int:\n    mut x = if (False) then (1) else if ((False)) then ((2)) else ((3))\n    return x\n");
    try canonical("func main() -> int:\n    return describe(if (True) then (1) else (2))\n");
}
