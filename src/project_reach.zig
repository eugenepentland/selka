//! The source files one entry's project graph reads, found by loading the graph
//! from disk. `selka fix` uses it to skip an entry whose modules an earlier
//! entry's check already covered.
const std = @import("std");
const product = @import("compiler_root").compiler_language.product;
const language = @import("selka");
const project = language.project;
const project_config = language.project_config;

/// Why the graph of an entry could not be listed.
pub const Error = error{ OutOfMemory, InvalidEntry };

/// User sources read by one graph, and whether their imports and declarations
/// were completely parsed. Partial paths alone cannot prove independence.
pub const Scope = struct { paths: []const []const u8, complete: bool };

/// The absolute paths of every source file loading `entry`'s project graph read,
/// or just the entry itself when the graph does not load. Every path is allocated
/// from `allocator`, which the caller releases as one arena.
pub fn reach(allocator: std.mem.Allocator, io: std.Io, entry: []const u8) Error![]const []const u8 {
    return (try load(allocator, io, entry, false)).paths;
}

/// A tuple migration may be isolated only with a complete graph and declaration
/// parse. Embedded standard modules are not editable user-source dependencies.
pub fn tupleScope(allocator: std.mem.Allocator, io: std.Io, entry: []const u8) Error!Scope {
    return load(allocator, io, entry, true);
}

fn load(allocator: std.mem.Allocator, io: std.Io, entry: []const u8, require_syntax: bool) Error!Scope {
    const cwd = std.Io.Dir.cwd().realPathFileAlloc(io, ".", allocator) catch return error.InvalidEntry;
    const absolute = try std.fs.path.resolve(allocator, &.{ cwd, entry });
    var root: []const u8 = std.fs.path.dirname(absolute) orelse return error.InvalidEntry;
    var module_name: []const u8 = try entryModule(allocator, std.fs.path.basename(absolute));
    if (project_config.testEntryLocation(allocator, io, absolute) catch return error.InvalidEntry) |location| {
        root = location.root;
        module_name = location.name;
    }
    var provider: DiskProvider = .{ .allocator = allocator, .io = io, .root = root };
    var loaded = project.Project.init(allocator);
    defer loaded.deinit();
    var complete = true;
    loaded.load(.{ .context = &provider, .read = DiskProvider.read }, module_name, .{ .legacy_headers = true }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => complete = false,
    };
    if (provider.paths.items.len == 0) try provider.paths.append(allocator, absolute);
    if (require_syntax and complete) complete = try syntaxComplete(allocator, loaded.modules.items);
    if (require_syntax) for (provider.paths.items) |*path| {
        const canonical = std.Io.Dir.cwd().realPathFileAlloc(io, path.*, allocator) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return .{ .paths = provider.paths.items, .complete = false },
        };
        // An alias could connect two apparently disjoint declaration paths.
        // Keep the fallback for symlinks and multiply linked sources.
        if (!std.mem.eql(u8, canonical, path.*)) complete = false;
        const stat = std.Io.Dir.cwd().statFile(io, canonical, .{}) catch return .{ .paths = provider.paths.items, .complete = false };
        if (stat.kind != .file or stat.nlink != 1) complete = false;
        path.* = canonical;
    };
    return .{ .paths = provider.paths.items, .complete = complete };
}

/// Header discovery can finish before a body fails to parse. Such a source
/// cannot supply complete declaration facts for a directory migration.
fn syntaxComplete(allocator: std.mem.Allocator, modules: []const project.Module) error{OutOfMemory}!bool {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    for (modules) |module| {
        if (std.mem.startsWith(u8, module.src.path, "@stdlib/")) continue;
        if (!scratch.reset(.retain_capacity)) return error.OutOfMemory;
        const memory = scratch.allocator();
        var sink: language.diagnostic.Sink = .{ .allocator = memory };
        const tokens = language.lexer.lex(memory, module.src.bytes, &sink) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return false,
        };
        var parser: language.parser.Parser = .{ .src = module.src, .storage = memory, .tokens = tokens, .sink = &sink, .cursor = .{ .dialect = .migration } };
        defer parser.release();
        _ = parser.parseModule() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return false,
        };
        for (sink.items.items) |item| if (item.severity == .err) return false;
    }
    return true;
}

/// A file whose own text the parser refuses outright (not one that carries a repairable retired form), and the module names its
/// `import` lines give. Null when the file parses or cannot be read. `selka fix` uses it to hold back a rename of a declaration
/// the file may call, since the file's qualified calls cannot be renamed with it while it does not parse.
pub fn unparsedImports(allocator: std.mem.Allocator, io: std.Io, path: []const u8) Error!?[]const []const u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const memory = scratch.allocator();
    const src = try language.source.Source.init(memory, path, bytes);
    var sink: language.diagnostic.Sink = .{ .allocator = memory };
    const tokens = language.lexer.lex(memory, bytes, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            const imports = try importedModules(allocator, bytes);
            return imports;
        },
    };
    var parser: language.parser.Parser = .{ .src = src, .storage = memory, .tokens = tokens, .sink = &sink, .cursor = .{ .dialect = .migration } };
    defer parser.release();
    _ = parser.parseModule() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            const imports = try importedModules(allocator, bytes);
            return imports;
        },
    };
    return null;
}

/// The module names the `import` and `from ... import` lines of `bytes` name, in order, from `allocator`.
fn importedModules(allocator: std.mem.Allocator, bytes: []const u8) Error![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        const rest = if (std.mem.startsWith(u8, line, "import ")) line["import ".len..] else if (std.mem.startsWith(u8, line, "from ")) line["from ".len..] else continue;
        var modules = std.mem.tokenizeAny(u8, rest, ", \t");
        const first = modules.next() orelse continue;
        try names.append(allocator, try allocator.dupe(u8, first));
        // `import a, b` names two modules; an `as` alias or an `import` keyword ends the list.
        while (modules.next()) |next| {
            if (std.mem.eql(u8, next, "as") or std.mem.eql(u8, next, "import") or !std.mem.startsWith(u8, line, "import ")) break;
            try names.append(allocator, try allocator.dupe(u8, next));
        }
    }
    return names.toOwnedSlice(allocator);
}

/// The exit status a finished child reports: its own code, else 2.
pub fn exitCode(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        else => 2,
    };
}

/// The dotted module name of an entry path relative to its project root.
fn entryModule(allocator: std.mem.Allocator, entry: []const u8) Error![]const u8 {
    if (!product.isSource(entry)) return error.InvalidEntry;
    const name = try allocator.dupe(u8, product.chopSource(entry));
    for (name) |*byte| {
        if (byte.* == std.fs.path.sep) byte.* = '.';
    }
    return name;
}

/// Reads project sources beneath one root and records each path it served.
const DiskProvider = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    paths: std.ArrayList([]const u8) = .empty,
    fn read(raw: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) project.ReadError![]u8 {
        const self: *DiskProvider = @ptrCast(@alignCast(raw.?));
        const absolute = std.fs.path.join(self.allocator, &.{ self.root, path }) catch return error.OutOfMemory;
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.io, absolute, allocator, .limited(limit + 1)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.FileNotFound => return error.NotFound,
            error.StreamTooLong => return error.TooLarge,
            else => return error.ReadFailed,
        };
        self.paths.append(self.allocator, absolute) catch return error.OutOfMemory;
        return bytes;
    }
};
