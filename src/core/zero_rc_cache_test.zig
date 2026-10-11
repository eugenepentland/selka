//! Ownership modes must never share incompatible lowered, optimized or emitted code.
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
const owned = @import("single_owner.zig");
const zero = @import("zero_rc.zig");
const Outcome = struct { llvm: []const u8, lowered: usize, reused: usize };
const source =
    \\func values(n: int) -> int[]:
    \\    return [n, n + 1, n + 2]
    \\func main(out: Stream) -> int:
    \\    mut original = values(7)
    \\    const saved = original.copy()
    \\    original.clear()
    \\    out.print(len(saved), saved[1])
    \\    return 0
;
fn location(_: *const anyopaque, offset: u32) emitter.Location {
    return .{ .path = "cache-modes.my", .line = 1, .column = offset + 1 };
}
fn compile(a: std.mem.Allocator, backing: std.mem.Allocator, storage: *stage.Store, input: build.Input, cached: bool) !Outcome {
    var refusal: build.Refusal = .{};
    var lowering_cache = lowering.Cache.init(storage);
    var module = if (cached) try build.buildExecutableCached(a, input, &refusal, &lowering_cache) else try build.buildExecutable(a, input, &refusal);
    const context: u8 = 0;
    const locator: emitter.Locator = .{ .context = &context, .locate = location };
    var cache = optimizer.Context.init(storage, try snapshot.Context.init(a, &module, input.source), locator);
    const result = if (cached) try passes.runCached(a, backing, &module, .verify, &cache) else try passes.runWithScratch(a, backing, &module, .verify);
    if (input.zero_rc) {
        var failure: owned.Failure = .{};
        try owned.verifyLowered(&module, &failure);
    }
    const llvm = try emitter.emitModule(a, &module, .{
        .locator = locator,
        .source_path = "cache-modes.my",
        .main = .{ .parameters = &.{"out"} },
        .verify = true,
        .analysis = support.analysis(&result),
    });
    if (input.zero_rc) try std.testing.expect(zero.emittedClean(llvm));
    return .{ .llvm = llvm, .lowered = lowering_cache.lowered, .reused = lowering_cache.reused };
}
// spec: NEW-CORE-ZERO-RC-CACHE-1
test "zero RC caches isolate three ownership modes and reproduce the uncached oracle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var storage = try stage.Store.init(std.testing.allocator, std.testing.io, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    var unit = try language.Compilation.init(a, "cache-modes.my", source);
    try unit.check();
    var seen: [3]bool = @splat(false);
    for ([_]u8{ 0, 2, 1, 2, 0, 1 }) |mode| {
        const input: build.Input = .{ .program = unit.program.?, .source = unit.src, .single_owner = mode != 0, .zero_rc = mode == 2 };
        const fresh = try compile(a, std.testing.allocator, &storage, input, false);
        const saved = try compile(a, std.testing.allocator, &storage, input, true);
        try std.testing.expectEqualStrings(fresh.llvm, saved.llvm);
        if (seen[mode]) {
            try std.testing.expect(saved.reused > 0);
            try std.testing.expectEqual(@as(usize, 0), saved.lowered);
        } else {
            try std.testing.expect(saved.lowered > 0);
            try std.testing.expectEqual(@as(usize, 0), saved.reused);
        }
        seen[mode] = true;
    }
}
fn copyKey(a: std.mem.Allocator, shifted: bool, inner: ir.Type) ![32]u8 {
    var module: ir.Module = .{ .single_owner = true, .zero_rc = true };
    if (shifted) _ = try module.intern(a, .{ .array = .{ .elem = .u8, .n = 5 } });
    const ty = try module.intern(a, .{ .box = inner });
    const name = try std.fmt.allocPrint(a, "{s}{d}", .{ @import("emit_values.zig").copy_prefix, @backingInt(ty) });
    const helper = try @import("test_builder.zig").helper(a, &module, name, &.{ty}, ty);
    const context: u8 = 0;
    var canon = try @import("canonical_ir.zig").Canon.prepare(a, &module, .{ .context = &context, .locate = location });
    return canon.callee(helper);
}
// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "zero RC generated copy identities follow type structure across catalog shifts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try copyKey(a, false, .i64);
    try std.testing.expectEqual(original, try copyKey(a, true, .i64));
    try std.testing.expect(!std.mem.eql(u8, &original, &try copyKey(a, true, .str)));
}
