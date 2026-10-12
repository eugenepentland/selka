//! End-to-end indexed property campaigns, checked against forced native execution.
const std = @import("std");
const options = @import("core_test_options");
const Value = std.json.Value;
const campaign_receipt = @import("property_campaign_receipt.zig");

const passing =
    \\public func test_generated(n: int) -> bool:
    \\    return n == n
    \\
;
const discarding =
    \\@requires(n >= 0, "nonnegative input")
    \\public func test_generated(n: int) -> bool:
    \\    return n >= 0
    \\
;
const failing =
    \\public func test_generated(n: int) -> bool:
    \\    return n == 0
    \\
;

const Project = struct {
    arena: std.mem.Allocator,
    root: []const u8,
    environment: std.process.Environ.Map,

    fn init(a: std.mem.Allocator, root: []const u8, source: []const u8) !Project {
        var environment = try std.testing.environ.createMap(a);
        errdefer environment.deinit();
        try environment.put("MYL_CORE_LEAKCHECK", "0");
        try environment.put("MYLANG_CACHE_PLAN_MODE", "shadow");
        var project: Project = .{ .arena = a, .root = root, .environment = environment };
        try project.write("app.my", source);
        return project;
    }

    fn path(self: Project, relative: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ self.root, relative });
    }

    fn write(self: Project, relative: []const u8, source: []const u8) !void {
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try self.path(relative), .data = source });
    }

    fn run(self: *Project, budget: u32, extra: []const []const u8) !Value {
        return self.runPath("app.my", budget, extra);
    }

    fn runPath(self: *Project, relative: []const u8, budget: u32, extra: []const []const u8) !Value {
        var args: std.ArrayList([]const u8) = .empty;
        try args.appendSlice(self.arena, &.{ options.corePath(), "test", try self.path(relative), "--json", "--seed", "42" });
        try args.appendSlice(self.arena, &.{ "--property-policy", "indexed-v1", "--property-runs", try std.fmt.allocPrint(self.arena, "{d}", .{budget}) });
        try args.appendSlice(self.arena, &.{ "--cache-dir", try self.path("cache") });
        try args.appendSlice(self.arena, extra);
        const result = try std.process.run(self.arena, std.testing.io, .{ .argv = args.items, .environ_map = &self.environment });
        try std.testing.expectEqualStrings("", result.stderr);
        const parsed = try std.json.parseFromSliceLeaky(Value, self.arena, result.stdout, .{});
        const failed = parsed.object.get("failed").?.integer != 0;
        const expected: std.process.Child.Term = .{ .exited = if (failed) 1 else 0 };
        try std.testing.expectEqual(expected, result.term);
        return parsed;
    }

    fn campaignPath(self: Project, value: Value) ![]const u8 {
        var digest: campaign_receipt.Digest = undefined;
        _ = try std.fmt.hexToBytes(&digest, row(value).object.get("cache").?.object.get("key").?.string);
        const store: campaign_receipt.Store = .{ .arena = self.arena, .io = std.testing.io, .root = try self.path("cache") };
        return store.artifactPath(self.arena, digest);
    }

    fn removeCoarse(self: Project) !void {
        std.Io.Dir.cwd().deleteTree(std.testing.io, try self.path("cache/tests/receipts-v3")) catch |err| {
            if (err != error.FileNotFound) return err;
        };
        std.Io.Dir.cwd().deleteTree(std.testing.io, try self.path("cache/tests/manifests-v3")) catch |err| {
            if (err != error.FileNotFound) return err;
        };
    }
};

fn row(value: Value) Value {
    return value.object.get("tests").?.array.items[0];
}
fn evidence(value: Value) Value {
    return row(value).object.get("property").?;
}
fn count(value: Value, name: []const u8) i64 {
    return evidence(value).object.get("counts").?.object.get(name).?.integer;
}
fn campaign(value: Value, name: []const u8) i64 {
    return evidence(value).object.get("campaign").?.object.get(name).?.integer;
}
fn equalResult(a: std.mem.Allocator, actual: Value, oracle: Value) !void {
    try std.testing.expectEqualStrings(row(oracle).object.get("status").?.string, row(actual).object.get("status").?.string);
    try std.testing.expectEqualStrings(row(oracle).object.get("reason").?.string, row(actual).object.get("reason").?.string);
    try std.testing.expectEqual(count(oracle, "passed"), count(actual, "passed"));
    try std.testing.expectEqual(count(oracle, "discarded"), count(actual, "discarded"));
    const actual_failure = evidence(actual).object.get("failure").?;
    const oracle_failure = evidence(oracle).object.get("failure").?;
    try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, oracle_failure, .{}), try std.json.Stringify.valueAlloc(a, actual_failure, .{}));
}

// spec: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property campaign extends 32 to 64 after coarse receipts are deleted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), passing);
    defer project.environment.deinit();
    const cold = try project.run(32, &.{});
    try std.testing.expectEqual(@as(i64, 32), campaign(cold, "fresh_classified"));
    try std.testing.expectEqual(@as(i64, 0), campaign(cold, "reused"));
    try project.removeCoarse();
    const warm = try project.run(32, &.{});
    try std.testing.expectEqual(@as(i64, 0), campaign(warm, "fresh_classified"));
    try std.testing.expectEqual(@as(i64, 32), campaign(warm, "reused"));
    try std.testing.expectEqual(@as(i64, 0), count(warm, "processes"));
    const extended = try project.run(64, &.{});
    try std.testing.expectEqual(@as(i64, 32), campaign(extended, "fresh_classified"));
    try std.testing.expectEqual(@as(i64, 32), campaign(extended, "reused"));
    const forced = try project.run(64, &.{"--force"});
    try std.testing.expectEqual(@as(i64, 64), campaign(forced, "fresh_classified"));
    try std.testing.expectEqual(@as(i64, 0), campaign(forced, "reused"));
    try equalResult(a, extended, forced);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property campaign discard and refill matches the forced ordinal oracle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), discarding);
    defer project.environment.deinit();
    const cold = try project.run(32, &.{});
    try std.testing.expect(count(cold, "discarded") > 0);
    const extended = try project.run(64, &.{});
    try std.testing.expect(campaign(extended, "reused") > 0);
    const forced = try project.run(64, &.{"--force"});
    try equalResult(a, extended, forced);
    try std.testing.expectEqual(@as(i64, 64), count(extended, "passed"));
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property campaign failing shrink and reproduction never become cached success" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), failing);
    defer project.environment.deinit();
    const cold = try project.run(32, &.{});
    const repeated = try project.run(32, &.{});
    const forced = try project.run(32, &.{"--force"});
    try equalResult(a, cold, repeated);
    try equalResult(a, repeated, forced);
    try std.testing.expectEqualStrings("failed", row(repeated).object.get("status").?.string);
    try std.testing.expectEqual(@as(i64, 0), campaign(repeated, "reused"));
    try std.testing.expect(count(repeated, "attempts") > 0);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property campaign missing and corrupted prefix records fall back and repair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), passing);
    defer project.environment.deinit();
    const cold = try project.run(32, &.{});
    const path = try project.campaignPath(cold);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = "incomplete or corrupt campaign evidence" });
    const corrupt = try project.run(32, &.{});
    try std.testing.expectEqual(@as(i64, 32), campaign(corrupt, "fresh_classified"));
    try std.testing.expectEqual(@as(i64, 0), campaign(corrupt, "reused"));
    const repaired = try project.run(32, &.{});
    try std.testing.expectEqual(@as(i64, 32), campaign(repaired, "reused"));
    try std.Io.Dir.cwd().deleteFile(std.testing.io, path);
    const missing = try project.run(32, &.{});
    try std.testing.expectEqual(@as(i64, 32), campaign(missing, "fresh_classified"));
    try std.testing.expectEqual(@as(i64, 0), campaign(missing, "reused"));
    try equalResult(a, corrupt, missing);
}

const transitive =
    \\import helper
    \\
    \\public func test_generated(n: int) -> bool:
    \\    return helper.accept(n)
    \\
;

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property campaign transitive helper changes invalidate the complete closure key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), transitive);
    defer project.environment.deinit();
    try project.write("helper.my", "public func accept(n: int) -> bool:\n    return n <= n\n");
    const cold = try project.run(32, &.{});
    const warm = try project.run(32, &.{});
    try std.testing.expectEqual(@as(i64, 32), campaign(warm, "reused"));
    try project.write("helper.my", "public func accept(n: int) -> bool:\n    return n >= n\n");
    const changed = try project.run(32, &.{});
    try std.testing.expectEqual(@as(i64, 32), campaign(changed, "fresh_classified"));
    try std.testing.expectEqual(@as(i64, 0), campaign(changed, "reused"));
    try std.testing.expect(!std.mem.eql(u8, row(cold).object.get("cache").?.object.get("key").?.string, row(changed).object.get("cache").?.object.get("key").?.string));
    const forced = try project.run(32, &.{"--force"});
    try equalResult(a, changed, forced);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property campaign directory workers forward the stable generation policy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), passing);
    defer project.environment.deinit();
    const cold = try project.runPath(".", 32, &.{ "--jobs", "1" });
    const warm = try project.runPath(".", 32, &.{ "--jobs", "1" });
    const extended = try project.runPath(".", 64, &.{ "--jobs", "1" });
    try std.testing.expectEqual(@as(i64, 32), campaign(cold, "fresh_classified"));
    try std.testing.expectEqual(@as(i64, 32), campaign(warm, "reused"));
    try std.testing.expectEqual(@as(i64, 0), count(warm, "processes"));
    try std.testing.expectEqual(@as(i64, 32), campaign(extended, "fresh_classified"));
    try std.testing.expectEqual(@as(i64, 32), campaign(extended, "reused"));
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property campaign force and verify facts preserve live execution restrictions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), passing);
    defer project.environment.deinit();
    const cold = try project.run(32, &.{});
    const forced = try project.run(32, &.{"--force"});
    const verified = try project.run(32, &.{"--verify-facts"});
    const warm = try project.run(32, &.{});
    try project.environment.put("MYL_CORE_LEAKCHECK", "1");
    const leak = try project.run(32, &.{});
    try std.testing.expectEqual(@as(i64, 0), campaign(leak, "reused"));
    try std.testing.expectEqual(@as(i64, 32), campaign(leak, "fresh_classified"));
    try std.testing.expectEqual(@as(i64, 0), campaign(forced, "reused"));
    try std.testing.expectEqual(@as(i64, 32), campaign(forced, "fresh_classified"));
    try std.testing.expectEqual(@as(i64, 0), campaign(verified, "reused"));
    try std.testing.expectEqual(@as(i64, 32), campaign(verified, "fresh_classified"));
    try std.testing.expectEqual(@as(i64, 32), campaign(warm, "reused"));
    try equalResult(a, cold, forced);
    try equalResult(a, cold, verified);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property campaign native links cannot reuse or publish completed ranges" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), passing);
    defer project.environment.deinit();
    try project.write("support.c", "int support(void) { return 0; }\n");
    const link = try project.path("support.c");
    const cold = try project.run(32, &.{ "--link", link });
    const repeated = try project.run(32, &.{ "--link", link });
    try std.testing.expectEqual(@as(i64, 32), campaign(cold, "fresh_classified"));
    try std.testing.expectEqual(@as(i64, 32), campaign(repeated, "fresh_classified"));
    try std.testing.expectEqual(@as(i64, 0), campaign(repeated, "reused"));
    try std.testing.expectEqualStrings("native-links", row(repeated).object.get("cache").?.object.get("reason").?.string);
    try equalResult(a, cold, repeated);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property campaign leaves fixed cases as one plain native trial" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var project = try Project.init(a, try temporary.dir.realPathFileAlloc(std.testing.io, ".", a), passing);
    defer project.environment.deinit();
    try project.write("cases.json", "{\"app::test_generated\":{\"arguments\":{\"n\":\"7\"}}}");
    const cases = try project.path("cases.json");
    const fixed = try project.run(32, &.{ "--cases", cases });
    const repeated = try project.run(64, &.{ "--cases", cases });
    try std.testing.expectEqualStrings("", row(fixed).object.get("reason").?.string);
    try std.testing.expectEqualStrings("passed", row(fixed).object.get("status").?.string);
    try std.testing.expectEqualStrings("passed", row(repeated).object.get("status").?.string);
    try std.testing.expect(!row(fixed).object.contains("property"));
    try std.testing.expect(!row(repeated).object.contains("property"));
}
