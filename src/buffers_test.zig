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
    try run("fn main(alloc: allocator) -> i64 { match acquire_buffer<R>(alloc, 4u8) { R.ok(b) => { discard b; return 7; }, R.err(e) => { return e; } } }", 7, 1, .{});
    try run("fn main(alloc: allocator) -> i64 { match acquire_buffer<R>(alloc, 4) { R.ok(discard) => { return 0; }, R.err(e) => { return e; } } }", 1, 0, .{ .max_buffer_capacity = 3 });
    try run("fn main(alloc: allocator) -> i64 { match acquire_buffer<R>(alloc, -1) { R.ok(discard) => { return 0; }, R.err(e) => { return e; } } }", 1, 0, .{});
    try run("fn main(alloc: allocator) -> i64 { acknowledge acquire_buffer<R>(alloc, 18446744073709551615u64); return 9; }", 9, 0, .{});
    try run("result Other { err: i64, ok: B } fn main(alloc: allocator) -> i64 { match acquire_buffer<Other>(alloc, 0) { Other.ok(b) => { return 2; }, Other.err(e) => { return e; } } }", 2, 1, .{});
}

test "owned source values transfer through helpers returns and wrappers" {
    try run("struct Box { payload: B, value: i64 } fn forward(b: B) -> B { let moved = b; return moved; } fn box(b: B) -> Box { return new Box { payload: forward(b), value: 42 }; } fn main(alloc: allocator) -> i64 { match acquire_buffer<R>(alloc, 2) { R.ok(b) => { let wrapped = box(b); return wrapped.value; }, R.err(e) => { return e; } } }", 42, 1, .{});
    try run("fn forward(r: R) -> R { return r; } fn main(alloc: allocator) -> i64 { acknowledge forward(acquire_buffer<R>(alloc, 1)); return 3; }", 3, 1, .{});
    try run("fn main(alloc: allocator) -> i64 { match acquire_buffer<R>(alloc, 1) { R.ok(b) => { let values = new [1]B[b]; discard values[0]; return 5; }, R.err(e) => { return e; } } }", 5, 1, .{});
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
    try reject("fn main(alloc: allocator) -> i64 { discard new B {}; return 0; }", "E_TYPE");
    try reject("fn main(alloc: allocator) -> i64 { acknowledge acquire_buffer<B>(alloc, 1); return 0; }", "E_BUFFER_RESULT");
    try reject("result Wrong { ok: B, err: bool } fn main(alloc: allocator) -> i64 { acknowledge acquire_buffer<Wrong>(alloc, 1); return 0; }", "E_BUFFER_RESULT");
    try reject("fn main(alloc: allocator) -> i64 { acknowledge acquire_buffer<R>(alloc, true); return 0; }", "E_TYPE");
    try reject("buffer Other: i64; fn f(b: B) -> Other { return b; } fn main() -> i64 { return 0; }", "E_TYPE");
}

const partial = declarations ++ "struct Pair { first: B, second: B } result PairResult { ok: Pair, err: i64 } fn make(alloc: allocator) -> PairResult { return new PairResult.ok(new Pair { first: try acquire_buffer<R>(alloc, 2), second: try acquire_buffer<R>(alloc, 2) }); } fn main(alloc: allocator) -> i64 { match make(alloc) { PairResult.ok(p) => { discard p; }, PairResult.err(e) => { discard e; } } match acquire_buffer<R>(alloc, 1) { R.ok(discard) => { return 7; }, R.err(e) => { return e; } } }";
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
    try run("fn make(alloc: allocator) -> R { let a = try acquire_buffer<R>(alloc, 1); let b = try acquire_buffer<R>(alloc, 1); return new R.ok(b); } fn main(alloc: allocator) -> i64 { acknowledge make(alloc); match acquire_buffer<R>(alloc, 1) { R.ok(discard) => { return 8; }, R.err(e) => { return e; } } }", 8, 2, .{ .max_allocations = 1 });
}
test "source acquisition and resource wrappers release on every host allocation failure" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), partialScenario, .{@as(usize, 1)});
    try t.checkAllAllocationFailures(no_resize.allocator(), partialScenario, .{@as(usize, 2)});
}

test "lexical blocks and match payloads release before subsequent acquisitions" {
    try run("fn make(alloc: allocator) -> R { return acquire_buffer<R>(alloc, 1); } fn work(alloc: allocator) -> R { { let local = try make(alloc); } return make(alloc); } fn main(alloc: allocator) -> i64 { match work(alloc) { R.ok(b) => {}, R.err(e) => { return e; } } match make(alloc) { R.ok(b) => { return 9; }, R.err(e) => { return e; } } }", 9, 3, .{ .max_allocations = 1 });
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
    var c = try language.Compilation.init(t.allocator, "loop.my", declarations ++ "fn forward(b: B) -> B { return b; } fn main(alloc: allocator) -> i64 { let mut i = 0; while i < 10000 { match acquire_buffer<R>(alloc, 4) { R.ok(b) => { let owned = forward(b); }, R.err(e) => { return e; } } i += 1; } return i; }");
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
    var c = try language.Compilation.init(t.allocator, "frames.my", declarations ++ "fn recurse(alloc: allocator, b: B) -> R { let local = try acquire_buffer<R>(alloc, 1); return recurse(alloc, local); } fn main(alloc: allocator) -> i64 { match acquire_buffer<R>(alloc, 1) { R.ok(b) => { acknowledge recurse(alloc, b); return 0; }, R.err(e) => { return e; } } }");
    defer c.deinit();
    var stats: memory.Statistics = .{};
    const result = try c.executeWithOptions(t.allocator, .{ .max_frames = 4, .memory_statistics = &stats });
    try t.expectEqualStrings("R_FRAME_LIMIT", result.trap.code);
    try t.expectEqual(@as(u64, 4), stats.created);
    try t.expectEqual(stats.created, stats.released);
}

test "mutable owner replacement releases old storage and consumed slots can be refilled" {
    try run("fn swap(alloc: allocator) -> R { let mut b = try acquire_buffer<R>(alloc, 1); b = try acquire_buffer<R>(alloc, 1); discard b; b = try acquire_buffer<R>(alloc, 1); return new R.ok(b); } fn main(alloc: allocator) -> i64 { acknowledge swap(alloc); return 6; }", 6, 3, .{ .max_allocations = 2 });
    try run("fn choose(b: B, flag: bool) -> i64 { if flag { discard b; } else { discard b; } return 5; } fn main(alloc: allocator) -> i64 { match acquire_buffer<R>(alloc, 1) { R.ok(b) => { return choose(b, true); }, R.err(e) => { return e; } } }", 5, 1, .{});
}

test "duplicate discovery preserves acquisition types capacities and ownership operations" {
    var c = try language.Compilation.init(t.allocator, "duplicates.my", declarations ++ "fn a(alloc: allocator, n: i64) -> R { return acquire_buffer<R>(alloc, n); } fn b(alloc: allocator, capacity: i64) -> R { return acquire_buffer<R>(alloc, capacity); } fn different(alloc: allocator, n: i64) -> R { return acquire_buffer<R>(alloc, n + 1); } fn main() -> i64 { return 0; }");
    defer c.deinit();
    try c.check();
    var found = try language.duplicates.discover(t.allocator, c.program.?, .{ .min_nodes = 1 });
    defer found.deinit();
    try t.expectEqual(@as(usize, 1), found.groups.len);
    try t.expectEqual(@as(usize, 2), found.groups[0].members.len);
    try t.expectEqualStrings("exact-v24", language.duplicates.version);
}

test "bytecode rejects buffer construction bypass and invalid acquisition contracts" {
    var c = try language.Compilation.init(t.allocator, "invalid.my", declarations ++ "fn main(alloc: allocator) -> i64 { acknowledge acquire_buffer<R>(alloc, 1); return 0; }");
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

const operations = "result Status { ok: bool, err: i64 } ";

test "buffer operations retain owners and distinguish initialized length from capacity" {
    try run(operations ++ "fn work(alloc: allocator) -> R { let mut b = try acquire_buffer<R>(alloc, 2); acknowledge append_buffer<Status>(b, 7); acknowledge append_buffer<Status>(b, 8); acknowledge reserve_buffer<Status>(b, alloc, 4); acknowledge resize_buffer<Status>(b, 3, 9); acknowledge write_buffer<Status>(b, 1, 10); return new R.ok(b); } fn main(alloc: allocator) -> i64 { match work(alloc) { R.ok(b) => { return read_buffer(b, 0) + read_buffer(b, 1) + read_buffer(b, 2) + cast<i64>(len_buffer(b)) + cast<i64>(capacity_buffer(b)); }, R.err(e) => { return e; } } }", 33, 1, .{});
}

test "failed buffer edits preserve existing contents length and capacity" {
    try run(operations ++ "fn work(alloc: allocator) -> R { let mut b = try acquire_buffer<R>(alloc, 1); acknowledge append_buffer<Status>(b, 7); match append_buffer<Status>(b, 8) { Status.ok(discard) => {}, Status.err(e) => { if e != 2 { return new R.err(10); } } } match reserve_buffer<Status>(b, alloc, 5) { Status.ok(discard) => {}, Status.err(e) => { if e != 1 { return new R.err(20); } } } match write_buffer<Status>(b, -1, 99) { Status.ok(discard) => {}, Status.err(e) => { if e != 3 { return new R.err(30); } } } acknowledge resize_buffer<Status>(b, 2, 99); return new R.ok(b); } fn main(alloc: allocator) -> i64 { match work(alloc) { R.ok(b) => { return read_buffer(b, 0) + cast<i64>(len_buffer(b)) + cast<i64>(capacity_buffer(b)); }, R.err(e) => { return e; } } }", 9, 1, .{ .max_buffer_capacity = 4 });
}

test "buffer operations require live mutable owners exact elements and handled status" {
    try reject(operations ++ "fn f(b: B) -> i64 { acknowledge append_buffer<Status>(b, 1); return 0; } fn main() -> i64 { return 0; }", "E_IMMUTABLE");
    try reject("fn f(b: B) -> u64 { discard b; return len_buffer(b); } fn main() -> i64 { return 0; }", "E_OWNED_CONSUMED");
    try reject(operations ++ "fn f(input: B) -> i64 { let mut b = input; acknowledge append_buffer<Status>(b, true); return 0; } fn main() -> i64 { return 0; }", "E_TYPE");
    try reject("fn main(alloc: allocator) -> i64 { let b = 1; return read_buffer(b, 0); }", "E_BUFFER_TYPE");
    try reject(operations ++ "fn f(input: B) -> i64 { let mut b = input; discard append_buffer<Status>(b, 1); return 0; } fn main() -> i64 { return 0; }", "E_RESULT_DISCARD");
    try reject("fn f(input: B) -> i64 { let mut b = input; acknowledge append_buffer<R>(b, 1); return 0; } fn main() -> i64 { return 0; }", "E_BUFFER_RESULT");
    try reject("fn consume(b: B) -> i64 { return 0; } fn f(b: B) -> i64 { return read_buffer(b, consume(b)); } fn main() -> i64 { return 0; }", "E_OWNED_CONSUMED");
}

const mutation_program = declarations ++ operations ++ "fn work(alloc: allocator) -> R { let mut b = try acquire_buffer<R>(alloc, 1); acknowledge append_buffer<Status>(b, 7); acknowledge reserve_buffer<Status>(b, alloc, 4); acknowledge resize_buffer<Status>(b, 4, 9); acknowledge write_buffer<Status>(b, 2, 12); acknowledge resize_buffer<Status>(b, 3, 0); return new R.ok(b); } fn main(alloc: allocator) -> i64 { match work(alloc) { R.ok(b) => { return read_buffer(b, 2); }, R.err(e) => { return e; } } }";
fn mutationScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "mutation.my", mutation_program);
    defer c.deinit();
    try t.expectEqual(@as(i64, 12), (try c.execute(allocator)).value);
}
test "buffer mutations release storage on every allocation failure and instruction trap" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), mutationScenario, .{});
    var c = try language.Compilation.init(t.allocator, "mutation.my", mutation_program);
    defer c.deinit();
    var budget: u64 = 1;
    while (budget < 150) : (budget += 1) {
        var stats: memory.Statistics = .{};
        const result = try c.executeWithOptions(t.allocator, .{ .max_steps = budget, .memory_statistics = &stats });
        try t.expectEqual(stats.created, stats.released);
        if (result == .value) break;
        try t.expectEqualStrings("R_STEP_LIMIT", result.trap.code);
    }
    try t.expect(budget < 150);
}

test "buffer aggregate element reads survive later writes shrink and owner destruction" {
    try run("struct Point { x: i64 } buffer Points: Point; result PointsResult { ok: Points, err: i64 } " ++ operations ++ "fn work(alloc: allocator) -> PointsResult { let mut p = try acquire_buffer<PointsResult>(alloc, 2); acknowledge append_buffer<Status>(p, new Point { x: 7 }); let snapshot = read_buffer(p, 0); acknowledge write_buffer<Status>(p, 0, new Point { x: 99 }); acknowledge resize_buffer<Status>(p, 0, new Point { x: 0 }); acknowledge append_buffer<Status>(p, snapshot); return new PointsResult.ok(p); } fn main(alloc: allocator) -> i64 { match work(alloc) { PointsResult.ok(p) => { let saved = read_buffer(p, 0); discard p; return saved.x; }, PointsResult.err(e) => { return e; } } }", 7, 1, .{});
}

test "uninitialized buffer reads trap and oversized edit arguments remain recoverable" {
    var c = try language.Compilation.init(t.allocator, "bounds.my", declarations ++ "fn main(alloc: allocator) -> i64 { match acquire_buffer<R>(alloc, 4) { R.ok(b) => { return read_buffer(b, 0); }, R.err(e) => { return e; } } }");
    defer c.deinit();
    const result = try c.execute(t.allocator);
    try t.expectEqualStrings("R_BUFFER_BOUNDS", result.trap.code);
    try run(operations ++ "fn work(alloc: allocator) -> R { let mut b = try acquire_buffer<R>(alloc, 1); acknowledge resize_buffer<Status>(b, -1, 0); acknowledge reserve_buffer<Status>(b, alloc, 18446744073709551615u64); acknowledge write_buffer<Status>(b, 18446744073709551615u64, 2); return new R.ok(b); } fn main(alloc: allocator) -> i64 { match work(alloc) { R.ok(b) => { return cast<i64>(len_buffer(b)) + cast<i64>(capacity_buffer(b)); }, R.err(e) => { return e; } } }", 1, 1, .{});
}

const view_program = declarations ++ operations ++ "fn tail(s: &mut []i64) -> &mut []i64 from s { borrow mut s[1..3] as part { return part; } } fn modify(s: &mut []i64) -> i64 { borrow mut tail(s) as part { write_slice(part, 0, 11); return read_slice(part, 1); } } fn work(alloc: allocator) -> R { let mut b = try acquire_buffer<R>(alloc, 4); acknowledge resize_buffer<Status>(b, 4, 7); borrow mut b[0..4] as s { discard modify(s); } acknowledge reserve_buffer<Status>(b, alloc, 8); return new R.ok(b); } fn main(alloc: allocator) -> i64 { match work(alloc) { R.ok(b) => { return read_buffer(b, 1) + cast<i64>(capacity_buffer(b)); }, R.err(e) => { return e; } } }";
fn viewScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "views.my", view_program);
    defer c.deinit();
    try t.expectEqual(@as(i64, 19), (try c.execute(allocator)).value);
}
test "buffer views preserve offsets through parameters nested reborrows and returned views" {
    try viewScenario(t.allocator);
    try run(operations ++ "fn size(s: &[]i64) -> u64 { borrow s as again { return len_slice(again); } } fn main(alloc: allocator) -> i64 { match acquire_buffer<R>(alloc, 0) { R.ok(b) => { borrow b[0..0] as s { return cast<i64>(size(s)); } }, R.err(e) => { return e; } } }", 0, 1, .{});
    try run(operations ++ "fn first(s: &[]i64) -> i64 { return read_slice(s, 0); } fn work(alloc: allocator) -> R { let mut b = try acquire_buffer<R>(alloc, 1); acknowledge append_buffer<Status>(b, 7); return new R.ok(b); } fn main(alloc: allocator) -> i64 { let a = new [1]i64[2]; match work(alloc) { R.ok(b) => { borrow b[0..1] as s { borrow a[0..1] as t { return first(s) + first(t); } } }, R.err(e) => { return e; } } }", 9, 2, .{});
}

test "buffer views reject move mutation growth and escape while loans are active" {
    try reject("fn f(alloc: allocator, b: B) -> i64 { borrow b[0..0] as s { discard b; } return 0; } fn main() -> i64 { return 0; }", "E_BORROW_CONFLICT");
    try reject(operations ++ "fn f(alloc: allocator, input: B) -> i64 { let mut b = input; borrow b[0..0] as s { acknowledge reserve_buffer<Status>(b, alloc, 1); } return 0; } fn main() -> i64 { return 0; }", "E_BORROW_CONFLICT");
    try reject("fn f(alloc: allocator, input: B) -> u64 { let mut b = input; borrow mut b[0..0] as s { return len_buffer(b); } } fn main() -> i64 { return 0; }", "E_BORROW_CONFLICT");
    try reject("fn f(alloc: allocator, b: B) -> i64 { discard b; borrow b[0..0] as s {} return 0; } fn main() -> i64 { return 0; }", "E_OWNED_CONSUMED");
    try reject("fn f(alloc: allocator, b: B, input: &[]i64) -> &[]i64 from input { borrow b[0..0] as s { return s; } } fn main() -> i64 { return 0; }", "E_RETURN_LIFETIME");
    try reject(operations ++ "fn f(alloc: allocator, input: B) -> i64 { let mut b = input; borrow mut b[0..0] as s { borrow s as child { discard len_slice(s); } } return 0; } fn main() -> i64 { return 0; }", "E_BORROW_SUSPENDED");
}

test "buffer view allocation failures and every trap boundary clean nested loans and resources" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), viewScenario, .{});
    var c = try language.Compilation.init(t.allocator, "views.my", view_program);
    defer c.deinit();
    var budget: u64 = 1;
    while (budget < 150) : (budget += 1) {
        var stats: memory.Statistics = .{};
        const result = try c.executeWithOptions(t.allocator, .{ .max_steps = budget, .memory_statistics = &stats });
        try t.expectEqual(stats.created, stats.released);
        if (result == .value) break;
        try t.expectEqualStrings("R_STEP_LIMIT", result.trap.code);
    }
    try t.expect(budget < 150);
}

test "buffer slice writes preserve aggregate snapshots and trap on uninitialized ranges" {
    try run("struct Point { x: i64 } buffer Points: Point; result PointsResult { ok: Points, err: i64 } " ++ operations ++ "fn work(alloc: allocator) -> PointsResult { let mut p = try acquire_buffer<PointsResult>(alloc, 2); acknowledge resize_buffer<Status>(p, 2, new Point { x: 7 }); let snapshot = read_buffer(p, 0); borrow mut p[0..2] as s { write_slice(s, 0, new Point { x: 99 }); } acknowledge write_buffer<Status>(p, 1, snapshot); return new PointsResult.ok(p); } fn main(alloc: allocator) -> i64 { match work(alloc) { PointsResult.ok(p) => { borrow p[1..2] as s { return read_slice(s, 0).x; } }, PointsResult.err(e) => { return e; } } }", 7, 1, .{});
    var c = try language.Compilation.init(t.allocator, "empty.my", declarations ++ "fn main(alloc: allocator) -> i64 { match acquire_buffer<R>(alloc, 2) { R.ok(b) => { borrow b[0..1] as s { return read_slice(s, 0); } }, R.err(e) => { return e; } } }");
    defer c.deinit();
    try t.expectEqualStrings("R_SLICE_BOUNDS", (try c.execute(t.allocator)).trap.code);
}

test "ten thousand buffer writes through returned views use bounded live storage" {
    var c = try language.Compilation.init(t.allocator, "loop.my", declarations ++ operations ++ "fn view(s: &mut []i64) -> &mut []i64 from s { return s; } fn work(alloc: allocator) -> R { let mut b = try acquire_buffer<R>(alloc, 2); acknowledge resize_buffer<Status>(b, 2, 0); let mut i = 0; while i < 10000 { borrow mut b[0..2] as s { borrow mut view(s) as output { write_slice(output, 1, i); } } i += 1; } return new R.ok(b); } fn main(alloc: allocator) -> i64 { match work(alloc) { R.ok(b) => { return read_buffer(b, 1); }, R.err(e) => { return e; } } }");
    defer c.deinit();
    try c.emit();
    var limiter = LimitedLiveAllocator{ .parent = t.allocator, .limit = 16384 };
    var stats: memory.Statistics = .{};
    try t.expectEqual(@as(i64, 9999), (try c.executeWithOptions(limiter.allocator(), .{ .memory_statistics = &stats, .memory_limits = .{ .max_allocations = 1 } })).value);
    try t.expectEqual(@as(u64, 1), stats.created);
    try t.expectEqual(stats.created, stats.released);
    try t.expectEqual(@as(usize, 0), limiter.live);
}

test "propagating a failed buffer operation ends direct loans before owner cleanup" {
    try run(operations ++ "fn work(alloc: allocator) -> R { let mut first = try acquire_buffer<R>(alloc, 1); acknowledge append_buffer<Status>(first, 7); let mut second = try acquire_buffer<R>(alloc, 0); borrow mut first[0..1] as s { discard try append_buffer<Status>(second, read_slice(s, 0)); } return new R.ok(first); } fn main(alloc: allocator) -> i64 { acknowledge work(alloc); match acquire_buffer<R>(alloc, 1) { R.ok(b) => { return cast<i64>(capacity_buffer(b)); }, R.err(e) => { return e; } } }", 1, 3, .{ .max_allocations = 2 });
}

test "discovery distinguishes buffer operations and emission rejects invalid operation metadata" {
    var c = try language.Compilation.init(t.allocator, "operations.my", declarations ++ "fn a(b: B) -> u64 { return len_buffer(b); } fn duplicate(other: B) -> u64 { return len_buffer(other); } fn capacity(b: B) -> u64 { return capacity_buffer(b); } fn main() -> i64 { return 0; }");
    defer c.deinit();
    try c.emit();
    var found = try language.duplicates.discover(t.allocator, c.program.?, .{ .min_nodes = 1 });
    defer found.deinit();
    try t.expectEqual(@as(usize, 1), found.groups.len);
    try t.expectEqual(@as(usize, 2), found.groups[0].members.len);
    for (@constCast(c.code.?.functions[0].instructions)) |*instruction| {
        if (instruction.op == .buffer_operation) {
            const original = instruction.*;
            instruction.op.buffer_operation.owner = @fromBackingInt(9999);
            try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
            instruction.* = original;
            instruction.op.buffer_operation.output = .bool;
            try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
            instruction.* = original;
            return;
        }
    }
    return error.TestUnexpectedResult;
}
