//! Scalar mut writebacks rebase against the current parent after each sibling update.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const options = @import("core_test_options");
const zero = @import("zero_rc.zig");
const support = @import("test_support.zig");
const fixture = @embedFile("a05_scalar_mut_fixture.selka");

// spec-case: NEW-CORE-ZERO-RC-OWNED-MUT-CALL-1
test "zero RC A05 scalar mut calls preserve sibling writes and argument order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "methods.selka", .data = fixture });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "methods.selka" });
    const binary = try std.fs.path.join(a, &.{ root, "methods" });
    const llvm = try std.fs.path.join(a, &.{ root, "methods.ll" });
    const counts = try std.fs.path.join(a, &.{ root, "counts.json" });
    const modes = [_][]const []const u8{ &.{"--optimize-debug"}, &.{"--release"}, &.{ "--release", "--verify-facts" }, &.{ "--release", "--no-facts" } };
    for (modes) |mode| {
        try support.requireReleaseArgs(mode);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", source, "--counters", "--cache-dir", try options.suiteCache(a, @src()), "--emit-llvm", llvm, "-o", binary });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) std.debug.print("A05 scalar mut calls build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("SELKA_COUNTERS", counts);
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) std.debug.print("A05 scalar mut calls run: {s}{s}\n", .{ ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("scalar writebacks preserved\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        const text = try std.Io.Dir.cwd().readFileAlloc(io, counts, a, .limited(16 << 20));
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
        const totals = parsed.object.get("totals").?.object;
        try std.testing.expectEqual(@as(i64, 0), totals.get("live_bytes_at_exit").?.integer);
        for ([_][]const u8{ "retain", "release", "release_unique", "unique_test", "uniqueness" }) |kind| {
            for (parsed.object.get("sites").?.array.items) |site| {
                try std.testing.expect(!std.mem.eql(u8, site.object.get("kind").?.string, kind));
            }
        }
        for ([_][]const u8{ "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "share_marks" }) |kind|
            try std.testing.expect(totals.get(kind) == null);
        for ([_][]const u8{ "overlap", "bounds" }) |scenario| {
            const failed = try std.process.run(a, io, .{ .argv = &.{ binary, scenario }, .environ_map = &environment });
            if (failed.term != .exited or failed.term.exited != 1) std.debug.print("A05 scalar mut trap {s}: {any} {s}{s}\n", .{ scenario, failed.term, failed.stdout, failed.stderr });
            try std.testing.expect(failed.term == .exited and failed.term.exited == 1);
            try std.testing.expectEqualStrings("", failed.stdout);
            try std.testing.expect(std.mem.indexOf(u8, failed.stderr, if (std.mem.eql(u8, scenario, "bounds")) "R_LIST_BOUNDS" else "overlapping mut arguments") != null);
        }
    }
}

// spec-case: NEW-CORE-ZERO-RC-OWNED-MUT-CALL-1
test "zero RC A05 scalar mut calls retain managed root loan refusals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    const source =
        \\func pair(mut left: int[], mut right: int[]):
        \\    append(mut left, 1)
        \\    append(mut right, 2)
        \\func main() -> int:
        \\    mut rows = [[3], [4]]
        \\    const index = 0
        \\    pair(mut rows[index], mut rows[1])
        \\    return len(rows)
    ;
    try dir.dir.writeFile(io, .{ .sub_path = "overlap.selka", .data = source });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "overlap.selka" });
    const checked = try std.process.run(a, io, .{ .argv = &.{ options.corePath(), "check", path } });
    try std.testing.expect(checked.term == .exited and checked.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, checked.stderr, "E_SINGLE_OWNER_OVERLAP") != null);
}

// spec-case: NEW-CORE-MUT-1
test "zero RC A05 scalar mut calls keep borrowed inputs read-only" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    const source =
        \\func change(mut value: int) -> Unit:
        \\    value += 1
        \\func borrowed(values: int[]) -> int:
        \\    change(mut values[0])
        \\    return values[0]
        \\func main() -> int:
        \\    const values = [1]
        \\    return borrowed(values)
    ;
    try dir.dir.writeFile(io, .{ .sub_path = "borrowed.selka", .data = source });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "borrowed.selka" });
    const checked = try std.process.run(a, io, .{ .argv = &.{ options.corePath(), "check", path } });
    try std.testing.expect(checked.term == .exited and checked.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, checked.stderr, "E_IMMUTABLE") != null);
}
