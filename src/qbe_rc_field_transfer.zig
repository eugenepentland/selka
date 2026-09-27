//! Relocate a certified closed field owner into the ordinary operand journal.
const frame = @import("qbe_rc_frame.zig");
const values = @import("qbe_rc_values.zig");
/// Native emission failures shared with typed publication.
pub const Error = values.Error;

/// The input is a raw inline mut-record read with no operand obligation.
/// Clearing its owning field and publishing the same token cannot call or trap.
pub fn project(comptime E: type, self: *E) Error!bool {
    const state = frame.get(E, self) orelse return false;
    for (state.plan.field_transfers) |proof| {
        if (proof.projection != self.pc) continue;
        const member = try self.field(self.function.scope.locals[proof.source.local].ty, proof.source.field);
        const root = try self.load("l", proof.source.local);
        const field = try self.address(root, member.offset);
        const value = try self.load("s", 0);
        const destination = try values.operand(E, self, 0);
        try self.print(" # RC-CLOSED-FIELD-TRANSFER-1 source {d} field {d} target {d} commit {d}\n", .{ proof.source.local, proof.source.field, proof.target, proof.commit });
        try self.print(" storel %v{d}, %v{d}\n storel 0, %v{d}\n", .{ value, destination, field });
        const journal = values.journalIndex(E, self, 0);
        try frame.stableEntry(E, self, journal, member.ty);
        try frame.initialized(E, self, journal, true);
        return true;
    }
    return false;
}

/// Successful storeback owns the replacement before releasing the dead target.
/// Failed preparation never reaches this point and leaves its existing guard live.
pub fn committed(comptime E: type, self: *E) Error!void {
    const state = frame.get(E, self) orelse return;
    for (state.plan.field_transfers) |proof| {
        if (proof.commit == self.pc) try frame.drop(E, self, proof.target);
    }
}
