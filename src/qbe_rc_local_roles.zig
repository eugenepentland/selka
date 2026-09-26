//! Canonicalize private local loans before an ABI that accepts only O or borrow.
const frame = @import("qbe_rc_frame.zig");
const values = @import("qbe_rc_values.zig");
const loans = @import("qbe_rc_loans.zig");
/// Native emitter failures shared with ownership publication.
pub const Error = values.Error;

/// Convert only an initialized LOAN slot, retaining its exact payload identity.
/// Ordinary owners and unguarded caller borrows keep their existing convention.
pub fn owning(comptime E: type, self: *E, index: usize) Error!void {
    if (!self.function.scope.locals[index].usage.temporary) return;
    const ty = self.function.scope.locals[index].ty;
    if (!try loans.eligible(E, self, ty)) return;
    const flags = self.temp();
    const matches = self.temp();
    const live = self.temp();
    const condition = self.temp();
    const label = self.temp();
    try self.print(" %v{d} =w loaduw %v{d}\n %v{d} =w ceqw %v{d}, {d}\n", .{
        flags, try frame.entryField(E, self, index, 24), matches, flags, loans.flag,
    });
    try self.print(" %v{d} =w loaduw %v{d}\n %v{d} =w and %v{d}, %v{d}\n", .{
        live, try frame.guard(E, self, index), condition, live, matches,
    });
    try self.print(" jnz %v{d}, @rcownlocal{d}, @rcownedlocal{d}\n@rcownlocal{d}\n", .{ condition, label, label, label });
    const address = self.temp();
    try self.print(" %v{d} =l copy %l{d}\n", .{ address, index });
    try values.copied(E, self, ty, address);
    try frame.drop(E, self, index);
    const work = try values.workAddress(E, self);
    try self.print(values.blit_value, .{ work, address, (try self.layout(ty)).size });
    try frame.entry(E, self, index, ty, address);
    try frame.initialized(E, self, index, true);
    try frame.initialized(E, self, frame.pending(E, self), false);
    try self.print("@rcownedlocal{d}\n", .{label});
}
