//! Tuple diagnostics, identity and surface spelling: the four rejections the
//! plan fixes, the expected-type rule for literals, and the one identity every
//! equal element list interns to.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
/// Source name every fixture in this file is checked under.
const unit_name = "tuples.my";

/// Check one unit and require it to be accepted.
fn accepts(source: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, unit_name, source);
    defer compilation.deinit();
    try compilation.check();
}

/// Check one unit and require its first diagnostic to carry `code`.
fn rejects(source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, unit_name, source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

/// Check one unit and return an owned copy of its first diagnostic message.
fn message(source: []const u8) ![]u8 {
    var compilation = try language.Compilation.init(t.allocator, unit_name, source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    return t.allocator.dupe(u8, compilation.diagnostics.items[0].message);
}

// spec: TUPLE-1
test "a tuple type is one interned record with positional fields and a source spelling" {
    // The same element list written twice is one type: both parameters accept
    // each other's value with no conversion at all.
    try accepts(
        \\def pair_left(p: tuple[int, str]) -> str:
        \\    return "x"
        \\
        \\
        \\def pair_right(p: tuple[int, str]) -> str:
        \\    return pair_left(p)
        \\
        \\
        \\def main() -> int:
        \\    return 0
        \\
    );
    // A mismatched element list is the ordinary expected/found message, in the
    // source spelling of both types.
    const found = try message(
        \\def pair(p: tuple[int, str]) -> int:
        \\    return 0
        \\
        \\
        \\def main() -> int:
        \\    return pair(7)
        \\
    );
    defer t.allocator.free(found);
    try t.expect(std.mem.indexOf(u8, found, "expected tuple[int, str], found int") != null);
}

// spec-case: TUPLE-1
test "a tuple spelling outside two to eight elements is E_TUPLE_ARITY at the spelling" {
    try rejects(
        \\def f(p: tuple[int]) -> int:
        \\    return 0
        \\
        \\
        \\def main() -> int:
        \\    return 0
        \\
    , "E_TUPLE_ARITY");
    try rejects(
        \\def f(p: tuple[int, str, int, str, int, str, int, str, int]) -> int:
        \\    return 0
        \\
        \\
        \\def main() -> int:
        \\    return 0
        \\
    , "E_TUPLE_ARITY");
    // Nested element types keep the source spelling too.
    const nested = try message(
        \\def f(p: tuple[list[int], str]) -> int:
        \\    return 0
        \\
        \\
        \\def main() -> int:
        \\    return f(1)
        \\
    );
    defer t.allocator.free(nested);
    try t.expect(std.mem.indexOf(u8, nested, "expected tuple[list[int], str], found int") != null);
}

// spec: TUPLE-2
test "a tuple value takes its element types from the destination or infers them" {
    // The destination's tuple type fixes each element's type.
    try accepts(
        \\def main() -> int:
        \\    pair: tuple[int, str] = (1, "a")
        \\    number, text = pair
        \\    return number
        \\
    );
    // An inferred tuple interns the same identity as the spelling.
    try accepts(
        \\def shown(p: tuple[int, str]) -> str:
        \\    number, text = p
        \\    return text
        \\
        \\
        \\def main() -> int:
        \\    made = (1, "a")
        \\    return len(shown(made))
        \\
    );
    // A tuple arity that disagrees with its destination names both counts.
    const mismatch = try message(
        \\def main() -> int:
        \\    pair: tuple[int, str] = (1, "a", 2)
        \\    return 0
        \\
    );
    defer t.allocator.free(mismatch);
    try t.expect(std.mem.indexOf(u8, mismatch, "this tuple has 3 elements but tuple[int, str] has 2; write 2 elements") != null);
}

// spec: TUPLE-3
test "destructuring binds one name per element and rejects a wrong arity" {
    try accepts(
        \\def swap(a: int, b: int) -> int:
        \\    a, b = b, a
        \\    return a * 10 + b
        \\
        \\
        \\def main() -> int:
        \\    first, second = (1, 2)
        \\    first, second = second, first
        \\    return swap(first, second)
        \\
    );
    // The unused element is spelled `_` and binds nothing.
    try accepts(
        \\def main() -> int:
        \\    first, _ = (1, "a")
        \\    return first
        \\
    );
    // More names than values names the source and the count to bind.
    const too_many = try message(
        \\def pair() -> tuple[int, str]:
        \\    return 1, "a"
        \\
        \\
        \\def main() -> int:
        \\    first, second, third = pair()
        \\    return first
        \\
    );
    defer t.allocator.free(too_many);
    try t.expect(std.mem.indexOf(u8, too_many, "`pair` returns 2 values; bind 2 names, or `_` for one you do not need") != null);
    // A non-tuple right-hand side names the single-name alternative.
    const plain = try message(
        \\def main() -> int:
        \\    first, second = 7
        \\    return first
        \\
    );
    defer t.allocator.free(plain);
    try t.expect(std.mem.indexOf(u8, plain, "a destructuring assignment binds the values of a tuple; `int` is not one") != null);
}

// spec: TUPLE-4
test "a for loop destructures a two-element tuple element" {
    try accepts(
        \\def main() -> int:
        \\    pairs: list[tuple[int, str]] = [(1, "a"), (2, "b")]
        \\    total = 0
        \\    for number, letter in pairs:
        \\        total = total + number
        \\    return total
        \\
    );
    const wrong = try message(
        \\def main() -> int:
        \\    triples: list[tuple[int, str, int]] = [(1, "a", 2)]
        \\    for number, letter in triples:
        \\        return number
        \\    return 0
        \\
    );
    defer t.allocator.free(wrong);
    try t.expect(std.mem.indexOf(u8, wrong, "a two-name `for` destructures a two-value tuple; this one has 3 values") != null);
}

// spec: TUPLE-5
test "a tuple rejects indexing, fields, methods and len with the destructuring paste" {
    const indexed = try message(
        \\def main() -> int:
        \\    pair = (1, "a")
        \\    return pair[0]
        \\
    );
    defer t.allocator.free(indexed);
    try t.expect(std.mem.indexOf(u8, indexed, "a tuple has no elements to index; bind its values with `head, rest = ...`") != null);
    const field = try message(
        \\def main() -> int:
        \\    pair = (1, "a")
        \\    return pair.head
        \\
    );
    defer t.allocator.free(field);
    try t.expect(std.mem.indexOf(u8, field, "a tuple has no fields; take it apart with `head, rest = value`") != null);
    const method = try message(
        \\def main() -> int:
        \\    pair = (1, "a")
        \\    return pair.count()
        \\
    );
    defer t.allocator.free(method);
    try t.expect(std.mem.indexOf(u8, method, "a tuple has no methods; take it apart with `head, rest = value`") != null);
    const sized = try message(
        \\def main() -> int:
        \\    pair = (1, "a")
        \\    return len(pair)
        \\
    );
    defer t.allocator.free(sized);
    try t.expect(std.mem.indexOf(u8, sized, "a tuple has no length; take it apart with `head, rest = value`") != null);
}
