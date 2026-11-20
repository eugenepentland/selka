//! The formatter's safety net: text that does not parse, or parses to other syntax than its input, is refused with
//! `E_FORMAT_VERIFY` at the input line of the construct that changed, and layout, comments, trailing commas, literal quoting and
//! the `from` clause order the formatter chooses are not differences (F-S1a-10).
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

const input =
    \\func both(a: bool, b: bool) -> bool:
    \\    return (
    \\        a
    \\        and b
    \\    )
    \\
    \\
    \\func name() -> str:
    \\    return 'x'
    \\
    \\
    \\func main() -> int:
    \\    if both(True, False):
    \\        return 1
    \\    return 0
    \\
;

/// The tokens and syntax of the input, parsed as a module or as a program.
fn parsedInput(compilation: *language.Compilation, module: bool) !language.Compilation.ModuleParse {
    if (module) return compilation.parseModuleSyntax();
    try compilation.parse();
    return .{ .tokens = compilation.tokens.?, .syntax = compilation.syntax.? };
}

/// Parse `text` as the input and hold `candidate` to it, as `format` does with its own output.
fn verify(text: []const u8, candidate: []const u8, module: bool) !language.Compilation {
    var compilation = try language.Compilation.init(t.allocator, "unit.selka", text);
    errdefer compilation.deinit();
    const parsed = try parsedInput(&compilation, module);
    try compilation.verifyFormatted(t.allocator, candidate, .{ .tokens = parsed.tokens, .syntax = parsed.syntax, .module = module });
    return compilation;
}

/// Require that `candidate` is refused: the diagnostic names the input line, the code and a fragment of its message.
fn expectRefused(text: []const u8, candidate: []const u8, module: bool, line: usize, fragment: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "unit.selka", text);
    defer compilation.deinit();
    const parsed = try parsedInput(&compilation, module);
    try t.expectError(error.FormatRejected, compilation.verifyFormatted(t.allocator, candidate, .{ .tokens = parsed.tokens, .syntax = parsed.syntax, .module = module }));
    const item = compilation.diagnostics.items[compilation.diagnostics.items.len - 1];
    try t.expectEqualStrings("E_FORMAT_VERIFY", item.code);
    try t.expectEqual(line, compilation.src.locate(item.span.start).line);
    try t.expect(std.mem.indexOf(u8, item.message, fragment) != null);
    try t.expect(std.mem.indexOf(u8, item.message, "nothing was written") != null);
}

test "the net accepts text that only changes layout, comments, trailing commas and literal quoting" {
    var compilation = try verify(input,
        \\func both(a: bool, b: bool) -> bool:
        \\    return (a   and   b)   # the same expression on one line
        \\
        \\
        \\func name() -> str:
        \\    return "x"
        \\
        \\
        \\func main() -> int:
        \\    if both(True, False,):
        \\        return 1
        \\    return 0
        \\
    , false);
    compilation.deinit();
}

test "the net refuses text that does not parse, at the input line of the construct" {
    // The old formatter's output for the `return (` above: a one-element tuple.
    try expectRefused(input,
        \\func both(a: bool, b: bool) -> bool:
        \\    return (
        \\        a and b,
        \\    )
        \\
        \\
        \\func name() -> str:
        \\    return 'x'
        \\
        \\
        \\func main() -> int:
        \\    if both(True, False):
        \\        return 1
        \\    return 0
        \\
    , false, 4, "a one-element tuple is not a value");
}

test "the net names the formatted line beside the input line" {
    try expectRefused(input,
        \\func both(a: bool, b: bool) -> bool:
        \\    return (
        \\        a and b,
        \\    )
        \\
        \\
        \\func name() -> str:
        \\    return 'x'
        \\
        \\
        \\func main() -> int:
        \\    if both(True, False):
        \\        return 1
        \\    return 0
        \\
    , false, 4, "(formatted line 3: `a and b,`)");
}

test "the net refuses text that parses to a different expression" {
    try expectRefused(input,
        \\func both(a: bool, b: bool) -> bool:
        \\    return (
        \\        a or b
        \\    )
        \\
        \\
        \\func name() -> str:
        \\    return 'x'
        \\
        \\
        \\func main() -> int:
        \\    if both(True, False):
        \\        return 1
        \\    return 0
        \\
    , false, 2, "parses to different syntax");
}

test "the net refuses text that drops a statement or changes a literal or a name" {
    const dropped =
        \\func both(a: bool, b: bool) -> bool:
        \\    return (a and b)
        \\
        \\
        \\func name() -> str:
        \\    return 'x'
        \\
        \\
        \\func main() -> int:
        \\    if both(True, False):
        \\        return 1
        \\
    ;
    try expectRefused(input, dropped, false, 15, "parses to different syntax");
    const literal = std.mem.replaceOwned(u8, t.allocator, input, "'x'", "'y'") catch unreachable;
    defer t.allocator.free(literal);
    try expectRefused(input, literal, false, 9, "parses to different syntax");
    const renamed = std.mem.replaceOwned(u8, t.allocator, input, "both(True", "name2(True") catch unreachable;
    defer t.allocator.free(renamed);
    try expectRefused(input, renamed, false, 13, "parses to different syntax");
}

test "the net refuses a module whose formatted text drops an import or does not parse" {
    const module_input =
        \\import lists
        \\import strings
        \\
        \\func main() -> int:
        \\    return 0
        \\
    ;
    var accepted = try verify(module_input,
        \\import strings
        \\import lists
        \\
        \\func main() -> int:
        \\    return 0
        \\
    , true);
    accepted.deinit();
    try expectRefused(module_input,
        \\import lists
        \\
        \\func main() -> int:
        \\    return 0
        \\
    , true, 2, "import");
    try expectRefused(module_input,
        \\import lists
        \\import strings
        \\
        \\func main() -> int:
        \\    return (0,)
        \\
    , true, 5, "a one-element tuple is not a value");
}

test "the net refuses through verifyFormatted with error.FormatRejected and leaves its diagnostic" {
    var compilation = try language.Compilation.init(t.allocator, "unit.selka", input);
    defer compilation.deinit();
    const parsed = try parsedInput(&compilation, false);
    try t.expectError(error.FormatRejected, compilation.verifyFormatted(t.allocator, "func main() -> int:\n    return (0,)\n", .{ .tokens = parsed.tokens, .syntax = parsed.syntax, .module = false }));
    try t.expectEqual(@as(usize, 1), compilation.diagnostics.items.len);
    try t.expectEqualStrings("E_FORMAT_VERIFY", compilation.diagnostics.items[0].code);
}

test "the net compares nothing when the formatted text is the input" {
    var compilation = try language.Compilation.init(t.allocator, "unit.selka", input);
    defer compilation.deinit();
    const parsed = try parsedInput(&compilation, false);
    try compilation.verifyFormatted(t.failing_allocator, input, .{ .tokens = parsed.tokens, .syntax = parsed.syntax, .module = false });
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

test "the formatter output of a source it mishandled before the fix passes the net" {
    var compilation = try language.Compilation.init(t.allocator, "unit.selka", input);
    defer compilation.deinit();
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "(a and b,)") == null);
    try t.expect(std.mem.indexOf(u8, formatted, "        a and b\n    )") != null);
}
