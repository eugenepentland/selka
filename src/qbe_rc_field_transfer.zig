//! Relocate a certified closed field owner into the ordinary operand journal.
const frame = @import("qbe_rc_frame.zig");
const values = @import("qbe_rc_values.zig");
/// Native emission failures shared with typed publication.
pub const Error = values.Error;

/// The input is a raw inline record read with no operand obligation. Moving
/// the field's bits into the operand's stable storage, clearing the field and
/// publishing that one token cannot call, allocate or trap.
pub fn project(comptime E: type, self: *E) Error!bool {
    const state = frame.get(E, self) orelse return false;
    for (state.plan.records.transfers) |proof| {
        if (proof.projection != self.pc) continue;
        const member = try self.field(self.function.scope.locals[proof.source.local].ty, proof.source.field);
        const root = try home(E, self, proof.source.local);
        const field = try self.address(root, member.offset);
        if (self.isScalar(member.ty)) {
            // The operand word already holds the field's one pointer.
            const value = try self.load("s", 0);
            const destination = try values.operand(E, self, 0);
            try marker(E, self, proof);
            try self.print(" storel %v{d}, %v{d}\n storel 0, %v{d}\n", .{ value, destination, field });
        } else {
            // The operand names the field in place (or a raw snapshot of its
            // owner); relocate the inline value and name the stable copy.
            const destination = try values.operand(E, self, 0);
            const size = (try self.layout(member.ty)).size;
            try marker(E, self, proof);
            try self.print(values.blit_value, .{ field, destination, size });
            try self.print(" call $memset(l %v{d}, w 0, l {d})\n", .{ field, size });
            try self.store(0, destination);
        }
        const journal = values.journalIndex(E, self, 0);
        try frame.stableEntry(E, self, journal, member.ty);
        try frame.initialized(E, self, journal, true);
        return true;
    }
    return false;
}

// Caller storage is reached through the parameter's address; a frame-owned
// local's slot is its value's own inline storage.
fn home(comptime E: type, self: *E, local: usize) Error!usize {
    if (self.callerStorage(local)) return self.load("l", local);
    const address = self.temp();
    try self.print(" %v{d} =l copy %l{d}\n", .{ address, local });
    return address;
}

fn marker(comptime E: type, self: *E, proof: anytype) Error!void {
    try self.print(" # RC-CLOSED-FIELD-TRANSFER-1 source {d} field {d} target {d} commit {d}\n", .{ proof.source.local, proof.source.field, proof.target, proof.commit });
}

/// Successful storeback owns the replacement before releasing the dead target.
/// Failed preparation never reaches this point and leaves its existing guard live.
pub fn committed(comptime E: type, self: *E) Error!void {
    const state = frame.get(E, self) orelse return;
    for (state.plan.records.transfers) |proof| {
        if (proof.commit == self.pc) try frame.drop(E, self, proof.target);
    }
}
