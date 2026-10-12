//! Field list augmentation uses one exact collection receiver writeback.
const std = @import("std");
const options = @import("core_test_options");
const zero = @import("zero_rc.zig");
const fixture = @embedFile("a02_field_augmented_fixture.my");

// spec-case: AUGMENTED-FIELD-1
test "zero RC A02 field augmentation preserves exact receiver ownership" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "methods.my", .data = fixture });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "methods.my" });
    const binary = try std.fs.path.join(a, &.{ root, "methods" });
    const llvm = try std.fs.path.join(a, &.{ root, "methods.ll" });
    const counts = try std.fs.path.join(a, &.{ root, "counts.json" });
    const modes = [_][]const []const u8{ &.{"--release"}, &.{"--unoptimized"}, &.{ "--release", "--verify-facts" }, &.{"--optimize-debug"}, &.{ "--release", "--no-facts" } };
    for (modes) |mode| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.core_path, "build", source, "--experimental-zero-rc", "--counters", "--cache-dir", root, "--emit-llvm", llvm, "-o", binary });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) std.debug.print("A02 field augmentation build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("MYLANG_COUNTERS", counts);
        try environment.put("MYL_CORE_LEAKCHECK", "1");
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) std.debug.print("A02 field augmentation run: {s}{s}\n", .{ ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("rhs\nfield augmented preserved\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        const text = try std.Io.Dir.cwd().readFileAlloc(io, counts, a, .limited(16 << 20));
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
        const totals = parsed.object.get("totals").?.object;
        try std.testing.expectEqual(@as(i64, 0), totals.get("live_bytes_at_exit").?.integer);
        for ([_][]const u8{ "retain", "release", "unique_test", "uniqueness" }) |kind| {
            for (parsed.object.get("sites").?.array.items) |site| {
                if (std.mem.eql(u8, site.object.get("kind").?.string, kind)) try std.testing.expectEqual(@as(i64, 0), site.object.get("count").?.integer);
            }
        }
        for ([_][]const u8{ "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "share_marks" }) |kind|
            try std.testing.expectEqual(@as(i64, 0), totals.get(kind).?.integer);
        for ([_][]const u8{ "missing", "bounds" }) |scenario| {
            const failed = try std.process.run(a, io, .{ .argv = &.{ binary, scenario }, .environ_map = &environment });
            try std.testing.expect(failed.term == .exited and failed.term.exited == 1);
            try std.testing.expectEqualStrings("", failed.stdout);
            try std.testing.expect(std.mem.indexOf(u8, failed.stderr, if (std.mem.eql(u8, scenario, "bounds")) "R_LIST_BOUNDS" else "R_MISSING_KEY") != null);
        }
    }
}

// spec-case: AUGMENTED-FIELD-1
test "zero RC A02 field augmentation retains overlap and borrowed-return refusals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "negative.my" });
    const cases = [_]struct { source: []const u8, diagnostic: []const u8 }{
        .{ .source =
        \\record Controlled:
        \\    items: int[]
        \\    marker: int
        \\
        \\func changed(mut owner: Controlled) -> int[]:
        \\    owner = Controlled(items=[50], marker=7)
        \\    return [2]
        \\func main(out: Stream) -> int:
        \\    mut owner = Controlled(items=[1], marker=0)
        \\    owner.items += changed(mut owner)
        \\    out.print(owner.items, owner.marker)
        \\    return 0
        , .diagnostic = "OVERLAP" },
        .{ .source =
        \\record Controlled:
        \\    items: int[]
        \\    marker: int
        \\
        \\func changed(mut owner: Controlled) -> int[]:
        \\    owner.items = [50]
        \\    owner.marker = 7
        \\    return [2]
        \\func main(out: Stream) -> int:
        \\    mut owner = Controlled(items=[1], marker=0)
        \\    owner.items += changed(mut owner)
        \\    out.print(owner.items, owner.marker)
        \\    return 0
        , .diagnostic = "OVERLAP" },
        .{ .source =
        \\record Controlled:
        \\    items: int[]
        \\    marker: int
        \\
        \\func changed(mut owner: Controlled) -> int[]:
        \\    owner.marker = 7
        \\    return [2]
        \\func main(out: Stream) -> int:
        \\    mut owner = Controlled(items=[1], marker=0)
        \\    owner.items += changed(mut owner)
        \\    out.print(owner.items, owner.marker)
        \\    return 0
        , .diagnostic = "OVERLAP" },
        .{ .source =
        \\record Controlled:
        \\    items: int[]
        \\func bad(owner: Controlled) -> int[]:
        \\    return owner.items
        \\func main() -> int:
        \\    mut owner = Controlled(items=[1])
        \\    return len(bad(owner))
        , .diagnostic = "E_SINGLE_OWNER_BORROW" },
    };
    for (cases) |case| {
        try dir.dir.writeFile(io, .{ .sub_path = "negative.my", .data = case.source });
        const checked = try std.process.run(a, io, .{ .argv = &.{ options.core_path, "check", path, "--experimental-zero-rc" } });
        if (checked.term != .exited or checked.term.exited != 1) std.debug.print("A02 unexpected negative admission: {s}{s}\n", .{ checked.stdout, checked.stderr });
        try std.testing.expect(checked.term == .exited and checked.term.exited == 1);
        try std.testing.expect(std.mem.indexOf(u8, checked.stderr, case.diagnostic) != null);
    }
}
