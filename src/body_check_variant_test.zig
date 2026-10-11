//! Checked variant graph and ordered canonical recipe regressions.
const std = @import("std");
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const materialize = @import("body_check_materialize.zig");
const recipe_validate = @import("body_check_recipe_validate.zig");
const validate = @import("body_check_validate.zig");
const Native = @import("type_catalog.zig").Catalog;
const Fixture = struct { input: value.Input, native: Native };
fn fixture(a: std.mem.Allocator, text: []const u8) !Fixture {
    return fixtureDialect(a, text, false);
}
fn fixtureDialect(a: std.mem.Allocator, text: []const u8, migration: bool) !Fixture {
    const src = try source.Source.init(a, "variant.my", text);
    const sink = try a.create(diagnostic.Sink);
    sink.* = .{ .allocator = a };
    const tokens = try @import("lexer.zig").lex(a, src.bytes, sink);
    var p: @import("parser.zig").Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = sink };
    if (migration) p.cursor.dialect = .migration;
    const syntax = try p.parse();
    const native = try @import("records.zig").collectWithNames(a, src, syntax, sink, null);
    return .{ .input = .{ .context = .{ .path = src.path, .source = src.bytes, .trusted_intrinsics = false, .entry_required = false }, .program = syntax, .modules = &.{}, .catalog = try materialize.project(a, native) }, .native = native };
}
const scalar_text = "func value() -> int:\n    return 7\n";
fn resultRecipe(f: Fixture, ordinal: usize) value.CatalogRecipe {
    return .{ .result = .{ .id = @fromBackingInt(typed.Type.record_base + f.input.catalog.base_count + ordinal), .success = .i64, .failure = .bool, .span = f.input.program.functions[0].name } };
}
fn optionRecipe(f: Fixture, ordinal: usize, element: typed.Type) value.CatalogRecipe {
    return .{ .option = .{ .id = @fromBackingInt(typed.Type.record_base + f.input.catalog.base_count + ordinal), .element = element, .span = f.input.program.functions[0].signature.return_type } };
}
// spec: SELFHOST-BODY-VARIANTS-1
test "body variants materialize exact ordered Result and Option recipes independently" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var selected = try fixture(a, scalar_text);
    var reference = try fixture(a, scalar_text);
    const first = resultRecipe(selected, 0);
    const second = optionRecipe(selected, 1, first.result.id);
    const recipes = [_]value.CatalogRecipe{ first, second };
    _ = try recipe_validate.expanded(a, selected.input, &recipes);
    _ = try @import("nominal_catalog.zig").instantiateLengths(&reference.native, reference.input.catalog.templates.result.?.id, &.{ .i64, .bool }, &.{}, first.result.span);
    _ = try @import("nominal_catalog.zig").instantiateLengths(&reference.native, reference.input.catalog.templates.option.?.id, &.{first.result.id}, &.{}, second.option.span);
    try materialize.apply(a, &selected.native, selected.input, &recipes);
    try std.testing.expect(try materialize.equalCatalog(a, selected.native.records, reference.native.records));
    const observed = try materialize.added(a, reference.native, reference.input.catalog.base_count);
    try std.testing.expectEqualDeep(recipes, observed[0..2].*);
}
// spec-case: SELFHOST-BODY-VARIANTS-1
test "body variants reject forward duplicate unavailable and invented intern-site recipes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, scalar_text);
    const first = resultRecipe(f, 0);
    var duplicate = resultRecipe(f, 1);
    try std.testing.expectError(error.ComponentProtocol, recipe_validate.expanded(a, f.input, &.{ first, duplicate }));
    duplicate.result.failure = .unit;
    duplicate.result.success = duplicate.result.id;
    try std.testing.expectError(error.ComponentProtocol, recipe_validate.expanded(a, f.input, &.{ first, duplicate }));
    var missing = f.input;
    missing.catalog.templates.result = null;
    try std.testing.expectError(error.ComponentProtocol, recipe_validate.expanded(a, missing, &.{first}));
    var bad = first;
    bad.result.span = .{ .start = 1, .end = 2 };
    try std.testing.expectError(error.ComponentProtocol, recipe_validate.expanded(a, f.input, &.{bad}));
    bad.result.id = @fromBackingInt(@backingInt(first.result.id) + 1);
    try std.testing.expectError(error.ComponentProtocol, recipe_validate.expanded(a, f.input, &.{bad}));
}
// spec-case: SELFHOST-BODY-VARIANTS-1
test "body variants reject pending Result-bearing list elements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, scalar_text);
    const first = resultRecipe(f, 0);
    const second: value.CatalogRecipe = .{ .list = .{ .id = @fromBackingInt(@backingInt(first.result.id) + 1), .element = first.result.id, .span = f.input.program.statements.items[0].span } };
    try std.testing.expectError(error.ComponentProtocol, recipe_validate.expanded(a, f.input, &.{ first, second }));
}
fn nativeOutput(a: std.mem.Allocator, f: Fixture) !value.Output {
    const src = try source.Source.init(a, f.input.context.path, f.input.context.source);
    var sink: diagnostic.Sink = .{ .allocator = a };
    const program = try @import("sema.zig").checkLibraryProgram(a, src, f.input.program, &sink, null);
    const ranges = try a.alloc(@import("semantic_copy.zig").Range, 1);
    ranges[0] = .{ .nodes = .{ .start = 0, .end = program.nodes.len }, .statements = .{ .start = 0, .end = program.statements.len } };
    return .{ .batch = .{ .nodes = program.nodes, .statements = program.statements, .functions = program.functions, .ranges = ranges }, .import_used = &.{}, .diagnostics = &.{} };
}

fn parseSite(f: Fixture) source.Span {
    for (f.input.program.nodes.items) |node| {
        if (node.data == .call) {
            const call = node.data.call;
            if (std.mem.eql(u8, f.input.context.source[call.name.start..call.name.end], "parse_int")) return call.owner orelse node.span;
        }
        if (node.data == .method_call) return node.span;
    }
    unreachable;
}
fn parsedOutput(a: std.mem.Allocator, f: Fixture) !value.Output {
    var output = try nativeOutput(a, f);
    for (output.batch.nodes) |node| if (node.data == .buffer_operation and node.data.buffer_operation.kind == .parse_int) {
        if (node.ty.recordIndex() >= f.input.catalog.base_count) {
            const recipes = try a.alloc(value.CatalogRecipe, 1);
            recipes[0] = .{ .option = .{ .id = node.ty, .element = .i64, .span = parseSite(f) } };
            output.recipes = recipes;
        }
        return output;
    };
    try std.testing.expect(false);
    unreachable;
}
const parse_text = "func value(text: str) -> int:\n    match parse_int(text):\n        case Some(number):\n            return number\n        case None:\n            return 0\n";
// spec: SELFHOST-BODY-PARSE-INT-1
test "body integer parsing validates native first-demand Option and retained identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fresh = try fixture(a, parse_text);
    const output = try parsedOutput(a, fresh);
    try std.testing.expectEqual(@as(usize, 1), output.recipes.len);
    try std.testing.expectEqual(typed.Type.i64, output.recipes[0].option.element);
    try validate.outcome(a, fresh.input, .{ .success = output });
    const retained = try fixture(a, "func value(text: str, prior: int?) -> int:\n    _ = prior\n    match parse_int(text):\n        case Some(number):\n            return number\n        case None:\n            return 0\n");
    const existing = try parsedOutput(a, retained);
    try std.testing.expectEqual(@as(usize, 0), existing.recipes.len);
    try validate.outcome(a, retained.input, .{ .success = existing });
}
// spec-case: SELFHOST-BODY-PARSE-INT-1
test "body integer parsing admits byte local owner sites and expression text receivers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try fixture(a, "func value(text: bytes) -> int:\n    match text.parse_int():\n        case Some(number):\n            return number\n        case None:\n            return 0\n");
    const output = try parsedOutput(a, bytes);
    try std.testing.expectEqualStrings("text", bytes.input.context.source[output.recipes[0].option.span.start..output.recipes[0].option.span.end]);
    try validate.outcome(a, bytes.input, .{ .success = output });
    const text = try fixture(a, "func value() -> int:\n    match \"7\".parse_int():\n        case Some(number):\n            return number\n        case None:\n            return 0\n");
    const expression = try parsedOutput(a, text);
    try std.testing.expectEqual(@as(usize, 1), expression.recipes.len);
    try validate.outcome(a, text.input, .{ .success = expression });
}
fn corruptParse(a: std.mem.Allocator, f: Fixture, output: value.Output) !bool {
    var bad = output;
    const nodes = try a.dupe(typed.Node, output.batch.nodes);
    bad.batch.nodes = nodes;
    for (nodes, 0..) |*node, index| if (node.data == .buffer_operation and node.data.buffer_operation.kind == .parse_int) {
        const original = node.*;
        node.ty = .i64;
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = bad }));
        node.* = original;
        node.data.buffer_operation.arguments = try a.dupe(typed.NodeId, &.{@fromBackingInt(index)});
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = bad }));
        node.* = original;
        node.data.buffer_operation.owner = @fromBackingInt(output.batch.functions[0].scope.locals.len);
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = bad }));
        node.* = original;
        const functions = try a.dupe(typed.Function, output.batch.functions);
        const locals = try a.dupe(typed.Local, functions[0].scope.locals);
        functions[0].scope.locals = locals;
        bad.batch.functions = functions;
        locals[@backingInt(node.data.buffer_operation.owner)].ty = .i64;
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = bad }));
        return true;
    };
    return false;
}
// spec-case: SELFHOST-BODY-PARSE-INT-1
test "body integer parsing rejects forged arity result receiver and foreign owners" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, parse_text);
    const output = try parsedOutput(a, f);
    try std.testing.expect(try corruptParse(a, f, output));
}
const match_text = "result Value:\n    ok: int\n    err: bool\nfunc read(value: Value) -> int:\n    match value:\n        case Ok(item):\n            return item\n        case Err(_):\n            return 0\n";
// spec-case: SELFHOST-BODY-VARIANTS-1
test "body variants accept native exhaustive payload matches and reject duplicate tags and foreign slots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, match_text);
    const output = try nativeOutput(a, f);
    try validate.outcome(a, f.input, .{ .success = output });
    try std.testing.expect(try corruptMatch(a, f, output));
}
// spec-case: SELFHOST-BODY-VARIANTS-1
test "body variants reject forged initializer tags and payload operand types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "result Value:\n    ok: int\n    err: bool\nfunc make() -> Value:\n    return Ok(7)\n");
    const output = try nativeOutput(a, f);
    try validate.outcome(a, f.input, .{ .success = output });
    try std.testing.expect(try corruptVariant(a, f, output));
}

fn corruptMatch(a: std.mem.Allocator, f: Fixture, output: value.Output) !bool {
    var bad = output;
    const statements = try a.dupe(typed.Statement, output.batch.statements);
    bad.batch.statements = statements;
    var found = false;
    for (statements) |*statement| if (statement.data == .match) {
        const original = statement.data.match.arms;
        const arms = try a.dupe(typed.MatchArm, original);
        statement.data.match.arms = arms;
        arms[1].tag = arms[0].tag;
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = bad }));
        @memcpy(arms, original);
        for (arms) |*arm| if (arm.slot != null) {
            arm.slot = @fromBackingInt(output.batch.functions[0].scope.locals.len);
            break;
        };
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = bad }));
        found = true;
        break;
    };
    return found;
}

fn corruptVariant(a: std.mem.Allocator, f: Fixture, output: value.Output) !bool {
    var bad = output;
    const nodes = try a.dupe(typed.Node, output.batch.nodes);
    bad.batch.nodes = nodes;
    var found = false;
    for (nodes) |*node| if (node.data == .variant) {
        const tag = node.data.variant.tag;
        node.data.variant.tag = 2;
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = bad }));
        node.data.variant.tag = tag;
        const operand = node.data.variant.value.?;
        nodes[@backingInt(operand)].ty = .bool;
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = bad }));
        found = true;
        break;
    };
    return found;
}

const reordered_text = "result Result[Success, Failure]:\n    err: Failure\n    ok: Success\nunion Option[Element]:\n    some: Element\n    none\nfunc value() -> int:\n    return 7\n";
fn standardBasis(a: std.mem.Allocator) !Fixture {
    var f = try fixtureDialect(a, reordered_text, true);
    // Reproduce retained std_result authority while keeping the focused fixture
    // independent of filesystem project discovery and installed components.
    const state = f.native.templates.store.?;
    state.index.declarations.items[state.index.names.get("Result").?].builtin_name = "Result";
    state.index.declarations.items[state.index.names.get("Option").?].builtin_name = "Option";
    f.input.catalog = try materialize.project(a, f.native);
    const modules = try a.alloc(value.Module, 1);
    modules[0] = .{
        .context = .{ .module = 0, .name = "std_result", .path = "std_result.my", .trusted_intrinsics = false, .is_imported = false, .source = reordered_text[0 .. reordered_text.len - 1] },
        .offset = 0,
        .imports = &.{},
        .symbols = &.{},
        .import_used = &.{},
    };
    f.input.modules = modules;
    return f;
}
// spec-case: SELFHOST-BODY-VARIANTS-1
test "body variants preserve reordered standard template cases in virtual and materialized schemas" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try standardBasis(a);
    const recipes = [_]value.CatalogRecipe{ resultRecipe(f, 0), optionRecipe(f, 1, .i64) };
    const view = try recipe_validate.expanded(a, f.input, &recipes);
    const result = view.records[recipes[0].result.id.recordIndex()].shape.variants.?;
    const option = view.records[recipes[1].option.id.recordIndex()].shape.variants.?;
    try std.testing.expectEqualStrings("err", result.cases[0].name);
    try std.testing.expectEqualStrings("some", option.cases[0].name);
    try materialize.apply(a, &f.native, f.input, &recipes);
    try std.testing.expectEqualStrings("err", f.native.records[recipes[0].result.id.recordIndex()].shape.variants.?.cases[0].name);
    try std.testing.expectEqualStrings("some", f.native.records[recipes[1].option.id.recordIndex()].shape.variants.?.cases[0].name);
}
fn optionChain(a: std.mem.Allocator, f: Fixture, size: usize) ![]const value.CatalogRecipe {
    const recipes = try a.alloc(value.CatalogRecipe, size);
    var element: typed.Type = .i64;
    for (recipes, 0..) |*item, index| {
        item.* = optionRecipe(f, index, element);
        element = item.option.id;
    }
    return recipes;
}
// spec-case: SELFHOST-BODY-VARIANTS-1
test "body variants enforce exact recipe dependency depth and first excess" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, scalar_text);
    const chain = try optionChain(a, f, 256);
    const admitted = try recipe_validate.expanded(a, f.input, chain[0..255]);
    try std.testing.expectEqual(f.input.catalog.base_count + 255, admitted.base_count);
    try std.testing.expectError(error.ComponentProtocol, recipe_validate.expanded(a, f.input, chain));
}

fn corruptPropagation(a: std.mem.Allocator, f: Fixture, output: value.Output) !bool {
    var bad = output;
    const nodes = try a.dupe(typed.Node, output.batch.nodes);
    bad.batch.nodes = nodes;
    for (nodes) |*node| if (node.data == .propagate) {
        const original = node.data.propagate;
        node.data.propagate.output = .i64;
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = bad }));
        node.data.propagate = original;
        node.ty = .bool;
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = bad }));
        return true;
    };
    return false;
}
// spec-case: SELFHOST-BODY-VARIANTS-1
test "body variants accept native checked propagation and reject foreign return and extracted types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "func consume(value: Result[int, bool]) -> int fails bool:\n    return try value\n");
    const output = try nativeOutput(a, f);
    try validate.outcome(a, f.input, .{ .success = output });
    try std.testing.expect(try corruptPropagation(a, f, output));
}
// spec-case: SELFHOST-BODY-VARIANTS-1
test "body variants reject transfer state on scalar locals and out of source ownership spans" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "func consume(value: Result[int, bool]) -> int fails bool:\n    return try value\n");
    var output = try nativeOutput(a, f);
    const functions = try a.dupe(typed.Function, output.batch.functions);
    output.batch.functions = functions;
    const locals = try a.dupe(typed.Local, functions[0].scope.locals);
    functions[0].scope.locals = locals;
    locals[0].ownership.transfer_span = .{ .start = 0, .end = f.input.context.source.len + 1 };
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = output }));
    const scalar = try fixture(a, "func consume(value: int) -> int:\n    return value\n");
    var scalar_output = try nativeOutput(a, scalar);
    const scalar_functions = try a.dupe(typed.Function, scalar_output.batch.functions);
    scalar_output.batch.functions = scalar_functions;
    const scalar_locals = try a.dupe(typed.Local, scalar_functions[0].scope.locals);
    scalar_functions[0].scope.locals = scalar_locals;
    scalar_locals[0].ownership.transfer_available = true;
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, scalar.input, .{ .success = scalar_output }));
}
