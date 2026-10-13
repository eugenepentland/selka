//! Internal indirect calls return the same owned aggregates as direct calls.
const std = @import("std");
const options = @import("core_test_options");
const zero = @import("zero_rc.zig");
const fixture = @embedFile("a02_indirect_owned_fixture.my");

// spec-case: CALLBACK-1
test "zero RC A02 indirect calls transfer owned result and mutable writeback" {
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
        try argv.appendSlice(a, &.{ options.corePath(), "build", source, "--experimental-zero-rc", "--counters", "--cache-dir", root, "--emit-llvm", llvm, "-o", binary });
        try argv.appendSlice(a, mode);
        const built = try std.process.run(a, io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) std.debug.print("A02 indirect calls build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("MYLANG_COUNTERS", counts);
        try environment.put("MYL_CORE_LEAKCHECK", "1");
        for ([_][]const []const u8{ &.{binary}, &.{ binary, "alternate" } }) |command| {
            const ran = try std.process.run(a, io, .{ .argv = command, .environ_map = &environment });
            if (ran.term != .exited or ran.term.exited != 0) std.debug.print("A02 indirect calls run: {s}{s}\n", .{ ran.stdout, ran.stderr });
            try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
            try std.testing.expectEqualStrings("indirect owners preserved\n", ran.stdout);
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
        }
    }
}

// spec-case: CALLBACK-1
test "zero RC A02 indirect calls retain borrowed-return refusals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "borrowed.my" });
    const cases = [_][]const u8{
        \\func borrowed(values: str[]) -> str[]:
        \\    return values
        \\func apply(callback: func(str[]) -> str[], values: str[]) -> str[]:
        \\    return callback(values)
        \\func main() -> int:
        \\    const values = ["source"]
        \\    const result = apply(borrowed, values)
        \\    return len(result)
        ,
        \\record Product:
        \\    values: str[]
        \\func borrowed(values: str[]) -> Product:
        \\    return Product(values=values)
        \\func apply(callback: func(str[]) -> Product, values: str[]) -> Product:
        \\    return callback(values)
        \\func main() -> int:
        \\    const values = ["source"]
        \\    const result = apply(borrowed, values)
        \\    return len(result.values)
        ,
    };
    for (cases) |source| {
        try dir.dir.writeFile(io, .{ .sub_path = "borrowed.my", .data = source });
        const checked = try std.process.run(a, io, .{ .argv = &.{ options.corePath(), "check", path, "--experimental-zero-rc" } });
        try std.testing.expect(checked.term == .exited and checked.term.exited == 1);
        try std.testing.expect(std.mem.indexOf(u8, checked.stderr, "E_SINGLE_OWNER_BORROW") != null);
    }
}
