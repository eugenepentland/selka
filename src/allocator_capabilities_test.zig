const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const memory = @import("memory.zig");
const declarations = "buffer B: i64; result R { ok: B, err: i64 } result Status { ok: bool, err: i64 } ";
fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "capabilities.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

const forwarded = declarations ++ "struct Authority { heap: allocator } fn echo(heap: allocator) -> allocator effects() { return heap; } fn grow(auth: Authority, input: B) -> R { let mut b = input; discard try reserve_buffer<Status>(b, auth.heap, 3); return new R.ok(b); } fn make(heap: allocator) -> R { let copy = echo(heap); let b = try acquire_buffer<R>(copy, 1); return grow(new Authority { heap: heap }, b); } fn main(heap: allocator) -> i64 { match make(heap) { R.ok(b) => { return cast<i64>(capacity_buffer(b)); }, R.err(e) => { return e; } } }";
fn forwardingScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "capabilities.my", forwarded);
    defer c.deinit();
    var stats: memory.Statistics = .{};
    try t.expectEqual(@as(i64, 3), (try c.executeWithOptions(allocator, .{ .memory_statistics = &stats })).value);
    try t.expectEqual(@as(u64, 1), stats.created);
    try t.expectEqual(stats.created, stats.released);
}
test "entry allocator capabilities flow explicitly through copies wrappers calls and returns" {
    try forwardingScenario(t.allocator);
}

test "allocator capability copies share a ceiling and cannot amplify authority" {
    var c = try language.Compilation.init(t.allocator, "limits.my", forwarded);
    defer c.deinit();
    var stats: memory.Statistics = .{};
    const result = try c.executeWithOptions(t.allocator, .{ .memory_limits = .{ .max_buffer_capacity = 2 }, .memory_statistics = &stats });
    try t.expectEqual(@as(i64, 1), result.value);
    try t.expectEqual(@as(u64, 1), stats.created);
    try t.expectEqual(stats.created, stats.released);
}

test "entry capability provisioning can be denied and scalar entry needs no capability" {
    var c = try language.Compilation.init(t.allocator, "denied.my", forwarded);
    defer c.deinit();
    var stats: memory.Statistics = .{};
    try t.expectError(error.CapabilityUnavailable, c.executeWithOptions(t.allocator, .{ .provide_allocator = false, .memory_statistics = &stats }));
    try t.expectEqual(@as(u64, 0), stats.created);
    var scalar = try language.Compilation.init(t.allocator, "scalar.my", "fn main() -> i64 { return 7; }");
    defer scalar.deinit();
    try t.expectEqual(@as(i64, 7), (try scalar.executeWithOptions(t.allocator, .{ .provide_allocator = false })).value);
}

test "safe source cannot manufacture allocator authority or use the old ambient syntax" {
    try reject(declarations ++ "fn main() -> i64 { acknowledge acquire_buffer<R>(1); return 0; }", "E_SYNTAX");
    try reject(declarations ++ "fn main() -> i64 { acknowledge acquire_buffer<R>(0, 1); return 0; }", "E_TYPE");
    try reject("fn forge() -> allocator { return cast<allocator>(0); } fn main() -> i64 { return 0; }", "E_TYPE");
    try reject("fn forge() -> allocator { return 0; } fn main() -> i64 { return 0; }", "E_TYPE");
    try reject("fn main(heap: allocator) -> i64 { return cast<i64>(heap); }", "E_TYPE");
    try reject(declarations ++ "fn forge() -> R effects(allocation) { return acquire_buffer<R>(heap, 1); } fn main() -> i64 { return 0; }", "E_UNKNOWN_NAME");
    try reject(declarations ++ "fn make(heap: allocator) -> R { return acquire_buffer<R>(heap, 1); } fn main() -> i64 { acknowledge make(); return 0; }", "E_ARITY");
    try reject("fn main(heap: &allocator) -> i64 { return 0; }", "E_MAIN");
    try reject("fn main(a: allocator, b: allocator) -> i64 { return 0; }", "E_MAIN");
    try reject(declarations ++ "fn grow(input: B) -> R { let mut b = input; acknowledge reserve_buffer<Status>(b, 0, 1); return new R.ok(b); } fn main() -> i64 { return 0; }", "E_TYPE");
}

test "possessing allocator authority does not bypass noalloc and forwarding authority has no effect" {
    try reject(declarations ++ "fn make(heap: allocator) -> R noalloc { return acquire_buffer<R>(heap, 1); } fn main() -> i64 { return 0; }", "E_EFFECT_BOUND");
    var c = try language.Compilation.init(t.allocator, "forward.my", "fn forward(heap: allocator) -> allocator effects() { return heap; } fn main(heap: allocator) -> i64 noalloc { discard forward(heap); return 5; }");
    defer c.deinit();
    try t.expectEqual(@as(i64, 5), (try c.execute(t.allocator)).value);
    for (c.program.?.functions) |function| try t.expectEqual(@as(u8, 0), function.effects);
}

test "allocator capability identities reject foreign stale and closed stores" {
    var first = try memory.Store.init(t.allocator);
    defer first.deinit();
    var other = try memory.Store.init(t.allocator);
    defer other.deinit();
    const capability = try first.allocatorCapability();
    try first.checkAllocator(capability);
    try t.expectError(error.InvalidCapability, other.checkAllocator(capability));
    first.deinit();
    try t.expectError(error.InvalidCapability, first.checkAllocator(capability));
    first = try memory.Store.init(t.allocator);
    try t.expectError(error.InvalidCapability, first.checkAllocator(capability));
    try t.expectError(error.InvalidCapability, first.checkAllocator(.{ .memory = 0 }));
}

test "capability forwarding allocation growth and cleanup handle every allocation failure" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), forwardingScenario, .{});
}

test "emission and VM operand checks reject fabricated allocator inputs" {
    var c = try language.Compilation.init(t.allocator, "invalid.my", declarations ++ "fn main(heap: allocator) -> i64 { acknowledge acquire_buffer<R>(heap, 1); return 0; }");
    defer c.deinit();
    try c.emit();
    const functions = @constCast(c.code.?.functions);
    const original_count = functions[0].parameter_count;
    functions[0].parameter_count = 2;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    functions[0].parameter_count = original_count;
    for (@constCast(functions[0].instructions)) |*instruction| {
        if (instruction.op == .load_local) {
            const original = instruction.*;
            instruction.op = .{ .push_i64 = 0 };
            var stats: memory.Statistics = .{};
            try t.expectError(error.InternalError, language.vm.runWithOptions(t.allocator, c.code.?, .{ .memory_statistics = &stats }));
            try t.expectEqual(@as(u64, 0), stats.created);
            instruction.* = original;
            return;
        }
    }
    return error.TestUnexpectedResult;
}
