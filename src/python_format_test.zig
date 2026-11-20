//! Interpolated `f"..."` literals render once and join multiple pieces into text.
//! The `foundation syntax:` cases at the end cover the token formatter's
//! canonical text for the local-reasoning spellings: `mut` on a parameter and a
//! call argument, a bare `*` keyword-only separator, tuple values and types, and
//! the conditional expression, each of which must survive `selka fmt` unchanged.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn execute(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "format.selka", source);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}

fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "format.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

/// The first diagnostic of checking `source`, as `code message`.
fn firstDiagnostic(source: []const u8) ![]u8 {
    var c = try language.Compilation.init(t.allocator, "format.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    return std.fmt.allocPrint(t.allocator, "{s} {s}", .{ c.diagnostics.items[0].code, c.diagnostics.items[0].message });
}

fn expectFirst(source: []const u8, expected: []const u8) !void {
    const got = try firstDiagnostic(source);
    defer t.allocator.free(got);
    try t.expectEqualStrings(expected, got);
}

// FR21: a lone `{` in a format string is written `{{`. A hole that is not an expression with a specification, as CSS, JSON or a
// template is not, says so and quotes this hole's opening as it stands and doubled.
test "a format string with a lone brace says a literal brace is written {{ and shows this hole's opening doubled" {
    const head = "func main(out: Stream) -> int:\n    const color = \"red\"\n    const x = 1\n";
    const tail = "\n    return x\n";
    const way = "A literal brace in a format string is written `{{` and `}}`: if `";
    const nested = "a nested `{...}` inside a format specification is not supported; a specification is literal text such as `{value:>8.2f}`. ";
    try expectFirst(head ++ "    print(out, f\"p { color: {color}; }\")" ++ tail, "E_FORMAT_STRING " ++ nested ++ way ++ "{ color:` was meant as text, write `{{ color:`");
    try expectFirst(head ++ "    print(out, f\"p { color: red; }\")" ++ tail, "E_FORMAT_STRING Invalid format specifier. " ++ way ++ "{ color:` was meant as text, write `{{ color:`");
    try expectFirst(head ++ "    print(out, f\"a {x y} d\")" ++ tail, "E_FORMAT_STRING a format string interpolation holds exactly one expression. " ++ way ++ "{x y` was meant as text, write `{{x y`");
    try expectFirst(head ++ "    print(out, f\"a { x\")" ++ tail, "E_FORMAT_STRING unterminated interpolation in a format string. " ++ way ++ "{ x` was meant as text, write `{{ x`");
    // A long opening is cut at 24 bytes, and the doubled form is the way out.
    const long = "func main(out: Stream) -> int:\n    const a_very_long_name_for_a_hole = 1\n    print(out, f\"{ a_very_long_name_for_a_hole: red; }\")\n    return 0\n";
    try expectFirst(long, "E_FORMAT_STRING Invalid format specifier. " ++ way ++ "{ a_very_long_name_for_a...` was meant as text, write `{{ a_very_long_name_for_a...`");
    try execute("func main() -> int:\n    const color = \"red\"\n    if f\"p {{ color: {color}; }}\" != \"p { color: red; }\":\n        return 1\n    return 42\n", 42);
}

// A `!` in a hole is another language's conversion (`f"{text!r}"`): the message says what a hole holds and writes the call.
test "a format string hole with a ! conversion says it holds an expression and a format, and writes repr(text)" {
    const head = "func main(out: Stream) -> int:\n    const text = \"a\"\n    const a = 1\n    const b = 2\n";
    const tail = "\n    return 0\n";
    const said = "E_TOKEN unexpected character in source: a format string hole holds an expression, then an optional format after `:`, as in `{count:>8}`; it has no `!` conversion, so call the function in the hole: ";
    try expectFirst(head ++ "    print(out, f\"{text!r}\")" ++ tail, said ++ "`{repr(text)}` for `!r`, `{str(text)}` for `!s`");
    try expectFirst(head ++ "    print(out, f\"{a + b!r:>8}\")" ++ tail, said ++ "`{repr(a + b)}` for `!r`, `{str(a + b)}` for `!s`");
    // An expression of more than 40 bytes is not quoted.
    try expectFirst(head ++ "    print(out, f\"{a + b + a + b + a + b + a + b + a + b + a + b!r}\")" ++ tail, said ++ "`{repr(value)}` for `!r`, `{str(value)}` for `!s`");
    try expectFirst(head ++ "    print(out, f\"\"\"{text!s}\"\"\")" ++ tail, said ++ "`{repr(text)}` for `!r`, `{str(text)}` for `!s`");
    try execute("func main() -> int:\n    const text = \"a\"\n    if f\"{repr(text)}\" != \"'a'\":\n        return 1\n    return 42\n", 42);
}

/// `source` with the repair of its first diagnostic applied, or null when that diagnostic carries none.
fn repaired(source: []const u8) !?[]u8 {
    var c = try language.Compilation.init(t.allocator, "format.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_TOKEN", c.diagnostics.items[0].code);
    const fix = c.diagnostics.items[0].provenance.fix orelse return null;
    try t.expectEqual(@as(usize, 2), fix.count());
    const open = fix.at(0);
    const close = fix.at(1);
    const text = try std.fmt.allocPrint(t.allocator, "{s}{s}{s}{s}{s}", .{
        source[0..open.span.start], open.text, source[open.span.end..close.span.start], close.text, source[close.span.end..],
    });
    return text;
}

fn expectRepair(source: []const u8, expected: ?[]const u8) !void {
    const got = try repaired(source);
    defer if (got) |text| t.allocator.free(text);
    try t.expectEqualStrings(expected orelse "no repair", got orelse "no repair");
}

// The repair of `{text!r}` and `{text!s}` is the call written around the expression, where the hole is exactly that: the text
// before the `!` is one expression, the conversion is `r` or `s` alone, and a specification after it stays where it is.
test "a ! conversion of one expression carries the call as its repair, and any other hole carries none" {
    const head = "func main(out: Stream) -> int:\n    const text = \"a\"\n    const a = 1\n    const b = 2\n";
    const tail = "\n    return 0\n";
    try expectRepair(head ++ "    print(out, f\"{text!r}\")" ++ tail, head ++ "    print(out, f\"{repr(text)}\")" ++ tail);
    try expectRepair(head ++ "    print(out, f\"{a + b!s:>8}\")" ++ tail, head ++ "    print(out, f\"{str(a + b):>8}\")" ++ tail);
    try expectRepair(head ++ "    print(out, f\"\"\"x {text!s}\"\"\")" ++ tail, head ++ "    print(out, f\"\"\"x {str(text)}\"\"\")" ++ tail);
    try expectRepair(head ++ "    print(out, f\"{len(text)!r} {a!s}\")" ++ tail, head ++ "    print(out, f\"{repr(len(text))} {a!s}\")" ++ tail);
    // Another conversion, a longer one, two of them, a tuple and an expression that does not parse are left as they are.
    try expectRepair(head ++ "    print(out, f\"{text!a}\")" ++ tail, null);
    try expectRepair(head ++ "    print(out, f\"{text!rr}\")" ++ tail, null);
    try expectRepair(head ++ "    print(out, f\"{text!r!s}\")" ++ tail, null);
    try expectRepair(head ++ "    print(out, f\"{a, b!r}\")" ++ tail, null);
    try expectRepair(head ++ "    print(out, f\"{(a +)!r}\")" ++ tail, null);
}

test "formatHole adds the literal-brace advice to the syntax error of a hole, and only to the hole's own error" {
    var c = try language.Compilation.init(t.allocator, "format.selka", "func main() -> int:\n    const x = 1\n    _ = f\"a {x +} b {x y}\"\n    return 0\n");
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqual(@as(usize, 1), c.diagnostics.items.len);
    try t.expectEqualStrings("E_EXPRESSION", c.diagnostics.items[0].code);
    try t.expect(std.mem.endsWith(u8, c.diagnostics.items[0].message, "was meant as text, write `{{x +`"));
    // A syntax error outside any hole is untouched.
    var plain = try language.Compilation.init(t.allocator, "format.selka", "func main() -> int:\n    const x = 1 +\n    return 0\n");
    defer plain.deinit();
    try t.expectError(error.SourceError, plain.check());
    try t.expect(std.mem.indexOf(u8, plain.diagnostics.items[0].message, "literal brace") == null);
}

test "a specification that is a specification keeps its own refusal with no advice about braces" {
    const head = "func main(out: Stream) -> int:\n    const x = 1\n";
    try expectFirst(head ++ "    print(out, f\"{x:.2d}\")\n    return x\n", "E_FORMAT_STRING Precision not allowed in integer format specifier");
    try expectFirst(head ++ "    print(out, f\"{x:>8q}\")\n    return x\n", "E_FORMAT_STRING Invalid format specifier");
    try execute("func main() -> int:\n    const x = 4\n    if f\"{x:> 3}|{x:*^5}\" != \"  4|**4**\":\n        return 1\n    return 42\n", 42);
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
    \\func pick(n: int) -> int fails str:
    \\    if n < 0:
    \\        fail "nope"
    \\    return n
    \\
    \\func main(out: Stream) -> int:
    \\    mut score = 0
    \\    mut values = [1, 2]
    \\    mut counts: dict[str, int] = {"k": 1}
    \\    mut spot = Point(x=1, y=2)
    \\    mut found: int? = Some(4)
    \\    mut raw = b"ab"
    \\    print(out, values, f"{values}")
    \\    print(out, counts, f"{counts}")
    \\    print(out, spot, f"{spot}")
    \\    print(out, Colour.green, f"{Colour.green}")
    \\    print(out, pick(3), f"{pick(3)}")
    \\    print(out, pick(-1), f"{pick(-1)}")
    \\    print(out, found, f"{found}")
    \\    print(out, raw, f"{raw}")
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
    var c = try language.Compilation.init(t.allocator, "format.selka", rendered_holes);
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
    var c = try language.Compilation.init(t.allocator, "format.selka",
        \\@noalloc
        \\func length(value: str) -> int:
        \\    return strings.char_count(f"{value}")
        \\@noalloc
        \\func generic[T: integer](value: str, unused: T) -> int:
        \\    return strings.char_count(f"{value}")
        \\func main() -> int:
        \\    return generic("hello", length("hello")) + strings.char_count(f"")
    );
    defer c.deinit();
    try c.check();
    try t.expect(c.program != null);
}

// spec-case: PY-FSTRING-1
test "a multi-piece f-string owns a borrowed text hole" {
    try execute(
        \\func message(reason: str) -> str:
        \\    return f"{reason}!"
        \\
        \\func length(reason: str) -> int:
        \\    return strings.char_count(f"{reason} y")
        \\
        \\func main() -> int:
        \\    return strings.char_count(message("hello")) + length("ab") + 32
    , 42);
}

// spec-case: PY-FSTRING-1
test "f-string holes still evaluate once from left to right including generic holes" {
    const source =
        \\func mark(out: Stream, value: int) -> int:
        \\    print(out, value, end="")
        \\    return value
        \\
        \\func generic[T: integer](value: T) -> str:
        \\    return f"{value}"
        \\
        \\func main(out: Stream) -> int:
        \\    mut text = f"{mark(out, 1)}{mark(out, 2)}"
        \\    print(out, text, end="")
        \\    print(out)
        \\    if generic(42) == "42":
        \\        return 42
        \\    return 0
    ;
    var c = try language.Compilation.init(t.allocator, "format.selka", source);
    defer c.deinit();
    const outcome = try native.run(&c);
    try t.expectEqual(@as(i64, 42), outcome.value);
    try t.expectEqualStrings("1212\n", outcome.stdout);
}

// spec-case: PY-FSTRING-1
test "a failing later f-string hole writes none of the unfinished result" {
    var c = try language.Compilation.init(t.allocator, "format.selka",
        \\func fail(value: int) -> int:
        \\    return 1 // value
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, f"ready {fail(0)}")
        \\    return 0
    );
    defer c.deinit();
    const outcome = try native.run(&c);
    try t.expect(outcome.trap.code.len != 0);
    try t.expectEqualStrings("", outcome.stdout);
}

/// Format retained old syntax through explicit migration recognition. This
/// preserves the token formatter contract without asserting target acceptance.
fn recognizedFormat(c: *language.Compilation) ![]u8 {
    const allocator = c.arena.allocator();
    var sink: @import("diagnostic.zig").Sink = .{ .allocator = allocator };
    const tokens = try @import("lexer.zig").lex(allocator, c.src.bytes, &sink);
    var recognition: @import("parser.zig").Parser = .{
        .src = c.src,
        .storage = allocator,
        .tokens = tokens,
        .sink = &sink,
        .cursor = .{ .dialect = .migration },
    };
    const syntax = try recognition.parse();
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
    return @import("formatter.zig").format(t.allocator, c.src.bytes, tokens, syntax);
}

/// Format one already-canonical source twice and require the bytes back
/// unchanged both times, so a spelling that only looks stable on the first pass
/// fails here.
fn canonical(source: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "canonical.selka", source);
    defer c.deinit();
    const formatted = try recognizedFormat(&c);
    defer t.allocator.free(formatted);
    try t.expectEqualStrings(source, formatted);
    var again = try language.Compilation.init(t.allocator, "canonical.selka", formatted);
    defer again.deinit();
    const twice = try recognizedFormat(&again);
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
    // migrate-embedded: skip original R2 diagnostic, syntax-recognition or exact-output fixture; see L01 r2-preservation classification
    try canonical("func choose(flag: bool) -> int:\n    mut y = if (flag) then (1) else (2)\n    return y\n");
    // migrate-embedded: skip original R2 diagnostic, syntax-recognition or exact-output fixture; see L01 r2-preservation classification
    try canonical("func label(flag: bool) -> int:\n    mut pair = (1, 2)\n    return if (flag) then (pair[0]) else (pair[1])\n");
}

// spec-case: SYNTAX-FMT-1
test "foundation syntax: fmt drops a redundant trailing comma after the last tuple element" {
    try canonical("func main() -> int:\n    mut pair = (1, 2)\n    return pair[0]\n");
    var c = try language.Compilation.init(t.allocator, "canonical.selka", "func main() -> int:\n    mut pair = (1, 2,)\n    return pair[0]\n");
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expectEqualStrings("func main() -> int:\n    mut pair = (1, 2)\n    return pair[0]\n", formatted);
}

// spec-case: CONDITIONAL-EXPR-2
test "a nested conditional and one inside a call argument survive fmt unchanged" {
    // migrate-embedded: skip original R2 diagnostic, syntax-recognition or exact-output fixture; see L01 r2-preservation classification
    try canonical("func main() -> int:\n    mut x = if (False) then (1) else if ((False)) then ((2)) else ((3))\n    return x\n");
    // migrate-embedded: skip original R2 diagnostic, syntax-recognition or exact-output fixture; see L01 r2-preservation classification
    try canonical("func main() -> int:\n    return describe(if (True) then (1) else (2))\n");
}

// FR24: the two shapes FR21 left out. A name the program lacks in a hole that reads as the literal's own braces (`f"body { margin: 0 }"`),
// and a hole that is a value with a specification that is no specification (`{ color: red }`, the JSON `{"a": 1}`), say how a literal
// brace is written. The test is on the hole's text (white space around it, a quoted text or a space before its specification) and only
// runs for a hole that was refused, so no hole that checks is judged by it.
test "checkFormatHinted and refuseSpecification: a name the program lacks in a hole that reads as braces, and a JSON key with a value, say a literal brace is written {{" {
    const head = "func main(out: Stream) -> int:\n    const color = \"red\"\n";
    const tail = "\n    return 0\n";
    const way = "A literal brace in a format string is written `{{` and `}}`: if `";
    const unknown = "E_UNKNOWN_NAME name is not defined in this scope. ";
    try expectFirst(head ++ "    print(out, f\"body { margin: 0 }\")" ++ tail, unknown ++ way ++ "{ margin:` was meant as text, write `{{ margin:`");
    try expectFirst(head ++ "    print(out, f\"body {margin: 0}\")" ++ tail, unknown ++ way ++ "{margin:` was meant as text, write `{{margin:`");
    try expectFirst(head ++ "    print(out, f\"a { shade }\")" ++ tail, unknown ++ way ++ "{ shade ` was meant as text, write `{{ shade `");
    try expectFirst(head ++ "    print(out, f'{\"a\": 1}')" ++ tail, "E_FORMAT_STRING Sign not allowed in string format specifier. " ++ way ++ "{\"a\":` was meant as text, write `{{\"a\":`");
    try expectFirst(head ++ "    print(out, f\"p { color: red }\")" ++ tail, "E_FORMAT_STRING Invalid format specifier. " ++ way ++ "{ color:` was meant as text, write `{{ color:`");
    // The same in a triple-quoted format string, and the doubled form is the way out.
    try expectFirst(head ++ "    print(out, f\"\"\"body { margin: 0 }\"\"\")" ++ tail, unknown ++ way ++ "{ margin:` was meant as text, write `{{ margin:`");
    try execute("func main() -> int:\n    const x = 7\n    if f'{{\"a\": {x}}}' != '{\"a\": 7}':\n        return 1\n    return 42\n", 42);
}

// FR25 item 4: a generic function body checks its format strings on its own path (`generic_bodies.formatValue`), which reported the
// unknown name without the sentence; it asks the same helper (`format_strings.unknownNameAdvice`) the concrete checker does.
test "generic_bodies formatValue says a literal brace is written {{ for a name in a hole that reads as braces, and leaves an ordinary hole alone" {
    const head = "func boxed[T](value: T) -> str:\n";
    const tail = "\n\n\nfunc main(out: Stream) -> int:\n    print(out, boxed(1))\n    return 0\n";
    const way = "A literal brace in a format string is written `{{` and `}}`: if `";
    const unknown = "E_UNKNOWN_NAME name is not defined in this template scope. ";
    try expectFirst(head ++ "    return f\"body { margin: 0 }\"" ++ tail, unknown ++ way ++ "{ margin:` was meant as text, write `{{ margin:`");
    try expectFirst(head ++ "    return f\"a { shade }\"" ++ tail, unknown ++ way ++ "{ shade ` was meant as text, write `{{ shade `");
    try expectFirst(head ++ "    return f\"{ color: red }\"" ++ tail, unknown ++ way ++ "{ color:` was meant as text, write `{{ color:`");
    try expectFirst(head ++ "    return f\"a {colr}\"" ++ tail, "E_UNKNOWN_NAME name is not defined in this template scope");
    try expectFirst(head ++ "    return f\"a {colr:>8}\"" ++ tail, "E_UNKNOWN_NAME name is not defined in this template scope");
}

test "checkFormatHinted leaves an unknown name in an ordinary hole and a refused specification of an ordinary hole with their own message" {
    const head = "func main(out: Stream) -> int:\n    const color = \"red\"\n    const x = 1\n";
    const tail = "\n    return x\n";
    try expectFirst(head ++ "    print(out, f\"a {colr}\")" ++ tail, "E_UNKNOWN_NAME name is not defined in this scope; did you mean `color`?");
    try expectFirst(head ++ "    print(out, f\"a {colr:>8}\")" ++ tail, "E_UNKNOWN_NAME name is not defined in this scope; did you mean `color`?");
    try expectFirst(head ++ "    print(out, f\"a {x:>8q}\")" ++ tail, "E_FORMAT_STRING Invalid format specifier");
}

// A `\"` in a hole is another language's escaped quote (`f"{d[\"k\"]}"`): before, the lexer said only that a character was unexpected.
test "a format string hole with an escaped quote says a hole holds an expression and what to write instead" {
    const head = "func main(out: Stream) -> int:\n    const d = {\"k\": 1}\n";
    const tail = "\n    return 0\n";
    const said = "E_TOKEN unexpected character in source: a format string hole holds an expression, not escaped text, so a quote inside it is written as the other kind, ";
    try expectFirst(head ++ "    print(out, f\"{d[\\\"k\\\"]}\")" ++ tail, said ++ "`f\"{d['k']}\"`, or the value goes in a local first: `const k = d[\"k\"]`, then `f\"{k}\"`");
    try expectFirst(head ++ "    print(out, f'{d[\\'k\\']}')" ++ tail, said ++ "`f'{d[\"k\"]}'`, or the value goes in a local first: `const k = d['k']`, then `f'{k}'`");
    // A backslash that is not before a quote keeps the plain message, and the other kind of quote is the repair.
    try expectFirst(head ++ "    print(out, f\"{d[\\k]}\")" ++ tail, "E_TOKEN unexpected character in source");
    try execute("func main() -> int:\n    const d = {\"k\": 7}\n    if f\"{d['k']}\" != \"7\":\n        return 1\n    return 42\n", 42);
}

// Round 4: `f"{names["a"]}"` was refused with a message about braces and a repair that doubled the brace. The quote of the literal's own
// kind ended the literal inside the hole; the message says so and writes the other kind of quote, in the hole or for the literal.
test "a quote of the literal's own kind inside a hole says it ended the literal and what to write instead" {
    const head = "func main(out: Stream) -> int:\n    const d = {\"k\": 1}\n    const x = 1\n";
    const tail = "\n    return 0\n";
    const advice = "A `\"` inside a hole ends the literal there, so this hole was left open: " ++
        "write the quote inside the hole as the other kind, `f\"{d['k']}\"`, or the literal as the other kind, `f'{d[\"k\"]}'`, " ++
        "or bind the value to a name first: `const k = d[\"k\"]`, then `f\"{k}\"`";
    const said = "E_FORMAT_STRING unterminated interpolation in a format string. " ++ advice;
    try expectFirst(head ++ "    print(out, f\"x {d[\"k\"]}\")" ++ tail, said);
    try expectFirst(head ++ "    print(out, f\"{x + len(\"ab\")}\")" ++ tail, said);
    // The literal's own kind is the quote that ends it, so the examples swap with it.
    try expectFirst(head ++ "    print(out, f'{d['k']}')" ++ tail, "E_FORMAT_STRING unterminated interpolation in a format string. A `'` inside a hole ends " ++
        "the literal there, so this hole was left open: write the quote inside the hole as the other kind, `f'{d[\"k\"]}'`, or the literal as " ++
        "the other kind, `f\"{d['k']}\"`, or bind the value to a name first: `const k = d['k']`, then `f'{k}'`");
    // A format specification is a hole too; a hole that opens at the quote (JSON) also says how its brace is written.
    try expectFirst(head ++ "    print(out, f\"{x:\"a\"}\")" ++ tail, "E_FORMAT_STRING unterminated format specification in a format string. " ++ advice);
    try expectFirst(head ++ "    print(out, f\"{\"k\": 1}\")" ++ tail, said ++ ". A `{` of the text itself is written `{{`: `f'{{\"k\": 1}}'`");
    // No `}` after the quote: the hole was never closed, and the advice about a literal brace stays.
    try expectFirst(head ++ "    print(out, f\"a { x\" + \")\")" ++ tail, "E_FORMAT_STRING unterminated interpolation in a format string. A literal brace in a format string " ++
        "is written `{{` and `}}`: if `{ x` was meant as text, write `{{ x`");
    // Both repairs run.
    try execute("func main() -> int:\n    const d = {\"k\": 7}\n    if f'{d[\"k\"]}' != \"7\" or f\"{d['k']}\" != \"7\":\n        return 1\n    return 42\n", 42);
}
