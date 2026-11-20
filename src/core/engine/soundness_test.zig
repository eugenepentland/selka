//! The soundness rules (spec §4): a kind reads the world only through its context. The files that implement each
//! registered kind are scanned for the names that reach the world another way, and the scan's own findings are tested
//! on a source that breaks the rule.
const std = @import("std");
const build_identity = @import("build_identity");
const access_scan = @import("access_scan.zig");
const kinds = @import("kinds.zig");

/// How many banned names the files of `closure` outside the engine runtime use. Reads the files from `src/`.
fn violations(a: std.mem.Allocator, closure: []const []const u8) !usize {
    var count: usize = 0;
    for (closure) |path| {
        if (access_scan.isEngineRuntime(path)) continue;
        const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fmt.allocPrint(a, "src/{s}", .{path}), a, .limited(8 << 20));
        count += (try access_scan.scan(a, source)).len;
    }
    return count;
}

test "no registered kind's implementation uses std.fs, std.Io.Dir, the environment, the clock or C directly" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(usize, kinds.all.len), build_identity.kind_code.len);
    var scanned: usize = 0;
    for (build_identity.kind_code) |closure| scanned += try violations(a, closure);
    try std.testing.expectEqual(@as(usize, 0), scanned);
}

test "a kind that reaches the world around its context is a violation" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sneaky =
        \\const std = @import("std");
        \\const context = @import("../context.zig");
        \\pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
        \\    _ = ctx;
        \\    const bytes = std.Io.Dir.cwd().readFileAlloc(undefined, argument, undefined, .unlimited) catch return error.Failed;
        \\    return bytes;
        \\}
    ;
    const found = try access_scan.scan(a, sneaky);
    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqualStrings("std.Io.Dir", found[0].name);
    try std.testing.expectEqual(@as(usize, 5), found[0].line);
}

test "the closure of a kind never holds the compiler, whose files read the world freely" {
    for (build_identity.kind_code) |closure| {
        for (closure) |path| try std.testing.expect(!std.mem.eql(u8, path, "compiler.zig"));
    }
}
