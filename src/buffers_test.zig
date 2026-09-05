const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const memory = @import("memory.zig");
const LimitedLiveAllocator = @import("test_support.zig").LimitedLiveAllocator;
const declarations = "buffer B: i64; result R { ok: B, err: i64 } ";

fn run(body: []const u8, expected: i64, created: u64, limits: memory.Limits) !void {
    const text = try std.mem.concat(t.allocator, u8, &.{ declarations, body });
    defer t.allocator.free(text);
    var c = try language.Compilation.init(t.allocator, "buffers.my", text);
    defer c.deinit();
    var stats: memory.Statistics = .{};
    const result = c.executeWithOptions(t.allocator, .{ .memory_limits = limits, .memory_statistics = &stats }) catch |err| {
        for (c.diagnostics.items) |d| std.debug.print("{s}: {s}\n", .{ d.code, d.message });
        return err;
    };
    try t.expectEqual(expected, result.value);
    try t.expectEqual(created, stats.created);
    try t.expectEqual(stats.created, stats.released);
    try t.expectEqual(@as(usize, 0), stats.live_allocations);
    try t.expectEqual(@as(usize, 0), stats.total_capacity);
}
fn reject(body: []const u8, code: []const u8) !void {
    const text = try std.mem.concat(t.allocator, u8, &.{ declarations, body });
    defer t.allocator.free(text);
    var c = try language.Compilation.init(t.allocator, "buffers.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

test "source acquisition returns nominal buffers or typed capacity errors" {
    try run("fn main() -> i64 { match acquire_buffer<R>(4u8) { R.ok(b) => { discard b; return 7; }, R.err(e) => { return e; } } }", 7, 1, .{});
    try run("fn main() -> i64 { match acquire_buffer<R>(4) { R.ok(discard) => { return 0; }, R.err(e) => { return e; } } }", 1, 0, .{ .max_buffer_capacity = 3 });
    try run("fn main() -> i64 { match acquire_buffer<R>(-1) { R.ok(discard) => { return 0; }, R.err(e) => { return e; } } }", 1, 0, .{});
    try run("fn main() -> i64 { acknowledge acquire_buffer<R>(18446744073709551615u64); return 9; }", 9, 0, .{});
    try run("result Other { err: i64, ok: B } fn main() -> i64 { match acquire_buffer<Other>(0) { Other.ok(b) => { return 2; }, Other.err(e) => { return e; } } }", 2, 1, .{});
}

test "owned source values transfer through helpers returns and wrappers" {
    try run("struct Box { payload: B, value: i64 } fn forward(b: B) -> B { let moved = b; return moved; } fn box(b: B) -> Box { return new Box { payload: forward(b), value: 42 }; } fn main() -> i64 { match acquire_buffer<R>(2) { R.ok(b) => { let wrapped = box(b); return wrapped.value; }, R.err(e) => { return e; } } }", 42, 1, .{});
    try run("fn forward(r: R) -> R { return r; } fn main() -> i64 { acknowledge forward(acquire_buffer<R>(1)); return 3; }", 3, 1, .{});
    try run("fn main() -> i64 { match acquire_buffer<R>(1) { R.ok(b) => { let values = new [1]B[b]; discard values[0]; return 5; }, R.err(e) => { return e; } } }", 5, 1, .{});
}

test "owned bindings cannot be reused or conditionally consumed" {
    try reject("fn f(b: B) -> i64 { let moved = b; discard b; return 0; } fn main() -> i64 { return 0; }", "E_OWNED_CONSUMED");
    try reject("struct Box { value: B } fn f(b: Box) -> i64 { let moved = b.value; discard b; return 0; } fn main() -> i64 { return 0; }", "E_OWNED_CONSUMED");
    try reject("fn f(b: B, flag: bool) -> i64 { if flag { discard b; } return 0; } fn main() -> i64 { return 0; }", "E_OWNED_PATH");
    try reject("fn f(b: B) -> i64 { while false { discard b; } return 0; } fn main() -> i64 { return 0; }", "E_OWNED_LOOP");
    try reject("fn consume(b: B) -> bool { return true; } fn f(b: B) -> i64 { discard false && consume(b); return 0; } fn main() -> i64 { return 0; }", "E_OWNED_PATH");
    try reject("fn f(b: B) -> i64 { borrow b as r { discard read_ref(r); } return 0; } fn main() -> i64 { return 0; }", "E_RESULT_BORROW");
    try reject("fn f(b: &B) -> i64 { return 0; } fn main() -> i64 { return 0; }", "E_RESULT_BORROW");
}

test "owned schemas preserve nominal identity and reject bypass construction" {
    try reject("buffer B: bool; fn main() -> i64 { return 0; }", "E_DUPLICATE_TYPE");
    try reject("buffer Recursive: Recursive; fn main() -> i64 { return 0; }", "E_RECURSIVE_RECORD");
    try reject("buffer Nested: B; fn main() -> i64 { return 0; }", "E_BUFFER_ELEMENT");
    try reject("buffer Errors: R; fn main() -> i64 { return 0; }", "E_BUFFER_ELEMENT");
    try reject("fn main() -> i64 { discard new B {}; return 0; }", "E_TYPE");
    try reject("fn main() -> i64 { acknowledge acquire_buffer<B>(1); return 0; }", "E_BUFFER_RESULT");
    try reject("result Wrong { ok: B, err: bool } fn main() -> i64 { acknowledge acquire_buffer<Wrong>(1); return 0; }", "E_BUFFER_RESULT");
    try reject("fn main() -> i64 { acknowledge acquire_buffer<R>(true); return 0; }", "E_TYPE");
    try reject("buffer Other: i64; fn f(b: B) -> Other { return b; } fn main() -> i64 { return 0; }", "E_TYPE");
}

const partial = declarations ++ "struct Pair { first: B, second: B } result PairResult { ok: Pair, err: i64 } fn make() -> PairResult { return new PairResult.ok(new Pair { first: try acquire_buffer<R>(2), second: try acquire_buffer<R>(2) }); } fn main() -> i64 { match make() { PairResult.ok(p) => { discard p; }, PairResult.err(e) => { discard e; } } match acquire_buffer<R>(1) { R.ok(discard) => { return 7; }, R.err(e) => { return e; } } }";
fn partialScenario(allocator: std.mem.Allocator, max_allocations: usize) !void {
    var c = try language.Compilation.init(allocator, "partial.my", partial);
    defer c.deinit();
    var stats: memory.Statistics = .{};
    try t.expectEqual(@as(i64, 7), (try c.executeWithOptions(allocator, .{ .memory_limits = .{ .max_allocations = max_allocations }, .memory_statistics = &stats })).value);
    try t.expectEqual(@as(u64, if (max_allocations == 1) 2 else 3), stats.created);
    try t.expectEqual(stats.created, stats.released);
}
test "source partial construction and propagation release acquired resources once" {
    try partialScenario(t.allocator, 1);
    try partialScenario(t.allocator, 2);
    try run("fn make() -> R { let a = try acquire_buffer<R>(1); let b = try acquire_buffer<R>(1); return new R.ok(b); } fn main() -> i64 { acknowledge make(); match acquire_buffer<R>(1) { R.ok(discard) => { return 8; }, R.err(e) => { return e; } } }", 8, 2, .{ .max_allocations = 1 });
}
test "source acquisition and resource wrappers release on every host allocation failure" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), partialScenario, .{@as(usize, 1)});
    try t.checkAllAllocationFailures(no_resize.allocator(), partialScenario, .{@as(usize, 2)});
}

test "lexical blocks and match payloads release before subsequent acquisitions" {
    try run("fn make() -> R { return acquire_buffer<R>(1); } fn work() -> R { { let local = try make(); } return make(); } fn main() -> i64 { match work() { R.ok(b) => {}, R.err(e) => { return e; } } match make() { R.ok(b) => { return 9; }, R.err(e) => { return e; } } }", 9, 3, .{ .max_allocations = 1 });
}

test "resource cleanup at every instruction trap boundary preserves allocator ownership" {
    var c = try language.Compilation.init(t.allocator, "traps.my", partial);
    defer c.deinit();
    try c.emit();
    var budget: u64 = 1;
    while (budget < 150) : (budget += 1) {
        var stats: memory.Statistics = .{};
        const result = try c.executeWithOptions(t.allocator, .{ .max_steps = budget, .memory_statistics = &stats });
        try t.expectEqual(stats.created, stats.released);
        try t.expectEqual(@as(usize, 0), stats.live_allocations);
        if (result == .value) break;
        try t.expectEqualStrings("R_STEP_LIMIT", result.trap.code);
    }
    try t.expect(budget < 150);
}

test "ten thousand source ownership cycles fit bounded runtime storage" {
    var c = try language.Compilation.init(t.allocator, "loop.my", declarations ++ "fn forward(b: B) -> B { return b; } fn main() -> i64 { let mut i = 0; while i < 10000 { match acquire_buffer<R>(4) { R.ok(b) => { let owned = forward(b); }, R.err(e) => { return e; } } i += 1; } return i; }");
    defer c.deinit();
    try c.emit();
    var limiter = LimitedLiveAllocator{ .parent = t.allocator, .limit = 16384 };
    var stats: memory.Statistics = .{};
    try t.expectEqual(@as(i64, 10000), (try c.executeWithOptions(limiter.allocator(), .{ .memory_limits = .{ .max_allocations = 1 }, .memory_statistics = &stats })).value);
    try t.expectEqual(@as(u64, 10000), stats.created);
    try t.expectEqual(stats.created, stats.released);
    try t.expectEqual(@as(usize, 0), limiter.live);
}

test "recursive frame budget traps release resource parameters and active locals" {
    var c = try language.Compilation.init(t.allocator, "frames.my", declarations ++ "fn recurse(b: B) -> R { let local = try acquire_buffer<R>(1); return recurse(local); } fn main() -> i64 { match acquire_buffer<R>(1) { R.ok(b) => { acknowledge recurse(b); return 0; }, R.err(e) => { return e; } } }");
    defer c.deinit();
    var stats: memory.Statistics = .{};
    const result = try c.executeWithOptions(t.allocator, .{ .max_frames = 4, .memory_statistics = &stats });
    try t.expectEqualStrings("R_FRAME_LIMIT", result.trap.code);
    try t.expectEqual(@as(u64, 4), stats.created);
    try t.expectEqual(stats.created, stats.released);
}

test "mutable owner replacement releases old storage and consumed slots can be refilled" {
    try run("fn swap() -> R { let mut b = try acquire_buffer<R>(1); b = try acquire_buffer<R>(1); discard b; b = try acquire_buffer<R>(1); return new R.ok(b); } fn main() -> i64 { acknowledge swap(); return 6; }", 6, 3, .{ .max_allocations = 2 });
    try run("fn choose(b: B, flag: bool) -> i64 { if flag { discard b; } else { discard b; } return 5; } fn main() -> i64 { match acquire_buffer<R>(1) { R.ok(b) => { return choose(b, true); }, R.err(e) => { return e; } } }", 5, 1, .{});
}

test "duplicate discovery preserves acquisition types capacities and ownership operations" {
    var c = try language.Compilation.init(t.allocator, "duplicates.my", declarations ++ "fn a(n: i64) -> R { return acquire_buffer<R>(n); } fn b(capacity: i64) -> R { return acquire_buffer<R>(capacity); } fn different(n: i64) -> R { return acquire_buffer<R>(n + 1); } fn main() -> i64 { return 0; }");
    defer c.deinit();
    try c.check();
    var found = try language.duplicates.discover(t.allocator, c.program.?, .{ .min_nodes = 1 });
    defer found.deinit();
    try t.expectEqual(@as(usize, 1), found.groups.len);
    try t.expectEqual(@as(usize, 2), found.groups[0].members.len);
    try t.expectEqualStrings("exact-v14", language.duplicates.version);
}

test "bytecode rejects buffer construction bypass and invalid acquisition contracts" {
    var c = try language.Compilation.init(t.allocator, "invalid.my", declarations ++ "fn main() -> i64 { acknowledge acquire_buffer<R>(1); return 0; }");
    defer c.deinit();
    try c.emit();
    const instructions = @constCast(c.code.?.functions[0].instructions);
    for (instructions) |*instruction| {
        if (instruction.op == .acquire_buffer) {
            const original = instruction.*;
            const shape = @import("typed.zig").resultShape(instruction.op.acquire_buffer, c.code.?.records).?;
            instruction.op = .{ .acquire_buffer = shape.ok_type };
            try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
            instruction.op = .{ .make_record = .{ .ty = shape.ok_type, .fields = 0 } };
            try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
            instruction.* = original;
            return;
        }
    }
    return error.TestUnexpectedResult;
}

test "runtime resource wrappers consume the external handle and retain a single cleanup record" {
    const Value = @import("value.zig").Value;
    const Type = @import("value.zig").Type;
    var store = try memory.Store.init(t.allocator);
    defer store.deinit();
    const external = try store.create(.i64, &.{.{ .i64 = 7 }});
    const resource = try Value.ownBuffer(t.allocator, @fromBackingInt(Type.record_base), &store, external);
    try t.expectError(error.InvalidAllocation, store.info(external));
    const wrapper = try Value.create(t.allocator, @fromBackingInt(Type.record_base + 1), &.{resource});
    resource.release(t.allocator);
    try t.expectEqual(@as(u64, 0), store.statistics.released);
    wrapper.release(t.allocator);
    try t.expectEqual(@as(u64, 1), store.statistics.released);
    try t.expectEqual(@as(usize, 0), store.statistics.live_allocations);
}
