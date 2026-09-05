const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const memory = @import("memory.zig");
const source = "buffer B: i64;\nresult Open { ok: B, err: i64 }\nstruct Pair { first: B, second: B, code: i64 }\nresult Work { ok: i64, err: i64 }\nfn work(heap: allocator) -> Work {\n    let pair = new Pair { first: try acquire_buffer<Open>(heap, 1), second: try acquire_buffer<Open>(heap, 1), code: 7 };\n    discard take_field(pair, first);\n    let spare = try acquire_buffer<Open>(heap, 1);\n    let second = take_field(pair, second);\n    return new Work.ok(read_field(pair, code) + cast<i64>(capacity_buffer(second)) + cast<i64>(capacity_buffer(spare)));\n}\nfn main(heap: allocator) -> i64 {\n    match work(heap) { Work.ok(value) => { return value; }, Work.err(code) => { return code; } }\n}\n";
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "partial.my", source);
    defer c.deinit();
    var stats: memory.Statistics = .{};
    const result = try c.executeWithOptions(allocator, .{ .memory_statistics = &stats, .memory_limits = .{ .max_allocations = 2 } });
    try t.expectEqual(@as(i64, 9), result.value);
    try t.expectEqual(@as(u64, 3), stats.created);
    try t.expectEqual(stats.created, stats.released);
    try t.expectEqual(@as(usize, 0), stats.live_allocations);
}
test "partial field transfer releases extracted buffers immediately and preserves remaining metadata and owners" {
    try scenario(t.allocator);
}
test "partial field bookkeeping and transferred values clean up on every allocation failure" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
test "partial field cleanup works at every instruction boundary on both memory backends" {
    var c = try language.Compilation.init(t.allocator, "partial.my", source);
    defer c.deinit();
    for ([_]language.vm.MemoryBacking{ .general, .arena }) |backing| {
        var completed = false;
        for (1..200) |budget| {
            var stats: memory.Statistics = .{};
            const result = try c.executeWithOptions(t.allocator, .{ .memory_backing = backing, .max_steps = budget, .memory_statistics = &stats, .memory_limits = .{ .max_allocations = 2 } });
            try t.expectEqual(stats.created, stats.released);
            if (result == .value) {
                try t.expectEqual(@as(i64, 9), result.value);
                completed = true;
                break;
            }
            try t.expectEqualStrings("R_STEP_LIMIT", result.trap.code);
        }
        try t.expect(completed);
    }
}
const declarations = "buffer B: i64; struct Pair { first: B, second: B, code: i64 } ";
fn reject(text: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "partial.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[c.diagnostics.items.len - 1].code);
}
test "moved fields whole-value escape inconsistent branches loops and short circuits are rejected" {
    try reject(declarations ++ "fn f(pair: Pair) -> i64 { discard take_field(pair, first); discard take_field(pair, first); return 0; } fn main() -> i64 { return 0; }", "E_FIELD_MOVED");
    try reject(declarations ++ "fn f(pair: Pair) -> Pair { discard take_field(pair, first); return pair; } fn main() -> i64 { return 0; }", "E_PARTIAL_MOVE");
    try reject(declarations ++ "fn f(pair: Pair) -> i64 { discard take_field(pair, code); return read_field(pair, code); } fn main() -> i64 { return 0; }", "E_FIELD_MOVED");
    try reject(declarations ++ "fn f(pair: Pair, flag: bool) -> i64 { if flag { discard take_field(pair, first); } else { discard take_field(pair, second); } return 0; } fn main() -> i64 { return 0; }", "E_OWNED_PATH");
    try reject(declarations ++ "fn f(pair: Pair) -> i64 { while false { discard take_field(pair, first); } return 0; } fn main() -> i64 { return 0; }", "E_OWNED_LOOP");
    try reject(declarations ++ "fn f(pair: Pair) -> bool { return false && take_field(pair, code) == 1; } fn main() -> i64 { return 0; }", "E_OWNED_PATH");
    try reject("struct Plain { code: i64 } fn main() -> i64 { let p = new Plain { code: 7 }; return take_field(p, code); }", "E_FIELD_TAKE");
}
test "result obligations remain on untouched fields and transfer independently" {
    const prefix = "result R { ok: i64, err: i64 } struct Pair { first: R, second: R, code: i64 } ";
    try reject(prefix ++ "fn f(pair: Pair) -> i64 { acknowledge take_field(pair, first); return 0; } fn main() -> i64 { return 0; }", "E_RESULT_UNHANDLED");
    try reject(prefix ++ "fn f(pair: Pair) -> i64 { discard take_field(pair, first); return 0; } fn main() -> i64 { return 0; }", "E_RESULT_DISCARD");
    var c = try language.Compilation.init(t.allocator, "results.my", prefix ++ "fn f(pair: Pair) -> i64 { acknowledge take_field(pair, first); acknowledge take_field(pair, second); return read_field(pair, code); } fn main() -> i64 { return f(new Pair { first: new R.ok(1), second: new R.err(2), code: 7 }); }");
    defer c.deinit();
    try t.expectEqual(@as(i64, 7), (try c.execute(t.allocator)).value);
}
test "equal branch field states can join and replacing the whole binding restores its fields" {
    const prefix = "result R { ok: i64, err: i64 } struct Pair { first: R, second: R } ";
    var c = try language.Compilation.init(t.allocator, "branches.my", prefix ++ "fn f(input: Pair, flag: bool) -> i64 { let mut pair = input; if flag { acknowledge take_field(pair, first); acknowledge take_field(pair, second); } else { acknowledge take_field(pair, second); acknowledge take_field(pair, first); } pair = new Pair { first: new R.ok(3), second: new R.ok(4) }; acknowledge pair; return 7; } fn main() -> i64 { return f(new Pair { first: new R.ok(1), second: new R.ok(2) }, false); }");
    defer c.deinit();
    try t.expectEqual(@as(i64, 7), (try c.execute(t.allocator)).value);
    try reject(prefix ++ "fn f(input: Pair) -> i64 { let mut pair = input; acknowledge take_field(pair, first); pair = new Pair { first: new R.ok(3), second: new R.ok(4) }; acknowledge pair; return 0; } fn main() -> i64 { return 0; }", "E_RESULT_OVERWRITE");
}
test "nested record fields transfer intact and can then be partially moved themselves" {
    const text = "result R { ok: i64, err: i64 } struct Inner { result: R, code: i64 } struct Outer { inner: Inner, code: i64 } fn main() -> i64 { let outer = new Outer { inner: new Inner { result: new R.ok(1), code: 3 }, code: 4 }; let inner = take_field(outer, inner); acknowledge take_field(inner, result); return read_field(inner, code) + read_field(outer, code); }";
    var c = try language.Compilation.init(t.allocator, "nested.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 7), (try c.execute(t.allocator)).value);
}
test "unique aggregate field transfer guards aliases preserves other snapshots and skips moved cleanup" {
    const Value = @import("value.zig").Value;
    const ty: @import("value.zig").Type = @fromBackingInt(@import("value.zig").Type.record_base);
    const child = try Value.create(t.allocator, ty, &.{.{ .i64 = 7 }});
    defer child.release(t.allocator);
    const parent = try Value.create(t.allocator, ty, &.{ child, .{ .i64 = 9 } });
    var alive = true;
    defer if (alive) parent.release(t.allocator);
    const alias = parent.retain();
    try t.expectError(error.InternalError, parent.takeField(t.allocator, 0));
    alias.release(t.allocator);
    const moved = try parent.takeField(t.allocator, 0);
    defer moved.release(t.allocator);
    try t.expectError(error.InternalError, parent.getField(0));
    try t.expectError(error.InternalError, parent.takeField(t.allocator, 0));
    try t.expectError(error.InternalError, parent.updated(t.allocator, &.{1}, &.{.{ .i64 = 11 }}));
    try t.expectEqual(@as(i64, 9), (try parent.getField(1)).i64);
    parent.release(t.allocator);
    alive = false;
    const field = try moved.getField(0);
    defer field.release(t.allocator);
    try t.expectEqual(@as(i64, 7), field.i64);
}

test "recoverable propagation cleans both an extracted owner and the record remainder" {
    const text = try std.mem.replaceOwned(u8, t.allocator, source, "discard take_field(pair, first);", "let extracted = take_field(pair, first);");
    defer t.allocator.free(text);
    var c = try language.Compilation.init(t.allocator, "partial-failure.my", text);
    defer c.deinit();
    var stats: memory.Statistics = .{};
    try t.expectEqual(@as(i64, 1), (try c.executeWithOptions(t.allocator, .{ .memory_limits = .{ .max_allocations = 2 }, .memory_statistics = &stats })).value);
    try t.expectEqual(@as(u64, 2), stats.created);
    try t.expectEqual(stats.created, stats.released);
}

test "partial field bytecode validates schemas and runtime rejects repeated extraction with complete cleanup" {
    var c = try language.Compilation.init(t.allocator, "malformed.my", source);
    defer c.deinit();
    try c.emit();
    var found: usize = 0;
    for (c.code.?.functions) |function| {
        const instructions = @constCast(function.instructions);
        for (instructions) |*instruction| {
            if (instruction.op != .take_field) continue;
            found += 1;
            if (found != 2) continue;
            const original = instruction.*;
            defer instruction.* = original;
            instruction.op.take_field.output = .bool;
            try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
            instruction.* = original;
            instruction.op.take_field.field = 0;
            try language.bytecode.validate(t.allocator, c.code.?);
            var stats: memory.Statistics = .{};
            try t.expectError(error.InternalError, c.executeWithOptions(t.allocator, .{ .memory_statistics = &stats }));
            try t.expectEqual(stats.created, stats.released);
            try t.expectEqual(@as(usize, 0), stats.live_allocations);
        }
    }
    try t.expectEqual(@as(usize, 2), found);
}

test "duplicate discovery distinguishes field reads from transfers while normalizing bound names" {
    var c = try language.Compilation.init(t.allocator, "discovery.my", declarations ++ "fn a(pair: Pair) -> i64 { return take_field(pair, code); } fn renamed(input: Pair) -> i64 { return take_field(input, code); } fn b(pair: Pair) -> i64 { return read_field(pair, code); } fn main() -> i64 { return 0; }");
    defer c.deinit();
    try c.check();
    var analysis = try language.duplicates.discover(t.allocator, c.program.?, .{ .min_nodes = 1 });
    defer analysis.deinit();
    try t.expectEqual(@as(usize, 1), analysis.groups.len);
    try t.expectEqual(@as(usize, 2), analysis.groups[0].members.len);
}
test "repeated partial moves and remainder cleanup stay within bounded live runtime memory" {
    const text = declarations ++ "result Open { ok: B, err: i64 } result Work { ok: i64, err: i64 } fn work(heap: allocator) -> Work { let mut i = 0; while i < 10000 { let pair = new Pair { first: try acquire_buffer<Open>(heap, 1), second: try acquire_buffer<Open>(heap, 1), code: 1 }; discard take_field(pair, first); i += read_field(pair, code); } return new Work.ok(i); } fn main(heap: allocator) -> i64 { match work(heap) { Work.ok(value) => { return value; }, Work.err(code) => { return -code; } } }";
    var c = try language.Compilation.init(t.allocator, "loops.my", text);
    defer c.deinit();
    try c.emit();
    var limited: @import("test_support.zig").LimitedLiveAllocator = .{ .parent = t.allocator, .limit = 16384 };
    var stats: memory.Statistics = .{};
    try t.expectEqual(@as(i64, 10000), (try c.executeWithOptions(limited.allocator(), .{ .memory_statistics = &stats, .memory_limits = .{ .max_allocations = 2 } })).value);
    try t.expectEqual(@as(u64, 20000), stats.created);
    try t.expectEqual(stats.created, stats.released);
    try t.expectEqual(@as(usize, 0), limited.live);
}
