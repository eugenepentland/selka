//! Directory programs run in bounded child processes. Every test-declaring
//! source must appear in a child's checked inventory, including orphan libraries.
const std = @import("std");
const language = @import("mylang");
const project_entry = @import("project_entry.zig");
const frontend = @import("frontend.zig");
const options = @import("test_runner_options.zig");
const budget = @import("memory_budget");
const report = @import("test_runner_report.zig");
const tool_identity = @import("tool_identity.zig");
const tool_ticket = @import("tool_ticket.zig");
const case_settings = @import("test_runner_cases.zig");
const receipt = @import("test_runner_receipt.zig");
const Error = @import("test_runner_property.zig").Error;
const root_share = @import("test_runner_shared.zig");
const together = @import("test_runner_union.zig");

const Input = struct { path: []const u8, digest: ?[32]u8 };
const Location = struct { path: []const u8, root: []const u8, name: []const u8, configuration: ?[]const u8 };
const Selection = struct { entries: []const []const u8, tested: []const []const u8, inputs: []const Input, discovered: []const []const u8, locations: []const Location = &.{} };
const Orphan = struct { path: []const u8, closure: []const []const u8 };
const Outcome = root_share.Outcome;
const Fanout = struct { compiler: []const u8, directory: []const u8, controls: options.Options, jobs: usize, ticket: []const u8, run_root: root_share.RunRoot, guest: tool_identity.Identity };
const Discovery = struct { allocator: std.mem.Allocator, gpa: std.mem.Allocator, io: std.Io };
const Snapshot = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    inputs: std.ArrayList(Input) = .empty,
    index: std.StringHashMapUnmanaged(usize) = .empty,
    locations: std.ArrayList(Location) = .empty,

    fn record(self: *Snapshot, path: []const u8, digest: ?[32]u8) error{ OutOfMemory, SourceChanged }!void {
        if (self.index.get(path)) |position| {
            if (!sameDigest(self.inputs.items[position].digest, digest)) return error.SourceChanged;
            return;
        }
        try self.inputs.append(self.allocator, .{ .path = path, .digest = digest });
        try self.index.put(self.allocator, path, self.inputs.items.len - 1);
    }

    fn content(self: *Snapshot, path: []const u8, bytes: []const u8) error{ OutOfMemory, SourceChanged }!void {
        var digest: [32]u8 = undefined;
        std.crypto.hash.Blake3.hash(bytes, &digest, .{});
        try self.record(path, digest);
    }

    fn disk(self: *Snapshot, path: []const u8) !void {
        if (self.index.contains(path)) return;
        try self.record(path, try receipt.readDigest(self.allocator, self.io, path));
    }

    fn source(self: *Snapshot, path: []const u8, src: language.source.Source, overridden: bool) !void {
        if (!overridden) try self.content(path, src.bytes);
        for (src.embeds) |embed| {
            if (embed.status != .ok and embed.status != .missing) continue;
            const asset = try std.fs.path.resolve(self.allocator, &.{ std.fs.path.dirname(path).?, embed.path });
            try self.record(asset, if (embed.status == .ok) embed.digest else null);
        }
    }
};

const Overlay = struct {
    files: *language.project_files.Files,
    providers: []const frontend.Provider,

    fn provider(self: *Overlay) language.project.Provider {
        return .{ .context = self, .read = read, .embed = readEmbed };
    }
    fn read(context: ?*anyopaque, a: std.mem.Allocator, relative: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Overlay = @ptrCast(@alignCast(context.?));
        for (self.providers) |item| if (std.mem.eql(u8, item.path, relative)) {
            if (item.text.len > limit) return error.TooLarge;
            return a.dupe(u8, item.text);
        };
        return language.project_files.Files.read(self.files, a, relative, limit);
    }
    fn readEmbed(context: ?*anyopaque, a: std.mem.Allocator, module_path: []const u8, path: []const u8, limit: usize) std.mem.Allocator.Error!language.embed.Read {
        const self: *Overlay = @ptrCast(@alignCast(context.?));
        return language.project_files.Files.readEmbed(self.files, a, module_path, path, limit);
    }
};

/// Whether the command names a directory rather than a single project entry.
pub fn selected(io: std.Io, path: []const u8) bool {
    const info = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return info.kind == .directory;
}

/// Discover roots and run them with one shared bounded worker budget: in this
/// process from a shared check where they can (NEW-CORE-TEST-UNION-1, `run_root`),
/// else in child processes.
pub fn run(init: std.process.Init, opts: options.Options, run_root: root_share.RunRoot) Error!u8 {
    const a = init.arena.allocator();
    if (opts.controls.cases != null) {
        try write(init.io, std.Io.File.stderr(), "error: --cases requires a single test entry\n");
        return 2;
    }
    var diagnostics: std.ArrayList(u8) = .empty;
    const selection = programs(init, opts, &diagnostics) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try diagnostics.print(a, "error: directory test discovery failed: {s}\n", .{@errorName(err)});
        try write(init.io, std.Io.File.stderr(), diagnostics.items);
        return 1;
    };
    if (selection.entries.len == 0) {
        try write(init.io, std.Io.File.stdout(), if (opts.json) try report.jsonSources(a, &.{}, &.{}) else try report.text(a, &.{}));
        return 3;
    }
    const compiler = std.Io.Dir.cwd().realPathFileAlloc(init.io, "/proc/self/exe", a) catch return error.ReadFailed;
    var nonce: [16]u8 = undefined;
    std.Io.random(init.io, &nonce);
    const directory = try std.fmt.allocPrint(a, "{s}/tests/directory-{s}", .{ opts.build.cache, std.fmt.bytesToHex(nonce, .lower) });
    std.Io.Dir.cwd().createDirPath(init.io, directory) catch return error.WriteFailed;
    defer retire(init.io, directory);
    const request: tool_identity.Request = .{ .arena = a, .io = init.io, .environment = init.environ_map, .executable = opts.build.zig, .cache = opts.build.cache };
    const guest = tool_identity.captureReplayParent(request) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try write(init.io, std.Io.File.stderr(), try std.fmt.allocPrint(a, "error: cannot identify guest toolchain: {s}\n", .{@errorName(err)}));
        return 1;
    };
    const ticket = try std.fs.path.join(a, &.{ directory, "tool-ticket.json" });
    const encoded = tool_ticket.encode(.{ .tool = request, .compiler_identity = frontend.compiler_identity }, guest) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.ReadFailed;
    };
    std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = ticket, .data = encoded }) catch return error.WriteFailed;
    var controls = opts;
    controls.build.zig = guest.path;
    const free = budget.available(init.io);
    const workers = options.width(opts.controls, init.environ_map, selection.entries.len, free);
    const overall = options.width(opts.controls, init.environ_map, std.math.maxInt(usize), free);
    const fanout: Fanout = .{ .compiler = compiler, .directory = directory, .controls = controls, .jobs = overall, .ticket = ticket, .run_root = run_root, .guest = guest };
    const outcomes = try a.alloc(Outcome, selection.entries.len);
    const plans = try a.alloc(together.Plan, selection.entries.len);
    var checks = try together.plan(.{ .init = init, .controls = controls, .guest = guest, .run_root = run_root, .workers = workers }, selection.entries, outcomes, plans);
    defer checks.deinit();
    var order: std.ArrayList(usize) = .empty;
    for (try largestFirst(a, init.io, selection.entries)) |index| if (plans[index] != .replayed) try order.append(a, index);
    const roots: Roots = .{ .paths = selection.entries, .order = order.items, .outcomes = outcomes, .plans = plans };
    // Roots run in this process share one budget of test processes with the children.
    var permits: root_share.Permits = .init(overall);
    var sharing = false;
    for (plans) |item| sharing = sharing or item == .together;
    try pool(init, fanout, .{ .roots = roots, .workers = workers, .permits = if (sharing) &permits else null });
    const unchanged = tool_identity.unchanged(request, guest) catch |err| unchanged: {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        break :unchanged false;
    };
    return summarize(init, opts, selection, outcomes, unchanged);
}

fn programs(init: std.process.Init, opts: options.Options, diagnostics: *std.ArrayList(u8)) !Selection {
    const a = init.arena.allocator();
    const found = try inventory(a, init.io, opts);
    var roots: std.ArrayList([]const u8) = .empty;
    var tested: std.ArrayList([]const u8) = .empty;
    var libraries: std.ArrayList([]const u8) = .empty;
    var snapshot: Snapshot = .{ .allocator = a, .io = init.io };
    defer snapshot.index.deinit(a);
    for (found) |path| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 << 20));
        try snapshot.content(path, bytes);
        const tests = declaresTests(bytes);
        if (tests) try tested.append(a, path);
        if (language.project_config.declaresMain(bytes) or std.mem.endsWith(u8, path, "_test.my")) {
            try roots.append(a, path);
        } else if (tests) try libraries.append(a, path);
    }
    var reached: std.StringHashMapUnmanaged(void) = .empty;
    defer reached.deinit(a);
    const shares = try sharedClosures(init, roots.items, &snapshot);
    for (roots.items, shares) |path, share| for (try closure(init, path, .{ .diagnostics = diagnostics, .snapshot = &snapshot, .filter = opts.filter, .share = share })) |loaded| try reached.put(a, loaded, {});
    var orphans: std.ArrayList(Orphan) = .empty;
    for (libraries.items) |path| if (!reached.contains(path)) {
        try orphans.append(a, .{ .path = path, .closure = try closure(init, path, .{ .diagnostics = diagnostics, .snapshot = &snapshot, .filter = opts.filter }) });
    };
    for (orphans.items, 0..) |orphan, index| {
        var imported = false;
        for (orphans.items, 0..) |other, other_index| {
            if (index == other_index) continue;
            for (other.closure) |path| if (std.mem.eql(u8, path, orphan.path)) {
                imported = true;
            };
        }
        if (!imported) try roots.append(a, orphan.path);
    }
    if (roots.items.len > 4096) return error.TooManyTestPrograms;
    std.mem.sort([]const u8, roots.items, {}, before);
    return .{ .entries = roots.items, .tested = tested.items, .inputs = snapshot.inputs.items, .discovered = found, .locations = snapshot.locations.items };
}

fn inventory(a: std.mem.Allocator, io: std.Io, opts: options.Options) ![]const []const u8 {
    const root = try std.Io.Dir.cwd().realPathFileAlloc(io, opts.path, a);
    const working = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", a);
    const cache = std.Io.Dir.cwd().realPathFileAlloc(io, opts.build.cache, a) catch try std.fs.path.resolve(a, &.{ working, opts.build.cache });
    const cache_prefix = try std.fmt.allocPrint(a, "{s}/", .{cache});
    var directory = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true, .follow_symlinks = false });
    defer directory.close(io);
    var walker = try directory.walk(a);
    defer walker.deinit();
    var found: std.ArrayList([]const u8) = .empty;
    while (try walker.next(io)) |item| {
        const absolute = try std.fs.path.join(a, &.{ root, item.path });
        if (std.mem.eql(u8, absolute, cache) or std.mem.startsWith(u8, absolute, cache_prefix)) {
            if (item.kind == .directory) walker.leave(io);
            continue;
        }
        if (generated(item.basename)) {
            if (item.kind == .directory) walker.leave(io);
            continue;
        }
        if (item.kind == .file and std.mem.endsWith(u8, item.path, ".my")) try found.append(a, try std.fs.path.join(a, &.{ root, item.path }));
    }
    std.mem.sort([]const u8, found.items, {}, before);
    return found.items;
}

/// What `closure` records into and reads: where problems go, the run's input
/// snapshot, the run's filter, and the root's import graph when a shared load
/// already found it.
const Reading = struct { diagnostics: *std.ArrayList(u8), snapshot: *Snapshot, filter: []const u8, share: ?[]const []const u8 = null };

fn closure(init: std.process.Init, path: []const u8, reading: Reading) ![]const []const u8 {
    const a = init.arena.allocator();
    const diagnostics = reading.diagnostics;
    const snapshot = reading.snapshot;
    const filter = reading.filter;
    const located = try project_entry.resolve(a, init.io, path, diagnostics);
    try snapshot.locations.append(a, .{ .path = located.path, .root = located.root, .name = located.name, .configuration = if (located.configuration) |file| file.path else null });
    try configurationInputs(snapshot, located);
    const cases = try case_settings.load(a, init.io, located.path, null);
    const cases_path = try case_settings.defaultPath(a, located.path);
    if (cases.path != null) try snapshot.content(cases_path, cases.bytes) else try snapshot.record(cases_path, null);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 << 20));
    if (!language.opensAsModule(bytes)) {
        var src = try language.source.Source.init(a, std.fs.path.basename(path), bytes);
        src.embeds = try language.embed.scan(a, src);
        const module_path = try language.project.modulePath(a, located.name);
        try language.embed.resolve(a, .{ .io = init.io, .import_root = located.root, .root = if (located.configuration) |file| std.fs.path.dirname(file.path).? else located.root }, module_path, @constCast(src.embeds));
        try snapshot.source(located.path, src, false);
        return a.dupe([]const u8, &.{located.path});
    }
    const resources: Discovery = .{ .allocator = a, .gpa = init.gpa, .io = init.io };
    const paths = reading.share orelse try loadedClosure(resources, located, &.{}, snapshot);
    for (try case_settings.providerSets(a, cases, filter)) |providers| _ = try loadedClosure(resources, located, providers, snapshot);
    return paths;
}

/// The import closures of the headed roots of `roots` (those opening with a `module`
/// header), each project's from one load of an entry importing all of them, each
/// module read once (NEW-CORE-TEST-UNION-1); null for every other root, and for
/// every root of a project whose shared load fails, which load alone.
fn sharedClosures(init: std.process.Init, roots: []const []const u8, snapshot: *Snapshot) ![]const ?[]const []const u8 {
    const a = init.arena.allocator();
    const found = try a.alloc(?[]const []const u8, roots.len);
    @memset(found, null);
    const entries = try a.alloc(?project_entry.Entry, roots.len);
    for (roots, entries) |path, *entry| entry.* = try headedEntry(init, path);
    const done = try a.alloc(bool, roots.len);
    @memset(done, false);
    for (entries, 0..) |candidate, first| {
        const entry = candidate orelse continue;
        if (done[first]) continue;
        var members: std.ArrayList(usize) = .empty;
        for (entries[first..], first..) |other, index| {
            const peer = other orelse continue;
            if (done[index] or !sameProject(entry, peer)) continue;
            done[index] = true;
            try members.append(a, index);
        }
        try loadTogether(init, entries, members.items, snapshot, found);
    }
    return found;
}

/// The resolved entry of a root that opens with its `module` header, else null.
fn headedEntry(init: std.process.Init, path: []const u8) !?project_entry.Entry {
    const a = init.arena.allocator();
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 << 20)) catch return null;
    if (!together.headed(bytes)) return null;
    var problems: std.ArrayList(u8) = .empty;
    return project_entry.resolve(a, init.io, path, &problems) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
}

fn sameProject(one: project_entry.Entry, other: project_entry.Entry) bool {
    const mine = if (one.configuration) |file| file.path else "";
    const theirs = if (other.configuration) |file| file.path else "";
    return std.mem.eql(u8, one.root, other.root) and std.mem.eql(u8, mine, theirs);
}

/// Load the roots `members` of one project through one synthetic entry and record
/// each one's closure, as `loadedClosure` records one root's.
fn loadTogether(init: std.process.Init, entries: []const ?project_entry.Entry, members: []const usize, snapshot: *Snapshot, found: []?[]const []const u8) !void {
    const a = init.arena.allocator();
    const first = entries[members[0]].?;
    if (try together.occupied(init.io, a, first.root)) return;
    const names = try a.alloc([]const u8, members.len);
    for (members, names) |index, *name| name.* = entries[index].?.name;
    var session = frontend.Session.init(init.gpa, init.io, first.root);
    defer session.deinit();
    first.configure(&session);
    const providers = [_]frontend.Provider{.{ .path = together.entry_name ++ ".my", .text = try together.entryText(a, names) }};
    var overlay: Overlay = .{ .files = &session.files, .providers = &providers };
    session.project.load(overlay.provider(), together.entry_name, first.limits()) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return;
    };
    for (members) |index| {
        const reached = try root_share.closure(a, session.project.modules.items, entries[index].?.name);
        if (reached.len == 0) continue;
        var paths: std.ArrayList([]const u8) = .empty;
        for (reached) |module| if (try recordModule(a, first, module, &.{}, snapshot)) |path| try paths.append(a, path);
        found[index] = paths.items;
    }
}

/// Record one loaded module's source, embeds and interface file in `snapshot`; its
/// path, or null for a standard module.
fn recordModule(a: std.mem.Allocator, located: project_entry.Entry, module: *const frontend.Module, providers: []const frontend.Provider, snapshot: *Snapshot) !?[]const u8 {
    if (std.mem.startsWith(u8, module.src.path, "@stdlib/")) return null;
    const path = try std.fs.path.join(a, &.{ located.root, module.src.path });
    var overridden = false;
    for (providers) |provider| overridden = overridden or std.mem.eql(u8, provider.path, module.src.path);
    try snapshot.source(path, module.src, overridden);
    if (located.configuration) |file| if (file.document.interface_files) {
        try snapshot.disk(try std.fmt.allocPrint(a, "{s}.api", .{path[0 .. path.len - 3]}));
    };
    return path;
}

fn loadedClosure(resources: Discovery, located: project_entry.Entry, providers: []const frontend.Provider, snapshot: *Snapshot) ![]const []const u8 {
    const a = resources.allocator;
    var session = frontend.Session.init(resources.gpa, resources.io, located.root);
    defer session.deinit();
    located.configure(&session);
    var overlay: Overlay = .{ .files = &session.files, .providers = providers };
    try session.project.load(overlay.provider(), located.name, located.limits());
    var paths: std.ArrayList([]const u8) = .empty;
    for (session.project.modules.items) |*module| if (try recordModule(a, located, module, providers, snapshot)) |path| try paths.append(a, path);
    return paths.items;
}

fn configurationInputs(snapshot: *Snapshot, entry: project_entry.Entry) !void {
    if (entry.configuration) |file| {
        try snapshot.content(file.path, file.bytes);
        if (file.policy) |policy| try snapshot.content(policy.path, policy.bytes);
    }
    var directory = std.fs.path.dirname(entry.path).?;
    while (true) {
        const path = try std.fs.path.join(snapshot.allocator, &.{ directory, language.project_config.config_name });
        try snapshot.disk(path);
        if (entry.configuration) |file| if (std.mem.eql(u8, path, file.path)) return;
        const parent = std.fs.path.dirname(directory) orelse return;
        if (std.mem.eql(u8, parent, directory)) return;
        directory = parent;
    }
}

/// The roots of one directory run, the order they start in, where their reports go,
/// and how each runs.
const Roots = struct { paths: []const []const u8, order: []const usize, outcomes: []Outcome, plans: []const together.Plan };
/// The shared state of one directory run's workers.
const Queue = struct {
    roots: Roots,
    workers: usize,
    next: std.atomic.Value(usize) = .init(0),
    running: std.atomic.Value(usize) = .init(0),
    /// Set once, by the first worker whose child could not start; that worker alone
    /// writes `failure`, which is read only after every worker has joined.
    stopped: std.atomic.Value(bool) = .init(false),
    failure: ?Error = null,
    /// The run's test process budget when roots run in this process too.
    permits: ?*root_share.Permits = null,

    fn stop(self: *Queue, err: Error) void {
        if (self.stopped.cmpxchgStrong(false, true, .acq_rel, .acquire) == null) self.failure = err;
    }
};

/// NEW-CORE-TEST-QUEUE-1: `queue.workers` workers each start the next root as soon as
/// their last child exits, in `queue.roots.order`, until every root has run. Reports stay
/// in root order, whatever order the children finish in.
fn pool(init: std.process.Init, fanout: Fanout, queue: Queue) Error!void {
    const a = init.arena.allocator();
    var environment = try init.environ_map.clone(a);
    defer environment.deinit();
    try environment.put(tool_ticket.hint, "1");
    var shared = queue;
    const worker: Worker = .{ .init = init, .fanout = fanout, .environment = &environment, .queue = &shared };
    const threads = try a.alloc(std.Thread, @max(1, shared.workers) - 1);
    var started: usize = 0;
    // The pinned Zig arena is thread-safe with Init's thread-safe backing.
    for (threads) |*thread| {
        thread.* = std.Thread.spawn(.{}, Worker.run, .{worker}) catch break;
        started += 1;
    }
    worker.run();
    for (threads[0..started]) |thread| thread.join();
    if (shared.failure) |err| return err;
}

/// One worker of `pool`: it runs roots until the queue is empty or a child could not start.
const Worker = struct {
    init: std.process.Init,
    fanout: Fanout,
    environment: *const std.process.Environ.Map,
    queue: *Queue,

    fn run(self: Worker) void {
        const queue = self.queue;
        while (!queue.stopped.load(.acquire)) {
            const roots = queue.roots;
            const position = queue.next.fetchAdd(1, .monotonic);
            if (position >= roots.order.len) return;
            const running = queue.running.fetchAdd(1, .monotonic) + 1;
            defer _ = queue.running.fetchSub(1, .monotonic);
            const index = roots.order[position];
            const jobs = childJobs(self.fanout.jobs, queue.workers, roots.order.len - position - 1, running);
            const outcome = switch (roots.plans[index]) {
                .together => |view| self.inProcess(roots.paths[index], view),
                else => self.held(roots.paths[index], index, jobs),
            };
            roots.outcomes[index] = outcome catch |err| return queue.stop(err);
        }
    }

    /// A child root, holding its share of the run's test process budget while it runs.
    fn held(self: Worker, path: []const u8, slot: usize, jobs: usize) Error!Outcome {
        const permits = self.queue.permits orelse return self.child(path, slot, jobs);
        permits.acquire(self.init.io, jobs);
        defer permits.release(self.init.io, jobs);
        return self.child(path, slot, jobs);
    }

    /// Run a root in this process from its share of a shared check, with its own
    /// arena, as a child would run it. Its tests may use the whole budget: each of its
    /// test processes holds a permit, so it takes what the other roots leave.
    fn inProcess(self: Worker, path: []const u8, view: root_share.View) Error!Outcome {
        var arena = std.heap.ArenaAllocator.init(self.init.gpa);
        defer arena.deinit();
        var init = self.init;
        init.arena = &arena;
        var controls = self.fanout.controls;
        controls.path = path;
        controls.controls.jobs = self.fanout.jobs;
        const outcome = try self.fanout.run_root(init, controls, .{ .guest = self.fanout.guest, .view = view, .permits = self.queue.permits }) orelse return .{};
        return .{ .code = outcome.code, .bytes = try self.init.arena.allocator().dupe(u8, outcome.bytes) };
    }

    fn child(self: Worker, path: []const u8, slot: usize, jobs: usize) Error!Outcome {
        const a = self.init.arena.allocator();
        const name = try std.fmt.allocPrint(a, "{s}/{d}.json", .{ self.fanout.directory, slot });
        const output = std.Io.Dir.cwd().createFile(self.init.io, name, .{}) catch return error.WriteFailed;
        defer output.close(self.init.io);
        // Each child gets its own open-file offset, never a shared stdin stream.
        const input = std.Io.Dir.cwd().openFile(self.init.io, self.fanout.ticket, .{}) catch return error.ReadFailed;
        defer input.close(self.init.io);
        var fanout = self.fanout;
        fanout.jobs = jobs;
        const launch: @import("process_spawn.zig").Options = .{ .argv = try argv(a, fanout, path), .environment = .{ .map = self.environment }, .stdin = .{ .file = input }, .stdout = .{ .file = output } };
        var process = @import("process_spawn.zig").spawn(self.init.gpa, launch) catch return error.WriteFailed;
        const term = process.wait(self.init.io) catch {
            process.kill(self.init.io);
            return error.ReadFailed;
        };
        return .{ .code = switch (term) {
            .exited => |code| code,
            else => 1,
        }, .bytes = std.Io.Dir.cwd().readFileAlloc(self.init.io, name, a, .limited(64 << 20)) catch "" };
    }
};

/// A child's share of the run's `overall` jobs: divided among the children that can
/// still run beside it (those running, itself included, and those not yet started),
/// at most `workers` of them, and never below one.
fn childJobs(overall: usize, workers: usize, unstarted: usize, running: usize) usize {
    const beside = @max(1, @min(workers, running + unstarted));
    return @max(1, overall / beside);
}

/// Root indices, largest root file first (ties in path order): the biggest test
/// programs start first, so a long one never begins after the short ones have drained.
fn largestFirst(a: std.mem.Allocator, io: std.Io, paths: []const []const u8) Error![]const usize {
    const Sized = struct { index: usize, size: u64 };
    const sized = try a.alloc(Sized, paths.len);
    for (paths, sized, 0..) |path, *item, index| {
        const info = std.Io.Dir.cwd().statFile(io, path, .{}) catch null;
        item.* = .{ .index = index, .size = if (info) |known| known.size else 0 };
    }
    std.mem.sort(Sized, sized, {}, struct {
        fn larger(_: void, left: Sized, right: Sized) bool {
            return left.size > right.size or (left.size == right.size and left.index < right.index);
        }
    }.larger);
    const order = try a.alloc(usize, paths.len);
    for (sized, order) |item, *slot| slot.* = item.index;
    return order;
}

fn argv(a: std.mem.Allocator, fanout: Fanout, path: []const u8) Error![]const []const u8 {
    const opts = fanout.controls;
    var arguments: std.ArrayList([]const u8) = .empty;
    try arguments.appendSlice(a, &.{ fanout.compiler, "test", path, "--json", "--filter", opts.filter, "--cache-dir", opts.build.cache, "--zig", opts.build.zig, "--jobs", try std.fmt.allocPrint(a, "{d}", .{fanout.jobs}) });
    try arguments.appendSlice(a, &.{ "--timeout-ms", try std.fmt.allocPrint(a, "{d}", .{opts.controls.timeout_ms}) });
    if (opts.controls.ceilings.explicit_steps) try arguments.appendSlice(a, &.{ "--max-steps", try std.fmt.allocPrint(a, "{d}", .{opts.controls.max_steps}) });
    const ceilings = opts.controls.ceilings;
    if (ceilings.explicit_frames) try arguments.appendSlice(a, &.{ "--max-frames", try std.fmt.allocPrint(a, "{d}", .{ceilings.frames}) });
    if (ceilings.explicit_memory) try arguments.appendSlice(a, &.{ "--max-memory", try std.fmt.allocPrint(a, "{d}", .{ceilings.memory}) });
    try arguments.appendSlice(a, &.{ "--property-runs", try std.fmt.allocPrint(a, "{d}", .{opts.property_runs}) });
    if (opts.build.release) try arguments.append(a, "--release");
    if (opts.build.facts == .verify) try arguments.append(a, "--verify-facts");
    if (opts.build.facts == .off) try arguments.append(a, "--no-facts");
    if (opts.controls.force) try arguments.append(a, "--force");
    if (opts.controls.against) |reference| try arguments.appendSlice(a, &.{ "--affected", "--against", reference });
    if (opts.seed) |seed| try arguments.appendSlice(a, &.{ "--seed", try std.fmt.allocPrint(a, "{d}", .{seed}) });
    for (opts.build.links) |link| try arguments.appendSlice(a, &.{ "--link", link });
    return arguments.items;
}

fn summarize(init: std.process.Init, opts: options.Options, selection: Selection, outcomes: []const Outcome, tool_unchanged: bool) Error!u8 {
    const a = init.arena.allocator();
    var verdicts: std.ArrayList(report.Verdict) = .empty;
    var accounted: std.StringHashMapUnmanaged(void) = .empty;
    defer accounted.deinit(a);
    // A program that failed to set up (status 2: an invalid cases file or provider
    // fixture, an unreadable entry) makes the whole run status 2, as in the old core.
    var setup_failed = false;
    for (selection.entries, outcomes) |path, outcome| {
        const first_verdict = verdicts.items.len;
        setup_failed = setup_failed or outcome.code == 2;
        const parsed = std.json.parseFromSlice(std.json.Value, a, outcome.bytes, .{ .allocate = .alloc_always }) catch {
            try verdicts.append(a, .{ .name = path, .status = .failed, .reason = if (outcome.code == 2) "test program failed to set up (status 2)" else "test program produced no usable report" });
            continue;
        };
        const value = parsed.value;
        if (value != .object or !std.mem.eql(u8, string(value, "version"), "native-tests-v1")) {
            try verdicts.append(a, .{ .name = path, .status = .failed, .reason = "invalid test report version" });
            continue;
        }
        const tests = value.object.get("tests") orelse .null;
        const sources = value.object.get("sources") orelse .null;
        if (tests != .array or sources != .array) {
            try verdicts.append(a, .{ .name = path, .status = .failed, .reason = "incomplete test report" });
            continue;
        }
        for (sources.array.items) |source| if (source == .string) {
            try accounted.put(a, source.string, {});
        };
        for (tests.array.items) |test_value| {
            const status = std.meta.stringToEnum(report.Status, string(test_value, "status")) orelse .failed;
            var item: report.Verdict = .{ .name = string(test_value, "name"), .status = status, .reason = string(test_value, "reason"), .at = string(test_value, "at") };
            if (test_value == .object) if (test_value.object.get("property")) |evidence| {
                const parsed_evidence = std.json.parseFromValueLeaky(@import("test_runner_property.zig").Evidence, a, evidence, .{}) catch {
                    item.status = .failed;
                    item.reason = "invalid property evidence in test report";
                    try verdicts.append(a, item);
                    continue;
                };
                item.property = parsed_evidence;
            };
            try verdicts.append(a, item);
        }
        if (outcome.code != report.exitStatus(verdicts.items[first_verdict..])) try verdicts.append(a, .{ .name = path, .status = .failed, .reason = "test program exit status disagrees with its report" });
    }
    if (!tool_unchanged) try verdicts.append(a, .{ .name = opts.path, .status = .failed, .reason = "SourceChanged: toolchain changed during directory execution" });
    if (try sourceChanged(a, init.io, opts, selection)) try verdicts.append(a, .{ .name = opts.path, .status = .failed, .reason = "SourceChanged: directory discovery inputs changed during execution" });
    for (selection.tested) |path| if (!accounted.contains(path)) {
        try verdicts.append(a, .{ .name = path, .status = .failed, .reason = "test-declaring source was not loaded by any test program" });
    };
    var sources: std.ArrayList([]const u8) = .empty;
    var keys = accounted.keyIterator();
    while (keys.next()) |key| try sources.append(a, key.*);
    std.mem.sort([]const u8, sources.items, {}, before);
    try write(init.io, std.Io.File.stdout(), if (opts.json) try report.jsonSources(a, verdicts.items, sources.items) else try report.text(a, verdicts.items));
    return if (setup_failed) 2 else report.exitStatus(verdicts.items);
}

fn sourceChanged(a: std.mem.Allocator, io: std.Io, opts: options.Options, selection: Selection) Error!bool {
    const current = inventory(a, io, opts) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return true;
    };
    if (current.len != selection.discovered.len) return true;
    for (current, selection.discovered) |path, original| if (!std.mem.eql(u8, path, original)) return true;
    for (selection.inputs) |input| {
        const digest = receipt.readDigest(a, io, input.path) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return true;
        };
        if (!sameDigest(digest, input.digest)) return true;
    }
    var diagnostics: std.ArrayList(u8) = .empty;
    for (selection.locations) |original| {
        const located = project_entry.resolve(a, io, original.path, &diagnostics) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return true;
        };
        if (!std.mem.eql(u8, original.root, located.root) or !std.mem.eql(u8, original.name, located.name)) return true;
        const config = if (located.configuration) |file| file.path else null;
        if (!samePath(config, original.configuration)) return true;
    }
    return false;
}

fn sameDigest(left: ?[32]u8, right: ?[32]u8) bool {
    if (left == null or right == null) return (left == null) == (right == null);
    return std.mem.eql(u8, &left.?, &right.?);
}
fn samePath(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return (left == null) == (right == null);
    return std.mem.eql(u8, left.?, right.?);
}

fn string(value: std.json.Value, key: []const u8) []const u8 {
    if (value != .object) return "";
    const field = value.object.get(key) orelse return "";
    return if (field == .string) field.string else "";
}

fn write(io: std.Io, file: std.Io.File, bytes: []const u8) Error!void {
    file.writeStreamingAll(io, bytes) catch return error.WriteFailed;
}

fn before(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}
fn generated(name: []const u8) bool {
    return std.mem.eql(u8, name, ".git") or std.mem.startsWith(u8, name, ".mylang-cache") or std.mem.eql(u8, name, ".zig-cache") or std.mem.eql(u8, name, "zig-out") or std.mem.eql(u8, name, "node_modules");
}
fn declaresTests(bytes: []const u8) bool {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.eql(u8, line, "@test")) return true;
        if (std.mem.startsWith(u8, line, "public ")) line = std.mem.trimStart(u8, line[7..], " \t");
        if (std.mem.startsWith(u8, line, "def test_")) return true;
    }
    return false;
}

// spec-case: NEW-CORE-S4-TEST-2
test "directory inventory recognizes test declarations and generated subtrees" {
    try std.testing.expect(declaresTests("public def test_x() -> bool:\n    return True\n"));
    try std.testing.expect(declaresTests("@test\ndef property(x: int) -> bool:\n    return True\n"));
    try std.testing.expect(!declaresTests("# def test_x()\n"));
    try std.testing.expect(generated(".mylang-cache-new"));
    try std.testing.expect(!generated("types"));
}

fn retire(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteTree(io, path) catch return;
}

// spec-case: NEW-CORE-S4-TEST-2
test "sourceChanged detects edited or removed discovery inputs and allocation failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "app.my" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = "original" });
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash("original", &digest, .{});
    const inputs = &.{Input{ .path = path, .digest = digest }};
    const selection: Selection = .{ .entries = &.{}, .tested = &.{}, .inputs = inputs, .discovered = &.{path} };
    const opts: options.Options = .{ .path = root, .build = .{ .zig = "zig", .cache = try std.fs.path.join(a, &.{ root, "cache" }) } };
    try std.testing.expect(!try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = "changed" });
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.deleteFile(std.testing.io, "app.my");
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, sourceChanged(failing.allocator(), std.testing.io, opts, selection));
}

// spec-case: NEW-CORE-S4-TEST-2
test "sourceChanged detects external dependencies absent cases and required API creation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.createDirPath(std.testing.io, "tests");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tests/app.my", .data = "entry" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dep.my", .data = "original" });
    const path = try std.fs.path.join(a, &.{ root, "tests/app.my" });
    const dependency = try std.fs.path.join(a, &.{ root, "dep.my" });
    const cases = try case_settings.defaultPath(a, path);
    const api = try std.fs.path.join(a, &.{ root, "dep.api" });
    var snapshot: Snapshot = .{ .allocator = a, .io = std.testing.io };
    defer snapshot.index.deinit(a);
    try snapshot.disk(path);
    try snapshot.disk(dependency);
    try snapshot.record(cases, null);
    try snapshot.record(api, null);
    const selection: Selection = .{ .entries = &.{}, .tested = &.{}, .inputs = snapshot.inputs.items, .discovered = &.{path} };
    const opts: options.Options = .{ .path = try std.fs.path.join(a, &.{ root, "tests" }), .build = .{ .zig = "zig", .cache = try std.fs.path.join(a, &.{ root, "cache" }) } };
    try std.testing.expect(!try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dep.my", .data = "changed" });
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dep.my", .data = "original" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tests/app.cases.json", .data = "{}" });
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.deleteFile(std.testing.io, "tests/app.cases.json");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dep.api", .data = "new interface" });
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
}

// spec-case: NEW-CORE-S4-TEST-2
test "Snapshot deduplicates content and refuses SourceChanged during discovery" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var snapshot: Snapshot = .{ .allocator = a, .io = std.testing.io };
    defer snapshot.index.deinit(a);
    try snapshot.content("dep.my", "first");
    try snapshot.content("dep.my", "first");
    try std.testing.expectEqual(@as(usize, 1), snapshot.inputs.items.len);
    try std.testing.expectError(error.SourceChanged, snapshot.content("dep.my", "other"));
}

// spec-case: NEW-CORE-S4-TEST-2
test "sourceChanged preserves inventory additions and ignores unrelated outputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "app.my" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = "original" });
    var snapshot: Snapshot = .{ .allocator = a, .io = std.testing.io };
    defer snapshot.index.deinit(a);
    try snapshot.disk(path);
    const selection: Selection = .{ .entries = &.{}, .tested = &.{}, .inputs = snapshot.inputs.items, .discovered = &.{path} };
    const opts: options.Options = .{ .path = root, .build = .{ .zig = "zig", .cache = try std.fs.path.join(a, &.{ root, "cache" }) } };
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "output.json", .data = "{}" });
    try std.testing.expect(!try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "new.my", .data = "new source" });
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
}

// spec-case: NEW-CORE-S4-TEST-2
test "loadedClosure snapshots provider imports embeds config policy cases and required APIs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.createDirPath(std.testing.io, "tests");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tests/app.my", .data = "module tests.app\nimport dep\npublic def test_x() -> bool:\n    return True\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dep.my", .data = "module dep\npublic def value() -> str:\n    return \"old\"\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "ext.my", .data = "module ext\npublic def value() -> str:\n    return \"external\"\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "data.txt", .data = "original asset" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = language.project_config.config_name, .data = "{\"version\":1,\"interface_files\":true,\"import_policy\":\"policy.json\"}" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "policy.json", .data = "{}" });
    const configured_cases = "{\"test_x\":{\"providers\":{\"dep.my\":\"module dep\\nimport ext\\n" ++
        "public def value() -> str:\\n    return embed_str(\\\"data.txt\\\")\\n\"}}}";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tests/app.cases.json", .data = configured_cases });
    const path = try std.fs.path.join(a, &.{ root, "tests/app.my" });
    var diagnostics: std.ArrayList(u8) = .empty;
    const entry = try project_entry.resolve(a, std.testing.io, path, &diagnostics);
    var snapshot: Snapshot = .{ .allocator = a, .io = std.testing.io };
    defer snapshot.index.deinit(a);
    try configurationInputs(&snapshot, entry);
    const cases = try case_settings.load(a, std.testing.io, path, null);
    try snapshot.content(cases.path.?, cases.bytes);
    const resources: Discovery = .{ .allocator = a, .gpa = std.testing.allocator, .io = std.testing.io };
    _ = try loadedClosure(resources, entry, &.{}, &snapshot);
    const sets = try case_settings.providerSets(a, cases, "");
    _ = try loadedClosure(resources, entry, sets[0], &snapshot);
    try std.testing.expect(snapshot.index.contains(try std.fs.path.join(a, &.{ root, "ext.my" })));
    try std.testing.expect(snapshot.index.contains(try std.fs.path.join(a, &.{ root, "data.txt" })));
    try std.testing.expect(snapshot.index.contains(try std.fs.path.join(a, &.{ root, "dep.api" })));
    try std.testing.expect(snapshot.index.contains(try std.fs.path.join(a, &.{ root, "policy.json" })));
    const selection: Selection = .{ .entries = &.{}, .tested = &.{}, .inputs = snapshot.inputs.items, .discovered = &.{path} };
    const opts: options.Options = .{ .path = try std.fs.path.join(a, &.{ root, "tests" }), .build = .{ .zig = "zig", .cache = try std.fs.path.join(a, &.{ root, "cache" }) } };
    try std.testing.expect(!try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "data.txt", .data = "changed asset" });
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
}

// spec: NEW-CORE-TEST-QUEUE-1
test "directory roots start largest file first and each child's jobs divide the budget among those beside it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "small.my", .data = "def test_a() -> bool:\n    return True\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "large.my", .data = "def test_b() -> bool:\n    return True\n\ndef test_c() -> bool:\n    return True\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "same.my", .data = "def test_d() -> bool:\n    return True\n\ndef test_e() -> bool:\n    return True\n" });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const paths = [_][]const u8{ try std.fs.path.join(a, &.{ root, "small.my" }), try std.fs.path.join(a, &.{ root, "large.my" }), try std.fs.path.join(a, &.{ root, "same.my" }), try std.fs.path.join(a, &.{ root, "missing.my" }) };
    try std.testing.expectEqualSlices(usize, &.{ 1, 2, 0, 3 }, try largestFirst(a, std.testing.io, &paths));
    try std.testing.expectEqual(@as(usize, 1), childJobs(16, 16, 57, 1));
    try std.testing.expectEqual(@as(usize, 4), childJobs(16, 4, 50, 1));
    try std.testing.expectEqual(@as(usize, 8), childJobs(16, 16, 0, 2));
    try std.testing.expectEqual(@as(usize, 16), childJobs(16, 4, 0, 1));
    try std.testing.expectEqual(@as(usize, 1), childJobs(1, 4, 9, 4));
}

/// Whether one of `paths` ends with `/name`.
fn lists(paths: []const []const u8, name: []const u8) bool {
    for (paths) |path| if (std.mem.endsWith(u8, path, name) and path[path.len - name.len - 1] == '/') return true;
    return false;
}

// spec-case: NEW-CORE-TEST-UNION-1
test "sharedClosures loads headed roots together (headedEntry, loadTogether) and leaves the rest and a failed load to load alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const io = std.testing.io;
    try temporary.dir.writeFile(io, .{ .sub_path = "mylang.json", .data = "{\"version\": 1}\n" });
    try temporary.dir.writeFile(io, .{ .sub_path = "dep.my", .data = "module dep\n\npublic def value() -> int:\n    return 3\n" });
    try temporary.dir.writeFile(io, .{ .sub_path = "a_test.my", .data = "module a_test\nimport dep\n\npublic def test_a() -> bool:\n    return dep.value() == 3\n" });
    try temporary.dir.writeFile(io, .{ .sub_path = "b_test.my", .data = "module b_test\n\npublic def test_b() -> bool:\n    return True\n" });
    try temporary.dir.writeFile(io, .{ .sub_path = "c_test.my", .data = "public def test_c() -> bool:\n    return True\n" });
    var environment = try std.testing.environ.createMap(a);
    const init: std.process.Init = .{ .minimal = .{ .environ = .empty, .args = .{ .vector = &.{} } }, .arena = &arena, .gpa = std.testing.allocator, .io = io, .environ_map = &environment, .preopens = .empty };
    const roots = [_][]const u8{ try std.fs.path.join(a, &.{ root, "a_test.my" }), try std.fs.path.join(a, &.{ root, "b_test.my" }), try std.fs.path.join(a, &.{ root, "c_test.my" }) };
    var snapshot: Snapshot = .{ .allocator = a, .io = io };
    const found = try sharedClosures(init, &roots, &snapshot);
    try std.testing.expect(lists(found[0].?, "a_test.my") and lists(found[0].?, "dep.my"));
    try std.testing.expect(lists(found[1].?, "b_test.my") and !lists(found[1].?, "dep.my"));
    try std.testing.expectEqual(@as(?[]const []const u8, null), found[2]);
    // A root that imports a missing module fails the shared load: every root loads alone.
    try temporary.dir.writeFile(io, .{ .sub_path = "b_test.my", .data = "module b_test\nimport missing\n\npublic def test_b() -> bool:\n    return True\n" });
    var fresh: Snapshot = .{ .allocator = a, .io = io };
    const alone = try sharedClosures(init, &roots, &fresh);
    try std.testing.expectEqual(@as(?[]const []const u8, null), alone[0]);
    try std.testing.expectEqual(@as(?[]const []const u8, null), alone[1]);
}
