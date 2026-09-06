//! Source pool operations return snapshots and inert IDs, never registry pointers.
/// Pool builtin operations and their signature/ownership properties.
pub const Kind = enum {
    length,
    capacity,
    insert,
    read,
    replace,
    remove,
    clear,
    /// Return the required source argument count for this pool builtin.
    pub fn arity(self: Kind) usize {
        return switch (self) {
            .length, .capacity, .clear => 0,
            .insert, .read, .remove => 1,
            .replace => 2,
        };
    }
    /// Indicate whether this operation changes pool contents.
    pub fn mutates(self: Kind) bool {
        return self != .length and self != .capacity and self != .read;
    }
    /// Indicate whether this operation requires a typed result boundary.
    pub fn fallible(self: Kind) bool {
        return self == .insert or self == .read or self == .replace or self == .remove;
    }
    /// Resolve the operation's output type from the pool element and handle schema.
    pub fn output(self: Kind, pool: anytype) @TypeOf(pool.element) {
        return switch (self) {
            .length, .capacity => .u64,
            .insert => pool.handle,
            .read => pool.element,
            .replace, .remove, .clear => .bool,
        };
    }
};
