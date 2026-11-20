//! Pure tests for strict release configuration and project-relative outputs.
const std = @import("std");
const t = std.testing;
const config = @import("release_config.zig");

test "release config defaults and explicit settings" {
    const defaults = try config.parseConfig(t.allocator, "{\"version\":2,\"release\":{}}");
    defer defaults.deinit();
    try t.expectEqualStrings("OVERVIEW.md", defaults.value.options.?.overview);
    try t.expectEqualStrings("decisions", defaults.value.options.?.decisions);
    try t.expectEqualStrings("release/baseline.txt", defaults.value.options.?.baseline);
    try t.expectEqual(@as(usize, 0), defaults.value.options.?.entries.len);
    const explicit = try config.parseConfig(t.allocator,
        \\{"version":2,"budgets":{"max_modules":50},"release":{"entries":["lib/main.selka","cli.selka"],"exclude":["oracle/"],"overview":"docs/OVERVIEW.md","decisions":"why","baseline":"api.txt"}}
    );
    defer explicit.deinit();
    try t.expectEqualStrings("lib/main.selka", explicit.value.options.?.entries[0]);
    try t.expectEqualStrings("oracle/", explicit.value.options.?.exclude[0]);
    try t.expectEqualStrings("docs/OVERVIEW.md", explicit.value.options.?.overview);
    const absent = try config.parseConfig(t.allocator, "{\"version\":1}");
    defer absent.deinit();
    try t.expect(absent.value.options == null);
}

test "release config rejects unknown duplicate and malformed fields" {
    try t.expectError(error.UnknownField, config.parseConfig(t.allocator, "{\"release\":{\"optional_examples\":true}}"));
    try t.expectError(error.DuplicateField, config.parseConfig(t.allocator, "{\"release\":{},\"release\":{}}"));
    try t.expectError(error.DuplicateField, config.parseConfig(t.allocator, "{\"release\":{\"entries\":[],\"entries\":[]}}"));
    try t.expectError(error.InvalidRelease, config.parseConfig(t.allocator, "{\"release\":null}"));
    try t.expectError(error.InvalidRelease, config.parseConfig(t.allocator, "{\"release\":{\"entries\":\"main.selka\"}}"));
    try t.expectError(error.InvalidRelease, config.parseConfig(t.allocator, "{\"release\":{\"exclude\":[1]}}"));
    try t.expectError(error.InvalidRelease, config.parseConfig(t.allocator, "{\"release\":{\"overview\":\"\"}}"));
}

test "release config prevents paths escaping the project" {
    try t.expect(!config.relativePath("../outside"));
    try t.expect(!config.relativePath("docs/../outside"));
    try t.expect(!config.relativePath("bad\x00path"));
    try t.expect(config.relativePath("docs/overview.md"));
    try t.expect(config.relativePath("oracle/"));
    try t.expectError(error.InvalidRelease, config.parseConfig(t.allocator, "{\"release\":{\"baseline\":\"../outside\"}}"));
    try t.expectError(error.InvalidRelease, config.parseConfig(t.allocator, "{\"release\":{\"decisions\":\"history/\"}}"));
    try t.expectError(error.InvalidRelease, config.parseConfig(t.allocator, "{\"release\":{\"entries\":[\"main.txt\"]}}"));
}

test "release config projection reads only the release object" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var scanner = std.json.Scanner.initCompleteInput(t.allocator, "{\"other\":{\"nested\":[1]},\"release\":{}}");
    defer scanner.deinit();
    const projected = try config.Projection.jsonParse(arena.allocator(), &scanner, .{ .allocate = .alloc_always, .max_value_len = 1024 });
    try t.expect(projected.options != null);
    try t.expectEqualStrings("OVERVIEW.md", projected.options.?.overview);
}

test "release config validates each configurable output path" {
    for ([_][]const u8{ "overview", "decisions", "baseline", "changes" }) |field| {
        for ([_][]const u8{ "../outside", "docs/../outside", "directory/", "" }) |path| {
            const bytes = try std.fmt.allocPrint(t.allocator, "{{\"release\":{{\"{s}\":\"{s}\"}}}}", .{ field, path });
            defer t.allocator.free(bytes);
            try t.expectError(error.InvalidRelease, config.parseConfig(t.allocator, bytes));
        }
    }
}

test "release config reads the changes directory and refuses an absolute one" {
    const notes = try config.parseConfig(t.allocator, "{\"release\":{\"changes\":\"notes\"}}");
    defer notes.deinit();
    try t.expectEqualStrings("notes", notes.value.options.?.changes);
    const defaults = try config.parseConfig(t.allocator, "{\"release\":{}}");
    defer defaults.deinit();
    try t.expectEqualStrings("changes", defaults.value.options.?.changes);
    try t.expectError(error.InvalidRelease, config.parseConfig(t.allocator, "{\"release\":{\"changes\":\"/abs/changes\"}}"));
    try t.expectError(error.InvalidRelease, config.parseConfig(t.allocator, "{\"release\":{\"changes\":\"notes/\"}}"));
}
