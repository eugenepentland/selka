//! Machine zero-flag branch proofs, including full-width truth and spills.
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
    try context.write(source, try context.read("tests/fixtures/qbe-zero-branch/probe.ssa"));
    try context.write(harness, try context.read("tests/fixtures/qbe-zero-branch/probe.c"));
    const selected = try std.process.run(a, t.io, .{ .argv = &.{ qbe, "-o", assembly, source } });
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, selected.term);
    const linked = try std.process.run(a, t.io, .{ .argv = &.{ zig, "cc", "-std=c11", "-O2", "-UNDEBUG", harness, assembly, "-o", binary } });
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, linked.term);
    const ran = try std.process.run(a, t.io, .{ .argv = &.{binary} });
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, ran.term);
    try t.expectEqualStrings("zero branch probes: 130 cases passed\n", ran.stdout);
    return t.allocator.dupe(u8, try context.read(assembly));
}

// spec: QBE-ZERO-BRANCH-1
test "QBE-ZERO-BRANCH-1 flags preserve full-width zero, negative admissions and spilled values" {
    const assembly = try compileAndRun();
    defer t.allocator.free(assembly);
    const added = try body(assembly, "branch_add:");
    const subtracted = try body(assembly, "branch_sub:");
    try t.expect(std.mem.indexOf(u8, added, "addq") != null);
    try t.expect(std.mem.indexOf(u8, subtracted, "subq") != null);
    try t.expect(std.mem.indexOf(u8, added, "cmp") == null);
    try t.expect(std.mem.indexOf(u8, subtracted, "cmp") == null);
    try t.expect(std.mem.indexOf(u8, added, "test") == null);
    try t.expect(std.mem.indexOf(u8, subtracted, "test") == null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "branch_reverse:"), "cmp") == null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "branch_ne:"), "cmp") == null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "branch_word:"), "cmp") == null);
    const spilled = try body(assembly, "branch_spill:");
    try t.expect(std.mem.indexOf(u8, spilled, "cmp") == null);
    try t.expect(std.mem.indexOf(u8, spilled, "(%rsp)") != null or std.mem.indexOf(u8, spilled, "(%rbp)") != null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "branch_clobber:"), "cmp") != null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "branch_other:"), "cmp") != null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "branch_wrongresult:"), "cmp") != null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "branch_width:"), "cmp") != null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "branch_nonzero:"), "cmp") != null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "branch_call:"), "cmp") != null);
    try t.expect(std.mem.indexOf(u8, try body(assembly, "branch_multi:"), "cmp") != null);
}
