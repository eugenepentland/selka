//! Shared syntax/IR operation shapes; allocation effects refer to guest backing storage.
const std = @import("std");
const ManagedKind = @import("runtime_values.zig").ManagedKind;
/// Source buffer builtin operations and their argument/mutation properties.
pub const Kind = enum {
    length,
    iteration_check,
    key_at,
    /// Internal insertion-order dictionary value read used by live views.
    value_at,
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
    /// Allocation-free numeric parsing over one clamped byte range.
    parse_int_range,
    parse_float_range,
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
    /// Allocation-free UTF-8 validation and scalar counting over one clamped
    /// byte range, with the same checked result as `scalar_count()`.
    scalar_count_range,
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
    /// Internal: the in-place keyed sort `values.sort(key=..., reverse=...)`,
    /// `sorted(values, key=...)` and `sort.sort_by_key` lower to after the
    /// guest has computed every key once, in input order, into a key list.
    /// Its three arguments are the list whose elements are sorted — the
    /// receiver itself for an in-place sort, or the original list whose
    /// sorted copy the empty receiver gathers — that key list and the
    /// `reverse` flag; no source spelling names it.
    sort_keyed,
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
    /// The no-argument form of the `split` spelling: Python's whitespace split,
    /// which breaks the receiver on runs of ASCII whitespace and drops every
    /// empty piece, returning `list[str]` for a `str` receiver and `list[bytes]`
    /// for a `bytes` one. It is a separate kind from `split` because the two
    /// forms take different argument counts, and the arity table answers one
    /// count per kind.
    split_whitespace,
    /// `ord(text)`: the one Unicode scalar value of a text argument, which must
    /// hold exactly one scalar. The prelude builtin has no receiver spelling, so
    /// the operation takes the argument as its owner and answers an `int`; the
    /// length check is the emitter's located trap.
    text_ord,
    /// `chr(code)`: one-scalar text for a Unicode scalar value, trapping on a
    /// code point outside `0..0x10FFFF` or in the surrogate range. The prelude
    /// builtin is text construction rather than a method, so its owner is the
    /// empty text value that names the family and its one argument is the code.
    text_chr,
    /// The set vocabulary (SET-1) with no dictionary or list meaning:
    /// `add`, `discard`, `union`, `intersection`, `difference`,
    /// `symmetric_difference`, `issubset`, `issuperset` and `isdisjoint`. The
    /// checker desugars each into operations on the set's unit-valued table
    /// and loops over its keys, so none of these kinds reaches checked code.
    set_add,
    set_discard,
    set_union,
    set_intersection,
    set_difference,
    set_symmetric_difference,
    set_subset,
    set_superset,
    set_disjoint,
    /// PY-FSTRING-SPEC-1: `f"{text:spec}"`, the receiver text laid out under
    /// one packed specification word, its only argument.
    text_format,
    /// PY-FSTRING-SPEC-1: `f"{number:spec}"`. Like `chr`, the owner is the empty
    /// text naming the family; the arguments are the number's 64 bits and the
    /// packed specification word, which also says how to read the bits.
    number_format,
    /// PRELUDE-ROUND-2: `round(x, n)`. The owner is the empty text naming the
    /// runtime family; the arguments are the float and the digit count.
    float_round,
    /// Explicit charset trims; existing no-argument ordinals remain unchanged.
    strip_chars,
    lstrip_chars,
    rstrip_chars,
    /// Python search bounds; start-only and range variants have fixed IR arities.
    find_start,
    find_range,
    rfind,
    rfind_start,
    rfind_range,
    text_index,
    text_index_start,
    text_index_range,
    rindex,
    rindex_start,
    rindex_range,
    count_start,
    count_range,
    starts_with_start,
    starts_with_range,
    ends_with_start,
    ends_with_range,
    /// Exact Python scalar repr of a str or bytes receiver.
    text_repr,
    /// A str slice whose upper endpoint was omitted; its long suffix may share.
    text_tail,
    /// Explicit list sharing: later writes preserve both logical values with COW.
    snapshot,
    /// A nonowning text/byte range, checked by the zero-RC source contract.
    borrow_view,

    /// Return the required source argument count for this buffer builtin.
    pub fn arity(self: Kind) usize {
        return switch (self) {
            .length, .capacity, .keys, .values, .encode, .decode, .to_list, .hex, .from_hex => 0,
            .strip, .lstrip, .rstrip, .upper, .lower, .splitlines, .split_whitespace, .text_ord => 0,
            .is_digit, .is_alpha, .is_space, .parse_int, .parse_float => 0,
            .scalar_count => 0,
            .pop, .reverse, .sort, .copy, .snapshot, .clear, .items => 0,
            .buffer_reserve, .buffer_append_byte, .buffer_append_utf8, .buffer_append_int => 1,
            .buffer_append_float => 1,
            .count, .zfill => 1,
            .extend, .pop_at, .remove, .index_of, .pop_key, .update => 1,
            .buffer_append_range => 3,
            .replace, .insert, .setdefault, .pop_default => 2,
            .iteration_check, .key_at, .value_at, .read, .append, .take, .truncate, .contains, .split, .join, .starts_with, .ends_with, .find => 1,
            .text_chr, .text_format => 1,
            .number_format, .float_round => 2,
            .set_add, .set_discard, .set_union, .set_intersection, .set_difference, .set_symmetric_difference => 1,
            .set_subset, .set_superset, .set_disjoint => 1,
            .write, .resize, .reserve, .get, .slice, .text_tail, .find_any, .view, .borrow_view => 2,
            .sort_keyed => 3,
            .parse_int_range, .parse_float_range, .scalar_count_range => 2,
            .slice_step => 3,
            .strip_chars, .lstrip_chars, .rstrip_chars, .rfind, .text_index, .rindex => 1,
            .find_start, .rfind_start, .text_index_start, .rindex_start => 2,
            .count_start, .starts_with_start, .ends_with_start => 2,
            .find_range, .rfind_range, .text_index_range, .rindex_range => 3,
            .count_range, .starts_with_range, .ends_with_range => 3,
            .text_repr => 0,
        };
    }
    /// Identify operations that may allocate new guest backing storage.
    pub fn allocates(self: Kind) bool {
        return self == .reserve;
    }
    /// Identify operations that change the collection they are called on, as
    /// a caller sees it: its elements, its length or its reserved capacity.
    pub fn writesReceiver(self: Kind) bool {
        return switch (self) {
            .write, .append, .resize, .reserve, .take, .truncate, .extend, .insert, .pop, .pop_at, .remove, .reverse, .sort, .sort_keyed, .clear => true,
            .update, .setdefault, .pop_key, .pop_default => true,
            .buffer_reserve, .buffer_append_byte, .buffer_append_range, .buffer_append_utf8, .buffer_append_int, .buffer_append_float => true,
            else => false,
        };
    }
    /// Identify operations that modify buffer contents or initialized length.
    pub fn mutates(self: Kind) bool {
        if (search(self) != null or trim(self) != null or self == .text_repr) return false;
        return switch (self) {
            .length, .capacity, .iteration_check, .key_at, .value_at, .read, .get, .contains, .keys, .values, .split, .join => false,
            .encode, .decode, .to_list, .hex, .from_hex, .starts_with, .ends_with, .find, .find_any => false,
            .strip, .lstrip, .rstrip, .upper, .lower, .splitlines, .split_whitespace, .replace, .count, .zfill => false,
            .text_ord, .text_chr, .text_format, .number_format, .float_round => false,
            .is_digit, .is_alpha, .is_space, .parse_int, .parse_float => false,
            .parse_int_range, .parse_float_range => false,
            .view, .borrow_view, .scalar_count, .scalar_count_range => false,
            .copy, .snapshot, .items, .index_of => false,
            .set_union, .set_intersection, .set_difference, .set_symmetric_difference => false,
            .set_subset, .set_superset, .set_disjoint => false,
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
    /// A `set[T]` method (SET-1). A set is a dictionary-kind collection, so
    /// this flag, not the family, is what admits it.
    set: bool = false,
};

/// Accepted method names in spelling order. Each spelling appears once so the
/// resolver and the per-family suggestion lists share one source of truth.
const methods = [_]Method{
    .{ .spelling = "add", .kind = .set_add, .set = true },
    .{ .spelling = "append", .kind = .append, .list = true },
    .{ .spelling = "append_byte", .kind = .buffer_append_byte, .buffer = true },
    .{ .spelling = "append_float", .kind = .buffer_append_float, .buffer = true },
    .{ .spelling = "append_int", .kind = .buffer_append_int, .buffer = true },
    .{ .spelling = "append_range", .kind = .buffer_append_range, .buffer = true },
    .{ .spelling = "append_utf8", .kind = .buffer_append_utf8, .buffer = true },
    .{ .spelling = "clear", .kind = .clear, .list = true, .dictionary = true, .set = true },
    .{ .spelling = "copy", .kind = .copy, .list = true, .dictionary = true, .string = true, .bytes = true, .buffer = true, .set = true },
    .{ .spelling = "count", .kind = .count, .string = true, .bytes = true },
    .{ .spelling = "decode", .kind = .decode, .bytes = true },
    .{ .spelling = "difference", .kind = .set_difference, .set = true },
    .{ .spelling = "discard", .kind = .set_discard, .set = true },
    .{ .spelling = "encode", .kind = .encode, .string = true },
    .{ .spelling = "endswith", .kind = .ends_with, .string = true, .bytes = true },
    .{ .spelling = "extend", .kind = .extend, .list = true },
    .{ .spelling = "find", .kind = .find, .string = true, .bytes = true },
    .{ .spelling = "find_any", .kind = .find_any, .bytes = true },
    .{ .spelling = "get", .kind = .get, .dictionary = true },
    .{ .spelling = "hex", .kind = .hex, .bytes = true },
    .{ .spelling = "index", .kind = .index_of, .list = true, .string = true, .bytes = true },
    .{ .spelling = "insert", .kind = .insert, .list = true },
    .{ .spelling = "intersection", .kind = .set_intersection, .set = true },
    .{ .spelling = "isalpha", .kind = .is_alpha, .string = true },
    .{ .spelling = "isdigit", .kind = .is_digit, .string = true },
    .{ .spelling = "isdisjoint", .kind = .set_disjoint, .set = true },
    .{ .spelling = "isspace", .kind = .is_space, .string = true },
    .{ .spelling = "issubset", .kind = .set_subset, .set = true },
    .{ .spelling = "issuperset", .kind = .set_superset, .set = true },
    .{ .spelling = "items", .kind = .items, .dictionary = true },
    .{ .spelling = "join", .kind = .join, .string = true, .bytes = true },
    .{ .spelling = "keys", .kind = .keys, .dictionary = true },
    .{ .spelling = "lower", .kind = .lower, .string = true },
    .{ .spelling = "lstrip", .kind = .lstrip, .string = true, .bytes = true },
    .{ .spelling = "parse_float", .kind = .parse_float, .string = true, .bytes = true },
    .{ .spelling = "parse_float_range", .kind = .parse_float_range, .bytes = true },
    .{ .spelling = "parse_int", .kind = .parse_int, .string = true, .bytes = true },
    .{ .spelling = "parse_int_range", .kind = .parse_int_range, .bytes = true },
    .{ .spelling = "pop", .kind = .pop, .list = true, .dictionary = true, .set = true },
    .{ .spelling = "remove", .kind = .remove, .list = true, .set = true },
    .{ .spelling = "replace", .kind = .replace, .string = true },
    .{ .spelling = "reserve", .kind = .buffer_reserve, .buffer = true },
    .{ .spelling = "reverse", .kind = .reverse, .list = true },
    .{ .spelling = "rfind", .kind = .rfind, .string = true, .bytes = true },
    .{ .spelling = "rindex", .kind = .rindex, .string = true, .bytes = true },
    .{ .spelling = "rstrip", .kind = .rstrip, .string = true, .bytes = true },
    .{ .spelling = "scalar_count", .kind = .scalar_count, .bytes = true },
    .{ .spelling = "scalar_count_range", .kind = .scalar_count_range, .bytes = true },
    .{ .spelling = "setdefault", .kind = .setdefault, .dictionary = true },
    .{ .spelling = "snapshot", .kind = .snapshot, .list = true },
    .{ .spelling = "sort", .kind = .sort, .list = true },
    .{ .spelling = "split", .kind = .split, .string = true, .bytes = true },
    .{ .spelling = "splitlines", .kind = .splitlines, .string = true },
    .{ .spelling = "startswith", .kind = .starts_with, .string = true, .bytes = true },
    .{ .spelling = "strip", .kind = .strip, .string = true, .bytes = true },
    .{ .spelling = "symmetric_difference", .kind = .set_symmetric_difference, .set = true },
    .{ .spelling = "to_list", .kind = .to_list, .bytes = true },
    .{ .spelling = "union", .kind = .set_union, .set = true },
    .{ .spelling = "update", .kind = .update, .dictionary = true, .set = true },
    .{ .spelling = "borrow", .kind = .borrow_view, .string = true, .bytes = true, .buffer = true },
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

/// Resolve one method spelling for a call with `arguments` source arguments.
/// One Python spelling can name two operations: `split` with a separator is the
/// separator split, and `split` with no argument is the whitespace split, which
/// is a distinct kind because the argument count differs.
pub fn methodFor(name: []const u8, arguments: usize) ?Kind {
    const resolved = method(name) orelse return null;
    if (resolved == .split and arguments == 0) return .split_whitespace;
    if (arguments == 1) return switch (resolved) {
        .strip => .strip_chars,
        .lstrip => .lstrip_chars,
        .rstrip => .rstrip_chars,
        else => resolved,
    };
    return boundedMethod(resolved, arguments);
}

/// The method spelling one operation is written with, or null for an operation
/// no source spelling names. The whitespace split shares the `split` spelling
/// with the separator split, and `pop` is one spelling whose argument count
/// selects the list-index, dictionary-key or dictionary-default operation; the
/// argument list is what tells each family apart.
pub fn spelling(kind: Kind) ?[]const u8 {
    if (kind == .split_whitespace) return "split";
    if (search(kind)) |mode| return switch (mode) {
        .find => "find",
        .rfind => "rfind",
        .index => "index",
        .rindex => "rindex",
        .count => "count",
        .prefix => "startswith",
        .suffix => "endswith",
    };
    if (kind == .strip_chars) return "strip";
    if (kind == .lstrip_chars) return "lstrip";
    if (kind == .rstrip_chars) return "rstrip";
    if (kind == .pop_at or kind == .pop_key or kind == .pop_default) return "pop";
    inline for (methods) |entry| {
        if (kind == entry.kind) return entry.spelling;
    }
    return null;
}

/// Rendered signatures of the callables a call-site rejection names but that are
/// not collection methods, so every rejection renders the accepted callee through
/// one spelling table rather than a string literal at each site.
pub const stream_print_signature = "stream.print(values..., sep: str, end: str) -> None";
/// The `sorted` prelude builtin with Python's keyword-only `key=` and `reverse=`.
pub const sorted_signature = "sorted(values: list[T], *, key: def(T) -> K = None, reverse: bool = False) -> list[T]";
/// A list's `sort` method in its Python keyword form, sorting in place.
pub const list_sort_signature = "list[T].sort(*, key: def(T) -> K = None, reverse: bool = False) -> None";
/// The `range` iteration source: one bound or two, never a first-class value.
pub const range_signature = "range(end: int) -> iterable[int], range(start: int, end: int) -> iterable[int], or range(start: int, end: int, step: int) -> iterable[int]";
/// `min` and `max`, which fold a list or compare two values.
pub const extreme_signature = "min(values: list[T]) -> T, or min(left: T, right: T) -> T";

/// The type spellings one method signature is rendered with: the receiver as
/// source spells it, the receiver's managed family, and the element and key
/// types of a list, dictionary or byte string.
pub const SignatureNames = struct {
    receiver: []const u8,
    family: ManagedKind,
    element: []const u8 = "int",
    key: []const u8 = "int",
    /// The receiver is a `set[T]`, whose element is spelled by `key`.
    set: bool = false,
};

/// Render one collection method's checked signature exactly as the call-site
/// diagnostics print it, so a rejection and the interface listing can never
/// disagree: `str.split(separator: str) -> list[str]`. Returns null for an
/// operation that no method spelling names, which no call site can produce.
/// Render one collection method's checked signature exactly as the call-site
/// diagnostics print it, so a rejection and the interface listing can never
/// disagree: `str.split(separator: str) -> list[str]`. Returns null for an
/// operation that no method spelling names, which no call site can produce.
pub fn signatureText(allocator: std.mem.Allocator, kind: Kind, names: SignatureNames) std.mem.Allocator.Error!?[]const u8 {
    const name = spelling(kind) orelse return null;
    const body = try signatureBody(allocator, kind, names);
    defer allocator.free(body);
    const rendered = try std.fmt.allocPrint(allocator, "{s}.{s}{s}", .{ names.receiver, name, body });
    return rendered;
}

/// Signature shapes more than one operation renders, so each shape has one
/// spelling in this file.
const fresh_signature = "() -> {s}";
const fresh_list_signature = "() -> list[{s}]";
const needle_signature = "(needle: {s}) -> int";
const span_signature = "(start: int, end: int) -> {s}";
const index_signature = "(index: int) -> {s}";
const element_signature = "(value: {s}) -> None";
const keyed_signature = "(key: {s}) -> {s}";
const other_signature = "(other: {s}) -> None";

/// The `(...) -> ...` half of one rendered signature, appended to `writer`.
fn signatureBody(allocator: std.mem.Allocator, kind: Kind, names: SignatureNames) std.mem.Allocator.Error![]const u8 {
    if (names.set) return setSignatureBody(allocator, kind, names);
    const receiver = names.receiver;
    const element = names.element;
    const key = names.key;
    const dictionary = names.family == .dictionary;
    if (search(kind)) |mode| {
        const result = if (mode == .prefix or mode == .suffix) "bool" else "int";
        return std.fmt.allocPrint(allocator, "(sub: {s}, start: int = 0, end: int = len(self)) -> {s}", .{ receiver, result });
    }
    if (trim(kind) != null)
        return std.fmt.allocPrint(allocator, "(chars: {s} = whitespace) -> {s}", .{ receiver, receiver });
    return switch (kind) {
        .strip, .lstrip, .rstrip, .upper, .lower => try std.fmt.allocPrint(allocator, fresh_signature, .{receiver}),
        .splitlines, .split_whitespace => try std.fmt.allocPrint(allocator, fresh_list_signature, .{receiver}),
        .split => try std.fmt.allocPrint(allocator, "(separator: {s}) -> list[{s}]", .{ receiver, receiver }),
        .join => try std.fmt.allocPrint(allocator, "(parts: list[{s}]) -> {s}", .{ receiver, receiver }),
        .starts_with => try std.fmt.allocPrint(allocator, "(prefix: {s}) -> bool", .{receiver}),
        .ends_with => try std.fmt.allocPrint(allocator, "(suffix: {s}) -> bool", .{receiver}),
        .find, .count => try std.fmt.allocPrint(allocator, needle_signature, .{receiver}),
        .replace => try std.fmt.allocPrint(allocator, "(old: {s}, new: {s}) -> {s}", .{ receiver, receiver, receiver }),
        .zfill => try std.fmt.allocPrint(allocator, "(width: int) -> {s}", .{receiver}),
        .is_digit, .is_alpha, .is_space => try allocator.dupe(u8, "() -> bool"),
        .parse_int => try allocator.dupe(u8, "() -> Option[int]"),
        .parse_float => try allocator.dupe(u8, "() -> Option[float]"),
        .parse_int_range => try allocator.dupe(u8, "(start: int, end: int) -> Option[int]"),
        .parse_float_range => try allocator.dupe(u8, "(start: int, end: int) -> Option[float]"),
        .encode => try allocator.dupe(u8, "() -> bytes"),
        .decode => try allocator.dupe(u8, "() -> Result[str, str]"),
        .hex => try allocator.dupe(u8, "() -> str"),
        .to_list => try allocator.dupe(u8, "() -> list[int]"),
        .scalar_count => try allocator.dupe(u8, "() -> Result[int, str]"),
        .scalar_count_range => try allocator.dupe(u8, "(start: int, end: int) -> Result[int, str]"),
        .borrow_view => try std.fmt.allocPrint(allocator, span_signature, .{if (names.family == .string) "TextView" else "ByteView"}),
        .view, .slice, .text_tail => try std.fmt.allocPrint(allocator, span_signature, .{receiver}),
        .find_any => try std.fmt.allocPrint(allocator, "(values: {s}, start: int) -> int", .{receiver}),
        .slice_step => try std.fmt.allocPrint(allocator, "(start: int, end: int, step: int) -> {s}", .{receiver}),
        .length => try allocator.dupe(u8, "() -> int"),
        .read => try std.fmt.allocPrint(allocator, index_signature, .{if (names.family == .string) receiver else element}),
        .write => if (dictionary)
            try std.fmt.allocPrint(allocator, "(key: {s}, value: {s}) -> None", .{ key, element })
        else
            try std.fmt.allocPrint(allocator, "(index: int, value: {s}) -> None", .{element}),
        .append, .remove => try std.fmt.allocPrint(allocator, element_signature, .{element}),
        .extend => try std.fmt.allocPrint(allocator, other_signature, .{receiver}),
        .insert => try std.fmt.allocPrint(allocator, "(index: int, value: {s}) -> None", .{element}),
        .pop => try std.fmt.allocPrint(allocator, fresh_signature, .{element}),
        .pop_at => try std.fmt.allocPrint(allocator, index_signature, .{element}),
        .index_of => try std.fmt.allocPrint(allocator, "(value: {s}) -> int", .{element}),
        .reverse, .sort, .clear, .iteration_check => try allocator.dupe(u8, "() -> None"),
        .copy, .snapshot => try std.fmt.allocPrint(allocator, fresh_signature, .{receiver}),
        .contains => if (dictionary) try std.fmt.allocPrint(allocator, "(key: {s}) -> bool", .{key}) else try std.fmt.allocPrint(allocator, "(value: {s}) -> bool", .{element}),
        .keys => try std.fmt.allocPrint(allocator, fresh_list_signature, .{key}),
        .values, .items => try std.fmt.allocPrint(allocator, fresh_list_signature, .{element}),
        .get, .pop_key => if (kind == .get)
            try std.fmt.allocPrint(allocator, "(key: {s}, default: {s}) -> {s}", .{ key, element, element })
        else
            try std.fmt.allocPrint(allocator, keyed_signature, .{ key, element }),
        .update => try std.fmt.allocPrint(allocator, other_signature, .{receiver}),
        .setdefault, .pop_default => try std.fmt.allocPrint(allocator, "(key: {s}, default: {s}) -> {s}", .{ key, element, element }),
        .key_at => try std.fmt.allocPrint(allocator, index_signature, .{key}),
        .value_at => try std.fmt.allocPrint(allocator, index_signature, .{element}),
        .buffer_reserve => try allocator.dupe(u8, "(extra: int) -> bool"),
        .buffer_append_byte, .buffer_append_int => try allocator.dupe(u8, "(value: int) -> bool"),
        .buffer_append_float => try allocator.dupe(u8, "(value: float) -> bool"),
        .buffer_append_range => try allocator.dupe(u8, "(data: bytes, start: int, end: int) -> bool"),
        .buffer_append_utf8 => try allocator.dupe(u8, "(value: str) -> bool"),
        else => try allocator.dupe(u8, "()"),
    };
}

/// The `(...) -> ...` half of one `set[T]` method signature (SET-1).
fn setSignatureBody(allocator: std.mem.Allocator, kind: Kind, names: SignatureNames) std.mem.Allocator.Error![]const u8 {
    const receiver = names.receiver;
    return switch (kind) {
        .set_add, .set_discard, .remove => std.fmt.allocPrint(allocator, element_signature, .{names.key}),
        .pop => std.fmt.allocPrint(allocator, fresh_signature, .{names.key}),
        .copy => std.fmt.allocPrint(allocator, fresh_signature, .{receiver}),
        .clear => allocator.dupe(u8, "() -> None"),
        .update => std.fmt.allocPrint(allocator, other_signature, .{receiver}),
        .set_subset, .set_superset, .set_disjoint => std.fmt.allocPrint(allocator, "(other: {s}) -> bool", .{receiver}),
        else => std.fmt.allocPrint(allocator, "(other: {s}) -> {s}", .{ receiver, receiver }),
    };
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

/// Accepted `set[T]` method spellings, sorted (SET-1).
pub fn setMethodSpellings(allocator: std.mem.Allocator) std.mem.Allocator.Error![]const []const u8 {
    var count: usize = 0;
    for (methods) |entry| {
        if (entry.set) count += 1;
    }
    const selected = try allocator.alloc([]const u8, count);
    var index: usize = 0;
    for (methods) |entry| {
        if (!entry.set) continue;
        selected[index] = entry.spelling;
        index += 1;
    }
    return selected;
}

/// Whether `kind` is a method a `set[T]` receiver answers (SET-1).
pub fn setMethod(kind: Kind) bool {
    inline for (methods) |entry| {
        if (entry.set and entry.kind == kind) return true;
    }
    return false;
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
        .extend, .insert, .pop, .remove, .index_of, .reverse, .sort, .copy, .snapshot, .clear => true,
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
/// `float(text)`, byte numeric parsing and comparisons/searches. Scalar-count
/// ranges are conservatively allocating because malformed UTF-8 constructs the
/// checked result's error text; the older whole-value spelling retains its
/// compatibility classification.
pub fn managedAllocation(kind: Kind, dictionary: bool) bool {
    if (trim(kind) != null or kind == .text_repr) return true;
    return switch (kind) {
        .append, .split, .join, .keys, .values, .slice, .text_tail, .slice_step => true,
        .extend, .insert, .items, .copy, .snapshot, .update, .setdefault => true,
        .encode, .decode, .to_list, .hex, .from_hex => true,
        .strip, .lstrip, .rstrip, .upper, .lower, .splitlines, .replace, .zfill => true,
        .split_whitespace, .text_chr, .text_format, .number_format => true,
        .view => true,
        .scalar_count_range => true,
        .buffer_reserve, .buffer_append_byte, .buffer_append_range => true,
        .buffer_append_utf8, .buffer_append_int, .buffer_append_float => true,
        .write => dictionary,
        // The set vocabulary that inserts or builds a fresh set (SET-1).
        .set_add, .set_union, .set_intersection, .set_difference, .set_symmetric_difference => true,
        else => false,
    };
}

/// Search behavior passed unchanged to the nonallocating native range engines.
pub const Search = enum(u3) { find, rfind, index, rindex, count, prefix, suffix };

/// Search mode, including old whole-value operations whose ordinals are stable.
pub fn search(kind: Kind) ?Search {
    return switch (kind) {
        .find, .find_start, .find_range => .find,
        .rfind, .rfind_start, .rfind_range => .rfind,
        .text_index, .text_index_start, .text_index_range => .index,
        .rindex, .rindex_start, .rindex_range => .rindex,
        .count, .count_start, .count_range => .count,
        .starts_with, .starts_with_start, .starts_with_range => .prefix,
        .ends_with, .ends_with_start, .ends_with_range => .suffix,
        else => null,
    };
}

/// Trim direction: both ends, leading only, or trailing only.
pub fn trim(kind: Kind) ?u2 {
    return switch (kind) {
        .strip, .strip_chars => 0,
        .lstrip, .lstrip_chars => 1,
        .rstrip, .rstrip_chars => 2,
        else => null,
    };
}

/// Resolve the receiver-dependent index spelling without changing list.index.
pub fn forFamily(kind: Kind, family: ManagedKind) Kind {
    if (kind == .index_of and (family == .string or family == .bytes)) return .text_index;
    return kind;
}

fn boundedMethod(kind: Kind, arguments: usize) Kind {
    if (arguments != 2 and arguments != 3) return kind;
    const range = arguments == 3;
    return switch (kind) {
        .find => if (range) .find_range else .find_start,
        .rfind => if (range) .rfind_range else .rfind_start,
        .index_of => if (range) .text_index_range else .text_index_start,
        .rindex => if (range) .rindex_range else .rindex_start,
        .count => if (range) .count_range else .count_start,
        .starts_with => if (range) .starts_with_range else .starts_with_start,
        .ends_with => if (range) .ends_with_range else .ends_with_start,
        else => kind,
    };
}
