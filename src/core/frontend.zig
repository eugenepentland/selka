//! The new core's view of the existing front end (decision N3): load one entry
//! file and its imports, check them, and hand back the checked `typed.Program`
//! with the merged source its spans index. Nothing below the checker (bytecode,
//! QBE, the native build driver) is reached from here.
const std = @import("std");
const language = @import("mylang");
const reuse = @import("frontend_reuse.zig");

/// Identity of all production compiler/runtime/property sources and toolchain.
pub const compiler_identity = reuse.compiler_identity;
/// Actual front-end cache work observed during this session.
pub const Statistics = reuse.Statistics;
/// One module source supplied by the project test runner, borrowed until deinit.
pub const Provider = struct { path: []const u8, text: []const u8 };

const Settings = struct {
    options: language.project.Options = .{},
    entry: ?[]const u8 = null,
    providers: []const Provider = &.{},
    /// How diagnostics are rendered into a report: terminal text or `diagnostic-v1` lines.
    format: language.diagnostic_output.Format = .text,
    /// Name a header-less file by the path it was given, as the `mylang` CLI does,
    /// rather than by its base name (`mylang-core`).
    given_path: bool = false,
};
const Graph = struct {
    index: language.interfaces.Index = undefined,
    compilation: language.project_compile.Compilation = undefined,
    settings: Settings = .{},
    profile: ?*language.timings.Profile = null,
};

/// The checked program and the merged source its spans point into.
pub const Checked = struct {
    program: language.typed.Program,
    src: language.source.Source,
};

/// Why a load stopped: diagnostics were already rendered into `report`.
pub const Error = error{ SourceError, OutOfMemory, InternalError };

/// Owns the project arena every checked node lives in; keep it alive while the
/// IR builder reads the program, and release it with `deinit`.
pub const Session = struct {
    project: language.project.Project,
    graph: Graph = .{},
    files: language.project_files.Files,
    /// A file with no `module` header is checked alone, as `mylang build` does.
    single: ?language.Compilation = null,
    /// Text appended to the entry file as it is read: `mylang-core test` appends the
    /// old runner's stub `main` to a library file so the file can be checked as a program.
    entry_suffix: []const u8 = "",
    /// The entry module's file name relative to the root, set by `check` while a suffix is in use.
    entry_file: []const u8 = "",
    cache: ?reuse.State = null,

    /// Prepare to load the module graph rooted at `root` (the entry file's directory).
    pub fn init(allocator: std.mem.Allocator, io: std.Io, root: []const u8) Session {
        return .{ .project = language.project.Project.init(allocator), .files = .{ .io = io, .root = root } };
    }

    /// Release the project arena and everything checked from it.
    pub fn deinit(self: *Session) void {
        if (self.cache) |*state| state.deinit();
        if (self.single) |*unit| unit.deinit();
        self.project.deinit();
    }

    /// Enable shared syntax/body/summary reuse under `root`. Keep the session at
    /// its current address after this call, as its index and cache borrow it.
    pub fn enableCache(self: *Session, allocator: std.mem.Allocator, root: []const u8) error{OutOfMemory}!void {
        self.cache = try reuse.State.init(allocator, self.files.io, root);
        self.cache.?.bind();
    }

    /// Configure loader budgets and the entry's module name for project paths.
    pub fn configureProject(self: *Session, options: language.project.Options, entry: ?[]const u8) void {
        self.graph.settings.options = options;
        self.graph.settings.entry = entry;
    }

    /// Render diagnostics as `format` (`mylang run --diagnostics=json`), and name a
    /// header-less file by the path it was given, as the `mylang` CLI does.
    pub fn setFormat(self: *Session, format: language.diagnostic_output.Format) void {
        self.graph.settings.format = format;
        self.graph.settings.given_path = true;
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

    fn renderAll(self: *const Session, allocator: std.mem.Allocator, items: []const language.diagnostic.Diagnostic, src: language.source.Source, out: *std.ArrayList(u8)) error{OutOfMemory}!void {
        for (items) |item| {
            const text = try language.diagnostic_output.render(allocator, item, src, self.graph.settings.format);
            defer allocator.free(text);
            try out.appendSlice(allocator, text);
        }
    }

    /// Overlay exact relative module paths with explicit test-provider sources.
    pub fn setProviders(self: *Session, providers: []const Provider) void {
        self.graph.settings.providers = providers;
    }

    /// The fresh interface index, valid after a successful module check.
    pub fn interfaceIndex(self: *Session) *language.interfaces.Index {
        return &self.graph.index;
    }

    /// Validation-only commands can omit unchanged bodies; builds/tests retain
    /// the default complete typed trees and use summaries for pass facts only.
    pub fn validationOnly(self: *Session) void {
        if (self.cache) |*state| state.request.facts_only = false;
    }

    /// Attach opt-in phase instrumentation without changing checking behavior.
    pub fn setProfile(self: *Session, profile: *language.timings.Profile) void {
        self.graph.profile = profile;
        if (self.cache) |*state| state.semantic.context.timing = profile;
    }

    /// Actual cache counters for this invocation, or zero when reuse is off.
    pub fn statistics(self: *const Session) Statistics {
        return if (self.cache) |*state| state.statistics() else .{};
    }

    fn syntaxCache(self: *Session) ?*language.frontend_cache.Cache {
        return if (self.cache) |*state| &state.frontend else null;
    }

    fn semanticCache(self: *Session) ?*language.semantic_cache.Cache {
        return if (self.cache) |*state| &state.semantic else null;
    }

    /// Check `path` alone when it opens without a `module` header, else as the
    /// entry of its module graph (`check`).
    pub fn checkFile(self: *Session, allocator: std.mem.Allocator, path: []const u8, report: *std.ArrayList(u8)) (Error || error{ReadFailed})!Checked {
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.files.io, path, allocator, .limited(64 << 20)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try report.print(allocator, "error: cannot read {s}: {s}\n", .{ path, @errorName(err) });
                return error.ReadFailed;
            },
        };
        if (language.opensAsModule(bytes)) return self.check(allocator, self.graph.settings.entry orelse entryOf(path).module, report);
        const full = if (self.entry_suffix.len == 0) bytes else try std.mem.concat(allocator, u8, &.{ bytes, self.entry_suffix });
        const name = if (self.graph.settings.given_path) path else std.fs.path.basename(path);
        self.single = try language.Compilation.init(self.project.arena.child_allocator, name, full);
        const unit = &self.single.?;
        try self.attachEmbeds(unit, path);
        self.checkSingle(unit) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try self.renderAll(allocator, unit.diagnostics.items, unit.src, report);
                return error.SourceError;
            },
        };
        return .{ .program = unit.program.?, .src = unit.src };
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

    fn checkSingle(self: *Session, unit: *language.Compilation) language.diagnostic.Error!void {
        try unit.parseCached(self.syntaxCache());
        try unit.checkWithCache(self.semanticCache());
    }

    /// Load `entry` (a module name: the file stem) and check it. On a source error
    /// the rendered diagnostics are appended to `report` and `SourceError` returns.
    pub fn check(self: *Session, allocator: std.mem.Allocator, entry: []const u8, report: *std.ArrayList(u8)) Error!Checked {
        if (self.entry_suffix.len != 0) self.entry_file = language.project.modulePath(allocator, entry) catch |err| return self.loadFailure(allocator, err, report);
        if (self.graph.profile) |profile| profile.begin("load", false);
        self.project.load(self.provider(), entry, self.graph.settings.options) catch |err| return self.loadFailure(allocator, err, report);
        if (self.graph.profile) |profile| profile.end();
        self.graph.index = language.interfaces.buildWithCacheTimed(&self.project, null, self.syntaxCache(), self.graph.profile) catch |err| return self.loadFailure(allocator, err, report);
        if (self.graph.profile) |profile| profile.begin("merge", false);
        self.graph.compilation = language.project_compile.Compilation.init(&self.graph.index) catch |err| return self.loadFailure(allocator, err, report);
        if (self.graph.profile) |profile| profile.end();
        if (self.cache) |*state| try state.begin(&self.project, self.project.arena.allocator());
        if (self.graph.profile) |profile| profile.begin("check", true);
        self.graph.compilation.checkWithCache(self.semanticCache()) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try self.renderAll(allocator, self.graph.compilation.diagnostics.items.items, self.graph.compilation.src, report);
                return error.SourceError;
            },
        };
        if (self.graph.profile) |profile| profile.end();
        if (self.cache) |*state| try state.finish(&self.project);
        return .{ .program = self.graph.compilation.program.?, .src = self.graph.compilation.src };
    }

    /// The file provider: the disk, with `entry_suffix` appended to the entry file when set.
    fn provider(self: *Session) language.project.Provider {
        if (self.entry_suffix.len == 0 and self.graph.settings.providers.len == 0) return self.files.provider();
        return .{ .context = &self.files, .read = readEntry, .embed = language.project_files.Files.readEmbed };
    }

    fn readEntry(context: ?*anyopaque, allocator: std.mem.Allocator, relative: []const u8, limit: usize) language.project.ReadError![]u8 {
        const files: *language.project_files.Files = @ptrCast(@alignCast(context.?));
        const self: *Session = @fieldParentPtr("files", files);
        const bytes = try self.readModule(context, allocator, relative, limit);
        if (!std.mem.eql(u8, relative, self.entry_file)) return bytes;
        defer allocator.free(bytes);
        return std.mem.concat(allocator, u8, &.{ bytes, self.entry_suffix }) catch error.OutOfMemory;
    }

    fn readModule(self: *Session, context: ?*anyopaque, allocator: std.mem.Allocator, relative: []const u8, limit: usize) language.project.ReadError![]u8 {
        for (self.graph.settings.providers) |override| {
            if (!std.mem.eql(u8, relative, override.path)) continue;
            if (override.text.len > limit) return error.TooLarge;
            return allocator.dupe(u8, override.text) catch error.OutOfMemory;
        }
        return language.project_files.Files.read(context, allocator, relative, limit);
    }

    fn loadFailure(self: *Session, allocator: std.mem.Allocator, err: anyerror, report: *std.ArrayList(u8)) Error {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        if (self.project.problem != null) {
            const text = language.diagnostic_output.renderProject(allocator, &self.project, self.graph.settings.format) catch return error.OutOfMemory;
            defer allocator.free(text);
            try report.appendSlice(allocator, text);
        } else {
            try report.print(allocator, "error: cannot load the program: {s}\n", .{@errorName(err)});
        }
        return error.SourceError;
    }
};

/// Split a path such as `dir/prog.my` into the loader's root directory and
/// module name (`dir`, `prog`).
pub fn entryOf(path: []const u8) struct { root: []const u8, module: []const u8 } {
    const root = std.fs.path.dirname(path) orelse ".";
    const base = std.fs.path.basename(path);
    const module = if (std.mem.endsWith(u8, base, ".my")) base[0 .. base.len - 3] else base;
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
