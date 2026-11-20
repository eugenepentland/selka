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
    \\    mut values: int[] = []
    \\    for j in range(n):
    \\        append(mut values, j % 100)
    \\    mut total = 0
    \\    for j in range(n):
    \\        total += values[j] * 3
    \\    print(out, total)
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

// A `const` borrow of an optional place (`const entry = by_ref[key]`) lowers to an option of a
// borrowed payload: a nullable view the verifier admits wherever it appears, while a list that
// would store one is still refused, and the refusal names the type.
// spec-case: NEW-CORE-S2-IR-1
test "the verifier admits a borrowed optional local and refuses a list that stores one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var good: ir.Module = .{};
    const record = try good.intern(a, .{ .record = &.{ .bytes, .i64 } });
    _ = try good.option(a, try good.intern(a, .{ .borrowed = record }));
    try support.verified(a, &good, &.{});
    var bad: ir.Module = .{};
    const stored_record = try bad.intern(a, .{ .record = &.{ .bytes, .i64 } });
    const stored = try bad.option(a, try bad.intern(a, .{ .borrowed = stored_record }));
    _ = try bad.intern(a, .{ .list = stored });
    var failure: verify_ir.Failure = .{};
    try std.testing.expectError(error.InvalidIr, verify(a, &bad, &failure));
    try std.testing.expect(std.mem.indexOf(u8, failure.reason, "list[option[borrowed[") != null);
}

/// Whether verifying `module` fails with a reason containing `expected`.
/// Whether the gate's check (the union-tag rule refusing) refuses `module` for `expected`.
fn refusedFor(arena: std.mem.Allocator, module: *const ir.Module, expected: []const u8) !bool {
    var failure: verify_ir.Failure = .{};
    verify_ir.verifyModuleWith(arena, module, &failure, .{ .mode = .refuse }) catch |err| return err == error.InvalidIr and std.mem.indexOf(u8, failure.reason, expected) != null;
    return false;
}

// The Lean copy of the verifier (`proofs/verify_ir`) found that constants and parameters, which no block lists, were never
// checked: a parameter read at another type than its signature's, or a constant of a type its operation does not make,
// reached the uses unchecked (proofs/verify_ir/NOTES.md, findings).
test "the verifier checks every constant and parameter of the table, and refuses an entry with predecessors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var entry: ir.Module = .{};
    try diamond(a, &entry, false);
    try entry.functions.items[0].blocks.items[0].preds.append(a, @fromBackingInt(0));
    try std.testing.expect(try refusedFor(a, &entry, "the entry block has predecessors"));
    var param: ir.Module = .{};
    try diamond(a, &param, false);
    // Parameter 0 is a `bool`.
    try param.functions.items[0].insts.append(a, .{ .op = .param, .ty = .i64, .data = 0 });
    try std.testing.expect(try refusedFor(a, &param, "param does not match its signature"));
    var text: ir.Module = .{};
    try diamond(a, &text, false);
    try text.functions.items[0].insts.append(a, .{ .op = .str_const, .ty = .i64 });
    try std.testing.expect(try refusedFor(a, &text, "str_const does not match its signature"));
    var callable: ir.Module = .{};
    try diamond(a, &callable, false);
    const function_type = try callable.intern(a, .{ .@"fn" = .{ .params = &.{}, .ret = .i64 } });
    try callable.functions.items[0].insts.append(a, .{ .op = .undef, .ty = function_type });
    try std.testing.expect(try refusedFor(a, &callable, "undef does not match its signature"));
    var stream: ir.Module = .{};
    try diamond(a, &stream, false);
    try stream.functions.items[0].insts.append(a, .{ .op = .iconst, .ty = .cap, .data = 1 });
    var failure: verify_ir.Failure = .{};
    try verify(a, &stream, &failure);
}

// The differential's robustness mutants: each made the Zig verifier panic or loop before (a copy chain that leaves the table
// or comes back to itself, a block whose last reference is out of range, a type the table does not have).
test "malformed tables are refused with a reason, never crashed or looped on" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var cycle: ir.Module = .{};
    try diamond(a, &cycle, false);
    const f = &cycle.functions.items[0];
    const first: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.appendSlice(a, &.{ .{ .op = .copy, .ty = .i64, .a = @fromBackingInt(@intCast(first.index() + 1)) }, .{ .op = .copy, .ty = .i64, .a = first } });
    const returned = f.blocks.items[2].insts.items[1];
    f.insts.items[returned.index()].a = first;
    try std.testing.expect(try refusedFor(a, &cycle, "forwards to nothing"));
    var nothing: ir.Module = .{};
    try diamond(a, &nothing, false);
    const g = &nothing.functions.items[0];
    try g.insts.append(a, .{ .op = .copy, .ty = .i64 });
    g.insts.items[g.blocks.items[2].insts.items[1].index()].a = @fromBackingInt(@intCast(g.insts.items.len - 1));
    try std.testing.expect(try refusedFor(a, &nothing, "forwards to nothing"));
    var listed: ir.Module = .{};
    try diamond(a, &listed, false);
    listed.functions.items[0].blocks.items[0].insts.items[0] = @fromBackingInt(999);
    try std.testing.expect(try refusedFor(a, &listed, "block lists an instruction that does not exist"));
    var table: ir.Module = .{};
    try diamond(a, &table, false);
    _ = try table.intern(a, .{ .list = @fromBackingInt(999) });
    try std.testing.expect(try refusedFor(a, &table, "names a type the module does not have"));
    var typed: ir.Module = .{};
    try diamond(a, &typed, false);
    const h = &typed.functions.items[0];
    try h.insts.append(a, .{ .op = .add, .ty = @fromBackingInt(999) });
    h.insts.items[h.blocks.items[2].insts.items[1].index()].a = @fromBackingInt(@intCast(h.insts.items.len - 1));
    try std.testing.expect(try refusedFor(a, &typed, "has no type of the module"));
}

// The fact certificate describes a constant that a block lists as an instruction of that block, and every field of `a` and
// `b` as a register the instruction reads; the SSA hypothesis of the fact proof (`ModWf`) is about that description
// (proofs/verify_ir, `SsaProof.lean`). So a listed constant's uses follow dominance, and an operation that reads only its
// extra list has nothing in `a` or `b`.
test "a listed constant is used where it dominates, and a print carries nothing in a or b" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var listed: ir.Module = .{};
    try diamond(a, &listed, false);
    const f = &listed.functions.items[0];
    // The `then` block reads constant 1 in its `add`; listing that constant after the `add` puts its definition after the use.
    const added = f.blocks.items[1].insts.items[0];
    const one = f.insts.items[added.index()].a;
    try f.blocks.items[1].insts.insert(a, 1, one);
    try std.testing.expect(try refusedFor(a, &listed, "is used before its definition"));
    var unlisted: ir.Module = .{};
    try diamond(a, &unlisted, false);
    var failure: verify_ir.Failure = .{};
    try verify(a, &unlisted, &failure);
    var m: ir.Module = .{};
    var h = try Hand.init(a, &m, "p", .{ .params = try a.dupe(ir.Type, &.{.cap}), .ret = .void });
    const stream = try h.param(0);
    const value = try h.int(.i64, 3);
    try h.printValues(stream, &.{value});
    _ = try h.emit(.{ .op = .ret, .ty = .void });
    _ = try h.finish();
    try verify(a, &m, &failure);
    m.functions.items[0].insts.items[m.functions.items[0].blocks.items[0].insts.items[0].index()].a = value;
    try std.testing.expect(try refusedFor(a, &m, "print reads no operand in a or b"));
}

// A span argument stands for a text or bytes parameter only: the function-value lemma (proofs/verify_ir, `FnProof.lean`)
// needs a list-view parameter, which may hold function values, to receive a list view of its own type.
test "a text span is not an argument for a list-view parameter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m: ir.Module = .{};
    const view = try m.intern(a, .{ .list_view = .i64 });
    var callee = try Hand.init(a, &m, "takes_view", .{ .params = try a.dupe(ir.Type, &.{view}), .ret = .void });
    _ = try callee.emit(.{ .op = .ret, .ty = .void });
    const index = try callee.finish();
    var caller = try Hand.init(a, &m, "passes_text", .{ .params = try a.dupe(ir.Type, &.{.str_view}), .ret = .void });
    const text = try caller.param(0);
    _ = try caller.emit(.{ .op = .call, .ty = .void, .a = @fromBackingInt(index), .data = try caller.extra(&.{text}) });
    _ = try caller.emit(.{ .op = .ret, .ty = .void });
    _ = try caller.finish();
    try std.testing.expect(try refusedFor(a, &m, "call does not match its signature"));
}

/// `f(a, b: Option[i64]) -> i64`: when `swapped`, the read of `a`'s payload is on the false edge of its tag test; when
/// `equality`, the tags of `a` and `b` are compared first and the payload read is of `b` under the test of `a`'s tag.
fn optionRead(arena: std.mem.Allocator, module: *ir.Module, swapped: bool, equality: bool) !void {
    const option = try module.option(arena, .i64);
    var h = try Hand.init(arena, module, "read", .{ .params = try arena.dupe(ir.Type, &.{ option, option }), .ret = .i64 });
    const a = try h.param(0);
    const b = try h.param(1);
    const some = try h.newBlock();
    const read = try h.newBlock();
    const none = try h.newBlock();
    const tag_a = try h.emit(.{ .op = .union_tag, .ty = .u32, .a = a });
    if (equality) {
        const tag_b = try h.emit(.{ .op = .union_tag, .ty = .u32, .a = b });
        try h.branch(try h.emit(.{ .op = .cmp, .ty = .bool, .a = tag_a, .b = tag_b, .data = @backingInt(ir.Predicate.eq) }), some, none);
    } else try h.jump(some);
    h.block = some;
    const is_some = try h.emit(.{ .op = .cmp, .ty = .bool, .a = tag_a, .b = try h.int(.u32, 1), .data = @backingInt(ir.Predicate.eq) });
    if (swapped) try h.branch(is_some, none, read) else try h.branch(is_some, read, none);
    h.block = read;
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.emit(.{ .op = .union_payload, .ty = .i64, .a = if (equality) b else a, .data = 1 }) });
    h.block = none;
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
}

// F-VL-10 (proofs/verify_ir, `FnProof.lean`): a union payload is read only under its own tag, as the tag facts of
// `verify_union_tags.zig` justify it, including through the equality of two tags.
test "a union payload is read under a test of its own tag, or through the equality of two tags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: verify_ir.Failure = .{};
    var guarded: ir.Module = .{};
    try optionRead(a, &guarded, false, false);
    try verify(a, &guarded, &failure);
    var unguarded: ir.Module = .{};
    try optionRead(a, &unguarded, true, false);
    try std.testing.expect(try refusedFor(a, &unguarded, "union payload read without a test of its tag"));
    var equal: ir.Module = .{};
    try optionRead(a, &equal, false, true);
    try verify(a, &equal, &failure);
    var unequal: ir.Module = .{};
    try optionRead(a, &unequal, true, true);
    try std.testing.expect(try refusedFor(a, &unequal, "union payload read without a test of its tag"));
}

/// A union of 70 `i64` cases tested for case `case` and read at that case (or, `swapped`, on the test's false side).
fn wideRead(arena: std.mem.Allocator, module: *ir.Module, case: u32, swapped: bool) !void {
    const cases = try arena.alloc(ir.Type, 70);
    @memset(cases, .i64);
    const wide = try module.intern(arena, .{ .@"union" = cases });
    var h = try Hand.init(arena, module, "wide", .{ .params = try arena.dupe(ir.Type, &.{wide}), .ret = .i64 });
    const value = try h.param(0);
    const read = try h.newBlock();
    const other = try h.newBlock();
    const tag = try h.emit(.{ .op = .union_tag, .ty = .u32, .a = value });
    const is_case = try h.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try h.int(.u32, case), .data = @backingInt(ir.Predicate.eq) });
    if (swapped) try h.branch(is_case, other, read) else try h.branch(is_case, read, other);
    h.block = read;
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.emit(.{ .op = .union_payload, .ty = .i64, .a = value, .data = case }) });
    h.block = other;
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
}

// F-VL-10: the sets of cases have any width, so a read of case 69 of a 70-case union is checked like a small union's.
test "a union of more than 64 cases is read under a test of its own tag" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: verify_ir.Failure = .{};
    var last: ir.Module = .{};
    try wideRead(a, &last, 69, false);
    try verify(a, &last, &failure);
    var first_wide: ir.Module = .{};
    try wideRead(a, &first_wide, 64, false);
    try verify(a, &first_wide, &failure);
    var swapped: ir.Module = .{};
    try wideRead(a, &swapped, 69, true);
    try std.testing.expect(try refusedFor(a, &swapped, "union payload read without a test of its tag"));
}

/// The three place shapes of the union-tag rule (F-VL-10), each read at case 1 of an `i64` option. `field`: a record of
/// two options tested at field 0 and read at field 0 again (`wrong`: read at field 1). `store`: a record whose field 0 is set
/// to `Some(5)` and read back (`wrong`: read back from field 1). `merge`: a `phi` of a parameter tested `Some` and a
/// `Some(5)` on two paths after the test (`wrong`: the second is `None`).
fn placeRead(arena: std.mem.Allocator, module: *ir.Module, shape: enum { field, store, merge }, wrong: bool) !void {
    const option = try module.option(arena, .i64);
    const pair = try module.intern(arena, .{ .record = try arena.dupe(ir.Type, &.{ option, option }) });
    var h = try Hand.init(arena, module, "place", .{ .params = try arena.dupe(ir.Type, &.{ pair, option }), .ret = .i64 });
    const record = try h.param(0);
    const value = try h.param(1);
    const read = try h.newBlock();
    const other = try h.newBlock();
    const join = try h.newBlock();
    const none_case = wrong and shape == .merge;
    const some = try h.emit(.{ .op = .union_make, .ty = option, .a = if (none_case) .none else try h.int(.i64, 5), .data = if (none_case) 0 else 1 });
    const read_field: u64 = if (wrong and shape != .merge) 1 else 0;
    switch (shape) {
        .field => {
            const tag = try h.emit(.{ .op = .union_tag, .ty = .u32, .a = try h.emit(.{ .op = .record_get, .ty = option, .a = record, .data = 0 }) });
            try h.branch(try h.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try h.int(.u32, 1), .data = @backingInt(ir.Predicate.eq) }), read, other);
            h.block = read;
            try h.jump(join);
            h.block = join;
            const again = try h.emit(.{ .op = .record_get, .ty = option, .a = record, .data = read_field });
            _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.emit(.{ .op = .union_payload, .ty = .i64, .a = again, .data = 1 }) });
        },
        .store => {
            const stored = try h.emit(.{ .op = .record_set, .ty = pair, .a = record, .b = some, .data = 0 });
            try h.jump(read);
            h.block = read;
            try h.jump(join);
            h.block = join;
            const back = try h.emit(.{ .op = .record_get, .ty = option, .a = stored, .data = read_field });
            _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.emit(.{ .op = .union_payload, .ty = .i64, .a = back, .data = 1 }) });
            h.block = other;
            try h.jump(join);
        },
        .merge => {
            // The parameter is tested `Some` first; then one path keeps it and the other replaces it with `Some(5)`.
            const tag = try h.emit(.{ .op = .union_tag, .ty = .u32, .a = value });
            try h.branch(try h.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try h.int(.u32, 1), .data = @backingInt(ir.Predicate.eq) }), read, other);
            h.block = other;
            _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
            const keep = try h.newBlock();
            const replace = try h.newBlock();
            h.block = read;
            try h.branch(try h.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try h.int(.u32, 2), .data = @backingInt(ir.Predicate.eq) }), keep, replace);
            h.block = keep;
            try h.jump(join);
            h.block = replace;
            try h.jump(join);
            h.block = join;
            const merged = try h.emit(.{ .op = .phi, .ty = option, .data = try h.extra(&.{ value, some }) });
            _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.emit(.{ .op = .union_payload, .ty = .i64, .a = merged, .data = 1 }) });
        },
    }
    if (shape == .field) {
        h.block = other;
        _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    }
    _ = try h.finish();
}

// F-VL-10, shapes R, S and P (the protobuf decoders' `if m.f is None: ...` then `match mut m.f`, a field stored and read
// back, and the port's `match mut best` after a tested parameter): each is accepted, and each with the read on another
// field, or the merged value of another case, is refused.
test "a union payload read through a field read twice, a field stored and read back, or a merge of known cases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: verify_ir.Failure = .{};
    var field: ir.Module = .{};
    try placeRead(a, &field, .field, false);
    try verify(a, &field, &failure);
    var store: ir.Module = .{};
    try placeRead(a, &store, .store, false);
    try verify(a, &store, &failure);
    var merge: ir.Module = .{};
    try placeRead(a, &merge, .merge, false);
    try verify(a, &merge, &failure);
    var other_field: ir.Module = .{};
    try placeRead(a, &other_field, .field, true);
    try std.testing.expect(try refusedFor(a, &other_field, "union payload read without a test of its tag"));
    var other_store: ir.Module = .{};
    try placeRead(a, &other_store, .store, true);
    try std.testing.expect(try refusedFor(a, &other_store, "union payload read without a test of its tag"));
    var other_merge: ir.Module = .{};
    try placeRead(a, &other_merge, .merge, true);
    try std.testing.expect(try refusedFor(a, &other_merge, "union payload read without a test of its tag"));
}

/// A loop `phi` joins two options in block 1, block 2 reads the tag, block 3 tests it and block 4 reads the payload (with
/// `swapped`, on the test's false side); with `looped` the test's false side goes back to block 1, which makes the phi again
/// and block 2 reads its tag again before the next test.
fn loopTagRead(arena: std.mem.Allocator, module: *ir.Module, looped: bool, swapped: bool) !void {
    const option = try module.option(arena, .i64);
    var h = try Hand.init(arena, module, "loop", .{ .params = try arena.dupe(ir.Type, &.{ option, option }), .ret = .i64 });
    const a = try h.param(0);
    const b = try h.param(1);
    const head = try h.newBlock();
    const tag_block = try h.newBlock();
    const test_block = try h.newBlock();
    const read = try h.newBlock();
    const back = try h.newBlock();
    try h.jump(head);
    h.block = head;
    const joined = try h.emit(.{ .op = .phi, .ty = option, .data = try h.extra(if (looped) &.{ a, b } else &.{a}) });
    try h.jump(tag_block);
    h.block = tag_block;
    const tag = try h.emit(.{ .op = .union_tag, .ty = .u32, .a = joined });
    try h.jump(test_block);
    h.block = test_block;
    const is_some = try h.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try h.int(.u32, 1), .data = @backingInt(ir.Predicate.eq) });
    if (swapped) try h.branch(is_some, back, read) else try h.branch(is_some, read, back);
    h.block = read;
    _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.emit(.{ .op = .union_payload, .ty = .i64, .a = joined, .data = 1 }) });
    h.block = back;
    if (looped) try h.jump(head) else _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
    _ = try h.finish();
}

// F-VL-10: a tag read in another block than its value's counts while no block has made the value again since the read
// (the fresh tag reads are a must-fact of their own), in a loop as on a straight path.
test "a tag read away from its value's block counts while the value is not made again after it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: verify_ir.Failure = .{};
    var straight: ir.Module = .{};
    try loopTagRead(a, &straight, false, false);
    try verify(a, &straight, &failure);
    var looped: ir.Module = .{};
    try loopTagRead(a, &looped, true, false);
    try verify(a, &looped, &failure);
    var false_side: ir.Module = .{};
    try loopTagRead(a, &false_side, true, true);
    try std.testing.expect(try refusedFor(a, &false_side, "union payload read without a test of its tag"));
}

// D-VL-18: an unjustified union payload read is a verdict of its own, so whether a check refuses it or counts it is one
// option. Refusing (the builds' mode today, and always `selka verify-ir`) names the read; counting accepts the function and
// adds the read to the count.
test "an unjustified union payload read is refused or counted by the check's mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var report: std.ArrayList(u8) = .empty;
    var unguarded: ir.Module = .{};
    try optionRead(a, &unguarded, true, false);
    try std.testing.expectError(error.InvalidIr, verify_ir.checkPresent(a, &unguarded, .{ .union_tags = .{ .mode = .refuse } }, &report));
    try std.testing.expect(std.mem.indexOf(u8, report.items, "union payload read without a test of its tag") != null);
    var counted: usize = 0;
    try verify_ir.checkPresent(a, &unguarded, .{ .union_tags = .{ .mode = .count, .counted = &counted } }, &report);
    try std.testing.expectEqual(@as(usize, 1), counted);
    var guarded: ir.Module = .{};
    try optionRead(a, &guarded, false, false);
    var none: usize = 0;
    try verify_ir.checkPresent(a, &guarded, .{ .union_tags = .{ .mode = .count, .counted = &none } }, &report);
    try std.testing.expectEqual(@as(usize, 0), none);
}

/// Runs the calling test only while builds count unjustified union payload reads (`verify_union_tags.build_mode`).
fn requireCountingBuilds() error{SkipZigTest}!void {
    if (union_tags.build_mode != .count) return error.SkipZigTest;
}

/// Runs the calling test only once builds refuse unjustified union payload reads.
fn requireRefusingBuilds() error{SkipZigTest}!void {
    if (union_tags.build_mode != .refuse) return error.SkipZigTest;
}

const union_tags = @import("verify_union_tags.zig");

// D-VL-18 ("Count for now"): a build's check (the default `Present`, as `pipeline.zig` calls it) accepts a module with an
// unjustified union payload read and counts it, and `selka verify-ir` (the gate's check) refuses the same module.
test "a build counts an unjustified union payload read and selka verify-ir refuses it" {
    try requireCountingBuilds();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var report: std.ArrayList(u8) = .empty;
    var unguarded: ir.Module = .{};
    try optionRead(a, &unguarded, true, false);
    var counted: usize = 0;
    try verify_ir.checkPresent(a, &unguarded, .{ .union_tags = .{ .counted = &counted } }, &report);
    try std.testing.expectEqual(@as(usize, 1), counted);
    try @import("pipeline.zig").reportUnionTags(a, counted, &report);
    try std.testing.expect(std.mem.indexOf(u8, report.items, "selka: union-tags: 1 payload reads not justified") != null);
    var counts: @import("verify_ir_commands.zig").Counts = .{};
    var lines: std.ArrayList(u8) = .empty;
    const sink: @import("verify_ir_commands.zig").Sink = .{ .work = a, .keep = a, .counts = &counts, .out = &lines };
    try @import("verify_ir_commands.zig").checkText(sink, "unguarded.core-ir", try @import("ir_text.zig").render(a, &unguarded));
    try std.testing.expect(std.mem.indexOf(u8, lines.items, "reject union-tag") != null);
}

// The same module once builds refuse (D-VL-18's later step: `build_mode = .refuse`): a build's check refuses it.
test "builds refuse an unjustified union payload read when the build mode refuses" {
    try requireRefusingBuilds();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var report: std.ArrayList(u8) = .empty;
    var unguarded: ir.Module = .{};
    try optionRead(a, &unguarded, true, false);
    try std.testing.expectError(error.InvalidIr, verify_ir.checkPresent(a, &unguarded, .{}, &report));
    try std.testing.expect(std.mem.indexOf(u8, report.items, "union payload read without a test of its tag") != null);
}

test "a demand build's check skips only the bodies it does not hold, and functionHolds judges one body" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var report: std.ArrayList(u8) = .empty;
    var open: ir.Module = .{};
    try diamond(a, &open, false);
    // The one function's last block loses its terminator: a body the build holds is checked and refused.
    _ = open.functions.items[0].blocks.items[2].insts.pop();
    try std.testing.expectError(error.InvalidIr, verify_ir.checkPresent(a, &open, .{ .present = &.{true} }, &report));
    try std.testing.expect(std.mem.indexOf(u8, report.items, "does not end in a terminator") != null);
    try std.testing.expect(!try verify_ir.functionHolds(a, &open, 0));
    // A body the build does not hold was checked by the build that made its record, together with its declaration.
    try verify_ir.checkPresent(a, &open, .{ .present = &.{false}, .tables = false }, &report);
    var whole: ir.Module = .{};
    try diamond(a, &whole, false);
    try std.testing.expect(try verify_ir.functionHolds(a, &whole, 0));
}

/// The walk `verify_ir.holdsFunctionType` replaced (BUILDHANG), kept as the reference its verdict must equal: no visited set,
/// only the depth bound, so on a recursive union it walks every path. `expanded` counts the compounds it walks.
fn holdsFunctionByDepth(module: *const ir.Module, ty: ir.Type, depth: usize, expanded: *usize) bool {
    if (depth > module.compounds.items.len or !module.valid(ty) or module.kind(ty) == null) return false;
    expanded.* += 1;
    return switch (module.compound(ty)) {
        .@"fn" => true,
        .record, .@"union" => |parts| for (parts) |part| {
            if (holdsFunctionByDepth(module, part, depth + 1, expanded)) break true;
        } else false,
        .array => |array| holdsFunctionByDepth(module, array.elem, depth + 1, expanded),
        .box, .list, .list_view, .borrowed => |inner| holdsFunctionByDepth(module, inner, depth + 1, expanded),
        .dict => |dict| holdsFunctionByDepth(module, dict.key, depth + 1, expanded) or
            holdsFunctionByDepth(module, dict.value, depth + 1, expanded),
    };
}

/// What `holdsFunctionType` answered for one type, and how many compounds it walked.
const Holds = struct { verdict: bool, expanded: usize };

fn holdsWithSeen(a: std.mem.Allocator, module: *const ir.Module, ty: ir.Type) !Holds {
    var seen = try std.DynamicBitSetUnmanaged.initEmpty(a, module.compounds.items.len);
    var expanded: usize = 0;
    const verdict = verify_ir.holdsFunctionType(module, ty, &seen, 0, &expanded);
    return .{ .verdict = verdict, .expanded = expanded };
}

/// Every compound of `module`, and a few scalars: the visited walk gives the reference's verdict and walks each compound at
/// most once. Returns how many types held a function.
fn expectSameVerdicts(a: std.mem.Allocator, module: *const ir.Module) !usize {
    var holding: usize = 0;
    const scalars = [_]ir.Type{ .i64, .bool, .str, .void };
    for (scalars) |ty| try std.testing.expect(!(try holdsWithSeen(a, module, ty)).verdict);
    for (0..module.compounds.items.len) |i| {
        const ty: ir.Type = @fromBackingInt(@intCast(ir.Type.first_compound + i));
        var reference_expanded: usize = 0;
        const reference = holdsFunctionByDepth(module, ty, 0, &reference_expanded);
        const holds = try holdsWithSeen(a, module, ty);
        try std.testing.expectEqual(reference, holds.verdict);
        try std.testing.expect(holds.expanded <= module.compounds.items.len);
        holding += @intFromBool(holds.verdict);
    }
    return holding;
}

/// The recursive union of the BUILDHANG repro, by hand: `Value` is a leaf, `arms` cases `arm(items: Value[])` and
/// `object(keys: str[], vals: Value[])`, with `padding` unrelated nested list types after it that raise the depth bound.
/// With `callback`, `object` also holds a function, so every type on the cycle holds one.
fn recursiveValue(a: std.mem.Allocator, module: *ir.Module, arms: usize, padding: usize, callback: bool) !ir.Type {
    const value: ir.Type = @fromBackingInt(@intCast(ir.Type.first_compound + module.compounds.items.len));
    try module.compounds.append(a, .{ .@"union" = &.{} });
    const values = try module.intern(a, .{ .list = value });
    const keys = try module.intern(a, .{ .list = .str });
    var cases: std.ArrayList(ir.Type) = .empty;
    try cases.append(a, .i64);
    for (0..arms) |_| {
        const arm: ir.Type = @fromBackingInt(@intCast(ir.Type.first_compound + module.compounds.items.len));
        try module.compounds.append(a, .{ .record = try a.dupe(ir.Type, &.{values}) });
        try cases.append(a, try module.intern(a, .{ .box = arm }));
    }
    const function = try module.intern(a, .{ .@"fn" = .{ .params = &.{.i64}, .ret = .i64 } });
    const fields: []const ir.Type = if (callback) &.{ keys, values, function } else &.{ keys, values };
    try cases.append(a, try module.intern(a, .{ .box = try module.intern(a, .{ .record = fields }) }));
    module.compounds.items[@backingInt(value) - ir.Type.first_compound] = .{ .@"union" = cases.items };
    var nested: ir.Type = .i64;
    for (0..padding) |_| nested = try module.intern(a, .{ .list = nested });
    return value;
}

/// A function `hold() -> void` whose body is one `undef` of `ty`: the verifier's `holdsFunction` question on `ty`.
fn undefOf(a: std.mem.Allocator, module: *ir.Module, ty: ir.Type) !void {
    var hand = try Hand.init(a, module, "hold", .{ .params = &.{}, .ret = .void });
    _ = try hand.emit(.{ .op = .undef, .ty = ty });
    _ = try hand.emit(.{ .op = .ret, .ty = .void });
    _ = try hand.finish();
}

// BUILDHANG: `holdsFunction` walked a recursive union's every path, exponential in the module's compounds.
test "the verifier's function-holding walk gives the depth-bounded walk's verdict on every compound of built modules" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    const callbacks = try support.buildSource(a,
        \\record Handler:
        \\    callback: func(int) -> int
        \\
        \\enum Tree:
        \\    leaf(n: int)
        \\    node(kids: Tree[], handler: Handler)
        \\
        \\func twice(value: int) -> int:
        \\    return value * 2
        \\
        \\func main() -> int:
        \\    const handlers = [Handler(callback=twice)]
        \\    const tree = Tree.node(kids=[Tree.leaf(n=1)], handler=handlers[0])
        \\    match tree:
        \\        case node(kids, handler):
        \\            const callback = handler.callback
        \\            return callback(len(kids))
        \\        case _:
        \\            return 0
    , &refusal);
    try std.testing.expect(try expectSameVerdicts(a, &callbacks) > 0);
    const values = try support.buildSource(a,
        \\import lists
        \\
        \\enum Value:
        \\    leaf(n: int)
        \\    arm0(items: Value[])
        \\    arm1(items: Value[])
        \\    object(keys: str[], vals: Value[])
        \\
        \\func del_keys(mut t: Value, keys: str[]):
        \\    match mut t:
        \\        case object(keys=names, vals):
        \\            for k in keys:
        \\                if len(names) > 0 and names[0] == k:
        \\                    _ = lists.pop_at(mut names, 0)
        \\                    _ = lists.pop_at(mut vals, 0)
        \\        case _:
        \\            pass
        \\
        \\func main() -> int:
        \\    mut t = Value.object(keys=["a", "b"], vals=[Value.leaf(n=1), Value.leaf(n=2)])
        \\    del_keys(mut t, ["a"])
        \\    const deep: int[][][][][][][][][][][][] = []
        \\    return len(deep)
    , &refusal);
    _ = try expectSameVerdicts(a, &values);
    var hand_built: ir.Module = .{};
    _ = try recursiveValue(a, &hand_built, 2, 6, false);
    _ = try recursiveValue(a, &hand_built, 1, 0, true);
    _ = try hand_built.intern(a, .{ .dict = .{ .key = .str, .value = try hand_built.intern(a, .{ .array = .{ .elem = .i64, .n = 4 } }) } });
    const function = try hand_built.intern(a, .{ .@"fn" = .{ .params = &.{}, .ret = .void } });
    _ = try hand_built.intern(a, .{ .dict = .{ .key = .str, .value = function } });
    _ = try hand_built.intern(a, .{ .borrowed = try hand_built.intern(a, .{ .list_view = function }) });
    _ = try hand_built.intern(a, .{ .array = .{ .elem = function, .n = 2 } });
    try std.testing.expect(try expectSameVerdicts(a, &hand_built) > 0);
}

// BUILDHANG: the counter the fix is held to; the old walk's own count on the same union shows the blow-up it had.
test "the verifier walks each compound at most once to see whether a recursive union holds a function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var small: ir.Module = .{};
    const small_value = try recursiveValue(a, &small, 2, 24, false);
    const holds = try holdsWithSeen(a, &small, small_value);
    try std.testing.expect(!holds.verdict);
    try std.testing.expect(holds.expanded <= small.compounds.items.len);
    var reference_expanded: usize = 0;
    try std.testing.expect(!holdsFunctionByDepth(&small, small_value, 0, &reference_expanded));
    try std.testing.expect(reference_expanded > 100 * small.compounds.items.len);
    // At 200 nested types the old walk did not finish; the verifier now admits the `undef` at once and still refuses one
    // whose union holds a function behind the cycle.
    var large: ir.Module = .{};
    const large_value = try recursiveValue(a, &large, 3, 200, false);
    const large_holds = try holdsWithSeen(a, &large, large_value);
    try std.testing.expect(!large_holds.verdict);
    try std.testing.expect(large_holds.expanded <= large.compounds.items.len);
    try undefOf(a, &large, large_value);
    try support.verified(a, &large, &.{});
    var holding: ir.Module = .{};
    const holding_value = try recursiveValue(a, &holding, 3, 200, true);
    try std.testing.expect((try holdsWithSeen(a, &holding, holding_value)).verdict);
    try undefOf(a, &holding, holding_value);
    var failure: verify_ir.Failure = .{};
    try std.testing.expectError(error.InvalidIr, verify(a, &holding, &failure));
}
