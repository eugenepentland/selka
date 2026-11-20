//! Per-module records: a module's header facts, kept between runs by the project loader, and a module's prepared dependency keys,
//! which the engine keeps and decides (the `module-check` kind; `frontend_shadow.zig`).
//! - a module's header facts, the imports, exports, embed calls and body start
//!   that header discovery reads from its tokens, keyed by its bytes;
//! - a module's prepared dependency keys, per function the stable key, the region digest, the
//!   dependency context and the recalled names. The keys are no store's: the engine decides when they still hold.
//!
//! A header record is read back only under its exact key, so a stale or foreign record can only ever miss. `Records` is the store the
//! loader is handed: a pair of function pointers with a context, the same shape as `project.Provider`, so this leaf file imports no
//! project types and every layer can use it.
const std = @import("std");
const codec = @import("persist_codec.zig");

/// Domain of a module's header facts. Bump it when their encoding or what header
/// discovery computes from the bytes changes.
pub const header_domain = "module-header-v2";

/// Whoever decides that a module's prepared facts still hold (the incremental engine, G2g): it answers for a module by its index in the
/// project, with the stored facts when it proves them valid, and is told when a record it proved valid could not be used. The facts it
/// keeps are published after the check, from what `prepare` computed, so this file needs no way to store one.
pub const Decider = struct {
    context: ?*anyopaque,
    /// The record of module `module` (an index into the project's modules) when it holds, in the allocator given, else null.
    restore: *const fn (?*anyopaque, std.mem.Allocator, usize) ?[]u8,
    /// The record `restore` returned for `module` did not describe the module's functions, so the module is computed.
    reject: *const fn (?*anyopaque, usize) void,
};

/// The loader's record store for header facts. `fetch` returns a copy the caller owns, allocated with
/// the allocator given, or null for an absent, damaged or unreadable record. `store`
/// keeps a payload under a key; a failure is ignored, because a record that is not
/// kept is only a later miss.
pub const Records = struct {
    context: ?*anyopaque,
    fetch: *const fn (?*anyopaque, std.mem.Allocator, [32]u8) ?[]u8,
    store: *const fn (?*anyopaque, [32]u8, []const u8) void,
};

/// The key of one record: SHA-256 over its domain and each part, every field
/// length-delimited so that adjacent parts cannot run together.
pub fn recordKey(domain: []const u8, parts: []const []const u8) [32]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    frame(&hash, domain);
    for (parts) |part| frame(&hash, part);
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

fn frame(hash: *std.crypto.hash.sha2.Sha256, bytes: []const u8) void {
    hash.update(std.mem.asBytes(&bytes.len));
    hash.update(bytes);
}

/// A byte range of one module's source.
pub const Range = struct { start: usize, end: usize };

/// One import of a module: the imported name, its local alias, its span, and the
/// `seen` flag header discovery sets when a qualified reference names it.
pub const ImportFact = struct { name: []const u8, alias: []const u8, span: Range, seen: bool };

/// One export directive: the exported name, its span and the re-export qualifier.
pub const ExportFact = struct { name: []const u8, span: Range, alias: ?[]const u8 };

/// One embed call site as header discovery found it, before any file is read.
pub const EmbedFact = struct { literal: Range, path: []const u8, text: bool };

/// Everything header discovery produces for a module whose header is valid.
pub const HeaderFacts = struct {
    body_start: usize,
    /// The legacy module name's span, or null when the module declares none.
    declaration: ?Range,
    imports: []const ImportFact,
    exports: []const ExportFact,
    embeds: []const EmbedFact,
};

/// A stored header record's text for `facts`; the caller frees it.
pub fn encodeHeader(allocator: std.mem.Allocator, facts: HeaderFacts) std.mem.Allocator.Error![]u8 {
    var writer = codec.Writer.init(allocator);
    errdefer writer.deinit();
    try writer.integer(@as(u64, facts.body_start));
    try writeOptionalRange(&writer, facts.declaration);
    try writer.integer(@as(u64, facts.imports.len));
    for (facts.imports) |item| {
        try writeText(&writer, item.name);
        try writeText(&writer, item.alias);
        try writeRange(&writer, item.span);
        try writer.integer(@as(u8, @intFromBool(item.seen)));
    }
    try writer.integer(@as(u64, facts.exports.len));
    for (facts.exports) |item| {
        try writeText(&writer, item.name);
        try writeRange(&writer, item.span);
        try writer.integer(@as(u8, @intFromBool(item.alias != null)));
        if (item.alias) |alias| try writeText(&writer, alias);
    }
    try writer.integer(@as(u64, facts.embeds.len));
    for (facts.embeds) |item| {
        try writeRange(&writer, item.literal);
        try writeText(&writer, item.path);
        try writer.integer(@as(u8, @intFromBool(item.text)));
    }
    const out = try writer.bytes.toOwnedSlice(allocator);
    return out;
}

/// The facts a stored header record holds, copied into `arena`, which must be an
/// arena: a damaged record leaves its partial copies allocated in it. Null for any
/// malformed, truncated or trailing-garbage payload, so the caller lexes instead.
pub fn decodeHeader(arena: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error!?HeaderFacts {
    var reader = codec.Reader.init(arena, bytes);
    return decodeHeaderFrom(&reader, bytes.len) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
}

fn decodeHeaderFrom(reader: *codec.Reader, limit: usize) codec.DecodeError!HeaderFacts {
    const allocator = reader.allocator;
    const body_start = try reader.integer(u64);
    const declaration = try readOptionalRange(reader);
    const import_count = try readCount(reader, limit);
    const imports = try allocator.alloc(ImportFact, import_count);
    for (imports) |*item| item.* = .{
        .name = try readText(reader, limit),
        .alias = try readText(reader, limit),
        .span = try readRange(reader),
        .seen = try readFlag(reader),
    };
    const export_count = try readCount(reader, limit);
    const exports = try allocator.alloc(ExportFact, export_count);
    for (exports) |*item| {
        const name = try readText(reader, limit);
        const span = try readRange(reader);
        const alias: ?[]const u8 = if (try readFlag(reader)) try readText(reader, limit) else null;
        item.* = .{ .name = name, .span = span, .alias = alias };
    }
    const embed_count = try readCount(reader, limit);
    const embeds = try allocator.alloc(EmbedFact, embed_count);
    for (embeds) |*item| item.* = .{
        .literal = try readRange(reader),
        .path = try readText(reader, limit),
        .text = try readFlag(reader),
    };
    if (!reader.done()) return error.InvalidEncoding;
    return .{ .body_start = std.math.cast(usize, body_start) orelse return error.InvalidEncoding, .declaration = declaration, .imports = imports, .exports = exports, .embeds = embeds };
}

/// One identifier-like reference a function's dependency context was collected
/// from: its text and, for a dotted `owner.member` reference, the owner's text.
pub const NameFact = struct { text: []const u8, owner: ?[]const u8 = null };

/// One function's record: its stable declaration key, its declaration region digest, its dependency context,
/// and the names its context was collected from, in the order they were recorded.
pub const FunctionFact = struct { key: []const u8 = "", region: [32]u8, context: [32]u8, names: []const NameFact };

/// A module's record: each of its functions in program order.
pub const ModuleKeys = struct { functions: []const FunctionFact };

/// A stored module-keys record's text; the caller frees it.
pub fn encodeKeys(allocator: std.mem.Allocator, keys: ModuleKeys) std.mem.Allocator.Error![]u8 {
    var writer = codec.Writer.init(allocator);
    errdefer writer.deinit();
    try writer.integer(@as(u64, keys.functions.len));
    for (keys.functions) |function| {
        try writeText(&writer, function.key);
        try writer.raw(&function.region);
        try writer.raw(&function.context);
        try writer.integer(@as(u64, function.names.len));
        for (function.names) |name| {
            try writeText(&writer, name.text);
            try writer.integer(@as(u8, @intFromBool(name.owner != null)));
            if (name.owner) |owner| try writeText(&writer, owner);
        }
    }
    const out = try writer.bytes.toOwnedSlice(allocator);
    return out;
}

/// The keys a stored record holds, copied into `arena` (an arena, as for `decodeHeader`);
/// null when malformed.
pub fn decodeKeys(arena: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error!?ModuleKeys {
    var reader = codec.Reader.init(arena, bytes);
    return decodeKeysFrom(&reader, bytes.len, .copy) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
}

/// `decodeKeys` whose texts (keys, names, owners) are slices of `bytes` itself, not copies: a build that restores every module of a program
/// makes one allocation per function and none per name. `bytes` must outlive the returned record.
pub fn decodeKeysBorrowed(arena: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error!?ModuleKeys {
    var reader = codec.Reader.init(arena, bytes);
    return decodeKeysFrom(&reader, bytes.len, .borrow) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
}

/// Whether a decoded text is copied out of the record's bytes or borrowed from them.
const TextMode = enum { copy, borrow };

fn decodeKeysFrom(reader: *codec.Reader, limit: usize, mode: TextMode) codec.DecodeError!ModuleKeys {
    const allocator = reader.allocator;
    const count = try readCount(reader, limit);
    const functions = try allocator.alloc(FunctionFact, count);
    for (functions) |*function| {
        const key = try readTextIn(reader, limit, mode);
        const region = try readDigest(reader);
        const context = try readDigest(reader);
        const name_count = try readCount(reader, limit);
        const names = try allocator.alloc(NameFact, name_count);
        for (names) |*name| {
            const text = try readTextIn(reader, limit, mode);
            const owner: ?[]const u8 = if (try readFlag(reader)) try readTextIn(reader, limit, mode) else null;
            name.* = .{ .text = text, .owner = owner };
        }
        function.* = .{ .key = key, .region = region, .context = context, .names = names };
    }
    if (!reader.done()) return error.InvalidEncoding;
    return .{ .functions = functions };
}

fn writeText(writer: *codec.Writer, text: []const u8) std.mem.Allocator.Error!void {
    try writer.integer(@as(u64, text.len));
    try writer.raw(text);
}

fn writeRange(writer: *codec.Writer, range: Range) std.mem.Allocator.Error!void {
    try writer.integer(@as(u64, range.start));
    try writer.integer(@as(u64, range.end));
}

fn writeOptionalRange(writer: *codec.Writer, range: ?Range) std.mem.Allocator.Error!void {
    try writer.integer(@as(u8, @intFromBool(range != null)));
    if (range) |present| try writeRange(writer, present);
}

fn readText(reader: *codec.Reader, limit: usize) codec.DecodeError![]const u8 {
    return readTextIn(reader, limit, .copy);
}

fn readTextIn(reader: *codec.Reader, limit: usize, mode: TextMode) codec.DecodeError![]const u8 {
    const length = try readCount(reader, limit);
    const raw = try reader.slice(length);
    if (mode == .borrow) return raw;
    return reader.allocator.dupe(u8, raw) catch return error.OutOfMemory;
}

fn readRange(reader: *codec.Reader) codec.DecodeError!Range {
    const start = try reader.integer(u64);
    const end = try reader.integer(u64);
    if (start > end) return error.InvalidEncoding;
    return .{ .start = std.math.cast(usize, start) orelse return error.InvalidEncoding, .end = std.math.cast(usize, end) orelse return error.InvalidEncoding };
}

fn readOptionalRange(reader: *codec.Reader) codec.DecodeError!?Range {
    if (!try readFlag(reader)) return null;
    const range = try readRange(reader);
    return range;
}

fn readFlag(reader: *codec.Reader) codec.DecodeError!bool {
    return switch (try reader.integer(u8)) {
        0 => false,
        1 => true,
        else => error.InvalidEncoding,
    };
}

/// A count or length that cannot exceed the bytes that follow it: each counted item
/// occupies at least one byte, so a larger count is damage, not a large record.
fn readCount(reader: *codec.Reader, limit: usize) codec.DecodeError!usize {
    const count = try reader.integer(u64);
    if (count > limit) return error.InvalidEncoding;
    return @intCast(count);
}

fn readDigest(reader: *codec.Reader) codec.DecodeError![32]u8 {
    const raw = try reader.slice(32);
    return raw[0..32].*;
}

test "a header record round trips and a damaged one is refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = std.testing.allocator;
    const imports = [_]ImportFact{
        .{ .name = "shared.data", .alias = "data", .span = .{ .start = 7, .end = 19 }, .seen = true },
        .{ .name = "left", .alias = "l", .span = .{ .start = 30, .end = 34 }, .seen = false },
    };
    const exports = [_]ExportFact{
        .{ .name = "Value", .span = .{ .start = 40, .end = 45 }, .alias = null },
        .{ .name = "Item", .span = .{ .start = 50, .end = 54 }, .alias = "data" },
    };
    const embeds = [_]EmbedFact{.{ .literal = .{ .start = 60, .end = 70 }, .path = "table.bin", .text = false }};
    const facts: HeaderFacts = .{ .body_start = 80, .declaration = .{ .start = 0, .end = 6 }, .imports = &imports, .exports = &exports, .embeds = &embeds };
    const bytes = try encodeHeader(allocator, facts);
    defer allocator.free(bytes);
    const again = try encodeHeader(allocator, facts);
    defer allocator.free(again);
    try std.testing.expectEqualSlices(u8, bytes, again);
    const decoded = (try decodeHeader(arena.allocator(), bytes)).?;
    try std.testing.expectEqual(@as(usize, 80), decoded.body_start);
    try std.testing.expectEqual(@as(?Range, Range{ .start = 0, .end = 6 }), decoded.declaration);
    try std.testing.expectEqual(@as(usize, 2), decoded.imports.len);
    try std.testing.expectEqualStrings("shared.data", decoded.imports[0].name);
    try std.testing.expect(decoded.imports[0].seen);
    try std.testing.expectEqualStrings("Item", decoded.exports[1].name);
    try std.testing.expectEqualStrings("data", decoded.exports[1].alias.?);
    try std.testing.expectEqual(@as(?[]const u8, null), decoded.exports[0].alias);
    try std.testing.expectEqualStrings("table.bin", decoded.embeds[0].path);
    try std.testing.expect((try decodeHeader(arena.allocator(), bytes[0 .. bytes.len - 1])) == null);
    try std.testing.expect((try decodeHeader(arena.allocator(), "not a record")) == null);
    var padded = try allocator.alloc(u8, bytes.len + 1);
    defer allocator.free(padded);
    @memcpy(padded[0..bytes.len], bytes);
    padded[bytes.len] = 0;
    try std.testing.expect((try decodeHeader(arena.allocator(), padded)) == null);
}

test "a header record without a declaration or any items round trips" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = std.testing.allocator;
    const bytes = try encodeHeader(allocator, .{ .body_start = 0, .declaration = null, .imports = &.{}, .exports = &.{}, .embeds = &.{} });
    defer allocator.free(bytes);
    const decoded = (try decodeHeader(arena.allocator(), bytes)).?;
    try std.testing.expectEqual(@as(?Range, null), decoded.declaration);
    try std.testing.expectEqual(@as(usize, 0), decoded.imports.len);
    try std.testing.expectEqual(@as(usize, 0), decoded.embeds.len);
}

test "a module-keys record round trips and keeps every name and owner" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = std.testing.allocator;
    const names = [_]NameFact{ .{ .text = "helper", .owner = null }, .{ .text = "member", .owner = "Domain" } };
    const functions = [_]FunctionFact{
        .{ .region = @splat(1), .context = @splat(2), .names = &names },
        .{ .region = @splat(3), .context = @splat(4), .names = &.{} },
    };
    const bytes = try encodeKeys(allocator, .{ .functions = &functions });
    defer allocator.free(bytes);
    const decoded = (try decodeKeys(arena.allocator(), bytes)).?;
    try std.testing.expectEqual(@as(usize, 2), decoded.functions.len);
    try std.testing.expectEqual(@as([32]u8, @splat(4)), decoded.functions[1].context);
    try std.testing.expectEqualStrings("member", decoded.functions[0].names[1].text);
    try std.testing.expectEqualStrings("Domain", decoded.functions[0].names[1].owner.?);
    try std.testing.expectEqual(@as(?[]const u8, null), decoded.functions[0].names[0].owner);
    try std.testing.expect((try decodeKeys(arena.allocator(), bytes[0 .. bytes.len - 3])) == null);
}

test "record keys separate domains and part boundaries" {
    try std.testing.expect(!std.mem.eql(u8, &recordKey("a", &.{"bc"}), &recordKey("ab", &.{"c"})));
    try std.testing.expect(!std.mem.eql(u8, &recordKey("a", &.{ "b", "c" }), &recordKey("a", &.{"bc"})));
    try std.testing.expectEqual(recordKey(header_domain, &.{"x"}), recordKey(header_domain, &.{"x"}));
    try std.testing.expect(!std.mem.eql(u8, &recordKey(header_domain, &.{"x"}), &recordKey("another-domain", &.{"x"})));
}
