//! Producer facts are checked against independent complete lowering, including misses.
const std = @import("std");
const language = @import("selka");
const facts = @import("test_runner_facts.zig");
const identity = @import("test_runner_identity.zig");
const build = @import("build.zig");
const lowering = @import("lowering_cache.zig");
const stage = @import("stage_store.zig");
const scopes = @import("stage_scopes.zig");
const ir = @import("ir.zig");
const pipeline = @import("pipeline.zig");
const emit = @import("emit_llvm.zig");
const loss = @import("stage_loss_test_support.zig");
const engine_run = @import("test_runner_engine.zig");
const test_records = @import("test_records.zig");

const Prepared = struct { module: *ir.Module, deferred: *lowering.Deferred, source: *language.source.Source, lowered: usize, reused: usize, records: test_records.Records };
const Work = struct { result: facts.Result, metrics: facts.Metrics, restored: usize };
const wire = struct { identity: stage.Digest, digest: stage.Digest, count: u32, edges: []const stage.Digest, chunks: []const stage.Digest, bare: bool };

fn prepare(a: std.mem.Allocator, store: *stage.Store, bench: *engine_run.Bench, source: language.source.Source) !Prepared {
    var unit = try language.Compilation.init(a, source.path, source.bytes);
    defer unit.deinit();
    unit.src = source;
    try unit.check();
    const retained = try a.create(language.source.Source);
    retained.* = source;
    const deferred = try a.create(lowering.Deferred);
    deferred.* = .{ .arena = a, .store = store };
    var cache = lowering.Cache.init(store);
    cache.lazy = deferred;
    const module = try a.create(ir.Module);
    var refusal: build.Refusal = .{};
    const input: build.Input = .{ .program = unit.program.?, .source = source };
    module.* = try build.buildRootsCached(a, &.{input.program.main}, input, &refusal, &cache);
    try deferred.prepare(module, source);
    return .{ .module = module, .deferred = deferred, .source = retained, .lowered = cache.counts.lowered, .reused = cache.counts.reused, .records = engine_run.planningOf(bench.state) };
}

/// The scope a prepared module's facts are keyed under (`facts.Identities`).
fn scopeOf(a: std.mem.Allocator, prepared: Prepared) !stage.Digest {
    var canon = try @import("canonical_ir.zig").Canon.prepare(a, prepared.module, pipeline.locator(prepared.source));
    return (try facts.Identities.of(a, prepared.module, &canon)).scope;
}

/// Remove the engine's record of every function's facts and of every group of them; how many functions had a key.
fn forgetFacts(a: std.mem.Allocator, bench: *engine_run.Bench, prepared: Prepared) !usize {
    var forgotten: usize = 0;
    const scope = try scopeOf(a, prepared);
    const keys = try a.alloc(?stage.Digest, prepared.module.functions.items.len);
    for (keys, 0..) |*slot, index| {
        slot.* = facts.factKey(prepared.deferred, scope, @intCast(index));
        const key = slot.* orelse continue;
        bench.state.runner.forget(&bench.state.kinds.facts, &key);
        forgotten += 1;
    }
    for (try facts.groups(a, prepared.deferred.store, prepared.module, keys)) |group| bench.state.runner.forget(&bench.state.kinds.facts, &group.key);
    return forgotten;
}

fn sourceOf(a: std.mem.Allocator, bytes: []const u8) !language.source.Source {
    return language.source.Source.init(a, "facts.selka", bytes);
}

fn extract(a: std.mem.Allocator, prepared: Prepared) !Work {
    var metrics: facts.Metrics = .{};
    const result = try facts.build(a, prepared.module, pipeline.locator(prepared.source), prepared.deferred, prepared.records, &metrics);
    try equalOracle(a, prepared.source.*, result.shared);
    return .{ .result = result, .metrics = metrics, .restored = prepared.deferred.restored };
}

/// `extract` with the group records on or off.
fn extractWith(a: std.mem.Allocator, prepared: Prepared, grouped: bool) !Work {
    var metrics: facts.Metrics = .{};
    const input: facts.Input = .{ .module = prepared.module, .locator = pipeline.locator(prepared.source), .deferred = prepared.deferred, .records = prepared.records, .grouped = grouped };
    const result = try facts.buildWith(a, input, &metrics);
    try equalOracle(a, prepared.source.*, result.shared);
    return .{ .result = result, .metrics = metrics, .restored = prepared.deferred.restored };
}

/// How many groups a prepared module's keyed functions fall into.
fn groupCount(a: std.mem.Allocator, prepared: Prepared) !usize {
    const scope = try scopeOf(a, prepared);
    const keys = try a.alloc(?stage.Digest, prepared.module.functions.items.len);
    for (keys, 0..) |*slot, index| slot.* = facts.factKey(prepared.deferred, scope, @intCast(index));
    return (try facts.groups(a, prepared.deferred.store, prepared.module, keys)).len;
}

/// A program of `count` helpers, each its own body, and a `main` that calls them all.
fn helpers(a: std.mem.Allocator, count: usize) !language.source.Source {
    var text: std.ArrayList(u8) = .empty;
    for (0..count) |index| try text.print(a, "func helper_{d}(n: int) -> int:\n    return n + {d}\n", .{ index, index });
    try text.appendSlice(a, "func main() -> int:\n    mut total = 0\n");
    for (0..count) |index| try text.print(a, "    total = total + helper_{d}(total)\n", .{index});
    try text.appendSlice(a, "    return total\n");
    return sourceOf(a, text.items);
}

fn equalOracle(a: std.mem.Allocator, source: language.source.Source, actual: identity.Shared) !void {
    var unit = try language.Compilation.init(a, source.path, source.bytes);
    defer unit.deinit();
    unit.src = source;
    try unit.check();
    var refusal: build.Refusal = .{};
    const fresh = try build.buildRootsSource(a, unit.program.?, &.{unit.program.?.main}, source, &refusal);
    const expected = try identity.Shared.plain(a, &fresh, pipeline.locator(&source));
    try std.testing.expectEqualDeep(expected, actual);
}

const arithmetic =
    \\func helper(n: int) -> int:
    \\    return n + 1
    \\func other(n: int) -> int:
    \\    return n * 2
    \\func main() -> int:
    \\    return helper(other(20))
    \\
;

// spec: NEW-CORE-TEST-FACTS-1
test "canonical producer facts reuse unrelated bodies after a private edit without decoding them" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const cold = try extract(a, try prepare(a, &store, bench, try sourceOf(a, arithmetic)));
    const warm = try extract(a, try prepare(a, &store, bench, try sourceOf(a, arithmetic)));
    const edited = try std.mem.replaceOwned(u8, a, arithmetic, "n + 1", "n + 3");
    const changed = try extract(a, try prepare(a, &store, bench, try sourceOf(a, edited)));
    try std.testing.expectEqual(@as(usize, 3), cold.metrics.fresh);
    try std.testing.expectEqual(@as(usize, 3), warm.metrics.reused);
    try std.testing.expectEqual(@as(usize, 0), warm.metrics.fresh);
    try std.testing.expectEqual(@as(usize, 0), warm.restored);
    try std.testing.expectEqual(@as(usize, 2), changed.metrics.reused);
    try std.testing.expectEqual(@as(usize, 1), changed.metrics.fresh);
    try std.testing.expectEqual(@as(usize, 0), changed.restored);
    try std.testing.expectEqualDeep(cold.result.identities, changed.result.identities);
    try std.testing.expect(!std.mem.eql(u8, &cold.result.shared.digests[1], &changed.result.shared.digests[1]));
}

// spec-case: NEW-CORE-TEST-FACTS-1
test "canonical producer facts retain complete callback references and recursive edges" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const callback =
        \\func helper(n: int) -> int:
        \\    if n <= 0:
        \\        return 1
        \\    return helper(n - 1)
        \\func apply(f: func(int) -> int, n: int) -> int:
        \\    return f(n)
        \\func main() -> int:
        \\    return apply(helper, 3)
        \\
    ;
    const cold = try extract(a, try prepare(a, &store, bench, try sourceOf(a, callback)));
    const warm = try extract(a, try prepare(a, &store, bench, try sourceOf(a, callback)));
    try std.testing.expectEqual(@as(usize, 3), warm.metrics.reused);
    try std.testing.expectEqualDeep(cold.result.shared, warm.result.shared);
    try std.testing.expectEqual(@as(usize, 2), warm.result.shared.callees[0].len);
    try std.testing.expectEqual(@as(usize, 0), warm.restored);
}

// spec-case: NEW-CORE-TEST-FACTS-1
test "canonical producer facts miss malformed complete edge records and recover from raw bodies" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const cold = try extract(a, try prepare(a, &store, bench, try sourceOf(a, arithmetic)));
    const warm = try prepare(a, &store, bench, try sourceOf(a, arithmetic));
    const key = facts.factKey(warm.deferred, try scopeOf(a, warm), 0).?;
    const malformed: wire = .{ .identity = cold.result.identities[0].?, .digest = cold.result.shared.digests[0], .count = 1, .edges = &.{@splat(255)}, .chunks = &.{}, .bare = true };
    try warm.records.storeValue(a, .{ .which = .facts, .key = &key, .replace = true }, wire, malformed);
    // The function's own record is read past its group's (a malformed group record is the group test's).
    const recovered = try extractWith(a, warm, false);
    try std.testing.expectEqual(@as(usize, 2), recovered.metrics.reused);
    try std.testing.expectEqual(@as(usize, 1), recovered.metrics.fresh);
    try std.testing.expectEqual(@as(usize, 1), recovered.restored);
}

// spec-case: NEW-CORE-TEST-FACTS-1
test "canonical producer facts expose missing raw payload after metadata eviction for complete retry" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    _ = try extract(a, try prepare(a, &store, bench, try sourceOf(a, arithmetic)));
    const warm = try prepare(a, &store, bench, try sourceOf(a, arithmetic));
    try std.testing.expect(try loss.damage(&store) > 0);
    // The metadata the eviction takes includes the facts the engine holds for the module's functions.
    try std.testing.expect(try forgetFacts(a, bench, warm) > 0);
    var metrics: facts.Metrics = .{};
    try std.testing.expectError(error.CacheMiss, facts.build(a, warm.module, pipeline.locator(warm.source), warm.deferred, warm.records, &metrics));
    try std.testing.expectEqual(@as(usize, 0), warm.deferred.restored);
}

// spec-case: NEW-CORE-TEST-FACTS-1
// spec-case: T2-FACTS-1
test "canonical producer facts are keyed by no position: another path or line for the same lowering reuses them" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    _ = try extract(a, try prepare(a, &store, bench, try sourceOf(a, arithmetic)));
    const warm = try prepare(a, &store, bench, try sourceOf(a, arithmetic));
    const other: LocatorContext = .{ .path = "another-root.selka", .zero_line = 2 };
    var metrics: facts.Metrics = .{};
    const result = try facts.build(a, warm.module, other.locator(), warm.deferred, warm.records, &metrics);
    try std.testing.expectEqual(@as(usize, 3), metrics.reused);
    try std.testing.expectEqual(@as(usize, 0), metrics.fallback);
    try std.testing.expectEqualSlices(u8, &(try scopeOf(a, warm)), &result.scope);
}

const LocatorContext = struct {
    path: []const u8,
    zero_line: u32 = 1,

    fn locator(self: *const LocatorContext) emit.Locator {
        return .{ .context = self, .locate = locate };
    }

    fn locate(pointer: *const anyopaque, offset: u32) emit.Location {
        const self: *const LocatorContext = @ptrCast(@alignCast(pointer));
        return .{ .path = self.path, .line = if (offset == 0) self.zero_line else 1, .column = offset + 1 };
    }
};

// spec-case: NEW-CORE-TEST-FACTS-1
test "canonical producer facts retain unaffected literal identities and survive moved source sites" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const text = "func helper() -> str:\n    return \"payload\"\nfunc other() -> str:\n    return \"untouched\"\nfunc main() -> int:\n    return strings.char_count(helper()) + strings.char_count(other())\n";
    _ = try extract(a, try prepare(a, &store, bench, try sourceOf(a, text)));
    const edited = try std.mem.replaceOwned(u8, a, text, "payload", "longer changed literal");
    const changed = try extract(a, try prepare(a, &store, bench, try sourceOf(a, edited)));
    const moved = try extract(a, try prepare(a, &store, bench, try sourceOf(a, try std.mem.concat(a, u8, &.{ "\n", edited }))));
    try std.testing.expectEqual(@as(usize, 2), changed.metrics.reused);
    try std.testing.expectEqual(@as(usize, 1), changed.metrics.fallback);
    try std.testing.expectEqual(@as(usize, 2), changed.metrics.fresh);
    try std.testing.expectEqual(@as(usize, 0), changed.restored);
    // A line above every function moves where each one is and none of their facts.
    try std.testing.expectEqual(@as(usize, 3), moved.metrics.reused);
    try std.testing.expectEqual(@as(usize, 0), moved.metrics.fallback);
    try std.testing.expectEqual(@as(usize, 1), moved.metrics.fresh);
}

// spec-case: NEW-CORE-TEST-FACTS-1
test "canonical producer facts survive a declaration the module does not reach and guard embedded assets" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const original = arithmetic ++ "func unused(n: int) -> int:\n    return n\n";
    _ = try extract(a, try prepare(a, &store, bench, try sourceOf(a, original)));
    const signature = try std.mem.replaceOwned(u8, a, original, "unused(n: int) -> int", "unused(n: i32) -> i32");
    const changed = try extract(a, try prepare(a, &store, bench, try sourceOf(a, signature)));
    const embedded = "func main() -> int:\n    return strings.char_count(embed_str(\"data.txt\"))\n";
    _ = try extract(a, try prepare(a, &store, bench, try embeddedSource(a, embedded, "before")));
    const assets = try extract(a, try prepare(a, &store, bench, try embeddedSource(a, embedded, "after")));
    // `unused` is not lowered, so its new signature changes no fact (D-T2-2); the embedded text is in the program's strings.
    try std.testing.expectEqual(@as(usize, 3), changed.metrics.reused);
    try std.testing.expectEqual(@as(usize, 0), changed.metrics.fallback);
    try std.testing.expectEqual(@as(usize, 0), assets.metrics.reused);
    try std.testing.expect(assets.metrics.fresh > 0);
}

fn embeddedSource(a: std.mem.Allocator, bytes: []const u8, contents: []const u8) !language.source.Source {
    var source = try sourceOf(a, bytes);
    const embeds = try language.embed.scan(a, source);
    for (embeds) |*item| {
        item.status = .ok;
        item.contents = contents;
        std.crypto.hash.Blake3.hash(contents, &item.digest, .{});
    }
    source.embeds = embeds;
    return source;
}

// spec-case: NEW-CORE-TEST-FACTS-1
test "canonical producer facts guard mapped default initializer provenance" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const model = "record Item:\n    value: int = 42\n";
    _ = try extract(a, try prepare(a, &store, bench, try mappedSource(a, model)));
    const warm = try extract(a, try prepare(a, &store, bench, try mappedSource(a, model)));
    const moved = try extract(a, try prepare(a, &store, bench, try mappedSource(a, "\n" ++ model)));
    const changed = try extract(a, try prepare(a, &store, bench, try mappedSource(a, "record Item:\n    value: int = 43\n")));
    try std.testing.expect(warm.metrics.reused > 0);
    // `main`'s lowering key names the checked context of the initializer, which says where it is: moving it lowers `main`
    // again, and its fact with it. Conservative, never stale.
    try std.testing.expectEqual(@as(usize, 0), moved.metrics.reused);
    try std.testing.expectEqual(@as(usize, 0), changed.metrics.reused);
}

fn mappedSource(a: std.mem.Allocator, model: []const u8) !language.source.Source {
    const sources = [_]language.source.Source{
        try language.source.Source.init(a, "model.selka", model),
        try language.source.Source.init(a, "main.selka", "func main() -> int:\n    return Item().value\n"),
    };
    return language.source.Source.initMapped(a, &sources);
}

// spec-case: NEW-CORE-TEST-FACTS-1
test "canonical producer facts tell structurally equal helpers apart by name and refuse two bodies with one identity" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    var module: ir.Module = .{};
    try module.compounds.appendSlice(a, &.{ .{ .list = .i64 }, .{ .list = .i64 } });
    const prefix = @import("build_equality.zig").prefix;
    const left: ir.Type = @fromBackingInt(ir.Type.first_compound);
    const right: ir.Type = @fromBackingInt(ir.Type.first_compound + 1);
    try module.functions.appendSlice(a, &.{
        .{ .name = prefix ++ "00000000000000000000000000000000", .signature = .{ .params = &.{ left, left }, .ret = .bool, .linkage = .runtime_c } },
        .{ .name = prefix ++ "11111111111111111111111111111111", .signature = .{ .params = &.{ right, right }, .ret = .bool, .linkage = .runtime_c } },
    });
    var deferred: lowering.Deferred = .{ .arena = a, .store = &store };
    try deferred.prepare(&module, null);
    const context: LocatorContext = .{ .path = "helpers.selka" };
    var metrics: facts.Metrics = .{};
    // The two helpers compare alike (one canonical identity); each keeps an identity of its own, qualified by its name.
    const result = try facts.build(a, &module, context.locator(), &deferred, engine_run.planningOf(bench.state), &metrics);
    try std.testing.expect(!std.mem.eql(u8, &result.identities[0].?, &result.identities[1].?));
    try std.testing.expectEqualSlices(u8, &result.shared.digests[0], &result.shared.digests[1]);
    // Two internal functions of one name and signature have one identity, and nothing tells them apart.
    var twins: ir.Module = .{};
    try twins.functions.appendSlice(a, &.{
        .{ .name = "twin", .signature = .{ .params = &.{}, .ret = .i64 } },
        .{ .name = "twin", .signature = .{ .params = &.{}, .ret = .i64 } },
    });
    var twin_deferred: lowering.Deferred = .{ .arena = a, .store = &store };
    try twin_deferred.prepare(&twins, null);
    try std.testing.expectError(error.UnknownMetadata, facts.build(a, &twins, context.locator(), &twin_deferred, engine_run.planningOf(bench.state), &metrics));
}

// spec-case: NEW-CORE-TEST-FACTS-1
test "canonical producer facts chunk large edge collections and recompute missing chunks" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const prepared = try largeGraph(a, &store);
    const records = engine_run.planningOf(bench.state);
    const context: LocatorContext = .{ .path = "large.selka" };
    var cold: facts.Metrics = .{};
    const expected = try facts.build(a, prepared.module, context.locator(), prepared.deferred, records, &cold);
    var warm: facts.Metrics = .{};
    const actual = try facts.build(a, prepared.module, context.locator(), prepared.deferred, records, &warm);
    const key = facts.factKey(prepared.deferred, expected.scope, 0).?;
    const stored = (try records.loadValue(a, a, .facts, &key, wire)).?;
    bench.state.runner.forget(&bench.state.kinds.facts, &stored.chunks[0]);
    var recovery: facts.Metrics = .{};
    const recovered = try facts.build(a, prepared.module, context.locator(), prepared.deferred, records, &recovery);
    try std.testing.expectEqualDeep(expected.shared, actual.shared);
    try std.testing.expectEqualDeep(expected.shared, recovered.shared);
    try std.testing.expectEqual(@as(usize, 1), warm.reused);
    try std.testing.expectEqual(@as(usize, 3), warm.decoded);
    try std.testing.expectEqual(@as(usize, 2), stored.chunks.len);
    try std.testing.expectEqual(@as(usize, 0), stored.edges.len);
    try std.testing.expectEqual(@as(usize, 0), recovery.reused);
}

const Graph = struct { module: *ir.Module, deferred: *lowering.Deferred };

fn largeGraph(a: std.mem.Allocator, store: *stage.Store) !Graph {
    const module = try a.create(ir.Module);
    module.* = .{};
    var root: ir.Function = .{ .name = "root", .signature = .{ .params = &.{}, .ret = .i64 } };
    for (1..514) |index| try root.insts.append(a, .{ .op = .call, .ty = .i64, .a = @fromBackingInt(@as(u32, @intCast(index))) });
    try module.functions.append(a, root);
    for (1..514) |index| try module.functions.append(a, .{ .name = try std.fmt.allocPrint(a, "external_{d}", .{index}), .signature = .{ .params = &.{}, .ret = .i64, .linkage = .runtime_c } });
    const deferred = try a.create(lowering.Deferred);
    deferred.* = .{ .arena = a, .store = store };
    try deferred.tables.keys.append(a, store.key("test-large-root", &.{}));
    try deferred.tables.unmixed.append(a, store.key("test-large-root", &.{}));
    try deferred.tables.source_max.append(a, null);
    try deferred.tables.handles.append(a, null);
    try deferred.tables.loaded.append(a, true);
    try deferred.prepare(module, null);
    return .{ .module = module, .deferred = deferred };
}

// spec-case: NEW-CORE-TEST-FACTS-1
// spec-case: T2-FACTS-1
test "canonical producer facts key on the lowered module's function table and not on a declaration it does not reach" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const original = arithmetic ++ "func unused(n: int) -> int:\n    return n\n";
    const signature = try std.mem.replaceOwned(u8, a, original, "unused(n: int) -> int", "unused(n: i32) -> i32");
    const reaching = try std.mem.replaceOwned(u8, a, original, "return helper(other(20))", "return helper(other(20)) + unused(1)");
    _ = try extract(a, try prepare(a, &store, bench, try sourceOf(a, original)));
    const before = try prepare(a, &store, bench, try sourceOf(a, original));
    _ = try extract(a, try prepare(a, &store, bench, try sourceOf(a, signature)));
    const after = try prepare(a, &store, bench, try sourceOf(a, signature));
    _ = try extract(a, try prepare(a, &store, bench, try sourceOf(a, reaching)));
    const reached = try prepare(a, &store, bench, try sourceOf(a, reaching));
    const helper = try indexNamed(before.module, "helper");
    try std.testing.expectEqualSlices(u8, &before.deferred.tables.unmixed.items[helper].?, &after.deferred.tables.unmixed.items[helper].?);
    try std.testing.expectEqualSlices(u8, &facts.factKey(before.deferred, try scopeOf(a, before), helper).?, &facts.factKey(after.deferred, try scopeOf(a, after), helper).?);
    // `main` now calls `unused` too: the table holds one more function, so every fact of the module is keyed anew, even the
    // helper's, whose own lowering is unchanged.
    const moved = try indexNamed(reached.module, "helper");
    try std.testing.expectEqualSlices(u8, &before.deferred.tables.unmixed.items[helper].?, &reached.deferred.tables.unmixed.items[moved].?);
    try std.testing.expect(!std.mem.eql(u8, &facts.factKey(before.deferred, try scopeOf(a, before), helper).?, &facts.factKey(reached.deferred, try scopeOf(a, reached), moved).?));
}

fn indexNamed(module: *const ir.Module, suffix: []const u8) !u32 {
    for (module.functions.items, 0..) |function, index| if (std.mem.endsWith(u8, function.name, suffix)) return @intCast(index);
    return error.NoSuchFunction;
}

// spec-case: NEW-CORE-TEST-FACTS-1
test "producer facts stay warm across an emitter edit, miss only when the test-runner stage moves, and equal the oracle" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var cold_store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer cold_store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const cold = try extract(a, try prepare(a, &cold_store, bench, try sourceOf(a, arithmetic)));
    const before = stage.defaultStageDigests();
    var emitted = before;
    emitted[@backingInt(scopes.Stage.emit)][0] ^= 0xff;
    emitted[@backingInt(scopes.Stage.whole)][0] ^= 0xff;
    var emit_store = try stage.Store.initWithOptions(std.testing.allocator, std.testing.io, root, .{ .identities = emitted });
    defer emit_store.deinit();
    const warm = try extract(a, try prepare(a, &emit_store, bench, try sourceOf(a, arithmetic)));
    try std.testing.expectEqual(@as(usize, 3), warm.metrics.reused);
    try std.testing.expectEqual(@as(usize, 0), warm.metrics.fresh);
    try std.testing.expectEqualDeep(cold.result.shared, warm.result.shared);
    var runner = before;
    runner[@backingInt(scopes.Stage.test_runner)][0] ^= 0xff;
    var runner_store = try stage.Store.initWithOptions(std.testing.allocator, std.testing.io, root, .{ .identities = runner });
    defer runner_store.deinit();
    const moved = try extract(a, try prepare(a, &runner_store, bench, try sourceOf(a, arithmetic)));
    try std.testing.expectEqual(@as(usize, 3), moved.metrics.fresh);
    try std.testing.expectEqualDeep(cold.result.shared, moved.result.shared);
}

// spec: TEST-LOOP-FACT-GROUPS-1
test "a root's facts read by group records equal its facts read one by one, and an edit records only its group again" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const source = try helpers(a, 30);
    // One by one, cold: every function's own record, and no group record.
    const whole = try extractWith(a, try prepare(a, &store, bench, source), false);
    // The first grouped run finds no group record, reads each function's own and records the groups.
    const first = try extractWith(a, try prepare(a, &store, bench, source), true);
    const warm_prepared = try prepare(a, &store, bench, source);
    const groups = try groupCount(a, warm_prepared);
    const warm = try extractWith(a, warm_prepared, true);
    const again = try extractWith(a, try prepare(a, &store, bench, source), false);
    try std.testing.expectEqual(@as(usize, 31), whole.metrics.fresh);
    try std.testing.expectEqual(@as(usize, 0), whole.metrics.groups);
    try std.testing.expectEqual(@as(usize, 31), first.metrics.reused);
    try std.testing.expectEqual(@as(usize, 0), first.metrics.groups);
    try std.testing.expect(groups > 1);
    try std.testing.expectEqual(groups, warm.metrics.groups);
    try std.testing.expectEqual(groups, warm.metrics.decoded);
    try std.testing.expectEqual(@as(usize, 31), warm.metrics.reused);
    try std.testing.expectEqual(@as(usize, 0), warm.metrics.fresh);
    try std.testing.expectEqual(@as(usize, 0), warm.restored);
    try std.testing.expectEqualDeep(whole.result, warm.result);
    try std.testing.expectEqualDeep(whole.result, first.result);
    try std.testing.expectEqualDeep(whole.result, again.result);
    // A body edit changes one function's key: its group reads its members one by one and is recorded again, the others are
    // one record each, and the facts are still the ones read one by one.
    const edited = try std.mem.replaceOwned(u8, a, source.bytes, "return n + 7\n", "return n + 70\n");
    const changed = try extractWith(a, try prepare(a, &store, bench, try sourceOf(a, edited)), true);
    const changed_whole = try extractWith(a, try prepare(a, &store, bench, try sourceOf(a, edited)), false);
    const settled = try extractWith(a, try prepare(a, &store, bench, try sourceOf(a, edited)), true);
    try std.testing.expectEqual(groups - 1, changed.metrics.groups);
    try std.testing.expectEqual(@as(usize, 1), changed.metrics.fresh);
    try std.testing.expectEqual(@as(usize, 30), changed.metrics.reused);
    try std.testing.expectEqual(groups, settled.metrics.groups);
    try std.testing.expectEqual(@as(usize, 0), settled.metrics.fresh);
    try std.testing.expectEqualDeep(changed_whole.result, changed.result);
    try std.testing.expectEqualDeep(changed_whole.result, settled.result);
}

// spec-case: TEST-LOOP-FACT-GROUPS-1
test "a group record that does not describe its members is read past, its facts recomputed or read one by one, and recorded again" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var bench = try engine_run.Bench.start(std.testing.allocator);
    defer bench.deinit();
    const source = try helpers(a, 30);
    const cold = try extractWith(a, try prepare(a, &store, bench, source), true);
    const prepared = try prepare(a, &store, bench, source);
    const scope = try scopeOf(a, prepared);
    const keys = try a.alloc(?stage.Digest, prepared.module.functions.items.len);
    for (keys, 0..) |*slot, index| slot.* = facts.factKey(prepared.deferred, scope, @intCast(index));
    const all = try facts.groups(a, prepared.deferred.store, prepared.module, keys);
    // A record of one fact too few under the first group's key: its members are read one by one.
    const stored = (try prepared.records.loadValue(a, a, .facts, &all[0].key, []const wire)).?;
    try prepared.records.storeValue(a, .{ .which = .facts, .key = &all[0].key, .replace = true }, []const wire, stored[1..]);
    const short = try extractWith(a, prepared, true);
    try std.testing.expectEqual(all.len - 1, short.metrics.groups);
    try std.testing.expectEqual(@as(usize, 0), short.metrics.fresh);
    try std.testing.expectEqualDeep(cold.result, short.result);
    // A record whose first fact names another function: that member is recomputed, the group recorded again.
    var swapped = try a.dupe(wire, stored);
    swapped[0].identity = swapped[1].identity;
    try prepared.records.storeValue(a, .{ .which = .facts, .key = &all[0].key, .replace = true }, []const wire, swapped);
    const wrong = try extractWith(a, try prepare(a, &store, bench, source), true);
    try std.testing.expectEqual(@as(usize, 1), wrong.metrics.fresh);
    try std.testing.expectEqualDeep(cold.result, wrong.result);
    const healed = try extractWith(a, try prepare(a, &store, bench, source), true);
    try std.testing.expectEqual(all.len, healed.metrics.groups);
    try std.testing.expectEqual(@as(usize, 0), healed.metrics.fresh);
    try std.testing.expectEqualDeep(cold.result, healed.result);
}
