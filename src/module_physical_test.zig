//! Physical imports must resolve names against the current catalog and reject missing authority.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const physical = language.module_physical;
const bytecode = language.bytecode;
const typed = @import("typed.zig");

// spec-case: MODULE-COMPILE-1
test "physical imports remap type and callee IDs and decline missing symbols" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const functions = [_]bytecode.Function{
        .{ .name = "lib.read", .id = @fromBackingInt(0), .scope = .{ .instructions = &.{} } },
        .{ .name = "lib.helper", .id = @fromBackingInt(1), .scope = .{ .instructions = &.{} } },
    };
    const record: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base), .name = "lib.Item", .declaration = .{ .start = 4, .end = 8 }, .fields = &.{} };
    const body: bytecode.Function = .{
        .name = "lib.read",
        .id = @fromBackingInt(0),
        .signature = .{ .return_type = record.id },
        .scope = .{ .instructions = &.{.{ .span = .{ .start = 20, .end = 21 }, .op = .{ .call = @fromBackingInt(1) } }} },
    };
    const data = try physical.write(a, .{ .functions = &functions, .records = &.{record} }, body);
    var ids: physical.Ids = .{};
    try ids.functions.put(a, "lib.read", @fromBackingInt(3));
    try ids.functions.put(a, "lib.helper", @fromBackingInt(8));
    try ids.records.put(a, "lib.Item", @fromBackingInt(typed.Type.record_base + 4));
    const restored = try physical.read(a, &ids, bytecode.Function, data);
    try t.expectEqual(@as(usize, 3), @backingInt(restored.id));
    try t.expectEqual(@as(usize, 8), @backingInt(restored.scope.instructions[0].op.call));
    try t.expectEqual(@as(usize, typed.Type.record_base + 4), @backingInt(restored.signature.return_type));
    _ = ids.functions.remove("lib.helper");
    try t.expectError(error.InvalidEncoding, physical.read(a, &ids, bytecode.Function, data));
}

// spec-case: MODULE-COMPILE-1
test "physical imports refuse conflicting record shapes and real bodies" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const record: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base), .name = "lib.Item", .declaration = .{ .start = 0, .end = 0 }, .fields = &.{} };
    const body: bytecode.Function = .{ .name = "lib.read", .id = @fromBackingInt(0), .scope = .{ .instructions = &.{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 1 } }} } };
    const code: bytecode.Program = .{ .functions = &.{body}, .records = &.{record} };
    const original = try physical.archive(a, code, &.{true});
    var other_record = record;
    other_record.managed = true;
    const different_shape = try physical.archive(a, .{ .functions = &.{body}, .records = &.{other_record} }, &.{true});
    var other_body = body;
    other_body.scope.instructions = &.{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 2 } }};
    const different_body = try physical.archive(a, .{ .functions = &.{other_body}, .records = &.{record} }, &.{true});
    const restore = @import("module_physical_inputs.zig").restore;
    const first: language.module_interface.Interface = .{ .module = "lib", .text = "", .emission = .{ .physical = original } };
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ first, .{ .module = "lib", .text = "", .emission = .{ .physical = different_shape } } }));
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ first, .{ .module = "lib", .text = "", .emission = .{ .physical = different_body } } }));
    try t.expectError(error.InternalError, restore(a, code, &.{false}, &.{null}, &.{.{ .module = "lib", .text = "", .emission = .{ .physical = different_shape } }}));
}

// spec-case: MODULE-COMPILE-1
test "signature-only original imports cannot prove unique mutable parameters" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const signature: bytecode.Function = .{ .name = "lib.mutate", .id = @fromBackingInt(0), .signature = .{ .parameter_count = 1, .declared_mutates = &.{0} }, .scope = .{ .instructions = &.{} } };
    const restored = try @import("module_physical_inputs.zig").restore(a, .{ .functions = &.{signature} }, &.{false}, &.{null}, &.{});
    try t.expect(!@import("ownership_model.zig").uniqueParameter(restored.code.functions[0], 0));
    try t.expect(restored.code.functions[0].physical.?.unknown);
    try t.expect(restored.imported[0].?.allocates);
    try t.expect(restored.imported[0].?.writes[0]);
    var actual = signature;
    actual.scope.instructions = &.{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 1 } }};
    const archive = try physical.archive(a, .{ .functions = &.{actual} }, &.{true});
    const supplied: language.module_interface.Interface = .{ .module = "lib", .text = "", .emission = .{ .physical = archive, .functions = &.{.{ .name = "lib.mutate", .allocates = false, .writes = &.{true} }} } };
    const known = try @import("module_physical_inputs.zig").restore(a, .{ .functions = &.{signature} }, &.{false}, &.{null}, &.{supplied});
    try t.expect(@import("ownership_model.zig").uniqueParameter(known.code.functions[0], 0));
    try t.expect(!known.code.functions[0].physical.?.unknown);
    try t.expect(!known.imported[0].?.allocates);
}
