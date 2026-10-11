//! Schema 11 declaration and concrete-instance authority, before body adoption.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const value = @import("body_check_value.zig");
const source = @import("source.zig");
const authority = @import("body_check_generic_validate.zig");
comptime {
    _ = @import("body_check_generic_adopt.zig");
}
const Fixture = struct { input: value.Input, batch: value.Batch };
fn fixture(a: std.mem.Allocator) !Fixture {
    const parameters = try a.dupe(ast.TypeParameter, &.{.{ .name = .{ .start = 2, .end = 3 }, .requirements = &.{} }});
    const raw = try a.dupe(ast.Function, &.{
        .{ .name = .{ .start = 0, .end = 1 }, .body = @fromBackingInt(0), .signature = .{ .type_parameters = parameters, .parameters = &.{}, .return_type = .{ .start = 2, .end = 3 } } },
        .{ .name = .{ .start = 4, .end = 8 }, .body = @fromBackingInt(0), .signature = .{ .parameters = &.{}, .return_type = .{ .start = 9, .end = 12 } } },
    });
    const functions = try a.dupe(typed.Function, &.{
        .{ .id = @fromBackingInt(0), .name = "main", .declaration = raw[1].name, .scope = .{ .body = @fromBackingInt(0) } },
        .{ .id = @fromBackingInt(1), .name = "g[i64]", .declaration = raw[0].name, .type_arguments = &.{.i64}, .signature = .{ .constant_arguments = &.{null} }, .scope = .{ .body = @fromBackingInt(0) } },
    });
    const nodes = try a.dupe(typed.Node, &.{.{ .ty = .i64, .span = raw[1].name, .data = .{ .call = .{ .function = @fromBackingInt(1), .arguments = &.{} } } }});
    return .{
        .input = .{ .context = .{ .path = "generic.my", .source = "g T main int", .trusted_intrinsics = false, .entry_required = false }, .program = .{ .nodes = .empty, .statements = .empty, .functions = raw }, .modules = &.{} },
        .batch = .{ .functions = functions, .nodes = nodes, .statements = &.{}, .ranges = try a.dupe(@import("semantic_copy.zig").Range, &.{
            .{ .nodes = .{ .start = 0, .end = 1 }, .statements = .{ .start = 0, .end = 0 } },
            .{ .nodes = .{ .start = 1, .end = 1 }, .statements = .{ .start = 0, .end = 0 } },
        }) },
    };
}
// spec-case: GENERIC-INSTANCE-1
test "generic body authority restores skipped declaration ordinals and ordinary executable ownership" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try fixture(arena.allocator());
    const plan = try authority.plan(arena.allocator(), f.input, f.batch);
    try std.testing.expectEqual(@as(usize, 1), plan.ordinary_count);
    try std.testing.expectEqual(@as(?typed.FunctionId, null), plan.ordinary[0]);
    try std.testing.expectEqual(@as(usize, 0), @backingInt(plan.ordinary[1].?));
    try std.testing.expectEqual(@as(usize, 0), @backingInt(plan.keys[1].declaration));
}
// spec-case: GENERIC-INSTANCE-1
test "generic body authority rejects an instance supported only by its own recursive call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var f = try fixture(arena.allocator());
    const ranges = try arena.allocator().dupe(@import("semantic_copy.zig").Range, f.batch.ranges);
    ranges[0].nodes = .{ .start = 0, .end = 0 };
    ranges[1].nodes = .{ .start = 0, .end = 1 };
    f.batch.ranges = ranges;
    try std.testing.expectError(error.ComponentProtocol, authority.plan(arena.allocator(), f.input, f.batch));
}
// spec-case: GENERIC-INSTANCE-1
test "generic body authority rejects diagnostic names and wrong constant argument roles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var f = try fixture(arena.allocator());
    const functions = try arena.allocator().dupe(typed.Function, f.batch.functions);
    f.batch.functions = functions;
    functions[1].name = "g[int]";
    try std.testing.expectError(error.ComponentProtocol, authority.plan(arena.allocator(), f.input, f.batch));
    functions[1].name = "g[i64]";
    functions[1].signature.constant_arguments = &.{0};
    try std.testing.expectError(error.ComponentProtocol, authority.plan(arena.allocator(), f.input, f.batch));
}
// spec-case: GENERIC-INSTANCE-1
test "generic body authority refuses duplicate instance keys and foreign declarations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try fixture(a);
    const functions = try a.alloc(typed.Function, 3);
    @memcpy(functions[0..2], f.batch.functions);
    functions[2] = functions[1];
    functions[2].id = @fromBackingInt(2);
    const ranges = try a.alloc(@import("semantic_copy.zig").Range, 3);
    @memcpy(ranges[0..2], f.batch.ranges);
    ranges[2] = ranges[1];
    f.batch.functions = functions;
    f.batch.ranges = ranges;
    try std.testing.expectError(error.ComponentProtocol, authority.plan(a, f.input, f.batch));
    f.batch.functions = functions[0..2];
    f.batch.ranges = ranges[0..2];
    functions[1].declaration = .{ .start = 2, .end = 3 };
    try std.testing.expectError(error.ComponentProtocol, authority.plan(a, f.input, f.batch));
}
// spec-case: GENERIC-EXECUTION-1
test "generic body adoption contract compiles alongside unchanged native specialization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "generic.my", "func id[T](value: T) -> T:\n    return value\nfunc main() -> int:\n    return id(7)\n");
    var sink: @import("diagnostic.zig").Sink = .{ .allocator = a };
    const tokens = try @import("lexer.zig").lex(a, src.bytes, &sink);
    var parser: @import("parser.zig").Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = &sink };
    const raw = try parser.parse();
    const native = try @import("sema.zig").checkLibraryProgram(a, src, raw, &sink, null);
    try std.testing.expectEqual(@as(usize, 2), native.functions.len);
    try std.testing.expectEqualStrings("id[i64]", native.functions[1].name);
    try std.testing.expectEqualSlices(typed.Type, &.{.i64}, native.functions[1].type_arguments);
}
// spec-case: SELFHOST-BODY-ENTRY-1
test "generic body skipped templates preserve scoped file declaration ownership" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = "func id[T](value: T) -> T:\n    return value\nfunc main(fs: Filesystem) -> int:\n    with fs.open(\"input\", \"rb\") as file:\n        const octets = file.read()\n        return len(octets)\n";
    const src = try source.Source.init(a, "generic.my", text);
    var sink: @import("diagnostic.zig").Sink = .{ .allocator = a };
    const tokens = try @import("lexer.zig").lex(a, src.bytes, &sink);
    var parser: @import("parser.zig").Parser = .{ .src = src, .tokens = tokens, .storage = a, .sink = &sink };
    const raw = try parser.parse();
    const native = try @import("sema.zig").checkLibraryProgram(a, src, raw, &sink, null);
    try std.testing.expectEqual(@as(usize, 1), native.functions.len);
    const input: value.Input = .{ .context = .{ .path = src.path, .source = src.bytes, .trusted_intrinsics = false, .entry_required = false }, .program = raw, .modules = &.{} };
    const ranges = [_]@import("semantic_copy.zig").Range{.{ .nodes = .{ .start = 0, .end = native.nodes.len }, .statements = .{ .start = 0, .end = native.statements.len } }};
    const functions = try a.dupe(typed.Function, native.functions);
    const batch: value.Batch = .{ .nodes = native.nodes, .statements = native.statements, .functions = functions, .ranges = &ranges };
    try @import("body_check_resource_scope.zig").batch(a, input, batch);
    functions[0].declaration = raw.functions[0].name;
    try std.testing.expectError(error.ComponentProtocol, @import("body_check_resource_scope.zig").batch(a, input, batch));
}
