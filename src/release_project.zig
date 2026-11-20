//! Pure, deterministic project-root and module selection for every release command.
const std = @import("std");
const product = @import("product.zig");
const config = @import("release_config.zig");

/// One root-relative source file and its syntax-derived discovery flags.
pub const File = struct { path: []const u8, test_bearing: bool = false, example_bearing: bool = false };
/// Configured entry order, sorted test roots and their sorted deduplicated union.
pub const Selection = struct { entries: []const []const u8, test_roots: []const []const u8, roots: []const []const u8 };
/// One loaded module and its direct import indices.
pub const Module = struct { path: []const u8, imports: []const usize, standard: bool = false };
/// Invalid entries and out-of-range graph edges are rejected before traversal.
pub const Error = error{ InvalidEntry, InvalidGraph, OutOfMemory };

/// Select configured entries or the named/default entry and all eligible tests/examples.
/// Returned strings borrow file/config bytes; list storage belongs to the allocator.
pub fn select(allocator: std.mem.Allocator, files: []const File, default_entry: []const u8, options: config.Options) Error!Selection {
    const entries = if (options.entries.len == 0) try allocator.dupe([]const u8, &.{default_entry}) else try allocator.dupe([]const u8, options.entries);
    var tests: std.ArrayList([]const u8) = .empty;
    var roots: std.ArrayList([]const u8) = .empty;
    for (entries) |entry| {
        if (excluded(entry, options.exclude) or !exists(files, entry)) return error.InvalidEntry;
        try appendUnique(allocator, &roots, entry);
    }
    for (files) |file| {
        if (excluded(file.path, options.exclude)) continue;
        if (!file.test_bearing and !file.example_bearing) continue;
        try appendUnique(allocator, &tests, file.path);
        try appendUnique(allocator, &roots, file.path);
    }
    std.mem.sort([]const u8, tests.items, {}, less);
    std.mem.sort([]const u8, roots.items, {}, less);
    return .{ .entries = entries, .test_roots = try tests.toOwnedSlice(allocator), .roots = try roots.toOwnedSlice(allocator) };
}

fn exists(files: []const File, path: []const u8) bool {
    for (files) |file| if (std.mem.eql(u8, file.path, path)) return true;
    return false;
}

fn appendUnique(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), path: []const u8) !void {
    for (list.items) |present| if (std.mem.eql(u8, present, path)) return;
    try list.append(allocator, path);
}

fn less(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// Match the test runner's conservative text inventory, including malformed tests.
/// Such files remain roots so checking diagnoses them rather than losing them.
pub fn declaresTests(bytes: []const u8) bool {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.eql(u8, line, "@test")) return true;
        if (std.mem.startsWith(u8, line, "public ")) line = std.mem.trimStart(u8, line[7..], " \t");
        if (std.mem.startsWith(u8, line, "func test_") or std.mem.startsWith(u8, line, "def test_")) return true;
    }
    return false;
}

/// Whether a source/directory is hidden, under build/, or explicitly excluded.
/// Configured exclusions are exact project-relative files or directory prefixes.
pub fn excluded(path: []const u8, exclusions: []const []const u8) bool {
    return excludedBeneath(path, "", exclusions);
}

/// `excluded` for a walk of the folder `named` (project-relative, `""` for the project root): `path` begins with `named`, and the
/// segments of `named` are the user's own choice, so a folder called `build` that a command line names is not left out for its name
/// (FR85); a hidden or `build` segment beneath it is. A path `release.exclude` lists is left out as before.
pub fn excludedBeneath(path: []const u8, named: []const u8, exclusions: []const []const u8) bool {
    // `named` counts only when `path` lies beneath it: one that does not (`..`, a folder beside) chose none of `path`'s segments.
    const folder = std.mem.trim(u8, named, "/");
    const beneath = folder.len != 0 and std.mem.startsWith(u8, path, folder) and (path.len == folder.len or path[folder.len] == '/');
    const chosen: usize = if (beneath) std.mem.count(u8, folder, "/") + 1 else 0;
    var segments = std.mem.splitScalar(u8, path, '/');
    var index: usize = 0;
    while (segments.next()) |segment| : (index += 1) {
        if (index < chosen) continue;
        if (std.mem.startsWith(u8, segment, ".") or std.mem.eql(u8, segment, "build")) return true;
    }
    for (exclusions) |raw| {
        const exclusion = std.mem.trimEnd(u8, raw, "/");
        if (std.mem.eql(u8, path, exclusion)) return true;
        if (std.mem.startsWith(u8, path, exclusion) and path.len > exclusion.len and path[exclusion.len] == '/') return true;
    }
    return false;
}

/// What a walk of a project folder leaves out: `selka test DIR` and `selka packages` both walk by `walkSkips`, so the two see the same
/// folders.
pub const Walk = struct {
    /// The directory of the nearest `selka.json`, else the walked folder: the exclusions are relative to it.
    project_root: []const u8,
    /// `release.exclude` of that `selka.json`.
    exclusions: []const []const u8 = &.{},
    /// The folder `--cache-dir` names, absolute; empty when the command was given none.
    cache: []const u8 = "",
    /// The working directory a relative path is taken from.
    working: []const u8 = "/",
    /// The folder the command line named, absolute, when the walk starts at one beneath `project_root`: its own name, and the
    /// names above it, are never a reason to leave it out (`excludedBeneath`). Empty when the walk starts at `project_root`.
    named: []const u8 = "",
};

/// Whether `name` is a folder (or file) a build generates, by name alone: one beginning with `.` (`.git`, `.zig-cache` and the default
/// cache folder `.selka-cache` among them), `build`, `zig-out` or `node_modules`, at any depth.
pub fn generatedName(name: []const u8) bool {
    return std.mem.startsWith(u8, name, ".") or std.mem.eql(u8, name, "build") or std.mem.eql(u8, name, "zig-out") or std.mem.eql(u8, name, "node_modules");
}

/// Whether a walk leaves out the file or folder `basename` at the absolute path `absolute` (a folder left out is not entered): the
/// `--cache-dir` folder and what is under it, a generated name (`generatedName`), and a path `release.exclude` lists. A scratch folder
/// such as `tmp/` is not among them.
pub fn walkSkips(allocator: std.mem.Allocator, walk: Walk, basename: []const u8, absolute: []const u8) std.mem.Allocator.Error!bool {
    const cache = walk.cache;
    if (cache.len != 0 and std.mem.startsWith(u8, absolute, cache) and (absolute.len == cache.len or absolute[cache.len] == '/')) return true;
    if (generatedName(basename)) return true;
    const relative = try std.fs.path.relative(allocator, walk.working, null, walk.project_root, absolute);
    defer allocator.free(relative);
    const named = if (walk.named.len == 0) "" else try std.fs.path.relative(allocator, walk.working, null, walk.project_root, walk.named);
    defer if (walk.named.len != 0) allocator.free(named);
    return excludedBeneath(relative, named, walk.exclusions);
}

test "a walk leaves out generated names, the cache folder and release.exclude, and nothing else" {
    const walk: Walk = .{ .project_root = "/p", .exclusions = &.{"vendor/"}, .cache = "/p/out/cache" };
    const names = [_]struct { path: []const u8, skipped: bool }{
        .{ .path = "/p/.git", .skipped = true },
        .{ .path = "/p/a/b/.hidden", .skipped = true },
        .{ .path = "/p/a/build", .skipped = true },
        .{ .path = "/p/zig-out", .skipped = true },
        .{ .path = "/p/a/node_modules", .skipped = true },
        .{ .path = "/p/out/cache", .skipped = true },
        .{ .path = "/p/out/cache/core", .skipped = true },
        .{ .path = "/p/vendor", .skipped = true },
        .{ .path = "/p/vendor/lib", .skipped = true },
        .{ .path = "/p/tmp", .skipped = false },
        .{ .path = "/p/out", .skipped = false },
        .{ .path = "/p/out/cache2", .skipped = false },
        .{ .path = "/p/vendors", .skipped = false },
        .{ .path = "/p/builds", .skipped = false },
    };
    for (names) |item| try std.testing.expectEqual(item.skipped, try walkSkips(std.testing.allocator, walk, std.fs.path.basename(item.path), item.path));
}

test "a walk of a folder the command line names leaves out only the generated names beneath it" {
    const walk: Walk = .{ .project_root = "/p", .exclusions = &.{"vendor/"}, .named = "/p/tools/build" };
    const names = [_]struct { path: []const u8, skipped: bool }{
        .{ .path = "/p/tools/build/t.selka", .skipped = false },
        .{ .path = "/p/tools/build/sub", .skipped = false },
        .{ .path = "/p/tools/build/sub/t.selka", .skipped = false },
        .{ .path = "/p/tools/build/build", .skipped = true },
        .{ .path = "/p/tools/build/sub/node_modules", .skipped = true },
        .{ .path = "/p/tools/build/.hidden/t.selka", .skipped = true },
        .{ .path = "/p/tools/build/zig-out", .skipped = true },
    };
    for (names) |item| try std.testing.expectEqual(item.skipped, try walkSkips(std.testing.allocator, walk, std.fs.path.basename(item.path), item.path));
    const hidden: Walk = .{ .project_root = "/p", .named = "/p/.hidden" };
    try std.testing.expect(!try walkSkips(std.testing.allocator, hidden, "t.selka", "/p/.hidden/t.selka"));
    try std.testing.expect(try walkSkips(std.testing.allocator, hidden, ".git", "/p/.hidden/.git"));
    const unnamed: Walk = .{ .project_root = "/p" };
    try std.testing.expect(try walkSkips(std.testing.allocator, unnamed, "build", "/p/build"));
    try std.testing.expect(try walkSkips(std.testing.allocator, unnamed, "t.selka", "/p/build/t.selka"));
}

test "excludedBeneath ignores the names the command line chose and keeps release.exclude" {
    try std.testing.expect(!excludedBeneath("build/t.selka", "build", &.{}));
    try std.testing.expect(!excludedBeneath("a/.b/build/t.selka", "a/.b/build/", &.{}));
    try std.testing.expect(excludedBeneath("build/build/t.selka", "build", &.{}));
    try std.testing.expect(excludedBeneath("build/t.selka", "", &.{}));
    try std.testing.expect(excludedBeneath("build/t.selka", "build", &.{"build/"}));
    // A folder that does not hold `path` chose none of its names.
    try std.testing.expect(excludedBeneath("build/t.selka", "..", &.{}));
    try std.testing.expect(excludedBeneath("builds/build/t.selka", "build", &.{}));
}

/// Union root import closures, excluding test modules, standard modules and exclusions.
/// Returned indices follow sorted relative source paths for checkout-independent output.
pub fn moduleSet(allocator: std.mem.Allocator, modules: []const Module, roots: []const usize, exclusions: []const []const u8) Error![]const usize {
    const visited = try allocator.alloc(bool, modules.len);
    defer allocator.free(visited);
    @memset(visited, false);
    var todo: std.ArrayList(usize) = .empty;
    defer todo.deinit(allocator);
    try todo.appendSlice(allocator, roots);
    var selected: std.ArrayList(usize) = .empty;
    while (todo.pop()) |id| {
        if (id >= modules.len) return error.InvalidGraph;
        if (visited[id]) continue;
        visited[id] = true;
        const module = modules[id];
        if (module.standard or excluded(module.path, exclusions)) continue;
        try todo.appendSlice(allocator, module.imports);
        if (!product.isTestSource(module.path)) try selected.append(allocator, id);
    }
    std.mem.sort(usize, selected.items, modules, moduleLess);
    return selected.toOwnedSlice(allocator);
}

fn moduleLess(modules: []const Module, a: usize, b: usize) bool {
    return std.mem.lessThan(u8, modules[a].path, modules[b].path);
}
