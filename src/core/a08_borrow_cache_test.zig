//! Borrow selections remain checked across lowering and optimizer artifacts.
const std = @import("std");
const language = @import("mylang");
const ir = @import("ir.zig");
const build = @import("build.zig");
const lowering = @import("lowering_cache.zig");
const optimizer = @import("optimization_cache.zig");
const snapshot = @import("ir_snapshot.zig");
const stage = @import("stage_store.zig");
const passes = @import("passes.zig");
const emitter = @import("emit_llvm.zig");
const support = @import("test_support.zig");
const ownership = @import("single_owner.zig");
const selection = @import("borrow_selection.zig");
const origins = @import("inline_origins.zig");
const source_path = "borrow-cache.my";
const source =
    \\func selected_size(values: dict[str, int[]], key: str, fallback: int[]) -> int:
    \\    return len(values.get(key, fallback))
    \\func main(out: Stream) -> int:
    \\    mut values = {"hit": [1, 2, 3]}
    \\    mut fallback = [4, 5]
    \\    out.print(selected_size(values, "hit", fallback), selected_size(values, "miss", fallback))
    \\    values.clear()
    \\    fallback.append(6)
    \\    out.print(len(values) + 1, len(fallback))
    \\    return 0
;

fn locate(_: *const anyopaque, offset: u32) emitter.Location {
    return .{ .path = source_path, .line = 1, .column = offset + 1 };
}

fn checked(a: std.mem.Allocator, text: []const u8) !language.Compilation {
    var unit = try language.Compilation.init(a, source_path, text);
    try unit.check();
    var failure: ownership.Failure = .{};
    try ownership.checkMode(a, unit.program.?, &failure, true);
    return unit;
}

const Outcome = struct { llvm: []const u8, lowered: usize, reused: usize, hits: usize, physical: ir.Type };

fn compile(a: std.mem.Allocator, backing: std.mem.Allocator, storage: *stage.Store, text: []const u8, cached: bool, release: bool) !Outcome {
    const unit = try checked(a, text);
    const input: build.Input = .{ .program = unit.program.?, .source = unit.src, .single_owner = true, .zero_rc = true };
    var refusal: build.Refusal = .{};
    var low = lowering.Cache.init(storage);
    var module = if (cached) try build.buildExecutableCached(a, input, &refusal, &low) else try build.buildExecutable(a, input, &refusal);
    var physical: ?ir.Type = null;
    for (module.functions.items) |*function| {
        if (try selection.declaration(&module, function)) physical = function.signature.params[1];
    }
    try std.testing.expect(physical != null);
    const token: u8 = 0;
    const locator: emitter.Locator = .{ .context = &token, .locate = locate };
    var cache = optimizer.Context.init(storage, try snapshot.Context.init(a, &module, unit.src), locator);
    const result = if (release)
        if (cached) try passes.runCached(a, backing, &module, .verify, &cache) else try passes.runWithScratch(a, backing, &module, .verify)
    else if (cached)
        try passes.debugCached(a, backing, &module, &cache)
    else
        try passes.debugWithScratch(a, backing, &module);
    var failure: ownership.Failure = .{};
    try ownership.verifyLowered(&module, &failure);
    try support.verified(a, &module, result.plans);
    const llvm = try emitter.emitModule(a, &module, .{
        .locator = locator,
        .source_path = source_path,
        .main = .{ .parameters = &.{"out"} },
        .verify = true,
        .analysis = support.analysis(&result),
    });
    try std.testing.expect(@import("zero_rc.zig").emittedClean(llvm));
    try std.testing.expect(std.mem.indexOf(u8, llvm, selection.prefix) == null);
    var hits: usize = 0;
    for (cache.statistics.hits) |count| hits += count;
    return .{ .llvm = llvm, .lowered = low.lowered, .reused = low.reused, .hits = hits, .physical = physical.? };
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "zero RC A08 borrowed selection cache replay tracks physical discovery in debug and release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try stage.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const prefix = "record Earlier:\n    labels: bytes[]\nfunc earlier() -> Earlier:\n    return Earlier(labels=[b\"a\"])\n";
    const body = try std.mem.replaceOwned(u8, a, source, "    mut values", "    const before = earlier()\n    assert len(before.labels) == 1\n    mut values");
    const edited = try std.mem.concat(a, u8, &.{ prefix, body });
    for ([_]bool{ false, true }) |release| {
        var physical: [2]ir.Type = undefined;
        for ([_][]const u8{ source, edited }, 0..) |text, index| {
            const fresh = try compile(a, std.testing.allocator, &storage, text, false, release);
            const cold = try compile(a, std.testing.allocator, &storage, text, true, release);
            const warm = try compile(a, std.testing.allocator, &storage, text, true, release);
            try std.testing.expectEqualStrings(fresh.llvm, cold.llvm);
            try std.testing.expectEqualStrings(fresh.llvm, warm.llvm);
            try std.testing.expect(warm.reused > 0);
            try std.testing.expectEqual(@as(usize, 0), warm.lowered);
            try std.testing.expect(warm.hits > 0);
            try std.testing.expectEqual(cold.physical, warm.physical);
            physical[index] = warm.physical;
        }
        try std.testing.expect(physical[0] != physical[1]);
    }
}

fn selected(module: *const ir.Module) !struct { function: u32, value: selection.Selection } {
    for (module.functions.items, 0..) |*function, index| {
        for (function.insts.items) |inst| {
            if (try selection.call(module, function, inst)) |value| {
                if (value.phi != null) return .{ .function = @intCast(index), .value = value };
            }
        }
    }
    return error.TestUnexpectedResult;
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "zero RC A08 malformed borrowed selection cached debug body misses and repairs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try stage.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const unit = try checked(a, source);
    const input: build.Input = .{ .program = unit.program.?, .source = unit.src, .single_owner = true, .zero_rc = true };
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, input, &refusal);
    const initial = try selected(&module);
    const token: u8 = 0;
    const locator: emitter.Locator = .{ .context = &token, .locate = locate };
    var cache = optimizer.Context.init(&storage, try snapshot.Context.init(a, &module, unit.src), locator);
    try cache.prepare(a);
    var ancestry: origins.Table = .{};
    const effects = try @import("effects.zig").analyze(a, &module);
    const key = (try cache.key(a, .{ .stage = .debug, .function = initial.function, .mode = 0, .provenance = &ancestry, .inputs = .{ .effects = &effects } })).?;
    const result = try passes.debugCached(a, std.testing.allocator, &module, &cache);
    try support.verified(a, &module, result.plans);
    const good = (try storage.loadValue(a, key, optimizer.Final)).?;
    const final_selection = try selected(&module);
    try std.testing.expectEqual(initial.function, final_selection.function);
    const phi = final_selection.value.phi.?;
    var broken = good;
    broken.function.function.extra = try a.dupe(ir.Ref, good.function.function.extra);
    const range = ir.ExtraSlice.unpack(broken.function.function.insts[phi.index()].data);
    // Both operands are valid, dominating and type-correct. Their root proof is false.
    @memset(broken.function.function.extra[range.start..][0..range.len], final_selection.value.fallback);
    var decoded = try snapshot.restore(a, cache.source, broken.function);
    try std.testing.expectError(error.UnsupportedInstruction, selection.validate(a, &module, &decoded));
    try std.testing.expectError(error.Unsupported, @import("own.zig").function(a, &module, &decoded, .{}));
    try storage.storeValue(key, optimizer.Final, broken);
    const persisted = (try cache.load(a, .debug, key, optimizer.Final)).?;
    try std.testing.expect(try cache.restore(a, initial.function, persisted.function, persisted.provenance, &ancestry) == null);
    cache.rejected(.debug);
    try std.testing.expect(cache.statistics.misses[@backingInt(optimizer.Stage.debug)] > 0);
    // A real fresh pipeline sees the malformed artifact, rejects it, and publishes repair.
    var fresh_module = try build.buildExecutable(a, input, &refusal);
    var fresh_cache = optimizer.Context.init(&storage, try snapshot.Context.init(a, &fresh_module, unit.src), locator);
    const recovered = try passes.debugCached(a, std.testing.allocator, &fresh_module, &fresh_cache);
    try support.verified(a, &fresh_module, recovered.plans);
    try std.testing.expect(fresh_cache.statistics.misses[@backingInt(optimizer.Stage.debug)] > 0);
    const repaired = (try storage.loadValue(a, key, optimizer.Final)).?;
    const restored = (try fresh_cache.restore(a, initial.function, repaired.function, repaired.provenance, &ancestry)).?;
    try selection.validate(a, &fresh_module, &restored);
    var expected = try @import("canonical_ir.zig").Canon.prepare(a, &module, locator);
    var actual = try @import("canonical_ir.zig").Canon.prepare(a, &fresh_module, locator);
    try std.testing.expectEqual(module.functions.items.len, fresh_module.functions.items.len);
    for (0..module.functions.items.len) |index| {
        try std.testing.expectEqual(try expected.functionDigest(@intCast(index)), try actual.functionDigest(@intCast(index)));
    }
    // The same central guard protects final/checkpoint restoration, even without own rerun.
    const transform: optimizer.Transform = .{ .function = broken.function, .provenance = broken.provenance, .changed = 1, .output = null };
    try std.testing.expect(try fresh_cache.restoreTransform(a, a, initial.function, transform, &ancestry) == null);
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "zero RC A08 borrowed selection rejects mismatched predecessor operands on restoration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try stage.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const unit = try checked(a, source);
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = unit.program.?, .source = unit.src, .single_owner = true, .zero_rc = true }, &refusal);
    const result = try passes.debug(a, &module);
    try support.verified(a, &module, result.plans);
    const found = try selected(&module);
    const function = &module.functions.items[found.function];
    const context = try snapshot.Context.init(a, &module, unit.src);
    const wire = try snapshot.capture(a, context, function.*);
    const phi = found.value.phi.?;
    const range = ir.ExtraSlice.unpack(wire.function.insts[phi.index()].data);
    try std.testing.expectEqual(@as(u32, 2), range.len);
    std.mem.swap(ir.Ref, &wire.function.extra[range.start], &wire.function.extra[range.start + 1]);
    const decoded = try snapshot.restore(a, context, wire);
    var failure: @import("verify_ir.zig").Failure = .{};
    try std.testing.expectError(error.InvalidIr, @import("verify_ir.zig").verifyFunction(a, &module, &decoded, &failure));
    try std.testing.expect(std.mem.indexOf(u8, failure.reason, "dominate") != null);
    // The always-on wrapper must reject even with the optional global verifier off.
    try std.testing.expectError(error.UnsupportedInstruction, @import("marker_validation.zig").validate(a, &module, &decoded));
    const token: u8 = 0;
    var cache = optimizer.Context.init(&storage, context, .{ .context = &token, .locate = locate });
    var ancestry: origins.Table = .{};
    const provenance = try optimizer.Provenance.capture(a, context, &result.provenance, found.function);
    try std.testing.expect(try cache.restore(a, found.function, wire, provenance, &ancestry) == null);
}
