//! Raw readonly bodies select managed alternates without requiring a journal.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const model = @import("rc_model.zig");
const frame = @import("qbe_rc_frame.zig");
const runtime = @import("runtime_mode.zig");
/// Failures shared by the native emitter; an inconsistent route never falls back.
pub const Error = frame.Error;

/// Select raw emission before any later ownership refinement can be planned.
pub fn activate(comptime E: type, self: *E) void {
    if (!runtime.enabled()) return;
    const state = self.cow.?.rc orelse return;
    if (state.plan.readonly == null) return;
    state.readonly = true;
    state.active = false;
}

/// Preflight already refused nonquiet plans; later refinements are inactive.
/// A mismatch is an emitter invariant failure, never a second optional choice.
pub fn verify(comptime E: type, self: *E) Error!void {
    if (!runtime.enabled()) return;
    const cow = self.cow.?;
    const state = cow.rc orelse return;
    if (!state.readonly) return;
    if (!@import("rc_readonly_plan.zig").quiet(cow.plan)) return error.InternalError;
    if (state.plan.field_transfers.len != 0 or state.plan.plain_writes.len != 0 or state.plan.dictionary_tails.len != 0) return error.InternalError;
    const none = @import("cow_plan.zig").none;
    for (cow.captures) |capture| {
        if (capture.begin != none or capture.active != none) return error.InternalError;
    }
}

/// A managed raw call must have the exact public certificate saved at this PC.
/// Access state directly: readonly bodies deliberately make frame.get return null.
pub fn route(comptime E: type, self: *E, callee: bytecode.Function) Error!?model.BorrowCertificate {
    const state = self.cow.?.rc orelse return error.InternalError;
    if (!state.readonly) return error.InternalError;
    const shape = state.catalog.get(callee.signature.return_type) catch return error.InternalError;
    if (shape.unique_drop) return error.InternalError;
    if (!shape.counted) return null;
    const proof = state.plan.readonly orelse return error.InternalError;
    const count = callee.signature.parameter_count;
    const stack = self.states[self.pc] orelse return error.InternalError;
    if (count > stack.len or count > callee.scope.locals.len) return error.InternalError;
    for (stack[stack.len - count ..], callee.scope.locals[0..count]) |argument, parameter|
        if (argument != parameter.ty) return error.InternalError;
    for (proof.calls) |call| {
        if (call.pc != self.pc) continue;
        if (call.target != callee.id or call.certificate.parameter >= count) return error.InternalError;
        const layout = state.catalog.native.layout(callee.signature.return_type) catch return error.InternalError;
        if (!std.mem.eql(u8, &layout.hash, &call.certificate.shape_identity)) return error.InternalError;
        return call.certificate;
    }
    return error.InternalError;
}
