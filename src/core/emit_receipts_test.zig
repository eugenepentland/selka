//! A unit's compact emission receipt misses exactly when something the unit reads changed (G4a step 2b): another function, type
//! or table position moving elsewhere never misses it.
const std = @import("std");
const language = @import("selka");
const emitter = @import("emit_llvm.zig");
const units = @import("emit_units.zig");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const stages = @import("stage_store.zig");
const optimization = @import("optimization_cache.zig");
const emission_cache = @import("emission_cache.zig");
const equality = @import("build_equality.zig");
const type_ids = @import("type_ids.zig");

/// One function of a fixture module. `calls` names the function it calls; `record` makes it compare two records.
const Spec = struct { name: []const u8, calls: []const u8 = "", params: []const ir.Type = &.{}, ret: ir.Type = .i64, record: bool = false };

const marker = equality.prefix ++ "0123456789abcdef0123456789abcdef";

fn location(_: *const anyopaque, _: u32) emitter.Location {
    return .{ .path = "receipts.selka", .line = 1, .column = 1 };
}

fn indexOf(specs: []const Spec, name: []const u8) u32 {
    for (specs, 0..) |spec, index| if (std.mem.eql(u8, spec.name, name)) return @intCast(index);
    return @intCast(specs.len);
}

/// The record the `record` functions compare: `unrelated` list types ahead of it, its fields, and whether it is a nominal record
/// (named, so that its descriptor keeps its id when its fields change).
const Shape = struct { unrelated: usize = 0, fields: []const ir.Type = &.{ .i64, .str }, named: bool = false };

fn build(a: std.mem.Allocator, specs: []const Spec, unrelated: usize) !ir.Module {
    return buildShaped(a, specs, .{ .unrelated = unrelated });
}

/// A module of `specs` in order, with the record of `shape` and the equality marker last. The entry is `unit[main]`.
fn buildShaped(a: std.mem.Allocator, specs: []const Spec, shape_of: Shape) !ir.Module {
    var module: ir.Module = .{};
    for (0..shape_of.unrelated) |_| try module.compounds.append(a, .{ .list = .str });
    const record: ir.Type = @fromBackingInt(@as(u32, @intCast(ir.Type.first_compound + module.compounds.items.len)));
    try module.compounds.append(a, .{ .record = shape_of.fields });
    if (shape_of.named) {
        const names = try a.alloc(?[32]u8, module.compounds.items.len);
        @memset(names, null);
        names[shape_of.unrelated] = @splat(7);
        module.nominal = names;
    }
    const sample: ir.Signature = .{ .params = try a.dupe(ir.Type, &.{ record, record }), .ret = .bool, .linkage = .runtime_c };
    for (specs) |spec| {
        var hand = try support.Hand.init(a, &module, spec.name, .{ .params = if (spec.record) sample.params else spec.params, .ret = if (spec.record) .bool else spec.ret });
        const result = try hand.emit(try shape(a, &hand, specs, spec, @intCast(specs.len)));
        _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = result });
        _ = try hand.finish();
    }
    try module.functions.append(a, .{ .name = marker, .signature = sample });
    module.entry = indexOf(specs, "unit[main]");
    return module;
}

fn shape(a: std.mem.Allocator, hand: *support.Hand, specs: []const Spec, spec: Spec, marker_at: u32) !ir.Inst {
    _ = a;
    if (spec.record) return .{ .op = .call, .ty = .bool, .a = @fromBackingInt(marker_at), .data = try hand.extra(&.{ try hand.param(0), try hand.param(1) }) };
    if (spec.calls.len == 0) return .{ .op = .iconst, .ty = spec.ret, .data = 7 };
    return .{ .op = .call, .ty = .i64, .a = @fromBackingInt(indexOf(specs, spec.calls)), .data = try hand.extra(&.{}) };
}

fn finalsOf(a: std.mem.Allocator, module: *const ir.Module, options: emitter.Options) ![]?optimization.FinalMetadata {
    const finals = try a.alloc(?optimization.FinalMetadata, module.functions.items.len);
    var canon = try @import("canonical_ir.zig").Canon.prepare(a, module, options.locator);
    for (finals, 0..) |*final, index| {
        const digest = try canon.functionDigest(@intCast(index));
        final.* = .{
            .key = digest,
            .body = .{ .positioned = digest, .plain = digest },
            .render = .{ .ancestry = @splat(0), .scopes = &.{} },
            .outgoing = try @import("optimizer_shortcut.zig").Index.targets(a, &module.functions.items[index]),
            .analysis = .{ .digest = @splat(0), .loop_ids = &.{} },
            .state = .{ .known = null, .plans = &.{}, .counts = .{}, .own = .{} },
        };
    }
    return finals;
}

fn present(_: *anyopaque, _: u32) @import("demand_ir.zig").Error!void {}

/// What a build needs: the arena for its results, a thread-safe allocator for its workers, the store, and a function whose "may write"
/// summary the build flips (the analysis changed though no body did).
/// `hooks` binds device hooks (`Main.hooks`, by name, to the functions at the indices after `main`); `receipts` turns the compact receipts
/// off, so that only the exact emission records serve a unit.
const Env = struct { a: std.mem.Allocator, gpa: std.mem.Allocator, store: *const stages.Store, flipped: ?u32 = null, hooks: []const []const u8 = &.{}, receipts: bool = true };

/// What one build of `module` asked of the store: units served by a receipt, and units rendered.
const Outcome = struct { counts: emission_cache.Counts, emitted: []units.Unit };

fn emit(env: Env, module: *const ir.Module, finals: []const ?optimization.FinalMetadata) !Outcome {
    const a = env.a;
    const where: u8 = 0;
    const summaries = try @import("effects.zig").analyze(a, module);
    if (env.flipped) |index| summaries.may[index][0] = !summaries.may[index][0];
    const options: emitter.Options = .{ .locator = .{ .context = &where, .locate = location }, .source_path = "receipts.selka", .main = .{ .hooks = env.hooks }, .analysis = .{ .effects = &summaries } };
    const source = try language.source.Source.init(a, "receipts.selka", "source\n");
    var counts: emission_cache.Counts = .{};
    var anchor: u8 = 0;
    const context: emission_cache.Context = .{
        .store = env.store,
        .counts = &counts,
        .lanes = 2,
        .receipts = if (env.receipts) .{ .finals = finals, .source = &source, .loader = .{ .pointer = &anchor, .ensure_fn = present } } else null,
    };
    const emitted = try units.emitCached(a, env.gpa, module, options, context);
    const fresh = try units.emitWithScratch(a, env.gpa, module, options);
    try std.testing.expectEqual(fresh.len, emitted.len);
    for (fresh, emitted) |left, right| try std.testing.expectEqualStrings(left.llvm, right.llvm);
    return .{ .counts = counts, .emitted = emitted };
}

fn optionsAt(where: *const u8) emitter.Options {
    return .{ .locator = .{ .context = where, .locate = location }, .source_path = "receipts.selka", .main = .{} };
}

fn cold(env: Env, specs: []const Spec, unrelated: usize) !Outcome {
    const a = env.a;
    const module = try build(a, specs, unrelated);
    const where: u8 = 0;
    return emit(env, &module, try finalsOf(a, &module, optionsAt(&where)));
}

const base = [_]Spec{
    .{ .name = "unit[main]", .calls = "unit[a]" },
    .{ .name = "unit[a]", .calls = "unit[b]" },
    .{ .name = "unit[b]" },
    .{ .name = "unit[c]" },
    .{ .name = "unit[eq]", .record = true },
};

fn openStore(a: std.mem.Allocator, gpa: std.mem.Allocator, directory: *std.testing.TmpDir) !stages.Store {
    return stages.Store.init(gpa, std.testing.io, try directory.dir.realPathFileAlloc(std.testing.io, ".", a));
}

test "a repeated build is served by its receipts and a function added at the front renders only its own unit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var store = try openStore(a, std.testing.allocator, &directory);
    defer store.deinit();
    const env: Env = .{ .a = a, .gpa = std.testing.allocator, .store = &store };
    const first = try cold(env, &base, 0);
    const again = try cold(env, &base, 0);
    const added = try cold(env, &[_]Spec{.{ .name = "unit[new]", .calls = "unit[c]" }} ++ base, 0);
    try std.testing.expectEqual(@as(u32, 6), first.counts.rendered);
    try std.testing.expectEqual(@as(u32, 6), again.counts.reused);
    try std.testing.expectEqual(@as(u32, 0), again.counts.rendered);
    try std.testing.expectEqual(@as(u32, 7), added.counts.units);
    try std.testing.expectEqual(@as(u32, 1), added.counts.rendered);
    try std.testing.expectEqual(@as(u32, 6), added.counts.reused);
    try std.testing.expect(@import("stage_scopes.zig").table.get("llvm-compact-receipt-v2") != null);
}

test "a function whose signature changed misses its own unit and its callers' and no other" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var store = try openStore(a, std.testing.allocator, &directory);
    defer store.deinit();
    const env: Env = .{ .a = a, .gpa = std.testing.allocator, .store = &store };
    const where: u8 = 0;
    const module = try build(a, &base, 0);
    const finals = try finalsOf(a, &module, optionsAt(&where));
    _ = try emit(env, &module, finals);
    var changed = base;
    changed[indexOf(&base, "unit[b]")].ret = .i32;
    const edited = try build(a, &changed, 0);
    const edited_finals = try finalsOf(a, &edited, optionsAt(&where));
    const outcome = try emit(env, &edited, edited_finals);
    try std.testing.expectEqual(@as(u32, 2), outcome.counts.rendered);
    try std.testing.expectEqual(@as(u32, 4), outcome.counts.reused);
}

test "a function whose effects changed misses its own unit and its callers', whose bodies did not, and no other" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var store = try openStore(a, std.testing.allocator, &directory);
    defer store.deinit();
    const where: u8 = 0;
    const module = try build(a, &base, 0);
    const finals = try finalsOf(a, &module, optionsAt(&where));
    const env: Env = .{ .a = a, .gpa = std.testing.allocator, .store = &store };
    const flipped: Env = .{ .a = a, .gpa = std.testing.allocator, .store = &store, .flipped = indexOf(&base, "unit[b]") };
    _ = try emit(env, &module, finals);
    const outcome = try emit(flipped, &module, finals);
    try std.testing.expectEqual(@as(u32, 2), outcome.counts.rendered);
    try std.testing.expectEqual(@as(u32, 4), outcome.counts.reused);
}

test "a type added ahead of a record renders no unit that does not read it, and a new unit that reads a new type renders alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var store = try openStore(a, std.testing.allocator, &directory);
    defer store.deinit();
    const env: Env = .{ .a = a, .gpa = std.testing.allocator, .store = &store };
    _ = try cold(env, &base, 0);
    const shifted = try cold(env, &base, 3);
    const reading = try cold(env, &(base ++ [_]Spec{.{ .name = "unit[eq2]", .record = true }}), 3);
    try std.testing.expectEqual(@as(u32, 0), shifted.counts.rendered);
    try std.testing.expectEqual(@as(u32, 6), shifted.counts.reused);
    try std.testing.expectEqual(@as(u32, 1), reading.counts.rendered);
    try std.testing.expectEqual(@as(u32, 6), reading.counts.reused);
}

test "a nominal record whose fields change misses the unit that reads it, though its descriptor keeps its id" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var store = try openStore(a, std.testing.allocator, &directory);
    defer store.deinit();
    const env: Env = .{ .a = a, .gpa = std.testing.allocator, .store = &store };
    const where: u8 = 0;
    const first = try buildShaped(a, &base, .{ .named = true });
    const retyped = try buildShaped(a, &base, .{ .named = true, .fields = &.{ .i32, .str } });
    const widened = try buildShaped(a, &base, .{ .named = true, .fields = &.{ .i64, .str, .i64 } });
    // The optimizer's records are made afresh for each module, as the optimizer makes them: a function that names the record has
    // another body digest, since digests take a type by structure, though the record's descriptor id (its name) is unchanged.
    const finals = try finalsOf(a, &first, optionsAt(&where));
    const retyped_finals = try finalsOf(a, &retyped, optionsAt(&where));
    const widened_finals = try finalsOf(a, &widened, optionsAt(&where));
    const record: ir.Type = @fromBackingInt(ir.Type.first_compound);
    const kept = try type_ids.Table.build(a, &first);
    const changed = try type_ids.Table.build(a, &retyped);
    _ = try emit(env, &first, finals);
    const after_type = try emit(env, &retyped, retyped_finals);
    const after_field = try emit(env, &widened, widened_finals);
    try std.testing.expectEqualSlices(u8, &kept.text(record), &changed.text(record));
    try std.testing.expectEqual(@as(u32, 1), after_type.counts.rendered);
    try std.testing.expectEqual(@as(u32, 5), after_type.counts.reused);
    try std.testing.expectEqual(@as(u32, 1), after_field.counts.rendered);
    try std.testing.expectEqual(@as(u32, 5), after_field.counts.reused);
}

test "a unit's compact key is the same when it is asked again, and a callee the unit's functions share is bound once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var store = try openStore(a, std.testing.allocator, &directory);
    defer store.deinit();
    const where: u8 = 0;
    const module = try build(a, &base, 0);
    const given = optionsAt(&where);
    const summaries = try @import("effects.zig").analyze(a, &module);
    var options = given;
    options.analysis.effects = &summaries;
    const source = try language.source.Source.init(a, "receipts.selka", "source\n");
    var anchor: u8 = 0;
    var canon = try @import("canonical_ir.zig").Canon.prepare(a, &module, options.locator);
    const catalog = try @import("emit_constants.zig").Catalog.init(a, &module);
    var compact = (try @import("emission_key.zig").Compact.init(a, &module, options, &canon, .{
        .store = &store,
        .receipts = .{ .finals = try finalsOf(a, &module, options), .source = &source, .loader = .{ .pointer = &anchor, .ensure_fn = present } },
    })).?;
    const exported = try a.alloc(bool, module.functions.items.len);
    @memset(exported, true);
    const symbols = try a.alloc(?[]const u8, exported.len);
    @memset(symbols, null);
    const main_at = indexOf(&base, "unit[main]");
    const caller_at = indexOf(&base, "unit[a]");
    const together: emitter.Selection = .{ .functions = &.{ main_at, caller_at }, .exported = exported, .symbols = symbols, .source_path = "receipts.selka", .constants = &catalog };
    const alone: emitter.Selection = .{ .functions = &.{main_at}, .exported = exported, .symbols = symbols, .source_path = "receipts.selka", .constants = &catalog };
    const first = (try compact.key(a, &module, options, together)).?;
    const again = (try compact.key(a, &module, options, together)).?;
    const other = (try compact.key(a, &module, options, alone)).?;
    const last = (try compact.key(a, &module, options, together)).?;
    try std.testing.expectEqualSlices(u8, &first, &again);
    try std.testing.expectEqualSlices(u8, &first, &last);
    try std.testing.expect(!std.mem.eql(u8, &first, &other));
}

/// Feed the same bytes to a plain hasher and a staged one in writes of every width from 1 to 59, then in a write wider than the
/// staging buffer and a short one, so the buffer fills, flushes and is bypassed. Returns both digests.
fn stagedAndPlain() [2][32]u8 {
    const Staged = @import("emission_key.zig").Staged;
    var bytes: [5000]u8 = undefined;
    for (&bytes, 0..) |*byte, at| byte.* = @truncate(at *% 131 +% 7);
    var plain = @import("fast_blake3.zig").Blake3.init(.{});
    var staged = Staged.init();
    var at: usize = 0;
    for (1..60) |width| {
        plain.update(bytes[at..][0..width]);
        staged.update(bytes[at..][0..width]);
        at += width;
    }
    plain.update(bytes[at..][0..1500]);
    staged.update(bytes[at..][0..1500]);
    plain.update(bytes[at + 1500 ..][0..40]);
    staged.update(bytes[at + 1500 ..][0..40]);
    var digests: [2][32]u8 = undefined;
    plain.final(&digests[0]);
    staged.final(&digests[1]);
    return digests;
}

test "a staged hasher gives the digest of the same bytes written one at a time" {
    const digests = stagedAndPlain();
    try std.testing.expectEqualSlices(u8, &digests[0], &digests[1]);
}

/// A program of `unit[main]` and two functions a device hook can bind, in the two orders: the hook `start` binds the function at index 1.
const hooked = [_]Spec{ .{ .name = "unit[main]" }, .{ .name = "unit[a]" }, .{ .name = "unit[b]" } };
const hooked_swapped = [_]Spec{ .{ .name = "unit[main]" }, .{ .name = "unit[b]" }, .{ .name = "unit[a]" } };

/// The text of the entry unit of `specs` with the hook `start` bound to its function at index 1, built through `env`'s store
/// (`emit` also checks it against the text a fresh emission makes).
fn startUnit(env: Env, specs: []const Spec) ![]const u8 {
    var bound = env;
    bound.hooks = &.{"start"};
    const module = try build(env.a, specs, 0);
    const where: u8 = 0;
    const outcome = try emit(bound, &module, try finalsOf(env.a, &module, optionsAt(&where)));
    for (outcome.emitted) |unit| if (std.mem.indexOf(u8, unit.llvm, "define void @myl_bare_platform_start") != null) return unit.llvm;
    return error.TestUnexpectedResult;
}

/// Two builds of one program through one store, whose devices bind `start` to different functions: each entry unit calls its own.
fn expectOwnHooks(receipts: bool) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var store = try openStore(a, std.testing.allocator, &directory);
    defer store.deinit();
    const env: Env = .{ .a = a, .gpa = std.testing.allocator, .store = &store, .receipts = receipts };
    const first = try startUnit(env, &hooked);
    const second = try startUnit(env, &hooked_swapped);
    try std.testing.expect(std.mem.indexOf(u8, first, "@\"my.unit[a]\"(i64 0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, second, "@\"my.unit[b]\"(i64 0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, second, "@\"my.unit[a]\"") == null);
}

test "a device hook bound to another function is another entry unit: its compact receipt and its exact record are not the first binding's" {
    try expectOwnHooks(true);
}

test "a device hook bound to another function is another entry unit when only the exact emission records serve it" {
    try expectOwnHooks(false);
}
