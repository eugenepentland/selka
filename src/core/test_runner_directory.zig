//! Directory programs run in bounded child processes. Every test-declaring
//! source must appear in a child's checked inventory, including orphan libraries.
const std = @import("std");
const product = @import("selka").product;
const fast_blake3 = @import("fast_blake3.zig");
const language = @import("selka");
const project_entry = @import("project_entry.zig");
const frontend = @import("frontend.zig");
const options = @import("test_runner_options.zig");
const budget = @import("memory_budget");
const report = @import("test_runner_report.zig");
const tool_identity = @import("tool_identity.zig");
const zig_lookup = @import("zig_lookup.zig");
const tool_ticket = @import("tool_ticket.zig");
const planner = @import("selka").cache_plan_adapter;
const case_settings = @import("test_runner_cases.zig");
const receipt = @import("test_runner_receipt.zig");
const build_mode = @import("build_mode.zig");
const Error = @import("test_runner_property.zig").Error;
const root_share = @import("test_runner_shared.zig");
const together = @import("test_runner_union.zig");

const Input = struct { path: []const u8, digest: ?[32]u8 };
const Location = struct { path: []const u8, root: []const u8, name: []const u8, configuration: ?[]const u8, under: ?[]const u8 = null };
const Selection = struct {
    entries: []const []const u8,
    tested: []const []const u8,
    inputs: []const Input,
    discovered: []const []const u8,
    locations: []const Location = &.{},
    example_owners: ?[]const []const []const u8 = null,
    test_owners: ?[]const ?[]const []const u8 = null,
};
const Orphan = struct { path: []const u8, closure: []const []const u8 };
const Outcome = root_share.Outcome;
const Fanout = struct { compiler: []const u8, directory: []const u8, controls: options.Options, jobs: usize, ticket: []const u8, run_root: root_share.RunRoot, identity: struct { guest: tool_identity.Identity, cache_plan: planner.Bound } };
const Discovery = struct { allocator: std.mem.Allocator, gpa: std.mem.Allocator, io: std.Io, diagnostics: ?*std.ArrayList(u8) = null };
const Snapshot = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    inputs: std.ArrayList(Input) = .empty,
    index: std.StringHashMapUnmanaged(usize) = .empty,
    locations: std.ArrayList(Location) = .empty,
    examples: std.ArrayList([]const u8) = .empty,
    /// The roots a directory run gave a directory as their import root (`place`), by path.
    placed: options.Placed = .empty,

    fn record(self: *Snapshot, path: []const u8, digest: ?[32]u8) error{ OutOfMemory, SourceChanged }!void {
        if (self.index.get(path)) |position| {
            if (!sameDigest(self.inputs.items[position].digest, digest)) return error.SourceChanged;
            return;
        }
        try self.inputs.append(self.allocator, .{ .path = path, .digest = digest });
        try self.index.put(self.allocator, path, self.inputs.items.len - 1);
    }

    fn content(self: *Snapshot, path: []const u8, bytes: []const u8) error{ OutOfMemory, SourceChanged }!void {
        const known = self.index.contains(path);
        var digest: [32]u8 = undefined;
        fast_blake3.hash(bytes, &digest);
        try self.record(path, digest);
        if (known or !product.isSource(path)) return;
        if (try language.docstring_example_source.contains(self.allocator, bytes)) try self.examples.append(self.allocator, path);
    }

    fn hasExamples(self: *const Snapshot, path: []const u8) bool {
        for (self.examples.items) |known| if (std.mem.eql(u8, known, path)) return true;
        return false;
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
    // The local files in the directory that a standard module hides are named once, as a single test entry names its own.
    if (!opts.json and !opts.build.show.codegen.local_stdlib) {
        var warned: std.ArrayList(u8) = .empty;
        try project_entry.appendShadowedStandardWarnings(try project_entry.shadowedIn(a, init.io, opts.path), a, &warned);
        if (warned.items.len != 0) try write(init.io, std.Io.File.stderr(), warned.items);
    }
    var diagnostics: std.ArrayList(u8) = .empty;
    const selection = programs(init, opts, &diagnostics) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        // The failure first, then the diagnostic that explains it (F-6).
        const headline = try std.fmt.allocPrint(a, "error: directory test discovery failed: {s}\n", .{@errorName(err)});
        try write(init.io, std.Io.File.stderr(), try std.mem.concat(a, u8, &.{ headline, diagnostics.items }));
        return 1;
    };
    if (selection.entries.len == 0) {
        try write(init.io, std.Io.File.stdout(), if (opts.json) try report.jsonSources(a, &.{}, &.{}) else try report.text(a, &.{}));
        try write(init.io, std.Io.File.stderr(), try emptyNote(a, init.io, opts));
        return 3;
    }
    const cache_plan = planner.bind(a, init.io, init.environ_map) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try write(init.io, std.Io.File.stderr(), try std.fmt.allocPrint(a, "error: cache-plan component: {s}\n", .{@errorName(err)}));
        return 2;
    };
    const compiler = std.Io.Dir.cwd().realPathFileAlloc(init.io, "/proc/self/exe", a) catch return error.ReadFailed;
    var nonce: [16]u8 = undefined;
    std.Io.random(init.io, &nonce);
    const directory = try std.fmt.allocPrint(a, "{s}/tests/directory-{s}", .{ opts.build.cache, std.fmt.bytesToHex(nonce, .lower) });
    std.Io.Dir.cwd().createDirPath(init.io, directory) catch return error.WriteFailed;
    defer retire(init.io, directory);
    const request: tool_identity.Request = .{ .arena = a, .io = init.io, .environment = init.environ_map, .executable = opts.build.zig, .cache = opts.build.cache };
    const guest = tool_identity.captureReplayParent(request) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try write(init.io, std.Io.File.stderr(), try std.fmt.allocPrint(a, "error: cannot identify guest toolchain: {s}\n{s}", .{ @errorName(err), zig_lookup.hintFor(err) }));
        return 1;
    };
    const ticket = try std.fs.path.join(a, &.{ directory, "tool-ticket.json" });
    const encoded = tool_ticket.encode(.{ .tool = request, .compiler_identity = frontend.compiler_identity, .component_identity = cache_plan.identity }, guest) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.ReadFailed;
    };
    std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = ticket, .data = encoded }) catch return error.WriteFailed;
    var controls = opts;
    controls.build.zig = guest.path;
    var placed: options.Placed = .empty;
    for (selection.locations) |location| if (location.under) |import_root| try placed.put(a, location.path, import_root);
    controls.controls.scope.placed = &placed;
    const free = budget.available(init.io);
    const workers = options.width(opts.controls, init.environ_map, selection.entries.len, free);
    const overall = options.width(opts.controls, init.environ_map, std.math.maxInt(usize), free);
    const fanout: Fanout = .{ .compiler = compiler, .directory = directory, .controls = controls, .jobs = overall, .ticket = ticket, .run_root = run_root, .identity = .{ .guest = guest, .cache_plan = cache_plan } };
    const outcomes = try a.alloc(Outcome, selection.entries.len);
    const plans = try a.alloc(together.Plan, selection.entries.len);
    @memset(plans, .child);
    const planning: together.Context = .{ .init = init, .controls = controls, .guest = guest, .cache_plan = cache_plan, .run_root = run_root, .workers = workers, .test_owners = selection.test_owners };
    var checks: together.Checks = if (selection.example_owners != null) .{} else try together.plan(planning, selection.entries, outcomes, plans);
    defer checks.deinit();
    var order: std.ArrayList(usize) = .empty;
    for (try largestFirst(a, init.io, selection.entries)) |index| if (plans[index] != .replayed) try order.append(a, index);
    const roots: Roots = .{ .paths = selection.entries, .order = order.items, .outcomes = outcomes, .plans = plans, .example_owners = selection.example_owners, .test_owners = selection.test_owners };
    // Roots run in this process share one budget of test processes with the children.
    var permits: root_share.Permits = .init(overall);
    var sharing = selection.example_owners != null;
    for (plans) |item| sharing = sharing or item == .together;
    try pool(init, fanout, .{ .roots = roots, .workers = workers, .permits = if (sharing) &permits else null });
    const unchanged = tool_identity.unchanged(request, guest) catch |err| unchanged: {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        break :unchanged false;
    };
    cache_plan.validate(a) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try write(init.io, std.Io.File.stderr(), try std.fmt.allocPrint(a, "error: cache-plan component: {s}\n", .{@errorName(err)}));
        return 2;
    };
    return summarize(init, opts, selection, outcomes, unchanged);
}

fn programs(init: std.process.Init, opts: options.Options, diagnostics: *std.ArrayList(u8)) !Selection {
    const a = init.arena.allocator();
    const found = try inventory(a, init.io, opts, diagnostics, null);
    const named = try std.Io.Dir.cwd().realPathFileAlloc(init.io, opts.path, a);
    var roots: std.ArrayList([]const u8) = .empty;
    var tested: std.ArrayList([]const u8) = .empty;
    var libraries: std.ArrayList([]const u8) = .empty;
    var snapshot: Snapshot = .{ .allocator = a, .io = init.io };
    defer snapshot.index.deinit(a);
    for (found) |path| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 << 20));
        try snapshot.content(path, bytes);
        const has_examples = snapshot.hasExamples(path);
        const tests = declaresTests(bytes) or has_examples;
        if (tests) try tested.append(a, path);
        if (language.project_config.declaresMain(bytes) or product.isTestSource(path)) {
            try roots.append(a, path);
        } else if (tests) try libraries.append(a, path);
    }
    var reached: std.StringHashMapUnmanaged(void) = .empty;
    defer reached.deinit(a);
    try place(init, named, &.{ roots.items, libraries.items }, &snapshot);
    const shares = try sharedClosures(init, roots.items, &snapshot);
    // Each root's import closure, which decides the modules whose tests it owns (`testOwners`).
    var closures: std.StringHashMapUnmanaged([]const []const u8) = .empty;
    for (roots.items, shares) |path, share| {
        const loaded_paths = try closure(init, path, .{ .diagnostics = diagnostics, .snapshot = &snapshot, .filter = opts.filter, .share = share });
        try closures.put(a, path, loaded_paths);
        for (loaded_paths) |loaded| try reached.put(a, loaded, {});
    }
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
        if (!imported) {
            try roots.append(a, orphan.path);
            try closures.put(a, orphan.path, orphan.closure);
        }
    }
    if (roots.items.len > 4096) return error.TooManyTestPrograms;
    std.mem.sort([]const u8, roots.items, {}, before);
    const owners = try exampleOwners(init, roots.items, .{ .snapshot = &snapshot, .diagnostics = diagnostics, .named = named });
    const test_owners = try testOwners(init, roots.items, .{ .closures = &closures, .tested = tested.items, .placed = &snapshot.placed }, diagnostics);
    return .{ .entries = roots.items, .tested = tested.items, .inputs = snapshot.inputs.items, .discovered = found, .locations = snapshot.locations.items, .example_owners = owners, .test_owners = test_owners };
}

/// What `testOwners` reads: each root's import closure and the sources that declare tests.
const Claims = struct { closures: *const std.StringHashMapUnmanaged([]const []const u8), tested: []const []const u8, placed: *const options.Placed };

/// For each root in `roots` order (sorted by path), the modules of its closure whose tests an earlier root runs, as paths
/// relative to the root's project root, or null when there are none (D-TL2-3 of experiments/test-loop-20261109/DECISIONS.md,
/// the user's D1): a source that declares tests belongs to the first root whose import closure holds it, so its tests run
/// once in the run and are listed once. A root is told only what to leave out, so a test no root claimed is never dropped.
fn testOwners(init: std.process.Init, roots: []const []const u8, claims: Claims, diagnostics: *std.ArrayList(u8)) !?[]const ?[]const []const u8 {
    // One root owns everything it reaches: nothing to leave out, and nothing to compute.
    if (roots.len < 2) return null;
    const a = init.arena.allocator();
    var declaring: std.StringHashMapUnmanaged(void) = .empty;
    for (claims.tested) |path| try declaring.put(a, path, {});
    var claimed: std.StringHashMapUnmanaged(void) = .empty;
    const result = try a.alloc(?[]const []const u8, roots.len);
    for (roots, result) |root, *skipped| {
        var paths: std.ArrayList([]const u8) = .empty;
        var located: ?project_entry.Entry = null;
        for (claims.closures.get(root) orelse &.{}) |path| {
            if (!declaring.contains(path)) continue;
            const slot = try claimed.getOrPut(a, path);
            if (!slot.found_existing) continue;
            if (located == null) located = try project_entry.resolveUnder(a, init.io, root, claims.placed.get(root), diagnostics);
            try paths.append(a, try rootRelative(a, located.?.root, path));
        }
        skipped.* = if (paths.items.len == 0) null else paths.items;
    }
    return result;
}

/// `path` relative to `root`. A closure's paths are the root joined with each module's path, so the prefix is cut without
/// resolving either (resolving both for every module of a large closure cost a percent of an unchanged run); any other
/// path is resolved.
fn rootRelative(a: std.mem.Allocator, root: []const u8, path: []const u8) error{OutOfMemory}![]const u8 {
    const plain = root.len != 0 and root[root.len - 1] != '/' and std.mem.indexOf(u8, path, "/./") == null and std.mem.indexOf(u8, path, "/../") == null;
    if (plain and path.len > root.len + 1 and std.mem.startsWith(u8, path, root) and path[root.len] == '/') return path[root.len + 1 ..];
    return std.fs.path.relative(a, root, null, root, path);
}

/// What `exampleOwners` reads and reports to: the run's snapshot, its diagnostics, and the folder the command line named.
const Owning = struct { snapshot: *Snapshot, diagnostics: *std.ArrayList(u8), named: []const u8 };

fn exampleOwners(init: std.process.Init, roots: []const []const u8, owning: Owning) !?[]const []const []const u8 {
    const snapshot = owning.snapshot;
    const diagnostics = owning.diagnostics;
    if (snapshot.examples.items.len == 0) return null;
    const a = init.arena.allocator();
    const result = try a.alloc([]const []const u8, roots.len);
    var claimed: std.StringHashMapUnmanaged(void) = .empty;
    for (roots, result) |root, *owned| {
        var paths: std.ArrayList([]const u8) = .empty;
        const loaded = try closure(init, root, .{ .diagnostics = diagnostics, .snapshot = snapshot, .filter = "" });
        const located = try project_entry.resolveUnder(a, init.io, root, snapshot.placed.get(root), diagnostics);
        const project_root = if (located.configuration) |config| std.fs.path.dirname(config.path).? else located.root;
        const exclusions = if (located.configuration) |config| config.releaseOptions().exclude else &.{};
        const named = try std.fs.path.relative(a, project_root, null, project_root, owning.named);
        for (loaded) |path| {
            if (!snapshot.hasExamples(path) or claimed.contains(path)) continue;
            if (language.release_project.excludedBeneath(try std.fs.path.relative(a, project_root, null, project_root, path), named, exclusions)) continue;
            try claimed.put(a, path, {});
            try paths.append(a, try rootRelative(a, located.root, path));
        }
        owned.* = paths.items;
    }
    return result;
}

/// The `.selka` files a directory run walks, sorted. A `selka.json` of the directory's project that cannot be read is printed into
/// `diagnostics` (when given) with its file, line and reason, as one under a folder of the run is. The folder `opts.path` names is walked whatever it is called (`release_project.excludedBeneath`);
/// the folders beneath it that the walk leaves out are appended to `left` (absolute paths) when it is given.
fn inventory(a: std.mem.Allocator, io: std.Io, opts: options.Options, diagnostics: ?*std.ArrayList(u8), left: ?*std.ArrayList([]const u8)) ![]const []const u8 {
    const root = try std.Io.Dir.cwd().realPathFileAlloc(io, opts.path, a);
    const config_path = try language.project_config.discover(a, io, try std.fs.path.join(a, &.{ root, language.project_config.config_name }));
    var failure: language.project_config.Failure = .{};
    var configuration: ?language.project_config.Config = if (config_path) |path| language.project_config.load(a, io, path, &failure) catch |err| {
        if (err == error.OutOfMemory) return err;
        if (diagnostics) |sink| try sink.print(a, "{s}:{d}:{d}: error[E_PROJECT_CONFIG]: {s}\n", .{ failure.path, failure.location.line, failure.location.column, failure.detail });
        return err;
    } else null;
    defer if (configuration) |*config| config.deinit();
    const exclusions = if (configuration) |*config| config.releaseOptions().exclude else &.{};
    const project_root = if (config_path) |path| std.fs.path.dirname(path).? else root;
    const working = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", a);
    const cache = std.Io.Dir.cwd().realPathFileAlloc(io, opts.build.cache, a) catch try std.fs.path.resolve(a, &.{ working, opts.build.cache });
    // The folders left out are the ones `selka packages` leaves out of its walk too (`release_project.walkSkips`).
    const walk: language.release_project.Walk = .{ .project_root = project_root, .exclusions = exclusions, .cache = cache, .working = working, .named = root };
    var directory = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true, .follow_symlinks = false });
    defer directory.close(io);
    var walker = try directory.walk(a);
    defer walker.deinit();
    var found: std.ArrayList([]const u8) = .empty;
    while (try walker.next(io)) |item| {
        const absolute = try std.fs.path.join(a, &.{ root, item.path });
        if (try language.release_project.walkSkips(a, walk, item.basename, absolute)) {
            if (item.kind == .directory) {
                walker.leave(io);
                if (left) |list| if (!std.mem.eql(u8, absolute, cache)) try list.append(a, absolute);
            }
            continue;
        }
        if (item.kind == .file and product.isSource(item.path)) try found.append(a, try std.fs.path.join(a, &.{ root, item.path }));
    }
    std.mem.sort([]const u8, found.items, {}, before);
    return found.items;
}

/// A folder the run left alone that holds `.selka` sources: how it is shown, and why it was left.
const Mention = struct { path: []const u8, why: []const u8 };

/// Why a walk leaves out the folder called `name`: `generatedName` by its name, else the project's `release.exclude`.
fn leftBecause(name: []const u8) []const u8 {
    if (std.mem.startsWith(u8, name, ".")) return "as a hidden folder";
    if (std.mem.eql(u8, name, "node_modules")) return "as a dependency folder";
    if (language.release_project.generatedName(name)) return "as a build-output folder";
    return "because `release.exclude` lists it";
}

/// Whether a `.selka` source lies anywhere beneath the folder `path` (absolute).
fn holdsSource(io: std.Io, a: std.mem.Allocator, path: []const u8) bool {
    var directory = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true, .follow_symlinks = false }) catch return false;
    defer directory.close(io);
    var walker = directory.walk(a) catch return false;
    defer walker.deinit();
    while (walker.next(io) catch return false) |item| {
        if (item.kind == .file and product.isSource(item.basename)) return true;
    }
    return false;
}

/// The one line a directory run ends with on standard error when it found no program to run: what `under` held, and which folders
/// (`mentions`, at most five are named) it left alone, with the reason and the way to include one. A run that names the folder walks it
/// whatever it is called, so the line says to name it.
fn emptyLine(a: std.mem.Allocator, under: []const u8, mentions: []const Mention) std.mem.Allocator.Error![]const u8 {
    var line: std.ArrayList(u8) = .empty;
    try line.print(a, "note: no tests found under `{s}`", .{under});
    for (mentions[0..@min(mentions.len, 5)], 0..) |item, index| {
        try line.appendSlice(a, if (index == 0) ": " else ", ");
        try line.print(a, "`{s}`{s}{s}", .{ item.path, if (index == 0) " is left alone " else " ", item.why });
    }
    if (mentions.len > 5) try line.print(a, ", and {d} more", .{mentions.len - 5});
    if (mentions.len != 0) try line.appendSlice(a, if (mentions.len == 1) "; name it to include it" else "; name one to include it");
    try line.append(a, '\n');
    return line.items;
}

/// `emptyLine` for the run `opts` describes: the folders beneath the named one that the walk leaves out and that hold `.selka` sources.
/// A folder that cannot be walked again names none: the line then says only that nothing was found.
fn emptyNote(a: std.mem.Allocator, io: std.Io, opts: options.Options) error{OutOfMemory}![]const u8 {
    const base = std.mem.trimEnd(u8, opts.path, "/");
    const root = std.Io.Dir.cwd().realPathFileAlloc(io, opts.path, a) catch return emptyLine(a, if (base.len == 0) "." else base, &.{});
    var left: std.ArrayList([]const u8) = .empty;
    _ = inventory(a, io, opts, null, &left) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return emptyLine(a, if (base.len == 0) "." else base, &.{});
    };
    var mentions: std.ArrayList(Mention) = .empty;
    for (left.items) |folder| {
        if (!holdsSource(io, a, folder)) continue;
        const inside = if (folder.len > root.len + 1) folder[root.len + 1 ..] else std.fs.path.basename(folder);
        const shown = if (base.len == 0 or std.mem.eql(u8, base, ".")) try std.fmt.allocPrint(a, "{s}/", .{inside}) else try std.fmt.allocPrint(a, "{s}/{s}/", .{ base, inside });
        try mentions.append(a, .{ .path = shown, .why = leftBecause(std.fs.path.basename(folder)) });
    }
    return emptyLine(a, if (base.len == 0) "." else base, mentions.items);
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
    const located = try project_entry.resolveUnder(a, init.io, path, snapshot.placed.get(path), diagnostics);
    try snapshot.locations.append(a, .{ .path = located.path, .root = located.root, .name = located.name, .configuration = if (located.configuration) |file| file.path else null, .under = snapshot.placed.get(path) });
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
    const resources: Discovery = .{ .allocator = a, .gpa = init.gpa, .io = init.io, .diagnostics = diagnostics };
    const mark = diagnostics.items.len;
    // A root that cannot be loaded does not end the discovery: it stays a root with only itself in its closure, and the run
    // reports it as failed, with its own diagnostic, beside the roots that did load.
    const paths = reading.share orelse loadedClosure(resources, located, &.{}, snapshot) catch |err| {
        if (err == error.OutOfMemory) return err;
        diagnostics.shrinkRetainingCapacity(mark);
        return a.dupe([]const u8, &.{located.path});
    };
    for (try case_settings.providerSets(a, cases, filter)) |providers| _ = try loadedClosure(resources, located, providers, snapshot);
    return paths;
}

/// The import closures of the headerless source roots of `roots`, obtained
/// for each project from one entry importing all of them, with each
/// module read once (NEW-CORE-TEST-UNION-1); null for every other root, and for
/// every root of a project whose shared load fails, which load alone.
fn sharedClosures(init: std.process.Init, roots: []const []const u8, snapshot: *Snapshot) ![]const ?[]const []const u8 {
    const a = init.arena.allocator();
    const found = try a.alloc(?[]const []const u8, roots.len);
    @memset(found, null);
    const entries = try a.alloc(?project_entry.Entry, roots.len);
    for (roots, entries) |path, *entry| entry.* = try headedEntry(init, path, snapshot.placed.get(path));
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
fn headedEntry(init: std.process.Init, path: []const u8, under: ?[]const u8) !?project_entry.Entry {
    const a = init.arena.allocator();
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 << 20)) catch return null;
    if (!together.headed(bytes)) return null;
    var problems: std.ArrayList(u8) = .empty;
    if (project_entry.resolveUnder(a, init.io, path, under, &problems)) |entry| return entry else |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    }
}

/// Decide which of `groups` (the roots and the libraries that declare tests) take `directory`, the folder the run was given,
/// as their import root, as `check DIR` takes it for every file beneath it. Only a file that no `selka.json` governs, whose
/// own folder is not `directory`, that cannot be loaded with its own root (`rows/more_test.selka` importing `rows`, which sits
/// in `directory`) and can be with `directory`. Every other file keeps the root it has had, so its tests keep their names and
/// every recorded result of a tree that ran before stays the one that run replays.
fn place(init: std.process.Init, directory: []const u8, groups: []const []const []const u8, snapshot: *Snapshot) !void {
    const a = init.arena.allocator();
    var problems: std.ArrayList(u8) = .empty;
    for (groups) |paths| for (paths) |path| {
        const own = project_entry.resolve(a, init.io, path, &problems) catch |err| {
            if (err == error.OutOfMemory) return err;
            continue;
        };
        if (own.configuration != null or std.mem.eql(u8, own.root, directory)) continue;
        const under = project_entry.resolveUnder(a, init.io, path, directory, &problems) catch |err| {
            if (err == error.OutOfMemory) return err;
            continue;
        };
        if (std.mem.eql(u8, under.root, own.root) or try loads(init, own, snapshot) or !try loads(init, under, snapshot)) continue;
        try snapshot.placed.put(a, path, directory);
    };
}

/// Whether `entry`'s import graph loads: every module it imports is found and parses.
fn loads(init: std.process.Init, entry: project_entry.Entry, snapshot: *Snapshot) !bool {
    const resources: Discovery = .{ .allocator = init.arena.allocator(), .gpa = init.gpa, .io = init.io };
    _ = loadedClosure(resources, entry, &.{}, snapshot) catch |err| {
        if (err == error.OutOfMemory) return err;
        return false;
    };
    return true;
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
    const providers = [_]frontend.Provider{.{ .path = together.entry_name ++ product.source_suffix, .text = try together.entryText(a, names) }};
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
        try snapshot.disk(try std.fmt.allocPrint(a, "{s}.api", .{product.chopSource(path)}));
    };
    return path;
}

fn loadedClosure(resources: Discovery, located: project_entry.Entry, providers: []const frontend.Provider, snapshot: *Snapshot) ![]const []const u8 {
    const a = resources.allocator;
    var session = frontend.Session.init(resources.gpa, resources.io, located.root);
    defer session.deinit();
    located.configure(&session);
    var overlay: Overlay = .{ .files = &session.files, .providers = providers };
    // A root that cannot be loaded prints its own diagnostic under the discovery failure (F-6).
    session.project.load(overlay.provider(), located.name, located.limits()) catch |err| {
        if (resources.diagnostics) |printed| return session.loadFailure(a, err, printed);
        return err;
    };
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

/// What a root owns in a directory run: the modules whose docstring examples it runs (null: every one), and the modules whose
/// tests another root runs (null: none, so it runs every test its closure declares).
const Owned = struct { examples: ?[]const []const u8 = null, skipped: ?[]const []const u8 = null };

/// The roots of one directory run, the order they start in, where their reports go,
/// and how each runs.
const Roots = struct { paths: []const []const u8, order: []const usize, outcomes: []Outcome, plans: []const together.Plan, example_owners: ?[]const []const []const u8 = null, test_owners: ?[]const ?[]const []const u8 = null };
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
    var environment = try childEnvironment(init, fanout.controls.build.show);
    defer environment.deinit();
    try environment.put(tool_ticket.hint, "1");
    if (fanout.controls.shared_cache) |directory| if (directory.len == 0)
        try environment.put(options.shared_cache_variable, "");
    var shared = queue;
    const threads = try a.alloc(std.Thread, @max(1, shared.workers) - 1);
    // Each worker allocates from an arena of its own. The directory run's arena was shared by every worker (outcome
    // copies, child argv), and the pinned arena's in-place growth is not safe against another thread allocating from
    // the same arena (lane U, 2026-10-28). The worker arenas take their nodes from `init`'s arena, which the workers do
    // not allocate from while they run, and they are never freed: outcome bytes outlive the workers.
    const arenas = try a.alloc(std.heap.ArenaAllocator, threads.len + 1);
    const workers = try a.alloc(Worker, threads.len + 1);
    for (arenas, workers) |*arena, *worker| {
        arena.* = std.heap.ArenaAllocator.init(a);
        var worker_init = init;
        worker_init.arena = arena;
        worker.* = .{ .init = worker_init, .fanout = fanout, .environment = &environment, .queue = &shared };
    }
    var started: usize = 0;
    for (threads, workers[1..]) |*thread, *worker| {
        thread.* = std.Thread.spawn(.{}, Worker.run, .{worker.*}) catch break;
        started += 1;
    }
    workers[0].run();
    for (threads[0..started]) |thread| thread.join();
    if (shared.failure) |err| return err;
}

fn childEnvironment(init: std.process.Init, policy: @import("pipeline.zig").Show) error{OutOfMemory}!std.process.Environ.Map {
    var environment = try init.environ_map.clone(init.arena.allocator());
    if (policy.compiler_cache_disabled or policy.verify_cache) {
        const name = language.shared_artifact_store.environment_variable;
        if (init.minimal.environ.getPosix(name)) |original| {
            try environment.put(name, original);
        } else _ = environment.swapRemove(name);
    }
    return environment;
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
            const skipped = if (roots.test_owners) |owners| owners[index] else null;
            const outcome = if (roots.example_owners) |owners| self.inProcess(roots.paths[index], null, .{ .examples = owners[index], .skipped = skipped }) else switch (roots.plans[index]) {
                .together => |view| self.inProcess(roots.paths[index], view, .{ .skipped = skipped }),
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
    fn inProcess(self: Worker, path: []const u8, view: ?root_share.View, owned: Owned) Error!Outcome {
        const example_modules = owned.examples;
        var arena = std.heap.ArenaAllocator.init(self.init.gpa);
        defer arena.deinit();
        var init = self.init;
        init.arena = &arena;
        var controls = self.fanout.controls;
        controls.path = path;
        controls.controls.jobs = self.fanout.jobs;
        controls.controls.scope.skipped = owned.skipped;
        const directed: root_share.Directed = .{
            .guest = self.fanout.identity.guest,
            .cache_plan = self.fanout.identity.cache_plan,
            .view = view,
            .permits = self.queue.permits,
            .example_modules = example_modules,
        };
        const outcome = try self.fanout.run_root(init, controls, directed) orelse return .{};
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
        var arguments = try argv(a, fanout, path);
        // The child leaves its count of printed diagnostics and the warnings it withheld here instead of closing with a `selka fix` line
        // and a `warnings:` line: this run prints one of each.
        const fixes = try std.fmt.allocPrint(a, "{s}/{d}.fixes", .{ self.fanout.directory, slot });
        arguments = try std.mem.concat(a, []const u8, &.{ arguments, &.{ language.warning_display.count_option, fixes } });
        // The packages of a build through `selka packages`, whose warnings the child counts and leaves to this run too.
        if (language.warning_display.packageNames()) |names| arguments = try std.mem.concat(a, []const u8, &.{ arguments, &.{ language.warning_display.packages_option, names } });
        // The directory a root takes as its import root when its own folder cannot serve its imports.
        if (fanout.controls.controls.scope.importRoot(path)) |directory| arguments = try std.mem.concat(a, []const u8, &.{ arguments, &.{ "--import-root", directory } });
        // The modules whose tests another root runs, one path a line (D-TL2-3).
        if (self.queue.roots.test_owners) |owners| if (owners[slot]) |skipped| {
            const list = try std.fmt.allocPrint(a, "{s}/{d}.skipped", .{ self.fanout.directory, slot });
            const text = try std.mem.join(a, "\n", skipped);
            std.Io.Dir.cwd().writeFile(self.init.io, .{ .sub_path = list, .data = text }) catch return error.WriteFailed;
            arguments = try std.mem.concat(a, []const u8, &.{ arguments, &.{ "--skip-test-modules", list } });
        };
        const launch: @import("process_spawn.zig").Options = .{ .argv = arguments, .environment = .{ .map = self.environment }, .stdin = .{ .file = input }, .stdout = .{ .file = output }, .die_with_parent = true };
        var process = @import("process_spawn.zig").spawn(self.init.gpa, launch) catch return error.WriteFailed;
        const term = process.wait(self.init.io) catch {
            process.kill(self.init.io);
            return error.ReadFailed;
        };
        const handed = std.Io.Dir.cwd().readFileAlloc(self.init.io, fixes, a, .limited(64 << 20)) catch "";
        language.warning_display.absorb(self.init.io, handed);
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

/// The option that makes a child `selka test` build in `mode`; null for the -O0 optimized debug build, which every `selka test` starts from.
fn modeArgument(mode: build_mode.Mode) ?[]const u8 {
    return switch (mode) {
        .optimized_debug => null,
        .lean_debug => "--debug-lean",
        .optimized_o2 => "--optimize-debug",
        .debug => "--unoptimized",
        .release => "--release",
    };
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
    if (ceilings.threads) |count| try arguments.appendSlice(a, &.{ "--threads", try std.fmt.allocPrint(a, "{d}", .{count}) });
    try arguments.appendSlice(a, &.{ "--property-runs", try std.fmt.allocPrint(a, "{d}", .{opts.properties.runs}) });
    try arguments.appendSlice(a, &.{ "--property-policy", opts.properties.policy.name() });
    if (opts.shared_cache) |directory| if (directory.len != 0)
        try arguments.appendSlice(a, &.{ "--shared-cache-dir", directory });
    if (modeArgument(opts.build.mode)) |flag| try arguments.append(a, flag);
    if (opts.build.facts == .verify) try arguments.append(a, "--verify-facts");
    if (opts.build.facts == .verify_written) try arguments.append(a, "--verify-written-copies");
    if (opts.build.facts == .off) try arguments.append(a, "--no-facts");
    if (opts.build.show.codegen.target.cpuModel() != .native) try arguments.appendSlice(a, &.{ "--cpu", opts.build.show.codegen.target.cpuModel().spelling() });
    if (opts.controls.force) try arguments.append(a, "--force");
    if (opts.build.show.compiler_cache_disabled or opts.build.show.verify_cache) try arguments.append(a, "--no-cache");
    if (opts.controls.scope.against) |reference| try arguments.appendSlice(a, &.{ "--affected", "--against", reference });
    if (opts.properties.seed) |seed| try arguments.appendSlice(a, &.{ "--seed", try std.fmt.allocPrint(a, "{d}", .{seed}) });
    for (opts.build.links) |link| try arguments.appendSlice(a, &.{ "--link", link });
    for (opts.build.show.codegen.device.include) |folder| try arguments.appendSlice(a, &.{ "--include", folder });
    if (opts.controls.scope.allow_host) try arguments.append(a, "--allow-host");
    // A child root builds its own programs: without this its certificates (`--emit-certificates DIR`) are never written.
    if (opts.build.show.certificates) |directory| try arguments.appendSlice(a, &.{ "--emit-certificates", directory });
    return arguments.items;
}

// spec-case: COMPILER-SHARED-CACHE-1
test "directory compiler suppression forwards policy while retaining the original guest environment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = [_:null]?[*:0]const u8{"SELKA_COMPILER_SHARED_CACHE=guest-visible-cache"};
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    try environment.put(language.shared_artifact_store.environment_variable, "");
    const init: std.process.Init = .{
        .minimal = .{ .environ = .{ .block = .{ .slice = &original } }, .args = .{ .vector = &.{} } },
        .arena = &arena,
        .gpa = std.testing.allocator,
        .io = std.testing.io,
        .environ_map = &environment,
        .preopens = .empty,
    };
    var child = try childEnvironment(init, .{ .compiler_cache_disabled = true });
    defer child.deinit();
    try std.testing.expectEqualStrings("guest-visible-cache", child.get(language.shared_artifact_store.environment_variable).?);
    try std.testing.expectEqualStrings("", environment.get(language.shared_artifact_store.environment_variable).?);
    const fanout: Fanout = .{
        .compiler = "selka",
        .directory = "unused",
        .controls = .{ .path = "suite", .build = .{ .zig = "zig", .show = .{ .compiler_cache_disabled = true } } },
        .jobs = 1,
        .ticket = "unused",
        .run_root = undefined,
        .identity = undefined,
    };
    const arguments = try std.mem.join(a, "\n", try argv(a, fanout, "suite/main.selka"));
    try std.testing.expect(std.mem.indexOf(u8, arguments, "--no-cache") != null);
    const compiled = try @import("compiler_sharing.zig").prepare(init, true);
    try std.testing.expectEqualStrings("guest-visible-cache", compiled.minimal.environ.getPosix(language.shared_artifact_store.environment_variable).?);
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "shared test cache directory arguments retain separate private cache and omit disabled sharing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fanout: Fanout = .{
        .compiler = "selka",
        .directory = "unused",
        .controls = .{ .path = "suite", .build = .{ .zig = "zig", .cache = "/private-store" }, .shared_cache = "/shared-store" },
        .jobs = 2,
        .ticket = "unused",
        .run_root = undefined,
        .identity = undefined,
    };
    const forwarded = try std.mem.join(a, "\n", try argv(a, fanout, "suite/main.selka"));
    try std.testing.expect(std.mem.indexOf(u8, forwarded, "--shared-cache-dir\n/shared-store") != null);
    try std.testing.expect(std.mem.indexOf(u8, forwarded, "--cache-dir\n/private-store\n") != null);
    fanout.controls.shared_cache = "";
    const disabled = try std.mem.join(a, "\n", try argv(a, fanout, "suite/main.selka"));
    try std.testing.expect(std.mem.indexOf(u8, disabled, "--shared-cache-dir") == null);
}

test "a directory run's child roots are asked for the CPU model the run was, and for none when it was native" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fanout: Fanout = .{
        .compiler = "selka",
        .directory = "unused",
        .controls = .{ .path = "suite", .build = .{ .zig = "zig" } },
        .jobs = 1,
        .ticket = "unused",
        .run_root = undefined,
        .identity = undefined,
    };
    const native = try std.mem.join(a, "\n", try argv(a, fanout, "suite/main.selka"));
    try std.testing.expect(std.mem.indexOf(u8, native, "--cpu") == null);
    fanout.controls.build.show.codegen.target = fanout.controls.build.show.codegen.target.forCpu(.x86_64_v3).?;
    const floor = try std.mem.join(a, "\n", try argv(a, fanout, "suite/main.selka"));
    try std.testing.expect(std.mem.indexOf(u8, floor, "--cpu\nx86-64-v3") != null);
}

/// Expect a child of a directory run in `mode` to be asked for `flag`, and for no other build mode.
fn expectModeForwarded(a: std.mem.Allocator, mode: build_mode.Mode, flag: ?[]const u8) !void {
    const fanout: Fanout = .{
        .compiler = "selka",
        .directory = "unused",
        .controls = .{ .path = "suite", .build = .{ .zig = "zig", .mode = mode } },
        .jobs = 1,
        .ticket = "unused",
        .run_root = undefined,
        .identity = undefined,
    };
    const arguments = try argv(a, fanout, "suite/main.selka");
    var found: usize = 0;
    for (arguments) |argument| {
        for ([_][]const u8{ "--release", "--unoptimized", "--optimize-debug", "--debug-lean", "--debug-o0" }) |option| {
            if (std.mem.eql(u8, argument, option)) {
                found += 1;
                try std.testing.expectEqualStrings(flag orelse "", option);
            }
        }
    }
    try std.testing.expectEqual(@as(usize, if (flag == null) 0 else 1), found);
}

// spec-case: DEBUG-OPTIMIZE-1
test "a directory run forwards every build mode to its children, and none for the -O0 default" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectModeForwarded(a, .optimized_debug, null);
    try expectModeForwarded(a, .lean_debug, "--debug-lean");
    try expectModeForwarded(a, .optimized_o2, "--optimize-debug");
    try expectModeForwarded(a, .debug, "--unoptimized");
    try expectModeForwarded(a, .release, "--release");
}

// spec-case: OWNERSHIP-PROOF-1
test "a directory run forwards the certificate directory to each child root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fanout: Fanout = .{
        .compiler = "selka",
        .directory = "unused",
        .controls = .{ .path = "suite", .build = .{ .zig = "zig" } },
        .jobs = 1,
        .ticket = "unused",
        .run_root = undefined,
        .identity = undefined,
    };
    const without = try std.mem.join(a, "\n", try argv(a, fanout, "suite/main.selka"));
    try std.testing.expect(std.mem.indexOf(u8, without, "--emit-certificates") == null);
    fanout.controls.build.show.certificates = "out/certificates";
    const forwarded = try std.mem.join(a, "\n", try argv(a, fanout, "suite/main.selka"));
    try std.testing.expect(std.mem.endsWith(u8, forwarded, "--emit-certificates\nout/certificates"));
}

fn summarize(init: std.process.Init, opts: options.Options, selection: Selection, outcomes: []const Outcome, tool_unchanged: bool) Error!u8 {
    const a = init.arena.allocator();
    var verdicts: std.ArrayList(report.Verdict) = .empty;
    var accounted: std.StringHashMapUnmanaged(void) = .empty;
    defer accounted.deinit(a);
    // Entries whose program already has a failed verdict for its own file: the final
    // "not loaded by any test program" sweep must not say the same file failed again.
    var failed_entries: std.StringHashMapUnmanaged(void) = .empty;
    defer failed_entries.deinit(a);
    // A program that failed to set up (status 2: an invalid cases file or provider
    // fixture, an unreadable entry) makes the whole run status 2, as in the old core.
    var setup_failed = false;
    // The entries that failed to check or build and that no `selka.json` governs: their import root is a guess (`importRootNote`).
    var ungoverned: usize = 0;
    for (selection.entries, outcomes) |path, outcome| {
        const first_verdict = verdicts.items.len;
        setup_failed = setup_failed or outcome.code == 2;
        const parsed = std.json.parseFromSlice(std.json.Value, a, outcome.bytes, .{ .allocate = .alloc_always }) catch {
            try verdicts.append(a, .{ .name = path, .status = .failed, .reason = noReportReason(outcome.code) });
            try failed_entries.put(a, path, {});
            if (outcome.code == 1 and !governed(selection.locations, path)) ungoverned += 1;
            continue;
        };
        const value = parsed.value;
        if (value != .object or !std.mem.eql(u8, string(value, "version"), "native-tests-v1")) {
            try verdicts.append(a, .{ .name = path, .status = .failed, .reason = "invalid test report version" });
            try failed_entries.put(a, path, {});
            continue;
        }
        const tests = value.object.get("tests") orelse .null;
        const sources = value.object.get("sources") orelse .null;
        if (tests != .array or sources != .array) {
            try verdicts.append(a, .{ .name = path, .status = .failed, .reason = "incomplete test report" });
            try failed_entries.put(a, path, {});
            continue;
        }
        for (sources.array.items) |source| if (source == .string) {
            try accounted.put(a, source.string, {});
        };
        for (tests.array.items) |test_value| {
            const status = std.meta.stringToEnum(report.Status, string(test_value, "status")) orelse .failed;
            var item: report.Verdict = .{ .name = string(test_value, "name"), .status = status, .reason = string(test_value, "reason"), .at = string(test_value, "at") };
            item.details.counts = counts(test_value);
            carried(test_value, &item);
            if (!ownershipRule(test_value, &item)) {
                try verdicts.append(a, item);
                continue;
            }
            if (!try explanation(a, test_value, &item)) {
                try verdicts.append(a, item);
                continue;
            }
            if (test_value == .object) if (test_value.object.get("property")) |evidence| {
                const parsed_evidence = std.json.parseFromValueLeaky(@import("test_runner_property.zig").Evidence, a, evidence, .{}) catch {
                    item.status = .failed;
                    item.reason = "invalid property evidence in test report";
                    try verdicts.append(a, item);
                    continue;
                };
                item.details.property = parsed_evidence;
            };
            try verdicts.append(a, item);
        }
        if (outcome.code != report.exitStatus(verdicts.items[first_verdict..])) try verdicts.append(a, .{ .name = path, .status = .failed, .reason = "test program exit status disagrees with its report" });
    }
    if (!tool_unchanged) try verdicts.append(a, .{ .name = opts.path, .status = .failed, .reason = "SourceChanged: toolchain changed during directory execution" });
    if (try sourceChanged(a, init.io, opts, selection)) try verdicts.append(a, .{ .name = opts.path, .status = .failed, .reason = "SourceChanged: directory discovery inputs changed during execution" });
    for (selection.tested) |path| if (!accounted.contains(path) and !failed_entries.contains(path)) {
        try verdicts.append(a, .{ .name = path, .status = .failed, .reason = "test-declaring source was not loaded by any test program" });
    };
    var sources: std.ArrayList([]const u8) = .empty;
    var keys = accounted.keyIterator();
    while (keys.next()) |key| try sources.append(a, key.*);
    std.mem.sort([]const u8, sources.items, {}, before);
    const json = if (opts.json or language.profile_history.enabled()) try report.jsonSources(a, verdicts.items, sources.items) else "";
    if (language.profile_history.enabled()) language.profile_history.captureJson(json);
    // One work line per test that crossed the threshold, compared with the last run of
    // the same test in the same build mode (NEW-CORE-TEST-WORK-1). A `--json` run only
    // reports the counts; its children did the same, so nothing consumed the store.
    if (!opts.json) @import("test_runner_counts.zig").compare(a, init.io, opts.build.cache, @tagName(opts.build.mode), verdicts.items);
    try write(init.io, std.Io.File.stdout(), if (opts.json) json else try report.text(a, verdicts.items));
    if (ungoverned != 0 and !opts.json) try write(init.io, std.Io.File.stderr(), importRootNote(ungoverned));
    return if (setup_failed) 2 else report.exitStatus(verdicts.items);
}

/// Whether a `selka.json` governs the root at `path` (or the run has no record of the root, which it does not guess about).
fn governed(locations: []const Location, path: []const u8) bool {
    for (locations) |location| if (std.mem.eql(u8, location.path, path)) return location.configuration != null;
    return true;
}

/// What a directory run says last when `count` roots with no `selka.json` failed to check or build, whatever the diagnostic above
/// says: the two ways to give such a file its import root. A diagnostic that is not a missing module is not about the root.
fn importRootNote(count: usize) []const u8 {
    const ways = "put a `selka.json` of {\"version\": 1} in the folder the imports start from, or run again with `--import-root DIR` to name that folder.\n";
    return if (count == 1)
        "note: no `selka.json` governs the failed file above. If its diagnostic says a module cannot be found, " ++ ways
    else
        "note: no `selka.json` governs the failed files above. If a diagnostic says a module cannot be found, " ++ ways;
}

/// The rest of what a test's report says about it that a directory run must hand on as the root's own run printed it: the advice of
/// a test that returned false (FR19) and, for a test run against providers, what it was accepted under (NATIVE-TEST-5). A report
/// without them leaves the verdict as it was.
fn carried(value: std.json.Value, item: *report.Verdict) void {
    item.details.advice = string(value, "advice");
    if (value != .object) return;
    if (value.object.get("contract") == null or value.object.get("provider") == null or value.object.get("source") == null) return;
    item.identity = .{ .contract = string(value, "contract"), .provider = string(value, "provider"), .source = string(value, "source") };
}

/// The work a test report carries for one test (`steps` and `peak_bytes`), or null
/// when the test did not report it or the fields are not plain non-negative integers.
fn counts(value: std.json.Value) ?report.Counts {
    if (value != .object) return null;
    const steps = value.object.get("steps") orelse return null;
    const peak = value.object.get("peak_bytes") orelse return null;
    if (steps != .integer or peak != .integer or steps.integer < 0 or peak.integer < 0) return null;
    return .{ .steps = @intCast(steps.integer), .peak_bytes = @intCast(peak.integer) };
}

/// Why a test program's file has a failed verdict but no report. Exit status 1 with an empty
/// report is a program that never ran its tests: the compiler already printed why on stderr,
/// so the verdict names the file and says it failed to check or build, and the sweep for
/// unloaded sources does not repeat it.
fn noReportReason(code: u8) []const u8 {
    return switch (code) {
        2 => "test program failed to set up (status 2)",
        1 => "failed to check or build, so no tests ran (the diagnostic is printed above)",
        else => "test program produced no usable report",
    };
}

test "a directory run hands on a test's advice and the identity it was accepted under (FR19)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const advised = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"name\":\"m::test_chain\",\"status\":\"failed\",\"reason\":\"expected true, got false\",\"advice\":\"write one assert\",\"at\":\"\"}", .{});
    var item: report.Verdict = .{ .name = "m::test_chain", .status = .failed };
    carried(advised, &item);
    try std.testing.expectEqualStrings("write one assert", item.details.advice);
    try std.testing.expect(item.identity == null);
    const provided = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"name\":\"m::test_p\",\"status\":\"passed\",\"reason\":\"\",\"at\":\"\",\"contract\":\"c\",\"provider\":\"p\",\"source\":\"s\"}", .{});
    var accepted: report.Verdict = .{ .name = "m::test_p", .status = .passed };
    carried(provided, &accepted);
    try std.testing.expectEqualStrings("", accepted.details.advice);
    try std.testing.expectEqualStrings("p", accepted.identity.?.provider);
}

fn ownershipRule(value: std.json.Value, item: *report.Verdict) bool {
    if (value != .object) return true;
    const selected_rule = value.object.get("rule") orelse return true;
    const rules = @import("selka").ownership_rules;
    if (selected_rule == .string) if (std.meta.stringToEnum(rules.Rule, selected_rule.string)) |rule| {
        if (rules.valid(.{ .code = "E_CORE_UNSUPPORTED", .rule = rule })) {
            item.details.rule = rule;
            return true;
        }
    };
    item.status = .failed;
    item.reason = "invalid ownership rule in test report";
    return false;
}

test "ownership rule survives directory report decoding and invalid code rule pairs fail closed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const owned = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"rule\":\"Z3\"}", .{});
    var item: report.Verdict = .{ .name = "m::test_one", .status = .unsupported };
    try std.testing.expect(ownershipRule(owned, &item));
    try std.testing.expectEqual(@import("selka").ownership_rules.Rule.Z3, item.details.rule.?);
    const ordinary = try std.json.parseFromSliceLeaky(std.json.Value, a, "{}", .{});
    var plain: report.Verdict = .{ .name = "m::test_two", .status = .unsupported };
    try std.testing.expect(ownershipRule(ordinary, &plain));
    try std.testing.expect(plain.details.rule == null);
    const invalid = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"rule\":\"M3\"}", .{});
    try std.testing.expect(!ownershipRule(invalid, &plain));
    try std.testing.expectEqual(report.Status.failed, plain.status);
}

fn explanation(a: std.mem.Allocator, value: std.json.Value, item: *report.Verdict) Error!bool {
    if (value != .object) return true;
    if (value.object.get("cache")) |cache| {
        item.cache = std.json.parseFromValueLeaky(report.Cache, a, cache, .{}) catch {
            item.status = .failed;
            item.reason = "invalid cache explanation in test report";
            return false;
        };
    }
    if (value.object.get("contract") != null) item.identity = .{
        .contract = string(value, "contract"),
        .provider = string(value, "provider"),
        .source = string(value, "source"),
    };
    return true;
}

fn sourceChanged(a: std.mem.Allocator, io: std.Io, opts: options.Options, selection: Selection) Error!bool {
    const current = inventory(a, io, opts, null, null) catch |err| {
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
        const located = project_entry.resolveUnder(a, io, original.path, original.under, &diagnostics) catch |err| {
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
fn declaresTests(bytes: []const u8) bool {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.eql(u8, line, "@test")) return true;
        if (std.mem.startsWith(u8, line, "public ")) line = std.mem.trimStart(u8, line[7..], " \t");
        if (std.mem.startsWith(u8, line, "func test_") or std.mem.startsWith(u8, line, "def test_")) return true;
    }
    return false;
}

// spec-case: NEW-CORE-S4-TEST-2
test "directory inventory recognizes test declarations and generated subtrees" {
    try std.testing.expect(declaresTests("public func test_x() -> bool:\n    return True\n"));
    try std.testing.expect(declaresTests("public func test_x() -> bool:\n    return True\n"));
    try std.testing.expect(declaresTests("@test\nfunc property(x: int) -> bool:\n    return True\n"));
    try std.testing.expect(!declaresTests("# def test_x()\n"));
    try std.testing.expect(language.release_project.generatedName(".selka-cache-new"));
    try std.testing.expect(!language.release_project.generatedName("types"));
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
    const path = try std.fs.path.join(a, &.{ root, "app.selka" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = "original" });
    var digest: [32]u8 = undefined;
    fast_blake3.hash("original", &digest);
    const inputs = &.{Input{ .path = path, .digest = digest }};
    const selection: Selection = .{ .entries = &.{}, .tested = &.{}, .inputs = inputs, .discovered = &.{path} };
    const opts: options.Options = .{ .path = root, .build = .{ .zig = "zig", .cache = try std.fs.path.join(a, &.{ root, "cache" }) } };
    try std.testing.expect(!try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = "changed" });
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.deleteFile(std.testing.io, "app.selka");
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
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tests/app.selka", .data = "entry" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dep.selka", .data = "original" });
    const path = try std.fs.path.join(a, &.{ root, "tests/app.selka" });
    const dependency = try std.fs.path.join(a, &.{ root, "dep.selka" });
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
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dep.selka", .data = "changed" });
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dep.selka", .data = "original" });
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
    try snapshot.content("dep.selka", "first");
    try snapshot.content("dep.selka", "first");
    try std.testing.expectEqual(@as(usize, 1), snapshot.inputs.items.len);
    try std.testing.expectError(error.SourceChanged, snapshot.content("dep.selka", "other"));
}

// spec-case: NEW-CORE-S4-TEST-2
test "sourceChanged preserves inventory additions and ignores unrelated outputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "app.selka" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = "original" });
    var snapshot: Snapshot = .{ .allocator = a, .io = std.testing.io };
    defer snapshot.index.deinit(a);
    try snapshot.disk(path);
    const selection: Selection = .{ .entries = &.{}, .tested = &.{}, .inputs = snapshot.inputs.items, .discovered = &.{path} };
    const opts: options.Options = .{ .path = root, .build = .{ .zig = "zig", .cache = try std.fs.path.join(a, &.{ root, "cache" }) } };
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "output.json", .data = "{}" });
    try std.testing.expect(!try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "new.selka", .data = "new source" });
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
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tests/app.selka", .data = "import dep\npublic func test_x() -> bool:\n    return True\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dep.selka", .data = "public func value() -> str:\n    return \"old\"\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "ext.selka", .data = "public func value() -> str:\n    return \"external\"\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "data.txt", .data = "original asset" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = language.project_config.config_name, .data = "{\"version\":1,\"interface_files\":true,\"import_policy\":\"policy.json\"}" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "policy.json", .data = "{}" });
    const configured_cases = "{\"test_x\":{\"providers\":{\"dep.selka\":\"import ext\\n" ++
        "public func value() -> str:\\n    return embed_str(\\\"data.txt\\\")\\n\"}}}";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tests/app.cases.json", .data = configured_cases });
    const path = try std.fs.path.join(a, &.{ root, "tests/app.selka" });
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
    try std.testing.expect(snapshot.index.contains(try std.fs.path.join(a, &.{ root, "ext.selka" })));
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
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "small.selka", .data = "func test_a() -> bool:\n    return True\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "large.selka", .data = "func test_b() -> bool:\n    return True\n\nfunc test_c() -> bool:\n    return True\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "same.selka", .data = "func test_d() -> bool:\n    return True\n\nfunc test_e() -> bool:\n    return True\n" });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const paths = [_][]const u8{ try std.fs.path.join(a, &.{ root, "small.selka" }), try std.fs.path.join(a, &.{ root, "large.selka" }), try std.fs.path.join(a, &.{ root, "same.selka" }), try std.fs.path.join(a, &.{ root, "missing.selka" }) };
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
test "sharedClosures loads headerless roots together and leaves a failed load to load alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const io = std.testing.io;
    try temporary.dir.writeFile(io, .{ .sub_path = "selka.json", .data = "{\"version\": 1}\n" });
    try temporary.dir.writeFile(io, .{ .sub_path = "dep.selka", .data = "\npublic func value() -> int:\n    return 3\n" });
    try temporary.dir.writeFile(io, .{ .sub_path = "a_test.selka", .data = "import dep\n\npublic func test_a() -> bool:\n    return dep.value() == 3\n" });
    try temporary.dir.writeFile(io, .{ .sub_path = "b_test.selka", .data = "\npublic func test_b() -> bool:\n    return True\n" });
    try temporary.dir.writeFile(io, .{ .sub_path = "c_test.selka", .data = "public func test_c() -> bool:\n    return True\n" });
    var environment = try std.testing.environ.createMap(a);
    const init: std.process.Init = .{ .minimal = .{ .environ = .empty, .args = .{ .vector = &.{} } }, .arena = &arena, .gpa = std.testing.allocator, .io = io, .environ_map = &environment, .preopens = .empty };
    const roots = [_][]const u8{ try std.fs.path.join(a, &.{ root, "a_test.selka" }), try std.fs.path.join(a, &.{ root, "b_test.selka" }), try std.fs.path.join(a, &.{ root, "c_test.selka" }) };
    var snapshot: Snapshot = .{ .allocator = a, .io = io };
    const found = try sharedClosures(init, &roots, &snapshot);
    try std.testing.expect(lists(found[0].?, "a_test.selka") and lists(found[0].?, "dep.selka"));
    try std.testing.expect(lists(found[1].?, "b_test.selka") and !lists(found[1].?, "dep.selka"));
    try std.testing.expect(lists(found[2].?, "c_test.selka") and !lists(found[2].?, "dep.selka"));
    // A root that imports a missing module fails the shared load: every root loads alone.
    try temporary.dir.writeFile(io, .{ .sub_path = "b_test.selka", .data = "import missing\n\npublic func test_b() -> bool:\n    return True\n" });
    var fresh: Snapshot = .{ .allocator = a, .io = io };
    const alone = try sharedClosures(init, &roots, &fresh);
    try std.testing.expectEqual(@as(?[]const []const u8, null), alone[0]);
    try std.testing.expectEqual(@as(?[]const []const u8, null), alone[1]);
}

// spec-case: SELFHOST-CACHE-REPORT-1
test "explanation rejects malformed child cache metadata instead of preserving a passed verdict" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const malformed = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"cache\":{\"action\":1}}", .{});
    var item: report.Verdict = .{ .name = "app::test", .status = .passed };
    try std.testing.expect(!try explanation(a, malformed, &item));
    try std.testing.expectEqual(report.Status.failed, item.status);
    try std.testing.expectEqualStrings("invalid cache explanation in test report", item.reason);
}

test "docstring example inventory honors ancestor release exclusions from a nested directory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const io = std.testing.io;
    try temporary.dir.createDirPath(io, "nested/vendor");
    try temporary.dir.createDirPath(io, "nested/build");
    try temporary.dir.createDirPath(io, "nested/.hidden");
    try temporary.dir.writeFile(io, .{ .sub_path = "selka.json", .data = "{\"version\":2,\"release\":{\"exclude\":[\"nested/vendor\"]}}" });
    try temporary.dir.writeFile(io, .{ .sub_path = "nested/kept.selka", .data = "" });
    try temporary.dir.writeFile(io, .{ .sub_path = "nested/vendor/skipped.selka", .data = "" });
    try temporary.dir.writeFile(io, .{ .sub_path = "nested/build/skipped.selka", .data = "" });
    try temporary.dir.writeFile(io, .{ .sub_path = "nested/.hidden/skipped.selka", .data = "" });
    const root = try temporary.dir.realPathFileAlloc(io, "nested", a);
    const found = try inventory(a, io, .{ .path = root, .build = .{ .zig = "zig" } }, null, null);
    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, "kept.selka" }), found[0]);
}

test "an inventory of a folder the command line names walks it whatever it is called, and notes the folders it left alone beneath it (FR85)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const io = std.testing.io;
    try temporary.dir.createDirPath(io, "tools/build/build");
    try temporary.dir.createDirPath(io, "tools/build/sub/node_modules");
    try temporary.dir.writeFile(io, .{ .sub_path = "selka.json", .data = "{\"version\":1}" });
    try temporary.dir.writeFile(io, .{ .sub_path = "tools/build/t.selka", .data = "" });
    try temporary.dir.writeFile(io, .{ .sub_path = "tools/build/sub/s.selka", .data = "" });
    try temporary.dir.writeFile(io, .{ .sub_path = "tools/build/build/out.selka", .data = "" });
    try temporary.dir.writeFile(io, .{ .sub_path = "tools/build/sub/node_modules/n.selka", .data = "" });
    const named = try temporary.dir.realPathFileAlloc(io, "tools/build", a);
    var left: std.ArrayList([]const u8) = .empty;
    const found = try inventory(a, io, .{ .path = named, .build = .{ .zig = "zig" } }, null, &left);
    try std.testing.expectEqual(@as(usize, 2), found.len);
    try std.testing.expectEqualStrings(try std.fs.path.join(a, &.{ named, "sub/s.selka" }), found[0]);
    try std.testing.expectEqualStrings(try std.fs.path.join(a, &.{ named, "t.selka" }), found[1]);
    try std.testing.expectEqual(@as(usize, 2), left.items.len);
    // A walk of the project root still leaves `build` alone.
    const whole = try inventory(a, io, .{ .path = try temporary.dir.realPathFileAlloc(io, ".", a), .build = .{ .zig = "zig" } }, null, null);
    try std.testing.expectEqual(@as(usize, 0), whole.len);
}

test "the line for a directory run that found nothing names the folders it left alone and why, and how to include one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("note: no tests found under `tools`\n", try emptyLine(a, "tools", &.{}));
    try std.testing.expectEqualStrings(
        "note: no tests found under `tools`: `tools/build/` is left alone as a build-output folder; name it to include it\n",
        try emptyLine(a, "tools", &.{.{ .path = "tools/build/", .why = leftBecause("build") }}),
    );
    try std.testing.expectEqualStrings(
        "note: no tests found under `.`: `a/node_modules/` is left alone as a dependency folder, `.hid/` as a hidden folder, `v/` because `release.exclude` lists it; name one to include it\n",
        try emptyLine(a, ".", &.{
            .{ .path = "a/node_modules/", .why = leftBecause("node_modules") },
            .{ .path = ".hid/", .why = leftBecause(".hid") },
            .{ .path = "v/", .why = leftBecause("v") },
        }),
    );
}

test "the note for an empty directory run names a left-alone folder only when it holds sources" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const io = std.testing.io;
    try temporary.dir.createDirPath(io, "tools/build");
    try temporary.dir.createDirPath(io, "tools/zig-out");
    try temporary.dir.writeFile(io, .{ .sub_path = "tools/build/t.selka", .data = "" });
    try temporary.dir.writeFile(io, .{ .sub_path = "tools/zig-out/notes.txt", .data = "" });
    const named = try temporary.dir.realPathFileAlloc(io, "tools", a);
    const note = try emptyNote(a, io, .{ .path = named, .build = .{ .zig = "zig" } });
    const expected = try std.fmt.allocPrint(a, "note: no tests found under `{s}`: `{s}/build/` is left alone as a build-output folder; name it to include it\n", .{ named, named });
    try std.testing.expectEqualStrings(expected, note);
}

test "a directory's own selka.json that cannot be read is named with its line and reason, as one below it is" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = arena.allocator();
    const io = std.testing.io;
    try temporary.dir.writeFile(io, .{ .sub_path = "selka.json", .data = "{}" });
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var diagnostics: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.MissingVersion, inventory(a, io, .{ .path = root, .build = .{ .zig = "zig" } }, &diagnostics, null));
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.items, "selka.json:") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.items, "error[E_PROJECT_CONFIG]: selka.json must carry version: 1") != null);
}

test "the note after a directory run names the two ways to set an import root, once, for the files no selka.json governs" {
    const located = [_]Location{
        .{ .path = "/p/a_test.selka", .root = "/p", .name = "a_test", .configuration = null },
        .{ .path = "/p/b/b_test.selka", .root = "/p/b", .name = "b_test", .configuration = "/p/b/selka.json" },
    };
    try std.testing.expect(!governed(&located, "/p/a_test.selka"));
    try std.testing.expect(governed(&located, "/p/b/b_test.selka"));
    try std.testing.expect(governed(&located, "/p/unknown_test.selka"));
    const note = importRootNote(2);
    try std.testing.expect(std.mem.indexOf(u8, note, "no `selka.json` governs") != null);
    try std.testing.expect(std.mem.indexOf(u8, note, "{\"version\": 1}") != null);
    try std.testing.expect(std.mem.indexOf(u8, note, "--import-root DIR") != null);
    // A relative folder names the root as an absolute one does, so the note no longer asks for an absolute path.
    try std.testing.expect(std.mem.indexOf(u8, note, "absolute") == null);
}

test "a closure path is made relative to its root by cutting the prefix, as resolving both would make it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("sub/lib.selka", try rootRelative(a, "/work/project", "/work/project/sub/lib.selka"));
    try std.testing.expectEqualStrings(try std.fs.path.relative(a, "/work/project", null, "/work/project", "/work/project/sub/lib.selka"), try rootRelative(a, "/work/project", "/work/project/sub/lib.selka"));
    // Anything else is resolved: a path with `..`, a sibling that shares the prefix, a root with a trailing slash.
    try std.testing.expectEqualStrings("lib.selka", try rootRelative(a, "/work/project", "/work/project/sub/../lib.selka"));
    try std.testing.expectEqualStrings("../project-two/lib.selka", try rootRelative(a, "/work/project", "/work/project-two/lib.selka"));
    try std.testing.expectEqualStrings("lib.selka", try rootRelative(a, "/work/project/", "/work/project/lib.selka"));
}
