//! The version line and the commit file it reads (D-FR22-4): what a build with, without and with a dirty tree prints.
const std = @import("std");
const t = std.testing;
const version = @import("version_line.zig");

const identity = "9f2c4e1a7b30d5c8e6a1f04b3d7c92e85a6b1f0c4d3e7a9b2c8d5e6f1a0b3c4d";

fn info(commit: version.Commit) version.Info {
    return .{ .identity = identity, .zig_version = "0.17.0-dev.1683+5ceec001b", .mode = "Debug", .architecture = "x86_64", .os = "linux", .commit = commit };
}

// spec-case: VERSION-LINE-1
test "the version line names the commit, the identity, the mode, the toolchain and the target" {
    const line = try version.render(t.allocator, info(.{ .built = .{ .hash = "11419ef271ab3c5d7e9f0a1b2c3d4e5f60718293", .dirty = false } }));
    defer t.allocator.free(line);
    try t.expectEqualStrings("selka commit 11419ef271ab, identity 9f2c4e1a7b30, Debug, zig 0.17.0-dev.1683+5ceec001b, x86_64-linux", line);
}

// spec-case: VERSION-LINE-1
test "the version line marks a tree with uncommitted changes and says unknown without a commit file" {
    const dirty = try version.render(t.allocator, info(.{ .built = .{ .hash = "11419ef271ab3c5d7e9f0a1b2c3d4e5f60718293", .dirty = true } }));
    defer t.allocator.free(dirty);
    try t.expectEqualStrings("selka commit 11419ef271ab+dirty, identity 9f2c4e1a7b30, Debug, zig 0.17.0-dev.1683+5ceec001b, x86_64-linux", dirty);
    const missing = try version.render(t.allocator, info(.unknown));
    defer t.allocator.free(missing);
    try t.expectEqualStrings("selka commit unknown, identity 9f2c4e1a7b30, Debug, zig 0.17.0-dev.1683+5ceec001b, x86_64-linux", missing);
}

// spec-case: VERSION-LINE-1
test "the commit file round-trips and anything that does not name a commit reads as unknown" {
    const written = try version.commitFile(t.allocator, "11419ef271ab3c5d7e9f0a1b2c3d4e5f60718293", false);
    defer t.allocator.free(written);
    try t.expectEqualStrings("commit 11419ef271ab3c5d7e9f0a1b2c3d4e5f60718293\ntree clean\n", written);
    const clean = version.parseCommitFile(written).built;
    try t.expectEqualStrings("11419ef271ab3c5d7e9f0a1b2c3d4e5f60718293", clean.hash);
    try t.expect(!clean.dirty);
    const marked = try version.commitFile(t.allocator, "abcdef1", true);
    defer t.allocator.free(marked);
    try t.expect(version.parseCommitFile(marked).built.dirty);
    // No `tree` line says nothing about the tree, so it is not called clean.
    try t.expect(version.parseCommitFile("commit abcdef1\n").built.dirty);
    try t.expect(version.parseCommitFile("") == .unknown);
    try t.expect(version.parseCommitFile("commit unknown\n") == .unknown);
    try t.expect(version.parseCommitFile("commit abc\n") == .unknown);
    try t.expect(version.parseCommitFile("11419ef271ab\n") == .unknown);
    try t.expect(version.parseCommitFile("commit 11419ef271ab; rm -rf /\n") == .unknown);
}
