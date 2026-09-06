//! Arena reset tests cover retained backing, live children, reuse, and bytecode result-schema validation.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const memory = @import("memory.zig");
const program =
    \\buffer B: i64;
    \\result Open { ok: B, err: i64 }
    \\result Status { ok: bool, err: i64 }
    \\result Work { ok: i64, err: i64 }
    \\fn reset(region: allocator) -> Status noalloc {
    \\    return reset_arena<Status>(region);
    \\}
    \\fn work(heap: allocator) -> Work {
    \\    arena heap as scratch {
    \\        let copy = scratch;
    \\        let mut buffer = try acquire_buffer<Open>(scratch, 8);
    \\        discard try append_buffer<Status>(buffer, 7);
    \\        borrow buffer[0..1] as view {
    \\            match reset(copy) {
    \\                Status.ok(discard) => { return new Work.err(90); },
    \\                Status.err(code) => { if code != 1 { return new Work.err(91); } }
    \\            }
    \\            if read_slice(view, 0) != 7 { return new Work.err(92); }
    \\        }
    \\        discard buffer;
    \\        arena scratch as child {
    \\            discard try reset(child);
    \\            match reset(scratch) {
    \\                Status.ok(discard) => { return new Work.err(93); },
    \\                Status.err(code) => { if code != 2 { return new Work.err(94); } }
    \\            }
    \\        }
    \\        discard try reset(copy);
    \\        let replacement = try acquire_buffer<Open>(scratch, 3);
    \\        let value = cast<i64>(capacity_buffer(replacement));
    \\        discard replacement;
    \\        discard try reset(scratch);
    \\        return new Work.ok(value);
    \\    }
    \\}
    \\fn main(heap: allocator) -> i64 {
    \\    match work(heap) { Work.ok(value) => { return value; }, Work.err(code) => { return code; } }
    \\}
;

fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "arena-reset.my", program);
    defer c.deinit();
    var statistics: memory.Statistics = .{};
    const result = c.executeWithOptions(allocator, .{
        .memory = .{ .statistics = &statistics, .limits = .{ .max_regions = 2, .max_allocations = 1 } },
    }) catch |err| {
        if (err != error.OutOfMemory) @import("diagnostics_test.zig").report(c.diagnostics.items);
        return err;
    };
    try t.expectEqual(@as(i64, 3), result.value);
    try t.expectEqual(@as(u64, 2), statistics.created);
    try t.expectEqual(statistics.created, statistics.released);
}
// spec: OWN-7
test "source reset rejects live buffers borrows and children and preserves copied authority" {
    try scenario(t.allocator);
}
test "executeResetArena and result creation unwind on every allocation failure" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
test "source reset cleanup is safe at every instruction boundary with either memory backing" {
    var c = try language.Compilation.init(t.allocator, "reset-traps.my", program);
    defer c.deinit();
    for ([_]language.vm.MemoryBacking{ .general, .arena }) |backing| {
        var finished = false;
        for (1..500) |budget| {
            var statistics: memory.Statistics = .{};
            const result = try c.executeWithOptions(t.allocator, .{
                .max_steps = budget,
                .memory = .{ .backing = backing, .statistics = &statistics },
            });
            try t.expectEqual(statistics.created, statistics.released);
            if (result == .value) {
                try t.expectEqual(@as(i64, 3), result.value);
                finished = true;
                break;
            }
            try t.expectEqualStrings("R_STEP_LIMIT", result.trap.code);
        }
        try t.expect(finished);
    }
}
fn expectResult(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "reset-case.my", source);
    defer c.deinit();
    try t.expectEqual(expected, (try c.execute(t.allocator)).value);
}
fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "reset-bad.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
test "reset contracts require allocator input and handled bool i64 results" {
    try reject("fn main(a: allocator) -> i64 { discard reset_arena<bool>(a); return 0; }", "E_ARENA_RESULT");
    try reject("result R { ok: i64, err: i64 } fn main(a: allocator) -> i64 { acknowledge reset_arena<R>(a); return 0; }", "E_ARENA_RESULT");
    try reject("result R { ok: bool, err: i64 } fn main() -> i64 { acknowledge reset_arena<R>(1); return 0; }", "E_TYPE");
    try reject("result R { ok: bool, err: i64 } fn main(a: allocator) -> i64 { discard reset_arena<R>(a); return 0; }", "E_RESULT_DISCARD");
    try expectResult("result R { err: i64, ok: bool } fn main(a: allocator) -> i64 noalloc { match reset_arena<R>(a) { R.ok(discard) => { return 99; }, R.err(code) => { return code; } } }", 3);
}
test "pool storage pins an arena across clear and retained snapshots survive successful reset" {
    try expectResult("pool P(Id): Node; struct Node { value: i64 } result Open { ok: P, err: i64 } result " ++
        "Insert { ok: Id, err: i64 } result Read { ok: Node, err: i64 } result Status { ok: " ++
        "bool, err: i64 } result Work { ok: i64, err: i64 } fn work(heap: allocator) -> Work " ++
        "{ arena heap as scratch { let mut p = try acquire_pool<Open>(scratch, 1); let id = " ++
        "try insert_pool<Insert>(p, new Node { value: 42 }); let snapshot = try " ++
        "read_pool<Read>(p, id); discard clear_pool(p); match reset_arena<Status>(scratch) { " ++
        "Status.ok(discard) => { return new Work.err(99); }, Status.err(code) => { if code != " ++
        "1 { return new Work.err(98); } } } discard p; discard try " ++
        "reset_arena<Status>(scratch); let other = try acquire_pool<Open>(scratch, 1); match " ++
        "read_pool<Read>(other, id) { Read.ok(discard) => { return new Work.err(97); }, " ++
        "Read.err(code) => { if code != 2 { return new Work.err(96); } } } return new " ++
        "Work.ok(snapshot.value); } } fn main(heap: allocator) -> i64 { match work(heap) { " ++
        "Work.ok(v) => { return v; }, Work.err(e) => { return e; } } }", 42);
}
test "reset frees retained chunks and rejects closed foreign and root capabilities" {
    var limited: @import("test_support.zig").LimitedLiveAllocator = .{ .parent = t.allocator, .limit = 256 * 1024 };
    defer limited.deinit();
    const allocator = limited.allocator();
    {
        var store = try memory.Store.init(allocator);
        defer store.deinit();
        var other = try memory.Store.init(allocator);
        defer other.deinit();
        const root = try store.allocatorCapability();
        const region = try store.beginRegion(root);
        const copy = region;
        const first = try store.createAuthorized(region, .i64, &.{}, 1000);
        const second = try store.createAuthorized(region, .i64, &.{}, 1000);
        try t.expectError(error.RegionInUse, store.resetRegion(region));
        try store.destroy(first);
        try store.destroy(second);
        const before = limited.live;
        try store.resetRegion(region);
        try t.expect(limited.live + 1024 < before);
        try store.checkAllocator(copy);
        const reused = try store.createAuthorized(copy, .i64, &.{.{ .i64 = 7 }}, 1);
        try store.destroy(reused);
        try t.expectError(error.InvalidCapability, other.resetRegion(copy));
        try t.expectError(error.InvalidCapability, store.resetRegion(root));
        try store.endRegion(region);
        try t.expectError(error.InvalidCapability, store.resetRegion(copy));
    }
    try t.expectEqual(@as(usize, 0), limited.live);
}

test "repeated source reset bounds allocation churn inside one long-lived arena" {
    const source = "buffer B: i64; result Open { ok: B, err: i64 } result Status { ok: bool, err: i64 } " ++
        "result Work { ok: i64, err: i64 } fn work(heap: allocator) -> Work { arena heap as " ++
        "scratch { let mut n = 0; while n < 10000 { let first = try " ++
        "acquire_buffer<Open>(scratch, 16); let second = try acquire_buffer<Open>(scratch, " ++
        "16); discard first; discard second; discard try reset_arena<Status>(scratch); n += 1;" ++
        " } return new Work.ok(n); } } fn main(heap: allocator) -> i64 { match work(heap) { " ++
        "Work.ok(v) => { return v; }, Work.err(e) => { return e; } } }";
    var c = try language.Compilation.init(t.allocator, "reset-loop.my", source);
    defer c.deinit();
    try c.emit();
    for ([_]language.vm.MemoryBacking{ .general, .arena }) |backing| {
        var limited: @import("test_support.zig").LimitedLiveAllocator = .{ .parent = t.allocator, .limit = 16 * 1024 };
        defer limited.deinit();
        var statistics: memory.Statistics = .{};
        try t.expectEqual(@as(i64, 10000), (try c.executeWithOptions(limited.allocator(), .{
            .memory = .{ .backing = backing, .statistics = &statistics },
        })).value);
        try t.expectEqual(@as(u64, 20000), statistics.created);
        try t.expectEqual(statistics.created, statistics.released);
        try t.expectEqual(@as(usize, 0), limited.live);
    }
    const without_reset = try std.mem.replaceOwned(u8, t.allocator, source, "discard try reset_arena<Status>(scratch);", "");
    defer t.allocator.free(without_reset);
    var control = try language.Compilation.init(t.allocator, "no-reset.my", without_reset);
    defer control.deinit();
    try control.emit();
    var limited: @import("test_support.zig").LimitedLiveAllocator = .{ .parent = t.allocator, .limit = 16 * 1024 };
    defer limited.deinit();
    try t.expectError(error.OutOfMemory, control.execute(limited.allocator()));
    try t.expectEqual(@as(usize, 0), limited.live);
}
test "reset discovery distinguishes the operation and bytecode rejects invalid result schemas" {
    var c = try language.Compilation.init(t.allocator, "reset-tools.my", "result R { ok: bool, err: i64 } fn a(cap: allocator) -> R { return " ++
        "reset_arena<R>(cap); } fn b(renamed: allocator) -> R { return " ++
        "reset_arena<R>(renamed); } fn other(cap: allocator) -> R { return new R.ok(true); } " ++
        "fn main() -> i64 { return 0; }");
    defer c.deinit();
    try c.emit();
    var discovered = try language.duplicates.discover(t.allocator, c.program.?, .{ .min_nodes = 1 });
    defer discovered.deinit();
    try t.expectEqual(@as(usize, 1), discovered.groups.len);
    try t.expectEqual(@as(usize, 2), discovered.groups[0].members.len);
    try expectInvalidResetSchemas(&c);
}

fn expectInvalidResetSchemas(c: *language.Compilation) !void {
    var checked = false;
    for (c.code.?.functions) |function| for (@constCast(function.scope.instructions)) |*instruction| {
        if (instruction.op == .reset_arena) {
            const saved = instruction.*;
            defer instruction.* = saved;
            instruction.op.reset_arena = .i64;
            try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
            checked = true;
        }
    };
    try t.expect(checked);
}
