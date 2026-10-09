//! Shared release analysis reaches split units, whole output and native receipts.
const std = @import("std");
const frontend = @import("frontend.zig");
const build = @import("build.zig");
const pipeline = @import("pipeline.zig");
const driver = @import("driver.zig");

const app = "import leaf\nfunc main() -> int:\n    mut xs = [1]\n    return leaf.origin(mut xs, 2)\n";
const leaf = "public func origin(mut xs: int[], x: int) -> int:\n    xs.append(2)\n    return xs[x]\n";

fn snapshot(a: std.mem.Allocator, scratch: std.mem.Allocator, mode: @import("build_mode.zig").Mode, whole: bool) !pipeline.Emission {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = app });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "leaf.my", .data = leaf });
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var session = frontend.Session.init(a, std.testing.io, root);
    defer session.deinit();
    var report: std.ArrayList(u8) = .empty;
    const checked = try session.check(a, "app", &report);
    var refusal: build.Refusal = .{};
    var module = try build.buildModuleSource(a, checked.program, checked.src, &refusal);
    const emitted = try pipeline.emittedWithScratch(a, scratch, &module, .{ .src = checked.src, .source_path = "app.my", .main = .{} }, .{
        .zig = "unused",
        .mode = mode,
        .show = .{ .llvm = if (whole) "unused" else null, .stats = true },
    }, &report);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, report.items, "mylang-core: inlined "));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, report.items, "mylang-core: ownership: "));
    return emitted;
}

// spec-case: NEW-CORE-S4-UNITS-1
test "pipeline emitted optional whole output preserves every native unit and cloned source frame" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    inline for (.{ .debug, .optimized_debug, .release }) |mode| {
        const split = try snapshot(a, std.testing.allocator, mode, false);
        const both = try snapshot(a, std.testing.allocator, mode, true);
        try std.testing.expect(split.whole == null);
        try std.testing.expectEqual(split.units.len, both.units.len);
        if (mode == .optimized_debug) try std.testing.expect(split.units.len > 1);
        for (split.units, both.units) |left, right| {
            try std.testing.expectEqualStrings(left.name, right.name);
            try std.testing.expectEqualStrings(left.llvm, right.llvm);
        }
        try std.testing.expect(std.mem.indexOf(u8, both.whole.?, "!DIFile(filename: \"leaf.my\"") != null);
        if (mode != .debug) try std.testing.expect(std.mem.indexOf(u8, both.whole.?, "inlinedAt:") != null);
    }
}

fn native(a: std.mem.Allocator, emission: pipeline.Emission, split: bool, mode: @import("build_mode.zig").Mode) !std.process.RunResult {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    const output = try std.fs.path.join(a, &.{ root, "program" });
    var report: std.ArrayList(u8) = .empty;
    _ = try driver.link(a, std.testing.io, &environment, .{
        .zig = environment.get("MYLANG_ZIG") orelse "zig",
        .work = root,
        .output = output,
        .mode = mode,
        .links = &.{},
        .units = if (split) emission.units else &.{driver.wholeUnit(emission.whole.?)},
    }, &report);
    return std.process.run(a, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment });
}

// spec-case: NEW-CORE-S4-SITES-1
test "pipeline emitted split and whole native traps preserve exact consuming callee and caller frames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const emission = try snapshot(a, std.testing.allocator, .release, true);
    const split = try native(a, emission, true, .release);
    const whole = try native(a, emission, false, .release);
    try std.testing.expectEqual(@as(u8, 1), split.term.exited);
    try std.testing.expectEqual(@as(u8, 1), whole.term.exited);
    try std.testing.expectEqualStrings("", split.stdout);
    try std.testing.expectEqualStrings(split.stdout, whole.stdout);
    try std.testing.expectEqualStrings(split.stderr, whole.stderr);
    try std.testing.expect(std.mem.indexOf(u8, split.stderr, "in leaf::origin at leaf.my:3:12") != null);
    try std.testing.expect(std.mem.indexOf(u8, split.stderr, "in app::main at app.my:4:12") != null);
    const development = try native(a, try snapshot(a, std.testing.allocator, .optimized_debug, false), true, .optimized_debug);
    try std.testing.expectEqual(@as(u8, 1), development.term.exited);
    try std.testing.expectEqualStrings(whole.stdout, development.stdout);
    try std.testing.expectEqualStrings(whole.stderr, development.stderr);
}
