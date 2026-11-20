//! What the engine's behaviour tests share: a script kind over an in-memory world, a store in a temporary directory,
//! and `restart`, which starts a new engine over the same store and the same world, as a new process would.
const std = @import("std");
const engine_rules = @import("engine.zig");
const memory_world = @import("memory_world.zig");
const script = @import("kinds/script.zig");
const context = @import("context.zig");
const digest_rules = @import("digest.zig");
const stats = @import("stats.zig");
const shared_tier = @import("shared_tier.zig");

/// The failures a fixture step can have: the engine's, the filesystem's and the allocator's.
pub const Failure = std.mem.Allocator.Error || engine_rules.Error || std.Io.Dir.RealPathFileAllocError || std.fmt.BufPrintError ||
    error{ DuplicateKind, InvalidKindName, TooManyKinds };

/// The knobs of a restarted engine.
pub const Settings = struct {
    verify_every: u32 = 0,
    depth_limit: u32 = 512,
    shared: ?shared_tier.Tier = null,
    filter: ?shared_tier.Filter = null,
    /// The fewest adopted records that make a pack (`engine.Policy`).
    pack_min_records: u32 = 16,
};

/// Where the fixture's store lives and what frees it.
const Site = struct {
    gpa: std.mem.Allocator,
    temporary: std.testing.TmpDir,
    /// The work directory, an absolute path in `gpa`.
    work: []const u8,
};

/// A script kind, a world and an engine; heap-allocated so the kind's pointer to the graph stays valid.
pub const Fixture = struct {
    site: Site,
    files: memory_world.MemoryWorld,
    graph: script.Graph,
    kind: context.Kind,
    runner: engine_rules.Engine,

    /// A fixture running `graph`, with an engine started and the script kind registered.
    pub fn create(gpa: std.mem.Allocator, graph: script.Graph) Failure!*Fixture {
        const self = try gpa.create(Fixture);
        errdefer gpa.destroy(self);
        self.site = .{ .gpa = gpa, .temporary = std.testing.tmpDir(.{}), .work = "" };
        errdefer self.site.temporary.cleanup();
        const real = try self.site.temporary.dir.realPathFileAlloc(std.testing.io, ".", gpa);
        defer gpa.free(real);
        self.site.work = try gpa.dupe(u8, real);
        errdefer gpa.free(self.site.work);
        self.files = .init(gpa);
        errdefer self.files.deinit();
        self.graph = graph;
        self.kind = script.kindFor(&self.graph, @splat(1));
        self.runner = try engine_rules.Engine.init(gpa, std.testing.io, self.files.world(), .{ .work = self.site.work });
        errdefer self.runner.deinit();
        try self.runner.register(&self.kind);
        return self;
    }

    /// Free the fixture.
    pub fn destroy(self: *Fixture) void {
        const gpa = self.site.gpa;
        self.runner.deinit();
        self.files.deinit();
        gpa.free(self.site.work);
        self.site.temporary.cleanup();
        gpa.destroy(self);
    }

    /// Start a new engine over the same store and world, as a new process does: nothing is remembered.
    pub fn restart(self: *Fixture, settings: Settings) Failure!void {
        return self.restartWith(settings, &.{});
    }

    /// `restart`, registering `extra` kinds beside the script kind.
    pub fn restartWith(self: *Fixture, settings: Settings, extra: []const *const context.Kind) Failure!void {
        self.runner.deinit();
        self.runner = try engine_rules.Engine.init(self.site.gpa, std.testing.io, self.files.world(), .{
            .work = self.site.work,
            .verify_every = settings.verify_every,
            .depth_limit = settings.depth_limit,
            .shared = settings.shared,
            .policy = .{ .pack_min_records = settings.pack_min_records },
        });
        try self.runner.register(&self.kind);
        for (extra) |kind| try self.runner.register(kind);
        if (settings.shared != null) self.runner.share(&self.kind, settings.filter);
    }

    /// The result of node `number` as text, valid until the next restart.
    pub fn run(self: *Fixture, number: u32) Failure![]const u8 {
        var text: [16]u8 = undefined;
        const argument = try std.fmt.bufPrint(&text, "{d}", .{number});
        const answered = try self.runner.query(&self.kind, argument);
        return answered.payload();
    }

    /// The script kind's numbers since the last restart.
    pub fn numbers(self: *Fixture) stats.Snapshot {
        return self.runner.snapshot(&self.kind).?;
    }

    /// The path of the record of node `number`.
    pub fn recordPath(self: *Fixture, a: std.mem.Allocator, number: u32) Failure![]const u8 {
        const argument = try script.argumentFor(a, number);
        defer a.free(argument);
        const key = digest_rules.key(self.kind.name, self.kind.identity, argument);
        return self.runner.store.recordPath(a, self.runner.registry.entries[0].directory, key);
    }
};

/// A node reading one file, folded by `fold`. The path is comptime so the node's reads are static data.
pub fn fileNode(comptime path: []const u8, fold: script.Fold) script.Node {
    return .{ .ops = &.{.{ .file = path }}, .fold = fold };
}
