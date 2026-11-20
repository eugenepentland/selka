//! Pure checked-docs project, decision and baseline acceptance cases.
const std = @import("std");
const t = std.testing;
const project = @import("release_project.zig");
const decisions = @import("release_decisions.zig");
const baseline = @import("api_diff_baseline.zig");

const valid_decision = "# Represent shapes precisely\nDate: 2026-10-19\nChanges: app::added, app::changed, app::removed\nWhy: Reject misspelled shape values before producing incorrect output.\nRejected: keeping unchecked strings.\n";
const old = [_]baseline.Entry{
    .{ .identity = "same", .display = "app::same", .kind = "function", .interface = "one", .body = "old" },
    .{ .identity = "changed", .display = "app::changed", .kind = "type", .interface = "one", .body = "-" },
    .{ .identity = "removed", .display = "app::removed", .kind = "function", .interface = "one", .body = "old" },
};
const current = [_]baseline.Entry{
    .{ .identity = "same", .display = "app::same", .kind = "function", .interface = "one", .body = "new" },
    .{ .identity = "changed", .display = "app::changed", .kind = "type", .interface = "two", .body = "-" },
    .{ .identity = "added", .display = "app::added", .kind = "function", .interface = "one", .body = "new" },
};

test "release foundations select entries tests and examples with stable exclusions" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const files = [_]project.File{
        .{ .path = "main.selka" },                            .{ .path = "other.selka" },                         .{ .path = "z_test.selka", .test_bearing = true },
        .{ .path = "a.selka", .example_bearing = true },      .{ .path = "build/x.selka", .test_bearing = true }, .{ .path = "vendor/x.selka", .test_bearing = true },
        .{ .path = ".hidden/y.selka", .test_bearing = true },
    };
    const selected = try project.select(arena.allocator(), &files, "main.selka", .{ .exclude = &.{"vendor"} });
    try t.expectEqualStrings("main.selka", selected.entries[0]);
    try t.expectEqual(@as(usize, 2), selected.test_roots.len);
    try t.expectEqualStrings("a.selka", selected.test_roots[0]);
    try t.expectEqual(@as(usize, 3), selected.roots.len);
    const configured = try project.select(arena.allocator(), &files, "main.selka", .{ .entries = &.{ "other.selka", "main.selka" } });
    try t.expectEqualStrings("other.selka", configured.entries[0]);
    try t.expectError(error.InvalidEntry, project.select(arena.allocator(), &files, "missing.selka", .{}));
    try t.expect(project.excluded("pkg/.hidden/file.selka", &.{}));
    try t.expect(!project.excluded("vendorish/file.selka", &.{"vendor/"}));
}

test "release foundations module set unites closures and excludes test and standard modules" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const modules = [_]project.Module{
        .{ .path = "main.selka", .imports = &.{1} },
        .{ .path = "lib.selka", .imports = &.{3} },
        .{ .path = "lib_test.selka", .imports = &.{ 1, 4 } },
        .{ .path = "@stdlib/math.selka", .imports = &.{}, .standard = true },
        .{ .path = "extra.selka", .imports = &.{1} },
    };
    const selected = try project.moduleSet(arena.allocator(), &modules, &.{ 0, 2 }, &.{});
    try t.expectEqualSlices(usize, &.{ 4, 1, 0 }, selected);
    const excluded = try project.moduleSet(arena.allocator(), &modules, &.{ 0, 2 }, &.{"extra.selka"});
    try t.expectEqualSlices(usize, &.{ 1, 0 }, excluded);
    try t.expectError(error.InvalidGraph, project.moduleSet(arena.allocator(), &modules, &.{99}, &.{}));
}

test "release foundations pending decisions cover addition interface edit and removal" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const parsed = try decisions.parse(arena.allocator(), "decisions/unreleased/shapes.md", valid_decision, true);
    try t.expectEqual(@as(usize, 0), parsed.issues.len);
    try t.expectEqualStrings("shapes", parsed.decision.identity);
    try t.expectEqualStrings("2026-10-19", parsed.decision.metadata.date.?);
    try t.expectEqual(@as(usize, 3), parsed.decision.changes.len);
    const covered = try decisions.coverage(arena.allocator(), &old, &current, &.{parsed.decision});
    try t.expectEqual(@as(usize, 0), covered.len);
    const missing = try decisions.coverage(arena.allocator(), &old, &current, &.{});
    try t.expectEqual(@as(usize, 3), missing.len);
    try t.expectEqualStrings("E_RELEASE_DECISION_MISSING", missing[0].code);
    const no_baseline = try decisions.coverage(arena.allocator(), null, &current, &.{});
    try t.expectEqualStrings("E_RELEASE_NO_BASELINE", no_baseline[0].code);
}

test "release foundations body edits need no decision and visibility flips are additions and removals" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const body = try decisions.coverage(arena.allocator(), old[0..1], current[0..1], &.{});
    try t.expectEqual(@as(usize, 0), body.len);
    const made_public = try decisions.coverage(arena.allocator(), &.{}, current[0..1], &.{});
    try t.expectEqual(@as(usize, 1), made_public.len);
    try t.expectEqualStrings("app::same", made_public[0].name.?);
    const made_private = try decisions.coverage(arena.allocator(), old[0..1], &.{}, &.{});
    try t.expectEqual(@as(usize, 1), made_private.len);
    try t.expectEqualStrings("app::same", made_private[0].name.?);
}

test "release foundations placeholders malformed fields and invalid dates are refused" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const placeholder = try decisions.parse(arena.allocator(), "draft.md", "# TODO\nChanges: app::added\nWhy: TODO\n", true);
    try t.expect(!placeholder.decision.valid);
    try t.expectEqual(@as(usize, 2), placeholder.issues.len);
    const missing = try decisions.parse(arena.allocator(), "draft.md", "No heading\nWhy: A sufficiently long reason for making this interface change.\n", true);
    try t.expectEqual(@as(usize, 2), missing.issues.len);
    const malformed = try decisions.parse(arena.allocator(), "draft.md", "# Reason\nChanges: bad, app::added\nDate: 2026-02-30\nWhy: A sufficiently long reason for making this interface change.\n", true);
    try t.expectEqual(@as(usize, 2), malformed.issues.len);
    try t.expect(!decisions.validDate("2026-13-01"));
    try t.expect(!decisions.validDate("2025-02-29"));
    try t.expect(decisions.validDate("2024-02-29"));
    try t.expect(decisions.qualifiedName("package.module::name"));
    try t.expect(!decisions.qualifiedName("package.module::name()"));
}

test "release foundations unknown pending names fail while archived removed names remain history" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const pending = try decisions.parse(arena.allocator(), "unreleased/old.md", "# Previous design\nChanges: app::obsolete\nWhy: Preserve the recorded rationale for the older design choices.\n", true);
    const unknown = try decisions.coverage(arena.allocator(), &old, &current, &.{pending.decision});
    try t.expectEqualStrings("E_RELEASE_REFERENCE_UNKNOWN", unknown[0].code);
    const archived = try decisions.parse(arena.allocator(), "0.1/old.md", "# Previous design\nChanges: app::obsolete\nWhy: TODO\n", false);
    try t.expectEqual(@as(usize, 0), archived.issues.len);
    const historical = try decisions.coverage(arena.allocator(), &current, &current, &.{archived.decision});
    try t.expectEqual(@as(usize, 0), historical.len);
    try t.expectEqual(@as(?usize, null), decisions.covering(&.{archived.decision}, "app::obsolete"));
}

test "release foundations baseline roundtrip is deterministic and rejects the wrong format marker" {
    const bytes = try baseline.serialize(t.allocator, &current);
    defer t.allocator.free(bytes);
    const entries = try baseline.parseBaseline(t.allocator, bytes);
    defer baseline.freeEntries(t.allocator, entries);
    try t.expectEqualStrings("app::added", entries[0].display);
    try t.expectEqual(@as(usize, 3), entries.len);
    try t.expectError(error.InvalidBaseline, baseline.parseReleaseBaseline(t.allocator, "# some-other-format\n"));
}

test "release foundations ignore fenced metadata and enforce exact date digits and configured paths" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const parsed = try decisions.parse(arena.allocator(), "design.md", valid_decision ++ "\n```text\nWhy: TODO\nChanges: missing::name\n```\n", true);
    try t.expectEqual(@as(usize, 0), parsed.issues.len);
    try t.expectEqual(@as(usize, 3), parsed.decision.changes.len);
    try t.expect(!decisions.validDate("+026-10-19"));
    try t.expect(!decisions.validDate("2026-+1-19"));
    const no_baseline = try decisions.coverageAt(arena.allocator(), null, &current, &.{}, .{ .baseline = "versions/public.txt" });
    try t.expectEqualStrings("versions/public.txt", no_baseline[0].path);
    const missing = try decisions.coverageAt(arena.allocator(), &old, &current, &.{}, .{ .pending = "design/pending" });
    try t.expectEqualStrings("design/pending", missing[0].path);
    const legacy = try baseline.parseBaseline(t.allocator, "# legacy-comment\n");
    defer baseline.freeEntries(t.allocator, legacy);
    try t.expectEqual(@as(usize, 0), legacy.len);
}

test "release foundations retain malformed text-discovered test roots" {
    try t.expect(project.declaresTests("public func test_broken(\n"));
    try t.expect(project.declaresTests("@test\nfunc property(\n"));
    try t.expect(!project.declaresTests("# public func test_broken(\n"));
}

test "release foundations respect fence widths and closing suffixes around example metadata" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    for ([_][]const u8{
        "\n````text\n```\nWhy: TODO\n````not-a-close\nChanges: missing::name\n`````\n",
        "\n~~~~~text\n~~~~\nWhy: TODO\n~~~~~not-a-close\nChanges: missing::name\n~~~~~~\n",
    }) |example| {
        const bytes = try std.mem.concat(arena.allocator(), u8, &.{ valid_decision, example });
        const parsed = try decisions.parse(arena.allocator(), "design.md", bytes, true);
        try t.expectEqual(@as(usize, 0), parsed.issues.len);
        try t.expectEqual(@as(usize, 3), parsed.decision.changes.len);
        try t.expect(parsed.decision.valid);
    }
}
