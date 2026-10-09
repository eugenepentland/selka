//! Python numeric literal spellings: diagnostics for malformed and out-of-range literals,
//! token boundaries against field access, and byte-for-byte formatting.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const lexer = language.lexer;
const source = language.source;
const diagnostic = language.diagnostic;
const number_literal = @import("number_literal.zig");

const Case = struct { body: []const u8, code: []const u8, fragment: []const u8 };

/// Check `func main() -> i64:` around one body and return the first diagnostic.
fn firstDiagnostic(arena: std.mem.Allocator, body: []const u8) !struct { code: []const u8, message: []const u8 } {
    const text = try std.fmt.allocPrint(arena, "func main() -> i64:\n    {s}\n    return 0\n", .{body});
    var compilation = try language.Compilation.init(arena, "literal.my", text);
    try t.expectError(error.SourceError, compilation.check());
    const first = compilation.diagnostics.items[0];
    return .{ .code = first.code, .message = first.message };
}

fn expectRejected(cases: []const Case) !void {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    for (cases) |case| {
        const found = try firstDiagnostic(arena, case.body);
        // Comparing labelled lines names the failing literal in the test output.
        const wanted = try std.fmt.allocPrint(arena, "`{s}` => {s}", .{ case.body, case.code });
        const actual = try std.fmt.allocPrint(arena, "`{s}` => {s}: {s}", .{ case.body, found.code, found.message });
        try t.expectEqualStrings(wanted, actual[0..@min(actual.len, wanted.len)]);
        const mentions = std.mem.indexOf(u8, found.message, case.fragment) != null;
        try t.expectEqualStrings(wanted, if (mentions) wanted else actual);
    }
}

// spec: NUM-LITERAL-5
test "malformed integer spellings are E_INTEGER_LITERAL errors that say what is wrong" {
    try expectRejected(&.{
        .{ .body = "_ = 1__0", .code = "E_INTEGER_LITERAL", .fragment = "doubled underscore" },
        .{ .body = "_ = 1_", .code = "E_INTEGER_LITERAL", .fragment = "must be followed by a digit" },
        .{ .body = "_ = 0_x1", .code = "E_INTEGER_LITERAL", .fragment = "must be followed by a digit" },
        .{ .body = "_ = 1_u8", .code = "E_INTEGER_LITERAL", .fragment = "suffix goes directly after the last digit" },
        .{ .body = "_ = 0x__F", .code = "E_INTEGER_LITERAL", .fragment = "doubled underscore" },
        .{ .body = "_ = 0xF_", .code = "E_INTEGER_LITERAL", .fragment = "must be followed by a digit" },
        .{ .body = "_ = 0x", .code = "E_INTEGER_LITERAL", .fragment = "hexadecimal digit" },
        .{ .body = "_ = 0xg", .code = "E_INTEGER_LITERAL", .fragment = "hexadecimal digit" },
        .{ .body = "_ = 0o", .code = "E_INTEGER_LITERAL", .fragment = "octal digit" },
        .{ .body = "_ = 0b", .code = "E_INTEGER_LITERAL", .fragment = "binary digit" },
        .{ .body = "_ = 0b12", .code = "E_INTEGER_LITERAL", .fragment = "binary digits are 0 and 1" },
        .{ .body = "_ = 0o18", .code = "E_INTEGER_LITERAL", .fragment = "octal digits are 0 through 7" },
    });
}

// spec-case: NUM-LITERAL-1
test "decimal integers reject leading zeros and say how to write octal" {
    try expectRejected(&.{
        .{ .body = "_ = 0755", .code = "E_INTEGER_LITERAL", .fragment = "write `0o755` for octal" },
        .{ .body = "_ = 01", .code = "E_INTEGER_LITERAL", .fragment = "leading zeros are not allowed" },
        .{ .body = "_ = 0_1", .code = "E_INTEGER_LITERAL", .fragment = "leading zeros are not allowed" },
        .{ .body = "_ = 00_7", .code = "E_INTEGER_LITERAL", .fragment = "leading zeros are not allowed" },
        .{ .body = "_ = 007u8", .code = "E_INTEGER_LITERAL", .fragment = "leading zeros are not allowed" },
        .{ .body = "_ = -0009223372036854775808", .code = "E_INTEGER_LITERAL", .fragment = "or `755` for decimal" },
    });
    try expectConstantRejected("const MODE: u32 = 0644\n\n\nfunc main() -> i64:\n    return 0\n", "E_INTEGER_LITERAL");
}

// spec-case: NUM-LITERAL-1
test "a decimal run of zeros and a float with leading zeros stay legal" {
    try t.expectEqual(number_literal.CountResult{ .ok = 0 }, number_literal.count("0_0"));
    try t.expectEqual(number_literal.CountResult{ .ok = 0 }, number_literal.count("00"));
    try t.expectEqual(number_literal.CountResult{ .ok = 0 }, number_literal.count("0"));
    try t.expect(number_literal.isFloat("007.5"));
    try t.expect(number_literal.isFloat("01e2"));
}

// spec-case: NUM-LITERAL-5
test "malformed float spellings and imaginary literals are rejected with a message" {
    try expectRejected(&.{
        .{ .body = "_ = 1_.5", .code = "E_FLOAT_LITERAL", .fragment = "must be followed by a digit" },
        .{ .body = "_ = 1.5_", .code = "E_FLOAT_LITERAL", .fragment = "must be followed by a digit" },
        .{ .body = "_ = 1.5__0", .code = "E_FLOAT_LITERAL", .fragment = "doubled underscore" },
        .{ .body = "_ = 1e", .code = "E_FLOAT_LITERAL", .fragment = "exponent needs digits" },
        .{ .body = "_ = 1e+", .code = "E_FLOAT_LITERAL", .fragment = "exponent needs digits" },
        .{ .body = "_ = 1e_5", .code = "E_FLOAT_LITERAL", .fragment = "must sit between two digits" },
        .{ .body = "_ = 1.5u8", .code = "E_FLOAT_LITERAL", .fragment = "takes no suffix" },
        .{ .body = "_ = 1.5j", .code = "E_FLOAT_LITERAL", .fragment = "no complex numbers" },
        .{ .body = "_ = 1j", .code = "E_INTEGER_SUFFIX", .fragment = "no complex numbers" },
        .{ .body = "_ = 1x", .code = "E_INTEGER_SUFFIX", .fragment = "unknown integer suffix" },
        .{ .body = "_ = 0xFFz", .code = "E_INTEGER_SUFFIX", .fragment = "unknown integer suffix" },
        .{ .body = "_ = 0xFFi7", .code = "E_INTEGER_SUFFIX", .fragment = "unknown integer suffix" },
    });
}

// spec-case: NUM-LITERAL-5
test "a literal outside its expected or suffixed type is E_INTEGER_RANGE in every base" {
    try expectRejected(&.{
        .{ .body = "const n: u8 = 256", .code = "E_INTEGER_RANGE", .fragment = "does not fit" },
        .{ .body = "const n: u8 = 0x100", .code = "E_INTEGER_RANGE", .fragment = "does not fit" },
        .{ .body = "const n: u8 = 0b1_0000_0000", .code = "E_INTEGER_RANGE", .fragment = "does not fit" },
        .{ .body = "const n: u8 = 0o400", .code = "E_INTEGER_RANGE", .fragment = "does not fit" },
        .{ .body = "const n: u32 = 0x1_0000_0000", .code = "E_INTEGER_RANGE", .fragment = "does not fit" },
        .{ .body = "const n: i32 = 0xFFFFFFFF", .code = "E_INTEGER_RANGE", .fragment = "does not fit" },
        .{ .body = "const n: i8 = -0x81", .code = "E_INTEGER_RANGE", .fragment = "does not fit" },
        .{ .body = "_ = 0xFFi8", .code = "E_INTEGER_RANGE", .fragment = "does not fit" },
        .{ .body = "_ = 0x10000000000000000", .code = "E_INTEGER_RANGE", .fragment = "does not fit" },
        .{ .body = "_ = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF", .code = "E_INTEGER_RANGE", .fragment = "too large" },
    });
}

fn expectConstantRejected(text: []const u8, code: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    var compilation = try language.Compilation.init(arena_state.allocator(), "constant.my", text);
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

// spec-case: NUM-LITERAL-5
test "constant initializers reject a literal that does not fit the declared type" {
    try expectConstantRejected("const LOW: u8 = 0x100\n\n\nfunc main() -> i64:\n    return 0\n", "E_INTEGER_RANGE");
    try expectConstantRejected("const HIGH: u32 = 4294967296\n\n\nfunc main() -> i64:\n    return 0\n", "E_INTEGER_RANGE");
    try expectConstantRejected("const BAD: u32 = 0xFFFF_FFFF_1\n\n\nfunc main() -> i64:\n    return 0\n", "E_INTEGER_RANGE");
    try expectConstantRejected("const BAD: u32 = 0x_\n\n\nfunc main() -> i64:\n    return 0\n", "E_INTEGER_LITERAL");
}

const Piece = struct { tag: lexer.Tag, text: []const u8 };

/// Lex `bytes` and compare every token before the end of file with `expected`.
fn expectTokens(bytes: []const u8, expected: []const Piece) !void {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var sink: diagnostic.Sink = .{ .allocator = arena };
    const tokens = try lexer.lex(arena, bytes, &sink);
    try t.expectEqual(expected.len + 1, tokens.len);
    for (expected, tokens[0..expected.len]) |piece, token| {
        try t.expectEqual(piece.tag, token.tag);
        try t.expectEqualStrings(piece.text, bytes[token.span.start..token.span.end]);
    }
}

// spec: NUM-LITERAL-3
test "numeric tokens keep field access on names calls and integers apart from leading and trailing dots" {
    try expectTokens("return .5", &.{ .{ .tag = .kw_return, .text = "return" }, .{ .tag = .integer, .text = ".5" } });
    try expectTokens("f(a,.5)", &.{
        .{ .tag = .ident, .text = "f" },
        .{ .tag = .lparen, .text = "(" },
        .{ .tag = .ident, .text = "a" },
        .{ .tag = .comma, .text = "," },
        .{ .tag = .integer, .text = ".5" },
        .{ .tag = .rparen, .text = ")" },
    });
    try expectTokens("x.5", &.{ .{ .tag = .ident, .text = "x" }, .{ .tag = .dot, .text = "." }, .{ .tag = .integer, .text = "5" } });
    try expectTokens("f().5", &.{ .{ .tag = .ident, .text = "f" }, .{ .tag = .lparen, .text = "(" }, .{ .tag = .rparen, .text = ")" }, .{ .tag = .dot, .text = "." }, .{ .tag = .integer, .text = "5" } });
    try expectTokens("5.name", &.{ .{ .tag = .integer, .text = "5" }, .{ .tag = .dot, .text = "." }, .{ .tag = .ident, .text = "name" } });
    try expectTokens("5.else", &.{ .{ .tag = .integer, .text = "5" }, .{ .tag = .dot, .text = "." }, .{ .tag = .kw_else, .text = "else" } });
    try expectTokens("5. + 1.e2 + 1.5e-3", &.{
        .{ .tag = .integer, .text = "5." },
        .{ .tag = .plus, .text = "+" },
        .{ .tag = .integer, .text = "1.e2" },
        .{ .tag = .plus, .text = "+" },
        .{ .tag = .integer, .text = "1.5e-3" },
    });
    try expectTokens("[1_000.5, 1e1_0]", &.{ .{ .tag = .lbracket, .text = "[" }, .{ .tag = .integer, .text = "1_000.5" }, .{ .tag = .comma, .text = "," }, .{ .tag = .integer, .text = "1e1_0" }, .{ .tag = .rbracket, .text = "]" } });
}

// spec-case: NUM-LITERAL-2
test "a prefixed literal scans its digits and suffix as one token and splits at the first non-digit" {
    try expectTokens("0xFFu8", &.{.{ .tag = .integer, .text = "0xFFu8" }});
    try expectTokens("0x_DEAD_beefu32 + 0B1010i8", &.{ .{ .tag = .integer, .text = "0x_DEAD_beefu32" }, .{ .tag = .plus, .text = "+" }, .{ .tag = .integer, .text = "0B1010i8" } });
    const hex = number_literal.integer("0xE5u8").ok;
    try t.expectEqual(@as(u8, 16), hex.base);
    try t.expectEqualStrings("E5", hex.digits);
    try t.expectEqualStrings("u8", hex.suffix);
    const binary = number_literal.integer("0b1_0i16").ok;
    try t.expectEqual(@as(u8, 2), binary.base);
    try t.expectEqual(@as(?u128, 2), number_literal.magnitude(binary));
    try t.expectEqualStrings("i16", binary.suffix);
    const octal = number_literal.integer("0o17").ok;
    try t.expectEqual(@as(?u128, 15), number_literal.magnitude(octal));
    try t.expectEqualStrings("", octal.suffix);
    try t.expect(!number_literal.isFloat("0xE5"));
    try t.expect(number_literal.isFloat("1e5"));
}

// spec: NUM-LITERAL-6
test "the formatter reproduces every numeric spelling byte for byte" {
    const text =
        \\const MASK: u32 = 0xFF00_0000
        \\
        \\
        \\func main() -> int:
        \\    mut a = 0XDEAD_beef
        \\    mut b = 0o17
        \\    mut c = 0B1010_1010
        \\    mut d = 1_000u32
        \\    mut e = .5
        \\    mut f = 5.
        \\    mut g = 1_000.5e1_0
        \\    mut h = 0x_FFu8
        \\    return 0
        \\
    ;
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    var compilation = try language.Compilation.init(arena_state.allocator(), "spelling.my", text);
    const formatted = try compilation.format(arena_state.allocator());
    try t.expectEqualStrings(text, formatted);
}

fn expectLengthRejected(length: []const u8, code: []const u8, fragment: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const text = try std.fmt.allocPrint(arena, "func main() -> i64:\n    const a: FixedArray[i64, {s}] = FixedArray[i64, 1]([1])\n    return a[0]\n", .{length});
    var compilation = try language.Compilation.init(arena, "length.my", text);
    try t.expectError(error.SourceError, compilation.check());
    const first = compilation.diagnostics.items[0];
    // Comparing labelled lines names the failing length in the test output.
    const wanted = try std.fmt.allocPrint(arena, "`[{s}]` => {s}", .{ length, code });
    const actual = try std.fmt.allocPrint(arena, "`[{s}]` => {s}", .{ length, first.code });
    try t.expectEqualStrings(wanted, actual);
    const found = if (std.mem.indexOf(u8, first.message, fragment) != null) fragment else first.message;
    try t.expectEqualStrings(fragment, found);
    try t.expectEqualStrings(length, compilation.src.text(first.span));
}

// spec-case: NUM-LITERAL-7
test "array lengths reject a width suffix and every malformed integer spelling" {
    try expectLengthRejected("2u8", "E_ARRAY_LENGTH", "no width suffix");
    try expectLengthRejected("0x10u8", "E_ARRAY_LENGTH", "no width suffix");
    try expectLengthRejected("010", "E_ARRAY_LENGTH", "leading zeros are not allowed");
    try expectLengthRejected("1__0", "E_ARRAY_LENGTH", "doubled underscore");
    try expectLengthRejected("1_", "E_ARRAY_LENGTH", "must be followed by a digit");
    try expectLengthRejected("0x", "E_ARRAY_LENGTH", "hexadecimal digit");
    try expectLengthRejected("0b12", "E_ARRAY_LENGTH", "binary digits are 0 and 1");
    try expectLengthRejected("0x1_0000_0000_0000_0000_0", "E_ARRAY_LENGTH", "exceeds the host index range");
}

fn expectChecks(text: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    var compilation = try language.Compilation.init(arena_state.allocator(), "spelling.my", text);
    try compilation.check();
}

// spec-case: NUM-LITERAL-7
test "one array type has one identity whichever integer spelling writes its length" {
    try expectChecks(
        \\func take(a: FixedArray[u8, 16]) -> u8:
        \\    return a[0]
        \\
        \\
        \\func main() -> i64:
        \\    mut hex: FixedArray[u8, 0x10] = FixedArray[u8, 16]([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8])
        \\    return i64(take(hex))
        \\
    );
    try expectChecks(
        \\func make[T, const N: u64](items: FixedArray[T, N]) -> T:
        \\    return items[0]
        \\
        \\
        \\func main() -> i64:
        \\    mut values: FixedArray[i64, 2] = FixedArray[int, 2]([40, 2])
        \\    return make[i64, 0x2](values) + make[i64, 0b10](values) + make[i64, 0o2](values) + make[i64, 2](values)
        \\
    );
    try expectChecks(
        \\record Chunk[T, const N: u64]:
        \\    items: FixedArray[T, N]
        \\
        \\
        \\func main() -> i64:
        \\    mut chunk = Chunk[i64, 0x2](items=FixedArray[int, 2]([4, 5]))
        \\    return chunk.items[1]
        \\
    );
}

// spec-case: NUM-LITERAL-7
test "const generic length arguments share the array length spellings and bound" {
    try expectLengthArgumentRejected("0x2u8", "no width suffix");
    try expectLengthArgumentRejected("02", "leading zeros are not allowed");
    try expectLengthArgumentRejected("0x100001", "exceeds 1048576");
    try expectLengthArgumentRejected("1__0", "doubled underscore");
}

fn expectLengthArgumentRejected(length: []const u8, fragment: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const text = try std.fmt.allocPrint(arena, "func pick[T, const N: u64](items: FixedArray[T, N]) -> T:\n    return items[0]" ++
        "\n\n\nfunc main() -> i64:\n    const values = FixedArray[i64, 2]([40, 2])\n    return pick[i64, {s}](values)\n", .{length});
    var compilation = try language.Compilation.init(arena, "argument.my", text);
    try t.expectError(error.SourceError, compilation.check());
    const first = compilation.diagnostics.items[0];
    const wanted = try std.fmt.allocPrint(arena, "`{s}` => E_GENERIC_LENGTH", .{length});
    const actual = try std.fmt.allocPrint(arena, "`{s}` => {s}", .{ length, first.code });
    try t.expectEqualStrings(wanted, actual);
    const found = if (std.mem.indexOf(u8, first.message, fragment) != null) fragment else first.message;
    try t.expectEqualStrings(fragment, found);
}
