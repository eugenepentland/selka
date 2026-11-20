//! Owned Result/Option propagation transfers values without duplicating their trees.
const std = @import("std");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const verify = @import("verify_ir.zig");

// spec-case: NEW-CORE-ZERO-RC-PAYLOAD-TRANSFER-1
test "zero RC payload transfer verifies unboxed result types and refuses invalid payload types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const box = try module.intern(a, .{ .box = .str });
    const option = try module.option(a, box);
    var h = try support.Hand.init(a, &module, "take", .{ .params = &.{option}, .ret = .str, .passing = .{ .owned = 1 } });
    // The payload is taken under a test of its tag (the verifier's union-tag rule).
    const some = try h.newBlock();
    const none = try h.newBlock();
    const optional = try h.param(0);
    const tag = try h.emit(.{ .op = .union_tag, .ty = .u32, .a = optional });
    try h.branch(try h.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try h.int(.u32, 1), .data = @backingInt(ir.Predicate.eq) }), some, none);
    h.block = some;
    const taken = try h.emit(.{ .op = .union_take, .ty = .str, .a = optional, .data = 1 });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = taken });
    h.block = none;
    _ = try h.emit(.{ .op = .@"unreachable", .ty = .void });
    _ = try h.finish();
    var failure: verify.Failure = .{};
    try verify.verifyModule(a, &module, &failure);
    module.functions.items[0].insts.items[taken.index()].ty = box;
    try std.testing.expectError(error.InvalidIr, verify.verifyModule(a, &module, &failure));
}

fn wideBox(h: *support.Hand, wide: ir.Type, box: ir.Type, list: ir.Type, value: i64) !ir.Ref {
    const number = try h.int(.i64, value);
    const empty = try h.emit(.{ .op = .list_new, .ty = list, .a = try h.int(.u64, 1) });
    const items = try h.emit(.{ .op = .list_push, .ty = list, .a = empty, .b = number });
    const record = try h.emit(.{ .op = .record_make, .ty = wide, .data = try h.extra(&.{ number, number, number, number, items }) });
    return h.emit(.{ .op = .box_make, .ty = box, .a = record });
}

// spec-case: NEW-CORE-ZERO-RC-PAYLOAD-TRANSFER-1
test "zero RC payload transfer preserves wide boxed children after the shell is reused" {
    inline for (.{ .{ false, false }, .{ false, true }, .{ true, false }, .{ true, true } }) |case| {
        const optimized = case[0];
        const wide_union = case[1];
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var module: ir.Module = .{};
        const list = try module.intern(a, .{ .list = .i64 });
        const wide = try module.intern(a, .{ .record = &.{ .i64, .i64, .i64, .i64, list } });
        const box = try module.intern(a, .{ .box = wide });
        // A wide alternative makes the union itself memory-backed. The boxed
        // case still needs an independent payload home before its shell is freed.
        const option = if (wide_union) try module.intern(a, .{ .@"union" = &.{ wide, box } }) else try module.option(a, box);
        var h = try support.Hand.init(a, &module, "main", .{ .params = &.{.cap}, .ret = .i64 });
        const original = try wideBox(&h, wide, box, list, 7);
        const wrapped = try h.emit(.{ .op = .union_make, .ty = option, .a = original, .data = 1 });
        const taken = try h.emit(.{ .op = .union_take, .ty = wide, .a = wrapped, .data = 1 });
        // Allocate an identically sized box before reading any transferred field.
        const replacement = try wideBox(&h, wide, box, list, 99);
        const other = try h.emit(.{ .op = .box_get, .ty = wide, .a = replacement });
        const first = try h.emit(.{ .op = .record_get, .ty = .i64, .a = taken });
        const child = try h.emit(.{ .op = .record_get, .ty = list, .a = taken, .data = 4 });
        const element = try h.emit(.{ .op = .list_get, .ty = .i64, .a = child, .b = try h.int(.u64, 0) });
        const second = try h.emit(.{ .op = .record_get, .ty = .i64, .a = other });
        try h.printValues(try h.param(0), &.{ first, element, second });
        _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
        module.entry = try h.finish();
        const run = try support.runOwned(a, &module, .{ .release = optimized, .verify = optimized });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings("7 7 99\n", run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(@import("zero_rc.zig").emittedClean(run.llvm));
        try std.testing.expect(std.mem.indexOf(u8, run.llvm, "call void @myl_core_box_drop_shell(") != null);
    }
}
