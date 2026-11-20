//! Unit tests for the compiler-derived reference engine and its command.
//!
//! The engine is generic over the compiler surface, so this test module
//! assembles the same surface the installed executable passes as `selka`.
//! Two kinds of expectation are deliberately different here: facts the
//! compiler derives are asserted against the compiler's own tables, while a
//! few current answers (a standard module's signature, a documented anchor)
//! are pinned as literals so a change to them fails loudly instead of silently
//! redefining the reference.

const std = @import("std");
const product = @import("product.zig");
const t = std.testing;
const reference = @import("reference.zig");
const command = @import("reference_command.zig");
const reference_text = @import("reference_text.zig");
const coverage = @import("doc_coverage.zig");
const standard_library = @import("standard_library.zig");
const buffer_operations = @import("buffer_operations.zig");
const io_builtins = @import("io_builtins.zig");
const diagnostic_codes = @import("diagnostic_codes.zig");
const user_docs = @import("user_docs.zig");
const reference_source = @import("reference_source.zig");
const prelude_names = @import("prelude_names.zig");

/// The compiler surface the engine reads. The unit module has no `selka`
/// import, so the surface is assembled from the same files `src/compiler.zig`
/// re-exports for the installed executable.
const language = struct {
    /// Project loading and its provider contract.
    pub const project = @import("project.zig");
    /// Declaration identities and the `interface-contracts-v2` listing.
    pub const interfaces = @import("interfaces.zig");
    /// Whole-project checking and the checked program.
    pub const project_compile = @import("project_compile.zig");
    /// Source text and spans.
    pub const source = @import("source.zig");
    /// The reserved standard modules: the one table the engine lists them from.
    pub const standard_library = @import("standard_library.zig");
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
        if (entry.kind != .file or !product.isSource(entry.name)) continue;
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

/// Whether one curated example is the body of a fenced `selka` block.
fn exampleIsExecutable(document: []const u8, example: []const u8) bool {
    var walk = coverage.fences(document);
    while (walk.next()) |fence| {
        if (!std.mem.eql(u8, fence.info, "selka")) continue;
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
    try t.expect(declaration.object.get("effects") == null);
    try t.expect(declaration.object.get("ceiling") == null);
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
    try t.expect(declaration.object.get("effects") == null);
    try t.expect(declaration.object.get("ceiling") == null);
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
    try t.expect(declaration.object.get("effects") == null);
    try t.expect(declaration.object.get("ceiling") == null);
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
    // `split(separator)` is retired for text and for byte strings, so neither
    // family advertises the spelling; its zero-argument form still works, and the
    // arities below are what the operation table spells.
    try t.expectEqualStrings("", stringAt(method, "families"));
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

// spec-case: FUNCTION-IDENTITY-1
test "same_function is discoverable through the reference" {
    const bytes = try json("same_function");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    const builtin = find(section(parsed.value, "builtins"), "name", "same_function") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("prelude_builtins.reserved", stringAt(builtin, "source"));
}

// spec: REFERENCE-13
test "the reference handles short nominal exports beside generic memo functions" {
    const bytes = try json("memo");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    const declarations = section(parsed.value, "declarations");
    const key = find(declarations, "name", "memo::Key") orelse return error.TestUnexpectedResult;
    const call = find(declarations, "name", "memo::call") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("type", stringAt(key, "kind"));
    try t.expectEqualStrings("declared", stringAt(key, "analysis"));
    try t.expectEqualStrings("function", stringAt(call, "kind"));
    try t.expectEqualStrings("template", stringAt(call, "analysis"));
}

test "the reference includes the generic parallel map declaration" {
    const bytes = try json("parallel");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    const declarations = section(parsed.value, "declarations");
    const declaration = find(declarations, "name", "parallel::map") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("function", stringAt(declaration, "kind"));
    try t.expectEqualStrings("template", stringAt(declaration, "analysis"));
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
    try t.expectEqual(@as(usize, standard_library.count), integerAt(parsed.value.object.get("library").?, "modules").?);
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
    try t.expectError(error.NotFound, Reader.read(&reader, t.allocator, "sort.selka", 1 << 20));
    try t.expectError(error.NotFound, Reader.read(&reader, t.allocator, "src/stdlib/sort.selka", 1 << 20));
    const served = try Reader.read(&reader, t.allocator, reference.entry_path, 1 << 20);
    defer t.allocator.free(served);
    try t.expectEqualStrings("", served);
    // The engine reads the compiler's own table, so a module added there is listed here with no second edit.
    try t.expect(try standardModulesMatchCheckout(&standard_library.paths));
    try t.expectEqual(standard_library.count, standard_library.paths.len);
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
    try t.expect(std.mem.indexOf(u8, missing.stderr, "usage: selka reference") != null);
    const unknown = try command.answer(language, t.allocator, &.{ "--query", "sort", "--nope" });
    try t.expectEqual(@as(u8, 2), unknown.status);
    const bad_format = try command.answer(language, t.allocator, &.{ "--query", "sort", "--format=yaml" });
    try t.expectEqual(@as(u8, 2), bad_format.status);
    const empty = try command.answer(language, t.allocator, &.{ "--query", " " });
    try t.expectEqual(@as(u8, 2), empty.status);
    const help = try command.answer(language, t.allocator, &.{"--help"});
    try t.expectEqual(@as(u8, 0), help.status);
    try t.expect(std.mem.indexOf(u8, help.stdout, "usage: selka reference") != null);
    const answered = try command.answer(language, t.allocator, &.{ "--query", "standard-sort", "--format=json" });
    defer t.allocator.free(answered.stdout);
    try t.expectEqual(@as(u8, 0), answered.status);
    var parsed = try envelope(t.allocator, answered.stdout);
    defer parsed.deinit();
    try t.expectEqual(@as(usize, 1), section(parsed.value, "features").len);
}

// spec-case: FUNCTION-DIGEST-1
test "function_digest is discoverable through the reference" {
    const bytes = try json("function_digest");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    const builtin = find(section(parsed.value, "builtins"), "name", "function_digest") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("prelude_builtins.reserved", stringAt(builtin, "source"));
}

/// The `diagnostic` record for `code` in a JSON answer, or null.
fn codeRecord(root: std.json.Value, code: []const u8) ?std.json.Value {
    return find(section(root, "diagnostics"), "code", code);
}

// spec: REFERENCE-CODES-1
test "reference answers a diagnostic code with its meaning and guide" {
    const bytes = try json("E_TRY_POSITION");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    try t.expectEqualStrings("exact", stringAt(parsed.value, "match"));
    const record = codeRecord(parsed.value, "E_TRY_POSITION") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("errors", stringAt(record, "guide"));
    // TRY-2: `try` stands anywhere a value is computed at run time, so the code names what is still refused.
    try t.expect(std.mem.indexOf(u8, stringAt(record, "meaning"), "not an operator expression") != null);
    try t.expect(std.mem.indexOf(u8, stringAt(record, "meaning"), "a module constant, a default") != null);
    const answer = try text("e_try_position");
    defer t.allocator.free(answer);
    try t.expect(std.mem.indexOf(u8, answer, "diagnostic E_TRY_POSITION\n  meaning: ") != null);
    try t.expect(std.mem.indexOf(u8, answer, "\n  guide: selka docs errors\n") != null);
}

test "reference lists every applicable ownership rule without selecting one for a shared code" {
    const bytes = try uncheckedJson("E_SINGLE_OWNER_OVERLAP");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    const record = codeRecord(parsed.value, "E_SINGLE_OWNER_OVERLAP").?;
    const actual = section(record, "rules");
    try t.expectEqual(@as(usize, 6), actual.len);
    try t.expectEqualStrings("R2", actual[0].string);
    try t.expectEqualStrings("X2", actual[5].string);
    const answer = try reference.run(language, t.allocator, .{ .query = "E_SINGLE_OWNER_OVERLAP", .format = .text, .check_bodies = false });
    defer t.allocator.free(answer);
    try t.expect(std.mem.indexOf(u8, answer, "ownership rules: Exclusion (R2, R7, M5, M6, X1, X2)\n") != null);
    const ordinary = try uncheckedJson("E_TRY_POSITION");
    defer t.allocator.free(ordinary);
    var plain = try envelope(t.allocator, ordinary);
    defer plain.deinit();
    try t.expectEqual(@as(usize, 0), section(codeRecord(plain.value, "E_TRY_POSITION").?, "rules").len);
}

test "reference names which of the model's rules each ownership code enforces, heading by heading" {
    const answer = try reference.run(language, t.allocator, .{ .query = "E_SINGLE_OWNER_BORROW", .format = .text, .check_bodies = false });
    defer t.allocator.free(answer);
    const expected = "ownership rules: Escape (B7, B9, R1, R3, R4, R6, M1); Exclusion (M4, X2); Current limits (B8); Applications (P4)\n";
    try t.expect(std.mem.indexOf(u8, answer, expected) != null);
    const marker = try reference.run(language, t.allocator, .{ .query = "E_OWN_MARKER", .format = .text, .check_bodies = false });
    defer t.allocator.free(marker);
    try t.expect(std.mem.indexOf(u8, marker, "ownership rules: Escape (B2, B9, W2)\n") != null);
    const bytes = try uncheckedJson("E_SLICE_ESCAPES");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    const families = section(codeRecord(parsed.value, "E_SLICE_ESCAPES").?, "rule_families");
    try t.expectEqual(@as(usize, 3), families.len);
    try t.expectEqualStrings("Escape", stringAt(families[0], "family"));
    try t.expectEqualStrings("Exclusion", stringAt(families[1], "family"));
    try t.expectEqualStrings("Applications", stringAt(families[2], "family"));
}

fn checkDiagnosticRuleCounts(diagnostics: []const std.json.Value) !void {
    const ownership = @import("ownership_rules.zig");
    for (diagnostics) |record| {
        const code = stringAt(record, "code");
        try t.expectEqual(ownership.rulesFor(code).len, section(record, "rules").len);
    }
}

test "ownership reference JSON exposes exactly the canonical live code rule relation" {
    const ownership = @import("ownership_rules.zig");
    const bytes = try uncheckedJson("E_");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    const diagnostics = section(parsed.value, "diagnostics");
    for (ownership.entries) |entry| {
        const record = codeRecord(parsed.value, entry.code) orelse return error.TestUnexpectedResult;
        const selected = section(record, "rules");
        try t.expectEqual(entry.rules.len, selected.len);
        for (entry.rules, selected) |rule, actual| try t.expectEqualStrings(@tagName(rule), actual.string);
    }
    try checkDiagnosticRuleCounts(diagnostics);
    try t.expect(codeRecord(parsed.value, "E_SINGLE_OWNER_UNSUPPORTED") == null);
}

// spec-case: REFERENCE-CODES-1
test "reference finds codes by substring and reports a runtime trap and a lint rule" {
    const bytes = try json("shadow");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    try t.expect(codeRecord(parsed.value, "E_SHADOWING") != null);
    const traps = try json("R_LIST_BOUNDS");
    defer t.allocator.free(traps);
    var trap_root = try envelope(t.allocator, traps);
    defer trap_root.deinit();
    try t.expect(codeRecord(trap_root.value, "R_LIST_BOUNDS") != null);
    const lint = try json("L_DEAD_PRIVATE");
    defer t.allocator.free(lint);
    var lint_root = try envelope(t.allocator, lint);
    defer lint_root.deinit();
    try t.expect(codeRecord(lint_root.value, "L_DEAD_PRIVATE") != null);
}

/// Whether `entries` is strictly sorted by code and every guide is a `selka docs` topic.
fn indexIsWellFormed() bool {
    var previous: []const u8 = "";
    for (diagnostic_codes.entries) |entry| {
        if (!std.mem.lessThan(u8, previous, entry.code)) return false;
        previous = entry.code;
        if (entry.meaning.len == 0 or !isGuide(entry.guide)) return false;
    }
    return true;
}

/// Whether `name` is a topic `selka docs` prints.
fn isGuide(name: []const u8) bool {
    for (user_docs.topics) |topic| if (std.mem.eql(u8, topic.name, name)) return true;
    return false;
}

/// Whether the index has a row for `code`.
fn indexed(code: []const u8) bool {
    for (diagnostic_codes.entries) |entry| if (std.mem.eql(u8, entry.code, code)) return true;
    return false;
}

/// Append one line to `report` for each diagnostic code written as a string literal in one source
/// file that the index lacks. A code is `E_`, `W_`, `L_` or `R_` followed by capitals, digits and
/// underscores, between double quotes.
fn reportMissing(report: *std.ArrayList(u8), bytes: []const u8, path: []const u8) !void {
    var at: usize = 0;
    while (std.mem.indexOfScalarPos(u8, bytes, at, '"')) |quote| {
        at = quote + 1;
        if (at + 2 >= bytes.len or bytes[at + 1] != '_' or std.mem.indexOfScalar(u8, "EWLR", bytes[at]) == null) continue;
        var end = at + 2;
        while (end < bytes.len and (std.ascii.isUpper(bytes[end]) or std.ascii.isDigit(bytes[end]) or bytes[end] == '_')) end += 1;
        if (end >= bytes.len or bytes[end] != '"' or end - at < 4) continue;
        if (indexed(bytes[at..end])) continue;
        try report.print(t.allocator, "{s} is printed in {s} and has no row in src/diagnostic_codes.zig\n", .{ bytes[at..end], path });
    }
}

/// Whether `name` is a compiler source that can print a diagnostic code: a Zig or C file that is
/// not a test and not the index itself.
fn printsCodes(name: []const u8) bool {
    if (std.mem.eql(u8, name, "diagnostic_codes.zig")) return false;
    if (std.mem.endsWith(u8, name, "_test.zig") or std.mem.endsWith(u8, name, "_test.c")) return false;
    return std.mem.endsWith(u8, name, ".zig") or std.mem.endsWith(u8, name, ".c");
}

/// One line per printed diagnostic code under `src/` that the index lacks, owned by the caller.
fn unindexedCodes() ![]u8 {
    var directory = try std.Io.Dir.cwd().openDir(t.io, "src", .{ .iterate = true });
    defer directory.close(t.io);
    var walker = try directory.walk(t.allocator);
    defer walker.deinit();
    var report: std.ArrayList(u8) = .empty;
    errdefer report.deinit(t.allocator);
    while (try walker.next(t.io)) |entry| {
        if (entry.kind != .file or !printsCodes(entry.basename)) continue;
        const bytes = try entry.dir.readFileAlloc(t.io, entry.basename, t.allocator, .limited(16 * 1024 * 1024));
        defer t.allocator.free(bytes);
        try reportMissing(&report, bytes, entry.path);
    }
    return report.toOwnedSlice(t.allocator);
}

test "the recursive-copy warning is indexed with the memory guide (O4)" {
    var guide: []const u8 = "";
    for (diagnostic_codes.entries) |entry| {
        if (std.mem.eql(u8, entry.code, "W_COPY_IN_RECURSION")) guide = entry.guide;
    }
    try t.expectEqualStrings("memory", guide);
}

test "the checker's operand guard is indexed as a compiler defect" {
    var found: usize = 0;
    for (diagnostic_codes.entries) |entry| {
        if (std.mem.eql(u8, entry.code, "E_INTERNAL_OPERANDS")) found += 1;
    }
    try t.expectEqual(@as(usize, 1), found);
}

// spec-case: REFERENCE-CODES-1
test "the runtime traps of the pool, the group and the result wait are indexed with their guides" {
    var found: usize = 0;
    for (diagnostic_codes.entries) |entry| {
        if (std.mem.eql(u8, entry.code, "R_THREAD_START") or std.mem.eql(u8, entry.code, "R_TASK_ESCAPE") or std.mem.eql(u8, entry.code, "R_INTERNAL")) found += 1;
    }
    try t.expectEqual(@as(usize, 3), found);
}

// spec-case: REFERENCE-CODES-1
test "the typed-hole trap is indexed beside its compile-time refusal" {
    var found: usize = 0;
    for (diagnostic_codes.entries) |entry| {
        if (std.mem.eql(u8, entry.code, "R_TYPED_HOLE") or std.mem.eql(u8, entry.code, "E_TYPED_HOLE")) found += 1;
    }
    try t.expectEqual(@as(usize, 2), found);
}

// spec-case: REFERENCE-CODES-1
test "the take refusal for a type with no empty value is indexed once" {
    var found: usize = 0;
    for (diagnostic_codes.entries) |entry| {
        if (std.mem.eql(u8, entry.code, "E_TAKE_TYPE")) found += 1;
    }
    try t.expectEqual(@as(usize, 1), found);
}

/// How many index rows carry `code`.
fn rowsOf(code: []const u8) usize {
    var found: usize = 0;
    for (diagnostic_codes.entries) |entry| {
        if (std.mem.eql(u8, entry.code, code)) found += 1;
    }
    return found;
}

test "the traps only a bare target's runtime raises are indexed once each" {
    try t.expectEqual(@as(usize, 1), rowsOf("R_ABORT"));
    try t.expectEqual(@as(usize, 1), rowsOf("R_BARE_FAULT"));
    try t.expectEqual(@as(usize, 1), rowsOf("R_BARE_STACK"));
    try t.expectEqual(@as(usize, 1), rowsOf("R_BARE_UNSUPPORTED"));
}

// spec-case: REFERENCE-CODES-1
test "every diagnostic code the compiler prints has a sorted index row naming a real guide" {
    try t.expect(indexIsWellFormed());
    const missing = try unindexedCodes();
    defer t.allocator.free(missing);
    try t.expectEqualStrings("", missing);
}

test "reference explains release foundation diagnostics" {
    const bytes = try json("E_RELEASE");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    for ([_][]const u8{ "E_RELEASE_DECISION_INVALID", "E_RELEASE_DECISION_MISSING", "E_RELEASE_NO_BASELINE", "E_RELEASE_OVERVIEW_STALE", "E_RELEASE_REFERENCE_UNKNOWN", "E_RELEASE_STEP_FAILED" }) |code| {
        const record = codeRecord(parsed.value, code) orelse return error.TestUnexpectedResult;
        try t.expect(stringAt(record, "meaning").len > 20);
        try t.expectEqualStrings("release-docs", stringAt(record, "guide"));
    }
}

test "reference points every change review diagnostic at the change-review guide" {
    const bytes = try json("E_REVIEW");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    for ([_][]const u8{ "E_REVIEW_BASE_UNREADABLE", "E_REVIEW_DECISION_MISSING", "E_REVIEW_HEAD_UNREADABLE", "E_REVIEW_NOTE_INVALID", "E_REVIEW_SUMMARY_MISSING" }) |code| {
        const record = codeRecord(parsed.value, code) orelse return error.TestUnexpectedResult;
        try t.expect(stringAt(record, "meaning").len > 20);
        try t.expectEqualStrings("change-review", stringAt(record, "guide"));
    }
    // The note rule counts non-whitespace characters, not words, at its lower bound.
    const note = codeRecord(parsed.value, "E_REVIEW_NOTE_INVALID") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, stringAt(note, "meaning"), "under 40 non-whitespace characters") != null);
}

test "reference discovers checked documentation commands with live guide anchors" {
    for ([_][]const u8{ "overview", "release-init", "release-draft", "release-check", "release-cut" }) |slug| {
        const bytes = try uncheckedJson(slug);
        defer t.allocator.free(bytes);
        var parsed = try envelope(t.allocator, bytes);
        defer parsed.deinit();
        const feature = find(section(parsed.value, "features"), "slug", slug) orelse return error.TestUnexpectedResult;
        try t.expectEqualStrings("tooling", stringAt(feature, "kind"));
        try t.expect(std.mem.startsWith(u8, stringAt(feature, "doc"), "docs/tooling/release-docs.md#"));
        try t.expect(try docAnchorResolves(t.allocator, stringAt(feature, "doc")));
    }
}

test "reference explains stale interface files with the API guide" {
    const bytes = try json("E_INTERFACE_FILE_STALE");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    const record = codeRecord(parsed.value, "E_INTERFACE_FILE_STALE") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("api", stringAt(record, "guide"));
    try t.expect(std.mem.indexOf(u8, stringAt(record, "meaning"), "regenerate") != null);
}

/// How many lines an answer prints.
fn lineCount(bytes: []const u8) usize {
    return std.mem.count(u8, bytes, "\n");
}

/// Whether `haystack` holds `needle`.
fn has(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

/// Answer `query` as text and hold it to the short form: eight lines at most, with the call and the guide in it.
fn expectShortAnswer(query: []const u8, call: []const u8, guide: []const u8) !void {
    const answered = try text(query);
    defer t.allocator.free(answered);
    try t.expect(lineCount(answered) <= 8);
    try t.expect(has(answered, call));
    try t.expect(has(answered, guide));
    try t.expect(has(answered, "match=exact facts=1"));
}

// spec-case: REFERENCE-SIGNATURE-1
test "a module-qualified name answers with its call, its description and its guide in at most eight lines" {
    try expectShortAnswer("strings.split", "\nstrings.split(text: str, separator: str) -> str[]\n", "  guide: selka docs text\n");
    const answered = try text("strings.split");
    defer t.allocator.free(answered);
    try t.expect(has(answered, "\n  Split on `separator`, keeping every piece including empty ones.\n"));
    // The substring search is not run: no collection-method fact, no feature that mentions the name.
    try t.expect(!has(answered, "method split"));
    try t.expect(!has(answered, "feature "));
}

// spec-case: REFERENCE-SIGNATURE-2
test "a bare prelude name answers the same way, and a module-qualified type answers with its keyword" {
    try expectShortAnswer("len", "\nlen(value) -> int\n", "  guide: selka docs syntax\n");
    try expectShortAnswer("sorted", "\nsorted(values: T[]) -> T[]\n", "  guide: selka docs syntax\n");
    try expectShortAnswer("parse_int", "\nparse_int(text: str) -> int?\n", "  guide: selka docs text\n");
    try expectShortAnswer("strings.Error", "\nenum strings.Error\n", "  guide: selka docs text\n");
    try expectShortAnswer("lists.index_of", "\nlists.index_of(values: T[], value: T) -> int\n", "  guide: selka docs stdlib\n");
    try expectShortAnswer("process.SIGINT", "\nprocess.SIGINT: int = 2\n", "  guide: selka docs stdlib\n");
}

/// The position of the first line of `answered` that starts with `prefix`, or null.
fn lineStartingWith(answered: []const u8, prefix: []const u8) ?usize {
    var offset: usize = 0;
    var lines = std.mem.splitScalar(u8, answered, '\n');
    while (lines.next()) |line| : (offset += line.len + 1) {
        if (std.mem.startsWith(u8, line, prefix)) return offset;
    }
    return null;
}

/// How many lines of `answered` begin with two spaces: the signature lines of a module answer.
fn indentedLines(answered: []const u8) usize {
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, answered, '\n');
    while (lines.next()) |line| count += @intFromBool(std.mem.startsWith(u8, line, "  "));
    return count;
}

// spec-case: REFERENCE-SIGNATURE-3
test "a module's name lists its exported declarations, one signature per line, in source order" {
    const answered = try text("strings");
    defer t.allocator.free(answered);
    const bytes = try json("strings");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    const module = find(section(parsed.value, "answers"), "kind", "module") orelse return error.TestUnexpectedResult;
    const declared = module.object.get("declarations").?.array.items;
    try t.expectEqualStrings("text", stringAt(module, "guide"));
    try t.expect(declared.len > 50);
    // One indented line per declaration, and the order is the source's: `message` is declared before `letters`, which a
    // sorted listing would reverse.
    try t.expectEqual(declared.len, indentedLines(answered));
    try t.expectEqualStrings("strings.digits", stringAt(declared[0], "name"));
    try t.expect(lineStartingWith(answered, "  strings.message(").? < lineStartingWith(answered, "  strings.letters(").?);
    try t.expect(lineStartingWith(answered, "  strings.digits() -> str").? < lineStartingWith(answered, "  enum strings.Error").?);
    try t.expect(has(answered, "module strings: "));
}

// spec-case: REFERENCE-SIGNATURE-4
test "a qualified name no module declares answers with the nearest names of that module, at most three" {
    const answered = try text("strings.isdigit");
    defer t.allocator.free(answered);
    try t.expect(has(answered, "match=none facts=0"));
    try t.expect(has(answered, "no declaration strings.isdigit in module strings; nearest:\n  strings.is_digit(text: str) -> bool\n"));
    const bytes = try json("strings.splitlines");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    const nearest = find(section(parsed.value, "answers"), "kind", "nearest") orelse return error.TestUnexpectedResult;
    const candidates = nearest.object.get("candidates").?.array.items;
    try t.expectEqualStrings("strings", stringAt(nearest, "module"));
    try t.expect(candidates.len >= 1 and candidates.len <= 3);
    try t.expectEqualStrings("strings.lines", stringAt(candidates[0], "name"));
    try t.expect(find(candidates, "name", "strings.split") != null);
    // A name nothing resembles still points at the module.
    const lost = try text("strings.zzzzzzzz");
    defer t.allocator.free(lost);
    try t.expect(has(lost, "no declaration strings.zzzzzzzz in module strings\n"));
    try t.expect(has(lost, "selka reference --query strings"));
}

// spec-case: REFERENCE-SIGNATURE-5
test "the JSON envelope carries the same answers beside every field it had" {
    const bytes = try json("strings.split");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    try t.expectEqualStrings("strings.split", stringAt(parsed.value, "query"));
    try t.expectEqualStrings("exact", stringAt(parsed.value, "match"));
    try t.expectEqual(@as(usize, 1), integerAt(parsed.value, "count").?);
    const answers = section(parsed.value, "answers");
    try t.expectEqual(@as(usize, 1), answers.len);
    try t.expectEqualStrings("declaration", stringAt(answers[0], "kind"));
    try t.expectEqualStrings("strings.split", stringAt(answers[0], "name"));
    try t.expectEqualStrings("strings.split(text: str, separator: str) -> str[]", stringAt(answers[0], "call"));
    try t.expectEqualStrings("Split on `separator`, keeping every piece including empty ones.", stringAt(answers[0], "summary"));
    try t.expectEqualStrings("text", stringAt(answers[0], "guide"));
    // The declaration record keeps every field it had and adds the call form and the description.
    const record = find(section(parsed.value, "declarations"), "name", "strings::split") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("func(text:str,separator:str)->str[]", stringAt(record, "signature"));
    try t.expectEqualStrings("checked", stringAt(record, "analysis"));
    try t.expectEqualStrings("function", stringAt(record, "kind"));
    try t.expect(record.object.get("mutates") != null);
    try t.expectEqualStrings("strings.split(text: str, separator: str) -> str[]", stringAt(record, "call"));
    // A bare prelude name keeps its substring facts and adds the answer; an ordinary term has no answers.
    const prelude_bytes = try json("sorted");
    defer t.allocator.free(prelude_bytes);
    var prelude_parsed = try envelope(t.allocator, prelude_bytes);
    defer prelude_parsed.deinit();
    const prelude = find(section(prelude_parsed.value, "answers"), "kind", "prelude") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("sorted(values: T[]) -> T[]", stringAt(prelude, "call"));
    try t.expect(section(prelude_parsed.value, "features").len > 0);
    const plain = try json("standard-sort");
    defer t.allocator.free(plain);
    var plain_parsed = try envelope(t.allocator, plain);
    defer plain_parsed.deinit();
    try t.expectEqual(@as(usize, 0), section(plain_parsed.value, "answers").len);
}

/// Whether every prelude row names a prelude function and a real guide, in alphabetical order, with a call that names it.
fn preludeTableIsSound() bool {
    var previous: []const u8 = "";
    for (reference_text.prelude) |row| {
        if (!std.mem.lessThan(u8, previous, row.name)) return false;
        previous = row.name;
        if (prelude_names.find(row.name) == null) return false;
        if (!hasTopic(row.guide)) return false;
        if (std.mem.indexOf(u8, row.call, row.name) == null) return false;
        if (row.summary.len == 0) return false;
    }
    return true;
}

/// Whether `name` is a topic `selka docs` prints.
fn hasTopic(name: []const u8) bool {
    for (user_docs.topics) |topic| if (std.mem.eql(u8, topic.name, name)) return true;
    return false;
}

/// Whether every module with a guide of its own is a standard module and every guide a topic.
fn moduleGuidesAreSound() bool {
    for (reference_text.module_guides) |row| {
        if (!hasTopic(row.guide)) return false;
        var known = false;
        for (standard_library.paths) |path| known = known or std.mem.eql(u8, product.chopSource(path), row.module);
        if (!known) return false;
    }
    return hasTopic(reference_text.default_module_guide);
}

// spec-case: REFERENCE-SIGNATURE-6
test "the curated prelude rows and module guides name real prelude functions, modules and guides" {
    try t.expect(preludeTableIsSound());
    try t.expect(moduleGuidesAreSound());
    try t.expectEqualStrings("text", reference_text.moduleGuide("strings"));
    try t.expectEqualStrings("stdlib", reference_text.moduleGuide("json"));
}

/// Whether every standard module that has a topic of its own (a topic named like the module) names that topic as its guide.
fn modulesWithTopicsNameThem() bool {
    for (standard_library.paths) |path| {
        const module = product.chopSource(path);
        if (hasTopic(module) and !std.mem.eql(u8, reference_text.moduleGuide(module), module)) return false;
    }
    return true;
}

/// Whether every `guide: selka docs NAME` line of `answered` names a topic.
fn guideLinesNameTopics(answered: []const u8) bool {
    const prefix = "  guide: selka docs ";
    var lines = std.mem.splitScalar(u8, answered, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, prefix)) continue;
        const name = line[prefix.len..][0 .. std.mem.indexOfScalar(u8, line[prefix.len..], ' ') orelse line.len - prefix.len];
        if (!hasTopic(name)) return false;
    }
    return true;
}

// spec-case: REFERENCE-SIGNATURE-6
test "a module with a topic of its own names it as its guide, not the standard-library page" {
    try t.expect(modulesWithTopicsNameThem());
    try t.expectEqualStrings("logging", reference_text.moduleGuide("logging"));
    const answered = try text("logging.new");
    defer t.allocator.free(answered);
    try t.expect(has(answered, "  guide: selka docs logging\n"));
    try t.expect(!has(answered, "selka docs stdlib"));
    const listing = try text("logging");
    defer t.allocator.free(listing);
    try t.expect(has(listing, "module logging: 22 declarations (guide: selka docs logging)"));
}

/// The file the topic table says `selka docs NAME` prints.
fn topicPath(name: []const u8) []const u8 {
    for (user_docs.topics) |topic| if (std.mem.eql(u8, topic.name, name)) return topic.path;
    return "";
}

// spec-case: REFERENCE-SIGNATURE-6
test "a feature names the topic that prints its page and section, and no path that selka docs cannot print" {
    const packages = try text("local-locked-packages");
    defer t.allocator.free(packages);
    try t.expect(has(packages, "\n  guide: selka docs packages (section #local-locked-packages)\n"));
    const page_path = topicPath("packages");
    try t.expect(!has(packages, page_path));
    // Every feature answers: the manifest's pages with no topic leave the guide line out, and the rest name a topic.
    const everything = try text(page_path[0..std.mem.indexOfScalar(u8, page_path, '/').?]);
    defer t.allocator.free(everything);
    try t.expect(has(everything, "\nfeature local-locked-packages\n"));
    try t.expect(guideLinesNameTopics(everything));
    try t.expect(!has(everything, "\n  doc: "));
}

// spec-case: REFERENCE-SIGNATURE-6
test "the integer helpers answer with their call and the integer-operations guide" {
    try expectShortAnswer("wrapping_add", "\nwrapping_add(a: T, b: T) -> T\n", "  guide: selka docs integer-operations\n");
    try expectShortAnswer("shift_right", "\nshift_right(value: T, count: T) -> T\n", "  guide: selka docs integer-operations\n");
    try expectShortAnswer("saturating_mul", "\nsaturating_mul(a: T, b: T) -> T\n", "  guide: selka docs integer-operations\n");
}

/// Whether every exported declaration of every standard module is found in its module's source, so none answers with the
/// listing's compact signature instead of the source's call form.
fn everyDeclarationIsRead() !bool {
    const bytes = try json("::");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    for (standard_library.paths) |path| {
        const stem = product.chopSource(path);
        const entries = try reference_source.scan(arena.allocator(), stem, standard_library.source(path).?);
        for (section(parsed.value, "declarations")) |declaration| {
            const name = stringAt(declaration, "name");
            if (!std.mem.startsWith(u8, name, stem) or !std.mem.startsWith(u8, name[stem.len..], "::")) continue;
            if (reference_source.lookup(entries, name[stem.len + 2 ..]) == null) return false;
        }
    }
    return true;
}

// spec-case: REFERENCE-SIGNATURE-7
test "every exported standard-library declaration has a call form read from its module's source" {
    try t.expect(try everyDeclarationIsRead());
}

// spec-case: REFERENCE-SIGNATURE-8
test "the source scan reads call forms, constants, types, attributes and descriptions" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const source =
        \\# One line, e.g. as a test. A second sentence.
        \\public builtin func pick[T: copy](values: T[], index: int = 0) -> T? fails str
        \\
        \\# Over lines.
        \\public func wide(
        \\    first: int,
        \\    second: int,
        \\) -> int:
        \\    return first
        \\
        \\# A limit.
        \\public const LIMIT: int = 8
        \\
        \\# A shape that
        \\# spans two comment lines.
        \\@sealed
        \\public record Box[T]:
        \\    value: T
        \\
        \\public func undocumented() -> int:
        \\    return 1
    ;
    const entries = try reference_source.scan(arena.allocator(), "demo", source);
    try t.expectEqual(@as(usize, 5), entries.len);
    const pick = reference_source.lookup(entries, "pick").?;
    try t.expectEqualStrings("demo.pick(values: T[], index: int = 0) -> T? fails str", pick.call);
    try t.expectEqualStrings("One line, e.g. as a test.", pick.summary);
    try t.expectEqual(@as(usize, 1), pick.line);
    try t.expectEqualStrings("demo.wide(first: int, second: int) -> int", reference_source.lookup(entries, "wide").?.call);
    try t.expectEqualStrings("demo.LIMIT: int = 8", reference_source.lookup(entries, "LIMIT").?.call);
    const box = reference_source.lookup(entries, "Box").?;
    try t.expectEqualStrings("record demo.Box[T]", box.call);
    try t.expectEqualStrings("A shape that spans two comment lines.", box.summary);
    try t.expectEqualStrings("", reference_source.lookup(entries, "undocumented").?.summary);
    try t.expect(reference_source.lookup(entries, "missing") == null);
}

/// Whether a summary names the method form, which the compiler has refused since W13.
fn namesMethodForm(summary: []const u8) bool {
    return has(summary, "str methods") or has(summary, ", methods,") or has(summary, "receiver's own table") or has(summary, "method such as");
}

/// Whether any `selka docs` topic summary or curated entry still describes a method form.
fn anySummaryNamesMethodForm() bool {
    for (user_docs.topics) |topic| if (namesMethodForm(topic.summary)) return true;
    for (reference_text.entries) |entry| if (namesMethodForm(entry.summary) or namesMethodForm(entry.python)) return true;
    return false;
}

/// The summary of one curated entry, or an empty string.
fn entrySummary(id: []const u8) []const u8 {
    for (reference_text.entries) |entry| if (std.mem.eql(u8, entry.id, id)) return entry.summary;
    return "";
}

/// The summary of one `selka docs` topic, or an empty string.
fn topicSummary(name: []const u8) []const u8 {
    for (user_docs.topics) |topic| if (std.mem.eql(u8, topic.name, name)) return topic.summary;
    return "";
}

// spec-case: REFERENCE-SIGNATURE-9
test "no curated summary or guide line describes a method form the compiler refuses since W13" {
    try t.expect(!anySummaryNamesMethodForm());
    // `text.split(",")` and `xs.append(1)` are refused with E_METHOD_REMOVED; the replacement spellings are named instead.
    try t.expect(has(entrySummary("core-builtin-spellings"), "E_METHOD_REMOVED"));
    try t.expect(has(entrySummary("core-builtin-spellings"), "strings.split(text, \",\")"));
    try t.expect(has(entrySummary("core-builtin-spellings"), "append(mut xs, x)"));
    try t.expect(has(topicSummary("text"), "strings.split"));
    try t.expect(has(topicSummary("sets"), "`sets` functions"));
    try t.expect(!has(entrySummary("capability-parameters"), "effect set"));
    // The collection-method facts say so too: the table lists the operation, and the method spelling is refused.
    const answered = try text("pop");
    defer t.allocator.free(answered);
    try t.expect(has(answered, "\nmethod pop\n"));
    try t.expect(has(answered, "\n  method form: refused (E_METHOD_REMOVED); write the function"));
    const bytes = try json("pop");
    defer t.allocator.free(bytes);
    var parsed = try envelope(t.allocator, bytes);
    defer parsed.deinit();
    const method = find(section(parsed.value, "methods"), "name", "pop") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("refused", stringAt(method, "method_form"));
}

/// The standard modules whose opening comment is their first declaration's own description: it runs straight into that
/// declaration and says nothing of the module as a whole. Every other module's header is set off by a blank line or an
/// `import`, so it can never become a declaration's description (FR34).
const headerless = [_][]const u8{ "base64", "environment", "lists", "math", "memo", "options", "parallel", "pool", "random", "streams" };

/// The first sentence of the comment block that opens a module's source, or an empty string when the source opens with code.
fn headerSentence(arena: std.mem.Allocator, module: []const u8) error{OutOfMemory}![]const u8 {
    var joined: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, module, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "#")) break;
        const body = std.mem.trim(u8, line[1..], " \t\r");
        if (body.len == 0) continue;
        if (joined.items.len != 0) try joined.append(arena, ' ');
        try joined.appendSlice(arena, body);
    }
    return reference_source.firstSentence(joined.items);
}

/// The first declaration, as `module.name`, whose description is its module's header sentence; null when none is.
fn firstDescribedByHeader(arena: std.mem.Allocator) error{OutOfMemory}!?[]const u8 {
    for (standard_library.paths) |path| {
        const stem = product.chopSource(path);
        if (contains(&headerless, stem)) continue;
        const module = standard_library.source(path).?;
        const header = try headerSentence(arena, module);
        if (header.len == 0) continue;
        for (try reference_source.scan(arena, stem, module)) |entry| {
            if (!std.mem.eql(u8, entry.found.summary, header)) continue;
            const named = try std.fmt.allocPrint(arena, "{s}.{s}", .{ stem, entry.name });
            return named;
        }
    }
    return null;
}

// FR34 item 3: `selka reference --query buffers.empty` answered "The byte-buffer module: ..." because the header ran into the
// first function's comment. A module's header is set off from its first declaration, in all 38 modules.
test "no standard-library declaration is described by its module's header sentence (FR34)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expectEqual(@as(?[]const u8, null), try firstDescribedByHeader(arena.allocator()));
}

test "a module listed as headerless opens with its first declaration's own description (FR34)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    for (headerless) |stem| {
        const module = standard_library.source(try std.fmt.allocPrint(arena.allocator(), "{s}.selka", .{stem})).?;
        const entries = try reference_source.scan(arena.allocator(), stem, module);
        try t.expectEqualStrings(try headerSentence(arena.allocator(), module), entries[0].found.summary);
    }
}

test "buffers.empty and sets.add answer with their own descriptions (FR34)" {
    const empty = try text("buffers.empty");
    defer t.allocator.free(empty);
    try t.expect(has(empty, "  An empty buffer.\n"));
    try t.expect(!has(empty, "byte-buffer module"));
    const add = try text("sets.add");
    defer t.allocator.free(add);
    try t.expect(has(add, "  Add `value` to the set."));
    try t.expect(!has(add, "set module"));
}

test "the comment that opens a module ends at its last empty comment line, and the declaration's own comment follows (FR34)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const source =
        \\# The demo module: two words.
        \\# Its header goes on.
        \\#
        \\# Its header goes on after a paragraph.
        \\#
        \\# One word. Another sentence.
        \\public func first() -> int:
        \\    return 1
        \\
        \\
        \\# The second word.
        \\#
        \\# A longer note on it.
        \\public func second() -> int:
        \\    return 2
    ;
    const entries = try reference_source.scan(arena.allocator(), "demo", source);
    try t.expectEqualStrings("One word.", reference_source.lookup(entries, "first").?.summary);
    // Only the comment that opens the file is a header; a later declaration's comment is read from its first line.
    try t.expectEqualStrings("The second word.", reference_source.lookup(entries, "second").?.summary);
}

// The `simd` topic's summary says what the guide covers: it documents integer lanes and bool masks beside the float ones,
// so a summary of "lanes of one float type" sent integer-lane readers elsewhere.
test "the simd topic's summary names the integer and mask lanes the guide documents" {
    try t.expect(has(topicSummary("simd"), "integer"));
    try t.expect(has(topicSummary("simd"), "mask"));
    try t.expect(!has(topicSummary("simd"), "one float type"));
}
