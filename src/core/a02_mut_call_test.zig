//! Checked mutable calls transfer and reattach exactly one interior child owner.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const options = @import("core_test_options");
const zero = @import("zero_rc.zig");
const support = @import("test_support.zig");
const fixture = @embedFile("a02_mut_call_fixture.selka");

// spec: NEW-CORE-ZERO-RC-OWNED-MUT-CALL-1
test "zero RC A02 interior mut calls preserve child ownership and selected places" {
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
    // Check the untouched legacy fixture, then run its explicit modern counterpart.
    const rejected = try std.process.run(a, io, .{ .argv = &.{ options.corePath(), "check", source } });
    try std.testing.expect(rejected.term == .exited and rejected.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, rejected.stderr, "E_NEGATIVE_INDEX_REMOVED") != null);
    const selected = try std.mem.replaceOwned(u8, a, fixture, "return -2", "return 0");
    const modern = try std.mem.replaceOwned(u8, a, selected, "            effect(mut bundle.mapping[0][-3], out)", "            const invalid_index = -3\n            effect(mut bundle.mapping[0][invalid_index], out)");
    try std.testing.expect(!std.mem.eql(u8, fixture, modern));
    try dir.dir.writeFile(io, .{ .sub_path = "methods.selka", .data = modern });
    // The historical fixture keeps its retired spellings; the compiler's own fix
    // publishes the modern spelling of the same program.
    const repaired = try std.process.run(a, io, .{ .argv = &.{ options.corePath(), "fix", source } });
    try std.testing.expect(repaired.term == .exited and repaired.term.exited == 0);
    const modes = [_][]const []const u8{ &.{"--optimize-debug"}, &.{"--release"}, &.{ "--release", "--verify-facts" }, &.{ "--release", "--no-facts" } };
    for (modes) |mode| {
        try support.requireReleaseArgs(mode);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", source, "--counters", "--cache-dir", try options.suiteCache(a, @src()), "--emit-llvm", llvm, "-o", binary });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) std.debug.print("A02 interior mut calls build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("SELKA_COUNTERS", counts);
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) std.debug.print("A02 interior mut calls run: {s}{s}\n", .{ ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("41 1 8 19\n", ran.stdout);
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
        for ([_][]const u8{ "missing", "bounds" }) |scenario| {
            const failed = try std.process.run(a, io, .{ .argv = &.{ binary, scenario }, .environ_map = &environment });
            try std.testing.expect(failed.term == .exited and failed.term.exited == 1);
            try std.testing.expectEqualStrings("", failed.stdout);
            try std.testing.expect(std.mem.indexOf(u8, failed.stderr, if (std.mem.eql(u8, scenario, "bounds")) "R_LIST_BOUNDS" else "R_MISSING_KEY") != null);
        }
    }
}

// spec-case: NEW-CORE-ZERO-RC-OWNED-MUT-CALL-1
test "zero RC A02 interior mut calls reject overlapping parent roots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    const source =
        // migrate-embedded: skip intentional overlapping parent roots
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
