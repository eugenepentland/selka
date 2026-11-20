//! `selka do [STEP] [ARGS...]`: find `build.selka` in the working folder or the nearest folder above it, and run it as
//! `selka run build.selka -- STEP ARGS...` would from that folder, with the program told what it would otherwise guess:
//! `SELKA` (this compiler's path), `SELKA_ZIG` (the Zig it uses) and `SELKA_PROJECT_ROOT` (the folder of `build.selka`).
//! The program's exit status is `do`'s; with no `build.selka` above, `do` names the folder it started from (status 2).
const std = @import("std");
const cli_run = @import("cli_run.zig");

/// The build program `do` looks for.
pub const program_name = "build.selka";

/// The usage `run`'s parser prints when the arguments `do` hands it are refused.
const usage = "usage: selka do [STEP] [ARGS...] (find build.selka here or in the nearest folder above and run it there)\n";

/// The folder `start` or the nearest one above it that holds a file `build.selka`, or null; `start` is absolute.
pub fn findRoot(io: std.Io, a: std.mem.Allocator, start: []const u8) error{OutOfMemory}!?[]const u8 {
    var folder: []const u8 = start;
    while (true) {
        const candidate = try std.fs.path.join(a, &.{ folder, program_name });
        if (std.Io.Dir.cwd().statFile(io, candidate, .{})) |stat| {
            if (stat.kind == .file) return folder;
        } else |_| {}
        folder = std.fs.path.dirname(folder) orelse return null;
    }
}

/// The arguments of `selka run` that run `build.selka` with `step_and_args` after `--` (none when there are none).
pub fn runArguments(a: std.mem.Allocator, step_and_args: []const []const u8) error{OutOfMemory}![]const []const u8 {
    var arguments: std.ArrayList([]const u8) = .empty;
    try arguments.append(a, program_name);
    if (step_and_args.len > 0) {
        try arguments.append(a, "--");
        try arguments.appendSlice(a, step_and_args);
    }
    return arguments.items;
}

/// `zig` as the build program must name it from the project's root: a path relative to `start` made absolute, a bare
/// name (searched on PATH) or an absolute path left as it is.
pub fn zigFrom(a: std.mem.Allocator, start: []const u8, zig: []const u8) error{OutOfMemory}![]const u8 {
    if (std.fs.path.isAbsolute(zig) or std.mem.indexOfScalar(u8, zig, '/') == null) return zig;
    return std.fs.path.resolve(a, &.{ start, zig });
}

fn fail(init: std.process.Init, message: []const u8) cli_run.Error!u8 {
    std.Io.File.stderr().writeStreamingAll(init.io, message) catch return error.WriteFailed;
    return 2;
}

/// Run `selka do` with `args` (the words after `do`) and return the build program's exit status.
pub fn run(init: std.process.Init, args: []const []const u8) cli_run.Error!u8 {
    const a = init.arena.allocator();
    const start = std.Io.Dir.cwd().realPathFileAlloc(init.io, ".", a) catch |err|
        return fail(init, try std.fmt.allocPrint(a, "selka do: cannot read the working folder: {s}\n", .{@errorName(err)}));
    const root = try findRoot(init.io, a, start) orelse
        return fail(init, try std.fmt.allocPrint(a, "selka do: no {s} in {s} or any folder above it\n", .{ program_name, start }));
    const compiler = std.process.executablePathAlloc(init.io, a) catch |err|
        return fail(init, try std.fmt.allocPrint(a, "selka do: cannot find this compiler's own path: {s}\n", .{@errorName(err)}));
    const zig = try zigFrom(a, start, cli_run.zigPath(init));
    std.process.setCurrentPath(init.io, root) catch |err|
        return fail(init, try std.fmt.allocPrint(a, "selka do: cannot enter {s}: {s}\n", .{ root, @errorName(err) }));
    const request = try cli_run.parseRequest(init, .run, try runArguments(a, args), usage) orelse return 2;
    const variables = [_]cli_run.GuestVariable{
        .{ .name = "SELKA", .value = compiler },
        .{ .name = "SELKA_ZIG", .value = zig },
        .{ .name = "SELKA_PROJECT_ROOT", .value = root },
    };
    return cli_run.runWith(init, request, "do", &variables);
}

test "do finds the nearest build.selka above, and none above the root" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = t.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(t.io, "project/src/deep");
    try tmp.dir.writeFile(t.io, .{ .sub_path = "project/build.selka", .data = "func main() -> int:\n    return 0\n" });
    try tmp.dir.createDirPath(t.io, "project/src/build.selka");
    const base = try tmp.dir.realPathFileAlloc(t.io, ".", a);
    const deep = try std.fs.path.join(a, &.{ base, "project/src/deep" });
    // `src/build.selka` is a folder, so the search goes on to `project`.
    try t.expectEqualStrings(try std.fs.path.join(a, &.{ base, "project" }), (try findRoot(t.io, a, deep)).?);
    try t.expectEqual(@as(?[]const u8, null), try findRoot(t.io, a, base));
}

test "do passes the step and its arguments after --, and nothing when there is no step" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const with_step = try runArguments(a, &.{ "image", "blink", "--release" });
    try t.expectEqual(@as(usize, 5), with_step.len);
    try t.expectEqualStrings("build.selka", with_step[0]);
    try t.expectEqualStrings("--", with_step[1]);
    try t.expectEqualStrings("--release", with_step[4]);
    try t.expectEqual(@as(usize, 1), (try runArguments(a, &.{})).len);
    try t.expectEqualStrings("/opt/zig/zig", try zigFrom(a, "/home/p", "/opt/zig/zig"));
    try t.expectEqualStrings("zig", try zigFrom(a, "/home/p", "zig"));
    try t.expectEqualStrings("/home/p/tools/zig", try zigFrom(a, "/home/p", "tools/zig"));
}
