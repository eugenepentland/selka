//! Semantic fixtures exercise public pipeline behavior and allocation ownership.
const std = @import("std");
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const testing = std.testing;

fn result(expression: []const u8, expected: i64) !void {
    const text = try std.fmt.allocPrint(testing.allocator, "func main() -> i64:\n    return {s}\n", .{expression});
    defer testing.allocator.free(text);
    var compilation = try language.Compilation.init(testing.allocator, "test.my", text);
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
        var compilation = try language.Compilation.init(testing.allocator, "trap.my", text);
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
        var compilation = try language.Compilation.init(testing.allocator, "bad.my", case.text);
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expect(compilation.program == null);
        try testing.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
        try testing.expect(compilation.diagnostics.items[0].span.end <= case.text.len);
    }
}

// spec-case: CHECK-LIBRARY-2
test "a unit without main checks as a library and retains no executable program" {
    var library = try language.Compilation.init(testing.allocator, "lib.my", "public func add(a: int, b: int) -> int:\n    return a + b\n\nfunc mainly() -> int:\n    return 1\n");
    defer library.deinit();
    try library.parse();
    try testing.expect(!library.declaresMain());
    try library.checkLibrary();
    try testing.expect(library.program == null and library.diagnostics.items.len == 0);

    var broken = try language.Compilation.init(testing.allocator, "broken.my", "public func value() -> int:\n    return False\n");
    defer broken.deinit();
    try broken.parse();
    try testing.expectError(error.SourceError, broken.checkLibrary());
    try testing.expectEqualStrings("E_TYPE", broken.diagnostics.items[0].code);

    var entry = try language.Compilation.init(testing.allocator, "entry.my", "func main(count: int) -> int:\n    return count\n");
    defer entry.deinit();
    try entry.parse();
    try testing.expect(entry.declaresMain());
    try testing.expectError(error.SourceError, entry.check());
    try testing.expectEqualStrings("E_MAIN", entry.diagnostics.items[0].code);
}

test "source is owned and CRLF diagnostics locate operators and EOF" {
    const bytes = try testing.allocator.dupe(u8, "# comment\r\nfunc main() -> i64:\r\n    return 9223372036854775807 + 1\r\n");
    var compilation = try language.Compilation.init(testing.allocator, "crlf.my", bytes);
    testing.allocator.free(bytes);
    defer compilation.deinit();
    const outcome = try native.run(&compilation);
    try testing.expectEqual(@as(u64, 3), outcome.trap.line);
    try testing.expectEqual(@as(u64, 32), outcome.trap.column);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "crlf.my:3:32: error[R_OVERFLOW]") != null);
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
    var compilation = try language.Compilation.init(testing.allocator, "deep.my", text.written());
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings("E_NESTING_LIMIT", compilation.diagnostics.items[0].code);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "test.my",
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
    var compilation = try language.Compilation.init(testing.allocator, "program.my", text);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try native.run(&compilation)).value);
}

test "unary arithmetic and directly negated minimum literal" {
    try result("-3 * 2 + 10", 4);
    try result("--8", 8);
    try result("-9223372036854775808", std.math.minInt(i64));
    try result("-((9223372036854775808))", std.math.minInt(i64));
    try result("-9_223_372_036_854_775_808", std.math.minInt(i64));
    var compilation = try language.Compilation.init(testing.allocator, "neg.my",
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
        var compilation = try language.Compilation.init(testing.allocator, "bad.my", text);
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
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
    var compilation = try language.Compilation.init(testing.allocator, "warnings.my", text);
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
    var compilation = try language.Compilation.init(allocator, "locals.my",
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

test "long left-associative expressions do not recursively traverse host stacks" {
    var deep: std.Io.Writer.Allocating = .init(testing.allocator);
    defer deep.deinit();
    try additions(&deep, 4096);
    var compilation = try language.Compilation.init(testing.allocator, "long.my", deep.written());
    defer compilation.deinit();
    // Parsing and checking 4,096 operands stay iterative; a shorter chain then
    // proves the program still evaluates from the left.
    try compilation.check();
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
    var compilation = try language.Compilation.init(allocator, "flow.my",
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
        var compilation = try language.Compilation.init(testing.allocator, "functions.my", case.text);
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

test "parameter warnings remain separate between functions and are deferred until full success" {
    var compilation = try language.Compilation.init(testing.allocator, "warnings.my",
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
    var invalid = try language.Compilation.init(testing.allocator, "bad.my",
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
    var compilation = try language.Compilation.init(testing.allocator, "trace.my", text);
    defer compilation.deinit();
    const outcome = try native.run(&compilation);
    try testing.expectEqualStrings("R_DIVISION_BY_ZERO", outcome.trap.code);
    try testing.expectEqual(@as(usize, 3), outcome.trap.frames.len);
    for ([_][]const u8{ "inner", "outer", "main" }, 0..) |name, i| {
        try testing.expectEqualStrings(name, outcome.trap.frames[i].function);
        try testing.expectEqual(@as(u64, 10 - 4 * i), outcome.trap.frames[i].line);
    }
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "in outer at trace.my:6:") != null);
    var order = try language.Compilation.init(testing.allocator, "order.my",
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
    var compilation = try language.Compilation.init(allocator, "calls.my",
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
        var compilation = try language.Compilation.init(testing.allocator, "prefix.my", seed[0..end]);
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
        var compilation = try language.Compilation.init(testing.allocator, "mutated.my", &mutated);
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
        var compilation = try language.Compilation.init(testing.allocator, "nesting.my", text.written());
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expectEqualStrings("E_NESTING_LIMIT", compilation.diagnostics.items[0].code);
    }
}

fn rejectedAllocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "rejected.my",
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

test "all comparisons boolean operations and logical precedence have observable results" {
    try booleanResult("1 < 2", true);
    try booleanResult("2 < 2", false);
    try booleanResult("2 <= 2", true);
    try booleanResult("3 > 2", true);
    try booleanResult("2 >= 2", true);
    try booleanResult("2 >= 3", false);
    try booleanResult("2 == 2", true);
    try booleanResult("2 != 2", false);
    try booleanResult("True == False", false);
    try booleanResult("True != False", true);
    try booleanResult("not False", true);
    try booleanResult("not True", false);
    try booleanResult("False or True and False", false);
    try booleanResult("True or False and False", true);
    try booleanResult("1 + 2 * 3 == 7 and 4 >= 3", true);
    const operands = [_][]const u8{ "False", "True" };
    for (0..4) |pair| {
        const a = pair / 2;
        const b = pair % 2;
        const left = operands[a];
        const right = operands[b];
        const conjunction = try std.fmt.allocPrint(testing.allocator, "{s} and {s}", .{ left, right });
        defer testing.allocator.free(conjunction);
        const disjunction = try std.fmt.allocPrint(testing.allocator, "{s} or {s}", .{ left, right });
        defer testing.allocator.free(disjunction);
        try booleanResult(conjunction, a == 1 and b == 1);
        try booleanResult(disjunction, a == 1 or b == 1);
    }
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
        var compilation = try language.Compilation.init(testing.allocator, "trap.my", text);
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
        var compilation = try language.Compilation.init(testing.allocator, "bad.my", text);
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
    var compilation = try language.Compilation.init(testing.allocator, "warnings.my", text);
    defer compilation.deinit();
    try compilation.check();
    try testing.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

test "runtime storage remains bounded across many calls and loop declarations" {
    var compilation = try language.Compilation.init(testing.allocator, "bounded.my",
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
        var compilation = try language.Compilation.init(testing.allocator, "eof.my", text);
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        const diag = compilation.diagnostics.items[0];
        try testing.expectEqual(text.len, diag.span.start);
        try testing.expectEqual(text.len, diag.span.end);
        try testing.expectEqual(@as(usize, 3), compilation.src.locate(diag.span.start).line);
        try testing.expectEqual(@as(usize, 1), compilation.src.locate(diag.span.start).column);
    }
    var duplicate = try language.Compilation.init(testing.allocator, "duplicate.my",
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
    try testing.expect(std.mem.indexOf(u8, rendered, "note: duplicate.my:1:6: previous function declaration") != null);
    var discard = try language.Compilation.init(testing.allocator, "ignored.my",
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
    var reclaiming = try language.Compilation.init(testing.allocator, "pacing.my",
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
    var bounded = try language.Compilation.init(testing.allocator, "pacing.my",
        \\func main() -> i64:
        \\    mut values: i64[] = []
        \\    mut n = 0
        \\    while n < 400000:
        \\        values.append(n)
        \\        n += 1
        \\    return len(values)
    );
    defer bounded.deinit();
    // A live list that outgrows the ceiling still traps, so the budget binds on
    // every allocation and not only when a collection would have run.
    const refused = try native.runWithOptions(&bounded, .{ .max_memory = 1 << 20 });
    try testing.expectEqualStrings("R_MEMORY_BUDGET", refused.trap.code);
}

/// A library with `public func wide(a0: int, ..., items: mut list[int])` of `count`
/// parameters whose body reads every one and appends to `items`.
fn wideSource(allocator: std.mem.Allocator, count: usize) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    try text.writer.writeAll("public func wide(");
    for (0..count - 1) |i| try text.writer.print("a{d}: int, ", .{i});
    try text.writer.writeAll("mut items: int[]) -> Unit:\n    items.append(0");
    for (0..count - 1) |i| try text.writer.print(" + a{d}", .{i});
    try text.writer.writeAll(")\n");
    return text.toOwnedSlice();
}

/// Check `wideSource(count)` as a library; the first diagnostic's code, or "" when it checks.
fn wideCheck(count: usize) ![]const u8 {
    const text = try wideSource(testing.allocator, count);
    defer testing.allocator.free(text);
    var compilation = try language.Compilation.init(testing.allocator, "wide.my", text);
    defer compilation.deinit();
    try compilation.parse();
    compilation.checkLibrary() catch |err| switch (err) {
        error.SourceError => return compilation.diagnostics.items[0].code,
        else => return err,
    };
    return "";
}

// spec: ORIGIN-WIDE-1
test "a mut collection at parameter 17 or 64 checks, and one at parameter 65 is a located error" {
    try testing.expectEqualStrings("", try wideCheck(17));
    try testing.expectEqualStrings("", try wideCheck(64));
    try testing.expectEqualStrings("E_PARAMETER_POSITION", try wideCheck(65));
}

// spec-case: SELFHOST-BODY-CHECK-1
test "body check checkRuntime preserves source errors without publishing a program" {
    var compilation = try language.Compilation.init(testing.allocator, "bad-body.my", "func main() -> int:\n    return True\n");
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expect(compilation.program == null);
    try testing.expectEqualStrings("E_TYPE", compilation.diagnostics.items[0].code);
}
