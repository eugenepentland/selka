//! RC-LOCAL-LIST-1 retains cold constructors and rejects observable lifetimes.
const std = @import("std");
const debug_print = std.debug.print;
const t = std.testing;
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const local_list = @import("qbe_rc_local_list.zig");
const llvm = @import("qbe_build_llvm.zig");
const bundled = @import("qbe_build_assets");

fn emitted(source: []const u8) ![]const u8 {
    var compilation = try compiler.Compilation.init(t.allocator, "local.my", source);
    defer compilation.deinit();
    return compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = true, .frame_checks = true });
}

const local =
    \\def local(value: int, index: int) -> int:
    \\    values = [value, value + 1, value + 2]
    \\    alias = values
    \\    return alias[index] + values[1] + alias[-1] + len(values)
    \\def main() -> int:
    \\    return local(12, 0)
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
    try t.expect(std.mem.indexOf(u8, text, "# myl-rc ") == null);
    try contains(text, "# myl-no-alias");
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

const stack_prefix =
    \\export function l $private_prefix(l %ctx) {
    \\@entry
    \\ %frame =l alloc8 88
    \\ storel 2, %frame
    \\ %payload =l add %frame, 16
    \\ %prefix =l sub %payload, 16
    \\ # myl-rc %prefix
    \\ %mark =l loadl %prefix
    \\ %state =l add %ctx, 176
    \\ # myl-rc-state %state
    \\ %held =l loadl %state
    \\ %sum =l add %mark, %held
    \\ ret %sum
    \\}
    \\
;

// spec-case: RC-LOCAL-LIST-1
test "local list stack prefix hints are removed while instructions and heap state hints remain" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const stripped = try local_list.stackHints(a, stack_prefix);
    const without = try std.mem.replaceOwned(u8, a, stack_prefix, " # myl-rc %prefix\n", "");
    const expected = try std.mem.replaceOwned(u8, a, without, "@entry\n", "@entry\n # myl-no-alias\n");
    try t.expectEqualStrings(expected, stripped);
    const signatures: llvm.Signatures = .empty;
    const table: llvm.RuntimeTable = .{};
    var diagnostic: llvm.Diagnostic = .{ .unit = "private-prefix" };
    const ir = try llvm.translate(a, stripped, .{ .signatures = &signatures, .runtime = &table }, &diagnostic);
    try t.expect(std.mem.indexOf(u8, ir, "!alias.scope !9, !noalias !10") == null);
    try t.expect(std.mem.indexOf(u8, ir, "rc prefix") == null);
    try contains(stripped, "# myl-rc-state %state");
    try t.expect(std.mem.indexOf(u8, ir, "!alias.scope") == null);
    try t.expect(std.mem.indexOf(u8, ir, ", !noalias") == null);
    const ordinary = try llvm.translate(a, stack_prefix, .{ .signatures = &signatures, .runtime = &table }, &diagnostic);
    try contains(ordinary, "!alias.scope !9, !noalias !10");
    try t.expectError(error.WriteFailed, local_list.withoutPrefixHints(t.failing_allocator, stack_prefix));
    try t.expectError(error.InternalError, local_list.stackHints(a, "no entry\n"));
}

fn runtimeTable(a: std.mem.Allocator) !llvm.RuntimeTable {
    var sources: std.ArrayList(llvm.RuntimeSource) = .empty;
    for (bundled.files) |file| {
        if (std.mem.indexOfScalar(u8, file.path, '/') != null) continue;
        try sources.append(a, .{ .name = file.path, .bytes = file.bytes });
    }
    return llvm.RuntimeTable.read(a, sources.items);
}

fn glueSignatures(a: std.mem.Allocator, text: []const u8) !llvm.Signatures {
    var signatures: llvm.Signatures = .empty;
    const start = (std.mem.indexOf(u8, text, "call $myl_t_") orelse return error.TestUnexpectedResult) + "call $".len;
    const end = std.mem.indexOfPos(u8, text, start, "_rcg_") orelse return error.TestUnexpectedResult;
    for ([_][]const u8{ "drop", "unloan", "retain", "take" }) |operation| {
        const transfer = std.mem.eql(u8, operation, "retain") or std.mem.eql(u8, operation, "take");
        const name = try std.fmt.allocPrint(a, "{s}_rcg_{s}", .{ text[start..end], operation });
        try signatures.put(a, name, .{ .parameters = if (transfer) &.{ "l", "l", "l", "w" } else &.{ "l", "l" }, .result = if (transfer) "w" else null });
    }
    return signatures;
}

fn emittedLocal(a: std.mem.Allocator, source: []const u8) ![]const u8 {
    const text = try emitted(source);
    defer t.allocator.free(text);
    const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
    const manifest = try std.json.parseFromSliceLeaky(Manifest, a, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, "local")) return function.il;
    return error.TestUnexpectedResult;
}

// spec-case: RC-LOCAL-LIST-1
test "local list stack actual admitted LLVM unit carries no foreign prefix alias scope" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const table = try runtimeTable(a);
    for ([_][]const u8{
        local,
        "def local(n: u8, index: int) -> u8:\n    values = [n, n]\n    return values[index]\ndef main() -> int:\n    assert local(u8(255), 1) == u8(255)\n    return 0\n",
        "def local(n: bool, index: int) -> bool:\n    values = [n, not n]\n    return values[index]\ndef main() -> int:\n    assert local(True, 0)\n    return 0\n",
    }) |source| {
        const text = try emittedLocal(a, source);
        try admitted(text);
        try contains(text, "# myl-no-alias");
        try t.expect(std.mem.indexOf(u8, text, "# myl-rc ") == null);
        const signatures = try glueSignatures(a, text);
        var diagnostic: llvm.Diagnostic = .{ .unit = "local" };
        const ir = try llvm.translate(a, text, .{ .signatures = &signatures, .runtime = &table }, &diagnostic);
        try t.expect(std.mem.indexOf(u8, ir, "rc prefix") == null);
        try t.expect(std.mem.indexOf(u8, ir, "!alias.scope") == null);
        try t.expect(std.mem.indexOf(u8, ir, ", !noalias") == null);
    }
}
