//! Backend scalar selection preserves checked operations and cache isolation.
const std = @import("std");
const t = std.testing;
const policy = @import("runtime_contract").scalars.Policy;
const compiler = @import("compiler.zig");
const source =
    \\def divide(x: int) -> int:
    \\    return x // 7
    \\def checked(x: int, d: int) -> int:
    \\    return divtrunc(x, d)
    \\def main() -> int:
    \\    return divide(-100)
;

// spec: NATIVE-SCALAR-BACKEND-1
test "NATIVE-SCALAR-BACKEND-1 selects only current resolved LLVM producers" {
    try t.expectEqual(policy.llvm, policy.forBackend(true, false));
    try t.expectEqual(policy.qbe, policy.forBackend(false, false));
    try t.expectEqual(policy.qbe, policy.forBackend(true, true));
    try t.expectEqual(policy.qbe, policy.forBackend(false, true));
    try t.expectEqual(policy.llvm, policy.parse("llvm-v1").?);
    try t.expectEqual(policy.qbe, policy.parse("qbe").?);
    try t.expect(policy.parse("unchecked") == null);
    try t.expect(policy.qbe.flag() == null);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const flags = try @import("qbe_build.zig").frontendSwitches(arena.allocator(), .{ .drop_debug = false, .step_checks = true, .frame_checks = true, .scalar_policy = .llvm });
    try t.expectEqual(@as(usize, 1), flags.len);
    try t.expectEqualStrings("--native-scalars=llvm-v1", flags[0]);
}

const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

// spec-case: NATIVE-SCALAR-BACKEND-1
test "NATIVE-SCALAR-BACKEND-1 emitted division forms preserve variable traps" {
    var compilation = try compiler.Compilation.init(t.allocator, "scalar_policy.my", source);
    defer compilation.deinit();
    const original = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(original);
    const selected = try compilation.emitQbeWithOptions(t.allocator, .{ .scalar_policy = .llvm });
    defer t.allocator.free(selected);
    var qbe = try std.json.parseFromSlice(Manifest, t.allocator, original, .{ .ignore_unknown_fields = true });
    defer qbe.deinit();
    var llvm = try std.json.parseFromSlice(Manifest, t.allocator, selected, .{ .ignore_unknown_fields = true });
    defer llvm.deinit();
    try t.expect(std.mem.indexOf(u8, try named(qbe.value, "divide"), " =l umulh ") != null);
    try t.expect(std.mem.indexOf(u8, try named(llvm.value, "divide"), " =l div ") != null);
    try t.expect(std.mem.indexOf(u8, try named(llvm.value, "divide"), " =l umulh ") == null);
    try t.expectEqualStrings(try named(qbe.value, "checked"), try named(llvm.value, "checked"));
    try t.expect(std.mem.indexOf(u8, try named(llvm.value, "checked"), "myl_qbe_fail_division") != null);
}

// spec-case: NATIVE-SCALAR-BACKEND-1
test "NATIVE-SCALAR-BACKEND-1 fragment and module identities partition scalar forms" {
    var compilation = try compiler.Compilation.init(t.allocator, "scalar_policy.my", source);
    defer compilation.deinit();
    try compilation.emit();
    var keys = try @import("qbe_fragments.zig").Keys.init(t.allocator, compilation.code.?);
    defer keys.deinit();
    const a = try keys.local(0, .{ .step_checks = true, .frame_checks = true, .arenas = false, .entry = false });
    const b = try keys.local(0, .{ .step_checks = true, .frame_checks = true, .arenas = false, .entry = false, .emission = .{ .scalar_policy = .llvm } });
    try t.expect(!std.mem.eql(u8, &a, &b));
    const iface = @import("module_interface.zig");
    const original = try iface.configName(t.allocator, .{ .drop_debug = false, .step_checks = true, .frame_checks = true, .arenas = false });
    defer t.allocator.free(original);
    const selected = try iface.configName(t.allocator, .{ .drop_debug = false, .step_checks = true, .frame_checks = true, .arenas = false, .scalar_policy = .llvm });
    defer t.allocator.free(selected);
    try t.expect(!std.mem.eql(u8, original, selected));
    try t.expect(std.mem.endsWith(u8, selected, " scalar=llvm-v1"));
}
