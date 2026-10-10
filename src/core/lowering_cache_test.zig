//! Durable lowering replay is compared with the uncached builder, including
//! declaration/string order, source spans and complete emitted LLVM text.
const std = @import("std");
const stage_loss = @import("stage_loss_test_support.zig");
const language = @import("mylang");
const build = @import("build.zig");
const lowering = @import("lowering_cache.zig");
const stage = @import("stage_store.zig");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const emit = @import("emit_llvm.zig");
const frontend_reuse = @import("frontend_reuse.zig");

const report = std.debug.print;
const cached_path = "cached.my";
const source_name = "cached.my";

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
    return .{ .lowered = cache.lowered, .reused = cache.reused };
}

fn compareMapped(root: []const u8, backing: std.mem.Allocator, left: []const u8, right: []const u8) !Work {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const sources = [_]language.source.Source{
        try language.source.Source.init(a, "templates.my", left),
        try language.source.Source.init(a, "entry.my", right),
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
    \\    out.print("answer")
    \\    return first(second(20))
    \\
;

// spec-case: NEW-CORE-STAGE-CACHE-3
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
    try std.testing.expectEqual(@as(usize, 3), cache.reused);
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
    try std.testing.expectEqualDeep(Work{ .lowered = 3, .reused = 0 }, try compare(root, std.testing.allocator, ids, false));
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 3 }, try compare(root, std.testing.allocator, ids, false));
    try std.testing.expectEqualDeep(Work{ .lowered = 3, .reused = 0 }, try compare(root, std.testing.allocator, ids, true));
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 3 }, try compare(root, std.testing.allocator, ids, true));
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
    \\    out.print(Item(n=3))
    \\    assert True, "kept"
    \\    return 7
    \\
    \\func main(out: Stream) -> int:
    \\    out.print("start")
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
    const needle = "out.print(\"start\")";
    const at = std.mem.indexOf(u8, render_source, needle).?;
    const edited = try std.mem.concat(std.testing.allocator, u8, &.{ render_source[0..at], "out.print(\"longer\", \"prefix\")", render_source[at + needle.len ..] });
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
    const entry = "func main(out: Stream) -> int:\n    out.print(\"ready\")\n    return identity[int](Item().value)\n";
    try std.testing.expectEqualDeep(Work{ .lowered = 2, .reused = 0 }, try compareMapped(root, std.testing.allocator, templates, entry));
    try std.testing.expectEqualDeep(Work{ .lowered = 0, .reused = 2 }, try compareMapped(root, std.testing.allocator, templates, entry));
    const grown = templates ++ "\n\n\n";
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
        \\    out.print("loops")
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
        try language.source.Source.init(a, "templates.my", left),
        try language.source.Source.init(a, "entry.my", right),
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
    try std.testing.expectEqual(cache.reused, lazy.restored);
    const fresh = try build.buildExecutable(a, input, &refusal);
    try sameModule(a, &module, &fresh);
    return .{ .lowered = cache.lowered, .reused = cache.reused };
}

const demand_entry = "func main(out: Stream) -> int:\n    out.print(\"before\")\n    return helper(out)\n";
const demand_helper = "func helper(out: Stream) -> int:\n    out.print(\"helper payload\")\n    return 42\n";

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
    const edited = "func main(out: Stream) -> int:\n    out.print(\"before\")\n    out.print(\"new neighbor string\")\n    return helper(out)\n";
    const work = try compareDemandMapped(root, std.testing.allocator, edited, demand_helper);
    try std.testing.expectEqualDeep(Work{ .lowered = 1, .reused = 1 }, work);
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "raw source prefix retains unrelated same file edits but catches equal length newlines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try language.source.Source.init(a, "sites.my", "func owner():\n    x = 1\nother 2\n");
    const unrelated = try language.source.Source.init(a, "sites.my", "func owner():\n    x = 1\nother 3\n");
    const newline = try language.source.Source.init(a, "sites.my", "func owner():\n\n   x = 1\nother 2\n");
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
    const original = try language.source.Source.init(a, "sites.my", "func owner():\n    x = 1\n");
    const later_line = try language.source.Source.init(a, "sites.my", "\nfunc owner():\n    x = 1\n");
    const later_column = try language.source.Source.init(a, "sites.my", " func owner():\n    x = 1\n");
    const renamed = try language.source.Source.init(a, "renamed.my", original.bytes);
    const proof = try lowering.sourceProof(original, 0, 21);
    const others = [_]stage.Digest{
        try lowering.sourceProof(later_line, 1, 21),
        try lowering.sourceProof(later_column, 1, 21),
        try lowering.sourceProof(renamed, 0, 21),
    };
    for (others) |other| try std.testing.expect(!std.mem.eql(u8, &proof, &other));
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "raw source prefix rejects malformed bounds and binds the maximum" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try language.source.Source.init(a, "sites.my", "func owner():\n    x = 1\n");
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
    const source = try language.source.Source.init(a, "sites.my", "func owner():\n    x = 1\n");
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

const SourceRun = struct { keys: []const ?stage.Digest, headers: []const ?stage.Digest, omitted: usize };

fn frontendSourceKeys(a: std.mem.Allocator, backing: std.mem.Allocator, root: []const u8) !SourceRun {
    const front = @import("frontend.zig");
    const queries = @import("lowering_demand.zig");
    const cache_root = try std.fs.path.join(a, &.{ root, "cache" });
    var storage = try stage.Store.init(backing, std.testing.io, cache_root);
    defer storage.deinit();
    var demand = try queries.Context.init(a, &storage, try std.fs.path.join(a, &.{ root, "main.my" }), false);
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
    for (headers, deferred.tables.keys.items) |*header, raw| header.* = if (raw) |key| storage.key("lowered-header-source-v2", &.{&key}) else null;
    try deferred.prepare(&module, checked.src);
    const keys = try a.dupe(?stage.Digest, deferred.context.keys);
    // Materialize only after recording compact authority, then compare replay
    // from genuinely omitted typed bodies with an independent complete check.
    for (0..module.functions.items.len) |index| try deferred.context.ensure(@intCast(index));
    var eager = front.Session.init(backing, std.testing.io, root);
    defer eager.deinit();
    const fresh = try eager.check(a, "main", &diagnostics);
    const expected = try build.buildExecutable(a, .{ .program = fresh.program, .source = fresh.src }, &refusal);
    try sameModule(a, &module, &expected);
    try demand.finish();
    return .{ .keys = keys, .headers = headers, .omitted = demand.count() };
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
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.my", .data = source_proof_before });
    const cold = try frontendSourceKeys(a, std.testing.allocator, root);
    const warm = try frontendSourceKeys(a, std.testing.allocator, root);
    try std.testing.expect(warm.omitted > 0);
    try std.testing.expectEqualDeep(cold.keys, warm.keys);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.my", .data = source_proof_after });
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
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.my", .data = source_proof_before });
    _ = try frontendSourceKeys(a, std.testing.allocator, root);
    const warm = try frontendSourceKeys(a, std.testing.allocator, root);
    var storage = try stage.Store.init(std.testing.allocator, std.testing.io, try std.fs.path.join(a, &.{ root, "cache" }));
    defer storage.deinit();
    const header = (try storage.load(a, warm.headers[1].?)).?;
    try std.testing.expectEqual(@as(u8, 1), header[header.len - 5]);
    @memset(header[header.len - 4 ..], 0);
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
        try language.source.Source.init(a, "first.my", "first\n"),
        try language.source.Source.init(a, "second.my", "func owner():\n    x = 1\n"),
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
