//! Canonical list recipe and native representation admission regressions.
const std = @import("std");
const value = @import("body_check_value.zig");
const validate = @import("body_check_list_validate.zig");
const materialize = @import("body_check_materialize.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const diagnostic = @import("diagnostic.zig");
const Native = @import("type_catalog.zig").Catalog;
const Fixture = struct { native: Native, input: value.Input };
const program_text = "func items() -> int:\n    const values = [1, 2]\n    return 0\n";
fn fixture(a: std.mem.Allocator, text: []const u8) !Fixture {
    const src = try source.Source.init(a, "list.my", text);
    const sink = try a.create(diagnostic.Sink);
    sink.* = .{ .allocator = a };
    const tokens = try lexer.lex(a, src.bytes, sink);
    var p: parser.Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = sink };
    const syntax = try p.parse();
    const native = try @import("records.zig").collectWithNames(a, src, syntax, sink, null);
    return .{ .native = native, .input = .{ .context = .{ .path = src.path, .source = src.bytes, .trusted_intrinsics = false, .entry_required = false }, .program = syntax, .modules = &.{}, .catalog = try materialize.project(a, native) } };
}
fn recipe(f: Fixture, ordinal: usize, element: typed.Type) value.ListRecipe {
    var site: source.Span = .{ .start = 0, .end = 0 };
    for (f.input.program.nodes.items) |node| if (node.data == .list_literal) {
        site = node.span;
        break;
    };
    return .{ .id = @fromBackingInt(typed.Type.record_base + f.input.catalog.base_count + ordinal), .element = element, .span = site };
}
// spec: SELFHOST-BODY-LISTS-1
test "body lists independently materialize exact ordered nested recipes and complete schemas" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var selected = try fixture(a, program_text);
    var reference = try fixture(a, program_text);
    const inner = recipe(selected, 0, .i64);
    const outer = recipe(selected, 1, inner.id);
    const recipes = [_]value.CatalogRecipe{ .{ .list = inner }, .{ .list = outer } };
    const first = try @import("collection_lower.zig").listType(&reference.native, .i64, inner.span);
    const second = try @import("collection_lower.zig").listType(&reference.native, first, outer.span);
    try std.testing.expectEqual(inner.id, first);
    try std.testing.expectEqual(outer.id, second);
    try materialize.apply(a, &selected.native, selected.input, &recipes);
    try std.testing.expect(try materialize.equalCatalog(a, reference.native.records, selected.native.records));
    const observed = try materialize.added(a, reference.native, reference.input.catalog.base_count);
    try std.testing.expectEqual(@as(usize, 2), observed.len);
    try std.testing.expectEqualDeep(recipes, observed[0..2].*);
}
// spec-case: SELFHOST-BODY-LISTS-1
test "body lists retain annotated native identities and reject redundant recipes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a, "func keep(items: int[][]) -> int[][]:\n    return items\n");
    try std.testing.expectEqual(@as(usize, 2), f.input.catalog.lists.len);
    try validate.catalog(a, f.input.catalog);
    const existing = f.input.catalog.lists[0];
    const id = try @import("collection_lower.zig").listType(&f.native, existing.element, .{ .start = 0, .end = 0 });
    try std.testing.expectEqual(existing.id, id);
    try std.testing.expectEqual(f.input.catalog.base_count, f.native.records.len);
    var duplicate = recipe(f, 0, existing.element);
    duplicate.span = f.input.program.nodes.items[0].span;
    try std.testing.expectError(error.ComponentProtocol, validate.recipes(a, f.input, &.{duplicate}));
}
// spec-case: SELFHOST-BODY-LISTS-1
test "body lists reject cyclic forward conflicting missing and unlocated deltas" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, program_text);
    const first = recipe(f, 0, .i64);
    var bad = first;
    bad.element = first.id;
    try std.testing.expectError(error.ComponentProtocol, validate.recipes(a, f.input, &.{bad}));
    bad.element = @fromBackingInt(@backingInt(first.id) + 1);
    try std.testing.expectError(error.ComponentProtocol, validate.recipes(a, f.input, &.{bad}));
    bad = recipe(f, 1, .i64);
    try std.testing.expectError(error.ComponentProtocol, validate.recipes(a, f.input, &.{ first, bad }));
    bad.id = @fromBackingInt(@backingInt(first.id) + 2);
    try std.testing.expectError(error.ComponentProtocol, validate.recipes(a, f.input, &.{bad}));
    bad = first;
    bad.span = .{ .start = 1, .end = 2 };
    try std.testing.expectError(error.ComponentProtocol, validate.recipes(a, f.input, &.{bad}));
    var unavailable = f.input;
    unavailable.catalog.list_available = false;
    try std.testing.expectError(error.ComponentProtocol, validate.recipes(a, unavailable, &.{first}));
}
// spec-case: SELFHOST-BODY-LISTS-1
test "body lists validate existing forward dependencies independently of IDs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const outer: typed.Type = @fromBackingInt(typed.Type.record_base);
    const inner: typed.Type = @fromBackingInt(typed.Type.record_base + 1);
    var catalog: value.Catalog = .{ .base_count = 2, .list_available = true, .lists = &.{ .{ .id = outer, .element = inner }, .{ .id = inner, .element = .i64 } } };
    try validate.catalog(a, catalog);
    catalog.lists = &.{ .{ .id = outer, .element = inner }, .{ .id = inner, .element = outer } };
    try std.testing.expectError(error.ComponentProtocol, validate.catalog(a, catalog));
}
// spec-case: SELFHOST-BODY-LISTS-1
test "body lists preserve native unsupported descriptor profile admission" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixture(arena.allocator(), "func keep(items: u32[]) -> int:\n    return 0\n");
    try std.testing.expect(f.input.catalog.list_available);
    try std.testing.expectEqual(@as(usize, 0), f.input.catalog.lists.len);
    try std.testing.expect(f.input.catalog.base_count > 0);
}

// spec-case: SELFHOST-BODY-LISTS-1
test "body lists accept native dynamic literal graphs and reject forged buffer arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, program_text);
    var sink: diagnostic.Sink = .{ .allocator = a };
    const src = f.native.templates.store.?.context.src;
    const program = try @import("sema.zig").checkLibraryProgram(a, src, f.input.program, &sink, null);
    const nodes = try a.dupe(typed.Node, program.nodes);
    const ranges = try a.alloc(@import("semantic_copy.zig").Range, 1);
    ranges[0] = .{ .nodes = .{ .start = 0, .end = nodes.len }, .statements = .{ .start = 0, .end = program.statements.len } };
    const output: value.Output = .{
        .batch = .{ .nodes = nodes, .statements = program.statements, .functions = program.functions, .ranges = ranges },
        .import_used = &.{},
        .diagnostics = &.{},
        .recipes = &.{.{ .list = recipe(f, 0, .i64) }},
    };
    const protocol = @import("body_check_protocol.zig");
    const request = try protocol.request(a, f.input, @splat(6));
    const good = try protocol.response(a, .{ .success = output }, request.identity);
    var decoded = try protocol.reply(a, good, request.identity, f.input);
    defer decoded.deinit();
    for (nodes) |*node| {
        if (node.data == .buffer_operation and node.data.buffer_operation.kind == .append) {
            node.data.buffer_operation.arguments = &.{};
            break;
        }
    }
    const bad = try protocol.response(a, .{ .success = output }, request.identity);
    try std.testing.expectError(error.ComponentProtocol, protocol.reply(a, bad, request.identity, f.input));
}
// spec-case: SELFHOST-BODY-LISTS-1
test "body lists bound logical nesting and exact catalog record counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const entries = try a.alloc(value.Sequence, 256);
    for (entries, 0..) |*item, index| item.* = .{ .id = @fromBackingInt(typed.Type.record_base + index), .element = if (index == 0) .i64 else @fromBackingInt(typed.Type.record_base + index - 1) };
    var catalog: value.Catalog = .{ .base_count = 65536, .lists = entries[0..255], .list_available = true };
    try validate.catalog(a, catalog);
    catalog.lists = entries;
    try std.testing.expectError(error.ComponentProtocol, validate.catalog(a, catalog));
    catalog.lists = &.{};
    catalog.base_count = 65537;
    try std.testing.expectError(error.ComponentProtocol, validate.catalog(a, catalog));
}

// spec-case: SELFHOST-BODY-LISTS-1
test "body lists project sequences only with their retained identity and exact element" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a, program_text);
    const ty = f.input.catalog.string.?.id;
    const original = f.native.records[ty.recordIndex()];
    f.native.records[ty.recordIndex()].id = .i64;
    try std.testing.expectError(error.ComponentProtocol, materialize.project(a, f.native));
    f.native.records[ty.recordIndex()] = original;
    f.native.records[ty.recordIndex()].shape.buffer = .u8;
    const wrong_element = try materialize.project(a, f.native);
    try std.testing.expect(wrong_element.string == null);
    f.native.records[ty.recordIndex()] = original;
    const valid = try materialize.project(a, f.native);
    try std.testing.expectEqual(ty, valid.string.?.id);
}

const BodyFixture = struct { input: value.Input, output: value.Output };
fn nativeBody(a: std.mem.Allocator, text: []const u8) !BodyFixture {
    const f = try fixture(a, text);
    var sink: diagnostic.Sink = .{ .allocator = a };
    const program = try @import("sema.zig").checkLibraryProgram(a, f.native.templates.store.?.context.src, f.input.program, &sink, null);
    const nodes = try a.dupe(typed.Node, program.nodes);
    const ranges = try a.alloc(@import("semantic_copy.zig").Range, 1);
    ranges[0] = .{ .nodes = .{ .start = 0, .end = nodes.len }, .statements = .{ .start = 0, .end = program.statements.len } };
    return .{ .input = f.input, .output = .{ .batch = .{ .nodes = nodes, .statements = program.statements, .functions = program.functions, .ranges = ranges }, .import_used = &.{}, .diagnostics = &.{} } };
}
fn admitted(a: std.mem.Allocator, f: BodyFixture) !void {
    try @import("body_check_validate.zig").outcome(a, f.input, .{ .success = f.output });
}
// spec-case: SELFHOST-BODY-LISTS-1
test "body lists admit native indexed augmentation and reject forged addition results and operands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try nativeBody(a, "func update(mut rows: int[][], other: int[]) -> int:\n    rows[0] += other\n    return 7\n");
    try admitted(a, f);
    var found = false;
    for (@constCast(f.output.batch.nodes)) |*node| {
        if (node.data != .binary or node.data.binary.op != .add or !node.ty.isAggregate()) continue;
        found = true;
        const original = node.*;
        node.ty = .bool;
        try std.testing.expectError(error.ComponentProtocol, admitted(a, f));
        node.* = original;
        var integer: ?typed.NodeId = null;
        for (f.output.batch.nodes, 0..) |candidate, index| {
            if (candidate.ty == .i64 and candidate.data == .integer) {
                integer = @fromBackingInt(index);
                break;
            }
        }
        node.data.binary.right = integer.?;
        try std.testing.expectError(error.ComponentProtocol, admitted(a, f));
        node.* = original;
        node.data.binary.op = .lt;
        try std.testing.expectError(error.ComponentProtocol, admitted(a, f));
        node.* = original;
        break;
    }
    try std.testing.expect(found);
}
// spec-case: SELFHOST-BODY-LISTS-1
test "body lists admit closed native sort and reject keyed arity wrong results and owners" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try nativeBody(a, "func order(mut values: int[], count: int) -> int:\n    values.sort()\n    return count\n");
    try admitted(a, f);
    var found = false;
    for (@constCast(f.output.batch.nodes)) |*node| {
        if (node.data != .buffer_operation or node.data.buffer_operation.kind != .sort) continue;
        found = true;
        const original = node.*;
        node.ty = .i64;
        try std.testing.expectError(error.ComponentProtocol, admitted(a, f));
        node.* = original;
        node.data.buffer_operation.owner = @fromBackingInt(f.output.batch.functions[0].scope.locals.len);
        try std.testing.expectError(error.ComponentProtocol, admitted(a, f));
        node.* = original;
        node.data.buffer_operation.owner = @fromBackingInt(1);
        try std.testing.expectError(error.ComponentProtocol, admitted(a, f));
        node.* = original;
        node.data.buffer_operation.arguments = &.{@fromBackingInt(0)};
        try std.testing.expectError(error.ComponentProtocol, admitted(a, f));
        node.* = original;
        node.data.buffer_operation.kind = .sort_keyed;
        try std.testing.expectError(error.ComponentProtocol, admitted(a, f));
        node.* = original;
        break;
    }
    try std.testing.expect(found);
}
// spec-case: SELFHOST-BODY-LISTS-1
test "body lists refuse sort over nonorderable admitted element schemas" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try nativeBody(a, "func reverse(mut flags: bool[]) -> int:\n    flags.reverse()\n    return 7\n");
    try admitted(a, f);
    var found = false;
    for (@constCast(f.output.batch.nodes)) |*node| {
        if (node.data != .buffer_operation or node.data.buffer_operation.kind != .reverse) continue;
        found = true;
        node.data.buffer_operation.kind = .sort;
        try std.testing.expectError(error.ComponentProtocol, admitted(a, f));
        node.data.buffer_operation.kind = .reverse;
        break;
    }
    try std.testing.expect(found);
}
// spec-case: SELFHOST-BODY-LISTS-1
test "body lists reject wrong indexed write position and element types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try nativeBody(a, "func update(mut values: int[], flag: bool) -> int:\n    values[0] = 7\n    return 7\n");
    try admitted(a, f);
    var flag: ?typed.NodeId = null;
    // The unused parameter has no native read; append a valid local read in its owned interval.
    const nodes = try a.alloc(typed.Node, f.output.batch.nodes.len + 1);
    @memcpy(nodes[0..f.output.batch.nodes.len], f.output.batch.nodes);
    nodes[nodes.len - 1] = .{ .span = f.input.program.functions[0].signature.parameters[1].name, .ty = .bool, .data = .{ .local = @fromBackingInt(1) } };
    flag = @fromBackingInt(nodes.len - 1);
    var forged = f;
    forged.output.batch.nodes = nodes;
    const ranges = try a.dupe(@import("semantic_copy.zig").Range, f.output.batch.ranges);
    ranges[0].nodes.end = nodes.len;
    forged.output.batch.ranges = ranges;
    try admitted(a, forged);
    var found = false;
    for (nodes) |*node| {
        if (node.data != .buffer_operation or node.data.buffer_operation.kind != .write) continue;
        found = true;
        const original = node.data.buffer_operation.arguments;
        node.data.buffer_operation.arguments = &.{ flag.?, original[1] };
        try std.testing.expectError(error.ComponentProtocol, admitted(a, forged));
        node.data.buffer_operation.arguments = &.{ original[0], flag.? };
        try std.testing.expectError(error.ComponentProtocol, admitted(a, forged));
        node.data.buffer_operation.arguments = original;
        break;
    }
    try std.testing.expect(found);
}

// spec-case: SELFHOST-BODY-LISTS-1
test "body lists admit native text and byte element sorting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const strings = try nativeBody(a, "func order(mut values: str[]) -> int:\n    values.sort()\n    return 7\n");
    try admitted(a, strings);
    const bytes = try nativeBody(a, "func order(mut values: bytes[]) -> int:\n    values.sort()\n    return 7\n");
    try admitted(a, bytes);
}
