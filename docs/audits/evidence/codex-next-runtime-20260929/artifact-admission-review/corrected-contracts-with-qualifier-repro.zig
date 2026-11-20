const std = @import("std");
const t = std.testing;
const bc = @import("bytecode.zig");
const typed = @import("typed.zig");
const physical = @import("module_physical.zig");
const inputs = @import("module_physical_inputs.zig");
const iface = @import("module_interface.zig");

test "review: packed list with blob must reject ambiguous authority" {
    const list: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base), .name = "list[int]", .declaration = .{ .start = 0, .end = 0 }, .fields = &.{}, .managed = true, .collection = .{ .kind = .list }, .shape = .{ .buffer = .i64 } };
    const blob: typed.Blob = .{ .digest = @splat(0), .length = 8 };
    const code: bc.Program = .{ .records = &.{list}, .functions = &.{.{ .name = "main", .id = @fromBackingInt(0), .scope = .{ .instructions = &.{
        .{ .span = .{ .start = 0, .end = 0 }, .op = .{ .make_record = .{ .ty = list.id, .fields = 0, .payload = &.{ 0, 0, 0, 0, 0, 0, 0, 0 }, .blob = &blob } } },
        .{ .span = .{ .start = 0, .end = 0 }, .op = .pop },
        .{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 0 } },
        .{ .span = .{ .start = 0, .end = 0 }, .op = .ret },
    } } }} };
    try t.expectError(error.InternalError, bc.validate(t.allocator, code));
}

test "review: physical dependency signature conflict must reject" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const signature: bc.Function = .{ .name = "lib.helper", .id = @fromBackingInt(0), .scope = .{ .instructions = &.{} } };
    var other = signature;
    other.signature.return_type = .bool;
    const left = try physical.archive(a, .{ .functions = &.{signature} }, &.{false});
    const right = try physical.archive(a, .{ .functions = &.{other} }, &.{false});
    const first: iface.Interface = .{ .module = "first", .text = "", .emission = .{ .physical = left } };
    const second: iface.Interface = .{ .module = "second", .text = "", .emission = .{ .physical = right } };
    try t.expectError(error.InternalError, inputs.restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ first, second }));
    try t.expectError(error.InternalError, inputs.restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ second, first }));
    try t.expectError(error.InternalError, inputs.restore(a, .{ .functions = &.{signature} }, &.{false}, &.{null}, &.{second}));
}

test "review: restored physical body ID must bind its named function" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const signatures = [_]bc.Function{
        .{ .name = "lib.first", .id = @fromBackingInt(0), .scope = .{ .instructions = &.{} } },
        .{ .name = "lib.second", .id = @fromBackingInt(1), .scope = .{ .instructions = &.{} } },
    };
    var body = signatures[0];
    body.id = signatures[1].id;
    body.scope.instructions = &.{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 0 } }, .{ .span = .{ .start = 0, .end = 0 }, .op = .ret }};
    const malformed = try physical.write(a, .{ .functions = &signatures, .records = &.{} }, body);
    const supplied: iface.Interface = .{ .module = "lib", .text = "", .emission = .{ .physical = .{ .functions = &.{malformed} } } };
    try t.expectError(error.InternalError, inputs.restore(a, .{ .functions = &signatures }, &.{ false, false }, &.{ null, null }, &.{supplied}));
}

test "review: wrong imported ID must not hide a printing helper from readonly proof" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const signatures = [_]bc.Function{
        .{ .name = "lib.first", .id = @fromBackingInt(0), .scope = .{ .instructions = &.{} } },
        .{ .name = "lib.second", .id = @fromBackingInt(1), .scope = .{ .instructions = &.{
            .{ .span = .{ .start = 0, .end = 0 }, .op = .{ .print = .{ .types = &.{}, .separator = false, .terminator = false } } },
            .{ .span = .{ .start = 0, .end = 0 }, .op = .pop },
            .{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 0 } },
            .{ .span = .{ .start = 0, .end = 0 }, .op = .ret },
        } } },
    };
    var body = signatures[0];
    body.scope.instructions = &.{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .call = signatures[1].id } }, .{ .span = .{ .start = 0, .end = 0 }, .op = .ret }};
    const valid = try physical.write(a, .{ .functions = &signatures, .records = &.{} }, body);
    const supplied: iface.Interface = .{ .module = "lib", .text = "", .emission = .{ .physical = .{ .functions = &.{valid} } } };
    const restored = try inputs.restore(a, .{ .functions = &signatures }, &.{ false, false }, &.{ null, null }, &.{supplied});
    var layouts = try @import("native_types.zig").Catalog.initRecords(a, restored.code.records);
    defer layouts.deinit();
    var catalog = try @import("rc_shape.zig").Catalog.init(a, &layouts);
    defer catalog.deinit();
    const certify = @import("rc_readonly_calls.zig").certify;
    try t.expect((try certify(&catalog, restored.code.functions, restored.code.functions[0], "rc-v4")) == null);
    body.id = signatures[1].id;
    const malformed = try physical.write(a, .{ .functions = &signatures, .records = &.{} }, body);
    var forged = supplied;
    forged.emission.physical.functions = &.{malformed};
    try t.expectError(error.InternalError, inputs.restore(a, .{ .functions = &signatures }, &.{ false, false }, &.{ null, null }, &.{forged}));
    try t.expectError(error.InternalError, inputs.restore(a, .{ .functions = &signatures }, &.{ true, false }, &.{ null, null }, &.{forged}));
    forged.emission.physical = .{ .dependencies = &.{malformed} };
    try t.expectError(error.InternalError, inputs.restore(a, .{ .functions = &signatures }, &.{ false, false }, &.{ null, null }, &.{forged}));
}

test "review: matching dependencies tolerate body-local normalized facts in both orders" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first = baseSignature();
    var second = first;
    second.policy.effects = 1;
    second.signature.mutates = &.{0};
    second.signature.return_origin = .fresh;
    second.signature.inferred.writes = true;
    second.scope.locals = &.{
        .{ .name = "items", .ty = .i64, .declaration = .{ .start = 20, .end = 21 }, .mutable = true, .ownership = .{ .initialized = true, .transfer_available = true }, .usage = .{ .reads = 2, .writes = 3 }, .origin = .parameter },
        .{ .name = "$scratch", .ty = .bool, .declaration = .{ .start = 0, .end = 0 }, .mutable = false },
    };
    const left = try dependency(a, first, &.{});
    const right = try dependency(a, second, &.{});
    const forward = try inputs.restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ left, right });
    const backward = try inputs.restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ right, left });
    try t.expectEqual(typed.Type.i64, forward.code.functions[0].scope.locals[0].ty);
    try t.expectEqual(typed.Type.i64, backward.code.functions[0].scope.locals[0].ty);
    try t.expect(forward.code.functions[0].physical.?.unknown and backward.code.functions[0].physical.?.unknown);
    const original = try inputs.restore(a, .{ .functions = &.{first} }, &.{false}, &.{null}, &.{right});
    try t.expectEqual(typed.Type.i64, original.code.functions[0].scope.locals[0].ty);
}

test "review: parameter type count constants and host policy conflicts reject" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var changed = baseSignature();
    changed.scope.locals = &.{.{ .name = "items", .ty = .bool, .declaration = .{ .start = 0, .end = 0 }, .mutable = false }};
    try expectConflict(a, baseSignature(), changed, &.{});
    changed = baseSignature();
    changed.signature.parameter_count = 0;
    try expectConflict(a, baseSignature(), changed, &.{});
    changed = baseSignature();
    changed.signature.constant_arguments = &.{1};
    try expectConflict(a, baseSignature(), changed, &.{});
    changed = baseSignature();
    changed.policy.host = .{ .start = 10, .end = 20 };
    try expectConflict(a, baseSignature(), changed, &.{});
    changed = baseSignature();
    changed.policy.c_abi = true;
    try expectConflict(a, baseSignature(), changed, &.{});
}

test "review: declared mutation qualifier conflict must reject" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const array: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base), .name = "Array[int,2]", .declaration = .{ .start = 0, .end = 0 }, .fields = &.{}, .shape = .{ .array = .{ .element = .i64, .length = 2 } } };
    var plain = baseSignature();
    plain.scope.locals = &.{.{ .name = "items", .ty = array.id, .declaration = .{ .start = 0, .end = 0 }, .mutable = false }};
    var mutated = plain;
    mutated.signature.declared_mutates = &.{0};
    try t.expect(typed.referenceMut(&.{array}, array.id));
    try t.expect(!@import("ownership_model.zig").writesParameter(plain, 0));
    try t.expect(@import("ownership_model.zig").writesParameter(mutated, 0));
    try expectConflict(a, plain, mutated, &.{array});
}

fn baseSignature() bc.Function {
    return .{ .name = "lib.helper", .id = @fromBackingInt(0), .signature = .{ .parameter_count = 1 }, .scope = .{ .locals = &.{.{ .name = "items", .ty = .i64, .declaration = .{ .start = 0, .end = 0 }, .mutable = false }}, .instructions = &.{} } };
}

fn dependency(a: std.mem.Allocator, function: bc.Function, records: []const typed.Record) !iface.Interface {
    return .{ .module = function.name, .text = "", .emission = .{ .physical = try physical.archive(a, .{ .functions = &.{function}, .records = records }, &.{false}) } };
}

fn expectConflict(a: std.mem.Allocator, first: bc.Function, second: bc.Function, records: []const typed.Record) !void {
    const left = try dependency(a, first, records);
    const right = try dependency(a, second, records);
    try t.expectError(error.InternalError, inputs.restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ left, right }));
    try t.expectError(error.InternalError, inputs.restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ right, left }));
    try t.expectError(error.InternalError, inputs.restore(a, .{ .functions = &.{first}, .records = records }, &.{false}, &.{null}, &.{right}));
}
