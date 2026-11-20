//! The reader inventory: every file under `src/` that reads the merged syntax tables is on the audited list of `lazy_readers.zig`.
const std = @import("std");
const readers = @import("lazy_readers.zig");
const t = std.testing;

fn sourcesUnderSrc(arena: std.mem.Allocator) ![]readers.File {
    var directory = try std.Io.Dir.cwd().openDir(t.io, "src", .{ .iterate = true });
    defer directory.close(t.io);
    var walker = try directory.walk(arena);
    defer walker.deinit();
    var files: std.ArrayList(readers.File) = .empty;
    while (try walker.next(t.io)) |file| {
        if (file.kind != .file or !std.mem.endsWith(u8, file.basename, ".zig") or std.mem.endsWith(u8, file.basename, "_test.zig")) continue;
        const bytes = try file.dir.readFileAlloc(t.io, file.basename, arena, .limited(16 * 1024 * 1024));
        try files.append(arena, .{ .path = try std.fmt.allocPrint(arena, "src/{s}", .{file.path}), .bytes = bytes });
    }
    return files.items;
}

fn reported(entries: []const readers.Entry, files: []const readers.File) ![]u8 {
    return readers.check(t.allocator, entries, files);
}

test "every file under src that reads the merged syntax tables is audited, with a reason that holds" {
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    const files = try sourcesUnderSrc(arena.allocator());
    const found = try reported(&readers.audited, files);
    defer t.allocator.free(found);
    try t.expectEqualStrings("", found);
    try t.expect(files.len > 100);
    // The `@linear` rules read the checker's syntax tables, as every checker internal does (D-FFI-11).
    var linear_audited = false;
    for (readers.audited) |entry| linear_audited = linear_audited or std.mem.eql(u8, entry.path, "src/linear_rules.zig");
    try t.expect(linear_audited);
}

test "a new file that reads the tables without an audit entry is reported by name" {
    const files = [_]readers.File{.{ .path = "src/new_pass.zig", .bytes = "const n = program.nodes.items[0];" }};
    const found = try reported(&.{}, &files);
    defer t.allocator.free(found);
    try t.expect(std.mem.indexOf(u8, found, "src/new_pass.zig: reads the syntax tables and is not audited") != null);
}

test "the rule finds the list spellings and an ast field, and nothing else" {
    try t.expect(readers.readsTables("x.statements.items[0]"));
    try t.expect(readers.readsTables("const ast = @import(\"ast.zig\");\nconst n = program.nodes[0];"));
    try t.expect(readers.readsTables("const a = @import(\"../ast.zig\");\nreturn p.statements;"));
    try t.expect(!readers.readsTables("const ast = @import(\"ast.zig\");\nconst n = program.node_count;"));
    try t.expect(!readers.readsTables("const n = program.nodes[0];"));
    try t.expect(!readers.readsTables("const ast = @import(\"ast.zig\");\nconst n = program.nodes_total;"));
}

test "an entry that is stale, hookless, unexplained, duplicated or out of order is reported" {
    const reading = "const n = program.nodes.items[0];";
    const files = [_]readers.File{
        .{ .path = "src/a.zig", .bytes = reading },
        .{ .path = "src/b.zig", .bytes = reading },
        .{ .path = "src/c.zig", .bytes = "const unrelated = 1;" },
    };
    const entries = [_]readers.Entry{
        .{ .path = "src/b.zig", .safety = .hooked, .via = "calls ast.ensureBody before it reads a body" },
        .{ .path = "src/a.zig", .safety = .checker, .via = "" },
        .{ .path = "src/a.zig", .safety = .checker, .via = "a checker internal, entered after the body is filled" },
        .{ .path = "src/c.zig", .safety = .eager, .via = "a command that completes the program in full" },
        .{ .path = "src/d.zig", .safety = .eager, .via = "a command that completes the program in full" },
    };
    const found = try reported(&entries, &files);
    defer t.allocator.free(found);
    try t.expect(std.mem.indexOf(u8, found, "src/b.zig: audited as hooked but calls no ast.ensure* or scanAt hook") != null);
    try t.expect(std.mem.indexOf(u8, found, "src/a.zig: the audit names no hook or path") != null);
    try t.expect(std.mem.indexOf(u8, found, "src/a.zig: audited out of order or twice") != null);
    try t.expect(std.mem.indexOf(u8, found, "src/c.zig: audited but no longer reads the syntax tables") != null);
    try t.expect(std.mem.indexOf(u8, found, "src/d.zig: audited but not found under src/") != null);
}

test "a hooked entry that calls a hook, and a file that defines them, pass" {
    try t.expect(readers.callsHook("try ast.ensureBody(program, root);"));
    try t.expect(readers.callsHook("try @import(\"ast.zig\").ensureAll(program);"));
    try t.expect(readers.callsHook("const around = try ast.scanAt(syntax, at);"));
    try t.expect(readers.callsHook("pub fn ensureBody(program: Program) void {}"));
    try t.expect(!readers.callsHook("fn scanAttributeWaivers() void {}"));
}

/// How a source file is audited, or null when the list does not name it.
fn auditedSafety(path: []const u8) ?readers.Safety {
    for (readers.audited) |entry| if (std.mem.eql(u8, entry.path, path)) return entry.safety;
    return null;
}

test "the formatter's safety net is audited as a reader of two complete parses" {
    try t.expectEqual(@as(?readers.Safety, .fresh_parse), auditedSafety("src/format_verify.zig"));
    try t.expectEqual(@as(?readers.Safety, null), auditedSafety("src/display_name.zig"));
}

fn auditedAs(path: []const u8, safety: readers.Safety) bool {
    for (readers.audited) |entry| if (std.mem.eql(u8, entry.path, path)) return entry.safety == safety;
    return false;
}

test "the checks of case_name, cases and from_name are audited as checker internals" {
    try t.expect(auditedAs("src/enum_cases.zig", .checker));
    try t.expect(!auditedAs("src/enum_cases_missing.zig", .checker));
}
