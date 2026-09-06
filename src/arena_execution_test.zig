const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const memory = @import("memory.zig");
const source =
    \\buffer Numbers: i64;
    \\result Acquired { ok: Numbers, err: i64 }
    \\result Status { ok: bool, err: i64 }
    \\fn tail(values: &mut []i64) -> &mut []i64 from values {
    \\    borrow mut values[1..3] as selected { return selected; }
    \\}
    \\fn make(heap: allocator) -> Acquired {
    \\    let mut values = try acquire_buffer<Acquired>(heap, 3);
    \\    discard try resize_buffer<Status>(values, 3, 7);
    \\    borrow mut values[0..3] as whole {
    \\        borrow mut tail(whole) as selected { write_slice(selected, 0, 11); }
    \\    }
    \\    discard try reserve_buffer<Status>(values, heap, 8);
    \\    return new Acquired.ok(values);
    \\}
    \\fn main(heap: allocator) -> i64 {
    \\    match make(heap) {
    \\        Acquired.ok(values) => { return read_buffer(values, 1) + cast<i64>(capacity_buffer(values)); },
    \\        Acquired.err(code) => { return code; }
    \\    }
    \\}
;
fn released(stats: memory.Statistics) !void {
    try t.expectEqual(stats.created, stats.released);
    try t.expectEqual(@as(usize, 0), stats.live_allocations);
    try t.expectEqual(@as(usize, 0), stats.total_capacity);
}
test "source allocator forwarding growth and returned buffer slices agree across memory backends" {
    var c = try language.Compilation.init(t.allocator, "arena.my", source);
    defer c.deinit();
    for ([_]language.vm.MemoryBacking{ .general, .arena }) |backing| {
        var stats: memory.Statistics = .{};
        const result = try c.executeWithOptions(t.allocator, .{
            .memory = .{ .backing = backing, .statistics = &stats },
        });
        try t.expectEqual(@as(i64, 19), result.value);
        try t.expectEqual(@as(u64, 1), stats.created);
        try released(stats);
        try t.expectError(error.CapabilityUnavailable, c.executeWithOptions(t.allocator, .{
            .memory = .{ .backing = backing, .provide_allocator = false },
        }));
        const limited = try c.executeWithOptions(t.allocator, .{
            .memory = .{ .backing = backing, .limits = .{ .max_buffer_capacity = 2 }, .statistics = &stats },
        });
        try t.expectEqual(@as(i64, 1), limited.value);
        try released(stats);
    }
}
fn executeScenario(allocator: std.mem.Allocator, c: *language.Compilation) !void {
    var stats: memory.Statistics = .{};
    defer std.debug.assert(stats.created == stats.released);
    try t.expectEqual(@as(i64, 19), (try c.executeWithOptions(allocator, .{
        .memory = .{ .backing = .arena, .statistics = &stats },
    })).value);
    try released(stats);
}
// spec: OWN-12
test "arena VM releases backing and owners on every host allocation failure" {
    var c = try language.Compilation.init(t.allocator, "arena.my", source);
    defer c.deinit();
    try c.emit();
    try executeScenario(t.allocator, &c);
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), executeScenario, .{&c});
}
test "arena VM cleanup survives every instruction boundary including suspended returned borrows" {
    var c = try language.Compilation.init(t.allocator, "arena.my", source);
    defer c.deinit();
    for (1..500) |budget| {
        var stats: memory.Statistics = .{};
        const result = try c.executeWithOptions(t.allocator, .{ .memory = .{ .backing = .arena, .statistics = &stats }, .max_steps = budget });
        try released(stats);
        if (result == .value) {
            try t.expectEqual(@as(i64, 19), result.value);
            return;
        }
        try t.expectEqualStrings("R_STEP_LIMIT", result.trap.code);
    }
    return error.TestUnexpectedResult;
}
test "arena VM preserves immutable snapshots and cleans partial acquisition on propagation" {
    const fixed = "fn main() -> i64 { let mut a = new [3]i64 [2, 3, 5]; let before = a; borrow mut a[0..3] as all { write_slice(all, 1, 11); } return before[1] + a[1]; }";
    const partial = "buffer B: i64; result R { ok: B, err: i64 } struct Pair { first: B, second: B } " ++
        "result P { ok: Pair, err: i64 } fn make(heap: allocator) -> P { return new P.ok(new " ++
        "Pair { first: try acquire_buffer<R>(heap, 2), second: try acquire_buffer<R>(heap, 2) " ++
        "}); } fn main(heap: allocator) -> i64 { acknowledge make(heap); match " ++
        "acquire_buffer<R>(heap, 1) { R.ok(discard) => { return 7; }, R.err(code) => { return " ++
        "code; } } }";
    for ([_][]const u8{ fixed, partial }, [_]i64{ 14, 7 }) |text, expected| {
        var c = try language.Compilation.init(t.allocator, "arena.my", text);
        defer c.deinit();
        var stats: memory.Statistics = .{};
        try t.expectEqual(expected, (try c.executeWithOptions(t.allocator, .{
            .memory = .{ .backing = .arena, .statistics = &stats, .limits = .{ .max_allocations = 1 } },
        })).value);
        try released(stats);
    }
}
test "separate arena VM executions reclaim their complete backing" {
    var c = try language.Compilation.init(t.allocator, "arena.my", source);
    defer c.deinit();
    try c.emit();
    var limited: @import("test_support.zig").LimitedLiveAllocator = .{ .parent = t.allocator, .limit = 32768 };
    defer limited.deinit();
    for (0..1000) |_| {
        try executeScenario(limited.allocator(), &c);
        try t.expectEqual(@as(usize, 0), limited.live);
    }
}
