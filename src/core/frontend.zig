//! The new core's view of the existing front end (decision N3): load one entry
//! file and its imports, check them, and hand back the checked `typed.Program`
//! with the merged source its spans index. Nothing below the checker (bytecode,
//! QBE, the native build driver) is reached from here.
const recovered_ownership = @import("recovered_ownership.zig");
const std = @import("std");
const product = @import("selka").product;
const allocation_contract = @import("allocation_contract.zig");
const language = @import("selka");
const reuse = @import("frontend_reuse.zig");
const ownership_cache = @import("ownership_cache.zig");
const entry_name = @import("entry_name.zig");
const engine_sharing = @import("engine_sharing.zig");
const shadow_rules = @import("frontend_shadow.zig");
const lowering_cache = @import("lowering_cache.zig");
const world_rules = @import("engine/world.zig");

/// Identity of all production compiler/runtime/property sources and toolchain.
pub const compiler_identity = reuse.compiler_identity;
/// Actual front-end cache work observed during this session.
pub const Statistics = reuse.Statistics;
/// How a session reads the stored syntax of its modules: `SELKA_LAZY_SYNTAX=0` (or `off`) completely, anything else, and by default, as far
/// as the declarations (the bodies are filled when the check reads them). A session that verifies (`SELKA_ENGINE_VERIFY`, and every Debug
/// compiler) also fills the bodies that are not read with a sentinel, so a reader that missed its fill is found by the comparison.
fn syntaxModeOf(environment: *const std.process.Environ.Map, verify_every: u32) language.lazy_module.Mode {
    if (environment.get("SELKA_LAZY_SYNTAX")) |value| {
        if (std.mem.eql(u8, value, "0") or std.mem.eql(u8, value, "off")) return .eager;
    }
    return if (verify_every != 0) .lazy_sentinel else .lazy;
}

/// The racy window the module digests' stat rule uses (`language.file_digests`): the engine's own, so a file the engine would not trust to its
/// stat tuple is not trusted by the loader either. `frontend_shadow` configures the engine with the default `Assumptions`.
pub const digest_window_ns: i64 = (world_rules.Assumptions{}).racy_window_ns;

/// One module source supplied by the project test runner, borrowed until deinit.
pub const Provider = struct { path: []const u8, text: []const u8 };

const Settings = struct {
    options: language.project.Options = .{},
    entry: ?[]const u8 = null,
    providers: []const Provider = &.{},
    /// How diagnostics are rendered into a report: terminal text or `diagnostic-v1` lines.
    format: language.diagnostic_output.Format = .text,
    /// Name a header-less file by the path it was given, as the `selka` CLI does,
    /// rather than by its base name (`selka-core`).
    given_path: bool = false,
    allocation_contracts: bool = true,
    /// A library check of one file (`check-module`) reports the typed holes of its own module in full and counts those of the other
    /// modules it reached on one line (`renderFolded`). Text only: `diagnostic-v1` lines stay complete.
    fold_foreign_holes: bool = false,
    /// How the checks treat a `todo[T]()` hole: `trap` (the default, for builds and tests in debug
    /// modes) keeps it as a located runtime trap; `refuse` reports E_TYPED_HOLE. Release and `check` refuse.
    /// `template_probes`: a check also judges each generic function at its declaration through stand-in instances
    /// (`Sink.template_probes`).
    validation: struct { holes: language.diagnostic.HoleMode = .trap, ownership_reports: bool = false, complete: bool = false, template_probes: language.diagnostic.Probes = .off } = .{},
};
const Graph = struct {
    index: language.interfaces.Index = undefined,
    compilation: language.project_compile.Compilation = undefined,
    settings: Settings = .{},
    profile: ?*language.timings.Profile = null,
    /// The caches a long-lived process lends this session and keeps between sessions (`check-session`): parsed syntax and checked bodies.
    resident: struct { syntax: ?*language.syntax_cache.Cache = null, functions: ?*language.semantic_cache.Cache = null } = .{},
    /// How the stored syntax of the modules is read: as far as the declarations with the bodies filled on demand (the default), or completely
    /// (`SELKA_LAZY_SYNTAX=0`, and every command that reads all bodies).
    syntax_mode: language.lazy_module.Mode = .lazy,
};

/// A module of a loaded project graph.
pub const Module = language.project.Module;

/// The checked program and the merged source its spans point into.
pub const Checked = struct {
    program: language.typed.Program,
    src: language.source.Source,
    allocation_warnings: []const u8 = "",
};

/// Prepared declaration identities and actual body omissions from a demand check.
pub const DemandState = struct {
    prepared: language.semantic_summary.Prepared,
    omitted: []const bool,
};

/// The checked program of `checkBodiesOf` and how many of its bodies were left out of the check.
pub const Bodies = struct { checked: Checked, omitted: usize };

/// The modules whose bodies a `checkBodiesOf` keeps concrete, by module name. As a demand host it leaves out a body that is not one of
/// theirs.
const Asked = struct {
    names: []const []const u8,

    /// Whether the module called `name` is one of them.
    fn includes(self: *const Asked, name: []const u8) bool {
        for (self.names) |known| if (std.mem.eql(u8, known, name)) return true;
        return false;
    }

    /// Whether the stored artifact of the function with stable key `key` may stand for its body: when its module was not asked for.
    fn leavesOut(context: *const anyopaque, key: []const u8, _: [32]u8, _: [32]u8) bool {
        const asked: *const Asked = @ptrCast(@alignCast(context));
        var fields = std.mem.splitScalar(u8, key, 0x1f);
        _ = fields.next();
        const module = fields.next() orelse return false;
        return !asked.includes(module);
    }
};

/// Why a load stopped: diagnostics were already rendered into `report`.
pub const Error = error{ SourceError, OutOfMemory, InternalError };

/// Cache owners stay at their final session address after binding. `work` is the work directory the caches are under, and
/// `shadow` the engine's shadow of this session (`frontend_shadow.zig`), present only when the environment turns it on.
const Caches = struct {
    frontend: ?reuse.State = null,
    ownership: ?*ownership_cache.Cache = null,
    work: []const u8 = "",
    shadow: ?*shadow_rules.Shadow = null,
    /// Whether the passes stand in for a function whose summary cannot stand in whole (`SELKA_ENGINE_DECIDE_PASSES`, on by default).
    passes: bool = true,
    /// One pass stand-in in this many is withheld and compared with what the passes compute (the engine's verify sampling).
    verify_every: u32 = 0,
    /// A zero-retention checked-body counter for a session with no caches, so a command can still report how many bodies it checked.
    counting: ?language.semantic_cache.Cache = null,
};

/// Entry-file overrides for a session: appended test stub, entry path, and load name.
pub const EntryState = struct {
    /// Text appended to the entry file as it is read: `selka-core test` appends the
    /// old runner's stub `main` to a library file so the file can be checked as a program.
    suffix: []const u8 = "",
    /// The entry module's file name relative to the root, set by `check` while a suffix is in use.
    file: []const u8 = "",
    /// The module name the last `declare` was asked to load, for load diagnostics.
    name: []const u8 = "",
    /// A caller's own module provider (generated inputs, an embed root, the header records), used instead of the session's files.
    provider: ?language.project.Provider = null,
};

/// One command's project graph, source files and reuse caches.
pub const Session = struct {
    project: language.project.Project,
    graph: Graph = .{},
    files: language.project_files.Files,
    /// A file with no `module` header is checked alone, as `selka build` does.
    single: ?language.Compilation = null,
    /// Entry-file overrides and the name used in load diagnostics.
    entry: EntryState = .{},
    caches: Caches = .{},
    /// The modules a `checkBodiesOf` asked for; null when the session asks for the whole program.
    asked: ?*const Asked = null,

    /// Prepare to load the module graph rooted at `root` (the entry file's directory).
    pub fn init(allocator: std.mem.Allocator, io: std.Io, root: []const u8) Session {
        return .{ .project = language.project.Project.init(allocator), .files = .{ .io = io, .root = root } };
    }

    /// Release the project arena and everything checked from it.
    pub fn deinit(self: *Session) void {
        if (self.caches.shadow) |shadow| shadow.end();
        if (self.caches.ownership) |cache| cache.deinit();
        if (self.caches.frontend) |*state| state.deinit();
        if (self.single) |*unit| unit.deinit();
        if (self.caches.counting) |*counter| counter.deinit();
        self.project.deinit();
    }

    /// Count the bodies this session checks although it has no caches (`--no-cache`): the check goes through a cache that retains
    /// nothing, so `workCounter` reports the same work a cached check would.
    pub fn countWork(self: *Session, allocator: std.mem.Allocator) void {
        self.caches.counting = language.semantic_cache.Cache.init(allocator, 0);
    }

    /// The checked-body cache this session checks through, whose statistics count checked and reused bodies: the cached state's, the
    /// counter of `countWork`, or null when the session checks without either.
    pub fn workCounter(self: *Session) ?*language.semantic_cache.Cache {
        return self.semanticCache();
    }

    /// Enable shared syntax/body/summary reuse under `root`. Keep the session at
    /// its current address after this call, as its index and cache borrow it.
    pub fn enableCache(self: *Session, allocator: std.mem.Allocator, root: []const u8) error{OutOfMemory}!void {
        self.caches.frontend = try reuse.State.init(allocator, self.files.io, root);
        self.caches.frontend.?.bind();
        self.caches.work = root;
        const owned = try self.project.arena.allocator().create(ownership_cache.Cache);
        owned.* = try ownership_cache.Cache.init(self.project.arena.allocator(), allocator, self.files.io, root);
        self.caches.ownership = owned;
    }

    /// Attach immutable compiler artifacts after the private cache has its final address.
    pub fn enableSharedCache(self: *Session, environment: *const std.process.Environ.Map) error{ OutOfMemory, WriteFailed }!void {
        self.caches.passes = shadow_rules.decidesPasses(environment);
        self.caches.verify_every = shadow_rules.passesVerifyEvery(environment);
        self.graph.syntax_mode = syntaxModeOf(environment, self.caches.verify_every);
        if (self.caches.shadow == null and self.caches.work.len != 0) {
            self.caches.shadow = shadow_rules.begin(self.project.arena.child_allocator, self.files.io, environment, self.caches.work, self.files.root);
            // The session now has its final address: the engine reads the modules this session overlays as the session reads them.
            if (self.caches.shadow) |shadow| shadow.machine.os.overlay = .{ .context = self, .has = overlays, .text = overlaidText };
        }
        if (self.caches.ownership) |cache| {
            cache.verifyFrom(environment);
            cache.share(engine_sharing.explicit(environment));
        }
        const directory = language.shared_artifact_store.selected(environment) orelse return;
        const state = if (self.caches.frontend) |*cache| cache else return;
        if (state.shared != null) return;
        state.shared = language.shared_artifact_store.Store.open(state.semantic.allocator, self.files.io, directory) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            var buffer: [256]u8 = undefined;
            const text = std.fmt.bufPrint(&buffer, "error: shared compiler cache: {s}\n", .{@errorName(err)}) catch return error.WriteFailed;
            std.Io.File.stderr().writeStreamingAll(self.files.io, text) catch return error.WriteFailed;
            return error.WriteFailed;
        };
        state.bind();
    }

    /// Configure loader budgets and the entry's module name for project paths.
    pub fn configureProject(self: *Session, options: language.project.Options, entry: ?[]const u8) void {
        self.graph.settings.options = options;
        self.graph.settings.entry = entry;
    }

    /// Render diagnostics as `format` (`selka run --diagnostics=json`), and name a
    /// header-less file by the path it was given, as the `selka` CLI does.
    /// Choose how this session's checks treat typed holes (see `Settings.validation.holes`): `true` keeps each hole as a
    /// runtime trap, as debug builds and tests do; `false` refuses it with `E_TYPED_HOLE`, as a release build does.
    pub fn setHoleTraps(self: *Session, traps: bool) void {
        self.graph.settings.validation.holes = if (traps) .trap else .refuse;
    }

    /// Enable the uncached developer ownership census and Core refusal audit.
    pub fn setOwnershipReports(self: *Session) void {
        std.debug.assert(self.caches.frontend == null);
        std.debug.assert(self.caches.ownership == null);
        self.graph.settings.validation.ownership_reports = true;
    }

    /// Choose how diagnostics are rendered: text or `diagnostic-v1` lines.
    pub fn setFormat(self: *Session, format: language.diagnostic_output.Format) void {
        self.graph.settings.format = format;
        self.graph.settings.given_path = true;
    }

    /// Render diagnostics as `format` but keep naming a header-less file by its base
    /// name, as `selka test` does; `setFormat` names it by the path it was given.
    pub fn setReportFormat(self: *Session, format: language.diagnostic_output.Format) void {
        self.graph.settings.format = format;
    }

    /// Make a failed library check report the typed holes of other modules as one counted line (`check-module FILE`: the holes of FILE
    /// stay in full, since they are what the file still owes). The exit status is unchanged.
    pub fn foldForeignHoles(self: *Session) void {
        self.graph.settings.fold_foreign_holes = true;
    }

    /// Call only after a successful check. The warnings of that check, rendered in the session's format,
    /// as the old CLI printed them before building or running (NEW-CORE-S5-CLI-1).
    pub fn warnings(self: *Session, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        if (self.single) |*unit| {
            try self.renderAll(allocator, unit.diagnostics.items, unit.src, &out);
        } else {
            try self.renderAll(allocator, self.graph.compilation.diagnostics.items.items, self.graph.compilation.src, &out);
        }
        return out.items;
    }

    /// `renderAll`, except that in text a typed hole of a module other than the entry (the first module of the merged source) is
    /// counted, not printed, and one `note:` line after the rest says how many holes in how many modules.
    fn renderFolded(self: *const Session, allocator: std.mem.Allocator, items: []const language.diagnostic.Diagnostic, src: language.source.Source, out: *std.ArrayList(u8)) error{OutOfMemory}!void {
        if (!self.graph.settings.fold_foreign_holes or self.graph.settings.format != .text) return self.renderAll(allocator, items, src, out);
        var kept: std.ArrayList(language.diagnostic.Diagnostic) = .empty;
        defer kept.deinit(allocator);
        var modules: std.AutoHashMapUnmanaged(usize, void) = .empty;
        defer modules.deinit(allocator);
        var holes: usize = 0;
        for (items) |item| {
            const other = foreignModule(item, src) orelse {
                try kept.append(allocator, item);
                continue;
            };
            holes += 1;
            try modules.put(allocator, other, {});
        }
        try self.renderAll(allocator, kept.items, src, out);
        if (holes == 0) return;
        try out.print(allocator, "note: {d} typed hole{s} in {d} other module{s} (check DIR lists them)\n", .{
            holes,
            if (holes == 1) "" else "s",
            modules.count(),
            if (modules.count() == 1) "" else "s",
        });
    }

    /// The module of the merged source that holds `item`, when it is a typed hole outside the entry module.
    fn foreignModule(item: language.diagnostic.Diagnostic, src: language.source.Source) ?usize {
        if (!std.mem.eql(u8, item.code, language.diagnostic.typed_hole_code)) return null;
        const original = src.originalSpan(item.span) catch return null;
        return if (original.input == 0) null else original.input;
    }

    fn renderAll(self: *const Session, allocator: std.mem.Allocator, all: []const language.diagnostic.Diagnostic, src: language.source.Source, out: *std.ArrayList(u8)) error{OutOfMemory}!void {
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();
        const named = try language.project_module_import.explain(scratch.allocator(), .{ .io = self.files.io, .path = self.files.root }, all, src);
        const items = try self.repairNotes(scratch.allocator(), named, src);
        for (items) |item| {
            language.friction_session.note(item);
            const text = try language.diagnostic_output.render(allocator, item, src, self.graph.settings.format);
            defer allocator.free(text);
            try out.appendSlice(allocator, text);
        }
    }

    /// `items` with the `selka rename` note on each `E_SHADOWING` refusal of a binding that hides a module-level name or
    /// an import alias (`shadowing_repair.zig`), its paths relative to the working directory. Rendering adds it, so no
    /// stored diagnostic holds it.
    fn repairNotes(self: *const Session, allocator: std.mem.Allocator, items: []const language.diagnostic.Diagnostic, src: language.source.Source) error{OutOfMemory}![]const language.diagnostic.Diagnostic {
        const any = for (items) |item| {
            if (std.mem.eql(u8, item.code, language.diagnostic.shadowing)) break true;
        } else false;
        if (!any) return items;
        const cwd = std.Io.Dir.cwd().realPathFileAlloc(self.files.io, ".", allocator) catch return items;
        // A merged program prints paths relative to its root; a file checked alone, the path it was given.
        const root = if (src.origins.len == 0) cwd else try std.fs.path.resolve(allocator, &.{ cwd, self.files.root });
        // The entry is the first module of a merged program, or the one file of a program checked alone.
        const entry = if (src.origins.len != 0) src.origins[0].original.path else src.path;
        return language.shadowing_repair.annotate(allocator, items, src, .{ .root = root, .cwd = cwd, .entry = entry });
    }

    /// Overlay exact relative module paths with explicit test-provider sources.
    pub fn setProviders(self: *Session, providers: []const Provider) void {
        self.graph.settings.providers = providers;
    }

    /// The merged program, valid after `mergeDeclared`.
    pub fn mergedProgram(self: *Session) *language.project_compile.Compilation {
        return &self.graph.compilation;
    }

    /// The fresh interface index, valid after a successful module check.
    pub fn interfaceIndex(self: *Session) *language.interfaces.Index {
        return &self.graph.index;
    }

    /// Validation-only commands can omit unchanged bodies. Builds retain typed
    /// trees unless their lowering host admits safe artifacts through demand.
    pub fn validationOnly(self: *Session) void {
        self.graph.settings.allocation_contracts = false;
        self.graph.settings.validation.template_probes = .declaration;
        if (self.caches.frontend) |*state| state.request.body_policy = .concrete;
    }

    /// Judge `W_COPY_MOVE` hints against the callers inside the check, as `check` prints them (FR14b): each checked caller's
    /// answers are stored in its summary, so a check that stands unchanged bodies in judges as a check of every body does.
    pub fn judgeCopyMoves(self: *Session) void {
        if (self.caches.frontend) |*state| state.request.policy.copy_moves = .{ .context = self, .facts = copyMoveFacts };
    }

    /// Let the check repair `public` functions too (`W_COPY_FOR_STORE` in a project that is no package). Summaries made under the other
    /// answer are not read: the stood-in function's warning would differ from what a check of every body prints.
    pub fn repairPublic(self: *Session, repaired: bool) void {
        self.graph.compilation.repairs_public = repaired;
        if (self.caches.frontend) |*state| state.frontend.setSummaryPolicy(if (repaired) reuse.public_identity else reuse.compiler_identity);
    }

    fn copyMoveFacts(
        _: *const anyopaque,
        allocator: std.mem.Allocator,
        program: language.typed.Program,
        src: language.source.Source,
        targets: []const language.semantic_summary.HintTarget,
    ) error{OutOfMemory}![]const []const language.semantic_summary.CallerFact {
        return @import("single_owner.zig").callerFacts(allocator, program, src, targets);
    }

    /// Check through stand-in instances of every template (the developer count of W3, `diagnostic.Probes.every`), recording each
    /// in `log`, and leave the ownership validation to the caller: the check then refuses no instance the count made. Call it after
    /// `validationOnly`, on a session with no caches.
    pub fn countStandIns(self: *Session, log: *language.template_stand_ins.Log) void {
        self.graph.settings.validation.template_probes = .{ .every = log };
    }

    /// Keep no typed trees for a later build: a check lowers nothing, so an unchanged body stands in by its summary and ownership proof
    /// alone and a stored tree is never read for it. That also keeps a check from serving a tree checked under another standard-library
    /// trust (`src.trusted_intrinsics` is not in a stored body's key), which a comment edit of a standard-named file flips.
    pub fn discardTrees(self: *Session) void {
        if (self.caches.frontend) |*state| state.semantic.context.retain_summary_trees = false;
    }

    /// Check for a whole checked program and omit no body: a command that reads every body's tree (the invalidation receipt) asks for this
    /// instead of `validationOnly`. Summaries still stand in the cross-function facts of unchanged bodies, and no ownership proof lets a
    /// body go unchecked.
    pub fn completeProgram(self: *Session) void {
        self.graph.settings.allocation_contracts = false;
        self.graph.settings.validation.complete = true;
        if (self.caches.frontend) |*state| state.request.body_policy = .concrete;
        self.discardTrees();
    }

    /// Let a lowering host admit unchanged body artifacts before checking.
    pub fn configureDemand(self: *Session, demand: language.semantic_summary.Demand) void {
        if (self.caches.frontend) |*state| state.request.policy.demand = demand;
    }

    /// The checked bodies of the modules at `paths` (project-relative) of the program entered at `entry`, and of no other module that
    /// can be left out: the call a unit's computation makes to get the bodies it lowers. A body of one of those modules is restored from
    /// the checked-body store when its keys stand (the engine's `module-check` record decides them) and checked otherwise. A body of
    /// any other module whose stored summary still stands, and whose ownership proof the engine holds, is not checked and not decoded;
    /// `demandState().omitted` says which, and an omitted body has no tree in the program (read only the bodies it does not mark).
    /// A module whose bodies changed is checked whoever asks, because the passes that read it need it. With no work directory (no
    /// caches) nothing is left out. The asked set stays in the session (`asks`), and the mask is the one the stand-in planner and the
    /// passes already read (`Plan.bodyStandIn`), so a pass that skips what a stood-in body stands for skips it for exactly these modules.
    /// Replaces any demand host configured before; the report gets a message and `SourceError` returns when a path names no module of
    /// the program.
    pub fn checkBodiesOf(self: *Session, allocator: std.mem.Allocator, entry: []const u8, paths: []const []const u8, report: *std.ArrayList(u8)) Error!Bodies {
        try self.declare(allocator, entry, report);
        const asked = try allocator.create(Asked);
        const names = try allocator.alloc([]const u8, paths.len);
        for (paths, names) |path, *name| {
            name.* = self.moduleNameAt(path) orelse {
                try report.print(allocator, "error: the program entered at {s} has no module at {s}\n", .{ entry, path });
                return error.SourceError;
            };
        }
        asked.* = .{ .names = names };
        self.asked = asked;
        self.configureDemand(.{ .context = asked, .allow = Asked.leavesOut, .body_dependencies = false, .facts_unread = true });
        // The bodies of the asked modules are restored from the store when their keys stand, so the check keeps writing every one.
        if (self.caches.frontend) |*state| state.request.policy.restores_trees = true;
        const checked = try self.checkDeclared(allocator, report);
        var omitted: usize = 0;
        if (self.demandState()) |state| for (state.omitted) |left_out| {
            omitted += @intFromBool(left_out);
        };
        return .{ .checked = checked, .omitted = omitted };
    }

    /// Whether this session's caller wants the module called `name` (a module name, as the stable keys spell it) concrete: every module,
    /// unless a `checkBodiesOf` named some. The body policy leaves out a module this says no to, and so can any pass that would
    /// otherwise read what the module's stood-in bodies stand for (the same mask: `demandState`).
    pub fn asks(self: *const Session, name: []const u8) bool {
        const asked = self.asked orelse return true;
        return asked.includes(name);
    }

    /// The name of the loaded module whose project-relative path is `path`, or null.
    fn moduleNameAt(self: *const Session, path: []const u8) ?[]const u8 {
        for (self.project.modules.items) |module| if (std.mem.eql(u8, module.src.path, path)) return module.name;
        return null;
    }

    /// Actual skipped bodies and declaration identities, valid after checking.
    pub fn demandState(self: *const Session) ?DemandState {
        const state = self.caches.frontend orelse return null;
        const prepared = state.request.prepared orelse return null;
        const omitted = if (state.request.policy.demand) |demand| demand.omitted else &.{};
        return .{ .prepared = prepared, .omitted = omitted };
    }

    /// Attach opt-in phase instrumentation without changing checking behavior.
    pub fn setProfile(self: *Session, profile: *language.timings.Profile) void {
        self.graph.profile = profile;
        if (self.caches.frontend) |*state| state.semantic.context.timing = profile;
    }
    /// Start an exclusive phase window on the attached profile, if there is one.
    fn phaseMark(self: *const Session) ?language.timings.Mark {
        return if (self.graph.profile) |profile| profile.mark() else null;
    }
    /// Record the exclusive phase `name` from `mark` to now, if a profile is attached.
    fn addPhase(self: *const Session, name: []const u8, mark: ?language.timings.Mark) void {
        if (self.graph.profile) |profile| if (mark) |window| profile.addMark(name, window, false);
    }

    /// Actual cache counters for this invocation, or zero when reuse is off.
    pub fn statistics(self: *const Session) Statistics {
        return if (self.caches.frontend) |*state| state.statistics() else .{};
    }

    /// Ownership functions actually checked or reused in this session.
    pub fn ownershipWork(self: *const Session) ownership_cache.Work {
        return if (self.caches.ownership) |cache| cache.work else .{};
    }

    fn syntaxCache(self: *Session) ?*language.frontend_cache.Cache {
        return if (self.caches.frontend) |*state| &state.frontend else null;
    }

    fn semanticCache(self: *Session) ?*language.semantic_cache.Cache {
        if (self.caches.frontend) |*state| return &state.semantic;
        if (self.graph.resident.functions) |lent| return lent;
        return if (self.caches.counting) |*counter| counter else null;
    }

    /// Borrow the caches a long-lived process keeps between requests: parsed syntax is looked up and kept in `syntax`, and bodies are checked
    /// through `functions` (so its statistics count the work). The session owns neither and stores nothing on disk.
    pub fn lendCaches(self: *Session, syntax: *language.syntax_cache.Cache, functions: *language.semantic_cache.Cache) void {
        self.graph.resident = .{ .syntax = syntax, .functions = functions };
    }

    /// Check `path` alone when it opens without a `module` header, else as the
    /// entry of its module graph (`check`).
    pub fn checkFile(self: *Session, allocator: std.mem.Allocator, path: []const u8, report: *std.ArrayList(u8)) (Error || error{ReadFailed})!Checked {
        return self.checkFileMode(allocator, path, report, false);
    }

    /// Check a single file as `check` does: a file with no `main` is checked as a
    /// library, with no executable program retained, like the `selka check` CLI.
    pub fn checkFileLibrary(self: *Session, allocator: std.mem.Allocator, path: []const u8, report: *std.ArrayList(u8)) (Error || error{ReadFailed})!Checked {
        return self.checkFileMode(allocator, path, report, true);
    }

    /// The scope the ownership proofs of the entry file at `path` are kept under: the name the build gave its cache keys, else its
    /// realpath relative to the project root (`entry_name.zig`), never the spelling the command was given. A project checked from
    /// another worktree, or by an absolute path, then finds the proofs the first one made (G4c, spec G-D11).
    fn ownershipScope(self: *const Session, allocator: std.mem.Allocator, path: []const u8) error{OutOfMemory}![]const u8 {
        if (self.files.entry_key.len != 0) return self.files.entry_key;
        return entry_name.of(allocator, self.files.io, self.files.embed_root orelse "", path);
    }

    // Match ordinary `check` routing for public libraries and configured entries.
    // Audit needs the module index too, including trusted standard-library syntax.
    fn auditAsModule(self: *Session, allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) error{OutOfMemory}!bool {
        if (!self.graph.settings.validation.ownership_reports) return false;
        const base = std.fs.path.stem(path);
        if (base.len == 0 or (!std.ascii.isAlphabetic(base[0]) and base[0] != '_')) return false;
        for (base) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |line| if (std.mem.startsWith(u8, line, "public ")) return true;
        const configured = language.project_config.discover(allocator, self.files.io, path) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return false,
        };
        defer if (configured) |found| allocator.free(found);
        return configured != null;
    }

    fn checkFileMode(self: *Session, allocator: std.mem.Allocator, path: []const u8, report: *std.ArrayList(u8), library: bool) (Error || error{ReadFailed})!Checked {
        const relative = if (self.graph.settings.providers.len == 0) "" else try std.fs.path.relative(allocator, self.files.root, null, self.files.root, path);
        const bytes = for (self.graph.settings.providers) |overlay| {
            if (std.mem.eql(u8, overlay.path, relative)) break overlay.text;
        } else std.Io.Dir.cwd().readFileAlloc(self.files.io, path, allocator, .limited(64 << 20)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try report.print(allocator, "error: cannot read {s}: {s}\n", .{ path, @errorName(err) });
                return error.ReadFailed;
            },
        };
        if (language.opensAsModule(bytes) or try self.auditAsModule(allocator, path, bytes)) {
            const name = self.graph.settings.entry orelse entryOf(path).module;
            if (library) return self.checkLibraryModule(allocator, name, report);
            return self.check(allocator, name, report);
        }
        const open_mark = self.phaseMark();
        if (self.caches.ownership) |cache| try cache.open(try self.ownershipScope(allocator, path));
        self.addPhase("ownership_cache_open", open_mark);
        try self.checkSourceBudget(allocator, path, bytes.len, report);
        const full = if (self.entry.suffix.len == 0) bytes else try std.mem.concat(allocator, u8, &.{ bytes, self.entry.suffix });
        const name = if (self.graph.settings.given_path) path else std.fs.path.basename(path);
        self.single = try language.Compilation.init(self.project.arena.child_allocator, name, full);
        const unit = &self.single.?;
        // The entry's key name, when the build set one (`entry_name.zig`): its bytes live in the build's arena, which outlives every re-check.
        unit.src.key_path = self.files.entry_key;
        unit.checking = .{ .holes = self.graph.settings.validation.holes, .template_probes = self.graph.settings.validation.template_probes };
        try self.attachEmbeds(unit, path);
        self.checkSingle(unit, library) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                const shadow = unit.holeProgram(library and unit.syntax != null and !unit.declaresMain()) catch |hole_err| switch (hole_err) {
                    error.OutOfMemory => return error.OutOfMemory,
                };
                try self.renderRefused(allocator, .{ .items = unit.diagnostics.items, .shadow = shadow, .src = unit.src }, report);
                return error.SourceError;
            },
        };
        return self.checkAllocationContracts(allocator, .{ .program = unit.program.?, .src = unit.src }, report);
    }

    /// Check a project whose entry is a library: load its graph, check every
    /// body and boundary, and retain the checked tree without an executable main.
    fn checkLibraryModule(self: *Session, allocator: std.mem.Allocator, entry: []const u8, report: *std.ArrayList(u8)) Error!Checked {
        try self.declare(allocator, entry, report);
        try self.mergeDeclared(allocator, report);
        // `check` still prefers the executable path when the entry declares
        // main; only a genuinely mainless entry uses the library path.
        if (self.graph.compilation.declaresMain()) return self.checkMerged(allocator, report);
        return self.checkLibraryMerged(allocator, null, report);
    }

    /// Check the program `mergeDeclared` built as a library, an entry that declares no `main`: every body, effect and boundary, with
    /// nothing executable retained, then the ownership validation. A refused check renders its diagnostics, and the ownership
    /// errors of the same program with each hole as a typed node, into `report`.
    ///
    /// With `retained` (the slot of this entry's library checks) unchanged bodies stand in from the summaries the entry's last
    /// successful library check left, and this check's own summaries are stored for the next. Preparing dependency keys costs a sixth
    /// of a cold check, and a library checked once, or one that does not check, never uses them, so an entry whose slot is empty runs
    /// the plain check and leaves an empty table behind as a mark. The second successful check finds the mark, prepares the keys
    /// and stores the summaries; the third and later stand bodies in. Without `retained`, or without caches, the check is plain.
    pub fn checkLibraryMerged(self: *Session, allocator: std.mem.Allocator, retained: ?language.frontend_cache.SummarySlot, report: *std.ArrayList(u8)) Error!Checked {
        var request: language.semantic_summary.Request = .{ .body_policy = .summaries };
        const slot = retained orelse return self.checkLibraryWith(allocator, null, report);
        const state = if (self.caches.frontend) |*kept| kept else return self.checkLibraryWith(allocator, null, report);
        request.policy.copy_moves = state.request.policy.copy_moves;
        const load_mark = self.phaseMark();
        // The strings of a decoded table (keys, names, the notes a stood-in body replays) borrow its bytes, and the diagnostics of this check are
        // rendered after this function returns: the bytes live as long as the project's arena.
        const stored: ?[]const u8 = if (try state.frontend.lookupSlotIn(&self.project, slot)) |found| kept: {
            defer state.semantic.allocator.free(found.buffer);
            break :kept try self.project.arena.allocator().dupe(u8, found.payload);
        } else null;
        // A table that does not decode is no table: the check is plain and leaves the mark.
        var table: ?[]const u8 = null;
        if (stored) |bytes| if (language.semantic_summary.decode(self.project.arena.allocator(), bytes)) |decoded| {
            const previous = try self.project.arena.allocator().create(language.semantic_summary.Index);
            previous.* = decoded;
            request.previous = previous;
            table = bytes;
        };
        self.addPhase("summary_load", load_mark);
        // Stored summaries stand bodies in only with the ownership proofs they rest on.
        const reusing = table != null and self.caches.ownership != null;
        if (reusing) {
            self.caches.ownership.?.configure(&request, null, true);
            state.semantic.context.summaries = &request;
        }
        defer if (reusing) {
            state.semantic.context.summaries = null;
            self.caches.ownership.?.policy.request = null;
        };
        const checked = try self.checkLibraryWith(allocator, if (reusing) &state.semantic else null, report);
        if (reusing) {
            try self.rememberLibrarySummaries(slot, &request, table);
        } else if (table == null) {
            const mark = try language.semantic_summary.encode(state.semantic.allocator, .{});
            defer state.semantic.allocator.free(mark);
            try state.frontend.markSummariesIn(&self.project, slot, mark);
        }
        return checked;
    }

    /// Store the summaries a library check produced in `slot`, unless the slot already holds the very same table.
    fn rememberLibrarySummaries(self: *Session, slot: language.frontend_cache.SummarySlot, request: *const language.semantic_summary.Request, table: ?[]const u8) error{OutOfMemory}!void {
        const state = if (self.caches.frontend) |*kept| kept else return;
        const produced = request.produced orelse return;
        const store_mark = self.phaseMark();
        defer self.addPhase("summary_store", store_mark);
        const payload = try language.semantic_summary.encodeFrom(state.semantic.allocator, produced, request.previous, .{});
        defer state.semantic.allocator.free(payload);
        if (table) |same| if (std.mem.eql(u8, same, payload)) return;
        try state.frontend.rememberSummariesIn(&self.project, slot, payload);
    }

    /// The library check itself, through `cache` when the caller attached summaries to it, then the ownership validation.
    fn checkLibraryWith(self: *Session, allocator: std.mem.Allocator, cache: ?*language.semantic_cache.Cache, report: *std.ArrayList(u8)) Error!Checked {
        if (self.graph.profile) |profile| profile.begin("check", true);
        const program = self.graph.compilation.checkLibraryProgramWithCache(cache) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                const shadow = self.graph.compilation.holeProgram(true) catch |hole_err| switch (hole_err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.SourceError, error.InternalError => null,
                };
                try self.renderRefused(allocator, .{ .items = self.graph.compilation.diagnostics.items.items, .shadow = shadow, .src = self.graph.compilation.src, .folded = true }, report);
                return error.SourceError;
            },
        };
        self.graph.compilation.program = program;
        if (self.graph.profile) |profile| profile.end();
        return self.checkAllocationContracts(allocator, .{ .program = program, .src = self.graph.compilation.src }, report);
    }

    fn checkSourceBudget(self: *Session, allocator: std.mem.Allocator, path: []const u8, size: usize, report: *std.ArrayList(u8)) Error!void {
        const options = self.graph.settings.options;
        const limit = @min(options.max_file_bytes, options.max_total_bytes);
        if (size <= limit) return;
        try report.print(allocator, "{s}: error[E_PROJECT_BYTES]: source exceeds the {d}-byte configured budget\n", .{ path, limit });
        return error.SourceError;
    }

    /// Read the files a header-less unit's `embed_bytes`/`embed_str` calls name, against
    /// the unit's own directory and confined to the configuration's root, as the old
    /// CLI did (NEW-CORE-S5-EMBED-1).
    fn attachEmbeds(self: *Session, unit: *language.Compilation, path: []const u8) error{OutOfMemory}!void {
        const arena = unit.arena.allocator();
        const found = try language.embed.scan(arena, unit.src);
        if (found.len == 0) return;
        const import_root = std.fs.path.dirname(path) orelse ".";
        const roots: language.embed.Roots = .{ .io = self.files.io, .import_root = import_root, .root = self.files.embed_root orelse import_root };
        try language.embed.resolve(arena, roots, std.fs.path.basename(path), found);
        unit.src.embeds = found;
    }

    fn checkSingle(self: *Session, unit: *language.Compilation, library: bool) language.diagnostic.Error!void {
        try unit.parseCached(self.syntaxCache());
        if (self.graph.settings.validation.ownership_reports) return unit.checkForOwnershipAudit(library);
        if (library and !unit.declaresMain()) {
            const program = try unit.checkLibraryProgram();
            unit.program = program;
            return;
        }
        try unit.checkWithCache(self.semanticCache());
    }

    /// Load `entry` (a module name: the file stem) and check it. On a source error
    /// the rendered diagnostics are appended to `report` and `SourceError` returns.
    pub fn check(self: *Session, allocator: std.mem.Allocator, entry: []const u8, report: *std.ArrayList(u8)) Error!Checked {
        try self.declare(allocator, entry, report);
        return self.checkDeclared(allocator, report);
    }

    /// Read modules through `given` (a command's generated inputs, its embed root and the header records of its syntax cache) instead
    /// of the session's own files. `given` and what it points at outlive every load of this session.
    pub fn useProvider(self: *Session, given: language.project.Provider) void {
        self.entry.provider = given;
    }

    /// Load `entry`'s module graph (a module name: the file stem) and parse nothing: the first half of `declare`, for a command that
    /// runs its own steps (its configured policy, its stored verdict) between loading and indexing. The loader's own errors return
    /// as they are, so the command words them; `loadFailure` is the words `declare` uses.
    pub fn loadModules(self: *Session, allocator: std.mem.Allocator, entry: []const u8) (language.project.LoadError || error{OutOfMemory})!void {
        self.entry.name = entry;
        const open_mark = self.phaseMark();
        if (self.caches.ownership) |cache| try cache.open(entry);
        self.addPhase("ownership_cache_open", open_mark);
        if (self.entry.suffix.len != 0) self.entry.file = try language.project.modulePath(allocator, entry);
        if (self.graph.profile) |profile| profile.begin("load", false);
        defer if (self.graph.profile) |profile| profile.end();
        self.openDigests();
        try self.project.load(self.provider(), entry, self.graph.settings.options);
        self.saveDigests();
    }

    /// Parse the loaded modules and build their interface index: the second half of `declare`. The syntax cache is fitted to the project
    /// first, as a command that indexes without a session does. A source error leaves the project's problem for the caller to render.
    pub fn indexModules(self: *Session) (language.diagnostic.Error || error{IncompleteProject})!void {
        if (self.caches.frontend) |*state| state.frontend.fitProject(self.project.counts.bytes);
        const complete = self.graph.settings.validation.complete;
        self.graph.index = try language.interfaces.buildWithMode(&self.project, .{
            .cache = self.graph.resident.syntax,
            .frontend = self.syntaxCache(),
            .timing = self.graph.profile,
            .mode = if (complete) .eager else self.graph.syntax_mode,
        });
        self.observeShadow(self.entry.name);
    }

    /// Load `entry`'s module graph and check its declarations alone: every module
    /// parses and its exported interface resolves, no body is checked
    /// (`interfaceIndex` is then valid). On a source error the rendered
    /// diagnostics are appended to `report` and `SourceError` returns.
    pub fn declare(self: *Session, allocator: std.mem.Allocator, entry: []const u8, report: *std.ArrayList(u8)) Error!void {
        self.loadModules(allocator, entry) catch |err| return self.loadFailure(allocator, err, report);
        self.indexModules() catch |err| return self.loadFailure(allocator, err, report);
    }

    /// Let the shadow compare the interfaces of the merged program, once `declare` has had the shadow describe the syntax.
    fn observeMerged(self: *Session) void {
        const shadow = self.caches.shadow orelse return;
        const compilation = &self.graph.compilation;
        shadow.observeInterfaces(.{ .index = &self.graph.index, .src = compilation.src, .syntax = compilation.syntax, .entry = self.entry.name });
    }

    /// Let the shadow compare the checks of the modules, once the bodies are checked: the keys the front end prepared for them.
    fn observeChecked(self: *Session) void {
        const shadow = self.caches.shadow orelse return;
        const state = self.caches.frontend orelse return;
        const prepared = state.request.prepared orelse return;
        const compilation = &self.graph.compilation;
        shadow.observeChecks(.{
            .index = &self.graph.index,
            .src = compilation.src,
            .syntax = compilation.syntax,
            .prepared = prepared,
            .outputs = .{
                .produced = state.request.produced,
                .diagnostics = compilation.diagnostics.items.items,
                .rendering = .{ .options = self.graph.settings.options, .format = self.graph.settings.format },
                .program = compilation.program,
            },
            .entry = self.entry.name,
            .contracts = contractsOf(&state),
        });
    }

    /// The contracts the front end prepares dependency contexts under.
    fn contractsOf(state: *const reuse.State) language.semantic_key.Contracts {
        return .{ .build = state.semantic.context.contract, .mutation = state.semantic.context.mutation_contract };
    }

    /// Let the engine decide which modules' prepared keys hold (`SELKA_ENGINE_DECIDE_COMPILER`), before the front end opens its
    /// per-module plan.
    fn beginDeciding(self: *Session) void {
        const shadow = self.caches.shadow orelse return;
        if (!shadow.deciding()) return;
        const state = if (self.caches.frontend) |*kept| kept else return;
        const compilation = &self.graph.compilation;
        self.graph.index.decider = shadow.beginDeciding(.{
            .merged = .{ .index = &self.graph.index, .src = compilation.src, .syntax = compilation.syntax, .entry = self.entry.name },
            .contracts = contractsOf(state),
        });
    }

    /// Tell the shadow what the verify sampling of the pass stand-in compared and found.
    fn noteVerifiedPasses(self: *Session) void {
        const shadow = self.caches.shadow orelse return;
        const state = self.caches.frontend orelse return;
        const verify = state.request.policy.verify;
        shadow.notePassesVerified(verify.compared, verify.mismatched, verify.first, self.entry.name);
    }

    /// Let the engine record the keys the front end computed for the modules it did not decide, once the keys are prepared.
    fn settleDecided(self: *Session) void {
        const shadow = self.caches.shadow orelse return;
        if (!shadow.deciding()) return;
        const state = if (self.caches.frontend) |*kept| kept else return;
        const prepared = state.request.prepared orelse return;
        const compilation = &self.graph.compilation;
        shadow.settleDecided(.{
            .merged = .{ .index = &self.graph.index, .src = compilation.src, .syntax = compilation.syntax, .entry = self.entry.name },
            .prepared = prepared,
            .contracts = contractsOf(state),
        });
    }

    /// Let the engine's shadow compare its answers about the loaded project with the front end's (see `frontend_shadow.zig`).
    /// The modules this session overlays are read by the engine's world as the session reads them (`overlays`, `overlaidText`).
    fn observeShadow(self: *Session, entry: []const u8) void {
        const shadow = self.caches.shadow orelse return;
        shadow.observe(.{ .project = &self.project, .index = &self.graph.index, .entry = entry, .options = self.graph.settings.options });
    }

    /// Whether the engine's shadow is watching this session's lowering, so the build should note what it lowers
    /// (`lowering_cache.Observed`): it compares (it does not only decide the front end's keys), and the session overlays no
    /// sources.
    pub fn shadowsLowering(self: *const Session) bool {
        const shadow = self.caches.shadow orelse return false;
        return shadow.comparing() and self.graph.settings.providers.len == 0 and self.entry.suffix.len == 0;
    }

    /// The checked-body parts lowering keys its functions by, when the engine decides this session's modules (`frontend_shadow.Shadow.partSource`).
    pub fn bodyParts(self: *const Session) ?lowering_cache.PartSource {
        const shadow = self.caches.shadow orelse return null;
        return shadow.partSource();
    }

    /// Hand the engine's shadow to the build, which keeps it for the stages after the front end (the optimizer's joins) and ends
    /// it; this session then has none. Null when the shadow is off.
    pub fn detachShadow(self: *Session) ?*shadow_rules.Shadow {
        const held = self.caches.shadow;
        self.caches.shadow = null;
        return held;
    }

    /// Let the shadow compare the engine's answers about how the program lowered with what lowering did (see
    /// `lowering_shadow.zig`). Call after the program is lowered, with what the build noted.
    pub fn observeLowering(self: *Session, lowered: shadow_rules.Shadow.Lowered) void {
        const shadow = self.caches.shadow orelse return;
        if (!self.shadowsLowering()) return shadow.count(.lower_skipped);
        var named = lowered;
        named.entry = self.entry.name;
        shadow.observeLowering(named);
    }

    /// Merge the modules `declare` loaded into one program (`graph.compilation`), without checking a body. A command that decides
    /// between an executable and a library check by what the program declares (`compilation.declaresMain()`) merges first, then calls
    /// `checkMerged` or its library check.
    pub fn mergeDeclared(self: *Session, allocator: std.mem.Allocator, report: *std.ArrayList(u8)) Error!void {
        if (self.graph.profile) |profile| profile.begin("merge", false);
        self.graph.compilation = language.project_compile.Compilation.init(&self.graph.index) catch |err| return self.loadFailure(allocator, err, report);
        self.graph.compilation.diagnostics.hole_mode = self.graph.settings.validation.holes;
        self.graph.compilation.diagnostics.template_probes = self.graph.settings.validation.template_probes;
        if (self.graph.profile) |profile| profile.end();
        self.observeMerged();
    }

    /// Check the bodies of the graph `declare` loaded; diagnostics as `check`.
    pub fn checkDeclared(self: *Session, allocator: std.mem.Allocator, report: *std.ArrayList(u8)) Error!Checked {
        try self.mergeDeclared(allocator, report);
        return self.checkMerged(allocator, report);
    }

    /// Check the program `mergeDeclared` built: the engine-decided keys, the check, the passes and the ownership validation.
    pub fn checkMerged(self: *Session, allocator: std.mem.Allocator, report: *std.ArrayList(u8)) Error!Checked {
        self.checkBodies() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                const shadow = self.graph.compilation.holeProgram(false) catch |hole_err| switch (hole_err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.SourceError, error.InternalError => null,
                };
                try self.renderRefused(allocator, .{ .items = self.graph.compilation.diagnostics.items.items, .shadow = shadow, .src = self.graph.compilation.src }, report);
                return error.SourceError;
            },
        };
        const contracts_mark = self.phaseMark();
        const checked = try self.checkAllocationContracts(allocator, .{ .program = self.graph.compilation.program.?, .src = self.graph.compilation.src }, report);
        self.addPhase("allocation_contracts", contracts_mark);
        return checked;
    }

    /// The check of `checkMerged` without rendering a refusal and without the ownership validation: the engine-decided keys, the bodies, the
    /// passes and the summary table. A command that words a failed check itself (`context` answers about a project that does not check) calls
    /// this and reads `graph.compilation.diagnostics`; the raw error returns.
    pub fn checkBodies(self: *Session) language.project_compile.CheckError!void {
        self.beginDeciding();
        const begin_mark = self.phaseMark();
        if (self.caches.frontend) |*state| {
            try state.begin(&self.project, self.project.arena.allocator());
            if (self.caches.ownership) |cache| if (!self.graph.settings.validation.complete) cache.configure(&state.request, state.request.policy.demand, !self.graph.settings.allocation_contracts);
            state.request.policy.passes = self.caches.passes;
            state.request.policy.verify = .{ .every = self.caches.verify_every };
        }
        self.addPhase("frontend_cache_begin", begin_mark);
        if (self.graph.profile) |profile| profile.begin("check", true);
        self.graph.compilation.checkWithCache(self.semanticCache()) catch |err| {
            if (err != error.OutOfMemory) self.settleDecided();
            return err;
        };
        if (self.graph.profile) |profile| profile.end();
        self.settleDecided();
        self.noteVerifiedPasses();
        self.observeChecked();
        const finish_mark = self.phaseMark();
        if (self.caches.frontend) |*state| try state.finish(&self.project);
        self.addPhase("frontend_cache_finish", finish_mark);
    }

    /// The library check of a command that words its own failures and validates nothing: every body, effect and boundary of the merged
    /// program with no `main` required, through no cache (`lint`).
    pub fn checkLibraryBodies(self: *Session) language.project_compile.CheckError!void {
        self.graph.compilation.program = try self.graph.compilation.checkLibraryProgram();
    }

    /// What a refused check renders: its diagnostics, the program `holeProgram` made of it (null for none), and whether other
    /// modules' holes fold into one line (`renderFolded`).
    const Refused = struct { items: []const language.diagnostic.Diagnostic, shadow: ?language.typed.Program, src: language.source.Source, folded: bool = false };

    /// Render a refused check: its diagnostics, then the ownership errors of the program with its holes as typed nodes. When the
    /// refusal was a body that failed to check, the ownership errors of the bodies that did check stand among the refused check's
    /// own diagnostics in source order (F-RC-214).
    fn renderRefused(self: *Session, allocator: std.mem.Allocator, refused: Refused, report: *std.ArrayList(u8)) error{OutOfMemory}!void {
        if (refused.shadow) |program| if (recovered_ownership.recovered(program)) {
            var scratch = std.heap.ArenaAllocator.init(allocator);
            defer scratch.deinit();
            const found = try recovered_ownership.collect(scratch.allocator(), self.project.arena.child_allocator, program, refused.src);
            const all = try recovered_ownership.merged(scratch.allocator(), refused.items, found);
            return if (refused.folded) self.renderFolded(allocator, all, refused.src, report) else self.renderAll(allocator, all, refused.src, report);
        };
        if (refused.folded) try self.renderFolded(allocator, refused.items, refused.src, report) else try self.renderAll(allocator, refused.items, refused.src, report);
        try self.holeOwnership(allocator, refused.shadow, refused.src, report);
    }

    /// A refused check whose only errors are typed holes also reports the ownership errors of the same
    /// program checked with each hole as a typed node (`shadow`, null when there is none): finished code
    /// is not hidden behind an unfinished function (F-G2b-17).
    fn holeOwnership(self: *Session, allocator: std.mem.Allocator, shadow: ?language.typed.Program, src: language.source.Source, report: *std.ArrayList(u8)) error{OutOfMemory}!void {
        const program = shadow orelse return;
        _ = try @import("single_owner.zig").validate(allocator, self.project.arena.child_allocator, program, src, self.graph.settings.format, report);
    }

    fn checkAllocationContracts(self: *Session, allocator: std.mem.Allocator, checked: Checked, report: *std.ArrayList(u8)) Error!Checked {
        // The stand-in count judges the instances itself and refuses nothing (`template_stand_ins_command.zig`).
        if (self.graph.settings.validation.template_probes == .every) return checked;
        if (self.graph.settings.validation.ownership_reports) {
            try report.appendSlice(allocator, try self.warnings(allocator));
            if (!try @import("single_owner.zig").audit(allocator, checked.program, checked.src, report)) return error.SourceError;
        }
        const validation_mark = self.phaseMark();
        const valid = if (self.graph.settings.validation.ownership_reports) true else if (self.caches.ownership) |cache|
            try cache.validate(allocator, checked.program, checked.src, self.graph.settings.format, report)
        else
            try @import("single_owner.zig").validate(allocator, self.project.arena.child_allocator, checked.program, checked.src, self.graph.settings.format, report);
        self.addPhase("ownership_validation", validation_mark);
        if (!valid) return error.SourceError;
        if (!self.graph.settings.allocation_contracts) return checked;
        const promises_mark = self.phaseMark();
        const failures = try allocation_contract.collectProgram(allocator, checked.program, checked.src);
        self.addPhase("noalloc_promises", promises_mark);
        for (failures) |failure| {
            const item = try allocation_contract.diagnostic(allocator, failure);
            language.friction_session.note(item);
            try report.appendSlice(allocator, try language.diagnostic_output.render(allocator, item, checked.src, self.graph.settings.format));
        }
        if (failures.len != 0) return error.SourceError;
        return checked;
    }

    /// The file provider: the disk, with `entry.suffix` appended to the entry file when set.
    fn provider(self: *Session) language.project.Provider {
        if (self.entry.provider) |given| return given;
        self.files.records = if (self.syntaxCache()) |cache| cache.records() else null;
        if (self.entry.suffix.len == 0 and self.graph.settings.providers.len == 0) return self.files.provider();
        const trusting = self.files.digests != null;
        return .{
            .context = &self.files,
            .read = readEntry,
            .embed = language.project_files.Files.readEmbed,
            .records = self.files.records,
            .vouch = if (trusting) vouchEntry else null,
            .learned = if (trusting) learnedEntry else null,
        };
    }

    /// The digest the stat-trusted memo holds for a module read from disk; never for a module this session reads from memory (a
    /// provider's text, or the entry file with its stub appended), whose bytes the file's tuple does not describe.
    fn vouchEntry(context: ?*anyopaque, relative: []const u8, bytes: []const u8) ?[32]u8 {
        const files: *language.project_files.Files = @ptrCast(@alignCast(context.?));
        const self: *Session = @fieldParentPtr("files", files);
        const memo = files.digests orelse return null;
        if (overlays(self, relative)) return null;
        return memo.vouch(relative, bytes);
    }

    /// Hand the memo the digest the loader took of a module read from disk.
    fn learnedEntry(context: ?*anyopaque, relative: []const u8, digest: [32]u8) void {
        const files: *language.project_files.Files = @ptrCast(@alignCast(context.?));
        const self: *Session = @fieldParentPtr("files", files);
        const memo = files.digests orelse return;
        if (overlays(self, relative)) return;
        memo.learned(relative, digest);
    }

    /// Open the stat-trusted digest memo of this project from the work directory, when the session has a cache and reads its own files.
    fn openDigests(self: *Session) void {
        if (self.entry.provider != null) return;
        const state = if (self.caches.frontend) |*kept| kept else return;
        const arena = self.project.arena.allocator();
        const memo = arena.create(language.file_digests.Memo) catch return;
        memo.* = language.file_digests.Memo.init(arena, .{
            .io = self.files.io,
            .window_ns = digest_window_ns,
            .verify = self.caches.verify_every != 0,
        });
        if (state.frontend.read(language.file_digests.Memo.key(self.files.root))) |stored| {
            defer state.semantic.allocator.free(stored);
            memo.decode(stored);
        } else |_| {}
        self.files.digests = memo;
    }

    /// Store the memo when this load taught it a digest.
    fn saveDigests(self: *Session) void {
        const memo = self.files.digests orelse return;
        const state = if (self.caches.frontend) |*kept| kept else return;
        if (!memo.dirty) return;
        memo.prune();
        const bytes = memo.encode(self.project.arena.allocator()) catch return;
        state.frontend.writeRecord(language.file_digests.Memo.key(self.files.root), bytes) catch return;
        memo.dirty = false;
    }

    fn readEntry(context: ?*anyopaque, allocator: std.mem.Allocator, relative: []const u8, limit: usize) language.project.ReadError![]u8 {
        const files: *language.project_files.Files = @ptrCast(@alignCast(context.?));
        const self: *Session = @fieldParentPtr("files", files);
        const bytes = try self.readModule(context, allocator, relative, limit);
        if (!std.mem.eql(u8, relative, self.entry.file)) return bytes;
        defer allocator.free(bytes);
        return std.mem.concat(allocator, u8, &.{ bytes, self.entry.suffix }) catch error.OutOfMemory;
    }

    fn readModule(self: *Session, context: ?*anyopaque, allocator: std.mem.Allocator, relative: []const u8, limit: usize) language.project.ReadError![]u8 {
        for (self.graph.settings.providers) |override| {
            if (!std.mem.eql(u8, relative, override.path)) continue;
            if (override.text.len > limit) return error.TooLarge;
            return allocator.dupe(u8, override.text) catch error.OutOfMemory;
        }
        return language.project_files.Files.read(context, allocator, relative, limit);
    }

    /// Whether this session reads project-relative `path` from memory: a provider's text, or the entry file with its stub appended.
    fn overlays(context: *anyopaque, path: []const u8) bool {
        const self: *Session = @ptrCast(@alignCast(context));
        for (self.graph.settings.providers) |override| if (std.mem.eql(u8, path, override.path)) return true;
        return self.entry.suffix.len != 0 and std.mem.eql(u8, path, self.entry.file);
    }

    /// Rewrite the project's load problem, before it is printed, where the session knows more than the loader: a
    /// module that is not there names the import root it was looked for under (F-6).
    pub fn explainProblem(self: *Session) Error!void {
        if (self.project.problem) |*problem| if (std.mem.eql(u8, problem.code, "E_MODULE_READ")) {
            if (try self.rootedModuleRead(problem.*)) |message| problem.message = message;
        } else if (problem.site.module < self.project.modules.items.len) {
            const own = self.project.modules.items[problem.site.module].src;
            try language.project_module_import.explainProblem(self.project.arena.allocator(), .{ .io = self.files.io, .path = self.files.root }, problem, own);
        };
    }

    /// The `E_MODULE_READ` message of a module that is not there, naming the import root it was looked for under and
    /// what set that root (a `selka.json` in it, or none), and, when the importing module's own directory holds the
    /// file, the import that reaches it (F-6). Null for any other read failure, whose message stays.
    fn rootedModuleRead(self: *Session, problem: language.project.Problem) Error!?[]const u8 {
        const prefix = "cannot load ";
        const suffix = ": NotFound";
        if (!std.mem.startsWith(u8, problem.message, prefix) or !std.mem.endsWith(u8, problem.message, suffix)) return null;
        const arena = self.project.arena.allocator();
        const path = problem.message[prefix.len .. problem.message.len - suffix.len];
        const root = self.files.root;
        const manifest = try std.fs.path.join(arena, &.{ root, language.project_config.config_name });
        const configured = if (std.Io.Dir.cwd().access(self.files.io, manifest, .{})) true else |_| false;
        const why = if (configured)
            try std.fmt.allocPrint(arena, "the directory of `{s}`", .{manifest})
        else
            try std.fmt.allocPrint(arena, "no `{s}` sets it", .{language.project_config.config_name});
        const searched = try std.fmt.allocPrint(arena, "cannot load {s}: there is no `{s}` under the import root `{s}` ({s})", .{ path, path, root, why });
        // A module whose name has a directory (`src.lib_test`) imports from the root, not from that directory.
        if (problem.site.module >= self.project.modules.items.len) return searched;
        const importer = self.project.modules.items[problem.site.module].name;
        const dot = std.mem.lastIndexOfScalar(u8, importer, '.') orelse return searched;
        const directory = try std.mem.replaceOwned(u8, arena, importer[0..dot], ".", "/");
        const beside = try std.fs.path.join(arena, &.{ root, directory, path });
        if (std.Io.Dir.cwd().access(self.files.io, beside, .{})) {} else |_| return searched;
        const stem = product.chopSource(path);
        const dotted = try std.mem.replaceOwned(u8, arena, stem, "/", ".");
        const advice = try std.fmt.allocPrint(arena, "{s}; `{s}/{s}` is beside the importing module: import it as `{s}.{s}`, or move `{s}` into `{s}`", .{
            searched,
            directory,
            path,
            importer[0..dot],
            dotted,
            language.project_config.config_name,
            directory,
        });
        return advice;
    }

    /// The bytes this session reads for an overlaid `path`, exactly as `readEntry` gives them to the loader.
    fn overlaidText(context: *anyopaque, arena: std.mem.Allocator, path: []const u8) ?[]const u8 {
        const self: *Session = @ptrCast(@alignCast(context));
        return readEntry(&self.files, arena, path, 64 << 20) catch null;
    }

    /// Render why the module graph could not be loaded into `report` and answer `SourceError`: the project's own
    /// problem when it has one (a module it could not find also names the import root it searched, F-6), else the
    /// load error's name.
    pub fn loadFailure(self: *Session, allocator: std.mem.Allocator, err: anyerror, report: *std.ArrayList(u8)) Error {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try self.explainProblem();
        if (self.project.problem != null) {
            language.friction_session.noteProject(&self.project);
            const text = language.diagnostic_output.renderProject(allocator, &self.project, self.graph.settings.format) catch return error.OutOfMemory;
            defer allocator.free(text);
            try report.appendSlice(allocator, text);
        } else if (err == error.InvalidModuleName) {
            try report.print(allocator, "error: invalid module name '{s}'; use letters, digits or '_' in each dot-separated segment\n", .{self.entry.name});
        } else {
            try report.print(allocator, "error: cannot load the program: {s}\n", .{@errorName(err)});
        }
        return error.SourceError;
    }
};

// spec-case: COMPILER-SHARED-CACHE-1
test "enableSharedCache rejects unusable configured storage after opening private caches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "blocked", .data = "regular-file" });
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    try environment.put(language.shared_artifact_store.environment_variable, try std.fs.path.join(a, &.{ root, "blocked" }));
    var session = Session.init(std.testing.allocator, std.testing.io, root);
    defer session.deinit();
    try session.enableCache(std.testing.allocator, try std.fs.path.join(a, &.{ root, "private" }));
    try std.testing.expectError(error.WriteFailed, session.enableSharedCache(&environment));
    try std.testing.expect(session.caches.frontend.?.shared == null);
}

test "G4c a session whose environment names a compiler store gives its engines the tier, and one whose store is off gives them none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    try environment.put(language.shared_artifact_store.environment_variable, try std.fs.path.join(a, &.{ root, "store" }));
    var shared = Session.init(std.testing.allocator, std.testing.io, root);
    defer shared.deinit();
    try shared.enableCache(std.testing.allocator, try std.fs.path.join(a, &.{ root, "work-shared" }));
    try shared.enableSharedCache(&environment);
    try std.testing.expect(shared.caches.ownership.?.proofs.?.machine.records != null);
    try std.testing.expect(shared.caches.shadow.?.machine.records != null);
    try std.testing.expect(shared.caches.shadow.?.runner.registry.entries[0].shared);
    try environment.put(language.shared_artifact_store.environment_variable, "");
    var alone = Session.init(std.testing.allocator, std.testing.io, root);
    defer alone.deinit();
    try alone.enableCache(std.testing.allocator, try std.fs.path.join(a, &.{ root, "work-alone" }));
    try alone.enableSharedCache(&environment);
    try std.testing.expect(alone.caches.ownership.?.proofs.?.machine.records == null);
    try std.testing.expect(alone.caches.shadow.?.machine.records == null);
}

test "ownership proofs of an entry file are scoped by its root-relative path, whatever its spelling" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "app");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app/main.selka", .data = "func main() -> int:\n    return 0\n" });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var session = Session.init(std.testing.allocator, std.testing.io, root);
    defer session.deinit();
    session.files.embed_root = root;
    const direct = try std.fs.path.join(a, &.{ root, "app", "main.selka" });
    const detour = try std.fs.path.join(a, &.{ root, "app", "..", "app", "main.selka" });
    try std.testing.expectEqualStrings("app/main.selka", try session.ownershipScope(a, direct));
    try std.testing.expectEqualStrings("app/main.selka", try session.ownershipScope(a, detour));
    // The build's own name for the entry wins when it set one.
    session.files.entry_key = "named/by/the/build.selka";
    try std.testing.expectEqualStrings("named/by/the/build.selka", try session.ownershipScope(a, direct));
}

/// Split a path such as `dir/prog.selka` into the loader's root directory and
/// module name (`dir`, `prog`).
pub fn entryOf(path: []const u8) struct { root: []const u8, module: []const u8 } {
    const root = std.fs.path.dirname(path) orelse ".";
    const base = std.fs.path.basename(path);
    const module = product.sourceStem(base);
    return .{ .root = root, .module = module };
}

/// The 1-based line and column of byte `offset` in the merged source, mapped
/// back to the file it came from.
pub const Position = struct { path: []const u8, line: u32, column: u32 };

/// Resolve a merged-source span start to the original file, line and column.
pub fn position(src: language.source.Source, span: language.source.Span) Position {
    var file = src;
    var local = span;
    if (src.origins.len != 0) {
        if (src.originalSpan(span)) |found| {
            file = src.origins[found.input].original;
            local = found.span;
        } else |_| {}
    }
    const starts = file.line_starts;
    var low: usize = 0;
    var high: usize = starts.len;
    while (high - low > 1) {
        const middle = (low + high) / 2;
        if (starts[middle] <= local.start) low = middle else high = middle;
    }
    return .{ .path = file.path, .line = @intCast(low + 1), .column = @intCast(local.start - starts[low] + 1) };
}
