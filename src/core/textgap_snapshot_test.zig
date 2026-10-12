//! Checked donor elision preserves independent live snapshots and child borrows.
const std = @import("std");
const report = std.debug.print;
const language = @import("mylang");
const ir = @import("ir.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");

const snapshot = @import("inline_snapshot.zig");
const emit = @import("emit_llvm.zig");
const fixture_name = "textgap_snapshot.my";
fn fixture(a: std.mem.Allocator) ![]const u8 {
    const path = try std.fs.path.join(a, &.{ @import("core_test_options").fixtures, fixture_name });
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(1 << 20));
}
fn buildSource(a: std.mem.Allocator, source: []const u8) !ir.Module {
    var unit = try language.Compilation.init(a, "snapshot.my", source);
    try unit.check();
    var failure: @import("single_owner.zig").Failure = .{};
    try @import("single_owner.zig").checkMode(a, unit.program.?, &failure, true);
    var refusal: build.Refusal = .{};
    return build.buildExecutable(a, .{ .program = unit.program.?, .single_owner = true, .zero_rc = true }, &refusal);
}

const Lane = struct { release: bool, mode: ?passes.Mode };
const lanes = [_]Lane{
    .{ .release = true, .mode = .trusted },
    .{ .release = false, .mode = null },
    .{ .release = true, .mode = .verify },
    .{ .release = false, .mode = .trusted },
    .{ .release = true, .mode = .off },
};

fn execute(a: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    for (lanes) |lane| {
        var module = try buildSource(a, source);
        const result = if (lane.mode) |mode| try passes.run(a, &module, mode) else try passes.debug(a, &module);
        const run = try support.runOwned(a, &module, .{ .own = false, .release = lane.release, .verify = lane.mode == .verify, .analysis = support.analysis(&result) });
        if (run.status != 0) report("snapshot: {s}{s}\n", .{ run.stdout, run.stderr });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings(expected, run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(@import("zero_rc.zig").emittedClean(run.llvm));
    }
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "textgap_snapshot dead owned donors transfer but live sources and children retain independent storage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try execute(a, try fixture(a), "True\nTrue\nTrue\nTrue\n");
}

fn copies(module: *const ir.Module, name: []const u8) usize {
    var result: usize = 0;
    for (module.functions.items) |*f| {
        if (!std.mem.eql(u8, f.name, name)) continue;
        for (f.blocks.items) |block| for (block.insts.items) |ref| {
            if (snapshot.source(module, f, f.inst(ref)) != null) result += 1;
        };
    }
    return result;
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "textgap_snapshot exact wrapper exposure removes only dead owned copy calls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try buildSource(a, try fixture(a));
    var found = false;
    for (module.functions.items) |*f| {
        if (!std.mem.eql(u8, f.name, "snapshot")) continue;
        found = true;
        try std.testing.expect(snapshot.qualifies(&module, f));
        const original = f.signature;
        f.signature.owned = 1;
        try std.testing.expect(!snapshot.qualifies(&module, f));
        f.signature = original;
    }
    try std.testing.expect(found);
    _ = try passes.run(a, &module, .trusted);
    try std.testing.expectEqual(@as(usize, 0), copies(&module, "donated"));
    try std.testing.expect(copies(&module, "snapshot") > 0);
    try std.testing.expect(copies(&module, "test_textgap_json_copy_live_child_outlives_replaced_snapshot_owner") > 0);
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "textgap_snapshot rejects untrusted malformed and wrong type copy helpers" {
    for (0..6) |variant| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var module = try buildSource(a, try fixture(a));
        var tested = false;
        for (module.functions.items, 0..) |f, i| {
            if (!std.mem.eql(u8, f.name, "snapshot")) continue;
            for (f.insts.items) |inst| {
                if (snapshot.source(&module, &f, inst) == null) continue;
                tested = true;
                const callee = &module.functions.items[inst.a.index()];
                switch (variant) {
                    0 => callee.signature.linkage = .extern_c,
                    1 => callee.signature.owned = 1,
                    2 => callee.signature.consumes = 1,
                    3 => callee.signature.views = 1,
                    4 => callee.signature.ret = .str,
                    5 => callee.name = "myl_core_owned_copy_9999999",
                    else => unreachable,
                }
                try std.testing.expect(snapshot.source(&module, &module.functions.items[i], inst) == null);
                try std.testing.expect(!snapshot.qualifies(&module, &module.functions.items[i]));
            }
        }
        try std.testing.expect(tested);
    }
}

const store = @import("stage_store.zig");
const cache = @import("optimization_cache.zig");
const wire = @import("ir_snapshot.zig");
const Produced = struct { llvm: []const u8, statistics: cache.Statistics };
fn locate(_: *const anyopaque, offset: u32) emit.Location {
    return .{ .line = 1, .column = offset + 1, .path = fixture_name };
}
fn compile(a: std.mem.Allocator, backing: std.mem.Allocator, storage: ?*store.Store) !Produced {
    var module = try buildSource(a, try fixture(a));
    const token: u8 = 0;
    const locator: emit.Locator = .{ .context = &token, .locate = locate };
    var context: cache.Context = undefined;
    if (storage) |s| context = cache.Context.init(s, try wire.Context.init(a, &module, null), locator);
    const result = if (storage != null) try passes.runCached(a, backing, &module, .trusted, &context) else try passes.runWithScratch(a, backing, &module, .trusted);
    try support.verified(a, &module, result.plans);
    try std.testing.expectEqual(@as(usize, 0), copies(&module, "donated"));
    try std.testing.expect(copies(&module, "test_textgap_json_copy_live_child_outlives_replaced_snapshot_owner") > 0);
    const llvm = try emit.emitModule(a, &module, .{ .locator = locator, .source_path = fixture_name, .main = .{ .parameters = &.{"out"}, .capabilities = &.{0} }, .analysis = support.analysis(&result) });
    try std.testing.expect(@import("zero_rc.zig").emittedClean(llvm));
    return .{ .llvm = llvm, .statistics = if (storage != null) context.statistics else .{} };
}
// spec-case: NEW-CORE-STAGE-CACHE-8
// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "textgap_snapshot cold warm replay matches uncached donor and retained child ownership" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try dir.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const uncached = try compile(a, std.testing.allocator, null);
    const cold = try compile(a, std.testing.allocator, &storage);
    const warm = try compile(a, std.testing.allocator, &storage);
    try std.testing.expectEqualStrings(uncached.llvm, cold.llvm);
    try std.testing.expectEqualStrings(cold.llvm, warm.llvm);
    try std.testing.expect(warm.statistics.hits[@backingInt(cache.Stage.inline_cfg)] > 0);
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "textgap_snapshot direct retained dictionary child binding still refuses before optimization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "retained.my",
        \\func main() -> int:
        \\    mut values: dict[str, str[]] = {"key": ["old-" + str(7)]}
        \\    const child = values["key"]
        \\    return len(child)
    );
    try unit.check();
    var failure: @import("single_owner.zig").Failure = .{};
    try std.testing.expectError(error.Rejected, @import("single_owner.zig").checkMode(a, unit.program.?, &failure, true));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_BORROW", failure.code);
}
