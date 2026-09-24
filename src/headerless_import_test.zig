//! A headerless script may import compiler-embedded standard modules and stay a
//! single unit; importing a project module still needs the `module` declaration.
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
    \\def main() -> i64:
    \\    return 0
;
const project_import =
    \\import helper
    \\
    \\def main() -> i64:
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

/// The code and location of the one diagnostic a rejected file reports.
const Failure = struct { code: []const u8, line: usize, column: usize };

/// Parse one module program that must be rejected, answering its first
/// diagnostic's code and location.
fn moduleFailure(arena: *std.heap.ArenaAllocator, bytes: []const u8) !Failure {
    const allocator = arena.allocator();
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    const src = try source.Source.init(allocator, "script.my", bytes);
    const tokens = try lexer.lex(allocator, bytes, &sink);
    var p: parser.Parser = .{ .src = src, .storage = arena.allocator(), .tokens = tokens, .sink = &sink };
    try t.expectError(error.SourceError, p.parseModule());
    const first = sink.items.items[0];
    const at = src.locate(first.span.start);
    return .{ .code = first.code, .line = at.line, .column = at.column };
}

/// Load `entry` from an in-memory project that must be rejected, answering the
/// diagnostic that stopped it.
fn loadFailure(files: *Files, entry: []const u8) !Failure {
    var loaded = project.Project.init(t.allocator);
    defer loaded.deinit();
    try t.expectError(error.SourceError, loaded.load(files.provider(), entry, .{}));
    const problem = loaded.problem.?;
    const at = loaded.modules.items[problem.site.module].src.locate(problem.site.span.start);
    return .{ .code = problem.code, .line = at.line, .column = at.column };
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
test "a headerless file that needs a project module keeps the module header rule" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const headerless = try moduleFailure(&arena, project_import);
    try t.expectEqualStrings("E_MODULE_HEADER", headerless.code);
    try t.expectEqual(@as(usize, 1), headerless.line);
    try t.expectEqual(@as(usize, 1), headerless.column);
    var files: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes = project_import },
        .{ .path = "helper.my", .bytes = "module helper\n" },
    } };
    const unimported = try loadFailure(&files, "main");
    try t.expectEqualStrings("E_MODULE_HEADER", unimported.code);
    try t.expectEqual(@as(usize, 1), unimported.line);
    try t.expectEqual(@as(usize, 1), unimported.column);
    var imported: Files = .{ .entries = &.{
        .{ .path = "main.my", .bytes = "module main\nimport helper\n" },
        .{ .path = "helper.my", .bytes = script },
    } };
    const nested = try loadFailure(&imported, "main");
    try t.expectEqualStrings("E_MODULE_HEADER", nested.code);
    try t.expectEqual(@as(usize, 1), nested.line);
    try t.expectEqual(@as(usize, 1), nested.column);
    var declarations: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = "def main() -> i64:\n    return 0\n" }} };
    const declared = try loadFailure(&declarations, "main");
    try t.expectEqualStrings("E_MODULE_HEADER", declared.code);
    try t.expectEqual(@as(usize, 1), declared.line);
    try t.expectEqual(@as(usize, 1), declared.column);
}

// spec: HEADERLESS-STD-IMPORT-HINT-1
test "a headerless script importing a non-standard module is told which module and what is standard" {
    var files: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = "import math\nimport heapq\n\ndef main() -> int:\n    return 0\n" }} };
    var loaded = project.Project.init(t.allocator);
    defer loaded.deinit();
    try t.expectError(error.SourceError, loaded.load(files.provider(), "main", .{}));
    const problem = loaded.problem.?;
    try t.expectEqualStrings("E_MODULE_HEADER", problem.code);
    try t.expect(std.mem.startsWith(u8, problem.message, "`heapq` is not a standard module (base64, byte_builder, hex, json, math,"));
    try t.expect(std.mem.endsWith(u8, problem.message, "start this file with `module main`"));
    try t.expectEqual(@as(usize, 0), problem.site.span.start);
}

// The fixture provider is what makes the loader tests above mean anything, so
// its own refusals are exercised too: a missing path and an oversized file.
test "the in-memory provider reports a missing path and an oversized file" {
    var files: Files = .{ .entries = &.{.{ .path = "small.my", .bytes = "module small\n" }} };
    var provider = files.provider();
    try t.expectError(error.NotFound, provider.read(provider.context, t.allocator, "missing.my", 64));
    try t.expectError(error.TooLarge, provider.read(provider.context, t.allocator, "small.my", 4));
}
