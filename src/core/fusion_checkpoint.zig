//! Portable post-fusion bodies and the exact appended runtime declaration catalog.
const std = @import("std");
const cache_miss = @import("selka").cache_miss;
const ir = @import("ir.zig");
const cache = @import("optimization_cache.zig");
const snapshot = @import("ir_snapshot.zig");
const demand = @import("demand_ir.zig");

/// Runtime declarations appended by the optimizer's source-local fusions.
pub const Declaration = struct { name: []const u8, signature: ir.Signature };
/// Prior helper ownership proves that replay preserves the eager declaration order.
pub const Catalog = struct {
    /// The layout after fusion: the declarations fusions appended, with the program's compounds and signatures.
    layout: ?[32]u8 = null,
    /// The layout before fusion (`ir_snapshot.layout` of the lowered module). A candidate catalog is reused only when this
    /// equals the build's own raw layout, so a type or signature edit never seeds declarations an edited program does not have.
    raw_layout: ?[32]u8 = null,
    raw_count: usize = 0,
    declarations: []const Declaration = &.{},
    requests: []const []const u32 = &.{},
};
/// A changed fusion retains a full base body; unchanged fusions alias raw lowering.
pub const Body = struct { identity: bool = false, key: ?[32]u8 = null };

/// Replay only the previously validated runtime declarations, before dirty fusions.
pub fn seed(a: std.mem.Allocator, module: *ir.Module, catalog: Catalog) demand.Error!void {
    if (catalog.raw_count != module.functions.items.len) return cache_miss.at(@src());
    if (catalog.requests.len != catalog.raw_count) return cache_miss.at(@src());
    for (catalog.declarations) |declaration| {
        if (declaration.signature.linkage != .runtime_c) return cache_miss.at(@src());
        for (module.functions.items) |function| if (std.mem.eql(u8, function.name, declaration.name)) return cache_miss.at(@src());
        try module.functions.append(a, .{ .name = declaration.name, .signature = declaration.signature });
    }
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
