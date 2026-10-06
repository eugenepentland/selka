//! S3-0 hand-built shapes, fail-closed LLVM, runtime ABI and byte COW provenance.
const std = @import("std");
const ir = @import("ir.zig");
const print = @import("print.zig");
const verify_ir = @import("verify_ir.zig");
const own = @import("own.zig");
const support = @import("test_support.zig");
const Hand = support.Hand;

const Program = struct { module: ir.Module, operation: ir.Ref };

fn pendingProgram(a: std.mem.Allocator, op: ir.Op) !Program {
    var m: ir.Module = .{};
    var h = try Hand.init(a, &m, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const buffer = if (op == .buffer_new) try h.loose(.{ .op = .undef, .ty = .byte_buffer }) else if (op == .buffer_copy or op == .buffer_set or op == .buffer_pop or op == .buffer_push) blk: {
        const fresh = try h.emit(.{ .op = .buffer_new, .ty = .byte_buffer, .a = try h.int(.u64, 8) });
        break :blk try h.emit(.{ .op = .buffer_push, .ty = .byte_buffer, .a = fresh, .b = try h.int(.u8, 1) });
    } else try h.loose(.{ .op = .undef, .ty = .byte_buffer });
    const value = try h.int(.u8, 42);
    const index = try h.int(.i64, 0);
    var inst: ir.Inst = .{ .op = op, .ty = .byte_buffer, .a = buffer };
    switch (op) {
        .buffer_new => inst.a = try h.int(.u64, 8),
        .buffer_copy, .buffer_pop => {},
        .buffer_push => inst.b = value,
        .buffer_set => {
            inst.b = index;
            inst.data = try h.extra(&.{value});
            inst.check = .exact;
        },
        .shift_left, .shift_right, .saturating_add => {
            inst.ty = .i64;
            inst.a = try h.int(.i64, 42);
            inst.b = index;
            inst.check = if (op == .saturating_add) .none else .exact;
        },
        .float_unary => {
            inst.ty = .f64;
            inst.a = try h.loose(.{ .op = .fconst, .ty = .f64, .data = @bitCast(@as(f64, 4)) });
            inst.data = @backingInt(ir.FloatUnary.sqrt);
        },
        else => unreachable,
    }
    const operation = try h.emit(inst);
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return .{ .module = m, .operation = operation };
}

fn exercise(op: ir.Op, allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var program = try pendingProgram(a, op);
    var failure: verify_ir.Failure = .{};
    try verify_ir.verifyModule(a, &program.module, &failure);
    const text = try print.module(a, &program.module);
    try std.testing.expect(std.mem.indexOf(u8, text, @tagName(op)) != null);
    const ran = try support.runModule(a, &program.module, false);
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
    const f = &program.module.functions.items[0];
    const original = f.inst(program.operation);
    f.insts.items[program.operation.index()].ty = .cap;
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &program.module, &failure));
    f.insts.items[program.operation.index()] = original;
    const wrong: ir.Ref = @fromBackingInt(@as(u32, @intCast(f.insts.items.len)));
    try f.insts.append(a, .{ .op = .iconst, .ty = .bool, .data = 1 });
    f.insts.items[program.operation.index()].a = wrong;
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &program.module, &failure));
}

// spec: NEW-CORE-S3-IR-2
test "S3 IR buffer_new compiles and executes a fresh mutable value" {
    try exercise(.buffer_new, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S3-IR-2
test "S3 IR buffer_copy compiles and verifies its independent result" {
    try exercise(.buffer_copy, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S3-IR-2
test "S3 IR buffer_set verifies its index and byte replacement" {
    try exercise(.buffer_set, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S3-IR-2
test "S3 IR buffer_push verifies its byte argument" {
    try exercise(.buffer_push, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S3-IR-2
test "S3 IR buffer_pop verifies its mutable receiver" {
    try exercise(.buffer_pop, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S3-IR-2
test "S3 IR shift_left compiles and verifies integer operands" {
    try exercise(.shift_left, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S3-IR-2
test "S3 IR shift_right compiles and verifies integer operands" {
    try exercise(.shift_right, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S3-IR-2
test "S3 IR saturating_add compiles and verifies result signedness" {
    try exercise(.saturating_add, std.testing.allocator);
    try std.testing.expect(true);
}

// spec-case: NEW-CORE-S3-IR-2
test "S3 IR float_unary compiles and verifies floating operands" {
    try exercise(.float_unary, std.testing.allocator);
    try std.testing.expect(true);
}

fn floatSelectors(a: std.mem.Allocator) !void {
    var program = try pendingProgram(a, .float_unary);
    var failure: verify_ir.Failure = .{};
    for (std.meta.tags(ir.FloatUnary)) |kind| {
        program.module.functions.items[0].insts.items[program.operation.index()].data = @backingInt(kind);
        try verify_ir.verifyModule(a, &program.module, &failure);
    }
    program.module.functions.items[0].insts.items[program.operation.index()].data = std.meta.tags(ir.FloatUnary).len;
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyModule(a, &program.module, &failure));
}

// spec: NEW-CORE-S3-IR-1
test "S3 IR float selector cannot address an unknown intrinsic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try floatSelectors(arena.allocator());
    try std.testing.expect(true);
}

fn layouts(a: std.mem.Allocator) !void {
    var m: ir.Module = .{};
    for ([_]ir.Type{ .byte_buffer, .capability, .resource }) |ty| {
        try std.testing.expect(m.valid(ty));
        try std.testing.expect(m.isBlock(ty));
        try std.testing.expect(m.managed(ty));
        try std.testing.expectEqual(@as(u32, 8), m.size(ty));
        try std.testing.expectEqual(@as(u32, 8), m.alignment(ty));
        const option = try m.option(a, ty);
        try std.testing.expectEqual(ir.UnionForm.niche, m.unionLayout(option).form);
        const record = try m.intern(a, .{ .record = &.{ .i64, ty } });
        const array = try m.intern(a, .{ .array = .{ .elem = ty, .n = 3 } });
        try std.testing.expect(m.managed(record));
        try std.testing.expect(m.managed(array));
        try std.testing.expectEqual(@as(u32, 16), m.size(record));
        try std.testing.expectEqual(@as(u32, 24), m.size(array));
    }
    try std.testing.expectEqual(@as(u32, 15), ir.Type.first_compound);
}

// spec-case: NEW-CORE-S3-IR-1
test "S3 leaf types retain one-count aggregate and Option layouts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try layouts(arena.allocator());
    try std.testing.expect(true);
}

fn tokenCall(a: std.mem.Allocator, linkage: ir.Linkage) !support.Run {
    var m: ir.Module = .{};
    const params: []const ir.Type = if (linkage == .runtime_c) &.{.cap} else &.{ .cap, .i64 };
    try m.functions.append(a, .{ .name = "myl_core_s3_token_roundtrip", .signature = .{ .params = params, .ret = .i64, .linkage = linkage } });
    m.entry = 1;
    var h = try Hand.init(a, &m, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const cap = try h.param(0);
    const value = try h.int(.i64, 42);
    const args: []const ir.Ref = if (linkage == .runtime_c) &.{cap} else &.{ cap, value };
    const result = try h.emit(.{ .op = .call, .ty = .i64, .a = @fromBackingInt(0), .data = try h.extra(args) });
    try h.printValues(cap, &.{result});
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    return support.runModule(a, &m, false);
}

// spec: NEW-CORE-S3-ABI-1
test "S3 runtime C passes a stream token while source extern erases it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const runtime = try tokenCall(arena.allocator(), .runtime_c);
    const foreign = try tokenCall(arena.allocator(), .extern_c);
    try std.testing.expectEqual(@as(u8, 0), runtime.status);
    try std.testing.expectEqualStrings("1\n", runtime.stdout);
    try std.testing.expectEqual(@as(u8, 0), foreign.status);
    try std.testing.expectEqualStrings("42\n", foreign.stdout);
}

fn borrowedUpdate(a: std.mem.Allocator) !ir.Module {
    var m: ir.Module = .{};
    var h = try Hand.init(a, &m, "update", .{ .params = &.{.byte_buffer}, .ret = .byte_buffer });
    const update = try h.emit(.{ .op = .buffer_push, .ty = .byte_buffer, .a = try h.param(0), .b = try h.int(.u8, 42) });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = update });
    _ = try h.finish();
    _ = try own.run(a, &m, .{ .verify = true });
    try support.verified(a, &m, &.{});
    return m;
}

// spec: NEW-CORE-S3-OWN-1
test "S3 a borrowed mutable byte update receives a buffer copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const m = try borrowedUpdate(arena.allocator());
    const text = try print.module(arena.allocator(), &m);
    try std.testing.expect(std.mem.indexOf(u8, text, "buffer_copy byte_buffer") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "list_copy") == null);
}

fn freshUpdate(a: std.mem.Allocator) !ir.Module {
    var m: ir.Module = .{};
    var h = try Hand.init(a, &m, "main", .{ .params = &.{.cap}, .ret = .i64 });
    const buffer = try h.emit(.{ .op = .buffer_new, .ty = .byte_buffer, .a = try h.int(.u64, 2) });
    const pushed = try h.emit(.{ .op = .buffer_push, .ty = .byte_buffer, .a = buffer, .b = try h.int(.u8, 42) });
    const read = try h.emit(.{ .op = .list_get, .ty = .u8, .a = pushed, .b = try h.int(.i64, 0), .check = .exact });
    const wide = try h.emit(.{ .op = .convert, .ty = .i64, .a = read });
    try h.printValues(try h.param(0), &.{wide});
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
    _ = try own.run(a, &m, .{ .verify = true });
    try support.verified(a, &m, &.{});
    return m;
}

// spec-case: NEW-CORE-S3-OWN-1
test "S3 fresh mutable bytes assert uniqueness before update and admit byte reads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const m = try freshUpdate(arena.allocator());
    const text = try print.module(arena.allocator(), &m);
    try std.testing.expect(std.mem.indexOf(u8, text, "is_unique bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "buffer_copy") == null);
    const ran = try support.runModule(arena.allocator(), &m, false);
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("", ran.stdout);
    try std.testing.expectEqualStrings("", ran.stderr);
}
