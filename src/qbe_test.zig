//! Independent QBE unit boundaries and stable artifact inputs.
const std = @import("std");
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const Unit = struct { name: []const u8, symbol: []const u8, il: []const u8 };
const Manifest = struct { version: []const u8, abi: []const u8, functions: []Unit, entry: []const u8 };
fn emitted(a: std.mem.Allocator, input: []const u8) !std.json.Parsed(Manifest) {
    var c = try language.Compilation.init(a, "qbe.my", input);
    defer c.deinit();
    const manifest = try c.emitQbe(a);
    defer a.free(manifest);
    return std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ?Unit {
    for (manifest.functions) |unit| if (std.mem.eql(u8, unit.name, name)) return unit;
    return null;
}
// spec: QBE-1
test "scalar units remain stable across body edits and declaration reorder" {
    var before = try emitted(std.testing.allocator,
        \\def square(x: i64) -> i64:
        \\    return x * x
        \\
        \\
        \\def main() -> i64:
        \\    return square(10)
    );
    defer before.deinit();
    var after = try emitted(std.testing.allocator,
        \\def main() -> i64:
        \\    return square(10)
        \\
        \\
        \\def square(x: i64) -> i64:
        \\    return x * x + 1
    );
    defer after.deinit();
    const caller_before = named(before.value, "main").?;
    const caller_after = named(after.value, "main").?;
    const callee_before = named(before.value, "square").?;
    const callee_after = named(after.value, "square").?;
    try std.testing.expectEqualStrings(before.value.entry, after.value.entry);
    try std.testing.expectEqualStrings(caller_before.il, caller_after.il);
    try std.testing.expectEqualStrings(callee_before.symbol, callee_after.symbol);
    try std.testing.expect(!std.mem.eql(u8, callee_before.il, callee_after.il));
}

test "QBE lowers stack joins loops casts and calls independently" {
    const a = std.testing.allocator;
    var c = try language.Compilation.init(a, "qbe.my",
        \\def twice(x: i64) -> i64:
        \\    return x * 2
        \\
        \\
        \\def main() -> i64:
        \\    x: i64 = 0
        \\    while x < 4:
        \\        x = x + 1
        \\    if x == 4:
        \\        return twice(x)
        \\    return 0
    );
    defer c.deinit();
    const manifest = try c.emitQbe(a);
    defer a.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "jnz") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "myl_qbe_int_binary") != null);
    try std.testing.expectEqual(@as(i64, 8), (try native.run(&c)).value);
}

fn allocationScenario(a: std.mem.Allocator) !void {
    var c = try language.Compilation.init(a, "qbe.my",
        \\def main() -> i64:
        \\    return 7
    );
    defer c.deinit();
    const manifest = try c.emitQbe(a);
    defer a.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "qbe-units-v1") != null);
}
test "QBE emission releases partial allocations" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

test "QBE bounds ABI stack usage and heap backs large local frames" {
    const typed = @import("typed.zig");
    const bc = @import("bytecode.zig");
    const a = std.testing.allocator;
    const src = try @import("source.zig").Source.init(a, "qbe.my", "");
    defer a.free(src.bytes);
    defer a.free(src.path);
    defer a.free(src.line_starts);
    var sink = @import("diagnostic.zig").Sink{ .allocator = a };
    defer sink.deinit();
    const local = typed.Local{ .name = "x", .declaration = .{ .start = 0, .end = 0 }, .ty = .i64, .mutable = false };
    const locals: [5000]typed.Local = @splat(local);
    const instructions = [_]bc.Instruction{
        .{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 0 } },
        .{ .span = .{ .start = 0, .end = 0 }, .op = .ret },
    };
    const functions = [_]bc.Function{.{ .id = @fromBackingInt(0), .name = "main", .signature = .{ .parameter_count = locals.len }, .scope = .{ .locals = &locals, .instructions = &instructions } }};
    const manifest = try @import("qbe.zig").generate(a, .{ .functions = &functions }, src, &sink);
    defer a.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "l %packed") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "myl_qbe_frame_allocate") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "myl_qbe_frame_release") != null);
}

test "QBE emits direct scalar comparisons wrapping and checked addition" {
    var parsed = try emitted(std.testing.allocator,
        \\def main() -> i64:
        \\    x: i64 = 3
        \\    if x < 8:
        \\        return x + 2
        \\    return 0
    );
    defer parsed.deinit();
    const il = named(parsed.value, "main").?.il;
    try std.testing.expect(std.mem.indexOf(u8, il, "csltl") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, " =l add ") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, "myl_qbe_int_binary") == null);
    try std.testing.expect(std.mem.indexOf(u8, il, "myl_qbe_fail_overflow") != null);
}
test "QBE specializes scalar generic calls" {
    var parsed = try emitted(std.testing.allocator,
        \\def identity[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return identity[i64](2)
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), parsed.value.functions.len);
}
