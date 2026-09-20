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
    /// `bytes.find_any(values, start)`: the first octet at or after `start` that
    /// occurs anywhere in the octet set `values`, or -1. Unlike `find`, whose
    /// needle is a sequence, `values` is a set, so an empty one finds nothing,
    /// duplicates cost nothing, and `start` clamps like a search bound rather
    /// than trapping like an index.
    find_any,
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
    /// `bytes.view(start, end)`: the same octets as an owner-retaining range
    /// instead of a copy. Its endpoints clamp like a slice's, the source's
    /// backing storage stays reachable through the view, and every read —
    /// comparison, search, counting, numeric parsing, re-emission — then works
    /// on the range itself with no decoded or copied intermediate value.
    view,
    /// `bytes.scalar_count()`: the Unicode scalar count of the octets, validated
    /// in the same nonallocating pass, as `Result[int, str]` with the decoder's
    /// invalid-UTF-8 reason. Measuring a range never decodes it.
    scalar_count,
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
    /// In-place octet-buffer operations on a `bytes` receiver. A byte string's
    /// header keeps spare capacity beyond its length, so each of these writes the
    /// appended octets straight into that capacity, doubling it when it runs out,
    /// and answers whether it wrote. None builds an intermediate value for the
    /// appended fragment, and every one refuses a frozen literal receiver, whose
    /// storage the whole image shares.
    buffer_reserve,
    buffer_append_byte,
    buffer_append_range,
    buffer_append_utf8,
    buffer_append_int,
    /// `byte_buffer.append_float(value)`: the binary64's canonical spelling,
    /// formatted into the buffer's own capacity, so a buffered float is byte for
    /// byte what `str(value)` would print and no temporary text exists.
    buffer_append_float,
    /// Return the required source argument count for this buffer builtin.
    pub fn arity(self: Kind) usize {
        return switch (self) {
            .length, .capacity, .keys, .values, .encode, .decode, .to_list, .hex, .from_hex => 0,
            .strip, .lstrip, .rstrip, .upper, .lower, .splitlines => 0,
            .is_digit, .is_alpha, .is_space, .parse_int, .parse_float => 0,
            .scalar_count => 0,
            .pop, .reverse, .sort, .copy, .clear, .items => 0,
            .buffer_reserve, .buffer_append_byte, .buffer_append_utf8, .buffer_append_int => 1,
            .buffer_append_float => 1,
            .count, .zfill => 1,
            .extend, .pop_at, .remove, .index_of, .pop_key, .update => 1,
            .buffer_append_range => 3,
            .replace, .insert, .setdefault, .pop_default => 2,
            .iteration_check, .key_at, .read, .append, .take, .truncate, .contains, .split, .join, .starts_with, .ends_with, .find => 1,
            .write, .resize, .reserve, .get, .slice, .find_any, .view => 2,
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
            .encode, .decode, .to_list, .hex, .from_hex, .starts_with, .ends_with, .find, .find_any => false,
            .strip, .lstrip, .rstrip, .upper, .lower, .splitlines, .replace, .count, .zfill => false,
            .is_digit, .is_alpha, .is_space, .parse_int, .parse_float => false,
            .view, .scalar_count => false,
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
    /// An in-place octet-buffer method: a byte-kind buffer operation only the
    /// mutable `byte_buffer` receiver accepts, never an immutable `bytes`.
    buffer: bool = false,
};

/// Accepted method names in spelling order. Each spelling appears once so the
/// resolver and the per-family suggestion lists share one source of truth.
const methods = [_]Method{
    .{ .spelling = "append", .kind = .append, .list = true },
    .{ .spelling = "append_byte", .kind = .buffer_append_byte, .buffer = true },
    .{ .spelling = "append_float", .kind = .buffer_append_float, .buffer = true },
    .{ .spelling = "append_int", .kind = .buffer_append_int, .buffer = true },
    .{ .spelling = "append_range", .kind = .buffer_append_range, .buffer = true },
    .{ .spelling = "append_utf8", .kind = .buffer_append_utf8, .buffer = true },
    .{ .spelling = "clear", .kind = .clear, .list = true, .dictionary = true },
    .{ .spelling = "copy", .kind = .copy, .list = true, .dictionary = true, .bytes = true },
    .{ .spelling = "count", .kind = .count, .string = true },
    .{ .spelling = "decode", .kind = .decode, .bytes = true },
    .{ .spelling = "encode", .kind = .encode, .string = true },
    .{ .spelling = "endswith", .kind = .ends_with, .string = true, .bytes = true },
    .{ .spelling = "extend", .kind = .extend, .list = true },
    .{ .spelling = "find", .kind = .find, .string = true, .bytes = true },
    .{ .spelling = "find_any", .kind = .find_any, .bytes = true },
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
    .{ .spelling = "parse_float", .kind = .parse_float, .string = true, .bytes = true },
    .{ .spelling = "parse_int", .kind = .parse_int, .string = true, .bytes = true },
    .{ .spelling = "pop", .kind = .pop, .list = true, .dictionary = true },
    .{ .spelling = "remove", .kind = .remove, .list = true },
    .{ .spelling = "replace", .kind = .replace, .string = true },
    .{ .spelling = "reserve", .kind = .buffer_reserve, .buffer = true },
    .{ .spelling = "reverse", .kind = .reverse, .list = true },
    .{ .spelling = "rstrip", .kind = .rstrip, .string = true },
    .{ .spelling = "scalar_count", .kind = .scalar_count, .bytes = true },
    .{ .spelling = "setdefault", .kind = .setdefault, .dictionary = true },
    .{ .spelling = "sort", .kind = .sort, .list = true },
    .{ .spelling = "split", .kind = .split, .string = true, .bytes = true },
    .{ .spelling = "splitlines", .kind = .splitlines, .string = true },
    .{ .spelling = "startswith", .kind = .starts_with, .string = true, .bytes = true },
    .{ .spelling = "strip", .kind = .strip, .string = true },
    .{ .spelling = "to_list", .kind = .to_list, .bytes = true },
    .{ .spelling = "update", .kind = .update, .dictionary = true },
    .{ .spelling = "view", .kind = .view, .bytes = true },
    .{ .spelling = "upper", .kind = .upper, .string = true },
    .{ .spelling = "values", .kind = .values, .dictionary = true },
    .{ .spelling = "zfill", .kind = .zfill, .string = true },
};

/// Whether `family` accepts `entry`. The byte family holds both the immutable
/// byte string and the mutable octet buffer, so its suggestion list names the
/// buffer methods too; the checker rejects one on the wrong receiver.
fn accepts(entry: Method, family: ManagedKind) bool {
    return switch (family) {
        .list => entry.list,
        .dictionary => entry.dictionary,
        .string => entry.string,
        .bytes => entry.bytes or entry.buffer,
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
/// Whether a kind is one of the in-place octet-buffer appends, which only a
/// `bytes` receiver accepts and which answer whether they wrote.
pub fn byteBuffer(kind: Kind) bool {
    return switch (kind) {
        .buffer_reserve, .buffer_append_byte, .buffer_append_range => true,
        .buffer_append_utf8, .buffer_append_int, .buffer_append_float => true,
        else => false,
    };
}
/// Whether a managed operation can allocate, including new dictionary entries.
/// Both numeric parses are absent on purpose: the shared grammar reads the
/// scalars or the octets in place, so `noalloc` accepts `int(text)`,
/// `float(text)`, `bytes.parse_int()` and `bytes.parse_float()`, exactly as it
/// accepts a comparison, a search or `bytes.scalar_count()`.
pub fn managedAllocation(kind: Kind, dictionary: bool) bool {
    return switch (kind) {
        .append, .split, .join, .keys, .values, .slice, .slice_step => true,
        .extend, .insert, .items, .copy, .update, .setdefault => true,
        .encode, .decode, .to_list, .hex, .from_hex => true,
        .strip, .lstrip, .rstrip, .upper, .lower, .splitlines, .replace, .zfill => true,
        .view => true,
        .buffer_reserve, .buffer_append_byte, .buffer_append_range => true,
        .buffer_append_utf8, .buffer_append_int, .buffer_append_float => true,
        .write => dictionary,
        else => false,
    };
}
