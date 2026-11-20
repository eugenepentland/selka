//! Exchange transfers exactly one owner without allocating a replacement list.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const options = @import("core_test_options");
const zero = @import("zero_rc.zig");
const support = @import("test_support.zig");

// spec: OWNED-LIST-EXCHANGE-1
test "list exchange transfers nested wide recursive values in every ownership build mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = stable_dir.tmpDir(std.testing.allocator, @src());
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "exchange.selka", .data = @embedFile("list_exchange_fixture.selka") });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "exchange.selka" });
    const binary = try std.fs.path.join(a, &.{ root, "exchange" });
    const llvm = try std.fs.path.join(a, &.{ root, "exchange.ll" });
    const counts = try std.fs.path.join(a, &.{ root, "counts.json" });
    // Preserve the original fixture's removal checks and negative runtime scenarios.
    const rejected = try std.process.run(a, io, .{ .argv = &.{ options.corePath(), "check", source } });
    try std.testing.expect(rejected.term == .exited and rejected.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, rejected.stderr, "E_NEGATIVE_INDEX_REMOVED") != null);
    const old = @embedFile("list_exchange_fixture.selka");
    const selected = try std.mem.replaceOwned(u8, a, old, "return -1", "return 1");
    const narrow = try std.mem.replaceOwned(u8, a, selected, "const from_end: i8 = -1", "const from_end: i8 = i8(len(narrow) - 1)");
    const generic = try std.mem.replaceOwned(u8, a, narrow, "    const selected = generic(mut numbers, -1, 19)", "    const last_number = len(numbers) - 1\n    const selected = generic(mut numbers, last_number, 19)");
    const units = try std.mem.replaceOwned(u8, a, generic, "units.exchange(-1, ())", "units.exchange(len(units) - 1, ())");
    const modern = try std.mem.replaceOwned(u8, a, units, "            _ = numbers.exchange(-3, 9)", "            const invalid_index = -3\n            _ = numbers.exchange(invalid_index, 9)");
    try std.testing.expect(!std.mem.eql(u8, old, modern));
    try dir.dir.writeFile(io, .{ .sub_path = "exchange.selka", .data = modern });
    // The historical fixture keeps its retired spellings; the compiler's own fix
    // publishes the modern spelling of the same program.
    const repaired = try std.process.run(a, io, .{ .argv = &.{ options.corePath(), "fix", source } });
    try std.testing.expect(repaired.term == .exited and repaired.term.exited == 0);
    for ([_][]const []const u8{ &.{"--optimize-debug"}, &.{"--release"}, &.{ "--release", "--verify-facts" }, &.{ "--release", "--no-facts" } }) |mode| {
        try support.requireReleaseArgs(mode);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.corePath(), "build", source, "--counters", "--cache-dir", try options.suiteCache(a, @src()), "--emit-llvm", llvm, "-o", binary });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) std.debug.print("exchange build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("SELKA_COUNTERS", counts);
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) std.debug.print("exchange run: {s}{s}\n", .{ ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("exchange passed\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        const text = try std.Io.Dir.cwd().readFileAlloc(io, counts, a, .limited(16 << 20));
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
        const totals = parsed.object.get("totals").?.object;
        try std.testing.expectEqual(@as(i64, 0), totals.get("live_bytes_at_exit").?.integer);
        for ([_][]const u8{ "negative", "positive", "empty", "unsigned-max" }) |scenario| {
            // Fatal counted runs use the default counter filename. Keep their
            // output inside this test's temporary directory as well.
            const failed = try std.process.run(a, io, .{ .argv = &.{ binary, scenario }, .cwd = .{ .path = root } });
            try std.testing.expect(failed.term == .exited and failed.term.exited == 1);
            try std.testing.expect(std.mem.indexOf(u8, failed.stderr, "error[R_LIST_BOUNDS]") != null);
        }
    }
}
