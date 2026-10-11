//! Scalar body transport and forged authenticated graph regression tests.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const value = @import("body_check_value.zig");
const protocol = @import("body_check_protocol.zig");
const validate = @import("body_check_validate.zig");
const diagnostic = @import("diagnostic.zig");
const parser = @import("parser.zig");
const lexer = @import("lexer.zig");
const source = @import("source.zig");
const text = "func value() -> int:\n    return 1\n";
const Fixture = struct { input: value.Input, output: value.Output };
fn fixture(a: std.mem.Allocator) !Fixture {
    const src = try source.Source.init(a, "body.my", text);
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try lexer.lex(a, src.bytes, &sink);
    var p: parser.Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = &sink };
    const syntax = try p.parse();
    const nodes = try a.alloc(typed.Node, 1);
    nodes[0] = .{ .ty = .i64, .span = .{ .start = 0, .end = 0 }, .data = .{ .integer = 1 } };
    const statements = try a.alloc(typed.Statement, 1);
    statements[0] = .{ .span = .{ .start = 0, .end = 0 }, .terminates = true, .data = .{ .ret = @fromBackingInt(0) } };
    const functions = try a.alloc(typed.Function, 1);
    functions[0] = .{ .scope = .{ .body = @fromBackingInt(0) }, .id = @fromBackingInt(0), .name = "value", .declaration = syntax.functions[0].name };
    return .{
        .input = .{ .context = .{ .path = src.path, .source = src.bytes, .trusted_intrinsics = false, .entry_required = false }, .program = syntax, .modules = &.{} },
        .output = .{ .batch = .{ .nodes = nodes, .statements = statements, .functions = functions, .ranges = &.{.{ .nodes = .{ .start = 0, .end = 1 }, .statements = .{ .start = 0, .end = 1 } }} }, .import_used = &.{}, .diagnostics = &.{} },
    };
}
fn rejects(a: std.mem.Allocator, input: value.Input, output: value.Output) !void {
    const request = try protocol.request(a, input, @splat(7));
    defer a.free(request.bytes);
    const bytes = try protocol.response(a, .{ .success = output }, request.identity);
    defer a.free(bytes);
    try std.testing.expectError(error.ComponentProtocol, protocol.reply(a, bytes, request.identity, input));
}
// spec: SELFHOST-BODY-CHECK-1
test "body check full scalar batch survives capture and decode ownership" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixture(arena.allocator());
    const request = try protocol.request(std.testing.allocator, f.input, @splat(7));
    defer std.testing.allocator.free(request.bytes);
    const bytes = try protocol.response(std.testing.allocator, .{ .success = f.output }, request.identity);
    defer std.testing.allocator.free(bytes);
    var decoded = try protocol.reply(std.testing.allocator, bytes, request.identity, f.input);
    const clone = try value.cloneBatch(arena.allocator(), decoded.outcome.success.batch);
    decoded.deinit();
    try std.testing.expectEqual(@as(i128, 1), clone.nodes[0].data.integer);
    try std.testing.expectEqualStrings("value", clone.functions[0].name);
    try std.testing.expect(try value.equal(std.testing.allocator, .{ .success = f.output }, .{ .success = f.output }));
}
// spec-case: SELFHOST-BODY-CHECK-1
test "body check rejects authenticated node references outside tables" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixture(arena.allocator());
    const statements = try arena.allocator().dupe(typed.Statement, f.output.batch.statements);
    statements[0].data = .{ .ret = @fromBackingInt(1) };
    var bad = f.output;
    bad.batch.statements = statements;
    try rejects(std.testing.allocator, f.input, bad);
}
// spec-case: SELFHOST-BODY-CHECK-1
test "body check rejects authenticated scalar type corruption and bad source span" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixture(arena.allocator());
    const nodes = try arena.allocator().dupe(typed.Node, f.output.batch.nodes);
    nodes[0].ty = .bool;
    var bad = f.output;
    bad.batch.nodes = nodes;
    try rejects(std.testing.allocator, f.input, bad);
    nodes[0].ty = .i64;
    nodes[0].span.end = text.len + 1;
    try rejects(std.testing.allocator, f.input, bad);
}
// spec-case: SELFHOST-BODY-CHECK-1
test "body check rejects authenticated expression cycles and foreign lexical locals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixture(arena.allocator());
    const nodes = try arena.allocator().dupe(typed.Node, f.output.batch.nodes);
    nodes[0].data = .{ .cast = @fromBackingInt(0) };
    var bad = f.output;
    bad.batch.nodes = nodes;
    try rejects(std.testing.allocator, f.input, bad);
    nodes[0].data = .{ .local = @fromBackingInt(0) };
    try rejects(std.testing.allocator, f.input, bad);
}
// spec-case: SELFHOST-BODY-CHECK-1
test "body check rejects incomplete function batches and altered frame identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixture(arena.allocator());
    var bad = f.output;
    bad.batch.functions = &.{};
    try rejects(std.testing.allocator, f.input, bad);
    const request = try protocol.request(std.testing.allocator, f.input, @splat(7));
    defer std.testing.allocator.free(request.bytes);
    const bytes = try protocol.response(std.testing.allocator, .{ .success = f.output }, request.identity);
    defer std.testing.allocator.free(bytes);
    bytes[24] ^= 1;
    try std.testing.expectError(error.ComponentProtocol, protocol.reply(std.testing.allocator, bytes, request.identity, f.input));
}
// spec-case: SELFHOST-BODY-CHECK-1
test "body check diagnostics retain notes repairs and profile refusals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixture(arena.allocator());
    const original = diagnostic.Diagnostic{
        .code = "E_NAME",
        .span = .{ .start = 0, .end = 1 },
        .message = "unknown name",
        .related = .{ .span = .{ .start = 1, .end = 2 }, .message = "declared here" },
        .provenance = .{ .fix = .{ .edit = .{ .span = .{ .start = 0, .end = 1 }, .text = "x" } } },
    };
    const items = try value.diagnostics(arena.allocator(), &.{original});
    try validate.outcome(std.testing.allocator, f.input, .{ .failure = items });
    var sink: diagnostic.Sink = .{ .allocator = arena.allocator() };
    try value.publish(&sink, items);
    try std.testing.expectEqualStrings("declared here", sink.items.items[0].related.?.message);
    try std.testing.expectEqualStrings("x", sink.items.items[0].provenance.fix.?.edit.text);
    try validate.outcome(std.testing.allocator, f.input, .{ .profile = .{ .code = "P_BODY_PROFILE", .span = .{ .start = 0, .end = 1 }, .message = "unsupported body" } });
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(std.testing.allocator, f.input, .{ .failure = &.{} }));
}

// spec-case: SELFHOST-BODY-CHECK-1
test "body check rejects overlapping ownership ranges and wrong function declarations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixture(arena.allocator());
    var bad = f.output;
    bad.batch.ranges = &.{.{ .nodes = .{ .start = 1, .end = 1 }, .statements = .{ .start = 0, .end = 1 } }};
    try rejects(std.testing.allocator, f.input, bad);
    const functions = try arena.allocator().dupe(typed.Function, f.output.batch.functions);
    functions[0].declaration.end += 1;
    bad = f.output;
    bad.batch.functions = functions;
    try rejects(std.testing.allocator, f.input, bad);
}
// spec-case: SELFHOST-BODY-CHECK-1
test "body check admits exact source limit and rejects first excess" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixture(arena.allocator());
    const bytes = try arena.allocator().alloc(u8, 1048577);
    @memset(bytes, ' ');
    @memcpy(bytes[0..text.len], text);
    var exact = f.input;
    exact.context.source = bytes[0..1048576];
    try validate.input(std.testing.allocator, exact);
    try std.testing.expectEqual(@as(usize, 1048576), exact.context.source.len);
    exact.context.source = bytes;
    try std.testing.expectError(error.ComponentProtocol, validate.input(std.testing.allocator, exact));
}
// spec-case: SELFHOST-BODY-CHECK-1
test "body check rejects success errors and unrecognized profile vocabulary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixture(arena.allocator());
    const native = diagnostic.Diagnostic{ .code = "E_NAME", .span = .{ .start = 0, .end = 1 }, .message = "unknown name" };
    var bad = f.output;
    bad.diagnostics = try value.diagnostics(arena.allocator(), &.{native});
    try rejects(std.testing.allocator, f.input, bad);
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(std.testing.allocator, f.input, .{ .profile = .{ .code = "E_NAME", .span = .{ .start = 0, .end = 1 }, .message = "unsupported body" } }));
}
// spec-case: SELFHOST-BODY-CHECK-1
test "body check canonical equality includes lexical usage and range metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixture(arena.allocator());
    const functions = try arena.allocator().dupe(typed.Function, f.output.batch.functions);
    functions[0].policy.effects = 1;
    var changed = f.output;
    changed.batch.functions = functions;
    try std.testing.expect(!try value.equal(std.testing.allocator, .{ .success = f.output }, .{ .success = changed }));
    changed = f.output;
    changed.batch.ranges = &.{.{ .nodes = .{ .start = 0, .end = 0 }, .statements = .{ .start = 0, .end = 1 } }};
    try std.testing.expect(!try value.equal(std.testing.allocator, .{ .success = f.output }, .{ .success = changed }));
}

// spec-case: SELFHOST-BODY-CHECK-1
test "body check rejects authenticated loop exits without a declaring loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixture(arena.allocator());
    const statements = try arena.allocator().dupe(typed.Statement, f.output.batch.statements);
    statements[0].data = .{ .loop_exit = .{ .target = 37, .continuing = false } };
    var bad = f.output;
    bad.batch.statements = statements;
    try rejects(std.testing.allocator, f.input, bad);
}

fn allocationRoundtrip(a: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const f = try fixture(arena.allocator());
    const request = try protocol.request(a, f.input, @splat(7));
    defer a.free(request.bytes);
    const bytes = try protocol.response(a, .{ .success = f.output }, request.identity);
    defer a.free(bytes);
    var decoded = try protocol.reply(a, bytes, request.identity, f.input);
    defer decoded.deinit();
    const cloned = try value.cloneBatch(arena.allocator(), decoded.outcome.success.batch);
    try std.testing.expectEqual(@as(i128, 1), cloned.nodes[0].data.integer);
}
// spec-case: SELFHOST-BODY-CHECK-1
test "body check allocation failures release partial framing decoded graphs and adopted tables" {
    var stable = std.testing.FailingAllocator.init(std.testing.allocator, .{ .resize_fail_index = 0 });
    try std.testing.checkAllAllocationFailures(stable.allocator(), allocationRoundtrip, .{});
    try std.testing.expect(true);
}
