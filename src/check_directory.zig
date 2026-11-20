//! `selka check DIR`: every module of a project, in one check.
//!
//! `selka check ENTRY.selka` loads the modules `ENTRY` imports and no others, so a module nothing
//! imports (a library not yet wired in, a test module, a tool) could hold any error and the check
//! would pass. A directory names the project instead: every `.selka` source beneath it is a module,
//! and the check loads all of them through one generated entry, `selka_check_all`, that imports
//! each and declares an empty `main`. The entry exists only in memory; the modules are checked
//! exactly as an import from any other module would check them, and the one check shares its work
//! across the whole project.
//!
//! Module names follow `selka test DIR` and `selka fix DIR`: they are the paths beneath the
//! project root, the directory holding the nearest `selka.json` at or above `DIR`, else `DIR`.
//! Hidden directories, `build`, `zig-out`, `node_modules` and the `release.exclude` paths of the
//! configuration are not part of the project, wherever they lie beneath `DIR`; `DIR` itself, and the folders above it, are
//! the user's own choice and are walked whatever they are called (`selka check build`). A file whose name cannot be
//! imported (a hyphen, a leading digit) is skipped and named.
const std = @import("std");
const product = @import("product.zig");
const project_config = @import("project_config.zig");
const release_project = @import("release_project.zig");

/// The reserved module name of the generated entry. A project that has a module of this name
/// is refused, since the entry would shadow it; `release_project` and the warnings skip it.
pub const entry_name = "selka_check_all";

/// The module name of the entry a `selka test DIR` run generates for the check its roots share (`test_runner_union.zig`): one
/// import of each root and an empty `main`. It exists only in memory, and the runner loads its roots one by one when a project
/// module of that name sits at the root.
pub const directory_run_entry_name = "selka_directory_run";

/// What a directory check could not start from.
pub const Error = std.mem.Allocator.Error || error{ ReadFailed, NotInsideProject, ReservedName };

/// The modules of one project directory.
pub const Inventory = struct {
    /// Dotted module names (`placement.drc` for `placement/drc.selka`), in path order.
    modules: []const []const u8,
    /// Project-relative paths of `.selka` files whose names are not module names, in path order.
    skipped: []const []const u8,
};

/// Where to look and how to name what is found: `directory` and `root` are absolute, `directory` lies
/// within `root`, and `exclusions` are the project-relative paths the configuration leaves out.
pub const Scan = struct { directory: []const u8, root: []const u8, exclusions: []const []const u8 = &.{} };

/// A directory check, ready to run: the virtual entry and the modules it imports.
pub const Plan = struct {
    /// Absolute path of the generated entry, `<directory>/selka_check_all.selka`; the file does not exist.
    entry_path: []const u8,
    /// The source of the generated entry.
    source: []const u8,
    /// How many modules the entry imports.
    module_count: usize,
    /// Project-relative paths that were skipped because they are not module names.
    skipped: []const []const u8,
};

/// Whether `name`, an entry beneath the directory a check names, is a directory or file the project walk leaves alone.
fn generated(name: []const u8) bool {
    return std.mem.startsWith(u8, name, ".") or std.mem.eql(u8, name, "build") or std.mem.eql(u8, name, "zig-out") or std.mem.eql(u8, name, "node_modules");
}

/// Whether `module` (a dotted module name) is the generated entry of a directory check.
pub fn isEntry(module: []const u8) bool {
    if (std.mem.eql(u8, module, entry_name)) return true;
    return std.mem.endsWith(u8, module, entry_name) and module[module.len - entry_name.len - 1] == '.';
}

/// The top-level names of a project's modules, as `selka packages lock` reads them: it accepts a root only when every source is
/// `NAME.selka` or under `NAME/`, so modules (the generated entry apart) with two top-level names are no package's root. `add` each
/// module's dotted name; `several` is then true when no package root could hold them. No module, or one name, may be a package.
pub const Namespaces = struct {
    first: ?[]const u8 = null,
    several: bool = false,

    /// Take in one module's dotted name; the generated entry names no namespace.
    pub fn add(self: *Namespaces, module: []const u8) void {
        if (isEntry(module)) return;
        const top = module[0 .. std.mem.indexOfScalar(u8, module, '.') orelse module.len];
        const seen = self.first orelse {
            self.first = top;
            return;
        };
        if (!std.mem.eql(u8, seen, top)) self.several = true;
    }
};

/// Whether `module` is an entry a command generates to load a project's modules together: a directory check's (`isEntry`) or
/// a directory test run's shared check's (`directory_run_entry_name`). Such an entry imports a module only to load it, so its
/// import does not make a test file a module that another module imports (`interfaces.Index.testsModule`).
pub fn isGeneratedEntry(module: []const u8) bool {
    return isEntry(module) or std.mem.eql(u8, module, directory_run_entry_name);
}

/// The stub `main` the test runner appends to a test file that declares none, so that the file can be checked and built as a
/// program (`test_runner.zig: check_stub`).
pub const test_stub = "\n\n# the test runner's entry point, appended to a test file that has none\nfunc main() -> int:\n    return 0\n";

/// Whether the declaration at `span` of a module whose text is `bytes` is the `main` of that stub: the name in the stub that
/// ends the text. A test file that imports a module named `main` (`import main`) would otherwise meet its own stub as a
/// declaration that conflicts with the import alias (FR19); the stub is the runner's, never the author's, which is why it
/// carries a comment that says so: a file of the author's own that declares `main` is still refused.
pub fn isTestStubMain(bytes: []const u8, span: @import("source.zig").Span) bool {
    if (!std.mem.endsWith(u8, bytes, test_stub)) return false;
    const stub_start = bytes.len - test_stub.len;
    const name_at = stub_start + std.mem.indexOf(u8, test_stub, "main").?;
    return span.start == name_at;
}

/// The source of the generated entry: one aliased import per module and an empty `main`.
pub fn entrySource(allocator: std.mem.Allocator, modules: []const []const u8) std.mem.Allocator.Error![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    for (modules, 0..) |name, position| try text.print(allocator, "import {s} as root_{d}\n", .{ name, position });
    try text.appendSlice(allocator, "\nfunc main() -> int:\n    return 0\n");
    return text.items;
}

/// Every `.selka` source beneath `scan.directory`, named relative to `scan.root`. All allocations come
/// from `arena`.
pub fn collect(arena: std.mem.Allocator, io: std.Io, scan: Scan) Error!Inventory {
    if (!std.mem.startsWith(u8, scan.directory, scan.root)) return error.NotInsideProject;
    var directory = std.Io.Dir.cwd().openDir(io, scan.directory, .{ .iterate = true, .follow_symlinks = false }) catch return error.ReadFailed;
    defer directory.close(io);
    var walker = directory.walk(arena) catch return error.ReadFailed;
    defer walker.deinit();
    var modules: std.ArrayList([]const u8) = .empty;
    var skipped: std.ArrayList([]const u8) = .empty;
    // The folder the check names, relative to the root: its own name and the ones above it are never a reason to leave it out.
    const named = if (scan.directory.len > scan.root.len + 1) scan.directory[scan.root.len + 1 ..] else "";
    while (walker.next(io) catch return error.ReadFailed) |item| {
        const absolute = try std.fs.path.join(arena, &.{ scan.directory, item.path });
        const relative = if (absolute.len > scan.root.len + 1) absolute[scan.root.len + 1 ..] else "";
        if (generated(item.basename) or release_project.excludedBeneath(relative, named, scan.exclusions)) {
            if (item.kind == .directory) walker.leave(io);
            continue;
        }
        if (item.kind != .file or !product.isSource(relative)) continue;
        const stem = product.sourceStem(relative);
        if (!project_config.validModuleName(stem)) {
            try skipped.append(arena, relative);
            continue;
        }
        const name = try arena.dupe(u8, stem);
        for (name) |*byte| {
            if (byte.* == std.fs.path.sep) byte.* = '.';
        }
        if (isEntry(name)) return error.ReservedName;
        try modules.append(arena, name);
    }
    std.mem.sort([]const u8, modules.items, {}, lessThan);
    std.mem.sort([]const u8, skipped.items, {}, lessThan);
    return .{ .modules = modules.items, .skipped = skipped.items };
}

fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

/// Plan the check of the project at `directory_argument` (a path to a directory): find its root and its
/// configuration, collect its modules and write the generated entry that imports them.
pub fn plan(arena: std.mem.Allocator, io: std.Io, directory_argument: []const u8) Error!Plan {
    const directory = std.Io.Dir.cwd().realPathFileAlloc(io, directory_argument, arena) catch return error.ReadFailed;
    const entry_path = try std.fs.path.join(arena, &.{ directory, entry_name ++ product.source_suffix });
    const configuration = project_config.discover(arena, io, entry_path) catch return error.ReadFailed;
    const root = if (configuration) |path| (std.fs.path.dirname(path) orelse directory) else directory;
    var exclusions: []const []const u8 = &.{};
    if (configuration) |path| {
        var failure: project_config.Failure = .{};
        // A configuration that does not load is reported by the check proper; it excludes nothing here.
        if (project_config.load(arena, io, path, &failure)) |loaded| {
            exclusions = loaded.releaseOptions().exclude;
        } else |_| {}
    }
    const found = try collect(arena, io, .{ .directory = directory, .root = root, .exclusions = exclusions });
    return .{
        .entry_path = entry_path,
        .source = try entrySource(arena, found.modules),
        .module_count = found.modules.len,
        .skipped = found.skipped,
    };
}

/// Create each of `paths` under `directory` as an empty file.
fn writeEmpty(directory: std.Io.Dir, paths: []const []const u8) !void {
    for (paths) |path| try directory.writeFile(std.testing.io, .{ .sub_path = path, .data = "" });
}

test "entrySource imports every module under its own alias and declares an empty main" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try entrySource(arena.allocator(), &.{ "a", "placement.drc" });
    try std.testing.expectEqualStrings("import a as root_0\nimport placement.drc as root_1\n\nfunc main() -> int:\n    return 0\n", text);
}

/// Whether no package root could hold the modules named `names`.
fn noPackageRoot(names: []const []const u8) bool {
    var spaces: Namespaces = .{};
    for (names) |name| spaces.add(name);
    return spaces.several;
}

test "Namespaces finds a project no package root could hold: two top-level names, the generated entry apart" {
    try std.testing.expect(!noPackageRoot(&.{ "selka_check_all", "numbers", "numbers.more", "numbers.more.deep" }));
    try std.testing.expect(noPackageRoot(&.{ "selka_check_all", "rows", "rows_test", "main" }));
    try std.testing.expect(!noPackageRoot(&.{"rows"}));
    // A check of one directory below the project root sees the directory's name as the one namespace: it may still be a package.
    try std.testing.expect(!noPackageRoot(&.{ "src.selka_check_all", "src.rows", "src.rows_test" }));
}

test "isEntry names the generated entry in any directory of the project" {
    try std.testing.expect(isEntry("selka_check_all"));
    try std.testing.expect(isEntry("src.selka_check_all"));
    try std.testing.expect(!isEntry("my_selka_check_all"));
    try std.testing.expect(!isEntry("selka_check_all_two"));
}

test "collect names modules by path, skips hidden and excluded paths and reports unimportable names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    try temporary.dir.createDirPath(io, "src/placement");
    try temporary.dir.createDirPath(io, "src/.cache");
    try temporary.dir.createDirPath(io, "src/build");
    try temporary.dir.createDirPath(io, "src/vendor");
    try writeEmpty(temporary.dir, &.{ "src/main.selka", "src/placement/drc.selka", "src/placement/drc_test.selka", "src/.cache/hidden.selka", "src/build/out.selka", "src/vendor/lib.selka", "src/bad-name.selka", "src/notes.txt" });
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const found = try collect(a, io, .{ .directory = root, .root = root, .exclusions = &.{"src/vendor"} });
    try std.testing.expectEqual(@as(usize, 3), found.modules.len);
    try std.testing.expectEqualStrings("src.main", found.modules[0]);
    try std.testing.expectEqualStrings("src.placement.drc", found.modules[1]);
    try std.testing.expectEqualStrings("src.placement.drc_test", found.modules[2]);
    try std.testing.expectEqual(@as(usize, 1), found.skipped.len);
    try std.testing.expectEqualStrings("src/bad-name.selka", found.skipped[0]);
}

test "collect walks a folder it is named whatever it is called, and leaves the generated names beneath it alone (FR85)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    try temporary.dir.createDirPath(io, "tools/build/build");
    try temporary.dir.createDirPath(io, "tools/build/node_modules");
    try temporary.dir.createDirPath(io, ".hidden");
    try writeEmpty(temporary.dir, &.{ "tools/build/t.selka", "tools/build/build/out.selka", "tools/build/node_modules/n.selka", ".hidden/h.selka", "tools/x.selka" });
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const named = try collect(a, io, .{ .directory = try std.fs.path.join(a, &.{ root, "tools/build" }), .root = root });
    try std.testing.expectEqual(@as(usize, 1), named.modules.len);
    try std.testing.expectEqualStrings("tools.build.t", named.modules[0]);
    // A hidden folder named is walked too; no module name begins with a dot, so its file is named as one that cannot be imported.
    const hidden = try collect(a, io, .{ .directory = try std.fs.path.join(a, &.{ root, ".hidden" }), .root = root });
    try std.testing.expectEqual(@as(usize, 0), hidden.modules.len);
    try std.testing.expectEqualStrings(".hidden/h.selka", hidden.skipped[0]);
    // A walk of the project root, or of a folder above `build`, still leaves `build` and the hidden folder alone.
    const whole = try collect(a, io, .{ .directory = root, .root = root });
    try std.testing.expectEqual(@as(usize, 1), whole.modules.len);
    try std.testing.expectEqualStrings("tools.x", whole.modules[0]);
}

test "collect refuses a project that has a module named like the generated entry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "selka_check_all.selka", .data = "" });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try std.testing.expectError(error.ReservedName, collect(a, std.testing.io, .{ .directory = root, .root = root }));
}

test "collect refuses a directory that is not inside the project root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.NotInsideProject, collect(arena.allocator(), std.testing.io, .{ .directory = "/elsewhere", .root = "/project" }));
}
