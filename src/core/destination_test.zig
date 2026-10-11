//! Returned constructors expose caller storage without source ownership syntax.
const std = @import("std");
const ir = @import("ir.zig");
const destination = @import("destination.zig");
const support = @import("test_support.zig");
const passes = @import("passes.zig");
const origins = @import("inline_origins.zig");

const constructors =
    \\func total(xs: int[]) -> int:
    \\    mut answer = 0
    \\    for x in xs:
    \\        answer += x
    \\    return answer
    \\
    \\func make_values(n: int) -> int[]:
    \\    mut xs: int[] = []
    \\    for i in range(8):
    \\        xs.append(n + i)
    \\    return xs
    \\
    \\func unknown(n: int) -> int[]:
    \\    mut xs: int[] = []
    \\    for i in range(n):
    \\        xs.append(n + i)
    \\    return xs
    \\
    \\func large(n: int) -> int[]:
    \\    mut xs: int[] = []
    \\    for i in range(600):
    \\        xs.append(n + i)
    \\    return xs
    \\
    \\func managed(n: int) -> str[]:
    \\    mut xs: str[] = []
    \\    for i in range(8):
    \\        xs.append("word")
    \\    return xs
    \\
    \\func alias(xs: int[], n: int) -> int[]:
    \\    mut answer = 0
    \\    for i in range(n):
    \\        answer += i
    \\    return xs
    \\
    \\func edge(n: int) -> int[]:
    \\    mut xs: int[] = []
    \\    for i in range(512):
    \\        xs.append(n + i)
    \\    return xs
    \\
    \\func probe(n: int) -> int:
    \\    const xs = make_values(n)
    \\    return total(xs)
    \\
    \\func looped(n: int) -> int:
    \\    mut answer = 0
    \\    for batch in range(3):
    \\        const xs = make_values(n + batch)
    \\        answer += total(xs)
    \\    return answer
    \\
    \\func escape(n: int) -> int[]:
    \\    return make_values(n)
    \\
    \\func stored(n: int) -> int[][]:
    \\    const xs = make_values(n)
    \\    return [xs]
    \\
    \\func snapshot(n: int) -> int:
    \\    const before = make_values(n)
    \\    mut after = before
    \\    after.append(n + 8)
    \\    return total(before) * 10 + total(after)
    \\
    \\func joined(n: int) -> int:
    \\    mut xs = make_values(n)
    \\    if n > 0:
    \\        xs = make_values(n + 1)
    \\    return total(xs)
    \\
    \\func budget(n: int) -> int:
    \\    const first = edge(n)
    \\    const second = edge(n + 1)
    \\    return total(first) + total(second)
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(probe(4), looped(4), snapshot(4), joined(4))
    \\    out.print(total(escape(4)), total(stored(4)[0]))
    \\    out.print(total(unknown(4)), total(large(4)), len(managed(4)))
    \\    out.print(total(alias([1, 2], 4)), budget(4))
    \\    return 0
;

fn functionIndex(module: *const ir.Module, name: []const u8) !u32 {
    for (module.functions.items, 0..) |function, i| {
        if (std.mem.eql(u8, function.name, name)) return @intCast(i);
    }
    return error.TestUnexpectedResult;
}

fn llvmFunction(text: []const u8, name: []const u8) []const u8 {
    const start = std.mem.indexOf(u8, text, name) orelse return "";
    const end = std.mem.indexOf(u8, text[start..], "\n}") orelse return "";
    return text[start..][0..end];
}

// spec: NEW-CORE-DEST-1
test "caller destinations qualify only bounded fresh unmanaged list constructors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    const module = try support.buildSource(a, constructors, &refusal);
    const before = try @import("print.zig").module(a, &module);
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const cases = [_]struct { name: []const u8, expected: bool }{
        .{ .name = "make_values", .expected = true },
        .{ .name = "edge", .expected = true },
        .{ .name = "unknown", .expected = false },
        .{ .name = "large", .expected = false },
        .{ .name = "managed", .expected = false },
        .{ .name = "alias", .expected = false },
        .{ .name = "escape", .expected = false },
        .{ .name = "stored", .expected = false },
    };
    for (cases) |case| {
        const index = try functionIndex(&module, case.name);
        try std.testing.expectEqual(case.expected, try destination.qualifies(scratch.allocator(), &module, &module.functions.items[index]));
        _ = scratch.reset(.free_all);
    }
    try std.testing.expectEqualStrings(before, try @import("print.zig").module(a, &module));
}

// spec-case: NEW-CORE-DEST-1
test "caller destinations use real caller storage while escaping snapshots and large results keep heap lifetimes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, constructors, &refusal);
    const result = try support.runPasses(a, &module, .trusted);
    const cases = [_]struct { name: []const u8, expected: u32 }{
        .{ .name = "probe", .expected = 1 },
        .{ .name = "looped", .expected = 1 },
        .{ .name = "escape", .expected = 0 },
        .{ .name = "stored", .expected = 0 },
        .{ .name = "snapshot", .expected = 0 },
        .{ .name = "unknown", .expected = 0 },
        .{ .name = "large", .expected = 0 },
        .{ .name = "managed", .expected = 0 },
        .{ .name = "joined", .expected = 0 },
        // 512 elements fit the per-list limit, but two headers put these two
        // lists over the cumulative 8 KiB frame budget. Only one is promoted.
        .{ .name = "budget", .expected = 1 },
    };
    for (cases) |case| {
        const index = try functionIndex(&module, case.name);
        try std.testing.expectEqual(case.expected, result.per_function[index].own.promoted);
    }
    const text = try support.releaseLlvmText(a, constructors);
    const caller = llvmFunction(text, "define internal fastcc i64 @\"my.probe\"(");
    try std.testing.expect(std.mem.indexOf(u8, caller, "alloca [96 x i8], align 32") != null);
    try std.testing.expect(std.mem.indexOf(u8, caller, "@\"my.make_values\"(") == null);
    try std.testing.expect(std.mem.indexOf(u8, caller, "@myl_core_list_new(") == null);
    try std.testing.expect(std.mem.indexOf(u8, caller, "@myl_core_list_grow(") == null);
    try std.testing.expect(std.mem.indexOf(u8, caller, "@\"my.total\"(") != null);
}

// spec-case: NEW-CORE-DEST-1
test "caller destinations preserve independent loop instances snapshots and heap escapes in every build mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const modes = [_]?passes.Mode{ null, .trusted, .verify };
    for (modes) |mode| {
        var refusal: @import("build.zig").Refusal = .{};
        var module = try support.buildSource(a, constructors, &refusal);
        const ran = if (mode) |selected| blk: {
            const result = try support.runPasses(a, &module, selected);
            break :blk try support.runOwned(a, &module, .{ .release = true, .verify = selected == .verify, .own = false, .analysis = support.analysis(&result) });
        } else try support.runOwned(a, &module, .{});
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        try std.testing.expectEqualStrings("60 204 672 68\n60 60\n22 182100 8\n3 266240\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
    }
}

const trapped =
    \\func make_checked(n: int) -> int[]:
    \\    mut xs: int[] = []
    \\    for i in range(8):
    \\        xs.append(n // (i - 3))
    \\    return xs
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(17)
    \\    const xs = make_checked(9)
    \\    out.print(len(xs))
    \\    return 0
;

// spec-case: NEW-CORE-DEST-1
test "caller destinations keep construction trap order and the inlined constructor frame" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, trapped, &refusal);
    const result = try support.runPasses(a, &module, .verify);
    try std.testing.expectEqual(@as(u32, 1), result.per_function[module.entry].own.promoted);
    const ran = try support.runOwned(a, &module, .{ .release = true, .verify = true, .own = false, .leakcheck = false, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 1), ran.status);
    try std.testing.expectEqualStrings("17\n", ran.stdout);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "error[R_DIVISION_BY_ZERO]") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in make_checked at hand.my:") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "in main at hand.my:") != null);
}

// spec-case: NEW-CORE-DEST-1
test "caller destinations bound repeated expansion and keep cloned facts independent of scratch storage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var text: std.Io.Writer.Allocating = .init(a);
    try text.writer.writeAll("func make_values(n: int) -> int[]:\n    mut xs: int[] = []\n    for i in range(8):\n        xs.append(n + i)\n    return xs\nfunc main(out: Stream) -> int:\n");
    for (0..40) |i| try text.writer.print("    out.print(len(make_values({d})))\n", .{i});
    try text.writer.writeAll("    return 0\n");
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, text.written(), &refusal);
    var table: origins.Table = .{};
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    const before = module.functions.items[module.entry].insts.items.len;
    const expanded = try @import("inline.zig").cfgCallerDemandWithScratch(a, scratch.allocator(), &module, module.entry, &table, null);
    try std.testing.expect(expanded > 0 and expanded < 40);
    try std.testing.expect(module.functions.items[module.entry].insts.items.len - before <= destination.max_caller_instructions);
    _ = scratch.reset(.free_all);
    const overwritten = try scratch.allocator().alloc(u8, 1 << 20);
    @memset(overwritten, 0xa5);
    try support.verified(a, &module, &.{});
    const result = try support.runPasses(a, &module, .trusted);
    try std.testing.expect(result.own.promoted > 0);
}
