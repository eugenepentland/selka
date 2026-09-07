//! Validate finite nested storage at the bytecode boundary without trusting ownership flags.
const std = @import("std");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
/// Recompute buffer-containing graphs so forged copy/storable flags cannot admit resource owners.
pub fn validate(allocator: std.mem.Allocator, records: []const typed.Record) error{ OutOfMemory, InternalError }!void {
    var has_buffers = false;
    for (records) |record| has_buffers = has_buffers or record.shape.buffer != null;
    if (!has_buffers) return;
    const derived = try allocator.dupe(typed.Record, records);
    defer allocator.free(derived);
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    defer sink.deinit();
    @import("record_layouts.zig").validate(allocator, derived, &sink) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InternalError,
    };
    for (derived, records) |computed, supplied| {
        if (computed.contract.move_only != supplied.contract.move_only) return error.InternalError;
        if (computed.contract.requires_handling != supplied.contract.requires_handling) return error.InternalError;
        if (computed.contract.storable != supplied.contract.storable) return error.InternalError;
    }
}
