//! The pure half of the `build-env` host tool: command parsing, environment
//! projection and the environment manifest the build graph keys verdicts on.
const std = @import("std");
const identity = @import("environment_identity.zig");
const rules = @import("build_env_rules.zig");

/// A tool digest of the right shape.
const fake_digest = "abababababababababababababababababababababababababababababababab";

/// A synthetic live environment with one variable of every class.
fn liveEnvironment(a: std.mem.Allocator) !std.process.Environ.Map {
    var live = std.process.Environ.Map.init(a);
    try live.put("CODEX_THREAD_ID", "thread-1");
    try live.put("TERM", "xterm");
    try live.put("MYLANG_MEMORY_LIMIT", "1G");
    try live.put("PYTHONPATH", "python-lib");
    try live.put("TMPDIR", "scratch-tmp");
    try live.put("PATH", "tool-bin");
    return live;
}

/// The manifest of `map` and `tools`, rendered into `a`.
fn manifest(a: std.mem.Allocator, map: *const std.process.Environ.Map, tools: []identity.Tool) ![]const u8 {
    var buffer: [16]identity.Variable = undefined;
    var text: std.Io.Writer.Allocating = .init(a);
    try rules.writeManifest(&text.writer, rules.variablesOf(map, &buffer), tools);
    return text.written();
}

// spec: ENV-PROJECTION-1
test "build-env projection drops a dropped variable from the child and the manifest and keeps keyed and placement ones" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var live = try liveEnvironment(a);
    var child = std.process.Environ.Map.init(a);
    try rules.project(&live, &child);
    const text = try manifest(a, &live, &.{});
    try std.testing.expect(child.get("CODEX_THREAD_ID") == null);
    try std.testing.expect(child.get("TERM") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "CODEX_THREAD_ID") == null);
    try std.testing.expectEqualStrings("1G", child.get("MYLANG_MEMORY_LIMIT").?);
    try std.testing.expect(std.mem.indexOf(u8, text, "\nMYLANG_MEMORY_LIMIT=1G\n") != null);
    try std.testing.expectEqualStrings("python-lib", child.get("PYTHONPATH").?);
    try std.testing.expect(std.mem.indexOf(u8, text, "\nPYTHONPATH=python-lib\n") != null);
    try std.testing.expectEqualStrings("scratch-tmp", child.get("TMPDIR").?);
    try std.testing.expectEqualStrings("tool-bin", child.get("PATH").?);
    try std.testing.expect(std.mem.indexOf(u8, text, "TMPDIR") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\nPATH=") == null);
    try std.testing.expectEqual(@as(u32, 4), child.count());
}

// spec-case: ENV-PROJECTION-1
test "build-env manifest is unchanged by a dropped variable and changed by a keyed one" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var live = try liveEnvironment(a);
    const before = try manifest(a, &live, &.{});
    try live.put("CODEX_THREAD_ID", "thread-2");
    try live.put("OLDPWD", "/elsewhere");
    try std.testing.expectEqualStrings(before, try manifest(a, &live, &.{}));
    try live.put("MYLANG_MEMORY_LIMIT", "2G");
    try std.testing.expect(!std.mem.eql(u8, before[0..64], (try manifest(a, &live, &.{}))[0..64]));
}

// spec: ENV-PROJECTION-2
test "build-env manifest starts with the host-scope environment identity digest of the same inputs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var live = try liveEnvironment(a);
    try live.put("MYL_SPLIT", "a\\b\nc");
    var tools = [_]identity.Tool{ .{ .name = "zig", .digest = fake_digest }, .{ .name = "sh", .digest = rules.absent_tool } };
    const text = try manifest(a, &live, &tools);
    var buffer: [16]identity.Variable = undefined;
    var again = [_]identity.Tool{ .{ .name = "sh", .digest = rules.absent_tool }, .{ .name = "zig", .digest = fake_digest } };
    const expected = identity.digest(.host, rules.variablesOf(&live, &buffer), &again);
    try std.testing.expectEqualStrings(&expected, text[0..64]);
    try std.testing.expect(!std.mem.eql(u8, &expected, &identity.digest(.guest, rules.variablesOf(&live, &buffer), &again)));
    try std.testing.expectEqualStrings(
        "MYLANG_MEMORY_LIMIT=1G\nMYL_SPLIT=a\\\\b\\nc\nPYTHONPATH=python-lib\ntool:sh=absent\ntool:zig=" ++ fake_digest ++ "\n",
        text[65..],
    );
}

// spec-case: ENV-PROJECTION-2
test "build-env parses its digest and project commands and rejects malformed ones" {
    const digest = rules.parse(&.{ "digest", "out.txt", "zig=toolchain/zig", "sh" }).?.digest;
    try std.testing.expectEqualStrings("out.txt", digest.out);
    try std.testing.expectEqual(@as(usize, 2), digest.tools.len);
    try std.testing.expectEqualStrings("env", rules.parse(&.{ "project", "--", "env", "-0" }).?.project[0]);
    try std.testing.expect(rules.parse(&.{}) == null);
    try std.testing.expect(rules.parse(&.{"digest"}) == null);
    try std.testing.expect(rules.parse(&.{ "digest", "out", "=x" }) == null);
    try std.testing.expect(rules.parse(&.{ "project", "env" }) == null);
    try std.testing.expect(rules.parse(&.{ "project", "--" }) == null);
    try std.testing.expect(rules.parse(&.{"run"}) == null);
    try std.testing.expectEqualStrings("toolchain/zig", rules.toolRequest("zig=toolchain/zig").?.path.?);
    try std.testing.expect(rules.toolRequest("git").?.path == null);
    try std.testing.expect(rules.toolRequest("bin/git") == null);
    try std.testing.expect(rules.toolRequest("git=") == null);
}
