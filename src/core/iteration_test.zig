//! Executable D1 live-place iteration contracts against the accepted checker forms.
const std = @import("std");
const options = @import("core_test_options");
const support = @import("test_support.zig");
const report = std.debug.print;

// spec: NEW-CORE-ITERATION-1
test "live iteration refreshes shared elements, appends, mut callees and record fields while root rebinding snapshots" {
    for ([_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } }) |flags| {
        try support.requireReleaseArgs(flags);
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var environment = try options.privateEnvironment(a);
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "test", "--force", try std.fs.path.join(a, &.{ options.fixtures, "i_live_place.selka" }), "--cache-dir", try options.suiteCache(a, @src()) });
        try argv.appendSlice(a, flags);
        const ran = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) {
            report("live iteration flags {any}, term {any}\nstdout:\n{s}\nstderr:\n{s}\n", .{ flags, ran.term, ran.stdout, ran.stderr });
        }
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("", ran.stderr);
        try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "5 passed") != null);
        try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "unsupported") == null);
    }
}

// spec-case: NEW-CORE-S2-SPLIT-3
test "gap_words checked split iteration preserves stored keys and control flow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment = try options.privateEnvironment(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    for ([_][]const []const u8{ &.{}, &.{ "--release", "--verify-facts" } }) |flags| {
        try support.requireReleaseArgs(flags);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "test", "--force", try std.fs.path.join(a, &.{ options.fixtures, "gap_words.selka" }), "--cache-dir", try options.suiteCache(a, @src()) });
        try argv.appendSlice(a, flags);
        const ran = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) std.debug.print("{s}{s}\n", .{ ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("", ran.stderr);
        try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "3 passed") != null);
    }
}

// spec-case: NEW-CORE-S2-SPLIT-3
test "gap_words empty separator traps before loop effects and early exit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment = try options.privateEnvironment(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const fixture = try std.fs.path.join(a, &.{ options.fixtures, "gap_words_empty.selka" });
    const argv: []const []const u8 = &.{ options.corePath(), "run", fixture, "--cache-dir", try options.suiteCache(a, @src()), "--release", "--verify-facts" };
    try support.requireReleaseArgs(argv);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = argv, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited and ran.term.exited != 0);
    try std.testing.expectEqualStrings("before\n", ran.stdout);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "R_EMPTY_SEPARATOR") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stderr, "live block") == null);
}
