//! `selka do [STEP] [ARGS...]`, driven through the compiler binary: it finds `build.selka` above the working folder, runs
//! it there with the step and its arguments, tells it where the compiler, its Zig and the root are, refuses when there is
//! no `build.selka`, and ends with the program's exit status.
const std = @import("std");
const testing = std.testing;

/// The `selka` executable under test, which `zig build` names at run time (TEST-PATHS-1).
fn compilerPath() []const u8 {
    return @import("test_paths").corePath();
}

/// A build program that prints what it was given and ends with 7 for the step `seven`; `hang` runs `sleep 30` with a
/// time limit of 0.3 s.
const build_program =
    \\import buildkit
    \\import filesystem
    \\
    \\func main(args: str[], proc: Process, fs: Filesystem, env: Environment, out: Stream) -> int:
    \\    print(out, "args", args)
    \\    if len(args) > 0 and args[0] == "hang":
    \\        const sleeper = buildkit.Command(argv=["sleep", "30"], limit_millis=300, log="hang.log")
    \\        const ran = buildkit.execute(proc, fs, out, sleeper) else Err(message):
    \\            print(out, message)
    \\            return 5
    \\        print(out, "timed out", ran.timed_out)
    \\        return 0
    \\    const tools = buildkit.locate(env) else Err(message):
    \\        print(out, message)
    \\        return 3
    \\    print(out, "compiler", tools.compiler)
    \\    print(out, "zig", tools.zig)
    \\    print(out, "root", tools.root)
    \\    const here = filesystem.cwd(fs) else Err(_):
    \\        return 4
    \\    print(out, "cwd", here)
    \\    if len(args) > 0 and args[0] == "seven":
    \\        return 7
    \\    return 0
    \\
;

/// Run the compiler with `args` in the folder `cwd`, with the test's private stores.
fn runIn(a: std.mem.Allocator, cwd: []const u8, args: []const []const u8) !std.process.RunResult {
    var environment = try @import("test_paths").privateEnvironment(a);
    defer environment.deinit();
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(a, compilerPath());
    try argv.appendSlice(a, args);
    return std.process.run(a, testing.io, .{ .argv = argv.items, .environ_map = &environment, .cwd = .{ .path = cwd } });
}

fn exitCode(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        else => 255,
    };
}

fn expectLine(stdout: []const u8, line: []const u8) !void {
    var lines = std.mem.splitScalar(u8, stdout, '\n');
    while (lines.next()) |found| if (std.mem.eql(u8, found, line)) return;
    std.debug.print("no line `{s}` in:\n{s}\n", .{ line, stdout });
    return error.TestExpectedEqual;
}

test "do from a sub-folder runs the build.selka above with the step, its arguments, the variables and its exit status" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDirPath(testing.io, "project/src/deep");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "project/build.selka", .data = build_program });
    const root = try temp.dir.realPathFileAlloc(testing.io, "project", a);
    const deep = try std.fs.path.join(a, &.{ root, "src/deep" });
    const ran = try runIn(a, deep, &.{ "do", "seven", "a", "--b" });
    if (exitCode(ran.term) != 7) std.debug.print("stdout:\n{s}\nstderr:\n{s}\n", .{ ran.stdout, ran.stderr });
    try testing.expectEqual(@as(u8, 7), exitCode(ran.term));
    try expectLine(ran.stdout, "args ['seven', 'a', '--b']");
    try expectLine(ran.stdout, try std.fmt.allocPrint(a, "root {s}", .{root}));
    try expectLine(ran.stdout, try std.fmt.allocPrint(a, "cwd {s}", .{root}));
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), a);
    try expectLine(ran.stdout, try std.fmt.allocPrint(a, "compiler {s}", .{compiler}));
    var environment = try @import("test_paths").privateEnvironment(a);
    defer environment.deinit();
    const zig = environment.get("ZIG") orelse environment.get("SELKA_ZIG") orelse "zig";
    if (std.fs.path.isAbsolute(zig) or std.mem.indexOfScalar(u8, zig, '/') == null)
        try expectLine(ran.stdout, try std.fmt.allocPrint(a, "zig {s}", .{zig}));

    // No step passes no arguments, and the program's status 0 is `do`'s.
    const bare = try runIn(a, root, &.{"do"});
    try testing.expectEqual(@as(u8, 0), exitCode(bare.term));
    try expectLine(bare.stdout, "args []");

    // A command past its time limit is stopped, and says so (`process.run_within` on a real program).
    const hung = try runIn(a, root, &.{ "do", "hang" });
    try testing.expectEqual(@as(u8, 0), exitCode(hung.term));
    try expectLine(hung.stdout, "timed out True");

    // Started with `selka run`, the program has no variables and `buildkit.locate` says how to start it.
    const plain = try runIn(a, root, &.{ "run", "build.selka" });
    try testing.expectEqual(@as(u8, 3), exitCode(plain.term));
    try testing.expect(std.mem.indexOf(u8, plain.stdout, "SELKA is not set: start this build program with `selka do STEP`") != null);
}

test "do with no build.selka above names the folder it started from and exits with 2" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDirPath(testing.io, "empty/build.selka");
    const start = try temp.dir.realPathFileAlloc(testing.io, "empty", a);
    // A folder named `build.selka` is not a build program.
    const inner = try std.fs.path.join(a, &.{ start, "build.selka" });
    const ran = try runIn(a, inner, &.{ "do", "check" });
    try testing.expectEqual(@as(u8, 2), exitCode(ran.term));
    const wanted = try std.fmt.allocPrint(a, "selka do: no build.selka in {s} or any folder above it\n", .{inner});
    try testing.expectEqualStrings(wanted, ran.stderr);
    try testing.expectEqualStrings("", ran.stdout);
}
