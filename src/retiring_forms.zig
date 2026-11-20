//! The spellings W13 removed (W13, slices 2 and 5): a refusal that carries the certain rewrite, so one `selka fix`
//! moves a project across.
//!
//! - `E_METHOD_REMOVED`, the retired methods' own code: a method on text, bytes, the byte buffer, a list or a set whose
//!   function home exists, `text.encode()` for `strings.encode(text)`. The rows are `retired_methods.method_homes`, the
//!   rows of `method_forms` below, and for a `byte_buffer` receiver every `bytes` read whose home lends it the buffer.
//! - `E_REMOVED_SPELLING`, the code of a retired spelling that is not a method (`push` for `append`): a second spelling
//!   of an operation: the bare `unwrap_or(x, d)` (the method stays, W13-Q1), `math.min`, `max`, `sqrt`, `abs`,
//!   `round`, `floor`, `ceil` and `trunc` (W13-Q2, W13-Q2b: a zero result keeps its sign in the prelude's forms, which
//!   the message says), `strings.to_int` and `to_float` (`strings.starts_with_at` stays: it is no duplicate, W13-Q3b)
//!   and the 32 bare file functions (`exists(fs, p)` is `fs.exists(p)`, W13-Q7).
//! - `E_INTERNAL_NAME`: the standard library's three channels, `run_process`, `process_control` and `stop_control`,
//!   which only the library may call (W13-Q6), as only it may write the intrinsics.
//!
//! The checker reports a refusal and keeps checking the body, so one check reports every site of a function and one
//! round of `selka fix` rewrites them all; the function fails when its body is done (`sema.checkInstance`). No waiver
//! excuses one: a `# lint: allow method-form` comment names a rule nothing reads. The standard library's own sources
//! are refused as any program is (W13, slice 3); only the channel refusal skips the library (`librarySource`), since the
//! channels are the library's own, and a module's own call of its function (`math.floor`'s `trunc(value)`) is no second
//! spelling (`sema_calls.warnDuplicateSpelling`).
const std = @import("std");
const source = @import("source.zig");
const retired_methods = @import("retired_methods.zig");
const diagnostic = @import("diagnostic.zig");
const ManagedKind = @import("runtime_values.zig").ManagedKind;

/// A method spelling whose function home exists: the retired methods' code.
pub const method_code = retired_methods.code;
/// A second spelling of an operation that is not a method: the code of every retired spelling that is not a method.
pub const duplicate_code = "E_REMOVED_SPELLING";
/// A call of one of the standard library's channels outside the library: the code of the library's other reserved names.
pub const channel_code = "E_INTERNAL_NAME";

/// What the float twins' refusal adds: the one way the prelude's form differs. `math.round`, `floor`, `ceil` and
/// `trunc` answer `0.0` where the prelude's forms answer `-0.0` for a negative input that rounds to zero; the user
/// retired them with that difference stated (W13-Q2b, 15 November).
const zero_sign = "a result of zero keeps its sign, so `round(-0.4)` is `-0.0` where `math.round(-0.4)` was `0.0`: the two compare equal and print differently";

/// The method spellings refused here although their home is not the method's own lowering (`retired_methods.method_forms`).
pub const method_forms = retired_methods.method_forms;

/// The row a method spelling is refused with on a receiver of `family` and `shape`, or null when it keeps its method. A
/// `byte_buffer` receiver also takes every `bytes` row whose home lends it the buffer (W13-Q5), the rows retired on
/// `bytes` included (`buf.find(x)` is `bytes.find(buf, x)`).
pub fn methodForm(method: []const u8, family: ManagedKind, shape: retired_methods.Shape, arguments: usize) ?retired_methods.Retirement {
    inline for (.{ &retired_methods.method_homes, &method_forms, &retired_methods.retirements }, 0..) |table, index| for (table) |row| {
        if (row.family != family or row.arguments != arguments or !std.mem.eql(u8, row.method, method)) continue;
        const lent = shape == .buffer and retired_methods.lendsBuffer(row);
        // A retired row is asked here only for the buffer it lends; on its own shape it is refused before this is asked.
        if (index == 2) {
            if (lent) return row;
            continue;
        }
        if (row.shape == shape or lent) return row;
    };
    return null;
}

/// How a duplicate's rewrite is written.
pub const Repair = enum {
    /// The callee's name becomes the prelude function's, `math.sqrt(x)` as `sqrt(x)`.
    prelude,
    /// As `prelude`, but `math.min[T](a, b)` drops its type argument only when both operands have type `T` on their
    /// own: a literal takes `T` from the call, and the prelude's `min` would read it as an `int` (W13-Q2).
    typed_prelude,
    /// No edit: the message says why.
    none,
};

/// One function that is a second spelling of an operation: where it is declared, what replaces it and how.
pub const Duplicate = struct {
    /// The standard module that declares it.
    module: []const u8,
    /// Its name there.
    function: []const u8,
    /// The spelling that stays.
    home: []const u8,
    repair: Repair,
    /// Why there is no edit, for `repair == .none`.
    reason: []const u8 = "",
    /// A difference the rewrite makes that the message states, for a row with an edit.
    note: []const u8 = "",
};

/// The module functions W13 removed.
pub const duplicates = [_]Duplicate{
    .{ .module = "math", .function = "min", .home = "min", .repair = .typed_prelude },
    .{ .module = "math", .function = "max", .home = "max", .repair = .typed_prelude },
    .{ .module = "math", .function = "sqrt", .home = "sqrt", .repair = .prelude },
    .{ .module = "math", .function = "abs", .home = "abs", .repair = .none, .reason = "`math.abs` fails on the most negative `int` and `abs` does not, so the failure's handling goes with it by hand" },
    .{ .module = "strings", .function = "to_int", .home = "parse_int", .repair = .prelude },
    .{ .module = "strings", .function = "to_float", .home = "parse_float", .repair = .prelude },
    .{ .module = "math", .function = "round", .home = "round", .repair = .prelude, .note = zero_sign },
    .{ .module = "math", .function = "floor", .home = "floor", .repair = .prelude, .note = zero_sign },
    .{ .module = "math", .function = "ceil", .home = "ceil", .repair = .prelude, .note = zero_sign },
    .{ .module = "math", .function = "trunc", .home = "trunc", .repair = .prelude, .note = zero_sign },
};

/// The duplicate row for `module.function`, or null.
pub fn duplicate(module: []const u8, function: []const u8) ?Duplicate {
    for (duplicates) |row| {
        if (std.mem.eql(u8, row.module, module) and std.mem.eql(u8, row.function, function)) return row;
    }
    return null;
}

/// The longest replacement a message quotes in full; a longer one is named by its function and operand sketch.
const quoted_limit = 72;

/// The message of a method form: the replacement this program would write, and, when there is no edit, why.
pub fn methodMessage(allocator: std.mem.Allocator, row: retired_methods.Retirement, replacement: ?[]const u8, reason: ?[]const u8) std.mem.Allocator.Error![]const u8 {
    const module = row.home.module orelse "";
    const dot: []const u8 = if (row.home.module != null) "." else "";
    const written = if (replacement) |text| if (text.len <= quoted_limit and std.mem.indexOfScalar(u8, text, '\n') == null) text else null else null;
    const call = if (written) |text|
        try allocator.dupe(u8, text)
    else
        try std.fmt.allocPrint(allocator, "{s}{s}{s}({s})", .{ module, dot, row.home.function, if (row.home.operands.len != 0) row.home.operands else if (row.home.writer) "mut value" else "value" });
    const absence: []const u8 = if (row.home.absence == .option) " (it answers `int?`: test absence with `is None`)" else "";
    if (reason) |why| return std.fmt.allocPrint(allocator, "`{s}()` is a function now; write `{s}`{s}; {s}", .{ row.method, call, absence, why });
    return std.fmt.allocPrint(allocator, "`{s}()` is a function now; write `{s}`{s}", .{ row.method, call, absence });
}

/// The message of a duplicate spelling: the call to write, and, when there is no edit, why.
pub fn duplicateMessage(allocator: std.mem.Allocator, written: []const u8, replacement: []const u8, reason: ?[]const u8) std.mem.Allocator.Error![]const u8 {
    return noteMessage(allocator, written, replacement, reason, "");
}

/// `duplicateMessage` with a difference the rewrite makes stated after it (`Duplicate.note`).
pub fn noteMessage(allocator: std.mem.Allocator, written: []const u8, replacement: []const u8, reason: ?[]const u8, note: []const u8) std.mem.Allocator.Error![]const u8 {
    if (note.len != 0) {
        const plain = try noteMessage(allocator, written, replacement, reason, "");
        defer allocator.free(plain);
        return std.fmt.allocPrint(allocator, "{s}; {s}", .{ plain, note });
    }
    const quoted = replacement.len <= quoted_limit and std.mem.indexOfScalar(u8, replacement, '\n') == null;
    if (reason) |why| {
        if (!quoted) return std.fmt.allocPrint(allocator, "`{s}` is a second spelling and was removed; {s}", .{ written, why });
        return std.fmt.allocPrint(allocator, "`{s}` is a second spelling and was removed; write `{s}`; {s}", .{ written, replacement, why });
    }
    if (!quoted) return std.fmt.allocPrint(allocator, "`{s}` is a second spelling and was removed; `selka fix` writes the one that stays", .{written});
    return std.fmt.allocPrint(allocator, "`{s}` is a second spelling and was removed; write `{s}`", .{ written, replacement });
}

/// The message for a call of one of the standard library's channels outside the library (W13-Q6).
pub fn channelMessage(allocator: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "`{s}` is the standard library's own channel, which only the library may call; use the `process` module's functions", .{name});
}

/// Note a refused site in `sink.file_reads` before its message and repair are decided: what the refusal says
/// (`fileNames`, the import its edit adds, a prelude name the file declares) reads the file beyond the declaration the
/// site is in, so no store may key such a function by its own region (FX13). Every site is reported, the standard
/// library's own sources included (W13-S3); no waiver excuses one.
pub fn reported(sink: *diagnostic.Sink, span: source.Span) std.mem.Allocator.Error!void {
    try sink.file_reads.append(sink.allocator, span);
}

/// Whether `span` is written in one of the compiler's own standard-library sources: a unit marked trusted, or one whose
/// path names an embedded module (`@stdlib/strings.selka`). Only the channel warning asks: the library's own calls of its
/// channels are what the channels are for (W13-Q6). Unlike `standard_library.trusted` it compares no bytes, so a check
/// that meets the library's channel calls in every program pays for a path comparison only.
pub fn librarySource(src: source.Source, span: source.Span) bool {
    if (src.trusted_intrinsics) return true;
    if (src.origins.len == 0) return libraryPath(src.path);
    const original = src.originalSpan(span) catch return false;
    const unit = src.origins[original.input].original;
    return unit.trusted_intrinsics or libraryPath(unit.path);
}

fn libraryPath(path: []const u8) bool {
    const prefix = "@stdlib/";
    if (!std.mem.startsWith(u8, path, prefix)) return false;
    return @import("standard_library.zig").source(path[prefix.len..]) != null;
}

/// Append one refusal with its repair, once: a site the checker reads twice (a generic function's instances, a receiver
/// two dispatch paths see) reports one. The checker keeps checking past it, as past a missing `mut` marker, and the
/// function fails when its body is done, so one check reports every site of a function.
pub fn append(sink: *diagnostic.Sink, code: []const u8, span: source.Span, message: []const u8, fix: ?diagnostic.Fix) std.mem.Allocator.Error!void {
    var item: diagnostic.Diagnostic = .{ .severity = .err, .code = code, .span = span, .message = message };
    item.provenance.fix = fix;
    if (diagnostic.holds(sink.items.items, item)) return;
    try sink.items.append(sink.allocator, item);
}

/// Whether an operand's text is a pure read whose place in a call cannot change what runs first: a name or a field
/// chain of one, or a one-line text or bytes literal, escapes included (`"\n".join(lines)`, W13-S5).
pub fn pureText(text: []const u8) bool {
    if (text.len == 0) return false;
    if (std.mem.indexOfScalar(u8, text, '\n') != null) return false;
    const body = if (text[0] == 'b' and text.len > 1 and (text[1] == '"' or text[1] == '\'')) text[1..] else text;
    if (body[0] == '"' or body[0] == '\'') return oneLiteral(body);
    if (std.ascii.isDigit(body[0])) return false;
    for (body) |byte| if (!wordByte(byte) and byte != '.') return false;
    return true;
}

/// Whether `body` is one quoted literal and nothing more: its first closing quote, past any escape, is its last byte.
fn oneLiteral(body: []const u8) bool {
    var at: usize = 1;
    while (at < body.len) : (at += 1) {
        if (body[at] == '\\') {
            at += 1;
            continue;
        }
        if (body[at] == body[0]) return at == body.len - 1;
    }
    return false;
}

/// The bytes of the file `span` is written in, and where they start in `src`.
const File = struct { bytes: []const u8, start: usize };

fn fileOf(src: source.Source, span: source.Span) File {
    if (src.origins.len == 0) return .{ .bytes = src.bytes, .start = 0 };
    const original = src.originalSpan(span) catch return .{ .bytes = src.bytes, .start = 0 };
    const origin = src.origins[original.input];
    return .{ .bytes = origin.original.bytes, .start = origin.start };
}

/// Whether the file `span` is written in names `word` as an identifier of its own outside comments and text: a local,
/// parameter or field of that name. Adding `import word` to such a file would make the name hide the module
/// (`E_SHADOWING`), so a rewrite that needs the import is withheld. A use after a `.` (a field or method) is not one.
pub fn fileNames(src: source.Source, span: source.Span, word: []const u8) bool {
    // `bytes` is also a builtin type, which no binding may hide, so every use of the word is the type or the module.
    if (std.mem.eql(u8, word, "bytes")) return false;
    const bytes = fileOf(src, span).bytes;
    var at: usize = 0;
    while (at < bytes.len) {
        const byte = bytes[at];
        if (byte == '#') {
            at = std.mem.indexOfScalarPos(u8, bytes, at, '\n') orelse bytes.len;
            continue;
        }
        if (byte == '"' or byte == '\'') {
            at = textEnd(bytes, at);
            continue;
        }
        if (!wordByte(byte)) {
            at += 1;
            continue;
        }
        const begin = at;
        while (at < bytes.len and wordByte(bytes[at])) at += 1;
        // A prefixed literal (`b"..."`, `f'...'`) is text, not a name.
        if (at < bytes.len and (bytes[at] == '"' or bytes[at] == '\'') and at - begin <= 2) continue;
        if (!std.mem.eql(u8, bytes[begin..at], word)) continue;
        if (begin > 0 and bytes[begin - 1] == '.') continue;
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, bytes[at..], " \t"), ".")) continue;
        if (importLine(bytes, begin)) continue;
        return true;
    }
    return false;
}

/// Whether the identifier at `at` is the module of an `import` line (`import strings`, `import strings as s`).
fn importLine(bytes: []const u8, at: usize) bool {
    const line = if (std.mem.lastIndexOfScalar(u8, bytes[0..at], '\n')) |found| found + 1 else 0;
    return std.mem.startsWith(u8, std.mem.trimStart(u8, bytes[line..at], " \t"), "import ");
}

/// The offset just past the text literal that opens at `at`, triple quotes and escapes included.
fn textEnd(bytes: []const u8, at: usize) usize {
    const quote = bytes[at];
    const triple = at + 2 < bytes.len and bytes[at + 1] == quote and bytes[at + 2] == quote;
    var cursor = at + if (triple) @as(usize, 3) else 1;
    while (cursor < bytes.len) : (cursor += 1) {
        const byte = bytes[cursor];
        if (byte == '\\') {
            cursor += 1;
            continue;
        }
        if (!triple and byte == '\n') return cursor;
        if (byte != quote) continue;
        if (!triple) return cursor + 1;
        if (cursor + 2 < bytes.len and bytes[cursor + 1] == quote and bytes[cursor + 2] == quote) return cursor + 3;
    }
    return bytes.len;
}

fn wordByte(byte: u8) bool {
    return byte == '_' or std.ascii.isAlphanumeric(byte);
}

/// Whether an operand's own text holds an integer literal that takes its type from the call it is written in: one with
/// no type suffix (`3`, not `3u64`, which carries its own type; W13-S5).
pub fn holdsIntegerLiteral(text: []const u8) bool {
    var at: usize = 0;
    // A literal inside brackets is an index or a slice bound (`xs[0]`), which takes no type from the call.
    var depth: usize = 0;
    while (at < text.len) : (at += 1) {
        if (text[at] == '[') depth += 1;
        if (text[at] == ']' and depth > 0) depth -= 1;
        if (depth != 0 or !std.ascii.isDigit(text[at])) continue;
        if (at != 0 and wordByte(text[at - 1])) continue;
        var end = at;
        while (end < text.len and (std.ascii.isDigit(text[end]) or text[end] == '_')) end += 1;
        if (end < text.len and (text[end] == 'u' or text[end] == 'i') and integerSuffix(text[end..])) {
            at = end;
            continue;
        }
        return true;
    }
    return false;
}

/// Whether `text` starts with an integer type suffix (`u8` to `u64`, `i8` to `i64`) that ends the literal.
fn integerSuffix(text: []const u8) bool {
    inline for (.{ "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64" }) |suffix| {
        if (std.mem.startsWith(u8, text, suffix) and (text.len == suffix.len or !wordByte(text[suffix.len]))) return true;
    }
    return false;
}

/// Whether an operand's whole text is one plain decimal integer literal with no suffix, which a rewrite can give the
/// call's integer type as a suffix (`math.min[u8](x, 3)` is `min(x, 3u8)`).
pub fn plainIntegerLiteral(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |byte| if (!std.ascii.isDigit(byte) and byte != '_') return false;
    return true;
}

/// Whether `name` is an integer type a literal suffix can spell.
pub fn suffixType(name: []const u8) bool {
    return integerSuffix(name) and name.len <= 3;
}

test "a buffer receiver takes the bytes rows its home lends it" {
    try std.testing.expect(methodForm("find", .bytes, .buffer, 1) != null);
    try std.testing.expect(methodForm("find", .bytes, .collection, 1) == null);
    try std.testing.expect(methodForm("encode", .string, .collection, 0) != null);
    try std.testing.expect(methodForm("join", .bytes, .buffer, 1) == null);
    try std.testing.expect(methodForm("exchange", .list, .collection, 2) != null);
    try std.testing.expect(methodForm("clear", .dictionary, .set, 0) != null);
    try std.testing.expect(methodForm("clear", .dictionary, .collection, 0) == null);
}

test "a file names a module only as an identifier of its own" {
    const src: source.Source = .{ .path = "a.selka", .line_starts = &.{}, .bytes = "import hex\n# hex digits\nconst text = \"hex\"\nconst x = b.hex()\n" };
    try std.testing.expect(!fileNames(src, .{ .start = 0, .end = 0 }, "hex"));
    const bound: source.Source = .{ .path = "b.selka", .line_starts = &.{}, .bytes = "func f(hex: str) -> str:\n    return hex\n" };
    try std.testing.expect(fileNames(bound, .{ .start = 0, .end = 0 }, "hex"));
    try std.testing.expect(holdsIntegerLiteral("x + 1"));
    try std.testing.expect(!holdsIntegerLiteral("row.x1"));
    try std.testing.expect(!holdsIntegerLiteral("5u64"));
    try std.testing.expect(holdsIntegerLiteral("5u64 + 2"));
    try std.testing.expect(!holdsIntegerLiteral("xs[0]") and holdsIntegerLiteral("xs[0] + 1"));
    try std.testing.expect(plainIntegerLiteral("1_000"));
    try std.testing.expect(!plainIntegerLiteral("0 - 1"));
    try std.testing.expect(suffixType("u8") and !suffixType("int") and !suffixType("u8x"));
    try std.testing.expect(pureText("\"\\n\"") and pureText("b\"\\x00\"") and !pureText("\"a\" + \"b\"") and !pureText("\"\\\""));
}

test "strings.starts_with_at is no duplicate and is not refused (W13-Q3b)" {
    try std.testing.expect(duplicate("strings", "starts_with_at") == null);
    try std.testing.expect(duplicate("strings", "to_int") != null);
}

test "the float twins are refused and say that a zero keeps its sign" {
    try std.testing.expect(duplicate("math", "round") != null);
    try std.testing.expect(duplicate("math", "trunc").?.note.len != 0);
    try std.testing.expect(duplicate("math", "sqrt").?.note.len == 0);
    const message = try noteMessage(std.testing.allocator, "math.round", "round(x)", null, duplicate("math", "floor").?.note);
    defer std.testing.allocator.free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "was removed; write `round(x)`; a result of zero keeps its sign") != null);
}

test "the channel refusal's library test reads the path of an embedded module" {
    try std.testing.expect(libraryPath("@stdlib/strings.selka"));
    try std.testing.expect(!libraryPath("@stdlib/no_such_module.selka"));
    try std.testing.expect(!libraryPath("src/strings.selka"));
}

test "the standard library keeps no method spelling and no W13 waiver (W13-S3)" {
    // `strings.find` and `strings.rfind` answer `int?` and convert the bounded search's `-1`, which their private homes
    // `find_offset` and `rfind_offset` answer (`retired_methods.library_homes`); no library source needs a waiver.
    var waived_methods: usize = 0;
    var waived_duplicates: usize = 0;
    const library = @import("standard_library.zig");
    for (library.paths) |path| {
        const text = library.source(path).?;
        waived_methods += std.mem.count(u8, text, "method-form");
        waived_duplicates += std.mem.count(u8, text, "duplicate-spelling");
    }
    try std.testing.expectEqual(@as(usize, 0), waived_methods);
    try std.testing.expectEqual(@as(usize, 0), waived_duplicates);
    const strings = library.source("strings.selka").?;
    try std.testing.expect(std.mem.indexOf(u8, strings, "    mut offset = find_offset(text, needle, start, end)") != null);
    try std.testing.expect(std.mem.indexOf(u8, strings, "    mut offset = rfind_offset(text, needle, start, end)") != null);
}
