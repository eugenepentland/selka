//! File paths determine module identities for standard and project imports.
const std = @import("std");
const t = std.testing;
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const project = @import("project.zig");
const source = @import("source.zig");

const script =
    \\import strings
    \\
    \\func main() -> i64:
    \\    return 0
;
const project_import =
    \\import helper
    \\
    \\func main() -> i64:
    \\    return 0
;

const File = struct { path: []const u8, bytes: []const u8 };
/// In-memory provider: the loader reads exactly the entries a test declares.
const Files = struct {
    entries: []const File,

    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        for (self.entries) |file| {
            if (!std.mem.eql(u8, file.path, path)) continue;
            if (file.bytes.len > limit) return error.TooLarge;
            return allocator.dupe(u8, file.bytes);
        }
        return error.NotFound;
    }

    fn provider(self: *Files) project.Provider {
        return .{ .context = self, .read = read };
    }
};

/// One parsed module program with the source its spans index.
const Parsed = struct { syntax: ast.Program, src: source.Source };

/// Parse one module program; the arena owns every returned span.
fn parseModuleSource(arena: *std.heap.ArenaAllocator, bytes: []const u8) !Parsed {
    const allocator = arena.allocator();
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    const src = try source.Source.init(allocator, "script.my", bytes);
    const tokens = try lexer.lex(allocator, bytes, &sink);
    var p: parser.Parser = .{ .src = src, .storage = arena.allocator(), .tokens = tokens, .sink = &sink };
    return .{ .syntax = try p.parseModule(), .src = src };
}

// spec: HEADERLESS-STD-IMPORT-1
test "a headerless entry imports an embedded standard module and stays one unit" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const parsed = try parseModuleSource(&arena, script);
    try t.expectEqual(@as(usize, 1), parsed.syntax.functions.len);
    try t.expectEqualStrings("main", parsed.src.text(parsed.syntax.functions[0].name));
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = script }} };
    var loaded = project.Project.init(t.allocator);
    defer loaded.deinit();
    try loaded.load(files.provider(), "main", .{});
    try t.expect(loaded.modules.items.len >= 2);
    try t.expectEqualStrings("main", loaded.modules.items[0].name);
    try t.expectEqualStrings("strings", loaded.modules.items[loaded.modules.items[0].imports[0].target].name);
    try t.expect(loaded.modules.items[0].header.body_start > 0);
}

// spec: HEADERLESS-STD-IMPORT-2
test "headerless project imports preserve deterministic path identities" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const parsed = try parseModuleSource(&arena, project_import);
    try t.expectEqual(@as(usize, 1), parsed.syntax.functions.len);
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes = project_import },
        .{ .path = "helper.my", .bytes = "func value() -> int:\n    return 1\n" },
    } };
    var loaded = project.Project.init(t.allocator);
    defer loaded.deinit();
    try loaded.load(files.provider(), "main", .{});
    const imported = loaded.modules.items[0].imports[0].target;
    try t.expectEqualStrings("helper", loaded.modules.items[imported].name);
    try t.expectEqualStrings("helper.my", loaded.modules.items[imported].src.path);
}

// spec: HEADERLESS-STD-IMPORT-HINT-1
test "redundant headers have a deletion fix and migration uses path identity" {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = "module copied_name\n" }} };
    var loaded = project.Project.init(t.allocator);
    defer loaded.deinit();
    try t.expectError(error.SourceError, loaded.load(files.provider(), "main", .{}));
    try t.expectEqualStrings("E_MODULE_HEADER", loaded.problem.?.code);
    try t.expectEqualStrings("", loaded.problem.?.fix.?.text);
    var migration = project.Project.init(t.allocator);
    defer migration.deinit();
    try migration.load(files.provider(), "main", .{ .legacy_headers = true });
    try t.expectEqualStrings("main", migration.modules.items[0].name);
}

// The fixture provider is what makes the loader tests above mean anything, so
// its own refusals are exercised too: a missing path and an oversized file.
test "the in-memory provider reports a missing path and an oversized file" {
    var files: Files = .{ .entries = &.{.{ .path = "small.my", .bytes = "module small\n" }} };
    var provider = files.provider();
    try t.expectError(error.NotFound, provider.read(provider.context, t.allocator, "missing.my", 64));
    try t.expectError(error.TooLarge, provider.read(provider.context, t.allocator, "small.my", 4));
}

// spec-case: HEADERLESS-STD-IMPORT-HINT-1
test "target module parsing repairs a redundant header while migration consumes it" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const bytes = "module copied_name\nfunc value() -> int:\n    return 1\n";
    const src = try source.Source.init(allocator, "helper.my", bytes);
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    const tokens = try lexer.lex(allocator, bytes, &sink);
    var target: parser.Parser = .{ .src = src, .storage = allocator, .tokens = tokens, .sink = &sink };
    try t.expectError(error.SourceError, target.parseModule());
    const fix = sink.items.items[0].provenance.fix.?.edit;
    try t.expectEqualStrings("", fix.text);
    var migration: parser.Parser = .{ .src = src, .storage = allocator, .tokens = tokens, .sink = &sink, .cursor = .{ .dialect = .migration } };
    const syntax = try migration.parseModule();
    try t.expectEqual(@as(usize, 1), syntax.functions.len);
}

// spec-case: HEADERLESS-STD-IMPORT-HINT-1
test "project parser diagnostics preserve declaration repair edits" {
    var files: Files = .{ .entries = &.{.{
        .path = "main.my",
        .bytes = "func main() -> int:\n    value = 1\n    return value\n",
    }} };
    var loaded = project.Project.init(t.allocator);
    defer loaded.deinit();
    try loaded.load(files.provider(), "main", .{});
    try t.expectError(error.SourceError, @import("interfaces.zig").build(&loaded));
    try t.expectEqualStrings("E_BINDING_DECLARATION", loaded.problem.?.code);
    try t.expect(loaded.problem.?.fix != null);
    try t.expect(loaded.problem.?.fix.?.text.len != 0);
}

// spec-case: HEADERLESS-STD-IMPORT-HINT-1
test "project parser retains every edit in a variant migration batch" {
    var files: Files = .{ .entries = &.{.{
        .path = "main.my",
        .bytes = "union Value:\n    boolean: bool,\n    integer: int\n",
    }} };
    var loaded = project.Project.init(t.allocator);
    defer loaded.deinit();
    try loaded.load(files.provider(), "main", .{});
    try t.expectError(error.SourceError, @import("interfaces.zig").build(&loaded));
    try t.expect(loaded.problem.?.fix != null);
    try t.expect(parserRepairCount(loaded.problem.?.recovered) >= 3);
}

fn parserRepairCount(problems: []const diagnostic.Diagnostic) usize {
    var edits: usize = 0;
    for (problems) |item| if (item.provenance.fix) |fix| {
        edits += fix.count();
    };
    return edits;
}
