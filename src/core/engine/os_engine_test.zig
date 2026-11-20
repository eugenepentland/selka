//! The engine over the machine's filesystem: real stat tuples, real timestamps, real files and many threads asking at
//! once. The in-memory world tests the rules exactly; these tests show the same rules hold where the clock and the
//! kernel are not ours.
const std = @import("std");
const engine_rules = @import("engine.zig");
const os_world = @import("os_world.zig");
const script = @import("kinds/script.zig");
const model_rules = @import("model_test.zig");
const fixture_rules = @import("fixture_test.zig");

/// Longer than the racy window, so a file written before it is trusted by its tuple.
const settle_ms = 80;

/// A temporary directory holding source files and a work directory, and the engine's inputs over them.
const Site = struct {
    temporary: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    root: []const u8,
    environment: std.process.Environ.Map,

    fn create(gpa: std.mem.Allocator) !*Site {
        const self = try gpa.create(Site);
        errdefer gpa.destroy(self);
        self.temporary = std.testing.tmpDir(.{});
        errdefer self.temporary.cleanup();
        self.arena = .init(gpa);
        errdefer self.arena.deinit();
        self.root = try self.temporary.dir.realPathFileAlloc(std.testing.io, ".", self.arena.allocator());
        self.environment = .init(self.arena.allocator());
        return self;
    }

    fn destroy(self: *Site, gpa: std.mem.Allocator) void {
        self.arena.deinit();
        self.temporary.cleanup();
        gpa.destroy(self);
    }

    fn path(self: *Site, name: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena.allocator(), &.{ self.root, name });
    }

    fn write(self: *Site, name: []const u8, bytes: []const u8) !void {
        if (std.fs.path.dirname(name)) |parent| try self.temporary.dir.createDirPath(std.testing.io, parent);
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = bytes });
    }

    fn settle(self: *Site) !void {
        _ = self;
        try std.Io.sleep(std.testing.io, .fromMilliseconds(settle_ms), .awake);
    }
};

/// A new process: an engine over the machine's world, with the script kind of `graph` registered.
const Process = struct {
    machine: os_world.OsWorld,
    kind: @import("context.zig").Kind,
    runner: engine_rules.Engine,

    fn start(self: *Process, gpa: std.mem.Allocator, site: *Site, graph: *const script.Graph) !void {
        self.machine = .{ .io = std.testing.io, .environment = &site.environment, .work = try site.path("work") };
        self.kind = script.kindFor(graph, @splat(1));
        self.runner = try engine_rules.Engine.init(gpa, std.testing.io, self.machine.world(), .{ .work = self.machine.work });
        errdefer self.runner.deinit();
        try self.runner.register(&self.kind);
    }

    fn stop(self: *Process) void {
        self.runner.deinit();
    }

    fn ask(self: *Process, number: u32) ![]const u8 {
        var text: [16]u8 = undefined;
        const argument = try std.fmt.bufPrint(&text, "{d}", .{number});
        return (try self.runner.query(&self.kind, argument)).payload();
    }
};

test "real files: unchanged is served, touched is served after a hash, an edit of the same size is recomputed, a removal is seen" {
    const site = try Site.create(std.testing.allocator);
    defer site.destroy(std.testing.allocator);
    const a = site.arena.allocator();
    const source = try site.path("a.txt");
    const nodes = try a.dupe(script.Node, &.{.{ .ops = try a.dupe(script.Op, &.{.{ .file = source }}) }});
    const graph: script.Graph = .{ .nodes = nodes };
    try site.write("a.txt", "alpha");
    try site.settle();
    var first: Process = undefined;
    try first.start(std.testing.allocator, site, &graph);
    defer first.stop();
    try std.testing.expectEqualStrings("alpha", try first.ask(0));
    var second: Process = undefined;
    try second.start(std.testing.allocator, site, &graph);
    defer second.stop();
    try std.testing.expectEqualStrings("alpha", try second.ask(0));
    try std.testing.expectEqual(@as(u64, 1), second.runner.snapshot(&second.kind).?.count(.served));
    // Touched: same bytes, new timestamps.
    try site.settle();
    try site.temporary.dir.setTimestampsNow(std.testing.io, "a.txt", .{});
    var third: Process = undefined;
    try third.start(std.testing.allocator, site, &graph);
    defer third.stop();
    try std.testing.expectEqualStrings("alpha", try third.ask(0));
    try std.testing.expectEqual(@as(u64, 1), third.runner.snapshot(&third.kind).?.count(.served));
    // Edited in place to other bytes of the same size, at once: the kernel's tick may leave the size and a stamp alone.
    try site.write("a.txt", "omega");
    var fourth: Process = undefined;
    try fourth.start(std.testing.allocator, site, &graph);
    defer fourth.stop();
    try std.testing.expectEqualStrings("omega", try fourth.ask(0));
    try std.testing.expectEqual(@as(u64, 1), fourth.runner.snapshot(&fourth.kind).?.count(.recomputed));
    try site.settle();
    try site.temporary.dir.deleteFile(std.testing.io, "a.txt");
    var fifth: Process = undefined;
    try fifth.start(std.testing.allocator, site, &graph);
    defer fifth.stop();
    try std.testing.expectEqualStrings("~", try fifth.ask(0));
}

/// A layered graph over files `f0` to `f5`: node `n` of layer `l` reads one file and two nodes of the layer below.
fn layered(a: std.mem.Allocator, site: *Site) !script.Graph {
    const width = 6;
    const layers = 4;
    const nodes = try a.alloc(script.Node, width * layers);
    for (nodes, 0..) |*node, at| {
        const layer = at / width;
        const ops = try a.alloc(script.Op, if (layer == 0) 1 else 3);
        const name = try std.fmt.allocPrint(a, "f{d}", .{at % width});
        ops[0] = .{ .file = try site.path(name) };
        if (layer != 0) {
            ops[1] = .{ .node = @intCast((layer - 1) * width + at % width) };
            ops[2] = .{ .node = @intCast((layer - 1) * width + (at + 1) % width) };
        }
        node.* = .{ .ops = ops, .fold = if (layer % 2 == 0) .concat else .length };
    }
    return .{ .nodes = nodes };
}

/// Write the six source files, two lengths of content when `mixed`.
fn writeSources(site: *Site, a: std.mem.Allocator, mixed: bool) !void {
    for (0..6) |at| try site.write(try std.fmt.allocPrint(a, "f{d}", .{at}), if (mixed and at % 2 == 1) "abc" else "ab");
}

/// Ask every node from `threads` threads at once, each in its own order; the first wrong answer, or null.
fn askAll(process: *Process, graph: script.Graph, threads: usize, gpa: std.mem.Allocator, wrong: *std.atomic.Value(u32)) !void {
    const handles = try gpa.alloc(std.Thread, threads);
    defer gpa.free(handles);
    for (handles, 0..) |*handle, at| handle.* = try std.Thread.spawn(.{}, askOrdered, .{ process, graph, at, wrong });
    for (handles) |handle| handle.join();
}

fn askOrdered(process: *Process, graph: script.Graph, start: usize, wrong: *std.atomic.Value(u32)) void {
    var scratch: std.heap.ArenaAllocator = .init(process.runner.setup.gpa);
    defer scratch.deinit();
    const count = graph.nodes.len;
    for (0..count) |step| {
        const node: u32 = @intCast((start * 7 + step) % count);
        const got = process.ask(node) catch {
            _ = wrong.fetchAdd(1, .monotonic);
            return;
        };
        const want = model_rules.truth(scratch.allocator(), graph, process.machine.world(), node) catch {
            _ = wrong.fetchAdd(1, .monotonic);
            return;
        };
        if (!std.mem.eql(u8, got, want)) _ = wrong.fetchAdd(1, .monotonic);
    }
}

test "eight threads asking a layered graph at once all get the from-scratch answers, and the next process is served" {
    const site = try Site.create(std.testing.allocator);
    defer site.destroy(std.testing.allocator);
    const a = site.arena.allocator();
    const graph = try layered(a, site);
    try writeSources(site, a, true);
    try site.settle();
    var wrong: std.atomic.Value(u32) = .init(0);
    var first: Process = undefined;
    try first.start(std.testing.allocator, site, &graph);
    defer first.stop();
    try askAll(&first, graph, 8, std.testing.allocator, &wrong);
    try std.testing.expectEqual(@as(u32, 0), wrong.load(.monotonic));
    var second: Process = undefined;
    try second.start(std.testing.allocator, site, &graph);
    defer second.stop();
    try askAll(&second, graph, 8, std.testing.allocator, &wrong);
    try std.testing.expectEqual(@as(u32, 0), wrong.load(.monotonic));
    const numbers = second.runner.snapshot(&second.kind).?;
    try std.testing.expectEqual(@as(u64, 0), numbers.count(.recomputed));
    try std.testing.expect(numbers.count(.served) >= graph.nodes.len);
}

test "edits between threaded processes are seen by the next one" {
    const site = try Site.create(std.testing.allocator);
    defer site.destroy(std.testing.allocator);
    const a = site.arena.allocator();
    const graph = try layered(a, site);
    try writeSources(site, a, false);
    try site.settle();
    var wrong: std.atomic.Value(u32) = .init(0);
    var first: Process = undefined;
    try first.start(std.testing.allocator, site, &graph);
    defer first.stop();
    try askAll(&first, graph, 4, std.testing.allocator, &wrong);
    try site.write("f3", "different");
    var second: Process = undefined;
    try second.start(std.testing.allocator, site, &graph);
    defer second.stop();
    try askAll(&second, graph, 4, std.testing.allocator, &wrong);
    try std.testing.expectEqual(@as(u32, 0), wrong.load(.monotonic));
    try std.testing.expect(second.runner.snapshot(&second.kind).?.count(.recomputed) >= 1);
}
