//! Relocate a certified closed field owner between the field and its target.
const frame = @import("qbe_rc_frame.zig");
const values = @import("qbe_rc_values.zig");
const Certificate = @import("rc_field_transfer.zig").Certificate;
/// Native emission failures shared with typed publication.
pub const Error = values.Error;

/// The input is a raw inline record read with no operand obligation.
///
/// When the target has its own journal guard the move goes straight into its
/// slot: an initialized previous value is released, the field's bytes are
/// relocated and cleared, and the target's guard is published; the ordinary
/// copy and target store that follow emit nothing (`local`). Otherwise the
/// token is published as the owned operand the ordinary copy then takes.
/// Neither path can allocate, call guest code or trap after the release.
pub fn project(comptime E: type, self: *E) Error!bool {
    const state = frame.get(E, self) orelse return false;
    for (state.plan.records.transfers) |proof| {
        if (proof.projection != self.pc) continue;
        const member = try self.field(self.function.scope.locals[proof.source.local].ty, proof.source.field);
        if (try direct(E, self, proof)) {
            try frame.drop(E, self, proof.target);
            const field = try self.address(try home(E, self, proof.source.local), member.offset);
            const slot = try home(E, self, proof.target);
            try marker(E, self, proof);
            try relocate(E, self, field, slot, (try self.layout(member.ty)).size);
            try frame.initialized(E, self, proof.target, true);
            return true;
        }
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
            try marker(E, self, proof);
            try relocate(E, self, field, destination, (try self.layout(member.ty)).size);
            try self.store(0, destination);
        }
        const journal = values.journalIndex(E, self, 0);
        try frame.stableEntry(E, self, journal, member.ty);
        try frame.initialized(E, self, journal, true);
        return true;
    }
    return false;
}

/// Direct transfers own every instruction of their two sequences: the copy
/// and target store after the projection emit nothing, the store-back's
/// temporaries, copy and record update emit nothing, and its final store
/// relocates the target's value into the still-empty field and clears the
/// target's guard. Returns whether the current instruction was lowered.
pub fn local(comptime E: type, self: *E) Error!bool {
    const state = frame.get(E, self) orelse return false;
    for (state.plan.records.transfers) |proof| {
        if (!proof.intercepts(self.pc) or self.pc == proof.projection) continue;
        if (!try direct(E, self, proof)) return false;
        if (self.pc != proof.commit) return true;
        const member = try self.field(self.function.scope.locals[proof.source.local].ty, proof.source.field);
        const field = try self.address(try home(E, self, proof.source.local), member.offset);
        const slot = try home(E, self, proof.target);
        try self.print(" # RC-CLOSED-FIELD-TRANSFER-2 store-back source {d} field {d} target {d}\n", .{ proof.source.local, proof.source.field, proof.target });
        try relocate(E, self, slot, field, (try self.layout(member.ty)).size);
        try frame.initialized(E, self, proof.target, false);
        return true;
    }
    return false;
}

/// Successful ordinary storeback owns the replacement before releasing the dead
/// target. A direct store-back already cleared the target's guard.
pub fn committed(comptime E: type, self: *E) Error!void {
    const state = frame.get(E, self) orelse return;
    for (state.plan.records.transfers) |proof| {
        if (proof.commit == self.pc and !try direct(E, self, proof)) try frame.drop(E, self, proof.target);
    }
}

// A target with its own guard can hold the token in place; its frame entry
// already names its slot and type.
// A certified borrowed body never reaches `project`, so it never skips.
fn direct(comptime E: type, self: *E, proof: Certificate) Error!bool {
    const state = frame.get(E, self) orelse return false;
    if (@import("qbe_rc_borrow.zig").active(E, self)) return false;
    const slot = try state.plan.journal.slot(proof.target);
    return slot != null;
}

// Caller storage is reached through the parameter's address; a frame-owned
// local's slot is its value's own inline storage.
fn home(comptime E: type, self: *E, index: usize) Error!usize {
    if (self.callerStorage(index)) return self.load("l", index);
    const address = self.temp();
    try self.print(" %v{d} =l copy %l{d}\n", .{ address, index });
    return address;
}

fn relocate(comptime E: type, self: *E, from: usize, to: usize, size: u64) Error!void {
    try self.print(values.blit_value, .{ from, to, size });
    try self.print(" call $memset(l %v{d}, w 0, l {d})\n", .{ from, size });
}

fn marker(comptime E: type, self: *E, proof: Certificate) Error!void {
    try self.print(" # RC-CLOSED-FIELD-TRANSFER-1 source {d} field {d} target {d} commit {d}\n", .{ proof.source.local, proof.source.field, proof.target, proof.commit });
}
