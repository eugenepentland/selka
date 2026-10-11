//! Pure octet buffer authority, recipe and closed operation regressions.
const std = @import("std");
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const materialize = @import("body_check_materialize.zig");
const buffers = @import("body_check_buffer_validate.zig");
const validate = @import("body_check_validate.zig");
const recipes = @import("body_check_recipe_validate.zig");
const collections = @import("collection_lower.zig");
const buffer_name = @import("nominal_templates.zig").byte_buffer_name;
const Native = @import("type_catalog.zig").Catalog;
const Fixture = struct { input: value.Input, native: Native };
fn fixture(a: std.mem.Allocator, text: []const u8) !Fixture {
    const src = try source.Source.init(a, "buffer.my", text);
    const sink = try a.create(diagnostic.Sink);
    sink.* = .{ .allocator = a };
    const tokens = try @import("lexer.zig").lex(a, src.bytes, sink);
    var parser: @import("parser.zig").Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = sink };
    const syntax = try parser.parse();
    const native = try @import("records.zig").collectWithNames(a, src, syntax, sink, null);
    return .{ .input = .{ .context = .{ .path = src.path, .source = src.bytes, .trusted_intrinsics = false, .entry_required = false }, .program = syntax, .modules = &.{}, .catalog = try materialize.project(a, native) }, .native = native };
}
fn retained(a: std.mem.Allocator) !Fixture {
    var f = try fixture(a, buffer_text);
    const at = f.input.program.functions[0].name;
    _ = try collections.preludeType(&f.native, buffer_name, at);
    _ = try collections.preludeType(&f.native, "bytes", at);
    _ = try collections.listType(&f.native, .i64, at);
    a.free(f.input.catalog.records);
    a.free(f.input.catalog.lists);
    f.input.catalog = try materialize.project(a, f.native);
    return f;
}
fn bufferRecipe(f: Fixture) value.CatalogRecipe {
    return .{ .byte_buffer = .{ .id = @fromBackingInt(typed.Type.record_base + f.input.catalog.base_count), .span = f.input.program.functions[0].name } };
}
const scalar_text = "func buffer_value() -> int:\n    return 7\n";
const buffer_text = "func value(mut buffer: byte_buffer, data: bytes, values: int[]) -> int:\n    return 7\n";
// spec: SELFHOST-BODY-BUFFERS-1
test "body buffers independently materialize first demand with exact schema and site" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var selected = try fixture(a, scalar_text);
    var reference = try fixture(a, scalar_text);
    const recipe = bufferRecipe(selected);
    _ = try recipes.expanded(a, selected.input, &.{recipe});
    _ = try collections.preludeType(&reference.native, buffer_name, recipe.byte_buffer.span);
    try materialize.apply(a, &selected.native, selected.input, &.{recipe});
    try std.testing.expect(try materialize.equalCatalog(a, selected.native.records, reference.native.records));
    const observed = try materialize.added(a, reference.native, reference.input.catalog.base_count);
    try std.testing.expectEqualDeep(recipe, observed[0]);
}
// spec-case: SELFHOST-BODY-BUFFERS-1
test "body buffers authenticate retained identity and block duplicate unavailable and invented recipes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const initial = try retained(a);
    try std.testing.expect(initial.input.catalog.templates.byte_buffer.identity != null);
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, initial.input, &.{bufferRecipe(initial)}));
    var missing = try fixture(a, scalar_text);
    const recipe = bufferRecipe(missing);
    missing.input.catalog.templates.byte_buffer.available = false;
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, missing.input, &.{recipe}));
    missing.input.catalog.templates.byte_buffer.available = true;
    var bad = recipe;
    bad.byte_buffer.span = .{ .start = 1, .end = 2 };
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, missing.input, &.{bad}));
}
// spec-case: SELFHOST-BODY-BUFFERS-1
test "body buffers reject inconsistent authority and snapshot casts outside exact pairs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try retained(arena.allocator());
    const catalog = f.input.catalog;
    const buffer = catalog.templates.byte_buffer.identity.?.id;
    const bytes = catalog.bytes.?.id;
    const list = catalog.lists[0].id;
    try std.testing.expect(buffers.cast(catalog, buffer, list));
    try std.testing.expect(buffers.cast(catalog, bytes, list));
    try std.testing.expect(buffers.cast(catalog, bytes, buffer));
    try std.testing.expect(!buffers.cast(catalog, buffer, bytes));
    try std.testing.expect(!buffers.cast(catalog, buffer, .i64));
    var forged = catalog;
    forged.templates.byte_buffer.identity = null;
    try std.testing.expectError(error.ComponentProtocol, buffers.basis(forged));
    forged = catalog;
    forged.templates.byte_buffer.available = false;
    try std.testing.expectError(error.ComponentProtocol, buffers.basis(forged));
    forged = catalog;
    forged.templates.byte_buffer.identity.?.id = bytes;
    try std.testing.expectError(error.ComponentProtocol, buffers.basis(forged));
}
// spec-case: SELFHOST-BODY-BUFFERS-1
test "body buffers require canonical writable owner and exact closed operands and results" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try retained(arena.allocator());
    const c = f.input.catalog;
    const b = c.templates.byte_buffer.identity.?.id;
    const bytes = c.bytes.?.id;
    try buffers.operation(c, b, .bool, .buffer_append_byte, &.{.i64}, true);
    try buffers.operation(c, b, .bool, .buffer_reserve, &.{.i64}, true);
    try buffers.operation(c, b, .bool, .buffer_append_range, &.{ bytes, .i64, .i64 }, true);
    try buffers.operation(c, b, .u8, .read, &.{.i64}, false);
    try buffers.operation(c, bytes, bytes, .slice, &.{ .i64, .i64 }, false);
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, bytes, .bool, .buffer_append_byte, &.{.i64}, true));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, b, .bool, .buffer_append_byte, &.{.i64}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, b, .unit, .buffer_append_byte, &.{.i64}, true));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, b, .bool, .buffer_append_range, &.{ b, .bool, .i64 }, true));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, b, .unit, .write, &.{ .i64, .u8 }, true));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, b, b, .text_tail, &.{ .i64, .i64 }, false));
}

const GraphFixture = struct { input: value.Input, output: value.Output };
fn graphFixture(a: std.mem.Allocator, text: []const u8) !GraphFixture {
    const f = try fixture(a, text);
    const src = f.native.templates.store.?.context.src;
    var sink: diagnostic.Sink = .{ .allocator = a };
    const program = try @import("sema.zig").checkLibraryProgram(a, src, f.input.program, &sink, null);
    const ranges = try a.alloc(@import("semantic_copy.zig").Range, 1);
    ranges[0] = .{ .nodes = .{ .start = 0, .end = program.nodes.len }, .statements = .{ .start = 0, .end = program.statements.len } };
    const delta = try a.alloc(value.CatalogRecipe, program.records.len - f.input.catalog.base_count);
    for (program.records[f.input.catalog.base_count..], delta) |record, *recipe| {
        const at = try graphSite(f.input, record);
        if (record.collection.kind == .list) {
            recipe.* = .{ .list = .{ .id = record.id, .element = record.shape.buffer.?, .span = at } };
        } else if (std.mem.eql(u8, record.name, buffer_name)) {
            recipe.* = .{ .byte_buffer = .{ .id = record.id, .span = at } };
        } else return error.ComponentProtocol;
    }
    return .{
        .input = f.input,
        .output = .{
            .batch = .{ .nodes = try a.dupe(typed.Node, program.nodes), .statements = program.statements, .functions = program.functions, .ranges = ranges },
            .import_used = &.{},
            .diagnostics = &.{},
            .recipes = delta,
        },
    };
}
fn graphSite(input: value.Input, record: typed.Record) !source.Span {
    const annotation = input.program.functions[0].signature.parameters[0].ty;
    if (record.collection.kind == .list) return annotation;
    if (std.mem.eql(u8, input.context.source[annotation.start..annotation.end], buffer_name)) return annotation;
    for (input.program.nodes.items) |node| {
        if (node.data != .call) continue;
        const name = node.data.call.name;
        if (std.mem.eql(u8, input.context.source[name.start..name.end], buffer_name)) return node.span;
    }
    return error.ComponentProtocol;
}
const graph_text = "func value(mut buffer: byte_buffer) -> int:\n    _ = buffer.append_byte(7)\n    _ = buffer.reserve(9)\n    _ = buffer.append_range(b\"abc\", 0, 2)\n    const snapshot = bytes(buffer)\n    return len(snapshot[0:2])\n";
const text_graph =
    \\func methods(text: str, raw: bytes, mut buffer: byte_buffer, parts: str[], raw_parts: bytes[], buffer_parts: byte_buffer[]) -> Result[str, str]:
    \\    _ = len(parts) + len(raw_parts) + len(buffer_parts)
    \\    _ = buffer.append_byte(65)
    \\    _ = text.encode()
    \\    _ = text.split(",")
    \\    _ = text.split()
    \\    _ = raw.split(b",")
    \\    _ = buffer.split(b",")
    \\    _ = text.startswith("a", 0, 2)
    \\    _ = raw.endswith(b"b", 0)
    \\    return buffer.decode()
    \\
;

// spec-case: SELFHOST-BODY-BUFFERS-1
test "body buffers accept native text conversion split and ranged prefix suffix graphs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try graphFixture(a, text_graph);
    try std.testing.expectEqual(@as(usize, 0), f.output.recipes.len);
    const wire = @import("body_check_protocol.zig");
    const request = try wire.request(a, f.input, @splat(7));
    const bytes = try wire.response(a, .{ .success = f.output }, request.identity);
    var decoded = try wire.reply(a, bytes, request.identity, f.input);
    defer decoded.deinit();
    try std.testing.expectEqual(f.output.batch.nodes.len, decoded.outcome.success.batch.nodes.len);
}

fn retainedList(c: value.Catalog, element: typed.Type) !typed.Type {
    var found: ?typed.Type = null;
    for (c.lists) |entry| {
        if (entry.element == element) found = entry.id;
    }
    return found orelse error.TestUnexpectedResult;
}

// spec-case: SELFHOST-BODY-BUFFERS-1
test "body buffers authenticate exact text method results operands and Result template" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, text_graph);
    const c = f.input.catalog;
    const text = c.string.?.id;
    const bytes = c.bytes.?.id;
    const buffer = c.templates.byte_buffer.identity.?.id;
    var found: ?typed.Type = null;
    for (c.records) |record| {
        const shape = typed.resultShape(record.id, c.records) orelse continue;
        if (shape.ok_type != text or shape.error_type != text) continue;
        try std.testing.expect(found == null);
        found = record.id;
    }
    const result = found orelse return error.TestUnexpectedResult;
    const parts = try retainedList(c, text);
    try buffers.operation(c, text, bytes, .encode, &.{}, false);
    try buffers.operation(c, bytes, result, .decode, &.{}, false);
    try buffers.operation(c, buffer, result, .decode, &.{}, false);
    try buffers.operation(c, text, .bool, .starts_with_range, &.{ text, .u8, .i64 }, false);
    try buffers.operation(c, buffer, .bool, .ends_with, &.{buffer}, false);
    try buffers.operation(c, text, parts, .split, &.{text}, false);
    try buffers.operation(c, text, parts, .split_whitespace, &.{}, false);
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, bytes, bytes, .encode, &.{}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, text, text, .encode, &.{}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, text, result, .decode, &.{}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, bytes, text, .decode, &.{}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, text, .i64, .starts_with, &.{text}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, text, .bool, .starts_with, &.{bytes}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, text, .bool, .ends_with_start, &.{ text, .bool }, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, text, bytes, .split, &.{text}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, text, parts, .split, &.{bytes}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, text, parts, .split_whitespace, &.{text}, false));
    var forged = c;
    forged.templates.result = null;
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(forged, bytes, result, .decode, &.{}, false));
    const records = try a.dupe(typed.Record, c.records);
    forged = c;
    forged.records = records;
    records[result.recordIndex()].contract.requires_handling = false;
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(forged, bytes, result, .decode, &.{}, false));
    records[result.recordIndex()] = c.records[result.recordIndex()];
    records[result.recordIndex()].name = "ForeignResult";
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(forged, bytes, result, .decode, &.{}, false));
}
// spec-case: SELFHOST-BODY-BUFFERS-1
test "body buffers accept full native snapshot slice and mutable parameter graphs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try graphFixture(arena.allocator(), graph_text);
    const wire = @import("body_check_protocol.zig");
    const request = try wire.request(arena.allocator(), f.input, @splat(3));
    const bytes = try wire.response(arena.allocator(), .{ .success = f.output }, request.identity);
    var decoded = try wire.reply(arena.allocator(), bytes, request.identity, f.input);
    defer decoded.deinit();
    try std.testing.expectEqual(f.output.batch.nodes.len, decoded.outcome.success.batch.nodes.len);
}
fn corruptOperation(a: std.mem.Allocator, f: GraphFixture) !void {
    const nodes = try a.dupe(typed.Node, f.output.batch.nodes);
    var output = f.output;
    output.batch.nodes = nodes;
    for (nodes) |*node| {
        if (node.data != .buffer_operation or node.data.buffer_operation.kind != .buffer_append_range) continue;
        node.data.buffer_operation.arguments = &.{ node.data.buffer_operation.arguments[0], node.data.buffer_operation.arguments[0], node.data.buffer_operation.arguments[2] };
        return validate.outcome(a, f.input, .{ .success = output });
    }
    return error.MissingOperation;
}
// spec-case: SELFHOST-BODY-BUFFERS-1
test "body buffers reject forged foreign range operand inside native graph" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try graphFixture(arena.allocator(), graph_text);
    try std.testing.expectError(error.ComponentProtocol, corruptOperation(arena.allocator(), f));
    var absent = f;
    absent.output.batch.nodes = &.{};
    try std.testing.expectError(error.MissingOperation, corruptOperation(arena.allocator(), absent));
}
// spec-case: SELFHOST-BODY-BUFFERS-1
test "body buffers raw alias and user record block builtin availability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alias = try fixture(arena.allocator(), "type byte_buffer = int\nfunc value() -> int:\n    return 7\n");
    const record = try fixture(arena.allocator(), "record byte_buffer:\n    value: int\nfunc value() -> int:\n    return 7\n");
    try std.testing.expect(!alias.input.catalog.templates.byte_buffer.available);
    try std.testing.expect(alias.input.catalog.templates.byte_buffer.identity == null);
    try std.testing.expect(!record.input.catalog.templates.byte_buffer.available);
    try std.testing.expect(record.input.catalog.templates.byte_buffer.identity == null);
}

// spec-case: SELFHOST-BODY-BUFFERS-1
test "body buffers accept native Unicode tail byte slice and octet read lowering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try graphFixture(a, "func value(text: str, data: bytes) -> int:\n    const tail = text[1:]\n    const raw = data[-2:]\n    return len(tail) + len(raw)\n");
    const read = try graphFixture(a, "func value(buffer: byte_buffer) -> int:\n    return int(buffer[0])\n");
    try validate.outcome(a, text.input, .{ .success = text.output });
    try validate.outcome(a, read.input, .{ .success = read.output });
}
fn indexedWrite(a: std.mem.Allocator) ![]const u8 {
    const f = try fixture(a, "func value(mut buffer: byte_buffer):\n    buffer[0] = 7\n");
    var sink: diagnostic.Sink = .{ .allocator = a };
    _ = @import("sema.zig").checkLibraryProgram(a, f.native.templates.store.?.context.src, f.input.program, &sink, null) catch |err| {
        if (err != error.SourceError or sink.items.items.len == 0) return err;
        return sink.items.items[0].code;
    };
    return "accepted";
}
// spec-case: SELFHOST-BODY-BUFFERS-1
test "body buffers preserve native indexed write source rejection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("E_COLLECTION_METHOD", try indexedWrite(arena.allocator()));
}

// spec-case: SELFHOST-BODY-BUFFERS-1
test "body buffers accept native integer list construction and immutable snapshot casts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try graphFixture(a, "func copy(values: int[]) -> bytes:\n    const buffer = byte_buffer(values)\n    return bytes(buffer)\n");
    try validate.outcome(a, f.input, .{ .success = f.output });
}

// spec-case: SELFHOST-BODY-BUFFERS-1
test "body buffers refuse authenticated schema five replies before graph adoption" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try graphFixture(a, graph_text);
    const protocol = @import("body_check_protocol.zig");
    const request = try protocol.request(a, f.input, @splat(4));
    const bytes = try protocol.response(a, .{ .success = f.output }, request.identity);
    bytes[12] = 5;
    try std.testing.expectError(error.ComponentProtocol, protocol.reply(a, bytes, request.identity, f.input));
}

// spec-case: SELFHOST-BODY-BUFFERS-1
test "body pure closure accepts native text iteration ord and scalar rendering graphs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = "func value(text: str) -> int:\n    mut count = 0\n    for ch in text:\n        count += ord(ch)\n    return len(str(count))\n";
    const f = try graphFixture(a, text);
    try validate.outcome(a, f.input, .{ .success = f.output });
    var guards: usize = 0;
    var ords: usize = 0;
    for (f.output.batch.nodes) |node| {
        if (node.data != .buffer_operation) continue;
        if (node.data.buffer_operation.kind == .iteration_check) guards += 1;
        if (node.data.buffer_operation.kind == .text_ord) ords += 1;
    }
    try std.testing.expect(guards != 0 and ords != 0);
}

// spec-case: SELFHOST-BODY-BUFFERS-1
test "body pure closure accepts native octet iteration and source first range comprehension" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = "func value(items: int[]) -> int:\n    const copied = [for x in range(-2, 3) yield x]\n    mut count = len(copied)\n    for octet in b\"abc\":\n        count += octet\n    return count\n";
    const f = try graphFixture(a, text);
    try validate.outcome(a, f.input, .{ .success = f.output });
    var capacities: usize = 0;
    var unsigned_adds: usize = 0;
    for (f.output.batch.nodes) |node| {
        if (node.data == .acquire_buffer and f.output.batch.nodes[@backingInt(node.data.acquire_buffer.capacity)].ty == .u64) capacities += 1;
        if (node.data == .binary and node.ty == .u64) unsigned_adds += 1;
    }
    try std.testing.expect(capacities != 0 and unsigned_adds != 0);
}

// spec-case: SELFHOST-BODY-BUFFERS-1
test "body pure closure rejects foreign text guards ord and rendering operands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const c = (try retained(arena.allocator())).input.catalog;
    const text = c.string.?.id;
    const bytes = c.bytes.?.id;
    const buffer = c.templates.byte_buffer.identity.?.id;
    try buffers.operation(c, text, .unit, .iteration_check, &.{.i64}, false);
    try buffers.operation(c, bytes, .unit, .iteration_check, &.{.i64}, false);
    try buffers.operation(c, text, .i64, .text_ord, &.{}, false);
    try buffers.operation(c, buffer, .unit, .iteration_check, &.{.i64}, true);
    try buffers.operation(c, buffer, .unit, .iteration_check, &.{.i64}, false);
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, text, .unit, .iteration_check, &.{.bool}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, text, .bool, .iteration_check, &.{.i64}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, text, .unit, .iteration_check, &.{}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, bytes, .i64, .text_ord, &.{}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, text, .i64, .text_ord, &.{.i64}, false));
    try std.testing.expect(buffers.cast(c, text, .i64));
    try std.testing.expect(buffers.cast(c, text, .bool));
    try std.testing.expect(buffers.cast(c, text, .unit));
    try std.testing.expect(!buffers.cast(c, text, bytes));
    try std.testing.expect(!buffers.cast(c, text, c.lists[0].id));
}

fn corruptCapacity(a: std.mem.Allocator, f: GraphFixture, ty: typed.Type) !void {
    const nodes = try a.dupe(typed.Node, f.output.batch.nodes);
    var output = f.output;
    output.batch.nodes = nodes;
    for (nodes) |node| {
        if (node.data != .acquire_buffer) continue;
        nodes[@backingInt(node.data.acquire_buffer.capacity)].ty = ty;
        return validate.outcome(a, f.input, .{ .success = output });
    }
    return error.MissingOperation;
}

const iteration_text =
    \\func value(buffer: byte_buffer, foreign: int) -> int:
    \\    mut total = foreign
    \\    for octet in buffer:
    \\        total += octet
    \\    for index, octet in enumerate(buffer):
    \\        total += index + octet
    \\    assert total >= 0
    \\    return total
    \\
;
fn iterationGuards(f: GraphFixture) usize {
    var count: usize = 0;
    for (f.output.batch.nodes) |node| {
        if (node.data == .buffer_operation and node.data.buffer_operation.kind == .iteration_check) count += 1;
    }
    return count;
}
// spec-case: SELFHOST-BODY-BUFFERS-1
test "body buffers accept native readonly byte buffer iteration and enumeration guards" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try graphFixture(a, iteration_text);
    const protocol = @import("body_check_protocol.zig");
    const request = try protocol.request(a, f.input, @splat(7));
    const encoded = try protocol.response(a, .{ .success = f.output }, request.identity);
    var decoded = try protocol.reply(a, encoded, request.identity, f.input);
    defer decoded.deinit();
    try std.testing.expectEqual(@as(usize, 2), iterationGuards(f));
    try std.testing.expectEqualDeep(f.output, decoded.outcome.success);
}
const IterationForgery = enum { result, bound, arity, owner };
fn corruptIteration(a: std.mem.Allocator, f: GraphFixture, attack: IterationForgery) !void {
    const nodes = try a.dupe(typed.Node, f.output.batch.nodes);
    var output = f.output;
    output.batch.nodes = nodes;
    var boolean: ?typed.NodeId = null;
    for (nodes, 0..) |node, i| if (node.ty == .bool) {
        boolean = @fromBackingInt(i);
        break;
    };
    for (nodes) |*node| {
        if (node.data != .buffer_operation or node.data.buffer_operation.kind != .iteration_check) continue;
        switch (attack) {
            .result => node.ty = .bool,
            .bound => node.data.buffer_operation.arguments = try a.dupe(typed.NodeId, &.{boolean orelse return error.MissingOperation}),
            .arity => node.data.buffer_operation.arguments = &.{},
            .owner => node.data.buffer_operation.owner = @fromBackingInt(1),
        }
        return validate.outcome(a, f.input, .{ .success = output });
    }
    return error.MissingOperation;
}
// spec-case: SELFHOST-BODY-BUFFERS-1
test "body buffers reject forged iteration result bound arity and scalar owner" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try graphFixture(a, iteration_text);
    try std.testing.expectError(error.ComponentProtocol, corruptIteration(a, f, .result));
    try std.testing.expectError(error.ComponentProtocol, corruptIteration(a, f, .bound));
    try std.testing.expectError(error.ComponentProtocol, corruptIteration(a, f, .arity));
    try std.testing.expectError(error.ComponentProtocol, corruptIteration(a, f, .owner));
}

// spec-case: SELFHOST-BODY-BUFFERS-1
test "body pure closure rejects noninteger range comprehension capacity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try graphFixture(a, "func value(items: int[]) -> int:\n    return len([for x in range(-2, 3) yield x])\n");
    try std.testing.expectError(error.ComponentProtocol, corruptCapacity(a, f, .bool));
    try std.testing.expectError(error.ComponentProtocol, corruptCapacity(a, f, .u8));
}

fn corruptUnsigned(a: std.mem.Allocator, f: GraphFixture, mixed: bool) !void {
    const nodes = try a.dupe(typed.Node, f.output.batch.nodes);
    var output = f.output;
    output.batch.nodes = nodes;
    for (nodes) |*node| {
        if (node.data != .binary or node.ty != .u64) continue;
        if (mixed) {
            nodes[@backingInt(node.data.binary.right)].ty = .i64;
        } else node.data.binary.op = .mul;
        return validate.outcome(a, f.input, .{ .success = output });
    }
    return error.MissingOperation;
}

// spec-case: SELFHOST-BODY-NUMERIC-1
test "body pure closure accepts unsigned multiplication and rejects mixed capacity arithmetic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try graphFixture(a, "func value(items: int[]) -> int:\n    return len([for x in range(-2, 3) yield x])\n");
    try corruptUnsigned(a, f, false);
    try std.testing.expectError(error.ComponentProtocol, corruptUnsigned(a, f, true));
}

// spec-case: SELFHOST-BODY-BUFFERS-1
test "body pure closure accepts authentic text and octet repetition join graphs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = "func value(octets: bytes[], words: str[]) -> int:\n    const first = b\"a\" * 32\n    const second = 3 * \"é\"\n    return len(first) + len(second)\n";
    const f = try graphFixture(a, text);
    try validate.outcome(a, f.input, .{ .success = f.output });
    var joins: usize = 0;
    for (f.output.batch.nodes) |node| {
        if (node.data == .buffer_operation and node.data.buffer_operation.kind == .join) joins += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), joins);
}

// spec-case: SELFHOST-BODY-BUFFERS-1
test "body pure closure rejects foreign join result element owner and arity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try graphFixture(a, "func value(mut buffer: byte_buffer, octets: bytes[], words: str[]) -> int:\n    return len(b\"a\" * 32)\n");
    const c = try recipes.expanded(a, f.input, f.output.recipes);
    const bytes = c.bytes.?.id;
    const text = c.string.?.id;
    var bytes_list: typed.Type = .unit;
    var text_list: typed.Type = .unit;
    for (c.lists) |entry| {
        if (entry.element == bytes) bytes_list = entry.id;
        if (entry.element == text) text_list = entry.id;
    }
    try buffers.operation(c, bytes, bytes, .join, &.{bytes_list}, false);
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, bytes, text, .join, &.{bytes_list}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, bytes, bytes, .join, &.{text_list}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, bytes, bytes, .join, &.{.i64}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, bytes, bytes, .join, &.{}, false));
    try std.testing.expectError(error.ComponentProtocol, buffers.operation(c, c.templates.byte_buffer.identity.?.id, bytes, .join, &.{bytes_list}, true));
}

// spec-case: SELFHOST-BODY-BUFFERS-1
test "body pure closure admits native augmented repetition first demand operator site" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "func value() -> int:\n    mut text = \"x\"\n    text *= 3\n    return len(text)\n");
    var site: source.Span = undefined;
    var found = false;
    for (f.input.program.statements.items) |statement| {
        if (statement.data == .assignment and statement.data.assignment.op == .mul) {
            site = statement.data.assignment.op_span;
            found = true;
        }
    }
    try std.testing.expect(found);
    const recipe: value.CatalogRecipe = .{ .list = .{ .id = @fromBackingInt(typed.Type.record_base + f.input.catalog.base_count), .element = f.input.catalog.string.?.id, .span = site } };
    _ = try recipes.expanded(a, f.input, &.{recipe});
    var forged = recipe;
    forged.list.span.end -= 1;
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, f.input, &.{forged}));
    var changed = f.input;
    const statements = try a.dupe(@import("ast.zig").Statement, changed.program.statements.items);
    changed.program.statements.items = statements;
    removeRepetitionOperators(statements);
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, changed, &.{recipe}));
}

fn removeRepetitionOperators(statements: []@import("ast.zig").Statement) void {
    for (statements) |*statement| {
        if (statement.data == .assignment and statement.data.assignment.op == .mul) statement.data.assignment.op = .add;
    }
}
