//! End-to-end tests: build the slice programs under `test/core` with the
//! `mylang-core` this build produced, run them, and compare stdout and exit
//! status with the old core's output (recorded below from `mylang build` of the
//! same files; `-Dcore-diff=true` also rebuilds them with the old compiler).
const std = @import("std");
const options = @import("core_test_options");
/// Failure detail goes to the test's stderr.
const report = std.debug.print;

const Outcome = struct { stdout: []const u8, stderr: []const u8, status: u8 };

const Build = struct {
    compiler: []const u8,
    release: bool,
    /// Build with the old `mylang` (always `--release`: its LLVM path needs no QBE binary).
    old: bool = false,
};

fn scratch(arena: std.mem.Allocator, dir: std.testing.TmpDir) ![]const u8 {
    return dir.dir.realPathFileAlloc(std.testing.io, ".", arena);
}

/// Build `test/core/NAME.my` into the scratch directory and return the executable's path.
fn buildFixture(arena: std.mem.Allocator, root: []const u8, name: []const u8, how: Build) ![]const u8 {
    const source = try std.fmt.allocPrint(arena, "{s}/{s}.my", .{ options.fixtures, name });
    const output = try std.fmt.allocPrint(arena, "{s}/{s}-{s}{s}", .{ root, name, if (how.release) "release" else "debug", if (how.old) "-old" else "" });
    const cache = try std.fmt.allocPrint(arena, "{s}/cache{s}", .{ root, if (how.old) "-old" else "" });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ how.compiler, "build", source, "-o", output, "--link", options.clock_path, "--cache-dir", cache });
    if (how.release or how.old) try argv.append(arena, "--release");
    const result = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    if (result.term != .exited or result.term.exited != 0) {
        report("build of {s} failed:\n{s}{s}\n", .{ name, result.stdout, result.stderr });
        // UNTESTED-ERROR: a fixture that fails to build fails the test that asked for it.
        return error.BuildFailed;
    }
    return output;
}

fn run(arena: std.mem.Allocator, executable: []const u8, args: []const []const u8) !Outcome {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(arena, executable);
    try argv.appendSlice(arena, args);
    const result = try std.process.run(arena, std.testing.io, .{ .argv = argv.items });
    const status: u8 = switch (result.term) {
        .exited => |code| code,
        else => 255,
    };
    return .{ .stdout = result.stdout, .stderr = result.stderr, .status = status };
}

/// The first whitespace-separated field: the checksum of a program that also prints a time.
fn firstField(text: []const u8) []const u8 {
    var fields = std.mem.tokenizeAny(u8, text, " \n");
    return fields.next() orelse "";
}

/// The integer_math checksums at three sizes, from one build.
fn sliceChecksums(arena: std.mem.Allocator, executable: []const u8) ![3][]const u8 {
    const sizes = [_][]const u8{ "4096", "64", "4100" };
    var sums: [3][]const u8 = undefined;
    for (sizes, &sums) |size, *sum| sum.* = firstField((try run(arena, executable, &.{ size, "300", "7" })).stdout);
    return sums;
}

/// The control program's output with no arguments and with `3 x`.
fn controlRuns(arena: std.mem.Allocator, executable: []const u8) ![2]Outcome {
    return .{ try run(arena, executable, &.{}), try run(arena, executable, &.{ "3", "x" }) };
}

const control_plain =
    \\215 111 547
    \\3001 -3999 -4001 2999
    \\-12 1000 5 9 4
    \\9223372036854775807 1 -9223372036854775808
    \\True False
    \\
;
const control_args =
    \\255 111 547
    \\3001 -3999 -4001 2999
    \\-12 1000 5 9 4
    \\9223372036854775807 1 -9223372036854775808
    \\False True
    \\
;

// spec: NEW-CORE-SLICE-1
test "mylang-core builds the integer_math slice at debug and release with the old core's checksums" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try scratch(arena.allocator(), dir);
    const debug = try sliceChecksums(arena.allocator(), try buildFixture(arena.allocator(), root, "int_math", .{ .compiler = options.core_path, .release = false }));
    const release_build = try buildFixture(arena.allocator(), root, "int_math", .{ .compiler = options.core_path, .release = true });
    const release = try sliceChecksums(arena.allocator(), release_build);
    try std.testing.expectEqualStrings("561601106", debug[0]);
    try std.testing.expectEqualStrings("8773872", debug[1]);
    try std.testing.expectEqualStrings("562398344", debug[2]);
    try std.testing.expectEqualStrings("561601106", release[0]);
    try std.testing.expectEqualStrings("8773872", release[1]);
    try std.testing.expectEqualStrings("562398344", release[2]);
    const refused = try run(arena.allocator(), release_build, &.{"1"});
    try std.testing.expectEqual(@as(u8, 2), refused.status);
}

// spec: NEW-CORE-SLICE-2
test "the control-flow program prints and exits like the old core at debug and release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try scratch(arena.allocator(), dir);
    const debug = try controlRuns(arena.allocator(), try buildFixture(arena.allocator(), root, "control", .{ .compiler = options.core_path, .release = false }));
    const release = try controlRuns(arena.allocator(), try buildFixture(arena.allocator(), root, "control", .{ .compiler = options.core_path, .release = true }));
    try std.testing.expectEqualStrings(control_plain, debug[0].stdout);
    try std.testing.expectEqual(@as(u8, 215), debug[0].status);
    try std.testing.expectEqualStrings(control_args, debug[1].stdout);
    try std.testing.expectEqual(@as(u8, 255), debug[1].status);
    try std.testing.expectEqualStrings(control_plain, release[0].stdout);
    try std.testing.expectEqual(@as(u8, 215), release[0].status);
    try std.testing.expectEqualStrings(control_args, release[1].stdout);
    try std.testing.expectEqual(@as(u8, 255), release[1].status);
}

// spec: NEW-CORE-TRAP-1
test "an overflow or bounds failure flushes stdout, reports like the old core and exits 1" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try scratch(arena.allocator(), dir);
    const overflow = try run(arena.allocator(), try buildFixture(arena.allocator(), root, "overflow", .{ .compiler = options.core_path, .release = false }), &.{});
    const bounds = try run(arena.allocator(), try buildFixture(arena.allocator(), root, "bounds", .{ .compiler = options.core_path, .release = true }), &.{});
    try std.testing.expectEqualStrings("1\n", overflow.stdout);
    try std.testing.expectEqual(@as(u8, 1), overflow.status);
    try std.testing.expect(std.mem.indexOf(u8, overflow.stderr, "overflow.my:2:14: error[R_OVERFLOW]: native execution failed (mul: left 9300000, right 1000000000000, width 64)\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, overflow.stderr, "MYLANG-TRAP {\"version\":1,\"operation\":\"mul\",\"left\":9300000,\"right\":1000000000000,\"width\":64}\n") != null);
    try std.testing.expectEqualStrings("0\n", bounds.stdout);
    try std.testing.expectEqual(@as(u8, 1), bounds.status);
    try std.testing.expect(std.mem.indexOf(u8, bounds.stderr, "bounds.my:4:15: error[R_LIST_BOUNDS]: native execution failed (index 5, length 3)\n") != null);
}

/// The old and new builds of one fixture, run the same way: equal stdout and status.
fn sameAsOld(arena: std.mem.Allocator, root: []const u8, name: []const u8, args: []const []const u8) !bool {
    if (!options.differential) return true;
    const new = try run(arena, try buildFixture(arena, root, name, .{ .compiler = options.core_path, .release = true }), args);
    const old = try run(arena, try buildFixture(arena, root, name, .{ .compiler = options.old_path, .release = true, .old = true }), args);
    const timed = !std.mem.eql(u8, name, "control") and !std.mem.eql(u8, name, "overflow") and !std.mem.eql(u8, name, "bounds");
    const same_out = if (timed) std.mem.eql(u8, firstField(new.stdout), firstField(old.stdout)) else std.mem.eql(u8, new.stdout, old.stdout);
    if (!same_out or new.status != old.status) report("{s} differs:\nnew ({d}):\n{s}\nold ({d}):\n{s}\n", .{ name, new.status, new.stdout, old.status, old.stdout });
    return same_out and new.status == old.status;
}

// spec-case: NEW-CORE-SLICE-1
test "with -Dcore-diff=true every fixture matches the old compiler's build of it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try scratch(arena.allocator(), dir);
    try std.testing.expect(try sameAsOld(arena.allocator(), root, "int_math", &.{ "4096", "300", "7" }));
    try std.testing.expect(try sameAsOld(arena.allocator(), root, "int_math", &.{ "64", "300", "7" }));
    try std.testing.expect(try sameAsOld(arena.allocator(), root, "int_math", &.{"1"}));
    try std.testing.expect(try sameAsOld(arena.allocator(), root, "control", &.{}));
    try std.testing.expect(try sameAsOld(arena.allocator(), root, "control", &.{ "3", "x" }));
    try std.testing.expect(try sameAsOld(arena.allocator(), root, "overflow", &.{}));
    try std.testing.expect(try sameAsOld(arena.allocator(), root, "bounds", &.{}));
    try std.testing.expect(try sameAsOld(arena.allocator(), root, "float_math", &.{ "4100", "30", "7" }));
    try std.testing.expect(try sameAsOld(arena.allocator(), root, "branch_mixed", &.{ "4100", "30", "7" }));
    try std.testing.expect(try sameAsOld(arena.allocator(), root, "binary_search", &.{ "100", "30", "7" }));
}

/// One kernel's checksums at 4096 and 64 elements (300 iterations, seed 7), from one build.
fn kernelChecksums(arena: std.mem.Allocator, root: []const u8, name: []const u8, release: bool) ![2][]const u8 {
    const executable = try buildFixture(arena, root, name, .{ .compiler = options.core_path, .release = release });
    const large = firstField((try run(arena, executable, &.{ "4096", "300", "7" })).stdout);
    const small = firstField((try run(arena, executable, &.{ "64", "300", "7" })).stdout);
    return .{ large, small };
}

/// Whether a kernel's debug and release builds both give the expected checksums.
fn kernelMatches(arena: std.mem.Allocator, root: []const u8, name: []const u8, expected: [2][]const u8) !bool {
    const debug = try kernelChecksums(arena, root, name, false);
    const release = try kernelChecksums(arena, root, name, true);
    const same = std.mem.eql(u8, debug[0], expected[0]) and std.mem.eql(u8, debug[1], expected[1]) and
        std.mem.eql(u8, release[0], expected[0]) and std.mem.eql(u8, release[1], expected[1]);
    if (!same) report("{s}: debug {s} {s}, release {s} {s}, expected {s} {s}\n", .{ name, debug[0], debug[1], release[0], release[1], expected[0], expected[1] });
    return same;
}

// spec: NEW-CORE-KERNELS-1
test "the S0 compute kernels give the old core's checksums at 4096 and 64 elements, debug and release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try scratch(arena.allocator(), dir);
    try std.testing.expect(try kernelMatches(arena.allocator(), root, "float_math", .{ "86580286", "119488164" }));
    try std.testing.expect(try kernelMatches(arena.allocator(), root, "call_direct", .{ "894136189", "27260364" }));
    try std.testing.expect(try kernelMatches(arena.allocator(), root, "branch_predictable", .{ "965504293", "28108500" }));
    try std.testing.expect(try kernelMatches(arena.allocator(), root, "branch_mixed", .{ "524637494", "35092986" }));
    try std.testing.expect(try kernelMatches(arena.allocator(), root, "binary_search", .{ "70251766", "197974" }));
}

/// The integer_math checksum line and trap code of a verify (or sabotaged) release build.
fn verified(arena: std.mem.Allocator, root: []const u8, flag: []const u8) !Outcome {
    const output = try std.fmt.allocPrint(arena, "{s}/int_math{s}", .{ root, flag });
    const source = try std.fmt.allocPrint(arena, "{s}/int_math.my", .{options.fixtures});
    const cache = try std.fmt.allocPrint(arena, "{s}/cache", .{root});
    const result = try std.process.run(arena, std.testing.io, .{ .argv = &.{ options.core_path, "build", source, "-o", output, "--release", flag, "--link", options.clock_path, "--cache-dir", cache } });
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
    return run(arena, output, &.{ "4096", "300", "7" });
}

// spec: NEW-CORE-VERIFY-1
test "a verify build checks every fact at run time, and catches a deliberately wrong interval rule" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try scratch(arena.allocator(), dir);
    const honest = try verified(arena.allocator(), root, "--verify-facts");
    try std.testing.expectEqualStrings("561601106", firstField(honest.stdout));
    try std.testing.expectEqual(@as(u8, 0), honest.status);
    const sabotaged = try verified(arena.allocator(), root, "--sabotage-facts");
    try std.testing.expectEqual(@as(u8, 1), sabotaged.status);
    try std.testing.expect(std.mem.indexOf(u8, sabotaged.stderr, "error[R_CORE_FACT]: native execution failed (range [0, 1007]: value 1008") != null);
}

/// compute_s0's checksum for one kind and size (300 iterations, seed 7).
fn kindChecksum(arena: std.mem.Allocator, executable: []const u8, kind: []const u8, size: []const u8) ![]const u8 {
    return firstField((try run(arena, executable, &.{ kind, size, "300", "7" })).stdout);
}

/// Every kind of compute_s0 at 4096 and 64 elements, in kind order.
fn computeChecksums(arena: std.mem.Allocator, executable: []const u8) ![12][]const u8 {
    const kinds = [_][]const u8{ "0", "1", "2", "3", "6", "10" };
    var sums: [12][]const u8 = undefined;
    for (kinds, 0..) |kind, i| {
        sums[i] = try kindChecksum(arena, executable, kind, "4096");
        sums[6 + i] = try kindChecksum(arena, executable, kind, "64");
    }
    return sums;
}

const compute_expected = [12][]const u8{ "561601106", "86580286", "965504293", "524637494", "894136189", "70251766", "8773872", "119488164", "28108500", "35092986", "27260364", "197974" };

// spec: NEW-CORE-UNSWITCH-1
test "the multi-kind compute program, dispatching on an invariant kind per element, matches the old core at debug and release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try scratch(arena.allocator(), dir);
    const debug = try computeChecksums(arena.allocator(), try buildFixture(arena.allocator(), root, "compute_s0", .{ .compiler = options.core_path, .release = false }));
    const release = try computeChecksums(arena.allocator(), try buildFixture(arena.allocator(), root, "compute_s0", .{ .compiler = options.core_path, .release = true }));
    try std.testing.expect(sameSums(debug));
    try std.testing.expect(sameSums(release));
}

/// Whether every checksum equals the old core's.
fn sameSums(got: [12][]const u8) bool {
    for (compute_expected, got) |expected, sum| {
        if (!std.mem.eql(u8, expected, sum)) {
            report("compute_s0 checksum {s}, expected {s}\n", .{ sum, expected });
            return false;
        }
    }
    return true;
}
