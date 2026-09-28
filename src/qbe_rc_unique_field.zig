//! RC-UNIQUE-FIELD-TAKE-1: reading a unique field (a resource handle, or a
//! value that holds one) out of a record operand the read consumes moves the
//! field instead of copying it. A copy of a unique handle would leave two
//! owners, and the record's cleanup, which runs before the result publishes,
//! would close the handle the result still names.
const typed = @import("typed.zig");
const frame = @import("qbe_rc_frame.zig");
const values = @import("qbe_rc_values.zig");
const state_model = @import("qbe_rc_state.zig");

/// Errors shared with the native emitter.
pub const Error = values.Error;

/// Lower the ownership half of a completed `get_field` whose result holds a
/// unique drop: take the field out of the consumed record's operand storage,
/// clearing it there, drop what remains of the record, then publish the
/// field. Returns false, emitting nothing, for every other field read.
pub fn take(comptime E: type, self: *E, field: usize, stack: []const typed.Type) Error!bool {
    const state = frame.get(E, self) orelse return false;
    if (stack.len == 0) return error.InternalError;
    const base = stack.len - 1;
    const next = self.states[self.pc + 1] orelse return error.InternalError;
    if (next.len != stack.len) return error.InternalError;
    const result = next[base];
    const shape = state.catalog.get(result) catch return error.InternalError;
    if (!shape.unique_drop or !try state_model.owns(state, stack[base])) return false;
    const record = try values.operand(E, self, base);
    const inner = try self.address(record, (try self.field(stack[base], field)).offset);
    try values.taken(E, self, result, inner);
    try values.drop(E, self, base);
    try values.publish(E, self, result, base);
    return true;
}
