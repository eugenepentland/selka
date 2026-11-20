//! Filesystem integration for the shared checked-docs project model.
const std = @import("std");
const t = std.testing;
const loader = @import("release_project_load.zig");
const api = @import("api_diff.zig");

test "O3 release loader preserves Core R4 and its rendered rule without checking a body" {
    const allocator = t.allocator;
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "selka.json", .data = "{\"version\":2}" });
    try temporary.dir.writeFile(t.io, .{
        .sub_path = "main.selka",
        .data = "public func part(a: str) -> str from missing:\n    return unknown_body()\nfunc main() -> int:\n    return 0\n",
    });
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", allocator);
    defer allocator.free(root);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: loader.Failure = .{};
    try t.expectError(error.SourceError, loader.loadWith(a, t.io, root, &failure));
    try t.expectEqualStrings("main.selka", failure.path);
    try t.expectEqualStrings("E_BORROW_SOURCE", failure.code);
    try t.expectEqual(@import("diagnostic.zig").Rule.R4, failure.rule.?);
    try t.expectEqualStrings("  note: ownership rule R4\n", try failure.ruleNote(a));
    var report: @import("release_report.zig").Report = .{ .allocator = a };
    defer report.deinit();
    try report.atRule(failure.code, .{ .path = failure.path, .line = failure.line, .column = failure.column }, failure.message, failure.rule);
    const record = report.findings.items[0].record.object.get("diagnostic").?.object;
    try t.expectEqualStrings("E_BORROW_SOURCE", record.get("code").?.string);
    try t.expectEqualStrings("R4", record.get("rule").?.string);
}

fn fixture(dir: std.Io.Dir) !void {
    const io = t.io;
    try dir.createDirPath(io, "build");
    try dir.createDirPath(io, ".hidden");
    try dir.createDirPath(io, "vendor");
    try dir.writeFile(io, .{ .sub_path = "selka.json", .data = "{\"version\":2,\"release\":{\"entries\":[\"main.selka\",\"other.selka\"],\"exclude\":[\"vendor\"]}}" });
    try dir.writeFile(io, .{ .sub_path = "main.selka", .data = "import dep\nimport math\n\nfunc main() -> int:\n    return wrong_type\n" });
    try dir.writeFile(io, .{ .sub_path = "other.selka", .data = "public const label: int = 3\n" });
    try dir.writeFile(io, .{ .sub_path = "dep.selka", .data = "public func value() -> int:\n    return 1\n\nfunc private_helper() -> int:\n    return 2\n" });
    try dir.writeFile(io, .{ .sub_path = "dep_test.selka", .data = "import dep\nimport extra\n\npublic func test_value() -> bool:\n    return dep.value() == 1\n" });
    try dir.writeFile(io, .{ .sub_path = "extra.selka", .data = "public record Extra:\n    value: int\n" });
    try dir.writeFile(io, .{ .sub_path = "examples.selka", .data = "public func answer() -> int:\n    \"\"\"An example without a test.\n\n    >>> answer()\n    42\n    \"\"\"\n    return 42\n" });
    try dir.writeFile(io, .{ .sub_path = "build/broken.selka", .data = "public func test_broken(\n" });
    try dir.writeFile(io, .{ .sub_path = ".hidden/broken.selka", .data = "public func test_broken(\n" });
    try dir.writeFile(io, .{ .sub_path = "vendor/broken.selka", .data = "public func test_broken(\n" });
    try dir.writeFile(io, .{ .sub_path = "unused.selka", .data = "public func unused() -> int:\n    return 99\n" });
    try dir.writeFile(io, .{ .sub_path = "nested_marker.selka", .data = "public func nested() -> int:\n    \"\"\"A prompt indented inside prose.\n    prose\n      >>> nested()\n      42\n    \"\"\"\n    return 42\n" });
}

test "release project loader unites roots and snapshots public declarations without checking bodies" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try fixture(temporary.dir);
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var loaded = try loader.load(t.allocator, t.io, root);
    defer loaded.deinit();
    try t.expectEqual(@as(usize, 5), loaded.modules.len);
    try t.expectEqual(@as(usize, 2), loaded.selection.entries.len);
    try t.expectEqual(@as(usize, 2), loaded.selection.test_roots.len);
    const bytes = try api.snapshotPublic(t.allocator, loaded.index, loaded.modules);
    defer t.allocator.free(bytes);
    try t.expect(std.mem.indexOf(u8, bytes, "dep::value") != null);
    try t.expect(std.mem.indexOf(u8, bytes, "extra::Extra") != null);
    try t.expect(std.mem.indexOf(u8, bytes, "examples::answer") != null);
    try t.expect(std.mem.indexOf(u8, bytes, "private_helper") == null);
    try t.expect(std.mem.indexOf(u8, bytes, "dep_test::") == null);
    try t.expect(std.mem.indexOf(u8, bytes, "unused::") == null);
    try t.expect(std.mem.indexOf(u8, bytes, "nested_marker::") == null);
    try t.expect(std.mem.indexOf(u8, bytes, root) == null);
}

test "release project loader accepts standalone files and reports invalid entries" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "entry.selka", .data = "public func value() -> int:\n    return 1\n" });
    const entry = try temporary.dir.realPathFileAlloc(t.io, "entry.selka", t.allocator);
    defer t.allocator.free(entry);
    var loaded = try loader.load(t.allocator, t.io, entry);
    defer loaded.deinit();
    try t.expectEqualStrings("entry.selka", loaded.selection.entries[0]);
    try t.expectEqual(@as(usize, 1), loaded.modules.len);
    try t.expectError(error.HostIo, loader.load(t.allocator, t.io, "does-not-exist-release-project.selka"));
}

test "release project loader rejects malformed nonexcluded test roots" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try fixture(temporary.dir);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "broken_test.selka", .data = "public func test_broken(\n" });
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    try t.expectError(error.SourceError, loader.load(t.allocator, t.io, root));
}

test "release project loader honors configured file budget during discovery" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const padding = try t.allocator.alloc(u8, 4 * 1024 * 1024);
    defer t.allocator.free(padding);
    @memset(padding, 'x');
    const bytes = try std.mem.concat(t.allocator, u8, &.{ "# ", padding, "\nfunc main() -> int:\n    return 0\n" });
    defer t.allocator.free(bytes);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "main.selka", .data = bytes });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "selka.json", .data = "{\"version\":2,\"budgets\":{\"max_file_bytes\":6291456}}" });
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var loaded = try loader.load(t.allocator, t.io, root);
    defer loaded.deinit();
    try t.expectEqual(@as(usize, 1), loaded.modules.len);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "selka.json", .data = "{\"version\":2}" });
    try t.expectError(error.HostIo, loader.load(t.allocator, t.io, root));
}

test "release project loader reports a declaration failure's file and position" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "selka.json", .data = "{\"version\":2}" });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "main.selka", .data = "func main() -> int:\n    return 0\n" });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "repro_helper.selka", .data = "def old_syntax(:\nfunc test_old() -> bool:\n    return True\n" });
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var failure: loader.Failure = .{};
    try t.expectError(error.SourceError, loader.loadWith(arena.allocator(), t.io, root, &failure));
    try t.expect(failure.present);
    try t.expectEqualStrings("repro_helper.selka", failure.path);
    try t.expectEqual(@as(usize, 1), failure.line);
    try t.expectEqual(@as(usize, 16), failure.column);
    try t.expectEqualStrings("E_SYNTAX", failure.code);
    try t.expect(std.mem.indexOf(u8, failure.message, "unexpected token") != null);
}

test "release project loader reports a discovery parse failure's file and position" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "selka.json", .data = "{\"version\":2}" });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "main.selka", .data = "func main() -> int:\n    return 0\n" });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "bad_docs.selka", .data = "# >>> value()\npublic func bad(:\n" });
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var failure: loader.Failure = .{};
    try t.expectError(error.SourceError, loader.loadWith(arena.allocator(), t.io, root, &failure));
    try t.expect(failure.present);
    try t.expectEqualStrings("bad_docs.selka", failure.path);
    try t.expectEqual(@as(usize, 2), failure.line);
}

test "release project discovery reports a parse failure's file and position" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var failure: loader.Failure = .{};
    const scan: loader.Scan = .{ .a = arena.allocator(), .allocator = arena.allocator(), .io = t.io, .root = root, .options = .{}, .max_bytes = 1 << 20, .source = &failure };
    try t.expectError(error.SourceError, loader.discoveryFlags(scan, "bad_docs.selka", "# >>> value()\npublic func bad(:\n"));
    try t.expect(failure.present);
    try t.expectEqualStrings("bad_docs.selka", failure.path);
    try t.expectEqual(@as(usize, 2), failure.line);
}
