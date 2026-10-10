//! Producer facts are checked against independent complete lowering, including misses.
const std = @import("std");
const language = @import("mylang");
const facts = @import("test_runner_facts.zig");
const identity = @import("test_runner_identity.zig");
const build = @import("build.zig");
const lowering = @import("lowering_cache.zig");
const stage = @import("stage_store.zig");
const ir = @import("ir.zig");
const pipeline = @import("pipeline.zig");
const emit = @import("emit_llvm.zig");
const loss = @import("stage_loss_test_support.zig");

const Prepared = struct { module: *ir.Module, deferred: *lowering.Deferred, source: *language.source.Source, lowered: usize, reused: usize };
const Work = struct { result: facts.Result, metrics: facts.Metrics, restored: usize };
const wire = struct { identity: stage.Digest, digest: stage.Digest, count: u32, edges: []const stage.Digest, chunks: []const stage.Digest };

fn prepare(a: std.mem.Allocator, store: *stage.Store, source: language.source.Source) !Prepared {
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
    return .{ .module = module, .deferred = deferred, .source = retained, .lowered = cache.lowered, .reused = cache.reused };
}

fn sourceOf(a: std.mem.Allocator, bytes: []const u8) !language.source.Source {
    return language.source.Source.init(a, "facts.my", bytes);
}

fn extract(a: std.mem.Allocator, prepared: Prepared) !Work {
    var metrics: facts.Metrics = .{};
    const result = try facts.build(a, prepared.module, pipeline.locator(prepared.source), prepared.deferred, &metrics);
    try equalOracle(a, prepared.source.*, result.shared);
    return .{ .result = result, .metrics = metrics, .restored = prepared.deferred.restored };
}

fn equalOracle(a: std.mem.Allocator, source: language.source.Source, actual: identity.Shared) !void {
    var unit = try language.Compilation.init(a, source.path, source.bytes);
    defer unit.deinit();
    unit.src = source;
    try unit.check();
    var refusal: build.Refusal = .{};
    const fresh = try build.buildRootsSource(a, unit.program.?, &.{unit.program.?.main}, source, &refusal);
    const expected = try identity.Shared.build(a, &fresh, pipeline.locator(&source));
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
    const cold = try extract(a, try prepare(a, &store, try sourceOf(a, arithmetic)));
    const warm = try extract(a, try prepare(a, &store, try sourceOf(a, arithmetic)));
    const edited = try std.mem.replaceOwned(u8, a, arithmetic, "n + 1", "n + 3");
    const changed = try extract(a, try prepare(a, &store, try sourceOf(a, edited)));
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
    const cold = try extract(a, try prepare(a, &store, try sourceOf(a, callback)));
    const warm = try extract(a, try prepare(a, &store, try sourceOf(a, callback)));
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
    const cold = try extract(a, try prepare(a, &store, try sourceOf(a, arithmetic)));
    const warm = try prepare(a, &store, try sourceOf(a, arithmetic));
    const key = facts.factKey(warm.deferred, pipeline.locator(warm.source), 0).?;
    try store.storeValue(key, wire, .{ .identity = cold.result.identities[0].?, .digest = cold.result.shared.digests[0], .count = 1, .edges = &.{@splat(255)}, .chunks = &.{} });
    const recovered = try extract(a, warm);
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
    _ = try extract(a, try prepare(a, &store, try sourceOf(a, arithmetic)));
    const warm = try prepare(a, &store, try sourceOf(a, arithmetic));
    try std.testing.expect(try loss.damage(&store) > 0);
    var metrics: facts.Metrics = .{};
    try std.testing.expectError(error.CacheMiss, facts.build(a, warm.module, pipeline.locator(warm.source), warm.deferred, &metrics));
    try std.testing.expectEqual(@as(usize, 0), warm.deferred.restored);
}

// spec-case: NEW-CORE-TEST-FACTS-1
test "canonical producer facts bind locator paths and zero span provenance independently" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    _ = try extract(a, try prepare(a, &store, try sourceOf(a, arithmetic)));
    const warm = try prepare(a, &store, try sourceOf(a, arithmetic));
    const original: LocatorContext = .{ .path = "one-root.my" };
    const other: LocatorContext = .{ .path = "another-root.my" };
    const zero: LocatorContext = .{ .path = "one-root.my", .zero_line = 2 };
    const original_key = facts.factKey(warm.deferred, original.locator(), 0).?;
    try std.testing.expect(!std.mem.eql(u8, &original_key, &facts.factKey(warm.deferred, other.locator(), 0).?));
    try std.testing.expect(!std.mem.eql(u8, &original_key, &facts.factKey(warm.deferred, zero.locator(), 0).?));
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
test "canonical producer facts retain unaffected literal identities and invalidate moved source sites" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    const text = "func helper() -> str:\n    return \"payload\"\nfunc other() -> str:\n    return \"untouched\"\nfunc main() -> int:\n    return len(helper()) + len(other())\n";
    _ = try extract(a, try prepare(a, &store, try sourceOf(a, text)));
    const edited = try std.mem.replaceOwned(u8, a, text, "payload", "longer changed literal");
    const changed = try extract(a, try prepare(a, &store, try sourceOf(a, edited)));
    const moved = try extract(a, try prepare(a, &store, try sourceOf(a, try std.mem.concat(a, u8, &.{ "\n", edited }))));
    try std.testing.expectEqual(@as(usize, 2), changed.metrics.reused);
    try std.testing.expectEqual(@as(usize, 1), changed.metrics.fallback);
    try std.testing.expectEqual(@as(usize, 2), changed.metrics.fresh);
    try std.testing.expectEqual(@as(usize, 0), changed.restored);
    try std.testing.expectEqual(@as(usize, 0), moved.metrics.reused);
    try std.testing.expectEqual(@as(usize, 3), moved.metrics.fallback);
    try std.testing.expectEqual(@as(usize, 4), moved.metrics.fresh);
}

// spec-case: NEW-CORE-TEST-FACTS-1
test "canonical producer facts preserve conservative complete declaration and embed guards" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    const original = arithmetic ++ "func unused(n: int) -> int:\n    return n\n";
    _ = try extract(a, try prepare(a, &store, try sourceOf(a, original)));
    const signature = try std.mem.replaceOwned(u8, a, original, "unused(n: int) -> int", "unused(n: i32) -> i32");
    const changed = try extract(a, try prepare(a, &store, try sourceOf(a, signature)));
    const embedded = "func main() -> int:\n    return len(embed_str(\"data.txt\"))\n";
    _ = try extract(a, try prepare(a, &store, try embeddedSource(a, embedded, "before")));
    const assets = try extract(a, try prepare(a, &store, try embeddedSource(a, embedded, "after")));
    try std.testing.expectEqual(@as(usize, 0), changed.metrics.reused);
    try std.testing.expectEqual(@as(usize, 3), changed.metrics.fresh);
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
    const model = "record Item:\n    value: int = 42\n";
    _ = try extract(a, try prepare(a, &store, try mappedSource(a, model)));
    const warm = try extract(a, try prepare(a, &store, try mappedSource(a, model)));
    const moved = try extract(a, try prepare(a, &store, try mappedSource(a, "\n" ++ model)));
    const changed = try extract(a, try prepare(a, &store, try mappedSource(a, "record Item:\n    value: int = 43\n")));
    try std.testing.expect(warm.metrics.reused > 0);
    try std.testing.expectEqual(@as(usize, 0), moved.metrics.reused);
    try std.testing.expectEqual(@as(usize, 0), changed.metrics.reused);
}

fn mappedSource(a: std.mem.Allocator, model: []const u8) !language.source.Source {
    const sources = [_]language.source.Source{
        try language.source.Source.init(a, "model.my", model),
        try language.source.Source.init(a, "main.my", "func main() -> int:\n    return Item().value\n"),
    };
    return language.source.Source.initMapped(a, &sources);
}

// spec-case: NEW-CORE-TEST-FACTS-1
test "canonical producer facts refuse ambiguous structurally equal helper identities" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var module: ir.Module = .{};
    try module.compounds.appendSlice(a, &.{ .{ .list = .i64 }, .{ .list = .i64 } });
    const prefix = @import("emit_values.zig").equal_prefix;
    const left: ir.Type = @fromBackingInt(ir.Type.first_compound);
    const right: ir.Type = @fromBackingInt(ir.Type.first_compound + 1);
    try module.functions.appendSlice(a, &.{
        .{ .name = try std.fmt.allocPrint(a, "{s}{d}", .{ prefix, @backingInt(left) }), .signature = .{ .params = &.{ left, left }, .ret = .bool, .linkage = .runtime_c } },
        .{ .name = try std.fmt.allocPrint(a, "{s}{d}", .{ prefix, @backingInt(right) }), .signature = .{ .params = &.{ right, right }, .ret = .bool, .linkage = .runtime_c } },
    });
    var deferred: lowering.Deferred = .{ .arena = a, .store = &store };
    try deferred.prepare(&module, null);
    const context: LocatorContext = .{ .path = "helpers.my" };
    var metrics: facts.Metrics = .{};
    try std.testing.expectError(error.UnknownMetadata, facts.build(a, &module, context.locator(), &deferred, &metrics));
    try std.testing.expectEqual(@as(usize, 0), metrics.reused);
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
    const prepared = try largeGraph(a, &store);
    const context: LocatorContext = .{ .path = "large.my" };
    var cold: facts.Metrics = .{};
    const expected = try facts.build(a, prepared.module, context.locator(), prepared.deferred, &cold);
    var warm: facts.Metrics = .{};
    const actual = try facts.build(a, prepared.module, context.locator(), prepared.deferred, &warm);
    const key = facts.factKey(prepared.deferred, context.locator(), 0).?;
    const stored = (try store.loadValue(a, key, wire)).?;
    try loss.remove(a, &store, stored.chunks[0]);
    var recovery: facts.Metrics = .{};
    const recovered = try facts.build(a, prepared.module, context.locator(), prepared.deferred, &recovery);
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
    try deferred.tables.source_max.append(a, null);
    try deferred.tables.handles.append(a, null);
    try deferred.tables.loaded.append(a, true);
    try deferred.prepare(module, null);
    return .{ .module = module, .deferred = deferred };
}
