//! `selka fix`: apply every structured diagnostic fix a check publishes, check
//! again, and repeat until nothing mechanical is left; then report what changed
//! per file and the diagnostics that remain for a person to resolve.
//!
//! Each round runs this executable's own `check --diagnostics=json` on the
//! entry, so the fixes are exactly the `fix` fields of `diagnostic-v1`, located
//! by file and UTF-8 byte range. A round applies every fix whose edits do not
//! collide with another fix's; a colliding fix is left for the next round,
//! which sees the updated source, and a fix whose own edits overlap is never
//! applied (`fix_plan.zig`). `--check` runs one round and writes nothing.
//!
//! A directory run checks every entry each round, so a round's checks run
//! across a pool of workers (`SELKA_JOBS`, else the cores free memory allows)
//! and are read back in entry order. An entry is checked again only when the
//! previous round wrote a file it reads or would edit; otherwise its last check
//! stands. A round that changed nothing is confirmed with every entry checked
//! afresh before `fix` stops, so it settles exactly where a serial run does.
//!
//! Several paths on the command line are several runs of all of the above, one after another in the order written, each as if
//! it were named alone (`repairPath`) and each on the files the paths before it left: what the whole invocation reports (the
//! edits per file, the rounds, the diagnostics already printed) carries over, and the status is the worst of the paths'.
//!
//! An entry that checks clean also has its docstring examples checked, the way
//! `selka test` compiles them (`check --examples`): their diagnostics arrive
//! already located in the docstring, and carry a fix only when it maps exactly
//! onto the docstring's text, so the same planning applies them.
const std = @import("std");
const product = @import("compiler_root").compiler_language.product;
const budget = @import("memory_budget");
const language = @import("selka");
const project_config = language.project_config;
const diagnostic_output = @import("selka").diagnostic_output;
const reach = @import("project_reach.zig");
const fix_coverage = @import("fix_coverage.zig");
const fix_memo = @import("fix_memo.zig");
const tuple_scope = @import("fix_tuple_scope.zig");
const input_probe = @import("input_probe.zig");
const fix_directory = @import("fix_directory.zig");

const usage = "usage: selka fix [--check] [--imports] [--warnings] [--report] [--diagnostics=text|json] [--cache-dir=DIR] [--no-cache] <entry.selka|directory>...\n";
/// Rounds one invocation may take before `fix` stops and reports that the fixes did
/// not converge. A round applies all published repairs; ownership checking may
/// expose the next required marker in a function only after the current repair.
/// The cap bounds a repair sequence that does not settle.
const max_rounds = 200;
/// Largest source file a fix is applied to, matching the loader's own ceiling.
const file_limit = 16 * 1024 * 1024;
/// The cache switch `fix` accepts and passes on to every check it runs.
const cache_flag = "--cache-dir=";
/// Memory one check of a round is assumed to need when `SELKA_JOBS` does not set the width: a Debug compiler's check of
/// a 268-module program peaked at 1.4 GiB resident, and a whole-project check of 523 modules at 2.5 GiB (FR23). On a
/// 31 GiB machine with 20 GiB available that is 8 checks at once, where `selka test`'s 512 MiB allowed one per core.
const check_reservation: u64 = 2 << 30;

/// Parsed command line.
const Options = struct {
    /// The path being repaired: the first one named until `repairPath` reaches the next.
    path: []const u8 = "",
    /// Every path named on the command line, in the order written; each is repaired as if it were named alone.
    paths: []const []const u8 = &.{},
    check: bool = false,
    json: bool = false,
    cache: Caching = .{},
    /// `--report`: a last line that counts the checks the run started, by kind.
    report: bool = false,
    /// `--imports`: a module or test file named alone is repaired together with the modules it imports.
    imports: bool = false,
    /// `--warnings`: a file named alone is repaired for its warnings as well as its errors. A directory always is.
    warnings: bool = false,
    /// Checks one round runs at once.
    workers: usize = 1,
};

/// The cache switches `fix` passes on to every check it runs.
const Caching = struct { directory: ?[]const u8 = null, off: bool = false };

const fix_plan = @import("fix_plan.zig");
const Edit = fix_plan.Edit;
const Fix = fix_plan.Fix;
const Planned = fix_plan.Planned;

/// What `fix` did to one file: how many edits, and which codes they repaired.
const Tally = struct { edits: usize = 0, codes: std.ArrayList([]const u8) = .empty };

/// Everything one invocation shares across its entries and rounds.
const Session = struct {
    allocator: std.mem.Allocator,
    /// The process allocator, which backs the scratch arenas of one-off graph loads.
    backing: std.mem.Allocator,
    io: std.Io,
    compiler: []const u8,
    cwd: []const u8,
    options: Options,
    report: Report = .{},
    /// The snapshot of a `selka packages fix` run (`runStaged`); null for every other run.
    staged: ?Staged = null,
};

/// A run of `fix` over the snapshot `selka packages fix` staged (`packages_command.zig`): the application's files and the locked
/// packages' in one private directory. `fix` repairs the staged application files and the command copies back the ones it changed.
pub const Staged = struct {
    /// The staging directory, by its real path, and the application root it mirrors: a staged path is shown as the user's file.
    directory: []const u8,
    app_root: []const u8,
    /// Every staged file of a locked package, by real path, to the package's namespace: a fix that edits one is set aside whole.
    packages: *const std.StringHashMapUnmanaged([]const u8),
    /// The namespaces, comma-separated, for the checks `fix` runs (`warning_display.packages_option`).
    namespaces: []const u8,
    /// The entry and the lock as the user gave them, for the commands the closing lines advise.
    entry: []const u8,
    lock: []const u8,
};

/// What the invocation has done and said so far.
const Report = struct {
    /// Edits applied (or, under `--check`, found) per absolute file path.
    changes: std.array_hash_map.String(Tally) = .empty,
    /// Check rounds that found at least one fix.
    rounds: usize = 0,
    /// Remaining diagnostics already printed, so a module several entries
    /// import reports its unfixable errors once.
    printed: std.StringHashMapUnmanaged(void) = .empty,
    tuple_withheld: bool = false,
    /// Fixes the last check published that edit a file other than the one named, and how many files hold them.
    left: fix_plan.Elsewhere = .{},
    /// The checks the run started, for `--report`.
    checks: fix_directory.Checks = .{},
    /// The one module or test file named, whose own repairs are the only ones applied (see `ownRepairs`).
    only: ?[]const u8 = null,
    /// The one file named on the command line, which is repaired even when its first line says it is generated.
    named: ?[]const u8 = null,
    /// Warnings with a repair that the last check published and this run left alone (`leaveWarnings`), for the closing line.
    left_warnings: usize = 0,
    /// Whether a file's first line says a tool generated it, by absolute path, read once.
    generated: std.StringHashMapUnmanaged(bool) = .empty,
    /// The fixes set aside for editing a generated file, once each (`path:start:end:code`), and the files they are in.
    set_aside: std.StringHashMapUnmanaged(void) = .empty,
    set_aside_files: std.StringHashMapUnmanaged(void) = .empty,
    /// The fixes a `selka packages fix` run left for editing a package's file, once each (`path:start:end:code`), to the package.
    in_packages: std.array_hash_map.String([]const u8) = .empty,
    /// The closing lines each path asked for (`closing`), in the order the paths were repaired.
    closing: std.ArrayList(u8) = .empty,
    /// Under `--check`, the edits already counted (`path:start:end:code:text`): two paths that reach one module find its fixes once.
    previewed: std.StringHashMapUnmanaged(void) = .empty,
};

/// The `diagnostic-v1` fields a round reads; everything else is ignored.
const Wire = struct {
    version: []const u8 = "",
    kind: []const u8 = "",
    diagnostic: ?struct {
        code: []const u8 = "",
        message: []const u8 = "",
        severity: []const u8 = "",
        fix: ?struct { edits: []const WireEdit = &.{} } = null,
    } = null,
};
const WireEdit = struct { path: []const u8 = "", bytes: struct { start: usize = 0, end: usize = 0 } = .{}, text: []const u8 = "" };

/// Run `selka fix` with the arguments after the command name and return its
/// exit status: 0 when nothing is left to fix and every entry of every path checks, 1 when
/// errors remain or `--check` found something to change, 2 on a usage or host
/// failure, which is named on stderr. Several paths are repaired one after another, each as if
/// it were named alone, and make one report and one closing line.
/// `staged` describes the snapshot of a `selka packages fix` run, whose path is the staged entry or directory; null otherwise.
pub fn run(process: std.process.Init, args: []const []const u8, staged: ?Staged) u8 {
    return runCommand(process, args, staged) catch |err| {
        var buffer: [192]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "selka fix: {s}\n", .{@errorName(err)}) catch "selka fix: host failure\n";
        std.Io.File.stderr().writeStreamingAll(process.io, message) catch return 2;
        return 2;
    };
}

fn runCommand(process: std.process.Init, args: []const []const u8, staged: ?Staged) !u8 {
    const allocator = process.arena.allocator();
    const options = parse(allocator, args) catch |err| switch (err) {
        error.Usage => {
            try std.Io.File.stderr().writeStreamingAll(process.io, usage);
            return 2;
        },
        error.OutOfMemory => return err,
    };
    const compiler = std.process.executablePathAlloc(process.io, allocator) catch {
        try std.Io.File.stderr().writeStreamingAll(process.io, "selka fix: cannot locate this executable\n");
        return 2;
    };
    const cwd = try std.Io.Dir.cwd().realPathFileAlloc(process.io, ".", allocator);
    var session: Session = .{ .allocator = allocator, .backing = process.gpa, .io = process.io, .compiler = compiler, .cwd = cwd, .options = options, .staged = staged };
    // Every path is found and listed before the first is repaired: a path that cannot be used ends the run with nothing written.
    var jobs: std.ArrayList(Job) = .empty;
    for (options.paths) |path| switch (try prepare(process, &session, path)) {
        .refused => |status| return status,
        .ready => |job| if (!prepared(jobs.items, job.target)) try jobs.append(allocator, job),
    };
    // Each path's status and the rounds the run had taken when the path ended.
    const outcomes = try allocator.alloc(u8, jobs.items.len);
    const ends = try allocator.alloc(usize, jobs.items.len);
    @memset(outcomes, 0);
    for (jobs.items, outcomes, ends, 0..) |job, *outcome, *end, index| {
        outcome.* = try repairPath(&session, job);
        end.* = session.report.rounds;
        if (outcome.* != 2) continue;
        try stoppedAt(&session, jobs.items[index..]);
        break;
    }
    try confirm(&session, jobs.items, outcomes, ends);
    try summarize(&session);
    return std.mem.max(u8, outcomes);
}

/// A path that ended with errors left, before a later path wrote files, may be clean now (the later path repaired the module the
/// errors were in): its entries are checked once more, so the status says how the files stand and not how they stood. What it
/// prints is only a diagnostic not printed before. Under `--check` nothing is written, so no status is stale.
fn confirm(session: *Session, jobs: []const Job, outcomes: []u8, ends: []const usize) !void {
    for (jobs, outcomes, ends) |job, *outcome, end| {
        if (!fix_directory.mayBeStale(outcome.*, end, session.report.rounds, session.options.check)) continue;
        session.options.workers = job.width;
        outcome.* = try finalEntries(session, job.entries);
    }
}

/// One path of the command line, found and listed: the real path it names, its entries and the checks one round of them may run at once.
const Job = struct { path: []const u8, target: []const u8, entries: []const []const u8, width: usize };

/// What preparing a path found: the job to run, or the status the command ends with because the path cannot be used.
const Prepared = union(enum) { ready: Job, refused: u8 };

/// Find `path` and list its entries, as the command always has for the one path it was given; a path that does not exist, is not
/// a `.selka` file or a directory, or a width `SELKA_JOBS` does not allow is named on stderr and ends the run.
fn prepare(process: std.process.Init, session: *Session, path: []const u8) !Prepared {
    const allocator = session.allocator;
    if (try input_probe.check(allocator, process.io, "fix", path, true)) |refusal| {
        try std.Io.File.stderr().writeStreamingAll(process.io, refusal);
        return .{ .refused = input_probe.refused_status };
    }
    const target = try std.Io.Dir.cwd().realPathFileAlloc(process.io, path, allocator);
    const listed = try entriesOf(process, target) orelse {
        const message = try std.fmt.allocPrint(allocator, "selka fix: {s} is neither a .selka entry nor a directory\n", .{path});
        try std.Io.File.stderr().writeStreamingAll(process.io, message);
        return .{ .refused = 2 };
    };
    const entries = try ownEntries(session, listed);
    const width = workers(process, entries.len) catch {
        try std.Io.File.stderr().writeStreamingAll(process.io, "selka fix: " ++ budget.jobs_variable ++ " must be a positive whole number\n");
        return .{ .refused = 2 };
    };
    return .{ .ready = .{ .path = path, .target = target, .entries = entries, .width = width } };
}

/// Whether a path that names `target` was already prepared: naming one file or directory twice repairs it once.
fn prepared(jobs: []const Job, target: []const u8) bool {
    for (jobs) |job| if (std.mem.eql(u8, job.target, target)) return true;
    return false;
}

/// Repair one path as `selka fix PATH` alone would, on the files as the paths before it left them: the state that belongs to
/// one path (the file it names, the repairs it leaves, the width of its rounds) is set here, and what the whole run reports
/// (the edits per file, the rounds, the diagnostics already printed) carries over from the paths before. Answers the path's status.
fn repairPath(session: *Session, job: Job) !u8 {
    session.options.path = job.path;
    session.options.workers = job.width;
    session.report.only = try onlyFile(session, job.entries, job.target);
    session.report.named = if (job.entries.len == 1 and std.mem.eql(u8, job.entries[0], job.target)) job.target else null;
    session.report.left = .{};
    session.report.left_warnings = 0;
    if (session.report.named) |file| try repairedByName(session, file);
    if (session.staged) |snapshot| session.options.path = snapshot.entry;
    // A staged directory holds the packages' files too, which its whole-project check would read as the application's.
    const project = if (session.staged == null) try projectOf(session, job.entries, job.target) else null;
    const status = try fixEntries(session, job.entries, project);
    try closing(session);
    return status;
}

/// A file named on the command line is repaired even when it is generated. An earlier path that reached it set its fixes aside
/// as a generated file's; they are no longer left alone, so they leave the count the closing line gives.
fn repairedByName(session: *Session, file: []const u8) !void {
    var doomed: std.ArrayList([]const u8) = .empty;
    var keys = session.report.set_aside.keyIterator();
    while (keys.next()) |key| {
        if (key.len > file.len and key.*[file.len] == ':' and std.mem.startsWith(u8, key.*, file)) try doomed.append(session.allocator, key.*);
    }
    for (doomed.items) |key| _ = session.report.set_aside.remove(key);
    _ = session.report.set_aside_files.remove(file);
}

/// A path ended in a host failure: the paths after it are not repaired, and the line says which.
fn stoppedAt(session: *Session, jobs: []const Job) !void {
    if (jobs.len < 2) return;
    var line: std.ArrayList(u8) = .empty;
    try line.print(session.allocator, "selka fix: stopped at {s}; not repaired:", .{jobs[0].path});
    for (jobs[1..]) |job| try line.print(session.allocator, " {s}", .{job.path});
    try line.append(session.allocator, '\n');
    try std.Io.File.stderr().writeStreamingAll(session.io, line.items);
}

/// Parse the switches and the entry or directory paths, in the order written.
fn parse(allocator: std.mem.Allocator, args: []const []const u8) error{ Usage, OutOfMemory }!Options {
    var options: Options = .{};
    var paths: std.ArrayList([]const u8) = .empty;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--check")) {
            if (options.check) return error.Usage;
            options.check = true;
        } else if (std.mem.eql(u8, arg, "--imports")) {
            if (options.imports) return error.Usage;
            options.imports = true;
        } else if (std.mem.eql(u8, arg, "--warnings")) {
            if (options.warnings) return error.Usage;
            options.warnings = true;
        } else if (std.mem.eql(u8, arg, "--no-cache")) {
            if (options.cache.off) return error.Usage;
            options.cache.off = true;
        } else if (std.mem.eql(u8, arg, "--report")) {
            if (options.report) return error.Usage;
            options.report = true;
        } else if (std.mem.startsWith(u8, arg, "--diagnostics=")) {
            const value = arg["--diagnostics=".len..];
            if (std.mem.eql(u8, value, "json")) options.json = true else if (!std.mem.eql(u8, value, "text")) return error.Usage;
        } else if (std.mem.startsWith(u8, arg, cache_flag)) {
            if (options.cache.directory != null or arg.len == cache_flag.len) return error.Usage;
            options.cache.directory = arg[cache_flag.len..];
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return error.Usage;
        } else try paths.append(allocator, arg);
    }
    if (paths.items.len == 0) return error.Usage;
    options.paths = paths.items;
    options.path = paths.items[0];
    return options;
}

/// The entries one invocation fixes, in order: the one `.selka` file named, or
/// every `.selka` file under the directory named — programs (files that declare
/// `main`) first, then `*_test.selka` files, then the remaining modules, each
/// group in path order. A module a program imports is skipped once that
/// program has been checked in the same round, so each round observes every
/// independent entry before it writes any edits. Null when the path is neither.
fn entriesOf(process: std.process.Init, target: []const u8) !?[]const []const u8 {
    const allocator = process.arena.allocator();
    const stat = try std.Io.Dir.cwd().statFile(process.io, target, .{});
    if (stat.kind != .directory) {
        if (!product.isSource(target)) return null;
        const single = try allocator.alloc([]const u8, 1);
        single[0] = target;
        return single;
    }
    var directory = try std.Io.Dir.cwd().openDir(process.io, target, .{ .iterate = true, .follow_symlinks = false });
    defer directory.close(process.io);
    var walker = try directory.walk(allocator);
    defer walker.deinit();
    var groups: [3]std.ArrayList([]const u8) = @splat(.empty);
    while (try walker.next(process.io)) |item| {
        if (item.kind == .directory and item.basename.len != 0 and (item.basename[0] == '.' or std.mem.eql(u8, item.basename, "zig-out"))) {
            walker.leave(process.io);
            continue;
        }
        if (item.kind != .file or !product.isSource(item.basename)) continue;
        const path = try std.fs.path.join(allocator, &.{ target, item.path });
        const bytes = std.Io.Dir.cwd().readFileAlloc(process.io, path, allocator, .limited(file_limit)) catch "";
        const group: usize = if (project_config.declaresMain(bytes)) 0 else if (product.isTestSource(item.basename)) 1 else 2;
        try groups[group].append(allocator, path);
    }
    var ordered: std.ArrayList([]const u8) = .empty;
    for (&groups) |*group| {
        std.mem.sort([]const u8, group.items, {}, lessThan);
        try ordered.appendSlice(allocator, group.items);
    }
    return ordered.items;
}

/// Why the entries of a path could not be listed.
pub const EntriesError = error{ OutOfMemory, ReadFailed };

/// The entries `selka fix` visits for `target` (an absolute path), in its order: the one `.selka` file named, or every `.selka`
/// file under the directory named, programs first, then tests, then the other modules. `selka rename` visits the same.
pub fn projectEntries(process: std.process.Init, target: []const u8) EntriesError!?[]const []const u8 {
    return entriesOf(process, target) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.ReadFailed,
    };
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// The entries that are the user's own: all of them, except in a staged directory, whose packages' files are not entries.
fn ownEntries(session: *Session, entries: []const []const u8) ![]const []const u8 {
    const staged = session.staged orelse return entries;
    var own: std.ArrayList([]const u8) = .empty;
    for (entries) |entry| if (!staged.packages.contains(entry)) try own.append(session.allocator, entry);
    return own.items;
}

/// The file whose own repairs are the only ones to apply: the one `.selka` file named when it is a module or a test and `--imports`
/// is not given. A program (a file that declares `main`) is the entry of its project, so naming it repairs the project it
/// builds, as it always has; a directory repairs every file under it. Null for those, and for a file that cannot be read.
fn onlyFile(session: *Session, entries: []const []const u8, target: []const u8) !?[]const u8 {
    if (session.options.imports or entries.len != 1 or !std.mem.eql(u8, entries[0], target)) return null;
    const bytes = std.Io.Dir.cwd().readFileAlloc(session.io, target, session.allocator, .limited(file_limit)) catch return null;
    return if (project_config.declaresMain(bytes)) null else target;
}

/// The fixes that edit only `file`. A fix with an edit in another file is not applied: it would change a module its owner did not
/// ask to have repaired, or half of a repair that renames across files (`fix_plan.onlyIn`). They are counted for the closing
/// line (`summarize`), and `--imports` applies them.
fn ownRepairs(session: *Session, file: []const u8, fixes: []const Fix) ![]const Fix {
    const split = try fix_plan.onlyIn(session.allocator, file, fixes);
    session.report.left = split.elsewhere;
    return split.own;
}

/// Collect every entry's repairs before writing a round, so changes to shared
/// declarations cannot hide the old metadata needed to repair another caller.
/// A directory that is one project (`project`) is checked whole, once a round,
/// until that check stops answering for the entries (`projectRound`); from then
/// on, and for every other run, each entry is checked on its own.
fn fixEntries(session: *Session, entries: []const []const u8, project: ?Project) !u8 {
    const memo = try session.allocator.alloc(?Memo, entries.len);
    @memset(memo, null);
    var whole = project;
    var round: usize = 0;
    var idle: usize = 0;
    while (round < max_rounds) {
        if (whole) |directory| {
            switch (try projectRound(session, entries, directory)) {
                .settled => return finalProject(session, entries, directory),
                .previewed => return 1,
                .applied => {
                    round += 1;
                    continue;
                },
                .entries => whole = null,
            }
        }
        const reused = for (memo) |kept| {
            if (kept != null) break true;
        } else false;
        const fixes = try collectEntries(session, entries, memo) orelse return 2;
        const plan = try fix_plan.select(session.allocator, fixes);
        try withhold(session, plan.withheld);
        if (plan.chosen.len == 0) {
            if (!reused) break;
            // Nothing left by the checks this round reused: confirm it with
            // every entry checked afresh before stopping.
            @memset(memo, null);
            continue;
        }
        round += 1;
        if (session.options.check) {
            session.report.rounds += 1;
            try record(session, plan.chosen, null);
            return 1;
        }
        const written = try apply(session, plan.chosen);
        try invalidate(session, memo, written);
        if (written.len == 0) {
            // A round can change nothing when it read a reused check that no longer
            // fits; two in a row is a repair that cannot change its file.
            idle += 1;
            if (idle == 2) return stalled(session, plan.chosen);
            continue;
        }
        idle = 0;
        session.report.rounds += 1;
        try record(session, plan.chosen, written);
    } else {
        const message = try std.fmt.allocPrint(session.allocator, "selka fix: {s}: fixes did not settle after {d} rounds\n", .{ session.options.path, max_rounds });
        try std.Io.File.stderr().writeStreamingAll(session.io, message);
        return 1;
    }
    return finalEntries(session, entries);
}

/// A directory `fix` checks as one project: `selka check DIR` on `path`, whose diagnostics name files relative to `root`.
const Project = struct { path: []const u8, root: []const u8 };

/// The directory `target` as one project, when its whole-project check answers for its entries (`fix_directory.eligible`):
/// it holds more than one entry, each entry is a module of the project `selka check DIR` loads and resolves its imports
/// beneath the same root, and no source there holds a docstring example. Null otherwise, and for a file named alone.
fn projectOf(session: *Session, entries: []const []const u8, target: []const u8) !?Project {
    if (session.report.only != null or entries.len < 2) return null;
    const stat = std.Io.Dir.cwd().statFile(session.io, target, .{}) catch return null;
    if (stat.kind != .directory) return null;
    const allocator = session.allocator;
    const plan = language.check_directory.plan(allocator, session.io, target) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    const configured = project_config.discoverDirectory(allocator, session.io, target) catch return null;
    const root = if (configured) |path| std.fs.path.dirname(path) orelse target else target;
    var same_root = true;
    for (entries) |entry| {
        const location = project_config.testEntryLocation(allocator, session.io, entry) catch return null;
        const entry_root = if (location) |found| found.root else std.fs.path.dirname(entry) orelse return null;
        const entry_configured = (project_config.discover(allocator, session.io, entry) catch return null) != null;
        if (!fix_directory.sharesRoot(entry_root, root, configured == null and !entry_configured)) same_root = false;
    }
    const scan = fix_directory.scanRoot(allocator, session.io, root) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    const facts: fix_directory.Facts = .{ .entries = entries.len, .modules = plan.module_count, .skipped = plan.skipped.len, .same_root = same_root, .scan = scan };
    return if (fix_directory.eligible(facts)) .{ .path = target, .root = root } else null;
}

/// What one round that checked the directory whole did.
const ProjectRound = enum {
    /// The check is clean and offered nothing: the run is settled.
    settled,
    /// It found fixes and applied them.
    applied,
    /// `--check` found fixes, counted and wrote nothing.
    previewed,
    /// The check no longer answers for the entries: it failed as a host, offered a repair that waits on per-entry facts
    /// (a tuple or domain migration) or depends on the callers (`fix_directory.callerDependent`), stopped at errors with nothing to
    /// apply, or is not clean under `--check`. This round and every later one check the entries.
    entries,
};

/// Check the directory as one project and apply what it offers, as a round of entry checks would: the same filters
/// (`blockedRename`, `leaveGenerated`), the same overlap rule and the same records. A project check that stops at an
/// error offers the repairs of the stage it reached in every module, where an entry clear of that error would reach
/// further; its repairs are applied and the next round checks again, so such a run can take more rounds to the same
/// tree. `--check` reports one round, so it checks the entries whenever the project check is not clean.
fn projectRound(session: *Session, entries: []const []const u8, project: Project) !ProjectRound {
    const result = try runCheck(session, project.path, true, .directory);
    const status = reach.exitCode(result.term);
    // `--check` answers for the first round alone, which is the entries' round exactly when the project check is clean.
    if (status > 1 or (session.options.check and status != 0)) return .entries;
    const collected = try collect(session, project.root, result.stderr);
    var fixes: std.ArrayList(Fix) = .empty;
    var unparsed: ?[]const fix_plan.Unparsed = null;
    for (collected.fixes) |fix| {
        if (std.mem.eql(u8, fix.code, language.tuple_migration.removed_code) or
            std.mem.eql(u8, fix.code, language.domain_migration.removed_code) or
            fix_directory.callerDependent(fix.code)) return .entries;
        // Every entry is a file of the directory, so the files that do not parse are found among them.
        if (try blockedRename(session, entries, fix, &unparsed)) continue;
        try fixes.append(session.allocator, fix);
    }
    const plan = try fix_plan.select(session.allocator, try leaveGenerated(session, try leavePackages(session, fixes.items)));
    try withhold(session, plan.withheld);
    if (plan.chosen.len == 0) return if (status == 0) .settled else .entries;
    if (session.options.check) {
        session.report.rounds += 1;
        try record(session, plan.chosen, null);
        return .previewed;
    }
    const written = try apply(session, plan.chosen);
    // A project round that changed no file hands on to the entries' rounds, which stop such a repair.
    if (written.len == 0) return .entries;
    session.report.rounds += 1;
    try record(session, plan.chosen, written);
    return .applied;
}

/// The final check of a directory checked as one project: its diagnostics in the format asked for, each printed once.
/// When it finds an error, every entry is checked on its own instead (`finalEntries`), so what is left is reported
/// entry by entry as before, an entry clear of the error included.
fn finalProject(session: *Session, entries: []const []const u8, project: Project) !u8 {
    const result = try runCheck(session, project.path, session.options.json, .directory);
    if (reach.exitCode(result.term) != 0) return finalEntries(session, entries);
    try forward(session, project.root, result.stderr);
    return 0;
}

/// Check every independent entry against the sources before this round's edits.
/// A host failure aborts the round before any file is written. The checks run
/// across the session's workers; their outcomes are read here in entry order,
/// so a round reports, refuses and plans exactly as a serial one does.
fn collectEntries(session: *Session, entries: []const []const u8, memo: []?Memo) !?[]const Fix {
    const round = try roundOutcomes(session, entries, memo);
    var covered: std.StringHashMapUnmanaged(void) = .empty;
    var batches: std.ArrayList(Collected) = .empty;
    var scopes: std.ArrayList(tuple_scope.Entry) = .empty;
    var deferred_domain = false;
    var incomplete: std.ArrayList([]const u8) = .empty;
    for (entries, round, 0..) |entry, outcome, index| {
        if (covered.contains(entry)) continue;
        if (reach.exitCode(outcome.result.term) > 1) {
            try std.Io.File.stderr().writeStreamingAll(session.io, outcome.result.stderr);
            return null;
        }
        const collected = outcome.collected;
        deferred_domain = deferred_domain or collected.deferred_domain;
        const scope = outcome.scope;
        memo[index] = try remember(session, outcome);
        try fix_coverage.add(session.allocator, &covered, entries, scope.paths);
        if (!scope.complete) try incomplete.append(session.allocator, entry);
        try batches.append(session.allocator, collected);
        try scopes.append(session.allocator, scope);
    }
    const groups = try tuple_scope.Groups.init(session.allocator, scopes.items);
    var fixes: std.ArrayList(Fix) = .empty;
    var unparsed: ?[]const fix_plan.Unparsed = null;
    for (batches.items, 0..) |batch, index| for (batch.fixes) |fix| {
        if (try blockedRename(session, incomplete.items, fix, &unparsed)) continue;
        if (deferred_domain and std.mem.eql(u8, fix.code, @import("selka").domain_migration.removed_code)) continue;
        if (std.mem.eql(u8, fix.code, @import("selka").tuple_migration.removed_code)) if (groups.reason(index)) |reason| {
            try withholdTuple(session, fix, reason);
            continue;
        };
        try fixes.append(session.allocator, fix);
    };
    const own = try leavePackages(session, fixes.items);
    const wanted = if (session.report.named != null and !session.options.warnings) try leaveWarnings(session, own) else own;
    const repairable = try leaveGenerated(session, wanted);
    if (session.report.only) |file| {
        const own_file = try ownRepairs(session, file, repairable);
        return own_file;
    }
    return repairable;
}

/// The fixes of errors, when the run names one file and not `--warnings`: a warning's repair rewrites code the agent is editing
/// (`match` into `is Some(x)`, `copy(a)` into `take(mut a)`), so a file run applies the repairs of errors only and a directory, or
/// `--warnings`, the warnings' as well (SP2-F-10, SP3-F-12). The warnings left are counted as `--warnings` would apply them: the
/// ones in the file itself when it is a module or a test, and none in a generated file other than the one named, for `summarize`.
fn leaveWarnings(session: *Session, fixes: []const Fix) ![]const Fix {
    var errors: std.ArrayList(Fix) = .empty;
    var warnings: std.ArrayList(Fix) = .empty;
    for (fixes) |fix| if (fix.warning) try warnings.append(session.allocator, fix) else try errors.append(session.allocator, fix);
    const applicable = if (session.report.only) |file| (try fix_plan.onlyIn(session.allocator, file, warnings.items)).own else warnings.items;
    var distinct: std.StringHashMapUnmanaged(void) = .empty;
    for (applicable) |fix| {
        if (try inGenerated(session, fix)) continue;
        const first = fix.edits[0];
        try distinct.put(session.allocator, try std.fmt.allocPrint(session.allocator, "{s}:{d}:{d}:{s}", .{ first.path, first.start, first.end, fix.code }), {});
    }
    session.report.left_warnings = distinct.count();
    return errors.items;
}

/// The fixes that edit no file of a locked package, in a run of `selka packages fix`; all of them in any other run. A package's
/// files are never written: a fix with an edit in one is set aside whole, and counted for the closing line (`summarize`) when the
/// run would have applied it (an error's, or a warning's when the run repairs warnings, in a run that does not name a module alone).
fn leavePackages(session: *Session, fixes: []const Fix) ![]const Fix {
    const staged = session.staged orelse return fixes;
    var kept: std.ArrayList(Fix) = .empty;
    for (fixes) |fix| {
        const package = for (fix.edits) |edit| {
            if (staged.packages.get(edit.path)) |name| break name;
        } else {
            try kept.append(session.allocator, fix);
            continue;
        };
        const left_anyway = (fix.warning and session.report.named != null and !session.options.warnings) or session.report.only != null;
        if (left_anyway) continue;
        const first = fix.edits[0];
        const key = try std.fmt.allocPrint(session.allocator, "{s}:{d}:{d}:{s}", .{ first.path, first.start, first.end, fix.code });
        try session.report.in_packages.put(session.allocator, key, package);
    }
    return kept.items;
}

/// Whether `fix` edits a generated file other than the one named on the command line, which `leaveGenerated` sets aside.
fn inGenerated(session: *Session, fix: Fix) !bool {
    for (fix.edits) |edit| {
        if (session.report.named) |named| if (std.mem.eql(u8, edit.path, named)) continue;
        if (try isGenerated(session, edit.path)) return true;
    }
    return false;
}

/// The fixes that edit no generated file. A file whose first line says a tool wrote it (`# generated by …`, the rule lint and
/// the change review share) is written again by that tool, and its check compares bytes, so a repair there is lost or breaks
/// the check (the site's `viewgen --check`): the fix is set aside whole and counted for the closing line (`summarize`). The
/// one file named on the command line is repaired all the same.
fn leaveGenerated(session: *Session, fixes: []const Fix) ![]const Fix {
    var skipped: std.StringHashMapUnmanaged(void) = .empty;
    for (fixes) |fix| for (fix.edits) |edit| {
        if (session.report.named) |named| if (std.mem.eql(u8, edit.path, named)) continue;
        if (try isGenerated(session, edit.path)) try skipped.put(session.allocator, edit.path, {});
    };
    if (skipped.count() == 0) return fixes;
    const split = try fix_plan.withoutFiles(session.allocator, fixes, &skipped);
    for (split.set_aside) |fix| {
        const first = fix.edits[0];
        const key = try std.fmt.allocPrint(session.allocator, "{s}:{d}:{d}:{s}", .{ first.path, first.start, first.end, fix.code });
        try session.report.set_aside.put(session.allocator, key, {});
        for (fix.edits) |edit| if (skipped.contains(edit.path)) try session.report.set_aside_files.put(session.allocator, edit.path, {});
    }
    return split.kept;
}

/// Whether the file at `path` opens with the generated marker; a file that cannot be read is not generated.
fn isGenerated(session: *Session, path: []const u8) !bool {
    const known = try session.report.generated.getOrPut(session.allocator, path);
    if (!known.found_existing) {
        const bytes = std.Io.Dir.cwd().readFileAlloc(session.io, path, session.allocator, .limited(file_limit)) catch "";
        known.value_ptr.* = @import("selka").generated_marker.isGenerated(bytes);
    }
    return known.value_ptr.*;
}

/// Whether `fix` is a rename that waits, because a file of the directory that does not parse imports a module the rename edits:
/// the file's qualified calls cannot be renamed with the declaration, and a rename that left them behind would turn a parse
/// error into an unknown name once the file is repaired. The wait is named on stderr, once, with the file and the module, and
/// the diagnostic stays; the next `selka fix`, after the file parses, renames everything together. `unparsed` is read on the
/// first rename of a round, from the entries whose graph did not load.
fn blockedRename(session: *Session, incomplete: []const []const u8, fix: Fix, unparsed: *?[]const fix_plan.Unparsed) !bool {
    if (!fix_plan.isRename(fix.code)) return false;
    if (unparsed.* == null) {
        var found: std.ArrayList(fix_plan.Unparsed) = .empty;
        for (incomplete) |entry| {
            const absolute = try std.fs.path.resolve(session.allocator, &.{ session.cwd, entry });
            const imports = reach.unparsedImports(session.allocator, session.io, absolute) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => continue,
            } orelse continue;
            try found.append(session.allocator, .{ .path = absolute, .imports = imports });
        }
        unparsed.* = found.items;
    }
    const block = fix_plan.blockedBy(fix, unparsed.*.?) orelse return false;
    const shown = try display(session, fix.edits[0].path);
    const broken = try display(session, block.file.path);
    const reason = "{s} does not parse and imports `{s}`, so its qualified uses would be left behind; repair {s}, then run `selka fix` again\n";
    const message = try std.fmt.allocPrint(session.allocator, "selka fix: {s}: withheld {s} repairs: " ++ reason, .{ shown, fix.code, broken, block.module, broken });
    const seen = try session.report.printed.getOrPut(session.allocator, message);
    if (!seen.found_existing) try std.Io.File.stderr().writeStreamingAll(session.io, message);
    return true;
}

/// One entry's check: its output and, for a round's check, the fixes it
/// published and the source graph it read. `examples` is the final pass's
/// docstring-example check, run only for an entry that checked clean.
const Outcome = struct {
    result: std.process.RunResult,
    examples: ?std.process.RunResult = null,
    collected: Collected = .{ .fixes = &.{}, .deferred_domain = false, .deferred_tuple = false },
    scope: tuple_scope.Entry = .{ .paths = &.{}, .complete = false, .deferred = false },
};

/// A round's outcome that later rounds reuse while it stays current. `inputs`
/// are the files the entry's graph read and the files its fixes edit; a round
/// that writes any of them drops the memo, and the entry is checked again.
const Memo = struct { outcome: Outcome, inputs: []const []const u8 };

/// Every entry's outcome for this round, in entry order: a current memo is
/// reused, and every other entry is checked across the session's workers.
fn roundOutcomes(session: *Session, entries: []const []const u8, memo: []const ?Memo) ![]const Outcome {
    const outcomes = try session.allocator.alloc(Outcome, entries.len);
    var pending: std.ArrayList(usize) = .empty;
    for (memo, outcomes, 0..) |kept, *outcome, index| {
        if (kept) |current| outcome.* = current.outcome else try pending.append(session.allocator, index);
    }
    try runPool(session, entries, pending.items, outcomes, false);
    return outcomes;
}

/// The memo for one outcome, or null when its graph is not complete
/// (`fix_memo.inputs`), so that entry is checked every round.
fn remember(session: *Session, outcome: Outcome) !?Memo {
    var edited: std.ArrayList([]const u8) = .empty;
    for (outcome.collected.fixes) |fix| for (fix.edits) |edit| try edited.append(session.allocator, edit.path);
    const inputs = try fix_memo.inputs(session.allocator, outcome.scope.paths, outcome.scope.complete, edited.items) orelse return null;
    return .{ .outcome = outcome, .inputs = inputs };
}

/// Drop every memo that reads or would edit a file this round wrote.
fn invalidate(session: *Session, memo: []?Memo, written: []const []const u8) !void {
    const touched = try fix_memo.touched(session.allocator, session.io, written);
    for (memo) |*slot| {
        const kept = slot.* orelse continue;
        if (fix_memo.stale(kept.inputs, &touched)) slot.* = null;
    }
}

/// Workers a round's entry checks share: `SELKA_JOBS` when it is set, otherwise the
/// machine's cores capped by how many checks of `check_reservation` its free memory
/// holds; never more than the entries there are. A round that checks the directory
/// as one project runs one check and no pool.
fn workers(process: std.process.Init, entries: usize) budget.Error!usize {
    const text = process.environ_map.get(budget.jobs_variable) orelse "";
    const requested: ?usize = if (text.len == 0) null else try budget.jobs(text);
    return budget.workers(.{
        .jobs = requested,
        .programs = entries,
        .cores = std.Thread.getCpuCount() catch 1,
        .free = budget.available(process.io),
        .ceiling = check_reservation,
    });
}

/// The shared state of one pool run. Each worker writes only the outcome and
/// the failure of the entry it claimed, so the cursor is all they contend over.
const Pool = struct {
    session: *Session,
    entries: []const []const u8,
    pending: []const usize,
    outcomes: []Outcome,
    failures: []?anyerror,
    final: bool,
    next: std.atomic.Value(usize) = .init(0),
};

/// Check the `pending` entries across the session's workers, writing each
/// outcome at its entry's index. The dispatching thread is one of the workers,
/// so a machine that refuses more concurrency still finishes the round. A host
/// failure is returned for the first failing entry in entry order.
fn runPool(session: *Session, entries: []const []const u8, pending: []const usize, outcomes: []Outcome, final: bool) !void {
    const failures = try session.allocator.alloc(?anyerror, entries.len);
    @memset(failures, null);
    var pool: Pool = .{ .session = session, .entries = entries, .pending = pending, .outcomes = outcomes, .failures = failures, .final = final };
    var tasks: std.Io.Group = .init;
    defer tasks.cancel(session.io);
    var spawned: usize = 1;
    while (spawned < @min(session.options.workers, pending.len)) : (spawned += 1) {
        tasks.concurrent(session.io, work, .{&pool}) catch break;
    }
    work(&pool);
    try tasks.await(session.io);
    for (failures) |failure| if (failure) |err| return err;
}

/// Take entries off the shared cursor until it is exhausted.
fn work(pool: *Pool) void {
    while (true) {
        const slot = pool.next.fetchAdd(1, .monotonic);
        if (slot >= pool.pending.len) return;
        const index = pool.pending[slot];
        pool.outcomes[index] = examine(pool.session, pool.entries[index], pool.final) catch |err| {
            pool.failures[index] = err;
            continue;
        };
    }
}

/// Check one entry. A round's check also reads its fixes and loads its source
/// graph; the final pass needs only the output it forwards. An entry that
/// checks clean also has its docstring examples checked (an entry that does not
/// check cannot have its examples compiled). An example's diagnostics add their
/// fixes only: they say nothing about the domain and tuple facts the entry's own
/// check completes. A host failure of the example check stands as the outcome.
fn examine(session: *Session, entry: []const u8, final: bool) !Outcome {
    if (final) {
        const result = try check(session, entry, session.options.json);
        if (reach.exitCode(result.term) != 0) return .{ .result = result };
        return .{ .result = result, .examples = try checkExamples(session, entry, session.options.json) };
    }
    const result = try check(session, entry, true);
    if (reach.exitCode(result.term) > 1) return .{ .result = result };
    const root = try projectRoot(session, entry);
    var collected = try collect(session, root, result.stderr);
    if (reach.exitCode(result.term) == 0) {
        const examples = try checkExamples(session, entry, true);
        if (reach.exitCode(examples.term) > 1) return .{ .result = examples };
        const added = try collect(session, root, examples.stderr);
        collected.fixes = try std.mem.concat(session.allocator, Fix, &.{ collected.fixes, added.fixes });
    }
    return .{ .result = result, .collected = collected, .scope = try tupleScope(session, entry, collected) };
}

/// Retain only paths between checks, releasing loaded sources and syntax after
/// each entry. Every edited declaration must belong to its proved source graph.
fn tupleScope(session: *Session, entry: []const u8, collected: Collected) !tuple_scope.Entry {
    var scratch = std.heap.ArenaAllocator.init(session.backing);
    defer scratch.deinit();
    const reached = reach.tupleScope(scratch.allocator(), session.io, entry) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .paths = &.{}, .complete = false, .deferred = collected.deferred_tuple },
    };
    var complete = reached.complete;
    for (collected.fixes) |fix| {
        if (!std.mem.eql(u8, fix.code, @import("selka").tuple_migration.removed_code)) continue;
        for (fix.edits) |edit| {
            for (reached.paths) |path| {
                if (std.mem.eql(u8, edit.path, path)) break;
            } else complete = false;
        }
    }
    const paths = try session.allocator.alloc([]const u8, reached.paths.len);
    for (reached.paths, paths) |path, *copy| copy.* = try session.allocator.dupe(u8, path);
    return .{ .paths = paths, .complete = complete, .deferred = collected.deferred_tuple };
}

/// Explain a suppressed certain proposal once, preserving the diagnostic and
/// status rather than reporting an unchanged directory as a clean fixed point.
fn withholdTuple(session: *Session, fix: Fix, reason: tuple_scope.Reason) !void {
    session.report.tuple_withheld = true;
    const shown = try display(session, fix.edits[0].path);
    const explanation = switch (reason) {
        .incomplete => "incomplete import or declaration graph",
        .shared => "a shared import or declaration group has unresolved diagnostics",
    };
    const message = try std.fmt.allocPrint(session.allocator, "selka fix: {s}: withheld E_TUPLE_REMOVED repairs: {s}\n", .{ shown, explanation });
    const seen = try session.report.printed.getOrPut(session.allocator, message);
    if (!seen.found_existing) try std.Io.File.stderr().writeStreamingAll(session.io, message);
}

/// Print each remaining diagnostic once after all entries reach a fixed point.
fn finalEntries(session: *Session, entries: []const []const u8) !u8 {
    const outcomes = try session.allocator.alloc(Outcome, entries.len);
    const every = try session.allocator.alloc(usize, entries.len);
    for (every, 0..) |*index, position| index.* = position;
    try runPool(session, entries, every, outcomes, true);
    var covered: std.StringHashMapUnmanaged(void) = .empty;
    var status: u8 = 0;
    for (entries, outcomes) |entry, outcome| {
        if (covered.contains(entry)) continue;
        const final = outcome.result;
        const root = try projectRoot(session, entry);
        try forward(session, root, final.stderr);
        var entry_status = @min(reach.exitCode(final.term), 2);
        if (outcome.examples) |examples| {
            try forward(session, root, examples.stderr);
            entry_status = @min(reach.exitCode(examples.term), 2);
        }
        status = @max(status, entry_status);
        if (status == 2) break;
        // Every entry's own diagnostics are printed; only its imports are covered.
        try coverEntry(session, entries, &covered, entry);
    }
    return status;
}

/// Imported modules are already checked with their entry in the current round.
/// A file that is itself an entry stays uncovered: checking it through an
/// importer attributes its repairs to another file's root, and a repair in the
/// importer's own file is what a directory run must still apply.
fn coverEntry(session: *Session, entries: []const []const u8, covered: *std.StringHashMapUnmanaged(void), entry: []const u8) !void {
    // The graph load parses every module the entry reaches. Its memory is released
    // with this scratch arena, not kept in the session's: a directory run loads one
    // graph per entry, and retaining them all exhausted the compiler's memory cap.
    var scratch = std.heap.ArenaAllocator.init(session.backing);
    defer scratch.deinit();
    const reached = reach.reach(scratch.allocator(), session.io, entry) catch return;
    try fix_coverage.add(session.allocator, covered, entries, reached);
}

/// Print a final check's diagnostics, each one once per invocation, whatever path the check printed for its file
/// (`printedKey`). A diagnostic is a JSON line, or a text line that starts in column one together with the indented lines
/// under it; `root` is the directory the check's paths are relative to.
fn forward(session: *Session, root: []const u8, stderr: []const u8) !void {
    var out: std.ArrayList(u8) = .empty;
    var start: usize = 0;
    while (start < stderr.len) {
        var end = std.mem.indexOfScalarPos(u8, stderr, start, '\n') orelse stderr.len;
        if (!session.options.json) while (end + 1 < stderr.len and (stderr[end + 1] == ' ' or stderr[end + 1] == '\t')) {
            end = std.mem.indexOfScalarPos(u8, stderr, end + 1, '\n') orelse stderr.len;
        };
        const block = stderr[start..@min(end + 1, stderr.len)];
        // The final check's own "check: ok" status line is not something `fix` reports, nor is its closing line, which names
        // the command that is running (with the absolute path `fix` gave the check) beside `fix`'s own last lines.
        if (std.mem.startsWith(u8, block, diagnostic_output.check_passed) or language.warning_display.isFixLine(block)) {
            start = end + 1;
            continue;
        }
        const seen = try session.report.printed.getOrPut(session.allocator, try printedKey(session, root, block));
        if (!seen.found_existing) try out.appendSlice(session.allocator, block);
        start = end + 1;
    }
    try std.Io.File.stderr().writeStreamingAll(session.io, out.items);
}

/// The directory an entry's diagnostic paths are relative to: the enclosing
/// project root for a `*_test.selka` entry, otherwise the entry's own directory.
fn projectRoot(session: *Session, entry: []const u8) ![]const u8 {
    if (project_config.testEntryLocation(session.allocator, session.io, entry) catch null) |location| return location.root;
    return std.fs.path.dirname(entry) orelse session.cwd;
}

/// Run this executable's `check` on one entry and capture its output.
fn check(session: *Session, entry: []const u8, json: bool) !std.process.RunResult {
    return runCheck(session, entry, json, .entry);
}

/// Run this executable's `check --examples` on one entry: the docstring examples
/// of its modules, compiled as `selka test` compiles them and never run.
fn checkExamples(session: *Session, entry: []const u8, json: bool) !std.process.RunResult {
    return runCheck(session, entry, json, .examples);
}

/// Run this executable's `check` on an entry, its docstring examples, or a whole project directory (`kind`), and count it.
fn runCheck(session: *Session, path: []const u8, json: bool, kind: fix_directory.Checks.Kind) !std.process.RunResult {
    session.report.checks.count(kind);
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(session.allocator, &.{ session.compiler, "check", path, if (json) "--diagnostics=json" else "--diagnostics=text" });
    if (kind == .examples) try argv.append(session.allocator, "--examples");
    if (session.staged) |staged| try argv.appendSlice(session.allocator, &.{ language.warning_display.packages_option, staged.namespaces });
    if (session.options.cache.off) try argv.append(session.allocator, "--no-cache");
    if (session.options.cache.directory) |directory| try argv.append(session.allocator, try std.mem.concat(session.allocator, u8, &.{ cache_flag, directory }));
    return std.process.run(session.allocator, session.io, .{ .argv = argv.items });
}

/// Every fix one check published, with each edit's file resolved against the
/// entry's project root. A fix naming an embedded standard module is dropped:
/// `fix` only ever edits the user's own files.
fn collect(session: *Session, root: []const u8, stderr: []const u8) !Collected {
    var fixes: std.ArrayList(Fix) = .empty;
    var deferred_domain = false;
    var deferred_tuple = false;
    var lines = std.mem.splitScalar(u8, stderr, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] != '{') continue;
        const wire = std.json.parseFromSliceLeaky(Wire, session.allocator, line, .{ .ignore_unknown_fields = true }) catch continue;
        if (!std.mem.eql(u8, wire.version, "diagnostic-v1")) continue;
        const diagnostic = wire.diagnostic orelse continue;
        if (std.mem.eql(u8, diagnostic.code, @import("selka").domain_migration.removed_code) and
            std.mem.eql(u8, diagnostic.message, @import("selka").domain_migration.deferred_message)) deferred_domain = true;
        // A parser or early frontend error can prevent the domain pass from
        // publishing its own missing-facts marker for this entry.
        const retirement_error = std.mem.eql(u8, diagnostic.code, @import("selka").domain_migration.removed_code) or
            std.mem.eql(u8, diagnostic.code, @import("selka").tuple_migration.removed_code);
        if (std.mem.eql(u8, diagnostic.severity, "error") and !retirement_error) deferred_domain = true;
        // A tuple diagnostic that publishes no repair is a deferred one, whatever it says: the program did not check, or
        // no repair is certain. What it says is for the reader (FR16), never matched here.
        if (std.mem.eql(u8, diagnostic.code, @import("selka").tuple_migration.removed_code) and diagnostic.fix == null) deferred_tuple = true;
        if (std.mem.eql(u8, diagnostic.severity, "error") and
            !std.mem.eql(u8, diagnostic.code, @import("selka").tuple_migration.removed_code)) deferred_tuple = true;
        const fix = diagnostic.fix orelse continue;
        if (fix.edits.len == 0) continue;
        const edits = try session.allocator.alloc(Edit, fix.edits.len);
        const usable = for (fix.edits, edits) |input, *output| {
            if (std.mem.startsWith(u8, input.path, "@stdlib/") or input.bytes.start > input.bytes.end) break false;
            output.* = .{
                .path = try canonical(session, try std.fs.path.resolve(session.allocator, &.{ root, input.path })),
                .start = input.bytes.start,
                .end = input.bytes.end,
                .text = input.text,
            };
        } else true;
        if (usable) try fixes.append(session.allocator, .{ .code = diagnostic.code, .edits = edits, .warning = std.mem.eql(u8, diagnostic.severity, "warning") });
    }
    return .{ .fixes = fixes.items, .deferred_domain = deferred_domain, .deferred_tuple = deferred_tuple };
}

/// The file `path` names, by its real path: a module a project reaches through a symbolic link (selka-protobuf's `protobuf/`
/// links into `lib/`) is one file whatever path an entry's check printed for it, so its edits are planned, applied and
/// reported once (FR14). A path that does not resolve stays as it is.
fn canonical(session: *Session, path: []const u8) error{OutOfMemory}![]const u8 {
    return std.Io.Dir.cwd().realPathFileAlloc(session.io, path, session.allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => path,
    };
}

/// What a final check's diagnostic block is told apart by: its text with every `.selka` path in it (relative to the entry's
/// project `root`) replaced by the file's real path, so one diagnostic that two entries print under different paths to the
/// same file is printed once.
fn printedKey(session: *Session, root: []const u8, block: []const u8) error{OutOfMemory}![]const u8 {
    var key: std.ArrayList(u8) = .empty;
    var copied: usize = 0;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, block, at, product.source_suffix)) |found| {
        const end = found + product.source_suffix.len;
        at = end;
        if (end >= block.len or (block[end] != ':' and block[end] != '"')) continue;
        var start = found;
        while (start > copied and std.mem.indexOfScalar(u8, " \t\n\"(", block[start - 1]) == null) start -= 1;
        if (start == found) continue;
        try key.appendSlice(session.allocator, block[copied..start]);
        try key.appendSlice(session.allocator, try canonical(session, try std.fs.path.resolve(session.allocator, &.{ root, block[start..end] })));
        copied = end;
    }
    if (copied == 0) return block;
    try key.appendSlice(session.allocator, block[copied..]);
    return key.items;
}

/// Typed domain repairs wait across all entry roots; tuple repairs wait within
/// complete shared-source groups. Independent repairs run first.
const Collected = struct { fixes: []const Fix, deferred_domain: bool, deferred_tuple: bool };

/// Name a withheld fix, whose own edits overlap one another, on stderr once
/// per invocation; it is never applied, so its diagnostic stays for a person.
fn withhold(session: *Session, withheld: []const Fix) !void {
    for (withheld) |fix| {
        const shown = try display(session, fix.edits[0].path);
        const message = try std.fmt.allocPrint(session.allocator, "selka fix: {s}: withheld a {s} fix whose edits overlap one another\n", .{ shown, fix.code });
        const seen = try session.report.printed.getOrPut(session.allocator, message);
        if (!seen.found_existing) try std.Io.File.stderr().writeStreamingAll(session.io, message);
    }
}

/// Stop a run whose last two rounds left every file's bytes as they were, naming
/// the diagnostics whose repairs changed nothing and the file each would edit.
fn stalled(session: *Session, chosen: []const Planned) !u8 {
    var named: std.ArrayList(u8) = .empty;
    for (chosen, 0..) |planned, index| {
        const repeated = for (chosen[0..index]) |earlier| {
            if (std.mem.eql(u8, earlier.code, planned.code) and std.mem.eql(u8, earlier.edit.path, planned.edit.path)) break true;
        } else false;
        if (repeated) continue;
        if (named.items.len > 0) try named.appendSlice(session.allocator, ", ");
        try named.print(session.allocator, "{s} ({s})", .{ planned.code, planned.edit.path });
    }
    const message = try std.fmt.allocPrint(session.allocator, "selka fix: {s}: fixes stopped: two rounds in a row left every file as it was; the repair of {s} did not change anything\n", .{ session.options.path, named.items });
    try std.Io.File.stderr().writeStreamingAll(session.io, message);
    return 1;
}

/// Count the chosen edits against the files they change: of those in `written`
/// alone when it is given (an edit to a file left as it was changed nothing).
fn record(session: *Session, chosen: []const Planned, written: ?[]const []const u8) !void {
    for (chosen) |planned| {
        if (written) |files| for (files) |path| {
            if (std.mem.eql(u8, path, planned.edit.path)) break;
        } else continue;
        if (session.options.check and try previewedBefore(session, planned)) continue;
        const entry = try session.report.changes.getOrPut(session.allocator, planned.edit.path);
        if (!entry.found_existing) entry.value_ptr.* = .{};
        entry.value_ptr.edits += 1;
        for (entry.value_ptr.codes.items) |code| {
            if (std.mem.eql(u8, code, planned.code)) break;
        } else try entry.value_ptr.codes.append(session.allocator, planned.code);
    }
}

/// Whether an earlier path of this `--check` run already found `planned`: nothing is written, so a module that two paths reach
/// shows the same fix to both, and it is counted once.
fn previewedBefore(session: *Session, planned: Planned) !bool {
    const edit = planned.edit;
    const key = try std.fmt.allocPrint(session.allocator, "{s}:{d}:{d}:{s}:{s}", .{ edit.path, edit.start, edit.end, planned.code, edit.text });
    const seen = try session.report.previewed.getOrPut(session.allocator, key);
    return seen.found_existing;
}

/// Apply the chosen edits file by file, from the end of each file backwards so
/// every earlier offset stays valid. A file whose edits no longer fit its
/// current bytes is left alone; the next round's check reports it afresh. So is
/// one whose edits leave its bytes as they were. Answer the files written.
fn apply(session: *Session, chosen: []const Planned) ![]const []const u8 {
    var written: std.ArrayList([]const u8) = .empty;
    var files: std.array_hash_map.String(std.ArrayList(Edit)) = .empty;
    for (chosen) |planned| {
        const entry = try files.getOrPut(session.allocator, planned.edit.path);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        try entry.value_ptr.append(session.allocator, planned.edit);
    }
    for (files.keys(), files.values()) |path, *edits| {
        std.mem.sort(Edit, edits.items, {}, later);
        const bytes = std.Io.Dir.cwd().readFileAlloc(session.io, path, session.allocator, .limited(file_limit)) catch continue;
        const fits = for (edits.items) |edit| {
            if (edit.end > bytes.len) break false;
        } else true;
        if (!fits) continue;
        var text: std.ArrayList(u8) = .empty;
        try text.appendSlice(session.allocator, bytes);
        for (edits.items) |edit| try text.replaceRange(session.allocator, edit.start, edit.end - edit.start, edit.text);
        if (std.mem.eql(u8, text.items, bytes)) continue;
        try std.Io.Dir.cwd().writeFile(session.io, .{ .sub_path = path, .data = text.items });
        try written.append(session.allocator, path);
    }
    return written.items;
}

fn later(_: void, a: Edit, b: Edit) bool {
    return a.start > b.start;
}

/// Print what changed (or, under `--check`, what would change) per file, then
/// one total line, on standard output.
fn summarize(session: *Session) !void {
    var out: std.ArrayList(u8) = .empty;
    const verb = if (session.options.check) "would fix" else "fixed";
    const paths = try session.allocator.dupe([]const u8, session.report.changes.keys());
    std.mem.sort([]const u8, paths, {}, lessThan);
    var total: usize = 0;
    for (paths) |path| {
        const tally = session.report.changes.get(path).?;
        total += tally.edits;
        const shown = try display(session, path);
        try out.print(session.allocator, "{s} {s}: {d} edit{s} (", .{ verb, shown, tally.edits, if (tally.edits == 1) "" else "s" });
        for (tally.codes.items, 0..) |code, index| try out.print(session.allocator, "{s}{s}", .{ if (index == 0) "" else ", ", code });
        try out.appendSlice(session.allocator, ")\n");
    }
    if (total == 0) {
        try out.appendSlice(session.allocator, if (session.report.tuple_withheld) "fix: tuple repairs withheld; diagnostics remain\n" else "fix: nothing to fix\n");
    } else if (session.options.check) {
        try out.print(session.allocator, "fix --check: {d} edit{s} in {d} file{s} would change\n", .{ total, plural(total), paths.len, plural(paths.len) });
    } else {
        try out.print(session.allocator, "fix: {d} edit{s} in {d} file{s} over {d} round{s}\n", .{ total, plural(total), paths.len, plural(paths.len), session.report.rounds, plural(session.report.rounds) });
    }
    if (session.report.set_aside.count() != 0) {
        const fixes = session.report.set_aside.count();
        const files = session.report.set_aside_files.count();
        try out.print(session.allocator, "fix: left {d} fix{s} in {d} generated file{s} alone (the first line of each says `# generated by`; change the generator, or name a file to repair it)\n", .{
            fixes, if (fixes == 1) "" else "es", files, plural(files),
        });
    }
    try out.appendSlice(session.allocator, session.report.closing.items);
    if (session.report.in_packages.count() != 0) try out.appendSlice(session.allocator, try packagesLine(session));
    if (session.options.report) try out.appendSlice(session.allocator, try session.report.checks.line(session.allocator, session.report.rounds));
    try std.Io.File.stdout().writeStreamingAll(session.io, out.items);
}

/// The lines one path asks for after the totals, kept for `summarize` in the order the paths were repaired: the warnings with a
/// repair it left alone, and, for a module or test file, the fixes it left in the files it imports. Each names the command that
/// repairs them, with the path as it was written.
fn closing(session: *Session) !void {
    const out = &session.report.closing;
    if (session.report.left_warnings != 0) {
        const left = session.report.left_warnings;
        const command = try advice(session, if (session.options.imports) "--imports " else "", session.options.path, " --warnings");
        try out.print(session.allocator, "fix: left {d} warning{s} with a repair alone; `{s}` repairs {s} too\n", .{ left, plural(left), command, if (left == 1) "it" else "them" });
    }
    if (session.report.only) |file| if (session.report.left.fixes != 0) {
        const shown = try display(session, file);
        try out.print(session.allocator, "fix: left {d} fix{s} in {d} other file{s} that {s} imports; `{s}` repairs them too\n", .{
            session.report.left.fixes,                    if (session.report.left.fixes == 1) "" else "es", session.report.left.files, plural(session.report.left.files), shown,
            try advice(session, "--imports ", shown, ""),
        });
    };
}

/// The closing line of a `selka packages fix` run that left fixes in a package's files: how many, in which package, in one line.
fn packagesLine(session: *Session) ![]const u8 {
    var counts: std.array_hash_map.String(usize) = .empty;
    for (session.report.in_packages.values()) |package| {
        const slot = try counts.getOrPut(session.allocator, package);
        if (!slot.found_existing) slot.value_ptr.* = 0;
        slot.value_ptr.* += 1;
    }
    const names = try session.allocator.dupe([]const u8, counts.keys());
    std.mem.sort([]const u8, names, {}, lessThan);
    var line: std.ArrayList(u8) = .empty;
    try line.appendSlice(session.allocator, "fix: left ");
    for (names, 0..) |name, index| {
        const count = counts.get(name).?;
        const separator = if (index == 0) "" else if (index + 1 == names.len) " and " else ", ";
        try line.print(session.allocator, "{s}{d} fix{s} in package `{s}`", .{ separator, count, if (count == 1) "" else "es", name });
    }
    try line.appendSlice(session.allocator, " alone: `selka packages fix` never writes a package's files\n");
    return line.items;
}

/// The command a closing line advises: `selka fix FLAGS PATH TAIL`, or in a `selka packages fix` run that command with the lock.
fn advice(session: *Session, flags: []const u8, path: []const u8, tail: []const u8) ![]const u8 {
    const staged = session.staged orelse return std.mem.concat(session.allocator, u8, &.{ "selka fix ", flags, path, tail });
    return std.mem.concat(session.allocator, u8, &.{ "selka packages fix ", flags, path, " --lock ", staged.lock, tail });
}

/// `path` as the run shows it, relative to the working directory: in a `selka packages fix` run, a staged file is shown as the
/// application's own file it was staged from.
fn display(session: *Session, path: []const u8) ![]const u8 {
    const original = if (session.staged) |staged| original: {
        if (!std.mem.startsWith(u8, path, staged.directory) or !std.mem.startsWith(u8, path[staged.directory.len..], "/")) break :original path;
        break :original try std.fs.path.join(session.allocator, &.{ staged.app_root, path[staged.directory.len + 1 ..] });
    } else path;
    return std.fs.path.relativePosix(session.allocator, session.cwd, session.cwd, original);
}

fn plural(count: usize) []const u8 {
    return if (count == 1) "" else "s";
}
