//! Canonical retained-template file result authority without validator dependency cycles.
const std = @import("std");
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
/// Only an authenticated Result template may carry a primitive open handle.
pub fn fileResult(catalog: value.Catalog, ty: typed.Type) ?typed.Type {
    const payload = resultPayload(catalog, ty) orelse return null;
    return if (payload.isFile()) payload else null;
}
/// Payload of an authenticated Result template with canonical text failure.
pub fn resultPayload(catalog: value.Catalog, ty: typed.Type) ?typed.Type {
    if (catalog.templates.result == null or !ty.isAggregate() or ty.recordIndex() >= catalog.records.len) return null;
    const record = catalog.records[ty.recordIndex()];
    if (!std.mem.startsWith(u8, record.name, "Result<") and record.name.len != 0) return null;
    const shape = typed.resultShape(ty, catalog.records) orelse return null;
    const string = catalog.string orelse return null;
    if (shape.error_type != string.id) return null;
    if (!record.contract.requires_handling) return null;
    return shape.ok_type;
}
