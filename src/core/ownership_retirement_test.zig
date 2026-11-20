//! The final ownership ABI has direct destruction and no reference-counting path.
const std = @import("std");
const ir = @import("ir.zig");
const build = @import("build.zig");
const driver = @import("driver.zig");
const support = @import("test_support.zig");
const counters = @import("emit_count.zig");
const language = @import("selka");

fn header() []const u8 {
    const end = std.mem.indexOf(u8, driver.runtime_source, "} myl_block;").?;
    const start = std.mem.lastIndexOf(u8, driver.runtime_source[0..end], "typedef struct {").?;
    return driver.runtime_source[start..end];
}

fn directDestruction(a: std.mem.Allocator, optimized: bool) !void {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a,
        \\import lists
        \\
        \\func main(out: Stream) -> int:
        \\    mut values = [[1, 2], [3, 4]]
        \\    const copied = copy(values)
        \\    lists.clear(mut values)
        \\    print(out, copied[0][1], copied[1][0])
        \\    return 0
    , &refusal);
    const result = if (optimized) try @import("passes.zig").run(a, &module, .verify) else try @import("passes.zig").debug(a, &module);
    const run = try support.runOwned(a, &module, .{ .own = false, .release = optimized, .verify = optimized, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 0), run.status);
    try std.testing.expectEqualStrings("2 3\n", run.stdout);
    try std.testing.expectEqualStrings("", run.stderr);
    const lowered = try @import("print.zig").module(a, &module);
    try std.testing.expect(std.mem.indexOf(u8, lowered, "drop ") != null);
    try std.testing.expect(std.mem.indexOf(u8, run.llvm, "@myl_core_retain") == null);
    try std.testing.expect(std.mem.indexOf(u8, run.llvm, "@myl_core_release") == null);
    try std.testing.expect(std.mem.indexOf(u8, run.llvm, "load atomic i32") == null);
    try std.testing.expect(std.mem.indexOf(u8, run.llvm, "myl.count") == null);
}

// spec: OWNERSHIP-RETIREMENT-1
test "ownership retirement removes RC operations modes snapshot and instrumentation kinds" {
    try std.testing.expect(std.meta.stringToEnum(ir.Op, "retain") == null);
    try std.testing.expect(std.meta.stringToEnum(ir.Op, "release") == null);
    try std.testing.expect(std.meta.stringToEnum(ir.Op, "is_unique") == null);
    try std.testing.expect(std.meta.stringToEnum(ir.Op, "drop") != null);
    try std.testing.expect(!@hasField(ir.Module, "single_owner"));
    try std.testing.expect(!@hasField(ir.Module, "zero_rc"));
    try std.testing.expect(!@hasField(build.Input, "single_owner"));
    try std.testing.expect(!@hasField(build.Input, "zero_rc"));
    const codegen = @import("pipeline.zig").Codegen;
    try std.testing.expect(!@hasField(codegen, "single_owner"));
    try std.testing.expect(!@hasField(codegen, "zero_rc"));
    const contract = @import("single_owner.zig");
    try std.testing.expect(!@hasDecl(contract, "checkMode"));
    try std.testing.expect(!@hasDecl(contract, "validateMode"));
    try std.testing.expect(!@hasDecl(contract, "enableSnapshots"));
    try std.testing.expect(!@hasDecl(contract, "containsExclusiveList"));
    try std.testing.expect(language.reference_tables.buffer_operations.method("snapshot") == null);
    try std.testing.expect(std.meta.stringToEnum(counters.Kind, "retain") == null);
    try std.testing.expect(std.meta.stringToEnum(counters.Kind, "release") == null);
    try std.testing.expect(std.meta.stringToEnum(counters.Kind, "release_unique") == null);
    try std.testing.expect(std.meta.stringToEnum(counters.Kind, "unique_test") == null);
    try std.testing.expectEqual(@as(usize, 40), counters.function_slots);
}

// spec-case: OWNERSHIP-RETIREMENT-1
test "ownership retirement runtime has one count-free ABI without conditional RC" {
    try std.testing.expect(std.mem.indexOf(u8, header(), "count") == null);
    try std.testing.expect(std.mem.indexOf(u8, driver.runtime_source, "MYL_ZERO_RC") == null);
    try std.testing.expect(std.mem.indexOf(u8, driver.runtime_source, "count_retain(") == null);
    try std.testing.expect(std.mem.indexOf(u8, driver.runtime_source, "count_release(") == null);
    try std.testing.expect(std.mem.indexOf(u8, driver.runtime_source, "MYL_SHARED") == null);
    try std.testing.expect(std.mem.indexOf(u8, driver.runtime_source, "MYL_SATURATED") == null);
}

// spec-case: OWNERSHIP-RETIREMENT-1
test "ownership retirement destroys copied nested owners without RC in debug and verify builds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try directDestruction(arena.allocator(), false);
    try directDestruction(arena.allocator(), true);
}

// spec-case: OWNERSHIP-RETIREMENT-1
test "ownership retirement rejects borrowed escape and duplicate owners in lowered IR" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const own = @import("own.zig");
    var borrowed: ir.Module = .{};
    const ints = try borrowed.intern(a, .{ .list = .i64 });
    var read = try support.Hand.init(a, &borrowed, "escape", .{ .params = try a.dupe(ir.Type, &.{ints}), .ret = ints });
    const parameter = try read.param(0);
    _ = try read.emit(.{ .op = .ret, .ty = .void, .a = parameter });
    _ = try read.finish();
    var refusal: own.Refusal = .{};
    try std.testing.expectError(error.Unsupported, own.run(a, &borrowed, .{ .refusal = &refusal }));
    // The refusal names the function and the operation that stopped the pass, so
    // the build can report it instead of exiting silently (REGRESSION-R2).
    try std.testing.expectEqualStrings("escape", refusal.function);
    try std.testing.expect(refusal.operation.len != 0);
    try std.testing.expect(refusal.rule == null);
    // The per-function entry records the same refusal through the wrapper.
    var escape_module: ir.Module = .{};
    const escape_int = try escape_module.intern(a, .{ .list = .i64 });
    var only = try support.Hand.init(a, &escape_module, "escape", .{ .params = try a.dupe(ir.Type, &.{escape_int}), .ret = escape_int });
    _ = try only.emit(.{ .op = .ret, .ty = .void, .a = try only.param(0) });
    _ = try only.finish();
    var function_refusal: own.Refusal = .{};
    try std.testing.expectError(error.Unsupported, own.functionWithScratch(a, a, &escape_module, &escape_module.functions.items[0], .{ .refusal = &function_refusal }));
    try std.testing.expectEqualStrings("escape", function_refusal.function);
    try std.testing.expect(function_refusal.operation.len != 0);
    try std.testing.expect(function_refusal.rule == null);

    var repeated: ir.Module = .{};
    const list = try repeated.intern(a, .{ .list = .i64 });
    const pair = try repeated.intern(a, .{ .record = &.{ list, list } });
    var make = try support.Hand.init(a, &repeated, "duplicate", .{ .params = &.{}, .ret = pair });
    const value = try make.emit(.{ .op = .list_new, .ty = list, .a = try make.int(.u64, 1) });
    const result = try make.emit(.{ .op = .record_make, .ty = pair, .data = try make.extra(&.{ value, value }) });
    _ = try make.emit(.{ .op = .ret, .ty = .void, .a = result });
    _ = try make.finish();
    var repeated_refusal: own.Refusal = .{};
    try std.testing.expectError(error.Unsupported, own.run(a, &repeated, .{ .refusal = &repeated_refusal }));
    try std.testing.expectEqual(.Z3, repeated_refusal.rule.?);
}

/// A borrowed result names each owned argument in its explicit source list.
fn borrowedResultProgram(a: std.mem.Allocator, sources: []const ir.BorrowSource) !ir.Module {
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    const borrowed = try module.borrowedType(a, list);
    const params = try a.dupe(ir.Type, &.{ list, list, list });
    try module.functions.append(a, .{ .name = "borrow_many", .signature = .{ .params = params, .ret = borrowed, .linkage = .extern_c, .borrow = .{ .sources = sources } } });
    var hand = try support.Hand.init(a, &module, "many_owners", .{ .params = params, .ret = .u64, .passing = .{ .owned = 7 } });
    const first = try hand.param(0);
    const second = try hand.param(1);
    const third = try hand.param(2);
    const result = try hand.emit(.{ .op = .call, .ty = borrowed, .a = @fromBackingInt(0), .data = try hand.extra(&.{ first, second, third }), .span = 73 });
    const storage = try hand.emit(.{ .op = .borrow, .ty = list, .a = result });
    const size = try hand.emit(.{ .op = .list_len, .ty = .u64, .a = storage, .span = 77 });
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = size });
    _ = try hand.finish();
    return module;
}

/// Moving one list into two record fields remains an unsupported owner schedule.
fn duplicateOwners(a: std.mem.Allocator) !ir.Module {
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    const pair = try module.intern(a, .{ .record = &.{ list, list } });
    var hand = try support.Hand.init(a, &module, "duplicate_owners", .{ .params = &.{}, .ret = pair });
    const value = try hand.emit(.{ .op = .list_new, .ty = list, .a = try hand.int(.u64, 1) });
    const result = try hand.emit(.{ .op = .record_make, .ty = pair, .data = try hand.extra(&.{ value, value }), .span = 73 });
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = result });
    _ = try hand.finish();
    return module;
}

fn preservePartialRefusal(a: std.mem.Allocator, previous: @import("own.zig").Refusal) !void {
    var module = try duplicateOwners(a);
    var refusal = previous;
    try std.testing.expectError(error.Unsupported, @import("own.zig").functionWithScratch(a, a, &module, &module.functions.items[0], .{ .refusal = &refusal }));
    try std.testing.expectEqualDeep(previous, refusal);
}

test "O3 ownership scheduler keeps all three declared result sources until their final borrowed use" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try borrowedResultProgram(a, &.{ .{ .argument = 0 }, .{ .argument = 1 }, .{ .argument = 2 } });
    try support.verified(a, &module, &.{});
    const stats = try @import("own.zig").run(a, &module, .{});
    try std.testing.expectEqual(@as(u32, 3), stats.drops);
    try support.verified(a, &module, &.{});
    const function = &module.functions.items[1];
    var read = false;
    var destroyed: [3]bool = @splat(false);
    for (function.blocks.items[0].insts.items) |ref| {
        const inst = function.inst(ref);
        if (inst.op == .list_len) read = true;
        if (inst.op != .drop) continue;
        try std.testing.expect(read);
        const source = function.inst(function.resolve(inst.a));
        try std.testing.expectEqual(.param, source.op);
        try std.testing.expect(source.data < destroyed.len);
        const position: usize = @intCast(source.data);
        try std.testing.expect(!destroyed[position]);
        destroyed[position] = true;
    }
    try std.testing.expect(read);
    try std.testing.expectEqualSlices(bool, &.{ true, true, true }, &destroyed);
}

test "ownership scheduler labels supported-shape limits and preserves its first refusal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const own = @import("own.zig");
    var limited = try duplicateOwners(a);
    var refusal: own.Refusal = .{};
    try std.testing.expectError(error.Unsupported, own.run(a, &limited, .{ .refusal = &refusal }));
    try std.testing.expectEqual(.Z3, refusal.rule.?);
    try std.testing.expectEqualStrings("duplicate_owners", refusal.function);
    try std.testing.expectEqualStrings("record_make", refusal.operation);
    try std.testing.expectEqual(@as(u32, 73), refusal.span);
    var next = try duplicateOwners(a);
    var previous: own.Refusal = .{ .function = "first", .operation = "phi", .span = 21, .rule = .Z3 };
    const expected = previous;
    try std.testing.expectError(error.Unsupported, own.run(a, &next, .{ .refusal = &previous }));
    try std.testing.expectEqualDeep(expected, previous);
    try preservePartialRefusal(a, .{ .rule = .Z3 });
    try preservePartialRefusal(a, .{ .span = 21 });
    try preservePartialRefusal(a, .{ .function = "first" });
}

test "ownership scheduler leaves malformed markers unlabeled and verifier rejects invalid borrow sources" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const own = @import("own.zig");
    var marker_module: ir.Module = .{};
    const marker = try support.declareChoice(a, &marker_module, .min_text, .str, .str);
    marker_module.functions.items[marker].signature.passing.owned = 1;
    var marker_refusal: own.Refusal = .{};
    try std.testing.expectError(error.Unsupported, own.run(a, &marker_module, .{ .refusal = &marker_refusal }));
    try std.testing.expect(marker_refusal.rule == null);
    var invalid = try borrowedResultProgram(a, &.{ .{ .argument = 0 }, .{ .argument = 1 }, .{ .argument = 2 }, .{ .argument = 3 } });
    var failure: @import("verify_ir.zig").Failure = .{};
    try std.testing.expectError(error.InvalidIr, @import("verify_ir.zig").verifyModule(a, &invalid, &failure));
    try std.testing.expectEqualStrings("borrow_many", failure.function);
    try std.testing.expectEqualStrings("invalid declared borrowed result paths or owner sources", failure.reason);
}

/// A borrowed record parameter whose list field a push consumes: the push takes a part the function only borrows.
fn consumedBorrowedPart(a: std.mem.Allocator) !ir.Module {
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    const holder = try module.intern(a, .{ .record = &.{list} });
    var hand = try support.Hand.init(a, &module, "push_part", .{ .params = try a.dupe(ir.Type, &.{holder}), .ret = .u64 });
    const part = try hand.emit(.{ .op = .record_get, .ty = list, .a = try hand.param(0), .data = 0, .span = 11 });
    const pushed = try hand.emit(.{ .op = .list_push, .ty = list, .a = part, .b = try hand.int(.i64, 5), .span = 22 });
    const size = try hand.emit(.{ .op = .list_len, .ty = .u64, .a = pushed, .span = 33 });
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = size });
    _ = try hand.finish();
    return module;
}

test "a Z3 refusal names the operation that takes a borrowed part and the place it reads (lane O3, item 1)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const own = @import("own.zig");
    var module = try consumedBorrowedPart(a);
    var refusal: own.Refusal = .{};
    try std.testing.expectError(error.Unsupported, own.run(a, &module, .{ .refusal = &refusal }));
    try std.testing.expectEqual(.Z3, refusal.rule.?);
    try std.testing.expectEqualStrings("push_part", refusal.function);
    try std.testing.expectEqualStrings("list_push", refusal.operation);
    try std.testing.expectEqual(@as(u32, 22), refusal.span);
    try std.testing.expectEqual(own.Conflict.Kind.takes_borrowed, refusal.conflict.kind);
    try std.testing.expectEqual(@as(u32, 11), refusal.conflict.place);
    try std.testing.expectEqual(@as(u32, 1), refusal.conflict.depth);
    try std.testing.expectEqualStrings("", refusal.conflict.caller);
}

test "a Z3 refusal of one owner moved into two fields says the constructor takes it twice (lane O3, item 1)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const own = @import("own.zig");
    var module = try duplicateOwners(a);
    var refusal: own.Refusal = .{};
    try std.testing.expectError(error.Unsupported, own.run(a, &module, .{ .refusal = &refusal }));
    try std.testing.expectEqualStrings("record_make", refusal.operation);
    try std.testing.expectEqual(@as(u32, 73), refusal.span);
    try std.testing.expectEqual(own.Conflict.Kind.takes_twice, refusal.conflict.kind);
}
