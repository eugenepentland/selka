//! The debug build's code generation: `build`, `run` and `build --run` compile each unit with the lean flags unless `--debug-o0`
//! asks for LLVM -O0, `selka test` compiles at -O0 unless `--debug-lean` asks otherwise, a directory run hands its mode to the
//! children it starts, and the two builds of one program behave alike (DEBUG-OPTIMIZE-1).
const std = @import("std");
const testing = std.testing;

const paths = @import("test_paths");
const zig = "--zig=" ++ @import("test_options").zig_path;

/// A program with a loop, a float, a dictionary, text and a list append: enough code for the two builds to differ in what they emit.
const program =
    \\func weigh(items: int[], scale: float) -> float:
    \\    mut total = 0.0
    \\    for item in items:
    \\        total = total + float(item) * scale
    \\    return total
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut items: int[] = []
    \\    mut counts: dict[str, int] = {}
    \\    for step in range(50):
    \\        append(mut items, step * step)
    \\        counts[f"k{step % 7}"] = step
    \\    print(out, weigh(items, 0.5))
    \\    print(out, len(counts))
    \\    const key = "k3"
    \\    print(out, counts[key])
    \\    return 0
    \\
;

/// A program that reads past the end of a list: it traps with a source line.
const trapping =
    \\func pick(items: int[], at: int) -> int:
    \\    return items[at]
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    const items = [1, 2, 3]
    \\    print(out, pick(items, 7))
    \\    return 0
    \\
;

const testing_program =
    \\public func test_one() -> bool:
    \\    return 1 + 1 == 2
    \\
;

const Run = struct { stdout: []const u8, stderr: []const u8, term: std.process.Child.Term };

/// Run the compiler in `dir` with `args` after its name, in a private environment (`extra` adds one variable when given).
fn compiler(a: std.mem.Allocator, dir: std.Io.Dir, args: []const []const u8, extra: ?[2][]const u8) !Run {
    const path = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, paths.corePath(), a);
    const argv = try a.alloc([]const u8, args.len + 1);
    argv[0] = path;
    @memcpy(argv[1..], args);
    var environment = try paths.privateEnvironment(a);
    if (extra) |pair| try environment.put(pair[0], pair[1]);
    const result = try std.process.run(a, testing.io, .{ .argv = argv, .cwd = .{ .dir = dir }, .environ_map = &environment, .stdout_limit = .limited(8 << 20), .stderr_limit = .limited(8 << 20) });
    return .{ .stdout = result.stdout, .stderr = result.stderr, .term = result.term };
}

/// Every 64-digit value that follows `"NAME":"` in `text`, each ended by a comma.
fn valuesOf(a: std.mem.Allocator, text: []const u8, name: []const u8) ![]const u8 {
    const marker = try std.fmt.allocPrint(a, "\"{s}\":\"", .{name});
    var found: std.ArrayList(u8) = .empty;
    var rest = text;
    while (std.mem.indexOf(u8, rest, marker)) |at| {
        const value = rest[at + marker.len ..][0..64];
        try found.appendSlice(a, value);
        try found.append(a, ',');
        rest = rest[at + marker.len + 64 ..];
    }
    return found.items;
}

/// The unit keys of the build of `prog.selka` under `options`, from its report, in a cache directory of its own.
fn buildKeys(a: std.mem.Allocator, dir: std.Io.Dir, name: []const u8, options: []const []const u8) ![]const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ "build", "prog.selka", "-o", name, "--report", "--cache-dir", try std.fmt.allocPrint(a, "{s}-cache", .{name}), zig });
    try argv.appendSlice(a, options);
    const built = try compiler(a, dir, argv.items, null);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const keys = try valuesOf(a, built.stderr, "key");
    try testing.expect(keys.len >= 2 * 65);
    return keys;
}

// spec-case: DEBUG-OPTIMIZE-1
test "a plain build compiles its units as --debug-lean does, and --debug-o0, --optimize-debug and --unoptimized each as a build of their own" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "prog.selka", .data = program });
    const plain = try buildKeys(a, temporary.dir, "plain", &.{});
    const lean = try buildKeys(a, temporary.dir, "lean", &.{"--debug-lean"});
    const o0 = try buildKeys(a, temporary.dir, "o0", &.{"--debug-o0"});
    const o2 = try buildKeys(a, temporary.dir, "o2", &.{"--optimize-debug"});
    const bare = try buildKeys(a, temporary.dir, "bare", &.{"--unoptimized"});
    try testing.expectEqualStrings(plain, lean);
    try testing.expect(!std.mem.eql(u8, plain, o0));
    try testing.expect(!std.mem.eql(u8, plain, o2));
    try testing.expect(!std.mem.eql(u8, o0, o2));
    try testing.expect(!std.mem.eql(u8, o0, bare));
    // The same options in the other spelling: `--mode Debug` is the plain build, and two different modes are refused.
    const mode = try buildKeys(a, temporary.dir, "mode", &.{ "--mode", "Debug" });
    try testing.expectEqualStrings(plain, mode);
    const refused = try compiler(a, temporary.dir, &.{ "build", "prog.selka", "-o", "x", "--debug-o0", "--debug-lean", zig }, null);
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, refused.term);
}

/// The execution keys of the test run of `target` (a file or a directory) under `options`, in a cache directory of its own,
/// with every root of a directory run started as a child process when `children` is set.
fn testKeys(a: std.mem.Allocator, dir: std.Io.Dir, target: []const u8, name: []const u8, options: []const []const u8, children: bool) ![]const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ "test", target, "--json", "--cache-dir", try std.fmt.allocPrint(a, "{s}-cache", .{name}), "--jobs", "2", zig });
    try argv.appendSlice(a, options);
    const tested = try compiler(a, dir, argv.items, if (children) .{ "SELKA_TEST_CHILDREN", "1" } else null);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, tested.term);
    const keys = try valuesOf(a, tested.stdout, "execution_key");
    try testing.expect(keys.len >= 65);
    return keys;
}

// spec-case: DEBUG-OPTIMIZE-1
test "selka test builds at -O0 unless asked for the lean build, and a directory run passes its mode to every child" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "t.selka", .data = testing_program });
    try temporary.dir.createDirPath(testing.io, "suite");
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "suite/one.selka", .data = "public func test_one() -> bool:\n    return 1 + 1 == 2\n" });
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "suite/two.selka", .data = "public func test_two() -> bool:\n    return 2 + 2 == 4\n" });
    const plain = try testKeys(a, temporary.dir, "t.selka", "plain", &.{}, false);
    const o0 = try testKeys(a, temporary.dir, "t.selka", "o0", &.{"--debug-o0"}, false);
    const lean = try testKeys(a, temporary.dir, "t.selka", "lean", &.{"--debug-lean"}, false);
    const o2 = try testKeys(a, temporary.dir, "t.selka", "o2", &.{"--optimize-debug"}, false);
    try testing.expectEqualStrings(plain, o0);
    try testing.expect(!std.mem.eql(u8, plain, lean));
    try testing.expect(!std.mem.eql(u8, plain, o2));
    try testing.expect(!std.mem.eql(u8, lean, o2));
    // Each root of a directory run, started as a child, builds in the run's mode (before the fix it built at -O0 under `--optimize-debug`).
    const dir_plain = try testKeys(a, temporary.dir, "suite", "dir-plain", &.{}, true);
    const dir_o2 = try testKeys(a, temporary.dir, "suite", "dir-o2", &.{"--optimize-debug"}, true);
    const dir_lean = try testKeys(a, temporary.dir, "suite", "dir-lean", &.{"--debug-lean"}, true);
    try testing.expectEqual(@as(usize, 2 * 65), dir_plain.len);
    try testing.expect(!std.mem.eql(u8, dir_plain, dir_o2));
    try testing.expect(!std.mem.eql(u8, dir_plain, dir_lean));
    try testing.expect(!std.mem.eql(u8, dir_o2, dir_lean));
    const alone_o2 = try testKeys(a, temporary.dir, "suite/one.selka", "alone-o2", &.{"--optimize-debug"}, false);
    try testing.expect(std.mem.indexOf(u8, dir_o2, alone_o2[0..64]) != null);
}

/// Build `prog.selka` in `dir` with `options`, run the binary and return its output and status.
fn buildAndRun(a: std.mem.Allocator, dir: std.Io.Dir, name: []const u8, options: []const []const u8) !Run {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ "build", "prog.selka", "-o", name, "--cache-dir", try std.fmt.allocPrint(a, "{s}-cache", .{name}), zig });
    try argv.appendSlice(a, options);
    const built = try compiler(a, dir, argv.items, null);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const binary = try std.fmt.allocPrint(a, "./{s}", .{name});
    const ran = try std.process.run(a, testing.io, .{ .argv = &.{binary}, .cwd = .{ .dir = dir } });
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .term = ran.term };
}

// spec-case: DEBUG-OPTIMIZE-1
test "a program prints the same under the lean build and the -O0 build, and a trap keeps its text and source line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "prog.selka", .data = program });
    const lean = try buildAndRun(a, temporary.dir, "lean", &.{});
    const o0 = try buildAndRun(a, temporary.dir, "o0", &.{"--debug-o0"});
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, lean.term);
    try testing.expectEqualStrings("20212.5\n7\n45\n", lean.stdout);
    try testing.expectEqualStrings(o0.stdout, lean.stdout);
    try temporary.dir.writeFile(testing.io, .{ .sub_path = "prog.selka", .data = trapping });
    const lean_trap = try buildAndRun(a, temporary.dir, "lean-trap", &.{});
    const o0_trap = try buildAndRun(a, temporary.dir, "o0-trap", &.{"--debug-o0"});
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, lean_trap.term);
    try testing.expectEqual(o0_trap.term, lean_trap.term);
    try testing.expect(std.mem.indexOf(u8, lean_trap.stderr, "prog.selka:2:12: error[R_LIST_BOUNDS]") != null);
    try testing.expect(std.mem.indexOf(u8, lean_trap.stderr, "in main at prog.selka:7:16") != null);
    try testing.expectEqualStrings(o0_trap.stderr, lean_trap.stderr);
}
