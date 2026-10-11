//! Spawn the selected-mode compiler binary; fixtures assert the public CLI contract.
const std = @import("std");
const testing = std.testing;
const compiler_path = @import("test_options").compiler_path;
test {
    _ = @import("components.zig");
    _ = @import("cache_retention_cli_test.zig");
}
// Mirror src/semantic_store.zig's directory format: this CLI test cannot
// import files outside its Zig module root.
const semantic_cache_version = "semantic-cache-v6";

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
    try invoke("check", "const S: str = \"hé🙂\"\nconst B: bytes = b\"\\x00\\xff\"\nfunc main() -> int:\n    return len(S) + len(B)\n", 0, "", "");
    try invoke("check", "const S: str = \"a\" + \"b\"\nfunc main() -> int:\n    return 0\n", 1, "", "E_CONSTANT_EXPRESSION");
    try invoke("check", "const B: bytes = OTHER\nconst OTHER: bytes = b\"x\"\nfunc main() -> int:\n    return 0\n", 1, "", "E_CONSTANT_EXPRESSION");
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
    try expectConstantProcess(&.{ compiler_path, "run", entry, cache_argument, tools[0] }, expected);
    try expectConstantProcess(&.{ compiler_path, "build", entry, "--run", "--cache-dir", cache, tools[0] }, expected);
    try expectConstantProcess(&.{ compiler_path, "build", entry, "--project", "-o", output, "--cache-dir", cache, tools[0] }, "");
    try expectConstantProcess(&.{output}, expected);
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
test "CLI managed constants import run build installed and invalidate warm caches" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\import constants
        \\func read[T]() -> str:
        \\    return constants.TEXT
        \\func main(out: Stream) -> int:
        \\    out.print(read[int]())
        \\    out.print(len(constants.DATA))
        \\    out.print(constants.DATA[1])
        \\    return 0
    });
    const original = "public const TEXT: str = \"hé🙂\"\npublic const DATA: bytes = b\"\\x00\\xff\"\n";
    try managedConstantModes(&temporary, original, "hé🙂\n2\n255\n");
    try managedConstantModes(&temporary, original, "hé🙂\n2\n255\n");
    // Same byte lengths, new contents: unchanged callers must observe the new IL.
    try managedConstantModes(&temporary, "public const TEXT: str = \"hà🙃\"\npublic const DATA: bytes = b\"\\x00\\xfe\"\n", "hà🙃\n2\n254\n");
}

// spec-case: NEW-CORE-S5-HOST-1
test "CLI refuses a retired host declaration at check time and names extern func" {
    try invoke("check", host_program, 1, "", "error[E_HOST_RETIRED]");
    try invoke("run", host_program, 1, "", "declare the function `extern func`");
}
// spec: HOST-CAPABILITY-1
test "CLI threads a Host capability through an extern call and runs it natively" {
    const source =
        \\extern func abs(host: Host, x: i32) -> i32 effects(host)
        \\
        \\
        \\func main(host: Host) -> i64:
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
        \\extern func copysign(host: Host, x: float, y: float) -> float effects(host)
        \\
        \\
        \\func nan_of(zero: float) -> float:
        \\    return zero / zero
        \\
        \\
        \\func main(host: Host, out: Stream) -> int:
        \\    mut nan = nan_of(0.0)
        \\    out.print(copysign(host, 1.0, nan), copysign(host, 1.0, -nan), copysign(host, 1.0, -2.0))
        \\    out.print(copysign(host, -nan, 1.0), copysign(host, nan, -1.0))
        \\    return 0
    ;
    try invokeOptions("run", source, &.{}, 0, "1.0 1.0 -1.0\nnan nan\n0\n", "");
}
// spec-case: HOST-CAPABILITY-1
test "CLI withholds Host under restrict and grants it with --allow-host" {
    const source =
        \\extern func abs(host: Host, x: i32) -> i32 effects(host)
        \\
        \\
        \\func main(host: Host) -> i64:
        \\    return i64(abs(host, -7))
    ;
    try invokeOptions("run", source, &.{"--restrict"}, 2, "", "--allow-host");
    try invokeOptions("run", source, &.{ "--restrict", "--allow-host" }, 0, "7\n", "");
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
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.my" });
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = seed });
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
        \\func main() -> i64:
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
        \\func helper(n: i64) -> i64:
        \\    return n + 1
        \\func main() -> i64:
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
        if (module > 0) try out.print("import m{d}\n", .{module - 1});
        try out.print("\n\npublic record Acc{d}:\n    total: int\n    count: int\n", .{module});
        var function: usize = 0;
        while (function < functions) : (function += 1) {
            const offset = if (module == 1 and function == 0) constant else module;
            try out.print("\n\npublic func f{d}_{d}(n: int) -> int:\n    mut xs: int[] = []\n    for k in range(n):\n        xs.append(k * {d} + {d})\n", .{ module, function, function + 1, offset });
            if (module == 0 and function == 0) try out.writeAll("    const spare = 1\n");
            try out.print("    mut acc = Acc{d}(total=0, count=0)\n    for x in xs:\n        acc = Acc{d}(total=acc.total + x, count=acc.count + 1)\n", .{ module, module });
            if (module > 0) try out.print("    return acc.total + m{d}.f{d}_{d}(n - 1)\n", .{ module - 1, module - 1, function }) else try out.writeAll("    return acc.total\n");
        }
        const name = try std.fmt.allocPrint(testing.allocator, "m{d}.my", .{module});
        defer testing.allocator.free(name);
        try directory.writeFile(testing.io, .{ .sub_path = name, .data = text.written() });
    }
    var main_text: std.Io.Writer.Allocating = .init(testing.allocator);
    defer main_text.deinit();
    try main_text.writer.print("import m{d}\n\n\nfunc main() -> int:\n    mut total = 0\n", .{modules - 1});
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
    const shapes = "public record Inner:\n    x: int\npublic record Outer:\n    items: Inner[]\npublic func make() -> Outer:\n    mut items: Inner[] = []\n    items.append(Inner(x=1))\n    return Outer(items=items)\n";
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "shapes.my", .data = shapes });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "user.my", .data = "import shapes\npublic func first(o: shapes.Outer) -> int:\n    mut v = o.items[0]\n    return v.x\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = "import shapes\nimport user\nfunc main() -> int:\n    return user.first(shapes.make())\n" });
    const seed = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check", entry, cache_argument } });
    defer testing.allocator.free(seed.stdout);
    defer testing.allocator.free(seed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, seed.term);
    const renamed = "public record Inner:\n    y: int\npublic record Outer:\n    items: Inner[]\npublic func make() -> Outer:\n    mut items: Inner[] = []\n    items.append(Inner(y=1))\n    return Outer(items=items)\n";
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "shapes.my", .data = renamed });
    const cached = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check", entry, cache_argument } });
    defer testing.allocator.free(cached.stdout);
    defer testing.allocator.free(cached.stderr);
    const cold = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check", entry, "--no-cache" } });
    defer testing.allocator.free(cold.stdout);
    defer testing.allocator.free(cold.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, cold.term);
    try testing.expect(std.mem.indexOf(u8, cold.stderr, "user.my:4:14: error[E_UNKNOWN_FIELD]") != null);
    try testing.expectEqual(cold.term, cached.term);
    try testing.expectEqualStrings(cold.stderr, cached.stderr);
}

/// Run the compiler with `argv` after its path; the caller frees both outputs.
fn runInterfaces(argv: []const []const u8) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(testing.allocator);
    try args.append(testing.allocator, compiler_path);
    try args.appendSlice(testing.allocator, argv);
    return std.process.run(testing.allocator, testing.io, .{ .argv = args.items });
}

// spec-case: MODULE-INTERFACE-3
test "a module checks against emitted interfaces after its imports' sources are gone" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(directory);
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.my" });
    defer testing.allocator.free(entry);
    const out = try std.fmt.allocPrint(testing.allocator, "--out={s}/interfaces", .{directory});
    defer testing.allocator.free(out);
    const from = try std.fmt.allocPrint(testing.allocator, "--from={s}/interfaces", .{directory});
    defer testing.allocator.free(from);
    const artifact = try std.fs.path.join(testing.allocator, &.{ directory, "interfaces", "lib.myi" });
    defer testing.allocator.free(artifact);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "shapes.my", .data = "public record Inner:\n    x: int\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib.my", .data = "import shapes\npublic func firsts(items: shapes.Inner[]) -> int:\n    mut total = 0\n    for item in items:\n        total += item.x\n    return total\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = "import shapes\nimport lib\nfunc main() -> int:\n    return lib.firsts([shapes.Inner(x=2)])\n" });
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
    try temporary.dir.deleteFile(testing.io, "lib.my");
    try temporary.dir.deleteFile(testing.io, "shapes.my");
    const alone = try runInterfaces(&.{ "interfaces", "check", entry, "--module=main", from });
    defer freeRun(alone);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, alone.term);
    try testing.expect(std.mem.indexOf(u8, alone.stdout, "\"stood_in\":1,\"declared_only\":true") != null);
    // A call the interface's signature rejects is reported against the module's own source.
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = "import shapes\nimport lib\nfunc main() -> int:\n    return lib.firsts(3)\n" });
    const rejected = try runInterfaces(&.{ "interfaces", "check", entry, "--module=main", from });
    defer freeRun(rejected);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, rejected.term);
    try testing.expect(std.mem.indexOf(u8, rejected.stdout, "main:") != null);
}

// spec: MODULE-INTERFACE-4
test "the interfaces command is listed in help and answers a bad action with its usage" {
    const help = try runInterfaces(&.{"--help"});
    defer freeRun(help);
    try testing.expect(std.mem.indexOf(u8, help.stdout, "mylang interfaces emit|check|oracle <entry.my> | show <module.myi>") != null);
    const usage = try runInterfaces(&.{ "interfaces", "bogus", "main.my" });
    defer freeRun(usage);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, usage.term);
    try testing.expect(std.mem.startsWith(u8, usage.stderr, "usage: mylang interfaces emit <entry.my>"));
    const missing = try runInterfaces(&.{"interfaces"});
    defer freeRun(missing);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, missing.term);
}

/// A build of the project whose entry is `main.my` in `directory`: into
/// `output`, over the cache `cache` (both under `directory`), with `--report`,
/// and `extra` after the build options.
fn projectBuild(allocator: std.mem.Allocator, directory: []const u8, output: []const u8, cache: []const u8, extra: []const []const u8) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    try args.appendSlice(allocator, &.{
        "build",
        try std.fs.path.join(allocator, &.{ directory, "main.my" }),
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
    \\        out.append(value + largest(values))
    \\    return out
    \\
;

const schedule_main =
    \\import util
    \\func main(out: Stream) -> int:
    \\    mut values = util.grow([3, 9, 4])
    \\    mut ranked = sorted(values, key=lambda v: v % 5)
    \\    out.print(ranked)
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "util.my", .data = schedule_generic });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = schedule_main });
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
        \\func size[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 7
        \\
        \\
        \\
    ;
    const edited_template =
        \\func size[T: integer](value: T) -> i64 effects():
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
        \\func main(clock: Clock) -> int:
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
    try expectConstantProcess(&.{ compiler_path, "build", path, "-o", output, "--cache-dir", cache, tools[0] }, "");
    return output;
}

/// Run a built executable with `argv` under `MYLANG_OPTIONS=options`.
fn runExecutable(argv: []const []const u8, options: []const u8) !std.process.RunResult {
    var environment = try runtimeOptions(options);
    defer environment.deinit();
    return std.process.run(testing.allocator, testing.io, .{ .argv = argv, .environ_map = &environment });
}

const argv_echo =
    \\func main(args: str[], out: Stream) -> int:
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
    const inherited = try runExecutable(&.{ compiler_path, "run", path, tools[0], "--", "--gc-stress" }, "--print-result");
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
    try testing.expect(std.mem.endsWith(u8, rejected.stderr, "input.my:3:16  main  Err(...) created\n"));

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
    \\func parse_port(text: str) -> Result[int, str]:
    \\    if len(text) == 0:
    \\        return Err("empty port")
    \\    return Ok(len(text))
    \\
    \\func read_config(text: str) -> Result[int, str]:
    \\    mut port = try parse_port(text)
    \\    return Ok(port + 1)
    \\
    \\func load(text: str) -> Result[int, AppError]:
    \\    const port = try read_config(text)
    \\    return Ok(port)
    \\
    \\func main() -> Result[int, AppError]:
    \\    mut port = try load("")
    \\    return Ok(port)
;
/// The report `error_trace_program` writes, `{path}` standing for its entry.
const error_trace_report =
    \\error: AppError.Config(value='empty port')
    \\  {path}:7:16   parse_port   Err(...) created
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "traced.my", .data = error_trace_program });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "traced.my", a);
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
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", debug, cache_argument, tools[0] }, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", fast, "--mode", "ReleaseFast", cache_argument, tools[0] }, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", release, "--release", cache_argument, tools[0] }, "");
    const ran = try std.process.run(a, testing.io, .{ .argv = &.{ compiler_path, "run", entry, cache_argument, tools[0] } });
    defer a.free(ran.stdout);
    defer a.free(ran.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, ran.term);
    try testing.expectEqualStrings(wanted, ran.stderr);
    try expectErrorReport(debug, wanted);
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
    \\func step(x: int, i: int) -> Result[int, int]:
    \\    if i % 5 == 2:
    \\        return Err(i)
    \\    return Ok((x * 7 + i) % 1000003)
    \\
    \\
    \\func relay(x: int, i: int) -> Result[int, int]:
    \\    mut value = try step(x, i)
    \\    return Ok(value + 1)
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
    \\        mut r: Result[int, int] = if (i % 3 == 0) then (Err(i)) else (Ok(i))
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
    \\    out.print(churn(3000))
    \\    mut value = try relay(1, 7)
    \\    return Ok(value)
    \\
;
/// What `kept_registers_program` writes on stderr, `{path}` standing for its entry.
const kept_registers_report =
    \\error: 7
    \\  {path}:3:16   step   Err(...) created
    \\  {path}:8:17   relay  try propagated
    \\  {path}:47:17  main   try propagated
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "kept.my", .data = kept_registers_program });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "kept.my", a);
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
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", debug, cache_argument, tools[0] }, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", release, "--release", cache_argument, tools[0] }, "");
    try expectKeptReport(debug, wanted);
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "config_test.my", .data =
        \\func parse_port(text: str) -> Result[int, str]:
        \\    if len(text) == 0:
        \\        return Err("empty")
        \\    return Ok(len(text))
        \\
        \\public func test_port() -> Result[bool, str]:
        \\    mut port = try parse_port("")
        \\    return Ok(port == 2)
        \\
        \\public func test_fine() -> Result[bool, str]:
        \\    const port = try parse_port("ab")
        \\    return Ok(port == 2)
    });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "config_test.my", a);
    defer a.free(entry);
    const cache = try std.fmt.allocPrint(a, "{s}/cache", .{std.fs.path.dirname(entry).?});
    defer a.free(cache);
    const text = try std.process.run(a, testing.io, .{ .argv = &.{ compiler_path, "test", entry, "--cache-dir", cache, tools[0] } });
    defer a.free(text.stdout);
    defer a.free(text.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, text.term);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "passed config_test::test_fine\n") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout,
        \\failed config_test::test_port: expected {"case":"ok","value":true}, got {"case":"err","value":"empty"}
        \\  config_test.my:3:16  config_test::parse_port  Err(...) created
        \\  config_test.my:7:16  config_test::test_port   try propagated
        \\
    ) != null);
    const json = try std.process.run(a, testing.io, .{ .argv = &.{ compiler_path, "test", entry, "--json", "--cache-dir", cache, tools[0] } });
    defer a.free(json.stdout);
    defer a.free(json.stderr);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, json.stdout, .{});
    defer parsed.deinit();
    try testing.expect(std.mem.endsWith(u8, testReason(parsed.value, "config_test::test_port"), "\n  config_test.my:7:16  config_test::test_port   try propagated"));
}

// spec: EPRINT-1
test "CLI separates eprint stderr from print stdout byte-exactly" {
    const program =
        \\func main(out: Stream, err: Stream) -> int:
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
        \\func main(args: str[], out: Stream) -> int:
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
        \\import helper
        \\
        \\func main(args: str[], out: Stream) -> int:
        \\    out.print(helper.render(args))
        \\    return 0
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.my", .data =
        \\
        \\
        \\public func render(args: str[]) -> str:
        \\    mut out = ""
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
    try link_argv.appendSlice(testing.allocator, &.{ compiler_path, "build", entry, "-o", output });
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
    \\import text.words
    \\
    \\func main(out: Stream) -> int:
    \\    mut n = words.count_words("the quick brown fox")
    \\    out.print(f"words: {n}")
    \\    return 0
    \\
    \\
    \\public func test_main_words() -> bool:
    \\    return words.count_words("one two") == 2
    \\
;
/// The imported module of the empty-`PATH` project, with a test of its own.
const empty_path_words =
    \\public func count_words(line: str) -> int:
    \\    mut total = 0
    \\    for part in line.split(" "):
    \\        if len(part) > 0:
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
    const installed_host = try @import("components.zig").stageInstalledHost(testing.allocator, testing.io, root, compiler_path);
    defer testing.allocator.free(installed_host);
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
    try expectEmptyPathRun(&.{ installed_host, "check", entry }, &environment, "");
    try expectEmptyPathRun(&.{ installed_host, "build", entry, "-o", program, "--cache-dir", cache, tools[0] }, &environment, "");
    try expectEmptyPathRun(&.{program}, &environment, "words: 4\n");
    try expectEmptyPathRun(&.{ installed_host, "run", entry, cache_argument, tools[0] }, &environment, "words: 4\n");
    try expectEmptyPathRun(&.{ installed_host, "test", entry, cache_argument, tools[0] }, &environment, "2 passed");
    try expectEmptyPathRun(&.{ installed_host, "fmt-project", entry, "--check" }, &environment, "");
    try expectEmptyPathRun(&.{ installed_host, "docs", "primer" }, &environment, "mylang");
    try expectEmptyPathRun(&.{ installed_host, "index-project", entry }, &environment, "\"version\":\"navigation-summary-v1\"");
    try expectEmptyPathRun(&.{ installed_host, "context", entry, "--symbol=text.words::count_words" }, &environment, "\"status\":\"ok\"");
    // The LLVM release path is built into the compiler (LLVM-ZIG-1): it runs no adapter.
    const release = try std.fs.path.join(testing.allocator, &.{ root, "program-release" });
    defer testing.allocator.free(release);
    try expectEmptyPathRun(&.{ installed_host, "build", entry, "-o", release, "--release", "--cache-dir", cache, tools[0] }, &environment, "");
    try expectEmptyPathRun(&.{release}, &environment, "words: 4\n");
    try expectEmptyPathRun(&.{ installed_host, "run", entry, "--release", cache_argument, tools[0] }, &environment, "words: 4\n");
}

/// The shared library every packages fixture locks.
const package_library = "\n\npublic func answer() -> int:\n    return 42\n";
/// An application entry that imports the locked library and returns its answer.
const package_application = "import numbers\n\nfunc main() -> int:\n    return numbers.answer()\n";

/// A temporary tree holding `library/numbers.my`, `packages.json` naming it, and
/// the absolute compiler, plus the environment every `mylang packages` call runs
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
        try writeProjectFile(&temporary, "library/numbers.my", package_library);
        try writeProjectFile(&temporary, "packages.json", "{\"packages\":[{\"name\":\"numbers\",\"root\":\"library\"}]}");
        const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
        errdefer testing.allocator.free(root);
        var environment = try emptyPathEnvironment(root);
        errdefer environment.deinit();
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
    try fixture.write("library/numbers.my", "\n\npublic func answer() -> int:\n    return 43\n");
    try fixture.expect(&build_args, 2, "", "packages: locked dependency changed: numbers");
    try fixture.write("library/numbers.my", package_library);
    try fixture.write("app1/numbers.my", package_library);
    try fixture.expect(&build_args, 2, "", "duplicate or invalid module path: numbers.my");
    try fixture.temporary.dir.deleteFile(testing.io, "app1/numbers.my");
    try fixture.write("app1/std_extra.my", "");
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
    try fixture.write("library/stray.my", "");
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
    try link_argv.appendSlice(testing.allocator, &.{ compiler_path, "build", entry, "-o", output });
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
    const no_args = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{compiler_path} });
    defer testing.allocator.free(no_args.stdout);
    defer testing.allocator.free(no_args.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, no_args.term);
    try testing.expectEqualStrings("", no_args.stdout);
    // A bare `mylang` prints the general usage; `mylang run` with no file prints run's own.
    try testing.expect(std.mem.startsWith(u8, no_args.stderr, "usage: mylang build <file.my>"));
    const no_file = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "run" } });
    defer testing.allocator.free(no_file.stdout);
    defer testing.allocator.free(no_file.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, no_file.term);
    try testing.expect(std.mem.startsWith(u8, no_file.stderr, "usage: mylang run <file.my>"));
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
    try testing.expectEqualStrings("mylang run: cannot read 'missing.my': no such file or directory\n", absent.stderr);
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
        \\func main() -> i64:
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
    // A built executable carries no call-depth accounting.
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", output, cache_argument, tools[0] }, "");
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
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "mylang run --max-frames=N") != null);
    // The executable still runs without any ceiling argument, and `run` compiles
    // the accounting in and enforces the same ceiling.
    try expectConstantProcess(&.{output}, "");
    try invokeOptions("run", "func inner() -> i64:\n    return 0\n\n\nfunc main() -> i64:\n    return inner()\n", &.{"--max-frames=1"}, 1, "", "error[R_FRAME_LIMIT]");
}
/// Build `name` as a debug and as a `--release` executable and run both; then run
/// it through `mylang run` with and without a frame ceiling. Each pair must
/// report the same bytes and exit status 1, and the executable's report must be
/// `expected` with `{path}` standing for the entry's absolute path.
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
    const fast = try std.fmt.allocPrint(a, "{s}/{s}-debug", .{ directory, name });
    defer a.free(fast);
    const framed = try std.fmt.allocPrint(a, "{s}/{s}-release", .{ directory, name });
    defer a.free(framed);
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", fast, cache_argument, tools[0] }, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", framed, "--release", cache_argument, tools[0] }, "");
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
    // `mylang run` compiles a frame ceiling's accounting in; both report the trap the same way.
    const run_fast = try std.process.run(a, testing.io, .{ .argv = &.{ compiler_path, "run", entry, cache_argument, tools[0] } });
    defer a.free(run_fast.stdout);
    defer a.free(run_fast.stderr);
    const run_framed = try std.process.run(a, testing.io, .{ .argv = &.{ compiler_path, "run", entry, cache_argument, tools[0], "--max-frames=100000" } });
    defer a.free(run_framed.stdout);
    defer a.free(run_framed.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, run_fast.term);
    try testing.expectEqual(run_fast.term, run_framed.term);
    try testing.expect(std.mem.indexOf(u8, run_fast.stderr, wanted[0 .. std.mem.indexOfScalar(u8, wanted, '\n') orelse wanted.len]) != null);
    try testing.expectEqualStrings(run_fast.stderr, run_framed.stderr);
}
/// Build `name` with `--release` — whole-program LLVM with LTO, which is free to
/// inline guest functions into one another — and as the default debug build, run
/// each, and require exit status 1 and exactly `expected` on stderr from both,
/// `{path}` standing for the entry's absolute path.
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
    const release = try std.fmt.allocPrint(a, "{s}/{s}-release", .{ directory, name });
    defer a.free(release);
    const debug = try std.fmt.allocPrint(a, "{s}/{s}-debug", .{ directory, name });
    defer a.free(debug);
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", release, "--release", cache_argument, tools[0] }, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", debug, cache_argument, tools[0] }, "");
    for ([_][]const u8{ release, debug }) |binary| {
        const trapped = try std.process.run(a, testing.io, .{ .argv = &.{binary} });
        defer a.free(trapped.stdout);
        defer a.free(trapped.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, trapped.term);
        try testing.expectEqualStrings("", trapped.stdout);
        try testing.expectEqualStrings(wanted, trapped.stderr);
    }
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
        \\func key_of(x: int) -> int:
        \\    assert x != 3, "no threes"
        \\    return 0 - x
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut ordered = sorted([5, 4, 3, 2, 1], key=key_of)
        \\    out.print(ordered[0])
        \\    return 0
    ,
        \\{path}:5:12: error[R_ASSERT]: native execution failed: no threes
        \\  in key_of at {path}:5:12
        \\  in main at {path}:10:19
        \\
    ++ "\x1eMYLANG-TRAP {\"version\":1,\"operation\":\"no threes\"}\n");
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
        \\{path}:7:16: error[R_FRAME_LIMIT]: call-depth budget exhausted; raise it with --max-frames=N (each frame reserves 32 KiB of stack, so --max-memory must cover N x 32 KiB)
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
        \\    out.print(descend(1000000000))
        \\    return 0
    , recursion_trace);
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
    \\    mut width = args[0]
    \\    mut op = args[1]
    \\    mut x = number(args[2])
    \\    mut y = number(args[3])
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "checked.my", .data = checked_arithmetic_program });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "checked.my", a);
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
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", release, "--release", cache_argument, tools[0] }, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", debug, cache_argument, tools[0] }, "");
    try expectCheckedBoundaries(.{ release, debug });
    // One trap in full: code, detail, the three frames and the record.
    const trapped = try expectSameBoundary(.{ release, debug }, .{ "i64", "add", "9223372036854775806", "2" }, 1, "");
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
    \\    out.print(calculate(args[0], number(args[1])))
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
        try testing.expect(std.mem.indexOf(u8, trapped, "MYLANG-TRAP ") != null);
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "literal.my", .data = literal_overflow_program });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "literal.my", a);
    defer a.free(entry);
    const directory = std.fs.path.dirname(entry).?;
    const cache = try std.fmt.allocPrint(a, "--cache-dir={s}/cache", .{directory});
    defer a.free(cache);
    const llvm = try std.fmt.allocPrint(a, "{s}/literal-llvm", .{directory});
    defer a.free(llvm);
    const qbe = try std.fmt.allocPrint(a, "{s}/literal-qbe", .{directory});
    defer a.free(qbe);
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", llvm, "--release", cache, tools[0] }, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", qbe, cache, tools[0] }, "");
    try expectLiteralBoundaries(.{ llvm, qbe });
}

const sticky_reduction_program =
    \\# checked reductions in loops, operands from the command line
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
    \\        values.append(value)
    \\    values.append(last)
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
    \\        _ = buffer.append_byte(109)
    \\        _ = buffer.append_byte(7)
    \\    mut data = bytes(buffer)
    \\    mut count = start
    \\    for i in range(len(data)):
    \\        if data[i] == 109:
    \\            count += 1
    \\    return count
    \\
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    mut kind = args[0]
    \\    mut n = number(args[1])
    \\    mut value = number(args[2])
    \\    mut last = number(args[3])
    \\    mut start = number(args[4])
    \\    mut values = build(n, value, last)
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
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", llvm, cache_argument, tools[0] }, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", qbe, cache_argument, tools[0] }, "");
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
    \\    mut a = [for i in range(n) yield [for j in range(n) yield float(i + j)]]
    \\    mut b = [for i in range(n) yield [for j in range(n) yield float(i * j % 7)]]
    \\    mut c = [for i in range(n) yield [for j in range(n) yield 0.0]]
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
    \\        _ = buffer.append_byte(i % 256)
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
    \\    out.print(int(product(n)))
    \\    mut bodies = [for i in range(n) yield Body(x=float(i), v=1.0)]
    \\    advance(mut bodies, 10)
    \\    out.print(int(bodies[n - 1].x * 1000.0))
    \\    out.print(scan(n * 100))
    \\    mut values = [for i in range(n) yield i * 3]
    \\    out.print(int(dot([for v in values yield float(v)], [for v in values yield 1.5])))
    \\    out.print(prefix(values, at))
    \\    return 0
;
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
    \\        if data[i] == 109:
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
    \\        text = text + "mylang "
    \\    mut b = [for i in range(n) yield float(i)]
    \\    mut c = [for i in range(n) yield 1.0]
    \\    axpy(mut c, b, 0.5, number(args[1]))
    \\    mut total = 0.0
    \\    for x in c:
    \\        total = total + x
    \\    out.print(scan(text.encode()))
    \\    out.print(int(total))
    \\    return 0
;
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
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", llvm, cache_argument, tools[0] }, "");
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", qbe, cache_argument, tools[0] }, "");
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
test "an executable built without a requested ceiling refuses a runtime step budget" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "budget.my", .data =
        \\func main() -> i64:
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
    // A built executable carries no step accounting.
    try expectConstantProcess(&.{ compiler_path, "build", entry, "-o", output, cache_argument, tools[0] }, "");
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
    try invokeOptions("run", "func main() -> i64:\n    while True:\n        pass\n    return 0\n", &.{"--max-steps=1"}, 1, "", "error[R_STEP_LIMIT]");
}
// spec: CLI-3
test "CLI executes the exact plan acceptance programs and recursive functions" {
    try invoke("run", @embedFile("fixtures/sum.my"), 0, "4950\n", "");
    try invoke("run", @embedFile("fixtures/gcd.my"), 0, "6\n", "");
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
        try invoke(command, @embedFile("fixtures/rejected.my"), 1, "", ":2:12: error[E_UNKNOWN_NAME]");
        try invoke(command,
            \\func main() -> bool:
            \\    return True
        , 1, "", "error[E_TYPE]");
    }
    // An empty file has no entry point: `run` rejects it, while
    // `check` accepts it as an empty library (CHECK-LIBRARY-2).
    try invoke("run", "", 1, "", "error[E_MAIN]");
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
    try invoke("run", @embedFile("fixtures/records.my"), 0, "12\n", "");
    try invoke("run", @embedFile("fixtures/conversions.my"), 0, "11\n", "");
    try invoke("check", @embedFile("fixtures/conversions.my"), 0, "", "");
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
    const source = @embedFile("fixtures/resources.my");
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
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_EFFECT_BOUND]");
}
test "CLI checks resource data operations effects and required mutation without ambient providers" {
    const source = @embedFile("fixtures/resource-io.my");
    try invoke("check", source, 0, "", "");
    try invokeOptions("run", source, &.{"--restrict"}, 2, "", "--restrict is active");
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
        \\func write_once(fs: Filesystem) -> i64 effects(filesystem):
        \\    mut request: FixedArray[u8, 1] = FixedArray[u8, 1]([42u8])
        \\    match acquire_resource[Open](fs, request):
        \\        case Open.ok(file):
        \\            mut payload: FixedArray[u8, 1] = FixedArray[u8, 1]([7u8])
        \\            _ = write_resource[Written](file, payload)
        \\            return 0
        \\        case Open.err(code):
        \\            return code
        \\
        \\
        \\func main(fs: Filesystem) -> i64:
        \\    return write_once(fs)
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_IMMUTABLE]");
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
// spec: CHECK-LIBRARY-1
test "CLI check-module checks bodies and never invents main" {
    try invoke("check-module", "\npublic func value() -> int:\n    return 7\n", 0, "", "");
    try invoke("check-module", "\npublic record Pair:\n    value: int\n", 0, "", "");
    try invoke("check-module", "\npublic func identity[T](value: T) -> T:\n    return value\n", 0, "", "");
    try invoke("check-module", "\npublic func value() -> int:\n    return False\n", 1, "", "E_TYPE");
    try invoke("check-module", "\npublic func value() -> int:\n    return main()\n", 1, "", "E_UNKNOWN_SYMBOL");
    try invoke("check-module", "\nrecord Hidden:\n    value: int\n\npublic func value() -> Hidden:\n    return Hidden(value=7)\n", 1, "", "E_PRIVATE_INTERFACE");
    try invoke("check-module", "\npublic func value(out: Stream) -> Unit noio:\n    out.print(7)\n", 1, "", "E_EFFECT");
    const library = "\npublic func grown(xs: int[]) -> int[]:\n    mut copy = xs\n    copy.append(1)\n    return copy\n";
    try invoke("check-module", library, 0, "", "");
}

fn expectLibraryCommand(path: []const u8, cache: []const u8, command: []const u8, status: u8, diagnostic: []const u8) !void {
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, command, path, cache } });
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data = "\npublic func value() -> int:\n    return 7\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.my", .data = "import helper\n\npublic func value() -> int:\n    return helper.value()\n" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "library.my", testing.allocator);
    defer testing.allocator.free(path);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{std.fs.path.dirname(path).?});
    defer testing.allocator.free(cache);
    try expectLibraryCommand(path, cache, "check-module", 0, "");
    try expectLibraryCommand(path, cache, "check-project", 1, "E_MAIN");
    try expectLibraryCommand(path, cache, "run", 1, "E_MAIN");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data = "\npublic func value() -> int:\n    return False\n" });
    try expectLibraryCommand(path, cache, "check-module", 1, "E_TYPE");
}

// spec-case: CHECK-LIBRARY-1
test "CLI check-module enforces configured warning and interface gates" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.my", .data = "\npublic func value() -> int:\n    mut unused: int = 1\n    return 7\n" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "library.my", testing.allocator);
    defer testing.allocator.free(path);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = "{\"version\":2,\"lint\":{\"warnings\":\"deny\"}}" });
    try expectLibraryCommand(path, "--no-cache", "check-module", 1, "W_UNUSED_BINDING");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = "{\"version\":2,\"interface_files\":true}" });
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

// spec: CHECK-LIBRARY-2
test "CLI check type-checks a file without main as a library" {
    try invoke("check", "public func add(a: int, b: int) -> int:\n    return a + b\n", 0, "", "");
    try invoke("check", "public record Pair:\n    value: int\n", 0, "", "");
    try invoke("check", "public func identity[T](value: T) -> T:\n    return value\n", 0, "", "");
    try invoke("check", "func helper() -> int:\n    return 1\n", 0, "", "");
    try invoke("check", "", 0, "", "");
    try invoke("check", "\npublic func value() -> int:\n    return 7\n", 0, "", "");
    try invoke("check", "import strings\n\npublic func shout(text: str) -> str:\n    return strings.upper(text)\n", 0, "", "");
    const library = "\npublic func grown(xs: int[]) -> int[]:\n    mut copy = xs\n    copy.append(1)\n    return copy\n";
    try invoke("check", library, 0, "", "");
    try invokeOptions("check", library, &.{"--diagnostics=json"}, 0, "", "");
    // A body error is the library's own diagnostic, never the missing entry point.
    try expectFailsAsItself("check", "public func value() -> int:\n    return False\n", &.{}, "error[E_TYPE]");
    try expectFailsAsItself("check", "\npublic func value() -> int:\n    return False\n", &.{}, "error[E_TYPE]");
    try expectFailsAsItself("check", "public func value() -> int:\n    return missing\n", &.{}, "error[E_UNKNOWN_NAME]");
    try expectFailsAsItself("check", "public func value(out: Stream) -> Unit noio:\n    out.print(7)\n", &.{}, "error[E_EFFECT_BOUND]");
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
    try invoke("run", library, 1, "", "`mylang check FILE` type-checks a library");
}

// spec-case: CHECK-LIBRARY-2
test "CLI check keeps every entry check when main is declared" {
    try invoke("check", "func main() -> int:\n    return 0\n", 0, "", "");
    try invoke("check", "\nfunc main() -> int:\n    return 0\n", 0, "", "");
    try invoke("check", "func main(args: str[], out: Stream) -> int:\n    out.print(len(args))\n    return 0\n", 0, "", "");
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data = "\npublic func value() -> int:\n    return 7\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.my", .data = "import helper\n\npublic func value() -> int:\n    return helper.value()\n" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "library.my", testing.allocator);
    defer testing.allocator.free(path);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{std.fs.path.dirname(path).?});
    defer testing.allocator.free(cache);
    try expectLibraryCommand(path, cache, "check", 0, "");
    try expectLibraryCommand(path, cache, "check", 0, "");
    try expectLibraryCommand(path, cache, "check-project", 1, "E_MAIN");
    try expectLibraryCommand(path, cache, "run", 1, "E_MAIN");
    try expectLibraryCommand(path, "--no-cache", "check", 0, "");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data = "\npublic func value() -> int:\n    return False\n" });
    try expectLibraryCommand(path, cache, "check", 1, "E_TYPE");
    try expectLibraryCommand(path, "--no-cache", "check-module", 1, "E_TYPE");
}

// spec-case: CHECK-LIBRARY-2
test "CLI check of a library enforces configured warning and interface gates" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "headerless.my", .data = "public func value() -> int:\n    mut unused: int = 1\n    return 7\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library.my", .data = "\npublic func value() -> int:\n    mut unused: int = 1\n    return 7\n" });
    const headerless = try temp.dir.realPathFileAlloc(testing.io, "headerless.my", testing.allocator);
    defer testing.allocator.free(headerless);
    const path = try temp.dir.realPathFileAlloc(testing.io, "library.my", testing.allocator);
    defer testing.allocator.free(path);
    try expectLibraryCommand(path, "--no-cache", "check", 0, "W_UNUSED_BINDING");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = "{\"version\":2,\"lint\":{\"warnings\":\"deny\"}}" });
    try expectLibraryCommand(headerless, "--no-cache", "check", 1, "W_UNUSED_BINDING");
    try expectLibraryCommand(path, "--no-cache", "check", 1, "W_UNUSED_BINDING");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = "{\"version\":2,\"interface_files\":true}" });
    try expectLibraryCommand(path, "--no-cache", "check", 1, "E_INTERFACE_FILE_STALE");
}

// spec: FMT-CHECK-LOCATION-1
test "CLI formatter check locates spacing and missing final newline" {
    try invokeOptions("fmt", "func  main() -> int:\n    return 7\n", &.{"--check"}, 1, "", "input.my:1:6: formatting differs");
    try invokeOptions("fmt", "func main() -> int:\n    return 7", &.{"--check"}, 1, "", "input.my:2:13: formatting differs");
    try invokeOptions("fmt-module", "\nfunc  f() -> int:\n    return 7\n", &.{"--check"}, 1, "", "input.my:1:1: formatting differs");
}

// spec: FMT-TEST-MODULE-1
test "CLI formatter and test agree on headerless sibling test imports" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data = "\npublic func value() -> int:\n    return 7\n" });
    const source = "import helper\n\npublic func test_value() -> bool:\n    return helper.value() == 7\n";
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper_test.my", .data = source });
    const path = try temp.dir.realPathFileAlloc(testing.io, "helper_test.my", testing.allocator);
    defer testing.allocator.free(path);
    const formatted = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "fmt", path } });
    defer testing.allocator.free(formatted.stdout);
    defer testing.allocator.free(formatted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, formatted.term);
    try testing.expectEqualStrings(source, formatted.stdout);
    const checked = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "fmt-module", path, "--check" } });
    defer testing.allocator.free(checked.stdout);
    defer testing.allocator.free(checked.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
    const tested = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "test", path } });
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data = "\npublic func value() -> int:\n    return 7\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper_test.my", .data = "import helper\n\npublic func test_value() -> bool:\n    return helper.value() == 7\n" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "helper.my", testing.allocator);
    defer testing.allocator.free(path);
    const empty = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "test", path, "--json" } });
    defer testing.allocator.free(empty.stdout);
    defer testing.allocator.free(empty.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, empty.term);
    try testing.expect(std.mem.indexOf(u8, empty.stderr, "helper_test.my") != null);
    try testing.expect(std.mem.indexOf(u8, empty.stderr, "Run that file explicitly") != null);
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, empty.stdout, .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("native-tests-v1", parsed.value.object.get("version").?.string);
    try testing.expectEqual(@as(usize, 0), parsed.value.object.get("tests").?.array.items.len);
    try temp.dir.deleteFile(testing.io, "helper_test.my");
    const absent = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "test", path } });
    defer testing.allocator.free(absent.stdout);
    defer testing.allocator.free(absent.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, absent.term);
    try testing.expectEqualStrings("", absent.stderr);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper_test.my", .data = "\npublic func value() -> int:\n    return 7\n\n\npublic func test_value() -> bool:\n    return True\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data = "import helper_test\n\nfunc main() -> int:\n    return helper_test.value()\n" });
    const loaded = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "test", path, "--filter", "does_not_exist" } });
    defer testing.allocator.free(loaded.stdout);
    defer testing.allocator.free(loaded.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, loaded.term);
    try testing.expectEqualStrings("", loaded.stderr);
}

test "CLI module discovery loads real files and diagnoses cross-file cycles" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDirPath(testing.io, "shared");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\import shared.data as data
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "shared/data.my", .data = "" });
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "shared/data.my", .data = "import input\n" });
    const cycle = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "list-modules", path } });
    defer testing.allocator.free(cycle.stdout);
    defer testing.allocator.free(cycle.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, cycle.term);
    try testing.expectEqualStrings("", cycle.stdout);
    for ([_][]const u8{ "E_IMPORT_CYCLE", "shared/data.my:1:", "input.my:1:", "input -> shared.data -> input" }) |part| try testing.expect(std.mem.indexOf(u8, cycle.stderr, part) != null);
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "units.my", .data =
        \\
        \\
        \\public domain Distance: i64:
        \\    func make(x: i64) -> Distance effects():
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
        \\
        \\
        \\domain Distance: i64:
        \\    func make(x: i64) -> Distance:
        \\        return wrap[Distance](x)
    });
    const hidden = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "list-interfaces", path } });
    defer testing.allocator.free(hidden.stdout);
    defer testing.allocator.free(hidden.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, hidden.term);
    try testing.expectEqualStrings("", hidden.stdout);
    for ([_][]const u8{ "E_PRIVATE_SYMBOL", "input.my:5:", "units.my:3:" }) |part| try testing.expect(std.mem.indexOf(u8, hidden.stderr, part) != null);
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\
        \\
        \\public func main(fs: Filesystem, clock: Clock) -> int:
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
        \\import math
        \\
        \\
        \\func main() -> int:
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
        \\import helper
        \\
        \\
        \\func main() -> int:
        \\    return helper.value()
    });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data =
        \\
        \\
        \\public func value() -> int effects():
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
        \\import helper
        \\
        \\func main() -> int:
        \\    return helper.value()
    });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "app/helper.my", .data =
        \\
        \\public func value() -> int effects():
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

test "CLI test discovers a test_ function without an explicit export" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\
        \\func test_add() -> bool:
        \\    return 1 + 1 == 2
        \\
        \\func main() -> int:
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "hello.my", .data = "func main(out: Stream) -> int:\n    out.print(\"hello\")\n    return 0\n" });
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try std.process.Environ.createMap(testing.environ, testing.allocator);
    defer environment.deinit();
    // An inherited local cache would hide where the tools put their cache.
    _ = environment.swapRemove("ZIG_LOCAL_CACHE_DIR");
    const built = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "build", "hello.my", "-o", "hello", "--cache-dir", "cache", tools[0] },
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
test "mylang test inside a build.zig project compiles its runner without a Zig cache there" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "build.zig", .data = "" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "checks.my", .data = "public func test_adds() -> bool:\n    return 1 + 1 == 2\n" });
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, testing.allocator);
    defer testing.allocator.free(compiler);
    var environment = try std.process.Environ.createMap(testing.environ, testing.allocator);
    defer environment.deinit();
    _ = environment.swapRemove("ZIG_LOCAL_CACHE_DIR");
    // A fresh cache directory makes this run compile the runner harness itself.
    const tested = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "test", "checks.my", "--cache-dir=cache", tools[0] },
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
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

// spec: DIRECTORY-CASES-1
// spec-case: TEST-PRIVATE-ACCESS-1
test "CLI directory test applies each entry's own cases file and lets a test file reach its module's privates" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "scanner.my", .data = "\n\nfunc helper() -> int:\n    return 7\n\n\npublic func scan() -> int:\n    return helper()\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "scanner_test.my", .data = "import scanner\n\n\npublic func test_helper() -> bool:\n    return scanner.helper() == scanner.scan()\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "scaled_test.my", .data = "\n\npublic func test_scaled(n: int) -> int:\n    return n * 2\n" });
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, ".mylang-test-cache" });
    defer testing.allocator.free(cache);
    // Without its cases file the parameterized test is a property test
    // (PROPERTY-TEST-1), which an `int` result cannot be.
    const bare = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "test", root, "--cache-dir", cache } });
    defer testing.allocator.free(bare.stdout);
    defer testing.allocator.free(bare.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, bare.term);
    try testing.expect(std.mem.indexOf(u8, bare.stdout, "passed scanner_test::test_helper") != null);
    try testing.expect(std.mem.indexOf(u8, bare.stdout, "a property test returns bool or Result[bool, E]") != null);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "scaled_test.cases.json", .data = "{\"scaled_test::test_scaled\": {\"arguments\": {\"n\": \"21\"}, \"expected\": \"42\"}}" });
    const cased = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "test", root, "--cache-dir", cache } });
    defer testing.allocator.free(cased.stdout);
    defer testing.allocator.free(cased.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cased.term);
    try testing.expect(std.mem.indexOf(u8, cased.stdout, "scaled_test::test_scaled") != null);
    try testing.expect(std.mem.indexOf(u8, cased.stdout, "0 failed") != null);
    // An explicit `--cases` still names one project, so a directory refuses it.
    const explicit = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "test", root, "--cases", "scaled_test.cases.json", "--cache-dir", cache } });
    defer testing.allocator.free(explicit.stdout);
    defer testing.allocator.free(explicit.stderr);
    try testing.expect(explicit.term.exited != 0);
}

test "CLI test reports an exported ill-shaped test as a failed case" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\
        \\
        \\public func test_bad() -> int effects():
        \\    return 1
        \\
        \\
        \\public func test_ok() -> bool effects():
        \\    return True
        \\
        \\
        \\func main() -> int:
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

/// One `mylang test` run of `path` with a private cache and extra arguments.
fn capabilityTestRun(path: []const u8, cache: []const u8, extra: []const []const u8) !std.process.RunResult {
    const argv = try std.mem.concat(testing.allocator, []const u8, &.{ &.{ compiler_path, "test", path, "--cache-dir", cache }, extra });
    defer testing.allocator.free(argv);
    return std.process.run(testing.allocator, testing.io, .{ .argv = argv });
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
    \\    match network.connect(net.host("127.0.0.1:1")):
    \\        case network.Connected.ok(_):
    \\            return False
    \\        case network.Connected.err(code):
    \\            return code == network.denied_here() and fs.exists("a.txt") and len(env.names()) == 0
    \\
    \\public func test_entropy(entropy: Entropy, out: Stream) -> bool:
    \\    match random.from_entropy(entropy):
    \\        case Ok(sampled):
    \\            mut generator = sampled
    \\            out.print("word", random.next_word(mut generator))
    \\        case Err(_):
    \\            out.print("no entropy")
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = capability_tests });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
    defer testing.allocator.free(path);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const cache = try std.fs.path.join(testing.allocator, &.{ root, ".mylang-test-cache" });
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\import helper
        \\
        \\
        \\func main() -> i64:
        \\    return helper.value()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data =
        \\
        \\
        \\public func value() -> i64 effects():
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
        \\
        \\
        \\public func value() -> i64 effects():
        \\    return divtrunc(1, 0)
    });
    const trap = try std.process.run(testing.allocator, testing.io, .{ .argv = &(.{ compiler_path, "run-project", path, "--print-result" } ++ tools) });
    defer testing.allocator.free(trap.stdout);
    defer testing.allocator.free(trap.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, trap.term);
    for ([_][]const u8{ "R_DIVISION_BY_ZERO", "helper.my:4:", "input.my:5:" }) |part| try testing.expect(std.mem.indexOf(u8, trap.stderr, part) != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data =
        \\
        \\
        \\func value() -> i64:
        \\    return 42
    });
    const hidden = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-project", path } });
    defer testing.allocator.free(hidden.stdout);
    defer testing.allocator.free(hidden.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, hidden.term);
    for ([_][]const u8{ "E_PRIVATE_SYMBOL", "helper.my:3:", "input.my:5:" }) |part| try testing.expect(std.mem.indexOf(u8, hidden.stderr, part) != null);
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\import core
        \\
        \\
        \\func main() -> i64:
        \\    return core.value()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "core.my", .data =
        \\
        \\
        \\public func value() -> i64 effects():
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
        \\
        \\
        \\public func value() -> i64:
        \\    return True
    });
    const invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-policy", path, option } });
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
        \\public func test_compute() -> bool effects():
        \\    return compute(1) == 2
        \\
        \\
        \\func main() -> int:
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
        \\
        \\
        \\func square(value: int) -> int:
        \\    return value * value
        \\
        \\
        \\func test_expression() -> bool effects():
        \\    return square(3) == 9
        \\
        \\
        \\func test_fake() -> bool effects():
        \\    return True
        \\
        \\
        \\func test_conditional() -> bool effects():
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
test "CLI lint advisory budget rules report only and never block under gate" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = "{\"version\":2,\"lint\":{\"rules\":{\"function-length\":{\"max\":1}}}}" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data =
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
        \\
        \\
        \\func main() -> int:
        \\    mut unused: int = 1
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
        \\
        \\
        \\public func value() -> int:
        \\    return 42
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "unused_mod.my", .data =
        \\
        \\
        \\public func thing() -> int:
        \\    return 1
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\import helper
        \\import unused_mod
        \\
        \\
        \\func main() -> int:
        \\    mut note = "unused_mod.thing()"
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
        \\func test_compute() -> bool effects():
        \\    return compute(1) == 2
        \\
        \\
        \\func main() -> int:
        \\    return 0
    ;
    try invoke("lint", source, 0, "lint: 1 finding(s): 0 blocking, 1 report, 0 waived, 0 accepted\n", "L_UNDOCUMENTED_EXPORT");
    try invokeOptions("lint", source, &.{ "--gate", "--profile=strict" }, 3, "lint: 1 finding(s): 1 blocking, 0 report, 0 waived, 0 accepted\n", "L_UNDOCUMENTED_EXPORT");
    const documented =
        \\
        \\
        \\public func compute(value: int) -> int:
        \\    "Compute the input plus one."
        \\    return value + 1
        \\
        \\
        \\func test_compute() -> bool effects():
        \\    return compute(1) == 2
        \\
        \\
        \\func main() -> int:
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
        \\
        \\
        \\public func compute(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\func main() -> int:
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
        \\
        \\
        \\public func compute(value: int) -> int:
        \\    return value + 2
        \\
        \\
        \\func main() -> int:
        \\    return 0
    });
    const body = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "api-diff", path, against_option } });
    defer testing.allocator.free(body.stdout);
    defer testing.allocator.free(body.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, body.term);
    try testing.expect(std.mem.indexOf(u8, body.stdout, "compatible=1") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data =
        \\
        \\
        \\public func compute(value: int, extra: int) -> int:
        \\    return value + extra
        \\
        \\
        \\func main() -> int:
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
    \\# generated by mylang api; do not edit
    \\module app
    \\
    \\public func compute(value: int) -> int ceiling(managed_allocation)
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

fn writeApiFixture(dir: std.Io.Dir, config: ?[]const u8) !void {
    try dir.writeFile(testing.io, .{ .sub_path = "app.my", .data = api_app_source });
    try dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = api_main_source });
    if (config) |bytes| try dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = bytes });
}

// spec-case: API-FILE-2
test "CLI api --check and --write: exit codes, diff, json, body-edit stability and cache states" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    try writeApiFixture(temp.dir, null);
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data = "\n\npublic func compute(value: int) -> int:\n    # changed body\n    return 1 + value\n" });
    try expectApi(warm, "api", &.{"--write"}, 0, "api: 2 interface files current\n", "");
    const body_bytes = try temp.dir.readFileAlloc(testing.io, "app.api", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(body_bytes);
    try testing.expectEqualStrings(warm_bytes, body_bytes);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data = "\n\npublic func compute(value: int, extra: int = 1) -> int:\n    return value + extra\n" });
    try expectApi(warm, "api", &.{"--check"}, 1, "@@ -2,3 +2,3 @@\n module app\n \n-public func compute(value: int) -> int ceiling(managed_allocation)\n+public func compute(value: int, extra: int = 1) -> int ceiling(managed_allocation)\n", "");
    try expectApi(warm, "api", &.{ "--check", "--json" }, 1, "{\"version\":\"interface-files-v1\",\"mode\":\"check\",\"status\":\"stale\",\"files\":2,\"modules\":[{\"module\":\"app\",\"path\":\"app.api\",\"state\":\"stale\",\"added\":[],\"removed\":[],\"changed\":[\"compute\"]}]}\n", "");
    try expectApi(warm, "api", &.{ "--write", "--json" }, 0, "\"mode\":\"write\",\"status\":\"updated\"", "");
    try expectApi(warm, "api", &.{ "--check", "--json" }, 0, "{\"version\":\"interface-files-v1\",\"mode\":\"check\",\"status\":\"current\",\"files\":2,\"modules\":[]}\n", "");

    // A generated file whose source is gone is an orphan until --write deletes it.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "old.api", .data = "# generated by mylang api; do not edit\nmodule old\n" });
    try expectApi(warm, "api", &.{"--check"}, 1, "api: old is orphaned (old.api)\n", "");
    try expectApi(warm, "api", &.{"--write"}, 0, "api: deleted old.api (old)\n", "");
    try testing.expectError(error.FileNotFound, temp.dir.statFile(testing.io, "old.api", .{}));
}

// spec: API-FILE-3
test "CLI check rejects a stale interface file when mylang.json sets interface_files" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    try writeApiFixture(temp.dir, "{\"version\": 1, \"interface_files\": true}");
    const fixture = ApiRun{ .root = root, .entry = "main.my", .cache = "--cache-dir=cache" };

    try expectApi(fixture, "check", &.{}, 1, "", "app.api:1:1: error[E_INTERFACE_FILE_STALE]: the interface file of module `app` is missing; run `mylang api main.my --write` and review its diff\n");
    try expectApi(fixture, "api", &.{"--write"}, 0, "", "");
    try expectApi(fixture, "check", &.{}, 0, "", "");
    // The replayed success is keyed on the interface files' bytes.
    try expectApi(fixture, "check", &.{}, 0, "", "");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.api", .data = "# generated by mylang api; do not edit\n" });
    try expectApi(fixture, "check", &.{}, 1, "", "app.api:1:1: error[E_INTERFACE_FILE_STALE]: the interface file of module `app` is stale;");
    try expectApi(fixture, "run", &.{}, 1, "", "E_INTERFACE_FILE_STALE");
    try expectApi(fixture, "api", &.{"--write"}, 0, "", "");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data = "\n\npublic func compute(value: int) -> int:\n    return value + 2\n" });
    try expectApi(fixture, "check", &.{}, 0, "", "");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app.my", .data = "\n\n@deprecated(\"use compute2\")\npublic func compute(value: int) -> int:\n    return value + 1\n" });
    try expectApi(fixture, "check", &.{}, 1, "", "app.api:1:1: error[E_INTERFACE_FILE_STALE]");
    try temp.dir.deleteFile(testing.io, "app.api");
    try expectApi(fixture, "check-project", &.{}, 1, "", "is missing");

    // Without the key nothing is enforced, and the value must be a boolean.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = "{\"version\": 1, \"interface_files\": false}" });
    try expectApi(fixture, "check", &.{}, 0, "", "");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = "{\"version\": 1, \"interface_files\": \"yes\"}" });
    try expectApi(fixture, "check", &.{}, 2, "", "error[E_PROJECT_CONFIG]: interface_files must be true or false");
}

// spec-case: API-FILE-3
test "CLI the interface-files example keeps its checked-in interface files current" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const cache = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(cache);
    const cache_option = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache});
    defer testing.allocator.free(cache_option);
    const entry = "examples/interface-files/main.my";
    const checked = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "api", entry, "--check", cache_option } });
    defer testing.allocator.free(checked.stdout);
    defer testing.allocator.free(checked.stderr);
    try testing.expectEqualStrings("api: 3 interface files current\n", checked.stdout);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
    const project = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check-project", entry, cache_option } });
    defer testing.allocator.free(project.stdout);
    defer testing.allocator.free(project.stderr);
    try testing.expectEqualStrings("", project.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, project.term);
}

/// The two-module fixture `mylang context` answers about: the entry imports
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
        \\import alpha
        \\import beta
        \\
        \\
        \\func main() -> int:
        \\    return alpha.first() + beta.second()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "alpha.my", .data =
        \\
        \\
        \\public func validate(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\public func first() -> int:
        \\    return 1
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "beta.my", .data =
        \\
        \\
        \\public func validate(value: int) -> int:
        \\    return value + 2
        \\
        \\
        \\public func second() -> int:
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
        \\
        \\
        \\func helper(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\func test_helper() -> bool effects():
        \\    return helper(1) == 2
        \\
        \\
        \\func main() -> int:
        \\    return 0
    });
    try gitIn(testing.allocator, root, &.{ "init", "-q" });
    try gitIn(testing.allocator, root, &.{ "add", "main.my" });
    try gitIn(testing.allocator, root, &.{ "-c", "user.email=test@example.com", "-c", "user.name=test", "commit", "-q", "-m", "init" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\
        \\
        \\func helper(value: int) -> int:
        \\    return value + 2
        \\
        \\
        \\func test_helper() -> bool effects():
        \\    return helper(1) == 2
        \\
        \\
        \\func main() -> int:
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
        \\
        \\
        \\func helper(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\func test_helper() -> bool effects():
        \\    return helper(1) == 2
        \\
        \\
        \\func test_unrelated() -> bool effects():
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
        \\func test_helper() -> bool effects():
        \\    return helper(1) == 3
        \\
        \\
        \\func test_unrelated() -> bool effects():
        \\    return 3 == 3
        \\
        \\
        \\func main() -> int:
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
        \\
        \\
        \\func helper() -> int:
        \\    return 1
        \\
        \\
        \\func main() -> int:
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data =
        \\
        \\
        \\func copy(x: i64) -> i64:
        \\    return x * 2 + 3
    });
    const path = try temp.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "discover-project-duplicates", path, "--min-nodes=1", "--approximate", "--max-work=1", "--population=reference", "--timings" } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    for ([_][]const u8{ "scope: reachable module graph", "population=reference", "input::twice", "helper::copy", "input.my:4:", "helper.my:3:", "approximate near-v3", "truncated=true" }) |part| try testing.expect(std.mem.indexOf(u8, result.stdout, part) != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "project_frontend_ns=") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "modules=2") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data =
        \\
        \\
        \\func copy(x: i64) -> i64:
        \\    return True
    });
    const invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "discover-project-duplicates", path } });
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\import api
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "api.my", .data =
        \\
        \\
        \\public func entry() -> i64 effects():
        \\    return hidden()
        \\
        \\
        \\func hidden() -> i64:
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
    try testing.expectEqualStrings("input.my:1:8: warning[W_UNUSED_IMPORT]: import `api` is never referenced in this module; remove it or use it\n  import api\n         ^\n", result.stderr);
    for ([_][]const u8{ "quality-modules-v1", "api.my:3:", "api::entry; private=false; reachable-from-main=false", "module-exported=true reachable-from-exports=true", "module-exported=false reachable-from-exports=true", "function-lines 2 exceeds configured 1", "calls api::hidden at api.my:4:", "Runtime coverage and assertions: not measured" }) |part| try testing.expect(std.mem.indexOf(u8, result.stdout, part) != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "no call path from main or exported interfaces") == null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "api.my", .data =
        \\
        \\
        \\func invalid() -> i64:
        \\    return True
    });
    const invalid = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "report-project-quality", path } });
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "child.my", .data = "\nfunc  f() -> Missing:\n    return unknown()\n" });
    const differing = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "fmt-project", path, "--check" } });
    defer testing.allocator.free(differing.stdout);
    defer testing.allocator.free(differing.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, differing.term);
    try testing.expect(std.mem.indexOf(u8, differing.stderr, "child.my:1:1: formatting differs") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "child.my", .data =
        \\func broken(
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
        \\import config
        \\
        \\
        \\public func read() -> i64 effects():
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\
        \\
        \\func main() -> i64:
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
        \\        case Slot.none:
        \\            return 0
        \\        case Slot.some(value=box):
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
    try testing.expectEqualStrings("input.my", parsed.value.object.get("inputs").?.array.items[0].object.get("path").?.string);
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
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, flag } });
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
        try testing.expectEqualStrings("", result.stderr);
        try testing.expect(std.mem.startsWith(u8, result.stdout, "mylang: a Python-shaped"));
        const everyday = std.mem.indexOf(u8, result.stdout, "mylang check FILE.my").?;
        const reference = std.mem.indexOf(u8, result.stdout, "usage: mylang build").?;
        try testing.expect(everyday < reference);
        // The guides and the large-project commands are on the first screen too.
        try testing.expect(std.mem.indexOf(u8, result.stdout, "mylang docs primer").? < everyday);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "mylang docs [TOPIC]").? < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "--release").? < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "mylang cost ENTRY.my").? < reference);
        try testing.expect(std.mem.indexOf(u8, result.stdout, "[--cost]").? < reference);
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
        try expectTrivia(listing_module[accounted..range.start]);
        accounted = range.end;
    }
    try expectTrivia(listing_module[accounted..]);
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
    const source = @embedFile("fixtures/warnings.my");
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
test "CLI preserves integer width bounds and explicit casts" {
    try invoke("run", @embedFile("fixtures/integers.my"), 0, "6148914691236516950\n", "");
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
    try invoke("run", @embedFile("fixtures/arrays.my"), 0, "44\n", "");
    try invoke("check", @embedFile("fixtures/arrays.my"), 0, "", "");
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
test "CLI checks domain privacy unit mismatches and qualified factory execution" {
    try invoke("run", @embedFile("fixtures/domains.my"), 0, "1003\n", "");
    try invoke("check", @embedFile("fixtures/domains.my"), 0, "", "");
    const private =
        \\domain D: i64:
        \\    private func raw(n: i64) -> D:
        \\        return wrap[D](n)
        \\
        \\
        \\func main() -> i64:
        \\    _ = D.raw(1)
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| {
        try invoke(command, private, 1, "", "error[E_PRIVATE_FUNCTION]");
    }
    try invoke("check",
        \\domain D: i64:
        \\    func make(n: i64) -> D:
        \\        return wrap[D](n)
        \\
        \\
        \\func main() -> i64:
        \\    _ = wrap[D](1)
        \\    return 0
    , 1, "", "error[E_PRIVATE_DOMAIN]");
    try invoke("check",
        \\domain Seconds: i64:
        \\    func from(n: i64) -> Seconds:
        \\        return wrap[Seconds](n)
        \\
        \\
        \\domain Millimeters: i64:
        \\    func of(n: i64) -> Millimeters:
        \\        return wrap[Millimeters](n)
        \\
        \\
        \\func distance(n: Millimeters) -> i64:
        \\    _ = n
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return distance(Seconds.from(1))
    , 1, "", "expected Millimeters, found Seconds");
}
test "CLI executes variants dumps dispatch and rejects newly incomplete matches" {
    try invoke("run", @embedFile("fixtures/variants.my"), 0, "24\n", "");
    try invoke("check", @embedFile("fixtures/variants.my"), 0, "", "");
    const added =
        \\enum Color:
        \\    red
        \\    green
        \\    added
        \\
        \\
        \\func main() -> i64:
        \\    match Color.red:
        \\        case Color.red:
        \\            return 1
        \\        case Color.green:
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
        \\        case U.value(value=_):
        \\            return 0
    , 1, "", "error[R_DIVISION_BY_ZERO]");
}
test "CLI executes complete enum tables and rejects missing mappings in every command" {
    try invoke("run", @embedFile("fixtures/tables.my"), 0, "1407\n", "");
    try invoke("check", @embedFile("fixtures/tables.my"), 0, "", "");
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
    const source = @embedFile("fixtures/results.my");
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
    const source = @embedFile("fixtures/external-capabilities.my");
    try checkProjectClean(source);
    try invokeProjectOptions("run", source, &.{"--restrict"}, 2, "", "--restrict is active");
    const invalid =
        \\import time
        \\
        \\
        \\func main(c: Clock) -> int effects():
        \\    _ = time.now(c)
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "discover-project-duplicates" }) |command| try invokeProject(command, invalid, 1, "", "error[E_EFFECT_BOUND]");
}
test "CLI checks bounded environment access without granting ambient process access" {
    const source = @embedFile("fixtures/environment.my");
    try invoke("check", source, 0, "", "");
    try invokeOptions("run", source, &.{"--restrict"}, 2, "", "--restrict is active");
    const invalid =
        \\func main(env: Environment) -> i64 effects():
        \\    _ = env.get("K")
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_EFFECT_BOUND]");
}
// spec: CAPABILITY-METHOD-NARROWING-2
test "CLI exposes fs.read_only permission attenuation and rejects the removed spelling" {
    const source = @embedFile("fixtures/attenuation.my");
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
        \\resource Socket: network
        \\
        \\result Open:
        \\    ok: Socket,
        \\    err: int
        \\
        \\func main(net: Network) -> int:
        \\    mut scoped = net.host("127.0.0.1:8000")
        \\    mut request: FixedArray[u8, 1] = FixedArray[u8, 1]([0u8])
        \\    match acquire_resource[Open](scoped, request):
        \\        case Open.ok(socket):
        \\            _ = socket
        \\            return 0
        \\        case Open.err(code):
        \\            return code
    ;
    try invoke("check", source, 0, "", "");
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
        \\        case Open.ok(socket):
        \\            _ = socket
        \\            return 0
        \\        case Open.err(code):
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
    \\func main(net: Network) -> int effects(network):
    \\    mut scoped = net.host("127.0.0.1:9")
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
        \\import network
        \\
        \\
        \\func main(net: Network) -> int effects(network):
        \\    mut scoped = net.host("{s}")
        \\    match network.connect(scoped):
        \\        case network.Connected.ok(first):
        \\            mut payload: FixedArray[u8, 4] = b"ping"
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
    const argv = [_][]const u8{ compiler_path, "run", entry, "--print-result", tools[0], "--restrict", grant };
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
    const invalid =
        \\func main(fs: Filesystem) -> int:
        \\    _ = fs.read_text()
        \\    return 0
    ;
    for ([_][]const u8{ "check", "run", "discover-duplicates" }) |command| try invoke(command, invalid, 1, "", "error[E_ARITY]");
}

const clock_program =
    \\import time
    \\
    \\
    \\func main(clock: Clock) -> int:
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
        \\func main(env: Environment) -> i64 effects(environment):
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
        \\func main() -> i64:
        \\    return 4
    , &.{ "--restrict", "--allow-clock", "--allow-random=7" }, 0, "4\n", "");
}
// spec: CAPABILITY-5
test "CLI clock entropy and environment providers honour their grants" {
    const seeded =
        \\import random
        \\
        \\
        \\func main(rng: Entropy) -> int:
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
        \\func main(env: Environment) -> i64 effects(environment):
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
    const program =
        \\func main(fs: Filesystem, out: Stream) -> int:
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
        \\func main(out: Stream) -> int:
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
        \\import time
        \\import random
        \\
        \\func main(clock: Clock, rng: Entropy, fs: Filesystem, out: Stream) -> int:
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
        \\func main(fs: Filesystem, out: Stream) -> int:
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
    const outcome = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "run", entry, tools[0] },
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
    const absolute = try std.fmt.allocPrint(testing.allocator, "func main(fs: Filesystem, out: Stream) -> int:\n    out.print(read_text(fs, \"{s}\"))\n    return 0\n", .{anchor});
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
        \\
        \\import helper
        \\
        \\func main() -> i64:
        \\    return helper.answer()
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.my", .data =
        \\
        \\
        \\public func answer() -> i64 effects():
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
        \\
        \\
        \\public func answer() -> i64 effects():
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
        \\
        \\
        \\public func answer() -> i64:
        \\    return True
    });
    const broken = try projectCacheCheck(entry, cache_argument, 1);
    try testing.expectEqual(@as(usize, 0), broken.verdict_hits);

    // Repair the source so the final no-cache run is a successful check.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/helper.my", .data =
        \\
        \\
        \\public func answer() -> i64 effects():
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

// spec: CAPABILITY-DIAG-1
test "multiple missing capabilities report exactly one identical diagnostic" {
    const program =
        \\func main(fs: Filesystem, env: Environment) -> int:
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
        \\func main(args: str[]) -> int:
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
    \\
    \\
    \\public constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
;
const named_constraint_checkout =
    \\import contracts
    \\
    \\
    \\public func total[P: contracts.Prices](policy: P, subtotal: int) -> int effects():
    \\    return P.price(policy, subtotal) + 500
;
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
const named_constraint_fake_tests =
    \\import checkout
    \\import fakes
    \\
    \\
    \\func main() -> int:
    \\    assert test_checkout()
    \\    return 0
    \\
    \\
    \\public func test_checkout() -> bool effects():
    \\    return checkout.total(fakes.FixedPrices.make(1750), 2000) == 2250
;
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
// spec: NEW-CORE-S5-ONE-BINARY-1
test "mylang build answers the core's developer switches as mylang-core did" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = "func main(out: Stream) -> int:\n    out.print(6 * 7)\n    return 0\n" });
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, testing.allocator);
    defer testing.allocator.free(compiler);
    const built = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{ compiler, "build", "main.my", "-o", "program", "--generic-vectors", "--trap-frames=posix_exit", "--cache-dir", "cache", "--zig", @import("test_options").zig_path },
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
        .argv = &.{ compiler, "build", "main.my", "--run", "--generic-vectors" },
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
const policy_project_helper = "public func value() -> int effects():\n    return 7\n";

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

// spec-case: POLICY-IDENTITY-OWNED-1
test "loadConfiguredPolicy keeps a configured project's warm verdicts replayable on disk and in a session" {
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
    var child = try std.process.spawn(testing.io, .{ .argv = &.{ compiler_path, "check-session", entry }, .stdin = .{ .file = input }, .stdout = .{ .file = output }, .stderr = .ignore });
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
    try writeProjectFile(&temp, "entry/main.my", policy_project_main);
    try writeProjectFile(&temp, "entry/helper.my", policy_project_helper);
    try writeProjectFile(&temp, "entry/mylang.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try writeProjectFile(&temp, "entry/policy.json", policy_deny);
    try writeProjectFile(&temp, "elsewhere/main.my", "func main() -> int:\n    return 0\n");
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
    try writeProjectFile(&temp, "main.my", "import helper\nfunc main() -> int:\n    return helper.value()\n");
    try writeProjectFile(&temp, "helper.my", "import main\npublic func value() -> int effects():\n    return 0\n");
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
        \\import helper
        \\
        \\
        \\func main() -> int:
        \\    return 0
        \\
        \\
        \\public func test_policy() -> bool effects():
        \\    return helper.value() == 7
    );
    try writeProjectFile(&temp, "helper.my", "public func value() -> int effects():\n    return 7\n");
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
    try writeProjectFile(&temp, "main.my", "func main() -> int:\n    return 0\n");
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
        \\import helper
        \\
        \\
        \\func main() -> int:
        \\    return 0
        \\
        \\
        \\public func test_policy() -> bool effects():
        \\    return helper.value() == 7
    );
    try writeProjectFile(&temp, "helper.my", "public func value() -> int effects():\n    return 7\n");
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

// spec: MUTATION-ENFORCE-1
test "CLI migrated corpus projects carry the checked mutation contract" {
    // The corpus pieces M3 repaired: domain methods exposed through an exported
    // type, a generated input accessor and guest tests that allocate. Every one
    // needs an explicit, narrow ceiling.
    for ([_][]const u8{
        "examples/modules/main.my",
        "examples/input-values/main.my",
        "tests/guest/generics.my",
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
    try invoke("check", rejected, 1, "", "E_MUTATION_PERMISSION");
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
    \\
    \\
    \\public domain Stub: int:
    \\    func make(discount: int) -> Stub effects():
    \\        return wrap[Stub](discount)
    \\
    \\    func price(policy: Stub, mut ledger: int[], rates: int[], subtotal: int) -> int effects(mutation):
    \\        return todo[int]()
;
/// Production with the whole derived ceiling written out, so a replacement can
/// narrow the clause while keeping the signature.
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
const p1_main =
    \\import production
    \\
    \\
    \\func main() -> int:
    \\    return 0
    \\
    \\
    \\public func test_checkout() -> bool:
    \\    mut policy = production.Stub.make(250)
    \\    mut ledger: int[] = [0]
    \\    mut rates: int[] = [0]
    \\    return production.Stub.price(policy, mut ledger, rates, 2000) == 1750
;
/// A replacement `production.Stub.price` whose managed parameters, effect
/// clause and first body line vary; `ledger` is the production footprint.
fn p1Fake(parameters: []const u8, perm: []const u8, body: []const u8) ![]const u8 {
    return std.fmt.allocPrint(
        testing.allocator,
        "public domain Stub: int:\n" ++
            "    func make(discount: int) -> Stub effects():\n        return wrap[Stub](discount)\n\n" ++
            "    func price(policy: Stub, {s}, subtotal: int) -> int {s}:\n        {s}\n        return subtotal - unwrap(policy)\n",
        .{ parameters, perm, body },
    );
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
    try args.appendSlice(testing.allocator, &.{ compiler_path, "test", entry, "--filter", "test_checkout", "--json", cache_arg });
    if (cases_path) |path| try args.appendSlice(testing.allocator, &.{ "--cases", path });
    try args.appendSlice(testing.allocator, &tools);
    return runCompiler(testing.allocator, args.items);
}

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
    try testing.expect(std.mem.indexOf(u8, edited.stdout, "\"failed\":1") != null);

    // A full production check still rejects the unfinished body.
    const full = try p1Invoke(entry, null, cache);
    defer testing.allocator.free(full.stdout);
    defer testing.allocator.free(full.stderr);
    try testing.expect(full.term != .exited or full.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, full.stderr, "E_TYPED_HOLE") != null);
}

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
        .{ "ledger: int[], rates: int[]", "_ = subtotal" },
        .{ "mut ledger: int[], mut rates: int[]", "ledger[0] = subtotal\n        rates[0] = subtotal" },
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

    // A changed production footprint rejects a provider built for the earlier interface.
    try writeProjectFile(&temp, "production.my", p1_production_bad_interface);
    try p1WriteCases(&temp, "cases.json", "production.my", narrow);
    const interface_error = try p1Invoke(entry, cases_path, cache);
    defer testing.allocator.free(interface_error.stdout);
    defer testing.allocator.free(interface_error.stderr);
    try testing.expect(interface_error.term != .exited or interface_error.term.exited != 0);
    try testing.expect(std.mem.indexOf(u8, interface_error.stderr, "IncompatibleProvider") != null);
}

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
        .{ .label = "generic requirement", .from = "func price(policy:", .to = "func price[T: copy](policy:" },
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

test "P1 ignores an unselected production body type error while its declarations stay valid" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
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
    \\public func size(values: Counts) -> Count effects():
    \\    return values[0] + values[1]
    \\
    \\
    \\public func pick(value: Chosen) -> Count effects():
    \\    return value.left
    \\
    \\
    \\public func test_alias() -> Truth effects():
    \\    return True
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

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
    \\public func test_reading() -> bool effects():
    \\    return reading.sample() == 42
    \\
    \\
    \\func main() -> int:
    \\    return 0
;
const r3_scalar_production =
    \\
    \\
    \\public func sample() -> int effects():
    \\    return todo[int]()
;
const r3_nominal_main =
    \\import reading
    \\
    \\
    \\public func test_reading() -> bool effects():
    \\    return True
    \\
    \\
    \\func main() -> int:
    \\    return 0
;
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
        \\
        \\
        \\public func sample() -> i64 effects():
        \\    return 42
    ;
    try r3WriteCases(&temp, "cases.json", "main::test_reading", "reading.my", equivalent);
    const accepted = try r3TestInvoke(entry, cases_path, cache);
    defer testing.allocator.free(accepted.stdout);
    defer testing.allocator.free(accepted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, accepted.term);
    try testing.expect(std.mem.indexOf(u8, accepted.stdout, "\"passed\":1") != null);

    const scalar_variants = [_][]const u8{
        \\
        \\
        \\public func sample() -> u8 effects():
        \\    return 42
        ,
        \\
        \\
        \\public func sample() -> str effects():
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
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.my" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);

    const library_render40 =
        \\
        \\
        \\public func render[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 40
        \\
        \\
        \\public func label[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 7
    ;
    const library_render41 =
        \\
        \\
        \\public func render[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 41
        \\
        \\
        \\public func label[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 7
    ;
    const library_label8 =
        \\
        \\
        \\public func render[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 41
        \\
        \\
        \\public func label[T: integer](value: T) -> i64 effects():
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
        \\
        \\
        \\func helper(n: i64) -> i64 effects():
        \\    return n + 1
        \\
        \\
        \\public func render[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return helper(40)
    ;
    const edited_library =
        \\
        \\
        \\func helper(n: i64) -> i64 effects():
        \\    return n + 2
        \\
        \\
        \\public func render[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return helper(40)
    ;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "lib.my", .data = base_library });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data =
        \\import lib
        \\
        \\
        \\func main() -> i64:
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
        \\func size[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 7
        \\
        \\
        \\func main() -> i64:
        \\    return size[u8](1u8)
    ;
    const edited =
        \\func size[T: integer](value: T) -> i64 effects():
        \\    _ = value
        \\    return 7
        \\
        \\
        \\func main() -> i64:
        \\    mut value = size[u8](1u8)
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
        \\func size[T: integer](value: T) -> i64 effects():
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
    const entry = try std.fs.path.join(testing.allocator, &.{ directory, "main.my" });
    defer testing.allocator.free(entry);
    const cache_base = try std.fs.path.join(testing.allocator, &.{ directory, "cache" });
    defer testing.allocator.free(cache_base);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_base});
    defer testing.allocator.free(cache_argument);
    const base =
        \\func size[T: integer](value: T, extra: i64 = 5) -> i64 effects():
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
        \\func size[T: integer](value: T, extra: i64 = 5) -> i64 effects():
        \\    mut unused_local = 3
        \\    _ = value
        \\    return extra
        \\
        \\
        \\func main() -> i64:
        \\    mut a = size[u8](1u8)
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
    try args.appendSlice(testing.allocator, &.{ compiler_path, "test", paths.entry, "--json", cache_arg });
    try args.appendSlice(testing.allocator, &tools);
    var environment: std.process.Environ.Map = .init(testing.allocator);
    defer environment.deinit();
    try environment.put("MYLANG_TEST_TRACE", paths.trace);
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "util.my", .data = "public func ratio(n: int, d: int) -> int:\n    return n // d\npublic func test_ratio() -> bool:\n    return ratio(6, 0) == 1\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = "import util\nfunc main() -> int:\n    return 0\npublic func test_said(out: Stream) -> bool effects(output):\n    out.print(\"said\")\n    return util.ratio(4, 2) == 3\n" });
    const entry = try std.fs.path.join(a, &.{ directory, "main.my" });
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
    \\
    \\
    \\public func test_chatty(out: Stream) -> bool effects(output, managed_allocation):
    \\    out.print("debug-marker")
    \\    return True
    \\
    \\
    \\public func test_failing(out: Stream) -> bool effects(output, managed_allocation):
    \\    out.print("debug-marker")
    \\    return False
    \\
    \\
    \\public func test_assert(out: Stream) -> bool effects(output, managed_allocation):
    \\    out.print("debug-marker")
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
    \\
    \\
    \\public func test_value() -> int effects():
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
    \\
    \\
    \\public func test_count() -> bool effects():
    \\    return 3 == 3
;

const bare_test_entry_program =
    \\
    \\
    \\public func test_bare() -> bool effects():
    \\    return True
;

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
    \\import helper
    \\
    \\
    \\public func test_main() -> bool effects():
    \\    return helper.value() == 7
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

const directory_project_helper =
    \\
    \\
    \\public func value() -> int effects():
    \\    return 7
;

const directory_project_test =
    \\
    \\
    \\public func test_alone() -> bool effects():
    \\    return True
;

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
    try testing.expectEqual(@as(i64, 2), report.object.get("passed").?.integer);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "main::test_main") != null);
    try testing.expect(std.mem.indexOf(u8, run.stdout, "library_test::test_alone") != null);
    try testing.expect(std.mem.indexOf(u8, run.stderr, "E_MODULE_NAME") == null);
}

const directory_orphan_inner =
    \\
    \\
    \\public func base() -> int effects():
    \\    return 40
    \\
    \\
    \\public func test_inner() -> bool effects():
    \\    return base() == 40
;

const directory_orphan_outer =
    \\import inner
    \\
    \\
    \\public func test_outer() -> bool effects():
    \\    return inner.base() + 2 == 42
;

const directory_helper_with_test =
    \\
    \\
    \\public func value() -> int effects():
    \\    return 7
    \\
    \\
    \\public func test_helper() -> bool effects():
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
    try writeProjectFile(&temporary, "suite/main.my", directory_project_main);
    try writeProjectFile(&temporary, "suite/helper.my", directory_project_helper);
    try writeProjectFile(&temporary, "suite/unrelated.my", directory_orphan_inner);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const entry = try std.fs.path.join(a, &.{ root, "suite", "main.my" });
    const run = try guestTestRun(a, entry, &.{"--json"}, try std.fs.path.join(a, &.{ root, "cache" }));
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run.term);
    const report = (try std.json.parseFromSlice(std.json.Value, a, run.stdout, .{})).value;
    const sources = report.object.get("sources").?.array.items;
    try testing.expectEqual(@as(usize, 2), sources.len);
    try testing.expectEqualStrings(entry, sources[0].string);
    try testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, "suite", "helper.my" }), sources[1].string);
}

// spec-case: LINT-5
test "CLI list-interfaces prints a tests column from the shared reachability index" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\
        \\
        \\public func parse(value: int) -> int:
        \\    return value
        \\
        \\
        \\func test_parse() -> bool effects():
        \\    return parse(1) == 1
        \\
        \\
        \\func main() -> int:
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

// spec: RELEASE-CHECKED-1
test "every building and running command refuses --unchecked as removed" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "refused.my", .data =
        \\func main() -> i64:
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
    const warm_test = try contractCommand(&.{ compiler_path, "test", entry, cache_argument, tools[0] });
    defer freeResult(warm_test);
    try testing.expect(std.mem.indexOf(u8, warm_test.stdout, "2 passed") != null);
    const warm_run = try contractCommand(&.{ compiler_path, "run", entry, cache_argument, tools[0] });
    defer freeResult(warm_run);
    try testing.expectEqual(std.process.Child.Term{ .exited = 5 }, warm_run.term);
    // Only the precondition changes: the same caches must now trap under it.
    try writeContractFixture(temporary.dir, "amount > 10", "self.low <= self.high");
    const run = try contractCommand(&.{ compiler_path, "run", entry, cache_argument, tools[0] });
    defer freeResult(run);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, run.term);
    try testing.expect(std.mem.indexOf(u8, run.stderr, "error[R_REQUIRES]: precondition violated: half requires `amount > 10`") != null);
    const tested = try contractCommand(&.{ compiler_path, "test", entry, cache_argument, tools[0] });
    defer freeResult(tested);
    try testing.expect(std.mem.indexOf(u8, tested.stdout, "failed main::test_half: R_REQUIRES: half requires `amount > 10`") != null);
    try testing.expect(std.mem.indexOf(u8, tested.stdout, "1 failed") != null);
    // An invariant lives on another declaration than the body that checks it.
    try writeContractFixture(temporary.dir, "amount > 10", "self.low > self.high");
    const rechecked = try contractCommand(&.{ compiler_path, "test", entry, cache_argument, tools[0] });
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "caller.my", .data =
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
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.my" });
    defer testing.allocator.free(entry);
    const caller = try std.fs.path.join(testing.allocator, &.{ root, "caller.my" });
    defer testing.allocator.free(caller);
    const program = try std.fs.path.join(testing.allocator, &.{ root, "program" });
    defer testing.allocator.free(program);
    const cache_argument = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{root});
    defer testing.allocator.free(cache_argument);
    const built = try contractCommand(&.{ compiler_path, "build", entry, "-o", program, "--release", cache_argument, tools[0] });
    defer freeResult(built);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const released = try contractCommand(&.{program});
    defer freeResult(released);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, released.term);
    try testing.expect(std.mem.indexOf(u8, released.stderr, "error[R_ENSURES]: postcondition violated: grow ensures `result > 100`") != null);
    const json = try contractCommand(&.{ compiler_path, "run", caller, "--diagnostics=json", cache_argument, tools[0] });
    defer freeResult(json);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, json.term);
    try testing.expect(std.mem.indexOf(u8, json.stderr, "\"code\":\"R_REQUIRES\"") != null);
    try testing.expect(std.mem.indexOf(u8, json.stderr, "\"contract\":{\"kind\":\"requires\",\"subject\":\"half\",\"clause\":\"amount > 0\",\"message\":\"amount must be positive\",\"caller\":{") != null);
}

/// One project directory holding `main.my`, with its own test cache, for the
/// property-test CLI runs below.
const PropertyProject = struct {
    temporary: std.testing.TmpDir,
    path: [:0]const u8,
    cache: []const u8,

    fn init(source: []const u8) !PropertyProject {
        var temporary = testing.tmpDir(.{});
        errdefer temporary.cleanup();
        try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = source });
        const path = try temporary.dir.realPathFileAlloc(testing.io, "main.my", testing.allocator);
        errdefer testing.allocator.free(path);
        const root = try temporary.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
        defer testing.allocator.free(root);
        return .{ .temporary = temporary, .path = path, .cache = try std.fs.path.join(testing.allocator, &.{ root, ".mylang-test-cache" }) };
    }
    fn deinit(self: *PropertyProject) void {
        testing.allocator.free(self.path);
        testing.allocator.free(self.cache);
        self.temporary.cleanup();
    }
    /// `mylang test main.my` with the project cache and `extra` arguments.
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
    \\
    \\public func test_sum_stays_below_100(xs: int[]) -> bool:
    \\    mut total = 0
    \\    for x in xs:
    \\        total = total + x
    \\    return total < 100
    \\
    \\public func test_reversing_twice_is_the_identity(xs: int[]) -> bool:
    \\    mut ys = xs.copy()
    \\    ys.reverse()
    \\    ys.reverse()
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
    try testing.expect(std.mem.indexOf(u8, text.stdout, "  reason: returned False\n  reproduce: mylang test ") != null);
    try testing.expect(std.mem.indexOf(u8, text.stdout, "main.my --filter 'main::test_sum_stays_below_100' --seed ") != null);
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

const refused_properties =
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

// spec: PROPERTY-TEST-1
test "CLI property test names the parameter and type it cannot generate" {
    var project = try PropertyProject.init(refused_properties);
    defer project.deinit();
    const result = try project.run(&.{});
    defer freeRun(result);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "failed main::test_domain: property test parameter `m: main::Meters` cannot be generated: a domain is built only through its own constructors") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "failed main::test_function: property test parameter `f: func(i64) -> i64") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "a function value cannot be generated") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "failed main::test_host: property test parameter `host: Host` cannot be generated: a Host capability is never handed to a test") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "failed main::test_count: a property test returns bool or Result[bool, E], not i64") != null);
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
    \\    while n > 1000000:
    \\        spins = spins + 1
    \\    return spins == 0
    \\
    \\func main() -> int:
    \\    return 0
;

// spec: PROPERTY-TEST-4
test "CLI property test runs in one process, reuses a pass until its seed or runs change, and survives a child that dies mid-batch" {
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
    // An input that never finishes kills its batch at the timeout; the inputs
    // before it keep their answers, it is run alone, and it is the failure.
    var hanging = try PropertyProject.init(hanging_property);
    defer hanging.deinit();
    const hung = try hanging.run(&.{ "--timeout-ms", "1000", "--max-steps", "4000000000" });
    defer freeRun(hung);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, hung.term);
    try testing.expect(std.mem.indexOf(u8, hung.stdout, "failed main::test_finishes: falsified after ") != null);
    try testing.expect(std.mem.indexOf(u8, hung.stdout, "  input (not shrunk: it ran out of time, and so could every candidate):") != null);
    try testing.expect(std.mem.indexOf(u8, hung.stdout, "  reason: the input ran past --timeout-ms 1000") != null);
}

const boundary_values =
    \\
    \\public func test_echo_set(s: set[str]) -> set[str]:
    \\    mut t = s.copy()
    \\    t.add("zz")
    \\    return t
    \\
    \\public func test_echo_dict(d: dict[tuple[int, str], float]) -> dict[tuple[int, str], float]:
    \\    mut e = d.copy()
    \\    e[(9, "k")] = 0.5
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
    \\ "main::test_echo_dict":{"arguments":{"d":[[{"$0":"1","$1":"x"},"1.5"],[{"$0":"-3","$1":""},"nan"]]},
    \\   "expected":[[{"$0":"1","$1":"x"},"1.5"],[{"$0":"-3","$1":""},"nan"],[{"$0":"9","$1":"k"},"0.5"]]},
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
    \\
    \\func parse(text: str) -> Result[int, str]:
    \\    if len(text) > 3:
    \\        return Err("too long")
    \\    return Ok(len(text))
    \\
    \\func checked(text: str) -> Result[int, str]:
    \\    mut size = try parse(text)
    \\    return Ok(size)
    \\
    \\public func test_short_text_parses(text: str) -> Result[bool, str]:
    \\    mut size = try checked(text)
    \\    return Ok(size <= 3)
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
    try testing.expect(std.mem.indexOf(u8, text.stdout, "main.my:4:16") != null);
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
    \\    rt.objects.append(value)
    \\func main() -> int:
    \\    mut it = Interp(rt=Runtime(objects=[1, 2]))
    \\    mut saved = it.rt
    \\    mut seen = 0
    \\    for x in it.rt.objects:
    \\        seen = seen + x
    \\        if x < 3:
    \\            mut wb = it.rt
    \\            push(mut wb, x + 2)
    \\            it.rt = wb
    \\    return if (seen == 10 and len(it.rt.objects) == 4 and saved.objects == [1, 2]) then (0) else (1)
;

// spec-case: RC-ITERATION-HOLD-TRANSFER-1
test "CLI growth written back through a named field remains live" {
    try invokeOptions("run", iterated_write_back, &.{}, 0, "0\n", "");
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
    inline for (.{ "check", "check-module", "fmt", "fmt-module", "run", "lint", "list-modules", "run-project", "list-declarations", "dump-tokens" }) |command| {
        try expectRefused(dir, &.{ compiler_path, command, "nope.my" }, "mylang " ++ command ++ ": cannot read 'nope.my': no such file or directory\n");
        try expectRefused(dir, &.{ compiler_path, command, "adir" }, "mylang " ++ command ++ ": cannot read 'adir': is a directory, not a file\n");
    }
}

/// The refusal a file this process cannot read gets, or nothing when it can read
/// it anyway (running as root), where there is nothing to refuse.
fn expectUnreadableRefused(dir: std.Io.Dir, command: []const u8) !void {
    try dir.writeFile(testing.io, .{ .sub_path = "locked.my", .data = "func main() -> int:\n    return 0\n" });
    try dir.setFilePermissions(testing.io, "locked.my", std.Io.File.Permissions.fromMode(0), .{});
    const readable = dir.openFile(testing.io, "locked.my", .{});
    if (readable) |file| {
        file.close(testing.io);
        return;
    } else |_| {}
    const sentence = try std.fmt.allocPrint(testing.allocator, "mylang {s}: cannot read 'locked.my': permission denied\n", .{command});
    defer testing.allocator.free(sentence);
    try expectRefused(dir, &.{ compiler_path, command, "locked.my" }, sentence);
}

// spec: CLI-INPUT-REFUSED-1
test "a missing, unreadable or directory entry is refused by name with the usage status" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDir(testing.io, "adir", .default_dir);
    const missing = "no such file or directory";
    try expectEveryEntryCommandRefused(temp.dir);
    try expectRefused(temp.dir, &.{ compiler_path, "build", "nope.my", "-o", "out.bin" }, "mylang build: cannot read 'nope.my': " ++ missing ++ "\n");
    try expectRefused(temp.dir, &.{ compiler_path, "build", "adir", "-o", "out.bin" }, "mylang build: cannot read 'adir': is a directory, not a file\n");
    try expectRefused(temp.dir, &.{ compiler_path, "test", "nope.my" }, "mylang test: cannot read 'nope.my': " ++ missing ++ "\n");
    try expectRefused(temp.dir, &.{ compiler_path, "fix", "nope.my" }, "mylang fix: cannot read 'nope.my': " ++ missing ++ "\n");
    try expectRefused(temp.dir, &.{ compiler_path, "api", "nope.my", "--check" }, "mylang api: cannot read 'nope.my': " ++ missing ++ "\n");
    try expectUnreadableRefused(temp.dir, "check");
    // The refusal is in the structured diagnostic format when one is asked for.
    const json = try runInDirectory(temp.dir, &.{ compiler_path, "check", "nope.my", "--diagnostics=json" });
    defer freeRun(json);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, json.term);
    try testing.expect(std.mem.indexOf(u8, json.stderr, "cannot read 'nope.my'") != null);
    // A refused input leaves no cache directory behind.
    try testing.expectError(error.FileNotFound, temp.dir.statFile(testing.io, ".mylang-cache", .{}));
}

/// Run one command from inside `dir` with the fixture tools appended and require
/// exit status `wanted`; the compiler path is made absolute for the changed cwd.
fn runToolIn(dir: std.Io.Dir, environ: ?*const std.process.Environ.Map, args: []const []const u8, wanted: u8) !void {
    const absolute = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, testing.allocator);
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
    \\    out.print("hi")
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
    try work.dir.writeFile(testing.io, .{ .sub_path = "prog.my", .data = cache_program });
    const cache_path = try cache.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(cache_path);
    const flag = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}", .{cache_path});
    defer testing.allocator.free(flag);
    try runToolIn(work.dir, null, &.{ "test", "prog.my", "--force", flag }, 0);
    try runToolIn(work.dir, null, &.{ "build", "prog.my", "-o", "prog.bin", flag }, 0);
    try runToolIn(work.dir, null, &.{ "run", "prog.my", flag }, 0);
    try runToolIn(work.dir, null, &.{ "check", "prog.my", flag }, 0);
    try runToolIn(work.dir, null, &.{ "check-project", "prog.my", "--explain-invalidation", flag }, 0);
    try testing.expectError(error.FileNotFound, work.dir.statFile(testing.io, ".mylang-cache", .{}));
    // The named directory took the frontend cache instead.
    _ = try cache.dir.statFile(testing.io, "frontend", .{});
}

// spec-case: CLI-CACHE-DIR-1
test "MYLANG_FRONTEND_CACHE moves the checked-body store and invalidation baseline out of the working directory" {
    var work = testing.tmpDir(.{});
    defer work.cleanup();
    var cache = testing.tmpDir(.{});
    defer cache.cleanup();
    try work.dir.writeFile(testing.io, .{ .sub_path = "prog.my", .data = cache_program });
    const cache_path = try cache.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(cache_path);
    var environment = try std.process.Environ.createMap(testing.environ, testing.allocator);
    defer environment.deinit();
    try environment.put("MYLANG_FRONTEND_CACHE", cache_path);
    try runToolIn(work.dir, &environment, &.{ "check", "prog.my" }, 0);
    try runToolIn(work.dir, &environment, &.{ "check-project", "prog.my", "--explain-invalidation" }, 0);
    try testing.expectError(error.FileNotFound, work.dir.statFile(testing.io, ".mylang-cache", .{}));
    _ = try cache.dir.statFile(testing.io, "semantic", .{});
    _ = try cache.dir.statFile(testing.io, "invalidation", .{});
}

const trivial_run =
    \\func main(out: Stream) -> int:
    \\    out.print("ok")
    \\    return 0
;

/// Run `mylang run` on the trivial program with `options` and, when the run is
/// refused, require exit 2 with `expected` inside the diagnostic on stderr.
fn expectRunRefused(options: []const []const u8, environ: ?*const std.process.Environ.Map, expected: []const u8) !void {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "prog.my", .data = trivial_run });
    const path = try temp.dir.realPathFileAlloc(testing.io, "prog.my", testing.allocator);
    defer testing.allocator.free(path);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.appendSlice(testing.allocator, &.{ compiler_path, "run", path });
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
        try expectRunRefused(bad, null, "usage: mylang run <file.my> [options] [-- ARGS...]");
    }
    try expectRunRefused(&.{"--bogus"}, null, "--max-frames N     call-depth ceiling");
    // The general text opens with the `test` usage; `run` must not print it.
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "prog.my", .data = trivial_run });
    const path = try temp.dir.realPathFileAlloc(testing.io, "prog.my", testing.allocator);
    defer testing.allocator.free(path);
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "run", path, "--bogus" } });
    defer freeRun(outcome);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "mylang test <entry.my>") == null);
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "prog.my", .data = cache_program });
    const refused = try runInDirectory(temp.dir, &.{ compiler_path, "test", "prog.my", "--max-frames", "30000" });
    defer freeRun(refused);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, refused.term);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "mylang test: a call-depth budget of 30000 frames (--max-frames) reserves 946 MiB of native stack (32 KiB per frame), but a test may map only 768 MiB") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "raise --max-memory to at least 1G") != null);
    try runToolIn(temp.dir, null, &.{ "test", "prog.my", "--force", "--max-frames", "30000", "--max-memory", "1G" }, 0);
}

// spec-case: RUN-FRAME-BUDGET-1
test "a built program reports the frame reservation its address space cannot back" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const output = try buildExecutable(&temp, trivial_run);
    defer testing.allocator.free(output);
    var environment = try runtimeOptions("--max-frames=150000");
    defer environment.deinit();
    try environment.put("MYLANG_MEMORY_LIMIT", "1G");
    const outcome = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{output}, .environ_map = &environment });
    defer freeRun(outcome);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "a call-depth budget of 150000 frames (--max-frames) reserves 4.6 GiB of native stack (32 KiB per frame), but this process may map only 1.2 GiB") != null);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "OutOfMemory: QBE runtime failure") == null);
}

/// Write `mylang.json` and the trivial program into `dir`, one project.
fn writeLimitedProject(dir: std.Io.Dir, limits: []const u8) !void {
    const config = try std.fmt.allocPrint(testing.allocator, "{{\"version\":1,\"limits\":{s}}}", .{limits});
    defer testing.allocator.free(config);
    try dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = config });
    try dir.writeFile(testing.io, .{ .sub_path = "prog.my", .data = cache_program });
}

/// Run `command prog.my` in `dir` and return its outcome; the caller frees it.
fn runLimited(dir: std.Io.Dir, args: []const []const u8) !std.process.RunResult {
    const absolute = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, testing.allocator);
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
test "mylang.json limits set the run and test defaults and the command line still wins" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    // A configured frame budget the default ceiling cannot back is refused exactly as the flag is.
    try writeLimitedProject(temp.dir, "{\"run\":{\"max_frames\":150000},\"test\":{\"max_frames\":30000}}");
    const configured = try runLimited(temp.dir, &.{ "run", "prog.my" });
    defer freeRun(configured);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, configured.term);
    try testing.expect(std.mem.indexOf(u8, configured.stderr, "a call-depth budget of 150000 frames (--max-frames) reserves 4.6 GiB") != null);
    // The flag overrides the file: 5000 frames fit, and the program runs.
    const overridden = try runLimited(temp.dir, &.{ "run", "prog.my", "--max-frames", "5000" });
    defer freeRun(overridden);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, overridden.term);
    try testing.expectEqualStrings("hi\n", overridden.stdout);
    // Guest arguments after `--` are untouched by configured options.
    const guest = try runLimited(temp.dir, &.{ "run", "prog.my", "--max-frames=5000", "--", "--max-frames=1" });
    defer freeRun(guest);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, guest.term);
    // `mylang test` reads `limits.test` the same way.
    const tests_refused = try runLimited(temp.dir, &.{ "test", "prog.my", "--force" });
    defer freeRun(tests_refused);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, tests_refused.term);
    try testing.expect(std.mem.indexOf(u8, tests_refused.stderr, "mylang test: a call-depth budget of 30000 frames") != null);
    const tests_overridden = try runLimited(temp.dir, &.{ "test", "prog.my", "--force", "--max-frames=1024" });
    defer freeRun(tests_overridden);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, tests_overridden.term);
    // A configured max_memory that holds the configured budget lets both commands run it.
    try writeLimitedProject(temp.dir, "{\"run\":{\"max_frames\":30000,\"max_memory\":\"2G\"},\"test\":{\"max_frames\":30000,\"max_memory\":\"1G\"}}");
    const run_ok = try runLimited(temp.dir, &.{ "run", "prog.my" });
    defer freeRun(run_ok);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, run_ok.term);
    const test_ok = try runLimited(temp.dir, &.{ "test", "prog.my", "--force" });
    defer freeRun(test_ok);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, test_ok.term);
}

test {
    _ = @import("fix_cli_test.zig");
}

// spec-case: EMBED-2
test "check reports an embed's diagnostic at its literal and exits nonzero" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = "func main() -> int:\n    return len(embed_bytes(\"absent.bin\"))\n" });
    const entry = try std.fs.path.join(a, &.{ root, "main.my" });
    const result = try std.process.run(a, testing.io, .{ .argv = &.{ compiler_path, "check", entry } });
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "main.my:2:28: error[E_EMBED_MISSING]") != null);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "absent.bin", .data = "x" });
    const found = try std.process.run(a, testing.io, .{ .argv = &.{ compiler_path, "check", entry } });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, found.term);
}

// spec-case: EMBED-3
test "mylang test runs a module that embeds and reruns it when only the fixture changes" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    try temporary.dir.createDirPath(testing.io, "fixtures");
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "fixtures/nul.bin", .data = "a\x00b" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "emb.my", .data = "\nconst NUL: bytes = embed_bytes(\"fixtures/nul.bin\")\n\n\npublic func test_nul() -> bool:\n    return len(NUL) == 3 and NUL[1] == 0\n" });
    const entry = try std.fs.path.join(a, &.{ root, "emb.my" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const argv = [_][]const u8{ compiler_path, "test", entry, "--cache-dir", cache, tools[0] };
    const first = try std.process.run(a, testing.io, .{ .argv = &argv });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    try testing.expect(std.mem.indexOf(u8, first.stdout, "passed emb::test_nul") != null);
    const again = try std.process.run(a, testing.io, .{ .argv = &argv });
    try testing.expect(std.mem.indexOf(u8, again.stdout, "cached emb::test_nul") != null);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "fixtures/nul.bin", .data = "a\x00bc" });
    const changed = try std.process.run(a, testing.io, .{ .argv = &argv });
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, changed.term);
    try testing.expect(std.mem.indexOf(u8, changed.stdout, "failed emb::test_nul") != null);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "fixtures/nul.bin", .data = "a\x00b" });
    const restored = try std.process.run(a, testing.io, .{ .argv = &argv });
    try testing.expect(std.mem.indexOf(u8, restored.stdout, "cached emb::test_nul") != null);
}

/// Exercise a real guest reservation and, optionally, a caller's soft ceiling.
fn expectGuestFrames(frames: []const u8, external: bool, expected_status: u8) !void {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "prog.my", .data = trivial_run });
    const path = try temp.dir.realPathFileAlloc(testing.io, "prog.my", a);
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", a);
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    var environment = try std.process.Environ.createMap(testing.environ, a);
    try environment.put("MYLANG_HOST_MEMORY_LIMIT", if (external) "4G" else "8G");
    var argv: std.ArrayList([]const u8) = .empty;
    if (external) try argv.appendSlice(a, &.{ "sh", "-c", "ulimit -S -v 6291456; exec \"$@\"", "caller-limit" });
    try argv.appendSlice(a, &.{ compiler_path, "run", path, frames, "--max-memory=12G", "--print-result", try std.fmt.allocPrint(a, "--cache-dir={s}", .{cache}) });
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
    try argv.appendSlice(allocator, &.{ compiler_path, command, entry });
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = embed_tooling_source });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "data.bin", .data = "abcd" });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.my", a);
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = try std.fmt.allocPrint(a, "{{\"version\":1,\"budgets\":{{\"max_total_bytes\":{d}}}}}", .{total}) });
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = "public func test_ok() -> bool:\n    return True\n" });
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    var environment = try std.process.Environ.createMap(testing.environ, a);
    try environment.put("MYLANG_HOST_MEMORY_LIMIT", "8G");
    _ = environment.swapRemove("MYLANG_HOST_LIMIT_CHECKPOINT");
    _ = environment.swapRemove("MYLANG_HOST_LIMIT_RESTORE");
    const result = try std.process.run(a, testing.io, .{ .argv = &(.{ compiler_path, "test", root, "--max-memory=12G", "--max-frames=300000", "--jobs=1", "--cache-dir", cache } ++ tools), .environ_map = &environment });
    testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term) catch |err| {
        std.debug.print("directory host receipt: {s}\n{s}\n", .{ result.stdout, result.stderr });
        return err;
    };
    try testing.expect(std.mem.indexOf(u8, result.stdout, "1 passed") != null);
}

const snapshot_embed_main = "import data\n\nconst A: bytes = embed_bytes(\"data.bin\")\nconst B: bytes = embed_bytes(\"data.bin\")\n\nfunc main() -> int:\n    return 0\n\npublic func test_payload() -> bool:\n    return A == b\"abcd\" and B == A and data.C == A\n";
const snapshot_embed_data = "\npublic const C: bytes = embed_bytes(\"data.bin\")\n";

/// Run a real snapshot test and preserve the located budget diagnostic on refusal.
fn expectSnapshotBudget(allocator: std.mem.Allocator, entry: []const u8, cache: []const u8, expected_status: u8) !void {
    const result = try std.process.run(allocator, testing.io, .{ .argv = &(.{ compiler_path, "test", entry, "--cache-dir", cache, "--force" } ++ tools) });
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = snapshot_embed_main });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "data.my", .data = snapshot_embed_data });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "data.bin", .data = "abcd" });
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.my", a);
    const root = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const total = snapshot_embed_main.len + snapshot_embed_data.len + 8;
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = try std.fmt.allocPrint(a, "{{\"version\":1,\"budgets\":{{\"max_total_bytes\":{d}}}}}", .{total}) });
    try expectSnapshotBudget(a, entry, cache, 0);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = try std.fmt.allocPrint(a, "{{\"version\":1,\"budgets\":{{\"max_total_bytes\":{d}}}}}", .{total - 1}) });
    try expectSnapshotBudget(a, entry, cache, 1);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "mylang.json", .data = try std.fmt.allocPrint(a, "{{\"version\":1,\"budgets\":{{\"max_total_bytes\":{d}}}}}", .{total}) });
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
    try writeProjectFile(&temporary, "main.my", "import dependency\n\npublic func test_fixture() -> bool:\n    return dependency.value() == 7\n");
    try writeProjectFile(&temporary, "dependency.my", "\npublic func value() -> int effects():\n    return 7\n");
    try writeProjectFile(&temporary, "fixture.my", "\npublic const DATA: bytes = embed_bytes(\"fixture.bin\")\n");
    try writeProjectFile(&temporary, "fixture.bin", "1234567");
    try r3WriteCases(&temporary, "cases.json", "main::test_fixture", "dependency.my", "import fixture\n\npublic func value() -> int effects():\n    return len(fixture.DATA)\n");
    const entry = try temporary.dir.realPathFileAlloc(testing.io, "main.my", a);
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
    try invokeOptions("run", "func main(args: str[], out: Stream) -> int:\n    out.print(len(args), args[1])\n    return 0\n", &.{ "--", "--release", "b" }, 0, "2 b\n0\n", "");
    try invokeOptions("run", s5_loop, &.{"--max-steps=1000"}, 1, "", "R_STEP_LIMIT");
    // A counting loop can be optimized directly to its eventual overflow trap.
    const endless = "func main() -> int:\n    while True:\n        pass\n    return 0\n";
    try invokeOptions("run", endless, &.{ "--timeout", "1" }, 1, "", "R_TIMEOUT");
    const deep = "func down(n: int) -> int:\n    if n == 0:\n        return 0\n    return down(n - 1) + 1\n\nfunc main() -> int:\n    return down(100000)\n";
    try invokeOptions("run", deep, &.{"--max-frames=100"}, 1, "", "R_FRAME_LIMIT");
    const grow = "func main() -> int:\n    mut xs: int[] = []\n    mut i = 0\n    while i < 100000000:\n        xs.append(i)\n        i = i + 1\n    return len(xs)\n";
    try invokeOptions("run", grow, &.{"--max-memory=16M"}, 1, "", "R_MEMORY_BUDGET");
    try invokeOptions("run", "func main(clock: Clock) -> int:\n    _ = clock\n    return 0\n", &.{"--restrict"}, 2, "", "pass --allow-clock");
    try invokeOptions("run", "func main() -> int:\n    return 0\n", &.{"--allow-read="}, 2, "", "usage: mylang run");
}

// spec: NEW-CORE-S5-RETIRED-1
test "the old back end's commands and flags are refused by name with what replaces them" {
    const program = "func main() -> int:\n    return 0\n";
    try invoke("invoke", program, 2, "", "retired with host functions");
    try invoke("emit-qbe", program, 2, "", "QBE IL emission was retired");
    try invoke("dump-bytecode", program, 2, "", "mylang dump-ir");
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
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.my", .data = "import helper\n\nfunc main() -> int:\n    return helper.two()\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data = "\npublic func two() -> int:\n    return \"two\"\n" });
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const entry = try std.fs.path.join(testing.allocator, &.{ root, "main.my" });
    defer testing.allocator.free(entry);
    const cache = try std.fmt.allocPrint(testing.allocator, "--cache-dir={s}/cache", .{root});
    defer testing.allocator.free(cache);
    const rejected = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check", entry, cache } });
    defer testing.allocator.free(rejected.stdout);
    defer testing.allocator.free(rejected.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, rejected.term);
    try testing.expect(std.mem.indexOf(u8, rejected.stderr, "helper.my:3:") != null);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "helper.my", .data = "\npublic func two() -> int:\n    return 2\n" });
    const accepted = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ compiler_path, "check", entry, cache } });
    defer testing.allocator.free(accepted.stdout);
    defer testing.allocator.free(accepted.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, accepted.term);
    try testing.expectEqualStrings("", accepted.stderr);
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
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data =
        \\public func changed(xs: int[]) -> int[]:
        \\    mut ys = xs
        \\    ys[0] = 4
        \\    return ys
        \\public func unused() -> int:
        \\    return 9
        \\func main(out: Stream) -> int:
        \\    mut xs = [1]
        \\    out.print(changed(xs))
        \\    return 0
    });
    const path = try temporary.dir.realPathFileAlloc(testing.io, "input.my", testing.allocator);
    defer testing.allocator.free(path);
    const plain = try contractCommand(&.{ compiler_path, "list-interfaces", path });
    defer freeResult(plain);
    try testing.expectEqualStrings("", plain.stderr);
    try testing.expect(std.mem.indexOf(u8, plain.stdout, "export function unused") != null);
    const cost = try contractCommand(&.{ compiler_path, "cost", path });
    defer freeResult(cost);
    try testing.expect(std.mem.indexOf(u8, cost.stdout, "changed: checks") != null);
    try testing.expect(std.mem.indexOf(u8, cost.stdout, "unused:") == null);
    try testing.expect(std.mem.indexOf(u8, cost.stdout, "TOTAL:") != null);
    const listed = try contractCommand(&.{ compiler_path, "list-interfaces", path, "--cost" });
    defer freeResult(listed);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, listed.term);
    try testing.expectEqualStrings(plain.stdout, listed.stdout[0..plain.stdout.len]);
    try testing.expectEqualStrings(cost.stdout, listed.stdout[plain.stdout.len..]);
    const again = try contractCommand(&.{ compiler_path, "list-interfaces", path });
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

// spec-case: FRONTEND-CORE-NOALLOC-1
test "F1 check accepts direct and transitive noalloc allocations without warnings" {
    try invoke("check", "func main() -> int noalloc:\n    const xs = [1]\n    return len(xs) - 1\n", 0, "", "");
    try invoke("check", "public func bounded(mut xs: int[]) -> Unit noalloc:\n    xs[0] = 1\n", 0, "", "");
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "F1 run reports a noalloc warning and preserves the program result" {
    try invoke("run", "func main() -> int noalloc:\n    const xs = [1]\n    return len(xs) - 1\n", 0, "0\n", "warning[W_NOALLOC_ALLOCATES]");
}

fn expectNoallocLint(profile: []const u8) !void {
    const outcome = try runFixture("lint", "public func bounded(mut xs: int[]) -> Unit noalloc:\n    xs[0] = 1\nfunc main() -> int:\n    return 0\n", &.{ "--gate", profile });
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
    const outcome = try runFixture("lint", "# lint: allow noalloc-allocates reason=\"this benchmark measures COW\"\npublic func bounded(mut xs: int[]) -> Unit noalloc:\n    xs[0] = 1\n", &.{"--gate"});
    defer testing.allocator.free(outcome.stdout);
    defer testing.allocator.free(outcome.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, outcome.term);
    try testing.expect(std.mem.indexOf(u8, outcome.stderr, "L_NOALLOC_ALLOCATES") == null);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "F1 test receipts retain allocation warnings on replay" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "input.my", .data = "func bounded() -> int noalloc:\n    const xs = [1]\n    return len(xs)\npublic func test_one() -> bool:\n    return bounded() == 1\n" });
    for (0..2) |_| {
        const result = try runInDirectory(temp.dir, &(.{ compiler_path, "test", "input.my" } ++ tools));
        defer freeRun(result);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, result.stderr, "warning[W_NOALLOC_ALLOCATES]"));
    }
}

const unsupported_noalloc =
    \\record Grid:
    \\    port: Stream
    \\    label: str
    \\public func bounded(out: Stream) -> int noalloc:
    \\    out.print(Grid(port=out, label="a"))
    \\    return 0
    \\public func another(mut values: int[]) -> Unit noalloc:
    \\    values[0] = 1
    \\func main() -> int:
    \\    return 0
;

// spec-case: FRONTEND-CORE-NOALLOC-1
test "F1 unsupported unused bounded bodies warn with a reason and still block lint" {
    try invoke("check", unsupported_noalloc, 0, "", "");
    try invoke("run", unsupported_noalloc, 0, "0\n", "Core does not support rendering a non-value source type");
    const result = try runFixture("lint", unsupported_noalloc, &.{"--gate"});
    defer freeRun(result);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, result.term);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, result.stderr, "L_NOALLOC_ALLOCATES"));
    try testing.expect(std.mem.indexOf(u8, result.stderr, "Core does not support rendering a non-value source type") != null);
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
        const path = try std.fmt.allocPrint(testing.allocator, "src/stdlib/{s}.my", .{name});
        defer testing.allocator.free(path);
        const checked = try contractCommand(&.{ compiler_path, "check", path });
        defer freeResult(checked);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
        const formatted = try contractCommand(&.{ compiler_path, "fmt", path, "--check" });
        defer freeResult(formatted);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, formatted.term);
        try testing.expectEqualStrings("", formatted.stderr);
    }
}

// spec-case: INTERNAL-NAME-1
test "F8 formatter rejects internal intrinsics in an ordinary source named math" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "math.my", .data = "func main() -> float:\n    return __float_sqrt(4.0)\n" });
    const path = try temp.dir.realPathFileAlloc(testing.io, "math.my", testing.allocator);
    defer testing.allocator.free(path);
    const result = try contractCommand(&.{ compiler_path, "fmt", path, "--check" });
    defer freeResult(result);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "E_INTERNAL_NAME") != null);
}

// spec-case: INTERNAL-NAME-1
test "F8 formatter withholds standard library trust when any source bytes differ" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const original = try std.Io.Dir.cwd().readFileAlloc(testing.io, "src/stdlib/math.my", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(original);
    const changed = try std.fmt.allocPrint(testing.allocator, "{s}\n", .{original});
    defer testing.allocator.free(changed);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "math.my", .data = changed });
    const path = try temp.dir.realPathFileAlloc(testing.io, "math.my", testing.allocator);
    defer testing.allocator.free(path);
    for ([_][]const u8{ "fmt", "fmt-module" }) |command| {
        const result = try contractCommand(&.{ compiler_path, command, path, "--check" });
        defer freeResult(result);
        try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
        try testing.expect(std.mem.indexOf(u8, result.stderr, "E_INTERNAL_NAME") != null);
    }
}
