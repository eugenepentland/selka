//! Private physical loans preserve payload identity until a semantic publication.
const typed = @import("typed.zig");
const frame = @import("qbe_rc_frame.zig");
const slots = @import("qbe_rc_slots.zig");
/// Exclusive private lifetime role, matching MYL_QBE_RC_LOAN.
pub const flag: u32 = 16;
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

/// Copy stable bytes into pending storage and acquire only lifetime holds.
pub fn prepare(comptime E: type, self: *E, ty: typed.Type, source: usize) Error!void {
    const result = self.temp();
    try self.print(" %v{d} =w call $myl_rc_native_loan(l %heap, l extern ${s}, l %rcwork, l %v{d})\n", .{
        result, try self.descriptor(ty), source,
    });
    try slots.requireSuccess(E, self, result);
    try frame.stableEntry(E, self, frame.pending(E, self), ty);
    try role(E, self, frame.pending(E, self), flag);
    try frame.initialized(E, self, frame.pending(E, self), true);
}
