//! Behaviour the unit suites found missing when they moved onto the new core (S5-C1):
//! each test builds a small program from source text with the core this build made
//! and compares what it prints and reports with what the old core printed.
const std = @import("std");
const options = @import("core_test_options");

/// Failure detail goes to the test's stderr.
const report = std.debug.print;

const Outcome = struct { stdout: []const u8, stderr: []const u8, status: u8 };

/// Write `source` as `NAME.my` in `root`, build it (`--release` when asked) and run it.
fn buildAndRun(a: std.mem.Allocator, root: []const u8, name: []const u8, source: []const u8, release: bool) !Outcome {
    const path = try std.fmt.allocPrint(a, "{s}/{s}.my", .{ root, name });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = source });
    const output = try std.fmt.allocPrint(a, "{s}/{s}-{s}", .{ root, name, if (release) "release" else "debug" });
    const cache = try std.fmt.allocPrint(a, "{s}/cache", .{root});
    // `mylang build` reports the source path as it was given, so build from
    // `root` by the file's own name.
    var argv: std.ArrayList([]const u8) = .empty;
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, options.core_path, a);
    try argv.appendSlice(a, &.{ compiler, "build", try std.fmt.allocPrint(a, "{s}.my", .{name}), "-o", output, "--cache-dir", cache });
    if (release) try argv.append(a, "--release");
    const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .cwd = .{ .path = root } });
    if (built.term != .exited or built.term.exited != 0) report("{s}{s}", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{output} });
    const status: u8 = switch (ran.term) {
        .exited => |code| code,
        else => 255,
    };
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = status };
}

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

// spec: NEW-CORE-S5-STREAM-WRITE-1
test "stream.write answers the scalars of a string and the bytes of a byte value it wrote" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const source =
        \\func send(log: Stream, data: bytes) -> int:
        \\    return log.write(data)
        \\
        \\
        \\func show(log: Stream) -> int:
        \\    return log.write("abcd")
        \\
        \\
        \\func main(out: Stream, err: Stream) -> int:
        \\    out.print(show(out))
        \\    err.print(send(err, b"B\x00\xff"))
        \\    out.print(out.write("λ"), out.write(b"λ"))
        \\    _ = out.write("!")
        \\    return 0
    ;
    for ([_]bool{ false, true }) |release| {
        const ran = try buildAndRun(arena.allocator(), root, "write", source, release);
        try std.testing.expectEqualStrings("abcd4\nλλ1 2\n!", ran.stdout);
        try std.testing.expectEqualStrings("B\x00\xff3\n", ran.stderr);
    }
}

// spec-case: TRAP-UNSIGNED-1
test "an unsigned overflow, division or cast trap quotes its operands unsigned and marks its record" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const a = arena.allocator();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const Case = struct { body: []const u8, text: []const u8, record: []const u8 };
    const cases = [_]Case{
        .{ .body = "return i64(x + y)", .text = "(add: left 18446744073709551614, right 5, width 64)", .record = "{\"version\":1,\"operation\":\"add\",\"unsigned\":true,\"left\":18446744073709551614,\"right\":5,\"width\":64}" },
        .{ .body = "return i64(x)", .text = "(cast: left 18446744073709551614, width 64)", .record = "\"operation\":\"cast\",\"unsigned\":true,\"left\":18446744073709551614" },
        .{ .body = "return i64(x // (y - y))", .text = "left 18446744073709551614, right 0)", .record = "\"unsigned\":true,\"left\":18446744073709551614,\"right\":0}" },
        // A signed operation keeps its signed rendering and record.
        .{ .body = "return z + 1", .text = "(add: left 9223372036854775807, right 1, width 64)", .record = "{\"version\":1,\"operation\":\"add\",\"left\":9223372036854775807,\"right\":1,\"width\":64}" },
    };
    for (cases, 0..) |case, index| {
        const source = try std.fmt.allocPrint(a,
            \\func compute(x: u64, y: u64, z: i64) -> i64:
            \\    _ = x
            \\    _ = y
            \\    _ = z
            \\    {s}
            \\
            \\
            \\func main() -> i64:
            \\    return compute(18446744073709551614, 5, 9223372036854775807)
        , .{case.body});
        const ran = try buildAndRun(a, root, try std.fmt.allocPrint(a, "unsigned{d}", .{index}), source, false);
        try std.testing.expectEqual(@as(u8, 1), ran.status);
        try std.testing.expect(contains(ran.stderr, case.text));
        try std.testing.expect(contains(ran.stderr, case.record));
    }
}

// spec-case: NEW-CORE-S5-CONTRACT-1
test "a broken precondition names the caller that broke it, and a postcondition does not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const a = arena.allocator();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const requires =
        \\@requires(x > 0, "must be positive")
        \\func f(x: int) -> int:
        \\    return x
        \\
        \\func g(y: int) -> int:
        \\    return f(y)
        \\
        \\func main() -> int:
        \\    return g(0)
    ;
    for ([_]bool{ false, true }) |release| {
        const ran = try buildAndRun(a, root, "requires", requires, release);
        try std.testing.expectEqual(@as(u8, 1), ran.status);
        const expected = "requires.my:1:11: error[R_REQUIRES]: precondition violated: f requires `x > 0`: must be positive; " ++
            "broken by the caller g at requires.my:6:12\n" ++
            "  in f at requires.my:1:11\n  in g at requires.my:6:12\n  in main at requires.my:9:12\n";
        try std.testing.expect(contains(ran.stderr, expected));
    }
    const ensures = "@ensures(result < 10)\nfunc clamp(x: int) -> int:\n    return x\n\nfunc main() -> int:\n    return clamp(70)\n";
    const broken = try buildAndRun(a, root, "ensures", ensures, false);
    try std.testing.expect(contains(broken.stderr, "error[R_ENSURES]: postcondition violated: clamp ensures `result < 10`\n  in clamp at"));
}

// spec-case: NEW-CORE-ERRTRACE-1
test "an Err a runtime operation answers starts the trace as produced by the runtime" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const a = arena.allocator();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source =
        \\func main() -> Result[int, str]:
        \\    mut data = b"\xff"
        \\    mut text = try data.decode()
        \\    return Ok(len(text))
    ;
    const ran = try buildAndRun(a, root, "decode", source, false);
    try std.testing.expectEqual(@as(u8, 1), ran.status);
    try std.testing.expect(contains(ran.stderr, "error: invalid UTF-8 in byte string\n"));
    try std.testing.expect(contains(ran.stderr, "decode.my:3:20  main  Err produced by the runtime\n"));
    try std.testing.expect(std.mem.endsWith(u8, ran.stderr, "decode.my:3:16  main  try propagated\n"));
}

// spec: NEW-CORE-S5-EMBED-1
test "a header-less file embeds a file beside it, and an edit to that file alone rebuilds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const a = arena.allocator();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "data.bin", .data = "abc" });
    const source = "func main() -> int:\n    return len(embed_bytes(\"data.bin\")) + len(embed_str(\"data.bin\")) + 40\n";
    try std.testing.expectEqual(@as(u8, 46), (try buildAndRun(a, root, "embedded", source, false)).status);
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "data.bin", .data = "abcdef" });
    try std.testing.expectEqual(@as(u8, 52), (try buildAndRun(a, root, "embedded", source, false)).status);
}

// spec: NEW-CORE-S5-LABELS-1
test "a block that continues after a thousand checks builds, in debug and release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const a = arena.allocator();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const text = try chain(a, 1024);
    for ([_]bool{ false, true }) |release| {
        const ran = try buildAndRun(a, root, "chain", text, release);
        try std.testing.expectEqual(@as(u8, 24), ran.status);
    }
}

/// `main` returning the sum of `terms` checked additions of one, less 1000.
fn chain(a: std.mem.Allocator, terms: usize) ![]const u8 {
    var text: std.Io.Writer.Allocating = .init(a);
    try text.writer.writeAll("func main(args: str[]) -> int:\n    mut one = len(args) + 1\n    return one");
    for (1..terms) |_| try text.writer.writeAll(" + one");
    try text.writer.writeAll(" - 1000\n");
    return text.written();
}

// spec-case: STREAM-BYTES-1
test "a program whose standard output refuses its writes fails R_OUTPUT instead of exiting with main's status" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const a = arena.allocator();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = "func main(out: Stream) -> int:\n    out.print(\"line\")\n    _ = out.write(b\"raw\\x00\\xff\")\n    return 7\n";
    const ran = try buildAndRun(a, root, "full", source, false);
    try std.testing.expectEqual(@as(u8, 7), ran.status);
    const full = std.Io.Dir.openFileAbsolute(std.testing.io, "/dev/full", .{ .mode = .write_only }) catch return error.SkipZigTest;
    defer full.close(std.testing.io);
    const program = try std.fmt.allocPrint(a, "{s}/full-debug", .{root});
    var child = try std.process.spawn(std.testing.io, .{ .argv = &.{program}, .stdout = .{ .file = full }, .stderr = .pipe });
    var buffer: [4096]u8 = undefined;
    var reader = child.stderr.?.readerStreaming(std.testing.io, &buffer);
    const diagnostic = try reader.interface.allocRemaining(a, .limited(64 * 1024));
    const term = try child.wait(std.testing.io);
    try std.testing.expect(term == .exited and term.exited == 1);
    try std.testing.expectEqualStrings("error[R_OUTPUT]: native execution failed\nstandard output refused a write\n", diagnostic);
}
