//! Shared syntax/IR operation shapes; allocation effects refer to guest backing storage.
/// Source buffer builtin operations and their argument/mutation properties.
pub const Kind = enum {
    length,
    capacity,
    read,
    write,
    append,
    resize,
    reserve,
    take,
    truncate,
    /// Return the required source argument count for this buffer builtin.
    pub fn arity(self: Kind) usize {
        return switch (self) {
            .length, .capacity => 0,
            .read, .append, .take, .truncate => 1,
            .write, .resize, .reserve => 2,
        };
    }
    /// Identify operations that may allocate new guest backing storage.
    pub fn allocates(self: Kind) bool {
        return self == .reserve;
    }
    /// Identify operations that modify buffer contents or initialized length.
    pub fn mutates(self: Kind) bool {
        return switch (self) {
            .length, .capacity, .read => false,
            else => true,
        };
    }
};
