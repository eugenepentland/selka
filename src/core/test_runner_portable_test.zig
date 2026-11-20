//! Actual native commands qualify success sharing through the engine's shared tier across two roots. Private caches are
//! removed before transport assertions, so a local record cannot masquerade as a hit in the tier.
const std = @import("std");
const tools = @import("core_test_options");
const support = @import("test_support.zig");
const value = @import("property_value.zig");
const leakcheck = "SELKA_CORE_LEAKCHECK";
const host_name = "app::test_host";

const Outcome = struct { status: u8, report: std.json.Value, stderr: []const u8 };
const Invocation = struct { project: []const u8, source: []const u8 = "app.selka", extra: []const []const u8 = &.{} };

const Projects = struct {
    arena: std.mem.Allocator,
    root: []const u8,
    environment: std.process.Environ.Map,

    fn init(a: std.mem.Allocator, root: []const u8) !Projects {
        // The project's own `--shared-cache-dir` is the only shared store these
        // tests see: the gate's or a default compiler or receipt store is disabled.
        var environment = try tools.privateEnvironment(a);
        errdefer environment.deinit();
        try environment.put(leakcheck, "0");
        try environment.put("SELKA_CACHE_PLAN_MODE", "component");
        const projects: Projects = .{ .arena = a, .root = root, .environment = environment };
        try projects.write("a", "app.selka", app);
        try projects.write("b", "app.selka", app);
        try projects.write("a", "dep.selka", dependency);
        try projects.write("b", "dep.selka", dependency);
        try projects.write("a", "selka.json", configuration);
        try projects.write("b", "selka.json", configuration);
        return projects;
    }

    fn path(self: Projects, parts: []const []const u8) ![]const u8 {
        var all: std.ArrayList([]const u8) = .empty;
        try all.append(self.arena, self.root);
        try all.appendSlice(self.arena, parts);
        return std.fs.path.join(self.arena, all.items);
    }

    fn write(self: Projects, project: []const u8, name: []const u8, data: []const u8) !void {
        const path_name = try self.path(&.{ project, name });
        try std.Io.Dir.cwd().createDirPath(std.testing.io, std.fs.path.dirname(path_name).?);
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path_name, .data = data });
    }

    fn remove(self: Projects, project: []const u8, name: []const u8) !void {
        try std.Io.Dir.cwd().deleteFile(std.testing.io, try self.path(&.{ project, name }));
    }

    fn reset(self: Projects, project: []const u8) !void {
        try std.Io.Dir.cwd().deleteTree(std.testing.io, try self.path(&.{ project, "private" }));
    }

    fn run(self: *const Projects, invocation: Invocation) !Outcome {
        try support.requireReleaseArgs(invocation.extra);
        var args: std.ArrayList([]const u8) = .empty;
        const source = try self.path(&.{ invocation.project, invocation.source });
        const private = try self.path(&.{ invocation.project, "private" });
        const store = try self.path(&.{"shared"});
        try args.appendSlice(self.arena, &.{ tools.corePath(), "test", source, "--json", "--cache-dir", private });
        try args.appendSlice(self.arena, &.{ "--shared-cache-dir", store, "--jobs", "2", "--property-runs", "5" });
        try args.appendSlice(self.arena, invocation.extra);
        const result = try std.process.run(self.arena, std.testing.io, .{ .argv = args.items, .environ_map = &self.environment });
        return parse(self.arena, result);
    }

    fn again(self: *const Projects, invocation: Invocation) !Outcome {
        try self.reset(invocation.project);
        return self.run(invocation);
    }
};

fn parse(a: std.mem.Allocator, result: std.process.RunResult) !Outcome {
    const parsed = if (result.stdout.len == 0) .null else try std.json.parseFromSliceLeaky(std.json.Value, a, result.stdout, .{});
    return .{ .status = switch (result.term) {
        .exited => |code| code,
        else => 255,
    }, .report = parsed, .stderr = result.stderr };
}

const app =
    \\import dep
    \\
    \\public func test_dependency() -> bool:
    \\    return dep.value() == 3
    \\
    \\public func test_constant() -> bool:
    \\    return True
    \\
;
const configuration = "{\"version\":2}";
const dependency = @import("cache_fixture_sources_test.zig").dependency;
const changed_dependency = @import("cache_fixture_sources_test.zig").changed_dependency;

fn item(report: std.json.Value, name: []const u8) !std.json.Value {
    for (value.array(value.get(report, "tests"))) |test_value| {
        if (std.mem.eql(u8, value.text(value.get(test_value, "name")), name)) return test_value;
    }
    return error.MissingTestVerdict;
}

fn status(result: Outcome, expected: u8) !void {
    try std.testing.expectEqualStrings("", result.stderr);
    try std.testing.expectEqual(expected, result.status);
}

fn verdict(result: Outcome, name: []const u8, expected: []const u8) !void {
    try std.testing.expectEqualStrings(expected, value.text(value.get(try item(result.report, name), "status")));
}

fn shared(result: Outcome, name: []const u8) !void {
    try verdict(result, name, "cached");
    const cache = value.get(try item(result.report, name), "cache");
    try std.testing.expectEqualStrings("engine-hit", value.text(value.get(cache, "reason")));
    // The tier holds the IR key, which names every path relative to the root (RECEIPT-PATHS-1).
    try std.testing.expectEqual(@as(usize, 64), value.text(value.get(cache, "key")).len);
}

fn bothShared(result: Outcome) !void {
    try status(result, 0);
    try std.testing.expectEqual(@as(u64, 2), value.number(value.get(result.report, "cached")));
    try shared(result, "app::test_dependency");
    try shared(result, "app::test_constant");
}

// spec: NEW-CORE-TEST-SHARED-1
test "the shared tier crosses roots, and an edit reruns only the tests that reach it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    const cold = try projects.run(.{ .project = "a" });
    try status(cold, 0);
    try std.testing.expectEqual(@as(u64, 2), value.number(value.get(cold.report, "passed")));
    try bothShared(try projects.run(.{ .project = "b" }));
    try projects.write("b", "dep.selka", changed_dependency);
    const edited = try projects.again(.{ .project = "b" });
    try status(edited, 1);
    try verdict(edited, "app::test_dependency", "failed");
    try shared(edited, "app::test_constant");
    try projects.write("b", "dep.selka", dependency);
    try bothShared(try projects.again(.{ .project = "b" }));
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "the shared tier binds mode settings and the keyed environment, and force, facts, leak checks and no-cache execute" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try status(try projects.run(.{ .project = "a" }), 0);
    try controlMatrix(&projects);
    try std.testing.expectEqualStrings("0", projects.environment.get(leakcheck).?);
}

fn freshPair(result: Outcome) !void {
    try status(result, 0);
    try std.testing.expectEqual(@as(u64, 2), value.number(value.get(result.report, "passed")));
    try std.testing.expectEqual(@as(u64, 0), value.number(value.get(result.report, "cached")));
}

fn controlMatrix(projects: *Projects) !void {
    try freshPair(try projects.run(.{ .project = "b", .extra = &.{"--force"} }));
    try freshPair(try projects.again(.{ .project = "b", .extra = &.{"--verify-facts"} }));
    try freshPair(try projects.again(.{ .project = "b", .extra = &.{"--no-cache"} }));
    try projects.environment.put(leakcheck, "1");
    try freshPair(try projects.again(.{ .project = "b" }));
    try projects.environment.put(leakcheck, "0");
    try projects.environment.put("SELKA_PORTABLE_PROBE", "changed");
    try freshPair(try projects.again(.{ .project = "b" }));
    _ = projects.environment.swapRemove("SELKA_PORTABLE_PROBE");
    try bothShared(try projects.again(.{ .project = "b" }));
    try freshPair(try projects.again(.{ .project = "b", .extra = &.{"--release"} }));
    try bothShared(try projects.again(.{ .project = "a", .extra = &.{"--release"} }));
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "the shared tier honors configuration and cases before trusting a foreign success" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try status(try projects.run(.{ .project = "a" }), 0);
    const matching_cases = "{\"app::test_dependency\":{\"expected\":true}}";
    try projects.write("a", "app.cases.json", matching_cases);
    try projects.write("b", "app.cases.json", matching_cases);
    try freshPair(try projects.again(.{ .project = "a" }));
    try bothShared(try projects.again(.{ .project = "b" }));
    try projects.write("b", "app.cases.json", "{\"app::test_dependency\":{\"expected\":false}}");
    const cases = try projects.again(.{ .project = "b" });
    try status(cases, 1);
    try verdict(cases, "app::test_dependency", "failed");
    try projects.remove("b", "app.cases.json");
    try bothShared(try projects.again(.{ .project = "b" }));
    try projects.write("b", "selka.json", "{\"version\":1,\"budgets\":{\"max_file_bytes\":16}}");
    const configured = try projects.again(.{ .project = "b" });
    try std.testing.expectEqual(@as(u8, 1), configured.status);
    try std.testing.expect(std.mem.indexOf(u8, configured.stderr, "E_PROJECT_BYTES") != null);
    try projects.write("b", "selka.json", configuration);
    try bothShared(try projects.again(.{ .project = "b" }));
}

const embedded = "public func test_asset() -> bool:\n    return len(embed_bytes(\"data.bin\")) == 1\n";
const identity_query = "import strings\nfunc compute() -> int:\n    return 3\n\npublic func test_identity() -> bool:\n    return strings.char_count(function_digest(compute)) == 64\n";
const environment_query = "public func test_environment(env: Environment) -> bool:\n    return len(env.names()) == 0\n";
const host_query = "extern func stamp(host: Host) -> int\n\npublic func test_host(host: Host) -> bool:\n    return stamp(host) > 0\n";

// spec: EXEC-SHARED-1
// spec-case: NEW-CORE-TEST-SHARED-1
test "the shared tier shares introspection and capability stand-ins but refuses Host input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try boundaryMatrix(&projects);
}

fn boundaryMatrix(projects: *Projects) !void {
    // A function digest shares its exact program-and-runner execution key. An
    // Environment parameter receives the trial's empty stand-in and can also
    // share its earlier IR receipt; neither observes the live host environment.
    const boundaries = [_]struct { source: []const u8, name: []const u8, receiving: []const u8 }{
        .{ .source = identity_query, .name = "app::test_identity", .receiving = "cached" },
        .{ .source = environment_query, .name = "app::test_environment", .receiving = "cached" },
    };
    for (boundaries) |boundary| {
        try projects.write("a", "app.selka", boundary.source);
        try projects.write("b", "app.selka", boundary.source);
        const left = try projects.again(.{ .project = "a" });
        const right = try projects.again(.{ .project = "b" });
        try status(left, 0);
        try status(right, 0);
        try verdict(left, boundary.name, "passed");
        try verdict(right, boundary.name, boundary.receiving);
    }
    try projects.write("a", "app.selka", host_query);
    try projects.write("b", "app.selka", host_query);
    const left = try projects.again(.{ .project = "a" });
    const right = try projects.again(.{ .project = "b" });
    try status(left, 1);
    try status(right, 1);
    try verdict(left, host_name, "failed");
    try verdict(right, host_name, "failed");
    try std.testing.expect(std.mem.indexOf(u8, value.text(value.get(try item(right.report, host_name), "reason")), "Host capability") != null);
}

// spec-case: EXEC-RECEIPT-1
test "the shared tier binds changed callable programs by their program and honors force" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    const mixed = identity_query ++ "\npublic func test_plain() -> bool:\n    return True\n";
    try projects.write("a", "app.selka", mixed);
    try projects.write("b", "app.selka", mixed);
    try verdict(try projects.again(.{ .project = "a" }), "app::test_identity", "passed");
    const reused = try projects.again(.{ .project = "b" });
    try verdict(reused, "app::test_identity", "cached");
    try shared(reused, "app::test_plain");
    const cache = value.get(try item(reused.report, "app::test_identity"), "cache");
    try std.testing.expectEqualStrings("engine-program-hit", value.text(value.get(cache, "reason")));
    try std.testing.expectEqual(@as(u64, 1), value.number(value.get(value.get(reused.report, "exec_receipts"), "hits")));
    try verdict(try projects.again(.{ .project = "b", .extra = &.{"--force"} }), "app::test_identity", "passed");
    try projects.write("b", "app.selka", "import strings\nfunc compute() -> int:\n    return 4\n\n" ++
        "public func test_identity() -> bool:\n    return strings.char_count(function_digest(compute)) == 64\n\n" ++
        "public func test_plain() -> bool:\n    return True\n");
    try verdict(try projects.again(.{ .project = "b" }), "app::test_identity", "passed");
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "the shared tier leaves provider overlays private" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    const cases = try std.json.Stringify.valueAlloc(arena.allocator(), .{ .@"app::test_dependency" = .{ .providers = .{ .@"dep.selka" = dependency } } }, .{});
    try projects.write("a", "app.cases.json", cases);
    try projects.write("b", "app.cases.json", cases);
    try freshPair(try projects.run(.{ .project = "a" }));
    const receiving = try projects.run(.{ .project = "b" });
    try status(receiving, 0);
    try verdict(receiving, "app::test_dependency", "passed");
    try shared(receiving, "app::test_constant");
    try std.testing.expectEqual(@as(u64, 1), value.number(value.get(receiving.report, "passed")));
    try std.testing.expectEqual(@as(u64, 1), value.number(value.get(receiving.report, "cached")));
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "the shared tier cannot hide embedded asset mutations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try projects.write("a", "app.selka", embedded);
    try projects.write("b", "app.selka", embedded);
    try projects.write("a", "data.bin", "x");
    try projects.write("b", "data.bin", "xx");
    try status(try projects.run(.{ .project = "a" }), 0);
    const edited = try projects.run(.{ .project = "b" });
    try status(edited, 1);
    try verdict(edited, "app::test_asset", "failed");
    try projects.write("b", "data.bin", "x");
    const restored = try projects.again(.{ .project = "b" });
    try status(restored, 0);
    try shared(restored, "app::test_asset");
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "the shared tier forwards through directory fanout without a private report" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try projects.write("a", "suite/first.selka", "public func test_first() -> bool:\n    return True\n");
    try projects.write("b", "suite/first.selka", "public func test_first() -> bool:\n    return True\n");
    try projects.write("a", "suite/second.selka", "public func test_second() -> bool:\n    return 2 + 3 == 5\n");
    try projects.write("b", "suite/second.selka", "public func test_second() -> bool:\n    return 2 + 3 == 5\n");
    const cold = try projects.run(.{ .project = "a", .source = "suite" });
    const warm = try projects.run(.{ .project = "b", .source = "suite" });
    try status(cold, 0);
    try status(warm, 0);
    try std.testing.expectEqual(@as(u64, 2), value.number(value.get(cold.report, "passed")));
    try std.testing.expectEqual(@as(u64, 2), value.number(value.get(warm.report, "cached")));
    try shared(warm, "suite.first::test_first");
    try shared(warm, "suite.second::test_second");
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "the shared tier preserves absolute path literals as ordinary values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    const left = try projects.path(&.{"a"});
    const right = try projects.path(&.{"b"});
    const template = "public func test_literal() -> bool:\n    return \"{s}\" == \"{s}\"\n";
    try projects.write("a", "app.selka", try std.fmt.allocPrint(arena.allocator(), template, .{ left, left }));
    try projects.write("b", "app.selka", try std.fmt.allocPrint(arena.allocator(), template, .{ right, left }));
    try status(try projects.run(.{ .project = "a" }), 0);
    const changed = try projects.run(.{ .project = "b" });
    try status(changed, 1);
    try verdict(changed, "app::test_literal", "failed");
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "the shared tier refuses an escaping source symlink before publication" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try projects.write("external", "dep.selka", dependency);
    try projects.remove("a", "dep.selka");
    try projects.remove("b", "dep.selka");
    try temporary.dir.symLink(std.testing.io, "../external/dep.selka", "a/dep.selka", .{});
    try temporary.dir.symLink(std.testing.io, "../external/dep.selka", "b/dep.selka", .{});
    try freshPair(try projects.run(.{ .project = "a" }));
    try freshPair(try projects.again(.{ .project = "b" }));
    try projects.write("external", "dep.selka", changed_dependency);
    const changed = try projects.again(.{ .project = "b" });
    try status(changed, 1);
    try verdict(changed, "app::test_dependency", "failed");
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "the shared tier cannot mask a new embedded symlink escape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try projects.write("a", "app.selka", embedded);
    try projects.write("b", "app.selka", embedded);
    try projects.write("a", "data.bin", "x");
    try projects.write("external", "data.bin", "x");
    try status(try projects.run(.{ .project = "a" }), 0);
    try temporary.dir.symLink(std.testing.io, "../external/data.bin", "b/data.bin", .{});
    const changed = try projects.run(.{ .project = "b" });
    try std.testing.expectEqual(@as(u8, 1), changed.status);
    try std.testing.expect(std.mem.indexOf(u8, changed.stderr, "E_EMBED_ESCAPE") != null);
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "validateShared rejects a bad configured format before a warm private report replay" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try status(try projects.run(.{ .project = "a" }), 0);
    try projects.write("shared", "native-tests-v3/format", "unknown shared format");
    const rejected = try projects.run(.{ .project = "a" });
    try std.testing.expectEqual(@as(u8, 2), rejected.status);
    try std.testing.expect(std.mem.indexOf(u8, rejected.stderr, "ReadFailed") != null);
    try std.testing.expect(rejected.report == .null);
}
