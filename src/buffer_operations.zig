//! Shared syntax/IR operation shapes; allocation effects refer to guest backing storage.
const std = @import("std");
const ManagedKind = @import("runtime_values.zig").ManagedKind;
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

/// One accepted Python method name: the operation it resolves to and the
/// managed collection families whose checker accepts it.
const Method = struct {
    spelling: []const u8,
    kind: Kind,
    list: bool = false,
    dictionary: bool = false,
    string: bool = false,
    bytes: bool = false,
};

/// Accepted method names in spelling order. Each spelling appears once so the
/// resolver and the per-family suggestion lists share one source of truth.
const methods = [_]Method{
    .{ .spelling = "append", .kind = .append, .list = true },
    .{ .spelling = "clear", .kind = .clear, .list = true, .dictionary = true },
    .{ .spelling = "copy", .kind = .copy, .list = true, .dictionary = true },
    .{ .spelling = "count", .kind = .count, .string = true },
    .{ .spelling = "decode", .kind = .decode, .bytes = true },
    .{ .spelling = "encode", .kind = .encode, .string = true },
    .{ .spelling = "endswith", .kind = .ends_with, .string = true, .bytes = true },
    .{ .spelling = "extend", .kind = .extend, .list = true },
    .{ .spelling = "find", .kind = .find, .string = true, .bytes = true },
    .{ .spelling = "get", .kind = .get, .dictionary = true },
    .{ .spelling = "hex", .kind = .hex, .bytes = true },
    .{ .spelling = "index", .kind = .index_of, .list = true },
    .{ .spelling = "insert", .kind = .insert, .list = true },
    .{ .spelling = "isalpha", .kind = .is_alpha, .string = true },
    .{ .spelling = "isdigit", .kind = .is_digit, .string = true },
    .{ .spelling = "isspace", .kind = .is_space, .string = true },
    .{ .spelling = "items", .kind = .items, .dictionary = true },
    .{ .spelling = "join", .kind = .join, .string = true, .bytes = true },
    .{ .spelling = "keys", .kind = .keys, .dictionary = true },
    .{ .spelling = "lower", .kind = .lower, .string = true },
    .{ .spelling = "lstrip", .kind = .lstrip, .string = true },
    .{ .spelling = "pop", .kind = .pop, .list = true, .dictionary = true },
    .{ .spelling = "remove", .kind = .remove, .list = true },
    .{ .spelling = "replace", .kind = .replace, .string = true },
    .{ .spelling = "reverse", .kind = .reverse, .list = true },
    .{ .spelling = "rstrip", .kind = .rstrip, .string = true },
    .{ .spelling = "setdefault", .kind = .setdefault, .dictionary = true },
    .{ .spelling = "sort", .kind = .sort, .list = true },
    .{ .spelling = "split", .kind = .split, .string = true, .bytes = true },
    .{ .spelling = "splitlines", .kind = .splitlines, .string = true },
    .{ .spelling = "startswith", .kind = .starts_with, .string = true, .bytes = true },
    .{ .spelling = "strip", .kind = .strip, .string = true },
    .{ .spelling = "to_list", .kind = .to_list, .bytes = true },
    .{ .spelling = "update", .kind = .update, .dictionary = true },
    .{ .spelling = "upper", .kind = .upper, .string = true },
    .{ .spelling = "values", .kind = .values, .dictionary = true },
    .{ .spelling = "zfill", .kind = .zfill, .string = true },
};

/// Whether `family` accepts `entry`.
fn accepts(entry: Method, family: ManagedKind) bool {
    return switch (family) {
        .list => entry.list,
        .dictionary => entry.dictionary,
        .string => entry.string,
        .bytes => entry.bytes,
    };
}

/// Resolve conventional collection method names independently of receiver shape.
pub fn method(name: []const u8) ?Kind {
    // `push` is removed on purpose; callers turn it into a migration diagnostic.
    inline for (methods) |entry| {
        if (std.mem.eql(u8, name, entry.spelling)) return entry.kind;
    }
    return null;
}

/// Accepted Python method spellings for `family`, sorted and deduplicated.
pub fn methodSpellings(allocator: std.mem.Allocator, family: ManagedKind) std.mem.Allocator.Error![]const []const u8 {
    var count: usize = 0;
    for (methods) |entry| {
        if (accepts(entry, family)) count += 1;
    }
    const selected = try allocator.alloc([]const u8, count);
    var index: usize = 0;
    for (methods) |entry| {
        if (!accepts(entry, family)) continue;
        selected[index] = entry.spelling;
        index += 1;
    }
    return selected;
}

/// Every managed collection method spelling, sorted, for a receiver whose exact
/// collection family is not statically known.
pub fn unionMethodSpellings(allocator: std.mem.Allocator) std.mem.Allocator.Error![]const []const u8 {
    const selected = try allocator.alloc([]const u8, methods.len);
    for (methods, selected) |entry, *out| out.* = entry.spelling;
    return selected;
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
