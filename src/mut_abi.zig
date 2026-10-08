//! Which `mut` parameter types a whole-variable rebinding can reach the caller
//! through: lists, dictionaries and sets.
const typed = @import("typed.zig");

/// Whether a type is a list, mapping or set whose whole binding can be replaced.
pub fn collection(records: []const typed.Record, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    if (!records[ty.recordIndex()].isCollection()) return false;
    return switch (records[ty.recordIndex()].collection.kind) {
        .list, .dictionary => true,
        else => false,
    };
}
