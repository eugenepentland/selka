//! Stage 4 of the test-loop plan (`docs/audits/test-loop-plan-2026-11-09.md`, decisions in
//! `experiments/test-loop-20261109/DECISIONS.md`, D-TL4-1): key derivation keys each function's lowering by the engine's
//! `module-check` part when it has one, as a build does, instead of hashing its tree. The tree hash stays as the oracle
//! (`SELKA_ENGINE_DECIDE_LOWERING=0`): every test's key must be the same either way.
const std = @import("std");
const options = @import("core_test_options");
const v = @import("property_value.zig");

const library = "public func value() -> int:\n    return 3\n\n\npublic func test_lib() -> bool:\n    return value() == 3\n";
const first_root = "import lib\n\n\npublic func test_one() -> bool:\n    return lib.value() + 1 == 4\n";
const second_root = "import lib\n\n\npublic func test_two() -> bool:\n    return lib.value() + 2 == 5\n";
const dependency = "public func value() -> int:\n    return 3\n";
const provided = "public func value() -> int:\n    return 3\n";
const app = "import dep\n\n\npublic func test_dependency() -> bool:\n    return dep.value() == 3\n\n\npublic func test_plain() -> bool:\n    return True\n";

/// What one run of `selka test --json` found: each test's key, and how many functions key derivation keyed by a part.
const Keys = struct { by_name: std.array_hash_map.String([]const u8), by_part: i64 };

/// A temporary project and the runs over it, each in a cache of its own.
const Project = struct {
    arena: std.mem.Allocator,
    root: []const u8,

    fn write(self: Project, name: []const u8, data: []const u8) !void {
        const path = try std.fs.path.join(self.arena, &.{ self.root, "project", name });
        try std.Io.Dir.cwd().createDirPath(std.testing.io, std.fs.path.dirname(path).?);
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = data });
    }

    /// `selka test TARGET --json --force` in the cache `cache`, with the engine's parts or (`tree`) without them.
    fn keys(self: Project, target: []const u8, cache: []const u8, tree: bool) !Keys {
        var environment = try options.privateEnvironment(self.arena);
        if (tree) try environment.put("SELKA_ENGINE_DECIDE_LOWERING", "0");
        const path = try std.fs.path.join(self.arena, &.{ self.root, "project", target });
        const directory = try std.fs.path.join(self.arena, &.{ self.root, cache });
        const argv = [_][]const u8{ options.corePath(), "test", path, "--json", "--force", "--cache-dir", directory, "--jobs", "1" };
        const result = try std.process.run(self.arena, std.testing.io, .{ .argv = &argv, .environ_map = &environment });
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
        const report = try std.json.parseFromSliceLeaky(std.json.Value, self.arena, result.stdout, .{});
        var found: Keys = .{ .by_name = .empty, .by_part = 0 };
        for (v.array(v.get(report, "tests"))) |item| {
            const cache_value = v.get(item, "cache");
            try found.by_name.put(self.arena, v.text(v.get(item, "name")), v.text(v.get(cache_value, "key")));
            const lowering = v.get(v.get(v.get(cache_value, "work"), "producer"), "lowering");
            if (lowering == .object) found.by_part += @intCast(v.number(v.get(lowering, "by_part")));
        }
        return found;
    }
};

/// Every test has a key, and the keys with the engine's parts are the tree hash's, name by name.
fn expectSameKeys(parts: Keys, tree: Keys) !void {
    try std.testing.expectEqual(tree.by_name.count(), parts.by_name.count());
    var all = tree.by_name.iterator();
    while (all.next()) |entry| {
        const other = parts.by_name.get(entry.key_ptr.*) orelse return error.MissingTestVerdict;
        try std.testing.expectEqual(@as(usize, 64), entry.value_ptr.*.len);
        try std.testing.expectEqualStrings(entry.value_ptr.*, other);
    }
}

// spec: TEST-LOOP-PART-KEYS-1
test "the engine's checked-body parts key a test as the tree hash does: a directory's shared check and a root's own" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try project.write("lib.selka", library);
    try project.write("one.selka", first_root);
    try project.write("two.selka", second_root);
    try project.write("selka.json", "{\"version\":2}");
    // The directory's two roots share one check, which the engine now decides; each run is cold, in its own cache.
    const shared_parts = try project.keys(".", "cache-shared-parts", false);
    const shared_tree = try project.keys(".", "cache-shared-tree", true);
    try expectSameKeys(shared_parts, shared_tree);
    try std.testing.expect(shared_parts.by_part > 0);
    try std.testing.expectEqual(@as(i64, 0), shared_tree.by_part);
    // A file run checks the root alone, in its own session.
    const own_parts = try project.keys("two.selka", "cache-own-parts", false);
    const own_tree = try project.keys("two.selka", "cache-own-tree", true);
    try expectSameKeys(own_parts, own_tree);
    try std.testing.expect(own_parts.by_part > 0);
    // The same root after an edit, warm: the parts of the changed module move, the others are served.
    try project.write("lib.selka", "public func value() -> int:\n    return 1 + 2\n\n\npublic func test_lib() -> bool:\n    return value() == 3\n");
    try expectSameKeys(try project.keys("two.selka", "cache-own-parts", false), try project.keys("two.selka", "cache-own-tree", true));
}

// spec-case: TEST-LOOP-PART-KEYS-1
test "a provider group keys its functions by their trees, and every key is still the tree hash's" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project: Project = .{ .arena = a, .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a) };
    try project.write("dep.selka", dependency);
    try project.write("app.selka", app);
    try project.write("selka.json", "{\"version\":2}");
    const cases = try std.json.Stringify.valueAlloc(a, .{ .@"app::test_dependency" = .{ .providers = .{ .@"dep.selka" = provided } } }, .{});
    try project.write("app.cases.json", cases);
    try expectSameKeys(try project.keys("app.selka", "cache-parts", false), try project.keys("app.selka", "cache-tree", true));
}
