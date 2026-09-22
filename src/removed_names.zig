//! Canonical migration diagnostics for spellings removed from the language surface.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const Span = @import("source.zig").Span;

const Entry = struct { removed: []const u8, canonical: []const u8, message: []const u8 };

const entries = [_]Entry{
    .{ .removed = "push", .canonical = "append", .message = "`push` was removed; use `append(value)`" },
    .{ .removed = "len", .canonical = "len(", .message = "`.len()` was removed; use `len(value)`" },
    .{ .removed = "contains", .canonical = "in", .message = "`.contains(key)` was removed for dictionaries; use `key in mapping`" },
    .{ .removed = "List", .canonical = "list[", .message = "`List[T]` was removed; use `list[T]`" },
    .{ .removed = "filesystem_cap", .canonical = "Filesystem", .message = "`filesystem_cap` was removed; use the `Filesystem` capability type" },
    .{ .removed = "network_cap", .canonical = "Network", .message = "`network_cap` was removed; use the `Network` capability type" },
    .{ .removed = "clock_cap", .canonical = "Clock", .message = "`clock_cap` was removed; use the `Clock` capability type" },
    .{ .removed = "random_cap", .canonical = "Entropy", .message = "`random_cap` was removed; use the `Entropy` capability type" },
    .{ .removed = "environment_cap", .canonical = "Environment", .message = "`environment_cap` was removed; use the `Environment` capability type" },
    .{ .removed = "codec_encode", .canonical = "domain codec API", .message = "`codec_encode` was removed; use the documented domain codec API" },
    .{ .removed = "codec_decode", .canonical = "domain codec API", .message = "`codec_decode` was removed; use the documented domain codec API" },
    .{ .removed = "f64_add", .canonical = "float", .message = "`f64_add` was removed; use `float` values and `+`" },
    .{ .removed = "f64_sub", .canonical = "float", .message = "`f64_sub` was removed; use `float` values and `-`" },
    .{ .removed = "f64_mul", .canonical = "float", .message = "`f64_mul` was removed; use `float` values and `*`" },
    .{ .removed = "f64_div", .canonical = "float", .message = "`f64_div` was removed; use `float` values and `/`" },
    .{ .removed = "f64_eq", .canonical = "float", .message = "`f64_eq` was removed; compare `float` values with `==`" },
    .{ .removed = "f64_lt", .canonical = "float", .message = "`f64_lt` was removed; compare `float` values with `<`" },
    .{ .removed = "f64_le", .canonical = "float", .message = "`f64_le` was removed; compare `float` values with `<=`" },
    .{ .removed = "f64_sqrt", .canonical = "sqrt", .message = "`f64_sqrt` was removed; use `sqrt` with a `float` value" },
    .{ .removed = "f64_floor", .canonical = "floor", .message = "`f64_floor` was removed; use `floor` with a `float` value" },
    .{ .removed = "f64_ceil", .canonical = "ceil", .message = "`f64_ceil` was removed; use `ceil` with a `float` value" },
    .{ .removed = "f64_trunc", .canonical = "trunc", .message = "`f64_trunc` was removed; use `trunc` with a `float` value" },
    .{ .removed = "f64_abs", .canonical = "abs", .message = "`f64_abs` was removed; use `abs` with a `float` value" },
    .{ .removed = "f64_neg", .canonical = "float", .message = "`f64_neg` was removed; negate a `float` value with `-`" },
    .{ .removed = "f64_from_u64", .canonical = "float", .message = "`f64_from_u64` was removed; convert an integer with `float(value)`" },
    .{ .removed = "f64_to_u64", .canonical = "int", .message = "`f64_to_u64` was removed; convert a `float` value with `int(value)`" },
    .{ .removed = "&", .canonical = "mut", .message = "`&` was removed; write `mut value`" },
    .{ .removed = "=>", .canonical = "", .message = "`=>` was removed and has no replacement" },
};

/// Return migration metadata for one exact removed spelling.
fn lookup(spelling: []const u8) ?Entry {
    for (entries) |entry| if (std.mem.eql(u8, spelling, entry.removed)) return entry;
    return null;
}

/// Reject one exact removed spelling at its source location, or report that it is current.
pub fn reject(sink: *diagnostic.Sink, span: Span, spelling: []const u8) diagnostic.Error!bool {
    const entry = lookup(spelling) orelse return false;
    return sink.fail("E_REMOVED_SPELLING", span, entry.message);
}

/// Reject names removed at tokenization while leaving contextual type and member names to later layers.
pub fn rejectLexical(sink: *diagnostic.Sink, span: Span, spelling: []const u8) diagnostic.Error!bool {
    inline for (.{ "push", "len", "contains", "List" }) |contextual| {
        if (std.mem.eql(u8, spelling, contextual)) return false;
    }
    return reject(sink, span, spelling);
}
