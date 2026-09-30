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

// spec-case: MODULE-COMPILE-1
test "physical imports reject dependency signature conflicts in either order and against originals" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const signature: bytecode.Function = .{ .name = "lib.helper", .id = @fromBackingInt(0), .scope = .{ .instructions = &.{} } };
    var different = signature;
    different.signature.return_type = .bool;
    const left = try physical.archive(a, .{ .functions = &.{signature} }, &.{false});
    const right = try physical.archive(a, .{ .functions = &.{different} }, &.{false});
    const first: language.module_interface.Interface = .{ .module = "first", .text = "", .emission = .{ .physical = left } };
    const second: language.module_interface.Interface = .{ .module = "second", .text = "", .emission = .{ .physical = right } };
    const restore = @import("module_physical_inputs.zig").restore;
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ first, second }));
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ second, first }));
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{signature} }, &.{false}, &.{null}, &.{second}));
    const valid = try restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ first, first });
    try t.expectEqual(typed.Type.i64, valid.code.functions[0].signature.return_type);
    try t.expect(valid.code.functions[0].physical.?.unknown);
}

// spec-case: MODULE-COMPILE-1
test "physical imports bind decoded function IDs to named slots before granting readonly authority" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const signatures = [_]bytecode.Function{
        .{ .name = "lib.first", .id = @fromBackingInt(0), .scope = .{ .instructions = &.{} } },
        .{ .name = "lib.second", .id = @fromBackingInt(1), .scope = .{ .instructions = &.{
            .{ .span = .{ .start = 0, .end = 0 }, .op = .{ .print = .{ .types = &.{}, .separator = false, .terminator = false } } },
            .{ .span = .{ .start = 0, .end = 0 }, .op = .pop },
            .{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 0 } },
            .{ .span = .{ .start = 0, .end = 0 }, .op = .ret },
        } } },
    };
    var body = signatures[0];
    body.scope.instructions = &.{ .{ .span = .{ .start = 0, .end = 0 }, .op = .{ .call = signatures[1].id } }, .{ .span = .{ .start = 0, .end = 0 }, .op = .ret } };
    const good = try physical.write(a, .{ .functions = &signatures, .records = &.{} }, body);
    const supplied: language.module_interface.Interface = .{ .module = "lib", .text = "", .emission = .{ .physical = .{ .functions = &.{good} } } };
    const restore = @import("module_physical_inputs.zig").restore;
    const restored = try restore(a, .{ .functions = &signatures }, &.{ false, false }, &.{ null, null }, &.{supplied});
    var layouts = try @import("native_types.zig").Catalog.initRecords(a, restored.code.records);
    defer layouts.deinit();
    var catalog = try @import("rc_shape.zig").Catalog.init(a, &layouts);
    defer catalog.deinit();
    try t.expect((try @import("rc_readonly_calls.zig").certify(&catalog, restored.code.functions, restored.code.functions[0], "rc-v3")) == null);
    body.id = signatures[1].id;
    const bad = try physical.write(a, .{ .functions = &signatures, .records = &.{} }, body);
    var forged = supplied;
    forged.emission.physical.functions = &.{bad};
    try t.expectError(error.InternalError, restore(a, .{ .functions = &signatures }, &.{ false, false }, &.{ null, null }, &.{forged}));
    try t.expectError(error.InternalError, restore(a, .{ .functions = &signatures }, &.{ true, false }, &.{ null, null }, &.{forged}));
    forged.emission.physical = .{ .dependencies = &.{bad} };
    try t.expectError(error.InternalError, restore(a, .{ .functions = &signatures }, &.{ false, false }, &.{ null, null }, &.{forged}));
}

// spec-case: MODULE-COMPILE-1
test "physical imports compare declaration signatures without importing body-local facts" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const signature: bytecode.Function = .{
        .name = "lib.helper",
        .id = @fromBackingInt(0),
        .signature = .{ .parameter_count = 1 },
        .scope = .{ .locals = &.{.{ .name = "n", .ty = .i64, .declaration = .{ .start = 0, .end = 1 }, .mutable = false }}, .instructions = &.{} },
    };
    var actual = signature;
    actual.signature.inferred.writes = true;
    actual.scope.locals = &.{
        .{ .name = "n", .ty = .i64, .declaration = .{ .start = 9, .end = 10 }, .mutable = true, .usage = .{ .reads = 4 }, .origin = .parameter },
        .{ .name = "local", .ty = .bool, .declaration = .{ .start = 0, .end = 0 }, .mutable = false },
    };
    actual.scope.instructions = &.{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 1 } }};
    const archive = try physical.archive(a, .{ .functions = &.{actual} }, &.{true});
    const restored = try @import("module_physical_inputs.zig").restore(a, .{ .functions = &.{signature} }, &.{false}, &.{null}, &.{.{ .module = "lib", .text = "", .emission = .{ .physical = archive } }});
    try t.expectEqual(@as(usize, 2), restored.code.functions[0].scope.locals.len);
    try t.expect(restored.code.functions[0].signature.inferred.writes);
}
