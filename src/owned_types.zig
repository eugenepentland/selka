//! The types whose values own storage the ownership pass tracks, in the front end so the check (`core/single_owner.zig`) and the
//! needless-copy pass read one definition. A written `own` on a value of any other type is `E_OWN_MARKER`: "a scalar has no
//! managed storage to transfer", which is why `W_NEEDLESS_COPY` writes such a move bare.
const std = @import("std");
const typed = @import("typed.zig");

/// Resolve owned leaves to a fixed point: one flag for each record, true when a value of that record owns storage (it is
/// managed, a collection box or a resource, or holds a boxed field, a field, an array element or a variant payload that does).
pub fn table(a: std.mem.Allocator, program: typed.Program) error{OutOfMemory}![]bool {
    const linear = try a.alloc(bool, program.records.len);
    @memset(linear, false);
    var changed = true;
    while (changed) {
        changed = false;
        for (program.records, 0..) |record, index| {
            if (linear[index]) continue;
            const owns = if (record.managed) true else owns: {
                if ((record.collection.box or record.shape.resource != null)) break :owns true;
                for (record.fields) |field| if ((field.boxed) or isOwned(linear, field.ty)) break :owns true;
                if (record.shape.array) |array| if (isOwned(linear, array.element)) break :owns true;
                if (record.shape.variants) |variants| for (variants.cases) |case| {
                    if (case.payload) |payload| if ((case.boxed) or isOwned(linear, payload)) break :owns true;
                };
                break :owns false;
            };
            if (owns) {
                linear[index] = true;
                changed = true;
            }
        }
    }
    return linear;
}

/// Whether `ty` is a record `linear` (`table`) marks as owning storage.
pub fn isLinear(linear: []const bool, ty: typed.Type) bool {
    return ty.isAggregate() and ty.recordIndex() < linear.len and linear[ty.recordIndex()];
}

/// Whether a value of type `ty` owns storage the ownership pass tracks: a file, or a type `linear` (`table`) marks.
pub fn isOwned(linear: []const bool, ty: typed.Type) bool {
    if (ty.isFile()) return true;
    return isLinear(linear, ty);
}
