//! Check complete ordinary-value graphs independently of a wire representation.
const std = @import("std");
const typed = @import("typed.zig");
pub fn check(allocator: std.mem.Allocator, records: []const typed.Record, root: typed.Type, allow_domains: bool) !void {
    var pending: std.ArrayList(typed.Type) = .empty;
    defer pending.deinit(allocator);
    const seen = try allocator.alloc(bool, typed.Type.record_base + records.len);
    defer allocator.free(seen);
    @memset(seen, false);
    try pending.append(allocator, root);
    while (pending.pop()) |ty| {
        if (@backingInt(ty) >= seen.len) return error.InvalidDataType;
        if (seen[@backingInt(ty)]) continue;
        seen[@backingInt(ty)] = true;
        if (ty.isInteger() or ty == .bool) continue;
        if (!ty.isAggregate()) return error.NotDataType;
        const record = records[ty.recordIndex()];
        if (record.buffer != null or record.resource != null or record.pool != null or record.handle_pool != null or record.move_only) return error.NotDataType;
        if (record.domain) |backing| {
            if (!allow_domains) return error.NotDataType;
            try pending.append(allocator, backing);
        } else if (record.array) |array| {
            try pending.append(allocator, array.element);
            if (array.key) |key| try pending.append(allocator, key);
        } else if (record.variants) |variants| {
            for (variants.cases) |case| if (case.payload) |payload| try pending.append(allocator, payload);
        } else for (record.fields) |field| try pending.append(allocator, field.ty);
    }
}
