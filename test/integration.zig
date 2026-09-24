//! Spawn the selected-mode compiler binary; fixtures assert the public CLI contract.
const std = @import("std");
const testing = std.testing;
const compiler_path = @import("test_options").compiler_path;
const arena_example_path = @import("test_options").arena_example_path;
/// `run` and `run-project` build natively; the fixtures name this build's tools
/// because the compiler under test is not installed beside them.
const tools = [_][]const u8{
    "--qbe=" ++ @import("test_options").qbe_path,
    "--zig=" ++ @import("test_options").zig_path,
};
const host_program =
    \\host def measure(host: Host, x: i64) -> i64 effects(host)
    \\
    \\
    \\def main(host: Host) -> i64:
    \\    return measure(host, 6)
;

// spec-case: CONSTANT-2
test "CLI managed constants check and reject expressions" {
    try invoke("check", "const S: str = \"hé🙂\"\nconst B: bytes = b\"\\x00\\xff\"\ndef main() -> int:\n    return len(S) + len(B)\n", 0, "", "");
    try invoke("check", "const S: str = \"a\" + \"b\"\ndef main() -> int:\n    return 0\n", 1, "", "E_CONSTANT_EXPRESSION");
    try invoke("check", "const B: bytes = OTHER\nconst OTHER: bytes = b\"x\"\ndef main() -> int:\n    return 0\n", 1, "", "E_CONSTANT_EXPRESSION");
}

fn expectConstantProcess(argv: []const []const u8, expected: []const u8) !void {
    return expectConstantRun(argv, null, expected);
}

/// The inherited environment plus `MYLANG_OPTIONS`, where a built program reads
/// its runtime options.
fn runtimeOptions(value: []const u8) !std.process.Environ.Map {
    var environment = try std.process.Environ.createMap(testing.environ, testing.allocator);
    errdefer environment.deinit();
    try environment.put("MYLANG_OPTIONS", value);
    return environment;
}

fn expectConstantRun(argv: []const []const u8, environment: ?*const std.process.Environ.Map, expected: []const u8) !void {
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv, .environ_map = environment });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqualStrings("", result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings(expected, result.stdout);
}

fn managedConstantModes(temporary: *testing.TmpDir, data: []const u8, expected: []const u8) !void {
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "constants.my", .data = data });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const output = try std.fs.path.join(testing.allocator, &.{ root, "program" });
    defer testing.allocator.free(output);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);
    try expectConstantProcess(&.{ compiler_path, "check-project", entry, cache_argument }, "");
    try expectConstantProcess(&.{ compiler_path, "run", entry, cache_argument, tools[0], tools[1] }, expected);
    try expectConstantProcess(&.{ compiler_path, "build", entry, "--run", "--cache-dir", cache, tools[0], tools[1] }, expected);
    try expectConstantProcess(&.{ compiler_path, "build", entry, "--project", "-o", output, "--cache-dir", cache, tools[0], tools[1] }, "");
    try expectConstantProcess(&.{output}, expected);
    var stressed = try runtimeOptions("--gc-stress");
    defer stressed.deinit();
    try expectConstantRun(&.{output}, &stressed, expected);
}

// A module-entry `run` prints the check phase's diagnostics exactly once: a
// clean project prints none, and the runner has nothing to repeat.
test "CLI run reports each frontend warning once" {
    const outcome = try runProjectFixture("run",
        \\module main
        \\
        \\
        \\def touch(values: mut list[int]) -> None:
        \\    values[0] = 1
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    touch(mut values)
        \\    return 0
    , &.{});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expectEqual(@as(usize, 0), std.mem.count(u8, outcome.stderr, "warning["));
}

// spec-case: NATIVE-RUN-MANIFEST-CACHE-1
test "CLI project run reuses emitted manifest while no-cache and grants stay authoritative" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\module main
        \\
        \\
        \\def main(fs: Filesystem) -> int:
        \\    _ = fs
        \\    return 0
    });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);
    const base = .{ compiler_path, "run-project", entry, "--report", cache_argument } ++ tools;

    const cold = try std.process.run(testing.allocator, testing.io, .{ .argv = &base });
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cold.term);
    const cold_work = try c4CommandWorkLine(cold.stderr, "run-project");
    const cold_lowered = try c4WorkCount(cold_work, "lowered_functions", "performed");
    const cold_emitted = try c4WorkCount(cold_work, "emitted_fragments", "performed");
    try testing.expect(cold_lowered > 0);
    try testing.expectEqual(cold_lowered, cold_emitted);

    const warm = try std.process.run(testing.allocator, testing.io, .{ .argv = &base });
    defer testing.allocator.free(warm.stdout);
    defer testing.allocator.free(warm.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, warm.term);
    const warm_work = try c4CommandWorkLine(warm.stderr, "run-project");
    try testing.expectEqual(@as(usize, 0), try c4WorkCount(warm_work, "lowered_functions", "performed"));
    try testing.expectEqual(cold_lowered, try c4WorkCount(warm_work, "lowered_functions", "reused"));
    try testing.expectEqual(@as(usize, 0), try c4WorkCount(warm_work, "emitted_fragments", "performed"));
    try testing.expectEqual(cold_emitted, try c4WorkCount(warm_work, "emitted_fragments", "reused"));

    const alias_argv = .{ compiler_path, "run", entry, "--report", cache_argument } ++ tools;
    const alias = try std.process.run(testing.allocator, testing.io, .{ .argv = &alias_argv });
    defer testing.allocator.free(alias.stdout);
    defer testing.allocator.free(alias.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, alias.term);
    const alias_work = try c4CommandWorkLine(alias.stderr, "run");
    try testing.expectEqual(@as(usize, 0), try c4WorkCount(alias_work, "lowered_functions", "performed"));
    try testing.expectEqual(cold_lowered, try c4WorkCount(alias_work, "lowered_functions", "reused"));
    try testing.expectEqual(@as(usize, 0), try c4WorkCount(alias_work, "emitted_fragments", "performed"));
    try testing.expectEqual(cold_emitted, try c4WorkCount(alias_work, "emitted_fragments", "reused"));

    const explained_argv = base ++ .{"--explain-invalidation"};
    const explained = try std.process.run(testing.allocator, testing.io, .{ .argv = &explained_argv });
    defer testing.allocator.free(explained.stdout);
    defer testing.allocator.free(explained.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, explained.term);
    const explained_work = try c4CommandWorkLine(explained.stderr, "run-project");
    try testing.expect(try c4WorkCount(explained_work, "lowered_functions", "performed") > 0);
    try testing.expectEqual(@as(usize, 0), try c4WorkCount(explained_work, "emitted_fragments", "performed"));
    try testing.expectEqual(cold_emitted, try c4WorkCount(explained_work, "emitted_fragments", "reused"));

    const uncached_argv = base ++ .{"--no-cache"};
    const uncached = try std.process.run(testing.allocator, testing.io, .{ .argv = &uncached_argv });
    defer testing.allocator.free(uncached.stdout);
    defer testing.allocator.free(uncached.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, uncached.term);
    const uncached_work = try c4CommandWorkLine(uncached.stderr, "run-project");
    try testing.expect(try c4WorkCount(uncached_work, "lowered_functions", "performed") > 0);
    try testing.expect(try c4WorkCount(uncached_work, "emitted_fragments", "performed") > 0);

    const restricted_argv = base ++ .{"--restrict"};
    const restricted = try std.process.run(testing.allocator, testing.io, .{ .argv = &restricted_argv });
    defer testing.allocator.free(restricted.stdout);
    defer testing.allocator.free(restricted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, restricted.term);
    try testing.expect(std.mem.indexOf(u8, restricted.stderr, "--allow-read=DIR") != null);
}

// spec-case: CONSTANT-2
test "CLI managed constants import run build installed and invalidate warm caches" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\module main
        \\import constants
        \\def read[T]() -> str:
        \\    return constants.TEXT
        \\def main(out: Stream) -> int:
        \\    out.print(read[int]())
        \\    out.print(len(constants.DATA))
        \\    out.print(constants.DATA[1])
        \\    return 0
    });
    const original = "module constants\npublic const TEXT: str = \"hé🙂\"\npublic const DATA: bytes = b\"\\x00\\xff\"\n";
    try managedConstantModes(&temporary, original, "hé🙂\n2\n255\n");
    try managedConstantModes(&temporary, original, "hé🙂\n2\n255\n");
    // Same byte lengths, new contents: unchanged callers must observe the new IL.
    try managedConstantModes(&temporary, "module constants\npublic const TEXT: str = \"hà🙃\"\npublic const DATA: bytes = b\"\\x00\\xfe\"\n", "hà🙃\n2\n254\n");
}

test "CLI checks host declarations and refuses to run one with no registration" {
    try invoke("check", host_program, 0, "", "");
    // Nothing registers a host implementation for a plain `mylang run`, so the
    // program cannot start; that is a host-boundary refusal, not a guest trap.
    try invoke("run", host_program, 2, "", "HostMissingRegistration");
}
// spec: HOST-CAPABILITY-1
test "CLI threads a Host capability through an extern call and runs it natively" {
    const source =
        \\extern def abs(host: Host, x: i32) -> i32 effects(host)
        \\
        \\
        \\def main(host: Host) -> i64:
        \\    return i64(abs(host, -7))
    ;
    try invoke("check", source, 0, "", "");
    try invokeOptions("run", source, &.{}, 0, "7\n", "");
}
// spec: FLOAT-NAN-OBSERVED-3
test "CLI passes every NaN to foreign code as the canonical quiet NaN" {
    // `-(0.0 / 0.0)` carries the sign bit; C's `copysign` reads it, so an
    // argument that crossed uncanonicalized would answer -1.0. A NaN the
    // foreign function returns enters the guest and still prints `nan`.
    const source =
        \\extern def copysign(host: Host, x: float, y: float) -> float effects(host)
        \\
        \\
        \\def nan_of(zero: float) -> float:
        \\    return zero / zero
        \\
        \\
        \\def main(host: Host, out: Stream) -> int:
        \\    nan = nan_of(0.0)
        \\    out.print(copysign(host, 1.0, nan), copysign(host, 1.0, -nan), copysign(host, 1.0, -2.0))
        \\    out.print(copysign(host, -nan, 1.0), copysign(host, nan, -1.0))
        \\    return 0
    ;
    try invokeOptions("run", source, &.{}, 0, "1.0 1.0 -1.0\nnan nan\n0\n", "");
}
// spec-case: HOST-CAPABILITY-1
test "CLI withholds Host under restrict and grants it with --allow-host" {
    const source =
        \\extern def abs(host: Host, x: i32) -> i32 effects(host)
        \\
        \\
        \\def main(host: Host) -> i64:
        \\    return i64(abs(host, -7))
    ;
    try invokeOptions("run", source, &.{"--restrict"}, 2, "", "--allow-host");
    try invokeOptions("run", source, &.{ "--restrict", "--allow-host" }, 0, "7\n", "");
}
// spec-case: ARENA-MANAGED-1
test "CLI runs the managed arena example under normal and stress collection" {
    for ([_][]const []const u8{ &.{}, &.{"--gc-stress"} }) |options| {
        var args: std.ArrayList([]const u8) = .empty;
        defer args.deinit(testing.allocator);
        try args.appendSlice(testing.allocator, &.{ compiler_path, "run", arena_example_path, "--print-result" });
        try args.appendSlice(testing.allocator, &tools);
        try args.appendSlice(testing.allocator, options);
        const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
        defer testing.allocator.free(outcome.stdout);
        defer testing.allocator.free(outcome.stderr);
        // The entry returns 38, which is now the process exit status.
        try testing.expectEqual(std.process.Child.Term{ .exited = 38 }, outcome.term);
        try testing.expectEqualStrings("38\n", outcome.stdout);
        try testing.expectEqualStrings("", outcome.stderr);
    }
}
// spec-case: ARENA-MANAGED-4
test "CLI reports managed arena escapes as machine-readable diagnostics" {
    const source =
        \\def main() -> int:
        \\    keeper: list[int] = []
        \\    with arena() as scratch:
        \\        keeper = [1, 2]
        \\    return len(keeper)
    ;
    try invoke("check", source, 1, "", "error[E_ARENA_ESCAPE]");
    try invokeOptions("check", source, &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_ARENA_ESCAPE\"");
}
fn invoke(command: []const u8, text: []const u8, expected_status: u8, expected_stdout: []const u8, stderr_part: []const u8) !void {
    return invokeOptions(command, text, &.{}, expected_status, expected_stdout, stderr_part);
}
/// The process exit status a `--print-result` run now yields: the entry's printed
/// integer result truncated to the low 8 bits (POSIX status), read from the final
/// output line. A command that does not print a result line, or a non-run command,
/// yields 0.
fn resultStatus(printed: []const u8) u8 {
    const body = std.mem.trimEnd(u8, printed, "\n");
    const start = if (std.mem.lastIndexOfScalar(u8, body, '\n')) |index| index + 1 else 0;
    const value = std.fmt.parseInt(i64, body[start..], 10) catch return 0;
    return @truncate(@as(u64, @bitCast(value)));
}
fn invokeOptions(command: []const u8, text: []const u8, options: []const []const u8, expected_status: u8, expected_stdout: []const u8, stderr_part: []const u8) !void {
    const outcome = try runFixture(command, text, options);
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    // A successful run exits with its entry's `int` result; the callers pass 0 for
    // that success and encode it through `expected_stdout` (the `--print-result`
    // line), so derive the truncated status from there and keep the explicit value
    // for traps, usage and host failures.
    const wanted = if (std.mem.startsWith(u8, command, "run") and expected_status == 0) resultStatus(expected_stdout) else expected_status;
    try testing.expectEqual(std.process.Child.Term{ .exited = wanted }, outcome.term);
    try testing.expectEqualStrings(expected_stdout, outcome.stdout);
    if (stderr_part.len == 0) try testing.expectEqualStrings("", outcome.stderr) else try testing.expect(std.mem.indexOf(u8, outcome.stderr, stderr_part) != null);
}
fn runFixture(command: []const u8, text: []const u8, options: []const []const u8) !std.process.RunResult {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = text });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, command, path });
    // These fixtures assert the entry point's int result, which `run` now reports only on request.
    if (std.mem.startsWith(u8, command, "run")) try args.appendSlice(testing.allocator, &(.{"--print-result"} ++ tools));
    try args.appendSlice(testing.allocator, options);
    return std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
}

/// `runFixture` for a module-syntax entry. The public clock/random read surface
/// lives in the embedded `time`/`random` modules, so a capability program can
/// reach it only as a project entry whose declared module matches its file stem;
/// this writes `main.my` so `check`/`run` auto-route to the project loader.
fn runProjectFixture(command: []const u8, text: []const u8, options: []const []const u8) !std.process.RunResult {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = text });
    const path = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(path);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, command, path });
    if (std.mem.startsWith(u8, command, "run")) try args.appendSlice(testing.allocator, &(.{"--print-result"} ++ tools));
    try args.appendSlice(testing.allocator, options);
    return std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
}

fn invokeProject(command: []const u8, text: []const u8, expected_status: u8, expected_stdout: []const u8, stderr_part: []const u8) !void {
    return invokeProjectOptions(command, text, &.{}, expected_status, expected_stdout, stderr_part);
}

fn invokeProjectOptions(command: []const u8, text: []const u8, options: []const []const u8, expected_status: u8, expected_stdout: []const u8, stderr_part: []const u8) !void {
    const outcome = try runProjectFixture(command, text, options);
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    const wanted = if (std.mem.startsWith(u8, command, "run") and expected_status == 0) resultStatus(expected_stdout) else expected_status;
    try testing.expectEqual(std.process.Child.Term{ .exited = wanted }, outcome.term);
    try testing.expectEqualStrings(expected_stdout, outcome.stdout);
    if (stderr_part.len == 0) try testing.expectEqualStrings("", outcome.stderr) else try testing.expect(std.mem.indexOf(u8, outcome.stderr, stderr_part) != null);
}

/// `check` a project entry that imports the embedded `random` module. Its
/// private helpers declare the `mut` parameters they write, so the check must
/// succeed with no diagnostic at all.
fn checkProjectClean(text: []const u8) !void {
    const outcome = try runProjectFixture("check", text, &.{});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expectEqualStrings("", outcome.stdout);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "error[") == null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "host failure:") == null);
}

const C2Counts = struct { performed: usize, reused: usize };

fn c2NumberAfter(text: []const u8, field: []const u8) !usize {
    const marker = try std.fmt.allocPrint(testing.allocator, "\"{s}\":", .{field});
    defer testing.allocator.free(marker);
    const at = std.mem.indexOf(u8, text, marker) orelse return error.MissingCounter;
    var index = at + marker.len;
    while (index < text.len and !std.ascii.isDigit(text[index])) : (index += 1) {}
    const start = index;
    while (index < text.len and std.ascii.isDigit(text[index])) : (index += 1) {}
    if (start == index) return error.MissingCounter;
    return std.fmt.parseInt(usize, text[start..index], 10);
}

fn c2Counts(stderr: []const u8) !C2Counts {
    const section = std.mem.indexOf(u8, stderr, "\"checked_bodies\":") orelse return error.MissingCounter;
    const end = std.mem.indexOfPos(u8, stderr, section, "}") orelse stderr.len;
    return .{
        .performed = try c2NumberAfter(stderr[section..end], "performed"),
        .reused = try c2NumberAfter(stderr[section..end], "reused"),
    };
}

fn c2RunCheckReport(path: []const u8, cache_argument: []const u8, no_cache: bool) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "check", path, "--report" });
    if (cache_argument.len != 0) try args.append(testing.allocator, cache_argument);
    if (no_cache) try args.append(testing.allocator, "--no-cache");
    return std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
}

fn c2WarningLine(stderr: []const u8) ![]const u8 {
    var lines = std.mem.splitScalar(u8, stderr, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "warning[W_UNUSED_BINDING]") != null) return line;
    }
    return error.MissingWarning;
}

fn c2PathExists(path: []const u8) bool {
    var directory = std.Io.Dir.cwd().openDir(testing.io, path, .{}) catch return false;
    directory.close(testing.io);
    return true;
}

fn c2FirstSemanticFile(allocator: std.mem.Allocator, cache_base: []const u8) ![]u8 {
    const version_dir = try std.fs.path.join(allocator, &.{ cache_base, "semantic", "semantic-cache-v2" });
    defer allocator.free(version_dir);
    var directory = std.Io.Dir.cwd().openDir(testing.io, version_dir, .{ .iterate = true }) catch return error.MissingSemanticEntry;
    defer directory.close(testing.io);
    var contracts = directory.iterate();
    while (contracts.next(testing.io) catch return error.MissingSemanticEntry) |contract| {
        if (contract.kind != .directory) continue;
        const contract_dir = try std.fs.path.join(allocator, &.{ version_dir, contract.name });
        defer allocator.free(contract_dir);
        var entries = std.Io.Dir.cwd().openDir(testing.io, contract_dir, .{ .iterate = true }) catch continue;
        defer entries.close(testing.io);
        var files = entries.iterate();
        while (files.next(testing.io) catch return error.MissingSemanticEntry) |file| {
            if (file.kind != .file or std.mem.endsWith(u8, file.name, ".tmp")) continue;
            return std.fs.path.join(allocator, &.{ contract_dir, file.name });
        }
    }
    return error.MissingSemanticEntry;
}

fn c2SetFileLength(path: []const u8, length: u64) !void {
    const file = try std.Io.Dir.cwd().createFile(testing.io, path, .{ .truncate = false });
    defer file.close(testing.io);
    try file.setLength(testing.io, length);
}

fn c2FileLength(path: []const u8) !u64 {
    const stat = try std.Io.Dir.cwd().statFile(testing.io, path, .{});
    return stat.size;
}

// C2 is not yet registered in SPEC.md; this block is the regression evidence for
// ordinary checked-body persistence and must be reported with its SPEC patch.
// spec: SEMANTIC-CACHE-8
test "C2 ordinary body reuse crosses processes and relocates warnings" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(directory);
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.my" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    const seed =
        \\def helper(n: i64) -> i64:
        \\    return n + 1
        \\
        \\
        \\def keep(n: i64) -> i64:
        \\    unused = 3
        \\    return n + 1
        \\
        \\
        \\def main() -> i64:
        \\    return keep(helper(40))
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = seed });
    const first = try c2RunCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    const seeded = try c2Counts(first.stderr);
    try testing.expectEqual(@as(usize, 3), seeded.performed);
    try testing.expectEqual(@as(usize, 0), seeded.reused);

    const edited =
        \\def helper(n: i64) -> i64:
        \\    return n + 2
        \\
        \\
        \\type Marker = i64
        \\
        \\
        \\def keep(n: i64) -> i64:
        \\    unused = 3
        \\    return n + 1
        \\
        \\
        \\def main() -> i64:
        \\    return keep(helper(40))
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = edited });
    const second = try c2RunCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(second.stdout);
    defer testing.allocator.free(second.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, second.term);
    const changed = try c2Counts(second.stderr);
    try testing.expectEqual(@as(usize, 1), changed.performed);
    try testing.expectEqual(@as(usize, 2), changed.reused);

    const cold = try c2RunCheckReport(entry, cache_argument, true);
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cold.term);
    const uncached = try c2Counts(cold.stderr);
    try testing.expectEqual(@as(usize, 3), uncached.performed);
    try testing.expectEqual(@as(usize, 0), uncached.reused);
    try testing.expectEqualStrings(try c2WarningLine(second.stderr), try c2WarningLine(cold.stderr));

    const third = try c2RunCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(third.stdout);
    defer testing.allocator.free(third.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, third.term);
    const unchanged = try c2Counts(third.stderr);
    try testing.expectEqual(@as(usize, 0), unchanged.performed);
    try testing.expectEqual(@as(usize, 3), unchanged.reused);

    const no_cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "nocache" });
    defer testing.allocator.free(no_cache_base);
    const no_cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{no_cache_base});
    defer testing.allocator.free(no_cache_argument);
    const disabled = try c2RunCheckReport(entry, no_cache_argument, true);
    defer testing.allocator.free(disabled.stdout);
    defer testing.allocator.free(disabled.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, disabled.term);
    const no_reuse = try c2Counts(disabled.stderr);
    try testing.expectEqual(@as(usize, 3), no_reuse.performed);
    try testing.expectEqual(@as(usize, 0), no_reuse.reused);
    try testing.expect(!c2PathExists(no_cache_base));
}

test "C2 damaged truncated oversized and foreign-version entries fall back fresh" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(directory);
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.my" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    const source =
        \\def main() -> i64:
        \\    return 42
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = source });
    const seed = try c2RunCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(seed.stdout);
    defer testing.allocator.free(seed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, seed.term);
    try testing.expectEqual(@as(usize, 0), (try c2Counts(seed.stderr)).reused);
    const semantic_file = try c2FirstSemanticFile(testing.allocator, cache_base);
    defer testing.allocator.free(semantic_file);

    const original_len = try c2FileLength(semantic_file);
    try c2SetFileLength(semantic_file, original_len / 2);
    const truncated = try c2RunCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(truncated.stdout);
    defer testing.allocator.free(truncated.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, truncated.term);
    try testing.expectEqual(@as(usize, 0), (try c2Counts(truncated.stderr)).reused);

    try c2SetFileLength(semantic_file, 70 * 1024 * 1024);
    const oversized = try c2RunCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(oversized.stdout);
    defer testing.allocator.free(oversized.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, oversized.term);
    try testing.expectEqual(@as(usize, 0), (try c2Counts(oversized.stderr)).reused);

    const version_bytes = try std.Io.Dir.cwd().readFileAlloc(testing.io, semantic_file, testing.allocator, .limited(1024 * 1024));
    defer testing.allocator.free(version_bytes);
    version_bytes[12] ^= 0x20;
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = semantic_file, .data = version_bytes });
    const foreign = try c2RunCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(foreign.stdout);
    defer testing.allocator.free(foreign.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, foreign.term);
    try testing.expectEqual(@as(usize, 0), (try c2Counts(foreign.stderr)).reused);

    const damaged_bytes = try std.Io.Dir.cwd().readFileAlloc(testing.io, semantic_file, testing.allocator, .limited(1024 * 1024));
    defer testing.allocator.free(damaged_bytes);
    damaged_bytes[damaged_bytes.len - 12] ^= 0x01;
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = semantic_file, .data = damaged_bytes });
    const damaged = try c2RunCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(damaged.stdout);
    defer testing.allocator.free(damaged.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, damaged.term);
    try testing.expectEqual(@as(usize, 0), (try c2Counts(damaged.stderr)).reused);
}

test "C2 concurrent publishers never expose a partial entry" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(directory);
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.my" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    const source =
        \\def helper(n: i64) -> i64:
        \\    return n + 1
        \\def main() -> i64:
        \\    return helper(41)
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = source });
    const argv = [_][]const u8{ compiler_path, "check", entry, cache_argument };
    var first = try std.process.spawn(testing.io, .{ .argv = &argv, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore });
    var second = try std.process.spawn(testing.io, .{ .argv = &argv, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try first.wait(testing.io));
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try second.wait(testing.io));
    const warm = try c2RunCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(warm.stdout);
    defer testing.allocator.free(warm.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, warm.term);
    const counts = try c2Counts(warm.stderr);
    try testing.expectEqual(@as(usize, 0), counts.performed);
    try testing.expectEqual(@as(usize, 2), counts.reused);
}

/// Write a ladder-shaped project into `directory`: `modules` modules in an
/// import chain, each declaring a record and `functions` functions whose bodies
/// build a `list[int]` (a collection type that first appears inside bodies),
/// fold it through the record and call the same function of the previous
/// module. `constant` is the edited literal in `m1.f1_0`; `m0.f0_0` carries an
/// unused binding so a warning has to survive every check.
fn writeLadder(directory: std.Io.Dir, modules: usize, functions: usize, constant: usize) !void {
    var module: usize = 0;
    while (module < modules) : (module += 1) {
        var text: std.Io.Writer.Allocating = .init(testing.allocator);
        defer text.deinit();
        const out = &text.writer;
        try out.print("module m{d}\n", .{module});
        if (module > 0) try out.print("import m{d}\n", .{module - 1});
        try out.print("\n\npublic record Acc{d}:\n    total: int\n    count: int\n", .{module});
        var function: usize = 0;
        while (function < functions) : (function += 1) {
            const offset = if (module == 1 and function == 0) constant else module;
            try out.print("\n\npublic def f{d}_{d}(n: int) -> int:\n    xs: list[int] = []\n    for k in range(n):\n        xs.append(k * {d} + {d})\n", .{ module, function, function + 1, offset });
            if (module == 0 and function == 0) try out.writeAll("    spare = 1\n");
            try out.print("    acc = Acc{d}(total=0, count=0)\n    for x in xs:\n        acc = Acc{d}(total=acc.total + x, count=acc.count + 1)\n", .{ module, module });
            if (module > 0) try out.print("    return acc.total + m{d}.f{d}_{d}(n - 1)\n", .{ module - 1, module - 1, function }) else try out.writeAll("    return acc.total\n");
        }
        const name = try std.fmt.allocPrint(testing.allocator, "m{d}.my", .{module});
        defer testing.allocator.free(name);
        try directory.writeFile(testing.io, .{ .sub_path = name, .data = text.written() });
    }
    var main_text: std.Io.Writer.Allocating = .init(testing.allocator);
    defer main_text.deinit();
    try main_text.writer.print("module main\nimport m{d}\n\n\ndef main() -> int:\n    total = 0\n", .{modules - 1});
    var function: usize = 0;
    while (function < functions) : (function += 1) try main_text.writer.print("    total += m{d}.f{d}_{d}(5)\n", .{ modules - 1, modules - 1, function });
    try main_text.writer.writeAll("    return total - total\n");
    try directory.writeFile(testing.io, .{ .sub_path = "main.my", .data = main_text.written() });
}

/// `stderr` without the JSON report lines `--report` adds.
fn diagnosticLines(allocator: std.mem.Allocator, stderr: []const u8) ![]u8 {
    var kept: std.Io.Writer.Allocating = .init(allocator);
    defer kept.deinit();
    var lines = std.mem.splitScalar(u8, stderr, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "{")) continue;
        try kept.writer.print("{s}\n", .{line});
    }
    return kept.toOwnedSlice();
}

/// `check <entry> --report` with the given cache argument under `environment`.
fn checkReportWith(environment: *const std.process.Environ.Map, entry: []const u8, cache_argument: []const u8) !std.process.RunResult {
    return std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check", entry, "--report", cache_argument }, .environ_map = environment });
}

// The deterministic ratchet for the check-at-scale lane: a project whose
// checked trees do not fit the semantic retention budget (pinned small here,
// as a 50k-line project's are at the default) re-checked every body the
// budget dropped. Summaries do not depend on that budget.
// spec-case: CHECK-SUMMARY-1
test "check after a one-body edit re-checks only that body when retention cannot hold the project" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(directory);
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.my" });
    defer testing.allocator.free(entry);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{directory});
    defer testing.allocator.free(cache_argument);
    var environment = try std.process.Environ.createMap(testing.environ, testing.allocator);
    defer environment.deinit();
    try environment.put("MYLANG_SEMANTIC_BUDGET", "65536");
    try writeLadder(temporary.dir, 4, 6, 1);
    const seed = try checkReportWith(&environment, entry, cache_argument);
    defer testing.allocator.free(seed.stdout);
    defer testing.allocator.free(seed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, seed.term);
    try testing.expectEqual(@as(usize, 25), (try c2Counts(seed.stderr)).performed);

    try writeLadder(temporary.dir, 4, 6, 7);
    const edited = try checkReportWith(&environment, entry, cache_argument);
    defer testing.allocator.free(edited.stdout);
    defer testing.allocator.free(edited.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, edited.term);
    // The edited body and the entry point; the other 23 bodies stand in.
    const counts = try c2Counts(edited.stderr);
    try testing.expectEqual(@as(usize, 2), counts.performed);
    try testing.expectEqual(@as(usize, 23), counts.reused);

    const cold = try c2RunCheckReport(entry, cache_argument, true);
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cold.term);
    const warm_diagnostics = try diagnosticLines(testing.allocator, edited.stderr);
    defer testing.allocator.free(warm_diagnostics);
    const cold_diagnostics = try diagnosticLines(testing.allocator, cold.stderr);
    defer testing.allocator.free(cold_diagnostics);
    try testing.expect(std.mem.indexOf(u8, warm_diagnostics, "W_UNUSED_BINDING") != null);
    try testing.expectEqualStrings(cold_diagnostics, warm_diagnostics);
}

// The coordinator's false-clean: `user.first` reaches `shapes.Inner` only
// through `Outer.items`'s element type. Renaming `Inner.x` used to leave the
// cached check green while a cold check rejected the program.
// spec-case: SEMANTIC-KEY-TRANSITIVE-1
test "a cached check sees a field renamed in a record reached only through a list element" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(directory);
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.my" });
    defer testing.allocator.free(entry);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{directory});
    defer testing.allocator.free(cache_argument);
    const shapes = "module shapes\npublic class Inner:\n    x: int\npublic class Outer:\n    items: list[Inner]\npublic def make() -> Outer:\n    items: list[Inner] = []\n    items.append(Inner(x=1))\n    return Outer(items=items)\n";
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "shapes.my", .data = shapes });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "user.my", .data = "module user\nimport shapes\npublic def first(o: shapes.Outer) -> int:\n    v = o.items[0]\n    return v.x\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = "module main\nimport shapes\nimport user\ndef main() -> int:\n    return user.first(shapes.make())\n" });
    const seed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check", entry, cache_argument } });
    defer testing.allocator.free(seed.stdout);
    defer testing.allocator.free(seed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, seed.term);
    const renamed = "module shapes\npublic class Inner:\n    y: int\npublic class Outer:\n    items: list[Inner]\npublic def make() -> Outer:\n    items: list[Inner] = []\n    items.append(Inner(y=1))\n    return Outer(items=items)\n";
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "shapes.my", .data = renamed });
    const cached = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check", entry, cache_argument } });
    defer testing.allocator.free(cached.stdout);
    defer testing.allocator.free(cached.stderr);
    const cold = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check", entry, "--no-cache" } });
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, cold.term);
    try testing.expect(std.mem.indexOf(u8, cold.stderr, "user.my:5:14: error[E_UNKNOWN_FIELD]") != null);
    try testing.expectEqual(cold.term, cached.term);
    try testing.expectEqualStrings(cold.stderr, cached.stderr);
}

const SymbolicCounts = struct { performed: usize, reused: usize };

fn symbolicCounts(stderr: []const u8) !SymbolicCounts {
    const marker = std.mem.indexOf(u8, stderr, "\"symbolic_templates\":") orelse return error.MissingCounter;
    const end = std.mem.indexOfPos(u8, stderr, marker, "}") orelse stderr.len;
    return .{
        .performed = try c2NumberAfter(stderr[marker..end], "performed"),
        .reused = try c2NumberAfter(stderr[marker..end], "reused"),
    };
}

fn symbolicCheck(entry: []const u8, cache_argument: []const u8, no_cache: bool) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "check", entry, "--report" });
    if (cache_argument.len != 0) try args.append(testing.allocator, cache_argument);
    if (no_cache) try args.append(testing.allocator, "--no-cache");
    return std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
}

// C3 top-level SPEC registration is outstanding; this test is the fresh-process
// evidence for the symbolic-template half and must be reported with its patch.
// spec-case: SEMANTIC-CACHE-7
test "C3 symbolic template reuse crosses processes and preserves selective invalidation" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(directory);
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.my" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    const base_template =
        \\def size[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 7
        \\
        \\
        \\
    ;
    const edited_template =
        \\def size[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 8
        \\
        \\
        \\
    ;
    const base_helper =
        \\def helper(n: i64) -> i64:
        \\    return n + 1
        \\
        \\
        \\
    ;
    const edited_helper =
        \\def helper(n: i64) -> i64:
        \\    return n + 2
        \\
        \\
        \\
    ;
    const main_fn =
        \\def main() -> i64:
        \\    return size[u8](1u8) + helper(0)
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = base_template ++ base_helper ++ main_fn });
    // Cold process: one abstract template check, no reuse.
    const first = try symbolicCheck(entry, cache_argument, false);
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    try testing.expectEqual(@as(usize, 1), (try symbolicCounts(first.stderr)).performed);
    try testing.expectEqual(@as(usize, 0), (try symbolicCounts(first.stderr)).reused);
    // Fresh process, unchanged source: the template is replayed.
    const warm = try symbolicCheck(entry, cache_argument, false);
    defer testing.allocator.free(warm.stdout);
    defer testing.allocator.free(warm.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, warm.term);
    try testing.expectEqual(@as(usize, 0), (try symbolicCounts(warm.stderr)).performed);
    try testing.expectEqual(@as(usize, 1), (try symbolicCounts(warm.stderr)).reused);
    // Editing an unrelated ordinary body must not disturb template reuse.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = base_template ++ edited_helper ++ main_fn });
    const unrelated = try symbolicCheck(entry, cache_argument, false);
    defer testing.allocator.free(unrelated.stdout);
    defer testing.allocator.free(unrelated.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, unrelated.term);
    try testing.expectEqual(@as(usize, 0), (try symbolicCounts(unrelated.stderr)).performed);
    try testing.expectEqual(@as(usize, 1), (try symbolicCounts(unrelated.stderr)).reused);
    // Editing the template body invalidates its retained direct result.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = edited_template ++ edited_helper ++ main_fn });
    const edited = try symbolicCheck(entry, cache_argument, false);
    defer testing.allocator.free(edited.stdout);
    defer testing.allocator.free(edited.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, edited.term);
    try testing.expectEqual(@as(usize, 1), (try symbolicCounts(edited.stderr)).performed);
    try testing.expectEqual(@as(usize, 0), (try symbolicCounts(edited.stderr)).reused);
    // Disabling the cache must not change acceptance and must report fresh work.
    const disabled = try symbolicCheck(entry, cache_argument, true);
    defer testing.allocator.free(disabled.stdout);
    defer testing.allocator.free(disabled.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, disabled.term);
    try testing.expectEqual(@as(usize, 1), (try symbolicCounts(disabled.stderr)).performed);
    try testing.expectEqual(@as(usize, 0), (try symbolicCounts(disabled.stderr)).reused);
}

// spec-case: CAPABILITY-3
test "run build --run and installed executables share the restricted capability diagnostic" {
    const program =
        \\def main(clock: Clock) -> int:
        \\    _ = clock
        \\    return 0
    ;
    const message = "mylang: --restrict is active and this command line did not grant a capability the entry point requests; pass --allow-clock, or drop --restrict to grant every capability\n";
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "cap.my", .data = program });
    const path = try temp.dir.realPathFileAlloc(testing.io, "cap.my", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "cap-bin" });
    defer testing.allocator.free(output);

    var run_argv: std.ArrayList([]const u8) = .empty;
    defer run_argv.deinit(testing.allocator);
    try run_argv.appendSlice(testing.allocator, &.{ compiler_path, "run", path, "--restrict" });
    try run_argv.appendSlice(testing.allocator, &tools);
    const run = try std.process.run(testing.allocator, testing.io, .{ .argv = run_argv.items });
    defer testing.allocator.free(run.stdout);
    defer testing.allocator.free(run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, run.term);
    try testing.expectEqualStrings("", run.stdout);
    try testing.expectEqualStrings(message, run.stderr);

    var build_argv: std.ArrayList([]const u8) = .empty;
    defer build_argv.deinit(testing.allocator);
    try build_argv.appendSlice(testing.allocator, &.{ compiler_path, "build", path, "--run", "--restrict" });
    try build_argv.appendSlice(testing.allocator, &tools);
    const build = try std.process.run(testing.allocator, testing.io, .{ .argv = build_argv.items });
    defer testing.allocator.free(build.stdout);
    defer testing.allocator.free(build.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, build.term);
    try testing.expectEqualStrings("", build.stdout);
    try testing.expectEqualStrings(message, build.stderr);

    var link_argv: std.ArrayList([]const u8) = .empty;
    defer link_argv.deinit(testing.allocator);
    try link_argv.appendSlice(testing.allocator, &.{ compiler_path, "build", path, "-o", output });
    try link_argv.appendSlice(testing.allocator, &tools);
    const link = try std.process.run(testing.allocator, testing.io, .{ .argv = link_argv.items });
    defer testing.allocator.free(link.stdout);
    defer testing.allocator.free(link.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, link.term);
    var restricted = try runtimeOptions("--restrict");
    defer restricted.deinit();
    const installed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{output}, .environ_map = &restricted });
    defer testing.allocator.free(installed.stdout);
    defer testing.allocator.free(installed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, installed.term);
    try testing.expectEqualStrings("", installed.stdout);
    try testing.expectEqualStrings(message, installed.stderr);
}

/// Build `program` with `-o` in `temp` and return the executable's path.
fn buildExecutable(temp: *testing.TmpDir, program: []const u8) ![]const u8 {
    try temp.dir.writeFile(testing.io, .{ .sub_path = "argv.my", .data = program });
    const path = try temp.dir.realPathFileAlloc(testing.io, "argv.my", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "argv-bin" });
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    try expectConstantProcess(&.{ compiler_path, "build", path, "-o", output, "--cache-dir", cache, tools[0], tools[1] }, "");
    return output;
}

/// Run a built executable with `argv` under `MYLANG_OPTIONS=options`.
fn runExecutable(argv: []const []const u8, options: []const u8) !std.process.RunResult {
    var environment = try runtimeOptions(options);
    defer environment.deinit();
    return std.process.run(testing.allocator, testing.io, .{ .argv = argv, .environ_map = &environment });
}

const argv_echo =
    \\def main(args: list[str], out: Stream) -> int:
    \\    out.print("count", len(args))
    \\    for value in args:
    \\        out.print("[" + value + "]")
    \\    return 0
;

// spec: NATIVE-ARGV-1
test "a built executable hands main every argument and reads runtime options from MYLANG_OPTIONS" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const output = try buildExecutable(&temp, argv_echo);
    defer testing.allocator.free(output);
    // Every former runtime spelling, `--` included, is now the program's data.
    const verbatim = try runExecutable(&.{ output, "--gc-stress", "--print-result", "--max-steps=9", "--restrict", "--allow-list", "--", "x" }, "");
    defer testing.allocator.free(verbatim.stdout);
    defer testing.allocator.free(verbatim.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, verbatim.term);
    try testing.expectEqualStrings("count 7\n[--gc-stress]\n[--print-result]\n[--max-steps=9]\n[--restrict]\n[--allow-list]\n[--]\n[x]\n", verbatim.stdout);
    try testing.expectEqualStrings("", verbatim.stderr);
    // The runtime reads its options from the environment, quoted or bare.
    const optioned = try runExecutable(&.{ output, "--" }, "--gc-stress \"--print-result\"");
    defer testing.allocator.free(optioned.stdout);
    defer testing.allocator.free(optioned.stderr);
    try testing.expectEqualStrings("count 1\n[--]\n0\n", optioned.stdout);
    try testing.expectEqualStrings("", optioned.stderr);
    // An option the runtime does not know is refused before the guest runs.
    const unknown = try runExecutable(&.{output}, "--engine=vm");
    defer testing.allocator.free(unknown.stdout);
    defer testing.allocator.free(unknown.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, unknown.term);
    try testing.expectEqualStrings("", unknown.stdout);
    try testing.expectEqualStrings("mylang: MYLANG_OPTIONS names --engine=vm, which is not a runtime option\n", unknown.stderr);
    const unterminated = try runExecutable(&.{output}, "\"--print-result");
    defer testing.allocator.free(unterminated.stdout);
    defer testing.allocator.free(unterminated.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, unterminated.term);
    try testing.expectEqualStrings("mylang: MYLANG_OPTIONS has an unterminated quote\n", unterminated.stderr);
}

// spec-case: NATIVE-ARGV-1
test "run replaces an inherited MYLANG_OPTIONS with its own command line" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "argv.my", .data = argv_echo });
    const path = try temp.dir.realPathFileAlloc(testing.io, "argv.my", testing.allocator);
    defer testing.allocator.free(path);
    const inherited = try runExecutable(&.{ compiler_path, "run", path, tools[0], tools[1], "--", "--gc-stress" }, "--print-result");
    defer testing.allocator.free(inherited.stdout);
    defer testing.allocator.free(inherited.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, inherited.term);
    try testing.expectEqualStrings("count 1\n[--gc-stress]\n", inherited.stdout);
    try testing.expectEqualStrings("", inherited.stderr);
}

// spec: RESULT-MAIN-1
test "CLI maps Result main ok and err to status codes and one diagnostic" {
    const ok =
        \\def main(args: list[str]) -> Result[int, str]:
        \\    if len(args) == 0:
        \\        return Err("missing name")
        \\    return Ok(7)
    ;
    const accepted = try runFixture("run", ok, &.{ "--", "x" });
    defer testing.allocator.free(accepted.stdout);
    defer testing.allocator.free(accepted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 7 }, accepted.term);
    try testing.expectEqualStrings("7\n", accepted.stdout);
    try testing.expectEqualStrings("", accepted.stderr);

    const rejected = try runFixture("run", ok, &.{});
    defer testing.allocator.free(rejected.stdout);
    defer testing.allocator.free(rejected.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, rejected.term);
    try testing.expectEqualStrings("1\n", rejected.stdout);
    try testing.expectEqualStrings("missing name\n", rejected.stderr);

    const wrapped =
        \\def main() -> Result[int, str]:
        \\    return Ok(300)
    ;
    const status = try runFixture("run", wrapped, &.{});
    defer testing.allocator.free(status.stdout);
    defer testing.allocator.free(status.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 44 }, status.term);
    try testing.expectEqualStrings("300\n", status.stdout);
    try testing.expectEqualStrings("", status.stderr);
}

// spec: EPRINT-1
test "CLI separates eprint stderr from print stdout byte-exactly" {
    const program =
        \\def main(out: Stream, err: Stream) -> int:
        \\    out.print("out", 1)
        \\    err.print("err", 7, sep="-", end="!\n")
        \\    err.print()
        \\    return 0
    ;
    const outcome = try runFixture("run", program, &.{});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expectEqualStrings("out 1\n0\n", outcome.stdout);
    try testing.expectEqualStrings("err-7!\n\n", outcome.stderr);
}

// spec-case: ARGV-1
test "CLI forwards guest arguments after -- for run and build --run" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const program =
        \\def main(args: list[str], out: Stream) -> int:
        \\    out.print("count", len(args))
        \\    for value in args:
        \\        out.print("[" + value + "]")
        \\    return 0
    ;
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = program });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const guest = [_][]const u8{ "", "héllo wörld", "two words", "--print-result", "--max-steps=9" };
    const expected = "count 5\n[]\n[héllo wörld]\n[two words]\n[--print-result]\n[--max-steps=9]\n";

    var run_argv: std.ArrayList([]const u8) = .empty;
    defer run_argv.deinit(testing.allocator);
    try run_argv.appendSlice(testing.allocator, &.{ compiler_path, "run", path, "--print-result" });
    try run_argv.appendSlice(testing.allocator, &tools);
    try run_argv.append(testing.allocator, "--");
    try run_argv.appendSlice(testing.allocator, &guest);
    const run = try std.process.run(testing.allocator, testing.io, .{ .argv = run_argv.items });
    defer testing.allocator.free(run.stdout);
    defer testing.allocator.free(run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run.term);
    try testing.expectEqualStrings(expected ++ "0\n", run.stdout);
    try testing.expectEqualStrings("", run.stderr);

    var stress_run_argv: std.ArrayList([]const u8) = .empty;
    defer stress_run_argv.deinit(testing.allocator);
    try stress_run_argv.appendSlice(testing.allocator, &.{ compiler_path, "run", path, "--print-result", "--gc-stress" });
    try stress_run_argv.appendSlice(testing.allocator, &tools);
    try stress_run_argv.append(testing.allocator, "--");
    try stress_run_argv.appendSlice(testing.allocator, &guest);
    const stress_run = try std.process.run(testing.allocator, testing.io, .{ .argv = stress_run_argv.items });
    defer testing.allocator.free(stress_run.stdout);
    defer testing.allocator.free(stress_run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, stress_run.term);
    try testing.expectEqualStrings(expected ++ "0\n", stress_run.stdout);
    try testing.expectEqualStrings("", stress_run.stderr);

    var empty_run_argv: std.ArrayList([]const u8) = .empty;
    defer empty_run_argv.deinit(testing.allocator);
    try empty_run_argv.appendSlice(testing.allocator, &.{ compiler_path, "run", path, "--print-result" });
    try empty_run_argv.appendSlice(testing.allocator, &tools);
    const empty_run = try std.process.run(testing.allocator, testing.io, .{ .argv = empty_run_argv.items });
    defer testing.allocator.free(empty_run.stdout);
    defer testing.allocator.free(empty_run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, empty_run.term);
    try testing.expectEqualStrings("count 0\n0\n", empty_run.stdout);
    try testing.expectEqualStrings("", empty_run.stderr);

    var invalid_run_argv: std.ArrayList([]const u8) = .empty;
    defer invalid_run_argv.deinit(testing.allocator);
    try invalid_run_argv.appendSlice(testing.allocator, &.{ compiler_path, "run", path, "--print-result" });
    try invalid_run_argv.appendSlice(testing.allocator, &tools);
    try invalid_run_argv.appendSlice(testing.allocator, &.{ "--", "\xff" });
    const invalid_run = try std.process.run(testing.allocator, testing.io, .{ .argv = invalid_run_argv.items });
    defer testing.allocator.free(invalid_run.stdout);
    defer testing.allocator.free(invalid_run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, invalid_run.term);
    try testing.expectEqualStrings("", invalid_run.stdout);
    try testing.expect(std.mem.indexOf(u8, invalid_run.stderr, "not valid UTF-8") != null);

    var build_argv: std.ArrayList([]const u8) = .empty;
    defer build_argv.deinit(testing.allocator);
    try build_argv.appendSlice(testing.allocator, &.{ compiler_path, "build", path, "--run" });
    try build_argv.appendSlice(testing.allocator, &tools);
    try build_argv.append(testing.allocator, "--");
    try build_argv.appendSlice(testing.allocator, &guest);
    const build = try std.process.run(testing.allocator, testing.io, .{ .argv = build_argv.items });
    defer testing.allocator.free(build.stdout);
    defer testing.allocator.free(build.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, build.term);
    try testing.expectEqualStrings(expected, build.stdout);
    try testing.expectEqualStrings("", build.stderr);

    var empty_build_argv: std.ArrayList([]const u8) = .empty;
    defer empty_build_argv.deinit(testing.allocator);
    try empty_build_argv.appendSlice(testing.allocator, &.{ compiler_path, "build", path, "--run" });
    try empty_build_argv.appendSlice(testing.allocator, &tools);
    const empty_build = try std.process.run(testing.allocator, testing.io, .{ .argv = empty_build_argv.items });
    defer testing.allocator.free(empty_build.stdout);
    defer testing.allocator.free(empty_build.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, empty_build.term);
    try testing.expectEqualStrings("count 0\n", empty_build.stdout);
    try testing.expectEqualStrings("", empty_build.stderr);
}

// spec-case: ARGV-1
test "build --run detects module projects and installed binaries receive the same argv" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDir(testing.io, "app", .default_dir);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/main.my", .data =
        \\module main
        \\import helper
        \\
        \\def main(args: list[str], out: Stream) -> int:
        \\    out.print(helper.render(args))
        \\    return 0
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.my", .data =
        \\module helper
        \\
        \\
        \\public def render(args: list[str]) -> str:
        \\    out = ""
        \\    for value in args:
        \\        out = out + "[" + value + "]"
        \\    return out
    });
    const entry = try temp.dir.realPathFileAlloc(testing.io, "app/main.my", testing.allocator);
    defer testing.allocator.free(entry);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "program" });
    defer testing.allocator.free(output);
    const guest = [_][]const u8{ "", "héllo wörld", "two words", "--print-result" };
    const expected = "[][héllo wörld][two words][--print-result]\n";

    var run_argv: std.ArrayList([]const u8) = .empty;
    defer run_argv.deinit(testing.allocator);
    try run_argv.appendSlice(testing.allocator, &.{ compiler_path, "build", entry, "--run" });
    try run_argv.appendSlice(testing.allocator, &tools);
    try run_argv.append(testing.allocator, "--");
    try run_argv.appendSlice(testing.allocator, &guest);
    const run = try std.process.run(testing.allocator, testing.io, .{ .argv = run_argv.items });
    defer testing.allocator.free(run.stdout);
    defer testing.allocator.free(run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run.term);
    try testing.expectEqualStrings(expected, run.stdout);
    try testing.expectEqualStrings("", run.stderr);

    var link_argv: std.ArrayList([]const u8) = .empty;
    defer link_argv.deinit(testing.allocator);
    try link_argv.appendSlice(testing.allocator, &.{ compiler_path, "build", entry, "--project", "-o", output });
    try link_argv.appendSlice(testing.allocator, &tools);
    const link = try std.process.run(testing.allocator, testing.io, .{ .argv = link_argv.items });
    defer testing.allocator.free(link.stdout);
    defer testing.allocator.free(link.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, link.term);
    try testing.expectEqualStrings("", link.stderr);

    var install_argv: std.ArrayList([]const u8) = .empty;
    defer install_argv.deinit(testing.allocator);
    // An installed executable reads no option from its arguments: every value,
    // flag-looking or not, is the guest's without a `--`.
    try install_argv.append(testing.allocator, output);
    try install_argv.appendSlice(testing.allocator, &guest);
    const installed = try std.process.run(testing.allocator, testing.io, .{ .argv = install_argv.items });
    defer testing.allocator.free(installed.stdout);
    defer testing.allocator.free(installed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, installed.term);
    try testing.expectEqualStrings(expected, installed.stdout);
    try testing.expectEqualStrings("", installed.stderr);

    var installed_stress_argv: std.ArrayList([]const u8) = .empty;
    defer installed_stress_argv.deinit(testing.allocator);
    try installed_stress_argv.append(testing.allocator, output);
    try installed_stress_argv.appendSlice(testing.allocator, &guest);
    var stressed = try runtimeOptions("--gc-stress");
    defer stressed.deinit();
    const installed_stress = try std.process.run(testing.allocator, testing.io, .{ .argv = installed_stress_argv.items, .environ_map = &stressed });
    defer testing.allocator.free(installed_stress.stdout);
    defer testing.allocator.free(installed_stress.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, installed_stress.term);
    try testing.expectEqualStrings(expected, installed_stress.stdout);
    try testing.expectEqualStrings("", installed_stress.stderr);

    var installed_empty_argv: std.ArrayList([]const u8) = .empty;
    defer installed_empty_argv.deinit(testing.allocator);
    try installed_empty_argv.append(testing.allocator, output);
    const installed_empty = try std.process.run(testing.allocator, testing.io, .{ .argv = installed_empty_argv.items });
    defer testing.allocator.free(installed_empty.stdout);
    defer testing.allocator.free(installed_empty.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, installed_empty.term);
    try testing.expectEqualStrings("\n", installed_empty.stdout);
    try testing.expectEqualStrings("", installed_empty.stderr);

    var installed_invalid_argv: std.ArrayList([]const u8) = .empty;
    defer installed_invalid_argv.deinit(testing.allocator);
    try installed_invalid_argv.appendSlice(testing.allocator, &.{ output, "\xff" });
    const installed_invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = installed_invalid_argv.items });
    defer testing.allocator.free(installed_invalid.stdout);
    defer testing.allocator.free(installed_invalid.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, installed_invalid.term);
    try testing.expectEqualStrings("", installed_invalid.stdout);
    try testing.expect(std.mem.indexOf(u8, installed_invalid.stderr, "not valid UTF-8") != null);
}

/// Give a hand-built child environment the parent's Zig global cache.
///
/// Zig resolves that cache from `ZIG_GLOBAL_CACHE_DIR`, else `$XDG_CACHE_HOME/zig`,
/// else `$HOME/.cache/zig`. These tests redirect `HOME` into a temp directory so a
/// child compiler never touches the shared runtime root under `~/.cache/mylang`,
/// but the redirect also hides Zig's cache, so every child `zig cc` rebuilds
/// compiler-rt from empty — seconds per invocation. Naming the parent's cache
/// explicitly keeps the `HOME` isolation and still starts the child warm.
fn forwardZigCache(environment: *std.process.Environ.Map) !void {
    if (testing.environ.getPosix("ZIG_GLOBAL_CACHE_DIR")) |explicit| {
        if (explicit.len != 0) return environment.put("ZIG_GLOBAL_CACHE_DIR", explicit);
    }
    if (testing.environ.getPosix("XDG_CACHE_HOME")) |cache_home| {
        if (cache_home.len != 0) return putJoined(environment, &.{ cache_home, "zig" });
    }
    if (testing.environ.getPosix("HOME")) |home| {
        if (home.len != 0) return putJoined(environment, &.{ home, ".cache", "zig" });
    }
}

/// Join `parts` into one path and store it as the child's Zig global cache.
fn putJoined(environment: *std.process.Environ.Map, parts: []const []const u8) !void {
    const resolved = try std.fs.path.join(testing.allocator, parts);
    defer testing.allocator.free(resolved);
    try environment.put("ZIG_GLOBAL_CACHE_DIR", resolved);
}

fn spawnWithEnv(argv: []const []const u8, env_map: *const std.process.Environ.Map) !std.process.RunResult {
    return std.process.run(testing.allocator, testing.io, .{ .argv = argv, .environ_map = env_map });
}

/// The entry of the empty-`PATH` project: it imports a module, prints through
/// its stream and carries a test, so `build`, `run` and `test` all have work.
const empty_path_main =
    \\module main
    \\import text.words
    \\
    \\def main(out: Stream) -> int:
    \\    n = words.count_words("the quick brown fox")
    \\    out.print(f"words: {n}")
    \\    return 0
    \\
    \\
    \\public def test_main_words() -> bool:
    \\    return words.count_words("one two") == 2
    \\
;
/// The imported module of the empty-`PATH` project, with a test of its own.
const empty_path_words =
    \\module text.words
    \\
    \\public def count_words(line: str) -> int:
    \\    total = 0
    \\    for part in line.split(" "):
    \\        if len(part) > 0:
    \\            total = total + 1
    \\    return total
    \\
    \\
    \\public def test_count_words() -> bool:
    \\    return count_words("a bb  ccc") == 3 and count_words("") == 0
    \\
;

/// A child environment whose `PATH` names only an empty directory under `root`,
/// with `HOME` and `TMPDIR` inside the fixture and Zig's global cache forwarded.
/// A command that reached for `python3`, or for any program it was not handed
/// by `--zig`/`--qbe`, cannot start it here.
fn emptyPathEnvironment(root: []const u8) !std.process.Environ.Map {
    var environment: std.process.Environ.Map = .init(testing.allocator);
    errdefer environment.deinit();
    const bin = try std.fs.path.join(testing.allocator, &.{ root, "empty-bin" });
    defer testing.allocator.free(bin);
    try std.Io.Dir.cwd().createDirPath(testing.io, bin);
    try environment.put("PATH", bin);
    try environment.put("HOME", root);
    try environment.put("TMPDIR", root);
    try forwardZigCache(&environment);
    return environment;
}

/// Run one command under `environment`, requiring exit status 0 and
/// `stdout_part` somewhere in its standard output; a failure prints its stderr.
fn expectEmptyPathRun(argv: []const []const u8, environment: *const std.process.Environ.Map, stdout_part: []const u8) !void {
    const result = try spawnWithEnv(argv, environment);
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    errdefer std.debug.print("`{s}` under an empty PATH:\nstdout: {s}\nstderr: {s}\n", .{ argv[@min(1, argv.len - 1)], result.stdout, result.stderr });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, stdout_part) != null);
}

// spec: USE-WITHOUT-PYTHON-1
test "CLI user commands need no interpreter: check, build, run, test, fmt, docs, navigation and the release build under an empty PATH" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "main.my", empty_path_main);
    try writeProjectFile(&temporary, "text/words.my", empty_path_words);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.my" });
    defer testing.allocator.free(entry);
    const program = try std.fs.path.join(testing.allocator, &.{ root, "program" });
    defer testing.allocator.free(program);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);
    var environment = try emptyPathEnvironment(root);
    defer environment.deinit();
    try expectEmptyPathRun(&.{ compiler_path, "check", entry }, &environment, "");
    try expectEmptyPathRun(&.{ compiler_path, "build", entry, "-o", program, "--cache-dir", cache, tools[0], tools[1] }, &environment, "");
    try expectEmptyPathRun(&.{program}, &environment, "words: 4\n");
    try expectEmptyPathRun(&.{ compiler_path, "run", entry, cache_argument, tools[0], tools[1] }, &environment, "words: 4\n");
    try expectEmptyPathRun(&.{ compiler_path, "test", entry, cache_argument, tools[0], tools[1] }, &environment, "2 passed");
    try expectEmptyPathRun(&.{ compiler_path, "fmt-project", entry, "--check" }, &environment, "");
    try expectEmptyPathRun(&.{ compiler_path, "docs", "primer" }, &environment, "mylang");
    try expectEmptyPathRun(&.{ compiler_path, "index-project", entry }, &environment, "\"version\":\"navigation-summary-v1\"");
    try expectEmptyPathRun(&.{ compiler_path, "context", entry, "--symbol=text.words::count_words" }, &environment, "\"status\":\"ok\"");
    // The LLVM release path is built into the compiler (LLVM-ZIG-1): it runs no adapter.
    const release = try std.fs.path.join(testing.allocator, &.{ root, "program-release" });
    defer testing.allocator.free(release);
    try expectEmptyPathRun(&.{ compiler_path, "build", entry, "-o", release, "--release", "--cache-dir", cache, tools[1] }, &environment, "");
    try expectEmptyPathRun(&.{release}, &environment, "words: 4\n");
    try expectEmptyPathRun(&.{ compiler_path, "run", entry, "--release", cache_argument, tools[1] }, &environment, "words: 4\n");
}

/// The shared library every packages fixture locks.
const package_library = "module numbers\n\n\npublic def answer() -> int:\n    return 42\n";
/// An application entry that imports the locked library and returns its answer.
const package_application = "module main\nimport numbers\n\ndef main() -> int:\n    return numbers.answer()\n";

/// A temporary tree holding `library/numbers.my`, `packages.json` naming it, and
/// the absolute compiler, plus the environment every `mylang packages` call runs
/// under: an empty `PATH`, `HOME` and `TMPDIR` inside the tree, and the native
/// tools named the way `zig build` names them, since a staged build spawns this
/// compiler with no `--qbe`/`--zig` of its own.
const PackagesFixture = struct {
    temporary: testing.TmpDir,
    root: [:0]const u8,
    compiler: [:0]const u8,
    environment: std.process.Environ.Map,

    fn init() !PackagesFixture {
        var temporary = testing.tmpDir(.{});
        errdefer temporary.cleanup();
        try writeProjectFile(&temporary, "library/numbers.my", package_library);
        try writeProjectFile(&temporary, "packages.json", "{\"packages\":[{\"name\":\"numbers\",\"root\":\"library\"}]}");
        const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
        errdefer testing.allocator.free(root);
        var environment = try emptyPathEnvironment(root);
        errdefer environment.deinit();
        const qbe = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_options").qbe_path, testing.allocator);
        defer testing.allocator.free(qbe);
        try environment.put("MYLANG_QBE", qbe);
        try environment.put("MYLANG_ZIG", @import("test_options").zig_path);
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, testing.allocator);
        return .{ .temporary = temporary, .root = root, .compiler = compiler, .environment = environment };
    }

    fn deinit(self: *PackagesFixture) void {
        self.environment.deinit();
        testing.allocator.free(self.compiler);
        testing.allocator.free(self.root);
        self.temporary.cleanup();
    }

    /// Run `mylang packages ARGS` from the fixture root.
    fn run(self: *PackagesFixture, args: []const []const u8) !std.process.RunResult {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(testing.allocator);
        try argv.appendSlice(testing.allocator, &.{ self.compiler, "packages" });
        try argv.appendSlice(testing.allocator, args);
        return std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .path = self.root }, .environ_map = &self.environment });
    }

    /// Run `mylang packages ARGS` and require `status`, `stdout` exactly and
    /// `stderr_part` somewhere in standard error.
    fn expect(self: *PackagesFixture, args: []const []const u8, status: u8, stdout: []const u8, stderr_part: []const u8) !void {
        const result = try self.run(args);
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        errdefer std.debug.print("mylang packages {s}: stdout {s}\nstderr {s}\n", .{ args[0], result.stdout, result.stderr });
        try testing.expectEqual(std.process.Child.Term{ .exited = status }, result.term);
        try testing.expectEqualStrings(stdout, result.stdout);
        try testing.expect(std.mem.indexOf(u8, result.stderr, stderr_part) != null);
    }

    fn read(self: *PackagesFixture, path: []const u8) ![]u8 {
        return self.temporary.dir.readFileAlloc(testing.io, path, testing.allocator, .limited(1 << 20));
    }

    fn write(self: *PackagesFixture, path: []const u8, data: []const u8) !void {
        try writeProjectFile(&self.temporary, path, data);
    }
};

/// Build one application through the lock with `run-project`: the program's
/// answer is printed and is its exit status, the receipt names the lock, this
/// compiler and the dependency report, and the application directory still
/// holds only its entry.
fn expectPackagedApplication(fixture: *PackagesFixture, application: []const u8, identity: []const u8) !void {
    const entry = try std.fmt.allocPrint(testing.allocator, "{s}/main.my", .{application});
    defer testing.allocator.free(entry);
    try fixture.write(entry, package_application);
    try fixture.expect(&.{ "build", entry, "--lock", "lock.json", "--command", "run-project", "--receipt", "receipt.json" }, 42, "42\n", "");
    const receipt = try fixture.read("receipt.json");
    defer testing.allocator.free(receipt);
    try testing.expect(std.mem.indexOf(u8, receipt, "\"version\": \"package-build-v1\"") != null);
    try testing.expect(std.mem.indexOf(u8, receipt, "\"lock_sha256\": \"") != null);
    try testing.expect(std.mem.indexOf(u8, receipt, identity) != null);
    try testing.expect(std.mem.indexOf(u8, receipt, "\"version\": \"project-dependencies-v1\"") != null);
    const directory = try std.fs.path.join(testing.allocator, &.{ fixture.root, application });
    defer testing.allocator.free(directory);
    const entries = try scratchEntries(directory);
    defer testing.allocator.free(entries);
    try testing.expectEqualStrings("main.my", entries);
}

/// This compiler's `compiler_sha256`, as `--features` reports it.
fn featureIdentity(compiler: []const u8) ![]u8 {
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler, "--features" } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    const marker = "\"compiler_sha256\":\"";
    const start = (std.mem.indexOf(u8, result.stdout, marker) orelse return error.TestUnexpectedResult) + marker.len;
    return testing.allocator.dupe(u8, result.stdout[start .. start + 64]);
}

// spec: PACKAGES-BUILD-1
test "mylang packages builds two applications from one locked library without writing either tree" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    const identity = try featureIdentity(fixture.compiler);
    defer testing.allocator.free(identity);
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const frozen = try fixture.read("lock.json");
    defer testing.allocator.free(frozen);
    try expectPackagedApplication(&fixture, "app1", identity);
    try expectPackagedApplication(&fixture, "app2", identity);
    // The default command only checks, and prints nothing on success.
    try fixture.expect(&.{ "build", "app1/main.my", "--lock=lock.json" }, 0, "", "");
    const after = try fixture.read("lock.json");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(frozen, after);
    // Every staging directory under TMPDIR (the fixture root) was removed.
    const entries = try scratchEntries(fixture.root);
    defer testing.allocator.free(entries);
    try testing.expect(std.mem.indexOf(u8, entries, "mylang-packages-") == null);
}

/// The lock with its one package listed twice, as two versions of one namespace would be.
fn doubledLock(fixture: *PackagesFixture, frozen: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, frozen, .{});
    defer parsed.deinit();
    const packages = &parsed.value.object.getPtr("packages").?.array;
    try packages.append(packages.items[0]);
    const doubled = try std.json.Stringify.valueAlloc(testing.allocator, parsed.value, .{});
    defer testing.allocator.free(doubled);
    try fixture.write("lock.json", doubled);
}

// spec-case: PACKAGES-BUILD-1
test "mylang packages refuses drift, shared paths, doubled namespaces, standard names and symbolic links before compiling" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.write("app1/main.my", package_application);
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const frozen = try fixture.read("lock.json");
    defer testing.allocator.free(frozen);
    try fixture.expect(&.{ "build", "app1/main.my", "--lock", "lock.json", "--receipt", "receipt.json" }, 0, "", "");
    const receipt = try fixture.read("receipt.json");
    defer testing.allocator.free(receipt);
    const build_args = [_][]const u8{ "build", "app1/main.my", "--lock", "lock.json", "--receipt", "receipt.json" };
    try fixture.write("library/numbers.my", "module numbers\n\n\npublic def answer() -> int:\n    return 43\n");
    try fixture.expect(&build_args, 2, "", "packages: locked dependency changed: numbers");
    try fixture.write("library/numbers.my", package_library);
    try fixture.write("app1/numbers.my", package_library);
    try fixture.expect(&build_args, 2, "", "duplicate or invalid module path: numbers.my");
    try fixture.temporary.dir.deleteFile(testing.io, "app1/numbers.my");
    try fixture.write("app1/std_extra.my", "module std_extra\n");
    try fixture.expect(&build_args, 2, "", "cannot replace a standard module: std_extra.my");
    try fixture.temporary.dir.deleteFile(testing.io, "app1/std_extra.my");
    try doubledLock(&fixture, frozen);
    try fixture.expect(&build_args, 2, "", "duplicate or incompatible package namespace: numbers");
    try fixture.write("lock.json", "{\"version\":\"package-lock-v0\",\"packages\":[]}");
    try fixture.expect(&build_args, 2, "", "unsupported package lock");
    try fixture.write("lock.json", frozen);
    try fixture.temporary.dir.deleteFile(testing.io, "library/numbers.my");
    try fixture.temporary.dir.symLink(testing.io, "../app1/main.my", "library/numbers.my", .{});
    try fixture.expect(&build_args, 2, "", "symbolic-link sources are rejected: numbers.my");
    // No refusal touched the receipt the passing build wrote.
    const kept = try fixture.read("receipt.json");
    defer testing.allocator.free(kept);
    try testing.expectEqualStrings(receipt, kept);
}

// spec: PACKAGES-LOCK-1
test "mylang packages lock pins each resolved root and module hash and refuses bad namespaces, empty packages and stray sources" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const lock = try fixture.read("lock.json");
    defer testing.allocator.free(lock);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(package_library, &digest, .{});
    const pinned = try std.fmt.allocPrint(testing.allocator, "\"numbers.my\": \"{s}\"", .{std.fmt.bytesToHex(digest, .lower)});
    defer testing.allocator.free(pinned);
    const root = try std.fmt.allocPrint(testing.allocator, "\"root\": \"{s}/library\"", .{fixture.root});
    defer testing.allocator.free(root);
    try testing.expect(std.mem.startsWith(u8, lock, "{\n  \"version\": \"package-lock-v1\",\n  \"packages\": [\n"));
    try testing.expect(std.mem.indexOf(u8, lock, pinned) != null);
    try testing.expect(std.mem.indexOf(u8, lock, root) != null);
    const lock_args = [_][]const u8{ "lock", "packages.json", "--output", "other.json" };
    try fixture.write("packages.json", "{\"packages\":[{\"name\":\"std_numbers\",\"root\":\"library\"}]}");
    try fixture.expect(&lock_args, 2, "", "invalid or reserved package namespace: std_numbers");
    try fixture.write("packages.json", "{\"packages\":[{\"name\":\"9numbers\",\"root\":\"library\"}]}");
    try fixture.expect(&lock_args, 2, "", "invalid or reserved package namespace: 9numbers");
    try fixture.write("packages.json", "{\"packages\":[{\"name\":\"numbers\",\"root\":\"library\"},{\"name\":\"numbers\",\"root\":\"library\"}]}");
    try fixture.expect(&lock_args, 2, "", "duplicate package namespace: numbers");
    try fixture.write("packages.json", "{\"packages\":[{\"name\":\"numbers\",\"root\":\"missing\"}]}");
    try fixture.expect(&lock_args, 2, "", "cannot resolve root");
    try fixture.write("empty/notes.txt", "no sources here");
    try fixture.write("packages.json", "{\"packages\":[{\"name\":\"numbers\",\"root\":\"empty\"}]}");
    try fixture.expect(&lock_args, 2, "", "empty dependency: numbers");
    try fixture.write("library/stray.my", "module stray\n");
    try fixture.write("packages.json", "{\"packages\":[{\"name\":\"numbers\",\"root\":\"library\"}]}");
    try fixture.expect(&lock_args, 2, "", "dependency source must declare its package namespace: stray.my");
    try fixture.expect(&.{ "lock", "packages.json" }, 2, "", "usage: mylang packages");
    // No refused lock wrote its output.
    try testing.expectError(error.FileNotFound, fixture.temporary.dir.access(testing.io, "other.json", .{}));
}

// spec: BOUNDARY-CLI-1
test "boundary acceptance CLI runs through run build --run and installed paths" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "sample.my", .data = "a\nb\n" });
    const input = try temp.dir.realPathFileAlloc(testing.io, "sample.my", testing.allocator);
    defer testing.allocator.free(input);
    const home = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(home);
    const output = try std.fs.path.join(testing.allocator, &.{ home, "boundary-cli" });
    defer testing.allocator.free(output);
    const cache = try std.fs.path.join(testing.allocator, &.{ home, "cache" });
    defer testing.allocator.free(cache);
    const cache_arg = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_arg);
    const entry = "examples/boundary-cli/main.my";
    const expected = "{\"lines\":2,\"characters\":4}\n";
    const trace = try std.fmt.allocPrint(testing.allocator, "reading {s}\n", .{input});
    defer testing.allocator.free(trace);

    var plain_env: std.process.Environ.Map = .init(testing.allocator);
    defer plain_env.deinit();
    try plain_env.put("HOME", home);
    try forwardZigCache(&plain_env);
    var trace_env: std.process.Environ.Map = .init(testing.allocator);
    defer trace_env.deinit();
    try trace_env.put("HOME", home);
    try trace_env.put("MYLANG_ACCEPT_MODE", "1");
    try forwardZigCache(&trace_env);

    var run_argv: std.ArrayList([]const u8) = .empty;
    defer run_argv.deinit(testing.allocator);
    try run_argv.appendSlice(testing.allocator, &.{ compiler_path, "run", entry, cache_arg });
    try run_argv.appendSlice(testing.allocator, &tools);
    try run_argv.appendSlice(testing.allocator, &.{ "--", input });
    const cold = try spawnWithEnv(run_argv.items, &plain_env);
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cold.term);
    try testing.expectEqualStrings(expected, cold.stdout);
    try testing.expectEqualStrings("", cold.stderr);
    const warm = try spawnWithEnv(run_argv.items, &trace_env);
    defer testing.allocator.free(warm.stdout);
    defer testing.allocator.free(warm.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, warm.term);
    try testing.expectEqualStrings(expected, warm.stdout);
    try testing.expectEqualStrings(trace, warm.stderr);

    var build_argv: std.ArrayList([]const u8) = .empty;
    defer build_argv.deinit(testing.allocator);
    try build_argv.appendSlice(testing.allocator, &.{ compiler_path, "build", entry, "--run", cache_arg });
    try build_argv.appendSlice(testing.allocator, &tools);
    try build_argv.appendSlice(testing.allocator, &.{ "--", input });
    const built = try spawnWithEnv(build_argv.items, &trace_env);
    defer testing.allocator.free(built.stdout);
    defer testing.allocator.free(built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    try testing.expectEqualStrings(expected, built.stdout);
    try testing.expectEqualStrings(trace, built.stderr);

    var link_argv: std.ArrayList([]const u8) = .empty;
    defer link_argv.deinit(testing.allocator);
    try link_argv.appendSlice(testing.allocator, &.{ compiler_path, "build", entry, "--project", "-o", output });
    try link_argv.appendSlice(testing.allocator, &tools);
    const link = try spawnWithEnv(link_argv.items, &plain_env);
    defer testing.allocator.free(link.stdout);
    defer testing.allocator.free(link.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, link.term);
    const installed = try spawnWithEnv(&.{ output, input }, &trace_env);
    defer testing.allocator.free(installed.stdout);
    defer testing.allocator.free(installed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, installed.term);
    try testing.expectEqualStrings(expected, installed.stdout);
    try testing.expectEqualStrings(trace, installed.stderr);
}

test "CLI run and check success" {
    try invoke("run", @embedFile("fixtures/arithmetic.my"), 0, "7\n", "");
    try invoke("check", @embedFile("fixtures/arithmetic.my"), 0, "", "");
}
// spec-case: NATIVE-TEST-10
test "a native run reports a failed assert with its message" {
    try invoke("run",
        \\def main() -> int:
        \\    assert False, "x should be two"
        \\    return 0
    , 1, "", "error[R_ASSERT]: native execution failed: x should be two");
    // A message carrying JSON syntax must not corrupt the machine record: the
    // `trap_detail` object still parses and appears in the JSON diagnostics.
    try invokeOptions("run",
        \\def main() -> int:
        \\    assert False, "say \"hi\""
        \\    return 0
    , &.{"--diagnostics=json"}, 1, "", "\"trap_detail\"");
}
// spec: NATIVE-TIMING-1
test "CLI execution timings preserve results and runtime diagnostics" {
    const source =
        \\def main() -> i64:
        \\    return 42
    ;
    const outcome = try runFixture("run", source, &.{"--timings"});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    // The entry returns 42, which is now the process exit status.
    try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, outcome.term);
    try testing.expectEqualStrings("42\n", outcome.stdout);
    const prefix = "timings: native_ns=";
    try testing.expect(std.mem.startsWith(u8, outcome.stderr, prefix));
    _ = try std.fmt.parseInt(u64, std.mem.trim(u8, outcome.stderr[prefix.len..], "\n"), 10);
    const trap =
        \\def main() -> i64:
        \\    return divtrunc(1, 0)
    ;
    try invokeOptions("run", trap, &.{"--timings"}, 1, "", "error[R_DIVISION_BY_ZERO]");
    try invokeOptions("run", trap, &.{"--diagnostics=json"}, 1, "", "\"code\":\"R_DIVISION_BY_ZERO\"");
    try invokeOptions("run", source, &.{ "--timings", "--timings" }, 2, "", "usage:");
    try invokeOptions("check", source, &.{"--timings"}, 2, "", "usage:");
}
test "CLI dumps actual instructions" {
    try invoke("dump-bytecode", @embedFile("fixtures/arithmetic.my"), 0, @embedFile("fixtures/arithmetic.dump"), "");
}
// spec: CLI-1
test "CLI distinguishes source errors runtime traps and Usage errors" {
    try invoke("check",
        \\def main() -> i64:
        \\    return 1 +
    , 1, "", "error[E_EXPRESSION]");
    try invoke("check",
        \\def main() -> i64:
        \\    return 9223372036854775807 + 1
    , 0, "", "");
    try invoke("run",
        \\def main() -> i64:
        \\    return 9223372036854775807 + 1
    , 1, "", "error[R_OVERFLOW]");
    try invoke("unknown", "", 2, "", "usage:");
}
// spec: CLI-2
test "CLI missing arguments and missing files are host or usage failures" {
    const no_args = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{compiler_path} });
    defer testing.allocator.free(no_args.stdout);
    defer testing.allocator.free(no_args.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, no_args.term);
    try testing.expectEqualStrings("", no_args.stdout);
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const absolute_compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, testing.allocator);
    defer testing.allocator.free(absolute_compiler);
    const absent = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ absolute_compiler, "run", "missing.my" },
        .cwd = .{ .dir = temp.dir },
    });
    defer testing.allocator.free(absent.stdout);
    defer testing.allocator.free(absent.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, absent.term);
    try testing.expectEqualStrings("", absent.stdout);
    try testing.expect(std.mem.indexOf(u8, absent.stderr, "FileNotFound") != null);
}
test "CLI binding warnings do not alter status or result output" {
    const text =
        \\def main() -> i64:
        \\    unused = 3
        \\    return 7
    ;
    try invoke("run", text, 0, "7\n", "warning[W_UNUSED_BINDING]");
    try invoke("check", text, 0, "", "warning[W_UNUSED_BINDING]");
    try invoke("run",
        \\def main() -> i64:
        \\    unused = 9223372036854775807 + 1
        \\    return 7
    , 1, "", "error[R_OVERFLOW]");
    try invoke("run",
        \\def main() -> i64:
        \\    return -9223372036854775808
    , 0, "-9223372036854775808\n", "");
    try invoke("check",
        \\def main() -> i64:
        \\    x = True
        \\    x = 1
        \\    return 7
    , 1, "", "error[E_TYPE]");
}
test "CLI step budgets count dispatch and reject invalid options" {
    const text =
        \\def main() -> i64:
        \\    return 1
    ;
    try invokeOptions("run", text, &.{"--max-steps=2"}, 0, "1\n", "");
    try invokeOptions("run", text, &.{"--max-steps=1"}, 1, "", "error[R_STEP_LIMIT]");
    try invokeOptions("run",
        \\def main() -> i64:
        \\    while True:
        \\        pass
        \\    return 1
    , &.{"--max-steps=100"}, 1, "", "error[R_STEP_LIMIT]");
    for ([_][]const u8{ "--max-steps=0", "--max-steps=-1", "--max-steps=+1", "--max-steps=", "--max-steps=abc", "--max-steps=18446744073709551616", "--unknown=1" }) |option| {
        try invokeOptions("run", text, &.{option}, 2, "", "usage:");
    }
    try invokeOptions("run", text, &.{ "--max-steps=2", "--max-steps=3" }, 2, "", "usage:");
    try invokeOptions("check", text, &.{"--max-steps=2"}, 2, "", "usage:");
    try invokeOptions("dump-bytecode", text, &.{"--max-steps=2"}, 2, "", "usage:");
}
// spec: BUDGET-HINT-1
test "CLI budget traps name the flag that raises the budget" {
    const text =
        \\def main() -> i64:
        \\    return 1
    ;
    try invokeOptions("run", text, &.{"--max-steps=1"}, 1, "", "raise it with --max-steps=N");
    try invokeOptions("run", text, &.{ "--max-steps=1", "--diagnostics=json" }, 1, "", "\"message\":\"instruction budget exhausted; raise it with --max-steps=N\"");
    try invokeOptions("run",
        \\def inner() -> i64:
        \\    return 1
        \\
        \\
        \\def main() -> i64:
        \\    return inner()
    , &.{ "--max-frames=1", "--max-steps=1000000" }, 1, "", "raise it with --max-frames=N");
    try invokeOptions("run",
        \\def inner() -> i64:
        \\    return 1
        \\
        \\
        \\def main() -> i64:
        \\    return inner()
    , &.{ "--max-frames=1", "--max-steps=1000000", "--diagnostics=json" }, 1, "", "\"message\":\"call-depth budget exhausted; raise it with --max-frames=N\"");
    const memory =
        \\def main() -> i64:
        \\    values: list[int] = []
        \\    for r in range(100000000):
        \\        values.append(r)
        \\    return len(values)
    ;
    try invokeOptions("run", memory, &.{ "--max-steps=4000000000", "--max-memory=32M" }, 1, "", "error[R_MEMORY_BUDGET]: memory budget exhausted");
}
// spec: QBE-FRAME-ACCOUNTING-2
test "an executable built without a frame ceiling refuses a runtime frame budget" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "depth.my", .data =
        \\def main() -> i64:
        \\    return 0
    });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "depth.my", testing.allocator);
    defer testing.allocator.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const output = try std.fs.path.join(testing.allocator, &.{ directory, "depth-bin" });
    defer testing.allocator.free(output);
    const cache = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);
    // The default mode is ReleaseFast and no ceiling was asked for, so the
    // published executable carries no call-depth accounting.
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", output, cache_argument, tools[0], tools[1] }, "");
    try expectConstantProcess(&.{output}, "");
    // A ceiling it cannot enforce is refused instead of silently ignored.
    var one_frame = try runtimeOptions("--max-frames=1");
    defer one_frame.deinit();
    const refused = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{output}, .environ_map = &one_frame });
    defer testing.allocator.free(refused.stdout);
    defer testing.allocator.free(refused.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, refused.term);
    try testing.expectEqualStrings("", refused.stdout);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "error[R_NO_FRAME_ACCOUNTING]") != null);
    // A build that keeps its traces still runs without any ceiling argument.
    try expectConstantProcess(&.{output}, "");
    // Both explicit ReleaseFast accounting and Debug's default must accept the
    // requested budget. Emission cannot depend on `saw_frames`: emit-qbe does
    // not accept run-only budget flags from its build-driver parent.
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", output, cache_argument, tools[0], tools[1], "--max-frames=1" }, "");
    try expectConstantRun(&.{output}, &one_frame, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", output, cache_argument, tools[0], tools[1], "--mode=Debug" }, "");
    try expectConstantRun(&.{output}, &one_frame, "");
}
/// Build `name` as a ReleaseFast executable twice — with no ceiling, so its
/// failure paths end in `hlt`, and with a frame ceiling, which keeps the sticky
/// return through `@failure` — and run both; then run it through `mylang run`
/// with and without a frame ceiling. Each pair must report the same bytes and
/// exit status 1, and the executable's report must be `expected` with `{path}`
/// standing for the entry's absolute path.
fn expectHaltedTrapIdentical(temporary: *testing.TmpDir, name: []const u8, source: []const u8, expected: []const u8) !void {
    const a = testing.allocator;
    const file = try std.fmt.allocPrint(a, "{s}.my", .{name});
    defer a.free(file);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = file, .data = source });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, file, a);
    defer a.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const cache_argument = try std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{directory});
    defer a.free(cache_argument);
    const fast = try std.fmt.allocPrint(a, "{s}/{s}-fast", .{ directory, name });
    defer a.free(fast);
    const framed = try std.fmt.allocPrint(a, "{s}/{s}-framed", .{ directory, name });
    defer a.free(framed);
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", fast, cache_argument, tools[0], tools[1] }, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", framed, cache_argument, tools[0], tools[1], "--max-frames=100000" }, "");
    const wanted = try std.mem.replaceOwned(u8, a, expected, "{path}", entry);
    defer a.free(wanted);
    const halted = try std.process.run(a, testing.io, .{ .argv = &.{fast} });
    defer a.free(halted.stdout);
    defer a.free(halted.stderr);
    const sticky = try std.process.run(a, testing.io, .{ .argv = &.{framed} });
    defer a.free(sticky.stdout);
    defer a.free(sticky.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, halted.term);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, sticky.term);
    try testing.expectEqualStrings("", halted.stdout);
    try testing.expectEqualStrings(wanted, halted.stderr);
    try testing.expectEqualStrings(halted.stderr, sticky.stderr);
    // `mylang run` builds the same fast protocol with QBE unless a ceiling asks
    // for accounting; both report the trap the same way.
    const run_fast = try std.process.run(a, testing.io, .{ .argv = &.{ compiler_path, "run", entry, cache_argument, tools[0], tools[1] } });
    defer a.free(run_fast.stdout);
    defer a.free(run_fast.stderr);
    const run_framed = try std.process.run(a, testing.io, .{ .argv = &.{ compiler_path, "run", entry, cache_argument, tools[0], tools[1], "--max-frames=100000" } });
    defer a.free(run_framed.stdout);
    defer a.free(run_framed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, run_fast.term);
    try testing.expectEqual(run_fast.term, run_framed.term);
    try testing.expect(std.mem.indexOf(u8, run_fast.stderr, wanted[0 .. std.mem.indexOfScalar(u8, wanted, '\n') orelse wanted.len]) != null);
    try testing.expectEqualStrings(run_fast.stderr, run_framed.stderr);
}
/// Build `name` with `--release` — LLVM with full LTO, which
/// is free to inline guest functions into one another — with LLVM ThinLTO,
/// which inlines them across modules (LLVM-THINLTO-1), and with QBE, all
/// with no ceiling so none links a frame record, run each, and require exit
/// status 1 and exactly `expected` on stderr from every one, `{path}` standing
/// for the entry's absolute path.
fn expectFrameMapTrap(temporary: *testing.TmpDir, name: []const u8, source: []const u8, expected: []const u8) !void {
    const a = testing.allocator;
    const file = try std.fmt.allocPrint(a, "{s}.my", .{name});
    defer a.free(file);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = file, .data = source });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, file, a);
    defer a.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const cache_argument = try std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{directory});
    defer a.free(cache_argument);
    const wanted = try std.mem.replaceOwned(u8, a, expected, "{path}", entry);
    defer a.free(wanted);
    const llvm = try std.fmt.allocPrint(a, "{s}/{s}-llvm", .{ directory, name });
    defer a.free(llvm);
    const qbe = try std.fmt.allocPrint(a, "{s}/{s}-qbe", .{ directory, name });
    defer a.free(qbe);
    const thin = try std.fmt.allocPrint(a, "{s}/{s}-thin", .{ directory, name });
    defer a.free(thin);
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", llvm, "--release", cache_argument, tools[1] }, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", thin, "--mode", "ReleaseFast", "--backend", "llvm", "--llvm-opt", "3", "--lto=thin", cache_argument, tools[1] }, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", qbe, cache_argument, tools[0], tools[1] }, "");
    for ([_][]const u8{ llvm, thin, qbe }) |binary| {
        const trapped = try std.process.run(a, testing.io, .{ .argv = &.{binary} });
        defer a.free(trapped.stdout);
        defer a.free(trapped.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, trapped.term);
        try testing.expectEqualStrings("", trapped.stdout);
        try testing.expectEqualStrings(wanted, trapped.stderr);
    }
}
// spec-case: QBE-FRAMEMAP-1
// spec-case: LLVM-THINLTO-1
test "a frame-map trap names every logical frame an inlined callee, a callback, a runtime helper or recursion passes through" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    // LLVM inlines `a` into the loop in `total`; its frame is still reported.
    try expectFrameMapTrap(&temporary, "inlined",
        \\# a trap inside a small callee LLVM inlines into a loop
        \\
        \\
        \\def a(i: int, j: int) -> float:
        \\    return 1.0 / float((i + j) * (i + j + 1) // 2 + i + 1)
        \\
        \\
        \\def total(n: int, start: int) -> float:
        \\    s = 0.0
        \\    for i in range(n):
        \\        s = s + a(start + i, 9223372036854775000)
        \\    return s
        \\
        \\
        \\def main(out: Stream) -> int:
        \\    out.print(int(total(10, 1)))
        \\    return 0
    ,
        \\{path}:5:32: error[R_OVERFLOW]: native execution failed (mul: left 9223372036854775001, right 9223372036854775002, width 64)
        \\  in a at {path}:5:32
        \\  in total at {path}:11:17
        \\  in main at {path}:16:19
        \\
    ++ "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\"mul\",\"left\":9223372036854775001,\"right\":9223372036854775002,\"width\":64}\n");
    // An assertion's message still comes from the innermost frame's position.
    try expectFrameMapTrap(&temporary, "callback",
        \\# an assertion inside a key function called back by sorted
        \\
        \\
        \\def key_of(x: int) -> int:
        \\    assert x != 3, "no threes"
        \\    return 0 - x
        \\
        \\
        \\def main(out: Stream) -> int:
        \\    ordered = sorted([5, 4, 3, 2, 1], key=key_of)
        \\    out.print(ordered[0])
        \\    return 0
    ,
        \\{path}:5:12: error[R_ASSERT]: native execution failed: no threes
        \\  in key_of at {path}:5:12
        \\  in main at {path}:10:15
        \\
    ++ "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\"no threes\"}\n");
    // The runtime helper traps inside itself; the frame is its call site.
    try expectFrameMapTrap(&temporary, "helper",
        \\# a conversion the runtime helper refuses, two frames deep
        \\
        \\
        \\def convert(x: float) -> int:
        \\    return int(x * 1e300 * 1e300)
        \\
        \\
        \\def main(out: Stream) -> int:
        \\    total = 0
        \\    for i in range(3):
        \\        total = total + convert(float(i) + 0.5)
        \\    out.print(total)
        \\    return 0
    ,
        \\{path}:5:12: error[R_FLOAT_CONVERSION]: native execution failed
        \\  in convert at {path}:5:12
        \\  in main at {path}:11:25
        \\
    );
    // The stack-floor guard fails in the prologue of the frame it would have
    // entered, so the trace starts at its caller's call site.
    const recursion_trace =
        \\{path}:7:16: error[R_FRAME_LIMIT]: call-depth budget exhausted; raise it with --max-frames=N
        \\  in descend at {path}:7:16
        \\  in descend at {path}:7:16
        \\  in descend at {path}:7:16
        \\  in descend at {path}:7:16
        \\  in descend at {path}:7:16
        \\  in descend at {path}:7:16
        \\  in descend at {path}:7:16
        \\  in descend at {path}:7:16
        \\  in descend at {path}:7:16
        \\  in descend at {path}:7:16
        \\  in descend at {path}:7:16
        \\  in descend at {path}:7:16
        \\  in descend at {path}:7:16
        \\  in descend at {path}:7:16
        \\  in descend at {path}:7:16
        \\  in descend at {path}:7:16
        \\
    ;
    try expectFrameMapTrap(&temporary, "recursion",
        \\# unbounded recursion reaches the execution-stack floor
        \\
        \\
        \\def descend(depth: int) -> int:
        \\    if depth == 0:
        \\        return 0
        \\    return 1 + descend(depth - 1)
        \\
        \\
        \\def main(out: Stream) -> int:
        \\    out.print(descend(1000000000))
        \\    return 0
    , recursion_trace);
}
// spec-case: QBE-NORETURN-1
test "a trap through a halting failure path reports the same code, trace, record and status" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    // A checked add that overflows three frames deep.
    try expectHaltedTrapIdentical(&temporary, "overflow",
        \\# an overflow three frames deep
        \\
        \\
        \\def grow(x: int, step: int) -> int:
        \\    return x + step
        \\
        \\
        \\def climb(x: int) -> int:
        \\    total = x
        \\    for i in range(10):
        \\        total = grow(total, 1000000000000000000)
        \\    return total
        \\
        \\
        \\def main(out: Stream) -> int:
        \\    out.print(climb(1))
        \\    return 0
    ,
        \\{path}:5:14: error[R_OVERFLOW]: native execution failed (add: left 9000000000000000001, right 1000000000000000000, width 64)
        \\  in grow at {path}:5:14
        \\  in climb at {path}:11:17
        \\  in main at {path}:16:15
        \\
    ++ "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\"add\",\"left\":9000000000000000001,\"right\":1000000000000000000,\"width\":64}\n");
    // An out-of-range list write after a loop that succeeded.
    try expectHaltedTrapIdentical(&temporary, "index",
        \\# an out-of-range list write after a successful loop
        \\
        \\
        \\def poke(xs: mut list[int], at: int) -> None:
        \\    xs[at] = 7
        \\
        \\
        \\def main(out: Stream) -> int:
        \\    xs: list[int] = [1, 2, 3]
        \\    total = 0
        \\    for x in xs:
        \\        total = total + x
        \\    poke(mut xs, total)
        \\    out.print(total)
        \\    return 0
    ,
        \\{path}:5:5: error[R_LIST_BOUNDS]: native execution failed (index 6, length 3)
        \\  in poke at {path}:5:5
        \\  in main at {path}:13:5
        \\
    ++ "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\"index\",\"index\":6,\"length\":3}\n");
}
/// Checked `+ - *` at every width, operands and width from the command line:
/// `WIDTH OP X Y` prints `X OP Y` computed in that width, three frames deep.
const checked_arithmetic_program =
    \\# checked + - * at every width, operands from the command line
    \\
    \\
    \\def number(text: str) -> int:
    \\    match int(text):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\
    \\
    \\def wide(x: int) -> u64:
    \\    if x >= 0:
    \\        return u64(x)
    \\    return u64(x + 9223372036854775807 + 1) + 9223372036854775808u64
    \\
    \\
    \\def signed64(op: str, x: int, y: int) -> int:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\def unsigned64(op: str, x: u64, y: u64) -> u64:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\def signed32(op: str, x: i32, y: i32) -> i32:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\def unsigned32(op: str, x: u32, y: u32) -> u32:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\def signed16(op: str, x: i16, y: i16) -> i16:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\def unsigned16(op: str, x: u16, y: u16) -> u16:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\def signed8(op: str, x: i8, y: i8) -> i8:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\def unsigned8(op: str, x: u8, y: u8) -> u8:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\def report(out: Stream, args: list[str]) -> int:
    \\    width = args[0]
    \\    op = args[1]
    \\    x = number(args[2])
    \\    y = number(args[3])
    \\    if width == "i64":
    \\        out.print(signed64(op, x, y))
    \\    if width == "u64":
    \\        out.print(unsigned64(op, wide(x), wide(y)))
    \\    if width == "i32":
    \\        out.print(signed32(op, i32(x), i32(y)))
    \\    if width == "u32":
    \\        out.print(unsigned32(op, u32(x), u32(y)))
    \\    if width == "i16":
    \\        out.print(signed16(op, i16(x), i16(y)))
    \\    if width == "u16":
    \\        out.print(unsigned16(op, u16(x), u16(y)))
    \\    if width == "i8":
    \\        out.print(signed8(op, i8(x), i8(y)))
    \\    if width == "u8":
    \\        out.print(unsigned8(op, u8(x), u8(y)))
    \\    return 0
    \\
    \\
    \\def main(args: list[str], out: Stream) -> int:
    \\    return report(out, args)
;
/// One boundary of `checked_arithmetic_program`: `x op ok` is `sum`, the
/// largest (or smallest) value the width holds, and `x op bad` overflows it. A
/// `u64` operand spelled negative is its two's-complement pattern.
const CheckedBoundary = struct { width: []const u8, op: []const u8, x: []const u8, ok: []const u8, bad: []const u8, sum: []const u8, bits: []const u8 };
const checked_boundaries = [_]CheckedBoundary{
    .{ .width = "i64", .op = "add", .x = "9223372036854775806", .ok = "1", .bad = "2", .sum = "9223372036854775807", .bits = "64" },
    .{ .width = "i64", .op = "add", .x = "-9223372036854775807", .ok = "-1", .bad = "-2", .sum = "-9223372036854775808", .bits = "64" },
    .{ .width = "i64", .op = "sub", .x = "-9223372036854775807", .ok = "1", .bad = "2", .sum = "-9223372036854775808", .bits = "64" },
    .{ .width = "i64", .op = "sub", .x = "9223372036854775806", .ok = "-1", .bad = "-2", .sum = "9223372036854775807", .bits = "64" },
    .{ .width = "i64", .op = "mul", .x = "3037000500", .ok = "3037000499", .bad = "3037000500", .sum = "9223372033963249500", .bits = "64" },
    .{ .width = "i64", .op = "mul", .x = "-4611686018427387904", .ok = "2", .bad = "3", .sum = "-9223372036854775808", .bits = "64" },
    .{ .width = "i64", .op = "mul", .x = "-1", .ok = "-9223372036854775807", .bad = "-9223372036854775808", .sum = "9223372036854775807", .bits = "64" },
    .{ .width = "u64", .op = "add", .x = "-2", .ok = "1", .bad = "2", .sum = "18446744073709551615", .bits = "64" },
    .{ .width = "u64", .op = "sub", .x = "5", .ok = "5", .bad = "6", .sum = "0", .bits = "64" },
    .{ .width = "u64", .op = "mul", .x = "4294967296", .ok = "4294967295", .bad = "4294967296", .sum = "18446744069414584320", .bits = "64" },
    .{ .width = "i32", .op = "add", .x = "2147483646", .ok = "1", .bad = "2", .sum = "2147483647", .bits = "32" },
    .{ .width = "i32", .op = "sub", .x = "-2147483647", .ok = "1", .bad = "2", .sum = "-2147483648", .bits = "32" },
    .{ .width = "i32", .op = "mul", .x = "46341", .ok = "46340", .bad = "46341", .sum = "2147441940", .bits = "32" },
    .{ .width = "u32", .op = "add", .x = "4294967294", .ok = "1", .bad = "2", .sum = "4294967295", .bits = "32" },
    .{ .width = "u32", .op = "sub", .x = "5", .ok = "5", .bad = "6", .sum = "0", .bits = "32" },
    .{ .width = "u32", .op = "mul", .x = "65536", .ok = "65535", .bad = "65536", .sum = "4294901760", .bits = "32" },
    .{ .width = "i16", .op = "add", .x = "32766", .ok = "1", .bad = "2", .sum = "32767", .bits = "16" },
    .{ .width = "i16", .op = "sub", .x = "-32767", .ok = "1", .bad = "2", .sum = "-32768", .bits = "16" },
    .{ .width = "i16", .op = "mul", .x = "182", .ok = "180", .bad = "181", .sum = "32760", .bits = "16" },
    .{ .width = "u16", .op = "add", .x = "65534", .ok = "1", .bad = "2", .sum = "65535", .bits = "16" },
    .{ .width = "u16", .op = "sub", .x = "5", .ok = "5", .bad = "6", .sum = "0", .bits = "16" },
    .{ .width = "u16", .op = "mul", .x = "256", .ok = "255", .bad = "256", .sum = "65280", .bits = "16" },
    .{ .width = "i8", .op = "add", .x = "126", .ok = "1", .bad = "2", .sum = "127", .bits = "8" },
    .{ .width = "i8", .op = "sub", .x = "-127", .ok = "1", .bad = "2", .sum = "-128", .bits = "8" },
    .{ .width = "i8", .op = "mul", .x = "11", .ok = "11", .bad = "12", .sum = "121", .bits = "8" },
    .{ .width = "u8", .op = "add", .x = "254", .ok = "1", .bad = "2", .sum = "255", .bits = "8" },
    .{ .width = "u8", .op = "sub", .x = "5", .ok = "5", .bad = "6", .sum = "0", .bits = "8" },
    .{ .width = "u8", .op = "mul", .x = "16", .ok = "15", .bad = "16", .sum = "240", .bits = "8" },
};
/// Run `WIDTH OP X Y` through the LLVM and the QBE binary and require the same
/// status, stdout and stderr from both; returns the LLVM run's stderr.
fn expectSameBoundary(binaries: [2][]const u8, args: [4][]const u8, status: u8, stdout: []const u8) ![]u8 {
    const a = testing.allocator;
    const llvm = try std.process.run(a, testing.io, .{ .argv = &.{ binaries[0], args[0], args[1], args[2], args[3] } });
    defer a.free(llvm.stdout);
    errdefer a.free(llvm.stderr);
    const qbe = try std.process.run(a, testing.io, .{ .argv = &.{ binaries[1], args[0], args[1], args[2], args[3] } });
    defer a.free(qbe.stdout);
    defer a.free(qbe.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = status }, llvm.term);
    try testing.expectEqual(llvm.term, qbe.term);
    try testing.expectEqualStrings(stdout, llvm.stdout);
    try testing.expectEqualStrings(llvm.stdout, qbe.stdout);
    try testing.expectEqualStrings(llvm.stderr, qbe.stderr);
    return llvm.stderr;
}
/// Every row of `checked_boundaries`: the in-range operand prints the width's
/// extreme on both backends, and the next one traps there with the same
/// `R_OVERFLOW` detail, trace and record.
fn expectCheckedBoundaries(binaries: [2][]const u8) !void {
    const a = testing.allocator;
    for (checked_boundaries) |row| {
        const printed = try std.fmt.allocPrint(a, "{s}\n", .{row.sum});
        defer a.free(printed);
        const quiet = try expectSameBoundary(binaries, .{ row.width, row.op, row.x, row.ok }, 0, printed);
        defer a.free(quiet);
        try testing.expectEqualStrings("", quiet);
        const trapped = try expectSameBoundary(binaries, .{ row.width, row.op, row.x, row.bad }, 1, "");
        defer a.free(trapped);
        // TRAP-UNSIGNED-1: an unsigned operand prints unsigned, so a `u64`
        // operand spelled negative shows its two's-complement value.
        const left = if (std.mem.eql(u8, row.width, "u64") and row.x[0] == '-')
            try std.fmt.allocPrint(a, "{d}", .{@as(u64, @bitCast(try std.fmt.parseInt(i64, row.x, 10)))})
        else
            try a.dupe(u8, row.x);
        defer a.free(left);
        const detail = try std.fmt.allocPrint(a, "error[R_OVERFLOW]: native execution failed ({s}: left {s}, right {s}, width {s})\n", .{ row.op, left, row.bad, row.bits });
        defer a.free(detail);
        try testing.expect(std.mem.indexOf(u8, trapped, detail) != null);
    }
}
// spec: LLVM-OVERFLOW-INTRINSIC-1
test "checked arithmetic at every width reports the same result and trap from the LLVM overflow intrinsics as from QBE" {
    const a = testing.allocator;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "checked.my", .data = checked_arithmetic_program });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "checked.my", a);
    defer a.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const cache_argument = try std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{directory});
    defer a.free(cache_argument);
    const llvm = try std.fmt.allocPrint(a, "{s}/checked-llvm", .{directory});
    defer a.free(llvm);
    const qbe = try std.fmt.allocPrint(a, "{s}/checked-qbe", .{directory});
    defer a.free(qbe);
    // The release build (LLVM, full LTO) lowers the 64-bit checks to the
    // intrinsics; QBE keeps the frontend's formulas and is the reference.
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", llvm, "--release", cache_argument, tools[1] }, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", qbe, cache_argument, tools[0], tools[1] }, "");
    try expectCheckedBoundaries(.{ llvm, qbe });
    // One trap in full: code, detail, the three frames and the record.
    const trapped = try expectSameBoundary(.{ llvm, qbe }, .{ "i64", "add", "9223372036854775806", "2" }, 1, "");
    defer a.free(trapped);
    const expected =
        \\{path}:20:18: error[R_OVERFLOW]: native execution failed (add: left 9223372036854775806, right 2, width 64)
        \\  in signed64 at {path}:20:18
        \\  in report at {path}:88:19
        \\  in main at {path}:107:12
        \\
    ++ "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\"add\",\"left\":9223372036854775806,\"right\":2,\"width\":64}\n";
    const wanted = try std.mem.replaceOwned(u8, a, expected, "{path}", entry);
    defer a.free(wanted);
    try testing.expectEqualStrings(wanted, trapped);
}
const sticky_reduction_program =
    \\# checked reductions in loops, operands from the command line
    \\
    \\
    \\def number(text: str) -> int:
    \\    match int(text):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\
    \\
    \\def build(n: int, value: int, last: int) -> list[int]:
    \\    values: list[int] = []
    \\    for i in range(n):
    \\        values.append(value)
    \\    values.append(last)
    \\    return values
    \\
    \\
    \\def total_of(values: list[int], start: int) -> int:
    \\    total = start
    \\    for v in values:
    \\        total += v
    \\    return total
    \\
    \\
    \\def indexed(values: list[int], start: int) -> int:
    \\    total = start
    \\    for i in range(len(values)):
    \\        total = total + values[i]
    \\    return total
    \\
    \\
    \\def scaled(values: list[int], start: int) -> int:
    \\    total = start
    \\    for v in values:
    \\        total += v * 3
    \\    return total
    \\
    \\
    \\def difference(values: list[int], start: int) -> int:
    \\    total = start
    \\    for v in values:
    \\        total -= v
    \\    return total
    \\
    \\
    \\def count_of(values: list[int], start: int) -> int:
    \\    count = start
    \\    for v in values:
    \\        if v == 109:
    \\            count += 1
    \\    return count
    \\
    \\
    \\def octets(n: int, start: int) -> int:
    \\    empty: list[int] = []
    \\    buffer = byte_buffer(empty)
    \\    for i in range(n):
    \\        _ = buffer.append_byte(109)
    \\        _ = buffer.append_byte(7)
    \\    data = bytes(buffer)
    \\    count = start
    \\    for i in range(len(data)):
    \\        if data[i] == 109:
    \\            count += 1
    \\    return count
    \\
    \\
    \\def main(args: list[str], out: Stream) -> int:
    \\    kind = args[0]
    \\    n = number(args[1])
    \\    value = number(args[2])
    \\    last = number(args[3])
    \\    start = number(args[4])
    \\    values = build(n, value, last)
    \\    if kind == "sum":
    \\        out.print(total_of(values, start))
    \\    if kind == "indexed":
    \\        out.print(indexed(values, start))
    \\    if kind == "scaled":
    \\        out.print(scaled(values, start))
    \\    if kind == "difference":
    \\        out.print(difference(values, start))
    \\    if kind == "count":
    \\        out.print(count_of(values, start))
    \\    if kind == "octets":
    \\        out.print(octets(n, start))
    \\    return 0
;
/// One run of `sticky_reduction_program` — kind, count, value, last value,
/// start — and the exit status it must have: 1 when a checked update overflows.
const ReductionCase = struct { args: [5][]const u8, status: u8 };
const reduction_cases = [_]ReductionCase{
    .{ .args = .{ "sum", "1000", "5", "7", "0" }, .status = 0 },
    .{ .args = .{ "sum", "3", "9223372036854775807", "1", "0" }, .status = 1 },
    .{ .args = .{ "sum", "50", "1099511627776", "3", "9223318161234591743" }, .status = 1 },
    .{ .args = .{ "sum", "50", "1099511627776", "3", "9223316402983323647" }, .status = 0 },
    .{ .args = .{ "sum", "2000", "-1125899906842624", "4611686018427387904", "0" }, .status = 0 },
    .{ .args = .{ "indexed", "1000", "5", "7", "0" }, .status = 0 },
    .{ .args = .{ "indexed", "3", "-9223372036854775807", "-2", "0" }, .status = 1 },
    .{ .args = .{ "scaled", "7", "3074457345618258602", "1", "0" }, .status = 1 },
    .{ .args = .{ "scaled", "1000", "-4", "9", "0" }, .status = 0 },
    .{ .args = .{ "difference", "100", "109", "1", "-9223372036854764908" }, .status = 1 },
    .{ .args = .{ "difference", "100", "109", "1", "-9223372036854764907" }, .status = 0 },
    .{ .args = .{ "count", "100", "109", "109", "9223372036854775707" }, .status = 1 },
    .{ .args = .{ "count", "100", "109", "1", "9223372036854775707" }, .status = 0 },
    .{ .args = .{ "octets", "1000", "0", "0", "9223372036854774807" }, .status = 0 },
    .{ .args = .{ "octets", "1000", "0", "0", "9223372036854774808" }, .status = 1 },
};
/// Run one argument list through the LLVM and the QBE binary and require the
/// same status, stdout and stderr from both; returns the LLVM run's stderr.
fn expectSameRun(binaries: [2][]const u8, args: []const []const u8, status: u8) ![]u8 {
    const a = testing.allocator;
    var runs: [2]std.process.RunResult = undefined;
    for (binaries, 0..) |binary, index| {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(a);
        try argv.append(a, binary);
        try argv.appendSlice(a, args);
        runs[index] = try std.process.run(a, testing.io, .{ .argv = argv.items });
    }
    defer a.free(runs[0].stdout);
    errdefer a.free(runs[0].stderr);
    defer a.free(runs[1].stdout);
    defer a.free(runs[1].stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = status }, runs[0].term);
    try testing.expectEqual(runs[0].term, runs[1].term);
    try testing.expectEqualStrings(runs[0].stdout, runs[1].stdout);
    try testing.expectEqualStrings(runs[0].stderr, runs[1].stderr);
    return runs[0].stderr;
}
/// One program built with the release default (LLVM, full LTO) and with QBE:
/// the LLVM executable, the QBE executable and the source path.
const BuiltPair = struct {
    llvm: []u8,
    qbe: []u8,
    entry: [:0]u8,
    fn binaries(self: BuiltPair) [2][]const u8 {
        return .{ self.llvm, self.qbe };
    }
    fn deinit(self: BuiltPair) void {
        testing.allocator.free(self.llvm);
        testing.allocator.free(self.qbe);
        testing.allocator.free(self.entry);
    }
};
/// Build `program`, written to `name` in `temporary`, with both backends.
fn buildBothBackends(temporary: *testing.TmpDir, name: []const u8, program: []const u8) !BuiltPair {
    const a = testing.allocator;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = name, .data = program });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, name, a);
    errdefer a.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const cache_argument = try std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{directory});
    defer a.free(cache_argument);
    const llvm = try std.fmt.allocPrint(a, "{s}/{s}-llvm", .{ directory, name });
    errdefer a.free(llvm);
    const qbe = try std.fmt.allocPrint(a, "{s}/{s}-qbe", .{ directory, name });
    errdefer a.free(qbe);
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", llvm, cache_argument, tools[1] }, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", qbe, cache_argument, tools[0], tools[1] }, "");
    return .{ .llvm = llvm, .qbe = qbe, .entry = entry };
}
/// Every row of `reduction_cases` runs the same on both backends, and traps
/// with `R_OVERFLOW` exactly when its status says so.
fn expectReductionCases(binaries: [2][]const u8) !void {
    for (reduction_cases) |case| {
        const stderr = try expectSameRun(binaries, &case.args, case.status);
        defer testing.allocator.free(stderr);
        try testing.expectEqual(case.status == 1, std.mem.indexOf(u8, stderr, "error[R_OVERFLOW]") != null);
    }
}
// spec: LLVM-STICKY-REDUCTION-1
test "checked reduction loops sum and trap the same from the LLVM fast copy as from QBE" {
    const a = testing.allocator;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const built = try buildBothBackends(&temporary, "reductions.my", sticky_reduction_program);
    defer built.deinit();
    try expectReductionCases(built.binaries());
    // One trap in full: the update that overflows is the third, with the
    // running total and the element it adds, in the loop's own function.
    const trapped = try expectSameRun(built.binaries(), &.{ "sum", "3", "9223372036854775807", "1", "0" }, 1);
    defer a.free(trapped);
    const expected =
        \\{path}:23:15: error[R_OVERFLOW]: native execution failed (add: left 9223372036854775807, right 9223372036854775807, width 64)
        \\  in total_of at {path}:23:15
        \\  in main at {path}:78:19
        \\
    ++ "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\"add\",\"left\":9223372036854775807,\"right\":9223372036854775807,\"width\":64}\n";
    const wanted = try std.mem.replaceOwned(u8, a, expected, "{path}", built.entry);
    defer a.free(wanted);
    try testing.expectEqualStrings(wanted, trapped);
}
const element_loops_program =
    \\# element loops over lists, nested lists, records in lists and bytes; sizes from the command line
    \\
    \\
    \\record Body:
    \\    x: float
    \\    v: float
    \\
    \\
    \\def number(text: str) -> int:
    \\    match int(text):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\
    \\
    \\def dot(a: list[float], b: list[float]) -> float:
    \\    s = 0.0
    \\    for i in range(len(a)):
    \\        s = s + a[i] * b[i]
    \\    return s
    \\
    \\
    \\def product(n: int) -> float:
    \\    a = [[float(i + j) for j in range(n)] for i in range(n)]
    \\    b = [[float(i * j % 7) for j in range(n)] for i in range(n)]
    \\    c = [[0.0 for j in range(n)] for i in range(n)]
    \\    for i in range(n):
    \\        for k in range(n):
    \\            aik = a[i][k]
    \\            for j in range(n):
    \\                c[i][j] = c[i][j] + aik * b[k][j]
    \\    total = 0.0
    \\    for i in range(n):
    \\        for j in range(n):
    \\            total = total + c[i][j]
    \\    return total
    \\
    \\
    \\def advance(bodies: mut list[Body], steps: int) -> None:
    \\    for s in range(steps):
    \\        for i in range(len(bodies)):
    \\            bodies[i].x = bodies[i].x + bodies[i].v
    \\            bodies[i].v = bodies[i].v * 0.5
    \\
    \\
    \\def scan(n: int) -> int:
    \\    empty: list[int] = []
    \\    buffer = byte_buffer(empty)
    \\    for i in range(n):
    \\        _ = buffer.append_byte(i % 256)
    \\    data = bytes(buffer)
    \\    count = 0
    \\    for i in range(len(data)):
    \\        if data[i] == 109:
    \\            count += 1
    \\    return count
    \\
    \\
    \\def prefix(values: list[int], at: int) -> int:
    \\    total = 0
    \\    for i in range(at):
    \\        total += values[i]
    \\    return total
    \\
    \\
    \\def main(args: list[str], out: Stream) -> int:
    \\    n = number(args[0])
    \\    at = number(args[1])
    \\    out.print(int(product(n)))
    \\    bodies = [Body(x=float(i), v=1.0) for i in range(n)]
    \\    advance(mut bodies, 10)
    \\    out.print(int(bodies[n - 1].x * 1000.0))
    \\    out.print(scan(n * 100))
    \\    values = [i * 3 for i in range(n)]
    \\    out.print(int(dot([float(v) for v in values], [1.5 for v in values])))
    \\    out.print(prefix(values, at))
    \\    return 0
;
// spec: LLVM-ELEMENT-GEP-1
test "element loops over lists, nested lists, records and bytes compute and trap the same from LLVM as from QBE" {
    const a = testing.allocator;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const built = try buildBothBackends(&temporary, "elements.my", element_loops_program);
    defer built.deinit();
    const quiet = try expectSameRun(built.binaries(), &.{ "20", "20" }, 0);
    defer a.free(quiet);
    try testing.expectEqualStrings("", quiet);
    // One past the end of the list traps in the loop that reads it.
    const trapped = try expectSameRun(built.binaries(), &.{ "20", "21" }, 1);
    defer a.free(trapped);
    try testing.expect(std.mem.indexOf(u8, trapped, "error[R_LIST_BOUNDS]: native execution failed (index 20, length 20)") != null);
    try testing.expect(std.mem.indexOf(u8, trapped, "  in prefix at ") != null);
}
/// Loops LLVM vectorizes once their checks are proven (`QBE-LOOP-VERSION-1`):
/// a byte count and a row update, sized and shifted from the command line.
const vector_loops_program =
    \\def number(text: str) -> int:
    \\    match int(text):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\
    \\
    \\def scan(data: bytes) -> int:
    \\    count = 0
    \\    for i in range(len(data)):
    \\        if data[i] == 109:
    \\            count += 1
    \\    return count
    \\
    \\
    \\def axpy(c: mut list[float], b: list[float], a: float, shift: int) -> None:
    \\    for j in range(len(c)):
    \\        c[j] = c[j] + a * b[j + shift]
    \\
    \\
    \\def main(args: list[str], out: Stream) -> int:
    \\    n = number(args[0])
    \\    text = ""
    \\    for i in range(n):
    \\        text = text + "mylang "
    \\    b = [float(i) for i in range(n)]
    \\    c = [1.0 for i in range(n)]
    \\    axpy(mut c, b, 0.5, number(args[1]))
    \\    total = 0.0
    \\    for x in c:
    \\        total = total + x
    \\    out.print(scan(text.encode()))
    \\    out.print(int(total))
    \\    return 0
;
// spec-case: QBE-LOOP-VERSION-1
test "versioned loops LLVM vectorizes compute and trap exactly as QBE does" {
    const a = testing.allocator;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "vector.my", .data = vector_loops_program });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "vector.my", a);
    defer a.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const cache_argument = try std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{directory});
    defer a.free(cache_argument);
    const llvm = try std.fmt.allocPrint(a, "{s}/vector-llvm", .{directory});
    defer a.free(llvm);
    const qbe = try std.fmt.allocPrint(a, "{s}/vector-qbe", .{directory});
    defer a.free(qbe);
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", llvm, cache_argument, tools[1] }, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", qbe, cache_argument, tools[0], tools[1] }, "");
    // Every index proven: 1000 words of "mylang ", and 1000 + 0.5 * (0 + ... + 999).
    const quiet = try expectSameBoundary(.{ llvm, qbe }, .{ "1000", "0", "", "" }, 0, "1000\n250750\n");
    defer a.free(quiet);
    try testing.expectEqualStrings("", quiet);
    // `b[j + 1]` fails the guard, so the original loop traps at its last row.
    const trapped = try expectSameBoundary(.{ llvm, qbe }, .{ "1000", "1", "", "" }, 1, "");
    defer a.free(trapped);
    try testing.expect(std.mem.indexOf(u8, trapped, "index 1000, length 1000") != null);
    try testing.expect(std.mem.indexOf(u8, trapped, "  in axpy at ") != null);
}
// spec-case: QBE-STEP-ACCOUNTING-1
test "an executable built without a requested ceiling refuses a runtime step budget" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "budget.my", .data =
        \\def main() -> i64:
        \\    return 0
    });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "budget.my", testing.allocator);
    defer testing.allocator.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const output = try std.fs.path.join(testing.allocator, &.{ directory, "budget-bin" });
    defer testing.allocator.free(output);
    const cache = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);
    // The default mode is ReleaseFast and no ceiling was asked for, so the
    // published executable carries no step accounting.
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", output, cache_argument, tools[0], tools[1] }, "");
    try expectConstantProcess(&.{output}, "");
    // A ceiling it cannot enforce is refused instead of silently ignored.
    var one_step = try runtimeOptions("--max-steps=1");
    defer one_step.deinit();
    const refused = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{output}, .environ_map = &one_step });
    defer testing.allocator.free(refused.stdout);
    defer testing.allocator.free(refused.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, refused.term);
    try testing.expectEqualStrings("", refused.stdout);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "error[R_NO_STEP_ACCOUNTING]") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "mylang run --max-steps=N") != null);
    // Asking `run` for the same ceiling compiles the accounting and enforces it.
    try invokeOptions("run", "def main() -> i64:\n    return 0\n", &.{"--max-steps=1"}, 1, "", "error[R_STEP_LIMIT]");
}
// spec-case: BUILD-MODE-1
test "CLI build report states the default and explicit optimize modes" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\def main() -> i64:
        \\    return 42
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const directory = std.fs.path.dirname(path).?;
    const cache = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache);
    const output = try std.fs.path.join(testing.allocator, &.{ directory, "program" });
    defer testing.allocator.free(output);
    for ([_][]const u8{ "ReleaseFast", "Debug" }) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(testing.allocator);
        try argv.appendSlice(testing.allocator, &.{ compiler_path, "build", path, "-o", output, "--report", "--cache-dir", cache });
        try argv.appendSlice(testing.allocator, &tools);
        if (!std.mem.eql(u8, mode, "ReleaseFast")) try argv.appendSlice(testing.allocator, &.{ "--mode", mode });
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items });
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
        try testing.expectEqualStrings("", result.stderr);
        const needle = try std.fmt.allocPrint(testing.allocator, "\"mode\":\"{s}\"", .{mode});
        defer testing.allocator.free(needle);
        try testing.expect(std.mem.indexOf(u8, result.stdout, needle) != null);
    }
}
/// Build `path` into `output` with only the `--zig` tool named, so the backend
/// is whatever `extra` asks for, and return the `--report` receipt.
fn buildReceipt(path: []const u8, output: []const u8, cache: []const u8, extra: []const []const u8) ![]u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.appendSlice(testing.allocator, &.{ compiler_path, "build", path, "-o", output, "--report", "--cache-dir", cache, tools[1] });
    try argv.appendSlice(testing.allocator, extra);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items });
    defer testing.allocator.free(result.stderr);
    errdefer testing.allocator.free(result.stdout);
    try testing.expectEqualStrings("", result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    return result.stdout;
}
// spec-case: BUILD-RELEASE-1
test "CLI build uses QBE when no backend is named and --release builds LLVM O3 with LTO" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\def main() -> i64:
        \\    return 42
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const directory = std.fs.path.dirname(path).?;
    const cache = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache);
    const output = try std.fs.path.join(testing.allocator, &.{ directory, "program" });
    defer testing.allocator.free(output);
    // The plain build is the fast one: ReleaseFast, generated by QBE.
    const plain = try buildReceipt(path, output, cache, &.{});
    defer testing.allocator.free(plain);
    try testing.expect(std.mem.indexOf(u8, plain, "\"mode\":\"ReleaseFast\"") != null);
    try testing.expect(std.mem.indexOf(u8, plain, "\"backend\":\"qbe\",\"optimization\":\"default\",\"lto\":false") != null);
    const debug = try buildReceipt(path, output, cache, &.{ "--mode", "Debug" });
    defer testing.allocator.free(debug);
    try testing.expect(std.mem.indexOf(u8, debug, "\"backend\":\"qbe\"") != null);
    // `--release` is the LLVM O3 build with full LTO, and it runs the same program.
    const release = try buildReceipt(path, output, cache, &.{"--release"});
    defer testing.allocator.free(release);
    try testing.expect(std.mem.indexOf(u8, release, "\"mode\":\"ReleaseFast\"") != null);
    try testing.expect(std.mem.indexOf(u8, release, "\"backend\":\"llvm\",\"optimization\":\"3\",\"lto\":true") != null);
    const ran = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{output} });
    defer testing.allocator.free(ran.stdout);
    defer testing.allocator.free(ran.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, ran.term);
    // `run --release` builds the same way; beside an explicit QBE it is a usage error.
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);
    const released = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "run", path, "--release", "--print-result", cache_argument, tools[1] } });
    defer testing.allocator.free(released.stdout);
    defer testing.allocator.free(released.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, released.term);
    try testing.expectEqualStrings("42\n", released.stdout);
    try invokeOptions("run", "def main() -> i64:\n    return 0\n", &.{"--release"}, 2, "", "usage:");
}
// spec-case: QBE-FRAMEMAP-ROOTS-1
test "CLI default build keeps the shared metadata object when a function is added and its trap still names every frame" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\def divide(a: i64, b: i64) -> i64:
        \\    return a // b
        \\
        \\
        \\def main() -> i64:
        \\    return divide(7, 0)
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const directory = std.fs.path.dirname(path).?;
    const cache = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache);
    const output = try std.fs.path.join(testing.allocator, &.{ directory, "program" });
    defer testing.allocator.free(output);
    const cold = try buildReceipt(path, output, cache, &.{});
    defer testing.allocator.free(cold);
    try testing.expect(std.mem.indexOf(u8, cold, "\"metadata_reused\":false") != null);
    // A new function reached from `main`: the default (ReleaseFast, QBE,
    // frame-map) build compiles it and `main` again, and reuses the shared unit.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\def divide(a: i64, b: i64) -> i64:
        \\    return a // b
        \\
        \\
        \\def extra(n: i64) -> i64:
        \\    return n + 3
        \\
        \\
        \\def main() -> i64:
        \\    return divide(extra(4), 0)
    });
    const added = try buildReceipt(path, output, cache, &.{});
    defer testing.allocator.free(added);
    try testing.expect(std.mem.indexOf(u8, added, "\"mode\":\"ReleaseFast\"") != null);
    try testing.expect(std.mem.indexOf(u8, added, "\"metadata_reused\":true") != null);
    const ran = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{output} });
    defer testing.allocator.free(ran.stdout);
    defer testing.allocator.free(ran.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, ran.term);
    try testing.expect(std.mem.indexOf(u8, ran.stderr, "error[R_DIVISION_BY_ZERO]") != null);
    try testing.expect(std.mem.indexOf(u8, ran.stderr, "in divide at ") != null);
    try testing.expect(std.mem.indexOf(u8, ran.stderr, "in main at ") != null);
}
// spec: CLI-3
test "CLI executes the exact plan acceptance programs and recursive functions" {
    try invoke("run", @embedFile("fixtures/sum.my"), 0, "4950\n", "");
    try invoke("run", @embedFile("fixtures/gcd.my"), 0, "6\n", "");
    try invoke("run",
        \\def fact(n: i64) -> i64:
        \\    if n <= 1:
        \\        return 1
        \\    return n * fact(n - 1)
        \\
        \\
        \\def main() -> i64:
        \\    return fact(10)
    , 0, "3628800\n", "");
    try invoke("run",
        \\def main() -> i64:
        \\    return 1 + add(add(2, 3), add(4, 5))
        \\
        \\
        \\def add(a: i64, b: i64) -> i64:
        \\    return a + b
    , 0, "15\n", "");
    try invoke("run",
        \\def main() -> i64:
        \\    return bad()
        \\
        \\
        \\def bad() -> i64:
        \\    return divtrunc(1, 0)
    , 1, "", "in main at");
}
test "CLI frame budgets count main and reject invalid overrides" {
    const text =
        \\def main() -> i64:
        \\    return f()
        \\
        \\
        \\def f() -> i64:
        \\    return 7
    ;
    try invokeOptions("run", text, &.{"--max-frames=2"}, 0, "7\n", "");
    try invokeOptions("run", text, &.{"--max-frames=1"}, 1, "", "error[R_FRAME_LIMIT]");
    try invokeOptions("run", text, &.{ "--max-frames=2", "--max-steps=4" }, 0, "7\n", "");
    for ([_][]const u8{ "--max-frames=0", "--max-frames=-1", "--max-frames=+1", "--max-frames=", "--max-frames=abc", "--max-frames=18446744073709551616" }) |option| {
        try invokeOptions("run", text, &.{option}, 2, "", "usage:");
    }
    try invokeOptions("run", text, &.{ "--max-frames=2", "--max-frames=3" }, 2, "", "usage:");
    try invokeOptions("check", text, &.{"--max-frames=2"}, 2, "", "usage:");
    try invokeOptions("dump-bytecode", text, &.{"--max-frames=2"}, 2, "", "usage:");
}
test "all commands reject invalid programs before execution and locate runtime traps" {
    for ([_][]const u8{ "check", "run", "dump-bytecode" }) |command| {
        try invoke(command, @embedFile("fixtures/rejected.my"), 1, "", ":2:12: error[E_UNKNOWN_NAME]");
        try invoke(command, "", 1, "", "error[E_MAIN]");
        try invoke(command,
            \\def main() -> bool:
            \\    return True
        , 1, "", "error[E_TYPE]");
    }
    try invoke("check", @embedFile("fixtures/trap.my"), 0, "", "");
    try invoke("run", @embedFile("fixtures/trap.my"), 1, "", ":2:9: error[R_DIVISION_BY_ZERO]");
}
test "oversized source is a host resource failure with no result output" {
    const text = try testing.allocator.alloc(u8, 16 * 1024 * 1024 + 1);
    defer testing.allocator.free(text);
    @memset(text, ' ');
    try invoke("run", text, 2, "", "host failure:");
}
test "duplicate discovery is separate advisory analysis with explicit options" {
    const source =
        \\def a(n: i64) -> i64:
        \\    return n * 2 + 1
        \\
        \\
        \\def b(x: i64) -> i64:
        \\    return x * 2 + 1
        \\
        \\
        \\def main() -> i64:
        \\    return 7
    ;
    const outcome = try runFixture("discover-duplicates", source, &.{ "--min-nodes=1", "--population=reference", "--timings" });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stdout, "1 candidate groups") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stdout, "population=reference") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "discovery_ns=") != null);
    try invoke("check", source, 0, "", "");
    try invoke("run", source, 0, "7\n", "");
    try invoke("discover-duplicates",
        \\def main() -> i64:
        \\    return unknown
    , 1, "", "error[E_UNKNOWN_NAME]");
    for ([_][]const u8{ "--min-nodes=0", "--min-nodes=", "--min-nodes=-1", "--population=unknown", "--max-steps=10" }) |option| {
        try invokeOptions("discover-duplicates", source, &.{option}, 2, "", "usage:");
    }
    try invokeOptions("discover-duplicates", source, &.{ "--min-nodes=1", "--min-nodes=2" }, 2, "", "usage:");
    try invokeOptions("check", source, &.{"--min-nodes=1"}, 2, "", "usage:");
}
test "CLI checks runs and dumps records and declared complete conversions" {
    try invoke("run", @embedFile("fixtures/records.my"), 0, "12\n", "");
    try invoke("run", @embedFile("fixtures/conversions.my"), 0, "11\n", "");
    try invoke("check", @embedFile("fixtures/conversions.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/conversions.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    try testing.expect(std.mem.indexOf(u8, dumped.stdout, "conversion function to_view(source: Source) -> View") != null);
    try testing.expect(std.mem.indexOf(u8, dumped.stdout, "MAKE_RECORD") != null);
    const incomplete =
        \\class Source:
        \\    x: i64
        \\    added: bool
        \\
        \\
        \\class View:
        \\    y: i64
        \\
        \\
        \\conversion def convert(src: Source) -> View:
        \\    return View(y=src.x)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| {
        try invoke(command, incomplete, 1, "", "error[E_INCOMPLETE_CONVERSION]");
    }
}
test "CLI checks resource ownership completion and implicit cleanup effects without ambient access" {
    const source = @embedFile("fixtures/resources.my");
    try invoke("check", source, 0, "", "");
    try invokeOptions("run", source, &.{"--restrict"}, 2, "", "--restrict is active");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    for ([_][]const u8{ "ACQUIRE_RESOURCE", "COMPLETE_RESOURCE", "effects {filesystem}", "provider filesystem (owned)" }) |text| try testing.expect(std.mem.indexOf(u8, dumped.stdout, text) != null);
    const invalid =
        \\resource File: filesystem
        \\
        \\
        \\class Wrapper:
        \\    file: File
        \\
        \\
        \\def cleanup(input: Wrapper) -> i64 noio:
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_EFFECT_BOUND]");
}
test "CLI checks resource data operations effects and required mutation without ambient providers" {
    const source = @embedFile("fixtures/resource-io.my");
    try invoke("check", source, 0, "", "");
    try invokeOptions("run", source, &.{"--restrict"}, 2, "", "--restrict is active");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    for ([_][]const u8{ "RESOURCE_read", "RESOURCE_write", "effects {filesystem}" }) |text| try testing.expect(std.mem.indexOf(u8, dumped.stdout, text) != null);
    // A match arm binds its payload immutably, so writing through that binding still needs mutation.
    const invalid =
        \\resource File: filesystem
        \\
        \\result Open:
        \\    ok: File,
        \\    err: i64
        \\
        \\
        \\result Written:
        \\    ok: u64,
        \\    err: i64
        \\
        \\
        \\def write_once(fs: Filesystem) -> i64 effects(filesystem):
        \\    request: [1]u8 = [42u8]
        \\    match acquire_resource[Open](fs, request):
        \\        case Open.ok(file):
        \\            payload: [1]u8 = [7u8]
        \\            _ = write_resource[Written](file, payload)
        \\            return 0
        \\        case Open.err(code):
        \\            return code
        \\
        \\
        \\def main(fs: Filesystem) -> i64:
        \\    return write_once(fs)
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_IMMUTABLE]");
}
test "CLI approximate discovery is advisory explains drift and reports budget exhaustion" {
    const source =
        \\def a(x: i64) -> i64:
        \\    return x * 2 + 1
        \\
        \\
        \\def b(x: i64) -> i64:
        \\    return x * 2 + 3
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    const outcome = try runFixture("discover-duplicates", source, &.{ "--approximate", "--min-nodes=1" });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    for ([_][]const u8{ "near-v3", "near candidate:", "- 1", "+ 3", "Advisory only" }) |part| try testing.expect(std.mem.indexOf(u8, outcome.stdout, part) != null);
    const limited = try runFixture("discover-duplicates", source, &.{ "--approximate", "--min-nodes=1", "--max-work=1" });
    defer testing.allocator.free(limited.stdout);
    defer testing.allocator.free(limited.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, limited.term);
    try testing.expect(std.mem.indexOf(u8, limited.stdout, "Incomplete approximate search") != null);
    for ([_][]const []const u8{ &.{"--max-work=1"}, &.{ "--approximate", "--max-work=0" }, &.{ "--approximate", "--approximate" } }) |options| try invokeOptions("discover-duplicates", source, options, 2, "", "usage:");
    try invokeOptions("check", source, &.{"--approximate"}, 2, "", "usage:");
}
test "CLI static quality report uses advisory thresholds and rejects invalid options" {
    const source =
        \\def helper(x: i64) -> i64:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return helper(7)
    ;
    const outcome = try runFixture("report-quality", source, &.{"--max-line-bytes=1"});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    for ([_][]const u8{ "quality-v1", "calls helper", "reachable-from-main=true", "exceeds configured 1", "Runtime coverage and assertions: not measured" }) |part| try testing.expect(std.mem.indexOf(u8, outcome.stdout, part) != null);
    for ([_][]const []const u8{ &.{"--max-nesting=-1"}, &.{"--max-decisions="}, &.{ "--max-parameters=1", "--max-parameters=2" }, &.{"--max-steps=1"} }) |options| try invokeOptions("report-quality", source, options, 2, "", "usage:");
    try invokeOptions("run", source, &.{"--max-nesting=1"}, 2, "", "usage:");
    try invoke("report-quality",
        \\def main() -> i64:
        \\    return False
    , 1, "", "error[E_TYPE]");
}
test "CLI formatter supports stdout check mode and syntax-only formatting" {
    // `fmt` writes canonical bytes to stdout; `--check` is nonzero when the
    // input differs from that canonical form.
    const canonical =
        \\def main() -> i64:
        \\    return 7
        \\
    ;
    try invoke("fmt", canonical, 0, canonical, "");
    try invokeOptions("fmt", canonical, &.{"--check"}, 0, "", "");
    const spaced =
        \\def  main( ) ->  i64 :
        \\        return   7
    ;
    try invoke("fmt", spaced, 0, canonical, "");
    try invokeOptions("fmt", spaced, &.{"--check"}, 1, "", "formatting differs");
    try invoke("fmt",
        \\def main() -> i64:
        \\    return False
    , 0,
        \\def main() -> i64:
        \\    return False
        \\
    , "");
    try invoke("fmt",
        \\def main() -> i64:
        \\    return +
    , 1, "", "error[E_EXPRESSION]");
    try invokeOptions("fmt", canonical, &.{ "--check", "--check" }, 2, "", "usage:");
    try invokeOptions("check", canonical, &.{"--check"}, 2, "", "usage:");
}
test "CLI module discovery loads real files and diagnoses cross-file cycles" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDirPath(testing.io, "shared");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\module input
        \\import shared.data as data
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "shared/data.my", .data = "module shared.data\n" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "list-modules", path } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings("", result.stderr);
    const child = std.mem.indexOf(u8, result.stdout, "module shared.data path=shared/data.my sha256=").?;
    const root = std.mem.indexOf(u8, result.stdout, "module input path=input.my sha256=").?;
    try testing.expect(child < root);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "bodies/exports/types not checked") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "shared/data.my", .data = "module shared.data\nimport input\n" });
    const cycle = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "list-modules", path } });
    defer testing.allocator.free(cycle.stdout);
    defer testing.allocator.free(cycle.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, cycle.term);
    try testing.expectEqualStrings("", cycle.stdout);
    for ([_][]const u8{ "E_IMPORT_CYCLE", "shared/data.my:2:", "input.my:1:", "input -> shared.data -> input" }) |part| try testing.expect(std.mem.indexOf(u8, cycle.stderr, part) != null);
}
test "CLI module discovery keeps header validity separate from compilation" {
    const result = try runFixture("list-modules",
        \\module input
        \\def broken(
    , &.{});
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "header discovery only") != null);
    try invoke("list-modules",
        \\module input
        \\import missing
    , 1, "", "E_MODULE_READ");
    try invokeOptions("list-modules", "module input", &.{"--max-steps=10"}, 2, "", "usage:");
    const compilation = try runFixture("check",
        \\module input
        \\
        \\
        \\def main() -> i64:
        \\    return unknown()
    , &.{});
    defer testing.allocator.free(compilation.stdout);
    defer testing.allocator.free(compilation.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, compilation.term);
    try testing.expect(std.mem.indexOf(u8, compilation.stderr, "E_UNKNOWN_SYMBOL") != null);
}
test "CLI module interfaces parse bodies and check exported signature visibility" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\module input
        \\import units
        \\
        \\
        \\public class Sample:
        \\    distance: units.Distance
        \\
        \\
        \\def main() -> i64:
        \\    return unknown()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "units.my", .data =
        \\module units
        \\
        \\
        \\public domain Distance: i64:
        \\    def make(x: i64) -> Distance effects():
        \\        return wrap[Distance](x)
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "list-interfaces", path } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings("", result.stderr);
    for ([_][]const u8{ "bodies not type checked", "export type Sample", "export type Distance", "export function Distance.make" }) |part| try testing.expect(std.mem.indexOf(u8, result.stdout, part) != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "units.my", .data =
        \\module units
        \\
        \\
        \\domain Distance: i64:
        \\    def make(x: i64) -> Distance:
        \\        return wrap[Distance](x)
    });
    const hidden = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "list-interfaces", path } });
    defer testing.allocator.free(hidden.stdout);
    defer testing.allocator.free(hidden.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, hidden.term);
    try testing.expectEqualStrings("", hidden.stdout);
    for ([_][]const u8{ "E_PRIVATE_SYMBOL", "input.my:6:", "units.my:4:" }) |part| try testing.expect(std.mem.indexOf(u8, hidden.stderr, part) != null);
    try invoke("list-interfaces",
        \\module input
        \\def broken(
    , 1, "", "E_SYNTAX");
    try invoke("list-interfaces",
        \\module input
        \\
        \\
        \\class Secret:
        \\    pass
        \\
        \\
        \\public def f() -> Secret:
        \\    return Secret()
    , 1, "", "E_PRIVATE_INTERFACE");
    try invokeOptions("list-interfaces", "module input", &.{"--check"}, 2, "", "usage:");
}
// spec: INTERFACE-SIGNATURE-CLI-1
test "CLI list-interfaces renders capability parameters with their Python spelling" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\module input
        \\
        \\
        \\public def main(fs: Filesystem, clock: Clock) -> int:
        \\    return 0
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "list-interfaces", path } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Filesystem") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Clock") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "filesystem_cap") == null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "clock_cap") == null);
}
// spec: PROJ-5
test "CLI run loads a project entry that imports a standard module and leaves single-file run unchanged" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\module main
        \\import math
        \\
        \\
        \\def main() -> int:
        \\    return math.clamp(99, 0, 42)
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &(.{ compiler_path, "run", path, "--print-result" } ++ tools) });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    // `main` returns 42, and a run now exits with its int result.
    try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, result.term);
    try testing.expectEqualStrings("42\n", result.stdout);
    try testing.expectEqualStrings("", result.stderr);
    // `run-project` stays an explicit alias for the same entry.
    const alias = try std.process.run(testing.allocator, testing.io, .{ .argv = &(.{ compiler_path, "run-project", path, "--print-result" } ++ tools) });
    defer testing.allocator.free(alias.stdout);
    defer testing.allocator.free(alias.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, alias.term);
    try testing.expectEqualStrings("42\n", alias.stdout);
    // A plain single-file program still takes the original one-unit path.
    try invoke("run", @embedFile("fixtures/arithmetic.my"), 0, "7\n", "");
}
// spec: CHECK-PROJECT-ENTRY-1
test "CLI check on a CHECK-PROJECT-ENTRY-1 module project loads the reachable graph" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\module main
        \\import helper
        \\
        \\
        \\def main() -> int:
        \\    return helper.value()
    });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data =
        \\module helper
        \\
        \\
        \\public def value() -> int effects():
        \\    return 42
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(path);
    const checked = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check", path } });
    defer testing.allocator.free(checked.stdout);
    defer testing.allocator.free(checked.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
    try testing.expectEqualStrings("", checked.stdout);
    try testing.expectEqualStrings("", checked.stderr);
    const explicit = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-project", path } });
    defer testing.allocator.free(explicit.stdout);
    defer testing.allocator.free(explicit.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, explicit.term);
    try testing.expectEqualStrings("", explicit.stdout);
    try testing.expectEqualStrings("", explicit.stderr);
}
// spec: PROJ-7
test "CLI build loads a module project entry without --project" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(testing.io, "app", .default_dir);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "app/main.my", .data =
        \\module main
        \\import helper
        \\
        \\def main() -> int:
        \\    return helper.value()
    });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "app/helper.my", .data =
        \\module helper
        \\
        \\public def value() -> int effects():
        \\    return 42
    });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "app/main.my", testing.allocator);
    defer testing.allocator.free(entry);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "program" });
    defer testing.allocator.free(output);
    var link_argv: std.ArrayList([]const u8) = .empty;
    defer link_argv.deinit(testing.allocator);
    try link_argv.appendSlice(testing.allocator, &.{ compiler_path, "build", entry, "-o", output });
    try link_argv.appendSlice(testing.allocator, &tools);
    const link = try std.process.run(testing.allocator, testing.io, .{ .argv = link_argv.items });
    defer testing.allocator.free(link.stdout);
    defer testing.allocator.free(link.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, link.term);
    try testing.expectEqualStrings("", link.stderr);
    var reporting = try runtimeOptions("--print-result");
    defer reporting.deinit();
    const installed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{output}, .environ_map = &reporting });
    defer testing.allocator.free(installed.stdout);
    defer testing.allocator.free(installed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, installed.term);
    try testing.expectEqualStrings("42\n", installed.stdout);
}

// spec-case: NATIVE-TEST-1
test "CLI test discovers a test_ function without an explicit export" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\module main
        \\
        \\def test_add() -> bool:
        \\    return 1 + 1 == 2
        \\
        \\def main() -> int:
        \\    return 0
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, ".mylang-test-cache" });
    defer testing.allocator.free(cache);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "test", path, "--cache-dir", cache } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "1 passed") != null);
}

/// A guest test file whose one test passes.
const scratch_passing_program =
    \\module main
    \\
    \\def test_add() -> bool:
    \\    return 1 + 1 == 2
    \\
    \\def main() -> int:
    \\    return 0
;
/// A guest test file the checker rejects before any test is built.
const scratch_rejected_program =
    \\module main
    \\
    \\def test_add() -> bool:
    \\    return 1 + "two"
    \\
    \\def main() -> int:
    \\    return 0
;
/// Paths of one scratch-staging fixture: the entry, its private cache, the
/// compiler-child trace, and the directory offered as `TMPDIR`.
const ScratchFixture = struct { root: []const u8, entry: []const u8, cache: []const u8, trace: []const u8, scratch: []const u8 };
/// Write `program` as `main.my` and create an empty scratch directory beside it.
fn scratchFixture(temporary: *testing.TmpDir, program: []const u8) !ScratchFixture {
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = program });
    try temporary.dir.createDirPath(testing.io, "scratch");
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    return .{
        .root = try testing.allocator.dupe(u8, root),
        .entry = try std.fs.path.join(testing.allocator, &.{ root, "main.my" }),
        .cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" }),
        .trace = try std.fs.path.join(testing.allocator, &.{ root, "trace.log" }),
        .scratch = try std.fs.path.join(testing.allocator, &.{ root, "scratch" }),
    };
}
fn freeScratchFixture(fixture: ScratchFixture) void {
    for ([_][]const u8{ fixture.root, fixture.entry, fixture.cache, fixture.trace, fixture.scratch }) |path| testing.allocator.free(path);
}
/// Run `mylang test` on the fixture with a private environment: `TMPDIR` is the
/// fixture's scratch directory when `offer_scratch` is set and absent otherwise.
fn scratchRun(fixture: ScratchFixture, offer_scratch: bool) !std.process.RunResult {
    var environment: std.process.Environ.Map = .init(testing.allocator);
    defer environment.deinit();
    try environment.put("HOME", fixture.root);
    try environment.put("MYLANG_TEST_TRACE", fixture.trace);
    if (offer_scratch) try environment.put("TMPDIR", fixture.scratch);
    try forwardZigCache(&environment);
    const cache_arg = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{fixture.cache});
    defer testing.allocator.free(cache_arg);
    return spawnWithEnv(&.{ compiler_path, "test", fixture.entry, cache_arg, tools[0], tools[1] }, &environment);
}
/// The compiler-child trace the last run wrote, or empty when it spawned none.
fn scratchTrace(fixture: ScratchFixture) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(testing.io, fixture.trace, testing.allocator, .limited(1 << 20)) catch testing.allocator.dupe(u8, "");
}
/// Names directly under `directory`, sorted, joined by `,`.
fn scratchEntries(directory: []const u8) ![]u8 {
    var names: std.ArrayList([]const u8) = .empty;
    defer {
        for (names.items) |name| testing.allocator.free(name);
        names.deinit(testing.allocator);
    }
    var opened = try std.Io.Dir.cwd().openDir(testing.io, directory, .{ .iterate = true });
    defer opened.close(testing.io);
    var iterator = opened.iterate();
    while (try iterator.next(testing.io)) |entry| try names.append(testing.allocator, try testing.allocator.dupe(u8, entry.name));
    std.mem.sort([]const u8, names.items, {}, struct {
        fn less(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.less);
    return std.mem.join(testing.allocator, ",", names.items);
}

// spec: NATIVE-SCRATCH-ROOT-2
test "mylang test stages under TMPDIR, never under /tmp, and removes its staging after a passing run" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const fixture = try scratchFixture(&temporary, scratch_passing_program);
    defer freeScratchFixture(fixture);
    const result = try scratchRun(fixture, true);
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "1 passed") != null);
    const trace = try scratchTrace(fixture);
    defer testing.allocator.free(trace);
    const staged = try std.fs.path.join(testing.allocator, &.{ fixture.scratch, ".pending", "" });
    defer testing.allocator.free(staged);
    // Every compiler child read its snapshot from beneath TMPDIR's staging folder.
    try testing.expect(std.mem.indexOf(u8, trace, staged) != null);
    try testing.expect(std.mem.indexOf(u8, trace, "/tmp/.pending/") == null);
    // The run removed its private staging and the then-empty shared folder.
    const entries = try scratchEntries(fixture.scratch);
    defer testing.allocator.free(entries);
    try testing.expectEqualStrings("", entries);
}

// spec-case: NATIVE-SCRATCH-ROOT-2
test "mylang test leaves no staging behind when the project is rejected before any test builds" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const fixture = try scratchFixture(&temporary, scratch_rejected_program);
    defer freeScratchFixture(fixture);
    const result = try scratchRun(fixture, true);
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    const trace = try scratchTrace(fixture);
    defer testing.allocator.free(trace);
    const staged = try std.fs.path.join(testing.allocator, &.{ fixture.scratch, ".pending", "" });
    defer testing.allocator.free(staged);
    // The rejection came from a child that did stage under TMPDIR ...
    try testing.expect(std.mem.indexOf(u8, trace, staged) != null);
    // ... and the failing run still removed every staging directory it made.
    const entries = try scratchEntries(fixture.scratch);
    defer testing.allocator.free(entries);
    try testing.expectEqualStrings("", entries);
}

// spec-case: NATIVE-SCRATCH-ROOT-2
test "mylang test with TMPDIR unset falls back to staging under /tmp" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const fixture = try scratchFixture(&temporary, scratch_passing_program);
    defer freeScratchFixture(fixture);
    const result = try scratchRun(fixture, false);
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    const trace = try scratchTrace(fixture);
    defer testing.allocator.free(trace);
    try testing.expect(std.mem.indexOf(u8, trace, " /tmp/.pending/") != null);
    // The offered-but-unused scratch directory stays untouched.
    const entries = try scratchEntries(fixture.scratch);
    defer testing.allocator.free(entries);
    try testing.expectEqualStrings("", entries);
}

// spec-case: NATIVE-SCRATCH-OWNER-1
test "mylang test reclaims a killed run's marked staging and keeps unmarked scratch" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const fixture = try scratchFixture(&temporary, scratch_passing_program);
    defer freeScratchFixture(fixture);
    // What a SIGKILLed run leaves: its owned directory, marker unlocked because
    // the kernel dropped the dead holder's lock, and its half-written snapshot.
    try temporary.dir.createDirPath(testing.io, "scratch/.pending/0123456789abcdef0123456789abcdef/.pending/snapshot");
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "scratch/.pending/0123456789abcdef0123456789abcdef/.owner", .data = "" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "scratch/.pending/0123456789abcdef0123456789abcdef/.pending/snapshot/main.my", .data = "module main\n" });
    // Scratch without a marker is not provably this runner's, so it survives.
    try temporary.dir.createDirPath(testing.io, "scratch/.pending/foreign");
    const result = try scratchRun(fixture, true);
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    const pending = try std.fs.path.join(testing.allocator, &.{ fixture.scratch, ".pending" });
    defer testing.allocator.free(pending);
    const entries = try scratchEntries(pending);
    defer testing.allocator.free(entries);
    try testing.expectEqualStrings("foreign", entries);
}

// spec-case: NATIVE-TEST-1
test "CLI test ignores unexported test_ helpers that cannot default" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\module main
        \\
        \\def test_helper(value: int) -> bool:
        \\    return value > 0
        \\
        \\def test_count() -> int:
        \\    return 1
        \\
        \\def test_ok() -> bool:
        \\    return True
        \\
        \\def main() -> int:
        \\    return 0
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, ".mylang-test-cache" });
    defer testing.allocator.free(cache);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "test", path, "--cache-dir", cache } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "1 passed") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "test_helper") == null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "test_count") == null);
}

// spec-case: NATIVE-TEST-1
test "CLI test reports an exported ill-shaped test as a failed case" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\module main
        \\
        \\
        \\public def test_bad() -> int effects():
        \\    return 1
        \\
        \\
        \\public def test_ok() -> bool effects():
        \\    return True
        \\
        \\
        \\def main() -> int:
        \\    return 0
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, ".mylang-test-cache" });
    defer testing.allocator.free(cache);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "test", path, "--cache-dir", cache } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "failed main::test_bad") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "1 failed") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "host failure") == null);
}

// spec-case: CHECK-PROJECT-ENTRY-1
test "CLI check keeps plain single-file programs on the one-unit path" {
    try invoke("check",
        \\def main() -> int:
        \\    return 7
    , 0, "", "");
    try invoke("check",
        \\def main() -> int:
        \\    x = True
        \\    x = 1
        \\    return 7
    , 1, "", "E_TYPE");
}
// spec: CLI-6
test "CLI answers removed C-backend commands with their QBE migration" {
    try invokeOptions("emit-c", "def main() -> int:\n    return 0\n", &.{}, 2, "", "emit-qbe");
    try invokeOptions("emit-project-c", "module main\n\n\ndef main() -> int:\n    return 0\n", &.{}, 2, "", "emit-project-qbe");
}
test "CLI checks and runs module programs with private boundaries and cross-file traps" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\module input
        \\import helper
        \\
        \\
        \\def main() -> i64:
        \\    return helper.value()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data =
        \\module helper
        \\
        \\
        \\public def value() -> i64 effects():
        \\    return 42
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    for ([_][]const u8{ "check-project", "run-project" }) |command| {
        const reporting: []const []const u8 = if (std.mem.eql(u8, command, "run-project")) &.{"--print-result"} else &.{};
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(testing.allocator);
        try argv.appendSlice(testing.allocator, &.{ compiler_path, command, path });
        try argv.appendSlice(testing.allocator, reporting);
        if (std.mem.eql(u8, command, "run-project")) try argv.appendSlice(testing.allocator, &tools);
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items });
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        // `run-project` exits with the entry's `42`; `check-project` never runs it.
        const wanted: u8 = if (std.mem.eql(u8, command, "check-project")) 0 else 42;
        try testing.expectEqual(std.process.Child.Term{ .exited = wanted }, result.term);
        try testing.expectEqualStrings(if (std.mem.eql(u8, command, "check-project")) "" else "42\n", result.stdout);
        try testing.expectEqualStrings("", result.stderr);
    }
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data =
        \\module helper
        \\
        \\
        \\public def value() -> i64 effects():
        \\    return divtrunc(1, 0)
    });
    const trap = try std.process.run(testing.allocator, testing.io, .{ .argv = &(.{ compiler_path, "run-project", path, "--print-result" } ++ tools) });
    defer testing.allocator.free(trap.stdout);
    defer testing.allocator.free(trap.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, trap.term);
    for ([_][]const u8{ "R_DIVISION_BY_ZERO", "helper.my:5:", "input.my:6:" }) |part| try testing.expect(std.mem.indexOf(u8, trap.stderr, part) != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data =
        \\module helper
        \\
        \\
        \\def value() -> i64:
        \\    return 42
    });
    const hidden = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-project", path } });
    defer testing.allocator.free(hidden.stdout);
    defer testing.allocator.free(hidden.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, hidden.term);
    for ([_][]const u8{ "E_PRIVATE_SYMBOL", "helper.my:4:", "input.my:6:" }) |part| try testing.expect(std.mem.indexOf(u8, hidden.stderr, part) != null);
    try invokeOptions("run-project",
        \\module input
        \\
        \\
        \\def main() -> i64:
        \\    return 7
    , &.{"--max-steps=1"}, 1, "", "R_STEP_LIMIT");
    try invokeOptions("check-project",
        \\module input
        \\
        \\
        \\def main() -> i64:
        \\    return 7
    , &.{"--max-steps=1"}, 2, "", "usage:");
}
test "CLI checkProjectPolicy distinguishes language failures policy failures and configuration failures" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\module input
        \\import core
        \\
        \\
        \\def main() -> i64:
        \\    return core.value()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "core.my", .data =
        \\module core
        \\
        \\
        \\public def value() -> i64 effects():
        \\    return 7
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "rules file.json", .data = "{\"version\":1,\"default_action\":\"deny\",\"rules\":[]}" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const policy_path = try temp.dir.realPathFileAlloc(testing.io, "rules file.json", testing.allocator);
    defer testing.allocator.free(policy_path);
    const option = try std.fmt.allocPrint(testing.allocator, "--policy={s}", .{policy_path});
    defer testing.allocator.free(option);
    const denied = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-policy", path, option } });
    defer testing.allocator.free(denied.stdout);
    defer testing.allocator.free(denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, denied.term);
    try testing.expectEqualStrings("", denied.stderr);
    for ([_][]const u8{ "language: valid", "import-direction-v1: failed", "edges=1; denied=1", "input -> core: deny; rule=default" }) |part| try testing.expect(std.mem.indexOf(u8, denied.stdout, part) != null);
    const ordinary = try std.process.run(testing.allocator, testing.io, .{ .argv = &(.{ compiler_path, "run-project", path, "--print-result" } ++ tools) });
    defer testing.allocator.free(ordinary.stdout);
    defer testing.allocator.free(ordinary.stderr);
    // The entry returns 7, which is now the process exit status.
    try testing.expectEqual(std.process.Child.Term{ .exited = 7 }, ordinary.term);
    try testing.expectEqualStrings("7\n", ordinary.stdout);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "rules file.json", .data = "{\"version\":1,\"default_action\":\"allow\",\"rules\":[]}" });
    const allowed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-policy", path, option } });
    defer testing.allocator.free(allowed.stdout);
    defer testing.allocator.free(allowed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, allowed.term);
    try testing.expect(std.mem.indexOf(u8, allowed.stdout, "import-direction-v1: passed") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "rules file.json", .data = "{\"version\":99,\"default_action\":\"allow\",\"rules\":[]}" });
    const config_error = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-policy", path, option } });
    defer testing.allocator.free(config_error.stdout);
    defer testing.allocator.free(config_error.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, config_error.term);
    try testing.expectEqualStrings("", config_error.stdout);
    try testing.expect(std.mem.indexOf(u8, config_error.stderr, "UnsupportedPolicyVersion") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "core.my", .data =
        \\module core
        \\
        \\
        \\public def value() -> i64:
        \\    return True
    });
    const invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-policy", path, option } });
    defer testing.allocator.free(invalid.stdout);
    defer testing.allocator.free(invalid.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, invalid.term);
    try testing.expectEqualStrings("", invalid.stdout);
    try testing.expect(std.mem.indexOf(u8, invalid.stderr, "E_TYPE") != null);
    try invoke("check-policy",
        \\module input
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , 2, "", "usage:");
    try invokeOptions("check-project",
        \\module input
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , &.{"--policy=some.json"}, 2, "", "usage:");
    try invokeOptions("check-policy",
        \\module input
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , &.{ "--policy=a", "--policy=b" }, 2, "", "usage:");
}
// spec: LINT-1
test "CLI lint reports L_ findings and blocks only under --gate" {
    const source =
        \\module input
        \\
        \\
        \\public def compute(value: int) -> int:
        \\    "Compute the input plus one."
        \\    return helper(value)
        \\
        \\
        \\def helper(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\def unused_helper(value: int) -> int:
        \\    return value - 1
        \\
        \\
        \\public def test_compute() -> bool effects():
        \\    return compute(1) == 2
        \\
        \\
        \\def main() -> int:
        \\    return 0
    ;
    try invoke("lint", source, 0, "lint: 1 finding(s): 0 blocking, 1 report, 0 waived, 0 accepted\n", "warning[L_DEAD_PRIVATE]");
    try invokeOptions("lint", source, &.{"--gate"}, 3, "lint: 1 finding(s): 1 blocking, 0 report, 0 waived, 0 accepted\n", "error[L_DEAD_PRIVATE]");
    try invokeOptions("lint", source, &.{ "--gate", "--json" }, 3, "lint: 1 finding(s): 1 blocking, 0 report, 0 waived, 0 accepted\n", "\"code\":\"L_DEAD_PRIVATE\"");
    try invokeOptions("lint", source, &.{"--nope"}, 2, "", "usage:");
}
// spec-case: LINT-1
test "CLI lint test hygiene rules flag fake tests and leave expression tests alone" {
    const source =
        \\module input
        \\
        \\
        \\def square(value: int) -> int:
        \\    return value * value
        \\
        \\
        \\def test_expression() -> bool effects():
        \\    return square(3) == 9
        \\
        \\
        \\def test_fake() -> bool effects():
        \\    return True
        \\
        \\
        \\def test_conditional() -> bool effects():
        \\    if 1 == 1:
        \\        assert 1 == 1
        \\        return True
        \\    return False
        \\
        \\
        \\def main() -> int:
        \\    return 0
    ;
    try invokeOptions("lint", source, &.{"--gate"}, 3, "lint: 2 finding(s): 2 blocking, 0 report, 0 waived, 0 accepted\n", "L_TEST_NO_ASSERTION");
    try invokeOptions("lint", source, &.{ "--gate", "--json" }, 3, "lint: 2 finding(s): 2 blocking, 0 report, 0 waived, 0 accepted\n", "L_TEST_CONDITIONAL");
}
// spec-case: LINT-1
test "CLI lint advisory budget rules report only and never block under gate" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = "{\"version\":2,\"lint\":{\"rules\":{\"function-length\":{\"max\":1}}}}" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data =
        \\module app
        \\
        \\
        \\def value(input: int) -> int:
        \\    if input > 0:
        \\        return input
        \\    return 0
        \\
        \\
        \\def main() -> int:
        \\    return value(1)
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "app.my", testing.allocator);
    defer testing.allocator.free(path);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "lint", path, "--gate" } });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stdout, "0 blocking") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "L_FUNCTION_LENGTH") != null);
}
// spec-case: LINT-2
test "CLI warnings deny makes a checker warning rejecting in check and check-project" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data =
        \\module app
        \\
        \\
        \\def main() -> int:
        \\    unused: int = 1
        \\    return 0
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "app.my", testing.allocator);
    defer testing.allocator.free(path);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = "{\"version\":2,\"lint\":{\"warnings\":\"deny\"}}" });
    const denied = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check", path } });
    defer testing.allocator.free(denied.stdout);
    defer testing.allocator.free(denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, denied.term);
    try testing.expect(std.mem.indexOf(u8, denied.stderr, "W_UNUSED_BINDING") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = "{\"version\":2,\"lint\":{\"warnings\":\"report\"}}" });
    const reported = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check", path } });
    defer testing.allocator.free(reported.stdout);
    defer testing.allocator.free(reported.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, reported.term);
    try testing.expect(std.mem.indexOf(u8, reported.stderr, "W_UNUSED_BINDING") != null);
}
// spec-case: UNUSED-IMPORT-1
test "CLI check-project reports an import no reference resolves through" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data =
        \\module helper
        \\
        \\
        \\public def value() -> int:
        \\    return 42
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "unused_mod.my", .data =
        \\module unused_mod
        \\
        \\
        \\public def thing() -> int:
        \\    return 1
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\module main
        \\import helper
        \\import unused_mod
        \\
        \\
        \\def main() -> int:
        \\    note = "unused_mod.thing()"
        \\    return helper.value() - 42
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(path);
    const reported = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-project", path } });
    defer testing.allocator.free(reported.stdout);
    defer testing.allocator.free(reported.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, reported.term);
    try testing.expect(std.mem.indexOf(u8, reported.stderr, "W_UNUSED_IMPORT") != null);
    // The import the checker resolved through is not reported, and the alias
    // spelled inside a string literal is not a reference.
    try testing.expect(std.mem.indexOf(u8, reported.stderr, "`unused_mod`") != null);
    try testing.expect(std.mem.indexOf(u8, reported.stderr, "`helper`") == null);
    // A configured `warnings: "deny"` makes the warning rejecting, as for any
    // other `W_*` code.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = "{\"version\":2,\"lint\":{\"warnings\":\"deny\"}}" });
    const denied = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-project", path } });
    defer testing.allocator.free(denied.stdout);
    defer testing.allocator.free(denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, denied.term);
}
// spec-case: TESTS-FOR-1
test "CLI tests-for lists direct and transitive tests and rejects an unknown name" {
    const source =
        \\module input
        \\
        \\
        \\def parse(value: int) -> int:
        \\    return helper(value)
        \\
        \\
        \\def helper(value: int) -> int:
        \\    return value
        \\
        \\
        \\def test_parse() -> bool effects():
        \\    return parse(1) == 1
        \\
        \\
        \\def main() -> int:
        \\    return 0
    ;
    try invokeOptions("tests-for", source, &.{"input::helper"}, 0,
        \\tests-for input::helper
        \\  direct (0):
        \\  reached-by (1): input::test_parse
        \\
    , "");
    try invokeOptions("tests-for", source, &.{"input::parse"}, 0,
        \\tests-for input::parse
        \\  direct (1): input::test_parse
        \\  reached-by (1): input::test_parse
        \\
    , "");
    try invokeOptions("tests-for", source, &.{"input::missing"}, 2, "", "no checked declaration");
}
// spec-case: TESTS-FOR-SYNTAX-1
test "CLI tests-for answers a project that does not type-check from its syntax and accepts module.name" {
    const source =
        \\module input
        \\
        \\
        \\def parse(value: int) -> int:
        \\    return helper(value)
        \\
        \\
        \\def helper(value: int) -> int:
        \\    return value
        \\
        \\
        \\def test_parse() -> bool effects():
        \\    return parse(1) == 1
        \\
        \\
        \\def main() -> int:
        \\    return 0
    ;
    const red = try std.mem.replaceOwned(u8, testing.allocator, source, "    return value\n", "    return value + \"red\"\n");
    defer testing.allocator.free(red);
    try invokeOptions("tests-for", red, &.{"input.helper"}, 0,
        \\tests-for input::helper
        \\  direct (0):
        \\  reached-by (1): input::test_parse
        \\  basis: syntax (the project does not type-check; calls were resolved by name, not by checked types)
        \\
    , "error[E_TYPE]");
    try invokeOptions("tests-for", red, &.{"input.missing"}, 2, "", "no declaration has that qualified name");
    try invokeOptions("tests-for", source, &.{"input.parse"}, 0,
        \\tests-for input::parse
        \\  direct (1): input::test_parse
        \\  reached-by (1): input::test_parse
        \\
    , "");
    try invokeOptions("tests-for", "module input\n\n\ndef parse(value: int) -> int:\n    return +\n", &.{"input::parse"}, 1, "", "the project does not parse");
}
// spec-case: NAVIGATION-SELECT-1
test "CLI index-project prints the summary by default, the full document on --full and a selection per filter" {
    const source =
        \\module input
        \\
        \\
        \\def helper(value: int) -> int:
        \\    return value
        \\
        \\
        \\def main() -> int:
        \\    return helper(0)
    ;
    const summary = try runFixture("index-project", source, &.{});
    defer testing.allocator.free(summary.stdout);
    defer testing.allocator.free(summary.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, summary.term);
    try testing.expect(std.mem.startsWith(u8, summary.stdout, "{\"version\":\"navigation-summary-v1\",\"checked\":true,"));
    try testing.expect(std.mem.indexOf(u8, summary.stdout, "\"kinds\":{\"function\":2,\"parameter\":1}") != null);
    const full = try runFixture("index-project", source, &.{"--full"});
    defer testing.allocator.free(full.stdout);
    defer testing.allocator.free(full.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, full.term);
    try testing.expect(std.mem.startsWith(u8, full.stdout, "{\"version\":\"navigation-v1\",\"checked\":true,"));
    const selected = try runFixture("index-project", source, &.{ "--symbol", "input.helper" });
    defer testing.allocator.free(selected.stdout);
    defer testing.allocator.free(selected.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, selected.term);
    try testing.expect(std.mem.startsWith(u8, selected.stdout, "{\"version\":\"navigation-selection-v1\",\"status\":\"ok\","));
    try testing.expect(std.mem.indexOf(u8, selected.stdout, "\"resolved\":\"input::helper\"") != null);
    const missing = try runFixture("index-project", source, &.{"--module=absent"});
    defer testing.allocator.free(missing.stdout);
    defer testing.allocator.free(missing.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, missing.term);
    try testing.expect(std.mem.indexOf(u8, missing.stdout, "\"status\":\"missing\"") != null);
    try invokeOptions("index-project", source, &.{ "--full", "--module=input" }, 2, "", "usage:");
    try invokeOptions("index-project", source, &.{"--kind=method"}, 2, "", "usage:");
}
// spec-case: LINT-1
test "CLI lint undocumented-export reports under agent and blocks under strict" {
    const source =
        \\module input
        \\
        \\
        \\public def compute(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\def test_compute() -> bool effects():
        \\    return compute(1) == 2
        \\
        \\
        \\def main() -> int:
        \\    return 0
    ;
    try invoke("lint", source, 0, "lint: 1 finding(s): 0 blocking, 1 report, 0 waived, 0 accepted\n", "L_UNDOCUMENTED_EXPORT");
    try invokeOptions("lint", source, &.{ "--gate", "--profile=strict" }, 3, "lint: 1 finding(s): 1 blocking, 0 report, 0 waived, 0 accepted\n", "L_UNDOCUMENTED_EXPORT");
    const documented =
        \\module input
        \\
        \\
        \\public def compute(value: int) -> int:
        \\    "Compute the input plus one."
        \\    return value + 1
        \\
        \\
        \\def test_compute() -> bool effects():
        \\    return compute(1) == 2
        \\
        \\
        \\def main() -> int:
        \\    return 0
    ;
    try invokeOptions("lint", documented, &.{ "--gate", "--profile=strict" }, 0, "lint: 0 finding(s): 0 blocking, 0 report, 0 waived, 0 accepted\n", "");
}
// spec-case: API-DIFF-1
test "CLI api-diff records a baseline and classifies body and interface changes" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data =
        \\module app
        \\
        \\
        \\public def compute(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\def main() -> int:
        \\    return 0
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "app.my", testing.allocator);
    defer testing.allocator.free(path);
    const baseline = try std.fs.path.join(testing.allocator, &.{ root, "baseline.txt" });
    defer testing.allocator.free(baseline);
    const write_option = try std.fmt.allocPrint(testing.allocator, "--write={s}", .{baseline});
    defer testing.allocator.free(write_option);
    const against_option = try std.fmt.allocPrint(testing.allocator, "--against={s}", .{baseline});
    defer testing.allocator.free(against_option);
    const write = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "api-diff", path, write_option } });
    defer testing.allocator.free(write.stdout);
    defer testing.allocator.free(write.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, write.term);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data =
        \\module app
        \\
        \\
        \\public def compute(value: int) -> int:
        \\    return value + 2
        \\
        \\
        \\def main() -> int:
        \\    return 0
    });
    const body = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "api-diff", path, against_option } });
    defer testing.allocator.free(body.stdout);
    defer testing.allocator.free(body.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, body.term);
    try testing.expect(std.mem.indexOf(u8, body.stdout, "compatible=1") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data =
        \\module app
        \\
        \\
        \\public def compute(value: int, extra: int) -> int:
        \\    return value + extra
        \\
        \\
        \\def main() -> int:
        \\    return 0
    });
    const signature = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "api-diff", path, against_option, "--json" } });
    defer testing.allocator.free(signature.stdout);
    defer testing.allocator.free(signature.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, signature.term);
    try testing.expect(std.mem.indexOf(u8, signature.stdout, "\"breaking\":[\"app::compute\"]") != null);
    const missing = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "api-diff", path, "--against=absent.txt" } });
    defer testing.allocator.free(missing.stdout);
    defer testing.allocator.free(missing.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, missing.term);
}

/// The module the interface-file CLI fixtures publish, and its entry.
const api_app_source =
    \\module app
    \\
    \\
    \\public def compute(value: int) -> int:
    \\    return value + 1
    \\
;
const api_main_source =
    \\module main
    \\import app
    \\
    \\
    \\def main() -> int:
    \\    return app.compute(41) - 42
    \\
;

/// The interface file `api_app_source` renders.
const api_app_interface =
    \\# generated by mylang api; do not edit
    \\module app
    \\
    \\public def compute(value: int) -> int ceiling(managed_allocation)
    \\
;

/// One `mylang` run in the interface-file fixture directory with its own cache.
const ApiRun = struct {
    root: []const u8,
    entry: []const u8,
    cache: []const u8,

    fn run(self: ApiRun, command: []const u8, options: []const []const u8) !std.process.RunResult {
        // The fixture runs from its own directory, so the compiler is named absolutely.
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, testing.allocator);
        defer testing.allocator.free(compiler);
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(testing.allocator);
        try argv.appendSlice(testing.allocator, &.{ compiler, command, self.entry, self.cache });
        try argv.appendSlice(testing.allocator, options);
        return std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .path = self.root } });
    }
};

/// Run one command and return its exit code, stdout and stderr (caller frees both).
fn apiRun(fixture: ApiRun, command: []const u8, options: []const []const u8) !struct { code: u8, stdout: []u8, stderr: []u8 } {
    const result = try fixture.run(command, options);
    const code: u8 = switch (result.term) {
        .exited => |status| status,
        else => 255,
    };
    return .{ .code = code, .stdout = result.stdout, .stderr = result.stderr };
}

/// Assert one command's exit code and that `stdout` and `stderr` contain the
/// given fragments (an empty fragment matches anything).
fn expectApi(fixture: ApiRun, command: []const u8, options: []const []const u8, code: u8, stdout: []const u8, stderr: []const u8) !void {
    const result = try apiRun(fixture, command, options);
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try expectIncludes(stdout, result.stdout);
    try expectIncludes(stderr, result.stderr);
    try testing.expectEqual(code, result.code);
}

/// Pass when `actual` contains `fragment`; otherwise fail showing both.
fn expectIncludes(fragment: []const u8, actual: []const u8) !void {
    if (std.mem.indexOf(u8, actual, fragment) == null) try testing.expectEqualStrings(fragment, actual);
}

fn writeApiFixture(dir: std.Io.Dir) !void {
    try dir.writeFile(testing.io, .{ .sub_path = "app.my", .data = api_app_source });
    try dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = api_main_source });
}

// spec-case: API-FILE-2
test "CLI api --check and --write: exit codes, diff, json, body-edit stability and cache states" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    try writeApiFixture(temp.dir);
    const cold = ApiRun{ .root = root, .entry = "main.my", .cache = "--cache-dir=cold" };
    const warm = ApiRun{ .root = root, .entry = "main.my", .cache = "--cache-dir=warm" };

    try expectApi(cold, "api", &.{}, 2, "", "usage:");
    try expectApi(cold, "api", &.{ "--write", "--check" }, 2, "", "usage:");
    try expectApi(warm, "api", &.{"--check"}, 1, "api: app is missing (app.api)\n--- app.api\n+++ app.api (generated)\n@@ -0,0 +1,4 @@\n+# generated by mylang api; do not edit\n", "");
    try expectApi(warm, "api", &.{"--check"}, 1, "api: 2 interface files out of date; run `mylang api main.my --write`\n", "");
    try expectApi(warm, "api", &.{"--write"}, 0, "api: wrote app.api (app)\napi: wrote main.api (main)\napi: 2 interface files current (2 written, 0 deleted)\n", "");
    const warm_bytes = try temp.dir.readFileAlloc(testing.io, "app.api", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(warm_bytes);
    try testing.expectEqualStrings(api_app_interface, warm_bytes);

    // A cold cache, a warm one and no cache at all render the same bytes.
    try temp.dir.deleteFile(testing.io, "app.api");
    try expectApi(cold, "api", &.{"--write"}, 0, "api: wrote app.api (app)\n", "");
    const cold_bytes = try temp.dir.readFileAlloc(testing.io, "app.api", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(cold_bytes);
    try testing.expectEqualStrings(warm_bytes, cold_bytes);
    try expectApi(cold, "api", &.{"--check"}, 0, "api: 2 interface files current\n", "");
    try expectApi(warm, "api", &.{"--check"}, 0, "api: 2 interface files current\n", "");
    try expectApi(.{ .root = root, .entry = "main.my", .cache = "--no-cache" }, "api", &.{"--check"}, 0, "api: 2 interface files current\n", "");

    // A body edit leaves the file byte-identical; a signature edit does not.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data = "module app\n\n\npublic def compute(value: int) -> int:\n    # changed body\n    return 1 + value\n" });
    try expectApi(warm, "api", &.{"--write"}, 0, "api: 2 interface files current\n", "");
    const body_bytes = try temp.dir.readFileAlloc(testing.io, "app.api", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(body_bytes);
    try testing.expectEqualStrings(warm_bytes, body_bytes);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data = "module app\n\n\npublic def compute(value: int, extra: int = 1) -> int:\n    return value + extra\n" });
    try expectApi(warm, "api", &.{"--check"}, 1, "@@ -2,3 +2,3 @@\n module app\n \n-public def compute(value: int) -> int ceiling(managed_allocation)\n+public def compute(value: int, extra: int = 1) -> int ceiling(managed_allocation)\n", "");
    try expectApi(warm, "api", &.{ "--check", "--json" }, 1, "{\"version\":\"interface-files-v1\",\"mode\":\"check\",\"status\":\"stale\",\"files\":2,\"modules\":[{\"module\":\"app\",\"path\":\"app.api\",\"state\":\"stale\",\"added\":[],\"removed\":[],\"changed\":[\"compute\"]}]}\n", "");
    try expectApi(warm, "api", &.{ "--write", "--json" }, 0, "\"mode\":\"write\",\"status\":\"updated\"", "");
    try expectApi(warm, "api", &.{ "--check", "--json" }, 0, "{\"version\":\"interface-files-v1\",\"mode\":\"check\",\"status\":\"current\",\"files\":2,\"modules\":[]}\n", "");

    // A generated file whose source is gone is an orphan until --write deletes it.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "old.api", .data = "# generated by mylang api; do not edit\nmodule old\n" });
    try expectApi(warm, "api", &.{"--check"}, 1, "api: old is orphaned (old.api)\n", "");
    try expectApi(warm, "api", &.{"--write"}, 0, "api: deleted old.api (old)\n", "");
    try testing.expectError(error.FileNotFound, temp.dir.statFile(testing.io, "old.api", .{}));
}

/// The two-module fixture `mylang context` answers about: the entry imports
/// `model`, `model::validate` calls the private `check`, and the separate
/// `entry_value` export keeps `main` independent of `validate`'s signature so
/// the baseline fixture can change it without breaking the project.
const context_entry =
    \\module main
    \\import model
    \\
    \\
    \\def main() -> int:
    \\    return model.entry_value()
;

const context_model =
    \\module model
    \\
    \\
    \\public def validate(value: int) -> int:
    \\    total = value
    \\    return check(total)
    \\
    \\
    \\public def entry_value() -> int:
    \\    return 1
    \\
    \\
    \\def check(value: int) -> int:
    \\    return value + 1
;

/// `context_model` with a body-only edit: the same signature computes a
/// different result, which an interface baseline classifies as compatible.
const context_model_body_edit =
    \\module model
    \\
    \\
    \\public def validate(value: int) -> int:
    \\    total = value + 1
    \\    return check(total)
    \\
    \\
    \\public def entry_value() -> int:
    \\    return 1
    \\
    \\
    \\def check(value: int) -> int:
    \\    return value + 1
;

/// `context_model` with a breaking interface edit: `validate` gains a parameter
/// every caller would have to supply.
const context_model_signature_edit =
    \\module model
    \\
    \\
    \\public def validate(value: int, extra: int) -> int:
    \\    total = value + extra
    \\    return check(total)
    \\
    \\
    \\public def entry_value() -> int:
    \\    return 1
    \\
    \\
    \\def check(value: int) -> int:
    \\    return value + 1
;

/// The `model` module whose `validate` body carries `extra` straight-line
/// updates, so the complete answer about it is far wider than a small
/// `--context-bytes` budget and the envelope has to drop records.
fn wideContextModel(allocator: std.mem.Allocator, extra: usize) ![]u8 {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(allocator);
    try source.appendSlice(allocator, "module model\n\n\npublic def validate(value: int) -> int:\n    total = value\n");
    var line: usize = 0;
    while (line < extra) : (line += 1) {
        try source.appendSlice(allocator, "    total = total + 1\n");
    }
    try source.appendSlice(allocator, "    return check(total)\n\n\npublic def entry_value() -> int:\n    return 1\n\n\ndef check(value: int) -> int:\n    return value + 1\n");
    return source.toOwnedSlice(allocator);
}

/// Write `main.my` and `model.my` into `temporary` and return the allocated
/// entry path every `context` invocation names. The path keeps its sentinel, so
/// the caller frees exactly the allocation `realPathFileAlloc` made.
fn writeContextProject(temporary: *testing.TmpDir, model: []const u8) ![:0]u8 {
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = context_entry });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "model.my", .data = model });
    return temporary.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
}

/// Parse the one JSON object a successful `mylang context` prints, asserting
/// stdout holds nothing else around it.
fn parseContextAnswer(printed: []const u8) !std.json.Parsed(std.json.Value) {
    const body = std.mem.trim(u8, printed, " \t\r\n");
    try testing.expect(body.len > 1);
    try testing.expectEqual(@as(u8, '{'), body[0]);
    try testing.expectEqual(@as(u8, '}'), body[body.len - 1]);
    return std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
}

/// A required top-level string field of a context envelope.
fn contextString(answer: std.json.Value, key: []const u8) ![]const u8 {
    const value = answer.object.get(key) orelse return error.MissingContextField;
    if (value != .string) return error.ContextFieldNotString;
    return value.string;
}

/// A required top-level integer field of a context envelope.
fn contextInteger(answer: std.json.Value, key: []const u8) !i64 {
    const value = answer.object.get(key) orelse return error.MissingContextField;
    if (value != .integer) return error.ContextFieldNotInteger;
    return value.integer;
}

/// A required top-level array field of a context envelope.
fn contextArray(answer: std.json.Value, key: []const u8) ![]std.json.Value {
    const value = answer.object.get(key) orelse return error.MissingContextField;
    if (value != .array) return error.ContextFieldNotArray;
    return value.array.items;
}

/// Index of the first `sections` entry named `name`.
fn contextSectionIndex(answer: std.json.Value, name: []const u8) !usize {
    const sections = answer.object.get("sections") orelse return error.MissingContextSections;
    if (sections != .array) return error.ContextSectionsNotArray;
    for (sections.array.items, 0..) |section, index| {
        if (section != .object) continue;
        const field = section.object.get("name") orelse continue;
        if (field != .string) continue;
        if (std.mem.eql(u8, field.string, name)) return index;
    }
    return error.MissingContextSection;
}

/// The rendered JSON of one section, so a test can assert on a record's
/// vocabulary without pinning field order the implementation still owns.
fn contextSectionRendering(answer: std.json.Value, name: []const u8) ![]u8 {
    const sections = answer.object.get("sections") orelse return error.MissingContextSections;
    const index = try contextSectionIndex(answer, name);
    return std.json.Stringify.valueAlloc(testing.allocator, sections.array.items[index], .{});
}

/// The `declaration` section must name the declaration it is about.
fn expectDeclarationNames(answer: std.json.Value, needle: []const u8) !void {
    const rendered = try contextSectionRendering(answer, "declaration");
    defer testing.allocator.free(rendered);
    try testing.expect(std.mem.indexOf(u8, rendered, needle) != null);
}

/// The envelope echoes its question in `selector`; only the shape is asserted,
/// because its rendering is still moving.
fn expectContextSelectorShape(answer: std.json.Value) !void {
    const selector = answer.object.get("selector") orelse return error.MissingContextField;
    switch (selector) {
        .string => |text| try testing.expect(text.len > 0),
        .object => |object| try testing.expect(object.count() > 0),
        else => return error.ContextSelectorShape,
    }
}

/// A rejected request must not print a successful envelope: stdout is either
/// empty or one JSON object whose `status` is not `ok`.
fn expectNoContextOk(printed: []const u8) !void {
    const body = std.mem.trim(u8, printed, " \t\r\n");
    if (body.len == 0) return;
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return;
    const status = parsed.value.object.get("status") orelse return;
    if (status != .string) return;
    try testing.expect(!std.mem.eql(u8, status.string, "ok"));
}

/// Run `mylang context` with `options` and require `expected_status`, with no
/// successful envelope printed.
fn expectContextRejected(entry: []const u8, options: []const []const u8, expected_status: u8) !void {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "context", entry });
    try args.appendSlice(testing.allocator, options);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = expected_status }, outcome.term);
    try expectNoContextOk(outcome.stdout);
}

/// A usage mistake prints nothing on stdout and the usage text on stderr.
fn expectContextUsage(entry: []const u8, options: []const []const u8) !void {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "context", entry });
    try args.appendSlice(testing.allocator, options);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, outcome.term);
    try testing.expectEqualStrings("", outcome.stdout);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "usage:") != null);
}

/// An incomplete project must not publish an `ok` verdict: either the
/// envelope's own status says so, or the analysis record inside it reports that
/// checking did not complete.
fn expectUncheckedVerdict(answer: std.json.Value) !void {
    const status = try contextString(answer, "status");
    if (!std.mem.eql(u8, status, "ok")) return;
    inline for (.{ "analysis", "analysis_status" }) |key| {
        if (answer.object.get(key)) |analysis| {
            const rendered = try std.json.Stringify.valueAlloc(testing.allocator, analysis, .{});
            defer testing.allocator.free(rendered);
            try testing.expect(std.mem.indexOf(u8, rendered, "checked") == null);
            return;
        }
    }
    return error.IncompleteProjectClaimedChecked;
}

// spec-case: CONTEXT-SECTIONS-1
// spec-case: CONTEXT-ENVELOPE-1
test "CLI context answers a symbol question with declaration before contract" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const path = try writeContextProject(&temp, context_model);
    defer testing.allocator.free(path);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "context", path, "--symbol", "model::validate", "--format=json" } });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expectEqualStrings("", outcome.stderr);
    const answer = try parseContextAnswer(outcome.stdout);
    defer answer.deinit();
    try testing.expectEqualStrings("agent-context-v1", try contextString(answer.value, "version"));
    try testing.expectEqualStrings("ok", try contextString(answer.value, "status"));
    try expectContextSelectorShape(answer.value);
    try testing.expect(try contextInteger(answer.value, "emitted_bytes") > 0);
    try testing.expect(try contextInteger(answer.value, "emitted_bytes") <= 8192);
    const declaration = try contextSectionIndex(answer.value, "declaration");
    const contract = try contextSectionIndex(answer.value, "contract");
    try testing.expect(declaration < contract);
    try expectDeclarationNames(answer.value, "validate");
}

// spec-case: CONTEXT-BUDGET-1
test "CLI context keeps emitted bytes within the requested budget" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const model = try wideContextModel(testing.allocator, 200);
    defer testing.allocator.free(model);
    const path = try writeContextProject(&temp, model);
    defer testing.allocator.free(path);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "context", path, "--symbol", "model::validate", "--context-bytes=1200" } });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    const answer = try parseContextAnswer(outcome.stdout);
    defer answer.deinit();
    const emitted = try contextInteger(answer.value, "emitted_bytes");
    try testing.expect(emitted > 0);
    // The budget covers the whole serialized response, JSON escaping included,
    // so even a response that had to drop records stays inside it.
    try testing.expect(emitted <= 1200);
    try testing.expect((try contextString(answer.value, "status")).len > 0);
    const omissions = try contextArray(answer.value, "omissions");
    try testing.expect(omissions.len > 0);
    try testing.expect((try contextString(answer.value, "continuation")).len > 0);
}

// spec-case: CONTEXT-SELECT-1
test "CLI context rejects a symbol no declaration carries" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const path = try writeContextProject(&temp, context_model);
    defer testing.allocator.free(path);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "context", path, "--symbol", "model::no_such_function" } });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, outcome.term);
    try expectNoContextOk(outcome.stdout);
}

// spec-case: CONTEXT-SELECT-1
test "CLI context refuses an unqualified name that two modules both declare" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\module main
        \\import alpha
        \\import beta
        \\
        \\
        \\def main() -> int:
        \\    return alpha.first() + beta.second()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "alpha.my", .data =
        \\module alpha
        \\
        \\
        \\public def validate(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\public def first() -> int:
        \\    return 1
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "beta.my", .data =
        \\module beta
        \\
        \\
        \\public def validate(value: int) -> int:
        \\    return value + 2
        \\
        \\
        \\public def second() -> int:
        \\    return 2
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(path);
    // Both `alpha::validate` and `beta::validate` exist, so the bare name is
    // genuinely ambiguous rather than unknown...
    const qualified = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "context", path, "--symbol", "alpha::validate" } });
    defer testing.allocator.free(qualified.stdout);
    defer testing.allocator.free(qualified.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, qualified.term);
    const answer = try parseContextAnswer(qualified.stdout);
    defer answer.deinit();
    try testing.expectEqualStrings("agent-context-v1", try contextString(answer.value, "version"));
    // ...and `--symbol` takes a module-qualified name, so the command refuses
    // to choose between the two rather than silently picking one.
    try expectContextRejected(path, &.{ "--symbol", "validate" }, 2);
}

// spec-case: CONTEXT-AT-1
test "CLI context resolves a source position and rejects unusable coordinates" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const path = try writeContextProject(&temp, context_model);
    defer testing.allocator.free(path);
    // `context_model` line 5 column 5 is inside `validate`'s body.
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "context", path, "--at", "model.my:5:5" } });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    const answer = try parseContextAnswer(outcome.stdout);
    defer answer.deinit();
    try testing.expectEqualStrings("agent-context-v1", try contextString(answer.value, "version"));
    try expectDeclarationNames(answer.value, "validate");
    // A file that is not in the project, and two malformed coordinate strings.
    try expectContextRejected(path, &.{ "--at", "ghost.my:1:1" }, 2);
    try expectContextRejected(path, &.{ "--at", "model.my:not-a-coordinate" }, 2);
    try expectContextRejected(path, &.{ "--at", "model.my" }, 2);
}

// spec-case: CONTEXT-SELECT-1
// spec-case: CONTEXT-BUDGET-1
test "CLI context rejects missing conflicting and malformed options" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const path = try writeContextProject(&temp, context_model);
    defer testing.allocator.free(path);
    // Neither selector, and both selectors.
    try expectContextUsage(path, &.{});
    try expectContextUsage(path, &.{ "--symbol", "model::validate", "--at", "model.my:5:5" });
    // A budget below the documented minimum, at the boundary and far below it,
    // and one that is not a number at all.
    try expectContextUsage(path, &.{ "--symbol", "model::validate", "--context-bytes=1023" });
    try expectContextUsage(path, &.{ "--symbol", "model::validate", "--context-bytes=10" });
    try expectContextUsage(path, &.{ "--symbol", "model::validate", "--context-bytes=abc" });
    // JSON is the only accepted format.
    try expectContextUsage(path, &.{ "--symbol", "model::validate", "--format=xml" });
}

// A `--against=FILE` path the process cannot read is reported before any
// classification runs: `contextOptions` answers `error.BaselineUnreadable`,
// which the command turns into the same usage-level failure a malformed
// baseline gets, and never into an answer with a silently absent changes
// section. Both spellings of the flag take the same path.
// spec-case: CONTEXT-SECTIONS-1
test "CLI context reports an unreadable baseline as error.BaselineUnreadable" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const path = try writeContextProject(&temp, context_model);
    defer testing.allocator.free(path);
    const root = std.fs.path.dirname(path).?;
    const missing = try std.fs.path.join(testing.allocator, &.{ root, "no-such-baseline.txt" });
    defer testing.allocator.free(missing);
    const attached = try std.fmt.allocPrint(testing.allocator, "--against={s}", .{missing});
    defer testing.allocator.free(attached);
    try expectUnreadableBaseline(path, &.{ "--symbol", "model::validate", attached });
    try expectUnreadableBaseline(path, &.{ "--symbol", "model::validate", "--against", missing });
}

/// Run `mylang context` with one unreadable baseline spelling and require the
/// usage-level failure with its message, printing no envelope at all.
fn expectUnreadableBaseline(entry: []const u8, options: []const []const u8) !void {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "context", entry });
    try args.appendSlice(testing.allocator, options);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, outcome.term);
    try testing.expectEqualStrings("", outcome.stdout);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "cannot read or classify the baseline") != null);
}

// spec-case: CONTEXT-PARTIAL-1
test "CLI context answers an incomplete project without checked facts" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    // `validate` declares an `int` result and returns `True`, so the project's
    // bodies do not check; the command still owes a parseable answer.
    const broken_model =
        \\module model
        \\
        \\
        \\public def validate(value: int) -> int:
        \\    return True
        \\
        \\
        \\public def entry_value() -> int:
        \\    return 1
    ;
    const path = try writeContextProject(&temp, broken_model);
    defer testing.allocator.free(path);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "context", path, "--symbol", "model::validate" } });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    const answer = try parseContextAnswer(outcome.stdout);
    defer answer.deinit();
    try testing.expectEqualStrings("agent-context-v1", try contextString(answer.value, "version"));
    try expectUncheckedVerdict(answer.value);
}

// spec-case: CONTEXT-SECTIONS-1
test "CLI context classifies a declaration against an api-diff baseline" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const path = try writeContextProject(&temp, context_model);
    defer testing.allocator.free(path);
    const baseline = try std.fs.path.join(testing.allocator, &.{ root, "baseline.txt" });
    defer testing.allocator.free(baseline);
    const write_option = try std.fmt.allocPrint(testing.allocator, "--write={s}", .{baseline});
    defer testing.allocator.free(write_option);
    const against_option = try std.fmt.allocPrint(testing.allocator, "--against={s}", .{baseline});
    defer testing.allocator.free(against_option);
    const write = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "api-diff", path, write_option } });
    defer testing.allocator.free(write.stdout);
    defer testing.allocator.free(write.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, write.term);
    // A body-only edit stays compatible; `main` calls the untouched
    // `entry_value`, so the project still checks.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "model.my", .data = context_model_body_edit });
    const body = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "context", path, "--symbol", "model::validate", against_option } });
    defer testing.allocator.free(body.stdout);
    defer testing.allocator.free(body.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, body.term);
    const body_answer = try parseContextAnswer(body.stdout);
    defer body_answer.deinit();
    const body_changes = try contextSectionRendering(body_answer.value, "changes");
    defer testing.allocator.free(body_changes);
    try testing.expect(std.mem.indexOf(u8, body_changes, "compatible") != null);
    // A signature change is breaking.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "model.my", .data = context_model_signature_edit });
    const signature = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "context", path, "--symbol", "model::validate", against_option } });
    defer testing.allocator.free(signature.stdout);
    defer testing.allocator.free(signature.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, signature.term);
    const signature_answer = try parseContextAnswer(signature.stdout);
    defer signature_answer.deinit();
    const signature_changes = try contextSectionRendering(signature_answer.value, "changes");
    defer testing.allocator.free(signature_changes);
    try testing.expect(std.mem.indexOf(u8, signature_changes, "breaking") != null);
}

/// Run one git subcommand in `root`, asserting a zero exit. `std.process.run`
/// ignores the child's stdin, so git cannot disturb the test harness protocol.
fn gitIn(allocator: std.mem.Allocator, root: []const u8, args: []const []const u8) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.appendSlice(allocator, &.{ "git", "-C", root });
    try argv.appendSlice(allocator, args);
    const result = try std.process.run(allocator, testing.io, .{ .argv = argv.items });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

// spec-case: CHANGE-WITHOUT-TEST-1
test "CLI lint change-without-test blocks a changed helper only under gate and against" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\module main
        \\
        \\
        \\def helper(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\def test_helper() -> bool effects():
        \\    return helper(1) == 2
        \\
        \\
        \\def main() -> int:
        \\    return 0
    });
    try gitIn(testing.allocator, root, &.{ "init", "-q" });
    try gitIn(testing.allocator, root, &.{ "add", "main.my" });
    try gitIn(testing.allocator, root, &.{ "-c", "user.email=test@example.com", "-c", "user.name=test", "commit", "-q", "-m", "init" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\module main
        \\
        \\
        \\def helper(value: int) -> int:
        \\    return value + 2
        \\
        \\
        \\def test_helper() -> bool effects():
        \\    return helper(1) == 2
        \\
        \\
        \\def main() -> int:
        \\    return 0
    });
    const path = try std.fs.path.join(testing.allocator, &.{ root, "main.my" });
    defer testing.allocator.free(path);
    const flagged = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "lint", path, "--gate", "--against=HEAD" } });
    defer testing.allocator.free(flagged.stdout);
    defer testing.allocator.free(flagged.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, flagged.term);
    try testing.expect(std.mem.indexOf(u8, flagged.stderr, "L_CHANGE_WITHOUT_TEST") != null);
    const silent = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "lint", path, "--gate" } });
    defer testing.allocator.free(silent.stdout);
    defer testing.allocator.free(silent.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, silent.term);
}
// spec: AFFECTED-TEST-1
test "CLI test affected selects tests that reach a changed declaration" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const before =
        \\module app
        \\
        \\
        \\def helper(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\def test_helper() -> bool effects():
        \\    return helper(1) == 2
        \\
        \\
        \\def test_unrelated() -> bool effects():
        \\    return 3 == 3
        \\
        \\
        \\def main() -> int:
        \\    return 0
    ;
    const after =
        \\module app
        \\
        \\
        \\def helper(value: int) -> int:
        \\    return value + 2
        \\
        \\
        \\def test_helper() -> bool effects():
        \\    return helper(1) == 3
        \\
        \\
        \\def test_unrelated() -> bool effects():
        \\    return 3 == 3
        \\
        \\
        \\def main() -> int:
        \\    return 0
    ;
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data = before });
    try gitIn(testing.allocator, root, &.{ "init", "-q" });
    try gitIn(testing.allocator, root, &.{ "add", "app.my" });
    try gitIn(testing.allocator, root, &.{ "-c", "user.email=test@example.com", "-c", "user.name=test", "commit", "-q", "-m", "init" });
    const path = try std.fs.path.join(testing.allocator, &.{ root, "app.my" });
    defer testing.allocator.free(path);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    // An unchanged tree derives nothing: the selection is empty and exits 3,
    // exactly as a filter that matches nothing does.
    const empty = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "test", path, "--affected", "--against=HEAD", "--cache-dir", cache } });
    defer testing.allocator.free(empty.stdout);
    defer testing.allocator.free(empty.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, empty.term);
    try testing.expect(std.mem.indexOf(u8, empty.stderr, "affected: 0 selected, 2 skipped against HEAD") != null);
    // Editing the helper selects only the test that reaches it.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data = after });
    const selected = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "test", path, "--affected", "--against=HEAD", "--cache-dir", cache } });
    defer testing.allocator.free(selected.stdout);
    defer testing.allocator.free(selected.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, selected.term);
    try testing.expect(std.mem.indexOf(u8, selected.stderr, "affected: 1 selected, 1 skipped against HEAD") != null);
    try testing.expect(std.mem.indexOf(u8, selected.stderr, "skipped app::test_unrelated") != null);
    // The two switches are only meaningful together, and a bad reference is a
    // host failure rather than an empty selection.
    const without = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "test", path, "--against=HEAD", "--cache-dir", cache } });
    defer testing.allocator.free(without.stdout);
    defer testing.allocator.free(without.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, without.term);
    const alone = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "test", path, "--affected", "--cache-dir", cache } });
    defer testing.allocator.free(alone.stdout);
    defer testing.allocator.free(alone.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, alone.term);
    const unresolvable = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "test", path, "--affected", "--against=no-such-revision", "--cache-dir", cache } });
    defer testing.allocator.free(unresolvable.stdout);
    defer testing.allocator.free(unresolvable.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, unresolvable.term);
    try testing.expect(std.mem.indexOf(u8, unresolvable.stderr, "git cannot resolve") != null);
}
// spec-case: LINT-3
test "CLI lint accept records a baseline that gate then accepts" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data =
        \\module app
        \\
        \\
        \\def helper() -> int:
        \\    return 1
        \\
        \\
        \\def main() -> int:
        \\    return 0
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "app.my", testing.allocator);
    defer testing.allocator.free(path);
    const before = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "lint", path, "--gate" } });
    defer testing.allocator.free(before.stdout);
    defer testing.allocator.free(before.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, before.term);
    const accept = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "lint", path, "--accept" } });
    defer testing.allocator.free(accept.stdout);
    defer testing.allocator.free(accept.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, accept.term);
    const after = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "lint", path, "--gate" } });
    defer testing.allocator.free(after.stdout);
    defer testing.allocator.free(after.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, after.term);
    try testing.expect(std.mem.indexOf(u8, after.stdout, "1 accepted") != null);
}
test "CLI discovers cross module duplicates with options and rejects invalid dependencies" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\module input
        \\import helper
        \\
        \\
        \\def twice(value: i64) -> i64:
        \\    return value * 2 + 3
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data =
        \\module helper
        \\
        \\
        \\def copy(x: i64) -> i64:
        \\    return x * 2 + 3
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "discover-project-duplicates", path, "--min-nodes=1", "--approximate", "--max-work=1", "--population=reference", "--timings" } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    for ([_][]const u8{ "scope: reachable module graph", "population=reference", "input::twice", "helper::copy", "input.my:5:", "helper.my:4:", "approximate near-v3", "truncated=true" }) |part| try testing.expect(std.mem.indexOf(u8, result.stdout, part) != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "project_frontend_ns=") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "modules=2") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data =
        \\module helper
        \\
        \\
        \\def copy(x: i64) -> i64:
        \\    return True
    });
    const invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "discover-project-duplicates", path } });
    defer testing.allocator.free(invalid.stdout);
    defer testing.allocator.free(invalid.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, invalid.term);
    try testing.expectEqualStrings("", invalid.stdout);
    try testing.expect(std.mem.indexOf(u8, invalid.stderr, "E_TYPE") != null);
    try invokeOptions("discover-project-duplicates",
        \\module input
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , &.{"--max-work=1"}, 2, "", "usage:");
    try invokeOptions("discover-project-duplicates",
        \\module input
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , &.{"--max-steps=1"}, 2, "", "usage:");
}
test "CLI module quality reports preserve export roots and advisory thresholds" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\module input
        \\import api
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "api.my", .data =
        \\module api
        \\
        \\
        \\public def entry() -> i64 effects():
        \\    return hidden()
        \\
        \\
        \\def hidden() -> i64:
        \\    return 1
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "report-project-quality", path, "--max-function-lines=1" } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    // `import api` exists only to pull `api.my` into the reachable graph, so the
    // unused-import warning names it and nothing else is written to stderr.
    try testing.expectEqualStrings("input.my:2:8: warning[W_UNUSED_IMPORT]: import `api` is never referenced in this module; remove it or use it\n  import api\n         ^\n", result.stderr);
    for ([_][]const u8{ "quality-modules-v1", "api.my:4:", "api::entry; private=false; reachable-from-main=false", "module-exported=true reachable-from-exports=true", "module-exported=false reachable-from-exports=true", "function-lines 2 exceeds configured 1", "calls api::hidden at api.my:5:", "Runtime coverage and assertions: not measured" }) |part| try testing.expect(std.mem.indexOf(u8, result.stdout, part) != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "no call path from main or exported interfaces") == null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "api.my", .data =
        \\module api
        \\
        \\
        \\def invalid() -> i64:
        \\    return True
    });
    const invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "report-project-quality", path } });
    defer testing.allocator.free(invalid.stdout);
    defer testing.allocator.free(invalid.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, invalid.term);
    try testing.expectEqualStrings("", invalid.stdout);
    try testing.expect(std.mem.indexOf(u8, invalid.stderr, "E_TYPE") != null);
    try invokeOptions("report-project-quality",
        \\module input
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , &.{"--approximate"}, 2, "", "usage:");
}
test "CLI module formatting is syntax only and canonical for every reachable module" {
    // The header directive group is followed by one blank line and top-level
    // declarations by two, so the fixtures below are already canonical.
    const draft =
        \\module input
        \\import absent as a
        \\
        \\def f(x: a.T) -> a.T:
        \\    return x
        \\
    ;
    try invoke("fmt-module", draft, 0, draft, "");
    try invokeOptions("fmt-module", draft, &.{"--check"}, 0, "", "");
    try invoke("fmt-module",
        \\module input
        \\def broken(
    , 1, "", "E_SYNTAX");
    const root_module =
        \\module input
        \\import child
        \\
        \\def main() -> i64:
        \\    return unknown()
        \\
    ;
    const child_module =
        \\module child
        \\
        \\def f() -> Missing:
        \\    return unknown()
        \\
    ;
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = root_module });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "child.my", .data = child_module });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    // Neither module type checks; the formatter still reaches and accepts both.
    const clean = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "fmt-project", path, "--check" } });
    defer testing.allocator.free(clean.stdout);
    defer testing.allocator.free(clean.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, clean.term);
    try testing.expectEqualStrings("", clean.stdout);
    try testing.expectEqualStrings("", clean.stderr);
    for ([_][]const u8{ "input.my", "child.my" }) |name| {
        const absolute = try temp.dir.realPathFileAlloc(testing.io, name, testing.allocator);
        defer testing.allocator.free(absolute);
        const output = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "fmt-module", absolute } });
        defer testing.allocator.free(output.stdout);
        defer testing.allocator.free(output.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, output.term);
        try testing.expectEqualStrings(if (std.mem.eql(u8, name, "input.my")) root_module else child_module, output.stdout);
    }
    try temp.dir.writeFile(testing.io, .{ .sub_path = "child.my", .data =
        \\module child
        \\def broken(
    });
    const invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "fmt-project", path, "--check" } });
    defer testing.allocator.free(invalid.stdout);
    defer testing.allocator.free(invalid.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, invalid.term);
    try testing.expect(std.mem.indexOf(u8, invalid.stderr, "E_SYNTAX") != null);
    try testing.expect(std.mem.indexOf(u8, invalid.stderr, "formatting differs") == null);
    try invoke("fmt-project", "module input", 2, "", "usage:");
    try invokeOptions("fmt-module", "module input", &.{"--max-steps=1"}, 2, "", "usage:");
}
// spec: CLI-4
test "CLI schema inputs load fresh generated modules and reject malformed manifests" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "values.json", .data =
        \\{"version":1,"module":"config","values":[{"name":"value","type":"i64","value":"7"}]}
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "values.json", testing.allocator);
    defer testing.allocator.free(path);
    const option = try std.fmt.allocPrint(testing.allocator, "--inputs={s}", .{path});
    defer testing.allocator.free(option);
    const source =
        \\module input
        \\import config
        \\
        \\
        \\public def read() -> i64 effects():
        \\    return config.value()
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    const result = try runFixture("schema-project", source, &.{option});
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "input::read") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "values.json", .data = "{}" });
    try invokeOptions("schema-project", source, &.{option}, 2, "", "MissingField");
    try invokeOptions("schema-project", source, &.{ option, option }, 2, "", "usage:");
}
fn sessionScript(script: []const u8, flags: []const []const u8, expected_status: u8) ![]u8 {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\module input
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "commands", .data = script });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const input = try temp.dir.openFile(testing.io, "commands", .{});
    defer input.close(testing.io);
    const output = try temp.dir.createFile(testing.io, "replies", .{});
    defer output.close(testing.io);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "check-session", path });
    try args.appendSlice(testing.allocator, flags);
    var child = try std.process.spawn(testing.io, .{ .argv = args.items, .stdin = .{ .file = input }, .stdout = .{ .file = output }, .stderr = .ignore });
    defer child.kill(testing.io);
    try testing.expectEqual(std.process.Child.Term{ .exited = expected_status }, try child.wait(testing.io));
    return temp.dir.readFileAlloc(testing.io, "replies", testing.allocator, .limited(16384));
}
// spec: CLI-5
test "CLI check session reuses parses and clears retained storage" {
    const replies = try sessionScript("check\ncheck\nclear\ncheck\nquit\n", &.{}, 0);
    defer testing.allocator.free(replies);
    try testing.expect(std.mem.indexOf(u8, replies, "\"version\":\"check-session-v1\"") != null);
    try testing.expect(std.mem.indexOf(u8, replies, "\"semantic\":{\"hits\":1,\"misses\":1") != null);
    try testing.expect(std.mem.indexOf(u8, replies, "\"retained_bytes\":0") != null);
    try testing.expect(std.mem.indexOf(u8, replies, "\"status\":1") == null);
    try testing.expect(std.mem.indexOf(u8, replies, "\"status\":2") == null);
}
test "CLI sessionCheck returns host failure without terminating the session" {
    const replies = try sessionScript("check\nclear\nquit\n", &.{"--inputs=/nonexistent-mylang-manifest/inputs.json"}, 0);
    defer testing.allocator.free(replies);
    try testing.expect(std.mem.indexOf(u8, replies, "\"failure\":\"FileNotFound\"") != null);
    try testing.expect(std.mem.indexOf(u8, replies, "\"action\":\"quit\",\"status\":0") != null);
}
test "CLI executes generic fixed arrays and reports uncalled template shape errors" {
    try invoke("run",
        \\def twice[T: integer](x: T) -> [2]T:
        \\    return [x, x + x]
        \\
        \\
        \\def main() -> i64:
        \\    return twice[i64](6)[1]
    , 0, "12\n", "");
    try invokeOptions("check",
        \\def bad[T](a: [2]T) -> [3]T:
        \\    return a
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_GENERIC_TYPE\"");
}
test "CLI formats nominal templates and runs programs with unused declarations" {
    const source =
        \\class Box[T]:
        \\    value: T
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    try invoke("fmt", source, 0,
        \\class Box[T]:
        \\    value: T
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        \\
    , "");
    try invokeOptions("run", source, &.{"--diagnostics=json"}, 0, "0\n", "");
}
test "CLI reports unused nominal template requirement errors" {
    try invokeOptions("check",
        \\class Key[T: equality]:
        \\    value: T
        \\
        \\
        \\class Bad[U]:
        \\    key: Key[U]
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_GENERIC_REQUIREMENT\"");
    try invokeOptions("check",
        \\class Bad[T]:
        \\    value: Missing
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_UNKNOWN_TYPE\"");
}
test "CLI rejects recursive nominal layouts but preserves finite nested and phantom forms" {
    try invokeOptions("check",
        \\record Node[T]:
        \\    next: Node[T]
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_RECURSIVE_RECORD\"");
    try invokeOptions("check",
        \\class Box[T]:
        \\    value: T
        \\
        \\
        \\class Empty[T]:
        \\    pass
        \\
        \\
        \\class Finite[U]:
        \\    nested: Box[Box[U]]
        \\    phantom: Empty[Finite[[1]U]]
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , &.{"--diagnostics=json"}, 0, "", "");
}
test "CLI executes concrete nominal instances and reports argument identity errors" {
    const definitions =
        \\class Box[T]:
        \\    value: T
        \\
        \\
        \\union Slot[T]:
        \\    none,
        \\    some: T
    ;
    const program = definitions ++ "\n\n\n" ++
        \\def main() -> i64:
        \\    slot: Slot[Box[i64]] = Slot.some(Box[i64](value=12))
        \\    match slot:
        \\        case Slot.none:
        \\            return 0
        \\        case Slot.some(box):
        \\            return box.value
    ;
    try invoke("run", program, 0, "12\n", "");
    try invokeOptions("check", definitions ++ "\n\n\n" ++
        \\def takes(box: Box[i64]) -> i64:
        \\    return box.value
        \\
        \\
        \\def main() -> i64:
        \\    return takes(Box[bool](value=True))
    , &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_TYPE\"");
}
test "CLI specializes nominal generic bodies and reports uncalled shape errors" {
    const definitions =
        \\class Box[T]:
        \\    value: T
    ;
    try invoke("run", definitions ++ "\n\n\n" ++
        \\def pack[T](x: T) -> Box[T]:
        \\    return Box[T](value=x)
        \\
        \\
        \\def main() -> i64:
        \\    return pack[i64](31).value
    , 0, "31\n", "");
    try invokeOptions("check", definitions ++ "\n\n\n" ++
        \\def bad[T](x: T) -> Box[T]:
        \\    return Box[T](value=1)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_GENERIC_TYPE\"");
}
// spec: DEPENDENCIES-1
test "CLI project-dependencies buildIndex emits checked graph identity and rejects invalid bodies" {
    const outcome = try runFixture("project-dependencies",
        \\module input
        \\
        \\
        \\def main() -> i64:
        \\    return 7
    , &.{});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, outcome.stdout, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("project-dependencies-v1", parsed.value.object.get("version").?.string);
    try testing.expect(parsed.value.object.get("complete").?.bool);
    try testing.expectEqualStrings("input.my", parsed.value.object.get("inputs").?.array.items[0].object.get("path").?.string);
    try testing.expectEqual(@as(usize, 64), parsed.value.object.get("implementation").?.object.get("compiler_sha256").?.string.len);
    try invoke("project-dependencies",
        \\module input
        \\
        \\
        \\def main() -> i64:
        \\    return True
    , 1, "", "E_TYPE");
    try invoke("project-dependencies",
        \\module input
        \\export absent
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , 1, "", "error[E_EXPORT_REMOVED]");
}
// spec: CLI-HELP-1
test "CLI help answers on stdout with the everyday commands first and exits 0" {
    for ([_][]const u8{ "--help", "-h", "help" }) |flag| {
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, flag } });
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
        try testing.expectEqualStrings("", result.stderr);
        try testing.expect(std.mem.startsWith(u8, result.stdout, "mylang: a Python-shaped"));
        const everyday = std.mem.indexOf(u8, result.stdout, "mylang check FILE.my").?;
        const reference = std.mem.indexOf(u8, result.stdout, "usage: mylang test").?;
        try testing.expect(everyday < reference);
        // The guides and the large-project commands are on the first screen too.
        try testing.expect(std.mem.indexOf(u8, result.stdout, "mylang docs primer").? < everyday);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "mylang docs [TOPIC]").? < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "--release").? < reference);
        const large = std.mem.indexOf(u8, result.stdout, "Working in a large project:").?;
        try testing.expect(everyday < large and large < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "mylang context ENTRY.my --symbol=module::name").? < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "mylang tests-for ENTRY.my module::name").? < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "--affected --against REF").? < reference);
    }
}
// spec-case: CLI-DOCS-1
test "CLI docs lists the embedded guides and prints one from a directory with no docs" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, testing.allocator);
    defer testing.allocator.free(compiler);
    const listed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler, "docs" }, .cwd = .{ .dir = temporary.dir } });
    defer testing.allocator.free(listed.stdout);
    defer testing.allocator.free(listed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, listed.term);
    try testing.expectEqualStrings("", listed.stderr);
    try testing.expect(std.mem.indexOf(u8, listed.stdout, "  primer ").? < std.mem.indexOf(u8, listed.stdout, "  build ").?);
    const primer = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler, "docs", "primer" }, .cwd = .{ .dir = temporary.dir } });
    defer testing.allocator.free(primer.stdout);
    defer testing.allocator.free(primer.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, primer.term);
    try testing.expect(std.mem.startsWith(u8, primer.stdout, "# mylang in one page"));
    try testing.expect(std.mem.indexOf(u8, primer.stdout, "--release") != null);
    const unknown = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "docs", "nonsense" } });
    defer testing.allocator.free(unknown.stdout);
    defer testing.allocator.free(unknown.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, unknown.term);
    try testing.expect(std.mem.indexOf(u8, unknown.stderr, "no topic `nonsense`") != null);
}
// spec: FEATURE-REPORT-1
test "CLI features identify installed compiler without source input" {
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "--features" } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings("", result.stderr);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, result.stdout, .{});
    defer parsed.deinit();
    const report = parsed.value.object;
    try testing.expectEqualStrings("language-features-v1", report.get("version").?.string);
    try testing.expectEqual(@as(usize, 64), report.get("compiler_sha256").?.string.len);
    try testing.expectEqualStrings("qbe", report.get("features").?.object.get("primary_backend").?.string);
    // The identity is the compiler's embedded build-time digest, not a fresh hash of its
    // own executable, so a receipt from the same compiler reports exactly the same value.
    const receipt = try runFixture("project-dependencies",
        \\module input
        \\
        \\
        \\def main() -> i64:
        \\    return 7
    , &.{});
    defer testing.allocator.free(receipt.stdout);
    defer testing.allocator.free(receipt.stderr);
    const graph = try std.json.parseFromSlice(std.json.Value, testing.allocator, receipt.stdout, .{});
    defer graph.deinit();
    try testing.expectEqualStrings(report.get("compiler_sha256").?.string, graph.value.object.get("implementation").?.object.get("compiler_sha256").?.string);
}
// spec: FEATURE-REPORT-2
test "every implemented feature carries a kind, a summary and a documentation pointer" {
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "--features" } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, result.stdout, .{});
    defer parsed.deinit();
    const features = parsed.value.object.get("features").?.object;
    const implemented = features.get("implemented").?.object;
    try testing.expect(implemented.count() > 80);
    var entries = implemented.iterator();
    while (entries.next()) |entry| {
        const feature = entry.value_ptr.*.object;
        const kind = feature.get("kind").?.string;
        try testing.expect(std.mem.eql(u8, kind, "language") or std.mem.eql(u8, kind, "tooling"));
        try testing.expect(feature.get("summary").?.string.len > 0);
        const pointer = feature.get("doc").?.string;
        try testing.expect(std.mem.indexOf(u8, pointer, ".md#") != null);
        try testing.expect(std.mem.indexOf(u8, pointer, "..") == null);
    }
    // A slug whose form no longer exists is retired with a date and a note, not deleted.
    const retired = features.get("removed").?.object.get("record-literals-without-new").?.object;
    try testing.expectEqualStrings("2026-09-13", retired.get("date").?.string);
    try testing.expect(retired.get("note").?.string.len > 0);
}
const listing_module =
    \\module input
    \\import math
    \\import shared.units as units
    \\
    \\
    \\# leading comment
    \\# second line
    \\public type Count = i64
    \\
    \\
    \\const LIMIT: Count = 3 # trailing note
    \\
    \\
    \\class Job:
    \\    id: Count
    \\
    \\
    \\host def measure(host: Host, x: i64) -> i64 effects(host)
    \\
    \\
    \\
    \\
    \\public def main() -> i64:
    \\    return LIMIT
;
const Listing = struct {
    version: []const u8,
    module: ?[]const u8,
    header: ?Extent,
    imports: []const struct { name: []const u8, alias: ?[]const u8, bytes: Extent },
    exports: []const struct { name: []const u8, bytes: Extent },
    declarations: []const struct { kind: []const u8, name: []const u8, exported: bool, bytes: Extent, comment_start: usize },
    const Extent = struct { start: usize, end: usize };
};
fn expectTrivia(text: []const u8) !void {
    var at: usize = 0;
    while (at < text.len) {
        if (std.ascii.isWhitespace(text[at])) {
            at += 1;
            continue;
        }
        if (text[at] != '#') return error.UnaccountedSourceByte;
        at = std.mem.indexOfScalarPos(u8, text, at, '\n') orelse text.len;
    }
}
// spec: DECLARATION-LIST-2
test "CLI declaration listing accounts for every byte with disjoint ordered ranges" {
    const outcome = try runFixture("list-declarations", listing_module, &.{});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expectEqualStrings("", outcome.stderr);
    const parsed = try std.json.parseFromSlice(Listing, testing.allocator, outcome.stdout, .{});
    defer parsed.deinit();
    const listing = parsed.value;
    try testing.expectEqualStrings("declarations-v1", listing.version);
    try testing.expectEqualStrings("input", listing.module.?);
    try testing.expectEqualStrings("units", listing.imports[1].alias.?);
    try testing.expectEqual(@as(usize, 5), listing.declarations.len);
    var ranges: std.ArrayList(Listing.Extent) = .empty;
    defer ranges.deinit(testing.allocator);
    try ranges.append(testing.allocator, listing.header.?);
    for (listing.imports) |imported| try ranges.append(testing.allocator, imported.bytes);
    for (listing.exports) |exported| try ranges.append(testing.allocator, exported.bytes);
    var previous: usize = 0;
    for (listing.declarations) |declaration| {
        try testing.expect(declaration.bytes.start >= previous);
        try testing.expect(declaration.comment_start <= declaration.bytes.start);
        previous = declaration.bytes.start;
        try ranges.append(testing.allocator, .{ .start = declaration.comment_start, .end = declaration.bytes.end });
    }
    std.mem.sort(Listing.Extent, ranges.items, {}, struct {
        fn before(_: void, a: Listing.Extent, b: Listing.Extent) bool {
            return a.start < b.start;
        }
    }.before);
    var accounted: usize = 0;
    for (ranges.items) |range| {
        try testing.expect(range.start >= accounted and range.end > range.start);
        try expectTrivia(listing_module[accounted..range.start]);
        accounted = range.end;
    }
    try expectTrivia(listing_module[accounted..]);
    try testing.expect(listing.declarations[0].comment_start < listing.declarations[0].bytes.start);
    try testing.expect(listing.declarations[3].exported == false and listing.declarations[4].exported);
}
test "CLI declaration listing separates parse failures from checking and usage failures" {
    try invoke("list-declarations",
        \\def main() -> i64:
        \\    return 1 +
    , 1, "", "error[E_EXPRESSION]");
    try invokeOptions("list-declarations",
        \\module m
        \\export absent
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_EXPORT_REMOVED\"");
    try invokeOptions("list-declarations",
        \\def main() -> i64:
        \\    return 0
    , &.{"--check"}, 2, "", "usage:");
    const unchecked =
        \\module m
        \\
        \\
        \\def main() -> i64:
        \\    flag: bool = 1
        \\    return flag
    ;
    const outcome = try runFixture("list-declarations", unchecked, &.{});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stdout, "\"kind\":\"fn\",\"name\":\"main\"") != null);
}
test "CLI executes control flow and preserves discarded traps" {
    try invoke("run",
        \\def main() -> i64:
        \\    sum = 0
        \\    i = 0
        \\    while i < 100:
        \\        sum += i
        \\        i += 1
        \\    return sum
    , 0, "4950\n", "");
    try invoke("run",
        \\def main() -> i64:
        \\    if False and divtrunc(1, 0) == 0:
        \\        return 1
        \\    else:
        \\        return 7
    , 0, "7\n", "");
    try invoke("run",
        \\def main() -> i64:
        \\    _ = divtrunc(1, 0)
        \\    return 7
    , 1, "", "error[R_DIVISION_BY_ZERO]");
    try invoke("run",
        \\def main() -> i64:
        \\    while True:
        \\        return 7
    , 0, "7\n", "");
    try invoke("check",
        \\def main() -> i64:
        \\    while True:
        \\        break
    , 1, "", "error[E_MISSING_RETURN]");
}
test "all commands preserve stdout and deterministic advisory stderr" {
    const source = @embedFile("fixtures/warnings.my");
    const commands = [_][]const u8{ "check", "run", "dump-bytecode" };
    const outputs = [_][]const u8{ "", "7\n", @embedFile("fixtures/warnings.dump") };
    for (commands, outputs) |command, expected| {
        const outcome = try runFixture(command, source, &.{});
        defer testing.allocator.free(outcome.stdout);
        defer testing.allocator.free(outcome.stderr);
        // Only `run` executes the guest; its entry returns 7, now the exit status.
        const wanted: u8 = if (std.mem.eql(u8, command, "run")) 7 else 0;
        try testing.expectEqual(std.process.Child.Term{ .exited = wanted }, outcome.term);
        try testing.expectEqualStrings(expected, outcome.stdout);
        try testing.expect(std.mem.indexOf(u8, outcome.stderr, ":2:5: warning[W_UNUSED_BINDING]") != null);
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, outcome.stderr, "warning["));
        try testing.expect(std.mem.indexOf(u8, outcome.stderr, "`_ =`") != null);
    }
}
test "CLI preserves integer width bounds and explicit casts" {
    try invoke("run", @embedFile("fixtures/integers.my"), 0, "6148914691236516950\n", "");
    try invoke("check",
        \\def main() -> i64:
        \\    _ = u8(256)
        \\    return 0
    , 0, "", "");
    try invoke("run",
        \\def main() -> i64:
        \\    _ = u8(256)
        \\    return 0
    , 1, "", "error[R_OVERFLOW]");
    try invoke("run",
        \\def main() -> i64:
        \\    _ = 255u8 + 1u8
        \\    return 0
    , 1, "", "error[R_OVERFLOW]");
    try invoke("check",
        \\def main() -> i64:
        \\    _ = 256u8
        \\    return 0
    , 1, "", "error[E_INTEGER_RANGE]");
    try invoke("check",
        \\def main() -> u8:
        \\    return 0u8
    , 1, "", "error[E_TYPE]");
}
test "CLI checks array schemas dumps indexing and reports bounds traps" {
    try invoke("run", @embedFile("fixtures/arrays.my"), 0, "44\n", "");
    try invoke("check", @embedFile("fixtures/arrays.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/arrays.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    for ([_][]const u8{ "array [3]i64", "GET_INDEX [3]i64", "REPLACE_INDEX [3]i64", "ARRAY_LENGTH [3]i64" }) |instruction| {
        try testing.expect(std.mem.indexOf(u8, dumped.stdout, instruction) != null);
    }
    const invalid =
        \\def main() -> i64:
        \\    values: [3]i64 = [1]
        \\    return values[0]
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| {
        try invoke(command, invalid, 1, "", "error[E_ARRAY_LENGTH]");
    }
    const bounds =
        \\def main() -> i64:
        \\    values: [1]i64 = [7]
        \\    return values[1]
    ;
    try invoke("check", bounds, 0, "", "");
    try invoke("run", bounds, 1, "", ":3:12: error[R_LIST_BOUNDS]");
    try invoke("run",
        \\def main() -> i64:
        \\    payload: [1]u8 = [7u8]
        \\    _ = replace(payload, 18446744073709551615u64, 8u8)
        \\    return 0
    , 1, "", "error[R_LIST_BOUNDS]");
}
test "CLI checks domain privacy unit mismatches and qualified factory execution" {
    try invoke("run", @embedFile("fixtures/domains.my"), 0, "1003\n", "");
    try invoke("check", @embedFile("fixtures/domains.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/domains.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    for ([_][]const u8{ "domain Millimeters", "private function Millimeters.raw", "WRAP_DOMAIN Millimeters", "UNWRAP_DOMAIN Seconds" }) |instruction| {
        try testing.expect(std.mem.indexOf(u8, dumped.stdout, instruction) != null);
    }
    const private =
        \\domain D: i64:
        \\    private def raw(n: i64) -> D:
        \\        return wrap[D](n)
        \\
        \\
        \\def main() -> i64:
        \\    _ = D.raw(1)
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| {
        try invoke(command, private, 1, "", "error[E_PRIVATE_FUNCTION]");
    }
    try invoke("check",
        \\domain D: i64:
        \\    def make(n: i64) -> D:
        \\        return wrap[D](n)
        \\
        \\
        \\def main() -> i64:
        \\    _ = wrap[D](1)
        \\    return 0
    , 1, "", "error[E_PRIVATE_DOMAIN]");
    try invoke("check",
        \\domain Seconds: i64:
        \\    def from(n: i64) -> Seconds:
        \\        return wrap[Seconds](n)
        \\
        \\
        \\domain Millimeters: i64:
        \\    def of(n: i64) -> Millimeters:
        \\        return wrap[Millimeters](n)
        \\
        \\
        \\def distance(n: Millimeters) -> i64:
        \\    _ = n
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return distance(Seconds.from(1))
    , 1, "", "expected Millimeters, found Seconds");
}
test "CLI executes variants dumps dispatch and rejects newly incomplete matches" {
    try invoke("run", @embedFile("fixtures/variants.my"), 0, "24\n", "");
    try invoke("check", @embedFile("fixtures/variants.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/variants.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    for ([_][]const u8{ "enum Color", "union Shape", "MAKE_VARIANT Shape.point", "SWITCH_VARIANT Shape" }) |instruction| try testing.expect(std.mem.indexOf(u8, dumped.stdout, instruction) != null);
    const added =
        \\enum Color:
        \\    red,
        \\    green,
        \\    added
        \\
        \\
        \\def main() -> i64:
        \\    match Color.red:
        \\        case Color.red:
        \\            return 1
        \\        case Color.green:
        \\            return 2
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, added, 1, "", "match does not handle variant `added`");
    try invoke("check",
        \\union U:
        \\    value: i64,
        \\    empty
        \\
        \\
        \\def main() -> i64:
        \\    _ = U.value(True)
        \\    return 0
    , 1, "", "error[E_TYPE]");
    try invoke("run",
        \\union U:
        \\    value: i64
        \\
        \\
        \\def main() -> i64:
        \\    match U.value(divtrunc(1, 0)):
        \\        case U.value(_):
        \\            return 0
    , 1, "", "error[R_DIVISION_BY_ZERO]");
}
test "CLI executes complete enum tables and rejects missing mappings in every command" {
    try invoke("run", @embedFile("fixtures/tables.my"), 0, "1407\n", "");
    try invoke("check", @embedFile("fixtures/tables.my"), 0, "", "");
    const dumped = try runFixture("dump-bytecode", @embedFile("fixtures/tables.my"), &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expectEqualStrings("", dumped.stderr);
    for ([_][]const u8{ "table [Status]u16", "GET_INDEX [Status]u16", "REPLACE_INDEX [Status]u16" }) |instruction| try testing.expect(std.mem.indexOf(u8, dumped.stdout, instruction) != null);
    const added =
        \\enum Key:
        \\    old,
        \\    added
        \\
        \\
        \\def main() -> i64:
        \\    table: [Key]i64 = {Key.old: 7}
        \\    return table[Key.old]
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, added, 1, "", "missing initializer for key `added`");
    try invoke("check",
        \\enum Key:
        \\    a
        \\
        \\
        \\def main() -> i64:
        \\    table: [Key]i64 = {Key.a: 7}
        \\    return table[0]
    , 1, "", "expected Key, found int");
    // A positional list cannot stand in for an enum-keyed table; only named entries reach one.
    try invoke("check",
        \\enum Key:
        \\    a
        \\
        \\
        \\def main() -> i64:
        \\    table: [Key]i64 = [7]
        \\    return table[Key.a]
    , 1, "", "error[E_LIST_TYPE]");
}
test "CLI handles recoverable results and rejects silent error loss" {
    const source = @embedFile("fixtures/results.my");
    try invoke("run", source, 0, "7\n", "");
    try invoke("check", source, 0, "", "");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    for ([_][]const u8{ "result Quotient", "ACKNOWLEDGE Quotient" }) |text| try testing.expect(std.mem.indexOf(u8, dumped.stdout, text) != null);
    const ignored =
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\def main() -> i64:
        \\    r: R = Err(7)
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, ignored, 1, "", "error[E_RESULT_UNHANDLED]");
    try invoke("check",
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\def make() -> R:
        \\    return Ok(1)
        \\
        \\
        \\def main() -> i64:
        \\    make()
        \\    return 0
    , 1, "", "error[E_EXPLICIT_DISCARD_REQUIRED]");
}
// spec-case: CLOCK-INTRINSIC-1
test "CLI checks external capabilities but cannot silently grant ambient providers" {
    const source = @embedFile("fixtures/external-capabilities.my");
    try checkProjectClean(source);
    try invokeProjectOptions("run", source, &.{"--restrict"}, 2, "", "--restrict is active");
    const emitted = try runProjectFixture("emit-project-qbe", source, &.{});
    defer testing.allocator.free(emitted.stdout);
    defer testing.allocator.free(emitted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, emitted.term);
    // The clock and random modules lower to the same provider boundary the raw
    // spellings did, so the emitted program still carries both reads.
    try testing.expect(std.mem.indexOf(u8, emitted.stdout, "myl_qbe_external_read") != null);
    const invalid =
        \\module main
        \\import time
        \\
        \\
        \\def main(c: Clock) -> int effects():
        \\    _ = time.now(c)
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "emit-project-qbe", "discover-project-duplicates" }) |command| try invokeProject(command, invalid, 1, "", "error[E_EFFECT_BOUND]");
}
test "CLI checks bounded environment access without granting ambient process access" {
    const source = @embedFile("fixtures/environment.my");
    try invoke("check", source, 0, "", "");
    try invokeOptions("run", source, &.{"--restrict"}, 2, "", "--restrict is active");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    for ([_][]const u8{ "ENVIRONMENT_GET", "effects {environment}" }) |text| try testing.expect(std.mem.indexOf(u8, dumped.stdout, text) != null);
    const invalid =
        \\def main(env: Environment) -> i64 effects():
        \\    _ = env.get("K")
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_EFFECT_BOUND]");
}
// spec: CAPABILITY-METHOD-NARROWING-2
test "CLI exposes fs.read_only permission attenuation and rejects the removed spelling" {
    const source = @embedFile("fixtures/attenuation.my");
    try invoke("check", source, 0, "", "");
    try invokeOptions("run", source, &.{"--restrict"}, 2, "", "--restrict is active");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expect(std.mem.indexOf(u8, dumped.stdout, "RESTRICT_RESOURCE permissions=1 -> filesystem_cap") != null);
    try testing.expect(std.mem.indexOf(u8, dumped.stdout, "DIR_RESOURCE -> filesystem_cap") != null);
    const invalid =
        \\def main(fs: Filesystem) -> i64:
        \\    _ = restrict_resource[read, read](fs)
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_REMOVED_SPELLING]");
    const extra =
        \\def main(fs: Filesystem) -> i64:
        \\    _ = fs.read_only(1)
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, extra, 1, "", "error[E_ARITY]");
}
// spec: NETWORK-HOST-1
test "CLI narrows a Network to one literal endpoint and rejects a dynamic host" {
    const source =
        \\resource Socket: network
        \\
        \\result Open:
        \\    ok: Socket,
        \\    err: int
        \\
        \\def main(net: Network) -> int:
        \\    scoped = net.host("127.0.0.1:8000")
        \\    request: [1]u8 = [0u8]
        \\    match acquire_resource[Open](scoped, request):
        \\        case Open.ok(socket):
        \\            _ = socket
        \\            return 0
        \\        case Open.err(code):
        \\            return code
    ;
    try invoke("check", source, 0, "", "");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expect(std.mem.indexOf(u8, dumped.stdout, "HOST_RESOURCE -> network_cap") != null);
    const dynamic =
        \\resource Socket: network
        \\
        \\result Open:
        \\    ok: Socket,
        \\    err: int
        \\
        \\def main(net: Network) -> int:
        \\    endpoint = "127.0.0.1:8000"
        \\    scoped = net.host(endpoint)
        \\    request: [1]u8 = [0u8]
        \\    match acquire_resource[Open](scoped, request):
        \\        case Open.ok(socket):
        \\            _ = socket
        \\            return 0
        \\        case Open.err(code):
        \\            return code
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, dynamic, 1, "", "error[E_NETWORK_HOST]");
}

/// A project guest whose `main` takes a `Network`, narrows it to one literal
/// endpoint and reports the acquisition code. Used by the grant tests.
const network_connect_guest =
    \\module main
    \\import network
    \\
    \\
    \\def main(net: Network) -> int effects(network):
    \\    scoped = net.host("127.0.0.1:9")
    \\    match network.connect(scoped):
    \\        case network.Connected.ok(connection):
    \\            _ = connection
    \\            return 0
    \\        case network.Connected.err(code):
    \\            return code
;

/// Read until `buffer` fills or the peer closes; the bounded loop keeps the
/// loopback test body free of control flow.
fn readExact(io: std.Io, stream: std.Io.net.Stream, buffer: []u8) !usize {
    var total: usize = 0;
    while (total < buffer.len) {
        var slices = [_][]u8{buffer[total..]};
        const width = try stream.read(io, &slices);
        if (width == 0) break;
        total += width;
    }
    return total;
}

/// Accept the guest's write connection, assert the payload, answer it and close.
fn acceptPayload(io: std.Io, server: *std.Io.net.Server) !void {
    const peer = try server.accept(io);
    defer peer.close(io);
    var buffer: [4]u8 = undefined;
    const width = try readExact(io, peer, &buffer);
    try testing.expectEqualStrings("ping", buffer[0..width]);
    var writer = peer.writer(io, &.{});
    try writer.interface.writeAll("PONG");
}

/// Accept the guest's read connection and answer it with the echo payload.
fn acceptBanner(io: std.Io, server: *std.Io.net.Server) !void {
    const peer = try server.accept(io);
    defer peer.close(io);
    var writer = peer.writer(io, &.{});
    try writer.interface.writeAll("PONG");
}

// spec: NETWORK-ENDPOINT-1
test "CLI grants a narrowed endpoint and the network module exchanges bytes over loopback" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const address = try std.Io.net.IpAddress.parseLiteral("127.0.0.1:0");
    var server = try address.listen(testing.io, .{});
    defer server.deinit(testing.io);
    const name = try std.fmt.allocPrint(testing.allocator, "{f}", .{server.socket.address});
    defer testing.allocator.free(name);
    const source = try std.fmt.allocPrint(testing.allocator,
        \\module main
        \\import network
        \\
        \\
        \\def main(net: Network) -> int effects(network):
        \\    scoped = net.host("{s}")
        \\    match network.connect(scoped):
        \\        case network.Connected.ok(first):
        \\            payload: [4]u8 = b"ping"
        \\            match network.write(first, payload):
        \\                case network.Written.ok(sent):
        \\                    _ = sent
        \\                case network.Written.err(code):
        \\                    return 0 - code
        \\        case network.Connected.err(code):
        \\            return 0 - code
        \\    match network.connect(scoped):
        \\        case network.Connected.ok(second):
        \\            match network.read[4](second):
        \\                case network.Read.ok(chunk):
        \\                    return int(chunk.bytes[0]) + int(chunk.bytes[1]) + int(chunk.bytes[2]) + int(chunk.bytes[3]) + int(chunk.length)
        \\                case network.Read.err(code):
        \\                    return 0 - code
        \\        case network.Connected.err(code):
        \\            return 0 - code
        \\
    , .{name});
    defer testing.allocator.free(source);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = source });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);
    const grant = try std.fmt.allocPrint(testing.allocator, "--allow-endpoint={s}", .{name});
    defer testing.allocator.free(grant);
    const output = try temporary.dir.createFile(testing.io, "stdout", .{});
    defer output.close(testing.io);
    const failure = try temporary.dir.createFile(testing.io, "stderr", .{});
    defer failure.close(testing.io);
    const argv = [_][]const u8{ compiler_path, "run", entry, "--print-result", tools[0], tools[1], "--restrict", grant };
    var child = try std.process.spawn(testing.io, .{ .argv = &argv, .stdin = .ignore, .stdout = .{ .file = output }, .stderr = .{ .file = failure } });
    defer child.kill(testing.io);
    // The guest opens two connections: send `ping` on the first (summed bytes:
    // P+O+N+G + length 4 = 312) and read `PONG` on the second.
    try acceptPayload(testing.io, &server);
    try acceptBanner(testing.io, &server);
    try testing.expectEqual(std.process.Child.Term{ .exited = 312 & 0xff }, try child.wait(testing.io));
    const printed = try temporary.dir.readFileAlloc(testing.io, "stdout", testing.allocator, .limited(4096));
    defer testing.allocator.free(printed);
    try testing.expectEqualStrings("312\n", printed);
}

// spec-case: NETWORK-ENDPOINT-1
test "CLI denies a Network entry point and an endpoint outside the grant under restrict" {
    try invokeProjectOptions("run", network_connect_guest, &.{"--restrict"}, 2, "", "--allow-endpoint=IP:PORT");
    try invokeProjectOptions("run", network_connect_guest, &.{ "--restrict", "--allow-endpoint=127.0.0.1:8000" }, 2, "2\n", "");
}

// spec-case: NETWORK-ENDPOINT-1
test "CLI rejects malformed repeated and empty endpoint grants" {
    for ([_][]const []const u8{
        &.{"--allow-endpoint="},
        &.{"--allow-endpoint=localhost:9"},
        &.{"--allow-endpoint=[::1]:9"},
        &.{"--allow-endpoint=127.0.0.1:0"},
        &.{ "--allow-endpoint=127.0.0.1:9", "--allow-endpoint=127.0.0.1:9" },
    }) |options| try invokeProjectOptions("run", network_connect_guest, options, 2, "", "usage:");
}

// spec-case: FILE-METHOD-1
test "CLI checks and lowers the qualified whole-path helper methods" {
    const source = @embedFile("fixtures/file-methods.my");
    try invoke("check", source, 0, "", "");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    for ([_][]const u8{ "FILE_read_text", "FILE_read_file", "FILE_write_text", "FILE_write_file", "FILE_exists", "FILE_listdir", "FILE_mkdir", "FILE_remove", "FILE_open", "FILE_read local=" }) |text|
        try testing.expect(std.mem.indexOf(u8, dumped.stdout, text) != null);
    const invalid =
        \\def main(fs: Filesystem) -> int:
        \\    _ = fs.read_text()
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_ARITY]");
}

const clock_program =
    \\module main
    \\import time
    \\
    \\
    \\def main(clock: Clock) -> int:
    \\    match time.now(clock):
    \\        case Ok(instant):
    \\            return instant.unix_nanoseconds - instant.unix_nanoseconds
    \\        case Err(message):
    \\            return len(message)
;
// spec: CAPABILITY-1
test "CLI accepts Python capability spellings and lets a declared type keep the name" {
    try invokeProject("check", clock_program, 0, "", "");
    const declared =
        \\class Clock:
        \\    ticks: int
        \\
        \\def main() -> int:
        \\    return Clock(ticks=7).ticks
    ;
    try invoke("run", declared, 0, "7\n", "");
    const entropy =
        \\module main
        \\import random
        \\
        \\
        \\def main(rng: Entropy) -> int:
        \\    _ = random.from_entropy(rng)
        \\    return 0
    ;
    try checkProjectClean(entropy);
    try invoke("check",
        \\def main(env: Environment) -> i64:
        \\    _ = env
        \\    return 0
    , 0, "", "");
    try invoke("check",
        \\def main(fs: Filesystem) -> i64:
        \\    _ = fs
        \\    return 0
    , 0, "", "");
}
// spec: CAPABILITY-2
test "CLI grant flags reject repeats empty values and commands that do not execute" {
    for ([_][]const []const u8{
        &.{ "--allow-clock", "--allow-clock" },
        &.{"--allow-read="},
        &.{"--allow-write="},
        &.{"--allow-random=x"},
        &.{ "--allow-env=PATH", "--allow-env" },
        &.{ "--allow-all", "--allow-clock" },
        &.{"--allow-nonsense"},
        &.{ "--restrict", "--restrict" },
    }) |options| try invokeProjectOptions("run", clock_program, options, 2, "", "usage:");
    try invokeProjectOptions("check", clock_program, &.{"--allow-clock"}, 2, "", "usage:");
    try invokeProjectOptions("check", clock_program, &.{"--restrict"}, 2, "", "usage:");
    try invokeProjectOptions("emit-project-qbe", clock_program, &.{"--allow-clock"}, 2, "", "usage:");
}
// spec: CAPABILITY-3
test "CLI refuses an ungranted entry capability only while --restrict is active" {
    const environment =
        \\def main(env: Environment) -> i64 effects(environment):
        \\    _ = env.get("PATH")
        \\    return 0
    ;
    try invokeProjectOptions("run", clock_program, &.{"--restrict"}, 2, "", "--restrict is active");
    try invokeProjectOptions("run", clock_program, &.{"--restrict"}, 2, "", "drop --restrict");
    // The default grants every capability, so the same program runs unchanged.
    try invokeProject("run", clock_program, 0, "0\n", "");
    try invokeOptions("run", environment, &.{"--restrict"}, 2, "", "--restrict is active");
    try invokeOptions("run", environment, &.{"--restrict"}, 2, "", "drop --restrict");
    try invoke("run", environment, 0, "0\n", "");
    try invokeProjectOptions("run", clock_program, &.{ "--restrict", "--allow-clock" }, 0, "0\n", "");
    try invokeOptions("run", environment, &.{ "--restrict", "--allow-env=PATH" }, 0, "0\n", "");
    // A grant the entry point never requests is simply never read.
    try invokeOptions("run",
        \\def main() -> i64:
        \\    return 4
    , &.{ "--restrict", "--allow-clock", "--allow-random=7" }, 0, "4\n", "");
}
// spec: CAPABILITY-5
test "CLI clock entropy and environment providers honour their grants" {
    const seeded =
        \\module main
        \\import random
        \\
        \\
        \\def main(rng: Entropy) -> int:
        \\    match random.from_entropy(rng):
        \\        case Ok(generator):
        \\            return int(generator.state[0] % 1000u64)
        \\        case Err(message):
        \\            return len(message)
    ;
    const first = try runProjectFixture("run", seeded, &.{"--allow-random=11"});
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    const again = try runProjectFixture("run", seeded, &.{"--allow-random=11"});
    defer testing.allocator.free(again.stdout);
    defer testing.allocator.free(again.stderr);
    try testing.expectEqualStrings(first.stdout, again.stdout);
    // The seeded entry returns `value % 1000`, which is now the exit status; the
    // value is unknown here, so assert the contract against its printed result.
    try testing.expectEqual(std.process.Child.Term{ .exited = resultStatus(first.stdout) }, first.term);
    const missing =
        \\def main(env: Environment) -> i64 effects(environment):
        \\    match env.get("PATH"):
        \\        case Some(value):
        \\            return len(value) - len(value)
        \\        case None:
        \\            return 0
    ;
    // PATH is outside this allowlist, so the lookup is denied and the native
    // Python surface traps instead of answering None.
    try invokeOptions("run", missing, &.{ "--restrict", "--allow-env=OTHER" }, 1, "", "R_CAPABILITY");
}

// spec-case: CAPABILITY-4
// spec-case: IO-9
test "CLI directory grants scope the file surface and separate reading from writing" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "notes.txt", .data = "alpha\n" });
    const anchor = try temporary.dir.realPathFileAlloc(testing.io, "notes.txt", testing.allocator);
    defer testing.allocator.free(anchor);
    const directory = std.fs.path.dirname(anchor).?;
    const read_grant = try std.fmt.allocPrint(testing.allocator, "--allow-read={s}", .{directory});
    defer testing.allocator.free(read_grant);
    const write_grant = try std.fmt.allocPrint(testing.allocator, "--allow-write={s}", .{directory});
    defer testing.allocator.free(write_grant);
    const program =
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    out.print(read_text(fs, "notes.txt"))
        \\    out.print(write_text(fs, "copy.txt", "beta\n"))
        \\    out.print(read_text(fs, "../escape"))
        \\    return 0
    ;
    // These fixtures pass --print-result, so the entry point's `0` follows the program's output.
    const denied = "Err('read \\'../escape\\': denied: outside the granted directories, or the mode needs a write grant')\n0\n";
    try invokeOptions("run", program, &.{ "--restrict", read_grant }, 0, "Ok('alpha\\n')\n" ++
        "Err('write \\'copy.txt\\': denied: outside the granted directories, or the mode needs a write grant')\n" ++ denied, "");
    try invokeOptions("run", program, &.{ "--restrict", write_grant }, 0, "Ok('alpha\\n')\nOk(None)\n" ++ denied, "");
    const written = try temporary.dir.readFileAlloc(testing.io, "copy.txt", testing.allocator, .limited(32));
    defer testing.allocator.free(written);
    try testing.expectEqualStrings("beta\n", written);
    try invokeOptions("run", program, &.{"--restrict"}, 2, "", "--allow-read=DIR");
}
// spec-case: IO-1
test "CLI streams program output and reports the entry result only on request" {
    const program =
        \\def main(out: Stream) -> int:
        \\    out.print("streamed")
        \\    return 7
    ;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = program });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const plain = try std.process.run(testing.allocator, testing.io, .{ .argv = &(.{ compiler_path, "run", path } ++ tools) });
    defer testing.allocator.free(plain.stdout);
    defer testing.allocator.free(plain.stderr);
    // Without `--print-result` the value is not printed, but the entry still
    // returns 7, so the process exits 7 all the same.
    try testing.expectEqual(std.process.Child.Term{ .exited = 7 }, plain.term);
    try testing.expectEqualStrings("streamed\n", plain.stdout);
    try invoke("run", program, 0, "streamed\n7\n", "");
}

// spec-case: CAPABILITY-1
test "CLI resolves the Python capability spellings inside projects that import modules" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const entry =
        \\module main
        \\import time
        \\import random
        \\
        \\def main(clock: Clock, rng: Entropy, fs: Filesystem, out: Stream) -> int:
        \\    match time.now(clock):
        \\        case Ok(instant):
        \\            out.print("clock", instant.unix_nanoseconds - instant.unix_nanoseconds)
        \\        case Err(message):
        \\            out.print(message)
        \\    match random.from_entropy(rng):
        \\        case Ok(stream):
        \\            out.print("entropy", len(stream.state))
        \\        case Err(message):
        \\            out.print(message)
        \\    out.print(exists(fs, "notes.txt"))
        \\    return 0
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = entry });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(path);
    const directory = std.fs.path.dirname(path).?;
    const grant = try std.fmt.allocPrint(testing.allocator, "--allow-read={s}", .{directory});
    defer testing.allocator.free(grant);
    const granted = try std.process.run(testing.allocator, testing.io, .{
        .argv = &(.{ compiler_path, "run-project", path, "--restrict", "--allow-clock", "--allow-random=5", grant } ++ tools),
    });
    defer testing.allocator.free(granted.stdout);
    defer testing.allocator.free(granted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, granted.term);
    try testing.expectEqualStrings("clock 0\nentropy 1\nFalse\n", granted.stdout);
    const ungranted = try std.process.run(testing.allocator, testing.io, .{ .argv = &(.{ compiler_path, "run-project", path, "--restrict" } ++ tools) });
    defer testing.allocator.free(ungranted.stdout);
    defer testing.allocator.free(ungranted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, ungranted.term);
    try testing.expect(std.mem.indexOf(u8, ungranted.stderr, "--allow-clock") != null);
}

// spec-case: CAPABILITY-2
// spec-case: CAPABILITY-4
test "CLI grants every capability by default and resolves paths against the working directory" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "notes.txt", .data = "alpha\n" });
    const anchor = try temporary.dir.realPathFileAlloc(testing.io, "notes.txt", testing.allocator);
    defer testing.allocator.free(anchor);
    const directory = std.fs.path.dirname(anchor).?;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\def main(fs: Filesystem, out: Stream) -> int:
        \\    out.print(read_text(fs, "notes.txt"))
        \\    out.print(write_text(fs, "made.txt", "beta\n"))
        \\    out.print(read_text(fs, "../escape"))
        \\    return 0
    });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);
    // A relative guest path resolves against the process working directory, and
    // a path that leaves it is an ordinary filesystem failure rather than a denial.
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, testing.allocator);
    defer testing.allocator.free(compiler);
    // The child runs somewhere else, so the native tools must name themselves.
    const tool = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_options").qbe_path, testing.allocator);
    defer testing.allocator.free(tool);
    const qbe = try std.fmt.allocPrint(testing.allocator, "--qbe={s}", .{tool});
    defer testing.allocator.free(qbe);
    const outcome = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "run", entry, qbe, tools[1] },
        .cwd = .{ .path = directory },
    });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expectEqualStrings("Ok('alpha\\n')\nOk(None)\n" ++
        "Err('read \\'../escape\\': failed: the path does not exist or could not be used')\n", outcome.stdout);
    const written = try temporary.dir.readFileAlloc(testing.io, "made.txt", testing.allocator, .limited(32));
    defer testing.allocator.free(written);
    try testing.expectEqualStrings("beta\n", written);
    // An absolute path names itself, and `--allow-*` without `--restrict` narrows nothing.
    const absolute = try std.fmt.allocPrint(testing.allocator, "def main(fs: Filesystem, out: Stream) -> int:\n    out.print(read_text(fs, \"{s}\"))\n    return 0\n", .{anchor});
    defer testing.allocator.free(absolute);
    try invokeOptions("run", absolute, &.{"--allow-read=."}, 0, "Ok('alpha\\n')\n0\n", "");
}

/// Persistent frontend cache counters parsed from the `frontend-cache-v1` report line.
const CacheCounters = struct { syntax_hits: usize, syntax_misses: usize, verdict_hits: usize, verdict_misses: usize };

fn numberAfter(object: std.json.Value, key: []const u8) usize {
    const value = object.object.get(key) orelse return 0;
    return @intCast(value.integer);
}

/// Return the complete JSON object that contains `marker`.  Braces inside
/// strings and escaped quotes do not affect nesting, so the `stages` object on
/// the `frontend-cache-v1` line can nest freely.  The slice borrows `bytes`.
fn jsonObjectContaining(bytes: []const u8, marker: usize) ?[]const u8 {
    var index: usize = 0;
    while (index < bytes.len) {
        if (bytes[index] != '{') {
            index += 1;
            continue;
        }
        var depth: usize = 0;
        var in_string = false;
        var escaped = false;
        var cursor = index;
        var closed = false;
        while (cursor < bytes.len) : (cursor += 1) {
            const character = bytes[cursor];
            if (in_string) {
                if (escaped) {
                    escaped = false;
                } else if (character == '\\') {
                    escaped = true;
                } else if (character == '"') {
                    in_string = false;
                }
                continue;
            }
            switch (character) {
                '"' => in_string = true,
                '{' => depth += 1,
                '}' => {
                    if (depth == 0) break;
                    depth -= 1;
                    if (depth == 0) {
                        closed = true;
                        break;
                    }
                },
                else => {},
            }
        }
        if (closed and index <= marker and marker <= cursor) return bytes[index .. cursor + 1];
        index = if (closed) cursor + 1 else index + 1;
    }
    return null;
}

fn cacheCounters(stderr: []const u8) !CacheCounters {
    const marker = std.mem.indexOf(u8, stderr, "frontend-cache-v1") orelse return error.MissingCacheLine;
    const object = jsonObjectContaining(stderr, marker) orelse return error.MissingCacheLine;
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, object, .{});
    defer parsed.deinit();
    return .{
        .syntax_hits = numberAfter(parsed.value, "syntax_hits"),
        .syntax_misses = numberAfter(parsed.value, "syntax_misses"),
        .verdict_hits = numberAfter(parsed.value, "verdict_hits"),
        .verdict_misses = numberAfter(parsed.value, "verdict_misses"),
    };
}

/// Parse the `invalidation-report-v1` line out of `stderr`.
fn invalidationReport(stderr: []const u8) !std.json.Parsed(std.json.Value) {
    const marker = std.mem.indexOf(u8, stderr, "invalidation-report-v1") orelse return error.MissingInvalidationLine;
    const object = jsonObjectContaining(stderr, marker) orelse return error.MissingInvalidationLine;
    return std.json.parseFromSlice(std.json.Value, testing.allocator, object, .{});
}

fn stageQuery(report: std.json.Value, name: []const u8) !std.json.Value {
    for (report.object.get("queries").?.array.items) |query| {
        if (std.mem.eql(u8, query.object.get("stage").?.string, name)) return query;
    }
    return error.MissingStage;
}

fn stageStatus(report: std.json.Value, name: []const u8) ![]const u8 {
    return (try stageQuery(report, name)).object.get("status").?.string;
}

/// Check a two-module project under `--report`, returning the parsed counters.
fn projectCacheCheck(entry: []const u8, cache_dir: []const u8, expected_status: u8) !CacheCounters {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "check-project", entry, "--report", cache_dir });
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = expected_status }, outcome.term);
    return cacheCounters(outcome.stderr);
}

// spec: FRONTEND-CACHE-1
// spec: FRONTEND-CACHE-2
test "CLI project checks reuse syntax and verdicts and invalidate only changed modules" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDir(testing.io, "app", .default_dir);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/main.my", .data =
        \\module main
        \\
        \\import helper
        \\
        \\def main() -> i64:
        \\    return helper.answer()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.my", .data =
        \\module helper
        \\
        \\
        \\public def answer() -> i64 effects():
        \\    return 7
    });
    const entry = try temp.dir.realPathFileAlloc(testing.io, "app/main.my", testing.allocator);
    defer testing.allocator.free(entry);
    const temp_root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(temp_root);
    const cache_root = try std.fs.path.join(testing.allocator, &.{ temp_root, "frontend-cache" });
    defer testing.allocator.free(cache_root);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_root});
    defer testing.allocator.free(cache_argument);

    // Cold: two parses stored and the successful verdict is retained.
    const cold = try projectCacheCheck(entry, cache_argument, 0);
    try testing.expectEqual(@as(usize, 0), cold.syntax_hits);
    try testing.expectEqual(@as(usize, 2), cold.syntax_misses);
    try testing.expectEqual(@as(usize, 0), cold.verdict_hits);

    // Warm: the whole-program verdict comes from disk, so no syntax lookup runs.
    const warm = try projectCacheCheck(entry, cache_argument, 0);
    try testing.expectEqual(@as(usize, 1), warm.verdict_hits);
    try testing.expectEqual(@as(usize, 0), warm.syntax_misses);

    // Editing the dependency invalidates the verdict and only that module's syntax.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.my", .data =
        \\module helper
        \\
        \\
        \\public def answer() -> i64 effects():
        \\    return 8
    });
    const edited = try projectCacheCheck(entry, cache_argument, 0);
    try testing.expectEqual(@as(usize, 1), edited.syntax_hits);
    try testing.expectEqual(@as(usize, 1), edited.syntax_misses);
    try testing.expectEqual(@as(usize, 0), edited.verdict_hits);
    try testing.expect(edited.verdict_misses >= 1);

    // A rejected edit can never inherit the earlier successful verdict. The
    // failure is reported and the cache is not consulted again for this content.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.my", .data =
        \\module helper
        \\
        \\
        \\public def answer() -> i64:
        \\    return True
    });
    const broken = try projectCacheCheck(entry, cache_argument, 1);
    try testing.expectEqual(@as(usize, 0), broken.verdict_hits);

    // Repair the source so the final no-cache run is a successful check.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.my", .data =
        \\module helper
        \\
        \\
        \\public def answer() -> i64 effects():
        \\    return 8
    });

    // `--no-cache` opens no cache at all, so it emits no reuse receipt and the
    // stored successful verdict for the same content is not consulted.
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "check-project", entry, "--report", "--no-cache" });
    const uncached = try std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
    defer testing.allocator.free(uncached.stdout);
    defer testing.allocator.free(uncached.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, uncached.term);
    try testing.expect(std.mem.indexOf(u8, uncached.stderr, "frontend-cache-v1") == null);
}

// spec: INVALIDATION-EXECUTION-1
test "CLI invalidation reports actual query work and marks unexecuted stages skipped" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDir(testing.io, "app", .default_dir);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/main.my", .data =
        \\module main
        \\import helper
        \\
        \\def main() -> i64:
        \\    return helper.answer()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.my", .data =
        \\module helper
        \\
        \\public def answer() -> i64 effects():
        \\    return 40
    });
    const entry = try temp.dir.realPathFileAlloc(testing.io, "app/main.my", testing.allocator);
    defer testing.allocator.free(entry);
    const temp_root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(temp_root);
    const cache_root = try std.fs.path.join(testing.allocator, &.{ temp_root, "invalidation-cache" });
    defer testing.allocator.free(cache_root);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_root});
    defer testing.allocator.free(cache_argument);

    // Seed a baseline with a check-only command, then edit a private body.
    var seed_args: std.ArrayList([]const u8) = .empty;
    defer seed_args.deinit(testing.allocator);
    try seed_args.appendSlice(testing.allocator, &.{ compiler_path, "check-project", entry, "--explain-invalidation", cache_argument });
    const seed = try std.process.run(testing.allocator, testing.io, .{ .argv = seed_args.items });
    defer testing.allocator.free(seed.stdout);
    defer testing.allocator.free(seed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, seed.term);

    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.my", .data =
        \\module helper
        \\
        \\public def answer() -> i64 effects():
        \\    return 41
    });
    var check_args: std.ArrayList([]const u8) = .empty;
    defer check_args.deinit(testing.allocator);
    try check_args.appendSlice(testing.allocator, &.{ compiler_path, "check-project", entry, "--explain-invalidation", "--report", cache_argument });
    const check = try std.process.run(testing.allocator, testing.io, .{ .argv = check_args.items });
    defer testing.allocator.free(check.stdout);
    defer testing.allocator.free(check.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, check.term);
    var report = try invalidationReport(check.stderr);
    defer report.deinit();
    try testing.expectEqualStrings("miss", try stageStatus(report.value, "check_body"));
    // A check-only command never lowers, emits or links, so those stages must be
    // skipped rather than reported as reuse.
    for ([_][]const u8{ "lower_function", "emit_fragment", "link" }) |name| {
        try testing.expectEqualStrings("skipped", try stageStatus(report.value, name));
    }
    try testing.expect(std.mem.indexOf(u8, check.stderr, "\"skipped\":") != null);

    // A command that does lower/emit/link must report real misses for those
    // stages after a body edit, and its executed result must change.
    try temp.dir.createDir(testing.io, "runapp", .default_dir);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "runapp/main.my", .data =
        \\module main
        \\import helper
        \\
        \\def main() -> i64:
        \\    return helper.answer()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "runapp/helper.my", .data =
        \\module helper
        \\
        \\public def answer() -> i64 effects():
        \\    return 42
    });
    const run_entry = try temp.dir.realPathFileAlloc(testing.io, "runapp/main.my", testing.allocator);
    defer testing.allocator.free(run_entry);
    const run_cache_root = try std.fs.path.join(testing.allocator, &.{ temp_root, "run-cache" });
    defer testing.allocator.free(run_cache_root);
    const run_cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{run_cache_root});
    defer testing.allocator.free(run_cache_argument);
    var run_args: std.ArrayList([]const u8) = .empty;
    defer run_args.deinit(testing.allocator);
    try run_args.appendSlice(testing.allocator, &.{ compiler_path, "run", run_entry, "--explain-invalidation", run_cache_argument, tools[0], tools[1] });
    const first = try std.process.run(testing.allocator, testing.io, .{ .argv = run_args.items });
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, first.term);

    try temp.dir.writeFile(testing.io, .{ .sub_path = "runapp/helper.my", .data =
        \\module helper
        \\
        \\public def answer() -> i64 effects():
        \\    return 43
    });
    const second = try std.process.run(testing.allocator, testing.io, .{ .argv = run_args.items });
    defer testing.allocator.free(second.stdout);
    defer testing.allocator.free(second.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 43 }, second.term);
    var run_report = try invalidationReport(second.stderr);
    defer run_report.deinit();
    for ([_][]const u8{ "check_body", "lower_function", "emit_fragment", "link" }) |name| {
        try testing.expectEqualStrings("miss", try stageStatus(run_report.value, name));
    }
    try testing.expectEqualStrings("module:helper::answer", (try stageQuery(run_report.value, "check_body")).object.get("first_changed").?.string);
}

// spec: CAPABILITY-DIAG-1
test "multiple missing capabilities report exactly one identical diagnostic" {
    const program =
        \\def main(fs: Filesystem, env: Environment) -> int:
        \\    _ = fs
        \\    _ = env
        \\    return 0
    ;
    const message = "mylang: --restrict is active and this command line did not grant a capability the entry point requests; pass --allow-read=DIR, or drop --restrict to grant every capability\n";
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "cap.my", .data = program });
    const path = try temp.dir.realPathFileAlloc(testing.io, "cap.my", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "cap-bin" });
    defer testing.allocator.free(output);

    var run_argv: std.ArrayList([]const u8) = .empty;
    defer run_argv.deinit(testing.allocator);
    try run_argv.appendSlice(testing.allocator, &.{ compiler_path, "run", path, "--restrict" });
    try run_argv.appendSlice(testing.allocator, &tools);
    const run = try std.process.run(testing.allocator, testing.io, .{ .argv = run_argv.items });
    defer testing.allocator.free(run.stdout);
    defer testing.allocator.free(run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, run.term);
    try testing.expectEqualStrings("", run.stdout);
    try testing.expectEqualStrings(message, run.stderr);

    var build_argv: std.ArrayList([]const u8) = .empty;
    defer build_argv.deinit(testing.allocator);
    try build_argv.appendSlice(testing.allocator, &.{ compiler_path, "build", path, "--run", "--restrict" });
    try build_argv.appendSlice(testing.allocator, &tools);
    const build = try std.process.run(testing.allocator, testing.io, .{ .argv = build_argv.items });
    defer testing.allocator.free(build.stdout);
    defer testing.allocator.free(build.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, build.term);
    try testing.expectEqualStrings("", build.stdout);
    try testing.expectEqualStrings(message, build.stderr);

    var link_argv: std.ArrayList([]const u8) = .empty;
    defer link_argv.deinit(testing.allocator);
    try link_argv.appendSlice(testing.allocator, &.{ compiler_path, "build", path, "-o", output });
    try link_argv.appendSlice(testing.allocator, &tools);
    const link = try std.process.run(testing.allocator, testing.io, .{ .argv = link_argv.items });
    defer testing.allocator.free(link.stdout);
    defer testing.allocator.free(link.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, link.term);
    var restricted = try runtimeOptions("--restrict");
    defer restricted.deinit();
    const installed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{output}, .environ_map = &restricted });
    defer testing.allocator.free(installed.stdout);
    defer testing.allocator.free(installed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, installed.term);
    try testing.expectEqualStrings("", installed.stdout);
    try testing.expectEqualStrings(message, installed.stderr);
}

// spec: ARGV-LIMIT-1
test "run build --run and installed executables accept more than 256 guest arguments" {
    const program =
        \\def main(args: list[str]) -> int:
        \\    return len(args)
    ;
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "args.my", .data = program });
    const path = try temp.dir.realPathFileAlloc(testing.io, "args.my", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "args-bin" });
    defer testing.allocator.free(output);
    var guest: [260][]const u8 = @splat("x");

    var run_argv: std.ArrayList([]const u8) = .empty;
    defer run_argv.deinit(testing.allocator);
    try run_argv.appendSlice(testing.allocator, &.{ compiler_path, "run", path });
    try run_argv.appendSlice(testing.allocator, &tools);
    try run_argv.append(testing.allocator, "--");
    try run_argv.appendSlice(testing.allocator, &guest);
    const run = try std.process.run(testing.allocator, testing.io, .{ .argv = run_argv.items });
    defer testing.allocator.free(run.stdout);
    defer testing.allocator.free(run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 4 }, run.term);
    try testing.expectEqualStrings("", run.stdout);
    try testing.expectEqualStrings("", run.stderr);

    var build_argv: std.ArrayList([]const u8) = .empty;
    defer build_argv.deinit(testing.allocator);
    try build_argv.appendSlice(testing.allocator, &.{ compiler_path, "build", path, "--run" });
    try build_argv.appendSlice(testing.allocator, &tools);
    try build_argv.append(testing.allocator, "--");
    try build_argv.appendSlice(testing.allocator, &guest);
    const build = try std.process.run(testing.allocator, testing.io, .{ .argv = build_argv.items });
    defer testing.allocator.free(build.stdout);
    defer testing.allocator.free(build.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 4 }, build.term);
    try testing.expectEqualStrings("", build.stdout);
    try testing.expectEqualStrings("", build.stderr);

    var link_argv: std.ArrayList([]const u8) = .empty;
    defer link_argv.deinit(testing.allocator);
    try link_argv.appendSlice(testing.allocator, &.{ compiler_path, "build", path, "-o", output });
    try link_argv.appendSlice(testing.allocator, &tools);
    const link = try std.process.run(testing.allocator, testing.io, .{ .argv = link_argv.items });
    defer testing.allocator.free(link.stdout);
    defer testing.allocator.free(link.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, link.term);
    var installed_argv: std.ArrayList([]const u8) = .empty;
    defer installed_argv.deinit(testing.allocator);
    // An installed executable reads no option from its arguments, so every one
    // of them is the guest's and no `--` is needed.
    try installed_argv.append(testing.allocator, output);
    try installed_argv.appendSlice(testing.allocator, &guest);
    const installed = try std.process.run(testing.allocator, testing.io, .{ .argv = installed_argv.items });
    defer testing.allocator.free(installed.stdout);
    defer testing.allocator.free(installed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 4 }, installed.term);
    try testing.expectEqualStrings("", installed.stdout);
    try testing.expectEqualStrings("", installed.stderr);
}
const named_constraint_contracts =
    \\module contracts
    \\
    \\
    \\public constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
;
const named_constraint_checkout =
    \\module checkout
    \\import contracts
    \\
    \\
    \\public def total[P: contracts.Prices](policy: P, subtotal: int) -> int effects():
    \\    return P.price(policy, subtotal) + 500
;
const named_constraint_fakes =
    \\module fakes
    \\
    \\
    \\public domain FixedPrices: int:
    \\    def make(amount: int) -> FixedPrices effects():
    \\        return wrap[FixedPrices](amount)
    \\
    \\    def price(policy: FixedPrices, subtotal: int) -> int effects():
    \\        _ = subtotal
    \\        return unwrap(policy)
;
const named_constraint_fake_tests =
    \\module fake_tests
    \\import checkout
    \\import fakes
    \\
    \\
    \\def main() -> int:
    \\    assert test_checkout()
    \\    return 0
    \\
    \\
    \\public def test_checkout() -> bool effects():
    \\    return checkout.total(fakes.FixedPrices.make(1750), 2000) == 2250
;
const named_constraint_production_invalid =
    \\module production
    \\import contracts
    \\
    \\
    \\public domain DiscountPrices: int:
    \\    def make(discount: int) -> DiscountPrices effects():
    \\        return wrap[DiscountPrices](discount)
    \\
    \\    def price(policy: DiscountPrices, subtotal: int) -> int effects():
    \\        return missing_name(policy, subtotal)
;
const named_constraint_main =
    \\module main
    \\import checkout
    \\import production
    \\
    \\
    \\def main() -> int:
    \\    real = production.DiscountPrices.make(250)
    \\    assert checkout.total(real, 2000) == 2250
    \\    return 0
;

fn acceptNamedConstraintFake(testing_: *std.testing.TmpDir, allocator: std.mem.Allocator) !void {
    const entry = try testing_.dir.realPathFileAlloc(testing.io, "fake_tests.my", allocator);
    defer allocator.free(entry);
    const result = try std.process.run(allocator, testing.io, .{ .argv = &.{ compiler_path, "test", entry, "--filter", "test_checkout" } });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    // A warm cache reports the same outcome as `cached`; both mean the entry passed.
    try testing.expect(std.mem.indexOf(u8, result.stdout, "test_checkout") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "0 failed") != null);
}

// spec: NAMED-CONSTRAINT-FIXTURE-1
test "named constraints fake-only entry ignores an absent or invalid production module" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "contracts.my", .data = named_constraint_contracts });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "checkout.my", .data = named_constraint_checkout });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "fakes.my", .data = named_constraint_fakes });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "fake_tests.my", .data = named_constraint_fake_tests });
    try acceptNamedConstraintFake(&temp, testing.allocator);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "production.my", .data = named_constraint_production_invalid });
    try acceptNamedConstraintFake(&temp, testing.allocator);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = named_constraint_main });
    const main_path = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(main_path);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "run", main_path });
    try args.appendSlice(testing.allocator, &tools);
    const rejected = try std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
    defer testing.allocator.free(rejected.stdout);
    defer testing.allocator.free(rejected.stderr);
    try testing.expect(rejected.term != .exited or rejected.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, rejected.stderr, "E_UNKNOWN_SYMBOL") != null);
    try testing.expect(std.mem.indexOf(u8, rejected.stderr, "missing_name") != null);
}

const named_probes = @import("named_constraints_probes.zig");

fn runNamedConstraintProbe(allocator: std.mem.Allocator, probe: named_probes.Probe) !void {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    for (probe.files) |file| try temp.dir.writeFile(testing.io, .{ .sub_path = file.name, .data = file.body });
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.my", allocator);
    defer allocator.free(entry);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(allocator);
    try args.appendSlice(allocator, &.{ compiler_path, probe.command, entry });
    if (std.mem.eql(u8, probe.command, "check-project")) try args.append(allocator, "--no-cache");
    const result = try std.process.run(allocator, testing.io, .{ .argv = args.items });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (probe.expect_success) {
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    } else {
        try testing.expect(result.term != .exited or result.term.exited != 0);
        if (probe.diagnostic.len != 0) try testing.expect(std.mem.indexOf(u8, result.stderr, probe.diagnostic) != null);
    }
}

fn runNamedConstraintProbes(allocator: std.mem.Allocator) !void {
    for (named_probes.probes) |probe| try runNamedConstraintProbe(allocator, probe);
}

// The named-constraints review repros stay executable: imported export identity,
// declaration-scoped type resolution, identity-based merging, implied copy,
// normalized limits, standalone namespace rules, and unused declaration checks.
// spec: NAMED-CONSTRAINT-REVIEW-1
test "named constraints review repros keep their repaired checking outcomes" {
    try runNamedConstraintProbes(testing.allocator);
}

fn runCompiler(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.RunResult {
    return std.process.run(allocator, testing.io, .{ .argv = argv });
}

fn writeProjectFile(dir: *std.testing.TmpDir, path: []const u8, data: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| try dir.dir.createDirPath(testing.io, parent);
    try dir.dir.writeFile(testing.io, .{ .sub_path = path, .data = data });
}

const policy_allow = "{\"version\":1,\"default_action\":\"allow\",\"rules\":[]}";
const policy_deny = "{\"version\":1,\"default_action\":\"deny\",\"rules\":[]}";
const policy_project_main = "module main\nimport helper\ndef main() -> int:\n    return helper.value()\n";
const policy_project_helper = "module helper\npublic def value() -> int effects():\n    return 7\n";

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "loadConfiguredPolicy enforces mylang.json across ordinary project commands cold warm and after policy-only edits" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.my", policy_project_main);
    try writeProjectFile(&temp, "helper.my", policy_project_helper);
    try writeProjectFile(&temp, "mylang.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "policy.json", policy_deny);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "program" });
    defer testing.allocator.free(output);
    const explicit_policy = try std.fmt.allocPrint(testing.allocator, "--policy={s}/policy.json", .{root});
    defer testing.allocator.free(explicit_policy);

    // Cold and warm `check-project`: a required denial cannot be skipped by the cache.
    for (0..2) |_| {
        const denied = try runCompiler(testing.allocator, &.{ compiler_path, "check-project", entry, cache_argument });
        defer testing.allocator.free(denied.stdout);
        defer testing.allocator.free(denied.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, denied.term);
        try testing.expectEqualStrings("", denied.stdout);
        try testing.expect(std.mem.indexOf(u8, denied.stderr, "import-direction-v1: failed") != null);
        try testing.expect(std.mem.indexOf(u8, denied.stderr, "main -> helper: deny") != null);
    }

    // `build` and `run-project` go through the same required-policy gate.
    var build_args: std.ArrayList([]const u8) = .empty;
    defer build_args.deinit(testing.allocator);
    try build_args.appendSlice(testing.allocator, &.{ compiler_path, "build", entry, "--project", "-o", output, cache_argument });
    try build_args.appendSlice(testing.allocator, &tools);
    const built = try runCompiler(testing.allocator, build_args.items);
    defer testing.allocator.free(built.stdout);
    defer testing.allocator.free(built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, built.term);

    var run_args: std.ArrayList([]const u8) = .empty;
    defer run_args.deinit(testing.allocator);
    try run_args.appendSlice(testing.allocator, &.{ compiler_path, "run-project", entry, "--print-result", cache_argument });
    try run_args.appendSlice(testing.allocator, &tools);
    const run_denied = try runCompiler(testing.allocator, run_args.items);
    defer testing.allocator.free(run_denied.stdout);
    defer testing.allocator.free(run_denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, run_denied.term);
    try testing.expectEqualStrings("", run_denied.stdout);

    // Explicit `check-policy` inspection keeps working and names its own policy.
    const explicit = try runCompiler(testing.allocator, &.{ compiler_path, "check-policy", entry, explicit_policy });
    defer testing.allocator.free(explicit.stdout);
    defer testing.allocator.free(explicit.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, explicit.term);
    try testing.expect(std.mem.indexOf(u8, explicit.stdout, "import-direction-v1: failed") != null);

    // A policy-only edit flips acceptance; the earlier deny never wrote a pass.
    try writeProjectFile(&temp, "policy.json", policy_allow);
    for (0..2) |_| {
        const allowed = try runCompiler(testing.allocator, &.{ compiler_path, "check-project", entry, cache_argument });
        defer testing.allocator.free(allowed.stdout);
        defer testing.allocator.free(allowed.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, allowed.term);
        try testing.expectEqualStrings("", allowed.stderr);
    }
    const allowed_run = try runCompiler(testing.allocator, run_args.items);
    defer testing.allocator.free(allowed_run.stdout);
    defer testing.allocator.free(allowed_run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 7 }, allowed_run.term);
    try testing.expectEqualStrings("7\n", allowed_run.stdout);

    // A stricter policy-only edit must invalidate the warm allowed pass.
    try writeProjectFile(&temp, "policy.json", policy_deny);
    const stricter = try runCompiler(testing.allocator, &.{ compiler_path, "check-project", entry, cache_argument });
    defer testing.allocator.free(stricter.stdout);
    defer testing.allocator.free(stricter.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, stricter.term);
    try testing.expect(std.mem.indexOf(u8, stricter.stderr, "main -> helper: deny") != null);
}

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "loadConfiguredPolicy policy discovery anchors to the entry file instead of the shell working directory" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "entry/main.my", policy_project_main);
    try writeProjectFile(&temp, "entry/helper.my", policy_project_helper);
    try writeProjectFile(&temp, "entry/mylang.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "entry/policy.json", policy_deny);
    try writeProjectFile(&temp, "elsewhere/main.my", "module main\ndef main() -> int:\n    return 0\n");
    try writeProjectFile(&temp, "elsewhere/mylang.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "elsewhere/policy.json", policy_allow);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "entry/main.my", testing.allocator);
    defer testing.allocator.free(entry);
    var elsewhere = try temp.dir.openDir(testing.io, "elsewhere", .{ .iterate = false });
    defer elsewhere.close(testing.io);
    // The child runs from another directory, so the compiler must name itself absolutely.
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, testing.allocator);
    defer testing.allocator.free(compiler);

    const result = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "check-project", entry },
        .cwd = .{ .dir = elsewhere },
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    // Running from the allow-policy directory must not select that policy for an
    // entry whose own project denies the import.
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "main -> helper: deny") != null);
}

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "configured policy never disables independent import-cycle rejection" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.my", "module main\nimport helper\ndef main() -> int:\n    return helper.value()\n");
    try writeProjectFile(&temp, "helper.my", "module helper\nimport main\npublic def value() -> int effects():\n    return 0\n");
    try writeProjectFile(&temp, "mylang.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);
    for ([_][]const u8{ policy_allow, policy_deny }) |body| {
        try writeProjectFile(&temp, "policy.json", body);
        const result = try runCompiler(testing.allocator, &.{ compiler_path, "check-project", entry });
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
        try testing.expect(std.mem.indexOf(u8, result.stderr, "E_IMPORT_CYCLE") != null);
    }
}

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "loadConfiguredPolicy policy reports missing and malformed configuration as host status 2" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.my", policy_project_main);
    try writeProjectFile(&temp, "helper.my", policy_project_helper);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);

    const malformed = [_][]const u8{
        "{\"version\":1,\"import_policy\":\"absent.json\"}",
        "{\"version\":2,\"import_policy\":\"policy.json\"}",
        "{\"version\":1,\"typo\":true}",
        "not json at all",
    };
    for (malformed) |body| {
        try writeProjectFile(&temp, "mylang.json", body);
        const result = try runCompiler(testing.allocator, &.{ compiler_path, "check-project", entry });
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, result.term);
        try testing.expectEqualStrings("", result.stdout);
        try testing.expect(std.mem.indexOf(u8, result.stderr, "E_PROJECT_CONFIG") != null);
    }
}

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "loadConfiguredPolicy policy statuses parseDocument HostConfiguration and PolicyViolation" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.my", policy_project_main);
    try writeProjectFile(&temp, "helper.my", policy_project_helper);
    try writeProjectFile(&temp, "mylang.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "policy.json", policy_deny);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);

    const denied = try runCompiler(testing.allocator, &.{ compiler_path, "check-project", entry });
    defer testing.allocator.free(denied.stdout);
    defer testing.allocator.free(denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, denied.term);
    try testing.expect(std.mem.indexOf(u8, denied.stderr, "main -> helper: deny") != null);

    try writeProjectFile(&temp, "mylang.json", "{");
    const malformed = try runCompiler(testing.allocator, &.{ compiler_path, "check-project", entry });
    defer testing.allocator.free(malformed.stdout);
    defer testing.allocator.free(malformed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, malformed.term);
    try testing.expect(std.mem.indexOf(u8, malformed.stderr, "E_PROJECT_CONFIG") != null);
}

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "loadConfiguredPolicy policy applies to native test preparation ProjectConfigurationFailed and ProjectPolicyRejected" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "tests.my",
        \\module tests
        \\import helper
        \\
        \\
        \\def main() -> int:
        \\    return 0
        \\
        \\
        \\public def test_policy() -> bool effects():
        \\    return helper.value() == 7
    );
    try writeProjectFile(&temp, "helper.my", "module helper\npublic def value() -> int effects():\n    return 7\n");
    try writeProjectFile(&temp, "mylang.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "policy.json", policy_allow);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "tests.my", testing.allocator);
    defer testing.allocator.free(entry);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "test-cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);

    const allowed = try runCompiler(testing.allocator, &.{ compiler_path, "test", entry, "--filter", "test_policy", cache_argument });
    defer testing.allocator.free(allowed.stdout);
    defer testing.allocator.free(allowed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, allowed.term);
    try testing.expect(std.mem.indexOf(u8, allowed.stdout, "test_policy") != null);

    try writeProjectFile(&temp, "policy.json", policy_deny);
    const denied = try runCompiler(testing.allocator, &.{ compiler_path, "test", entry, "--filter", "test_policy", cache_argument });
    defer testing.allocator.free(denied.stdout);
    defer testing.allocator.free(denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, denied.term);
    try testing.expect(std.mem.indexOf(u8, denied.stderr, "tests -> helper: deny") != null);

    try writeProjectFile(&temp, "mylang.json", "{");
    const malformed = try runCompiler(testing.allocator, &.{ compiler_path, "test", entry, "--filter", "test_policy", cache_argument });
    defer testing.allocator.free(malformed.stdout);
    defer testing.allocator.free(malformed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, malformed.term);
    try testing.expect(std.mem.indexOf(u8, malformed.stderr, "E_PROJECT_CONFIG") != null);
}

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "validateUnitConfiguredPolicy checks required configuration for single-unit commands" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.my", "def main() -> int:\n    return 0\n");
    try writeProjectFile(&temp, "mylang.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "policy.json", policy_deny);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);

    // A unit has no import edges, so a well-formed policy is satisfied.
    const allowed = try runCompiler(testing.allocator, &.{ compiler_path, "check", entry });
    defer testing.allocator.free(allowed.stdout);
    defer testing.allocator.free(allowed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, allowed.term);

    try writeProjectFile(&temp, "mylang.json", "{\"version\":1,\"import_policy\":\"absent.json\"}");
    const missing = try runCompiler(testing.allocator, &.{ compiler_path, "check", entry });
    defer testing.allocator.free(missing.stdout);
    defer testing.allocator.free(missing.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, missing.term);
    try testing.expect(std.mem.indexOf(u8, missing.stderr, "E_PROJECT_CONFIG") != null);

    try writeProjectFile(&temp, "mylang.json", "not json");
    const malformed = try runCompiler(testing.allocator, &.{ compiler_path, "check", entry });
    defer testing.allocator.free(malformed.stdout);
    defer testing.allocator.free(malformed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, malformed.term);
    try testing.expect(std.mem.indexOf(u8, malformed.stderr, "E_PROJECT_CONFIG") != null);
}

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "loadConfiguredPolicy policy discovery above the native test entry enforces the ancestor config" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "nested/tests.my",
        \\module tests
        \\import helper
        \\
        \\
        \\def main() -> int:
        \\    return 0
        \\
        \\
        \\public def test_policy() -> bool effects():
        \\    return helper.value() == 7
    );
    try writeProjectFile(&temp, "nested/helper.my", "module helper\npublic def value() -> int effects():\n    return 7\n");
    try writeProjectFile(&temp, "mylang.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "policy.json", policy_deny);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "nested/tests.my", testing.allocator);
    defer testing.allocator.free(entry);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "test-cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);

    const denied = try runCompiler(testing.allocator, &.{ compiler_path, "test", entry, "--filter", "test_policy", cache_argument });
    defer testing.allocator.free(denied.stdout);
    defer testing.allocator.free(denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, denied.term);
    try testing.expect(std.mem.indexOf(u8, denied.stderr, "tests -> helper: deny") != null);
}

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "loadConfiguredPolicy policy identity participates in project-dependencies receipts" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.my", policy_project_main);
    try writeProjectFile(&temp, "helper.my", policy_project_helper);
    try writeProjectFile(&temp, "mylang.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "policy.json", policy_allow);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "receipt-cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);

    const first = try runCompiler(testing.allocator, &.{ compiler_path, "project-dependencies", entry, cache_argument });
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    try testing.expect(std.mem.indexOf(u8, first.stdout, "\"policy\"") != null);
    try testing.expect(std.mem.indexOf(u8, first.stdout, "\"config_sha256\"") != null);

    try writeProjectFile(&temp, "policy.json", "{\"version\":1,\"default_action\":\"deny\",\"rules\":[]}");
    const second = try runCompiler(testing.allocator, &.{ compiler_path, "project-dependencies", entry, cache_argument });
    defer testing.allocator.free(second.stdout);
    defer testing.allocator.free(second.stderr);
    // A stricter policy denies the ordinary receipt command before it can be
    // produced, which is the acceptance-relevant identity change.
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, second.term);
    try testing.expect(std.mem.indexOf(u8, second.stderr, "main -> helper: deny") != null);
}

// spec-case: MUTATION-ENFORCE-1
test "CLI migrated corpus projects carry the checked mutation contract" {
    // The corpus pieces M3 repaired: domain methods exposed through an exported
    // type, a generated input accessor, guest tests that allocate, and the
    // schematic/board applications. Every one needs an explicit, narrow ceiling.
    for ([_][]const u8{
        "examples/modules/main.my",
        "examples/input-values/main.my",
        "tests/guest/generics.my",
        "src/schematic/guest/main.my",
        "src/board_trial/guest/main.my",
    }) |entry| {
        const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-project", entry } });
        defer testing.allocator.free(outcome.stdout);
        defer testing.allocator.free(outcome.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    }
}

// spec-case: MUTATION-ENFORCE-1
test "CLI nested record alias rejects under effects and runs with a mutation footprint" {
    const rejected =
        \\record Box:
        \\    values: list[int]
        \\
        \\
        \\def overwrite(box: mut Box) -> None effects():
        \\    box.values[0] = 7
        \\
        \\
        \\def main() -> int:
        \\    box = Box(values=[1])
        \\    overwrite(mut box)
        \\    return box.values[0]
    ;
    try invoke("check", rejected, 1, "", "E_MUTATION_PERMISSION");
    const permitted =
        \\record Box:
        \\    values: list[int]
        \\
        \\
        \\def overwrite(box: mut Box) -> None:
        \\    box.values[0] = 7
        \\
        \\
        \\def main() -> int:
        \\    box = Box(values=[1])
        \\    overwrite(mut box)
        \\    return box.values[0]
    ;
    try invoke("run", permitted, 0, "7\n", "");
}

// spec-case: MUT-PARAM-5
test "CLI the mut spelling checks and runs while the removed flag is rejected" {
    try invokeOptions("check", @embedFile("fixtures/mutation-markers.my"), &.{}, 0, "", "");
    try invokeOptions("run", @embedFile("fixtures/mutation-markers.my"), &.{}, 0, "8\n", "");
    try invokeOptions("check", @embedFile("fixtures/mutation-markers.my"), &.{"--mutation-markers"}, 2, "", "--mutation-markers was removed");
}

// --- P1: selected test providers validated against declared contracts ---

const p1_production_unfinished =
    \\module production
    \\
    \\
    \\public domain Stub: int:
    \\    def make(discount: int) -> Stub effects():
    \\        return wrap[Stub](discount)
    \\
    \\    def price(policy: Stub, ledger: mut list[int], rates: list[int], subtotal: int) -> int effects(mutation):
    \\        return todo[int]()
;
/// Production with the whole derived ceiling written out, so a replacement can
/// narrow the clause while keeping the signature.
const p1_production_allocating =
    \\module production
    \\
    \\
    \\public domain Stub: int:
    \\    def make(discount: int) -> Stub effects():
    \\        return wrap[Stub](discount)
    \\
    \\    def price(policy: Stub, ledger: mut list[int], rates: list[int], subtotal: int) -> int effects(mutation, managed_allocation):
    \\        return todo[int]()
;
const p1_production_bad_interface =
    \\module mismatched
    \\
    \\
    \\public domain Stub: int:
    \\    def make(discount: int) -> Stub effects():
    \\        return wrap[Stub](discount)
    \\
    \\    def price(policy: Stub, ledger: list[int], rates: list[int], subtotal: int) -> int effects():
    \\        return subtotal
;
const p1_main =
    \\module main
    \\import production
    \\
    \\
    \\def main() -> int:
    \\    return 0
    \\
    \\
    \\public def test_checkout() -> bool:
    \\    policy = production.Stub.make(250)
    \\    ledger: list[int] = [0]
    \\    rates: list[int] = [0]
    \\    return production.Stub.price(policy, mut ledger, rates, 2000) == 1750
;
/// A replacement `production.Stub.price` whose managed parameters, effect
/// clause and first body line vary; `ledger` is the production footprint.
fn p1Fake(parameters: []const u8, perm: []const u8, body: []const u8) ![]const u8 {
    return std.fmt.allocPrint(
        testing.allocator,
        "module production\n\n\npublic domain Stub: int:\n" ++
            "    def make(discount: int) -> Stub effects():\n        return wrap[Stub](discount)\n\n" ++
            "    def price(policy: Stub, {s}, subtotal: int) -> int {s}:\n        {s}\n        return subtotal - unwrap(policy)\n",
        .{ parameters, perm, body },
    );
}
/// The production footprint: `ledger` written, `rates` read-only.
const p1_footprint = "ledger: mut list[int], rates: list[int]";
const p1_write = "ledger[0] = subtotal";
fn p1WriteCases(dir: *std.testing.TmpDir, name: []const u8, key: []const u8, source: []const u8) !void {
    const a = testing.allocator;
    var providers: std.json.ObjectMap = .empty;
    defer providers.deinit(a);
    try providers.put(a, key, .{ .string = source });
    var settings: std.json.ObjectMap = .empty;
    defer settings.deinit(a);
    try settings.put(a, "providers", .{ .object = providers });
    var root: std.json.ObjectMap = .empty;
    defer root.deinit(a);
    try root.put(a, "main::test_checkout", .{ .object = settings });
    const bytes = try std.json.Stringify.valueAlloc(a, std.json.Value{ .object = root }, .{});
    defer a.free(bytes);
    try dir.dir.writeFile(testing.io, .{ .sub_path = name, .data = bytes });
}
fn p1Invoke(entry: []const u8, cases_path: ?[]const u8, cache: []const u8) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    const cache_arg = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_arg);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "test", entry, "--filter", "test_checkout", "--json", cache_arg });
    if (cases_path) |path| try args.appendSlice(testing.allocator, &.{ "--cases", path });
    try args.appendSlice(testing.allocator, &tools);
    return runCompiler(testing.allocator, args.items);
}

// spec-case: NATIVE-TEST-3
// spec: NATIVE-TEST-5
test "P1 selects a validated fake while the unfinished production body is never checked" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.my", p1_main);
    try writeProjectFile(&temp, "production.my", p1_production_unfinished);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const cases_path = try std.fs.path.join(testing.allocator, &.{ root, "cases.json" });
    defer testing.allocator.free(cases_path);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);

    const fake = try p1Fake(p1_footprint, "effects(mutation)", p1_write);
    defer testing.allocator.free(fake);
    try p1WriteCases(&temp, "cases.json", "production.my", fake);

    // Same consumer test passes against the fake while production returns todo[T]().
    const first = try p1Invoke(entry, cases_path, cache);
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    try testing.expect(std.mem.indexOf(u8, first.stdout, "\"passed\":1") != null);
    try testing.expect(std.mem.indexOf(u8, first.stdout, "\"contract\":") != null);
    try testing.expect(std.mem.indexOf(u8, first.stdout, "\"provider\":") != null);
    try testing.expect(std.mem.indexOf(u8, first.stdout, "\"source\":") != null);

    // The verified receipt is reused while nothing changed.
    const warm = try p1Invoke(entry, cases_path, cache);
    defer testing.allocator.free(warm.stdout);
    defer testing.allocator.free(warm.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, warm.term);
    try testing.expect(std.mem.indexOf(u8, warm.stdout, "\"cached\":1") != null);

    // Changing the fake value changes its identity and forces a fresh execution.
    const changed = try p1Fake(p1_footprint, "effects(mutation)", p1_write);
    defer testing.allocator.free(changed);
    const mutated = try std.mem.replaceOwned(u8, testing.allocator, changed, "return subtotal - unwrap(policy)", "return subtotal - unwrap(policy) + 1");
    defer testing.allocator.free(mutated);
    try p1WriteCases(&temp, "cases.json", "production.my", mutated);
    const edited = try p1Invoke(entry, cases_path, cache);
    defer testing.allocator.free(edited.stdout);
    defer testing.allocator.free(edited.stderr);
    try testing.expect(std.mem.indexOf(u8, edited.stdout, "\"cached\":0") != null);
    try testing.expect(std.mem.indexOf(u8, edited.stdout, "\"executed\":1") != null);
    try testing.expect(std.mem.indexOf(u8, edited.stdout, "\"failed\":1") != null);

    // A full production check still rejects the unfinished body.
    const full = try p1Invoke(entry, null, cache);
    defer testing.allocator.free(full.stdout);
    defer testing.allocator.free(full.stderr);
    try testing.expect(full.term != .exited or full.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, full.stderr, "E_TYPED_HOLE") != null);
}

// spec-case: NATIVE-TEST-3
test "P1 rejects stronger or malformed replacements and a bad production interface" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.my", p1_main);
    try writeProjectFile(&temp, "production.my", p1_production_allocating);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const cases_path = try std.fs.path.join(testing.allocator, &.{ root, "cases.json" });
    defer testing.allocator.free(cases_path);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);

    // A narrower effect clause is accepted.
    const narrow = try p1Fake(p1_footprint, "effects(mutation)", p1_write);
    defer testing.allocator.free(narrow);
    try p1WriteCases(&temp, "cases.json", "production.my", narrow);
    const accepted = try p1Invoke(entry, cases_path, cache);
    defer testing.allocator.free(accepted.stdout);
    defer testing.allocator.free(accepted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, accepted.term);

    // The `mut` footprint is part of the signature every caller writes against
    // (`price(policy, mut ledger, rates, ...)`), so a replacement may neither
    // drop a `mut` nor add one.
    for ([_][2][]const u8{
        .{ "ledger: list[int], rates: list[int]", "_ = subtotal" },
        .{ "ledger: mut list[int], rates: mut list[int]", "ledger[0] = subtotal\n        rates[0] = subtotal" },
    }) |footprint| {
        const changed = try p1Fake(footprint[0], "effects(mutation)", footprint[1]);
        defer testing.allocator.free(changed);
        try p1WriteCases(&temp, "cases.json", "production.my", changed);
        const rejected = try p1Invoke(entry, cases_path, cache);
        defer testing.allocator.free(rejected.stdout);
        defer testing.allocator.free(rejected.stderr);
        try testing.expect(rejected.term != .exited or rejected.term.exited != 0);
        try testing.expect(std.mem.indexOf(u8, rejected.stderr, "IncompatibleProvider") != null);
    }

    // An unknown replacement path rejects without touching a production body.
    try p1WriteCases(&temp, "cases.json", "nope.my", narrow);
    const unknown = try p1Invoke(entry, cases_path, cache);
    defer testing.allocator.free(unknown.stdout);
    defer testing.allocator.free(unknown.stderr);
    try testing.expect(unknown.term != .exited or unknown.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, unknown.stderr, "InvalidTestProviders") != null);

    // A production interface error rejects before any provider is selected.
    try writeProjectFile(&temp, "production.my", p1_production_bad_interface);
    try p1WriteCases(&temp, "cases.json", "production.my", narrow);
    const interface_error = try p1Invoke(entry, cases_path, cache);
    defer testing.allocator.free(interface_error.stdout);
    defer testing.allocator.free(interface_error.stderr);
    try testing.expect(interface_error.term != .exited or interface_error.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, interface_error.stderr, "E_MODULE_NAME") != null);
}

// spec-case: NATIVE-TEST-3
test "P1 rejects every incompatible replacement dimension" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.my", p1_main);
    try writeProjectFile(&temp, "production.my", p1_production_unfinished);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const cases_path = try std.fs.path.join(testing.allocator, &.{ root, "cases.json" });
    defer testing.allocator.free(cases_path);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);

    const base = try p1Fake(p1_footprint, "effects(mutation)", p1_write);
    defer testing.allocator.free(base);
    const variants = [_]struct { label: []const u8, from: []const u8, to: []const u8 }{
        .{ .label = "parameter type", .from = "subtotal: int) -> int", .to = "subtotal: bool) -> int" },
        .{ .label = "parameter default", .from = "subtotal: int) -> int", .to = "subtotal: int = 0) -> int" },
        .{ .label = "nominal identity", .from = "Stub", .to = "Other" },
        .{ .label = "generic requirement", .from = "def price(policy:", .to = "def price[T: copy](policy:" },
        .{ .label = "effects too wide", .from = "effects(mutation)", .to = "effects(mutation, managed_allocation)" },
    };
    for (variants) |variant| {
        const changed = try std.mem.replaceOwned(u8, testing.allocator, base, variant.from, variant.to);
        defer testing.allocator.free(changed);
        try p1WriteCases(&temp, "cases.json", "production.my", changed);
        const result = try p1Invoke(entry, cases_path, cache);
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        testing.expect(result.term != .exited or result.term.exited != 0) catch |err| {
            std.debug.print("variant {s} was accepted\n", .{variant.label});
            return err;
        };
        testing.expect(std.mem.indexOf(u8, result.stderr, "IncompatibleProvider") != null) catch |err| {
            std.debug.print("variant {s} failed without IncompatibleProvider: {s}\n", .{ variant.label, result.stderr });
            return err;
        };
    }
}

// spec-case: NATIVE-TEST-3
test "P1 ignores an unselected production body type error while its declarations stay valid" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const production_body_error =
        \\module production
        \\
        \\
        \\public domain Stub: int:
        \\    def make(discount: int) -> Stub effects():
        \\        return wrap[Stub](discount)
        \\
        \\    def price(policy: Stub, ledger: mut list[int], rates: list[int], subtotal: int) -> int effects(mutation):
        \\        return True
    ;
    try writeProjectFile(&temp, "main.my", p1_main);
    try writeProjectFile(&temp, "production.my", production_body_error);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const cases_path = try std.fs.path.join(testing.allocator, &.{ root, "cases.json" });
    defer testing.allocator.free(cases_path);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);

    const fake = try p1Fake(p1_footprint, "effects(mutation)", p1_write);
    defer testing.allocator.free(fake);
    try p1WriteCases(&temp, "cases.json", "production.my", fake);
    const selected = try p1Invoke(entry, cases_path, cache);
    defer testing.allocator.free(selected.stdout);
    defer testing.allocator.free(selected.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, selected.term);
    try testing.expect(std.mem.indexOf(u8, selected.stdout, "\"passed\":1") != null);

    const full = try p1Invoke(entry, null, cache);
    defer testing.allocator.free(full.stdout);
    defer testing.allocator.free(full.stderr);
    try testing.expect(full.term != .exited or full.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, full.stderr, "E_TYPE") != null);
}

// --- R3: canonical declaration-level type descriptors ---

fn r3TestInvoke(entry: []const u8, cases_path: ?[]const u8, cache: []const u8) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    const cache_arg = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_arg);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "test", entry, "--json", cache_arg });
    if (cases_path) |path| try args.appendSlice(testing.allocator, &.{ "--cases", path });
    try args.appendSlice(testing.allocator, &tools);
    return runCompiler(testing.allocator, args.items);
}
fn r3WriteCases(dir: *std.testing.TmpDir, name: []const u8, qualified: []const u8, key: []const u8, source: []const u8) !void {
    const a = testing.allocator;
    var providers: std.json.ObjectMap = .empty;
    defer providers.deinit(a);
    try providers.put(a, key, .{ .string = source });
    var settings: std.json.ObjectMap = .empty;
    defer settings.deinit(a);
    try settings.put(a, "providers", .{ .object = providers });
    var root: std.json.ObjectMap = .empty;
    defer root.deinit(a);
    try root.put(a, qualified, .{ .object = settings });
    const bytes = try std.json.Stringify.valueAlloc(a, std.json.Value{ .object = root }, .{});
    defer a.free(bytes);
    try dir.dir.writeFile(testing.io, .{ .sub_path = name, .data = bytes });
}

const r3_alias_main =
    \\module main
    \\
    \\
    \\public type Truth = bool
    \\public type Count = int
    \\public type Counts = [2]Count
    \\public class Pair[T]:
    \\    left: T
    \\    right: T
    \\public type Chosen = Pair[Count]
    \\
    \\
    \\public def size(values: Counts) -> Count effects():
    \\    return values[0] + values[1]
    \\
    \\
    \\public def pick(value: Chosen) -> Count effects():
    \\    return value.left
    \\
    \\
    \\public def test_alias() -> Truth effects():
    \\    return True
    \\
    \\
    \\def main() -> int:
    \\    return 0
;

// spec-case: NATIVE-TEST-3
test "R3 canonical descriptors expand transparent aliases for discovery and nested contracts" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.my", r3_alias_main);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);

    // A boolean alias is discovered with the same default expectation as bool.
    const tested = try r3TestInvoke(entry, null, cache);
    defer testing.allocator.free(tested.stdout);
    defer testing.allocator.free(tested.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, tested.term);
    try testing.expect(std.mem.indexOf(u8, tested.stdout, "\"passed\":1") != null);

    // The producer descriptor is canonical through nested transparent aliases.
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "list-interfaces", "--contracts", entry });
    const contracts = try runCompiler(testing.allocator, args.items);
    defer testing.allocator.free(contracts.stdout);
    defer testing.allocator.free(contracts.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, contracts.term);
    try testing.expect(std.mem.indexOf(u8, contracts.stdout, "\"version\":\"interface-contracts-v2\"") != null);
    for ([_][]const u8{
        "{\"name\":\"Count\",\"kind\":\"alias\",\"signature\":\"\",\"generics\":\"\",\"permissions\":\"\",\"shape\":\"target:i64\"}",
        "{\"name\":\"Counts\",\"kind\":\"alias\",\"signature\":\"\",\"generics\":\"\",\"permissions\":\"\",\"shape\":\"target:[2]i64\"}",
        "{\"name\":\"Chosen\",\"kind\":\"alias\",\"signature\":\"\",\"generics\":\"\",\"permissions\":\"\",\"shape\":\"target:main::Pair[i64]\"}",
        "{\"name\":\"size\",\"kind\":\"function\",\"signature\":\"def(values:[2]i64)->i64\"",
        "{\"name\":\"pick\",\"kind\":\"function\",\"signature\":\"def(value:main::Pair[i64])->i64\"",
        "{\"name\":\"test_alias\",\"kind\":\"function\",\"signature\":\"def()->bool\"",
    }) |needle| {
        testing.expect(std.mem.indexOf(u8, contracts.stdout, needle) != null) catch |err| {
            std.debug.print("missing canonical contract fragment: {s}\n", .{needle});
            return err;
        };
    }
}

const r3_scalar_main =
    \\module main
    \\import reading
    \\
    \\
    \\public def test_reading() -> bool effects():
    \\    return reading.sample() == 42
    \\
    \\
    \\def main() -> int:
    \\    return 0
;
const r3_scalar_production =
    \\module reading
    \\
    \\
    \\public def sample() -> int effects():
    \\    return todo[int]()
;
const r3_nominal_main =
    \\module main
    \\import reading
    \\
    \\
    \\public def test_reading() -> bool effects():
    \\    return True
    \\
    \\
    \\def main() -> int:
    \\    return 0
;
const r3_nominal_production =
    \\module reading
    \\
    \\
    \\public domain D: i64:
    \\    def make(x: i64) -> D effects():
    \\        return wrap[D](x)
    \\
    \\
    \\public def sample() -> D effects():
    \\    return todo[D]()
;
const r3_nominal_fake =
    \\module reading
    \\
    \\
    \\public domain D: i64:
    \\    def make(x: i64) -> D effects():
    \\        return wrap[D](x)
    \\
    \\
    \\public domain E: i64:
    \\    def make(x: i64) -> E effects():
    \\        return wrap[E](x)
    \\
    \\
    \\public def sample() -> E effects():
    \\    return E.make(1)
;

// spec-case: NATIVE-TEST-3
test "R3 canonical descriptors compare provider scalar and nominal contracts" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.my", r3_scalar_main);
    try writeProjectFile(&temp, "reading.my", r3_scalar_production);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const cases_path = try std.fs.path.join(testing.allocator, &.{ root, "cases.json" });
    defer testing.allocator.free(cases_path);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);

    const equivalent =
        \\module reading
        \\
        \\
        \\public def sample() -> i64 effects():
        \\    return 42
    ;
    try r3WriteCases(&temp, "cases.json", "main::test_reading", "reading.my", equivalent);
    const accepted = try r3TestInvoke(entry, cases_path, cache);
    defer testing.allocator.free(accepted.stdout);
    defer testing.allocator.free(accepted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, accepted.term);
    try testing.expect(std.mem.indexOf(u8, accepted.stdout, "\"passed\":1") != null);

    const scalar_variants = [_][]const u8{
        \\module reading
        \\
        \\
        \\public def sample() -> u8 effects():
        \\    return 42
        ,
        \\module reading
        \\
        \\
        \\public def sample() -> str effects():
        \\    return "x"
        ,
    };
    for (scalar_variants) |fake| {
        try r3WriteCases(&temp, "cases.json", "main::test_reading", "reading.my", fake);
        const rejected = try r3TestInvoke(entry, cases_path, cache);
        defer testing.allocator.free(rejected.stdout);
        defer testing.allocator.free(rejected.stderr);
        try testing.expect(rejected.term != .exited or rejected.term.exited != 0);
        try testing.expect(std.mem.indexOf(u8, rejected.stderr, "IncompatibleProvider") != null);
    }

    try writeProjectFile(&temp, "main.my", r3_nominal_main);
    try writeProjectFile(&temp, "reading.my", r3_nominal_production);
    try r3WriteCases(&temp, "cases.json", "main::test_reading", "reading.my", r3_nominal_fake);
    const nominal = try r3TestInvoke(entry, cases_path, cache);
    defer testing.allocator.free(nominal.stdout);
    defer testing.allocator.free(nominal.stderr);
    try testing.expect(nominal.term != .exited or nominal.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, nominal.stderr, "IncompatibleProvider") != null);
}

// C3 concrete-specialization reuse is not yet registered in SPEC.md; this block
// is the fresh-process regression evidence and must be reported with its patch.

fn c3sCheckProjectReport(path: []const u8, cache_argument: []const u8, no_cache: bool) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "check-project", path, "--report" });
    if (cache_argument.len != 0) try args.append(testing.allocator, cache_argument);
    if (no_cache) try args.append(testing.allocator, "--no-cache");
    return std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
}

fn c3sCheckReport(path: []const u8, cache_argument: []const u8, no_cache: bool) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "check", path, "--report" });
    if (cache_argument.len != 0) try args.append(testing.allocator, cache_argument);
    if (no_cache) try args.append(testing.allocator, "--no-cache");
    return std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
}

/// First semantic file whose payload carries the `specialization-v1` stable-key
/// prefix. The durable file name is a hash, so the kind marker is the discriminator.
fn c3sFirstSpecializationFile(allocator: std.mem.Allocator, cache_base: []const u8) ![]u8 {
    const version_dir = try std.fs.path.join(allocator, &.{ cache_base, "semantic", "semantic-cache-v2" });
    defer allocator.free(version_dir);
    var directory = std.Io.Dir.cwd().openDir(testing.io, version_dir, .{ .iterate = true }) catch return error.MissingSpecializationEntry;
    defer directory.close(testing.io);
    var contracts = directory.iterate();
    while (contracts.next(testing.io) catch return error.MissingSpecializationEntry) |contract| {
        if (contract.kind != .directory) continue;
        const contract_dir = try std.fs.path.join(allocator, &.{ version_dir, contract.name });
        defer allocator.free(contract_dir);
        var entries = std.Io.Dir.cwd().openDir(testing.io, contract_dir, .{ .iterate = true }) catch continue;
        defer entries.close(testing.io);
        var files = entries.iterate();
        while (files.next(testing.io) catch return error.MissingSpecializationEntry) |file| {
            if (file.kind != .file or std.mem.endsWith(u8, file.name, ".tmp")) continue;
            const path = try std.fs.path.join(allocator, &.{ contract_dir, file.name });
            const bytes = std.Io.Dir.cwd().readFileAlloc(testing.io, path, allocator, .limited(1024 * 1024)) catch {
                allocator.free(path);
                continue;
            };
            defer allocator.free(bytes);
            if (std.mem.indexOf(u8, bytes, "spec\x1fv1\x1f") != null) return path;
            allocator.free(path);
        }
    }
    return error.MissingSpecializationEntry;
}

// spec-case: SEMANTIC-CACHE-12
test "C3s concrete specialization reuse survives fresh processes with selective invalidation" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(directory);
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.my" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);

    const library_render40 =
        \\module lib
        \\
        \\
        \\public def render[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 40
        \\
        \\
        \\public def label[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 7
    ;
    const library_render41 =
        \\module lib
        \\
        \\
        \\public def render[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 41
        \\
        \\
        \\public def label[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 7
    ;
    const library_label8 =
        \\module lib
        \\
        \\
        \\public def render[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 41
        \\
        \\
        \\public def label[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 8
    ;
    const entry_u8 =
        \\module main
        \\import lib
        \\
        \\
        \\def main() -> i64:
        \\    return lib.render[u8](1u8) + lib.label[i64](2)
    ;
    const entry_split =
        \\module main
        \\import lib
        \\
        \\
        \\def main() -> i64:
        \\    a = lib.render[u8](1u8)
        \\    return a + lib.label[i64](2)
    ;
    const entry_i64 =
        \\module main
        \\import lib
        \\
        \\
        \\def main() -> i64:
        \\    return lib.render[i64](1) + lib.label[i64](2)
    ;

    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib.my", .data = library_render40 });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = entry_u8 });
    const seed = try c3sCheckProjectReport(entry, cache_argument, false);
    defer testing.allocator.free(seed.stdout);
    defer testing.allocator.free(seed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, seed.term);
    const cold = try c2Counts(seed.stderr);
    try testing.expectEqual(@as(usize, 0), cold.reused);

    // A body edit in the entry forces a recheck; both concrete specializations
    // replay even though the source bytes changed.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = entry_split });
    const warm = try c3sCheckProjectReport(entry, cache_argument, false);
    defer testing.allocator.free(warm.stdout);
    defer testing.allocator.free(warm.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, warm.term);
    const unchanged = try c2Counts(warm.stderr);
    try testing.expectEqual(@as(usize, 2), unchanged.reused);
    try testing.expectEqual(@as(usize, 1), unchanged.performed);

    // Editing `render`'s template body invalidates only its specialization;
    // `label[i64]` remains reusable.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib.my", .data = library_render41 });
    const template_edit = try c3sCheckProjectReport(entry, cache_argument, false);
    defer testing.allocator.free(template_edit.stdout);
    defer testing.allocator.free(template_edit.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, template_edit.term);
    const template_counts = try c2Counts(template_edit.stderr);
    try testing.expectEqual(@as(usize, 1), template_counts.reused);
    try testing.expectEqual(@as(usize, 2), template_counts.performed);

    // Editing the concrete argument instantiates a fresh `render[i64]` while
    // `label[i64]` still replays.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = entry_i64 });
    const argument_edit = try c3sCheckProjectReport(entry, cache_argument, false);
    defer testing.allocator.free(argument_edit.stdout);
    defer testing.allocator.free(argument_edit.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, argument_edit.term);
    const argument_counts = try c2Counts(argument_edit.stderr);
    try testing.expectEqual(@as(usize, 1), argument_counts.reused);
    try testing.expectEqual(@as(usize, 2), argument_counts.performed);

    // Editing `label`'s template body invalidates only its specialization.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib.my", .data = library_label8 });
    const label_edit = try c3sCheckProjectReport(entry, cache_argument, false);
    defer testing.allocator.free(label_edit.stdout);
    defer testing.allocator.free(label_edit.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, label_edit.term);
    const label_counts = try c2Counts(label_edit.stderr);
    try testing.expectEqual(@as(usize, 1), label_counts.reused);
    try testing.expectEqual(@as(usize, 2), label_counts.performed);

    // Cold/warm agreement: an uncached check accepts exactly like the cached one.
    const uncached = try c3sCheckProjectReport(entry, cache_argument, true);
    defer testing.allocator.free(uncached.stdout);
    defer testing.allocator.free(uncached.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, uncached.term);
    const uncached_counts = try c2Counts(uncached.stderr);
    try testing.expectEqual(@as(usize, 0), uncached_counts.reused);
    try testing.expectEqual(@as(usize, 3), uncached_counts.performed);
}

test "C3s provider body changes stay visible through reused specializations" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(directory);
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.my" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    const base_library =
        \\module lib
        \\
        \\
        \\def helper(n: i64) -> i64 effects():
        \\    return n + 1
        \\
        \\
        \\public def render[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return helper(40)
    ;
    const edited_library =
        \\module lib
        \\
        \\
        \\def helper(n: i64) -> i64 effects():
        \\    return n + 2
        \\
        \\
        \\public def render[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return helper(40)
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib.my", .data = base_library });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\module main
        \\import lib
        \\
        \\
        \\def main() -> i64:
        \\    return lib.render[u8](1u8)
    });
    const warm_argv = [_][]const u8{ compiler_path, "run-project", entry, "--print-result", cache_argument };
    const first = try std.process.run(testing.allocator, testing.io, .{ .argv = &warm_argv });
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 41 }, first.term);
    try testing.expectEqualStrings("41\n", first.stdout);

    // The provider body edit must appear in the generated code even though
    // `render`'s specialization region is unchanged.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib.my", .data = edited_library });
    const warm = try std.process.run(testing.allocator, testing.io, .{ .argv = &warm_argv });
    defer testing.allocator.free(warm.stdout);
    defer testing.allocator.free(warm.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, warm.term);
    try testing.expectEqualStrings("42\n", warm.stdout);
    const cold_argv = [_][]const u8{ compiler_path, "run-project", entry, "--print-result", "--no-cache" };
    const cold = try std.process.run(testing.allocator, testing.io, .{ .argv = &cold_argv });
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, cold.term);
    try testing.expectEqualStrings(warm.stdout, cold.stdout);
}

test "C3s damaged truncated and foreign specialization entries fall back fresh" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(directory);
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.my" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    const source =
        \\def size[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 7
        \\
        \\
        \\def main() -> i64:
        \\    return size[u8](1u8)
    ;
    const edited =
        \\def size[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 7
        \\
        \\
        \\def main() -> i64:
        \\    value = size[u8](1u8)
        \\    return value
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = source });
    const seed = try c3sCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(seed.stdout);
    defer testing.allocator.free(seed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, seed.term);
    const spec_file = try c3sFirstSpecializationFile(testing.allocator, cache_base);
    defer testing.allocator.free(spec_file);

    const original_len = try c2FileLength(spec_file);
    try c2SetFileLength(spec_file, original_len / 2);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = edited });
    const truncated = try c3sCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(truncated.stdout);
    defer testing.allocator.free(truncated.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, truncated.term);
    try testing.expectEqual(@as(usize, 0), (try c2Counts(truncated.stderr)).reused);

    // Republish a clean entry, then simulate a foreign format version.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = source });
    const republished = try c3sCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(republished.stdout);
    defer testing.allocator.free(republished.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, republished.term);
    const version_bytes = try std.Io.Dir.cwd().readFileAlloc(testing.io, spec_file, testing.allocator, .limited(1024 * 1024));
    defer testing.allocator.free(version_bytes);
    version_bytes[12] ^= 0x20;
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = spec_file, .data = version_bytes });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = edited });
    const foreign = try c3sCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(foreign.stdout);
    defer testing.allocator.free(foreign.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, foreign.term);
    try testing.expectEqual(@as(usize, 0), (try c2Counts(foreign.stderr)).reused);
}

test "C3s no-cache performs specialization checks without reads or writes" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(directory);
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.my" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "nocache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\def size[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 7
        \\
        \\
        \\def main() -> i64:
        \\    return size[u8](1u8)
    });
    const first = try c3sCheckReport(entry, cache_argument, true);
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    const counts = try c2Counts(first.stderr);
    try testing.expect(counts.performed > 0);
    try testing.expectEqual(@as(usize, 0), counts.reused);
    const second = try c3sCheckReport(entry, cache_argument, true);
    defer testing.allocator.free(second.stdout);
    defer testing.allocator.free(second.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, second.term);
    try testing.expectEqual(@as(usize, 0), (try c2Counts(second.stderr)).reused);
    try testing.expect(!c2PathExists(cache_base));
}

test "C3s reused specialization warnings relocate and defaults stay equivalent" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(directory);
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.my" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    const base =
        \\def size[T: integer](value: T, extra: i64 = 5) -> i64 effects():
        \\    unused_local = 3
        \\    _ = value
        \\    return extra
        \\
        \\
        \\def main() -> i64:
        \\    return size[u8](1u8)
    ;
    const edited =
        \\type Marker = i64
        \\
        \\
        \\def size[T: integer](value: T, extra: i64 = 5) -> i64 effects():
        \\    unused_local = 3
        \\    _ = value
        \\    return extra
        \\
        \\
        \\def main() -> i64:
        \\    a = size[u8](1u8)
        \\    return a
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = base });
    const seed = try c3sCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(seed.stdout);
    defer testing.allocator.free(seed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, seed.term);

    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = edited });
    const warm = try c3sCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(warm.stdout);
    defer testing.allocator.free(warm.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, warm.term);
    const counts = try c2Counts(warm.stderr);
    try testing.expectEqual(@as(usize, 1), counts.reused);
    try testing.expectEqual(@as(usize, 1), counts.performed);

    const cold = try c3sCheckReport(entry, cache_argument, true);
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cold.term);
    // The replayed body's unused-binding warning must relocate to the edited
    // source and render byte-identically to the uncached check.
    try testing.expectEqualStrings(try c2WarningLine(cold.stderr), try c2WarningLine(warm.stderr));
}

// ---------------------------------------------------------------------------
// C4 native test preparation: reduced checked graphs and receipt reuse
// ---------------------------------------------------------------------------

const c4_main =
    \\module main
    \\import helpers
    \\
    \\
    \\def main() -> int:
    \\    return 0
    \\
    \\
    \\public def test_a(x: i64) -> bool effects():
    \\    return helpers.a() == x
    \\
    \\
    \\public def test_b() -> bool effects():
    \\    return helpers.b() == 2
;
const c4_helpers =
    \\module helpers
    \\
    \\
    \\public def a() -> i64 effects():
    \\    return 1
    \\
    \\
    \\public def b() -> i64 effects():
    \\    return 2
;
const c4_cases =
    \\{"main::test_a":{"arguments":{"x":"1"},"expected":true},"main::test_b":{"expected":true}}
;

const C4Counts = struct { passed: usize, failed: usize, skipped: usize, cached: usize, executed: usize };

fn c4Counts(stdout: []const u8) !C4Counts {
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, stdout, .{});
    defer parsed.deinit();
    const root = parsed.value;
    return .{
        .passed = @intCast(root.object.get("passed").?.integer),
        .failed = @intCast(root.object.get("failed").?.integer),
        .skipped = @intCast(root.object.get("skipped").?.integer),
        .cached = @intCast(root.object.get("cached").?.integer),
        .executed = @intCast(root.object.get("executed").?.integer),
    };
}

fn c4TraceReset(path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(testing.io, path) catch {};
}

fn c4TraceCount(path: []const u8, needle: []const u8) !usize {
    const bytes = std.Io.Dir.cwd().readFileAlloc(testing.io, path, testing.allocator, .limited(1 << 20)) catch return 0;
    defer testing.allocator.free(bytes);
    return std.mem.count(u8, bytes, needle);
}

/// One `work-report-v1` line for a named child command.
fn c4CommandWorkLine(stderr: []const u8, command: []const u8) ![]const u8 {
    const marker = try std.fmt.allocPrint(testing.allocator, "\"command\":\"{s}\"", .{command});
    defer testing.allocator.free(marker);
    var lines = std.mem.splitScalar(u8, stderr, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "work-report-v1") == null) continue;
        if (std.mem.indexOf(u8, line, marker) != null) return line;
    }
    return error.MissingWorkReport;
}
/// The parent `command:"test"` work-report line, distinct from compiler children.
fn c4WorkLine(stderr: []const u8) ![]const u8 {
    return c4CommandWorkLine(stderr, "test");
}
fn c4WorkCount(line: []const u8, stage: []const u8, field: []const u8) !usize {
    const marker = try std.fmt.allocPrint(testing.allocator, "\"{s}\"", .{stage});
    defer testing.allocator.free(marker);
    const start = std.mem.indexOf(u8, line, marker) orelse return error.MissingWorkReport;
    const end = std.mem.indexOfPos(u8, line, start, "}") orelse return error.MissingWorkReport;
    const section = line[start..end];
    const field_marker = try std.fmt.allocPrint(testing.allocator, "\"{s}\":", .{field});
    defer testing.allocator.free(field_marker);
    const at = std.mem.indexOf(u8, section, field_marker) orelse return error.MissingWorkReport;
    const digits = section[at + field_marker.len ..];
    var end_of_digits: usize = 0;
    while (end_of_digits < digits.len and std.ascii.isDigit(digits[end_of_digits])) end_of_digits += 1;
    if (end_of_digits == 0) return error.MissingWorkReport;
    return std.fmt.parseInt(usize, digits[0..end_of_digits], 10) catch return error.MissingWorkReport;
}
fn c4WorkStatus(line: []const u8, stage: []const u8) ![]const u8 {
    const marker = try std.fmt.allocPrint(testing.allocator, "\"{s}\"", .{stage});
    defer testing.allocator.free(marker);
    const start = std.mem.indexOf(u8, line, marker) orelse return error.MissingWorkReport;
    const status_marker = "\"status\":\"";
    const at = std.mem.indexOfPos(u8, line, start, status_marker) orelse return error.MissingWorkReport;
    const value = line[at + status_marker.len ..];
    const end = std.mem.indexOfScalar(u8, value, '"') orelse return error.MissingWorkReport;
    return value[0..end];
}
fn c4Invoke(entry: []const u8, cases_path: ?[]const u8, cache: []const u8, trace: []const u8, extra: []const []const u8) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "test", entry, "--json", "--report" });
    if (cases_path) |path| try args.appendSlice(testing.allocator, &.{ "--cases", path });
    try args.appendSlice(testing.allocator, extra);
    const cache_arg = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_arg);
    try args.append(testing.allocator, cache_arg);
    try args.appendSlice(testing.allocator, &tools);
    var environment: std.process.Environ.Map = .init(testing.allocator);
    defer environment.deinit();
    try environment.put("MYLANG_TEST_TRACE", trace);
    try environment.put("HOME", std.fs.path.dirname(entry) orelse ".");
    try forwardZigCache(&environment);
    return spawnWithEnv(args.items, &environment);
}

fn c4Project(temp: *std.testing.TmpDir) !struct { entry: []const u8, root: []const u8, cases_path: []const u8, cache: []const u8, trace: []const u8 } {
    try writeProjectFile(temp, "main.my", c4_main);
    try writeProjectFile(temp, "helpers.my", c4_helpers);
    try writeProjectFile(temp, "cases.json", c4_cases);
    const root_sentinel = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root_sentinel);
    const root = try testing.allocator.dupe(u8, root_sentinel);
    return .{
        .entry = try std.fs.path.join(testing.allocator, &.{ root, "main.my" }),
        .root = root,
        .cases_path = try std.fs.path.join(testing.allocator, &.{ root, "cases.json" }),
        .cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" }),
        .trace = try std.fs.path.join(testing.allocator, &.{ root, "trace.log" }),
    };
}

// spec-case: NATIVE-TEST-5
// spec: NATIVE-TEST-6
test "C4 unchanged deterministic rerun executes zero tests without lowering emission or linking" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const project = try c4Project(&temp);
    defer testing.allocator.free(project.entry);
    defer testing.allocator.free(project.root);
    defer testing.allocator.free(project.cases_path);
    defer testing.allocator.free(project.cache);
    defer testing.allocator.free(project.trace);

    c4TraceReset(project.trace);
    const cold = try c4Invoke(project.entry, project.cases_path, project.cache, project.trace, &.{});
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cold.term);
    const cold_counts = try c4Counts(cold.stdout);
    try testing.expectEqual(@as(usize, 2), cold_counts.executed);
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(project.trace, "native-test-compile"));
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(project.trace, " build "));
    const cold_work = try c4WorkLine(cold.stderr);
    try testing.expectEqual(@as(usize, 2), try c4WorkCount(cold_work, "executed_tests", "performed"));
    try testing.expect(try c4WorkCount(cold_work, "lowered_functions", "performed") > 0);
    // One checked compilation per provider graph: the same child that produced
    // the facts also lowered the selected closure, and the linking driver never
    // spawned a second frontend to re-check it.
    try testing.expectEqual(@as(usize, 0), try c4TraceCount(project.trace, "emit-project-qbe"));
    const cold_compile = try c4CommandWorkLine(cold.stderr, "native-test-compile");
    try testing.expect(try c4WorkCount(cold_compile, "checked_bodies", "performed") > 0);
    const cold_lowered = try c4WorkCount(cold_compile, "lowered_functions", "performed");
    try testing.expect(cold_lowered > 0);
    // The checked fixture has five functions; closure selection must leave the
    // unreferenced `main` body out instead of lowering the whole project.
    try testing.expect(cold_lowered < 5);

    c4TraceReset(project.trace);
    const warm = try c4Invoke(project.entry, project.cases_path, project.cache, project.trace, &.{});
    defer testing.allocator.free(warm.stdout);
    defer testing.allocator.free(warm.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, warm.term);
    const warm_counts = try c4Counts(warm.stdout);
    try testing.expectEqual(@as(usize, 0), warm_counts.executed);
    try testing.expectEqual(@as(usize, 2), warm_counts.cached);
    try testing.expectEqual(@as(usize, 0), try c4TraceCount(project.trace, "native-test-compile"));
    try testing.expectEqual(@as(usize, 0), try c4TraceCount(project.trace, " build "));
    // Validity is still re-established through the shared query cache before any receipt.
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(project.trace, "check-project"));
    const warm_validity = try c4CommandWorkLine(warm.stderr, "check-project");
    try testing.expectEqualStrings("skipped", try c4WorkStatus(warm_validity, "lowered_functions"));
    const warm_work = try c4WorkLine(warm.stderr);
    try testing.expectEqual(@as(usize, 0), try c4WorkCount(warm_work, "executed_tests", "performed"));
    try testing.expectEqual(@as(usize, 2), try c4WorkCount(warm_work, "executed_tests", "reused"));
    try testing.expect(std.mem.indexOf(u8, warm_work, "\"lowered_functions\":{\"status\":\"skipped\"") != null);
}

// spec-case: NATIVE-TEST-5
test "C4 helper edit reruns only the dependent test and lower only on an uncached selection" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const project = try c4Project(&temp);
    defer testing.allocator.free(project.entry);
    defer testing.allocator.free(project.root);
    defer testing.allocator.free(project.cases_path);
    defer testing.allocator.free(project.cache);
    defer testing.allocator.free(project.trace);

    c4TraceReset(project.trace);
    const cold = try c4Invoke(project.entry, project.cases_path, project.cache, project.trace, &.{});
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cold.term);

    const edited_helpers = try std.mem.replaceOwned(u8, testing.allocator, c4_helpers, "return 1", "return 3");
    defer testing.allocator.free(edited_helpers);
    try writeProjectFile(&temp, "helpers.my", edited_helpers);
    c4TraceReset(project.trace);
    const edited = try c4Invoke(project.entry, project.cases_path, project.cache, project.trace, &.{});
    defer testing.allocator.free(edited.stdout);
    defer testing.allocator.free(edited.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, edited.term);
    const counts = try c4Counts(edited.stdout);
    try testing.expectEqual(@as(usize, 1), counts.executed);
    try testing.expectEqual(@as(usize, 1), counts.cached);
    try testing.expectEqual(@as(usize, 1), counts.failed);
    // The changed helper is in exactly one closure, so exactly one test executed.
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(project.trace, "native-test-compile"));
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(project.trace, " build "));
    const edited_build = try c4CommandWorkLine(edited.stderr, "native-test-compile");
    const edited_lowered = try c4WorkCount(edited_build, "lowered_functions", "performed");
    try testing.expect(edited_lowered > 0);
    // Cold built the union of both test closures; a helper edit lowers only the
    // one dependent test and its helper.
    const cold_build = try c4CommandWorkLine(cold.stderr, "native-test-compile");
    const cold_lowered = try c4WorkCount(cold_build, "lowered_functions", "performed");
    try testing.expect(cold_lowered > edited_lowered);
}

// spec-case: NATIVE-TEST-5
test "C4 invalid selected project fails before any green result" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const project = try c4Project(&temp);
    defer testing.allocator.free(project.entry);
    defer testing.allocator.free(project.root);
    defer testing.allocator.free(project.cases_path);
    defer testing.allocator.free(project.cache);
    defer testing.allocator.free(project.trace);

    const cold = try c4Invoke(project.entry, project.cases_path, project.cache, project.trace, &.{});
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cold.term);

    const invalid_main = try std.mem.replaceOwned(u8, testing.allocator, c4_main, "return helpers.a() == x", "return 42");
    defer testing.allocator.free(invalid_main);
    try writeProjectFile(&temp, "main.my", invalid_main);
    const invalid = try c4Invoke(project.entry, project.cases_path, project.cache, project.trace, &.{});
    defer testing.allocator.free(invalid.stdout);
    defer testing.allocator.free(invalid.stderr);
    try testing.expect(invalid.term != .exited or invalid.term.exited != 0);
    try testing.expectEqual(@as(usize, 0), invalid.stdout.len);
    try testing.expect(std.mem.indexOf(u8, invalid.stderr, "E_TYPE") != null);
}

// spec-case: NATIVE-TEST-5
// spec-case: NATIVE-TEST-12
test "C4 expectation argument budget and force invalidate while irrelevant environment preserves receipts" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const project = try c4Project(&temp);
    defer testing.allocator.free(project.entry);
    defer testing.allocator.free(project.root);
    defer testing.allocator.free(project.cases_path);
    defer testing.allocator.free(project.cache);
    defer testing.allocator.free(project.trace);

    const seed = try c4Invoke(project.entry, project.cases_path, project.cache, project.trace, &.{});
    defer testing.allocator.free(seed.stdout);
    defer testing.allocator.free(seed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, seed.term);

    // A changed test argument invalidates only that test's receipt.
    const changed_cases = "{\"main::test_a\":{\"arguments\":{\"x\":\"2\"},\"expected\":false},\"main::test_b\":{\"expected\":true}}";
    try writeProjectFile(&temp, "cases.json", changed_cases);
    const argument = try c4Invoke(project.entry, project.cases_path, project.cache, project.trace, &.{});
    defer testing.allocator.free(argument.stdout);
    defer testing.allocator.free(argument.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, argument.term);
    const argument_counts = try c4Counts(argument.stdout);
    try testing.expectEqual(@as(usize, 1), argument_counts.executed);
    try testing.expectEqual(@as(usize, 1), argument_counts.cached);

    // A changed expectation likewise invalidates only the edited test.
    const changed_expectation = "{\"main::test_a\":{\"arguments\":{\"x\":\"2\"},\"expected\":false},\"main::test_b\":{\"expected\":false}}";
    try writeProjectFile(&temp, "cases.json", changed_expectation);
    const expectation = try c4Invoke(project.entry, project.cases_path, project.cache, project.trace, &.{});
    defer testing.allocator.free(expectation.stdout);
    defer testing.allocator.free(expectation.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, expectation.term);
    const expectation_counts = try c4Counts(expectation.stdout);
    try testing.expectEqual(@as(usize, 1), expectation_counts.executed);
    try testing.expectEqual(@as(usize, 1), expectation_counts.cached);

    // A changed execution budget invalidates every receipt.
    const budget = try c4Invoke(project.entry, project.cases_path, project.cache, project.trace, &.{ "--max-steps", "500000" });
    defer testing.allocator.free(budget.stdout);
    defer testing.allocator.free(budget.stderr);
    try testing.expectEqual(@as(usize, 2), (try c4Counts(budget.stdout)).executed);

    // An unrelated inherited variable preserves valid receipts. `test_b` still
    // executes because its changed expectation failed and published no pass.
    var environment: std.process.Environ.Map = .init(testing.allocator);
    defer environment.deinit();
    try environment.put("MYLANG_TEST_TRACE", project.trace);
    try environment.put("HOME", project.root);
    try environment.put("MYLANG_C4_CHANGED", "1");
    try forwardZigCache(&environment);
    var env_args: std.ArrayList([]const u8) = .empty;
    defer env_args.deinit(testing.allocator);
    const cache_arg = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{project.cache});
    defer testing.allocator.free(cache_arg);
    try env_args.appendSlice(testing.allocator, &.{ compiler_path, "test", project.entry, "--json", "--cases", project.cases_path, "--report", cache_arg });
    try env_args.appendSlice(testing.allocator, &tools);
    const changed_env = try spawnWithEnv(env_args.items, &environment);
    defer testing.allocator.free(changed_env.stdout);
    defer testing.allocator.free(changed_env.stderr);
    const environment_counts = try c4Counts(changed_env.stdout);
    try testing.expectEqual(@as(usize, 1), environment_counts.executed);
    try testing.expectEqual(@as(usize, 1), environment_counts.cached);

    // Force re-executes every selected test even with a valid warm receipt.
    const forced = try c4Invoke(project.entry, project.cases_path, project.cache, project.trace, &.{"--force"});
    defer testing.allocator.free(forced.stdout);
    defer testing.allocator.free(forced.stderr);
    const forced_counts = try c4Counts(forced.stdout);
    try testing.expectEqual(@as(usize, 2), forced_counts.executed);
    try testing.expectEqual(@as(usize, 0), forced_counts.cached);
}

// spec-case: NATIVE-TEST-5
test "C4 two providers with reversed map order prepare one graph and one library" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "first.my", c4_first);
    try writeProjectFile(&temp, "second.my", c4_second);
    try writeProjectFile(&temp, "main.my", c4_provider_main);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.my" });
    defer testing.allocator.free(entry);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const trace = try std.fs.path.join(testing.allocator, &.{ root, "trace.log" });
    defer testing.allocator.free(trace);

    const provider_cases = try c4ProviderCases(testing.allocator, c4_first, c4_second);
    defer testing.allocator.free(provider_cases);
    try writeProjectFile(&temp, "cases.json", provider_cases);
    const cases_path = try std.fs.path.join(testing.allocator, &.{ root, "cases.json" });
    defer testing.allocator.free(cases_path);
    c4TraceReset(trace);
    const forced = try c4Invoke(entry, cases_path, cache, trace, &.{"--force"});
    defer testing.allocator.free(forced.stdout);
    defer testing.allocator.free(forced.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, forced.term);
    try testing.expectEqual(@as(usize, 2), (try c4Counts(forced.stdout)).executed);
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(trace, "native-test-compile"));
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(trace, " build "));

    // The same graph is reused when both provider maps select identical bytes.
    c4TraceReset(trace);
    const warm = try c4Invoke(entry, cases_path, cache, trace, &.{});
    defer testing.allocator.free(warm.stdout);
    defer testing.allocator.free(warm.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, warm.term);
    try testing.expectEqual(@as(usize, 2), (try c4Counts(warm.stdout)).cached);
    try testing.expectEqual(@as(usize, 0), try c4TraceCount(trace, "native-test-compile"));
    try testing.expectEqual(@as(usize, 0), try c4TraceCount(trace, " build "));

    // Changing one replacement's bytes invalidates only that case's graph and
    // receipt: the unchanged case keeps its graph and does not execute.
    const changed_first = try std.mem.replaceOwned(u8, testing.allocator, c4_first, "return 1", "return 1 + 0");
    defer testing.allocator.free(changed_first);
    const changed_cases = try c4ProviderCasesChanged(testing.allocator, c4_first, changed_first, c4_second);
    defer testing.allocator.free(changed_cases);
    try writeProjectFile(&temp, "cases.json", changed_cases);
    c4TraceReset(trace);
    const edited = try c4Invoke(entry, cases_path, cache, trace, &.{});
    defer testing.allocator.free(edited.stdout);
    defer testing.allocator.free(edited.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, edited.term);
    const edited_counts = try c4Counts(edited.stdout);
    try testing.expectEqual(@as(usize, 1), edited_counts.executed);
    try testing.expectEqual(@as(usize, 1), edited_counts.cached);
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(trace, "native-test-compile"));
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(trace, " build "));

    // A forced run still sees two distinct graphs: one per replacement byte set.
    c4TraceReset(trace);
    const distinct = try c4Invoke(entry, cases_path, cache, trace, &.{"--force"});
    defer testing.allocator.free(distinct.stdout);
    defer testing.allocator.free(distinct.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, distinct.term);
    try testing.expectEqual(@as(usize, 2), try c4TraceCount(trace, "native-test-compile"));
    try testing.expectEqual(@as(usize, 2), try c4TraceCount(trace, " build "));
}

// spec-case: NATIVE-TEST-5
test "C4 no-cache performs fresh runs without durable result or graph entries" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const project = try c4Project(&temp);
    defer testing.allocator.free(project.entry);
    defer testing.allocator.free(project.root);
    defer testing.allocator.free(project.cases_path);
    defer testing.allocator.free(project.cache);
    defer testing.allocator.free(project.trace);

    const first = try c4Invoke(project.entry, project.cases_path, project.cache, project.trace, &.{"--no-cache"});
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    try testing.expectEqual(@as(usize, 2), (try c4Counts(first.stdout)).executed);

    const second = try c4Invoke(project.entry, project.cases_path, project.cache, project.trace, &.{"--no-cache"});
    defer testing.allocator.free(second.stdout);
    defer testing.allocator.free(second.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, second.term);
    try testing.expectEqual(@as(usize, 2), (try c4Counts(second.stdout)).executed);
    try testing.expect(!c4DirHasFiles(project.cache, "results"));
    try testing.expect(!c4DirHasFiles(project.cache, "graphs"));
}

fn c4DirHasFiles(base: []const u8, leaf: []const u8) bool {
    const path = std.fs.path.join(testing.allocator, &.{ base, leaf }) catch return false;
    defer testing.allocator.free(path);
    var directory = std.Io.Dir.cwd().openDir(testing.io, path, .{ .iterate = true }) catch return false;
    defer directory.close(testing.io);
    var iterator = directory.iterate();
    while (iterator.next(testing.io) catch return false) |_| return true;
    return false;
}

const c4_first =
    \\module first
    \\
    \\
    \\public def value() -> i64 effects():
    \\    return 1
;
const c4_second =
    \\module second
    \\
    \\
    \\public def value() -> i64 effects():
    \\    return 2
;
const c4_provider_main =
    \\module main
    \\import first
    \\import second
    \\
    \\
    \\def main() -> int:
    \\    return 0
    \\
    \\
    \\public def test_one() -> bool effects():
    \\    return first.value() + second.value() == 3
    \\
    \\
    \\public def test_two() -> bool effects():
    \\    return second.value() + first.value() == 3
;

fn c4ProviderCases(allocator: std.mem.Allocator, first: []const u8, second: []const u8) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .@"main::test_one" = .{ .providers = .{ .@"first.my" = first, .@"second.my" = second } },
        .@"main::test_two" = .{ .providers = .{ .@"second.my" = second, .@"first.my" = first } },
    }, .{});
}
fn c4ProviderCasesChanged(allocator: std.mem.Allocator, first: []const u8, changed: []const u8, second: []const u8) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .@"main::test_one" = .{ .providers = .{ .@"first.my" = first, .@"second.my" = second } },
        .@"main::test_two" = .{ .providers = .{ .@"second.my" = second, .@"first.my" = changed } },
    }, .{});
}

// ---------------------------------------------------------------------------
// PURE-SKIP: opt-in outcome replay for unchanged signature-pure tests
// ---------------------------------------------------------------------------

const pure_main =
    \\module main
    \\import helpers
    \\
    \\
    \\def main() -> int:
    \\    return 0
    \\
    \\
    \\public def test_ok() -> bool effects():
    \\    return helpers.value() == 1
    \\
    \\
    \\public def test_bad() -> bool effects():
    \\    return helpers.value() == 2
;
const pure_helpers =
    \\module helpers
    \\
    \\
    \\public def value() -> i64 effects():
    \\    return 1
;

const PureProject = struct { root: []const u8, entry: []const u8, cache: []const u8, trace: []const u8 };
fn pureProject(temp: *std.testing.TmpDir) !PureProject {
    try writeProjectFile(temp, "main.my", pure_main);
    try writeProjectFile(temp, "helpers.my", pure_helpers);
    const root_sentinel = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root_sentinel);
    const root = try testing.allocator.dupe(u8, root_sentinel);
    return .{
        .root = root,
        .entry = try std.fs.path.join(testing.allocator, &.{ root, "main.my" }),
        .cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" }),
        .trace = try std.fs.path.join(testing.allocator, &.{ root, "trace.log" }),
    };
}

/// One module of the scale chain: `f` adds one to the previous module's `f`
/// (its statement is line 6), `unused` is reached by no test, and `test_mK`
/// checks `f(1) == K + 2`.
fn scaleModule(allocator: std.mem.Allocator, module: usize, body: []const u8) ![]u8 {
    const opening = if (module == 0) try allocator.dupe(u8, "# the base of the chain") else try std.fmt.allocPrint(allocator, "import m{d}", .{module - 1});
    defer allocator.free(opening);
    const call = if (module == 0) try allocator.dupe(u8, "n") else try std.fmt.allocPrint(allocator, "m{d}.f(n)", .{module - 1});
    defer allocator.free(call);
    const default_body = try std.fmt.allocPrint(allocator, "return {s} + 1", .{call});
    defer allocator.free(default_body);
    return std.fmt.allocPrint(allocator,
        \\module m{d}
        \\{s}
        \\
        \\
        \\public def f(n: int) -> int:
        \\    {s}
        \\
        \\
        \\public def unused(n: int) -> int:
        \\    return n * 2
        \\
        \\
        \\public def test_m{d}() -> bool:
        \\    return f(1) == {d}
        \\
    , .{ module, opening, if (body.len != 0) body else default_body, module, module + 2 });
}
const scale_main =
    \\module main
    \\import m3
    \\
    \\
    \\def main() -> int:
    \\    return 0
    \\
;
/// Where one scale fixture keeps its entry, cache and child trace.
const ScalePaths = struct { entry: []const u8, cache: []const u8, trace: []const u8 };
/// A four-module chain whose test in module K depends on modules 0..K.
fn scaleProject(temp: *std.testing.TmpDir) !ScalePaths {
    try writeProjectFile(temp, "main.my", scale_main);
    for (0..4) |module| try scaleEdit(temp, module, "");
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    return .{
        .entry = try std.fs.path.join(testing.allocator, &.{ root, "main.my" }),
        .cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" }),
        .trace = try std.fs.path.join(testing.allocator, &.{ root, "trace.log" }),
    };
}
fn freeScalePaths(paths: ScalePaths) void {
    testing.allocator.free(paths.entry);
    testing.allocator.free(paths.cache);
    testing.allocator.free(paths.trace);
}
/// Rewrite module `module` of the chain with `body` as `f`'s statement.
fn scaleEdit(temp: *std.testing.TmpDir, module: usize, body: []const u8) !void {
    const text = try scaleModule(testing.allocator, module, body);
    defer testing.allocator.free(text);
    const name = try std.fmt.allocPrint(testing.allocator, "m{d}.my", .{module});
    defer testing.allocator.free(name);
    try writeProjectFile(temp, name, text);
}
/// Run the chain's tests once with a fresh trace; the caller frees the result.
fn scaleRun(paths: ScalePaths, extra: []const []const u8) !std.process.RunResult {
    c4TraceReset(paths.trace);
    return c4Invoke(paths.entry, null, paths.cache, paths.trace, extra);
}
/// Whether any stored checked-facts graph under `cache` mentions `needle`.
fn storedGraphMentions(cache: []const u8, needle: []const u8) !bool {
    const directory_path = try std.fs.path.join(testing.allocator, &.{ cache, "graphs" });
    defer testing.allocator.free(directory_path);
    var directory = try std.Io.Dir.cwd().openDir(testing.io, directory_path, .{ .iterate = true });
    defer directory.close(testing.io);
    var iterator = directory.iterate();
    while (try iterator.next(testing.io)) |entry| {
        if (entry.kind != .file) continue;
        const bytes = try directory.readFileAlloc(testing.io, entry.name, testing.allocator, .limited(64 << 20));
        defer testing.allocator.free(bytes);
        if (std.mem.indexOf(u8, bytes, needle) != null) return true;
    }
    return false;
}

// spec: NATIVE-TEST-SCALE-1
// spec: NATIVE-TEST-FACTS-2
// spec-case: NATIVE-TEST-STABLE-1
// spec-case: NATIVE-TEST-INTERFACES-1
// spec-case: NATIVE-TEST-RUNNER-1
// spec: NATIVE-TEST-SUMMARY-1
test "after a body edit in module k exactly the tests that depend on k are rebuilt and re-run, and an unchanged rerun only replays a verdict" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const paths = try scaleProject(&temp);
    defer freeScalePaths(paths);

    const cold = try scaleRun(paths, &.{});
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cold.term);
    try testing.expectEqual(@as(usize, 4), (try c4Counts(cold.stdout)).executed);
    // The facts cover the tests' closure only: no untested function.
    try testing.expect(try storedGraphMentions(paths.cache, "m0::f"));
    try testing.expect(!try storedGraphMentions(paths.cache, "m2::unused"));

    // Unchanged: one validity child, answered by the verdict the session recorded.
    const unchanged = try scaleRun(paths, &.{});
    defer testing.allocator.free(unchanged.stdout);
    defer testing.allocator.free(unchanged.stderr);
    const idle = try c4Counts(unchanged.stdout);
    try testing.expectEqual(@as(usize, 0), idle.executed);
    try testing.expectEqual(@as(usize, 4), idle.cached);
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(paths.trace, "check-project"));
    try testing.expectEqual(@as(usize, 0), try c4TraceCount(paths.trace, "list-interfaces"));
    try testing.expectEqual(@as(usize, 0), try c4TraceCount(paths.trace, "native-test-compile"));
    try testing.expectEqual(@as(usize, 0), try c4TraceCount(paths.trace, " build "));
    try testing.expectEqual(@as(usize, 0), try c4TraceCount(paths.trace, "native-test-runner"));
    try testing.expectEqualStrings("skipped", try c4WorkStatus(try c4CommandWorkLine(unchanged.stderr, "check-project"), "checked_bodies"));

    // A body edit in module 1 re-runs exactly the tests of modules 1, 2 and 3.
    try scaleEdit(&temp, 1, "return m0.f(n) + 2 - 1");
    const edited = try scaleRun(paths, &.{});
    defer testing.allocator.free(edited.stdout);
    defer testing.allocator.free(edited.stderr);
    const rerun = try c4Counts(edited.stdout);
    try testing.expectEqual(@as(usize, 3), rerun.executed);
    try testing.expectEqual(@as(usize, 1), rerun.cached);
    try testing.expectEqual(@as(usize, 0), rerun.failed);
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(paths.trace, "native-test-compile"));
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(paths.trace, " build "));
    // The harness the cold run compiled is reused.
    try testing.expectEqual(@as(usize, 0), try c4TraceCount(paths.trace, "native-test-runner"));
    // Lowered: the three tests and the four `f` they reach, nothing else.
    const session = try c4CommandWorkLine(edited.stderr, "native-test-compile");
    // The session's check is served by the summaries the cold run published:
    // every body is checked for the tree, and no retained checked tree is read.
    try testing.expectEqual(@as(usize, 0), try c4WorkCount(session, "checked_bodies", "reused"));
    try testing.expect(try c4WorkCount(session, "checked_bodies", "performed") > 0);
    try testing.expectEqual(@as(usize, 7), try c4WorkCount(session, "lowered_functions", "performed"));
    // Emitted fragments the cold run stored answer again, which a snapshot at
    // a fresh path on every run never allowed.
    try testing.expect(try c4WorkCount(session, "emitted_fragments", "reused") > 0);
    try testing.expect(try c4WorkCount(session, "emitted_fragments", "performed") < 7);

    // An edit that no test reaches builds nothing and runs nothing.
    const original = try scaleModule(testing.allocator, 2, "");
    defer testing.allocator.free(original);
    const untouched = try std.mem.replaceOwned(u8, testing.allocator, original, "return n * 2", "return n * 3");
    defer testing.allocator.free(untouched);
    try writeProjectFile(&temp, "m2.my", untouched);
    const unreached = try scaleRun(paths, &.{});
    defer testing.allocator.free(unreached.stdout);
    defer testing.allocator.free(unreached.stderr);
    const quiet = try c4Counts(unreached.stdout);
    try testing.expectEqual(@as(usize, 0), quiet.executed);
    try testing.expectEqual(@as(usize, 4), quiet.cached);
    try testing.expectEqual(@as(usize, 0), try c4TraceCount(paths.trace, " build "));
}

// spec-case: NATIVE-TEST-SCALE-1
// spec-case: NATIVE-TEST-PARALLEL-1
test "an edit that makes dependent tests trap reports the edited line, re-runs the failures, and a filter still selects one test" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const paths = try scaleProject(&temp);
    defer freeScalePaths(paths);
    const cold = try scaleRun(paths, &.{});
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cold.term);

    // `f` in module 1 now divides by zero on line 6 of m1.my.
    try scaleEdit(&temp, 1, "return m0.f(n) // 0");
    const broken = try scaleRun(paths, &.{});
    defer testing.allocator.free(broken.stdout);
    defer testing.allocator.free(broken.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, broken.term);
    const failing = try c4Counts(broken.stdout);
    try testing.expectEqual(@as(usize, 3), failing.failed);
    try testing.expectEqual(@as(usize, 1), failing.cached);
    try testing.expect(std.mem.indexOf(u8, broken.stdout, "R_DIVISION_BY_ZERO") != null);
    try testing.expect(std.mem.indexOf(u8, broken.stdout, "in m1::f at m1.my:6:") != null);
    // A failure is never a receipt: the unchanged rerun executes it again.
    const again = try scaleRun(paths, &.{});
    defer testing.allocator.free(again.stdout);
    defer testing.allocator.free(again.stderr);
    const repeated = try c4Counts(again.stdout);
    try testing.expectEqual(@as(usize, 3), repeated.executed);
    try testing.expectEqual(@as(usize, 3), repeated.failed);
    // A filter still narrows the selection to one case.
    const filtered = try scaleRun(paths, &.{ "--filter", "test_m2" });
    defer testing.allocator.free(filtered.stdout);
    defer testing.allocator.free(filtered.stderr);
    const one = try c4Counts(filtered.stdout);
    try testing.expectEqual(@as(usize, 1), one.executed + one.cached);
    try testing.expectEqual(@as(usize, 1), one.failed);
    try testing.expect(std.mem.indexOf(u8, filtered.stdout, "m3::test_m3") == null);
}

// spec: PURE-SKIP-1
test "PURE-SKIP-1 pure failure outcome replays without executing and is never masked" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const project = try pureProject(&temp);
    defer testing.allocator.free(project.root);
    defer testing.allocator.free(project.entry);
    defer testing.allocator.free(project.cache);
    defer testing.allocator.free(project.trace);

    c4TraceReset(project.trace);
    const cold = try c4Invoke(project.entry, null, project.cache, project.trace, &.{"--pure-skip"});
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, cold.term);
    const cold_counts = try c4Counts(cold.stdout);
    try testing.expectEqual(@as(usize, 1), cold_counts.passed);
    try testing.expectEqual(@as(usize, 1), cold_counts.failed);
    try testing.expectEqual(@as(usize, 2), cold_counts.executed);
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(project.trace, " build "));

    c4TraceReset(project.trace);
    const warm = try c4Invoke(project.entry, null, project.cache, project.trace, &.{"--pure-skip"});
    defer testing.allocator.free(warm.stdout);
    defer testing.allocator.free(warm.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, warm.term);
    const warm_counts = try c4Counts(warm.stdout);
    try testing.expectEqual(@as(usize, 1), warm_counts.failed);
    try testing.expectEqual(@as(usize, 1), warm_counts.cached);
    try testing.expectEqual(@as(usize, 0), warm_counts.executed);
    // The recorded outcome replays with no lowering, no native build and no run.
    try testing.expectEqual(@as(usize, 0), try c4TraceCount(project.trace, "native-test-compile"));
    try testing.expectEqual(@as(usize, 0), try c4TraceCount(project.trace, " build "));
    const warm_work = try c4WorkLine(warm.stderr);
    try testing.expectEqual(@as(usize, 0), try c4WorkCount(warm_work, "executed_tests", "performed"));
    try testing.expectEqual(@as(usize, 2), try c4WorkCount(warm_work, "executed_tests", "reused"));
    try testing.expect(std.mem.indexOf(u8, warm.stdout, "expected true, got false") != null);

    // Without the flag the default path never replays a recorded failure.
    c4TraceReset(project.trace);
    const default_run = try c4Invoke(project.entry, null, project.cache, project.trace, &.{});
    defer testing.allocator.free(default_run.stdout);
    defer testing.allocator.free(default_run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, default_run.term);
    try testing.expectEqual(@as(usize, 1), (try c4Counts(default_run.stdout)).failed);
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(project.trace, " build "));
}

// spec-case: PURE-SKIP-1
test "PURE-SKIP-1 a changed dependency invalidates the recorded pure outcome" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const project = try pureProject(&temp);
    defer testing.allocator.free(project.root);
    defer testing.allocator.free(project.entry);
    defer testing.allocator.free(project.cache);
    defer testing.allocator.free(project.trace);

    const cold = try c4Invoke(project.entry, null, project.cache, project.trace, &.{"--pure-skip"});
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, cold.term);
    try testing.expectEqual(@as(usize, 1), (try c4Counts(cold.stdout)).failed);

    const edited_helpers = try std.mem.replaceOwned(u8, testing.allocator, pure_helpers, "return 1", "return 2");
    defer testing.allocator.free(edited_helpers);
    try writeProjectFile(&temp, "helpers.my", edited_helpers);
    c4TraceReset(project.trace);
    const edited = try c4Invoke(project.entry, null, project.cache, project.trace, &.{"--pure-skip"});
    defer testing.allocator.free(edited.stdout);
    defer testing.allocator.free(edited.stderr);
    // The old failure is not replayed: both tests re-run against the new closure.
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, edited.term);
    const edited_counts = try c4Counts(edited.stdout);
    try testing.expectEqual(@as(usize, 1), edited_counts.passed);
    try testing.expectEqual(@as(usize, 1), edited_counts.failed);
    try testing.expectEqual(@as(usize, 2), edited_counts.executed);
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(project.trace, " build "));
}

// spec-case: PURE-SKIP-1
test "PURE-SKIP-1 no-cache and force disable pure outcome replay" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const project = try pureProject(&temp);
    defer testing.allocator.free(project.root);
    defer testing.allocator.free(project.entry);
    defer testing.allocator.free(project.cache);
    defer testing.allocator.free(project.trace);

    const cold = try c4Invoke(project.entry, null, project.cache, project.trace, &.{"--pure-skip"});
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, cold.term);

    c4TraceReset(project.trace);
    const fresh = try c4Invoke(project.entry, null, project.cache, project.trace, &.{ "--pure-skip", "--no-cache" });
    defer testing.allocator.free(fresh.stdout);
    defer testing.allocator.free(fresh.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, fresh.term);
    try testing.expectEqual(@as(usize, 2), (try c4Counts(fresh.stdout)).executed);
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(project.trace, " build "));

    c4TraceReset(project.trace);
    const forced = try c4Invoke(project.entry, null, project.cache, project.trace, &.{ "--pure-skip", "--force" });
    defer testing.allocator.free(forced.stdout);
    defer testing.allocator.free(forced.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, forced.term);
    try testing.expectEqual(@as(usize, 2), (try c4Counts(forced.stdout)).executed);
    try testing.expectEqual(@as(usize, 1), try c4TraceCount(project.trace, " build "));
}

// ---------------------------------------------------------------------------
// Guest performance benchmarks: candidate, approval and immutable enforcement
// ---------------------------------------------------------------------------

const bench_program =
    \\module main
    \\
    \\
    \\public def test_small() -> bool effects():
    \\    return bench_loop(3) == 3
    \\
    \\
    \\public def bench_loop(limit: int) -> int effects():
    \\    total: int = 0
    \\    index: int = 0
    \\    while index < limit:
    \\        total = total + index
    \\        index = index + 1
    \\    return total
    \\
    \\
    \\def main() -> int:
    \\    return 0
;
const bench_cases =
    \\{"main::bench_loop":{"sizes":{"small":{"arguments":{"limit":"10"},"expected":"45"}}}}
;
const bench_sampling = [_][]const u8{ "--bench-warmup", "0", "--bench-batches", "2", "--bench-batch-ms", "1" };
// Both policies decide by construction, never by how fast the machine is right
// now. Two 1 ms batches taken during a loaded gate can differ by far more than
// the default 25% spread budget, and the enforcement run can be many times
// slower than the run that made the baseline, so a policy that leaves noise or
// growth reachable fails at random under load (it did in the 2026-09-22 parity
// gates). The passing policy sets a spread budget and a meaningful-delta floor
// no measurement of this loop reaches; the ceiling is below any measurement.
// The growth, noise and confirmation arithmetic has its own deterministic unit
// tests in `src/native_bench.zig`; this test covers the CLI path end to end.
const bench_policy_pass =
    \\{"version":"bench-policy-v1","runner_profile":"default","default":{"allowed_growth_percent":1000,"minimum_meaningful_delta_ns":1000000000,"max_ns_per_op":1000000000},"required":["main::bench_loop[small]"],"noise":{"max_relative_spread_percent":1000000000,"near_limit_margin_percent":0}}
;
const bench_policy_ceiling =
    \\{"version":"bench-policy-v1","runner_profile":"default","default":{"allowed_growth_percent":1000,"minimum_meaningful_delta_ns":0,"max_ns_per_op":0.0000001},"required":["main::bench_loop[small]"],"noise":{"max_relative_spread_percent":1000000000,"near_limit_margin_percent":0}}
;

fn benchArgs(allocator: std.mem.Allocator, base: []const []const u8) ![]const []const u8 {
    var args: std.ArrayList([]const u8) = .empty;
    try args.appendSlice(allocator, base);
    try args.appendSlice(allocator, &bench_sampling);
    return args.items;
}

fn benchRun(allocator: std.mem.Allocator, entry: []const u8, cases: []const u8, cache: []const u8, extra: []const []const u8) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    try args.appendSlice(allocator, &.{ compiler_path, "test", entry, "--cases", cases, "--json" });
    try args.appendSlice(allocator, extra);
    return benchSpawn(allocator, &args, cache);
}

/// A directory run rejects `--cases`; benchmarks there are argument-free.
fn benchRunDirectory(allocator: std.mem.Allocator, entry: []const u8, cache: []const u8, extra: []const []const u8) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    try args.appendSlice(allocator, &.{ compiler_path, "test", entry, "--json" });
    try args.appendSlice(allocator, extra);
    // The directory run has no cases file, but sampling is a command flag, not a
    // case setting; without it a sequencing test pays the full default warmup.
    try args.appendSlice(allocator, &bench_sampling);
    return benchSpawn(allocator, &args, cache);
}

fn benchSpawn(allocator: std.mem.Allocator, args: *std.ArrayList([]const u8), cache: []const u8) !std.process.RunResult {
    const cache_argument = try std.fmt.allocPrint(allocator, "--cache-dir={s}", .{cache});
    try args.append(allocator, cache_argument);
    try args.appendSlice(allocator, &tools);
    return std.process.run(allocator, testing.io, .{ .argv = args.items });
}

/// Expect a benchmark run's exit status and print its stderr when it differs:
/// an unexpected 2 is a host failure (spawn, disk quota, memory on a loaded
/// machine), and only that text says which.
fn expectBenchExit(expected: u8, result: std.process.RunResult) !void {
    const wanted = std.process.Child.Term{ .exited = expected };
    if (std.meta.eql(wanted, result.term)) return;
    std.debug.print("benchmark run ended {any}, wanted exit {d}; stderr:\n{s}\n", .{ result.term, expected, result.stderr });
    return error.TestUnexpectedResult;
}

/// The verdict of the one comparison a baseline-checked benchmark report carries.
fn benchVerdict(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const report = (try std.json.parseFromSlice(std.json.Value, allocator, try readFile(allocator, path), .{})).value;
    const comparisons = report.object.get("comparisons").?.array.items;
    try testing.expectEqual(@as(usize, 1), comparisons.len);
    return comparisons[0].object.get("verdict").?.string;
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(testing.io, path, allocator, .limited(1 << 20));
}

fn benchPromote(allocator: std.mem.Allocator, candidate: []const u8, baseline: []const u8) !std.process.RunResult {
    return std.process.run(allocator, testing.io, .{ .argv = &.{
        compiler_path, "bench-promote", "--candidate", candidate,
        "--baseline",  baseline,        "--approver",  "maintainer",
        "--reason",    "reviewed",      "--revision",  "testrev",
    } });
}

// spec-case: NATIVE-BENCH-3
test "guest benchmarks write a candidate and enforce an approved baseline immutably" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "main.my", bench_program);
    try writeProjectFile(&temporary, "cases.json", bench_cases);
    try writeProjectFile(&temporary, "pass.json", bench_policy_pass);
    try writeProjectFile(&temporary, "ceiling.json", bench_policy_ceiling);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    defer a.free(root);
    const entry = try std.fs.path.join(a, &.{ root, "main.my" });
    const cases = try std.fs.path.join(a, &.{ root, "cases.json" });
    const candidate = try std.fs.path.join(a, &.{ root, "candidate.json" });
    const baseline = try std.fs.path.join(a, &.{ root, "baseline.json" });
    const pass_policy = try std.fs.path.join(a, &.{ root, "pass.json" });
    const ceiling_policy = try std.fs.path.join(a, &.{ root, "ceiling.json" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const candidate_run = try benchRun(a, entry, cases, cache, try benchArgs(a, &.{ "--bench", "*", "--mode", "Debug", "--bench-output", candidate }));
    try expectBenchExit(0, candidate_run);
    const report = (try std.json.parseFromSlice(std.json.Value, a, try readFile(a, candidate), .{})).value;
    try testing.expectEqualStrings("bench-report-v1", report.object.get("version").?.string);
    try testing.expect(report.object.get("complete").?.bool);
    try testing.expect(report.object.get("passed").?.bool);
    try testing.expectEqual(@as(usize, 1), report.object.get("measurements").?.array.items.len);
    try testing.expectEqualStrings("main::bench_loop[small]", report.object.get("measurements").?.array.items[0].object.get("id").?.string);
    const promoted = try benchPromote(a, candidate, baseline);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, promoted.term);
    const approved = try readFile(a, baseline);
    const approved_json = (try std.json.parseFromSlice(std.json.Value, a, approved, .{})).value;
    try testing.expectEqualStrings("bench-baseline-v1", approved_json.object.get("version").?.string);
    try testing.expectEqualStrings("testrev", approved_json.object.get("provenance").?.object.get("revision").?.string);
    const passing_report = try std.fs.path.join(a, &.{ root, "passing.json" });
    const failing_report = try std.fs.path.join(a, &.{ root, "failing.json" });
    const passing = try benchRun(a, entry, cases, cache, try benchArgs(a, &.{ "--bench", "*", "--mode", "Debug", "--bench-baseline", baseline, "--bench-policy", pass_policy, "--bench-output", passing_report }));
    try expectBenchExit(0, passing);
    try testing.expectEqualStrings("pass", try benchVerdict(a, passing_report));
    const failing = try benchRun(a, entry, cases, cache, try benchArgs(a, &.{ "--bench", "*", "--mode", "Debug", "--bench-baseline", baseline, "--bench-policy", ceiling_policy, "--bench-output", failing_report }));
    try expectBenchExit(1, failing);
    // It fails on the ceiling itself, not on noise or an incompatible baseline.
    try testing.expectEqualStrings("ceiling", try benchVerdict(a, failing_report));
    // A failed check leaves the approved baseline byte-for-byte unchanged.
    try testing.expectEqualStrings(approved, try readFile(a, baseline));
}

const bench_failure_program =
    \\module main
    \\
    \\
    \\public def bench_wrong() -> int effects():
    \\    return 2
    \\
    \\
    \\public def bench_trap(divisor: int) -> int effects():
    \\    return 10 // divisor
    \\
    \\
    \\def main() -> int:
    \\    return 0
;
const bench_failure_cases =
    \\{"main::bench_wrong":{"expected":"1"},"main::bench_trap":{"arguments":{"divisor":"0"},"expected":"1"}}
;

// spec-case: NATIVE-BENCH-2
test "a wrong benchmark result or trap fails the run and reports no measurement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "main.my", bench_failure_program);
    try writeProjectFile(&temporary, "cases.json", bench_failure_cases);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const entry = try std.fs.path.join(a, &.{ root, "main.my" });
    const cases = try std.fs.path.join(a, &.{ root, "cases.json" });
    const candidate = try std.fs.path.join(a, &.{ root, "candidate.json" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const run = try benchRun(a, entry, cases, cache, try benchArgs(a, &.{ "--bench", "*", "--mode", "Debug", "--bench-output", candidate }));
    try expectBenchExit(1, run);
    const report = (try std.json.parseFromSlice(std.json.Value, a, try readFile(a, candidate), .{})).value;
    try testing.expect(!report.object.get("complete").?.bool);
    try testing.expect(!report.object.get("passed").?.bool);
    try testing.expectEqual(@as(usize, 0), report.object.get("measurements").?.array.items.len);
    try testing.expectEqual(@as(usize, 2), report.object.get("failures").?.array.items.len);
    try testing.expectEqualStrings("failed", failureStatus(report, "main::bench_wrong"));
    try testing.expectEqualStrings("trap", failureStatus(report, "main::bench_trap"));
}

fn failureStatus(report: std.json.Value, id: []const u8) []const u8 {
    for (report.object.get("failures").?.array.items) |failure| {
        if (std.mem.eql(u8, failure.object.get("id").?.string, id)) return failure.object.get("status").?.string;
    }
    return "";
}

const bench_dir_program =
    \\module main
    \\
    \\
    \\public def bench_ok() -> bool effects():
    \\    return 1 + 1 == 2
    \\
    \\
    \\def main() -> int:
    \\    return 0
;

// spec-case: NATIVE-BENCH-6
test "a directory benchmark run measures sequentially and stays green without tests" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const suite = try std.fs.path.join(a, &.{ root, "suite" });
    try writeProjectFile(&temporary, "suite/one/main.my", bench_dir_program);
    try writeProjectFile(&temporary, "suite/two/main.my", bench_dir_program);
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const run = try benchRunDirectory(a, suite, cache, &.{ "--bench", "*", "--mode", "Debug" });
    try expectBenchExit(0, run);
}

// Guest test transport, failure text and entry discovery
// ------------------------------------------------------

/// Run `mylang test ENTRY` with this build's tools and an isolated cache.
fn guestTestRun(allocator: std.mem.Allocator, entry: []const u8, extra: []const []const u8, cache: []const u8) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    try args.appendSlice(allocator, &.{ compiler_path, "test", entry });
    try args.appendSlice(allocator, extra);
    const cache_argument = try std.fmt.allocPrint(allocator, "--cache-dir={s}", .{cache});
    try args.append(allocator, cache_argument);
    try args.appendSlice(allocator, &tools);
    return std.process.run(allocator, testing.io, .{ .argv = args.items });
}

const guest_output_program =
    \\module main
    \\
    \\
    \\public def test_chatty(out: Stream) -> bool effects(output, managed_allocation):
    \\    out.print("debug-marker")
    \\    return True
    \\
    \\
    \\public def test_failing(out: Stream) -> bool effects(output, managed_allocation):
    \\    out.print("debug-marker")
    \\    return False
    \\
    \\
    \\public def test_assert(out: Stream) -> bool effects(output, managed_allocation):
    \\    out.print("debug-marker")
    \\    assert 1 == 2, "one equals two"
    \\    return True
    \\
    \\
    \\def main() -> int:
    \\    return 0
;

// spec: NATIVE-TEST-10
// spec-case: NATIVE-TEST-7
// spec-case: NATIVE-TEST-8
test "guest print output stays off the test protocol and shows on failure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "main.my", guest_output_program);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const entry = try std.fs.path.join(a, &.{ root, "main.my" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const passing = try guestTestRun(a, entry, &.{ "--filter", "test_chatty" }, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, passing.term);
    try testing.expect(std.mem.indexOf(u8, passing.stdout, "1 passed") != null);
    try testing.expect(std.mem.indexOf(u8, passing.stderr, "InvalidNativeTestResponse") == null);
    const failing = try guestTestRun(a, entry, &.{ "--filter", "test_failing" }, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, failing.term);
    try testing.expect(std.mem.indexOf(u8, failing.stdout, "expected true, got false") != null);
    try testing.expect(std.mem.indexOf(u8, failing.stdout, "debug-marker") != null);
    try testing.expect(std.mem.indexOf(u8, failing.stderr, "InvalidNativeTestResponse") == null);
    const trapped = try guestTestRun(a, entry, &.{ "--filter", "test_assert" }, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, trapped.term);
    try testing.expect(std.mem.indexOf(u8, trapped.stdout, "R_ASSERT: one equals two") != null);
    try testing.expect(std.mem.indexOf(u8, trapped.stdout, "in main::test_assert at main.my:") != null);
    try testing.expect(std.mem.indexOf(u8, trapped.stdout, "debug-marker") != null);
}

const guest_typed_program =
    \\module main
    \\
    \\
    \\public def test_value() -> int effects():
    \\    return 3
    \\
    \\
    \\def main() -> int:
    \\    return 0
;

// spec-case: NATIVE-TEST-8
test "a typed expectation failure names both actual and expected values" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "main.my", guest_typed_program);
    try writeProjectFile(&temporary, "cases.json", "{\"main::test_value\":{\"expected\":9}}");
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const entry = try std.fs.path.join(a, &.{ root, "main.my" });
    const cases = try std.fs.path.join(a, &.{ root, "cases.json" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const run = try guestTestRun(a, entry, &.{ "--cases", cases }, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, run.term);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "expected 9, got 3") != null);
}

const library_entry_program =
    \\module inventory
    \\
    \\
    \\public def test_count() -> bool effects():
    \\    return 3 == 3
;

const bare_test_entry_program =
    \\
    \\
    \\public def test_bare() -> bool effects():
    \\    return True
;

// spec-case: NATIVE-TEST-9
test "library modules and bare *_test.my files are valid guest test entries" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "inventory.my", library_entry_program);
    try writeProjectFile(&temporary, "bare_test.my", bare_test_entry_program);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const library = try std.fs.path.join(a, &.{ root, "inventory.my" });
    const bare = try std.fs.path.join(a, &.{ root, "bare_test.my" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const library_run = try guestTestRun(a, library, &.{ "--filter", "test_count" }, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, library_run.term);
    try testing.expect(std.mem.indexOf(u8, library_run.stdout, "1 passed") != null);
    const bare_run = try guestTestRun(a, bare, &.{ "--filter", "test_bare" }, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, bare_run.term);
    try testing.expect(std.mem.indexOf(u8, bare_run.stdout, "1 passed") != null);
}

const directory_project_main =
    \\module main
    \\import helper
    \\
    \\
    \\public def test_main() -> bool effects():
    \\    return helper.value() == 7
    \\
    \\
    \\def main() -> int:
    \\    return 0
;

const directory_project_helper =
    \\module helper
    \\
    \\
    \\public def value() -> int effects():
    \\    return 7
;

const directory_project_test =
    \\module library_test
    \\
    \\
    \\public def test_alone() -> bool effects():
    \\    return True
;

// spec-case: NATIVE-TEST-4
test "a directory run discovers project roots instead of every module" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "suite/main.my", directory_project_main);
    try writeProjectFile(&temporary, "suite/helper.my", directory_project_helper);
    try writeProjectFile(&temporary, "suite/library_test.my", directory_project_test);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const suite = try std.fs.path.join(a, &.{ root, "suite" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const run = try guestTestRun(a, suite, &.{"--json"}, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run.term);
    const report = (try std.json.parseFromSlice(std.json.Value, a, run.stdout, .{})).value;
    try testing.expectEqual(@as(i64, 2), report.object.get("programs").?.integer);
    try testing.expectEqual(@as(i64, 2), report.object.get("passed").?.integer);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "main::test_main") != null);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "library_test::test_alone") != null);
    try testing.expect(std.mem.indexOf(u8, run.stderr, "E_MODULE_NAME") == null);
}

const directory_orphan_inner =
    \\module inner
    \\
    \\
    \\public def base() -> int effects():
    \\    return 40
    \\
    \\
    \\public def test_inner() -> bool effects():
    \\    return base() == 40
;

const directory_orphan_outer =
    \\module outer
    \\import inner
    \\
    \\
    \\public def test_outer() -> bool effects():
    \\    return inner.base() + 2 == 42
;

const directory_helper_with_test =
    \\module helper
    \\
    \\
    \\public def value() -> int effects():
    \\    return 7
    \\
    \\
    \\public def test_helper() -> bool effects():
    \\    return value() == 7
;

// spec: NATIVE-TEST-14
test "a directory run runs a main-less test library no root imports, and every test once" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "suite/main.my", directory_project_main);
    try writeProjectFile(&temporary, "suite/helper.my", directory_helper_with_test);
    try writeProjectFile(&temporary, "suite/inner.my", directory_orphan_inner);
    try writeProjectFile(&temporary, "suite/outer.my", directory_orphan_outer);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const suite = try std.fs.path.join(a, &.{ root, "suite" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const run = try guestTestRun(a, suite, &.{"--json"}, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run.term);
    const report = (try std.json.parseFromSlice(std.json.Value, a, run.stdout, .{})).value;
    // `main.my` carries `helper`; `outer.my` carries `inner`, so `inner.my` is
    // not a program of its own and none of the four tests runs twice.
    try testing.expectEqual(@as(i64, 2), report.object.get("programs").?.integer);
    try testing.expectEqual(@as(i64, 4), report.object.get("passed").?.integer);
    try testing.expectEqual(@as(i64, 0), report.object.get("unloaded").?.integer);
    for ([_][]const u8{ "main::test_main", "helper::test_helper", "inner::test_inner", "outer::test_outer" }) |name| {
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, run.stdout, name));
    }
}

// spec-case: NATIVE-TEST-15
test "a single-entry test report lists the project sources its check loaded" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "suite/main.my", directory_project_main);
    try writeProjectFile(&temporary, "suite/helper.my", directory_project_helper);
    try writeProjectFile(&temporary, "suite/unrelated.my", directory_orphan_inner);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const entry = try std.fs.path.join(a, &.{ root, "suite", "main.my" });
    const run = try guestTestRun(a, entry, &.{"--json"}, try std.fs.path.join(a, &.{ root, "cache" }));
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run.term);
    const report = (try std.json.parseFromSlice(std.json.Value, a, run.stdout, .{})).value;
    const modules = report.object.get("modules").?.array.items;
    try testing.expectEqual(@as(usize, 2), modules.len);
    try testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, "suite", "helper.my" }), modules[0].string);
    try testing.expectEqualStrings(entry, modules[1].string);
}

// spec-case: LINT-5
test "CLI list-interfaces prints a tests column from the shared reachability index" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\module input
        \\
        \\
        \\public def parse(value: int) -> int:
        \\    return value
        \\
        \\
        \\def test_parse() -> bool effects():
        \\    return parse(1) == 1
        \\
        \\
        \\def main() -> int:
        \\    return 0
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "list-interfaces", path } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "export function parse") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "tests(1)") != null);
}

// `mylang invoke` calls one export of a checked project through the native
// runtime. These cases follow the `CLI context` fixtures: a small library
// project in a temporary directory, one JSON answer on stdout, and assertions
// about the shape of that answer rather than about a byte-for-byte document,
// because the envelope is still moving. Every case passes this build's QBE and
// Zig and a cache directory under its own fixture, so no case reads the
// repository cache, depends on PATH, or shares artifacts with another shard.

/// The invoked project: one small module whose exports each answer one wire
/// question, with a `main` so it is also an ordinary program.
const invoke_app =
    \\module app
    \\
    \\
    \\public class Point:
    \\    x: i64
    \\    y: i64
    \\
    \\
    \\public def add(a: i64, b: i64) -> i64:
    \\    return a + b
    \\
    \\
    \\public def identity(x: i64) -> i64:
    \\    return x
    \\
    \\
    \\public def shift(p: Point, dx: i64) -> Point:
    \\    return Point(x=p.x + dx, y=p.y)
    \\
    \\
    \\public def origin(x: i64) -> Point:
    \\    return Point(x=x, y=0)
    \\
    \\
    \\public def classify(x: i64) -> Result[i64, i64]:
    \\    if x < 0:
    \\        return Err(x)
    \\    return Ok(x)
    \\
    \\
    \\public def shout(out: Stream, x: i64) -> i64 effects(output):
    \\    out.print(x)
    \\    return x
    \\
    \\
    \\def hidden(x: i64) -> i64:
    \\    return x
    \\
    \\
    \\public def look(fs: Filesystem, x: i64) -> i64 effects(filesystem):
    \\    return x
    \\
    \\
    \\public def text_len(text: str) -> i64:
    \\    return len(text)
    \\
    \\
    \\public def total(values: list[i64]) -> i64:
    \\    return len(values)
    \\
    \\
    \\public def pick[T](x: T) -> T:
    \\    return x
    \\
    \\
    \\def main() -> int:
    \\    return 0
;

/// The second fixture declares no `main` at all: the command has to supply a
/// synthetic entry instead of asking the caller to edit the library first.
const invoke_library =
    \\module library
    \\
    \\
    \\public def double(x: i64) -> i64:
    \\    return x + x
;

/// The text fixture: a copied managed text crosses the invocation boundary in
/// the return direction, so a `str` result is eligible and comes back as the
/// exact string while the same type in an argument position stays refused for
/// want of a root. The non-ASCII literals are written as language escapes, so
/// this Zig file stays ASCII and the guest decodes the scalars itself.
const invoke_text =
    \\module app
    \\
    \\
    \\public def letter(n: i64) -> str:
    \\    return chr(n)
    \\
    \\
    \\public def greeting() -> str:
    \\    return "h\u00e9llo \u4e16\u754c \U0001F600"
    \\
    \\
    \\public def frozen() -> str:
    \\    return "literal"
    \\
    \\
    \\public def shout(n: i64) -> str:
    \\    return chr(n) + "!"
    \\
    \\
    \\public def repeated(n: i64) -> str:
    \\    text = ""
    \\    i = 0
    \\    while i < n:
    \\        text = text + "z"
    \\        i = i + 1
    \\    return text
    \\
    \\
    \\public def count(text: str) -> i64:
    \\    return len(text)
;

/// Write `source` as `name` in `temporary` and return its absolute path.
fn writeInvokeSource(a: std.mem.Allocator, temporary: *testing.TmpDir, name: []const u8, source: []const u8) ![]u8 {
    try temporary.dir.writeFile(testing.io, .{ .sub_path = name, .data = source });
    return temporary.dir.realPathFileAlloc(testing.io, name, a);
}

/// Write one request document and return its absolute path.
fn writeInvokeRequest(a: std.mem.Allocator, temporary: *testing.TmpDir, name: []const u8, body: []const u8) ![]u8 {
    return writeInvokeSource(a, temporary, name, body);
}

/// The `--input=FILE` option naming `path`.
fn invokeInputOption(a: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fmt.allocPrint(a, "--input={s}", .{path});
}

/// The `--cache-dir=DIR` option every fixture passes, under the fixture root so
/// concurrent shards and the repository cache stay independent.
fn invokeCacheOption(a: std.mem.Allocator, temporary: *testing.TmpDir) ![]u8 {
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    return std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{root});
}

/// Run `mylang invoke` for `entry` with `options`, the fixture's private cache
/// and this build's QBE and Zig.
fn runInvoke(entry: []const u8, options: []const []const u8, cache_option: []const u8) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compiler_path, "invoke", entry });
    try args.appendSlice(testing.allocator, options);
    try args.append(testing.allocator, cache_option);
    try args.appendSlice(testing.allocator, &tools);
    return std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
}

/// Index of the `}` that closes the object starting at `body[0]`, so a caller
/// can prove stdout holds exactly one object and nothing else around it.
fn singleObjectEnd(body: []const u8) ?usize {
    var depth: usize = 0;
    var quoted = false;
    var escaped = false;
    for (body, 0..) |byte, index| {
        if (quoted) {
            if (escaped) {
                escaped = false;
            } else if (byte == '\\') {
                escaped = true;
            } else if (byte == '"') {
                quoted = false;
            }
            continue;
        }
        if (byte == '"') {
            quoted = true;
        } else if (byte == '{') {
            depth += 1;
        } else if (byte == '}') {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) return index;
        }
    }
    return null;
}

/// Parse the single JSON object a `mylang invoke` answer prints, asserting that
/// stdout holds nothing else around it.
fn parseInvokeAnswer(printed: []const u8) !std.json.Parsed(std.json.Value) {
    const body = std.mem.trim(u8, printed, " \t\r\n");
    try testing.expect(body.len > 1);
    const end = singleObjectEnd(body) orelse return error.InvokeStdoutNotOneObject;
    try testing.expectEqual(body.len - 1, end);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    errdefer parsed.deinit();
    try testing.expect(parsed.value == .object);
    return parsed;
}

/// A required top-level string field of an invoke answer.
fn invokeString(answer: std.json.Value, key: []const u8) ![]const u8 {
    const value = answer.object.get(key) orelse return error.MissingInvokeField;
    if (value != .string) return error.InvokeFieldNotString;
    return value.string;
}

/// The qualified name an answer is about, accepted either at the top level or
/// inside the `target` record.
fn invokeFunction(answer: std.json.Value) ![]const u8 {
    const value = answer.object.get("function") orelse return error.MissingInvokeFunction;
    if (value != .string) return error.MissingInvokeFunction;
    return value.string;
}

/// One object an answer carries at the top level. The envelope is pinned to the
/// published shape, so a second tolerated spelling would let a rename through.
fn invokeContextObject(answer: std.json.Value, key: []const u8) !std.json.Value {
    const value = answer.object.get(key) orelse return error.MissingInvokeContext;
    if (value != .object) return error.MissingInvokeContext;
    return value;
}

/// Whether an object carries at least one non-empty string value.
fn objectHasText(value: std.json.Value) bool {
    var entries = value.object.iterator();
    while (entries.next()) |entry| {
        const item = entry.value_ptr.*;
        if (item != .string) continue;
        if (item.string.len != 0) return true;
    }
    return false;
}

/// Every answer carries the version, a status, the function it is about, the
/// identities it was produced from and the limits it was judged against.
fn expectInvokeEnvelope(answer: std.json.Value, qualified: []const u8) !void {
    try testing.expectEqualStrings("native-invocation-v1", try invokeString(answer, "version"));
    try testing.expect((try invokeString(answer, "status")).len > 0);
    try testing.expectEqualStrings(qualified, try invokeFunction(answer));
    const limits = try invokeContextObject(answer, "limits");
    try testing.expect(limits.object.count() > 0);
    const identities = try invokeContextObject(answer, "identities");
    try testing.expect(objectHasText(identities));
}

/// One effective limit the answer reports. Bounds travel as JSON numbers; only
/// a guest value uses the decimal-string form, which is why this does not go
/// through `valueInteger`.
fn limitInteger(answer: std.json.Value, key: []const u8) !i64 {
    const limits = try invokeContextObject(answer, "limits");
    const value = limits.object.get(key) orelse return error.MissingInvokeLimit;
    if (value != .integer) return error.MissingInvokeLimit;
    return value.integer;
}

/// The integer a response value carries. The published wire form is a canonical
/// decimal string, chosen so a 64-bit value survives a client whose numbers
/// cannot represent it, so a JSON number here would be a contract regression
/// rather than an alternative spelling.
fn valueInteger(value: std.json.Value) !i64 {
    if (value != .string) return error.InvokeValueNotInteger;
    return std.fmt.parseInt(i64, value.string, 10);
}

/// The text a response value carries. A returned `str` is published as one
/// wire node per Unicode scalar and rebuilt as a JSON string, so an integer
/// node or a bare scalar array at the value position is a contract regression
/// rather than another spelling of the same answer.
fn valueText(value: std.json.Value) ![]const u8 {
    if (value != .string) return error.InvokeValueNotText;
    return value.string;
}

/// The description payload of a `--describe` answer.
fn invokeDescribe(answer: std.json.Value) !std.json.Value {
    if (answer.object.get("describe")) |value| {
        if (value == .object) return value;
    }
    if (answer.object.get("description")) |value| {
        if (value == .object) return value;
    }
    return error.MissingInvokeDescribe;
}

/// The argument positions a description publishes.
fn describeParameters(payload: std.json.Value) ![]std.json.Value {
    inline for (.{ "parameters", "arguments" }) |key| {
        if (payload.object.get(key)) |value| {
            if (value == .array) return value.array.items;
        }
    }
    return error.MissingInvokeParameters;
}

/// The description must publish `name` as a position of the checked type.
fn expectDescribeParameter(parameters: []std.json.Value, name: []const u8, type_name: []const u8) !void {
    for (parameters) |parameter| {
        if (parameter == .string) {
            if (std.mem.eql(u8, parameter.string, name)) return;
            continue;
        }
        if (parameter != .object) continue;
        const field = parameter.object.get("name") orelse continue;
        if (field != .string) continue;
        if (!std.mem.eql(u8, field.string, name)) continue;
        if (parameter.object.get("type")) |declared| {
            if (declared == .string) try testing.expectEqualStrings(type_name, declared.string);
        }
        return;
    }
    return error.MissingInvokeParameter;
}

/// The checked result position a description publishes.
fn describeResult(payload: std.json.Value) ![]const u8 {
    const value = payload.object.get("result") orelse return error.MissingInvokeResult;
    if (value == .string) return value.string;
    if (value == .object) {
        if (value.object.get("type")) |declared| {
            if (declared == .string) return declared.string;
        }
    }
    return error.InvokeResultNotString;
}

/// Whether a description says the target can be called as written.
fn describeEligible(payload: std.json.Value) !bool {
    if (payload.object.get("eligible")) |value| {
        if (value == .bool) return value.bool;
    }
    inline for (.{ "invocation", "wire", "eligibility" }) |key| {
        if (payload.object.get(key)) |scope| {
            if (scope == .object) {
                if (scope.object.get("eligible")) |value| {
                    if (value == .bool) return value.bool;
                }
            }
        }
    }
    return error.MissingInvokeEligibility;
}

/// The sentence explaining why a description is not eligible.
fn describeReason(payload: std.json.Value) ![]const u8 {
    if (payload.object.get("reason")) |value| {
        if (value == .string) return value.string;
    }
    inline for (.{ "invocation", "wire", "eligibility" }) |key| {
        if (payload.object.get(key)) |scope| {
            if (scope == .object) {
                if (scope.object.get("reason")) |value| {
                    if (value == .string) return value.string;
                }
            }
        }
    }
    return error.MissingInvokeReason;
}

/// The executed call an answer reports, or null when no call ran.
fn invokeOutcome(answer: std.json.Value) ?std.json.Value {
    inline for (.{ "outcome", "invocation", "call" }) |key| {
        if (answer.object.get(key)) |value| {
            if (value != .null) return value;
        }
    }
    return null;
}

/// The typed value one executed call reports.
fn outcomeValue(outcome: std.json.Value) !std.json.Value {
    if (outcome != .object) return outcome;
    inline for (.{ "value", "result", "actual" }) |key| {
        if (outcome.object.get(key)) |value| return value;
    }
    return error.MissingInvokeOutcomeValue;
}

/// The guest output one executed call captured, when the envelope reports it.
fn outcomeOutput(outcome: std.json.Value) ?[]const u8 {
    if (outcome != .object) return null;
    inline for (.{ "output", "captured_output", "guest_output" }) |key| {
        if (outcome.object.get(key)) |value| {
            if (value == .string) return value.string;
        }
    }
    return null;
}

/// Run a request that must complete: exit 0 and one parseable answer object.
fn expectInvokeCompleted(entry: []const u8, options: []const []const u8, cache_option: []const u8) !std.json.Parsed(std.json.Value) {
    const outcome = try runInvoke(entry, options, cache_option);
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    return parseInvokeAnswer(outcome.stdout);
}

/// A refused request must not print a success object: stdout is either empty or
/// one JSON object whose status is none of the completion spellings.
fn expectNoInvokeSuccess(printed: []const u8) !void {
    const body = std.mem.trim(u8, printed, " \t\r\n");
    if (body.len == 0) return;
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    defer parsed.deinit();
    try testing.expect(parsed.value == .object);
    const status = parsed.value.object.get("status") orelse return;
    if (status != .string) return;
    inline for (.{ "ok", "described", "completed", "value" }) |success| {
        try testing.expect(!std.mem.eql(u8, status.string, success));
    }
}

/// Run an `invoke` request that must be refused with `expected_status` and must
/// not report a completed call.
fn expectInvokeRefused(entry: []const u8, options: []const []const u8, cache_option: []const u8, expected_status: u8) !void {
    const outcome = try runInvoke(entry, options, cache_option);
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = expected_status }, outcome.term);
    try expectNoInvokeSuccess(outcome.stdout);
}

/// Run a usage mistake: exit 2, the usage text on stderr, no success object.
fn expectInvokeUsage(entry: []const u8, options: []const []const u8, cache_option: []const u8) !void {
    const outcome = try runInvoke(entry, options, cache_option);
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "usage") != null);
    try expectNoInvokeSuccess(outcome.stdout);
}

/// An authority refusal must name the capability in either spelling.
fn expectMentionsFilesystem(bytes: []const u8) !void {
    if (std.mem.indexOf(u8, bytes, "Filesystem") != null) return;
    try testing.expect(std.mem.indexOf(u8, bytes, "filesystem") != null);
}

/// A refusal about a call position must name the native call ABI, so a caller
/// can tell "not a copied value" from "a copied value the call ABI cannot carry".
fn expectMentionsCallAbi(bytes: []const u8) !void {
    try testing.expect(std.mem.indexOf(u8, bytes, "ABI") != null);
}

/// A text-argument refusal must name the root the argument direction would
/// need, so a caller can tell it from "this type cannot cross the boundary at
/// all".
fn expectMentionsRoot(bytes: []const u8) !void {
    try testing.expect(std.mem.indexOf(u8, bytes, "root") != null);
}

/// The generic wording a type with no copied-value representation gets must
/// not be used for a text argument: the same type does cross the boundary in
/// the return direction, so the refusal has to be the specific one.
fn expectNoGenericTextRefusal(bytes: []const u8) !void {
    try testing.expect(std.mem.indexOf(u8, bytes, "no copied-value representation") == null);
}

/// The worked invocation example, invoked in place from the repository root so
/// the committed fixture is exactly the file the example publishes.
const invoke_report_example = "examples/invoke-report/report.my";

/// A list result must be one JSON array of element texts, exactly `expected`
/// in order and with no element added or dropped. A returned `list[T]` is
/// published as one node per element in the declared element form, so an array
/// collapsed into a single string at the value position is a contract
/// regression rather than another spelling of the same answer.
fn expectValueStrings(value: std.json.Value, expected: []const []const u8) !void {
    if (value != .array) return error.InvokeValueNotList;
    try testing.expectEqual(expected.len, value.array.items.len);
    for (value.array.items, 0..) |item, index| {
        try testing.expectEqualStrings(expected[index], try valueText(item));
    }
}

/// A call that printed nothing must publish no captured output text: the
/// protocol channel carries the answer alone, so absent and empty are both a
/// zero-length capture and neither is text that leaked onto the channel.
fn expectNoCapturedOutput(outcome: std.json.Value) !void {
    const captured: []const u8 = outcomeOutput(outcome) orelse "";
    try testing.expectEqual(@as(usize, 0), captured.len);
}

/// Run `argv` and require the removal refusal `mylang COMMAND` gives for
/// `--unchecked`: usage exit status 2, the reason on stderr, nothing built.
fn expectUncheckedRemoved(argv: []const []const u8, command: []const u8) !void {
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, result.term);
    const expected = try std.fmt.allocPrint(testing.allocator, "mylang {s}: --unchecked was removed: every build keeps overflow, cast and bounds checks so optimization never changes a program's result\n", .{command});
    defer testing.allocator.free(expected);
    try testing.expectEqualStrings(expected, result.stderr);
    try testing.expectEqualStrings("", result.stdout);
}

// spec-case: RELEASE-CHECKED-1
test "every building and running command refuses --unchecked as removed" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "refused.my", .data =
        \\def main() -> i64:
        \\    return 0
    });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "refused.my", testing.allocator);
    defer testing.allocator.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const output = try std.fs.path.join(testing.allocator, &.{ directory, "refused-bin" });
    defer testing.allocator.free(output);
    try expectUncheckedRemoved(&.{ compiler_path, "build", entry, "-o", output, "--unchecked" }, "build");
    try expectUncheckedRemoved(&.{ compiler_path, "build", entry, "--run", "--release", "--unchecked" }, "build");
    try expectUncheckedRemoved(&.{ compiler_path, "build", entry, "-o", output, "--unchecked", "--mode=Debug" }, "build");
    try expectUncheckedRemoved(&.{ compiler_path, "run", entry, "--unchecked" }, "run");
    try expectUncheckedRemoved(&.{ compiler_path, "run-project", entry, "--unchecked" }, "run-project");
    try expectUncheckedRemoved(&.{ compiler_path, "test", entry, "--unchecked" }, "test");
    // Nothing was built.
    try testing.expectError(error.FileNotFound, temporary.dir.access(testing.io, "refused-bin", .{}));
}

/// One version of the two-module project the incremental-build fixture edits.
const IncrementalVersion = struct { main: []const u8, helper: []const u8 };

const incremental_main =
    \\module main
    \\import helper
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    p = helper.Pair(left=3, right=4)
    \\    xs = helper.scale([1, 2, 3], helper.total(p))
    \\    out.print(helper.first(xs))
    \\    out.print(str(p.left) + ":" + str(len(xs)))
    \\    return 0
    \\
;

const incremental_helper =
    \\module helper
    \\
    \\
    \\public record Pair:
    \\    left: int
    \\    right: int
    \\
    \\
    \\public def total(p: Pair) -> int:
    \\    return p.left + p.right
    \\
    \\
    \\public def scale(xs: list[int], k: int) -> list[int]:
    \\    out: list[int] = []
    \\    for x in xs:
    \\        out.append(x * k)
    \\    return out
    \\
    \\
    \\public def first(xs: list[int]) -> int:
    \\    return xs[0]
    \\
;

fn incrementalEdit(comptime text: []const u8, comptime needle: []const u8, comptime replacement: []const u8) []const u8 {
    const at = std.mem.indexOf(u8, text, needle) orelse @compileError("missing edit site");
    return text[0..at] ++ replacement ++ text[at + needle.len ..];
}

const body_edited_helper = incrementalEdit(incremental_helper, "    return p.left + p.right\n", "    return p.left + p.right + 10\n");
const signature_edited_helper = incrementalEdit(body_edited_helper, "public def first(xs: list[int]) -> int:\n    return xs[0]\n", "public def first(xs: list[int], at: int) -> int:\n    return xs[at]\n");

/// The project after a body edit, then a signature edit, then an interface
/// edit that puts a new function ahead of every other declaration.
const incremental_versions = [_]IncrementalVersion{
    .{ .main = incremental_main, .helper = body_edited_helper },
    .{ .main = incrementalEdit(incremental_main, "helper.first(xs)", "helper.first(xs, 2)"), .helper = signature_edited_helper },
    .{
        .main = incrementalEdit(incremental_main, "helper.first(xs)", "helper.first(xs, 2) + helper.zero()"),
        .helper = incrementalEdit(signature_edited_helper, "module helper\n", "module helper\n\n\npublic def zero() -> int:\n    return 0\n"),
    },
};

/// One `--report` build's guest objects as sorted `symbol key` lines, plus how
/// many it compiled. Object keys name the unit text's digest under the build
/// environment, so equal lines mean byte-identical guest objects.
const BuiltObjects = struct { lines: []u8, compiled: i64 };

fn buildObjects(allocator: std.mem.Allocator, entry: []const u8, output: []const u8, cache: []const u8) !BuiltObjects {
    const result = try std.process.run(allocator, testing.io, .{ .argv = &.{ compiler_path, "build", entry, "--project", "-o", output, "--cache-dir", cache, "--mode", "Debug", "--report", tools[0], tools[1] } });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    const report = try std.json.parseFromSliceLeaky(std.json.Value, allocator, result.stdout, .{});
    var lines: std.ArrayList([]const u8) = .empty;
    for (report.object.get("functions").?.array.items) |function| {
        try lines.append(allocator, try std.fmt.allocPrint(allocator, "{s} {s}\n", .{ function.object.get("symbol").?.string, function.object.get("key").?.string }));
    }
    std.mem.sort([]const u8, lines.items, {}, incrementalLess);
    return .{ .lines = try std.mem.concat(allocator, u8, lines.items), .compiled = report.object.get("compiled_functions").?.integer };
}

fn incrementalLess(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn writeIncrementalVersion(directory: std.Io.Dir, version: IncrementalVersion) !void {
    try directory.writeFile(testing.io, .{ .sub_path = "main.my", .data = version.main });
    try directory.writeFile(testing.io, .{ .sub_path = "helper.my", .data = version.helper });
}

fn programOutput(allocator: std.mem.Allocator, program: []const u8) ![]const u8 {
    const result = try std.process.run(allocator, testing.io, .{ .argv = &.{program} });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    return result.stdout;
}

/// Build `version` incrementally over the previous version's caches and from
/// clean caches, and require the same guest objects and the same behaviour.
fn expectIncrementalEqualsClean(allocator: std.mem.Allocator, directory: std.Io.Dir, root: []const u8, version: IncrementalVersion, round: usize) !void {
    try writeIncrementalVersion(directory, version);
    const entry = try std.fs.path.join(allocator, &.{ root, "main.my" });
    const incremental_program = try std.fs.path.join(allocator, &.{ root, "incremental" });
    const clean_program = try std.fs.path.join(allocator, &.{ root, "clean" });
    const incremental = try buildObjects(allocator, entry, incremental_program, try std.fs.path.join(allocator, &.{ root, "cache" }));
    const clean = try buildObjects(allocator, entry, clean_program, try std.fmt.allocPrint(allocator, "{s}/clean-{d}", .{ root, round }));
    try testing.expectEqualStrings(clean.lines, incremental.lines);
    // A clean build compiles every function. An edit that stays inside one
    // module rebuilds only that module's batch (round 0); the signature and
    // interface edits change both modules, so they may rebuild everything.
    try testing.expect(incremental.compiled <= clean.compiled);
    try testing.expect(round != 0 or incremental.compiled < clean.compiled);
    try testing.expectEqualStrings(try programOutput(allocator, clean_program), try programOutput(allocator, incremental_program));
}

// spec-case: QBE-FRAGMENT-REUSE-1
test "an incremental build after body, signature and interface edits builds the program a clean build builds" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const program = try std.fs.path.join(a, &.{ root, "incremental" });
    try writeIncrementalVersion(temporary.dir, .{ .main = incremental_main, .helper = incremental_helper });
    const first = try buildObjects(a, try std.fs.path.join(a, &.{ root, "main.my" }), program, try std.fs.path.join(a, &.{ root, "cache" }));
    try testing.expect(first.compiled > 0);
    try testing.expectEqualStrings("7\n3:3\n", try programOutput(a, program));
    try expectIncrementalEqualsClean(a, temporary.dir, root, incremental_versions[0], 0);
    try testing.expectEqualStrings("17\n3:3\n", try programOutput(a, program));
    try expectIncrementalEqualsClean(a, temporary.dir, root, incremental_versions[1], 1);
    try testing.expectEqualStrings("51\n3:3\n", try programOutput(a, program));
    try expectIncrementalEqualsClean(a, temporary.dir, root, incremental_versions[2], 2);
    try testing.expectEqualStrings("51\n3:3\n", try programOutput(a, program));
}

/// One `--report` build of `entry` into `output` over `cache`: whether it says
/// the output changed.
fn reportedOutputChange(allocator: std.mem.Allocator, entry: []const u8, output: []const u8, cache: []const u8) !bool {
    const result = try std.process.run(allocator, testing.io, .{ .argv = &.{ compiler_path, "build", entry, "--project", "-o", output, "--cache-dir", cache, "--mode", "Debug", "--report", tools[0], tools[1] } });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    const report = try std.json.parseFromSliceLeaky(std.json.Value, allocator, result.stdout, .{});
    return report.object.get("output_changed").?.bool;
}

// spec: BUILD-PUBLISH-1
test "a relink of reused objects keeps an identical executable, and a link over compiled ones replaces it unread" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    try writeIncrementalVersion(temporary.dir, .{ .main = incremental_main, .helper = incremental_helper });
    const entry = try std.fs.path.join(a, &.{ root, "main.my" });
    const output = try std.fs.path.join(a, &.{ root, "program" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    try testing.expect(try reportedOutputChange(a, entry, output, cache));
    const built = try std.Io.Dir.cwd().statFile(testing.io, output, .{});
    // Without the sidecar the link cannot be skipped, but every object is
    // reused, so the identical result keeps the published file.
    try temporary.dir.deleteFile(testing.io, "program.qbe-manifest.json");
    try testing.expect(!try reportedOutputChange(a, entry, output, cache));
    try testing.expectEqual(built.inode, (try std.Io.Dir.cwd().statFile(testing.io, output, .{})).inode);
    // A fresh cache compiles every object: the same program is published
    // again rather than compared.
    try testing.expect(try reportedOutputChange(a, entry, output, try std.fs.path.join(a, &.{ root, "fresh" })));
    try testing.expect(built.inode != (try std.Io.Dir.cwd().statFile(testing.io, output, .{})).inode);
    try testing.expectEqualStrings("7\n3:3\n", try programOutput(a, output));
}

/// The standard error of `program` run with no arguments.
fn programStderr(allocator: std.mem.Allocator, program: []const u8) ![]const u8 {
    const result = try std.process.run(allocator, testing.io, .{ .argv = &.{program} });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    return result.stderr;
}

// spec-case: DEBUG-LINE-1
test "a ReleaseFast project build drops debug lines and a Debug one keeps them" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = "module main\nimport helper\n\n\ndef main() -> int:\n    debug(\"trace\")\n    return helper.zero()\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data = "module helper\n\n\npublic def zero() -> int:\n    debug(\"inner\")\n    return 0\n" });
    const entry = try std.fs.path.join(a, &.{ root, "main.my" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const debug_program = try std.fs.path.join(a, &.{ root, "debug" });
    const fast_program = try std.fs.path.join(a, &.{ root, "fast" });
    const debug_build = try std.process.run(a, testing.io, .{ .argv = &.{ compiler_path, "build", entry, "--project", "-o", debug_program, "--cache-dir", cache, "--mode", "Debug", tools[0], tools[1] } });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, debug_build.term);
    const fast_build = try std.process.run(a, testing.io, .{ .argv = &.{ compiler_path, "build", entry, "--project", "-o", fast_program, "--cache-dir", cache, "--mode", "ReleaseFast", "--backend", "qbe", tools[0], tools[1] } });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, fast_build.term);
    try testing.expectEqualStrings("trace\ninner\n", try programStderr(a, debug_program));
    try testing.expectEqualStrings("", try programStderr(a, fast_program));
}

/// How one `--report` build of `entry` into `output` over `cache` ran its
/// link, followed by whether the output changed.
fn reportedLinkRoute(allocator: std.mem.Allocator, entry: []const u8, output: []const u8, cache: []const u8) ![]const u8 {
    const result = try std.process.run(allocator, testing.io, .{ .argv = &.{ compiler_path, "build", entry, "--project", "-o", output, "--cache-dir", cache, "--mode", "Debug", "--report", tools[0], tools[1] } });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    const report = try std.json.parseFromSliceLeaky(std.json.Value, allocator, result.stdout, .{});
    const changed = if (report.object.get("output_changed").?.bool) "changed" else "kept";
    return std.fmt.allocPrint(allocator, "{s} {s}", .{ report.object.get("link_route").?.string, changed });
}

// spec-case: BUILD-LINK-1
test "the first link records how zig cc links and every later link runs the linker directly" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    try writeIncrementalVersion(temporary.dir, .{ .main = incremental_main, .helper = incremental_helper });
    const entry = try std.fs.path.join(a, &.{ root, "main.my" });
    const output = try std.fs.path.join(a, &.{ root, "program" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    try testing.expectEqualStrings("recorded changed", try reportedLinkRoute(a, entry, output, cache));
    // A direct relink of the same objects writes exactly the bytes `zig cc`
    // wrote: the comparison keeps the published executable.
    try temporary.dir.deleteFile(testing.io, "program.qbe-manifest.json");
    try testing.expectEqualStrings("direct kept", try reportedLinkRoute(a, entry, output, cache));
    try writeIncrementalVersion(temporary.dir, incremental_versions[0]);
    // An edit relinks with no `zig cc`, and the program is the edited one.
    try testing.expectEqualStrings("direct changed", try reportedLinkRoute(a, entry, output, cache));
    try testing.expectEqualStrings("17\n3:3\n", try programOutput(a, output));
}

// spec-case: BUILD-NOOP-1
test "an unchanged build keeps its executable without rebuilding and a replaced one is rebuilt" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    try writeIncrementalVersion(temporary.dir, .{ .main = incremental_main, .helper = incremental_helper });
    const entry = try std.fs.path.join(a, &.{ root, "main.my" });
    const output = try std.fs.path.join(a, &.{ root, "program" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const argv = [_][]const u8{ compiler_path, "build", entry, "--project", "-o", output, "--cache-dir", cache, "--mode", "Debug", "--timings=json", tools[0], tools[1] };
    const cold = try std.process.run(a, testing.io, .{ .argv = &argv });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cold.term);
    const built = try std.Io.Dir.cwd().statFile(testing.io, output, .{});
    // Nothing changed: no codegen or link ran, and the executable is untouched.
    const noop = try std.process.run(a, testing.io, .{ .argv = &argv });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, noop.term);
    try testing.expect(std.mem.indexOf(u8, noop.stderr, "\"name\":\"codegen\",\"duration_ns\":0,") != null);
    try testing.expect(std.mem.indexOf(u8, noop.stderr, "\"name\":\"link\",\"duration_ns\":0,") != null);
    const kept = try std.Io.Dir.cwd().statFile(testing.io, output, .{});
    try testing.expectEqual(built.inode, kept.inode);
    try testing.expectEqual(built.mtime.nanoseconds, kept.mtime.nanoseconds);
    try testing.expectEqualStrings("7\n3:3\n", try programOutput(a, output));
    // A replaced executable is not the recorded one: the build puts it back.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "program", .data = "stale" });
    const repaired = try std.process.run(a, testing.io, .{ .argv = &argv });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, repaired.term);
    try testing.expect(std.mem.indexOf(u8, repaired.stderr, "\"name\":\"link\",\"duration_ns\":0,") == null);
    try testing.expectEqualStrings("7\n3:3\n", try programOutput(a, output));
}

/// One contract fixture: a module whose `half` carries `@requires(PRE)` and
/// whose `Range` carries `@invariant(INV)`, with a passing test for each.
fn contractFixture(precondition: []const u8, invariant: []const u8) ![]u8 {
    return std.fmt.allocPrint(testing.allocator,
        \\module main
        \\
        \\@invariant({s})
        \\public record Range:
        \\    low: int
        \\    high: int
        \\
        \\@requires({s})
        \\public def half(amount: int) -> int:
        \\    return amount // 2
        \\
        \\def make(low: int) -> Range:
        \\    return Range(low, 5)
        \\
        \\public def test_half() -> bool:
        \\    return half(4) == 2
        \\
        \\public def test_make() -> bool:
        \\    return make(3).low == 3
        \\
        \\def main() -> int:
        \\    return half(4) + make(3).low
        \\
    , .{ invariant, precondition });
}

/// Run one compiler command and hand back its result; the caller frees it.
fn contractCommand(argv: []const []const u8) !std.process.RunResult {
    return std.process.run(testing.allocator, testing.io, .{ .argv = argv });
}

fn freeResult(result: std.process.RunResult) void {
    testing.allocator.free(result.stdout);
    testing.allocator.free(result.stderr);
}

/// Write `main.my` from the fixture template in `directory`.
fn writeContractFixture(directory: std.Io.Dir, precondition: []const u8, invariant: []const u8) !void {
    const text = try contractFixture(precondition, invariant);
    defer testing.allocator.free(text);
    try directory.writeFile(testing.io, .{ .sub_path = "main.my", .data = text });
}

// spec: CONTRACT-CACHE-1
test "CLI an edit to one contract clause is never served from a warm cache" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeContractFixture(temporary.dir, "amount > 0", "self.low <= self.high");
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.my" });
    defer testing.allocator.free(entry);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);
    const warm_test = try contractCommand(&.{ compiler_path, "test", entry, cache_argument, tools[0], tools[1] });
    defer freeResult(warm_test);
    try testing.expect(std.mem.indexOf(u8, warm_test.stdout, "2 passed") != null);
    const warm_run = try contractCommand(&.{ compiler_path, "run", entry, cache_argument, tools[0], tools[1] });
    defer freeResult(warm_run);
    try testing.expectEqual(std.process.Child.Term{ .exited = 5 }, warm_run.term);
    // Only the precondition changes: the same caches must now trap under it.
    try writeContractFixture(temporary.dir, "amount > 10", "self.low <= self.high");
    const run = try contractCommand(&.{ compiler_path, "run", entry, cache_argument, tools[0], tools[1] });
    defer freeResult(run);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, run.term);
    try testing.expect(std.mem.indexOf(u8, run.stderr, "error[R_REQUIRES]: precondition violated: half requires `amount > 10`") != null);
    const tested = try contractCommand(&.{ compiler_path, "test", entry, cache_argument, tools[0], tools[1] });
    defer freeResult(tested);
    try testing.expect(std.mem.indexOf(u8, tested.stdout, "failed main::test_half: R_REQUIRES: half requires `amount > 10`") != null);
    try testing.expect(std.mem.indexOf(u8, tested.stdout, "1 failed") != null);
    // An invariant lives on another declaration than the body that checks it.
    try writeContractFixture(temporary.dir, "amount > 10", "self.low > self.high");
    const rechecked = try contractCommand(&.{ compiler_path, "test", entry, cache_argument, tools[0], tools[1] });
    defer freeResult(rechecked);
    try testing.expect(std.mem.indexOf(u8, rechecked.stdout, "failed main::test_make: R_INVARIANT: Range invariant `self.low > self.high`") != null);
    try testing.expect(std.mem.indexOf(u8, rechecked.stdout, "2 failed") != null);
}

// spec: CONTRACT-INTERFACE-1
test "CLI interfaces, the contracts manifest, context and api-diff carry contract clauses" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeContractFixture(temporary.dir, "amount > 0", "self.low <= self.high");
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.my" });
    defer testing.allocator.free(entry);
    const baseline = try std.fs.path.join(testing.allocator, &.{ root, "baseline.txt" });
    defer testing.allocator.free(baseline);
    const write_argument = try std.fmt.allocPrint(testing.allocator, "--write={s}", .{baseline});
    defer testing.allocator.free(write_argument);
    const against_argument = try std.fmt.allocPrint(testing.allocator, "--against={s}", .{baseline});
    defer testing.allocator.free(against_argument);
    const listed = try contractCommand(&.{ compiler_path, "list-interfaces", entry });
    defer freeResult(listed);
    try testing.expect(std.mem.indexOf(u8, listed.stdout, "export type Range @invariant(self.low <= self.high)") != null);
    try testing.expect(std.mem.indexOf(u8, listed.stdout, "tests(1) @requires(amount > 0)") != null);
    const manifest = try contractCommand(&.{ compiler_path, "list-interfaces", "--contracts", entry });
    defer freeResult(manifest);
    try testing.expect(std.mem.indexOf(u8, manifest.stdout, "\"contracts\":\"@invariant(self.low <= self.high)\"") != null);
    const context = try contractCommand(&.{ compiler_path, "context", entry, "--symbol=main::half" });
    defer freeResult(context);
    try testing.expect(std.mem.indexOf(u8, context.stdout, "\"signature\":\"@requires(amount > 0)\\nhalf(amount: int) -> int") != null);
    const written = try contractCommand(&.{ compiler_path, "api-diff", entry, write_argument });
    defer freeResult(written);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, written.term);
    try writeContractFixture(temporary.dir, "amount > 1", "self.low < self.high");
    const diffed = try contractCommand(&.{ compiler_path, "api-diff", entry, against_argument });
    defer freeResult(diffed);
    try testing.expect(std.mem.indexOf(u8, diffed.stdout, "breaking: main::Range (interface changed)") != null);
    try testing.expect(std.mem.indexOf(u8, diffed.stdout, "breaking: main::half (interface changed)") != null);
}

// spec-case: CONTRACT-TRAP-1
test "CLI a release build and a JSON diagnostic report the contract that failed" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\@requires(amount > 0, "amount must be positive")
        \\def half(amount: int) -> int:
        \\    return amount // 2
        \\
        \\@ensures(result > 100)
        \\def grow(x: int) -> int:
        \\    return x + 1
        \\
        \\def main() -> int:
        \\    return grow(half(8))
        \\
    });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "caller.my", .data =
        \\@requires(amount > 0, "amount must be positive")
        \\def half(amount: int) -> int:
        \\    return amount // 2
        \\
        \\def main() -> int:
        \\    return half(0)
        \\
    });
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.my" });
    defer testing.allocator.free(entry);
    const caller = try std.fs.path.join(testing.allocator, &.{ root, "caller.my" });
    defer testing.allocator.free(caller);
    const program = try std.fs.path.join(testing.allocator, &.{ root, "program" });
    defer testing.allocator.free(program);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{root});
    defer testing.allocator.free(cache_argument);
    const built = try contractCommand(&.{ compiler_path, "build", entry, "-o", program, "--release", cache_argument, tools[1] });
    defer freeResult(built);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const released = try contractCommand(&.{program});
    defer freeResult(released);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, released.term);
    try testing.expect(std.mem.indexOf(u8, released.stderr, "error[R_ENSURES]: postcondition violated: grow ensures `result > 100`") != null);
    const json = try contractCommand(&.{ compiler_path, "run", caller, "--diagnostics=json", cache_argument, tools[0], tools[1] });
    defer freeResult(json);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, json.term);
    try testing.expect(std.mem.indexOf(u8, json.stderr, "\"code\":\"R_REQUIRES\"") != null);
    try testing.expect(std.mem.indexOf(u8, json.stderr, "\"contract\":{\"kind\":\"requires\",\"subject\":\"half\",\"clause\":\"amount > 0\",\"message\":\"amount must be positive\",\"caller\":{") != null);
}
