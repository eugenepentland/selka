//! Check complete ordinary-value graphs independently of a wire representation.
const std = @import("std");
const typed = @import("typed.zig");
pub fn check(allocator: std.mem.Allocator, records: []const typed.Record, root: typed.Type, allow_domains: bool) !void {
    return checkMode(allocator, records, root, if (allow_domains) .backing else .reject);
}
pub fn checkCodecs(allocator: std.mem.Allocator, records: []const typed.Record, root: typed.Type) !void {
    return checkMode(allocator, records, root, .wire);
}
fn checkMode(allocator: std.mem.Allocator, records: []const typed.Record, root: typed.Type, mode: enum { reject, backing, wire }) !void {
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
            const next = switch (mode) {
                .reject => return error.NotDataType,
                .backing => backing,
                .wire => wire: {
                    const wire_type = (record.codec orelse return error.NotDataType).wire;
                    // The source contract requires an ordinary wire graph. Recheck
                    // here before traversal, including for host-supplied catalogs.
                    try checkMode(allocator, records, wire_type, .reject);
                    break :wire wire_type;
                },
            };
            try pending.append(allocator, next);
        } else if (record.array) |array| {
            try pending.append(allocator, array.element);
            if (array.key) |key| try pending.append(allocator, key);
        } else if (record.variants) |variants| {
            for (variants.cases) |case| if (case.payload) |payload| try pending.append(allocator, payload);
        } else for (record.fields) |field| try pending.append(allocator, field.ty);
    }
}
