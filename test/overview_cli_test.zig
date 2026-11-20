//! Public overview command contract, isolated paths and cache locations.
const std = @import("std");
const t = std.testing;
const fixture_path = "test/fixtures/release-docs/overview";
const files = [_][]const u8{
    "selka.json",                      "main.selka",               "catalog.selka",       "reader.selka", "catalog_test.selka",
    "decisions/unreleased/current.md", "decisions/0.1/initial.md", "release/history.txt",
};

fn fixture(dir: std.Io.Dir) ![:0]u8 {
    try dir.createDir(t.io, "project", .default_dir);
    var project = try dir.openDir(t.io, "project", .{});
    defer project.close(t.io);
    for (files) |path| {
        const input = try std.fs.path.join(t.allocator, &.{ fixture_path, path });
        defer t.allocator.free(input);
        const bytes = try std.Io.Dir.cwd().readFileAlloc(t.io, input, t.allocator, .unlimited);
        defer t.allocator.free(bytes);
        if (std.fs.path.dirname(path)) |parent| try project.createDirPath(t.io, parent);
        try project.writeFile(t.io, .{ .sub_path = path, .data = bytes });
    }
    return project.realPathFileAlloc(t.io, ".", t.allocator);
}

fn invoke(root: []const u8, options: []const []const u8, cache: []const u8) !std.process.RunResult {
    var env = try @import("test_paths").privateEnvironment(t.allocator);
    defer env.deinit();
    try env.put("SELKA_FRONTEND_CACHE", cache);
    const args = try std.mem.concat(t.allocator, []const u8, &.{ &.{ @import("test_paths").corePath(), "overview", root }, options });
    defer t.allocator.free(args);
    return std.process.run(t.allocator, t.io, .{ .argv = args, .environ_map = &env, .stdout_limit = .limited(4 * 1024 * 1024) });
}
fn release(result: std.process.RunResult) void {
    t.allocator.free(result.stdout);
    t.allocator.free(result.stderr);
}

fn read(root: []const u8) ![]u8 {
    return readAt(root, "OVERVIEW.md");
}

fn readAt(root: []const u8, relative: []const u8) ![]u8 {
    const path = try std.fs.path.join(t.allocator, &.{ root, relative });
    defer t.allocator.free(path);
    return std.Io.Dir.cwd().readFileAlloc(t.io, path, t.allocator, .unlimited);
}

test "overview CLI writes checks emits equivalent JSON and caps stale diff" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try fixture(temporary.dir);
    defer t.allocator.free(root);
    const cache = try std.fs.path.join(t.allocator, &.{ root, ".cache-a" });
    defer t.allocator.free(cache);
    const missing = try invoke(root, &.{"--check"}, cache);
    defer release(missing);
    try t.expectEqual(std.process.Child.Term{ .exited = 1 }, missing.term);
    try t.expect(std.mem.indexOf(u8, missing.stdout, "--write") != null);
    try t.expect(std.mem.count(u8, missing.stdout, "\n") <= 61);
    const written = try invoke(root, &.{"--write"}, cache);
    defer release(written);
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, written.term);
    const repeated = try invoke(root, &.{"--write"}, cache);
    defer release(repeated);
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, repeated.term);
    try t.expectEqualStrings("overview: current OVERVIEW.md\n", repeated.stdout);
    const bytes = try read(root);
    defer t.allocator.free(bytes);
    const checked = try invoke(root, &.{ "--check", "--json" }, cache);
    defer release(checked);
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, checked.stdout, .{});
    defer parsed.deinit();
    try t.expectEqualStrings("overview-v1", parsed.value.object.get("version").?.string);
    try t.expectEqualStrings("current", parsed.value.object.get("status").?.string);
    try t.expectEqualStrings(bytes, parsed.value.object.get("markdown").?.string);
    try t.expect(parsed.value.object.get("content").?.object.get("modules").?.array.items.len == 3);
    try t.expectEqual(@as(usize, 3), parsed.value.object.get("references").?.array.items.len);
    const reference = try readAt(root, "reference/catalog.md");
    defer t.allocator.free(reference);
    try t.expect(std.mem.indexOf(u8, reference, "public func value(") != null);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "project/reference/reader.md", .data = "stale\n" });
    const stale_reference = try invoke(root, &.{"--check"}, cache);
    defer release(stale_reference);
    try t.expectEqual(std.process.Child.Term{ .exited = 1 }, stale_reference.term);
    try t.expect(std.mem.indexOf(u8, stale_reference.stdout, "--- reference/reader.md") != null);
    const repaired = try invoke(root, &.{"--write"}, cache);
    defer release(repaired);
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, repaired.term);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "project/reference/orphan.md", .data = "# orphan\n" });
    const orphan = try invoke(root, &.{"--check"}, cache);
    defer release(orphan);
    try t.expectEqual(std.process.Child.Term{ .exited = 1 }, orphan.term);
    const cleaned = try invoke(root, &.{"--write"}, cache);
    defer release(cleaned);
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, cleaned.term);
    try t.expectError(error.FileNotFound, temporary.dir.statFile(t.io, "project/reference/orphan.md", .{}));
    try temporary.dir.writeFile(t.io, .{ .sub_path = "project/OVERVIEW.md", .data = "stale\n" });
    const stale = try invoke(root, &.{"--check"}, cache);
    defer release(stale);
    try t.expectEqual(std.process.Child.Term{ .exited = 1 }, stale.term);
    try t.expect(std.mem.startsWith(u8, stale.stdout, "--- OVERVIEW.md\n+++ OVERVIEW.md (generated)\n"));
    try t.expect(std.mem.count(u8, stale.stdout, "\n") <= 61);
}

test "overview CLI bytes ignore cache placement and absolute checkout parent" {
    var left = t.tmpDir(.{});
    defer left.cleanup();
    var right = t.tmpDir(.{});
    defer right.cleanup();
    const a = try fixture(left.dir);
    defer t.allocator.free(a);
    const b = try fixture(right.dir);
    defer t.allocator.free(b);
    const cache_a = try std.fs.path.join(t.allocator, &.{ a, ".first-cache" });
    defer t.allocator.free(cache_a);
    const cache_b = try std.fs.path.join(t.allocator, &.{ b, ".second-cache" });
    defer t.allocator.free(cache_b);
    const once = try invoke(a, &.{"--write"}, cache_a);
    defer release(once);
    const twice = try invoke(a, &.{"--write"}, cache_b);
    defer release(twice);
    const elsewhere = try invoke(b, &.{"--write"}, cache_b);
    defer release(elsewhere);
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, once.term);
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, twice.term);
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, elsewhere.term);
    const first = try read(a);
    defer t.allocator.free(first);
    const second = try read(b);
    defer t.allocator.free(second);
    try t.expectEqualStrings(first, second);
    const first_reference = try readAt(a, "reference/catalog.md");
    defer t.allocator.free(first_reference);
    const second_reference = try readAt(b, "reference/catalog.md");
    defer t.allocator.free(second_reference);
    try t.expectEqualStrings(first_reference, second_reference);
    try t.expect(std.mem.indexOf(u8, first_reference, a) == null);
    try t.expect(std.mem.indexOf(u8, first, a) == null);
    try t.expect(std.mem.indexOf(u8, first, cache_a) == null);
    try t.expect(std.mem.indexOf(u8, first, "compiler_digest") == null);
    try t.expect(std.mem.indexOf(u8, first, "timestamp") == null);
}

test "overview CLI rejects ambiguous modes and missing projects" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try fixture(temporary.dir);
    defer t.allocator.free(root);
    const bad = try invoke(root, &.{ "--write", "--check" }, "");
    defer release(bad);
    const absent = try invoke(root, &.{}, "");
    defer release(absent);
    const missing = try invoke("missing-overview-project", &.{"--write"}, "");
    defer release(missing);
    try t.expectEqual(std.process.Child.Term{ .exited = 2 }, bad.term);
    try t.expectEqual(std.process.Child.Term{ .exited = 2 }, absent.term);
    try t.expectEqual(std.process.Child.Term{ .exited = 2 }, missing.term);
    try t.expect(std.mem.indexOf(u8, bad.stderr, "usage:") != null);
}

test "overview html writes the project page and its data, with the back link" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try fixture(temporary.dir);
    defer t.allocator.free(root);
    const cache = try std.fs.path.join(t.allocator, &.{ root, ".cache-html" });
    defer t.allocator.free(cache);
    const page_path = try std.fs.path.join(t.allocator, &.{ root, "page.html" });
    defer t.allocator.free(page_path);
    const data_path = try std.fs.path.join(t.allocator, &.{ root, "page.json" });
    defer t.allocator.free(data_path);
    const written = try invoke(root, &.{ "--html", page_path, "--data", data_path, "--back", "../../index.html" }, cache);
    defer release(written);
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, written.term);
    const page = try std.Io.Dir.cwd().readFileAlloc(t.io, page_path, t.allocator, .unlimited);
    defer t.allocator.free(page);
    try t.expect(std.mem.startsWith(u8, page, "<!doctype html>"));
    try t.expect(std.mem.indexOf(u8, page, "\"title\":\"project\"") != null);
    try t.expect(std.mem.indexOf(u8, page, "\"back\":\"../../index.html\"") != null);
    try t.expect(std.mem.indexOf(u8, page, "\"release_notes\":[{\"name\":\"0.1\",\"titles\":[]}]") != null);
    const data = try std.Io.Dir.cwd().readFileAlloc(t.io, data_path, t.allocator, .unlimited);
    defer t.allocator.free(data);
    try t.expect(std.mem.startsWith(u8, data, "{\"version\":\"overview-v1\",\"title\":\"project\""));
    try t.expect(std.mem.indexOf(u8, data, "release_notes") == null);
    const again_path = try std.fs.path.join(t.allocator, &.{ root, "again.html" });
    defer t.allocator.free(again_path);
    const again = try invoke(root, &.{ "--html", again_path, "--data", data_path, "--back", "../../index.html" }, cache);
    defer release(again);
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, again.term);
    const repeated = try std.Io.Dir.cwd().readFileAlloc(t.io, again_path, t.allocator, .unlimited);
    defer t.allocator.free(repeated);
    try t.expectEqualStrings(page, repeated);
}

test "overview html is a mode of its own: with --write or --check it is usage and writes nothing" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try fixture(temporary.dir);
    defer t.allocator.free(root);
    const page_path = try std.fs.path.join(t.allocator, &.{ root, "x.html" });
    defer t.allocator.free(page_path);
    const bad = try invoke(root, &.{ "--html", page_path, "--write" }, "");
    defer release(bad);
    try t.expectEqual(std.process.Child.Term{ .exited = 2 }, bad.term);
    try t.expect(std.mem.indexOf(u8, bad.stderr, "--html FILE") != null);
    try t.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(t.io, page_path, .{}));
}
