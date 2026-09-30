//! Exact C ABI signatures of the runtime helpers a unit calls (LLVM-ZIG-1).
//!
//! Types are LLVM source types, not QBE's pointer-width spellings. A curated
//! table covers the benchmark closure; every other `myl_native_*`/`myl_qbe_*`
//! helper is read from the runtime header that declares it, or from the Zig
//! `@export` that defines it, in the bundled runtime tree. A helper found in
//! neither refuses translation rather than receiving a guessed declaration.
const std = @import("std");
const il = @import("qbe_build_llvm_il.zig");

const Allocator = std.mem.Allocator;

/// One helper's parameter and result types in LLVM spelling.
pub const Signature = struct { parameters: []const []const u8, result: []const u8 };

const P = "ptr";
const i64_type = "i64";
const i32_type = "i32";
const V = "void";

/// A curated entry: a helper's name and its signature.
const Entry = struct { name: []const u8, signature: Signature };

fn entry(name: []const u8, parameters: []const []const u8, result: []const u8) Entry {
    return .{ .name = name, .signature = .{ .parameters = parameters, .result = result } };
}

/// The frozen closure's curated manifest; it stays the authority for
/// everything it covers.
const curated = [_]Entry{
    entry("myl_native_bytes_concat", &.{ P, P, P }, P),
    entry("myl_native_bytes_encode", &.{ P, P }, P),
    entry("myl_native_bytes_find", &.{ P, P }, i64_type),
    entry("myl_native_bytes_join", &.{ P, P, P }, P),
    entry("myl_native_bytes_slice", &.{ P, P, i64_type, i64_type }, P),
    entry("myl_native_bytes_split_whitespace", &.{ P, P }, P),
    entry("myl_native_equal", &.{ P, P, P }, i32_type),
    entry("myl_native_fail_text_scalar", &.{P}, V),
    entry("myl_native_heap_alloc", &.{ P, P, i64_type }, P),
    entry("myl_native_list_append", &.{ P, P, P }, i32_type),
    entry("myl_native_list_clear", &.{P}, i32_type),
    entry("myl_native_list_get", &.{ P, i64_type, P }, i32_type),
    entry("myl_native_list_new", &.{ P, P, i64_type }, P),
    entry("myl_native_number_parse", &.{ P, i64_type, i32_type, P }, i32_type),
    entry("myl_native_text_at", &.{ P, P, i64_type }, P),
    entry("myl_native_text_chr", &.{ P, P, i64_type }, P),
    entry("myl_native_text_concat", &.{ P, P, P }, P),
    entry("myl_native_text_edge", &.{ P, P, i32_type }, i32_type),
    entry("myl_native_text_every", &.{ P, i32_type }, i32_type),
    entry("myl_native_text_find", &.{ P, P }, i64_type),
    entry("myl_native_text_join", &.{ P, P, P }, P),
    entry("myl_native_text_ord", &.{P}, i64_type),
    entry("myl_native_text_scalar", &.{ P, P, i32_type }, P),
    entry("myl_native_text_slice", &.{ P, P, i64_type, i64_type }, P),
    entry("myl_native_text_tail", &.{ P, P, i64_type, i64_type }, P),
    entry("myl_native_text_split_whitespace", &.{ P, P }, P),
    entry("myl_qbe_bytes_decode_range", &.{ P, P, i64_type, i64_type, P }, i32_type),
    entry("myl_qbe_bytes_decode", &.{ P, P, P }, i32_type),
    entry("myl_qbe_bytes_from_list", &.{ P, P }, P),
    entry("myl_qbe_dir_resource", &.{ P, i64_type, P, i64_type }, i64_type),
    entry("myl_qbe_fail_allocation", &.{P}, V),
    entry("myl_qbe_fail_assert", &.{P}, V),
    entry("myl_qbe_fail_cast", &.{ P, i64_type, i64_type }, V),
    entry("myl_qbe_fail_empty_separator", &.{P}, V),
    entry("myl_qbe_fail_division", &.{ P, i64_type, i64_type, i64_type }, V),
    entry("myl_qbe_fail_equality", &.{ P, i32_type }, V),
    entry("myl_qbe_fail_frame", &.{P}, V),
    entry("myl_qbe_fail_frame_allocation", &.{P}, V),
    entry("myl_qbe_fail_index_bounds", &.{ P, i64_type, i64_type }, V),
    entry("myl_qbe_fail_iteration", &.{P}, V),
    entry("myl_qbe_fail_list_capacity", &.{P}, V),
    entry("myl_qbe_fail_normalized_index_bounds", &.{ P, i64_type, i64_type }, V),
    entry("myl_qbe_fail_overflow_op", &.{ P, i64_type, i64_type, i64_type, i64_type }, V),
    entry("myl_qbe_fail_step", &.{P}, V),
    entry("myl_qbe_fail_text_bounds_detail", &.{ P, i64_type, i64_type }, V),
    entry("myl_qbe_file_access", &.{ P, i64_type, i32_type, P, P, P }, i32_type),
    entry("myl_qbe_float_unary", &.{ P, i64_type, i64_type }, i64_type),
    entry("myl_qbe_float_integer", &.{ P, i64_type, i64_type }, i64_type),
    entry("myl_qbe_frame_allocate", &.{ P, i64_type }, P),
    entry("myl_qbe_frame_try_allocate", &.{ P, i64_type }, P),
    entry("myl_qbe_frame_release", &.{ P, P }, V),
    entry("myl_qbe_heap", &.{P}, P),
    entry("myl_qbe_host_resource", &.{ P, i64_type, P, i64_type }, i64_type),
    entry("myl_qbe_int_neg", &.{ P, i64_type, i64_type, i64_type }, i64_type),
    entry("myl_qbe_int_binary", &.{ P, i64_type, i64_type, i64_type, i64_type, i64_type }, i64_type),
    entry("myl_qbe_print_byte", &.{ P, i32_type }, V),
    entry("myl_qbe_require_frame_accounting", &.{P}, V),
    entry("myl_qbe_require_step_accounting", &.{P}, V),
    entry("myl_qbe_root_mark", &.{P}, P),
    entry("myl_qbe_stream_begin", &.{ P, i64_type }, P),
    entry("myl_qbe_stream_finish", &.{ P, P, i64_type }, V),
    entry("myl_qbe_stream_write", &.{ P, i64_type, P }, i64_type),
    entry("myl_qbe_stream_write_bytes", &.{ P, i64_type, P }, i64_type),
};

/// The declaration attributes a helper's C definition proves: `myl_qbe_heap`
/// computes an address and touches no memory, and the error return trace
/// recorders are cold.
pub fn attributes(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "myl_qbe_heap")) return "memory(none) nounwind willreturn";
    // ERROR-TRACE-1: an error return trace recorder runs only on an error path.
    if (traceRecorder(name) or preservingRecorder(name)) return "cold nounwind";
    return "";
}

/// ERROR-TRACE-5: the call-site attribute that makes LLVM's inliner count a
/// call as free. Every error return trace recorder call carries it, so
/// recording never tips a function over the inliner's threshold.
pub const free_call = "\"call-inline-cost\"=\"0\"";

/// Whether `name` is one of the runtime's error return trace recorders.
pub fn traceRecorder(name: []const u8) bool {
    return std.mem.eql(u8, name, "myl_qbe_error_trace_origin") or std.mem.eql(u8, name, "myl_qbe_error_trace_append");
}

/// ERROR-TRACE-6: the runtime symbol a call to `name` in the IL is
/// translated into. A trace recorder call goes to its `preserve_most` twin
/// (`qbe_runtime.h`), which keeps every general-purpose register but r11, so
/// the caller keeps its live values in registers across the recording; every
/// other call keeps its symbol.
pub fn translatedCallee(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "myl_qbe_error_trace_origin")) return "myl_qbe_error_trace_origin_preserve_most";
    if (std.mem.eql(u8, name, "myl_qbe_error_trace_append")) return "myl_qbe_error_trace_append_preserve_most";
    return name;
}

/// ERROR-TRACE-6: the calling convention a runtime symbol's C definition
/// declares, spelled as LLVM writes it before a declaration's or a call's
/// result type (with its trailing space), or "" for the C convention.
pub fn callingConvention(name: []const u8) []const u8 {
    if (preservingRecorder(name)) return "preserve_mostcc ";
    return "";
}

/// Whether `name` is the `preserve_most` twin of a trace recorder.
fn preservingRecorder(name: []const u8) bool {
    return std.mem.eql(u8, name, "myl_qbe_error_trace_origin_preserve_most") or std.mem.eql(u8, name, "myl_qbe_error_trace_append_preserve_most");
}

/// One file of the bundled runtime tree's top level.
pub const Source = struct { name: []const u8, bytes: []const u8 };

/// The helper signatures a build can declare: the curated table, the fixed
/// generated shapes, and every helper read from the runtime tree.
pub const Table = struct {
    generated: std.StringHashMapUnmanaged(Signature) = .empty,

    /// Read every header's declarations, then every Zig `@export`, from the
    /// runtime tree's top-level files in name order; the first reading of a
    /// name wins.
    pub fn read(arena: Allocator, sources: []const Source) il.Error!Table {
        var table: Table = .{};
        for (sources) |source| {
            if (!std.mem.endsWith(u8, source.name, ".h")) continue;
            try readHeader(arena, &table.generated, source.bytes);
        }
        for (sources) |source| {
            if (!std.mem.endsWith(u8, source.name, ".zig")) continue;
            if (std.mem.indexOf(u8, source.bytes, "@export") == null) continue;
            try readZigExports(arena, &table.generated, source.bytes);
        }
        return table;
    }

    /// The exact signature of one runtime symbol, or null when none is known.
    pub fn signature(self: *const Table, name: []const u8) ?Signature {
        for (curated) |known| if (std.mem.eql(u8, known.name, name)) return known.signature;
        if (std.mem.startsWith(u8, name, "myl_r_")) return .{ .parameters = &.{ P, P, i32_type }, .result = V };
        if (hostBoundary(name)) return .{ .parameters = &.{ P, P, P }, .result = V };
        return self.generated.get(name);
    }
};

/// `myl_f_[0-9a-f]{64}_host`: the C boundary `qbe_build_host.zig` emits for
/// every copied host call.
fn hostBoundary(name: []const u8) bool {
    const prefix = "myl_f_";
    const suffix = "_host";
    if (name.len != prefix.len + 64 + suffix.len) return false;
    if (!std.mem.startsWith(u8, name, prefix) or !std.mem.endsWith(u8, name, suffix)) return false;
    for (name[prefix.len .. prefix.len + 64]) |c| if (!std.ascii.isDigit(c) and (c < 'a' or c > 'f')) return false;
    return true;
}

/// A runtime helper must have a checked C signature; never infer one from IL.
pub fn isHelper(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "myl_native_") or std.mem.startsWith(u8, name, "myl_qbe_") or std.mem.startsWith(u8, name, "myl_rc_");
}

// ---------------------------------------------------------------------------
// C headers
// ---------------------------------------------------------------------------

/// `text` with every `/* ... */` comment, then every `// ...` comment, replaced by a space.
fn withoutComments(arena: Allocator, text: []const u8) il.Error![]const u8 {
    var blocks: std.ArrayList(u8) = .empty;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, text, at, "/*")) |open| {
        const close = std.mem.indexOfPos(u8, text, open + 2, "*/") orelse break;
        try blocks.appendSlice(arena, text[at..open]);
        try blocks.append(arena, ' ');
        at = close + 2;
    }
    try blocks.appendSlice(arena, text[at..]);
    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, blocks.items, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try out.append(arena, '\n');
        first = false;
        if (std.mem.indexOf(u8, line, "//")) |comment| {
            try out.appendSlice(arena, line[0..comment]);
            try out.append(arena, ' ');
        } else try out.appendSlice(arena, line);
    }
    return out.items;
}

/// One declaration the header pattern found: where its line starts, its name and its parameters.
const Declaration = struct { start: usize, name_start: usize, name: []const u8, parameters: []const u8, end: usize };

/// Every declaration of the form `TYPE NAME(PARAMETERS);` starting a line,
/// found the way `(?m)^[A-Za-z_][^\n;{}#]*?\b(\w+)\s*\(([^;{}]*?)\)\s*;` scans.
fn readHeader(arena: Allocator, table: *std.StringHashMapUnmanaged(Signature), raw: []const u8) il.Error!void {
    const text = try withoutComments(arena, raw);
    var at: usize = 0;
    while (at < text.len) {
        const line_start = at == 0 or text[at - 1] == '\n';
        if (line_start) if (declarationAt(text, at)) |found| {
            try record(arena, table, text, found);
            at = found.end;
            continue;
        };
        at += 1;
    }
}

fn record(arena: Allocator, table: *std.StringHashMapUnmanaged(Signature), text: []const u8, found: Declaration) il.Error!void {
    if (!isHelper(found.name)) return;
    const result_words = try il.words(arena, text[found.start..found.name_start]);
    const result = cType(if (result_words.len == 0) "void" else result_words[result_words.len - 1], false) orelse return;
    const parameters = (try cParameters(arena, found.parameters)) orelse return;
    const slot = try table.getOrPut(arena, found.name);
    if (!slot.found_existing) slot.value_ptr.* = .{ .parameters = parameters, .result = result };
}

fn declarationAt(text: []const u8, start: usize) ?Declaration {
    if (!std.ascii.isAlphabetic(text[start]) and text[start] != '_') return null;
    var name_start = start + 1;
    while (name_start <= text.len) : (name_start += 1) {
        if (name_start > start + 1 and std.mem.indexOfScalar(u8, "\n;{}#", text[name_start - 1]) != null) return null;
        if (name_start == text.len) return null;
        if (nameAt(text, start, name_start)) |found| return found;
    }
    return null;
}

/// `\b(\w+)\s*\(([^;{}]*?)\)\s*;` at `at`, for a line starting at `start`.
fn nameAt(text: []const u8, start: usize, at: usize) ?Declaration {
    if (!il.isWord(text[at]) or il.isWord(text[at - 1])) return null;
    var end = at;
    while (end < text.len and il.isWord(text[end])) end += 1;
    var open = end;
    while (open < text.len and il.isSpace(text[open])) open += 1;
    if (open >= text.len or text[open] != '(') return null;
    var close = open + 1;
    while (close < text.len) : (close += 1) {
        const c = text[close];
        if (c == ';' or c == '{' or c == '}') return null;
        if (c != ')') continue;
        var semicolon = close + 1;
        while (semicolon < text.len and il.isSpace(text[semicolon])) semicolon += 1;
        if (semicolon < text.len and text[semicolon] == ';') {
            return .{ .start = start, .name_start = at, .name = text[at..end], .parameters = text[open + 1 .. close], .end = semicolon + 1 };
        }
    }
    return null;
}

/// Whitespace runs collapsed to one space, and the ends stripped.
fn normalized(arena: Allocator, text: []const u8) il.Error![]const u8 {
    return std.mem.join(arena, " ", try il.words(arena, text));
}

/// One C parameter or result type in LLVM spelling, or null when unknown.
fn cType(text: []const u8, pointer: bool) ?[]const u8 {
    if (pointer or std.mem.endsWith(u8, text, "*")) return P;
    const table = [_][2][]const u8{
        .{ "void", V },                 .{ "float", "float" },           .{ "double", "double" },
        .{ "int", i32_type },           .{ "unsigned", i32_type },       .{ "unsigned int", i32_type },
        .{ "int32_t", i32_type },       .{ "uint32_t", i32_type },       .{ "size_t", i64_type },
        .{ "int64_t", i64_type },       .{ "uint64_t", i64_type },       .{ "long", i64_type },
        .{ "unsigned long", i64_type }, .{ "long long", i64_type },      .{ "unsigned long long", i64_type },
        .{ "char", i32_type },          .{ "signed char", i32_type },    .{ "unsigned char", i32_type },
        .{ "short", i32_type },         .{ "unsigned short", i32_type }, .{ "int16_t", i32_type },
        .{ "uint16_t", i32_type },      .{ "myl_rc_status", i32_type },  .{ "myl_rc_transfer", i32_type },
    };
    for (table) |row| if (std.mem.eql(u8, row[0], text)) return row[1];
    return null;
}

/// A C parameter list's types, or null when any one is unknown.
fn cParameters(arena: Allocator, raw: []const u8) il.Error!?[]const []const u8 {
    const text = try normalized(arena, raw);
    if (text.len == 0 or std.mem.eql(u8, text, "void")) return &.{};
    var parts: std.ArrayList([]const u8) = .empty;
    var depth: i32 = 0;
    var begin: usize = 0;
    for (text, 0..) |c, index| {
        if (c == '(') depth += 1;
        if (c == ')') depth -= 1;
        if (c == ',' and depth == 0) {
            try parts.append(arena, text[begin..index]);
            begin = index + 1;
        }
    }
    try parts.append(arena, text[begin..]);
    const out = try arena.alloc([]const u8, parts.items.len);
    for (parts.items, out) |part, *slot| {
        var piece = il.strip(part);
        if (std.mem.endsWith(u8, piece, "[]")) piece = il.strip(piece[0 .. piece.len - 2]);
        var tokens = try il.words(arena, piece);
        if (tokens.len > 1) tokens = tokens[0 .. tokens.len - 1];
        const pointer = std.mem.indexOfScalar(u8, piece, '*') != null;
        slot.* = cType(try std.mem.join(arena, " ", tokens), pointer) orelse return null;
    }
    return out;
}

// ---------------------------------------------------------------------------
// Zig exports
// ---------------------------------------------------------------------------

/// Every `@export(&function, .{ .name = "symbol" ...` of one Zig file whose
/// declaration uses only C-ABI scalar and pointer types.
fn readZigExports(arena: Allocator, table: *std.StringHashMapUnmanaged(Signature), text: []const u8) il.Error!void {
    const marker = "@export(&";
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, text, at, marker)) |found| {
        at = found + 1;
        const exported = exportAt(text, found + marker.len) orelse continue;
        if (!isHelper(exported.symbol)) continue;
        const declaration = zigDeclaration(text, exported.function) orelse continue;
        const parameters = (try zigParameters(arena, declaration.parameters)) orelse continue;
        const result = zigType(declaration.result) orelse continue;
        const slot = try table.getOrPut(arena, exported.symbol);
        if (!slot.found_existing) slot.value_ptr.* = .{ .parameters = parameters, .result = result };
    }
}

/// `(\w+)\s*,\s*\.\{\s*\.name\s*=\s*"(\w+)"` at `start`.
fn exportAt(text: []const u8, start: usize) ?struct { function: []const u8, symbol: []const u8 } {
    var at = start;
    const function = wordAt(text, &at) orelse return null;
    for ([_][]const u8{ ",", ".{", ".name", "=", "\"" }) |token| if (!expect(text, &at, token)) return null;
    const symbol = wordAt(text, &at) orelse return null;
    if (at >= text.len or text[at] != '"') return null;
    return .{ .function = function, .symbol = symbol };
}

fn wordAt(text: []const u8, at: *usize) ?[]const u8 {
    const start = at.*;
    while (at.* < text.len and il.isWord(text[at.*])) at.* += 1;
    if (at.* == start) return null;
    return text[start..at.*];
}

/// Skip whitespace, then require `token`.
fn expect(text: []const u8, at: *usize, token: []const u8) bool {
    while (at.* < text.len and il.isSpace(text[at.*])) at.* += 1;
    if (!std.mem.startsWith(u8, text[at.*..], token)) return false;
    at.* += token.len;
    return true;
}

/// The parameter text and result type of `fn name(...)` in one Zig file.
fn zigDeclaration(text: []const u8, name: []const u8) ?struct { parameters: []const u8, result: []const u8 } {
    const open = functionOpen(text, name) orelse return null;
    var depth: i32 = 0;
    var index = open;
    while (index < text.len) : (index += 1) {
        if (text[index] == '(') depth += 1;
        if (text[index] != ')') continue;
        depth -= 1;
        if (depth != 0) continue;
        var tail = std.mem.trimStart(u8, text[index + 1 ..], " \t\n\r\x0b\x0c");
        if (std.mem.startsWith(u8, tail, "callconv")) {
            const close = std.mem.indexOfScalar(u8, tail, ')') orelse return null;
            tail = std.mem.trimStart(u8, tail[close + 1 ..], " \t\n\r\x0b\x0c");
        }
        const brace = std.mem.indexOfScalar(u8, tail, '{') orelse tail.len;
        return .{ .parameters = text[open + 1 .. index], .result = il.strip(tail[0..brace]) };
    }
    return null;
}

/// The `(` of the first line `^(?:pub )?fn\s+NAME\s*\(`.
fn functionOpen(text: []const u8, name: []const u8) ?usize {
    var at: usize = 0;
    while (at < text.len) : (at += 1) {
        if (at != 0 and text[at - 1] != '\n') continue;
        if (std.mem.startsWith(u8, text[at..], "pub fn")) {
            if (functionAfter(text, at + 4, name)) |open| return open;
        }
        if (std.mem.startsWith(u8, text[at..], "fn")) {
            if (functionAfter(text, at, name)) |open| return open;
        }
    }
    return null;
}

fn functionAfter(text: []const u8, start: usize, name: []const u8) ?usize {
    var at = start + 2;
    const gap = at;
    while (at < text.len and il.isSpace(text[at])) at += 1;
    if (at == gap or !std.mem.startsWith(u8, text[at..], name)) return null;
    at += name.len;
    while (at < text.len and il.isSpace(text[at])) at += 1;
    if (at >= text.len or text[at] != '(') return null;
    return at;
}

/// One Zig parameter or result type in LLVM spelling, or null.
fn zigType(text: []const u8) ?[]const u8 {
    const piece = il.strip(text);
    if (std.mem.indexOfScalar(u8, piece, '*') != null) return P;
    const table = [_][2][]const u8{
        .{ "u8", i32_type },         .{ "i8", i32_type },       .{ "u16", i32_type },    .{ "i16", i32_type },
        .{ "u32", i32_type },        .{ "i32", i32_type },      .{ "c_uint", i32_type }, .{ "c_int", i32_type },
        .{ "c_short", i32_type },    .{ "c_ushort", i32_type }, .{ "c_char", i32_type }, .{ "c_schar", i32_type },
        .{ "c_uchar", i32_type },    .{ "u64", i64_type },      .{ "i64", i64_type },    .{ "usize", i64_type },
        .{ "isize", i64_type },      .{ "c_ulong", i64_type },  .{ "c_long", i64_type }, .{ "c_ulonglong", i64_type },
        .{ "c_longlong", i64_type }, .{ "f32", "float" },       .{ "f64", "double" },    .{ "void", V },
    };
    for (table) |row| if (std.mem.eql(u8, row[0], piece)) return row[1];
    return null;
}

/// An exported Zig function's parameter types, split at every comma; null
/// when any one is not a C-ABI type this table knows.
fn zigParameters(arena: Allocator, text: []const u8) il.Error!?[]const []const u8 {
    if (il.strip(text).len == 0) return &.{};
    var out: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.splitScalar(u8, text, ',');
    while (parts.next()) |part| {
        const piece = if (std.mem.indexOfScalar(u8, part, ':')) |colon| part[colon + 1 ..] else part;
        try out.append(arena, zigType(piece) orelse return null);
    }
    return out.items;
}
