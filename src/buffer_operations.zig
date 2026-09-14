//! Shared syntax/IR operation shapes; allocation effects refer to guest backing storage.
/// Source buffer builtin operations and their argument/mutation properties.
pub const Kind = enum {
    length,
    iteration_check,
    key_at,
    slice,
    /// `values[start:stop:step]`; the endpoints carry omission sentinels.
    slice_step,
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
    encode,
    decode,
    to_list,
    hex,
    from_hex,
    starts_with,
    ends_with,
    find,
    strip,
    lstrip,
    rstrip,
    upper,
    lower,
    splitlines,
    is_digit,
    is_alpha,
    is_space,
    replace,
    count,
    zfill,
    parse_int,
    parse_float,
    /// Python-shaped everyday collection vocabulary. `pop` is the no-argument
    /// list form; `pop_at`, `pop_key` and `pop_default` are its arity variants.
    extend,
    insert,
    pop,
    pop_at,
    remove,
    index_of,
    reverse,
    sort,
    copy,
    clear,
    items,
    update,
    setdefault,
    pop_key,
    pop_default,
    /// Return the required source argument count for this buffer builtin.
    pub fn arity(self: Kind) usize {
        return switch (self) {
            .length, .capacity, .keys, .values, .encode, .decode, .to_list, .hex, .from_hex => 0,
            .strip, .lstrip, .rstrip, .upper, .lower, .splitlines => 0,
            .is_digit, .is_alpha, .is_space, .parse_int, .parse_float => 0,
            .pop, .reverse, .sort, .copy, .clear, .items => 0,
            .count, .zfill => 1,
            .extend, .pop_at, .remove, .index_of, .pop_key, .update => 1,
            .replace, .insert, .setdefault, .pop_default => 2,
            .iteration_check, .key_at, .read, .append, .take, .truncate, .contains, .split, .join, .starts_with, .ends_with, .find => 1,
            .write, .resize, .reserve, .get, .slice => 2,
            .slice_step => 3,
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
            .encode, .decode, .to_list, .hex, .from_hex, .starts_with, .ends_with, .find => false,
            .strip, .lstrip, .rstrip, .upper, .lower, .splitlines, .replace, .count, .zfill => false,
            .is_digit, .is_alpha, .is_space, .parse_int, .parse_float => false,
            .copy, .items, .index_of => false,
            else => true,
        };
    }
};

/// Resolve conventional collection method names independently of receiver shape.
pub fn method(name: []const u8) ?Kind {
    const std = @import("std");
    if (std.mem.eql(u8, name, "append")) return .append;
    // `push` is removed on purpose; callers turn it into a migration diagnostic.
    inline for (.{ "extend", "insert", "pop", "remove", "reverse", "sort", "copy", "clear", "items", "update", "setdefault" }) |spelling| {
        if (std.mem.eql(u8, name, spelling)) return @field(Kind, spelling);
    }
    if (std.mem.eql(u8, name, "index")) return .index_of;
    if (std.mem.eql(u8, name, "startswith")) return .starts_with;
    if (std.mem.eql(u8, name, "endswith")) return .ends_with;
    if (std.mem.eql(u8, name, "isdigit")) return .is_digit;
    if (std.mem.eql(u8, name, "isalpha")) return .is_alpha;
    if (std.mem.eql(u8, name, "isspace")) return .is_space;
    inline for (.{ "strip", "lstrip", "rstrip", "upper", "lower", "splitlines", "replace", "count", "zfill" }) |spelling| {
        if (std.mem.eql(u8, name, spelling)) return @field(Kind, spelling);
    }
    inline for (.{ "get", "keys", "values", "split", "join", "encode", "decode", "to_list", "hex", "find" }) |spelling| {
        if (std.mem.eql(u8, name, spelling)) return @field(Kind, spelling);
    }
    return null;
}
/// Whether a method is part of the everyday vocabulary whose receiver-dependent
/// arity and element rules live in the checker rather than the eager desugaring.
pub fn vocabulary(kind: Kind) bool {
    return switch (kind) {
        .extend, .insert, .pop, .remove, .index_of, .reverse, .sort, .copy, .clear => true,
        .items, .update, .setdefault, .pop_key, .pop_default => true,
        else => false,
    };
}
/// Whether a managed operation can allocate, including new dictionary entries.
pub fn managedAllocation(kind: Kind, dictionary: bool) bool {
    return switch (kind) {
        .append, .split, .join, .keys, .values, .slice, .slice_step => true,
        .extend, .insert, .items, .copy, .update, .setdefault => true,
        .encode, .decode, .to_list, .hex, .from_hex => true,
        .strip, .lstrip, .rstrip, .upper, .lower, .splitlines, .replace, .zfill => true,
        .parse_int, .parse_float => true,
        .write => dictionary,
        else => false,
    };
}
