//! Exact default-ownership refusal witnesses.
const std = @import("std");
const options = @import("test_paths");

const Error = std.mem.Allocator.Error || std.process.RunError || std.Io.Dir.WriteFileError || std.Io.Dir.RealPathFileAllocError || error{TestUnexpectedResult};

/// Check the same source under ownership and require its stated refusal.
pub fn refuses(gpa: std.mem.Allocator, source: []const u8, code: []const u8) Error!void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "ownership.selka", .data = source });
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "ownership.selka" });
    const result = try std.process.run(a, std.testing.io, .{
        .argv = &.{ options.corePath(), "check", path, "--no-cache", "--diagnostics=json" },
    });
    try std.testing.expect(result.term == .exited and result.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, code) != null);
}
