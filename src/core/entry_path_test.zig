//! A single-file program's bytes do not depend on the directory its tree sits in
//! (ENTRY-PATH-1): the same source built from two roots by the same relative
//! spelling emits identical LLVM and links an identical program, and its tests
//! report identical execution keys.
const std = @import("std");
const options = @import("core_test_options");

/// Failure detail goes to the test's stderr.
const report = std.debug.print;

const program =
    \\func ratio(x: int) -> int:
    \\    return 100 // x
    \\
    \\
    \\public func test_ratio() -> bool:
    \\    return ratio(4) == 25
    \\
    \\
    \\func main() -> int:
    \\    return ratio(5)
    \\
;

/// What one root's build of `prog.my` produced.
const Built = struct { llvm: []const u8, program: []const u8 };

/// A fresh temporary root holding `prog.my`, by absolute path.
fn root(a: std.mem.Allocator, dir: *std.testing.TmpDir) ![]const u8 {
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "prog.my", .data = program });
    return dir.dir.realPathFileAlloc(std.testing.io, ".", a);
}

fn compiler(a: std.mem.Allocator) ![]const u8 {
    return std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, options.corePath(), a);
}

/// Build `prog.my` from `at` by its own name, with `flags`, and read back the
/// emitted LLVM and the linked program.
fn buildIn(a: std.mem.Allocator, at: []const u8, flags: []const []const u8) !Built {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ try compiler(a), "build", "prog.my", "-o", "prog", "--emit-llvm", "prog.ll", "--cache-dir", "cache" });
    try argv.appendSlice(a, flags);
    var environment = try options.privateEnvironment(a);
    const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .cwd = .{ .path = at }, .environ_map = &environment });
    if (built.term != .exited or built.term.exited != 0) report("{s}{s}", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const llvm = try std.fs.path.join(a, &.{ at, "prog.ll" });
    const linked = try std.fs.path.join(a, &.{ at, "prog" });
    return .{
        .llvm = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, llvm, a, .limited(64 << 20)),
        .program = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, linked, a, .limited(256 << 20)),
    };
}

/// Both roots' builds in one mode agree byte for byte and name neither root.
fn expectRootFree(a: std.mem.Allocator, left: []const u8, right: []const u8, flags: []const []const u8) !void {
    const one = try buildIn(a, left, flags);
    const two = try buildIn(a, right, flags);
    try std.testing.expect(std.mem.indexOf(u8, one.llvm, "source_filename = \"prog.my\"") != null);
    try std.testing.expectEqualStrings(one.llvm, two.llvm);
    try std.testing.expect(std.mem.eql(u8, one.program, two.program));
    for ([_][]const u8{ one.llvm, one.program }) |bytes| try std.testing.expect(std.mem.indexOf(u8, bytes, left) == null);
    for ([_][]const u8{ two.llvm, two.program }) |bytes| try std.testing.expect(std.mem.indexOf(u8, bytes, right) == null);
}

/// The `cache` record of a fresh `mylang test prog.my --json` run from `at`.
/// The shared stores are disabled, so the verdict is executed here rather than
/// served as a shared receipt hit, which carries no execution key.
fn testCache(a: std.mem.Allocator, at: []const u8) !std.json.ObjectMap {
    const argv = &.{ try compiler(a), "test", "prog.my", "--json", "--cache-dir", "test-cache" };
    var environment = try options.privateEnvironment(a);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = argv, .cwd = .{ .path = at }, .environ_map = &environment });
    if (ran.term != .exited or ran.term.exited != 0) report("{s}{s}", .{ ran.stdout, ran.stderr });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, ran.stdout, .{});
    const tests = parsed.object.get("tests").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), tests.len);
    return tests[0].object.get("cache").?.object;
}

// spec: ENTRY-PATH-1
test "a single-file program built from two roots emits identical LLVM and program bytes naming neither root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var left_dir = std.testing.tmpDir(.{});
    defer left_dir.cleanup();
    var right_dir = std.testing.tmpDir(.{});
    defer right_dir.cleanup();
    const left = try root(a, &left_dir);
    const right = try root(a, &right_dir);
    try std.testing.expect(!std.mem.eql(u8, left, right));
    try expectRootFree(a, left, right, &.{});
    try expectRootFree(a, left, right, &.{"--release"});
}

// spec-case: ENTRY-PATH-1
test "a single-file test entry tested from two roots reports one execution key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var left_dir = std.testing.tmpDir(.{});
    defer left_dir.cleanup();
    var right_dir = std.testing.tmpDir(.{});
    defer right_dir.cleanup();
    const left_cache = try testCache(a, try root(a, &left_dir));
    const right_cache = try testCache(a, try root(a, &right_dir));
    // Both verdicts were executed, not served from a store the gate may share.
    try std.testing.expectEqualStrings("execute", left_cache.get("action").?.string);
    try std.testing.expectEqualStrings("execute", right_cache.get("action").?.string);
    const left = left_cache.get("execution_key").?.string;
    const right = right_cache.get("execution_key").?.string;
    try std.testing.expectEqual(@as(usize, 64), left.len);
    try std.testing.expectEqualStrings(left, right);
}
