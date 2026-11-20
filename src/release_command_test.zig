//! Library boundary regressions behind the release command's public CLI tests.
const std = @import("std");
const t = std.testing;
const host = @import("release_context.zig");
const sources = @import("release_gate_sources.zig");
const adopt = @import("release_adopt.zig");
const baseline = @import("api_diff_baseline.zig");
const reports = @import("release_report.zig");

test "release host ChildFailed distinguishes signals and setup errors from refusals" {
    try t.expectError(error.ChildFailed, host.childStatus(.{ .signal = .TERM }));
    try t.expectError(error.ChildFailed, host.childStatus(.{ .unknown = 0 }));
    try t.expectEqual(@as(u8, 3), try host.childStatus(.{ .exited = 3 }));
    const failed: host.Child = .{ .status = 2, .stdout = "", .stderr = "invalid cases file" };
    try t.expectError(error.ChildFailed, failed.checkHost());
    const refused: host.Child = .{ .status = 3, .stdout = "", .stderr = "finding" };
    try refused.checkHost();
}

test "release runCase parseReport and soleVerdict refuse malformed missing duplicated and mismatched cases" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expectError(error.InvalidTestReport, sources.parseReport(a, "{not json}"));
    const empty = try std.json.parseFromSlice(std.json.Value, a, "{\"tests\":[]}", .{});
    try t.expectError(error.InvalidTestReport, sources.soleVerdict(empty.value, "main::test_a"));
    const wrong = try std.json.parseFromSlice(std.json.Value, a, "{\"tests\":[{\"name\":\"main::test_ab\"}]}", .{});
    try t.expectError(error.InvalidTestReport, sources.soleVerdict(wrong.value, "main::test_a"));
    const duplicate = try std.json.parseFromSlice(std.json.Value, a, "{\"tests\":[{\"name\":\"main::test_a\"},{\"name\":\"main::test_a\"}]}", .{});
    try t.expectError(error.InvalidTestReport, sources.soleVerdict(duplicate.value, "main::test_a"));
    const valid = try std.json.parseFromSlice(std.json.Value, a, "{\"tests\":[{\"name\":\"main::test_a\",\"status\":\"cached\"}]}", .{});
    const result = try sources.soleVerdict(valid.value, "main::test_a");
    try t.expectEqualStrings("cached", @import("release_report.zig").string(result, "status"));
}

test "release adoption AdoptionChangedInterface compares interface rather than body bytes" {
    const before: baseline.Entry = .{ .identity = "id", .display = "main::value", .kind = "function", .interface = "same", .body = "old" };
    var body = before;
    body.body = "new";
    try adopt.confirmInterface(t.allocator, &.{before}, &.{body});
    var signature = before;
    signature.interface = "changed";
    try t.expectError(error.AdoptionChangedInterface, adopt.confirmInterface(t.allocator, &.{before}, &.{signature}));
    try t.expectError(error.AdoptionChangedInterface, adopt.confirmInterface(t.allocator, &.{before}, &.{}));
    try t.expectError(error.AdoptionChangedInterface, adopt.confirmInterface(t.allocator, &.{}, &.{before}));
}

test "release adoption CommentDelimiterCollision refuses unrepresentable comment text" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "selka.json", .data = "{\"version\":2}" });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "main.selka", .data = "# Both delimiters: \"\"\" and '''.\npublic func value() -> int:\n    return 1\n" });
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", a);
    var model = try @import("release_project_load.zig").load(t.allocator, t.io, root);
    defer model.deinit();
    const id = model.modules[0];
    try t.expectError(error.CommentDelimiterCollision, adopt.rewrite(a, model.project.modules.items[id], model.index.units[id]));
}

// spec: DOCS-RELEASE-CHECK-2
test "FR-423 the tests aggregation counts each case once and refuses every non-passing verdict" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var counts: sources.Counts = .{};
    var report: reports.Report = .{ .allocator = a };
    defer report.deinit();
    const first = try std.json.parseFromSlice(std.json.Value, a, "{\"tests\":[{\"name\":\"m::test_a\",\"status\":\"passed\"}," ++
        "{\"name\":\"m::value.example\",\"status\":\"cached\"}," ++
        "{\"name\":\"m::test_b\",\"status\":\"failed\",\"reason\":\"boom\"}," ++
        "{\"name\":\"m::test_c\",\"status\":\"skipped\",\"reason\":\"later\"}]}", .{});
    try t.expect(first.value == .object);
    try sources.aggregate(a, &report, "main.selka", first.value, &seen, &counts);
    try t.expectEqual(@as(usize, 3), counts.tests);
    try t.expectEqual(@as(usize, 1), counts.examples);
    try t.expectEqual(@as(usize, 1), counts.passed);
    try t.expectEqual(@as(usize, 1), counts.cached);
    try t.expectEqual(@as(usize, 1), counts.skipped);
    try t.expectEqual(@as(usize, 2), report.findings.items.len);
    // A second root repeats one case and adds one: the shared case is counted once.
    const second = try std.json.parseFromSlice(std.json.Value, a, "{\"tests\":[{\"name\":\"m::test_a\",\"status\":\"cached\"},{\"name\":\"m::test_d\",\"status\":\"passed\"}]}", .{});
    try sources.aggregate(a, &report, "extra_test.selka", second.value, &seen, &counts);
    try t.expectEqual(@as(usize, 4), counts.tests);
    try t.expectEqual(@as(usize, 2), report.findings.items.len);
}

test "release adoption reports adjacent blocks and leaves detached comments and banners in place" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "selka.json", .data = "{\"version\":2}" });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "main.selka", .data = "# ==============================\n" ++
        "# Arithmetic helpers\n" ++
        "# ==============================\n" ++
        "public func banner() -> int:\n    return 1\n\n\n" ++
        "# ---- A titled section ----\n" ++
        "public func titled() -> int:\n    return 2\n\n\n" ++
        "# A detached comment.\n\n" ++
        "# Adjacent documentation.\n" ++
        "public func adjacent() -> int:\n    return 2\n\n\n" ++
        "func main() -> int:\n    return 0\n" });
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", a);
    var model = try @import("release_project_load.zig").load(t.allocator, t.io, root);
    defer model.deinit();
    const id = model.modules[0];
    const report = try adopt.rewriteReport(a, model.project.modules.items[id], model.index.units[id]);
    try t.expect(std.mem.indexOf(u8, report.source, "    \"\"\"Adjacent documentation.\"\"\"") != null);
    try t.expect(std.mem.indexOf(u8, report.source, "# A detached comment.") != null);
    try t.expect(std.mem.indexOf(u8, report.source, "# ==============================") != null);
    try t.expect(std.mem.indexOf(u8, report.source, "# ---- A titled section ----") != null);
    try t.expect(std.mem.indexOf(u8, report.source, "\"\"\"Arithmetic helpers") == null);
    try t.expectEqual(@as(usize, 1), report.adoptions.len);
    try t.expectEqualStrings("main::adjacent", report.adoptions[0].target);
    try t.expectEqual(@as(usize, 15), report.adoptions[0].line);
}

test "release adoption keeps quoted punctuation in prose instead of reading it as a banner" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "selka.json", .data = "{\"version\":2}" });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "main.selka", .data = "# It keeps ''' as prose.\n" ++
        "public func quoted() -> int:\n    return 3\n\n\n" ++
        "func main() -> int:\n    return 0\n" });
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", a);
    var model = try @import("release_project_load.zig").load(t.allocator, t.io, root);
    defer model.deinit();
    const id = model.modules[0];
    const report = try adopt.rewriteReport(a, model.project.modules.items[id], model.index.units[id]);
    try t.expect(std.mem.indexOf(u8, report.source, "    \"\"\"It keeps ''' as prose.\"\"\"") != null);
    try t.expectEqual(@as(usize, 1), report.adoptions.len);
    try t.expectEqualStrings("main::quoted", report.adoptions[0].target);
}
