//! Bulk byte reductions preserve guards, tails and refusal semantics.
const std = @import("std");
const t = std.testing;
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const proof = @import("qbe_byte_reduction.zig");
const bytecode = @import("bytecode.zig");
extern fn myl_native_bytes_sum_xor([*]const u8, usize, u64) u64;
const source =
    \\def reduce(raw: bytes, mask: int, seed: int) -> int:
    \\    total = seed
    \\    for value in raw:
    \\        total += value ^ mask
    \\    return total
    \\def main() -> int:
    \\    return reduce(b"abcdefghijklmnopq", 7, 13)
;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
fn emitted(frames: bool) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "byte_reduction.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = false, .frame_checks = frames });
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, "reduce", function.name)) return function.il;
    return error.TestUnexpectedResult;
}
fn tails() !void {
    var storage: [1073]u8 = undefined;
    for (&storage, 0..) |*byte, index| byte.* = @truncate(index * 37 + 11);
    for (0..16) |offset| {
        for ([_]usize{ 0, 1, 15, 16, 17, 31, 32, 33, 1024, 1041 }) |length| {
            for (0..256) |mask| {
                var expected: u64 = 0;
                for (storage[offset .. offset + length]) |byte| expected += byte ^ mask;
                try t.expectEqual(expected, myl_native_bytes_sum_xor(storage[offset..].ptr, length, mask));
            }
        }
    }
}
fn certificateMutations() !void {
    var compilation = try compiler.Compilation.init(t.allocator, "byte_reduction.my", source);
    defer compilation.deinit();
    try compilation.emit();
    const code = compilation.code.?.functions[0].scope.instructions;
    const shape = proof.shape(code, 9, 33) orelse return error.TestUnexpectedResult;
    try t.expectEqual(@as(usize, 3), shape.total);
    try t.expectEqual(@as(usize, 1), shape.mask.local);
    const copy = try t.allocator.dupe(bytecode.Instruction, code);
    defer t.allocator.free(copy);
    for (9..34) |pc| {
        copy[pc].op = .push_unit;
        try t.expect(proof.shape(copy, 9, 33) == null);
        copy[pc] = code[pc];
    }
    copy[22].op = .{ .load_local = code[25].op.store_local };
    try t.expect(proof.shape(copy, 9, 33) == null);
    try t.expect(proof.shape(code, 9, 32) == null);
    try t.expect(proof.shape(code, 9, code.len) == null);
}

// spec: QBE-BYTE-REDUCTION-1
test "bulk byte reduction emits byte and signed headroom guards with checked fallback" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var fast = try emitted(false);
    defer fast.deinit();
    const il = try named(fast.value);
    const start = std.mem.indexOf(u8, il, "QBE-BYTE-REDUCTION-1") orelse return error.TestUnexpectedResult;
    const end = std.mem.indexOfPos(u8, il, start, "\n@oi") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, il[start..end], "myl_native_bytes_sum_xor") != null);
    try t.expect(std.mem.indexOf(u8, il[start..end], ", 255\n") != null);
    try t.expect(std.mem.indexOf(u8, il[start..end], "cslel") != null);
    try t.expect(std.mem.indexOf(u8, il[start..end], "loadub") != null);
    try t.expect(std.mem.indexOf(u8, il[end..], "myl_qbe_fail_overflow_op") != null);
    var counted = try emitted(true);
    defer counted.deinit();
    try t.expect(std.mem.indexOf(u8, try named(counted.value), "myl_native_bytes_sum_xor") == null);
    try certificateMutations();
}

// spec-case: QBE-BYTE-REDUCTION-1
test "bulk byte runtime matches scalar XOR for every mask alignment and vector tail" {
    try tails();
}
