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
    \\host def measure(x: i64) -> i64 effects(host)
    \\
    \\
    \\def main() -> i64:
    \\    return measure(6)
;

// spec-case: CONSTANT-2
test "CLI managed constants check and reject expressions" {
    try invoke("check", "const S: str = \"hé🙂\"\nconst B: bytes = b\"\\x00\\xff\"\ndef main() -> int:\n    return len(S) + len(B)\n", 0, "", "");
    try invoke("check", "const S: str = \"a\" + \"b\"\ndef main() -> int:\n    return 0\n", 1, "", "E_CONSTANT_EXPRESSION");
    try invoke("check", "const B: bytes = OTHER\nconst OTHER: bytes = b\"x\"\ndef main() -> int:\n    return 0\n", 1, "", "E_CONSTANT_EXPRESSION");
}

fn expectConstantProcess(argv: []const []const u8, expected: []const u8) !void {
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv });
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
    try expectConstantProcess(&.{ output, "--gc-stress" }, expected);
}

// spec-case: CONSTANT-2
test "CLI managed constants import run build installed and invalidate warm caches" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\module main
        \\import constants
        \\def read[T]() -> str effects(managed_allocation):
        \\    return constants.TEXT
        \\def main() -> int:
        \\    print(read[int]())
        \\    print(len(constants.DATA))
        \\    print(constants.DATA[1])
        \\    return 0
    });
    const original = "module constants\nexport TEXT\nexport DATA\nconst TEXT: str = \"hé🙂\"\nconst DATA: bytes = b\"\\x00\\xff\"\n";
    try managedConstantModes(&temporary, original, "hé🙂\n2\n255\n");
    try managedConstantModes(&temporary, original, "hé🙂\n2\n255\n");
    // Same byte lengths, new contents: unchanged callers must observe the new IL.
    try managedConstantModes(&temporary, "module constants\nexport TEXT\nexport DATA\nconst TEXT: str = \"hà🙃\"\nconst DATA: bytes = b\"\\x00\\xfe\"\n", "hà🙃\n2\n254\n");
}

test "CLI checks host declarations and refuses to run one with no registration" {
    try invoke("check", host_program, 0, "", "");
    // Nothing registers a host implementation for a plain `mylang run`, so the
    // program cannot start; that is a host-boundary refusal, not a guest trap.
    try invoke("run", host_program, 2, "", "HostMissingRegistration");
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
    const installed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ output, "--restrict" } });
    defer testing.allocator.free(installed.stdout);
    defer testing.allocator.free(installed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, installed.term);
    try testing.expectEqualStrings("", installed.stdout);
    try testing.expectEqualStrings(message, installed.stderr);
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
        \\def main() -> int:
        \\    print("out", 1)
        \\    eprint("err", 7, sep="-", end="!\n")
        \\    eprint()
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
        \\def main(args: list[str]) -> int:
        \\    print("count", len(args))
        \\    for value in args:
        \\        print("[" + value + "]")
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
        \\def main(args: list[str]) -> int:
        \\    print(helper.render(args))
        \\    return 0
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.my", .data =
        \\module helper
        \\
        \\export render
        \\
        \\def render(args: list[str]) -> str:
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
    try install_argv.append(testing.allocator, output);
    try install_argv.append(testing.allocator, "--");
    try install_argv.appendSlice(testing.allocator, &guest);
    const installed = try std.process.run(testing.allocator, testing.io, .{ .argv = install_argv.items });
    defer testing.allocator.free(installed.stdout);
    defer testing.allocator.free(installed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, installed.term);
    try testing.expectEqualStrings(expected, installed.stdout);
    try testing.expectEqualStrings("", installed.stderr);

    var installed_stress_argv: std.ArrayList([]const u8) = .empty;
    defer installed_stress_argv.deinit(testing.allocator);
    try installed_stress_argv.appendSlice(testing.allocator, &.{ output, "--gc-stress", "--" });
    try installed_stress_argv.appendSlice(testing.allocator, &guest);
    const installed_stress = try std.process.run(testing.allocator, testing.io, .{ .argv = installed_stress_argv.items });
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
    try installed_invalid_argv.appendSlice(testing.allocator, &.{ output, "--", "\xff" });
    const installed_invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = installed_invalid_argv.items });
    defer testing.allocator.free(installed_invalid.stdout);
    defer testing.allocator.free(installed_invalid.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, installed_invalid.term);
    try testing.expectEqualStrings("", installed_invalid.stdout);
    try testing.expect(std.mem.indexOf(u8, installed_invalid.stderr, "not valid UTF-8") != null);
}

fn spawnWithEnv(argv: []const []const u8, env_map: *const std.process.Environ.Map) !std.process.RunResult {
    return std.process.run(testing.allocator, testing.io, .{ .argv = argv, .environ_map = env_map });
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
    var trace_env: std.process.Environ.Map = .init(testing.allocator);
    defer trace_env.deinit();
    try trace_env.put("HOME", home);
    try trace_env.put("MYLANG_ACCEPT_MODE", "1");

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
    const installed = try spawnWithEnv(&.{ output, "--", input }, &trace_env);
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
        \\    return 0
    , &.{});
    defer testing.allocator.free(compilation.stdout);
    defer testing.allocator.free(compilation.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, compilation.term);
}
test "CLI module interfaces parse bodies and check exported signature visibility" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\module input
        \\import units
        \\export Sample
        \\
        \\
        \\class Sample:
        \\    distance: units.Distance
        \\
        \\
        \\def main() -> i64:
        \\    return unknown()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "units.my", .data =
        \\module units
        \\export Distance
        \\
        \\
        \\domain Distance: i64:
        \\    def make(x: i64) -> Distance:
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
    for ([_][]const u8{ "E_PRIVATE_SYMBOL", "input.my:7:", "units.my:4:" }) |part| try testing.expect(std.mem.indexOf(u8, hidden.stderr, part) != null);
    try invoke("list-interfaces",
        \\module input
        \\def broken(
    , 1, "", "E_SYNTAX");
    try invoke("list-interfaces",
        \\module input
        \\export f
        \\
        \\
        \\class Secret:
        \\    pass
        \\
        \\
        \\def f() -> Secret:
        \\    return Secret()
    , 1, "", "E_PRIVATE_INTERFACE");
    try invokeOptions("list-interfaces", "module input", &.{"--check"}, 2, "", "usage:");
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
        \\export value
        \\
        \\
        \\def value() -> i64:
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
        \\export value
        \\
        \\
        \\def value() -> i64:
        \\    return divtrunc(1, 0)
    });
    const trap = try std.process.run(testing.allocator, testing.io, .{ .argv = &(.{ compiler_path, "run-project", path, "--print-result" } ++ tools) });
    defer testing.allocator.free(trap.stdout);
    defer testing.allocator.free(trap.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, trap.term);
    for ([_][]const u8{ "R_DIVISION_BY_ZERO", "helper.my:6:", "input.my:6:" }) |part| try testing.expect(std.mem.indexOf(u8, trap.stderr, part) != null);
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
        \\export value
        \\
        \\
        \\def value() -> i64:
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
        \\export value
        \\
        \\
        \\def value() -> i64:
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
        \\export entry
        \\
        \\
        \\def entry() -> i64:
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
    try testing.expectEqualStrings("", result.stderr);
    for ([_][]const u8{ "quality-modules-v1", "api.my:5:", "api::entry; private=false; reachable-from-main=false", "module-exported=true reachable-from-exports=true", "module-exported=false reachable-from-exports=true", "function-lines 2 exceeds configured 1", "calls api::hidden at api.my:6:", "Runtime coverage and assertions: not measured" }) |part| try testing.expect(std.mem.indexOf(u8, result.stdout, part) != null);
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
        \\export Missing
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
        \\export read
        \\
        \\
        \\def read() -> i64:
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
        \\class Node[T]:
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
    , 1, "", "error[");
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
    \\export Count
    \\
    \\
    \\# leading comment
    \\# second line
    \\type Count = i64
    \\
    \\
    \\const LIMIT: Count = 3 # trailing note
    \\
    \\
    \\class Job:
    \\    id: Count
    \\
    \\
    \\host def measure(x: i64) -> i64 effects(host)
    \\
    \\
    \\export main
    \\
    \\
    \\def main() -> i64:
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
    , &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_UNKNOWN_EXPORT\"");
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
    try invoke("run", bounds, 1, "", ":3:12: error[R_INDEX_BOUNDS]");
    try invoke("run",
        \\def main() -> i64:
        \\    payload: [1]u8 = [7u8]
        \\    _ = replace(payload, 18446744073709551615u64, 8u8)
        \\    return 0
    , 1, "", "error[R_INDEX_BOUNDS]");
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
    , 1, "", "expected Key, found i64");
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
test "CLI checks external capabilities but cannot silently grant ambient providers" {
    const source = @embedFile("fixtures/external-capabilities.my");
    try invoke("check", source, 0, "", "");
    try invokeOptions("run", source, &.{"--restrict"}, 2, "", "--restrict is active");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    for ([_][]const u8{ "EXTERNAL_clock", "EXTERNAL_random", "effects {clock, random}" }) |text| try testing.expect(std.mem.indexOf(u8, dumped.stdout, text) != null);
    const invalid =
        \\result T:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\def main(c: Clock) -> i64 effects():
        \\    _ = clock_now[T](c)
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_EFFECT_BOUND]");
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
        \\class Entry:
        \\    bytes: [1]u8
        \\    length: u64
        \\    present: bool
        \\
        \\
        \\result Lookup:
        \\    ok: Entry,
        \\    err: i64
        \\
        \\
        \\def main(env: Environment) -> i64 effects():
        \\    _ = environment_get[Lookup](env, [75u8])
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_EFFECT_BOUND]");
}
test "CLI exposes resource permission attenuation and rejects malformed permission sets" {
    const source = @embedFile("fixtures/attenuation.my");
    try invoke("check", source, 0, "", "");
    try invokeOptions("run", source, &.{"--restrict"}, 2, "", "--restrict is active");
    const dumped = try runFixture("dump-bytecode", source, &.{});
    defer testing.allocator.free(dumped.stdout);
    defer testing.allocator.free(dumped.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, dumped.term);
    try testing.expect(std.mem.indexOf(u8, dumped.stdout, "RESTRICT_RESOURCE permissions=1 -> filesystem_cap") != null);
    const invalid =
        \\def main(fs: Filesystem) -> i64:
        \\    _ = restrict_resource[read, read](fs)
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "dump-bytecode", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_PERMISSION]");
}

const clock_program =
    \\result Time:
    \\    ok: i64,
    \\    err: i64
    \\
    \\
    \\def main(clock: Clock) -> i64:
    \\    match clock_now[Time](clock):
    \\        case Time.ok(now):
    \\            return now - now
    \\        case Time.err(code):
    \\            return code
;
// spec: CAPABILITY-1
test "CLI accepts Python capability spellings and lets a declared type keep the name" {
    try invoke("check", clock_program, 0, "", "");
    const declared =
        \\class Clock:
        \\    ticks: int
        \\
        \\def main() -> int:
        \\    return Clock(ticks=7).ticks
    ;
    try invoke("run", declared, 0, "7\n", "");
    const entropy =
        \\result Word:
        \\    ok: u64,
        \\    err: i64
        \\
        \\
        \\def main(rng: Entropy) -> i64:
        \\    _ = random_u64[Word](rng)
        \\    return 0
    ;
    try invoke("check", entropy, 0, "", "");
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
    }) |options| try invokeOptions("run", clock_program, options, 2, "", "usage:");
    try invokeOptions("check", clock_program, &.{"--allow-clock"}, 2, "", "usage:");
    try invokeOptions("check", clock_program, &.{"--restrict"}, 2, "", "usage:");
    try invokeOptions("dump-bytecode", clock_program, &.{"--allow-clock"}, 2, "", "usage:");
}
// spec: CAPABILITY-3
test "CLI refuses an ungranted entry capability only while --restrict is active" {
    const environment =
        \\class Entry:
        \\    bytes: [8]u8
        \\    length: u64
        \\    present: bool
        \\
        \\
        \\result Lookup:
        \\    ok: Entry,
        \\    err: i64
        \\
        \\
        \\def main(env: Environment) -> i64:
        \\    _ = environment_get[Lookup](env, [80u8, 65u8, 84u8, 72u8])
        \\    return 0
    ;
    for ([_][]const u8{ clock_program, environment }) |program| {
        try invokeOptions("run", program, &.{"--restrict"}, 2, "", "--restrict is active");
        try invokeOptions("run", program, &.{"--restrict"}, 2, "", "drop --restrict");
        // The default grants every capability, so the same program runs unchanged.
        try invoke("run", program, 0, "0\n", "");
    }
    try invokeOptions("run", clock_program, &.{ "--restrict", "--allow-clock" }, 0, "0\n", "");
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
        \\result Word:
        \\    ok: u64,
        \\    err: i64
        \\
        \\
        \\def main(rng: Entropy) -> i64:
        \\    match random_u64[Word](rng):
        \\        case Word.ok(value):
        \\            return i64(value % 1000u64)
        \\        case Word.err(code):
        \\            return code
    ;
    const first = try runFixture("run", seeded, &.{"--allow-random=11"});
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    const again = try runFixture("run", seeded, &.{"--allow-random=11"});
    defer testing.allocator.free(again.stdout);
    defer testing.allocator.free(again.stderr);
    try testing.expectEqualStrings(first.stdout, again.stdout);
    // The seeded entry returns `value % 1000`, which is now the exit status; the
    // value is unknown here, so assert the contract against its printed result.
    try testing.expectEqual(std.process.Child.Term{ .exited = resultStatus(first.stdout) }, first.term);
    const missing =
        \\class Entry:
        \\    bytes: [8]u8
        \\    length: u64
        \\    present: bool
        \\
        \\
        \\result Lookup:
        \\    ok: Entry,
        \\    err: i64
        \\
        \\
        \\def main(env: Environment) -> i64:
        \\    match environment_get[Lookup](env, [80u8, 65u8, 84u8, 72u8]):
        \\        case Lookup.ok(entry):
        \\            return i64(entry.length) - i64(entry.length)
        \\        case Lookup.err(code):
        \\            return code
    ;
    // PATH is outside this allowlist, so the lookup is denied rather than answered.
    try invokeOptions("run", missing, &.{ "--restrict", "--allow-env=OTHER" }, 0, "2\n", "");
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
        \\def main(fs: Filesystem) -> int:
        \\    print(read_text(fs, "notes.txt"))
        \\    print(write_text(fs, "copy.txt", "beta\n"))
        \\    print(read_text(fs, "../escape"))
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
        \\def main() -> int:
        \\    print("streamed")
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
        \\def main(clock: Clock, rng: Entropy, fs: Filesystem) -> int:
        \\    match time.now(clock):
        \\        case Ok(instant):
        \\            print("clock", instant.unix_nanoseconds - instant.unix_nanoseconds)
        \\        case Err(message):
        \\            print(message)
        \\    match random.from_entropy(rng):
        \\        case Ok(stream):
        \\            print("entropy", len(stream.state))
        \\        case Err(message):
        \\            print(message)
        \\    print(exists(fs, "notes.txt"))
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
        \\def main(fs: Filesystem) -> int:
        \\    print(read_text(fs, "notes.txt"))
        \\    print(write_text(fs, "made.txt", "beta\n"))
        \\    print(read_text(fs, "../escape"))
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
    const absolute = try std.fmt.allocPrint(testing.allocator, "def main(fs: Filesystem) -> int:\n    print(read_text(fs, \"{s}\"))\n    return 0\n", .{anchor});
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
        \\export answer
        \\
        \\def answer() -> i64:
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
        \\export answer
        \\
        \\def answer() -> i64:
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
        \\export answer
        \\
        \\def answer() -> i64:
        \\    return True
    });
    const broken = try projectCacheCheck(entry, cache_argument, 1);
    try testing.expectEqual(@as(usize, 0), broken.verdict_hits);

    // Repair the source so the final no-cache run is a successful check.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.my", .data =
        \\module helper
        \\
        \\export answer
        \\
        \\def answer() -> i64:
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
        \\export answer
        \\
        \\def answer() -> i64:
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
        \\export answer
        \\
        \\def answer() -> i64:
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
        \\export answer
        \\
        \\def answer() -> i64:
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
        \\export answer
        \\
        \\def answer() -> i64:
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
    const installed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ output, "--restrict" } });
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
    try installed_argv.append(testing.allocator, output);
    try installed_argv.append(testing.allocator, "--");
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
    \\export Prices
    \\
    \\
    \\constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
;
const named_constraint_checkout =
    \\module checkout
    \\import contracts
    \\export total
    \\
    \\
    \\def total[P: contracts.Prices](policy: P, subtotal: int) -> int effects():
    \\    return P.price(policy, subtotal) + 500
;
const named_constraint_fakes =
    \\module fakes
    \\export FixedPrices
    \\
    \\
    \\domain FixedPrices: int:
    \\    def make(amount: int) -> FixedPrices:
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
    \\export test_checkout
    \\
    \\
    \\def main() -> int:
    \\    assert test_checkout()
    \\    return 0
    \\
    \\
    \\def test_checkout() -> bool:
    \\    return checkout.total(fakes.FixedPrices.make(1750), 2000) == 2250
;
const named_constraint_production_invalid =
    \\module production
    \\import contracts
    \\export DiscountPrices
    \\
    \\
    \\domain DiscountPrices: int:
    \\    def make(discount: int) -> DiscountPrices:
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
