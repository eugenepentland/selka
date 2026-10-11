//! Authenticated primitive file operations and all-path lexical handle ownership.
const std = @import("std");
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const validate = @import("body_check_validate.zig");
const Fixture = struct { input: value.Input, output: value.Output };
fn fixture(a: std.mem.Allocator, text: []const u8) !Fixture {
    const src = try source.Source.init(a, "entry.my", text);
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try @import("lexer.zig").lex(a, src.bytes, &sink);
    var parser: @import("parser.zig").Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = &sink };
    const syntax = try parser.parse();
    const native = try @import("records.zig").collectWithNames(a, src, syntax, &sink, null);
    const catalog = try @import("body_check_materialize.zig").project(a, native);
    const program = try @import("sema.zig").checkLibraryProgram(a, src, syntax, &sink, null);
    const recipes = try a.alloc(value.CatalogRecipe, program.records.len - catalog.base_count);
    for (program.records[catalog.base_count..], recipes) |record, *recipe| {
        const at = try recipeSite(program.nodes, record.id);
        if (record.isCollection() and record.collection.kind == .list) {
            recipe.* = .{ .list = .{ .id = record.id, .element = record.shape.buffer.?, .span = at } };
        } else if (typed.resultShape(record.id, program.records)) |shape| {
            recipe.* = .{ .result = .{ .id = record.id, .success = shape.ok_type, .failure = shape.error_type, .span = at } };
        } else return error.ComponentProtocol;
    }
    const ranges = try a.alloc(@import("semantic_copy.zig").Range, 1);
    ranges[0] = .{ .nodes = .{ .start = 0, .end = program.nodes.len }, .statements = .{ .start = 0, .end = program.statements.len } };
    return .{
        .input = .{ .context = .{ .path = src.path, .source = src.bytes, .trusted_intrinsics = false, .entry_required = false }, .program = syntax, .modules = &.{}, .catalog = catalog },
        .output = .{ .batch = .{ .nodes = program.nodes, .statements = program.statements, .functions = program.functions, .ranges = ranges }, .import_used = &.{}, .diagnostics = &.{}, .recipes = recipes },
    };
}
fn recipeSite(nodes: []const typed.Node, id: typed.Type) !source.Span {
    for (nodes) |node| switch (node.data) {
        .file_access => |access| {
            if (node.ty == id or access.shapes.list == id) return node.span;
        },
        .file_method => |method| {
            if (node.ty == id or method.shapes.list == id) return node.span;
        },
        else => {},
    };
    return error.TestUnexpectedResult;
}
const scoped = "func value(fs: Filesystem, out: Stream) -> int:\n    with fs.open(\"input.bin\", \"rb\") as input:\n        const data = input.read(8)\n        _ = out.write(data)\n        _ = out.print(len(data))\n    return 7\n";
// spec: SELFHOST-BODY-ENTRY-1
test "body resources accept authentic file scope and exact output forms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixture(arena.allocator(), scoped);
    try validate.input(arena.allocator(), f.input);
    try validate.outcome(arena.allocator(), f.input, .{ .success = f.output });
    try std.testing.expectEqual(@as(usize, 1), f.output.recipes.len);
    try std.testing.expect(f.output.recipes[0] == .list);
}
// spec-case: SELFHOST-BODY-ENTRY-1
test "body resources preserve list before file Result and match owned scopes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = "func value(fs: Filesystem) -> int:\n" ++
        "    match fs.open(\"input.bin\", \"rb\"):\n" ++
        "        case Ok(file):\n            with file as input:\n                _ = input.read()\n" ++
        "            return 7\n        case Err(message):\n            return 0\n";
    const f = try fixture(arena.allocator(), text);
    try validate.outcome(arena.allocator(), f.input, .{ .success = f.output });
    try std.testing.expectEqual(@as(usize, 2), f.output.recipes.len);
    try std.testing.expect(f.output.recipes[0] == .list and f.output.recipes[1] == .result);
    try std.testing.expectEqual(typed.Type.file, f.output.recipes[1].result.success);
    // Native match-arm restoration resets locals created after its snapshot,
    // including a scoped binding initialized earlier inside the successful arm.
    var scoped_locals: usize = 0;
    for (f.output.batch.functions[0].scope.locals) |local| {
        if (!local.ownership.scoped_file) continue;
        try std.testing.expect(!local.ownership.initialized);
        scoped_locals += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), scoped_locals);
}
fn methodIndex(nodes: []const typed.Node) !usize {
    for (nodes, 0..) |node, index| if (node.data == .file_method) return index;
    return error.TestUnexpectedResult;
}
// spec-case: SELFHOST-BODY-ENTRY-1
test "body resources reject valid handle reads outside their enclosing body" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, scoped);
    var forged = f.output;
    const statements = try a.dupe(typed.Statement, forged.batch.statements);
    forged.batch.statements = statements;
    const method: typed.NodeId = @fromBackingInt(try methodIndex(f.output.batch.nodes));
    for (statements) |*statement| {
        if (statement.data != .ret) continue;
        statement.data = .{ .discard = method };
        statement.terminates = false;
        break;
    }
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = forged }));
}
// spec-case: SELFHOST-BODY-ENTRY-1
test "body resources reject forged handle ownership and read operand widths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, scoped);
    var forged = f.output;
    const nodes = try a.dupe(typed.Node, forged.batch.nodes);
    forged.batch.nodes = nodes;
    const index = try methodIndex(nodes);
    const original = nodes[index];
    nodes[index].data.file_method.owner = @fromBackingInt(0);
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = forged }));
    nodes[index] = original;
    nodes[index].ty = .i64;
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = forged }));
    nodes[index] = original;
    const argument = nodes[index].data.file_method.argument.?;
    nodes[@backingInt(argument)].ty = .bool;
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = forged }));
}
// spec-case: SELFHOST-BODY-ENTRY-1
test "body resources refuse old schema six correlated replies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, scoped);
    const protocol = @import("body_check_protocol.zig");
    const request = try protocol.request(a, f.input, @splat(7));
    const bytes = try protocol.response(a, .{ .success = f.output }, request.identity);
    bytes[12] = 6;
    try std.testing.expectError(error.ComponentProtocol, protocol.reply(a, bytes, request.identity, f.input));
}

// spec-case: SELFHOST-BODY-ENTRY-1
test "body resources reject a sibling scope borrowing an authenticated handle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = "func value(fs: Filesystem) -> int:\n    with fs.open(\"first.bin\", \"rb\") as first:\n        _ = first.read()\n    with fs.open(\"second.bin\", \"rb\") as second:\n        _ = second.read()\n    return 7\n";
    const f = try fixture(a, text);
    try validate.outcome(a, f.input, .{ .success = f.output });
    var forged = f.output;
    const nodes = try a.dupe(typed.Node, forged.batch.nodes);
    forged.batch.nodes = nodes;
    var first: ?typed.LocalId = null;
    var changed = false;
    for (nodes) |*node| {
        if (node.data != .file_method) continue;
        if (first) |owner| {
            node.data.file_method.owner = owner;
            changed = true;
            break;
        }
        first = node.data.file_method.owner;
    }
    try std.testing.expect(changed);
    try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = forged }));
}

// spec-case: SELFHOST-BODY-ENTRY-1
test "body resources close file recipes to Result with canonical text failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = "func value(fs: Filesystem) -> int:\n" ++
        "    match fs.open(\"input.bin\", \"rb\"):\n" ++
        "        case Ok(file):\n            with file as input:\n                _ = input.read()\n" ++
        "            return 7\n        case Err(message):\n            return 0\n";
    const f = try fixture(a, text);
    const delta = try a.dupe(value.CatalogRecipe, f.output.recipes);
    const expand = @import("body_check_recipe_validate.zig").expanded;
    delta[1].result.failure = .bool;
    try std.testing.expectError(error.ComponentProtocol, expand(a, f.input, delta));
    delta[1] = .{ .option = .{ .id = f.output.recipes[1].result.id, .element = .file, .span = f.output.recipes[1].result.span } };
    try std.testing.expectError(error.ComponentProtocol, expand(a, f.input, delta));
    delta[1] = .{ .list = .{ .id = f.output.recipes[1].result.id, .element = .filesystem_cap, .span = f.output.recipes[1].result.span } };
    try std.testing.expectError(error.ComponentProtocol, expand(a, f.input, delta));
}

// spec-case: SELFHOST-BODY-ENTRY-1
test "body resources bind open mode and text metadata to literal operands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, scoped);
    var forged = f.output;
    const nodes = try a.dupe(typed.Node, forged.batch.nodes);
    forged.batch.nodes = nodes;
    for (nodes) |*node| {
        if (node.data != .file_access) continue;
        const original = node.*;
        node.data.file_access.mode = 'w';
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = forged }));
        node.* = original;
        node.data.file_access.text = true;
        try std.testing.expectError(error.ComponentProtocol, validate.outcome(a, f.input, .{ .success = forged }));
        return;
    }
    return error.TestUnexpectedResult;
}

// spec-case: SELFHOST-BODY-ENTRY-1
test "body resources retain nested file cleanup scopes around early byte returns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = "func read(fs: Filesystem) -> bytes:\n" ++
        "    with fs.open(\"first.bin\", \"rb\") as first:\n" ++
        "        with fs.open(\"second.bin\", \"rb\") as second:\n" ++
        "            _ = first.read(1)\n            return second.read(8)\n";
    const f = try fixture(a, text);
    try validate.outcome(a, f.input, .{ .success = f.output });
    try std.testing.expectEqual(@as(usize, 2), try terminatingScopes(f.output.batch.statements));
}
fn terminatingScopes(statements: []const typed.Statement) !usize {
    var scopes: usize = 0;
    for (statements) |statement| if (statement.data == .with_scope) {
        try std.testing.expect(statement.terminates);
        scopes += 1;
    };
    return scopes;
}

// spec-case: SELFHOST-BODY-ENTRY-1
test "body resources bind raw scopes to their owning function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, scoped);
    var request = f.input;
    const other = "func other(fs: Filesystem) -> int:\n    with fs.open(\"other.bin\", \"rb\") as foreign:\n        _ = foreign.read()\n    return 0\n";
    const text = try std.mem.concat(a, u8, &.{ scoped, other });
    const src = try source.Source.init(a, "entry.my", text);
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try @import("lexer.zig").lex(a, src.bytes, &sink);
    var parser: @import("parser.zig").Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = &sink };
    request.program = try parser.parse();
    request.context.source = text;
    const scopes = @import("body_check_resource_scope.zig");
    try scopes.batch(a, request, f.output.batch);
    const foreign = try foreignScope(request, scoped.len);
    var forged = f.output.batch;
    const nodes = try a.dupe(typed.Node, forged.nodes);
    const statements = try a.dupe(typed.Statement, forged.statements);
    const functions = try a.dupe(typed.Function, forged.functions);
    const locals = try a.dupe(typed.Local, functions[0].scope.locals);
    functions[0].scope.locals = locals;
    forged.nodes = nodes;
    forged.statements = statements;
    forged.functions = functions;
    try replaceScope(request, foreign, .{ .nodes = nodes, .statements = statements, .locals = locals });
    try std.testing.expectError(error.ComponentProtocol, scopes.batch(a, request, forged));
}
const Replacements = struct { nodes: []typed.Node, statements: []typed.Statement, locals: []typed.Local };
fn foreignScope(request: value.Input, first_end: usize) !@import("ast.zig").Statement {
    for (request.program.statements.items) |statement| {
        if (statement.data == .with_scope and statement.span.start >= first_end) return statement;
    }
    return error.TestUnexpectedResult;
}
fn replaceScope(request: value.Input, foreign: @import("ast.zig").Statement, rows: Replacements) !void {
    for (rows.statements) |*statement| {
        if (statement.data != .with_scope) continue;
        statement.span = foreign.span;
        const local = &rows.locals[@backingInt(statement.data.with_scope.slot)];
        local.declaration = foreign.data.with_scope.name.?;
        local.name = request.context.source[local.declaration.start..local.declaration.end];
        const raw = request.program.nodes.items[@backingInt(foreign.data.with_scope.resource.?)];
        rows.nodes[@backingInt(statement.data.with_scope.resource.?)].span = raw.span;
        return;
    }
    return error.TestUnexpectedResult;
}

// spec-case: SELFHOST-BODY-ENTRY-1
test "body resources rawBindings rejects raw bodies shared by foreign functions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, scoped);
    var request = f.input;
    request.program.functions = try a.dupe(@import("ast.zig").Function, &.{ request.program.functions[0], request.program.functions[0] });
    try std.testing.expectError(error.ComponentProtocol, @import("body_check_resource_scope.zig").batch(a, request, f.output.batch));
}

// spec: SELFHOST-BODY-FILESYSTEM-1
test "body resources accept all authentic text and binary open modes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "r", "rt", "rb", "w", "wt", "wb", "a", "at", "ab" }) |mode| {
        const text = try std.fmt.allocPrint(a, "func value(fs: Filesystem) -> int:\n    with fs.open(\"input.bin\", \"{s}\") as input:\n        _ = input.read(1)\n    return 7\n", .{mode});
        const f = try fixture(a, text);
        try validate.outcome(a, f.input, .{ .success = f.output });
        try std.testing.expectEqual(@as(usize, 1), f.output.recipes.len);
    }
}

fn printIndex(nodes: []const typed.Node) !usize {
    for (nodes, 0..) |node, index| if (node.data == .print) return index;
    return error.TestUnexpectedResult;
}

fn changedPrintContract(a: std.mem.Allocator, f: Fixture, schema: typed.Record) !void {
    const item = f.output.batch.nodes[try printIndex(f.output.batch.nodes)];
    const records = try a.dupe(typed.Record, f.input.catalog.records);
    records[schema.id.recordIndex()] = schema;
    var catalog = f.input.catalog;
    catalog.records = records;
    try @import("body_check_resource_validate.zig").node(catalog, f.output.batch.nodes, f.output.batch.functions[0].scope.locals, item);
}

// spec: SELFHOST-BODY-PRINT-1
test "body resources accept native aggregate print graphs without changing renderer authority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const collections = try fixture(a, "func value(out: Stream, items: int[], mapping: dict[int, str], keys: set[int]) -> Unit:\n" ++
        "    out.print(items, mapping, keys)\n");
    const structural = try fixture(a, "func value(out: Stream, fixed: FixedArray[int, 2], pair: tuple[int, str]) -> Unit:\n" ++
        "    out.print(fixed, pair)\n");
    const nominal = try fixture(a, "record Item:\n    count: int\n    values: int[]\n\n" ++
        "func value(out: Stream, item: Item, maybe: int?, number: float) -> Unit:\n" ++
        "    out.print(item, maybe, number)\n");
    try validate.outcome(a, collections.input, .{ .success = collections.output });
    try validate.outcome(a, structural.input, .{ .success = structural.output });
    try validate.outcome(a, nominal.input, .{ .success = nominal.output });
    try std.testing.expectEqual(@as(usize, 3), collections.output.batch.nodes[try printIndex(collections.output.batch.nodes)].data.print.arguments.len);
    try std.testing.expectEqual(@as(usize, 2), structural.output.batch.nodes[try printIndex(structural.output.batch.nodes)].data.print.arguments.len);
    try std.testing.expectEqual(@as(usize, 3), nominal.output.batch.nodes[try printIndex(nominal.output.batch.nodes)].data.print.arguments.len);
}

// spec-case: SELFHOST-BODY-PRINT-1
test "body resources refuse nonrenderable aggregate print contracts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "record Item:\n    count: int\n\nfunc value(out: Stream, item: Item) -> Unit:\n    out.print(item)\n");
    const item = f.output.batch.nodes[try printIndex(f.output.batch.nodes)];
    const ty = f.output.batch.nodes[@backingInt(item.data.print.arguments[0])].ty;
    const original = f.input.catalog.records[ty.recordIndex()];
    var schema = original;
    schema.contract.move_only = true;
    try std.testing.expectError(error.ComponentProtocol, changedPrintContract(a, f, schema));
    schema = original;
    schema.shape.resource = .filesystem;
    try std.testing.expectError(error.ComponentProtocol, changedPrintContract(a, f, schema));
    schema = original;
    schema.contract.callback = .{ .parameters = &.{}, .return_type = .unit, .effects = 0 };
    try std.testing.expectError(error.ComponentProtocol, changedPrintContract(a, f, schema));
    schema = original;
    schema.managed = true;
    schema.shape.builtin = .cell;
    try std.testing.expectError(error.ComponentProtocol, changedPrintContract(a, f, schema));
    schema = original;
    schema.collection.contains_cell = true;
    try std.testing.expectError(error.ComponentProtocol, changedPrintContract(a, f, schema));
}

fn accessForms(a: std.mem.Allocator, name: []const u8, arguments: []const u8) !usize {
    const text = try std.fmt.allocPrint(a, "func value(fs: Filesystem) -> int:\n    _ = fs.{s}({s})\n    _ = {s}(fs, {s})\n    return 7\n", .{ name, arguments, name, arguments });
    const f = try fixture(a, text);
    try validate.outcome(a, f.input, .{ .success = f.output });
    try std.testing.expect(f.output.recipes.len >= 1);
    var count: usize = 0;
    for (f.output.batch.nodes) |item| if (item.data == .file_access) {
        count += 1;
    };
    return count;
}
// spec-case: SELFHOST-BODY-FILESYSTEM-1
test "body resources accept native whole path helpers in both spellings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(usize, 2), try accessForms(a, "read_file", "\"path\""));
    try std.testing.expectEqual(@as(usize, 2), try accessForms(a, "read_text", "\"path\""));
    try std.testing.expectEqual(@as(usize, 2), try accessForms(a, "write_file", "\"path\", b\"data\""));
    try std.testing.expectEqual(@as(usize, 2), try accessForms(a, "write_text", "\"path\", \"data\""));
    try std.testing.expectEqual(@as(usize, 2), try accessForms(a, "exists", "\"path\""));
    try std.testing.expectEqual(@as(usize, 2), try accessForms(a, "listdir", "\"path\""));
    try std.testing.expectEqual(@as(usize, 2), try accessForms(a, "mkdir", "\"path\""));
    try std.testing.expectEqual(@as(usize, 2), try accessForms(a, "remove", "\"path\""));
}
fn allFileMethods(a: std.mem.Allocator, mode_value: []const u8, data: []const u8) !usize {
    const text = try std.fmt.allocPrint(a, "func value(fs: Filesystem) -> int:\n" ++
        "    with fs.open(\"path\", \"{s}\") as file:\n" ++
        "        _ = file.read()\n        _ = file.read(1)\n        _ = file.readline()\n" ++
        "        _ = file.readlines()\n        _ = file.write({s})\n" ++
        "        _ = file.flush()\n        _ = file.close()\n    return 7\n", .{ mode_value, data });
    const f = try fixture(a, text);
    try validate.outcome(a, f.input, .{ .success = f.output });
    try std.testing.expectEqual(@as(usize, if (std.mem.eql(u8, mode_value, "rb")) 2 else 1), f.output.recipes.len);
    var count: usize = 0;
    for (f.output.batch.nodes) |item| if (item.data == .file_method) {
        count += 1;
    };
    return count;
}
// spec-case: SELFHOST-BODY-FILESYSTEM-1
test "body resources accept all scoped text and binary file methods" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 7), try allFileMethods(arena.allocator(), "rb", "b\"data\""));
    try std.testing.expectEqual(@as(usize, 7), try allFileMethods(arena.allocator(), "r", "\"data\""));
}
fn accessIndex(nodes: []const typed.Node) !usize {
    for (nodes, 0..) |node, index| if (node.data == .file_access) return index;
    return error.TestUnexpectedResult;
}
fn primitive(a: std.mem.Allocator, f: Fixture, item: typed.Node) !void {
    const catalog = try @import("body_check_recipe_validate.zig").expanded(a, f.input, f.output.recipes);
    try @import("body_check_resource_validate.zig").node(catalog, f.output.batch.nodes, f.output.batch.functions[0].scope.locals, item);
}
// spec-case: SELFHOST-BODY-FILESYSTEM-1
test "body resources reject forged whole path arity mode capability payload and result" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "func value(fs: Filesystem) -> int:\n    _ = fs.write_file(\"path\", b\"data\")\n    return 7\n");
    const original = f.output.batch.nodes[try accessIndex(f.output.batch.nodes)];
    var item = original;
    item.data.file_access.arguments = original.data.file_access.arguments[0..2];
    try std.testing.expectError(error.ComponentProtocol, primitive(a, f, item));
    item = original;
    item.data.file_access.mode = 'w';
    try std.testing.expectError(error.ComponentProtocol, primitive(a, f, item));
    item = original;
    item.data.file_access.text = true;
    try std.testing.expectError(error.ComponentProtocol, primitive(a, f, item));
    item = original;
    item.data.file_access.arguments = &.{ original.data.file_access.arguments[1], original.data.file_access.arguments[0], original.data.file_access.arguments[2] };
    try std.testing.expectError(error.ComponentProtocol, primitive(a, f, item));
    item = original;
    item.data.file_access.kind = .write_text;
    item.data.file_access.text = true;
    try std.testing.expectError(error.ComponentProtocol, primitive(a, f, item));
    item = original;
    item.ty = .unit;
    try std.testing.expectError(error.ComponentProtocol, primitive(a, f, item));
}
// spec-case: SELFHOST-BODY-FILESYSTEM-1
test "body resources bind read helper Result payload and retained template authority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "func value(fs: Filesystem) -> int:\n    _ = fs.read_file(\"path\")\n    return 7\n");
    const original = f.output.batch.nodes[try accessIndex(f.output.batch.nodes)];
    var item = original;
    item.data.file_access.kind = .read_text;
    item.data.file_access.text = true;
    try std.testing.expectError(error.ComponentProtocol, primitive(a, f, item));
    var catalog = try @import("body_check_recipe_validate.zig").expanded(a, f.input, f.output.recipes);
    try std.testing.expectEqual(@as(?typed.Type, null), @import("body_check_resource_authority.zig").fileResult(catalog, original.ty));
    catalog.templates.result = null;
    try std.testing.expectError(error.ComponentProtocol, @import("body_check_resource_validate.zig").node(catalog, f.output.batch.nodes, f.output.batch.functions[0].scope.locals, original));
}
// spec-case: SELFHOST-BODY-FILESYSTEM-1
test "body resources reject missing write arguments and extraneous no argument method operands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "func value(fs: Filesystem) -> int:\n    with fs.open(\"path\", \"wb\") as file:\n        _ = file.write(b\"data\")\n    return 7\n");
    const original = f.output.batch.nodes[try methodIndex(f.output.batch.nodes)];
    var item = original;
    item.data.file_method.argument = null;
    try std.testing.expectError(error.ComponentProtocol, primitive(a, f, item));
    item = original;
    item.data.file_method.kind = .close;
    item.ty = .unit;
    try std.testing.expectError(error.ComponentProtocol, primitive(a, f, item));
    item = original;
    item.data.file_method.text = true;
    try std.testing.expectError(error.ComponentProtocol, primitive(a, f, item));
    item = original;
    item.ty = .unit;
    try std.testing.expectError(error.ComponentProtocol, primitive(a, f, item));
}
// spec-case: SELFHOST-BODY-FILESYSTEM-1
test "body resources bind binary readlines to the bytes list rather than the shared text list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "func value(fs: Filesystem) -> int:\n    with fs.open(\"path\", \"rb\") as file:\n        _ = file.readlines()\n    return 7\n");
    try validate.outcome(a, f.input, .{ .success = f.output });
    var item = f.output.batch.nodes[try methodIndex(f.output.batch.nodes)];
    try std.testing.expect(item.ty != item.data.file_method.shapes.list);
    item.ty = item.data.file_method.shapes.list;
    try std.testing.expectError(error.ComponentProtocol, primitive(a, f, item));
}

// spec-case: SELFHOST-BODY-FILESYSTEM-1
test "body resources preserve Result text handles through matched lexical scopes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try fixture(a, "func value(fs: Filesystem) -> int:\n" ++
        "    match fs.open(\"path\", \"r\"):\n        case Ok(file):\n" ++
        "            with file as input:\n                _ = input.readlines()\n" ++
        "            return 7\n        case Err(_):\n            return 0\n");
    try validate.outcome(a, f.input, .{ .success = f.output });
    try std.testing.expectEqual(@as(usize, 2), f.output.recipes.len);
    try std.testing.expectEqual(typed.Type.text_file, f.output.recipes[1].result.success);
}
