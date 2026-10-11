//! Structural body catalog choices and complete native typed-graph validation.
const std = @import("std");
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
const materialize = @import("body_check_materialize.zig");
const recipes = @import("body_check_recipe_validate.zig");
const validate = @import("body_check_validate.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Native = @import("type_catalog.zig").Catalog;
const Fixture = struct { native: Native, input: value.Input };
fn fixture(a: std.mem.Allocator, input_text: []const u8) !Fixture {
    const src = try source.Source.init(a, "structural.my", input_text);
    const sink = try a.create(diagnostic.Sink);
    sink.* = .{ .allocator = a };
    const tokens = try @import("lexer.zig").lex(a, src.bytes, sink);
    var parser: @import("parser.zig").Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = sink };
    const syntax = try parser.parse();
    const native = try @import("records.zig").collectWithNames(a, src, syntax, sink, null);
    return .{ .native = native, .input = .{ .context = .{ .path = src.path, .source = src.bytes, .trusted_intrinsics = false, .entry_required = false }, .program = syntax, .modules = &.{}, .catalog = try materialize.project(a, native) } };
}
fn next(f: Fixture, offset: usize) typed.Type {
    return @fromBackingInt(typed.Type.record_base + f.input.catalog.base_count + offset);
}
fn tuple(id: typed.Type, elements: []const typed.Type) value.CatalogRecipe {
    return .{ .structural = .{ .tuple = .{ .id = id, .elements = elements } } };
}
const text = "func main() -> int:\n    const left, right = (3, 4)\n    return left + right\n";
// spec: SELFHOST-BODY-STRUCTURAL-1
test "body structural direct tuples and arrays materialize exactly without nominal graph sites" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var selected = try fixture(a, text);
    var reference = try fixture(a, text);
    const at = selected.input.program.nodes.items[0].span;
    const delta = [_]value.CatalogRecipe{
        tuple(next(selected, 0), &.{ .i64, .bool }),
        .{ .structural = .{ .array = .{ .id = next(selected, 1), .element = next(selected, 0), .length = 3, .span = at } } },
    };
    const first = try reference.native.tupleType(&.{ .i64, .bool });
    try std.testing.expect(reference.native.templates.store.?.semantic(first) == null);
    const second = try reference.native.instantiateArray(a, first, 3, at, reference.native.templates.store.?.context.sink);
    try std.testing.expectEqual(next(selected, 1), second);
    try materialize.apply(a, &selected.native, selected.input, &delta);
    try std.testing.expect(try materialize.equalCatalog(a, reference.native.records, selected.native.records));
    try std.testing.expectEqualDeep(&delta, try materialize.added(a, reference.native, reference.input.catalog.base_count));
}
// spec-case: SELFHOST-BODY-STRUCTURAL-1
test "body structural tuple recipes reject arity duplicate order and forward identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, text);
    const first = tuple(next(f, 0), &.{ .i64, .bool });
    _ = try recipes.expanded(a, f.input, &.{first});
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, f.input, &.{tuple(next(f, 0), &.{.i64})}));
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, f.input, &.{tuple(next(f, 0), &(@as([9]typed.Type, @splat(.i64))))}));
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, f.input, &.{ first, tuple(next(f, 1), &.{ .i64, .bool }) }));
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, f.input, &.{tuple(next(f, 1), &.{ .i64, .bool })}));
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, f.input, &.{tuple(next(f, 0), &.{ next(f, 0), .bool })}));
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, f.input, &.{tuple(next(f, 0), &.{ next(f, 1), .bool })}));
    _ = try recipes.expanded(a, f.input, &.{ first, tuple(next(f, 1), &.{ .bool, .i64 }) });
}
// spec-case: SELFHOST-BODY-STRUCTURAL-1
test "body structural retained annotation tuples deduplicate anonymous body demands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a, "func keep(pair: tuple[int, bool]) -> int:\n    return 7\n");
    const before = f.native.records.len;
    const id = try f.native.tupleType(&.{ .i64, .bool });
    try std.testing.expectEqual(before, f.native.records.len);
    try std.testing.expect(f.native.records[id.recordIndex()].declaration.end != 0);
    try validate.input(a, f.input);
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, f.input, &.{tuple(next(f, 0), &.{ .i64, .bool })}));
}
fn nativeOutput(a: std.mem.Allocator, f: Fixture) !value.Output {
    var sink: diagnostic.Sink = .{ .allocator = a };
    const program = try @import("sema.zig").checkLibraryProgram(a, f.native.templates.store.?.context.src, f.input.program, &sink, null);
    var native = f.native;
    native.records = try a.dupe(typed.Record, program.records);
    const ranges = try a.alloc(@import("semantic_copy.zig").Range, 1);
    ranges[0] = .{ .nodes = .{ .start = 0, .end = program.nodes.len }, .statements = .{ .start = 0, .end = program.statements.len } };
    return .{
        .batch = .{ .nodes = try a.dupe(typed.Node, program.nodes), .statements = program.statements, .functions = program.functions, .ranges = ranges },
        .recipes = try materialize.added(a, native, f.input.catalog.base_count),
        .import_used = &.{},
        .diagnostics = &.{},
    };
}
// spec-case: SELFHOST-BODY-STRUCTURAL-1
test "body structural native tuple graph survives framed decoding and rejects wrong fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, text);
    var output = try nativeOutput(a, f);
    const protocol = @import("body_check_protocol.zig");
    const request = try protocol.request(a, f.input, @splat(10));
    const response = try protocol.response(a, .{ .success = output }, request.identity);
    var decoded = try protocol.reply(a, response, request.identity, f.input);
    defer decoded.deinit();
    const nodes = try a.dupe(typed.Node, output.batch.nodes);
    output.batch.nodes = nodes;
    var changed = false;
    for (nodes) |*node| {
        if (node.data != .field) continue;
        node.data.field.index = 8;
        changed = true;
        break;
    }
    try std.testing.expect(changed);
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = output }));
}
// spec-case: SELFHOST-BODY-STRUCTURAL-1
test "body structural fixed arrays check exact lengths replacement and negative indices" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "func main() -> int:\n    mut values: FixedArray[int, 3] = FixedArray[int, 3]([1, 2, 3])\n    mut index = -1\n    values[index] = 7\n    return values[-1]\n");
    var output = try nativeOutput(a, f);
    try validate.outcome(a, f.input, .{ .success = output });
    const nodes = try a.dupe(typed.Node, output.batch.nodes);
    output.batch.nodes = nodes;
    var changed = false;
    for (nodes) |*node| {
        if (node.data != .array or node.data.array.len != 3) continue;
        node.data.array = node.data.array[0..2];
        changed = true;
        break;
    }
    try std.testing.expect(changed);
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = output }));
}
// spec-case: SELFHOST-BODY-STRUCTURAL-1
test "body structural enum tables preserve declared keys and reject from end addressing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a,
        \\enum Status:
        \\    ok
        \\    missing
        \\    failed
        \\
        \\func main() -> int:
        \\    mut values: [Status]int = {Status.failed: 3, Status.ok: 1, Status.missing: 2}
        \\    const snapshot = values
        \\    values[Status.ok] = 5
        \\    return values[Status.ok] + snapshot[Status.missing]
        \\
    );
    var output = try nativeOutput(a, f);
    try validate.input(a, f.input);
    try validate.outcome(a, f.input, .{ .success = output });
    const nodes = try a.dupe(typed.Node, output.batch.nodes);
    output.batch.nodes = nodes;
    var changed = false;
    for (nodes) |*node| {
        if (node.data != .replace) continue;
        node.data.replace.from_end = true;
        changed = true;
        break;
    }
    try std.testing.expect(changed);
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = output }));
}
// spec-case: SELFHOST-BODY-STRUCTURAL-1
test "body structural zero arrays erase pending element obligations exactly like native" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var selected = try fixture(a, text);
    var reference = try fixture(a, text);
    const at = selected.input.program.nodes.items[0].span;
    const result: value.CatalogRecipe = .{ .result = .{ .id = next(selected, 0), .success = .i64, .failure = .bool, .span = at } };
    const empty: value.CatalogRecipe = .{ .structural = .{ .array = .{ .id = next(selected, 1), .element = next(selected, 0), .length = 0, .span = at } } };
    const nonempty: value.CatalogRecipe = .{ .structural = .{ .array = .{ .id = next(selected, 2), .element = next(selected, 0), .length = 1, .span = at } } };
    const element = try @import("nominal_catalog.zig").instantiateLengths(&reference.native, selected.input.catalog.templates.result.?.id, &.{ .i64, .bool }, &.{}, at);
    _ = try reference.native.instantiateArray(a, element, 0, at, reference.native.templates.store.?.context.sink);
    _ = try reference.native.instantiateArray(a, element, 1, at, reference.native.templates.store.?.context.sink);
    try materialize.apply(a, &selected.native, selected.input, &.{ result, empty, nonempty });
    try std.testing.expect(try materialize.equalCatalog(a, reference.native.records, selected.native.records));
    const zero = selected.native.records[next(selected, 1).recordIndex()].contract;
    const one = selected.native.records[next(selected, 2).recordIndex()].contract;
    try std.testing.expect(zero.storable and !zero.requires_handling and !zero.move_only);
    try std.testing.expect(!one.storable and one.requires_handling);
}
// spec-case: SELFHOST-BODY-STRUCTURAL-1
test "body structural tuple chains enforce the existing dependency depth budget" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, text);
    const delta = try a.alloc(value.CatalogRecipe, 256);
    for (delta, 0..) |*item, index| {
        const elements = try a.alloc(typed.Type, 2);
        elements[0] = if (index == 0) .i64 else next(f, index - 1);
        elements[1] = .bool;
        item.* = tuple(next(f, index), elements);
    }
    _ = try recipes.expanded(a, f.input, delta[0..255]);
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, f.input, delta));
}
