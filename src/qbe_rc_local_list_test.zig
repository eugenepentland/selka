//! RC-LOCAL-LIST-1 retains cold constructors and rejects observable lifetimes.
const std = @import("std");
const debug_print = std.debug.print;
const t = std.testing;
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");

fn emitted(source: []const u8) ![]const u8 {
    var compilation = try compiler.Compilation.init(t.allocator, "local.my", source);
    defer compilation.deinit();
    return compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = true, .frame_checks = true });
}

const local =
    \\def local(value: int) -> int:
    \\    values = [value, value + 1, value + 2]
    \\    alias = values
    \\    return alias[0] + values[1] + alias[-1] + len(values)
    \\def main() -> int:
    \\    return local(12)
;

// spec: RC-LOCAL-LIST-1
test "local list stack admission keeps checked cold allocation and counts scratch" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const text = try emitted(local);
    defer t.allocator.free(text);
    try admitted(text);
    try contains(text, "@rclocalslow");
    try contains(text, "call $myl_native_list_new");
    try contains(text, "call $myl_qbe_fail_allocation");
    try contains(text, "alloc8 112");
    try contains(text, "@step_limit");
    try t.expect(std.mem.indexOf(u8, text, "# myl-obj") == null);
    try t.expect(std.mem.indexOf(u8, text, "# myl-elem") == null);
}

// spec-case: RC-LOCAL-LIST-1
test "local list stack scalar widths admit while zero sized units remain original" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    for ([_][]const u8{
        "def take(n: u8) -> u8:\n    values = [n, n]\n    return values[-1]\ndef main() -> int:\n    return int(take(u8(255)))\n",
        "def take(n: i16) -> i16:\n    values = [n, n]\n    return values[-1]\ndef main() -> int:\n    return int(take(i16(-32768)))\n",
        "def take(n: bool) -> bool:\n    values = [n, not n]\n    return values[0] and not values[1]\ndef main() -> int:\n    assert take(True)\n    return 0\n",
    }) |source| {
        const text = try emitted(source);
        defer t.allocator.free(text);
        try admitted(text);
    }
    try refused("def take(n: None) -> int:\n    values = [n, n]\n    return len(values)\ndef main() -> int:\n    return take(None)\n");
}

// spec-case: RC-LOCAL-LIST-1
test "local list stack promotion rejects counting collectors escapes mutation and backedges" {
    const saved = runtime.get();
    defer runtime.set(saved);
    for ([_]runtime.Selection{ .rc_counting, .rc_sites, .gc }) |mode| {
        runtime.set(mode);
        const text = try emitted(local);
        defer t.allocator.free(text);
        try t.expect(std.mem.indexOf(u8, text, "myl_qbe_local_list") == null);
    }
    runtime.set(.rc);
    try refused("def make(n: int) -> list[int]:\n    return [n, n + 1]\ndef main() -> int:\n    return len(make(1))\n");
    try refused("def take(values: list[int], n: int) -> int:\n    local = [n, n + 1]\n    return values[0] + local[0]\ndef main() -> int:\n    return take([1], 2)\n");
    try refused("def changed(n: int) -> int:\n    values = [n, n + 1]\n    values[0] = n + 2\n    return values[0]\ndef main() -> int:\n    return changed(1)\n");
    try refused("def loop(n: int) -> int:\n    value = 0\n    while value < n:\n        values = [value, n]\n        value += values[0] + 1\n    return value\ndef main() -> int:\n    return loop(2)\n");
    try refused("def overlap(n: int) -> int:\n    first = [n, n + 1, n + 2]\n    second = [n, n + 1, n + 2, n + 3]\n    return first[0] + second[0]\ndef main() -> int:\n    return overlap(2)\n");
}

fn refused(source: []const u8) !void {
    const text = try emitted(source);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "myl_qbe_local_list") == null);
}

fn contains(text: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, text, needle) == null) debug_print("missing IL {s}\n", .{needle});
    try t.expect(std.mem.indexOf(u8, text, needle) != null);
}

fn admitted(text: []const u8) !void {
    if (std.mem.indexOf(u8, text, "call $myl_qbe_local_list") == null) debug_print("missing admission: {s}\n", .{text});
    try contains(text, "call $myl_qbe_local_list");
}
