//! The unit test binary carries no absolute path of its build tree (TEST-PATHS-1).
const std = @import("std");
const paths = @import("test_paths");

// spec-case: TEST-PATHS-1
test "the unit test binary names neither its build tree nor its compiler outside debug sections" {
    const a = std.testing.allocator;
    const root = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(root);
    const self = try std.process.executablePathAlloc(std.testing.io, a);
    defer a.free(self);
    try std.testing.expectEqual(@as(usize, 0), try paths.occurrencesOutsideDebug(std.testing.io, std.Io.Dir.cwd(), self, root));
    try std.testing.expectEqual(@as(usize, 0), try paths.occurrencesOutsideDebug(std.testing.io, std.Io.Dir.cwd(), self, std.fs.path.dirname(paths.corePath()).?));
    try std.testing.expect(try paths.occurrencesOutsideDebug(std.testing.io, std.Io.Dir.cwd(), self, paths.compiler_variable) > 0);
}
