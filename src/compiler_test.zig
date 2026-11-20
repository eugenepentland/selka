//! Semantic fixtures exercise public pipeline behavior and allocation ownership.
const std = @import("std");
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const testing = std.testing;

fn result(expression: []const u8, expected: i64) !void {
    const text = try std.fmt.allocPrint(testing.allocator, "func main() -> i64:\n    return {s}\n", .{expression});
    defer testing.allocator.free(text);
    var compilation = try language.Compilation.init(testing.allocator, "test.selka", text);
    defer compilation.deinit();
    const outcome = try native.run(&compilation);
    try testing.expectEqual(expected, outcome.value);
}

// spec: CORE-2
test "overflow traps at the responsible operator without folding during check" {
    // The reported column is the one-based offset of the responsible operator,
    // which sits at `len("    return ")` plus its index inside the expression.
    const cases = [_]struct { expression: []const u8, column: u64 }{
        .{ .expression = "9223372036854775807 + 1", .column = 32 },
        .{ .expression = "3037000500 * 3037000500", .column = 23 },
        .{ .expression = "(0 - 9223372036854775807) - 2", .column = 38 },
    };
    for (cases) |case| {
        const text = try std.fmt.allocPrint(testing.allocator, "func main() -> i64:\n    return {s}\n", .{case.expression});
        defer testing.allocator.free(text);
        var compilation = try language.Compilation.init(testing.allocator, "trap.selka", text);
        defer compilation.deinit();
        try compilation.check();
        const outcome = try native.run(&compilation);
        try testing.expectEqualStrings("R_OVERFLOW", outcome.trap.code);
        try testing.expectEqual(@as(u64, 2), outcome.trap.line);
        try testing.expectEqual(case.column, outcome.trap.column);
    }
}

// spec: CORE-3
test "malformed source and range errors are normal located diagnostics" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text = "", .code = "E_MAIN" },
        .{ .text = "func main() -> i64:\n    return 1 + \n", .code = "E_EXPRESSION" },
        .{ .text = "func main() -> i64:\n    x = 41 return x + 1\n", .code = "E_SYNTAX" },
        .{ .text =
        \\func main() -> i64:
        \\    return 9223372036854775808
        , .code = "E_INTEGER_RANGE" },
        .{ .text =
        \\func main() -> i64:
        \\    return 999999999999999999999999999999999999999
        , .code = "E_INTEGER_RANGE" },
        .{ .text =
        \\func helper() -> i64:
        \\    return 1
        , .code = "E_MAIN" },
        .{ .text =
        \\func main() -> bool:
        \\    return 1
        , .code = "E_TYPE" },
        .{ .text = "func main() -> i64:\n    return $\n", .code = "E_TOKEN" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(testing.allocator, "bad.selka", case.text);
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expect(compilation.program == null);
        try testing.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
        try testing.expect(compilation.diagnostics.items[0].span.end <= case.text.len);
    }
}

// spec-case: CHECK-LIBRARY-2
test "a unit without main checks as a library and retains no executable program" {
    var library = try language.Compilation.init(testing.allocator, "lib.selka", "public func add(a: int, b: int) -> int:\n    return a + b\n\nfunc mainly() -> int:\n    return 1\n");
    defer library.deinit();
    try library.parse();
    try testing.expect(!library.declaresMain());
    try library.checkLibrary();
    try testing.expect(library.program == null and library.diagnostics.items.len == 0);

    var broken = try language.Compilation.init(testing.allocator, "broken.selka", "public func value() -> int:\n    return False\n");
    defer broken.deinit();
    try broken.parse();
    try testing.expectError(error.SourceError, broken.checkLibrary());
    try testing.expectEqualStrings("E_TYPE", broken.diagnostics.items[0].code);

    var entry = try language.Compilation.init(testing.allocator, "entry.selka", "func main(count: int) -> int:\n    return count\n");
    defer entry.deinit();
    try entry.parse();
    try testing.expect(entry.declaresMain());
    try testing.expectError(error.SourceError, entry.check());
    try testing.expectEqualStrings("E_MAIN", entry.diagnostics.items[0].code);
}

test "source is owned and CRLF diagnostics locate operators and EOF" {
    const bytes = try testing.allocator.dupe(u8, "# comment\r\nfunc main() -> i64:\r\n    return 9223372036854775807 + 1\r\n");
    var compilation = try language.Compilation.init(testing.allocator, "crlf.selka", bytes);
    testing.allocator.free(bytes);
    defer compilation.deinit();
    const outcome = try native.run(&compilation);
    try testing.expectEqual(@as(u64, 3), outcome.trap.line);
    try testing.expectEqual(@as(u64, 32), outcome.trap.column);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "crlf.selka:3:32: error[R_OVERFLOW]") != null);
    try testing.expect(std.mem.indexOfScalar(u8, outcome.stderr, '\r') == null);
    try testing.expectEqual(@as(usize, 4), compilation.src.locate(compilation.src.bytes.len).line);
}

test "parser rejects excessive nesting without a host stack overflow" {
    var text: std.Io.Writer.Allocating = .init(testing.allocator);
    defer text.deinit();
    try text.writer.writeAll("func main() -> i64:\n    return ");
    try text.writer.splatByteAll('(', 300);
    try text.writer.writeByte('1');
    try text.writer.splatByteAll(')', 300);
    try text.writer.writeAll("\n");
    var compilation = try language.Compilation.init(testing.allocator, "deep.selka", text.written());
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings("E_NESTING_LIMIT", compilation.diagnostics.items[0].code);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "test.selka",
        \\func main() -> i64:
        \\    return (1 + 2) * 3
    );
    defer compilation.deinit();
    try compilation.check();
    try testing.expect(compilation.program != null);
}

test "request allocation failures release all owned storage" {
    try testing.checkAllAllocationFailures(testing.allocator, allocationScenario, .{});
}

fn programResult(text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(testing.allocator, "program.selka", text);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try native.run(&compilation)).value);
}

test "unary arithmetic and directly negated minimum literal" {
    try result("-3 * 2 + 10", 4);
    try result("--8", 8);
    try result("-9223372036854775808", std.math.minInt(i64));
    try result("-((9223372036854775808))", std.math.minInt(i64));
    try result("-9_223_372_036_854_775_808", std.math.minInt(i64));
    var compilation = try language.Compilation.init(testing.allocator, "neg.selka",
        \\func main() -> i64:
        \\    return --9223372036854775808
    );
    defer compilation.deinit();
    const outcome = try native.run(&compilation);
    try testing.expectEqualStrings("R_OVERFLOW", outcome.trap.code);
    try testing.expectEqual(@as(u64, 2), outcome.trap.line);
    try testing.expectEqual(@as(u64, 12), outcome.trap.column);
}

test "scope types immutability and structural return diagnostics" {
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body = "const main = 1\n    return main", .code = "E_SHADOWING" },
        .{ .body = "const x = x\n    return x", .code = "E_UNKNOWN_NAME" },
        .{ .body = "const x: bool = 1\n    return 0", .code = "E_TYPE" },
        .{ .body = "mut x = True\n    x = 1\n    return 0", .code = "E_TYPE" },
        .{ .body = "return True + 1", .code = "E_TYPE" },
        .{ .body = "const b = True < False\n    return 0", .code = "E_TYPE" },
        .{ .body = "const b = True == 1\n    return 0", .code = "E_TYPE" },
        .{ .body = "return not 1", .code = "E_TYPE" },
        .{ .body = "return -True", .code = "E_TYPE" },
        .{ .body = "return True", .code = "E_TYPE" },
        .{ .body = "const x = 1", .code = "E_MISSING_RETURN" },
        .{ .body = "return 1\n    return 2", .code = "E_UNREACHABLE" },
        .{ .body = "return -(9223372036854775808 + 0)", .code = "E_INTEGER_RANGE" },
        .{ .body = "return -9223372036854775809", .code = "E_INTEGER_RANGE" },
        .{ .body = "bool = 1\n    return 0", .code = "E_EXPRESSION" },
    };
    for (cases) |case| {
        const text = try std.fmt.allocPrint(testing.allocator,
            \\func main() -> i64:
            \\    {s}
        , .{case.body});
        defer testing.allocator.free(text);
        var compilation = try language.Compilation.init(testing.allocator, "bad.selka", text);
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

/// Check `text`, which must be refused first with `E_UNREACHABLE` and `message`; its repair must delete exactly the
/// text `removed`, or the refusal carries no repair when `removed` is null.
fn expectUnreachable(text: []const u8, message: []const u8, removed: ?[]const u8) !void {
    const program = try std.mem.concat(testing.allocator, u8, &.{ text, "\n\nfunc main() -> int:\n    return 0\n" });
    defer testing.allocator.free(program);
    var compilation = try language.Compilation.init(testing.allocator, "bad.selka", program);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    const first = compilation.diagnostics.items[0];
    try testing.expectEqualStrings("E_UNREACHABLE", first.code);
    try testing.expectEqualStrings(message, first.message);
    const fix = first.provenance.fix orelse return testing.expect(removed == null);
    try testing.expectEqual(@as(usize, 1), fix.count());
    try testing.expectEqualStrings("", fix.edit.text);
    try testing.expectEqualStrings(removed orelse "(no repair)", program[fix.edit.span.start..fix.edit.span.end]);
}

test "E_UNREACHABLE says why the earlier statement leaves, and repairs only a trailing return or fail" {
    const plain = "statement follows a structurally terminating statement";
    const cases = [_]struct { text: []const u8, message: []const u8, removed: ?[]const u8 }{
        // After a `match` whose every arm returns: the message names it, and the trailing `return` is deleted.
        .{ .text =
        \\enum Shape:
        \\    circle(r: int)
        \\    square(s: int)
        \\
        \\
        \\func f(s: Shape) -> int:
        \\    match s:
        \\        case circle(r=r):
        \\            return r
        \\        case square(s=side):
        \\            return side
        \\    return 0
        \\
        , .message = "every arm of the `match` at line 7 returns, so this statement cannot run", .removed = "    return 0\n" },
        // After an `if`/`else` chain, with a comment on the deleted line.
        .{ .text =
        \\func f(n: int) -> int:
        \\    if n > 0:
        \\        return 1
        \\    elif n < 0:
        \\        return 2
        \\    else:
        \\        return 3
        \\    # not a fallback
        \\    return 4  # never
        \\
        , .message = "every branch of the `if` at line 2 returns, so this statement cannot run", .removed = "    return 4  # never\n" },
        // In a nested block.
        .{ .text =
        \\func f(n: int) -> int:
        \\    if n > 5:
        \\        if n > 9:
        \\            return 1
        \\        else:
        \\            return 2
        \\        return 3
        \\    return 0
        , .message = "every branch of the `if` at line 3 returns, so this statement cannot run", .removed = "        return 3\n" },
        // In a loop body, with a value that spans lines.
        .{ .text =
        \\func pick(a: int, b: int) -> int:
        \\    return a
        \\
        \\
        \\func f(items: int[]) -> int:
        \\    for item in items:
        \\        match item:
        \\            case 0:
        \\                return 0
        \\            case _:
        \\                return 1
        \\        return pick(
        \\            item,
        \\            3,
        \\        )
        \\    return 5
        \\
        , .message = "every arm of the `match` at line 7 returns, so this statement cannot run", .removed = "        return pick(\n            item,\n            3,\n        )\n" },
        // A trailing `fail` after branches that leave in different ways.
        .{ .text =
        \\func f(n: int) -> int fails str:
        \\    if n > 0:
        \\        return 1
        \\    else:
        \\        fail "no"
        \\    fail "again"
        \\
        , .message = "every branch of the `if` at line 2 leaves, so this statement cannot run", .removed = "    fail \"again\"\n" },
        // After branches that all fail.
        .{ .text =
        \\func f(n: int) -> int fails str:
        \\    if n > 0:
        \\        fail "a"
        \\    else:
        \\        fail "b"
        \\    return 0
        \\
        , .message = "every branch of the `if` at line 2 fails, so this statement cannot run", .removed = "    return 0\n" },
        // A bare `return` after branches that all return.
        .{ .text =
        \\func f(n: int):
        \\    if n > 0:
        \\        return
        \\    else:
        \\        return
        \\    return
        \\
        , .message = "every branch of the `if` at line 2 returns, so this statement cannot run", .removed = "    return\n" },
        // A plain `return` followed by a `return` keeps today's wording and is repaired.
        .{ .text =
        \\func f(n: int) -> int:
        \\    return n
        \\    return 2
        \\
        , .message = plain, .removed = "    return 2\n" },
        // A `return` after a `break`.
        .{ .text =
        \\func f(items: int[]) -> int:
        \\    for item in items:
        \\        if item > 3:
        \\            break
        \\            return 7
        \\    return 0
        \\
        , .message = plain, .removed = "            return 7\n" },
        // Two statements after a `return`: the author may have meant the early exit to go.
        .{ .text =
        \\func f(n: int) -> int:
        \\    return n
        \\    const x = 1
        \\    return x
        \\
        , .message = plain, .removed = null },
        // A call after a `return`, and an assignment after a `break`.
        .{ .text =
        \\func f(n: int) -> int:
        \\    return n
        \\    f(n)
        \\
        , .message = plain, .removed = null },
        .{ .text =
        \\func f(items: int[]) -> int:
        \\    mut total = 0
        \\    for item in items:
        \\        if item > 3:
        \\            break
        \\            total += 1
        \\        total += item
        \\    return total
        \\
        , .message = plain, .removed = null },
        // A statement after a `match` that is not a `return` or a `fail` keeps the explanation and has no repair.
        .{ .text =
        \\func f(n: int) -> int:
        \\    match n:
        \\        case 0:
        \\            return 1
        \\        case _:
        \\            return 2
        \\    mut total = 0
        \\    total += 1
        \\    return total
        \\
        , .message = "every arm of the `match` at line 2 returns, so this statement cannot run", .removed = null },
    };
    for (cases) |case| try expectUnreachable(case.text, case.message, case.removed);
}

test "binding warnings distinguish writes from reads across function-scoped blocks" {
    const text =
        \\func main() -> i64:
        \\    mut unused = 1
        \\    mut write_only = 2
        \\    write_only = 3
        \\    if True:
        \\        mut branch_only = 4
        \\    if True:
        \\        mut used = 5
        \\        return used
        \\    return 0
    ;
    var compilation = try language.Compilation.init(testing.allocator, "warnings.selka", text);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 5), (try native.run(&compilation)).value);
    const warnings = compilation.diagnostics.items;
    try testing.expectEqual(@as(usize, 3), warnings.len);
    try testing.expectEqualStrings("W_UNUSED_BINDING", warnings[0].code);
    try testing.expectEqualStrings("W_UNUSED_BINDING", warnings[1].code);
    try testing.expectEqualStrings("unused", compilation.src.text(warnings[0].span));
    try testing.expectEqualStrings("write_only", compilation.src.text(warnings[1].span));
    // A binding assigned only inside a branch and never read still warns, and its
    // span points at the assignment that introduced it.
    try testing.expectEqualStrings("branch_only", compilation.src.text(warnings[2].span));
    try testing.expectEqual(std.mem.indexOf(u8, text, "branch_only = 4").?, warnings[2].span.start);
    for (warnings) |warning| try testing.expectEqual(language.diagnostic.Severity.warning, warning.severity);
    try compilation.check();
    try testing.expectEqual(@as(usize, 3), compilation.diagnostics.items.len);
}

fn localAllocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "locals.selka",
        \\func main() -> i64:
        \\    mut x = 3
        \\    mut y = 5
        \\    x = x * y
        \\    mut unused = False
        \\    return x
    );
    defer compilation.deinit();
    try compilation.check();
    try testing.expect(compilation.diagnostics.items.len != 0);
    for (compilation.diagnostics.items) |diagnostic| {
        const text = try diagnostic.render(allocator, compilation.src);
        defer allocator.free(text);
    }
}

test "allocation failure during scope checking warning rendering and locals execution releases storage" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), localAllocationScenario, .{});
}

/// Write `func main` returning a left-associative chain of `terms` added ones.
fn additions(text: *std.Io.Writer.Allocating, terms: usize) !void {
    try text.writer.writeAll("func main() -> i64:\n    return 1");
    for (1..terms) |_| try text.writer.writeAll(" + 1");
    try text.writer.writeAll("\n");
}

// spec-case: SEMANTIC-CACHE-7
test "long left-associative expressions do not recursively traverse host stacks" {
    var deep: std.Io.Writer.Allocating = .init(testing.allocator);
    defer deep.deinit();
    try additions(&deep, 4096);
    var compilation = try language.Compilation.init(testing.allocator, "long.selka", deep.written());
    defer compilation.deinit();
    // Parsing and checking 4,096 operands stay iterative; a shorter chain then
    // proves the program still evaluates from the left.
    try compilation.check();
    // The CLI also prepares dependency keys; raw checking alone never exercised
    // this AST traversal and previously hid its recursive stack overflow.
    const keys = try @import("semantic_key.zig").prepare(compilation.arena.allocator(), compilation.src, compilation.syntax.?, .{ .build = "test", .mutation = "mutation-v1" }, null, null);
    try testing.expectEqual(@as(usize, 1), keys.contexts.len);
    var shorter: std.Io.Writer.Allocating = .init(testing.allocator);
    defer shorter.deinit();
    try additions(&shorter, 1024);
    try programResult(shorter.written(), 1024);
}

fn booleanResult(expression: []const u8, expected: bool) !void {
    const text = try std.fmt.allocPrint(testing.allocator, "func main() -> i64:\n    if {s}:\n        return 1\n    else:\n        return 0\n", .{expression});
    defer testing.allocator.free(text);
    try programResult(text, if (expected) 1 else 0);
}

fn flowAllocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "flow.selka",
        \\func main() -> i64:
        \\    mut i = 0
        \\    while i < 5:
        \\        if remtrunc(i, 2) == 0:
        \\            _ = True or divtrunc(1, 0) == 0
        \\        i += 1
        \\    return i
    );
    defer compilation.deinit();
    try compilation.check();
}

test "allocation failures during label patching and control-flow validation release storage" {
    try testing.checkAllAllocationFailures(testing.allocator, flowAllocationScenario, .{});
}

test "function signatures entry points and all uncalled bodies are checked" {
    try programResult(
        \\func f(n: i64) -> i64:
        \\    return n
        \\
        \\
        \\func main() -> i64:
        \\    return f(42)
    , 42);
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text =
        \\func main() -> i64:
        \\    return 1
        \\
        \\
        \\func main() -> i64:
        \\    return 2
        , .code = "E_DUPLICATE_FUNCTION" },
        .{ .text =
        \\func f() -> i64:
        \\    return 1
        \\
        \\
        \\func f() -> bool:
        \\    return True
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        , .code = "E_DUPLICATE_FUNCTION" },
        .{ .text =
        \\func main(n: i64) -> i64:
        \\    return n
        , .code = "E_MAIN" },
        .{ .text =
        \\func main() -> i64:
        \\    return missing()
        , .code = "E_UNKNOWN_FUNCTION" },
        .{ .text =
        \\func main() -> i64:
        \\    mut f = 1
        \\    return f()
        , .code = "E_CALLBACK_TYPE" },
        .{ .text =
        \\func f(n: i64) -> i64:
        \\    return n
        \\
        \\
        \\func main() -> i64:
        \\    return f()
        , .code = "E_ARITY" },
        .{ .text =
        \\func f(n: i64) -> i64:
        \\    return n
        \\
        \\
        \\func main() -> i64:
        \\    return f(1, 2)
        , .code = "E_ARITY" },
        .{ .text =
        \\func f(n: i64) -> i64:
        \\    return n
        \\
        \\
        \\func main() -> i64:
        \\    return f(True)
        , .code = "E_TYPE" },
        .{ .text =
        \\func f(n: i64, n: bool) -> bool:
        \\    return n
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        , .code = "E_DUPLICATE_PARAMETER" },
        .{ .text =
        \\func f(main: i64) -> i64:
        \\    return main
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        , .code = "E_SHADOWING" },
        .{ .text =
        \\func f(n: i64) -> i64:
        \\    mut n: i64 = 2
        \\    return n
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        , .code = "E_SHADOWING" },
        .{ .text =
        \\func main() -> i64:
        \\    mut f = 2
        \\    return f
        \\
        \\
        \\func f() -> i64:
        \\    return 0
        , .code = "E_SHADOWING" },
        .{ .text =
        \\func f() -> bool:
        \\    return 1
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        , .code = "E_TYPE" },
        .{ .text =
        \\func f() -> bool:
        \\    pass
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        , .code = "E_MISSING_RETURN" },
        .{ .text =
        \\func main() -> i64:
        \\    return 0
        \\
        \\
        \\func f() -> i64:
        \\    return unknown
        , .code = "E_UNKNOWN_NAME" },
        .{ .text =
        \\func main() -> i64:
        \\    f()
        \\    return 0
        \\
        \\
        \\func f() -> i64:
        \\    return 1
        , .code = "E_EXPLICIT_DISCARD_REQUIRED" },
        .{ .text =
        \\func main() -> i64:
        \\    return main(1)
        , .code = "E_ARITY" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(testing.allocator, "functions.selka", case.text);
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

test "parameter warnings remain separate between functions and are deferred until full success" {
    var compilation = try language.Compilation.init(testing.allocator, "warnings.selka",
        \\func f(x: i64) -> i64:
        \\    return 0
        \\
        \\
        \\func g(x: i64) -> i64:
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return 7
    );
    defer compilation.deinit();
    try compilation.check();
    try testing.expectEqual(@as(usize, 1), compilation.diagnostics.items.len);
    try testing.expectEqualStrings("W_UNUSED_BINDING", compilation.diagnostics.items[0].code);
    try testing.expectEqual(@as(usize, 7), compilation.diagnostics.items[0].span.start);
    var invalid = try language.Compilation.init(testing.allocator, "bad.selka",
        \\func f(x: i64) -> i64:
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return False
    );
    defer invalid.deinit();
    try testing.expectError(error.SourceError, invalid.check());
    try testing.expectEqual(@as(usize, 1), invalid.diagnostics.items.len);
    try testing.expectEqualStrings("E_TYPE", invalid.diagnostics.items[0].code);
}

test "a file parameter used only through its methods is read, and one the body never touches still warns" {
    const text =
        \\func m_read(f: File) -> bytes:
        \\    return f.read()
        \\func m_readn(f: File) -> bytes:
        \\    return f.read(4)
        \\func m_readline(f: File) -> bytes:
        \\    return f.readline()
        \\func m_readlines(f: File) -> int:
        \\    return len(f.readlines())
        \\func m_write(f: File, data: bytes) -> int:
        \\    return f.write(data)
        \\func m_flush(f: File):
        \\    f.flush()
        \\func m_close(f: File):
        \\    f.close()
        \\func m_sync(f: File) -> Unit fails str:
        \\    return try f.sync()
        \\func t_read(f: TextFile) -> str:
        \\    return f.read()
        \\func t_readline(f: TextFile) -> str:
        \\    return f.readline()
        \\func t_readlines(f: TextFile) -> int:
        \\    return len(f.readlines())
        \\func t_write(f: TextFile, data: str) -> int:
        \\    return f.write(data)
        \\func t_flush(f: TextFile):
        \\    f.flush()
        \\func t_close(f: TextFile):
        \\    f.close()
        \\func t_sync(f: TextFile) -> Unit fails str:
        \\    return try f.sync()
        \\func untouched(f: File) -> int:
        \\    return 1
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("a.bin", "wb") as f:
        \\        _ = m_write(f, b"x")
        \\    return 0
    ;
    var compilation = try language.Compilation.init(testing.allocator, "file_parameters.selka", text);
    defer compilation.deinit();
    try compilation.check();
    try testing.expectEqual(@as(usize, 1), compilation.diagnostics.items.len);
    try testing.expectEqualStrings("W_UNUSED_BINDING", compilation.diagnostics.items[0].code);
    try testing.expectEqual(std.mem.indexOf(u8, text, "f: File) -> int:\n    return 1").?, compilation.diagnostics.items[0].span.start);
}

test "call traces locate guest operators and callers and argument traps evaluate left to right" {
    const text =
        \\func main() -> i64:
        \\    return outer()
        \\
        \\
        \\func outer() -> i64:
        \\    return inner()
        \\
        \\
        \\func inner() -> i64:
        \\    return divtrunc(1, 0)
    ;
    var compilation = try language.Compilation.init(testing.allocator, "trace.selka", text);
    defer compilation.deinit();
    const outcome = try native.run(&compilation);
    try testing.expectEqualStrings("R_DIVISION_BY_ZERO", outcome.trap.code);
    try testing.expectEqual(@as(usize, 3), outcome.trap.frames.len);
    for ([_][]const u8{ "inner", "outer", "main" }, 0..) |name, i| {
        try testing.expectEqualStrings(name, outcome.trap.frames[i].function);
        try testing.expectEqual(@as(u64, 10 - 4 * i), outcome.trap.frames[i].line);
    }
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "in outer at trace.selka:6:") != null);
    var order = try language.Compilation.init(testing.allocator, "order.selka",
        \\func f(a: i64, b: i64) -> i64:
        \\    return a + b
        \\
        \\
        \\func main() -> i64:
        \\    return f(divtrunc(1, 0), 9223372036854775807 + 1)
    );
    defer order.deinit();
    try testing.expectEqualStrings("R_DIVISION_BY_ZERO", (try native.run(&order)).trap.code);
}

fn callAllocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "calls.selka",
        \\func f(n: i64) -> i64:
        \\    if n == 0:
        \\        return divtrunc(1, 0)
        \\    return 1 + f(n - 1)
        \\
        \\
        \\func main() -> i64:
        \\    return f(50)
    );
    defer compilation.deinit();
    try compilation.check();
}

test "allocation failures in signature collection and call emission release storage" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), callAllocationScenario, .{});
}

test "malformed syntax smoke corpus keeps diagnostics inside owned source" {
    const seed =
        \\func main() -> i64:
        \\    mut x = 3
        \\    while x > 0:
        \\        x -= 1
        \\    return x
    ;
    for (0..seed.len) |end| {
        var compilation = try language.Compilation.init(testing.allocator, "prefix.selka", seed[0..end]);
        defer compilation.deinit();
        compilation.check() catch |err| {
            try testing.expectEqual(error.SourceError, err);
            const diag = compilation.diagnostics.items[0];
            try testing.expect(diag.span.start <= diag.span.end and diag.span.end <= end);
        };
    }
}
test "mutated syntax smoke corpus keeps diagnostics inside owned source" {
    const seed =
        \\func main() -> i64:
        \\    mut x = 3
        \\    while x > 0:
        \\        x -= 1
        \\    return x
    ;
    const bytes = [_]u8{ 0, 0xff, '\n', ')', '}', ',', ';', '!', '=', '/', '&', '|' };
    for (0..bytes.len * seed.len) |case| {
        const byte = bytes[case / seed.len];
        const at = case % seed.len;
        var mutated: [seed.len]u8 = seed.*;
        mutated[at] = byte;
        var compilation = try language.Compilation.init(testing.allocator, "mutated.selka", &mutated);
        defer compilation.deinit();
        compilation.check() catch |err| {
            try testing.expectEqual(error.SourceError, err);
            const diag = compilation.diagnostics.items[0];
            try testing.expect(diag.span.start <= diag.span.end and diag.span.end <= mutated.len);
        };
    }
}

test "all recursive syntax forms obey the parser nesting budget" {
    for ([_][]const u8{ "-", "id(", "{" }) |opening| {
        var text: std.Io.Writer.Allocating = .init(testing.allocator);
        defer text.deinit();
        try text.writer.writeAll("func main() -> i64:\n    return ");
        for (0..300) |_| try text.writer.writeAll(opening);
        // Rejection occurs at the resource boundary before trailing syntax matters.
        try text.writer.writeAll("1");
        var compilation = try language.Compilation.init(testing.allocator, "nesting.selka", text.written());
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expectEqualStrings("E_NESTING_LIMIT", compilation.diagnostics.items[0].code);
    }
}

fn rejectedAllocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "rejected.selka",
        \\func main() -> i64:
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return 1
    );
    defer compilation.deinit();
    compilation.check() catch |err| switch (err) {
        error.SourceError => {
            const text = try compilation.diagnostics.items[0].render(allocator, compilation.src);
            defer allocator.free(text);
            return;
        },
        else => return err,
    };
    return error.ExpectedSourceError;
}

test "allocation failures while producing source errors remain host failures and release storage" {
    try testing.checkAllAllocationFailures(testing.allocator, rejectedAllocationScenario, .{});
}

test "short circuit skips traps while an explicit drop retains evaluation" {
    try booleanResult("False and (divtrunc(1, 0) == 0)", false);
    try booleanResult("True or (divtrunc(1, 0) == 0)", true);
    try programResult(
        \\func main() -> i64:
        \\    _ = False and divtrunc(1, 0) == 0
        \\    _ = True or divtrunc(1, 0) == 0
        \\    _ = 1 + 2
        \\    return 7
    , 7);
    try programResult(
        \\func main() -> i64:
        \\    mut flag = False
        \\    flag = True and not flag
        \\    if flag:
        \\        return 4
        \\    else:
        \\        return 9
    , 4);
    const cases = [_]struct { expression: []const u8, code: []const u8 }{
        .{ .expression = "True and (divtrunc(1, 0) == 0)", .code = "R_DIVISION_BY_ZERO" },
        .{ .expression = "False or (divtrunc(1, 0) == 0)", .code = "R_DIVISION_BY_ZERO" },
        .{ .expression = "divtrunc(1, 0)", .code = "R_DIVISION_BY_ZERO" },
        .{ .expression = "remtrunc(1, 0)", .code = "R_DIVISION_BY_ZERO" },
        .{ .expression = "divtrunc(-9223372036854775808, -1)", .code = "R_OVERFLOW" },
        .{ .expression = "(9223372036854775807 + 1) + divtrunc(1, 0)", .code = "R_OVERFLOW" },
        .{ .expression = "divtrunc(1, 0) + (9223372036854775807 + 1)", .code = "R_DIVISION_BY_ZERO" },
    };
    for (cases) |case| {
        const text = try std.fmt.allocPrint(testing.allocator, "func main() -> i64:\n    _ = {s}\n    return 0\n", .{case.expression});
        defer testing.allocator.free(text);
        var compilation = try language.Compilation.init(testing.allocator, "trap.selka", text);
        defer compilation.deinit();
        try compilation.check();
        try testing.expectEqualStrings(case.code, (try native.run(&compilation)).trap.code);
    }
}

test "control flow requires boolean conditions and conservative complete returns" {
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body = "if 1:\n        return 1\n    else:\n        return 0", .code = "E_TYPE" },
        .{ .body = "while 0:\n        pass\n    return 0", .code = "E_TYPE" },
        .{ .body = "if True:\n        return 1", .code = "E_MISSING_RETURN" },
        .{ .body = "while True:\n        break", .code = "E_MISSING_RETURN" },
        .{ .body = "if True:\n        return 1\n    else:\n        return 2\n    return 3", .code = "E_UNREACHABLE" },
        .{ .body = "if True:\n        return 1\n    else:\n        return True", .code = "E_TYPE" },
        .{ .body = "_ = False and unknown\n    return 0", .code = "E_UNKNOWN_NAME" },
        .{ .body = "_ = 1 and True\n    return 0", .code = "E_TYPE" },
        .{ .body = "mut x = True\n    x += False\n    return 0", .code = "E_TYPE" },
        .{ .body = "1 + 2\n    return 0", .code = "E_EXPLICIT_DISCARD_REQUIRED" },
        .{ .body = "if True:\n        const local = 1\n    return local", .code = "E_UNKNOWN_NAME" },
    };
    for (cases) |case| {
        const text = try std.fmt.allocPrint(testing.allocator,
            \\func main() -> i64:
            \\    {s}
        , .{case.body});
        defer testing.allocator.free(text);
        var compilation = try language.Compilation.init(testing.allocator, "bad.selka", text);
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

test "explicit drops and compound assignment count as reads and skipped branches count syntactically" {
    const text =
        \\func main() -> i64:
        \\    mut x = 1
        \\    _ = x
        \\    mut y = 0
        \\    y += 1
        \\    mut z = 0
        \\    if False:
        \\        z = 1
        \\    _ = z
        \\    return 0
    ;
    var compilation = try language.Compilation.init(testing.allocator, "warnings.selka", text);
    defer compilation.deinit();
    try compilation.check();
    try testing.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

test "runtime storage remains bounded across many calls and loop declarations" {
    var compilation = try language.Compilation.init(testing.allocator, "bounded.selka",
        \\func f(n: i64) -> i64:
        \\    mut local = n + 1
        \\    return local
        \\
        \\
        \\func main() -> i64:
        \\    mut n = 0
        \\    while n < 100000:
        \\        mut local = 1 + f(n)
        \\        _ = local
        \\        n += 1
        \\    return n
    );
    defer compilation.deinit();
    // Two live frames are all this program ever needs. Retaining an abandoned
    // frame, local or value for any of the 100,000 iterations would exceed the
    // budget long before the loop finished.
    const outcome = try native.runWithOptions(&compilation, .{ .max_frames = 2 });
    try testing.expectEqual(@as(i64, 100000), outcome.value);
    try testing.expectEqualStrings("", outcome.stdout);
}

test "located source diagnostics include EOF explicit drops and previous declarations" {
    for ([_][]const u8{ "\n", "\r\n" }) |newline| {
        const text = try std.fmt.allocPrint(testing.allocator, "func main() -> i64:{s}    return 1 + {s}", .{ newline, newline });
        defer testing.allocator.free(text);
        var compilation = try language.Compilation.init(testing.allocator, "eof.selka", text);
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        const diag = compilation.diagnostics.items[0];
        try testing.expectEqual(text.len, diag.span.start);
        try testing.expectEqual(text.len, diag.span.end);
        try testing.expectEqual(@as(usize, 3), compilation.src.locate(diag.span.start).line);
        try testing.expectEqual(@as(usize, 1), compilation.src.locate(diag.span.start).column);
    }
    var duplicate = try language.Compilation.init(testing.allocator, "duplicate.selka",
        \\func main() -> i64:
        \\    return 1
        \\
        \\
        \\func main() -> i64:
        \\    return 2
    );
    defer duplicate.deinit();
    try testing.expectError(error.SourceError, duplicate.check());
    const diag = duplicate.diagnostics.items[0];
    try testing.expectEqualStrings("main", duplicate.src.text(diag.span));
    try testing.expectEqual(@as(usize, 5), diag.related.?.span.start);
    const rendered = try diag.render(testing.allocator, duplicate.src);
    defer testing.allocator.free(rendered);
    try testing.expect(std.mem.indexOf(u8, rendered, "note: duplicate.selka:1:6: previous function declaration") != null);
    var discard = try language.Compilation.init(testing.allocator, "ignored.selka",
        \\func main() -> i64:
        \\    1 + 2
        \\    return 7
    );
    defer discard.deinit();
    try testing.expectError(error.SourceError, discard.check());
    try testing.expectEqualStrings("E_EXPLICIT_DISCARD_REQUIRED", discard.diagnostics.items[0].code);
    try testing.expectEqualStrings("1 + 2", discard.src.text(discard.diagnostics.items[0].span));
}
test "the pausing collector reclaims garbage and still enforces the byte budget" {
    var reclaiming = try language.Compilation.init(testing.allocator, "pacing.selka",
        \\func main() -> i64:
        \\    mut n = 0
        \\    while n < 50000:
        \\        mut garbage = [n, n + 1, n + 2, n + 3]
        \\        n += 1
        \\    return n
    );
    defer reclaiming.deinit();
    // Every list is unreachable and the loop allocates several times the ceiling;
    // only collection keeps the run inside the budget.
    const reclaimed = try native.runWithOptions(&reclaiming, .{ .max_memory = 1 << 20 });
    try testing.expectEqual(@as(i64, 50000), reclaimed.value);
    var bounded = try language.Compilation.init(testing.allocator, "pacing.selka",
        \\func main() -> i64:
        \\    mut values: i64[] = []
        \\    mut n = 0
        \\    while n < 400000:
        \\        append(mut values, n)
        \\        n += 1
        \\    return len(values)
    );
    defer bounded.deinit();
    // A live list that outgrows the ceiling still traps, so the budget binds on
    // every allocation and not only when a collection would have run.
    const refused = try native.runWithOptions(&bounded, .{ .max_memory = 1 << 20 });
    try testing.expectEqualStrings("R_MEMORY_BUDGET", refused.trap.code);
}

/// A library with `public func wide(a0: int, ..., mut items: int[])` of `count`
/// parameters whose body reads every one and appends to `items`.
fn wideSource(allocator: std.mem.Allocator, count: usize) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    try text.writer.writeAll("public func wide(");
    for (0..count - 1) |i| try text.writer.print("a{d}: int, ", .{i});
    try text.writer.writeAll("mut items: int[]) -> Unit:\n    append(mut items, 0");
    for (0..count - 1) |i| try text.writer.print(" + a{d}", .{i});
    try text.writer.writeAll(")\n");
    return text.toOwnedSlice();
}

/// Check that the mutation contract keeps the final parameter's actual position.
fn checkWideMutation(count: usize) !void {
    const text = try wideSource(testing.allocator, count);
    defer testing.allocator.free(text);
    var compilation = try language.Compilation.init(testing.allocator, "wide.selka", text);
    defer compilation.deinit();
    const program = try compilation.checkLibraryProgram();
    const signature = program.functions[0].signature;
    try testing.expectEqual(count, signature.parameter_count);
    const expected = [_]u16{@intCast(count - 1)};
    try testing.expectEqualSlices(u16, &expected, signature.declared_mutates);
    try testing.expectEqualSlices(u16, &expected, signature.mutates);
}

// spec: ORIGIN-WIDE-1
test "O3 mut collections preserve declared positions beyond parameter 64" {
    try checkWideMutation(17);
    try checkWideMutation(64);
    try checkWideMutation(65);
    try checkWideMutation(70);
}

/// A borrowed managed result whose only source is beyond the former mask width.
fn wideBorrowSource(allocator: std.mem.Allocator, count: usize) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    try text.writer.writeAll("public func wide(");
    for (0..count - 1) |i| try text.writer.print("a{d}: int, ", .{i});
    try text.writer.writeAll("items: int[][]) -> int[] from items:\n    _ = 0");
    for (0..count - 1) |i| try text.writer.print(" + a{d}", .{i});
    try text.writer.writeAll("\n    return items[0]\n");
    return text.toOwnedSlice();
}

test "O3 borrowed result declarations retain a source beyond parameter 64" {
    const text = try wideBorrowSource(testing.allocator, 70);
    defer testing.allocator.free(text);
    var compilation = try language.Compilation.init(testing.allocator, "wide_borrow.selka", text);
    defer compilation.deinit();
    const program = try compilation.checkLibraryProgram();
    const signature = program.functions[0].signature;
    try testing.expectEqual(@as(usize, 70), signature.parameter_count);
    try testing.expectEqualSlices(u16, &.{69}, signature.return_origin.params);
}
