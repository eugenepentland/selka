//! Arithmetic-only RC loops retain guarded fallback and step accounting.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\def calculate(count: int, seed: int) -> int:
    \\    total = seed
    \\    for at in range(count):
    \\        total = (total + at * 7) % 1000003
    \\    return total
    \\def read_items(items: list[int]) -> int:
    \\    total = 0
    \\    for at in range(len(items)):
    \\        total += items[at] * 7
    \\    return total
    \\def callback(out: Stream, count: int) -> int:
    \\    total = 0
    \\    for at in range(count):
    \\        out.print(at)
    \\        total += at * 7
    \\    return total
    \\def main(out: Stream) -> int:
    \\    out.print(calculate(32, 0))
    \\    return 0
;

fn emitted(steps: bool) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_scalar_loop.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = steps, .frame_checks = false });
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

// spec: RC-SCALAR-LOOP-VERSION-1
test "RC scalar loop versions retain original checked and step-accounted paths" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var fast = try emitted(false);
    defer fast.deinit();
    const calculation = try named(fast.value, "calculate");
    try t.expect(std.mem.indexOf(u8, calculation, "\n@fi") != null);
    try t.expect(std.mem.indexOf(u8, calculation, "\n@oi") != null);
    try t.expect(std.mem.indexOf(u8, calculation, "myl_qbe_fail") != null);
    try t.expect(std.mem.indexOf(u8, try named(fast.value, "read_items"), "\n@fi") == null);
    try t.expect(std.mem.indexOf(u8, try named(fast.value, "callback"), "\n@fi") == null);
    var counted = try emitted(true);
    defer counted.deinit();
    try t.expect(std.mem.indexOf(u8, try named(counted.value, "calculate"), "\n@fi") == null);
}
