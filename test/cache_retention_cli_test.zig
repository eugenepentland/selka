//! Retention runs through the installed native command, including an empty PATH.
const std = @import("std");
const testing = std.testing;
const compiler_path = @import("test_options").compiler_path;
const key = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

const Fixture = struct {
    temp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,

    fn init() !Fixture {
        var temp = testing.tmpDir(.{});
        errdefer temp.cleanup();
        try temp.dir.createDirPath(testing.io, "shared/compiler-artifacts-v2/syntax");
        try temp.dir.createDirPath(testing.io, "shared/native-tests-v2/receipts");
        try temp.dir.writeFile(testing.io, .{ .sub_path = "shared/compiler-artifacts-v2/.retention.lock", .data = "" });
        try temp.dir.writeFile(testing.io, .{ .sub_path = "shared/native-tests-v2/.retention.lock", .data = "" });
        try temp.dir.writeFile(testing.io, .{ .sub_path = "shared/compiler-artifacts-v2/format", .data = "selka-compiler-artifact-store-v2\n" });
        try temp.dir.writeFile(testing.io, .{ .sub_path = "shared/native-tests-v2/format", .data = "selka-native-test-store-v2\n" });
        try temp.dir.writeFile(testing.io, .{ .sub_path = "shared/compiler-artifacts-v2/syntax/" ++ key ++ ".blob", .data = "disposable artifact" });
        return .{ .temp = temp, .arena = std.heap.ArenaAllocator.init(testing.allocator) };
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
        self.temp.cleanup();
    }

    fn run(self: *Fixture, command: []const u8, kind: []const u8, flags: []const []const u8) !std.process.RunResult {
        const a = self.arena.allocator();
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, a);
        const root = try self.temp.dir.realPathFileAlloc(testing.io, "shared", a);
        var environment = try std.process.Environ.createMap(testing.environ, a);
        try environment.put("PATH", "");
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ compiler, "cache", command, "--shared-cache-dir", root, "--kind", kind });
        try argv.appendSlice(a, flags);
        return std.process.run(a, testing.io, .{ .argv = argv.items, .environ_map = &environment });
    }

    fn exists(self: *Fixture, path: []const u8) bool {
        self.temp.dir.access(testing.io, path, .{}) catch return false;
        return true;
    }
};

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention CLI preview is immutable and zero budgets collect with empty PATH" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const preview = try fixture.run("gc", "compiler", &.{ "--max-bytes", "0", "--max-entries", "0" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, preview.term);
    try testing.expect(contains(preview.stdout, "\"dry_run\":true"));
    try testing.expect(contains(preview.stdout, "\"scanned\":{\"entries\":1"));
    try testing.expect(fixture.exists("shared/compiler-artifacts-v2/syntax/" ++ key ++ ".blob"));
    const lock_bytes = try fixture.temp.dir.readFileAlloc(testing.io, "shared/compiler-artifacts-v2/.retention.lock", fixture.arena.allocator(), .limited(16));
    try testing.expectEqualStrings("", lock_bytes);
    const applied = try fixture.run("gc", "compiler", &.{ "--max-bytes", "0", "--max-entries", "0", "--apply" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, applied.term);
    try testing.expect(contains(applied.stdout, "\"removed\":{\"entries\":1"));
    try testing.expect(!fixture.exists("shared/compiler-artifacts-v2/syntax/" ++ key ++ ".blob"));
    try testing.expect(fixture.exists("shared/compiler-artifacts-v2/format"));
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention CLI config persists and legacy namespace refuses without mutation" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const configured = try fixture.run("configure", "tests", &.{ "--max-bytes", "7", "--max-entries", "2", "--interval-seconds", "0" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, configured.term);
    try testing.expect(contains(configured.stdout, "\"configured\":true"));
    const observed = try fixture.run("configure", "tests", &.{});
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, observed.term);
    try testing.expect(contains(observed.stdout, "\"max_bytes\":7"));
    try testing.expect(contains(observed.stdout, "\"max_entries\":2"));
    try fixture.temp.dir.writeFile(testing.io, .{ .sub_path = "shared/compiler-artifacts-v2/format", .data = "selka-compiler-artifact-store-v1\n" });
    const refused = try fixture.run("gc", "compiler", &.{});
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, refused.term);
    try testing.expect(contains(refused.stderr, "initialized, valid v2"));
    try testing.expect(fixture.exists("shared/compiler-artifacts-v2/syntax/" ++ key ++ ".blob"));
    try testing.expect(fixture.exists("shared/compiler-artifacts-v2/.retention.lock"));
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention CLI invalid limits and missing namespaces are explicit refusals" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const invalid = try fixture.run("gc", "compiler", &.{ "--max-bytes", "-1" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, invalid.term);
    try testing.expect(contains(invalid.stderr, "usage: mylang cache"));
    try fixture.temp.dir.deleteTree(testing.io, "shared/native-tests-v2");
    const missing = try fixture.run("gc", "tests", &.{});
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, missing.term);
    try testing.expect(!fixture.exists("shared/native-tests-v2"));
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention CLI skips an active lease without removing artifacts or changing policy" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const lease = try fixture.temp.dir.createFile(testing.io, "shared/compiler-artifacts-v2/.retention.lock", .{ .truncate = false });
    defer lease.close(testing.io);
    try lease.lock(testing.io, .shared);
    const busy = try fixture.run("gc", "compiler", &.{ "--max-bytes", "0", "--apply" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, busy.term);
    try testing.expect(contains(busy.stdout, "\"skipped_active\":true"));
    try testing.expect(fixture.exists("shared/compiler-artifacts-v2/syntax/" ++ key ++ ".blob"));
    const configure = try fixture.run("configure", "compiler", &.{ "--max-bytes", "0" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, configure.term);
    try testing.expect(contains(configure.stdout, "\"configured\":false"));
    try testing.expect(contains(configure.stdout, "\"skipped_active\":true"));
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention CLI observes terminated process lease release without a delay" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    const lock = try fixture.temp.dir.realPathFileAlloc(testing.io, "shared/compiler-artifacts-v2/.retention.lock", a);
    var child = try std.process.spawn(testing.io, .{
        .argv = &.{ "flock", "--no-fork", "--shared", lock, "sh", "-c", "printf R; read token" },
        .expand_arg0 = .expand,
        .stdin = .pipe,
        .stdout = .pipe,
    });
    defer child.kill(testing.io);
    var ready: [1]u8 = undefined;
    try testing.expectEqual(@as(usize, 1), try child.stdout.?.readStreaming(testing.io, &.{&ready}));
    try testing.expectEqual(@as(u8, 'R'), ready[0]);
    const busy = try fixture.run("gc", "compiler", &.{ "--max-bytes", "0", "--apply" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, busy.term);
    try testing.expect(contains(busy.stdout, "\"skipped_active\":true"));
    child.kill(testing.io);
    const released = try fixture.run("gc", "compiler", &.{ "--max-bytes", "0", "--apply" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, released.term);
    try testing.expect(contains(released.stdout, "\"skipped_active\":false"));
    try testing.expect(contains(released.stdout, "\"removed\":{\"entries\":1"));
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention CLI refuses preview without a lock without creating one" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.temp.dir.deleteFile(testing.io, "shared/compiler-artifacts-v2/.retention.lock");
    const preview = try fixture.run("gc", "compiler", &.{});
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, preview.term);
    try testing.expect(!fixture.exists("shared/compiler-artifacts-v2/.retention.lock"));
    try testing.expect(fixture.exists("shared/compiler-artifacts-v2/syntax/" ++ key ++ ".blob"));
}

fn checkFresh(fixture: *Fixture) !std.process.RunResult {
    const a = fixture.arena.allocator();
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compiler_path, a);
    const root = try fixture.temp.dir.realPathFileAlloc(testing.io, ".", a);
    const source = try std.fs.path.join(a, &.{ root, "program.my" });
    const cache = try std.fs.path.join(a, &.{ root, "private" });
    const shared = try std.fs.path.join(a, &.{ root, "shared" });
    var environment = try std.process.Environ.createMap(testing.environ, a);
    try environment.put("MYLANG_COMPILER_SHARED_CACHE", shared);
    try environment.put("PATH", "");
    return std.process.run(a, testing.io, .{ .argv = &.{ compiler, "check", source, try std.fmt.allocPrint(a, "--cache-dir={s}", .{cache}) }, .environ_map = &environment });
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention CLI compiler eviction safely refills artifacts from source" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.temp.dir.writeFile(testing.io, .{ .sub_path = "program.my", .data = "func main() -> int:\n    return 42\n" });
    const first = try checkFresh(&fixture);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    const collected = try fixture.run("gc", "compiler", &.{ "--max-bytes", "0", "--apply" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, collected.term);
    try testing.expect(contains(collected.stdout, "\"retained\":{\"entries\":0"));
    try fixture.temp.dir.deleteTree(testing.io, "private");
    const refilled = try checkFresh(&fixture);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, refilled.term);
    try testing.expectEqualStrings(first.stdout, refilled.stdout);
    const inventory = try fixture.run("gc", "compiler", &.{});
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, inventory.term);
    try testing.expect(!contains(inventory.stdout, "\"scanned\":{\"entries\":0"));
}

// spec-case: NATIVE-CACHE-RETENTION-1
test "native retention CLI policy interval controls collection on real compiler store open" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.temp.dir.writeFile(testing.io, .{ .sub_path = "program.my", .data = "func main() -> int:\n    return 42\n" });
    const warm = try checkFresh(&fixture);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, warm.term);
    try testing.expect(fixture.exists("shared/compiler-artifacts-v2/retention-last"));
    const throttled = try fixture.run("configure", "compiler", &.{ "--max-bytes", "0", "--interval-seconds", "9223372036854775807" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, throttled.term);
    try fixture.temp.dir.deleteTree(testing.io, "private");
    const no_sweep = try checkFresh(&fixture);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, no_sweep.term);
    try testing.expect(fixture.exists("shared/compiler-artifacts-v2/syntax/" ++ key ++ ".blob"));
    const every_open = try fixture.run("configure", "compiler", &.{ "--interval-seconds", "0" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, every_open.term);
    try fixture.temp.dir.deleteTree(testing.io, "private");
    const swept = try checkFresh(&fixture);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, swept.term);
    try testing.expect(!fixture.exists("shared/compiler-artifacts-v2/syntax/" ++ key ++ ".blob"));
}
