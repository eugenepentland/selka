//! Portable post-fusion bodies and the exact appended runtime declaration catalog.
const std = @import("std");
const ir = @import("ir.zig");
const cache = @import("optimization_cache.zig");
const snapshot = @import("ir_snapshot.zig");
const demand = @import("demand_ir.zig");
const codec = @import("mylang").persist_codec;

/// Runtime declarations appended by the optimizer's source-local fusions.
pub const Declaration = struct { name: []const u8, signature: ir.Signature };
/// Prior helper ownership proves that replay preserves the eager declaration order.
pub const Catalog = struct {
    layout: ?[32]u8 = null,
    raw_count: usize = 0,
    declarations: []const Declaration = &.{},
    uses: []const [32]u8 = &.{},
};
/// A changed fusion retains a full base body; unchanged fusions alias raw lowering.
pub const Body = struct { identity: bool = false, key: ?[32]u8 = null };

/// Replay only the previously validated runtime declarations, before dirty fusions.
pub fn seed(a: std.mem.Allocator, module: *ir.Module, catalog: Catalog) demand.Error!void {
    if (catalog.raw_count != module.functions.items.len) return error.CacheMiss;
    if (catalog.uses.len != catalog.raw_count) return error.CacheMiss;
    for (catalog.declarations) |declaration| {
        if (declaration.signature.linkage != .runtime_c) return error.CacheMiss;
        for (module.functions.items) |function| if (std.mem.eql(u8, function.name, declaration.name)) return error.CacheMiss;
        try module.functions.append(a, .{ .name = declaration.name, .signature = declaration.signature });
    }
}

/// Bind every appended-helper reference in post-fusion instruction order.
pub fn usage(a: std.mem.Allocator, function: *const ir.Function, raw_count: usize) std.mem.Allocator.Error![32]u8 {
    var writer = codec.Writer.init(a);
    defer writer.deinit();
    for (function.insts.items) |inst| {
        if (inst.op != .call and inst.op != .func_ref) continue;
        const target: u32 = if (inst.op == .call) @intCast(inst.a.index()) else @intCast(inst.data);
        if (target >= raw_count) try writer.write(u32, target);
    }
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(writer.bytes.items, &digest, .{});
    return digest;
}

/// Capture a complete fused input under its lowering, catalog and body identities.
pub fn save(a: std.mem.Allocator, context: *cache.Context, index: u32, lowered: [32]u8, output: [32]u8) std.mem.Allocator.Error!?[32]u8 {
    const layout = context.layoutDigest() orelse return null;
    const key = context.store.key("optimizer-fusion-v1", &.{ &lowered, &layout, &output });
    const wire = snapshot.capture(a, context.source, context.source.module.functions.items[index]) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidSnapshot => return null,
    };
    try context.store.storeValue(key, snapshot.Wire, wire);
    return key;
}
