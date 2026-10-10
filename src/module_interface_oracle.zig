//! MODULE-INTERFACE-1 driver and oracle. `Whole` loads a project from disk and
//! checks it as one program, the way every command does today, then builds
//! every module's interface from that check. `checkModule` checks one module
//! against its imports' interfaces alone — its own source, and for every other
//! module only the interface text and the facts it carries — and `compare`
//! asserts that result equals the whole-program one: the same diagnostics, the
//! same checked facts and signatures for every function the module's check
//! produced, and the same dependency context for every one of its declarations.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const project_module = @import("project.zig");
const project_files = @import("project_files.zig");
const standard_library = @import("standard_library.zig");
const interfaces = @import("interfaces.zig");
const project_compile = @import("project_compile.zig");
const semantic_cache = @import("semantic_cache.zig");
const semantic_key = @import("semantic_key.zig");
const summary = @import("semantic_summary.zig");
const entry_adapter = @import("entry_adapter.zig");
const iface = @import("module_interface.zig");
const builder = @import("module_interface_build.zig");
const frontend = @import("frontend_runtime.zig");

/// Failures of loading, checking or comparing. `SourceError` means the project
/// did not load or check; its problem or diagnostics are on the value.
pub const Error = frontend.Error;

/// The module a per-module check synthesizes as its entry when the module
/// under check is not the project's entry: it imports that module and has an
/// empty `main`, so the module is checked as an ordinary imported module.
pub const root_module = "mylang_interface_root";
const root_text = "import {s}\n\n\nfunc main() -> int:\n    return 0\n";
/// Appended to an entry with no `main`, as `mylang test` does, so a library or
/// test module checks as a project.
pub const main_stub = "\n\nfunc main() -> int:\n    return 0\n";

/// One source path served from memory instead of disk.
pub const Override = struct { path: []const u8, bytes: []const u8 };

/// A project provider: overrides first, then interface texts by module path,
/// then disk under `root` when set.
const Sources = struct {
    io: std.Io,
    root: ?[]const u8,
    overrides: []const Override,
    library: ?*Library = null,
    assets: ?project_module.Provider = null,

    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, relative: []const u8, limit: usize) project_module.ReadError![]u8 {
        const self: *Sources = @ptrCast(@alignCast(context.?));
        for (self.overrides) |entry| if (std.mem.eql(u8, entry.path, relative)) {
            if (entry.bytes.len > limit) return error.TooLarge;
            return allocator.dupe(u8, entry.bytes);
        };
        if (self.library) |library| if (library.text(relative)) |text| {
            if (text.len > limit) return error.TooLarge;
            return allocator.dupe(u8, text);
        };
        const root = self.root orelse return error.NotFound;
        var files: project_files.Files = .{ .io = self.io, .root = root };
        return project_files.Files.read(&files, allocator, relative, limit);
    }
    fn readEmbed(context: ?*anyopaque, allocator: std.mem.Allocator, module_path: []const u8, literal_path: []const u8, limit: usize) std.mem.Allocator.Error!@import("embed.zig").Read {
        const self: *Sources = @ptrCast(@alignCast(context.?));
        const provider = self.assets orelse return .{ .status = .unreadable };
        const callback = provider.embed orelse return .{ .status = .unreadable };
        return callback(provider.context, allocator, module_path, literal_path, limit);
    }
};

/// A project's import root, its entry module's name, and the entry's source as
/// the check reads it (with the test runner's `main` stub appended when the
/// entry declares no `main`).
pub const Entry = struct {
    /// Import root on disk; empty serves every module from `modules` alone.
    root: []const u8,
    name: []const u8,
    bytes: []const u8,
    /// Other modules served from memory by path, ahead of the disk.
    modules: []const Override = &.{},
    assets: ?project_module.Provider = null,
    limits: project_module.Options = .{},
};

/// A loaded, checked project and what its interfaces are built from. It is
/// heap-allocated because the compilation points into its index and project.
pub const Whole = struct {
    gpa: std.mem.Allocator,
    project: project_module.Project,
    index: interfaces.Index,
    compilation: project_compile.Compilation,
    cache: semantic_cache.Cache,
    request: summary.Request,
    entry: Entry,

    /// Load `entry`'s project, the entry from `entry.bytes` and every other
    /// module from disk under `entry.root`, and check it as one program,
    /// recording every body's facts. On `SourceError` the value is still
    /// returned through `out`, with the project problem or the diagnostics set.
    pub fn open(gpa: std.mem.Allocator, io: std.Io, entry: Entry, out: **Whole) Error!void {
        const self = try gpa.create(Whole);
        out.* = self;
        self.* = .{
            .gpa = gpa,
            .project = project_module.Project.init(gpa),
            .index = undefined,
            .compilation = undefined,
            .cache = semantic_cache.Cache.init(gpa, 0),
            .request = .{ .body_policy = .concrete },
            .entry = entry,
        };
        const arena = self.project.arena.allocator();
        const entry_path = project_module.modulePath(arena, entry.name) catch return error.SourceError;
        const overrides = try arena.alloc(Override, entry.modules.len + 1);
        overrides[0] = .{ .path = entry_path, .bytes = entry.bytes };
        @memcpy(overrides[1..], entry.modules);
        var files: project_files.Files = .{ .io = io, .root = entry.root };
        var sources: Sources = .{
            .io = io,
            .root = if (entry.root.len == 0) null else entry.root,
            .overrides = overrides,
            .assets = entry.assets orelse if (entry.root.len != 0) files.provider() else null,
        };
        const parts: Parts = .of(self);
        try parts.load(&sources);
        try parts.check();
    }

    /// Release everything the project, its check and its interfaces hold.
    pub fn deinit(self: *Whole) void {
        const gpa = self.gpa;
        self.cache.deinit();
        self.project.deinit();
        gpa.destroy(self);
    }

    /// Build every module's interface from this check.
    pub fn buildInterfaces(self: *Whole) Error!builder.Set {
        const arena = self.project.arena.allocator();
        const program = self.compilation.program orelse return error.InternalError;
        return builder.build(arena, .{
            .index = &self.index,
            .src = self.compilation.src,
            .syntax = self.compilation.syntax,
            .program = program,
            .prepared = self.request.prepared orelse return error.InternalError,
            .facts = self.request.produced orelse return error.InternalError,
        });
    }

    /// This check's canonical result for comparison with per-module checks,
    /// allocated with `allocator` so it outlives the check.
    pub fn result(self: *Whole, allocator: std.mem.Allocator) Error!Result {
        return resultOf(allocator, .{ .compilation = &self.compilation, .request = &self.request, .stubs = null });
    }
};

/// The pieces one check is assembled in, borrowed from a `Whole` or `Single`.
const Parts = struct {
    project: *project_module.Project,
    index: *interfaces.Index,
    compilation: *project_compile.Compilation,
    cache: *semantic_cache.Cache,
    request: *summary.Request,
    entry: []const u8,
    limits: project_module.Options,

    fn of(owner: anytype) Parts {
        return .{ .project = &owner.project, .index = &owner.index, .compilation = &owner.compilation, .cache = &owner.cache, .request = &owner.request, .entry = owner.entry.name, .limits = owner.entry.limits };
    }

    /// Load the module graph through `sources`.
    fn load(self: Parts, sources: *Sources) Error!void {
        var limits = self.limits;
        limits.standard_from_provider = if (sources.library) |library| library.standardServed() else false;
        self.project.load(.{ .context = sources, .read = Sources.read, .embed = if (sources.assets != null) Sources.readEmbed else null }, self.entry, limits) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return frontend.hostFailure(err) orelse error.SourceError,
        };
    }

    /// Index, merge and check the loaded graph under the request.
    fn check(self: Parts) Error!void {
        self.index.* = interfaces.buildWithCache(self.project, null, null) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return frontend.hostFailure(err) orelse error.SourceError,
        };
        // MODULE-INTERFACE-CUTOFF-1: every name the check looks up in a
        // module; the index's own validation above resolves only types.
        const lookups = try self.project.arena.allocator().create(std.ArrayList(interfaces.Lookup));
        lookups.* = .empty;
        self.index.lookups = lookups;
        self.compilation.* = project_compile.Compilation.init(self.index) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return frontend.hostFailure(err) orelse error.InternalError,
        };
        self.cache.context.summaries = self.request;
        defer self.cache.context.summaries = null;
        try self.compilation.checkWithCache(self.cache);
    }
};

/// A set of decoded interfaces by module name and by source path.
pub const Library = struct {
    by_name: std.StringHashMapUnmanaged(iface.Interface) = .empty,
    /// Interface text by the module path a project loader asks for.
    by_path: std.StringHashMapUnmanaged([]const u8) = .empty,
    /// Where artifacts not read yet are, for a library read on demand.
    store: ?Store = null,

    /// A directory of `<module>.myi` artifacts, read one at a time on first
    /// use; `arena` keeps what it reads.
    pub const Store = struct {
        io: std.Io,
        directory: []const u8,
        arena: std.mem.Allocator,
        /// MODULE-SCHEDULE-4: where the standard modules' interfaces are,
        /// when a check reads them from interfaces rather than the compiler.
        standard: ?[]const u8 = null,
    };

    /// Whether this library serves the standard modules' interfaces.
    pub fn standardServed(self: *const Library) bool {
        const store = self.store orelse return false;
        return store.standard != null;
    }

    /// A library that reads each artifact from `store` only when a check
    /// loads that module, so a check reads the interfaces it imports and no
    /// others.
    pub fn stored(store: Store) Library {
        return .{ .store = store };
    }

    /// The interface text served for a module path, reading and decoding its
    /// artifact on first use; null when there is none or it does not decode.
    pub fn text(self: *Library, path: []const u8) ?[]const u8 {
        if (self.by_path.get(path)) |known| return known;
        const store = self.store orelse return null;
        if (!std.mem.endsWith(u8, path, ".my")) return null;
        const directory = if (standard_library.source(path) != null) store.standard orelse return null else store.directory;
        const module = store.arena.dupe(u8, path[0 .. path.len - 3]) catch return null;
        std.mem.replaceScalar(u8, module, '/', '.');
        const file = std.fmt.allocPrint(store.arena, "{s}/{s}{s}", .{ directory, module, iface.extension }) catch return null;
        const bytes = std.Io.Dir.cwd().readFileAlloc(store.io, file, store.arena, .limited(256 * 1024 * 1024)) catch return null;
        const interface = iface.decode(store.arena, bytes) orelse return null;
        if (!std.mem.eql(u8, interface.module, module)) return null;
        self.by_name.put(store.arena, interface.module, interface) catch return null;
        self.by_path.put(store.arena, path, interface.text) catch return null;
        return interface.text;
    }

    /// Index `list`; every allocation comes from `allocator`, an arena that
    /// keeps whatever a failure leaves behind.
    pub fn of(allocator: std.mem.Allocator, list: []const iface.Interface) Error!Library {
        var library: Library = .{};
        for (list) |interface| {
            const path = project_module.modulePath(allocator, interface.module) catch return error.InternalError;
            // The compiler serves its standard library from source, never an interface.
            if (standard_library.source(path) != null) continue;
            try library.by_name.put(allocator, interface.module, interface);
            try library.by_path.put(allocator, path, interface.text);
        }
        return library;
    }

    /// The declared functions of the loaded modules' interfaces, every module
    /// but `own`, indexed by stable key: what a check of `own` stands in for
    /// bodies it does not have. Its own functions are checked from its source.
    pub fn standIns(self: *const Library, allocator: std.mem.Allocator, loaded: []const project_module.Module, own: []const u8) Error!*const summary.Index {
        var stood: std.ArrayList(summary.Summary) = .empty;
        for (loaded) |module| {
            if (std.mem.eql(u8, module.name, own)) continue;
            const interface = self.by_name.get(module.name) orelse continue;
            for (interface.declarations.functions) |function| {
                if (function.role != .declared) continue;
                try stood.append(allocator, .{
                    .key = function.key,
                    .context = @splat(0),
                    .region = .{ .len = 0, .digest = @splat(0) },
                    .fact = function.fact,
                    .stubbable = true,
                });
            }
        }
        const out = try allocator.create(summary.Index);
        out.* = .{ .summaries = stood.items };
        try out.by_key.ensureTotalCapacity(allocator, @intCast(stood.items.len));
        for (stood.items, 0..) |entry, position| out.by_key.putAssumeCapacity(entry.key, @intCast(position));
        return out;
    }
};

/// One module checked against its imports' interfaces.
pub const Single = struct {
    gpa: std.mem.Allocator,
    project: project_module.Project,
    index: interfaces.Index,
    compilation: project_compile.Compilation,
    cache: semantic_cache.Cache,
    request: summary.Request,
    entry: Entry,

    /// Check module `module` from `bytes` against `library` alone. `is_entry`
    /// says the module is the project's entry, which then stays the entry
    /// (its bytes as `Entry.bytes` gave them to the whole program); otherwise
    /// a synthetic entry imports it. On `SourceError` the value is still
    /// returned through `out` with its diagnostics or project problem.
    pub fn open(gpa: std.mem.Allocator, request: ModuleRequest, out: **Single) Error!void {
        const self = try gpa.create(Single);
        out.* = self;
        self.* = .{
            .gpa = gpa,
            .project = project_module.Project.init(gpa),
            .index = undefined,
            .compilation = undefined,
            .cache = semantic_cache.Cache.init(gpa, 0),
            .request = .{ .policy = .{ .declared = true } },
            .entry = .{ .root = "", .name = if (request.is_entry) request.module else root_module, .bytes = request.bytes, .assets = request.assets, .limits = request.limits },
        };
        const arena = self.project.arena.allocator();
        var overrides: std.ArrayList(Override) = .empty;
        const own_path = project_module.modulePath(arena, request.module) catch return error.SourceError;
        try overrides.append(arena, .{ .path = own_path, .bytes = request.bytes });
        if (!request.is_entry) {
            const root_path = project_module.modulePath(arena, root_module) catch return error.InternalError;
            try overrides.append(arena, .{ .path = root_path, .bytes = try std.fmt.allocPrint(arena, root_text, .{request.module}) });
        }
        var sources: Sources = .{ .io = undefined, .root = null, .overrides = overrides.items, .library = request.library, .assets = request.assets };
        const parts: Parts = .of(self);
        try parts.load(&sources);
        self.request.previous = try request.library.standIns(arena, self.project.modules.items, request.module);
        try parts.check();
    }

    /// Release the module's project and check.
    pub fn deinit(self: *Single) void {
        const gpa = self.gpa;
        self.cache.deinit();
        self.project.deinit();
        gpa.destroy(self);
    }

    /// Whether every declared function the check met was stood in, with no
    /// fallback to a full check (which would have read no body for them).
    pub fn declaredOnly(self: *const Single) bool {
        return self.request.policy.declared;
    }

    /// This check's canonical result, with interface-text positions mapped
    /// back to their modules' sources, allocated with `allocator` so it
    /// outlives the check.
    pub fn result(self: *Single, allocator: std.mem.Allocator, library: *const Library, module: []const u8) Error!Result {
        return resultOf(allocator, .{ .compilation = &self.compilation, .request = &self.request, .stubs = library, .root = root_module, .own = module });
    }
};

/// What a per-module check needs: the module, its source bytes, whether it is
/// the project's entry, and the interfaces of the modules it may import.
pub const ModuleRequest = struct {
    module: []const u8,
    bytes: []const u8,
    is_entry: bool,
    library: *Library,
    assets: ?project_module.Provider = null,
    limits: project_module.Options = .{},
};

/// One diagnostic as `module:start-end severity code message`, in its
/// module's own source coordinates.
pub const Located = []const u8;

/// One function's checked result: its canonical name and the digest of its
/// checked contract (effects, mutation footprint, return origin, write facts)
/// and signature types.
pub const Checked = struct { name: []const u8, digest: [32]u8, stood_in: bool };

/// One check's canonical result.
pub const Result = struct {
    diagnostics: []const Located,
    functions: []const Checked,
    /// Stable key and dependency context of every ordinary declaration.
    contexts: []const Context,
    /// Diagnostics located in interface text no verbatim stretch covers.
    unmapped: usize = 0,
};

/// One declaration's stable key and dependency context.
pub const Context = struct { key: []const u8, context: [32]u8 };

const ResultInputs = struct {
    compilation: *project_compile.Compilation,
    request: *const summary.Request,
    /// Interfaces the check read in place of sources, to map positions back.
    stubs: ?*const Library,
    /// Synthetic entry module whose functions and diagnostics are not compared.
    root: ?[]const u8 = null,
    /// The module under check, read from its source rather than an interface.
    own: []const u8 = "",
};

fn resultOf(allocator: std.mem.Allocator, inputs: ResultInputs) Error!Result {
    const compilation = inputs.compilation;
    const modules = compilation.index.project.modules.items;
    var located: std.ArrayList(Located) = .empty;
    var unmapped: usize = 0;
    for (compilation.diagnostics.items.items) |item| {
        const at = compilation.src.originalSpan(item.span) catch {
            unmapped += 1;
            continue;
        };
        const module = modules[at.input].name;
        if (inputs.root) |root| if (std.mem.eql(u8, module, root)) continue;
        var span = at.span;
        if (inputs.stubs) |library| if (!std.mem.eql(u8, module, inputs.own)) if (library.by_name.get(module)) |interface| {
            // An unused-import warning is a lint about the module's own
            // source; its own compile reports it, not a dependent's.
            if (std.mem.eql(u8, item.code, "W_UNUSED_IMPORT")) continue;
            span = mapStub(interface, span) orelse {
                unmapped += 1;
                continue;
            };
        };
        try located.append(allocator, try std.fmt.allocPrint(allocator, "{s}:{d}-{d} {s} {s} {s}", .{ module, span.start, span.end, @tagName(item.severity), item.code, item.message }));
    }
    std.mem.sort(Located, located.items, {}, lessText);
    var checked: std.ArrayList(Checked) = .empty;
    const program = compilation.program;
    const stood = try standIns(allocator, inputs, if (program) |typed_program| typed_program.functions.len else 0);
    if (program) |typed_program| for (typed_program.functions, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, entry_adapter.wrapper_name)) continue;
        const name = try canonicalName(allocator, compilation, function);
        if (inputs.root) |root| if (std.mem.startsWith(u8, name, root) and std.mem.startsWith(u8, name[root.len..], "::")) continue;
        try checked.append(allocator, .{ .name = name, .digest = functionDigest(function, typed_program.records), .stood_in = stood[index] });
    };
    std.mem.sort(Checked, checked.items, {}, checkedBefore);
    var contexts: std.ArrayList(Context) = .empty;
    if (inputs.request.prepared) |prepared| for (prepared.ordinary_ast) |ast_index| {
        try contexts.append(allocator, .{ .key = try allocator.dupe(u8, prepared.keys[ast_index]), .context = prepared.contexts[ast_index] });
    };
    std.mem.sort(Context, contexts.items, {}, contextBefore);
    return .{ .diagnostics = located.items, .functions = checked.items, .contexts = contexts.items, .unmapped = unmapped };
}

/// Which checked functions an interface's facts stood in for: the ordinary
/// instances whose stable key a declared interface function has.
fn standIns(allocator: std.mem.Allocator, inputs: ResultInputs, count: usize) Error![]const bool {
    const marks = try allocator.alloc(bool, count);
    @memset(marks, false);
    if (!inputs.request.policy.declared) return marks;
    const declared = inputs.request.previous orelse return marks;
    const prepared = inputs.request.prepared orelse return marks;
    for (prepared.ordinary_ast, 0..) |ast_index, instance| {
        if (instance < count and declared.find(prepared.keys[ast_index]) != null) marks[instance] = true;
    }
    return marks;
}

/// Map a span in an interface's text to the module source it was copied from.
fn mapStub(interface: iface.Interface, span: source.Span) ?source.Span {
    for (interface.positions.origins) |origin| {
        if (span.start < origin.text or span.end > origin.text + origin.len + origin.gap) continue;
        return .{ .start = origin.source + (span.start - origin.text), .end = origin.source + (span.end - origin.text) };
    }
    return null;
}

/// A function's name. A lambda is named by its module and its offset in that
/// module's source (LAMBDA-NAME-1), so two checks of different module sets agree.
fn canonicalName(allocator: std.mem.Allocator, compilation: *project_compile.Compilation, function: typed.Function) Error![]const u8 {
    _ = compilation;
    return allocator.dupe(u8, function.name);
}

/// The digest one checked function is compared by.
pub fn functionDigest(function: typed.Function, records: []const typed.Record) [32]u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("oracle-function-v1");
    hash.update(&semantic_key.contractDigest(function));
    const count = @min(function.signature.parameter_count, function.scope.locals.len);
    for (function.scope.locals[0..count]) |local| {
        hash.update(typed.typeName(local.ty, records));
        hash.update(&.{0});
    }
    hash.update(typed.typeName(function.signature.return_type, records));
    hash.update(&.{ @as(u8, @intFromBool(function.policy.c_abi)), @as(u8, @intFromBool(function.policy.host != null)), @as(u8, @intFromBool(function.policy.conversion)) });
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

/// How one module's check differed from the whole program's.
pub const Comparison = struct {
    /// Checked functions: contract digest and signature types.
    functions: Tally = .{},
    /// The module's own declarations' dependency contexts.
    contexts: Tally = .{},
    /// Diagnostics the module's check reported that the whole program did not.
    extra_diagnostics: []const Located = &.{},
    /// Diagnostics the module's check reported, for the whole-program union.
    diagnostics: []const Located = &.{},
    unmapped: usize = 0,

    /// Everything that differed, counted.
    pub fn mismatches(self: Comparison) usize {
        return self.functions.mismatches.len + self.contexts.mismatches.len + self.extra_diagnostics.len + self.unmapped;
    }
};

/// How many items one comparison looked at and the names of those that differ.
pub const Tally = struct { compared: usize = 0, mismatches: []const []const u8 = &.{} };

/// Compare digests by name: every item of `single` must be in `whole` with the same digest.
fn tally(allocator: std.mem.Allocator, whole: []const Checked, single: []const Checked) Error!Tally {
    var digests: std.StringHashMapUnmanaged([32]u8) = .empty;
    for (whole) |item| try digests.put(allocator, item.name, item.digest);
    var out: Tally = .{};
    var differing: std.ArrayList([]const u8) = .empty;
    for (single) |item| {
        out.compared += 1;
        const expected = digests.get(item.name) orelse {
            try differing.append(allocator, try std.fmt.allocPrint(allocator, "{s} (not in the whole program)", .{item.name}));
            continue;
        };
        if (!std.mem.eql(u8, &expected, &item.digest)) try differing.append(allocator, item.name);
    }
    out.mismatches = differing.items;
    return out;
}

/// Compare one module's check with the whole program's. Only the module's own
/// declarations' contexts are compared: another module's declarations were
/// read from interface text.
pub fn compare(allocator: std.mem.Allocator, whole: Result, single: Result, module: []const u8) Error!Comparison {
    var out: Comparison = .{ .diagnostics = single.diagnostics, .unmapped = single.unmapped };
    out.functions = try tally(allocator, whole.functions, single.functions);
    var contexts: std.StringHashMapUnmanaged([32]u8) = .empty;
    for (whole.contexts) |context| try contexts.put(allocator, context.key, context.context);
    var differing: std.ArrayList([]const u8) = .empty;
    for (single.contexts) |context| {
        const owner = iface.keyModule(context.key) orelse continue;
        if (!std.mem.eql(u8, owner, module)) continue;
        out.contexts.compared += 1;
        const expected = contexts.get(context.key) orelse {
            try differing.append(allocator, try iface.displayKey(allocator, context.key));
            continue;
        };
        if (!std.mem.eql(u8, &expected, &context.context)) try differing.append(allocator, try iface.displayKey(allocator, context.key));
    }
    out.contexts.mismatches = differing.items;
    var known: std.StringHashMapUnmanaged(void) = .empty;
    for (whole.diagnostics) |item| try known.put(allocator, item, {});
    var extra: std.ArrayList(Located) = .empty;
    for (single.diagnostics) |item| if (!known.contains(item)) try extra.append(allocator, item);
    out.extra_diagnostics = extra.items;
    return out;
}

/// The whole-program diagnostics no module's check reported.
pub fn missingDiagnostics(allocator: std.mem.Allocator, whole: Result, comparisons: []const Comparison) Error![]const Located {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    for (comparisons) |comparison| for (comparison.diagnostics) |item| try seen.put(allocator, item, {});
    var missing: std.ArrayList(Located) = .empty;
    for (whole.diagnostics) |item| if (!seen.contains(item)) try missing.append(allocator, item);
    return missing.items;
}

/// Whether a module is compiler-embedded standard library, which a module's
/// check reads from the compiler itself rather than from an interface.
pub fn standardModule(allocator: std.mem.Allocator, name: []const u8) bool {
    const path = project_module.modulePath(allocator, name) catch return false;
    defer allocator.free(path);
    return standard_library.source(path) != null;
}

fn lessText(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn checkedBefore(_: void, a: Checked, b: Checked) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

fn contextBefore(_: void, a: Context, b: Context) bool {
    return std.mem.lessThan(u8, a.key, b.key);
}
