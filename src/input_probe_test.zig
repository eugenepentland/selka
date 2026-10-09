//! The wording and kinds `input_probe` gives an unusable command-line input.
const std = @import("std");
const t = std.testing;
const input_probe = @import("input_probe.zig");

// spec-case: CLI-INPUT-REFUSED-1
test "the reason for each unusable input names it in words" {
    try t.expectEqualStrings("no such file or directory", input_probe.reason(error.FileNotFound));
    try t.expectEqualStrings("permission denied", input_probe.reason(error.AccessDenied));
    try t.expectEqualStrings("is a directory, not a file", input_probe.reason(error.IsDir));
    try t.expectEqualStrings("Unexpected", input_probe.reason(error.Unexpected));
}

// spec-case: CLI-INPUT-REFUSED-1
test "probe tells a file from a directory and check refuses what it cannot open" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(t.io, .{ .sub_path = "a.selka", .data = "x" });
    try temp.dir.createDir(t.io, "d", .default_dir);
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const file = try std.fs.path.join(t.allocator, &.{ root, "a.selka" });
    defer t.allocator.free(file);
    const directory = try std.fs.path.join(t.allocator, &.{ root, "d" });
    defer t.allocator.free(directory);
    const absent = try std.fs.path.join(t.allocator, &.{ root, "absent.selka" });
    defer t.allocator.free(absent);
    try t.expectEqual(input_probe.Kind.file, try input_probe.probe(t.io, file));
    try t.expectEqual(input_probe.Kind.directory, try input_probe.probe(t.io, directory));
    try t.expectError(error.FileNotFound, input_probe.probe(t.io, absent));
    try t.expect(try input_probe.check(t.allocator, t.io, "check", file, false) == null);
    try t.expect(try input_probe.check(t.allocator, t.io, "test", directory, true) == null);
    const sentence = try input_probe.check(t.allocator, t.io, "check", directory, false);
    defer t.allocator.free(sentence.?);
    try t.expect(std.mem.endsWith(u8, sentence.?, "is a directory, not a file\n"));
}
