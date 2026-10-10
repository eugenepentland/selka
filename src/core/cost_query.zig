//! Static final-Core queries. Keys cover every input read by cost.functionCounts.
const std = @import("std");
const ir = @import("ir.zig");
const passes = @import("passes.zig");
const cost = @import("cost.zig");
const canon = @import("canonical_ir.zig");
const snapshot = @import("ir_snapshot.zig");
const storage = @import("stage_store.zig");
const llvm = @import("emit_llvm.zig");
const codec = @import("mylang").persist_codec;

/// Verification compares saved rows with an independent current measurement.
pub const Error = error{ OutOfMemory, InvalidQuery };

/// Actual rows restored, computed, or independently checked for this request.
pub const Statistics = struct { reused: usize = 0, computed: usize = 0, verified: usize = 0, bypassed: usize = 0 };
/// Borrowed store; all returned rows belong to the caller's arena.
pub const Cache = struct {
    store: *const storage.Store,
    verify: bool = false,
    statistics: Statistics = .{},

    /// Assemble current names/totals from separately verified per-body queries.
    pub fn measure(self: *Cache, a: std.mem.Allocator, module: *ir.Module, result: *const passes.Result, locator: llvm.Locator) Error!cost.Report {
        var canonical = canon.Canon.prepare(a, module, locator) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnknownMetadata => return self.fallback(a, module, result),
        };
        const layout = try snapshot.layout(a, .{ .module = module });
        const allocation = allocationIdentity(module);
        var rows: std.ArrayList(cost.Function) = .empty;
        var totals: cost.Counts = .{};
        for (module.functions.items, 0..) |function, index| {
            if (function.signature.linkage != .internal) continue;
            const input_key = try self.key(a, &canonical, .{ .layout = layout, .allocation = allocation }, result, @intCast(index));
            var counts: ?cost.Counts = if (input_key) |digest| try self.store.loadValue(a, digest, cost.Counts) else null;
            // LLVM evidence is a separate query and cannot enter a Core row.
            if (counts != null and counts.?.llvm_vectorized_loops != null) counts = null;
            if (counts != null and !self.verify) {
                self.statistics.reused += 1;
            } else {
                const fresh = cost.functionCounts(module, result, index);
                if (counts) |saved| {
                    if (!std.meta.eql(saved, fresh)) return error.InvalidQuery;
                    self.statistics.verified += 1;
                }
                counts = fresh;
                self.statistics.computed += 1;
                if (input_key) |digest| try self.store.storeValue(digest, cost.Counts, fresh) else self.statistics.bypassed += 1;
            }
            try rows.append(a, .{ .name = function.name, .counts = counts.? });
            totals.add(counts.?);
        }
        return .{ .functions = try rows.toOwnedSlice(a), .totals = totals };
    }

    fn fallback(self: *Cache, a: std.mem.Allocator, module: *const ir.Module, result: *const passes.Result) std.mem.Allocator.Error!cost.Report {
        const measured = try cost.measure(a, module, result, null);
        self.statistics.computed += measured.functions.len;
        self.statistics.bypassed += measured.functions.len;
        return measured;
    }

    /// Expose exact keys for loss/corruption qualification; unknown metadata bypasses.
    pub fn key(self: *const Cache, a: std.mem.Allocator, canonical: *canon.Canon, dependencies: Dependencies, result: *const passes.Result, index: u32) std.mem.Allocator.Error!?storage.Digest {
        const body = canonical.functionDigest(index) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnknownMetadata => return null,
        };
        var writer = codec.Writer.init(a);
        defer writer.deinit();
        const events = if (index < result.per_function.len) result.per_function[index] else passes.FunctionStats{};
        try writer.write(passes.FunctionStats, events);
        try writer.write(bool, result.emission.verifying);
        const known = if (index < result.known.len) result.known[index] else null;
        try writer.write(?[]const bool, if (known) |facts| facts.reachable else null);
        // Equal name/signature callees can have different allocation provenance.
        // The guarded catalog alone does not say which physical one was used.
        for (canonical.module.functions.items[index].insts.items) |inst| {
            const target: u32 = switch (inst.op) {
                .call => @intCast(inst.a.index()),
                .func_ref => @intCast(inst.data),
                else => continue,
            };
            try writer.write(u32, target);
        }

        // Callee canonical identity omits source-vs-synthesized extern provenance.
        // Bind this classification guard explicitly, including indirect func_refs.
        return self.store.key("static-cost-function-v1", &.{ &dependencies.layout, &dependencies.allocation, &body, writer.bytes.items });
    }
};

/// Common declaration guards, prepared once rather than once per function.
pub const Dependencies = struct { layout: storage.Digest, allocation: storage.Digest };
/// Source extern declarations stay opaque even when named like runtime helpers.
pub fn allocationIdentity(module: *const ir.Module) storage.Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    for (module.functions.items) |function| hash.update(&.{@intFromBool(function.span == 0)});
    var digest: storage.Digest = undefined;
    hash.final(&digest);
    return digest;
}
