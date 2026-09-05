//! Shared syntax/IR operation shapes; allocation effects refer to guest backing storage.
pub const Kind = enum {
    length,
    capacity,
    read,
    write,
    append,
    resize,
    reserve,
    pub fn arity(self: Kind) usize {
        return switch (self) {
            .length, .capacity => 0,
            .read, .append => 1,
            .write, .resize, .reserve => 2,
        };
    }
    pub fn mutates(self: Kind) bool {
        return switch (self) {
            .length, .capacity, .read => false,
            else => true,
        };
    }
};
