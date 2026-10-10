//! Inline ancestry bounds and preservation through actual loop/ownership passes.
const std = @import("std");
const ir = @import("ir.zig");
const origins = @import("inline_origins.zig");
const support = @import("test_support.zig");
const passes = @import("passes.zig");

// spec-case: NEW-CORE-S4-SITES-1
test "inline ancestry refuses a thirty-third frame before recording a clone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var table: origins.Table = .{};
    var callee: ir.Function = .{ .name = "callee", .signature = .{ .params = &.{}, .ret = .i64 } };
    try callee.blocks.append(a, .{});
    const ref: ir.Ref = @fromBackingInt(0);
    for (0..origins.max_depth) |depth| {
        const clone = (try table.prepare(a, .{ .caller = 0, .callee = 1, .block = 0, .ref = ref, .span = @intCast(depth + 7) }, &callee)).?;
        try table.setBlock(a, 0, 0, clone.outer);
    }
    const before = table.frames.items.len;
    try std.testing.expect((try table.prepare(a, .{ .caller = 0, .callee = 1, .block = 0, .ref = ref, .span = 99 }, &callee)) == null);
    try std.testing.expectEqual(before, table.frames.items.len);
    try std.testing.expectEqual(@as(usize, 1), callee.blocks.items.len);
    try std.testing.expectEqual(@as(usize, 0), callee.insts.items.len);
}

// spec-case: NEW-CORE-S4-SITES-1
test "caller root overrides survive movement and duplication into a cloned block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var table: origins.Table = .{};
    const callee: ir.Function = .{ .name = "callee", .signature = .{ .params = &.{}, .ret = .i64 } };
    const call: ir.Ref = @fromBackingInt(0);
    const clone = (try table.prepare(a, .{ .caller = 0, .callee = 1, .block = 0, .ref = call, .span = 7 }, &callee)).?;
    const context = table.context(0);
    try context.setBlock(a, 1, clone.outer);
    const release: ir.Ref = @fromBackingInt(1);
    try std.testing.expectEqual(@as(?u32, clone.outer), context.at(1, release));
    try context.setInstruction(a, release, null);
    try std.testing.expect(context.at(1, release) == null);
    const copied: ir.Ref = @fromBackingInt(2);
    try context.copyInstruction(a, release, copied);
    try context.copyBlock(a, 1, 2);
    try std.testing.expect(context.at(2, copied) == null);
    try std.testing.expectEqual(@as(?u32, clone.outer), context.at(2, call));
    try table.setInstruction(a, 9, release, null);
    try std.testing.expect(!table.functions.contains(9));
}

const looping =
    \\func origin(mut xs: int[], x: int, kind: int) -> int:
    \\    xs.append(2)
    \\    mut total = 0
    \\    for i in range(x):
    \\        if kind == 0:
    \\            total += xs[i]
    \\        else:
    \\            total += xs[i] + 1
    \\    return total
    \\func main(args: str[]) -> int:
    \\    mut xs = [1]
    \\    return origin(mut xs, 3, len(args))
;

// spec-case: NEW-CORE-S4-SITES-1
test "unswitched consuming loops and ownership keep every copied read in its exact callee" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, looping, &refusal);
    const result = try support.runPasses(a, &module, .verify);
    try std.testing.expect(result.counts.unswitched > 0);
    try std.testing.expect(try copiedReads(&module, &result) >= 4);
    const ran = try support.runOwned(a, &module, .{ .release = true, .verify = true, .own = false, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 1), ran.status);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in origin at hand.my:") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in main at hand.my:") != null);
}

fn copiedReads(module: *const ir.Module, result: *const passes.Result) !usize {
    const function = &module.functions.items[module.entry];
    var reads: usize = 0;
    for (function.blocks.items, 0..) |block, b| for (block.insts.items) |ref| {
        if (function.inst(ref).op != .list_get) continue;
        const frame = result.provenance.instruction(module.entry, @intCast(b), ref).?;
        try std.testing.expectEqualStrings("origin", module.functions.items[result.provenance.frames.items[frame].function].name);
        reads += 1;
    };
    return reads;
}

// spec-case: NEW-CORE-S4-SITES-1
test "analyzed native fixtures refuse ownership edits that would discard ancestry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, looping, &refusal);
    const result = try support.runPasses(a, &module, .verify);
    try std.testing.expect(result.provenance.frames.items.len != 0);
    const count = module.functions.items[module.entry].insts.items.len;
    try std.testing.expectError(error.AnalyzedOwnership, support.runOwned(a, &module, .{ .analysis = support.analysis(&result) }));
    try std.testing.expectEqual(count, module.functions.items[module.entry].insts.items.len);
}

// spec-case: NEW-CORE-S4-SITES-1
test "a corrupted cloned reachability premise reports its callee declaration and caller" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, looping, &refusal);
    const result = try support.runPasses(a, &module, .verify);
    try invalidateReachability(&module, &result);
    const ran = try support.runOwned(a, &module, .{ .release = true, .verify = true, .own = false, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 1), ran.status);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "unreachable block") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in origin at hand.my:") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in main at hand.my:") != null);
}

fn invalidateReachability(module: *const ir.Module, result: *const passes.Result) !void {
    const known = result.known[module.entry].?;
    for (module.functions.items[module.entry].blocks.items, 0..) |_, b| {
        if (!known.reachable[b] or result.provenance.block(module.entry, @intCast(b)) == null) continue;
        known.reachable[b] = false;
        return;
    }
    try std.testing.expect(false);
}

// spec-case: NEW-CORE-S4-SITES-1
test "a failed ownership check added to a consuming clone retains its callee frame" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.mem.replaceOwned(u8, a, looping, "xs = [1]", "xs = [1] * 1025");
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const result = try support.runPasses(a, &module, .verify);
    try corruptUnique(&module, &result);
    const ran = try support.runOwned(a, &module, .{ .release = true, .verify = true, .own = false, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 1), ran.status);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "count == 1 before an in-place update") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in origin at hand.my:") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in main at hand.my:") != null);
}

fn corruptUnique(module: *ir.Module, result: *const passes.Result) !void {
    const function = &module.functions.items[module.entry];
    for (function.blocks.items, 0..) |block, b| {
        if (result.provenance.block(module.entry, @intCast(b)) == null or block.insts.items.len == 0 or block.preds.items.len != 1) continue;
        const terminal = function.inst(block.insts.items[block.insts.items.len - 1]);
        if (terminal.op != .@"unreachable" or terminal.data != @import("own.zig").unique_assert) continue;
        const head = function.blocks.items[block.preds.items[0].index()].insts.items;
        const condition = function.resolve(function.inst(head[head.len - 1]).a);
        const old = function.inst(condition);
        function.insts.items[condition.index()] = .{ .op = .iconst, .ty = .bool, .data = 0, .span = old.span };
        return;
    }
    try std.testing.expect(false);
}

const checked_leaves =
    \\func affine(x: int) -> int:
    \\    return x * 3 + 7
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(affine(9), affine(12))
    \\    return 0
;

// spec-case: NEW-CORE-INLINE-1
test "checked leaf clones and ancestry survive reclaimed caller facts and repeated proof trials" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var oracle = try support.buildSource(a, checked_leaves, &refusal);
    var expected_origins: origins.Table = .{};
    const expected_count = try @import("inline.zig").leafCaller(a, &oracle, oracle.entry, &.{}, &expected_origins);
    const revisited = try @import("inline.zig").withParametersCounted(a, &oracle, &.{}, &expected_origins, null);
    try std.testing.expectEqual(@as(u32, 0), revisited);
    const expected_text = try @import("print.zig").module(a, &oracle);
    var module = try support.buildSource(a, checked_leaves, &refusal);
    var actual_origins: origins.Table = .{};
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const count = try @import("inline.zig").leafCallerWithScratch(a, scratch.allocator(), &module, module.entry, &.{}, &actual_origins);
    try std.testing.expectEqual(@as(u32, 2), count);
    try std.testing.expectEqual(expected_count, count);
    try std.testing.expect(scratch.queryCapacity() > 0);
    _ = scratch.reset(.free_all);
    try std.testing.expectEqual(@as(usize, 0), scratch.queryCapacity());
    const overwrite = try scratch.allocator().alloc(u8, 1 << 20);
    @memset(overwrite, 0xa5);
    try support.verified(a, &module, &.{});
    try std.testing.expectEqualStrings(expected_text, try @import("print.zig").module(a, &module));
    try std.testing.expectEqualDeep(expected_origins.frames.items, actual_origins.frames.items);
    try std.testing.expectEqual(expected_origins.instructions.count(), actual_origins.instructions.count());
    try std.testing.expectEqual(expected_origins.blocks.count(), actual_origins.blocks.count());
    const known = try passes.runWithScratch(a, std.testing.allocator, &module, .trusted);
    try support.verified(a, &module, known.plans);
}
