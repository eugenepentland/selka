//! Inferred consuming list arguments keep an actual call boundary and preserve
//! checked ownership transfers and borrowed read semantics.
const std = @import("std");
const ir = @import("ir.zig");
const consume = @import("consume.zig");
const effects = @import("effects.zig");
const support = @import("test_support.zig");
const Hand = support.Hand;

fn updater(a: std.mem.Allocator, module: *ir.Module, element: ir.Type) !u32 {
    const list = try module.intern(a, .{ .list = element });
    var h = try Hand.init(a, module, "append", .{ .params = try a.dupe(ir.Type, &.{ list, element }), .ret = list });
    const input = try h.param(0);
    const value = try h.param(1);
    const copy = try h.emit(.{ .op = .copy, .ty = list, .a = input });
    const result = try h.emit(.{ .op = .list_push, .ty = list, .a = copy, .b = value });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = result });
    return h.finish();
}

// spec: NEW-CORE-CONSUME-1
test "consuming list eligibility is separate from a module's closed direct-call proof" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const index = try updater(a, &module, .i64);
    try std.testing.expect(consume.closed(&module));
    try std.testing.expectEqual(@as(u64, 1), try consume.candidates(a, &module, &module.functions.items[index]));
    // The catalog remains present when a warm body containing a function reference
    // is omitted, so closure cannot accidentally re-enable an indirect target.
    _ = try module.intern(a, .{ .@"fn" = module.functions.items[index].signature });
    try std.testing.expect(!consume.closed(&module));
    const summaries = try effects.analyze(a, &module);
    try std.testing.expect(summaries.of(index, 0).consumes);
    try std.testing.expect(!summaries.of(index, 0).borrow_only);
}

fn mixedPhi(a: std.mem.Allocator, module: *ir.Module) !u32 {
    const list = try module.intern(a, .{ .list = .i64 });
    var h = try Hand.init(a, module, "mixed", .{ .params = try a.dupe(ir.Type, &.{ list, list, .bool }), .ret = list });
    const first = try h.param(0);
    const second = try h.param(1);
    const flag = try h.param(2);
    const value = try h.int(.i64, 7);
    const left = try h.newBlock();
    const right = try h.newBlock();
    const join = try h.newBlock();
    try h.branch(flag, left, right);
    h.block = left;
    const one = try h.emit(.{ .op = .list_push, .ty = list, .a = first, .b = value });
    try h.jump(join);
    h.block = right;
    const two = try h.emit(.{ .op = .list_push, .ty = list, .a = second, .b = value });
    try h.jump(join);
    h.block = join;
    const result = try h.emit(.{ .op = .phi, .ty = list, .data = try h.extra(&.{ one, two }) });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = result });
    return h.finish();
}

// spec-case: NEW-CORE-CONSUME-1
test "consuming list inference does not choose a parameter from a mixed-root return phi" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const index = try mixedPhi(a, &module);
    try support.verified(a, &module, &.{});
    try std.testing.expectEqual(@as(u64, 0), try consume.candidates(a, &module, &module.functions.items[index]));
}

fn finalParameter(a: std.mem.Allocator, module: *ir.Module, count: usize) !u32 {
    const list = try module.intern(a, .{ .list = .i64 });
    const params = try a.alloc(ir.Type, count);
    @memset(params, .i64);
    params[count - 1] = list;
    var h = try Hand.init(a, module, "last", .{ .params = params, .ret = list });
    const value = try h.param(0);
    const input = try h.param(@intCast(count - 1));
    const result = try h.emit(.{ .op = .list_push, .ty = list, .a = input, .b = value });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = result });
    return h.finish();
}

// spec-case: NEW-CORE-CONSUME-1
test "consuming list parameter masks accept bit 63 and reject an unrepresentable parameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Case = struct { count: usize, mask: u64 };
    for ([_]Case{ .{ .count = 64, .mask = @as(u64, 1) << 63 }, .{ .count = 65, .mask = 0 } }) |case| {
        var module: ir.Module = .{};
        const index = try finalParameter(a, &module, case.count);
        try support.verified(a, &module, &.{});
        try std.testing.expectEqual(case.mask, try consume.candidates(a, &module, &module.functions.items[index]));
    }
}

const Rejection = enum { managed, source_mut, foreign, runtime, unloaded, oversized, recursive, other_root, identity };

fn rejected(a: std.mem.Allocator, module: *ir.Module, kind: Rejection) !u32 {
    const index = try updater(a, module, if (kind == .managed) .str else .i64);
    const f = &module.functions.items[index];
    switch (kind) {
        .managed => {},
        .source_mut => f.signature.passing.owned = 1,
        .foreign => f.signature.linkage = .extern_c,
        .runtime => f.signature.linkage = .runtime_c,
        .unloaded => f.blocks = .empty,
        .oversized => try f.insts.appendNTimes(a, .{ .op = .iconst, .ty = .i64, .data = 0 }, consume.max_instructions),
        .recursive => try f.insts.append(a, .{ .op = .call, .ty = f.signature.ret, .a = @fromBackingInt(index) }),
        .other_root => f.insts.items[0] = .{ .op = .list_new, .ty = f.signature.ret, .a = @fromBackingInt(1) },
        .identity => f.insts.items[4].a = @fromBackingInt(0),
    }
    return index;
}

// spec-case: NEW-CORE-CONSUME-1
test "consuming list inference rejects opaque managed recursive and non-updater bodies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (std.enums.values(Rejection)) |kind| {
        var module: ir.Module = .{};
        const index = try rejected(a, &module, kind);
        try std.testing.expectEqual(@as(u64, 0), try consume.candidates(a, &module, &module.functions.items[index]));
    }
}

// spec-case: NEW-CORE-CONSUME-1
test "consuming list candidates survive validated reuse while an unloaded body remains unknown" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const index = try updater(a, &module, .i64);
    const eager = try effects.analyze(a, &module);
    const retained = try effects.retain(a, .{ .params = eager.params[index], .may = eager.may[index] });
    eager.params[index][0].consumes = false;
    try std.testing.expect(retained.params[0].consumes);
    module.functions.items[index].blocks = .empty;
    module.functions.items[index].insts = .empty;
    const missing = try effects.analyze(a, &module);
    try std.testing.expect(!missing.of(index, 0).consumes);
    const seeded = try effects.analyzeReused(a, &module, &.{retained});
    try std.testing.expect(seeded.of(index, 0).consumes);
}

fn allocationFailure(a: std.mem.Allocator, module: *const ir.Module) !void {
    try std.testing.expectEqual(@as(u64, 1), try consume.candidates(a, module, &module.functions.items[0]));
}

// spec-case: NEW-CORE-CONSUME-1
test "consuming list candidate analysis cleans up every allocation failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var module: ir.Module = .{};
    _ = try updater(arena.allocator(), &module, .i64);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailure, .{&module});
}
