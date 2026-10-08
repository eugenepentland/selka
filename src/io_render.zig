//! Which checked types `print` can render, and the printed spelling of a record name.
const std = @import("std");
const typed = @import("typed.zig");

/// Whether a checked type has a Python rendering, used to reject `print` arguments.
pub fn printable(ty: typed.Type, records: []const typed.Record) bool {
    if (ty == .unit or ty == .bool or ty.isInteger()) return true;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    if (record.isCell() or record.collection.contains_cell) return false;
    if (record.contract.callback != null or record.shape.resource != null) return false;
    if (record.contract.move_only) return false;
    return true;
}

/// Strip a module qualification so printed records read like their source spelling.
pub fn shortName(name: []const u8) []const u8 {
    return if (std.mem.lastIndexOf(u8, name, "::")) |at| name[at + 2 ..] else name;
}
