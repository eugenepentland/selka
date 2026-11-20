//! Negative positions are explicit terminating bounds failures through optimized lowering.
const std = @import("std");
const testing = std.testing;

/// Skips the calling test while release builds are off (`-Dtest-release=true` runs them).
fn requireRelease() error{SkipZigTest}!void {
    if (!@import("test_release_options").enabled) return error.SkipZigTest;
}

/// Skips the calling test while release builds are off, when the compiler flags ask for `--release`.
fn requireReleaseArgs(argv: []const []const u8) error{SkipZigTest}!void {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--release")) return requireRelease();
    }
}

const source =
    \\import buffers
    \\import bytes
    \\import strings
    \\
    \\@noalloc
    \\func search(text: str, start: int, end: int) -> int:
    \\    return strings.char_find(text, "", start, end)
    \\
    \\func find_any(data: bytes, start: int) -> int:
    \\    return bytes.find_any(data, b"1", start)
    \\
    \\func find_any_end(data: bytes, end: int) -> int:
    \\    return bytes.find_any(data, b"1", 0, end)
    \\
    \\func main(args: str[]) -> int:
    \\    const n = 0 - len(args)
    \\    const xs = [10, 20, 30]
    \\    const text = "aéz"
    \\    const data = b"123"
    \\    const empty: int[] = []
    \\    mut buffer = byte_buffer(empty)
    \\    if args[0] == "list-read":
    \\        _ = xs[n]
    \\    if args[0] == "list-start":
    \\        _ = xs[n:2]
    \\    if args[0] == "list-end":
    \\        _ = xs[0:n]
    \\    if args[0] == "text-read":
    \\        _ = strings.char_at(text, n)
    \\    if args[0] == "bytes-read":
    \\        _ = data[n]
    \\    if args[0] == "text-start":
    \\        _ = strings.char_slice(text, n, 2)
    \\    if args[0] == "text-end":
    \\        _ = strings.char_slice(text, 0, n)
    \\    if args[0] == "bytes-start":
    \\        _ = data[n:2]
    \\    if args[0] == "bytes-end":
    \\        _ = data[0:n]
    \\    if args[0] == "find-start":
    \\        _ = search(text, n, 3)
    \\    if args[0] == "find-end":
    \\        _ = search(text, 0, n)
    \\    if args[0] == "bytes-find-start":
    \\        _ = bytes.find(data, b"", n)
    \\    if args[0] == "bytes-find-end":
    \\        _ = bytes.find(data, b"", 0, n)
    \\    if args[0] == "find-any":
    \\        _ = find_any(data, n)
    \\    if args[0] == "find-any-end":
    \\        _ = find_any_end(data, n)
    \\    if args[0] == "append-start":
    \\        _ = buffers.append_range(mut buffer, data, n, 2)
    \\    if args[0] == "append-end":
    \\        _ = buffers.append_range(mut buffer, data, 0, n)
    \\    if args[0] == "parse-int":
    \\        _ = bytes.parse_int_range(data, n, 2)
    \\    if args[0] == "parse-float":
    \\        _ = bytes.parse_float_range(data, 0, n)
    \\    if args[0] == "nested-byte-start":
    \\        _ = data[n:2]
    \\    if args[0] == "nested-text-end":
    \\        _ = strings.char_slice(text, 0, n)
    \\    if args[0] == "step":
    \\        _ = strings.char_stride(text, n, 2, 1)
    \\    assert xs[1] == 20 and xs[1:99] == [20, 30]
    \\    assert strings.char_slice(text, 1, 99) == "éz" and data[1:99] == b"23"
    \\    assert strings.char_find(text, "", 99) == -1 and strings.char_find(text, "", 0, 99) == 0
    \\    assert find_any(data, 99) == -1 and find_any_end(data, 99) == 0 and find_any_end(data, 0) == -1
    \\    assert not buffers.append_range(mut buffer, data, 4, 5)
    \\    assert buffers.append_range(mut buffer, data, 1, 3)
    \\    assert bytes(buffer) == b"23"
    \\    return 0
;

const negative_cases = [_]struct { kind: []const u8, code: []const u8 }{
    .{ .kind = "list-read", .code = "R_LIST_BOUNDS" },
    .{ .kind = "list-start", .code = "R_LIST_BOUNDS" },
    .{ .kind = "list-end", .code = "R_LIST_BOUNDS" },
    .{ .kind = "text-read", .code = "R_TEXT_BOUNDS" },
    .{ .kind = "bytes-read", .code = "R_LIST_BOUNDS" },
    .{ .kind = "text-start", .code = "R_TEXT_BOUNDS" },
    .{ .kind = "text-end", .code = "R_TEXT_BOUNDS" },
    .{ .kind = "bytes-start", .code = "R_LIST_BOUNDS" },
    .{ .kind = "bytes-end", .code = "R_LIST_BOUNDS" },
    .{ .kind = "find-start", .code = "R_TEXT_BOUNDS" },
    .{ .kind = "find-end", .code = "R_TEXT_BOUNDS" },
    .{ .kind = "bytes-find-start", .code = "R_LIST_BOUNDS" },
    .{ .kind = "bytes-find-end", .code = "R_LIST_BOUNDS" },
    .{ .kind = "find-any", .code = "R_LIST_BOUNDS" },
    .{ .kind = "find-any-end", .code = "R_LIST_BOUNDS" },
    .{ .kind = "append-start", .code = "R_LIST_BOUNDS" },
    .{ .kind = "append-end", .code = "R_LIST_BOUNDS" },
    .{ .kind = "parse-int", .code = "R_LIST_BOUNDS" },
    .{ .kind = "parse-float", .code = "R_LIST_BOUNDS" },
    .{ .kind = "nested-byte-start", .code = "R_LIST_BOUNDS" },
    .{ .kind = "nested-text-end", .code = "R_TEXT_BOUNDS" },
    .{ .kind = "step", .code = "R_TEXT_BOUNDS" },
};

fn status(result: std.process.RunResult) u8 {
    return switch (result.term) {
        .exited => |value| value,
        else => 255,
    };
}

fn matrix() !bool {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(testing.io, ".", a);
    const input = try std.fs.path.join(a, &.{ root, "positions.selka" });
    const binary = try std.fs.path.join(a, &.{ root, "positions" });
    const cache = try std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{root});
    const modes = [_][]const []const u8{ &.{}, &.{"--release"}, &.{ "--release", "--verify-facts" } };
    for (modes) |mode| {
        try requireReleaseArgs(mode);
        const input_source = source;
        try dir.dir.writeFile(testing.io, .{ .sub_path = "positions.selka", .data = input_source });
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ @import("test_paths").corePath(), "build", input, "-o", binary, cache });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, testing.io, .{ .argv = argv.items });
        if (status(built) != 0) std.debug.print("position build: {s}{s}\n", .{ built.stdout, built.stderr });
        try testing.expectEqual(@as(u8, 0), status(built));
        for (negative_cases) |case| {
            const kind = case.kind;
            const code = case.code;
            const ran = try std.process.run(a, testing.io, .{ .argv = &.{ binary, kind } });
            try testing.expectEqual(@as(u8, 1), status(ran));
            if (std.mem.indexOf(u8, ran.stderr, code) == null) std.debug.print("position {s}: {s}\n", .{ kind, ran.stderr });
            try testing.expect(std.mem.indexOf(u8, ran.stderr, code) != null);
            try testing.expect(std.mem.indexOf(u8, ran.stderr, "positions.selka:") != null);
            try testing.expect(std.mem.indexOf(u8, ran.stderr, "(index -1, length 3)") != null);
            try testing.expect(std.mem.indexOf(u8, ran.stderr, "negative indexes are not allowed") != null);
        }
        const positive = try std.process.run(a, testing.io, .{ .argv = &.{ binary, "positive" } });
        if (status(positive) != 0) std.debug.print("positive: {s}\n", .{positive.stderr});
        try testing.expectEqual(@as(u8, 0), status(positive));
        try testing.expectEqualStrings("", positive.stderr);
    }
    return true;
}

// spec: POSITION-BOUNDS-1
test "cleanup negative positions trap after optimization and preserve positive contracts" {
    try testing.expect(try matrix());
}
