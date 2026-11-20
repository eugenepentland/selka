//! Native storage transfer and const-borrow lifetime regressions for O4.
const std = @import("std");
const modes = @import("native_language_modes.zig");
const ir = @import("ir.zig");
const emitter = @import("emit_llvm.zig");
const units = @import("emit_units.zig");
const support = @import("test_support.zig");

test "O4 owned moves preserve storage and const borrow lifetimes without copies in native modes" {
    try std.testing.expectEqual(@as(usize, 3), try modes.run(std.testing.allocator, .{
        .path = "tests/lang/explicit_moves.selka",
        .passed = 7,
        .label = "explicit moves runtime",
    }));
}

test "O4 owned field moves consume carriers across native modes" {
    try std.testing.expectEqual(@as(usize, 3), try modes.run(std.testing.allocator, .{
        .path = "tests/lang/owned_field_moves.selka",
        .passed = 26,
        .label = "owned field moves runtime",
    }));
}

fn fixedLocation(_: *const anyopaque, _: u32) emitter.Location {
    return .{ .path = "allocation.selka", .line = 1, .column = 1 };
}

test "O4 allocation measurements count reused list blocks across split emission" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    var hand = try support.Hand.init(a, &module, "main", .{ .params = &.{}, .ret = .i64 });
    const value = try hand.emit(.{ .op = .list_new, .ty = list, .a = try hand.int(.i64, 2) });
    _ = try hand.emit(.{ .op = .drop, .ty = .void, .a = value });
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = try hand.int(.i64, 0) });
    _ = try hand.finish();
    const context: u8 = 0;
    const options: emitter.Options = .{ .locator = .{ .context = &context, .locate = fixedLocation }, .source_path = "allocation.selka", .main = .{} };
    const ordinary = try emitter.emitModule(a, &module, options);
    try std.testing.expect(std.mem.indexOf(u8, ordinary, "label %pop") != null);
    try module.functions.append(a, .{ .name = "myl_core_test_allocations", .signature = .{ .params = &.{.bool}, .ret = .i64, .linkage = .runtime_c } });
    const measured = try emitter.emitModule(a, &module, options);
    try std.testing.expect(std.mem.indexOf(u8, measured, "label %pop") == null);
    const fragments = try units.emit(a, &module, options);
    var allocators: usize = 0;
    for (fragments) |fragment| {
        if (std.mem.indexOf(u8, fragment.llvm, "define internal ptr @myl_core_list_new(") == null) continue;
        allocators += 1;
        try std.testing.expect(std.mem.indexOf(u8, fragment.llvm, "label %pop") == null);
    }
    try std.testing.expect(allocators > 0);
}
