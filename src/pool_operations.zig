//! Source pool operations return snapshots and inert IDs, never registry pointers.
pub const Kind = enum {
    length,
    capacity,
    insert,
    read,
    replace,
    remove,
    clear,
    pub fn arity(self: Kind) usize {
        return switch (self) {
            .length, .capacity, .clear => 0,
            .insert, .read, .remove => 1,
            .replace => 2,
        };
    }
    pub fn mutates(self: Kind) bool {
        return self != .length and self != .capacity and self != .read;
    }
    pub fn fallible(self: Kind) bool {
        return self == .insert or self == .read or self == .replace or self == .remove;
    }
    pub fn output(self: Kind, pool: @import("typed.zig").Pool) @import("typed.zig").Type {
        return switch (self) {
            .length, .capacity => .u64,
            .insert => pool.handle,
            .read => pool.element,
            .replace, .remove, .clear => .bool,
        };
    }
};
