//! Physical held-pointer journal roles shared by live views and value publication.
const typed = @import("typed.zig");
const semantics = @import("value_semantics.zig");
const frame = @import("qbe_rc_frame.zig");
const Error = frame.Error;
/// Exclusive terminal-pointer journal role, matching MYL_QBE_RC_HOLD_POINTER.
pub const flag: u32 = 8;

/// Live views and managed iteration sources can create terminal H collection slots.
pub fn mayHold(comptime E: type, self: *E, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    if (!record.isCollection()) return false;
    for (self.function.scope.locals, 0..) |local, index| {
        if (local.ty == ty and @import("cow_plan.zig").iterationOwner(self.function, index)) return true;
    }
    if (record.collection.kind != .dictionary) return false;
    for (self.states) |state| if (state) |stack| for (stack) |value| {
        if (semantics.isLiveView(self.program.records, value)) return true;
    };
    return false;
}

/// Read one journal token's actual role, independent of its logical dict type.
pub fn held(comptime E: type, self: *E, index: usize) Error!usize {
    const flag_address = self.temp();
    const role = self.temp();
    const matches = self.temp();
    const guard = self.temp();
    const result = self.temp();
    try self.print(" %v{d} =l add %rcentries, {d}\n %v{d} =w loaduw %v{d}\n %v{d} =w ceqw %v{d}, {d}\n", .{ flag_address, index * frame.entry_bytes + 24, role, flag_address, matches, role, flag });
    try self.print(" %v{d} =w loaduw %v{d}\n %v{d} =w and %v{d}, %v{d}\n", .{ guard, try frame.guard(E, self, index), result, matches, guard });
    return result;
}
