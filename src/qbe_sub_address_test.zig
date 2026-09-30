//! Executable constant-subtraction address selection and fallback proofs.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const t = std.testing;

fn body(assembly: []const u8, name: []const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, assembly, name) orelse return error.TestUnexpectedResult;
    const end = std.mem.indexOf(u8, assembly[start..], "/* end function") orelse return error.TestUnexpectedResult;
    return assembly[start..][0..end];
}

fn compileAndRun() ![]const u8 {
    var environment: std.process.Environ.Map = .init(t.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(t.allocator, t.io, &environment);
    defer context.deinit();
    const a = context.allocator;
    const qbe = t.environ.getPosix("MYLANG_QBE") orelse return error.ToolNotFound;
    const zig = t.environ.getPosix("MYLANG_ZIG") orelse return error.ToolNotFound;
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "probe.ssa" });
    const assembly = try std.fs.path.join(a, &.{ root, "probe.s" });
    const harness = try std.fs.path.join(a, &.{ root, "probe.c" });
    const binary = try std.fs.path.join(a, &.{ root, "probe" });
    try context.write(source, try context.read("tests/fixtures/qbe-sub-address/probe.ssa"));
    try context.write(harness, try context.read("tests/fixtures/qbe-sub-address/probe.c"));
    const selected = try std.process.run(a, t.io, .{ .argv = &.{ qbe, "-o", assembly, source } });
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, selected.term);
    const linked = try std.process.run(a, t.io, .{ .argv = &.{ zig, "cc", "-std=c11", "-O2", "-UNDEBUG", "-fsanitize=undefined", harness, assembly, "-o", binary } });
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, linked.term);
    const ran = try std.process.run(a, t.io, .{ .argv = &.{binary} });
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, ran.term);
    try t.expectEqualStrings("sub address probes: 323 cases passed\n", ran.stdout);
    return t.allocator.dupe(u8, try context.read(assembly));
}

// spec: QBE-SUB-ADDRESS-1
test "QBE-SUB-ADDRESS-1 long constant prefix addresses fold without changing other arithmetic or flags" {
    const assembly = try compileAndRun();
    defer t.allocator.free(assembly);
    const loaded = try body(assembly, "addr_load:");
    const stored = try body(assembly, "addr_store:");
    try t.expect(std.mem.indexOf(u8, loaded, "-32(") != null);
    try t.expect(std.mem.indexOf(u8, stored, "-32(") != null);
    try t.expect(std.mem.indexOf(u8, loaded, "subq") == null);
    try t.expect(std.mem.indexOf(u8, stored, "subq") == null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "addr_hold:"), "-24(") != null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "addr_mark:"), "-16(") != null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "addr_scaled:"), ", 8)") != null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "addr_min:"), "-2147483648(") != null);
    const outside = try body(assembly, "addr_outside:");
    try t.expect(std.mem.indexOf(u8, outside, "addq") != null);
    try t.expect(std.mem.indexOf(u8, outside, "-2147483649(") == null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "addr_multi:"), "subq") != null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "addr_word:"), "subl") != null);
    const flags = try body(assembly, "addr_flags:");
    try t.expect(std.mem.indexOf(u8, flags, "subq") != null);
    try t.expect(std.mem.indexOf(u8, flags, "cmp") == null);
}
