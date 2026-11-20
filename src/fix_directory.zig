//! When a directory `selka fix` run may check the whole project once per round instead of every entry file on its own
//! (FR23, `docs/tooling/fix.md`). Every `.selka` file beneath the directory is an entry, and a round used to start one
//! `selka check` per entry, each of which checked its entry's whole import graph again: a module was checked once for
//! every entry above it. `selka check DIR` checks every module of the project once, through one generated entry, so a
//! round costs one project check when its answer is the entries' answer.
//!
//! That holds when every entry would be checked as a module of the same project: each entry's root is the directory
//! check's root, every entry is one of its modules (none skipped for its name, none left out by `release.exclude`), and no
//! source the project can load holds a docstring example (those are checked per entry with `check --examples`). This file
//! decides that from facts `fix` gathers, scans a project for examples and links that leave it, and counts the checks a
//! run starts for `fix --report`.
const std = @import("std");
const product = @import("compiler_root").compiler_language.product;

/// What `fix` found out about a directory before its first round.
pub const Facts = struct {
    /// Entry files the run fixes.
    entries: usize,
    /// Modules `check DIR` would load through its generated entry, and how many files it skips for their names.
    modules: usize,
    skipped: usize,
    /// Whether every entry's own check would resolve its imports beneath the directory check's root.
    same_root: bool,
    /// What a scan of the root found (`scanRoot`).
    scan: Scan,
};

/// Whether the run may check the directory as one project: more than one entry, each a module of one project with the
/// directory check's root, and nothing an entry's own check would add (a docstring example, a source reached through a
/// link that leaves the root).
pub fn eligible(facts: Facts) bool {
    return facts.entries > 1 and facts.modules == facts.entries and facts.skipped == 0 and facts.same_root and
        !facts.scan.examples and !facts.scan.outside_link;
}

/// Whether an entry whose own check takes `entry_root` as its import root is a module of the project `selka check DIR` loads
/// from `root`. With a `selka.json` (`unconfigured` false) that is so when the two are the same directory. Where no
/// `selka.json` governs the directory or the entry, `check DIR` takes the directory as the root of every file beneath it
/// (`check_directory.plan`: `rows/more.selka` is the module `rows.more`) while a check of the one file takes the folder it sits
/// in, so an entry in a folder below the root is still a module of that project: its own check cannot say what the project
/// check does, and the project check does, as it does for the files beside the root.
pub fn sharesRoot(entry_root: []const u8, root: []const u8, unconfigured: bool) bool {
    return if (unconfigured) within(root, entry_root) else std.mem.eql(u8, entry_root, root);
}

/// What the sources beneath a project root hold that a whole-project check would not answer as the entries' checks do.
pub const Scan = struct {
    /// A `.selka` source holds `>>> `, the mark of a docstring example (`example_check.zig: holdsExamples`).
    examples: bool = false,
    /// A symbolic link beneath the root names something outside it, so a module could be loaded from there.
    outside_link: bool = false,
};

/// The mark `check --examples` looks for in a module's text before it compiles anything.
const example_mark = ">>> ";
/// Largest source file read, the loader's own ceiling.
const file_limit = 16 * 1024 * 1024;

/// Why a project root could not be scanned.
pub const ScanError = error{ OutOfMemory, ReadFailed };

/// Walk every file beneath `root` (absolute; hidden directories are not entered, links are not followed) and report
/// whether a `.selka` file holds an example mark or a link leaves the root. A file that cannot be read counts as one that
/// holds an example, so the run keeps checking entries on their own.
pub fn scanRoot(allocator: std.mem.Allocator, io: std.Io, root: []const u8) ScanError!Scan {
    var scan: Scan = .{};
    var directory = std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true, .follow_symlinks = false }) catch return error.ReadFailed;
    defer directory.close(io);
    var walker = try directory.walk(allocator);
    defer walker.deinit();
    while (walker.next(io) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.ReadFailed,
    }) |item| {
        if (item.kind == .directory and item.basename.len != 0 and item.basename[0] == '.') {
            walker.leave(io);
            continue;
        }
        const path = try std.fs.path.join(allocator, &.{ root, item.path });
        defer allocator.free(path);
        if (item.kind == .sym_link) {
            const target = std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator) catch {
                scan.outside_link = true;
                continue;
            };
            defer allocator.free(target);
            if (!within(root, target)) scan.outside_link = true;
            continue;
        }
        if (item.kind != .file or !product.isSource(item.basename)) continue;
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(file_limit)) catch {
            scan.examples = true;
            continue;
        };
        defer allocator.free(bytes);
        if (std.mem.indexOf(u8, bytes, example_mark) != null) scan.examples = true;
    }
    return scan;
}

/// Whether `path` is `root` or lies beneath it; both are absolute.
fn within(root: []const u8, path: []const u8) bool {
    if (!std.mem.startsWith(u8, path, root)) return false;
    return path.len == root.len or path[root.len] == std.fs.path.sep;
}

/// Whether a repair's edit depends on the callers the checked program holds, so that a project check and an entry's check
/// can offer different edits for it. `E_BORROW_UNDECLARED` declares `from` only when no caller keeps the result and copies
/// the returns otherwise (F-8, F-15): an entry's program holds the callers its graph reaches, the project's holds them all.
/// A round that meets one checks the entries. (`W_COPY_MOVE` is judged against the callers too, and carries no repair.)
pub fn callerDependent(code: []const u8) bool {
    return std.mem.eql(u8, code, "E_BORROW_UNDECLARED");
}

/// Whether the status of a path of a run of several paths may no longer be true. A path that ended with errors left (status 1)
/// before a later path wrote files (the run had taken more rounds by then) may be clean now, because the later path repaired the
/// module its errors were in. Under `--check` nothing is written, and a path that ended clean or in a host failure stands.
pub fn mayBeStale(status: u8, rounds_at_end: usize, rounds_now: usize, check: bool) bool {
    return !check and status == 1 and rounds_at_end != rounds_now;
}

/// The checks one `fix` run started, for `fix --report`. Workers of a round count concurrently.
pub const Checks = struct {
    /// `selka check DIR` runs, one per round of a directory checked as one project, and its final check.
    directory: std.atomic.Value(usize) = .init(0),
    /// `selka check ENTRY` runs, one per entry checked on its own.
    entry: std.atomic.Value(usize) = .init(0),
    /// `selka check ENTRY --examples` runs.
    examples: std.atomic.Value(usize) = .init(0),

    /// The kind of check one process ran.
    pub const Kind = enum { directory, entry, examples };

    /// Count one check of `kind`.
    pub fn count(checks: *Checks, kind: Kind) void {
        const counter = switch (kind) {
            .directory => &checks.directory,
            .entry => &checks.entry,
            .examples => &checks.examples,
        };
        _ = counter.fetchAdd(1, .monotonic);
    }

    /// The one line `fix --report` prints on standard error after the summary.
    pub fn line(checks: *const Checks, allocator: std.mem.Allocator, rounds: usize) std.mem.Allocator.Error![]const u8 {
        return std.fmt.allocPrint(allocator, "fix report: {d} round{s} with edits, {d} directory check{s}, {d} entry check{s}, {d} example check{s}\n", .{
            rounds,                            plural(rounds),
            checks.directory.load(.monotonic), plural(checks.directory.load(.monotonic)),
            checks.entry.load(.monotonic),     plural(checks.entry.load(.monotonic)),
            checks.examples.load(.monotonic),  plural(checks.examples.load(.monotonic)),
        });
    }
};

fn plural(count: usize) []const u8 {
    return if (count == 1) "" else "s";
}

test "a directory is checked as one project only when every entry is a module of it with its root and nothing else" {
    const clean: Facts = .{ .entries = 3, .modules = 3, .skipped = 0, .same_root = true, .scan = .{} };
    try std.testing.expect(eligible(clean));
    var one = clean;
    one.entries = 1;
    one.modules = 1;
    try std.testing.expect(!eligible(one));
    var excluded = clean;
    excluded.modules = 2;
    try std.testing.expect(!eligible(excluded));
    var named = clean;
    named.skipped = 1;
    try std.testing.expect(!eligible(named));
    var rooted = clean;
    rooted.same_root = false;
    try std.testing.expect(!eligible(rooted));
    var examples = clean;
    examples.scan.examples = true;
    try std.testing.expect(!eligible(examples));
    var linked = clean;
    linked.scan.outside_link = true;
    try std.testing.expect(!eligible(linked));
}

test "an entry in a folder below an unconfigured directory shares its project root, and below a configured one it does not" {
    // No `selka.json` anywhere: `check DIR` roots every file at the directory, so `rows/more.selka` is the module `rows.more`.
    try std.testing.expect(sharesRoot("/p", "/p", true));
    try std.testing.expect(sharesRoot("/p/rows", "/p", true));
    try std.testing.expect(sharesRoot("/p/rows/deep", "/p", true));
    // A folder whose name only starts like the root, and the folder above it, are not beneath it.
    try std.testing.expect(!sharesRoot("/p-other", "/p", true));
    try std.testing.expect(!sharesRoot("/", "/p", true));
    // With a `selka.json` the entry's own root is the project's or another project: the same directory or nothing.
    try std.testing.expect(sharesRoot("/p", "/p", false));
    try std.testing.expect(!sharesRoot("/p/rows", "/p", false));
}

test "a scan finds an example mark in a source and a link that leaves the root, and nothing in a hidden directory" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const a = std.testing.allocator;
    try directory.dir.createDirPath(std.testing.io, "project/lib");
    try directory.dir.createDirPath(std.testing.io, "project/.hidden");
    try directory.dir.createDirPath(std.testing.io, "elsewhere");
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "project/main.selka", .data = "func main() -> int:\n    return 0\n" });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "project/.hidden/doc.selka", .data = "# >>> 1\n" });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "project/notes.txt", .data = ">>> not a source\n" });
    const root = try directory.dir.realPathFileAlloc(std.testing.io, "project", a);
    defer a.free(root);
    try std.testing.expectEqual(Scan{}, try scanRoot(a, std.testing.io, root));
    try directory.dir.symLink(std.testing.io, "lib", "project/inside", .{ .is_directory = true });
    try std.testing.expectEqual(Scan{}, try scanRoot(a, std.testing.io, root));
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "project/lib/util.selka", .data = "## Twice.\n##     >>> twice(2)\n" });
    try std.testing.expectEqual(Scan{ .examples = true }, try scanRoot(a, std.testing.io, root));
    try directory.dir.symLink(std.testing.io, "../elsewhere", "project/away", .{ .is_directory = true });
    try std.testing.expectEqual(Scan{ .examples = true, .outside_link = true }, try scanRoot(a, std.testing.io, root));
}

test "only the from-clause repair depends on which callers the checked program holds" {
    try std.testing.expect(callerDependent("E_BORROW_UNDECLARED"));
    try std.testing.expect(!callerDependent("W_MATCH_ELSE"));
    try std.testing.expect(!callerDependent("E_OWN_MARKER"));
    try std.testing.expect(!callerDependent("E_BUILTIN_FUNCTION_NAME"));
}

test "the report line counts each kind of check" {
    var checks: Checks = .{};
    checks.count(.directory);
    checks.count(.directory);
    checks.count(.entry);
    const text = try checks.line(std.testing.allocator, 1);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("fix report: 1 round with edits, 2 directory checks, 1 entry check, 0 example checks\n", text);
}

test "a path's status may be stale only when errors were left and a later path wrote files, and never under --check" {
    try std.testing.expect(mayBeStale(1, 1, 2, false));
    try std.testing.expect(!mayBeStale(1, 2, 2, false));
    try std.testing.expect(!mayBeStale(0, 1, 2, false));
    try std.testing.expect(!mayBeStale(2, 1, 2, false));
    try std.testing.expect(!mayBeStale(1, 0, 1, true));
}
