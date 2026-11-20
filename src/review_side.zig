//! One side of a change review: a project as it stands at one revision, or as its
//! working tree stands. A side loads its declarations (no body is checked), its
//! overview document and its public entries, and it reads the files the review
//! compares: the decision and change-note Markdown and the source files.
const std = @import("std");
const product = @import("product.zig");
const loader = @import("release_project_load.zig");
const release_config = @import("release_config.zig");
const release_project = @import("release_project.zig");
const overview_collect = @import("overview_collect.zig");
const overview_facts = @import("overview_facts.zig");
const overview_store = @import("overview_store.zig");
const overview_types = @import("overview_types.zig");
const api_diff = @import("api_diff.zig");
const baseline = @import("api_diff_baseline.zig");

/// Host and memory failures. A project whose declarations do not load is an
/// `unreadable` side, not an error.
pub const Error = overview_facts.Error || baseline.Error || error{HostIo};

/// Largest source or Markdown file a side reads, as the release loader does.
const max_file_bytes = 16 * 1024 * 1024;
/// Top-level directories of a project that hold generated or local evidence, not source.
const evidence_directories = [_][]const u8{ "friction", "results", "oracle" };

/// One file of a side: `path` relative to the project and `bytes` its whole content.
pub const File = struct { path: []const u8, bytes: []const u8 };

/// The files a side contributes to the review, each list sorted by path.
pub const Files = struct { decisions: []const File = &.{}, notes: []const File = &.{}, sources: []const File = &.{} };

/// Why a side's declarations did not load: the located compiler diagnostic when the
/// source has one, else the name of the error that stopped the load. A diagnostic
/// located in the release loader's synthesized root has no path of its own: it sets
/// `project_module`, and the refusal says a project module does not load.
pub const Problem = struct { path: []const u8 = "", line: usize = 0, code: []const u8 = "", message: []const u8, project_module: bool = false, rule: ?@import("diagnostic.zig").Rule = null };

/// A side whose declarations loaded. `model` keeps the strings of `document` alive.
pub const Loaded = struct { model: loader.Model, document: overview_types.Document, entries: []const baseline.Entry };

/// One side of the review: its files, and its state when the declarations load.
pub const Side = struct {
    files: Files = .{},
    state: State = .absent,

    /// Whether the project does not exist on this side, or loaded, or failed to load.
    pub const State = union(enum) { absent, unreadable: Problem, loaded: Loaded };

    /// Release the model of a loaded side; a side that did not load owns nothing.
    pub fn deinit(self: *Side) void {
        if (self.state == .loaded) self.state.loaded.model.deinit();
        self.* = undefined;
    }
};

/// Load the project in `directory` as one side. `gpa` owns the model, which the
/// caller releases with `Side.deinit`; `a` owns everything else.
pub fn load(gpa: std.mem.Allocator, a: std.mem.Allocator, io: std.Io, directory: []const u8) Error!Side {
    var failure: loader.Failure = .{};
    var model = loader.loadWith(gpa, io, directory, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.HostIo => return error.HostIo,
        else => {
            // The loader duplicated the located failure with `gpa`; keep the arena copy only.
            defer releaseFailure(gpa, failure);
            return .{ .files = try readFiles(a, io, directory, .{}), .state = .{ .unreadable = try problem(a, err, failure) } };
        },
    };
    errdefer model.deinit();
    const files = try readFiles(a, io, model.root, model.options);
    const document = try overview_collect.collect(a, &model, overview_store.Store{});
    const entries = try baseline.parseReleaseBaseline(a, try api_diff.snapshotPublic(a, model.index, model.modules));
    return .{ .files = files, .state = .{ .loaded = .{ .model = model, .document = document, .entries = entries } } };
}

/// Free the strings `release_project_load` duplicated into a located failure.
fn releaseFailure(gpa: std.mem.Allocator, failure: loader.Failure) void {
    if (!failure.present) return;
    gpa.free(failure.path);
    gpa.free(failure.code);
    gpa.free(failure.message);
}

/// The located problem of a failed load, or the error's name when no diagnostic locates it.
fn problem(a: std.mem.Allocator, err: anyerror, failure: loader.Failure) Error!Problem {
    if (!failure.present) return .{ .message = @errorName(err) };
    if (loader.isSynthesizedRoot(failure.path)) return .{
        .code = try a.dupe(u8, failure.code),
        .message = try a.dupe(u8, failure.message),
        .rule = failure.rule,
        .project_module = true,
    };
    return .{
        .path = try a.dupe(u8, failure.path),
        .line = failure.line,
        .code = try a.dupe(u8, failure.code),
        .message = try a.dupe(u8, failure.message),
        .rule = failure.rule,
    };
}

/// Read every decision and change-note Markdown file, and every source file, under
/// `root`. Hidden directories, `build/`, `release.exclude` paths and the top-level
/// evidence directories are skipped; the decisions and changes directories are read
/// for Markdown only.
pub fn readFiles(a: std.mem.Allocator, io: std.Io, root: []const u8, options: release_config.Options) Error!Files {
    var directory = std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true }) catch return error.HostIo;
    defer directory.close(io);
    var walker = try directory.walk(a);
    defer walker.deinit();
    var decisions: std.ArrayList(File) = .empty;
    var notes: std.ArrayList(File) = .empty;
    var sources: std.ArrayList(File) = .empty;
    while (walker.next(io) catch return error.HostIo) |item| {
        if (item.kind == .directory) {
            if (skippedDirectory(item.path, options)) walker.leave(io);
            continue;
        }
        if (item.kind != .file) continue;
        if (inside(item.path, options.decisions) and std.mem.endsWith(u8, item.path, ".md")) {
            try decisions.append(a, try read(a, io, directory, item.path));
        } else if (inside(item.path, options.changes) and std.mem.endsWith(u8, item.path, ".md")) {
            try notes.append(a, try read(a, io, directory, item.path));
        } else if (sourceFile(item.path, options)) {
            try sources.append(a, try read(a, io, directory, item.path));
        }
    }
    return .{
        .decisions = try sorted(a, decisions.items),
        .notes = try sorted(a, notes.items),
        .sources = try sorted(a, sources.items),
    };
}

/// Every Markdown file under one project-relative directory, sorted by path; empty when
/// the directory does not exist.
pub fn markdownUnder(a: std.mem.Allocator, io: std.Io, root: []const u8, relative: []const u8) Error![]const File {
    const absolute = try std.fs.path.join(a, &.{ root, relative });
    var directory = std.Io.Dir.cwd().openDir(io, absolute, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return error.HostIo,
    };
    defer directory.close(io);
    var walker = try directory.walk(a);
    defer walker.deinit();
    var files: std.ArrayList(File) = .empty;
    while (walker.next(io) catch return error.HostIo) |item| {
        if (item.kind != .file or !std.mem.endsWith(u8, item.path, ".md")) continue;
        try files.append(a, try read(a, io, directory, item.path));
    }
    const named = try a.alloc(File, files.items.len);
    for (files.items, named) |file, *out| out.* = .{ .path = try std.fs.path.join(a, &.{ relative, file.path }), .bytes = file.bytes };
    return sorted(a, named);
}

/// Whether a directory the walk meets holds nothing the review reads: a hidden or
/// build directory, an excluded path, or a top-level evidence directory.
fn skippedDirectory(path: []const u8, options: release_config.Options) bool {
    if (release_project.excluded(path, options.exclude)) return true;
    for (evidence_directories) |name| if (std.mem.eql(u8, path, name)) return true;
    return false;
}

/// Whether a file is a source the review compares: a `.selka` file, or the project's own `selka.json`.
pub fn sourceFile(path: []const u8, options: release_config.Options) bool {
    if (release_project.excluded(path, options.exclude)) return false;
    if (std.mem.eql(u8, path, product.project_file)) return true;
    return product.isSource(path);
}

/// The overview declaration with this qualified name, if the document lists it.
pub fn declaration(document: *const overview_types.Document, name: []const u8) ?overview_types.Declaration {
    for (document.modules) |module| {
        for (module.declarations) |found| {
            if (std.mem.eql(u8, found.name, name)) return found;
        }
    }
    return null;
}

/// Whether `path` names `directory` or a file below it.
pub fn inside(path: []const u8, directory: []const u8) bool {
    if (std.mem.eql(u8, path, directory)) return true;
    return path.len > directory.len and std.mem.startsWith(u8, path, directory) and path[directory.len] == '/';
}

fn read(a: std.mem.Allocator, io: std.Io, directory: std.Io.Dir, path: []const u8) Error!File {
    const owned = try a.dupe(u8, path);
    const bytes = directory.readFileAlloc(io, owned, a, .limited(max_file_bytes)) catch return error.HostIo;
    return .{ .path = owned, .bytes = bytes };
}

fn sorted(a: std.mem.Allocator, files: []const File) Error![]const File {
    const copy = try a.dupe(File, files);
    std.mem.sort(File, copy, {}, fileLess);
    return copy;
}

fn fileLess(_: void, left: File, right: File) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}

test "review side reads only .selka files and the root selka.json as source" {
    const options: release_config.Options = .{ .exclude = &.{"generated"} };
    try std.testing.expect(sourceFile("main.selka", options));
    try std.testing.expect(sourceFile("app/serve.selka", options));
    try std.testing.expect(sourceFile("selka.json", options));
    try std.testing.expect(!sourceFile("generated/ports.selka", options));
    try std.testing.expect(!sourceFile(".hidden.selka", options));
    try std.testing.expect(!sourceFile("build/out.selka", options));
    try std.testing.expect(!sourceFile("notes.md", options));
}

test "review side skips evidence directories but keeps decisions and changes" {
    const options: release_config.Options = .{};
    try std.testing.expect(skippedDirectory("friction", options));
    try std.testing.expect(skippedDirectory("results", options));
    try std.testing.expect(skippedDirectory(".selka-cache", options));
    try std.testing.expect(!skippedDirectory("decisions", options));
    try std.testing.expect(!skippedDirectory("changes", options));
    try std.testing.expect(!skippedDirectory("app", options));
}

test "review side matches a path inside a directory by whole segments" {
    try std.testing.expect(inside("decisions/0.2/x.md", "decisions"));
    try std.testing.expect(inside("decisions", "decisions"));
    try std.testing.expect(!inside("decisions2/x.md", "decisions"));
}

test "review side releases every string of a located load failure" {
    const gpa = std.testing.allocator;
    const failure: loader.Failure = .{
        .present = true,
        .path = try gpa.dupe(u8, "main.selka"),
        .line = 3,
        .column = 1,
        .code = try gpa.dupe(u8, "E_SYNTAX"),
        .message = try gpa.dupe(u8, "unexpected token"),
    };
    // The testing allocator fails this test if any of the three strings is left behind.
    releaseFailure(gpa, failure);
    try std.testing.expect(failure.present);
}

test "review side says a project module does not load when the synthesized root is located" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const located: loader.Failure = .{ .present = true, .path = "_release_docs_root.selka", .line = 1, .code = "E_MODULE_READ", .message = "cannot load missing.selka: NotFound" };
    const mapped = try problem(a, error.SourceError, located);
    try std.testing.expect(mapped.project_module);
    try std.testing.expectEqualStrings("", mapped.path);
    try std.testing.expectEqualStrings("cannot load missing.selka: NotFound", mapped.message);
    const plain: loader.Failure = .{ .present = true, .path = "main.selka", .line = 3, .code = "E_SYNTAX", .message = "unexpected token" };
    const kept = try problem(a, error.SourceError, plain);
    try std.testing.expect(!kept.project_module);
    try std.testing.expectEqualStrings("main.selka", kept.path);
}
