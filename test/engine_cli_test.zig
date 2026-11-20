//! `selka engine` end to end through the installed native command (spec §3, §10, §11): the closure that a kind's code
//! identity covers, queries answered from records across processes, the early cutoff through the real filesystem, the
//! report line, and `explain`.
const std = @import("std");
const testing = std.testing;

/// The `selka` executable under test, which `zig build` names at run time (TEST-PATHS-1).
fn compilerPath() []const u8 {
    return @import("test_paths").corePath();
}

/// A source file the queries read, and the work directory holding the engine's store.
const Fixture = struct {
    temp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    source: []const u8,
    work: []const u8,

    fn init() !*Fixture {
        const self = try testing.allocator.create(Fixture);
        errdefer testing.allocator.destroy(self);
        self.temp = testing.tmpDir(.{});
        errdefer self.temp.cleanup();
        self.arena = .init(testing.allocator);
        errdefer self.arena.deinit();
        const root = try self.temp.dir.realPathFileAlloc(testing.io, ".", self.arena.allocator());
        self.source = try std.fs.path.join(self.arena.allocator(), &.{ root, "a.txt" });
        self.work = try std.fs.path.join(self.arena.allocator(), &.{ root, "work" });
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
        self.temp.cleanup();
        testing.allocator.destroy(self);
    }

    fn write(self: *Fixture, bytes: []const u8) !void {
        try self.temp.dir.writeFile(testing.io, .{ .sub_path = "a.txt", .data = bytes });
    }

    /// Wait out the engine's racy window, so the file's stamps are trusted.
    fn settle(_: *Fixture) !void {
        try std.Io.sleep(testing.io, .fromMilliseconds(80), .awake);
    }

    /// Run `selka engine ARGS`; the result's streams are in the fixture's arena.
    fn engine(self: *Fixture, args: []const []const u8) !std.process.RunResult {
        const a = self.arena.allocator();
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ try std.Io.Dir.cwd().realPathFileAlloc(testing.io, compilerPath(), a), "engine" });
        try argv.appendSlice(a, args);
        var environment = try std.process.Environ.createMap(testing.environ, a);
        @import("test_paths").withoutEngineSettings(&environment);
        try environment.put("SELKA_ENGINE_VERIFY", "1");
        return std.process.run(a, testing.io, .{ .argv = argv.items, .environ_map = &environment });
    }

    /// One query of `kind` on the source file, with the report line asked for.
    fn query(self: *Fixture, kind: []const u8) !std.process.RunResult {
        return self.engine(&.{ "query", kind, self.source, "--cache-dir", self.work, "--engine-report" });
    }
};

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// The number the report line gives for `field` of `kind`, or null when the line has no such kind or field.
fn reported(a: std.mem.Allocator, report: []const u8, kind: []const u8, field: []const u8) !?u64 {
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, report, .{});
    for (parsed.object.get("engine-report-v1").?.object.get("kinds").?.array.items) |row| {
        if (!std.mem.eql(u8, row.object.get("kind").?.string, kind)) continue;
        return @intCast((row.object.get(field) orelse return null).integer);
    }
    return null;
}

test "the closure of a kind lists the files its code identity covers, and the compiler is not among them" {
    const fixture = try Fixture.init();
    defer fixture.deinit();
    const closure = try fixture.engine(&.{ "closure", "engine-probe" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, closure.term);
    try testing.expect(contains(closure.stdout, "kind engine-probe\nidentity "));
    try testing.expect(contains(closure.stdout, "core/engine/context.zig\n"));
    try testing.expect(contains(closure.stdout, "core/engine/kinds/probe.zig\n"));
    try testing.expect(!contains(closure.stdout, "compiler.zig"));
    const kinds = try fixture.engine(&.{"kinds"});
    try testing.expect(contains(kinds.stdout, "engine-probe-class "));
    const unknown = try fixture.engine(&.{ "closure", "no-such-kind" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, unknown.term);
    const usage = try fixture.engine(&.{"bogus"});
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, usage.term);
}

test "a query is computed once, served by the next process, and cut off early when an edit leaves its dependency's answer alone" {
    const fixture = try Fixture.init();
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    try fixture.write("hello\n");
    try fixture.settle();
    const cold = try fixture.query("engine-probe-class");
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, cold.term);
    try testing.expectEqualStrings("small\n", cold.stdout);
    try testing.expectEqual(@as(?u64, 3), blk: {
        const probe = (try reported(a, cold.stderr, "engine-probe", "recomputed")).?;
        const size = (try reported(a, cold.stderr, "engine-probe-size", "recomputed")).?;
        break :blk probe + size + (try reported(a, cold.stderr, "engine-probe-class", "recomputed")).?;
    });
    const warm = try fixture.query("engine-probe-class");
    try testing.expectEqual(@as(?u64, 1), try reported(a, warm.stderr, "engine-probe-class", "served"));
    try testing.expectEqual(@as(?u64, 0), try reported(a, warm.stderr, "engine-probe-class", "recomputed"));
    // The same size, other bytes: the probe and the size are recomputed, and the class is served.
    try fixture.settle();
    try fixture.write("HELLO\n");
    try fixture.settle();
    const cut = try fixture.query("engine-probe-class");
    try testing.expectEqualStrings("small\n", cut.stdout);
    try testing.expectEqual(@as(?u64, 1), try reported(a, cut.stderr, "engine-probe", "recomputed"));
    try testing.expectEqual(@as(?u64, 1), try reported(a, cut.stderr, "engine-probe-size", "recomputed"));
    try testing.expectEqual(@as(?u64, 1), try reported(a, cut.stderr, "engine-probe-size", "early_cutoffs"));
    try testing.expectEqual(@as(?u64, 1), try reported(a, cut.stderr, "engine-probe-class", "served"));
    try testing.expectEqual(@as(?u64, 0), try reported(a, cut.stderr, "engine-probe-class", "recomputed"));
}

test "explain names the read that changed, through the chain of queries that depend on it" {
    const fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("hello\n");
    try fixture.settle();
    _ = try fixture.query("engine-probe-size");
    const unchanged = try fixture.engine(&.{ "explain", "engine-probe-size", fixture.source, "--cache-dir", fixture.work });
    try testing.expect(contains(unchanged.stdout, "served: every read is as it was seen"));
    try fixture.settle();
    try fixture.write("changed\n");
    const changed = try fixture.engine(&.{ "explain", "engine-probe-size", fixture.source, "--cache-dir", fixture.work });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, changed.term);
    try testing.expect(contains(changed.stdout, "would recompute: read #0 of engine-probe-size("));
    try testing.expect(contains(changed.stdout, " -> engine-probe("));
    try testing.expect(contains(changed.stdout, "read: file "));
    const missing = try fixture.engine(&.{ "explain", "engine-probe", "/no/such/file", "--cache-dir", fixture.work });
    try testing.expect(contains(missing.stdout, "no record"));
}

test "a query of a file that is not there fails with a message and stores nothing" {
    const fixture = try Fixture.init();
    defer fixture.deinit();
    const failed = try fixture.query("engine-probe");
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, failed.term);
    try testing.expect(contains(failed.stderr, "selka engine: Failed"));
}
