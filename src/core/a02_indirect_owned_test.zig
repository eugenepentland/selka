//! Internal indirect calls return the same owned aggregates as direct calls.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const options = @import("core_test_options");
const zero = @import("zero_rc.zig");
const support = @import("test_support.zig");
const fixture = @embedFile("a02_indirect_owned_fixture.selka");

// spec-case: CALLBACK-1
test "zero RC A02 indirect calls transfer owned result and mutable writeback" {
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
        if (built.term != .exited or built.term.exited != 0) std.debug.print("A02 indirect calls build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const emitted = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(emitted));
        var environment = try std.testing.environ.createMap(a);
        defer environment.deinit();
        try environment.put("SELKA_COUNTERS", counts);
        try environment.put("SELKA_CORE_LEAKCHECK", "1");
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
            for ([_][]const u8{ "retain", "release", "release_unique", "unique_test", "uniqueness" }) |kind| {
                for (parsed.object.get("sites").?.array.items) |site| {
                    try std.testing.expect(!std.mem.eql(u8, site.object.get("kind").?.string, kind));
                }
            }
            for ([_][]const u8{ "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "share_marks" }) |kind|
                try std.testing.expect(totals.get(kind) == null);
        }
    }
}

/// Require exact ownership codes and rule ids from the source checking command.
fn refusalCases(backing: std.mem.Allocator, cases: []const []const u8, expected: @import("selka").ownership_rules.Refusal) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var dir = stable_dir.tmpDir(backing, @src());
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "borrowed.selka" });
    const rule = try std.fmt.allocPrint(a, "\"rule\":\"{s}\"", .{@tagName(expected.rule)});
    for (cases) |source| {
        try dir.dir.writeFile(io, .{ .sub_path = "borrowed.selka", .data = source });
        const checked = try std.process.run(a, io, .{ .argv = &.{ options.corePath(), "check", path, "--no-cache", "--diagnostics=json" } });
        try std.testing.expect(checked.term == .exited and checked.term.exited == 1);
        try std.testing.expect(std.mem.indexOf(u8, checked.stderr, expected.code) != null);
        try std.testing.expect(std.mem.indexOf(u8, checked.stderr, rule) != null);
    }
}

// spec-case: CALLBACK-1
test "zero RC A02 indirect calls retain borrowed-return refusals" {
    try refusalCases(std.testing.allocator, &.{
        \\func borrowed(values: str[][]) -> str[] from values:
        \\    return values[0]
        \\func apply(callback: func(str[][]) -> str[], values: str[][]) -> str[]:
        \\    return callback(values)
        \\func main() -> int:
        \\    const values = [["source"]]
        \\    const result = apply(borrowed, values)
        \\    return len(result)
        ,
        \\record Product:
        \\    values: str[]
        \\func borrowed(value: Product) -> Product from value:
        \\    return value
        \\func apply(callback: func(Product) -> Product, value: Product) -> Product:
        \\    return callback(value)
        \\func main() -> int:
        \\    const value = Product(values=["source"])
        \\    const result = apply(borrowed, value)
        \\    return len(result.values)
        ,
    }, .{ .code = "E_VIEW_FUNCTION_VALUE", .rule = .V4 });
}

test "zero RC A02 undeclared borrowed returns require an explicit source" {
    try refusalCases(std.testing.allocator, &.{
        \\func borrowed(values: str[]) -> str[]:
        \\    return values
        \\func apply(callback: func(str[]) -> str[], values: str[]) -> str[]:
        \\    return callback(values)
        \\func main() -> int:
        \\    const values = ["source"]
        \\    const result = apply(borrowed, values)
        \\    return len(result)
        ,
    }, .{ .code = "E_BORROW_UNDECLARED", .rule = .R4 });
}

test "zero RC A02 borrowed stores retain their R1 refusal" {
    try refusalCases(std.testing.allocator, &.{
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
    }, .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .R1 });
}
