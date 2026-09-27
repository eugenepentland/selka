//! Room append admission retains the dynamic refusal and original slow helper.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\def scalar(items: mut list[int], value: int) -> unit:
    \\    items.append(value)
    \\def narrow(items: mut list[u8], value: u8) -> unit:
    \\    items.append(value)
    \\def floating(items: mut list[float], value: float) -> unit:
    \\    items.append(value)
    \\def managed(items: mut list[list[int]], value: list[int]) -> unit:
    \\    items.append(value)
    \\def aggregate(items: mut list[tuple[int, int]], value: tuple[int, int]) -> unit:
    \\    items.append(value)
    \\def main() -> int:
    \\    return 0
;
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
// spec: RC-PLAIN-APPEND-1
test "RC-PLAIN-APPEND-1 room stores retain queue capacity generation and fallback guards" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_append.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer manifest.deinit();
    for ([_][]const u8{ "scalar", "narrow", "floating" }) |name| {
        const il = try named(manifest.value, name);
        try t.expect(std.mem.indexOf(u8, il, "myl_rc_list_plain_ready") != null);
        try t.expect(std.mem.indexOf(u8, il, " =w cultl ") != null);
        try t.expect(std.mem.indexOf(u8, il, " =w cnel ") != null);
        try t.expect(std.mem.indexOf(u8, il, ", -1\n") != null);
        try t.expect(std.mem.indexOf(u8, il, "myl_rc_list_append") != null);
        try t.expect(std.mem.indexOf(u8, il, "myl_qbe_fail_allocation") != null);
    }
    try refused(manifest.value);
}
fn refused(manifest: Manifest) !void {
    for ([_][]const u8{ "managed", "aggregate" }) |name| {
        const il = try named(manifest, name);
        try t.expect(std.mem.indexOf(u8, il, "myl_rc_list_plain_ready") == null);
        // Counted and plain aggregate elements append through their
        // generated glue (RC-GLUE-1), which keeps the helper for growth.
        try t.expect(std.mem.indexOf(u8, il, "# RC-GLUE-1 list_append") != null);
    }
}

const loop_source =
    \\def grown(n: int) -> int:
    \\    items: list[int] = []
    \\    for i in range(n):
    \\        items.append(i)
    \\    return len(items)
    \\def comprehension(n: int) -> int:
    \\    flags = [True for _ in range(n)]
    \\    return len(flags)
    \\def repeated(n: int) -> int:
    \\    total = 0
    \\    for outer in range(3):
    \\        items: list[int] = []
    \\        for i in range(n):
    \\            items.append(i)
    \\        total += len(items)
    \\    return total
    \\def heap_frame(values: [4096]int, n: int) -> int:
    \\    padding = replace(values, 0, 7)
    \\    items: list[int] = []
    \\    for i in range(n):
    \\        items.append(i)
    \\    return len(items) + padding[0]
    \\def value(x: int) -> int:
    \\    return x
    \\def calls(n: int) -> int:
    \\    items: list[int] = []
    \\    for i in range(n):
    \\        items.append(value(i))
    \\    return len(items)
    \\def parameter(items: mut list[int], n: int) -> int:
    \\    for i in range(n):
    \\        items.append(i)
    \\    return len(items)
    \\def snapshots(n: int) -> int:
    \\    items: list[int] = []
    \\    for i in range(n):
    \\        earlier = items
    \\        items.append(i)
    \\        assert len(earlier) == i
    \\    return len(items)
    \\def managed_loop(n: int) -> int:
    \\    items: list[list[int]] = []
    \\    for i in range(n):
    \\        items.append([i])
    \\    return len(items)
    \\def main() -> int:
    \\    return grown(0) + comprehension(0) + repeated(0)
;

// spec-case: RC-PLAIN-APPEND-1
test "RC append loop lazily queries after entry reset and invalidates before slow allocation" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_append_loops.my", loop_source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer manifest.deinit();
    for ([_][]const u8{ "grown", "comprehension", "repeated" }) |name| try admissionOrder(try named(manifest.value, name));
    try refusedLoops(manifest.value);
    const heap = try named(manifest.value, "heap_frame");
    try t.expect(std.mem.indexOf(u8, heap, "%rcappend0 =l add %frame_memory,") != null);
    try t.expect(std.mem.indexOf(u8, heap, "myl_qbe_frame_allocate") != null);
    try t.expect(std.mem.indexOf(u8, heap, "myl_qbe_frame_release") != null);
    try t.expect(std.mem.indexOf(u8, heap, "%rcappend0 =l alloc8") == null);
}

fn refusedLoops(manifest: Manifest) !void {
    for ([_][]const u8{ "calls", "parameter", "snapshots", "managed_loop" }) |name| {
        const il = try named(manifest, name);
        try t.expect(std.mem.indexOf(u8, il, "%rcappend0") == null);
        try t.expect(std.mem.indexOf(u8, il, "myl_rc_list_append") != null);
    }
}

const reset_flag = " storew 0, %rcappend0\n";
fn admissionOrder(il: []const u8) !void {
    try t.expect(std.mem.indexOf(u8, il, "%rcappend0 =l alloc8 8") != null);
    const reset = std.mem.indexOf(u8, il, reset_flag) orelse return error.TestUnexpectedResult;
    const unique = std.mem.indexOf(u8, il, "call $myl_qbe_rc_unique_local") orelse return error.TestUnexpectedResult;
    const query = std.mem.indexOf(u8, il, "call $myl_rc_list_plain_ready") orelse return error.TestUnexpectedResult;
    const slow = std.mem.indexOf(u8, il, "call $myl_rc_list_append") orelse return error.TestUnexpectedResult;
    try t.expect(unique < reset and reset < query and query < slow);
    const body = il[reset + reset_flag.len ..];
    try t.expect(std.mem.startsWith(u8, body, "@i"));
    const end = std.mem.indexOfScalar(u8, body, '\n') orelse return error.TestUnexpectedResult;
    const target = body[0..end];
    const backedge = try std.fmt.allocPrint(t.allocator, "jmp {s}\n", .{target});
    defer t.allocator.free(backedge);
    try t.expect(std.mem.indexOf(u8, il[slow..], backedge) != null);
    const entry_label = try std.fmt.allocPrint(t.allocator, "@ce{s}\n", .{target[2..]});
    defer t.allocator.free(entry_label);
    try t.expect(std.mem.lastIndexOf(u8, il[0..reset], entry_label) != null);
    try t.expect(std.mem.indexOf(u8, il[reset..query], " =w loaduw %rcappend0") != null);
    try t.expect(std.mem.indexOf(u8, il[query..slow], reset_flag) != null);
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, il, reset_flag));
}

// This uses the lowering's real entry query, not only our CFG admission model.
const EntryEmitter = struct {
    cow: ?struct { plan: struct { loops: @import("cow_plan.zig").Loops } },
    pc: usize,
};
// spec-case: RC-PLAIN-APPEND-1
test "RC append loop external backwards entry selects reset and internal backedge bypasses it" {
    const cow = @import("cow_plan.zig");
    var entries: [21][]const cow.Hoisted = @splat(&.{});
    entries[10] = &.{.{ .local = 3, .elements = false }};
    var back: [21]u32 = @splat(cow.none);
    back[10] = 20;
    var emitter: EntryEmitter = .{ .cow = .{ .plan = .{ .loops = .{ .entries = &entries, .back = &back } } }, .pc = 25 };
    const lower = @import("qbe_cow.zig").Lower(EntryEmitter);
    try t.expect(lower.enters(&emitter, 10));
    emitter.pc = 20;
    try t.expect(!lower.enters(&emitter, 10));
    emitter.pc = 5;
    try t.expect(lower.enters(&emitter, 10));
    try t.expect(!lower.enters(&emitter, 11));
}
