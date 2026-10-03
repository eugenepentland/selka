//! Stack-only constructor eligibility for bytecode inlining.
const typed = @import("typed.zig");

/// Whether a value has no managed edge, recursive box, callable or resource.
/// Decline recursive/deep schemas rather than assuming that a value record's
/// outer inline representation makes its fields allocation-free.
pub fn plain(records: []const typed.Record, ty: typed.Type) bool {
    return visit(records, ty, 0);
}

fn visit(records: []const typed.Record, ty: typed.Type, depth: usize) bool {
    if (depth > 16) return false;
    if (!ty.isAggregate()) return ty.isInteger() or ty == .bool or ty == .unit;
    if (ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    if (record.managed or record.shape.hasRuntimeIdentity() or record.contract.callback != null or record.contract.move_only) return false;
    if (record.shape.array) |array| return visit(records, array.element, depth + 1);
    if (record.shape.domain) |backing| return visit(records, backing, depth + 1);
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| {
            if (case.boxed) return false;
            if (case.payload) |payload| if (!visit(records, payload, depth + 1)) return false;
        }
    }
    for (record.fields) |field| {
        if (field.boxed or !visit(records, field.ty, depth + 1)) return false;
    }
    return true;
}
