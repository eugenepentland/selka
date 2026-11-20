//! Durable lowering replay is compared with the uncached builder, including
//! declaration/string order, source spans and complete emitted LLVM text.
const std = @import("std");
const stage_loss = @import("stage_loss_test_support.zig");
const language = @import("selka");
const build = @import("build.zig");
const lowering = @import("lowering_cache.zig");
const stage = @import("stage_store.zig");
const stage_tally = @import("stage_tally.zig");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const emit = @import("emit_llvm.zig");
const frontend_reuse = @import("frontend_reuse.zig");

const report = std.debug.print;
const cached_path = "cached.selka";
const source_name = "cached.selka";

const Work = struct { lowered: usize, reused: usize };

fn firstLine(_: *const anyopaque, span: u32) emit.Location {
    return .{ .line = 1, .column = span + 1 };
}

fn sameModule(a: std.mem.Allocator, cached: *const ir.Module, fresh: *const ir.Module) !void {
    try support.verified(a, cached, &.{});
    try std.testing.expectEqual(fresh.entry, cached.entry);
    try std.testing.expectEqualDeep(fresh.compounds.items, cached.compounds.items);
    try std.testing.expectEqualDeep(fresh.strings.items, cached.strings.items);
    try std.testing.expectEqual(fresh.functions.items.len, cached.functions.items.len);
    for (fresh.functions.items, cached.functions.items) |expected, actual| {
        try std.testing.expectEqualStrings(expected.name, actual.name);
        try std.testing.expectEqualDeep(expected.signature, actual.signature);
        try std.testing.expectEqual(expected.span, actual.span);
        try std.testing.expectEqualDeep(expected.insts.items, actual.insts.items);
        try std.testing.expectEqualDeep(expected.extra.items, actual.extra.items);
        try std.testing.expectEqualDeep(expected.loops.items, actual.loops.items);
        try std.testing.expectEqual(expected.blocks.items.len, actual.blocks.items.len);
        for (expected.blocks.items, actual.blocks.items) |left, right| {
            try std.testing.expectEqualDeep(left.insts.items, right.insts.items);
            try std.testing.expectEqualDeep(left.preds.items, right.preds.items);
        }
    }
    const context: u8 = 0;
    const options: emit.Options = .{ .locator = .{ .context = &context, .locate = firstLine }, .source_path = source_name, .main = .{ .parameters = &.{"out"} } };
    try std.testing.expectEqualStrings(try emit.emitModule(a, fresh, options), try emit.emitModule(a, cached, options));
}

fn compare(root: []const u8, backing: std.mem.Allocator, bytes: []const u8, drop_debug: bool) !Work {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, source_name, bytes);
    defer unit.deinit();
    unit.check() catch |err| {
        for (unit.diagnostics.items) |diagnostic| report("{s}", .{try diagnostic.render(a, unit.src)});
        return err;
    };
    return compareChecked(root, backing, a, &unit, drop_debug);
}

fn compareChecked(root: []const u8, backing: std.mem.Allocator, a: std.mem.Allocator, unit: *const language.Compilation, drop_debug: bool) !Work {
    var store = try stage.Store.init(backing, std.testing.io, root);
    defer store.deinit();
    var cache = lowering.Cache.init(&store);
    const input: build.Input = .{ .program = unit.program.?, .source = unit.src, .drop_debug = drop_debug };
    var refusal: build.Refusal = .{};
    const cached = try build.buildExecutableCached(a, input, &refusal, &cache);
    const fresh = try build.buildExecutable(a, input, &refusal);
    try sameModule(a, &cached, &fresh);
    return .{ .lowered = cache.counts.lowered, .reused = cache.counts.reused };
}

fn compareMapped(root: []const u8, backing: std.mem.Allocator, left: []const u8, right: []const u8) !Work {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const sources = [_]language.source.Source{
        try language.source.Source.init(a, "templates.selka", left),
        try language.source.Source.init(a, "entry.selka", right),
    };
    const merged = try language.source.Source.initMapped(a, &sources);
    var unit = try language.Compilation.init(a, merged.path, merged.bytes);
    defer unit.deinit();
    unit.src = merged;
    unit.check() catch |err| {
        for (unit.diagnostics.items) |diagnostic| report("{s}", .{try diagnostic.render(a, unit.src)});
        return err;
    };
    return compareChecked(root, backing, a, &unit, false);
}

const arithmetic =
    \\func first(n: int) -> int:
    \\    return n + 1
    \\
    \\func second(n: int) -> int:
    \\    return n * 2
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, "answer")
    \\    return first(second(20))
    \\
;

const CatalogEvidence = struct { digest: stage.Digest, assets: stage.Digest, reused: bool };
const catalog_record =
    \\record Item:
    \\    value: int = 42
    \\
    \\func identity[T](x: T) -> T:
    \\    return x
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, "ready")
    \\    return identity[int](Item().value)
    \\
;

fn catalogEvidence(store: *const stage.Store, program: language.typed.Program, source: ?language.source.Source, catalog: ?*const lowering.Catalog) !CatalogEvidence {
    var module: ir.Module = .{};
    var discovery: lowering.Discovery = .{};
    var types: std.AutoHashMapUnmanaged(language.typed.Type, ir.Type) = .empty;
    var cache = lowering.Cache.init(store);
    cache.catalog.known = catalog;
    // A session keeps its per-program tables in the build's arena, which is dropped with the build.
    var arena = std.heap.ArenaAllocator.init(store.backing);
    defer arena.deinit();
    const session = try lowering.Session.prepare(&cache, .{
        .arena = arena.allocator(),
        .input = .{ .program = program, .source = source, .drop_debug = false },
        .module = &module,
        .discovery = &discovery,
        .types = &types,
    });
    return .{ .digest = session.catalog.?, .assets = session.assets, .reused = cache.catalog.reused };
}

fn catalogEquivalent(store: *const stage.Store, program: language.typed.Program, source: ?language.source.Source, catalog: *const lowering.Catalog) !CatalogEvidence {
    const ordinary = try catalogEvidence(store, program, source, null);
    const shared = try catalogEvidence(store, program, source, catalog);
    try std.testing.expectEqualSlices(u8, &ordinary.digest, &shared.digest);
    try std.testing.expectEqualSlices(u8, &ordinary.assets, &shared.assets);
    return shared;
}

// spec-case: NEW-CORE-TEST-FACTS-1
// spec-case: NEW-CORE-STAGE-CACHE-3
test "shared checked catalog keeps per-root origins and assets in ordinary lowering fingerprints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var unit = try language.Compilation.init(a, source_name, arithmetic);
    defer unit.deinit();
    try unit.check();
    const catalog = try lowering.Catalog.prepare(unit.program.?);
    const plain = try catalogEquivalent(&store, unit.program.?, unit.src, &catalog);
    try std.testing.expect(plain.reused);
    const merged = try language.source.Source.initMapped(a, &.{ try language.source.Source.init(a, "directory.selka", "import body\n"), unit.src });
    const first = try catalogEquivalent(&store, unit.program.?, merged, &catalog);
    try std.testing.expect(first.reused);
    var rooted = merged;
    const origins = try a.dupe(language.source.Source.Origin, merged.origins);
    origins[0].original.path = "another_root.selka";
    rooted.origins = origins;
    const second = try catalogEquivalent(&store, unit.program.?, rooted, &catalog);
    try std.testing.expect(second.reused);
    try std.testing.expect(!std.mem.eql(u8, &first.digest, &second.digest));
    rooted.embeds = &.{.{ .literal = .{ .start = 0, .end = 0 }, .path = "asset.txt", .status = .ok, .digest = @splat(1), .contents = "changed" }};
    const embedded = try catalogEquivalent(&store, unit.program.?, rooted, &catalog);
    try std.testing.expect(embedded.reused);
    try std.testing.expect(!std.mem.eql(u8, &second.assets, &embedded.assets));
}

fn noPart(_: *anyopaque, _: ?language.source.Source, _: language.typed.Function) ?stage.Digest {
    return null;
}

test "a session that keys by parts alone has no catalog, and cannot key a function the engine holds no part for" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var unit = try language.Compilation.init(a, source_name, arithmetic);
    defer unit.deinit();
    try unit.check();
    var module: ir.Module = .{};
    var discovery: lowering.Discovery = .{};
    var types: std.AutoHashMapUnmanaged(language.typed.Type, ir.Type) = .empty;
    const context: lowering.Context = .{ .arena = a, .input = .{ .program = unit.program.?, .source = unit.src, .drop_debug = false }, .module = &module, .discovery = &discovery, .types = &types };
    var anchor: u8 = 0;
    var cache = lowering.Cache.init(&store);
    cache.engine.parts = .{ .context = &anchor, .digest = noPart };
    var parts = try lowering.Session.prepareKeys(&cache, context);
    try std.testing.expectEqual(@as(?stage.Digest, null), parts.catalog);
    try std.testing.expectError(error.InvalidSnapshot, parts.key(context, unit.program.?.functions[0]));
    var whole = try lowering.Session.prepare(&cache, context);
    try std.testing.expect(whole.catalog != null);
    _ = try whole.key(context, unit.program.?.functions[0]);
}

fn changedCatalog(store: *const stage.Store, original: CatalogEvidence, program: language.typed.Program, catalog: *const lowering.Catalog) !void {
    const changed = try catalogEquivalent(store, program, null, catalog);
    try std.testing.expect(!changed.reused);
    try std.testing.expect(!std.mem.eql(u8, &original.digest, &changed.digest));
}

fn catalogMutations(a: std.mem.Allocator, store: *const stage.Store, program: language.typed.Program, catalog: *const lowering.Catalog) !void {
    const original = try catalogEquivalent(store, program, null, catalog);
    const functions = try a.dupe(language.typed.Function, program.functions);
    var changed = program;
    changed.functions = functions;
    functions[0].signature.return_type = .bool;
    try changedCatalog(store, original, changed, catalog);
    functions[0] = program.functions[0];
    // The source effect policy was retired; the live Core allocation promise
    // must still invalidate the checked declaration catalog.
    try std.testing.expect(functions[0].policy.noalloc == null);
    functions[0].policy.noalloc = functions[0].declaration;
    try changedCatalog(store, original, changed, catalog);
    functions[0] = program.functions[0];
    functions[0].signature.constant_arguments = &.{1};
    try changedCatalog(store, original, changed, catalog);
    changed = program;
    const records = try a.dupe(language.typed.Record, program.records);
    changed.records = records;
    records[0].name = "changed nominal declaration";
    try changedCatalog(store, original, changed, catalog);
    records[0] = program.records[0];
    const fields = try a.dupe(language.typed.Field, records[0].fields);
    try std.testing.expect(fields.len > 0 and fields[0].default_value != null);
    records[0].fields = fields;
    fields[0].default_value = null;
    try changedCatalog(store, original, changed, catalog);
    // Separate table storage is a new snapshot even when its catalog bytes agree.
    changed = program;
    changed.nodes = try a.dupe(language.typed.Node, program.nodes);
    const copied = try catalogEquivalent(store, changed, null, catalog);
    try std.testing.expect(!copied.reused);
    try std.testing.expectEqualSlices(u8, &original.digest, &copied.digest);
    changed = program;
    changed.functions = functions[0 .. functions.len - 1];
    try changedCatalog(store, original, changed, catalog);
}

// spec-case: NEW-CORE-TEST-FACTS-1
// spec-case: NEW-CORE-STAGE-CACHE-3
test "shared checked catalog rejects changed signatures effects defaults records and table snapshots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var unit = try language.Compilation.init(a, source_name, catalog_record);
    defer unit.deinit();
    try unit.check();
    const catalog = try lowering.Catalog.prepare(unit.program.?);
    try std.testing.expect(catalog.matches(unit.program.?));
    try catalogMutations(a, &store, unit.program.?, &catalog);
}

// spec-case: NEW-CORE-TEST-FACTS-1
// spec-case: NEW-CORE-STAGE-CACHE-3
test "shared checked catalog replays ordinary lowering artifacts including record defaults and generic calls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var unit = try language.Compilation.init(a, source_name, catalog_record);
    defer unit.deinit();
    try unit.check();
    const input: build.Input = .{ .program = unit.program.?, .source = unit.src };
    var refusal: build.Refusal = .{};
    var ordinary = lowering.Cache.init(&store);
    const first = try build.buildExecutableCached(a, input, &refusal, &ordinary);
    try std.testing.expect(ordinary.counts.lowered > 0);
    const catalog = try lowering.Catalog.prepare(unit.program.?);
    var shared = lowering.Cache.init(&store);
    shared.catalog.known = &catalog;
    const second = try build.buildExecutableCached(a, input, &refusal, &shared);
    try std.testing.expect(shared.catalog.reused);
    try std.testing.expectEqual(@as(usize, 0), shared.counts.lowered);
    try std.testing.expectEqual(ordinary.counts.lowered, shared.counts.reused);
    const fresh = try build.buildExecutable(a, input, &refusal);
    try sameModule(a, &second, &first);
    try sameModule(a, &second, &fresh);
}

// spec-case: NEW-CORE-STAGE-CACHE-3
/// Whether `keys` name the full artifact of every function `lazy` restored from a header.
fn namesEveryHandle(lazy: *const lowering.Deferred, keys: []const stage.Digest) bool {
    for (lazy.tables.handles.items) |maybe| {
        const handle = maybe orelse continue;
        var found = false;
        for (keys) |key| found = found or std.mem.eql(u8, &key, &handle.key);
        if (!found) return false;
    }
    return true;
}

test "demand raw headers materialize only requested bodies and reject lost payloads" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    _ = try compare(root, std.testing.allocator, arithmetic, false);
    var unit = try language.Compilation.init(a, source_name, arithmetic);
    defer unit.deinit();
    try unit.check();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var lazy: lowering.Deferred = .{ .arena = a, .store = &store };
    var cache = lowering.Cache.init(&store);
    cache.lazy = &lazy;
    var refusal: build.Refusal = .{};
    const input: build.Input = .{ .program = unit.program.?, .source = unit.src };
    var module = try build.buildExecutableCached(a, input, &refusal, &cache);
    try lazy.prepare(&module, unit.src);
    try std.testing.expectEqual(@as(usize, 0), lazy.restored);
    try std.testing.expectEqual(@as(usize, 3), cache.counts.reused);
    // A function restored from its header alone is still one this build needs in full: its artifact is among the build's roots,
    // or compaction would drop it while the next build's receipts still say the body may be omitted.
    try std.testing.expect(namesEveryHandle(&lazy, try store.touchedKeys(a)));
    try std.testing.expectEqual(@as(usize, 0), module.functions.items[module.entry].insts.items.len);
    try lazy.context.ensure(module.entry);
    try std.testing.expectEqual(@as(usize, 1), lazy.restored);
    try std.testing.expect(module.functions.items[module.entry].insts.items.len > 0);
    try lazy.context.ensure(module.entry);
    try std.testing.expectEqual(@as(usize, 1), lazy.restored);
    for (0..module.functions.items.len) |index| try lazy.context.ensure(@intCast(index));
    const fresh = try build.buildExecutable(a, input, &refusal);
    try sameModule(a, &module, &fresh);

    var lost: lowering.Deferred = .{ .arena = a, .store = &store };
    cache.lazy = &lost;
    var replayed = try build.buildExecutableCached(a, input, &refusal, &cache);
    try lost.prepare(&replayed, unit.src);
    try std.testing.expect(try stage_loss.damage(&store) > 0);
    try std.testing.expectError(error.CacheMiss, lost.context.ensure(replayed.entry));
    try std.testing.expect(!lost.tables.loaded.items[replayed.entry]);
}

const finish_helper =
    \\enum Tag:
    \\    atom(value: bytes)
    \\    other
    \\
    \\record Node:
    \\    tag: Tag
    \\
    \\func as_atom(n: Node) -> bytes? from n:
    \\    match n.tag:
    \\        case atom(value=a):
    \\            return Some(a)
    \\        case _:
    \\            return None
    \\
    \\func probe(nodes: Node[]) -> bool:
    \\    for node in nodes:
    \\        const head = copy(as_atom(node).unwrap_or(b""))
    \\        if head == b"ab":
    \\            return True
    \\    return False
    \\
    \\func slice_probe(s: str) -> bool:
    \\    return s[0:1] == "x"
    \\
    \\func idle() -> int:
    \\    return 1
    \\
    \\func main() -> int:
    \\    if slice_probe("xy") and probe([Node(tag=Tag.atom(value=b"ab"))]):
    \\        return idle()
    \\    return 0
;

// spec-case: NEW-CORE-STAGE-CACHE-3
test "demand raw headers declare the runtime helpers of deferred bodies in the eager order" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    _ = try compare(root, std.testing.allocator, finish_helper, false);
    var unit = try language.Compilation.init(a, source_name, finish_helper);
    defer unit.deinit();
    try unit.check();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var refusal: build.Refusal = .{};
    const input: build.Input = .{ .program = unit.program.?, .source = unit.src };
    const fresh = try build.buildExecutable(a, input, &refusal);
    // The last span equality is declared by `probe`'s local normalization, after lowering.
    const helper = lastNamed(&fresh, "myl_core_span_eq");
    try std.testing.expect(helper != null);
    var lazy: lowering.Deferred = .{ .arena = a, .store = &store };
    var cache = lowering.Cache.init(&store);
    cache.lazy = &lazy;
    var module = try build.buildExecutableCached(a, input, &refusal, &cache);
    // Before any optimizer work, the demand table already matches the eager one.
    try std.testing.expectEqual(fresh.functions.items.len, module.functions.items.len);
    try std.testing.expectEqualStrings("myl_core_span_eq", module.functions.items[helper.?].name);
    try lazy.prepare(&module, unit.src);
    // `probe` was restored for its helper; the plain bodies stay deferred.
    try std.testing.expectEqual(@as(usize, 1), lazy.restored);
    try ensureAll(&lazy, &module);
    try sameModule(a, &module, &fresh);
    // A complete-tree (eager) build keys every raw body exactly as the demand build does, so the
    // optimizer shortcut's saved entries match across the two.
    var eager: lowering.Deferred = .{ .arena = a, .store = &store, .force_eager = true };
    cache.lazy = &eager;
    var complete = try build.buildExecutableCached(a, input, &refusal, &cache);
    try eager.prepare(&complete, unit.src);
    try std.testing.expectEqualDeep(lazy.tables.keys.items, eager.tables.keys.items);
}

fn indexNamed(module: *const ir.Module, name: []const u8) ?usize {
    for (module.functions.items, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, name)) return index;
    }
    return null;
}

/// The loads (hits and misses) the store tallied under `scope`.
fn scopeLoads(counts: []const stage_tally.ScopeCount, scope: []const u8) u64 {
    var loads: u64 = 0;
    for (counts) |count| {
        if (std.mem.eql(u8, count.scope, scope)) loads += count.hits + count.misses;
    }
    return loads;
}

// spec-case: NEW-CORE-STAGE-CACHE-3
test "a function's header says whether finishing its body declares a helper, and a build that defers the body reads no other record to learn it" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    _ = try compare(root, std.testing.allocator, finish_helper, false);
    var unit = try language.Compilation.init(a, source_name, finish_helper);
    defer unit.deinit();
    try unit.check();
    var store = try stage.Store.initWithOptions(std.testing.allocator, std.testing.io, root, .{ .observe = true });
    defer store.deinit();
    var lazy: lowering.Deferred = .{ .arena = a, .store = &store };
    var cache = lowering.Cache.init(&store);
    cache.lazy = &lazy;
    var refusal: build.Refusal = .{};
    const input: build.Input = .{ .program = unit.program.?, .source = unit.src };
    var module = try build.buildExecutableCached(a, input, &refusal, &cache);
    try lazy.prepare(&module, unit.src);
    // `idle` finishes without a helper and `probe` declares one: the headers of the first cold, lazy-less build said so.
    try std.testing.expectEqual(@as(?bool, true), lazy.tables.finish.items[indexNamed(&module, "idle").?].plain);
    try std.testing.expectEqual(@as(?bool, false), lazy.tables.finish.items[indexNamed(&module, "probe").?].plain);
    try std.testing.expectEqual(@as(usize, 1), lazy.restored);
    const counts = try store.tallies(a);
    try std.testing.expect(scopeLoads(counts, "lowered-header-source-v10") > 0);
    try std.testing.expectEqual(@as(u64, 0), scopeLoads(counts, "lowered-finish-v1"));
}

// spec-case: NEW-CORE-STAGE-CACHE-3
test "a build that ends before it finishes a body leaves its header without the flag, and the body counts as declaring a helper" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    _ = try compare(root, std.testing.allocator, finish_helper, false);
    var unit = try language.Compilation.init(a, source_name, finish_helper);
    defer unit.deinit();
    try unit.check();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    var refusal: build.Refusal = .{};
    const input: build.Input = .{ .program = unit.program.?, .source = unit.src };
    var warm: lowering.Deferred = .{ .arena = a, .store = &store };
    var cache = lowering.Cache.init(&store);
    cache.lazy = &warm;
    var module = try build.buildExecutableCached(a, input, &refusal, &cache);
    try warm.prepare(&module, unit.src);
    const probe = indexNamed(&module, "probe").?;
    try std.testing.expect(probe < indexNamed(&module, "idle").?);
    // `idle` is lowered anew below, after `probe` in the table, and `probe` (it declares a helper) is restored while its
    // body finishes: its stored artifact is gone, so the build ends there with `idle`'s finish still unknown.
    try stage_loss.remove(a, &store, warm.tables.handles.items[probe].?.key);
    const edited_source = try std.mem.replaceOwned(u8, a, finish_helper, "return 1", "return 2");
    var edited = try language.Compilation.init(a, source_name, edited_source);
    defer edited.deinit();
    try edited.check();
    var broken: lowering.Deferred = .{ .arena = a, .store = &store };
    cache.lazy = &broken;
    const edited_input: build.Input = .{ .program = edited.program.?, .source = edited.src };
    try std.testing.expectError(error.CacheMiss, build.buildExecutableCached(a, edited_input, &refusal, &cache));
    // A build with no deferred bodies lowers `probe` again and keeps the header of `idle` as the failed build left it.
    cache.lazy = null;
    _ = try build.buildExecutableCached(a, edited_input, &refusal, &cache);
    var later: lowering.Deferred = .{ .arena = a, .store = &store };
    cache.lazy = &later;
    var replayed = try build.buildExecutableCached(a, edited_input, &refusal, &cache);
    try later.prepare(&replayed, edited.src);
    try std.testing.expectEqual(@as(?bool, null), later.tables.finish.items[indexNamed(&replayed, "idle").?].plain);
    try std.testing.expectEqual(@as(?bool, false), later.tables.finish.items[indexNamed(&replayed, "probe").?].plain);
    // The header without a flag costs `idle` its deferral, nothing else: the module is the one a fresh lowering builds.
    try std.testing.expectEqual(@as(usize, 2), later.restored);
    const fresh = try build.buildExecutable(a, edited_input, &refusal);
    try ensureAll(&later, &replayed);
    try sameModule(a, &replayed, &fresh);
}

fn lastNamed(module: *const ir.Module, name: []const u8) ?usize {
    var found: ?usize = null;
    for (module.functions.items, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, name)) found = index;
    }
    return found;
}

fn ensureAll(lazy: *lowering.Deferred, module: *const ir.Module) !void {
    for (0..module.functions.items.len) |index| try lazy.context.ensure(@intCast(index));
}

/// Rename checked function `from` to `to` in place, giving two functions one name.
fn shareName(program: language.typed.Program, from: []const u8, to: []const u8) void {
    const functions = @constCast(program.functions);
    for (functions) |*function| {
        if (std.mem.eql(u8, function.name, from)) function.name = to;
    }
}

// spec: NEW-CORE-STAGE-CACHE-3
test "lowered function artifacts survive new sessions, local edits and source shifts" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    try std.testing.expectEqualDeep(Work{ .lowered = 3, .reused = 0 }, try compare(root, std.testing.allocator, arithmetic, false));
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 3 }, try compare(root, std.testing.allocator, arithmetic, false));
    const edited = try std.testing.allocator.dupe(u8, arithmetic);
    defer std.testing.allocator.free(edited);
    edited[std.mem.indexOf(u8, edited, "+ 1").? + 2] = '2';
    try std.testing.expectEqualDeep(Work{ .lowered = 1, .reused = 2 }, try compare(root, std.testing.allocator, edited, false));
    const shifted = try std.mem.concat(std.testing.allocator, u8, &.{ "\n\n", edited });
    defer std.testing.allocator.free(shifted);
    const moved = try compare(root, std.testing.allocator, shifted, false);
    try std.testing.expectEqual(@as(usize, 3), moved.lowered + moved.reused);
    try std.testing.expect(moved.reused >= 2);
    const ids = try std.mem.concat(std.testing.allocator, u8, &.{ "record Earlier:\n    value: int\nfunc unused() -> int:\n    return 9\n\n", shifted });
    defer std.testing.allocator.free(ids);
    // Earlier declarations shift indices. Only a function that names a shifted declaration is lowered again;
    // compare checks every served module against a fresh build, so the reuse is verified, not assumed.
    const shifted_ids = try compare(root, std.testing.allocator, ids, false);
    try std.testing.expectEqual(@as(usize, 3), shifted_ids.lowered + shifted_ids.reused);
    try std.testing.expect(shifted_ids.reused >= 1);
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 3 }, try compare(root, std.testing.allocator, ids, false));
    try std.testing.expectEqualDeep(Work{ .lowered = 3, .reused = 0 }, try compare(root, std.testing.allocator, ids, true));
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 3 }, try compare(root, std.testing.allocator, ids, true));
}

const states_source =
    \\record Item:
    \\    n: int
    \\record Wide:
    \\    a: int
    \\    b: int
    \\func make_items() -> int:
    \\    const items: Item[] = [Item(n=1), Item(n=2)]
    \\    return len(items)
    \\func make_wides() -> int:
    \\    const wides: Wide[] = [Wide(a=1, b=2)]
    \\    return len(wides)
    \\func main() -> int:
    \\    return make_items() + make_wides()
    \\
;

// spec-case: NEW-CORE-STAGE-CACHE-3
test "a stored function restores into a module in another state and equals a fresh lowering there" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const a = std.testing.allocator;
    try std.testing.expectEqualDeep(Work{ .lowered = 3, .reused = 0 }, try compare(root, a, states_source, false));
    // The callees are lowered in the other order, so each meets the types the other made: only the entry point changed.
    const swapped = try std.mem.replaceOwned(u8, a, states_source, "make_items() + make_wides()", "make_wides() + make_items()");
    defer a.free(swapped);
    try std.testing.expectEqualDeep(Work{ .lowered = 1, .reused = 2 }, try compare(root, a, swapped, false));
    // One callee is gone: the other meets a module that holds fewer of the types and helpers it once found.
    const dropped = try std.mem.replaceOwned(u8, a, states_source, "make_items() + make_wides()", "make_wides()");
    defer a.free(dropped);
    try std.testing.expectEqualDeep(Work{ .lowered = 1, .reused = 1 }, try compare(root, a, dropped, false));
    // A record and a function that builds it come first, so every record the others read moves by one position, and the
    // module holds the new record's types before theirs.
    const earlier = try std.mem.concat(a, u8, &.{ "record Earlier:\n    z: int\nfunc use_earlier() -> int:\n    return Earlier(z=3).z\n", swapped });
    defer a.free(earlier);
    const used = try std.mem.replaceOwned(u8, a, earlier, "return make_wides() + make_items()", "return use_earlier() + make_wides() + make_items()");
    defer a.free(used);
    try std.testing.expectEqualDeep(Work{ .lowered = 2, .reused = 2 }, try compare(root, a, used, false));
    // An unused record inserted first changes nothing a function reads.
    const unused = try std.mem.concat(a, u8, &.{ "record Idle:\n    q: int\n", used });
    defer a.free(unused);
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 4 }, try compare(root, a, unused, false));
}

const unify_source =
    \\record Pair:
    \\    a: int
    \\    b: int
    \\func use_pair() -> int:
    \\    return Pair(a=1, b=2).a
    \\func change_pair(mut left: int, mut right: int) -> Unit:
    \\    left += 10
    \\    right += 20
    \\func main() -> int:
    \\    mut x = 1
    \\    mut y = 2
    \\    const first = use_pair()
    \\    change_pair(mut x, mut y)
    \\    return first + x + y
    \\
;

// spec-case: NEW-CORE-STAGE-CACHE-3
test "a mut return record that has the layout of a nominal record is unified exactly as a fresh lowering unifies it" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const a = std.testing.allocator;
    // The nominal record is reserved first, so the pair the mutating function returns is that record.
    const first = try compare(root, a, unify_source, false);
    try std.testing.expectEqual(@as(usize, 3), first.lowered);
    // The mutating function now comes first: its pair is structural and the record is reserved after it. The stored
    // function named the record, which this module lacks when it is restored, so it lowers again and equals a fresh one.
    const reordered = try std.mem.replaceOwned(u8, a, unify_source, "    const first = use_pair()\n    change_pair(mut x, mut y)\n", "    change_pair(mut x, mut y)\n    const first = use_pair()\n");
    defer a.free(reordered);
    const second = try compare(root, a, reordered, false);
    try std.testing.expectEqual(@as(usize, 3), second.lowered + second.reused);
    try std.testing.expect(second.reused >= 1);
    // Back to the first order: the function stored from the second names a structural pair, and meets the record.
    const third = try compare(root, a, unify_source, false);
    try std.testing.expectEqual(@as(usize, 3), third.lowered + third.reused);
    try std.testing.expect(third.reused >= 1);
}

// spec-case: NEW-CORE-STAGE-CACHE-3
test "lowered replay shifts later declarations and instructions after same file literal grows" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    try std.testing.expectEqualDeep(Work{ .lowered = 3, .reused = 0 }, try compare(root, std.testing.allocator, arithmetic, false));
    const at = std.mem.indexOf(u8, arithmetic, "+ 1").? + 2;
    const grown = try std.mem.concat(std.testing.allocator, u8, &.{ arithmetic[0..at], "10000", arithmetic[at + 1 ..] });
    defer std.testing.allocator.free(grown);
    try std.testing.expectEqualDeep(Work{ .lowered = 1, .reused = 2 }, try compare(root, std.testing.allocator, grown, false));
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 3 }, try compare(root, std.testing.allocator, grown, false));
}

const render_source =
    \\record Item:
    \\    n: int
    \\func keep(out: Stream) -> int:
    \\    print(out, Item(n=3))
    \\    assert True, "kept"
    \\    return 7
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, "start")
    \\    return keep(out)
    \\
;

// spec-case: NEW-CORE-STAGE-CACHE-3
test "lowering replay relocates string slots and compiler rendering authority names exactly" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    try std.testing.expectEqualDeep(Work{ .lowered = 2, .reused = 0 }, try compare(root, std.testing.allocator, render_source, false));
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 2 }, try compare(root, std.testing.allocator, render_source, false));
    const needle = "print(out, \"start\")";
    const at = std.mem.indexOf(u8, render_source, needle).?;
    const edited = try std.mem.concat(std.testing.allocator, u8, &.{ render_source[0..at], "print(out, \"longer\", \"prefix\")", render_source[at + needle.len ..] });
    defer std.testing.allocator.free(edited);
    try std.testing.expectEqualDeep(Work{ .lowered = 1, .reused = 1 }, try compare(root, std.testing.allocator, edited, false));
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 2 }, try compare(root, std.testing.allocator, edited, false));
}

// spec-case: NEW-CORE-STAGE-CACHE-3
test "damaged lowering entries miss without changing the uncached result" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    _ = try compare(root, std.testing.allocator, arithmetic, false);
    var storage = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer storage.deinit();
    try std.testing.expect(try stage_loss.damage(&storage) > 0);
    try std.testing.expectEqualDeep(Work{ .lowered = 3, .reused = 0 }, try compare(root, std.testing.allocator, arithmetic, false));
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 3 }, try compare(root, std.testing.allocator, arithmetic, false));
}

// spec-case: NEW-CORE-STAGE-CACHE-3
test "lowered generic and default bodies preserve mapped origins across another file growing" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const templates = "record Item:\n    value: int = 42\n\nfunc identity[T](x: T) -> T:\n    return x\n";
    const entry = "func main(out: Stream) -> int:\n    print(out, \"ready\")\n    return identity[int](Item().value)\n";
    try std.testing.expectEqualDeep(Work{ .lowered = 2, .reused = 0 }, try compareMapped(root, std.testing.allocator, templates, entry));
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 2 }, try compareMapped(root, std.testing.allocator, templates, entry));
    const grown = templates ++ "\n\n\n";
    // The file grew after the line of the default and the generic: the proofs of the main function cover the file only as far as
    // those lines, so nothing is lowered again (compareMapped checks the replay against a fresh lowering).
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 2 }, try compareMapped(root, std.testing.allocator, grown, entry));
    const edited = try std.testing.allocator.dupe(u8, grown);
    defer std.testing.allocator.free(edited);
    edited[std.mem.indexOf(u8, edited, "value: int = 42").? + 14] = '3';
    try std.testing.expectEqualDeep(Work{ .lowered = 1, .reused = 1 }, try compareMapped(root, std.testing.allocator, edited, entry));
    const moved = try std.mem.concat(std.testing.allocator, u8, &.{ "\n\n", edited });
    defer std.testing.allocator.free(moved);
    const result = try compareMapped(root, std.testing.allocator, moved, entry);
    try std.testing.expectEqual(@as(usize, 2), result.lowered + result.reused);
    try std.testing.expect(result.reused >= 1);
}

// spec-case: SEMANTIC-CACHE-9
test "core durable body retention fits project size with bounded saturating arithmetic" {
    var limits: @FieldType(language.semantic_cache.Store, "limits") = .{};
    const single = limits.max_entry_bytes;
    frontend_reuse.fitBodyStore(&limits, 0);
    try std.testing.expectEqual(@as(usize, 128 << 20), limits.max_bytes);
    try std.testing.expectEqual(@as(usize, 65536), limits.max_entries);
    frontend_reuse.fitBodyStore(&limits, 4 << 20);
    try std.testing.expectEqual(@as(usize, 256 << 20), limits.max_bytes);
    try std.testing.expectEqual(@as(usize, 1 << 20), limits.max_entries);
    frontend_reuse.fitBodyStore(&limits, std.math.maxInt(usize));
    try std.testing.expectEqual(@as(usize, 4) << 30, limits.max_bytes);
    try std.testing.expectEqual(@as(usize, 1 << 20), limits.max_entries);
    try std.testing.expectEqual(single, limits.max_entry_bytes);
}

fn compareRetainedLoops(root: []const u8, backing: std.mem.Allocator, semantic: *language.semantic_cache.Cache, bytes: []const u8) !Work {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var retained = try language.Compilation.init(a, source_name, bytes);
    defer retained.deinit();
    try retained.checkWithCache(semantic);
    var fresh = try language.Compilation.init(a, source_name, bytes);
    defer fresh.deinit();
    try fresh.check();
    var refusal: build.Refusal = .{};
    const retained_module = try build.buildExecutable(a, .{ .program = retained.program.?, .source = retained.src }, &refusal);
    const fresh_module = try build.buildExecutable(a, .{ .program = fresh.program.?, .source = fresh.src }, &refusal);
    try sameModule(a, &retained_module, &fresh_module);
    return compareChecked(root, backing, a, &retained, false);
}

// spec-case: NEW-CORE-STAGE-CACHE-3
// spec-case: SEMANTIC-CACHE-6
test "function local loop IDs preserve exact retained CoreIR after preceding loops change" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    var semantic = language.semantic_cache.Cache.init(std.testing.allocator, 4 << 20);
    defer semantic.deinit();
    const head =
        \\func first(n: int) -> int:
        \\    mut i = 0
        \\    while i < n:
        \\        i += 1
        \\    return i
        \\
    ;
    const tail =
        \\func nested(n: int) -> int:
        \\    mut total = 0
        \\    for i in range(n):
        \\        for j in range(n):
        \\            if j == 1:
        \\                continue
        \\            total += i + j
        \\            if total > 100:
        \\                break
        \\    return total
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, "loops")
        \\    return nested(first(3))
        \\
    ;
    try std.testing.expectEqualDeep(Work{ .lowered = 3, .reused = 0 }, try compareRetainedLoops(root, std.testing.allocator, &semantic, head ++ tail));
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 3 }, try compareRetainedLoops(root, std.testing.allocator, &semantic, head ++ tail));
    const changed_head =
        \\func first(n: int) -> int:
        \\    mut i = 0
        \\    for ignored in range(1):
        \\        while i < n:
        \\            i += 1
        \\    return i
        \\
    ;
    try std.testing.expectEqualDeep(Work{ .lowered = 1, .reused = 2 }, try compareRetainedLoops(root, std.testing.allocator, &semantic, changed_head ++ tail));
    try std.testing.expect(semantic.statistics.reused >= 2);
    // A separate fresh frontend must hit those same durable raw artifacts.
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 3 }, try compare(root, std.testing.allocator, changed_head ++ tail, false));
}

// twin-drift-ok: this independently restores demand headers before comparing with the eager builder; compareMapped seeds the eager artifacts used by these tests.
fn compareDemandMapped(root: []const u8, backing: std.mem.Allocator, left: []const u8, right: []const u8) !Work {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const sources = [_]language.source.Source{
        try language.source.Source.init(a, "templates.selka", left),
        try language.source.Source.init(a, "entry.selka", right),
    };
    const merged = try language.source.Source.initMapped(a, &sources);
    var unit = try language.Compilation.init(a, merged.path, merged.bytes);
    defer unit.deinit();
    unit.src = merged;
    try unit.check();
    var store = try stage.Store.init(backing, std.testing.io, root);
    defer store.deinit();
    var lazy: lowering.Deferred = .{ .arena = a, .store = &store };
    var cache = lowering.Cache.init(&store);
    cache.lazy = &lazy;
    var refusal: build.Refusal = .{};
    const input: build.Input = .{ .program = unit.program.?, .source = unit.src };
    var module = try build.buildExecutableCached(a, input, &refusal, &cache);
    try lazy.prepare(&module, unit.src);
    try std.testing.expectEqual(@as(usize, 0), lazy.restored);
    for (0..module.functions.items.len) |index| try lazy.context.ensure(@intCast(index));
    try std.testing.expectEqual(cache.counts.reused, lazy.restored);
    const fresh = try build.buildExecutable(a, input, &refusal);
    try sameModule(a, &module, &fresh);
    return .{ .lowered = cache.counts.lowered, .reused = cache.counts.reused };
}

const demand_entry = "func main(out: Stream) -> int:\n    print(out, \"before\")\n    return helper(out)\n";
const demand_helper = "func helper(out: Stream) -> int:\n    print(out, \"helper payload\")\n    return 42\n";

// spec-case: NEW-CORE-STAGE-CACHE-3
test "demand raw headers preserve mapped source positions after preceding file grows" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    _ = try compareMapped(root, std.testing.allocator, demand_entry, demand_helper);
    const work = try compareDemandMapped(root, std.testing.allocator, demand_entry ++ "\n\n\n", demand_helper);
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 2 }, work);
}

// spec-case: NEW-CORE-STAGE-CACHE-3
test "demand raw headers relocate strings after preceding function adds a string" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    _ = try compareMapped(root, std.testing.allocator, demand_entry, demand_helper);
    const edited = "func main(out: Stream) -> int:\n    print(out, \"before\")\n    print(out, \"new neighbor string\")\n    return helper(out)\n";
    const work = try compareDemandMapped(root, std.testing.allocator, edited, demand_helper);
    try std.testing.expectEqualDeep(Work{ .lowered = 1, .reused = 1 }, work);
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "raw source prefix retains unrelated same file edits but catches equal length newlines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try language.source.Source.init(a, "sites.selka", "func owner():\n    x = 1\nother 2\n");
    const unrelated = try language.source.Source.init(a, "sites.selka", "func owner():\n    x = 1\nother 3\n");
    const newline = try language.source.Source.init(a, "sites.selka", "func owner():\n\n   x = 1\nother 2\n");
    const maximum: u32 = 21;
    const proof = try lowering.sourceProof(original, 0, maximum);
    try std.testing.expectEqual(proof, try lowering.sourceProof(unrelated, 0, maximum));
    try std.testing.expect(!std.mem.eql(u8, &proof, &try lowering.sourceProof(newline, 0, maximum)));
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "raw source prefix catches declaration line column and path movement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try language.source.Source.init(a, "sites.selka", "func owner():\n    x = 1\n");
    const later_line = try language.source.Source.init(a, "sites.selka", "\nfunc owner():\n    x = 1\n");
    const later_column = try language.source.Source.init(a, "sites.selka", " func owner():\n    x = 1\n");
    const renamed = try language.source.Source.init(a, "renamed.selka", original.bytes);
    const proof = try lowering.sourceProof(original, 0, 21);
    const others = [_]stage.Digest{
        try lowering.sourceProof(later_line, 1, 21),
        try lowering.sourceProof(later_column, 1, 21),
        try lowering.sourceProof(renamed, 0, 21),
    };
    for (others) |other| try std.testing.expect(!std.mem.eql(u8, &proof, &other));
}

/// The digest of a source proof's byte stream written out in full: the prefix, the maximum, the line, the column, the key path, a zero byte and the span.
fn referenceProof(a: std.mem.Allocator, source: language.source.Source, span: u32, maximum: u32) !stage.Digest {
    const point = source.physicalLocation(span);
    var stream: std.ArrayList(u8) = .empty;
    try stream.appendSlice(a, "lowered-local-source-v2\x00");
    try stream.appendSlice(a, &std.mem.toBytes(std.mem.nativeToLittle(u32, maximum)));
    try stream.appendSlice(a, &std.mem.toBytes(std.mem.nativeToLittle(u64, point.line)));
    try stream.appendSlice(a, &std.mem.toBytes(std.mem.nativeToLittle(u64, point.column)));
    try stream.appendSlice(a, source.keyPath());
    try stream.append(a, 0);
    try stream.appendSlice(a, source.bytes[span..][0..maximum]);
    var digest: stage.Digest = undefined;
    @import("fast_blake3.zig").hash(stream.items, &digest);
    return digest;
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "G3p-r11 source proof: the digest is the hash of the whole byte stream, for a key path that fits the head buffer and for one that does not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = "func owner():\n    x = 1\n";
    const short = try language.source.Source.init(a, "sites.selka", bytes);
    const filler = try a.alloc(u8, 600);
    @memset(filler, 'd');
    const long_path = try std.fmt.allocPrint(a, "{s}/sites.selka", .{filler});
    const long = try language.source.Source.init(a, long_path, bytes);
    try std.testing.expect(long_path.len > 512);
    try std.testing.expectEqual(try referenceProof(a, short, 0, 21), try lowering.sourceProof(short, 0, 21));
    try std.testing.expectEqual(try referenceProof(a, short, 14, 7), try lowering.sourceProof(short, 14, 7));
    try std.testing.expectEqual(try referenceProof(a, long, 0, 21), try lowering.sourceProof(long, 0, 21));
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "raw source prefix rejects malformed bounds and binds the maximum" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try language.source.Source.init(a, "sites.selka", "func owner():\n    x = 1\n");
    try std.testing.expectError(error.InvalidSnapshot, lowering.sourceProof(source, 0, std.math.maxInt(u32)));
    try std.testing.expectError(error.InvalidSnapshot, lowering.sourceProof(source, @intCast(source.bytes.len + 1), 0));
    const complete = try lowering.sourceProof(source, 0, 21);
    const understated = try lowering.sourceProof(source, 0, 0);
    try std.testing.expect(!std.mem.eql(u8, &complete, &understated));
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "raw source authority prepares omitted instruction standins without reading a body" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try stage.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const source = try language.source.Source.init(a, "sites.selka", "func owner():\n    x = 1\n");
    var module: ir.Module = .{};
    try module.functions.append(a, .{ .name = "owner", .signature = .{ .params = &.{}, .ret = .i64, .linkage = .internal }, .span = 0 });
    var deferred: lowering.Deferred = .{ .arena = a, .store = &storage };
    try deferred.tables.keys.append(a, storage.key("typed-semantic", &.{}));
    try deferred.tables.source_max.append(a, 21);
    try deferred.tables.handles.append(a, null);
    try deferred.tables.loaded.append(a, false);
    try deferred.prepare(&module, source);
    try std.testing.expect(deferred.context.keys[0] != null);
    try std.testing.expect(!deferred.context.loaded[0]);
    try std.testing.expectEqual(@as(usize, 0), module.functions.items[0].insts.items.len);
    try std.testing.expectEqual(@as(usize, 0), deferred.restored);
}

fn preparedSourceKeys(a: std.mem.Allocator, backing: std.mem.Allocator, root: []const u8, bytes: []const u8) ![]const ?stage.Digest {
    var unit = try language.Compilation.init(a, source_name, bytes);
    defer unit.deinit();
    try unit.check();
    var storage = try stage.Store.init(backing, std.testing.io, root);
    defer storage.deinit();
    var deferred: lowering.Deferred = .{ .arena = a, .store = &storage };
    var cache = lowering.Cache.init(&storage);
    cache.lazy = &deferred;
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutableCached(a, .{ .program = unit.program.?, .source = unit.src }, &refusal, &cache);
    try deferred.prepare(&module, unit.src);
    return a.dupe(?stage.Digest, deferred.context.keys);
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "raw demand source keys retain unchanged function across same file literal edits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const before = "func helper() -> int:\n    return 7\nfunc main() -> int:\n    return helper() + 1\n";
    const after = "func helper() -> int:\n    return 7\nfunc main() -> int:\n    return helper() + 2\n";
    const cold = try preparedSourceKeys(a, std.testing.allocator, root, before);
    const warm = try preparedSourceKeys(a, std.testing.allocator, root, before);
    const edited = try preparedSourceKeys(a, std.testing.allocator, root, after);
    try std.testing.expectEqualDeep(cold, warm);
    try std.testing.expectEqual(cold[1], edited[1]);
    try std.testing.expect(!std.mem.eql(u8, &cold[0].?, &edited[0].?));
}

const SourceRun = struct { keys: []const ?stage.Digest, headers: []const ?stage.Digest, omitted: usize, allocation_warnings: []const u8 };

fn frontendSourceKeys(a: std.mem.Allocator, backing: std.mem.Allocator, root: []const u8) !SourceRun {
    const front = @import("frontend.zig");
    const queries = @import("lowering_demand.zig");
    const cache_root = try std.fs.path.join(a, &.{ root, "cache" });
    var storage = try stage.Store.init(backing, std.testing.io, cache_root);
    defer storage.deinit();
    var demand = try queries.Context.init(a, &storage, false);
    var session = front.Session.init(backing, std.testing.io, root);
    defer session.deinit();
    try session.enableCache(backing, cache_root);
    session.configureDemand(demand.callback());
    var diagnostics: std.ArrayList(u8) = .empty;
    const checked = try session.check(a, "main", &diagnostics);
    const state = session.demandState().?;
    demand.attach(state.prepared, state.omitted);
    var deferred: lowering.Deferred = .{ .arena = a, .store = &storage };
    var cache = lowering.Cache.init(&storage);
    cache.demand = &demand;
    cache.lazy = &deferred;
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutableCached(a, .{ .program = checked.program, .source = checked.src }, &refusal, &cache);
    const headers = try a.alloc(?stage.Digest, deferred.tables.keys.items.len);
    for (headers, deferred.tables.keys.items) |*header, raw| header.* = if (raw) |key| storage.key("lowered-header-source-v10", &.{&key}) else null;
    try deferred.prepare(&module, checked.src);
    const keys = try a.dupe(?stage.Digest, deferred.context.keys);
    // Materialize only after recording compact authority, then compare replay
    // from genuinely omitted typed bodies with an independent complete check.
    for (0..module.functions.items.len) |index| try deferred.context.ensure(@intCast(index));
    var eager = front.Session.init(backing, std.testing.io, root);
    defer eager.deinit();
    const fresh = try eager.check(a, "main", &diagnostics);
    try std.testing.expectEqualStrings(fresh.allocation_warnings, checked.allocation_warnings);
    const expected = try build.buildExecutable(a, .{ .program = fresh.program, .source = fresh.src }, &refusal);
    try sameModule(a, &module, &expected);
    try demand.finish();
    return .{ .keys = keys, .headers = headers, .omitted = demand.count(), .allocation_warnings = checked.allocation_warnings };
}

/// Compare cached demand checks and eager checks after an allocation refusal.
fn frontendSourceRefusal(a: std.mem.Allocator, backing: std.mem.Allocator, root: []const u8, cached: bool) ![]const u8 {
    const front = @import("frontend.zig");
    const queries = @import("lowering_demand.zig");
    const cache_root = try std.fs.path.join(a, &.{ root, "cache" });
    var storage = try stage.Store.init(backing, std.testing.io, cache_root);
    defer storage.deinit();
    var demand = try queries.Context.init(a, &storage, false);
    var session = front.Session.init(backing, std.testing.io, root);
    defer session.deinit();
    if (cached) {
        try session.enableCache(backing, cache_root);
        session.configureDemand(demand.callback());
    }
    var diagnostics: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.SourceError, session.check(a, "main", &diagnostics));
    return diagnostics.items;
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "demand frontend keeps allocation bounded transitive callees concrete after edits and reordering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    // The bounded closure lives in `core`; `side` is a module `core` does not import, so its body is a genuine omission.
    const bounded = "@noalloc\npublic func bounded(mut values: int[]) -> Unit:\n    middle(mut values)\n";
    const middle = "func middle(mut values: int[]) -> Unit:\n    deep(mut values)\n";
    const pure = "func deep(mut values: int[]) -> Unit:\n    _ = values[0]\n";
    const allocating = "func deep(mut values: int[]) -> Unit:\n    append(mut values, 42)\n";
    const entry = "import core\nimport side\n\nfunc main() -> int:\n    mut values = [1, 2]\n    core.bounded(mut values)\n    return side.spare() - 7\n";
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = entry });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "side.selka", .data = "public func spare() -> int:\n    return 7\n" });
    const before = try std.mem.concat(a, u8, &.{ bounded, middle, pure });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "core.selka", .data = before });
    const cold = try frontendSourceKeys(a, std.testing.allocator, root);
    try std.testing.expectEqualStrings("", cold.allocation_warnings);
    const warm = try frontendSourceKeys(a, std.testing.allocator, root);
    try std.testing.expect(warm.omitted > 0);
    const after = try std.mem.concat(a, u8, &.{ allocating, middle, bounded });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "core.selka", .data = after });
    const changed = try frontendSourceRefusal(a, std.testing.allocator, root, true);
    const changed_warm = try frontendSourceRefusal(a, std.testing.allocator, root, true);
    const eager = try frontendSourceRefusal(a, std.testing.allocator, root, false);
    try std.testing.expect(std.mem.indexOf(u8, changed, "E_NOALLOC_ALLOCATES") != null);
    try std.testing.expectEqualStrings(eager, changed);
    try std.testing.expectEqualStrings(eager, changed_warm);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "core.selka", .data = before });
    const recovered = try frontendSourceKeys(a, std.testing.allocator, root);
    try std.testing.expectEqualStrings("", recovered.allocation_warnings);
    try std.testing.expect(recovered.omitted > 0);
}

const source_proof_before = "func helper() -> int:\n    return 7\n\nfunc main() -> int:\n    return helper() + 1\n";
const source_proof_after = "func helper() -> int:\n    return 7\n\nfunc main() -> int:\n    return helper() + 2\n";

// spec-case: NEW-CORE-STAGE-CACHE-1
test "raw source authority preserves genuine omitted frontend bodies after unrelated edits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = source_proof_before });
    const cold = try frontendSourceKeys(a, std.testing.allocator, root);
    const warm = try frontendSourceKeys(a, std.testing.allocator, root);
    try std.testing.expect(warm.omitted > 0);
    try std.testing.expectEqualDeep(cold.keys, warm.keys);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = source_proof_after });
    const edited = try frontendSourceKeys(a, std.testing.allocator, root);
    try std.testing.expect(edited.omitted > 0);
    try std.testing.expectEqual(warm.keys[1], edited.keys[1]);
    try std.testing.expect(!std.mem.eql(u8, &warm.keys[0].?, &edited.keys[0].?));
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "raw source authority demotes valid checksum understated header maxima" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = source_proof_before });
    _ = try frontendSourceKeys(a, std.testing.allocator, root);
    const warm = try frontendSourceKeys(a, std.testing.allocator, root);
    var storage = try stage.Store.init(std.testing.allocator, std.testing.io, try std.fs.path.join(a, &.{ root, "cache" }));
    defer storage.deinit();
    const header = (try storage.load(a, warm.headers[1].?)).?;
    // The header ends with the maximum local position (an optional u32), the digest of the artifact and the digest of its effects.
    const maximum = header.len - 64;
    try std.testing.expectEqual(@as(u8, 1), header[maximum - 5]);
    @memset(header[maximum - 4 .. maximum], 0);
    // save recomputes the physical checksum; this is malformed metadata rather
    // than an ordinary damaged-record miss.
    try std.testing.expect(try storage.save(warm.headers[1].?, header));
    const damaged = try frontendSourceKeys(a, std.testing.allocator, root);
    try std.testing.expect(!std.mem.eql(u8, &warm.keys[1].?, &damaged.keys[1].?));
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "raw source authority maps independent original files and bounds each prefix" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const originals = [_]language.source.Source{
        try language.source.Source.init(a, "first.selka", "first\n"),
        try language.source.Source.init(a, "second.selka", "func owner():\n    x = 1\n"),
    };
    const mapped = try language.source.Source.initMapped(a, &originals);
    const start: u32 = @intCast(std.mem.indexOf(u8, mapped.bytes, "func owner").?);
    try std.testing.expectEqual(try lowering.sourceProof(originals[1], 0, 21), try lowering.sourceProof(mapped, start, 21));
    try std.testing.expectError(error.InvalidSnapshot, lowering.sourceProof(mapped, start, @intCast(originals[1].bytes.len + 1)));
}

// spec-case: NEW-CORE-STAGE-CACHE-3
test "raw source authority keeps conservative mapped default initializer replay" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const templates = "record Item:\n    value: int = 42\n";
    const entry = "func main() -> int:\n    return Item().value\n";
    _ = try compareMapped(root, std.testing.allocator, templates, entry);
    const warm = try compareDemandMapped(root, std.testing.allocator, templates, entry);
    try std.testing.expectEqual(@as(usize, 0), warm.lowered);
    // Moving a default initializer's original site cannot be attested from
    // the caller's local prefix: full typed replay remains the safe path.
    const moved = try compareDemandMapped(root, std.testing.allocator, "\n" ++ templates, entry);
    try std.testing.expect(moved.lowered > 0);
    const changed = try compareDemandMapped(root, std.testing.allocator, "record Item:\n    value: int = 43\n", entry);
    try std.testing.expect(changed.lowered > 0);
}

// spec-case: NEW-CORE-STAGE-CACHE-3
test "demand frontend proves external default source files before omitting checked bodies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const entry = "import model as m\nfunc helper() -> int:\n    return m.Item().value\nfunc main() -> int:\n    return helper()\n";
    const model = "public record Item:\n    value: int = 42\n";
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = entry });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "model.selka", .data = model });
    _ = try frontendSourceKeys(a, std.testing.allocator, root);
    const warm = try frontendSourceKeys(a, std.testing.allocator, root);
    try std.testing.expect(warm.omitted > 0);
    // The body digest and debug locations remain reusable while every external
    // original file agrees with the receipt; file growth rejects that proof.
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "model.selka", .data = "\n" ++ model });
    const moved = try frontendSourceKeys(a, std.testing.allocator, root);
    try std.testing.expectEqual(@as(usize, 0), moved.omitted);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "model.selka", .data = "public record Item:\n    value: int = 43\n" });
    const changed = try frontendSourceKeys(a, std.testing.allocator, root);
    try std.testing.expectEqual(@as(usize, 0), changed.omitted);
    const changed_warm = try frontendSourceKeys(a, std.testing.allocator, root);
    try std.testing.expect(changed_warm.omitted > 0);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "extra.selka", .data = "# unrelated source\n" });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = "import extra\n" ++ entry });
    // A module added in front of the others moves every file's index in the merged source. The proofs name files by path, so
    // the receipt of the function whose default lives in model.selka is still admitted (the helper compares the replay with a
    // complete check and lowering, so the omission is exact).
    const reordered = try frontendSourceKeys(a, std.testing.allocator, root);
    try std.testing.expect(reordered.omitted > 0);
}

// spec-case: NEW-CORE-STAGE-CACHE-3
test "external source authority names files by path and covers a file only as far as its last position" {
    const sources = @import("demand_sources.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first = try language.source.Source.init(a, "first.selka", "first line\nsecond line\nthird line\n");
    const second = try language.source.Source.init(a, "second.selka", "second\n");
    var cache: sources.Cache = .{ .arena = a };
    cache.bind(try language.source.Source.initMapped(a, &.{ first, second }));
    // A position on the second line of first.selka: the proof covers the file up to the end of that line and no further.
    var reach: sources.Reach = .{};
    try std.testing.expect(try cache.collect(&reach, .{ .origin = "first.selka", .offset = 0, .point = .{ .line = 2, .column = 3 } }));
    try std.testing.expect(try cache.collect(&reach, .{ .origin = "first.selka", .offset = 0, .point = .{ .line = 1, .column = 1 } }));
    const proofs = (try cache.seal(&reach)).?;
    try std.testing.expectEqual(@as(usize, 1), proofs.len);
    try std.testing.expectEqualStrings("first.selka", proofs[0].path);
    try std.testing.expectEqual(@as(u32, "first line\nsecond line\n".len), proofs[0].length);
    try std.testing.expect(try cache.matches(proofs));
    // Another module in front, or the modules in the other order: the file is found by its path.
    const added = try language.source.Source.init(a, "added.selka", "added\n");
    cache.bind(try language.source.Source.initMapped(a, &.{ second, added, first }));
    try std.testing.expect(try cache.matches(proofs));
    // An edit after the last position leaves the proof; an edit before it, or in it, breaks it.
    const appended = try language.source.Source.init(a, "first.selka", "first line\nsecond line\nthird line\nfourth\n");
    cache.bind(try language.source.Source.initMapped(a, &.{ appended, second }));
    try std.testing.expect(try cache.matches(proofs));
    const edited_third = try language.source.Source.init(a, "first.selka", "first line\nsecond line\nthird LINE\n");
    cache.bind(try language.source.Source.initMapped(a, &.{ edited_third, second }));
    try std.testing.expect(try cache.matches(proofs));
    const edited_second = try language.source.Source.init(a, "first.selka", "first line\nsecond LINE\nthird line\n");
    cache.bind(try language.source.Source.initMapped(a, &.{ edited_second, second }));
    try std.testing.expect(!try cache.matches(proofs));
    const shorter = try language.source.Source.init(a, "first.selka", "first line\n");
    cache.bind(try language.source.Source.initMapped(a, &.{ shorter, second }));
    try std.testing.expect(!try cache.matches(proofs));
    // A renamed file, a program without the file, and a path two modules share are no authority.
    const renamed = try language.source.Source.init(a, "renamed.selka", first.bytes);
    cache.bind(try language.source.Source.initMapped(a, &.{ renamed, second }));
    try std.testing.expect(!try cache.matches(proofs));
    cache.bind(first);
    try std.testing.expect(try cache.matches(proofs));
    cache.bind(second);
    try std.testing.expect(!try cache.matches(proofs));
    cache.bind(try language.source.Source.initMapped(a, &.{ first, first }));
    try std.testing.expect(!try cache.matches(proofs));
    // A position that names no file, or is outside the file, cannot be proven.
    cache.bind(try language.source.Source.initMapped(a, &.{ first, second }));
    var lost: sources.Reach = .{};
    try std.testing.expect(!try cache.collect(&lost, .{ .origin = "missing.selka", .offset = 0, .point = .{ .line = 1, .column = 1 } }));
    try std.testing.expect(!try cache.collect(&lost, .{ .origin = "first.selka", .offset = 0, .point = .{ .line = 9, .column = 1 } }));
    try std.testing.expect(!try cache.collect(&lost, .{ .origin = null, .offset = 0, .point = .{ .line = 1, .column = 1 } }));
    // The proofs of a longer reach cover those of a shorter one, and not the other way.
    var longer: sources.Reach = .{};
    try std.testing.expect(try cache.collect(&longer, .{ .origin = "first.selka", .offset = 0, .point = .{ .line = 3, .column = 1 } }));
    const covering = (try cache.seal(&longer)).?;
    try std.testing.expect(sources.Cache.covers(covering, proofs));
    try std.testing.expect(!sources.Cache.covers(proofs, covering));
}

// spec-case: NEW-CORE-STAGE-CACHE-3
test "demand raw payload rejects valid checksummed provenance spliced after header admission" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var storage = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer storage.deinit();
    var unit = try language.Compilation.init(a, "proof.selka", "func main() -> int:\n    return 7\n");
    defer unit.deinit();
    try unit.check();
    var refusal: build.Refusal = .{};
    const input: build.Input = .{ .program = unit.program.?, .source = unit.src };
    var cold = lowering.Cache.init(&storage);
    _ = try build.buildExecutableCached(a, input, &refusal, &cold);
    var deferred: lowering.Deferred = .{ .arena = a, .store = &storage };
    var warm = lowering.Cache.init(&storage);
    warm.lazy = &deferred;
    var module = try build.buildExecutableCached(a, input, &refusal, &warm);
    try deferred.prepare(&module, unit.src);
    const handle = deferred.tables.handles.items[0].?;
    const wire = (try storage.load(a, handle.key)).?;
    const demand_sources = @import("demand_sources.zig");
    var sources: demand_sources.Cache = .{ .arena = a };
    sources.bind(unit.src);
    var reach: demand_sources.Reach = .{};
    try std.testing.expect(try sources.collect(&reach, .{ .offset = 0, .point = .{ .line = 1, .column = 1 } }));
    const proof = (try sources.seal(&reach)).?[0];
    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, wire[wire.len - 8 ..][0..8], .little));
    var writer = language.persist_codec.Writer.init(a);
    try writer.write([]const demand_sources.Proof, &.{proof});
    const spliced = try std.mem.concat(a, u8, &.{ wire[0 .. wire.len - 8], writer.bytes.items });
    // The substituted proof is valid for the current source and the store
    // recomputes its checksum. It differs from the admitted header's authority.
    try std.testing.expect(try sources.matches(&.{proof}));
    try std.testing.expect(try storage.save(handle.key, spliced));
    try std.testing.expectError(error.CacheMiss, deferred.context.ensure(0));
}

const unpack_source =
    \\enum Parts:
    \\    pair(left: str[], right: str[])
    \\func main() -> int:
    \\    match Parts.pair(left=["left"], right=["right"]):
    \\        case pair(left=left, right=right):
    \\            return 7 + len(left) + len(right)
;

fn unpackKey(a: std.mem.Allocator, store: *const stage.Store, program: language.typed.Program, source: language.source.Source) !stage.Digest {
    var module: ir.Module = .{};
    var discovery: lowering.Discovery = .{};
    var types: std.AutoHashMapUnmanaged(language.typed.Type, ir.Type) = .empty;
    var cache = lowering.Cache.init(store);
    const context: lowering.Context = .{ .arena = a, .input = .{ .program = program, .source = source, .drop_debug = false }, .module = &module, .discovery = &discovery, .types = &types };
    var session = try lowering.Session.prepare(&cache, context);
    return (try session.key(context, program.functions[@backingInt(program.main)])).key;
}

fn unpackStatement(program: language.typed.Program) !language.typed.Statement {
    for (program.statements) |statement| if (statement.data == .match) {
        for (statement.data.match.arms) |arm| if (arm.unpack != null) return statement;
    };
    return error.TestUnexpectedResult;
}

fn unpackInteger(program: language.typed.Program) !*language.typed.Node {
    for (@constCast(program.nodes)) |*node| if (node.data == .integer) return node;
    return error.TestUnexpectedResult;
}

// spec-case: NEW-CORE-ZERO-RC-RECORD-UNPACK-1
// spec-case: NEW-CORE-STAGE-CACHE-3
test "lowering cache owned unpack hashes body selection bindings and source changes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var unit = try language.Compilation.init(a, source_name, unpack_source);
    defer unit.deinit();
    try unit.check();
    const program = unit.program.?;
    const statement = try unpackStatement(program);
    const arm = &@constCast(statement.data.match.arms)[0];
    const original = arm.*;
    const baseline = try unpackKey(a, &store, program, unit.src);
    const fields = try a.dupe(?language.typed.LocalId, original.unpack.?.fields);
    std.mem.swap(?language.typed.LocalId, &fields[0], &fields[1]);
    arm.unpack.?.fields = fields;
    try std.testing.expect(!std.mem.eql(u8, &baseline, &try unpackKey(a, &store, program, unit.src)));
    arm.* = original;
    // An all-discard arm can select the entire body instead of its last child.
    // Both selections are valid descriptors, but must have different keys.
    arm.unpack.?.body = arm.body;
    try std.testing.expect(!std.mem.eql(u8, &baseline, &try unpackKey(a, &store, program, unit.src)));
    arm.* = original;
    arm.unpack = null;
    try std.testing.expect(!std.mem.eql(u8, &baseline, &try unpackKey(a, &store, program, unit.src)));
    arm.* = original;
    const integer = try unpackInteger(program);
    integer.data.integer += 1;
    try std.testing.expect(!std.mem.eql(u8, &baseline, &try unpackKey(a, &store, program, unit.src)));
    integer.data.integer -= 1;
    try std.testing.expectEqual(baseline, try unpackKey(a, &store, program, unit.src));
    arm.unpack.?.body = @fromBackingInt(program.statements.len);
    try std.testing.expectError(error.InvalidSnapshot, unpackKey(a, &store, program, unit.src));
    arm.* = original;
}

/// Build a checked DAG with one more fielded match around the previous body.
/// At 64 levels duplicate unpack.body recursion would visit 2^64 bodies.
fn nestedUnpack(a: std.mem.Allocator, original: language.typed.Program, depth: usize) !language.typed.Program {
    const typed = language.typed;
    const statement = try unpackStatement(original);
    const arm = statement.data.match.arms[0];
    const prologue = original.statements[@backingInt(arm.body)].data.block;
    var statements: std.ArrayList(typed.Statement) = .empty;
    try statements.appendSlice(a, original.statements);
    var body = arm.unpack.?.body;
    for (0..depth) |_| {
        const children = try a.dupe(typed.StatementId, prologue);
        children[children.len - 1] = body;
        const wrapper: typed.StatementId = @fromBackingInt(statements.items.len);
        try statements.append(a, .{ .span = statement.span, .terminates = true, .data = .{ .block = children } });
        var next = arm;
        next.body = wrapper;
        next.unpack.?.body = body;
        var outer = statement;
        outer.data.match.arms = try a.dupe(typed.MatchArm, &.{next});
        body = @fromBackingInt(statements.items.len);
        try statements.append(a, outer);
    }
    var program = original;
    const functions = try a.dupe(typed.Function, original.functions);
    functions[@backingInt(program.main)].scope.body = body;
    program.functions = functions;
    program.statements = statements.items;
    return program;
}

// spec-case: NEW-CORE-ZERO-RC-RECORD-UNPACK-1
// spec-case: NEW-CORE-STAGE-CACHE-3
test "lowering cache owned unpack hashes deeply nested bodies without duplicate traversal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer store.deinit();
    var unit = try language.Compilation.init(a, source_name, unpack_source);
    defer unit.deinit();
    try unit.check();
    const program = try nestedUnpack(a, unit.program.?, 64);
    const baseline = try unpackKey(a, &store, program, unit.src);
    const integer = try unpackInteger(program);
    integer.data.integer += 1;
    try std.testing.expect(!std.mem.eql(u8, &baseline, &try unpackKey(a, &store, program, unit.src)));
    integer.data.integer -= 1;
    try std.testing.expectEqual(baseline, try unpackKey(a, &store, program, unit.src));
}

/// Whether `keys` hold `key`.
fn holds(keys: []const stage.Digest, key: stage.Digest) bool {
    for (keys) |known| if (std.mem.eql(u8, &known, &key)) return true;
    return false;
}

test "keying a function from its checked tree puts the references record a later build that omits the body will look for among the build's roots" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try stage.Store.init(std.testing.allocator, std.testing.io, root);
    defer store.deinit();
    const keyed = try keyedNamed(a, &store, reach_base, "helper");
    const refs_key = store.key("lowered-body-refs-v4", &.{&keyed.body});
    try std.testing.expect(holds(try store.touchedKeys(a), refs_key));
}

const reach_base =
    \\record Pair:
    \\    a: int
    \\    b: int
    \\func first(p: Pair) -> int:
    \\    return p.a
    \\func helper(x: int) -> int:
    \\    return x + 1
    \\func main() -> int:
    \\    return first(Pair(a=1, b=2)) + helper(2)
    \\
;

/// The lowering key of the named function in the program that `text` checks to.
fn keyNamed(a: std.mem.Allocator, store: *const stage.Store, text: []const u8, name: []const u8) !stage.Digest {
    return (try keyedNamed(a, store, text, name)).key;
}

/// The lowering key, body digest and stored references of the named function in the program that `text` checks to.
fn keyedNamed(a: std.mem.Allocator, store: *const stage.Store, text: []const u8, name: []const u8) !lowering.Keyed {
    var unit = try language.Compilation.init(a, source_name, text);
    defer unit.deinit();
    try unit.check();
    const program = unit.program.?;
    var module: ir.Module = .{};
    var discovery: lowering.Discovery = .{};
    var types: std.AutoHashMapUnmanaged(language.typed.Type, ir.Type) = .empty;
    var cache = lowering.Cache.init(store);
    const context: lowering.Context = .{ .arena = a, .input = .{ .program = program, .source = unit.src, .drop_debug = false }, .module = &module, .discovery = &discovery, .types = &types };
    var session = try lowering.Session.prepare(&cache, context);
    for (program.functions) |function| {
        if (std.mem.eql(u8, function.name, name)) {
            const keyed = try session.key(context, function);
            return keyed;
        }
    }
    @panic("keyedNamed: the program has no function with the requested name");
}

/// A body part the engine is pretending to hold: what `digest` answers for every function of the program.
const HeldPart = struct { digest: ?stage.Digest };

fn heldDigest(context: *anyopaque, _: ?language.source.Source, _: language.typed.Function) ?stage.Digest {
    const held: *const HeldPart = @ptrCast(@alignCast(context));
    return held.digest;
}

/// `keyedNamed` with the engine's checked-body part for every function being `held`.
fn keyedWithPart(a: std.mem.Allocator, store: *const stage.Store, text: []const u8, name: []const u8, held: *const HeldPart) !lowering.Keyed {
    var unit = try language.Compilation.init(a, source_name, text);
    defer unit.deinit();
    try unit.check();
    const program = unit.program.?;
    var module: ir.Module = .{};
    var discovery: lowering.Discovery = .{};
    var types: std.AutoHashMapUnmanaged(language.typed.Type, ir.Type) = .empty;
    var cache = lowering.Cache.init(store);
    cache.engine.parts = .{ .context = @constCast(held), .digest = heldDigest };
    const context: lowering.Context = .{ .arena = a, .input = .{ .program = program, .source = unit.src, .drop_debug = false }, .module = &module, .discovery = &discovery, .types = &types };
    var session = try lowering.Session.prepare(&cache, context);
    for (program.functions) |function| {
        // A name ending in `[` is a generic instance, found by what comes before its arguments.
        const found = if (std.mem.endsWith(u8, name, "[")) std.mem.startsWith(u8, function.name, name) else std.mem.eql(u8, function.name, name);
        if (found) return session.key(context, function);
    }
    @panic("keyedWithPart: the program has no function with the requested name");
}

test "a function the engine holds a body part for is keyed by the part: the tree and the declarations it reaches are not read" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try reachStore(std.testing.allocator, a, &temporary);
    defer store.deinit();
    const one: HeldPart = .{ .digest = @splat(1) };
    const two: HeldPart = .{ .digest = @splat(2) };
    const none: HeldPart = .{ .digest = null };
    // The same part gives the same key for a different body: the part is the engine's record that the body stands.
    const edited = "record Pair:\n    a: int\n    b: int\nfunc first(p: Pair) -> int:\n    return p.a + 1000\nfunc helper(x: int) -> int:\n    return x + 1\nfunc main() -> int:\n    return first(Pair(a=1, b=2)) + helper(2)\n";
    const before = try keyedWithPart(a, &store, reach_base, "first", &one);
    const after = try keyedWithPart(a, &store, edited, "first", &one);
    try std.testing.expectEqualSlices(u8, &before.key, &after.key);
    // Another part gives another key, a function the engine holds nothing for is keyed as before, and the two differ.
    const moved = try keyedWithPart(a, &store, reach_base, "first", &two);
    try std.testing.expect(!std.mem.eql(u8, &before.key, &moved.key));
    const plain = try keyedWithPart(a, &store, reach_base, "first", &none);
    try std.testing.expectEqualSlices(u8, &(try keyNamed(a, &store, reach_base, "first")), &plain.key);
    try std.testing.expect(!std.mem.eql(u8, &before.key, &plain.key));
    // No references are stored for a part-keyed function.
    try std.testing.expectEqual(@as(usize, 0), before.refs.functions.len + before.refs.types.len);
}

test "a generic instance is keyed by its template's part, its type arguments and the layout of the records they reach" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var store = try reachStore(std.testing.allocator, a, &temporary);
    defer store.deinit();
    const part: HeldPart = .{ .digest = @splat(1) };
    const base = "record Pair:\n    a: int\n    b: int\nfunc head[T](items: T[]) -> T:\n    return items[0]\nfunc main() -> int:\n    const pairs = [Pair(a=1, b=2)]\n    return head(pairs).a + head([1, 2])\n";
    // The record the instance's argument is gains a field: the template and its part are as they were, the instance is another.
    const wider = "record Pair:\n    a: int\n    b: int\n    c: int\nfunc head[T](items: T[]) -> T:\n    return items[0]\nfunc main() -> int:\n    const pairs = [Pair(a=1, b=2, c=3)]\n    return head(pairs).a + head([1, 2])\n";
    const before = try keyedWithPart(a, &store, base, "head[", &part);
    const after = try keyedWithPart(a, &store, wider, "head[", &part);
    try std.testing.expect(!std.mem.eql(u8, &before.key, &after.key));
    // The same program and part give the same key, and the instance's key is not the key of a function with that part and no arguments.
    const again = try keyedWithPart(a, &store, base, "head[", &part);
    try std.testing.expectEqualSlices(u8, &before.key, &again.key);
    try std.testing.expect(!std.mem.eql(u8, &before.key, &(try keyedWithPart(a, &store, base, "main", &part)).key));
}

/// A module of a merged project: the file it came from and its text.
const Module = struct { path: []const u8, text: []const u8 };

/// The lowering key of the named function in the project whose modules, in this order, are `modules`.
fn keyInProject(a: std.mem.Allocator, store: *const stage.Store, modules: []const Module, name: []const u8) !lowering.Keyed {
    const sources = try a.alloc(language.source.Source, modules.len);
    for (sources, modules) |*source, module| source.* = try language.source.Source.init(a, module.path, module.text);
    const merged = try language.source.Source.initMapped(a, sources);
    var unit = try language.Compilation.init(a, merged.path, merged.bytes);
    defer unit.deinit();
    unit.src = merged;
    try unit.check();
    const program = unit.program.?;
    var module: ir.Module = .{};
    var discovery: lowering.Discovery = .{};
    var types: std.AutoHashMapUnmanaged(language.typed.Type, ir.Type) = .empty;
    var cache = lowering.Cache.init(store);
    const context: lowering.Context = .{ .arena = a, .input = .{ .program = program, .source = unit.src, .drop_debug = false }, .module = &module, .discovery = &discovery, .types = &types };
    var session = try lowering.Session.prepare(&cache, context);
    for (program.functions) |function| {
        if (std.mem.eql(u8, function.name, name)) return session.key(context, function);
    }
    @panic("keyInProject: the project has no function with the requested name");
}

const project_lib = Module{ .path = "lib.selka", .text = "public record Item:\n    value: int = 42\n\npublic func bump(x: int) -> int:\n    return x + 1\n" };
const project_entry = Module{ .path = "entry.selka", .text = "func main() -> int:\n    return Item().value + bump(1)\n" };
const project_extra = Module{ .path = "extra.selka", .text = "func extra_unused(y: int) -> int:\n    return y * 3\n" };

// spec-case: NEW-CORE-STAGE-CACHE-1
test "a lowering key ignores modules added, removed or reordered around the ones it reads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try reachStore(std.testing.allocator, a, &temporary);
    defer store.deinit();
    // `main` expands the default of `Item.value`, a position in lib.selka, so its key holds a proof of that file.
    const base = try keyInProject(a, &store, &.{ project_lib, project_entry }, "main");
    try std.testing.expect(base.refs.types.len != 0);
    try std.testing.expectEqualSlices(u8, &base.key, &(try keyInProject(a, &store, &.{ project_extra, project_lib, project_entry }, "main")).key);
    try std.testing.expectEqualSlices(u8, &base.key, &(try keyInProject(a, &store, &.{ project_lib, project_extra, project_entry }, "main")).key);
    try std.testing.expectEqualSlices(u8, &base.key, &(try keyInProject(a, &store, &.{ project_lib, project_entry, project_extra }, "main")).key);
    try std.testing.expectEqualSlices(u8, &base.key, &(try keyInProject(a, &store, &.{ project_entry, project_lib }, "main")).key);
    // The callee's key is as free of the other modules.
    const callee = try keyInProject(a, &store, &.{ project_lib, project_entry }, "bump");
    try std.testing.expectEqualSlices(u8, &callee.key, &(try keyInProject(a, &store, &.{ project_extra, project_lib, project_entry }, "bump")).key);
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "a lowering key holds the file of an external position only as far as that position" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try reachStore(std.testing.allocator, a, &temporary);
    defer store.deinit();
    const base = try keyInProject(a, &store, &.{ project_lib, project_entry }, "main");
    // A declaration appended to the file after the default's line: the key stays.
    const appended = Module{ .path = project_lib.path, .text = project_lib.text ++ "\npublic func later(x: int) -> int:\n    return x * 2\n" };
    try std.testing.expectEqualSlices(u8, &base.key, &(try keyInProject(a, &store, &.{ appended, project_entry }, "main")).key);
    // An edit in the function that follows the default, in the same file: also after the position.
    const edited_after = Module{ .path = project_lib.path, .text = "public record Item:\n    value: int = 42\n\npublic func bump(x: int) -> int:\n    return x + 2\n" };
    try std.testing.expectEqualSlices(u8, &base.key, &(try keyInProject(a, &store, &.{ edited_after, project_entry }, "main")).key);
    // A line in front of the default moves the position, the default itself is another expression: each moves the key.
    const moved = Module{ .path = project_lib.path, .text = "\n" ++ project_lib.text };
    try std.testing.expect(!std.mem.eql(u8, &base.key, &(try keyInProject(a, &store, &.{ moved, project_entry }, "main")).key));
    const changed = Module{ .path = project_lib.path, .text = "public record Item:\n    value: int = 43\n\npublic func bump(x: int) -> int:\n    return x + 1\n" };
    try std.testing.expect(!std.mem.eql(u8, &base.key, &(try keyInProject(a, &store, &.{ changed, project_entry }, "main")).key));
}

fn reachStore(backing: std.mem.Allocator, a: std.mem.Allocator, temporary: *std.testing.TmpDir) !stage.Store {
    return stage.Store.init(backing, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "lowering keys of a caller and its callees ignore an unrelated function appended to the program" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try reachStore(std.testing.allocator, a, &temporary);
    defer store.deinit();
    const extended = reach_base ++ "func unused(y: int) -> int:\n    return y * 3\n";
    try std.testing.expectEqualSlices(u8, &(try keyNamed(a, &store, reach_base, "main")), &(try keyNamed(a, &store, extended, "main")));
    try std.testing.expectEqualSlices(u8, &(try keyNamed(a, &store, reach_base, "helper")), &(try keyNamed(a, &store, extended, "helper")));
    try std.testing.expectEqualSlices(u8, &(try keyNamed(a, &store, reach_base, "first")), &(try keyNamed(a, &store, extended, "first")));
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "a caller's lowering key changes when a callee's declaration changes, even with the caller's body unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try reachStore(std.testing.allocator, a, &temporary);
    defer store.deinit();
    // The caller's text is unchanged and its literal argument still fits: only the callee's parameter type differs.
    const narrowed = "record Pair:\n    a: int\n    b: int\nfunc first(p: Pair) -> int:\n    return p.a\nfunc helper(x: i32) -> int:\n    return 1\nfunc main() -> int:\n    return first(Pair(a=1, b=2)) + helper(2)\n";
    try std.testing.expect(!std.mem.eql(u8, &(try keyNamed(a, &store, reach_base, "main")), &(try keyNamed(a, &store, narrowed, "main"))));
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "a caller's lowering key changes when a record it uses changes layout, and not when an unrelated record is added" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try reachStore(std.testing.allocator, a, &temporary);
    defer store.deinit();
    const with_other = reach_base ++ "record Other:\n    c: int\n";
    try std.testing.expectEqualSlices(u8, &(try keyNamed(a, &store, reach_base, "first")), &(try keyNamed(a, &store, with_other, "first")));
    const reordered = "record Pair:\n    b: int\n    a: int\nfunc first(p: Pair) -> int:\n    return p.a\nfunc helper(x: int) -> int:\n    return x + 1\nfunc main() -> int:\n    return first(Pair(a=1, b=2)) + helper(2)\n";
    try std.testing.expect(!std.mem.eql(u8, &(try keyNamed(a, &store, reach_base, "first")), &(try keyNamed(a, &store, reordered, "first"))));
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "a lowering key and the records it stores name a record by its name, so a record inserted before it moves neither" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try reachStore(std.testing.allocator, a, &temporary);
    defer store.deinit();
    const inserted = "record Earlier:\n    c: int\n" ++ reach_base;
    for ([_][]const u8{ "first", "helper", "main" }) |name| {
        const before = try keyedNamed(a, &store, reach_base, name);
        const after = try keyedNamed(a, &store, inserted, name);
        try std.testing.expectEqualSlices(u8, &before.key, &after.key);
        try std.testing.expectEqualSlices(u8, &before.body, &after.body);
        try std.testing.expectEqualDeep(before.refs.types, after.refs.types);
    }
    // The record the function reads is what the reference names; a scalar and a function are not records.
    try std.testing.expectEqual(@as(usize, 1), (try keyedNamed(a, &store, inserted, "first")).refs.types.len);
    try std.testing.expectEqual(@as(usize, 0), (try keyedNamed(a, &store, inserted, "helper")).refs.types.len);
    // A renamed record is another record, and a function that reads it lowers again.
    const renamed = try std.mem.replaceOwned(u8, a, reach_base, "Pair", "Twin");
    try std.testing.expect(!std.mem.eql(u8, &(try keyNamed(a, &store, reach_base, "first")), &(try keyNamed(a, &store, renamed, "first"))));
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "lowering keys of a callee and its caller ignore an unrelated function inserted before the entry point" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try reachStore(std.testing.allocator, a, &temporary);
    defer store.deinit();
    const plain = "func helper(x: int) -> int:\n    return x + 1\nfunc main() -> int:\n    return helper(2)\n";
    const inserted = "func helper(x: int) -> int:\n    return x + 1\nfunc unused(y: int) -> int:\n    return y * 3\nfunc main() -> int:\n    return helper(2)\n";
    try std.testing.expectEqualSlices(u8, &(try keyNamed(a, &store, plain, "helper")), &(try keyNamed(a, &store, inserted, "helper")));
    // The entry point moves, but its own index is not part of its artifact and the callee keeps its index.
    try std.testing.expectEqualSlices(u8, &(try keyNamed(a, &store, plain, "main")), &(try keyNamed(a, &store, inserted, "main")));
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "a function's lowering key ignores its own index when the functions it names keep theirs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try reachStore(std.testing.allocator, a, &temporary);
    defer store.deinit();
    const plain = "func helper(x: int) -> int:\n    return x + 1\nfunc main() -> int:\n    return helper(2)\n";
    const shifted = "func unused(y: int) -> int:\n    return y * 3\nfunc helper(x: int) -> int:\n    return x + 1\nfunc main() -> int:\n    return helper(2)\n";
    try std.testing.expectEqualSlices(u8, &(try keyNamed(a, &store, plain, "helper")), &(try keyNamed(a, &store, shifted, "helper")));
}

/// `keyNamed`, after renaming checked function `from` to `to` in place: a
/// program in which two functions share a name, which the checker refuses.
fn keyNamedSharing(a: std.mem.Allocator, store: *const stage.Store, text: []const u8, name: []const u8, from: []const u8, to: []const u8) !stage.Digest {
    var unit = try language.Compilation.init(a, source_name, text);
    defer unit.deinit();
    try unit.check();
    const program = unit.program.?;
    shareName(program, from, to);
    var module: ir.Module = .{};
    var discovery: lowering.Discovery = .{};
    var types: std.AutoHashMapUnmanaged(language.typed.Type, ir.Type) = .empty;
    var cache = lowering.Cache.init(store);
    const context: lowering.Context = .{ .arena = a, .input = .{ .program = program, .source = unit.src, .drop_debug = false }, .module = &module, .discovery = &discovery, .types = &types };
    var session = try lowering.Session.prepare(&cache, context);
    for (program.functions) |function| {
        if (std.mem.eql(u8, function.name, name) and function.id == program.main) return (try session.key(context, function)).key;
    }
    @panic("keyNamedSharing: the program's entry point does not carry the requested name");
}

const callee_first = "func helper(x: int) -> int:\n    return x + 1\nfunc unused(y: int) -> int:\n    return y * 3\nfunc main() -> int:\n    return helper(2)\n";
const callee_moved = "func unused(y: int) -> int:\n    return y * 3\nfunc helper(x: int) -> int:\n    return x + 1\nfunc main() -> int:\n    return helper(2)\n";

// spec-case: NEW-CORE-STAGE-CACHE-1
test "a caller's lowering key names a uniquely named callee by name, so moving the callee to another index keeps it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try reachStore(std.testing.allocator, a, &temporary);
    defer store.deinit();
    try std.testing.expectEqualSlices(u8, &(try keyNamed(a, &store, callee_first, "main")), &(try keyNamed(a, &store, callee_moved, "main")));
    // A renamed callee is another declaration: the caller re-lowers, though its call moved with the rename.
    const renamed = "func unused(y: int) -> int:\n    return y * 3\nfunc helper2(x: int) -> int:\n    return x + 1\nfunc main() -> int:\n    return helper2(2)\n";
    try std.testing.expect(!std.mem.eql(u8, &(try keyNamed(a, &store, callee_moved, "main")), &(try keyNamed(a, &store, renamed, "main"))));
    // A changed callee declaration with the same name still re-lowers the caller.
    const changed = "func unused(y: int) -> int:\n    return y * 3\nfunc helper(x: i32) -> int:\n    return 1\nfunc main() -> int:\n    return helper(2)\n";
    try std.testing.expect(!std.mem.eql(u8, &(try keyNamed(a, &store, callee_moved, "main")), &(try keyNamed(a, &store, changed, "main"))));
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "a callee whose name another function shares keeps its positional index in the caller's lowering key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try reachStore(std.testing.allocator, a, &temporary);
    defer store.deinit();
    // `unused` renamed to `helper`: the name is ambiguous, so the key cannot name the callee by it.
    const first = try keyNamedSharing(a, &store, callee_first, "main", "unused", "helper");
    const moved = try keyNamedSharing(a, &store, callee_moved, "main", "unused", "helper");
    try std.testing.expect(!std.mem.eql(u8, &first, &moved));
    try std.testing.expectEqualSlices(u8, &first, &(try keyNamedSharing(a, &store, callee_first, "main", "unused", "helper")));
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "lowering identities name unique functions and refuse a shared name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, source_name, callee_first);
    defer unit.deinit();
    try unit.check();
    const program = unit.program.?;
    const names = try lowering.Identities.init(a, program);
    const helper = names.find("helper").?;
    try std.testing.expectEqualStrings("helper", names.name(program, helper).?);
    try std.testing.expectEqual(@as(?u32, null), names.find("missing"));
    try std.testing.expectEqual(@as(?[]const u8, null), names.name(program, program.functions.len));
    shareName(program, "unused", "helper");
    const shared = try lowering.Identities.init(a, program);
    try std.testing.expectEqual(@as(?u32, null), shared.find("helper"));
    try std.testing.expectEqual(@as(?[]const u8, null), shared.name(program, helper));
}

// spec-case: NEW-CORE-STAGE-CACHE-3
test "lowered artifacts replay exactly after their callee moves to another checked index" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    try std.testing.expectEqualDeep(Work{ .lowered = 2, .reused = 0 }, try compare(root, std.testing.allocator, callee_first, false));
    // `helper` moves from index 0 to 1; `main` replays and rebinds it by name, and compare checks the
    // served module against a fresh build.
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 2 }, try compare(root, std.testing.allocator, callee_moved, false));
}

fn borrowedWideCacheSource(a: std.mem.Allocator) ![]const u8 {
    var source: std.ArrayList(u8) = .empty;
    try source.appendSlice(a, "func wide(");
    for (0..69) |position| try source.print(a, "pad{d}: int, ", .{position});
    try source.appendSlice(
        a,
        "mut rows: str[][]) -> str[][]? from rows:\n" ++
            "    return Some(rows)\n" ++
            "func main(out: Stream) -> int:\n" ++
            "    mut rows = [[\"one\"]]\n" ++
            "    const result = wide(",
    );
    for (0..69) |_| try source.appendSlice(a, "0, ");
    try source.appendSlice(
        a,
        "mut rows)\n" ++
            "    match result:\n" ++
            "        case Some(value):\n" ++
            "            print(out, value[0][0])\n" ++
            "        case None:\n" ++
            "            return 1\n" ++
            "    return 0\n",
    );
    return source.items;
}

test "O3 lowering cache retains nested borrowed paths and wide passing metadata after scratch release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source = try borrowedWideCacheSource(a);
    const cold = try compare(root, std.testing.allocator, source, false);
    try std.testing.expect(cold.lowered > 0);
    const warm = try compare(root, std.testing.allocator, source, false);
    try std.testing.expectEqual(@as(usize, 0), warm.lowered);
    try std.testing.expect(warm.reused > 0);
    const replay = try compare(root, std.testing.allocator, source, false);
    try std.testing.expectEqual(@as(usize, 0), replay.lowered);
    try std.testing.expectEqual(warm.reused, replay.reused);
}

/// Lower `unit` through a store (on `backing`) on the work directory `work` and the shared root `shared`, without comparing it with a fresh
/// lowering: the lowering cache's counts, and the module.
fn lowerShared(backing: std.mem.Allocator, a: std.mem.Allocator, work: []const u8, shared: []const u8, unit: *const language.Compilation, strict: bool) !struct { module: ir.Module, lowered: usize, reused: usize, unfit: usize } {
    var store = try stage.Store.initWithOptions(backing, std.testing.io, work, .{ .shared = shared });
    defer store.deinit();
    var cache = lowering.Cache.init(&store);
    cache.strict_fit = strict;
    var refusal: build.Refusal = .{};
    const module = try build.buildExecutableCached(a, .{ .program = unit.program.?, .source = unit.src, .drop_debug = false }, &refusal, &cache);
    return .{ .module = module, .lowered = cache.counts.lowered, .reused = cache.counts.reused, .unfit = cache.counts.unfit };
}

/// A checked compilation of `bytes`, whose diagnostics are printed when the check fails.
fn checkedUnit(a: std.mem.Allocator, bytes: []const u8) !language.Compilation {
    var unit = try language.Compilation.init(a, source_name, bytes);
    unit.check() catch |err| {
        for (unit.diagnostics.items) |diagnostic| report("{s}", .{try diagnostic.render(a, unit.src)});
        return err;
    };
    return unit;
}

/// Functions whose `from` list names a plain bytes or text parameter beside the parameter the result is lent from (lane SK:
/// `erc::instance_of` of the port, 9 November).
const view_source_program =
    \\record Inst:
    \\    ref_des: bytes
    \\    value: bytes
    \\record Label:
    \\    name: str
    \\record Block:
    \\    instances: Inst[]
    \\    labels: Label[]
    \\func instance_of(block: Block, ref_des: bytes) -> Inst? from block, ref_des:
    \\    for inst in block.instances:
    \\        if inst.ref_des == ref_des:
    \\            return Some(inst)
    \\    return None
    \\func label_of(block: Block, name: str) -> Label? from block, name:
    \\    for label in block.labels:
    \\        if label.name == name:
    \\            return Some(label)
    \\    return None
    \\func main(out: Stream) -> int:
    \\    mut items: Inst[] = []
    \\    append(mut items, Inst(ref_des=b"R1", value=b"10k"))
    \\    mut labels: Label[] = []
    \\    append(mut labels, Label(name="L1"))
    \\    const block = Block(instances=own items, labels=own labels)
    \\    const inst = instance_of(block, b"R1")
    \\    const label = label_of(block, "L1")
    \\    mut total = 0
    \\    match inst:
    \\        case Some(found):
    \\            total += len(found.value)
    \\        case None:
    \\            total += 100
    \\    match label:
    \\        case Some(found):
    \\            total += len(found.name)
    \\        case None:
    \\            total += 100
    \\    print(out, total)
    \\    return 0
    \\
;

// spec-case: NEW-CORE-STAGE-CACHE-3
test "SK a borrowed record lent from a parameter beside a plain bytes or text source is declared valid and restores in another work directory" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A plain bytes or text parameter is passed as a view, which lends no record: the declarations keep only `block`, so the IR
    // verifier accepts them (it refused them before, and a restore, which checks a signature, refused the build).
    try std.testing.expectEqualDeep(Work{ .lowered = 3, .reused = 0 }, try compare(root, std.testing.allocator, view_source_program, false));
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 3 }, try compare(root, std.testing.allocator, view_source_program, false));
    // The port's sequence: one work directory publishes to the shared store, and a fresh one restores every function from it.
    var unit = try checkedUnit(a, view_source_program);
    defer unit.deinit();
    const shared = try std.fs.path.join(a, &.{ root, "shared" });
    const first = try lowerShared(std.testing.allocator, a, try std.fs.path.join(a, &.{ root, "one" }), shared, &unit, false);
    try std.testing.expectEqual(@as(usize, 3), first.lowered);
    const second = try lowerShared(std.testing.allocator, a, try std.fs.path.join(a, &.{ root, "two" }), shared, &unit, true);
    try std.testing.expectEqual(@as(usize, 3), second.reused);
    try std.testing.expectEqual(@as(usize, 0), second.unfit);
    try support.verified(a, &second.module, &.{});
}

/// A record result whose only `from` source is a plain bytes parameter: no source can lend it, so its declaration is one the IR
/// verifier refuses, and a stored lowering of it does not fit any module. The declaration authority refuses such a clause at a
/// nongeneric declaration (lane CB), and Core's ownership check refuses this generic instance (`T` = `Inst`, lane HC), so
/// `selka check` and a build refuse the program. The language check `checkedUnit` runs judges only the declaration, which lends
/// for `T = bytes`, so the instance still reaches the lowering and the store: a record a valid program can never make, which is
/// what the fit check exists to catch.
const unlendable_program =
    \\record Inst:
    \\    ref_des: bytes
    \\func none_of[T](name: bytes, tag: T) -> T? from name:
    \\    return None
    \\func main(out: Stream) -> int:
    \\    const found = none_of(b"x", Inst(ref_des=b"y"))
    \\    match found:
    \\        case Some(inst):
    \\            print(out, len(inst.ref_des))
    \\        case None:
    \\            print(out, 0)
    \\    return 0
    \\
;

// spec-case: NEW-CORE-STAGE-CACHE-3
test "SK a stored function that does not fit the module is a counted miss logged in the serving store, and a strict fit refuses it" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try checkedUnit(a, unlendable_program);
    defer unit.deinit();
    const shared = try std.fs.path.join(a, &.{ root, "shared" });
    const first = try lowerShared(std.testing.allocator, a, try std.fs.path.join(a, &.{ root, "one" }), shared, &unit, false);
    try std.testing.expectEqual(@as(usize, 2), first.lowered);
    try std.testing.expectEqual(@as(usize, 0), first.unfit);
    // A fresh work directory finds `none_of` in the shared store: it does not fit, so it is lowered, never a refused build.
    const second = try lowerShared(std.testing.allocator, a, try std.fs.path.join(a, &.{ root, "two" }), shared, &unit, false);
    try std.testing.expectEqual(@as(usize, 1), second.unfit);
    try std.testing.expectEqual(@as(usize, 1), second.reused);
    try std.testing.expectEqual(@as(usize, 1), second.lowered);
    const context: u8 = 0;
    const options: emit.Options = .{ .locator = .{ .context = &context, .locate = firstLine }, .source_path = source_name, .main = .{ .parameters = &.{"out"} } };
    try std.testing.expectEqualStrings(try emit.emitModule(a, &first.module, options), try emit.emitModule(a, &second.module, options));
    const log = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fs.path.join(a, &.{ shared, stage.shared_leaf, "mismatches.log" }), a, .limited(1 << 16));
    try std.testing.expect(std.mem.startsWith(u8, log, "unfit stage "));
    // The stage-served pass of `--verify-cache` fits strictly: the record that does not fit refuses the build.
    try std.testing.expectError(error.Unsupported, lowerShared(std.testing.allocator, a, try std.fs.path.join(a, &.{ root, "three" }), shared, &unit, true));
}
