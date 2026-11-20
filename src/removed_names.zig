//! Canonical migration diagnostics for spellings removed from the language surface.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const Span = @import("source.zig").Span;

/// One removed spelling, its canonical successor, the migration message, and
/// the exact text that replaces the removed token when a plain rename is the
/// whole migration.
/// `lexical` is false for a word the language has unreserved: it is an ordinary
/// identifier everywhere, and only an *unresolved use* of its spelling reports
/// this migration (wave 2 batch 0, DECISIONS F7).
/// `example` is a whole program that uses the replacement the message advises
/// (empty when the message names none): `src/advice_tables_test.zig` requires
/// it to check, and requires every backquoted fragment after the message's
/// first `; ` to occur in it, so advice and program cannot drift apart.
pub const Entry = struct {
    /// The removed spelling, as the lexer or checker meets it.
    removed: []const u8,
    /// The spelling that replaces it, for readers of the table.
    canonical: []const u8,
    /// The one-line migration message, whose text after its first `; ` is the advice.
    message: []const u8,
    /// The exact text a plain rename writes in place of the token, when one is certain.
    fix: ?[]const u8 = null,
    /// Whether the lexer rejects the word everywhere (false: only an unresolved use does).
    lexical: bool = true,
    /// A whole program that uses the advised replacement; empty when the message names none.
    example: []const u8 = "",
};

const push_example =
    \\func main() -> int:
    \\    mut xs: int[] = []
    \\    const value = 1
    \\    append(mut xs, value)
    \\    return len(xs)
    \\
;
const len_example =
    \\func main() -> int:
    \\    const value = [1, 2]
    \\    return len(value)
    \\
;
const contains_example =
    \\import lists
    \\
    \\
    \\func main() -> int:
    \\    const value = 1
    \\    const container: set[int] = {1}
    \\    const values: int[] = [1]
    \\    if value in container and lists.contains(values, value):
    \\        return 1
    \\    return 0
    \\
;
const list_example =
    \\func main() -> int:
    \\    const items: int[] = []
    \\    return len(items)
    \\
;
/// One program per capability type: the capability is stored in a record, which uses it.
fn capabilityExample(comptime name: []const u8) []const u8 {
    return "record Holder:\n    cap: " ++ name ++ "\n\nfunc main(handle: " ++ name ++ ") -> int:\n    _ = Holder(cap=handle)\n    return 0\n";
}
const encode_example =
    \\import base64
    \\import hex
    \\
    \\func main() -> int:
    \\    const raw = b"abc"
    \\    const text = base64.b64encode(raw)
    \\    const digits = hex.encode(raw)
    \\    return len(text) + len(digits)
    \\
;
const decode_example =
    \\import base64
    \\import hex
    \\
    \\func decoded(raw: bytes, digits: str) -> int fails str:
    \\    const first = try base64.b64decode(raw)
    \\    const second = try hex.decode(digits)
    \\    return len(first) + len(second)
    \\
    \\func main() -> int:
    \\    match decoded(b"YWJj", "616263"):
    \\        case Ok(total):
    \\            return total
    \\        case Err(_):
    \\            return 1
    \\
;
const float_operator_example =
    \\func main() -> int:
    \\    const a: float = 1.5
    \\    const b: float = 2.5
    \\    const sum = a + b
    \\    const difference = a - b
    \\    const product = a * b
    \\    const quotient = a / b
    \\    const negated = -a
    \\    if a == b or a < b or a <= b:
    \\        return 1
    \\    return int(sum + difference + product + quotient + negated)
    \\
;
const float_function_example =
    \\func main() -> int:
    \\    const x: float = 4.5
    \\    const roots = sqrt(x)
    \\    const rounded = floor(x) + ceil(x) + trunc(x) + abs(x)
    \\    return int(roots + rounded)
    \\
;
const float_from_integer_example =
    \\func main() -> int:
    \\    const value = 3
    \\    const x: float = float(value)
    \\    return int(x)
    \\
;
const float_to_integer_example =
    \\func main() -> int:
    \\    const value: float = 2.5
    \\    return int(value)
    \\
;
const marker_example =
    \\func bump(mut value: int[]) -> int:
    \\    append(mut value, 1)
    \\    return len(value)
    \\
    \\func main() -> int:
    \\    mut value: int[] = []
    \\    return bump(mut value)
    \\
;
const and_example =
    \\func main() -> int:
    \\    const a = True
    \\    const b = False
    \\    if a and b:
    \\        return 1
    \\    return 0
    \\
;
const or_example =
    \\func main() -> int:
    \\    const a = True
    \\    const b = False
    \\    if a or b:
    \\        return 1
    \\    return 0
    \\
;
const bit_not_example =
    \\func main() -> int:
    \\    const value = 5
    \\    return bit_not(value)
    \\
;
const not_example =
    \\func main() -> int:
    \\    const a = True
    \\    if not a:
    \\        return 1
    \\    return 0
    \\
;

/// Every removed spelling, in lookup order. `&&`, `||`, `!` and `~` are never
/// identifiers: the lexer asks for them by their punctuation.
pub const entries = [_]Entry{
    .{ .removed = "push", .canonical = "append", .message = "`push` was removed; use `append(mut xs, value)`", .fix = "append", .example = push_example },
    .{ .removed = "len", .canonical = "len(", .message = "`.len()` was removed; use `len(value)`", .example = len_example },
    .{ .removed = "contains", .canonical = "in", .message = "`.contains(value)` was removed; use `value in container` for a dictionary, a set, text or bytes, and `lists.contains(values, value)` for a list", .example = contains_example },
    .{ .removed = "List", .canonical = "T[]", .message = "`List[int]` was removed; write the element type and brackets, as in `int[]`", .example = list_example },
    .{ .removed = "filesystem_cap", .canonical = "Filesystem", .message = "`filesystem_cap` was removed; use the `Filesystem` capability type", .fix = "Filesystem", .lexical = false, .example = capabilityExample("Filesystem") },
    .{ .removed = "network_cap", .canonical = "Network", .message = "`network_cap` was removed; use the `Network` capability type", .fix = "Network", .lexical = false, .example = capabilityExample("Network") },
    .{ .removed = "clock_cap", .canonical = "Clock", .message = "`clock_cap` was removed; use the `Clock` capability type", .fix = "Clock", .lexical = false, .example = capabilityExample("Clock") },
    .{ .removed = "random_cap", .canonical = "Entropy", .message = "`random_cap` was removed; use the `Entropy` capability type", .fix = "Entropy", .lexical = false, .example = capabilityExample("Entropy") },
    .{ .removed = "environment_cap", .canonical = "Environment", .message = "`environment_cap` was removed; use the `Environment` capability type", .fix = "Environment", .lexical = false, .example = capabilityExample("Environment") },
    .{ .removed = "codec_encode", .canonical = "base64", .message = "`codec_encode` was removed; encode with `base64.b64encode` for base64 or `hex.encode` for hex", .lexical = false, .example = encode_example },
    .{ .removed = "codec_decode", .canonical = "base64", .message = "`codec_decode` was removed; decode with `base64.b64decode` for base64 or `hex.decode` for hex", .lexical = false, .example = decode_example },
    .{ .removed = "f64_add", .canonical = "float", .message = "`f64_add` was removed; use `float` values and `+`", .lexical = false, .example = float_operator_example },
    .{ .removed = "f64_sub", .canonical = "float", .message = "`f64_sub` was removed; use `float` values and `-`", .lexical = false, .example = float_operator_example },
    .{ .removed = "f64_mul", .canonical = "float", .message = "`f64_mul` was removed; use `float` values and `*`", .lexical = false, .example = float_operator_example },
    .{ .removed = "f64_div", .canonical = "float", .message = "`f64_div` was removed; use `float` values and `/`", .lexical = false, .example = float_operator_example },
    .{ .removed = "f64_eq", .canonical = "float", .message = "`f64_eq` was removed; compare `float` values with `==`", .lexical = false, .example = float_operator_example },
    .{ .removed = "f64_lt", .canonical = "float", .message = "`f64_lt` was removed; compare `float` values with `<`", .lexical = false, .example = float_operator_example },
    .{ .removed = "f64_le", .canonical = "float", .message = "`f64_le` was removed; compare `float` values with `<=`", .lexical = false, .example = float_operator_example },
    .{ .removed = "f64_sqrt", .canonical = "sqrt", .message = "`f64_sqrt` was removed; use `sqrt` with a `float` value", .fix = "sqrt", .lexical = false, .example = float_function_example },
    .{ .removed = "f64_floor", .canonical = "floor", .message = "`f64_floor` was removed; use `floor` with a `float` value", .fix = "floor", .lexical = false, .example = float_function_example },
    .{ .removed = "f64_ceil", .canonical = "ceil", .message = "`f64_ceil` was removed; use `ceil` with a `float` value", .fix = "ceil", .lexical = false, .example = float_function_example },
    .{ .removed = "f64_trunc", .canonical = "trunc", .message = "`f64_trunc` was removed; use `trunc` with a `float` value", .fix = "trunc", .lexical = false, .example = float_function_example },
    .{ .removed = "f64_abs", .canonical = "abs", .message = "`f64_abs` was removed; use `abs` with a `float` value", .fix = "abs", .lexical = false, .example = float_function_example },
    .{ .removed = "f64_neg", .canonical = "float", .message = "`f64_neg` was removed; negate a `float` value with `-`", .lexical = false, .example = float_operator_example },
    .{ .removed = "f64_from_u64", .canonical = "float", .message = "`f64_from_u64` was removed; convert an integer with `float(value)`", .lexical = false, .example = float_from_integer_example },
    .{ .removed = "f64_to_u64", .canonical = "int", .message = "`f64_to_u64` was removed; convert a `float` value with `int(value)`", .lexical = false, .example = float_to_integer_example },
    .{ .removed = "&", .canonical = "mut", .message = "`&` before an argument was removed; write `mut` before it, as in `mut value`", .example = marker_example },
    .{ .removed = "&&", .canonical = "and", .message = "`&&` is not an operator; write `and`", .example = and_example },
    .{ .removed = "||", .canonical = "or", .message = "`||` is not an operator; write `or`", .example = or_example },
    .{ .removed = "!", .canonical = "not", .message = "`!` is not an operator; write `not`", .example = not_example },
    .{ .removed = "~", .canonical = "bit_not", .message = "`~` is not an operator; write `bit_not(value)`", .example = bit_not_example },
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
    return rejectUnless(sink, span, spelling, false);
}

/// The replacement text of a removed spelling's plain rename, or null when it has
/// none, so a use-site refusal can ask whether the edit would capture a name this
/// file declares (FIX-MIGRATION-CAPTURE-1).
pub fn replacement(spelling: []const u8) ?[]const u8 {
    const entry = lookup(spelling) orelse return null;
    return entry.fix;
}

/// Reject a removed spelling, withholding its edit when `withheld` says the rename
/// would name a declaration or binding of this file.
pub fn rejectUnless(sink: *diagnostic.Sink, span: Span, spelling: []const u8, withheld: bool) diagnostic.Error!bool {
    const entry = lookup(spelling) orelse return false;
    if (entry.fix) |text| if (!withheld) return sink.failFix(removed_code, span, entry.message, .{ .span = span, .text = text });
    const message = if (withheld) blk: {
        const fix = entry.fix orelse break :blk entry.message;
        break :blk try std.fmt.allocPrint(sink.allocator, "{s}; this file declares or binds `{s}`, so rename the call by hand", .{ entry.message, fix });
    } else entry.message;
    return sink.fail(removed_code, span, message);
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
    const entry = lookup(spelling) orelse return false;
    if (!entry.lexical) return false;
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
