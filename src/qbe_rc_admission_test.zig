//! Unique incoming arguments survive refusal before the callee journal exists.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\resource File: filesystem
    \\record Owned:
    \\    file: File
    \\    values: list[int]
    \\record Wide:
    \\    file: File
    \\    padding: [8192]int
    \\    values: list[int]
    \\def recurse(value: Owned) -> int:
    \\    return recurse(value)
    \\def wide(value: Wide) -> int:
    \\    return wide(value)
    \\def invoke(callback: def(Owned) -> int, value: Owned) -> int:
    \\    return callback(value)
    \\def main() -> int:
    \\    return 0
;

fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_admission.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
fn location(text: []const u8, needle: []const u8) !usize {
    return std.mem.indexOf(u8, text, needle) orelse error.TestUnexpectedResult;
}

// spec: RC-ADMISSION-1
test "RC-ADMISSION-1 cold guards drop unique and counted incoming edges before trapping" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const code = try named(manifest.value, "recurse");
    const fail = try location(code, "call $myl_qbe_fail_frame");
    try t.expect(try location(code, "call $myl_native_owned_drop") < fail);
    try t.expect(try location(code, "call $myl_rc_native_drop") < fail);
    try t.expect(try location(code, "call $myl_qbe_rc_frame_enter") > fail);
    const wide = try named(manifest.value, "wide");
    const allocation = try location(wide, "call $myl_qbe_frame_try_allocate");
    const refusal = wide[allocation..];
    try t.expect(try location(refusal, "call $myl_native_owned_drop") < try location(refusal, "call $myl_qbe_fail_frame_allocation"));
    try t.expect(try location(refusal, "call $myl_rc_native_drop") < try location(refusal, "call $myl_qbe_fail_frame_allocation"));
    try t.expect(std.mem.indexOf(u8, refusal, "loadl") != null);
}

// spec-case: RC-ADMISSION-1
test "RC-ADMISSION-1 indirect calls disarm consumed operand ownership before invoking" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const code = try named(manifest.value, "invoke");
    const call = try location(code, " call %v");
    const prefix = code[0..call];
    const guard = std.mem.lastIndexOf(u8, prefix, " storew 0,") orelse return error.TestUnexpectedResult;
    try t.expect(guard > try location(code, "call $myl_qbe_rc_frame_enter"));
    try t.expect(call - guard < 100);
}

extern fn myl_qbe_frame_try_allocate(?*anyopaque, u64) ?*anyopaque;
// spec-case: RC-ADMISSION-1
test "RC-ADMISSION-1 oversized heap-frame request refuses without trapping or touching context" {
    try t.expectEqual(@as(?*anyopaque, null), myl_qbe_frame_try_allocate(null, std.math.maxInt(u64)));
}
