//! Growing scalar append copies preserve runtime operations and trap order.
const std = @import("std");
const t = std.testing;
const compiler = @import("compiler.zig");
const native = @import("native_execute.zig");
const runtime = @import("runtime_mode.zig");
const copy_proof = @import("qbe_rc_append_version.zig");
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const project = @import("project.zig");
const fixture_path = "append_range.my";
const test_log = std.debug.print;

const growing =
    \\def grown(n: int, seed: int) -> int:
    \\    values: list[int] = []
    \\    for i in range(n):
    \\        values.append((seed + i * 13) % 1009)
    \\    if n <= 0:
    \\        return len(values)
    \\    return len(values) + values[0] + values[-1]
    \\def main() -> int:
    \\    return grown(32, 17)
;

fn emitted(source: []const u8, mode: runtime.Selection, steps: bool) !std.json.Parsed(Manifest) {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(mode);
    var compilation = try compiler.Compilation.init(t.allocator, fixture_path, source);
    defer compilation.deinit();
    const text = compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = steps, .frame_checks = false }) catch |err| {
        for (compilation.diagnostics.items) |diagnostic| test_log("{s}: {s}\n", .{ diagnostic.code, diagnostic.message });
        return err;
    };
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

const Parts = struct { guard: []const u8, fast: []const u8, original: []const u8 };
fn parts(body: []const u8) !Parts {
    const begin = std.mem.indexOf(u8, body, "\n@fi") orelse return error.TestUnexpectedResult;
    const original = std.mem.indexOf(u8, body, "\n@oi") orelse return error.TestUnexpectedResult;
    return .{ .guard = body[0..begin], .fast = body[begin..original], .original = body[original..] };
}

// spec: RC-APPEND-RANGE-1
test "append range copy removes scalar checks and retains ordinary growing append in both copies" {
    var manifest = try emitted(growing, .rc, false);
    defer manifest.deinit();
    const body = try named(manifest.value, "grown");
    const loop = try parts(body);
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, body, "# mylang-rc-append-range "));
    try t.expect(std.mem.indexOf(u8, loop.guard, "myl_rc_list_plain_ready") == null);
    try t.expect(std.mem.indexOf(u8, loop.guard, "@rcpresized") == null);
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, loop.fast, "myl_qbe_fail_overflow_op"));
    try t.expect(std.mem.count(u8, loop.original, "myl_qbe_fail_overflow_op") >= 3);
    for ([_][]const u8{ loop.fast, loop.original }) |copy| {
        try t.expectEqual(@as(usize, 1), std.mem.count(u8, copy, "call $myl_rc_list_append("));
        try t.expectEqual(@as(usize, 1), std.mem.count(u8, copy, "call $myl_rc_list_plain_ready("));
        try t.expect(std.mem.indexOf(u8, copy, "%rcappend0") != null);
        try t.expect(std.mem.indexOf(u8, copy, "@rcappend_slow") != null);
        try t.expect(std.mem.indexOf(u8, copy, " cultl ") != null);
    }
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, body, "call $myl_rc_list_append("));
    try t.expect(std.mem.indexOf(u8, loop.fast, "RC-LOOP-OPERANDS-BEGIN") == null);
}

// spec-case: RC-APPEND-RANGE-1
test "append range exact frozen collection project has an admitted growing arithmetic copy" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const source = try std.Io.Dir.cwd().readFileAlloc(t.io, "benchmarks/runtime/expanded/collections/main.my", t.allocator, .limited(65536));
    defer t.allocator.free(source);
    var tree = project.Project.init(t.allocator);
    defer tree.deinit();
    try tree.load(.{ .context = @ptrCast(@constCast(&source)), .read = benchmarkRead }, "main", .{});
    var index = try compiler.interfaces.build(&tree);
    var compilation = try @import("project_compile.zig").Compilation.init(&index);
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = false, .frame_checks = false });
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer manifest.deinit();
    const body = try named(manifest.value, "main::batch_result");
    const marker = std.mem.indexOf(u8, body, "# mylang-rc-append-range ") orelse return error.TestUnexpectedResult;
    const loop = try parts(body[marker..]);
    try t.expect(copy_proof.ordinaryCopy(loop.fast));
    try t.expect(std.mem.indexOf(u8, loop.fast, "myl_qbe_fail_overflow_op") == null);
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, loop.fast, "call $myl_rc_list_append("));
    try t.expect(std.mem.count(u8, loop.original, "myl_qbe_fail_overflow_op") >= 4);
}

fn benchmarkRead(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    const source: *const []const u8 = @ptrCast(@alignCast(context.?));
    if (source.*.len > limit) return error.TooLarge;
    return allocator.dupe(u8, source.*);
}

const refused =
    \\def parameter(values: mut list[int], n: int, seed: int) -> int:
    \\    for i in range(n):
    \\        values.append(seed + i * 13)
    \\    return len(values)
    \\def used(n: int, seed: int) -> int:
    \\    values: list[int] = []
    \\    values.append(9)
    \\    for i in range(n):
    \\        values.append(seed + i * 13)
    \\    return len(values)
    \\def aliased(n: int, seed: int) -> int:
    \\    values: list[int] = []
    \\    saved = values
    \\    for i in range(n):
    \\        values.append(seed + i * 13)
    \\    return len(saved) + len(values)
    \\def squares(n: int) -> int:
    \\    values = [i * i for i in range(n)]
    \\    return len(values)
    \\def read_other(n: int, other: list[int]) -> int:
    \\    values: list[int] = []
    \\    for i in range(n):
    \\        values.append(other[i])
    \\    return len(values)
    \\def callback(i: int, out: Stream) -> int:
    \\    out.print(i)
    \\    return i
    \\def effectful(n: int, out: Stream) -> int:
    \\    values: list[int] = []
    \\    for i in range(n):
    \\        values.append(callback(i, out))
    \\    return len(values)
    \\def main() -> int:
    \\    return used(32, 17)
;

// spec-case: RC-APPEND-RANGE-1
test "append range refuses incoming used aliased dependent and effectful roots and retains presized comprehension" {
    var manifest = try emitted(refused, .rc, false);
    defer manifest.deinit();
    for ([_][]const u8{ "parameter", "used", "aliased", "read_other", "effectful" }) |name| {
        const body = try named(manifest.value, name);
        try t.expect(std.mem.indexOf(u8, body, "# mylang-rc-append-range") == null);
        try t.expect(std.mem.indexOf(u8, body, "call $myl_rc_list_append(") != null);
    }
    const squares = try named(manifest.value, "squares");
    try t.expect(std.mem.indexOf(u8, squares, "# mylang-rc-append-range") == null);
    try t.expect(std.mem.indexOf(u8, squares, "@rcpresized") != null);
}

// spec-case: RC-APPEND-RANGE-1
test "append range retains checked and collector protocols and counting append publication" {
    var checked = try emitted(growing, .rc, true);
    defer checked.deinit();
    try t.expect(std.mem.indexOf(u8, try named(checked.value, "grown"), "# mylang-rc-append-range") == null);
    var collector = try emitted(growing, .gc, false);
    defer collector.deinit();
    try t.expect(std.mem.indexOf(u8, try named(collector.value, "grown"), "# mylang-rc-append-range") == null);
    var counting = try emitted(growing, .rc_counting, false);
    defer counting.deinit();
    const loop = try parts(try named(counting.value, "grown"));
    try t.expect(copy_proof.ordinaryCopy(loop.fast));
    try t.expect(std.mem.indexOf(u8, loop.fast, "call $myl_rc_list_append(") != null);
}

// spec-case: RC-APPEND-RANGE-1
test "append range allocating copy exception rejects unrelated indirect duplicate and renamed calls" {
    const ordinary = " %v1 =w call $myl_rc_list_plain_ready(l %heap, l %v0)\n %v2 =w call $myl_rc_list_append(l %heap, l %v0, l %s0)\n";
    try t.expect(copy_proof.ordinaryCopy(ordinary));
    for ([_][]const u8{
        ordinary ++ " call %callback(l %heap)\n",
        ordinary ++ " call $myl_native_heap_alloc(l %heap, l 8)\n",
        ordinary ++ " call $guest(l %heap)\n",
        " call $myl_rc_list_append(l %heap, l %v0, l %s0) call $guest(l %heap)\n",
        ordinary ++ " call $myl_rc_list_append(l %heap, l %v0, l %s0)\n",
        " call $myl_rc_list_append_extra(l %heap, l %v0, l %s0)\n",
        " call $myl_rc_list_plain_ready(l %heap, l %v0)\n",
    }) |text| try t.expect(!copy_proof.ordinaryCopy(text));
}

fn same(a: native.Run, b: native.Run) !void {
    try t.expectEqual(a.status, b.status);
    try t.expectEqual(a.failed, b.failed);
    try t.expectEqual(a.value, b.value);
    try t.expectEqualStrings(a.stdout, b.stdout);
    try t.expectEqualStrings(a.stderr, b.stderr);
    try t.expectEqualStrings(a.trap.code, b.trap.code);
    try t.expectEqualStrings(a.trap.path, b.trap.path);
    try t.expectEqual(a.trap.line, b.trap.line);
    try t.expectEqual(a.trap.column, b.trap.column);
    try t.expectEqual(a.trap.frames.len, b.trap.frames.len);
    for (a.trap.frames, b.trap.frames) |left, right| {
        try t.expectEqualStrings(left.function, right.function);
        try t.expectEqualStrings(left.path, right.path);
        try t.expectEqual(left.line, right.line);
        try t.expectEqual(left.column, right.column);
    }
    try t.expect(std.meta.eql(a.trap.detail, b.trap.detail));
}

fn outcome(seed: i64, count: i64, options: native.Options) !native.Run {
    const body = growing[0..std.mem.indexOf(u8, growing, "def main()").?];
    const source = try std.fmt.allocPrint(t.allocator, "{s}def main() -> int:\n    return grown({d}, {d})\n", .{ body, count, seed });
    defer t.allocator.free(source);
    var compilation = try compiler.Compilation.init(t.allocator, fixture_path, source);
    defer compilation.deinit();
    const ordinary = try native.runWithOptions(&compilation, options);
    const fast = try native.runUnaccounted(&compilation, options);
    try same(ordinary, fast);
    const evidence = try std.json.Stringify.valueAlloc(t.allocator, .{ .seed = seed, .count = count, .max_memory = options.max_memory, .ordinary = ordinary, .fast = fast }, .{});
    defer t.allocator.free(evidence);
    test_log("APPEND-RANGE-OUTCOME {s}\n", .{evidence});
    return fast;
}

fn success(seed: i64, count: i64) !void {
    const result = try outcome(seed, count, .{});
    const expected: i64 = if (count <= 0) 0 else count + @as(i64, @intCast(@mod(@as(i128, seed), 1009))) +
        @as(i64, @intCast(@mod(@as(i128, seed) + (count - 1) * 13, 1009)));
    try t.expect(!result.failed);
    try t.expectEqual(expected, result.value);
    try t.expectEqual(@as(u8, @truncate(@as(u64, @bitCast(expected)))), result.status);
    try t.expectEqualStrings("", result.trap.code);
    try t.expectEqualStrings("", result.stdout);
}

// spec-case: RC-APPEND-RANGE-1
test "append range exact outcomes include growth short zero negative and overflow fallback" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    for ([_]i64{ -1, 0, 3, 16, 32, 65 }) |count| try success(17, count);
    try success(-31, 32);
    try success(std.math.minInt(i64), 32);
    try success(std.math.maxInt(i64), 0);
    const overflow = try outcome(std.math.maxInt(i64), 32, .{});
    try t.expectEqualStrings("R_OVERFLOW", overflow.trap.code);
    try t.expect(overflow.failed);
}

// spec-case: RC-APPEND-RANGE-1
test "append range keeps the first growing heap-budget refusal exact" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const refused_heap = try outcome(17, 400000, .{ .max_memory = 1 << 20 });
    try t.expect(refused_heap.failed);
    try t.expectEqualStrings("R_MEMORY_BUDGET", refused_heap.trap.code);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(allocator, fixture_path, growing);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(allocator, .{ .step_checks = false, .frame_checks = false });
    defer allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "# mylang-rc-append-range") != null);
}

// spec-case: RC-APPEND-RANGE-1
test "append range emission releases partial allocations on every allocator refusal" {
    try t.checkAllAllocationFailures(t.allocator, allocationScenario, .{});
}
