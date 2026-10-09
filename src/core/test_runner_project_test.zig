//! Project tests exercise fresh runs, unchanged receipts, provider edits and
//! dependency invalidation through the actual command and native processes.
const std = @import("std");
const tools = @import("core_test_options");
const language = @import("selka");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const v = @import("property_value.zig");
const Outcome = struct { status: u8, report: std.json.Value, stderr: []const u8 };
const command_cache = "--cache-dir";
const InvalidCase = struct { name: []const u8, body: []const u8, settings: []const u8 };
const diagnostic = std.debug.print;
const Context = struct {
    arena: std.mem.Allocator,
    root: []const u8,
    fn write(self: Context, path: []const u8, bytes: []const u8) !void {
        const absolute = try std.fs.path.join(self.arena, &.{ self.root, path });
        try std.Io.Dir.cwd().createDirPath(std.testing.io, std.fs.path.dirname(absolute).?);
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = absolute, .data = bytes });
    }
    fn writeInterfaces(self: Context, source: []const u8) !void {
        const path = try std.fs.path.join(self.arena, &.{ self.root, source });
        var diagnostics: std.ArrayList(u8) = .empty;
        const located = try project_entry.resolve(self.arena, std.testing.io, path, &diagnostics);
        var session = frontend.Session.init(self.arena, std.testing.io, located.root);
        defer session.deinit();
        located.configure(&session);
        session.entry_suffix = @import("test_runner.zig").check_stub;
        _ = try session.checkFile(self.arena, located.path, &diagnostics);
        const written = try language.api_files.run(self.arena, .{ .io = std.testing.io, .root = located.root, .entry = located.path, .mode = .write, .json = false }, session.interfaceIndex());
        try std.testing.expectEqual(@as(u8, 0), written.status);
    }
    fn run(self: Context, source: []const u8, extra: []const []const u8) !Outcome {
        const path = try std.fs.path.join(self.arena, &.{ self.root, source });
        const cache = try std.fs.path.join(self.arena, &.{ self.root, "cache" });
        var args: std.ArrayList([]const u8) = .empty;
        try args.appendSlice(self.arena, &.{ tools.core_path, "test", path, "--json", command_cache, cache, "--jobs", "2", "--property-runs", "5" });
        try args.appendSlice(self.arena, extra);
        const result = try std.process.run(self.arena, std.testing.io, .{ .argv = args.items });
        const parsed = std.json.parseFromSliceLeaky(std.json.Value, self.arena, result.stdout, .{}) catch .null;
        return .{ .status = switch (result.term) {
            .exited => |code| code,
            else => 255,
        }, .report = parsed, .stderr = result.stderr };
    }
};
const project_source =
    \\import dep
    \\
    \\public func test_dependency() -> bool:
    \\    return dep.value() == 3
    \\
    \\public func test_constant() -> bool:
    \\    return True
    \\
    \\public func test_property(x: int) -> bool:
    \\    return x == x
    \\
    \\func main() -> int:
    \\    return 0
    \\
;
const dependency_three = "\npublic func value() -> int:\n    return 3\n";
const dependency_four = "\npublic func value() -> int:\n    return 4\n";

// spec-case: NEW-CORE-S4-TEST-3
test "guestTool refuses a missing executable before checking or replaying tests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("app.selka", project_source);
    try context.write("dep.selka", dependency_three);
    const missing = try std.fs.path.join(a, &.{ context.root, "absent-zig" });
    const found = try context.run("app.selka", &.{ "--zig", missing });
    try std.testing.expectEqual(@as(u8, 1), found.status);
    try std.testing.expect(std.mem.indexOf(u8, found.stderr, "ToolNotFound") != null);
    const directory = try context.run(".", &.{ "--zig", missing });
    try std.testing.expectEqual(@as(u8, 1), directory.status);
    try std.testing.expect(std.mem.indexOf(u8, directory.stderr, "ToolNotFound") != null);
}

fn verdict(value: std.json.Value, name: []const u8, wanted: []const u8) !void {
    for (v.array(v.get(value, "tests"))) |item| {
        if (!std.mem.eql(u8, v.text(v.get(item, "name")), name)) continue;
        try std.testing.expectEqualStrings(wanted, v.text(v.get(item, "status")));
        return;
    }
    return error.MissingTestVerdict;
}
fn expectStatus(context: Context, found: Outcome, status: u8) !void {
    if (found.status != status) {
        const json = try std.json.Stringify.valueAlloc(context.arena, found.report, .{});
        diagnostic("unexpected project test result: {s}\n{s}\n", .{ found.stderr, json });
    }
    try std.testing.expectEqual(status, found.status);
}

// spec: NEW-CORE-S4-TEST-2
// spec: NEW-CORE-S4-TEST-3
test "directory receipts account for orphan libraries and rerun only the edited reachable program" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("app.selka", project_source);
    try context.write("dep.selka", dependency_three);
    try context.write("orphan.selka", "\nfunc test_orphan() -> bool:\n    return True\n");
    const cold = try context.run(".", &.{});
    try expectStatus(context, cold, 0);
    try std.testing.expectEqual(@as(u64, 4), v.number(v.get(cold.report, "passed")));
    const warm = try context.run(".", &.{});
    try expectStatus(context, warm, 0);
    try std.testing.expectEqual(@as(u64, 4), v.number(v.get(warm.report, "cached")));
    try context.write("dep.selka", dependency_four);
    const changed = try context.run(".", &.{});
    try expectStatus(context, changed, 1);
    try verdict(changed.report, "app::test_dependency", "failed");
    try verdict(changed.report, "app::test_constant", "cached");
    try verdict(changed.report, "app::test_property", "cached");
    try verdict(changed.report, "orphan::test_orphan", "cached");
    const force = try context.run("app.selka", &.{ "--force", "--filter", "test_constant" });
    try expectStatus(context, force, 0);
    try verdict(force.report, "app::test_constant", "passed");
}

const whole_source =
    \\import dep
    \\
    \\public func test_dependency() -> bool:
    \\    return dep.value() == 3
    \\
    \\public func test_constant() -> bool:
    \\    return True
    \\
    \\func main() -> int:
    \\    return 0
    \\
;
/// A file's bytes, kept so a trial can put a receipt directory back as it was.
const Saved = struct { name: []const u8, bytes: []const u8 };

fn receiptDirectory(context: Context) ![]const u8 {
    return std.fs.path.join(context.arena, &.{ context.root, "cache", "tests", "receipts-v2" });
}

/// Every receipt the run's cache holds, with its bytes.
fn receipts(context: Context) ![]const Saved {
    var directory = try std.Io.Dir.cwd().openDir(std.testing.io, try receiptDirectory(context), .{ .iterate = true });
    defer directory.close(std.testing.io);
    var found: std.ArrayList(Saved) = .empty;
    var entries = directory.iterate();
    while (try entries.next(std.testing.io)) |entry| {
        const bytes = try directory.readFileAlloc(std.testing.io, entry.name, context.arena, .limited(4096));
        try found.append(context.arena, .{ .name = try context.arena.dupe(u8, entry.name), .bytes = bytes });
    }
    return found.items;
}

/// Replace the receipt directory with `kept` alone and drop the report manifests, so
/// the next run cannot replay a whole report and must consult the receipts.
fn keepOnly(context: Context, kept: []const Saved) !void {
    const directory = try receiptDirectory(context);
    try std.Io.Dir.cwd().deleteTree(std.testing.io, directory);
    try std.Io.Dir.cwd().deleteTree(std.testing.io, try std.fs.path.join(context.arena, &.{ context.root, "cache", "tests", "manifests-v2" }));
    try std.Io.Dir.cwd().createDirPath(std.testing.io, directory);
    for (kept) |item| try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try std.fs.path.join(context.arena, &.{ directory, item.name }), .data = item.bytes });
}

/// How many single receipts, each kept alone, still let every test of `source` replay.
fn aloneSufficient(context: Context, source: []const u8, all: []const Saved) !usize {
    var sufficient: usize = 0;
    for (all) |item| {
        try keepOnly(context, &.{item});
        const run = try context.run(source, &.{});
        if (run.status == 0 and v.number(v.get(run.report, "cached")) == 2) sufficient += 1;
    }
    try keepOnly(context, all);
    return sufficient;
}

// spec: NEW-CORE-TEST-WHOLE-1
test "sharedKeys: a program's whole-file receipt alone replays every test, and an edit reruns only the tests that reach it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
    try context.write("app.selka", whole_source);
    try context.write("dep.selka", dependency_three);
    const cold = try context.run("app.selka", &.{});
    try expectStatus(context, cold, 0);
    try std.testing.expectEqual(@as(u64, 2), v.number(v.get(cold.report, "passed")));
    const saved = try receipts(context);
    try std.testing.expectEqual(@as(usize, 3), saved.len);
    try std.testing.expectEqual(@as(usize, 1), try aloneSufficient(context, "app.selka", saved));
    try context.write("dep.selka", dependency_four);
    const changed = try context.run("app.selka", &.{});
    try expectStatus(context, changed, 1);
    try verdict(changed.report, "app::test_dependency", "failed");
    try verdict(changed.report, "app::test_constant", "cached");
}

const keys_app =
    \\import dep
    \\
    \\public func test_value() -> bool:
    \\    return dep.value() == 3
    \\
    \\public func test_greeting() -> bool:
    \\    return len(dep.greeting()) == 2
    \\
    \\public func test_point() -> bool:
    \\    return dep.origin().x == 0
    \\
    \\public func test_alone() -> bool:
    \\    return True
    \\
    \\func main() -> int:
    \\    return 0
    \\
;
const keys_dep_parts = [_][]const u8{
    "\npublic record Point:\n    x: int\n    y: int\n\n",
    "public func value() -> int:\n    return 3\n\n",
    "public func greeting() -> str:\n    return \"hi\"\n\n",
    "public func origin() -> Point:\n    return Point(x=0, y=0)\n\n",
    "public func unused() -> int:\n    return 1\n",
};
/// One step of the key differential: the dependency's source after it, and the tests
/// whose program it changes.
const KeyEdit = struct { dep: []const u8, rerun: []const []const u8 };

fn byName(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// Run `app.selka` with derived keys and with `SELKA_TEST_KEYS=per-test`, each in its own
/// cache, and require both to rerun exactly the tests named in `expected` (in any
/// order; every other test `cached`).
fn sameReruns(context: Context, expected: []const []const u8) !void {
    for ([_]bool{ false, true }) |oracle| {
        var environment = try std.testing.environ.createMap(context.arena);
        if (oracle) try environment.put("SELKA_TEST_KEYS", "per-test");
        const cache = try std.fs.path.join(context.arena, &.{ context.root, if (oracle) "cache-oracle" else "cache-derived" });
        const entry_path = try std.fs.path.join(context.arena, &.{ context.root, "app.selka" });
        const argv = [_][]const u8{ tools.core_path, "test", entry_path, "--json", command_cache, cache };
        const result = try std.process.run(context.arena, std.testing.io, .{ .argv = &argv, .environ_map = &environment });
        const report = try std.json.parseFromSliceLeaky(std.json.Value, context.arena, result.stdout, .{});
        var rerun: std.ArrayList([]const u8) = .empty;
        for (v.array(v.get(report, "tests"))) |item| if (!std.mem.eql(u8, v.text(v.get(item, "status")), "cached")) try rerun.append(context.arena, v.text(v.get(item, "name")));
        const wanted = try context.arena.dupe([]const u8, expected);
        std.mem.sort([]const u8, wanted, {}, byName);
        std.mem.sort([]const u8, rerun.items, {}, byName);
        try std.testing.expectEqual(wanted.len, rerun.items.len);
        for (wanted, rerun.items) |want, got| try std.testing.expectEqualStrings(want, got);
    }
}

// spec-case: NEW-CORE-TEST-KEYS-1
test "derived per-test keys rerun exactly the tests the per-test oracle reruns across body, string, type and interface edits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    const parts = keys_dep_parts;
    try context.write("app.selka", keys_app);
    try context.write("dep.selka", try std.mem.concat(a, u8, &parts));
    try sameReruns(context, &.{ "app::test_value", "app::test_greeting", "app::test_point", "app::test_alone" });
    const value_sum = "public func value() -> int:\n    return 1 + 2\n\n";
    const unused_text = "public func unused() -> int:\n    _ = \"new text\"\n    return 1\n";
    const greeting_ho = "public func greeting() -> str:\n    return \"ho\"\n\n";
    const point_z = "\npublic record Point:\n    x: int\n    y: int\n    z: int\n\n";
    const origin_z = "public func origin() -> Point:\n    return Point(x=0, y=0, z=0)\n\n";
    const added = "\npublic func added() -> int:\n    return 2\n";
    const edits = [_]KeyEdit{
        .{ .dep = try std.mem.concat(a, u8, &.{ parts[0], value_sum, parts[2], parts[3], parts[4] }), .rerun = &.{"app::test_value"} },
        .{ .dep = try std.mem.concat(a, u8, &.{ parts[0], value_sum, parts[2], parts[3], unused_text }), .rerun = &.{} },
        .{ .dep = try std.mem.concat(a, u8, &.{ parts[0], value_sum, greeting_ho, parts[3], unused_text }), .rerun = &.{"app::test_greeting"} },
        .{ .dep = try std.mem.concat(a, u8, &.{ point_z, value_sum, greeting_ho, origin_z, unused_text, added }), .rerun = &.{ "app::test_value", "app::test_greeting", "app::test_point" } },
    };
    for (edits) |edit| {
        try context.write("dep.selka", edit.dep);
        try sameReruns(context, edit.rerun);
    }
}

// spec: NEW-CORE-S4-TEST-4
test "localReplay invalidates provider edits and explicit expectations in successful test receipts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("app.selka", project_source);
    try context.write("dep.selka", dependency_three);
    const fixture = try std.json.Stringify.valueAlloc(a, .{ .@"app::test_dependency" = .{ .providers = .{ .@"dep.selka" = dependency_four }, .expected = false } }, .{});
    try context.write("app.cases.json", fixture);
    const cold = try context.run("app.selka", &.{ "--filter", "test_dependency" });
    try expectStatus(context, cold, 0);
    try verdict(cold.report, "app::test_dependency", "passed");
    const warm = try context.run("app.selka", &.{ "--filter", "test_dependency" });
    try expectStatus(context, warm, 0);
    try verdict(warm.report, "app::test_dependency", "cached");
    try context.write("app.cases.json", try std.json.Stringify.valueAlloc(a, .{ .@"app::test_dependency" = .{ .providers = .{ .@"dep.selka" = dependency_three }, .expected = false } }, .{}));
    const changed = try context.run("app.selka", &.{ "--filter", "test_dependency" });
    try expectStatus(context, changed, 1);
    try verdict(changed.report, "app::test_dependency", "failed");
    try context.write("app.cases.json", "{\"missing::test_unknown\":{}}");
    const unknown = try context.run("app.selka", &.{});
    try expectStatus(context, unknown, 2);
    try std.testing.expect(std.mem.indexOf(u8, unknown.stderr, "UnknownTestCase") != null);
    const replacement = try std.json.Stringify.valueAlloc(a, .{ .@"app::test_dependency" = .{ .providers = .{ .@"app.selka" = project_source } } }, .{});
    try context.write("app.cases.json", replacement);
    const entry_override = try context.run("app.selka", &.{});
    try expectStatus(context, entry_override, 2);
    try std.testing.expect(std.mem.indexOf(u8, entry_override.stderr, "invalid test provider dependencies") != null);
}

// spec-case: NEW-CORE-S4-TEST-4
// spec-case: NEW-CORE-S4-TEST-3
test "provider-only imports and embedded assets participate in receipt invalidation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("app.selka", project_source);
    try context.write("dep.selka", dependency_three);
    try context.write("extra.selka", "\npublic func value() -> int:\n    return 3\n");
    const provided = "import extra\n\npublic func value() -> int:\n    return extra.value() + len(embed_bytes(\"data.bin\")) - 1\n";
    try context.write("data.bin", "x");
    try context.write("app.cases.json", try std.json.Stringify.valueAlloc(a, .{ .@"app::test_dependency" = .{ .providers = .{ .@"dep.selka" = provided } } }, .{}));
    try expectStatus(context, try context.run("app.selka", &.{ "--filter", "test_dependency" }), 0);
    const warm = try context.run("app.selka", &.{ "--filter", "test_dependency" });
    try verdict(warm.report, "app::test_dependency", "cached");
    try context.write("extra.selka", "\npublic func value() -> int:\n    return 4\n");
    const changed = try context.run("app.selka", &.{ "--filter", "test_dependency" });
    try expectStatus(context, changed, 1);
    try verdict(changed.report, "app::test_dependency", "failed");
    try context.write("extra.selka", "\npublic func value() -> int:\n    return 3\n");
    try context.write("data.bin", "xx");
    try expectStatus(context, try context.run("app.selka", &.{ "--filter", "test_dependency" }), 1);
}

// spec-case: NEW-CORE-S4-TEST-4
test "configuredCases require canonical discovered names and never ignore an expectation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("plain.selka", "func test_value() -> bool:\n    return True\n");
    try context.write("plain.cases.json", "{\"test_value\":{\"expected\":false}}");
    const alias = try context.run("plain.selka", &.{});
    try expectStatus(context, alias, 2);
    try std.testing.expect(std.mem.indexOf(u8, alias.stderr, "UnknownTestCase") != null);
    try context.write("plain.cases.json", "{\"plain::test_value\":{\"expected\":false}}");
    const canonical = try context.run("plain.selka", &.{});
    try expectStatus(context, canonical, 1);
    try verdict(canonical.report, "plain::test_value", "failed");
}

// spec: NEW-CORE-S5-TEST-STATUS-1
test "a run whose selected tests were all skipped exits 3 and an invalid cases file exits 2, in a file or a directory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("skipped_test.selka", "public func test_later() -> bool:\n    return True\n");
    try context.write("skipped_test.cases.json", "{\"skipped_test::test_later\":{\"skip\":\"not yet\"}}");
    const skipped = try context.run("skipped_test.selka", &.{});
    try expectStatus(context, skipped, 3);
    try verdict(skipped.report, "skipped_test::test_later", "skipped");
    try expectStatus(context, try context.run(".", &.{}), 3);
    try context.write("passing_test.selka", "public func test_now() -> bool:\n    return True\n");
    try expectStatus(context, try context.run(".", &.{}), 0);
    try context.write("skipped_test.cases.json", "{\"skipped_test::test_later\":{\"bogus\":1}}");
    const invalid = try context.run("skipped_test.selka", &.{});
    try expectStatus(context, invalid, 2);
    try std.testing.expect(std.mem.indexOf(u8, invalid.stderr, "InvalidTestCases") != null);
    try expectStatus(context, try context.run(".", &.{}), 2);
}

// spec-case: NEW-CORE-S4-PROJECT-1
// spec-case: NEW-CORE-S4-TEST-3
test "embedded bytes and stricter project budgets invalidate unchanged test manifests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("asset.selka", "\nfunc test_asset() -> bool:\n    return len(embed_bytes(\"data.bin\")) == 1\n");
    try context.write("data.bin", "x");
    try expectStatus(context, try context.run("asset.selka", &.{}), 0);
    const cached = try context.run("asset.selka", &.{});
    try verdict(cached.report, "asset::test_asset", "cached");
    try context.write("data.bin", "xx");
    const changed = try context.run("asset.selka", &.{});
    try expectStatus(context, changed, 1);
    try verdict(changed.report, "asset::test_asset", "failed");
    try context.write("data.bin", "x");
    try expectStatus(context, try context.run("asset.selka", &.{}), 0);
    try context.write("selka.json", "{\"version\":1,\"budgets\":{\"max_file_bytes\":16}}");
    const bounded = try context.run("asset.selka", &.{});
    try expectStatus(context, bounded, 1);
    try std.testing.expect(std.mem.indexOf(u8, bounded.stderr, "E_PROJECT_BYTES") != null);
}

// spec-case: NEW-CORE-S4-TEST-1
test "native test step and wall bounds are honored while force bypasses reuse" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("loop.selka", "\nfunc test_loop() -> bool:\n    mut total = 0\n    for i in range(100):\n        total = total + i\n    return total == 4950\n");
    try context.write("selka.json", "{\"version\":1,\"limits\":{\"test\":{\"max_steps\":2}}}");
    try expectStatus(context, try context.run("loop.selka", &.{}), 1);
    try expectStatus(context, try context.run("loop.selka", &.{ "--max-steps", "100000" }), 0);
    const limited = try context.run("loop.selka", &.{ "--max-steps", "2" });
    try expectStatus(context, limited, 1);
    try verdict(limited.report, "loop::test_loop", "failed");
    try context.write("loop.selka", "\nfunc test_loop() -> bool:\n    while True:\n        pass\n    return True\n");
    try expectStatus(context, try context.run("loop.selka", &.{ "--max-steps", "0", "--timeout-ms", "50" }), 1);
}

// spec: NEW-CORE-S4-STEPS-1
test "the default step budget charges one step per executed block, like the old core's dispatch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("long.selka", "\nfunc test_long() -> bool:\n    mut values: int[] = []\n    for i in range(200000):\n        values.append(i * 3 + 1)\n    return len(values) == 200000\n");
    try expectStatus(context, try context.run("long.selka", &.{}), 0);
    const limited = try context.run("long.selka", &.{ "--max-steps", "1000" });
    try expectStatus(context, limited, 1);
    try verdict(limited.report, "long::test_long", "failed");
}

/// The reason a named test's verdict gives, or an error when the report has no such test.
fn reasonOf(value: std.json.Value, name: []const u8) ![]const u8 {
    for (v.array(v.get(value, "tests"))) |item| {
        if (std.mem.eql(u8, v.text(v.get(item, "name")), name)) return v.text(v.get(item, "reason"));
    }
    return error.MissingTestVerdict;
}

/// Run `selka-core test` on `source` under a 1 MiB native stack limit, which a
/// recursion 40,000 calls deep overflows unless the runtime maps the trial's stack.
fn runSmallStack(context: Context, source: []const u8, extra: []const u8) !Outcome {
    const path = try std.fs.path.join(context.arena, &.{ context.root, source });
    const cache = try std.fs.path.join(context.arena, &.{ context.root, "cache" });
    const command = try std.fmt.allocPrint(context.arena, "ulimit -s 1024 && exec \"$0\" test \"$1\" --json --cache-dir \"$2\" --max-steps 0 {s}", .{extra});
    const result = try std.process.run(context.arena, std.testing.io, .{ .argv = &.{ "sh", "-c", command, tools.core_path, path, cache } });
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, context.arena, result.stdout, .{}) catch .null;
    return .{ .status = switch (result.term) {
        .exited => |code| code,
        else => 255,
    }, .report = parsed, .stderr = result.stderr };
}

const deep_source = "\nfunc down(n: int) -> int:\n    if n == 0:\n        return 0\n    return 1 + down(n - 1)\n\n" ++
    "func test_deep() -> bool:\n    return down(40000) == 40000\n\nfunc test_shallow() -> bool:\n    return down(10) == 10\n";

// spec: NEW-CORE-S4-FRAMES-1
// spec-case: NEW-CORE-S5-TRACE-1
test "a test's call depth is bounded by --max-frames, 1024 by default, on a stack mapped for the whole budget" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("deep.selka", deep_source);
    // The default budget traps the deep test and leaves the shallow one alone.
    const default = try context.run("deep.selka", &.{ "--max-steps", "0" });
    try expectStatus(context, default, 1);
    try verdict(default.report, "deep::test_shallow", "passed");
    // A budget's trap is a trap (NEW-CORE-S5-TRACE-1): its code, sixteen frames, the count left out and the advice.
    const deep_reason = try reasonOf(default.report, "deep::test_deep");
    try std.testing.expect(std.mem.startsWith(u8, deep_reason, "R_FRAME_LIMIT\n  in deep::down at "));
    try std.testing.expect(std.mem.indexOf(u8, deep_reason, "\n  1008 frames omitted\n\ncall-depth budget exhausted; raise it with --max-frames=N") != null);
    try std.testing.expectEqual(@as(usize, 16), std.mem.count(u8, deep_reason, "  in deep::down at "));
    // 40,002 frames (the test and 40,001 calls of `down`) run on 1.2 GiB of mapped stack, not the 1 MiB native one.
    try expectStatus(context, try runSmallStack(context, "deep.selka", "--max-frames 40002 --max-memory 2G"), 0);
    try expectStatus(context, try runSmallStack(context, "deep.selka", "--max-frames=40002 --max-memory=2G --release"), 0);
    const short = try runSmallStack(context, "deep.selka", "--max-frames 40001 --max-memory 2G");
    try expectStatus(context, short, 1);
    try std.testing.expect(std.mem.startsWith(u8, try reasonOf(short.report, "deep::test_deep"), "R_FRAME_LIMIT\n"));
    // A budget whose stack the byte ceiling cannot back is refused before anything is built.
    const refused = try context.run("deep.selka", &.{ "--max-frames", "40002" });
    try expectStatus(context, refused, 2);
    try std.testing.expect(std.mem.indexOf(u8, refused.stderr, "raise --max-memory to at least 2G") != null);
    try expectStatus(context, try context.run("deep.selka", &.{ "--max-frames", "0" }), 2);
    // The project's `limits.test` supplies both ceilings; a flag still wins.
    try context.write("selka.json", "{\"version\":1,\"limits\":{\"test\":{\"max_steps\":4000000000,\"max_frames\":40002,\"max_memory\":\"2G\"}}}");
    try expectStatus(context, try context.run("deep.selka", &.{}), 0);
    try expectStatus(context, try context.run("deep.selka", &.{ "--max-frames", "100" }), 1);
}

// spec: NEW-CORE-S4-MEMORY-1
// spec-case: NEW-CORE-S5-TRACE-1
test "a test's managed heap is bounded by --max-memory and a runaway allocation traps R_MEMORY_BUDGET" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    const source = "\nfunc fill(rounds: int) -> int:\n    mut values: int[] = []\n    for r in range(rounds):\n        values.append(r)\n    return len(values)\n\n" ++
        "func test_runaway() -> bool:\n    return fill(100000000) > 0\n\nfunc test_modest() -> bool:\n    return fill(1000000) == 1000000\n\n" ++
        "func test_words() -> bool:\n    mut words: str[] = []\n    for i in range(200000):\n        words.append(str(i))\n    return len(words) == 200000\n";
    try context.write("grow.selka", source);
    const bounded = try context.run("grow.selka", &.{ "--max-steps", "0", "--max-memory", "64M" });
    try expectStatus(context, bounded, 1);
    try verdict(bounded.report, "grow::test_modest", "passed");
    try verdict(bounded.report, "grow::test_words", "passed");
    const runaway = try reasonOf(bounded.report, "grow::test_runaway");
    try std.testing.expect(std.mem.startsWith(u8, runaway, "R_MEMORY_BUDGET\n"));
    try std.testing.expect(std.mem.indexOf(u8, runaway, "NativeTestProcessFailed") == null);
    try std.testing.expect(std.mem.indexOf(u8, runaway, "memory budget exhausted; raise it with --max-memory=SIZE") != null);
    // The ceiling is part of the receipt key: a lower one runs the passing tests again.
    const lower = try context.run("grow.selka", &.{ "--max-steps", "0", "--max-memory=4M", "--filter", "words" });
    try expectStatus(context, lower, 1);
    try std.testing.expect(std.mem.indexOf(u8, try reasonOf(lower.report, "grow::test_words"), "R_MEMORY_BUDGET") != null);
    try expectStatus(context, try context.run("grow.selka", &.{ "--max-memory", "12X" }), 2);
}

// spec-case: NEW-CORE-S4-TEST-2
test "directory assertion detects an omitted test verdict" {
    try std.testing.expectError(error.MissingTestVerdict, verdict(.null, "missing", "passed"));
}

// spec-case: NEW-CORE-S4-PROJECT-1
// spec-case: NEW-CORE-S4-TEST-3
test "warm project tests revalidate import policy and required generated interfaces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    const source = "import dep\n\npublic func test_dependency() -> bool:\n    return dep.value() == 3\n";
    try context.write("app.selka", source);
    try context.write("dep.selka", dependency_three);
    try expectStatus(context, try context.run("app.selka", &.{}), 0);
    try context.write("selka.json", "{\"version\":1,\"import_policy\":\"policy.json\"}");
    try context.write("policy.json", "{\"version\":1,\"default_action\":\"deny\",\"rules\":[]}");
    const denied = try context.run("app.selka", &.{});
    // A denied import policy exits 3, as the old CLI's policy gate does (NEW-CORE-S5-POLICY-1).
    try expectStatus(context, denied, 3);
    try std.testing.expect(std.mem.indexOf(u8, denied.stderr, "deny") != null);
    try context.write("policy.json", "{\"version\":1,\"default_action\":\"allow\",\"rules\":[]}");
    try expectStatus(context, try context.run("app.selka", &.{}), 0);
    try context.write("selka.json", "{\"version\":1,\"interface_files\":true}");
    const missing = try context.run("app.selka", &.{});
    try expectStatus(context, missing, 1);
    try std.testing.expect(std.mem.indexOf(u8, missing.stderr, "E_INTERFACE_FILE_STALE") != null);
    try context.writeInterfaces("app.selka");
    try expectStatus(context, try context.run("app.selka", &.{}), 0);
    try context.write("dep.api", "damaged interface\n");
    const stale = try context.run("app.selka", &.{});
    try expectStatus(context, stale, 1);
    try std.testing.expect(std.mem.indexOf(u8, stale.stderr, "E_INTERFACE_FILE_STALE") != null);
}

// spec-case: NEW-CORE-S4-TEST-4
test "providers preserve exported record layouts behind unchanged function signatures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("app.selka", "import dep\n\npublic func test_answer() -> bool:\n    return dep.answer()\n");
    const old = "\npublic record Cell:\n    value: int\n\npublic func answer() -> bool:\n    return Cell(value=1).value == 1\n";
    const changed = "\npublic record Cell:\n    value: bool\n\npublic func answer() -> bool:\n    return Cell(value=True).value\n";
    try context.write("dep.selka", old);
    try context.write("app.cases.json", try std.json.Stringify.valueAlloc(a, .{ .@"app::test_answer" = .{ .providers = .{ .@"dep.selka" = old } } }, .{}));
    try expectStatus(context, try context.run("app.selka", &.{}), 0);
    try context.write("app.cases.json", try std.json.Stringify.valueAlloc(a, .{ .@"app::test_answer" = .{ .providers = .{ .@"dep.selka" = changed } } }, .{}));
    // NATIVE-TEST-5: the changed declaration is refused before any body is checked.
    const refused = try context.run("app.selka", &.{});
    try expectStatus(context, refused, 2);
    try std.testing.expect(std.mem.indexOf(u8, refused.stderr, "IncompatibleProvider") != null);
}

// spec-case: NEW-CORE-S4-TEST-4
test "a provider may drop an import while its module keeps the same exports" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("app.selka", "import dep\n\npublic func test_answer() -> bool:\n    return dep.answer() == 3\n");
    try context.write("dep.selka", "import math\n\npublic func answer() -> int:\n    return math.clamp(9, 0, 3)\n");
    const stub = "\npublic func answer() -> int:\n    return 3\n";
    try context.write("app.cases.json", try std.json.Stringify.valueAlloc(a, .{ .@"app::test_answer" = .{ .providers = .{ .@"dep.selka" = stub } } }, .{}));
    const accepted = try context.run("app.selka", &.{});
    try expectStatus(context, accepted, 0);
    try verdict(accepted.report, "app::test_answer", "passed");
}

// spec-case: NEW-CORE-S4-TEST-4
test "providers preserve private parameter layouts of marked property tests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("app.selka", "import dep\n\npublic func test_answer() -> bool:\n    return dep.answer()\n");
    const old = "\nrecord Cell:\n    value: int\n\n@test\nfunc property(x: Cell) -> bool:\n    return x.value == x.value\n\npublic func answer() -> bool:\n    return True\n";
    const changed = "\nrecord Cell:\n    value: bool\n\n@test\nfunc property(x: Cell) -> bool:\n    return x.value == x.value\n\npublic func answer() -> bool:\n    return True\n";
    try context.write("dep.selka", old);
    try context.write("app.cases.json", try std.json.Stringify.valueAlloc(a, .{ .@"dep::property" = .{ .providers = .{ .@"dep.selka" = old } } }, .{}));
    try expectStatus(context, try context.run("app.selka", &.{ "--filter", "dep::property" }), 0);
    try context.write("app.cases.json", try std.json.Stringify.valueAlloc(a, .{ .@"dep::property" = .{ .providers = .{ .@"dep.selka" = changed } } }, .{}));
    const refused = try context.run("app.selka", &.{ "--filter", "dep::property" });
    try expectStatus(context, refused, 1);
    try std.testing.expect(std.mem.indexOf(u8, refused.stderr, "ProviderSignatureChanged") != null);
}

// spec-case: NEW-CORE-S4-PROJECT-1
test "nested standalone test entries use the configured project import root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("selka.json", "{\"version\":1}");
    try context.write("dep.selka", dependency_three);
    try context.write("tests/suite_test.selka", "import dep\n\npublic func test_dependency() -> bool:\n    return dep.value() == 3\n");
    const result = try context.run("tests/suite_test.selka", &.{});
    try expectStatus(context, result, 0);
    try verdict(result.report, "tests.suite_test::test_dependency", "passed");
}

// spec-case: NEW-CORE-S4-PROJECT-1
test "copied migrated propagation project retains all nine passing tests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    for (0..10) |index| {
        const name = if (index == 0) "propagation.selka" else try std.fmt.allocPrint(a, "propagation_case_{d}.selka", .{index});
        const source = try std.fs.path.join(a, &.{ tools.fixtures, "projects", "propagation", name });
        const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, source, a, .limited(1 << 20));
        try context.write(name, bytes);
    }
    const result = try context.run("propagation.selka", &.{});
    try expectStatus(context, result, 0);
    try std.testing.expectEqual(@as(u64, 9), v.number(v.get(result.report, "passed")));
}

// spec-case: NEW-CORE-S4-TEST-2
test "reserved embedded module names cannot account for an untested disk source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("app.selka", "import strings\n\npublic func test_ok() -> bool:\n    return True\n\nfunc main() -> int:\n    return 0\n");
    try context.write("strings.selka", "\nfunc test_hidden() -> bool:\n    return False\n");
    const result = try context.run(".", &.{});
    try expectStatus(context, result, 1);
    try std.testing.expect(v.number(v.get(result.report, "failed")) != 0);
}

// spec-case: NEW-CORE-S4-TEST-4
// spec-case: NEW-CORE-S4-TEST-3
test "runSelected and expectedResult malformed typed cases fail individually and never become cached successes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    const fixtures = [_]InvalidCase{
        .{ .name = "answer", .body = "public func test_answer() -> bool:\n    return True\n", .settings = "{\"arguments\":{\"unused\":\"x\"}}" },
        .{ .name = "answer", .body = "public func test_answer() -> bool:\n    return True\n", .settings = "{\"expected\":\"true\"}" },
        .{ .name = "zero", .body = "public func test_zero() -> int:\n    return 0\n", .settings = "{\"expected\":\"18446744073709551616\"}" },
        .{ .name = "zero", .body = "public func test_zero() -> int:\n    return 0\n", .settings = "{\"expected\":\"00\"}" },
        .{ .name = "text", .body = "public func test_text() -> str:\n    return \"\"\n", .settings = "{\"expected\":7}" },
        .{ .name = "list", .body = "public func test_list() -> int[]:\n    return []\n", .settings = "{\"expected\":null}" },
        .{ .name = "dict", .body = "public func test_dict() -> dict[int, int]:\n    return {1: 2}\n", .settings = "{\"expected\":[[\"1\"]]}" },
        .{ .name = "argument", .body = "public func test_argument(x: u8) -> bool:\n    return x == 0\n", .settings = "{\"arguments\":{\"x\":\"256\"}}" },
        .{ .name = "argument", .body = "public func test_argument(x: int) -> bool:\n    return True\n", .settings = "{\"arguments\":{\"x\":\"00\"}}" },
        .{ .name = "argument", .body = "public func test_argument(x: int) -> bool:\n    return True\n", .settings = "{\"arguments\":{\"x\":\"+0\"}}" },
        .{ .name = "argument", .body = "public func test_argument(x: int) -> bool:\n    return True\n", .settings = "{\"arguments\":{\"x\":\"-0\"}}" },
        .{ .name = "argument", .body = "public func test_argument(x: int) -> bool:\n    return True\n", .settings = "{\"arguments\":{\"x\":\"1_0\"}}" },
    };
    for (fixtures) |fixture| {
        const source = try std.fmt.allocPrint(a, "\n{s}\npublic func test_z_survivor() -> bool:\n    return True\n", .{fixture.body});
        const name = try std.fmt.allocPrint(a, "app::test_{s}", .{fixture.name});
        try context.write("app.selka", source);
        try context.write("app.cases.json", try std.fmt.allocPrint(a, "{{\"{s}\":{s}}}", .{ name, fixture.settings }));
        const cold = try context.run("app.selka", &.{});
        try expectStatus(context, cold, 1);
        try verdict(cold.report, name, "failed");
        try verdict(cold.report, "app::test_z_survivor", "passed");
        const warm = try context.run("app.selka", &.{});
        try expectStatus(context, warm, 1);
        try verdict(warm.report, name, "failed");
        try verdict(warm.report, "app::test_z_survivor", "cached");
    }
}

/// Where a directory run's roots run.
const Placement = enum { shared_check, children };

/// `selka test` of the whole project with `--json`, in a cache of its own for
/// `placement`; `SELKA_TEST_CHILDREN=1` gives every root a child process.
fn runDirectory(context: Context, placement: Placement) !Outcome {
    var environment = try std.testing.environ.createMap(context.arena);
    if (placement == .children) try environment.put("SELKA_TEST_CHILDREN", "1");
    const cache = try std.fs.path.join(context.arena, &.{ context.root, @tagName(placement) });
    const argv = [_][]const u8{ tools.core_path, "test", context.root, "--json", command_cache, cache, "--jobs", "2" };
    const result = try std.process.run(context.arena, std.testing.io, .{ .argv = &argv, .environ_map = &environment });
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, context.arena, result.stdout, .{}) catch .null;
    return .{ .status = switch (result.term) {
        .exited => |code| code,
        else => 255,
    }, .report = parsed, .stderr = result.stderr };
}

/// Both runs report the same tests, verdicts, reasons and sources, with the same status.
fn sameDirectoryReports(together: Outcome, children: Outcome) !void {
    try std.testing.expectEqual(children.status, together.status);
    const left = v.array(v.get(together.report, "tests"));
    const right = v.array(v.get(children.report, "tests"));
    try std.testing.expectEqual(right.len, left.len);
    for (left, right) |one, other| {
        try std.testing.expectEqualStrings(v.text(v.get(other, "name")), v.text(v.get(one, "name")));
        try std.testing.expectEqualStrings(v.text(v.get(other, "status")), v.text(v.get(one, "status")));
        try std.testing.expectEqualStrings(v.text(v.get(other, "reason")), v.text(v.get(one, "reason")));
    }
    const sources = v.array(v.get(together.report, "sources"));
    const expected_sources = v.array(v.get(children.report, "sources"));
    try std.testing.expectEqual(expected_sources.len, sources.len);
    for (sources, expected_sources) |one, other| try std.testing.expectEqualStrings(v.text(other), v.text(one));
}

const union_dep = "\npublic func value() -> int:\n    return 3\n\npublic func test_dep_value() -> bool:\n    return value() == 3\n";

// spec: NEW-CORE-TEST-UNION-1
test "a directory run that checks its roots together in process reports what one child per root reports" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const context: Context = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try context.write("selka.json", "{\"version\": 1}\n");
    try context.write("dep.selka", union_dep);
    try context.write("a_test.selka", "import dep\n\npublic func test_a() -> bool:\n    return dep.value() == 3\n\npublic func test_a_fails() -> bool:\n    return dep.value() == 4\n");
    try context.write("b_test.selka", "import dep\n\npublic func test_b(out: Stream) -> bool:\n    out.print(\"from b\")\n    return dep.value() > 0\n");
    try context.write("c_test.selka", "public func test_c() -> bool:\n    return 3 == 3\n");
    try context.write("app.selka", "import dep\n\nfunc main() -> int:\n    return dep.value()\n\npublic func test_app() -> bool:\n    return True\n");
    try sameDirectoryReports(try runDirectory(context, .shared_check), try runDirectory(context, .children));
    // After an edit both rerun the same tests and replay the rest.
    try context.write("dep.selka", "\npublic func value() -> int:\n    mut total = 1\n    return total + 2\n\npublic func test_dep_value() -> bool:\n    return value() == 3\n");
    const edited = try runDirectory(context, .shared_check);
    try sameDirectoryReports(edited, try runDirectory(context, .children));
    try expectStatus(context, edited, 1);
    // A root that does not check fails alone in both, its diagnostics on stderr.
    try context.write("b_test.selka", "import dep\n\npublic func test_b() -> bool:\n    return dep.value() == \"three\"\n");
    const broken = try runDirectory(context, .shared_check);
    try sameDirectoryReports(broken, try runDirectory(context, .children));
    try std.testing.expect(std.mem.indexOf(u8, broken.stderr, "b_test.selka") != null);
}
