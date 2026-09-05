//! Semantic fixtures exercise public pipeline behavior and allocation ownership.
const std = @import("std");
const language = @import("compiler.zig");
const testing = std.testing;

fn result(expression: []const u8, expected: i64) !void {
    const text = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ return {s}; }}", .{expression});
    defer testing.allocator.free(text);
    var compilation = try language.Compilation.init(testing.allocator, "test.my", text);
    defer compilation.deinit();
    const outcome = try compilation.execute(testing.allocator);
    try testing.expectEqual(expected, outcome.value);
}

test "precedence grouping left associativity and operand order" {
    try result("1 + 2 * 3", 7);
    try result("(1 + 2) * 3", 9);
    try result("20 - 6 - 2", 12);
    try result("1 - 3 * 4", -11);
    try result("9223372036854775807", std.math.maxInt(i64));
    try result("00012", 12);
}

test "overflow traps at the responsible operator without folding during check" {
    const cases = [_][]const u8{
        "9223372036854775807 + 1",       "3037000500 * 3037000500",
        "(0 - 9223372036854775807) - 2",
    };
    for (cases) |expression| {
        const text = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ return {s}; }}", .{expression});
        defer testing.allocator.free(text);
        var compilation = try language.Compilation.init(testing.allocator, "trap.my", text);
        defer compilation.deinit();
        try compilation.check();
        try testing.expect(compilation.code == null);
        const outcome = try compilation.execute(testing.allocator);
        try testing.expectEqualStrings("R_OVERFLOW", outcome.trap.code);
        const token = compilation.src.text(outcome.trap.span);
        try testing.expect(token.len == 1 and (token[0] == '+' or token[0] == '-' or token[0] == '*'));
    }
}

test "malformed source and range errors are normal located diagnostics" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text = "", .code = "E_MAIN" },
        .{ .text = "fn main() -> i64 { return 1 + ; }", .code = "E_EXPRESSION" },
        .{ .text = "fn main() -> i64 { return 1;", .code = "E_SYNTAX" },
        .{ .text = "fn main() -> i64 { return 9223372036854775808; }", .code = "E_INTEGER_RANGE" },
        .{ .text = "fn main() -> i64 { return 999999999999999999999999999999999999999; }", .code = "E_INTEGER_RANGE" },
        .{ .text = "fn helper() -> i64 { return 1; }", .code = "E_MAIN" },
        .{ .text = "fn main() -> bool { return 1; }", .code = "E_TYPE" },
        .{ .text = "fn main() -> i64 { return @; }", .code = "E_TOKEN" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(testing.allocator, "bad.my", case.text);
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expect(compilation.program == null and compilation.code == null);
        try testing.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
        try testing.expect(compilation.diagnostics.items[0].span.end <= case.text.len);
    }
}

test "source is owned and CRLF diagnostics locate operators and EOF" {
    const bytes = try testing.allocator.dupe(u8, "// comment\r\nfn main() -> i64 {\r\nreturn 9223372036854775807 + 1;\r\n}");
    var compilation = try language.Compilation.init(testing.allocator, "crlf.my", bytes);
    testing.allocator.free(bytes);
    defer compilation.deinit();
    const outcome = try compilation.execute(testing.allocator);
    const location = compilation.src.locate(outcome.trap.span.start);
    try testing.expectEqual(@as(usize, 3), location.line);
    try testing.expectEqual(@as(usize, 28), location.column);
    const rendered = try outcome.trap.render(testing.allocator, compilation.src);
    defer testing.allocator.free(rendered);
    try testing.expect(std.mem.indexOf(u8, rendered, "crlf.my:3:28: error[R_OVERFLOW]") != null);
    try testing.expect(std.mem.indexOfScalar(u8, rendered, '\r') == null);
    try testing.expectEqual(@as(usize, 4), compilation.src.locate(compilation.src.bytes.len).line);
}

test "bytecode dump is deterministic and multiplication precedes addition" {
    var compilation = try language.Compilation.init(testing.allocator, "test.my", "fn main() -> i64 { return 1 + 2 * 3; }");
    defer compilation.deinit();
    const first = try compilation.dump(testing.allocator);
    defer testing.allocator.free(first);
    const second = try compilation.dump(testing.allocator);
    defer testing.allocator.free(second);
    try testing.expectEqualStrings(first, second);
    try testing.expect(std.mem.indexOf(u8, first, "MUL_I64_CHECKED").? < std.mem.indexOf(u8, first, "ADD_I64_CHECKED").?);
}

test "parser rejects excessive nesting without a host stack overflow" {
    var text: std.Io.Writer.Allocating = .init(testing.allocator);
    defer text.deinit();
    try text.writer.writeAll("fn main() -> i64 { return ");
    for (0..300) |_| try text.writer.writeByte('(');
    try text.writer.writeByte('1');
    for (0..300) |_| try text.writer.writeByte(')');
    try text.writer.writeAll("; }");
    var compilation = try language.Compilation.init(testing.allocator, "deep.my", text.written());
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings("E_NESTING_LIMIT", compilation.diagnostics.items[0].code);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "test.my", "fn main() -> i64 { return (1 + 2) * 3; }");
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 9), (try compilation.execute(allocator)).value);
    const text = try compilation.dump(allocator);
    defer allocator.free(text);
}

test "request allocation failures release all owned storage" {
    try testing.checkAllAllocationFailures(testing.allocator, allocationScenario, .{});
}

test "invalid internal bytecode is not a guest trap" {
    const program: language.bytecode.Program = .{ .functions = &.{.{
        .id = @fromBackingInt(@intCast(0)),
        .name = "main",
        .instructions = &.{.{ .span = .{ .start = 0, .end = 0 }, .op = .ret }},
    }} };
    try testing.expectError(error.InternalError, language.vm.run(testing.allocator, program));
}

fn programResult(text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(testing.allocator, "program.my", text);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try compilation.execute(testing.allocator)).value);
}

test "locals mutation annotations and lexical scope" {
    try programResult("fn main() -> i64 { let n = 7; let mut result: i64 = n; { let amount = 3; result = result * amount; } return result; }", 21);
    try programResult("fn main() -> i64 { let mut result = 0; { let x = 2; result = x; } { let x = 3; result = result + x; } return result; }", 5);
    try programResult("fn main() -> i64 { { return 8; } }", 8);
    try programResult("fn main() -> i64 { let mut flag: bool = true; flag = !flag; let equal = flag == false; return 4; }", 4);
}

test "unary arithmetic and directly negated minimum literal" {
    try result("-3 * 2 + 10", 4);
    try result("--8", 8);
    try result("-9223372036854775808", std.math.minInt(i64));
    try result("-((9223372036854775808))", std.math.minInt(i64));
    try result("-0009223372036854775808", std.math.minInt(i64));
    var compilation = try language.Compilation.init(testing.allocator, "neg.my", "fn main() -> i64 { return --9223372036854775808; }");
    defer compilation.deinit();
    const outcome = try compilation.execute(testing.allocator);
    try testing.expectEqualStrings("R_OVERFLOW", outcome.trap.code);
    try testing.expectEqual(std.mem.indexOf(u8, compilation.src.bytes, "--").?, outcome.trap.span.start);
}

test "scope types immutability and structural return diagnostics" {
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body = "let x = 1; x = 2; return x;", .code = "E_IMMUTABLE" },
        .{ .body = "let x = 1; { let x = 2; } return x;", .code = "E_SHADOWING" },
        .{ .body = "let main = 1; return main;", .code = "E_SHADOWING" },
        .{ .body = "let x = x; return x;", .code = "E_UNKNOWN_NAME" },
        .{ .body = "{ let x = 1; } return x;", .code = "E_UNKNOWN_NAME" },
        .{ .body = "x = 1; return 0;", .code = "E_UNKNOWN_NAME" },
        .{ .body = "let x: bool = 1; return 0;", .code = "E_TYPE" },
        .{ .body = "let mut x = true; x = 1; return 0;", .code = "E_TYPE" },
        .{ .body = "return true + 1;", .code = "E_TYPE" },
        .{ .body = "let b = true < false; return 0;", .code = "E_TYPE" },
        .{ .body = "let b = true == 1; return 0;", .code = "E_TYPE" },
        .{ .body = "return !1;", .code = "E_TYPE" },
        .{ .body = "return -true;", .code = "E_TYPE" },
        .{ .body = "return true;", .code = "E_TYPE" },
        .{ .body = "let x = 1;", .code = "E_MISSING_RETURN" },
        .{ .body = "{ return 1; } return 2;", .code = "E_UNREACHABLE" },
        .{ .body = "return -(9223372036854775808 + 0);", .code = "E_INTEGER_RANGE" },
        .{ .body = "return -9223372036854775809;", .code = "E_INTEGER_RANGE" },
        .{ .body = "let bool = 1; return 0;", .code = "E_SYNTAX" },
    };
    for (cases) |case| {
        const text = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ {s} }}", .{case.body});
        defer testing.allocator.free(text);
        var compilation = try language.Compilation.init(testing.allocator, "bad.my", text);
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

test "binding warnings distinguish writes from reads and sibling identities" {
    const text = "fn main() -> i64 { let mut unused = 1; let mut write_only = 2; write_only = 3; { let x = 4; } { let x = 5; return x; } }";
    var compilation = try language.Compilation.init(testing.allocator, "warnings.my", text);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 5), (try compilation.execute(testing.allocator)).value);
    const warnings = compilation.diagnostics.items;
    try testing.expectEqual(@as(usize, 4), warnings.len);
    try testing.expectEqualStrings("W_UNNECESSARY_MUT", warnings[0].code);
    try testing.expectEqualStrings("W_UNUSED_BINDING", warnings[1].code);
    try testing.expectEqualStrings("unused", compilation.src.text(warnings[0].span));
    try testing.expectEqualStrings("write_only", compilation.src.text(warnings[2].span));
    try testing.expectEqualStrings("x", compilation.src.text(warnings[3].span));
    try testing.expectEqual(std.mem.indexOf(u8, text, "x = 4").?, warnings[3].span.start);
    for (warnings) |warning| try testing.expectEqual(language.diagnostic.Severity.warning, warning.severity);
    try compilation.check();
    try testing.expectEqual(@as(usize, 4), compilation.diagnostics.items.len);
}

fn localAllocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "locals.my", "fn main() -> i64 { let mut x = 3; { let y = 5; x = x * y; } let unused = false; return x; }");
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 15), (try compilation.execute(allocator)).value);
    for (compilation.diagnostics.items) |diagnostic| {
        const text = try diagnostic.render(allocator, compilation.src);
        defer allocator.free(text);
    }
}

test "allocation failure during scope checking warning rendering and locals execution releases storage" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), localAllocationScenario, .{});
}

test "long left-associative expressions do not recursively traverse host stacks" {
    var text: std.Io.Writer.Allocating = .init(testing.allocator);
    defer text.deinit();
    try text.writer.writeAll("fn main() -> i64 { return 1");
    for (0..4095) |_| try text.writer.writeAll(" + 1");
    try text.writer.writeAll("; }");
    try programResult(text.written(), 4096);
}

test "branches and loops execute both outcomes with balanced statements" {
    try programResult("fn main() -> i64 { let mut total = 0; let mut i = 0; while i < 100 { total += i; i += 1; } return total; }", 4950);
    try programResult("fn main() -> i64 { let mut x = 48; let mut y = 18; while y != 0 { let remainder = x % y; x = y; y = remainder; } return x; }", 6);
    try programResult("fn main() -> i64 { let mut x = 3; while false { x = 100; } if x < 2 { return 8; } else if x == 3 { return 9; } else { return 10; } }", 9);
    try programResult("fn main() -> i64 { let mut x = 0; if true { x = 4; } else { x = 9; } if false { return 6; } return x; }", 4);
    try programResult("fn main() -> i64 { while true { return 5; } return 6; }", 5);
    try programResult("fn main() -> i64 { let mut x = 5; x -= 2; return x; }", 3);
    try programResult("fn main() -> i64 { let mut i = 0; while i < 5000 { let local = i; discard local * 2; i += 1; } return i; }", 5000);
}

fn booleanResult(expression: []const u8, expected: bool) !void {
    const text = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ if {s} {{ return 1; }} else {{ return 0; }} }}", .{expression});
    defer testing.allocator.free(text);
    try programResult(text, if (expected) 1 else 0);
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
    try booleanResult("true == false", false);
    try booleanResult("true != false", true);
    try booleanResult("!false", true);
    try booleanResult("!true", false);
    try booleanResult("false || true && false", false);
    try booleanResult("true || false && false", true);
    try booleanResult("1 + 2 * 3 == 7 && 4 >= 3", true);
    const operands = [_][]const u8{ "false", "true" };
    for (operands, 0..) |left, a| for (operands, 0..) |right, b| {
        const conjunction = try std.fmt.allocPrint(testing.allocator, "{s} && {s}", .{ left, right });
        defer testing.allocator.free(conjunction);
        const disjunction = try std.fmt.allocPrint(testing.allocator, "{s} || {s}", .{ left, right });
        defer testing.allocator.free(disjunction);
        try booleanResult(conjunction, a == 1 and b == 1);
        try booleanResult(disjunction, a == 1 or b == 1);
    };
}

test "short circuit skips traps while explicit discard retains evaluation" {
    try booleanResult("false && (1 / 0 == 0)", false);
    try booleanResult("true || (1 / 0 == 0)", true);
    try programResult("fn main() -> i64 { discard false && (1 / 0 == 0); discard true || (1 / 0 == 0); discard 1 + 2; return 7; }", 7);
    try programResult("fn main() -> i64 { let mut flag = false; flag = true && !flag; if flag { return 4; } else { return 9; } }", 4);
    const cases = [_]struct { expression: []const u8, code: []const u8 }{
        .{ .expression = "true && (1 / 0 == 0)", .code = "R_DIVISION_BY_ZERO" },
        .{ .expression = "false || (1 / 0 == 0)", .code = "R_DIVISION_BY_ZERO" },
        .{ .expression = "1 / 0", .code = "R_DIVISION_BY_ZERO" },
        .{ .expression = "1 % 0", .code = "R_DIVISION_BY_ZERO" },
        .{ .expression = "-9223372036854775808 / -1", .code = "R_OVERFLOW" },
        .{ .expression = "(9223372036854775807 + 1) + (1 / 0)", .code = "R_OVERFLOW" },
        .{ .expression = "(1 / 0) + (9223372036854775807 + 1)", .code = "R_DIVISION_BY_ZERO" },
    };
    for (cases) |case| {
        const text = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ discard {s}; return 0; }}", .{case.expression});
        defer testing.allocator.free(text);
        var compilation = try language.Compilation.init(testing.allocator, "trap.my", text);
        defer compilation.deinit();
        try compilation.check();
        try testing.expectEqualStrings(case.code, (try compilation.execute(testing.allocator)).trap.code);
    }
}

test "signed division and remainder implement truncation toward zero" {
    try result("-7 / 3", -2);
    try result("7 / -3", -2);
    try result("-7 / -3", 2);
    try result("-7 % 3", -1);
    try result("7 % -3", 1);
    try result("-7 % -3", -1);
    try result("-9223372036854775808 % -1", 0);
    try result("20 - 6 / 2", 17);
}

test "control flow requires boolean conditions and conservative complete returns" {
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body = "if 1 { return 1; } else { return 0; }", .code = "E_TYPE" },
        .{ .body = "while 0 {} return 0;", .code = "E_TYPE" },
        .{ .body = "if true { return 1; }", .code = "E_MISSING_RETURN" },
        .{ .body = "while true { return 1; }", .code = "E_MISSING_RETURN" },
        .{ .body = "if true { return 1; } else { return 2; } return 3;", .code = "E_UNREACHABLE" },
        .{ .body = "if true { return 1; } else { return true; }", .code = "E_TYPE" },
        .{ .body = "discard false && unknown; return 0;", .code = "E_UNKNOWN_NAME" },
        .{ .body = "discard 1 && true; return 0;", .code = "E_TYPE" },
        .{ .body = "let mut x = true; x += false; return 0;", .code = "E_TYPE" },
        .{ .body = "1 + 2; return 0;", .code = "E_EXPLICIT_DISCARD_REQUIRED" },
        .{ .body = "if true { let local = 1; } return local;", .code = "E_UNKNOWN_NAME" },
    };
    for (cases) |case| {
        const text = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{ {s} }}", .{case.body});
        defer testing.allocator.free(text);
        var compilation = try language.Compilation.init(testing.allocator, "bad.my", text);
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

test "instruction limit is checked before the next dispatch" {
    var compilation = try language.Compilation.init(testing.allocator, "budget.my", "fn main() -> i64 { return 1; }");
    defer compilation.deinit();
    try testing.expectEqualStrings("R_STEP_LIMIT", (try compilation.executeWithOptions(testing.allocator, .{ .max_steps = 1 })).trap.code);
    try testing.expectEqual(@as(i64, 1), (try compilation.executeWithOptions(testing.allocator, .{ .max_steps = 2 })).value);
    try testing.expectError(error.InvalidBudget, compilation.executeWithOptions(testing.allocator, .{ .max_steps = 0 }));
    var infinite = try language.Compilation.init(testing.allocator, "loop.my", "fn main() -> i64 { while true {} return 0; }");
    defer infinite.deinit();
    const outcome = try infinite.executeWithOptions(testing.allocator, .{ .max_steps = 123 });
    try testing.expectEqualStrings("R_STEP_LIMIT", outcome.trap.code);
    try testing.expect(outcome.trap.span.start < infinite.src.bytes.len);
}

test "discard and compound assignment count as reads and skipped branches count syntactically" {
    const text = "fn main() -> i64 { let x = 1; discard x; let mut y = 0; y += 1; let mut z = 0; if false { z = 1; } discard z; return 0; }";
    var compilation = try language.Compilation.init(testing.allocator, "warnings.my", text);
    defer compilation.deinit();
    try compilation.check();
    try testing.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

fn flowAllocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "flow.my", "fn main() -> i64 { let mut i = 0; while i < 5 { if i % 2 == 0 { discard true || (1 / 0 == 0); } i += 1; } return i; }");
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 5), (try compilation.execute(allocator)).value);
}

test "allocation failures during label patching and control-flow validation release storage" {
    try testing.checkAllAllocationFailures(testing.allocator, flowAllocationScenario, .{});
}

test "forward mutual recursive and nested calls preserve caller operands" {
    try programResult("fn main() -> i64 { return 1 + add(add(2, 3), add(4, 5)); } fn add(a: i64, b: i64) -> i64 { return a + b; }", 15);
    try programResult("fn fact(n: i64) -> i64 { if n <= 1 { return 1; } return n * fact(n - 1); } fn main() -> i64 { return fact(10); }", 3628800);
    try programResult("fn even(n: i64) -> bool { if n == 0 { return true; } return odd(n - 1); } fn main() -> i64 { if even(100) && !odd(100) { return 7; } return 0; } fn odd(n: i64) -> bool { if n == 0 { return false; } return even(n - 1); }", 7);
    try programResult("fn f(n: i64) -> i64 { let x = n + 2; discard g(x); return x; } fn g(x: i64) -> bool { return x > 0; } fn main() -> i64 { let mut n = 0; while n < 5000 { discard f(n); n += 1; } return 1 + f(2); }", 5);
    try programResult("fn f(x: bool, y: i64) -> bool { return x && y > 0; } fn main() -> i64 { if f(true, 2) { return 8; } return 0; }", 8);
}

test "function signatures entry points and all uncalled bodies are checked" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text = "fn main() -> i64 { return 1; } fn main() -> i64 { return 2; }", .code = "E_DUPLICATE_FUNCTION" },
        .{ .text = "fn f() -> i64 { return 1; } fn f() -> bool { return true; } fn main() -> i64 { return 0; }", .code = "E_DUPLICATE_FUNCTION" },
        .{ .text = "fn main(n: i64) -> i64 { return n; }", .code = "E_MAIN" },
        .{ .text = "fn main() -> i64 { return missing(); }", .code = "E_UNKNOWN_FUNCTION" },
        .{ .text = "fn main() -> i64 { let f = 1; return f(); }", .code = "E_UNKNOWN_FUNCTION" },
        .{ .text = "fn f(n: i64) -> i64 { return n; } fn main() -> i64 { return f(); }", .code = "E_ARITY" },
        .{ .text = "fn f(n: i64) -> i64 { return n; } fn main() -> i64 { return f(1, 2); }", .code = "E_ARITY" },
        .{ .text = "fn f(n: i64) -> i64 { return n; } fn main() -> i64 { return f(true); }", .code = "E_TYPE" },
        .{ .text = "fn f(n: i64, n: bool) -> bool { return n; } fn main() -> i64 { return 0; }", .code = "E_DUPLICATE_PARAMETER" },
        .{ .text = "fn f(main: i64) -> i64 { return main; } fn main() -> i64 { return 0; }", .code = "E_SHADOWING" },
        .{ .text = "fn f(n: i64) -> i64 { let n = 2; return n; } fn main() -> i64 { return 0; }", .code = "E_SHADOWING" },
        .{ .text = "fn main() -> i64 { let f = 2; return f; } fn f() -> i64 { return 0; }", .code = "E_SHADOWING" },
        .{ .text = "fn f(n: i64) -> i64 { n = 2; return n; } fn main() -> i64 { return 0; }", .code = "E_IMMUTABLE" },
        .{ .text = "fn f() -> bool { return 1; } fn main() -> i64 { return 0; }", .code = "E_TYPE" },
        .{ .text = "fn f() -> bool {} fn main() -> i64 { return 0; }", .code = "E_MISSING_RETURN" },
        .{ .text = "fn main() -> i64 { return 0; } fn f() -> i64 { return unknown; }", .code = "E_UNKNOWN_NAME" },
        .{ .text = "fn main() -> i64 { f(); return 0; } fn f() -> i64 { return 1; }", .code = "E_EXPLICIT_DISCARD_REQUIRED" },
        .{ .text = "fn main() -> i64 { return main(1,); }", .code = "E_EXPRESSION" },
        .{ .text = "fn f(n: i64,) -> i64 { return n; } fn main() -> i64 { return 0; }", .code = "E_SYNTAX" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(testing.allocator, "functions.my", case.text);
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

test "parameter warnings remain separate between functions and are deferred until full success" {
    var compilation = try language.Compilation.init(testing.allocator, "warnings.my", "fn f(x: i64) -> i64 { return 0; } fn g(x: i64) -> i64 { return x; } fn main() -> i64 { return 7; }");
    defer compilation.deinit();
    try compilation.check();
    try testing.expectEqual(@as(usize, 1), compilation.diagnostics.items.len);
    try testing.expectEqualStrings("W_UNUSED_BINDING", compilation.diagnostics.items[0].code);
    try testing.expectEqual(@as(usize, 5), compilation.diagnostics.items[0].span.start);
    var invalid = try language.Compilation.init(testing.allocator, "bad.my", "fn f(x: i64) -> i64 { return 0; } fn main() -> i64 { return false; }");
    defer invalid.deinit();
    try testing.expectError(error.SourceError, invalid.check());
    try testing.expectEqual(@as(usize, 1), invalid.diagnostics.items.len);
    try testing.expectEqualStrings("E_TYPE", invalid.diagnostics.items[0].code);
}

test "frame limits count main and guest recursion never consumes the host call stack" {
    var compilation = try language.Compilation.init(testing.allocator, "frames.my", "fn main() -> i64 { return main(); }");
    defer compilation.deinit();
    try testing.expectError(error.InvalidBudget, compilation.executeWithOptions(testing.allocator, .{ .max_frames = 0 }));
    const one = try compilation.executeWithOptions(testing.allocator, .{ .max_frames = 1 });
    try testing.expectEqualStrings("R_FRAME_LIMIT", one.trap.code);
    try testing.expectEqual(@as(usize, 1), one.trap.trace_len);
    const deep = try compilation.executeWithOptions(testing.allocator, .{ .max_frames = 20_000 });
    try testing.expectEqualStrings("R_FRAME_LIMIT", deep.trap.code);
    try testing.expectEqual(@as(usize, 16), deep.trap.trace_len);
    try testing.expectEqual(@as(usize, 19_984), deep.trap.trace_omitted);
    const step = try compilation.executeWithOptions(testing.allocator, .{ .max_steps = 2 });
    try testing.expectEqualStrings("R_STEP_LIMIT", step.trap.code);
    try testing.expectEqual(@as(usize, 3), step.trap.trace_len);
}

test "call traces locate guest operators and callers and argument traps evaluate left to right" {
    const text = "fn main() -> i64 { return outer(); }\nfn outer() -> i64 { return inner(); }\nfn inner() -> i64 { return 1 / 0; }";
    var compilation = try language.Compilation.init(testing.allocator, "trace.my", text);
    defer compilation.deinit();
    const outcome = try compilation.execute(testing.allocator);
    try testing.expectEqualStrings("R_DIVISION_BY_ZERO", outcome.trap.code);
    try testing.expectEqual(@as(usize, 3), outcome.trap.trace_len);
    for ([_][]const u8{ "inner", "outer", "main" }, 0..) |name, i| {
        try testing.expectEqualStrings(name, outcome.trap.trace[i].function);
        try testing.expectEqual(3 - i, compilation.src.locate(outcome.trap.trace[i].span.start).line);
    }
    const rendered = try outcome.trap.render(testing.allocator, compilation.src);
    defer testing.allocator.free(rendered);
    try testing.expect(std.mem.indexOf(u8, rendered, "in outer at trace.my:2:") != null);
    var order = try language.Compilation.init(testing.allocator, "order.my", "fn f(a: i64, b: i64) -> i64 { return a + b; } fn main() -> i64 { return f(1 / 0, 9223372036854775807 + 1); }");
    defer order.deinit();
    try testing.expectEqualStrings("R_DIVISION_BY_ZERO", (try order.execute(testing.allocator)).trap.code);
}

fn callAllocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "calls.my", "fn f(n: i64) -> i64 { if n == 0 { return 1 / 0; } return 1 + f(n - 1); } fn main() -> i64 { return f(50); }");
    defer compilation.deinit();
    const outcome = try compilation.execute(allocator);
    const rendered = try outcome.trap.render(allocator, compilation.src);
    defer allocator.free(rendered);
    const dumped = try compilation.dump(allocator);
    defer allocator.free(dumped);
}

test "allocation failures in signature collection calls frame growth and trace rendering release storage" {
    try testing.checkAllAllocationFailures(testing.allocator, callAllocationScenario, .{});
}

test "runtime storage remains bounded across many calls and loop declarations" {
    var compilation = try language.Compilation.init(testing.allocator, "bounded.my", "fn f(n: i64) -> i64 { let local = n + 1; return local; } fn main() -> i64 { let mut n = 0; while n < 100000 { let local = 1 + f(n); discard local; n += 1; } return n; }");
    defer compilation.deinit();
    try compilation.emit();
    // Includes validator scratch and all three VM buffers. Retaining abandoned
    // values, locals, or frames for 100,000 iterations would exceed this buffer.
    var storage: [16 * 1024]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&storage);
    const outcome = try compilation.execute(fixed.allocator());
    try testing.expectEqual(@as(i64, 100000), outcome.value);
    for (0..20) |_| {
        try testing.expectEqual(@as(i64, 100000), (try compilation.execute(testing.allocator)).value);
    }
}

test "malformed syntax smoke corpus keeps diagnostics inside owned source" {
    const seed = "fn main() -> i64 { let mut x = 3; while x > 0 { x -= 1; } return x; }";
    for (0..seed.len) |end| {
        var compilation = try language.Compilation.init(testing.allocator, "prefix.my", seed[0..end]);
        defer compilation.deinit();
        compilation.check() catch |err| {
            try testing.expectEqual(error.SourceError, err);
            const diag = compilation.diagnostics.items[0];
            try testing.expect(diag.span.start <= diag.span.end and diag.span.end <= end);
        };
    }
    const bytes = [_]u8{ 0, 0xff, '\n', ')', '}', ',', ';', '!', '=', '/', '&', '|' };
    for (bytes) |byte| for (0..seed.len) |at| {
        var mutated: [seed.len]u8 = seed.*;
        mutated[at] = byte;
        var compilation = try language.Compilation.init(testing.allocator, "mutated.my", &mutated);
        defer compilation.deinit();
        compilation.check() catch |err| {
            try testing.expectEqual(error.SourceError, err);
            const diag = compilation.diagnostics.items[0];
            try testing.expect(diag.span.start <= diag.span.end and diag.span.end <= mutated.len);
        };
    };
}

test "all recursive syntax forms obey the parser nesting budget" {
    for ([_][]const u8{ "-", "id(", "{" }) |opening| {
        var text: std.Io.Writer.Allocating = .init(testing.allocator);
        defer text.deinit();
        try text.writer.writeAll("fn main() -> i64 { ");
        if (!std.mem.eql(u8, opening, "{")) try text.writer.writeAll("return ");
        for (0..300) |_| try text.writer.writeAll(opening);
        // Rejection occurs at the resource boundary before trailing syntax matters.
        try text.writer.writeAll("1");
        var compilation = try language.Compilation.init(testing.allocator, "nesting.my", text.written());
        defer compilation.deinit();
        try testing.expectError(error.SourceError, compilation.check());
        try testing.expectEqualStrings("E_NESTING_LIMIT", compilation.diagnostics.items[0].code);
    }
}

test "located source diagnostics include EOF discard and previous declarations" {
    for ([_][]const u8{ "\n", "\r\n" }) |newline| {
        const text = try std.fmt.allocPrint(testing.allocator, "fn main() -> i64 {{{s}return 1;{s}", .{ newline, newline });
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
    var duplicate = try language.Compilation.init(testing.allocator, "duplicate.my", "fn main() -> i64 { return 1; }\nfn main() -> i64 { return 2; }");
    defer duplicate.deinit();
    try testing.expectError(error.SourceError, duplicate.check());
    const diag = duplicate.diagnostics.items[0];
    try testing.expectEqualStrings("main", duplicate.src.text(diag.span));
    try testing.expectEqual(@as(usize, 3), diag.related.?.span.start);
    const rendered = try diag.render(testing.allocator, duplicate.src);
    defer testing.allocator.free(rendered);
    try testing.expect(std.mem.indexOf(u8, rendered, "note: duplicate.my:1:4: previous function declaration") != null);
    var discard = try language.Compilation.init(testing.allocator, "discard.my", "fn main() -> i64 {\n  1 + 2;\n  return 7;\n}");
    defer discard.deinit();
    try testing.expectError(error.SourceError, discard.check());
    try testing.expectEqualStrings("E_EXPLICIT_DISCARD_REQUIRED", discard.diagnostics.items[0].code);
    try testing.expectEqualStrings("1", discard.src.text(discard.diagnostics.items[0].span));
}

test "emission validation rejects invalid references jumps and inconsistent joins" {
    const bc = language.bytecode;
    const span: language.source.Span = .{ .start = 0, .end = 0 };
    const variants = [_][]const bc.Instruction{
        &.{.{ .span = span, .op = .{ .jump = 1 } }},
        &.{.{ .span = span, .op = .{ .call = @fromBackingInt(1) } }},
        &.{.{ .span = span, .op = .{ .load_local = @fromBackingInt(0) } }},
        &.{ .{ .span = span, .op = .{ .push_bool = true } }, .{ .span = span, .op = .{ .jump_if_false = 3 } }, .{ .span = span, .op = .{ .push_i64 = 1 } }, .{ .span = span, .op = .{ .jump = 3 } } },
    };
    for (variants) |instructions| {
        const program: bc.Program = .{ .functions = &.{.{ .id = @fromBackingInt(0), .name = "main", .instructions = instructions }} };
        try testing.expectError(error.InternalError, language.vm.run(testing.allocator, program));
    }
}

fn rejectedAllocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "rejected.my", "fn main() -> i64 { return 0; } fn main() -> i64 { return 1; }");
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
