//! The Core IR verifier: well-formed IR passes, and each kind of malformed IR is
//! rejected with the place and the reason.
const std = @import("std");
const ir = @import("ir.zig");
const verify_ir = @import("verify_ir.zig");
const support = @import("test_support.zig");

const Hand = support.Hand;

fn callbackComparison(a: std.mem.Allocator, module: *ir.Module, predicate: ir.Predicate) !void {
    const callback = try module.intern(a, .{ .@"fn" = .{ .params = &.{.i64}, .ret = .i64 } });
    const parameters = try a.dupe(ir.Type, &.{ callback, callback });
    var hand = try Hand.init(a, module, "compare", .{ .params = parameters, .ret = .bool });
    const result = try hand.emit(.{ .op = .cmp, .ty = .bool, .a = try hand.param(0), .b = try hand.param(1), .data = @backingInt(predicate) });
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = result });
    _ = try hand.finish();
}

// spec-case: FUNCTION-IDENTITY-1
test "same_function verifier admits callable equality and rejects pointer ordering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var good: ir.Module = .{};
    var bad: ir.Module = .{};
    var failure: verify_ir.Failure = .{};
    try callbackComparison(arena.allocator(), &good, .eq);
    try support.verified(arena.allocator(), &good, &.{});
    try callbackComparison(arena.allocator(), &bad, .lt);
    try std.testing.expectError(error.InvalidIr, verify(arena.allocator(), &bad, &failure));
}

/// `f(c: bool) -> i64`: `if c: x = 1 + 2` then a join that returns `x` or 0 through a phi.
/// With `broken`, the join reads `x` directly, which the else edge never defined.
fn diamond(arena: std.mem.Allocator, module: *ir.Module, broken: bool) !void {
    var h = try Hand.init(arena, module, "f", .{ .params = try arena.dupe(ir.Type, &.{.bool}), .ret = .i64 });
    const then = try h.newBlock();
    const join = try h.newBlock();
    try h.branch(try h.param(0), then, join);
    h.block = then;
    const x = try h.emit(.{ .op = .add, .ty = .i64, .a = try h.int(.i64, 1), .b = try h.int(.i64, 2) });
    try h.jump(join);
    h.block = join;
    // Predecessors of the join: the entry (else edge) first, then `then`.
    const merged = try h.emit(.{ .op = .phi, .ty = .i64, .data = try h.extra(&.{ try h.int(.i64, 0), x }) });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = if (broken) x else merged });
    _ = try h.finish();
}

fn verify(arena: std.mem.Allocator, module: *const ir.Module, failure: *verify_ir.Failure) verify_ir.Error!void {
    return verify_ir.verifyModule(arena, module, failure);
}

// spec: NEW-CORE-VERIFY-IR-1
test "the verifier accepts a well-formed diamond and rejects a use its definition does not dominate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var good: ir.Module = .{};
    try diamond(a, &good, false);
    var failure: verify_ir.Failure = .{};
    try verify(a, &good, &failure);
    var bad: ir.Module = .{};
    try diamond(a, &bad, true);
    try std.testing.expectError(error.InvalidIr, verify(a, &bad, &failure));
    try std.testing.expectEqual(@as(u32, 2), failure.block);
    try std.testing.expect(std.mem.indexOf(u8, failure.reason, "does not dominate its use in b2") != null);
    const rendered = try failure.render(a);
    try std.testing.expect(std.mem.startsWith(u8, rendered, "invalid Core IR in f b2 %"));
}

// spec-case: NEW-CORE-VERIFY-IR-1
test "the verifier rejects a phi without one operand per predecessor, a missing terminator and a use before its definition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: verify_ir.Failure = .{};
    var phi: ir.Module = .{};
    try diamond(a, &phi, false);
    // Drop the phi's second operand.
    const merged = phi.functions.items[0].blocks.items[2].insts.items[0];
    phi.functions.items[0].insts.items[merged.index()].data = (ir.ExtraSlice{ .start = 0, .len = 1 }).pack();
    try std.testing.expectError(error.InvalidIr, verify(a, &phi, &failure));
    try std.testing.expect(std.mem.indexOf(u8, failure.reason, "phi has 1 operands for 2 predecessors") != null);
    var open: ir.Module = .{};
    try diamond(a, &open, false);
    _ = open.functions.items[0].blocks.items[2].insts.pop();
    try std.testing.expectError(error.InvalidIr, verify(a, &open, &failure));
    try std.testing.expect(std.mem.indexOf(u8, failure.reason, "does not end in a terminator") != null);
    var order: ir.Module = .{};
    try diamond(a, &order, false);
    std.mem.swap(ir.Ref, &order.functions.items[0].blocks.items[2].insts.items[0], &order.functions.items[0].blocks.items[2].insts.items[1]);
    try std.testing.expectError(error.InvalidIr, verify(a, &order, &failure));
    try std.testing.expect(std.mem.indexOf(u8, failure.reason, "terminator before the end") != null);
}

// spec-case: NEW-CORE-VERIFY-IR-1
test "the verifier checks each operation's operand and result types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m: ir.Module = .{};
    const pair = try m.intern(a, .{ .record = &.{ .i64, .bool } });
    var h = try Hand.init(a, &m, "f", .{ .params = &.{}, .ret = .i64 });
    const r = try h.emit(.{ .op = .record_make, .ty = pair, .data = try h.extra(&.{ try h.int(.i64, 1), try h.int(.bool, 0) }) });
    // Field 1 is a bool, not an i64.
    const wrong = try h.emit(.{ .op = .record_get, .ty = .i64, .a = r, .data = 1 });
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = wrong });
    _ = try h.finish();
    var failure: verify_ir.Failure = .{};
    try std.testing.expectError(error.InvalidIr, verify(a, &m, &failure));
    try std.testing.expectEqualStrings("record_get does not match its signature", failure.reason);
    m.functions.items[0].insts.items[wrong.index()].data = 0;
    try verify(a, &m, &failure);
}

const reduction =
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = len(args) + 4096
    \\    mut values = [for j in range(n) yield j % 100]
    \\    mut total = 0
    \\    for j in range(n):
    \\        total += values[j] * 3
    \\    out.print(total)
    \\    return 0
    \\
;

// spec-case: NEW-CORE-VERIFY-IR-1
test "a vector plan that reads a loop value before the loop is rejected, as the S0 splat bug would have been" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, reduction, &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    const index = module.entry;
    try std.testing.expectEqual(@as(usize, 1), result.plans[index].len);
    var plan = result.plans[index][0];
    const f = &module.functions.items[index];
    var failure: verify_ir.Failure = .{};
    try verify_ir.verifyPlan(a, &module, f, plan, &failure);
    // The initial sum taken from a lane value (defined inside the loop) does not exist yet.
    plan.carried.acc_init = plan.body[0];
    try std.testing.expectError(error.InvalidIr, verify_ir.verifyPlan(a, &module, f, plan, &failure));
    try std.testing.expect(std.mem.indexOf(u8, failure.reason, "does not dominate its use") != null);
}

/// `f() -> void` with one `err_trace` of `mode`, naming a case string when `named`.
fn traceProgram(arena: std.mem.Allocator, module: *ir.Module, mode: u64, named: bool) !void {
    var h = try Hand.init(arena, module, "f", .{ .params = &.{}, .ret = .void });
    const case = if (named) try h.emit(.{ .op = .str_const, .ty = .str, .data = 0 }) else ir.Ref.none;
    _ = try h.emit(.{ .op = .err_trace, .ty = .void, .a = case, .data = mode, .span = 1 });
    _ = try h.emit(.{ .op = .ret, .ty = .void });
    _ = try h.finish();
}

// spec: NEW-CORE-VERIFY-IR-2
test "the verifier admits err_trace modes 0 to 4, with a case string only on converted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: verify_ir.Failure = .{};
    var returned: ir.Module = .{};
    try traceProgram(a, &returned, @backingInt(ir.TraceMode.returned), false);
    try verify(a, &returned, &failure);
    var converted: ir.Module = .{};
    try traceProgram(a, &converted, @backingInt(ir.TraceMode.converted), true);
    try verify(a, &converted, &failure);
    var unnamed: ir.Module = .{};
    try traceProgram(a, &unnamed, @backingInt(ir.TraceMode.converted), false);
    try std.testing.expectError(error.InvalidIr, verify(a, &unnamed, &failure));
    var unknown: ir.Module = .{};
    try traceProgram(a, &unknown, 5, false);
    try std.testing.expectError(error.InvalidIr, verify(a, &unknown, &failure));
}
