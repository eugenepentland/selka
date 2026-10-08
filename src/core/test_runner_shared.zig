//! What a directory run hands one of its roots when the root runs in the directory
//! run's own process instead of a child (NEW-CORE-TEST-UNION-1). `test_runner.zig`
//! runs the root; `test_runner_directory.zig` schedules it and merges its report.
const std = @import("std");
const language = @import("mylang");
const frontend = @import("frontend.zig");
const tool_identity = @import("tool_identity.zig");
const options = @import("test_runner_options.zig");
const Error = @import("test_runner_property.zig").Error;

/// A root's exit status and its JSON report, exactly as a child process gives them.
pub const Outcome = struct { code: u8 = 1, bytes: []const u8 = "" };

/// A module of a checked project graph.
pub const Module = frontend.Module;

/// One root's share of a check several roots share: the checked program of their
/// union, and the modules (standard ones included) the root's own import graph
/// reaches, which are the modules its own check would have loaded.
pub const View = struct { checked: frontend.Checked, modules: []const *const Module };

/// What a directory run hands a root it runs in process: the toolchain the run
/// identified, the shared check when the root took part in one, and the run's test
/// process permits. A `replay_only` run stops after setup and replay.
pub const Directed = struct { guest: tool_identity.Identity, view: ?View = null, permits: ?*Permits = null, replay_only: bool = false };

/// A directory run's budget of concurrent test processes, shared by every root
/// (NEW-CORE-TEST-UNION-1): an in-process root holds one permit per test process it
/// runs, so the root that is still working can use what the finished ones freed,
/// and a child root holds its whole share for as long as it runs.
pub const Permits = struct {
    semaphore: std.Io.Semaphore,
    /// Taken while one holder gathers several permits, so two such holders never
    /// wait on each other with a part each.
    gate: std.Io.Mutex = .init,

    /// A budget of `count` permits.
    pub fn init(count: usize) Permits {
        return .{ .semaphore = .{ .permits = count } };
    }

    /// Wait until `count` permits are free and take them.
    pub fn acquire(self: *Permits, io: std.Io, count: usize) void {
        self.gate.lockUncancelable(io);
        defer self.gate.unlock(io);
        for (0..count) |_| self.semaphore.waitUncancelable(io);
    }

    /// Return `count` permits.
    pub fn release(self: *Permits, io: std.Io, count: usize) void {
        for (0..count) |_| self.semaphore.post(io);
    }
};

/// Run one root in this process, as a child `mylang test ROOT --json` would; null
/// when a `replay_only` run found no recorded report to replay.
pub const RunRoot = *const fn (init: std.process.Init, opts: options.Options, directed: Directed) Error!?Outcome;

/// The modules `root` reaches through imports in `modules`, itself first, each once.
/// A module of `modules` named by no reached import is left out.
pub fn closure(a: std.mem.Allocator, modules: []const Module, root: []const u8) error{OutOfMemory}![]const *const Module {
    var reached: std.ArrayList(*const Module) = .empty;
    var seen = try a.alloc(bool, modules.len);
    @memset(seen, false);
    const first = indexOf(modules, root) orelse return reached.items;
    seen[first] = true;
    try reached.append(a, &modules[first]);
    var next: usize = 0;
    while (next < reached.items.len) : (next += 1) {
        for (reached.items[next].imports) |import| {
            const target = indexOf(modules, import.name) orelse continue;
            if (seen[target]) continue;
            seen[target] = true;
            try reached.append(a, &modules[target]);
        }
    }
    return reached.items;
}

fn indexOf(modules: []const Module, name: []const u8) ?usize {
    for (modules, 0..) |module, index| if (std.mem.eql(u8, module.name, name)) return index;
    return null;
}

// spec-case: NEW-CORE-TEST-UNION-1
test "closure follows imports from its root once each and leaves out what the root does not reach" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var a_imports = [_]language.project.Import{ .{ .name = "b", .alias = "b", .span = .{ .start = 0, .end = 0 } }, .{ .name = "c", .alias = "c", .span = .{ .start = 0, .end = 0 } } };
    var b_imports = [_]language.project.Import{.{ .name = "c", .alias = "c", .span = .{ .start = 0, .end = 0 } }};
    const source: language.source.Source = .{ .path = "", .bytes = "", .line_starts = &.{} };
    const modules = [_]Module{
        .{ .name = "other", .src = source },
        .{ .name = "a", .src = source, .imports = &a_imports },
        .{ .name = "b", .src = source, .imports = &b_imports },
        .{ .name = "c", .src = source },
    };
    const reached = try closure(a, &modules, "a");
    try std.testing.expectEqual(@as(usize, 3), reached.len);
    try std.testing.expectEqualStrings("a", reached[0].name);
    try std.testing.expectEqualStrings("b", reached[1].name);
    try std.testing.expectEqualStrings("c", reached[2].name);
    try std.testing.expectEqual(@as(usize, 0), (try closure(a, &modules, "missing")).len);
}

/// Take `count` permits from `permits` and give them straight back.
fn takeAndReturn(permits: *Permits, count: usize) void {
    permits.acquire(std.testing.io, count);
    permits.release(std.testing.io, count);
}

// spec-case: NEW-CORE-TEST-UNION-1
test "Permits.acquire takes several permits at once and a second taker waits until release returns them" {
    var permits: Permits = .init(3);
    permits.acquire(std.testing.io, 2);
    try std.testing.expectEqual(@as(usize, 1), permits.semaphore.permits);
    // Needs two while one is free: it waits for the release below.
    const waiter = try std.Thread.spawn(.{}, takeAndReturn, .{ &permits, 2 });
    permits.release(std.testing.io, 2);
    waiter.join();
    try std.testing.expectEqual(@as(usize, 3), permits.semaphore.permits);
}
