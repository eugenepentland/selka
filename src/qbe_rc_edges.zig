//! Guarded releases of finished collection temporaries on empty-stack edges.
const bytecode = @import("bytecode.zig");
const frame = @import("qbe_rc_frame.zig");
/// Failures shared with the concrete native emitter.
pub const Error = frame.Error;

/// Discharge the conservative straight-line part of the finalized CFG plan.
/// Nonparameter address borrowing is disabled in RC; captured receiver paths
/// retain their own holds, and final COW liveness includes implicit parent uses.
pub fn after(comptime E: type, self: *E, op: @FieldType(bytecode.Instruction, "op")) Error!void {
    const state = frame.get(E, self) orelse return;
    if (op != .store_local or @import("qbe_rc_borrow.zig").active(E, self)) return;
    for (state.locals.edges) |edge| {
        if (edge.from != self.pc or edge.to != self.pc + 1) continue;
        for (edge.releases) |release| {
            const index = @backingInt(release.storage);
            if (index < self.function.signature.parameter_count) continue;
            const local = self.function.scope.locals[index];
            if (!local.usage.temporary or self.byReference(index) or self.callerStorage(index)) continue;
            const shape = state.catalog.get(local.ty) catch return error.InternalError;
            if (!shape.counted or shape.unique_drop) continue;
            if (!self.isScalar(local.ty) or !local.ty.isAggregate()) continue;
            // Recursive boxes and inline aggregate loans need their physical
            // anchors represented before general edge cleanup is enabled.
            const record = self.program.records[local.ty.recordIndex()];
            if (!record.isCollection() or record.collection.box) continue;
            try frame.drop(E, self, index);
        }
    }
}
