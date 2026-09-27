//! RC loop guards require a separate physical owner lifetime proof.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\def flat(count: int) -> list[int]:
    \\    items = [0 for at in range(count)]
    \\    for at in range(count):
    \\        items[at] = at + 1
    \\    return items
    \\def publish(items: list[int], snapshots: mut list[list[int]]) -> int:
    \\    snapshots.append(items)
    \\    return 0
    \\def callback(count: int) -> list[list[int]]:
    \\    items = [0, 0]
    \\    snapshots: list[list[int]] = []
    \\    for at in range(count):
    \\        items[publish(items, mut snapshots)] = at
    \\    return snapshots
    \\def readonly(items: list[int]) -> int:
    \\    result = 0
    \\    for at in range(len(items)):
    \\        result += items[at]
    \\    return result
    \\def held(count: int) -> list[int]:
    \\    items = [0 for at in range(count)]
    \\    total = 0
    \\    for value in items:
    \\        total += value
    \\    for at in range(count):
    \\        items[at] = at + total
    \\    return items
    \\def main() -> int:
    \\    return len(flat(2))
;
fn emitted(steps: bool) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_loop_version.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = steps, .frame_checks = false });
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
// spec: RC-LOOP-VERSION-1
test "RC-LOOP-VERSION-1 callback publication and step accounting keep original loops" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var fast = try emitted(false);
    defer fast.deinit();
    const flat = try named(fast.value, "flat");
    const copy = std.mem.indexOf(u8, flat, "\n@fi") orelse return error.TestUnexpectedResult;
    const original = std.mem.indexOf(u8, flat, "\n@oi") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, flat[copy..original], "@rcslotdrop") == null);
    try t.expect(std.mem.indexOf(u8, flat[copy..original], "myl_qbe_fail_normalized_index_bounds") == null);
    try t.expect(std.mem.indexOf(u8, try named(fast.value, "callback"), "\n@fi") == null);
    // No physical entry interval was certified for this read-only loop.
    try t.expect(std.mem.indexOf(u8, try named(fast.value, "readonly"), "\n@fi") == null);
    const held = try named(fast.value, "held");
    // The earlier real H iterator remains; its later inert capture is proved
    // non-H independently, so that separate write loop can use its fast arm.
    try t.expect(std.mem.indexOf(u8, held, "# RC-NONHELD-CAPTURE-1") != null);
    try t.expect(std.mem.indexOf(u8, held, "\n@fi") != null);
    try t.expect(std.mem.indexOf(u8, held, "# RC-GLUE-1 hold") != null);
    try t.expect(std.mem.indexOf(u8, held, "@rcslotdrop") != null);
    var counted = try emitted(true);
    defer counted.deinit();
    try t.expect(std.mem.indexOf(u8, try named(counted.value, "flat"), "\n@fi") == null);
}
