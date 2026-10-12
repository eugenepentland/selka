//! Actual native commands qualify disposable success sharing across two roots.
//! Private caches are removed before transport assertions, so local replay cannot
//! masquerade as a hit in the shared store.
const std = @import("std");
const tools = @import("core_test_options");
const value = @import("property_value.zig");
const leakcheck = "MYL_CORE_LEAKCHECK";
const host_name = "app::test_host";

const Outcome = struct { status: u8, report: std.json.Value, stderr: []const u8 };
const Invocation = struct { project: []const u8, source: []const u8 = "app.my", extra: []const []const u8 = &.{} };

const Projects = struct {
    arena: std.mem.Allocator,
    root: []const u8,
    environment: std.process.Environ.Map,

    fn init(a: std.mem.Allocator, root: []const u8) !Projects {
        var environment = try std.testing.environ.createMap(a);
        errdefer environment.deinit();
        _ = environment.swapRemove("MYLANG_TEST_SHARED_CACHE");
        try environment.put(leakcheck, "0");
        try environment.put("MYLANG_CACHE_PLAN_MODE", "component");
        const projects: Projects = .{ .arena = a, .root = root, .environment = environment };
        try projects.write("a", "app.my", app);
        try projects.write("b", "app.my", app);
        try projects.write("a", "dep.my", dependency);
        try projects.write("b", "dep.my", dependency);
        try projects.write("a", "mylang.json", configuration);
        try projects.write("b", "mylang.json", configuration);
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
const dependency = "public func value() -> int:\n    return 3\n";
const changed_dependency = "public func value() -> int:\n    return 4\n";

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
    try std.testing.expectEqualStrings("shared-receipt-hit", value.text(value.get(cache, "reason")));
    try std.testing.expectEqualStrings("portable-reachable-ir", value.text(value.get(cache, "key_method")));
}

fn bothShared(result: Outcome) !void {
    try status(result, 0);
    try std.testing.expectEqual(@as(u64, 2), value.number(value.get(result.report, "cached")));
    try shared(result, "app::test_dependency");
    try shared(result, "app::test_constant");
}

// spec: NEW-CORE-TEST-SHARED-1
test "portable shared receipts cross roots and sharedKeys invalidate only reachable dependency edits" {
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
    try projects.write("b", "dep.my", changed_dependency);
    const edited = try projects.again(.{ .project = "b" });
    try status(edited, 1);
    try verdict(edited, "app::test_dependency", "failed");
    try shared(edited, "app::test_constant");
    try projects.write("b", "dep.my", dependency);
    try bothShared(try projects.again(.{ .project = "b" }));
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "portable shared receipts bind mode settings and keyed environment while force facts leak and no-cache execute" {
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
    try freshPair(try projects.again(.{ .project = "b", .extra = &.{"--release"} }));
    try bothShared(try projects.again(.{ .project = "a", .extra = &.{"--release"} }));
    try projects.environment.put("MYLANG_PORTABLE_PROBE", "changed");
    try freshPair(try projects.again(.{ .project = "b" }));
    _ = projects.environment.swapRemove("MYLANG_PORTABLE_PROBE");
    try bothShared(try projects.again(.{ .project = "b" }));
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "portable shared receipts honor configuration and cases before trusting a foreign success" {
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
    try projects.write("b", "mylang.json", "{\"version\":1,\"budgets\":{\"max_file_bytes\":16}}");
    const configured = try projects.again(.{ .project = "b" });
    try std.testing.expectEqual(@as(u8, 1), configured.status);
    try std.testing.expect(std.mem.indexOf(u8, configured.stderr, "E_PROJECT_BYTES") != null);
    try projects.write("b", "mylang.json", configuration);
    try bothShared(try projects.again(.{ .project = "b" }));
}

const embedded = "public func test_asset() -> bool:\n    return len(embed_bytes(\"data.bin\")) == 1\n";
const identity_query = "func compute() -> int:\n    return 3\n\npublic func test_identity() -> bool:\n    return len(function_digest(compute)) == 64\n";
const environment_query = "public func test_environment(env: Environment) -> bool:\n    return len(env.names()) == 0\n";
const host_query = "extern func stamp(host: Host) -> int effects(host)\n\npublic func test_host(host: Host) -> bool:\n    return stamp(host) > 0\n";

// spec-case: NEW-CORE-TEST-SHARED-1
test "portable shared receipts refuse introspection environment authority and unsupported Host input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try boundaryMatrix(&projects);
    try std.testing.expectEqual(@as(u64, 0), try receiptCount(projects));
}

fn boundaryMatrix(projects: *Projects) !void {
    const boundaries = [_]struct { source: []const u8, name: []const u8 }{
        .{ .source = identity_query, .name = "app::test_identity" },
        .{ .source = environment_query, .name = "app::test_environment" },
    };
    for (boundaries) |boundary| {
        try projects.write("a", "app.my", boundary.source);
        try projects.write("b", "app.my", boundary.source);
        const left = try projects.again(.{ .project = "a" });
        const right = try projects.again(.{ .project = "b" });
        try status(left, 0);
        try status(right, 0);
        try verdict(left, boundary.name, "passed");
        try verdict(right, boundary.name, "passed");
    }
    try projects.write("a", "app.my", host_query);
    try projects.write("b", "app.my", host_query);
    const left = try projects.again(.{ .project = "a" });
    const right = try projects.again(.{ .project = "b" });
    try status(left, 1);
    try status(right, 1);
    try verdict(left, host_name, "failed");
    try verdict(right, host_name, "failed");
    try std.testing.expect(std.mem.indexOf(u8, value.text(value.get(try item(right.report, host_name), "reason")), "Host capability") != null);
}

fn receiptCount(projects: Projects) !u64 {
    const path_name = try projects.path(&.{ "shared", "native-tests-v2", "receipts" });
    var directory = std.Io.Dir.cwd().openDir(std.testing.io, path_name, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return 0;
        return err;
    };
    defer directory.close(std.testing.io);
    var iterator = directory.iterate();
    var count: u64 = 0;
    while (try iterator.next(std.testing.io)) |entry| if (std.mem.endsWith(u8, entry.name, ".pass")) {
        count += 1;
    };
    return count;
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "portable shared receipts cannot hide embedded asset mutations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try projects.write("a", "app.my", embedded);
    try projects.write("b", "app.my", embedded);
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
test "portable shared receipts forward through directory fanout without private report replay" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try projects.write("a", "suite/first.my", "public func test_first() -> bool:\n    return True\n");
    try projects.write("b", "suite/first.my", "public func test_first() -> bool:\n    return True\n");
    try projects.write("a", "suite/second.my", "public func test_second() -> bool:\n    return 2 + 3 == 5\n");
    try projects.write("b", "suite/second.my", "public func test_second() -> bool:\n    return 2 + 3 == 5\n");
    const cold = try projects.run(.{ .project = "a", .source = "suite" });
    const warm = try projects.run(.{ .project = "b", .source = "suite" });
    try status(cold, 0);
    try status(warm, 0);
    try std.testing.expectEqual(@as(u64, 2), value.number(value.get(cold.report, "passed")));
    try std.testing.expectEqual(@as(u64, 2), value.number(value.get(warm.report, "cached")));
    try shared(warm, "suite.first::test_first");
    try shared(warm, "suite.second::test_second");
}

fn damageReceipts(projects: Projects) !void {
    var directory = try std.Io.Dir.cwd().openDir(std.testing.io, try projects.path(&.{ "shared", "native-tests-v2", "receipts" }), .{ .iterate = true });
    defer directory.close(std.testing.io);
    var iterator = directory.iterate();
    var damaged: usize = 0;
    while (try iterator.next(std.testing.io)) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".pass")) continue;
        try directory.writeFile(std.testing.io, .{ .sub_path = entry.name, .data = "truncated shared success" });
        damaged += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), damaged);
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "portable shared receipt Store.hit corruption misses and refills verified successes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try status(try projects.run(.{ .project = "a" }), 0);
    try damageReceipts(projects);
    try freshPair(try projects.run(.{ .project = "b" }));
    try bothShared(try projects.again(.{ .project = "b" }));
}

const Publisher = struct {
    projects: Projects,
    project: []const u8,
    storage: std.heap.ArenaAllocator,
    result: ?Outcome = null,
    failure: ?anyerror = null,

    fn start(self: *Publisher) void {
        self.projects.arena = self.storage.allocator();
        self.result = self.projects.run(.{ .project = self.project }) catch |err| {
            self.failure = err;
            return;
        };
    }
};

fn publishers(projects: Projects, backing: std.mem.Allocator) !void {
    var left: Publisher = .{ .projects = projects, .project = "a", .storage = std.heap.ArenaAllocator.init(backing) };
    defer left.storage.deinit();
    var right: Publisher = .{ .projects = projects, .project = "b", .storage = std.heap.ArenaAllocator.init(backing) };
    defer right.storage.deinit();
    const a = try std.Thread.spawn(.{}, Publisher.start, .{&left});
    const b = spawned: {
        errdefer a.join();
        break :spawned try std.Thread.spawn(.{}, Publisher.start, .{&right});
    };
    a.join();
    b.join();
    try std.testing.expectEqual(@as(?anyerror, null), left.failure);
    try std.testing.expectEqual(@as(?anyerror, null), right.failure);
    try status(left.result.?, 0);
    try status(right.result.?, 0);
    try std.testing.expectEqual(@as(u64, 2), value.number(value.get(left.result.?.report, "passed")) + value.number(value.get(left.result.?.report, "cached")));
    try std.testing.expectEqual(@as(u64, 2), value.number(value.get(right.result.?.report, "passed")) + value.number(value.get(right.result.?.report, "cached")));
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "portable shared receipt Store.save simultaneous publishers produce replayable successes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try publishers(projects, std.heap.page_allocator);
    try bothShared(try projects.again(.{ .project = "b" }));
    try std.testing.expectEqual(@as(u64, 2), try receiptCount(projects));
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "portable shared receipts preserve absolute path literals as ordinary values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    const left = try projects.path(&.{"a"});
    const right = try projects.path(&.{"b"});
    const template = "public func test_literal() -> bool:\n    return \"{s}\" == \"{s}\"\n";
    try projects.write("a", "app.my", try std.fmt.allocPrint(arena.allocator(), template, .{ left, left }));
    try projects.write("b", "app.my", try std.fmt.allocPrint(arena.allocator(), template, .{ right, left }));
    try status(try projects.run(.{ .project = "a" }), 0);
    const changed = try projects.run(.{ .project = "b" });
    try status(changed, 1);
    try verdict(changed, "app::test_literal", "failed");
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "portable shared receipts refuse an escaping source symlink before publication" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try projects.write("external", "dep.my", dependency);
    try projects.remove("a", "dep.my");
    try projects.remove("b", "dep.my");
    try temporary.dir.symLink(std.testing.io, "../external/dep.my", "a/dep.my", .{});
    try temporary.dir.symLink(std.testing.io, "../external/dep.my", "b/dep.my", .{});
    try freshPair(try projects.run(.{ .project = "a" }));
    try freshPair(try projects.run(.{ .project = "b" }));
    try std.testing.expectEqual(@as(u64, 0), try receiptCount(projects));
    try projects.write("external", "dep.my", changed_dependency);
    const changed = try projects.again(.{ .project = "b" });
    try status(changed, 1);
    try verdict(changed, "app::test_dependency", "failed");
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "portable shared receipts cannot mask a new embedded symlink escape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try projects.write("a", "app.my", embedded);
    try projects.write("b", "app.my", embedded);
    try projects.write("a", "data.bin", "x");
    try projects.write("external", "data.bin", "x");
    try status(try projects.run(.{ .project = "a" }), 0);
    try temporary.dir.symLink(std.testing.io, "../external/data.bin", "b/data.bin", .{});
    const changed = try projects.run(.{ .project = "b" });
    try std.testing.expectEqual(@as(u8, 1), changed.status);
    try std.testing.expect(std.mem.indexOf(u8, changed.stderr, "E_EMBED_ESCAPE") != null);
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "portable validateShared rejects a bad configured format before warm private manifest replay" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try status(try projects.run(.{ .project = "a" }), 0);
    try projects.write("shared", "native-tests-v2/format", "unknown shared format");
    const rejected = try projects.run(.{ .project = "a" });
    try std.testing.expectEqual(@as(u8, 2), rejected.status);
    try std.testing.expect(std.mem.indexOf(u8, rejected.stderr, "ReadFailed") != null);
    try std.testing.expect(rejected.report == .null);
}
