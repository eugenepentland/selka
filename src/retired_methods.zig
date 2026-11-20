//! The method spellings stage 2b retires, and the function homes that replace
//! them: `text.upper()` becomes `strings.upper(text)`.
//!
//! Each row is one public spelling that has a function home today, so the
//! refusal always carries the certain rewrite. A home whose operation *is* the
//! method is a `builtin func` (`strings.upper`), so the standard library calls
//! the homes as programs do and no source is exempt from a refusal (W13, slice 3).
const std = @import("std");
const ManagedKind = @import("runtime_values.zig").ManagedKind;
const source = @import("source.zig");

/// Stable code for every retired method spelling.
pub const code = "E_METHOD_REMOVED";

/// What the replacement answers in place of the method's `-1` sentinel.
pub const Absence = enum {
    /// The replacement answers what the method did: a plain offset with `-1`
    /// for absent, so the rewrite keeps every use.
    plain,
    /// The replacement answers an `int?`, so a caller tests absence with
    /// `is None` and this stage supplies the comparison repairs (F57).
    option,
};

/// Where a retired method's replacement lives. `module` is null for a prelude
/// function, which needs no import; `writer` marks the operations that take the
/// receiver with the call-site `mut` marker.
pub const Home = struct {
    /// The standard module that owns the replacement, or null for the prelude.
    module: ?[]const u8 = null,
    /// The replacement function's own name.
    function: []const u8,
    /// Whether the replacement writes its receiver.
    writer: bool = false,
    /// Whether the receiver is the replacement's *last* operand. `bytes.join`
    /// takes the parts first and the separator — the method's receiver — last.
    arguments_first: bool = false,
    /// What the replacement answers where the method answered `-1`.
    absence: Absence = .plain,
    /// The replacement's operand sketch, as the refusal's message writes it; a
    /// plain receiver is `value`, and a writer's marker form is
    /// `mut value` unless the row names its operands.
    operands: []const u8 = "",
};

/// The receiver shape a retired spelling belongs to within its family (F-b). A
/// `set[T]` shares the dictionary kind and the mutable `byte_buffer` shares the
/// byte kind, so the family alone cannot tell their rows from the plain
/// collection's: a set answers its own nine operations, and a buffer its writes.
pub const Shape = enum {
    /// Any other managed collection: a list, a dictionary, `str` or `bytes`.
    collection,
    /// A `set[T]`, whose own operations are the `sets` module's.
    set,
    /// The mutable `byte_buffer`, whose writes are the `buffers` module's.
    buffer,
};

/// What a replacement answers in place of its method's answer (wave 2, lane B). A
/// method that answers `bool` keeps the answer, so its statement form keeps `_ =`.
/// A method that always answered `true` has a replacement that answers nothing,
/// so the statement form is bare.
pub const Answer = enum {
    /// The replacement answers the method's `bool`.
    flag,
    /// The replacement answers nothing: the method always answered `true`.
    nothing,
};

/// One retired spelling: the method name, the receiver family and shape that
/// accepted it, the argument count that selected it, and its replacement.
pub const Retirement = struct {
    /// The method spelling a caller writes today.
    method: []const u8,
    /// The collection family the receiver had to be.
    family: ManagedKind,
    /// The argument count the spelling took.
    arguments: usize,
    /// The function that replaces it.
    home: Home,
    /// The receiver shape the spelling needed within `family`.
    shape: Shape = .collection,
    /// What the replacement answers in place of the method's answer.
    answer: Answer = .flag,
};

/// Every spelling this stage retires. A row appears only when the home exists,
/// so the refusal's rewrite is certain; the rest of the family lands with its
/// homes.
pub const retirements = [_]Retirement{
    .{ .method = "count", .family = .bytes, .arguments = 1, .home = .{ .module = "bytes", .function = "count", .operands = "value, needle" } },
    .{ .method = "endswith", .family = .bytes, .arguments = 1, .home = .{ .module = "bytes", .function = "ends_with", .operands = "value, suffix" } },
    .{ .method = "find", .family = .bytes, .arguments = 1, .home = .{ .module = "bytes", .function = "find", .operands = "value, needle" } },
    .{ .method = "join", .family = .bytes, .arguments = 1, .home = .{ .module = "bytes", .function = "join", .arguments_first = true, .operands = "parts, separator" } },
    .{ .method = "lstrip", .family = .bytes, .arguments = 0, .home = .{ .module = "bytes", .function = "lstrip" } },
    .{ .method = "rfind", .family = .bytes, .arguments = 1, .home = .{ .module = "bytes", .function = "rfind", .operands = "value, needle" } },
    .{ .method = "rstrip", .family = .bytes, .arguments = 0, .home = .{ .module = "bytes", .function = "rstrip" } },
    .{ .method = "split", .family = .bytes, .arguments = 1, .home = .{ .module = "bytes", .function = "split", .operands = "value, separator" } },
    .{ .method = "startswith", .family = .bytes, .arguments = 1, .home = .{ .module = "bytes", .function = "starts_with", .operands = "value, prefix" } },
    .{ .method = "strip", .family = .bytes, .arguments = 0, .home = .{ .module = "bytes", .function = "strip" } },
    .{ .method = "endswith", .family = .string, .arguments = 1, .home = .{ .module = "strings", .function = "ends_with", .operands = "value, suffix" } },
    .{ .method = "isalpha", .family = .string, .arguments = 0, .home = .{ .module = "strings", .function = "is_alpha" } },
    .{ .method = "isdigit", .family = .string, .arguments = 0, .home = .{ .module = "strings", .function = "is_digit" } },
    .{ .method = "isspace", .family = .string, .arguments = 0, .home = .{ .module = "strings", .function = "is_space" } },
    .{ .method = "lower", .family = .string, .arguments = 0, .home = .{ .module = "strings", .function = "lower" } },
    .{ .method = "lstrip", .family = .string, .arguments = 0, .home = .{ .module = "strings", .function = "lstrip" } },
    .{ .method = "replace", .family = .string, .arguments = 2, .home = .{ .module = "strings", .function = "replace", .operands = "value, old, new" } },
    .{ .method = "rstrip", .family = .string, .arguments = 0, .home = .{ .module = "strings", .function = "rstrip" } },
    .{ .method = "split", .family = .string, .arguments = 1, .home = .{ .module = "strings", .function = "split", .operands = "value, separator" } },
    .{ .method = "splitlines", .family = .string, .arguments = 0, .home = .{ .module = "strings", .function = "lines" } },
    .{ .method = "startswith", .family = .string, .arguments = 1, .home = .{ .module = "strings", .function = "starts_with", .operands = "value, prefix" } },
    .{ .method = "strip", .family = .string, .arguments = 0, .home = .{ .module = "strings", .function = "strip" } },
    .{ .method = "upper", .family = .string, .arguments = 0, .home = .{ .module = "strings", .function = "upper" } },
    // The four text search words (F57). `find` and `rfind` answer an option, so
    // their comparison shapes carry the `is None` / `Some(N)` repairs; `index`
    // and `rindex` keep trapping when the needle is absent, so their rewrite
    // changes no use.
    .{ .method = "find", .family = .string, .arguments = 1, .home = .{ .module = "strings", .function = "find", .absence = .option, .operands = "value, needle" } },
    .{ .method = "rfind", .family = .string, .arguments = 1, .home = .{ .module = "strings", .function = "rfind", .absence = .option, .operands = "value, needle" } },
    .{ .method = "index", .family = .string, .arguments = 1, .home = .{ .module = "strings", .function = "text_index", .operands = "value, needle" } },
    .{ .method = "rindex", .family = .string, .arguments = 1, .home = .{ .module = "strings", .function = "text_rindex", .operands = "value, needle" } },
    // The list family (F59). `append` and `sort` are prelude writers; the rest
    // live in `lists`, whose names are the compiler's own `Kind` names
    // (`index_of`, `pop_at`). `sort` takes the method's keyword operands too,
    // so it has a row per accepted count.
    .{ .method = "append", .family = .list, .arguments = 1, .home = .{ .function = "append", .writer = true, .operands = "mut value, item" } },
    .{ .method = "sort", .family = .list, .arguments = 0, .home = .{ .function = "sort", .writer = true } },
    .{ .method = "sort", .family = .list, .arguments = 1, .home = .{ .function = "sort", .writer = true, .operands = "mut value, reverse=flag" } },
    .{ .method = "sort", .family = .list, .arguments = 2, .home = .{ .function = "sort", .writer = true, .operands = "mut value, key=key_fn, reverse=flag" } },
    // The list's module words (round 24). `pop` is one spelling whose argument
    // count selects the tail or the index form, and `index` is the method name
    // for the compiler's own `index_of` kind.
    .{ .method = "pop", .family = .list, .arguments = 0, .home = .{ .module = "lists", .function = "pop", .writer = true, .operands = "mut value" } },
    .{ .method = "pop", .family = .list, .arguments = 1, .home = .{ .module = "lists", .function = "pop_at", .writer = true, .operands = "mut value, index" } },
    .{ .method = "extend", .family = .list, .arguments = 1, .home = .{ .module = "lists", .function = "extend", .writer = true, .operands = "mut value, other" } },
    .{ .method = "insert", .family = .list, .arguments = 2, .home = .{ .module = "lists", .function = "insert", .writer = true, .operands = "mut value, index, element" } },
    .{ .method = "remove", .family = .list, .arguments = 1, .home = .{ .module = "lists", .function = "remove", .writer = true, .operands = "mut value, element" } },
    .{ .method = "index", .family = .list, .arguments = 1, .home = .{ .module = "lists", .function = "index_of", .operands = "value, element" } },
    .{ .method = "clear", .family = .list, .arguments = 0, .home = .{ .module = "lists", .function = "clear", .writer = true, .operands = "mut value" } },
    .{ .method = "reverse", .family = .list, .arguments = 0, .home = .{ .module = "lists", .function = "reverse", .writer = true, .operands = "mut value" } },
    // The dictionary family (F-d). Each home lowers to the buffer operation its
    // method spelling built, so the emitted program is the method's, with no
    // copy the method did not make (plan 4b, rule C). `keys`, `values` and
    // `items` answer ephemeral views that a function cannot return, so their
    // homes are recognized calls with no guest body. A `set[T]` shares the
    // dictionary kind and keeps its `update`, `pop` and `clear` (the checker
    // excludes sets; their family is a later step).
    .{ .method = "get", .family = .dictionary, .arguments = 2, .home = .{ .module = "dicts", .function = "get", .operands = "mapping, key, fallback" } },
    .{ .method = "keys", .family = .dictionary, .arguments = 0, .home = .{ .module = "dicts", .function = "keys", .operands = "mapping" } },
    .{ .method = "values", .family = .dictionary, .arguments = 0, .home = .{ .module = "dicts", .function = "values", .operands = "mapping" } },
    .{ .method = "items", .family = .dictionary, .arguments = 0, .home = .{ .module = "dicts", .function = "items", .operands = "mapping" } },
    .{ .method = "setdefault", .family = .dictionary, .arguments = 2, .home = .{ .module = "dicts", .function = "setdefault", .writer = true, .operands = "mut mapping, key, fallback" } },
    .{ .method = "update", .family = .dictionary, .arguments = 1, .home = .{ .module = "dicts", .function = "update", .writer = true, .operands = "mut mapping, other" } },
    .{ .method = "pop", .family = .dictionary, .arguments = 1, .home = .{ .module = "dicts", .function = "pop", .writer = true, .operands = "mut mapping, key" } },
    .{ .method = "pop", .family = .dictionary, .arguments = 2, .home = .{ .module = "dicts", .function = "pop_default", .writer = true, .operands = "mut mapping, key, fallback" } },
    .{ .method = "clear", .family = .dictionary, .arguments = 0, .home = .{ .module = "dicts", .function = "clear", .writer = true, .operands = "mut mapping" } },
    // The set family (F-b, F27 and F28). A set's own nine operations move to the
    // `sets` module; its `update`, `pop`, `clear` and `remove` keep their methods,
    // whose homes are in `method_homes`. Each home lowers to the set operation its method built.
    .{ .method = "add", .family = .dictionary, .shape = .set, .arguments = 1, .home = .{ .module = "sets", .function = "add", .writer = true, .operands = "mut values, value" } },
    .{ .method = "discard", .family = .dictionary, .shape = .set, .arguments = 1, .home = .{ .module = "sets", .function = "discard", .writer = true, .operands = "mut values, value" } },
    .{ .method = "union", .family = .dictionary, .shape = .set, .arguments = 1, .home = .{ .module = "sets", .function = "union", .operands = "left, right" } },
    .{ .method = "intersection", .family = .dictionary, .shape = .set, .arguments = 1, .home = .{ .module = "sets", .function = "intersection", .operands = "left, right" } },
    .{ .method = "difference", .family = .dictionary, .shape = .set, .arguments = 1, .home = .{ .module = "sets", .function = "difference", .operands = "left, right" } },
    .{ .method = "symmetric_difference", .family = .dictionary, .shape = .set, .arguments = 1, .home = .{ .module = "sets", .function = "symmetric_difference", .operands = "left, right" } },
    .{ .method = "issubset", .family = .dictionary, .shape = .set, .arguments = 1, .home = .{ .module = "sets", .function = "subset", .operands = "left, right" } },
    .{ .method = "issuperset", .family = .dictionary, .shape = .set, .arguments = 1, .home = .{ .module = "sets", .function = "superset", .operands = "left, right" } },
    .{ .method = "isdisjoint", .family = .dictionary, .shape = .set, .arguments = 1, .home = .{ .module = "sets", .function = "disjoint", .operands = "left, right" } },
    // The mutable octet buffer's writes (wave 2, lane B). Each home is a `buffers`
    // function with its method's operand types. `append_byte`, `append_range` and
    // `reserve` answer whether they wrote (`bool`), so a statement keeps `_ =`; the
    // other four always write, so their homes answer nothing.
    .{ .method = "append_byte", .family = .bytes, .shape = .buffer, .arguments = 1, .home = .{ .module = "buffers", .function = "append_byte", .writer = true, .operands = "mut data, value" } },
    .{ .method = "append_range", .family = .bytes, .shape = .buffer, .arguments = 3, .home = .{ .module = "buffers", .function = "append_range", .writer = true, .operands = "mut data, piece, start, end" } },
    .{ .method = "reserve", .family = .bytes, .shape = .buffer, .arguments = 1, .home = .{ .module = "buffers", .function = "reserve", .writer = true, .operands = "mut data, extra" } },
    .{ .method = "append", .family = .bytes, .shape = .buffer, .arguments = 1, .home = .{ .module = "buffers", .function = "append", .writer = true, .operands = "mut data, piece" }, .answer = .nothing },
    // `clear` is no method of a buffer today: the row gives `buf.clear()` the repair a list's `xs.clear()` has, and the
    // home empties the buffer and keeps its storage (`myl_core_buffer_clear`).
    .{ .method = "clear", .family = .bytes, .shape = .buffer, .arguments = 0, .home = .{ .module = "buffers", .function = "clear", .writer = true, .operands = "mut data" } },
    .{ .method = "append_int", .family = .bytes, .shape = .buffer, .arguments = 1, .home = .{ .module = "buffers", .function = "append_int", .writer = true, .operands = "mut data, value" }, .answer = .nothing },
    .{ .method = "append_float", .family = .bytes, .shape = .buffer, .arguments = 1, .home = .{ .module = "buffers", .function = "append_float", .writer = true, .operands = "mut data, value" }, .answer = .nothing },
    .{ .method = "append_utf8", .family = .bytes, .shape = .buffer, .arguments = 1, .home = .{ .module = "buffers", .function = "append_utf8", .writer = true, .operands = "mut data, text" }, .answer = .nothing },
    // The byte range words (F-b, F32). Each `bytes` home is declared and its body is
    // the method, so a call lowers to the method's own range operation. `view` and
    // `borrow` answer view types no signature can name, so they keep their methods.
    .{ .method = "parse_int_range", .family = .bytes, .arguments = 2, .home = .{ .module = "bytes", .function = "parse_int_range", .operands = "value, start, end" } },
    .{ .method = "parse_float_range", .family = .bytes, .arguments = 2, .home = .{ .module = "bytes", .function = "parse_float_range", .operands = "value, start, end" } },
    .{ .method = "scalar_count_range", .family = .bytes, .arguments = 2, .home = .{ .module = "bytes", .function = "scalar_count_range", .operands = "value, start, end" } },
};

/// The function homes of method spellings that are still accepted (W13, slice 1). Each row has the shape of a
/// retirement and its home lowers to the method's own operation, exactly as a retired row's does, so a call of the
/// home is the method's code. No row here refuses anything: `find`, `findShaped` and `retires` read `retirements`
/// only, and the next slice moves these rows there (as warnings first). `home` reads both tables.
pub const method_homes = [_]Retirement{
    // Text (`str`). The strip family with a character set, the zero fill, the whitespace split and the join are the
    // native operations; `count`, `text_index`, `text_rindex`, `starts_with` and `ends_with` take the optional
    // `start` and `end` bounds of the ranged methods (W13-Q3), one row per accepted count.
    .{ .method = "strip", .family = .string, .arguments = 1, .home = .{ .module = "strings", .function = "strip_chars", .operands = "value, characters" } },
    .{ .method = "lstrip", .family = .string, .arguments = 1, .home = .{ .module = "strings", .function = "lstrip_chars", .operands = "value, characters" } },
    .{ .method = "rstrip", .family = .string, .arguments = 1, .home = .{ .module = "strings", .function = "rstrip_chars", .operands = "value, characters" } },
    .{ .method = "zfill", .family = .string, .arguments = 1, .home = .{ .module = "strings", .function = "zfill", .operands = "value, width" } },
    .{ .method = "split", .family = .string, .arguments = 0, .home = .{ .module = "strings", .function = "words" } },
    .{ .method = "join", .family = .string, .arguments = 1, .home = .{ .module = "strings", .function = "join", .arguments_first = true, .operands = "parts, separator" } },
    .{ .method = "encode", .family = .string, .arguments = 0, .home = .{ .module = "strings", .function = "encode" } },
    .{ .method = "count", .family = .string, .arguments = 1, .home = .{ .module = "strings", .function = "count", .operands = "value, needle" } },
    .{ .method = "count", .family = .string, .arguments = 2, .home = .{ .module = "strings", .function = "count", .operands = "value, needle, start" } },
    .{ .method = "count", .family = .string, .arguments = 3, .home = .{ .module = "strings", .function = "count", .operands = "value, needle, start, end" } },
    .{ .method = "index", .family = .string, .arguments = 2, .home = .{ .module = "strings", .function = "text_index", .operands = "value, needle, start" } },
    .{ .method = "index", .family = .string, .arguments = 3, .home = .{ .module = "strings", .function = "text_index", .operands = "value, needle, start, end" } },
    .{ .method = "rindex", .family = .string, .arguments = 2, .home = .{ .module = "strings", .function = "text_rindex", .operands = "value, needle, start" } },
    .{ .method = "rindex", .family = .string, .arguments = 3, .home = .{ .module = "strings", .function = "text_rindex", .operands = "value, needle, start, end" } },
    .{ .method = "startswith", .family = .string, .arguments = 2, .home = .{ .module = "strings", .function = "starts_with", .operands = "value, prefix, start" } },
    .{ .method = "startswith", .family = .string, .arguments = 3, .home = .{ .module = "strings", .function = "starts_with", .operands = "value, prefix, start, end" } },
    .{ .method = "endswith", .family = .string, .arguments = 2, .home = .{ .module = "strings", .function = "ends_with", .operands = "value, suffix, start" } },
    .{ .method = "endswith", .family = .string, .arguments = 3, .home = .{ .module = "strings", .function = "ends_with", .operands = "value, suffix, start, end" } },
    .{ .method = "sha256", .family = .string, .arguments = 0, .home = .{ .module = "hashes", .function = "sha256_text_bytes" } },
    .{ .method = "blake3", .family = .string, .arguments = 0, .home = .{ .module = "hashes", .function = "blake3_text_bytes" } },
    // Bytes. A `byte_buffer` is accepted wherever one of these reads `bytes` (W13-Q5, `lendsBuffer`).
    .{ .method = "split", .family = .bytes, .arguments = 0, .home = .{ .module = "bytes", .function = "words" } },
    .{ .method = "strip", .family = .bytes, .arguments = 1, .home = .{ .module = "bytes", .function = "strip_chars", .operands = "value, characters" } },
    .{ .method = "lstrip", .family = .bytes, .arguments = 1, .home = .{ .module = "bytes", .function = "lstrip_chars", .operands = "value, characters" } },
    .{ .method = "rstrip", .family = .bytes, .arguments = 1, .home = .{ .module = "bytes", .function = "rstrip_chars", .operands = "value, characters" } },
    .{ .method = "find", .family = .bytes, .arguments = 2, .home = .{ .module = "bytes", .function = "find", .operands = "value, needle, start" } },
    .{ .method = "find", .family = .bytes, .arguments = 3, .home = .{ .module = "bytes", .function = "find", .operands = "value, needle, start, end" } },
    .{ .method = "rfind", .family = .bytes, .arguments = 2, .home = .{ .module = "bytes", .function = "rfind", .operands = "value, needle, start" } },
    .{ .method = "rfind", .family = .bytes, .arguments = 3, .home = .{ .module = "bytes", .function = "rfind", .operands = "value, needle, start, end" } },
    .{ .method = "count", .family = .bytes, .arguments = 2, .home = .{ .module = "bytes", .function = "count", .operands = "value, needle, start" } },
    .{ .method = "count", .family = .bytes, .arguments = 3, .home = .{ .module = "bytes", .function = "count", .operands = "value, needle, start, end" } },
    .{ .method = "startswith", .family = .bytes, .arguments = 2, .home = .{ .module = "bytes", .function = "starts_with", .operands = "value, prefix, start" } },
    .{ .method = "startswith", .family = .bytes, .arguments = 3, .home = .{ .module = "bytes", .function = "starts_with", .operands = "value, prefix, start, end" } },
    .{ .method = "endswith", .family = .bytes, .arguments = 2, .home = .{ .module = "bytes", .function = "ends_with", .operands = "value, suffix, start" } },
    .{ .method = "endswith", .family = .bytes, .arguments = 3, .home = .{ .module = "bytes", .function = "ends_with", .operands = "value, suffix, start, end" } },
    .{ .method = "index", .family = .bytes, .arguments = 1, .home = .{ .module = "bytes", .function = "index", .operands = "value, needle" } },
    .{ .method = "index", .family = .bytes, .arguments = 2, .home = .{ .module = "bytes", .function = "index", .operands = "value, needle, start" } },
    .{ .method = "index", .family = .bytes, .arguments = 3, .home = .{ .module = "bytes", .function = "index", .operands = "value, needle, start, end" } },
    .{ .method = "rindex", .family = .bytes, .arguments = 1, .home = .{ .module = "bytes", .function = "rindex", .operands = "value, needle" } },
    .{ .method = "rindex", .family = .bytes, .arguments = 2, .home = .{ .module = "bytes", .function = "rindex", .operands = "value, needle, start" } },
    .{ .method = "rindex", .family = .bytes, .arguments = 3, .home = .{ .module = "bytes", .function = "rindex", .operands = "value, needle, start, end" } },
    .{ .method = "parse_int", .family = .bytes, .arguments = 0, .home = .{ .module = "bytes", .function = "parse_int" } },
    .{ .method = "parse_float", .family = .bytes, .arguments = 0, .home = .{ .module = "bytes", .function = "parse_float" } },
    .{ .method = "scalar_count", .family = .bytes, .arguments = 0, .home = .{ .module = "bytes", .function = "scalar_count" } },
    .{ .method = "to_list", .family = .bytes, .arguments = 0, .home = .{ .module = "bytes", .function = "to_list" } },
    .{ .method = "find_any", .family = .bytes, .arguments = 2, .home = .{ .module = "bytes", .function = "find_any", .operands = "value, octets, start" } },
    .{ .method = "find_any", .family = .bytes, .arguments = 3, .home = .{ .module = "bytes", .function = "find_any", .operands = "value, octets, start, end" } },
    .{ .method = "decode", .family = .bytes, .arguments = 0, .home = .{ .module = "strings", .function = "decode" } },
    .{ .method = "hex", .family = .bytes, .arguments = 0, .home = .{ .module = "hex", .function = "encode" } },
    .{ .method = "sha256", .family = .bytes, .arguments = 0, .home = .{ .module = "hashes", .function = "sha256_bytes" } },
    .{ .method = "blake3", .family = .bytes, .arguments = 0, .home = .{ .module = "hashes", .function = "blake3_bytes" } },
    // The list's exchange (W13, slice 3): `lists.exchange` is the method's own operation, so it takes what the method
    // takes, any integer index, any element and a fresh replacement such as `Ok(5)`; a named managed replacement needs
    // `own` in both spellings, and the rewrite keeps the operand's text.
    .{ .method = "exchange", .family = .list, .arguments = 2, .home = .{ .module = "lists", .function = "exchange", .writer = true, .operands = "mut values, index, replacement" } },
    // A set's four writes that had no home (F-b): each lowers to the set operation its method built.
    .{ .method = "clear", .family = .dictionary, .shape = .set, .arguments = 0, .home = .{ .module = "sets", .function = "clear", .writer = true, .operands = "mut values" } },
    .{ .method = "pop", .family = .dictionary, .shape = .set, .arguments = 0, .home = .{ .module = "sets", .function = "pop", .writer = true, .operands = "mut values" } },
    .{ .method = "remove", .family = .dictionary, .shape = .set, .arguments = 1, .home = .{ .module = "sets", .function = "remove", .writer = true, .operands = "mut values, value" } },
    .{ .method = "update", .family = .dictionary, .shape = .set, .arguments = 1, .home = .{ .module = "sets", .function = "update", .writer = true, .operands = "mut values, other" } },
};

/// Method spellings that warn (`retiring_forms`) although their home is not the method's own lowering, so `home` does not
/// read them: the text searches with bounds (their home answers `int?`, repaired in a comparison as F57's retired
/// searches are) and the text parses (prelude homes, which a declaration of the same name captures).
pub const method_forms = [_]Retirement{
    .{ .method = "find", .family = .string, .arguments = 2, .home = .{ .module = "strings", .function = "find", .absence = .option, .operands = "value, needle, start" } },
    .{ .method = "find", .family = .string, .arguments = 3, .home = .{ .module = "strings", .function = "find", .absence = .option, .operands = "value, needle, start, end" } },
    .{ .method = "rfind", .family = .string, .arguments = 2, .home = .{ .module = "strings", .function = "rfind", .absence = .option, .operands = "value, needle, start" } },
    .{ .method = "rfind", .family = .string, .arguments = 3, .home = .{ .module = "strings", .function = "rfind", .absence = .option, .operands = "value, needle, start, end" } },
    .{ .method = "parse_int", .family = .string, .arguments = 0, .home = .{ .function = "parse_int" } },
    .{ .method = "parse_float", .family = .string, .arguments = 0, .home = .{ .function = "parse_float" } },
    .{ .method = "parse_f32", .family = .string, .arguments = 0, .home = .{ .function = "parse_f32" } },
};

/// Homes only the standard library declares and calls (W13, slice 3): private `builtin func` declarations whose operation
/// is a method no public function answers in the same way. `strings.find` and `strings.rfind` answer `int?`, and their
/// bodies need the bounded search's `-1`, which they convert. `home` does not read these rows, so no program call is
/// recognized as one; a program cannot name a private function either.
pub const library_homes = [_]Retirement{
    .{ .method = "find", .family = .string, .arguments = 3, .home = .{ .module = "strings", .function = "find_offset", .operands = "value, needle, start, end" } },
    .{ .method = "rfind", .family = .string, .arguments = 3, .home = .{ .module = "strings", .function = "rfind_offset", .operands = "value, needle, start, end" } },
};

/// The library-only home `module.function` with `arguments` operands including the receiver, or null (`library_homes`).
pub fn libraryHome(module: []const u8, function: []const u8, arguments: usize) ?Retirement {
    for (library_homes) |row| {
        if (row.arguments + 1 != arguments) continue;
        if (!std.mem.eql(u8, row.home.module.?, module) or !std.mem.eql(u8, row.home.function, function)) continue;
        return row;
    }
    return null;
}

/// Whether a home of `row` also takes a `byte_buffer` where it reads `bytes` (W13-Q5): every read of the byte family
/// whose method a buffer answers, which is every byte row but `join` (its receiver is the separator) and the buffer's
/// own writes. The buffer lends its octets for the call, as its method's receiver does.
pub fn lendsBuffer(row: Retirement) bool {
    return row.family == .bytes and row.shape == .collection and !std.mem.eql(u8, row.method, "join");
}

/// The retirement one method spelling names for a plain collection receiver of
/// `family` called with `arguments` operands, or null when the spelling keeps
/// its home. A set or a mutable buffer asks `findShaped` with its own shape.
pub fn find(method: []const u8, family: ManagedKind, arguments: usize) ?Retirement {
    return findShaped(method, family, .collection, arguments);
}

/// The retirement one method spelling names for a receiver of `family` and
/// `shape` called with `arguments` operands, or null when the spelling keeps its
/// home (F-b): a set's `add` and a buffer's `append_byte` are rows of their own.
pub fn findShaped(method: []const u8, family: ManagedKind, shape: Shape, arguments: usize) ?Retirement {
    for (retirements) |retirement| {
        if (!std.mem.eql(u8, retirement.method, method)) continue;
        if (retirement.family != family or retirement.shape != shape or retirement.arguments != arguments) continue;
        return retirement;
    }
    return null;
}

/// Whether this stage retires `method` for `family` at any argument count. `selka reference` asks this.
pub fn retires(method: []const u8, family: ManagedKind) bool {
    for (retirements) |retirement| {
        if (retirement.family != family) continue;
        if (std.mem.eql(u8, retirement.method, method)) return true;
    }
    return false;
}

/// Whether `method` on `family` is refused or retiring at any argument count: a retired row, or a row W13 warns about
/// (`method_homes`, `method_forms`). The receiver's accepted-method list asks this, so it advertises no spelling the
/// checker refuses or a later release will (W13, slice 3); `selka reference` reports what checks today (`retires`).
pub fn retiring(method: []const u8, family: ManagedKind) bool {
    inline for (.{ &retirements, &method_homes, &method_forms }) |table| for (table) |row| {
        if (row.family == family and std.mem.eql(u8, row.method, method)) return true;
    };
    return false;
}

/// The retirement whose function home is `module.function` called with
/// `arguments` operands including the receiver, or null when the call is not a
/// home. The checker asks this before ordinary resolution, so a recognized home
/// lowers to the same operation its retired spelling did.
pub fn home(module: []const u8, function: []const u8, arguments: usize) ?Retirement {
    inline for (.{ &retirements, &method_homes }) |table| for (table) |retirement| {
        const owner = retirement.home.module orelse continue;
        if (!std.mem.eql(u8, owner, module)) continue;
        if (!std.mem.eql(u8, retirement.home.function, function)) continue;
        if (retirement.arguments + 1 != arguments) continue;
        return retirement;
    };
    return null;
}

/// The row a retired call becomes for its written argument (F-2). `sets.add` takes its value `own`, which the method
/// did not, so a value the caller only lends (a parameter, a loop or pattern binding, a field or element) would be
/// refused next round; `sets.include` borrows it and copies it only when the set lacks it. A value the caller can give
/// (`givable`: a literal, a call's result, an owned local) keeps `sets.add`, whose `own` marker the next round's
/// repair writes. Every other row is returned unchanged.
pub fn forArgument(retirement: Retirement, givable: bool) Retirement {
    const module = retirement.home.module orelse return retirement;
    if (givable) return retirement;
    const set_add = std.mem.eql(u8, module, "sets") and std.mem.eql(u8, retirement.home.function, "add");
    if (!set_add) return retirement;
    var borrowed = retirement;
    borrowed.home.function = "include";
    return borrowed;
}

/// The one-line diagnostic message naming the function a retired spelling
/// becomes, in the shape `strings.upper(text)` or `parse_int(text)`.
pub fn message(allocator: std.mem.Allocator, retirement: Retirement) std.mem.Allocator.Error![]const u8 {
    const call = try std.fmt.allocPrint(
        allocator,
        "`{s}()` is a function now; write `{s}{s}{s}({s})`",
        .{ retirement.method, retirement.home.module orelse "", if (retirement.home.module != null) "." else "", retirement.home.function, sketch(retirement.home) },
    );
    defer allocator.free(call);
    // The option homes never answer `-1`, so the message also names the
    // convention a comparison has to change to (F57).
    if (retirement.home.absence == .option)
        return std.fmt.allocPrint(allocator, "{s}; it answers `int?`, so test absence with `is None`", .{call});
    return allocator.dupe(u8, call);
}

/// The one-line message for a value use of a home that answers nothing (wave 2,
/// lane B). Its statement form is the only repair, so the message names it.
pub fn nothingMessage(allocator: std.mem.Allocator, retirement: Retirement) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "`{s}()` answers nothing; write `{s}{s}{s}({s})` as a statement of its own",
        .{ retirement.method, retirement.home.module orelse "", if (retirement.home.module != null) "." else "", retirement.home.function, sketch(retirement.home) },
    );
}

/// The operand sketch the message writes: the row's own when it names one, the
/// writer's marker form when it only knows that the receiver is written, and a
/// plain `value` otherwise.
fn sketch(replacement: Home) []const u8 {
    if (replacement.operands.len != 0) return replacement.operands;
    return if (replacement.writer) "mut value" else "value";
}

/// The replacement call: the home's qualified name, the receiver's own source
/// text as its first operand, and each argument's text after it, in order.
pub fn callText(
    allocator: std.mem.Allocator,
    retirement: Retirement,
    receiver: []const u8,
    arguments: []const []const u8,
    names: []const ?[]const u8,
) std.mem.Allocator.Error![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    if (retirement.home.module) |module| writer.print("{s}.", .{module}) catch return error.OutOfMemory;
    writer.print("{s}(", .{retirement.home.function}) catch return error.OutOfMemory;
    if (retirement.home.writer) writer.writeAll("mut ") catch return error.OutOfMemory;
    // `bytes.join(parts, separator)` takes the method's receiver last; every
    // other home takes it first.
    if (!retirement.home.arguments_first) writer.writeAll(receiver) catch return error.OutOfMemory;
    for (arguments, 0..) |argument, index| {
        if (index != 0 or !retirement.home.arguments_first) writer.writeAll(", ") catch return error.OutOfMemory;
        // A call written with a keyword operand (`sort(reverse=True)`) keeps the
        // name in front of the value; the home takes the same operand by name.
        if (index < names.len) if (names[index]) |name| {
            writer.print("{s}=", .{name}) catch return error.OutOfMemory;
        };
        writer.writeAll(argument) catch return error.OutOfMemory;
    }
    if (retirement.home.arguments_first) {
        if (arguments.len != 0) writer.writeAll(", ") catch return error.OutOfMemory;
        writer.writeAll(receiver) catch return error.OutOfMemory;
    }
    writer.writeAll(")") catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

/// The comparison a retired search call is written inside: the operator's text,
/// the literal it is compared against, and the span the whole comparison covers.
pub const Comparison = struct {
    /// `==`, `!=`, `<`, `<=`, `>` or `>=`, written left to right.
    operator: []const u8,
    /// The integer literal's own text, `-1` included.
    literal: []const u8,
    /// The span from the comparison's first token through its last.
    span: source.Span,
};

/// The comparison one retired search call is an operand of, on either side, or
/// null when the call is not a comparison operand that can be rewritten whole.
/// A call inside a larger expression is not certain: rewriting only the
/// comparison would regroup the arithmetic around it, so those sites name the
/// convention and are migrated by hand (F57).
pub fn comparisonAround(bytes: []const u8, span: source.Span) ?Comparison {
    if (forwardComparison(bytes, span)) |comparison| return comparison;
    return backwardComparison(bytes, span);
}

/// The comparison written after the call: `x.find(y) OP literal`.
fn forwardComparison(bytes: []const u8, span: source.Span) ?Comparison {
    if (!startsOperand(bytes, span.start)) return null;
    const at = skipSpace(bytes, span.end);
    const operator = operatorAt(bytes, at) orelse return null;
    const literal = skipSpace(bytes, at + operator.len);
    const parsed = literalAt(bytes, literal) orelse return null;
    if (!endsOperand(bytes, parsed.end)) return null;
    return .{ .operator = operator, .literal = bytes[literal..parsed.end], .span = .{ .start = span.start, .end = parsed.end } };
}

/// The comparison written before the call: `literal OP x.find(y)`, whose
/// operator mirrors into the forward shape the repair table is written for.
fn backwardComparison(bytes: []const u8, span: source.Span) ?Comparison {
    if (!endsOperand(bytes, span.end)) return null;
    const at = skipSpaceBack(bytes, span.start);
    const operator = operatorEndingAt(bytes, at) orelse return null;
    const literal = literalEndingAt(bytes, at - operator.len) orelse return null;
    if (!startsOperand(bytes, literal.start)) return null;
    return .{ .operator = mirror(operator), .literal = bytes[literal.start..literal.end], .span = .{ .start = literal.start, .end = span.end } };
}

/// The repair text the comparison needs under one absence convention, or null
/// when §4a's table does not cover it. `call` is the replacement call's text.
pub fn absenceRepair(allocator: std.mem.Allocator, comparison: Comparison, call: []const u8) std.mem.Allocator.Error!?[]const u8 {
    const one = std.mem.eql(u8, comparison.literal, "-1");
    const zero = std.mem.eql(u8, comparison.literal, "0");
    const test_text: ?[]const u8 =
        if (one and std.mem.eql(u8, comparison.operator, "==")) "is None" //
        else if (one and std.mem.eql(u8, comparison.operator, "!=")) "is not None" //
        else if (one and std.mem.eql(u8, comparison.operator, "<=")) "is None" //
        else if (one and std.mem.eql(u8, comparison.operator, ">")) "is not None" //
        else if (zero and std.mem.eql(u8, comparison.operator, "<")) "is None" //
        else if (zero and std.mem.eql(u8, comparison.operator, ">=")) "is not None" //
        else null;
    if (test_text) |text| {
        const sentence = try std.fmt.allocPrint(allocator, "{s} {s}", .{ call, text });
        return sentence;
    }
    // A payload comparison is certain only for a non-negative literal;
    // `== -1` is the absence test above.
    if (std.mem.eql(u8, comparison.operator, "==") and !std.mem.startsWith(u8, comparison.literal, "-")) {
        const sentence = try std.fmt.allocPrint(allocator, "{s} == Some({s})", .{ call, comparison.literal });
        return sentence;
    }
    return null;
}

/// The operator written at `at`, longest first so `==` never reads as `=`.
fn operatorAt(bytes: []const u8, at: usize) ?[]const u8 {
    for ([_][]const u8{ "==", "!=", "<=", ">=", "<", ">" }) |operator| {
        if (std.mem.startsWith(u8, bytes[at..], operator)) return operator;
    }
    return null;
}

/// The operator ending at `end`, longest first as `operatorAt` reads it.
fn operatorEndingAt(bytes: []const u8, end: usize) ?[]const u8 {
    for ([_][]const u8{ "==", "!=", "<=", ">=", "<", ">" }) |operator| {
        if (end >= operator.len and std.mem.eql(u8, bytes[end - operator.len .. end], operator)) return operator;
    }
    return null;
}

/// The operator that means the same comparison with its operands swapped.
fn mirror(operator: []const u8) []const u8 {
    if (std.mem.eql(u8, operator, "<")) return ">";
    if (std.mem.eql(u8, operator, "<=")) return ">=";
    if (std.mem.eql(u8, operator, ">")) return "<";
    if (std.mem.eql(u8, operator, ">=")) return "<=";
    return operator;
}

/// One integer literal: an optional minus and at least one digit.
const Literal = struct { start: usize, end: usize };

/// The literal starting at `from`, or null when the byte there begins no
/// number.
fn literalAt(bytes: []const u8, from: usize) ?Literal {
    var at = from;
    if (at < bytes.len and bytes[at] == '-') at += 1;
    const digits = at;
    while (at < bytes.len and bytes[at] >= '0' and bytes[at] <= '9') at += 1;
    if (at == digits) return null;
    return .{ .start = from, .end = at };
}

/// The literal ending just before `end`, skipping spaces backwards.
fn literalEndingAt(bytes: []const u8, end: usize) ?Literal {
    var at = skipSpaceBack(bytes, end);
    const digits = at;
    while (at > 0 and bytes[at - 1] >= '0' and bytes[at - 1] <= '9') at -= 1;
    if (at == digits) return null;
    if (at > 0 and bytes[at - 1] == '-') at -= 1;
    return .{ .start = at, .end = digits };
}

/// Skip spaces and tabs forward, answering the next byte's index.
fn skipSpace(bytes: []const u8, from: usize) usize {
    var at = from;
    while (at < bytes.len) : (at += 1) switch (bytes[at]) {
        ' ', '\t', '\r' => {},
        else => break,
    };
    return at;
}

/// Skip spaces and tabs backwards, answering the index after them.
fn skipSpaceBack(bytes: []const u8, from: usize) usize {
    var at = from;
    while (at > 0) : (at -= 1) switch (bytes[at - 1]) {
        ' ', '\t', '\r' => {},
        else => break,
    };
    return at;
}

/// Whether a token can begin the comparison at `at`: the start of a statement,
/// inside a delimiter, or after a word that binds looser than a comparison.
fn startsOperand(bytes: []const u8, at: usize) bool {
    const before = skipSpaceBack(bytes, at);
    if (before == 0) return true;
    switch (bytes[before - 1]) {
        '(', '[', '{', ',', ':', '\n' => return true,
        // A single `=` is an assignment; a doubled one is already a comparison.
        '=' => return before < 2 or (bytes[before - 2] != '=' and bytes[before - 2] != '!' and bytes[before - 2] != '<' and bytes[before - 2] != '>'),
        else => {},
    }
    for ([_][]const u8{ "return", "assert", "and", "or", "not", "if", "elif", "while", "else" }) |word| {
        if (!std.mem.endsWith(u8, bytes[0..before], word)) continue;
        if (before == word.len or !wordByte(bytes[before - word.len - 1])) return true;
    }
    return false;
}

/// Whether the comparison can end at `end`: the end of a statement, a closing
/// delimiter, or a word that binds looser than a comparison.
fn endsOperand(bytes: []const u8, end: usize) bool {
    const at = skipSpace(bytes, end);
    if (at >= bytes.len) return true;
    switch (bytes[at]) {
        ')', ']', '}', ',', ':', '\n' => return true,
        else => {},
    }
    for ([_][]const u8{ "and", "or", "else", "if", "in", "not" }) |word| {
        if (!std.mem.startsWith(u8, bytes[at..], word)) continue;
        if (at + word.len == bytes.len or !wordByte(bytes[at + word.len])) return true;
    }
    return false;
}

/// Whether a byte continues an identifier.
fn wordByte(byte: u8) bool {
    return byte == '_' or (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9');
}

/// One stream method spelling and the stream-first function that replaces it
/// (F-s). `out.print(...)` and `out.write(...)` on a `Stream` receiver become
/// `print(out, ...)` and `write(out, ...)`, which take the stream by name (F18).
/// `flush` has no method spelling, so it has no row.
pub const StreamMethod = struct {
    /// The method spelling a caller writes today.
    method: []const u8,
    /// The stream-first function that replaces it.
    function: []const u8,
    /// The replacement's operand sketch, as the refusal's message writes it.
    operands: []const u8,
};

/// Every stream method spelling this family retires.
pub const stream_methods = [_]StreamMethod{
    .{ .method = "print", .function = "print", .operands = "out, value" },
    .{ .method = "write", .function = "write", .operands = "out, data" },
};

/// The stream spelling `method` names, or null when it keeps no method form.
pub fn streamMethod(method: []const u8) ?StreamMethod {
    for (stream_methods) |entry| {
        if (std.mem.eql(u8, entry.method, method)) return entry;
    }
    return null;
}

/// The one-line message for a stream spelling. `placed` says the call stands
/// alone on its line, so the rewrite is the certain repair; otherwise the message
/// names the statement form the author must write by hand.
pub fn streamMessage(allocator: std.mem.Allocator, method: StreamMethod, placed: bool) std.mem.Allocator.Error![]const u8 {
    if (!placed) return std.fmt.allocPrint(
        allocator,
        "`{s}()` is a function now; bind the stream to a name and write `{s}({s})` on its own line",
        .{ method.method, method.function, method.operands },
    );
    return std.fmt.allocPrint(allocator, "`{s}()` is a function now; write `{s}({s})`", .{ method.method, method.function, method.operands });
}

/// The stream-first replacement call: the function, the stream's own source text
/// as its first operand, and each argument's text after it, keyword names kept.
pub fn streamCallText(
    allocator: std.mem.Allocator,
    method: StreamMethod,
    stream: []const u8,
    arguments: []const []const u8,
    names: []const ?[]const u8,
) std.mem.Allocator.Error![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    writer.print("{s}({s}", .{ method.function, stream }) catch return error.OutOfMemory;
    for (arguments, 0..) |argument, index| {
        writer.writeAll(", ") catch return error.OutOfMemory;
        if (index < names.len) if (names[index]) |name| {
            writer.print("{s}=", .{name}) catch return error.OutOfMemory;
        };
        writer.writeAll(argument) catch return error.OutOfMemory;
    }
    writer.writeAll(")") catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

/// Whether a byte ends a comparison operator, so a `=` after it is not an assignment.
fn comparisonByte(byte: u8) bool {
    return byte == '=' or byte == '!' or byte == '<' or byte == '>';
}

/// The span a stream call is rewritten over when the call is a statement of its
/// own: the call alone on its line, or the call after an `_ =` discard, which
/// goes too because the stream-first function answers nothing. Null when the
/// call's value is used or it shares its line with other code, so no certain
/// repair exists.
pub fn statementSpan(bytes: []const u8, span: source.Span) ?source.Span {
    const after = skipSpace(bytes, span.end);
    if (after < bytes.len and bytes[after] != '\n' and bytes[after] != '\r' and bytes[after] != '#') return null;
    const before = skipSpaceBack(bytes, span.start);
    if (before == 0 or bytes[before - 1] == '\n') return span;
    // The discard is a single `=` written after `_`, never a comparison.
    if (bytes[before - 1] != '=') return null;
    if (before >= 2 and comparisonByte(bytes[before - 2])) return null;
    const name = skipSpaceBack(bytes, before - 1);
    if (name == 0 or bytes[name - 1] != '_') return null;
    if (name >= 2 and wordByte(bytes[name - 2])) return null;
    const line = skipSpaceBack(bytes, name - 1);
    if (line != 0 and bytes[line - 1] != '\n') return null;
    return .{ .start = name - 1, .end = span.end };
}

test "a retired spelling answers only its own family, name and argument count" {
    try std.testing.expect(find("upper", .string, 0) != null);
    try std.testing.expect(find("upper", .bytes, 0) == null);
    try std.testing.expect(find("upper", .string, 1) == null);
    try std.testing.expect(find("upper", .list, 0) == null);
    try std.testing.expect(find("strip", .string, 0) != null);
    try std.testing.expect(find("strip", .string, 1) == null);
    try std.testing.expect(find("replace", .string, 2) != null);
    try std.testing.expect(find("replace", .string, 1) == null);
    try std.testing.expect(find("split", .bytes, 1) != null);
    try std.testing.expect(find("split", .bytes, 0) == null);
    try std.testing.expect(find("join", .bytes, 1) != null);
    try std.testing.expect(find("find", .bytes, 2) == null);
    try std.testing.expect(find("join", .string, 1) == null);
}

test "a home answers its function name and operand count" {
    try std.testing.expect(home("strings", "starts_with", 2) != null);
    try std.testing.expect(std.mem.eql(u8, home("strings", "starts_with", 2).?.method, "startswith"));
    try std.testing.expect(home("strings", "starts_with", 1) == null);
    try std.testing.expect(home("strings", "split", 2) != null);
    try std.testing.expect(home("strings", "split", 1) == null);
    try std.testing.expect(home("bytes", "split", 2) != null);
    try std.testing.expect(home("bytes", "join", 2).?.home.arguments_first);
    try std.testing.expect(home("strings", "upper", 1) != null);
}

test "the message and the replacement name the home and keep the receiver text" {
    const retirement = find("upper", .string, 0).?;
    const sentence = try message(std.testing.allocator, retirement);
    defer std.testing.allocator.free(sentence);
    try std.testing.expectEqualStrings("`upper()` is a function now; write `strings.upper(value)`", sentence);
    const call = try callText(std.testing.allocator, retirement, "(text)", &.{}, &.{});
    defer std.testing.allocator.free(call);
    try std.testing.expectEqualStrings("strings.upper((text))", call);
    const join = find("join", .bytes, 1).?;
    const joined = try message(std.testing.allocator, join);
    defer std.testing.allocator.free(joined);
    try std.testing.expectEqualStrings("`join()` is a function now; write `bytes.join(parts, separator)`", joined);
    const join_call = try callText(std.testing.allocator, join, "separator", &.{"parts"}, &.{});
    defer std.testing.allocator.free(join_call);
    try std.testing.expectEqualStrings("bytes.join(parts, separator)", join_call);
}

test "a retired spelling leaves the receiver's accepted-method list" {
    try std.testing.expect(retires("upper", .string));
    try std.testing.expect(!retires("upper", .bytes));
    try std.testing.expect(retires("strip", .string));
    try std.testing.expect(retires("splitlines", .string));
    try std.testing.expect(retires("split", .string));
    try std.testing.expect(retires("find", .string));
    try std.testing.expect(retires("rfind", .string));
    try std.testing.expect(retires("append", .list));
    try std.testing.expect(retires("sort", .list));
    try std.testing.expect(retires("pop", .list));
    try std.testing.expect(retires("extend", .list));
    try std.testing.expect(retires("insert", .list));
    try std.testing.expect(retires("remove", .list));
    try std.testing.expect(retires("index", .list));
    try std.testing.expect(retires("clear", .list));
    try std.testing.expect(retires("reverse", .list));
    try std.testing.expect(!retires("exchange", .list));
    try std.testing.expect(retires("append", .bytes));
}

test "the list family answers its seven module words and their operand counts" {
    try std.testing.expectEqualStrings("lists", find("pop", .list, 0).?.home.module.?);
    try std.testing.expectEqualStrings("pop", find("pop", .list, 0).?.home.function);
    try std.testing.expectEqualStrings("pop_at", find("pop", .list, 1).?.home.function);
    try std.testing.expect(find("pop", .list, 2) == null);
    try std.testing.expectEqualStrings("index_of", find("index", .list, 1).?.home.function);
    try std.testing.expect(find("index", .list, 1).?.home.absence == .plain);
    try std.testing.expect(!find("index", .list, 1).?.home.writer);
    try std.testing.expectEqualStrings("extend", find("extend", .list, 1).?.home.function);
    try std.testing.expectEqualStrings("insert", find("insert", .list, 2).?.home.function);
    try std.testing.expectEqualStrings("remove", find("remove", .list, 1).?.home.function);
    try std.testing.expectEqualStrings("clear", find("clear", .list, 0).?.home.function);
    try std.testing.expectEqualStrings("reverse", find("reverse", .list, 0).?.home.function);
    try std.testing.expect(find("reverse", .list, 1) == null);
    // Each home is recognized back to the spelling it replaces, which is how the
    // function call lowers to the retired method's own operation.
    try std.testing.expectEqualStrings("pop", home("lists", "pop", 1).?.method);
    try std.testing.expectEqualStrings("pop", home("lists", "pop_at", 2).?.method);
    try std.testing.expectEqualStrings("index", home("lists", "index_of", 2).?.method);
    try std.testing.expect(home("lists", "remove", 2).?.home.writer);
    try std.testing.expect(home("lists", "clear", 1) != null);
    try std.testing.expect(home("lists", "index_of", 1) == null);
}

test "the dictionary family answers its dicts homes and operand counts" {
    try std.testing.expectEqualStrings("dicts", find("get", .dictionary, 2).?.home.module.?);
    try std.testing.expect(find("get", .dictionary, 1) == null);
    try std.testing.expectEqualStrings("pop", find("pop", .dictionary, 1).?.home.function);
    try std.testing.expectEqualStrings("pop_default", find("pop", .dictionary, 2).?.home.function);
    try std.testing.expect(find("pop", .dictionary, 0) == null);
    try std.testing.expect(find("clear", .dictionary, 0).?.home.writer);
    try std.testing.expect(find("setdefault", .dictionary, 2).?.home.writer);
    try std.testing.expect(find("update", .dictionary, 1).?.home.writer);
    try std.testing.expect(!find("keys", .dictionary, 0).?.home.writer);
    try std.testing.expect(find("keys", .dictionary, 1) == null);
    // Each dictionary home is recognized back to the spelling it replaces.
    try std.testing.expectEqualStrings("get", home("dicts", "get", 3).?.method);
    try std.testing.expectEqualStrings("pop", home("dicts", "pop", 2).?.method);
    try std.testing.expectEqualStrings("pop", home("dicts", "pop_default", 3).?.method);
    try std.testing.expect(home("dicts", "pop", 3) == null);
    try std.testing.expect(home("dicts", "keys", 1) != null);
    try std.testing.expect(!retires("get", .list));
}

test "a dictionary home's message and call keep the receiver and the operands" {
    const allocator = std.testing.allocator;
    const got = try message(allocator, find("get", .dictionary, 2).?);
    defer allocator.free(got);
    try std.testing.expectEqualStrings("`get()` is a function now; write `dicts.get(mapping, key, fallback)`", got);
    const popped = try message(allocator, find("pop", .dictionary, 2).?);
    defer allocator.free(popped);
    try std.testing.expectEqualStrings("`pop()` is a function now; write `dicts.pop_default(mut mapping, key, fallback)`", popped);
    const call = try callText(allocator, find("pop", .dictionary, 2).?, "counts", &.{ "\"a\"", "0" }, &.{});
    defer allocator.free(call);
    try std.testing.expectEqualStrings("dicts.pop_default(mut counts, \"a\", 0)", call);
    const keys = try callText(allocator, find("keys", .dictionary, 0).?, "counts", &.{}, &.{});
    defer allocator.free(keys);
    try std.testing.expectEqualStrings("dicts.keys(counts)", keys);
}

test "a writer's message names its marker and its operands" {
    const appended = try message(std.testing.allocator, find("append", .list, 1).?);
    defer std.testing.allocator.free(appended);
    try std.testing.expectEqualStrings("`append()` is a function now; write `append(mut value, item)`", appended);
    const popped = try message(std.testing.allocator, find("pop", .list, 1).?);
    defer std.testing.allocator.free(popped);
    try std.testing.expectEqualStrings("`pop()` is a function now; write `lists.pop_at(mut value, index)`", popped);
    const indexed = try message(std.testing.allocator, find("index", .list, 1).?);
    defer std.testing.allocator.free(indexed);
    try std.testing.expectEqualStrings("`index()` is a function now; write `lists.index_of(value, element)`", indexed);
    const swapped = try callText(std.testing.allocator, find("pop", .list, 1).?, "values", &.{"0"}, &.{});
    defer std.testing.allocator.free(swapped);
    try std.testing.expectEqualStrings("lists.pop_at(mut values, 0)", swapped);
    const cleared = try callText(std.testing.allocator, find("clear", .list, 0).?, "rows", &.{}, &.{});
    defer std.testing.allocator.free(cleared);
    try std.testing.expectEqualStrings("lists.clear(mut rows)", cleared);
    const at = try callText(std.testing.allocator, find("index", .list, 1).?, "rows", &.{"7"}, &.{});
    defer std.testing.allocator.free(at);
    try std.testing.expectEqualStrings("lists.index_of(rows, 7)", at);
}

/// The repair the first occurrence of `call` in `text` needs, computing its span
/// as the parser would.
fn repairOf(allocator: std.mem.Allocator, text: []const u8, call: []const u8, call_text: []const u8) !?[]const u8 {
    const start = std.mem.indexOf(u8, text, call).?;
    const comparison = comparisonAround(text, .{ .start = start, .end = start + call.len }) orelse return null;
    return absenceRepair(allocator, comparison, call_text);
}

test "the four text search words retire for one argument" {
    try std.testing.expect(find("find", .string, 1) != null);
    try std.testing.expect(find("find", .string, 0) == null);
    try std.testing.expect(find("rfind", .string, 1).?.home.absence == .option);
    try std.testing.expect(find("index", .string, 1).?.home.absence == .plain);
    try std.testing.expect(find("rindex", .string, 1) != null);
    try std.testing.expect(find("find", .bytes, 1).?.home.absence == .plain);
    try std.testing.expect(home("strings", "find", 2).?.home.absence == .option);
}

test "the absence repairs follow the F57 table" {
    const absent = try repairOf(std.testing.allocator, "if x.find(y) == -1:\n", "x.find(y)", "strings.find(x, y)");
    defer std.testing.allocator.free(absent.?);
    try std.testing.expectEqualStrings("strings.find(x, y) is None", absent.?);
    const present = try repairOf(std.testing.allocator, "if x.find(y) != -1:\n", "x.find(y)", "strings.find(x, y)");
    defer std.testing.allocator.free(present.?);
    try std.testing.expectEqualStrings("strings.find(x, y) is not None", present.?);
    const below = try repairOf(std.testing.allocator, "if x.find(y) < 0:\n", "x.find(y)", "strings.find(x, y)");
    defer std.testing.allocator.free(below.?);
    try std.testing.expectEqualStrings("strings.find(x, y) is None", below.?);
    const at_most = try repairOf(std.testing.allocator, "if x.find(y) <= -1:\n", "x.find(y)", "strings.find(x, y)");
    defer std.testing.allocator.free(at_most.?);
    try std.testing.expectEqualStrings("strings.find(x, y) is None", at_most.?);
    const above = try repairOf(std.testing.allocator, "if x.find(y) > -1:\n", "x.find(y)", "strings.find(x, y)");
    defer std.testing.allocator.free(above.?);
    try std.testing.expectEqualStrings("strings.find(x, y) is not None", above.?);
    const reached = try repairOf(std.testing.allocator, "if x.find(y) >= 0:\n", "x.find(y)", "strings.find(x, y)");
    defer std.testing.allocator.free(reached.?);
    try std.testing.expectEqualStrings("strings.find(x, y) is not None", reached.?);
    const payload = try repairOf(std.testing.allocator, "if x.find(y) == 3:\n", "x.find(y)", "strings.find(x, y)");
    defer std.testing.allocator.free(payload.?);
    try std.testing.expectEqualStrings("strings.find(x, y) == Some(3)", payload.?);
    const assigned = try repairOf(std.testing.allocator, "mut hit = x.find(y) == -1\n", "x.find(y)", "strings.find(x, y)");
    defer std.testing.allocator.free(assigned.?);
    try std.testing.expectEqualStrings("strings.find(x, y) is None", assigned.?);
}

test "a reversed comparison reads the mirror of its operator" {
    const absent = try repairOf(std.testing.allocator, "if -1 == x.find(y):\n", "x.find(y)", "strings.find(x, y)");
    defer std.testing.allocator.free(absent.?);
    try std.testing.expectEqualStrings("strings.find(x, y) is None", absent.?);
    const present = try repairOf(std.testing.allocator, "if -1 < x.find(y):\n", "x.find(y)", "strings.find(x, y)");
    defer std.testing.allocator.free(present.?);
    try std.testing.expectEqualStrings("strings.find(x, y) is not None", present.?);
    const below = try repairOf(std.testing.allocator, "if 0 > x.find(y):\n", "x.find(y)", "strings.find(x, y)");
    defer std.testing.allocator.free(below.?);
    try std.testing.expectEqualStrings("strings.find(x, y) is None", below.?);
    const payload = try repairOf(std.testing.allocator, "if 2 == x.find(y):\n", "x.find(y)", "strings.find(x, y)");
    defer std.testing.allocator.free(payload.?);
    try std.testing.expectEqualStrings("strings.find(x, y) == Some(2)", payload.?);
}

test "an unlisted shape withholds the repair" {
    try std.testing.expect(try repairOf(std.testing.allocator, "if x.find(y) != 0:\n", "x.find(y)", "strings.find(x, y)") == null);
    try std.testing.expect(try repairOf(std.testing.allocator, "if 1 + x.find(y) == -1:\n", "x.find(y)", "strings.find(x, y)") == null);
    try std.testing.expect(try repairOf(std.testing.allocator, "if x.find(y) == -1 == b:\n", "x.find(y)", "strings.find(x, y)") == null);
    try std.testing.expect(try repairOf(std.testing.allocator, "if x.find(y) == 2 + 3:\n", "x.find(y)", "strings.find(x, y)") == null);
    try std.testing.expect(try repairOf(std.testing.allocator, "mut g = x.find(y)\n", "x.find(y)", "strings.find(x, y)") == null);
    try std.testing.expect(try repairOf(std.testing.allocator, "if x.find(y) == n:\n", "x.find(y)", "strings.find(x, y)") == null);
}

test "the stream spellings are print and write, and flush has no method form" {
    try std.testing.expect(streamMethod("print") != null);
    try std.testing.expect(streamMethod("write") != null);
    try std.testing.expect(streamMethod("flush") == null);
    try std.testing.expect(streamMethod("upper") == null);
    try std.testing.expectEqualStrings("write", streamMethod("write").?.function);
}

test "a stream call's repair keeps the stream, every operand and its keyword" {
    const allocator = std.testing.allocator;
    const text = try streamCallText(allocator, streamMethod("print").?, "out", &.{ "1", "2", "\"-\"" }, &.{ null, null, "sep" });
    defer allocator.free(text);
    try std.testing.expectEqualStrings("print(out, 1, 2, sep=\"-\")", text);
    const bare = try streamCallText(allocator, streamMethod("print").?, "out", &.{}, &.{});
    defer allocator.free(bare);
    try std.testing.expectEqualStrings("print(out)", bare);
}

test "the message names the function, and an unplaced call names its statement form" {
    const allocator = std.testing.allocator;
    const placed = try streamMessage(allocator, streamMethod("write").?, true);
    defer allocator.free(placed);
    try std.testing.expectEqualStrings("`write()` is a function now; write `write(out, data)`", placed);
    const unplaced = try streamMessage(allocator, streamMethod("print").?, false);
    defer allocator.free(unplaced);
    try std.testing.expectEqualStrings("`print()` is a function now; bind the stream to a name and write `print(out, value)` on its own line", unplaced);
}

test "a statement call takes its discard; a used value or a shared line has no repair" {
    const sourceSpan = source.Span;
    // `_ = out.write("x")` on its own line: the discard goes with the call.
    const line = "    _ = out.write(\"x\")\n";
    const call = std.mem.indexOf(u8, line, "out.write").?;
    const span = sourceSpan{ .start = call, .end = line.len - 1 };
    const edit = statementSpan(line, span).?;
    try std.testing.expectEqualStrings("_ = out.write(\"x\")", line[edit.start..edit.end]);
    // A bare statement call is its own edit.
    const bare = "out.print(1)\n";
    try std.testing.expectEqual(@as(usize, 0), statementSpan(bare, sourceSpan{ .start = 0, .end = 12 }).?.start);
    // A value used on the right of `mut x =` or after `==` has no statement form.
    const used = "    mut x = out.write(\"x\")\n";
    const used_call = std.mem.indexOf(u8, used, "out.write").?;
    try std.testing.expect(statementSpan(used, sourceSpan{ .start = used_call, .end = used.len - 1 }) == null);
    const compared = "    _ == out.write(\"x\")\n";
    const compared_call = std.mem.indexOf(u8, compared, "out.write").?;
    try std.testing.expect(statementSpan(compared, sourceSpan{ .start = compared_call, .end = compared.len - 1 }) == null);
}

test "a set's add becomes sets.include for a lent value and stays sets.add for one the caller can give" {
    const add = findShaped("add", .dictionary, .set, 1).?;
    try std.testing.expectEqualStrings("include", forArgument(add, false).home.function);
    try std.testing.expectEqualStrings("add", forArgument(add, true).home.function);
    const named = try message(std.testing.allocator, forArgument(add, false));
    defer std.testing.allocator.free(named);
    try std.testing.expectEqualStrings("`add()` is a function now; write `sets.include(mut values, value)`", named);
    const discard = findShaped("discard", .dictionary, .set, 1).?;
    try std.testing.expectEqualStrings("discard", forArgument(discard, false).home.function);
}

test "a set answers its own rows, apart from a plain collection's, and a buffer answers its writes" {
    try std.testing.expect(findShaped("add", .dictionary, .set, 1) != null);
    try std.testing.expect(findShaped("add", .dictionary, .collection, 1) == null);
    try std.testing.expect(findShaped("update", .dictionary, .set, 1) == null);
    try std.testing.expect(findShaped("update", .dictionary, .collection, 1) != null);
    try std.testing.expect(findShaped("append_byte", .bytes, .buffer, 1) != null);
    try std.testing.expect(findShaped("append_byte", .bytes, .collection, 1) == null);
    try std.testing.expect(findShaped("find", .bytes, .collection, 1) != null);
}

test "a set's homes name their module functions and writers" {
    try std.testing.expectEqualStrings("issubset", home("sets", "subset", 2).?.method);
    try std.testing.expectEqualStrings("isdisjoint", home("sets", "disjoint", 2).?.method);
    try std.testing.expect(home("sets", "add", 2).?.home.writer);
    try std.testing.expect(!home("sets", "union", 2).?.home.writer);
    try std.testing.expect(home("sets", "union", 1) == null);
    try std.testing.expect(home("buffers", "reserve", 3) == null);
}

test "a buffer home answers its method's answer, and the always-true writes answer nothing" {
    try std.testing.expectEqual(Answer.flag, home("buffers", "append_byte", 2).?.answer);
    try std.testing.expectEqual(Answer.flag, home("buffers", "append_range", 4).?.answer);
    try std.testing.expectEqual(Answer.flag, home("buffers", "reserve", 2).?.answer);
    try std.testing.expectEqual(Answer.nothing, home("buffers", "append", 2).?.answer);
    try std.testing.expectEqual(Answer.nothing, home("buffers", "append_int", 2).?.answer);
    try std.testing.expectEqual(Answer.nothing, home("buffers", "append_float", 2).?.answer);
    try std.testing.expectEqual(Answer.nothing, home("buffers", "append_utf8", 2).?.answer);
    try std.testing.expect(home("buffers", "clear", 1) != null);
    try std.testing.expect(home("buffers", "clear", 2) == null);
    try std.testing.expect(home("buffers", "append_byte", 1) == null);
    try std.testing.expect(home("buffers", "append_array", 4) == null);
}

test "a buffer write is refused with its home, which is recognized" {
    try std.testing.expectEqualStrings("append_byte", findShaped("append_byte", .bytes, .buffer, 1).?.method);
    try std.testing.expect(findShaped("append_int", .bytes, .buffer, 1).?.answer == .nothing);
    try std.testing.expect(retires("append_range", .bytes));
    try std.testing.expect(home("buffers", "append_range", 4) != null);
}

test "a value use of a home that answers nothing is named as a statement" {
    const text = try nothingMessage(std.testing.allocator, findShaped("append_int", .bytes, .buffer, 1).?);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("`append_int()` answers nothing; write `buffers.append_int(mut data, value)` as a statement of its own", text);
}

test "a byte range word is refused with its bytes home and answers the method's range" {
    try std.testing.expect(find("parse_int_range", .bytes, 2) != null);
    try std.testing.expect(find("parse_int_range", .bytes, 1) == null);
    try std.testing.expectEqualStrings("scalar_count_range", home("bytes", "scalar_count_range", 3).?.method);
    try std.testing.expect(home("bytes", "parse_float_range", 3) != null);
    try std.testing.expect(find("view", .bytes, 2) == null);
}
