//! Spawn the selected-mode compiler binary; fixtures assert the public CLI contract.
const std = @import("std");
const transition = @import("ownership_transition_test_support.zig");
const testing = std.testing;
const check_line = @import("check_line.zig");
/// The `selka` executable under test, which `zig build` names at run time (TEST-PATHS-1).
fn compilerPath() []const u8 {
    return @import("test_paths").corePath();
}
/// True while release builds are off (`-Dtest-release=true` turns them on). A helper that follows a debug half with a release
/// half returns when it holds, and its test ends with `requireRelease()` so that it is reported as skipped, never as passed.
fn releaseOff() bool {
    return !@import("test_release_options").enabled;
}
/// Skips the calling test while release builds are off. A release build calls it after the debug assertions the same test makes.
fn requireRelease() error{SkipZigTest}!void {
    if (releaseOff()) return error.SkipZigTest;
}
/// Skips the calling test while release builds are off, when a compiler command line asks for one: `--release`, `--mode ReleaseFast`
/// or `--mode=ReleaseFast`. Arguments after `--` belong to the guest program and are not read.
fn requireReleaseArgs(argv: []const []const u8) error{SkipZigTest}!void {
    for (argv, 0..) |arg, index| {
        if (std.mem.eql(u8, arg, "--")) return;
        const mode_value = std.mem.eql(u8, arg, "--mode") and index + 1 < argv.len and std.mem.eql(u8, argv[index + 1], "ReleaseFast");
        if (mode_value or std.mem.eql(u8, arg, "--release") or std.mem.eql(u8, arg, "--mode=ReleaseFast")) return requireRelease();
    }
}
test {
    _ = @import("components.zig");
    _ = @import("overview_cli_test.zig");
    _ = @import("cache_retention_cli_test.zig");
    _ = @import("target_cli_test.zig");
    _ = @import("cpu_cli_test.zig");
    _ = @import("work_markers_cli_test.zig");
    _ = @import("constant_value_cache_cli_test.zig");
    _ = @import("native_cli_test.zig");
    _ = @import("store_settings_cli_test.zig");
    _ = @import("release_cli_test.zig");
    _ = @import("review_cli_test.zig");
    _ = @import("ownership_fix_cli_test.zig");
    _ = @import("friction_cli_test.zig");
    _ = @import("frame_floor_cli_test.zig");
    _ = @import("compiler_stack_cli_test.zig");
    _ = @import("trap_position_cli_test.zig");
    _ = @import("debug_codegen_cli_test.zig");
    _ = @import("file_read_errors_cli_test.zig");
    _ = @import("runtime_limits_cli_test.zig");
    _ = @import("crossing_hints_cli_test.zig");
    _ = @import("file_directory_errors_cli_test.zig");
    _ = @import("test_directory_unchecked_cli_test.zig");
    _ = @import("network_poller_cli_test.zig");
    _ = @import("network_address_cli_test.zig");
    _ = @import("run_signals_cli_test.zig");
    _ = @import("engine_cli_test.zig");
    _ = @import("check_directory_cli_test.zig");
    _ = @import("named_folder_cli_test.zig");
    _ = @import("check_build_agree_cli_test.zig");
    _ = @import("check_generic_bodies_cli_test.zig");
    _ = @import("template_stand_ins_cli_test.zig");
    _ = @import("check_build_agree_redo_cli_test.zig");
    _ = @import("hole_replay_cli_test.zig");
    _ = @import("ownership_matrix_cli_test.zig");
    _ = @import("match_mut_matrix_cli_test.zig");
    _ = @import("exchange_matrix_cli_test.zig");
    _ = @import("parse_matrix_cli_test.zig");
    _ = @import("match_mut_pairs_cli_test.zig");
    _ = @import("fs_permissions_cli_test.zig");
    _ = @import("private_test_reuse_cli_test.zig");
    _ = @import("test_stub_cli_test.zig");
    _ = @import("test_advice_cli_test.zig");
}
// spec-case: TEST-PATHS-1
test "the CLI test binary names neither its build tree nor the executables it runs outside debug sections" {
    const paths = @import("test_paths");
    const root = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const self = try std.process.executablePathAlloc(testing.io, testing.allocator);
    defer testing.allocator.free(self);
    try testing.expectEqual(@as(usize, 0), try paths.occurrencesOutsideDebug(testing.io, std.Io.Dir.cwd(), self, root));
    try testing.expectEqual(@as(usize, 0), try paths.occurrencesOutsideDebug(testing.io, std.Io.Dir.cwd(), self, std.fs.path.dirname(compilerPath()).?));
    try testing.expectEqual(@as(usize, 0), try paths.occurrencesOutsideDebug(testing.io, std.Io.Dir.cwd(), self, std.fs.path.dirname(paths.componentBuilderPath()).?));
    try testing.expect(try paths.occurrencesOutsideDebug(testing.io, std.Io.Dir.cwd(), self, paths.component_builder_variable) > 0);
}
// Bind corruption fixtures to the compiler's exported durable-store format.
const semantic_cache_version = @import("test_options").semantic_cache_version;

// spec: VALUE-SEMANTICS-11
test "a scalar-only mut record parameter writes the caller" {
    const program =
        \\record Counter:
        \\    n: int
        \\
        \\func increment(mut c: Counter) -> Unit:
        \\    c.n = c.n + 1
        \\
        \\func reset(mut c: Counter) -> Unit:
        \\    c = Counter(n=10)
        \\
        \\func main() -> int:
        \\    mut c = Counter(n=1)
        \\    increment(mut c)
        \\    reset(mut c)
        \\    return c.n
    ;
    try invokeOptions("run", program, &.{}, 10, "10\n", "");
}
/// `run` and `run-project` build natively; the fixtures name this build's Zig
/// because the compiler under test is not installed beside it.
const tools = [_][]const u8{
    "--zig=" ++ @import("test_options").zig_path,
};
const host_program =
    \\host func measure(host: Host, x: i64) -> i64 effects(host)
    \\
    \\
    \\func main(host: Host) -> i64:
    \\    return measure(host, 6)
;

// spec-case: CONSTANT-2
test "CLI managed constants check and reject expressions" {
    try invoke("check", "const S: str = \"hé🙂\"\nconst B: bytes = b\"\\x00\\xff\"\nfunc main() -> int:\n    return strings.char_count(S) + len(B)\n", 0, "", "");
    try invoke("check", "const S: str = \"a\" * 2\nfunc main() -> int:\n    return 0\n", 1, "", "E_CONSTANT_EXPRESSION");
    try invoke("check", "const B: bytes = OTHER + b\"y\"\nconst OTHER: bytes = b\"x\" + B\nfunc main() -> int:\n    return 0\n", 1, "", "E_CONSTANT_CYCLE");
}

fn expectConstantProcess(argv: []const []const u8, expected: []const u8) !void {
    return expectConstantRun(argv, null, expected);
}

/// The inherited environment plus `SELKA_OPTIONS`, where a built program reads
/// its runtime options.
fn runtimeOptions(value: []const u8) !std.process.Environ.Map {
    var environment = try std.process.Environ.createMap(testing.environ, testing.allocator);
    errdefer environment.deinit();
    try environment.put("SELKA_OPTIONS", value);
    return environment;
}

fn expectConstantRun(argv: []const []const u8, environment: ?*const std.process.Environ.Map, expected: []const u8) !void {
    try requireReleaseArgs(argv);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv, .environ_map = environment });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqualStrings("", result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings(expected, result.stdout);
}

fn managedConstantModes(temporary: *testing.TmpDir, data: []const u8, expected: []const u8) !void {
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "constants.selka", .data = data });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const output = try std.fs.path.join(testing.allocator, &.{ root, "program" });
    defer testing.allocator.free(output);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);
    try expectConstantProcess(&.{ compilerPath(), "check-project", entry, cache_argument }, "");
    try expectConstantProcess(&.{ compilerPath(), "run", entry, cache_argument, tools[0] }, expected);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "--run", "--cache-dir", cache, tools[0] }, expected);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "--project", "-o", output, "--cache-dir", cache, tools[0] }, "");
    try expectConstantProcess(&.{output}, expected);
}

/// A program whose only unfinished part is a typed hole in `unfinished`, beside a passing test and a test that reaches the hole.
const hole_trap_program =
    \\func unfinished() -> int:
    \\    return todo[int]()
    \\
    \\func double(x: int) -> int:
    \\    return x * 2
    \\
    \\public func test_double() -> bool:
    \\    return double(21) == 42
    \\
    \\public func test_reaches_hole() -> bool:
    \\    return unfinished() == 1
    \\
    \\func main() -> int:
    \\    return 0
;
/// A finished function with an ownership error (a borrowed `message` stored in a record) beside a typed hole.
const hole_ownership_program =
    \\public record Finding:
    \\    message: bytes
    \\    net: bytes
    \\
    \\public func make_finding(message: bytes, net: bytes) -> Finding:
    \\    return Finding(message=message, net=copy(net))
    \\
    \\public func unfinished() -> int:
    \\    return todo[int]()
    \\
    \\public func main(out: Stream) -> int:
    \\    print(out, len(make_finding(b"a", b"b").net))
    \\    return 0
;
test "a typed hole traps only where it is reached, release refuses it, and check still does" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "holes.selka", .data = hole_trap_program });
    const path = try temp.dir.realPathFileAlloc(testing.io, "holes.selka", testing.allocator);
    defer testing.allocator.free(path);
    const cache = try privateTestCache(path);
    defer testing.allocator.free(cache);

    // The test that avoids the hole runs and passes; the one that reaches it traps R_TYPED_HOLE at the hole.
    const passing = try privateRun(testing.allocator, &.{ compilerPath(), "test", path, "--filter", "double", "--cache-dir", cache });
    defer testing.allocator.free(passing.stdout);
    defer testing.allocator.free(passing.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, passing.term);
    try testing.expect(std.mem.indexOf(u8, passing.stdout, "1 passed") != null);
    const reaching = try privateRun(testing.allocator, &.{ compilerPath(), "test", path, "--filter", "reaches", "--cache-dir", cache });
    defer testing.allocator.free(reaching.stdout);
    defer testing.allocator.free(reaching.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, reaching.term);
    try testing.expect(std.mem.indexOf(u8, reaching.stdout, "R_TYPED_HOLE") != null);
    try testing.expect(std.mem.indexOf(u8, reaching.stdout, "unfinished at ") != null);
    try testing.expect(std.mem.indexOf(u8, reaching.stdout, ":2:12") != null);

    // `check` refuses the hole as before, even after the debug runs above.
    const checked = try privateRun(testing.allocator, &.{ compilerPath(), "check", path });
    defer testing.allocator.free(checked.stdout);
    defer testing.allocator.free(checked.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, checked.term);
    try testing.expect(std.mem.indexOf(u8, checked.stderr, "E_TYPED_HOLE") != null);
    // A release build refuses only a hole `main` can reach (F-RB-18): `unfinished` is public, and nothing calls it from `main`.
    const release_out = try std.fs.path.join(testing.allocator, &.{ std.fs.path.dirname(path).?, "holes_release" });
    defer testing.allocator.free(release_out);
    const release = try privateRun(testing.allocator, &.{ compilerPath(), "build", path, "-o", release_out, "--release" });
    defer testing.allocator.free(release.stdout);
    defer testing.allocator.free(release.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, release.term);
    try testing.expectEqualStrings("", release.stderr);
}

/// Build `files` (the first is the entry, `main.selka`) in a temporary directory with `--release` and return what the compiler said.
fn releaseBuildOf(files: []const [2][]const u8, extra: []const []const u8) !struct { run: std.process.RunResult, binary: []u8, directory: testing.TmpDir } {
    var temp = testing.tmpDir(.{});
    errdefer temp.cleanup();
    for (files) |file| try temp.dir.writeFile(testing.io, .{ .sub_path = file[0], .data = file[1] });
    const path = try temp.dir.realPathFileAlloc(testing.io, files[0][0], testing.allocator);
    defer testing.allocator.free(path);
    const binary = try std.fs.path.join(testing.allocator, &.{ std.fs.path.dirname(path).?, "release_binary" });
    errdefer testing.allocator.free(binary);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.appendSlice(testing.allocator, &.{ compilerPath(), "build", path, "-o", binary, "--release" });
    try argv.appendSlice(testing.allocator, extra);
    return .{ .run = try privateRun(testing.allocator, argv.items), .binary = binary, .directory = temp };
}

test "a release build refuses a typed hole main reaches, directly or through a function value" {
    const direct = try releaseBuildOf(&.{.{
        "main.selka",
        \\func unfinished() -> int:
        \\    return todo[int]()
        \\
        \\func main() -> int:
        \\    return unfinished()
    }}, &.{});
    var directory = direct.directory;
    defer directory.cleanup();
    defer testing.allocator.free(direct.binary);
    defer testing.allocator.free(direct.run.stdout);
    defer testing.allocator.free(direct.run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, direct.run.term);
    try testing.expect(std.mem.indexOf(u8, direct.run.stderr, "main.selka:2:12: error[E_TYPED_HOLE]") != null);
    try testing.expect(std.mem.indexOf(u8, direct.run.stderr, "which main can reach") != null);
    try testing.expectError(error.FileNotFound, directory.dir.statFile(testing.io, "release_binary", .{}));

    // A function value counts as a call: `main` hands `unfinished` on and never calls it, and the build still refuses.
    const valued = try releaseBuildOf(&.{.{
        "main.selka",
        \\func unfinished(x: int) -> int:
        \\    return todo[int]()
        \\
        \\func apply(f: func(int) -> int, flag: bool) -> int:
        \\    if flag:
        \\        return f(1)
        \\    return 0
        \\
        \\func main() -> int:
        \\    return apply(unfinished, False)
    }}, &.{"--diagnostics=json"});
    var valued_directory = valued.directory;
    defer valued_directory.cleanup();
    defer testing.allocator.free(valued.binary);
    defer testing.allocator.free(valued.run.stdout);
    defer testing.allocator.free(valued.run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, valued.run.term);
    try testing.expect(std.mem.indexOf(u8, valued.run.stderr, "\"code\":\"E_TYPED_HOLE\"") != null);
}

test "a release build runs past a typed hole in a function and a module main cannot reach" {
    const built = try releaseBuildOf(&.{
        .{
            "main.selka",
            \\import stubs
            \\
            \\func unfinished() -> int:
            \\    return todo[int]()
            \\
            \\func never_called() -> int:
            \\    return unfinished() + stubs.chain()
            \\
            \\func main() -> int:
            \\    return stubs.fine(21)
        },
        .{
            "stubs.selka",
            \\public func later() -> int:
            \\    return todo[int]()
            \\
            \\public func fine(x: int) -> int:
            \\    return x * 2
            \\
            \\public func chain() -> int:
            \\    return later() + 1
        },
    }, &.{});
    var directory = built.directory;
    defer directory.cleanup();
    defer testing.allocator.free(built.binary);
    defer testing.allocator.free(built.run.stdout);
    defer testing.allocator.free(built.run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.run.term);
    try testing.expectEqualStrings("", built.run.stderr);
    const ran = try privateRun(testing.allocator, &.{built.binary});
    defer testing.allocator.free(ran.stdout);
    defer testing.allocator.free(ran.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, ran.term);
}

test "a debug run of a generic typed hole does not let a release build accept it" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const generic_program =
        \\func pick[T](value: T) -> T:
        \\    return todo[T]()
        \\
        \\public func main(out: Stream) -> int:
        \\    print(out, pick(3))
        \\    return 0
    ;
    try temp.dir.writeFile(testing.io, .{ .sub_path = "generic.selka", .data = generic_program });
    const path = try temp.dir.realPathFileAlloc(testing.io, "generic.selka", testing.allocator);
    defer testing.allocator.free(path);
    const run = try privateRun(testing.allocator, &.{ compilerPath(), "run", path });
    defer testing.allocator.free(run.stdout);
    defer testing.allocator.free(run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, run.term);
    try testing.expect(std.mem.indexOf(u8, run.stderr, "R_TYPED_HOLE") != null);
    const release_out = try std.fs.path.join(testing.allocator, &.{ std.fs.path.dirname(path).?, "generic_release" });
    defer testing.allocator.free(release_out);
    const release = try privateRun(testing.allocator, &.{ compilerPath(), "build", path, "-o", release_out, "--release" });
    defer testing.allocator.free(release.stdout);
    defer testing.allocator.free(release.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, release.term);
    try testing.expect(std.mem.indexOf(u8, release.stderr, "E_TYPED_HOLE") != null);
}

test "a typed hole does not hide an ownership error in a finished function" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "owners.selka", .data = hole_ownership_program });
    const path = try temp.dir.realPathFileAlloc(testing.io, "owners.selka", testing.allocator);
    defer testing.allocator.free(path);
    const checked = try privateRun(testing.allocator, &.{ compilerPath(), "check", path });
    defer testing.allocator.free(checked.stdout);
    defer testing.allocator.free(checked.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, checked.term);
    try testing.expect(std.mem.indexOf(u8, checked.stderr, "E_TYPED_HOLE") != null);
    try testing.expect(std.mem.indexOf(u8, checked.stderr, "E_SINGLE_OWNER_BORROW") != null);
    const owners_out = try std.fs.path.join(testing.allocator, &.{ std.fs.path.dirname(path).?, "owners_bin" });
    defer testing.allocator.free(owners_out);
    const built = try privateRun(testing.allocator, &.{ compilerPath(), "build", path, "-o", owners_out });
    defer testing.allocator.free(built.stdout);
    defer testing.allocator.free(built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, built.term);
    try testing.expect(std.mem.indexOf(u8, built.stderr, "E_SINGLE_OWNER_BORROW") != null);
}

// A local named like the root of an imported module path (`eval` beside `import eval.deprecations`) reads as the local
// wherever it is in force, and the same spelling is the module path where it is not (local_qualifiers.zig).
test "a local named like an imported path root is the local in its scope and the module path outside it" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "eval/deprecations.selka",
        \\public record Log:
        \\    items: int[]
        \\
        \\public const LIMIT: int = 7
        \\
        \\public func note(mut log: Log, n: int):
        \\    append(mut log.items, n)
        \\
    );
    try writeProjectFile(&temp, "state.selka",
        \\import eval.deprecations as eval_log
        \\
        \\public record Holder:
        \\    deprecations: eval_log.Log
        \\    name: str
        \\
    );
    try writeProjectFile(&temp, "main.selka",
        \\import eval.deprecations as eval_deprecations
        \\import state
        \\
        \\func count(eval: state.Holder) -> int:
        \\    return len(eval.deprecations.items)
        \\
        \\func limit_after_block() -> int:
        \\    if True:
        \\        const eval = 3
        \\        if eval == 3:
        \\            return eval
        \\    return eval.deprecations.LIMIT
        \\
        \\func main() -> int:
        \\    mut eval = state.Holder(deprecations=eval_deprecations.Log(items=[1, 2]), name="x")
        \\    append(mut eval.deprecations.items, 3)
        \\    eval_deprecations.note(mut eval.deprecations, 4)
        \\    const first = eval.deprecations.items[0]
        \\    return count(eval) + first + limit_after_block() + len(eval.name)
        \\
    );
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const checked = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry });
    defer testing.allocator.free(checked.stdout);
    defer testing.allocator.free(checked.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
    try testing.expect(std.mem.indexOf(u8, checked.stderr, "error[") == null);
    const cache = try privateTestCache(entry);
    defer testing.allocator.free(cache);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "run", entry, "--print-result", "--cache-dir", cache });
    try args.appendSlice(testing.allocator, &tools);
    const ran = try privateRun(testing.allocator, args.items);
    defer testing.allocator.free(ran.stdout);
    defer testing.allocator.free(ran.stderr);
    // count = 4 items, first = 1, limit_after_block = 3 (the block's local), name length = 1 (the field of the local).
    try testing.expectEqual(std.process.Child.Term{ .exited = 9 }, ran.term);
    try testing.expectEqualStrings("9\n", ran.stdout);
}

// A module-entry `run` prints the check phase's diagnostics exactly once: a
// clean project prints none, and the runner has nothing to repeat.
test "CLI run reports each frontend warning once" {
    const outcome = try runProjectFixture("run",
        \\
        \\
        \\func touch(mut values: int[]) -> Unit:
        \\    values[0] = 1
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    touch(mut values)
        \\    return 0
    , &.{});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expectEqual(@as(usize, 0), std.mem.count(u8, outcome.stderr, "warning["));
}

// spec-case: CONSTANT-2
test "CLI run takes --threads and refuses a count outside 1 to 256 (E1c)" {
    const program =
        \\import parallel
        \\
        \\func double(value: int) -> int:
        \\    return value * 2
        \\
        \\func main(out: Stream) -> int:
        \\    mut items: int[] = []
        \\    for i in range(1000):
        \\        append(mut items, i)
        \\    print(out, parallel.map(items, double)[999])
        \\    return 0
    ;
    const threaded = try runProjectFixture("run", program, &.{ "--threads", "3" });
    defer testing.allocator.free(threaded.stdout);
    defer testing.allocator.free(threaded.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, threaded.term);
    try testing.expect(std.mem.indexOf(u8, threaded.stdout, "1998\n") != null);
    const refused = try runProjectFixture("run", program, &.{ "--threads", "257" });
    defer testing.allocator.free(refused.stdout);
    defer testing.allocator.free(refused.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, refused.term);
}

const pool_probe =
    \\import parallel
    \\
    \\func pool_in_task(item: int) -> int:
    \\    if item < 0:
    \\        return 0
    \\    return parallel.threads()
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, f"outside {parallel.threads()}")
    \\    const inside = parallel.map([0, 1, 2, 3], pool_in_task)
    \\    print(out, f"task {inside[0]} {inside[3]}")
    \\    print(out, f"cpus {parallel.cpus()}")
    \\    return 0
;

/// The probe's output under `options`: the pool's size outside a task and in one, and the machine's CPU count.
fn expectPool(options: []const []const u8, pool: usize) !void {
    const cpus = try std.Thread.getCpuCount();
    const outcome = try runProjectFixture("run", pool_probe, options);
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    const wanted = try std.fmt.allocPrint(testing.allocator, "outside {d}\ntask {d} {d}\ncpus {d}\n", .{ pool, pool, pool, cpus });
    defer testing.allocator.free(wanted);
    try testing.expect(std.mem.indexOf(u8, outcome.stdout, wanted) != null);
}

test "parallel.threads answers the pool the tasks run on, outside a task and in one, and parallel.cpus the machine's count" {
    try expectPool(&.{ "--threads", "1" }, 1);
    try expectPool(&.{ "--threads", "3" }, 3);
    try expectPool(&.{}, @min(try std.Thread.getCpuCount(), 256));
}

test "parallel.threads in a test child is one, with or without --threads, because the step and frame budgets force one thread" {
    const program =
        \\import parallel
        \\
        \\public func test_pool_is_one() -> bool:
        \\    return parallel.threads() == 1 and parallel.cpus() >= 1
    ;
    for ([_][]const []const u8{ &.{}, &.{ "--threads", "3" } }) |options| {
        const outcome = try runProjectFixture("test", program, options);
        defer testing.allocator.free(outcome.stdout);
        defer testing.allocator.free(outcome.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
        try testing.expect(std.mem.indexOf(u8, outcome.stdout, "passed main::test_pool_is_one") != null);
    }
}

test "CLI managed constants import run build installed and invalidate warm caches" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\import constants
        \\func read[T]() -> str:
        \\    return constants.TEXT
        \\func main(out: Stream) -> int:
        \\    print(out, read[int]())
        \\    print(out, len(constants.DATA))
        \\    print(out, constants.DATA[1])
        \\    return 0
    });
    const original = "public const TEXT: str = \"hé🙂\"\npublic const DATA: bytes = b\"\\x00\\xff\"\n";
    try managedConstantModes(&temporary, original, "hé🙂\n2\n255\n");
    try managedConstantModes(&temporary, original, "hé🙂\n2\n255\n");
    // Same byte lengths, new contents: unchanged callers must observe the new IL.
    try managedConstantModes(&temporary, "public const TEXT: str = \"hà🙃\"\npublic const DATA: bytes = b\"\\x00\\xfe\"\n", "hà🙃\n2\n254\n");
}

// ACM-2, rule 6: a table constant reads the same under check, run, a build and an installed program, and a warm cache follows an edit
// of the constant's own line (a cached build that follows an edit of only the function that builds it is the open defect of
// `experiments/audit-work-20261111/CONSTTAB.md`, which scalar constants share).
test "CLI table constants agree across commands and follow an edit of the constant" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\import bytes
        \\import constants
        \\func main(out: Stream) -> int:
        \\    print(out, len(constants.TABLE))
        \\    print(out, bytes.read_u8(constants.TABLE, 3))
        \\    return 0
    });
    const build = "import buffers\n\npublic const TABLE: bytes = build({d})\n\n\nfunc build(count: int) -> bytes:\n    mut table = buffers.empty()\n    for index in range(count):\n        _ = buffers.append_byte(mut table, index * {d})\n    return bytes(table)\n";
    var first: [400]u8 = undefined;
    try managedConstantModes(&temporary, try std.fmt.bufPrint(&first, build, .{ 4, 10 }), "4\n30\n");
    var again: [400]u8 = undefined;
    try managedConstantModes(&temporary, try std.fmt.bufPrint(&again, build, .{ 4, 10 }), "4\n30\n");
    var edited: [400]u8 = undefined;
    try managedConstantModes(&temporary, try std.fmt.bufPrint(&edited, build, .{ 5, 11 }), "5\n33\n");
}

/// A table function whose octets come from `buffers`, and the `main` that reads them back.
const buffers_program =
    \\import buffers
    \\import bytes
    \\
    \\const TABLE: bytes = make()
    \\
    \\
    \\func make() -> bytes:
    \\    mut table = buffers.empty()
    \\    _ = buffers.append_byte(mut table, 7)
    \\    return bytes(table)
    \\
    \\
    \\func main() -> int:
    \\    return int(bytes.read_u8(TABLE, 0)) - 7
    \\
;

/// Run `argv` and require exit status `status`, and `stderr_part` in what it printed to stderr.
fn expectProcess(argv: []const []const u8, status: u8, stderr_part: []const u8) !void {
    const outcome = try privateRun(testing.allocator, argv);
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    if (!std.meta.eql(outcome.term, std.process.Child.Term{ .exited = status })) std.debug.print("{any}\n{s}{s}", .{ outcome.term, outcome.stdout, outcome.stderr });
    try testing.expectEqual(std.process.Child.Term{ .exited = status }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, stderr_part) != null);
}

// ACM-2, rule 2: the `buffers` operations of a table function are the standard library's, however the library is read: embedded in the
// compiler, or from source beside the entry. `scripts/check_programs.py` checks `src/stdlib/flate.selka` that way, from the repository root.
test "CLI table constants take the standard buffers module from source beside the entry" {
    try expectProcess(&.{ compilerPath(), "check", "src/stdlib/flate.selka", "--no-cache" }, 0, "");
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const library = try std.Io.Dir.cwd().readFileAlloc(testing.io, "src/stdlib/buffers.selka", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(library);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "buffers.selka", .data = library });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = buffers_program });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    try expectProcess(&.{ compilerPath(), "check", entry, "--local-stdlib", "--no-cache" }, 0, "");
    try expectProcess(&.{ compilerPath(), "run", entry, "--local-stdlib", "--no-cache", tools[0] }, 0, "");
}

// ACM-2, rule 2: a module of the user's own that is called `buffers` is an ordinary module. Only source whose bytes are the compiler's
// own `buffers.selka` is the standard library, so this `empty` is called as the function it is.
test "CLI a module called buffers that is not the standard library is an ordinary module" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "buffers.selka", .data = "public func empty() -> int:\n    return 7\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "import buffers\n\nconst N: int = buffers.empty() + 5\n\n\nfunc main() -> int:\n    return N - 12\n" });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    try expectProcess(&.{ compilerPath(), "run", entry, "--local-stdlib", "--no-cache", tools[0] }, 0, "");
}

// FR46: a record of borrows that a `mut` local holds and a `mut` argument writes once made the ownership check recurse until the
// compiler crashed (a signal, not status 1); it is refused at the field that needs `own` or `copy`, with the line that causes it.
test "CLI refuses a borrowed mut record written through a mut argument at its field, and does not crash" {
    try invoke("check", "record Token:\n    text: str\n    pos: int\n\nrecord Parser:\n    toks: Token[]\n    i: int\n\n" ++
        "func cur(p: Parser) -> Token from p:\n    return p.toks[p.i]\n\nfunc advance(mut p: Parser):\n    p.i += 1\n\n" ++
        "func first_pos() -> int:\n    const toks: Token[] = [Token(text=\"a\", pos=0), Token(text=\"b\", pos=2)]\n" ++
        "    mut p = Parser(toks=toks, i=0)\n    advance(mut p)\n    return cur(p).pos\n\n" ++
        "func main() -> int:\n    return first_pos()\n", 1, "", "field `toks` of `Parser` needs its own value; write `own toks` to give it, or `copy(toks)` to keep both");
}

// ACM-2, rule 4: `own` on a table constant is the marker error every other fresh value gets.
test "CLI refuses own on a table constant" {
    try invoke("check", "const TABLE: bytes = b\"\\x01\"\n\nfunc eat(own data: bytes) -> int:\n    return len(data)\n\nfunc main() -> int:\n    return eat(own TABLE)\n", 1, "", "E_OWN_MARKER");
}

// FR57 (friction W1-F-2 of the jq sample): a slice view that a later write to another field of its record invalidated is refused with
// the write's line and column, and the repairs that copy nothing come before the copy.
test "CLI names the write that invalidated a slice view and puts the copy last" {
    try invoke("check", "record Reader:\n    buf: bytes\n    pos: int\n\nfunc take_piece(mut r: Reader, end: int) -> str:\n" ++
        "    const piece = r.buf[r.pos:end]\n    r.pos = end + 1\n    return strings_decode(piece)\n\n" ++
        "func strings_decode(b: bytes) -> str:\n    return \"x\"\n\nfunc main(out: Stream) -> int:\n" ++
        "    mut r = Reader(buf=b\"abc\", pos=0)\n    print(out, take_piece(mut r, 2))\n    return 0\n", 1, "", "error[E_SLICE_ESCAPES]: " ++
        "`piece` is the slice `r.buf[r.pos:end]`, lent by the `mut` parameter `r`, and the write to `r.pos` at line 7, column 5 " ++
        "changes `r` as a whole, so `piece` cannot be read at line 8, column 27; use `piece` before line 7, keep its span " ++
        "(the start and length) and slice again where it is read, or wrap the initializer of `piece` in `copy(...)` to keep both");
}

// R3-RESORIGIN (friction F-3 of the load-test sample), RES-ORIGIN-2 (FR90): a function that returns a resource names the inputs its
// result can come from when it takes none or two or more, and says what to write. A `Clock`, an `Entropy`, an `Environment`, a
// `Process` and a provider of the other kind are not counted, and beside one `own` input of the result's type no provider is.
test "CLI names the inputs a resource-returning function took and what to write for a Clock, a Network and a resource" {
    try invoke("check", "import network\nimport time\n\nfunc on_event(own held: network.Poller, clock: Clock, net: Network) -> network.Poller:\n" ++
        "    _ = time.monotonic(clock)\n    _ = net.host(\"127.0.0.1:9000\")\n    return held\n\nfunc main(out: Stream) -> int:\n" ++
        "    print(out, \"x\")\n    return 0\n", 0, "", "");
    try invoke("check", "import network\n\nfunc two(net: Network, other: Network) -> network.Polling:\n    _ = other.host(\"127.0.0.1:9\")\n" ++
        "    return network.open_client_poller(net)\n\nfunc main(out: Stream) -> int:\n    print(out, \"x\")\n    return 0\n", 1, "", "error[E_RESOURCE_ORIGIN]: `two` returns a resource, so it takes exactly one input the result can come from (a `Network` or a " ++
        "resource), and it takes 2: `net: Network`, `other: Network`. Keep the one the result comes from and take the others out of " ++
        "the parameters: do the work that needs `net` and `other` together in a function that returns a `bool` or an `int`, which may " ++
        "take any number of inputs.");
    try invoke("check", "func pick(own first: File, own second: File) -> File:\n    return first\n\nfunc main(out: Stream) -> int:\n" ++
        "    print(out, \"x\")\n    return 0\n", 1, "", "error[E_RESOURCE_ORIGIN]: `pick` returns a resource, so it takes exactly one " ++
        "input the result can come from (a `Filesystem` or a resource), and it takes 2: `first: File`, `second: File`. Keep the one the " ++
        "result comes from and take the others out of the parameters: do the work that needs `first` and `second` together in a " ++
        "function that returns a `bool` or an `int`, which may take any number of inputs (take `first` and `second` as `mut`).");
    try invoke("check", "import network\nimport random\nimport process\n\nfunc again(env: Environment, entropy: Entropy, proc: Process, " ++
        "own held: network.Poller, out: Stream) -> network.Poller:\n    _ = env.get(\"HOME\")\n    _ = random.from_entropy(entropy)\n" ++
        "    _ = process.executable_path(proc)\n    print(out, \"x\")\n    return held\n\nfunc main(out: Stream) -> int:\n" ++
        "    print(out, \"x\")\n    return 0\n", 0, "", "");
    try invoke("check", "resource Ticket: filesystem\nresult Open:\n    ok: Ticket,\n    err: int\n\nfunc make() -> Open:\n    return Open.err(1)\n\n" ++
        "func main(out: Stream) -> int:\n    print(out, \"x\")\n    return 0\n", 1, "", "error[E_RESOURCE_ORIGIN]: `make` returns a " ++
        "resource, so it takes exactly one input the result can come from (a `Filesystem` or a resource), and it takes none: add as " ++
        "its one input the provider the resource is acquired from, or the resource it continues");
}

// R3-RESORIGIN: the shapes the refusal advises are accepted: the time read by the caller and passed as an `int`, and the dial in a function
// that returns a `bool` and takes the poller as `mut` beside the `Network`.
test "CLI accepts the shapes the resource-input refusal advises" {
    try invoke("check", "import network\nimport time\n\nfunc on_event(own held: network.Poller, now: int) -> network.Poller:\n    _ = now\n" ++
        "    return held\n\nfunc dial_slot(mut live: network.Poller, net: Network, mut outcome: network.Outcome) -> bool:\n" ++
        "    network.dial(mut live, net, mut outcome)\n    return outcome.code == network.OUTCOME_OK\n\n" ++
        "func drive(net: Network, clock: Clock) -> int:\n    match network.open_client_poller(net):\n        case ok(poller):\n" ++
        "            mut live = own poller\n            mut outcome = network.new_outcome()\n            const now = time.monotonic(clock)\n" ++
        "            if not dial_slot(mut live, net, mut outcome):\n                return 1\n            live = on_event(own live, now)\n" ++
        "            return 0\n        case err(code):\n            return code\n\nfunc main(out: Stream) -> int:\n" ++
        "    print(out, \"x\")\n    return 0\n", 0, "", "");
}

// spec-case: NEW-CORE-S5-HOST-1
test "CLI refuses a retired host declaration at check time and names extern func" {
    try invoke("check", host_program, 1, "", "error[E_HOST_RETIRED]");
    try invoke("run", host_program, 1, "", "declare the function `extern func`");
}
// spec: HOST-CAPABILITY-1
test "CLI threads a Host capability through an extern call and runs it natively" {
    const source =
        \\extern func labs(host: Host, x: i64) -> i64
        \\
        \\
        \\func main(host: Host) -> i64:
        \\    return labs(host, -7)
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
        \\extern func copysign(host: Host, x: float, y: float) -> float
        \\
        \\
        \\func nan_of(zero: float) -> float:
        \\    return zero / zero
        \\
        \\
        \\func main(host: Host, out: Stream) -> int:
        \\    mut nan = nan_of(0.0)
        \\    print(out, copysign(host, 1.0, nan), copysign(host, 1.0, -nan), copysign(host, 1.0, -2.0))
        \\    print(out, copysign(host, -nan, 1.0), copysign(host, nan, -1.0))
        \\    return 0
    ;
    try invokeOptions("run", source, &.{}, 0, "1.0 1.0 -1.0\nnan nan\n0\n", "");
}
// spec-case: HOST-CAPABILITY-1
test "CLI withholds Host under restrict and grants it with --allow-host" {
    const source =
        \\extern func labs(host: Host, x: i64) -> i64
        \\
        \\
        \\func main(host: Host) -> i64:
        \\    return labs(host, -7)
    ;
    try invokeOptions("run", source, &.{"--restrict"}, 2, "", "pass --allow-host, or drop --restrict to grant every capability; or, if the program can run without it, declare the parameter optional (`host: Host?`)\n");
    try invokeOptions("run", source, &.{ "--restrict", "--allow-host" }, 0, "7\n", "");
}
// spec-case: CAPABILITY-2
test "CLI takes the wildcard network grants a built program takes, and refuses a pattern around the star (FR19)" {
    const source =
        \\import network
        \\
        \\
        \\func main(net: Network) -> int:
        \\    with net.host("127.0.0.1:0") as scoped:
        \\        match network.open_poller(scoped):
        \\            case ok(poller):
        \\                _ = own poller
        \\                return 1
        \\            case err(code):
        \\                return 100 + code
    ;
    // `--allow-listen=*` lets the program listen anywhere; `--allow-endpoint=*` is a connect grant, so listening has no grant of its kind.
    try invokeOptions("run", source, &.{ "--restrict", "--allow-listen=*" }, 0, "1\n", "");
    try invokeOptions("run", source, &.{ "--restrict", "--allow-endpoint=*" }, 0, "101\n", "");
    try invokeOptions("run", source, &.{ "--restrict", "--allow-listen=127.0.0.1:*" }, 2, "", "usage: selka run");
    try invokeOptions("run", source, &.{ "--restrict", "--allow-endpoint=*:80" }, 2, "", "usage: selka run");
}
// spec-case: NEW-CORE-S5-ARENA-2
test "CLI checks and runs the migrated managed value assignment" {
    const source =
        \\func main() -> int:
        \\    mut keeper: int[] = []
        \\    keeper = [1, 2]
        \\    return len(keeper)
    ;
    try invoke("check", source, 0, "", "");
    try invoke("run", source, 0, "2\n", "");
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
    if (stderr_part.len == 0) try expectQuietStderr(command, .{ .status = expected_status, .options = options }, outcome.stderr) else try testing.expect(std.mem.indexOf(u8, outcome.stderr, stderr_part) != null);
}
/// The command a fixture run was given, for deciding what its quiet stderr may hold.
const QuietRun = struct { status: u8, options: []const []const u8 };
/// A clean fixture run leaves nothing on stderr, except that a successful `check` writes its one
/// `check: ok (N modules, M cached)` line (CHECK-SUCCESS-LINE-1); `--diagnostics=json` keeps it silent.
fn expectQuietStderr(command: []const u8, run: QuietRun, stderr: []const u8) !void {
    var json = false;
    for (run.options) |option| json = json or std.mem.eql(u8, option, "--diagnostics=json");
    if (!std.mem.eql(u8, command, "check") or run.status != 0 or json) return testing.expectEqualStrings("", stderr);
    try check_line.expectPassed(stderr);
}
fn runFixture(command: []const u8, text: []const u8, options: []const []const u8) !std.process.RunResult {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data = text });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.selka", testing.allocator);
    defer testing.allocator.free(path);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compilerPath(), command, path });
    // These fixtures assert the entry point's int result, which `run` now reports only on request.
    if (std.mem.startsWith(u8, command, "run")) try args.appendSlice(testing.allocator, &(.{"--print-result"} ++ tools));
    const cache = try privateTestCache(path);
    defer testing.allocator.free(cache);
    if (std.mem.eql(u8, command, "test")) try args.appendSlice(testing.allocator, &.{ "--cache-dir", cache });
    try args.appendSlice(testing.allocator, options);
    return privateRun(testing.allocator, args.items);
}

/// A receipt cache beside a fixture, removed with its temporary directory. Receipt
/// keys name the entry relative to its root (RECEIPT-PATHS-1), so a fixture tested
/// through the shared default cache would hit an earlier run's receipt and report
/// `cached` where its test asserts `passed`.
fn privateTestCache(entry: []const u8) ![]const u8 {
    return std.fs.path.join(testing.allocator, &.{ std.fs.path.dirname(entry).?, "test-cache" });
}

/// `runFixture` for a module-syntax entry. The public clock/random read surface
/// lives in the embedded `time`/`random` modules, so a capability program can
/// reach it only as a project entry whose declared module matches its file stem;
/// this writes `main.selka` so `check`/`run` auto-route to the project loader.
fn runProjectFixture(command: []const u8, text: []const u8, options: []const []const u8) !std.process.RunResult {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = text });
    const path = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(path);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compilerPath(), command, path });
    if (std.mem.startsWith(u8, command, "run")) try args.appendSlice(testing.allocator, &(.{"--print-result"} ++ tools));
    const cache = try privateTestCache(path);
    defer testing.allocator.free(cache);
    if (std.mem.eql(u8, command, "test")) try args.appendSlice(testing.allocator, &.{ "--cache-dir", cache });
    try args.appendSlice(testing.allocator, options);
    return privateRun(testing.allocator, args.items);
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
    if (stderr_part.len == 0) try expectQuietStderr(command, .{ .status = expected_status, .options = options }, outcome.stderr) else try testing.expect(std.mem.indexOf(u8, outcome.stderr, stderr_part) != null);
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
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "check", path, "--report" });
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
    const version_dir = try std.fs.path.join(allocator, &.{ cache_base, "semantic", semantic_cache_version });
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
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.selka" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    const seed =
        \\func helper(n: i64) -> i64:
        \\    return n + 1
        \\
        \\
        \\func keep(n: i64) -> i64:
        \\    mut unused = 3
        \\    return n + 1
        \\
        \\
        \\func main() -> i64:
        \\    return keep(helper(40))
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = seed });
    const first = try c2RunCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    const seeded = try c2Counts(first.stderr);
    try testing.expectEqual(@as(usize, 3), seeded.performed);
    try testing.expectEqual(@as(usize, 0), seeded.reused);

    const edited =
        \\func helper(n: i64) -> i64:
        \\    return n + 2
        \\
        \\
        \\type Marker = i64
        \\
        \\
        \\func keep(n: i64) -> i64:
        \\    mut unused = 3
        \\    return n + 1
        \\
        \\
        \\func main() -> i64:
        \\    return keep(helper(40))
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = edited });
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
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.selka" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    const source =
        \\func main() -> i64:
        \\    return 42
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
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
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.selka" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    const source =
        \\func helper(n: i64) -> i64:
        \\    return n + 1
        \\func main() -> i64:
        \\    return helper(41)
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
    const argv = [_][]const u8{ compilerPath(), "check", entry, cache_argument };
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
        if (module > 0) try out.print("import m{d}\n", .{module - 1});
        try out.print("\n\npublic record Acc{d}:\n    total: int\n    count: int\n", .{module});
        var function: usize = 0;
        while (function < functions) : (function += 1) {
            const offset = if (module == 1 and function == 0) constant else module;
            try out.print("\n\npublic func f{d}_{d}(n: int) -> int:\n    mut xs: int[] = []\n    for k in range(n):\n        append(mut xs, k * {d} + {d})\n", .{ module, function, function + 1, offset });
            if (module == 0 and function == 0) try out.writeAll("    const spare = 1\n");
            try out.print("    mut acc = Acc{d}(total=0, count=0)\n    for x in xs:\n        acc = Acc{d}(total=acc.total + x, count=acc.count + 1)\n", .{ module, module });
            if (module > 0) try out.print("    return acc.total + m{d}.f{d}_{d}(n - 1)\n", .{ module - 1, module - 1, function }) else try out.writeAll("    return acc.total\n");
        }
        const name = try std.fmt.allocPrint(testing.allocator, "m{d}.selka", .{module});
        defer testing.allocator.free(name);
        try directory.writeFile(testing.io, .{ .sub_path = name, .data = text.written() });
    }
    var main_text: std.Io.Writer.Allocating = .init(testing.allocator);
    defer main_text.deinit();
    try main_text.writer.print("import m{d}\n\n\nfunc main() -> int:\n    mut total = 0\n", .{modules - 1});
    var function: usize = 0;
    while (function < functions) : (function += 1) try main_text.writer.print("    total += m{d}.f{d}_{d}(5)\n", .{ modules - 1, modules - 1, function });
    try main_text.writer.writeAll("    return total - total\n");
    try directory.writeFile(testing.io, .{ .sub_path = "main.selka", .data = main_text.written() });
}

/// `stderr` without the JSON report lines `--report` adds.
fn diagnosticLines(allocator: std.mem.Allocator, stderr: []const u8) ![]u8 {
    var kept: std.Io.Writer.Allocating = .init(allocator);
    defer kept.deinit();
    var lines = std.mem.splitScalar(u8, stderr, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "{") or std.mem.startsWith(u8, line, "check: ok")) continue;
        try kept.writer.print("{s}\n", .{line});
    }
    return kept.toOwnedSlice();
}

/// `check <entry> --report` with the given cache argument under `environment`.
fn checkReportWith(environment: *const std.process.Environ.Map, entry: []const u8, cache_argument: []const u8) !std.process.RunResult {
    return std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check", entry, "--report", cache_argument }, .environ_map = environment });
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
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.selka" });
    defer testing.allocator.free(entry);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{directory});
    defer testing.allocator.free(cache_argument);
    // The counts are of the work this process does: a shared compiler store could serve the cold run's bodies from an earlier test.
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    defer environment.deinit();
    try environment.put("SELKA_SEMANTIC_BUDGET", "65536");
    // A Debug compiler re-checks one proven function in 64, chosen by its digest, to verify the proof; the count below is of the work
    // the edit causes, so the sampling is off.
    try environment.put("SELKA_ENGINE_VERIFY", "0");
    // The warning that has to survive is in `m0`, not the entry, so a text check would only count it in a summary line.
    try environment.put("SELKA_WARNINGS", "all");
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

    const cold = try checkReportWith(&environment, entry, "--no-cache");
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

// spec-case: G2O-1
test "G2o a project check works in the build's work directory and leaves the old front-end directories alone" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = "public func value() -> int:\n    return 7\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "import helper\n\nfunc main() -> int:\n    return helper.value()\n" });
    const first = try runInDirectory(temporary.dir, &.{ compilerPath(), "check", "main.selka" });
    defer freeRun(first);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    try testing.expect(std.mem.indexOf(u8, first.stderr, "check: ok (2 modules, ") != null);
    // The work directory is the build's, so a check and a build of one program share their records.
    _ = try temporary.dir.statFile(testing.io, ".selka-cache/core/frontend", .{});
    try testing.expectError(error.FileNotFound, temporary.dir.statFile(testing.io, ".selka-cache/frontend", .{}));
    // An unchanged project replays its stored verdict, and a cache directory named on the command line moves the whole work directory.
    const again = try runInDirectory(temporary.dir, &.{ compilerPath(), "check", "main.selka" });
    defer freeRun(again);
    try testing.expect(std.mem.indexOf(u8, again.stderr, "check: ok (2 modules, 2 cached)") != null);
    const moved = try runInDirectory(temporary.dir, &.{ compilerPath(), "check", "main.selka", "--cache-dir=elsewhere" });
    defer freeRun(moved);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, moved.term);
    _ = try temporary.dir.statFile(testing.io, "elsewhere/frontend", .{});
}

// spec-case: G2O-1
test "G2o checkOnSession refuses a project whose index, check or ownership validation fails, with the status and text of the old driver" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = "public func value( -> int:\n    return 7\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "import helper\n\nfunc main() -> int:\n    return helper.value()\n" });
    // A syntax error in an imported module stops at the index step.
    const indexed = try runInDirectory(temporary.dir, &.{ compilerPath(), "check", "main.selka", "--no-cache" });
    defer freeRun(indexed);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, indexed.term);
    try testing.expect(std.mem.indexOf(u8, indexed.stderr, "helper.selka:1:20: error[E_SYNTAX]") != null);
    // A type error stops at the check, and the diagnostic comes out once.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = "public func value() -> int:\n    return \"seven\"\n" });
    const checked = try runInDirectory(temporary.dir, &.{ compilerPath(), "check", "main.selka" });
    defer freeRun(checked);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, checked.term);
    try testing.expect(std.mem.indexOf(u8, checked.stderr, "error[E_TYPE]") != null);
    try testing.expectEqual(std.mem.indexOf(u8, checked.stderr, "error[E_TYPE]"), std.mem.lastIndexOf(u8, checked.stderr, "error[E_TYPE]"));
    // An ownership error stops at the validation the session runs after the check; the diagnostics come as JSON lines on request.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = "public func value() -> int:\n    mut a: int[] = [1, 2]\n    mut b: int[] = a\n    append(mut b, 3)\n    return len(a)\n" });
    const owned = try runInDirectory(temporary.dir, &.{ compilerPath(), "check", "main.selka", "--diagnostics=json" });
    defer freeRun(owned);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, owned.term);
    try testing.expect(std.mem.indexOf(u8, owned.stderr, "\"kind\":\"diagnostic\"") != null);
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
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.selka" });
    defer testing.allocator.free(entry);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{directory});
    defer testing.allocator.free(cache_argument);
    const shapes = "public record Inner:\n    x: int\npublic record Outer:\n    items: Inner[]\npublic func make() -> Outer:\n    mut items: Inner[] = []\n    append(mut items, Inner(x=1))\n    return Outer(items=own items)\n";
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "shapes.selka", .data = shapes });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "user.selka", .data = "import shapes\npublic func first(o: shapes.Outer) -> int:\n    mut v = o.items[0]\n    return v.x\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "import shapes\nimport user\nfunc main() -> int:\n    return user.first(shapes.make())\n" });
    const seed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check", entry, cache_argument } });
    defer testing.allocator.free(seed.stdout);
    defer testing.allocator.free(seed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, seed.term);
    const renamed = "public record Inner:\n    y: int\npublic record Outer:\n    items: Inner[]\npublic func make() -> Outer:\n    mut items: Inner[] = []\n    append(mut items, Inner(y=1))\n    return Outer(items=own items)\n";
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "shapes.selka", .data = renamed });
    const cached = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check", entry, cache_argument } });
    defer testing.allocator.free(cached.stdout);
    defer testing.allocator.free(cached.stderr);
    const cold = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check", entry, "--no-cache" } });
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, cold.term);
    try testing.expect(std.mem.indexOf(u8, cold.stderr, "user.selka:4:14: error[E_UNKNOWN_FIELD]") != null);
    try testing.expectEqual(cold.term, cached.term);
    try testing.expectEqualStrings(cold.stderr, cached.stderr);
}

/// Run the compiler with `argv` after its path; the caller frees both outputs.
fn runInterfaces(argv: []const []const u8) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.append(testing.allocator, compilerPath());
    try args.appendSlice(testing.allocator, argv);
    return std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
}

// spec-case: MODULE-INTERFACE-3
test "a module checks against emitted interfaces after its imports' sources are gone" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(directory);
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.selka" });
    defer testing.allocator.free(entry);
    const out = try std.fmt.allocPrint(testing.allocator, "--out={s}/interfaces", .{directory});
    defer testing.allocator.free(out);
    const from = try std.fmt.allocPrint(testing.allocator, "--from={s}/interfaces", .{directory});
    defer testing.allocator.free(from);
    const artifact = try std.fs.path.join(testing.allocator, &.{ directory, "interfaces", "lib.selkai" });
    defer testing.allocator.free(artifact);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "shapes.selka", .data = "public record Inner:\n    x: int\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib.selka", .data = "import shapes\npublic func firsts(items: shapes.Inner[]) -> int:\n    mut total = 0\n    for item in items:\n        total += item.x\n    return total\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "import shapes\nimport lib\nfunc main() -> int:\n    return lib.firsts([shapes.Inner(x=2)])\n" });
    const emitted = try runInterfaces(&.{ "interfaces", "emit", entry, out });
    defer freeRun(emitted);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, emitted.term);
    try testing.expect(std.mem.indexOf(u8, emitted.stdout, "\"version\":\"module-interface-index-v1\"") != null);
    const shown = try runInterfaces(&.{ "interfaces", "show", artifact });
    defer freeRun(shown);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, shown.term);
    try testing.expect(std.mem.indexOf(u8, shown.stdout, "public func firsts(items: shapes.Inner[]) -> int:\n    pass") != null);
    const verified = try runInterfaces(&.{ "interfaces", "oracle", entry });
    defer freeRun(verified);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, verified.term);
    try testing.expect(std.mem.indexOf(u8, verified.stdout, "\"equal\":true") != null);
    // Only the interfaces remain for `lib` and `shapes`: the module's check reads them alone.
    try temporary.dir.deleteFile(testing.io, "lib.selka");
    try temporary.dir.deleteFile(testing.io, "shapes.selka");
    const alone = try runInterfaces(&.{ "interfaces", "check", entry, "--module=main", from });
    defer freeRun(alone);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, alone.term);
    try testing.expect(std.mem.indexOf(u8, alone.stdout, "\"stood_in\":1,\"declared_only\":true") != null);
    // A call the interface's signature rejects is reported against the module's own source.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "import shapes\nimport lib\nfunc main() -> int:\n    return lib.firsts(3)\n" });
    const rejected = try runInterfaces(&.{ "interfaces", "check", entry, "--module=main", from });
    defer freeRun(rejected);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, rejected.term);
    try testing.expect(std.mem.indexOf(u8, rejected.stdout, "main:") != null);
}

// spec: MODULE-INTERFACE-4
test "the interfaces command is listed in help and answers a bad action with its usage" {
    const help = try runInterfaces(&.{"--help"});
    defer freeRun(help);
    try testing.expect(std.mem.indexOf(u8, help.stdout, "selka interfaces emit|check|oracle <entry.selka> | show <module.selkai>") != null);
    const usage = try runInterfaces(&.{ "interfaces", "bogus", "main.selka" });
    defer freeRun(usage);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, usage.term);
    try testing.expect(std.mem.startsWith(u8, usage.stderr, "usage: selka interfaces emit <entry.selka>"));
    const missing = try runInterfaces(&.{"interfaces"});
    defer freeRun(missing);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, missing.term);
}

/// A build of the project whose entry is `main.selka` in `directory`: into
/// `output`, over the cache `cache` (both under `directory`), with `--report`,
/// and `extra` after the build options.
fn projectBuild(allocator: std.mem.Allocator, directory: []const u8, output: []const u8, cache: []const u8, extra: []const []const u8) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    try args.appendSlice(allocator, &.{
        "build",
        try std.fs.path.join(allocator, &.{ directory, "main.selka" }),
        "-o",
        try std.fs.path.join(allocator, &.{ directory, output }),
        try std.fmt.allocPrint(allocator, "--cache-dir={s}/{s}", .{ directory, cache }),
        "--report",
    });
    try args.appendSlice(allocator, &tools);
    try args.appendSlice(allocator, extra);
    const result = try runInterfaces(args.items);
    // The caller's arena owns what the run printed.
    defer freeRun(result);
    return .{ .term = result.term, .stdout = try allocator.dupe(u8, result.stdout), .stderr = try allocator.dupe(u8, result.stderr) };
}

const schedule_generic =
    \\public func largest[T: integer](values: T[]) -> T:
    \\    mut best = values[0]
    \\    for value in values:
    \\        if value > best:
    \\            best = value
    \\    return best
    \\public func grow(values: int[]) -> int[]:
    \\    mut out: int[] = []
    \\    for value in values:
    \\        append(mut out, value + largest(values))
    \\    return out
    \\
;

const schedule_main =
    \\import util
    \\func rank_mod_five(value: int) -> int:
    \\    return value % 5
    \\func main(out: Stream) -> int:
    \\    mut values = util.grow([3, 9, 4])
    \\    mut ranked = sorted(values, key=rank_mod_five)
    \\    print(out, ranked)
    \\    return util.largest(values) + values[1]
    \\
;

// spec: BUILD-REPRODUCIBLE-1
test "a Debug build's executable does not depend on where its cache is" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "util.selka", .data = schedule_generic });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = schedule_main });
    const one = try projectBuild(a, directory, "one", "first", &.{"--whole-program"});
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, one.term);
    const two = try projectBuild(a, directory, "two", "second/nested", &.{"--whole-program"});
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, two.term);
    try testing.expectEqualSlices(u8, try temporary.dir.readFileAlloc(testing.io, "one", a, .limited(1 << 30)), try temporary.dir.readFileAlloc(testing.io, "two", a, .limited(1 << 30)));
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
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "check", entry, "--report" });
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
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.selka" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    const base_template =
        \\func size[T: integer](value: T) -> i64:
        \\    _ = value
        \\    return 7
        \\
        \\
        \\
    ;
    const edited_template =
        \\func size[T: integer](value: T) -> i64:
        \\    _ = value
        \\    return 8
        \\
        \\
        \\
    ;
    const base_helper =
        \\func helper(n: i64) -> i64:
        \\    return n + 1
        \\
        \\
        \\
    ;
    const edited_helper =
        \\func helper(n: i64) -> i64:
        \\    return n + 2
        \\
        \\
        \\
    ;
    const main_fn =
        \\func main() -> i64:
        \\    return size[u8](1u8) + helper(0)
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = base_template ++ base_helper ++ main_fn });
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = base_template ++ edited_helper ++ main_fn });
    const unrelated = try symbolicCheck(entry, cache_argument, false);
    defer testing.allocator.free(unrelated.stdout);
    defer testing.allocator.free(unrelated.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, unrelated.term);
    try testing.expectEqual(@as(usize, 0), (try symbolicCounts(unrelated.stderr)).performed);
    try testing.expectEqual(@as(usize, 1), (try symbolicCounts(unrelated.stderr)).reused);
    // Editing the template body invalidates its retained direct result.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = edited_template ++ edited_helper ++ main_fn });
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
        \\func main(rng: Entropy) -> int:
        \\    _ = rng
        \\    return 0
    ;
    const message = "selka: --restrict is active and this command line did not grant a capability the entry point requests; pass --allow-random, or drop --restrict to grant every capability; or, if the program can run without it, declare the parameter optional (`rng: Entropy?`)\n";
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "cap.selka", .data = program });
    const path = try temp.dir.realPathFileAlloc(testing.io, "cap.selka", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "cap-bin" });
    defer testing.allocator.free(output);

    var run_argv: std.ArrayList([]const u8) = .empty;
    defer run_argv.deinit(testing.allocator);
    try run_argv.appendSlice(testing.allocator, &.{ compilerPath(), "run", path, "--restrict" });
    try run_argv.appendSlice(testing.allocator, &tools);
    const run = try std.process.run(testing.allocator, testing.io, .{ .argv = run_argv.items });
    defer testing.allocator.free(run.stdout);
    defer testing.allocator.free(run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, run.term);
    try testing.expectEqualStrings("", run.stdout);
    try testing.expectEqualStrings(message, run.stderr);

    var build_argv: std.ArrayList([]const u8) = .empty;
    defer build_argv.deinit(testing.allocator);
    try build_argv.appendSlice(testing.allocator, &.{ compilerPath(), "build", path, "--run", "--restrict" });
    try build_argv.appendSlice(testing.allocator, &tools);
    const build = try std.process.run(testing.allocator, testing.io, .{ .argv = build_argv.items });
    defer testing.allocator.free(build.stdout);
    defer testing.allocator.free(build.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, build.term);
    try testing.expectEqualStrings("", build.stdout);
    try testing.expectEqualStrings(message, build.stderr);

    var link_argv: std.ArrayList([]const u8) = .empty;
    defer link_argv.deinit(testing.allocator);
    try link_argv.appendSlice(testing.allocator, &.{ compilerPath(), "build", path, "-o", output });
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

const optional_entry =
    \\func held(present: bool) -> str:
    \\    if present:
    \\        return "S"
    \\    return "N"
    \\
    \\
    \\func reaches(fs: Filesystem?) -> str:
    \\    match fs:
    \\        case Some(files):
    \\            return held(not files.exists("absent.txt"))
    \\        case None:
    \\            return "-"
    \\
    \\
    \\func main(clock: Clock?, rng: Entropy?, fs: Filesystem?, net: Network?, env: Environment?, proc: Process?, host: Host?, out: Stream) -> int:
    \\    print(out, held(clock is Some), held(rng is Some), held(fs is Some), held(net is Some), held(env is Some), held(proc is Some), held(host is Some), reaches(fs))
    \\    return 0
;

// CAP-OPT: an entry parameter written `T?` is `None` when a restricted command line grants nothing of its capability.
test "an entry capability written T? is Some when the command line grants it and None when --restrict does not" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const read = try std.fmt.allocPrint(testing.allocator, "--allow-read={s}", .{root});
    defer testing.allocator.free(read);
    const write = try std.fmt.allocPrint(testing.allocator, "--allow-write={s}", .{root});
    defer testing.allocator.free(write);
    // Without --restrict every capability is granted; with it, nothing is until a flag names it.
    try invokeOptions("run", optional_entry, &.{}, 0, "S S S S S S S S\n0\n", "");
    try invokeOptions("run", optional_entry, &.{"--restrict"}, 0, "N N N N N N N -\n0\n", "");
    const every = [_][]const u8{ "--restrict", "--allow-clock", "--allow-random", read, "--allow-endpoint=127.0.0.1:1", "--allow-env", "--allow-process", "--allow-host" };
    try invokeOptions("run", optional_entry, &every, 0, "S S S S S S S S\n0\n", "");
    // A Filesystem counts any read or write grant; a Network counts a listen grant as well as a connect grant.
    try invokeOptions("run", optional_entry, &.{ "--restrict", write }, 0, "N N S N N N N S\n0\n", "");
    try invokeOptions("run", optional_entry, &.{ "--restrict", "--allow-listen=127.0.0.1:0" }, 0, "N N N S N N N -\n0\n", "");
    // The plain form keeps its refusal to start, word for word.
    try invokeOptions("run", "func main(fs: Filesystem, out: Stream) -> int:\n    print(out, fs.exists(\"x\"))\n    return 0\n", &.{"--restrict"}, 2, "", "selka: --restrict is active and this command line did not grant a capability the entry point requests; pass --allow-read=DIR or --allow-write=DIR, or drop --restrict to grant every capability; or, if the program can run without it, declare the parameter optional (`fs: Filesystem?`)\n");
    // Each family of the refusal names its own optional form (a Network and an Environment here, the others in their own tests).
    const tail = "or drop --restrict to grant every capability; or, if the program can run without it, declare the parameter optional (`";
    try invokeOptions("run", "func main(_net: Network, out: Stream) -> int:\n    print(out, \"x\")\n    return 0\n", &.{"--restrict"}, 2, "", "pass --allow-endpoint=IP:PORT or --allow-listen=IP:PORT, " ++ tail ++ "net: Network?`)\n");
    try invokeOptions("run", "func main(_env: Environment, out: Stream) -> int:\n    print(out, \"x\")\n    return 0\n", &.{"--restrict"}, 2, "", "pass --allow-env, " ++ tail ++ "env: Environment?`)\n");
    // A capability that needs no grant is never None, so its `T?` is refused.
    try invokeOptions("check", "func main(out: Stream?) -> int:\n    _ = out\n    return 0\n", &.{}, 1, "", "error[E_MAIN]: an entry `Stream`, `Input`, `Stop` or `Registers` needs no grant");
    try invokeOptions("check", "func main(fs: Filesystem, spare: Filesystem?) -> int:\n    _ = fs\n    _ = spare\n    return 0\n", &.{}, 1, "", "entry requests at most one value parameter of each capability kind");
}

// STOPWATCH: a Clock needs no grant; its wall time does.
test "a restricted run reads monotonic time and sleeps without --allow-clock, and its wall-clock read fails until granted" {
    const program =
        \\import time
        \\
        \\
        \\func main(clock: Clock, out: Stream) -> int:
        \\    const start = time.monotonic(clock)
        \\    time.sleep(clock, 1000000)
        \\    print(out, "slept", time.monotonic(clock) - start >= 1000000)
        \\    match time.now(clock):
        \\        case Ok(instant):
        \\            print(out, "wall", instant.unix_nanoseconds > 0)
        \\        case Err(message):
        \\            print(out, message)
        \\    return 0
    ;
    try invokeOptions("run", program, &.{"--restrict"}, 0, "slept True\nthe wall clock is not granted: pass `--allow-clock`\n0\n", "");
    try invokeOptions("run", program, &.{ "--restrict", "--allow-clock" }, 0, "slept True\nwall True\n0\n", "");
    try invokeOptions("run", program, &.{}, 0, "slept True\nwall True\n0\n", "");
}

test "a Process entry parameter needs --allow-process under --restrict, for run and an installed executable" {
    const program =
        \\func main(proc: Process) -> int:
        \\    _ = proc
        \\    return 0
    ;
    const message = "selka: --restrict is active and this command line did not grant a capability the entry point requests; pass --allow-process, or drop --restrict to grant every capability; or, if the program can run without it, declare the parameter optional (`proc: Process?`)\n";
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "proc.selka", .data = program });
    const path = try temp.dir.realPathFileAlloc(testing.io, "proc.selka", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "proc-bin" });
    defer testing.allocator.free(output);

    const withheld = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "run", path, "--restrict", tools[0] } });
    defer testing.allocator.free(withheld.stdout);
    defer testing.allocator.free(withheld.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, withheld.term);
    try testing.expectEqualStrings(message, withheld.stderr);

    const granted = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "run", path, "--restrict", "--allow-process", tools[0] } });
    defer testing.allocator.free(granted.stdout);
    defer testing.allocator.free(granted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, granted.term);

    const link = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "build", path, "-o", output, tools[0] } });
    defer testing.allocator.free(link.stdout);
    defer testing.allocator.free(link.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, link.term);
    var restricted = try runtimeOptions("--restrict");
    defer restricted.deinit();
    const refused = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{output}, .environ_map = &restricted });
    defer testing.allocator.free(refused.stdout);
    defer testing.allocator.free(refused.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, refused.term);
    try testing.expectEqualStrings(message, refused.stderr);
    var allowed = try runtimeOptions("--restrict --allow-process");
    defer allowed.deinit();
    const ran = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{output}, .environ_map = &allowed });
    defer testing.allocator.free(ran.stdout);
    defer testing.allocator.free(ran.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, ran.term);
    var repeated = try runtimeOptions("--allow-process --allow-process");
    defer repeated.deinit();
    const bad = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{output}, .environ_map = &repeated });
    defer testing.allocator.free(bad.stdout);
    defer testing.allocator.free(bad.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, bad.term);
    try testing.expectEqualStrings("selka: the option --allow-process is not a usable capability grant\n", bad.stderr);
}

/// Build `program` with `-o` in `temp` and return the executable's path.
fn buildExecutable(temp: *testing.TmpDir, program: []const u8) ![]const u8 {
    try temp.dir.writeFile(testing.io, .{ .sub_path = "argv.selka", .data = program });
    const path = try temp.dir.realPathFileAlloc(testing.io, "argv.selka", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "argv-bin" });
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    try expectConstantProcess(&.{ compilerPath(), "build", path, "-o", output, "--cache-dir", cache, tools[0] }, "");
    return output;
}

/// Run a built executable with `argv` under `SELKA_OPTIONS=options`.
fn runExecutable(argv: []const []const u8, options: []const u8) !std.process.RunResult {
    var environment = try runtimeOptions(options);
    defer environment.deinit();
    return std.process.run(testing.allocator, testing.io, .{ .argv = argv, .environ_map = &environment });
}

const argv_echo =
    \\func main(args: str[], out: Stream) -> int:
    \\    print(out, "count", len(args))
    \\    for value in args:
    \\        print(out, "[" + value + "]")
    \\    return 0
;

// spec: NATIVE-ARGV-1
test "a built executable hands main every argument and reads runtime options from SELKA_OPTIONS" {
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
    const optioned = try runExecutable(&.{ output, "--" }, "--timeout=600 \"--print-result\"");
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
    try testing.expectEqualStrings("selka: SELKA_OPTIONS names --engine=vm, which is not a runtime option\n", unknown.stderr);
    const unterminated = try runExecutable(&.{output}, "\"--print-result");
    defer testing.allocator.free(unterminated.stdout);
    defer testing.allocator.free(unterminated.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, unterminated.term);
    try testing.expectEqualStrings("selka: SELKA_OPTIONS has an unterminated quote\n", unterminated.stderr);
}

// spec-case: NATIVE-ARGV-1
test "run replaces an inherited SELKA_OPTIONS with its own command line" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "argv.selka", .data = argv_echo });
    const path = try temp.dir.realPathFileAlloc(testing.io, "argv.selka", testing.allocator);
    defer testing.allocator.free(path);
    const inherited = try runExecutable(&.{ compilerPath(), "run", path, tools[0], "--", "--gc-stress" }, "--print-result");
    defer testing.allocator.free(inherited.stdout);
    defer testing.allocator.free(inherited.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, inherited.term);
    try testing.expectEqualStrings("count 1\n[--gc-stress]\n", inherited.stdout);
    try testing.expectEqualStrings("", inherited.stderr);
}

// spec: RESULT-MAIN-1
test "CLI maps Result main ok and err to status codes and one diagnostic" {
    const ok =
        \\func main(args: str[]) -> Result[int, str]:
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
    // ERROR-TRACE-2: the message line is followed by the error return trace.
    try testing.expect(std.mem.startsWith(u8, rejected.stderr, "error: missing name\n  "));
    try testing.expect(std.mem.endsWith(u8, rejected.stderr, "input.selka:3:16  main  Err(...) created\n"));

    const wrapped =
        \\func main() -> Result[int, str]:
        \\    return Ok(300)
    ;
    const status = try runFixture("run", wrapped, &.{});
    defer testing.allocator.free(status.stdout);
    defer testing.allocator.free(status.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 44 }, status.term);
    try testing.expectEqualStrings("300\n", status.stdout);
    try testing.expectEqualStrings("", status.stderr);
}

/// A program whose `Err` is created two calls deep, converted into the entry's
/// error union on the way out and reported by `main`.
const error_trace_program =
    \\enum AppError:
    \\    Config(value: str)
    \\    Usage(value: int)
    \\
    \\func parse_port(text: str) -> int fails str:
    \\    if strings.char_count(text) == 0:
    \\        fail "empty port"
    \\    return strings.char_count(text)
    \\
    \\func read_config(text: str) -> int fails str:
    \\    mut port = try parse_port(text)
    \\    return port + 1
    \\
    \\func load(text: str) -> int fails AppError:
    \\    const port = try read_config(text)
    \\    return port
    \\
    \\func main() -> Result[int, AppError]:
    \\    mut port = try load("")
    \\    return Ok(port)
;
/// The report `error_trace_program` writes, `{path}` standing for its entry.
const error_trace_report =
    \\error: AppError.Config(value='empty port')
    \\  {path}:7:9    parse_port   Err(...) created
    \\  {path}:11:16  read_config  try propagated
    \\  {path}:15:18  load         try converted to AppError.Config
    \\  {path}:19:16  main         try propagated
    \\
;

// spec-case: ERROR-TRACE-2
// spec-case: ERROR-TRACE-1
test "CLI reports main's Err and its error return trace the same from run, Debug, ReleaseFast and --release builds" {
    const a = testing.allocator;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "traced.selka", .data = error_trace_program });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "traced.selka", a);
    defer a.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const cache_argument = try std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{directory});
    defer a.free(cache_argument);
    const wanted = try std.mem.replaceOwned(u8, a, error_trace_report, "{path}", entry);
    defer a.free(wanted);
    const debug = try std.fmt.allocPrint(a, "{s}/traced-debug", .{directory});
    defer a.free(debug);
    const fast = try std.fmt.allocPrint(a, "{s}/traced-fast", .{directory});
    defer a.free(fast);
    const release = try std.fmt.allocPrint(a, "{s}/traced-release", .{directory});
    defer a.free(release);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", debug, cache_argument, tools[0] }, "");
    const ran = try std.process.run(a, testing.io, .{ .argv = &.{ compilerPath(), "run", entry, cache_argument, tools[0] } });
    defer a.free(ran.stdout);
    defer a.free(ran.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, ran.term);
    try testing.expectEqualStrings(wanted, ran.stderr);
    try expectErrorReport(debug, wanted);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", fast, "--mode", "ReleaseFast", cache_argument, tools[0] }, "");
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", release, "--release", cache_argument, tools[0] }, "");
    try expectErrorReport(fast, wanted);
    try expectErrorReport(release, wanted);
}
/// Run a built program whose `main` fails with a non-`int` error: it exits 1,
/// prints nothing on stdout and writes exactly `wanted` on stderr.
fn expectErrorReport(binary: []const u8, wanted: []const u8) !void {
    const reported = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{binary} });
    defer testing.allocator.free(reported.stdout);
    defer testing.allocator.free(reported.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, reported.term);
    try testing.expectEqualStrings("", reported.stdout);
    try testing.expectEqualStrings(wanted, reported.stderr);
}
/// A loop that keeps ten values live across an `Err` construction and, once
/// `relay` is inlined, across a `?` that propagates: recordings an optimized
/// caller makes with its values in registers. `main` then fails with a
/// three-site trace.
const kept_registers_program =
    \\func step(x: int, i: int) -> int fails int:
    \\    if i % 5 == 2:
    \\        fail i
    \\    return (x * 7 + i) % 1000003
    \\
    \\
    \\func relay(x: int, i: int) -> int fails int:
    \\    mut value = try step(x, i)
    \\    return value + 1
    \\
    \\
    \\func churn(n: int) -> int:
    \\    mut a = 1
    \\    mut b = 2
    \\    mut c = 3
    \\    mut d = 4
    \\    mut e = 5
    \\    mut f = 6
    \\    mut g = 7
    \\    mut h = 8
    \\    mut k = 9
    \\    mut failed = 0
    \\    for i in range(n):
    \\        const r: Result[int, int]
    \\        if i % 3 == 0:
    \\            r = Err(i)
    \\        else:
    \\            r = Ok(i)
    \\        match r:
    \\            case Ok(v):
    \\                a = (a + v * 3) % 1000003
    \\            case Err(code):
    \\                failed = failed + code
    \\        match relay(a + b, i):
    \\            case Ok(w):
    \\                b = (b * 5 + w) % 1000033
    \\            case Err(code):
    \\                failed = failed + code * 2
    \\        c = (c + b * 7) % 1000037
    \\        d = (d * 3 + c) % 1000039
    \\        e = (e + d * 11) % 1000081
    \\        f = (f * 13 + e) % 1000099
    \\        g = (g + f) % 1000117
    \\        h = (h * 17 + g) % 1000121
    \\        k = (k + h * 19) % 1000133
    \\    return a + b + c + d + e + f + g + h + k + failed
    \\
    \\
    \\func main(out: Stream) -> Result[int, int]:
    \\    print(out, churn(3000))
    \\    mut value = try relay(1, 7)
    \\    return Ok(value)
    \\
;
/// What `kept_registers_program` writes on stderr, `{path}` standing for its entry.
const kept_registers_report =
    \\error: 7
    \\  {path}:3:9    step   Err(...) created
    \\  {path}:8:17   relay  try propagated
    \\  {path}:51:17  main   try propagated
    \\
;
/// Run a build of `kept_registers_program`: its `int` error is the exit
/// status, the loop's result is on stdout and exactly `wanted` on stderr.
fn expectKeptReport(binary: []const u8, wanted: []const u8) !void {
    const reported = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{binary} });
    defer testing.allocator.free(reported.stdout);
    defer testing.allocator.free(reported.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 7 }, reported.term);
    try testing.expectEqualStrings("8548707\n", reported.stdout);
    try testing.expectEqualStrings(wanted, reported.stderr);
}

test "CLI computes and traces the same from a debug build and from --release" {
    const a = testing.allocator;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "kept.selka", .data = kept_registers_program });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "kept.selka", a);
    defer a.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const cache_argument = try std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{directory});
    defer a.free(cache_argument);
    const wanted = try std.mem.replaceOwned(u8, a, kept_registers_report, "{path}", entry);
    defer a.free(wanted);
    const debug = try std.fmt.allocPrint(a, "{s}/kept-debug", .{directory});
    defer a.free(debug);
    const release = try std.fmt.allocPrint(a, "{s}/kept-release", .{directory});
    defer a.free(release);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", debug, cache_argument, tools[0] }, "");
    try expectKeptReport(debug, wanted);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", release, "--release", cache_argument, tools[0] }, "");
    try expectKeptReport(release, wanted);
}
/// The `reason` a `native-tests-v1` report gives for the test called `name`.
fn testReason(report: std.json.Value, name: []const u8) []const u8 {
    for (report.object.get("tests").?.array.items) |case| {
        if (std.mem.eql(u8, case.object.get("name").?.string, name)) return case.object.get("reason").?.string;
    }
    return "";
}

// spec: ERROR-TRACE-3
test "CLI test reports a Result test's Err with its error return trace in text and JSON" {
    const a = testing.allocator;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "config_test.selka", .data =
        \\import strings
        \\func parse_port(text: str) -> int fails str:
        \\    if strings.char_count(text) == 0:
        \\        fail "empty"
        \\    return strings.char_count(text)
        \\
        \\public func test_port() -> bool fails str:
        \\    mut port = try parse_port("")
        \\    return port == 2
        \\
        \\public func test_fine() -> bool fails str:
        \\    const port = try parse_port("ab")
        \\    return port == 2
    });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "config_test.selka", a);
    defer a.free(entry);
    const cache = try std.fmt.allocPrint(a, "{s}/cache", .{std.fs.path.dirname(entry).?});
    defer a.free(cache);
    const text = try privateRun(a, &.{ compilerPath(), "test", entry, "--cache-dir", cache, tools[0] });
    defer a.free(text.stdout);
    defer a.free(text.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, text.term);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "passed config_test::test_fine\n") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout,
        \\failed config_test::test_port: expected {"case":"ok","value":true}, got {"case":"err","value":"empty"}
        \\  config_test.selka:4:9   config_test::parse_port  Err(...) created
        \\  config_test.selka:8:16  config_test::test_port   try propagated
        \\
    ) != null);
    const json = try privateRun(a, &.{ compilerPath(), "test", entry, "--json", "--cache-dir", cache, tools[0] });
    defer a.free(json.stdout);
    defer a.free(json.stderr);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, json.stdout, .{});
    defer parsed.deinit();
    try testing.expect(std.mem.endsWith(u8, testReason(parsed.value, "config_test::test_port"), "\n  config_test.selka:8:16  config_test::test_port   try propagated"));
}

// spec: EPRINT-1
test "CLI separates eprint stderr from print stdout byte-exactly" {
    const program =
        \\func main(out: Stream, err: Stream) -> int:
        \\    print(out, "out", 1)
        \\    print(err, "err", 7, sep="-", end="!\n")
        \\    print(err)
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
        \\func main(args: str[], out: Stream) -> int:
        \\    print(out, "count", len(args))
        \\    for value in args:
        \\        print(out, "[" + value + "]")
        \\    return 0
    ;
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data = program });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.selka", testing.allocator);
    defer testing.allocator.free(path);
    const guest = [_][]const u8{ "", "héllo wörld", "two words", "--print-result", "--max-steps=9" };
    const expected = "count 5\n[]\n[héllo wörld]\n[two words]\n[--print-result]\n[--max-steps=9]\n";

    var run_argv: std.ArrayList([]const u8) = .empty;
    defer run_argv.deinit(testing.allocator);
    try run_argv.appendSlice(testing.allocator, &.{ compilerPath(), "run", path, "--print-result" });
    try run_argv.appendSlice(testing.allocator, &tools);
    try run_argv.append(testing.allocator, "--");
    try run_argv.appendSlice(testing.allocator, &guest);
    const run = try std.process.run(testing.allocator, testing.io, .{ .argv = run_argv.items });
    defer testing.allocator.free(run.stdout);
    defer testing.allocator.free(run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run.term);
    try testing.expectEqualStrings(expected ++ "0\n", run.stdout);
    try testing.expectEqualStrings("", run.stderr);

    var empty_run_argv: std.ArrayList([]const u8) = .empty;
    defer empty_run_argv.deinit(testing.allocator);
    try empty_run_argv.appendSlice(testing.allocator, &.{ compilerPath(), "run", path, "--print-result" });
    try empty_run_argv.appendSlice(testing.allocator, &tools);
    const empty_run = try std.process.run(testing.allocator, testing.io, .{ .argv = empty_run_argv.items });
    defer testing.allocator.free(empty_run.stdout);
    defer testing.allocator.free(empty_run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, empty_run.term);
    try testing.expectEqualStrings("count 0\n0\n", empty_run.stdout);
    try testing.expectEqualStrings("", empty_run.stderr);

    var invalid_run_argv: std.ArrayList([]const u8) = .empty;
    defer invalid_run_argv.deinit(testing.allocator);
    try invalid_run_argv.appendSlice(testing.allocator, &.{ compilerPath(), "run", path, "--print-result" });
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
    try build_argv.appendSlice(testing.allocator, &.{ compilerPath(), "build", path, "--run" });
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
    try empty_build_argv.appendSlice(testing.allocator, &.{ compilerPath(), "build", path, "--run" });
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/main.selka", .data =
        \\import helper
        \\
        \\func main(args: str[], out: Stream) -> int:
        \\    print(out, helper.render(args))
        \\    return 0
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.selka", .data =
        \\
        \\
        \\public func render(args: str[]) -> str:
        \\    mut out = ""
        \\    for value in args:
        \\        out = out + "[" + value + "]"
        \\    return out
    });
    const entry = try temp.dir.realPathFileAlloc(testing.io, "app/main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "program" });
    defer testing.allocator.free(output);
    const guest = [_][]const u8{ "", "héllo wörld", "two words", "--print-result" };
    const expected = "[][héllo wörld][two words][--print-result]\n";

    var run_argv: std.ArrayList([]const u8) = .empty;
    defer run_argv.deinit(testing.allocator);
    try run_argv.appendSlice(testing.allocator, &.{ compilerPath(), "build", entry, "--run" });
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
    try link_argv.appendSlice(testing.allocator, &.{ compilerPath(), "build", entry, "-o", output });
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
/// child compiler never touches the shared runtime root under `~/.cache/selka`,
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

/// Point a child whose `HOME` is a fixture directory at a user cache shared by the tests
/// that do this, so the Zig toolchain is approved and the C runtime object built once per
/// suite cache instead of once per fixture. A fresh `HOME` is an empty user cache, and the
/// Debug compiler spends about 40 s approving the toolchain (SHA-256 over its closure) and
/// 4 s compiling the runtime before it builds the fixture's program. The stores are
/// content-keyed; the shared compiler-artifact and test-receipt stores stay off, so a
/// fixture's reports still count only its own work. The cache lives under the build root, not
/// the user's `~/.cache/selka`, which these fixtures exist to leave alone.
fn sharedUserCache(environment: *std.process.Environ.Map) !void {
    const relative = ".selka-cache/cli-user-cache";
    try std.Io.Dir.cwd().createDirPath(testing.io, relative);
    const absolute = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, relative, testing.allocator);
    defer testing.allocator.free(absolute);
    try environment.put("XDG_CACHE_HOME", absolute);
    try @import("test_paths").privateStores(environment);
}

/// Join `parts` into one path and store it as the child's Zig global cache.
fn putJoined(environment: *std.process.Environ.Map, parts: []const []const u8) !void {
    const resolved = try std.fs.path.join(testing.allocator, parts);
    defer testing.allocator.free(resolved);
    try environment.put("ZIG_GLOBAL_CACHE_DIR", resolved);
}

fn spawnWithEnv(argv: []const []const u8, env_map: *const std.process.Environ.Map) !std.process.RunResult {
    try requireReleaseArgs(argv);
    return std.process.run(testing.allocator, testing.io, .{ .argv = argv, .environ_map = env_map });
}

/// The entry of the empty-`PATH` project: it imports a module, prints through
/// its stream and carries a test, so `build`, `run` and `test` all have work.
const empty_path_main =
    \\import text.words
    \\
    \\func main(out: Stream) -> int:
    \\    mut n = words.count_words("the quick brown fox")
    \\    print(out, f"words: {n}")
    \\    return 0
    \\
    \\
    \\public func test_main_words() -> bool:
    \\    return words.count_words("one two") == 2
    \\
;
/// The imported module of the empty-`PATH` project, with a test of its own.
const empty_path_words =
    \\import strings
    \\
    \\public func count_words(line: str) -> int:
    \\    mut total = 0
    \\    for part in strings.split(line, " "):
    \\        if strings.char_count(part) > 0:
    \\            total = total + 1
    \\    return total
    \\
    \\
    \\public func test_count_words() -> bool:
    \\    return count_words("a bb  ccc") == 3 and count_words("") == 0
    \\
;

/// A child environment whose `PATH` names only an empty directory under `root`,
/// with `HOME` and `TMPDIR` inside the fixture and Zig's global cache forwarded.
/// A command that reached for `python3`, or for any program it was not handed
/// by `--zig`, cannot start it here.
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
    try sharedUserCache(&environment);
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
    try writeProjectFile(&temporary, "main.selka", empty_path_main);
    try writeProjectFile(&temporary, "text/words.selka", empty_path_words);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const installed_host = try @import("components.zig").stageInstalledHost(testing.allocator, testing.io, root, compilerPath());
    defer testing.allocator.free(installed_host);
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.selka" });
    defer testing.allocator.free(entry);
    const program = try std.fs.path.join(testing.allocator, &.{ root, "program" });
    defer testing.allocator.free(program);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);
    var environment = try emptyPathEnvironment(root);
    defer environment.deinit();
    try expectEmptyPathRun(&.{ installed_host, "check", entry }, &environment, "");
    try expectEmptyPathRun(&.{ installed_host, "build", entry, "-o", program, "--cache-dir", cache, tools[0] }, &environment, "");
    try expectEmptyPathRun(&.{program}, &environment, "words: 4\n");
    try expectEmptyPathRun(&.{ installed_host, "run", entry, cache_argument, tools[0] }, &environment, "words: 4\n");
    try expectEmptyPathRun(&.{ installed_host, "test", entry, cache_argument, tools[0] }, &environment, "2 passed");
    try expectEmptyPathRun(&.{ installed_host, "fmt-project", entry, "--check" }, &environment, "");
    try expectEmptyPathRun(&.{ installed_host, "docs", "primer" }, &environment, "selka");
    try expectEmptyPathRun(&.{ installed_host, "index-project", entry }, &environment, "\"version\":\"navigation-summary-v1\"");
    try expectEmptyPathRun(&.{ installed_host, "context", entry, "--symbol=text.words::count_words" }, &environment, "\"status\":\"ok\"");
    // The LLVM release path is built into the compiler (LLVM-ZIG-1): it runs no adapter.
    const release = try std.fs.path.join(testing.allocator, &.{ root, "program-release" });
    defer testing.allocator.free(release);
    try expectEmptyPathRun(&.{ installed_host, "build", entry, "-o", release, "--release", "--cache-dir", cache, tools[0] }, &environment, "");
    try expectEmptyPathRun(&.{release}, &environment, "words: 4\n");
    try expectEmptyPathRun(&.{ installed_host, "run", entry, "--release", cache_argument, tools[0] }, &environment, "words: 4\n");
    // `selka native show` reads the libraries and hashes them with no tool on PATH, and the pinned toolchain reuses
    // (GH-3b: nothing is approved, and no package manager is asked). `native approve` only says it is no longer needed.
    try expectEmptyPathRun(&.{ installed_host, "native", "show", tools[0] }, &environment, "reuse: on\n");
    try expectEmptyPathRun(&.{ installed_host, "native", "approve", "--dry-run", tools[0] }, &environment, "no longer needed");
}

/// What a `--version` run printed: its standard output, which holds one line.
fn versionLine(host: []const u8, argument: []const u8, environment: *const std.process.Environ.Map) ![]u8 {
    const result = try spawnWithEnv(&.{ host, argument }, environment);
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    errdefer std.debug.print("`{s}`:\nstdout: {s}\nstderr: {s}\n", .{ argument, result.stdout, result.stderr });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, result.stdout, "\n"));
    try testing.expect(std.mem.endsWith(u8, result.stdout, "\n"));
    return testing.allocator.dupe(u8, result.stdout[0 .. result.stdout.len - 1]);
}

/// The twelve digits after `identity ` in a version line.
fn identityOf(line: []const u8) ![]const u8 {
    const at = std.mem.indexOf(u8, line, "identity ") orelse return error.NoIdentity;
    const digits = line[at + "identity ".len ..][0..12];
    for (digits) |byte| try testing.expect(std.ascii.isHex(byte));
    return digits;
}

// spec: VERSION-1
test "CLI --version names the commit file beside the compiler and its identity, and a new commit leaves a stored test result served (D-FR22-4)" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "main.selka", empty_path_main);
    try writeProjectFile(&temporary, "text/words.selka", empty_path_words);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const installed_host = try @import("components.zig").stageInstalledHost(testing.allocator, testing.io, root, compilerPath());
    defer testing.allocator.free(installed_host);
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.selka" });
    defer testing.allocator.free(entry);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);
    var environment = try emptyPathEnvironment(root);
    defer environment.deinit();
    // Without the file the compiler still says what it is: its identity, and that no commit is recorded.
    const bare = try versionLine(installed_host, "--version", &environment);
    defer testing.allocator.free(bare);
    try testing.expect(std.mem.startsWith(u8, bare, "selka commit unknown, identity "));
    const identity = try identityOf(bare);
    try expectEmptyPathRun(&.{ installed_host, "test", entry, cache_argument, tools[0] }, &environment, "2 passed, 0 cached");
    // The install step's file beside the executable names the commit, and the identity does not move with it.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "installation/bin/selka.commit", .data = "commit 11419ef271ab3c5d7e9f0a1b2c3d4e5f60718293\ntree clean\n" });
    const clean = try versionLine(installed_host, "--version", &environment);
    defer testing.allocator.free(clean);
    try testing.expect(std.mem.startsWith(u8, clean, "selka commit 11419ef271ab, identity "));
    try testing.expectEqualStrings(identity, try identityOf(clean));
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "installation/bin/selka.commit", .data = "commit 0123456789abcdef0123456789abcdef01234567\ntree dirty\n" });
    const dirty = try versionLine(installed_host, "version", &environment);
    defer testing.allocator.free(dirty);
    try testing.expect(std.mem.startsWith(u8, dirty, "selka commit 0123456789ab+dirty, identity "));
    try testing.expectEqualStrings(identity, try identityOf(dirty));
    // A different commit file is a different commit and nothing else: the results the first run stored are served.
    try expectEmptyPathRun(&.{ installed_host, "test", entry, cache_argument, tools[0] }, &environment, "0 passed, 2 cached");
    // A file that names no commit reads as unknown.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "installation/bin/selka.commit", .data = "not a commit\n" });
    const junk = try versionLine(installed_host, "--version", &environment);
    defer testing.allocator.free(junk);
    try testing.expect(std.mem.startsWith(u8, junk, "selka commit unknown, identity "));
}

// spec: VERSION-2
test "the install step's commit file names the commit, marks a tree with changes, and says unknown outside a repository (D-FR22-4)" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const script = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, "scripts/write-commit-file.sh", testing.allocator);
    defer testing.allocator.free(script);
    try temporary.dir.createDirPath(testing.io, "tree/src");
    try temporary.dir.createDirPath(testing.io, "out");
    const repository = try std.fs.path.join(testing.allocator, &.{ root, "tree" });
    defer testing.allocator.free(repository);
    const out = try std.fs.path.join(testing.allocator, &.{ root, "out" });
    defer testing.allocator.free(out);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "tree/src/a.zig", .data = "// a\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "tree/notes.md", .data = "notes\n" });
    try gitIn(testing.allocator, repository, &.{ "init", "-q" });
    try gitIn(testing.allocator, repository, &.{ "add", "." });
    try gitIn(testing.allocator, repository, &.{ "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "one" });
    try runCommitScript(script, repository, out, null);
    const clean = try temporary.dir.readFileAlloc(testing.io, "out/selka.commit", testing.allocator, .limited(4096));
    defer testing.allocator.free(clean);
    try testing.expect(std.mem.startsWith(u8, clean, "commit "));
    try testing.expectEqual(@as(usize, 40), std.mem.indexOfScalar(u8, clean, '\n').? - "commit ".len);
    try testing.expect(std.mem.endsWith(u8, clean, "\ntree clean\n"));
    // An untracked file outside src is not built in; one under src is, and a changed tracked file is a change.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "tree/scratch.txt", .data = "x\n" });
    try runCommitScript(script, repository, out, null);
    const unrelated = try temporary.dir.readFileAlloc(testing.io, "out/selka.commit", testing.allocator, .limited(4096));
    defer testing.allocator.free(unrelated);
    try testing.expectEqualStrings(clean, unrelated);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "tree/src/new.zig", .data = "// new\n" });
    try runCommitScript(script, repository, out, null);
    const fresh = try temporary.dir.readFileAlloc(testing.io, "out/selka.commit", testing.allocator, .limited(4096));
    defer testing.allocator.free(fresh);
    try testing.expect(std.mem.endsWith(u8, fresh, "\ntree dirty\n"));
    try testing.expectEqualStrings(clean[0 .. clean.len - "tree clean\n".len], fresh[0 .. fresh.len - "tree dirty\n".len]);
    try temporary.dir.deleteFile(testing.io, "tree/src/new.zig");
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "tree/notes.md", .data = "changed\n" });
    try runCommitScript(script, repository, out, null);
    const modified = try temporary.dir.readFileAlloc(testing.io, "out/selka.commit", testing.allocator, .limited(4096));
    defer testing.allocator.free(modified);
    try testing.expect(std.mem.endsWith(u8, modified, "\ntree dirty\n"));
    // Outside a repository git cannot say, and the file says so.
    try temporary.dir.createDirPath(testing.io, "bare");
    const bare = try std.fs.path.join(testing.allocator, &.{ root, "bare" });
    defer testing.allocator.free(bare);
    try runCommitScript(script, bare, out, null);
    const unknown = try temporary.dir.readFileAlloc(testing.io, "out/selka.commit", testing.allocator, .limited(4096));
    defer testing.allocator.free(unknown);
    try testing.expectEqualStrings("commit unknown\n", unknown);
}

// FR24: the commit script asks its questions of a private copy of the index (a stale index made every install read all the
// tracked files), so the repository's own index is never touched, and every change of state is still noticed.
test "the commit script keeps a private copy of the index, leaves the repository's own alone and notices each change" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const script = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, "scripts/write-commit-file.sh", testing.allocator);
    defer testing.allocator.free(script);
    try temporary.dir.createDirPath(testing.io, "tree/src");
    try temporary.dir.createDirPath(testing.io, "out");
    const repository = try std.fs.path.join(testing.allocator, &.{ root, "tree" });
    defer testing.allocator.free(repository);
    const out = try std.fs.path.join(testing.allocator, &.{ root, "out" });
    defer testing.allocator.free(out);
    const work = try std.fs.path.join(testing.allocator, &.{ root, "cache", "commit-file" });
    defer testing.allocator.free(work);
    // An installation an earlier version wrote its private copy into: the two files go, `selka.commit` stays.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "out/selka.commit.index", .data = "old copy" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "out/selka.commit.index.stamp", .data = "" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "tree/src/a.zig", .data = "// a\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "tree/notes.md", .data = "notes\n" });
    try gitIn(testing.allocator, repository, &.{ "init", "-q" });
    try gitIn(testing.allocator, repository, &.{ "add", "." });
    try gitIn(testing.allocator, repository, &.{ "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "one" });
    const index_before = try temporary.dir.readFileAlloc(testing.io, "tree/.git/index", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(index_before);
    try runCommitScript(script, repository, out, work);
    const clean = try temporary.dir.readFileAlloc(testing.io, "out/selka.commit", testing.allocator, .limited(4096));
    defer testing.allocator.free(clean);
    try testing.expect(std.mem.endsWith(u8, clean, "\ntree clean\n"));
    // The copy exists in the build's cache and not beside the compiler, which holds the commit file alone; the repository's own
    // index is the same bytes, so no lock was taken and nothing was refreshed.
    _ = try temporary.dir.statFile(testing.io, "cache/commit-file/selka.commit.index", .{});
    _ = try temporary.dir.statFile(testing.io, "cache/commit-file/selka.commit.index.stamp", .{});
    try testing.expectError(error.FileNotFound, temporary.dir.statFile(testing.io, "out/selka.commit.index", .{}));
    try testing.expectError(error.FileNotFound, temporary.dir.statFile(testing.io, "out/selka.commit.index.stamp", .{}));
    var listing = try temporary.dir.openDir(testing.io, "out", .{ .iterate = true });
    defer listing.close(testing.io);
    var entries = listing.iterate();
    var count: usize = 0;
    while (try entries.next(testing.io)) |entry| {
        try testing.expectEqualStrings("selka.commit", entry.name);
        count += 1;
    }
    try testing.expectEqual(@as(usize, 1), count);
    const index_after = try temporary.dir.readFileAlloc(testing.io, "tree/.git/index", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(index_after);
    try testing.expectEqualStrings(index_before, index_after);
    // A tracked file edited, then put back, is a change and then none; the same run twice is the same file.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "tree/notes.md", .data = "changed\n" });
    try runCommitScript(script, repository, out, work);
    const edited = try temporary.dir.readFileAlloc(testing.io, "out/selka.commit", testing.allocator, .limited(4096));
    defer testing.allocator.free(edited);
    try testing.expect(std.mem.endsWith(u8, edited, "\ntree dirty\n"));
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "tree/notes.md", .data = "notes\n" });
    try runCommitScript(script, repository, out, work);
    const restored = try temporary.dir.readFileAlloc(testing.io, "out/selka.commit", testing.allocator, .limited(4096));
    defer testing.allocator.free(restored);
    try testing.expectEqualStrings(clean, restored);
    // A change staged and put back in the working tree is still a change (the index differs from HEAD); a commit is a new hash.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "tree/notes.md", .data = "staged\n" });
    try gitIn(testing.allocator, repository, &.{ "add", "notes.md" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "tree/notes.md", .data = "notes\n" });
    try runCommitScript(script, repository, out, work);
    const staged = try temporary.dir.readFileAlloc(testing.io, "out/selka.commit", testing.allocator, .limited(4096));
    defer testing.allocator.free(staged);
    try testing.expect(std.mem.endsWith(u8, staged, "\ntree dirty\n"));
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "tree/notes.md", .data = "second\n" });
    try gitIn(testing.allocator, repository, &.{ "add", "notes.md" });
    try gitIn(testing.allocator, repository, &.{ "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "two" });
    try runCommitScript(script, repository, out, work);
    const second = try temporary.dir.readFileAlloc(testing.io, "out/selka.commit", testing.allocator, .limited(4096));
    defer testing.allocator.free(second);
    try testing.expect(std.mem.endsWith(u8, second, "\ntree clean\n"));
    try testing.expect(!std.mem.eql(u8, clean, second));
    // A new file under src is a change, found through the copy, and a copy that cannot be made falls back to the old questions.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "tree/src/new.zig", .data = "// new\n" });
    try runCommitScript(script, repository, out, work);
    const fresh = try temporary.dir.readFileAlloc(testing.io, "out/selka.commit", testing.allocator, .limited(4096));
    defer testing.allocator.free(fresh);
    try testing.expect(std.mem.endsWith(u8, fresh, "\ntree dirty\n"));
    try temporary.dir.deleteFile(testing.io, "tree/src/new.zig");
    try temporary.dir.deleteFile(testing.io, "cache/commit-file/selka.commit.index");
    try temporary.dir.deleteFile(testing.io, "cache/commit-file/selka.commit.index.stamp");
    try temporary.dir.createDirPath(testing.io, "cache/commit-file/selka.commit.index");
    try runCommitScript(script, repository, out, work);
    const fallback = try temporary.dir.readFileAlloc(testing.io, "out/selka.commit", testing.allocator, .limited(4096));
    defer testing.allocator.free(fallback);
    try testing.expectEqualStrings(second, fallback);
    // With no cache directory given there is no copy at all, and the answer is the same.
    try temporary.dir.deleteTree(testing.io, "cache");
    try runCommitScript(script, repository, out, null);
    const without = try temporary.dir.readFileAlloc(testing.io, "out/selka.commit", testing.allocator, .limited(4096));
    defer testing.allocator.free(without);
    try testing.expectEqualStrings(second, without);
    try testing.expectError(error.FileNotFound, temporary.dir.statFile(testing.io, "cache/commit-file/selka.commit.index", .{}));
}

/// Run the install step's commit script with `directory` as its working directory, writing into `out`, and keeping its private
/// copy of the index in `work` when one is given. Git looks for a
/// repository upward from there and stops at the parent of `directory`'s own parent, so a directory in a temporary tree
/// is found in no repository above it (a checkout may hold the temporary directory).
fn runCommitScript(script: []const u8, directory: []const u8, out: []const u8, work: ?[]const u8) !void {
    var environment = try std.process.Environ.createMap(testing.environ, testing.allocator);
    defer environment.deinit();
    try environment.put("GIT_CEILING_DIRECTORIES", std.fs.path.dirname(std.fs.path.dirname(directory).?).?);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = if (work) |cache| &.{ "sh", script, out, cache } else &.{ "sh", script, out }, .cwd = .{ .path = directory }, .environ_map = &environment });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    errdefer std.debug.print("write-commit-file.sh:\nstdout: {s}\nstderr: {s}\n", .{ result.stdout, result.stderr });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

/// The shared library every packages fixture locks.
const package_library = "\n\npublic func answer() -> int:\n    return 42\n";
/// An application entry that imports the locked library and returns its answer.
const package_application = "import numbers\n\nfunc main() -> int:\n    return numbers.answer()\n";

/// A temporary tree holding `library/numbers.selka`, `packages.json` naming it, and
/// the absolute compiler, plus the environment every `selka packages` call runs
/// under: an empty `PATH`, `HOME` and `TMPDIR` inside the tree, and the native
/// toolchain named the way `zig build` names it, since a staged build spawns this
/// compiler with no `--zig` of its own.
const PackagesFixture = struct {
    temporary: testing.TmpDir,
    root: [:0]const u8,
    compiler: [:0]const u8,
    environment: std.process.Environ.Map,

    fn init() !PackagesFixture {
        var temporary = testing.tmpDir(.{});
        errdefer temporary.cleanup();
        try writeProjectFile(&temporary, "library/numbers.selka", package_library);
        try writeProjectFile(&temporary, "packages.json", "{\"packages\":[{\"name\":\"numbers\",\"root\":\"library\"}]}");
        const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
        errdefer testing.allocator.free(root);
        var environment = try emptyPathEnvironment(root);
        errdefer environment.deinit();
        try environment.put("SELKA_ZIG", @import("test_options").zig_path);
        // `selka test` plans its cache through a component, which an uninstalled compiler finds by this variable.
        if (testing.environ.getPosix("SELKA_COMPONENT_DIR")) |directory| try environment.put("SELKA_COMPONENT_DIR", directory);
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
        return .{ .temporary = temporary, .root = root, .compiler = compiler, .environment = environment };
    }

    fn deinit(self: *PackagesFixture) void {
        self.environment.deinit();
        testing.allocator.free(self.compiler);
        testing.allocator.free(self.root);
        self.temporary.cleanup();
    }

    /// Run `selka packages ARGS` from the fixture root.
    fn run(self: *PackagesFixture, args: []const []const u8) !std.process.RunResult {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(testing.allocator);
        try argv.appendSlice(testing.allocator, &.{ self.compiler, "packages" });
        try argv.appendSlice(testing.allocator, args);
        return std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .path = self.root }, .environ_map = &self.environment });
    }

    /// Run `selka ARGS` itself from the fixture root, under the environment `packages` runs in.
    fn runSelka(self: *PackagesFixture, args: []const []const u8) !std.process.RunResult {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(testing.allocator);
        try argv.append(testing.allocator, self.compiler);
        try argv.appendSlice(testing.allocator, args);
        return std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .path = self.root }, .environ_map = &self.environment });
    }

    /// Run `selka packages ARGS` and require `status`, `stdout` exactly and
    /// `stderr_part` somewhere in standard error.
    fn expect(self: *PackagesFixture, args: []const []const u8, status: u8, stdout: []const u8, stderr_part: []const u8) !void {
        const result = try self.run(args);
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        errdefer std.debug.print("selka packages {s}: stdout {s}\nstderr {s}\n", .{ args[0], result.stdout, result.stderr });
        try testing.expectEqual(std.process.Child.Term{ .exited = status }, result.term);
        try testing.expectEqualStrings(stdout, result.stdout);
        try testing.expect(std.mem.indexOf(u8, result.stderr, stderr_part) != null);
    }

    /// Run `selka packages ARGS` and require `status` and `part` somewhere in standard output or standard error (a
    /// build's `--report` line is on standard error, a test's listing on standard output).
    fn expectOutput(self: *PackagesFixture, args: []const []const u8, status: u8, part: []const u8) !void {
        const result = try self.run(args);
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        errdefer std.debug.print("selka packages {s}: stdout {s}\nstderr {s}\n", .{ args[0], result.stdout, result.stderr });
        try testing.expectEqual(std.process.Child.Term{ .exited = status }, result.term);
        try testing.expect(std.mem.indexOf(u8, result.stdout, part) != null or std.mem.indexOf(u8, result.stderr, part) != null);
    }

    /// Run `selka packages ARGS`, require `status`, and give back standard error, which the caller frees.
    fn stderrOf(self: *PackagesFixture, args: []const []const u8, status: u8) ![]u8 {
        const result = try self.run(args);
        defer testing.allocator.free(result.stdout);
        errdefer testing.allocator.free(result.stderr);
        errdefer std.debug.print("selka packages {s}: stdout {s}\nstderr {s}\n", .{ args[0], result.stdout, result.stderr });
        try testing.expectEqual(std.process.Child.Term{ .exited = status }, result.term);
        return result.stderr;
    }

    /// Run a program the fixture built, from the fixture root, and require its exit status.
    fn expectProgram(self: *PackagesFixture, program: []const u8, status: u8) !void {
        const path = try std.fs.path.join(testing.allocator, &.{ self.root, program });
        defer testing.allocator.free(path);
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{path}, .cwd = .{ .path = self.root }, .environ_map = &self.environment });
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        errdefer std.debug.print("{s}: stdout {s}\nstderr {s}\n", .{ program, result.stdout, result.stderr });
        try testing.expectEqual(std.process.Child.Term{ .exited = status }, result.term);
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
    const entry = try std.fmt.allocPrint(testing.allocator, "{s}/main.selka", .{application});
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
    try testing.expectEqualStrings("main.selka", entries);
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
test "selka packages builds two applications from one locked library without writing either tree" {
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
    try fixture.expect(&.{ "build", "app1/main.selka", "--lock=lock.json" }, 0, "", "");
    const after = try fixture.read("lock.json");
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(frozen, after);
    // Every staging directory under TMPDIR (the fixture root) was removed.
    const entries = try scratchEntries(fixture.root);
    defer testing.allocator.free(entries);
    try testing.expect(std.mem.indexOf(u8, entries, "selka-packages-") == null);
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
test "selka packages refuses drift, shared paths, doubled namespaces, standard names and symbolic links before compiling" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.write("app1/main.selka", package_application);
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const frozen = try fixture.read("lock.json");
    defer testing.allocator.free(frozen);
    try fixture.expect(&.{ "build", "app1/main.selka", "--lock", "lock.json", "--receipt", "receipt.json" }, 0, "", "");
    const receipt = try fixture.read("receipt.json");
    defer testing.allocator.free(receipt);
    const build_args = [_][]const u8{ "build", "app1/main.selka", "--lock", "lock.json", "--receipt", "receipt.json" };
    try fixture.write("library/numbers.selka", "\n\npublic func answer() -> int:\n    return 43\n");
    try fixture.expect(&build_args, 2, "", "packages: locked dependency changed: numbers");
    try fixture.write("library/numbers.selka", package_library);
    try fixture.write("app1/numbers.selka", package_library);
    try fixture.expect(&build_args, 2, "", "duplicate or invalid module path: numbers.selka");
    try fixture.temporary.dir.deleteFile(testing.io, "app1/numbers.selka");
    try fixture.write("app1/std_extra.selka", "");
    try fixture.expect(&build_args, 2, "", "cannot replace a standard module: std_extra.selka");
    try fixture.temporary.dir.deleteFile(testing.io, "app1/std_extra.selka");
    try doubledLock(&fixture, frozen);
    try fixture.expect(&build_args, 2, "", "duplicate or incompatible package namespace: numbers");
    try fixture.write("lock.json", "{\"version\":\"package-lock-v0\",\"packages\":[]}");
    try fixture.expect(&build_args, 2, "", "unsupported package lock");
    try fixture.write("lock.json", frozen);
    try fixture.temporary.dir.deleteFile(testing.io, "library/numbers.selka");
    try fixture.temporary.dir.symLink(testing.io, "../app1/main.selka", "library/numbers.selka", .{});
    try fixture.expect(&build_args, 2, "", "symbolic-link sources are rejected: numbers.selka");
    // No refusal touched the receipt the passing build wrote.
    const kept = try fixture.read("receipt.json");
    defer testing.allocator.free(kept);
    try testing.expectEqualStrings(receipt, kept);
}

// spec-case: PROJECT-LINKS-1
test "selka packages links a package's C only when the application allows it, and pins the C in the lock" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.write("library/numbers.selka", "extern func linked_answer(host: Host) -> i32\n\npublic func answer(host: Host) -> int:\n    return int(linked_answer(host))\n");
    try fixture.write("library/c/answer.c", "int linked_answer(void) { return 42; }\n");
    try fixture.write("library/selka.json", "{\"version\": 1, \"links\": [\"c/answer.c\"]}");
    try fixture.write("app1/main.selka", "import numbers\n\nfunc main(host: Host) -> int:\n    return numbers.answer(host)\n");
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const lock = try fixture.read("lock.json");
    defer testing.allocator.free(lock);
    try testing.expect(std.mem.indexOf(u8, lock, "\"path\": \"c/answer.c\"") != null);
    const build_args = [_][]const u8{ "build", "app1/main.selka", "--lock", "lock.json", "--command", "run-project" };
    // No configuration names the package: the refusal names the entry to add, and where.
    try fixture.expect(&build_args, 2, "", "package numbers links C (1 sources in");
    try fixture.expect(&build_args, 2, "", "add \"allow_links\": [\"numbers\"] to");
    try fixture.write("app1/selka.json", "{\"version\": 1, \"allow_links\": [\"numbers\"]}");
    try fixture.expect(&build_args, 42, "42\n", "");
    // Checking compiles no C, so it needs none of it.
    try fixture.expect(&.{ "build", "app1/main.selka", "--lock", "lock.json" }, 0, "", "");
    // The application's own links come along, resolved where its configuration is.
    try fixture.write("app1/extra.c", "int extra_value(void) { return 1; }\n");
    try fixture.write("app1/selka.json", "{\"version\": 1, \"links\": [\"extra.c\"], \"allow_links\": [\"numbers\"]}");
    try fixture.expect(&build_args, 42, "42\n", "");
    // An edit to the package's C, or to its list, is drift until the lock is made again.
    try fixture.write("library/c/answer.c", "int linked_answer(void) { return 43; }\n");
    try fixture.expect(&build_args, 2, "", "locked dependency changed: numbers (its links)");
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    try fixture.expect(&build_args, 43, "43\n", "");
    try fixture.write("library/selka.json", "{\"version\": 1, \"links\": []}");
    try fixture.expect(&build_args, 2, "", "locked dependency changed: numbers (its links)");
    try fixture.write("library/selka.json", "{\"version\": 1, \"links\": [\"c/answer.c\"]}");
    // Taking the package out of the allow list refuses it again.
    try fixture.write("app1/selka.json", "{\"version\": 1}");
    try fixture.expect(&build_args, 2, "", "add \"allow_links\": [\"numbers\"] to");
}

/// A test entry beside the application that imports the locked library; it passes for any answer above 40.
const package_test_entry = "import numbers\n\npublic func test_answer() -> bool:\n    return numbers.answer() > 40\n";

// spec-case: PACKAGES-BUILD-1
test "selka packages builds a binary and runs tests over the locked snapshot, and an unchanged snapshot replays" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.write("app1/main.selka", package_application);
    try fixture.write("app1/main_test.selka", package_test_entry);
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const build_args = [_][]const u8{ "build", "app1/main.selka", "--lock", "lock.json", "--command", "build", "--receipt", "receipt.json", "--", "-o", "app1.bin", "--report" };
    const test_args = [_][]const u8{ "build", "app1/main_test.selka", "--lock", "lock.json", "--command", "test" };
    // The binary is the program `run-project` runs: main returns the package's answer.
    try fixture.expectOutput(&build_args, 0, "\"program\":\"linked\"");
    try fixture.expectProgram("app1.bin", 42);
    const receipt = try fixture.read("receipt.json");
    defer testing.allocator.free(receipt);
    try testing.expect(std.mem.indexOf(u8, receipt, "\"version\": \"project-dependencies-v1\"") != null);
    // Nothing changed: the build replays its last identical build and the test its recorded pass.
    try fixture.expectOutput(&build_args, 0, "\"program\":\"replayed\"");
    try fixture.expectOutput(&test_args, 0, "passed main_test::test_answer");
    try fixture.expectOutput(&test_args, 0, "cached main_test::test_answer");
    // A directory runs every entry under it, through the same lock.
    try fixture.expectOutput(&.{ "build", "app1", "--lock", "lock.json", "--command", "test", "--receipt", "test-receipt.json" }, 0, "main_test::test_answer");
    const test_receipt = try fixture.read("test-receipt.json");
    defer testing.allocator.free(test_receipt);
    try testing.expect(std.mem.indexOf(u8, test_receipt, "\"dependencies\": null") != null);
    // Words after `--` reach the test command: a filter that matches nothing selects nothing.
    try fixture.expectOutput(&.{ "build", "app1/main_test.selka", "--lock", "lock.json", "--command", "test", "--", "--filter", "nothing" }, 3, "0 passed");
    // Only `test` takes a directory.
    try fixture.expect(&.{ "build", "app1", "--lock", "lock.json", "--command", "build", "--", "-o", "x.bin" }, 2, "", "only --command test takes one");
    try fixture.expect(&.{ "build", "app1/main.selka", "--lock", "lock.json", "--command", "deploy" }, 2, "", "--command check-project|run-project|index-project|build|test");
    try fixture.expect(&.{ "lock", "packages.json", "--output", "other.json", "--" }, 2, "", "usage: selka packages");
    // The program's own arguments need a second `--`: a word the command refuses as an option is named, with the line that works.
    const stray = [_][]const u8{ "build", "app1/main.selka", "--lock", "lock.json", "--command", "run-project", "--", "ing$", "file" };
    const refusal = try fixture.stderrOf(&stray, 2);
    defer testing.allocator.free(refusal);
    try testing.expect(std.mem.indexOf(u8, refusal, "`ing$` follows the first `--`") != null);
    try testing.expect(std.mem.indexOf(u8, refusal, "selka packages build app1/main.selka --lock lock.json --command run-project -- -- 'ing$' file") != null);
    try testing.expect(std.mem.indexOf(u8, refusal, "usage: selka run") == null);
    // A real usage error of the command keeps the command's usage text.
    const repeated = try fixture.stderrOf(&.{ "build", "app1/main.selka", "--lock", "lock.json", "--command", "run-project", "--", "--max-steps", "5", "--max-steps", "6" }, 2);
    defer testing.allocator.free(repeated);
    try testing.expect(std.mem.indexOf(u8, repeated, "usage: selka run") != null);
}

/// A library whose own source has two warnings (an unused import each) and an application with one of its own.
const warned_library = "import strings\nimport math\n\npublic func answer() -> int:\n    return 42\n";
const warned_application = "import numbers\nimport strings\n\nfunc main() -> int:\n    return numbers.answer()\n";

// spec-case: PACKAGES-BUILD-1
test "selka packages counts a package's warnings instead of printing them and its closing line names selka packages fix" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.write("library/numbers.selka", warned_library);
    try fixture.write("app1/main.selka", warned_application);
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const check = [_][]const u8{ "build", "app1/main.selka", "--lock", "lock.json", "--command", "check-project" };
    const text = try fixture.stderrOf(&check, 0);
    defer testing.allocator.free(text);
    // The application's warning is printed with its source line; the package's two are one line, and no other path is the staged copy's.
    try testing.expect(std.mem.startsWith(u8, text, "main.selka:2:8: warning[W_UNUSED_IMPORT]: import `strings` is never referenced"));
    try testing.expect(std.mem.indexOf(u8, text, "\n  import strings\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "numbers.selka:") == null);
    try testing.expect(std.mem.indexOf(u8, text, "\n2 warnings in package `numbers` are not shown\n") != null);
    // `selka fix` does not know the package: the closing line names `selka packages fix` with the entry and the lock as given, never
    // `selka fix` or a staged copy, and counts the application's warning alone.
    const closing = "`selka packages fix app1/main.selka --lock lock.json --warnings` repairs 1 of these 1\n";
    try testing.expect(std.mem.endsWith(u8, text, "\n2 warnings in package `numbers` are not shown\n" ++ closing));
    try testing.expect(std.mem.indexOf(u8, text, "selka fix") == null and std.mem.indexOf(u8, text, "selka-packages-") == null);
    // `--warnings` lists every warning, the package's too; the closing line offers the application's repair alone.
    const listed = try fixture.stderrOf(&(check ++ [_][]const u8{ "--", "--warnings" }), 0);
    defer testing.allocator.free(listed);
    try testing.expect(std.mem.indexOf(u8, listed, "numbers.selka:1:8: warning[W_UNUSED_IMPORT]") != null);
    try testing.expect(std.mem.indexOf(u8, listed, "numbers.selka:2:8: warning[W_UNUSED_IMPORT]") != null);
    try testing.expect(std.mem.indexOf(u8, listed, "not shown") == null);
    try testing.expect(std.mem.endsWith(u8, listed, "`selka packages fix app1/main.selka --lock lock.json --warnings` repairs 1 of these 3\n"));
    try testing.expect(std.mem.indexOf(u8, listed, "selka fix") == null);
    // A JSON report carries every diagnostic, with the staged path of each file, and has neither the count line nor the closing one.
    const json = try fixture.stderrOf(&(check ++ [_][]const u8{ "--", "--diagnostics=json" }), 0);
    defer testing.allocator.free(json);
    try testing.expect(std.mem.indexOf(u8, json, "\"path\":\"numbers.selka\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "not shown") == null and std.mem.indexOf(u8, json, "selka packages fix") == null);
}

// spec-case: PACKAGES-BUILD-1
test "selka packages prints an error in a package's file and every warning of a package when the project denies them" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.write("library/numbers.selka", warned_library ++ "\npublic func broken() -> int:\n    return \"text\"\n");
    try fixture.write("app1/main.selka", warned_application);
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const check = [_][]const u8{ "build", "app1/main.selka", "--lock", "lock.json", "--command", "check-project" };
    // The error is printed as it always was, and stops the command with the status it had.
    const refused = try fixture.stderrOf(&check, 1);
    defer testing.allocator.free(refused);
    try testing.expect(std.mem.indexOf(u8, refused, "numbers.selka:8:5: error[E_TYPE]") != null);
    try testing.expect(std.mem.indexOf(u8, refused, "not shown") == null);
    // A project that denies warnings fails on the package's too: they are why it failed, so they are printed.
    try fixture.write("library/numbers.selka", warned_library);
    try fixture.write("app1/selka.json", "{\"version\":2,\"lint\":{\"warnings\":\"deny\"}}");
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const denied = try fixture.stderrOf(&check, 1);
    defer testing.allocator.free(denied);
    try testing.expect(std.mem.indexOf(u8, denied, "numbers.selka:1:8: warning[W_UNUSED_IMPORT]") != null);
    try testing.expect(std.mem.indexOf(u8, denied, "not shown") == null);
    try testing.expect(std.mem.indexOf(u8, denied, "selka fix") == null);
}

// spec-case: PACKAGES-BUILD-1
test "selka packages says the same about a package's warnings on a build and on its replay" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.write("library/numbers.selka", warned_library);
    try fixture.write("app1/main.selka", package_application);
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const build_args = [_][]const u8{ "build", "app1/main.selka", "--lock", "lock.json", "--command", "build", "--", "-o", "app1.bin", "--report" };
    const fresh = try fixture.stderrOf(&build_args, 0);
    defer testing.allocator.free(fresh);
    const replayed = try fixture.stderrOf(&build_args, 0);
    defer testing.allocator.free(replayed);
    // The count line is on the build and on its replay, once each, and nothing of the package's is printed.
    try testing.expect(std.mem.indexOf(u8, fresh, "\"program\":\"linked\"") != null);
    try testing.expect(std.mem.indexOf(u8, replayed, "\"program\":\"replayed\"") != null);
    try testing.expect(std.mem.indexOf(u8, fresh, "2 warnings in package `numbers` are not shown\n") != null);
    try testing.expect(std.mem.indexOf(u8, replayed, "2 warnings in package `numbers` are not shown\n") != null);
    try testing.expect(std.mem.indexOf(u8, fresh, "numbers.selka:") == null and std.mem.indexOf(u8, replayed, "numbers.selka:") == null);
}

/// A library with a warning that has a repair (an unused import) and a function that takes its argument `mut`.
const fixable_library = "import strings\n\npublic func answer() -> int:\n    return 42\n\npublic func grow(mut xs: int[]) -> Unit:\n    append(mut xs, 1)\n";
/// An application with an error that has a repair (its call does not say `mut`) and a warning that has one (an unused import).
const fixable_application = "import numbers\nimport strings\n\nfunc main() -> int:\n    mut xs: int[] = []\n    numbers.grow(xs)\n    return numbers.answer() + len(xs)\n";
/// The application once both are repaired.
const fixed_application = "import numbers\n\nfunc main() -> int:\n    mut xs: int[] = []\n    numbers.grow(mut xs)\n    return numbers.answer() + len(xs)\n";
/// What a `selka packages fix` that repairs warnings says of the package's repair it left.
const package_fix_left = "fix: left 1 fix in package `numbers` alone: `selka packages fix` never writes a package's files\n";

/// Require the fixture's file at `path` to hold `expected`.
fn expectFixtureFile(fixture: *PackagesFixture, path: []const u8, expected: []const u8) !void {
    const bytes = try fixture.read(path);
    defer testing.allocator.free(bytes);
    try testing.expectEqualStrings(expected, bytes);
}

// spec-case: PACKAGES-FIX-1
test "selka packages fix repairs the application's file by selka fix's rules and never writes the package's" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.write("library/numbers.selka", fixable_library);
    try fixture.write("app1/main.selka", fixable_application);
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const fix = [_][]const u8{ "fix", "app1/main.selka", "--lock", "lock.json" };
    // `--check` lists the error's repair, under the user's path, and writes nothing.
    try fixture.expect(&(fix ++ [_][]const u8{"--check"}), 1, "would fix app1/main.selka: 1 edit (E_MUTATION_MARKER)\nfix --check: 1 edit in 1 file would change\n", "");
    try expectFixtureFile(&fixture, "app1/main.selka", fixable_application);
    // A file run repairs the error only and names the command that repairs the warning it left; the package's warning is counted.
    try fixture.expect(&fix, 0, "fixed app1/main.selka: 1 edit (E_MUTATION_MARKER)\nfix: 1 edit in 1 file over 1 round\n" ++
        "fix: left 1 warning with a repair alone; `selka packages fix app1/main.selka --lock lock.json --warnings` repairs it too\n", "1 warning in package `numbers` is not shown\n");
    // `--warnings` repairs the application's warning and leaves the package's repair, in one line; a second run has nothing to do.
    try fixture.expect(&(fix ++ [_][]const u8{"--warnings"}), 0, "fixed app1/main.selka: 1 edit (W_UNUSED_IMPORT)\nfix: 1 edit in 1 file over 1 round\n" ++ package_fix_left, "");
    try expectFixtureFile(&fixture, "app1/main.selka", fixed_application);
    try fixture.expect(&(fix ++ [_][]const u8{"--warnings"}), 0, "fix: nothing to fix\n" ++ package_fix_left, "");
    try expectFixtureFile(&fixture, "library/numbers.selka", fixable_library);
    // The check through the lock is clean of the application's warnings, and prints no closing line.
    const checked = try fixture.stderrOf(&.{ "build", "app1/main.selka", "--lock", "lock.json", "--command", "check-project" }, 0);
    defer testing.allocator.free(checked);
    try testing.expectEqualStrings("1 warning in package `numbers` is not shown\n", checked);
    // `selka packages fix` stages privately: the kept stage of a build still replays after it.
    const build_args = [_][]const u8{ "build", "app1/main.selka", "--lock", "lock.json", "--command", "build", "--", "-o", "app1.bin", "--report" };
    try fixture.expectOutput(&build_args, 0, "\"program\":\"linked\"");
    try fixture.expect(&fix, 0, "fix: nothing to fix\n", "");
    try fixture.expectOutput(&build_args, 0, "\"program\":\"replayed\"");
    // A package whose bytes differ from the lock is refused as `build` refuses it, and nothing is written.
    try fixture.write("library/numbers.selka", fixable_library ++ "\n");
    try fixture.write("app1/main.selka", fixable_application);
    try fixture.expect(&fix, 2, "", "packages: locked dependency changed: numbers\n");
    try expectFixtureFile(&fixture, "app1/main.selka", fixable_application);
    try fixture.expect(&.{ "fix", "app1/main.selka" }, 2, "", "usage: selka packages");
}

// spec-case: PACKAGES-FIX-1
test "selka packages fix of a directory repairs errors and warnings in the application's files and leaves the package's" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.write("library/numbers.selka", fixable_library);
    try fixture.write("app2/main.selka", fixable_application);
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    // The error hides the warning until it is repaired, so the run takes two rounds, as `selka fix` does.
    try fixture.expect(&.{ "fix", "app2", "--lock", "lock.json" }, 0, "fixed app2/main.selka: 2 edits (E_MUTATION_MARKER, W_UNUSED_IMPORT)\n" ++
        "fix: 2 edits in 1 file over 2 rounds\n" ++ package_fix_left, "1 warning in package `numbers` is not shown\n");
    try expectFixtureFile(&fixture, "app2/main.selka", fixed_application);
    try expectFixtureFile(&fixture, "library/numbers.selka", fixable_library);
    try fixture.expect(&.{ "fix", "app2", "--lock", "lock.json" }, 0, "fix: nothing to fix\n" ++ package_fix_left, "");
}

// spec-case: PACKAGES-BUILD-1
test "selka packages refuses a changed package before build or test runs, and a new lock rebuilds the binary and reruns the test" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.write("app1/main.selka", package_application);
    try fixture.write("app1/main_test.selka", package_test_entry);
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const build_args = [_][]const u8{ "build", "app1/main.selka", "--lock", "lock.json", "--command", "build", "--", "-o", "app1.bin", "--report" };
    const test_args = [_][]const u8{ "build", "app1/main_test.selka", "--lock", "lock.json", "--command", "test" };
    try fixture.expectOutput(&build_args, 0, "\"program\":\"linked\"");
    try fixture.expectOutput(&test_args, 0, "passed main_test::test_answer");
    // The package changed after locking: both commands refuse it, as check-project does, and build nothing.
    try fixture.write("library/numbers.selka", "\n\npublic func answer() -> int:\n    return 43\n");
    try fixture.expect(&build_args, 2, "", "packages: locked dependency changed: numbers");
    try fixture.expect(&test_args, 2, "", "packages: locked dependency changed: numbers");
    try fixture.expectProgram("app1.bin", 42);
    // Locked again, the binary is linked anew from the new source and the test runs again instead of replaying.
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    try fixture.expectOutput(&build_args, 0, "\"program\":\"linked\"");
    try fixture.expectProgram("app1.bin", 43);
    try fixture.expectOutput(&test_args, 0, "passed main_test::test_answer");
    // A module the package no longer has is gone from the kept stage, so the application cannot import it.
    try fixture.write("library/numbers/extra.selka", "public func more() -> int:\n    return 1\n");
    try fixture.write("app1/main.selka", "import numbers\nimport numbers.extra\n\nfunc main() -> int:\n    return numbers.answer() + numbers.extra.more()\n");
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    try fixture.expectOutput(&build_args, 0, "\"program\":\"linked\"");
    try fixture.expectProgram("app1.bin", 44);
    try fixture.temporary.dir.deleteFile(testing.io, "library/numbers/extra.selka");
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const missing = try fixture.run(&build_args);
    defer testing.allocator.free(missing.stdout);
    defer testing.allocator.free(missing.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, missing.term);
}

// spec-case: PROJECT-LINKS-1
test "selka packages links a package's C into the binary and the test programs that build and test make" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.write("library/numbers.selka", "extern func linked_answer(host: Host) -> i32\n\npublic func answer(host: Host) -> int:\n    return int(linked_answer(host))\n");
    try fixture.write("library/c/answer.c", "int linked_answer(void) { return 42; }\n");
    try fixture.write("library/selka.json", "{\"version\": 1, \"links\": [\"c/answer.c\"]}");
    try fixture.write("app1/main.selka", "import numbers\n\nfunc main(host: Host) -> int:\n    return numbers.answer(host)\n");
    try fixture.write("app1/main_test.selka", "import numbers\n\npublic func test_linked(host: Host) -> bool:\n    return numbers.answer(host) == 42\n");
    try fixture.write("app1/selka.json", "{\"version\": 1, \"allow_links\": [\"numbers\"]}");
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const build_args = [_][]const u8{ "build", "app1/main.selka", "--lock", "lock.json", "--command", "build", "--", "-o", "app1.bin", "--report" };
    try fixture.expectOutput(&build_args, 0, "\"program\":\"linked\"");
    try fixture.expectProgram("app1.bin", 42);
    try fixture.expectOutput(&build_args, 0, "\"program\":\"replayed\"");
    try fixture.expectOutput(&.{ "build", "app1/main_test.selka", "--lock", "lock.json", "--command", "test", "--", "--allow-host" }, 0, "passed main_test::test_linked");
    // The package's C changed: refused until locked again, then linked anew.
    try fixture.write("library/c/answer.c", "int linked_answer(void) { return 43; }\n");
    try fixture.expect(&build_args, 2, "", "locked dependency changed: numbers (its links)");
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    try fixture.expectOutput(&build_args, 0, "\"program\":\"linked\"");
    try fixture.expectProgram("app1.bin", 43);
}

/// An application of the fixture's locked library that sets `interface_files`: `main.selka` imports the library and `util.selka`, and
/// `main_test.selka` tests `util`, which `main_test.selka` imports beside the library.
fn writeKeyedApplication(fixture: *PackagesFixture) !void {
    try fixture.write("app1/selka.json", "{\"version\": 1, \"interface_files\": true}");
    try fixture.write("app1/util.selka", "\n\npublic func twice(n: int) -> int:\n    return n * 2\n");
    try fixture.write("app1/main.selka", "import numbers\nimport util\n\nfunc main() -> int:\n    return util.twice(numbers.answer())\n");
    try fixture.write("app1/main_test.selka", "import numbers\nimport util\n\npublic func test_twice() -> bool:\n    return util.twice(numbers.answer()) == 84\n");
}

// spec: API-FILE-3
test "selka packages asks the application's interface files and none of a package's or of a test module, and --command api writes them" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    try writeKeyedApplication(&fixture);
    const build_args = [_][]const u8{ "build", "app1/main.selka", "--lock", "lock.json" };
    // Before: every module was reported missing whatever was on disk, the library's and the test's among them, and the line named the
    // private snapshot. Now only the application's own modules are asked for, and the line names the command that writes them.
    const missing = try fixture.stderrOf(&build_args, 1);
    defer testing.allocator.free(missing);
    try testing.expect(std.mem.indexOf(u8, missing, "main.api:1:1: error[E_INTERFACE_FILE_STALE]: the interface file of module `main` is missing; run `selka packages build app1/main.selka --lock lock.json --command api -- --write` and review its diff") != null);
    try testing.expect(std.mem.indexOf(u8, missing, "util.api:1:1") != null);
    try testing.expect(std.mem.indexOf(u8, missing, "numbers.api") == null);
    try testing.expect(std.mem.indexOf(u8, missing, "/selka-packages-") == null);
    try fixture.expectOutput(&.{ "build", "app1/main.selka", "--lock", "lock.json", "--command", "api", "--", "--check" }, 1, "api: 2 interface files out of date; run `selka packages build app1/main.selka --lock lock.json --command api -- --write`\n");
    try testing.expectError(error.FileNotFound, fixture.temporary.dir.access(testing.io, "app1/main.api", .{}));
    try fixture.expectOutput(&.{ "build", "app1/main.selka", "--lock", "lock.json", "--command", "api", "--", "--write" }, 0, "api: 2 interface files current (2 written, 0 deleted)\n");
    const written = try fixture.read("app1/util.api");
    defer testing.allocator.free(written);
    try testing.expectEqualStrings("# generated by selka api; do not edit\nmodule util\n\npublic func twice(n: int) -> int\n", written);
    // The library's and the test module's files were never written, and the build and the test now pass.
    try testing.expectError(error.FileNotFound, fixture.temporary.dir.access(testing.io, "app1/numbers.api", .{}));
    try testing.expectError(error.FileNotFound, fixture.temporary.dir.access(testing.io, "app1/main_test.api", .{}));
    try fixture.expect(&build_args, 0, "", "");
    try fixture.expectOutput(&.{ "build", "app1/main_test.selka", "--lock", "lock.json", "--command", "test" }, 0, "passed main_test::test_twice");
    // A file that is stale is reported with the same command, and the next --write brings it current.
    try fixture.write("app1/util.selka", "\n\npublic func twice(n: int, extra: int = 0) -> int:\n    return n * 2 + extra\n");
    const stale = try fixture.stderrOf(&build_args, 1);
    defer testing.allocator.free(stale);
    try testing.expect(std.mem.indexOf(u8, stale, "util.api:1:1: error[E_INTERFACE_FILE_STALE]: the interface file of module `util` is stale; run `selka packages build app1/main.selka --lock lock.json --command api -- --write`") != null);
    try fixture.expectOutput(&.{ "build", "app1/main.selka", "--lock", "lock.json", "--command", "api", "--", "--write" }, 0, "api: wrote util.api (util)\n");
    try fixture.expect(&build_args, 0, "", "");
    // Without the key the snapshot holds no interface file and asks for none.
    try fixture.write("app1/selka.json", "{\"version\": 1}");
    try fixture.expect(&build_args, 0, "", "");
}

// spec: PACKAGES-LOCK-1
test "selka packages refuses a package named like a standard module, at lock and at build with a lock written before" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const earlier = try fixture.read("lock.json");
    defer testing.allocator.free(earlier);
    try fixture.write("app1/main.selka", "import strings\n\nfunc main() -> int:\n    return strings.char_count(\"abc\")\n");
    try fixture.write("other/strings.selka", "\n\npublic func shout(s: str) -> str:\n    return s\n");
    try fixture.write("packages.json", "{\"packages\":[{\"name\":\"strings\",\"root\":\"other\"}]}");
    const named = "package strings is named like the standard module `strings`, which `import strings` always loads: the package's `strings.selka` would never be used.";
    try fixture.expect(&.{ "lock", "packages.json", "--output", "other.json" }, 2, "", named);
    try testing.expectError(error.FileNotFound, fixture.temporary.dir.access(testing.io, "other.json", .{}));
    // A lock written before names the package `strings` too: the same words at build, and nothing built.
    const renamed = try std.mem.replaceOwned(u8, testing.allocator, earlier, "\"name\": \"numbers\"", "\"name\": \"strings\"");
    defer testing.allocator.free(renamed);
    try fixture.write("lock.json", renamed);
    try fixture.expect(&.{ "build", "app1/main.selka", "--lock", "lock.json" }, 2, "", named);
    // The standard module is what the application's `import strings` has always reached, whatever the package held.
    try fixture.write("lock.json", earlier);
    try fixture.expect(&.{ "build", "app1/main.selka", "--lock", "lock.json" }, 0, "", "");
}

/// The tests a run passed or replayed (a `passed` or `cached` line of its standard output), by name, sorted, one per line.
fn passedTests(output: []const u8) ![]u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(testing.allocator);
    var split = std.mem.splitScalar(u8, output, '\n');
    while (split.next()) |line| if (std.mem.startsWith(u8, line, "passed ") or std.mem.startsWith(u8, line, "cached ")) try lines.append(testing.allocator, line["passed ".len..]);
    std.mem.sort([]const u8, lines.items, {}, struct {
        fn less(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.less);
    return std.mem.join(testing.allocator, "\n", lines.items);
}

// spec: PACKAGES-BUILD-1
test "a directory run and selka packages walk the same folders, and a link to a folder is refused only in one they walk" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    try fixture.write("app1/selka.json", "{\"version\": 2, \"release\": {\"exclude\": [\"skipped/\"]}}");
    // One test in each folder: the ones a run walks are named `walked_*`.
    const folders = [_]struct { path: []const u8, name: []const u8 }{
        .{ .path = "app1/a_test.selka", .name = "walked_root" },
        .{ .path = "app1/tmp/t_test.selka", .name = "walked_tmp" },
        .{ .path = "app1/sub/deep/d_test.selka", .name = "walked_deep" },
        .{ .path = "app1/.hid/h_test.selka", .name = "left_hidden" },
        .{ .path = "app1/sub/.hid/h_test.selka", .name = "left_nested_hidden" },
        .{ .path = "app1/build/b_test.selka", .name = "left_build" },
        .{ .path = "app1/zig-out/z_test.selka", .name = "left_zig_out" },
        .{ .path = "app1/sub/node_modules/n_test.selka", .name = "left_node_modules" },
        .{ .path = "app1/skipped/s_test.selka", .name = "left_excluded" },
        .{ .path = "app1/cachedir/c_test.selka", .name = "left_cache" },
    };
    for (folders) |folder| {
        const source = try std.fmt.allocPrint(testing.allocator, "public func test_{s}() -> bool:\n    return True\n", .{folder.name});
        defer testing.allocator.free(source);
        try fixture.write(folder.path, source);
    }
    // A link to a folder inside each folder both leave out is never looked at: the one walk does not follow it, the other does not refuse it.
    for ([_][]const u8{ "app1/.hid", "app1/build", "app1/zig-out", "app1/sub/node_modules", "app1/skipped", "app1/cachedir" }) |folder| {
        const link = try std.fmt.allocPrint(testing.allocator, "{s}/linkdir", .{folder});
        defer testing.allocator.free(link);
        try fixture.temporary.dir.symLink(testing.io, "../sub", link, .{ .is_directory = true });
    }
    const cache = try std.fmt.allocPrint(testing.allocator, "{s}/app1/cachedir", .{fixture.root});
    defer testing.allocator.free(cache);
    const direct = try fixture.runSelka(&.{ "test", "app1", "--cache-dir", cache });
    defer testing.allocator.free(direct.stdout);
    defer testing.allocator.free(direct.stderr);
    errdefer std.debug.print("selka test: stdout {s}\nstderr {s}\n", .{ direct.stdout, direct.stderr });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, direct.term);
    const staged = try fixture.run(&.{ "build", "app1", "--lock", "lock.json", "--command", "test", "--", "--cache-dir", cache });
    defer testing.allocator.free(staged.stdout);
    defer testing.allocator.free(staged.stderr);
    errdefer std.debug.print("selka packages build: stdout {s}\nstderr {s}\n", .{ staged.stdout, staged.stderr });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, staged.term);
    const by_run = try passedTests(direct.stdout);
    defer testing.allocator.free(by_run);
    const by_packages = try passedTests(staged.stdout);
    defer testing.allocator.free(by_packages);
    try testing.expectEqualStrings(by_run, by_packages);
    for (folders) |folder| {
        const walked = std.mem.startsWith(u8, folder.name, "walked_");
        const name = try std.fmt.allocPrint(testing.allocator, "::test_{s}", .{folder.name});
        defer testing.allocator.free(name);
        try testing.expectEqual(walked, std.mem.indexOf(u8, by_run, name) != null);
    }
    // A link to a folder in a folder they do walk is still refused, with the message it has, and nothing is built.
    try fixture.temporary.dir.symLink(testing.io, "../sub", "app1/tmp/linkdir", .{ .is_directory = true });
    try fixture.expect(&.{ "build", "app1", "--lock", "lock.json", "--command", "test", "--", "--cache-dir", cache }, 2, "", "packages: symbolic-link directories are rejected: tmp/linkdir");
    // The folder `--cache-dir` names is walked when no such word is given, and a link in it is refused like one anywhere else.
    try fixture.expect(&.{ "build", "app1", "--lock", "lock.json", "--command", "test" }, 2, "", "packages: symbolic-link directories are rejected: cachedir/linkdir");
}

// spec: PACKAGES-LOCK-1
test "selka packages lock pins each resolved root and module hash and refuses bad namespaces, empty packages and stray sources" {
    var fixture = try PackagesFixture.init();
    defer fixture.deinit();
    try fixture.expect(&.{ "lock", "packages.json", "--output", "lock.json" }, 0, "", "");
    const lock = try fixture.read("lock.json");
    defer testing.allocator.free(lock);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(package_library, &digest, .{});
    const pinned = try std.fmt.allocPrint(testing.allocator, "\"numbers.selka\": \"{s}\"", .{std.fmt.bytesToHex(digest, .lower)});
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
    try fixture.write("library/stray.selka", "");
    try fixture.write("packages.json", "{\"packages\":[{\"name\":\"numbers\",\"root\":\"library\"}]}");
    try fixture.expect(&lock_args, 2, "", "package numbers: library/stray.selka is neither numbers.selka nor under numbers/");
    try fixture.expect(&lock_args, 2, "", "move it to library/numbers/stray.selka and import it as `import numbers.stray`");
    try fixture.expect(&.{ "lock", "packages.json" }, 2, "", "usage: selka packages");
    // No refused lock wrote its output.
    try testing.expectError(error.FileNotFound, fixture.temporary.dir.access(testing.io, "other.json", .{}));
}

// spec: BOUNDARY-CLI-1
test "boundary acceptance CLI runs through run build --run and installed paths" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "sample.selka", .data = "a\nb\n" });
    const input = try temp.dir.realPathFileAlloc(testing.io, "sample.selka", testing.allocator);
    defer testing.allocator.free(input);
    const home = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(home);
    const output = try std.fs.path.join(testing.allocator, &.{ home, "boundary-cli" });
    defer testing.allocator.free(output);
    const cache = try std.fs.path.join(testing.allocator, &.{ home, "cache" });
    defer testing.allocator.free(cache);
    const cache_arg = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_arg);
    const entry = "examples/boundary-cli/main.selka";
    const expected = "{\"lines\":2,\"characters\":4}\n";
    const trace = try std.fmt.allocPrint(testing.allocator, "reading {s}\n", .{input});
    defer testing.allocator.free(trace);

    var plain_env: std.process.Environ.Map = .init(testing.allocator);
    defer plain_env.deinit();
    try plain_env.put("HOME", home);
    try forwardZigCache(&plain_env);
    try sharedUserCache(&plain_env);
    var trace_env: std.process.Environ.Map = .init(testing.allocator);
    defer trace_env.deinit();
    try trace_env.put("HOME", home);
    try trace_env.put("SELKA_ACCEPT_MODE", "1");
    try forwardZigCache(&trace_env);
    try sharedUserCache(&trace_env);

    var run_argv: std.ArrayList([]const u8) = .empty;
    defer run_argv.deinit(testing.allocator);
    try run_argv.appendSlice(testing.allocator, &.{ compilerPath(), "run", entry, cache_arg });
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
    try build_argv.appendSlice(testing.allocator, &.{ compilerPath(), "build", entry, "--run", cache_arg });
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
    try link_argv.appendSlice(testing.allocator, &.{ compilerPath(), "build", entry, "-o", output });
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
    try invoke("run", @embedFile("fixtures/arithmetic.selka"), 0, "7\n", "");
    try invoke("check", @embedFile("fixtures/arithmetic.selka"), 0, "", "");
}
// spec-case: NATIVE-TEST-10
test "a native run reports a failed assert with its message" {
    try invoke("run",
        \\func main() -> int:
        \\    assert False, "x should be two"
        \\    return 0
    , 1, "", "error[R_ASSERT]: native execution failed: x should be two");
    // A message carrying JSON syntax must not corrupt the machine record: the
    // `trap_detail` object still parses and appears in the JSON diagnostics.
    try invokeOptions("run",
        \\func main() -> int:
        \\    assert False, "say \"hi\""
        \\    return 0
    , &.{"--diagnostics=json"}, 1, "", "\"trap_detail\"");
}
// spec: NATIVE-TIMING-1
test "CLI execution timings preserve results and runtime diagnostics" {
    const source =
        \\func main() -> i64:
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
        \\func main() -> i64:
        \\    return divtrunc(1, 0)
    ;
    try invokeOptions("run", trap, &.{"--timings"}, 1, "", "error[R_DIVISION_BY_ZERO]");
    try invokeOptions("run", trap, &.{"--diagnostics=json"}, 1, "", "\"code\":\"R_DIVISION_BY_ZERO\"");
    try invokeOptions("run", source, &.{ "--timings", "--timings" }, 2, "", "usage:");
    try invokeOptions("check", source, &.{"--timings"}, 2, "", "usage:");
}
test "CLI check timings name every project phase" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = "public func value() -> int:\n    return 7\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "import helper\n\nfunc main() -> int:\n    return helper.value()\n" });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);
    const outcome = try privateRun(testing.allocator, &.{ compilerPath(), "check-project", entry, cache_argument, "--timings=json" });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    // Each phase is a disjoint interval or an explicitly named sub-interval, so a
    // slow check is attributed to a name rather than to unnamed time.
    for ([_][]const u8{ "project_policy", "project_surface_and_verdict", "source_digests", "declaration_command", "index_build_wall", "semantic_cache_open", "sema_collect", "sema_session_open", "sema_checker_setup", "sema_post_bodies", "checked_command", "remember_frontend_verdict", "total" }) |name| {
        const needle = try std.fmt.allocPrint(testing.allocator, "\"name\":\"{s}\"", .{name});
        defer testing.allocator.free(needle);
        try testing.expect(std.mem.indexOf(u8, outcome.stderr, needle) != null);
    }
}
// spec: CLI-1
test "CLI distinguishes source errors runtime traps and Usage errors" {
    try invoke("check",
        \\func main() -> i64:
        \\    return 1 +
    , 1, "", "error[E_EXPRESSION]");
    try invoke("check",
        \\func main() -> i64:
        \\    return 9223372036854775807 + 1
    , 0, "", "");
    try invoke("run",
        \\func main() -> i64:
        \\    return 9223372036854775807 + 1
    , 1, "", "error[R_OVERFLOW]");
    try invoke("unknown", "", 2, "", "usage:");
}
// spec: CLI-2
test "CLI missing arguments and missing files are host or usage failures" {
    const no_args = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{compilerPath()} });
    defer testing.allocator.free(no_args.stdout);
    defer testing.allocator.free(no_args.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, no_args.term);
    try testing.expectEqualStrings("", no_args.stdout);
    // A bare `selka` prints the general usage; `selka run` with no file prints run's own.
    try testing.expect(std.mem.startsWith(u8, no_args.stderr, "usage: selka build <file.selka>"));
    const no_file = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "run" } });
    defer testing.allocator.free(no_file.stdout);
    defer testing.allocator.free(no_file.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, no_file.term);
    try testing.expect(std.mem.startsWith(u8, no_file.stderr, "usage: selka run <file.selka>"));
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const absolute_compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
    defer testing.allocator.free(absolute_compiler);
    const absent = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ absolute_compiler, "run", "missing.selka" },
        .cwd = .{ .dir = temp.dir },
    });
    defer testing.allocator.free(absent.stdout);
    defer testing.allocator.free(absent.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, absent.term);
    try testing.expectEqualStrings("", absent.stdout);
    try testing.expectEqualStrings("selka run: cannot read 'missing.selka': no such file or directory\n", absent.stderr);
}
test "CLI binding warnings do not alter status or result output" {
    const text =
        \\func main() -> i64:
        \\    mut unused = 3
        \\    return 7
    ;
    try invoke("run", text, 0, "7\n", "warning[W_UNUSED_BINDING]");
    try invoke("check", text, 0, "", "warning[W_UNUSED_BINDING]");
    try invoke("run",
        \\func main() -> i64:
        \\    mut unused = 9223372036854775807 + 1
        \\    return 7
    , 1, "", "error[R_OVERFLOW]");
    try invoke("run",
        \\func main() -> i64:
        \\    return -9223372036854775808
    , 0, "-9223372036854775808\n", "");
    try invoke("check",
        \\func main() -> i64:
        \\    mut x = True
        \\    x = 1
        \\    return 7
    , 1, "", "error[E_TYPE]");
}
// SP1-F-7: a `File` parameter used only through its methods is read; one the body never touches is still warned.
test "CLI check does not warn that a file parameter used through its method is never read" {
    const used =
        \\func put(f: File, data: bytes) -> int:
        \\    return f.write(data)
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("tmp-f7.txt", "wb") as f:
        \\        _ = put(f, b"hello")
        \\    return 0
    ;
    try invoke("check", used, 0, "", "");
    try invokeOptions("check", used, &.{"--no-cache"}, 0, "", "");
    try invokeOptions("check", used, &.{"--warnings"}, 0, "", "");
    const untouched =
        \\func put(f: File, data: bytes) -> int:
        \\    return len(data)
        \\func main(fs: Filesystem) -> int:
        \\    with fs.open("tmp-f7.txt", "wb") as f:
        \\        _ = put(f, b"hello")
        \\    return 0
    ;
    try invoke("check", untouched, 0, "", ":1:10: warning[W_UNUSED_BINDING]");
}
test "CLI step budgets stop a loop and reject invalid options" {
    const text =
        \\func main() -> i64:
        \\    return 1
    ;
    try invokeOptions("run", text, &.{"--max-steps=2"}, 0, "1\n", "");
    try invokeOptions("run",
        \\func main() -> i64:
        \\    while True:
        \\        pass
        \\    return 1
    , &.{"--max-steps=100"}, 1, "", "error[R_STEP_LIMIT]");
    for ([_][]const u8{ "--max-steps=0", "--max-steps=-1", "--max-steps=+1", "--max-steps=", "--max-steps=abc", "--max-steps=18446744073709551616", "--unknown=1" }) |option| {
        try invokeOptions("run", text, &.{option}, 2, "", "usage:");
    }
    try invokeOptions("run", text, &.{ "--max-steps=2", "--max-steps=3" }, 2, "", "usage:");
    try invokeOptions("check", text, &.{"--max-steps=2"}, 2, "", "usage:");
}
// spec: BUDGET-HINT-1
test "CLI budget traps name the flag that raises the budget" {
    const text =
        \\func main() -> i64:
        \\    while True:
        \\        pass
        \\    return 1
    ;
    try invokeOptions("run", text, &.{"--max-steps=1"}, 1, "", "raise it with --max-steps=N");
    try invokeOptions("run", text, &.{ "--max-steps=1", "--diagnostics=json" }, 1, "", "\"message\":\"instruction budget exhausted; raise it with --max-steps=N\"");
    try invokeOptions("run",
        \\func inner() -> i64:
        \\    return 1
        \\
        \\
        \\func main() -> i64:
        \\    return inner()
    , &.{ "--max-frames=1", "--max-steps=1000000" }, 1, "", "raise it with --max-frames=N");
    try invokeOptions("run",
        \\func inner() -> i64:
        \\    return 1
        \\
        \\
        \\func main() -> i64:
        \\    return inner()
    , &.{ "--max-frames=1", "--max-steps=1000000", "--diagnostics=json" }, 1, "", "\"message\":\"call-depth budget exhausted; raise it with --max-frames=N (each frame reserves 32 KiB of stack, so --max-memory must cover N x 32 KiB)\"");
    const memory =
        \\func main() -> i64:
        \\    mut values: int[] = []
        \\    for r in range(100000000):
        \\        append(mut values, r)
        \\    return len(values)
    ;
    try invokeOptions("run", memory, &.{ "--max-steps=4000000000", "--max-memory=32M" }, 1, "", "error[R_MEMORY_BUDGET]: memory budget exhausted");
}
test "a built program at -o is a read-only second name for the stored file, and a later build replaces it without writing through" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "answer.selka", .data = "func main() -> int:\n    return 3\n" });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "answer.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const first = try std.fs.path.join(testing.allocator, &.{ directory, "first" });
    defer testing.allocator.free(first);
    const second = try std.fs.path.join(testing.allocator, &.{ directory, "second" });
    defer testing.allocator.free(second);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{directory});
    defer testing.allocator.free(cache_argument);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", first, cache_argument, tools[0] }, "");
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", second, cache_argument, tools[0] }, "");
    // Two outputs of one program are names of one file, and the stored program is a third; none can be written to.
    const one = try temporary.dir.statFile(testing.io, "first", .{});
    const two = try temporary.dir.statFile(testing.io, "second", .{});
    try testing.expectEqual(one.inode, two.inode);
    try testing.expect(one.nlink >= 3);
    try testing.expect(one.permissions.readOnly());
    try testing.expectEqual(@as(u8, 3), try exitStatus(first));
    // An edit builds a different program over `first`: the old file stays what `second` and the store hold.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "answer.selka", .data = "func main() -> int:\n    return 4\n" });
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", first, cache_argument, tools[0] }, "");
    try testing.expectEqual(@as(u8, 4), try exitStatus(first));
    try testing.expectEqual(@as(u8, 3), try exitStatus(second));
    try testing.expect((try temporary.dir.statFile(testing.io, "first", .{})).inode != (try temporary.dir.statFile(testing.io, "second", .{})).inode);
    // Reverting finds the stored program again and links it back.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "answer.selka", .data = "func main() -> int:\n    return 3\n" });
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", first, cache_argument, tools[0] }, "");
    try testing.expectEqual(@as(u8, 3), try exitStatus(first));
    try testing.expectEqual((try temporary.dir.statFile(testing.io, "first", .{})).inode, (try temporary.dir.statFile(testing.io, "second", .{})).inode);
}

/// The exit status of the program at `path`.
fn exitStatus(path: []const u8) !u8 {
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{path} });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    return switch (result.term) {
        .exited => |code| code,
        else => error.TestUnexpectedResult,
    };
}

// spec: QBE-FRAME-ACCOUNTING-2
test "an executable built without a frame ceiling refuses a runtime frame budget" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "depth.selka", .data =
        \\func main() -> i64:
        \\    return 0
    });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "depth.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const output = try std.fs.path.join(testing.allocator, &.{ directory, "depth-bin" });
    defer testing.allocator.free(output);
    const cache = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);
    // A built executable carries no call-depth accounting.
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", output, cache_argument, tools[0] }, "");
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
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "selka run --max-frames=N") != null);
    // The executable still runs without any ceiling argument, and `run` compiles
    // the accounting in and enforces the same ceiling.
    try expectConstantProcess(&.{output}, "");
    try invokeOptions("run", "func inner() -> i64:\n    return 0\n\n\nfunc main() -> i64:\n    return inner()\n", &.{"--max-frames=1"}, 1, "", "error[R_FRAME_LIMIT]");
}
/// Build `name` as a debug and as a `--release` executable and run both; then run
/// it through `selka run` with and without a frame ceiling. Each pair must
/// report the same bytes and exit status 1, and the executable's report must be
/// `expected` with `{path}` standing for the entry's absolute path. While release
/// builds are off only the debug half runs, and the calling test ends with `requireRelease()`.
fn expectHaltedTrapIdentical(temporary: *testing.TmpDir, name: []const u8, source: []const u8, expected: []const u8) !void {
    const a = testing.allocator;
    const file = try std.fmt.allocPrint(a, "{s}.selka", .{name});
    defer a.free(file);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = file, .data = source });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, file, a);
    defer a.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const cache_argument = try std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{directory});
    defer a.free(cache_argument);
    const fast = try std.fmt.allocPrint(a, "{s}/{s}-debug", .{ directory, name });
    defer a.free(fast);
    const framed = try std.fmt.allocPrint(a, "{s}/{s}-release", .{ directory, name });
    defer a.free(framed);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", fast, cache_argument, tools[0] }, "");
    const wanted = try std.mem.replaceOwned(u8, a, expected, "{path}", entry);
    defer a.free(wanted);
    const halted = try std.process.run(a, testing.io, .{ .argv = &.{fast} });
    defer a.free(halted.stdout);
    defer a.free(halted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, halted.term);
    try testing.expectEqualStrings("", halted.stdout);
    try testing.expectEqualStrings(wanted, halted.stderr);
    // `selka run` compiles a frame ceiling's accounting in; both report the trap the same way.
    const run_fast = try std.process.run(a, testing.io, .{ .argv = &.{ compilerPath(), "run", entry, cache_argument, tools[0] } });
    defer a.free(run_fast.stdout);
    defer a.free(run_fast.stderr);
    const run_framed = try std.process.run(a, testing.io, .{ .argv = &.{ compilerPath(), "run", entry, cache_argument, tools[0], "--max-frames=100000" } });
    defer a.free(run_framed.stdout);
    defer a.free(run_framed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, run_fast.term);
    try testing.expectEqual(run_fast.term, run_framed.term);
    try testing.expect(std.mem.indexOf(u8, run_fast.stderr, wanted[0 .. std.mem.indexOfScalar(u8, wanted, '\n') orelse wanted.len]) != null);
    try testing.expectEqualStrings(run_fast.stderr, run_framed.stderr);
    if (releaseOff()) return;
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", framed, "--release", cache_argument, tools[0] }, "");
    const sticky = try std.process.run(a, testing.io, .{ .argv = &.{framed} });
    defer a.free(sticky.stdout);
    defer a.free(sticky.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, sticky.term);
    try testing.expectEqualStrings(halted.stderr, sticky.stderr);
}
/// Build `name` with `--release` — whole-program LLVM with LTO, which is free to
/// inline guest functions into one another — and as the default debug build, run
/// each, and require exit status 1 and exactly `expected` on stderr from both,
/// `{path}` standing for the entry's absolute path. While release builds are off only the
/// debug half runs, and the calling test ends with `requireRelease()`.
fn expectFrameMapTrap(temporary: *testing.TmpDir, name: []const u8, source: []const u8, expected: []const u8) !void {
    const a = testing.allocator;
    const file = try std.fmt.allocPrint(a, "{s}.selka", .{name});
    defer a.free(file);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = file, .data = source });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, file, a);
    defer a.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const cache_argument = try std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{directory});
    defer a.free(cache_argument);
    const wanted = try std.mem.replaceOwned(u8, a, expected, "{path}", entry);
    defer a.free(wanted);
    const release = try std.fmt.allocPrint(a, "{s}/{s}-release", .{ directory, name });
    defer a.free(release);
    const debug = try std.fmt.allocPrint(a, "{s}/{s}-debug", .{ directory, name });
    defer a.free(debug);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", debug, cache_argument, tools[0] }, "");
    try expectErrorReport(debug, wanted);
    if (releaseOff()) return;
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", release, "--release", cache_argument, tools[0] }, "");
    try expectErrorReport(release, wanted);
}
test "a frame-map trap names every logical frame an inlined callee, a callback, a runtime helper or recursion passes through" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    // The release build inlines `a` into the loop in `total`; its frame is still reported.
    try expectFrameMapTrap(&temporary, "inlined",
        \\# a trap inside a small callee LLVM inlines into a loop
        \\
        \\
        \\func a(i: int, j: int) -> float:
        \\    return 1.0 / float((i + j) * (i + j + 1) // 2 + i + 1)
        \\
        \\
        \\func total(n: int, start: int) -> float:
        \\    mut s = 0.0
        \\    for i in range(n):
        \\        s = s + a(start + i, 9223372036854775000)
        \\    return s
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, int(total(10, 1)))
        \\    return 0
    ,
        \\{path}:5:32: error[R_OVERFLOW]: native execution failed (mul: left 9223372036854775001, right 9223372036854775002, width 64)
        \\  in a at {path}:5:32
        \\  in total at {path}:11:17
        \\  in main at {path}:16:20
        \\
    ++ "\x1eSELKA-TRAP {\"version\":1,\"operation\":\"mul\",\"left\":9223372036854775001,\"right\":9223372036854775002,\"width\":64}\n");
    // An assertion's message still comes from the innermost frame's position.
    try expectFrameMapTrap(&temporary, "callback",
        \\# an assertion inside a key function called back by sorted
        \\
        \\
        \\func key_of(x: int) -> int:
        \\    assert x != 3, "no threes"
        \\    return 0 - x
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut ordered = sorted([5, 4, 3, 2, 1], key=key_of)
        \\    print(out, ordered[0])
        \\    return 0
    ,
        \\{path}:5:12: error[R_ASSERT]: native execution failed: no threes (left 3, right 3)
        \\  in key_of at {path}:5:12
        \\  in main at {path}:10:19
        \\
    ++ "\x1eSELKA-TRAP {\"version\":1,\"operation\":\"no threes (left 3, right 3)\"}\n");
    // The runtime helper traps inside itself; the frame is its call site.
    try expectFrameMapTrap(&temporary, "helper",
        \\# a conversion the runtime helper refuses, two frames deep
        \\
        \\
        \\func convert(x: float) -> int:
        \\    return int(x * 1e300 * 1e300)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut total = 0
        \\    for i in range(3):
        \\        total = total + convert(float(i) + 0.5)
        \\    print(out, total)
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
        \\{path}:7:16: error[R_FRAME_LIMIT]: call-depth limit reached: the native stack is full (a built binary has no --max-frames budget); raise the stack with `ulimit -s KBYTES` before starting it, or run it under `selka run --max-frames=N` (each frame reserves 32 KiB of stack, so --max-memory must cover N x 32 KiB)
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
        \\func descend(depth: int) -> int:
        \\    if depth == 0:
        \\        return 0
        \\    return 1 + descend(depth - 1)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, descend(1000000000))
        \\    return 0
    , recursion_trace);
    try requireRelease();
}
test "a trap through a halting failure path reports the same code, trace, record and status" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    // A checked add that overflows three frames deep.
    try expectHaltedTrapIdentical(&temporary, "overflow",
        \\# an overflow three frames deep
        \\
        \\
        \\func grow(x: int, step: int) -> int:
        \\    return x + step
        \\
        \\
        \\func climb(x: int) -> int:
        \\    mut total = x
        \\    for i in range(10):
        \\        total = grow(total, 1000000000000000000)
        \\    return total
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, climb(1))
        \\    return 0
    ,
        \\{path}:5:14: error[R_OVERFLOW]: native execution failed (add: left 9000000000000000001, right 1000000000000000000, width 64)
        \\  in grow at {path}:5:14
        \\  in climb at {path}:11:17
        \\  in main at {path}:16:16
        \\
    ++ "\x1eSELKA-TRAP {\"version\":1,\"operation\":\"add\",\"left\":9000000000000000001,\"right\":1000000000000000000,\"width\":64}\n");
    // An out-of-range list write after a loop that succeeded.
    try expectHaltedTrapIdentical(&temporary, "index",
        \\# an out-of-range list write after a successful loop
        \\
        \\
        \\func poke(mut xs: int[], at: int) -> Unit:
        \\    xs[at] = 7
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut xs: int[] = [1, 2, 3]
        \\    mut total = 0
        \\    for x in xs:
        \\        total = total + x
        \\    poke(mut xs, total)
        \\    print(out, total)
        \\    return 0
    ,
        \\{path}:5:5: error[R_LIST_BOUNDS]: native execution failed (index 6, length 3)
        \\  in poke at {path}:5:5
        \\  in main at {path}:13:5
        \\
    ++ "\x1eSELKA-TRAP {\"version\":1,\"operation\":\"index\",\"index\":6,\"length\":3}\n");
    try requireRelease();
}
/// Checked `+ - *` at every width, operands and width from the command line:
/// `WIDTH OP X Y` prints `X OP Y` computed in that width, three frames deep.
const checked_arithmetic_program =
    \\# checked + - * at every width, operands from the command line
    \\
    \\
    \\func number(text: str) -> int:
    \\    match parse_int(text):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\
    \\
    \\func wide(x: int) -> u64:
    \\    if x >= 0:
    \\        return u64(x)
    \\    return u64(x + 9223372036854775807 + 1) + 9223372036854775808u64
    \\
    \\
    \\func signed64(op: str, x: int, y: int) -> int:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\func unsigned64(op: str, x: u64, y: u64) -> u64:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\func signed32(op: str, x: i32, y: i32) -> i32:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\func unsigned32(op: str, x: u32, y: u32) -> u32:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\func signed16(op: str, x: i16, y: i16) -> i16:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\func unsigned16(op: str, x: u16, y: u16) -> u16:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\func signed8(op: str, x: i8, y: i8) -> i8:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\func unsigned8(op: str, x: u8, y: u8) -> u8:
    \\    if op == "add":
    \\        return x + y
    \\    if op == "sub":
    \\        return x - y
    \\    return x * y
    \\
    \\
    \\func report(out: Stream, args: str[]) -> int:
    \\    mut width = copy(args[0])
    \\    mut op = copy(args[1])
    \\    mut x = number(args[2])
    \\    mut y = number(args[3])
    \\    if width == "i64":
    \\        print(out, signed64(op, x, y))
    \\    if width == "u64":
    \\        print(out, unsigned64(op, wide(x), wide(y)))
    \\    if width == "i32":
    \\        print(out, signed32(op, i32(x), i32(y)))
    \\    if width == "u32":
    \\        print(out, unsigned32(op, u32(x), u32(y)))
    \\    if width == "i16":
    \\        print(out, signed16(op, i16(x), i16(y)))
    \\    if width == "u16":
    \\        print(out, unsigned16(op, u16(x), u16(y)))
    \\    if width == "i8":
    \\        print(out, signed8(op, i8(x), i8(y)))
    \\    if width == "u8":
    \\        print(out, unsigned8(op, u8(x), u8(y)))
    \\    return 0
    \\
    \\
    \\func main(args: str[], out: Stream) -> int:
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
/// Run `WIDTH OP X Y` through the release and the debug binary and require the
/// same status, stdout and stderr from both; returns the release run's stderr.
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
/// extreme in both builds, and the next one traps there with the same
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
test "checked arithmetic at every width reports the same result and trap from a release build as from a debug build" {
    const a = testing.allocator;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "checked.selka", .data = checked_arithmetic_program });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "checked.selka", a);
    defer a.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const cache_argument = try std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{directory});
    defer a.free(cache_argument);
    const release = try std.fmt.allocPrint(a, "{s}/checked-release", .{directory});
    defer a.free(release);
    const debug = try std.fmt.allocPrint(a, "{s}/checked-debug", .{directory});
    defer a.free(debug);
    // The release build (whole-program LLVM with LTO) lowers the checks to the
    // overflow intrinsics and optimizes around them; the debug build is the reference.
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", debug, cache_argument, tools[0] }, "");
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", release, "--release", cache_argument, tools[0] }, "");
    try expectCheckedBoundaries(.{ release, debug });
    // One trap in full: code, detail, the three frames and the record.
    const trapped = try expectSameBoundary(.{ release, debug }, .{ "i64", "add", "9223372036854775806", "2" }, 1, "");
    defer a.free(trapped);
    const expected =
        \\{path}:20:18: error[R_OVERFLOW]: native execution failed (add: left 9223372036854775806, right 2, width 64)
        \\  in signed64 at {path}:20:18
        \\  in report at {path}:88:20
        \\  in main at {path}:107:12
        \\
    ++ "\x1eSELKA-TRAP {\"version\":1,\"operation\":\"add\",\"left\":9223372036854775806,\"right\":2,\"width\":64}\n";
    const wanted = try std.mem.replaceOwned(u8, a, expected, "{path}", entry);
    defer a.free(wanted);
    try testing.expectEqualStrings(wanted, trapped);
}
/// Literal +/-1 operands retain their exact overflow details and cleanup.
const literal_overflow_program =
    \\func number(text: str) -> int:
    \\    match parse_int(text):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\
    \\
    \\func calculate(form: str, value: int) -> int:
    \\    if form == "add_one":
    \\        return value + 1
    \\    if form == "sub_one":
    \\        return value - 1
    \\    if form == "add_negative":
    \\        return value + -1
    \\    return value - -1
    \\
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    print(out, calculate(args[0], number(args[1])))
    \\    return 0
;

/// Exercise all four literal bounds, then their opposite safe extreme.
fn expectLiteralBoundaries(binaries: [2][]const u8) !void {
    const rows = [_][5][]const u8{
        .{ "add_one", "9223372036854775806", "9223372036854775807", "-9223372036854775808", "-9223372036854775807" },
        .{ "sub_one", "-9223372036854775807", "-9223372036854775808", "9223372036854775807", "9223372036854775806" },
        .{ "add_negative", "-9223372036854775807", "-9223372036854775808", "9223372036854775807", "9223372036854775806" },
        .{ "sub_negative", "9223372036854775806", "9223372036854775807", "-9223372036854775808", "-9223372036854775807" },
    };
    const a = testing.allocator;
    for (rows) |row| {
        const output = try std.fmt.allocPrint(a, "{s}\n", .{row[2]});
        defer a.free(output);
        const quiet = try expectSameBoundary(binaries, .{ row[0], row[1], "", "" }, 0, output);
        defer a.free(quiet);
        try testing.expectEqualStrings("", quiet);
        const trapped = try expectSameBoundary(binaries, .{ row[0], row[2], "", "" }, 1, "");
        defer a.free(trapped);
        try testing.expect(std.mem.indexOf(u8, trapped, "error[R_OVERFLOW]") != null);
        try testing.expect(std.mem.indexOf(u8, trapped, "SELKA-TRAP ") != null);
        const opposite = try std.fmt.allocPrint(a, "{s}\n", .{row[4]});
        defer a.free(opposite);
        const quiet_opposite = try expectSameBoundary(binaries, .{ row[0], row[3], "", "" }, 0, opposite);
        defer a.free(quiet_opposite);
        try testing.expectEqualStrings("", quiet_opposite);
    }
}

test "literal signed overflow preserves exact QBE output trap details traces and records" {
    const a = testing.allocator;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "literal.selka", .data = literal_overflow_program });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "literal.selka", a);
    defer a.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const cache = try std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{directory});
    defer a.free(cache);
    const llvm = try std.fmt.allocPrint(a, "{s}/literal-llvm", .{directory});
    defer a.free(llvm);
    const qbe = try std.fmt.allocPrint(a, "{s}/literal-qbe", .{directory});
    defer a.free(qbe);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", qbe, cache, tools[0] }, "");
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", llvm, "--release", cache, tools[0] }, "");
    try expectLiteralBoundaries(.{ llvm, qbe });
}

const sticky_reduction_program =
    \\# checked reductions in loops, operands from the command line
    \\import buffers
    \\
    \\
    \\func number(text: str) -> int:
    \\    match parse_int(text):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\
    \\
    \\func build(n: int, value: int, last: int) -> int[]:
    \\    mut values: int[] = []
    \\    for i in range(n):
    \\        append(mut values, value)
    \\    append(mut values, last)
    \\    return values
    \\
    \\
    \\func total_of(values: int[], start: int) -> int:
    \\    mut total = start
    \\    for v in values:
    \\        total += v
    \\    return total
    \\
    \\
    \\func indexed(values: int[], start: int) -> int:
    \\    mut total = start
    \\    for i in range(len(values)):
    \\        total = total + values[i]
    \\    return total
    \\
    \\
    \\func scaled(values: int[], start: int) -> int:
    \\    mut total = start
    \\    for v in values:
    \\        total += v * 3
    \\    return total
    \\
    \\
    \\func difference(values: int[], start: int) -> int:
    \\    mut total = start
    \\    for v in values:
    \\        total -= v
    \\    return total
    \\
    \\
    \\func count_of(values: int[], start: int) -> int:
    \\    mut count = start
    \\    for v in values:
    \\        if v == 109:
    \\            count += 1
    \\    return count
    \\
    \\
    \\func octets(n: int, start: int) -> int:
    \\    mut empty: int[] = []
    \\    mut buffer = byte_buffer(empty)
    \\    for i in range(n):
    \\        _ = buffers.append_byte(mut buffer, 109)
    \\        _ = buffers.append_byte(mut buffer, 7)
    \\    mut data = bytes(buffer)
    \\    mut count = start
    \\    for i in range(len(data)):
    \\        if data[i] == 109:
    \\            count += 1
    \\    return count
    \\
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    mut kind = copy(args[0])
    \\    mut n = number(args[1])
    \\    mut value = number(args[2])
    \\    mut last = number(args[3])
    \\    mut start = number(args[4])
    \\    mut values = build(n, value, last)
    \\    if kind == "sum":
    \\        print(out, total_of(values, start))
    \\    if kind == "indexed":
    \\        print(out, indexed(values, start))
    \\    if kind == "scaled":
    \\        print(out, scaled(values, start))
    \\    if kind == "difference":
    \\        print(out, difference(values, start))
    \\    if kind == "count":
    \\        print(out, count_of(values, start))
    \\    if kind == "octets":
    \\        print(out, octets(n, start))
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
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", llvm, cache_argument, tools[0] }, "");
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", qbe, cache_argument, tools[0] }, "");
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
test "checked reduction loops sum and trap the same from the LLVM fast copy as from QBE" {
    const a = testing.allocator;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const built = try buildBothBackends(&temporary, "reductions.selka", sticky_reduction_program);
    defer built.deinit();
    try expectReductionCases(built.binaries());
    // One trap in full: the update that overflows is the third, with the
    // running total and the element it adds, in the loop's own function.
    const trapped = try expectSameRun(built.binaries(), &.{ "sum", "3", "9223372036854775807", "1", "0" }, 1);
    defer a.free(trapped);
    const expected =
        \\{path}:24:15: error[R_OVERFLOW]: native execution failed (add: left 9223372036854775807, right 9223372036854775807, width 64)
        \\  in reductions::total_of at {path}:24:15
        \\  in reductions::main at {path}:79:20
        \\
    ++ "\x1eSELKA-TRAP {\"version\":1,\"operation\":\"add\",\"left\":9223372036854775807,\"right\":9223372036854775807,\"width\":64}\n";
    const wanted = try std.mem.replaceOwned(u8, a, expected, "{path}", "reductions.selka");
    defer a.free(wanted);
    try testing.expectEqualStrings(wanted, trapped);
}
const element_loops_program =
    \\# element loops over lists, nested lists, records in lists and bytes; sizes from the command line
    \\import buffers
    \\
    \\
    \\record Body:
    \\    x: float
    \\    v: float
    \\
    \\
    \\func number(text: str) -> int:
    \\    match parse_int(text):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\
    \\
    \\func dot(a: float[], b: float[]) -> float:
    \\    mut s = 0.0
    \\    for i in range(len(a)):
    \\        s = s + a[i] * b[i]
    \\    return s
    \\
    \\
    \\func product(n: int) -> float:
    \\    mut a: float[][] = []
    \\    for i in range(n):
    \\        mut a_row: float[] = []
    \\        for j in range(n):
    \\            append(mut a_row, float(i + j))
    \\        append(mut a, own a_row)
    \\    mut b: float[][] = []
    \\    for i in range(n):
    \\        mut b_row: float[] = []
    \\        for j in range(n):
    \\            append(mut b_row, float(i * j % 7))
    \\        append(mut b, own b_row)
    \\    mut c: float[][] = []
    \\    for i in range(n):
    \\        mut c_row: float[] = []
    \\        for j in range(n):
    \\            append(mut c_row, 0.0)
    \\        append(mut c, own c_row)
    \\    for i in range(n):
    \\        for k in range(n):
    \\            mut aik = a[i][k]
    \\            for j in range(n):
    \\                c[i][j] = c[i][j] + aik * b[k][j]
    \\    mut total = 0.0
    \\    for i in range(n):
    \\        for j in range(n):
    \\            total = total + c[i][j]
    \\    return total
    \\
    \\
    \\func advance(mut bodies: Body[], steps: int) -> Unit:
    \\    for s in range(steps):
    \\        for i in range(len(bodies)):
    \\            bodies[i].x = bodies[i].x + bodies[i].v
    \\            bodies[i].v = bodies[i].v * 0.5
    \\
    \\
    \\func scan(n: int) -> int:
    \\    mut empty: int[] = []
    \\    mut buffer = byte_buffer(empty)
    \\    for i in range(n):
    \\        _ = buffers.append_byte(mut buffer, i % 256)
    \\    mut data = bytes(buffer)
    \\    mut count = 0
    \\    for i in range(len(data)):
    \\        if data[i] == 109:
    \\            count += 1
    \\    return count
    \\
    \\
    \\func prefix(values: int[], at: int) -> int:
    \\    mut total = 0
    \\    for i in range(at):
    \\        total += values[i]
    \\    return total
    \\
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = number(args[0])
    \\    mut at = number(args[1])
    \\    print(out, int(product(n)))
    \\    mut bodies: Body[] = []
    \\    for i in range(n):
    \\        append(mut bodies, Body(x=float(i), v=1.0))
    \\    advance(mut bodies, 10)
    \\    print(out, int(bodies[n - 1].x * 1000.0))
    \\    print(out, scan(n * 100))
    \\    mut values: int[] = []
    \\    for i in range(n):
    \\        append(mut values, i * 3)
    \\    mut dot_left: float[] = []
    \\    for v in values:
    \\        append(mut dot_left, float(v))
    \\    mut dot_right: float[] = []
    \\    for v in values:
    \\        append(mut dot_right, 1.5)
    \\    print(out, int(dot(dot_left, dot_right)))
    \\    print(out, prefix(values, at))
    \\    return 0
;
test "element loops over lists, nested lists, records and bytes compute and trap the same from LLVM as from QBE" {
    const a = testing.allocator;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const built = try buildBothBackends(&temporary, "elements.selka", element_loops_program);
    defer built.deinit();
    const quiet = try expectSameRun(built.binaries(), &.{ "20", "20" }, 0);
    defer a.free(quiet);
    try testing.expectEqualStrings("", quiet);
    // One past the end of the list traps in the loop that reads it.
    const trapped = try expectSameRun(built.binaries(), &.{ "20", "21" }, 1);
    defer a.free(trapped);
    try testing.expect(std.mem.indexOf(u8, trapped, "error[R_LIST_BOUNDS]: native execution failed (index 20, length 20)") != null);
    try testing.expect(std.mem.indexOf(u8, trapped, "  in elements::prefix at ") != null);
}
/// Loops LLVM vectorizes once their checks are proven (`QBE-LOOP-VERSION-1`):
/// a byte count and a row update, sized and shifted from the command line.
const vector_loops_program =
    \\import strings
    \\
    \\func number(text: str) -> int:
    \\    match parse_int(text):
    \\        case Some(value):
    \\            return value
    \\        case None:
    \\            return 0
    \\
    \\
    \\func scan(data: bytes) -> int:
    \\    mut count = 0
    \\    for i in range(len(data)):
    \\        if data[i] == 115:
    \\            count += 1
    \\    return count
    \\
    \\
    \\func axpy(mut c: float[], b: float[], a: float, shift: int) -> Unit:
    \\    for j in range(len(c)):
    \\        c[j] = c[j] + a * b[j + shift]
    \\
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    mut n = number(args[0])
    \\    mut text = ""
    \\    for i in range(n):
    \\        text = text + "selka "
    \\    mut b: float[] = []
    \\    for i in range(n):
    \\        append(mut b, float(i))
    \\    mut c: float[] = []
    \\    for i in range(n):
    \\        append(mut c, 1.0)
    \\    axpy(mut c, b, 0.5, number(args[1]))
    \\    mut total = 0.0
    \\    for x in c:
    \\        total = total + x
    \\    print(out, scan(strings.encode(text)))
    \\    print(out, int(total))
    \\    return 0
;
test "versioned loops LLVM vectorizes compute and trap exactly as QBE does" {
    const a = testing.allocator;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "vector.selka", .data = vector_loops_program });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "vector.selka", a);
    defer a.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const cache_argument = try std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{directory});
    defer a.free(cache_argument);
    const llvm = try std.fmt.allocPrint(a, "{s}/vector-llvm", .{directory});
    defer a.free(llvm);
    const qbe = try std.fmt.allocPrint(a, "{s}/vector-qbe", .{directory});
    defer a.free(qbe);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", llvm, cache_argument, tools[0] }, "");
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", qbe, cache_argument, tools[0] }, "");
    // Every index proven: 1000 words of "selka ", and 1000 + 0.5 * (0 + ... + 999).
    const quiet = try expectSameBoundary(.{ llvm, qbe }, .{ "1000", "0", "", "" }, 0, "1000\n250750\n");
    defer a.free(quiet);
    try testing.expectEqualStrings("", quiet);
    // `b[j + 1]` fails the guard, so the original loop traps at its last row.
    const trapped = try expectSameBoundary(.{ llvm, qbe }, .{ "1000", "1", "", "" }, 1, "");
    defer a.free(trapped);
    try testing.expect(std.mem.indexOf(u8, trapped, "index 1000, length 1000") != null);
    // The program imports `strings` for `strings.encode` (W13-S5), so its functions carry its module's name.
    try testing.expect(std.mem.indexOf(u8, trapped, "  in vector::axpy at ") != null);
}
test "an executable built without a requested ceiling refuses a runtime step budget" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "budget.selka", .data =
        \\func main() -> i64:
        \\    return 0
    });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "budget.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const output = try std.fs.path.join(testing.allocator, &.{ directory, "budget-bin" });
    defer testing.allocator.free(output);
    const cache = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);
    // A built executable carries no step accounting.
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", output, cache_argument, tools[0] }, "");
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
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "selka run --max-steps=N") != null);
    // Asking `run` for the same ceiling compiles the accounting and enforces it.
    try invokeOptions("run", "func main() -> i64:\n    while True:\n        pass\n    return 0\n", &.{"--max-steps=1"}, 1, "", "error[R_STEP_LIMIT]");
}
// spec: CLI-3
test "CLI executes the exact plan acceptance programs and recursive functions" {
    try invoke("run", @embedFile("fixtures/sum.selka"), 0, "4950\n", "");
    try invoke("run", @embedFile("fixtures/gcd.selka"), 0, "6\n", "");
    try invoke("run",
        \\func fact(n: i64) -> i64:
        \\    if n <= 1:
        \\        return 1
        \\    return n * fact(n - 1)
        \\
        \\
        \\func main() -> i64:
        \\    return fact(10)
    , 0, "3628800\n", "");
    try invoke("run",
        \\func main() -> i64:
        \\    return 1 + add(add(2, 3), add(4, 5))
        \\
        \\
        \\func add(a: i64, b: i64) -> i64:
        \\    return a + b
    , 0, "15\n", "");
    try invoke("run",
        \\func main() -> i64:
        \\    return bad()
        \\
        \\
        \\func bad() -> i64:
        \\    return divtrunc(1, 0)
    , 1, "", "in main at");
}
test "CLI frame budgets count main and reject invalid overrides" {
    const text =
        \\func main() -> i64:
        \\    return f()
        \\
        \\
        \\func f() -> i64:
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
}
test "all commands reject invalid programs before execution and locate runtime traps" {
    for ([_][]const u8{ "check", "run" }) |command| {
        try invoke(command, @embedFile("fixtures/rejected.selka"), 1, "", ":2:12: error[E_UNKNOWN_NAME]");
        try invoke(command,
            \\func main() -> bool:
            \\    return True
        , 1, "", "error[E_TYPE]");
    }
    // An empty file has no entry point: `run` rejects it, while
    // `check` accepts it as an empty library (CHECK-LIBRARY-2).
    try invoke("run", "", 1, "", "error[E_MAIN]");
    try invoke("check", @embedFile("fixtures/trap.selka"), 0, "", "");
    try invoke("run", @embedFile("fixtures/trap.selka"), 1, "", ":2:9: error[R_DIVISION_BY_ZERO]");
}
test "oversized source is a host resource failure with no result output" {
    const text = try testing.allocator.alloc(u8, 16 * 1024 * 1024 + 1);
    defer testing.allocator.free(text);
    @memset(text, ' ');
    try invoke("run", text, 2, "", "host failure:");
}
test "duplicate discovery is separate advisory analysis with explicit options" {
    const source =
        \\func a(n: i64) -> i64:
        \\    return n * 2 + 1
        \\
        \\
        \\func b(x: i64) -> i64:
        \\    return x * 2 + 1
        \\
        \\
        \\func main() -> i64:
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
        \\func main() -> i64:
        \\    return unknown
    , 1, "", "error[E_UNKNOWN_NAME]");
    for ([_][]const u8{ "--min-nodes=0", "--min-nodes=", "--min-nodes=-1", "--population=unknown", "--max-steps=10" }) |option| {
        try invokeOptions("discover-duplicates", source, &.{option}, 2, "", "usage:");
    }
    try invokeOptions("discover-duplicates", source, &.{ "--min-nodes=1", "--min-nodes=2" }, 2, "", "usage:");
    try invokeOptions("check", source, &.{"--min-nodes=1"}, 2, "", "usage:");
}
test "CLI checks runs and dumps records and declared complete conversions" {
    try invoke("run", @embedFile("fixtures/records.selka"), 0, "12\n", "");
    try invoke("run", @embedFile("fixtures/conversions.selka"), 0, "11\n", "");
    try invoke("check", @embedFile("fixtures/conversions.selka"), 0, "", "");
    const incomplete =
        \\record Source:
        \\    x: i64
        \\    added: bool
        \\
        \\
        \\record View:
        \\    y: i64
        \\
        \\
        \\conversion func convert(src: Source) -> View:
        \\    return View(y=src.x)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| {
        try invoke(command, incomplete, 1, "", "error[E_INCOMPLETE_CONVERSION]");
    }
}
test "CLI checks resource ownership completion and implicit cleanup effects without ambient access" {
    const source = @embedFile("fixtures/resources.selka");
    try invoke("check", source, 0, "", "");
    try invokeOptions("run", source, &.{"--restrict"}, 2, "", "--restrict is active");
    const invalid =
        \\resource File: filesystem
        \\
        \\
        \\record Wrapper:
        \\    file: File
        \\
        \\
        \\func cleanup(input: Wrapper) -> i64 noio:
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_EFFECTS_REMOVED]");
}
test "CLI checks resource data operations effects and required mutation without ambient providers" {
    const source = @embedFile("fixtures/resource-io.selka");
    try invoke("check", source, 0, "", "");
    try invokeOptions("run", source, &.{"--restrict"}, 2, "", "--restrict is active");
    // A match arm binds its payload immutably, so writing through that binding still needs mutation.
    // migrate-embedded: skip -- exact original effect-clause rejection witness.
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
        \\func write_once(fs: Filesystem) -> i64 effects(filesystem):
        \\    mut request: FixedArray[u8, 1] = FixedArray[u8, 1]([42u8])
        \\    match acquire_resource[Open](fs, request):
        \\        case ok(file):
        \\            mut payload: FixedArray[u8, 1] = FixedArray[u8, 1]([7u8])
        \\            _ = write_resource[Written](file, payload)
        \\            return 0
        \\        case err(code):
        \\            return code
        \\
        \\
        \\func main(fs: Filesystem) -> i64:
        \\    return write_once(fs)
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_EFFECTS_REMOVED]");
    const readonly_payload = try std.mem.replaceOwned(u8, testing.allocator, invalid, " effects(filesystem)", "");
    defer testing.allocator.free(readonly_payload);
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| try invoke(command, readonly_payload, 1, "", "error[E_IMMUTABLE]");
}
test "CLI approximate discovery is advisory explains drift and reports budget exhaustion" {
    const source =
        \\func a(x: i64) -> i64:
        \\    return x * 2 + 1
        \\
        \\
        \\func b(x: i64) -> i64:
        \\    return x * 2 + 3
        \\
        \\
        \\func main() -> i64:
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
        \\func helper(x: i64) -> i64:
        \\    return x
        \\
        \\
        \\func main() -> i64:
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
        \\func main() -> i64:
        \\    return False
    , 1, "", "error[E_TYPE]");
}
test "CLI formatter supports stdout check mode and syntax-only formatting" {
    // `fmt` writes canonical bytes to stdout; `--check` is nonzero when the
    // input differs from that canonical form.
    const canonical =
        \\func main() -> i64:
        \\    return 7
        \\
    ;
    try invoke("fmt", canonical, 0, canonical, "");
    try invokeOptions("fmt", canonical, &.{"--check"}, 0, "", "");
    const spaced =
        \\func  main( ) ->  i64 :
        \\        return   7
    ;
    try invoke("fmt", spaced, 0, canonical, "");
    try invokeOptions("fmt", spaced, &.{"--check"}, 1, "", "formatting differs");
    try invoke("fmt",
        \\func main() -> i64:
        \\    return False
    , 0,
        \\func main() -> i64:
        \\    return False
        \\
    , "");
    try invoke("fmt",
        \\func main() -> i64:
        \\    return +
    , 1, "", "error[E_EXPRESSION]");
    try invokeOptions("fmt", canonical, &.{ "--check", "--check" }, 2, "", "usage:");
    try invokeOptions("check", canonical, &.{"--check"}, 2, "", "usage:");
}
// F-S1a-10: `(a and b,)` is a one-element tuple, so the formatter must not write it.
test "CLI formatter lays a multi-line parenthesized expression out so that it still parses" {
    const spread =
        \\func both(a: bool, b: bool) -> bool:
        \\    return (
        \\        a
        \\        and b
        \\    )
        \\
        \\
        \\func main() -> int:
        \\    return 0
        \\
    ;
    const canonical =
        \\func both(a: bool, b: bool) -> bool:
        \\    return (
        \\        a and b
        \\    )
        \\
        \\
        \\func main() -> int:
        \\    return 0
        \\
    ;
    try invoke("fmt", spread, 0, canonical, "");
    try invokeOptions("fmt", canonical, &.{"--check"}, 0, "", "");
    try invokeOptions("fmt", spread, &.{"--check"}, 1, "", "formatting differs");
}
// spec: FMT-WRITE-1
test "CLI formatter replaceFile writes in place and prints a unified diff" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const spaced = "func  main( ) ->  i64:\n        return   7\n";
    const canonical = "func main() -> i64:\n    return 7\n";
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data = spaced });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.selka", testing.allocator);
    defer testing.allocator.free(path);
    const written = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "fmt", path, "--write" } });
    defer testing.allocator.free(written.stdout);
    defer testing.allocator.free(written.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, written.term);
    try testing.expectEqualStrings("", written.stdout);
    try testing.expectEqualStrings("", written.stderr);
    const bytes = try temp.dir.readFileAlloc(testing.io, "input.selka", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(bytes);
    try testing.expectEqualStrings(canonical, bytes);

    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data = spaced });
    const diffed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "fmt", path, "--diff" } });
    defer testing.allocator.free(diffed.stdout);
    defer testing.allocator.free(diffed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, diffed.term);
    try testing.expect(std.mem.indexOf(u8, diffed.stdout, "-func  main( ) ->  i64:") != null);
    try testing.expect(std.mem.indexOf(u8, diffed.stdout, "+func main() -> i64:") != null);
    try testing.expectEqualStrings("", diffed.stderr);

    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data = canonical });
    const clean = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "fmt", path, "--diff" } });
    defer testing.allocator.free(clean.stdout);
    defer testing.allocator.free(clean.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, clean.term);
    try testing.expectEqualStrings("", clean.stdout);
    try testing.expectEqualStrings("", clean.stderr);

    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data = spaced });
    const aliased = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "fmt", path, "-i" } });
    defer testing.allocator.free(aliased.stdout);
    defer testing.allocator.free(aliased.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, aliased.term);
    const again = try temp.dir.readFileAlloc(testing.io, "input.selka", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(again);
    try testing.expectEqualStrings(canonical, again);

    try invokeOptions("fmt", spaced, &.{ "--write", "--check" }, 2, "", "usage:");
    try invokeOptions("fmt-project", spaced, &.{"--write"}, 2, "", "usage:");
}

// spec: CHECK-LIBRARY-1
test "CLI check-module checks bodies and never invents main" {
    try invoke("check-module", "\npublic func value() -> int:\n    return 7\n", 0, "", "");
    try invoke("check-module", "\npublic record Pair:\n    value: int\n", 0, "", "");
    try invoke("check-module", "\npublic func identity[T](value: T) -> T from value:\n    return value\n", 0, "", "");
    // W3 step 2: an identity that does not declare its borrowed result is refused at its declaration for a managed `T`.
    try invoke("check-module", "\npublic func identity[T](value: T) -> T:\n    return value\n", 1, "", "E_BORROW_UNDECLARED");
    try invoke("check-module", "\npublic func value() -> int:\n    return False\n", 1, "", "E_TYPE");
    try invoke("check-module", "\npublic func value() -> int:\n    return main()\n", 1, "", "E_UNKNOWN_SYMBOL");
    try invoke("check-module", "\nrecord Hidden:\n    value: int\n\npublic func value() -> Hidden:\n    return Hidden(value=7)\n", 1, "", "E_PRIVATE_INTERFACE");
    try invoke("check-module", "\npublic func value(out: Stream) -> Unit noio:\n    print(out, 7)\n", 1, "", "E_EFFECTS_REMOVED");
    try invoke("check-module", "\npublic func value(out: Stream) -> Unit:\n    print(out, 7)\n", 0, "", "");
    const library =
        \\
        \\public func grown(xs: int[]) -> int[]:
        \\    mut copy = copy(xs)
        \\    append(mut copy, 1)
        \\    return copy
        \\
    ;
    try invoke("check-module", library, 0, "", "");
}

fn expectLibraryCommand(path: []const u8, cache: []const u8, command: []const u8, status: u8, diagnostic: []const u8) !void {
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), command, path, cache } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = status }, result.term);
    try testing.expectEqualStrings("", result.stdout);
    try testing.expect(std.mem.indexOf(u8, result.stderr, diagnostic) != null);
}

// spec-case: CHECK-LIBRARY-1
test "CLI check-module follows imports and cannot cache an executable verdict" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = "\npublic func value() -> int:\n    return 7\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.selka", .data = "import helper\n\npublic func value() -> int:\n    return helper.value()\n" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "library.selka", testing.allocator);
    defer testing.allocator.free(path);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{std.fs.path.dirname(path).?});
    defer testing.allocator.free(cache);
    try expectLibraryCommand(path, cache, "check-module", 0, "");
    try expectLibraryCommand(path, cache, "check-project", 1, "E_MAIN");
    try expectLibraryCommand(path, cache, "run", 1, "E_MAIN");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = "\npublic func value() -> int:\n    return False\n" });
    try expectLibraryCommand(path, cache, "check-module", 1, "E_TYPE");
}

// spec-case: CHECK-LIBRARY-1
test "CLI check-module enforces configured warning and interface gates" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.selka", .data = "\npublic func value() -> int:\n    mut unused: int = 1\n    return 7\n" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "library.selka", testing.allocator);
    defer testing.allocator.free(path);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = "{\"version\":2,\"lint\":{\"warnings\":\"deny\"}}" });
    try expectLibraryCommand(path, "--no-cache", "check-module", 1, "W_UNUSED_BINDING");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = "{\"version\":2,\"interface_files\":true}" });
    try expectLibraryCommand(path, "--no-cache", "check-module", 1, "E_INTERFACE_FILE_STALE");
}

/// Run `command` on `text` with `options` and require exit 1, the diagnostic `code`
/// on stderr, and no `E_MAIN`: the failure must be the library's own.
fn expectFailsAsItself(command: []const u8, text: []const u8, options: []const []const u8, code: []const u8) !void {
    const outcome = try runFixture(command, text, options);
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, outcome.term);
    try testing.expectEqualStrings("", outcome.stdout);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, code) != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "E_MAIN") == null);
}

// spec: CHECK-SUCCESS-LINE-1
test "CLI check writes one status line on success and none on failure or in JSON" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(directory);
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.selka" });
    defer testing.allocator.free(entry);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{directory});
    defer testing.allocator.free(cache_argument);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "func main() -> int:\n    return 0\n" });
    // A cold pass parses the module; the same pass again is served from the cache and says so.
    const cold = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry, cache_argument });
    defer freeResult(cold);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cold.term);
    try testing.expectEqualStrings("", cold.stdout);
    try testing.expectEqualStrings("check: ok (1 module, 0 cached)\n", cold.stderr);
    const warm = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry, cache_argument });
    defer freeResult(warm);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, warm.term);
    try testing.expectEqualStrings("", warm.stdout);
    try testing.expectEqualStrings("check: ok (1 module, 1 cached)\n", warm.stderr);
    // Machine-readable diagnostics stay machine readable.
    const json = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry, cache_argument, "--diagnostics=json" });
    defer freeResult(json);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, json.term);
    try testing.expectEqualStrings("", json.stderr);
    // A failing check keeps its diagnostic and writes no status line.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "func main() -> int:\n    return missing\n" });
    const failed = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry, cache_argument });
    defer freeResult(failed);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, failed.term);
    try testing.expect(std.mem.indexOf(u8, failed.stderr, "error[E_UNKNOWN_NAME]") != null);
    try testing.expect(std.mem.indexOf(u8, failed.stderr, "check: ok") == null);
}

// spec: CHECK-LIBRARY-2
test "CLI check type-checks a file without main as a library" {
    try invoke("check", "public func add(a: int, b: int) -> int:\n    return a + b\n", 0, "", "");
    try invoke("check", "public record Pair:\n    value: int\n", 0, "", "");
    try invoke("check", "public func identity[T](value: T) -> T from value:\n    return value\n", 0, "", "");
    try invoke("check", "public func identity[T](value: T) -> T:\n    return value\n", 1, "", "E_BORROW_UNDECLARED");
    try invoke("check", "func helper() -> int:\n    return 1\n", 0, "", "");
    try invoke("check", "", 0, "", "");
    try invoke("check", "\npublic func value() -> int:\n    return 7\n", 0, "", "");
    try invoke("check", "import strings\n\npublic func shout(text: str) -> str:\n    return strings.upper(text)\n", 0, "", "");
    const library =
        \\
        \\public func grown(xs: int[]) -> int[]:
        \\    mut copy = copy(xs)
        \\    append(mut copy, 1)
        \\    return copy
        \\
    ;
    try invoke("check", library, 0, "", "");
    try invokeOptions("check", library, &.{"--diagnostics=json"}, 0, "", "");
    // A body error is the library's own diagnostic, never the missing entry point.
    try expectFailsAsItself("check", "public func value() -> int:\n    return False\n", &.{}, "error[E_TYPE]");
    try expectFailsAsItself("check", "\npublic func value() -> int:\n    return False\n", &.{}, "error[E_TYPE]");
    try expectFailsAsItself("check", "public func value() -> int:\n    return missing\n", &.{}, "error[E_UNKNOWN_NAME]");
    try expectFailsAsItself("check", "public func value(out: Stream) -> Unit noio:\n    print(out, 7)\n", &.{}, "error[E_EFFECTS_REMOVED]");
    try expectFailsAsItself("check", "\nrecord Hidden:\n    value: int\n\npublic func value() -> Hidden:\n    return Hidden(value=7)\n", &.{}, "error[E_PRIVATE_INTERFACE]");
    try expectFailsAsItself("check", "public func value() -> int:\n    return False\n", &.{"--diagnostics=json"}, "\"code\":\"E_TYPE\"");
    try expectFailsAsItself("check", "public func value() -> int:\n    return +\n", &.{}, "error[E_EXPRESSION]");
}

// spec-case: CHECK-LIBRARY-2
test "CLI commands that need an entry point still report E_MAIN for a library" {
    const library = "public func add(a: int, b: int) -> int:\n    return a + b\n";
    try invoke("run", library, 1, "", "error[E_MAIN]");
    try invokeOptions("build", library, &.{"--run"}, 1, "", "error[E_MAIN]");
    try invoke("run", "\npublic func value() -> int:\n    return 7\n", 1, "", "error[E_MAIN]");
    try invoke("check-project", "\npublic func value() -> int:\n    return 7\n", 1, "", "error[E_MAIN]");
    // The message points at the command that accepts a library.
    try invoke("run", library, 1, "", "`selka check FILE` type-checks a library");
}

// spec-case: CHECK-LIBRARY-2
test "CLI check keeps every entry check when main is declared" {
    try invoke("check", "func main() -> int:\n    return 0\n", 0, "", "");
    try invoke("check", "\nfunc main() -> int:\n    return 0\n", 0, "", "");
    try invoke("check", "func main(args: str[], out: Stream) -> int:\n    print(out, len(args))\n    return 0\n", 0, "", "");
    // A wrong signature is an entry error, not a library that happens to define `main`.
    try invoke("check", "func main(count: int) -> int:\n    return count\n", 1, "", "error[E_MAIN]");
    try invoke("check", "func main(log: Stream) -> int:\n    return 0\n", 1, "", "error[E_MAIN]");
    try invoke("check", "func main[T](value: T) -> int:\n    return 0\n", 1, "", "error[E_MAIN]");
    try invoke("check", "func main() -> bool:\n    return True\n", 1, "", "error[E_TYPE]");
    try invoke("check", "\nfunc main(count: int) -> int:\n    return count\n", 1, "", "error[E_MAIN]");
    try invoke("check", "\nfunc main() -> bool:\n    return True\n", 1, "", "error[E_TYPE]");
    // Bodies are still checked as an executable's are, and the entry is not skipped.
    try invoke("check", "func main() -> int:\n    return missing\n", 1, "", "error[E_UNKNOWN_NAME]");
    try invoke("check", "func helper() -> int:\n    return False\n\nfunc main() -> int:\n    return 0\n", 1, "", "error[E_TYPE]");
}

// spec-case: CHECK-LIBRARY-2
test "CLI check of a module entry follows imports and records no executable verdict" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = "\npublic func value() -> int:\n    return 7\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.selka", .data = "import helper\n\npublic func value() -> int:\n    return helper.value()\n" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "library.selka", testing.allocator);
    defer testing.allocator.free(path);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{std.fs.path.dirname(path).?});
    defer testing.allocator.free(cache);
    try expectLibraryCommand(path, cache, "check", 0, "");
    try expectLibraryCommand(path, cache, "check", 0, "");
    try expectLibraryCommand(path, cache, "check-project", 1, "E_MAIN");
    try expectLibraryCommand(path, cache, "run", 1, "E_MAIN");
    try expectLibraryCommand(path, "--no-cache", "check", 0, "");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = "\npublic func value() -> int:\n    return False\n" });
    try expectLibraryCommand(path, cache, "check", 1, "E_TYPE");
    try expectLibraryCommand(path, "--no-cache", "check-module", 1, "E_TYPE");
}

/// A check's exit status, standard output and standard error without the `check: ok` summary
/// line, which counts cached modules and so legitimately differs between a cached and an
/// uncached run. Owned by the caller.
const CheckedOutput = struct {
    status: std.process.Child.Term,
    stdout: []u8,
    stderr: []u8,

    fn free(self: CheckedOutput) void {
        testing.allocator.free(self.stdout);
        testing.allocator.free(self.stderr);
    }
};

fn checkedOutput(path: []const u8, cache: []const u8) !CheckedOutput {
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check", path, cache, "--warnings" } });
    defer testing.allocator.free(result.stderr);
    var kept: std.ArrayList(u8) = .empty;
    errdefer kept.deinit(testing.allocator);
    var lines = std.mem.splitScalar(u8, result.stderr, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "check: ok")) continue;
        try kept.appendSlice(testing.allocator, line);
        try kept.append(testing.allocator, '\n');
    }
    return .{ .status = result.term, .stdout = result.stdout, .stderr = try kept.toOwnedSlice(testing.allocator) };
}

/// Require that a cached `check` of `path` reports exactly what a `--no-cache` one does.
fn expectCachedMatchesUncached(path: []const u8, cache: []const u8) !CheckedOutput {
    const warm = try checkedOutput(path, cache);
    errdefer warm.free();
    const cold = try checkedOutput(path, "--no-cache");
    defer cold.free();
    try testing.expectEqual(cold.status, warm.status);
    try testing.expectEqualStrings(cold.stdout, warm.stdout);
    try testing.expectEqualStrings(cold.stderr, warm.stderr);
    return warm;
}

test "CLI check of an executable after an edit reports the imports its stood-in bodies use" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const helper = "import h2\nimport h3\n\n\npublic func shout(text: str) -> str:\n    return f\"{h2.up(text)}!\"\n";
    const entry = "import helper\n\n\nfunc main() -> int:\n    return len(helper.shout(\"a\")) + 1\n";
    try temp.dir.writeFile(testing.io, .{ .sub_path = "h2.selka", .data = "public func up(text: str) -> str from text:\n    return text\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "h3.selka", .data = "public func idle() -> int:\n    return 0\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = helper });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = entry });
    const path = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(path);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{std.fs.path.dirname(path).?});
    defer testing.allocator.free(cache);
    // The first check resolves every body and stores the entry's summaries.
    const first = try expectCachedMatchesUncached(path, cache);
    defer first.free();
    try testing.expect(std.mem.indexOf(u8, first.stderr, "import `h3` is never referenced") != null);
    try testing.expect(std.mem.indexOf(u8, first.stderr, "import `h2`") == null);
    // An edit to the entry stands `helper.shout` in; `h2` is still used through its f-string hole.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "import helper\n\n\nfunc main() -> int:\n    return len(helper.shout(\"a\")) + 2\n" });
    const edited = try expectCachedMatchesUncached(path, cache);
    defer edited.free();
    try testing.expect(std.mem.indexOf(u8, edited.stderr, "import `h3` is never referenced") != null);
    try testing.expect(std.mem.indexOf(u8, edited.stderr, "import `h2`") == null);
}

/// One cached check of the `h2`/`h3` library of the edit test, which must equal an uncached one,
/// names the unused `h3` and leaves the `h2` used only inside an f-string hole alone.
fn expectImportWarnings(path: []const u8, cache: []const u8) !void {
    const checked = try expectCachedMatchesUncached(path, cache);
    defer checked.free();
    try testing.expect(std.mem.indexOf(u8, checked.stderr, "import `h3` is never referenced") != null);
    try testing.expect(std.mem.indexOf(u8, checked.stderr, "import `h2`") == null);
}

// spec-case: CHECK-LIBRARY-2
test "CLI check of a library after edits reports exactly what a check without a cache reports" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const up = "public func up(text: str) -> str from text:\n    return text\n";
    const helper = "import h2\nimport h3\n\n\npublic func shout(text: str) -> str:\n    return f\"{h2.up(text)}!\"\n";
    const library = "import helper\n\n\npublic func twice(text: str) -> str:\n    return helper.shout(helper.shout(text))\n\n\npublic func other(n: int) -> int:\n    return n + 1\n";
    try temp.dir.writeFile(testing.io, .{ .sub_path = "h2.selka", .data = up });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "h3.selka", .data = "public func idle() -> int:\n    return 0\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = helper });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.selka", .data = library });
    const path = try temp.dir.realPathFileAlloc(testing.io, "library.selka", testing.allocator);
    defer testing.allocator.free(path);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{std.fs.path.dirname(path).?});
    defer testing.allocator.free(cache);
    // The first check runs plainly, the second stores the entry's summaries and the third stands
    // bodies in from them; an unused import is named, a used one is not, each time.
    try expectImportWarnings(path, cache);
    try expectImportWarnings(path, cache);
    try expectImportWarnings(path, cache);
    // An unrelated body edit stands `helper.shout` in; `h2` is still used through its f-string hole.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.selka", .data = "import helper\n\n\npublic func twice(text: str) -> str:\n    return helper.shout(helper.shout(text))\n\n\npublic func other(n: int) -> int:\n    return n + 2\n" });
    const edited = try expectCachedMatchesUncached(path, cache);
    defer edited.free();
    try testing.expect(std.mem.indexOf(u8, edited.stderr, "import `h3` is never referenced") != null);
    try testing.expect(std.mem.indexOf(u8, edited.stderr, "import `h2`") == null);
    // A body that fails to check is reported as a check without summaries reports it.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.selka", .data = "import helper\n\n\npublic func twice(text: str) -> str:\n    return helper.shout(helper.shout(text))\n\n\npublic func other(n: int) -> int:\n    return \"x\"\n" });
    const failing = try expectCachedMatchesUncached(path, cache);
    defer failing.free();
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, failing.status);
    try testing.expect(std.mem.indexOf(u8, failing.stderr, "error[E_TYPE]") != null);
    // An imported module's signature edit reaches the body that calls it through the f-string.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.selka", .data = library });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "h2.selka", .data = "public func up(text: str, extra: int) -> str from text:\n    return text\n" });
    const broken = try expectCachedMatchesUncached(path, cache);
    defer broken.free();
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, broken.status);
    try testing.expect(std.mem.indexOf(u8, broken.stderr, "error[E_ARITY]") != null);
    // Restoring it checks clean again, with the same warning.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "h2.selka", .data = up });
    const restored = try expectCachedMatchesUncached(path, cache);
    defer restored.free();
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, restored.status);
    try testing.expect(std.mem.indexOf(u8, restored.stderr, "import `h3` is never referenced") != null);
    // The library gains an entry point: the executable check reads no library summaries, so
    // `h2`, used only inside the f-string hole, is not reported, and removing `main` again
    // returns to the library's own.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.selka", .data = library ++ "\n\nfunc main() -> int:\n    return 0\n" });
    const executable = try expectCachedMatchesUncached(path, cache);
    defer executable.free();
    try testing.expect(std.mem.indexOf(u8, executable.stderr, "import `h2`") == null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.selka", .data = library });
    const library_again = try expectCachedMatchesUncached(path, cache);
    defer library_again.free();
    try testing.expect(std.mem.indexOf(u8, library_again.stderr, "import `h2`") == null);
}

/// Every file under `directory` with its inode and size, sorted and joined by newlines: two
/// snapshots are equal exactly when no file was added, replaced or removed between them.
fn cacheSnapshot(directory: []const u8) ![]u8 {
    var lines: std.ArrayList([]u8) = .empty;
    defer {
        for (lines.items) |line| testing.allocator.free(line);
        lines.deinit(testing.allocator);
    }
    var opened = try std.Io.Dir.cwd().openDir(testing.io, directory, .{ .iterate = true });
    defer opened.close(testing.io);
    var walker = try opened.walk(testing.allocator);
    defer walker.deinit();
    while (try walker.next(testing.io)) |entry| {
        if (entry.kind != .file) continue;
        const stat = try opened.statFile(testing.io, entry.path, .{});
        try lines.append(testing.allocator, try std.fmt.allocPrint(testing.allocator, "{s} {d} {d}", .{ entry.path, stat.inode, stat.size }));
    }
    std.mem.sort([]u8, lines.items, {}, struct {
        fn less(_: void, left: []u8, right: []u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.less);
    return std.mem.join(testing.allocator, "\n", lines.items);
}

/// The phase timings of one `check` of a library against `cache`; the caller frees them.
fn checkPhases(path: []const u8, cache: []const u8) ![]u8 {
    const outcome = try privateRun(testing.allocator, &.{ compilerPath(), "check", path, cache, "--timings=json" });
    defer testing.allocator.free(outcome.stdout);
    errdefer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    return outcome.stderr;
}

fn expectPhase(phases: []const u8, name: []const u8, present: bool) !void {
    const needle = try std.fmt.allocPrint(testing.allocator, "\"name\":\"{s}\"", .{name});
    defer testing.allocator.free(needle);
    try testing.expectEqual(present, std.mem.indexOf(u8, phases, needle) != null);
}

test "CLI check of a library prepares nothing for a first check and rewrites nothing when unchanged" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = "\npublic func value() -> int:\n    return 7\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.selka", .data = "import helper\n\npublic func value() -> int:\n    return helper.value()\n" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "library.selka", testing.allocator);
    defer testing.allocator.free(path);
    const root = std.fs.path.dirname(path).?;
    const cache_directory = try std.fmt.allocPrint(testing.allocator, "{s}/cache", .{root});
    defer testing.allocator.free(cache_directory);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_directory});
    defer testing.allocator.free(cache);
    // A library checked for the first time runs the plain check: no dependency keys, no summaries.
    const first = try checkPhases(path, cache);
    defer testing.allocator.free(first);
    try expectPhase(first, "dependency_key_preparation", false);
    try expectPhase(first, "summary_store", false);
    // The second check prepares the keys and stores the summaries the third will stand in from.
    const second = try checkPhases(path, cache);
    defer testing.allocator.free(second);
    try expectPhase(second, "dependency_key_preparation", true);
    try expectPhase(second, "summary_load", true);
    try expectPhase(second, "summary_store", true);
    // Checking it unchanged again must leave the cache exactly as it is: the same table is
    // not written twice.
    const third = try checkPhases(path, cache);
    defer testing.allocator.free(third);
    try expectPhase(third, "summary_load", true);
    const before = try cacheSnapshot(cache_directory);
    defer testing.allocator.free(before);
    const fourth = try checkPhases(path, cache);
    defer testing.allocator.free(fourth);
    const after = try cacheSnapshot(cache_directory);
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(before, after);
    // An edit changes the table, which is then written.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.selka", .data = "import helper\n\npublic func value() -> int:\n    return helper.value() + 1\n" });
    const edited = try checkPhases(path, cache);
    defer testing.allocator.free(edited);
    try expectPhase(edited, "summary_store", true);
    const changed = try cacheSnapshot(cache_directory);
    defer testing.allocator.free(changed);
    try testing.expect(!std.mem.eql(u8, before, changed));
    // A copy of the library under another directory, checked into the same cache, is a first
    // check of its own: the entry the original left a mark for does not prime it.
    try temp.dir.createDirPath(testing.io, "copy");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "copy/helper.selka", .data = "\npublic func value() -> int:\n    return 7\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "copy/library.selka", .data = "import helper\n\npublic func value() -> int:\n    return helper.value()\n" });
    const copy_path = try temp.dir.realPathFileAlloc(testing.io, "copy/library.selka", testing.allocator);
    defer testing.allocator.free(copy_path);
    const copied = try checkPhases(copy_path, cache);
    defer testing.allocator.free(copied);
    try expectPhase(copied, "dependency_key_preparation", false);
}

// spec-case: CHECK-LIBRARY-2
test "CLI check of a library enforces configured warning and interface gates" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "headerless.selka", .data = "public func value() -> int:\n    mut unused: int = 1\n    return 7\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.selka", .data = "\npublic func value() -> int:\n    mut unused: int = 1\n    return 7\n" });
    const headerless = try temp.dir.realPathFileAlloc(testing.io, "headerless.selka", testing.allocator);
    defer testing.allocator.free(headerless);
    const path = try temp.dir.realPathFileAlloc(testing.io, "library.selka", testing.allocator);
    defer testing.allocator.free(path);
    try expectLibraryCommand(path, "--no-cache", "check", 0, "W_UNUSED_BINDING");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = "{\"version\":2,\"lint\":{\"warnings\":\"deny\"}}" });
    try expectLibraryCommand(headerless, "--no-cache", "check", 1, "W_UNUSED_BINDING");
    try expectLibraryCommand(path, "--no-cache", "check", 1, "W_UNUSED_BINDING");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = "{\"version\":2,\"interface_files\":true}" });
    try expectLibraryCommand(path, "--no-cache", "check", 1, "E_INTERFACE_FILE_STALE");
}

// spec: FMT-CHECK-LOCATION-1
test "CLI formatter check locates spacing and missing final newline" {
    try invokeOptions("fmt", "func  main() -> int:\n    return 7\n", &.{"--check"}, 1, "", "input.selka:1:6: formatting differs");
    try invokeOptions("fmt", "func main() -> int:\n    return 7", &.{"--check"}, 1, "", "input.selka:2:13: formatting differs");
    try invokeOptions("fmt-module", "\nfunc  f() -> int:\n    return 7\n", &.{"--check"}, 1, "", "input.selka:1:1: formatting differs");
}

// W5-F-9: `fmt --check` says what the formatter wants at the first difference and names `fmt --write` as the repair, in one line.
// The fixture's path is absolute, so the clause and the repair are asserted in two pieces.
test "CLI formatter check says what the layout wants and names the repair" {
    try invokeOptions("fmt", "const A: int = 1\n\nconst B: int = 2\n", &.{"--check"}, 1, "", "input.selka:3:1: formatting differs: line 1 is followed by one blank line, " ++
        "and the formatter wants two blank lines between top-level declarations; `selka fmt --write ");
    try invokeOptions("fmt", "const A: int = 1\n\nconst B: int = 2\n", &.{"--check"}, 1, "", "input.selka` repairs it\n");
    try invokeOptions("fmt", "func  main() -> int:\n    return 7\n", &.{"--check"}, 1, "", "formatting differs: line 1 reads `func  main() -> int:` and the formatter wants `func main() -> int:`; ");
    try invokeOptions("fmt", "func main() -> int:\n    return 7", &.{"--check"}, 1, "", "formatting differs: the file does not end with a newline; `selka fmt --write ");
}

// spec: FMT-TEST-MODULE-1
test "CLI formatter and test agree on headerless sibling test imports" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = "\npublic func value() -> int:\n    return 7\n" });
    const source = "import helper\n\npublic func test_value() -> bool:\n    return helper.value() == 7\n";
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper_test.selka", .data = source });
    const path = try temp.dir.realPathFileAlloc(testing.io, "helper_test.selka", testing.allocator);
    defer testing.allocator.free(path);
    const formatted = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "fmt", path } });
    defer testing.allocator.free(formatted.stdout);
    defer testing.allocator.free(formatted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, formatted.term);
    try testing.expectEqualStrings(source, formatted.stdout);
    const checked = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "fmt-module", path, "--check" } });
    defer testing.allocator.free(checked.stdout);
    defer testing.allocator.free(checked.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
    const cache = try privateTestCache(path);
    defer testing.allocator.free(cache);
    const tested = try privateRun(testing.allocator, &.{ compilerPath(), "test", path, "--cache-dir", cache });
    defer testing.allocator.free(tested.stdout);
    defer testing.allocator.free(tested.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, tested.term);
    try testing.expect(std.mem.indexOf(u8, tested.stdout, "1 passed") != null);
    try invoke("fmt", source, 0, source, "");
}

// spec: TEST-SIBLING-HINT-1
test "CLI empty test selection names an unloaded sibling and preserves JSON" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = "\npublic func value() -> int:\n    return 7\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper_test.selka", .data = "import helper\n\npublic func test_value() -> bool:\n    return helper.value() == 7\n" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "helper.selka", testing.allocator);
    defer testing.allocator.free(path);
    const empty = try privateRun(testing.allocator, &.{ compilerPath(), "test", path, "--json" });
    defer testing.allocator.free(empty.stdout);
    defer testing.allocator.free(empty.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, empty.term);
    try testing.expect(std.mem.indexOf(u8, empty.stderr, "helper_test.selka") != null);
    try testing.expect(std.mem.indexOf(u8, empty.stderr, "Run that file explicitly") != null);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, empty.stdout, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("native-tests-v1", parsed.value.object.get("version").?.string);
    try testing.expectEqual(@as(usize, 0), parsed.value.object.get("tests").?.array.items.len);
    try temp.dir.deleteFile(testing.io, "helper_test.selka");
    const absent = try privateRun(testing.allocator, &.{ compilerPath(), "test", path });
    defer testing.allocator.free(absent.stdout);
    defer testing.allocator.free(absent.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, absent.term);
    try testing.expectEqualStrings("", absent.stderr);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper_test.selka", .data = "\npublic func value() -> int:\n    return 7\n\n\npublic func test_value() -> bool:\n    return True\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = "import helper_test\n\nfunc main() -> int:\n    return helper_test.value()\n" });
    const loaded = try privateRun(testing.allocator, &.{ compilerPath(), "test", path, "--filter", "does_not_exist" });
    defer testing.allocator.free(loaded.stdout);
    defer testing.allocator.free(loaded.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, loaded.term);
    try testing.expectEqualStrings("", loaded.stderr);
}

// spec: TEST-SIBLING-HINT-2
test "CLI a directory test run tests the sibling it would name, so it does not say the sibling is left out" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDirPath(testing.io, "app");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/main.selka", .data = "public func answer() -> int:\n    return 42\n\n\nfunc main() -> int:\n    return answer()\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/main_test.selka", .data = "import main\n\npublic func test_answer() -> bool:\n    return main.answer() == 42\n" });
    const directory = try temp.dir.realPathFileAlloc(testing.io, "app", testing.allocator);
    defer testing.allocator.free(directory);
    // A work directory of its own: in the repository's default one, a run after an earlier run of this test (same sources,
    // same compiler) replays the verdict as `cached` and prints no `1 passed` (FX10 found it order-dependent).
    const cache = try std.fs.path.join(testing.allocator, &.{ directory, ".cache" });
    defer testing.allocator.free(cache);
    const tested = try privateRun(testing.allocator, &.{ compilerPath(), "test", directory, "--cache-dir", cache });
    defer testing.allocator.free(tested.stdout);
    defer testing.allocator.free(tested.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, tested.term);
    try testing.expect(std.mem.indexOf(u8, tested.stdout, "1 passed") != null);
    try testing.expect(std.mem.indexOf(u8, tested.stderr, "sibling test file") == null);
    // The entry alone still names the sibling it leaves out.
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.selka" });
    defer testing.allocator.free(entry);
    const alone = try privateRun(testing.allocator, &.{ compilerPath(), "test", entry, "--cache-dir", cache });
    defer testing.allocator.free(alone.stdout);
    defer testing.allocator.free(alone.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, alone.term);
    try testing.expect(std.mem.indexOf(u8, alone.stderr, "sibling test file") != null);
}

test "CLI module discovery loads real files and diagnoses cross-file cycles" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDirPath(testing.io, "shared");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data =
        \\import shared.data as data
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "shared/data.selka", .data = "" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.selka", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "list-modules", path } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings("", result.stderr);
    const child = std.mem.indexOf(u8, result.stdout, "module shared.data path=shared/data.selka sha256=").?;
    const root = std.mem.indexOf(u8, result.stdout, "module input path=input.selka sha256=").?;
    try testing.expect(child < root);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "bodies/exports/types not checked") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "shared/data.selka", .data = "import input\n" });
    const cycle = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "list-modules", path } });
    defer testing.allocator.free(cycle.stdout);
    defer testing.allocator.free(cycle.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, cycle.term);
    try testing.expectEqualStrings("", cycle.stdout);
    for ([_][]const u8{ "E_IMPORT_CYCLE", "shared/data.selka:1:", "input.selka:1:", "input -> shared.data -> input", "`input` imports `shared.data` and uses nothing from it", "Remove `import shared.data` from `input`, which never reads it: that breaks the cycle" }) |part| try testing.expect(std.mem.indexOf(u8, cycle.stderr, part) != null);
}
// A file that imports is refused when its name is not a module's: before it said `list-modules: entry must be an identifier.selka file`,
// with no code, and now it names the file to rename and the name to give it.
test "CLI an entry that imports and has a hyphen in its name is refused with the name to give it" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const importing = "import strings\n\nfunc main(out: Stream) -> int:\n    print(out, strings.lower(\"ABC\"))\n    return 0\n";
    try temp.dir.writeFile(testing.io, .{ .sub_path = "my-prog.selka", .data = importing });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "2nd-try.selka", .data = importing });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "plain-prog.selka", .data = "func main() -> int:\n    return 0\n" });
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const names = [_][]const u8{ "my-prog.selka", "2nd-try.selka" };
    const wanted = [_][]const u8{ "rename `my-prog.selka` to `my_prog.selka`: a file that imports must be named like a module", "rename `2nd-try.selka` to `_2nd_try.selka`: a file that imports must be named like a module" };
    for (names, wanted) |name, part| {
        const path = try std.fs.path.join(testing.allocator, &.{ root, name });
        defer testing.allocator.free(path);
        for ([_][]const u8{ "check", "list-modules" }) |command| {
            const result = try privateRun(testing.allocator, &.{ compilerPath(), command, path });
            defer testing.allocator.free(result.stdout);
            defer testing.allocator.free(result.stderr);
            try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, result.term);
            try testing.expect(std.mem.indexOf(u8, result.stderr, "error[E_ENTRY_NAME]: ") != null);
            try testing.expect(std.mem.indexOf(u8, result.stderr, part) != null);
            try testing.expect(std.mem.indexOf(u8, result.stderr, "entry must be an identifier") == null);
        }
    }
    // The same name without an import is one standalone unit and checks as it stands.
    const plain = try std.fs.path.join(testing.allocator, &.{ root, "plain-prog.selka" });
    defer testing.allocator.free(plain);
    const standalone = try privateRun(testing.allocator, &.{ compilerPath(), "check", plain });
    defer testing.allocator.free(standalone.stdout);
    defer testing.allocator.free(standalone.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, standalone.term);
}
test "CLI module discovery keeps header validity separate from compilation" {
    const result = try runFixture("list-modules",
        \\func broken(
    , &.{});
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "header discovery only") != null);
    try invoke("list-modules",
        \\import missing
    , 1, "", "E_MODULE_READ");
    try invokeOptions("list-modules", "module input", &.{"--max-steps=10"}, 2, "", "usage:");
    const compilation = try runFixture("check",
        \\
        \\
        \\func main() -> i64:
        \\    return unknown()
    , &.{});
    defer testing.allocator.free(compilation.stdout);
    defer testing.allocator.free(compilation.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, compilation.term);
    try testing.expect(std.mem.indexOf(u8, compilation.stderr, "E_UNKNOWN_FUNCTION") != null);
}
test "CLI module interfaces parse bodies and check exported signature visibility" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data =
        \\import units
        \\
        \\
        \\public record Sample:
        \\    distance: units.Distance
        \\
        \\
        \\func main() -> i64:
        \\    return unknown()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "units.selka", .data =
        \\
        \\
        \\public record Distance:
        \\    value: i64
        \\
        \\public func make_D(x: i64) -> Distance:
        \\    return Distance(value=x)
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.selka", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "list-interfaces", path } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings("", result.stderr);
    for ([_][]const u8{ "bodies not type checked", "export type Sample", "export type Distance", "export function make_D" }) |part| try testing.expect(std.mem.indexOf(u8, result.stdout, part) != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "units.selka", .data =
        \\
        \\
        \\record Distance:
        \\    value: i64
        \\
        \\func make_D(x: i64) -> Distance:
        \\    return Distance(value=x)
    });
    const hidden = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "list-interfaces", path } });
    defer testing.allocator.free(hidden.stdout);
    defer testing.allocator.free(hidden.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, hidden.term);
    try testing.expectEqualStrings("", hidden.stdout);
    for ([_][]const u8{ "E_PRIVATE_SYMBOL", "input.selka:5:", "units.selka:3:" }) |part| try testing.expect(std.mem.indexOf(u8, hidden.stderr, part) != null);
    try invoke("list-interfaces",
        \\func broken(
    , 1, "", "E_SYNTAX");
    try invoke("list-interfaces",
        \\
        \\
        \\record Secret:
        \\    pass
        \\
        \\
        \\public func f() -> Secret:
        \\    return Secret()
    , 1, "", "E_PRIVATE_INTERFACE");
    try invokeOptions("list-interfaces", "module input", &.{"--check"}, 2, "", "usage:");
}
// spec: INTERFACE-SIGNATURE-CLI-1
test "CLI list-interfaces renders capability parameters with their Python spelling" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data =
        \\
        \\
        \\public func main(_fs: Filesystem, _clock: Clock) -> int:
        \\    return 0
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.selka", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "list-interfaces", path } });
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\import math
        \\
        \\
        \\func main() -> int:
        \\    return math.clamp(99, 0, 42)
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &(.{ compilerPath(), "run", path, "--print-result" } ++ tools) });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    // `main` returns 42, and a run now exits with its int result.
    try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, result.term);
    try testing.expectEqualStrings("42\n", result.stdout);
    try testing.expectEqualStrings("", result.stderr);
    // `run-project` stays an explicit alias for the same entry.
    const alias = try std.process.run(testing.allocator, testing.io, .{ .argv = &(.{ compilerPath(), "run-project", path, "--print-result" } ++ tools) });
    defer testing.allocator.free(alias.stdout);
    defer testing.allocator.free(alias.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, alias.term);
    try testing.expectEqualStrings("42\n", alias.stdout);
    // A plain single-file program still takes the original one-unit path.
    try invoke("run", @embedFile("fixtures/arithmetic.selka"), 0, "7\n", "");
}
// spec: CHECK-PROJECT-ENTRY-1
test "CLI check on a CHECK-PROJECT-ENTRY-1 module project loads the reachable graph" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\import helper
        \\
        \\
        \\func main() -> int:
        \\    return helper.value()
    });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data =
        \\
        \\
        \\public func value() -> int:
        \\    return 42
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(path);
    const checked = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check", path } });
    defer testing.allocator.free(checked.stdout);
    defer testing.allocator.free(checked.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
    try testing.expectEqualStrings("", checked.stdout);
    try check_line.expectPassed(checked.stderr);
    const explicit = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check-project", path } });
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "app/main.selka", .data =
        \\import helper
        \\
        \\func main() -> int:
        \\    return helper.value()
    });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "app/helper.selka", .data =
        \\
        \\public func value() -> int:
        \\    return 42
    });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "app/main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "program" });
    defer testing.allocator.free(output);
    var link_argv: std.ArrayList([]const u8) = .empty;
    defer link_argv.deinit(testing.allocator);
    try link_argv.appendSlice(testing.allocator, &.{ compilerPath(), "build", entry, "-o", output });
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

test "CLI test discovers a test_ function without an explicit export" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\
        \\func test_add() -> bool:
        \\    return 1 + 1 == 2
        \\
        \\func main() -> int:
        \\    return 0
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, ".selka-test-cache" });
    defer testing.allocator.free(cache);
    const result = try privateRun(testing.allocator, &.{ compilerPath(), "test", path, "--cache-dir", cache });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "1 passed") != null);
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

// spec: NATIVE-ZIG-CACHE-2
test "a guest build inside a build.zig project leaves no Zig cache in that project" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    // A `build.zig` makes this directory the project `zig cc` would cache under.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "build.zig", .data = "" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "hello.selka", .data = "func main(out: Stream) -> int:\n    print(out, \"hello\")\n    return 0\n" });
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try std.process.Environ.createMap(testing.environ, testing.allocator);
    defer environment.deinit();
    // An inherited local cache would hide where the tools put their cache.
    _ = environment.swapRemove("ZIG_LOCAL_CACHE_DIR");
    const built = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "build", "hello.selka", "-o", "hello", "--cache-dir", "cache", tools[0] },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    defer testing.allocator.free(built.stdout);
    defer testing.allocator.free(built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const program = try std.fs.path.join(testing.allocator, &.{ root, "hello" });
    defer testing.allocator.free(program);
    const ran = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{program} });
    defer testing.allocator.free(ran.stdout);
    defer testing.allocator.free(ran.stderr);
    try testing.expectEqualStrings("hello\n", ran.stdout);
    try testing.expectError(error.FileNotFound, temporary.dir.access(testing.io, ".zig-cache", .{}));
}

// spec-case: NATIVE-ZIG-CACHE-2
test "selka test inside a build.zig project compiles its runner without a Zig cache there" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "build.zig", .data = "" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "checks.selka", .data = "public func test_adds() -> bool:\n    return 1 + 1 == 2\n" });
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    defer environment.deinit();
    _ = environment.swapRemove("ZIG_LOCAL_CACHE_DIR");
    // A fresh cache directory makes this run compile the runner harness itself.
    const tested = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "test", "checks.selka", "--cache-dir=cache", tools[0] },
        .cwd = .{ .dir = temporary.dir },
        .environ_map = &environment,
    });
    defer testing.allocator.free(tested.stdout);
    defer testing.allocator.free(tested.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, tested.term);
    try testing.expect(std.mem.indexOf(u8, tested.stdout, "1 passed") != null);
    try testing.expectError(error.FileNotFound, temporary.dir.access(testing.io, ".zig-cache", .{}));
}

test "CLI test ignores unexported test_ helpers that cannot default" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\
        \\func test_helper(value: int) -> bool:
        \\    return value > 0
        \\
        \\func test_count() -> int:
        \\    return 1
        \\
        \\func test_ok() -> bool:
        \\    return True
        \\
        \\func main() -> int:
        \\    return 0
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, ".selka-test-cache" });
    defer testing.allocator.free(cache);
    const result = try privateRun(testing.allocator, &.{ compilerPath(), "test", path, "--cache-dir", cache });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "1 passed") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "test_helper") == null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "test_count") == null);
}

// spec: DIRECTORY-CASES-1
// spec-case: TEST-PRIVATE-ACCESS-1
test "CLI directory test applies each entry's own cases file and lets a test file reach its module's privates" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "scanner.selka", .data = "\n\nfunc helper() -> int:\n    return 7\n\n\npublic func scan() -> int:\n    return helper()\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "scanner_test.selka", .data = "import scanner\n\n\npublic func test_helper() -> bool:\n    return scanner.helper() == scanner.scan()\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "scaled_test.selka", .data = "\n\npublic func test_scaled(n: int) -> int:\n    return n * 2\n" });
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, ".selka-test-cache" });
    defer testing.allocator.free(cache);
    // Without its cases file the parameterized test is a property test
    // (PROPERTY-TEST-1), which an `int` result cannot be.
    const bare = try privateRun(testing.allocator, &.{ compilerPath(), "test", root, "--cache-dir", cache });
    defer testing.allocator.free(bare.stdout);
    defer testing.allocator.free(bare.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, bare.term);
    try testing.expect(std.mem.indexOf(u8, bare.stdout, "passed scanner_test::test_helper") != null);
    try testing.expect(std.mem.indexOf(u8, bare.stdout, "a property test returns bool or Result[bool, E]") != null);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "scaled_test.cases.json", .data = "{\"scaled_test::test_scaled\": {\"arguments\": {\"n\": \"21\"}, \"expected\": \"42\"}}" });
    const cased = try privateRun(testing.allocator, &.{ compilerPath(), "test", root, "--cache-dir", cache });
    defer testing.allocator.free(cased.stdout);
    defer testing.allocator.free(cased.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cased.term);
    try testing.expect(std.mem.indexOf(u8, cased.stdout, "scaled_test::test_scaled") != null);
    try testing.expect(std.mem.indexOf(u8, cased.stdout, "0 failed") != null);
    // An explicit `--cases` still names one project, so a directory refuses it.
    const explicit = try privateRun(testing.allocator, &.{ compilerPath(), "test", root, "--cases", "scaled_test.cases.json", "--cache-dir", cache });
    defer testing.allocator.free(explicit.stdout);
    defer testing.allocator.free(explicit.stderr);
    try testing.expect(explicit.term.exited != 0);
}

test "CLI test reports an exported ill-shaped test as a failed case" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\
        \\
        \\public func test_bad() -> int:
        \\    return 1
        \\
        \\
        \\public func test_ok() -> bool:
        \\    return True
        \\
        \\
        \\func main() -> int:
        \\    return 0
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, ".selka-test-cache" });
    defer testing.allocator.free(cache);
    const result = try privateRun(testing.allocator, &.{ compilerPath(), "test", path, "--cache-dir", cache });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "failed main::test_bad") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "1 failed") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "host failure") == null);
}

/// One `selka test` run of `path` with a private cache and extra arguments.
fn capabilityTestRun(path: []const u8, cache: []const u8, extra: []const []const u8) !std.process.RunResult {
    const argv = try std.mem.concat(testing.allocator, []const u8, &.{ &.{ compilerPath(), "test", path, "--cache-dir", cache }, extra });
    defer testing.allocator.free(argv);
    return privateRun(testing.allocator, argv);
}

/// Run a `selka test` child whose verdicts and counts come from its private
/// cache alone: both shared stores are disabled in its environment.
fn privateRun(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.RunResult {
    try requireReleaseArgs(argv);
    var environment = try @import("test_paths").privateEnvironment(allocator);
    defer environment.deinit();
    return std.process.run(allocator, testing.io, .{ .argv = argv, .environ_map = &environment });
}

/// The `word N` line a failing entropy test printed, which the runner appends
/// to its failure text.
fn printedWord(stdout: []const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, stdout, "word ") orelse return error.TestUnexpectedResult;
    const end = std.mem.indexOfScalarPos(u8, stdout, start, '\n') orelse stdout.len;
    return stdout[start..end];
}

const capability_tests =
    \\import network
    \\import random
    \\import time
    \\
    \\public func test_clock(clock: Clock) -> bool:
    \\    match time.now(clock):
    \\        case Ok(instant):
    \\            return instant.unix_nanoseconds == 946684800000000000
    \\        case Err(_):
    \\            return False
    \\
    \\public func test_files(fs: Filesystem, env: Environment, net: Network) -> bool:
    \\    _ = fs.write_text("a.txt", "x")
    \\    with net.host("127.0.0.1:1") as endpoint:
    \\        match network.connect(endpoint):
    \\            case ok(_):
    \\                return False
    \\            case err(code):
    \\                return code == network.denied_here() and fs.exists("a.txt") and len(env.names()) == 0
    \\
    \\public func test_entropy(entropy: Entropy, out: Stream) -> bool:
    \\    match random.from_entropy(entropy):
    \\        case Ok(sampled):
    \\            mut generator = own sampled
    \\            print(out, "word", random.next_word(mut generator))
    \\        case Err(_):
    \\            print(out, "no entropy")
    \\    return False
    \\
    \\public func test_host(host: Host) -> bool:
    \\    _ = host
    \\    return True
    \\
    \\func main() -> int:
    \\    return 0
;

// spec: TEST-CAPS-3
test "CLI test hands declared capabilities deterministic stand-ins and reuses their passes" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = capability_tests });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, ".selka-test-cache" });
    defer testing.allocator.free(cache);
    const first = try capabilityTestRun(path, cache, &.{});
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, first.term);
    try testing.expect(std.mem.indexOf(u8, first.stdout, "passed main::test_clock") != null);
    try testing.expect(std.mem.indexOf(u8, first.stdout, "passed main::test_files") != null);
    // No test is ever handed real authority: a Host parameter is not supplied.
    try testing.expect(std.mem.indexOf(u8, first.stdout, "failed main::test_host") != null);
    // Nothing the in-memory filesystem wrote reached the project directory.
    try testing.expectError(error.FileNotFound, temporary.dir.access(testing.io, "a.txt", .{}));
    const second = try capabilityTestRun(path, cache, &.{});
    defer testing.allocator.free(second.stdout);
    defer testing.allocator.free(second.stderr);
    try testing.expect(std.mem.indexOf(u8, second.stdout, "cached main::test_clock") != null);
    try testing.expect(std.mem.indexOf(u8, second.stdout, "cached main::test_files") != null);
    // The entropy seed comes from the test's name, so a rerun draws the same word.
    try testing.expectEqualStrings(try printedWord(first.stdout), try printedWord(second.stdout));
    const reseeded = try capabilityTestRun(path, cache, &.{ "--seed", "7" });
    defer testing.allocator.free(reseeded.stdout);
    defer testing.allocator.free(reseeded.stderr);
    // A different seed is a different execution, so no receipt answers for it.
    try testing.expect(std.mem.indexOf(u8, reseeded.stdout, "passed main::test_clock") != null);
    try testing.expect(!std.mem.eql(u8, try printedWord(first.stdout), try printedWord(reseeded.stdout)));
    const invalid = try capabilityTestRun(path, cache, &.{ "--seed", "seven" });
    defer testing.allocator.free(invalid.stdout);
    defer testing.allocator.free(invalid.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, invalid.term);
}

// spec-case: CHECK-PROJECT-ENTRY-1
test "CLI check keeps plain single-file programs on the one-unit path" {
    try invoke("check",
        \\func main() -> int:
        \\    return 7
    , 0, "", "");
    try invoke("check",
        \\func main() -> int:
        \\    mut x = True
        \\    x = 1
        \\    return 7
    , 1, "", "E_TYPE");
}
// spec: CLI-6
test "CLI answers removed C-backend commands with what replaces them" {
    try invokeOptions("emit-c", "func main() -> int:\n    return 0\n", &.{}, 2, "", "--emit-llvm PATH");
    try invokeOptions("emit-project-c", "\n\nfunc main() -> int:\n    return 0\n", &.{}, 2, "", "--emit-llvm PATH");
}
test "CLI checks and runs module programs with private boundaries and cross-file traps" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data =
        \\import helper
        \\
        \\
        \\func main() -> i64:
        \\    return helper.value()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data =
        \\
        \\
        \\public func value() -> i64:
        \\    return 42
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.selka", testing.allocator);
    defer testing.allocator.free(path);
    for ([_][]const u8{ "check-project", "run-project" }) |command| {
        const reporting: []const []const u8 = if (std.mem.eql(u8, command, "run-project")) &.{"--print-result"} else &.{};
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(testing.allocator);
        try argv.appendSlice(testing.allocator, &.{ compilerPath(), command, path });
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data =
        \\
        \\
        \\public func value() -> i64:
        \\    return divtrunc(1, 0)
    });
    const trap = try std.process.run(testing.allocator, testing.io, .{ .argv = &(.{ compilerPath(), "run-project", path, "--print-result" } ++ tools) });
    defer testing.allocator.free(trap.stdout);
    defer testing.allocator.free(trap.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, trap.term);
    for ([_][]const u8{ "R_DIVISION_BY_ZERO", "helper.selka:4:", "input.selka:5:" }) |part| try testing.expect(std.mem.indexOf(u8, trap.stderr, part) != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data =
        \\
        \\
        \\func value() -> i64:
        \\    return 42
    });
    const hidden = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check-project", path } });
    defer testing.allocator.free(hidden.stdout);
    defer testing.allocator.free(hidden.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, hidden.term);
    for ([_][]const u8{ "E_PRIVATE_SYMBOL", "helper.selka:3:", "input.selka:5:" }) |part| try testing.expect(std.mem.indexOf(u8, hidden.stderr, part) != null);
    try invokeOptions("run-project",
        \\
        \\
        \\func main() -> i64:
        \\    while True:
        \\        pass
        \\    return 7
    , &.{"--max-steps=100"}, 1, "", "R_STEP_LIMIT");
    try invokeOptions("check-project",
        \\
        \\
        \\func main() -> i64:
        \\    return 7
    , &.{"--max-steps=1"}, 2, "", "usage:");
}
test "CLI checkProjectPolicy distinguishes language failures policy failures and configuration failures" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data =
        \\import core
        \\
        \\
        \\func main() -> i64:
        \\    return core.value()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "core.selka", .data =
        \\
        \\
        \\public func value() -> i64:
        \\    return 7
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "rules file.json", .data = "{\"version\":1,\"default_action\":\"deny\",\"rules\":[]}" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.selka", testing.allocator);
    defer testing.allocator.free(path);
    const policy_path = try temp.dir.realPathFileAlloc(testing.io, "rules file.json", testing.allocator);
    defer testing.allocator.free(policy_path);
    const option = try std.fmt.allocPrint(testing.allocator, "--policy={s}", .{policy_path});
    defer testing.allocator.free(option);
    const denied = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check-policy", path, option } });
    defer testing.allocator.free(denied.stdout);
    defer testing.allocator.free(denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, denied.term);
    try testing.expectEqualStrings("", denied.stderr);
    for ([_][]const u8{ "language: valid", "import-direction-v1: failed", "edges=1; denied=1", "input -> core: deny; rule=default" }) |part| try testing.expect(std.mem.indexOf(u8, denied.stdout, part) != null);
    const ordinary = try std.process.run(testing.allocator, testing.io, .{ .argv = &(.{ compilerPath(), "run-project", path, "--print-result" } ++ tools) });
    defer testing.allocator.free(ordinary.stdout);
    defer testing.allocator.free(ordinary.stderr);
    // The entry returns 7, which is now the process exit status.
    try testing.expectEqual(std.process.Child.Term{ .exited = 7 }, ordinary.term);
    try testing.expectEqualStrings("7\n", ordinary.stdout);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "rules file.json", .data = "{\"version\":1,\"default_action\":\"allow\",\"rules\":[]}" });
    const allowed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check-policy", path, option } });
    defer testing.allocator.free(allowed.stdout);
    defer testing.allocator.free(allowed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, allowed.term);
    try testing.expect(std.mem.indexOf(u8, allowed.stdout, "import-direction-v1: passed") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "rules file.json", .data = "{\"version\":99,\"default_action\":\"allow\",\"rules\":[]}" });
    const config_error = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check-policy", path, option } });
    defer testing.allocator.free(config_error.stdout);
    defer testing.allocator.free(config_error.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, config_error.term);
    try testing.expectEqualStrings("", config_error.stdout);
    try testing.expect(std.mem.indexOf(u8, config_error.stderr, "UnsupportedPolicyVersion") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "core.selka", .data =
        \\
        \\
        \\public func value() -> i64:
        \\    return True
    });
    const invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check-policy", path, option } });
    defer testing.allocator.free(invalid.stdout);
    defer testing.allocator.free(invalid.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, invalid.term);
    try testing.expectEqualStrings("", invalid.stdout);
    try testing.expect(std.mem.indexOf(u8, invalid.stderr, "E_TYPE") != null);
    try invoke("check-policy",
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , 2, "", "usage:");
    try invokeOptions("check-project",
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , &.{"--policy=some.json"}, 2, "", "usage:");
    try invokeOptions("check-policy",
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , &.{ "--policy=a", "--policy=b" }, 2, "", "usage:");
}
// spec: LINT-1
test "CLI lint reports L_ findings and blocks only under --gate" {
    const source =
        \\
        \\
        \\public func compute(value: int) -> int:
        \\    "Compute the input plus one."
        \\    return helper(value)
        \\
        \\
        \\func helper(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\func unused_helper(value: int) -> int:
        \\    return value - 1
        \\
        \\
        \\public func test_compute() -> bool:
        \\    return compute(1) == 2
        \\
        \\
        \\func main() -> int:
        \\    return 0
    ;
    // A plain run prints a report-only rule as one count line; `--gate` prints
    // the findings that refuse in full.
    try invoke("lint", source, 0, "lint: 1 finding(s): 0 blocking, 1 report, 0 waived, 0 accepted\n", "L_DEAD_PRIVATE: 1 finding (selka lint --all lists them)");
    try invokeOptions("lint", source, &.{"--gate"}, 3, "lint: 1 finding(s): 1 blocking, 0 report, 0 waived, 0 accepted\n", "error[L_DEAD_PRIVATE]");
    try invokeOptions("lint", source, &.{"--all"}, 0, "lint: 1 finding(s): 0 blocking, 1 report, 0 waived, 0 accepted\n", "warning[L_DEAD_PRIVATE]");
    try invokeOptions("lint", source, &.{ "--gate", "--json" }, 3, "lint: 1 finding(s): 1 blocking, 0 report, 0 waived, 0 accepted\n", "\"code\":\"L_DEAD_PRIVATE\"");
    try invokeOptions("lint", source, &.{"--nope"}, 2, "", "usage:");
}
test "CLI lint runs dead-write only when --rule names it, and it never refuses" {
    // The implicit-code audit's probe: an update made on a copy is lost (G9-X6, lane W7).
    const source =
        \\record Item:
        \\    name: str
        \\    count: int
        \\
        \\func bump(mut items: Item[]):
        \\    mut first = copy(items[0])
        \\    first.count = first.count + 1
        \\
        \\func main(out: Stream) -> int:
        \\    mut items: Item[] = []
        \\    append(mut items, Item(name="a", count=1))
        \\    bump(mut items)
        \\    print(out, items[0].count)
        \\    return 0
    ;
    try invoke("lint", source, 0, "lint: 0 finding(s): 0 blocking, 0 report, 0 waived, 0 accepted\n", "");
    try invokeOptions("lint", source, &.{"--gate"}, 0, "lint: 0 finding(s): 0 blocking, 0 report, 0 waived, 0 accepted\n", "");
    try invokeOptions("lint", source, &.{"--rule=dead-write"}, 0, "lint: 1 finding(s): 0 blocking, 1 report, 0 waived, 0 accepted\n", "L_DEAD_WRITE: 1 finding (selka lint --all lists them)");
    try invokeOptions("lint", source, &.{ "--rule=dead-write", "--all" }, 0, "lint: 1 finding(s): 0 blocking, 1 report, 0 waived, 0 accepted\n", "warning[L_DEAD_WRITE]: dead-write: nothing reads `first` after this field write");
    try invokeOptions("lint", source, &.{ "--rule=dead-write", "--gate" }, 0, "lint: 1 finding(s): 0 blocking, 1 report, 0 waived, 0 accepted\n", "L_DEAD_WRITE");
    try invokeOptions("lint", source, &.{"--rule=no-such-rule"}, 2, "", "usage:");
}
// spec-case: LINT-1
test "CLI lint prints one count line per report-only rule and --all lists every finding" {
    // `helper` is a block-mode rule (a plain run reports it), and the exported
    // declarations are report-only: one count line each, and the exported ones
    // are not printed in full until `--all` or `--json` asks for them.
    const source =
        \\
        \\public func exported_helper(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\func helper(value: int) -> int:
        \\    return value - 1
        \\
        \\
        \\func main() -> int:
        \\    return 0
    ;
    const plain = try runFixture("lint", source, &.{});
    defer testing.allocator.free(plain.stdout);
    defer testing.allocator.free(plain.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, plain.term);
    try testing.expect(std.mem.indexOf(u8, plain.stderr, "L_DEAD_PRIVATE: 1 finding (selka lint --all lists them)") != null);
    try testing.expect(std.mem.indexOf(u8, plain.stderr, "L_UNTESTED_EXPORT: 1 finding (selka lint --all lists them)") != null);
    try testing.expect(std.mem.indexOf(u8, plain.stderr, "warning[L_UNTESTED_EXPORT]") == null);
    try testing.expect(std.mem.indexOf(u8, plain.stderr, "warning[L_DEAD_PRIVATE]") == null);
    // The default output of a project that blocks nothing stays inside the plan's
    // 30-line target (G4): only the count lines and the summary line.
    try testing.expect(std.mem.count(u8, plain.stderr, "\n") <= 29);
    // `--all` lists every finding in full.
    const all = try runFixture("lint", source, &.{"--all"});
    defer testing.allocator.free(all.stdout);
    defer testing.allocator.free(all.stderr);
    try testing.expect(std.mem.indexOf(u8, all.stderr, "warning[L_UNTESTED_EXPORT]") != null);
    try testing.expect(std.mem.indexOf(u8, all.stderr, "warning[L_DEAD_PRIVATE]") != null);
    // `--json` is unchanged and always complete, with or without `--all`.
    const json = try runFixture("lint", source, &.{"--json"});
    defer testing.allocator.free(json.stdout);
    defer testing.allocator.free(json.stderr);
    try testing.expect(std.mem.indexOf(u8, json.stderr, "\"code\":\"L_UNTESTED_EXPORT\"") != null);
    try testing.expect(std.mem.indexOf(u8, json.stderr, "\"code\":\"L_DEAD_PRIVATE\"") != null);
    // `--gate` prints the findings that refuse in full and still counts the rest.
    const gated = try runFixture("lint", source, &.{"--gate"});
    defer testing.allocator.free(gated.stdout);
    defer testing.allocator.free(gated.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, gated.term);
    try testing.expect(std.mem.indexOf(u8, gated.stderr, "error[L_DEAD_PRIVATE]") != null);
    try testing.expect(std.mem.indexOf(u8, gated.stderr, "L_UNTESTED_EXPORT: 1 finding") != null);
}
// spec-case: LINT-1
test "CLI lint --against prints changed declarations in full without gate" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\
        \\func helper(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\func test_helper() -> bool:
        \\    return helper(1) == 2
        \\
        \\
        \\func stale_helper(value: int) -> int:
        \\    return value - 1
        \\
        \\
        \\func main() -> int:
        \\    return 0
    });
    try gitIn(testing.allocator, root, &.{ "init", "-q" });
    try gitIn(testing.allocator, root, &.{ "add", "main.selka" });
    try gitIn(testing.allocator, root, &.{ "-c", "user.email=test@example.com", "-c", "user.name=test", "commit", "-q", "-m", "init" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\
        \\func helper(value: int) -> int:
        \\    return value + 2
        \\
        \\
        \\func test_helper() -> bool:
        \\    return helper(1) == 2
        \\
        \\
        \\func stale_helper(value: int) -> int:
        \\    return value - 1
        \\
        \\
        \\func main() -> int:
        \\    return 0
    });
    const path = try std.fs.path.join(testing.allocator, &.{ root, "main.selka" });
    defer testing.allocator.free(path);
    // Without `--gate`, `--against` reports the changed declaration in full and
    // summarizes the unchanged one; both are listed by `--all` and `--json`.
    const against = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "lint", path, "--against=HEAD" } });
    defer testing.allocator.free(against.stdout);
    defer testing.allocator.free(against.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, against.term);
    try testing.expect(std.mem.indexOf(u8, against.stderr, "warning[L_CHANGE_WITHOUT_TEST]") != null);
    try testing.expect(std.mem.indexOf(u8, against.stderr, "L_DEAD_PRIVATE: 1 finding (selka lint --all lists them)") != null);
    try testing.expect(std.mem.indexOf(u8, against.stderr, "warning[L_DEAD_PRIVATE]") == null);
    const gated = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "lint", path, "--gate", "--against=HEAD" } });
    defer testing.allocator.free(gated.stdout);
    defer testing.allocator.free(gated.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, gated.term);
    try testing.expect(std.mem.indexOf(u8, gated.stderr, "error[L_CHANGE_WITHOUT_TEST]") != null);
}
// spec: NEEDLESS-COPY-1
test "CLI check warns W_NEEDLESS_COPY with its fix, and fix, lint and a waiver agree" {
    // Case (i): `total` only reads the argument, so the copy carries no value.
    const source =
        // migrate-embedded: skip intentional W_NEEDLESS_COPY warning and structured fix input
        \\
        \\func total(values: int[]) -> int:
        \\    mut sum = 0
        \\    for value in values:
        \\        sum += value
        \\    return sum
        \\
        \\
        \\func run(n: int) -> int:
        \\    mut xs: int[] = []
        \\    for i in range(8):
        \\        append(mut xs, i)
        \\    mut acc = 0
        \\    for i in range(n):
        \\        acc += total(copy(xs))
        \\    return acc
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, run(2))
        \\    return 0
    ;
    const checked = try runFixture("check", source, &.{});
    defer testing.allocator.free(checked.stdout);
    defer testing.allocator.free(checked.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
    try testing.expect(std.mem.indexOf(u8, checked.stderr, "warning[W_NEEDLESS_COPY]") != null);
    try testing.expect(std.mem.indexOf(u8, checked.stderr, "`total` only reads `xs`, so pass `xs` itself rather than a copy") != null);
    // The structured diagnostic carries the one certain edit.
    const structured = try runFixture("check", source, &.{"--diagnostics=json"});
    defer testing.allocator.free(structured.stdout);
    defer testing.allocator.free(structured.stderr);
    try testing.expect(std.mem.indexOf(u8, structured.stderr, "\"code\":\"W_NEEDLESS_COPY\"") != null);
    try testing.expect(std.mem.indexOf(u8, structured.stderr, "\"fix\":{\"edits\":[") != null);
    try testing.expect(std.mem.indexOf(u8, structured.stderr, "\"text\":\"xs\"") != null);
    // `selka fix` applies it, and the repaired entry checks without the warning.
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data = source });
    const path = try temp.dir.realPathFileAlloc(testing.io, "app.selka", testing.allocator);
    defer testing.allocator.free(path);
    const fixed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "fix", path, "--warnings" } });
    defer testing.allocator.free(fixed.stdout);
    defer testing.allocator.free(fixed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, fixed.term);
    try testing.expect(std.mem.indexOf(u8, fixed.stdout, "1 edit (W_NEEDLESS_COPY)") != null);
    const repaired = try temp.dir.readFileAlloc(testing.io, "app.selka", testing.allocator, .limited(64 * 1024));
    defer testing.allocator.free(repaired);
    try testing.expect(std.mem.indexOf(u8, repaired, "total(copy(xs))") == null);
    try testing.expect(std.mem.indexOf(u8, repaired, "total(xs)") != null);
    const after = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check", path } });
    defer testing.allocator.free(after.stdout);
    defer testing.allocator.free(after.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, after.term);
    try testing.expect(std.mem.indexOf(u8, after.stderr, "W_NEEDLESS_COPY") == null);
    // `lint --gate` refuses the copy, and a reasoned site waiver clears it.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data = source });
    const gated = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "lint", path, "--gate" } });
    defer testing.allocator.free(gated.stdout);
    defer testing.allocator.free(gated.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, gated.term);
    try testing.expect(std.mem.indexOf(u8, gated.stderr, "error[L_NEEDLESS_COPY]") != null);
    const waived_source = try std.mem.replaceOwned(u8, testing.allocator, source, "        acc += total(copy(xs))", "        # lint: allow needless-copy reason=\"this test is about copying\"\n        acc += total(copy(xs))");
    defer testing.allocator.free(waived_source);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data = waived_source });
    const waived = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "lint", path, "--gate" } });
    defer testing.allocator.free(waived.stdout);
    defer testing.allocator.free(waived.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, waived.term);
    try testing.expect(std.mem.indexOf(u8, waived.stderr, "L_NEEDLESS_COPY") == null);
}
// spec: LOOP-RULES-4
test "CLI lint reads cost --sites for alloc-in-loop only in a changed declaration" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data =
        \\func build(n: int) -> int:
        \\    mut total = 0
        \\    for i in range(n):
        \\        const d = {"a": i}
        \\        total += len(d)
        \\    return total
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, build(2))
        \\    return 0
    });
    try gitIn(testing.allocator, root, &.{ "init", "-q" });
    try gitIn(testing.allocator, root, &.{ "add", "app.selka" });
    try gitIn(testing.allocator, root, &.{ "-c", "user.email=test@example.com", "-c", "user.name=test", "commit", "-q", "-m", "init" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data =
        \\func build(n: int) -> int:
        \\    mut total = 0
        \\    for i in range(n):
        \\        const d = {"a": i}
        \\        total += len(d) + 1
        \\    return total
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, build(2))
        \\    return 0
    });
    const path = try std.fs.path.join(testing.allocator, &.{ root, "app.selka" });
    defer testing.allocator.free(path);
    // Without a diff the rule reports nothing; the analysis does not even run.
    const plain = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "lint", path } });
    defer testing.allocator.free(plain.stdout);
    defer testing.allocator.free(plain.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, plain.term);
    try testing.expect(std.mem.indexOf(u8, plain.stderr, "L_ALLOC_IN_LOOP") == null);
    // The changed declaration reads the `cost --sites` rows: the site's own line,
    // its kind, its loop depth and the kind's hint, and it never refuses.
    const against = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "lint", path, "--against=HEAD" } });
    defer testing.allocator.free(against.stdout);
    defer testing.allocator.free(against.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, against.term);
    try testing.expect(std.mem.indexOf(u8, against.stderr, "L_ALLOC_IN_LOOP") != null);
    try testing.expect(std.mem.indexOf(u8, against.stderr, "a construction site at loop depth 1") != null);
    try testing.expect(std.mem.indexOf(u8, against.stderr, "construct it once outside the loop") != null);
    try testing.expect(std.mem.indexOf(u8, against.stderr, ":4:19:") != null);
}
test "CLI lint reports a copy in a loop in a test file, and in the module the test reaches" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "gather_test.selka", .data =
        \\func gather(rows: str[]) -> str[]:
        \\    mut kept: str[] = []
        \\    for row in rows:
        \\        append(mut kept, copy(row))
        \\    return kept
        \\
        \\
        \\public func test_gather() -> bool:
        \\    return len(gather(["a", "b"])) == 2
    });
    const path = try std.fs.path.join(testing.allocator, &.{ root, "gather_test.selka" });
    defer testing.allocator.free(path);
    // A test file has no `main`, so `cost --sites` alone gives it no rows: the lint reads the functions its tests reach.
    const run = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "lint", "--all", path } });
    defer testing.allocator.free(run.stdout);
    defer testing.allocator.free(run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run.term);
    try testing.expect(std.mem.indexOf(u8, run.stderr, "L_COPY_IN_LOOP") != null);
    try testing.expect(std.mem.indexOf(u8, run.stderr, "a copy at loop depth 1 in `gather`") != null);
    try testing.expect(std.mem.indexOf(u8, run.stderr, ":4:26:") != null);
}
/// One copy of each category `lint --copies` counts and one that no finding names, in a program of 40 lines.
const copy_count_source =
    \\record Plan:
    \\    head: int[]
    \\
    \\
    \\func show(name: str) -> int:
    \\    return len(name)
    \\
    \\
    \\func needless(name: str) -> int:
    \\    return show(copy(name))
    \\
    \\
    \\func gather(rows: str[]) -> str[]:
    \\    mut taken: str[] = []
    \\    for row in rows:
    \\        append(mut taken, copy(row))
    \\    return taken
    \\
    \\
    \\func plan(head: int[]) -> Plan:
    \\    return Plan(head=copy(head))
    \\
    \\
    \\func spread(n: int) -> str[]:
    \\    const base = "x" + str(n)
    \\    mut out: str[] = []
    \\    for i in range(n):
    \\        append(mut out, copy(base))
    \\    return out
    \\
    \\
    \\func kept(xs: int[]) -> int:
    \\    mut ys = copy(xs)
    \\    append(mut ys, 1)
    \\    return len(ys)
    \\
    \\
    \\func main() -> int:
    \\    const made = plan([1])
    \\    return needless("a") + len(gather(["b"])) + len(made.head) + len(spread(2)) + kept([2])
    \\
;
// spec-case: LINT-1
test "CLI lint --copies prints how many copies the program writes by the finding that names each, as text and as JSON" {
    try invokeOptions("lint", copy_count_source, &.{"--copies"}, 0,
        \\copies: 5 in 40 lines, 125.0 per 1000 lines
        \\     1 selka fix removes them (L_NEEDLESS_COPY)
        \\     1 a move replaces them (L_COPY_MOVE)
        \\     1 stored from a parameter (L_COPY_FOR_STORE)
        \\     1 in a loop (L_COPY_IN_LOOP)
        \\     1 named by nothing
        \\
    , "");
    const json = try runFixture("lint", copy_count_source, &.{ "--copies", "--json" });
    defer testing.allocator.free(json.stdout);
    defer testing.allocator.free(json.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, json.term);
    try testing.expectEqualStrings("", json.stderr);
    const head = "{\"schema\":\"copy-count-v1\",\"entries\":1,\"copies\":5,\"lines\":40,\"per_1000\":125.0,\"needless\":1,\"move\":1,\"for_store\":1,\"in_loop\":1,\"unnamed\":1,\"files\":[{\"path\":\"";
    try testing.expect(std.mem.startsWith(u8, json.stdout, head));
    try testing.expect(std.mem.endsWith(u8, json.stdout, "input.selka\",\"copies\":5,\"lines\":40}]}\n"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, json.stdout, "\n"));
}
// spec-case: LINT-1
test "CLI lint --copies is a usage error beside --gate or --accept, and counts a test file's copy" {
    const refusal = "selka lint: --copies prints a count and refuses nothing, so it takes neither --gate nor --accept\n";
    for ([_][]const u8{ "--gate", "--accept" }) |other| {
        const refused = try runFixture("lint", copy_count_source, &.{ "--copies", other });
        defer testing.allocator.free(refused.stdout);
        defer testing.allocator.free(refused.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, refused.term);
        try testing.expectEqualStrings("", refused.stdout);
        try testing.expectEqualStrings(refusal, refused.stderr);
    }
    try invokeOptions("lint", copy_count_source, &.{ "--copies", "--copies" }, 2, "", "usage:");
    // A test file has no `main`: its copy is counted from the functions its tests reach, and the move finding names it first.
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "gather_test.selka", .data =
        \\func gather(rows: str[]) -> str[]:
        \\    mut kept: str[] = []
        \\    for row in rows:
        \\        append(mut kept, copy(row))
        \\    return kept
        \\
        \\
        \\public func test_gather() -> bool:
        \\    return len(gather(["a", "b"])) == 2
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "gather_test.selka", testing.allocator);
    defer testing.allocator.free(path);
    const run = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "lint", "--copies", path } });
    defer testing.allocator.free(run.stdout);
    defer testing.allocator.free(run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run.term);
    try testing.expect(std.mem.startsWith(u8, run.stdout, "copies: 1 in 9 lines, 111.1 per 1000 lines\n"));
    try testing.expect(std.mem.indexOf(u8, run.stdout, "     1 a move replaces them (L_COPY_MOVE)\n") != null);
}
/// Two entries that import one module with a copy in a loop; the first writes one more copy `selka fix` removes, the second one nothing names.
const copy_count_entry_files = [_]struct { name: []const u8, text: []const u8 }{
    .{ .name = "lib.selka", .text =
    \\public func spread(n: int) -> str[]:
    \\    const base = "x" + str(n)
    \\    mut out: str[] = []
    \\    for i in range(n):
    \\        append(mut out, copy(base))
    \\    return out
    \\
    },
    .{ .name = "a.selka", .text =
    \\import lib
    \\
    \\
    \\func show(name: str) -> int:
    \\    return len(name)
    \\
    \\
    \\func needless(name: str) -> int:
    \\    return show(copy(name))
    \\
    \\
    \\func main() -> int:
    \\    return needless("a") + len(lib.spread(2))
    \\
    },
    .{ .name = "b.selka", .text =
    \\import lib
    \\
    \\
    \\func kept(xs: int[]) -> int:
    \\    mut ys = copy(xs)
    \\    append(mut ys, 1)
    \\    return len(ys)
    \\
    \\
    \\func main() -> int:
    \\    return kept([2]) + len(lib.spread(3))
    \\
    },
    .{ .name = "bad.selka", .text =
    \\func main() -> int:
    \\    return nope
    \\
    },
};

/// `selka lint` over the entry files named in `names`, which `copy_count_entry_files` wrote into `temp`, with `switches` first.
fn lintEntries(temp: *testing.TmpDir, switches: []const []const u8, names: []const []const u8) !std.process.RunResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer {
        for (argv.items[2 + switches.len ..]) |path| testing.allocator.free(path);
        argv.deinit(testing.allocator);
    }
    try argv.appendSlice(testing.allocator, &.{ compilerPath(), "lint" });
    try argv.appendSlice(testing.allocator, switches);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    for (names) |name| try argv.append(testing.allocator, try std.fs.path.join(testing.allocator, &.{ root, name }));
    return std.process.run(testing.allocator, testing.io, .{ .argv = argv.items });
}

fn writeEntryFiles(temp: *testing.TmpDir) !void {
    for (copy_count_entry_files) |file| try temp.dir.writeFile(testing.io, .{ .sub_path = file.name, .data = file.text });
}

// spec-case: LINT-1
test "CLI lint --copies with several entries prints one count for the union of what they reach" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeEntryFiles(&temp);
    // Alone, each entry counts the shared module's copy: two copies and two copies.
    const alone = try lintEntries(&temp, &.{"--copies"}, &.{"a.selka"});
    defer testing.allocator.free(alone.stdout);
    defer testing.allocator.free(alone.stderr);
    try testing.expect(std.mem.startsWith(u8, alone.stdout, "copies: 2 in 19 lines, 105.3 per 1000 lines\n"));
    // Together the module is read once: its 6 lines and its one copy count once.
    const both = try lintEntries(&temp, &.{"--copies"}, &.{ "a.selka", "b.selka" });
    defer testing.allocator.free(both.stdout);
    defer testing.allocator.free(both.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, both.term);
    try testing.expectEqualStrings("", both.stderr);
    try testing.expectEqualStrings(
        \\entries: 2
        \\copies: 3 in 30 lines, 100.0 per 1000 lines
        \\     1 selka fix removes them (L_NEEDLESS_COPY)
        \\     0 a move replaces them (L_COPY_MOVE)
        \\     0 stored from a parameter (L_COPY_FOR_STORE)
        \\     1 in a loop (L_COPY_IN_LOOP)
        \\     1 named by nothing
        \\
    , both.stdout);
    // The order of the entries changes nothing, and an entry that is itself a module the others reach adds no copy and no line.
    const json = try lintEntries(&temp, &.{ "--copies", "--json" }, &.{ "b.selka", "a.selka", "lib.selka" });
    defer testing.allocator.free(json.stdout);
    defer testing.allocator.free(json.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, json.term);
    const head = "{\"schema\":\"copy-count-v1\",\"entries\":3,\"copies\":3,\"lines\":30,\"per_1000\":100.0,\"needless\":1,\"move\":0,\"for_store\":0,\"in_loop\":1,\"unnamed\":1,\"files\":[";
    try testing.expect(std.mem.startsWith(u8, json.stdout, head));
    try testing.expect(std.mem.endsWith(u8, json.stdout, "lib.selka\",\"copies\":1,\"lines\":6}]}\n"));
    try testing.expectEqual(@as(usize, 3), std.mem.count(u8, json.stdout, "\"path\""));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, json.stdout, "\n"));
    // One entry keeps its text, and its JSON names the one entry.
    const one = try lintEntries(&temp, &.{ "--copies", "--json" }, &.{"a.selka"});
    defer testing.allocator.free(one.stdout);
    defer testing.allocator.free(one.stderr);
    try testing.expect(std.mem.startsWith(u8, one.stdout, "{\"schema\":\"copy-count-v1\",\"entries\":1,\"copies\":2,\"lines\":19,"));
}

/// `selka lint --copies main.selka` run in `dir`, whose `.selka-cache` the lint reads and writes, under `environment`'s stores.
fn lintCopiesIn(dir: std.Io.Dir, environment: *const std.process.Environ.Map) !std.process.RunResult {
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
    defer testing.allocator.free(compiler);
    return std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler, "lint", "--copies", "main.selka" }, .cwd = .{ .dir = dir }, .environ_map = environment });
}

/// A program whose `header` takes `name` borrowed (the test edits it to `own`), called by `build`, with a copy in `spread`'s loop.
const own_edit_source =
    \\record Header:
    \\    name: str
    \\    value: str
    \\
    \\
    \\func header(name: str, value: str) -> Header:
    \\    return Header(name=copy(name), value=copy(value))
    \\
    \\
    \\func build(location: str) -> Header[]:
    \\    mut out: Header[] = []
    \\    append(mut out, header(copy("Location"), location))
    \\    return out
    \\
    \\
    \\func spread(n: int) -> str[]:
    \\    const base = "x" + str(n)
    \\    mut out: str[] = []
    \\    for i in range(n):
    \\        append(mut out, copy(base))
    \\    return out
    \\
    \\
    \\func main() -> int:
    \\    return len(build("x")) + len(spread(2))
    \\
;

// spec-case: LINT-1
test "CLI lint --copies counts what a cold tree counts after a callee's parameter becomes own in a work directory the lint warmed" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    defer environment.deinit();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = own_edit_source });
    const before = try lintCopiesIn(temp.dir, &environment);
    defer testing.allocator.free(before.stdout);
    defer testing.allocator.free(before.stderr);
    try testing.expect(std.mem.indexOf(u8, before.stdout, "     1 in a loop (L_COPY_IN_LOOP)\n") != null);
    // The one edit that changes no caller's text: `header` takes `name` owned. `build` is unchanged, and the work directory
    // holds it as lowered for a callee that borrows.
    const declared = try std.mem.replaceOwned(u8, testing.allocator, own_edit_source, "func header(name: str", "func header(own name: str");
    defer testing.allocator.free(declared);
    const edited = try std.mem.replaceOwned(u8, testing.allocator, declared, "Header(name=copy(name)", "Header(name=own name");
    defer testing.allocator.free(edited);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = edited });
    const warm = try lintCopiesIn(temp.dir, &environment);
    defer testing.allocator.free(warm.stdout);
    defer testing.allocator.free(warm.stderr);
    try temp.dir.deleteTree(testing.io, ".selka-cache");
    const cold = try lintCopiesIn(temp.dir, &environment);
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expect(std.mem.indexOf(u8, cold.stdout, "     1 in a loop (L_COPY_IN_LOOP)\n") != null);
    try testing.expectEqualStrings(cold.stdout, warm.stdout);
}

/// `selka lint SWITCHES... main.selka` run in `dir`, whose `.selka-cache` the lint reads and writes, under `environment`'s stores.
fn lintMainIn(dir: std.Io.Dir, environment: *const std.process.Environ.Map, switches: []const []const u8) !std.process.RunResult {
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.appendSlice(testing.allocator, &.{ compiler, "lint" });
    try argv.appendSlice(testing.allocator, switches);
    try argv.append(testing.allocator, "main.selka");
    return std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = dir }, .environ_map = environment });
}

/// A program `check` accepts and the Core build the lint's analysis makes refuses: `fill` promises `@noalloc` and allocates
/// (`E_NOALLOC_ALLOCATES`). `spread` copies in a loop, which the failed analysis cannot see.
const failed_analysis_source =
    \\@noalloc
    \\func fill(n: int) -> int[]:
    \\    mut out: int[] = []
    \\    for i in range(n):
    \\        append(mut out, i)
    \\    return out
    \\
    \\
    \\func spread(n: int) -> str[]:
    \\    const base = "x" + str(n)
    \\    mut out: str[] = []
    \\    for i in range(n):
    \\        append(mut out, copy(base))
    \\    return out
    \\
    \\
    \\func main() -> int:
    \\    return len(fill(2)) + len(spread(2))
    \\
;

const analysis_failed_line = "selka lint: main.selka: the analysis behind the loop rules failed (E_NOALLOC_ALLOCATES), so L_ALLOC_IN_LOOP and L_COPY_IN_LOOP were not judged";

// spec-case: LINT-1
test "CLI lint --copies says the split is not known when the analysis behind the loop rules fails" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    defer environment.deinit();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = failed_analysis_source });
    const text = try lintMainIn(temp.dir, &environment, &.{"--copies"});
    defer testing.allocator.free(text.stdout);
    defer testing.allocator.free(text.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, text.term);
    try testing.expectEqualStrings(analysis_failed_line ++ "\n", text.stderr);
    try testing.expectEqualStrings(
        \\copies: 1 in 18 lines, 55.6 per 1000 lines
        \\     0 selka fix removes them (L_NEEDLESS_COPY)
        \\     0 a move replaces them (L_COPY_MOVE)
        \\     0 stored from a parameter (L_COPY_FOR_STORE)
        \\     ? in a loop (L_COPY_IN_LOOP): not known, the analysis failed
        \\     ? named by nothing: not known, the analysis failed (the two lines share 1 copy)
        \\
    , text.stdout);
    // The JSON carries the same: the two unknown counts are null, `split_known` is false, and the sum that is known is its own field.
    const json = try lintMainIn(temp.dir, &environment, &.{ "--copies", "--json" });
    defer testing.allocator.free(json.stdout);
    defer testing.allocator.free(json.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, json.term);
    try testing.expectEqualStrings(analysis_failed_line ++ "\n", json.stderr);
    try testing.expectEqualStrings(
        \\{"schema":"copy-count-v1","entries":1,"copies":1,"lines":18,"per_1000":55.6,"needless":0,"move":0,"for_store":0,"in_loop":null,"unnamed":null,"split_known":false,"in_loop_or_unnamed":1,"files":[{"path":"main.selka","copies":1,"lines":18}]}
        \\
    , json.stdout);
}

// spec-case: LINT-1
test "CLI lint --copies prints what it always printed when the analysis ran, or when a file has no main to analyse" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    defer environment.deinit();
    // The same program with the promise taken away: the analysis runs and the loop copy is named.
    const kept = try std.mem.replaceOwned(u8, testing.allocator, failed_analysis_source, "@noalloc\n", "");
    defer testing.allocator.free(kept);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = kept });
    const ran = try lintMainIn(temp.dir, &environment, &.{"--copies"});
    defer testing.allocator.free(ran.stdout);
    defer testing.allocator.free(ran.stderr);
    try testing.expectEqualStrings("", ran.stderr);
    try testing.expectEqualStrings(
        \\copies: 1 in 17 lines, 58.8 per 1000 lines
        \\     0 selka fix removes them (L_NEEDLESS_COPY)
        \\     0 a move replaces them (L_COPY_MOVE)
        \\     0 stored from a parameter (L_COPY_FOR_STORE)
        \\     1 in a loop (L_COPY_IN_LOOP)
        \\     0 named by nothing
        \\
    , ran.stdout);
    // A file with no `main` and no tests has nothing to analyse: no line, and today's counts (its copy is named by nothing).
    const library = try std.mem.replaceOwned(u8, testing.allocator, kept, "func main() -> int:\n    return len(fill(2)) + len(spread(2))\n", "");
    defer testing.allocator.free(library);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = library });
    const nothing = try lintMainIn(temp.dir, &environment, &.{ "--copies", "--json" });
    defer testing.allocator.free(nothing.stdout);
    defer testing.allocator.free(nothing.stderr);
    try testing.expectEqualStrings("", nothing.stderr);
    try testing.expect(std.mem.indexOf(u8, nothing.stdout, "\"in_loop\":0,\"unnamed\":1,\"files\"") != null);
}

// spec-case: LINT-1
test "CLI lint names the failed analysis on standard error, and --gate refuses for it when no finding does" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    defer environment.deinit();
    // The one finding the failure comes with is waived, so a gate that refuses does so for the rules it could not judge.
    const waived = try std.mem.concat(testing.allocator, u8, &.{ "# lint: allow noalloc-allocates reason=\"the test needs the failure\"\n", failed_analysis_source });
    defer testing.allocator.free(waived);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = waived });
    const plain = try lintMainIn(temp.dir, &environment, &.{});
    defer testing.allocator.free(plain.stdout);
    defer testing.allocator.free(plain.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, plain.term);
    try testing.expect(std.mem.indexOf(u8, plain.stderr, analysis_failed_line ++ "\n") != null);
    try testing.expect(std.mem.indexOf(u8, plain.stdout, "lint: 0 finding(s): 0 blocking, 0 report, 1 waived, 0 accepted\n") != null);
    const gate = try lintMainIn(temp.dir, &environment, &.{"--gate"});
    defer testing.allocator.free(gate.stdout);
    defer testing.allocator.free(gate.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, gate.term);
    try testing.expect(std.mem.indexOf(u8, gate.stderr, analysis_failed_line ++ "; --gate refuses (status 3)\n") != null);
    try testing.expect(std.mem.indexOf(u8, gate.stdout, "lint: 0 finding(s): 0 blocking, 0 report, 1 waived, 0 accepted\n") != null);
}

// spec-case: LINT-1
test "CLI lint --copies with several entries stops at an entry that gives no count, and takes several only with --copies" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeEntryFiles(&temp);
    // An entry that does not check ends the command as a lone one does (its diagnostics, status 1, no count), and is named.
    const bad = try lintEntries(&temp, &.{"--copies"}, &.{ "a.selka", "bad.selka", "b.selka" });
    defer testing.allocator.free(bad.stdout);
    defer testing.allocator.free(bad.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, bad.term);
    try testing.expectEqualStrings("", bad.stdout);
    try testing.expect(std.mem.indexOf(u8, bad.stderr, "E_UNKNOWN_NAME") != null);
    try testing.expect(std.mem.indexOf(u8, bad.stderr, "bad.selka gave no count (status 1), so there is no total\n") != null);
    // A file that is not there is refused by name, as for one entry, before the first entry is linted.
    try temp.dir.deleteFile(testing.io, "b.selka");
    const missing = try lintEntries(&temp, &.{"--copies"}, &.{ "a.selka", "b.selka" });
    defer testing.allocator.free(missing.stdout);
    defer testing.allocator.free(missing.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, missing.term);
    try testing.expectEqualStrings("", missing.stdout);
    try testing.expect(std.mem.indexOf(u8, missing.stderr, "b.selka': no such file or directory") != null);
    try testing.expect(std.mem.indexOf(u8, missing.stderr, "gave no count") == null);
    // Several entries without `--copies`, or beside `--gate`, are a usage error.
    const plain = try lintEntries(&temp, &.{}, &.{ "a.selka", "lib.selka" });
    defer testing.allocator.free(plain.stdout);
    defer testing.allocator.free(plain.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, plain.term);
    try testing.expect(std.mem.startsWith(u8, plain.stderr, "usage:"));
    const gated = try lintEntries(&temp, &.{ "--copies", "--gate" }, &.{ "a.selka", "lib.selka" });
    defer testing.allocator.free(gated.stdout);
    defer testing.allocator.free(gated.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, gated.term);
    try testing.expectEqualStrings("", gated.stdout);
}
// spec-case: LINT-1
test "CLI lint test hygiene rules flag fake tests and leave expression tests alone" {
    const source =
        \\
        \\
        \\func square(value: int) -> int:
        \\    return value * value
        \\
        \\
        \\func test_expression() -> bool:
        \\    return square(3) == 9
        \\
        \\
        \\func test_fake() -> bool:
        \\    return True
        \\
        \\
        \\func test_conditional() -> bool:
        \\    if 1 == 1:
        \\        assert 1 == 1
        \\        return True
        \\    return False
        \\
        \\
        \\func main() -> int:
        \\    return 0
    ;
    try invokeOptions("lint", source, &.{"--gate"}, 3, "lint: 2 finding(s): 2 blocking, 0 report, 0 waived, 0 accepted\n", "L_TEST_NO_ASSERTION");
    try invokeOptions("lint", source, &.{ "--gate", "--json" }, 3, "lint: 2 finding(s): 2 blocking, 0 report, 0 waived, 0 accepted\n", "L_TEST_CONDITIONAL");
}
// spec-case: LINT-1
test "CLI lint size rules report in a plain run and refuse under gate" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = "{\"version\":2,\"lint\":{\"rules\":{\"function-length\":{\"max\":1}}}}" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data =
        \\
        \\
        \\func value(input: int) -> int:
        \\    if input > 0:
        \\        return input
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return value(1)
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "app.selka", testing.allocator);
    defer testing.allocator.free(path);
    // Stage 5's flip (DECISIONS F38): a plain run still only reports, and `--gate`
    // is what `release check` runs, so that is where the budget refuses.
    const plain = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "lint", path } });
    defer testing.allocator.free(plain.stdout);
    defer testing.allocator.free(plain.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, plain.term);
    try testing.expect(std.mem.indexOf(u8, plain.stdout, "0 blocking") != null);
    try testing.expect(std.mem.indexOf(u8, plain.stderr, "L_FUNCTION_LENGTH") != null);
    const gated = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "lint", path, "--gate" } });
    defer testing.allocator.free(gated.stdout);
    defer testing.allocator.free(gated.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, gated.term);
    try testing.expect(std.mem.indexOf(u8, gated.stdout, "1 blocking") != null);
}
// spec-case: LINT-2
test "CLI warnings deny makes a checker warning rejecting in check and check-project" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data =
        \\
        \\
        \\func main() -> int:
        \\    mut unused: int = 1
        \\    return 0
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "app.selka", testing.allocator);
    defer testing.allocator.free(path);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = "{\"version\":2,\"lint\":{\"warnings\":\"deny\"}}" });
    const denied = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check", path } });
    defer testing.allocator.free(denied.stdout);
    defer testing.allocator.free(denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, denied.term);
    try testing.expect(std.mem.indexOf(u8, denied.stderr, "W_UNUSED_BINDING") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = "{\"version\":2,\"lint\":{\"warnings\":\"report\"}}" });
    const reported = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check", path } });
    defer testing.allocator.free(reported.stdout);
    defer testing.allocator.free(reported.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, reported.term);
    try testing.expect(std.mem.indexOf(u8, reported.stderr, "W_UNUSED_BINDING") != null);
}
// spec-case: UNUSED-IMPORT-1
test "CLI check-project reports an import no reference resolves through" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data =
        \\
        \\
        \\public func value() -> int:
        \\    return 42
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "unused_mod.selka", .data =
        \\
        \\
        \\public func thing() -> int:
        \\    return 1
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\import helper
        \\import unused_mod
        \\
        \\
        \\func main() -> int:
        \\    mut note = "unused_mod.thing()"
        \\    return helper.value() - 42
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(path);
    const reported = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check-project", path } });
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = "{\"version\":2,\"lint\":{\"warnings\":\"deny\"}}" });
    const denied = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check-project", path } });
    defer testing.allocator.free(denied.stdout);
    defer testing.allocator.free(denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, denied.term);
}
// spec-case: TESTS-FOR-1
test "CLI tests-for lists direct and transitive tests and rejects an unknown name" {
    const source =
        \\
        \\
        \\func parse(value: int) -> int:
        \\    return helper(value)
        \\
        \\
        \\func helper(value: int) -> int:
        \\    return value
        \\
        \\
        \\func test_parse() -> bool:
        \\    return parse(1) == 1
        \\
        \\
        \\func main() -> int:
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
    // migrate-embedded: skip intentional E_EFFECTS_REMOVED original navigation witness
    const original =
        \\
        \\
        \\func parse(value: int) -> int:
        \\    return helper(value)
        \\
        \\
        \\func helper(value: int) -> int:
        \\    return value
        \\
        \\
        \\func test_parse() -> bool effects():
        \\    return parse(1) == 1
        \\
        \\
        \\func main() -> int:
        \\    return 0
    ;
    // Keep the original spelling executable as a removal witness. The modern
    // counterpart below must still reach the syntax graph after an E_TYPE.
    try invoke("check", original, 1, "", "error[E_EFFECTS_REMOVED]");
    const source = try std.mem.replaceOwned(u8, testing.allocator, original, " effects()", "");
    defer testing.allocator.free(source);
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
    try invokeOptions("tests-for", "func parse(value: int) -> int:\n    return +\n", &.{"input::parse"}, 1, "", "the project does not parse");
}
// spec-case: NAVIGATION-SELECT-1
test "CLI index-project prints the summary by default, the full document on --full and a selection per filter" {
    const source =
        \\
        \\
        \\func helper(value: int) -> int:
        \\    return value
        \\
        \\
        \\func main() -> int:
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
        \\
        \\
        \\public func compute(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\func test_compute() -> bool:
        \\    return compute(1) == 2
        \\
        \\
        \\func main() -> int:
        \\    return 0
    ;
    try invoke("lint", source, 0, "lint: 1 finding(s): 0 blocking, 1 report, 0 waived, 0 accepted\n", "L_UNDOCUMENTED_EXPORT");
    const strict = try runFixture("lint", source, &.{ "--gate", "--profile=strict" });
    defer testing.allocator.free(strict.stdout);
    defer testing.allocator.free(strict.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, strict.term);
    try testing.expectEqualStrings("lint: 3 finding(s): 1 blocking, 2 report, 0 waived, 0 accepted\n", strict.stdout);
    try testing.expect(std.mem.indexOf(u8, strict.stderr, "L_UNDOCUMENTED_EXPORT") != null);
    try testing.expect(std.mem.indexOf(u8, strict.stderr, "L_UNDOCUMENTED_MODULE") != null);
    try testing.expect(std.mem.indexOf(u8, strict.stderr, "L_MISSING_EXAMPLE") != null);
    const documented =
        \\
        \\
        \\public func compute(value: int) -> int:
        \\    "Compute the input plus one."
        \\    return value + 1
        \\
        \\
        \\func test_compute() -> bool:
        \\    return compute(1) == 2
        \\
        \\
        \\func main() -> int:
        \\    return 0
    ;
    try invokeOptions("lint", documented, &.{ "--gate", "--profile=strict" }, 0, "lint: 2 finding(s): 0 blocking, 2 report, 0 waived, 0 accepted\n", "L_MISSING_EXAMPLE");
    const complete =
        \\"Arithmetic examples for documentation diagnostics."
        \\
        \\public func compute(value: int) -> int:
        \\    """Compute the input plus one.
        \\
        \\    >>> compute(1)
        \\    2
        \\    """
        \\    return value + 1
        \\
        \\func test_compute() -> bool:
        \\    return compute(1) == 2
        \\
        \\func main() -> int:
        \\    return 0
    ;
    try invokeOptions("lint", complete, &.{ "--gate", "--profile=strict" }, 0, "lint: 0 finding(s): 0 blocking, 0 report, 0 waived, 0 accepted\n", "");
}
// spec-case: API-DIFF-1
test "CLI api-diff records a baseline and classifies body and interface changes" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data =
        \\
        \\
        \\public func compute(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\func main() -> int:
        \\    return 0
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "app.selka", testing.allocator);
    defer testing.allocator.free(path);
    const baseline = try std.fs.path.join(testing.allocator, &.{ root, "baseline.txt" });
    defer testing.allocator.free(baseline);
    const write_option = try std.fmt.allocPrint(testing.allocator, "--write={s}", .{baseline});
    defer testing.allocator.free(write_option);
    const against_option = try std.fmt.allocPrint(testing.allocator, "--against={s}", .{baseline});
    defer testing.allocator.free(against_option);
    const write = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "api-diff", path, write_option } });
    defer testing.allocator.free(write.stdout);
    defer testing.allocator.free(write.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, write.term);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data =
        \\
        \\
        \\public func compute(value: int) -> int:
        \\    return value + 2
        \\
        \\
        \\func main() -> int:
        \\    return 0
    });
    const body = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "api-diff", path, against_option } });
    defer testing.allocator.free(body.stdout);
    defer testing.allocator.free(body.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, body.term);
    try testing.expect(std.mem.indexOf(u8, body.stdout, "compatible=1") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data =
        \\
        \\
        \\public func compute(value: int, extra: int) -> int:
        \\    return value + extra
        \\
        \\
        \\func main() -> int:
        \\    return 0
    });
    const signature = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "api-diff", path, against_option, "--json" } });
    defer testing.allocator.free(signature.stdout);
    defer testing.allocator.free(signature.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, signature.term);
    try testing.expect(std.mem.indexOf(u8, signature.stdout, "\"breaking\":[\"app::compute\"]") != null);
    const missing = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "api-diff", path, "--against=absent.txt" } });
    defer testing.allocator.free(missing.stdout);
    defer testing.allocator.free(missing.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, missing.term);
}

test "CLI O3 api-diff reads declared from contracts despite invalid bodies" {
    const allocator = testing.allocator;
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", allocator);
    defer allocator.free(root);
    try temp.dir.writeFile(testing.io, .{
        .sub_path = "app.selka",
        .data = "public func pick(a: str, b: str) -> str from b,a:\n    return missing()\nfunc main() -> int:\n    return 0\n",
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "app.selka", allocator);
    defer allocator.free(path);
    const baseline = try std.fs.path.join(allocator, &.{ root, "baseline.txt" });
    defer allocator.free(baseline);
    const write_option = try std.fmt.allocPrint(allocator, "--write={s}", .{baseline});
    defer allocator.free(write_option);
    const against_option = try std.fmt.allocPrint(allocator, "--against={s}", .{baseline});
    defer allocator.free(against_option);
    const written = try std.process.run(allocator, testing.io, .{ .argv = &.{ compilerPath(), "api-diff", path, write_option } });
    defer allocator.free(written.stdout);
    defer allocator.free(written.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, written.term);
    try testing.expectEqualStrings("", written.stderr);
    try temp.dir.writeFile(testing.io, .{
        .sub_path = "app.selka",
        .data = "public func pick(a: str, b: str) -> str from a,b:\n    return missing()\nfunc main() -> int:\n    return 0\n",
    });
    const reordered = try std.process.run(allocator, testing.io, .{ .argv = &.{ compilerPath(), "api-diff", path, against_option } });
    defer allocator.free(reordered.stdout);
    defer allocator.free(reordered.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, reordered.term);
    try testing.expect(std.mem.indexOf(u8, reordered.stdout, "breaking=0 unchanged=2") != null);
    try temp.dir.writeFile(testing.io, .{
        .sub_path = "app.selka",
        .data = "public func pick(a: str, b: str) -> str from a:\n    return missing()\nfunc main() -> int:\n    return 0\n",
    });
    const narrowed = try std.process.run(allocator, testing.io, .{ .argv = &.{ compilerPath(), "api-diff", path, against_option, "--json" } });
    defer allocator.free(narrowed.stdout);
    defer allocator.free(narrowed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, narrowed.term);
    try testing.expect(std.mem.indexOf(u8, narrowed.stdout, "\"compatible\":[\"app::pick\"]") != null);
    try testing.expect(std.mem.indexOf(u8, narrowed.stdout, "\"breaking\":[]") != null);
}

/// The module the interface-file CLI fixtures publish, and its entry.
const api_app_source =
    \\
    \\
    \\public func compute(value: int) -> int:
    \\    return value + 1
    \\
;
const api_main_source =
    \\import app
    \\
    \\
    \\func main() -> int:
    \\    return app.compute(41) - 42
    \\
;

/// The interface file `api_app_source` renders.
const api_app_interface =
    \\# generated by selka api; do not edit
    \\module app
    \\
    \\public func compute(value: int) -> int
    \\
;

/// One `selka` run in the interface-file fixture directory with its own cache.
const ApiRun = struct {
    root: []const u8,
    entry: []const u8,
    cache: []const u8,

    fn run(self: ApiRun, command: []const u8, options: []const []const u8) !std.process.RunResult {
        // The fixture runs from its own directory, so the compiler is named absolutely.
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
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

fn writeApiFixture(dir: std.Io.Dir, config: ?[]const u8) !void {
    try dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data = api_app_source });
    try dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = api_main_source });
    if (config) |bytes| try dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = bytes });
}

// spec-case: API-FILE-2
test "CLI api --check and --write: exit codes, diff, json, body-edit stability and cache states" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    try writeApiFixture(temp.dir, null);
    const cold = ApiRun{ .root = root, .entry = "main.selka", .cache = "--cache-dir=cold" };
    const warm = ApiRun{ .root = root, .entry = "main.selka", .cache = "--cache-dir=warm" };

    try expectApi(cold, "api", &.{}, 2, "", "usage:");
    try expectApi(cold, "api", &.{ "--write", "--check" }, 2, "", "usage:");
    try expectApi(warm, "api", &.{"--check"}, 1, "api: app is missing (app.api)\n--- app.api\n+++ app.api (generated)\n@@ -0,0 +1,4 @@\n+# generated by selka api; do not edit\n", "");
    try expectApi(warm, "api", &.{"--check"}, 1, "api: 2 interface files out of date; run `selka api main.selka --write`\n", "");
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
    try expectApi(.{ .root = root, .entry = "main.selka", .cache = "--no-cache" }, "api", &.{"--check"}, 0, "api: 2 interface files current\n", "");

    // A body edit leaves the file byte-identical; a signature edit does not.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data = "\n\npublic func compute(value: int) -> int:\n    # changed body\n    return 1 + value\n" });
    try expectApi(warm, "api", &.{"--write"}, 0, "api: 2 interface files current\n", "");
    const body_bytes = try temp.dir.readFileAlloc(testing.io, "app.api", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(body_bytes);
    try testing.expectEqualStrings(warm_bytes, body_bytes);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data = "\n\npublic func compute(value: int, extra: int = 1) -> int:\n    return value + extra\n" });
    try expectApi(warm, "api", &.{"--check"}, 1, "@@ -2,3 +2,3 @@\n module app\n \n-public func compute(value: int) -> int\n+public func compute(value: int, extra: int = 1) -> int\n", "");
    try expectApi(warm, "api", &.{ "--check", "--json" }, 1, "{\"version\":\"interface-files-v1\",\"mode\":\"check\",\"status\":\"stale\",\"files\":2,\"modules\":[{\"module\":\"app\",\"path\":\"app.api\",\"state\":\"stale\",\"added\":[],\"removed\":[],\"changed\":[\"compute\"]}]}\n", "");
    try expectApi(warm, "api", &.{ "--write", "--json" }, 0, "\"mode\":\"write\",\"status\":\"updated\"", "");
    try expectApi(warm, "api", &.{ "--check", "--json" }, 0, "{\"version\":\"interface-files-v1\",\"mode\":\"check\",\"status\":\"current\",\"files\":2,\"modules\":[]}\n", "");

    // A generated file whose source is gone is an orphan until --write deletes it.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "old.api", .data = "# generated by selka api; do not edit\nmodule old\n" });
    try expectApi(warm, "api", &.{"--check"}, 1, "api: old is orphaned (old.api)\n", "");
    try expectApi(warm, "api", &.{"--write"}, 0, "api: deleted old.api (old)\n", "");
    try testing.expectError(error.FileNotFound, temp.dir.statFile(testing.io, "old.api", .{}));
}

// spec: API-FILE-3
test "CLI check rejects a stale interface file when selka.json sets interface_files" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    try writeApiFixture(temp.dir, "{\"version\": 1, \"interface_files\": true}");
    const fixture = ApiRun{ .root = root, .entry = "main.selka", .cache = "--cache-dir=cache" };

    try expectApi(fixture, "check", &.{}, 1, "", "app.api:1:1: error[E_INTERFACE_FILE_STALE]: the interface file of module `app` is missing; run `selka api main.selka --write` and review its diff\n");
    try expectApi(fixture, "api", &.{"--write"}, 0, "", "");
    try expectApi(fixture, "check", &.{}, 0, "", "");
    // The replayed success is keyed on the interface files' bytes.
    try expectApi(fixture, "check", &.{}, 0, "", "");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.api", .data = "# generated by selka api; do not edit\n" });
    try expectApi(fixture, "check", &.{}, 1, "", "app.api:1:1: error[E_INTERFACE_FILE_STALE]: the interface file of module `app` is stale;");
    try expectApi(fixture, "run", &.{}, 1, "", "E_INTERFACE_FILE_STALE");
    try expectApi(fixture, "api", &.{"--write"}, 0, "", "");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data = "\n\npublic func compute(value: int) -> int:\n    return value + 2\n" });
    try expectApi(fixture, "check", &.{}, 0, "", "");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data = "\n\n@deprecated(\"use compute2\")\npublic func compute(value: int) -> int:\n    return value + 1\n" });
    try expectApi(fixture, "check", &.{}, 1, "", "app.api:1:1: error[E_INTERFACE_FILE_STALE]");
    try temp.dir.deleteFile(testing.io, "app.api");
    try expectApi(fixture, "check-project", &.{}, 1, "", "is missing");

    // Without the key nothing is enforced, and the value must be a boolean.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = "{\"version\": 1, \"interface_files\": false}" });
    try expectApi(fixture, "check", &.{}, 0, "", "");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = "{\"version\": 1, \"interface_files\": \"yes\"}" });
    try expectApi(fixture, "check", &.{}, 2, "", "error[E_PROJECT_CONFIG]: interface_files must be true or false");
}

// spec-case: API-FILE-3
test "CLI a test module needs no interface file, and api of a test file writes those of the modules it tests" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    try writeApiFixture(temp.dir, "{\"version\": 1, \"interface_files\": true}");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app_test.selka", .data = "import app\n\npublic func test_compute() -> bool:\n    return app.compute(1) == 2\n" });
    const tests = ApiRun{ .root = root, .entry = "app_test.selka", .cache = "--cache-dir=cache" };
    // The test file is the entry, so it is no module that any other file imports: only `app` has a file to be current.
    try expectApi(tests, "check", &.{}, 1, "", "app.api:1:1: error[E_INTERFACE_FILE_STALE]: the interface file of module `app` is missing");
    try expectApi(tests, "api", &.{"--write"}, 0, "api: wrote app.api (app)\napi: 1 interface files current (1 written, 0 deleted)\n", "");
    try testing.expectError(error.FileNotFound, temp.dir.statFile(testing.io, "app_test.api", .{}));
    try expectApi(tests, "check", &.{}, 0, "", "");
    try expectApi(tests, "api", &.{"--check"}, 0, "api: 1 interface files current\n", "");
    // The application's own entry has a file, and a file written for a test module before is left alone, never required or compared.
    try expectApi(.{ .root = root, .entry = "main.selka", .cache = "--cache-dir=cache" }, "api", &.{"--write"}, 0, "api: wrote main.api (main)\n", "");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app_test.api", .data = "# generated by selka api; do not edit\nmodule app_test\n" });
    try expectApi(tests, "check", &.{}, 0, "", "");
    try expectApi(tests, "api", &.{"--write"}, 0, "api: 1 interface files current\n", "");
    _ = try temp.dir.statFile(testing.io, "app_test.api", .{});
}

// spec-case: API-FILE-3
test "CLI the interface-files example keeps its checked-in interface files current" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const cache = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(cache);
    const cache_option = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_option);
    const entry = "examples/interface-files/main.selka";
    const checked = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "api", entry, "--check", cache_option } });
    defer testing.allocator.free(checked.stdout);
    defer testing.allocator.free(checked.stderr);
    try testing.expectEqualStrings("api: 3 interface files current\n", checked.stdout);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
    const project = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check-project", entry, cache_option } });
    defer testing.allocator.free(project.stdout);
    defer testing.allocator.free(project.stderr);
    try testing.expectEqualStrings("", project.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, project.term);
}

/// The two-module fixture `selka context` answers about: the entry imports
/// `model`, `model::validate` calls the private `check`, and the separate
/// `entry_value` export keeps `main` independent of `validate`'s signature so
/// the baseline fixture can change it without breaking the project.
const context_entry =
    \\import model
    \\
    \\
    \\func main() -> int:
    \\    return model.entry_value()
;

const context_model =
    \\
    \\
    \\public func validate(value: int) -> int:
    \\    mut total = value
    \\    return check(total)
    \\
    \\
    \\public func entry_value() -> int:
    \\    return 1
    \\
    \\
    \\func check(value: int) -> int:
    \\    return value + 1
;

/// `context_model` with a body-only edit: the same signature computes a
/// different result, which an interface baseline classifies as compatible.
const context_model_body_edit =
    \\
    \\
    \\public func validate(value: int) -> int:
    \\    mut total = value + 1
    \\    return check(total)
    \\
    \\
    \\public func entry_value() -> int:
    \\    return 1
    \\
    \\
    \\func check(value: int) -> int:
    \\    return value + 1
;

/// `context_model` with a breaking interface edit: `validate` gains a parameter
/// every caller would have to supply.
const context_model_signature_edit =
    \\
    \\
    \\public func validate(value: int, extra: int) -> int:
    \\    mut total = value + extra
    \\    return check(total)
    \\
    \\
    \\public func entry_value() -> int:
    \\    return 1
    \\
    \\
    \\func check(value: int) -> int:
    \\    return value + 1
;

/// The `model` module whose `validate` body carries `extra` straight-line
/// updates, so the complete answer about it is far wider than a small
/// `--context-bytes` budget and the envelope has to drop records.
fn wideContextModel(allocator: std.mem.Allocator, extra: usize) ![]u8 {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(allocator);
    try source.appendSlice(allocator, "\n\npublic func validate(value: int) -> int:\n    mut total = value\n");
    var line: usize = 0;
    while (line < extra) : (line += 1) {
        try source.appendSlice(allocator, "    total = total + 1\n");
    }
    try source.appendSlice(allocator, "    return check(total)\n\n\npublic func entry_value() -> int:\n    return 1\n\n\nfunc check(value: int) -> int:\n    return value + 1\n");
    return source.toOwnedSlice(allocator);
}

/// Write `main.selka` and `model.selka` into `temporary` and return the allocated
/// entry path every `context` invocation names. The path keeps its sentinel, so
/// the caller frees exactly the allocation `realPathFileAlloc` made.
fn writeContextProject(temporary: *testing.TmpDir, model: []const u8) ![:0]u8 {
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = context_entry });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "model.selka", .data = model });
    return temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
}

/// Parse the one JSON object a successful `selka context` prints, asserting
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

/// Run `selka context` with `options` and require `expected_status`, with no
/// successful envelope printed.
fn expectContextRejected(entry: []const u8, options: []const []const u8, expected_status: u8) !void {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "context", entry });
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
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "context", entry });
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
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "context", path, "--symbol", "model::validate", "--format=json" } });
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
    // The response repeats the entry as given (`entry` and the continuation), so
    // name it relative to the project: an absolute temporary path would make the
    // budget's headroom depend on where the checkout sits.
    const root = std.fs.path.dirname(path).?;
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
    defer testing.allocator.free(compiler);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler, "context", "main.selka", "--symbol", "model::validate", "--context-bytes=1200" }, .cwd = .{ .path = root } });
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
    try testing.expectEqualStrings("main.selka", try contextString(answer.value, "entry"));
    try testing.expect((try contextString(answer.value, "continuation")).len > 0);
}

// spec-case: CONTEXT-SELECT-1
test "CLI context rejects a symbol no declaration carries" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const path = try writeContextProject(&temp, context_model);
    defer testing.allocator.free(path);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "context", path, "--symbol", "model::no_such_function" } });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, outcome.term);
    try expectNoContextOk(outcome.stdout);
}

// spec-case: CONTEXT-SELECT-1
test "CLI context refuses an unqualified name that two modules both declare" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\import alpha
        \\import beta
        \\
        \\
        \\func main() -> int:
        \\    return alpha.first() + beta.second()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "alpha.selka", .data =
        \\
        \\
        \\public func validate(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\public func first() -> int:
        \\    return 1
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "beta.selka", .data =
        \\
        \\
        \\public func validate(value: int) -> int:
        \\    return value + 2
        \\
        \\
        \\public func second() -> int:
        \\    return 2
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(path);
    // Both `alpha::validate` and `beta::validate` exist, so the bare name is
    // genuinely ambiguous rather than unknown...
    const qualified = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "context", path, "--symbol", "alpha::validate" } });
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
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "context", path, "--at", "model.selka:5:5" } });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    const answer = try parseContextAnswer(outcome.stdout);
    defer answer.deinit();
    try testing.expectEqualStrings("agent-context-v1", try contextString(answer.value, "version"));
    try expectDeclarationNames(answer.value, "validate");
    // A file that is not in the project, and two malformed coordinate strings.
    try expectContextRejected(path, &.{ "--at", "ghost.selka:1:1" }, 2);
    try expectContextRejected(path, &.{ "--at", "model.selka:not-a-coordinate" }, 2);
    try expectContextRejected(path, &.{ "--at", "model.selka" }, 2);
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
    try expectContextUsage(path, &.{ "--symbol", "model::validate", "--at", "model.selka:5:5" });
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

/// Run `selka context` with one unreadable baseline spelling and require the
/// usage-level failure with its message, printing no envelope at all.
fn expectUnreadableBaseline(entry: []const u8, options: []const []const u8) !void {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "context", entry });
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
        \\
        \\
        \\public func validate(value: int) -> int:
        \\    return True
        \\
        \\
        \\public func entry_value() -> int:
        \\    return 1
    ;
    const path = try writeContextProject(&temp, broken_model);
    defer testing.allocator.free(path);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "context", path, "--symbol", "model::validate" } });
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
    const write = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "api-diff", path, write_option } });
    defer testing.allocator.free(write.stdout);
    defer testing.allocator.free(write.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, write.term);
    // A body-only edit stays compatible; `main` calls the untouched
    // `entry_value`, so the project still checks.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "model.selka", .data = context_model_body_edit });
    const body = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "context", path, "--symbol", "model::validate", against_option } });
    defer testing.allocator.free(body.stdout);
    defer testing.allocator.free(body.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, body.term);
    const body_answer = try parseContextAnswer(body.stdout);
    defer body_answer.deinit();
    const body_changes = try contextSectionRendering(body_answer.value, "changes");
    defer testing.allocator.free(body_changes);
    try testing.expect(std.mem.indexOf(u8, body_changes, "compatible") != null);
    // A signature change is breaking.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "model.selka", .data = context_model_signature_edit });
    const signature = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "context", path, "--symbol", "model::validate", against_option } });
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\
        \\
        \\func helper(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\func test_helper() -> bool:
        \\    return helper(1) == 2
        \\
        \\
        \\func main() -> int:
        \\    return 0
    });
    try gitIn(testing.allocator, root, &.{ "init", "-q" });
    try gitIn(testing.allocator, root, &.{ "add", "main.selka" });
    try gitIn(testing.allocator, root, &.{ "-c", "user.email=test@example.com", "-c", "user.name=test", "commit", "-q", "-m", "init" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\
        \\
        \\func helper(value: int) -> int:
        \\    return value + 2
        \\
        \\
        \\func test_helper() -> bool:
        \\    return helper(1) == 2
        \\
        \\
        \\func main() -> int:
        \\    return 0
    });
    const path = try std.fs.path.join(testing.allocator, &.{ root, "main.selka" });
    defer testing.allocator.free(path);
    const flagged = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "lint", path, "--gate", "--against=HEAD" } });
    defer testing.allocator.free(flagged.stdout);
    defer testing.allocator.free(flagged.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, flagged.term);
    try testing.expect(std.mem.indexOf(u8, flagged.stderr, "L_CHANGE_WITHOUT_TEST") != null);
    const silent = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "lint", path, "--gate" } });
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
        \\
        \\
        \\func helper(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\func test_helper() -> bool:
        \\    return helper(1) == 2
        \\
        \\
        \\func test_unrelated() -> bool:
        \\    return 3 == 3
        \\
        \\
        \\func main() -> int:
        \\    return 0
    ;
    const after =
        \\
        \\
        \\func helper(value: int) -> int:
        \\    return value + 2
        \\
        \\
        \\func test_helper() -> bool:
        \\    return helper(1) == 3
        \\
        \\
        \\func test_unrelated() -> bool:
        \\    return 3 == 3
        \\
        \\
        \\func main() -> int:
        \\    return 0
    ;
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data = before });
    try gitIn(testing.allocator, root, &.{ "init", "-q" });
    try gitIn(testing.allocator, root, &.{ "add", "app.selka" });
    try gitIn(testing.allocator, root, &.{ "-c", "user.email=test@example.com", "-c", "user.name=test", "commit", "-q", "-m", "init" });
    const path = try std.fs.path.join(testing.allocator, &.{ root, "app.selka" });
    defer testing.allocator.free(path);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    // An unchanged tree derives nothing: the selection is empty and exits 3,
    // exactly as a filter that matches nothing does.
    const empty = try privateRun(testing.allocator, &.{ compilerPath(), "test", path, "--affected", "--against=HEAD", "--cache-dir", cache });
    defer testing.allocator.free(empty.stdout);
    defer testing.allocator.free(empty.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, empty.term);
    try testing.expect(std.mem.indexOf(u8, empty.stderr, "affected: 0 selected, 2 skipped against HEAD") != null);
    // Editing the helper selects only the test that reaches it.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data = after });
    const selected = try privateRun(testing.allocator, &.{ compilerPath(), "test", path, "--affected", "--against=HEAD", "--cache-dir", cache });
    defer testing.allocator.free(selected.stdout);
    defer testing.allocator.free(selected.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, selected.term);
    try testing.expect(std.mem.indexOf(u8, selected.stderr, "affected: 1 selected, 1 skipped against HEAD") != null);
    try testing.expect(std.mem.indexOf(u8, selected.stderr, "skipped app::test_unrelated") != null);
    // The two switches are only meaningful together, and a bad reference is a
    // host failure rather than an empty selection.
    const without = try privateRun(testing.allocator, &.{ compilerPath(), "test", path, "--against=HEAD", "--cache-dir", cache });
    defer testing.allocator.free(without.stdout);
    defer testing.allocator.free(without.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, without.term);
    const alone = try privateRun(testing.allocator, &.{ compilerPath(), "test", path, "--affected", "--cache-dir", cache });
    defer testing.allocator.free(alone.stdout);
    defer testing.allocator.free(alone.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, alone.term);
    const unresolvable = try privateRun(testing.allocator, &.{ compilerPath(), "test", path, "--affected", "--against=no-such-revision", "--cache-dir", cache });
    defer testing.allocator.free(unresolvable.stdout);
    defer testing.allocator.free(unresolvable.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, unresolvable.term);
    try testing.expect(std.mem.indexOf(u8, unresolvable.stderr, "git cannot resolve") != null);
}
// spec-case: LINT-3
test "CLI lint accept records a baseline that gate then accepts" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.selka", .data =
        \\
        \\
        \\func helper() -> int:
        \\    return 1
        \\
        \\
        \\func main() -> int:
        \\    return 0
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "app.selka", testing.allocator);
    defer testing.allocator.free(path);
    const before = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "lint", path, "--gate" } });
    defer testing.allocator.free(before.stdout);
    defer testing.allocator.free(before.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, before.term);
    const accept = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "lint", path, "--accept" } });
    defer testing.allocator.free(accept.stdout);
    defer testing.allocator.free(accept.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, accept.term);
    const after = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "lint", path, "--gate" } });
    defer testing.allocator.free(after.stdout);
    defer testing.allocator.free(after.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, after.term);
    try testing.expect(std.mem.indexOf(u8, after.stdout, "1 accepted") != null);
}
test "CLI discovers cross module duplicates with options and rejects invalid dependencies" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data =
        \\import helper
        \\
        \\
        \\func twice(value: i64) -> i64:
        \\    return value * 2 + 3
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data =
        \\
        \\
        \\func copy(x: i64) -> i64:
        \\    return x * 2 + 3
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.selka", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "discover-project-duplicates", path, "--min-nodes=1", "--approximate", "--max-work=1", "--population=reference", "--timings" } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    for ([_][]const u8{ "scope: reachable module graph", "population=reference", "input::twice", "helper::copy", "input.selka:4:", "helper.selka:3:", "approximate near-v3", "truncated=true" }) |part| try testing.expect(std.mem.indexOf(u8, result.stdout, part) != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "project_frontend_ns=") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "modules=2") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data =
        \\
        \\
        \\func copy(x: i64) -> i64:
        \\    return True
    });
    const invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "discover-project-duplicates", path } });
    defer testing.allocator.free(invalid.stdout);
    defer testing.allocator.free(invalid.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, invalid.term);
    try testing.expectEqualStrings("", invalid.stdout);
    try testing.expect(std.mem.indexOf(u8, invalid.stderr, "E_TYPE") != null);
    try invokeOptions("discover-project-duplicates",
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , &.{"--max-work=1"}, 2, "", "usage:");
    try invokeOptions("discover-project-duplicates",
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , &.{"--max-steps=1"}, 2, "", "usage:");
}
test "CLI module quality reports preserve export roots and advisory thresholds" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data =
        \\import api
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "api.selka", .data =
        \\
        \\
        \\public func entry() -> i64:
        \\    return hidden()
        \\
        \\
        \\func hidden() -> i64:
        \\    return 1
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.selka", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "report-project-quality", path, "--max-function-lines=1" } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    // `import api` exists only to pull `api.selka` into the reachable graph, so the
    // unused-import warning names it and nothing else is written to stderr.
    try testing.expectEqualStrings("input.selka:1:8: warning[W_UNUSED_IMPORT]: import `api` is never referenced in this module; remove it or use it\n  import api\n         ^\n", result.stderr);
    for ([_][]const u8{ "quality-modules-v1", "api.selka:3:", "api::entry; private=false; reachable-from-main=false", "module-exported=true reachable-from-exports=true", "module-exported=false reachable-from-exports=true", "function-lines 2 exceeds configured 1", "calls api::hidden at api.selka:4:", "Runtime coverage and assertions: not measured" }) |part| try testing.expect(std.mem.indexOf(u8, result.stdout, part) != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "no call path from main or exported interfaces") == null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "api.selka", .data =
        \\
        \\
        \\func invalid() -> i64:
        \\    return True
    });
    const invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "report-project-quality", path } });
    defer testing.allocator.free(invalid.stdout);
    defer testing.allocator.free(invalid.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, invalid.term);
    try testing.expectEqualStrings("", invalid.stdout);
    try testing.expect(std.mem.indexOf(u8, invalid.stderr, "E_TYPE") != null);
    try invokeOptions("report-project-quality",
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , &.{"--approximate"}, 2, "", "usage:");
}
// spec-case: FMT-CHECK-LOCATION-1
test "CLI module formatting is syntax only and canonical for every reachable module" {
    // The header directive group is followed by one blank line and top-level
    // declarations by two, so the fixtures below are already canonical.
    const draft =
        \\import absent as a
        \\
        \\func f(x: a.T) -> a.T:
        \\    return x
        \\
    ;
    try invoke("fmt-module", draft, 0, draft, "");
    try invokeOptions("fmt-module", draft, &.{"--check"}, 0, "", "");
    try invoke("fmt-module",
        \\func broken(
    , 1, "", "E_SYNTAX");
    const root_module =
        \\import child
        \\
        \\func main() -> i64:
        \\    return unknown()
        \\
    ;
    const child_module =
        \\func f() -> Missing:
        \\    return unknown()
        \\
    ;
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data = root_module });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "child.selka", .data = child_module });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.selka", testing.allocator);
    defer testing.allocator.free(path);
    // Neither module type checks; the formatter still reaches and accepts both.
    const clean = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "fmt-project", path, "--check" } });
    defer testing.allocator.free(clean.stdout);
    defer testing.allocator.free(clean.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, clean.term);
    try testing.expectEqualStrings("", clean.stdout);
    try testing.expectEqualStrings("", clean.stderr);
    for ([_][]const u8{ "input.selka", "child.selka" }) |name| {
        const absolute = try temp.dir.realPathFileAlloc(testing.io, name, testing.allocator);
        defer testing.allocator.free(absolute);
        const output = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "fmt-module", absolute } });
        defer testing.allocator.free(output.stdout);
        defer testing.allocator.free(output.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, output.term);
        try testing.expectEqualStrings(if (std.mem.eql(u8, name, "input.selka")) root_module else child_module, output.stdout);
    }
    try temp.dir.writeFile(testing.io, .{ .sub_path = "child.selka", .data = "\nfunc  f() -> Missing:\n    return unknown()\n" });
    const differing = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "fmt-project", path, "--check" } });
    defer testing.allocator.free(differing.stdout);
    defer testing.allocator.free(differing.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, differing.term);
    try testing.expect(std.mem.indexOf(u8, differing.stderr, "child.selka:1:1: formatting differs") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "child.selka", .data =
        \\func broken(
    });
    const invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "fmt-project", path, "--check" } });
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
        \\import config
        \\
        \\
        \\public func read() -> i64:
        \\    return config.value()
        \\
        \\
        \\func main() -> i64:
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data =
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "commands", .data = script });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.selka", testing.allocator);
    defer testing.allocator.free(path);
    const input = try temp.dir.openFile(testing.io, "commands", .{});
    defer input.close(testing.io);
    const output = try temp.dir.createFile(testing.io, "replies", .{});
    defer output.close(testing.io);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "check-session", path });
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
    const replies = try sessionScript("check\nclear\nquit\n", &.{"--inputs=/nonexistent-selka-manifest/inputs.json"}, 0);
    defer testing.allocator.free(replies);
    try testing.expect(std.mem.indexOf(u8, replies, "\"failure\":\"FileNotFound\"") != null);
    try testing.expect(std.mem.indexOf(u8, replies, "\"action\":\"quit\",\"status\":0") != null);
}
test "CLI executes generic fixed arrays and reports uncalled template shape errors" {
    try invoke("run",
        \\func twice[T: integer](x: T) -> FixedArray[T, 2]:
        \\    return FixedArray[T, 2]([x, x + x])
        \\
        \\
        \\func main() -> i64:
        \\    return twice[i64](6)[1]
    , 0, "12\n", "");
    try invokeOptions("check",
        \\func bad[T](a: FixedArray[T, 2]) -> FixedArray[T, 3]:
        \\    return a
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_GENERIC_TYPE\"");
}
test "CLI formats nominal templates and runs programs with unused declarations" {
    const source =
        \\record Box[T]:
        \\    value: T
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    try invoke("fmt", source, 0,
        \\record Box[T]:
        \\    value: T
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        \\
    , "");
    try invokeOptions("run", source, &.{"--diagnostics=json"}, 0, "0\n", "");
}
test "CLI reports unused nominal template requirement errors" {
    try invokeOptions("check",
        \\record Key[T: equality]:
        \\    value: T
        \\
        \\
        \\record Bad[U]:
        \\    key: Key[U]
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_GENERIC_REQUIREMENT\"");
    try invokeOptions("check",
        \\record Bad[T]:
        \\    value: Missing
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_UNKNOWN_TYPE\"");
}
test "CLI rejects recursive nominal layouts but preserves finite nested and phantom forms" {
    try invokeOptions("check",
        \\record Node[T]:
        \\    next: Node[T]
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_RECURSIVE_RECORD\"");
    try invokeOptions("check",
        \\record Box[T]:
        \\    value: T
        \\
        \\
        \\record Empty[T]:
        \\    pass
        \\
        \\
        \\record Finite[U]:
        \\    nested: Box[Box[U]]
        \\    phantom: Empty[Finite[FixedArray[U, 1]]]
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , &.{"--diagnostics=json"}, 0, "", "");
}
test "CLI executes concrete nominal instances and reports argument identity errors" {
    const definitions =
        \\record Box[T]:
        \\    value: T
        \\
        \\
        \\enum Slot[T]:
        \\    none
        \\    some(value: T)
    ;
    const program = definitions ++ "\n\n\n" ++
        \\func main() -> i64:
        \\    mut slot: Slot[Box[i64]] = Slot.some(value=Box[i64](value=12))
        \\    match slot:
        \\        case none:
        \\            return 0
        \\        case some(value=box):
        \\            return box.value
    ;
    try invoke("run", program, 0, "12\n", "");
    try invokeOptions("check", definitions ++ "\n\n\n" ++
        \\func takes(box: Box[i64]) -> i64:
        \\    return box.value
        \\
        \\
        \\func main() -> i64:
        \\    return takes(Box[bool](value=True))
    , &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_TYPE\"");
}
test "CLI specializes nominal generic bodies and reports uncalled shape errors" {
    const definitions =
        \\record Box[T]:
        \\    value: T
    ;
    try invoke("run", definitions ++ "\n\n\n" ++
        \\func pack[T](x: T) -> Box[T]:
        \\    return Box[T](value=x)
        \\
        \\
        \\func main() -> i64:
        \\    return pack[i64](31).value
    , 0, "31\n", "");
    try invokeOptions("check", definitions ++ "\n\n\n" ++
        \\func bad[T](x: T) -> Box[T]:
        \\    return Box[T](value=1)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_GENERIC_TYPE\"");
}
// spec: DEPENDENCIES-1
test "CLI project-dependencies buildIndex emits checked graph identity and rejects invalid bodies" {
    const outcome = try runFixture("project-dependencies",
        \\
        \\
        \\func main() -> i64:
        \\    return 7
    , &.{});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, outcome.stdout, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("project-dependencies-v1", parsed.value.object.get("version").?.string);
    try testing.expect(parsed.value.object.get("complete").?.bool);
    try testing.expectEqualStrings("input.selka", parsed.value.object.get("inputs").?.array.items[0].object.get("path").?.string);
    try testing.expectEqual(@as(usize, 64), parsed.value.object.get("implementation").?.object.get("compiler_sha256").?.string.len);
    try invoke("project-dependencies",
        \\
        \\
        \\func main() -> i64:
        \\    return True
    , 1, "", "E_TYPE");
    try invoke("project-dependencies",
        \\export absent
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , 1, "", "error[E_EXPORT_REMOVED]");
}
// spec: CLI-HELP-1
test "CLI help answers on stdout with the everyday commands first and exits 0" {
    for ([_][]const u8{ "--help", "-h", "help" }) |flag| {
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), flag } });
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
        try testing.expectEqualStrings("", result.stderr);
        try testing.expect(std.mem.startsWith(u8, result.stdout, "selka: a Python-shaped"));
        const everyday = std.mem.indexOf(u8, result.stdout, "selka check FILE.selka").?;
        const reference = std.mem.indexOf(u8, result.stdout, "usage: selka build").?;
        try testing.expect(everyday < reference);
        // The guides and the large-project commands are on the first screen too.
        try testing.expect(std.mem.indexOf(u8, result.stdout, "selka docs primer").? < everyday);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "selka docs [TOPIC]").? < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "--release").? < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "selka cost ENTRY.selka").? < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "[--cost]").? < reference);
        const large = std.mem.indexOf(u8, result.stdout, "Working in a large project:").?;
        try testing.expect(everyday < large and large < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "selka context ENTRY.selka --symbol=module::name").? < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "selka tests-for ENTRY.selka module::name").? < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "--affected --against REF").? < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "selka overview PROJECT --write|--check").? < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "selka release check PROJECT").? < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "release init PROJECT [--adopt-comments [--dry-run]]") != null);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "release draft PROJECT --name SLUG [--date YYYY-MM-DD]") != null);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "release cut PROJECT --name NAME") != null);
    }
}
// spec-case: CLI-DOCS-1
test "CLI docs lists the embedded guides and prints one from a directory with no docs" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
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
    try testing.expect(std.mem.startsWith(u8, primer.stdout, "# selka in one page"));
    try testing.expect(std.mem.indexOf(u8, primer.stdout, "--release") != null);
    const unknown = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "docs", "nonsense" } });
    defer testing.allocator.free(unknown.stdout);
    defer testing.allocator.free(unknown.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, unknown.term);
    try testing.expect(std.mem.indexOf(u8, unknown.stderr, "no topic `nonsense`") != null);
    // The operations table is generated rather than embedded, and still travels
    // inside the executable (STDLIB-OPERATIONS-TABLE-1).
    const operations = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler, "docs", "operations" }, .cwd = .{ .dir = temporary.dir } });
    defer testing.allocator.free(operations.stdout);
    defer testing.allocator.free(operations.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, operations.term);
    try testing.expect(std.mem.startsWith(u8, operations.stdout, "# Operation homes"));
    try testing.expect(std.mem.indexOf(u8, operations.stdout, "## prelude (no import)") != null);
    try testing.expect(std.mem.indexOf(u8, operations.stdout, "## strings") != null);
}
// spec: FEATURE-REPORT-1
test "CLI features identify installed compiler without source input" {
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "--features" } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqualStrings("", result.stderr);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, result.stdout, .{});
    defer parsed.deinit();
    const report = parsed.value.object;
    try testing.expectEqualStrings("language-features-v1", report.get("version").?.string);
    try testing.expectEqual(@as(usize, 64), report.get("compiler_sha256").?.string.len);
    try testing.expectEqualStrings("llvm", report.get("features").?.object.get("primary_backend").?.string);
    // The identity is the compiler's embedded build-time digest, not a fresh hash of its
    // own executable, so a receipt from the same compiler reports exactly the same value.
    const receipt = try runFixture("project-dependencies",
        \\
        \\
        \\func main() -> i64:
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
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "--features" } });
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
    \\extern func measure(host: Host, x: i64) -> i64 effects(host)
    \\
    \\
    \\
    \\
    \\public func main() -> i64:
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
    // The unchanged shared fixture retains the exact retired clause witness.
    try invoke("list-declarations", listing_module, 1, "", "error[E_EFFECTS_REMOVED]");
    const modern_listing_module = try std.mem.replaceOwned(u8, testing.allocator, listing_module, " effects(host)", "");
    defer testing.allocator.free(modern_listing_module);
    const outcome = try runFixture("list-declarations", modern_listing_module, &.{});
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
    try testing.expect(listing.header == null);
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
        try expectTrivia(modern_listing_module[accounted..range.start]);
        accounted = range.end;
    }
    try expectTrivia(modern_listing_module[accounted..]);
    try testing.expect(listing.declarations[0].comment_start < listing.declarations[0].bytes.start);
    try testing.expect(listing.declarations[3].exported == false and listing.declarations[4].exported);
}
test "CLI declaration listing separates parse failures from checking and usage failures" {
    try invoke("list-declarations",
        \\func main() -> i64:
        \\    return 1 +
    , 1, "", "error[E_EXPRESSION]");
    try invokeOptions("list-declarations",
        \\export absent
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , &.{"--diagnostics=json"}, 1, "", "\"code\":\"E_EXPORT_REMOVED\"");
    try invokeOptions("list-declarations",
        \\func main() -> i64:
        \\    return 0
    , &.{"--check"}, 2, "", "usage:");
    const unchecked =
        \\
        \\
        \\func main() -> i64:
        \\    mut flag: bool = 1
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
        \\func main() -> i64:
        \\    mut sum = 0
        \\    mut i = 0
        \\    while i < 100:
        \\        sum += i
        \\        i += 1
        \\    return sum
    , 0, "4950\n", "");
    try invoke("run",
        \\func main() -> i64:
        \\    if False and divtrunc(1, 0) == 0:
        \\        return 1
        \\    else:
        \\        return 7
    , 0, "7\n", "");
    try invoke("run",
        \\func main() -> i64:
        \\    _ = divtrunc(1, 0)
        \\    return 7
    , 1, "", "error[R_DIVISION_BY_ZERO]");
    try invoke("run",
        \\func main() -> i64:
        \\    while True:
        \\        return 7
    , 0, "7\n", "");
    try invoke("check",
        \\func main() -> i64:
        \\    while True:
        \\        break
    , 1, "", "error[E_MISSING_RETURN]");
}
test "all commands preserve stdout and deterministic advisory stderr" {
    const source = @embedFile("fixtures/warnings.selka");
    const commands = [_][]const u8{ "check", "run" };
    const outputs = [_][]const u8{ "", "7\n" };
    for (commands, outputs) |command, expected| {
        const outcome = try runFixture(command, source, &.{});
        defer testing.allocator.free(outcome.stdout);
        defer testing.allocator.free(outcome.stderr);
        // Only `run` executes the guest; its entry returns 7, now the exit status.
        const wanted: u8 = if (std.mem.eql(u8, command, "run")) 7 else 0;
        try testing.expectEqual(std.process.Child.Term{ .exited = wanted }, outcome.term);
        try testing.expectEqualStrings(expected, outcome.stdout);
        try testing.expect(std.mem.indexOf(u8, outcome.stderr, ":2:9: warning[W_UNUSED_BINDING]") != null);
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, outcome.stderr, "warning["));
        try testing.expect(std.mem.indexOf(u8, outcome.stderr, "`_ =`") != null);
    }
}
/// A program whose loop copies each element of a plain parameter that nothing reads after it: one `W_COPY_MOVE` hint.
const copy_move_hint =
    \\func names(rows: str[]) -> str[]:
    \\    mut out: str[] = []
    \\    for row in rows:
    \\        append(mut out, copy(row))
    \\    return out
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, len(names(["a"])))
    \\    return 0
    \\
    \\
    \\public func test_names() -> bool:
    \\    return len(names(["a"])) == 1
;

test "build, run and test leave out the W_COPY_MOVE hints that check, a flag and json show" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = copy_move_hint });
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.selka" });
    defer testing.allocator.free(entry);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "program" });
    defer testing.allocator.free(output);

    // `check` is where the advice is read.
    const checked = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry, "--cache-dir", cache });
    defer testing.allocator.free(checked.stdout);
    defer testing.allocator.free(checked.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, checked.stderr, "warning[W_COPY_MOVE]"));

    // The commands that build the program print nothing for it: no hint and no count line, replays included.
    for (0..2) |_| {
        const built = try privateRun(testing.allocator, &.{ compilerPath(), "build", entry, "-o", output, "--cache-dir", cache });
        defer testing.allocator.free(built.stdout);
        defer testing.allocator.free(built.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
        try testing.expectEqualStrings("", built.stderr);
        const ran = try privateRun(testing.allocator, &.{ compilerPath(), "run", entry, "--cache-dir", cache });
        defer testing.allocator.free(ran.stdout);
        defer testing.allocator.free(ran.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, ran.term);
        try testing.expectEqualStrings("1\n", ran.stdout);
        try testing.expectEqualStrings("", ran.stderr);
    }
    const tested = try privateRun(testing.allocator, &.{ compilerPath(), "test", entry, "--cache-dir", cache, "--force" });
    defer testing.allocator.free(tested.stdout);
    defer testing.allocator.free(tested.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, tested.term);
    try testing.expect(std.mem.indexOf(u8, tested.stderr, "W_COPY_MOVE") == null);

    // Every warning: the flag and JSON bring the hint back to a build.
    const flagged = try privateRun(testing.allocator, &.{ compilerPath(), "build", entry, "-o", output, "--cache-dir", cache, "--warnings" });
    defer testing.allocator.free(flagged.stdout);
    defer testing.allocator.free(flagged.stderr);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, flagged.stderr, "warning[W_COPY_MOVE]"));
    const structured = try privateRun(testing.allocator, &.{ compilerPath(), "run", entry, "--cache-dir", cache, "--diagnostics=json" });
    defer testing.allocator.free(structured.stdout);
    defer testing.allocator.free(structured.stderr);
    try testing.expect(std.mem.indexOf(u8, structured.stderr, "W_COPY_MOVE") != null);
}
test "warnings of modules git tracks unmodified are counted, and every one is a flag, an edit or json away" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const source = @embedFile("fixtures/warnings.selka");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.selka" });
    defer testing.allocator.free(entry);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);

    // Not in a repository, or not committed: the warning prints, as it always did.
    const untracked = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry, "--cache-dir", cache });
    defer testing.allocator.free(untracked.stdout);
    defer testing.allocator.free(untracked.stderr);
    try testing.expect(std.mem.indexOf(u8, untracked.stderr, ":2:9: warning[W_UNUSED_BINDING]") != null);
    try testing.expect(std.mem.indexOf(u8, untracked.stderr, "unmodified module") == null);

    try gitIn(testing.allocator, root, &.{"init"});
    try gitIn(testing.allocator, root, &.{ "add", "main.selka" });
    try gitIn(testing.allocator, root, &.{ "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false", "commit", "-m", "base" });

    // Committed and unchanged: one line stands for it, replay or not, and the status is the same.
    for (0..2) |_| {
        const counted = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry, "--cache-dir", cache });
        defer testing.allocator.free(counted.stdout);
        defer testing.allocator.free(counted.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, counted.term);
        try testing.expect(std.mem.indexOf(u8, counted.stderr, "warning[") == null);
        try testing.expect(std.mem.indexOf(u8, counted.stderr, "warnings: 1 in 1 unmodified module (W_UNUSED_BINDING 1); `selka check --warnings` lists them\n") != null);
    }

    // The same program built and run says the same, and still runs.
    const output = try std.fs.path.join(testing.allocator, &.{ root, "program" });
    defer testing.allocator.free(output);
    const built = try privateRun(testing.allocator, &.{ compilerPath(), "build", entry, "-o", output, "--cache-dir", cache });
    defer testing.allocator.free(built.stdout);
    defer testing.allocator.free(built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    try testing.expect(std.mem.indexOf(u8, built.stderr, "warning[") == null);
    try testing.expect(std.mem.indexOf(u8, built.stderr, "warnings: 1 in 1 unmodified module") != null);

    // The whole list: the flag, the environment, and JSON (which always carries every warning).
    const flagged = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry, "--cache-dir", cache, "--warnings" });
    defer testing.allocator.free(flagged.stdout);
    defer testing.allocator.free(flagged.stderr);
    try testing.expect(std.mem.indexOf(u8, flagged.stderr, ":2:9: warning[W_UNUSED_BINDING]") != null);
    try testing.expect(std.mem.indexOf(u8, flagged.stderr, "unmodified module") == null);
    const structured = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry, "--cache-dir", cache, "--diagnostics=json" });
    defer testing.allocator.free(structured.stdout);
    defer testing.allocator.free(structured.stderr);
    try testing.expect(std.mem.indexOf(u8, structured.stderr, "W_UNUSED_BINDING") != null);
    try testing.expect(std.mem.indexOf(u8, structured.stderr, "unmodified module") == null);

    // A project that denies warnings fails on them, and a command that fails on a warning shows it.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = "{\"version\":2,\"lint\":{\"warnings\":\"deny\"}}" });
    const denied = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry, "--cache-dir", cache });
    defer testing.allocator.free(denied.stdout);
    defer testing.allocator.free(denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, denied.term);
    try testing.expect(std.mem.indexOf(u8, denied.stderr, ":2:9: warning[W_UNUSED_BINDING]") != null);
    try temp.dir.deleteFile(testing.io, "selka.json");

    // An edit makes the module the author's again: its warning prints in full.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source ++ "\n# edited\n" });
    const edited = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry, "--cache-dir", cache });
    defer testing.allocator.free(edited.stdout);
    defer testing.allocator.free(edited.stderr);
    try testing.expect(std.mem.indexOf(u8, edited.stderr, ":2:9: warning[W_UNUSED_BINDING]") != null);
    try testing.expect(std.mem.indexOf(u8, edited.stderr, "unmodified module") == null);
}
/// Run this compiler with `arguments` in `directory`, in the private environment of `privateRun`.
fn compilerIn(allocator: std.mem.Allocator, directory: std.Io.Dir, arguments: []const []const u8) !std.process.RunResult {
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), allocator);
    defer allocator.free(compiler);
    const argv = try std.mem.concat(allocator, []const u8, &.{ &.{compiler}, arguments });
    defer allocator.free(argv);
    var environment = try @import("test_paths").privateEnvironment(allocator);
    defer environment.deinit();
    return std.process.run(allocator, testing.io, .{ .argv = argv, .cwd = .{ .dir = directory }, .environ_map = &environment });
}
test "check FILE prints its own warnings and one line per other module, and --warnings, json, a directory and fix see every one" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDirPath(testing.io, "app");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.selka", .data = "public func twice(n: int) -> int:\n    mut unused = 3\n    mut other = 4\n    return n * 2\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/more.selka", .data = "public func three(n: int) -> int:\n    mut spare = 1\n    return n * 3\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/main.selka", .data = "import helper\nimport more\n\nfunc main(out: Stream) -> int:\n    mut left = 5\n    print(out, \"x\")\n    return helper.twice(1) + more.three(1) - 5\n" });
    const own = "main.selka:5:9: warning[W_UNUSED_BINDING]";
    const theirs = [_][]const u8{ "helper.selka:2:9: warning[W_UNUSED_BINDING]", "helper.selka:3:9: warning[W_UNUSED_BINDING]", "more.selka:2:9: warning[W_UNUSED_BINDING]" };

    // The file's own warning in full, then one line per other module, sorted, naming the check from the working directory;
    // the same on a replay.
    for (0..2) |_| {
        const checked = try compilerIn(a, temp.dir, &.{ "check", "app/main.selka", "--cache-dir", "cache" });
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
        try testing.expect(std.mem.indexOf(u8, checked.stderr, own) != null);
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, checked.stderr, "warning["));
        try testing.expect(std.mem.endsWith(u8, checked.stderr, "helper.selka: 2 warnings; `selka check app/helper.selka`\nmore.selka: 1 warning; `selka check app/more.selka`\n"));
    }
    // From the file's own directory the command is the module's name.
    var app = try temp.dir.openDir(testing.io, "app", .{});
    defer app.close(testing.io);
    const inside = try compilerIn(a, app, &.{ "check", "main.selka", "--cache-dir", "../cache" });
    try testing.expect(std.mem.indexOf(u8, inside.stderr, "helper.selka: 2 warnings; `selka check helper.selka`\n") != null);
    // The named module's own warnings print when it is checked.
    const helper = try compilerIn(a, temp.dir, &.{ "check", "app/helper.selka", "--cache-dir", "cache" });
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, helper.stderr, "helper.selka:"));

    // `--warnings`, JSON, a named format (how `selka fix` checks), a directory and `selka fix` itself see every warning.
    const listed = try compilerIn(a, temp.dir, &.{ "check", "app/main.selka", "--cache-dir", "cache", "--warnings" });
    const structured = try compilerIn(a, temp.dir, &.{ "check", "app/main.selka", "--cache-dir", "cache", "--diagnostics=json" });
    const named = try compilerIn(a, temp.dir, &.{ "check", "app/main.selka", "--cache-dir", "cache", "--diagnostics=text" });
    const directory = try compilerIn(a, temp.dir, &.{ "check", "app", "--cache-dir", "cache" });
    const fixed = try compilerIn(a, temp.dir, &.{ "fix", "app/main.selka" });
    for ([_][]const u8{ listed.stderr, named.stderr, directory.stderr, fixed.stderr }) |printed| {
        try testing.expectEqual(@as(usize, 4), std.mem.count(u8, printed, "warning[W_UNUSED_BINDING]"));
        for (theirs) |warning| try testing.expect(std.mem.indexOf(u8, printed, warning) != null);
        try testing.expect(std.mem.indexOf(u8, printed, " warnings; `selka check") == null);
    }
    try testing.expectEqual(@as(usize, 4), std.mem.count(u8, structured.stderr, "\"W_UNUSED_BINDING\""));
    try testing.expect(std.mem.indexOf(u8, structured.stderr, " warnings; `selka check") == null);
}
test "a command that printed diagnostics with a fix ends with how many of them `selka fix` repairs, a replay as the first run did" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "warned.selka", .data =
        \\func show(fs: Filesystem, out: Stream) -> int:
        \\    if fs.exists("x"):
        \\        print(out, "y")
        \\    return 0
        \\
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    return show(own fs, out)
        \\
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "refused.selka", .data =
        \\func main(out: Stream) -> int:
        \\    const xs = [1, 2, 3]
        \\    const ys = xs.append(4)
        \\    const n: int = "x"
        \\    print(out, str(len(xs)))
        \\    return 0
        \\
    });
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const warned = try std.fs.path.join(testing.allocator, &.{ root, "warned.selka" });
    defer testing.allocator.free(warned);
    const refused = try std.fs.path.join(testing.allocator, &.{ root, "refused.selka" });
    defer testing.allocator.free(refused);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "warned" });
    defer testing.allocator.free(output);
    const warned_line = try std.fmt.allocPrint(testing.allocator, "`selka fix {s} --warnings` repairs 1 of these 1\n", .{warned});
    defer testing.allocator.free(warned_line);

    // The line closes the report: one of the two errors has a repair, and a plain `selka fix` on a file applies an error's.
    const checked = try privateRun(testing.allocator, &.{ compilerPath(), "check", refused, "--cache-dir", cache });
    defer testing.allocator.free(checked.stdout);
    defer testing.allocator.free(checked.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, checked.term);
    const refused_line = try std.fmt.allocPrint(testing.allocator, "`selka fix {s}` repairs 1 of these 2\n", .{refused});
    defer testing.allocator.free(refused_line);
    try testing.expect(std.mem.endsWith(u8, checked.stderr, refused_line));

    // A warning counts, on a check and on a build, and the replay of that build says the same; its repair is the one that `--warnings` adds.
    const built = try privateRun(testing.allocator, &.{ compilerPath(), "build", warned, "-o", output, "--cache-dir", cache });
    defer testing.allocator.free(built.stdout);
    defer testing.allocator.free(built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    try testing.expect(std.mem.endsWith(u8, built.stderr, warned_line));
    const replayed = try privateRun(testing.allocator, &.{ compilerPath(), "build", warned, "-o", output, "--cache-dir", cache });
    defer testing.allocator.free(replayed.stdout);
    defer testing.allocator.free(replayed.stderr);
    try testing.expectEqualStrings(built.stderr, replayed.stderr);
    const warned_check = try privateRun(testing.allocator, &.{ compilerPath(), "check", warned, "--cache-dir", cache });
    defer testing.allocator.free(warned_check.stdout);
    defer testing.allocator.free(warned_check.stderr);
    try testing.expect(std.mem.endsWith(u8, warned_check.stderr, warned_line));

    // The JSON diagnostics are unchanged: no closing line.
    const structured = try privateRun(testing.allocator, &.{ compilerPath(), "check", refused, "--cache-dir", cache, "--diagnostics=json" });
    defer testing.allocator.free(structured.stdout);
    defer testing.allocator.free(structured.stderr);
    try testing.expect(std.mem.indexOf(u8, structured.stderr, "selka fix") == null);
}
test "a project check replayed from its stored verdict ends with the same `selka fix` line as the check that stored it" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data =
        \\public func first(found: int?) -> int:
        \\    match found:
        \\        case Some(value):
        \\            return value + 1
        \\        case None:
        \\            return 0
        \\
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\import helper
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, str(helper.first(Some(4))))
        \\    return 0
        \\
    });
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.selka" });
    defer testing.allocator.free(entry);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const line = try std.fmt.allocPrint(testing.allocator, "`selka fix {s} --warnings` repairs 1 of these 1\n", .{entry});
    defer testing.allocator.free(line);

    // The warning is in `helper`, not the entry, so the checks name `--warnings` to print it and the fix line.
    const stored = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry, "--cache-dir", cache, "--warnings" });
    defer testing.allocator.free(stored.stdout);
    defer testing.allocator.free(stored.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, stored.term);
    try testing.expect(std.mem.indexOf(u8, stored.stderr, "warning[W_MATCH_ELSE]") != null);
    try testing.expect(std.mem.endsWith(u8, stored.stderr, line));
    // The second check reads the stored verdict (every module counts as cached) and prints the warning and the line again.
    const replayed = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry, "--cache-dir", cache, "--warnings" });
    defer testing.allocator.free(replayed.stdout);
    defer testing.allocator.free(replayed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, replayed.term);
    try testing.expect(std.mem.indexOf(u8, replayed.stderr, "check: ok (2 modules, 2 cached)") != null);
    try testing.expect(std.mem.indexOf(u8, replayed.stderr, "warning[W_MATCH_ELSE]") != null);
    try testing.expect(std.mem.endsWith(u8, replayed.stderr, line));
    // The JSON diagnostics of a replay carry no closing line, and the stored text never shows its marker.
    const structured = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry, "--cache-dir", cache, "--diagnostics=json" });
    defer testing.allocator.free(structured.stdout);
    defer testing.allocator.free(structured.stderr);
    try testing.expect(std.mem.indexOf(u8, structured.stderr, "selka fix") == null);
    try testing.expect(std.mem.indexOfScalar(u8, replayed.stderr, 0) == null);
}
test "a directory test run ends with one `selka fix` line for all its entries, the same at every width of the run" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDirPath(testing.io, "suite");
    const body =
        \\func helper() -> int:
        \\    const xs = [1, 2, 3]
        \\    const ys = xs.append(4)
        \\    return len(ys)
        \\
        \\public func test_helper() -> bool:
        \\    return helper() == 4
        \\
    ;
    try temp.dir.writeFile(testing.io, .{ .sub_path = "suite/a.selka", .data = body });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "suite/b.selka", .data = body });
    // The third entry has two errors, one of which `selka fix` cannot repair.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "suite/c.selka", .data = body ++ "\nfunc refused() -> int:\n    const n: int = \"x\"\n    return n\n" });
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const suite = try std.fs.path.join(testing.allocator, &.{ root, "suite" });
    defer testing.allocator.free(suite);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const line = try std.fmt.allocPrint(testing.allocator, "`selka fix {s}` repairs 3 of these 4\n", .{suite});
    defer testing.allocator.free(line);
    // Each entry is a process of its own, and used to close its own report: one line for each, with its own file.
    for ([_][]const u8{ "1", "3" }) |width| {
        const ran = try privateRun(testing.allocator, &.{ compilerPath(), "test", suite, "--jobs", width, "--cache-dir", cache });
        defer testing.allocator.free(ran.stdout);
        defer testing.allocator.free(ran.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, ran.term);
        try testing.expectEqual(@as(usize, 4), std.mem.count(u8, ran.stderr, "error["));
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, ran.stderr, "`selka fix"));
        try testing.expect(std.mem.endsWith(u8, ran.stderr, line));
        try testing.expect(std.mem.indexOf(u8, ran.stdout, "0 passed, 0 cached, 3 failed, 0 skipped") != null);
    }
}
test "a directory test run ends with one line for the warnings it withheld, each counted once, the same at every width of the run" {
    // Three entries import one module that git tracks unmodified and that calls a deprecated function; each entry has an error, so its
    // check is refused and prints the diagnostics it has, which carry the module's warning. Each entry is a process of its own.
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "old.selka", .data = "\n\n@deprecated(\"use two\")\npublic func old() -> int:\n    return 1\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "shared.selka", .data = "import old\n\npublic func two() -> int:\n    return old.old() + 1\n" });
    for ([_][]const u8{ "t1", "t2", "t3" }) |name| {
        const entry = try std.fmt.allocPrint(testing.allocator, "import shared\n\npublic func test_{s}() -> bool:\n    const n: int = \"x\"\n    return shared.two() == 2\n", .{name});
        defer testing.allocator.free(entry);
        const file = try std.fmt.allocPrint(testing.allocator, "{s}.selka", .{name});
        defer testing.allocator.free(file);
        try temp.dir.writeFile(testing.io, .{ .sub_path = file, .data = entry });
    }
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    try gitIn(testing.allocator, root, &.{"init"});
    try gitIn(testing.allocator, root, &.{ "add", "old.selka", "shared.selka", "t1.selka", "t2.selka", "t3.selka" });
    try gitIn(testing.allocator, root, &.{ "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false", "commit", "-m", "base" });
    const line = "warnings: 1 in 1 unmodified module (W_DEPRECATED 1); `selka check --warnings` lists them\n";
    // Each entry's process used to close with this line for itself: three lines, in the order the entries ended.
    for ([_][]const u8{ "1", "3" }) |width| {
        const ran = try privateRun(testing.allocator, &.{ compilerPath(), "test", root, "--jobs", width, "--cache-dir", cache });
        defer testing.allocator.free(ran.stdout);
        defer testing.allocator.free(ran.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, ran.term);
        try testing.expectEqual(@as(usize, 3), std.mem.count(u8, ran.stderr, "error[E_TYPE]"));
        try testing.expectEqual(@as(usize, 0), std.mem.count(u8, ran.stderr, "warning["));
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, ran.stderr, "warnings: "));
        try testing.expect(std.mem.endsWith(u8, ran.stderr, line));
    }
    // One entry run alone prints the same line, as it always did.
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "t1.selka" });
    defer testing.allocator.free(entry);
    const alone = try privateRun(testing.allocator, &.{ compilerPath(), "test", entry, "--cache-dir", cache });
    defer testing.allocator.free(alone.stdout);
    defer testing.allocator.free(alone.stderr);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, alone.stderr, "error[E_TYPE]"));
    try testing.expect(std.mem.endsWith(u8, alone.stderr, line));
}
test "a check session that replays a stored verdict prints what its first request printed, and neither is counted for `selka fix`" {
    // `check-session` is the one command that keeps `check_cache` between requests. It is not a command the display policy covers,
    // so its tally is off for every request: a replay cannot differ from the first run in the closing line, and none is printed.
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "entry.selka", .data =
        \\func show(fs: Filesystem, out: Stream) -> int:
        \\    if fs.exists("x"):
        \\        print(out, "y")
        \\    return 0
        \\
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    return show(own fs, out)
        \\
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "commands", .data = "check\ncheck\nquit\n" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "entry.selka", testing.allocator);
    defer testing.allocator.free(path);
    const input = try temp.dir.openFile(testing.io, "commands", .{});
    defer input.close(testing.io);
    const replies = try temp.dir.createFile(testing.io, "replies", .{});
    defer replies.close(testing.io);
    const errors = try temp.dir.createFile(testing.io, "errors", .{});
    defer errors.close(testing.io);
    var child = try std.process.spawn(testing.io, .{ .argv = &.{ compilerPath(), "check-session", path }, .stdin = .{ .file = input }, .stdout = .{ .file = replies }, .stderr = .{ .file = errors } });
    defer child.kill(testing.io);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try child.wait(testing.io));
    const answered = try temp.dir.readFileAlloc(testing.io, "replies", testing.allocator, .limited(16384));
    defer testing.allocator.free(answered);
    const printed = try temp.dir.readFileAlloc(testing.io, "errors", testing.allocator, .limited(16384));
    defer testing.allocator.free(printed);
    // The second request was served from the in-process cache, and printed the warning again, in the same text.
    try testing.expect(std.mem.indexOf(u8, answered, "\"semantic\":{\"hits\":1,\"misses\":1") != null);
    const warning = "warning[W_CAPABILITY_OWN]";
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, printed, warning));
    const second = std.mem.indexOfPos(u8, printed, std.mem.indexOf(u8, printed, warning).? + warning.len, warning).?;
    const first_text = printed[0 .. std.mem.lastIndexOfScalar(u8, printed[0..second], '\n').? + 1];
    try testing.expectEqualStrings(first_text, printed[first_text.len..]);
    try testing.expect(std.mem.indexOf(u8, printed, "selka fix") == null);
    try testing.expect(std.mem.indexOfScalar(u8, printed, 0) == null);
}
test "CLI preserves integer width bounds and explicit casts" {
    try invoke("run", @embedFile("fixtures/integers.selka"), 0, "6148914691236516950\n", "");
    try invoke("check",
        \\func main() -> i64:
        \\    _ = u8(256)
        \\    return 0
    , 0, "", "");
    try invoke("run",
        \\func main() -> i64:
        \\    _ = u8(256)
        \\    return 0
    , 1, "", "error[R_OVERFLOW]");
    try invoke("run",
        \\func main() -> i64:
        \\    _ = 255u8 + 1u8
        \\    return 0
    , 1, "", "error[R_OVERFLOW]");
    try invoke("check",
        \\func main() -> i64:
        \\    _ = 256u8
        \\    return 0
    , 1, "", "error[E_INTEGER_RANGE]");
    try invoke("check",
        \\func main() -> u8:
        \\    return 0u8
    , 1, "", "error[E_TYPE]");
}
test "CLI checks array schemas dumps indexing and reports bounds traps" {
    try invoke("run", @embedFile("fixtures/arrays.selka"), 0, "44\n", "");
    try invoke("check", @embedFile("fixtures/arrays.selka"), 0, "", "");
    const invalid =
        \\func main() -> i64:
        \\    mut values: FixedArray[i64, 3] = FixedArray[int, 3]([1])
        \\    return values[0]
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| {
        try invoke(command, invalid, 1, "", "error[E_ARRAY_LENGTH]");
    }
    const bounds =
        \\func main() -> i64:
        \\    mut values: FixedArray[i64, 1] = FixedArray[int, 1]([7])
        \\    return values[1]
    ;
    try invoke("check", bounds, 0, "", "");
    try invoke("run", bounds, 1, "", ":3:12: error[R_LIST_BOUNDS]");
    try invoke("run",
        \\func main() -> i64:
        \\    mut payload: FixedArray[u8, 1] = FixedArray[u8, 1]([7u8])
        \\    _ = replace(payload, 18446744073709551615u64, 8u8)
        \\    return 0
    , 1, "", "error[R_LIST_BOUNDS]");
}
test "CLI checks nominal record units and factory execution" {
    try invoke("run", @embedFile("fixtures/domains.selka"), 0, "1003\n", "");
    try invoke("check", @embedFile("fixtures/domains.selka"), 0, "", "");
    try invoke("check",
        \\record Seconds:
        \\    value: i64
        \\
        \\record Millimeters:
        \\    value: i64
        \\
        \\func distance(n: Millimeters) -> i64:
        \\    _ = n
        \\    return 0
        \\
        \\func main() -> i64:
        \\    return distance(Seconds(value=1))
    , 1, "", "expected Millimeters, found Seconds");
}
test "CLI executes variants dumps dispatch and rejects newly incomplete matches" {
    try invoke("run", @embedFile("fixtures/variants.selka"), 0, "24\n", "");
    try invoke("check", @embedFile("fixtures/variants.selka"), 0, "", "");
    const added =
        \\enum Color:
        \\    red
        \\    green
        \\    added
        \\
        \\
        \\func main() -> i64:
        \\    match Color.red:
        \\        case red:
        \\            return 1
        \\        case green:
        \\            return 2
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| try invoke(command, added, 1, "", "match does not handle variant `added`");
    try invoke("check",
        \\enum U:
        \\    value(value: i64)
        \\    empty
        \\
        \\
        \\func main() -> i64:
        \\    _ = U.value(value=True)
        \\    return 0
    , 1, "", "error[E_TYPE]");
    try invoke("run",
        \\enum U:
        \\    value(value: i64)
        \\
        \\
        \\func main() -> i64:
        \\    match U.value(value=divtrunc(1, 0)):
        \\        case value(value=_):
        \\            return 0
    , 1, "", "error[R_DIVISION_BY_ZERO]");
}
test "CLI executes complete enum tables and rejects missing mappings in every command" {
    try invoke("run", @embedFile("fixtures/tables.selka"), 0, "1407\n", "");
    try invoke("check", @embedFile("fixtures/tables.selka"), 0, "", "");
    const added =
        \\enum Key:
        \\    old
        \\    added
        \\
        \\
        \\func main() -> i64:
        \\    mut table: [Key]i64 = {Key.old: 7}
        \\    return table[Key.old]
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| try invoke(command, added, 1, "", "missing initializer for key `added`");
    try invoke("check",
        \\enum Key:
        \\    a
        \\
        \\
        \\func main() -> i64:
        \\    mut table: [Key]i64 = {Key.a: 7}
        \\    return table[0]
    , 1, "", "expected Key, found int");
    // A positional list cannot stand in for an enum-keyed table; only named entries reach one.
    try invoke("check",
        \\enum Key:
        \\    a
        \\
        \\
        \\func main() -> i64:
        \\    mut table: [Key]i64 = [7]
        \\    return table[Key.a]
    , 1, "", "error[E_LIST_TYPE]");
}
test "CLI handles recoverable results and rejects silent error loss" {
    const source = @embedFile("fixtures/results.selka");
    try invoke("run", source, 0, "7\n", "");
    try invoke("check", source, 0, "", "");
    const ignored =
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func main() -> i64:
        \\    mut r: R = Err(7)
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| try invoke(command, ignored, 1, "", "error[E_RESULT_UNHANDLED]");
    try invoke("check",
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func make() -> R:
        \\    return Ok(1)
        \\
        \\
        \\func main() -> i64:
        \\    make()
        \\    return 0
    , 1, "", "error[E_EXPLICIT_DISCARD_REQUIRED]");
}
// spec-case: CLOCK-INTRINSIC-1
test "CLI checks external capabilities but cannot silently grant ambient providers" {
    const source = @embedFile("fixtures/external-capabilities.selka");
    try checkProjectClean(source);
    try invokeProjectOptions("run", source, &.{"--restrict"}, 2, "", "--restrict is active");
    const invalid =
        // migrate-embedded: skip intentional E_EFFECTS_REMOVED diagnostic input
        \\import time
        \\
        \\
        \\func main(c: Clock) -> int effects():
        \\    _ = time.now(c)
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "discover-project-duplicates" }) |command| try invokeProject(command, invalid, 1, "", "error[E_EFFECTS_REMOVED]");
}
test "CLI checks bounded environment access without granting ambient process access" {
    const source = @embedFile("fixtures/environment.selka");
    try invoke("check", source, 0, "", "");
    try invokeOptions("run", source, &.{"--restrict"}, 2, "", "--restrict is active");
    const invalid =
        \\func main(env: Environment) -> i64 effects():
        \\    _ = env.get("K")
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_EFFECTS_REMOVED]");
}
// spec: CAPABILITY-METHOD-NARROWING-2
test "CLI exposes fs.read_only permission attenuation and rejects the removed spelling" {
    const source = @embedFile("fixtures/attenuation.selka");
    try invoke("check", source, 0, "", "");
    try invokeOptions("run", source, &.{"--restrict"}, 2, "", "--restrict is active");
    const invalid =
        \\func main(fs: Filesystem) -> i64:
        \\    _ = restrict_resource[read, read](fs)
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_REMOVED_SPELLING]");
    const extra =
        \\func main(fs: Filesystem) -> i64:
        \\    _ = fs.read_only(1)
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| try invoke(command, extra, 1, "", "error[E_ARITY]");
}
// spec: NETWORK-HOST-1
test "CLI narrows a Network to one literal endpoint and rejects a dynamic host" {
    const source =
        \\import network
        \\
        \\func main(net: Network) -> int:
        \\    with net.host("127.0.0.1:8000") as scoped:
        \\        match network.connect(scoped):
        \\            case ok(socket):
        \\                _ = network.close(own socket)
        \\                return 0
        \\            case err(code):
        \\                return code
    ;
    try invoke("check", source, 0, "", "");
    // FR5a: the raw builtin on a Network belongs to the standard library, whose requests are its own encoding.
    const raw =
        \\resource Socket: network
        \\
        \\result Open:
        \\    ok: Socket,
        \\    err: int
        \\
        \\func main(net: Network) -> int:
        \\    with net.host("127.0.0.1:8000") as scoped:
        \\        mut request: FixedArray[u8, 1] = FixedArray[u8, 1]([0u8])
        \\        match acquire_resource[Open](scoped, request):
        \\            case ok(socket):
        \\                _ = own socket
        \\                return 0
        \\            case err(code):
        \\                return code
    ;
    for ([_][]const u8{ "check", "run" }) |command| try invoke(command, raw, 1, "", "error[E_INTERNAL_NAME]: `acquire_resource` on a Network is reserved for the standard library");
    const dynamic =
        \\resource Socket: network
        \\
        \\result Open:
        \\    ok: Socket,
        \\    err: int
        \\
        \\func main(net: Network) -> int:
        \\    mut endpoint = "127.0.0.1:8000"
        \\    mut scoped = net.host(endpoint)
        \\    mut request: FixedArray[u8, 1] = [0u8]
        \\    match acquire_resource[Open](scoped, request):
        \\        case ok(socket):
        \\            _ = socket
        \\            return 0
        \\        case err(code):
        \\            return code
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| try invoke(command, dynamic, 1, "", "error[E_NETWORK_HOST]");
}

/// A project guest whose `main` takes a `Network`, narrows it to one literal
/// endpoint and reports the acquisition code. Used by the grant tests.
const network_connect_guest =
    \\import network
    \\
    \\
    \\func main(net: Network) -> int:
    \\    with net.host("127.0.0.1:9") as scoped:
    \\        match network.connect(scoped):
    \\            case ok(connection):
    \\                _ = own connection
    \\                return 0
    \\            case err(code):
    \\                return code
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

/// True when the guest process is gone, so a blocking wait must not outlive it.
fn guestExited(pid: std.os.linux.pid_t) bool {
    return std.os.linux.errno(std.os.linux.kill(pid, @fromBackingInt(0))) == .SRCH;
}

/// Accept one loopback connection unless the guest exits or five minutes pass.
///
/// The pinned `Server.accept` has no deadline: when a guest fails to build, or
/// exits before it connects, an unbounded accept held a gate for hours on
/// 20 October. Polling the listening socket and the guest together makes that a
/// test failure instead. Every accept in this root goes through this helper.
fn acceptBeforeExit(io: std.Io, server: *std.Io.net.Server, pid: std.os.linux.pid_t) !std.Io.net.Stream {
    const linux = std.os.linux;
    var waited_ms: usize = 0;
    while (waited_ms < 300_000) : (waited_ms += 100) {
        var polls = [1]linux.pollfd{.{ .fd = server.socket.handle, .events = linux.POLL.IN, .revents = 0 }};
        const ready = linux.poll(&polls, 1, 100);
        if (linux.errno(ready) == .SUCCESS and ready > 0 and polls[0].revents & linux.POLL.IN != 0) {
            return server.accept(io);
        }
        if (guestExited(pid)) return error.TestUnexpectedResult;
    }
    return error.TestUnexpectedResult;
}

/// Accept the guest's write connection, assert the payload, answer it and close.
fn acceptPayload(io: std.Io, server: *std.Io.net.Server, pid: std.os.linux.pid_t) !void {
    const peer = try acceptBeforeExit(io, server, pid);
    defer peer.close(io);
    var buffer: [4]u8 = undefined;
    const width = try readExact(io, peer, &buffer);
    try testing.expectEqualStrings("ping", buffer[0..width]);
    var writer = peer.writer(io, &.{});
    try writer.interface.writeAll("PONG");
}

/// Accept the guest's read connection and answer it with the echo payload.
fn acceptBanner(io: std.Io, server: *std.Io.net.Server, pid: std.os.linux.pid_t) !void {
    const peer = try acceptBeforeExit(io, server, pid);
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
        \\import network
        \\
        \\
        \\func main(net: Network) -> int:
        \\    with net.host("{s}") as scoped:
        \\        match network.connect(scoped):
        \\            case ok(first):
        \\                mut payload: FixedArray[u8, 4] = b"ping"
        \\                match network.write(own first, payload):
        \\                    case ok(sent):
        \\                        _ = sent
        \\                    case err(code):
        \\                        return 0 - code
        \\            case err(code):
        \\                return 0 - code
        \\        match network.connect(scoped):
        \\            case ok(second):
        \\                match network.read[4](own second):
        \\                    case ok(chunk):
        \\                        return int(chunk.bytes[0]) + int(chunk.bytes[1]) + int(chunk.bytes[2]) + int(chunk.bytes[3]) + int(chunk.length)
        \\                    case err(code):
        \\                        return 0 - code
        \\            case err(code):
        \\                return 0 - code
        \\
    , .{name});
    defer testing.allocator.free(source);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const grant = try std.fmt.allocPrint(testing.allocator, "--allow-endpoint={s}", .{name});
    defer testing.allocator.free(grant);
    const output = try temporary.dir.createFile(testing.io, "stdout", .{});
    defer output.close(testing.io);
    const failure = try temporary.dir.createFile(testing.io, "stderr", .{});
    defer failure.close(testing.io);
    const argv = [_][]const u8{ compilerPath(), "run", entry, "--print-result", tools[0], "--restrict", grant };
    var child = try std.process.spawn(testing.io, .{ .argv = &argv, .stdin = .ignore, .stdout = .{ .file = output }, .stderr = .{ .file = failure } });
    defer child.kill(testing.io);
    // The guest opens two connections: send `ping` on the first (summed bytes:
    // P+O+N+G + length 4 = 312) and read `PONG` on the second.
    const pid = child.id.?;
    try acceptPayload(testing.io, &server, pid);
    try acceptBanner(testing.io, &server, pid);
    try testing.expectEqual(std.process.Child.Term{ .exited = 312 & 0xff }, try child.wait(testing.io));
    const printed = try temporary.dir.readFileAlloc(testing.io, "stdout", testing.allocator, .limited(4096));
    defer testing.allocator.free(printed);
    try testing.expectEqualStrings("312\n", printed);
}

/// Ask the kernel for a free loopback port and release it, returning the
/// `127.0.0.1:PORT` literal. The only race is the gap before the guest binds it.
fn freeLoopbackEndpoint(allocator: std.mem.Allocator) ![]u8 {
    const address = try std.Io.net.IpAddress.parseLiteral("127.0.0.1:0");
    var probe = try address.listen(testing.io, .{});
    defer probe.deinit(testing.io);
    return std.fmt.allocPrint(allocator, "{f}", .{probe.socket.address});
}

/// Dial `address` until the guest under test has bound it, giving up after five
/// minutes (a cold build of the guest's runtime unit takes most of a minute).
fn connectWhenListening(io: std.Io, address: std.Io.net.IpAddress) !std.Io.net.Stream {
    var attempts: usize = 0;
    while (attempts < 6000) : (attempts += 1) {
        if (address.connect(io, .{ .mode = .stream })) |stream| return stream else |_| {}
        std.Io.sleep(io, std.Io.Duration.fromMilliseconds(50), .awake) catch {};
    }
    return error.TestUnexpectedResult;
}

/// A project guest whose `main` takes a `Network` and tries to listen on a
/// literal endpoint. Used to check the listening grant's refusal paths.
const network_listen_guest =
    \\import network
    \\
    \\
    \\func main(net: Network) -> int:
    \\    with net.host("127.0.0.1:9") as scoped:
    \\        match network.listen(scoped):
    \\            case ok(listener):
    \\                _ = own listener
    \\                return 0
    \\            case err(code):
    \\                return code
;

// spec: NETWORK-SERVER-1
test "CLI listens on an allowed endpoint and serves an HTTP request" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    // The guest names its endpoint by literal, so rewrite the fixture's
    // placeholder to a free loopback port.
    const name = try freeLoopbackEndpoint(testing.allocator);
    defer testing.allocator.free(name);
    const source = try std.mem.replaceOwned(u8, testing.allocator, @embedFile("fixtures/http_server.selka"), "127.0.0.1:18080", name);
    defer testing.allocator.free(source);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const grant = try std.fmt.allocPrint(testing.allocator, "--allow-listen={s}", .{name});
    defer testing.allocator.free(grant);
    const output = try temporary.dir.createFile(testing.io, "stdout", .{});
    defer output.close(testing.io);
    const failure = try temporary.dir.createFile(testing.io, "stderr", .{});
    defer failure.close(testing.io);
    const argv = [_][]const u8{ compilerPath(), "run", entry, "--print-result", tools[0], "--restrict", grant };
    var child = try std.process.spawn(testing.io, .{ .argv = &argv, .stdin = .ignore, .stdout = .{ .file = output }, .stderr = .{ .file = failure } });
    defer child.kill(testing.io);
    const stream = try connectWhenListening(testing.io, try std.Io.net.IpAddress.parseLiteral(name));
    defer stream.close(testing.io);
    var writer = stream.writer(testing.io, &.{});
    try writer.interface.writeAll("GET / HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n");
    var response: [4096]u8 = undefined;
    const width = try readExact(testing.io, stream, &response);
    const text = response[0..width];
    try testing.expect(std.mem.startsWith(u8, text, "HTTP/1.1 200 OK\r\n"));
    try testing.expect(std.mem.endsWith(u8, text, "hello from selka\n"));
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try child.wait(testing.io));
}

/// A guest that accepts one connection and then writes to it after the client has closed (FR-020).
/// Each refused write is counted; the guest must keep running until three have been refused.
const closed_peer_guest =
    \\import network
    \\
    \\
    \\func main(net: Network, out: Stream) -> int:
    \\    with net.host("127.0.0.1:18082") as scoped:
    \\        match network.listen(scoped):
    \\            case ok(owned):
    \\                mut listener = own owned
    \\                match accept_resource[network.Accepted](listener):
    \\                    case Ok(connection):
    \\                        return flood(own connection, out)
    \\                    case Err(code):
    \\                        print(out, "accept failed", code)
    \\                        return 2
    \\            case err(code):
    \\                print(out, "listen failed", code)
    \\                return 1
    \\
    \\
    \\func flood(own connection: network.Connection, out: Stream) -> int:
    \\    mut live = own connection
    \\    mut refused = 0
    \\    mut attempts = 0
    \\    while refused < 3:
    \\        attempts += 1
    \\        if attempts > 100000:
    \\            return 3
    \\        match write_resource[network.Written](live, b"0123456789abcdef"):
    \\            case Ok(count):
    \\                _ = count
    \\            case Err(code):
    \\                _ = code
    \\                refused += 1
    \\    print(out, "refused", refused)
    \\    return 0
;

// FR-020: a blocking server that writes after its client has gone gets refused writes and keeps running.
test "CLI blocking server survives writes after its client has closed" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const name = try freeLoopbackEndpoint(testing.allocator);
    defer testing.allocator.free(name);
    const source = try std.mem.replaceOwned(u8, testing.allocator, closed_peer_guest, "127.0.0.1:18082", name);
    defer testing.allocator.free(source);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const grant = try std.fmt.allocPrint(testing.allocator, "--allow-listen={s}", .{name});
    defer testing.allocator.free(grant);
    const output = try temporary.dir.createFile(testing.io, "stdout", .{});
    defer output.close(testing.io);
    const failure = try temporary.dir.createFile(testing.io, "stderr", .{});
    defer failure.close(testing.io);
    const argv = [_][]const u8{ compilerPath(), "run", entry, tools[0], "--restrict", grant };
    var child = try std.process.spawn(testing.io, .{ .argv = &argv, .stdin = .ignore, .stdout = .{ .file = output }, .stderr = .{ .file = failure } });
    defer child.kill(testing.io);
    const stream = try connectWhenListening(testing.io, try std.Io.net.IpAddress.parseLiteral(name));
    stream.close(testing.io);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try child.wait(testing.io));
    const printed = try temporary.dir.readFileAlloc(testing.io, "stdout", testing.allocator, .limited(1 << 16));
    defer testing.allocator.free(printed);
    try testing.expectEqualStrings("refused 3\n", printed);
}

/// A guest that reads one `Read[65536]` chunk per call from the first connection it accepts and
/// sums `byte * 3 + index % 7` over every byte it receives (the FR-217 repro's arithmetic).
const chunk_checksum_guest =
    \\import network
    \\
    \\
    \\func main(net: Network) -> int:
    \\    with net.host("{s}") as scoped:
    \\        match network.listen(scoped):
    \\            case ok(owned):
    \\                mut listener = own owned
    \\                match accept_resource[network.Accepted](listener):
    \\                    case Ok(connection):
    \\                        return checksum(own connection)
    \\                    case Err(code):
    \\                        return 0 - code
    \\            case err(code):
    \\                return 0 - code
    \\
    \\
    \\func checksum(own connection: network.Connection) -> int:
    \\    mut live = own connection
    \\    mut total = 0
    \\    mut seen = 0
    \\    while True:
    \\        match read_resource[network.Read[65536]](live):
    \\            case Ok(chunk):
    \\                mut index = 0
    \\                while index < int(chunk.length):
    \\                    total += int(chunk.bytes[index]) * 3 + (seen + index) % 7
    \\                    index += 1
    \\                seen += int(chunk.length)
    \\                if chunk.eof:
    \\                    return total
    \\            case Err(code):
    \\                return 0 - code
    \\    return total
    \\
;

// spec: CORE-ARRAY-FROM-BYTES-1
test "a 64 KiB network chunk emits code whose size does not depend on the chunk" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const source = try std.fmt.allocPrint(testing.allocator, chunk_checksum_guest, .{"127.0.0.1:9"});
    defer testing.allocator.free(source);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "chunk.selka", .data = source });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "chunk.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const llvm = try std.fs.path.join(testing.allocator, &.{ root, "chunk.ll" });
    defer testing.allocator.free(llvm);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "chunk" });
    defer testing.allocator.free(output);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{root});
    defer testing.allocator.free(cache);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", output, "--emit-llvm", llvm, cache, tools[0] }, "");
    const text = try temporary.dir.readFileAlloc(testing.io, "chunk.ll", testing.allocator, .limited(64 << 20));
    defer testing.allocator.free(text);
    // Filling the array element by element made this file about 20 MB and its build a minute.
    try testing.expect(text.len < 256 * 1024);
    try testing.expect(std.mem.indexOf(u8, text, "llvm.memcpy.p0.p0.i64(ptr %") != null);
}

/// A guest that appends the filled part of one `Read[65536]` chunk to a builder (FR-205).
const chunk_append_guest =
    \\import byte_builder
    \\import network
    \\
    \\
    \\func main(net: Network) -> int:
    \\    with net.host("127.0.0.1:9") as scoped:
    \\        match network.listen(scoped):
    \\            case ok(owned):
    \\                mut listener = own owned
    \\                match accept_resource[network.Accepted](listener):
    \\                    case Ok(connection):
    \\                        return gather(own connection)
    \\                    case Err(code):
    \\                        return 0 - code
    \\            case err(code):
    \\                return 0 - code
    \\
    \\
    \\func gather(own connection: network.Connection) -> int:
    \\    mut live = own connection
    \\    mut raw = byte_builder.create()
    \\    while True:
    \\        match read_resource[network.Read[65536]](live):
    \\            case Ok(chunk):
    \\                if not byte_builder.append_array(mut raw, chunk.bytes, int(chunk.length)):
    \\                    return 0 - 1
    \\                if chunk.eof:
    \\                    return len(byte_builder.finish(raw))
    \\            case Err(code):
    \\                return 0 - code
    \\    return 0
    \\
;

// spec-case: BYTE-BUFFER-APPEND-ARRAY-1
test "appending a 64 KiB chunk is one runtime copy and code that does not grow with the chunk" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "append.selka", .data = chunk_append_guest });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "append.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const llvm = try std.fs.path.join(testing.allocator, &.{ root, "append.ll" });
    defer testing.allocator.free(llvm);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "append" });
    defer testing.allocator.free(output);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{root});
    defer testing.allocator.free(cache);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", output, "--emit-llvm", llvm, cache, tools[0] }, "");
    const text = try temporary.dir.readFileAlloc(testing.io, "append.ll", testing.allocator, .limited(64 << 20));
    defer testing.allocator.free(text);
    try testing.expect(text.len < 256 * 1024);
    // One call hands the array's address to the runtime; no octet is pushed one at a time for it.
    try testing.expect(std.mem.indexOf(u8, text, "@myl_core_buffer_append_octets(ptr") != null);
    try testing.expect(std.mem.indexOf(u8, text, "i64 65536, i64 0, i64") != null);
    try testing.expectEqual(@as(usize, 0), std.mem.count(u8, text, "call ptr @myl_core_buffer_push_checked("));
}

// spec-case: CORE-ARRAY-FROM-BYTES-1
test "CLI reads a 40,000 byte payload through a 64 KiB chunk with every octet intact" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const name = try freeLoopbackEndpoint(testing.allocator);
    defer testing.allocator.free(name);
    const source = try std.fmt.allocPrint(testing.allocator, chunk_checksum_guest, .{name});
    defer testing.allocator.free(source);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const grant = try std.fmt.allocPrint(testing.allocator, "--allow-listen={s}", .{name});
    defer testing.allocator.free(grant);
    const output = try temporary.dir.createFile(testing.io, "stdout", .{});
    defer output.close(testing.io);
    const failure = try temporary.dir.createFile(testing.io, "stderr", .{});
    defer failure.close(testing.io);
    const argv = [_][]const u8{ compilerPath(), "run", entry, "--print-result", tools[0], "--restrict", grant };
    var child = try std.process.spawn(testing.io, .{ .argv = &argv, .stdin = .ignore, .stdout = .{ .file = output }, .stderr = .{ .file = failure } });
    defer child.kill(testing.io);
    var payload: [40000]u8 = undefined;
    var expected: i64 = 0;
    for (&payload, 0..) |*octet, index| {
        octet.* = @truncate(index *% 31 +% 7);
        expected += @as(i64, octet.*) * 3 + @as(i64, @intCast(index % 7));
    }
    const stream = try connectWhenListening(testing.io, try std.Io.net.IpAddress.parseLiteral(name));
    defer stream.close(testing.io);
    var writer = stream.writer(testing.io, &.{});
    try writer.interface.writeAll(&payload);
    try stream.shutdown(testing.io, .send);
    _ = try child.wait(testing.io);
    const printed = try temporary.dir.readFileAlloc(testing.io, "stdout", testing.allocator, .limited(4096));
    defer testing.allocator.free(printed);
    const wanted = try std.fmt.allocPrint(testing.allocator, "{d}\n", .{expected});
    defer testing.allocator.free(wanted);
    try testing.expectEqualStrings(wanted, printed);
}

/// Opens `count` nonblocking loopback connections to `port` without accepting any, giving each
/// `wait_ms` to finish its handshake, and returns how many did. Every socket is closed on return.
fn connectionsHeld(port: u16, count: usize, wait_ms: i32) usize {
    const linux = std.os.linux;
    var open: [256]i32 = undefined;
    var held: usize = 0;
    var made: usize = 0;
    while (made < count) : (made += 1) {
        const fd: i32 = @intCast(linux.socket(linux.AF.INET, linux.SOCK.STREAM | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC, 0));
        open[made] = fd;
        const address: linux.sockaddr.in = .{ .port = std.mem.nativeToBig(u16, port), .addr = std.mem.nativeToBig(u32, 0x7f000001) };
        _ = linux.connect(fd, &address, @sizeOf(linux.sockaddr.in));
        var poll = [1]linux.pollfd{.{ .fd = fd, .events = linux.POLL.OUT, .revents = 0 }};
        const ready = linux.poll(&poll, 1, wait_ms);
        held += @intFromBool(ready == 1 and poll[0].revents & linux.POLL.OUT != 0 and poll[0].revents & (linux.POLL.ERR | linux.POLL.HUP) == 0);
    }
    for (open[0..made]) |fd| _ = linux.close(fd);
    return held;
}

/// The kernel's `net.core.somaxconn`, the most a listen backlog can be.
fn kernelBacklogLimit() !usize {
    var buffer: [32]u8 = undefined;
    const text = try std.Io.Dir.cwd().readFile(testing.io, "/proc/sys/net/core/somaxconn", &buffer);
    return std.fmt.parseInt(usize, std.mem.trim(u8, text, " \n"), 10);
}

/// A guest that opens a poller on a literal endpoint, accepts the first connection only, and returns when
/// that connection closes; every later connection stays in the kernel's accept queue.
const single_accept_poller_guest =
    \\import byte_builder
    \\import network
    \\
    \\
    \\func serve(own poller: network.Poller) -> int:
    \\    mut live = own poller
    \\    mut outcome = network.new_outcome()
    \\    mut ready = network.new_ready()
    \\    while True:
    \\        live = network.wait(own live, -1, mut ready)
    \\        for index in range(ready.count):
    \\            const id = ready.ids[index]
    \\            if id == network.LISTENER:
    \\                live = network.accept(own live, mut outcome)
    \\                live = network.set_interest(own live, network.LISTENER, 0, mut outcome)
    \\            else:
    \\                mut raw = byte_builder.create()
    \\                live = network.recv(own live, id, mut raw, mut outcome)
    \\                if outcome.code == network.OUTCOME_CLOSED:
    \\                    return 0
    \\    return 0
    \\
    \\
    \\func main(net: Network) -> int:
    \\    with net.host("{s}") as scoped:
    \\        match network.open_poller(scoped):
    \\            case ok(poller):
    \\                return serve(own poller)
    \\            case err(code):
    \\                return code
    \\
;

// spec: NETWORK-BACKLOG-1
test "a listener queues the connections that arrive before the program accepts any" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const name = try freeLoopbackEndpoint(testing.allocator);
    defer testing.allocator.free(name);
    const source = try std.fmt.allocPrint(testing.allocator, single_accept_poller_guest, .{name});
    defer testing.allocator.free(source);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const grant = try std.fmt.allocPrint(testing.allocator, "--allow-listen={s}", .{name});
    defer testing.allocator.free(grant);
    const output = try temporary.dir.createFile(testing.io, "stdout", .{});
    defer output.close(testing.io);
    const failure = try temporary.dir.createFile(testing.io, "stderr", .{});
    defer failure.close(testing.io);
    const argv = [_][]const u8{ compilerPath(), "run", entry, tools[0], "--restrict", grant };
    var child = try std.process.spawn(testing.io, .{ .argv = &argv, .stdin = .ignore, .stdout = .{ .file = output }, .stderr = .{ .file = failure } });
    defer child.kill(testing.io);
    const address = try std.Io.net.IpAddress.parseLiteral(name);
    // The guest accepts this connection and exits when it closes, which the deferred close below
    // does before the child is killed, so no guest outlives the test.
    const first = try connectWhenListening(testing.io, address);
    defer first.close(testing.io);
    const wanted = @min(100, (try kernelBacklogLimit()) -| 2);
    // A backlog of 64 held 65 of them and left the others to retransmit their SYN a second later.
    try testing.expect(wanted > 70);
    try testing.expectEqual(wanted, connectionsHeld(address.ip4.port, wanted, 300));
}

// spec-case: NETWORK-SERVER-1
test "CLI keeps a listener unreadable and accepts only on a listener" {
    const name = try freeLoopbackEndpoint(testing.allocator);
    defer testing.allocator.free(name);
    const source = try std.fmt.allocPrint(testing.allocator,
        \\import network
        \\
        \\
        \\func main(net: Network) -> int:
        \\    with net.host("{s}") as scoped:
        \\        match network.listen(scoped):
        \\            case ok(owned):
        \\                mut listener = own owned
        \\                match network.connect(scoped):
        \\                    case ok(peer):
        \\                        mut connection = own peer
        \\                        mut code = 0
        \\                        match read_resource[network.Read[8]](listener):
        \\                            case Ok(chunk):
        \\                                _ = chunk
        \\                                return 10
        \\                            case Err(first):
        \\                                code = first
        \\                        match accept_resource[network.Accepted](connection):
        \\                            case Ok(second):
        \\                                _ = own second
        \\                                return 11
        \\                            case Err(second):
        \\                                return code * 10 + second
        \\                    case err(failed):
        \\                        return 0 - failed
        \\            case err(failed):
        \\                return 0 - failed
        \\
    , .{name});
    defer testing.allocator.free(source);
    const listen_grant = try std.fmt.allocPrint(testing.allocator, "--allow-listen={s}", .{name});
    defer testing.allocator.free(listen_grant);
    const connect_grant = try std.fmt.allocPrint(testing.allocator, "--allow-endpoint={s}", .{name});
    defer testing.allocator.free(connect_grant);
    // Both operations answer Denied (2) at once: a read on the listener, and an
    // accept on an outbound connection that never held the accept right.
    try invokeProjectOptions("run", source, &.{ "--restrict", listen_grant, connect_grant }, 22, "22\n", "");
}

// spec-case: NETWORK-SERVER-1
test "CLI refuses a listen without authority and rejects malformed listen grants" {
    try invokeProjectOptions("run", network_listen_guest, &.{"--restrict"}, 2, "", "--allow-listen=IP:PORT");
    try invokeProjectOptions("run", network_listen_guest, &.{ "--restrict", "--allow-listen=127.0.0.1:10" }, 2, "2\n", "");
    // A port-0 grant is valid (the kernel chooses the port); it permits only a port-0 narrowing.
    try invokeProjectOptions("run", network_listen_guest, &.{ "--restrict", "--allow-listen=127.0.0.1:0" }, 2, "2\n", "");
    for ([_][]const []const u8{
        &.{"--allow-listen="},
        &.{"--allow-listen=localhost:9"},
        &.{"--allow-listen=[::1]:9"},
        &.{ "--allow-listen=127.0.0.1:9", "--allow-listen=127.0.0.1:9" },
    }) |options| try invokeProjectOptions("run", network_listen_guest, options, 2, "", "usage:");
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
    const source = @embedFile("fixtures/file-methods.selka");
    try invoke("check", source, 0, "", "");
    const invalid =
        \\func main(fs: Filesystem) -> int:
        \\    _ = fs.read_text()
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_ARITY]");
}

const clock_program =
    \\import strings
    \\import time
    \\
    \\
    \\func main(clock: Clock) -> int:
    \\    const instant = time.now(clock) else Err(message):
    \\        return strings.char_count(message)
    \\    return instant.unix_nanoseconds - instant.unix_nanoseconds
;
// spec: CAPABILITY-1
test "CLI accepts Python capability spellings and lets a declared type keep the name" {
    try invokeProject("check", clock_program, 0, "", "");
    const declared =
        \\record Clock:
        \\    ticks: int
        \\
        \\func main() -> int:
        \\    return Clock(ticks=7).ticks
    ;
    try invoke("run", declared, 0, "7\n", "");
    const entropy =
        \\import random
        \\
        \\
        \\func main(rng: Entropy) -> int:
        \\    _ = random.from_entropy(rng)
        \\    return 0
    ;
    try checkProjectClean(entropy);
    try invoke("check",
        \\func main(env: Environment) -> i64:
        \\    _ = env
        \\    return 0
    , 0, "", "");
    try invoke("check",
        \\func main(fs: Filesystem) -> i64:
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
}
// spec: CAPABILITY-3
test "CLI refuses an ungranted entry capability only while --restrict is active" {
    const environment =
        \\func main(env: Environment) -> i64:
        \\    _ = env.get("PATH")
        \\    return 0
    ;
    // A `Clock` starts without a grant (CAPGRANT); its `time.now` fails with "the wall clock is not granted: pass
    // `--allow-clock`", whose 51 characters the program returns.
    try invokeProjectOptions("run", clock_program, &.{"--restrict"}, 51, "51\n", "");
    // The default grants every capability, so the same program runs unchanged.
    try invokeProject("run", clock_program, 0, "0\n", "");
    try invokeOptions("run", environment, &.{"--restrict"}, 2, "", "--restrict is active");
    try invokeOptions("run", environment, &.{"--restrict"}, 2, "", "drop --restrict");
    try invoke("run", environment, 0, "0\n", "");
    try invokeProjectOptions("run", clock_program, &.{ "--restrict", "--allow-clock" }, 0, "0\n", "");
    try invokeOptions("run", environment, &.{ "--restrict", "--allow-env=PATH" }, 0, "0\n", "");
    // A grant the entry point never requests is simply never read.
    try invokeOptions("run",
        \\func main() -> i64:
        \\    return 4
    , &.{ "--restrict", "--allow-clock", "--allow-random=7" }, 0, "4\n", "");
}
// spec: CAPABILITY-5
test "CLI clock entropy and environment providers honour their grants" {
    const seeded =
        \\import strings
        \\import random
        \\
        \\
        \\func main(rng: Entropy) -> int:
        \\    match random.from_entropy(rng):
        \\        case Ok(generator):
        \\            return int(generator.state[0] % 1000u64)
        \\        case Err(message):
        \\            return strings.char_count(message)
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
    // migrate-embedded: skip -- exact original effect-clause rejection witness.
    const missing =
        \\func main(env: Environment) -> i64 effects(environment):
        \\    match env.get("PATH"):
        \\        case Some(value):
        \\            return strings.char_count(value) - strings.char_count(value)
        \\        case None:
        \\            return 0
    ;
    // PATH is outside this allowlist, so the lookup is denied and the native
    // Python surface traps instead of answering None.
    try invokeOptions("run", missing, &.{ "--restrict", "--allow-env=OTHER" }, 1, "", "E_EFFECTS_REMOVED");
    const denied_lookup = try std.mem.replaceOwned(u8, testing.allocator, missing, " effects(environment)", "");
    defer testing.allocator.free(denied_lookup);
    try invokeOptions("run", denied_lookup, &.{ "--restrict", "--allow-env=OTHER" }, 1, "", "R_CAPABILITY");
}

// spec: CAPABILITY-4
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
    // The fixture runs from elsewhere, so the program names the granted files by their absolute paths, as a plain run
    // would (docs/io.md, "How a path is read").
    const program = try std.mem.replaceOwned(u8, testing.allocator,
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    print(out, fs.read_text("@DIR@/notes.txt"))
        \\    print(out, fs.write_text("@DIR@/copy.txt", "beta\n"))
        \\    print(out, fs.read_text("@DIR@/../escape"))
        \\    return 0
    , "@DIR@", directory);
    defer testing.allocator.free(program);
    // These fixtures pass --print-result, so the entry point's `0` follows the program's output.
    const denied = try std.fmt.allocPrint(testing.allocator, "Err(\"read '{0s}/../escape': denied: '{1s}/escape' is outside the granted directories\")\n0\n", .{ directory, std.fs.path.dirname(directory).? });
    defer testing.allocator.free(denied);
    const refused = try std.fmt.allocPrint(testing.allocator, "Ok('alpha\\n')\nErr(\"write '{0s}/copy.txt': denied: writing needs a write grant (--allow-write); '{0s}/copy.txt' is granted for reading only\")\n{1s}", .{ directory, denied });
    defer testing.allocator.free(refused);
    try invokeOptions("run", program, &.{ "--restrict", read_grant }, 0, refused, "");
    const wrote = try std.fmt.allocPrint(testing.allocator, "Ok('alpha\\n')\nOk(None)\n{s}", .{denied});
    defer testing.allocator.free(wrote);
    try invokeOptions("run", program, &.{ "--restrict", write_grant }, 0, wrote, "");
    const written = try temporary.dir.readFileAlloc(testing.io, "copy.txt", testing.allocator, .limited(32));
    defer testing.allocator.free(written);
    try testing.expectEqualStrings("beta\n", written);
    // A write grant alone launched the run above, so the refusal of a run with no grant names both flags, not only the read one.
    try invokeOptions("run", program, &.{"--restrict"}, 2, "", "pass --allow-read=DIR or --allow-write=DIR, or drop --restrict");
}
// spec-case: CAPABILITY-4
test "CLI a copied and stored capability keeps its directory grant under --restrict (5C)" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "notes.txt", .data = "alpha\n" });
    const anchor = try temporary.dir.realPathFileAlloc(testing.io, "notes.txt", testing.allocator);
    defer testing.allocator.free(anchor);
    const directory = std.fs.path.dirname(anchor).?;
    const read_grant = try std.fmt.allocPrint(testing.allocator, "--allow-read={s}", .{directory});
    defer testing.allocator.free(read_grant);
    // A capability is a shareable handle: the copy in the list and the narrowed copy keep the read-only grant.
    const program = try std.mem.replaceOwned(u8, testing.allocator,
        \\record Ports:
        \\    fs: Filesystem
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    const ports = [Ports(fs=fs), Ports(fs=copy(fs))]
        \\    const kept = ports[1].fs
        \\    print(out, kept.read_text("@DIR@/notes.txt"))
        \\    print(out, kept.write_text("@DIR@/copy.txt", "beta\n"))
        \\    print(out, ports[0].fs.read_only().read_text("@DIR@/../escape"))
        \\    return 0
    , "@DIR@", directory);
    defer testing.allocator.free(program);
    const expected = try std.fmt.allocPrint(testing.allocator, "Ok('alpha\\n')\n" ++
        "Err(\"write '{0s}/copy.txt': denied: writing needs a write grant (--allow-write); '{0s}/copy.txt' is granted for reading only\")\n" ++
        "Err(\"read '{0s}/../escape': denied: '{1s}/escape' is outside the granted directories\")\n0\n", .{ directory, std.fs.path.dirname(directory).? });
    defer testing.allocator.free(expected);
    try invokeOptions("run", program, &.{ "--restrict", read_grant }, 0, expected, "");
    try testing.expectError(error.FileNotFound, temporary.dir.statFile(testing.io, "copy.txt", .{}));
}
// spec-case: IO-1
test "CLI streams program output and reports the entry result only on request" {
    const program =
        \\func main(out: Stream) -> int:
        \\    print(out, "streamed")
        \\    return 7
    ;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data = program });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "input.selka", testing.allocator);
    defer testing.allocator.free(path);
    const plain = try std.process.run(testing.allocator, testing.io, .{ .argv = &(.{ compilerPath(), "run", path } ++ tools) });
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
        \\import time
        \\import random
        \\
        \\func main(clock: Clock, rng: Entropy, fs: Filesystem, out: Stream) -> int:
        \\    match time.now(clock):
        \\        case Ok(instant):
        \\            print(out, "clock", instant.unix_nanoseconds - instant.unix_nanoseconds)
        \\        case Err(message):
        \\            print(out, message)
        \\    match random.from_entropy(rng):
        \\        case Ok(stream):
        \\            print(out, "entropy", len(stream.state))
        \\        case Err(message):
        \\            print(out, message)
        \\    print(out, fs.exists("notes.txt"))
        \\    return 0
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = entry });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(path);
    const directory = std.fs.path.dirname(path).?;
    const grant = try std.fmt.allocPrint(testing.allocator, "--allow-read={s}", .{directory});
    defer testing.allocator.free(grant);
    const granted = try std.process.run(testing.allocator, testing.io, .{
        .argv = &(.{ compilerPath(), "run-project", path, "--restrict", "--allow-clock", "--allow-random=5", grant } ++ tools),
    });
    defer testing.allocator.free(granted.stdout);
    defer testing.allocator.free(granted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, granted.term);
    try testing.expectEqualStrings("clock 0\nentropy 1\nFalse\n", granted.stdout);
    const ungranted = try std.process.run(testing.allocator, testing.io, .{ .argv = &(.{ compilerPath(), "run-project", path, "--restrict" } ++ tools) });
    defer testing.allocator.free(ungranted.stdout);
    defer testing.allocator.free(ungranted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, ungranted.term);
    // A Clock needs no grant to start (STOPWATCH), so the first capability refused is the Entropy.
    try testing.expect(std.mem.indexOf(u8, ungranted.stderr, "--allow-random") != null);
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\func main(fs: Filesystem, out: Stream) -> int:
        \\    print(out, fs.read_text("notes.txt"))
        \\    print(out, fs.write_text("made.txt", "beta\n"))
        \\    print(out, fs.read_text("../escape"))
        \\    return 0
    });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    // A relative guest path resolves against the process working directory, and
    // a path that leaves it is an ordinary filesystem failure rather than a denial.
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
    defer testing.allocator.free(compiler);
    const outcome = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "run", entry, tools[0] },
        .cwd = .{ .path = directory },
    });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expectEqualStrings("Ok('alpha\\n')\nOk(None)\n" ++
        "Err(\"read '../escape': the path does not exist\")\n", outcome.stdout);
    const written = try temporary.dir.readFileAlloc(testing.io, "made.txt", testing.allocator, .limited(32));
    defer testing.allocator.free(written);
    try testing.expectEqualStrings("beta\n", written);
    // An absolute path names itself, and `--allow-*` without `--restrict` narrows nothing.
    const absolute = try std.fmt.allocPrint(testing.allocator, "func main(fs: Filesystem, out: Stream) -> int:\n    print(out, fs.read_text(\"{s}\"))\n    return 0\n", .{anchor});
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

/// Check a two-module project under `--report`, returning the parsed counters.
fn projectCacheCheck(entry: []const u8, cache_dir: []const u8, expected_status: u8) !CacheCounters {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "check-project", entry, "--report", cache_dir });
    const outcome = try privateRun(testing.allocator, args.items);
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/main.selka", .data =
        \\
        \\import helper
        \\
        \\func main() -> i64:
        \\    return helper.answer()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.selka", .data =
        \\
        \\
        \\public func answer() -> i64:
        \\    return 7
    });
    const entry = try temp.dir.realPathFileAlloc(testing.io, "app/main.selka", testing.allocator);
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.selka", .data =
        \\
        \\
        \\public func answer() -> i64:
        \\    return 8
    });
    const edited = try projectCacheCheck(entry, cache_argument, 0);
    try testing.expectEqual(@as(usize, 1), edited.syntax_hits);
    try testing.expectEqual(@as(usize, 1), edited.syntax_misses);
    try testing.expectEqual(@as(usize, 0), edited.verdict_hits);
    try testing.expect(edited.verdict_misses >= 1);

    // A rejected edit can never inherit the earlier successful verdict. The
    // failure is reported and the cache is not consulted again for this content.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.selka", .data =
        \\
        \\
        \\public func answer() -> i64:
        \\    return True
    });
    const broken = try projectCacheCheck(entry, cache_argument, 1);
    try testing.expectEqual(@as(usize, 0), broken.verdict_hits);

    // Repair the source so the final no-cache run is a successful check.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.selka", .data =
        \\
        \\
        \\public func answer() -> i64:
        \\    return 8
    });

    // `--no-cache` opens no cache at all, so it emits no reuse receipt and the
    // stored successful verdict for the same content is not consulted.
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "check-project", entry, "--report", "--no-cache" });
    const uncached = try std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
    defer testing.allocator.free(uncached.stdout);
    defer testing.allocator.free(uncached.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, uncached.term);
    try testing.expect(std.mem.indexOf(u8, uncached.stderr, "frontend-cache-v1") == null);
}

// spec: CAPABILITY-DIAG-1
test "multiple missing capabilities report exactly one identical diagnostic" {
    const program =
        \\func main(fs: Filesystem, env: Environment) -> int:
        \\    _ = fs
        \\    _ = env
        \\    return 0
    ;
    const message = "selka: --restrict is active and this command line did not grant a capability the entry point requests; pass --allow-read=DIR or --allow-write=DIR, or drop --restrict to grant every capability; or, if the program can run without it, declare the parameter optional (`fs: Filesystem?`)\n";
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "cap.selka", .data = program });
    const path = try temp.dir.realPathFileAlloc(testing.io, "cap.selka", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "cap-bin" });
    defer testing.allocator.free(output);

    var run_argv: std.ArrayList([]const u8) = .empty;
    defer run_argv.deinit(testing.allocator);
    try run_argv.appendSlice(testing.allocator, &.{ compilerPath(), "run", path, "--restrict" });
    try run_argv.appendSlice(testing.allocator, &tools);
    const run = try std.process.run(testing.allocator, testing.io, .{ .argv = run_argv.items });
    defer testing.allocator.free(run.stdout);
    defer testing.allocator.free(run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, run.term);
    try testing.expectEqualStrings("", run.stdout);
    try testing.expectEqualStrings(message, run.stderr);

    var build_argv: std.ArrayList([]const u8) = .empty;
    defer build_argv.deinit(testing.allocator);
    try build_argv.appendSlice(testing.allocator, &.{ compilerPath(), "build", path, "--run", "--restrict" });
    try build_argv.appendSlice(testing.allocator, &tools);
    const build = try std.process.run(testing.allocator, testing.io, .{ .argv = build_argv.items });
    defer testing.allocator.free(build.stdout);
    defer testing.allocator.free(build.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, build.term);
    try testing.expectEqualStrings("", build.stdout);
    try testing.expectEqualStrings(message, build.stderr);

    var link_argv: std.ArrayList([]const u8) = .empty;
    defer link_argv.deinit(testing.allocator);
    try link_argv.appendSlice(testing.allocator, &.{ compilerPath(), "build", path, "-o", output });
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
        \\func main(args: str[]) -> int:
        \\    return len(args)
    ;
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "args.selka", .data = program });
    const path = try temp.dir.realPathFileAlloc(testing.io, "args.selka", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "args-bin" });
    defer testing.allocator.free(output);
    var guest: [260][]const u8 = @splat("x");

    var run_argv: std.ArrayList([]const u8) = .empty;
    defer run_argv.deinit(testing.allocator);
    try run_argv.appendSlice(testing.allocator, &.{ compilerPath(), "run", path });
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
    try build_argv.appendSlice(testing.allocator, &.{ compilerPath(), "build", path, "--run" });
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
    try link_argv.appendSlice(testing.allocator, &.{ compilerPath(), "build", path, "-o", output });
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
// migrate-embedded: skip preserved legacy provider/diagnostic source
const named_constraint_contracts =
    \\
    \\
    \\public constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
;
const modern_named_constraint_contracts =
    \\
    \\
    \\public record Prices:
    \\    pass
;
// migrate-embedded: skip preserved legacy provider/diagnostic source
const named_constraint_checkout =
    \\import contracts
    \\
    \\
    \\public func total[P: contracts.Prices](policy: P, subtotal: int) -> int effects():
    \\    return P.price(policy, subtotal) + 500
;
const modern_named_constraint_checkout =
    \\import contracts
    \\
    \\
    \\public func total[P: copy](policy: P, subtotal: int, price: func(P, int) -> int) -> int:
    \\    return price(policy, subtotal) + 500
;
// migrate-embedded: skip preserved legacy provider/diagnostic source
const named_constraint_fakes =
    \\
    \\
    \\public domain FixedPrices: int:
    \\    func make(amount: int) -> FixedPrices effects():
    \\        return wrap[FixedPrices](amount)
    \\
    \\    func price(policy: FixedPrices, subtotal: int) -> int effects():
    \\        _ = subtotal
    \\        return unwrap(policy)
;
const modern_named_constraint_fakes =
    \\
    \\
    \\public record FixedPrices:
    \\    value: int
    \\public func make(amount: int) -> FixedPrices:
    \\    return FixedPrices(value=amount)
    \\
    \\public func price(policy: FixedPrices, subtotal: int) -> int:
    \\    _ = subtotal
    \\    return policy.value
;
const modern_named_constraint_fake_tests =
    \\import checkout
    \\import fakes
    \\
    \\
    \\func main() -> int:
    \\    assert test_checkout()
    \\    return 0
    \\
    \\
    \\public func test_checkout() -> bool:
    \\    return checkout.total(fakes.make(1750), 2000, fakes.price) == 2250
;
// migrate-embedded: skip preserved legacy provider/diagnostic source
const named_constraint_production_invalid =
    \\import contracts
    \\
    \\
    \\public domain DiscountPrices: int:
    \\    func make(discount: int) -> DiscountPrices effects():
    \\        return wrap[DiscountPrices](discount)
    \\
    \\    func price(policy: DiscountPrices, subtotal: int) -> int effects():
    \\        return missing_name(policy, subtotal)
;
// migrate-embedded: skip preserved legacy provider/diagnostic source
const named_constraint_main =
    \\import checkout
    \\import production
    \\
    \\
    \\func main() -> int:
    \\    mut real = production.DiscountPrices.make(250)
    \\    assert checkout.total(real, 2000) == 2250
    \\    return 0
;

const modern_named_constraint_production_invalid =
    \\import contracts
    \\public record DiscountPrices:
    \\    value: int
    \\public func make(discount: int) -> DiscountPrices:
    \\    return DiscountPrices(value=discount)
    \\public func price(policy: DiscountPrices, subtotal: int) -> int:
    \\    return missing_name(policy, subtotal)
;
const modern_named_constraint_main =
    \\import checkout
    \\import production
    \\func main() -> int:
    \\    mut real = production.make(250)
    \\    assert checkout.total(real, 2000, production.price) == 2250
    \\    return 0
;

fn acceptNamedConstraintFake(testing_: *std.testing.TmpDir, allocator: std.mem.Allocator) !void {
    const entry = try testing_.dir.realPathFileAlloc(testing.io, "fake_tests.selka", allocator);
    defer allocator.free(entry);
    const result = try privateRun(allocator, &.{ compilerPath(), "test", entry, "--filter", "test_checkout" });
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "contracts.selka", .data = modern_named_constraint_contracts });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "checkout.selka", .data = modern_named_constraint_checkout });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "fakes.selka", .data = modern_named_constraint_fakes });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "fake_tests.selka", .data = modern_named_constraint_fake_tests });
    try acceptNamedConstraintFake(&temp, testing.allocator);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "production.selka", .data = named_constraint_production_invalid });
    try acceptNamedConstraintFake(&temp, testing.allocator);
    // Keep the deliberate legacy production diagnostic graph unchanged.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "contracts.selka", .data = named_constraint_contracts });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "checkout.selka", .data = named_constraint_checkout });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = named_constraint_main });
    const main_path = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(main_path);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "run", main_path });
    try args.appendSlice(testing.allocator, &tools);
    const rejected = try std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
    defer testing.allocator.free(rejected.stdout);
    defer testing.allocator.free(rejected.stderr);
    try testing.expect(rejected.term != .exited or rejected.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, rejected.stderr, "E_EFFECTS_REMOVED") != null);
    // The original graph remains an executable retirement witness. Modern
    // declarations still ignore an unselected bad body and reject it when reached.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "contracts.selka", .data = modern_named_constraint_contracts });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "checkout.selka", .data = modern_named_constraint_checkout });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "production.selka", .data = modern_named_constraint_production_invalid });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = modern_named_constraint_main });
    try acceptNamedConstraintFake(&temp, testing.allocator);
    const modern_rejected = try std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
    defer testing.allocator.free(modern_rejected.stdout);
    defer testing.allocator.free(modern_rejected.stderr);
    try testing.expect(modern_rejected.term != .exited or modern_rejected.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, modern_rejected.stderr, "E_UNKNOWN_SYMBOL") != null);
    try testing.expect(std.mem.indexOf(u8, modern_rejected.stderr, "missing_name") != null);
}

const named_probes = @import("named_constraints_probes.zig");
fn runNamedConstraintProbe(allocator: std.mem.Allocator, probe: named_probes.Probe) !void {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    for (probe.files) |file| try temp.dir.writeFile(testing.io, .{ .sub_path = file.name, .data = file.body });
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", allocator);
    defer allocator.free(entry);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(allocator);
    try args.appendSlice(allocator, &.{ compilerPath(), probe.command, entry });
    if (std.mem.eql(u8, probe.command, "check-project")) try args.append(allocator, "--no-cache");
    const result = try std.process.run(allocator, testing.io, .{ .argv = args.items });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (probe.expect_success) {
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    } else {
        try testing.expect(result.term != .exited or result.term.exited != 0);
        if (probe.diagnostic.len != 0) try testing.expect(std.mem.indexOf(u8, result.stderr, probe.diagnostic) != null);
        if (probe.diagnostic_detail.len != 0) try testing.expect(std.mem.indexOf(u8, result.stderr, probe.diagnostic_detail) != null);
    }
}

fn runNamedConstraintProbes(allocator: std.mem.Allocator) !void {
    for (named_probes.probes) |probe| try runNamedConstraintProbe(allocator, probe);
}

// The named-constraints review repros stay executable: imported export identity,
// declaration-scoped type resolution, identity-based merging, implied copy,
// spec: NEW-CORE-S5-ONE-BINARY-1
test "selka build answers the core's developer switches as selka-core did" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "func main(out: Stream) -> int:\n    print(out, 6 * 7)\n    return 0\n" });
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
    defer testing.allocator.free(compiler);
    const built = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "build", "main.selka", "-o", "program", "--generic-vectors", "--trap-frames=posix_exit", "--cache-dir", "cache", "--zig", @import("test_options").zig_path },
        .cwd = .{ .dir = temporary.dir },
    });
    defer testing.allocator.free(built.stdout);
    defer testing.allocator.free(built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const program = try std.fs.path.join(testing.allocator, &.{ root, "program" });
    defer testing.allocator.free(program);
    try expectConstantProcess(&.{program}, "42\n");
    // The core's build takes no `--run`: the switch is a usage error there.
    const refused = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "build", "main.selka", "--run", "--generic-vectors" },
        .cwd = .{ .dir = temporary.dir },
    });
    defer testing.allocator.free(refused.stdout);
    defer testing.allocator.free(refused.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, refused.term);
}

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
const policy_project_main = "import helper\nfunc main() -> int:\n    return helper.value()\n";
const policy_project_helper = "public func value() -> int:\n    return 7\n";

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "loadConfiguredPolicy enforces selka.json across ordinary project commands cold warm and after policy-only edits" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.selka", policy_project_main);
    try writeProjectFile(&temp, "helper.selka", policy_project_helper);
    try writeProjectFile(&temp, "selka.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "policy.json", policy_deny);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
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
        const denied = try runCompiler(testing.allocator, &.{ compilerPath(), "check-project", entry, cache_argument });
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
    try build_args.appendSlice(testing.allocator, &.{ compilerPath(), "build", entry, "--project", "-o", output, cache_argument });
    try build_args.appendSlice(testing.allocator, &tools);
    const built = try runCompiler(testing.allocator, build_args.items);
    defer testing.allocator.free(built.stdout);
    defer testing.allocator.free(built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, built.term);

    var run_args: std.ArrayList([]const u8) = .empty;
    defer run_args.deinit(testing.allocator);
    try run_args.appendSlice(testing.allocator, &.{ compilerPath(), "run-project", entry, "--print-result", cache_argument });
    try run_args.appendSlice(testing.allocator, &tools);
    const run_denied = try runCompiler(testing.allocator, run_args.items);
    defer testing.allocator.free(run_denied.stdout);
    defer testing.allocator.free(run_denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, run_denied.term);
    try testing.expectEqualStrings("", run_denied.stdout);

    // Explicit `check-policy` inspection keeps working and names its own policy.
    const explicit = try runCompiler(testing.allocator, &.{ compilerPath(), "check-policy", entry, explicit_policy });
    defer testing.allocator.free(explicit.stdout);
    defer testing.allocator.free(explicit.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, explicit.term);
    try testing.expect(std.mem.indexOf(u8, explicit.stdout, "import-direction-v1: failed") != null);

    // A policy-only edit flips acceptance; the earlier deny never wrote a pass.
    try writeProjectFile(&temp, "policy.json", policy_allow);
    for (0..2) |_| {
        const allowed = try runCompiler(testing.allocator, &.{ compilerPath(), "check-project", entry, cache_argument });
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
    const stricter = try runCompiler(testing.allocator, &.{ compilerPath(), "check-project", entry, cache_argument });
    defer testing.allocator.free(stricter.stdout);
    defer testing.allocator.free(stricter.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, stricter.term);
    try testing.expect(std.mem.indexOf(u8, stricter.stderr, "main -> helper: deny") != null);
}

// spec-case: POLICY-IDENTITY-OWNED-1
test "loadConfiguredPolicy keeps a configured project's warm verdicts replayable on disk and in a session" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.selka", policy_project_main);
    try writeProjectFile(&temp, "helper.selka", policy_project_helper);
    try writeProjectFile(&temp, "selka.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "policy.json", policy_allow);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);

    // The identity used to be sliced from a returned frame, so the warm key
    // hashed whatever later calls wrote there and never matched the stored one.
    const cold = try projectCacheCheck(entry, cache_argument, 0);
    try testing.expectEqual(@as(usize, 0), cold.verdict_hits);
    const warm = try projectCacheCheck(entry, cache_argument, 0);
    try testing.expectEqual(@as(usize, 1), warm.verdict_hits);
    try testing.expectEqual(@as(usize, 0), warm.verdict_misses);

    // The session's in-memory verdict compares the same identity on its next check.
    try writeProjectFile(&temp, "commands", "check\ncheck\nquit\n");
    const input = try temp.dir.openFile(testing.io, "commands", .{});
    defer input.close(testing.io);
    const output = try temp.dir.createFile(testing.io, "replies", .{});
    defer output.close(testing.io);
    var child = try std.process.spawn(testing.io, .{ .argv = &.{ compilerPath(), "check-session", entry }, .stdin = .{ .file = input }, .stdout = .{ .file = output }, .stderr = .ignore });
    defer child.kill(testing.io);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try child.wait(testing.io));
    const replies = try temp.dir.readFileAlloc(testing.io, "replies", testing.allocator, .limited(16384));
    defer testing.allocator.free(replies);
    try testing.expect(std.mem.indexOf(u8, replies, "\"semantic\":{\"hits\":1,\"misses\":1") != null);
    try testing.expect(std.mem.indexOf(u8, replies, "\"status\":1") == null);
}

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "loadConfiguredPolicy policy discovery anchors to the entry file instead of the shell working directory" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "entry/main.selka", policy_project_main);
    try writeProjectFile(&temp, "entry/helper.selka", policy_project_helper);
    try writeProjectFile(&temp, "entry/selka.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "entry/policy.json", policy_deny);
    try writeProjectFile(&temp, "elsewhere/main.selka", "func main() -> int:\n    return 0\n");
    try writeProjectFile(&temp, "elsewhere/selka.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "elsewhere/policy.json", policy_allow);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "entry/main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    var elsewhere = try temp.dir.openDir(testing.io, "elsewhere", .{ .iterate = false });
    defer elsewhere.close(testing.io);
    // The child runs from another directory, so the compiler must name itself absolutely.
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
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
    try writeProjectFile(&temp, "main.selka", "import helper\nfunc main() -> int:\n    return helper.value()\n");
    try writeProjectFile(&temp, "helper.selka", "import main\npublic func value() -> int:\n    return 0\n");
    try writeProjectFile(&temp, "selka.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    for ([_][]const u8{ policy_allow, policy_deny }) |body| {
        try writeProjectFile(&temp, "policy.json", body);
        const result = try runCompiler(testing.allocator, &.{ compilerPath(), "check-project", entry });
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
    try writeProjectFile(&temp, "main.selka", policy_project_main);
    try writeProjectFile(&temp, "helper.selka", policy_project_helper);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);

    const malformed = [_][]const u8{
        "{\"version\":1,\"import_policy\":\"absent.json\"}",
        "{\"version\":2,\"import_policy\":\"policy.json\"}",
        "{\"version\":1,\"typo\":true}",
        "not json at all",
    };
    for (malformed) |body| {
        try writeProjectFile(&temp, "selka.json", body);
        const result = try runCompiler(testing.allocator, &.{ compilerPath(), "check-project", entry });
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
    try writeProjectFile(&temp, "main.selka", policy_project_main);
    try writeProjectFile(&temp, "helper.selka", policy_project_helper);
    try writeProjectFile(&temp, "selka.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "policy.json", policy_deny);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);

    const denied = try runCompiler(testing.allocator, &.{ compilerPath(), "check-project", entry });
    defer testing.allocator.free(denied.stdout);
    defer testing.allocator.free(denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, denied.term);
    try testing.expect(std.mem.indexOf(u8, denied.stderr, "main -> helper: deny") != null);

    try writeProjectFile(&temp, "selka.json", "{");
    const malformed = try runCompiler(testing.allocator, &.{ compilerPath(), "check-project", entry });
    defer testing.allocator.free(malformed.stdout);
    defer testing.allocator.free(malformed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, malformed.term);
    try testing.expect(std.mem.indexOf(u8, malformed.stderr, "E_PROJECT_CONFIG") != null);
}

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "loadConfiguredPolicy policy applies to native test preparation ProjectConfigurationFailed and ProjectPolicyRejected" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "tests.selka",
        \\import helper
        \\
        \\
        \\func main() -> int:
        \\    return 0
        \\
        \\
        \\public func test_policy() -> bool:
        \\    return helper.value() == 7
    );
    try writeProjectFile(&temp, "helper.selka", "public func value() -> int:\n    return 7\n");
    try writeProjectFile(&temp, "selka.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "policy.json", policy_allow);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "tests.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "test-cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);

    const allowed = try privateRun(testing.allocator, &.{ compilerPath(), "test", entry, "--filter", "test_policy", cache_argument });
    defer testing.allocator.free(allowed.stdout);
    defer testing.allocator.free(allowed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, allowed.term);
    try testing.expect(std.mem.indexOf(u8, allowed.stdout, "test_policy") != null);

    try writeProjectFile(&temp, "policy.json", policy_deny);
    const denied = try privateRun(testing.allocator, &.{ compilerPath(), "test", entry, "--filter", "test_policy", cache_argument });
    defer testing.allocator.free(denied.stdout);
    defer testing.allocator.free(denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, denied.term);
    try testing.expect(std.mem.indexOf(u8, denied.stderr, "tests -> helper: deny") != null);

    try writeProjectFile(&temp, "selka.json", "{");
    const malformed = try privateRun(testing.allocator, &.{ compilerPath(), "test", entry, "--filter", "test_policy", cache_argument });
    defer testing.allocator.free(malformed.stdout);
    defer testing.allocator.free(malformed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, malformed.term);
    try testing.expect(std.mem.indexOf(u8, malformed.stderr, "E_PROJECT_CONFIG") != null);
}

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "validateUnitConfiguredPolicy checks required configuration for single-unit commands" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.selka", "func main() -> int:\n    return 0\n");
    try writeProjectFile(&temp, "selka.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "policy.json", policy_deny);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);

    // A unit has no import edges, so a well-formed policy is satisfied.
    const allowed = try runCompiler(testing.allocator, &.{ compilerPath(), "check", entry });
    defer testing.allocator.free(allowed.stdout);
    defer testing.allocator.free(allowed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, allowed.term);

    try writeProjectFile(&temp, "selka.json", "{\"version\":1,\"import_policy\":\"absent.json\"}");
    const missing = try runCompiler(testing.allocator, &.{ compilerPath(), "check", entry });
    defer testing.allocator.free(missing.stdout);
    defer testing.allocator.free(missing.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, missing.term);
    try testing.expect(std.mem.indexOf(u8, missing.stderr, "E_PROJECT_CONFIG") != null);

    try writeProjectFile(&temp, "selka.json", "not json");
    const malformed = try runCompiler(testing.allocator, &.{ compilerPath(), "check", entry });
    defer testing.allocator.free(malformed.stdout);
    defer testing.allocator.free(malformed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, malformed.term);
    try testing.expect(std.mem.indexOf(u8, malformed.stderr, "E_PROJECT_CONFIG") != null);
}

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "loadConfiguredPolicy policy discovery above the native test entry enforces the ancestor config" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "nested/tests.selka",
        \\import helper
        \\
        \\
        \\func main() -> int:
        \\    return 0
        \\
        \\
        \\public func test_policy() -> bool:
        \\    return helper.value() == 7
    );
    try writeProjectFile(&temp, "helper.selka", "public func value() -> int:\n    return 7\n");
    try writeProjectFile(&temp, "selka.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "policy.json", policy_deny);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "nested/tests.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "test-cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);

    const denied = try privateRun(testing.allocator, &.{ compilerPath(), "test", entry, "--filter", "test_policy", cache_argument });
    defer testing.allocator.free(denied.stdout);
    defer testing.allocator.free(denied.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, denied.term);
    try testing.expect(std.mem.indexOf(u8, denied.stderr, "tests -> helper: deny") != null);
}

// spec-case: REQUIRED-PROJECT-IMPORT-POLICY-1
test "loadConfiguredPolicy policy identity participates in project-dependencies receipts" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.selka", policy_project_main);
    try writeProjectFile(&temp, "helper.selka", policy_project_helper);
    try writeProjectFile(&temp, "selka.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "policy.json", policy_allow);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "receipt-cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);

    const first = try runCompiler(testing.allocator, &.{ compilerPath(), "project-dependencies", entry, cache_argument });
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    try testing.expect(std.mem.indexOf(u8, first.stdout, "\"policy\"") != null);
    try testing.expect(std.mem.indexOf(u8, first.stdout, "\"config_sha256\"") != null);

    try writeProjectFile(&temp, "policy.json", "{\"version\":1,\"default_action\":\"deny\",\"rules\":[]}");
    const second = try runCompiler(testing.allocator, &.{ compilerPath(), "project-dependencies", entry, cache_argument });
    defer testing.allocator.free(second.stdout);
    defer testing.allocator.free(second.stderr);
    // A stricter policy denies the ordinary receipt command before it can be
    // produced, which is the acceptance-relevant identity change.
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, second.term);
    try testing.expect(std.mem.indexOf(u8, second.stderr, "main -> helper: deny") != null);
}

// spec: MUTATION-ENFORCE-1
test "CLI migrated corpus projects carry the checked mutation contract" {
    // The corpus pieces M3 repaired: domain methods exposed through an exported
    // type, a generated input accessor and guest tests that allocate. Every one
    // needs an explicit, narrow ceiling.
    for ([_][]const u8{
        "examples/modules/main.selka",
        "examples/input-values/main.selka",
        "tests/guest/generics.selka",
    }) |entry| {
        const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check-project", entry } });
        defer testing.allocator.free(outcome.stdout);
        defer testing.allocator.free(outcome.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    }
}

// spec-case: MUTATION-ENFORCE-1
test "CLI nested record alias rejects under effects and runs with a mutation footprint" {
    // migrate-embedded: skip -- exact original effect-clause rejection witness.
    const rejected =
        \\record Box:
        \\    values: int[]
        \\
        \\
        \\func overwrite(mut box: Box) -> Unit effects():
        \\    box.values[0] = 7
        \\
        \\
        \\func main() -> int:
        \\    mut box = Box(values=[1])
        \\    overwrite(mut box)
        \\    return box.values[0]
    ;
    try invoke("check", rejected, 1, "", "E_EFFECTS_REMOVED");
    const permitted =
        \\record Box:
        \\    values: int[]
        \\
        \\
        \\func overwrite(mut box: Box) -> Unit:
        \\    box.values[0] = 7
        \\
        \\
        \\func main() -> int:
        \\    mut box = Box(values=[1])
        \\    overwrite(mut box)
        \\    return box.values[0]
    ;
    // The live mutation boundary is readonly versus explicit mut authority.
    const readonly = try std.mem.replaceOwned(u8, testing.allocator, permitted, "overwrite(mut box", "overwrite(box");
    defer testing.allocator.free(readonly);
    try invoke("check", readonly, 1, "", "E_IMMUTABLE");
    try invoke("run", permitted, 0, "7\n", "");
}

// spec-case: MUT-PARAM-5
test "CLI the mut spelling checks and runs while the removed flag is rejected" {
    try invokeOptions("check", @embedFile("fixtures/mutation-markers.selka"), &.{}, 0, "", "");
    try invokeOptions("run", @embedFile("fixtures/mutation-markers.selka"), &.{}, 0, "8\n", "");
    try invokeOptions("check", @embedFile("fixtures/mutation-markers.selka"), &.{"--mutation-markers"}, 2, "", "--mutation-markers was removed");
}

// --- P1: selected test providers validated against declared contracts ---

// migrate-embedded: skip preserved legacy provider/diagnostic source
const p1_production_unfinished =
    \\
    \\
    \\public domain Stub: int:
    \\    func make(discount: int) -> Stub effects():
    \\        return wrap[Stub](discount)
    \\
    \\    func price(policy: Stub, mut ledger: int[], rates: int[], subtotal: int) -> int effects(mutation):
    \\        return todo[int]()
;
const modern_p1_production_unfinished =
    \\
    \\
    \\public record Stub:
    \\    value: int
    \\public func make(discount: int) -> Stub:
    \\    return Stub(value=discount)
    \\
    \\public func price(policy: Stub, mut ledger: int[], rates: int[], subtotal: int) -> int:
    \\    return todo[int]()
;
/// Original production with its retired effect ceiling, preserved for diagnostics.
// migrate-embedded: skip preserved legacy provider/diagnostic source
const p1_production_allocating =
    \\
    \\
    \\public domain Stub: int:
    \\    func make(discount: int) -> Stub effects():
    \\        return wrap[Stub](discount)
    \\
    \\    func price(policy: Stub, mut ledger: int[], rates: int[], subtotal: int) -> int effects(mutation, managed_allocation):
    \\        return todo[int]()
;
const modern_p1_production_allocating =
    \\
    \\
    \\public record Stub:
    \\    value: int
    \\public func make(discount: int) -> Stub:
    \\    return Stub(value=discount)
    \\
    \\public func price(policy: Stub, mut ledger: int[], rates: int[], subtotal: int) -> int:
    \\    return todo[int]()
;
// migrate-embedded: skip preserved legacy provider/diagnostic source
const p1_production_bad_interface =
    \\
    \\
    \\public domain Stub: int:
    \\    func make(discount: int) -> Stub effects():
    \\        return wrap[Stub](discount)
    \\
    \\    func price(policy: Stub, ledger: int[], rates: int[], subtotal: int) -> int effects():
    \\        return subtotal
;
const modern_p1_production_bad_interface =
    \\
    \\
    \\public record Stub:
    \\    value: int
    \\public func make(discount: int) -> Stub:
    \\    return Stub(value=discount)
    \\
    \\public func price(policy: Stub, ledger: int[], rates: int[], subtotal: int) -> int:
    \\    return subtotal
;
const modern_p1_main =
    \\import production
    \\
    \\
    \\func main() -> int:
    \\    return 0
    \\
    \\
    \\public func test_checkout() -> bool:
    \\    mut policy = production.make(250)
    \\    mut ledger: int[] = [0]
    \\    mut rates: int[] = [0]
    \\    return production.price(policy, mut ledger, rates, 2000) == 1750
;
/// A replacement `production.Stub.price` whose managed parameters, effect
/// clause and first body line vary; `ledger` is the production footprint.
fn legacyP1Fake(parameters: []const u8, perm: []const u8, body: []const u8) ![]const u8 {
    return std.fmt.allocPrint(
        testing.allocator,
        "public domain Stub: int:\n" ++
            "    func make(discount: int) -> Stub effects():\n        return wrap[Stub](discount)\n\n" ++
            "    func price(policy: Stub, {s}, subtotal: int) -> int {s}:\n        {s}\n        return subtotal - unwrap(policy)\n",
        .{ parameters, perm, body },
    );
}
fn p1Fake(parameters: []const u8, perm: []const u8, body: []const u8) ![]const u8 {
    _ = perm;
    return std.fmt.allocPrint(
        testing.allocator,
        "public record Stub:\n    value: int\n\n" ++
            "public func make(discount: int) -> Stub:\n    return Stub(value=discount)\n\n" ++
            "public func price(policy: Stub, {s}, subtotal: int) -> int:\n        {s}\n        return subtotal - policy.value\n",
        .{ parameters, body },
    );
}
fn p1Replace(allocator: std.mem.Allocator, source: []const u8, from: []const u8, to: []const u8) ![]u8 {
    try testing.expect(std.mem.indexOf(u8, source, from) != null);
    const changed = try std.mem.replaceOwned(u8, allocator, source, from, to);
    errdefer allocator.free(changed);
    try testing.expect(!std.mem.eql(u8, source, changed));
    return changed;
}
/// The production footprint: `ledger` written, `rates` read-only.
const p1_footprint = "mut ledger: int[], rates: int[]";
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
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "test", entry, "--filter", "test_checkout", "--json", cache_arg });
    if (cases_path) |path| try args.appendSlice(testing.allocator, &.{ "--cases", path });
    try args.appendSlice(testing.allocator, &tools);
    return privateRun(testing.allocator, args.items);
}

// spec: NATIVE-TEST-5
test "P1 selects a validated fake while the unfinished production body is never checked" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.selka", modern_p1_main);
    try writeProjectFile(&temp, "production.selka", modern_p1_production_unfinished);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const cases_path = try std.fs.path.join(testing.allocator, &.{ root, "cases.json" });
    defer testing.allocator.free(cases_path);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);

    const fake = try p1Fake(p1_footprint, "effects(mutation)", p1_write);
    defer testing.allocator.free(fake);
    try p1WriteCases(&temp, "cases.json", "production.selka", fake);

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
    const mutated = try p1Replace(testing.allocator, changed, "return subtotal - policy.value", "return subtotal - policy.value + 1");
    defer testing.allocator.free(mutated);
    try p1WriteCases(&temp, "cases.json", "production.selka", mutated);
    const edited = try p1Invoke(entry, cases_path, cache);
    defer testing.allocator.free(edited.stdout);
    defer testing.allocator.free(edited.stderr);
    try testing.expect(std.mem.indexOf(u8, edited.stdout, "\"cached\":0") != null);
    try testing.expect(std.mem.indexOf(u8, edited.stdout, "\"failed\":1") != null);

    // A full production test run reaches the unfinished body and traps at its hole (a debug run keeps holes as
    // traps), and a strict check still refuses the body.
    const full = try p1Invoke(entry, null, cache);
    defer testing.allocator.free(full.stdout);
    defer testing.allocator.free(full.stderr);
    try testing.expect(full.term != .exited or full.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, full.stdout, "R_TYPED_HOLE") != null or std.mem.indexOf(u8, full.stderr, "R_TYPED_HOLE") != null);
    const checked = try privateRun(testing.allocator, &.{ compilerPath(), "check", entry });
    defer testing.allocator.free(checked.stdout);
    defer testing.allocator.free(checked.stderr);
    try testing.expect(checked.term != .exited or checked.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, checked.stderr, "E_TYPED_HOLE") != null);
}

test "P1 rejects stronger or malformed replacements and a bad production interface" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.selka", modern_p1_main);
    try writeProjectFile(&temp, "production.selka", modern_p1_production_allocating);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const cases_path = try std.fs.path.join(testing.allocator, &.{ root, "cases.json" });
    defer testing.allocator.free(cases_path);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);

    // A replacement with the same managed-parameter footprint is accepted.
    const narrow = try p1Fake(p1_footprint, "effects(mutation)", p1_write);
    defer testing.allocator.free(narrow);
    try p1WriteCases(&temp, "cases.json", "production.selka", narrow);
    const accepted = try p1Invoke(entry, cases_path, cache);
    defer testing.allocator.free(accepted.stdout);
    defer testing.allocator.free(accepted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, accepted.term);

    // The `mut` footprint is part of the signature every caller writes against
    // (`price(policy, mut ledger, rates, ...)`), so a replacement may neither
    // drop a `mut` nor add one.
    for ([_][2][]const u8{
        .{ "ledger: int[], rates: int[]", "_ = subtotal" },
        .{ "mut ledger: int[], mut rates: int[]", "ledger[0] = subtotal\n        rates[0] = subtotal" },
    }) |footprint| {
        const changed = try p1Fake(footprint[0], "effects(mutation)", footprint[1]);
        defer testing.allocator.free(changed);
        try p1WriteCases(&temp, "cases.json", "production.selka", changed);
        const rejected = try p1Invoke(entry, cases_path, cache);
        defer testing.allocator.free(rejected.stdout);
        defer testing.allocator.free(rejected.stderr);
        try testing.expect(rejected.term != .exited or rejected.term.exited != 0);
        try testing.expect(std.mem.indexOf(u8, rejected.stderr, "IncompatibleProvider") != null);
    }

    // An unknown replacement path rejects without touching a production body.
    try p1WriteCases(&temp, "cases.json", "nope.selka", narrow);
    const unknown = try p1Invoke(entry, cases_path, cache);
    defer testing.allocator.free(unknown.stdout);
    defer testing.allocator.free(unknown.stderr);
    try testing.expect(unknown.term != .exited or unknown.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, unknown.stderr, "InvalidTestProviders") != null);

    // A changed production footprint rejects a provider built for the earlier interface.
    try writeProjectFile(&temp, "production.selka", modern_p1_production_bad_interface);
    try p1WriteCases(&temp, "cases.json", "production.selka", narrow);
    const interface_error = try p1Invoke(entry, cases_path, cache);
    defer testing.allocator.free(interface_error.stdout);
    defer testing.allocator.free(interface_error.stderr);
    try testing.expect(interface_error.term != .exited or interface_error.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, interface_error.stderr, "IncompatibleProvider") != null);
}

// spec-case: EFFECTS-REMOVED-1
test "P1 preserves the original wider replacement effect clause as a removal diagnostic" {
    // migrate-embedded: skip preserved original dynamic legacy provider source
    const variants = [_]struct { label: []const u8, from: []const u8, to: []const u8 }{
        .{ .label = "effects too wide", .from = "effects(mutation)", .to = "effects(mutation, managed_allocation)" },
    };
    for (variants) |variant| {
        const base = try legacyP1Fake(p1_footprint, variant.from, p1_write);
        defer testing.allocator.free(base);
        const widened = try p1Replace(testing.allocator, base, variant.from, variant.to);
        defer testing.allocator.free(widened);
        try invoke("check-module", widened, 1, "", "error[E_EFFECTS_REMOVED]");
    }
}

test "P1 rejects every incompatible replacement dimension" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.selka", modern_p1_main);
    try writeProjectFile(&temp, "production.selka", modern_p1_production_unfinished);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
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
        .{ .label = "generic requirement", .from = "func price(policy:", .to = "func price[T: copy](policy:" },
        .{ .label = "return type", .from = "subtotal: int) -> int", .to = "subtotal: int) -> bool" },
    };
    for (variants) |variant| {
        const changed = try p1Replace(testing.allocator, base, variant.from, variant.to);
        defer testing.allocator.free(changed);
        try p1WriteCases(&temp, "cases.json", "production.selka", changed);
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

test "P1 ignores an unselected production body type error while its declarations stay valid" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    // migrate-embedded: skip intentional legacy production body type-error oracle
    const production_body_error =
        \\
        \\
        \\public domain Stub: int:
        \\    func make(discount: int) -> Stub effects():
        \\        return wrap[Stub](discount)
        \\
        \\    func price(policy: Stub, mut ledger: int[], rates: int[], subtotal: int) -> int effects(mutation):
        \\        return True
    ;
    _ = production_body_error;
    const modern_production_body_error =
        \\
        \\
        \\public record Stub:
        \\    value: int
        \\public func make(discount: int) -> Stub:
        \\    return Stub(value=discount)
        \\
        \\public func price(policy: Stub, mut ledger: int[], rates: int[], subtotal: int) -> int:
        \\    return True
    ;
    try writeProjectFile(&temp, "main.selka", modern_p1_main);
    try writeProjectFile(&temp, "production.selka", modern_production_body_error);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const cases_path = try std.fs.path.join(testing.allocator, &.{ root, "cases.json" });
    defer testing.allocator.free(cases_path);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);

    const fake = try p1Fake(p1_footprint, "effects(mutation)", p1_write);
    defer testing.allocator.free(fake);
    try p1WriteCases(&temp, "cases.json", "production.selka", fake);
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
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "test", entry, "--json", cache_arg });
    if (cases_path) |path| try args.appendSlice(testing.allocator, &.{ "--cases", path });
    try args.appendSlice(testing.allocator, &tools);
    return privateRun(testing.allocator, args.items);
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
    \\
    \\
    \\public type Truth = bool
    \\public type Count = int
    \\public type Counts = FixedArray[Count, 2]
    \\public record Pair[T]:
    \\    left: T
    \\    right: T
    \\public type Chosen = Pair[Count]
    \\
    \\
    \\public func size(values: Counts) -> Count:
    \\    return values[0] + values[1]
    \\
    \\
    \\public func pick(value: Chosen) -> Count:
    \\    return value.left
    \\
    \\
    \\public func test_alias() -> Truth:
    \\    return True
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

test "R3 canonical descriptors expand transparent aliases for discovery and nested contracts" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.selka", r3_alias_main);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
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
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "list-interfaces", "--contracts", entry });
    const contracts = try runCompiler(testing.allocator, args.items);
    defer testing.allocator.free(contracts.stdout);
    defer testing.allocator.free(contracts.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, contracts.term);
    try testing.expect(std.mem.indexOf(u8, contracts.stdout, "\"version\":\"interface-contracts-v2\"") != null);
    for ([_][]const u8{
        "{\"name\":\"Count\",\"kind\":\"alias\",\"signature\":\"\",\"generics\":\"\",\"permissions\":\"\",\"shape\":\"target:i64\"}",
        "{\"name\":\"Counts\",\"kind\":\"alias\",\"signature\":\"\",\"generics\":\"\",\"permissions\":\"\",\"shape\":\"target:FixedArray[i64,2]\"}",
        "{\"name\":\"Chosen\",\"kind\":\"alias\",\"signature\":\"\",\"generics\":\"\",\"permissions\":\"\",\"shape\":\"target:main::Pair[i64]\"}",
        "{\"name\":\"size\",\"kind\":\"function\",\"signature\":\"func(values:FixedArray[i64,2])->i64\"",
        "{\"name\":\"pick\",\"kind\":\"function\",\"signature\":\"func(value:main::Pair[i64])->i64\"",
        "{\"name\":\"test_alias\",\"kind\":\"function\",\"signature\":\"func()->bool\"",
    }) |needle| {
        testing.expect(std.mem.indexOf(u8, contracts.stdout, needle) != null) catch |err| {
            std.debug.print("missing canonical contract fragment: {s}\n", .{needle});
            return err;
        };
    }
}

const r3_scalar_main =
    \\import reading
    \\
    \\
    \\public func test_reading() -> bool:
    \\    return reading.sample() == 42
    \\
    \\
    \\func main() -> int:
    \\    return 0
;
const r3_scalar_production =
    \\
    \\
    \\public func sample() -> int:
    \\    return todo[int]()
;
const r3_nominal_main =
    \\import reading
    \\
    \\
    \\public func test_reading() -> bool:
    \\    return True
    \\
    \\
    \\func main() -> int:
    \\    return 0
;
// migrate-embedded: skip preserved legacy provider/diagnostic source
const r3_nominal_production =
    \\
    \\
    \\public domain D: i64:
    \\    func make(x: i64) -> D effects():
    \\        return wrap[D](x)
    \\
    \\
    \\public func sample() -> D effects():
    \\    return todo[D]()
;
const modern_r3_nominal_production =
    \\
    \\
    \\public record D:
    \\    value: i64
    \\public func make_D(x: i64) -> D:
    \\    return D(value=x)
    \\
    \\
    \\public func sample() -> D:
    \\    return todo[D]()
;
// migrate-embedded: skip preserved legacy provider/diagnostic source
const r3_nominal_fake =
    \\
    \\
    \\public domain D: i64:
    \\    func make(x: i64) -> D effects():
    \\        return wrap[D](x)
    \\
    \\
    \\public domain E: i64:
    \\    func make(x: i64) -> E effects():
    \\        return wrap[E](x)
    \\
    \\
    \\public func sample() -> E effects():
    \\    return E.make(1)
;
const modern_r3_nominal_fake =
    \\
    \\
    \\public record D:
    \\    value: i64
    \\public func make_D(x: i64) -> D:
    \\    return D(value=x)
    \\
    \\
    \\public record E:
    \\    value: i64
    \\public func make_E(x: i64) -> E:
    \\    return E(value=x)
    \\
    \\
    \\public func sample() -> E:
    \\    return make_E(1)
;

test "R3 canonical descriptors compare provider scalar and nominal contracts" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try writeProjectFile(&temp, "main.selka", r3_scalar_main);
    try writeProjectFile(&temp, "reading.selka", r3_scalar_production);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const cases_path = try std.fs.path.join(testing.allocator, &.{ root, "cases.json" });
    defer testing.allocator.free(cases_path);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);

    const equivalent =
        \\
        \\
        \\public func sample() -> i64:
        \\    return 42
    ;
    try r3WriteCases(&temp, "cases.json", "main::test_reading", "reading.selka", equivalent);
    const accepted = try r3TestInvoke(entry, cases_path, cache);
    defer testing.allocator.free(accepted.stdout);
    defer testing.allocator.free(accepted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, accepted.term);
    try testing.expect(std.mem.indexOf(u8, accepted.stdout, "\"passed\":1") != null);

    const scalar_variants = [_][]const u8{
        \\
        \\
        \\public func sample() -> u8:
        \\    return 42
        ,
        \\
        \\
        \\public func sample() -> str:
        \\    return "x"
        ,
    };
    for (scalar_variants) |fake| {
        try r3WriteCases(&temp, "cases.json", "main::test_reading", "reading.selka", fake);
        const rejected = try r3TestInvoke(entry, cases_path, cache);
        defer testing.allocator.free(rejected.stdout);
        defer testing.allocator.free(rejected.stderr);
        try testing.expect(rejected.term != .exited or rejected.term.exited != 0);
        try testing.expect(std.mem.indexOf(u8, rejected.stderr, "IncompatibleProvider") != null);
    }

    try writeProjectFile(&temp, "main.selka", r3_nominal_main);
    try writeProjectFile(&temp, "reading.selka", modern_r3_nominal_production);
    try r3WriteCases(&temp, "cases.json", "main::test_reading", "reading.selka", modern_r3_nominal_fake);
    const nominal = try r3TestInvoke(entry, cases_path, cache);
    defer testing.allocator.free(nominal.stdout);
    defer testing.allocator.free(nominal.stderr);
    try testing.expect(nominal.term != .exited or nominal.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, nominal.stderr, "IncompatibleProvider") != null);
}

// C3 concrete-specialization reuse is not yet registered in SPEC.md; this block
// is the fresh-process regression evidence and must be reported with its patch.

fn c3sCheckProjectReport(environment: *const std.process.Environ.Map, path: []const u8, cache_argument: []const u8, no_cache: bool) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "check-project", path, "--report" });
    if (cache_argument.len != 0) try args.append(testing.allocator, cache_argument);
    if (no_cache) try args.append(testing.allocator, "--no-cache");
    return std.process.run(testing.allocator, testing.io, .{ .argv = args.items, .environ_map = environment });
}

fn c3sCheckReport(path: []const u8, cache_argument: []const u8, no_cache: bool) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "check", path, "--report" });
    if (cache_argument.len != 0) try args.append(testing.allocator, cache_argument);
    if (no_cache) try args.append(testing.allocator, "--no-cache");
    return std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
}

/// First semantic file whose payload carries the `specialization-v2` stable-key
/// prefix. The durable file name is a hash, so the kind marker is the discriminator.
fn c3sFirstSpecializationFile(allocator: std.mem.Allocator, cache_base: []const u8) ![]u8 {
    const version_dir = try std.fs.path.join(allocator, &.{ cache_base, "semantic", semantic_cache_version });
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
            if (std.mem.indexOf(u8, bytes, "spec\x1fv2\x1f") != null) return path;
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
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.selka" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    // The counts are of the work each process does from this test's own cache. The ownership proofs, a template's judgment
    // among them, are shared through the compiler store, so with the per-user store an earlier run of this test had already
    // published `render`'s judgment after the edit below and that check made no `render[i64]`, while a first run, or one with
    // sharing off, made it (FLK). So the shared stores are off. A Debug compiler also judges one held template in 64, chosen
    // by its digest, to verify the proof, so the sampling is off too.
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    defer environment.deinit();
    try environment.put("SELKA_ENGINE_VERIFY", "0");

    const library_render40 =
        \\
        \\
        \\public func render[T: integer](value: T) -> i64:
        \\    _ = value
        \\    return 40
        \\
        \\
        \\public func label[T: integer](value: T) -> i64:
        \\    _ = value
        \\    return 7
    ;
    const library_render41 =
        \\
        \\
        \\public func render[T: integer](value: T) -> i64:
        \\    _ = value
        \\    return 41
        \\
        \\
        \\public func label[T: integer](value: T) -> i64:
        \\    _ = value
        \\    return 7
    ;
    const library_label8 =
        \\
        \\
        \\public func render[T: integer](value: T) -> i64:
        \\    _ = value
        \\    return 41
        \\
        \\
        \\public func label[T: integer](value: T) -> i64:
        \\    _ = value
        \\    return 8
    ;
    const entry_u8 =
        \\import lib
        \\
        \\
        \\func main() -> i64:
        \\    return lib.render[u8](1u8) + lib.label[i64](2)
    ;
    const entry_split =
        \\import lib
        \\
        \\
        \\func main() -> i64:
        \\    mut a = lib.render[u8](1u8)
        \\    return a + lib.label[i64](2)
    ;
    const entry_i64 =
        \\import lib
        \\
        \\
        \\func main() -> i64:
        \\    return lib.render[i64](1) + lib.label[i64](2)
    ;

    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib.selka", .data = library_render40 });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = entry_u8 });
    const seed = try c3sCheckProjectReport(&environment, entry, cache_argument, false);
    defer testing.allocator.free(seed.stdout);
    defer testing.allocator.free(seed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, seed.term);
    const cold = try c2Counts(seed.stderr);
    try testing.expectEqual(@as(usize, 0), cold.reused);

    // A body edit in the entry forces a recheck; both concrete specializations replay even
    // though the source bytes changed, and `render`'s judgment at its declaration is held,
    // so the `render[i64]` that judged it is not made again (W3 step 2).
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = entry_split });
    const warm = try c3sCheckProjectReport(&environment, entry, cache_argument, false);
    defer testing.allocator.free(warm.stdout);
    defer testing.allocator.free(warm.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, warm.term);
    const unchanged = try c2Counts(warm.stderr);
    try testing.expectEqual(@as(usize, 2), unchanged.reused);
    try testing.expectEqual(@as(usize, 1), unchanged.performed);

    // Editing `render`'s template body invalidates only its specialization: `main`, `render[u8]`
    // and the `render[i64]` that judges `render` again are checked; `label[i64]` remains reusable.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib.selka", .data = library_render41 });
    const template_edit = try c3sCheckProjectReport(&environment, entry, cache_argument, false);
    defer testing.allocator.free(template_edit.stdout);
    defer testing.allocator.free(template_edit.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, template_edit.term);
    const template_counts = try c2Counts(template_edit.stderr);
    try testing.expectEqual(@as(usize, 1), template_counts.reused);
    try testing.expectEqual(@as(usize, 3), template_counts.performed);

    // Editing the concrete argument to `render[i64]` reaches the instance that judged `render`
    // in the previous process, so it replays with `label[i64]`, and only `main` is checked.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = entry_i64 });
    const argument_edit = try c3sCheckProjectReport(&environment, entry, cache_argument, false);
    defer testing.allocator.free(argument_edit.stdout);
    defer testing.allocator.free(argument_edit.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, argument_edit.term);
    const argument_counts = try c2Counts(argument_edit.stderr);
    try testing.expectEqual(@as(usize, 2), argument_counts.reused);
    try testing.expectEqual(@as(usize, 1), argument_counts.performed);

    // Editing `label`'s template body invalidates only its specialization.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib.selka", .data = library_label8 });
    const label_edit = try c3sCheckProjectReport(&environment, entry, cache_argument, false);
    defer testing.allocator.free(label_edit.stdout);
    defer testing.allocator.free(label_edit.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, label_edit.term);
    const label_counts = try c2Counts(label_edit.stderr);
    try testing.expectEqual(@as(usize, 1), label_counts.reused);
    try testing.expectEqual(@as(usize, 2), label_counts.performed);

    // Cold/warm agreement: an uncached check accepts exactly like the cached one.
    const uncached = try c3sCheckProjectReport(&environment, entry, cache_argument, true);
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
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.selka" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    const base_library =
        \\
        \\
        \\func helper(n: i64) -> i64:
        \\    return n + 1
        \\
        \\
        \\public func render[T: integer](value: T) -> i64:
        \\    _ = value
        \\    return helper(40)
    ;
    const edited_library =
        \\
        \\
        \\func helper(n: i64) -> i64:
        \\    return n + 2
        \\
        \\
        \\public func render[T: integer](value: T) -> i64:
        \\    _ = value
        \\    return helper(40)
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib.selka", .data = base_library });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\import lib
        \\
        \\
        \\func main() -> i64:
        \\    return lib.render[u8](1u8)
    });
    const warm_argv = [_][]const u8{ compilerPath(), "run-project", entry, "--print-result", cache_argument };
    const first = try std.process.run(testing.allocator, testing.io, .{ .argv = &warm_argv });
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 41 }, first.term);
    try testing.expectEqualStrings("41\n", first.stdout);

    // The provider body edit must appear in the generated code even though
    // `render`'s specialization region is unchanged.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib.selka", .data = edited_library });
    const warm = try std.process.run(testing.allocator, testing.io, .{ .argv = &warm_argv });
    defer testing.allocator.free(warm.stdout);
    defer testing.allocator.free(warm.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, warm.term);
    try testing.expectEqualStrings("42\n", warm.stdout);
    const cold_argv = [_][]const u8{ compilerPath(), "run-project", entry, "--print-result", "--no-cache" };
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
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.selka" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    const source =
        \\func size[T: integer](value: T) -> i64:
        \\    _ = value
        \\    return 7
        \\
        \\
        \\func main() -> i64:
        \\    return size[i64](1)
    ;
    const edited =
        \\func size[T: integer](value: T) -> i64:
        \\    _ = value
        \\    return 7
        \\
        \\
        \\func main() -> i64:
        \\    mut value = size[i64](1)
        \\    return value
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
    const seed = try c3sCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(seed.stdout);
    defer testing.allocator.free(seed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, seed.term);
    const spec_file = try c3sFirstSpecializationFile(testing.allocator, cache_base);
    defer testing.allocator.free(spec_file);

    const original_len = try c2FileLength(spec_file);
    try c2SetFileLength(spec_file, original_len / 2);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = edited });
    const truncated = try c3sCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(truncated.stdout);
    defer testing.allocator.free(truncated.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, truncated.term);
    // The program's one instance is `size[i64]`, the instance `check` makes to judge `size` at its declaration (W3 step 2),
    // so one specialization is stored and the damaged entry is the only one.
    try testing.expectEqual(@as(usize, 0), (try c2Counts(truncated.stderr)).reused);

    // Republish a clean entry, then simulate a foreign format version.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
    const republished = try c3sCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(republished.stdout);
    defer testing.allocator.free(republished.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, republished.term);
    const version_bytes = try std.Io.Dir.cwd().readFileAlloc(testing.io, spec_file, testing.allocator, .limited(1024 * 1024));
    defer testing.allocator.free(version_bytes);
    version_bytes[12] ^= 0x20;
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = spec_file, .data = version_bytes });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = edited });
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
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.selka" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "nocache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\func size[T: integer](value: T) -> i64:
        \\    _ = value
        \\    return 7
        \\
        \\
        \\func main() -> i64:
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
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.selka" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    const base =
        \\func size[T: integer](value: T, extra: i64 = 5) -> i64:
        \\    mut unused_local = 3
        \\    _ = value
        \\    return extra
        \\
        \\
        \\func main() -> i64:
        \\    return size[u8](1u8)
    ;
    const edited =
        \\type Marker = i64
        \\
        \\
        \\func size[T: integer](value: T, extra: i64 = 5) -> i64:
        \\    mut unused_local = 3
        \\    _ = value
        \\    return extra
        \\
        \\
        \\func main() -> i64:
        \\    mut a = size[u8](1u8)
        \\    return a
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = base });
    const seed = try c3sCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(seed.stdout);
    defer testing.allocator.free(seed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, seed.term);

    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = edited });
    const warm = try c3sCheckReport(entry, cache_argument, false);
    defer testing.allocator.free(warm.stdout);
    defer testing.allocator.free(warm.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, warm.term);
    const counts = try c2Counts(warm.stderr);
    // `size[u8]` and the `size[i64]` that judges `size` at its declaration (W3 step 2) both replay.
    try testing.expectEqual(@as(usize, 2), counts.reused);
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

fn c4TraceReset(path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(testing.io, path) catch {};
}

// ---------------------------------------------------------------------------
// PURE-SKIP: opt-in outcome replay for unchanged signature-pure tests
// ---------------------------------------------------------------------------

/// Where one scale fixture keeps its entry, cache and child trace.
const ScalePaths = struct { entry: []const u8, cache: []const u8, trace: []const u8 };
/// Run the chain's tests module by module (MODULE-TEST-1) with a fresh
/// trace; the caller frees the result.
fn moduleScaleRun(paths: ScalePaths) !std.process.RunResult {
    return moduleScaleRunWith(paths, &.{});
}
/// `moduleScaleRun` with extra environment variables.
fn moduleScaleRunWith(paths: ScalePaths, extra: []const [2][]const u8) !std.process.RunResult {
    c4TraceReset(paths.trace);
    const cache_arg = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{paths.cache});
    defer testing.allocator.free(cache_arg);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.appendSlice(testing.allocator, &.{ compilerPath(), "test", paths.entry, "--json", cache_arg });
    try args.appendSlice(testing.allocator, &tools);
    var environment: std.process.Environ.Map = .init(testing.allocator);
    defer environment.deinit();
    try environment.put("SELKA_TEST_TRACE", paths.trace);
    try environment.put("HOME", std.fs.path.dirname(paths.entry) orelse ".");
    for (extra) |pair| try environment.put(pair[0], pair[1]);
    try forwardZigCache(&environment);
    return spawnWithEnv(args.items, &environment);
}

test "module by module, a trapping and a printing test report what the whole-program run reports" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "util.selka", .data = "public func ratio(n: int, d: int) -> int:\n    return n // d\npublic func test_ratio() -> bool:\n    return ratio(6, 0) == 1\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "import util\nfunc main() -> int:\n    return 0\npublic func test_said(out: Stream) -> bool:\n    print(out, \"said\")\n    return util.ratio(4, 2) == 3\n" });
    const entry = try std.fs.path.join(a, &.{ directory, "main.selka" });
    var module_args: std.ArrayList([]const u8) = .empty;
    try module_args.appendSlice(a, &.{ "test", entry, "--cache-dir", try std.fs.path.join(a, &.{ directory, "cm" }) });
    try module_args.appendSlice(a, &tools);
    var whole_args: std.ArrayList([]const u8) = .empty;
    try whole_args.appendSlice(a, &.{ "test", entry, "--whole-program", "--cache-dir", try std.fs.path.join(a, &.{ directory, "cw" }) });
    try whole_args.appendSlice(a, &tools);
    const module = try runInterfaces(module_args.items);
    defer freeRun(module);
    const whole = try runInterfaces(whole_args.items);
    defer freeRun(whole);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, module.term);
    try testing.expectEqual(whole.term, module.term);
    try testing.expect(std.mem.indexOf(u8, module.stdout, "said") != null);
    try testing.expect(std.mem.indexOf(u8, module.stdout, "R_") != null);
    try testing.expectEqualStrings(whole.stdout, module.stdout);
}

// ---------------------------------------------------------------------------
// Guest performance benchmarks: candidate, approval and immutable enforcement
// ---------------------------------------------------------------------------

// Guest test transport, failure text and entry discovery
// ------------------------------------------------------

/// Run `selka test ENTRY` with this build's tools and an isolated cache.
fn guestTestRun(allocator: std.mem.Allocator, entry: []const u8, extra: []const []const u8, cache: []const u8) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    try args.appendSlice(allocator, &.{ compilerPath(), "test", entry });
    try args.appendSlice(allocator, extra);
    const cache_argument = try std.fmt.allocPrint(allocator, "--cache-dir={s}", .{cache});
    try args.append(allocator, cache_argument);
    try args.appendSlice(allocator, &tools);
    return privateRun(allocator, args.items);
}

const guest_output_program =
    \\
    \\
    \\public func test_chatty(out: Stream) -> bool:
    \\    print(out, "debug-marker")
    \\    return True
    \\
    \\
    \\public func test_failing(out: Stream) -> bool:
    \\    print(out, "debug-marker")
    \\    return False
    \\
    \\
    \\public func test_assert(out: Stream) -> bool:
    \\    print(out, "debug-marker")
    \\    assert 1 == 2, "one equals two"
    \\    return True
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

// spec: NATIVE-TEST-10
test "guest print output stays off the test protocol and shows on failure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "main.selka", guest_output_program);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const entry = try std.fs.path.join(a, &.{ root, "main.selka" });
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
    // FR19: a test that returned false is told to write one assert per fact; a failed assert (below) is not.
    try testing.expect(std.mem.indexOf(u8, failing.stdout, "\n  advice: this test returned false from one expression, so the report cannot say which fact failed: write one `assert` for each fact") != null);
    const trapped = try guestTestRun(a, entry, &.{ "--filter", "test_assert" }, cache);
    try testing.expect(std.mem.indexOf(u8, trapped.stdout, "advice:") == null);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, trapped.term);
    try testing.expect(std.mem.indexOf(u8, trapped.stdout, "R_ASSERT: one equals two") != null);
    try testing.expect(std.mem.indexOf(u8, trapped.stdout, "in main::test_assert at main.selka:") != null);
    try testing.expect(std.mem.indexOf(u8, trapped.stdout, "debug-marker") != null);
}

const guest_typed_program =
    \\
    \\
    \\public func test_value() -> int:
    \\    return 3
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

test "a typed expectation failure names both actual and expected values" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "main.selka", guest_typed_program);
    try writeProjectFile(&temporary, "cases.json", "{\"main::test_value\":{\"expected\":9}}");
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const entry = try std.fs.path.join(a, &.{ root, "main.selka" });
    const cases = try std.fs.path.join(a, &.{ root, "cases.json" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const run = try guestTestRun(a, entry, &.{ "--cases", cases }, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, run.term);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "expected 9, got 3") != null);
}

const library_entry_program =
    \\
    \\
    \\public func test_count() -> bool:
    \\    return 3 == 3
;

const bare_test_entry_program =
    \\
    \\
    \\public func test_bare() -> bool:
    \\    return True
;

test "library modules and bare *_test.selka files are valid guest test entries" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "inventory.selka", library_entry_program);
    try writeProjectFile(&temporary, "bare_test.selka", bare_test_entry_program);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const library = try std.fs.path.join(a, &.{ root, "inventory.selka" });
    const bare = try std.fs.path.join(a, &.{ root, "bare_test.selka" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const library_run = try guestTestRun(a, library, &.{ "--filter", "test_count" }, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, library_run.term);
    try testing.expect(std.mem.indexOf(u8, library_run.stdout, "1 passed") != null);
    const bare_run = try guestTestRun(a, bare, &.{ "--filter", "test_bare" }, cache);
    if (bare_run.term != .exited or bare_run.term.exited != 0) std.debug.print("bare guest test: {s}{s}\n", .{ bare_run.stdout, bare_run.stderr });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, bare_run.term);
    try testing.expect(std.mem.indexOf(u8, bare_run.stdout, "1 passed") != null);
}

const directory_project_main =
    \\import helper
    \\
    \\
    \\public func test_main() -> bool:
    \\    return helper.value() == 7
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

const directory_project_helper =
    \\
    \\
    \\public func value() -> int:
    \\    return 7
;

const directory_project_test =
    \\
    \\
    \\public func test_alone() -> bool:
    \\    return True
;

test "a directory run discovers project roots instead of every module" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "suite/main.selka", directory_project_main);
    try writeProjectFile(&temporary, "suite/helper.selka", directory_project_helper);
    try writeProjectFile(&temporary, "suite/library_test.selka", directory_project_test);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const suite = try std.fs.path.join(a, &.{ root, "suite" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const run = try guestTestRun(a, suite, &.{"--json"}, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run.term);
    const report = (try std.json.parseFromSlice(std.json.Value, a, run.stdout, .{})).value;
    try testing.expectEqual(@as(i64, 2), report.object.get("passed").?.integer);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "main::test_main") != null);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "library_test::test_alone") != null);
    try testing.expect(std.mem.indexOf(u8, run.stderr, "E_MODULE_NAME") == null);
}

/// A folder with no `selka.json` whose `rows/more_test.selka` imports `rows`, which sits in the folder given (FR51).
fn writeNestedRoot(a: std.mem.Allocator, temporary: *std.testing.TmpDir, folder: []const u8, configuration: bool) !void {
    const files = [_]struct { path: []const u8, data: []const u8 }{
        .{ .path = "rows.selka", .data = "public func size(items: int[]) -> int:\n    return len(items)\n" },
        .{ .path = "rows_test.selka", .data = "import rows\n\n\npublic func test_size() -> bool:\n    return rows.size([1, 2]) == 2\n" },
        .{ .path = "rows/more.selka", .data = "import rows\n\n\npublic func doubled(items: int[]) -> int:\n    return rows.size(items) * 2\n" },
        .{ .path = "rows/more_test.selka", .data = "import rows\nimport rows.more\n\n\npublic func test_doubled() -> bool:\n    return more.doubled([1]) == 2\n" },
    };
    for (files) |file| try writeProjectFile(temporary, try std.fs.path.join(a, &.{ folder, file.path }), file.data);
    if (configuration) try writeProjectFile(temporary, try std.fs.path.join(a, &.{ folder, "selka.json" }), "{\"version\": 1}\n");
}

test "a directory run with no selka.json takes the directory as the import root of a nested test file, as check does" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeNestedRoot(a, &temporary, "plain", false);
    try writeNestedRoot(a, &temporary, "configured", true);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    var listings: [2][]const u8 = undefined;
    for (&listings, [_][]const u8{ "plain", "configured" }) |*listing, name| {
        const folder = try std.fs.path.join(a, &.{ root, name });
        const checked = try runCompiler(a, &.{ compilerPath(), "check", folder });
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
        const first = try guestTestRun(a, folder, &.{}, cache);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
        try testing.expect(std.mem.indexOf(u8, first.stderr, "E_MODULE_READ") == null);
        try testing.expect(std.mem.indexOf(u8, first.stdout, "passed rows.more_test::test_doubled\n") != null);
        try testing.expect(std.mem.indexOf(u8, first.stdout, "passed rows_test::test_size\n") != null);
        try testing.expect(std.mem.indexOf(u8, first.stdout, "2 passed, 0 cached, 0 failed, 0 skipped") != null);
        // A second run replays both: the root a nested file took does not change what a record is keyed on.
        const second = try guestTestRun(a, folder, &.{}, cache);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, second.term);
        try testing.expect(std.mem.indexOf(u8, second.stdout, "0 passed, 2 cached, 0 failed, 0 skipped") != null);
        listing.* = first.stdout;
    }
    // With and without a `selka.json` the tests have the same names.
    try testing.expectEqualStrings(listings[0], listings[1]);
}

test "a directory run keeps its own folder as the import root of a nested file that loads with it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "suite/top.selka", "public func top() -> int:\n    return 3\n");
    try writeProjectFile(&temporary, "suite/top_test.selka", "import top\n\n\npublic func test_top() -> bool:\n    return top.top() == 3\n");
    try writeProjectFile(&temporary, "suite/one/helper.selka", "public func two() -> int:\n    return 2\n");
    try writeProjectFile(&temporary, "suite/one/helper_test.selka", "import helper\n\n\npublic func test_two() -> bool:\n    return helper.two() == 2\n");
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const run = try guestTestRun(a, try std.fs.path.join(a, &.{ root, "suite" }), &.{}, try std.fs.path.join(a, &.{ root, "cache" }));
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run.term);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "passed helper_test::test_two\n") != null);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "passed top_test::test_top\n") != null);
}

test "a file under a hidden folder of a project imports from the project's selka.json directory, and a directory run still skips the folder" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "app/selka.json", "{\"version\": 1}\n");
    try writeProjectFile(&temporary, "app/helper.selka", "public func twice(x: int) -> int:\n    return x * 2\n");
    try writeProjectFile(&temporary, "app/.tmp/scratch.selka", "import helper\n\n\nfunc main(out: Stream) -> int:\n    print(out, helper.twice(21))\n    return 0\n");
    try writeProjectFile(&temporary, "app/.tmp/scratch_test.selka", "import helper\n\n\npublic func test_twice() -> bool:\n    return helper.twice(2) == 4\n");
    try writeProjectFile(&temporary, "app/.tmp/bad.selka", "import helper\n\n\nfunc main(out: Stream) -> int:\n    print(out, helper.twice(\"a\"))\n    return 0\n");
    const root = try temporary.dir.realPathFileAlloc(testing.io, "app", a);
    const scratch = try std.fs.path.join(a, &.{ root, ".tmp", "scratch.selka" });
    // Before: E_MODULE_READ, "there is no `helper.selka` under the import root `.../.tmp` (no `selka.json` sets it)".
    const checked = try privateRun(a, &.{ compilerPath(), "check", scratch });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
    try testing.expect(std.mem.indexOf(u8, checked.stderr, "E_MODULE_READ") == null);
    const ran = try privateRun(a, &.{ compilerPath(), "run", scratch });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, ran.term);
    try testing.expectEqualStrings("42\n", ran.stdout);
    // A diagnostic in the file names it by its path, not by a module name.
    const refused = try privateRun(a, &.{ compilerPath(), "check", try std.fs.path.join(a, &.{ root, ".tmp", "bad.selka" }) });
    try testing.expect(std.mem.indexOf(u8, refused.stderr, ".tmp/bad.selka:5:") != null);
    // `--no-cache`: the test's receipt would go to the working directory's cache, and a later run of this test would say `cached`.
    const tested = try privateRun(a, &.{ compilerPath(), "test", try std.fs.path.join(a, &.{ root, ".tmp", "scratch_test.selka" }), "--no-cache" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, tested.term);
    // The report names the test file by its folder, not by the reserved module spelling `__hidden_tmp.scratch_test`.
    try testing.expect(std.mem.indexOf(u8, tested.stdout, "passed .tmp.scratch_test::test_twice\n") != null);
    // A directory run does not enter the hidden folder.
    const directory = try privateRun(a, &.{ compilerPath(), "test", root });
    try testing.expect(std.mem.indexOf(u8, directory.stdout, "scratch_test") == null);
    // Source cannot import the reserved spelling of the file: hidden folders cannot be imported.
    try writeProjectFile(&temporary, "app/peek.selka", "import __hidden_tmp.scratch\n\n\nfunc main(out: Stream) -> int:\n    print(out, 1)\n    return 0\n");
    const peeked = try privateRun(a, &.{ compilerPath(), "check", try std.fs.path.join(a, &.{ root, "peek.selka" }) });
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, peeked.term);
    try testing.expect(std.mem.indexOf(u8, peeked.stderr, "peek.selka:1:8: error[E_INTERNAL_NAME]") != null);
    try testing.expect(std.mem.indexOf(u8, peeked.stderr, "hidden folders cannot be imported") != null);
}

test "a directory run reports a file it cannot load as failed and runs the other entries" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "suite/a.selka", "public func one() -> int:\n    return 1\n");
    try writeProjectFile(&temporary, "suite/a_test.selka", "import a\n\n\npublic func test_one() -> bool:\n    return a.one() == 1\n");
    try writeProjectFile(&temporary, "suite/b_test.selka", "import nothere\n\n\npublic func test_b() -> bool:\n    return True\n");
    try writeProjectFile(&temporary, "suite/c_test.selka", "public func test_c(:\n");
    try writeProjectFile(&temporary, "suite/d_test.selka", "import a\n\n\npublic func test_d() -> bool:\n    return a.one() == 1\n");
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const run = try guestTestRun(a, try std.fs.path.join(a, &.{ root, "suite" }), &.{}, try std.fs.path.join(a, &.{ root, "cache" }));
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, run.term);
    try testing.expect(std.mem.indexOf(u8, run.stderr, "discovery failed") == null);
    try testing.expect(std.mem.indexOf(u8, run.stderr, "b_test.selka:1:8: error[E_MODULE_READ]: cannot load nothere.selka") != null);
    try testing.expect(std.mem.indexOf(u8, run.stderr, "c_test.selka:1:") != null);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "passed a_test::test_one\n") != null);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "passed d_test::test_d\n") != null);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "b_test.selka: failed to check or build, so no tests ran") != null);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "c_test.selka: failed to check or build, so no tests ran") != null);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "2 passed, 0 cached, 2 failed, 0 skipped") != null);
}

test "a directory run says how a file no selka.json governs gets its import root, and names a selka.json it cannot read" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "bare/a_test.selka", "public func test_a() -> bool:\n    return True\n");
    try writeProjectFile(&temporary, "bare/b_test.selka", "import nothere\n\n\npublic func test_b() -> bool:\n    return True\n");
    try writeProjectFile(&temporary, "governed/selka.json", "{\"version\": 1}\n");
    try writeProjectFile(&temporary, "governed/b_test.selka", "import nothere\n\n\npublic func test_b() -> bool:\n    return True\n");
    try writeProjectFile(&temporary, "broken/selka.json", "{}\n");
    try writeProjectFile(&temporary, "broken/a_test.selka", "public func test_a() -> bool:\n    return True\n");
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const bare = try guestTestRun(a, try std.fs.path.join(a, &.{ root, "bare" }), &.{}, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, bare.term);
    try testing.expect(std.mem.indexOf(u8, bare.stdout, "passed a_test::test_a\n") != null);
    try testing.expect(std.mem.indexOf(u8, bare.stderr, "note: no `selka.json` governs the failed file above. If its diagnostic says a module cannot be found") != null);
    try testing.expect(std.mem.indexOf(u8, bare.stderr, "`--import-root DIR` to name that folder") != null);
    // A file a `selka.json` governs has its import root from it: the note is not for it.
    const governed = try guestTestRun(a, try std.fs.path.join(a, &.{ root, "governed" }), &.{}, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, governed.term);
    try testing.expect(std.mem.indexOf(u8, governed.stdout, "b_test.selka: failed to check or build") != null);
    try testing.expect(std.mem.indexOf(u8, governed.stderr, "note: no `selka.json` governs") == null);
    // The run's own `selka.json` that cannot be read ends it, naming the file, the line and why.
    const broken = try guestTestRun(a, try std.fs.path.join(a, &.{ root, "broken" }), &.{}, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, broken.term);
    try testing.expect(std.mem.indexOf(u8, broken.stderr, "broken/selka.json:2:1: error[E_PROJECT_CONFIG]: selka.json must carry version: 1") != null);
}

/// Run `selka test ARGS` with `folder` as the working directory, as `guestTestRun` does with the tools and a cache of its own.
fn guestTestRunIn(a: std.mem.Allocator, folder: []const u8, args: []const []const u8, cache: []const u8) !std.process.RunResult {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), a), "test" });
    try argv.appendSlice(a, args);
    try argv.append(a, try std.fmt.allocPrint(a, "--cache-dir={s}", .{cache}));
    try argv.appendSlice(a, &tools);
    var environment = try @import("test_paths").privateEnvironment(a);
    defer environment.deinit();
    return std.process.run(a, testing.io, .{ .argv = argv.items, .cwd = .{ .path = folder }, .environ_map = &environment });
}

// spec: NEW-CORE-S4-TEST-2
test "selka test takes a relative --import-root from the working directory, as an absolute one" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    // `rows/more_test.selka` imports `rows`, which sits in the folder above its own, and no `selka.json` says where imports start.
    const files = [_]struct { path: []const u8, data: []const u8 }{
        .{ .path = "rows.selka", .data = "public func size(items: int[]) -> int:\n    return len(items)\n" },
        .{ .path = "rows/more.selka", .data = "import rows\n\n\npublic func doubled(items: int[]) -> int:\n    return rows.size(items) * 2\n" },
        .{ .path = "rows/more_test.selka", .data = "import rows\nimport rows.more\n\n\npublic func test_doubled() -> bool:\n    return more.doubled([1]) == 2\n" },
    };
    for (files) |file| {
        try writeProjectFile(&temporary, try std.fs.path.join(a, &.{ "proj", file.path }), file.data);
        try writeProjectFile(&temporary, try std.fs.path.join(a, &.{ "proj/sub", file.path }), file.data);
    }
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const proj = try std.fs.path.join(a, &.{ root, "proj" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    // Without the flag the file's own folder is the import root and has no `rows.selka`.
    const bare = try guestTestRunIn(a, proj, &.{"rows/more_test.selka"}, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, bare.term);
    try testing.expect(std.mem.indexOf(u8, bare.stderr, "E_MODULE_READ") != null);
    // `.` and `sub` were ignored as the flag's value (it had to be absolute); now each names its folder, and the absolute spelling agrees.
    const cases = [_]struct { entry: []const u8, root: []const u8 }{
        .{ .entry = "rows/more_test.selka", .root = "." },
        .{ .entry = "sub/rows/more_test.selka", .root = "sub" },
        .{ .entry = "sub/rows/more_test.selka", .root = try std.fs.path.join(a, &.{ proj, "sub" }) },
    };
    for (cases) |case| {
        const run = try guestTestRunIn(a, proj, &.{ case.entry, "--import-root", case.root }, cache);
        errdefer std.debug.print("--import-root {s}: stdout {s}\nstderr {s}\n", .{ case.root, run.stdout, run.stderr });
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run.term);
        try testing.expect(std.mem.indexOf(u8, run.stdout, "rows.more_test::test_doubled") != null);
    }
}

const directory_orphan_inner =
    \\
    \\
    \\public func base() -> int:
    \\    return 40
    \\
    \\
    \\public func test_inner() -> bool:
    \\    return base() == 40
;

const directory_orphan_outer =
    \\import inner
    \\
    \\
    \\public func test_outer() -> bool:
    \\    return inner.base() + 2 == 42
;

const directory_helper_with_test =
    \\
    \\
    \\public func value() -> int:
    \\    return 7
    \\
    \\
    \\public func test_helper() -> bool:
    \\    return value() == 7
;

// spec: NATIVE-TEST-14
test "a directory run runs a main-less test library no root imports, and every test once" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "suite/main.selka", directory_project_main);
    try writeProjectFile(&temporary, "suite/helper.selka", directory_helper_with_test);
    try writeProjectFile(&temporary, "suite/inner.selka", directory_orphan_inner);
    try writeProjectFile(&temporary, "suite/outer.selka", directory_orphan_outer);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const suite = try std.fs.path.join(a, &.{ root, "suite" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const run = try guestTestRun(a, suite, &.{"--json"}, cache);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run.term);
    const report = (try std.json.parseFromSlice(std.json.Value, a, run.stdout, .{})).value;
    // `main.selka` carries `helper`; `outer.selka` carries `inner`, so `inner.selka` is
    // not a program of its own and none of the four tests runs twice.
    try testing.expectEqual(@as(i64, 4), report.object.get("passed").?.integer);
    for ([_][]const u8{ "main::test_main", "helper::test_helper", "inner::test_inner", "outer::test_outer" }) |name| {
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, run.stdout, name));
    }
}

test "a single-entry test report lists the project sources its check loaded" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeProjectFile(&temporary, "suite/main.selka", directory_project_main);
    try writeProjectFile(&temporary, "suite/helper.selka", directory_project_helper);
    try writeProjectFile(&temporary, "suite/unrelated.selka", directory_orphan_inner);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const entry = try std.fs.path.join(a, &.{ root, "suite", "main.selka" });
    const run = try guestTestRun(a, entry, &.{"--json"}, try std.fs.path.join(a, &.{ root, "cache" }));
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run.term);
    const report = (try std.json.parseFromSlice(std.json.Value, a, run.stdout, .{})).value;
    const sources = report.object.get("sources").?.array.items;
    try testing.expectEqual(@as(usize, 2), sources.len);
    try testing.expectEqualStrings(entry, sources[0].string);
    try testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, "suite", "helper.selka" }), sources[1].string);
}

// spec-case: LINT-5
test "CLI list-interfaces prints a tests column from the shared reachability index" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data =
        \\
        \\
        \\public func parse(value: int) -> int:
        \\    return value
        \\
        \\
        \\func test_parse() -> bool:
        \\    return parse(1) == 1
        \\
        \\
        \\func main() -> int:
        \\    return 0
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.selka", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "list-interfaces", path } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "export function parse") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "tests(1)") != null);
}

// `selka invoke` calls one export of a checked project through the native
// runtime. These cases follow the `CLI context` fixtures: a small library
// project in a temporary directory, one JSON answer on stdout, and assertions
// about the shape of that answer rather than about a byte-for-byte document,
// because the envelope is still moving. Every case passes this build's QBE and
// Zig and a cache directory under its own fixture, so no case reads the
// repository cache, depends on PATH, or shares artifacts with another shard.

/// Run `argv` and require the removal refusal `selka COMMAND` gives for
/// `--unchecked`: usage exit status 2, the reason on stderr, nothing built.
fn expectUncheckedRemoved(argv: []const []const u8, command: []const u8) !void {
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, result.term);
    const expected = try std.fmt.allocPrint(testing.allocator, "selka {s}: --unchecked was removed: every build keeps overflow, cast and bounds checks so optimization never changes a program's result\n", .{command});
    defer testing.allocator.free(expected);
    try testing.expectEqualStrings(expected, result.stderr);
    try testing.expectEqualStrings("", result.stdout);
}

// spec: RELEASE-CHECKED-1
test "every building and running command refuses --unchecked as removed" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "refused.selka", .data =
        \\func main() -> i64:
        \\    return 0
    });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "refused.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const output = try std.fs.path.join(testing.allocator, &.{ directory, "refused-bin" });
    defer testing.allocator.free(output);
    try expectUncheckedRemoved(&.{ compilerPath(), "build", entry, "-o", output, "--unchecked" }, "build");
    try expectUncheckedRemoved(&.{ compilerPath(), "build", entry, "--run", "--release", "--unchecked" }, "build");
    try expectUncheckedRemoved(&.{ compilerPath(), "build", entry, "-o", output, "--unchecked", "--mode=Debug" }, "build");
    try expectUncheckedRemoved(&.{ compilerPath(), "run", entry, "--unchecked" }, "run");
    try expectUncheckedRemoved(&.{ compilerPath(), "run-project", entry, "--unchecked" }, "run-project");
    try expectUncheckedRemoved(&.{ compilerPath(), "test", entry, "--unchecked" }, "test");
    // Nothing was built.
    try testing.expectError(error.FileNotFound, temporary.dir.access(testing.io, "refused-bin", .{}));
}

/// One contract fixture: a module whose `half` carries `@requires(PRE)` and
/// whose `Range` carries `@invariant(INV)`, with a passing test for each.
fn contractFixture(precondition: []const u8, invariant: []const u8) ![]u8 {
    return std.fmt.allocPrint(testing.allocator,
        \\
        \\@invariant({s})
        \\public record Range:
        \\    low: int
        \\    high: int
        \\
        \\@requires({s})
        \\public func half(amount: int) -> int:
        \\    return amount // 2
        \\
        \\func make(low: int) -> Range:
        \\    return Range(low=low, high=5)
        \\
        \\public func test_half() -> bool:
        \\    return half(4) == 2
        \\
        \\public func test_make() -> bool:
        \\    return make(3).low == 3
        \\
        \\func main() -> int:
        \\    return half(4) + make(3).low
        \\
    , .{ invariant, precondition });
}

/// Run one compiler command and hand back its result; the caller frees it.
fn contractCommand(argv: []const []const u8) !std.process.RunResult {
    return privateRun(testing.allocator, argv);
}

fn freeResult(result: std.process.RunResult) void {
    testing.allocator.free(result.stdout);
    testing.allocator.free(result.stderr);
}

/// Write `main.selka` from the fixture template in `directory`.
fn writeContractFixture(directory: std.Io.Dir, precondition: []const u8, invariant: []const u8) !void {
    const text = try contractFixture(precondition, invariant);
    defer testing.allocator.free(text);
    try directory.writeFile(testing.io, .{ .sub_path = "main.selka", .data = text });
}

// spec: CONTRACT-CACHE-1
test "CLI an edit to one contract clause is never served from a warm cache" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try writeContractFixture(temporary.dir, "amount > 0", "self.low <= self.high");
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.selka" });
    defer testing.allocator.free(entry);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, "cache" });
    defer testing.allocator.free(cache);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_argument);
    const warm_test = try contractCommand(&.{ compilerPath(), "test", entry, cache_argument, tools[0] });
    defer freeResult(warm_test);
    if (std.mem.indexOf(u8, warm_test.stdout, "2 passed") == null) std.debug.print("contract guest test: {s}{s}\n", .{ warm_test.stdout, warm_test.stderr });
    try testing.expect(std.mem.indexOf(u8, warm_test.stdout, "2 passed") != null);
    const warm_run = try contractCommand(&.{ compilerPath(), "run", entry, cache_argument, tools[0] });
    defer freeResult(warm_run);
    try testing.expectEqual(std.process.Child.Term{ .exited = 5 }, warm_run.term);
    // Only the precondition changes: the same caches must now trap under it.
    try writeContractFixture(temporary.dir, "amount > 10", "self.low <= self.high");
    const run = try contractCommand(&.{ compilerPath(), "run", entry, cache_argument, tools[0] });
    defer freeResult(run);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, run.term);
    try testing.expect(std.mem.indexOf(u8, run.stderr, "error[R_REQUIRES]: precondition violated: half requires `amount > 10`") != null);
    const tested = try contractCommand(&.{ compilerPath(), "test", entry, cache_argument, tools[0] });
    defer freeResult(tested);
    try testing.expect(std.mem.indexOf(u8, tested.stdout, "failed main::test_half: R_REQUIRES: half requires `amount > 10`") != null);
    try testing.expect(std.mem.indexOf(u8, tested.stdout, "1 failed") != null);
    // An invariant lives on another declaration than the body that checks it.
    try writeContractFixture(temporary.dir, "amount > 10", "self.low > self.high");
    const rechecked = try contractCommand(&.{ compilerPath(), "test", entry, cache_argument, tools[0] });
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
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.selka" });
    defer testing.allocator.free(entry);
    const baseline = try std.fs.path.join(testing.allocator, &.{ root, "baseline.txt" });
    defer testing.allocator.free(baseline);
    const write_argument = try std.fmt.allocPrint(testing.allocator, "--write={s}", .{baseline});
    defer testing.allocator.free(write_argument);
    const against_argument = try std.fmt.allocPrint(testing.allocator, "--against={s}", .{baseline});
    defer testing.allocator.free(against_argument);
    const listed = try contractCommand(&.{ compilerPath(), "list-interfaces", entry });
    defer freeResult(listed);
    try testing.expect(std.mem.indexOf(u8, listed.stdout, "export type Range @invariant(self.low <= self.high)") != null);
    try testing.expect(std.mem.indexOf(u8, listed.stdout, "tests(1) @requires(amount > 0)") != null);
    const manifest = try contractCommand(&.{ compilerPath(), "list-interfaces", "--contracts", entry });
    defer freeResult(manifest);
    try testing.expect(std.mem.indexOf(u8, manifest.stdout, "\"contracts\":\"@invariant(self.low <= self.high)\"") != null);
    const context = try contractCommand(&.{ compilerPath(), "context", entry, "--symbol=main::half" });
    defer freeResult(context);
    try testing.expect(std.mem.indexOf(u8, context.stdout, "\"signature\":\"@requires(amount > 0)\\nhalf(amount: int) -> int") != null);
    const written = try contractCommand(&.{ compilerPath(), "api-diff", entry, write_argument });
    defer freeResult(written);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, written.term);
    try writeContractFixture(temporary.dir, "amount > 1", "self.low < self.high");
    const diffed = try contractCommand(&.{ compilerPath(), "api-diff", entry, against_argument });
    defer freeResult(diffed);
    try testing.expect(std.mem.indexOf(u8, diffed.stdout, "breaking: main::Range (interface changed)") != null);
    try testing.expect(std.mem.indexOf(u8, diffed.stdout, "breaking: main::half (interface changed)") != null);
}

// spec-case: CONTRACT-TRAP-1
test "CLI a release build and a JSON diagnostic report the contract that failed" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data =
        \\@requires(amount > 0, "amount must be positive")
        \\func half(amount: int) -> int:
        \\    return amount // 2
        \\
        \\@ensures(result > 100)
        \\func grow(x: int) -> int:
        \\    return x + 1
        \\
        \\func main() -> int:
        \\    return grow(half(8))
        \\
    });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "caller.selka", .data =
        \\@requires(amount > 0, "amount must be positive")
        \\func half(amount: int) -> int:
        \\    return amount // 2
        \\
        \\func main() -> int:
        \\    return half(0)
        \\
    });
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.selka" });
    defer testing.allocator.free(entry);
    const caller = try std.fs.path.join(testing.allocator, &.{ root, "caller.selka" });
    defer testing.allocator.free(caller);
    const program = try std.fs.path.join(testing.allocator, &.{ root, "program" });
    defer testing.allocator.free(program);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{root});
    defer testing.allocator.free(cache_argument);
    const json = try contractCommand(&.{ compilerPath(), "run", caller, "--diagnostics=json", cache_argument, tools[0] });
    defer freeResult(json);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, json.term);
    try testing.expect(std.mem.indexOf(u8, json.stderr, "\"code\":\"R_REQUIRES\"") != null);
    try testing.expect(std.mem.indexOf(u8, json.stderr, "\"contract\":{\"kind\":\"requires\",\"subject\":\"half\",\"clause\":\"amount > 0\",\"message\":\"amount must be positive\",\"caller\":{") != null);
    const built = try contractCommand(&.{ compilerPath(), "build", entry, "-o", program, "--release", cache_argument, tools[0] });
    defer freeResult(built);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const released = try contractCommand(&.{program});
    defer freeResult(released);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, released.term);
    try testing.expect(std.mem.indexOf(u8, released.stderr, "error[R_ENSURES]: postcondition violated: grow ensures `result > 100`") != null);
}

/// One project directory holding `main.selka`, with its own test cache, for the
/// property-test CLI runs below.
const PropertyProject = struct {
    temporary: std.testing.TmpDir,
    path: [:0]const u8,
    cache: []const u8,

    fn init(source: []const u8) !PropertyProject {
        var temporary = testing.tmpDir(.{});
        errdefer temporary.cleanup();
        try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
        const path = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
        errdefer testing.allocator.free(path);
        const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
        defer testing.allocator.free(root);
        return .{ .temporary = temporary, .path = path, .cache = try std.fs.path.join(testing.allocator, &.{ root, ".selka-test-cache" }) };
    }
    fn deinit(self: *PropertyProject) void {
        testing.allocator.free(self.path);
        testing.allocator.free(self.cache);
        self.temporary.cleanup();
    }
    /// `selka test main.selka` with the project cache and `extra` arguments.
    fn run(self: PropertyProject, extra: []const []const u8) !std.process.RunResult {
        return capabilityTestRun(self.path, self.cache, extra);
    }
};
fn freeRun(result: std.process.RunResult) void {
    testing.allocator.free(result.stdout);
    testing.allocator.free(result.stderr);
}
/// The `property` object of the named test in a `native-tests-v1` report.
fn propertyOf(parsed: std.json.Value, name: []const u8) !std.json.Value {
    for (parsed.object.get("tests").?.array.items) |item| {
        if (std.mem.eql(u8, item.object.get("name").?.string, name)) return item.object.get("property") orelse error.TestUnexpectedResult;
    }
    return error.TestUnexpectedResult;
}

const failing_property =
    \\import lists
    \\
    \\
    \\public func test_sum_stays_below_100(xs: int[]) -> bool:
    \\    mut total = 0
    \\    for x in xs:
    \\        total = total + x
    \\    return total < 100
    \\
    \\public func test_reversing_twice_is_the_identity(xs: int[]) -> bool:
    \\    mut ys = copy(xs)
    \\    lists.reverse(mut ys)
    \\    lists.reverse(mut ys)
    \\    return ys == xs
    \\
    \\func main() -> int:
    \\    return 0
;

// spec: PROPERTY-TEST-3
test "CLI property test shrinks a failing sum to the single-element list [100] and reports how to reproduce it" {
    var project = try PropertyProject.init(failing_property);
    defer project.deinit();
    const text = try project.run(&.{});
    defer freeRun(text);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, text.term);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "passed main::test_reversing_twice_is_the_identity\n") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "failed main::test_sum_stays_below_100: falsified after ") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "  minimal input (") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "\n    xs = [100]\n  original input (run ") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "  reason: returned False\n  reproduce: selka test ") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "main.selka --filter 'main::test_sum_stays_below_100' --seed ") != null);
    const json = try project.run(&.{"--json"});
    defer freeRun(json);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json.stdout, .{});
    defer parsed.deinit();
    const property = try propertyOf(parsed.value, "main::test_sum_stays_below_100");
    const failure = property.object.get("failure").?;
    const minimal = failure.object.get("minimal").?;
    try testing.expectEqual(@as(usize, 1), minimal.object.get("arguments").?.object.get("xs").?.array.items.len);
    try testing.expectEqualStrings("100", minimal.object.get("arguments").?.object.get("xs").?.array.items[0].string);
    try testing.expectEqualStrings("[100]", minimal.object.get("literals").?.object.get("xs").?.string);
    try testing.expectEqualStrings("returned False", failure.object.get("reason").?.string);
    try testing.expect(property.object.get("counts").?.object.get("shrinks").?.integer > 0);
    // The same seed draws the same inputs, so the reproduction reports the
    // same counterexample from the same run.
    const seed = try std.json.Stringify.valueAlloc(testing.allocator, property.object.get("seed").?, .{});
    defer testing.allocator.free(seed);
    const again = try project.run(&.{ "--json", "--seed", seed, "--filter", "test_sum" });
    defer freeRun(again);
    const replay = try std.json.parseFromSlice(std.json.Value, testing.allocator, again.stdout, .{});
    defer replay.deinit();
    const replayed = (try propertyOf(replay.value, "main::test_sum_stays_below_100")).object.get("failure").?;
    try testing.expectEqual(failure.object.get("run").?.integer, replayed.object.get("run").?.integer);
    try testing.expectEqualStrings("[100]", replayed.object.get("minimal").?.object.get("literals").?.object.get("xs").?.string);
}

// migrate-embedded: skip intentional original property-domain removal diagnostic
const legacy_refused_properties =
    \\
    \\public domain Meters: u32:
    \\    func from(value: u32) -> Meters:
    \\        return wrap[Meters](value)
    \\
    \\public func test_domain(m: Meters) -> bool:
    \\    _ = m
    \\    return True
    \\
    \\public func test_function(f: func(int) -> int) -> bool:
    \\    return f(1) >= 0
    \\
    \\public func test_host(host: Host, n: int) -> bool:
    \\    _ = host
    \\    return n >= 0
    \\
    \\public func test_count(n: int) -> int:
    \\    return n
    \\
    \\func main() -> int:
    \\    return 0
;

const refused_properties =
    \\
    \\public record Meters:
    \\    value: u32
    \\
    \\public func meters_from(value: u32) -> Meters:
    \\    return Meters(value=value)
    \\
    \\public func test_domain(m: Meters) -> bool:
    \\    _ = m
    \\    return True
    \\
    \\public func test_function(f: func(int) -> int) -> bool:
    \\    return f(1) >= 0
    \\
    \\public func test_host(host: Host, n: int) -> bool:
    \\    _ = host
    \\    return n >= 0
    \\
    \\public func test_count(n: int) -> int:
    \\    return n
    \\
    \\public record Handler:
    \\    run: func(int) -> int
    \\
    \\public func test_handlers(items: Handler[]) -> bool:
    \\    return len(items) >= 0
    \\
    \\public func test_maybe(item: Handler?) -> bool:
    \\    _ = item
    \\    return True
    \\
    \\public func test_floats(x: float) -> float:
    \\    return x
    \\
    \\public func test_listing(xs: int[]) -> int[]:
    \\    return copy(xs)
    \\
    \\func main() -> int:
    \\    return 0
;

// spec: PROPERTY-TEST-1
test "CLI property test names the parameter and type it cannot generate" {
    var legacy = try PropertyProject.init(legacy_refused_properties);
    defer legacy.deinit();
    const removed = try legacy.run(&.{});
    defer freeRun(removed);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, removed.term);
    try testing.expect(std.mem.indexOf(u8, removed.stderr, "E_DOMAIN_REMOVED") != null);
    var project = try PropertyProject.init(refused_properties);
    defer project.deinit();
    const result = try project.run(&.{});
    defer freeRun(result);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "passed main::test_domain\n") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "failed main::test_function: property test parameter `f: func(int) -> int` cannot be generated") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "failed main::test_handlers: property test parameter `items: main.Handler[]` cannot be generated: it holds func(int) -> int, and") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "failed main::test_maybe: property test parameter `item: main.Handler?` cannot be generated") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "failed main::test_floats: a property test returns bool or Result[bool, E], not float\n") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "failed main::test_listing: a property test returns bool or Result[bool, E], not int[]\n") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "a function value cannot be generated") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "failed main::test_host: a test that declares `host: Host` calls C: the Host capability is handed to a test only under `selka test --allow-host`") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "failed main::test_count: a property test returns bool or Result[bool, E], not int") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "host failure") == null);
}

const filtered_properties =
    \\
    \\@invariant(self.low <= self.high, "a span never runs backwards")
    \\public record Span:
    \\    low: int
    \\    high: int
    \\
    \\@requires(n >= 0, "only non-negative numbers")
    \\public func test_halving(n: int) -> bool:
    \\    return n // 2 <= n
    \\
    \\public func test_span(span: Span, other: Span?) -> bool:
    \\    match other:
    \\        case Some(second):
    \\            return span.low <= span.high and second.low <= second.high
    \\        case None:
    \\            return span.low <= span.high
    \\
    \\@requires(n == 12345, "a single value")
    \\public func test_picky(n: int) -> bool:
    \\    return n == 12345
    \\
    \\func main() -> int:
    \\    return 0
;

// spec-case: PROPERTY-TEST-2
test "CLI property test discards inputs that break a precondition or a record invariant" {
    var project = try PropertyProject.init(filtered_properties);
    defer project.deinit();
    const result = try project.run(&.{"--json"});
    defer freeRun(result);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, result.stdout, .{});
    defer parsed.deinit();
    const halving = (try propertyOf(parsed.value, "main::test_halving")).object.get("counts").?;
    try testing.expectEqual(@as(i64, 100), halving.object.get("passed").?.integer);
    try testing.expect(halving.object.get("discarded").?.integer > 0);
    const span = (try propertyOf(parsed.value, "main::test_span")).object.get("counts").?;
    try testing.expectEqual(@as(i64, 100), span.object.get("passed").?.integer);
    try testing.expect(span.object.get("discarded").?.integer > 0);
    const text = try project.run(&.{ "--filter", "test_picky" });
    defer freeRun(text);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "failed main::test_picky: too many discarded inputs: 1001 of 1001 generated inputs broke a precondition before 0 of 100 runs passed; most often test_picky requires `n == 12345`: a single value") != null);
    // A cases-file argument still wins over generation, and an invalid record
    // it supplies is refused by the same invariant check.
    try project.temporary.dir.writeFile(testing.io, .{ .sub_path = "cases.json", .data = "{\"main::test_span\":{\"arguments\":{\"span\":{\"low\":\"5\",\"high\":\"1\"},\"other\":{\"case\":\"none\"}}}}" });
    const cases = try project.temporary.dir.realPathFileAlloc(testing.io, "cases.json", testing.allocator);
    defer testing.allocator.free(cases);
    const explicit = try project.run(&.{ "--cases", cases, "--filter", "test_span" });
    defer freeRun(explicit);
    try testing.expect(std.mem.indexOf(u8, explicit.stdout, "failed main::test_span: R_INVARIANT: Span invariant `self.low <= self.high`: a span never runs backwards") != null);
}

const hanging_property =
    \\
    \\public func test_finishes(n: int) -> bool:
    \\    mut spins = 0
    \\    while True:
    \\        spins = spins + 1
    \\    return spins == 0
    \\
    \\func main() -> int:
    \\    return 0
;

// spec: PROPERTY-TEST-4
test "CLI property test runs in one process, reuses a pass until its seed or runs change, and reports a timed-out child without shrinking" {
    var project = try PropertyProject.init(failing_property);
    defer project.deinit();
    const first = try project.run(&.{ "--json", "--filter", "test_reversing" });
    defer freeRun(first);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, first.stdout, .{});
    defer parsed.deinit();
    const counts = (try propertyOf(parsed.value, "main::test_reversing_twice_is_the_identity")).object.get("counts").?;
    try testing.expectEqual(@as(i64, 100), counts.object.get("passed").?.integer);
    try testing.expectEqual(@as(i64, 1), counts.object.get("processes").?.integer);
    const cached = try project.run(&.{ "--filter", "test_reversing" });
    defer freeRun(cached);
    try testing.expect(std.mem.indexOf(u8, cached.stdout, "cached main::test_reversing_twice_is_the_identity") != null);
    const fewer = try project.run(&.{ "--filter", "test_reversing", "--property-runs", "20" });
    defer freeRun(fewer);
    try testing.expect(std.mem.indexOf(u8, fewer.stdout, "passed main::test_reversing_twice_is_the_identity") != null);
    const reseeded = try project.run(&.{ "--filter", "test_reversing", "--seed", "3" });
    defer freeRun(reseeded);
    try testing.expect(std.mem.indexOf(u8, reseeded.stdout, "passed main::test_reversing_twice_is_the_identity") != null);
    const reused = try project.run(&.{ "--filter", "test_reversing", "--seed", "3" });
    defer freeRun(reused);
    try testing.expect(std.mem.indexOf(u8, reused.stdout, "cached main::test_reversing_twice_is_the_identity") != null);
    // Every input hangs: starting the child and accepting a useful prefix must
    // not race this actual deadline probe. The deterministic interrupted-prefix
    // regression in property_campaign_contract_test covers retaining prior rows.
    var hanging = try PropertyProject.init(hanging_property);
    defer hanging.deinit();
    const hung = try hanging.run(&.{ "--timeout-ms", "1000", "--max-steps", "4000000000" });
    defer freeRun(hung);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, hung.term);
    try testing.expect(std.mem.indexOf(u8, hung.stdout, "failed main::test_finishes: falsified after 0 passing runs") != null);
    if (std.mem.indexOf(u8, hung.stdout, "  input (not shrunk:") == null) {
        std.debug.print("property timeout stdout:\n{s}\nstderr:\n{s}\n", .{ hung.stdout, hung.stderr });
    }
    try testing.expect(std.mem.indexOf(u8, hung.stdout, "  input (not shrunk: it ran out of time, and so could every candidate):") != null);
    try testing.expect(std.mem.indexOf(u8, hung.stdout, "  reason: the input ran past --timeout-ms 1000") != null);
}

const boundary_values =
    \\import sets
    \\
    \\public record BoundaryKey:
    \\    number: int
    \\    text: str
    \\
    \\public func test_echo_set(s: set[str]) -> set[str]:
    \\    mut t = copy(s)
    \\    sets.add(mut t, "zz")
    \\    return t
    \\
    \\public func test_echo_dict(d: dict[BoundaryKey, float]) -> dict[BoundaryKey, float]:
    \\    mut e = copy(d)
    \\    e[BoundaryKey(number=9, text="k")] = 0.5
    \\    return e
    \\
    \\public func test_echo_bytes(b: bytes) -> bytes:
    \\    return b + b"!"
    \\
    \\public func test_echo_float(f: float) -> float:
    \\    return f * 2.0
    \\
    \\func main() -> int:
    \\    return 0
;
const boundary_cases =
    \\{"main::test_echo_set":{"arguments":{"s":["a","b"]},"expected":["a","b","zz"]},
    \\ "main::test_echo_dict":{"arguments":{"d":[[{"number":"1","text":"x"},"1.5"],[{"number":"-3","text":""},"nan"]]},
    \\   "expected":[[{"number":"1","text":"x"},"1.5"],[{"number":"-3","text":""},"nan"],[{"number":"9","text":"k"},"0.5"]]},
    \\ "main::test_echo_bytes":{"arguments":{"b":["104","0"]},"expected":["104","0","33"]},
    \\ "main::test_echo_float":{"arguments":{"f":"-inf"},"expected":"-inf"}}
;

// spec: PROPERTY-TEST-5
test "CLI test carries sets, dictionaries with tuple keys, bytes and floats across the copied-value boundary" {
    var project = try PropertyProject.init(boundary_values);
    defer project.deinit();
    try project.temporary.dir.writeFile(testing.io, .{ .sub_path = "cases.json", .data = boundary_cases });
    const cases = try project.temporary.dir.realPathFileAlloc(testing.io, "cases.json", testing.allocator);
    defer testing.allocator.free(cases);
    const result = try project.run(&.{ "--cases", cases });
    defer freeRun(result);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "4 passed, 0 cached, 0 failed, 0 skipped") != null);
}

const erring_property =
    \\import strings
    \\
    \\func parse(text: str) -> int fails str:
    \\    if strings.char_count(text) > 3:
    \\        fail "too long"
    \\    return strings.char_count(text)
    \\
    \\func checked(text: str) -> int fails str:
    \\    mut size = try parse(text)
    \\    return size
    \\
    \\public func test_short_text_parses(text: str) -> bool fails str:
    \\    mut size = try checked(text)
    \\    return size <= 3
    \\
    \\func main() -> int:
    \\    return 0
;

// spec-case: PROPERTY-TEST-3
// spec-case: ERROR-TRACE-3
test "CLI property test that fails with an Err reports the minimal input's error return trace" {
    var project = try PropertyProject.init(erring_property);
    defer project.deinit();
    const text = try project.run(&.{});
    defer freeRun(text);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, text.term);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "\n    text = \"aaaa\"\n  original input (run ") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "  reason: returned Err(\"too long\")\n    error return trace:\n") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "main.selka:5:9") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "main::parse") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "Err(...) created") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "main::test_short_text_parses") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "try propagated") != null);
    const json = try project.run(&.{"--json"});
    defer freeRun(json);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json.stdout, .{});
    defer parsed.deinit();
    const failure = (try propertyOf(parsed.value, "main::test_short_text_parses")).object.get("failure").?;
    const reason = failure.object.get("reason").?.string;
    try testing.expect(std.mem.startsWith(u8, reason, "returned Err(\"too long\")\nerror return trace:\n"));
    // The trace names the project's own file, not the runner's private snapshot.
    try testing.expect(std.mem.indexOf(u8, reason, ".pending") == null);
    try testing.expectEqualStrings("\"aaaa\"", failure.object.get("minimal").?.object.get("literals").?.object.get("text").?.string);
}

const iterated_write_back =
    \\record Runtime:
    \\    objects: int[]
    \\record Interp:
    \\    rt: Runtime
    \\func push(mut rt: Runtime, value: int) -> Unit:
    \\    append(mut rt.objects, value)
    \\func main() -> int:
    \\    mut it = Interp(rt=Runtime(objects=[1, 2]))
    \\    mut saved = copy(it.rt)
    \\    mut seen = 0
    \\    for x in it.rt.objects:
    \\        seen = seen + x
    \\        if x < 3:
    \\            mut wb = it.rt
    \\            push(mut wb, x + 2)
    \\            it.rt = wb
    \\    if seen == 10 and len(it.rt.objects) == 4 and saved.objects == [1, 2]:
    \\        return 0
    \\    return 1
;

// spec-case: RC-ITERATION-HOLD-TRANSFER-1
test "CLI rejects iteration growth written back through a borrowed named field" {
    try transition.refusesRule(testing.allocator, iterated_write_back, "E_SINGLE_OWNER_OVERLAP", "R7");
}

/// Run `argv` with its program path made absolute, from inside `dir`.
fn runInDirectory(dir: std.Io.Dir, argv: []const []const u8) !std.process.RunResult {
    const absolute = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, argv[0], testing.allocator);
    defer testing.allocator.free(absolute);
    var resolved = try testing.allocator.dupe([]const u8, argv);
    defer testing.allocator.free(resolved);
    resolved[0] = absolute;
    return std.process.run(testing.allocator, testing.io, .{ .argv = resolved, .cwd = .{ .dir = dir } });
}

/// Run `argv` inside `dir` and require the input refusal: exit 2, nothing on
/// standard output, and exactly `sentence` on standard error.
fn expectRefused(dir: std.Io.Dir, argv: []const []const u8, sentence: []const u8) !void {
    const outcome = try runInDirectory(dir, argv);
    defer freeRun(outcome);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, outcome.term);
    try testing.expectEqualStrings("", outcome.stdout);
    try testing.expectEqualStrings(sentence, outcome.stderr);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, ".zig:") == null);
}

/// Every command that takes one source entry refuses a missing file and a
/// directory in the same words.
fn expectEveryEntryCommandRefused(dir: std.Io.Dir) !void {
    inline for (.{ "check", "check-module", "fmt", "fmt-module", "run", "lint", "list-modules", "run-project", "list-declarations", "dump-tokens", "dump-syntax" }) |command| {
        try expectRefused(dir, &.{ compilerPath(), command, "nope.selka" }, "selka " ++ command ++ ": cannot read 'nope.selka': no such file or directory\n");
        // `check` takes a directory: it checks every module of the project beneath it (`check_directory_cli_test.zig`).
        if (comptime !std.mem.eql(u8, command, "check")) try expectRefused(dir, &.{ compilerPath(), command, "adir" }, "selka " ++ command ++ ": cannot read 'adir': is a directory, not a file\n");
    }
}

/// The refusal a file this process cannot read gets, or nothing when it can read
/// it anyway (running as root), where there is nothing to refuse.
fn expectUnreadableRefused(dir: std.Io.Dir, command: []const u8) !void {
    try dir.writeFile(testing.io, .{ .sub_path = "locked.selka", .data = "func main() -> int:\n    return 0\n" });
    try dir.setFilePermissions(testing.io, "locked.selka", std.Io.File.Permissions.fromMode(0), .{});
    const readable = dir.openFile(testing.io, "locked.selka", .{});
    if (readable) |file| {
        file.close(testing.io);
        return;
    } else |_| {}
    const sentence = try std.fmt.allocPrint(testing.allocator, "selka {s}: cannot read 'locked.selka': permission denied\n", .{command});
    defer testing.allocator.free(sentence);
    try expectRefused(dir, &.{ compilerPath(), command, "locked.selka" }, sentence);
}

// spec: CLI-INPUT-REFUSED-1
test "a missing, unreadable or directory entry is refused by name with the usage status" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDir(testing.io, "adir", .default_dir);
    const missing = "no such file or directory";
    try expectEveryEntryCommandRefused(temp.dir);
    try expectRefused(temp.dir, &.{ compilerPath(), "build", "nope.selka", "-o", "out.bin" }, "selka build: cannot read 'nope.selka': " ++ missing ++ "\n");
    try expectRefused(temp.dir, &.{ compilerPath(), "build", "adir", "-o", "out.bin" }, "selka build: cannot read 'adir': is a directory, not a file\n");
    try expectRefused(temp.dir, &.{ compilerPath(), "test", "nope.selka" }, "selka test: cannot read 'nope.selka': " ++ missing ++ "\n");
    try expectRefused(temp.dir, &.{ compilerPath(), "fix", "nope.selka" }, "selka fix: cannot read 'nope.selka': " ++ missing ++ "\n");
    try expectRefused(temp.dir, &.{ compilerPath(), "api", "nope.selka", "--check" }, "selka api: cannot read 'nope.selka': " ++ missing ++ "\n");
    try expectUnreadableRefused(temp.dir, "check");
    // The refusal is in the structured diagnostic format when one is asked for.
    const json = try runInDirectory(temp.dir, &.{ compilerPath(), "check", "nope.selka", "--diagnostics=json" });
    defer freeRun(json);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, json.term);
    try testing.expect(std.mem.indexOf(u8, json.stderr, "cannot read 'nope.selka'") != null);
    // A refused input leaves no cache directory behind.
    try testing.expectError(error.FileNotFound, temp.dir.statFile(testing.io, ".selka-cache", .{}));
}

test "a test run that refuses its entry by name creates no cache directory" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try expectRefused(temp.dir, &.{ compilerPath(), "test", "nope.selka" }, "selka test: cannot read 'nope.selka': no such file or directory\n");
    try testing.expectError(error.FileNotFound, temp.dir.statFile(testing.io, ".selka-cache", .{}));
}

/// A program of three shapes that read its standard input: the lines it holds, fixed-size chunks, and what a
/// refused request does. `mode` selects one.
const input_program =
    \\func lines(stdin: Input, out: Stream) -> int:
    \\    mut count = 0
    \\    mut octets = 0
    \\    mut longest = 0
    \\    while True:
    \\        match stdin.read_line():
    \\            case Some(line):
    \\                count += 1
    \\                octets += len(line)
    \\                longest = max(longest, len(line))
    \\            case None:
    \\                print(out, count, octets, longest)
    \\                return 0
    \\
    \\
    \\func chunks(stdin: Input, out: Stream) -> int:
    \\    mut total = 0
    \\    while True:
    \\        const piece = stdin.read(1000)
    \\        if len(piece) == 0:
    \\            break
    \\        total += len(piece)
    \\    print(out, total)
    \\    return 0
    \\
    \\
    \\func frames(stdin: Input, out: Stream) -> int:
    \\    mut whole = 0
    \\    while True:
    \\        match stdin.read_exact(1000):
    \\            case Some(_):
    \\                whole += 1
    \\            case None:
    \\                print(out, whole)
    \\                return 0
    \\
    \\
    \\func main(args: str[], stdin: Input, out: Stream) -> int:
    \\    if args[0] == "lines":
    \\        return lines(stdin, out)
    \\    if args[0] == "chunks":
    \\        return chunks(stdin, out)
    \\    if args[0] == "frames":
    \\        return frames(stdin, out)
    \\    print(out, stdin.read(-1))
    \\    return 0
;

const InputRun = struct { term: std.process.Child.Term, stdout: []u8, stderr: []u8 };

/// Run a built program with `input` as its standard input (a closed descriptor when null) and capture its output.
fn runWithInput(dir: std.Io.Dir, program: []const u8, mode: []const u8, input: ?[]const u8) !InputRun {
    if (input) |data| try dir.writeFile(testing.io, .{ .sub_path = "stdin.dat", .data = data });
    const absolute = try dir.realPathFileAlloc(testing.io, program, testing.allocator);
    defer testing.allocator.free(absolute);
    const fed = if (input != null) try dir.openFile(testing.io, "stdin.dat", .{}) else null;
    defer if (fed) |file| file.close(testing.io);
    const output = try dir.createFile(testing.io, "stdout.dat", .{});
    defer output.close(testing.io);
    const failure = try dir.createFile(testing.io, "stderr.dat", .{});
    defer failure.close(testing.io);
    var child = try std.process.spawn(testing.io, .{
        .argv = &.{ absolute, mode },
        .stdin = if (fed) |file| .{ .file = file } else .close,
        .stdout = .{ .file = output },
        .stderr = .{ .file = failure },
    });
    defer child.kill(testing.io);
    const term = try child.wait(testing.io);
    const printed = try dir.readFileAlloc(testing.io, "stdout.dat", testing.allocator, .limited(1 << 20));
    errdefer testing.allocator.free(printed);
    const complaint = try dir.readFileAlloc(testing.io, "stderr.dat", testing.allocator, .limited(1 << 20));
    return .{ .term = term, .stdout = printed, .stderr = complaint };
}

/// `count` lines of 99 `x` and a newline.
fn hundredOctetLines(count: usize) ![]u8 {
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(testing.allocator);
    for (0..count) |_| {
        try text.appendNTimes(testing.allocator, 'x', 99);
        try text.append(testing.allocator, '\n');
    }
    return text.toOwnedSlice(testing.allocator);
}

fn freeInputRun(run: InputRun) void {
    testing.allocator.free(run.stdout);
    testing.allocator.free(run.stderr);
}

test "a program reads its standard input in lines, chunks and frames, across the buffer size, and a bad read traps R_INPUT" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = input_program });
    const built = try runInDirectory(temp.dir, &.{ compilerPath(), "build", "main.selka", "-o", "reader" });
    defer freeRun(built);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    // 3,000 lines of 100 octets cross the runtime's 64 KiB buffer several times, a line among them.
    const many = try hundredOctetLines(3000);
    defer testing.allocator.free(many);
    const lines = try runWithInput(temp.dir, "reader", "lines", many);
    defer freeInputRun(lines);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, lines.term);
    try testing.expectEqualStrings("3000 300000 100\n", lines.stdout);
    const chunks = try runWithInput(temp.dir, "reader", "chunks", many);
    defer freeInputRun(chunks);
    try testing.expectEqualStrings("300000\n", chunks.stdout);
    // 300,000 octets are 300 whole frames of 1,000; the end of the input then truncates nothing more.
    const frames = try runWithInput(temp.dir, "reader", "frames", many);
    defer freeInputRun(frames);
    try testing.expectEqualStrings("300\n", frames.stdout);
    const unfinished = try runWithInput(temp.dir, "reader", "lines", "a\nbb\nccc");
    defer freeInputRun(unfinished);
    try testing.expectEqualStrings("3 8 3\n", unfinished.stdout);
    const empty = try runWithInput(temp.dir, "reader", "lines", "");
    defer freeInputRun(empty);
    try testing.expectEqualStrings("0 0 0\n", empty.stdout);
    const refused = try runWithInput(temp.dir, "reader", "negative", "abc");
    defer freeInputRun(refused);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, refused.term);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "error[R_INPUT]: standard input could not be read: a read size cannot be negative") != null);
    const closed = try runWithInput(temp.dir, "reader", "lines", null);
    defer freeInputRun(closed);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, closed.term);
    try testing.expect(std.mem.indexOf(u8, closed.stderr, "error[R_INPUT]: standard input could not be read: Bad file descriptor") != null);
}

test "selka run reads standard input under --restrict too: an Input needs no grant" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = input_program });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "stdin.dat", .data = "one\ntwo\n" });
    const fed = try temp.dir.openFile(testing.io, "stdin.dat", .{});
    defer fed.close(testing.io);
    const output = try temp.dir.createFile(testing.io, "stdout.dat", .{});
    defer output.close(testing.io);
    const entry = try temp.dir.realPathFileAlloc(testing.io, "main.selka", testing.allocator);
    defer testing.allocator.free(entry);
    var child = try std.process.spawn(testing.io, .{
        .argv = &.{ compilerPath(), "run", entry, "--restrict", "--", "lines" },
        .stdin = .{ .file = fed },
        .stdout = .{ .file = output },
        .stderr = .ignore,
    });
    defer child.kill(testing.io);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try child.wait(testing.io));
    const printed = try temp.dir.readFileAlloc(testing.io, "stdout.dat", testing.allocator, .limited(4096));
    defer testing.allocator.free(printed);
    try testing.expectEqualStrings("2 8 4\n", printed);
}

test "dump-tokens --tables writes the tag names and reserved spellings and needs no file" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const tables = try runInDirectory(temp.dir, &.{ compilerPath(), "dump-tokens", "--tables" });
    defer freeRun(tables);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, tables.term);
    try testing.expect(std.mem.startsWith(u8, tables.stdout, "tokens-tables-v1\nkinds "));
    try testing.expect(std.mem.indexOf(u8, tables.stdout, "\nkeyword func kw_def\n") != null);
}

test "dump-syntax writes the framed payload, refused files too, and the layout without a file" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "p.selka", .data = "func main() -> int:\n    return 0\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "bad.selka", .data = "x = $" });
    const parsed = try runInDirectory(temp.dir, &.{ compilerPath(), "dump-syntax", "p.selka" });
    defer freeRun(parsed);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, parsed.term);
    try testing.expect(std.mem.startsWith(u8, parsed.stdout, "SLKSYN01"));
    try testing.expectEqual(@as(u8, 0), parsed.stdout[10]);
    const refused = try runInDirectory(temp.dir, &.{ compilerPath(), "dump-syntax", "bad.selka" });
    defer freeRun(refused);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, refused.term);
    try testing.expectEqual(@as(u8, 1), refused.stdout[10]);
    const forced = try runInDirectory(temp.dir, &.{ compilerPath(), "dump-syntax", "p.selka", "--module" });
    defer freeRun(forced);
    try testing.expectEqual(@as(u8, 1), forced.stdout[8]);
    const trusted = try runInDirectory(temp.dir, &.{ compilerPath(), "dump-syntax", "p.selka", "--trusted" });
    defer freeRun(trusted);
    try testing.expectEqual(@as(u8, 1), trusted.stdout[9]);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "same.frame", .data = parsed.stdout });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "other.frame", .data = trusted.stdout });
    const equal = try runInDirectory(temp.dir, &.{ compilerPath(), "dump-syntax", "--diff", "same.frame", "same.frame" });
    defer freeRun(equal);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, equal.term);
    try testing.expectEqualStrings("", equal.stdout);
    const told = try runInDirectory(temp.dir, &.{ compilerPath(), "dump-syntax", "--diff", "same.frame", "other.frame" });
    defer freeRun(told);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, told.term);
    try testing.expectEqualStrings("trusted: reference false, candidate true\n", told.stdout);
    const layout = try runInDirectory(temp.dir, &.{ compilerPath(), "dump-syntax", "--layout" });
    defer freeRun(layout);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, layout.term);
    try testing.expect(std.mem.startsWith(u8, layout.stdout, "syntax-layout-v1\n"));
    const both = try runInDirectory(temp.dir, &.{ compilerPath(), "dump-syntax", "--layout", "p.selka" });
    defer freeRun(both);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, both.term);
    const bare = try runInDirectory(temp.dir, &.{ compilerPath(), "dump-syntax" });
    defer freeRun(bare);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, bare.term);
}

/// Run one command from inside `dir` with the fixture tools appended and require
/// exit status `wanted`; the compiler path is made absolute for the changed cwd.
fn runToolIn(dir: std.Io.Dir, environ: ?*const std.process.Environ.Map, args: []const []const u8, wanted: u8) !void {
    const absolute = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
    defer testing.allocator.free(absolute);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.append(testing.allocator, absolute);
    try argv.appendSlice(testing.allocator, args);
    // Only the commands that build take the toolchain; the paths are made
    // absolute because the child runs in `dir`.
    var absolute_tools: [tools.len][]u8 = undefined;
    var resolved: usize = 0;
    defer for (absolute_tools[0..resolved]) |path| testing.allocator.free(path);
    const builds = std.mem.eql(u8, args[0], "test") or std.mem.eql(u8, args[0], "build") or std.mem.eql(u8, args[0], "run");
    if (builds) for (tools) |flag| {
        const equals = std.mem.indexOfScalar(u8, flag, '=').?;
        const path = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, flag[equals + 1 ..], testing.allocator);
        defer testing.allocator.free(path);
        absolute_tools[resolved] = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ flag[0 .. equals + 1], path });
        try argv.append(testing.allocator, absolute_tools[resolved]);
        resolved += 1;
    };
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = dir }, .environ_map = environ });
    defer freeRun(outcome);
    testing.expectEqual(std.process.Child.Term{ .exited = wanted }, outcome.term) catch |err| {
        std.debug.print("{s}\n{s}\n", .{ outcome.stdout, outcome.stderr });
        return err;
    };
}

const cache_program =
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, "hi")
    \\    return 0
    \\
    \\public func test_ok() -> bool:
    \\    return True
;

// spec: CLI-CACHE-DIR-1
test "test, build, run and check write no cache into the working directory under --cache-dir" {
    var work = testing.tmpDir(.{});
    defer work.cleanup();
    var cache = testing.tmpDir(.{});
    defer cache.cleanup();
    try work.dir.writeFile(testing.io, .{ .sub_path = "prog.selka", .data = cache_program });
    const cache_path = try cache.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(cache_path);
    const flag = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_path});
    defer testing.allocator.free(flag);
    try runToolIn(work.dir, null, &.{ "test", "prog.selka", "--force", flag }, 0);
    try runToolIn(work.dir, null, &.{ "build", "prog.selka", "-o", "prog.bin", flag }, 0);
    try runToolIn(work.dir, null, &.{ "run", "prog.selka", flag }, 0);
    try runToolIn(work.dir, null, &.{ "check", "prog.selka", flag }, 0);
    try runToolIn(work.dir, null, &.{ "check-project", "prog.selka", "--explain-invalidation", flag }, 0);
    try testing.expectError(error.FileNotFound, work.dir.statFile(testing.io, ".selka-cache", .{}));
    // The named directory took the frontend cache instead.
    _ = try cache.dir.statFile(testing.io, "frontend", .{});
}

// spec-case: CLI-CACHE-DIR-1
test "SELKA_FRONTEND_CACHE moves the checked-body store and invalidation baseline out of the working directory" {
    var work = testing.tmpDir(.{});
    defer work.cleanup();
    var cache = testing.tmpDir(.{});
    defer cache.cleanup();
    try work.dir.writeFile(testing.io, .{ .sub_path = "prog.selka", .data = cache_program });
    const cache_path = try cache.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(cache_path);
    // The test asserts the private checked-body store is written; a shared
    // compiler store could serve those bodies instead.
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    defer environment.deinit();
    try environment.put("SELKA_FRONTEND_CACHE", cache_path);
    try runToolIn(work.dir, &environment, &.{ "check", "prog.selka" }, 0);
    try runToolIn(work.dir, &environment, &.{ "check-project", "prog.selka", "--explain-invalidation" }, 0);
    try testing.expectError(error.FileNotFound, work.dir.statFile(testing.io, ".selka-cache", .{}));
    // A check keeps no typed trees (G2o), so the checked-body store (`semantic`) is not written; the front-end store and the baseline are.
    _ = try cache.dir.statFile(testing.io, "frontend", .{});
    _ = try cache.dir.statFile(testing.io, "invalidation", .{});
}

const borrow_error_program =
    // migrate-embedded: skip intentional cached borrowed caller storage diagnostic input
    \\public enum Error:
    \\    Incomplete
    \\    Malformed(value: str)
    \\    Unsupported(value: str)
    \\
    \\public func message(error: Error) -> str from error:
    \\    match error:
    \\        case Incomplete:
    \\            return "incomplete message"
    \\        case Malformed(value=detail):
    \\            return detail
    \\        case Unsupported(value=detail):
    \\            return detail
    \\
    \\func main(out: Stream) -> int:
    \\    const found = message(Error.Malformed(value="m"))
    \\    mut kept = message(Error.Malformed(value="n"))
    \\    kept = kept + "!"
    \\    print(out, found, kept)
    \\    return 0
;

/// `borrow_error_program` with the caller's `mut` binding of the borrowed result repaired.
const borrow_fixed_program =
    \\public enum Error:
    \\    Incomplete
    \\    Malformed(value: str)
    \\    Unsupported(value: str)
    \\
    \\public func message(error: Error) -> str from error:
    \\    match error:
    \\        case Incomplete:
    \\            return "incomplete message"
    \\        case Malformed(value=detail):
    \\            return detail
    \\        case Unsupported(value=detail):
    \\            return detail
    \\
    \\func main(out: Stream) -> int:
    \\    const found = message(Error.Malformed(value="m"))
    \\    const kept = message(Error.Malformed(value="n"))
    \\    print(out, found, kept)
    \\    return 0
;

/// Write `source` as prog.selka in `dir` and run `check` on it with `environment`, requiring exit `wanted`. Returns the
/// stderr, which the caller frees, so two checks of one program can be compared byte for byte.
fn checkBorrowProgram(dir: std.Io.Dir, environment: *const std.process.Environ.Map, source: []const u8, wanted: u8) ![]u8 {
    try dir.writeFile(testing.io, .{ .sub_path = "prog.selka", .data = source });
    const absolute = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
    defer testing.allocator.free(absolute);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ absolute, "check", "prog.selka" }, .cwd = .{ .dir = dir }, .environ_map = environment });
    defer testing.allocator.free(outcome.stdout);
    errdefer testing.allocator.free(outcome.stderr);
    testing.expectEqual(std.process.Child.Term{ .exited = wanted }, outcome.term) catch |err| {
        std.debug.print("{s}\n", .{outcome.stderr});
        return err;
    };
    return outcome.stderr;
}

// A cached check of a program with a caller error gives the cold check's diagnostics, and the repaired program
// checks clean through the same cache: the callee's borrowed payload return is not an overlap (R2 publication).
test "a cached re-check of a borrowed-payload callee keeps the cold check's diagnostics" {
    var work = testing.tmpDir(.{});
    defer work.cleanup();
    var cache = testing.tmpDir(.{});
    defer cache.cleanup();
    const cache_path = try cache.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(cache_path);
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    defer environment.deinit();
    try environment.put("SELKA_FRONTEND_CACHE", cache_path);
    const cold = try checkBorrowProgram(work.dir, &environment, borrow_error_program, 1);
    defer testing.allocator.free(cold);
    const cached = try checkBorrowProgram(work.dir, &environment, borrow_error_program, 1);
    defer testing.allocator.free(cached);
    try testing.expectEqualStrings(cold, cached);
    try testing.expect(std.mem.indexOf(u8, cold, "E_SINGLE_OWNER_BORROW") != null);
    try testing.expect(std.mem.indexOf(u8, cold, "ownership rule R3") != null);
    try testing.expect(std.mem.indexOf(u8, cold, "E_SINGLE_OWNER_OVERLAP") == null);
    const repaired = try checkBorrowProgram(work.dir, &environment, borrow_fixed_program, 0);
    defer testing.allocator.free(repaired);
    try testing.expect(std.mem.indexOf(u8, repaired, "error[") == null);
    try testing.expect(std.mem.indexOf(u8, repaired, "check: ok") != null);
}

/// A program whose three-owner borrowed results are refused as stored, bound and returned: the migration must take
/// each repair the checker offers, and the cold and cached migrations must write the same file.
const three_owner_program =
    // migrate-embedded: skip intentional FIX-MIGRATION-1 three-owner borrowed result before input
    \\import dicts
    \\
    \\
    \\func bound_len(outer: dict[str, dict[str, dict[str, int]]], middle: dict[str, dict[str, int]], fallback: dict[str, int]) -> int:
    \\    const inner = dicts.get(dicts.get(outer, "a", middle), "b", fallback)
    \\    return len(inner)
    \\
    \\
    \\func stored_len(outer: dict[str, dict[str, dict[str, int]]], middle: dict[str, dict[str, int]], fallback: dict[str, int]) -> int:
    \\    mut kept = dicts.get(dicts.get(outer, "a", middle), "b", fallback)
    \\    kept["z"] = 1
    \\    return len(kept)
    \\
    \\
    \\func returned_value(outer: dict[str, dict[str, dict[str, int]]], middle: dict[str, dict[str, int]], fallback: dict[str, int]) -> dict[str, int]:
    \\    return dicts.get(dicts.get(outer, "a", middle), "b", fallback)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut outer: dict[str, dict[str, dict[str, int]]] = {}
    \\    mut middle: dict[str, dict[str, int]] = {}
    \\    mut fallback: dict[str, int] = {}
    \\    fallback["x"] = 3
    \\    print(out, bound_len(outer, middle, fallback), stored_len(outer, middle, fallback), len(returned_value(outer, middle, fallback)))
    \\    return 0
    \\
;

// Three owners of one borrowed result: `selka fix` takes each repair the checker offers and converges cold and cached,
// and the two migrated files are byte-identical, and the migrated program checks clean.
test "selka fix converges on a three-owner borrowed result, cold and cached, to the same file" {
    var work = testing.tmpDir(.{});
    defer work.cleanup();
    var cache = testing.tmpDir(.{});
    defer cache.cleanup();
    const cache_path = try cache.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(cache_path);
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    defer environment.deinit();
    try environment.put("SELKA_FRONTEND_CACHE", cache_path);
    const flag = "--no-cache";
    try work.dir.writeFile(testing.io, .{ .sub_path = "cold.selka", .data = three_owner_program });
    try runToolIn(work.dir, null, &.{ "fix", "cold.selka", flag }, 0);
    try work.dir.writeFile(testing.io, .{ .sub_path = "cached.selka", .data = three_owner_program });
    try runToolIn(work.dir, &environment, &.{ "fix", "cached.selka" }, 0);
    try runToolIn(work.dir, null, &.{ "check", "cold.selka", flag }, 0);
    const cold = try work.dir.readFileAlloc(testing.io, "cold.selka", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(cold);
    const cached = try work.dir.readFileAlloc(testing.io, "cached.selka", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(cached);
    try testing.expectEqualStrings(cold, cached);
    try testing.expect(std.mem.indexOf(u8, cold, "copy(dicts.get(") != null);
}

const trivial_run =
    \\func main(out: Stream) -> int:
    \\    print(out, "ok")
    \\    return 0
;

/// Run `selka run` on the trivial program with `options` and, when the run is
/// refused, require exit 2 with `expected` inside the diagnostic on stderr.
fn expectRunRefused(options: []const []const u8, environ: ?*const std.process.Environ.Map, expected: []const u8) !void {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "prog.selka", .data = trivial_run });
    const path = try temp.dir.realPathFileAlloc(testing.io, "prog.selka", testing.allocator);
    defer testing.allocator.free(path);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.appendSlice(testing.allocator, &.{ compilerPath(), "run", path });
    try argv.appendSlice(testing.allocator, options);
    try argv.appendSlice(testing.allocator, &tools);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .environ_map = environ });
    defer freeRun(outcome);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, outcome.term);
    try testing.expectEqualStrings("", outcome.stdout);
    testing.expect(std.mem.indexOf(u8, outcome.stderr, expected) != null) catch |err| {
        std.debug.print("expected {s} in:\n{s}\n", .{ expected, outcome.stderr });
        return err;
    };
}

// spec: RUN-FLAGS-1
test "run takes every budget in both spellings and prints its own usage for a bad flag" {
    try invokeOptions("run", trivial_run, &.{ "--max-steps", "1000000", "--max-frames", "5000", "--timeout", "60", "--max-memory", "1G" }, 0, "ok\n0\n", "");
    try invokeOptions("run", trivial_run, &.{ "--max-steps=1000000", "--max-frames=5000", "--timeout=60", "--max-memory=1G" }, 0, "ok\n0\n", "");
    for ([_][]const []const u8{ &.{"--bogus"}, &.{"--max-frames"}, &.{ "--max-frames", "0" }, &.{ "--max-steps", "many" }, &.{ "--max-memory", "12x" }, &.{ "--timeout", "-3" } }) |bad| {
        try expectRunRefused(bad, null, "usage: selka run <file.selka> [options] [-- ARGS...]");
    }
    try expectRunRefused(&.{"--bogus"}, null, "--max-frames N     call-depth ceiling");
    // The general text opens with the `test` usage; `run` must not print it.
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "prog.selka", .data = trivial_run });
    const path = try temp.dir.realPathFileAlloc(testing.io, "prog.selka", testing.allocator);
    defer testing.allocator.free(path);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "run", path, "--bogus" } });
    defer freeRun(outcome);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "selka test <entry.selka>") == null);
}

// spec: RUN-FRAME-BUDGET-1
test "a call-depth budget the memory ceiling cannot back is refused up front with what it needs" {
    // 150000 frames reserve 4.6 GiB, more than the default 4G ceiling holds.
    try expectRunRefused(&.{"--max-frames=150000"}, null, "a call-depth budget of 150000 frames (--max-frames) reserves 4.6 GiB of native stack (32 KiB per frame), but a guest may map only 4.3 GiB");
    try expectRunRefused(&.{ "--max-frames", "150000" }, null, "raise --max-memory to at least 5G, or lower --max-frames to at most 137984");
    // The same budget with a ceiling that holds it runs.
    try invokeOptions("run", trivial_run, &.{ "--max-frames", "30000", "--max-memory", "2G" }, 0, "ok\n0\n", "");
}

// spec-case: RUN-FRAME-BUDGET-1
test "test refuses a frame budget its per-test ceiling cannot back and accepts one it can" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "prog.selka", .data = cache_program });
    const refused = try runInDirectory(temp.dir, &.{ compilerPath(), "test", "prog.selka", "--max-frames", "30000" });
    defer freeRun(refused);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, refused.term);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "selka test: a call-depth budget of 30000 frames (--max-frames) reserves 946 MiB of native stack (32 KiB per frame), but a test may map only 768 MiB") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "raise --max-memory to at least 1G") != null);
    try runToolIn(temp.dir, null, &.{ "test", "prog.selka", "--force", "--max-frames", "30000", "--max-memory", "1G" }, 0);
}

// spec-case: RUN-FRAME-BUDGET-1
test "a built program reports the frame reservation its address space cannot back" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const output = try buildExecutable(&temp, trivial_run);
    defer testing.allocator.free(output);
    var environment = try runtimeOptions("--max-frames=150000");
    defer environment.deinit();
    try environment.put("SELKA_MEMORY_LIMIT", "1G");
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{output}, .environ_map = &environment });
    defer freeRun(outcome);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "a call-depth budget of 150000 frames (--max-frames) reserves 4.6 GiB of native stack (32 KiB per frame), but this process may map only 1.2 GiB") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "OutOfMemory: QBE runtime failure") == null);
}

/// Write `selka.json` and the trivial program into `dir`, one project.
fn writeLimitedProject(dir: std.Io.Dir, limits: []const u8) !void {
    const config = try std.fmt.allocPrint(testing.allocator, "{{\"version\":1,\"limits\":{s}}}", .{limits});
    defer testing.allocator.free(config);
    try dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = config });
    try dir.writeFile(testing.io, .{ .sub_path = "prog.selka", .data = cache_program });
}

/// Run `command prog.selka` in `dir` and return its outcome; the caller frees it.
fn runLimited(dir: std.Io.Dir, args: []const []const u8) !std.process.RunResult {
    const absolute = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), testing.allocator);
    defer testing.allocator.free(absolute);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.append(testing.allocator, absolute);
    try argv.appendSlice(testing.allocator, args);
    var absolute_tools: [tools.len][]u8 = undefined;
    for (tools, &absolute_tools) |flag, *slot| {
        const equals = std.mem.indexOfScalar(u8, flag, '=').?;
        const path = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, flag[equals + 1 ..], testing.allocator);
        defer testing.allocator.free(path);
        slot.* = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ flag[0 .. equals + 1], path });
        try argv.append(testing.allocator, slot.*);
    }
    defer for (absolute_tools) |path| testing.allocator.free(path);
    return std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = dir } });
}

// spec: PROJECT-LIMITS-1
test "selka.json limits set the run and test defaults and the command line still wins" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    // A configured frame budget the default ceiling cannot back is refused exactly as the flag is.
    try writeLimitedProject(temp.dir, "{\"run\":{\"max_frames\":150000},\"test\":{\"max_frames\":30000}}");
    const configured = try runLimited(temp.dir, &.{ "run", "prog.selka" });
    defer freeRun(configured);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, configured.term);
    try testing.expect(std.mem.indexOf(u8, configured.stderr, "a call-depth budget of 150000 frames (--max-frames) reserves 4.6 GiB") != null);
    // The flag overrides the file: 5000 frames fit, and the program runs.
    const overridden = try runLimited(temp.dir, &.{ "run", "prog.selka", "--max-frames", "5000" });
    defer freeRun(overridden);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, overridden.term);
    try testing.expectEqualStrings("hi\n", overridden.stdout);
    // Guest arguments after `--` are untouched by configured options.
    const guest = try runLimited(temp.dir, &.{ "run", "prog.selka", "--max-frames=5000", "--", "--max-frames=1" });
    defer freeRun(guest);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, guest.term);
    // `selka test` reads `limits.test` the same way.
    const tests_refused = try runLimited(temp.dir, &.{ "test", "prog.selka", "--force" });
    defer freeRun(tests_refused);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, tests_refused.term);
    try testing.expect(std.mem.indexOf(u8, tests_refused.stderr, "selka test: a call-depth budget of 30000 frames") != null);
    const tests_overridden = try runLimited(temp.dir, &.{ "test", "prog.selka", "--force", "--max-frames=1024" });
    defer freeRun(tests_overridden);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, tests_overridden.term);
    // A configured max_memory that holds the configured budget lets both commands run it.
    try writeLimitedProject(temp.dir, "{\"run\":{\"max_frames\":30000,\"max_memory\":\"2G\"},\"test\":{\"max_frames\":30000,\"max_memory\":\"1G\"}}");
    const run_ok = try runLimited(temp.dir, &.{ "run", "prog.selka" });
    defer freeRun(run_ok);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run_ok.term);
    const test_ok = try runLimited(temp.dir, &.{ "test", "prog.selka", "--force" });
    defer freeRun(test_ok);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, test_ok.term);
}

test {
    _ = @import("fix_cli_test.zig");
    _ = @import("do_cli_test.zig");
    _ = @import("rename_cli_test.zig");
    _ = @import("fix_wave1_effects_test.zig");
    _ = @import("fix_wave1_declarations_test.zig");
    _ = @import("fix_wave1_control_expressions_test.zig");
    _ = @import("fix_wave1_repetition_test.zig");
    _ = @import("fix_wave1_lambda_test.zig");
    _ = @import("fix_wave1_comprehensions_test.zig");
    _ = @import("fix_wave1_tuple_test.zig");
    _ = @import("fix_wave1_list_membership_test.zig");
    _ = @import("fix_wave1_domain_test.zig");
    _ = @import("fix_wave1_negative_index_test.zig");
    _ = @import("fix_wave3_text_test.zig");
    _ = @import("fix_wave3_fixes_test.zig");
    _ = @import("library_trap_cli_test.zig");
    _ = @import("fix_wave2_w_test.zig");
    _ = @import("wave1_cleanup_k1_test.zig");
    _ = @import("wave1_cleanup_k2_test.zig");
    _ = @import("wave1_cleanup_k4_test.zig");
}

// spec-case: EMBED-2
test "check reports an embed's diagnostic at its literal and exits nonzero" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "func main() -> int:\n    return len(embed_bytes(\"absent.bin\"))\n" });
    const entry = try std.fs.path.join(a, &.{ root, "main.selka" });
    const result = try std.process.run(a, testing.io, .{ .argv = &.{ compilerPath(), "check", entry } });
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "main.selka:2:28: error[E_EMBED_MISSING]") != null);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "absent.bin", .data = "x" });
    const found = try std.process.run(a, testing.io, .{ .argv = &.{ compilerPath(), "check", entry } });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, found.term);
}

// spec-case: EMBED-3
test "selka test runs a module that embeds and reruns it when only the fixture changes" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    try temporary.dir.createDirPath(testing.io, "fixtures");
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "fixtures/nul.bin", .data = "a\x00b" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "emb.selka", .data = "\nconst NUL: bytes = embed_bytes(\"fixtures/nul.bin\")\n\n\npublic func test_nul() -> bool:\n    return len(NUL) == 3 and NUL[1] == 0\n" });
    const entry = try std.fs.path.join(a, &.{ root, "emb.selka" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const argv = [_][]const u8{ compilerPath(), "test", entry, "--cache-dir", cache, tools[0] };
    const first = try privateRun(a, &argv);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    try testing.expect(std.mem.indexOf(u8, first.stdout, "passed emb::test_nul") != null);
    const again = try privateRun(a, &argv);
    try testing.expect(std.mem.indexOf(u8, again.stdout, "cached emb::test_nul") != null);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "fixtures/nul.bin", .data = "a\x00bc" });
    const changed = try privateRun(a, &argv);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, changed.term);
    try testing.expect(std.mem.indexOf(u8, changed.stdout, "failed emb::test_nul") != null);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "fixtures/nul.bin", .data = "a\x00b" });
    const restored = try privateRun(a, &argv);
    try testing.expect(std.mem.indexOf(u8, restored.stdout, "cached emb::test_nul") != null);
}

/// Exercise a real guest reservation and, optionally, a caller's soft ceiling.
fn expectGuestFrames(frames: []const u8, external: bool, expected_status: u8) !void {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "prog.selka", .data = trivial_run });
    const path = try temp.dir.realPathFileAlloc(testing.io, "prog.selka", a);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", a);
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    var environment = try std.process.Environ.createMap(testing.environ, a);
    try environment.put("SELKA_HOST_MEMORY_LIMIT", if (external) "4G" else "8G");
    var argv: std.ArrayList([]const u8) = .empty;
    if (external) try argv.appendSlice(a, &.{ "sh", "-c", "ulimit -S -v 6291456; exec \"$@\"", "caller-limit" });
    try argv.appendSlice(a, &.{ compilerPath(), "run", path, frames, "--max-memory=12G", "--print-result", try std.fmt.allocPrint(a, "--cache-dir={s}", .{cache}) });
    try argv.appendSlice(a, &tools);
    const result = try std.process.run(a, testing.io, .{ .argv = argv.items, .environ_map = &environment });
    testing.expectEqual(std.process.Child.Term{ .exited = expected_status }, result.term) catch |err| {
        std.debug.print("guest frame preflight: {s}\n{s}\n", .{ result.stdout, result.stderr });
        return err;
    };
    if (expected_status == 0) {
        try testing.expectEqualStrings("ok\n0\n", result.stdout);
        try testing.expectEqualStrings("", result.stderr);
    } else {
        try testing.expect(std.mem.indexOf(u8, result.stderr, "this process inherited an address-space limit below --max-memory") != null);
        try testing.expect(std.mem.indexOf(u8, result.stderr, "raise the caller's RLIMIT_AS") != null);
    }
}

// spec-case: MEMORY-HOST-GUEST-1
test "CLI guest frame preflight permits a restored compiler limit and preserves a caller limit" {
    try expectGuestFrames("--max-frames=300000", false, 0);
    try expectGuestFrames("--max-frames=160000", true, 0);
    try expectGuestFrames("--max-frames=300000", true, 2);
}

const embed_tooling_source =
    \\
    \\const DATA: bytes = embed_bytes("data.bin")
    \\
    \\public func measure[T](value: T) -> int:
    \\    return len(DATA)
    \\
    \\func main() -> int:
    \\    return measure(1)
;

/// Invoke a file-backed tooling frontend over the temporary embedded project.
fn embeddedTool(allocator: std.mem.Allocator, command: []const u8, entry: []const u8, extra: []const []const u8) !std.process.RunResult {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(allocator, &.{ compilerPath(), command, entry });
    try argv.appendSlice(allocator, extra);
    return std.process.run(allocator, testing.io, .{ .argv = argv.items });
}

// spec-case: EMBED-CONTEXT-1
// spec-case: EMBED-3
// spec-case: EMBED-PROJECT-BUDGET-1
test "CLI embedded inputs reach context and generic schema and obey project byte budgets" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = embed_tooling_source });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "data.bin", .data = "abcd" });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", a);
    const answer = try embeddedTool(a, "context", entry, &.{ "--symbol", "main::main" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, answer.term);
    const first = try std.json.parseFromSliceLeaky(std.json.Value, a, answer.stdout, .{});
    const file = first.object.get("snapshot").?.object.get("embeds").?.array.items[0];
    try testing.expectEqualStrings("data.bin", file.object.get("path").?.string);
    try testing.expectEqual(@as(i64, 4), file.object.get("bytes").?.integer);
    const schema = try embeddedTool(a, "schema-project", entry, &.{});
    testing.expectEqual(std.process.Child.Term{ .exited = 0 }, schema.term) catch |err| {
        std.debug.print("embedded schema: {s}\n", .{schema.stderr});
        return err;
    };
    try testing.expect(std.mem.indexOf(u8, schema.stdout, "measure") != null);
    try testing.expect(std.mem.indexOf(u8, schema.stdout, "generic_templates") != null);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "data.bin", .data = "dcba" });
    const edited = try embeddedTool(a, "context", entry, &.{ "--symbol", "main::main" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, edited.term);
    const second = try std.json.parseFromSliceLeaky(std.json.Value, a, edited.stdout, .{});
    try testing.expect(!std.mem.eql(u8, first.object.get("snapshot_sha256").?.string, second.object.get("snapshot_sha256").?.string));
    const total = embed_tooling_source.len + 3;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = try std.fmt.allocPrint(a, "{{\"version\":1,\"budgets\":{{\"max_total_bytes\":{d}}}}}", .{total}) });
    const refused = try embeddedTool(a, "check-project", entry, &.{"--diagnostics=json"});
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, refused.term);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "E_PROJECT_BYTES") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "max_total_bytes") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "data.bin") != null);
}

// spec-case: RUN-FRAME-BUDGET-1
test "CLI rejects an unaddressable native frame reservation without a compiler panic" {
    try invokeOptions("run", trivial_run, &.{"--max-frames=562949953421312"}, 2, "", "exceeds the addressable native stack size");
}

// spec-case: MEMORY-HOST-GUEST-1
test "CLI directory tests forward the installed host receipt when modes are already normalized" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "public func test_ok() -> bool:\n    return True\n" });
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    var environment = try @import("test_paths").privateEnvironment(a);
    try environment.put("SELKA_HOST_MEMORY_LIMIT", "8G");
    _ = environment.swapRemove("SELKA_HOST_LIMIT_CHECKPOINT");
    _ = environment.swapRemove("SELKA_HOST_LIMIT_RESTORE");
    const result = try std.process.run(a, testing.io, .{ .argv = &(.{ compilerPath(), "test", root, "--max-memory=12G", "--max-frames=300000", "--jobs=1", "--cache-dir", cache } ++ tools), .environ_map = &environment });
    testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term) catch |err| {
        std.debug.print("directory host receipt: {s}\n{s}\n", .{ result.stdout, result.stderr });
        return err;
    };
    try testing.expect(std.mem.indexOf(u8, result.stdout, "1 passed") != null);
}

/// Write a one-test project in a temporary directory and return its absolute path.
fn memoryCeilingProject(a: std.mem.Allocator, temporary: *testing.TmpDir) ![]const u8 {
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "public func test_ok() -> bool:\n    return True\n" });
    return temporary.dir.realPathFileAlloc(testing.io, ".", a);
}

// spec-case: MEMORY-HOST-GUEST-1
test "CLI test holds the compiler and its build tools to the host ceiling and names it when they run out" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try memoryCeilingProject(a, &temporary);
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    var environment = try @import("test_paths").privateEnvironment(a);
    _ = environment.swapRemove("SELKA_HOST_LIMIT_CHECKPOINT");
    _ = environment.swapRemove("SELKA_HOST_LIMIT_RESTORE");
    // No object is cached, so the build must run `zig cc`, which inherits the ceiling. The runtime store is the test's own, so the
    // runtime object is compiled by `zig cc` too: the recipe processes of a store that has them (`zig clang`, `zig ld.lld`) are much
    // lighter than `zig cc` and fit a ceiling it does not.
    try environment.put("SELKA_CORE_RUNTIME_CACHE", try std.fs.path.join(a, &.{ root, "runtime" }));
    const argv = .{ compilerPath(), "test", root, "--jobs=1", "--no-cache", "--cache-dir", cache } ++ tools;
    try environment.put("SELKA_HOST_MEMORY_LIMIT", "16M");
    const bounded = try std.process.run(a, testing.io, .{ .argv = &argv, .environ_map = &environment });
    // The run ends by itself, with a failure status and the ceiling's name, not by a signal.
    try testing.expect(bounded.term == .exited and bounded.term.exited != 0);
    testing.expect(std.mem.indexOf(u8, bounded.stdout, "SELKA_HOST_MEMORY_LIMIT") != null or std.mem.indexOf(u8, bounded.stderr, "SELKA_HOST_MEMORY_LIMIT") != null) catch |err| {
        std.debug.print("bounded compiler did not name its ceiling: {s}\n{s}\n", .{ bounded.stdout, bounded.stderr });
        return err;
    };
    try testing.expect(std.mem.indexOf(u8, bounded.stdout, "1 passed") == null);
    // The same run without a ceiling passes.
    try environment.put("SELKA_HOST_MEMORY_LIMIT", "0");
    const unbounded = try std.process.run(a, testing.io, .{ .argv = &argv, .environ_map = &environment });
    testing.expectEqual(std.process.Child.Term{ .exited = 0 }, unbounded.term) catch |err| {
        std.debug.print("unbounded compiler: {s}\n{s}\n", .{ unbounded.stdout, unbounded.stderr });
        return err;
    };
    try testing.expect(std.mem.indexOf(u8, unbounded.stdout, "1 passed") != null);
}

// spec-case: MEMORY-HOST-GUEST-1
test "CLI test of one file still gives its test processes more address space than the compiler's ceiling" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try memoryCeilingProject(a, &temporary);
    const entry = try std.fs.path.join(a, &.{ root, "main.selka" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    var environment = try @import("test_paths").privateEnvironment(a);
    _ = environment.swapRemove("SELKA_HOST_LIMIT_CHECKPOINT");
    _ = environment.swapRemove("SELKA_HOST_LIMIT_RESTORE");
    try environment.put("SELKA_HOST_MEMORY_LIMIT", "8G");
    // 300000 frames reserve about 9.2 GiB of stack: more than the compiler's 8 GiB and less than the test's 12 GiB.
    const result = try std.process.run(a, testing.io, .{ .argv = &(.{ compilerPath(), "test", entry, "--max-memory=12G", "--max-frames=300000", "--cache-dir", cache } ++ tools), .environ_map = &environment });
    testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term) catch |err| {
        std.debug.print("test of one file under a host ceiling: {s}\n{s}\n", .{ result.stdout, result.stderr });
        return err;
    };
    try testing.expect(std.mem.indexOf(u8, result.stdout, "1 passed") != null);
}

/// Put the files of an initialized test-receipt namespace under `root`: `count` receipts and the format marker.
fn writeReceiptNamespace(root: std.Io.Dir, count: usize) !void {
    var name: [96]u8 = undefined;
    try root.createDirPath(testing.io, "native-tests-v3/receipts");
    try root.writeFile(testing.io, .{ .sub_path = "native-tests-v3/format", .data = "selka-native-test-store-v3\n" });
    try root.writeFile(testing.io, .{ .sub_path = "native-tests-v3/.retention.lock", .data = "" });
    for (0..count) |index| {
        const receipt = try std.fmt.bufPrint(&name, "native-tests-v3/receipts/{x:0>64}.pass", .{index});
        try root.writeFile(testing.io, .{ .sub_path = receipt, .data = "x" });
    }
}

/// How many receipts of a namespace `writeReceiptNamespace` made are still there.
fn receiptsLeft(root: std.Io.Dir, count: usize) !usize {
    var name: [96]u8 = undefined;
    var left: usize = 0;
    for (0..count) |index| {
        const receipt = try std.fmt.bufPrint(&name, "native-tests-v3/receipts/{x:0>64}.pass", .{index});
        _ = root.statFile(testing.io, receipt, .{}) catch continue;
        left += 1;
    }
    return left;
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "CLI cache gc previews by default and reports what it visited, would remove and leaves" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try writeReceiptNamespace(temporary.dir, 3);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const preview = try std.process.run(a, testing.io, .{ .argv = &.{ compilerPath(), "cache", "gc", "--shared-cache-dir", root, "--kind", "tests", "--max-entries", "1" } });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, preview.term);
    // Six entries visited, none unseen: the format marker, the lock and the receipts directory, and three receipts.
    try testing.expect(std.mem.indexOf(u8, preview.stdout, "\"dry_run\":true") != null);
    try testing.expect(std.mem.indexOf(u8, preview.stdout, "\"removed\":{\"entries\":2,") != null);
    try testing.expect(std.mem.indexOf(u8, preview.stdout, "\"retained\":{\"entries\":1,") != null);
    try testing.expect(std.mem.indexOf(u8, preview.stdout, "\"inventory_complete\":true,\"visited\":6,\"unvisited\":0}") != null);
    try testing.expectEqual(@as(usize, 3), try receiptsLeft(temporary.dir, 3));
    const applied = try std.process.run(a, testing.io, .{ .argv = &.{ compilerPath(), "cache", "gc", "--shared-cache-dir", root, "--kind", "tests", "--max-entries", "1", "--apply" } });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, applied.term);
    try testing.expect(std.mem.indexOf(u8, applied.stdout, "\"dry_run\":false") != null);
    try testing.expectEqual(@as(usize, 1), try receiptsLeft(temporary.dir, 3));
}

const snapshot_embed_main = "import data\n\nconst A: bytes = embed_bytes(\"data.bin\")\nconst B: bytes = embed_bytes(\"data.bin\")\n\nfunc main() -> int:\n    return 0\n\npublic func test_payload() -> bool:\n    return A == b\"abcd\" and B == A and data.C == A\n";
const snapshot_embed_data = "\npublic const C: bytes = embed_bytes(\"data.bin\")\n";

/// Run a real snapshot test and preserve the located budget diagnostic on refusal.
fn expectSnapshotBudget(allocator: std.mem.Allocator, entry: []const u8, cache: []const u8, expected_status: u8) !void {
    const result = try privateRun(allocator, &(.{ compilerPath(), "test", entry, "--cache-dir", cache, "--force" } ++ tools));
    testing.expectEqual(std.process.Child.Term{ .exited = expected_status }, result.term) catch |err| {
        std.debug.print("snapshot embed budget: {s}\n{s}\n", .{ result.stdout, result.stderr });
        return err;
    };
    if (expected_status == 0) {
        try testing.expect(std.mem.indexOf(u8, result.stdout, "passed main::test_payload") != null);
    } else {
        try testing.expect(std.mem.indexOf(u8, result.stderr, "E_PROJECT_BYTES") != null);
        try testing.expect(std.mem.indexOf(u8, result.stderr, "data.bin") != null);
    }
}

// spec-case: EMBED-PROJECT-BUDGET-1
test "CLI test retains exact embedded budgets and recaptures tightened and widened policy" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = snapshot_embed_main });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "data.selka", .data = snapshot_embed_data });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "data.bin", .data = "abcd" });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", a);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const total = snapshot_embed_main.len + snapshot_embed_data.len + 8;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = try std.fmt.allocPrint(a, "{{\"version\":1,\"budgets\":{{\"max_total_bytes\":{d}}}}}", .{total}) });
    try expectSnapshotBudget(a, entry, cache, 0);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = try std.fmt.allocPrint(a, "{{\"version\":1,\"budgets\":{{\"max_total_bytes\":{d}}}}}", .{total - 1}) });
    try expectSnapshotBudget(a, entry, cache, 1);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = try std.fmt.allocPrint(a, "{{\"version\":1,\"budgets\":{{\"max_total_bytes\":{d}}}}}", .{total}) });
    try expectSnapshotBudget(a, entry, cache, 0);
    const oversized = try temporary.dir.createFile(testing.io, "data.bin", .{});
    defer oversized.close(testing.io);
    try oversized.setLength(testing.io, 1024 * 1024);
    try expectSnapshotBudget(a, entry, cache, 1);
}

// spec-case: EMBED-PROJECT-BUDGET-1
test "CLI provider replacements recapture embedded fixture edits with a warm test cache" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try writeProjectFile(&temporary, "main.selka", "import dependency\n\npublic func test_fixture() -> bool:\n    return dependency.value() == 7\n");
    try writeProjectFile(&temporary, "dependency.selka", "\npublic func value() -> int:\n    return 7\n");
    try writeProjectFile(&temporary, "fixture.selka", "\npublic const DATA: bytes = embed_bytes(\"fixture.bin\")\n");
    try writeProjectFile(&temporary, "fixture.bin", "1234567");
    try r3WriteCases(&temporary, "cases.json", "main::test_fixture", "dependency.selka", "import fixture\n\npublic func value() -> int:\n    return len(fixture.DATA)\n");
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.selka", a);
    const cases = try temporary.dir.realPathFileAlloc(testing.io, "cases.json", a);
    const cache = try std.fs.path.join(a, &.{ std.fs.path.dirname(entry).?, "cache" });
    const first = try r3TestInvoke(entry, cases, cache);
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term) catch |err| {
        std.debug.print("provider embedded fixture: {s}\n{s}\n", .{ first.stdout, first.stderr });
        return err;
    };
    try testing.expect(std.mem.indexOf(u8, first.stdout, "\"passed\":1") != null);
    try writeProjectFile(&temporary, "fixture.bin", "12345678");
    const changed = try r3TestInvoke(entry, cases, cache);
    defer testing.allocator.free(changed.stdout);
    defer testing.allocator.free(changed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, changed.term);
    try testing.expect(std.mem.indexOf(u8, changed.stdout, "\"failed\":1") != null);
}

// spec-case: DIAGNOSTIC-JSON-1
test "CLI native build forwards diagnostic presentation to its source frontend" {
    try invokeOptions("build", "func main() -> int:\n    return False\n", &.{ "--run", "--diagnostics=json" }, 1, "", "\"code\":\"E_TYPE\"");
}

test {}

const s5_loop =
    \\func main() -> int:
    \\    mut i = 0
    \\    while True:
    \\        i = i + 1
    \\    return i
;

// spec: NEW-CORE-S5-RUN-1
test "run on the new core keeps the exit, argument, budget and grant contract" {
    try invokeOptions("run", "func main() -> int:\n    return 300\n", &.{}, 0, "300\n", "");
    try invoke("run", "func main() -> int:\n    mut xs = [1]\n    return xs[3]\n", 1, "", "error[R_LIST_BOUNDS]");
    try invokeOptions("run", "func main(args: str[], out: Stream) -> int:\n    print(out, len(args), args[1])\n    return 0\n", &.{ "--", "--release", "b" }, 0, "2 b\n0\n", "");
    try invokeOptions("run", s5_loop, &.{"--max-steps=1000"}, 1, "", "R_STEP_LIMIT");
    // A counting loop can be optimized directly to its eventual overflow trap.
    const endless = "func main() -> int:\n    while True:\n        pass\n    return 0\n";
    try invokeOptions("run", endless, &.{ "--timeout", "1" }, 1, "", "R_TIMEOUT");
    const deep = "func down(n: int) -> int:\n    if n == 0:\n        return 0\n    return down(n - 1) + 1\n\nfunc main() -> int:\n    return down(100000)\n";
    try invokeOptions("run", deep, &.{"--max-frames=100"}, 1, "", "R_FRAME_LIMIT");
    const grow = "func main() -> int:\n    mut xs: int[] = []\n    mut i = 0\n    while i < 100000000:\n        append(mut xs, i)\n        i = i + 1\n    return len(xs)\n";
    try invokeOptions("run", grow, &.{"--max-memory=16M"}, 1, "", "R_MEMORY_BUDGET");
    try invokeOptions("run", "func main(rng: Entropy) -> int:\n    _ = rng\n    return 0\n", &.{"--restrict"}, 2, "", "pass --allow-random");
    try invokeOptions("run", "func main() -> int:\n    return 0\n", &.{"--allow-read="}, 2, "", "usage: selka run");
}

// spec: NEW-CORE-S5-RETIRED-1
test "the old back end's commands and flags are refused by name with what replaces them" {
    const program = "func main() -> int:\n    return 0\n";
    try invoke("invoke", program, 2, "", "retired with host functions");
    try invoke("emit-qbe", program, 2, "", "QBE IL emission was retired");
    try invoke("dump-bytecode", program, 2, "", "selka dump-ir");
    try invokeOptions("run", program, &.{"--gc-stress"}, 2, "", "retired (S5-D4)");
    try invokeOptions("check", program, &.{"--legacy-sharing"}, 2, "", "value semantics is the only mode");
    try invokeOptions("test", program, &.{"--bench=x"}, 2, "", "dropped with the old test runner (S5-D6)");
    try invokeOptions("run", program, &.{"--explain-invalidation"}, 2, "", "retired, S5-B2");
}

// spec: NEW-CORE-S5-ARENA-1
test "an arena block is rejected with its targeted removal diagnostic" {
    const program = "func main() -> int:\n    mut total = 0\n    with arena():\n        mut xs = [1, 2, 3]\n        total = len(xs)\n    return total\n";
    try invoke("check", program, 1, "", "error[E_ARENA_REMOVED]");
    try invoke("run", program, 1, "", "remove the `with arena():` line");
}

// spec: NEW-CORE-S5-CHECK-1
test "check of a project entry checks the merged program and writes no per-module records" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = "import helper\n\nfunc main() -> int:\n    return helper.two()\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = "\npublic func two() -> int:\n    return \"two\"\n" });
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.selka" });
    defer testing.allocator.free(entry);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{root});
    defer testing.allocator.free(cache);
    const rejected = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check", entry, cache } });
    defer testing.allocator.free(rejected.stdout);
    defer testing.allocator.free(rejected.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, rejected.term);
    try testing.expect(std.mem.indexOf(u8, rejected.stderr, "helper.selka:3:") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.selka", .data = "\npublic func two() -> int:\n    return 2\n" });
    const accepted = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "check", entry, cache } });
    defer testing.allocator.free(accepted.stdout);
    defer testing.allocator.free(accepted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, accepted.term);
    try check_line.expectPassed(accepted.stderr);
    try testing.expectError(error.FileNotFound, temp.dir.statFile(testing.io, "cache/modules", .{}));
}

// spec: NEW-CORE-S5-CONTRACT-1
test "a broken precondition traps with the old core's description of the clause" {
    const program = "@requires(amount > 10)\nfunc half(amount: int) -> int:\n    return amount // 2\n\nfunc main() -> int:\n    return half(4)\n";
    try invoke("run", program, 1, "", "error[R_REQUIRES]: precondition violated: half requires `amount > 10`");
    try invoke("run", "func main() -> int:\n    assert 1 > 2, \"never\"\n    return 0\n", 1, "", "error[R_ASSERT]: native execution failed: never");
}

// spec: NEW-CORE-S5-TEST-1
test "a test whose result is not bool fails its case and the run" {
    const outcome = try runFixture("test", "public func test_bad() -> int:\n    return 1\n\npublic func test_ok() -> bool:\n    return True\n", &.{});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stdout, "failed input::test_bad: test result type is not bool") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stdout, "passed input::test_ok") != null);
}

// spec: FRONTEND-INTERFACE-COST-1
test "CLI list-interfaces --cost output appends exact release costs without changing the default listing" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data =
        \\public func changed(xs: int[]) -> int[]:
        \\    mut ys = copy(xs)
        \\    ys[0] = 4
        \\    return ys
        \\public func unused() -> int:
        \\    return 9
        \\func main(out: Stream) -> int:
        \\    mut xs = [1]
        \\    print(out, changed(xs))
        \\    return 0
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "input.selka", testing.allocator);
    defer testing.allocator.free(path);
    const plain = try contractCommand(&.{ compilerPath(), "list-interfaces", path });
    defer freeResult(plain);
    try testing.expectEqualStrings("", plain.stderr);
    try testing.expect(std.mem.indexOf(u8, plain.stdout, "export function unused") != null);
    const cost = try contractCommand(&.{ compilerPath(), "cost", path });
    defer freeResult(cost);
    try testing.expect(std.mem.indexOf(u8, cost.stdout, "changed: checks") != null);
    try testing.expect(std.mem.indexOf(u8, cost.stdout, "unused:") == null);
    try testing.expect(std.mem.indexOf(u8, cost.stdout, "TOTAL:") != null);
    const listed = try contractCommand(&.{ compilerPath(), "list-interfaces", path, "--cost" });
    defer freeResult(listed);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, listed.term);
    try testing.expectEqualStrings(plain.stdout, listed.stdout[0..plain.stdout.len]);
    try testing.expectEqualStrings(cost.stdout, listed.stdout[plain.stdout.len..]);
    const again = try contractCommand(&.{ compilerPath(), "list-interfaces", path });
    defer freeResult(again);
    try testing.expectEqualStrings(plain.stdout, again.stdout);
    try testing.expectEqualStrings("", again.stderr);
    try invokeOptions("check", "module input", &.{"--cost"}, 2, "", "usage:");
    try invokeOptions("list-interfaces", "module input", &.{ "--cost", "--cost" }, 2, "", "usage:");
    try invokeOptions("list-interfaces", "module input", &.{ "--cost", "--contracts" }, 2, "", "usage:");
    try invokeOptions("list-interfaces", "module input", &.{ "--contracts", "--cost" }, 2, "", "usage:");
    try invokeOptions("list-interfaces",
        \\public func main() -> int:
        \\    return unknown()
    , &.{"--cost"}, 1, "", "unknown");
}

/// A program whose `read` probes a read-only borrowed dictionary: `table` borrows the record's field.
const borrowed_dictionary_probe =
    \\record Holder:
    \\    table: dict[str, int]
    \\func read(h: Holder, key: str) -> int:
    \\    const table = h.table
    \\    return table[key]
    \\func main(out: Stream) -> int:
    \\    mut table: dict[str, int] = {"a": 3}
    \\    const h = Holder(table=own table)
    \\    print(out, read(h, "a"))
    \\    return 0
;

/// Two noalloc functions that probe read-only borrowed dictionaries with an integer key and a text key.
const borrowed_dictionary_probe_noalloc =
    \\record Holder:
    \\    ints: dict[int, int]
    \\    words: dict[str, int]
    \\@noalloc
    \\func int_probe(h: Holder, key: int) -> int:
    \\    const table = h.ints
    \\    return table[key]
    \\@noalloc
    \\func text_probe(h: Holder, key: str) -> int:
    \\    const table = h.words
    \\    return table[key]
    \\func main(out: Stream) -> int:
    \\    mut ints: dict[int, int] = {1: 3}
    \\    mut words: dict[str, int] = {"a": 4}
    \\    const h = Holder(ints=own ints, words=own words)
    \\    print(out, int_probe(h, 1) + text_probe(h, "a"))
    \\    return 0
;

// spec-case: FRONTEND-COST-1
test "CLI cost, cost --sites, list-interfaces --cost, run --stats and lint classify a probe of a borrowed dictionary" {
    const read_row = "read: checks 0 kept / 0 proved; updates 0 in place; allocations 0 (0 unresolved)";
    const cost = try runFixture("cost", borrowed_dictionary_probe, &.{});
    defer freeResult(cost);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cost.term);
    try testing.expect(std.mem.indexOf(u8, cost.stdout, read_row) != null);
    const sites = try runFixture("cost", borrowed_dictionary_probe, &.{"--sites"});
    defer freeResult(sites);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, sites.term);
    try testing.expect(std.mem.indexOf(u8, sites.stdout, read_row) != null);
    // The text key stays a view: no copy of it is made for the probe.
    try testing.expect(std.mem.indexOf(u8, sites.stdout, "hidden copies: 0\n") != null);
    const listed = try runFixture("list-interfaces", borrowed_dictionary_probe, &.{"--cost"});
    defer freeResult(listed);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, listed.term);
    try testing.expect(std.mem.indexOf(u8, listed.stdout, read_row) != null);
    const stats = try runFixture("run", borrowed_dictionary_probe, &.{"--stats"});
    defer freeResult(stats);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, stats.term);
    try testing.expect(std.mem.indexOf(u8, stats.stderr, "selka-core: cost: 0 checks kept; ") != null);
    const linted = try runFixture("lint", borrowed_dictionary_probe, &.{});
    defer freeResult(linted);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, linted.term);
    try testing.expect(std.mem.indexOf(u8, linted.stdout, "lint: 0 finding(s)") != null);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "CLI run judges a noalloc probe of a borrowed dictionary by its key type" {
    const accepted = try runFixture("run", borrowed_dictionary_probe_noalloc, &.{});
    defer freeResult(accepted);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, accepted.term);
    try testing.expectEqualStrings("7\n0\n", accepted.stdout);
    try testing.expectEqualStrings("", accepted.stderr);
    const refused = try runFixture("run",
        \\record Point:
        \\    x: int
        \\    y: int
        \\record Holder:
        \\    table: dict[Point, int]
        \\@noalloc
        \\func read(h: Holder, key: Point) -> int:
        \\    const table = h.table
        \\    return table[key]
        \\func main() -> int:
        \\    return 0
    , &.{});
    defer freeResult(refused);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, refused.term);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "E_NOALLOC_ALLOCATES") != null);
}

// spec: FRONTEND-COST-1
test "CLI cost --sites adds source rows with inlined origin and loop depth and one cost-sites-v1 JSON" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "sites.selka", .data =
        \\func snapshot(xs: int[]) -> int[]:
        \\    return copy(xs)
        \\func main(out: Stream) -> int:
        \\    mut xs = [1, 2]
        \\    mut total = 0
        \\    for i in range(3):
        \\        mut ys = snapshot(xs)
        \\        total += len(ys)
        \\    print(out, total)
        \\    return 0
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "sites.selka", testing.allocator);
    defer testing.allocator.free(path);
    const text = try contractCommand(&.{ compilerPath(), "cost", path, "--sites" });
    defer freeResult(text);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, text.term);
    // The unchanged cost rows come first, then the site rows.
    try testing.expect(std.mem.indexOf(u8, text.stdout, "TOTAL:") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "cost-sites-v1 (static allocation and copy sites after Core passes)") != null);
    // The inlined copy keeps snapshot's source position and name inside main's loop.
    try testing.expect(std.mem.indexOf(u8, text.stdout, "sites.selka:2:12  snapshot  copy  written  loop 1  an independent copy: move the value, borrow a view, or copy once outside the loop") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "hidden copies: 0\n") != null);
    const json = try contractCommand(&.{ compilerPath(), "cost", path, "--sites", "--json" });
    defer freeResult(json);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, json.term);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json.stdout, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("cost-sites-v1", parsed.value.object.get("version").?.string);
    try testing.expect(parsed.value.object.get("functions").?.array.items.len > 0);
    try testing.expect(parsed.value.object.get("totals").? == .object);
    const sites = parsed.value.object.get("sites").?.array.items;
    try testing.expectEqual(@as(usize, 5), sites.len);
    try testing.expectEqualStrings("snapshot", sites[3].object.get("function").?.string);
    try testing.expectEqualStrings("sites.selka", std.fs.path.basename(sites[3].object.get("path").?.string));
    try testing.expectEqual(@as(i64, 2), sites[3].object.get("line").?.integer);
    try testing.expectEqualStrings("copy", sites[3].object.get("kind").?.string);
    // W4: the row keeps `written` and adds how the copy reads on the page.
    try testing.expect(sites[3].object.get("written").?.bool);
    try testing.expectEqualStrings("written", sites[3].object.get("label").?.string);
    try testing.expectEqual(@as(i64, 1), sites[3].object.get("loop_depth").?.integer);
    // FUNCTION selects report rows and site rows by the same name.
    const filtered = try contractCommand(&.{ compilerPath(), "cost", path, "snapshot", "--sites", "--json" });
    defer freeResult(filtered);
    const selected = try std.json.parseFromSlice(std.json.Value, testing.allocator, filtered.stdout, .{});
    defer selected.deinit();
    try testing.expectEqual(@as(usize, 2), selected.value.object.get("sites").?.array.items.len);
}

// spec-case: FRONTEND-COST-1
test "CLI cost --sites names unresolved calls, reports nested depth and is empty without sites" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "free.selka", .data =
        \\func main() -> int:
        \\    return 0
    });
    const free = try temporary.dir.realPathFileAlloc(testing.io, "free.selka", testing.allocator);
    defer testing.allocator.free(free);
    const empty = try contractCommand(&.{ compilerPath(), "cost", free, "--sites" });
    defer freeResult(empty);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, empty.term);
    try testing.expect(std.mem.endsWith(u8, empty.stdout, "cost-sites-v1 (static allocation and copy sites after Core passes)\nhidden copies: 0\n"));
    const empty_json = try contractCommand(&.{ compilerPath(), "cost", free, "--sites", "--json" });
    defer freeResult(empty_json);
    const empty_parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, empty_json.stdout, .{});
    defer empty_parsed.deinit();
    try testing.expectEqual(@as(usize, 0), empty_parsed.value.object.get("sites").?.array.items.len);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "nested.selka", .data =
        \\func main(args: str[], out: Stream) -> int:
        \\    mut total = 0
        \\    for i in range(3):
        \\        for j in range(2):
        \\            print(out, str(i + j))
        \\        total += i
        \\    print(out, total, len(args))
        \\    return 0
    });
    const nested = try temporary.dir.realPathFileAlloc(testing.io, "nested.selka", testing.allocator);
    defer testing.allocator.free(nested);
    const unresolved = try contractCommand(&.{ compilerPath(), "cost", nested, "--sites", "--json" });
    defer freeResult(unresolved);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, unresolved.term);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, unresolved.stdout, .{});
    defer parsed.deinit();
    const sites = parsed.value.object.get("sites").?.array.items;
    try testing.expectEqual(@as(usize, 1), sites.len);
    try testing.expectEqualStrings("unresolved call", sites[0].object.get("kind").?.string);
    try testing.expectEqual(@as(i64, 2), sites[0].object.get("loop_depth").?.integer);
    try testing.expectEqual(@as(i64, 5), sites[0].object.get("line").?.integer);
    // A counter run and site rows describe different things, so the flags do not combine.
    try invokeOptions("cost", "func main() -> int:\n    return 0\n", &.{ "--sites", "--counters", "x.json" }, 2, "", "usage:");
    try invokeOptions("cost", "func main() -> int:\n    return 0\n", &.{ "--sites", "absent" }, 2, "", "no reachable function");
}

test "CLI cost --clauses lists the probe's clamp clause proved and wrong's refuted, and build --stats totals them" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "probe.selka", .data =
        \\@ensures(result >= 0 and result < 3)
        \\func clamp(value: int) -> int:
        \\    if value < 0:
        \\        return 0
        \\    if value > 2:
        \\        return 2
        \\    return value
        \\
        \\@ensures(result >= 1)
        \\func wrong(value: int) -> int:
        \\    if value > 5:
        \\        return 0
        \\    return 0
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, clamp(7) + wrong(3))
        \\    return 0
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "probe.selka", testing.allocator);
    defer testing.allocator.free(path);
    const text = try contractCommand(&.{ compilerPath(), "cost", path, "--clauses" });
    defer freeResult(text);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, text.term);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "TOTAL:") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "clauses 2: 1 proved, 1 refuted, 0 kept;") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "probe.selka:1:10  ensures 1  clamp  `result >= 0 and result < 3`  proved  own 3/0/0") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "probe.selka:9:10  ensures 1  wrong  `result >= 1`  refuted  own 1/1/0") != null);
    const json = try contractCommand(&.{ compilerPath(), "cost", path, "wrong", "--clauses", "--json" });
    defer freeResult(json);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, json.term);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json.stdout, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("cost-clauses-v1", parsed.value.object.get("version").?.string);
    const rows = parsed.value.object.get("clauses").?.array.items;
    try testing.expectEqual(@as(usize, 1), rows.len);
    try testing.expectEqualStrings("refuted", rows[0].object.get("status").?.string);
    // Without facts every copy keeps its check.
    const unfolded = try contractCommand(&.{ compilerPath(), "cost", path, "--clauses", "--no-facts" });
    defer freeResult(unfolded);
    try testing.expect(std.mem.indexOf(u8, unfolded.stdout, "clauses 2: 0 proved, 0 refuted, 2 kept;") != null);
    // The build says the same in --stats, exits 0, and the refuted clause still traps when it runs.
    const stats = try contractCommand(&.{ compilerPath(), "run", path, "--stats" });
    defer freeResult(stats);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, stats.term);
    try testing.expect(std.mem.indexOf(u8, stats.stderr, "selka-core: clauses 2: 1 proved, 1 refuted, 0 kept;") != null);
    try testing.expect(std.mem.indexOf(u8, stats.stderr, "selka-core: refuted: ") != null);
    try testing.expect(std.mem.indexOf(u8, stats.stderr, "R_ENSURES") != null);
    try invokeOptions("cost", "func main() -> int:\n    return 0\n", &.{"--asserts"}, 2, "", "usage:");
    // A record has no function row; naming it selects its invariants.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "span.selka", .data =
        \\@invariant(self.lo <= self.hi)
        \\record Span:
        \\    lo: int
        \\    hi: int
        \\func main(args: str[]) -> int:
        \\    const s = Span(lo=len(args), hi=3)
        \\    return s.hi
    });
    const span = try temporary.dir.realPathFileAlloc(testing.io, "span.selka", testing.allocator);
    defer testing.allocator.free(span);
    const record = try contractCommand(&.{ compilerPath(), "cost", span, "Span", "--clauses" });
    defer freeResult(record);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, record.term);
    try testing.expect(std.mem.indexOf(u8, record.stdout, "span.selka:1:12  invariant 1  Span  `self.lo <= self.hi`  kept  own 0/0/1") != null);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "F1 check accepts direct and transitive noalloc allocations without warnings" {
    try invoke("check", "@noalloc\nfunc main() -> int:\n    const xs = [1]\n    return len(xs) - 1\n", 0, "", "");
    try invoke("check", "@noalloc\npublic func bounded(mut xs: int[]) -> Unit:\n    xs[0] = 1\n", 0, "", "");
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "F1 run rejects a violated noalloc contract before execution" {
    try invoke("run", "@noalloc\nfunc main() -> int:\n    const xs = [1]\n    return len(xs) - 1\n", 1, "", "error[E_NOALLOC_ALLOCATES]");
}

fn expectNoallocLint(profile: []const u8) !void {
    const outcome = try runFixture("lint", "@noalloc\npublic func bounded(mut xs: int[]) -> Unit:\n    append(mut xs, 1)\nfunc main() -> int:\n    return 0\n", &.{ "--gate", profile });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "L_NOALLOC_ALLOCATES") != null);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "F1 lint blocks noalloc allocations in every profile" {
    try expectNoallocLint("--profile=agent");
    try expectNoallocLint("--profile=strict");
    try expectNoallocLint("--profile=safety");
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "F1 lint accepts a reasoned noalloc waiver on a library declaration" {
    const outcome = try runFixture("lint", "# lint: allow noalloc-allocates reason=\"this benchmark measures list growth\"\n@noalloc\npublic func bounded(mut xs: int[]) -> Unit:\n    append(mut xs, 1)\n", &.{"--gate"});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "L_NOALLOC_ALLOCATES") == null);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "F1 test retries reject noalloc failures without reporting success" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.selka", .data = "@noalloc\nfunc bounded() -> int:\n    const xs = [1]\n    return len(xs)\npublic func test_one() -> bool:\n    return bounded() == 1\n" });
    for (0..2) |_| {
        const result = try runInDirectory(temp.dir, &(.{ compilerPath(), "test", "input.selka" } ++ tools));
        defer freeRun(result);
        try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, result.stderr, "error[E_NOALLOC_ALLOCATES]"));
        try testing.expectEqualStrings("", result.stdout);
    }
}

const unsupported_noalloc =
    \\import parallel
    \\func measure(value: bytes) -> int:
    \\    return len(value)
    \\@noalloc
    \\public func bounded(value: bytes) -> int:
    \\    with parallel.group() as group:
    \\        const job = group.submit(measure, value[0:2])
    \\        return job.result()
    \\@noalloc
    \\public func another(mut values: int[]) -> Unit:
    \\    append(mut values, 1)
    \\func main() -> int:
    \\    return 0
;

// spec-case: FRONTEND-CORE-NOALLOC-1
test "F1 unsupported unused bounded bodies fail with a reason and block lint" {
    try invoke("check", unsupported_noalloc, 0, "", "");
    try invoke("run", unsupported_noalloc, 1, "", "Core does not support a slice of bytes given to a task");
    const result = try runFixture("lint", unsupported_noalloc, &.{"--gate"});
    defer freeRun(result);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, result.term);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, result.stderr, "L_NOALLOC_ALLOCATES"));
    try testing.expect(std.mem.indexOf(u8, result.stderr, "Core does not support a slice of bytes given to a task") != null);
}

// spec-case: PARSE-RECOVERY-1
test "F3 project and module checks report both recovered syntax errors" {
    const source = "public func first() -> int:\n    const x = )\n    return 0\n\npublic func second() -> int:\n    const x = )\n    return 0\n";
    for ([_][]const u8{ "check", "check-project" }) |command| {
        const result = try runFixture(command, source, &.{});
        defer freeRun(result);
        try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
        try testing.expectEqual(@as(usize, 2), std.mem.count(u8, result.stderr, "error["));
        try testing.expect(std.mem.indexOf(u8, result.stderr, ":2:15:") != null);
        try testing.expect(std.mem.indexOf(u8, result.stderr, ":6:15:") != null);
        const structured = try runFixture(command, source, &.{"--diagnostics=json"});
        defer freeRun(structured);
        try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, structured.term);
        try testing.expectEqual(@as(usize, 2), std.mem.count(u8, structured.stderr, "\"kind\":\"diagnostic\""));
        try testing.expect(std.mem.indexOf(u8, structured.stderr, "\"line\":2,\"column\":15") != null);
        try testing.expect(std.mem.indexOf(u8, structured.stderr, "\"line\":6,\"column\":15") != null);
    }
}

// spec-case: PARSE-RECOVERY-1
test "F3 project migration edits belong to their own diagnostic" {
    const result = try runFixture("check", "public func first() -> int:\n    x = 1\n    return x\n\npublic func second() -> int:\n    y = 2\n    return y\n", &.{"--diagnostics=json"});
    defer freeRun(result);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    var lines = std.mem.tokenizeScalar(u8, result.stderr, '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, line, .{});
        defer parsed.deinit();
        const data = parsed.value.object.get("diagnostic").?;
        try testing.expectEqualStrings("E_BINDING_DECLARATION", data.object.get("code").?.string);
        try testing.expectEqual(@as(usize, 1), data.object.get("fix").?.object.get("edits").?.array.items.len);
        count += 1;
    }
    try testing.expectEqual(@as(usize, 2), count);
}

// spec: FRONTEND-FORMAT-STDLIB-1
test "F8 formatter accepts the exact standard library sources that check accepts" {
    for ([_][]const u8{ "environment", "filesystem", "math", "network", "random", "time" }) |name| {
        const path = try std.fmt.allocPrint(testing.allocator, "src/stdlib/{s}.selka", .{name});
        defer testing.allocator.free(path);
        const checked = try contractCommand(&.{ compilerPath(), "check", path });
        defer freeResult(checked);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
        const formatted = try contractCommand(&.{ compilerPath(), "fmt", path, "--check" });
        defer freeResult(formatted);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, formatted.term);
        try testing.expectEqualStrings("", formatted.stderr);
    }
}

// spec-case: INTERNAL-NAME-1
test "F8 formatter rejects internal intrinsics in an ordinary source named math" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "math.selka", .data = "func main() -> float:\n    return __float_sqrt(4.0)\n" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "math.selka", testing.allocator);
    defer testing.allocator.free(path);
    const result = try contractCommand(&.{ compilerPath(), "fmt", path, "--check" });
    defer freeResult(result);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "E_INTERNAL_NAME") != null);
}

// spec-case: INTERNAL-NAME-1
test "F8 formatter withholds standard library trust when any source bytes differ" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const original = try std.Io.Dir.cwd().readFileAlloc(testing.io, "src/stdlib/math.selka", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(original);
    const changed = try std.fmt.allocPrint(testing.allocator, "{s}\n", .{original});
    defer testing.allocator.free(changed);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "math.selka", .data = changed });
    const path = try temp.dir.realPathFileAlloc(testing.io, "math.selka", testing.allocator);
    defer testing.allocator.free(path);
    for ([_][]const u8{ "fmt", "fmt-module" }) |command| {
        const result = try contractCommand(&.{ compilerPath(), command, path, "--check" });
        defer freeResult(result);
        try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
        try testing.expect(std.mem.indexOf(u8, result.stderr, "E_INTERNAL_NAME") != null);
    }
}

// A bytes read past the end of its view traps like an out-of-range index, with the offset and the view's length.
test "a fixed-width read that runs past the end of a view traps with the list bounds report" {
    try invoke("check",
        \\import bytes
        \\import strings
        \\
        \\func tail(data: bytes) -> u32:
        \\    return bytes.read_u32_be(data, 3)
        \\
        \\func main(out: Stream) -> int:
        \\    const data = strings.encode("ABCDEFGH")
        \\    print(out, tail(data[0:6]))
        \\    return 0
    , 0, "", "");
    try invoke("run",
        \\import bytes
        \\import strings
        \\
        \\func tail(data: bytes) -> u32:
        \\    return bytes.read_u32_be(data, 3)
        \\
        \\func main(out: Stream) -> int:
        \\    const data = strings.encode("ABCDEFGH")
        \\    print(out, tail(data[0:6]))
        \\    return 0
    , 1, "", "error[R_LIST_BOUNDS]: native execution failed (index 3, length 6)");
    try invoke("run",
        \\import bytes
        \\import strings
        \\
        \\func main(out: Stream) -> int:
        \\    const data = strings.encode("ABCD")
        \\    print(out, bytes.read_u16_le(data, -1))
        \\    return 0
    , 1, "", "error[R_LIST_BOUNDS]: native execution failed (index -1, length 4)");
}

const byte_read_guest =
    \\import bytes
    \\import strings
    \\
    \\func window(data: bytes) -> u32:
    \\    return bytes.read_u32_be(data, 1)
    \\
    \\func main(out: Stream) -> int:
    \\    const data = strings.encode("ABCDEFGH")
    \\    print(out, window(data))
    \\    return 0
;

// A big-endian read is one checked load and one byte swap in the optimized module, whatever the view it reads.
test "a big-endian u32 read of a view is one load and one byte swap in its emitted function" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "read.selka", .data = byte_read_guest });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "read.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const llvm = try std.fs.path.join(testing.allocator, &.{ root, "read.ll" });
    defer testing.allocator.free(llvm);
    const output = try std.fs.path.join(testing.allocator, &.{ root, "read" });
    defer testing.allocator.free(output);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{root});
    defer testing.allocator.free(cache);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", output, "--release", "--emit-llvm", llvm, cache, tools[0] }, "");
    const text = try temporary.dir.readFileAlloc(testing.io, "read.ll", testing.allocator, .limited(64 << 20));
    defer testing.allocator.free(text);
    const start = std.mem.indexOf(u8, text, "define internal fastcc i32 @\"my.bytes::read_u32_be\"") orelse return error.TestUnexpectedResult;
    const end = std.mem.indexOfPos(u8, text, start, "\n}\n") orelse return error.TestUnexpectedResult;
    const body = text[start..end];
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, "load i32, ptr"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, "call i32 @llvm.bswap.i32"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, "call void @myl_core_trap"));
}

/// A program whose final IR takes a record field, stores it back and leaves an emptied record: the shapes a
/// certificate has to state.
const certificate_guest =
    \\record Row:
    \\    items: int[]
    \\    name: str
    \\
    \\func grow(own r: Row) -> Row:
    \\    mut rows = own r
    \\    append(mut rows.items, 3)
    \\    return rows
    \\
    \\func main(out: Stream) -> int:
    \\    const r = Row(items=[1, 2], name="x")
    \\    const g = grow(own r)
    \\    print(out, len(g.items), g.name)
    \\    return 0
;

// spec-case: OWNERSHIP-CERTIFICATE-EXPORT-1
test "dump-ir --certificate prints the versioned certificate text, the same on every run" {
    const first = try runFixture("dump-ir", certificate_guest, &.{"--certificate"});
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    const second = try runFixture("dump-ir", certificate_guest, &.{"--certificate"});
    defer testing.allocator.free(second.stdout);
    defer testing.allocator.free(second.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    try testing.expect(std.mem.startsWith(u8, first.stdout, "ownership-certificate-v2\nclass param Parameter\n"));
    try testing.expect(std.mem.indexOf(u8, first.stdout, "function grow result owned from - unchecked -\nparam 0 %0 owned\n") != null);
    try testing.expect(std.mem.indexOf(u8, first.stdout, " record_get Project reads %0 consumes - state owned parents - slot f0\n") != null);
    try testing.expect(std.mem.indexOf(u8, first.stdout, " state emptied parents - slot f0 slots f0,f1\n") != null);
    try testing.expectEqualStrings(first.stdout, second.stdout);
}

/// Build `certificate_guest` into `directory` (relative to `root`) with `--emit-certificates`.
fn buildCertificates(root: []const u8, entry: []const u8, directory: []const u8, mode: []const u8) !void {
    const output = try std.fs.path.join(testing.allocator, &.{ root, "certified" });
    defer testing.allocator.free(output);
    const target = try std.fs.path.join(testing.allocator, &.{ root, directory });
    defer testing.allocator.free(target);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache-{s}", .{ root, directory });
    defer testing.allocator.free(cache);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", output, mode, "--emit-certificates", target, cache, tools[0] }, "");
}

// spec-case: OWNERSHIP-CERTIFICATE-EXPORT-1
test "build --emit-certificates writes one file per unit, byte-identical across builds, and a release build writes one program file" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "certified.selka", .data = certificate_guest });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "certified.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    try buildCertificates(root, entry, "first", "--optimize-debug");
    try buildCertificates(root, entry, "second", "--optimize-debug");
    var first = try temporary.dir.openDir(testing.io, "first", .{ .iterate = true });
    defer first.close(testing.io);
    var files: usize = 0;
    var walker = first.iterate();
    while (try walker.next(testing.io)) |item| {
        files += 1;
        try testing.expect(std.mem.endsWith(u8, item.name, ".certificate") or std.mem.endsWith(u8, item.name, ".fact-certificate") or std.mem.endsWith(u8, item.name, ".core-ir"));
        const one = try first.readFileAlloc(testing.io, item.name, testing.allocator, .limited(64 << 20));
        defer testing.allocator.free(one);
        var second = try temporary.dir.openDir(testing.io, "second", .{});
        defer second.close(testing.io);
        const two = try second.readFileAlloc(testing.io, item.name, testing.allocator, .limited(64 << 20));
        defer testing.allocator.free(two);
        try testing.expect(std.mem.startsWith(u8, one, "ownership-certificate-v2\n") or std.mem.startsWith(u8, one, "fact-certificate-v1\n") or std.mem.startsWith(u8, one, "core-ir-v1\n"));
        try testing.expectEqualStrings(one, two);
    }
    try testing.expect(files >= 1);
    try buildCertificates(root, entry, "whole", "--release");
    const whole = try temporary.dir.readFileAlloc(testing.io, "whole/program.certificate", testing.allocator, .limited(64 << 20));
    defer testing.allocator.free(whole);
    try testing.expect(std.mem.indexOf(u8, whole, "\nfunction main result scalar from - unchecked -\n") != null);
    // The final IR beside the certificates, for the Lean copy of the IR verifier: `selka verify-ir` accepts it.
    const ir_text = try temporary.dir.readFileAlloc(testing.io, "whole/program.core-ir", testing.allocator, .limited(64 << 20));
    defer testing.allocator.free(ir_text);
    try testing.expect(std.mem.startsWith(u8, ir_text, "core-ir-v1\n"));
    const ir_path = try std.fs.path.join(testing.allocator, &.{ root, "whole", "program.core-ir" });
    defer testing.allocator.free(ir_path);
    const verdict = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "verify-ir", ir_path } });
    defer testing.allocator.free(verdict.stdout);
    defer testing.allocator.free(verdict.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, verdict.term);
    try testing.expect(std.mem.indexOf(u8, verdict.stdout, " main accept\n") != null);
}

// spec-case: OWNERSHIP-PROOF-1
test "a build leaves in its certificate directory the certificates of that build and removes a stale one" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "program.selka", .data = certificate_guest });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "program.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    try temporary.dir.createDirPath(testing.io, "shared");
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "shared/module-old.certificate", .data = "ownership-certificate-v2\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "shared/notes.txt", .data = "kept" });
    try buildCertificates(root, entry, "shared", "--optimize-debug");
    try testing.expectError(error.FileNotFound, temporary.dir.statFile(testing.io, "shared/module-old.certificate", .{}));
    _ = try temporary.dir.statFile(testing.io, "shared/notes.txt", .{});
    try testing.expect(try countCertificates(temporary.dir, "shared") >= 1);
}

fn countCertificates(parent: std.Io.Dir, sub_path: []const u8) !usize {
    var opened = try parent.openDir(testing.io, sub_path, .{ .iterate = true });
    defer opened.close(testing.io);
    var certificates: usize = 0;
    var listing = opened.iterate();
    while (try listing.next(testing.io)) |item| certificates += @intFromBool(std.mem.endsWith(u8, item.name, ".certificate"));
    return certificates;
}

// spec-case: OWNERSHIP-CERTIFICATE-EXPORT-1
test "run refuses --emit-certificates, which only a build writes" {
    try invokeOptions("run", certificate_guest, &.{ "--emit-certificates", "somewhere" }, 2, "", "usage:");
}

// spec-case: OWNERSHIP-VALIDATOR-1
test "run --verify-ownership validates the functions the passes finish and says how many" {
    const outcome = try runFixture("run", certificate_guest, &.{"--verify-ownership"});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "selka: ownership: ") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, " functions validated, 0 unchecked\n") != null);
}

/// The final stage's hits and misses in the `cache-report-v1` line of `stderr` (`optimization_cache.Stage.final` is entry 5), and the
/// bodies a demand build served by their metadata alone (`bypassed`).
const FinalCounts = struct { hits: usize, misses: usize, bypassed: usize };

fn finalCounts(allocator: std.mem.Allocator, stderr: []const u8) !FinalCounts {
    const at = std.mem.indexOf(u8, stderr, "{\"version\":\"cache-report-v1\"") orelse return error.NoReport;
    const end = std.mem.indexOfScalarPos(u8, stderr, at, '\n') orelse stderr.len;
    const Report = struct { stages: struct { optimizer: struct { hits: []const usize, misses: []const usize, bypassed: usize } } };
    const parsed = try std.json.parseFromSlice(Report, allocator, stderr[at..end], .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const optimizer = parsed.value.stages.optimizer;
    return .{ .hits = optimizer.hits[5], .misses = optimizer.misses[5], .bypassed = optimizer.bypassed };
}

/// A build of `directory`/main.selka into `cache` with `--report`, as an optimised compiler builds by default
/// (`--validate-like-optimised`), with `extra`, and the stage store's shared half at `shared` when one is named.
fn validatingBuild(allocator: std.mem.Allocator, directory: []const u8, cache: []const u8, shared: ?[]const u8, extra: []const []const u8) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    try args.appendSlice(allocator, &.{ compilerPath(), "build", try std.fs.path.join(allocator, &.{ directory, "main.selka" }), "-o" });
    try args.appendSlice(allocator, &.{ try std.fs.path.join(allocator, &.{ directory, cache, "prog" }), try std.fmt.allocPrint(allocator, "--cache-dir={s}/{s}", .{ directory, cache }) });
    try args.appendSlice(allocator, &.{ "--report", "--validate-like-optimised" });
    try args.appendSlice(allocator, &tools);
    try args.appendSlice(allocator, extra);
    var environment = try @import("test_paths").privateEnvironment(allocator);
    if (shared) |root| try environment.put("SELKA_STAGE_SHARED_CACHE", root);
    return std.process.run(allocator, testing.io, .{ .argv = args.items, .environ_map = &environment });
}

// spec-case: OWNERSHIP-VALIDATOR-1
test "a debug and a release build validate by default, and a record a --no-validate build wrote is validated again before reuse" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = certificate_guest });
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    // The way out: no validator runs, and the final records it saves say so.
    const unvalidated = try validatingBuild(a, root, "work", null, &.{"--no-validate"});
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, unvalidated.term);
    // The default validates: it refuses every final record the way out saved and makes each again.
    const refused = try finalCounts(a, (try validatingBuild(a, root, "work", null, &.{})).stderr);
    try testing.expectEqual(@as(usize, 0), refused.hits + refused.bypassed);
    try testing.expect(refused.misses >= 2);
    // What it made it validated: after an edit elsewhere in the program, a validating build reuses those records.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = certificate_guest ++ "\nfunc unused() -> int:\n    return 7\n" });
    const reused = try finalCounts(a, (try validatingBuild(a, root, "work", null, &.{})).stderr);
    try testing.expect(reused.hits + reused.bypassed >= 2);
    // A release build validates by default too: it refuses the records a `--release --no-validate` build wrote.
    const release_first = try validatingBuild(a, root, "release", null, &.{ "--release", "--no-validate" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, release_first.term);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = certificate_guest });
    const release_again = try finalCounts(a, (try validatingBuild(a, root, "release", null, &.{"--release"})).stderr);
    try testing.expectEqual(@as(usize, 0), release_again.hits);
    try testing.expect(release_again.misses >= 2);
}

// spec-case: OWNERSHIP-VALIDATOR-1
test "a --no-validate build publishes nothing to the shared stage store, and validated records there serve another work directory" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = certificate_guest });
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const shared = try std.fs.path.join(a, &.{ root, "shared" });
    const unvalidated = try validatingBuild(a, root, "one", shared, &.{"--no-validate"});
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, unvalidated.term);
    // Nothing reached the shared half: a fresh work directory finds no final record and no body to serve by its metadata.
    const fresh = try finalCounts(a, (try validatingBuild(a, root, "two", shared, &.{})).stderr);
    try testing.expectEqual(@as(usize, 0), fresh.hits + fresh.bypassed);
    try testing.expect(fresh.misses >= 2);
    // That validating build published its validated records, which serve a third directory.
    const served = try finalCounts(a, (try validatingBuild(a, root, "three", shared, &.{})).stderr);
    try testing.expect(served.hits + served.bypassed >= 2);
    // The same holds of a release build: `--release --no-validate` publishes nothing, and a validating release build of
    // another work directory finds no record to reuse.
    const release_shared = try std.fs.path.join(a, &.{ root, "release-shared" });
    const quiet = try validatingBuild(a, root, "four", release_shared, &.{ "--release", "--no-validate" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, quiet.term);
    const release = try finalCounts(a, (try validatingBuild(a, root, "five", release_shared, &.{"--release"})).stderr);
    try testing.expectEqual(@as(usize, 0), release.hits);
    try testing.expect(release.misses >= 2);
}

// spec-case: OWNERSHIP-VALIDATOR-1
test "dump-ir --certificate --validate prints the certificate and counts the functions it validated" {
    const outcome = try runFixture("dump-ir", certificate_guest, &.{ "--certificate", "--validate" });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expect(std.mem.startsWith(u8, outcome.stdout, "ownership-certificate-v2\nclass param Parameter\n"));
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, " validated, 0 unchecked, 0 rejected\n") != null);
}

// spec-case: OWNERSHIP-VALIDATOR-1
test "test --verify-ownership runs a guest test with the validator on" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "checked.selka", .data = "public func test_grows() -> bool:\n    mut xs: int[] = [1]\n    append(mut xs, 2)\n    return len(xs) == 2\n" });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "checked.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/validator-cache", .{std.fs.path.dirname(entry).?});
    defer testing.allocator.free(cache);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "test", entry, "--verify-ownership", "--force", cache, tools[0] } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

const fact_guest =
    \\func total(n: int) -> int:
    \\    mut acc = 0
    \\    for i in range(n):
    \\        acc += i * 2
    \\    return acc
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, total(10))
    \\    return 0
;

// spec-case: FACT-CERTIFICATE-1
test "a release build with --emit-certificates writes a fact certificate that validate-fact-certificates accepts and removes a stale one" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "facts.selka", .data = fact_guest });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "facts.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    try temporary.dir.createDirPath(testing.io, "shared");
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "shared/old.fact-certificate", .data = "fact-certificate-v1\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "shared/notes.txt", .data = "kept" });
    try buildCertificates(root, entry, "shared", "--release");
    try testing.expectError(error.FileNotFound, temporary.dir.statFile(testing.io, "shared/old.fact-certificate", .{}));
    _ = try temporary.dir.statFile(testing.io, "shared/notes.txt", .{});
    const written = try temporary.dir.readFileAlloc(testing.io, "shared/program.fact-certificate", testing.allocator, .limited(64 << 20));
    defer testing.allocator.free(written);
    try testing.expect(std.mem.startsWith(u8, written, "fact-certificate-v1\n"));
    try testing.expect(std.mem.indexOf(u8, written, " proven a ") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\nsite %") != null);
    const directory = try std.fs.path.join(testing.allocator, &.{ root, "shared" });
    defer testing.allocator.free(directory);
    const verdicts = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "validate-fact-certificates", directory } });
    defer testing.allocator.free(verdicts.stdout);
    defer testing.allocator.free(verdicts.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, verdicts.term);
    try testing.expect(std.mem.indexOf(u8, verdicts.stdout, " total accept\n") != null);
    try testing.expect(std.mem.indexOf(u8, verdicts.stdout, "\nsummary files=1 functions=2 accept=2 reject=0 errors=0 ") != null);
}

// spec-case: FACT-CERTIFICATE-1
test "validate-fact-certificates reads a certificate through a link, as the facts half of the gate lays out the files it checks" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const exported = try runFixture("dump-ir", fact_guest, &.{"--fact-certificate"});
    defer testing.allocator.free(exported.stdout);
    defer testing.allocator.free(exported.stderr);
    try temporary.dir.createDirPath(testing.io, "real");
    try temporary.dir.createDirPath(testing.io, "linked");
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "real/program.fact-certificate", .data = exported.stdout });
    try temporary.dir.symLink(testing.io, "../real/program.fact-certificate", "linked/program.fact-certificate", .{});
    const directory = try temporary.dir.realPathFileAlloc(testing.io, "linked", testing.allocator);
    defer testing.allocator.free(directory);
    const verdicts = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "validate-fact-certificates", directory } });
    defer testing.allocator.free(verdicts.stdout);
    defer testing.allocator.free(verdicts.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, verdicts.term);
    try testing.expect(std.mem.indexOf(u8, verdicts.stdout, "\nsummary files=1 functions=2 accept=2 reject=0 errors=0 ") != null);
}

// spec-case: FACT-CERTIFICATE-1
test "run --verify-facts-static validates the fact tables and says how many functions and proven checks" {
    const outcome = try runFixture("run", fact_guest, &.{ "--release", "--verify-facts-static" });
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "selka: facts: ") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, " functions validated, 3 proven checks validated, 0 unchecked, 0 intervals assumed\n") != null);
}

// spec-case: FACT-CERTIFICATE-1
test "dump-ir --fact-certificate prints the same text on every run, and mutate-fact-certificates writes mutants it rejects" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const first = try runFixture("dump-ir", fact_guest, &.{"--fact-certificate"});
    defer testing.allocator.free(first.stdout);
    defer testing.allocator.free(first.stderr);
    const second = try runFixture("dump-ir", fact_guest, &.{"--fact-certificate"});
    defer testing.allocator.free(second.stdout);
    defer testing.allocator.free(second.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    try testing.expect(std.mem.startsWith(u8, first.stdout, "fact-certificate-v1\nfunction "));
    try testing.expectEqualStrings(first.stdout, second.stdout);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "program.fact-certificate", .data = first.stdout });
    const file = try temporary.dir.realPathFileAlloc(testing.io, "program.fact-certificate", testing.allocator);
    defer testing.allocator.free(file);
    const made = try std.fs.path.join(testing.allocator, &.{ std.fs.path.dirname(file).?, "mutants" });
    defer testing.allocator.free(made);
    const listing = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "mutate-fact-certificates", file, made } });
    defer testing.allocator.free(listing.stdout);
    defer testing.allocator.free(listing.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, listing.term);
    try testing.expect(std.mem.indexOf(u8, listing.stdout, " narrow_range ") != null);
    const refused = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "validate-fact-certificates", made } });
    defer testing.allocator.free(refused.stdout);
    defer testing.allocator.free(refused.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, refused.term);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, " reject F") != null);
}

// spec-case: OWNERSHIP-PROOF-1
test "validate-certificates prints a verdict per function and mutate-certificates writes mutants it rejects" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const exported = try runFixture("dump-ir", certificate_guest, &.{"--certificate"});
    defer testing.allocator.free(exported.stdout);
    defer testing.allocator.free(exported.stderr);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "program.certificate", .data = exported.stdout });
    const file = try temporary.dir.realPathFileAlloc(testing.io, "program.certificate", testing.allocator);
    defer testing.allocator.free(file);
    const root = std.fs.path.dirname(file).?;
    const verdicts = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "validate-certificates", file } });
    defer testing.allocator.free(verdicts.stdout);
    defer testing.allocator.free(verdicts.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, verdicts.term);
    try testing.expect(std.mem.indexOf(u8, verdicts.stdout, " grow accept\n") != null);
    try testing.expect(std.mem.indexOf(u8, verdicts.stdout, "\nsummary files=1 functions=") != null);
    const made = try std.fs.path.join(testing.allocator, &.{ root, "mutants" });
    defer testing.allocator.free(made);
    const listing = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "mutate-certificates", file, made } });
    defer testing.allocator.free(listing.stdout);
    defer testing.allocator.free(listing.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, listing.term);
    try testing.expect(std.mem.indexOf(u8, listing.stdout, " delete_drop ") != null);
    const refused = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "validate-certificates", made } });
    defer testing.allocator.free(refused.stdout);
    defer testing.allocator.free(refused.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, refused.term);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, " accept\n") == null);
    try testing.expect(std.mem.indexOf(u8, refused.stdout, " reject J") != null);
    const identity = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "validate-certificates", "--identity" } });
    defer testing.allocator.free(identity.stdout);
    defer testing.allocator.free(identity.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, identity.term);
    try testing.expectEqual(@as(usize, 65), identity.stdout.len);
}

// spec-case: OWNERSHIP-CERTIFICATE-EXPORT-1
test "asking for certificates changes neither the emitted LLVM nor the executable" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "same.selka", .data = certificate_guest });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "same.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const plain_ll = try std.fs.path.join(testing.allocator, &.{ root, "plain.ll" });
    defer testing.allocator.free(plain_ll);
    const asked_ll = try std.fs.path.join(testing.allocator, &.{ root, "asked.ll" });
    defer testing.allocator.free(asked_ll);
    const plain_bin = try std.fs.path.join(testing.allocator, &.{ root, "plain" });
    defer testing.allocator.free(plain_bin);
    const asked_bin = try std.fs.path.join(testing.allocator, &.{ root, "asked" });
    defer testing.allocator.free(asked_bin);
    const certificates = try std.fs.path.join(testing.allocator, &.{ root, "certificates" });
    defer testing.allocator.free(certificates);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{root});
    defer testing.allocator.free(cache);
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", plain_bin, "--emit-llvm", plain_ll, cache, tools[0] }, "");
    try expectConstantProcess(&.{ compilerPath(), "build", entry, "-o", asked_bin, "--emit-llvm", asked_ll, "--emit-certificates", certificates, cache, tools[0] }, "");
    const plain_text = try temporary.dir.readFileAlloc(testing.io, "plain.ll", testing.allocator, .limited(64 << 20));
    defer testing.allocator.free(plain_text);
    const asked_text = try temporary.dir.readFileAlloc(testing.io, "asked.ll", testing.allocator, .limited(64 << 20));
    defer testing.allocator.free(asked_text);
    try testing.expectEqualStrings(plain_text, asked_text);
    const plain_exe = try temporary.dir.readFileAlloc(testing.io, "plain", testing.allocator, .limited(256 << 20));
    defer testing.allocator.free(plain_exe);
    const asked_exe = try temporary.dir.readFileAlloc(testing.io, "asked", testing.allocator, .limited(256 << 20));
    defer testing.allocator.free(asked_exe);
    try testing.expect(std.mem.eql(u8, plain_exe, asked_exe));
}

test "a build that fails without diagnostics of its own prints one line naming the error and the stage store, and exits 2" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "quiet.selka", .data = "func main() -> int:\n    return 0\n" });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "quiet.selka", testing.allocator);
    defer testing.allocator.free(entry);
    const root = std.fs.path.dirname(entry).?;
    const output = try std.fs.path.join(testing.allocator, &.{ root, "quiet" });
    defer testing.allocator.free(output);
    // The LLVM text cannot be written into a directory that does not exist: the pipeline's WriteFailed, which carried no text.
    const llvm = try std.fs.path.join(testing.allocator, &.{ root, "missing", "quiet.ll" });
    defer testing.allocator.free(llvm);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{root});
    defer testing.allocator.free(cache);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compilerPath(), "build", entry, "-o", output, "--emit-llvm", llvm, cache } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, result.term);
    const expected = try std.fmt.allocPrint(testing.allocator, "selka: build failed (WriteFailed): a build output could not be written; stage store {s}/cache/stages-packed-v1\n", .{root});
    defer testing.allocator.free(expected);
    try testing.expect(std.mem.indexOf(u8, result.stderr, expected) != null);
}

const pinned_steps_program =
    \\func sum_thirds(n: int) -> int:
    \\    mut total = 0
    \\    for i in range(n):
    \\        if i % 3 == 0:
    \\            total = total + i
    \\    return total
    \\
    \\
    \\public func test_steps() -> bool:
    \\    const ok = sum_thirds(100) == 1683
    \\    return ok
    \\
;

fn pinnedRun(a: std.mem.Allocator, entry: []const u8, extra: []const []const u8) !std.process.RunResult {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ compilerPath(), "test", entry, "--no-cache" });
    try argv.appendSlice(a, extra);
    return privateRun(a, argv.items);
}

test "a test charges the steps the budget instrumentation has always charged, and traps one step short of them" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "pinned.selka", .data = pinned_steps_program });
    const entry = try temp.dir.realPathFileAlloc(testing.io, "pinned.selka", a);
    // 438 steps: one per executed block of `sum_thirds` and the test, as the whole-module instrumentation charged them (lane EM).
    // The test returns a bound result: `return a == b` as a test's last line gets R3-TESTMSG's operand report, one block more.
    const counted = try pinnedRun(a, entry, &.{"--json"});
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, counted.term);
    try testing.expect(std.mem.indexOf(u8, counted.stdout, "\"steps\":438") != null);
    const short = try pinnedRun(a, entry, &.{ "--max-steps", "437" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, short.term);
    try testing.expect(std.mem.indexOf(u8, short.stdout, "R_STEP_LIMIT") != null or std.mem.indexOf(u8, short.stderr, "R_STEP_LIMIT") != null);
    const enough = try pinnedRun(a, entry, &.{ "--max-steps", "438" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, enough.term);
}
