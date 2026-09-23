//! Abstract contracts are checked without sampling a concrete type or executing templates.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const bodies = @import("generic_bodies.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const pure =
    \\def identity[T](x: T) -> T:
    \\    return x
    \\
    \\
    \\def equal[T: equality](x: T, y: T) -> bool:
    \\    return x == y
    \\
    \\
    \\def arithmetic[T: integer](x: T, y: T) -> T noalloc:
    \\    value = x
    \\    value += y
    \\    while value < T(10):
    \\        value = value + T(1)
    \\    if value == y:
    \\        return -value
    \\    else:
    \\        return value
    \\
    \\
    \\def minimum[T](x: T) -> i8:
    \\    _ = x
    \\    return -128i8
    \\
    \\
    \\def main() -> i64:
    \\    return 0
;
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "generic.my", pure);
    defer compilation.deinit();
    try compilation.parse();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    try bodies.check(allocator, compilation.src, compilation.syntax.?, &sink);
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
    try compilation.check();
}
// spec: GENERIC-BODY-1
test "generic body contracts check pure control flow without concrete representative types" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "invalid.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
test "generic body contracts preserve original module source locations" {
    var compilation = try language.Compilation.init(t.allocator, "mapped.my", "");
    defer compilation.deinit();
    const allocator = compilation.arena.allocator();
    compilation.src = try source.Source.initMapped(allocator, &.{
        try source.Source.init(allocator, "main.my",
            \\def main() -> i64:
            \\    return 0
        ),
        try source.Source.init(allocator, "library.my",
            \\def bad[T](x: T, y: T) -> T:
            \\    return x + y
        ),
    });
    try t.expectError(error.SourceError, compilation.check());
    const failure = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_GENERIC_OPERATION", failure.code);
    try t.expectEqualStrings("library.my", compilation.src.locate(failure.span.start).path);
    try t.expectEqualStrings("+", compilation.src.text(failure.span));
}

fn checkBound(text: []const u8, failure: bool) !void {
    var compilation = try language.Compilation.init(t.allocator, "bounded.my", text);
    defer compilation.deinit();
    try compilation.parse();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    if (failure) {
        try t.expectError(error.SourceError, bodies.check(t.allocator, compilation.src, compilation.syntax.?, &sink));
        try t.expectEqualStrings("E_GENERIC_BODY_LIMIT", sink.items.items[0].code);
    } else try bodies.check(t.allocator, compilation.src, compilation.syntax.?, &sink);
}
test "generic body contracts bound left-deep expression checking" {
    for ([_]usize{ 100, 300 }) |length| {
        var text: std.Io.Writer.Allocating = .init(t.allocator);
        defer text.deinit();
        try text.writer.writeAll("def f[T: integer](x: T) -> T:\n    return x");
        for (0..length) |_| try text.writer.writeAll(" + x");
        try text.writer.writeByte('\n');
        try checkBound(text.written(), length == 300);
    }
}
test "generic body contracts reject top-level and type-parameter shadowing" {
    try reject(
        \\def f[T](x: T) -> T:
        \\    main = x
        \\    return main
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_SHADOWING");
    try reject(
        \\class T:
        \\    pass
        \\
        \\
        \\def f[T](x: T) -> T:
        \\    return x
    , "E_SHADOWING");
    try reject(
        \\def f[T](x: T) -> T:
        \\    T = x
        \\    return T
    , "E_SHADOWING");
}

test "generic body contracts reject undeclared operations mismatches and invalid control flow" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text =
        \\def f[T](x: T, y: T) -> T:
        \\    return x + y
        , .code = "E_GENERIC_OPERATION" },
        .{ .text =
        \\def f[T](x: T, y: T) -> bool:
        \\    return x == y
        , .code = "E_GENERIC_OPERATION" },
        .{ .text =
        \\def f[T: equality](x: T, y: T) -> bool:
        \\    return x < y
        , .code = "E_GENERIC_OPERATION" },
        .{ .text =
        \\def f[T: integer, U: integer](x: T, y: U) -> T:
        \\    return x + y
        , .code = "E_GENERIC_TYPE" },
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    return 1
        , .code = "E_GENERIC_TYPE" },
        .{ .text =
        \\def f[T: integer](x: T) -> T:
        \\    return x + 1
        , .code = "E_GENERIC_TYPE" },
        // Assignment binds, so a loop variable is the binding that stays immutable.
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    for i in range(0, 2):
        \\        i = 1
        \\    return x
        , .code = "E_IMMUTABLE" },
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    if True:
        \\        y = x
        \\    return y
        , .code = "E_UNKNOWN_NAME" },
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    x: T = x
        \\    return x
        , .code = "E_SHADOWING" },
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    if True:
        \\        return x
        , .code = "E_MISSING_RETURN" },
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    while True:
        \\        return x
        , .code = "E_MISSING_RETURN" },
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    return x
        \\    _ = x
        , .code = "E_UNREACHABLE" },
        .{ .text =
        \\def f[T](x: T) -> i8:
        \\    _ = x
        \\    return 128i8
        , .code = "E_INTEGER_RANGE" },
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    return other(x)
        , .code = "E_UNKNOWN_FUNCTION" },
    };
    for (cases) |case| try reject(case.text, case.code);
}

test "generic body contracts bound wide statement work without host execution" {
    for ([_]usize{ 49998, 49999 }) |length| {
        var text: std.Io.Writer.Allocating = .init(t.allocator);
        defer text.deinit();
        try text.writer.writeAll("def f[T](x: T) -> T:\n");
        for (0..length) |_| try text.writer.writeAll("    _ = x\n");
        try text.writer.writeAll("    pass\n    return x\n");
        try checkBound(text.written(), length == 49999);
    }
}

fn expectMessage(text: []const u8, code: []const u8, message: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "diagnostic.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const failure = compilation.diagnostics.items[0];
    try t.expectEqualStrings(code, failure.code);
    try t.expectEqualStrings(message, failure.message);
}

// spec: DIAG-ORACLE-1
test "DIAG-ORACLE-1 arity diagnostics report expected and given counts" {
    try expectMessage(
        \\def f(a: i64, b: i64) -> i64:
        \\    return a + b
        \\
        \\
        \\def main() -> i64:
        \\    return f(1)
    , "E_ARITY", "missing required argument: expected 2, given 1");
    try expectMessage(
        \\def f(a: i64, b: i64) -> i64:
        \\    return a + b
        \\
        \\
        \\def main() -> i64:
        \\    return f(1, 2, 3)
    , "E_ARITY", "too many arguments for this function: expected 2, given 3");
}

// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 unknown field diagnostics list declared fields" {
    try expectMessage(
        \\class Point:
        \\    y: i64
        \\    x: i64
        \\
        \\
        \\def main() -> i64:
        \\    p = Point(x=1, y=2)
        \\    return p.z
    , "E_UNKNOWN_FIELD", "field does not exist on this record type; declared fields: x, y");
}

// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 unknown variant diagnostics list declared variants" {
    try expectMessage(
        \\enum Flag:
        \\    yes,
        \\    no
        \\
        \\
        \\def f(x: Flag) -> i64:
        \\    if x == Flag.maybe:
        \\        return 1
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return f(Flag.yes)
    , "E_UNKNOWN_VARIANT", "variant is not declared on this type; declared variants: no, yes");
}

// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 unknown function diagnostics suggest close names" {
    try expectMessage(
        \\def twice(x: i64) -> i64:
        \\    return x + x
        \\
        \\
        \\def main() -> i64:
        \\    return twic(2)
    , "E_UNKNOWN_FUNCTION", "no function has this qualified name; did you mean `twice`?");
    try expectMessage(
        \\def abc() -> i64:
        \\    return 1
        \\
        \\
        \\def abd() -> i64:
        \\    return 2
        \\
        \\
        \\def abe() -> i64:
        \\    return 3
        \\
        \\
        \\def main() -> i64:
        \\    return abx()
    , "E_UNKNOWN_FUNCTION", "no function has this qualified name; did you mean one of: `abc`, `abd`, `abe`?");
}

// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 generic body unknown function diagnostics suggest close names" {
    try expectMessage(
        \\def twice[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\def call[T](x: T) -> T:
        \\    return twic(x)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_UNKNOWN_FUNCTION", "no function has this qualified name; did you mean `twice`?");
}

// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 type mismatch diagnostics use source type spellings" {
    try expectMessage(
        \\def f(x: i64) -> i64:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return f("hi")
    , "E_TYPE", "expected int, found str");
    try expectMessage(
        \\def f(xs: list[i64]) -> i64:
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return f("hi")
    , "E_TYPE", "expected list[int], found str");
    try expectMessage(
        \\def f(x: Option[i64]) -> i64:
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return f("hi")
    , "E_TYPE", "expected Option[int], found str");
    try expectMessage(
        \\def f(xs: list[list[i64]]) -> i64:
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return f("hi")
    , "E_TYPE", "expected list[list[int]], found str");
    try expectMessage(
        \\def f(xs: list[u8]) -> i64:
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return f("hi")
    , "E_TYPE", "expected list[u8], found str");
}
// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 surface type text uses source punctuation and spelling" {
    const qualified = try typed.surfaceTypeText(t.allocator, "widgets::Widget");
    defer t.allocator.free(qualified);
    try t.expectEqualStrings("widgets.Widget", qualified);
    const nested = try typed.surfaceTypeText(t.allocator, "List<List<i64>>");
    defer t.allocator.free(nested);
    try t.expectEqualStrings("list[list[int]]", nested);
    const user = try typed.surfaceTypeText(t.allocator, "MyList<i64>");
    defer t.allocator.free(user);
    try t.expectEqualStrings("MyList[int]", user);
    const callback = try typed.surfaceTypeText(t.allocator, "def(i64) -> i64 effects(managed_allocation)");
    defer t.allocator.free(callback);
    try t.expectEqualStrings("def(int) -> int effects(managed_allocation)", callback);
    const byte_scalar = try typed.surfaceTypeText(t.allocator, "u8");
    defer t.allocator.free(byte_scalar);
    try t.expectEqualStrings("u8", byte_scalar);
    const byte_list = try typed.surfaceTypeText(t.allocator, "list<u8>");
    defer t.allocator.free(byte_list);
    try t.expectEqualStrings("list[u8]", byte_list);
    const result = try typed.surfaceTypeText(t.allocator, "Result<i64,i64>");
    defer t.allocator.free(result);
    try t.expectEqualStrings("Result[int, int]", result);
    const dictionary = try typed.surfaceTypeText(t.allocator, "dict<str,list<i64>>");
    defer t.allocator.free(dictionary);
    try t.expectEqualStrings("dict[str, list[int]]", dictionary);
}
// spec-case: PY-VARIANT-4
test "a generic body constructs and destructures a parenthesized case with a default" {
    var compilation = try language.Compilation.init(t.allocator, "case_fields.my",
        \\union Slot[T]:
        \\    pair(left: T, right: T, label: str = "p"),
        \\    none
        \\
        \\
        \\def build[T](a: T, b: T) -> Slot[T]:
        \\    return Slot.pair(a, b)
        \\
        \\
        \\def sum(slot: Slot[i64]) -> i64:
        \\    match slot:
        \\        case Slot.none:
        \\            return 0
        \\        case Slot.pair(left, right, label):
        \\            return left + right + i64(len(label))
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

fn conditionalScenario(allocator: std.mem.Allocator) !void {
    const text =
        \\def pick[T](left: T, right: T, choose_left: bool) -> T:
        \\    return left if choose_left else right
        \\
        \\
        \\def main() -> i64:
        \\    return pick(1, 2, True)
    ;
    var compilation = try language.Compilation.init(allocator, "generic.my", text);
    defer compilation.deinit();
    try compilation.parse();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    try bodies.check(allocator, compilation.src, compilation.syntax.?, &sink);
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
    try compilation.check();
    try t.expectEqual(@as(i64, 1), (try @import("native_execute.zig").run(&compilation)).value);
}
// spec-case: CONDITIONAL-EXPR-4
test "a generic body checks a conditional expression symbolically" {
    try conditionalScenario(t.allocator);
}

fn sortingScenario(allocator: std.mem.Allocator) !void {
    const text =
        \\def ranked(keys: list[int]) -> list[int]:
        \\    words = [k for k in keys]
        \\    words.sort()
        \\    return words
        \\
        \\
        \\def smallest_key[T: copy + storable](values: list[T], key: def(T) -> int effects()) -> int:
        \\    names = ["b", "a"]
        \\    names.sort()
        \\    scores = [2.5, 0.5]
        \\    scores.sort()
        \\    return ranked([key(value) for value in values])[0] + len(names[0]) + int(scores[0] * 2.0)
        \\
        \\
        \\def negated(value: int) -> int effects():
        \\    return 0 - value
        \\
        \\
        \\def main() -> i64:
        \\    return smallest_key([3, 9, 4], negated) + 50
    ;
    var compilation = try language.Compilation.init(allocator, "generic_sort.my", text);
    defer compilation.deinit();
    try compilation.parse();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    try bodies.check(allocator, compilation.src, compilation.syntax.?, &sink);
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
    try compilation.check();
    try t.expectEqual(@as(i64, 43), (try @import("native_execute.zig").run(&compilation)).value);
}
// spec: GENERIC-BODY-3
test "a generic body and its helpers sort concrete lists and reject a symbolic element" {
    try sortingScenario(t.allocator);
    try reject(
        \\def ordered[T: copy + storable](values: list[T]) -> list[T]:
        \\    copy = values[:]
        \\    copy.sort()
        \\    return copy
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_COLLECTION_METHOD");
    try reject(
        \\def last[T: copy + storable](values: list[T]) -> int:
        \\    stack = [1, 2]
        \\    _ = stack.pop()
        \\    return len(values)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_GENERIC_BODY_UNSUPPORTED");
}
/// Check `text`, expect exactly one diagnostic, and compare its code and message.
fn rejectOnly(text: []const u8, code: []const u8, message: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "invalid.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqual(@as(usize, 1), compilation.diagnostics.items.len);
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
    try t.expectEqualStrings(message, compilation.diagnostics.items[0].message);
}
// spec: GENERIC-LAMBDA-1
test "a lambda inside a generic body is one located unsupported diagnostic naming the fix" {
    // A sort key: the case the keyed-sort audit found reported as an unknown name.
    try rejectOnly(
        \\def order[T: copy + storable](values: list[T]) -> list[T]:
        \\    return sorted(values, key=lambda value: 0)
        \\
        \\
        \\def main() -> i64:
        \\    return len(order([3, 1]))
    , "E_GENERIC_BODY_UNSUPPORTED", bodies.lambda_in_generic_body);
    // Any callback argument, even one whose type mentions no type parameter.
    try rejectOnly(
        \\def apply(f: def(int) -> int effects(), x: int) -> int:
        \\    return f(x)
        \\
        \\
        \\def count[T: copy + storable](values: list[T]) -> int:
        \\    return apply(lambda x: x + 1, len(values))
        \\
        \\
        \\def main() -> i64:
        \\    return count([3, 1])
    , "E_GENERIC_BODY_UNSUPPORTED", bodies.lambda_in_generic_body);
}
