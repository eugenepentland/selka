//! Abstract contracts are checked without sampling a concrete type or executing templates.
const invalid_path = "invalid.selka";
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const fixture = @import("stdlib_fixture.zig");
const bodies = @import("generic_bodies.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const pure =
    \\func identity[T](x: T) -> T:
    \\    return x
    \\
    \\
    \\func equal[T: equality](x: T, y: T) -> bool:
    \\    return x == y
    \\
    \\
    \\@noalloc
    \\func arithmetic[T: integer](x: T, y: T) -> T:
    \\    mut value = x
    \\    value += y
    \\    while value < T(10):
    \\        value = value + T(1)
    \\    if value == y:
    \\        return -value
    \\    else:
    \\        return value
    \\
    \\
    \\func minimum[T](x: T) -> i8:
    \\    _ = x
    \\    return -128i8
    \\
    \\
    \\func unconditional_loop[T](x: T) -> T:
    \\    while True:
    \\        return x
    \\
    \\
    \\func main() -> i64:
    \\    return 0
;
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "generic.selka", pure);
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
    var compilation = try language.Compilation.init(t.allocator, invalid_path, text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

test "O3 unused generic from sources use declaration eligibility" {
    try reject(
        \\func bad[T](value: T, count: int) -> T from count:
        \\    return value
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_SOURCE");
    try reject(
        \\func bad[T](own value: T) -> T from value:
        \\    return value
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_SOURCE");
    try reject(
        \\func bad[T](value: T) -> T from missing:
        \\    return value
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_SOURCE");
    try reject(
        \\func bad[T: integer](value: T) -> T from value:
        \\    return value
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_SOURCE");
    try reject(
        \\record Marker[T]:
        \\    count: int
        \\func bad[T](marker: Marker[T], value: T) -> T from marker:
        \\    return value
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_SOURCE");
}

test "generic body contracts preserve original module source locations" {
    var compilation = try language.Compilation.init(t.allocator, "mapped.selka", "");
    defer compilation.deinit();
    const allocator = compilation.arena.allocator();
    compilation.src = try source.Source.initMapped(allocator, &.{
        try source.Source.init(allocator, "main.selka",
            \\func main() -> i64:
            \\    return 0
        ),
        try source.Source.init(allocator, "library.selka",
            \\func bad[T](x: T, y: T) -> T:
            \\    return x + y
        ),
    });
    try t.expectError(error.SourceError, compilation.check());
    const failure = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_GENERIC_OPERATION", failure.code);
    try t.expectEqualStrings("library.selka", compilation.src.locate(failure.span.start).path);
    try t.expectEqualStrings("+", compilation.src.text(failure.span));
}

fn checkBound(text: []const u8, failure: bool) !void {
    var compilation = try language.Compilation.init(t.allocator, "bounded.selka", text);
    defer compilation.deinit();
    try compilation.parse();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    if (failure) {
        try t.expectError(error.SourceError, bodies.check(t.allocator, compilation.src, compilation.syntax.?, &sink));
        try t.expectEqualStrings("E_GENERIC_BODY_LIMIT", sink.items.items[0].code);
    } else try bodies.check(t.allocator, compilation.src, compilation.syntax.?, &sink);
}
/// Check a generic body of a left-deep chain of 100 and of 300 terms: the second is past the limit.
fn leftDeepChains() !void {
    for ([_]usize{ 100, 300 }) |length| {
        var text: std.Io.Writer.Allocating = .init(t.allocator);
        defer text.deinit();
        try text.writer.writeAll("func f[T: integer](x: T) -> T:\n    return x");
        for (0..length) |_| try text.writer.writeAll(" + x");
        try text.writer.writeByte('\n');
        try checkBound(text.written(), length == 300);
    }
}

test "generic body contracts bound left-deep expression checking" {
    // The check recurses three frames per term, and in a Debug build of an incremental test binary they overflowed 8 MiB before the
    // limit stopped them: it runs on the stack a command has, not the runner's.
    try @import("memory_budget").onCompilerStack(leftDeepChains, .{});
}
test "generic body contracts reject top-level and type-parameter shadowing" {
    try reject(
        \\func f[T](x: T) -> T:
        \\    mut main = x
        \\    return main
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_SHADOWING");
    try reject(
        \\record T:
        \\    pass
        \\
        \\
        \\func f[T](x: T) -> T:
        \\    return x
    , "E_SHADOWING");
    try reject(
        \\func f[T](x: T) -> T:
        \\    mut T = x
        \\    return T
    , "E_SHADOWING");
}

test "generic body contracts reject undeclared operations mismatches and invalid control flow" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text =
        \\func f[T](x: T, y: T) -> T:
        \\    return x + y
        , .code = "E_GENERIC_OPERATION" },
        .{ .text =
        \\func f[T](x: T, y: T) -> bool:
        \\    return x == y
        , .code = "E_GENERIC_OPERATION" },
        .{ .text =
        \\func f[T: equality](x: T, y: T) -> bool:
        \\    return x < y
        , .code = "E_GENERIC_OPERATION" },
        .{ .text =
        \\func f[T: integer, U: integer](x: T, y: U) -> T:
        \\    return x + y
        , .code = "E_GENERIC_TYPE" },
        .{ .text =
        \\func f[T](x: T) -> T:
        \\    return 1
        , .code = "E_GENERIC_TYPE" },
        .{ .text =
        \\func f[T: integer](x: T) -> T:
        \\    return x + 1
        , .code = "E_GENERIC_TYPE" },
        // A loop variable is assignable (PY-FOR-REBIND-1), so no loop case here.
        .{ .text =
        \\func f[T](x: T) -> T:
        \\    if True:
        \\        y = x
        \\    return y
        , .code = "E_BINDING_SCOPE_MIGRATION" },
        .{ .text =
        \\func f[T](x: T) -> T:
        \\    mut x: T = x
        \\    return x
        , .code = "E_SHADOWING" },
        .{ .text =
        \\func f[T](x: T, flag: bool) -> T:
        \\    if flag:
        \\        return x
        , .code = "E_MISSING_RETURN" },
        .{ .text =
        \\func f[T](x: T, flag: bool) -> T:
        \\    while flag:
        \\        return x
        , .code = "E_MISSING_RETURN" },
        .{ .text =
        \\func f[T](x: T) -> T:
        \\    return x
        \\    _ = x
        , .code = "E_UNREACHABLE" },
        .{ .text =
        \\func f[T](x: T) -> i8:
        \\    _ = x
        \\    return 128i8
        , .code = "E_INTEGER_RANGE" },
        .{ .text =
        \\func f[T](x: T) -> T:
        \\    return other(x)
        , .code = "E_UNKNOWN_FUNCTION" },
    };
    for (cases) |case| try reject(case.text, case.code);
}

test "generic body contracts bound wide statement work without host execution" {
    for ([_]usize{ 49998, 49999 }) |length| {
        var text: std.Io.Writer.Allocating = .init(t.allocator);
        defer text.deinit();
        try text.writer.writeAll("func f[T](x: T) -> T:\n");
        for (0..length) |_| try text.writer.writeAll("    _ = x\n");
        try text.writer.writeAll("    pass\n    return x\n");
        try checkBound(text.written(), length == 49999);
    }
}

fn expectMessage(text: []const u8, code: []const u8, message: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "diagnostic.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const failure = compilation.diagnostics.items[0];
    try t.expectEqualStrings(code, failure.code);
    try t.expectEqualStrings(message, failure.message);
}

/// Check `text`, a generic function nothing calls, and require its first diagnostic to be `E_UNREACHABLE` with `message`
/// and, when `removed` is given, a repair that deletes exactly that text.
fn expectGenericUnreachable(text: []const u8, message: []const u8, removed: ?[]const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "diagnostic.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const failure = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_UNREACHABLE", failure.code);
    try t.expectEqualStrings(message, failure.message);
    const edit = (failure.provenance.fix orelse return t.expect(removed == null)).edit;
    try t.expectEqualStrings(removed orelse "(no repair)", text[edit.span.start..edit.span.end]);
    try t.expectEqualStrings("", edit.text);
}

test "a generic body says why a trailing return cannot run and repairs only a trailing return or fail" {
    try expectGenericUnreachable(
        \\func f[T](x: T, flag: bool) -> T:
        \\    if flag:
        \\        return x
        \\    else:
        \\        return x
        \\    return x
        \\
    , "every branch of the `if` at line 2 returns, so this statement cannot run", "    return x\n");
    try expectGenericUnreachable(
        \\func f[T](x: T) -> T:
        \\    return x
        \\    return x
    , "statement follows an unconditional return", "    return x");
    try expectGenericUnreachable(
        \\func f[T](x: T) -> T:
        \\    return x
        \\    _ = x
        \\
    , "statement follows an unconditional return", null);
}

// spec: DIAG-ORACLE-1
test "DIAG-ORACLE-1 arity diagnostics report expected and given counts" {
    try expectMessage(
        \\func f(a: i64, b: i64) -> i64:
        \\    return a + b
        \\
        \\
        \\func main() -> i64:
        \\    return f(1)
    , "E_ARITY", "missing required argument: expected 2, given 1");
    try expectMessage(
        \\func f(a: i64, b: i64) -> i64:
        \\    return a + b
        \\
        \\
        \\func main() -> i64:
        \\    return f(1, 2, 3)
    , "E_ARITY", "too many arguments for this function: expected 2, given 3");
}

// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 unknown field diagnostics list declared fields" {
    try expectMessage(
        \\record Point:
        \\    y: i64
        \\    x: i64
        \\
        \\
        \\func main() -> i64:
        \\    mut p = Point(x=1, y=2)
        \\    return p.z
    , "E_UNKNOWN_FIELD", "field does not exist on this record type; declared fields: x, y");
}

// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 unknown variant diagnostics list declared variants" {
    try expectMessage(
        \\enum Flag:
        \\    yes
        \\    no
        \\
        \\
        \\func f(x: Flag) -> i64:
        \\    if x == Flag.maybe:
        \\        return 1
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return f(Flag.yes)
    , "E_UNKNOWN_VARIANT", "variant is not declared on this type; declared variants: no, yes");
}

// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 unknown function diagnostics suggest close names" {
    try expectMessage(
        \\func twice(x: i64) -> i64:
        \\    return x + x
        \\
        \\
        \\func main() -> i64:
        \\    return twic(2)
    , "E_UNKNOWN_FUNCTION", "no function has this qualified name; did you mean `twice`?");
    try expectMessage(
        \\func abc() -> i64:
        \\    return 1
        \\
        \\
        \\func abd() -> i64:
        \\    return 2
        \\
        \\
        \\func abe() -> i64:
        \\    return 3
        \\
        \\
        \\func main() -> i64:
        \\    return abx()
    , "E_UNKNOWN_FUNCTION", "no function has this qualified name; did you mean one of: `abc`, `abd`, `abe`?");
}

// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 generic body unknown function diagnostics suggest close names" {
    try expectMessage(
        \\func twice[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\func call[T](x: T) -> T:
        \\    return twic(x)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_UNKNOWN_FUNCTION", "no function has this qualified name; did you mean `twice`?");
}

// spec-case: DIAG-ORACLE-1
test "DIAG-ORACLE-1 type mismatch diagnostics use source type spellings" {
    try expectMessage(
        \\func f(x: i64) -> i64:
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return f("hi")
    , "E_TYPE", "expected int, found str");
    try expectMessage(
        \\func f(xs: i64[]) -> i64:
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return f("hi")
    , "E_TYPE", "expected int[], found str");
    try expectMessage(
        \\func f(x: i64?) -> i64:
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return f("hi")
    , "E_TYPE", "expected int?, found str");
    try expectMessage(
        \\func f(xs: i64[][]) -> i64:
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return f("hi")
    , "E_TYPE", "expected int[][], found str");
    try expectMessage(
        \\func f(xs: u8[]) -> i64:
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return f("hi")
    , "E_TYPE", "expected u8[], found str");
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
    const callback = try typed.surfaceTypeText(t.allocator, "func(i64) -> i64 effects(managed_allocation)");
    defer t.allocator.free(callback);
    try t.expectEqualStrings("func(int) -> int effects(managed_allocation)", callback);
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
    var compilation = try language.Compilation.init(t.allocator, "case_fields.selka",
        \\enum Slot[T]:
        \\    pair(left: T, right: T, label: str = "p")
        \\    none
        \\
        \\
        \\func build[T](a: T, b: T) -> Slot[T]:
        \\    return Slot.pair(left=a, right=b)
        \\
        \\
        \\func sum(slot: Slot[i64]) -> i64:
        \\    match slot:
        \\        case none:
        \\            return 0
        \\        case pair(left, right, label):
        \\            return left + right + i64(strings.char_count(label))
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

fn conditionalScenario(allocator: std.mem.Allocator) !void {
    const text =
        \\func pick[T](left: T, right: T, choose_left: bool) -> T:
        \\    if choose_left:
        \\        return left
        \\    else:
        \\        return right
        \\
        \\
        \\func main() -> i64:
        \\    return pick(1, 2, True)
    ;
    var compilation = try language.Compilation.init(allocator, "generic.selka", text);
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
        \\func ranked(keys: int[]) -> int[]:
        \\    mut words: int[] = []
        \\    for k in keys:
        \\        append(mut words, k)
        \\    sort(mut words)
        \\    return words
        \\
        \\
        \\func smallest_key[T: copy + storable](values: T[], key: func(T) -> int) -> int:
        \\    mut names = ["b", "a"]
        \\    sort(mut names)
        \\    mut scores = [2.5, 0.5]
        \\    sort(mut scores)
        \\    mut keyed_values: int[] = []
        \\    for value in values:
        \\        append(mut keyed_values, key(value))
        \\    return ranked(keyed_values)[0] + strings.char_count(names[0]) + int(scores[0] * 2.0)
        \\
        \\
        \\func negated(value: int) -> int:
        \\    return 0 - value
        \\
        \\
        \\func main() -> i64:
        \\    return smallest_key([3, 9, 4], negated) + 50
    ;
    var compilation = try language.Compilation.init(allocator, "generic_sort.selka", text);
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
        \\func ordered[T: copy + storable](values: T[]) -> T[]:
        \\    mut copy = values[:]
        \\    sort(mut copy)
        \\    return copy
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_COLLECTION_METHOD");
    const concrete_stack =
        \\import lists
        \\
        \\
        \\func last[T: copy + storable](values: T[]) -> int:
        \\    mut stack = [1, 2]
        \\    _ = lists.pop(mut stack)
        \\    return len(values)
        \\
        \\
        \\func main() -> i64:
        \\    return last([3, 4, 5])
    ;
    try t.expectEqual(@as(i64, 3), try fixture.value(t.allocator, concrete_stack));
}

// spec: GENERIC-BODY-1
test "a generic body reaches a list module home without the module function's requirements" {
    // `lists.remove` asks its module caller for `equality`, but the recognized home
    // checks the operation the retired method checked, so a template body that the
    // method spelling accepted keeps checking.
    try t.expectEqual(@as(i64, 6), try fixture.value(t.allocator,
        \\import lists
        \\
        \\
        \\func shrink[T: copy + storable](mut values: T[], item: T) -> int:
        \\    lists.remove(mut values, item)
        \\    return len(values)
        \\
        \\
        \\func main() -> int:
        \\    mut xs = [4, 5, 6]
        \\    return shrink(mut xs, 5) + xs[0]
    ));
    try t.expectEqual(@as(i64, 6), try fixture.value(t.allocator,
        \\import lists
        \\
        \\
        \\func drop_last[T: copy + storable](mut values: T[]) -> T:
        \\    return lists.pop(mut values)
        \\
        \\
        \\func main() -> int:
        \\    mut xs = [4, 5]
        \\    return drop_last(mut xs) + len(xs)
    ));
    // The marker is the template's business too: an unmarked receiver would write
    // the caller's list without saying so.
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try fixture.rejectsWith(arena.allocator(),
        \\import lists
        \\
        \\
        \\func drop_last[T: copy + storable](mut values: T[]) -> T:
        \\    return lists.pop(values)
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , "E_MUTATION_MARKER");
}
/// Check `text`, expect exactly one diagnostic, and compare its code and message.
fn rejectOnly(text: []const u8, code: []const u8, message: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, invalid_path, text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqual(@as(usize, 1), compilation.diagnostics.items.len);
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
    try t.expectEqualStrings(message, compilation.diagnostics.items[0].message);
}
fn rejectLocatedLambda(text: []const u8, expected_span: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, invalid_path, text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqual(@as(usize, 1), compilation.diagnostics.items.len);
    const item = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_LAMBDA_REMOVED", item.code);
    try t.expectEqualStrings(bodies.lambda_in_generic_body, item.message);
    try t.expectEqualStrings(expected_span, compilation.src.text(item.span));
}
// spec: GENERIC-LAMBDA-1
test "a lambda inside a generic body is one located unsupported diagnostic naming the fix" {
    // A sort key: the case the keyed-sort audit found reported as an unknown name.
    try rejectLocatedLambda(
        // migrate-embedded: skip intentional generic-lambda retirement and located diagnostic
        \\func order[T: copy + storable](values: T[]) -> T[]:
        \\    return sorted(values, key=lambda value: 0)
        \\
        \\
        \\func main() -> i64:
        \\    return len(order([3, 1]))
    , "lambda value: 0");
    // Any callback argument, even one whose type mentions no type parameter.
    try rejectOnly(
        // migrate-embedded: skip intentional original callback effect-clause diagnostic
        \\func apply(f: func(int) -> int effects(), x: int) -> int:
        \\    return f(x)
        \\
        \\
        \\func count[T: copy + storable](values: T[]) -> int:
        \\    return apply(lambda x: x + 1, len(values))
        \\
        \\
        \\func main() -> i64:
        \\    return count([3, 1])
    , "E_EFFECTS_REMOVED", "source effect clauses were removed; capability parameters declare authority");
    try rejectLocatedLambda(
        // migrate-embedded: skip intentional generic-lambda retirement and located diagnostic
        \\func apply(f: func(int) -> int, x: int) -> int:
        \\    return f(x)
        \\
        \\
        \\func count[T: copy + storable](values: T[]) -> int:
        \\    return apply(lambda x: x + 1, len(values))
        \\
        \\
        \\func main() -> i64:
        \\    return count([3, 1])
    , "lambda x: x + 1");
}

test "a generic body reaches the dictionary homes and checks pop, setdefault and update by their dictionary signatures" {
    // The dictionary's `pop` is one spelling whose argument count selects the
    // keyed or defaulted operation, so a template body resolves it the same way.
    try t.expectEqual(@as(i64, 9), try fixture.value(t.allocator,
        \\import dicts
        \\
        \\
        \\func fetch[K: copy + equality + storable, V: copy + storable](mut mapping: dict[K, V], key: K, fallback: V) -> V:
        \\    _ = dicts.setdefault(mut mapping, copy(key), copy(fallback))
        \\    return dicts.pop(mut mapping, key)
        \\
        \\
        \\func main() -> int:
        \\    mut counts: dict[str, int] = {"a": 4}
        \\    dicts.update(mut counts, {"b": 5})
        \\    mut total = fetch(mut counts, "c", 3)
        \\    total += fetch(mut counts, "b", 9)
        \\    return total + len(counts)
    ));
}

test "generic bodies read str and bytes octets as int and skip literal text in f-strings" {
    var compilation = try language.Compilation.init(t.allocator, invalid_path,
        \\func octet[S: copy](value: S, text: str, data: bytes) -> int:
        \\    _ = value
        \\    mut total = 0
        \\    for i in range(len(text)):
        \\        if text[i] == 97:
        \\            total += 1
        \\    if data[0] == 71:
        \\        total += 10
        \\    return total + text[0] + data[1]
        \\
        \\
        \\func piece[S: copy](value: S, code: int) -> str:
        \\    _ = value
        \\    return f"\\u{code:04x}"
        \\
        \\
        \\func main() -> int:
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.check();
}

test "O4 generic own transfers pending Result lists without adding symbolic move checks" {
    var compilation = try language.Compilation.init(t.allocator, "generic-own-result.selka",
        \\func transferred[T](own values: Result[T, int][]) -> Result[T, int][]:
        \\    mut kept = own values
        \\    return kept
        \\func contextual[T](value: T) -> T?:
        \\    mut kept: T? = own Some(value)
        \\    return kept
        \\func main() -> int:
        \\    return 0
    );
    defer compilation.deinit();
    // Neither template is instantiated: preflight checks types, B1 and L1.
    // Core would judge the fresh constructor's misplaced marker at an instance.
    try compilation.check();
    try t.expectEqual(@as(usize, 1), compilation.program.?.functions.len);
}

test "O4 generic own still refuses reuse of a transferred Result obligation" {
    try reject(
        \\func duplicated[T](own values: Result[T, int][]) -> Result[T, int][]:
        \\    mut kept = own values
        \\    _ = values
        \\    return kept
        \\func main() -> int:
        \\    return 0
    , "E_RESULT_CONSUMED");
}

test "O4 symbolic type dependence follows fields inferred calls payloads iteration and aliases" {
    const text =
        \\record Holder[T]:
        \\    value: T
        \\    count: int
        \\func make[T: copy + storable](value: T) -> Holder[T]:
        \\    return Holder[T](value=copy(value), count=0)
        \\func facts[T: copy + storable](own value: T, holder: Holder[T], values: T[], optional: T??) -> int:
        \\    const made = make[T](copy(value))
        \\    const alias = holder.value
        \\    _ = own made.value
        \\    _ = own alias
        \\    _ = own holder.value
        \\    _ = own holder.count
        \\    match optional:
        \\        case Some(Some(payload)):
        \\            _ = own payload
        \\        case Some(None):
        \\            pass
        \\        case None:
        \\            pass
        \\    for element in values:
        \\        _ = own element
        \\    return 0
        \\func main() -> int:
        \\    return 0
    ;
    var compilation = try language.Compilation.init(t.allocator, "type-dependence.selka", text);
    defer compilation.deinit();
    try compilation.parse();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    const catalog = try @import("records.zig").collectWithNames(sink.allocator, compilation.src, compilation.syntax.?, &sink, null);
    var facts: bodies.TypeDependence = .empty;
    defer facts.deinit(t.allocator);
    try bodies.checkWithCatalogCached(t.allocator, compilation.src, compilation.syntax.?, &sink, catalog, .{ .type_dependence = &facts });
    const dependent = [_][]const u8{ "own made.value", "own alias", "own holder.value", "own payload", "own element" };
    for (dependent) |expression| {
        const start = std.mem.indexOf(u8, text, expression).?;
        try t.expect(facts.contains(.{ .start = start, .end = start + expression.len }));
    }
    const independent = "own holder.count";
    const start = std.mem.indexOf(u8, text, independent).?;
    try t.expect(!facts.contains(.{ .start = start, .end = start + independent.len }));
}

// Lane FX item 3: `debug(...)` in a template body was refused `E_UNKNOWN_FUNCTION` ("no function has this qualified
// name"), since the template checker knew no `debug`; a plain function accepts it, keywords included.
test "FX debug in a generic body checks as in a plain function, with sep= and end=, and an instance checks what it renders" {
    var compilation = try language.Compilation.init(t.allocator, "generic_debug.selka",
        \\func show[T: copy](value: T, label: str) -> T:
        \\    debug(value)
        \\    debug(label, value, sep=": ", end="!\n")
        \\    return copy(value)
        \\
        \\
        \\func main() -> i64:
        \\    return show(40, "n") + i64(len(show("ab", "s")))
    );
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
    // `sep=` takes a text, as in a plain function; the template checker names its mismatch.
    try reject(
        \\func show[T: copy](value: T) -> int:
        \\    debug(value, sep=3)
        \\    return 1
        \\
        \\
        \\func main() -> i64:
        \\    return show(4)
    , "E_GENERIC_TYPE");
    // A keyword other than `sep=` and `end=` is refused, as by `print`.
    try reject(
        \\func show[T: copy](value: T) -> int:
        \\    debug(value, end="", other="x")
        \\    return 1
        \\
        \\
        \\func main() -> i64:
        \\    return show(4)
    , "E_IO_ARGUMENT");
}

/// FR82: the source text of a generic function whose `match failure:` sits in an `else Err(failure):` block, with `arms`.
fn fr82Source(comptime arms: []const u8) []const u8 {
    return
    \\enum Fault:
    \\    busy
    \\    bad(code: int)
    \\
    \\
    \\func rank[T](result: Result[T, Fault]) -> int:
    \\    const value = result else Err(failure):
    \\        match failure:
    \\
    ++ arms ++
        \\
        \\    _ = value
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
}

test "FR82: a generic body's case _ is the wildcard arm and a case the type does not declare stays refused" {
    var compilation = try language.Compilation.init(t.allocator, "wildcard.selka", fr82Source(
        \\            case bad(code=c):
        \\                return c
        \\            case _:
        \\                return -1
    ));
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
    try expectMessage(fr82Source(
        \\            case nosuch:
        \\                return -3
        \\            case _:
        \\                return -1
    ), "E_UNKNOWN_VARIANT", "case is not a variant of the matched type");
    try expectMessage(fr82Source(
        \\            case _:
        \\                return -1
        \\            case busy:
        \\                return -2
    ), "E_WILDCARD_ARM", "`case _` must be the last arm of a match");
    try expectMessage(fr82Source(
        \\            case busy:
        \\                return -2
        \\            case bad(code=c):
        \\                return c
        \\            case _:
        \\                return -1
    ), "E_WILDCARD_ARM", "every variant already has an arm, so `case _` is unreachable");
}

test "FR87: a generic signature's or local's bare byte_buffer resolves as a plain signature's does, and an unknown name stays refused" {
    // Until FR87 the template check resolved a bare `byte_buffer` through a catalog that holds the lazily materialized
    // buffer only when something else had named it, so each signature and the local here was E_UNKNOWN_TYPE.
    var compilation = try language.Compilation.init(t.allocator, "buffer.selka",
        \\func fresh() -> byte_buffer:
        \\    return byte_buffer([1, 2])
        \\
        \\
        \\func note[K](mut out: byte_buffer, key: K) -> int:
        \\    _ = key
        \\    return len(out)
        \\
        \\
        \\func make[K](key: K) -> byte_buffer:
        \\    _ = key
        \\    return fresh()
        \\
        \\
        \\func held[K](key: K) -> int:
        \\    _ = key
        \\    const local: byte_buffer = fresh()
        \\    return len(local)
        \\
        \\
        \\func main() -> i64:
        \\    mut data = make(1)
        \\    return note(mut data, "k") + held(2)
    );
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
    try expectMessage(
        \\func note[K](mut out: byte_bufer, key: K) -> int:
        \\    _ = key
        \\    return len(out)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_UNKNOWN_TYPE", "type is not declared");
}
