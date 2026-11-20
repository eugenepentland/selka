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
    try t.expectError(error.InternalError, inputs.restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{
        .{ .module = "first", .text = "", .emission = .{ .physical = left } },
        .{ .module = "second", .text = "", .emission = .{ .physical = right } },
    }));
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
    body.id = signatures[1].id;
    body.scope.instructions = &.{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .call = signatures[1].id } }, .{ .span = .{ .start = 0, .end = 0 }, .op = .ret }};
    const malformed = try physical.write(a, .{ .functions = &signatures, .records = &.{} }, body);
    const supplied: iface.Interface = .{ .module = "lib", .text = "", .emission = .{ .physical = .{ .functions = &.{malformed} } } };
    const restored = try inputs.restore(a, .{ .functions = &signatures }, &.{ false, false }, &.{ null, null }, &.{supplied});
    var layouts = try @import("native_types.zig").Catalog.initRecords(a, restored.code.records);
    defer layouts.deinit();
    var catalog = try @import("rc_shape.zig").Catalog.init(a, &layouts);
    defer catalog.deinit();
    const certify = @import("rc_readonly_calls.zig").certify;
    var corrected = restored.code.functions[0];
    corrected.id = @fromBackingInt(0);
    try t.expect((try certify(&catalog, restored.code.functions, corrected, "rc-v4")) == null);
    const bad = try certify(&catalog, restored.code.functions, restored.code.functions[0], "rc-v4");
    try t.expect(bad == null);
}
