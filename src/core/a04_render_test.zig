//! Borrowed aggregate rendering has no temporary managed owner in either emitter.
const std = @import("std");
const ir = @import("ir.zig");
const emit = @import("emit_llvm.zig");
const support = @import("test_support.zig");
const zero = @import("zero_rc.zig");

fn location(_: *const anyopaque, offset: u32) emit.Location {
    return .{ .line = 1, .column = offset + 1 };
}

fn example(a: std.mem.Allocator) !ir.Module {
    var refusal: @import("build.zig").Refusal = .{};
    return support.buildSource(a,
        \\record Label:
        \\    number: int
        \\    word: str
        \\func show(value: Label) -> str:
        \\    return f"{value}"
        \\func main() -> int:
        \\    const value = Label(number=7, word="x")
        \\    return len(show(value))
    , &refusal);
}

// spec-case: NEW-CORE-S3-VALUES-1
test "A04 rendering borrows physical values in whole and unit emission" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const module = try example(a);
    var show_count: usize = 0;
    for (module.functions.items) |function| {
        for (function.insts.items) |inst| try std.testing.expect(inst.op != .box_make);
        if (!std.mem.startsWith(u8, function.name, "myl_core_show_")) continue;
        show_count += 1;
        try std.testing.expectEqual(@as(usize, 1), function.signature.params.len);
        try std.testing.expect(module.kind(function.signature.params[0]) == .record);
        try std.testing.expectEqual(@as(u64, 0), function.signature.owned);
    }
    try std.testing.expectEqual(@as(usize, 1), show_count);
    const context: u8 = 0;
    const options: emit.Options = .{ .locator = .{ .context = &context, .locate = location }, .source_path = "render.my", .main = .{ .parameters = &.{} } };
    const whole = try emit.emitModule(a, &module, options);
    try std.testing.expect(std.mem.indexOf(u8, whole, "call ptr @myl_core_values_render(ptr @myl.render.") != null);
    try std.testing.expect(std.mem.indexOf(u8, whole, "call fastcc ptr @myl_core_show_") == null);
    try std.testing.expect(std.mem.indexOf(u8, whole, "define internal fastcc ptr @myl_core_show_") == null);
    const units = try @import("emit_units.zig").emit(a, &module, options);
    try std.testing.expectEqual(@as(usize, 1), renderCalls(units));
}

fn renderCalls(units: []const @import("emit_units.zig").Unit) usize {
    var calls: usize = 0;
    for (units) |unit| {
        var lines = std.mem.splitScalar(u8, unit.llvm, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "call ptr @myl_core_values_render(") != null) calls += 1;
        }
    }
    return calls;
}

// spec-case: NEW-CORE-S3-VALUES-1
test "A04 rendering registry admits exact borrowed fresh show helpers" {
    for ([_][]const u8{ "myl_core_show_7", "myl_core_show_7_p8" }) |name| {
        const contract = zero.contract(name) orelse return error.TestUnexpectedResult;
        try std.testing.expect(contract.result == .fresh);
        try std.testing.expectEqual(@as(u64, 0), contract.owned);
    }
}

// spec-case: NEW-CORE-S3-VALUES-1
test "A04 rendering registry admits exact scalar descriptor helpers" {
    for ([_][]const u8{ "myl_core_render_shape_0_7", "myl_core_render_shape_0_7_p8" }) |name| {
        const contract = zero.contract(name) orelse return error.TestUnexpectedResult;
        try std.testing.expect(contract.result == .scalar);
        try std.testing.expectEqual(@as(u64, 0), contract.owned);
    }
}

// spec-case: NEW-CORE-S3-VALUES-1
test "A04 rendering registry rejects malformed generated helper identities" {
    for ([_][]const u8{
        "myl_core_show_",           "myl_core_show_7_",            "myl_core_show_7_p",           "myl_core_show_x",
        "myl_core_show_4294967296", "myl_core_show_7_p4294967296", "myl_core_show_7_p8_x",        "myl_core_render_shape_",
        "myl_core_render_shape_0",  "myl_core_render_shape_x_7",   "myl_core_render_shape_0_7_p", "myl_core_render_shape_4294967296_7",
    }) |name| try std.testing.expect(zero.contract(name) == null);
}

// spec-case: NEW-CORE-S3-VALUES-1
test "A04 rendering rejects wrong generated helper signatures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try example(a);
    const context: u8 = 0;
    const options: emit.Options = .{ .locator = .{ .context = &context, .locate = location }, .source_path = "render.my", .main = .{ .parameters = &.{} } };
    for (module.functions.items) |*function| {
        if (!std.mem.startsWith(u8, function.name, "myl_core_show_")) continue;
        function.signature.owned = 1;
        try std.testing.expectError(error.UnsupportedInstruction, emit.emitModule(a, &module, options));
        function.signature.owned = 0;
        function.signature.params = &.{.i64};
        try std.testing.expectError(error.UnsupportedInstruction, emit.emitModule(a, &module, options));
        break;
    }
    var metadata: ir.Module = .{};
    try metadata.functions.append(a, .{ .name = "myl_core_render_shape_0_7", .signature = .{ .params = &.{.i64}, .ret = .void, .linkage = .runtime_c } });
    var text: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.UnsupportedInstruction, @import("emit_render.zig").descriptors(a, &metadata, &text));
}
