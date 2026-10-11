//! Record/schema authority and typed member/place admission regressions.
const std = @import("std");
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const protocol = @import("body_check_protocol.zig");
const validate = @import("body_check_validate.zig");
const materialize = @import("body_check_materialize.zig");
const lists = @import("body_check_list_validate.zig");
const records = @import("body_check_record_validate.zig");
const Fixture = struct { input: value.Input, output: value.Output, native: @import("type_catalog.zig").Catalog };
fn fixture(a: std.mem.Allocator, text: []const u8) !Fixture {
    const src = try source.Source.init(a, "record.my", text);
    const sink = try a.create(diagnostic.Sink);
    sink.* = .{ .allocator = a };
    const tokens = try @import("lexer.zig").lex(a, src.bytes, sink);
    var parser: @import("parser.zig").Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = sink };
    const syntax = try parser.parse();
    const native = try @import("records.zig").collectWithNames(a, src, syntax, sink, null);
    const catalog = try materialize.project(a, native);
    const program = try @import("sema.zig").checkLibraryProgram(a, src, syntax, sink, null);
    const ranges = try a.alloc(@import("semantic_copy.zig").Range, 1);
    ranges[0] = .{ .nodes = .{ .start = 0, .end = program.nodes.len }, .statements = .{ .start = 0, .end = program.statements.len } };
    return .{
        .native = native,
        .input = .{
            .context = .{ .path = src.path, .source = src.bytes, .trusted_intrinsics = false, .entry_required = false },
            .program = syntax,
            .modules = &.{},
            .catalog = catalog,
        },
        .output = .{
            .batch = .{ .nodes = try a.dupe(typed.Node, program.nodes), .statements = program.statements, .functions = program.functions, .ranges = ranges },
            .import_used = &.{},
            .diagnostics = &.{},
        },
    };
}
const record_text = "record Pair:\n    left: int\n    right: bool\nfunc value() -> int:\n    mut pair = Pair(left=7, right=True)\n    pair.left = 9\n    return pair.left\n";
fn check(a: std.mem.Allocator, f: Fixture) !void {
    try validate.input(a, f.input);
    try validate.outcome(a, f.input, .{ .success = f.output });
}
// spec: SELFHOST-BODY-RECORDS-1
test "body records accept complete native construction fields and mutable update graphs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, record_text);
    const request = try protocol.request(a, f.input, @splat(3));
    const bytes = try protocol.response(a, .{ .success = f.output }, request.identity);
    var decoded = try protocol.reply(a, bytes, request.identity, f.input);
    defer decoded.deinit();
    var constructions: usize = 0;
    var updates: usize = 0;
    var fields: usize = 0;
    for (f.output.batch.nodes) |node| {
        switch (node.data) {
            .record => constructions += 1,
            .update => updates += 1,
            .field => fields += 1,
            else => {},
        }
    }
    try std.testing.expect(constructions > 0 and updates > 0 and fields > 0);
}
// spec-case: SELFHOST-BODY-RECORDS-1
test "body records reject missing duplicate mistyped and foreign construction entries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, record_text);
    try check(a, f);
    var found = false;
    for (@constCast(f.output.batch.nodes)) |*node| {
        if (node.data != .record) continue;
        found = true;
        const original = node.*;
        const fields = original.data.record;
        node.data.record = fields[0..1];
        try std.testing.expectError(error.ComponentProtocol, check(a, f));
        node.data.record = &.{ fields[0], fields[0] };
        try std.testing.expectError(error.ComponentProtocol, check(a, f));
        node.data.record = &.{ .{ .index = fields.len, .value = fields[0].value }, fields[1] };
        try std.testing.expectError(error.ComponentProtocol, check(a, f));
        node.data.record = &.{ .{ .index = fields[0].index, .value = fields[1].value }, fields[1] };
        try std.testing.expectError(error.ComponentProtocol, check(a, f));
        node.* = original;
        break;
    }
    try std.testing.expect(found);
}
// spec-case: SELFHOST-BODY-RECORDS-1
test "body records reject wrong field results indices and update identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, record_text);
    try check(a, f);
    var fields: usize = 0;
    var updates: usize = 0;
    for (@constCast(f.output.batch.nodes)) |*node| {
        const original = node.*;
        if (node.data == .field) {
            fields += 1;
            node.ty = .bool;
            try std.testing.expectError(error.ComponentProtocol, check(a, f));
            node.* = original;
            node.data.field.index = 65536;
            try std.testing.expectError(error.ComponentProtocol, check(a, f));
        } else if (node.data == .update) {
            updates += 1;
            node.ty = .i64;
            try std.testing.expectError(error.ComponentProtocol, check(a, f));
            node.* = original;
            node.data.update.fields = &.{ original.data.update.fields[0], original.data.update.fields[0] };
            try std.testing.expectError(error.ComponentProtocol, check(a, f));
        }
        node.* = original;
    }
    try std.testing.expect(fields > 0 and updates > 0);
}
// spec-case: SELFHOST-BODY-RECORDS-1
test "body records preserve exact retained declaration field and default authority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a, record_text);
    const schemas = try a.dupe(typed.Record, f.input.catalog.records);
    f.input.catalog.records = schemas;
    var found = false;
    for (schemas) |*schema| {
        if (!records.ordinary(schema.*)) continue;
        found = true;
        const original = schema.*;
        schema.name = "Foreign";
        try std.testing.expectError(error.ComponentProtocol, validate.input(a, f.input));
        schema.* = original;
        const fields = try a.dupe(typed.Field, original.fields);
        schema.fields = fields;
        fields[0].name = "foreign";
        try std.testing.expectError(error.ComponentProtocol, validate.input(a, f.input));
        fields[0] = original.fields[0];
        fields[0].default_value = 0;
        try std.testing.expectError(error.ComponentProtocol, validate.input(a, f.input));
        schema.* = original;
        schema.id = .i64;
        try std.testing.expectError(error.ComponentProtocol, validate.input(a, f.input));
        schema.* = original;
        break;
    }
    try std.testing.expect(found);
    f.input.catalog.records = schemas[0 .. schemas.len - 1];
    try std.testing.expectError(error.ComponentProtocol, validate.input(a, f.input));
}
// spec-case: SELFHOST-BODY-RECORDS-1
test "body records admit finite record list recursion and reject unsupported member closures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "record Tree:\n    value: int\n    children: Tree[]\nfunc value(tree: Tree) -> int:\n    return tree.value\n");
    try check(a, f);
    try std.testing.expect(f.input.catalog.lists.len > 0);
    const accepted = try records.policy(a, f.input.catalog);
    const ordinary = try ordinaryId(f.input.catalog);
    try std.testing.expect(accepted[ordinary.recordIndex()]);
    const schemas = try a.dupe(typed.Record, f.input.catalog.records);
    var catalog = f.input.catalog;
    catalog.records = schemas;
    const fields = try a.dupe(typed.Field, schemas[ordinary.recordIndex()].fields);
    schemas[ordinary.recordIndex()].fields = fields;
    fields[0].ty = .file;
    const rejected = try records.policy(a, catalog);
    try std.testing.expect(!rejected[ordinary.recordIndex()]);
    for (catalog.lists) |entry| try std.testing.expect(!rejected[entry.id.recordIndex()]);
}
fn capabilityClosure(a: std.mem.Allocator, ty: typed.Type) !bool {
    const f = try fixture(a, "record Tree:\n    value: int\n    children: Tree[]\nfunc value(tree: Tree) -> int:\n    return tree.value\n");
    const id = try ordinaryId(f.input.catalog);
    const schemas = try a.dupe(typed.Record, f.input.catalog.records);
    var catalog = f.input.catalog;
    catalog.records = schemas;
    const fields = try a.dupe(typed.Field, schemas[id.recordIndex()].fields);
    schemas[id.recordIndex()].fields = fields;
    fields[0].ty = ty;
    const accepted = try records.policy(a, catalog);
    try std.testing.expect(accepted[id.recordIndex()]);
    for (catalog.lists) |entry| try std.testing.expect(accepted[entry.id.recordIndex()]);
    return accepted[id.recordIndex()];
}
// spec: SELFHOST-BODY-CAPABILITY-RECORDS-1
test "body records admit filesystem and stream leaves through recursive value closures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try capabilityClosure(arena.allocator(), .filesystem_cap));
    try std.testing.expect(try capabilityClosure(arena.allocator(), .stream_cap));
}
// spec-case: SELFHOST-BODY-CAPABILITY-RECORDS-1
test "body records admit exact capability fields without making them hash keys" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "record Ports:\n    fs: Filesystem\n    out: Stream\nfunc value(fs: Filesystem, out: Stream) -> Ports:\n    return Ports(fs=fs, out=out)\n");
    try check(a, f);
    const id = try ordinaryId(f.input.catalog);
    const accepted = try records.policy(a, f.input.catalog);
    const hashable = try records.hashablePolicy(a, f.input.catalog);
    try std.testing.expect(accepted[id.recordIndex()]);
    try std.testing.expect(!hashable[id.recordIndex()]);
}
// spec-case: SELFHOST-BODY-RECORDS-1
test "body records retain prefix authority while materializing producer selected record lists" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a, record_text);
    const element = try ordinaryId(f.input.catalog);
    const recipe: value.ListRecipe = .{ .id = @fromBackingInt(typed.Type.record_base + f.input.catalog.base_count), .element = element, .span = f.input.program.nodes.items[0].span };
    try lists.recipes(a, f.input, &.{recipe});
    const expanded = try lists.expanded(a, f.input.catalog, &.{recipe});
    try std.testing.expectEqual(f.input.catalog.records.len, expanded.records.len);
    try std.testing.expectEqual(f.input.catalog.base_count + 1, expanded.base_count);
    try lists.catalog(a, expanded);
    try materialize.apply(a, &f.native, f.input, &.{.{ .list = recipe }});
    try std.testing.expectEqual(recipe.id, f.native.records[f.native.records.len - 1].id);
}

// spec-case: SELFHOST-BODY-RECORDS-1
test "body records retain and validate source default initializer identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "record Pair:\n    left: int = 7\n    right: bool = True\nfunc value() -> int:\n    const pair = Pair()\n    return pair.left\n");
    try check(a, f);
    var defaults: usize = 0;
    for (f.input.catalog.records) |schema| {
        if (!records.ordinary(schema)) continue;
        for (schema.fields) |field| {
            try std.testing.expect(field.default_value != null);
            try std.testing.expect(field.default_value.? < f.input.program.nodes.items.len);
            defaults += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), defaults);
}
// spec-case: SELFHOST-BODY-RECORDS-1
test "body records refuse unused invariant callbacks before successful batch publication" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "@invariant(self.left >= 0)\nrecord Unused:\n    left: int\nfunc value() -> int:\n    return 7\n");
    try validate.input(a, f.input);
    try std.testing.expect(f.output.batch.functions.len > f.input.program.functions.len);
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = f.output }));
    try validate.outcome(a, f.input, .{ .profile = .{ .code = "P_BODY_PROFILE", .span = f.input.program.attributes[0].attributes[0].span, .message = "invariant callback closure is outside this profile" } });
}
// spec-case: SELFHOST-BODY-RECORDS-1
test "body records reject changed retained schema before materialization even with no recipes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a, record_text);
    var found = false;
    for (f.native.records) |*schema| {
        if (!records.ordinary(schema.*)) continue;
        found = true;
        schema.contract.public_arguments = !schema.contract.public_arguments;
        break;
    }
    try std.testing.expect(found);
    try std.testing.expectError(error.ComponentProtocol, materialize.apply(a, &f.native, f.input, &.{}));
}
// spec-case: SELFHOST-BODY-RECORDS-1
test "body records reject old schema three replies before graph decoding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, record_text);
    const request = try protocol.request(a, f.input, @splat(3));
    const bytes = try protocol.response(a, .{ .success = f.output }, request.identity);
    std.mem.writeInt(u32, bytes[12..16], 3, .little);
    try std.testing.expectError(error.ComponentProtocol, protocol.reply(a, bytes, request.identity, f.input));
}

// spec-case: SELFHOST-BODY-RECORDS-1
test "body records refuse boxed retained fields even when their declaration is unused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a, "record Unused:\n    left: int\nfunc value() -> int:\n    return 7\n");
    const schemas = try a.dupe(typed.Record, f.input.catalog.records);
    f.input.catalog.records = schemas;
    var found = false;
    for (schemas) |*schema| {
        if (!records.ordinary(schema.*)) continue;
        found = true;
        const fields = try a.dupe(typed.Field, schema.fields);
        fields[0].boxed = true;
        schema.fields = fields;
        break;
    }
    try std.testing.expect(found);
    try validate.input(a, f.input);
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = f.output }));
}

// spec-case: SELFHOST-BODY-RECORDS-1
test "body records reject impossible by value cycles without rejecting list backed recursion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a, record_text);
    const schemas = try a.dupe(typed.Record, f.input.catalog.records);
    f.input.catalog.records = schemas;
    var found = false;
    for (schemas) |*schema| {
        if (!records.ordinary(schema.*)) continue;
        found = true;
        const fields = try a.dupe(typed.Field, schema.fields);
        fields[0].ty = schema.id;
        schema.fields = fields;
        break;
    }
    try std.testing.expect(found);
    try std.testing.expectError(error.ComponentProtocol, validate.input(a, f.input));
}

fn allocationRoundtrip(a: std.mem.Allocator, f: Fixture) !void {
    const projected = try materialize.project(a, f.native);
    defer a.free(projected.records);
    defer a.free(projected.lists);
    const request = try protocol.request(a, f.input, @splat(3));
    defer a.free(request.bytes);
    const bytes = try protocol.response(a, .{ .success = f.output }, request.identity);
    defer a.free(bytes);
    var decoded = try protocol.reply(a, bytes, request.identity, f.input);
    defer decoded.deinit();
    try std.testing.expectEqual(f.output.batch.nodes.len, decoded.outcome.success.batch.nodes.len);
}
// spec-case: SELFHOST-BODY-RECORDS-1
test "body records allocation failures release schema snapshots policy and owned replies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixture(arena.allocator(), record_text);
    var stable = std.testing.FailingAllocator.init(std.testing.allocator, .{ .resize_fail_index = 0 });
    try std.testing.checkAllAllocationFailures(stable.allocator(), allocationRoundtrip, .{f});
    try std.testing.expect(true);
}

fn ordinaryId(catalog: value.Catalog) !typed.Type {
    for (catalog.records) |schema| if (records.ordinary(schema)) return schema.id;
    return error.ComponentProtocol;
}

fn stripContract(f: Fixture, kind: typed.AssertionKind) usize {
    var count: usize = 0;
    for (@constCast(f.output.batch.statements)) |*statement| {
        if (statement.data != .assertion or statement.data.assertion.kind != kind) continue;
        const condition = statement.data.assertion.condition;
        statement.data = .{ .discard = condition };
        count += 1;
    }
    return count;
}
fn contractGuard(a: std.mem.Allocator, text: []const u8, kind: typed.AssertionKind) !void {
    const f = try fixture(a, text);
    try validate.input(a, f.input);
    try std.testing.expect(stripContract(f, kind) > 0);
    var without = f.input;
    without.program.attributes = &.{};
    try validate.outcome(a, without, .{ .success = f.output });
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = f.output }));
    try validate.outcome(a, f.input, .{ .profile = .{
        .code = "P_BODY_PROFILE",
        .span = f.input.program.attributes[0].attributes[0].span,
        .message = "function contract lowering is outside this profile",
    } });
}
// spec-case: SELFHOST-BODY-RECORDS-1
test "body records reject successful batches omitting required function entry contracts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try contractGuard(arena.allocator(), "@requires(True)\nfunc value() -> int:\n    return 7\n", .requires);
}
// spec-case: SELFHOST-BODY-RECORDS-1
test "body records reject successful batches omitting function return postconditions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try contractGuard(arena.allocator(), "@ensures(result == 7)\nfunc value() -> int:\n    return 7\n", .ensures);
}
