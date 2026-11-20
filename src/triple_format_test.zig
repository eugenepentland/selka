//! F-19 (D-F19-1 of `experiments/audit-work-20261111/F19.md`): `f"""..."""` and `f'''...'''` are format strings whose text
//! is the text of the plain triple-quoted string of the same source, with holes. These tests pin the lexer's token, the
//! pieces the splitter cuts, the text a program gets, the positions of holes on later lines, the messages that remain, and
//! the tools that read the literal as bytes (the formatter and the token digest).
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const lexer = language.lexer;
const diagnostics = language.diagnostic;
const native = @import("native_execute.zig");
const format_strings = @import("format_strings.zig");
const token_digest = @import("token_digest.zig");

/// The token tags and `start-end` spans of `bytes` as the lexer cuts them (no layout tokens), joined by spaces.
fn tokens(bytes: []const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var sink: diagnostics.Sink = .{ .allocator = arena.allocator() };
    const found = try lexer.lexRange(arena.allocator(), bytes, .{ .start = 0, .end = bytes.len }, &sink);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(t.allocator);
    for (found) |token| {
        if (out.items.len != 0) try out.append(t.allocator, ' ');
        try out.print(t.allocator, "{s}@{d}-{d}", .{ @tagName(token.tag), token.span.start, token.span.end });
    }
    return out.toOwnedSlice(t.allocator);
}

fn expectTokens(bytes: []const u8, expected: []const u8) !void {
    const got = try tokens(bytes);
    defer t.allocator.free(got);
    try t.expectEqualStrings(expected, got);
}

test "F-19 a triple-quoted format string is one format token over its lines, in both quote kinds" {
    try expectTokens("f\"\"\"x\"\"\"", "format@0-8 eof@8-8");
    try expectTokens("f'''a\nb''' y", "format@0-10 ident@11-12 eof@12-12");
    try expectTokens("f\"\"\"\"\"\" z", "format@0-7 ident@8-9 eof@9-9");
    // The first three quotes in a row close it, wherever a hole stands (D-F19-1 item 4), so holes may hold either single quote.
    try expectTokens("f\"\"\"a {x[\"k\"]} {y['k']} b\"\"\" c", "format@0-28 ident@29-30 eof@30-30");
    try expectTokens("f\"\"\"say \\\"hi\\\"\"\"\" c", "format@0-17 ident@18-19 eof@19-19");
}

test "F-19 the plain triple-quoted text, the one-line format string and a b-prefixed triple lex as they did" {
    try expectTokens("\"\"\"x\ny\"\"\"", "bytes@0-9 eof@9-9");
    try expectTokens("f\"x{y}\" f'z'", "format@0-7 format@8-12 eof@12-12");
    try expectTokens("f\"\" f''", "format@0-3 format@4-7 eof@7-7");
    try expectTokens("b\"\"\"x\"\"\"", "bytes@0-3 bytes@3-6 bytes@6-8 eof@8-8");
}

test "F-19 an unterminated triple-quoted format string names the line it opened on" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text = "a\nb\nx = f\"\"\"abc\n{y}\n";
    var sink: diagnostics.Sink = .{ .allocator = arena.allocator() };
    try t.expectError(error.SourceError, lexer.lexRange(arena.allocator(), text, .{ .start = 0, .end = text.len }, &sink));
    try t.expectEqualStrings("E_BYTE_LITERAL", sink.items.items[0].code);
    try t.expectEqualStrings("unterminated triple-quoted format string: it opened on line 3 and has no closing three quotes of the same kind", sink.items.items[0].message);
    // The span starts at the opening quotes, so the diagnostic's location is that line too.
    try t.expectEqual(@as(usize, 9), sink.items.items[0].span.start);
    var closed_by_two: diagnostics.Sink = .{ .allocator = arena.allocator() };
    try t.expectError(error.SourceError, lexer.lexRange(arena.allocator(), "f'''x''", .{ .start = 0, .end = 7 }, &closed_by_two));
    try t.expect(std.mem.indexOf(u8, closed_by_two.items.items[0].message, "opened on line 1") != null);
}

/// The pieces of the format string spelled by all of `text`, each as `kind:source text`, joined by `|`.
fn pieces(text: []const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const src = try language.source.Source.init(arena.allocator(), "pieces.selka", text);
    var sink: diagnostics.Sink = .{ .allocator = arena.allocator() };
    const cut = try format_strings.split(arena.allocator(), src, .{ .start = 0, .end = text.len }, &sink);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(t.allocator);
    for (cut, 0..) |piece, index| {
        if (index != 0) try out.append(t.allocator, '|');
        switch (piece) {
            .literal => |span| try out.print(t.allocator, "literal:{s}", .{src.text(span)}),
            .brace => |span| try out.print(t.allocator, "brace:{s}", .{src.text(span)}),
            .hole => |span| try out.print(t.allocator, "hole:{s}", .{src.text(span)}),
            .spec => |span| try out.print(t.allocator, "spec:{s}", .{src.text(span)}),
        }
    }
    return out.toOwnedSlice(t.allocator);
}

fn expectPieces(text: []const u8, expected: []const u8) !void {
    const got = try pieces(text);
    defer t.allocator.free(got);
    try t.expectEqualStrings(expected, got);
}

test "F-19 a triple-quoted format string splits like the one-line form, with its quotes three wide" {
    try expectPieces("f\"\"\"a {x}\n b {y:>3}\n\"\"\"", "literal:a |hole:x|literal:\n b |hole:y|spec:>3|literal:\n");
    try expectPieces("f'''{{a}} {b}'''", "brace:{{|literal:a|brace:}}|literal: |hole:b");
    try expectPieces("f\"\"\"\"\"\"", "literal:");
    try expectPieces("f\"\"\"{x[\"k\"]}\"\"\"", "hole:x[\"k\"]");
    // The one-line form is cut as before: one quote on each side.
    try expectPieces("f\"a {x}\"", "literal:a |hole:x");
    try expectPieces("f\"\"", "literal:");
}

test "F-19 a hole on a later line keeps its absolute position" {
    const text = "x = f\"\"\"one\ntwo\n  three {name} four\"\"\"";
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const src = try language.source.Source.init(arena.allocator(), "hole.selka", text);
    var sink: diagnostics.Sink = .{ .allocator = arena.allocator() };
    const cut = try format_strings.split(arena.allocator(), src, .{ .start = 4, .end = text.len }, &sink);
    const hole = cut[1].hole;
    try t.expectEqualStrings("name", src.text(hole));
    const at = src.locate(hole.start);
    try t.expectEqual(@as(usize, 3), at.line);
    try t.expectEqual(@as(usize, 10), at.column);
}

/// Run `source` and require the exit status `expected`.
fn expectExit(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "triple.selka", source);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}

test "F-19 the text is the plain triple-quoted text with holes: blank lines, indentation, tabs, quotes and braces kept" {
    try expectExit(
        "func main() -> int:\n" ++
            "    const name = \"ada\"\n" ++
            "    const n = 3\n" ++
            "    const xs = [1, 2, 3]\n" ++
            "    const built = \"first \" + name + \"\\n  second\\t\" + str(n + 1) + \"\\n\\\"q\\\" 'q'\\n\\nlast \" + str(xs)\n" ++
            "    const spelled = f\"\"\"first {name}\n  second\t{n + 1}\n\"q\" 'q'\n\nlast {xs}\"\"\"\n" ++
            "    if built != spelled:\n        return 1\n" ++
            "    const single = f'''a {{b}} \"c\" {name}'''\n" ++
            "    if single != \"a {b} \\\"c\\\" ada\":\n        return 2\n" ++
            "    const plain = \"\"\"first\n  second\"\"\"\n" ++
            "    const framed = f\"\"\"first\n  second\"\"\"\n" ++
            "    if plain != framed or len(framed) != 14:\n        return 3\n" ++
            "    const edges = f\"\"\"\n{name}\n\"\"\"\n" ++
            "    if edges != \"\\nada\\n\":\n        return 4\n" ++
            "    const quoted = f\"\"\"say \\\"hi\\\"\"\"\"\n" ++
            "    if quoted != \"say \\\"hi\\\"\" or f\"\"\"\"\"\" != \"\":\n        return 5\n" ++
            "    return 42\n",
        42,
    );
}

test "F-19 a hole may call, read a field, do arithmetic, show a list, take a format specification and sit on the last line" {
    try expectExit(
        "record Point:\n    x: int\n    y: int\n\n\n" ++
            "func twice(n: int) -> int:\n    return n * 2\n\n\n" ++
            "func main() -> int:\n" ++
            "    const p = Point(x=4, y=5)\n" ++
            "    const xs = [1, 2]\n" ++
            "    const text = f\"\"\"call {twice(p.x)}\nfield {p.y} sum {p.x + p.y}\nlist {xs} wide {p.x:>3}|\nlast {twice(1)}\"\"\"\n" ++
            "    if text != \"call 8\\nfield 5 sum 9\\nlist [1, 2] wide   4|\\nlast 2\":\n        return 1\n" ++
            "    return 42\n",
        42,
    );
}

/// The first diagnostic of checking `source`: its code, message and 1-based line and column, as `code line:column message`.
fn refusal(source: []const u8) ![]u8 {
    var c = try language.Compilation.init(t.allocator, "refuse.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    const first = c.diagnostics.items[0];
    const at = c.src.locate(first.span.start);
    return std.fmt.allocPrint(t.allocator, "{s} {d}:{d} {s}", .{ first.code, at.line, at.column, first.message });
}

fn expectRefusal(source: []const u8, expected: []const u8) !void {
    const got = try refusal(source);
    defer t.allocator.free(got);
    try t.expectEqualStrings(expected, got);
}

const hole_message = "a `{` in a triple-quoted format string closes on the line it opens: write the hole on one line, or `{{` for a literal brace";

test "F-19 a hole or a specification that does not close on its line is refused at its brace" {
    const head = "func main(out: Stream) -> int:\n    const x = 1\n";
    const tail = "\n    return 0\n";
    try expectRefusal(head ++ "    print(out, f\"\"\"a {x +\n 1} b\"\"\")" ++ tail, "E_FORMAT_STRING 3:22 " ++ hole_message);
    try expectRefusal(head ++ "    print(out, f\"\"\"a\nb {x\n} c\"\"\")" ++ tail, "E_FORMAT_STRING 4:3 " ++ hole_message);
    try expectRefusal(head ++ "    print(out, f'''a\nb {x:>5\n} c''')" ++ tail, "E_FORMAT_STRING 4:3 " ++ hole_message);
    // A text inside the hole stays on the line too, and so does a call's bracket.
    try expectRefusal(head ++ "    print(out, f\"\"\"a {str(\n x)} b\"\"\")" ++ tail, "E_FORMAT_STRING 3:22 " ++ hole_message);
    try expectRefusal(head ++ "    print(out, f\"\"\"a {\"t\n\"} b\"\"\")" ++ tail, "E_FORMAT_STRING 3:22 " ++ hole_message);
    try expectRefusal("func main(out: Stream) -> int:\r\n    const x = 1\r\n    print(out, f\"\"\"a\r\nb {x\r\n}\"\"\")\r\n    return 0\r\n", "E_FORMAT_STRING 4:3 " ++ hole_message);
}

/// The sentence a hole that was probably text ends with (FR21): how a literal brace is written, `quoted` as it stands and `doubled`.
fn braces_advice(comptime quoted: []const u8, comptime doubled: []const u8) []const u8 {
    return "A literal brace in a format string is written `{{` and `}}`: if `" ++ quoted ++ "` was meant as text, write `" ++ doubled ++ "`";
}

test "FR21 a lone brace in a triple-quoted format string says a literal brace is written {{, with this hole's opening doubled" {
    const head = "func main(out: Stream) -> int:\n    const color = \"red\"\n";
    const tail = "\n    return color\n";
    const nested = "a nested `{...}` inside a format specification is not supported; a specification is literal text such as `{value:>8.2f}`. ";
    // CSS with a hole inside the lone brace: the second brace is the one the refusal points at.
    try expectRefusal(head ++ "    print(out, f\"\"\"p { color: {color}; }\"\"\")" ++ tail, "E_FORMAT_STRING 3:31 " ++ nested ++ comptime braces_advice("{ color:", "{{ color:"));
    try expectRefusal(head ++ "    print(out, f\'\'\'p { color: {color}; }\'\'\')" ++ tail, "E_FORMAT_STRING 3:31 " ++ nested ++ comptime braces_advice("{ color:", "{{ color:"));
    // CSS with no hole in it is a specification that reads as text.
    try expectRefusal(head ++ "    print(out, f\"\"\"p { color: red; }\"\"\")" ++ tail, "E_FORMAT_STRING 3:30 Invalid format specifier. " ++ comptime braces_advice("{ color:", "{{ color:"));
    // A hole that is not one expression.
    try expectRefusal(head ++ "    print(out, f\"\"\"p {color red} q\"\"\")" ++ tail, "E_FORMAT_STRING 3:29 a format string interpolation holds exactly one expression. " ++ comptime braces_advice("{color red", "{{color red"));
    // The doubled form is the way out, in the triple form as in the one-line form.
    try expectExit("func main() -> int:\n    const color = \"red\"\n    const css = f\"\"\"p {{ color: {color}; }}\"\"\"\n" ++
        "    if css != \"p { color: red; }\":\n        return 1\n    return 42\n", 42);
}

test "F-19 the refusals that stay name the line of the hole, the escape or the opening quotes" {
    const head = "func main(out: Stream) -> int:\n    const x = 1\n";
    const tail = "\n    return 0\n";
    try expectRefusal(head ++ "    print(out, f\"\"\"a\nb\n  c {}\"\"\")" ++ tail, "E_FORMAT_STRING 5:6 a format string interpolation needs an expression");
    try expectRefusal(head ++ "    print(out, f\"\"\"a\nb\n  c }\"\"\")" ++ tail, "E_FORMAT_STRING 5:5 unmatched '}' in a format string; write '}}' for a literal brace");
    try expectRefusal(head ++ "    print(out, f\"\"\"a\\\nb\"\"\")" ++ tail, "E_BYTE_ESCAPE 3:21 unknown byte escape");
    try expectRefusal(head ++ "    print(out, f\"\"\"a\nb {x\"\"\")" ++ tail, "E_FORMAT_STRING 4:3 unterminated interpolation in a format string. " ++ comptime braces_advice("{x", "{{x"));
    try expectRefusal(head ++ "    print(out, f\"\"\"a\nb\n  c", "E_BYTE_LITERAL 3:17 unterminated triple-quoted format string: it opened on line 3 and has no closing three quotes of the same kind");
}

test "F-19 an error in a hole on the fourth line names that line and column" {
    const head = "func main(out: Stream) -> int:\n    const x = 1\n";
    try expectRefusal(head ++ "    print(out, f\"\"\"a\nb\n  c {x} d {y}\"\"\")\n    return 0\n", "E_UNKNOWN_NAME 5:12 name is not defined in this scope; did you mean `x`?");
    try expectRefusal(head ++ "    print(out, f'''a\nb\n  c {x} d {x + \"t\"}''')\n    return 0\n", "E_TYPE 5:14 expected int, found str");
}

test "F-19 a hole holding the literal's own three quotes ends the literal there, and the other quote kind is the way out" {
    const head = "func main(out: Stream) -> int:\n    const x = 1\n";
    try expectRefusal(head ++ "    print(out, f\"\"\"a {f\"\"\"y\"\"\"} b\"\"\")\n    return 0\n", "E_FORMAT_STRING 3:22 unterminated interpolation in a format string. " ++ comptime braces_advice("{f", "{{f"));
    try expectExit("func main() -> int:\n    const y = f'''a {f\"\"\"y\"\"\"} b'''\n    if y != \"a y b\":\n        return 1\n    return 42\n", 42);
}

fn formatted(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var c = try language.Compilation.init(allocator, "triple.selka", text);
    defer c.deinit();
    return c.format(allocator);
}

test "F-19 the formatter keeps every byte of a triple-quoted format string, holes included, and settles" {
    const program = "func f(x: int) -> str:\n    return f'''line {x}\n  \"two\"   {x   +  1}\n\n  {{three}}\t'''\n\n\n" ++
        "func main(out: Stream) -> int:\n    print(out, f\"\"\"a {1}\nb\"\"\", f'''c''')\n    return 0\n";
    const once = try formatted(t.allocator, program);
    defer t.allocator.free(once);
    try t.expect(std.mem.indexOf(u8, once, "f'''line {x}\n  \"two\"   {x   +  1}\n\n  {{three}}\t'''") != null);
    try t.expect(std.mem.indexOf(u8, once, "f\"\"\"a {1}\nb\"\"\"") != null);
    const twice = try formatted(t.allocator, once);
    defer t.allocator.free(twice);
    try t.expectEqualStrings(once, twice);
    // A program already in canonical form comes back unchanged.
    const canonical = "func f(x: int) -> str:\n    return f\"\"\"a {x}\n\n  b {x + 1}\n\"\"\"\n";
    const same = try formatted(t.allocator, canonical);
    defer t.allocator.free(same);
    try t.expectEqualStrings(canonical, same);
}

test "F-19 the token digest keys the text of a triple-quoted format string, a blank line inside it included" {
    const a = t.allocator;
    const base = "func f(x: int) -> str:\n    return f\"\"\"a {x}\n\nb\"\"\"\n";
    const blank_inside = "func f(x: int) -> str:\n    return f\"\"\"a {x}\n\n\nb\"\"\"\n";
    const blank_outside = "func f(x: int) -> str:\n\n    return f\"\"\"a {x}\n\nb\"\"\"\n\n";
    const comment = "func f(x: int) -> str:\n    # a comment\n    return f\"\"\"a {x}\n\nb\"\"\"\n";
    const first = (try token_digest.digest(a, base, "test")).?;
    try t.expect(!std.mem.eql(u8, &first, &(try token_digest.digest(a, blank_inside, "test")).?));
    try t.expectEqualSlices(u8, &first, &(try token_digest.digest(a, blank_outside, "test")).?);
    try t.expectEqualSlices(u8, &first, &(try token_digest.digest(a, comment, "test")).?);
}

test "F-19 a file saved with CRLF line ends keeps them in the text, as the plain form does" {
    try expectExit(
        "func main() -> int:\r\n    const x = 1\r\n    const t = f\"\"\"a\r\nb {x}\"\"\"\r\n    const p = \"\"\"a\r\nb 1\"\"\"\r\n" ++
            "    if t != p or len(t) != 6 or t[1] != 13 or t[2] != 10:\r\n        return 1\r\n    return 42\r\n",
        42,
    );
}

/// The token tags of `bytes` after the layout pass (`lexer.lex`: indent and dedent tokens included), joined by spaces.
fn laidOut(bytes: []const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var sink: diagnostics.Sink = .{ .allocator = arena.allocator() };
    const found = try lexer.lex(arena.allocator(), bytes, &sink);
    var out: std.ArrayList(u8) = .empty;
    for (found) |token| {
        if (out.items.len != 0) try out.append(arena.allocator(), ' ');
        try out.appendSlice(arena.allocator(), @tagName(token.tag));
    }
    return t.allocator.dupe(u8, out.items);
}

fn expectLayout(bytes: []const u8, expected: []const u8) !void {
    const got = try laidOut(bytes);
    defer t.allocator.free(got);
    try t.expectEqualStrings(expected, got);
}

test "FR24 a token after the closing quotes of a multi-line text continues the line they close on" {
    // Before, the token after the closing quotes was read as the first of a line of its own and the layout pass refused the line
    // after it (`E_INDENTATION`); the line the literal ends on is the line its next token is on.
    try expectLayout("x = \"\"\"a\nb\"\"\" + y\nz", "ident equal bytes plus ident ident eof");
    try expectLayout("x = f\"\"\"a {y}\nb\"\"\" + y\nz", "ident equal format plus ident ident eof");
    try expectLayout("if a:\n    x = '''a\nb''' + y\n    z", "kw_if ident indent ident equal bytes plus ident ident dedent eof");
    // Inside brackets the layout pass never looked: a comma and a further argument on the same line and on the next, a closing
    // bracket, a method call on the literal (`selka fmt` breaks such a call apart, so a guest test cannot pin them).
    try expectLayout("f(\"\"\"a\nb\"\"\", x)\ny", "ident lparen bytes comma ident rparen ident eof");
    try expectLayout("f(\"\"\"a\nb\"\"\",\n  x)\ny", "ident lparen bytes comma ident rparen ident eof");
    try expectLayout("x = (\"\"\"a\nb\"\"\")\ny", "ident equal lparen bytes rparen ident eof");
    try expectLayout("x = \"\"\"a\nb\"\"\".upper()\ny", "ident equal bytes dot ident lparen rparen ident eof");
    // A colon after the closing quotes ends the line and opens the suite, and a comment after them ends nothing.
    try expectLayout("if \"\"\"a\nb\"\"\" == x:\n    y", "kw_if bytes eq_eq ident indent ident dedent eof");
    try expectLayout("x = \"\"\"a\nb\"\"\"  # note\ny", "ident equal bytes ident eof");
    // Only a triple-quoted text can span lines (`tripleQuoted` in the layout pass): the empty triple, a one-line text and a
    // b-prefixed triple (a one-quote text and more) are on the line they start on, as before.
    try expectLayout("x = \"\"\"\"\"\" + y\nz", "ident equal bytes plus ident ident eof");
    try expectLayout("x = f\"\"\"\"\"\" + y\nz", "ident equal format plus ident ident eof");
    try expectLayout("x = \"ab\" + y\nz", "ident equal bytes plus ident ident eof");
    try expectLayout("x = b\"\"\"x\"\"\" + y\nz", "ident equal bytes bytes bytes plus ident ident eof");
    // What was accepted before reads the same: the statement ends with the quotes, the closing line has the block's indent.
    try expectLayout("x = \"\"\"a\nb\"\"\"\ny", "ident equal bytes ident eof");
    try expectLayout("if a:\n    x = \"\"\"a\n    b\"\"\" + y\n    z", "kw_if ident indent ident equal bytes plus ident ident dedent eof");
}

test "FR24 a line after a multi-line text that is out of place is still refused" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text = "if a:\n    x = \"\"\"a\nb\"\"\" + y\n  z";
    var sink: diagnostics.Sink = .{ .allocator = arena.allocator() };
    try t.expectError(error.SourceError, lexer.lex(arena.allocator(), text, &sink));
    try t.expectEqualStrings("E_INDENTATION", sink.items.items[0].code);
}
