const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const runtime = @import("pool_runtime.zig");
const declarations = "pool P(Id): i64; result Open { ok: P, err: i64 } result Insert { ok: Id, err: i64 } result Read { ok: i64, err: i64 } result Change { ok: bool, err: i64 } ";
const graph =
    \\pool Nodes(NodeId): Node;
    \\union Link { none, some: NodeId }
    \\struct Node { value: i64, next: Link }
    \\result Open { ok: Nodes, err: i64 }
    \\result Insert { ok: NodeId, err: i64 }
    \\result Read { ok: Node, err: i64 }
    \\result Change { ok: bool, err: i64 }
    \\result Work { ok: i64, err: i64 }
    \\fn work(heap: allocator) -> Work {
    \\    let mut nodes = try acquire_pool<Open>(heap, 2);
    \\    let a = try insert_pool<Insert>(nodes, new Node { value: 10, next: new Link.none });
    \\    let b = try insert_pool<Insert>(nodes, new Node { value: 20, next: new Link.some(a) });
    \\    let before = try read_pool<Read>(nodes, a);
    \\    discard try replace_pool<Change>(nodes, a, new Node { value: 30, next: new Link.some(b) });
    \\    let current = try read_pool<Read>(nodes, a);
    \\    match current.next { Link.none => { return new Work.err(90); }, Link.some(edge) => {
    \\        let neighbor = try read_pool<Read>(nodes, edge);
    \\        if neighbor.value != 20 { return new Work.err(91); }
    \\    } }
    \\    discard try remove_pool<Change>(nodes, b);
    \\    let replacement = try insert_pool<Insert>(nodes, new Node { value: 40, next: new Link.none });
    \\    match read_pool<Read>(nodes, b) { Read.ok(discard) => { return new Work.err(92); }, Read.err(code) => { if code != 1 { return new Work.err(93); } } }
    \\    let other = try acquire_pool<Open>(heap, 0);
    \\    match read_pool<Read>(other, a) { Read.ok(discard) => { return new Work.err(94); }, Read.err(code) => { if code != 2 { return new Work.err(95); } } }
    \\    let last = try read_pool<Read>(nodes, replacement);
    \\    discard clear_pool(nodes);
    \\    match read_pool<Read>(nodes, a) { Read.ok(discard) => { return new Work.err(96); }, Read.err(code) => { if code != 1 { return new Work.err(97); } } }
    \\    return new Work.ok(before.value + last.value + cast<i64>(len_pool(nodes)) + cast<i64>(capacity_pool(nodes)));
    \\}
    \\fn main(heap: allocator) -> i64 {
    \\    match work(heap) { Work.ok(value) => { return value; }, Work.err(code) => { return code; } }
    \\}
;

fn graphScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "pools.my", graph);
    defer c.deinit();
    var statistics: runtime.Statistics = .{};
    const result = c.executeWithOptions(allocator, .{ .pool_statistics = &statistics, .pool_limits = .{ .max_pools = 2, .max_total_slots = 2 } }) catch |err| {
        if (err != error.OutOfMemory) for (c.diagnostics.items) |d| std.debug.print("{s}: {s}\n", .{ d.code, d.message });
        return err;
    };
    try t.expectEqual(@as(i64, 52), result.value);
    try t.expectEqual(@as(u64, 2), statistics.acquired);
    try t.expectEqual(statistics.acquired, statistics.released);
    try t.expectEqual(@as(usize, 0), statistics.live_pools);
    try t.expectEqual(@as(usize, 0), statistics.reserved_slots);
}
test "source graphs retain snapshots and reject removed cleared and foreign IDs" {
    try graphScenario(t.allocator);
}
test "source pool graph cleanup survives every allocation failure" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), graphScenario, .{});
}
fn reject(body: []const u8, code: []const u8) !void {
    const text = try std.mem.concat(t.allocator, u8, &.{ declarations, body });
    defer t.allocator.free(text);
    var c = try language.Compilation.init(t.allocator, "invalid-pool.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
test "source pool types prevent forged IDs wrong categories and owning elements" {
    try reject("pool Q(Id): bool; fn main() -> i64 { return 0; }", "E_DUPLICATE_TYPE");
    try reject("pool Q(Q): bool; fn main() -> i64 { return 0; }", "E_DUPLICATE_TYPE");
    try reject("pool Q(QId): P; fn main() -> i64 { return 0; }", "E_POOL_ELEMENT");
    try reject("pool Q(QId): Read; fn main() -> i64 { return 0; }", "E_POOL_ELEMENT");
    try reject("pool Q(QId): Missing; fn main() -> i64 { return 0; }", "E_UNKNOWN_TYPE");
    try reject("struct Node { next: Node } pool Q(QId): Node; fn main() -> i64 { return 0; }", "E_RECURSIVE_RECORD");
    try reject("fn main() -> i64 { discard new Id {}; return 0; }", "E_TYPE");
    try reject("fn main() -> i64 { discard new P {}; return 0; }", "E_TYPE");
    try reject("pool Q(QId): i64; fn f(p: P, id: QId) -> Read { return read_pool<Read>(p, id); } fn main() -> i64 { return 0; }", "E_TYPE");
    try reject("fn f(p: P) -> Insert { return insert_pool<Insert>(p, 1); } fn main() -> i64 { return 0; }", "E_IMMUTABLE");
    try reject("fn f(p: P) -> Read { discard p; return read_pool<Read>(p, new Id {}); } fn main() -> i64 { return 0; }", "E_TYPE");
    try reject("fn f(p: P) -> u64 { discard p; return len_pool(p); } fn main() -> i64 { return 0; }", "E_OWNED_CONSUMED");
    try reject("fn f(p: P, id: Id) -> i64 { discard read_pool<Read>(p, id); return 0; } fn main() -> i64 { return 0; }", "E_RESULT_DISCARD");
    try reject("fn main(a: allocator) -> i64 { acknowledge acquire_pool<Read>(a, 1); return 0; }", "E_POOL_RESULT");
}

test "pool owners and node snapshots clean up at every instruction boundary on both buffer backends" {
    var c = try language.Compilation.init(t.allocator, "pool-traps.my", graph);
    defer c.deinit();
    for ([_]language.vm.MemoryBacking{ .general, .arena }) |backing| {
        var completed = false;
        for (1..1000) |budget| {
            var statistics: runtime.Statistics = .{};
            const result = try c.executeWithOptions(t.allocator, .{ .max_steps = budget, .memory_backing = backing, .pool_statistics = &statistics });
            try t.expectEqual(statistics.acquired, statistics.released);
            try t.expectEqual(@as(usize, 0), statistics.live_pools);
            try t.expectEqual(@as(usize, 0), statistics.reserved_slots);
            if (result == .value) {
                try t.expectEqual(@as(i64, 52), result.value);
                completed = true;
                break;
            }
            try t.expectEqualStrings("R_STEP_LIMIT", result.trap.code);
        }
        try t.expect(completed);
    }
}
fn expectResult(body: []const u8, expected: i64, limits: runtime.Limits) !void {
    const text = try std.mem.concat(t.allocator, u8, &.{ declarations, body });
    defer t.allocator.free(text);
    var c = try language.Compilation.init(t.allocator, "pool-case.my", text);
    defer c.deinit();
    var statistics: runtime.Statistics = .{};
    const actual = c.executeWithOptions(t.allocator, .{ .pool_limits = limits, .pool_statistics = &statistics }) catch |err| {
        for (c.diagnostics.items) |d| std.debug.print("{s}: {s}\n", .{ d.code, d.message });
        return err;
    };
    try t.expectEqual(expected, actual.value);
    try t.expectEqual(statistics.acquired, statistics.released);
    try t.expectEqual(@as(usize, 0), statistics.live_pools);
    try t.expectEqual(@as(usize, 0), statistics.reserved_slots);
}
test "pool quotas apply across copied allocator grants and recover after ownership cleanup" {
    try expectResult("fn main(a: allocator) -> i64 { match acquire_pool<Open>(a, -1) { Open.ok(discard) => { return 99; }, Open.err(e) => { return e; } } }", 1, .{});
    try expectResult("fn main(a: allocator) -> i64 { match acquire_pool<Open>(a, 18446744073709551615u64) { Open.ok(discard) => { return 99; }, Open.err(e) => { return e; } } }", 1, .{});
    try expectResult("fn main(a: allocator) -> i64 { match acquire_pool<Open>(a, 0) { Open.ok(discard) => { return 99; }, Open.err(e) => { return e; } } }", 1, .{ .max_pools = 0 });
    const body = "fn work(a: allocator) -> Read { let copy = a; let p = try acquire_pool<Open>(a, 2); match acquire_pool<Open>(copy, 2) { Open.ok(discard) => { return new Read.err(99); }, Open.err(e) => { if e != 1 { return new Read.err(98); } } } discard p; let reused = try acquire_pool<Open>(copy, 2); return new Read.ok(cast<i64>(capacity_pool(reused))); } fn main(a: allocator) -> i64 { match work(a) { Read.ok(v) => { return v; }, Read.err(e) => { return e; } } }";
    try expectResult(body, 2, .{ .max_total_slots = 3 });
    try expectResult(body, 2, .{ .max_pools = 1 });
    try expectResult("fn main(a: allocator) -> i64 { match acquire_pool<Open>(a, 3) { Open.ok(discard) => { return 99; }, Open.err(e) => { return e; } } }", 1, .{ .max_pool_slots = 2 });
}
test "source handles survive owner death as inert IDs and equality includes generation and pool" {
    try expectResult("fn make(a: allocator) -> Insert { let mut p = try acquire_pool<Open>(a, 1); return insert_pool<Insert>(p, 7); } fn work(a: allocator) -> Read { let old = try make(a); let mut p = try acquire_pool<Open>(a, 1); let current = try insert_pool<Insert>(p, 9); if old == current { return new Read.err(90); } if current != current { return new Read.err(91); } match read_pool<Read>(p, old) { Read.ok(discard) => { return new Read.err(92); }, Read.err(e) => { if e != 2 { return new Read.err(93); } } } discard try remove_pool<Change>(p, current); let reused = try insert_pool<Insert>(p, 11); if reused == current { return new Read.err(94); } return read_pool<Read>(p, reused); } fn main(a: allocator) -> i64 { match work(a) { Read.ok(v) => { return v; }, Read.err(e) => { return e; } } }", 11, .{ .max_pools = 1 });
}
test "reserved pool operations are noalloc while acquisition contributes transitive allocation effects" {
    try reject("fn make(a: allocator) -> Open { return acquire_pool<Open>(a, 0); } fn main(a: allocator) -> i64 noalloc { acknowledge make(a); return 0; }", "E_EFFECT_BOUND");
    try expectResult("fn edit(input: P) -> Read noalloc { let mut p = input; let id = try insert_pool<Insert>(p, 7); match insert_pool<Insert>(p, 9) { Insert.ok(discard) => { return new Read.err(99); }, Insert.err(e) => { if e != 3 { return new Read.err(98); } } } discard try replace_pool<Change>(p, id, 8); let n = try read_pool<Read>(p, id); discard clear_pool(p); return new Read.ok(n); } fn work(a: allocator) -> Read { return edit(try acquire_pool<Open>(a, 1)); } fn main(a: allocator) -> i64 { match work(a) { Read.ok(v) => { return v; }, Read.err(e) => { return e; } } }", 8, .{});
}

test "pool owners participate in wrapper field moves and early propagation cleanup" {
    try expectResult("struct Pair { first: P, second: P } fn work(a: allocator) -> Read { let pair = new Pair { first: try acquire_pool<Open>(a, 1), second: try acquire_pool<Open>(a, 1) }; discard take_field(pair, first); let spare = try acquire_pool<Open>(a, 1); let rest = take_field(pair, second); return new Read.ok(cast<i64>(capacity_pool(rest) + capacity_pool(spare))); } fn main(a: allocator) -> i64 { match work(a) { Read.ok(v) => { return v; }, Read.err(e) => { return e; } } }", 2, .{ .max_pools = 2 });
    try expectResult("struct Pair { first: P, second: P } result PairResult { ok: Pair, err: i64 } fn work(a: allocator) -> PairResult { return new PairResult.ok(new Pair { first: try acquire_pool<Open>(a, 1), second: try acquire_pool<Open>(a, 1) }); } fn main(a: allocator) -> i64 { acknowledge work(a); match acquire_pool<Open>(a, 1) { Open.ok(p) => { return cast<i64>(capacity_pool(p)); }, Open.err(e) => { return 99; } } }", 1, .{ .max_pools = 1 });
}
test "source pool registry reuse and snapshots stay bounded over ten thousand cycles" {
    const text = comptime graph[0..std.mem.indexOf(u8, graph, "fn work").?] ++ "fn work(a: allocator) -> Work { let mut p = try acquire_pool<Open>(a, 1); let mut n = 0; while n < 10000 { let id = try insert_pool<Insert>(p, new Node { value: n, next: new Link.none }); let snapshot = try read_pool<Read>(p, id); discard try remove_pool<Change>(p, id); if snapshot.value != n { return new Work.err(99); } n += 1; } return new Work.ok(n); } fn main(a: allocator) -> i64 { match work(a) { Work.ok(v) => { return v; }, Work.err(e) => { return e; } } }";
    var c = try language.Compilation.init(t.allocator, "pool-loop.my", text);
    defer c.deinit();
    try c.emit();
    for ([_]language.vm.MemoryBacking{ .general, .arena }) |backing| {
        var bounded: @import("test_support.zig").LimitedLiveAllocator = .{ .parent = t.allocator, .limit = 16 * 1024 };
        const actual = try c.executeWithOptions(bounded.allocator(), .{ .memory_backing = backing });
        try t.expectEqual(@as(i64, 10000), actual.value);
        try t.expectEqual(@as(usize, 0), bounded.live);
    }
}
test "bytecode rejects pool schema construction and operation type mismatches" {
    var c = try language.Compilation.init(t.allocator, "pool-bytecode.my", graph);
    defer c.deinit();
    try c.emit();
    const bc = @import("bytecode.zig");
    const records = @constCast(c.code.?.records);
    var checked_pool = false;
    var checked_handle = false;
    for (records) |*schema| {
        const saved = schema.*;
        defer schema.* = saved;
        if (schema.pool != null) {
            schema.move_only = false;
            try t.expectError(error.InternalError, bc.validate(t.allocator, c.code.?));
            checked_pool = true;
        }
        if (schema.handle_pool != null) {
            schema.handle_pool = .i64;
            try t.expectError(error.InternalError, bc.validate(t.allocator, c.code.?));
            checked_handle = true;
        }
    }
    try t.expect(checked_pool and checked_handle);
    var checked_operation = false;
    for (c.code.?.functions) |function| for (@constCast(function.instructions)) |*instruction| {
        const saved = instruction.*;
        defer instruction.* = saved;
        if (instruction.op == .pool_operation) {
            instruction.op.pool_operation.output = .i64;
            try t.expectError(error.InternalError, bc.validate(t.allocator, c.code.?));
            checked_operation = true;
        }
    };
    try t.expect(checked_operation);
}

test "pool discovery normalizes binding names and preserves operations and nominal categories" {
    var c = try language.Compilation.init(t.allocator, "pool-discovery.my", declarations ++ "pool Q(QId): i64; fn a(p: P) -> u64 { return len_pool(p); } fn b(renamed: P) -> u64 { return len_pool(renamed); } fn different(p: P) -> u64 { return capacity_pool(p); } fn category(p: Q) -> u64 { return len_pool(p); } fn main() -> i64 { return 0; }");
    defer c.deinit();
    try c.check();
    var found = try language.duplicates.discover(t.allocator, c.program.?, .{ .min_nodes = 1, .approximate = true });
    defer found.deinit();
    try t.expectEqual(@as(usize, 1), found.groups.len);
    try t.expectEqual(@as(usize, 2), found.groups[0].members.len);
    try t.expectEqual(@as(usize, 0), @backingInt(found.groups[0].members[0]));
    try t.expectEqual(@as(usize, 1), @backingInt(found.groups[0].members[1]));
}
test "pool execution requires explicit allocator authority" {
    var c = try language.Compilation.init(t.allocator, "pool-authority.my", graph);
    defer c.deinit();
    var statistics: runtime.Statistics = .{};
    try t.expectError(error.CapabilityUnavailable, c.executeWithOptions(t.allocator, .{ .provide_allocator = false, .pool_statistics = &statistics }));
    try t.expectEqual(@as(u64, 0), statistics.acquired);
    try reject("fn main() -> i64 { acknowledge acquire_pool<Open>(1, 2); return 0; }", "E_TYPE");
    try reject("fn f(p: P, id: Id) -> Change { return read_pool<Change>(p, id); } fn main() -> i64 { return 0; }", "E_POOL_RESULT");
    try reject("pool Q(QId): i64; fn f(a: Id, b: QId) -> bool { return a == b; } fn main() -> i64 { return 0; }", "E_TYPE");
}
