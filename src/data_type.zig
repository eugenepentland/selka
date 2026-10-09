//! Check complete ordinary-value graphs independently of a wire representation.
/// Failures returned by check; callers must handle these boundary errors.
pub const CheckError = error{
    InvalidDataType,
    NotDataType,
    OutOfMemory,
};

const std = @import("std");
const typed = @import("typed.zig");
/// Validate the complete ordinary data graph, optionally traversing domain backing types.
pub fn check(allocator: std.mem.Allocator, records: []const typed.Record, root: typed.Type, allow_domains: bool) CheckError!void {
    return checkMode(allocator, records, root, if (allow_domains) .backing else .reject);
}
/// Validate one trusted host-boundary type. Ordinary data crosses as copied
/// values; the immutable `bytes` byte string crosses as one owned payload the
/// packed bridge copies whole, so it is accepted at the boundary itself but not
/// as a field of some larger copied graph.
pub fn checkHost(allocator: std.mem.Allocator, records: []const typed.Record, root: typed.Type) CheckError!void {
    if (root.isAggregate() and root.recordIndex() < records.len and typed.isByteString(records[root.recordIndex()])) return;
    return check(allocator, records, root, true);
}
fn checkMode(allocator: std.mem.Allocator, records: []const typed.Record, root: typed.Type, mode: enum { reject, backing, wire }) !void {
    // A builtin integer or bool terminates the graph by itself. Traversal state
    // exists only for nominal graphs, so scalar boundaries -- every argument and
    // result of a raw byte host call -- must not pay for allocating it.
    if (root.isInteger() or root == .bool) return;
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
        if (record.contract.callback != null) return error.NotDataType;
        if (record.managed or record.shape.hasRuntimeIdentity() or record.contract.move_only) return error.NotDataType;
        // A tuple is taken apart by destructuring, not by a wire field name, so
        // it has no implicit codec: the boundary rejects it like a managed graph.
        if (record.shape.tuple) return error.NotDataType;
        if (record.shape.domain) |backing| {
            const next = switch (mode) {
                .reject => return error.NotDataType,
                .backing => backing,
                .wire => wire: {
                    const wire_type = (record.contract.codec orelse return error.NotDataType).wire;
                    // The source contract requires an ordinary wire graph. Recheck
                    // here before traversal, including for host-supplied catalogs.
                    try checkMode(allocator, records, wire_type, .reject);
                    break :wire wire_type;
                },
            };
            try pending.append(allocator, next);
        } else if (record.shape.array) |array| {
            try pending.append(allocator, array.element);
            if (array.key) |key| try pending.append(allocator, key);
        } else if (record.shape.variants) |variants| {
            // A boxed payload is a managed pointer, which no flat boundary carries
            // (RECURSIVE-VALUES-2).
            for (variants.cases) |case| if (case.payload) |payload| {
                if (case.boxed) return error.NotDataType;
                try pending.append(allocator, payload);
            };
        } else for (record.fields) |field| {
            if (field.boxed) return error.NotDataType;
            try pending.append(allocator, field.ty);
        }
    }
}
