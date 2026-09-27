//! Immediate scalar fields need no ownership of their unused managed siblings.
const bytecode = @import("bytecode.zig");
const shapes = @import("rc_shape.zig");
const Op = @FieldType(bytecode.Instruction, "op");
const maximum = 8;
/// The shape catalog can allocate during compile-time proof construction.
pub const Error = error{ InternalError, OutOfMemory };

/// Certify an exact checked-list-read followed by only inline field reads.
/// No aggregate escapes, and no branch, scope, cleanup or call can intervene.
pub fn end(comptime E: type, self: *E, pc: usize, catalog: *shapes.Catalog) Error!?usize {
    const code = self.function.scope.instructions;
    if (code[pc].op != .buffer_operation) return null;
    const operation = code[pc].op.buffer_operation;
    if (operation.kind != .read) return null;
    const owner = self.function.scope.locals[@backingInt(operation.owner)].ty;
    if (self.program.records[owner.recordIndex()].collection.kind != .list) return null;
    var ty = operation.output;
    for (1..maximum + 1) |distance| {
        const at = pc + distance;
        if (at >= code.len or self.states[at] == null or self.isBranchTarget(at)) return null;
        if (code[at].op != .get_field or !ty.isAggregate()) return null;
        const record = self.program.records[ty.recordIndex()];
        if (record.managed or @import("value_semantics.zig").containsLiveView(self.program.records, ty)) return null;
        if ((catalog.get(ty) catch |err| return translate(err)).unique_drop) return null;
        const layout = catalog.native.layout(ty) catch |err| return translate(err);
        const index = code[at].op.get_field;
        if (layout.kind != .record or index >= layout.fields.len) return null;
        ty = layout.fields[index].ty;
        const field = catalog.get(ty) catch |err| return translate(err);
        if (field.counted or field.unique_drop) continue;
        if (self.isScalar(ty)) return at;
    }
    return null;
}

/// Only a finalized no-token receiver can lend an interior pointer this way.
/// Its stable named root survives until the adjacent scalar read is complete.
pub fn borrowed(comptime E: type, self: *E, op: Op) Error!bool {
    if (op != .buffer_operation and op != .get_field) return false;
    const state = self.cow.?.rc orelse return false;
    const code = self.function.scope.instructions;
    var start = self.pc;
    var remaining: usize = maximum;
    while (code[start].op == .get_field) {
        if (start == 0 or remaining == 0) return false;
        remaining -= 1;
        start -= 1;
    }
    const final = try end(E, self, start, &state.catalog) orelse return false;
    if (self.pc >= final) return false;
    const owner = @backingInt(code[start].op.buffer_operation.owner);
    const role = state.plan.locals.entry[owner].ownership;
    return role == .borrowed and role.borrowed == .storage;
}

fn translate(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}
