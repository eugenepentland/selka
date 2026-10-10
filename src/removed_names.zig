//! Canonical migration diagnostics for spellings removed from the language surface.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const Span = @import("source.zig").Span;

/// One removed spelling, its canonical successor, the migration message, and
/// the exact text that replaces the removed token when a plain rename is the
/// whole migration.
const Entry = struct { removed: []const u8, canonical: []const u8, message: []const u8, fix: ?[]const u8 = null };

const entries = [_]Entry{
    .{ .removed = "push", .canonical = "append", .message = "`push` was removed; use `append(value)`", .fix = "append" },
    .{ .removed = "len", .canonical = "len(", .message = "`.len()` was removed; use `len(value)`" },
    .{ .removed = "contains", .canonical = "in", .message = "`.contains(key)` was removed for dictionaries; use `key in mapping`" },
    .{ .removed = "List", .canonical = "list[", .message = "`List[T]` was removed; use `list[T]`", .fix = "list" },
    .{ .removed = "filesystem_cap", .canonical = "Filesystem", .message = "`filesystem_cap` was removed; use the `Filesystem` capability type", .fix = "Filesystem" },
    .{ .removed = "network_cap", .canonical = "Network", .message = "`network_cap` was removed; use the `Network` capability type", .fix = "Network" },
    .{ .removed = "clock_cap", .canonical = "Clock", .message = "`clock_cap` was removed; use the `Clock` capability type", .fix = "Clock" },
    .{ .removed = "random_cap", .canonical = "Entropy", .message = "`random_cap` was removed; use the `Entropy` capability type", .fix = "Entropy" },
    .{ .removed = "environment_cap", .canonical = "Environment", .message = "`environment_cap` was removed; use the `Environment` capability type", .fix = "Environment" },
    .{ .removed = "codec_encode", .canonical = "domain codec API", .message = "`codec_encode` was removed; use the documented domain codec API" },
    .{ .removed = "codec_decode", .canonical = "domain codec API", .message = "`codec_decode` was removed; use the documented domain codec API" },
    .{ .removed = "f64_add", .canonical = "float", .message = "`f64_add` was removed; use `float` values and `+`" },
    .{ .removed = "f64_sub", .canonical = "float", .message = "`f64_sub` was removed; use `float` values and `-`" },
    .{ .removed = "f64_mul", .canonical = "float", .message = "`f64_mul` was removed; use `float` values and `*`" },
    .{ .removed = "f64_div", .canonical = "float", .message = "`f64_div` was removed; use `float` values and `/`" },
    .{ .removed = "f64_eq", .canonical = "float", .message = "`f64_eq` was removed; compare `float` values with `==`" },
    .{ .removed = "f64_lt", .canonical = "float", .message = "`f64_lt` was removed; compare `float` values with `<`" },
    .{ .removed = "f64_le", .canonical = "float", .message = "`f64_le` was removed; compare `float` values with `<=`" },
    .{ .removed = "f64_sqrt", .canonical = "sqrt", .message = "`f64_sqrt` was removed; use `sqrt` with a `float` value", .fix = "sqrt" },
    .{ .removed = "f64_floor", .canonical = "floor", .message = "`f64_floor` was removed; use `floor` with a `float` value", .fix = "floor" },
    .{ .removed = "f64_ceil", .canonical = "ceil", .message = "`f64_ceil` was removed; use `ceil` with a `float` value", .fix = "ceil" },
    .{ .removed = "f64_trunc", .canonical = "trunc", .message = "`f64_trunc` was removed; use `trunc` with a `float` value", .fix = "trunc" },
    .{ .removed = "f64_abs", .canonical = "abs", .message = "`f64_abs` was removed; use `abs` with a `float` value", .fix = "abs" },
    .{ .removed = "f64_neg", .canonical = "float", .message = "`f64_neg` was removed; negate a `float` value with `-`" },
    .{ .removed = "f64_from_u64", .canonical = "float", .message = "`f64_from_u64` was removed; convert an integer with `float(value)`" },
    .{ .removed = "f64_to_u64", .canonical = "int", .message = "`f64_to_u64` was removed; convert a `float` value with `int(value)`" },
    .{ .removed = "&", .canonical = "mut", .message = "`&` was removed; write `mut value`" },
    .{ .removed = "=>", .canonical = "", .message = "`=>` was removed and has no replacement" },
};

/// Removed spelling -> position in `entries`, built once at compile time so the
/// lexer's per-identifier check is one map probe rather than a scan of every entry.
const entry_index = std.StaticStringMap(usize).initComptime(indexPairs());
fn indexPairs() [entries.len]struct { []const u8, usize } {
    var pairs: [entries.len]struct { []const u8, usize } = undefined;
    for (entries, 0..) |entry, index| pairs[index] = .{ entry.removed, index };
    return pairs;
}

/// Return migration metadata for one exact removed spelling.
fn lookup(spelling: []const u8) ?Entry {
    const index = entry_index.get(spelling) orelse return null;
    return entries[index];
}

/// Reject one exact removed spelling at its source location, or report that it
/// is current. A spelling whose migration is a plain rename carries the
/// replacement as the diagnostic's fix.
pub fn reject(sink: *diagnostic.Sink, span: Span, spelling: []const u8) diagnostic.Error!bool {
    const entry = lookup(spelling) orelse return false;
    if (entry.fix) |text| return sink.failFix(removed_code, span, entry.message, .{ .span = span, .text = text });
    return sink.fail(removed_code, span, entry.message);
}

/// Reject the removed `&` call-argument marker. `bytes` is the whole source and
/// `span` the `&`; the fix rewrites it to `mut ` only where it stands where an
/// argument begins — after `(` or `,` and directly before a name — because that
/// is the one place `&value` was ever accepted.
pub fn rejectMarker(sink: *diagnostic.Sink, bytes: []const u8, span: Span) diagnostic.Error!bool {
    const entry = lookup("&").?;
    var before = span.start;
    while (before > 0 and (bytes[before - 1] == ' ' or bytes[before - 1] == '\t')) before -= 1;
    const opens = before > 0 and (bytes[before - 1] == '(' or bytes[before - 1] == ',');
    const names = span.end < bytes.len and (std.ascii.isAlphabetic(bytes[span.end]) or bytes[span.end] == '_');
    if (opens and names) return sink.failFix(removed_code, span, entry.message, .{ .span = span, .text = "mut " });
    return sink.fail(removed_code, span, entry.message);
}

const removed_code = "E_REMOVED_SPELLING";
/// The diagnostic code every removed spelling reports.
pub const code = removed_code;

/// Whether `rejectLexical` would reject this spelling.
pub fn removedLexically(spelling: []const u8) bool {
    if (entry_index.get(spelling) == null) return false;
    inline for (.{ "push", "len", "contains", "List" }) |contextual| {
        if (std.mem.eql(u8, spelling, contextual)) return false;
    }
    return true;
}

/// Reject names removed at tokenization while leaving contextual type and member names to later layers.
pub fn rejectLexical(sink: *diagnostic.Sink, span: Span, spelling: []const u8) diagnostic.Error!bool {
    // Nearly every identifier is not a removed spelling; answer those with one probe.
    if (!removedLexically(spelling)) return false;
    return reject(sink, span, spelling);
}
