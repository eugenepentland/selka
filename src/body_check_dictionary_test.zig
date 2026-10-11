//! Canonical dictionary/set/view recipes and hostile typed metadata regressions.
const std = @import("std");
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const materialize = @import("body_check_materialize.zig");
const recipes = @import("body_check_recipe_validate.zig");
const dictionaries = @import("body_check_dictionary_validate.zig");
const validate = @import("body_check_validate.zig");
const Fixture = struct { input: value.Input, native: @import("type_catalog.zig").Catalog };
fn fixture(a: std.mem.Allocator, text: []const u8) !Fixture {
    return fixtureDialect(a, text, false);
}
fn fixtureDialect(a: std.mem.Allocator, text: []const u8, migration: bool) !Fixture {
    const src = try source.Source.init(a, "dictionary.my", text);
    const sink = try a.create(@import("diagnostic.zig").Sink);
    sink.* = .{ .allocator = a };
    const tokens = try @import("lexer.zig").lex(a, src.bytes, sink);
    var parser: @import("parser.zig").Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = sink };
    if (migration) parser.cursor.dialect = .migration;
    const syntax = try parser.parse();
    const native = try @import("records.zig").collectWithNames(a, src, syntax, sink, null);
    return .{ .native = native, .input = .{ .context = .{ .path = src.path, .source = src.bytes, .trusted_intrinsics = false, .entry_required = false }, .program = syntax, .modules = &.{}, .catalog = try materialize.project(a, native) } };
}
const scalar = "func value() -> int:\n    return 7\n";
fn pair(f: Fixture, kind: dictionaries.Kind, ordinal: usize) value.CatalogRecipe {
    const item: value.DictionaryRecipe = .{ .id = @fromBackingInt(typed.Type.record_base + f.input.catalog.base_count + ordinal), .key = .i64, .value = .bool, .span = f.input.program.functions[0].name };
    return .{ .collection = switch (kind) {
        .dict => .{ .dict = item },
        .dict_item => .{ .dict_item = item },
        .dict_keys => .{ .dict_keys = item },
        .dict_values => .{ .dict_values = item },
        .dict_items => .{ .dict_items = item },
        .set => .{ .set = .{ .id = item.id, .element = item.key, .span = item.span } },
    } };
}
// spec: SELFHOST-BODY-DICTIONARIES-1
test "body dictionaries independently materialize ordered mapping view item and snapshot schemas" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var selected = try fixture(a, scalar);
    var reference = try fixture(a, scalar);
    const item = pair(selected, .dict_item, 2);
    const snapshot: value.CatalogRecipe = .{ .list = .{
        .id = @fromBackingInt(@backingInt(item.collection.dict_item.id) + 1),
        .element = item.collection.dict_item.id,
        .span = item.collection.dict_item.span,
    } };
    const delta = [_]value.CatalogRecipe{ pair(selected, .dict, 0), pair(selected, .dict_items, 1), item, snapshot };
    try materialize.apply(a, &selected.native, selected.input, &delta);
    const index = reference.native.templates.store.?.index;
    const nominal = @import("nominal_catalog.zig");
    const site = delta[0].collection.dict.span;
    const mapping = try nominal.instantiateLengths(&reference.native, index.names.get("dict").?, &.{ .i64, .bool }, &.{}, site);
    _ = try @import("dictionary_views.zig").typeOf(&reference.native, mapping, .items, site);
    const element = try @import("dictionary_views.zig").element(&reference.native, mapping, .items, site);
    _ = try @import("collection_lower.zig").listType(&reference.native, element, site);
    try std.testing.expect(try materialize.equalCatalog(a, selected.native.records, reference.native.records));
    const observed = try materialize.added(a, reference.native, reference.input.catalog.base_count);
    try std.testing.expectEqual(delta.len, observed.len);
    for (delta, observed) |expected, actual| try std.testing.expect(std.meta.eql(expected, actual));
}
// spec-case: SELFHOST-BODY-DICTIONARIES-1
test "body dictionaries permit independent item schemas and require prior mappings only for live views" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a, scalar);
    try materialize.apply(a, &f.native, f.input, &.{pair(f, .dict_item, 0)});
    const other = try fixture(a, scalar);
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, other.input, &.{pair(other, .dict_keys, 0)}));
}
// spec-case: SELFHOST-BODY-DICTIONARIES-1
test "body dictionaries reject conflicting recipes forward keys and forged template authorities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, scalar);
    const first = pair(f, .dict, 0);
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, f.input, &.{ first, pair(f, .dict, 1) }));
    var bad = first;
    bad.collection.dict.key = bad.collection.dict.id;
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, f.input, &.{bad}));
    bad = first;
    bad.collection.dict.id = @fromBackingInt(@backingInt(bad.collection.dict.id) + 1);
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, f.input, &.{bad}));
    var input = f.input;
    input.catalog.templates.collections.set = input.catalog.templates.collections.dict;
    try std.testing.expectError(error.ComponentProtocol, validate.input(a, input));
    input = f.input;
    input.catalog.templates.collections.dict = input.catalog.templates.result;
    try std.testing.expectError(error.ComponentProtocol, validate.input(a, input));
    input = f.input;
    input.catalog.templates.collections.dict.?.declaration = first.collection.dict.span;
    try std.testing.expectError(error.ComponentProtocol, validate.input(a, input));
}
// spec-case: SELFHOST-BODY-DICTIONARIES-1
test "body dictionaries reject managed keys and retain distinct set identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a, scalar);
    const list: value.CatalogRecipe = .{ .list = .{ .id = @fromBackingInt(typed.Type.record_base + f.input.catalog.base_count), .element = .i64, .span = f.input.program.functions[0].name } };
    var mapping = pair(f, .dict, 1);
    mapping.collection.dict.key = list.list.id;
    try std.testing.expectError(error.ComponentProtocol, recipes.expanded(a, f.input, &.{ list, mapping }));
    try materialize.apply(a, &f.native, f.input, &.{pair(f, .set, 0)});
    const added = try materialize.added(a, f.native, f.input.catalog.base_count);
    try std.testing.expect(added[0].collection == .set);
    try std.testing.expect(typed.isSet(f.native.records[added[0].collection.set.id.recordIndex()]));
}
// spec-case: SELFHOST-BODY-DICTIONARIES-1
test "body dictionaries reject foreign operation arguments results arities and readonly mutations" {
    const owner: typed.Type = @fromBackingInt(typed.Type.record_base);
    const item: dictionaries.Descriptor = .{ .kind = .dict, .key = .i64, .value = .bool };
    try dictionaries.operation(item, owner, .unit, .write, &.{ .i64, .bool }, true);
    try dictionaries.operation(item, owner, .bool, .get, &.{ .i64, .bool }, false);
    try std.testing.expectError(error.ComponentProtocol, dictionaries.operation(item, owner, .bool, .write, &.{ .i64, .bool }, true));
    try std.testing.expectError(error.ComponentProtocol, dictionaries.operation(item, owner, .unit, .write, &.{ .bool, .bool }, true));
    try std.testing.expectError(error.ComponentProtocol, dictionaries.operation(item, owner, .unit, .write, &.{.i64}, true));
    try std.testing.expectError(error.ComponentProtocol, dictionaries.operation(item, owner, .unit, .write, &.{ .i64, .bool }, false));
    try std.testing.expectError(error.ComponentProtocol, dictionaries.operation(item, owner, owner, .update, &.{owner}, true));
}

fn nativeOutput(a: std.mem.Allocator, f: Fixture) !value.Output {
    const src = f.native.templates.store.?.context.src;
    var sink: @import("diagnostic.zig").Sink = .{ .allocator = a };
    const program = try @import("sema.zig").checkLibraryProgram(a, src, f.input.program, &sink, null);
    const ranges = try a.alloc(@import("semantic_copy.zig").Range, 1);
    ranges[0] = .{ .nodes = .{ .start = 0, .end = program.nodes.len }, .statements = .{ .start = 0, .end = program.statements.len } };
    return .{ .batch = .{ .nodes = try a.dupe(typed.Node, program.nodes), .statements = program.statements, .functions = program.functions, .ranges = ranges }, .import_used = &.{}, .diagnostics = &.{} };
}
// spec-case: SELFHOST-BODY-DICTIONARIES-1
test "body dictionaries accept native set key snapshots and reject foreign result and operands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "func value() -> int:\n    const members: set[int] = {7}\n    const snapshot: int[] = list(members)\n    return snapshot[0]\n");
    const output = try nativeOutput(a, f);
    try validate.outcome(a, f.input, .{ .success = output });
    var found = false;
    for (@constCast(output.batch.nodes)) |*node| {
        if (node.data != .buffer_operation or node.data.buffer_operation.kind != .keys) continue;
        found = true;
        const saved = node.ty;
        node.ty = .bool;
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = output }));
        node.ty = saved;
        const extra = [_]typed.NodeId{@fromBackingInt(0)};
        node.data.buffer_operation.arguments = &extra;
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = output }));
        node.data.buffer_operation.arguments = &.{};
    }
    try std.testing.expect(found);
}
// spec-case: SELFHOST-BODY-DICTIONARIES-1
test "body dictionaries accept native structural optional flow without builtin name authority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixtureDialect(a, "union Maybe:\n    none\n    some: int\nfunc value(item: Maybe) -> int:\n    return item.unwrap_or(7)\n", true);
    const output = try nativeOutput(a, f);
    try validate.outcome(a, f.input, .{ .success = output });
    try std.testing.expect(try wrongOptionalResult(a, f.input, output));
    const malformed = try wrongOptionalPayload(a, f.input);
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, malformed, .{ .success = output }));
}
// spec-case: SELFHOST-BODY-DICTIONARIES-1
test "body dictionaries accept authentic literal mutation and lookup and reject odd initializer rows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "func value() -> int:\n    mut mapping: dict[int, bool] = {7: True}\n    mapping[8] = False\n    if mapping[7]:\n        return 7\n    return 0\n");
    const output = try nativeOutput(a, f);
    try validate.outcome(a, f.input, .{ .success = output });
    try std.testing.expect(try oddInitializer(a, f.input, output));
}

// spec-case: SELFHOST-BODY-DICTIONARIES-1
test "body dictionaries reject incompatible collection item and live view schema roles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, scalar);
    const delta = [_]value.CatalogRecipe{ pair(f, .dict, 0), pair(f, .dict_items, 1), pair(f, .dict_item, 2) };
    var catalog = try recipes.expanded(a, f.input, &delta);
    const rows = try a.dupe(typed.Record, catalog.records);
    catalog.records = rows;
    const first = delta[0].collection.dict.id.recordIndex();
    rows[first].shape.domain = .i64;
    try std.testing.expect(dictionaries.identify(catalog, rows[first].id) == null);
    rows[first].shape.domain = null;
    const view = delta[1].collection.dict_items.id.recordIndex();
    const fields = try a.dupe(typed.Field, rows[view].fields);
    rows[view].fields = fields;
    fields[0].ty = delta[2].collection.dict_item.id;
    try std.testing.expect(dictionaries.identify(catalog, rows[view].id) == null);
    const item = delta[2].collection.dict_item.id.recordIndex();
    rows[item].shape.builtin = .cell;
    try std.testing.expect(dictionaries.identify(catalog, rows[item].id) == null);
    rows[item].shape.builtin = .none;
    rows[item].shape.resource = .filesystem;
    try std.testing.expect(dictionaries.identify(catalog, rows[item].id) == null);
}
// spec-case: SELFHOST-BODY-DICTIONARIES-1
test "body dictionaries refuse schema seven even with exact request correlation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, scalar);
    const protocol = @import("body_check_protocol.zig");
    const request = try protocol.request(a, f.input, @splat(8));
    const output = try nativeOutput(a, f);
    const bytes = try protocol.response(a, .{ .success = output }, request.identity);
    var decoded = try protocol.reply(a, bytes, request.identity, f.input);
    decoded.deinit();
    std.mem.writeInt(u32, bytes[12..16], 7, .little);
    try std.testing.expectError(error.ComponentProtocol, protocol.reply(a, bytes, request.identity, f.input));
}

fn wrongOptionalResult(a: std.mem.Allocator, input: value.Input, output: value.Output) !bool {
    const nodes = @constCast(output.batch.nodes);
    var found = false;
    for (nodes) |*node| if (node.data == .block_value and node.ty == .i64) {
        found = true;
        node.ty = .bool;
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, input, .{ .success = output }));
        node.ty = .i64;
    };
    return found;
}

fn wrongOptionalPayload(a: std.mem.Allocator, input: value.Input) !value.Input {
    var malformed = input;
    const schemas = try a.dupe(typed.Record, malformed.catalog.records);
    malformed.catalog.records = schemas;
    for (schemas) |*record| if (@import("prelude.zig").optionShape(record.id, schemas) != null) {
        record.shape.variants.?.fallible = true;
        try std.testing.expect(@import("prelude.zig").optionShape(record.id, schemas) == null);
        record.shape.variants.?.fallible = false;
        const cases = try a.dupe(typed.Variant, record.shape.variants.?.cases);
        record.shape.variants.?.cases = cases;
        for (cases) |*item| if (item.payload != null) {
            item.payload = .bool;
        };
    };
    return malformed;
}

fn oddInitializer(a: std.mem.Allocator, input: value.Input, output: value.Output) !bool {
    const nodes = @constCast(output.batch.nodes);
    var found = false;
    for (nodes) |*node| if (node.data == .array and node.data.array.len == 2) {
        const saved = node.data.array;
        node.data.array = saved[0..1];
        found = true;
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, input, .{ .success = output }));
        node.data.array = saved;
    };
    return found;
}

// spec-case: SELFHOST-BODY-DICTIONARIES-1
test "body dictionaries preserve contextual octet values and reject foreign value widths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "func value() -> int:\n    mut mapping: dict[str, u8] = {\"a\": 7}\n    mapping[\"b\"] = 8\n    return int(mapping.get(\"a\", 0))\n");
    const output = try nativeOutput(a, f);
    try validate.outcome(a, f.input, .{ .success = output });
    try std.testing.expect(try wrongOctet(a, f.input, output));
}
fn wrongOctet(a: std.mem.Allocator, input: value.Input, output: value.Output) !bool {
    for (@constCast(output.batch.nodes)) |*node| if (node.ty == .u8 and node.data == .integer) {
        node.ty = .i64;
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, input, .{ .success = output }));
        node.ty = .u8;
        return true;
    };
    return false;
}

// spec-case: SELFHOST-BODY-DICTIONARIES-1
test "body dictionaries preserve native signed lengths and reject foreign capacity results" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "func value() -> int:\n    const mapping: dict[int, bool] = {7: True}\n    const members: set[int] = {7, 8}\n    return len(mapping) + len(members)\n");
    const output = try nativeOutput(a, f);
    try validate.outcome(a, f.input, .{ .success = output });
    var checked: usize = 0;
    var native = f.native;
    for (f.input.catalog.records, 0..) |record, index| {
        if (record.collection.kind != .dictionary) continue;
        const owner_type: typed.Type = @fromBackingInt(typed.Type.record_base + index);
        const expected = try @import("collection_lower.zig").operationType(&native, owner_type, .length, f.input.program.functions[0].name);
        try std.testing.expectEqual(typed.Type.i64, expected);
        const descriptor = dictionaries.identify(f.input.catalog, owner_type).?;
        try dictionaries.operation(descriptor, owner_type, expected, .length, &.{}, false);
        try std.testing.expectError(error.ComponentProtocol, dictionaries.operation(descriptor, owner_type, .u64, .length, &.{}, false));
        checked += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), checked);
}

// spec-case: SELFHOST-BODY-DICTIONARIES-1
test "body dictionaries reject unsupported capacities and length operands" {
    const owner: typed.Type = @fromBackingInt(typed.Type.record_base);
    for ([_]dictionaries.Kind{ .dict, .set }) |kind| {
        const descriptor: dictionaries.Descriptor = .{ .kind = kind, .key = .i64, .value = .bool };
        try std.testing.expectError(error.ComponentProtocol, dictionaries.operation(descriptor, owner, .u64, .capacity, &.{}, false));
        try std.testing.expectError(error.ComponentProtocol, dictionaries.operation(descriptor, owner, .i64, .length, &.{.i64}, false));
    }
}

// spec-case: SELFHOST-BODY-DICTIONARIES-1
test "body dictionaries bind set snapshots to canonical matching key list identities" {
    const int_list: typed.Type = @fromBackingInt(typed.Type.record_base);
    const bool_list: typed.Type = @fromBackingInt(typed.Type.record_base + 1);
    const catalog: value.Catalog = .{ .lists = &.{ .{ .id = int_list, .element = .i64 }, .{ .id = bool_list, .element = .bool } } };
    const item: dictionaries.Descriptor = .{ .kind = .set, .key = .i64, .value = .unit };
    try validate.setKeySnapshot(catalog, item, int_list, &.{});
    try std.testing.expectError(error.ComponentProtocol, validate.setKeySnapshot(catalog, item, bool_list, &.{}));
    try std.testing.expectError(error.ComponentProtocol, validate.setKeySnapshot(catalog, item, .i64, &.{}));
    const mapping: dictionaries.Descriptor = .{ .kind = .dict, .key = .i64, .value = .bool };
    try validate.setKeySnapshot(catalog, mapping, int_list, &.{});
}

// spec: SELFHOST-BODY-PRELUDE-KEYS-1
test "body dictionaries accept authentic ordinary prelude key snapshots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const texts = [_][]const u8{
        "func value(mapping: dict[int, bool], items: int[]) -> int:\n    _ = items\n    return sum(mapping)\n",
        "func value(mapping: dict[int, bool], items: int[]) -> int:\n    _ = items\n    return min(mapping)\n",
        "func value(mapping: dict[int, bool], items: int[]) -> int:\n    _ = items\n    return sorted(mapping)[0]\n",
    };
    for (texts) |text| try nativeKeySnapshot(a, text);
    try std.testing.expectEqual(@as(usize, 3), texts.len);
}

fn nativeKeySnapshot(a: std.mem.Allocator, text: []const u8) !void {
    const f = try fixture(a, text);
    const output = try nativeOutput(a, f);
    try validate.outcome(a, f.input, .{ .success = output });
    var found = false;
    for (@constCast(output.batch.nodes)) |*node| {
        if (node.data != .buffer_operation or node.data.buffer_operation.kind != .keys) continue;
        found = true;
        const saved = node.ty;
        node.ty = .bool;
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = output }));
        node.ty = saved;
        node.data.buffer_operation.arguments = &.{@fromBackingInt(0)};
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = output }));
        node.data.buffer_operation.arguments = &.{};
    }
    try std.testing.expect(found);
}

// spec-case: SELFHOST-BODY-PRELUDE-KEYS-1
test "body dictionaries reject foreign prelude key snapshot schemas and view owners" {
    const list: typed.Type = @fromBackingInt(typed.Type.record_base);
    const catalog: value.Catalog = .{ .lists = &.{.{ .id = list, .element = .i64 }} };
    const mapping: dictionaries.Descriptor = .{ .kind = .dict, .key = .i64, .value = .bool };
    const wrong_key: dictionaries.Descriptor = .{ .kind = .dict, .key = .bool, .value = .i64 };
    const view: dictionaries.Descriptor = .{ .kind = .dict_keys, .key = .i64, .value = .bool };
    try validate.setKeySnapshot(catalog, mapping, list, &.{});
    try std.testing.expectError(error.ComponentProtocol, validate.setKeySnapshot(catalog, wrong_key, list, &.{}));
    try std.testing.expectError(error.ComponentProtocol, validate.setKeySnapshot(catalog, view, list, &.{}));
    try std.testing.expectError(error.ComponentProtocol, validate.setKeySnapshot(catalog, mapping, .i64, &.{}));
    try std.testing.expectError(error.ComponentProtocol, validate.setKeySnapshot(catalog, mapping, list, &.{@fromBackingInt(0)}));
}
