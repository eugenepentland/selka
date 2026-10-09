//! Tuple diagnostics, identity and surface spelling: the four rejections the
//! plan fixes, the expected-type rule for literals, and the one identity every
//! equal element list interns to.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
/// Source name every fixture in this file is checked under.
const unit_name = "tuples.selka";

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
    // Nested element types keep the source spelling too.
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
    try t.expect(std.mem.indexOf(u8, nested, "expected tuple[list[int], str], found int") != null);
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
    try t.expect(std.mem.indexOf(u8, wrong, "a two-name `for` destructures a two-value tuple; this one has 3 values") != null);
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
    try t.expect(std.mem.indexOf(u8, indexed, "a tuple has no elements to index; bind its values with `head, rest = ...`") != null);
    const field = try message(
        \\func main() -> int:
        \\    mut pair = (1, "a")
        \\    return pair.head
        \\
    );
    defer t.allocator.free(field);
    try t.expect(std.mem.indexOf(u8, field, "a tuple has no fields; take it apart with `head, rest = value`") != null);
    const method = try message(
        \\func main() -> int:
        \\    mut pair = (1, "a")
        \\    return pair.count()
        \\
    );
    defer t.allocator.free(method);
    try t.expect(std.mem.indexOf(u8, method, "a tuple has no methods; take it apart with `head, rest = value`") != null);
    const sized = try message(
        \\func main() -> int:
        \\    mut pair = (1, "a")
        \\    return len(pair)
        \\
    );
    defer t.allocator.free(sized);
    try t.expect(std.mem.indexOf(u8, sized, "a tuple has no length; take it apart with `head, rest = value`") != null);
}

/// Execute one program natively and return everything it wrote to standard output.
fn output(text: []const u8) ![]const u8 {
    const native = @import("native_execute.zig");
    var compilation = try language.Compilation.init(t.allocator, unit_name, text);
    defer compilation.deinit();
    const outcome = native.run(&compilation) catch |err| {
        @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqualStrings("", outcome.trap.code);
    return outcome.stdout;
}

/// Execute one program natively and return its exit value.
fn value(text: []const u8) !i64 {
    const native = @import("native_execute.zig");
    var compilation = try language.Compilation.init(t.allocator, unit_name, text);
    defer compilation.deinit();
    const outcome = native.run(&compilation) catch |err| {
        @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqualStrings("", outcome.trap.code);
    return outcome.value;
}

// spec: TUPLE-6
test "a tuple prints as its bracketed elements and compares structurally" {
    try t.expectEqualStrings("(1, 'a')\n", try output(
        \\func main(out: Stream) -> int:
        \\    mut pair = (1, "a")
        \\    out.print(pair)
        \\    return 0
        \\
    ));
    // Nested tuples, and a tuple held in a list, keep the same element rules.
    try t.expectEqualStrings("(1, (2, 'b'))\n[(1, 'a'), (2, 'b')]\n", try output(
        \\func main(out: Stream) -> int:
        \\    mut nested = (1, (2, "b"))
        \\    mut pairs: tuple[int, str][] = [(1, "a"), (2, "b")]
        \\    out.print(nested)
        \\    out.print(pairs)
        \\    return 0
        \\
    ));
    // Equality is structural, including a text element compared by content.
    try t.expectEqual(@as(i64, 1), try value(
        \\func main() -> int:
        \\    const left, right = ((1, "a"), (1, "a"))
        \\    if left == right and left != (2, "a") and left != (1, "b"):
        \\        return 1
        \\    return 0
        \\
    ));
}

/// Check one module program through the project pipeline, which merges module
/// syntax before checking: a structural spelling lost in that merge would make
/// every tuple type in a module program unknown.
fn acceptsModule(source: []const u8) !void {
    const interfaces = @import("interfaces.zig");
    const project_compile = @import("project_compile.zig");
    const graph = @import("project.zig");
    const Files = struct {
        bytes: []const u8,
        fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) graph.ReadError![]u8 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (!std.mem.eql(u8, path, unit_name)) return error.NotFound;
            if (self.bytes.len > limit) return error.TooLarge;
            return allocator.dupe(u8, self.bytes);
        }
        fn provider(self: *@This()) graph.Provider {
            return .{ .context = self, .read = read };
        }
    };
    var files: Files = .{ .bytes = source };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "tuples", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile.Compilation.init(&index);
    try compilation.check();
}

// spec-case: TUPLE-1
test "a module program keeps its tuple type spellings" {
    try acceptsModule(
        \\
        \\
        \\record Holder:
        \\    pair: tuple[str, str]
        \\
        \\
        \\func split(text: str, sep: str) -> tuple[str, str]:
        \\    return text, sep
        \\
        \\
        \\func main() -> int:
        \\    const head, rest = split("key=value", "=")
        \\    mut holder = Holder(pair=(head, rest))
        \\    const first, second = holder.pair
        \\    return len(first) + len(second)
        \\
    );
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
    , "E_EXTERN_SIGNATURE");
}

// spec: TUPLE-8
test "a generic function takes, destructures and returns tuple[T, int]" {
    try accepts(
        \\func first_or[T](pair: tuple[T, int], fallback: T) -> T:
        \\    const value, count = pair
        \\    if count > 0:
        \\        return value
        \\    return fallback
        \\
        \\
        \\func main() -> int:
        \\    return first_or((7, 1), 0) + first_or(("a", 0), "b").find("a")
        \\
    );
    // The element that is a type parameter keeps its identity: an int for an
    // int tuple, a str for a str tuple, with no conversion between them.
    try t.expectEqual(@as(i64, 7), try value(
        \\func first_or[T](pair: tuple[T, int], fallback: T) -> T:
        \\    const value, count = pair
        \\    if count > 0:
        \\        return value
        \\    return fallback
        \\
        \\
        \\func main() -> int:
        \\    return first_or((7, 1), 0)
        \\
    ));
    try t.expectEqualStrings("b\n", try output(
        \\func first_or[T](pair: tuple[T, int], fallback: T) -> T:
        \\    const value, count = pair
        \\    if count > 0:
        \\        return value
        \\    return fallback
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    out.print(first_or(("a", 0), "b"))
        \\    return 0
        \\
    ));
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
