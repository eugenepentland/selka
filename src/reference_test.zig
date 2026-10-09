//! Unit tests for the compiler-derived reference engine and its command.
//!
//! The engine is generic over the compiler surface, so this test module
//! assembles the same surface the installed executable passes as `mylang`.
//! Two kinds of expectation are deliberately different here: facts the
//! compiler derives are asserted against the compiler's own tables, while a
//! few current answers (a standard module's signature, a documented anchor)
//! are pinned as literals so a change to them fails loudly instead of silently
//! redefining the reference.

const std = @import("std");
const t = std.testing;
const reference = @import("reference.zig");
const command = @import("reference_command.zig");
const reference_text = @import("reference_text.zig");
const coverage = @import("doc_coverage.zig");
const standard_library = @import("standard_library.zig");
const buffer_operations = @import("buffer_operations.zig");
const io_builtins = @import("io_builtins.zig");

/// The compiler surface the engine reads. The unit module has no `mylang`
/// import, so the surface is assembled from the same files `src/compiler.zig`
/// re-exports for the installed executable.
const language = struct {
    /// Project loading and its provider contract.
    pub const project = @import("project.zig");
    /// Declaration identities and the `interface-contracts-v2` listing.
    pub const interfaces = @import("interfaces.zig");
    /// Whole-project checking and the checked program.
    pub const project_compile = @import("project_compile.zig");
    /// The effect vocabulary an interface listing publishes.
    pub const effect_set = @import("effect_set.zig");
    /// Source text and spans.
    pub const source = @import("source.zig");
    /// The builtin vocabulary tables, mirroring `compiler.reference_tables`.
    pub const reference_tables = struct {
        /// Type constructor arities and reserved prelude type names.
        pub const prelude = @import("prelude.zig");
        /// Bare Python builtin spellings.
        pub const prelude_builtins = @import("prelude_builtins.zig");
        /// Collection method spellings, operations and arities.
        pub const buffer_operations = @import("buffer_operations.zig");
        /// Host I/O builtin names and arities.
        pub const io_builtins = @import("io_builtins.zig");
        /// Scalar float intrinsics accepted in call position.
        pub const float_intrinsics = @import("float_intrinsics.zig");
        /// Managed collection families a method spelling belongs to.
        pub const runtime_values = @import("runtime_values.zig");
        /// The compile-time file embedding builtins.
        pub const embed = @import("embed.zig");
    };
};

const Reader = reference.EntryReader(language);

/// Render one query as the JSON envelope with the embedding allocator.
fn json(query: []const u8) ![]u8 {
    return reference.run(language, t.allocator, .{ .query = query, .format = .json });
}

/// Render one query as text with the embedding allocator.
fn text(query: []const u8) ![]u8 {
    return reference.run(language, t.allocator, .{ .query = query, .format = .text });
}

/// Render one query without checking the embedded bodies.
fn uncheckedJson(query: []const u8) ![]u8 {
    return reference.run(language, t.allocator, .{ .query = query, .format = .json, .check_bodies = false });
}

/// Parse an envelope and hand back its root object.
fn envelope(allocator: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(std.json.Value) {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    if (parsed.value != .object) {
        parsed.deinit();
        return error.TestUnexpectedResult;
    }
    return parsed;
}

/// One array member of an envelope, or an empty slice when it is null.
fn section(root: std.json.Value, name: []const u8) []std.json.Value {
    const field = root.object.get(name) orelse return &.{};
    return switch (field) {
        .array => |array| array.items,
        else => &.{},
    };
}

/// The first object in `items` whose `field` equals `wanted`.
fn find(items: []std.json.Value, field: []const u8, wanted: []const u8) ?std.json.Value {
    for (items) |item| {
        if (!std.mem.eql(u8, stringAt(item, field), wanted)) continue;
        return item;
    }
    return null;
}

/// One string field, or an empty string when absent.
fn stringAt(value: std.json.Value, name: []const u8) []const u8 {
    const field = switch (value) {
        .object => |object| object.get(name) orelse return "",
        else => return "",
    };
    return switch (field) {
        .string => |content| content,
        else => "",
    };
}

/// Whether one field is present as JSON null.
fn isNull(value: std.json.Value, name: []const u8) bool {
    const field = switch (value) {
        .object => |object| object.get(name) orelse return false,
        else => return false,
    };
    return field == .null;
}

/// The string members of one array field, or null when the field is null.
fn stringsAt(allocator: std.mem.Allocator, value: std.json.Value, name: []const u8) !?[]const []const u8 {
    const field = switch (value) {
        .object => |object| object.get(name) orelse return null,
        else => return null,
    };
    const items = switch (field) {
        .array => |array| array.items,
        else => return null,
    };
    const out = try allocator.alloc([]const u8, items.len);
    for (items, out) |item, *slot| slot.* = switch (item) {
        .string => |content| content,
        else => "",
    };
    return out;
}

/// One integral field, or null when it is absent or not an integer.
fn integerAt(value: std.json.Value, name: []const u8) ?usize {
    const field = switch (value) {
        .object => |object| object.get(name) orelse return null,
        else => return null,
    };
    return switch (field) {
        .integer => |number| if (number < 0) null else @intCast(number),
        else => null,
    };
}

/// Whether the doc pointer `page.md#anchor` names a heading in this checkout.
/// This is a test-time check of a fact the compiler only stores as a pointer.
fn docAnchorResolves(allocator: std.mem.Allocator, pointer: []const u8) !bool {
    const hash = std.mem.indexOfScalar(u8, pointer, '#') orelse return false;
    const page = pointer[0..hash];
    const anchor = pointer[hash + 1 ..];
    const document = std.Io.Dir.cwd().readFileAlloc(t.io, page, allocator, .limited(4 * 1024 * 1024)) catch return false;
    defer allocator.free(document);
    return coverage.section(document, anchor) != null;
}

/// Whether every embedded standard module has library-owned source text, and
/// whether every library-owned path is in the engine's list.
fn standardModulesMatchCheckout(embedded: []const []const u8) !bool {
    for (embedded) |name| if (standard_library.source(name) == null) return false;
    var directory = std.Io.Dir.cwd().openDir(t.io, "src/stdlib", .{ .iterate = true }) catch return false;
    defer directory.close(t.io);
    var iterator = directory.iterate();
    var counted: usize = 0;
    while (try iterator.next(t.io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".my")) continue;
        counted += 1;
        if (!contains(embedded, entry.name)) return false;
    }
    return counted == embedded.len;
}

/// Whether a name list contains one exact name.
fn contains(names: []const []const u8, wanted: []const u8) bool {
    for (names) |name| if (std.mem.eql(u8, name, wanted)) return true;
    return false;
}

/// Fill `out` with the integer members of one array field; null when the field
/// is absent, not an array, not integral, or longer than `out`.
fn arities(value: std.json.Value, name: []const u8, out: []i64) ?[]const i64 {
    const field = switch (value) {
        .object => |object| object.get(name) orelse return null,
        else => return null,
    };
    const items = switch (field) {
        .array => |array| array.items,
        else => return null,
    };
    if (items.len > out.len) return null;
    for (items, 0..) |item, index| out[index] = switch (item) {
        .integer => |number| number,
        else => return null,
    };
    return out[0..items.len];
}

/// Whether one curated example is the body of a fenced `mylang` block.
fn exampleIsExecutable(document: []const u8, example: []const u8) bool {
    var walk = coverage.fences(document);
    while (walk.next()) |fence| {
        if (!std.mem.eql(u8, fence.info, "mylang")) continue;
        if (std.mem.indexOf(u8, fence.body, example) != null) return true;
    }
    return false;
}

/// The first curated entry whose example is not an executed documentation
/// block, or null when every entry is covered.
fn firstUndocumentedExample(document: []const u8) ?[]const u8 {
    for (reference_text.entries) |entry| {
        if (!exampleIsExecutable(document, entry.example)) return entry.id;
    }
    return null;
}

// spec: REFERENCE-1
test "an implemented feature answers with its manifest record and a live doc anchor" {
    const bytes = try json("standard-sort");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    const features = section(parsed.value, "features");
    const feature = find(features, "slug", "standard-sort") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("language", stringAt(feature, "kind"));
    try t.expect(stringAt(feature, "summary").len > 0);
    try t.expect(try docAnchorResolves(t.allocator, stringAt(feature, "doc")));
}

// spec: REFERENCE-2
test "a standard-library declaration answers with its checked signature and status" {
    const bytes = try json("sort_ints");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    const declarations = section(parsed.value, "declarations");
    const declaration = find(declarations, "name", "sort::sort_ints") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("function", stringAt(declaration, "kind"));
    try t.expectEqualStrings("func(values:i64[])->i64[]", stringAt(declaration, "signature"));
    try t.expectEqualStrings("checked", stringAt(declaration, "analysis"));
    const effects = (try stringsAt(t.allocator, declaration, "effects")).?;
    defer t.allocator.free(effects);
    try t.expectEqual(@as(usize, 1), effects.len);
    try t.expectEqualStrings("managed_allocation", effects[0]);
    const ceiling = (try stringsAt(t.allocator, declaration, "ceiling")).?;
    defer t.allocator.free(ceiling);
    try t.expectEqual(@as(usize, 1), ceiling.len);
    try t.expectEqualStrings("managed_allocation", ceiling[0]);
}

// spec: REFERENCE-3
test "declaration-only analysis publishes the declared ceiling and no inferred effect" {
    const bytes = try uncheckedJson("sort_ints");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    try t.expectEqualStrings("declaration-only", stringAt(parsed.value.object.get("library").?, "status"));
    const declarations = section(parsed.value, "declarations");
    const declaration = find(declarations, "name", "sort::sort_ints") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("declaration-only", stringAt(declaration, "analysis"));
    try t.expect(isNull(declaration, "effects"));
    const ceiling = (try stringsAt(t.allocator, declaration, "ceiling")).?;
    defer t.allocator.free(ceiling);
    try t.expectEqual(@as(usize, 1), ceiling.len);
    try t.expectEqualStrings("managed_allocation", ceiling[0]);
}

// spec: REFERENCE-4
test "a generic declaration without an instantiation publishes no inferred effect" {
    const bytes = try json("sort_by_key");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    const declarations = section(parsed.value, "declarations");
    const declaration = find(declarations, "name", "sort::sort_by_key") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("template", stringAt(declaration, "analysis"));
    try t.expect(isNull(declaration, "effects"));
    try t.expect(!isNull(declaration, "ceiling"));
}

// spec: REFERENCE-5
test "builtin and collection-method facts answer from the checker's own tables" {
    const builtin_bytes = try json("print");
    defer t.allocator.free(builtin_bytes);
    var builtin_parsed = try envelope(t.allocator, builtin_bytes);
    defer builtin_parsed.deinit();
    const builtin = find(section(builtin_parsed.value, "builtins"), "name", "print") orelse return error.TestUnexpectedResult;
    try t.expectEqual(io_builtins.builtin("print").?.arity(), integerAt(builtin, "arity").?);
    try t.expectEqualStrings("io_builtins.Builtin", stringAt(builtin, "source"));

    const method_bytes = try json("split");
    defer t.allocator.free(method_bytes);
    var method_parsed = try envelope(t.allocator, method_bytes);
    defer method_parsed.deinit();
    const method = find(section(method_parsed.value, "methods"), "name", "split") orelse return error.TestUnexpectedResult;
    var buffer: [8]i64 = undefined;
    const reported = arities(method, "arities", &buffer).?;
    try t.expectEqual(@as(i64, 0), reported[0]);
    try t.expectEqual(@as(i64, 1), reported[1]);
    try t.expectEqual(@as(usize, 2), reported.len);
    // The two reported counts are the two operations the table spells `split`.
    try t.expectEqual(@as(usize, 0), buffer_operations.Kind.split_whitespace.arity());
    try t.expectEqual(@as(usize, 1), buffer_operations.Kind.split.arity());
    try t.expectEqualStrings("split", buffer_operations.spelling(.split_whitespace).?);
    try t.expectEqualStrings("split", buffer_operations.spelling(.split).?);
    try t.expectEqualStrings("string,bytes", stringAt(method, "families"));
}

// spec-case: EMBED-5
test "the embed builtins are discoverable through the reference" {
    const bytes = try json("embed_bytes");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    const builtin = find(section(parsed.value, "builtins"), "name", "embed_bytes") orelse return error.TestUnexpectedResult;
    try t.expectEqual(@as(usize, 1), integerAt(builtin, "arity").?);
    try t.expectEqualStrings("embed.kindOf", stringAt(builtin, "source"));
}

// spec: REFERENCE-6
test "unsupported and removed names answer as exclusions, never as features" {
    const unsupported_bytes = try json("capturing-closures");
    defer t.allocator.free(unsupported_bytes);
    var unsupported_parsed = try envelope(t.allocator, unsupported_bytes);
    defer unsupported_parsed.deinit();
    try t.expectEqual(@as(usize, 0), section(unsupported_parsed.value, "features").len);
    const unsupported = find(section(unsupported_parsed.value, "exclusions"), "slug", "capturing-closures") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("unsupported", stringAt(unsupported, "status"));

    const removed_bytes = try json("legacy-syntax");
    defer t.allocator.free(removed_bytes);
    var removed_parsed = try envelope(t.allocator, removed_bytes);
    defer removed_parsed.deinit();
    try t.expectEqual(@as(usize, 0), section(removed_parsed.value, "features").len);
    const removed = find(section(removed_parsed.value, "exclusions"), "slug", "legacy-syntax") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("removed", stringAt(removed, "status"));
    try t.expectEqualStrings("2026-09-13", stringAt(removed, "date"));
    try t.expect(stringAt(removed, "detail").len > 0);
}

// spec: REFERENCE-7
test "the same query renders byte-identical answers and a dated envelope" {
    const first = try text("sort");
    defer t.allocator.free(first);
    const second = try text("sort");
    defer t.allocator.free(second);
    try t.expectEqualStrings(first, second);

    const bytes = try json("sort");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    try t.expectEqualStrings("reference-v1", stringAt(parsed.value, "version"));
    try t.expectEqualStrings("sort", stringAt(parsed.value, "query"));
    // `sort` is also a collection-method key, so the term matches it whole.
    try t.expectEqualStrings("exact", stringAt(parsed.value, "match"));
    try t.expectEqualStrings("0.1.0", stringAt(parsed.value.object.get("language").?, "version"));
    try t.expectEqualStrings("checked", stringAt(parsed.value.object.get("library").?, "status"));
    // Every embedded standard module publishes something, and the count is
    // taken before the match filter, so a matched list can never be mistaken
    // for the library's own size.
    try t.expectEqual(@as(usize, reference.standard_modules.len), integerAt(parsed.value.object.get("library").?, "modules").?);
    try t.expect(integerAt(parsed.value.object.get("library").?, "exports").? > 0);
    try t.expect(parsed.value.object.get("count").?.integer > 0);
    try t.expect(section(parsed.value, "declarations").len > 0);
    try t.expect(section(parsed.value, "methods").len > 0);
}

// spec: REFERENCE-8
test "an unmatched query is a normal answer and a malformed one is a usage error" {
    const bytes = try text("zzz-no-such-fact");
    defer t.allocator.free(bytes);
    try t.expect(std.mem.indexOf(u8, bytes, "match=none") != null);
    try t.expect(std.mem.indexOf(u8, bytes, "no fact in this executable matches") != null);
    const unmatched = try json("zzz-no-such-fact");
    defer t.allocator.free(unmatched);
    var parsed = try envelope(t.allocator, unmatched);
    defer parsed.deinit();
    try t.expectEqualStrings("none", stringAt(parsed.value, "match"));
    try t.expectEqual(@as(i64, 0), parsed.value.object.get("count").?.integer);
    try t.expectError(error.EmptyQuery, reference.run(language, t.allocator, .{ .query = "  " }));
}

// spec: REFERENCE-9
test "the embedded project reads exactly one in-memory path and no checkout file" {
    var reader: Reader = .{ .entry = "" };
    try t.expectError(error.NotFound, Reader.read(&reader, t.allocator, "sort.my", 1 << 20));
    try t.expectError(error.NotFound, Reader.read(&reader, t.allocator, "src/stdlib/sort.my", 1 << 20));
    const served = try Reader.read(&reader, t.allocator, reference.entry_path, 1 << 20);
    defer t.allocator.free(served);
    try t.expectEqualStrings("", served);
    try t.expect(try standardModulesMatchCheckout(&reference.standard_modules));
    // The stand-in modules are part of the reference project too (TEST-CAPS-1).
    try t.expectEqual(@as(usize, 14), reference.standard_modules.len);
}

// spec: REFERENCE-10
test "every curated example is an executed block in docs/reference.md" {
    const document = try std.Io.Dir.cwd().readFileAlloc(t.io, "docs/reference.md", t.allocator, .limited(1 << 20));
    defer t.allocator.free(document);
    try t.expectEqual(@as(?[]const u8, null), firstUndocumentedExample(document));
    try t.expect(coverage.hasRunnableExample(document));
}

// spec: REFERENCE-12
test "an allocation failure reaches the caller as OutOfMemory for either format" {
    var text_failure = std.testing.FailingAllocator.init(t.allocator, .{ .fail_index = 0 });
    try t.expectError(error.OutOfMemory, reference.run(language, text_failure.allocator(), .{ .query = "sort", .format = .text }));
    var json_failure = std.testing.FailingAllocator.init(t.allocator, .{ .fail_index = 0 });
    try t.expectError(error.OutOfMemory, reference.run(language, json_failure.allocator(), .{ .query = "sort", .format = .json }));
}

// spec: REFERENCE-11
test "the command reports usage on a malformed request and answers a well-formed one" {
    const missing = try command.answer(language, t.allocator, &.{});
    try t.expectEqual(@as(u8, 2), missing.status);
    try t.expect(std.mem.indexOf(u8, missing.stderr, "usage: mylang reference") != null);
    const unknown = try command.answer(language, t.allocator, &.{ "--query", "sort", "--nope" });
    try t.expectEqual(@as(u8, 2), unknown.status);
    const bad_format = try command.answer(language, t.allocator, &.{ "--query", "sort", "--format=yaml" });
    try t.expectEqual(@as(u8, 2), bad_format.status);
    const empty = try command.answer(language, t.allocator, &.{ "--query", " " });
    try t.expectEqual(@as(u8, 2), empty.status);
    const help = try command.answer(language, t.allocator, &.{"--help"});
    try t.expectEqual(@as(u8, 0), help.status);
    try t.expect(std.mem.indexOf(u8, help.stdout, "usage: mylang reference") != null);
    const answered = try command.answer(language, t.allocator, &.{ "--query", "standard-sort", "--format=json" });
    defer t.allocator.free(answered.stdout);
    try t.expectEqual(@as(u8, 0), answered.status);
    var parsed = try envelope(t.allocator, answered.stdout);
    defer parsed.deinit();
    try t.expectEqual(@as(usize, 1), section(parsed.value, "features").len);
}
