//! List mutation, receiver snapshots and checked failures at every core mode.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const options = @import("core_test_options");
const support = @import("test_support.zig");
const report = std.debug.print;
const methods_fixture = "m_list_methods.selka";

fn qualified(a: std.mem.Allocator) !void {
    const original_path = try std.fs.path.join(a, &.{ options.fixtures, methods_fixture });
    const original = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, original_path, a, .limited(1 << 20));
    // Keep the deliberate trap's original index instead of shifting it by len(values).
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, original, "lists.pop_at(mut values, len(values) - 99)"));
    const runtime_source = try std.mem.replaceOwned(u8, a, original, "lists.pop_at(mut values, len(values) - 99)", "lists.pop_at(mut values, len(values) - 101)");
    var directory = stable_dir.tmpDir(a, @src());
    defer directory.cleanup();
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = methods_fixture, .data = runtime_source });
    const source = try directory.dir.realPathFileAlloc(std.testing.io, methods_fixture, a);
    var environment = try options.privateEnvironment(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    for ([_][]const []const u8{ &.{"--release"}, &.{ "--release", "--verify-facts" } }) |mode| {
        try support.requireReleaseArgs(mode);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "test", "--force", source, "--json", "--cache-dir", try options.suiteCache(a, @src()) });
        try argv.appendSlice(a, mode);
        const result = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
        if (result.term != .exited or result.term.exited != 1 or result.stderr.len != 0)
            report("S3 list methods fixture: {s}{s}\n", .{ result.stdout, result.stderr });
        try std.testing.expect(result.term == .exited and result.term.exited == 1);
        try std.testing.expectEqualStrings("", result.stderr);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, result.stdout, .{});
        try std.testing.expectEqual(@as(i64, 4), parsed.value.object.get("passed").?.integer);
        try std.testing.expectEqual(@as(i64, 4), parsed.value.object.get("failed").?.integer);
        try std.testing.expectEqual(@as(i64, 0), parsed.value.object.get("unsupported").?.integer);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "R_LIST_VALUE") != null);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "R_LIST_BOUNDS") != null);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "R_SLICE_STEP") != null);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "R_LIST_BOUNDS (index -99, length 2)") != null);
    }
}

// spec: NEW-CORE-LIST-S3-2
test "list search splice and stepped slices preserve snapshots owned children and exact failures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try qualified(arena.allocator());
}

// spec-case: OWNED-LIST-MUTATION-1
// spec-case: LIST-SORT-KEY-1
test "zero RC keyed sorting gathers wide managed records with stable independent children" {
    const zero = @import("zero_rc.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "sort.selka", .data = @embedFile("gap_sort_fixture.selka") });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "sort.selka" });
    const binary = try std.fs.path.join(a, &.{ root, "sort" });
    const llvm = try std.fs.path.join(a, &.{ root, "sort.ll" });
    const counts = try std.fs.path.join(a, &.{ root, "counts.json" });
    for ([_][]const []const u8{ &.{"--optimize-debug"}, &.{"--release"}, &.{ "--release", "--verify-facts" }, &.{ "--release", "--no-facts" } }) |mode| {
        try support.requireReleaseArgs(mode);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", source, "--counters", "--cache-dir", try options.suiteCache(a, @src()), "--emit-llvm", llvm, "-o", binary });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("owned keyed sort build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        try std.testing.expect(std.mem.indexOf(u8, emitted, "@myl_core_owned_sort_keyed") != null);
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("SELKA_COUNTERS", counts);
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) report("owned keyed sort run: {s}{s}\n", .{ ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("owned keyed sorting preserved children and stability\n", ran.stdout);
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
    }
}

// spec-case: OWNED-LIST-MUTATION-1
// spec-case: LIST-SORT-KEY-1
test "zero RC keyed sorting optional scratch failure preserves managed cycle fallback" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-local" }));
    const binary = try @import("native_fixture.zig").buildProgram(a, root, .{ .source = @embedFile("gap_sort_failure_fixture.c") });
    const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
    try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
    try std.testing.expectEqualStrings("", ran.stderr);
    try std.testing.expectEqualStrings("scratch success and failure preserve stable managed ownership\n", ran.stdout);
}

// spec-case: NEW-CORE-LIST-S3-2
test "the original literal negative pop fixture reports its removal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // migrate-embedded: skip intentional literal negative index removal fixture
    const original =
        \\public func test_indexed_pop_reports_original_negative_index() -> bool:
        \\    mut values = [1, 2]
        \\    return values.pop(-99) == 0
        \\
        \\func main() -> int:
        \\    return 0
    ;
    // The retirement answers first: the method is gone, and its repair is the home
    // spelling plus the import. On that spelling the literal's own refusal answers,
    // so the fixture still witnesses the negative-index removal it was written for.
    const checked = try @import("test_support.zig").checkSource(a, original);
    try std.testing.expect(!checked.passed);
    try std.testing.expectEqualStrings("E_METHOD_REMOVED", checked.diagnostics[0].code);
    const migrated = try std.mem.replaceOwned(u8, a, original, "values.pop(-99)", "lists.pop_at(mut values, -99)");
    const home = try std.mem.concat(a, u8, &.{ "import lists\n", migrated });
    const repaired = try @import("test_support.zig").checkSource(a, home);
    try std.testing.expect(!repaired.passed);
    try std.testing.expectEqualStrings("E_NEGATIVE_INDEX_REMOVED", repaired.diagnostics[0].code);
}
