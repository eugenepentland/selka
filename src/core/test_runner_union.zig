//! A directory run's roots in the run's own process, from one shared check
//! (NEW-CORE-TEST-UNION-1).
//!
//! Every root that misses its recorded report rechecks the modules it imports, and
//! a directory's roots import much the same graph: after one edit, a directory's
//! roots used to check that graph once each, in parallel processes, mostly to the
//! same result. Here the roots that can share a check are checked together, once
//! per project, as one synthetic entry that imports each of them, and each root
//! then selects, builds and runs its tests from its share of that program: the
//! modules its own import graph reaches, which are exactly the modules its own check
//! would have loaded. A root shares the check when it opens as a module, its
//! project's configuration names no import policy and no interface files, its
//! cases file names no providers and the run selects by no git revision. Any other
//! root, and every root of a project whose shared check fails, runs in a child
//! process as before, where its own check reports its own diagnostics.
//! `MYLANG_TEST_CHILDREN=1` runs every root in a child, the differential oracle.
const std = @import("std");
const lowering_cache = @import("lowering_cache.zig");
const language = @import("mylang");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const case_settings = @import("test_runner_cases.zig");
const options = @import("test_runner_options.zig");
const shared = @import("test_runner_shared.zig");
const tool_identity = @import("tool_identity.zig");
const Error = @import("test_runner_property.zig").Error;

/// How one root of a directory run runs: in a child process, from its recorded
/// report, or in this process from its share of a shared check.
pub const Plan = union(enum) { child, replayed, together: shared.View };

/// What planning needs: the run's options (its toolchain path resolved), the
/// toolchain identity, the in-process root runner and the worker count.
pub const Context = struct { init: std.process.Init, controls: options.Options, guest: tool_identity.Identity, cache_plan: ?@import("mylang").cache_plan_adapter.Bound = null, run_root: shared.RunRoot, workers: usize };

/// The shared checks of one directory run. Their sessions own the checked programs
/// the `together` plans read; release them after every root has run.
pub const Checks = struct {
    sessions: std.ArrayList(*frontend.Session) = .empty,

    /// Release every shared check's session.
    pub fn deinit(self: *Checks) void {
        for (self.sessions.items) |session| session.deinit();
    }
};

/// Whether `MYLANG_TEST_CHILDREN=1` asks for a child process per root.
pub fn childrenOnly(environment: *const std.process.Environ.Map) bool {
    return std.mem.eql(u8, environment.get("MYLANG_TEST_CHILDREN") orelse "", "1");
}

/// The module a directory run's shared load and check enter through.
pub const entry_name = "mylang_directory_run";

/// The synthetic path-named entry imports each module and declares a `main`.
pub fn entryText(a: std.mem.Allocator, modules: []const []const u8) error{OutOfMemory}![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    for (modules, 0..) |name, position| try text.print(a, "import {s} as root_{d}\n", .{ name, position });
    try text.appendSlice(a, "\nfunc main() -> int:\n    return 0\n");
    return text.items;
}

/// Whether `root` holds a project module of the synthetic entry's name, which
/// the entry would shadow; such a project loads root by root.
pub fn occupied(io: std.Io, a: std.mem.Allocator, root: []const u8) error{OutOfMemory}!bool {
    const path = try std.fs.path.join(a, &.{ root, entry_name ++ ".my" });
    std.Io.Dir.cwd().access(io, path, .{}) catch |err| return err != error.FileNotFound;
    return true;
}

/// Plan every root of `paths`: an eligible root whose report replays is done, the
/// eligible roots that miss are checked together per project, and the rest run in
/// children. Fills `outcomes` for the replayed roots.
pub fn plan(context: Context, paths: []const []const u8, outcomes: []shared.Outcome, plans: []Plan) Error!Checks {
    const init = context.init;
    const a = init.arena.allocator();
    @memset(plans, .child);
    var checks: Checks = .{};
    if (childrenOnly(init.environ_map) or context.controls.controls.against != null) return checks;
    const eligible = try a.alloc(?Root, paths.len);
    for (paths, eligible) |path, *root| root.* = try eligibility(init, context.controls, path);
    try replay(context, paths, eligible, outcomes, plans);
    // One shared check per project: roots with the same root directory and configuration.
    var done = try a.alloc(bool, paths.len);
    @memset(done, false);
    for (eligible, 0..) |candidate, first| {
        const root = candidate orelse continue;
        if (done[first] or plans[first] != .child) continue;
        var members: std.ArrayList(usize) = .empty;
        for (eligible[first..], first..) |other, index| {
            const peer = other orelse continue;
            if (done[index] or plans[index] != .child or !root.sameProject(peer)) continue;
            done[index] = true;
            try members.append(a, index);
        }
        try together(context, &checks, eligible, members.items, plans);
    }
    return checks;
}

/// An eligible root: its resolved entry and module name.
const Root = struct {
    located: project_entry.Entry,

    fn sameProject(self: Root, other: Root) bool {
        const mine = if (self.located.configuration) |file| file.path else "";
        const theirs = if (other.located.configuration) |file| file.path else "";
        return std.mem.eql(u8, self.located.root, other.located.root) and std.mem.eql(u8, mine, theirs);
    }
};

/// The root at `path` when it can share a check, else null (it runs in a child,
/// which reports any problem with it).
fn eligibility(init: std.process.Init, controls: options.Options, path: []const u8) Error!?Root {
    const a = init.arena.allocator();
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 << 20)) catch return null;
    // A root checked alone is the entry: its `main`, when it declares one, is checked
    // as the program's. In a shared check it is one import among many, so it stays alone.
    if (!headed(bytes)) return null;
    if (language.project_config.declaresMain(bytes)) return null;
    var problems: std.ArrayList(u8) = .empty;
    const located = project_entry.resolve(a, init.io, path, &problems) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    if (located.configuration) |configured| if (configured.policy != null or configured.document.interface_files) return null;
    const cases = case_settings.load(a, init.io, located.path, null) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    const sets = case_settings.providerSets(a, cases, controls.filter) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    if (sets.len != 0) return null;
    return .{ .located = located };
}

/// Whether a source has a non-comment opening suitable for project loading.
pub fn headed(bytes: []const u8) bool {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        return !std.mem.startsWith(u8, line, "module ");
    }
    return false;
}

/// Replay every eligible root's recorded report, on `context.workers` threads.
fn replay(context: Context, paths: []const []const u8, eligible: []const ?Root, outcomes: []shared.Outcome, plans: []Plan) Error!void {
    const a = context.init.arena.allocator();
    var queue: Replays = .{ .context = context, .paths = paths, .eligible = eligible, .outcomes = outcomes, .plans = plans };
    const threads = try a.alloc(std.Thread, @max(1, @min(context.workers, paths.len)) - 1);
    var started: usize = 0;
    for (threads) |*thread| {
        thread.* = std.Thread.spawn(.{}, Replays.drain, .{&queue}) catch break;
        started += 1;
    }
    queue.drain();
    for (threads[0..started]) |thread| thread.join();
    if (queue.failure) |err| return err;
}

/// The replay phase's shared state.
const Replays = struct {
    context: Context,
    paths: []const []const u8,
    eligible: []const ?Root,
    outcomes: []shared.Outcome,
    plans: []Plan,
    next: std.atomic.Value(usize) = .init(0),
    /// Set once, by the first thread that fails; that thread alone writes `failure`,
    /// which is read only after every thread has joined.
    stopped: std.atomic.Value(bool) = .init(false),
    failure: ?Error = null,

    fn drain(self: *Replays) void {
        while (!self.stopped.load(.acquire)) {
            const index = self.next.fetchAdd(1, .monotonic);
            if (index >= self.paths.len) return;
            if (self.eligible[index] == null) continue;
            self.one(index) catch |err| {
                if (self.stopped.cmpxchgStrong(false, true, .acq_rel, .acquire) == null) self.failure = err;
                return;
            };
        }
    }

    fn one(self: *Replays, index: usize) Error!void {
        const init = self.context.init;
        var arena = std.heap.ArenaAllocator.init(init.gpa);
        defer arena.deinit();
        var root_init = init;
        root_init.arena = &arena;
        var controls = self.context.controls;
        controls.path = self.paths[index];
        const replayed = try self.context.run_root(root_init, controls, .{ .guest = self.context.guest, .cache_plan = self.context.cache_plan, .replay_only = true }) orelse return;
        self.outcomes[index] = .{ .code = replayed.code, .bytes = try init.arena.allocator().dupe(u8, replayed.bytes) };
        self.plans[index] = .replayed;
    }
};

/// Check the roots `members` of one project together; on success each gets its share
/// of the check, on any failure they all stay with their children.
fn together(context: Context, checks: *Checks, eligible: []const ?Root, members: []const usize, plans: []Plan) Error!void {
    if (members.len == 0) return;
    const init = context.init;
    const a = init.arena.allocator();
    const first = eligible[members[0]].?.located;
    const relative = entry_name ++ ".my";
    if (try occupied(init.io, a, first.root)) return;
    const names = try a.alloc([]const u8, members.len);
    for (members, names) |index, *name| name.* = eligible[index].?.located.name;
    const text = try entryText(a, names);
    const session = try a.create(frontend.Session);
    session.* = frontend.Session.init(init.gpa, init.io, first.root);
    first.configure(session);
    session.configureProject(first.limits(), entry_name);
    session.setProviders(try a.dupe(frontend.Provider, &.{.{ .path = relative, .text = text }}));
    // No semantic cache: replaying stored bodies costs more than checking them at
    // this size (on EDA's 58 roots after an edit, 170-200 ms checked fresh against
    // 210-250 ms with the cache), and the shared check runs once per run anyway.
    var problems: std.ArrayList(u8) = .empty;
    const checked = session.check(a, entry_name, &problems) catch |err| {
        session.deinit();
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return;
    };
    std.Io.File.stderr().writeStreamingAll(init.io, problems.items) catch return error.WriteFailed;
    try checks.sessions.append(a, session);
    if (checked.src.origins.len == 0) return;
    const catalog = try sharedCatalog(context, checked.program);
    for (members) |index| {
        const modules = try shared.closure(a, session.project.modules.items, eligible[index].?.located.name);
        if (modules.len == 0) continue;
        plans[index] = .{ .together = .{ .checked = try rooted(a, checked, modules[0].src.path), .modules = modules, .catalog = catalog } };
    }
}

/// Prepare a catalog only for the shared durable facts path that consumes it.
fn sharedCatalog(context: Context, program: language.typed.Program) Error!?*const lowering_cache.Catalog {
    const bound = context.cache_plan orelse return null;
    if (bound.mode == .reference or std.mem.eql(u8, context.init.environ_map.get("MYLANG_TEST_KEYS") orelse "", "per-test")) return null;
    const catalog = try context.init.arena.allocator().create(lowering_cache.Catalog);
    catalog.* = lowering_cache.Catalog.prepare(program) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    return catalog;
}

/// `checked` as root `path` reads it. The merged source's first segment is its
/// entry, and an instruction without a span of its own (span 0) is located at the
/// entry's first byte: in the root's own check, its own file. The synthetic entry's
/// segment is named after the root, so such an instruction is located, traced and
/// keyed exactly as in the root's own check.
fn rooted(a: std.mem.Allocator, checked: frontend.Checked, path: []const u8) error{OutOfMemory}!frontend.Checked {
    const origins = try a.dupe(language.source.Source.Origin, checked.src.origins);
    origins[0].original.path = path;
    var src = checked.src;
    src.origins = origins;
    return .{ .program = checked.program, .src = src };
}

// spec-case: NEW-CORE-TEST-UNION-1
test "headed accepts headerless source and rejects a legacy module opening" {
    try std.testing.expect(headed("# about\n\nimport dep\n"));
    try std.testing.expect(!headed("module app\nimport dep\n"));
    try std.testing.expect(!headed("# only a comment\n"));
}

/// A root runner with nothing recorded: every replay misses.
fn nothingRecorded(init: std.process.Init, opts: options.Options, directed: shared.Directed) Error!?shared.Outcome {
    _ = init;
    _ = opts;
    _ = directed;
    return null;
}

/// Write each `{name, text}` pair under `root`.
fn writeFiles(root: std.Io.Dir, files: []const [2][]const u8) !void {
    for (files) |file| try root.writeFile(std.testing.io, .{ .sub_path = file[0], .data = file[1] });
}

/// Whether `view`'s modules include one named `name`.
fn holds(view: shared.View, name: []const u8) bool {
    for (view.modules) |module| if (std.mem.eql(u8, module.name, name)) return true;
    return false;
}

/// Whether every plan of `plans` runs in a child.
fn allChildren(plans: []const Plan) bool {
    for (plans) |item| if (item != .child) return false;
    return true;
}

// spec-case: NEW-CORE-TEST-UNION-1
// spec-case: NEW-CORE-TEST-FACTS-1
test "plan checks eligible roots together after their replays miss (eligibility, Replays.drain) and leaves the rest and a failed shared check to children" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try writeFiles(temporary.dir, &.{
        .{ "mylang.json", "{\"version\": 1}\n" },
        .{ "dep.my", "\npublic func value() -> int:\n    return 3\n" },
        .{ "other.my", "\npublic func unused() -> int:\n    return 4\n" },
        .{ "a_test.my", "import dep\n\npublic func test_a() -> bool:\n    return dep.value() == 3\n" },
        .{ "b_test.my", "import other\n\npublic func test_b() -> bool:\n    return other.unused() == 4\n" },
        .{ "c_test.my", "import dep\n\npublic func test_c() -> bool:\n    return dep.value() == 3\n" },
        .{ "app.my", "import dep\n\nfunc main() -> int:\n    return dep.value()\n\npublic func test_app() -> bool:\n    return True\n" },
    });
    var environment = try std.testing.environ.createMap(a);
    const init: std.process.Init = .{ .minimal = .{ .environ = .empty, .args = .{ .vector = &.{} } }, .arena = &arena, .gpa = std.testing.allocator, .io = std.testing.io, .environ_map = &environment, .preopens = .empty };
    const guest: tool_identity.Identity = .{ .path = "zig", .digest = @splat(0), .generation = @splat(0), .native_target = @splat(0), .inputs = 0, .memo_hit = false };
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const context: Context = .{
        .init = init,
        .controls = .{ .path = root, .build = .{ .zig = "zig", .cache = cache } },
        .guest = guest,
        .cache_plan = .{ .identity = @splat(0), .mode = .component, .io = std.testing.io, .environ = &environment, .directory = null, .artifact = null },
        .run_root = nothingRecorded,
        .workers = 2,
    };
    const names = [_][]const u8{ "a_test.my", "app.my", "b_test.my", "c_test.my" };
    var paths: [names.len][]const u8 = undefined;
    for (names, &paths) |name, *path| path.* = try std.fs.path.join(a, &.{ root, name });
    var outcomes: [names.len]shared.Outcome = @splat(.{});
    var plans: [names.len]Plan = undefined;
    var checks = try plan(context, &paths, &outcomes, &plans);
    defer checks.deinit();
    // `app` declares `main` and keeps its own check; headerless test roots share.
    try std.testing.expect(plans[0] == .together and plans[2] == .together and plans[3] == .together);
    try std.testing.expect(plans[1] == .child);
    try std.testing.expect(plans[0].together.catalog != null);
    try std.testing.expect(plans[0].together.catalog == plans[2].together.catalog and plans[0].together.catalog == plans[3].together.catalog);
    try std.testing.expect(plans[0].together.catalog.?.matches(plans[0].together.checked.program));
    try std.testing.expect(plans[2].together.catalog.?.matches(plans[2].together.checked.program));
    var reference = context;
    reference.cache_plan.?.mode = .reference;
    try std.testing.expect(try sharedCatalog(reference, plans[0].together.checked.program) == null);
    reference.cache_plan = null;
    try std.testing.expect(try sharedCatalog(reference, plans[0].together.checked.program) == null);
    // Each root's share holds only its own graph.
    try std.testing.expect(holds(plans[0].together, "dep") and !holds(plans[0].together, "other") and !holds(plans[0].together, "b_test"));
    try std.testing.expect(holds(plans[2].together, "other") and !holds(plans[2].together, "dep"));
    // An instruction without a span of its own is located at the root's own file.
    try std.testing.expectEqualStrings("a_test.my", frontend.position(plans[0].together.checked.src, .{ .start = 0, .end = 0 }).path);
    try std.testing.expectEqualStrings("b_test.my", frontend.position(plans[2].together.checked.src, .{ .start = 0, .end = 0 }).path);
    // A shared check that fails leaves every root of the project to its own child.
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "b_test.my", .data = "import other\n\npublic func test_b() -> bool:\n    return other.unused() == \"four\"\n" });
    var failed_plans: [names.len]Plan = undefined;
    var failed = try plan(context, &paths, &outcomes, &failed_plans);
    defer failed.deinit();
    try std.testing.expect(allChildren(&failed_plans));
}
