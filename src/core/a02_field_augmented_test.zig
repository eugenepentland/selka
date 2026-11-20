//! Field list augmentation uses one exact collection receiver writeback.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const options = @import("core_test_options");
const zero = @import("zero_rc.zig");
const support = @import("test_support.zig");
const fixture = @embedFile("a02_field_augmented_fixture.selka");

// spec-case: AUGMENTED-FIELD-1
test "zero RC A02 field augmentation preserves receiver ownership after out-of-order inlining" {
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
    // Preserve the historical negative source and execute the explicit modern index.
    const rejected = try std.process.run(a, io, .{ .argv = &.{ options.corePath(), "check", source } });
    try std.testing.expect(rejected.term == .exited and rejected.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, rejected.stderr, "E_NEGATIVE_INDEX_REMOVED") != null);
    const selected = try std.mem.replaceOwned(u8, a, fixture, "return -1", "return 0");
    const modern = try std.mem.replaceOwned(u8, a, selected, "            parent.rows[-2].items += values(mut events, out)", "            const invalid_index = -2\n            parent.rows[invalid_index].items += values(mut events, out)");
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
        if (built.term != .exited or built.term.exited != 0) std.debug.print("A02 field augmentation build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("SELKA_COUNTERS", counts);
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) std.debug.print("A02 field augmentation run: {s}{s}\n", .{ ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("rhs\nfield augmented preserved\n", ran.stdout);
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

// spec-case: AUGMENTED-FIELD-1
test "zero RC A02 field augmentation retains overlap and borrowed-return refusals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "negative.selka" });
    const cases = [_]struct { source: []const u8, diagnostic: []const u8 }{
        .{
            .source =
            // migrate-embedded: skip intentional overlapping receiver / borrowed-return rejection
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
            \\    print(out, owner.items, owner.marker)
            \\    return 0
            ,
            .diagnostic = "E_SINGLE_OWNER_OVERLAP",
        },
        .{
            .source =
            // migrate-embedded: skip intentional overlapping receiver / borrowed-return rejection
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
            \\    print(out, owner.items, owner.marker)
            \\    return 0
            ,
            .diagnostic = "E_SINGLE_OWNER_OVERLAP",
        },
        .{
            .source =
            // migrate-embedded: skip intentional overlapping receiver / borrowed-return rejection
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
            \\    print(out, owner.items, owner.marker)
            \\    return 0
            ,
            .diagnostic = "E_SINGLE_OWNER_OVERLAP",
        },
    };
    for (cases) |case| {
        try dir.dir.writeFile(io, .{ .sub_path = "negative.selka", .data = case.source });
        const checked = try std.process.run(a, io, .{ .argv = &.{ options.corePath(), "check", path } });
        if (checked.term != .exited or checked.term.exited != 1) std.debug.print("A02 unexpected negative admission: {s}{s}\n", .{ checked.stdout, checked.stderr });
        try std.testing.expect(checked.term == .exited and checked.term.exited == 1);
        try std.testing.expect(std.mem.indexOf(u8, checked.stderr, case.diagnostic) != null);
    }
}
