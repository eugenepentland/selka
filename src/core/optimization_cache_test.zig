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
const source = @import("mylang").source;
const shortcut_mod = @import("optimizer_shortcut.zig");
const demand_scope = "optimizer-demand-v1";

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
const Produced = struct { llvm: []const u8, core: []const u8, result: passes.Result, statistics: cache.Statistics, ancestry: []const cache.Provenance = &.{} };

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
    const llvm = try emit.emitModuleWithScratch(a, backing, &module, .{ .locator = locator, .source_path = "test.my", .main = .{ .parameters = &.{"out"} }, .analysis = support.analysis(&result), .verify = result.emission.verifying });
    return .{ .llvm = llvm, .core = try print.module(a, &module), .result = result, .statistics = if (storage != null) context.statistics else .{}, .ancestry = try canonicalAncestry(a, &module, &result.provenance) };
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
        .output = .{ .llvm = llvm, .core = try print.module(a, &module), .result = result, .statistics = context.statistics, .ancestry = try canonicalAncestry(a, &module, &result.provenance) },
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
    \\    out.print(before(), caller(9), affine(12))
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
    const src = try source.Source.init(a, "test.my", text);
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
    return .{ .llvm = llvm, .core = try print.module(a, &module), .result = result, .statistics = if (storage != null) context.statistics else .{}, .ancestry = ancestry };
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
        try passes.restoreDeferredFinal(self.arena, scratch.allocator(), self.context, index, self.result);
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

const DemandSettings = struct { omit: bool, force_eager: bool = false, mode: passes.Mode = .verify };
fn verifyFinalDigests(a: std.mem.Allocator, locator: emit.Locator, context: *const cache.Context) !void {
    var fresh = try @import("canonical_ir.zig").Canon.prepare(a, context.source.module, locator);
    for (context.lazy.finals, context.lazy.loaded, 0..) |metadata, present, index| {
        if (!present) continue;
        const record = metadata orelse continue;
        const digest = try fresh.functionDigest(@intCast(index));
        try std.testing.expectEqualSlices(u8, &digest, &record.body);
    }
}

fn compileDemand(a: std.mem.Allocator, backing: std.mem.Allocator, text: []const u8, storage: *store.Store, omit: bool) !DemandProduced {
    return compileDemandGuarded(a, backing, text, storage, .{ .omit = omit });
}
fn compileDemandGuarded(a: std.mem.Allocator, backing: std.mem.Allocator, text: []const u8, storage: *store.Store, settings: DemandSettings) !DemandProduced {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, text, &refusal);
    const token: u8 = 0;
    const locator: emit.Locator = .{ .context = &token, .locate = locate };
    const source_context = try snapshot.Context.init(a, &module, null);
    const raw_layout = try snapshot.layout(a, source_context);
    const count = module.functions.items.len;
    const bodies = try a.alloc(snapshot.Wire, count);
    const keys = try a.alloc(?store.Digest, count);
    const loaded = try a.alloc(bool, count);
    for (module.functions.items, bodies, keys, loaded) |*function, *body, *key, *present| {
        body.* = try snapshot.capture(a, source_context, function.*);
        const body_digest = try snapshot.digest(a, source_context, function.*);
        key.* = storage.key("test-demand-lowering", &.{ &raw_layout, &body_digest });
        present.* = !settings.omit or function.signature.linkage != .internal;
        if (!present.*) function.* = .{ .name = function.name, .signature = function.signature, .span = function.span };
    }
    var loader: DemandLoader = .{ .arena = a, .context = source_context, .bodies = bodies };
    var demand: demand_ir.Context = .{ .keys = keys, .loaded = loaded, .pointer = &loader, .ensure_fn = DemandLoader.ensure, .force_eager = settings.force_eager };
    var context = cache.Context.init(storage, source_context, locator);
    context.lazy.raw = &demand;
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
    const original_source = try source.Source.init(a, "test.my", text);
    var emission_counts: @import("emission_cache.zig").Counts = .{};
    var analysis = support.analysis(&result);
    analysis.effects = if (result.emission.effects) |*summaries| summaries else null;
    const emission_options: emit.Options = .{ .locator = locator, .source_path = "test.my", .main = .{ .parameters = &.{"out"} }, .analysis = analysis, .verify = result.emission.verifying };
    const emitted = try @import("emit_units.zig").emitCached(a, backing, &module, emission_options, .{
        .store = storage,
        .counts = &emission_counts,
        .deferred = &table,
        .receipts = .{
            .finals = context.lazy.finals,
            .source = &original_source,
            .layout = context.layoutDigest().?,
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
        .source_path = "test.my",
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
        .output = .{ .llvm = llvm, .core = try print.module(a, &module), .result = result, .statistics = context.statistics, .ancestry = try canonicalAncestry(a, &module, &result.provenance) },
    };
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
    const DemandRecord = struct { entries: []shortcut_mod.Entry, layout: ?store.Digest };
    const index_key = storage.key(demand_scope, &.{ "", &.{@backingInt(passes.Mode.verify)} });
    var record = (try storage.loadValue(a, index_key, DemandRecord)).?;
    record.layout.?[0] ^= 1;
    // The stage checksum is valid, but the independently checked final catalog
    // guard is stale. No deferred body may be used under this index.
    try storage.storeValue(index_key, DemandRecord, record);
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
    const Saved = struct { entries: []shortcut_mod.Entry, layout: ?store.Digest };
    const key = storage.key(demand_scope, &.{ "", &.{@backingInt(passes.Mode.verify)} });
    const saved = (try storage.loadValue(a, key, Saved)) orelse return error.TestUnexpectedResult;
    for (module.functions.items, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, name)) return saved.entries[index].demand.fused_identity;
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
        \\    return s[0:1] == "x"
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
    \\    out.print(caller(7))
    \\    return 0
;

fn checkpointFixture(a: std.mem.Allocator, callee_first: bool) ![]const u8 {
    return std.mem.concat(a, u8, &.{ checkpoint_leaf, if (callee_first) checkpoint_wrapper else checkpoint_caller, if (callee_first) checkpoint_caller else checkpoint_wrapper, checkpoint_main });
}

fn savedCheckpoint(a: std.mem.Allocator, text: []const u8, storage: *store.Store, mode: passes.Mode, stage_index: usize) !?cache.Checkpoint {
    const Entry = shortcut_mod.Entry;
    const Envelope = struct { entries: []Entry, layout: ?store.Digest };
    const saved = (try storage.loadValue(a, storage.key(demand_scope, &.{ "", &.{@backingInt(mode)} }), Envelope)).?;
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
    \\    out.print(leaf(n))
    \\    return n + 1
    \\
    \\func caller(out: Stream, n: int) -> int:
    \\    return wrapper(out, n % 100) + 1
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(caller(out, 7))
    \\    return 0
;

fn savedWrapperParameters(a: std.mem.Allocator, text: []const u8, storage: *store.Store, mode: passes.Mode) !?[]const ?facts.Interval {
    const Entry = shortcut_mod.Entry;
    const Envelope = struct { entries: []Entry, layout: ?store.Digest };
    const saved = (try storage.loadValue(a, storage.key(demand_scope, &.{ "", &.{@backingInt(mode)} }), Envelope)).?;
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
    \\    xs.append(2)
    \\    mut total = 0
    \\    for i in range(n):
    \\        if kind == 0:
    \\            total += xs[i]
    \\        else:
    \\            total += xs[i] + 1
    \\    return total
    \\
    \\func wrapper(out: Stream, n: int, kind: int) -> int:
    \\    out.print(1)
    \\    mut xs = [1]
    \\    return origin(mut xs, n, kind)
    \\
    \\func main(out: Stream) -> int:
    \\    out.print(wrapper(out, 3, 1))
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
        \\    out.print(reader(State(x=3)), idle(), writer().x)
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
        \\    return s[0:1] == "x"
        \\func reader(s: State) -> int:
        \\    return s.x + 1
        \\func idle() -> int:
        \\    return 42
        \\func main(out: Stream) -> int:
        \\    out.print(reader(State(x=3)), idle(), borrow("abc"))
        \\    return 0
    ;
    const after = try std.mem.replaceOwned(u8, a, before, "borrow(\"abc\")", "borrow(\"abd\")");
    const oracle = try compile(a, std.testing.allocator, before, null, .verify);
    const cold = try compileDemand(a, std.testing.allocator, before, &storage, false);
    try equal(oracle, cold.output);
    const Envelope = struct { entries: []shortcut_mod.Entry, layout: ?store.Digest };
    const saved = (try storage.loadValue(a, storage.key(demand_scope, &.{ "", &.{@backingInt(passes.Mode.verify)} }), Envelope)).?;
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
