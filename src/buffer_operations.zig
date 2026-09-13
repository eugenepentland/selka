//! Shared syntax/IR operation shapes; allocation effects refer to guest backing storage.
/// Source buffer builtin operations and their argument/mutation properties.
pub const Kind = enum {
    length,
    iteration_check,
    key_at,
    slice,
    capacity,
    read,
    write,
    append,
    resize,
    reserve,
    take,
    truncate,
    get,
    contains,
    keys,
    values,
    split,
    join,
    /// Return the required source argument count for this buffer builtin.
    pub fn arity(self: Kind) usize {
        return switch (self) {
            .length, .capacity, .keys, .values => 0,
            .iteration_check, .key_at, .read, .append, .take, .truncate, .contains, .split, .join => 1,
            .write, .resize, .reserve, .get, .slice => 2,
        };
    }
    /// Identify operations that may allocate new guest backing storage.
    pub fn allocates(self: Kind) bool {
        return self == .reserve;
    }
    /// Identify operations that modify buffer contents or initialized length.
    pub fn mutates(self: Kind) bool {
        return switch (self) {
            .length, .capacity, .iteration_check, .key_at, .read, .get, .contains, .keys, .values, .split, .join => false,
            else => true,
        };
    }
};

/// Resolve conventional collection method names independently of receiver shape.
pub fn method(name: []const u8) ?Kind {
    const std = @import("std");
    if (std.mem.eql(u8, name, "push") or std.mem.eql(u8, name, "append")) return .append;
    if (std.mem.eql(u8, name, "len")) return .length;
    inline for (.{ "get", "contains", "keys", "values", "split", "join" }) |spelling| {
        if (std.mem.eql(u8, name, spelling)) return @field(Kind, spelling);
    }
    return null;
}
/// Whether a managed operation can allocate, including new dictionary entries.
pub fn managedAllocation(kind: Kind, dictionary: bool) bool {
    return switch (kind) {
        .append, .split, .join, .keys, .values, .slice => true,
        .write => dictionary,
        else => false,
    };
}
