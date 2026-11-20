//! Filesystem and declaration-index adapter for the pure release project model.
const std = @import("std");
const product = @import("product.zig");
const model = @import("release_project.zig");
const graph = @import("project.zig");
const interfaces = @import("interfaces.zig");
const config = @import("project_config.zig");
const release_config = @import("release_config.zig");
const Files = @import("project_files.zig").Files;
const ast = @import("ast.zig");

/// Host/configuration/parse failure before a project can be described.
pub const Error = config.Error || model.Error || graph.LoadError || error{ HostIo, IncompleteProject };
/// Where a project's declaration loading failed: the source file and position
/// of the first compiler diagnostic, so `release init`/`check` name it instead
/// of `SourceError` (FR-413). Strings belong to the caller's allocator.
pub const Failure = struct {
    present: bool = false,
    path: []const u8 = "",
    line: usize = 1,
    column: usize = 1,
    code: []const u8 = "",
    message: []const u8 = "",
    rule: ?@import("diagnostic.zig").Rule = null,

    /// Standard ownership-rule note retained when a host wraps a source error.
    pub fn ruleNote(self: Failure, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        const rule = self.rule orelse return "";
        return std.fmt.allocPrint(allocator, "  note: ownership rule {s}\n", .{@tagName(rule)});
    }
};
/// Loaded declaration-only model shared by overview, baseline and release rules.
pub const Model = struct {
    arena: *std.heap.ArenaAllocator,
    project: *graph.Project,
    index: *interfaces.Index,
    root: []const u8,
    selection: model.Selection,
    modules: []const usize,
    options: release_config.Options,

    /// Release the project arena and every owned path, option and selection list.
    pub fn deinit(self: *Model) void {
        const allocator = self.arena.child_allocator;
        self.project.deinit();
        self.arena.deinit();
        allocator.destroy(self.arena);
        self.* = undefined;
    }
};

/// Load a directory with selka.json, or an entry file whose directory is the root.
/// Bodies are never checked; invalid body types do not prevent an overview.
pub fn load(allocator: std.mem.Allocator, io: std.Io, requested: []const u8) Error!Model {
    return loadWith(allocator, io, requested, null);
}

/// Load as `load` does, filling `failure` with the file, position and compiler
/// diagnostic when declaration loading refuses a source (FR-413).
pub fn loadWith(allocator: std.mem.Allocator, io: std.Io, requested: []const u8, source: ?*Failure) Error!Model {
    const arena = try allocator.create(std.heap.ArenaAllocator);
    arena.* = .init(allocator);
    errdefer {
        arena.deinit();
        allocator.destroy(arena);
    }
    const a = arena.allocator();
    const absolute = std.Io.Dir.cwd().realPathFileAlloc(io, requested, a) catch return error.HostIo;
    const stat = std.Io.Dir.cwd().statFile(io, absolute, .{}) catch return error.HostIo;
    const directory = stat.kind == .directory;
    const root = if (directory) absolute else std.fs.path.dirname(absolute) orelse return error.InvalidEntry;
    const default_entry = if (directory) "main.selka" else std.fs.path.basename(absolute);
    const config_path = try std.fs.path.join(a, &.{ root, config.config_name });
    var failure: config.Failure = .{};
    var loaded: ?config.Config = config.load(a, io, config_path, &failure) catch |err| blk: {
        if (err == error.MissingConfig and !directory) break :blk @as(?config.Config, null);
        return err;
    };
    defer if (loaded) |*value| value.deinit();
    const options = try copyOptions(a, if (loaded) |*value| value.releaseOptions() else .{});
    const limits = projectOptions(loaded);
    const files = try discover(.{ .a = a, .allocator = allocator, .io = io, .root = root, .options = options, .max_bytes = limits.max_file_bytes, .source = source });
    const selection = try model.select(a, files, default_entry, options);
    const project = try a.create(graph.Project);
    project.* = graph.Project.init(allocator);
    errdefer project.deinit();
    const index = try a.create(interfaces.Index);
    var disk: Files = .{ .io = io, .root = root };
    var overlay = try Overlay.compose(a, disk.provider(), selection.roots, files);
    project.load(overlay.provider(), overlay.name, limits) catch |err| {
        if (err == error.SourceError) if (source) |slot| try captureFailure(allocator, project, slot);
        return err;
    };
    index.* = interfaces.build(project) catch |err| {
        if (err == error.SourceError) if (source) |slot| try captureFailure(allocator, project, slot);
        return err;
    };
    var compilation = @import("project_compile.zig").Compilation.init(index) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InternalError,
    };
    compilation.checkBorrowDeclarations() catch |err| {
        if (err == error.SourceError) _ = try captureSink(allocator, compilation.src, &compilation.diagnostics, source);
        return err;
    };
    const modules = try selectModules(a, project, selection, options);
    return .{ .arena = arena, .project = project, .index = index, .root = root, .selection = selection, .modules = modules, .options = options };
}

fn captureDiagnostic(allocator: std.mem.Allocator, src: @import("source.zig").Source, finding: @import("diagnostic.zig").Diagnostic, failure: *Failure) std.mem.Allocator.Error!void {
    const at = src.locate(finding.span.start);
    failure.* = .{
        .present = true,
        .path = try allocator.dupe(u8, at.path),
        .line = at.line,
        .column = at.column,
        .code = try allocator.dupe(u8, finding.code),
        .message = try allocator.dupe(u8, finding.message),
        .rule = finding.provenance.rule,
    };
}

fn captureFailure(allocator: std.mem.Allocator, project: *graph.Project, failure: *Failure) std.mem.Allocator.Error!void {
    const problem = project.problem orelse return;
    if (problem.site.module >= project.modules.items.len) return;
    const at = project.modules.items[problem.site.module].src.locate(problem.site.span.start);
    failure.* = .{
        .present = true,
        .path = try allocator.dupe(u8, at.path),
        .line = at.line,
        .column = at.column,
        .code = try allocator.dupe(u8, problem.code),
        .message = try allocator.dupe(u8, problem.message),
        .rule = if (problem.recovered.len != 0) problem.recovered[0].provenance.rule else null,
    };
}

fn copyOptions(a: std.mem.Allocator, options: release_config.Options) !release_config.Options {
    return .{
        .entries = try copyPaths(a, options.entries),
        .exclude = try copyPaths(a, options.exclude),
        .overview = try a.dupe(u8, options.overview),
        .decisions = try a.dupe(u8, options.decisions),
        .baseline = try a.dupe(u8, options.baseline),
        .changes = try a.dupe(u8, options.changes),
    };
}

fn copyPaths(a: std.mem.Allocator, paths: []const []const u8) ![]const []const u8 {
    const result = try a.alloc([]const u8, paths.len);
    for (paths, result) |path, *out| out.* = try a.dupe(u8, path);
    return result;
}

fn projectOptions(loaded: ?config.Config) graph.Options {
    const budgets = if (loaded) |value| value.document.budgets else config.Budgets{};
    const defaults: graph.Options = .{};
    return .{
        .max_modules = budgets.max_modules orelse defaults.max_modules,
        .max_imports = budgets.max_imports orelse defaults.max_imports,
        .max_file_bytes = budgets.max_file_bytes orelse defaults.max_file_bytes,
        .max_total_bytes = budgets.max_total_bytes orelse defaults.max_total_bytes,
    };
}

/// One discovery walk: the project arena, the caller's diagnostic allocator
/// (a `Failure` outlives the project arena), the source tree and its bounds.
pub const Scan = struct {
    a: std.mem.Allocator,
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    options: release_config.Options,
    max_bytes: usize,
    source: ?*Failure,

    /// Every allocator and path here is borrowed; a walk owns nothing to free.
    pub fn deinit(self: *Scan) void {
        self.* = undefined;
    }
};

fn discover(scan: Scan) Error![]const model.File {
    var directory = std.Io.Dir.cwd().openDir(scan.io, scan.root, .{ .iterate = true }) catch return error.HostIo;
    defer directory.close(scan.io);
    var walker = directory.walk(scan.a) catch return error.OutOfMemory;
    defer walker.deinit();
    var files: std.ArrayList(model.File) = .empty;
    while (walker.next(scan.io) catch return error.HostIo) |item| {
        if (model.excluded(item.path, scan.options.exclude)) {
            if (item.kind == .directory) walker.leave(scan.io);
            continue;
        }
        if (item.kind != .file or !product.isSource(item.path)) continue;
        const path = try scan.a.dupe(u8, item.path);
        const bytes = directory.readFileAlloc(scan.io, path, scan.a, .limited(scan.max_bytes)) catch return error.HostIo;
        try files.append(scan.a, try discoveryFlags(scan, path, bytes));
    }
    return files.toOwnedSlice(scan.a);
}

/// Copy the first error a lexer/parser sink holds into `failure`; false when the
/// sink accepted the source.
fn captureSink(allocator: std.mem.Allocator, src: @import("source.zig").Source, sink: *const @import("diagnostic.zig").Sink, source: ?*Failure) std.mem.Allocator.Error!bool {
    for (sink.items.items) |finding| {
        if (finding.severity != .err) continue;
        if (source) |slot| try captureDiagnostic(allocator, src, finding, slot);
        return true;
    }
    return false;
}

/// Scan one module's declarations and examples; a source parse failure fills
/// `Scan.source` with the file, position and compiler diagnostic (FR-413).
pub fn discoveryFlags(scan: Scan, path: []const u8, bytes: []const u8) Error!model.File {
    var file: model.File = .{ .path = path, .test_bearing = model.declaresTests(bytes) };
    if (std.mem.indexOf(u8, bytes, ">>>") == null) return file;
    var scratch = std.heap.ArenaAllocator.init(scan.a);
    defer scratch.deinit();
    const memory = scratch.allocator();
    var sink: @import("diagnostic.zig").Sink = .{ .allocator = memory };
    const src = try @import("source.zig").Source.init(memory, path, bytes);
    const tokens = @import("lexer.zig").lex(memory, bytes, &sink) catch |err| {
        _ = try captureSink(scan.allocator, src, &sink, scan.source);
        return err;
    };
    var parser: @import("parser.zig").Parser = .{ .src = src, .storage = memory, .tokens = tokens, .sink = &sink };
    const syntax = parser.parseModule() catch |err| {
        _ = try captureSink(scan.allocator, src, &sink, scan.source);
        return err;
    };
    if (try captureSink(scan.allocator, src, &sink, scan.source)) return error.SourceError;
    for (syntax.functions) |function| {
        if (std.mem.startsWith(u8, src.text(function.name), "test_") or ast.hasAttribute(syntax, function.name, .@"test")) file.test_bearing = true;
        const doc = ast.docstringOf(syntax, function.name) orelse continue;
        if (@import("docstring_examples.zig").count(doc.text) != 0) file.example_bearing = true;
    }
    return file;
}

fn selectModules(a: std.mem.Allocator, project: *graph.Project, selection: model.Selection, options: release_config.Options) Error![]const usize {
    const modules = try a.alloc(model.Module, project.modules.items.len);
    for (project.modules.items, modules) |loaded, *out| {
        const imports = try a.alloc(usize, loaded.imports.len);
        for (loaded.imports, imports) |edge, *id| id.* = edge.target;
        out.* = .{ .path = loaded.src.path, .imports = imports, .standard = std.mem.startsWith(u8, loaded.src.path, "@stdlib/") };
    }
    const roots = try a.alloc(usize, selection.roots.len);
    for (selection.roots, roots) |path, *id| id.* = project.names.get(try moduleName(a, path)) orelse return error.InvalidGraph;
    return model.moduleSet(a, modules, roots, options.exclude);
}

fn moduleName(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (!product.isSource(path)) return error.InvalidEntry;
    const name = try a.dupe(u8, product.chopSource(path));
    std.mem.replaceScalar(u8, name, '/', '.');
    return name;
}

/// The name the release loader gives the module that imports every selected root.
/// Its file is not a file of the project; a located failure in it names this path.
pub const synthesized_root = "_release_docs_root";

/// Whether a located failure's `path` names the synthesized root module: the name
/// with trailing underscores, which the loader adds when a project file already uses it.
pub fn isSynthesizedRoot(path: []const u8) bool {
    if (!product.isSource(path)) return false;
    const name = product.chopSource(path);
    if (!std.mem.startsWith(u8, name, synthesized_root)) return false;
    for (name[synthesized_root.len..]) |byte| if (byte != '_') return false;
    return true;
}

const Overlay = struct {
    underlying: graph.Provider,
    name: []const u8,
    path: []const u8,
    bytes: []const u8,

    fn compose(a: std.mem.Allocator, underlying: graph.Provider, roots: []const []const u8, files: []const model.File) !Overlay {
        var name: []const u8 = synthesized_root;
        while (collides(name, files)) name = try std.mem.concat(a, u8, &.{ name, "_" });
        var bytes: std.ArrayList(u8) = .empty;
        for (roots, 0..) |path, i| try bytes.print(a, "import {s} as release_root_{d}\n", .{ try moduleName(a, path), i });
        return .{ .underlying = underlying, .name = name, .path = try std.mem.concat(a, u8, &.{ name, product.source_suffix }), .bytes = bytes.items };
    }
    fn collides(name: []const u8, files: []const model.File) bool {
        for (files) |file| if (std.mem.eql(u8, product.chopSource(file.path), name)) return true;
        return false;
    }
    fn provider(self: *Overlay) graph.Provider {
        return .{ .context = self, .read = read, .embed = readEmbed };
    }
    fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, limit: usize) graph.ReadError![]u8 {
        const self: *Overlay = @ptrCast(@alignCast(context.?));
        if (std.mem.eql(u8, path, self.path)) return a.dupe(u8, self.bytes);
        return self.underlying.read(self.underlying.context, a, path, limit);
    }
    fn readEmbed(context: ?*anyopaque, a: std.mem.Allocator, module: []const u8, path: []const u8, limit: usize) std.mem.Allocator.Error!@import("embed.zig").Read {
        const self: *Overlay = @ptrCast(@alignCast(context.?));
        const hook = self.underlying.embed orelse return .{ .status = .unresolved };
        return hook(self.underlying.context, a, module, path, limit);
    }
};

test "the synthesized root is named by its path, with any underscores the loader added" {
    try std.testing.expect(isSynthesizedRoot("_release_docs_root.selka"));
    try std.testing.expect(isSynthesizedRoot("_release_docs_root_.selka"));
    try std.testing.expect(!isSynthesizedRoot("main.selka"));
    try std.testing.expect(!isSynthesizedRoot("sub/_release_docs_root.selka"));
    try std.testing.expect(!isSynthesizedRoot("_release_docs_root_x.selka"));
    try std.testing.expect(!isSynthesizedRoot("_release_docs_root"));
}
