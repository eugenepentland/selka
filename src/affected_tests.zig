//! `mylang test --affected`: select only the tests that reach a declaration
//! whose own body changed since a reference revision.
//!
//! The selection is derived, never judged: it loads and checks the same project
//! the runner would, maps each checked declaration's merged source span back to
//! its module file and original line range through the shared
//! `declaration_diff` helper, intersects that with the working-tree diff, and
//! keeps a discovered test only when the changed set is reachable from it over
//! the resolved call graph. If the project cannot be checked for any reason
//! other than allocation or a bad git revision, the whole discovered selection
//! runs unchanged: a selection aid must never turn a runnable test into a
//! silent skip.
const std = @import("std");
const declaration_diff = @import("declaration_diff.zig");
const interfaces = @import("interfaces.zig");
const project = @import("project.zig");
const project_compile = @import("project_compile.zig");
const project_files = @import("project_files.zig");
const quality = @import("quality.zig");
const ref_diff = @import("ref_diff.zig");
const typed = @import("typed.zig");

/// Failures a derivation reports: allocation, a reference `git` cannot resolve,
/// or an entry that is not a mylang source. Every other project failure
/// downgrades to `derived = false`.
pub const Error = error{ OutOfMemory, GitFailed, InvalidEntry };

/// One derivation's inputs. `load_root` carries the checked project (the
/// materialized test snapshot); `git_root` is the entry's own directory in the
/// user's repository, because the snapshot is a temp copy `git` cannot see.
/// `discovered` holds the qualified test names in discovery order.
pub const Request = struct {
    memory: std.mem.Allocator,
    io: std.Io,
    load_root: []const u8,
    git_root: []const u8,
    entry: []const u8,
    reference: []const u8,
    discovered: []const []const u8,
};

/// The derivation's verdict over the discovered tests, in discovery order.
pub const Selection = struct {
    /// One flag per discovered test: true keeps it in the run.
    keep: []const bool,
    /// Qualified names of the tests dropped as unaffected.
    skipped: []const []const u8,
    /// Whether the selection reflects a real derivation; false means the whole
    /// discovered set runs because the project could not be checked.
    derived: bool = true,
};

/// Select the tests that reach a declaration changed since `reference`.
pub fn select(request: Request) Error!Selection {
    if (!std.mem.endsWith(u8, request.entry, ".my")) return error.InvalidEntry;
    // Resolve the reference before deriving anything: a revision `git` cannot
    // diff is a host failure, not an empty selection.
    const changed = ref_diff.changedFiles(request.memory, request.io, request.git_root, request.reference) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.GitFailed => return error.GitFailed,
    };
    for (changed) |path| request.memory.free(path);
    request.memory.free(changed);
    return derive(request) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => Selection{ .keep = try keepAll(request.memory, request.discovered.len), .skipped = &.{}, .derived = false },
    };
}

/// One `true` per discovered test, for the run-everything fallback.
fn keepAll(allocator: std.mem.Allocator, count: usize) std.mem.Allocator.Error![]const bool {
    const keep = try allocator.alloc(bool, count);
    @memset(keep, true);
    return keep;
}

/// Check the project and keep every discovered test whose reachable set
/// intersects the changed declarations.
fn derive(request: Request) !Selection {
    const allocator = request.memory;
    var files: project_files.Files = .{ .io = request.io, .root = request.load_root };
    var graph = project.Project.init(allocator);
    defer graph.deinit();
    if (!std.mem.endsWith(u8, request.entry, ".my")) return error.InvalidEntry;
    try graph.load(files.provider(), request.entry[0 .. request.entry.len - ".my".len], .{});
    var index = try interfaces.build(&graph);
    var compilation = try project_compile.Compilation.init(&index);
    try compilation.check();
    const program = compilation.program orelse return error.InvalidEntry;
    const src = compilation.src;

    const diff_cache = try allocator.alloc(declaration_diff.ModuleDiff, index.project.modules.items.len);
    @memset(diff_cache, .{});
    if (entryModule(index.project.modules.items, request.entry)) |entry_module| diff_cache[entry_module].shift = try entryLineShift(request, index.project.modules.items[entry_module].src.bytes);
    const diff: declaration_diff.Diff = .{
        .memory = allocator,
        .io = request.io,
        .repo_root = request.git_root,
        .reference = request.reference,
        .index = &index,
        .src = src,
        .cache = diff_cache,
    };
    const changed = try allocator.alloc(bool, program.functions.len);
    for (program.functions, 0..) |function, position| {
        // A body edit lives outside the signature span, so the union of the
        // declaration and its body is what the diff intersects.
        const body = program.statements[@backingInt(function.scope.body)].span;
        changed[position] = try diff.changed(.{
            .start = @min(function.declaration.start, body.start),
            .end = @max(function.declaration.end, body.end),
        });
    }

    var analysis = try quality.analyze(allocator, program, src, .{});
    defer analysis.deinit();
    const keep = try allocator.alloc(bool, request.discovered.len);
    const visited = try allocator.alloc(bool, program.functions.len);
    defer allocator.free(visited);
    var pending: std.ArrayList(typed.FunctionId) = .empty;
    defer pending.deinit(allocator);
    var skipped: std.ArrayList([]const u8) = .empty;
    errdefer skipped.deinit(allocator);
    for (request.discovered, 0..) |name, position| {
        const id = functionNamed(program, name) orelse {
            // An unidentifiable declaration runs rather than being dropped.
            keep[position] = true;
            continue;
        };
        keep[position] = try reachesChanged(allocator, analysis.functions, changed, id, visited, &pending);
        if (!keep[position]) try skipped.append(allocator, name);
    }
    return .{ .keep = keep, .skipped = try skipped.toOwnedSlice(allocator) };
}

/// The checked module whose source path is the entry basename.
fn entryModule(modules: []const project.Module, entry: []const u8) ?usize {
    for (modules, 0..) |module, position| {
        if (std.mem.eql(u8, module.src.path, entry)) return position;
    }
    return null;
}

/// Lines the test snapshot prepended to a header-less entry. The snapshot adds
/// a `module <stem>` header, shifting every declaration down; the original file
/// in the repository carries the diff, so the checked line numbers must be
/// corrected back. An unchanged or unrecognizable entry shifts by zero.
fn entryLineShift(request: Request, materialized: []const u8) !isize {
    const path = try std.fs.path.join(request.memory, &.{ request.git_root, request.entry });
    defer request.memory.free(path);
    const original = std.Io.Dir.cwd().readFileAlloc(request.io, path, request.memory, .limited(16 * 1024 * 1024)) catch return 0;
    defer request.memory.free(original);
    if (std.mem.eql(u8, original, materialized)) return 0;
    const at = std.mem.indexOf(u8, materialized, original) orelse return 0;
    var lines: isize = 0;
    for (materialized[0..at]) |byte| lines += @intFromBool(byte == '\n');
    return -lines;
}

/// The checked function whose qualified name matches one discovered test.
fn functionNamed(program: typed.Program, name: []const u8) ?typed.FunctionId {
    for (program.functions, 0..) |function, position| {
        if (std.mem.eql(u8, function.name, name)) return @fromBackingInt(@intCast(position));
    }
    return null;
}

/// Whether any function reachable from `root` over resolved calls changed.
fn reachesChanged(
    allocator: std.mem.Allocator,
    functions: []const quality.Function,
    changed: []const bool,
    root: typed.FunctionId,
    visited: []bool,
    pending: *std.ArrayList(typed.FunctionId),
) !bool {
    @memset(visited, false);
    pending.clearRetainingCapacity();
    visited[@backingInt(root)] = true;
    try pending.append(allocator, root);
    var cursor: usize = 0;
    while (cursor < pending.items.len) : (cursor += 1) {
        const id = pending.items[cursor];
        if (changed[@backingInt(id)]) return true;
        for (functions[@backingInt(id)].calls) |call| {
            if (visited[@backingInt(call.callee)]) continue;
            visited[@backingInt(call.callee)] = true;
            try pending.append(allocator, call.callee);
        }
    }
    return false;
}
