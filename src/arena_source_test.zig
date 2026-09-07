//! Source arena allocation tests covering region entry, ownership cleanup, capability lifetime, and repeated execution.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const memory = @import("memory.zig");
const pools = @import("pool_runtime.zig");
const program =
    \\pool Nodes(NodeId): Node;
    \\struct Node { value: i64 }
    \\result OpenPool { ok: Nodes, err: i64 }
    \\result Insert { ok: NodeId, err: i64 }
    \\result Read { ok: Node, err: i64 }
    \\buffer B: i64;
    \\result OpenBuffer { ok: B, err: i64 }
    \\result Change { ok: bool, err: i64 }
    \\result Work { ok: i64, err: i64 }
    \\fn snapshot(heap: allocator) -> Read {
    \\    let mut nodes = try acquire_pool<OpenPool>(heap, 1);
    \\    let id = try insert_pool<Insert>(nodes, new Node { value: 42 });
    \\    return read_pool<Read>(nodes, id);
    \\}
    \\fn work(heap: allocator) -> Work {
    \\    let mut value = 0;
    \\    arena heap as outer {
    \\        arena outer as inner {
    \\            let retained = try snapshot(inner);
    \\            let mut buffer = try acquire_buffer<OpenBuffer>(inner, 2);
    \\            discard try append_buffer<Change>(buffer, 8);
    \\            borrow buffer[0..1] as view {
    \\                value = retained.value + read_slice(view, 0);
    \\            }
    \\        }
    \\    }
    \\    return new Work.ok(value);
    \\}
    \\fn main(heap: allocator) -> i64 {
    \\    match work(heap) { Work.ok(value) => { return value; }, Work.err(code) => { return code; } }
    \\}
;

fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "arenas.my", program);
    defer c.deinit();
    var buffers: memory.Statistics = .{};
    var registry: pools.Statistics = .{};
    const result = c.executeWithOptions(allocator, .{
        .memory = .{ .statistics = &buffers },
        .pools = .{ .statistics = &registry },
    }) catch |err| {
        if (err != error.OutOfMemory) @import("diagnostics_test.zig").report(c.diagnostics.items);
        return err;
    };
    try t.expectEqual(@as(i64, 50), result.value);
    try t.expectEqual(@as(u64, 1), buffers.created);
    try t.expectEqual(buffers.created, buffers.released);
    try t.expectEqual(@as(u64, 1), registry.acquired);
    try t.expectEqual(registry.acquired, registry.released);
}
test "nested source arenas support helpers pool snapshots buffers and borrowed views" {
    try scenario(t.allocator);
}
test "executeBeginRegion bookkeeping and snapshots unwind on every allocation failure" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
fn reject(text: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "arena-escape.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
const declarations = "buffer B: i64; result Open { ok: B, err: i64 } ";
// spec: OWN-6
test "source arena capabilities owners and wrappers cannot escape through returns and assignments" {
    try reject("fn f(heap: allocator) -> allocator { arena heap as scratch { return scratch; } } fn main() -> i64 { return 0; }", "E_ARENA_ESCAPE");
    try reject("fn f(heap: allocator) -> allocator { let mut outside = heap; arena heap as scratch { outside = scratch; } return outside; } fn main() -> i64 { return 0; }", "E_ARENA_ESCAPE");
    try reject(declarations ++ "fn f(heap: allocator) -> Open { arena heap as scratch { return acquire_buffer<Open>(scratch, 1); } } fn main() -> i64 { return 0; }", "E_ARENA_ESCAPE");
    try reject(declarations ++ "struct Box { owned: B } result BoxResult { ok: Box, err: i64 } fn f(heap: allocator) " ++
        "-> BoxResult { arena heap as scratch { return new BoxResult.ok(new Box { owned: try " ++
        "acquire_buffer<Open>(scratch, 1) }); } } fn main() -> i64 { return 0; }", "E_ARENA_ESCAPE");
    try reject("fn identity(input: allocator) -> allocator { return input; } fn f(heap: allocator) -> allocator { arena heap as scratch { return identity(scratch); } } fn main() -> i64 { return 0; }", "E_ARENA_ESCAPE");
    try reject("struct Box { cap: allocator } fn f(heap: allocator) -> Box { arena heap as scratch { return new Box { cap: scratch }; } } fn main() -> i64 { return 0; }", "E_ARENA_ESCAPE");
    try reject("fn f(heap: allocator) -> i64 { arena heap as scratch {} discard scratch; return 0; } fn main() -> i64 { return 0; }", "E_UNKNOWN_NAME");
}
test "arena escape checks include mutable references helper writes and container storage" {
    try reject("fn set(dest: &mut allocator, cap: allocator) -> i64 { write_ref(dest, cap); return 0;" ++
        " } fn main(heap: allocator) -> i64 { let mut outside = heap; borrow mut outside as " ++
        "dest { arena heap as scratch { discard set(dest, scratch); } } return 0; }", "E_ARENA_ESCAPE");
    try reject("fn main(heap: allocator) -> i64 { let mut outside = new [1]allocator[heap]; borrow mut outside[0..1] as dest { arena heap as scratch { write_slice(dest, 0, scratch); } } return 0; }", "E_ARENA_ESCAPE");
    try reject("buffer Caps: allocator; result Open { ok: Caps, err: i64 } result Change { ok: bool, " ++
        "err: i64 } fn f(heap: allocator) -> Change { let mut caps = try " ++
        "acquire_buffer<Open>(heap, 1); arena heap as scratch { return " ++
        "append_buffer<Change>(caps, scratch); } } fn main() -> i64 { return 0; }", "E_ARENA_ESCAPE");
    try reject("pool Caps(Id): allocator; result Open { ok: Caps, err: i64 } result Insert { ok: Id, " ++
        "err: i64 } fn f(heap: allocator) -> Insert { let mut caps = try " ++
        "acquire_pool<Open>(heap, 1); arena heap as scratch { return insert_pool<Insert>(caps," ++
        " scratch); } } fn main() -> i64 { return 0; }", "E_ARENA_ESCAPE");
    try reject("fn set(dest: &mut allocator, cap: allocator) -> i64 { write_ref(dest, cap); return 0;" ++
        " } fn f(heap: allocator) -> allocator { arena heap as scratch { let mut inside = " ++
        "heap; borrow mut inside as dest { discard set(dest, scratch); } return inside; } } " ++
        "fn main() -> i64 { return 0; }", "E_ARENA_ESCAPE");
}

test "source arena cleanup survives every instruction boundary with both execution backings" {
    var c = try language.Compilation.init(t.allocator, "arena-traps.my", program);
    defer c.deinit();
    for ([_]language.vm.MemoryBacking{ .general, .arena }) |backing| {
        var completed = false;
        for (1..500) |budget| {
            var buffers: memory.Statistics = .{};
            var registry: pools.Statistics = .{};
            const result = try c.executeWithOptions(t.allocator, .{ .memory = .{ .statistics = &buffers, .backing = backing }, .pools = .{ .statistics = &registry }, .max_steps = budget });
            try t.expectEqual(buffers.created, buffers.released);
            try t.expectEqual(registry.acquired, registry.released);
            if (result == .value) {
                try t.expectEqual(@as(i64, 50), result.value);
                completed = true;
                break;
            }
            try t.expectEqualStrings("R_STEP_LIMIT", result.trap.code);
        }
        try t.expect(completed);
    }
}
fn expectResult(text: []const u8, expected: i64, options: language.vm.Options) !void {
    var c = try language.Compilation.init(t.allocator, "arena-flow.my", text);
    defer c.deinit();
    const result = c.executeWithOptions(t.allocator, options) catch |err| {
        @import("diagnostics_test.zig").report(c.diagnostics.items);
        return err;
    };
    try t.expectEqual(expected, result.value);
}
test "return and propagation close frame regions after releasing owners" {
    try expectResult(declarations ++ "result Work { ok: i64, err: i64 } fn f(heap: allocator) -> Work { arena heap as " ++
        "outer { arena outer as inner { let buffer = try acquire_buffer<Open>(inner, 1); " ++
        "return new Work.ok(9); } } } fn main(heap: allocator) -> i64 { acknowledge f(heap); " ++
        "arena heap as outer { arena outer as inner { return 7; } } }", 7, .{
        .memory = .{ .limits = .{ .max_regions = 2, .max_allocations = 1 } },
    });
    try expectResult(declarations ++ "result Work { ok: i64, err: i64 } fn f(heap: allocator) -> Work { arena heap as " ++
        "scratch { let first = try acquire_buffer<Open>(scratch, 1); let second = try " ++
        "acquire_buffer<Open>(scratch, 1); return new Work.ok(99); } } fn main(heap: " ++
        "allocator) -> i64 { match f(heap) { Work.ok(discard) => { return 98; }, " ++
        "Work.err(code) => { if code != 1 { return 97; } } } arena heap as scratch { match " ++
        "acquire_buffer<Open>(scratch, 1) { Open.ok(discard) => { return 8; }, " ++
        "Open.err(discard) => { return 96; } } } }", 8, .{
        .memory = .{ .limits = .{ .max_regions = 1, .max_allocations = 1 } },
    });
}
test "heap owners plain snapshots and inert IDs can leave an arena scope" {
    try expectResult(declarations ++ "fn f(heap: allocator) -> Open { arena heap as scratch { return " ++
        "acquire_buffer<Open>(heap, 2); } } fn main(heap: allocator) -> i64 { match f(heap) { " ++
        "Open.ok(buffer) => { return cast<i64>(capacity_buffer(buffer)); }, Open.err(code) => " ++
        "{ return code; } } }", 2, .{});
    try expectResult("struct Plain { value: i64 } fn main(heap: allocator) -> i64 { let mut outside = new Plain { value: 0 }; arena heap as scratch { outside = new Plain { value: 11 }; } return outside.value; }", 11, .{});
    try expectResult("pool P(Id): i64; result Open { ok: P, err: i64 } result Insert { ok: Id, err: i64 } " ++
        "result Read { ok: i64, err: i64 } fn make(heap: allocator) -> Insert { arena heap as " ++
        "scratch { let mut pool = try acquire_pool<Open>(scratch, 1); return " ++
        "insert_pool<Insert>(pool, 7); } } fn work(heap: allocator) -> Read { let old = try " ++
        "make(heap); let pool = try acquire_pool<Open>(heap, 1); return read_pool<Read>(pool, " ++
        "old); } fn main(heap: allocator) -> i64 { match work(heap) { Read.ok(v) => { return " ++
        "v; }, Read.err(e) => { return e; } } }", 2, .{});
}
test "arena escape analysis includes propagation payloads branches loops and borrowed buffer storage" {
    try reject("result R { ok: i64, err: allocator } fn f(heap: allocator) -> R { arena heap as scratch { discard try new R.err(scratch); } return new R.ok(0); } fn main() -> i64 { return 0; }", "E_ARENA_ESCAPE");
    try reject("fn f(heap: allocator, flag: bool) -> allocator { let mut outside = heap; arena heap as scratch { if flag { outside = scratch; } } return outside; } fn main() -> i64 { return 0; }", "E_ARENA_ESCAPE");
    try reject("fn f(heap: allocator) -> allocator { let mut outside = heap; arena heap as scratch { while false { outside = scratch; } } return outside; } fn main() -> i64 { return 0; }", "E_ARENA_ESCAPE");
    try reject("buffer Caps: allocator; result Open { ok: Caps, err: i64 } result Change { ok: bool, " ++
        "err: i64 } fn f(heap: allocator) -> Change { let mut caps = try " ++
        "acquire_buffer<Open>(heap, 1); discard try append_buffer<Change>(caps, heap); borrow " ++
        "mut caps[0..1] as dest { arena heap as scratch { write_slice(dest, 0, scratch); } } " ++
        "return new Change.ok(true); } fn main() -> i64 { return 0; }", "E_ARENA_ESCAPE");
    try reject("fn set(dest: &mut allocator, source: &allocator) -> i64 { write_ref(dest, " ++
        "read_ref(source)); return 0; } fn main(heap: allocator) -> i64 { let mut outside = " ++
        "heap; borrow mut outside as dest { arena heap as scratch { borrow scratch as input { " ++
        "discard set(dest, input); } } } return 0; }", "E_ARENA_ESCAPE");
}
test "arena scope authority effect bounds and region limits are explicit" {
    try reject("fn main(heap: allocator) -> i64 noalloc { arena heap as scratch {} return 0; }", "E_EFFECT_BOUND");
    try reject("fn main() -> i64 { arena 1 as scratch {} return 0; }", "E_TYPE");
    try reject("fn main(heap: allocator) -> i64 { arena heap as heap {} return 0; }", "E_SHADOWING");
    var c = try language.Compilation.init(t.allocator, "arena-limit.my", "fn main(heap: allocator) -> i64 { arena heap as outer { arena outer as inner {} } return 0; }");
    defer c.deinit();
    const result = try c.executeWithOptions(t.allocator, .{
        .memory = .{ .limits = .{ .max_regions = 1 } },
    });
    try t.expectEqualStrings("R_REGION_LIMIT", result.trap.code);
}
test "ten thousand source arena scopes reclaim mixed backing within bounded live storage" {
    const text = comptime program[0..std.mem.indexOf(u8, program, "fn work").?] ++ "fn work(heap: allocator) -> Work { let mut n = 0; while n < 10000 { arena heap as " ++
        "scratch { let node = try snapshot(scratch); let buffer = try " ++
        "acquire_buffer<OpenBuffer>(scratch, 1); if node.value != 42 { return new " ++
        "Work.err(99); } } n += 1; } return new Work.ok(n); } fn main(heap: allocator) -> i64 " ++
        "{ match work(heap) { Work.ok(v) => { return v; }, Work.err(e) => { return e; } } }";
    var c = try language.Compilation.init(t.allocator, "arena-loop.my", text);
    defer c.deinit();
    try c.emit();
    for ([_]language.vm.MemoryBacking{ .general, .arena }) |backing| {
        var limited: @import("test_support.zig").LimitedLiveAllocator = .{ .parent = t.allocator, .limit = 16 * 1024 };
        defer limited.deinit();
        const result = try c.executeWithOptions(limited.allocator(), .{
            .memory = .{ .backing = backing, .limits = .{ .max_regions = 1 } },
        });
        try t.expectEqual(@as(i64, 10000), result.value);
        try t.expectEqual(@as(usize, 0), limited.live);
    }
}
test "duplicate discovery preserves arena boundaries while normalizing allocator names" {
    var c = try language.Compilation.init(t.allocator, "arena-duplicates.my", "fn a(heap: allocator) -> i64 { arena heap as scratch { discard scratch; } return 7; }" ++
        " fn b(parent: allocator) -> i64 { arena parent as region { discard region; } return " ++
        "7; } fn c(heap: allocator) -> i64 { discard heap; return 7; } fn main() -> i64 { " ++
        "return 0; }");
    defer c.deinit();
    try c.check();
    var found = try language.duplicates.discover(t.allocator, c.program.?, .{ .min_nodes = 1 });
    defer found.deinit();
    try t.expectEqual(@as(usize, 1), found.groups.len);
    try t.expectEqual(@as(usize, 2), found.groups[0].members.len);
}

test "bytecode rejects invalid arena targets and runtime rejects mismatched region closure" {
    var c = try language.Compilation.init(t.allocator, "arena-bytecode.my", program);
    defer c.deinit();
    try c.emit();
    const bc = @import("bytecode.zig");
    var checked = false;
    for (c.code.?.functions) |function| {
        var first_slot: ?@import("typed.zig").LocalId = null;
        for (@constCast(function.scope.instructions)) |*instruction| {
            const saved = instruction.*;
            defer instruction.* = saved;
            if (instruction.op == .begin_region) {
                if (first_slot == null) first_slot = instruction.op.begin_region;
                instruction.op.begin_region = @fromBackingInt(0);
                try t.expectError(error.InternalError, bc.validate(t.allocator, c.code.?));
            }
            if (instruction.op == .end_region and first_slot != null and first_slot.? != instruction.op.end_region) {
                instruction.op.end_region = first_slot.?;
                var buffers: memory.Statistics = .{};
                var registry: pools.Statistics = .{};
                try t.expectError(error.InternalError, c.executeWithOptions(t.allocator, .{
                    .memory = .{ .statistics = &buffers },
                    .pools = .{ .statistics = &registry },
                }));
                try t.expectEqual(buffers.created, buffers.released);
                try t.expectEqual(registry.acquired, registry.released);
                checked = true;
            }
        }
    }
    try t.expect(checked);
}

test "arena-local capability containers work while plain pool snapshots survive scope exit" {
    try expectResult("fn inspect(outer: &allocator, inner: &allocator) -> i64 { return 7; } fn main(heap: " ++
        "allocator) -> i64 { let mut outside = heap; borrow mut outside as dest { arena heap " ++
        "as scratch { borrow scratch as input { return inspect(dest, input); } } } }", 7, .{});
    try expectResult("pool Caps(Id): allocator; result Open { ok: Caps, err: i64 } result Insert { ok: Id, " ++
        "err: i64 } result Read { ok: allocator, err: i64 } buffer B: i64; result Buffer { " ++
        "ok: B, err: i64 } result Work { ok: i64, err: i64 } fn set(dest: &mut allocator, " ++
        "cap: allocator) -> i64 { write_ref(dest, cap); return 0; } fn work(heap: allocator) " ++
        "-> Work { arena heap as scratch { let mut alias = heap; borrow mut alias as dest { " ++
        "discard set(dest, scratch); } let mut caps = try acquire_pool<Open>(scratch, 1); let " ++
        "id = try insert_pool<Insert>(caps, alias); let from_pool = try read_pool<Read>(caps, " ++
        "id); let buffer = try acquire_buffer<Buffer>(from_pool, 3); return new " ++
        "Work.ok(cast<i64>(capacity_buffer(buffer))); } } fn main(heap: allocator) -> i64 { " ++
        "match work(heap) { Work.ok(v) => { return v; }, Work.err(e) => { return e; } } }", 3, .{});
    const source = comptime program[0..std.mem.indexOf(u8, program, "fn work").?] ++ "fn work(heap: allocator) -> Work { let mut outside = new Node { value: 0 }; arena " ++
        "heap as scratch { outside = try snapshot(scratch); } return new " ++
        "Work.ok(outside.value); } fn main(heap: allocator) -> i64 { match work(heap) { " ++
        "Work.ok(v) => { return v; }, Work.err(e) => { return e; } } }";
    try expectResult(source, 42, .{});
}

const provenance_source =
    \\fn choose(outer:allocator,scratch:allocator)->allocator {discard scratch;return outer;}
    \\fn work(heap:allocator)->allocator {
    \\    let mut selected=heap;
    \\    arena heap as scratch {selected=choose(heap,scratch);}
    \\    return selected;
    \\}
    \\fn main(heap:allocator)->i64 {discard work(heap);return 7;}
;
fn provenanceScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "provenance.my", provenance_source);
    defer c.deinit();
    const result = try c.execute(allocator);
    try t.expectEqual(@as(i64, 7), result.value);
}
// spec: REGION-PROVENANCE-1
test "directReturns excludes unrelated scratch authority and unwinds every allocation failure" {
    try provenanceScenario(t.allocator);
    try t.checkAllAllocationFailures(t.allocator, provenanceScenario, .{});
}
test "direct returned scratch authority remains a rejected region escape" {
    const source = try std.mem.replaceOwned(u8, t.allocator, provenance_source, "choose(heap,scratch)", "choose(scratch,heap)");
    defer t.allocator.free(source);
    var c = try language.Compilation.init(t.allocator, "escape.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_ARENA_ESCAPE", c.diagnostics.items[0].code);
}

test "multiple possible returned parameters conservatively retain scratch dependency" {
    const source = try std.mem.replaceOwned(u8, t.allocator, provenance_source, "discard scratch;return outer;", "if true {return outer;} else {return scratch;}");
    defer t.allocator.free(source);
    var c = try language.Compilation.init(t.allocator, "branches.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_ARENA_ESCAPE", c.diagnostics.items[0].code);
}
