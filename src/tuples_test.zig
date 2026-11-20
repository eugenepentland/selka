//! Surface tuples are retired; legacy fixtures are preserved under L08/retired.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const fixture = @import("stdlib_fixture.zig");

fn removed(bytes: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "tuple-removed.selka", bytes);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    for (compilation.diagnostics.items) |item| {
        if (std.mem.eql(u8, item.code, "E_TUPLE_REMOVED")) return;
    }
    return error.TestExpectedError;
}
// spec-case: TUPLE-REMOVED-1
// spec-case: TUPLE-1
// spec-case: TUPLE-2
// spec-case: TUPLE-5
// spec-case: TUPLE-6
// spec-case: TUPLE-7
test "tuple surface types values parameters payloads and comparisons are removed" {
    // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
    try removed("func main() -> int:\n    const pair = (1, 2)\n    print(pair)\n    return 0\n");
    // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
    try removed("func take(pair: tuple[int, int]) -> int:\n    const x, y = pair\n    return x + y\nfunc main() -> int:\n    return take((1, 2))\n");
    // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
    try removed("record Holder:\n    value: tuple[int, int]\nfunc main() -> int:\n    const h = Holder(value=(1, 2))\n    return 0\n");
    // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
    try removed("func main() -> int:\n    const a = (1, 2)\n    const b = (1, 2)\n    if a == b:\n        return 1\n    return 0\n");
}
// spec-case: TUPLE-REMOVED-1
// spec-case: TUPLE-4
test "tuple retirement preserves two name enumerate zip and dictionary items loop forms" {
    const bytes =
        \\import dicts
        \\
        \\func main() -> int:
        \\    mut result = 0
        \\    for i, value in enumerate([1, 2]):
        \\        result = result + i + value
        \\    for a, b in zip([1, 2], [3, 4]):
        \\        result = result + a + b
        \\    const values = {1: 2}
        \\    for key, value in dicts.items(values):
        \\        result = result + key + value
        \\    return result
    ;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try fixture.accept(arena.allocator(), bytes);
}
// spec-case: TUPLE-REMOVED-1
// spec: TUPLE-8
test "tuple diagnostics retain source spans for manual generic tuple parameters" {
    var compilation = try language.Compilation.init(t.allocator, "tuple-generic.selka",
        // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
        \\func first[T](pair: tuple[T, int]) -> T:
        \\    const value, count = pair
        \\    return value
        \\func main() -> int:
        \\    return first((1, 2))
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    var found = false;
    for (compilation.diagnostics.items) |item| {
        if (!std.mem.eql(u8, item.code, "E_TUPLE_REMOVED")) continue;
        if (std.mem.eql(u8, compilation.src.text(item.span), "tuple[T, int]")) found = true;
    }
    try t.expect(found);
}

const unit_name = "tuples.selka";

// Historical diagnostic inputs remain executable and byte-for-byte intact.
/// Check one unit and require it to be accepted.
fn accepts(source: []const u8) !void {
    try removed(source);
}

/// Check one unit and require its first diagnostic to carry `code`.
fn rejects(source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, unit_name, source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    for (compilation.diagnostics.items) |item| if (std.mem.eql(u8, item.code, code)) return;
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

// spec-case: TUPLE-3
test "tuple copy bypasses collection element hints before managed unpacking" {
    try accepts(
        \\func unpack(pair: tuple[int[], str]) -> int:
        \\    const values, text = copy(pair)
        \\    return len(values) + len(text)
        \\func main() -> int:
        \\    const pair: tuple[int[], str] = ([1, 2], "value")
        \\    return unpack(pair)
    );
}

// spec-case: NEW-CORE-ZERO-RC-RESULT-LISTS-1
test "tuple copy preserves independent pending Result obligations" {
    try accepts(
        \\func main() -> int:
        \\    const pending: Result[str, str] = Ok("value")
        \\    const pair = (pending, 7)
        \\    const copied = copy(pair)
        \\    _ = pair
        \\    _ = copied
        \\    return 0
    );
    try rejects(
        \\func main() -> int:
        \\    const pending: Result[str, str] = Ok("value")
        \\    const pair = (pending, 7)
        \\    const copied = copy(pair)
        \\    _ = pair
        \\    return 0
    , "E_RESULT_UNHANDLED");
}

/// Check one unit and return an owned copy of its first diagnostic message.
fn message(source: []const u8) ![]u8 {
    var compilation = try language.Compilation.init(t.allocator, unit_name, source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    for (compilation.diagnostics.items) |item| {
        if (item.severity == .err and !std.mem.eql(u8, item.code, "E_TUPLE_REMOVED")) return t.allocator.dupe(u8, item.message);
    }
    return error.TestExpectedError;
}

// spec: TUPLE-1
test "a tuple type is one interned record with positional fields and a source spelling" {
    // The same element list written twice is one type: both parameters accept
    // each other's value with no conversion at all.
    try accepts(
        \\func pair_left(p: tuple[int, str]) -> str:
        \\    return "x"
        \\
        \\
        \\func pair_right(p: tuple[int, str]) -> str:
        \\    return pair_left(p)
        \\
        \\
        \\func main() -> int:
        \\    return 0
        \\
    );
    // A mismatched element list is the ordinary expected/found message, in the
    // source spelling of both types.
    const found = try message(
        \\func pair(p: tuple[int, str]) -> int:
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return pair(7)
        \\
    );
    defer t.allocator.free(found);
    try t.expect(std.mem.indexOf(u8, found, "expected tuple[int, str], found int") != null);
}

// spec-case: TUPLE-1
test "a tuple spelling outside two to eight elements is E_TUPLE_ARITY at the spelling" {
    try rejects(
        \\func f(p: tuple[int]) -> int:
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return 0
        \\
    , "E_TUPLE_ARITY");
    try rejects(
        \\func f(p: tuple[int, str, int, str, int, str, int, str, int]) -> int:
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return 0
        \\
    , "E_TUPLE_ARITY");
    // Nested element types keep the source spelling too: a list is `int[]` (FR25).
    const nested = try message(
        \\func f(p: tuple[int[], str]) -> int:
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return f(1)
        \\
    );
    defer t.allocator.free(nested);
    try t.expect(std.mem.indexOf(u8, nested, "expected tuple[int[], str], found int") != null);
}

// spec: TUPLE-2
test "a tuple value takes its element types from the destination or infers them" {
    // The destination's tuple type fixes each element's type.
    try accepts(
        \\func main() -> int:
        \\    mut pair: tuple[int, str] = (1, "a")
        \\    const number, text = pair
        \\    return number
        \\
    );
    // An inferred tuple interns the same identity as the spelling.
    try accepts(
        \\func shown(p: tuple[int, str]) -> str:
        \\    const number, text = p
        \\    return text
        \\
        \\
        \\func main() -> int:
        \\    mut made = (1, "a")
        \\    return len(shown(made))
        \\
    );
    // A tuple arity that disagrees with its destination names both counts.
    const mismatch = try message(
        \\func main() -> int:
        \\    mut pair: tuple[int, str] = (1, "a", 2)
        \\    return 0
        \\
    );
    defer t.allocator.free(mismatch);
    try t.expect(std.mem.indexOf(u8, mismatch, "this tuple has 3 elements but tuple[int, str] has 2; write 2 elements") != null);
}

// spec: TUPLE-3
test "destructuring binds one name per element and rejects a wrong arity" {
    try accepts(
        \\func swap(left: int, right: int) -> int:
        \\    mut a, b = (left, right)
        \\    a, b = (b, a)
        \\    return a * 10 + b
        \\
        \\
        \\func main() -> int:
        \\    mut first, second = (1, 2)
        \\    first, second = (second, first)
        \\    return swap(first, second)
        \\
    );
    // The unused element is spelled `_` and binds nothing.
    try accepts(
        \\func main() -> int:
        \\    const first, _ = (1, "a")
        \\    return first
        \\
    );
    // More names than values names the source and the count to bind.
    const too_many = try message(
        \\func pair() -> tuple[int, str]:
        \\    return 1, "a"
        \\
        \\
        \\func main() -> int:
        \\    const first, second, third = pair()
        \\    return first
        \\
    );
    defer t.allocator.free(too_many);
    try t.expect(std.mem.indexOf(u8, too_many, "`pair` returns 2 values; bind 2 names, or `_` for one you do not need") != null);
    // A non-tuple right-hand side names the single-name alternative.
    const plain = try message(
        \\func main() -> int:
        \\    const first, second = 7
        \\    return first
        \\
    );
    defer t.allocator.free(plain);
    try t.expect(std.mem.indexOf(u8, plain, "a destructuring assignment binds the values of a tuple; `int` is not one") != null);
}

// spec: TUPLE-4
test "a for loop destructures a two-element tuple element" {
    try accepts(
        \\func main() -> int:
        \\    mut pairs: tuple[int, str][] = [(1, "a"), (2, "b")]
        \\    mut total = 0
        \\    for number, letter in pairs:
        \\        total = total + number
        \\    return total
        \\
    );
    const wrong = try message(
        \\func main() -> int:
        \\    mut triples: tuple[int, str, int][] = [(1, "a", 2)]
        \\    for number, letter in triples:
        \\        return number
        \\    return 0
        \\
    );
    defer t.allocator.free(wrong);
    try t.expect(std.mem.indexOf(u8, wrong, "a two-name `for` takes `enumerate(values)`, `zip(left, right)` or `dicts.items(mapping)`, and this source gives values of 3 parts") != null);
}

// spec: TUPLE-5
test "a tuple rejects indexing, fields, methods and len with the destructuring paste" {
    const indexed = try message(
        \\func main() -> int:
        \\    mut pair = (1, "a")
        \\    return pair[0]
        \\
    );
    defer t.allocator.free(indexed);
    try t.expect(std.mem.indexOf(u8, indexed, "a tuple has no elements to index, and tuples were removed; use a record with named fields") != null);
    const field = try message(
        \\func main() -> int:
        \\    mut pair = (1, "a")
        \\    return pair.head
        \\
    );
    defer t.allocator.free(field);
    try t.expect(std.mem.indexOf(u8, field, "a tuple has no fields, and tuples were removed; use a record with named fields") != null);
    const method = try message(
        \\func main() -> int:
        \\    mut pair = (1, "a")
        \\    return pair.count()
        \\
    );
    defer t.allocator.free(method);
    try t.expect(std.mem.indexOf(u8, method, "a tuple has no methods, and tuples were removed; use a record with named fields") != null);
    const sized = try message(
        \\func main() -> int:
        \\    mut pair = (1, "a")
        \\    return len(pair)
        \\
    );
    defer t.allocator.free(sized);
    try t.expect(std.mem.indexOf(u8, sized, "a tuple has no length, and tuples were removed; use a record with named fields") != null);
}

// spec-case: TUPLE-5
test "the extern boundary rejects a tuple signature" {
    try rejects(
        \\extern func measure(host: Host, pair: tuple[int, str]) -> i64 effects(host)
        \\
        \\
        \\func main() -> int:
        \\    return 0
        \\
    , "E_EFFECTS_REMOVED");
}

// spec-case: TUPLE-8
test "a generic tuple requirement is its elements' requirement" {
    // A copyable element list satisfies a copy bound, and the destructured
    // parameter still returns its own parameter type.
    try accepts(
        \\func swap_pair[T: copy](pair: tuple[T, T]) -> tuple[T, T]:
        \\    const left, right = pair
        \\    return (right, left)
        \\
        \\
        \\func main() -> int:
        \\    const first, second = swap_pair((1, 2))
        \\    return first * 10 + second
        \\
    );
}

/// Check one unit and return its canonical formatted text.
fn formatted(source: []const u8) ![]u8 {
    var compilation = try language.Compilation.init(t.allocator, unit_name, source);
    defer compilation.deinit();
    return compilation.format(t.allocator);
}

// spec: TUPLE-7
test "the formatter returns a tuple value, type and target list unchanged" {
    const source = "func pair() -> tuple[int, str]:\n    return (1, \"a\")\n\n\n" ++
        "func main() -> int:\n    first, second = pair()\n    return first\n";
    const once = try formatted(source);
    defer t.allocator.free(once);
    const twice = try formatted(once);
    defer t.allocator.free(twice);
    try t.expectEqualStrings(once, twice);
    try t.expect(std.mem.indexOf(u8, once, "tuple[int, str]") != null);
    try t.expect(std.mem.indexOf(u8, once, "first, second = pair()") != null);
}

// spec-case: TUPLE-5
test "wave1 tuple extern boundary retains an effect-free modern rejection" {
    try rejects(
        \\extern func measure(host: Host, pair: tuple[int, str]) -> int
        \\func main() -> int:
        \\    return 0
    , "E_EXTERN_SIGNATURE");
}

/// The messages of every `E_TUPLE_REMOVED` diagnostic of one unit, each owned by the caller's allocator.
fn tupleMessages(allocator: std.mem.Allocator, source: []const u8) ![]const []const u8 {
    var compilation = try language.Compilation.init(allocator, unit_name, source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    var found: std.ArrayList([]const u8) = .empty;
    for (compilation.diagnostics.items) |item| {
        if (std.mem.eql(u8, item.code, "E_TUPLE_REMOVED")) try found.append(allocator, try allocator.dupe(u8, item.message));
    }
    return found.items;
}

/// Require every message of `texts` to be exactly `wanted` when `whole`, else to begin with it.
fn expectEvery(texts: []const []const u8, wanted: []const u8, whole: bool) !void {
    for (texts) |text| {
        if (whole) try t.expectEqualStrings(wanted, text) else try t.expect(std.mem.startsWith(u8, text, wanted));
    }
}

// spec-case: TUPLE-1
test "a tuple that is the only diagnostic and has no certain repair does not say it waits for other diagnostics" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
    const only = try tupleMessages(arena.allocator(),
        \\func first[T](pair: tuple[T, int]) -> T:
        \\    const value, count = pair
        \\    return value
        \\func main() -> int:
        \\    return first((1, 2))
    );
    try t.expect(only.len > 0);
    try expectEvery(only, "tuples were removed; use a named record", false);
    // With another error in the program the wait is real, and the message keeps saying so (it is what `fix` once matched).
    // migrate-embedded: skip intentional FIX-MIGRATION-1 pre-removal source
    const waiting = try tupleMessages(arena.allocator(),
        \\func pair() -> tuple[int, int]:
        \\    return (1, 2)
        \\func main() -> int:
        \\    const left, right = pair()
        \\    return left + missing
    );
    try t.expect(waiting.len > 0);
    try expectEvery(waiting, language.tuple_migration.deferred_message, true);
}
