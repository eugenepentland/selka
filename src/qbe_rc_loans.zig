//! Private physical loans preserve payload identity until a semantic publication.
const typed = @import("typed.zig");
const frame = @import("qbe_rc_frame.zig");
const slots = @import("qbe_rc_slots.zig");
/// Exclusive private lifetime role, matching MYL_QBE_RC_LOAN.
pub const flag: u32 = @import("qbe_rc_glue.zig").loan_role;
/// Native emitter failures shared with typed slot operations.
pub const Error = slots.Error;

/// Raw unique resources never participate in a copyable physical loan.
pub fn eligible(comptime E: type, self: *E, ty: typed.Type) Error!bool {
    const state = frame.get(E, self) orelse return false;
    const shape = state.catalog.get(ty) catch return error.InternalError;
    return shape.counted and !shape.unique_drop;
}

/// Assign a role only after the corresponding value has been initialized.
pub fn role(comptime E: type, self: *E, index: usize, value: u32) Error!void {
    try self.print(" storew {d}, %v{d}\n", .{ value, try frame.entryField(E, self, index, 24) });
}

/// Relocate the source's cleanup role along with its already prepared bytes.
pub fn copyRole(comptime E: type, self: *E, destination: usize, source: usize) Error!void {
    const value = self.temp();
    try self.print(" %v{d} =w loaduw %v{d}\n storew %v{d}, %v{d}\n", .{
        value, try frame.entryField(E, self, source, 24), value, try frame.entryField(E, self, destination, 24),
    });
}

/// Whether a guarded token is an ordinary owner rather than an H or loan token.
pub fn owner(comptime E: type, self: *E, index: usize) Error!usize {
    if (frame.emptyLocal(E, self, index)) {
        const empty = self.temp();
        try self.print(" %v{d} =w copy 0\n", .{empty});
        return empty;
    }
    const live = self.temp();
    const flags = self.temp();
    const ordinary = self.temp();
    const result = self.temp();
    try self.print(" %v{d} =w loaduw %v{d}\n %v{d} =w loaduw %v{d}\n", .{
        live, try frame.guard(E, self, index), flags, try frame.entryField(E, self, index, 24),
    });
    try self.print(" %v{d} =w and %v{d}, 24\n %v{d} =w ceqw %v{d}, 0\n %v{d} =w and %v{d}, %v{d}\n", .{
        flags, flags, ordinary, flags, result, live, ordinary,
    });
    return result;
}

/// Whether a guarded token is a live private loan, or null when the entry can
/// never hold one.
pub fn lent(comptime E: type, self: *E, index: usize) Error!?usize {
    if (frame.emptyLocal(E, self, index)) return null;
    const live = self.temp();
    const flags = self.temp();
    const loan = self.temp();
    try self.print(" %v{d} =w loaduw %v{d}\n %v{d} =w loaduw %v{d}\n", .{
        live, try frame.guard(E, self, index), flags, try frame.entryField(E, self, index, 24),
    });
    try self.print(" %v{d} =w ceqw %v{d}, {d}\n %v{d} =w and %v{d}, %v{d}\n", .{ loan, flags, flag, loan, loan, live });
    return loan;
}

/// RC-LOAN-RELOCATE-1: move a live private loan's bytes and role into pending
/// storage and clear its source. The hold it carries moves with it, so no
/// count changes, where acquiring a second loan and dropping the first
/// changed the count twice and back.
pub fn relocate(comptime E: type, self: *E, ty: typed.Type, source: usize, index: usize) Error!void {
    const work = self.temp();
    const size = (try self.layout(ty)).size;
    try self.print(" # RC-LOAN-RELOCATE-1\n %v{d} =l copy %rcwork\n blit %v{d}, %v{d}, {d}\n", .{ work, source, work, size });
    if (size == 8) {
        try self.print(" storel 0, %v{d}\n", .{source});
    } else try self.print(" call $memset(l %v{d}, w 0, l {d})\n", .{ source, size });
    try frame.stableEntry(E, self, frame.pending(E, self), ty);
    try role(E, self, frame.pending(E, self), flag);
    try frame.initialized(E, self, frame.pending(E, self), true);
    try frame.initialized(E, self, index, false);
}

/// Copy stable bytes into pending storage and acquire only lifetime holds.
pub fn prepare(comptime E: type, self: *E, ty: typed.Type, source: usize) Error!void {
    const glue = @import("qbe_rc_glue.zig");
    if (try glue.routed(E, self, ty)) {
        const work = self.temp();
        try self.print(" %v{d} =l copy %rcwork\n", .{work});
        try glue.loan(E, self, .{ .ty = ty, .destination = work, .source = source });
    } else {
        const result = self.temp();
        try self.print(" %v{d} =w call $myl_rc_native_loan(l %heap, l extern ${s}, l %rcwork, l %v{d})\n", .{
            result, try self.descriptor(ty), source,
        });
        try slots.requireSuccess(E, self, result);
    }
    try frame.stableEntry(E, self, frame.pending(E, self), ty);
    try role(E, self, frame.pending(E, self), flag);
    try frame.initialized(E, self, frame.pending(E, self), true);
}

/// Test the live role of a mutable path's private inline containing local.
/// A null answer means its representation can never be a private loan.
pub fn local(comptime E: type, self: *E, index: usize) Error!?usize {
    if (frame.emptyLocal(E, self, index)) return null;
    if (!self.function.scope.locals[index].usage.temporary) return null;
    if (self.byReference(index) or self.callerStorage(index)) return null;
    if (!try eligible(E, self, self.function.scope.locals[index].ty)) return null;
    const flags = self.temp();
    const live = self.temp();
    const loan = self.temp();
    try self.print(" %v{d} =w loaduw %v{d}\n %v{d} =w ceqw %v{d}, {d}\n", .{
        flags, try frame.entryField(E, self, index, 24), loan, flags, flag,
    });
    try self.print(" %v{d} =w loaduw %v{d}\n %v{d} =w and %v{d}, %v{d}\n", .{
        live, try frame.guard(E, self, index), loan, loan, live,
    });
    return loan;
}
