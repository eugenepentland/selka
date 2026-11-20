//! Literal match arms: each refusal, with the diagnostic code it reports.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const transition = @import("ownership_transition_test_support.zig");

/// Check one program, which must be refused, and require its first diagnostic's code.
fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "literal.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

test "a match on an int with literal arms needs case _ to cover the other values" {
    try reject(
        \\func f(v: int) -> int:
        \\    match v:
        \\        case 1:
        \\            return 1
        \\
        \\func main() -> int:
        \\    return f(1)
    , "E_INCOMPLETE_MATCH");
}

test "a match on bool lists both values or ends with case _" {
    try reject(
        \\func f(v: bool) -> int:
        \\    match v:
        \\        case True:
        \\            return 1
        \\
        \\func main() -> int:
        \\    return f(True)
    , "E_INCOMPLETE_MATCH");
}

test "case _ must be the last arm of a literal match" {
    try reject(
        \\func f(v: int) -> int:
        \\    match v:
        \\        case _:
        \\            return 0
        \\        case 1:
        \\            return 1
        \\
        \\func main() -> int:
        \\    return f(1)
    , "E_WILDCARD_ARM");
}

test "case _ after both bool values is unreachable" {
    try reject(
        \\func f(v: bool) -> int:
        \\    match v:
        \\        case True:
        \\            return 1
        \\        case False:
        \\            return 0
        \\        case _:
        \\            return 2
        \\
        \\func main() -> int:
        \\    return f(True)
    , "E_WILDCARD_ARM");
}

test "a literal that repeats an earlier arm is a duplicate arm" {
    try reject(
        \\func f(v: int) -> int:
        \\    match v:
        \\        case 1:
        \\            return 1
        \\        case 1:
        \\            return 2
        \\        case _:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return f(1)
    , "E_DUPLICATE_ARM");
}

test "a str literal in an int match is refused with the matched type" {
    try reject(
        \\func f(v: int) -> int:
        \\    match v:
        \\        case "a":
        \\            return 1
        \\        case _:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return f(1)
    , "E_LITERAL_ARM");
}

test "alternatives of different kinds in one arm are refused" {
    try reject(
        \\func f(v: int) -> int:
        \\    match v:
        \\        case 1 | "a":
        \\            return 1
        \\        case _:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return f(1)
    , "E_LITERAL_ARM");
}

test "a literal arm is refused on an enum, whose cases are named" {
    try reject(
        \\enum Shape:
        \\    circle(radius: int)
        \\    empty
        \\
        \\func f(v: Shape) -> int:
        \\    match v:
        \\        case 1:
        \\            return 1
        \\        case _:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return f(Shape.empty)
    , "E_LITERAL_ARM");
}

test "a qualified constant arm is refused, because a constant is named alone" {
    try reject(
        \\const LIMIT: int = 7
        \\
        \\func f(v: int) -> int:
        \\    match v:
        \\        case Kind.LIMIT:
        \\            return 1
        \\        case _:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return f(1)
    , "E_LITERAL_ARM");
}

test "a literal inside a case payload is refused; a literal is a whole arm" {
    try reject(
        \\func f(v: int?) -> int:
        \\    match v:
        \\        case Some(1):
        \\            return 1
        \\        case _:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return f(None)
    , "E_SYNTAX");
}

test "a literal arm in a generic function is refused until the generic check supports it" {
    try reject(
        \\func f[T](v: int, x: T) -> int:
        \\    match v:
        \\        case 1:
        \\            return 1
        \\        case _:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return f(1, 2)
    , "E_LITERAL_ARM");
}

test "a bare name that is not a constant is refused: an arm names a constant, not a capture" {
    try reject(
        \\func f(v: int) -> int:
        \\    match v:
        \\        case NOPE:
        \\            return 1
        \\        case _:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return f(1)
    , "E_LITERAL_ARM");
}

test "a parameter named in an arm is refused, because a bare name there is not a capture" {
    try reject(
        \\func pick(n: int, limit: int) -> int:
        \\    match n:
        \\        case limit:
        \\            return 1
        \\        case _:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return pick(3, 3)
    , "E_LITERAL_ARM");
}

test "a local named in an arm is refused: comparing with a variable is written with if" {
    try reject(
        \\func pick(n: int) -> int:
        \\    const limit = 3
        \\    match n:
        \\        case limit:
        \\            return 1
        \\        case _:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return pick(3)
    , "E_LITERAL_ARM");
}

test "1 and 0x1 are one value, so the second arm repeats the first" {
    try reject(
        \\func f(v: int) -> int:
        \\    match v:
        \\        case 1:
        \\            return 1
        \\        case 0x1:
        \\            return 2
        \\        case _:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return f(1)
    , "E_DUPLICATE_ARM");
}

test "a string and its escape are one value, so the second arm repeats the first" {
    try reject(
        \\func f(v: str) -> int:
        \\    match v:
        \\        case "a":
        \\            return 1
        \\        case "\x61":
        \\            return 2
        \\        case _:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return f("a")
    , "E_DUPLICATE_ARM");
}

test "the same constant listed twice is a duplicate arm" {
    try reject(
        \\const LIMIT: int = 7
        \\
        \\func f(v: int) -> int:
        \\    match v:
        \\        case LIMIT:
        \\            return 1
        \\        case LIMIT:
        \\            return 2
        \\        case _:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return f(7)
    , "E_DUPLICATE_ARM");
}

test "a constant repeats a literal arm whose value it has" {
    try reject(
        \\const LIMIT: int = 7
        \\
        \\func f(v: int) -> int:
        \\    match v:
        \\        case 7:
        \\            return 1
        \\        case LIMIT:
        \\            return 2
        \\        case _:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return f(7)
    , "E_DUPLICATE_ARM");
}

test "O2 literal match projected copies pass typing and are refused by Core" {
    const source =
        \\record Entry:
        \\    text: str
        \\func choose(entry: Entry) -> int:
        \\    match entry.text:
        \\        case "a":
        \\            return 1
        \\        case _:
        \\            return 0
        \\func main() -> int:
        \\    return choose(Entry(text="a"))
    ;
    var compilation = try language.Compilation.init(t.allocator, "literal.selka", source);
    defer compilation.deinit();
    try compilation.check();
    try t.expect(compilation.program != null);
    try transition.refuses(t.allocator, source, "E_LITERAL_ARM");
}
