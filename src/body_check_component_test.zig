//! Scalar body transport and forged authenticated graph regression tests.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const value = @import("body_check_value.zig");
const protocol = @import("body_check_protocol.zig");
const component = @import("body_check_component.zig");
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
// spec-case: SELFHOST-BODY-CHECK-1
test "body check shadow comparison rejects changed diagnostic text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const original: diagnostic.Diagnostic = .{ .code = "E_NAME", .span = .{ .start = 0, .end = 1 }, .message = "unknown name" };
    var changed = original;
    changed.message = "different name";
    const expected: value.Outcome = .{ .failure = try value.diagnostics(arena.allocator(), &.{original}) };
    const actual: value.Outcome = .{ .failure = try value.diagnostics(arena.allocator(), &.{changed}) };
    try component.compare(std.testing.allocator, expected, expected);
    try std.testing.expectError(error.ComponentShadowMismatch, component.compare(std.testing.allocator, actual, expected));
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

// spec-case: SELFHOST-BODY-CHECK-1
test "body check accepts native assigned mutable parameter origin and rejects foreign identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "parameter.my", "func update(mut value: int) -> int:\n    value = 7\n    return value\n");
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try lexer.lex(a, src.bytes, &sink);
    var p: parser.Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = &sink };
    const syntax = try p.parse();
    const program = try @import("sema.zig").checkLibraryProgram(a, src, syntax, &sink, null);
    const input: value.Input = .{ .context = .{ .path = src.path, .source = src.bytes, .trusted_intrinsics = false, .entry_required = false }, .program = syntax, .modules = &.{} };
    const output: value.Output = .{ .batch = .{
        .nodes = program.nodes,
        .statements = program.statements,
        .functions = program.functions,
        .ranges = &.{.{ .nodes = .{ .start = 0, .end = program.nodes.len }, .statements = .{ .start = 0, .end = program.statements.len } }},
    }, .import_used = &.{}, .diagnostics = &.{} };
    try std.testing.expectEqual(typed.LocalOrigin.local, program.functions[0].scope.locals[0].origin);
    const request = try protocol.request(a, input, @splat(3));
    const response = try protocol.response(a, .{ .success = output }, request.identity);
    var decoded = try protocol.reply(std.testing.allocator, response, request.identity, input);
    defer decoded.deinit();
    var owned = try value.cloneBatch(a, output.batch);
    const functions = try a.dupe(typed.Function, owned.functions);
    const parameters = try a.dupe(typed.Local, functions[0].scope.locals);
    functions[0].scope.locals = parameters;
    owned.functions = functions;
    parameters[0].name = "foreign";
    var bad = output;
    bad.batch = owned;
    try rejects(std.testing.allocator, input, bad);
    parameters[0].name = "value";
    parameters[0].declaration = .{ .start = 0, .end = 1 };
    try rejects(std.testing.allocator, input, bad);
}

// spec-case: SELFHOST-BODY-CHECK-1
test "body check rejects in-range scalar call argument of incompatible type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "call.my", "func take(value: int) -> int:\n    return value\nfunc invoke() -> int:\n    return take(1)\n");
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try lexer.lex(a, src.bytes, &sink);
    var p: parser.Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = &sink };
    const syntax = try p.parse();
    const program = try @import("sema.zig").checkLibraryProgram(a, src, syntax, &sink, null);
    const input: value.Input = .{ .context = .{ .path = src.path, .source = src.bytes, .trusted_intrinsics = false, .entry_required = false }, .program = syntax, .modules = &.{} };
    const nodes = try a.dupe(typed.Node, program.nodes);
    const split = @backingInt(program.functions[0].scope.body) + 1;
    const first_nodes = functionNodeEnd(nodes, syntax.statements.items[@backingInt(syntax.functions[0].body)].span.end);
    const output: value.Output = .{ .batch = .{ .nodes = nodes, .statements = program.statements, .functions = program.functions, .ranges = &.{
        .{ .nodes = .{ .start = 0, .end = first_nodes }, .statements = .{ .start = 0, .end = split } },
        .{ .nodes = .{ .start = first_nodes, .end = nodes.len }, .statements = .{ .start = split, .end = program.statements.len } },
    } }, .import_used = &.{}, .diagnostics = &.{} };
    try validate.outcome(std.testing.allocator, input, .{ .success = output });
    for (nodes) |*node| {
        if (node.data == .integer) {
            node.ty = .bool;
            node.data = .{ .boolean = true };
        }
    }
    try rejects(std.testing.allocator, input, output);
}

fn functionNodeEnd(nodes: []const typed.Node, end: usize) usize {
    var result: usize = 0;
    for (nodes, 0..) |node, index| {
        if (node.span.end <= end) result = index + 1;
    }
    return result;
}

// spec-case: SELFHOST-BODY-CHECK-1
test "body check merges common prebody usage without concealing missing body observations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const projection = @import("body_check_projection.zig");
    const common = [_][]const bool{&.{ true, false }};
    const merged = try projection.mergeUsage(a, &.{&.{ false, true }}, &common);
    try std.testing.expectEqualSlices(bool, &.{ true, true }, merged[0]);
    const missing = try projection.mergeUsage(a, &.{&.{ false, false }}, &common);
    try std.testing.expectEqualSlices(bool, &.{ true, false }, missing[0]);
    const f = try fixture(a);
    var actual = f.output;
    actual.import_used = missing;
    var expected = f.output;
    expected.import_used = merged;
    try std.testing.expect(!try value.equal(a, .{ .success = actual }, .{ .success = expected }));
    try std.testing.expectError(error.ComponentProtocol, projection.mergeUsage(std.testing.allocator, &.{}, &common));
    try std.testing.expectError(error.ComponentProtocol, projection.mergeUsage(std.testing.allocator, &.{&.{false}}, &common));
}

fn managedFixture(a: std.mem.Allocator, text_source: []const u8) !Fixture {
    const src = try source.Source.init(a, "managed.my", text_source);
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try lexer.lex(a, src.bytes, &sink);
    var p: parser.Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = &sink };
    const syntax = try p.parse();
    const program = try @import("sema.zig").checkLibraryProgram(a, src, syntax, &sink, null);
    var catalog: value.Catalog = .{ .base_count = program.records.len };
    for (program.records) |record| {
        if (!record.isCollection()) continue;
        const entry: value.Sequence = .{ .id = record.id, .element = record.shape.buffer.? };
        if (record.collection.kind == .string) catalog.string = entry;
        if (record.collection.kind == .bytes and std.mem.eql(u8, record.name, "bytes")) catalog.bytes = entry;
    }
    const ranges = try a.alloc(@import("semantic_copy.zig").Range, 1);
    ranges[0] = .{ .nodes = .{ .start = 0, .end = program.nodes.len }, .statements = .{ .start = 0, .end = program.statements.len } };
    return .{
        .input = .{ .context = .{ .path = src.path, .source = src.bytes, .trusted_intrinsics = false, .entry_required = false }, .program = syntax, .modules = &.{}, .catalog = catalog },
        .output = .{ .batch = .{ .nodes = program.nodes, .statements = program.statements, .functions = program.functions, .ranges = ranges }, .import_used = &.{}, .diagnostics = &.{} },
    };
}
fn acceptsManaged(a: std.mem.Allocator, f: Fixture) !void {
    const request = try protocol.request(a, f.input, @splat(4));
    defer a.free(request.bytes);
    const response = try protocol.response(a, .{ .success = f.output }, request.identity);
    defer a.free(response);
    var decoded = try protocol.reply(a, response, request.identity, f.input);
    defer decoded.deinit();
    try std.testing.expect(try value.equal(a, .{ .success = f.output }, decoded.outcome));
}
// spec-case: SELFHOST-BODY-CHECK-1
test "body check schema two accepts native Unicode text and byte sequence graphs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = [_][]const u8{
        "func text(value: str) -> str:\n    return value + \"é😀\"\n",
        "func octets(value: bytes) -> bytes:\n    return value + b\"\\x00\\xff\"\n",
        "func count(value: str) -> int:\n    return len(value)\n",
        "func item(value: str) -> str:\n    return value[-1]\n",
        "func item(value: bytes) -> int:\n    return value[0]\n",
        "func order(left: bytes, right: bytes) -> bool:\n    return left < right\n",
    };
    for (cases) |case| {
        const f = try managedFixture(a, case);
        const catalog = f.input.catalog;
        try acceptsManaged(a, f);
        try std.testing.expect(std.meta.eql(catalog, f.input.catalog));
    }
}
// spec-case: SELFHOST-BODY-CHECK-1
test "body check rejects forged managed catalog identities and elements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var f = try fixture(arena.allocator());
    f.input.catalog.base_count = 65536;
    f.input.catalog.string = .{ .id = .i64, .element = .u32 };
    try std.testing.expectError(error.ComponentProtocol, validate.input(std.testing.allocator, f.input));
    f.input.catalog.string = .{ .id = @fromBackingInt(typed.Type.record_base), .element = .u8 };
    try std.testing.expectError(error.ComponentProtocol, validate.input(std.testing.allocator, f.input));
    f.input.catalog.string = .{ .id = @fromBackingInt(typed.Type.record_base), .element = .u32 };
    f.input.catalog.bytes = .{ .id = @fromBackingInt(typed.Type.record_base), .element = .u8 };
    try std.testing.expectError(error.ComponentProtocol, validate.input(std.testing.allocator, f.input));
    f.input.catalog.bytes = .{ .id = @fromBackingInt(typed.Type.record_base + 65536), .element = .u8 };
    try std.testing.expectError(error.ComponentProtocol, validate.input(std.testing.allocator, f.input));
    f.input.catalog.bytes = .{ .id = @fromBackingInt(typed.Type.record_base + 65535), .element = .u8 };
    try validate.input(std.testing.allocator, f.input);
}
fn corruptCodepoint(a: std.mem.Allocator, f: Fixture, number: i128) !void {
    var output = f.output;
    const nodes = try a.dupe(typed.Node, output.batch.nodes);
    for (nodes) |*node| {
        if (node.ty == .u32 and node.data == .integer) {
            node.data.integer = number;
            break;
        }
    }
    output.batch.nodes = nodes;
    try rejects(a, f.input, output);
}
// spec-case: SELFHOST-BODY-CHECK-1
test "body check rejects surrogate and out of range managed text codepoints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try managedFixture(a, "func text() -> str:\n    return \"x\"\n");
    try acceptsManaged(a, f);
    try corruptCodepoint(a, f, 0xd800);
    try corruptCodepoint(a, f, 0x110000);
}
// spec-case: SELFHOST-BODY-CHECK-1
test "body check refuses old schema replies and unavailable sequence identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try managedFixture(a, "func text() -> str:\n    return \"x\"\n");
    const request = try protocol.request(a, f.input, @splat(5));
    const response = try protocol.response(a, .{ .success = f.output }, request.identity);
    std.mem.writeInt(u32, response[12..16], 2, .little);
    try std.testing.expectError(error.ComponentProtocol, protocol.reply(a, response, request.identity, f.input));
    var absent = f.input;
    absent.catalog = .{};
    try rejects(a, absent, f.output);
}

fn corruptManagedIndex(a: std.mem.Allocator, f: Fixture, wrong_type: bool) !void {
    var output = f.output;
    const nodes = try a.dupe(typed.Node, output.batch.nodes);
    for (nodes) |*node| {
        if (node.data != .index) continue;
        if (wrong_type) node.ty = .bool else node.data.index.index = @fromBackingInt(nodes.len);
        break;
    }
    output.batch.nodes = nodes;
    try rejects(a, f.input, output);
}
// spec-case: SELFHOST-BODY-CHECK-1
test "body check rejects managed index result type and out of table operand" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try managedFixture(a, "func item(value: bytes) -> int:\n    return value[0]\n");
    try acceptsManaged(a, f);
    try corruptManagedIndex(a, f, true);
    try corruptManagedIndex(a, f, false);
}
