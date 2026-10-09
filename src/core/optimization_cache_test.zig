//! Persistent optimizer stages are checked against the uncached pass oracle.
const std = @import("std");
const support = @import("test_support.zig");
const passes = @import("passes.zig");
const cache = @import("optimization_cache.zig");
const store = @import("stage_store.zig");
const snapshot = @import("ir_snapshot.zig");
const emit = @import("emit_llvm.zig");
const print = @import("print.zig");
const build = @import("build.zig");
const deferred = @import("deferred_facts.zig");

const basic =
    \\func leaf(n: int) -> int:
    \\    return n % 3
    \\
    \\func sum(n: int) -> int:
    \\    mut total = 0
    \\    for i in range(n):
    \\        total += i
    \\    return total
    \\
    \\func idle() -> int:
    \\    return 42
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(sum(7), leaf(7), idle())
    \\    return 0
;
const recursive =
    \\func recurse(n: int) -> int:
    \\    if n <= 0:
    \\        return 3
    \\    return recurse(n - 1)
    \\
    \\func idle() -> int:
    \\    return 42
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(recurse(7), idle())
    \\    return 0
;
const mutating =
    \\record State:
    \\    x: int
    \\    y: int
    \\
    \\func mutate(mut s: State, n: int):
    \\    if n > 0:
    \\        s.x = s.x + 1
    \\        mutate(mut s, n - 1)
    \\
    \\func idle() -> int:
    \\    return 42
    \\
    \\func main(out: Stream) -> int:
    \\    mut s = State(x=0, y=0)
    \\    mutate(mut s, 3)
    \\    out.print(s.x, s.y, idle())
    \\    return 0
;
const Scenario = enum { callee, parameters, recursion, effects };
const Produced = struct { llvm: []const u8, core: []const u8, result: passes.Result, statistics: cache.Statistics };

fn locate(_: *const anyopaque, offset: u32) emit.Location {
    return .{ .line = 1, .column = offset + 1, .path = "test.my" };
}

fn compile(a: std.mem.Allocator, backing: std.mem.Allocator, text: []const u8, storage: ?*store.Store, mode: ?passes.Mode) !Produced {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, text, &refusal);
    const token: u8 = 0;
    const locator: emit.Locator = .{ .context = &token, .locate = locate };
    var context: cache.Context = undefined;
    if (storage) |s| context = cache.Context.init(s, try snapshot.Context.init(a, &module, null), locator);
    const result = if (mode) |m|
        if (storage != null) try passes.runCached(a, backing, &module, m, &context) else try passes.runWithScratch(a, backing, &module, m)
    else if (storage != null)
        try passes.debugCached(a, backing, &module, &context)
    else
        try passes.debugWithScratch(a, backing, &module);
    try support.verified(a, &module, result.plans);
    const llvm = try emit.emitModuleWithScratch(a, backing, &module, .{ .locator = locator, .source_path = "test.my", .main = .{ .parameters = &.{"out"} }, .analysis = support.analysis(&result), .verify = result.verifying });
    return .{ .llvm = llvm, .core = try print.module(a, &module), .result = result, .statistics = if (storage != null) context.statistics else .{} };
}

fn equal(expected: Produced, actual: Produced) !void {
    try std.testing.expectEqualStrings(expected.core, actual.core);
    try std.testing.expectEqualStrings(expected.llvm, actual.llvm);
    try std.testing.expectEqualDeep(expected.result.counts, actual.result.counts);
    try std.testing.expectEqualDeep(expected.result.own, actual.result.own);
    try std.testing.expectEqualDeep(expected.result.per_function, actual.result.per_function);
    try std.testing.expectEqualDeep(expected.result.known, actual.result.known);
    try std.testing.expectEqualDeep(expected.result.plans, actual.result.plans);
}

fn total(values: []const usize) usize {
    var sum: usize = 0;
    for (values) |value| sum += value;
    return sum;
}

fn fixture(a: std.mem.Allocator, scenario: Scenario, edited: bool) ![]const u8 {
    const text = switch (scenario) {
        .callee, .parameters => basic,
        .recursion => recursive,
        .effects => mutating,
    };
    if (!edited) return text;
    const before: []const u8 = switch (scenario) {
        .callee => "n % 3",
        .parameters => "sum(7)",
        .recursion => "return 3",
        .effects => "s.x = s.x + 1",
    };
    const after: []const u8 = switch (scenario) {
        .callee => "n % 5",
        .parameters => "sum(9)",
        .recursion => "return 5",
        .effects => "s.y = s.y + 1",
    };
    const at = std.mem.indexOf(u8, text, before).?;
    return std.fmt.allocPrint(a, "{s}{s}{s}", .{ text[0..at], after, text[at + before.len ..] });
}

// spec: NEW-CORE-STAGE-CACHE-4
test "optimizer stage round trips match the uncached oracle including facts plans ownership and ancestry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    for ([_]?passes.Mode{ .trusted, .verify, null }) |mode| {
        const oracle = try compile(a, std.testing.allocator, basic, null, mode);
        const cold = try compile(a, std.testing.allocator, basic, &storage, mode);
        const warm = try compile(a, std.testing.allocator, basic, &storage, mode);
        try equal(oracle, cold);
        try equal(oracle, warm);
        try std.testing.expectEqual(@as(usize, 0), total(&cold.statistics.hits));
        try std.testing.expect(total(&warm.statistics.hits) > 0);
        try std.testing.expectEqual(@as(usize, 0), total(&warm.statistics.misses));
    }
}

// spec-case: NEW-CORE-STAGE-CACHE-4
test "callee caller parameter recursive return and recursive effect edits invalidate consulted optimizer inputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]Scenario{ .callee, .parameters, .recursion, .effects }) |scenario| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
        defer storage.deinit();
        const before = try fixture(a, scenario, false);
        const after = try fixture(a, scenario, true);
        _ = try compile(a, std.testing.allocator, before, &storage, .trusted);
        const oracle = try compile(a, std.testing.allocator, after, null, .trusted);
        const edited = try compile(a, std.testing.allocator, after, &storage, .trusted);
        const repeated = try compile(a, std.testing.allocator, after, &storage, .trusted);
        try equal(oracle, edited);
        try equal(oracle, repeated);
        try std.testing.expect(total(&edited.statistics.hits) > 0);
        try std.testing.expect(edited.statistics.misses[@backingInt(cache.Stage.final)] > 0);
        try std.testing.expectEqual(@as(usize, 0), total(&repeated.statistics.misses));
    }
}

const DeferredProduced = struct { output: Produced, fact_key: store.Digest };

fn compileDeferred(a: std.mem.Allocator, backing: std.mem.Allocator, text: []const u8, storage: *store.Store) !DeferredProduced {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, text, &refusal);
    const token: u8 = 0;
    const locator: emit.Locator = .{ .context = &token, .locate = locate };
    var context = cache.Context.init(storage, try snapshot.Context.init(a, &module, null), locator);
    var table = try deferred.Table.init(a, module.functions.items.len);
    const result = try passes.runCachedDeferred(a, backing, &module, .trusted, &context, &table);
    try support.verified(a, &module, result.plans);
    for (result.known) |known| try std.testing.expect(known == null);
    // Whole-module emission is only the test oracle: production decodes a selected unit.
    var fact_key: ?store.Digest = null;
    for (result.known, module.functions.items, 0..) |*known, function, index| {
        known.* = try table.load(a, index);
        if (std.mem.eql(u8, function.name, "sum")) fact_key = context.factsKey(table.identity(index).?);
    }
    const llvm = try emit.emitModuleWithScratch(a, backing, &module, .{
        .locator = locator,
        .source_path = "test.my",
        .main = .{ .parameters = &.{"out"} },
        .analysis = support.analysis(&result),
    });
    return .{
        .output = .{ .llvm = llvm, .core = try print.module(a, &module), .result = result, .statistics = context.statistics },
        .fact_key = fact_key.?,
    };
}

// spec-case: NEW-CORE-STAGE-CACHE-4
test "optimizer stage deferred cold and warm results match eager and missing or damaged facts recompute before IR restore" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const oracle = try compile(a, std.testing.allocator, basic, null, .trusted);
    const cold = try compileDeferred(a, std.testing.allocator, basic, &storage);
    const warm = try compileDeferred(a, std.testing.allocator, basic, &storage);
    try equal(oracle, cold.output);
    try equal(oracle, warm.output);
    try std.testing.expectEqual(@as(usize, 0), total(&warm.output.statistics.misses));
    // This has a valid store checksum, but differs from the metadata's fact digest.
    try std.testing.expect(try storage.save(cold.fact_key, "damaged fact payload"));
    const repaired = try compileDeferred(a, std.testing.allocator, basic, &storage);
    try equal(oracle, repaired.output);
    try std.testing.expect(repaired.output.statistics.misses[@backingInt(cache.Stage.final)] > 0);
    const path = try std.fmt.allocPrint(a, "{s}/{s}.stage", .{ storage.root, std.fmt.bytesToHex(cold.fact_key, .lower) });
    try std.Io.Dir.cwd().deleteFile(std.testing.io, path);
    const missing = try compileDeferred(a, std.testing.allocator, basic, &storage);
    try equal(oracle, missing.output);
    try std.testing.expect(missing.output.statistics.misses[@backingInt(cache.Stage.final)] > 0);
}
