//! Visible-fact mutation and deterministic rendering tests for checked overviews.
const std = @import("std");
const t = std.testing;
const overview = @import("overview.zig");
const store = @import("overview_store.zig");
const loader = @import("release_project_load.zig");
const api = @import("api_diff.zig");
const fixture_path = "test/fixtures/release-docs/overview";
const fixture_files = [_][]const u8{
    "selka.json",                      "main.selka",               "catalog.selka",       "reader.selka", "catalog_test.selka",
    "decisions/unreleased/current.md", "decisions/0.1/initial.md", "release/history.txt",
};

fn copyFixture(dir: std.Io.Dir) !void {
    for (fixture_files) |path| {
        const input = try std.fs.path.join(t.allocator, &.{ fixture_path, path });
        defer t.allocator.free(input);
        const bytes = try std.Io.Dir.cwd().readFileAlloc(t.io, input, t.allocator, .unlimited);
        defer t.allocator.free(bytes);
        if (std.fs.path.dirname(path)) |parent| try dir.createDirPath(t.io, parent);
        try dir.writeFile(t.io, .{ .sub_path = path, .data = bytes });
    }
}

fn rootPath(dir: std.Io.Dir) ![:0]u8 {
    return dir.realPathFileAlloc(t.io, ".", t.allocator);
}

fn prepare(dir: std.Io.Dir) !void {
    try copyFixture(dir);
    const path = try rootPath(dir);
    defer t.allocator.free(path);
    var model = try loader.load(t.allocator, t.io, path);
    defer model.deinit();
    const snapshot = try api.snapshotPublic(t.allocator, model.index, model.modules);
    defer t.allocator.free(snapshot);
    try dir.writeFile(t.io, .{ .sub_path = "release/baseline.txt", .data = snapshot });
    const written = try overview.write(t.allocator, t.io, &model);
    defer written.deinit(t.allocator);
}

fn compare(dir: std.Io.Dir) !overview.Outcome {
    const path = try rootPath(dir);
    defer t.allocator.free(path);
    var model = try loader.load(t.allocator, t.io, path);
    defer model.deinit();
    return overview.check(t.allocator, t.io, &model);
}

fn replace(dir: std.Io.Dir, path: []const u8, before: []const u8, after: []const u8) !void {
    const bytes = try dir.readFileAlloc(t.io, path, t.allocator, .unlimited);
    defer t.allocator.free(bytes);
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, before));
    const changed = try std.mem.replaceOwned(u8, t.allocator, bytes, before, after);
    defer t.allocator.free(changed);
    try dir.writeFile(t.io, .{ .sub_path = path, .data = changed });
}

fn declaration(document: overview.Document, name: []const u8) !@import("overview_types.zig").Declaration {
    for (document.modules) |module| for (module.declarations) |item| {
        if (std.mem.eql(u8, item.name, name)) return item;
    };
    return error.TestUnexpectedResult;
}

fn storedDecision(metadata: store.Store, path: []const u8) !@import("release_decisions.zig").Decision {
    for (metadata.decisions) |item| if (std.mem.eql(u8, item.path, path)) return item;
    return error.TestUnexpectedResult;
}

fn moduleNamed(document: overview.Document, name: []const u8) !@import("overview_types.zig").Module {
    for (document.modules) |module| if (std.mem.eql(u8, module.name, name)) return module;
    return error.TestUnexpectedResult;
}

test "overview facts show signatures defaults waivers direct tests and archived references" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try prepare(temporary.dir);
    const path = try rootPath(temporary.dir);
    defer t.allocator.free(path);
    var model = try loader.load(t.allocator, t.io, path);
    defer model.deinit();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const metadata = try store.load(arena.allocator(), t.io, &model);
    const document = try overview.collect(arena.allocator(), &model, metadata);
    const value = try declaration(document, "catalog::value");
    const item = try declaration(document, "catalog::Item");
    const choice = try declaration(document, "catalog::Choice");
    const report = try declaration(document, "main::report");
    try t.expectEqualStrings("@ensures(result >= 0)\npublic func value(named extra: int = 0) -> int", value.signature);
    try t.expectEqualStrings("4", item.details.fields[0].default.?);
    try t.expectEqualStrings("amount", choice.details.cases[1].fields[0].name);
    try t.expectEqualStrings("catalog_test::test_value", value.details.function.?.tests[0]);
    try t.expectEqual(@as(usize, 1), value.details.function.?.tests.len);
    try t.expectEqualStrings("writes a stream; covered by catalog_test::test_report", report.details.function.?.waiver.?);
    try t.expectEqualStrings("Stream", report.details.function.?.authority[0].type);
    try t.expectEqual(@as(usize, 1), document.counts.holes);
    try t.expectEqual(@as(usize, 3), document.counts.tests);
    try t.expectEqual(@as(usize, 0), metadata.issues.len);
    const result = try compare(temporary.dir);
    defer result.deinit(t.allocator);
    try t.expect(result.current);
    try t.expect(std.mem.indexOf(u8, result.markdown, "private_helper") == null);
    try t.expect(std.mem.indexOf(u8, result.markdown, "see above") == null);
    try t.expect(std.mem.indexOf(u8, result.markdown, "| Module | Purpose | Imports | Public | Private |") != null);
    try t.expect(std.mem.indexOf(u8, result.markdown, "| [catalog](reference/catalog.md) | Catalog values and their public representation.") != null);
    try t.expect(std.mem.indexOf(u8, result.markdown, "[`catalog::Item`](reference/catalog.md#decl-catalog--Item)") != null);
    try t.expect(std.mem.indexOf(u8, result.markdown, "| `mut` |") != null);
    try t.expect(std.mem.indexOf(u8, result.markdown, "public func value(") == null);
    try t.expect(std.mem.indexOf(u8, result.markdown, "This decision also points") != null);
    try t.expect(std.mem.indexOf(u8, result.markdown, "Later sentences") == null);
    const reference = try temporary.dir.readFileAlloc(t.io, "reference/catalog.md", t.allocator, .unlimited);
    defer t.allocator.free(reference);
    try t.expect(std.mem.indexOf(u8, reference, "public func value(") != null);
    try t.expect(std.mem.indexOf(u8, reference, "catalog_test::test_value") != null);
    try t.expect(std.mem.indexOf(u8, reference, ">>> value()") != null);
}

const Mutation = struct { path: []const u8, before: []const u8, after: []const u8 };
const mutations = [_]Mutation{
    .{ .path = "catalog.selka", .before = "named extra: int = 0", .after = "named extra: int = 1" },
    .{ .path = "catalog.selka", .before = "@ensures(result >= 0)", .after = "@ensures(result > 0)" },
    .{ .path = "catalog.selka", .before = "Read the item amount without changing it.", .after = "Read a catalog amount without changing its record." },
    .{ .path = "catalog.selka", .before = ">>> value()", .after = ">>> value(extra=0)" },
    .{ .path = "catalog_test.selka", .before = "return reader.read() == 4", .after = "return catalog.value() == 4" },
    .{ .path = "catalog.selka", .before = "return todo[int]()", .after = "return 0" },
    .{ .path = "catalog.selka", .before = "amount: int = 4", .after = "amount: int = 5" },
    .{ .path = "main.selka", .before = "writes a stream; covered by catalog_test::test_report", .after = "writes a report stream tested by catalog_test::test_report" },
    .{ .path = "catalog.selka", .before = "present(amount: int)", .after = "present(amount: int, label: str)" },
    .{ .path = "catalog.selka", .before = "    >>> value()\n    4\n", .after = "    >>> value()\n    4  \n" },
};

fn mutationWalk(dir: std.Io.Dir, seed: usize) !void {
    // Coprime stride visits every fact exactly once; the seed fixes the starting point.
    for (0..mutations.len) |step| {
        try prepare(dir);
        const mutation = mutations[(seed + step * 7) % mutations.len];
        try replace(dir, mutation.path, mutation.before, mutation.after);
        const result = try compare(dir);
        defer result.deinit(t.allocator);
        try t.expect(!result.current);
        try t.expect(std.mem.startsWith(u8, result.diff, "--- "));
        try t.expect(std.mem.count(u8, result.diff, "\n") <= 60);
    }
}

test "overview seeded visible-fact mutation walk rejects stale bytes" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try mutationWalk(temporary.dir, 20261019);
    try t.expectEqual(@as(usize, 10), mutations.len);
}

test "overview tracks decision additions and module additions and removals" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try prepare(temporary.dir);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "decisions/unreleased/another.md", .data = "# Explain reading\n\nChanges: reader::read\nWhy: Reading remains separate so callers can depend only on the catalog interface.\n" });
    const decision_result = try compare(temporary.dir);
    defer decision_result.deinit(t.allocator);
    try t.expect(!decision_result.current);
    try temporary.dir.deleteFile(t.io, "decisions/unreleased/another.md");
    try temporary.dir.writeFile(t.io, .{ .sub_path = "new.selka", .data = "\"\"\"A newly included module.\"\"\"\npublic const count: int = 1\n" });
    try replace(temporary.dir, "main.selka", "import reader", "import reader\nimport new");
    const added = try compare(temporary.dir);
    defer added.deinit(t.allocator);
    try t.expect(!added.current);
    try prepare(temporary.dir);
    try replace(temporary.dir, "main.selka", "import reader\n", "");
    try replace(temporary.dir, "catalog_test.selka", "import reader\n", "");
    try temporary.dir.deleteFile(t.io, "reader.selka");
    const removed = try compare(temporary.dir);
    defer removed.deinit(t.allocator);
    try t.expect(!removed.current);
    try t.expect(std.mem.indexOf(u8, removed.markdown, "removed") != null);
}

test "overview body-only non-test edits remain current even when bodies fail checking" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try prepare(temporary.dir);
    try replace(temporary.dir, "catalog.selka", "return private_helper() + extra", "return undefined_body_name");
    try replace(temporary.dir, "reader.selka", "return catalog.value()", "return 42");
    try replace(temporary.dir, "catalog.selka", "    return 4\n", "    return 9\n");
    const result = try compare(temporary.dir);
    defer result.deinit(t.allocator);
    try t.expect(result.current);
    try t.expectEqualStrings("", result.diff);
}

test "overview is byte identical across runs and distinct absolute checkout paths" {
    var first = t.tmpDir(.{});
    defer first.cleanup();
    var second = t.tmpDir(.{});
    defer second.cleanup();
    try first.dir.createDir(t.io, "project", .default_dir);
    try second.dir.createDir(t.io, "project", .default_dir);
    var left = try first.dir.openDir(t.io, "project", .{});
    defer left.close(t.io);
    var right = try second.dir.openDir(t.io, "project", .{});
    defer right.close(t.io);
    try prepare(left);
    try prepare(right);
    const once = try compare(left);
    defer once.deinit(t.allocator);
    const twice = try compare(left);
    defer twice.deinit(t.allocator);
    const elsewhere = try compare(right);
    defer elsewhere.deinit(t.allocator);
    try t.expectEqualStrings(once.markdown, twice.markdown);
    try t.expectEqualStrings(once.markdown, elsewhere.markdown);
    const absolute = try rootPath(left);
    defer t.allocator.free(absolute);
    try t.expect(std.mem.indexOf(u8, once.markdown, absolute) == null);
    try t.expect(std.mem.indexOf(u8, once.markdown, "timestamp") == null);
    try t.expect(std.mem.indexOf(u8, once.markdown, "compiler_digest") == null);
}

test "overview metadata rejects malformed history and baseline while missing files remain describable" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try copyFixture(temporary.dir);
    const missing = try compare(temporary.dir);
    defer missing.deinit(t.allocator);
    try t.expect(!missing.current);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "release/baseline.txt", .data = "not a baseline" });
    try t.expectError(error.InvalidBaseline, compare(temporary.dir));
    try temporary.dir.deleteFile(t.io, "release/baseline.txt");
    try temporary.dir.writeFile(t.io, .{ .sub_path = "release/history.txt", .data = "../escape\t1\n" });
    try t.expectError(error.InvalidHistory, compare(temporary.dir));
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expectError(error.InvalidHistory, store.parseHistory(arena.allocator(), "0.1\t1\n0.1\t1\n"));
    try t.expectError(error.InvalidHistory, store.parseHistory(arena.allocator(), "0.1\tNaN\n"));
    try t.expectError(error.InvalidHistory, store.parseHistory(arena.allocator(), "0.1\n"));
}

test "release history reads two and three column rows and keeps note counts" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const releases = try store.parseHistory(arena.allocator(), "# release history\n0.1\t2\n0.2\t0\t3\n");
    try t.expectEqual(@as(usize, 2), releases.len);
    try t.expectEqualStrings("0.1", releases[0].name);
    try t.expectEqual(@as(usize, 2), releases[0].decisions);
    try t.expectEqual(@as(usize, 0), releases[0].notes);
    try t.expectEqual(@as(usize, 0), releases[1].decisions);
    try t.expectEqual(@as(usize, 3), releases[1].notes);
    try t.expectError(error.InvalidHistory, store.parseHistory(arena.allocator(), "0.1\t1\t1\t1\n"));
    try t.expectError(error.InvalidHistory, store.parseHistory(arena.allocator(), "0.1\t1\tmany\n"));
    try t.expectError(error.InvalidHistory, store.parseHistory(arena.allocator(), "0.1\t1\t1\n0.1\t1\t0\n"));
}

test "overview validates nested pending decisions without matching similarly prefixed archives" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try copyFixture(temporary.dir);
    try temporary.dir.createDirPath(t.io, "decisions/unreleased/subdir");
    try temporary.dir.createDirPath(t.io, "decisions/unreleased-old/subdir");
    const nested_path = "decisions/unreleased/subdir/invalid.md";
    const archive_path = "decisions/unreleased-old/subdir/legacy.md";
    try temporary.dir.writeFile(t.io, .{ .sub_path = nested_path, .data = "# Explain the next operation\n\nChanges: catalog::value\nWhy: TODO\n" });
    try temporary.dir.writeFile(t.io, .{ .sub_path = archive_path, .data = "Legacy text without current decision metadata.\n" });
    const path = try rootPath(temporary.dir);
    defer t.allocator.free(path);
    var model = try loader.load(t.allocator, t.io, path);
    defer model.deinit();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const metadata = try store.load(arena.allocator(), t.io, &model);
    const nested = try storedDecision(metadata, nested_path);
    const archived = try storedDecision(metadata, archive_path);
    const direct = try storedDecision(metadata, "decisions/unreleased/current.md");
    try t.expect(nested.pending);
    try t.expect(!nested.valid);
    try t.expect(!archived.pending);
    try t.expect(archived.valid);
    try t.expect(direct.pending);
    try t.expectEqual(@as(usize, 1), metadata.issues.len);
    try t.expectEqualStrings(nested_path, metadata.issues[0].path);
    try t.expectEqualStrings("E_RELEASE_DECISION_INVALID", metadata.issues[0].code);
}

fn appendSource(dir: std.Io.Dir, path: []const u8, added: []const u8) !void {
    const prior = try dir.readFileAlloc(t.io, path, t.allocator, .unlimited);
    defer t.allocator.free(prior);
    const combined = try std.mem.concat(t.allocator, u8, &.{ prior, "\n", added });
    defer t.allocator.free(combined);
    try dir.writeFile(t.io, .{ .sub_path = path, .data = combined });
}

test "overview counts private examples and holes once through chained public facades" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try prepare(temporary.dir);
    try appendSource(temporary.dir, "catalog.selka",
        \\func concealed() -> int:
        \\    """An internal example that still runs.
        \\
        \\    >>> concealed()
        \\    0
        \\    """
        \\    return todo[int]()
    );
    try temporary.dir.writeFile(t.io, .{ .sub_path = "bridge.selka", .data = "import catalog\nexport catalog.value\nexport catalog.Item\n" });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "facade.selka", .data = "import bridge\nexport bridge.value\nexport bridge.Item\n" });
    try replace(temporary.dir, "main.selka", "import reader", "import reader\nimport facade");
    const path = try rootPath(temporary.dir);
    defer t.allocator.free(path);
    var model = try loader.load(t.allocator, t.io, path);
    defer model.deinit();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const document = try overview.collect(arena.allocator(), &model, try store.load(arena.allocator(), t.io, &model));
    const facade = try declaration(document, "facade::value");
    const original = try declaration(document, "catalog::value");
    const record = try declaration(document, "facade::Item");
    try t.expectEqualStrings(original.signature, facade.signature);
    try t.expectEqualStrings(original.doc, facade.doc);
    try t.expectEqualStrings("catalog_test::test_value", facade.details.function.?.tests[0]);
    try t.expectEqualStrings("4", record.details.fields[0].default.?);
    try t.expectEqual(@as(usize, 4), document.counts.examples);
    try t.expectEqual(@as(usize, 2), document.counts.holes);
    const markdown = try overview.renderDocument(arena.allocator(), document);
    try t.expect(std.mem.indexOf(u8, markdown, "concealed") == null);
    try t.expect(std.mem.indexOf(u8, markdown, "internal example") == null);
    const reference = try temporary.dir.readFileAlloc(t.io, "reference/catalog.md", t.allocator, .unlimited);
    defer t.allocator.free(reference);
    try t.expect(std.mem.indexOf(u8, reference, "concealed") == null);
    try t.expect(std.mem.indexOf(u8, reference, "internal example") == null);
}

test "overview test discovery respects visibility attributes generic and return shapes" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try prepare(temporary.dir);
    try appendSource(temporary.dir, "catalog_test.selka",
        \\func test_private_argument(value: int) -> bool:
        \\    return catalog.value() == value
        \\
        \\func test_private_result() -> int:
        \\    return catalog.value()
        \\
        \\func test_default() -> bool:
        \\    return catalog.value() == 4
        \\
        \\@test
        \\func attributed(value: int) -> bool:
        \\    return catalog.value() == value
        \\
        \\public func test_generic[T](value: T) -> bool:
        \\    return catalog.value() == 4
    );
    const path = try rootPath(temporary.dir);
    defer t.allocator.free(path);
    var model = try loader.load(t.allocator, t.io, path);
    defer model.deinit();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const document = try overview.collect(arena.allocator(), &model, try store.load(arena.allocator(), t.io, &model));
    const value = try declaration(document, "catalog::value");
    try t.expectEqual(@as(usize, 5), document.counts.tests);
    try t.expectEqual(@as(usize, 3), value.details.function.?.tests.len);
    try t.expectEqualStrings("catalog_test::attributed", value.details.function.?.tests[0]);
    try t.expectEqualStrings("catalog_test::test_default", value.details.function.?.tests[1]);
    try t.expectEqualStrings("catalog_test::test_value", value.details.function.?.tests[2]);
}

test "overview history renders newest first and configured output failures are host errors" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try prepare(temporary.dir);
    try temporary.dir.createDirPath(t.io, "decisions/0.2");
    try temporary.dir.writeFile(t.io, .{ .sub_path = "decisions/0.2/next.md", .data = "# A newer choice\n\nChanges: catalog::removed_again\nWhy: This archived reason remains visible after declarations are removed.\n" });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "release/history.txt", .data = "0.1\t1\n0.2\t1\n" });
    const result = try compare(temporary.dir);
    defer result.deinit(t.allocator);
    const newer = std.mem.indexOf(u8, result.markdown, "### 0.2 (1 decisions)").?;
    const older = std.mem.indexOf(u8, result.markdown, "### 0.1 (1 decisions)").?;
    try t.expect(newer < older);
    try temporary.dir.deleteFile(t.io, "OVERVIEW.md");
    try temporary.dir.createDir(t.io, "OVERVIEW.md", .default_dir);
    try t.expectError(error.HostIo, compare(temporary.dir));
}

test "overview preserves prose fences and links references from configured nested output" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try prepare(temporary.dir);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "selka.json", .data = "{\"version\":2,\"release\":{\"overview\":\"docs/OVERVIEW.md\"}}" });
    try temporary.dir.writeFile(t.io, .{
        .sub_path = "decisions/unreleased/prose.md",
        .data = "# Preserve prose\n\nChanges: catalog::value\n" ++
            "This line follows a field directly and remains visible.\n" ++
            "Why: Preserve user explanations even when they are immediately after metadata.\n\n" ++
            "See ``catalog::Item`` and [`catalog::value`](catalog.selka).\n\n" ++
            "```text\n`catalog::Item` remains literal inside a fence.\n```\n",
    });
    const result = try compare(temporary.dir);
    defer result.deinit(t.allocator);
    try t.expect(std.mem.indexOf(u8, result.markdown, "(../decisions/unreleased/prose.md)") != null);
    try t.expect(std.mem.indexOf(u8, result.markdown, "This line follows a field directly") != null);
    try t.expect(std.mem.indexOf(u8, result.markdown, "See [`catalog::Item`](reference/catalog.md#decl-catalog--Item) and [`catalog::value`](catalog.selka).") != null);
    try t.expect(std.mem.indexOf(u8, result.markdown, "```text\n`catalog::Item` remains literal inside a fence.\n```") != null);
}

test "overview prose distinguishes escaped opening backticks by backslash parity" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try copyFixture(temporary.dir);
    const prose =
        \\Odd \`catalog::Item` remains literal.
        \\Three \\\`catalog::Item` remains literal.
        \\Even \\`catalog::Item` is linked.
        \\Four \\\\``catalog::Item`` is linked.
        \\Paired \`catalog::Item\` then `catalog::value`.
        \\Normal `catalog::Item`, wide ``catalog::value``, authored [`catalog::Item`](catalog.selka).
    ;
    try temporary.dir.writeFile(t.io, .{
        .sub_path = "decisions/unreleased/escaping.md",
        .data = "# Preserve escaped prose\n\nChanges: catalog::value\n" ++
            "Why: Literal references must remain readable without changing authored Markdown escapes.\n\n" ++ prose ++ "\n",
    });
    const result = try compare(temporary.dir);
    defer result.deinit(t.allocator);
    const expected =
        \\Odd \`catalog::Item` remains literal.
        \\Three \\\`catalog::Item` remains literal.
        \\Even \\[`catalog::Item`](reference/catalog.md#decl-catalog--Item) is linked.
        \\Four \\\\[`catalog::Item`](reference/catalog.md#decl-catalog--Item) is linked.
        \\Paired \`catalog::Item\` then [`catalog::value`](reference/catalog.md#decl-catalog--value).
        \\Normal [`catalog::Item`](reference/catalog.md#decl-catalog--Item), wide [`catalog::value`](reference/catalog.md#decl-catalog--value), authored [`catalog::Item`](catalog.selka).
    ;
    try t.expect(std.mem.indexOf(u8, result.markdown, expected) != null);
}

test "overview direct callers resolve explicitly applied generic functions" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try prepare(temporary.dir);
    try appendSource(temporary.dir, "catalog.selka", "public func identity[T](value: T) -> T:\n    return value\n");
    try appendSource(temporary.dir, "catalog_test.selka", "public func test_applied() -> bool:\n    return catalog.identity[int](1) == 1\n");
    const path = try rootPath(temporary.dir);
    defer t.allocator.free(path);
    var model = try loader.load(t.allocator, t.io, path);
    defer model.deinit();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const document = try overview.collect(arena.allocator(), &model, try store.load(arena.allocator(), t.io, &model));
    const generic = try declaration(document, "catalog::identity");
    try t.expectEqual(@as(usize, 1), generic.details.function.?.tests.len);
    try t.expectEqualStrings("catalog_test::test_applied", generic.details.function.?.tests[0]);
}

test "overview excludes loaded ignored modules from example hole and direct-test counts" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try prepare(temporary.dir);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "selka.json", .data = "{\"version\":2,\"release\":{\"exclude\":[\"ignored.selka\"]}}" });
    try temporary.dir.writeFile(t.io, .{
        .sub_path = "ignored.selka",
        .data = "import catalog\nimport ignored_helper\n\n" ++
            "public func test_ignored() -> bool:\n    return catalog.value() == 4\n\n" ++
            "func hidden_hole() -> int:\n    \"\"\"Hidden example.\n    >>> hidden_hole()\n    4\n    \"\"\"\n    return todo[int]()\n",
    });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "ignored_helper.selka", .data = "func hidden_dependency() -> int:\n    return todo[int]()\n" });
    try replace(temporary.dir, "main.selka", "import reader", "import reader\nimport ignored");
    const path = try rootPath(temporary.dir);
    defer t.allocator.free(path);
    var model = try loader.load(t.allocator, t.io, path);
    defer model.deinit();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const document = try overview.collect(arena.allocator(), &model, try store.load(arena.allocator(), t.io, &model));
    const value = try declaration(document, "catalog::value");
    try t.expectEqual(@as(usize, 3), document.counts.modules);
    try t.expectEqual(@as(usize, 3), document.counts.examples);
    try t.expectEqual(@as(usize, 3), document.counts.tests);
    try t.expectEqual(@as(usize, 1), document.counts.holes);
    try t.expectEqual(@as(usize, 1), value.details.function.?.tests.len);
}

test "overview retains long fences encoded decision links and malformed archived prose" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try prepare(temporary.dir);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "selka.json", .data = "{\"version\":2,\"release\":{\"overview\":\"docs/OVERVIEW.md\",\"decisions\":\"design notes#1\"}}" });
    try temporary.dir.createDirPath(t.io, "design notes#1/unreleased");
    try temporary.dir.createDirPath(t.io, "design notes#1/0.1");
    try temporary.dir.writeFile(t.io, .{
        .sub_path = "design notes#1/unreleased/current.md",
        .data = "# Preserve long fences\n\nChanges: catalog::value\n" ++
            "Why: Literal code remains useful when documenting the examples themselves.\n\n" ++
            "````text\n```\n`catalog::Item`\n>>> literal prompt\n````\n",
    });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "design notes#1/0.1/old.md", .data = "\n# A readable archived title\n\nA legacy reason survives without any modern metadata fields.\n" });
    const result = try compare(temporary.dir);
    defer result.deinit(t.allocator);
    try t.expect(std.mem.indexOf(u8, result.markdown, "(../design%20notes%231/unreleased/current.md)") != null);
    try t.expect(std.mem.indexOf(u8, result.markdown, "````text\n```\n`catalog::Item`\n>>> literal prompt\n````") != null);
    try t.expect(std.mem.indexOf(u8, result.markdown, "[A readable archived title](../design%20notes%231/0.1/old.md)") != null);
    try t.expect(std.mem.indexOf(u8, result.markdown, "A legacy reason survives") != null);
}

test "overview writes missing output once and repeated writes retain the same bytes" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try copyFixture(temporary.dir);
    const path = try rootPath(temporary.dir);
    defer t.allocator.free(path);
    var model = try loader.load(t.allocator, t.io, path);
    defer model.deinit();
    const first = try overview.write(t.allocator, t.io, &model);
    defer first.deinit(t.allocator);
    const second = try overview.write(t.allocator, t.io, &model);
    defer second.deinit(t.allocator);
    try t.expect(first.current);
    try t.expect(second.current);
    try t.expectEqualStrings(first.markdown, second.markdown);
    try t.expect(first.diff.len != 0);
    try t.expectEqualStrings("", second.diff);
}

test "overview quotes literal backticks in example output defaults and contracts" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try prepare(temporary.dir);
    try replace(temporary.dir, "catalog.selka", "    >>> value()\n    4\n", "    >>> value()\n    ```\n");
    try replace(temporary.dir, "catalog.selka", "@ensures(result >= 0)", "@ensures(result >= 0, \"`nonnegative`\")");
    try appendSource(temporary.dir, "catalog.selka", "public record Label:\n    \"\"\"Keep delimiter-bearing labels intact.\"\"\"\n    text: str = \"`value`\"\n");
    const result = try compare(temporary.dir);
    defer result.deinit(t.allocator);
    const path = try rootPath(temporary.dir);
    defer t.allocator.free(path);
    var model = try loader.load(t.allocator, t.io, path);
    defer model.deinit();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const document = try overview.collect(arena.allocator(), &model, try store.load(arena.allocator(), t.io, &model));
    const reference = try overview.renderReference(arena.allocator(), document, try moduleNamed(document, "catalog"));
    try t.expect(std.mem.indexOf(u8, reference, "````text\n>>> value()\n```\n````") != null);
    try t.expect(std.mem.indexOf(u8, reference, "| `text` | `str` | ``\"`value`\"`` |") != null);
    try t.expect(std.mem.indexOf(u8, reference, "Contracts: ``@ensures(result >= 0, \"`nonnegative`\")``.") != null);
}

fn generated(dir: std.Io.Dir, path: []const u8) ![]u8 {
    return dir.readFileAlloc(t.io, path, t.allocator, .unlimited);
}

test "overview generated lines never state only an empty fact" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try prepare(temporary.dir);
    const output = [_][]const u8{ "OVERVIEW.md", "reference/catalog.md", "reference/main.md", "reference/reader.md" };
    var checked: usize = 0;
    for (output) |path| {
        const bytes = try generated(temporary.dir, path);
        defer t.allocator.free(bytes);
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |line| {
            try t.expect(!overview.noneFact(line));
            checked += @intFromBool(line.len != 0);
        }
    }
    try t.expect(checked > 100);
}

test "overview summary and every reference are byte identical across checkouts" {
    var first = t.tmpDir(.{});
    defer first.cleanup();
    var second = t.tmpDir(.{});
    defer second.cleanup();
    try first.dir.createDir(t.io, "project", .default_dir);
    try second.dir.createDir(t.io, "project", .default_dir);
    var left = try first.dir.openDir(t.io, "project", .{});
    defer left.close(t.io);
    var right = try second.dir.openDir(t.io, "project", .{});
    defer right.close(t.io);
    try prepare(left);
    try prepare(right);
    const absolute = try rootPath(left);
    defer t.allocator.free(absolute);
    const output = [_][]const u8{ "OVERVIEW.md", "reference/catalog.md", "reference/main.md", "reference/reader.md" };
    for (output) |path| {
        const here = try generated(left, path);
        defer t.allocator.free(here);
        const elsewhere = try generated(right, path);
        defer t.allocator.free(elsewhere);
        try t.expectEqualStrings(here, elsewhere);
        try t.expect(std.mem.indexOf(u8, here, absolute) == null);
        try t.expect(std.mem.indexOf(u8, here, "timestamp") == null);
        try t.expect(std.mem.indexOf(u8, here, "compiler_digest") == null);
    }
}

test "overview check covers reference-only edits and write removes an orphan reference" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try prepare(temporary.dir);
    try replace(temporary.dir, "catalog.selka", "The record keeps its amount explicit for callers.", "The record keeps its amount explicit for every caller.");
    const edited = try compare(temporary.dir);
    defer edited.deinit(t.allocator);
    try t.expect(!edited.current);
    try t.expect(std.mem.indexOf(u8, edited.diff, "--- reference/catalog.md") != null);
    try prepare(temporary.dir);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "reference/orphan.md", .data = "# orphan\n" });
    const orphan = try compare(temporary.dir);
    defer orphan.deinit(t.allocator);
    try t.expect(!orphan.current);
    try t.expect(std.mem.indexOf(u8, orphan.diff, "--- reference/orphan.md") != null);
    const path = try rootPath(temporary.dir);
    defer t.allocator.free(path);
    var model = try loader.load(t.allocator, t.io, path);
    defer model.deinit();
    const written = try overview.write(t.allocator, t.io, &model);
    defer written.deinit(t.allocator);
    try t.expect(written.current);
    try t.expectError(error.FileNotFound, temporary.dir.statFile(t.io, "reference/orphan.md", .{}));
}

test "overview summary markers name mut capabilities and failure types" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try prepare(temporary.dir);
    try appendSource(temporary.dir, "catalog.selka",
        \\public func parse(text: str) -> int fails str:
        \\    """Read an amount from text.
        \\
        \\    >>> parse("4")
        \\    4
        \\    """
        \\    return 4
    );
    const path = try rootPath(temporary.dir);
    defer t.allocator.free(path);
    var model = try loader.load(t.allocator, t.io, path);
    defer model.deinit();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const document = try overview.collect(arena.allocator(), &model, try store.load(arena.allocator(), t.io, &model));
    const markdown = try overview.renderDocument(arena.allocator(), document);
    try t.expect(std.mem.indexOf(u8, markdown, "| [`catalog::parse`](reference/catalog.md#decl-catalog--parse) | Read an amount from text. | `fails str` |") != null);
    try t.expect(std.mem.indexOf(u8, markdown, "| `mut` |") != null);
}

test "overview render releases partial output when a caller allocation fails" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try prepare(temporary.dir);
    const path = try rootPath(temporary.dir);
    defer t.allocator.free(path);
    var model = try loader.load(t.allocator, t.io, path);
    defer model.deinit();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const document = try overview.collect(arena.allocator(), &model, try store.load(arena.allocator(), t.io, &model));
    for (0..5) |index| {
        var failing = std.testing.FailingAllocator.init(t.allocator, .{ .fail_index = index });
        try t.expectError(error.OutOfMemory, overview.renderDocumentSet(failing.allocator(), document));
    }
}
