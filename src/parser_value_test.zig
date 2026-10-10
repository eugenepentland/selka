//! Lossless full-AST boundary and adversarial table qualification.
const std = @import("std");
const ast = @import("ast.zig");
const parser = @import("parser.zig");
const lexer = @import("lexer.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");
const wire = @import("parser_value.zig");

fn parse(a: std.mem.Allocator, text: []const u8) !ast.Program {
    const src = try source.Source.init(a, "syntax.my", text);
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try lexer.lex(a, src.bytes, &sink);
    var p: parser.Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = &sink };
    return p.parse();
}

fn roundtrip(a: std.mem.Allocator, text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const program = try parse(arena.allocator(), text);
    const encoded = try wire.encode(a, program);
    defer a.free(encoded);
    var result = try wire.decode(a, encoded, text.len);
    defer result.deinit();
    const second = try wire.encode(a, result.program);
    defer a.free(second);
    try std.testing.expectEqualSlices(u8, encoded, second);
}

// spec: SELFHOST-PARSER-VALUE-1
test "parser values preserve declarations, calls, policies and exact operator spans" {
    try roundtrip(std.testing.allocator, "record Pair:\n    left: int\n    right: int\n\npublic func sum(p: Pair, extra: int = 1) -> int:\n    const value: int = p.left + p.right * extra\n    return value\n");
    try roundtrip(std.testing.allocator, "func answer() -> int:\n    mut x = 1\n    if x < 2:\n        x += 3\n    else:\n        x = 4\n    return x\n");
    try std.testing.expect(wire.max_values > 0);
}

// spec-case: SELFHOST-PARSER-VALUE-1
test "parser values reject truncation trailing data bad tags and stale schema" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const text = "func answer() -> int:\n    return 42\n";
    const bytes = try wire.encode(a, try parse(arena.allocator(), text));
    defer a.free(bytes);
    try std.testing.expectError(error.ComponentProtocol, wire.decode(a, bytes[0 .. bytes.len - 1], text.len));
    const trailing = try std.mem.concat(a, u8, &.{ bytes, "!" });
    defer a.free(trailing);
    try std.testing.expectError(error.ComponentProtocol, wire.decode(a, trailing, text.len));
    bytes[7] = '2';
    try std.testing.expectError(error.ComponentProtocol, wire.decode(a, bytes, text.len));
    bytes[7] = '1';
    bytes[16] = 255;
    try std.testing.expectError(error.ComponentProtocol, wire.decode(a, bytes, text.len));
}

// spec-case: SELFHOST-PARSER-VALUE-1
test "parser values reject unknown duplicate fields and over-budget tables" {
    const a = std.testing.allocator;
    const bytes = try wire.encode(a, .{ .nodes = .empty, .statements = .empty, .functions = &.{} });
    defer a.free(bytes);
    const field_at = std.mem.lastIndexOf(u8, bytes, "nodes").?;
    @memcpy(bytes[field_at..][0..5], "typez");
    try std.testing.expectError(error.ComponentProtocol, wire.decode(a, bytes, 0));
    @memcpy(bytes[field_at..][0..5], "types");
    try std.testing.expectError(error.ComponentProtocol, wire.decode(a, bytes, 0));
    @memcpy(bytes[field_at..][0..5], "nodes");
    std.mem.writeInt(u32, bytes[8..12], wire.max_values + 1, .little);
    try std.testing.expectError(error.ComponentProtocol, wire.decode(a, bytes, 0));
}

// spec-case: SELFHOST-PARSER-VALUE-1
test "parser values reject mixed expression and statement cycles" {
    var nodes = [_]ast.Node{.{ .span = .{ .start = 0, .end = 1 }, .data = .{ .gather = .{ .shape = .list, .loop = @fromBackingInt(@as(usize, 0)), .open = .{ .start = 0, .end = 1 } } } }};
    var statements = [_]ast.Statement{.{ .span = .{ .start = 0, .end = 1 }, .data = .{ .discard = @fromBackingInt(@as(usize, 0)) } }};
    try malformed(std.testing.allocator, .{ .nodes = .{ .items = &nodes, .capacity = nodes.len }, .statements = .{ .items = &statements, .capacity = statements.len }, .functions = &.{} }, 1);
    try std.testing.expectEqual(@as(usize, 1), statements.len);
}

fn malformed(a: std.mem.Allocator, program: ast.Program, source_len: usize) !void {
    const bytes = try wire.encode(a, program);
    defer a.free(bytes);
    try std.testing.expectError(error.ComponentProtocol, wire.decode(a, bytes, source_len));
}

// spec-case: SELFHOST-PARSER-VALUE-1
test "parser values reject source escapes foreign IDs and expression cycles" {
    var nodes = [_]ast.Node{.{ .span = .{ .start = 0, .end = 1 }, .data = .{ .boolean = true } }};
    const program: ast.Program = .{ .nodes = .{ .items = &nodes, .capacity = nodes.len }, .statements = .empty, .functions = &.{} };
    try malformed(std.testing.allocator, program, 0);
    nodes[0].data = .{ .propagate = @fromBackingInt(@as(usize, 2)) };
    try malformed(std.testing.allocator, program, 1);
    nodes[0].data = .{ .propagate = @fromBackingInt(@as(usize, 0)) };
    try malformed(std.testing.allocator, program, 1);
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
}

fn allocationRoundtrip(a: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const text = "func answer() -> int:\n    return 42\n";
    const bytes = try wire.encode(a, try parse(arena.allocator(), text));
    defer a.free(bytes);
    var decoded = try wire.decode(a, bytes, text.len);
    defer decoded.deinit();
}

// spec-case: SELFHOST-PARSER-VALUE-1
test "parser values decodeTree releases storage on every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationRoundtrip, .{});
    try std.testing.expect(true);
}

// spec-case: SELFHOST-PARSER-VALUE-1
test "parser values retain diagnostic notes recovery order and structured fixes" {
    const a = std.testing.allocator;
    const problems = [_]diagnostic.Diagnostic{
        .{
            .code = "E_SYNTAX",
            .span = .{ .start = 1, .end = 3 },
            .message = "unexpected token",
            .related = .{ .span = .{ .start = 0, .end = 1 }, .message = "use this spelling", .role = .alternative },
            .provenance = .{ .fix = .{ .edit = .{ .span = .{ .start = 1, .end = 3 }, .text = "func" } } },
        },
        .{ .code = "E_EXPRESSION", .span = .{ .start = 3, .end = 3 }, .message = "expected an expression" },
    };
    const bytes = try wire.encodeErrors(a, &problems);
    defer a.free(bytes);
    var decoded = try wire.decodeErrors(a, bytes, 3);
    defer decoded.deinit();
    try std.testing.expectEqual(@as(usize, 2), decoded.report.diagnostics.len);
    try std.testing.expectEqualStrings("func", decoded.report.diagnostics[0].provenance.fix.?.edit.text);
    try std.testing.expectEqual(diagnostic.Role.alternative, decoded.report.diagnostics[0].related.?.role);
    const canonical = try wire.encodeReport(a, decoded.report);
    defer a.free(canonical);
    try std.testing.expectEqualSlices(u8, bytes, canonical);
    try std.testing.expectError(error.ComponentProtocol, wire.decodeErrors(a, bytes, 2));
}
