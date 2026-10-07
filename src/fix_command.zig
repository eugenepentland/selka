//! `mylang fix`: apply every structured diagnostic fix a check publishes, check
//! again, and repeat until nothing mechanical is left; then report what changed
//! per file and the diagnostics that remain for a person to resolve.
//!
//! Each round runs this executable's own `check --diagnostics=json` on the
//! entry, so the fixes are exactly the `fix` fields of `diagnostic-v1`, located
//! by file and UTF-8 byte range. A round applies every fix whose edits do not
//! collide with another fix's; a colliding fix is left for the next round,
//! which sees the updated source. `--check` runs one round and writes nothing.
const std = @import("std");
const project_config = @import("mylang").project_config;
const fs = @import("qbe_build_io.zig");
const snapshot = @import("native_test_snapshot.zig");
const input_probe = @import("input_probe.zig");

const usage = "usage: mylang fix [--check] [--diagnostics=text|json] [--cache-dir=DIR] [--no-cache] <entry.my|directory>\n";
/// Rounds one entry may take before `fix` stops and reports that the fixes did
/// not converge. A round fixes every marker a function needs at once, so real
/// migrations settle in a handful; the cap only stops a fix that never takes.
const max_rounds = 200;
/// Largest source file a fix is applied to, matching the loader's own ceiling.
const file_limit = 16 * 1024 * 1024;
/// The cache switch `fix` accepts and passes on to every check it runs.
const cache_flag = "--cache-dir=";

/// Parsed command line.
const Options = struct {
    path: []const u8 = "",
    check: bool = false,
    json: bool = false,
    cache_dir: ?[]const u8 = null,
    no_cache: bool = false,
};

/// One edit a child check published, with its file resolved to an absolute path.
const Edit = struct { path: []const u8, start: usize, end: usize, text: []const u8 };
/// One diagnostic's fix: all of its edits apply together or not at all.
const Fix = struct { code: []const u8, edits: []const Edit };

/// What `fix` did to one file: how many edits, and which codes they repaired.
const Tally = struct { edits: usize = 0, codes: std.ArrayList([]const u8) = .empty };

/// Everything one invocation shares across its entries and rounds.
const Session = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    compiler: []const u8,
    cwd: []const u8,
    options: Options,
    report: Report = .{},
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
};

/// The `diagnostic-v1` fields a round reads; everything else is ignored.
const Wire = struct {
    version: []const u8 = "",
    kind: []const u8 = "",
    diagnostic: ?struct {
        code: []const u8 = "",
        fix: ?struct { edits: []const WireEdit = &.{} } = null,
    } = null,
};
const WireEdit = struct { path: []const u8 = "", bytes: struct { start: usize = 0, end: usize = 0 } = .{}, text: []const u8 = "" };

/// Run `mylang fix` with the arguments after the command name and return its
/// exit status: 0 when nothing is left to fix and every entry checks, 1 when
/// errors remain or `--check` found something to change, 2 on a usage or host
/// failure, which is named on stderr.
pub fn run(process: std.process.Init, args: []const []const u8) u8 {
    return runCommand(process, args) catch |err| {
        var buffer: [192]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "mylang fix: {s}\n", .{@errorName(err)}) catch "mylang fix: host failure\n";
        std.Io.File.stderr().writeStreamingAll(process.io, message) catch return 2;
        return 2;
    };
}

fn runCommand(process: std.process.Init, args: []const []const u8) !u8 {
    const options = parse(args) catch {
        try std.Io.File.stderr().writeStreamingAll(process.io, usage);
        return 2;
    };
    const allocator = process.arena.allocator();
    const compiler = std.process.executablePathAlloc(process.io, allocator) catch {
        try std.Io.File.stderr().writeStreamingAll(process.io, "mylang fix: cannot locate this executable\n");
        return 2;
    };
    const cwd = try std.Io.Dir.cwd().realPathFileAlloc(process.io, ".", allocator);
    if (try input_probe.check(allocator, process.io, "fix", options.path, true)) |refusal| {
        try std.Io.File.stderr().writeStreamingAll(process.io, refusal);
        return input_probe.refused_status;
    }
    const target = try std.Io.Dir.cwd().realPathFileAlloc(process.io, options.path, allocator);
    var session: Session = .{ .allocator = allocator, .io = process.io, .compiler = compiler, .cwd = cwd, .options = options };
    const entries = try entriesOf(process, target) orelse {
        const message = try std.fmt.allocPrint(allocator, "mylang fix: {s} is neither a .my entry nor a directory\n", .{options.path});
        try std.Io.File.stderr().writeStreamingAll(process.io, message);
        return 2;
    };
    var context = try fs.Context.init(process.gpa, process.io, process.environ_map);
    defer context.deinit();
    var covered: std.StringHashMapUnmanaged(void) = .empty;
    var status: u8 = 0;
    for (entries) |entry| {
        if (covered.contains(entry)) continue;
        const outcome = try fixEntry(&session, entry);
        status = @max(status, outcome);
        if (outcome == 2) break;
        // A module an entry imports was checked, and fixed, with it.
        const reached = snapshot.reach(context, entry) catch continue;
        for (reached) |path| try covered.put(allocator, path, {});
    }
    try summarize(&session);
    return status;
}

/// Parse the switches and the one entry or directory path.
fn parse(args: []const []const u8) error{Usage}!Options {
    var options: Options = .{};
    var path: ?[]const u8 = null;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--check")) {
            if (options.check) return error.Usage;
            options.check = true;
        } else if (std.mem.eql(u8, arg, "--no-cache")) {
            if (options.no_cache) return error.Usage;
            options.no_cache = true;
        } else if (std.mem.startsWith(u8, arg, "--diagnostics=")) {
            const value = arg["--diagnostics=".len..];
            if (std.mem.eql(u8, value, "json")) options.json = true else if (!std.mem.eql(u8, value, "text")) return error.Usage;
        } else if (std.mem.startsWith(u8, arg, cache_flag)) {
            if (options.cache_dir != null or arg.len == cache_flag.len) return error.Usage;
            options.cache_dir = arg[cache_flag.len..];
        } else if (std.mem.startsWith(u8, arg, "-") or path != null) {
            return error.Usage;
        } else path = arg;
    }
    options.path = path orelse return error.Usage;
    return options;
}

/// The entries one invocation fixes, in order: the one `.my` file named, or
/// every `.my` file under the directory named — programs (files that declare
/// `main`) first, then `*_test.my` files, then the remaining modules, each
/// group in path order. A module a program imports is skipped once that
/// program has been fixed, so a directory holding one project is one check per
/// round plus one per test file. Null when the path is neither.
fn entriesOf(process: std.process.Init, target: []const u8) !?[]const []const u8 {
    const allocator = process.arena.allocator();
    const stat = try std.Io.Dir.cwd().statFile(process.io, target, .{});
    if (stat.kind != .directory) {
        if (!std.mem.endsWith(u8, target, ".my")) return null;
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
        if (item.kind != .file or !std.mem.endsWith(u8, item.basename, ".my")) continue;
        const path = try std.fs.path.join(allocator, &.{ target, item.path });
        const bytes = std.Io.Dir.cwd().readFileAlloc(process.io, path, allocator, .limited(file_limit)) catch "";
        const group: usize = if (project_config.declaresMain(bytes)) 0 else if (std.mem.endsWith(u8, item.basename, "_test.my")) 1 else 2;
        try groups[group].append(allocator, path);
    }
    var ordered: std.ArrayList([]const u8) = .empty;
    for (&groups) |*group| {
        std.mem.sort([]const u8, group.items, {}, lessThan);
        try ordered.appendSlice(allocator, group.items);
    }
    return ordered.items;
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// Fix one entry to its fixed point, then report what still does not check.
/// Returns the entry's status: 0 checks, 1 errors remain (or `--check` found a
/// change), 2 the check itself could not run.
fn fixEntry(session: *Session, entry: []const u8) !u8 {
    const root = try projectRoot(session, entry);
    var round: usize = 0;
    while (round < max_rounds) : (round += 1) {
        const result = try check(session, entry, true);
        if (fs.exitCode(result.term) > 1) {
            try std.Io.File.stderr().writeStreamingAll(session.io, result.stderr);
            return 2;
        }
        const fixes = try collect(session, root, result.stderr);
        const chosen = try select(session.allocator, fixes);
        if (chosen.len == 0) break;
        session.report.rounds += 1;
        try record(session, chosen);
        if (session.options.check) return 1;
        try apply(session, chosen);
    } else {
        const message = try std.fmt.allocPrint(session.allocator, "mylang fix: {s}: fixes did not settle after {d} rounds\n", .{ entry, max_rounds });
        try std.Io.File.stderr().writeStreamingAll(session.io, message);
        return 1;
    }
    // The remaining diagnostics are the entry's own check, in the requested format.
    const final = try check(session, entry, session.options.json);
    try forward(session, final.stderr);
    return @min(fs.exitCode(final.term), 2);
}

/// Print a final check's diagnostics, each one once per invocation. A
/// diagnostic is a JSON line, or a text line that starts in column one together
/// with the indented lines under it.
fn forward(session: *Session, stderr: []const u8) !void {
    var out: std.ArrayList(u8) = .empty;
    var start: usize = 0;
    while (start < stderr.len) {
        var end = std.mem.indexOfScalarPos(u8, stderr, start, '\n') orelse stderr.len;
        if (!session.options.json) while (end + 1 < stderr.len and (stderr[end + 1] == ' ' or stderr[end + 1] == '\t')) {
            end = std.mem.indexOfScalarPos(u8, stderr, end + 1, '\n') orelse stderr.len;
        };
        const block = stderr[start..@min(end + 1, stderr.len)];
        const seen = try session.report.printed.getOrPut(session.allocator, block);
        if (!seen.found_existing) try out.appendSlice(session.allocator, block);
        start = end + 1;
    }
    try std.Io.File.stderr().writeStreamingAll(session.io, out.items);
}

/// The directory an entry's diagnostic paths are relative to: the enclosing
/// project root for a `*_test.my` entry, otherwise the entry's own directory.
fn projectRoot(session: *Session, entry: []const u8) ![]const u8 {
    if (project_config.testEntryLocation(session.allocator, session.io, entry) catch null) |location| return location.root;
    return std.fs.path.dirname(entry) orelse session.cwd;
}

/// Run this executable's `check` on one entry and capture its output.
fn check(session: *Session, entry: []const u8, json: bool) !std.process.RunResult {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(session.allocator, &.{ session.compiler, "check", entry, if (json) "--diagnostics=json" else "--diagnostics=text" });
    if (session.options.no_cache) try argv.append(session.allocator, "--no-cache");
    if (session.options.cache_dir) |directory| try argv.append(session.allocator, try std.mem.concat(session.allocator, u8, &.{ cache_flag, directory }));
    return std.process.run(session.allocator, session.io, .{ .argv = argv.items });
}

/// Every fix one check published, with each edit's file resolved against the
/// entry's project root. A fix naming an embedded standard module is dropped:
/// `fix` only ever edits the user's own files.
fn collect(session: *Session, root: []const u8, stderr: []const u8) ![]const Fix {
    var fixes: std.ArrayList(Fix) = .empty;
    var lines = std.mem.splitScalar(u8, stderr, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] != '{') continue;
        const wire = std.json.parseFromSliceLeaky(Wire, session.allocator, line, .{ .ignore_unknown_fields = true }) catch continue;
        if (!std.mem.eql(u8, wire.version, "diagnostic-v1")) continue;
        const diagnostic = wire.diagnostic orelse continue;
        const fix = diagnostic.fix orelse continue;
        if (fix.edits.len == 0) continue;
        const edits = try session.allocator.alloc(Edit, fix.edits.len);
        const usable = for (fix.edits, edits) |input, *output| {
            if (std.mem.startsWith(u8, input.path, "@stdlib/") or input.bytes.start > input.bytes.end) break false;
            output.* = .{
                .path = try std.fs.path.resolve(session.allocator, &.{ root, input.path }),
                .start = input.bytes.start,
                .end = input.bytes.end,
                .text = input.text,
            };
        } else true;
        if (usable) try fixes.append(session.allocator, .{ .code = diagnostic.code, .edits = edits });
    }
    return fixes.items;
}

/// The distinct edits one round applies, each with the code of the fix that
/// asked for it: every fix in order whose edits collide with no edit already
/// chosen. An edit identical to a chosen one (the same repair reported twice,
/// as a generic function's instances do) is a duplicate, not a collision, and
/// is applied once.
fn select(allocator: std.mem.Allocator, fixes: []const Fix) ![]const Planned {
    var taken: std.ArrayList(Planned) = .empty;
    for (fixes) |fix| {
        if (collides(fix, taken.items)) continue;
        for (fix.edits) |edit| {
            const seen = for (taken.items) |other| {
                if (same(edit, other.edit)) break true;
            } else false;
            if (!seen) try taken.append(allocator, .{ .code = fix.code, .edit = edit });
        }
    }
    return taken.items;
}

/// Whether any edit of `fix` overlaps a different edit already taken.
fn collides(fix: Fix, taken: []const Planned) bool {
    for (fix.edits) |edit| for (taken) |other| {
        if (!same(edit, other.edit) and overlaps(edit, other.edit)) return true;
    };
    return false;
}

/// One edit a round applies and the diagnostic code whose fix it belongs to.
const Planned = struct { code: []const u8, edit: Edit };

fn same(a: Edit, b: Edit) bool {
    return a.start == b.start and a.end == b.end and std.mem.eql(u8, a.path, b.path) and std.mem.eql(u8, a.text, b.text);
}

/// Whether two different edits of one file touch the same bytes or the same
/// insertion point, where applying both would depend on their order.
fn overlaps(a: Edit, b: Edit) bool {
    if (!std.mem.eql(u8, a.path, b.path)) return false;
    if (a.start == b.start) return true;
    return a.start < b.end and b.start < a.end;
}

/// Count the chosen edits against the files they change.
fn record(session: *Session, chosen: []const Planned) !void {
    for (chosen) |planned| {
        const entry = try session.report.changes.getOrPut(session.allocator, planned.edit.path);
        if (!entry.found_existing) entry.value_ptr.* = .{};
        entry.value_ptr.edits += 1;
        for (entry.value_ptr.codes.items) |code| {
            if (std.mem.eql(u8, code, planned.code)) break;
        } else try entry.value_ptr.codes.append(session.allocator, planned.code);
    }
}

/// Apply the chosen edits file by file, from the end of each file backwards so
/// every earlier offset stays valid. A file whose edits no longer fit its
/// current bytes is left alone; the next round's check reports it afresh.
fn apply(session: *Session, chosen: []const Planned) !void {
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
        try std.Io.Dir.cwd().writeFile(session.io, .{ .sub_path = path, .data = text.items });
    }
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
        const shown = try std.fs.path.relativePosix(session.allocator, session.cwd, session.cwd, path);
        try out.print(session.allocator, "{s} {s}: {d} edit{s} (", .{ verb, shown, tally.edits, if (tally.edits == 1) "" else "s" });
        for (tally.codes.items, 0..) |code, index| try out.print(session.allocator, "{s}{s}", .{ if (index == 0) "" else ", ", code });
        try out.appendSlice(session.allocator, ")\n");
    }
    if (total == 0) {
        try out.appendSlice(session.allocator, "fix: nothing to fix\n");
    } else if (session.options.check) {
        try out.print(session.allocator, "fix --check: {d} edit{s} in {d} file{s} would change\n", .{ total, plural(total), paths.len, plural(paths.len) });
    } else {
        try out.print(session.allocator, "fix: {d} edit{s} in {d} file{s} over {d} round{s}\n", .{ total, plural(total), paths.len, plural(paths.len), session.report.rounds, plural(session.report.rounds) });
    }
    try std.Io.File.stdout().writeStreamingAll(session.io, out.items);
}

fn plural(count: usize) []const u8 {
    return if (count == 1) "" else "s";
}
