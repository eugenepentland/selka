//! `--cpu=MODEL` (lane GH-7.4): `build`, `run`, `build --run` and `test` take `native` (the default: this machine's CPU) or
//! `x86-64-v3` (the AVX2 floor, which the Selka components are built for), and refuse any other word with one line, status 2.
//! A `x86-64-v3` program is built and runs; its build never answers for a `native` one, nor the other way round.
const std = @import("std");
const testing = std.testing;

/// The `selka` executable under test, which `zig build` names at run time (TEST-PATHS-1).
fn compilerPath() []const u8 {
    return @import("test_paths").corePath();
}

/// Run the compiler with the shared stores disabled, as the other command-line tests do.
fn privateRun(a: std.mem.Allocator, argv: []const []const u8) !std.process.RunResult {
    var environment = try @import("test_paths").privateEnvironment(a);
    defer environment.deinit();
    return std.process.run(a, testing.io, .{ .argv = argv, .environ_map = &environment });
}

const hello_program =
    \\func main(out: Stream) -> int:
    \\    print(out, "hello from the floor")
    \\    return 0
    \\
;

const unknown_cpu = "selka: unknown --cpu value `bogus`; the values are `native` and `x86-64-v3`\n";

/// Where a test's files live: its source, built program and cache, under `dir`.
const Place = struct { path: []const u8, output: []const u8, cache: []const u8 };

fn place(a: std.mem.Allocator, dir: std.Io.Dir) !Place {
    try dir.writeFile(testing.io, .{ .sub_path = "hello.selka", .data = hello_program });
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    return .{
        .path = try std.fs.path.join(a, &.{ root, "hello.selka" }),
        .output = try std.fs.path.join(a, &.{ root, "hello" }),
        .cache = try std.fs.path.join(a, &.{ root, "cache" }),
    };
}

fn expectExit(code: u8, result: std.process.RunResult) !void {
    try testing.expectEqual(std.process.Child.Term{ .exited = code }, result.term);
}

test "selka build --cpu=x86-64-v3 builds a hello world that runs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const where = try place(a, tmp.dir);
    const built = try privateRun(a, &.{ compilerPath(), "build", where.path, "-o", where.output, "--cpu=x86-64-v3", "--cache-dir", where.cache });
    try expectExit(0, built);
    try testing.expectEqualStrings("", built.stderr);
    const ran = try std.process.run(a, testing.io, .{ .argv = &.{where.output} });
    try expectExit(0, ran);
    try testing.expectEqualStrings("hello from the floor", std.mem.trimEnd(u8, ran.stdout, "\n"));
}

test "selka run and build --run take --cpu in both spellings, and native is the default's own name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const where = try place(a, tmp.dir);
    const spellings = [_][]const []const u8{
        &.{ compilerPath(), "run", where.path, "--cpu=x86-64-v3", "--cache-dir", where.cache },
        &.{ compilerPath(), "run", where.path, "--cpu", "x86-64-v3", "--cache-dir", where.cache },
        &.{ compilerPath(), "build", where.path, "--run", "--cpu=x86-64-v3", "--cache-dir", where.cache },
        &.{ compilerPath(), "run", where.path, "--cpu=native", "--cache-dir", where.cache },
    };
    for (spellings) |argv| {
        const ran = try privateRun(a, argv);
        try expectExit(0, ran);
        try testing.expectEqualStrings("hello from the floor", std.mem.trimEnd(u8, ran.stdout, "\n"));
    }
}

test "--cpu with a word that is no model exits 2 with one line naming the two that are, in build, run and test" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const where = try place(a, tmp.dir);
    const commands = [_][]const []const u8{
        &.{ compilerPath(), "build", where.path, "-o", where.output, "--cpu=bogus", "--cache-dir", where.cache },
        &.{ compilerPath(), "run", where.path, "--cpu", "bogus", "--cache-dir", where.cache },
        &.{ compilerPath(), "build", where.path, "--run", "--cpu=bogus", "--cache-dir", where.cache },
        &.{ compilerPath(), "test", where.path, "--cpu=bogus", "--cache-dir", where.cache },
    };
    for (commands) |argv| {
        const refused = try privateRun(a, argv);
        try expectExit(2, refused);
        try testing.expectEqualStrings(unknown_cpu, refused.stderr);
        try testing.expectEqualStrings("", refused.stdout);
    }
}

test "a x86-64-v3 build is never served by a native build's record, nor a native one by it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const where = try place(a, tmp.dir);
    const replayed = "replayed the last identical build";
    const native = [_][]const u8{ compilerPath(), "build", where.path, "-o", where.output, "--cache-report", "--cache-dir", where.cache };
    const floor = native ++ [_][]const u8{"--cpu=x86-64-v3"};
    const first = try privateRun(a, &native);
    try expectExit(0, first);
    try testing.expect(std.mem.indexOf(u8, first.stderr, replayed) == null);
    const again = try privateRun(a, &native);
    try expectExit(0, again);
    try testing.expect(std.mem.indexOf(u8, again.stderr, replayed) != null);
    // The same program, the same cache, the other model: built, not replayed.
    const other = try privateRun(a, &floor);
    try expectExit(0, other);
    try testing.expect(std.mem.indexOf(u8, other.stderr, replayed) == null);
    const other_again = try privateRun(a, &floor);
    try expectExit(0, other_again);
    try testing.expect(std.mem.indexOf(u8, other_again.stderr, replayed) != null);
    // And back: the native record is still its own.
    const back = try privateRun(a, &native);
    try expectExit(0, back);
    try testing.expect(std.mem.indexOf(u8, back.stderr, replayed) != null);
}
