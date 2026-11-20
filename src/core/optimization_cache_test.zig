//! Persistent optimizer stages are checked against the uncached pass oracle.
const std = @import("std");
const stage_loss = @import("stage_loss_test_support.zig");
const demand_ir = @import("demand_ir.zig");
const support = @import("test_support.zig");
const passes = @import("passes.zig");
const facts = @import("facts.zig");
const fields = @import("fields.zig");
const cache = @import("optimization_cache.zig");
const store = @import("stage_store.zig");
const snapshot = @import("ir_snapshot.zig");
const emit = @import("emit_llvm.zig");
const print = @import("print.zig");
const build = @import("build.zig");
const deferred = @import("deferred_facts.zig");
const source = @import("selka").source;
const shortcut_mod = @import("optimizer_shortcut.zig");

const basic =
    \\func leaf(n: int) -> int:
    \\    return n % 3
    \\
    \\func my_sum(n: int) -> int:
    \\    mut total = 0
    \\    for i in range(n):
    \\        total += i
    \\    return total
    \\
    \\func idle() -> int:
    \\    return 42
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, my_sum(7), leaf(7), idle())
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
    \\    print(out, recurse(7), idle())
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
    \\    print(out, s.x, s.y, idle())
    \\    return 0
;
const Scenario = enum { callee, parameters, recursion, effects };
const borrowed_reader =
    \\func read(xs: int[]) -> int[]:
    \\    mut total = 0
    \\    for i in range(len(xs)):
    \\        total += xs[i]
    \\    return [total]
    \\
    \\func forward(xs: int[]) -> int[]:
    \\    return read(xs)
    \\
    \\func main(out: Stream) -> int:
    \\    const xs = [4, 8, 15, 16, 23, 42]
    \\    const answer = forward(xs)
    \\    print(out, len(answer), len(xs))
    \\    return 0
;
const Produced = struct { llvm: []const u8, core: []const u8, result: passes.Result, statistics: cache.Statistics, ancestry: []const cache.Provenance = &.{} };

fn locate(_: *const anyopaque, offset: u32) emit.Location {
    return .{ .line = 1, .column = offset + 1, .path = "test.selka" };
}

/// Build `text` as an embedded project when it imports a module, so the
/// standard-module functions it names resolve; a headerless program stays a
/// single unit.
fn checkedModule(a: std.mem.Allocator, text: []const u8, refusal: *build.Refusal) !@import("ir.zig").Module {
    if (std.mem.startsWith(u8, text, "import ")) return support.projectModule(a, text, refusal);
    return support.buildSource(a, text, refusal);
}

fn compile(a: std.mem.Allocator, backing: std.mem.Allocator, text: []const u8, storage: ?*store.Store, mode: ?passes.Mode) !Produced {
    var refusal: build.Refusal = .{};
    var module = try checkedModule(a, text, &refusal);
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
    const llvm = try emit.emitModuleWithScratch(a, backing, &module, .{ .locator = locator, .source_path = "test.selka", .main = .{ .parameters = &.{"out"} }, .analysis = support.analysis(&result), .verify = result.emission.verifying });
    return .{ .llvm = llvm, .core = try canonicalCore(a, &module), .result = result, .statistics = if (storage != null) context.statistics else .{}, .ancestry = try canonicalAncestry(a, &module, &result.provenance) };
}

fn canonicalAncestry(a: std.mem.Allocator, module: *@import("ir.zig").Module, provenance: *const @import("inline_origins.zig").Table) ![]const cache.Provenance {
    const ancestry = try a.alloc(cache.Provenance, module.functions.items.len);
    const locations: snapshot.Context = .{ .module = module, .source = null };
    for (ancestry, 0..) |*scopes, index| scopes.* = try cache.Provenance.capture(a, locations, provenance, @intCast(index));
    return ancestry;
}

fn equal(expected: Produced, actual: Produced) !void {
    try std.testing.expectEqualStrings(expected.core, actual.core);
    try std.testing.expectEqualStrings(expected.llvm, actual.llvm);
    try std.testing.expectEqualDeep(expected.result.counts, actual.result.counts);
    try std.testing.expectEqualDeep(expected.result.own, actual.result.own);
    try std.testing.expectEqualDeep(expected.result.per_function, actual.result.per_function);
    try std.testing.expectEqualDeep(expected.result.known, actual.result.known);
    try std.testing.expectEqualDeep(expected.result.plans, actual.result.plans);
    try std.testing.expectEqualDeep(expected.ancestry, actual.ancestry);
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
        .parameters => "my_sum(7)",
        .recursion => "return 3",
        .effects => "s.x = s.x + 1",
    };
    const after: []const u8 = switch (scenario) {
        .callee => "n % 5",
        .parameters => "my_sum(9)",
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

const named_before =
    \\record Pair:
    \\    a: int
    \\    b: int
    \\
    \\record Twin:
    \\    a: int
    \\    b: int
    \\
    \\func total(p: Pair) -> int:
    \\    return p.a + p.b
    \\
    \\func twin_total(t: Twin) -> int:
    \\    return t.a * t.b
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, total(Pair(a=1, b=2)), twin_total(Twin(a=1, b=2)))
    \\    return 0
;
/// `named_before` with `main` changed to call a new function first and the two calls swapped, so every function after `main` moves,
/// `Twin` comes before `Pair` in the type table, and the two records of one shape can be told apart only by their names. The records
/// and the functions before `main` keep their text and so their positions (a final record is keyed by them); the field table, kept
/// whole in the key, is the same under the swap, since both records hold the same intervals.
const named_after =
    \\record Pair:
    \\    a: int
    \\    b: int
    \\
    \\record Twin:
    \\    a: int
    \\    b: int
    \\
    \\func total(p: Pair) -> int:
    \\    return p.a + p.b
    \\
    \\func twin_total(t: Twin) -> int:
    \\    return t.a * t.b
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, pad(1), twin_total(Twin(a=1, b=2)), total(Pair(a=1, b=2)))
    \\    return 0
    \\
    \\func pad(n: int) -> int:
    \\    return n + 1
;

/// A program with no record, so the exploratory summaries go through the `first_facts` records (a program with records takes the
/// field rounds, which the manifest keeps), and the same program with a function added and the calls reordered.
const plain_before =
    \\func leaf(n: int) -> int:
    \\    return n % 3
    \\
    \\func my_sum(n: int) -> int:
    \\    mut total = 0
    \\    for i in range(n):
    \\        total += i
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, my_sum(7), leaf(7))
    \\    return 0
;
const plain_after =
    \\func leaf(n: int) -> int:
    \\    return n % 3
    \\
    \\func my_sum(n: int) -> int:
    \\    mut total = 0
    \\    for i in range(n):
    \\        total += i
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, pad(1), leaf(7), my_sum(7))
    \\    return 0
    \\
    \\func pad(n: int) -> int:
    \\    return n + 1
;

test "the optimizer's stage records are restored after functions and records are added ahead of them, because they name their callees and types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Case = struct { before: []const u8, after: []const u8, summaries: bool };
    for ([_]Case{ .{ .before = named_before, .after = named_after, .summaries = false }, .{ .before = plain_before, .after = plain_after, .summaries = true } }) |case| {
        for ([_]passes.Mode{ .trusted, .verify }) |mode| {
            var temporary = std.testing.tmpDir(.{});
            defer temporary.cleanup();
            var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
            defer storage.deinit();
            _ = try compile(a, std.testing.allocator, case.before, &storage, mode);
            const oracle = try compile(a, std.testing.allocator, case.after, null, mode);
            const shifted = try compile(a, std.testing.allocator, case.after, &storage, mode);
            try equal(oracle, shifted);
            // The functions before `main` did not change: their final records come back though the tables around them moved
            // (`Pair` found by its name while `Twin` has its shape), and so do their intermediate records and summaries.
            try std.testing.expect(shifted.statistics.restores.final >= 1);
            try std.testing.expect(shifted.statistics.hits[@backingInt(cache.Stage.unswitch)] >= 1);
            if (case.summaries) try std.testing.expect(shifted.statistics.hits[@backingInt(cache.Stage.first_facts)] >= 1);
            try std.testing.expectEqual(@as(usize, 0), shifted.statistics.restores.refused);
        }
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

const consuming_source =
    \\func append_batch(values: int[], n: int) -> int[]:
    \\    mut result = copy(values)
    \\    for i in range(n):
    \\        append(mut result, i)
    \\    return result
    \\
    \\func replace(n: int) -> int:
    \\    mut values: int[] = []
    \\    for i in range(n):
    \\        values = append_batch(values, 3)
    \\    return len(values)
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, replace(8))
    \\    return 0
;

// spec: NEW-CORE-CONSUME-2
test "owned list copies survive caches and invalidate when the returned root changes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const edited_source = try std.mem.replaceOwned(u8, a, consuming_source, "return result", "return copy(values)");
    for ([_]passes.Mode{ .trusted, .verify }) |mode| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
        defer storage.deinit();
        const oracle = try compile(a, std.testing.allocator, consuming_source, null, mode);
        const cold = try compile(a, std.testing.allocator, consuming_source, &storage, mode);
        const warm = try compile(a, std.testing.allocator, consuming_source, &storage, mode);
        try equal(oracle, cold);
        try equal(oracle, warm);
        try std.testing.expectEqual(@as(usize, 0), total(&warm.statistics.misses));
        const changed = try compile(a, std.testing.allocator, edited_source, null, mode);
        try equal(changed, try compile(a, std.testing.allocator, edited_source, &storage, mode));
        try equal(changed, try compile(a, std.testing.allocator, edited_source, &storage, mode));
        try equal(oracle, try compile(a, std.testing.allocator, consuming_source, &storage, mode));
    }
}

// spec-case: NEW-CORE-CONSUME-2
test "owned list demand proofs agree with eager ownership across omitted bodies and function values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const callback =
        \\func apply(f: func(int) -> int, n: int) -> int:
        \\    return f(n)
        \\
    ;
    // migrate-embedded: skip original constructed lambda input; named callback counterpart follows.
    const legacy_source = try std.mem.replaceOwned(u8, a, consuming_source, "mut result = copy(values)", "mut result = values");
    const legacy_indirect_main = try std.mem.replaceOwned(u8, a, legacy_source, "print(out, replace(8))", "print(out, apply(lambda n: replace(n), 8))");
    const legacy_indirect = try std.mem.concat(a, u8, &.{ callback, "\n", legacy_indirect_main });
    var retired = try @import("selka").Compilation.init(a, "original-consuming-callback.selka", legacy_indirect);
    defer retired.deinit();
    try std.testing.expectError(error.SourceError, retired.check());
    try std.testing.expectEqualStrings("E_LAMBDA_REMOVED", retired.diagnostics.items[0].code);
    const named_callback = "func replace_callback(n: int) -> int:\n    return replace(n)\n";
    const indirect_main = try std.mem.replaceOwned(u8, a, consuming_source, "print(out, replace(8))", "print(out, apply(replace_callback, 8))");
    const indirect = try std.mem.concat(a, u8, &.{ callback, "\n", named_callback, "\n", indirect_main });
    const edited_source = try std.mem.replaceOwned(u8, a, consuming_source, "return result", "return copy(values)");
    for ([_]passes.Mode{ .trusted, .verify }) |mode| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
        defer storage.deinit();
        for ([_][]const u8{ consuming_source, edited_source, consuming_source, indirect, consuming_source }) |text| {
            const oracle = try compile(a, std.testing.allocator, text, null, mode);
            const cold = try compileDemandGuarded(a, std.testing.allocator, text, &storage, .{ .mode = mode, .omit = true });
            const warm = try compileDemandGuarded(a, std.testing.allocator, text, &storage, .{ .mode = mode, .omit = true });
            try equal(oracle, cold.output);
            try equal(oracle, warm.output);
            try std.testing.expect(warm.omitted > 0);
            try std.testing.expectEqual(@as(usize, 0), warm.output.statistics.active_functions);
        }
    }
}

const caller_destination_source =
    \\func make_values(seed: int) -> int[]:
    \\    mut values: int[] = []
    \\    for i in range(8):
    \\        append(mut values, seed + i)
    \\    return values
    \\
    \\func sum_values(values: int[]) -> int:
    \\    mut total = 0
    \\    for value in values:
    \\        total += value
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, sum_values(make_values(7)))
    \\    return 0
;

// spec: NEW-CORE-DEST-2
test "caller destination caches invalidate when a constructor exceeds the stack bound" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const larger = try std.mem.replaceOwned(u8, a, caller_destination_source, "range(8)", "range(600)");
    for ([_]passes.Mode{ .trusted, .verify }) |mode| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
        defer storage.deinit();
        const oracle = try compile(a, std.testing.allocator, caller_destination_source, null, mode);
        try std.testing.expectEqual(@as(u32, 1), oracle.result.own.promoted);
        const cold = try compile(a, std.testing.allocator, caller_destination_source, &storage, mode);
        const warm = try compile(a, std.testing.allocator, caller_destination_source, &storage, mode);
        try equal(oracle, cold);
        try equal(oracle, warm);
        try std.testing.expectEqual(@as(usize, 0), total(&warm.statistics.misses));
        const edited_oracle = try compile(a, std.testing.allocator, larger, null, mode);
        try std.testing.expectEqual(@as(u32, 0), edited_oracle.result.own.promoted);
        const edited = try compile(a, std.testing.allocator, larger, &storage, mode);
        try equal(edited_oracle, edited);
        try std.testing.expect(edited.statistics.misses[@backingInt(cache.Stage.inline_cfg)] > 0);
        try equal(oracle, try compile(a, std.testing.allocator, caller_destination_source, &storage, mode));
    }
}

// spec-case: NEW-CORE-DEST-2
test "caller destination proofs agree across deferred bodies and constructor edits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const larger = try std.mem.replaceOwned(u8, a, caller_destination_source, "range(8)", "range(600)");
    for ([_]passes.Mode{ .trusted, .verify }) |mode| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
        defer storage.deinit();
        const oracle = try compile(a, std.testing.allocator, caller_destination_source, null, mode);
        const cold = try compileDemandGuarded(a, std.testing.allocator, caller_destination_source, &storage, .{ .mode = mode, .omit = true });
        const warm = try compileDemandGuarded(a, std.testing.allocator, caller_destination_source, &storage, .{ .mode = mode, .omit = true });
        try equal(oracle, cold.output);
        try equal(oracle, warm.output);
        try std.testing.expectEqual(@as(u32, 1), warm.output.result.own.promoted);
        try std.testing.expect(warm.omitted > 0);
        const edited_oracle = try compile(a, std.testing.allocator, larger, null, mode);
        const edited = try compileDemandGuarded(a, std.testing.allocator, larger, &storage, .{ .mode = mode, .omit = true });
        const repeated = try compileDemandGuarded(a, std.testing.allocator, larger, &storage, .{ .mode = mode, .omit = true });
        try equal(edited_oracle, edited.output);
        try equal(edited_oracle, repeated.output);
        try std.testing.expectEqual(@as(u32, 0), edited.output.result.own.promoted);
        try std.testing.expectEqual(@as(usize, 0), repeated.output.statistics.active_functions);
        const restored = try compileDemandGuarded(a, std.testing.allocator, caller_destination_source, &storage, .{ .mode = mode, .omit = true });
        try equal(oracle, restored.output);
    }
}

// spec: NEW-CORE-STACK-4
test "borrow-only proofs survive warm optimizer caches and a transitive explicit copy removes stack promotion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const after = try std.mem.replaceOwned(u8, a, borrowed_reader, "return [total]", "return copy(xs)");
    for ([_]passes.Mode{ .trusted, .verify }) |mode| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
        defer storage.deinit();
        const before = try compile(a, std.testing.allocator, borrowed_reader, null, mode);
        try std.testing.expectEqual(@as(u32, 1), before.result.own.promoted);
        const cold = try compile(a, std.testing.allocator, borrowed_reader, &storage, mode);
        const warm = try compile(a, std.testing.allocator, borrowed_reader, &storage, mode);
        try equal(before, cold);
        try equal(before, warm);
        try std.testing.expectEqual(@as(usize, 0), total(&warm.statistics.misses));
        const oracle = try compile(a, std.testing.allocator, after, null, mode);
        try std.testing.expectEqual(@as(u32, 0), oracle.result.own.promoted);
        const changed = try compile(a, std.testing.allocator, after, &storage, mode);
        const repeated = try compile(a, std.testing.allocator, after, &storage, mode);
        try equal(oracle, changed);
        try equal(oracle, repeated);
        try std.testing.expect(changed.statistics.misses[@backingInt(cache.Stage.final)] > 0);
        try std.testing.expectEqual(@as(usize, 0), total(&repeated.statistics.misses));
        try equal(before, try compile(a, std.testing.allocator, borrowed_reader, &storage, mode));
    }
}

// spec-case: NEW-CORE-STACK-4
test "borrow-only proofs survive deferred bodies and invalidate unchanged transitive callers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const after = try std.mem.replaceOwned(u8, a, borrowed_reader, "return [total]", "return copy(xs)");
    for ([_]passes.Mode{ .trusted, .verify }) |mode| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
        defer storage.deinit();
        const before = try compile(a, std.testing.allocator, borrowed_reader, null, mode);
        const cold = try compileDemandGuarded(a, std.testing.allocator, borrowed_reader, &storage, .{ .mode = mode, .omit = true });
        const warm = try compileDemandGuarded(a, std.testing.allocator, borrowed_reader, &storage, .{ .mode = mode, .omit = true });
        try equal(before, cold.output);
        try equal(before, warm.output);
        try std.testing.expectEqual(@as(u32, 1), warm.output.result.own.promoted);
        try std.testing.expect(warm.omitted > 0);
        const oracle = try compile(a, std.testing.allocator, after, null, mode);
        const changed = try compileDemandGuarded(a, std.testing.allocator, after, &storage, .{ .mode = mode, .omit = true });
        const repeated = try compileDemandGuarded(a, std.testing.allocator, after, &storage, .{ .mode = mode, .omit = true });
        try equal(oracle, changed.output);
        try equal(oracle, repeated.output);
        try std.testing.expectEqual(@as(u32, 0), changed.output.result.own.promoted);
        try std.testing.expectEqual(@as(usize, 0), repeated.output.statistics.active_functions);
        const restored = try compileDemandGuarded(a, std.testing.allocator, borrowed_reader, &storage, .{ .mode = mode, .omit = true });
        try equal(before, restored.output);
    }
}

// spec-case: NEW-CORE-STACK-4
test "borrow-only proof changes final cache identity even when field effects are unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, borrowed_reader, &refusal);
    const token: u8 = 0;
    const locator: emit.Locator = .{ .context = &token, .locate = locate };
    var context = cache.Context.init(&storage, try snapshot.Context.init(a, &module, null), locator);
    try context.prepare(a);
    const summaries = try @import("effects.zig").analyze(a, &module);
    var reader: ?usize = null;
    var caller: ?u32 = null;
    for (module.functions.items, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, "read")) reader = index;
        if (std.mem.eql(u8, function.name, "forward")) caller = @intCast(index);
    }
    try std.testing.expect(summaries.of(reader.?, 0).borrow_only);
    const provenance: @import("inline_origins.zig").Table = .{};
    const request: cache.Request = .{ .stage = .final, .function = caller.?, .mode = @backingInt(passes.Mode.trusted), .provenance = &provenance, .inputs = .{ .effects = &summaries } };
    const before = (try context.key(a, request)).?;
    summaries.params[reader.?][0].borrow_only = false;
    const after = (try context.key(a, request)).?;
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

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
        if (std.mem.eql(u8, function.name, "my_sum")) fact_key = context.factsKey(table.identity(index).?);
    }
    const llvm = try emit.emitModuleWithScratch(a, backing, &module, .{
        .locator = locator,
        .source_path = "test.selka",
        .main = .{ .parameters = &.{"out"} },
        .analysis = support.analysis(&result),
    });
    return .{
        .output = .{ .llvm = llvm, .core = try canonicalCore(a, &module), .result = result, .statistics = context.statistics, .ancestry = try canonicalAncestry(a, &module, &result.provenance) },
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
    try stage_loss.remove(a, &storage, cold.fact_key);
    const missing = try compileDeferred(a, std.testing.allocator, basic, &storage);
    try equal(oracle, missing.output);
    try std.testing.expect(missing.output.statistics.misses[@backingInt(cache.Stage.final)] > 0);
}

const shifted_predecessor =
    \\func before() -> str:
    \\    return "tiny"
    \\
    \\func affine(x: int) -> int:
    \\    return x * 3 + 7
    \\
    \\func caller(n: int) -> int:
    \\    return affine(n % 100)
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, before(), caller(9), affine(12))
    \\    return 0
;

// spec: NEW-CORE-STAGE-CACHE-8
test "optimizer shortcut leaves independent identity checkpoints untouched across a callee edit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const edited = try fixture(a, .callee, true);
    const cold = try compile(a, std.testing.allocator, basic, &storage, .trusted);
    const warm = try compile(a, std.testing.allocator, basic, &storage, .trusted);
    const oracle = try compile(a, std.testing.allocator, edited, null, .trusted);
    const changed = try compile(a, std.testing.allocator, edited, &storage, .trusted);
    const repeated = try compile(a, std.testing.allocator, edited, &storage, .trusted);
    try equal(cold, warm);
    try equal(oracle, changed);
    try equal(oracle, repeated);
    try std.testing.expect(warm.statistics.bypassed >= 2);
    try std.testing.expect(changed.statistics.bypassed >= 1);
    try std.testing.expect(warm.statistics.hits[@backingInt(cache.Stage.first_facts)] < cold.statistics.misses[@backingInt(cache.Stage.first_facts)]);
    try std.testing.expect(changed.statistics.hits[@backingInt(cache.Stage.final)] > changed.statistics.hits[@backingInt(cache.Stage.inline_leaf)]);
    try std.testing.expectEqual(@as(usize, 0), total(&repeated.statistics.misses));
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer shortcut demotes an unchanged callee when its incoming caller interval changes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const edited = try fixture(a, .parameters, true);
    _ = try compile(a, std.testing.allocator, basic, &storage, .trusted);
    const warm = try compile(a, std.testing.allocator, basic, &storage, .trusted);
    const oracle = try compile(a, std.testing.allocator, edited, null, .trusted);
    const changed = try compile(a, std.testing.allocator, edited, &storage, .trusted);
    const repeated = try compile(a, std.testing.allocator, edited, &storage, .trusted);
    try equal(oracle, changed);
    try equal(oracle, repeated);
    try std.testing.expect(changed.statistics.bypassed < warm.statistics.bypassed);
    try std.testing.expect(changed.statistics.misses[@backingInt(cache.Stage.final)] > 0);
    try std.testing.expectEqual(warm.statistics.bypassed, repeated.statistics.bypassed);
}

fn sourceLocation(context: *const anyopaque, offset: u32) emit.Location {
    const src: *const source.Source = @ptrCast(@alignCast(context));
    const at = src.locate(offset);
    return .{ .line = @intCast(at.line), .column = @intCast(at.column), .path = at.path };
}

fn compileLocated(a: std.mem.Allocator, backing: std.mem.Allocator, text: []const u8, storage: ?*store.Store) !Produced {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, text, &refusal);
    const src = try source.Source.init(a, "test.selka", text);
    const locator: emit.Locator = .{ .context = &src, .locate = sourceLocation };
    var context: cache.Context = undefined;
    if (storage) |s| context = cache.Context.init(s, try snapshot.Context.init(a, &module, src), locator);
    const result = if (storage != null)
        try passes.runCached(a, backing, &module, .trusted, &context)
    else
        try passes.runWithScratch(a, backing, &module, .trusted);
    try support.verified(a, &module, result.plans);
    const llvm = try emit.emitModuleWithScratch(a, backing, &module, .{
        .locator = locator,
        .source_path = src.path,
        .main = .{ .parameters = &.{"out"} },
        .analysis = support.analysis(&result),
    });
    const ancestry = try a.alloc(cache.Provenance, module.functions.items.len);
    const locations: snapshot.Context = .{ .module = &module, .source = src };
    for (ancestry, 0..) |*scopes, index| scopes.* = try cache.Provenance.capture(a, locations, &result.provenance, @intCast(index));
    return .{ .llvm = llvm, .core = try canonicalCore(a, &module), .result = result, .statistics = if (storage != null) context.statistics else .{}, .ancestry = ancestry };
}

fn hasNestedAncestry(result: *const passes.Result) bool {
    for (result.provenance.frames.items) |frame| if (frame.parent != null) return true;
    return false;
}

// spec-case: NEW-CORE-STAGE-CACHE-4
test "optimizer cache relocates later declarations and nested inline ancestry after an earlier same-line literal grows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const edited = try std.mem.replaceOwned(u8, a, shifted_predecessor, "tiny", "significantly longer preceding literal");
    _ = try compileLocated(a, std.testing.allocator, shifted_predecessor, &storage);
    const oracle = try compileLocated(a, std.testing.allocator, edited, null);
    const cached = try compileLocated(a, std.testing.allocator, edited, &storage);
    const repeated = try compileLocated(a, std.testing.allocator, edited, &storage);
    try std.testing.expect(hasNestedAncestry(&oracle.result));
    try std.testing.expect(std.mem.indexOf(u8, oracle.llvm, "!DILocation(") != null);
    try std.testing.expect(cached.statistics.hits[@backingInt(cache.Stage.inline_leaf)] > 0);
    try std.testing.expect(cached.statistics.hits[@backingInt(cache.Stage.final)] >= 2);
    try equal(oracle, cached);
    try equal(oracle, repeated);
    try std.testing.expectEqualDeep(oracle.ancestry, cached.ancestry);
    try std.testing.expectEqualDeep(oracle.ancestry, repeated.ancestry);
    try std.testing.expectEqual(@as(usize, 0), total(&repeated.statistics.misses));
}

const DemandProduced = struct { output: Produced, loaded: usize, omitted: usize, emission: @import("emission_cache.zig").Counts, final_restored: usize, deferred_functions: []const []const u8 };
const DemandFinalLoader = struct {
    arena: std.mem.Allocator,
    context: *cache.Context,
    result: *passes.Result,
    restored: usize = 0,
    fn ensure(pointer: *anyopaque, index: u32) demand_ir.Error!void {
        const self: *DemandFinalLoader = @ptrCast(@alignCast(pointer));
        if (self.context.source.module.functions.items[index].signature.linkage != .internal or self.context.lazy.loaded[index]) return;
        var scratch = std.heap.ArenaAllocator.init(self.arena);
        defer scratch.deinit();
        passes.restoreDeferredFinal(self.arena, scratch.allocator(), self.context, index, self.result) catch |err| switch (err) {
            error.Unsupported => return error.CacheMiss,
            error.OutOfMemory => return error.OutOfMemory,
            error.CacheMiss => return error.CacheMiss,
        };
        self.restored += 1;
    }
};
const DemandLoader = struct {
    arena: std.mem.Allocator,
    context: snapshot.Context,
    bodies: []snapshot.Wire,

    fn ensure(pointer: *anyopaque, index: u32) demand_ir.Error!void {
        const self: *DemandLoader = @ptrCast(@alignCast(pointer));
        self.context.module.functions.items[index] = snapshot.restore(self.arena, self.context, self.bodies[index]) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return error.CacheMiss,
        };
    }
};

/// `stable_keys` keys each function's lowering by the digest of its body alone, as the engine's part keys do, so that it does not
/// change when the tables around it move.
/// `plain_keys` also gives each function the digest of its body without source positions as its lowering key without the source
/// proof (`demand_ir.Context.unmixed`), which a line shifted above a function leaves as it was.
const DemandSettings = struct { omit: bool, force_eager: bool = false, mode: passes.Mode = .verify, stable_keys: bool = false, plain_keys: bool = false, cutoff: @import("optimizer_cutoff.zig").Mode = .cutoff };
fn verifyFinalDigests(a: std.mem.Allocator, locator: emit.Locator, context: *const cache.Context) !void {
    var fresh = try @import("canonical_ir.zig").Canon.prepare(a, context.source.module, locator);
    for (context.lazy.finals, context.lazy.loaded, 0..) |metadata, present, index| {
        if (!present) continue;
        const record = metadata orelse continue;
        const digest = try fresh.functionDigest(@intCast(index));
        try std.testing.expectEqualSlices(u8, &digest, &record.body.positioned);
    }
}

fn compileDemand(a: std.mem.Allocator, backing: std.mem.Allocator, text: []const u8, storage: *store.Store, omit: bool) !DemandProduced {
    return compileDemandGuarded(a, backing, text, storage, .{ .omit = omit });
}
fn compileDemandGuarded(a: std.mem.Allocator, backing: std.mem.Allocator, text: []const u8, storage: *store.Store, settings: DemandSettings) !DemandProduced {
    var refusal: build.Refusal = .{};
    var module = try checkedModule(a, text, &refusal);
    const token: u8 = 0;
    const locator: emit.Locator = .{ .context = &token, .locate = locate };
    const source_context = try snapshot.Context.init(a, &module, null);
    const raw_layout = try snapshot.layout(a, source_context);
    const count = module.functions.items.len;
    const bodies = try a.alloc(snapshot.Wire, count);
    const keys = try a.alloc(?store.Digest, count);
    const unmixed = try a.alloc(?store.Digest, count);
    const loaded = try a.alloc(bool, count);
    var stable_canon = try @import("canonical_ir.zig").Canon.prepare(a, &module, locator);
    for (module.functions.items, bodies, keys, loaded, 0..) |*function, *body, *key, *present, index| {
        body.* = try snapshot.capture(a, source_context, function.*);
        unmixed[index] = if (settings.plain_keys)
            storage.key("test-demand-lowering-plain", &.{&(try stable_canon.plainDigest(@intCast(index)))})
        else
            null;
        const body_digest = try snapshot.digest(a, source_context, function.*);
        key.* = if (settings.stable_keys)
            storage.key("test-demand-lowering-stable", &.{&(try stable_canon.functionDigest(@intCast(index)))})
        else
            storage.key("test-demand-lowering", &.{ &raw_layout, &body_digest });
        present.* = !settings.omit or function.signature.linkage != .internal;
        if (!present.*) function.* = .{ .name = function.name, .signature = function.signature, .span = function.span };
    }
    var loader: DemandLoader = .{ .arena = a, .context = source_context, .bodies = bodies };
    var demand: demand_ir.Context = .{ .keys = keys, .unmixed = if (settings.plain_keys) unmixed else &.{}, .loaded = loaded, .pointer = &loader, .ensure_fn = DemandLoader.ensure, .force_eager = settings.force_eager };
    var context = cache.Context.init(storage, source_context, locator);
    context.lazy.raw = &demand;
    context.lazy.cutoff = settings.cutoff;
    var table = try deferred.Table.init(a, count);
    var result = try passes.runCachedDeferred(a, backing, &module, settings.mode, &context, &table);
    try verifyFinalDigests(a, locator, &context);
    var materialized: usize = 0;
    for (loaded) |present| materialized += @intFromBool(present);
    var omitted: usize = 0;
    var deferred_functions: std.ArrayList([]const u8) = .empty;
    for (module.functions.items, 0..) |function, index| {
        if (function.signature.linkage == .internal and !context.lazy.loaded[index]) {
            omitted += 1;
            try deferred_functions.append(a, function.name);
        }
    }
    var final_loader: DemandFinalLoader = .{ .arena = a, .context = &context, .result = &result };
    const original_source = try source.Source.init(a, "test.selka", text);
    var emission_counts: @import("emission_cache.zig").Counts = .{};
    var analysis = support.analysis(&result);
    analysis.effects = if (result.emission.effects) |*summaries| summaries else null;
    const emission_options: emit.Options = .{ .locator = locator, .source_path = "test.selka", .main = .{ .parameters = &.{"out"} }, .analysis = analysis, .verify = result.emission.verifying };
    const emitted = try @import("emit_units.zig").emitCached(a, backing, &module, emission_options, .{
        .store = storage,
        .counts = &emission_counts,
        .deferred = &table,
        .receipts = .{
            .finals = context.lazy.finals,
            .source = &original_source,
            .loader = .{ .pointer = &final_loader, .ensure_fn = DemandFinalLoader.ensure },
        },
    });
    const emission_restored = final_loader.restored;
    for (module.functions.items, 0..) |function, index| {
        if (function.signature.linkage != .internal) continue;
        if (!context.lazy.loaded[index]) {
            try passes.restoreDeferredFinal(a, a, &context, @intCast(index), &result);
        }
        result.known[index] = try table.load(a, index);
    }
    try support.verified(a, &module, result.plans);
    const fresh_units = try @import("emit_units.zig").emitWithScratch(a, backing, &module, emission_options);
    try std.testing.expectEqual(emitted.len, fresh_units.len);
    for (emitted, fresh_units) |actual, expected| {
        try std.testing.expectEqualStrings(expected.name, actual.name);
        try std.testing.expectEqualStrings(expected.llvm, actual.llvm);
        try std.testing.expectEqual(expected.dependencies.number, actual.dependencies.number);
        try std.testing.expectEqual(expected.dependencies.math, actual.dependencies.math);
        try std.testing.expectEqual(expected.dependencies.counting, actual.dependencies.counting);
    }
    const llvm = try emit.emitModuleWithScratch(a, backing, &module, .{
        .locator = locator,
        .source_path = "test.selka",
        .main = .{ .parameters = &.{"out"} },
        .analysis = support.analysis(&result),
        .verify = result.emission.verifying,
    });
    return .{
        .loaded = materialized,
        .omitted = omitted,
        .deferred_functions = deferred_functions.items,
        .emission = emission_counts,
        .final_restored = emission_restored,
        .output = .{ .llvm = llvm, .core = try canonicalCore(a, &module), .result = result, .statistics = context.statistics, .ancestry = try canonicalAncestry(a, &module, &result.provenance) },
    };
}

/// `pad` comes first in the text and nothing calls it, so the program does not lower it; `mid` calls `sum`, a recursion the
/// inliner leaves alone. In the second program `main` calls `pad`, so `pad` is lowered ahead of `sum` and `mid` and their numbers move
/// by one while their text, and so their positions, stay: the dependency digests of `mid` held the number of `sum`.
const chain_before =
    \\func pad(n: int) -> int:
    \\    return n + 1
    \\
    \\func my_sum(n: int) -> int:
    \\    if n <= 0:
    \\        return 3
    \\    return my_sum(n - 1)
    \\
    \\func mid(n: int) -> int:
    \\    return my_sum(n) + 1
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, mid(7))
    \\    return 0
;
const chain_after =
    \\func pad(n: int) -> int:
    \\    return n + 1
    \\
    \\func my_sum(n: int) -> int:
    \\    if n <= 0:
    \\        return 3
    \\    return my_sum(n - 1)
    \\
    \\func mid(n: int) -> int:
    \\    return my_sum(n) + 1
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, pad(1), mid(7))
    \\    return 0
;

test "a function with a callee stays deferred after the callee's number moved" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]passes.Mode{ .trusted, .verify }) |mode| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
        defer storage.deinit();
        _ = try compileDemandGuarded(a, std.testing.allocator, chain_before, &storage, .{ .omit = false, .mode = mode, .stable_keys = true });
        const oracle = try compile(a, std.testing.allocator, chain_after, null, mode);
        const shifted = try compileDemandGuarded(a, std.testing.allocator, chain_after, &storage, .{ .omit = true, .mode = mode, .stable_keys = true });
        try equal(oracle, shifted.output);
        try std.testing.expect(shifted.output.statistics.bypassed >= 2);
        try std.testing.expect(shifted.output.statistics.bypassed >= 2);
    }
}

test "the demand shortcut reuses the entries of unchanged functions after the tables around them moved, matched by lowering key and stored by name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]passes.Mode{ .trusted, .verify }) |mode| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
        defer storage.deinit();
        _ = try compileDemandGuarded(a, std.testing.allocator, plain_before, &storage, .{ .omit = false, .mode = mode, .stable_keys = true });
        const oracle = try compile(a, std.testing.allocator, plain_after, null, mode);
        const shifted = try compileDemandGuarded(a, std.testing.allocator, plain_after, &storage, .{ .omit = true, .mode = mode, .stable_keys = true });
        try equal(oracle, shifted.output);
        // `leaf` and `sum` are unchanged and stay deferred (bypassed) though `main` now calls `pad` first and the function and
        // type tables are numbered otherwise.
        try std.testing.expect(shifted.output.statistics.bypassed >= 1);
        try std.testing.expect(shifted.omitted >= 1);
    }
}

/// `named_before` with `total` changed.
const named_changed =
    \\record Pair:
    \\    a: int
    \\    b: int
    \\
    \\record Twin:
    \\    a: int
    \\    b: int
    \\
    \\func total(p: Pair) -> int:
    \\    return p.a + p.b + 1
    \\
    \\func twin_total(t: Twin) -> int:
    \\    return t.a * t.b
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, total(Pair(a=1, b=2)), twin_total(Twin(a=1, b=2)))
    \\    return 0
;

test "a function whose text only moved is found by its lowering key without the source proof and keeps its rounds and effect, and a changed body does not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const shifted_text = try std.mem.concat(a, u8, &.{ "\n\n", named_before });
    const changed_text = try std.mem.concat(a, u8, &.{ "\n\n", named_changed });
    for ([_]passes.Mode{ .trusted, .verify }) |mode| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
        defer storage.deinit();
        _ = try compileDemandGuarded(a, std.testing.allocator, named_before, &storage, .{ .omit = false, .mode = mode, .stable_keys = true, .plain_keys = true });
        const shifted = try compileDemandGuarded(a, std.testing.allocator, shifted_text, &storage, .{ .omit = true, .mode = mode, .stable_keys = true, .plain_keys = true });
        try equal(try compile(a, std.testing.allocator, shifted_text, null, mode), shifted.output);
        // The line shift moves every position, so no function keeps the key it was lowered under, and none is deferred.
        try std.testing.expectEqual(@as(usize, 0), shifted.output.statistics.bypassed);
        try std.testing.expect(shifted.output.statistics.restores.rounds >= 4);
        try std.testing.expect(shifted.output.statistics.restores.effects >= 2);
        // `total` changed: it misses the lookup, and `main`, which calls it, loses what it would keep. `twin_total` keeps its own.
        const changed = try compileDemandGuarded(a, std.testing.allocator, changed_text, &storage, .{ .omit = true, .mode = mode, .stable_keys = true, .plain_keys = true });
        try equal(try compile(a, std.testing.allocator, changed_text, null, mode), changed.output);
        try std.testing.expect(changed.output.statistics.restores.rounds > 0);
        try std.testing.expect(changed.output.statistics.restores.rounds < shifted.output.statistics.restores.rounds);
        try std.testing.expect(changed.output.statistics.restores.effects < shifted.output.statistics.restores.effects);
    }
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand leaves identity raw and final bodies unloaded while preserving the eager oracle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const oracle = try compile(a, std.testing.allocator, basic, null, .verify);
    const cold = try compileDemand(a, std.testing.allocator, basic, &storage, false);
    const warm = try compileDemand(a, std.testing.allocator, basic, &storage, true);
    try equal(oracle, cold.output);
    try equal(oracle, warm.output);
    try std.testing.expect(warm.loaded < cold.loaded);
    try std.testing.expect(warm.omitted > 0);
    try std.testing.expectEqual(@as(usize, 0), warm.final_restored);
    try std.testing.expectEqual(@as(u32, 0), warm.emission.work.keys_built);
    try std.testing.expect(warm.emission.work.receipts_checked > 0);
    const edited = try fixture(a, .parameters, true);
    const changed = try compileDemand(a, std.testing.allocator, edited, &storage, true);
    const edited_oracle = try compile(a, std.testing.allocator, edited, null, .verify);
    try equal(edited_oracle, changed.output);
    for ([_]Scenario{ .callee, .parameters, .effects, .recursion }) |scenario| {
        const seed_text = try fixture(a, scenario, false);
        _ = try compileDemand(a, std.testing.allocator, seed_text, &storage, false);
        const seeded_warm = try compileDemand(a, std.testing.allocator, seed_text, &storage, true);
        try equal(try compile(a, std.testing.allocator, seed_text, null, .verify), seeded_warm.output);
        const changed_text = try fixture(a, scenario, true);
        const demand_changed = try compileDemand(a, std.testing.allocator, changed_text, &storage, true);
        const fresh_changed = try compile(a, std.testing.allocator, changed_text, null, .verify);
        try equal(fresh_changed, demand_changed.output);
    }
    const moved_text = try std.mem.concat(a, u8, &.{ "\n\n", basic });
    const moved = try compileDemand(a, std.testing.allocator, moved_text, &storage, true);
    try equal(try compile(a, std.testing.allocator, moved_text, null, .verify), moved.output);
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "restoreDeferredFinal rejects missing metadata and corrupted fact artifacts before changing a body" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, basic, &refusal);
    const token: u8 = 0;
    const locator: emit.Locator = .{ .context = &token, .locate = locate };
    const source_context = try snapshot.Context.init(a, &module, null);
    const raw_layout = try snapshot.layout(a, source_context);
    const count = module.functions.items.len;
    const keys = try a.alloc(?store.Digest, count);
    const loaded = try a.alloc(bool, count);
    const bodies = try a.alloc(snapshot.Wire, count);
    for (module.functions.items, bodies, keys, loaded) |function, *body, *key, *present| {
        body.* = try snapshot.capture(a, source_context, function);
        const digest = try snapshot.digest(a, source_context, function);
        key.* = storage.key("test-demand-lowering", &.{ &raw_layout, &digest });
        present.* = true;
    }
    var loader: DemandLoader = .{ .arena = a, .context = source_context, .bodies = bodies };
    var demand: demand_ir.Context = .{ .keys = keys, .loaded = loaded, .pointer = &loader, .ensure_fn = DemandLoader.ensure };
    var context = cache.Context.init(&storage, source_context, locator);
    context.lazy.raw = &demand;
    var table = try deferred.Table.init(a, count);
    var result = try passes.runCachedDeferred(a, std.testing.allocator, &module, .verify, &context, &table);
    const metadata = context.lazy.finals[0].?;
    const before = try print.module(a, &module);
    context.lazy.loaded[0] = false;
    context.lazy.finals[0] = null;
    try std.testing.expectError(error.CacheMiss, passes.restoreDeferredFinal(a, a, &context, 0, &result));
    try std.testing.expectEqualStrings(before, try print.module(a, &module));
    context.lazy.finals[0] = metadata;
    try std.testing.expect(try storage.save(context.factsKey(metadata.analysis.digest), "corrupt fact payload with a valid stage checksum"));
    try std.testing.expectError(error.CacheMiss, passes.restoreDeferredFinal(a, a, &context, 0, &result));
    try std.testing.expectEqualStrings(before, try print.module(a, &module));
    try std.testing.expect(!context.lazy.loaded[0]);
}

/// Whether `keys` hold `key`.
fn holdsKey(keys: []const store.Digest, key: store.Digest) bool {
    for (keys) |known| if (std.mem.eql(u8, &known, &key)) return true;
    return false;
}

test "a manifest saved by a build that bypasses a function keeps the fact payload its final body restores with among that build's roots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, root);
    defer storage.deinit();
    const analysis_digest: [32]u8 = @splat(7);
    const state: cache.FinalState = .{ .known = null, .plans = &.{}, .counts = .{}, .own = .{} };
    const metadata: cache.FinalMetadata = .{ .key = @splat(5), .body = .{ .positioned = @splat(1), .plain = @splat(2) }, .analysis = .{ .digest = analysis_digest, .loop_ids = &.{} }, .state = state };
    var entries = [_]shortcut_mod.Entry{.{ .demand = .{ .lowered = @splat(3), .metadata = metadata }, .final = @splat(4) }};
    // The build saves the manifest and neither loads nor saves the final or its payload: it bypassed the function.
    try shortcut_mod.storeDemandIndex(&storage, shortcut_mod.manifestKey(&storage, &.{ "", &.{0} }), .{ .entries = &entries, .catalog = .{} });
    const touched = try storage.touchedKeys(a);
    try std.testing.expect(holdsKey(touched, metadata.key));
    try std.testing.expect(holdsKey(touched, cache.factsRecordKey(&storage, analysis_digest)));
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand rejects a stale postfusion catalog guard and an eager recovery refreshes it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    _ = try compileDemand(a, std.testing.allocator, basic, &storage, false);
    const index_key = shortcut_mod.manifestKey(&storage, &.{ "", &.{@backingInt(passes.Mode.verify)} });
    var record = (try shortcut_mod.loadManifest(a, &storage, index_key)).?;
    record.catalog.layout.?[0] ^= 1;
    // The stage checksum is valid, but the independently checked final catalog
    // guard is stale. No deferred body may be used under this index.
    try shortcut_mod.storeManifest(&storage, index_key, record);
    try std.testing.expectError(error.CacheMiss, compileDemand(a, std.testing.allocator, basic, &storage, true));
    const oracle = try compile(a, std.testing.allocator, basic, null, .verify);
    const recovered = try compileDemandGuarded(a, std.testing.allocator, basic, &storage, .{ .omit = false, .force_eager = true });
    const repeated = try compileDemand(a, std.testing.allocator, basic, &storage, true);
    try equal(oracle, recovered.output);
    try equal(oracle, repeated.output);
    try std.testing.expectEqual(@as(u32, 0), repeated.emission.work.keys_built);
}

fn savedFusionIdentity(a: std.mem.Allocator, storage: *store.Store, text: []const u8, name: []const u8) !bool {
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a, text, &refusal);
    const saved = (try shortcut_mod.loadDemandIndex(a, storage, &.{ "", &.{@backingInt(passes.Mode.verify)} })) orelse return error.TestUnexpectedResult;
    for (module.functions.items, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, name)) return saved.entries[index].demand.fusion.identity;
    }
    return error.TestUnexpectedResult;
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand preserves known fusion identity only across matching lowering inputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const original =
        \\func borrow(s: str) -> bool:
        \\    return s == "x"
        \\func main() -> int:
        \\    if borrow("abc"):
        \\        return 1
        \\    return 0
    ;
    const fused =
        \\func borrow(s: str) -> bool:
        \\    return copy(strings.char_slice(s, 0, 1)) == "x"
        \\func main() -> int:
        \\    if borrow("abc"):
        \\        return 1
        \\    return 0
    ;
    _ = try compileDemand(a, std.testing.allocator, original, &storage, false);
    try std.testing.expect(try savedFusionIdentity(a, &storage, original, "borrow"));
    const changed = try compileDemand(a, std.testing.allocator, fused, &storage, true);
    try equal(try compile(a, std.testing.allocator, fused, null, .verify), changed.output);
    try std.testing.expect(!try savedFusionIdentity(a, &storage, fused, "borrow"));
    const warm = try compileDemand(a, std.testing.allocator, fused, &storage, true);
    try equal(changed.output, warm.output);
    try std.testing.expect(!try savedFusionIdentity(a, &storage, fused, "borrow"));
    const restored = try compileDemand(a, std.testing.allocator, original, &storage, true);
    try equal(try compile(a, std.testing.allocator, original, null, .verify), restored.output);
    try std.testing.expect(try savedFusionIdentity(a, &storage, original, "borrow"));
}

const checkpoint_leaf =
    \\func leaf(n: int) -> int:
    \\    return n % 17
    \\
;
const checkpoint_wrapper =
    \\func wrapper(n: int) -> int:
    \\    return leaf(n) + 3
    \\
;
const checkpoint_caller =
    \\func caller(n: int) -> int:
    \\    return wrapper(n % 100) + 1
    \\
;
const checkpoint_main =
    \\func main(out: Stream) -> int:
    \\    print(out, caller(7))
    \\    return 0
;

fn checkpointFixture(a: std.mem.Allocator, callee_first: bool) ![]const u8 {
    return std.mem.concat(a, u8, &.{ checkpoint_leaf, if (callee_first) checkpoint_wrapper else checkpoint_caller, if (callee_first) checkpoint_caller else checkpoint_wrapper, checkpoint_main });
}

fn savedCheckpoint(a: std.mem.Allocator, text: []const u8, storage: *store.Store, mode: passes.Mode, stage_index: usize) !?cache.Checkpoint {
    const saved = (try shortcut_mod.loadDemandIndex(a, storage, &.{ "", &.{@backingInt(mode)} })).?;
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a, text, &refusal);
    for (module.functions.items, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, "wrapper")) return saved.entries[index].demand.history.?.outputs[stage_index].?;
    }
    return null;
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand nonidentity checkpoints preserve physical caller order parameter demotion and eager output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const Case = struct { mode: passes.Mode, callee_first: bool };
    for ([_]Case{ .{ .mode = .verify, .callee_first = true }, .{ .mode = .verify, .callee_first = false }, .{ .mode = .trusted, .callee_first = true }, .{ .mode = .trusted, .callee_first = false } }) |scenario| {
        const mode = scenario.mode;
        const callee_first = scenario.callee_first;
        const text = try checkpointFixture(a, callee_first);
        const cold = try compileDemandGuarded(a, std.testing.allocator, text, &storage, .{ .omit = false, .mode = mode });
        const stage = (try savedCheckpoint(a, text, &storage, mode, 0)).?;
        try std.testing.expect(stage.changed > 0);
        const alias = (try savedCheckpoint(a, text, &storage, mode, 1)).?;
        const alias_value = (try storage.loadValue(a, alias.key, cache.Transform)).?;
        try std.testing.expectEqual(@as(u32, 0), alias.changed);
        try std.testing.expect(alias_value.function == null);
        try std.testing.expectEqualSlices(u8, &stage.output, &alias.output);
        const warm = try compileDemandGuarded(a, std.testing.allocator, text, &storage, .{ .omit = true, .mode = mode });
        try equal(try compile(a, std.testing.allocator, text, null, mode), warm.output);
        try std.testing.expect(warm.loaded < cold.loaded);
        try std.testing.expectEqual(@as(usize, 0), warm.final_restored);
        try std.testing.expectEqual(@as(usize, 0), warm.output.statistics.active_functions);
        // The unchanged transformed wrapper is inspected at different checkpoints
        // when the dirty caller occurs before versus after it in physical order.
        const dirty_caller = try std.mem.replaceOwned(u8, a, text, "+ 1", "+ 2");
        const edited = try compileDemandGuarded(a, std.testing.allocator, dirty_caller, &storage, .{ .omit = true, .mode = mode });
        try equal(try compile(a, std.testing.allocator, dirty_caller, null, mode), edited.output);
        try std.testing.expect(edited.output.statistics.restores.checkpoints > 0);
        // Incoming bounds change without changing wrapper's own lowering inputs.
        const dirty_parameters = try std.mem.replaceOwned(u8, a, dirty_caller, "% 100", "% 200");
        const demoted = try compileDemandGuarded(a, std.testing.allocator, dirty_parameters, &storage, .{ .omit = true, .mode = mode });
        try equal(try compile(a, std.testing.allocator, dirty_parameters, null, mode), demoted.output);
        const dirty_callee = try std.mem.replaceOwned(u8, a, dirty_parameters, "% 17", "% 19");
        const invalidated = try compileDemandGuarded(a, std.testing.allocator, dirty_callee, &storage, .{ .omit = true, .mode = mode });
        try equal(try compile(a, std.testing.allocator, dirty_callee, null, mode), invalidated.output);
    }
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand missing nonidentity checkpoint falls back and eager recovery refreshes handles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const text = try checkpointFixture(a, true);
    _ = try compileDemand(a, std.testing.allocator, text, &storage, false);
    const stage = (try savedCheckpoint(a, text, &storage, .verify, 0)).?;
    try stage_loss.remove(a, &storage, stage.key);
    const edited = try std.mem.replaceOwned(u8, a, text, "+ 1", "+ 2");
    try std.testing.expectError(error.CacheMiss, compileDemand(a, std.testing.allocator, edited, &storage, true));
    const recovered = try compileDemandGuarded(a, std.testing.allocator, edited, &storage, .{ .omit = false, .force_eager = true });
    try equal(try compile(a, std.testing.allocator, edited, null, .verify), recovered.output);
    const warm = try compileDemand(a, std.testing.allocator, edited, &storage, true);
    try equal(recovered.output, warm.output);
    try std.testing.expectEqual(@as(usize, 0), warm.output.statistics.active_functions);
    // Successful repaired receipts must not invoke the deferred fallback again.
    try std.testing.expectEqual(@as(usize, 0), warm.final_restored);
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand rejects checksummed identity alias ancestry corruption before using a deferred callee" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const text = try checkpointFixture(a, false);
    _ = try compileDemand(a, std.testing.allocator, text, &storage, false);
    const alias = (try savedCheckpoint(a, text, &storage, .verify, 1)).?;
    var value = (try storage.loadValue(a, alias.key, cache.Transform)).?;
    try std.testing.expect(value.function == null);
    value.provenance.present = !value.provenance.present;
    try storage.storeValue(alias.key, cache.Transform, value);
    const edited = try std.mem.replaceOwned(u8, a, text, "+ 1", "+ 2");
    try std.testing.expectError(error.CacheMiss, compileDemand(a, std.testing.allocator, edited, &storage, true));
    try stage_loss.remove(a, &storage, alias.key);
    const repaired = try compileDemandGuarded(a, std.testing.allocator, edited, &storage, .{ .omit = false, .force_eager = true });
    try equal(try compile(a, std.testing.allocator, edited, null, .verify), repaired.output);
}

const checkpoint_printing =
    \\func leaf(n: int) -> int:
    \\    return n % 17
    \\
    \\func wrapper(out: Stream, n: int) -> int:
    \\    print(out, leaf(n))
    \\    return n + 1
    \\
    \\func caller(out: Stream, n: int) -> int:
    \\    return wrapper(out, n % 100) + 1
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, caller(out, 7))
    \\    return 0
;

fn savedWrapperParameters(a: std.mem.Allocator, text: []const u8, storage: *store.Store, mode: passes.Mode) !?[]const ?facts.Interval {
    const saved = (try shortcut_mod.loadDemandIndex(a, storage, &.{ "", &.{@backingInt(mode)} })).?;
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a, text, &refusal);
    for (module.functions.items, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, "wrapper")) return saved.entries[index].parameters;
    }
    return null;
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand demotes a transformed printing callee when only incoming bounds change" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    for ([_]passes.Mode{ .verify, .trusted }) |mode| {
        _ = try compileDemandGuarded(a, std.testing.allocator, checkpoint_printing, &storage, .{ .omit = false, .mode = mode });
        const before = (try savedWrapperParameters(a, checkpoint_printing, &storage, mode)).?;
        try std.testing.expect(before[1] != null);
        const warm = try compileDemandGuarded(a, std.testing.allocator, checkpoint_printing, &storage, .{ .omit = true, .mode = mode });
        try std.testing.expectEqual(@as(usize, 0), warm.output.statistics.active_functions);
        const edited = try std.mem.replaceOwned(u8, a, checkpoint_printing, "% 100", "% 200");
        const demoted = try compileDemandGuarded(a, std.testing.allocator, edited, &storage, .{ .omit = true, .mode = mode });
        const after = (try savedWrapperParameters(a, edited, &storage, mode)).?;
        try std.testing.expect(after[1] != null);
        try std.testing.expect(!std.meta.eql(before[1], after[1]));
        try std.testing.expect(demoted.output.statistics.restores.checkpoints > 0);
        const oracle = try compile(a, std.testing.allocator, edited, null, mode);
        try equal(oracle, demoted.output);
        try std.testing.expectEqualDeep(oracle.ancestry, demoted.output.ancestry);
    }
}

const checkpoint_looping =
    \\func origin(mut xs: int[], n: int, kind: int) -> int:
    \\    append(mut xs, 2)
    \\    mut total = 0
    \\    for i in range(n):
    \\        if kind == 0:
    \\            total += xs[i]
    \\        else:
    \\            total += xs[i] + 1
    \\    return total
    \\
    \\func wrapper(out: Stream, n: int, kind: int) -> int:
    \\    print(out, 1)
    \\    mut xs = [1]
    \\    return origin(mut xs, n, kind)
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, wrapper(out, 3, 1))
    \\    return 0
;

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand reuses nonidentity CFG and unswitch checkpoints with exact loop ancestry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    for ([_]passes.Mode{ .verify, .trusted }) |mode| {
        _ = try compileDemandGuarded(a, std.testing.allocator, checkpoint_looping, &storage, .{ .omit = false, .mode = mode });
        const cfg = (try savedCheckpoint(a, checkpoint_looping, &storage, mode, 1)).?;
        const unswitch = (try savedCheckpoint(a, checkpoint_looping, &storage, mode, 2)).?;
        try std.testing.expect(cfg.changed > 0);
        try std.testing.expect(unswitch.changed > 0);
        const warm = try compileDemandGuarded(a, std.testing.allocator, checkpoint_looping, &storage, .{ .omit = true, .mode = mode });
        try equal(try compile(a, std.testing.allocator, checkpoint_looping, null, mode), warm.output);
        try std.testing.expectEqual(@as(usize, 0), warm.output.statistics.active_functions);
        const edited = try std.mem.replaceOwned(u8, a, checkpoint_looping, "wrapper(out, 3, 1)", "wrapper(out, 3, 2)");
        const demoted = try compileDemandGuarded(a, std.testing.allocator, edited, &storage, .{ .omit = true, .mode = mode });
        try std.testing.expect(demoted.output.statistics.restores.checkpoints > 0);
        try equal(try compile(a, std.testing.allocator, edited, null, mode), demoted.output);
        const moved = try std.mem.concat(a, u8, &.{ "\n\n", edited });
        const relocated = try compileDemandGuarded(a, std.testing.allocator, moved, &storage, .{ .omit = true, .mode = mode });
        try equal(try compile(a, std.testing.allocator, moved, null, mode), relocated.output);
    }
}

// A writer with no call edge to reader still changes reader's global field facts.
// spec-case: NEW-CORE-F2-FIELD-1
test "optimizer demand field summaries retain warm bodies and invalidate unrelated writer bounds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const before =
        \\record State:
        \\    x: int
        \\
        \\func writer() -> State:
        \\    return State(x=7)
        \\
        \\func reader(s: State) -> int:
        \\    return s.x + 1
        \\
        \\func idle() -> int:
        \\    return 42
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, reader(State(x=3)), idle(), writer().x)
        \\    return 0
    ;
    const after = try std.mem.replaceOwned(u8, a, before, "State(x=7)", "State(x=9)");
    for ([_]passes.Mode{ .verify, .trusted }) |mode| {
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
        defer storage.deinit();
        const oracle = try compile(a, std.testing.allocator, before, null, mode);
        const cold = try compileDemandGuarded(a, std.testing.allocator, before, &storage, .{ .mode = mode, .omit = false });
        const warm = try compileDemandGuarded(a, std.testing.allocator, before, &storage, .{ .mode = mode, .omit = true });
        try equal(oracle, cold.output);
        try equal(oracle, warm.output);
        try std.testing.expect(warm.loaded < cold.loaded);
        try std.testing.expect(warm.omitted > 0);
        const edited_oracle = try compile(a, std.testing.allocator, after, null, mode);
        const edited = try compileDemandGuarded(a, std.testing.allocator, after, &storage, .{ .mode = mode, .omit = true });
        try equal(edited_oracle, edited.output);
        try std.testing.expect(edited.output.statistics.restores.checkpoints > 0);
        const repaired_warm = try compileDemandGuarded(a, std.testing.allocator, after, &storage, .{ .mode = mode, .omit = true });
        try equal(edited_oracle, repaired_warm.output);
        try std.testing.expect(repaired_warm.loaded < edited.loaded);
    }
}

// spec-case: NEW-CORE-F2-FIELD-1
test "field summaries sparse contributions match original dense hulls for writes reachability opening operations and escaped functions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ir = @import("ir.zig");
    const Builder = @import("test_builder.zig").Builder;
    var module: ir.Module = .{};
    const record = try module.intern(a, .{ .record = &.{.i64} });
    const escaped = try module.intern(a, .{ .record = &.{ .i64, .bool } });
    const outside = try module.intern(a, .{ .record = &.{ .i64, .i64 } });
    const list = try module.intern(a, .{ .list = record });
    const array = try module.intern(a, .{ .array = .{ .elem = .i64, .n = 2 } });
    const callback = try module.intern(a, .{ .@"fn" = .{ .params = &.{escaped}, .ret = .i64 } });
    const parsed = try module.option(a, .i64);
    try module.strings.append(a, "7");
    var b: Builder = .{ .arena = a, .function = .{ .name = "writer", .signature = .{ .params = &.{}, .ret = .void } } };
    const live = try b.block();
    const dead = try b.block();
    const zero = try b.constant(.u64, 0);
    const three = try b.constant(.i64, 3);
    const seven = try b.constant(.i64, 7);
    const nine = try b.constant(.i64, 9);
    const ignored = try b.constant(.i64, 99);
    _ = try b.put(live, .{ .op = .record_make, .ty = array, .data = try b.extra(&.{ three, seven }) });
    const made = try b.put(live, .{ .op = .record_make, .ty = record, .data = try b.extra(&.{three}) });
    const changed = try b.put(live, .{ .op = .record_set, .ty = record, .a = made, .b = seven, .data = 0 });
    const empty = try b.put(live, .{ .op = .list_new, .ty = list, .a = zero });
    const filled = try b.put(live, .{ .op = .list_push, .ty = list, .a = empty, .b = changed });
    const path = try b.constant(.u64, @bitCast(ir.FieldPath.init(&.{0}).?.pack()));
    _ = try b.put(live, .{ .op = .list_set_field, .ty = list, .a = filled, .b = zero, .data = try b.extra(&.{ nine, path }) });
    _ = try b.put(live, .{ .op = .func_ref, .ty = callback, .data = 1 });
    const text = try b.put(live, .{ .op = .str_const, .ty = .str, .data = 0 });
    _ = try b.put(live, .{ .op = .str_parse_int, .ty = parsed, .a = text });
    _ = try b.put(live, .{ .op = .ret, .ty = .void });
    _ = try b.put(dead, .{ .op = .record_make, .ty = record, .data = try b.extra(&.{ignored}) });
    _ = try b.put(dead, .{ .op = .ret, .ty = .void });
    try module.functions.append(a, b.function);
    var callback_body: Builder = .{ .arena = a, .function = .{ .name = "callback", .signature = .{ .params = &.{escaped}, .ret = .i64 } } };
    const home = try callback_body.block();
    _ = try callback_body.put(home, .{ .op = .ret, .ty = .void, .a = try callback_body.constant(.i64, 0) });
    try module.functions.append(a, callback_body.function);
    try module.functions.append(a, .{ .name = "external", .signature = .{ .params = &.{outside}, .ret = outside, .linkage = .extern_c } });
    const evidence = try fieldOracleEvidence(a, &module);
    const known = evidence.known;
    const compact = evidence.compact;
    try std.testing.expect(!known[0].?.reachable[dead.index()]);
    try std.testing.expect(compact[0].?.valid(&module));
    try std.testing.expectEqual(@as(usize, 3), compact[0].?.writes.len);
    try std.testing.expect(compact[0].?.opens.len > 0);
    try std.testing.expectEqual(@as(usize, 1), compact[0].?.references.len);
    const closed = try fields.closedTypes(a, &module);
    for ([_]bool{ false, true }) |sabotage| {
        const dense = try fields.hulls(a, &module, known, closed, sabotage);
        const sparse = try fields.fromContributions(a, &module, compact, sabotage);
        try std.testing.expectEqualDeep(dense.types, sparse.types);
        const bound = sparse.get(record, 0).?;
        try std.testing.expectEqual(@as(i128, 3), bound.lo);
        try std.testing.expectEqual(@as(i128, if (sabotage) 8 else 9), bound.hi);
        try std.testing.expect(sparse.table(escaped) == null);
        try std.testing.expect(sparse.table(outside) == null);
    }
}

const FieldOracleEvidence = struct {
    known: []?facts.Facts,
    compact: []?fields.Contribution,
};

fn fieldOracleEvidence(a: std.mem.Allocator, module: *@import("ir.zig").Module) std.mem.Allocator.Error!FieldOracleEvidence {
    const known = try a.alloc(?facts.Facts, module.functions.items.len);
    const compact = try a.alloc(?fields.Contribution, known.len);
    @memset(known, null);
    @memset(compact, null);
    for (module.functions.items, known, compact) |*function, *facts_slot, *evidence| {
        if (function.signature.linkage != .internal) continue;
        facts_slot.* = try facts.analyze(a, function, .{ .mark = false });
        evidence.* = try fields.contribution(a, module, function, &facts_slot.*.?);
    }
    return .{ .known = known, .compact = compact };
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand field summaries ignore fusion runtime entries and retain spectator final bodies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const before =
        \\record State:
        \\    x: int
        \\func borrow(s: str) -> bool:
        \\    return copy(strings.char_slice(s, 0, 1)) == "x"
        \\func reader(s: State) -> int:
        \\    return s.x + 1
        \\func idle() -> int:
        \\    return 42
        \\func main(out: Stream) -> int:
        \\    print(out, reader(State(x=3)), idle(), borrow("abc"))
        \\    return 0
    ;
    const after = try std.mem.replaceOwned(u8, a, before, "borrow(\"abc\")", "borrow(\"abd\")");
    const oracle = try compile(a, std.testing.allocator, before, null, .verify);
    const cold = try compileDemand(a, std.testing.allocator, before, &storage, false);
    try equal(oracle, cold.output);
    const saved = (try shortcut_mod.loadDemandIndex(a, &storage, &.{ "", &.{@backingInt(passes.Mode.verify)} })).?;
    var refusal: build.Refusal = .{};
    const raw = try support.buildSource(a, before, &refusal);
    try std.testing.expect(saved.entries.len > raw.functions.items.len);
    const warm = try compileDemand(a, std.testing.allocator, before, &storage, true);
    try equal(oracle, warm.output);
    try std.testing.expect(warm.output.statistics.bypassed > 0);
    try std.testing.expect(deferredName(warm, "idle"));
    try std.testing.expectEqual(warm.omitted, warm.deferred_functions.len);
    const edited = try compileDemand(a, std.testing.allocator, after, &storage, true);
    try equal(try compile(a, std.testing.allocator, after, null, .verify), edited.output);
    try std.testing.expect(edited.output.statistics.bypassed > 0);
    try std.testing.expect(deferredName(edited, "idle"));
    try std.testing.expectEqual(edited.omitted, edited.deferred_functions.len);
    const eager_cold = try compile(a, std.testing.allocator, before, &storage, .verify);
    const eager_warm = try compile(a, std.testing.allocator, before, &storage, .verify);
    try equal(oracle, eager_cold);
    try equal(oracle, eager_warm);
    try std.testing.expect(eager_warm.statistics.bypassed > 0);
}

fn deferredName(value: DemandProduced, name: []const u8) bool {
    for (value.deferred_functions) |function| if (std.mem.eql(u8, function, name)) return true;
    return false;
}

const fusion_fixture =
    \\func main(out: Stream) -> int:
    \\    print(out, keep_slice("abc"), borrow("abc"), idle())
    \\    return 0
    \\func keep_slice(s: str) -> str:
    \\    return strings.char_slice(s, 0, 1)
    \\func borrow(s: str) -> bool:
    \\    return copy(strings.char_slice(s, 0, 1)) == "x"
    \\func idle() -> int:
    \\    return 42
;

fn fusionEntry(a: std.mem.Allocator, storage: *store.Store, text: []const u8) !?shortcut_mod.Entry {
    const saved = (try shortcut_mod.loadDemandIndex(a, storage, &.{ "", &.{@backingInt(passes.Mode.verify)} })).?;
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a, text, &refusal);
    for (module.functions.items, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, "borrow")) return saved.entries[index];
    }
    return null;
}

const c5_trim_demand =
    \\import bytes
    \\import strings
    \\
    \\func text_read(text: str) -> bool:
    \\    return strings.lstrip_chars(text, "0") == "120"
    \\func bytes_read(data: bytes) -> bool:
    \\    return bytes.rstrip_chars(data, b"0") == b"abc"
    \\func owned_text(text: str) -> str:
    \\    return strings.strip_chars(text, "0")
    \\func main(out: Stream) -> int:
    \\    if text_read("000120") and bytes_read(b"abc000"):
    \\        print(out, owned_text("001200"))
    \\        return 0
    \\    return 1
;

fn c5TrimCatalog(a: std.mem.Allocator, storage: *store.Store, mode: passes.Mode) !void {
    const saved = (try shortcut_mod.loadDemandIndex(a, storage, &.{ "", &.{@backingInt(mode)} })).?;
    var text_seen = false;
    var bytes_seen = false;
    for (saved.catalog.declarations) |declaration| {
        const text = std.mem.eql(u8, declaration.name, "myl_core_span_text_trim_view");
        const bytes = std.mem.eql(u8, declaration.name, "myl_core_span_bytes_trim_view");
        if (!text and !bytes) continue;
        const signature = declaration.signature;
        try std.testing.expectEqual(.runtime_c, signature.linkage);
        try std.testing.expectEqual(@as(u64, 3), signature.passing.views);
        try std.testing.expect(!signature.passing.hasOwned());
        try std.testing.expect(!signature.passing.hasConsumes());
        try std.testing.expect(signature.viewSource() != null and signature.viewSource().? == 0);
        text_seen = text_seen or text;
        bytes_seen = bytes_seen or bytes;
    }
    try std.testing.expect(text_seen);
    try std.testing.expect(bytes_seen);
}

test "C5 trim demand runtime helpers preserve cold warm dirty and eager cache parity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    inline for (.{ passes.Mode.trusted, passes.Mode.verify }) |mode| {
        var directory = std.testing.tmpDir(.{});
        defer directory.cleanup();
        var storage = try store.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
        defer storage.deinit();
        const eager = try compile(a, std.testing.allocator, c5_trim_demand, null, mode);
        const cold = try compileDemandGuarded(a, std.testing.allocator, c5_trim_demand, &storage, .{ .omit = false, .mode = mode });
        const warm = try compileDemandGuarded(a, std.testing.allocator, c5_trim_demand, &storage, .{ .omit = true, .mode = mode });
        try equal(eager, cold.output);
        try equal(eager, warm.output);
        try std.testing.expect(warm.loaded < cold.loaded);
        try c5TrimCatalog(a, &storage, mode);
        const changed = try std.mem.replaceOwned(u8, a, c5_trim_demand, "120", "240");
        const dirty = try compileDemandGuarded(a, std.testing.allocator, changed, &storage, .{ .omit = true, .mode = mode });
        try equal(try compile(a, std.testing.allocator, changed, null, mode), dirty.output);
        const repeated = try compileDemandGuarded(a, std.testing.allocator, changed, &storage, .{ .omit = true, .mode = mode });
        try equal(dirty.output, repeated.output);
        const restored = try compileDemandGuarded(a, std.testing.allocator, c5_trim_demand, &storage, .{ .omit = true, .mode = mode });
        try equal(eager, restored.output);
    }
}

fn damageFusionLiteral(wire: *snapshot.Wire) bool {
    for (wire.function.insts) |*inst| {
        if (inst.op != .iconst) continue;
        inst.data ^= 1;
        return true;
    }
    return false;
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand fused base rejects checksummed changed instructions and missing snapshots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const cold = try compileDemand(a, std.testing.allocator, fusion_fixture, &storage, false);
    const warm = try compileDemand(a, std.testing.allocator, fusion_fixture, &storage, true);
    try equal(cold.output, warm.output);
    try std.testing.expect(warm.loaded < cold.loaded);
    const changed = try std.mem.replaceOwned(u8, a, fusion_fixture, "abc", "abd");
    const edited = try compileDemand(a, std.testing.allocator, changed, &storage, true);
    try equal(try compile(a, std.testing.allocator, changed, null, .verify), edited.output);
    try std.testing.expect(edited.output.statistics.restores.fusions > 0);
    const entry = (try fusionEntry(a, &storage, changed)).?;
    try std.testing.expect(!entry.demand.fusion.identity);
    const key = entry.demand.fusion.key.?;
    var wire = (try storage.loadValue(a, key, snapshot.Wire)).?;
    try std.testing.expect(damageFusionLiteral(&wire));
    try storage.storeValue(key, snapshot.Wire, wire);
    const inspect_corrupted = try std.mem.replaceOwned(u8, a, fusion_fixture, "abc", "abe");
    try std.testing.expectError(error.CacheMiss, compileDemand(a, std.testing.allocator, inspect_corrupted, &storage, true));
    const repaired = try compileDemandGuarded(a, std.testing.allocator, fusion_fixture, &storage, .{ .omit = false, .force_eager = true });
    try equal(cold.output, repaired.output);
    const repaired_entry = (try fusionEntry(a, &storage, fusion_fixture)).?;
    try stage_loss.remove(a, &storage, repaired_entry.demand.fusion.key.?);
    const inspect_missing = try std.mem.replaceOwned(u8, a, fusion_fixture, "abc", "abf");
    try std.testing.expectError(error.CacheMiss, compileDemand(a, std.testing.allocator, inspect_missing, &storage, true));
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand changed fusion helper inventory retries with exact eager declaration catalog" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    _ = try compileDemand(a, std.testing.allocator, fusion_fixture, &storage, false);
    const changed = try std.mem.replaceOwned(u8, a, fusion_fixture, "copy(strings.char_slice(s, 0, 1)) == \"x\"", "copy(s) == \"x\"");
    var refusal: build.Refusal = .{};
    var original_raw = try support.buildSource(a, fusion_fixture, &refusal);
    var changed_raw = try support.buildSource(a, changed, &refusal);
    try std.testing.expectEqual(original_raw.functions.items.len, changed_raw.functions.items.len);
    const original_layout = try snapshot.layout(a, try snapshot.Context.init(a, &original_raw, null));
    const changed_layout = try snapshot.layout(a, try snapshot.Context.init(a, &changed_raw, null));
    try std.testing.expectEqual(original_layout, changed_layout);
    // The saved declarations replay into the changed module, because its raw layout is the one they were
    // saved for: the warm compile is a hit, and its output is the eager oracle's (lane C-c: the compare
    // in `borrow` lowers as the same span form on both sides, so the inventories agree).
    const hit = try compileDemand(a, std.testing.allocator, changed, &storage, true);
    try equal(try compile(a, std.testing.allocator, changed, null, .verify), hit.output);
    const repaired = try compileDemandGuarded(a, std.testing.allocator, changed, &storage, .{ .omit = false, .force_eager = true });
    const oracle = try compile(a, std.testing.allocator, changed, null, .verify);
    try equal(oracle, repaired.output);
    const saved = (try shortcut_mod.loadDemandIndex(a, &storage, &.{ "", &.{@backingInt(passes.Mode.verify)} })).?;
    // The exact eager catalog holds the one runtime helper this compare's span form needs (`myl_core_span_eq`);
    // the old fixture needed none, because its slice compare was not a span (lane C-c, D7).
    try std.testing.expectEqual(@as(usize, 1), saved.catalog.declarations.len);
    try std.testing.expectEqualStrings("myl_core_span_eq", saved.catalog.declarations[0].name);
    const warm = try compileDemand(a, std.testing.allocator, changed, &storage, true);
    try equal(oracle, warm.output);
    try std.testing.expect(warm.output.statistics.bypassed > 0);
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand field summaries ignore FixedArray producers and preserve deferred record spectators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const text =
        \\record State:
        \\    x: int
        \\func pair() -> FixedArray[int, 2]:
        \\    return FixedArray[int, 2]([7, 9])
        \\func idle() -> int:
        \\    return 42
        \\func reader(s: State) -> int:
        \\    return s.x + 1
        \\func main(out: Stream) -> int:
        \\    print(out, pair()[0], reader(State(x=3)), idle())
        \\    return 0
    ;
    const cold = try compileDemand(a, std.testing.allocator, text, &storage, false);
    const warm = try compileDemand(a, std.testing.allocator, text, &storage, true);
    try equal(try compile(a, std.testing.allocator, text, null, .verify), cold.output);
    try equal(cold.output, warm.output);
    try std.testing.expect(warm.output.statistics.bypassed > 0);
    try std.testing.expect(deferredName(warm, "idle"));
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, text, &refusal);
    const evidence = try fieldOracleEvidence(a, &module);
    const closed = try fields.closedTypes(a, &module);
    const dense = try fields.hulls(a, &module, evidence.known, closed, false);
    const sparse = try fields.fromContributions(a, &module, evidence.compact, false);
    try std.testing.expectEqualDeep(dense.types, sparse.types);
    try validFieldEvidence(&module, evidence.compact);
}

fn validFieldEvidence(module: *const @import("ir.zig").Module, compact: []const ?fields.Contribution) error{TestUnexpectedResult}!void {
    for (compact) |entry| if (entry) |value| try std.testing.expect(value.valid(module));
}

fn literalLess(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.order(u8, left, right) == .lt;
}

fn canonicalCore(a: std.mem.Allocator, module: *const @import("ir.zig").Module) std.mem.Allocator.Error![]const u8 {
    const ir = @import("ir.zig");
    const literals = try usedLiteralValues(a, module);
    std.mem.sort([]const u8, literals, {}, literalLess);
    var unique: std.ArrayList([]const u8) = .empty;
    var slots: std.StringHashMapUnmanaged(u64) = .empty;
    defer slots.deinit(a);
    for (literals) |literal| {
        if (slots.contains(literal)) continue;
        try slots.put(a, literal, unique.items.len);
        try unique.append(a, literal);
    }
    var canonical = module.*;
    canonical.strings = unique;
    canonical.functions.items = try a.dupe(ir.Function, module.functions.items);
    for (canonical.functions.items) |*function| {
        function.insts.items = try a.dupe(ir.Inst, function.insts.items);
        for (function.insts.items) |*inst| {
            const original = literalSlot(inst.*) orelse continue;
            const slot = slots.get(module.strings.items[@intCast(original)]).?;
            inst.data = if (inst.op == .str_const) slot else (inst.data & 0xffffffff00000000) | slot;
        }
    }
    var values = @import("selka").persist_codec.Writer.init(a);
    defer values.deinit();
    try values.write([]const []const u8, unique.items);
    return std.mem.concat(a, u8, &.{ try print.module(a, &canonical), "\ncanonical literal bytes\n", values.bytes.items });
}

fn literalSlot(inst: @import("ir.zig").Inst) ?u64 {
    if (inst.op == .str_const) return inst.data;
    if (inst.op == .@"unreachable" and inst.data & @import("flags.zig").assertion_trap != 0) return @as(u32, @truncate(inst.data));
    return null;
}

fn usedLiteralValues(a: std.mem.Allocator, module: *const @import("ir.zig").Module) std.mem.Allocator.Error![][]const u8 {
    var values: std.ArrayList([]const u8) = .empty;
    for (module.functions.items) |function| for (function.insts.items) |inst| {
        const slot = literalSlot(inst) orelse continue;
        try values.append(a, module.strings.items[@intCast(slot)]);
    };
    return values.items;
}

const creation_fixture =
    \\import strings
    \\
    \\func probe(s: str) -> bool:
    \\    mut first = strings.char_slice(s, 0, 1)
    \\    mut second = strings.char_slice(s, 1, 2)
    \\    mut equal = second == "x"
    \\    mut counted = strings.char_count(first)
    \\    if len(s) > 99:
    \\        first = copy(s)
    \\        second = copy(s)
    \\    return equal or counted == 1
    \\func idle() -> int:
    \\    return 42
    \\func main(out: Stream) -> int:
    \\    print(out, probe("abc"), idle())
    \\    return 0
;

fn creationProbe(a: std.mem.Allocator, module: *@import("ir.zig").Module) ![]const u32 {
    _ = try @import("fuse_slice_key.zig").run(a, module);
    for (module.functions.items) |*function| {
        if (std.mem.eql(u8, function.name, "main::probe")) return shortcut_mod.Index.targetsOf(a, function, .call);
    }
    return error.TestUnexpectedResult;
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand fusion declaration requests reject producer reordering despite unchanged downstream helper calls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    _ = try compileDemand(a, std.testing.allocator, creation_fixture, &storage, false);
    const prior = (try shortcut_mod.loadDemandIndex(a, &storage, &.{ "", &.{@backingInt(passes.Mode.verify)} })).?;
    try std.testing.expectEqual(@as(usize, 2), prior.catalog.declarations.len);
    const changed = try std.mem.replaceOwned(
        u8,
        a,
        creation_fixture,
        "    mut first = strings.char_slice(s, 0, 1)\n    mut second = strings.char_slice(s, 1, 2)",
        "    mut second = strings.char_slice(s, 1, 2)\n    mut first = strings.char_slice(s, 0, 1)",
    );
    var refusal: build.Refusal = .{};
    var original_raw = try support.projectModule(a, creation_fixture, &refusal);
    var changed_raw = try support.projectModule(a, changed, &refusal);
    const original_layout = try snapshot.layout(a, try snapshot.Context.init(a, &original_raw, null));
    const changed_layout = try snapshot.layout(a, try snapshot.Context.init(a, &changed_raw, null));
    try std.testing.expectEqual(original_layout, changed_layout);
    try @import("fusion_checkpoint.zig").seed(a, &original_raw, prior.catalog);
    try @import("fusion_checkpoint.zig").seed(a, &changed_raw, prior.catalog);
    try std.testing.expectEqualSlices(u32, try creationProbe(a, &original_raw), try creationProbe(a, &changed_raw));
    try std.testing.expectError(error.CacheMiss, compileDemand(a, std.testing.allocator, changed, &storage, true));
    const repaired = try compileDemandGuarded(a, std.testing.allocator, changed, &storage, .{ .omit = false, .force_eager = true });
    try equal(try compile(a, std.testing.allocator, changed, null, .verify), repaired.output);
    const next = (try shortcut_mod.loadDemandIndex(a, &storage, &.{ "", &.{@backingInt(passes.Mode.verify)} })).?;
    try std.testing.expect(!std.mem.eql(u8, prior.catalog.declarations[0].name, next.catalog.declarations[0].name));
    try equal(repaired.output, (try compileDemand(a, std.testing.allocator, changed, &storage, true)).output);
}

const field_cycle_fixture =
    \\record State:
    \\    x: int
    \\func entry(out: Stream, n: int):
    \\    print(out, left(n), right(n))
    \\func left(n: int) -> int:
    \\    if n <= 0:
    \\        return 0
    \\    return right(n - 1) % 3
    \\func right(n: int) -> int:
    \\    if n <= 0:
    \\        return 0
    \\    return left(n - 1) % 7
    \\func spectator(s: State) -> int:
    \\    return s.x + 1
    \\func main(out: Stream) -> int:
    \\    mut left_ref = left
    \\    mut right_ref = right
    \\    entry(out, 5)
    \\    print(out, spectator(State(x=3)))
    \\    return 0
;

fn checkSummaryCycle(a: std.mem.Allocator, backing: std.mem.Allocator, mode: passes.Mode, text: []const u8) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try store.Store.init(backing, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const cold = try compileDemandGuarded(a, backing, text, &storage, .{ .mode = mode, .omit = false });
    const warm = try compileDemandGuarded(a, backing, text, &storage, .{ .mode = mode, .omit = true });
    try equal(cold.output, warm.output);
    try std.testing.expect(deferredName(warm, "left"));
    try std.testing.expect(warm.loaded < cold.loaded);
    try std.testing.expect(warm.output.statistics.bypassed > 0);
    const changed = try std.mem.replaceOwned(u8, a, text, "print(out, left(n), right(n))", "print(out, right(n), left(n))");
    var refusal: build.Refusal = .{};
    var original_raw = try support.buildSource(a, text, &refusal);
    var changed_raw = try support.buildSource(a, changed, &refusal);
    try std.testing.expectEqual(
        try snapshot.layout(a, try snapshot.Context.init(a, &original_raw, null)),
        try snapshot.layout(a, try snapshot.Context.init(a, &changed_raw, null)),
    );
    const edited = try compileDemandGuarded(a, backing, changed, &storage, .{ .mode = mode, .omit = true });
    const oracle = try compile(a, backing, changed, null, mode);
    try equal(oracle, edited.output);
    try std.testing.expect(edited.output.statistics.restores.checkpoints > 0);
    const repaired = try compileDemandGuarded(a, backing, changed, &storage, .{ .mode = mode, .omit = true });
    try equal(oracle, repaired.output);
    try std.testing.expect(repaired.output.statistics.bypassed > 0);
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand field receipts reuse recursive cycles and reject changed exploration entry return inputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for ([_]passes.Mode{ .verify, .trusted }) |mode| try checkSummaryCycle(arena.allocator(), std.testing.allocator, mode, field_cycle_fixture);
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand ordered return input receipts preserve record and record-free self recursion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    _ = try compileDemand(a, std.testing.allocator, recursive, &storage, false);
    const conservative = try compileDemand(a, std.testing.allocator, recursive, &storage, true);
    try equal(try compile(a, std.testing.allocator, recursive, null, .verify), conservative.output);
    try std.testing.expect(deferredName(conservative, "recurse"));
    const records = try std.mem.concat(a, u8, &.{ "record State:\n    x: int\n", recursive });
    const with_field = try std.mem.replaceOwned(u8, a, records, "print(out, recurse(7), idle())", "print(out, State(x=3).x, recurse(7), idle())");
    _ = try compileDemand(a, std.testing.allocator, with_field, &storage, false);
    const proven = try compileDemand(a, std.testing.allocator, with_field, &storage, true);
    try equal(try compile(a, std.testing.allocator, with_field, null, .verify), proven.output);
    try std.testing.expect(deferredName(proven, "recurse"));
    try std.testing.expectEqual(@as(usize, 0), proven.loaded);
    try std.testing.expectEqual(@as(usize, 0), conservative.loaded);
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand record-free summary receipts reject changed recursive traversal return inputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const without_record = try std.mem.replaceOwned(u8, a, field_cycle_fixture, "record State:\n    x: int\n", "");
    const integer_argument = try std.mem.replaceOwned(u8, a, without_record, "s: State", "s: int");
    const integer_body = try std.mem.replaceOwned(u8, a, integer_argument, "return s.x + 1", "return s + 1");
    const text = try std.mem.replaceOwned(u8, a, integer_body, "spectator(State(x=3))", "spectator(3)");
    for ([_]passes.Mode{ .verify, .trusted }) |mode| try checkSummaryCycle(a, std.testing.allocator, mode, text);
}

fn removeSummaryReceipt(a: std.mem.Allocator, storage: *store.Store, text: []const u8, name: []const u8) !void {
    const saved = (try shortcut_mod.loadDemandIndex(a, storage, &.{ "", &.{@backingInt(passes.Mode.verify)} })).?;
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a, text, &refusal);
    for (module.functions.items, saved.entries) |function, *entry| {
        if (std.mem.eql(u8, function.name, name)) entry.summary_input = null;
    }
    try shortcut_mod.storeDemandIndex(storage, shortcut_mod.manifestKey(storage, &.{ "", &.{@backingInt(passes.Mode.verify)} }), saved);
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand missing record-free summary input receipt restores recursive bodies and repairs admission" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const cold = try compileDemand(a, std.testing.allocator, recursive, &storage, false);
    const warm = try compileDemand(a, std.testing.allocator, recursive, &storage, true);
    try std.testing.expect(deferredName(warm, "recurse"));
    try removeSummaryReceipt(a, &storage, recursive, "recurse");
    const recovered = try compileDemand(a, std.testing.allocator, recursive, &storage, true);
    try equal(cold.output, recovered.output);
    try std.testing.expect(!deferredName(recovered, "recurse"));
    try std.testing.expect(recovered.loaded > warm.loaded);
    const repaired = try compileDemand(a, std.testing.allocator, recursive, &storage, true);
    try equal(cold.output, repaired.output);
    try std.testing.expect(deferredName(repaired, "recurse"));
}

const split_catalog_fixture =
    \\import strings
    \\
    \\func indexed(s: str, at: int) -> int:
    \\    mut parts = strings.split(s, ",")
    \\    return strings.char_count(parts[at]) + len(parts)
    \\func prefix(s: str) -> int:
    \\    mut parts = strings.split(s, ",")
    \\    return strings.char_count(parts[1])
    \\func count_pair(s: str) -> int:
    \\    return len(strings.split(s, ",")) + len(strings.split(s, "|"))
    \\func lazy(s: str, separator: str) -> int:
    \\    mut n = 0
    \\    for part in strings.split(s, separator):
    \\        n += strings.char_count(part)
    \\    return n
    \\func idle() -> int:
    \\    return 42
    \\func main(out: Stream) -> int:
    \\    print(out, indexed("a|b,c|d", 1), prefix("a,b"), count_pair("a|b,c|d"), lazy("a,b", ","), idle())
    \\    return 0
;

const whitespace_catalog_fixture =
    \\import dicts
    \\import strings
    \\
    \\func words(s: str) -> dict[str, int]:
    \\    mut counts: dict[str, int] = {}
    \\    for word in strings.words(s):
    \\        counts[copy(word)] = dicts.get(counts, word, 0) + 1
    \\    return counts
    \\func idle() -> int:
    \\    return 42
    \\func main(out: Stream) -> int:
    \\    mut counts = words("a b a")
    \\    print(out, counts["a"], idle())
    \\    return 0
;

/// Cold and warm demand builds of a program that splits match the uncached oracle. The shortcut
/// may defer other bodies, but never one that calls a split (`splitters`): split fusions read it.
fn checkSplitDemand(backing: std.mem.Allocator, text: []const u8, mode: passes.Mode, splitters: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try store.Store.init(backing, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const oracle = try compile(a, backing, text, null, mode);
    const cold = try compileDemandGuarded(a, backing, text, &storage, .{ .omit = false, .mode = mode });
    const warm = try compileDemandGuarded(a, backing, text, &storage, .{ .omit = true, .mode = mode });
    try equal(oracle, cold.output);
    try equal(oracle, warm.output);
    try std.testing.expect(warm.loaded <= cold.loaded);
    for (splitters) |name| try std.testing.expect(!deferredName(warm, name));
    try std.testing.expect(total(&warm.output.statistics.hits) > 0);
}

// spec-case: NEW-CORE-STAGE-CACHE-8
// spec-case: NEW-CORE-S2-SPLIT-2
test "RP3 cache integration split catalogs preserve compound offsets prefixes duplicate counts and lazy loops across cold and warm caches" {
    const splitters = [_][]const u8{ "main::indexed", "main::prefix", "main::count_pair", "main::lazy" };
    try checkSplitDemand(std.testing.allocator, split_catalog_fixture, .verify, &splitters);
    try checkSplitDemand(std.testing.allocator, split_catalog_fixture, .trusted, &splitters);
}

// spec-case: NEW-CORE-STAGE-CACHE-8
// spec-case: NEW-CORE-S2-SPLIT-3
test "RP3 cache integration whitespace only catalogs retain probe once insertion with ordinary stage cache reuse" {
    try checkSplitDemand(std.testing.allocator, whitespace_catalog_fixture, .verify, &.{"main::words"});
    try checkSplitDemand(std.testing.allocator, whitespace_catalog_fixture, .trusted, &.{"main::words"});
}

const split_creation_fixture =
    \\import strings
    \\
    \\func ordered(s: str) -> int:
    \\    mut first = strings.split(s, ",")
    \\    mut second = strings.split(s, "|")
    \\    return strings.char_count(first[0]) + strings.char_count(second[1])
    \\func spectator(s: str) -> int:
    \\    return strings.char_count(strings.split(s, ",")[0])
    \\func idle() -> int:
    \\    return 42
    \\func main(out: Stream) -> int:
    \\    print(out, ordered("a|b,c|d"), spectator("a,b"), idle())
    \\    return 0
;

fn splitCreationNames(a: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var refusal: build.Refusal = .{};
    var module = try support.projectModule(a, text, &refusal);
    const count = module.functions.items.len;
    try @import("fuse_text.zig").whitespace(a, &module);
    try @import("split_views.zig").run(a, &module);
    var names: std.ArrayList([]const u8) = .empty;
    for (module.functions.items[count..]) |function| {
        if (std.mem.startsWith(u8, function.name, "myl_core_span_split_prefix_")) try names.append(a, function.name);
    }
    return names.items;
}

fn checkSplitCreation(backing: std.mem.Allocator, mode: passes.Mode) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try store.Store.init(backing, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const changed = try std.mem.replaceOwned(u8, a, split_creation_fixture, "strings.char_count(first[0]) + strings.char_count(second[1])", "strings.char_count(first[1]) + strings.char_count(second[0])");
    const before_names = try splitCreationNames(a, split_creation_fixture);
    const after_names = try splitCreationNames(a, changed);
    try std.testing.expectEqual(@as(usize, 2), before_names.len);
    try std.testing.expectEqual(@as(usize, 2), after_names.len);
    try std.testing.expectEqualStrings("myl_core_span_split_prefix_1", before_names[0]);
    try std.testing.expectEqualStrings("myl_core_span_split_prefix_2", before_names[1]);
    try std.testing.expectEqualStrings(before_names[1], after_names[0]);
    try std.testing.expectEqualStrings(before_names[0], after_names[1]);
    var refusal: build.Refusal = .{};
    var before_raw = try support.projectModule(a, split_creation_fixture, &refusal);
    var after_raw = try support.projectModule(a, changed, &refusal);
    try std.testing.expectEqual(try snapshot.layout(a, try snapshot.Context.init(a, &before_raw, null)), try snapshot.layout(a, try snapshot.Context.init(a, &after_raw, null)));
    const cold = try compileDemandGuarded(a, backing, split_creation_fixture, &storage, .{ .omit = false, .mode = mode });
    const prior = try compileDemandGuarded(a, backing, split_creation_fixture, &storage, .{ .omit = true, .mode = mode });
    try equal(cold.output, prior.output);
    const oracle = try compile(a, backing, changed, null, mode);
    const edited = try compileDemandGuarded(a, backing, changed, &storage, .{ .omit = true, .mode = mode });
    const repeated = try compileDemandGuarded(a, backing, changed, &storage, .{ .omit = true, .mode = mode });
    try equal(oracle, edited.output);
    try equal(oracle, repeated.output);
    try std.testing.expectEqual(cold.loaded, edited.loaded);
    try std.testing.expectEqual(@as(usize, 0), edited.omitted);
    try std.testing.expect(total(&repeated.output.statistics.hits) > 0);
}

// spec-case: NEW-CORE-STAGE-CACHE-8
// spec-case: NEW-CORE-S2-SPLIT-2
test "RP3 cache integration dirty split producers reorder helpers exactly while unchanged spectators remain correct" {
    try checkSplitCreation(std.testing.allocator, .verify);
    try checkSplitCreation(std.testing.allocator, .trusted);
}

const bytes_demand_fixture =
    \\func borrow(s: bytes) -> bool:
    \\    return s[0:1] == b"x"
    \\func idle() -> int:
    \\    return 42
    \\func main(out: Stream) -> int:
    \\    print(out, borrow(b"abc"), idle())
    \\    return 0
;

fn checkByteDemand(backing: std.mem.Allocator, mode: passes.Mode) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try store.Store.init(backing, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const oracle = try compile(a, backing, bytes_demand_fixture, null, mode);
    const cold = try compileDemandGuarded(a, backing, bytes_demand_fixture, &storage, .{ .omit = false, .mode = mode });
    const warm = try compileDemandGuarded(a, backing, bytes_demand_fixture, &storage, .{ .omit = true, .mode = mode });
    try equal(oracle, cold.output);
    try equal(oracle, warm.output);
    try std.testing.expect(warm.loaded < cold.loaded);
    try std.testing.expect(deferredName(warm, "idle"));
    const changed = try std.mem.replaceOwned(u8, a, bytes_demand_fixture, "abc", "abd");
    const edited = try compileDemandGuarded(a, backing, changed, &storage, .{ .omit = true, .mode = mode });
    const repeated = try compileDemandGuarded(a, backing, changed, &storage, .{ .omit = true, .mode = mode });
    const changed_oracle = try compile(a, backing, changed, null, mode);
    try equal(changed_oracle, edited.output);
    try equal(changed_oracle, repeated.output);
    try std.testing.expect(deferredName(edited, "idle"));
}

// spec-case: NEW-CORE-STAGE-CACHE-8
// spec-case: NEW-CORE-S2-VIEW-1
test "RP3 cache integration byte views retain demand checkpoint reuse and dirty caller equality" {
    try checkByteDemand(std.testing.allocator, .verify);
    try checkByteDemand(std.testing.allocator, .trusted);
}

const array_only =
    \\func my_sum() -> int:
    \\    mut xs = FixedArray[int, 5]([0, 1, 2, 3, 4])
    \\    xs[2] = -7
    \\    return xs[3]
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, my_sum())
    \\    return 0
;

fn expectArrayOnly(backing: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    const module = try support.buildSource(a, array_only, &refusal);
    var found_array = false;
    for (module.compounds.items) |compound| {
        try std.testing.expect(compound != .record);
        found_array = found_array or compound == .array;
    }
    try std.testing.expect(found_array);
}

fn expectArrayHulls(value: Produced) !void {
    var literal = false;
    var updated = false;
    for (value.result.known) |optional| if (optional) |known| {
        for (known.aggregates.lists) |aggregate| {
            const length = aggregate.len orelse continue;
            if (length.lo != 5 or length.hi != 5) continue;
            const elements = aggregate.elements orelse continue;
            literal = literal or std.meta.eql(elements, facts.Interval{ .lo = 0, .hi = 4 });
            updated = updated or std.meta.eql(elements, facts.Interval{ .lo = -7, .hi = 4 });
        }
    };
    try std.testing.expect(literal);
    try std.testing.expect(updated);
}

// spec-case: NEW-CORE-R-ARRAY-2
test "R array-only modules preserve literal and update facts through deferred cold and warm caches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    try expectArrayOnly(std.testing.allocator);
    const oracle = try compile(a, std.testing.allocator, array_only, null, .trusted);
    try expectArrayHulls(oracle);
    try std.testing.expect(std.mem.indexOf(u8, oracle.llvm, "icmp uge i64") == null);
    const cold = try compileDeferred(a, std.testing.allocator, array_only, &storage);
    const warm = try compileDeferred(a, std.testing.allocator, array_only, &storage);
    try equal(oracle, cold.output);
    try equal(oracle, warm.output);
    try std.testing.expect(total(&warm.output.statistics.hits) > 0);
    try std.testing.expectEqual(@as(usize, 0), total(&warm.output.statistics.misses));
    const demand_cold = try compileDemandGuarded(a, std.testing.allocator, array_only, &storage, .{ .mode = .trusted, .omit = false });
    const demand_warm = try compileDemandGuarded(a, std.testing.allocator, array_only, &storage, .{ .mode = .trusted, .omit = true });
    try equal(oracle, demand_cold.output);
    try equal(oracle, demand_warm.output);
    try std.testing.expect(demand_warm.omitted > 0);
    try std.testing.expectEqual(@as(usize, 0), demand_warm.final_restored);
    try std.testing.expectEqual(@as(u32, 0), demand_warm.emission.work.keys_built);
}

// spec-case: NEW-CORE-R-ARRAY-2
test "R cached array-only verify builds restore bounds checks while retaining the same array hulls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const oracle = try compile(a, std.testing.allocator, array_only, null, .verify);
    try expectArrayHulls(oracle);
    try std.testing.expect(std.mem.indexOf(u8, oracle.llvm, "icmp uge i64") != null);
    const cold = try compile(a, std.testing.allocator, array_only, &storage, .verify);
    const warm = try compile(a, std.testing.allocator, array_only, &storage, .verify);
    try equal(oracle, cold);
    try equal(oracle, warm);
    try std.testing.expect(total(&warm.statistics.hits) > 0);
    try std.testing.expectEqual(@as(usize, 0), total(&warm.statistics.misses));
    const demand_cold = try compileDemandGuarded(a, std.testing.allocator, array_only, &storage, .{ .mode = .verify, .omit = false });
    const demand_warm = try compileDemandGuarded(a, std.testing.allocator, array_only, &storage, .{ .mode = .verify, .omit = true });
    try equal(oracle, demand_cold.output);
    try equal(oracle, demand_warm.output);
    try std.testing.expect(demand_warm.omitted > 0);
    try std.testing.expectEqual(@as(usize, 0), demand_warm.final_restored);
    try std.testing.expectEqual(@as(u32, 0), demand_warm.emission.work.keys_built);
}

const split_shortcut_fixture =
    \\import strings
    \\
    \\func words(s: str) -> int:
    \\    return len(strings.split(s, " "))
    \\func commas(s: str) -> int:
    \\    return len(strings.split(s, ","))
    \\func scale(n: int) -> int:
    \\    return n * 2 + 1
    \\func total(n: int) -> int:
    \\    mut t = 0
    \\    for i in range(n):
    \\        t = t + scale(i)
    \\    return t
    \\func idle() -> int:
    \\    return 42
    \\func main(out: Stream) -> int:
    \\    print(out, words("a b c"), commas("a,b"), total(4), idle())
    \\    return 0
;

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand shortcut defers bodies of a program that splits, except the split's callers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const oracle = try compile(a, std.testing.allocator, split_shortcut_fixture, null, .verify);
    try equal(oracle, (try compileDemand(a, std.testing.allocator, split_shortcut_fixture, &storage, false)).output);
    const warm = try compileDemand(a, std.testing.allocator, split_shortcut_fixture, &storage, true);
    try equal(oracle, warm.output);
    try std.testing.expect(warm.output.statistics.bypassed > 0);
    try std.testing.expect(deferredName(warm, "main::idle"));
    try std.testing.expect(deferredName(warm, "main::scale"));
    // The split's fusions must see its callers' bodies, and `main` inlines them. Both count-only splits
    // share one count helper, so the seeded catalog replays exactly.
    try std.testing.expect(!deferredName(warm, "main::words"));
    try std.testing.expect(!deferredName(warm, "main::commas"));
    // `main` inlines them, yet it stays deferred: their results did not change, so nothing `main` reads did (the early cutoff).
    try std.testing.expect(deferredName(warm, "main::main"));
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "optimizer demand shortcut keeps an unchanged function deferred after an unrelated edit and re-runs a changed callee's callers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    _ = try compileDemand(a, std.testing.allocator, split_shortcut_fixture, &storage, false);
    _ = try compileDemand(a, std.testing.allocator, split_shortcut_fixture, &storage, true);
    // An edit to `words` leaves `scale`, `total` and `idle` alone.
    const unrelated = try std.mem.replaceOwned(u8, a, split_shortcut_fixture, "s, \" \"", "s, \",\"");
    const edited = try compileDemand(a, std.testing.allocator, unrelated, &storage, true);
    try equal(try compile(a, std.testing.allocator, unrelated, null, .verify), edited.output);
    try std.testing.expect(edited.output.statistics.bypassed > 0);
    try std.testing.expect(deferredName(edited, "main::idle"));
    try std.testing.expect(deferredName(edited, "main::scale"));
    try std.testing.expect(deferredName(edited, "main::total"));
    // A changed callee: `total` inlines `scale`, so it is not deferred, and its output matches the oracle.
    const callee = try std.mem.replaceOwned(u8, a, unrelated, "n * 2 + 1", "n * 2 + 3");
    const changed = try compileDemand(a, std.testing.allocator, callee, &storage, true);
    try equal(try compile(a, std.testing.allocator, callee, null, .verify), changed.output);
    try std.testing.expect(!deferredName(changed, "main::scale"));
    try std.testing.expect(!deferredName(changed, "main::total"));
    try std.testing.expect(deferredName(changed, "main::idle"));
}

test "the optimizer cache names the source locator directly: it is the type the emitter re-exports" {
    try std.testing.expect(@import("emit_llvm.zig").Locator == @import("source_location.zig").Locator);
    try std.testing.expect(@import("emit_llvm.zig").Location == @import("source_location.zig").Location);
}

/// A chain `main -> c2 -> c1 -> f` whose `f` has a loop (so it is not inlined) and returns `total % 3`; `c2` branches on what `c1`
/// returns, so a return interval that reaches it changes the code the facts fold.
const cutoff_interval_chain =
    \\func f(n: int) -> int:
    \\    mut total = 0
    \\    for i in range(n):
    \\        total += i
    \\    return total % 3
    \\
    \\func c1(n: int) -> int:
    \\    return f(n) + 1
    \\
    \\func c2(n: int) -> int:
    \\    if c1(n) > 3:
    \\        return 1
    \\    return 0
    \\
    \\func idle() -> int:
    \\    return 42
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, c2(7), idle())
    \\    return 0
;
/// The chain with a recursive `f`, which no stage inlines: an edit to `f` that changes none of its results reaches only `c1`.
const cutoff_recursive_chain =
    \\func f(n: int) -> int:
    \\    if n <= 0:
    \\        return 3
    \\    return f(n - 1)
    \\
    \\func c1(n: int) -> int:
    \\    return f(n) + 1
    \\
    \\func c2(n: int) -> int:
    \\    return c1(n) + c1(n + 1)
    \\
    \\func idle() -> int:
    \\    return 42
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, c2(7), idle())
    \\    return 0
;
/// The same chain with a leaf `f`, which the inlining puts into `c1` and then `c1` into `c2`.
const cutoff_inline_chain =
    \\func f(n: int) -> int:
    \\    return n % 3
    \\
    \\func c1(n: int) -> int:
    \\    return f(n) % 7
    \\
    \\func c2(n: int) -> int:
    \\    return c1(n) % 11
    \\
    \\func idle() -> int:
    \\    return 42
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, c2(7), idle())
    \\    return 0
;
/// A chain of writers: `mutate`'s effect names the field it writes, and `m2` is two callers away.
const cutoff_effect_chain =
    \\record State:
    \\    x: int
    \\    y: int
    \\
    \\func mutate(mut s: State, n: int):
    \\    if n > 0:
    \\        s.x = s.x + 1
    \\        mutate(mut s, n - 1)
    \\
    \\func m1(mut s: State, n: int):
    \\    mutate(mut s, n)
    \\
    \\func m2(mut s: State, n: int):
    \\    m1(mut s, n)
    \\    m1(mut s, n + 1)
    \\
    \\func idle() -> int:
    \\    return 42
    \\
    \\func main(out: Stream) -> int:
    \\    mut s = State(x=0, y=0)
    \\    m2(mut s, 3)
    \\    print(out, s.x, s.y, idle())
    \\    return 0
;

/// Build `before`, then `before` again with its bodies deferred, then the edit of it, with the cutoff on: the edit's build must
/// equal the eager build of the edited program. Returns the edit's build.
fn cutoffEdit(a: std.mem.Allocator, backing: std.mem.Allocator, before: []const u8, edit: struct { from: []const u8, to: []const u8, cutoff: @import("optimizer_cutoff.zig").Mode = .cutoff }, mode: passes.Mode) !DemandProduced {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(backing, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    _ = try compileDemandGuarded(a, backing, before, &storage, .{ .omit = false, .mode = mode, .cutoff = edit.cutoff });
    _ = try compileDemandGuarded(a, backing, before, &storage, .{ .omit = true, .mode = mode, .cutoff = edit.cutoff });
    const after = try std.mem.replaceOwned(u8, a, before, edit.from, edit.to);
    const edited = try compileDemandGuarded(a, backing, after, &storage, .{ .omit = true, .mode = mode, .cutoff = edit.cutoff });
    try equal(try compile(a, backing, after, null, mode), edited.output);
    return edited;
}

test "a callee change that alters the return interval a caller two levels up reads recomputes that caller" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const edited = try cutoffEdit(a, std.testing.allocator, cutoff_interval_chain, .{ .from = "total % 3", .to = "total % 5" }, .trusted);
    try std.testing.expect(!deferredName(edited, "c2"));
    try std.testing.expect(deferredName(edited, "idle"));
}

test "a callee change that alters the checkpoints of its callers reaches the caller two levels up" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const edited = try cutoffEdit(a, std.testing.allocator, cutoff_inline_chain, .{ .from = "n % 3", .to = "n % 5" }, .trusted);
    try std.testing.expect(!deferredName(edited, "c1"));
    try std.testing.expect(!deferredName(edited, "c2"));
    try std.testing.expect(deferredName(edited, "idle"));
}

test "a callee change that alters the effect a caller two levels up reads recomputes that caller" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const edited = try cutoffEdit(a, std.testing.allocator, cutoff_effect_chain, .{ .from = "s.x = s.x + 1", .to = "s.y = s.y + 1" }, .trusted);
    try std.testing.expect(!deferredName(edited, "m2"));
}

test "a callee change that alters nothing its callers read leaves the caller two levels up deferred" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const edited = try cutoffEdit(a, std.testing.allocator, cutoff_recursive_chain, .{ .from = "return 3", .to = "return 5" }, .trusted);
    try std.testing.expect(!deferredName(edited, "f"));
    try std.testing.expect(deferredName(edited, "c2"));
    try std.testing.expect(deferredName(edited, "idle"));
    try std.testing.expect(edited.output.statistics.restores.cutoff.demoted > 0 or !deferredName(edited, "c1"));
}

test "the verify mode derives each deferred function that reads a recomputed one afresh and finds the cutoff missed nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const interval = try cutoffEdit(a, std.testing.allocator, cutoff_interval_chain, .{ .from = "total % 3", .to = "total % 5", .cutoff = .verify }, .trusted);
    const inline_chain = try cutoffEdit(a, std.testing.allocator, cutoff_inline_chain, .{ .from = "n % 3", .to = "n % 5", .cutoff = .verify }, .trusted);
    const effect = try cutoffEdit(a, std.testing.allocator, cutoff_effect_chain, .{ .from = "s.x = s.x + 1", .to = "s.y = s.y + 1", .cutoff = .verify }, .trusted);
    const same = try cutoffEdit(a, std.testing.allocator, cutoff_recursive_chain, .{ .from = "return 3", .to = "return 5", .cutoff = .verify }, .trusted);
    try std.testing.expectEqual(@as(usize, 0), interval.output.statistics.restores.cutoff.findings + inline_chain.output.statistics.restores.cutoff.findings);
    try std.testing.expectEqual(@as(usize, 0), effect.output.statistics.restores.cutoff.findings + same.output.statistics.restores.cutoff.findings);
    try std.testing.expect(same.output.statistics.restores.cutoff.demoted > 0);
}

test "an edit that contributes what its function contributed before takes the stored joins, and one that changes a return interval takes the full field rounds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const same = try cutoffEdit(a, std.testing.allocator, cutoff_effect_chain, .{ .from = "func idle() -> int:\n    return 42", .to = "func idle() -> int:\n    _ = 7\n    return 42" }, .trusted);
    const moved = try cutoffEdit(a, std.testing.allocator, cutoff_effect_chain, .{ .from = "return 42", .to = "return 43" }, .trusted);
    try std.testing.expectEqual(@as(usize, 1), same.output.statistics.restores.cutoff.joined);
    try std.testing.expectEqual(@as(usize, 0), same.output.statistics.restores.cutoff.rejoined);
    try std.testing.expectEqual(@as(usize, 0), moved.output.statistics.restores.cutoff.joined);
    try std.testing.expectEqual(@as(usize, 1), moved.output.statistics.restores.cutoff.rejoined);
    try std.testing.expect(deferredName(same, "m2"));
    // The rest of a row is read for the functions that were recomputed and the ones they were compared with, not for the others.
    try std.testing.expect(same.output.statistics.restores.cutoff.settled < moved.output.statistics.restores.cutoff.settled);
}

test "the verify mode finds the stored joins right for an edit that contributes what it did before, and for one that does not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const same = try cutoffEdit(a, std.testing.allocator, cutoff_effect_chain, .{ .from = "func idle() -> int:\n    return 42", .to = "func idle() -> int:\n    _ = 7\n    return 42", .cutoff = .verify }, .trusted);
    const moved = try cutoffEdit(a, std.testing.allocator, cutoff_effect_chain, .{ .from = "return 42", .to = "return 43", .cutoff = .verify }, .trusted);
    try std.testing.expectEqual(@as(usize, 0), same.output.statistics.restores.cutoff.findings + moved.output.statistics.restores.cutoff.findings);
    try std.testing.expectEqual(@as(usize, 0), same.output.statistics.restores.cutoff.joined);
}

test "a build of an unchanged program reads the rest of no row, and the verify mode finds the rows it left unread right" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    _ = try compileDemandGuarded(a, std.testing.allocator, cutoff_effect_chain, &storage, .{ .omit = false, .mode = .trusted });
    const again = try compileDemandGuarded(a, std.testing.allocator, cutoff_effect_chain, &storage, .{ .omit = true, .mode = .trusted });
    const verified = try compileDemandGuarded(a, std.testing.allocator, cutoff_effect_chain, &storage, .{ .omit = true, .mode = .trusted, .cutoff = .verify });
    try std.testing.expectEqual(@as(usize, 0), again.output.statistics.restores.cutoff.settled);
    try std.testing.expectEqual(@as(usize, 1), again.output.statistics.restores.cutoff.joined);
    try std.testing.expectEqual(@as(usize, 0), verified.output.statistics.restores.cutoff.findings);
    try std.testing.expect(deferredName(again, "m2") and deferredName(again, "idle") and deferredName(verified, "m2"));
}

/// A program of `count` small functions over one record, so that the functions of its one module fall into several chunks.
fn wideProgram(a: std.mem.Allocator, count: usize) ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(a, "record State:\n    x: int\n    y: int\n\n");
    for (0..count) |i| try text.print(a, "func w{d}(mut s: State, n: int) -> int:\n    s.x = s.x + {d}\n    return n + {d}\n\n", .{ i, i + 1, i % 5 });
    try text.appendSlice(a, "func main(out: Stream) -> int:\n    mut s = State(x=0, y=0)\n    mut total = 0\n");
    for (0..count) |i| try text.print(a, "    total = total + w{d}(mut s, {d})\n", .{ i, i });
    try text.appendSlice(a, "    print(out, total, s.x)\n    return 0\n");
    return text.items;
}

test "a program whose functions span many chunks takes the stored joins for an edit that contributes what it did, and its rows read as the eager build's" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try wideProgram(a, 40);
    const edited = try cutoffEdit(a, std.testing.allocator, program, .{ .from = "func w17(mut s: State, n: int) -> int:\n", .to = "func w17(mut s: State, n: int) -> int:\n    _ = 3\n" }, .trusted);
    try std.testing.expectEqual(@as(usize, 1), edited.output.statistics.restores.cutoff.joined);
    try std.testing.expect(edited.output.statistics.restores.cutoff.settled < 20);
}

test "an edit, its undoing and another edit each take the stored joins when the recomputed functions contribute what they did" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try wideProgram(a, 40);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    _ = try compileDemandGuarded(a, std.testing.allocator, program, &storage, .{ .omit = false, .mode = .trusted });
    _ = try compileDemandGuarded(a, std.testing.allocator, program, &storage, .{ .omit = true, .mode = .trusted });
    const head = "func w17(mut s: State, n: int) -> int:\n";
    const first = try std.mem.replaceOwned(u8, a, program, head, head ++ "    _ = 3\n");
    const second = try std.mem.replaceOwned(u8, a, program, head, head ++ "    _ = 4\n");
    const edit_one = try compileDemandGuarded(a, std.testing.allocator, first, &storage, .{ .omit = true, .mode = .trusted });
    const undone = try compileDemandGuarded(a, std.testing.allocator, program, &storage, .{ .omit = true, .mode = .trusted });
    const edit_two = try compileDemandGuarded(a, std.testing.allocator, second, &storage, .{ .omit = true, .mode = .trusted });
    try std.testing.expectEqual(@as(usize, 1), edit_one.output.statistics.restores.cutoff.joined);
    try std.testing.expectEqual(@as(usize, 1), undone.output.statistics.restores.cutoff.joined);
    try std.testing.expectEqual(@as(usize, 1), edit_two.output.statistics.restores.cutoff.joined);
}

test "deferred functions found in two manifests take the stored joins of the one that holds most, comparing the others with its rows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try wideProgram(a, 40);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const head = "func w17(mut s: State, n: int) -> int:\n";
    const first = try std.mem.replaceOwned(u8, a, program, head, head ++ "    _ = 3\n");
    const second = try std.mem.replaceOwned(u8, a, program, head, head ++ "    _ = 4\n");
    // Generation 1 is the program, generation 2 the program with its first edit; the second edit then reads generation 1 (the first was
    // undone) with generation 2 as the last full build: the functions after the edited one moved a line in both edits.
    storage.generations = .{ .read = 0, .write = 1, .last = 0 };
    _ = try compileDemandGuarded(a, std.testing.allocator, program, &storage, .{ .omit = false, .mode = .trusted });
    storage.generations = .{ .read = 1, .write = 2, .last = 1 };
    _ = try compileDemandGuarded(a, std.testing.allocator, first, &storage, .{ .omit = true, .mode = .trusted });
    storage.generations = .{ .read = 1, .write = 3, .last = 2 };
    const edited = try compileDemandGuarded(a, std.testing.allocator, second, &storage, .{ .omit = true, .mode = .trusted });
    try equal(try compile(a, std.testing.allocator, second, null, .trusted), edited.output);
    try std.testing.expectEqual(@as(usize, 1), edited.output.statistics.restores.cutoff.joined);
    storage.generations = .{ .read = 1, .write = 4, .last = 3 };
    const verified = try compileDemandGuarded(a, std.testing.allocator, second, &storage, .{ .omit = true, .mode = .trusted, .cutoff = .verify });
    try std.testing.expectEqual(@as(usize, 0), verified.output.statistics.restores.cutoff.findings);
}

/// Callers before a hub that a comment then moves: `c1` calls `rec`, which no stage inlines, and `c2` calls `leaf`, which the leaf stage
/// inlines. `rec` and `leaf` come after the point where the edit adds text; every caller comes before it.
const shifted_hub =
    \\func c1(n: int) -> int:
    \\    return rec(n) + 1
    \\
    \\func c2(n: int) -> int:
    \\    return leaf(n) % 7
    \\
    \\func c3(n: int) -> int:
    \\    return c2(n) % 11
    \\
    \\func idle() -> int:
    \\    return 42
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, c1(7), c3(7), idle())
    \\    return 0
    \\
    \\func rec(n: int) -> int:
    \\    if n <= 0:
    \\        return 3
    \\    return rec(n - 1)
    \\
    \\func leaf(n: int) -> int:
    \\    return n % 3
;

/// Build `before`, then `before` with its bodies deferred, then the edit of it, with every function keyed by its body alone and found again
/// by that key without its positions: the shape of a comment added above some functions. The edit's build must equal the eager build.
fn shiftedEdit(a: std.mem.Allocator, backing: std.mem.Allocator, edit: struct { from: []const u8, to: []const u8, cutoff: @import("optimizer_cutoff.zig").Mode = .cutoff, again: ?[]const u8 = null }) !DemandProduced {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try store.Store.init(backing, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const settings: DemandSettings = .{ .omit = false, .mode = .trusted, .stable_keys = true, .plain_keys = true, .cutoff = edit.cutoff };
    _ = try compileDemandGuarded(a, backing, shifted_hub, &storage, settings);
    var deferred_settings = settings;
    deferred_settings.omit = true;
    _ = try compileDemandGuarded(a, backing, shifted_hub, &storage, deferred_settings);
    var after = try std.mem.replaceOwned(u8, a, shifted_hub, edit.from, edit.to);
    var edited = try compileDemandGuarded(a, backing, after, &storage, deferred_settings);
    try equal(try compile(a, backing, after, null, .trusted), edited.output);
    // The functions the first edit recomputed were stored with the plain digests of their checkpoints: a second comment above them moves them again.
    if (edit.again) |more| {
        after = try std.mem.replaceOwned(u8, a, after, edit.to, more);
        edited = try compileDemandGuarded(a, backing, after, &storage, deferred_settings);
        try equal(try compile(a, backing, after, null, .trusted), edited.output);
    }
    return edited;
}

test "a callee that only moved leaves a caller that did not inline it deferred, and recomputes one that did, with the result of the eager build" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const edited = try shiftedEdit(a, std.testing.allocator, .{ .from = "func rec(n: int)", .to = "# moved\nfunc rec(n: int)" });
    // `rec` and `leaf` moved eight bytes. `c1` reads `rec` and inlines nothing of it; `c2` inlines `leaf`, whose positions its body now carries.
    try std.testing.expect(deferredName(edited, "c1"));
    try std.testing.expect(!deferredName(edited, "c2"));
    try std.testing.expect(deferredName(edited, "idle"));
    try std.testing.expect(edited.output.statistics.restores.cutoff.shifted > 0);
    // `c3` inlined `c2`, which was recomputed with other positions in its body, so it is recomputed too.
    try std.testing.expect(!deferredName(edited, "c3"));
    // The rule before the cutoff recomputes every caller of a function that moved, and builds the same program.
    const oracle = try shiftedEdit(a, std.testing.allocator, .{ .from = "func rec(n: int)", .to = "# moved\nfunc rec(n: int)", .cutoff = .transitive });
    try std.testing.expect(!deferredName(oracle, "c1"));
    try std.testing.expectEqualStrings(edited.output.llvm, oracle.output.llvm);
}

test "a second comment above the callee that only moved leaves the same callers deferred, by the plain digests the first edit stored" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const edited = try shiftedEdit(a, std.testing.allocator, .{ .from = "func rec(n: int)", .to = "# moved\nfunc rec(n: int)", .again = "# moved twice, further\nfunc rec(n: int)" });
    try std.testing.expect(deferredName(edited, "c1"));
    try std.testing.expect(!deferredName(edited, "c2"));
    try std.testing.expect(edited.output.statistics.restores.cutoff.shifted > 0);
}

test "the verify mode runs the stage afresh for a deferred function that read a callee which only moved and finds its result the entry's" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const edited = try shiftedEdit(a, std.testing.allocator, .{ .from = "func rec(n: int)", .to = "# moved\nfunc rec(n: int)", .cutoff = .verify });
    try std.testing.expectEqual(@as(usize, 0), edited.output.statistics.restores.cutoff.findings);
    try std.testing.expect(edited.output.statistics.restores.cutoff.shifted > 0);
}

test "an ancestry that differs only in the positions of its call sites is equal without them, and names the functions it inlined" {
    const here: cache.Provenance = .{
        .frames = &.{.{ .function = 7, .call = .{ .offset = 0, .point = .{ .line = 3, .column = 5 } }, .parent = null }},
        .blocks = &.{},
        .instructions = &.{},
        .present = true,
    };
    var moved = here;
    moved.frames = &.{.{ .function = 7, .call = .{ .offset = 0, .point = .{ .line = 9, .column = 5 } }, .parent = null }};
    var other = here;
    other.frames = &.{.{ .function = 8, .call = .{ .offset = 0, .point = .{ .line = 3, .column = 5 } }, .parent = null }};
    try std.testing.expect(!here.equal(moved));
    try std.testing.expect(here.equalPlain(moved));
    try std.testing.expect(!here.equalPlain(other));
    try std.testing.expect(here.inlines(7));
    try std.testing.expect(!here.inlines(8));
}
