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
        .{ .text = "", .code = "E_SYNTAX" },
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
    try testing.checkAllAllocationFailures(testing.allocator, localAllocationScenario, .{});
}

test "long left-associative expressions do not recursively traverse host stacks" {
    var text: std.Io.Writer.Allocating = .init(testing.allocator);
    defer text.deinit();
    try text.writer.writeAll("fn main() -> i64 { return 1");
    for (0..4095) |_| try text.writer.writeAll(" + 1");
    try text.writer.writeAll("; }");
    try programResult(text.written(), 4096);
}
