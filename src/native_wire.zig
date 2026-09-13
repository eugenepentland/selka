//! Native host schemas for ordinary values and opt-in declared domain codecs.
const std = @import("std");
const typed = @import("typed.zig");

/// Mark finite value shapes supported by the selected host conversion mode.
pub fn supported(allocator: std.mem.Allocator, records: []const typed.Record, codecs: bool) std.mem.Allocator.Error![]bool {
    const flags = try allocator.alloc(bool, records.len);
    @memset(flags, false);
    var changed = true;
    while (changed) {
        changed = false;
        for (records, 0..) |record, i| {
            if (flags[i] or record.shape.hasRuntimeIdentity() or record.contract.move_only) continue;
            if (record.shape.domain != null) {
                const codec = record.contract.codec orelse continue;
                if (!codecs or !valueSupported(codec.wire, flags)) continue;
            } else if (!childrenSupported(record, flags)) continue;
            flags[i] = true;
            changed = true;
        }
    }
    return flags;
}
fn childrenSupported(record: typed.Record, flags: []const bool) bool {
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |ty| {
            if (!valueSupported(ty, flags)) return false;
        };
    } else if (record.shape.array) |array| {
        if (!valueSupported(array.element, flags)) return false;
    } else for (record.fields) |field| {
        if (!valueSupported(field.ty, flags)) return false;
    }
    return true;
}
fn valueSupported(ty: typed.Type, flags: []const bool) bool {
    return if (ty.isAggregate()) flags[ty.recordIndex()] else ty.isInteger() or ty == .bool;
}
