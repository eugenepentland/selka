//! Which warnings a command prints in full, and which it counts.
//!
//! A project that has warnings gets them on every `check`, `build`, `run` and `test`, replays included: the G3 port prints 215
//! of them (645 lines) each time, and whoever reads the output pays for lines about code nobody touched. This is the display
//! policy that keeps the diagnostics whole and the output short.
//!
//! A warning is printed in full unless its module is **tracked by git and identical to `HEAD`**: then it is counted, and the
//! command ends with one line that says how many and how to see them. A module with uncommitted edits, an untracked or
//! ignored one, and any module outside a git repository print as they always did, so the warnings a change introduced are
//! the ones in front of its author. `build`, `run`, `run-project` and `test` also leave out the hints: `W_COPY_MOVE` (advice
//! about a copy a move could replace, about 450 lines on each build of the netlisp port) and `W_MATCH_ELSE` and `W_MATCH_IS`
//! (a `match` the flat forms say shorter, 1,218 on each build of the port before its `selka fix`); `check`, `check-project`,
//! `check-module` and `lint` print them. The rule reads the tree and never a cache, so a cached check, a replayed build and
//! a `--no-cache` one print the same text (the exactness the front end promises). `--warnings` (or `SELKA_WARNINGS=all`) prints
//! every warning, `--diagnostics=json` always carries every one, and a project that denies warnings
//! (`lint.warnings: "deny"`) prints them all when it fails on them.
//!
//! `check FILE` prints the warnings of that file, and for each other module it reached that has warnings one line,
//! `` helper.selka: 3 warnings; `selka check helper.selka` ``, so that checking one file after another does not repeat the warnings of
//! every module it imports. The same exceptions hold (`--warnings`, `SELKA_WARNINGS=all`, JSON, a project that denies warnings),
//! and a check that names its format (`--diagnostics=text`, which `selka fix` asks for) prints them all; `check DIR` is not changed.
//!
//! A command that printed a diagnostic with a structured fix ends with one more line, `` `selka fix FILE` repairs N of these M ``: N
//! of the M diagnostics it printed, errors and warnings together, carry a fix (`fix_tally.zig`). The count is of what was printed, so
//! a withheld warning or a dropped hint is in neither number, and a JSON report has no such line. A directory run (`selka test DIR`)
//! starts a process per entry: each hands its two counts to the run through a file (`count_option`) instead of closing its own
//! report, and the run adds them to what it printed itself and ends with one line, the path as it was given and the counts summed,
//! so ten entries with one finding each read `` `selka fix DIR` repairs 10 of these 10 ``, one command, at every `--jobs`. The
//! warnings a child withheld ride in the same file, one record each, and the run counts each place and code once, so ten entries that
//! import one module with a warning end in one `warnings:` line that counts that warning once, the same at every `--jobs`.
//!
//! A build through `selka packages` runs the project command over a staged copy and tells it, with `packages_option`, the package
//! namespaces the lock lists. A warning whose file is in one of those namespaces is not printed (neither its line nor its source):
//! `finish` ends with one line per package that says how many were left out. Such a run's closing line names `selka packages fix` with
//! the entry and the lock as the user gave them (`package_fix_option`), never `selka fix`, which does not know the package, and the
//! staged copy, which is deleted when the command ends; a diagnostic in a package's file is not counted as one that command repairs.
//! An error in a package's file is printed, `--warnings`, `SELKA_WARNINGS=all` and `--diagnostics=json` list every warning, and a
//! project that denies warnings prints them when it fails on them, as for the withheld ones.
//!
//! The process wiring brackets a command with `begin` and `finish`; the commands write their rendered diagnostics through `write`.
const std = @import("std");
const product = @import("../product.zig");
const fix_tally = @import("fix_tally.zig");

/// The option that prints every warning in full.
pub const flag = "--warnings";
/// The environment variable that does the same for a whole session, `all` being the one value.
pub const variable = "SELKA_WARNINGS";
/// The internal option a directory run gives each child root, followed by a file: the child writes there how many diagnostics it
/// printed, how many carry a fix and the warnings it withheld, instead of closing with the `selka fix` and `warnings:` lines, which the
/// directory run prints once for all. `selka test` reads it (`countInto`), like every other option of a child root.
pub const count_option = "--fix-count-file";
/// The internal option `selka packages build` gives the project command it runs over the staged snapshot, followed by the namespaces
/// of the locked packages, comma-separated (empty when it locks none): the warnings of their files are counted per package, not printed,
/// and the command prints no `selka fix` line (`package_fix_option` gives the line it prints instead). `begin` takes it out of the line, and a directory run passes it on to each child root
/// (`packageNames`).
pub const packages_option = "--package-namespaces";
/// The internal option `selka packages build` gives the same commands, followed by the entry and the lock as the user gave them
/// (`ENTRY --lock LOCK`): the command closes with the line that names `selka packages fix` with them, where it would name `selka fix`.
pub const package_fix_option = "--package-fix";

/// What writing a report can fail with: the stream, or memory for the bookkeeping.
pub const WriteError = std.Io.File.Writer.Error || std.mem.Allocator.Error;

/// Commands whose diagnostics this policy covers: the ones that check a program on the way to something else, and `api`, which
/// prints none but is told the packages of a staged snapshot (`packages_option`) and takes the option out of its line.
const commands = [_][]const u8{ "check", "check-project", "check-module", "build", "run", "run-project", "test", "api" };

/// The commands that build a program to use it, and that therefore leave the hints out: advice about a copy a move could
/// replace is for whoever is editing the code (`check`, `lint`), not for each build of the netlisp port (450 lines every time).
const hiding_commands = [_][]const u8{ "build", "run", "run-project", "test" };

/// The warnings that are hints by design: each reports a possible rewrite of code that is not wrong, for whoever edits it.
const hint_codes = [_][]const u8{ "W_COPY_MOVE", "W_MATCH_ELSE", "W_MATCH_IS" };

/// Options whose value is the next argument, which the search for the command's entry skips.
const valued_options = [_][]const u8{
    "-o",          "--cache-dir",  "--zig",     "--link",  "--filter", "--jobs",    "--seed",        "--threads",        "--timeout-ms", "--max-memory",
    "--max-steps", "--max-frames", "--against", "--cases", "--policy", "--project", packages_option, package_fix_option,
};

/// The warnings a command has withheld so far, each once: the same place and code is one warning however many roots print it.
const Withheld = struct {
    count: usize = 0,
    /// Their text, kept for a project that denies warnings.
    text: std.ArrayList(u8) = .empty,
    /// The same warnings as the records a child root of a directory run hands to the run (`record`).
    records: std.ArrayList(u8) = .empty,
    /// The warnings withheld, as `module:line:column:code` (`withhold`).
    seen: std.StringHashMapUnmanaged(void) = .empty,
    modules: std.StringHashMapUnmanaged(void) = .empty,
    codes: std.array_hash_map.String(usize) = .empty,
};

/// The warnings a build through `selka packages` leaves out because their files belong to a locked package (`packages_option`).
const Hidden = struct {
    /// The package namespaces, comma-separated (empty when the lock has none); null outside a build through `selka packages`.
    names: ?[]const u8 = null,
    /// The entry and the lock of the `selka packages fix` the closing line names (`package_fix_option`); null when none was given.
    fix: ?[]const u8 = null,
    /// The warnings left out, each once, as `path:line:column:code`: the same place and code is one warning however many roots print it.
    seen: std.StringHashMapUnmanaged(void) = .empty,
    /// How many were left out in each package.
    counts: std.array_hash_map.String(usize) = .empty,
    /// Their text, kept for a project that denies warnings.
    text: std.ArrayList(u8) = .empty,
    /// The same warnings as the records a child root of a directory run hands to the run (`handOver`), each `@package`, a line, its text.
    records: std.ArrayList(u8) = .empty,
};

/// The warnings `check FILE` leaves out because they are in another module than the file it names: one line per module stands for
/// them (`elsewhereLines`), so that each run shows the file being worked on, not every warning of every module it imports.
const Elsewhere = struct {
    /// The named file as an absolute path; empty when the rule is off (another command, a directory, every warning or a named format).
    entry: []const u8 = "",
    /// The working directory, which the command each line names is relative to.
    cwd: []const u8 = "",
    /// The warnings left out, each once, as `path:line:column:code`.
    seen: std.StringHashMapUnmanaged(void) = .empty,
    /// How many were left out in each module, by the path the warnings print.
    counts: std.array_hash_map.String(usize) = .empty,
    /// Their text, kept for a project that denies warnings.
    text: std.ArrayList(u8) = .empty,
};

/// The files of the entry's directory tree that git tracks and that equal `HEAD`, as absolute paths.
const Tree = struct {
    unmodified: std.StringHashMapUnmanaged(void) = .empty,
    known: bool = false,
};

const State = struct {
    /// Owns everything the state keeps: the process arena the command runs in.
    // SAFETY: `begin` sets it before anything else reads it; `write` and `finish` do nothing until a warning was withheld.
    allocator: std.mem.Allocator = undefined,
    /// The command is one the policy covers and nothing asked for every warning.
    active: bool = false,
    /// The command is one the policy covers and prints text: the diagnostics it prints are counted for the closing `selka fix` line.
    counting: bool = false,
    /// The path the command was given, as it was given, for the closing line; empty when the command named none.
    entry: []const u8 = "",
    /// The diagnostics printed so far, and how many of them carry a structured fix.
    reported: usize = 0,
    fixable: usize = 0,
    /// How many of the `fixable` are errors; a run that absorbs a directory's counts (`absorb`) does not know, and prints no such split.
    fixable_errors: usize = 0,
    /// Where a child root of a directory run leaves those two counts (`count_option`); empty for every other command.
    count_file: []const u8 = "",
    /// The command builds a program and prints no hint (`hiding_commands`); implies `active`.
    hide_hints: bool = false,
    /// The directory the entry lives in; printed module paths are looked for in it and the directories above it.
    base: []const u8 = "",
    withheld: Withheld = .{},
    /// The warnings of the locked packages a build through `selka packages` leaves out.
    hidden: Hidden = .{},
    /// The warnings of the other modules a `check FILE` leaves out.
    elsewhere: Elsewhere = .{},
    /// What git says about the base directory's tree, read once when the first warning needs it.
    tree: ?Tree = null,
    denied: bool = false,
};

var state: State = .{};
var lock: std.Io.Mutex = .init;

/// What `begin` decides from the command line.
pub const Selection = struct {
    /// The arguments to give the command: the line without `--warnings`.
    args: []const [:0]const u8,
    active: bool,
};

/// Decide how the command prints its warnings. `args` is the whole command line (program name first); the result is the line with
/// `--warnings` taken out, since no command parses it, and whether the policy covers this run. The flag also sets `SELKA_WARNINGS=all`
/// in `environ`, which the processes a directory run starts inherit. `allocator` must outlive the command (the process arena).
pub fn begin(allocator: std.mem.Allocator, io: std.Io, environ: *std.process.Environ.Map, args: []const [:0]const u8) std.mem.Allocator.Error!Selection {
    state = .{ .allocator = allocator };
    fix_tally.enable(false);
    if (args.len < 2 or !covered(args[1])) return .{ .args = args, .active = false };
    var everything = false;
    var json = false;
    var named_format = false;
    if (environ.get(variable)) |value| everything = std.mem.eql(u8, value, "all");
    var kept: std.ArrayList([:0]const u8) = .empty;
    var taken = false;
    for (args, 0..) |arg, index| {
        if (taken) {
            taken = false;
            continue;
        }
        if (std.mem.eql(u8, arg, "--")) {
            try kept.appendSlice(allocator, args[index..]);
            break;
        }
        if (index + 1 < args.len and std.mem.eql(u8, arg, packages_option)) {
            state.hidden.names = args[index + 1];
            taken = true;
            continue;
        }
        if (index + 1 < args.len and std.mem.eql(u8, arg, package_fix_option)) {
            state.hidden.fix = args[index + 1];
            taken = true;
            continue;
        }
        if (std.mem.eql(u8, arg, flag)) {
            everything = true;
            // A directory run starts a process per entry from this environment: they list every warning too.
            try environ.put(variable, "all");
            continue;
        }
        if (std.mem.eql(u8, arg, "--diagnostics=json")) json = true;
        if (std.mem.eql(u8, arg, "--diagnostics") and index + 1 < args.len and std.mem.eql(u8, args[index + 1], "json")) json = true;
        if (std.mem.startsWith(u8, arg, "--diagnostics")) named_format = true;
        try kept.append(allocator, arg);
    }
    state.active = !everything and !json;
    state.counting = !json;
    fix_tally.enable(state.counting);
    state.hide_hints = state.active and hides(args[1]);
    const entry = entryArgument(io, args);
    state.entry = entry orelse "";
    if (state.active) state.base = if (entry) |named| try entryDirectory(allocator, io, named) else "";
    // `check FILE` as a person types it; a tool that names the format (`selka fix` asks for `--diagnostics=text`) gets every warning.
    if (state.active and !named_format and std.mem.eql(u8, args[1], "check")) if (entry) |named| try elsewhereFor(allocator, io, named);
    return .{ .args = kept.items, .active = state.active };
}

/// Turn on the rule that leaves out the warnings of the modules `check FILE` reaches besides `named`, when `named` is a file.
fn elsewhereFor(allocator: std.mem.Allocator, io: std.Io, named: []const u8) std.mem.Allocator.Error!void {
    const stat = std.Io.Dir.cwd().statFile(io, named, .{}) catch return;
    if (stat.kind == .directory) return;
    const real = std.Io.Dir.cwd().realPathFileAlloc(io, named, allocator) catch return;
    const cwd = std.Io.Dir.cwd().realPathFileAlloc(io, ".", allocator) catch return;
    state.elsewhere.entry = real;
    state.elsewhere.cwd = cwd;
}

/// Whether this policy covers `command`: the ones that check a program on the way to something else.
pub fn covered(command: []const u8) bool {
    for (commands) |name| if (std.mem.eql(u8, name, command)) return true;
    return false;
}

/// Whether a warning is one of the hints a build command leaves out.
fn hint(code: []const u8) bool {
    for (hint_codes) |known| if (std.mem.eql(u8, known, code)) return true;
    return false;
}

/// Whether `command` builds a program and so prints no hint (`hint_codes`) unless every warning was asked for.
fn hides(command: []const u8) bool {
    for (hiding_commands) |name| if (std.mem.eql(u8, name, command)) return true;
    return false;
}

/// The command's entry: its first argument that names an existing file or directory, as it was given, skipping the values of the
/// options that take one. Null when there is none.
fn entryArgument(io: std.Io, args: []const [:0]const u8) ?[]const u8 {
    var index: usize = 2;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--")) break;
        if (arg.len != 0 and arg[0] == '-') {
            for (valued_options) |name| if (std.mem.eql(u8, arg, name)) {
                index += 1;
                break;
            };
            continue;
        }
        _ = std.Io.Dir.cwd().statFile(io, arg, .{}) catch continue;
        return arg;
    }
    return null;
}

/// The directory of the command's entry `entry` (see `entryArgument`). Empty when it cannot be resolved, which makes every module
/// print.
fn entryDirectory(allocator: std.mem.Allocator, io: std.Io, entry: []const u8) std.mem.Allocator.Error![]const u8 {
    const stat = std.Io.Dir.cwd().statFile(io, entry, .{}) catch return "";
    const real = std.Io.Dir.cwd().realPathFileAlloc(io, entry, allocator) catch return "";
    if (stat.kind == .directory) return real;
    return std.fs.path.dirname(real) orelse "";
}

/// Note that the project denies warnings: a command that then fails prints every one it withheld.
pub fn deny() void {
    state.denied = true;
}

/// Write `bytes`, rendered diagnostics, to standard error, withholding the warnings of modules git tracks unmodified.
pub fn write(io: std.Io, bytes: []const u8) WriteError!void {
    const stderr = std.Io.File.stderr();
    if (!state.counting or bytes.len == 0) return stderr.writeStreamingAll(io, bytes);
    if (std.mem.indexOf(u8, bytes, ": warning[") == null and std.mem.indexOf(u8, bytes, ": error[") == null) return stderr.writeStreamingAll(io, bytes);
    lock.lockUncancelable(io);
    defer lock.unlock(io);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(state.allocator);
    try filtered(io, bytes, &out);
    if (out.items.len != 0) try stderr.writeStreamingAll(io, out.items);
}

/// Append to `out` the text of `bytes` that is printed: everything except the warnings withheld, which are counted.
fn filtered(io: std.Io, bytes: []const u8, out: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var block: ?Block = null;
    var offset: usize = 0;
    while (lines.next()) |line| {
        const end = @min(offset + line.len + 1, bytes.len);
        const with_newline = bytes[offset..end];
        offset = end;
        if (block) |*open| {
            if (line.len != 0 and (line[0] == ' ' or line[0] == '\t')) {
                open.length += with_newline.len;
                continue;
            }
            try settle(io, bytes, open.*, out);
            block = null;
        }
        if (header(line)) |found| {
            block = .{ .start = offset - with_newline.len, .length = with_newline.len, .path = found.path, .position = found.position, .code = found.code };
        } else {
            if (errorHeader(line)) tally(line);
            try out.appendSlice(state.allocator, with_newline);
        }
    }
    if (block) |open| try settle(io, bytes, open, out);
}

/// One warning as the text renderer prints it: a header line and the indented lines under it.
const Block = struct { start: usize, length: usize, path: []const u8, position: []const u8, code: []const u8 };

/// Print the warning `block` of `bytes` into `out`, or withhold it.
fn settle(io: std.Io, bytes: []const u8, block: Block, out: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    const allocator = state.allocator;
    const text = bytes[block.start .. block.start + block.length];
    // A hint is dropped, not counted: no build command fails on a warning, so none is owed to a project that denies them.
    if (state.hide_hints and hint(block.code)) return;
    if (state.active) if (packageOf(block.path)) |name| return hide(name, text, .{ .path = block.path, .position = block.position, .code = block.code });
    if (state.active and try elsewhere(io, block.path)) return leaveOut(text, .{ .path = block.path, .position = block.position, .code = block.code });
    const module = if (state.active) try unmodified(io, block.path) else null;
    if (module == null) {
        tally(fix_tally.firstLine(text));
        return out.appendSlice(allocator, text);
    }
    try withhold(module.?, text, .{ .path = block.path, .position = block.position, .code = block.code });
}

/// Withhold the warning `text`, whose header is `found`, of the module at the absolute path `module`, which the state takes over: count
/// it, keep its text and its record, unless the same place and code was withheld before.
fn withhold(module: []const u8, text: []const u8, found: Header) std.mem.Allocator.Error!void {
    const allocator = state.allocator;
    const withheld = &state.withheld;
    const key = try std.fmt.allocPrint(allocator, "{s}:{s}:{s}", .{ module, found.position, found.code });
    if ((try withheld.seen.getOrPut(allocator, key)).found_existing) {
        allocator.free(key);
        return allocator.free(module);
    }
    withheld.count += 1;
    try withheld.text.appendSlice(allocator, text);
    try withheld.records.print(allocator, "{s}\n{s}\x00", .{ module, text });
    if (withheld.codes.getPtr(found.code)) |existing| {
        existing.* += 1;
    } else try withheld.codes.put(allocator, try allocator.dupe(u8, found.code), 1);
    if (withheld.modules.contains(module)) return allocator.free(module);
    try withheld.modules.put(allocator, module, {});
}

/// The locked package whose files include the printed `path` (`name.selka` or anything under `name/`, as the lock lists them), or null.
/// A path that is absolute is looked for under the entry's directory, which is the staged snapshot's root.
fn packageOf(path: []const u8) ?[]const u8 {
    const namespaces = state.hidden.names orelse return null;
    var relative = path;
    if (std.fs.path.isAbsolute(path)) {
        const root = state.base;
        const under = root.len != 0 and path.len > root.len and std.mem.startsWith(u8, path, root);
        if (!under or path[root.len] != '/') return null;
        relative = path[root.len + 1 ..];
    }
    var names = std.mem.splitScalar(u8, namespaces, ',');
    while (names.next()) |name| {
        if (name.len == 0 or !std.mem.startsWith(u8, relative, name)) continue;
        const rest = relative[name.len..];
        if (std.mem.eql(u8, rest, product.source_suffix) or (rest.len != 0 and rest[0] == '/')) return name;
    }
    return null;
}

/// Leave out the warning `text`, whose header is `found`, of a file of package `name`: count it for the package, keep its text and its
/// record, unless the same place and code was left out before.
fn hide(name: []const u8, text: []const u8, found: Header) std.mem.Allocator.Error!void {
    const allocator = state.allocator;
    const hidden = &state.hidden;
    const key = try std.fmt.allocPrint(allocator, "{s}:{s}:{s}", .{ found.path, found.position, found.code });
    if ((try hidden.seen.getOrPut(allocator, key)).found_existing) return allocator.free(key);
    try hidden.text.appendSlice(allocator, text);
    try hidden.records.print(allocator, "@{s}\n{s}\x00", .{ name, text });
    if (hidden.counts.getPtr(name)) |existing| {
        existing.* += 1;
    } else try hidden.counts.put(allocator, try allocator.dupe(u8, name), 1);
}

/// Whether the printed `path` is a module `check FILE` reached besides the file it names. A path that cannot be found is not: its
/// warning prints, as for the rule of unmodified modules.
fn elsewhere(io: std.Io, path: []const u8) std.mem.Allocator.Error!bool {
    const entry = state.elsewhere.entry;
    if (entry.len == 0) return false;
    const absolute = try locate(io, path) orelse return false;
    defer state.allocator.free(absolute);
    return !std.mem.eql(u8, absolute, entry);
}

/// Leave out the warning `text`, whose header is `found`, of a module other than the one `check FILE` names: count it for its
/// module and keep its text, unless the same place and code was left out before.
fn leaveOut(text: []const u8, found: Header) std.mem.Allocator.Error!void {
    const allocator = state.allocator;
    const others = &state.elsewhere;
    const key = try std.fmt.allocPrint(allocator, "{s}:{s}:{s}", .{ found.path, found.position, found.code });
    if ((try others.seen.getOrPut(allocator, key)).found_existing) return allocator.free(key);
    try others.text.appendSlice(allocator, text);
    if (others.counts.getPtr(found.path)) |existing| {
        existing.* += 1;
    } else try others.counts.put(allocator, try allocator.dupe(u8, found.path), 1);
}

const Header = struct { path: []const u8, position: []const u8, code: []const u8 };

/// The path, position (`line:column`) and code of a `path:line:column: warning[CODE]: message` line, or null.
fn header(line: []const u8) ?Header {
    return headerAt(line, ": warning[");
}

/// Whether `line` is the first line of a printed error, `path:line:column: error[CODE]: message`.
fn errorHeader(line: []const u8) bool {
    return headerAt(line, ": error[") != null;
}

/// Count one printed diagnostic, whose first line is `line`, for the closing `selka fix` line.
fn tally(line: []const u8) void {
    state.reported += 1;
    if (!fix_tally.carries(line)) return;
    // A package's file is never repaired by `selka packages fix`, which the closing line of a build through `selka packages` names.
    const found = header(line) orelse headerAt(line, ": error[");
    if (found) |diagnostic| if (packageOf(diagnostic.path) != null) return;
    state.fixable += 1;
    if (errorHeader(line)) state.fixable_errors += 1;
}

/// Count the diagnostics in `bytes`, which were printed some other way than through `filtered`.
fn tallyText(bytes: []const u8) void {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| if (header(line) != null or errorHeader(line)) tally(line);
}

/// The path and code of a diagnostic's first line, which has `marker` (`: warning[` or `: error[`) after its position.
fn headerAt(line: []const u8, marker_text: []const u8) ?Header {
    const marker = std.mem.indexOf(u8, line, marker_text) orelse return null;
    const code_start = marker + marker_text.len;
    const code_end = std.mem.indexOfScalarPos(u8, line, code_start, ']') orelse return null;
    // `path:line:column`: strip the two numbers from the end.
    var path = line[0..marker];
    var strips: usize = 0;
    while (strips < 2) : (strips += 1) {
        const colon = std.mem.lastIndexOfScalar(u8, path, ':') orelse return null;
        const digits = path[colon + 1 ..];
        if (digits.len == 0) return null;
        for (digits) |byte| if (!std.ascii.isDigit(byte)) return null;
        path = path[0..colon];
    }
    if (path.len == 0) return null;
    return .{ .path = path, .position = line[path.len + 1 .. marker], .code = line[code_start..code_end] };
}

/// The absolute path of `path` (as a warning prints it) when it is a module git tracks and finds equal to `HEAD`. Anything else,
/// including a failed git call, gives null: the warning prints. The path is the state's, kept as the module's name.
fn unmodified(io: std.Io, path: []const u8) std.mem.Allocator.Error!?[]const u8 {
    if (state.base.len == 0) return null;
    if (state.tree == null) state.tree = try readTree(io);
    const tree = state.tree.?;
    if (!tree.known) return null;
    const absolute = try locate(io, path) orelse return null;
    if (tree.unmodified.contains(absolute)) return absolute;
    state.allocator.free(absolute);
    return null;
}

/// The absolute path of a printed module path: absolute already, or relative to the entry's directory or one above it.
fn locate(io: std.Io, path: []const u8) std.mem.Allocator.Error!?[]const u8 {
    const allocator = state.allocator;
    if (std.fs.path.isAbsolute(path)) {
        const copy = try allocator.dupe(u8, path);
        return copy;
    }
    var directory: []const u8 = state.base;
    while (true) {
        const candidate = try std.fs.path.join(allocator, &.{ directory, path });
        if (std.Io.Dir.cwd().statFile(io, candidate, .{})) |_| return candidate else |_| allocator.free(candidate);
        directory = std.fs.path.dirname(directory) orelse return null;
    }
}

/// Ask git for the tracked files of the entry's tree and for those that differ from `HEAD`; what is tracked and not different
/// is unmodified. Not a repository, no commit yet or no git: `known` stays false.
fn readTree(io: std.Io) std.mem.Allocator.Error!Tree {
    const allocator = state.allocator;
    var tree: Tree = .{};
    const top = (try git(io, &.{ "rev-parse", "--show-toplevel" })) orelse return tree;
    defer allocator.free(top);
    const root = std.mem.trimEnd(u8, top, "\r\n");
    const tracked = (try git(io, &.{ "ls-files", "-z", "--full-name", "--", "." })) orelse return tree;
    defer allocator.free(tracked);
    const changed = (try git(io, &.{ "diff", "--name-only", "-z", "--no-renames", "HEAD", "--", "." })) orelse return tree;
    defer allocator.free(changed);
    var modified: std.StringHashMapUnmanaged(void) = .empty;
    defer modified.deinit(allocator);
    var changes = std.mem.splitScalar(u8, changed, 0);
    while (changes.next()) |name| if (name.len != 0) try modified.put(allocator, name, {});
    var names = std.mem.splitScalar(u8, tracked, 0);
    while (names.next()) |name| {
        if (name.len == 0 or modified.contains(name)) continue;
        const absolute = try std.fs.path.join(allocator, &.{ root, name });
        try tree.unmodified.put(allocator, absolute, {});
    }
    tree.known = true;
    return tree;
}

/// The standard output of `git -C <base> args`, or null when git cannot be run or fails.
fn git(io: std.Io, args: []const []const u8) std.mem.Allocator.Error!?[]u8 {
    const allocator = state.allocator;
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.appendSlice(allocator, &.{ "git", "-C", state.base });
    try argv.appendSlice(allocator, args);
    const result = std.process.run(allocator, io, .{ .argv = argv.items }) catch return null;
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code == 0) return result.stdout,
        else => {},
    }
    allocator.free(result.stdout);
    return null;
}

/// End the command with `status`: one line for the warnings withheld, or all of them when the project denies warnings and the
/// command failed.
pub fn finish(io: std.Io, status: u8) void {
    defer state = .{};
    defer fix_tally.enable(false);
    const withheld = state.withheld;
    const stderr = std.Io.File.stderr();
    // A child root of a directory run leaves the warnings it withheld to the run, which prints one line for all of them (`handOver`);
    // one that fails in a project that denies warnings prints what it withheld itself, as it always did.
    const printing = state.denied and status != 0;
    const leaving = state.count_file.len != 0 and !printing;
    if (state.elsewhere.counts.count() != 0) printElsewhere(io, printing);
    if (withheld.count != 0 and !leaving) {
        if (printing) {
            tallyText(withheld.text.items);
            stderr.writeStreamingAll(io, withheld.text.items) catch return;
        } else {
            const line = summary(state.allocator, withheld.count, withheld.modules.count(), withheld.codes) catch return;
            defer state.allocator.free(line);
            stderr.writeStreamingAll(io, line) catch return;
        }
    }
    if (state.hidden.counts.count() != 0 and !leaving) printHidden(io, printing);
    if (state.count_file.len != 0) return handOver(io, leaving);
    if (state.fixable == 0) return;
    const fixable: Repairs = .{ .errors = state.fixable_errors, .warnings = state.fixable - state.fixable_errors };
    // A run through `selka packages` names `selka packages fix` with the user's entry and lock, never `selka fix` and the staged
    // copy, which does not know the package and is gone; told neither, it prints no such line.
    const closing = if (state.hidden.names == null)
        fixLine(state.allocator, state.entry, fixable, state.reported) catch return
    else if (state.hidden.fix) |given| packagesFixLine(state.allocator, given, product.isSource(state.entry), fixable, state.reported) catch return else return;
    defer state.allocator.free(closing);
    stderr.writeStreamingAll(io, closing) catch return;
}

/// Print the warnings a build through `selka packages` left out: all of them when the project denies warnings and the command failed
/// (they are why it failed), else one line per package (`hiddenLines`).
fn printHidden(io: std.Io, printing: bool) void {
    const stderr = std.Io.File.stderr();
    if (printing) {
        tallyText(state.hidden.text.items);
        stderr.writeStreamingAll(io, state.hidden.text.items) catch return;
        return;
    }
    const lines = hiddenLines(state.allocator, state.hidden.counts) catch return;
    defer state.allocator.free(lines);
    stderr.writeStreamingAll(io, lines) catch return;
}

/// Print the warnings `check FILE` left out of the other modules: all of them when the project denies warnings and the command
/// failed, else one line per module (`elsewhereLines`).
fn printElsewhere(io: std.Io, printing: bool) void {
    const stderr = std.Io.File.stderr();
    if (printing) {
        tallyText(state.elsewhere.text.items);
        stderr.writeStreamingAll(io, state.elsewhere.text.items) catch return;
        return;
    }
    const lines = elsewhereLines(io) catch return;
    defer state.allocator.free(lines);
    stderr.writeStreamingAll(io, lines) catch return;
}

/// The lines that stand for the warnings `check FILE` left out, one per module in the order of their paths: the module as its warnings
/// print it, how many, and the check that lists them, with the module's path from the working directory.
fn elsewhereLines(io: std.Io) std.mem.Allocator.Error![]u8 {
    const a = state.allocator;
    const counts = state.elsewhere.counts;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    const order = try a.alloc(usize, counts.count());
    defer a.free(order);
    for (order, 0..) |*slot, index| slot.* = index;
    std.mem.sort(usize, order, counts, struct {
        fn before(known: std.array_hash_map.String(usize), left: usize, right: usize) bool {
            return std.mem.lessThan(u8, known.keys()[left], known.keys()[right]);
        }
    }.before);
    for (order) |index| {
        const shown = counts.keys()[index];
        const absolute = try locate(io, shown);
        const command = if (absolute) |found| try std.fs.path.relative(a, state.elsewhere.cwd, null, state.elsewhere.cwd, found) else shown;
        try out.appendSlice(a, try moduleLine(a, shown, command, counts.values()[index]));
    }
    return out.toOwnedSlice(a);
}

/// The line for the `total` warnings `check FILE` left out of the module its warnings print as `shown`, which `selka check path`
/// lists from the working directory.
fn moduleLine(a: std.mem.Allocator, shown: []const u8, path: []const u8, total: usize) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(a, "{s}: {d} warning{s}; `selka check {s}`\n", .{ shown, total, if (total == 1) "" else "s", path });
}

/// The namespaces of the locked packages whose warnings this command leaves out (`packages_option`), for a directory run to give
/// each child root; null when there are none.
pub fn packageNames() ?[]const u8 {
    const names = state.hidden.names orelse return null;
    return if (names.len == 0) null else names;
}

/// The entry and the lock as the user gave them to the `selka packages` that staged this run (`package_fix_option`), or null.
pub fn packageFix() ?[]const u8 {
    return state.hidden.fix;
}

/// Make the command leave its counts in `file` (`count_option`) instead of closing its report with the `selka fix` line.
pub fn countInto(file: []const u8) void {
    state.count_file = file;
}

/// A child root of a directory run does not close its report: it leaves in the file the run named (`count_option`) its counts, as
/// `reported fixable`, and with `warnings` the warnings it withheld, each as a record (`withhold`), for the run to add to its own
/// (`absorb`). A child that printed and withheld nothing leaves no file.
fn handOver(io: std.Io, warnings: bool) void {
    const left = if (warnings) state.withheld.records.items else "";
    const hidden = if (warnings) state.hidden.records.items else "";
    if (state.reported == 0 and left.len == 0 and hidden.len == 0) return;
    const text = std.fmt.allocPrint(state.allocator, "{d} {d}\n{s}{s}", .{ state.reported, state.fixable, left, hidden }) catch return;
    defer state.allocator.free(text);
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = state.count_file, .data = text }) catch return;
}

/// Add what a child root of this directory run left in its `count_option` file to the command's own, so that the run closes with one
/// line for everything it printed and one for everything it withheld: the two counts of its first line, then the warnings withheld,
/// each counted once however many roots left it. Does nothing for a command that does not count (a JSON report), and for text that is
/// not two numbers. Callable from any worker.
pub fn absorb(io: std.Io, text: []const u8) void {
    lock.lockUncancelable(io);
    defer lock.unlock(io);
    if (!state.counting) return;
    const split = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    var numbers = std.mem.tokenizeScalar(u8, text[0..split], ' ');
    const reported = std.fmt.parseInt(usize, numbers.next() orelse return, 10) catch return;
    const fixable = std.fmt.parseInt(usize, numbers.next() orelse return, 10) catch return;
    state.reported += reported;
    state.fixable += fixable;
    if (!state.active or split >= text.len) return;
    var records = std.mem.splitScalar(u8, text[split + 1 ..], 0);
    while (records.next()) |record| {
        const at = std.mem.indexOfScalar(u8, record, '\n') orelse continue;
        const warning = record[at + 1 ..];
        const found = header(fix_tally.firstLine(warning)) orelse continue;
        // A warning of a locked package a child root left out (`hide`), recorded under `@` and its package's name.
        if (record[0] == '@') {
            hide(record[1..at], warning, found) catch return;
            continue;
        }
        const module = state.allocator.dupe(u8, record[0..at]) catch return;
        withhold(module, warning, found) catch return;
    }
}

/// How many of a command's diagnostics carry a structured fix, by severity.
pub const Repairs = struct { errors: usize, warnings: usize };

/// The closing line that says how many of the `reported` diagnostics `selka fix` repairs: those in `fixable` carry a structured fix.
/// `entry` is the path the command was given, empty when it named none. A directory's `selka fix` repairs both kinds, so the line
/// counts them together. A file's repairs the errors only and `--warnings` adds the warnings', so a line for a file names the
/// command that repairs each kind: the plain one when every repair is an error's, `--warnings` when every one is a warning's,
/// and both counts when there are both.
pub fn fixLine(a: std.mem.Allocator, entry: []const u8, fixable: Repairs, reported: usize) std.mem.Allocator.Error![]u8 {
    const shown = if (entry.len == 0) "." else entry;
    return closingLine(a, "selka fix ", shown, product.isSource(entry), fixable, reported);
}

/// The same line for a run through `selka packages`, naming `selka packages fix` with `given`, the entry and the lock as the user
/// gave them (`ENTRY --lock LOCK`); `file` says whether the entry is a file, whose run repairs the errors only.
pub fn packagesFixLine(a: std.mem.Allocator, given: []const u8, file: bool, fixable: Repairs, reported: usize) std.mem.Allocator.Error![]u8 {
    return closingLine(a, "selka packages fix ", given, file, fixable, reported);
}

fn closingLine(a: std.mem.Allocator, command: []const u8, shown: []const u8, file: bool, fixable: Repairs, reported: usize) std.mem.Allocator.Error![]u8 {
    const all = fixable.errors + fixable.warnings;
    if (!file or fixable.warnings == 0) return std.fmt.allocPrint(a, "`{s}{s}` repairs {d} of these {d}\n", .{ command, shown, all, reported });
    if (fixable.errors == 0) return std.fmt.allocPrint(a, "`{s}{s} --warnings` repairs {d} of these {d}\n", .{ command, shown, all, reported });
    return std.fmt.allocPrint(a, "`{s}{s}` repairs {d} of these {d}, and `{s}{s} --warnings` repairs {d}\n", .{ command, shown, fixable.errors, reported, command, shown, all });
}

/// The lines that stand for the warnings left out of a build through `selka packages`, one for each package, in name order so that
/// they are the same whichever order the roots of a directory run end in: how many, and in which package.
pub fn hiddenLines(a: std.mem.Allocator, counts: std.array_hash_map.String(usize)) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    const order = try a.alloc(usize, counts.count());
    defer a.free(order);
    for (order, 0..) |*slot, index| slot.* = index;
    std.mem.sort(usize, order, counts, struct {
        fn before(known: std.array_hash_map.String(usize), left: usize, right: usize) bool {
            return std.mem.lessThan(u8, known.keys()[left], known.keys()[right]);
        }
    }.before);
    for (order) |index| {
        const total = counts.values()[index];
        const one = total == 1;
        try out.print(a, "{d} warning{s} in package `{s}` {s} not shown\n", .{ total, if (one) "" else "s", counts.keys()[index], if (one) "is" else "are" });
    }
    return out.toOwnedSlice(a);
}

/// Whether `text` (with or without its newline) is a closing line `fixLine` makes, in any of its three shapes. A diagnostic starts
/// with a path, never a backtick, so nothing else matches. `selka fix` uses it to leave out the line of the check it runs, which
/// tells a person to run the command they ran.
pub fn isFixLine(text: []const u8) bool {
    const line = std.mem.trimEnd(u8, text, "\n");
    if (std.mem.indexOfScalar(u8, line, '\n') != null or !std.mem.startsWith(u8, line, "`selka fix ")) return false;
    const repairs = std.mem.indexOf(u8, line, "` repairs ") orelse return false;
    return std.mem.indexOfPos(u8, line, repairs, " of these ") != null;
}

/// The line that stands for the withheld warnings: how many, in how many modules, the most common codes, and the way to the list.
pub fn summary(a: std.mem.Allocator, total: usize, modules: usize, codes: std.array_hash_map.String(usize)) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try out.print(a, "warnings: {d} in {d} unmodified module{s} (", .{ total, modules, if (modules == 1) "" else "s" });
    // The most common codes first, at most five; codes as common as each other in name order, so that the line is the same
    // whichever order the roots of a directory run end in.
    const order = try a.alloc(usize, codes.count());
    defer a.free(order);
    for (order, 0..) |*slot, index| slot.* = index;
    const counts = codes.values();
    std.mem.sort(usize, order, codes, struct {
        fn before(known: std.array_hash_map.String(usize), left: usize, right: usize) bool {
            const values = known.values();
            if (values[left] != values[right]) return values[left] > values[right];
            return std.mem.lessThan(u8, known.keys()[left], known.keys()[right]);
        }
    }.before);
    for (order[0..@min(order.len, 5)], 0..) |index, position| {
        if (position != 0) try out.appendSlice(a, ", ");
        try out.print(a, "{s} {d}", .{ codes.keys()[index], counts[index] });
    }
    if (order.len > 5) try out.appendSlice(a, ", ...");
    try out.appendSlice(a, "); `selka check --warnings` lists them\n");
    return out.toOwnedSlice(a);
}

// A rendered warning is a header line and the indented lines under it.
test "header reads the path and code of a warning line and nothing else" {
    const found = header("eval/env.selka:1750:75: warning[W_RANGE_CHAIN]: two comparisons").?;
    try std.testing.expectEqualStrings("eval/env.selka", found.path);
    try std.testing.expectEqualStrings("1750:75", found.position);
    try std.testing.expectEqualStrings("W_RANGE_CHAIN", found.code);
    try std.testing.expect(header("eval/env.selka:1750:75: error[E_TYPE]: no") == null);
    try std.testing.expect(header("warning[W_X]: no position") == null);
    try std.testing.expect(header("a.selka:x:y: warning[W_X]: letters") == null);
}

test "summary names the count, the modules and the most common codes" {
    var codes: std.array_hash_map.String(usize) = .empty;
    defer codes.deinit(std.testing.allocator);
    try codes.put(std.testing.allocator, "W_B", 2);
    try codes.put(std.testing.allocator, "W_A", 5);
    const line = try summary(std.testing.allocator, 7, 3, codes);
    defer std.testing.allocator.free(line);
    try std.testing.expectEqualStrings("warnings: 7 in 3 unmodified modules (W_A 5, W_B 2); `selka check --warnings` lists them\n", line);
}

test "warnings of unmodified modules are withheld, the others and the errors print" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "committed.selka", .data = "x\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "edited.selka", .data = "y\n" });
    const base = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const committed = try std.fs.path.join(a, &.{ base, "committed.selka" });
    state = .{ .allocator = a, .active = true, .base = base };
    defer state = .{};
    var tree: Tree = .{ .known = true };
    try tree.unmodified.put(a, committed, {});
    state.tree = tree;
    const text =
        "committed.selka:3:5: warning[W_A]: one\n  line\n  ^\n" ++
        "edited.selka:4:1: warning[W_B]: two\n  line\n  ^\n" ++
        "committed.selka:9:1: error[E_C]: three\n  line\n" ++
        "committed.selka:7:2: warning[W_A]: four\n  line\n  ^\n" ++
        "check: ok\n";
    var out: std.ArrayList(u8) = .empty;
    try filtered(std.testing.io, text, &out);
    try std.testing.expectEqualStrings(
        "edited.selka:4:1: warning[W_B]: two\n  line\n  ^\n" ++
            "committed.selka:9:1: error[E_C]: three\n  line\n" ++
            "check: ok\n",
        out.items,
    );
    try std.testing.expectEqual(@as(usize, 2), state.withheld.count);
    try std.testing.expectEqual(@as(usize, 1), state.withheld.modules.count());
    try std.testing.expectEqual(@as(usize, 2), state.withheld.codes.get("W_A").?);
    try std.testing.expect(std.mem.startsWith(u8, state.withheld.text.items, "committed.selka:3:5"));
}

test "check FILE prints the file's own warnings and one line for each other module, unless a format or every warning was asked for" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = "x\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "helper.selka", .data = "y\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "more.selka", .data = "z\n" });
    const base = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const entry = try std.fs.path.joinZ(a, &.{ base, "main.selka" });
    var environment: std.process.Environ.Map = .init(a);
    const line = [_][:0]const u8{ "selka", "check", entry };
    try std.testing.expect((try begin(a, std.testing.io, &environment, &line)).active);
    defer state = .{};
    // No repository holds the files, so the rule of unmodified modules withholds nothing.
    state.tree = .{};
    const text =
        "more.selka:2:1: warning[W_A]: one\n  line\n  ^\n" ++
        "main.selka:4:1: warning[W_B]: two\n  line\n  ^\n" ++
        "helper.selka:9:1: error[E_C]: three\n  line\n" ++
        "helper.selka:7:2: warning[W_A]: four\n  line\n  ^\n" ++
        "helper.selka:8:2: warning[W_B]: five\n  line\n  ^\n" ++
        "helper.selka:8:2: warning[W_B]: five\n  line\n  ^\n" ++
        "check: ok\n";
    var out: std.ArrayList(u8) = .empty;
    try filtered(std.testing.io, text, &out);
    try std.testing.expectEqualStrings(
        "main.selka:4:1: warning[W_B]: two\n  line\n  ^\n" ++
            "helper.selka:9:1: error[E_C]: three\n  line\n" ++
            "check: ok\n",
        out.items,
    );
    // One line per module in the order of their paths, each place and code once, the command's path from the working directory.
    const lines = try elsewhereLines(std.testing.io);
    const helper = try std.fs.path.relative(a, state.elsewhere.cwd, null, state.elsewhere.cwd, try std.fs.path.join(a, &.{ base, "helper.selka" }));
    const more = try std.fs.path.relative(a, state.elsewhere.cwd, null, state.elsewhere.cwd, try std.fs.path.join(a, &.{ base, "more.selka" }));
    const expected = try std.fmt.allocPrint(a, "helper.selka: 2 warnings; `selka check {s}`\nmore.selka: 1 warning; `selka check {s}`\n", .{ helper, more });
    try std.testing.expectEqualStrings(expected, lines);
    // The two printed diagnostics are the ones counted for the closing line.
    try std.testing.expectEqual(@as(usize, 2), state.reported);

    // `--warnings`, a named format (`selka fix` asks for `--diagnostics=text`), JSON and a directory print every warning.
    const listed = [_][:0]const u8{ "selka", "check", entry, "--warnings" };
    _ = try begin(a, std.testing.io, &environment, &listed);
    try std.testing.expectEqualStrings("", state.elsewhere.entry);
    _ = environment.swapRemove(variable);
    const named = [_][:0]const u8{ "selka", "check", entry, "--diagnostics=text" };
    try std.testing.expect((try begin(a, std.testing.io, &environment, &named)).active);
    try std.testing.expectEqualStrings("", state.elsewhere.entry);
    const structured = [_][:0]const u8{ "selka", "check", entry, "--diagnostics", "json" };
    _ = try begin(a, std.testing.io, &environment, &structured);
    try std.testing.expectEqualStrings("", state.elsewhere.entry);
    const directory = [_][:0]const u8{ "selka", "check", try a.dupeSentinel(u8, base, 0) };
    try std.testing.expect((try begin(a, std.testing.io, &environment, &directory)).active);
    try std.testing.expectEqualStrings("", state.elsewhere.entry);
    // Another command that checks a file on the way is not changed.
    const built = [_][:0]const u8{ "selka", "build", entry };
    _ = try begin(a, std.testing.io, &environment, &built);
    try std.testing.expectEqualStrings("", state.elsewhere.entry);
}

test "begin takes --warnings out of the line and turns the policy off for it, json and the environment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    const plain = [_][:0]const u8{ "selka", "check", "nowhere.selka" };
    const quiet = try begin(a, std.testing.io, &environment, &plain);
    try std.testing.expect(quiet.active);
    try std.testing.expectEqual(@as(usize, 3), quiet.args.len);
    const all = [_][:0]const u8{ "selka", "check", "nowhere.selka", "--warnings" };
    const listed = try begin(a, std.testing.io, &environment, &all);
    try std.testing.expect(!listed.active);
    try std.testing.expectEqual(@as(usize, 3), listed.args.len);
    // The processes a directory run starts see the request in their environment.
    try std.testing.expectEqualStrings("all", environment.get(variable).?);
    _ = environment.swapRemove(variable);
    try std.testing.expect((try begin(a, std.testing.io, &environment, &plain)).active);
    const structured = [_][:0]const u8{ "selka", "build", "nowhere.selka", "--diagnostics=json" };
    try std.testing.expect(!(try begin(a, std.testing.io, &environment, &structured)).active);
    const other = [_][:0]const u8{ "selka", "fmt", "nowhere.selka", "--warnings" };
    const untouched = try begin(a, std.testing.io, &environment, &other);
    try std.testing.expect(!untouched.active);
    try std.testing.expectEqual(@as(usize, 4), untouched.args.len);
    try environment.put(variable, "all");
    try std.testing.expect(!(try begin(a, std.testing.io, &environment, &plain)).active);
    state = .{};
}

/// Run `begin` for `command` and filter `text` as that command would print it, with every module treated as the author's.
fn printedBy(a: std.mem.Allocator, command: []const u8, text: []const u8) ![]const u8 {
    var environment: std.process.Environ.Map = .init(a);
    const line = [_][:0]const u8{ "selka", try a.dupeSentinel(u8, command, 0), "nowhere.selka" };
    _ = try begin(a, std.testing.io, &environment, &line);
    var out: std.ArrayList(u8) = .empty;
    try filtered(std.testing.io, text, &out);
    return out.items;
}

test "build, run, run-project and test drop the hints W_COPY_MOVE, W_MATCH_ELSE and W_MATCH_IS unseen, and the check commands print them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    defer state = .{};
    const copy_hint = "m.selka:3:5: warning[W_COPY_MOVE]: `row` is copied\n  line\n  ^\n";
    const match_hints = "m.selka:5:5: warning[W_MATCH_ELSE]: this `match` only unwraps\n  line\n  ^\n" ++
        "m.selka:7:5: warning[W_MATCH_IS]: this `match` only unwraps\n  line\n  ^\n";
    const other = "m.selka:9:1: warning[W_UNUSED_BINDING]: unused\n  line\n  ^\n";
    const text = copy_hint ++ match_hints ++ other ++ "done\n";
    const quiet = other ++ "done\n";
    try std.testing.expectEqualStrings(quiet, try printedBy(a, "build", text));
    // Dropped, not counted: no closing line stands for it.
    try std.testing.expectEqual(@as(usize, 0), state.withheld.count);
    try std.testing.expectEqualStrings(quiet, try printedBy(a, "run", text));
    try std.testing.expectEqualStrings(quiet, try printedBy(a, "run-project", text));
    try std.testing.expectEqualStrings(quiet, try printedBy(a, "test", text));
    try std.testing.expectEqualStrings(text, try printedBy(a, "check", text));
    try std.testing.expectEqualStrings(text, try printedBy(a, "check-project", text));
    try std.testing.expectEqualStrings(text, try printedBy(a, "check-module", text));
    try std.testing.expect(!state.hide_hints);
    // The flag asks for every warning, hints included.
    var environment: std.process.Environ.Map = .init(a);
    const flagged = [_][:0]const u8{ "selka", "build", "nowhere.selka", "--warnings" };
    _ = try begin(a, std.testing.io, &environment, &flagged);
    try std.testing.expect(!state.hide_hints);
}

test "the closing line counts the printed diagnostics that carry a fix, withheld warnings and the others excluded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "committed.selka", .data = "x\n" });
    const base = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const committed = try std.fs.path.join(a, &.{ base, "committed.selka" });
    state = .{ .allocator = a, .active = true, .counting = true, .base = base };
    defer state = .{};
    fix_tally.enable(true);
    defer fix_tally.enable(false);
    var tree: Tree = .{ .known = true };
    try tree.unmodified.put(a, committed, {});
    state.tree = tree;
    fix_tally.note("committed.selka:1:1: warning[W_A]: withheld, fixable\n");
    fix_tally.note("edited.selka:2:1: warning[W_B]: printed, fixable\n");
    fix_tally.note("edited.selka:5:1: error[E_C]: printed, fixable\n");
    const text =
        "committed.selka:1:1: warning[W_A]: withheld, fixable\n  line\n  ^\n" ++
        "edited.selka:2:1: warning[W_B]: printed, fixable\n  line\n  ^\n" ++
        "edited.selka:3:1: warning[W_B]: printed, no fix\n  line\n  ^\n" ++
        "edited.selka:5:1: error[E_C]: printed, fixable\n  line\n" ++
        "edited.selka:6:1: error[E_D]: printed, no fix\n  line\n";
    var out: std.ArrayList(u8) = .empty;
    try filtered(std.testing.io, text, &out);
    try std.testing.expectEqual(@as(usize, 4), state.reported);
    try std.testing.expectEqual(@as(usize, 2), state.fixable);
    try std.testing.expectEqual(@as(usize, 1), state.fixable_errors);
    const line = try fixLine(a, "prog.selka", .{ .errors = state.fixable_errors, .warnings = state.fixable - state.fixable_errors }, state.reported);
    try std.testing.expectEqualStrings("`selka fix prog.selka` repairs 1 of these 4, and `selka fix prog.selka --warnings` repairs 2\n", line);
}

test "a warning in a file of a locked package is counted for the package and not printed, and is in neither number" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    state = .{ .allocator = a, .active = true, .counting = true, .hidden = .{ .names = "rex,other" } };
    defer state = .{};
    fix_tally.enable(true);
    defer fix_tally.enable(false);
    fix_tally.note("main.selka:2:1: warning[W_B]: the program's, fixable\n");
    fix_tally.note("rex/parse.selka:5:8: warning[W_A]: the package's, fixable\n");
    const text =
        "main.selka:2:1: warning[W_B]: the program's, fixable\n  line\n  ^\n" ++
        "rex/parse.selka:5:8: warning[W_A]: the package's, fixable\n  line\n  ^\n" ++
        "rex/ranges.selka:9:1: warning[W_C]: the package's\n  line\n  ^\n" ++
        "rex/ranges.selka:9:1: warning[W_C]: the package's\n  line\n  ^\n" ++
        "rexa.selka:1:1: warning[W_C]: a file named like no package\n  line\n" ++
        "rex.selka:3:1: warning[W_D]: the package's own module file\n  line\n" ++
        "rexx/own.selka:3:1: warning[W_D]: another folder\n  line\n" ++
        "rex/ast.selka:4:2: error[E_C]: an error of the package\n  line\n";
    var out: std.ArrayList(u8) = .empty;
    try filtered(std.testing.io, text, &out);
    // Neither the line nor the source of a package's warning is printed; its error is, and so are files that merely start like its name.
    try std.testing.expectEqualStrings(
        "main.selka:2:1: warning[W_B]: the program's, fixable\n  line\n  ^\n" ++
            "rexa.selka:1:1: warning[W_C]: a file named like no package\n  line\n" ++
            "rexx/own.selka:3:1: warning[W_D]: another folder\n  line\n" ++
            "rex/ast.selka:4:2: error[E_C]: an error of the package\n  line\n",
        out.items,
    );
    // The same place and code of two roots is one warning; the count is of the package.
    try std.testing.expectEqual(@as(usize, 3), state.hidden.counts.get("rex").?);
    try std.testing.expectEqual(@as(usize, 4), state.reported);
    // What was printed is what is counted: the package's two fixable warnings are in neither number.
    try std.testing.expectEqual(@as(usize, 1), state.fixable);
}

test "the lines for the warnings left out name each package in order and agree in number" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var counts: std.array_hash_map.String(usize) = .empty;
    try counts.put(a, "rex", 2);
    try counts.put(a, "base", 1);
    const lines = try hiddenLines(a, counts);
    try std.testing.expectEqualStrings("1 warning in package `base` is not shown\n2 warnings in package `rex` are not shown\n", lines);
}

test "begin takes the internal option of a build through selka packages out of the line, and only for a covered command" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    defer state = .{};
    const line = [_][:0]const u8{ "selka", "check-project", "/stage/main.selka", packages_option, "rex,other", "--", packages_option, "x" };
    const selection = try begin(a, std.testing.io, &environment, &line);
    // The options before `--` are the display's; the words after it are the command's and stay.
    try std.testing.expectEqual(@as(usize, 6), selection.args.len);
    try std.testing.expectEqualStrings("/stage/main.selka", selection.args[2]);
    try std.testing.expectEqualStrings("--", selection.args[3]);
    try std.testing.expectEqualStrings("rex,other", packageNames().?);
    // A lock with no package still marks the run, so that it prints no `selka fix` line, and hides nothing.
    const bare = [_][:0]const u8{ "selka", "check-project", "/stage/main.selka", packages_option, "" };
    _ = try begin(a, std.testing.io, &environment, &bare);
    try std.testing.expect(state.hidden.names != null and packageNames() == null and packageOf("rex/parse.selka") == null);
    // `--warnings` lists every warning, the packages' included.
    const listed = [_][:0]const u8{ "selka", "check-project", "/stage/main.selka", packages_option, "rex", "--warnings" };
    try std.testing.expect(!(try begin(a, std.testing.io, &environment, &listed)).active);
    // The words of the `selka packages fix` the closing line names are taken out too, and kept for that line.
    const advised = [_][:0]const u8{ "selka", "check-project", "/stage/main.selka", packages_option, "rex", package_fix_option, "main.selka --lock lock.json" };
    try std.testing.expectEqual(@as(usize, 3), (try begin(a, std.testing.io, &environment, &advised)).args.len);
    try std.testing.expectEqualStrings("main.selka --lock lock.json", state.hidden.fix.?);
    // A command the policy does not cover keeps its line whole.
    const index = [_][:0]const u8{ "selka", "index-project", "/stage/main.selka", packages_option, "rex" };
    try std.testing.expectEqual(@as(usize, 5), (try begin(a, std.testing.io, &environment, &index)).args.len);
    try std.testing.expect(packageNames() == null);
    // `api` prints no warning but is told the packages, so that it asks no interface file of their modules and names the right command.
    const interfaces = [_][:0]const u8{ "selka", "api", "/stage/main.selka", packages_option, "rex", package_fix_option, "main.selka --lock lock.json", "--write" };
    const taken = try begin(a, std.testing.io, &environment, &interfaces);
    try std.testing.expectEqual(@as(usize, 4), taken.args.len);
    try std.testing.expectEqualStrings("--write", taken.args[3]);
    try std.testing.expectEqualStrings("rex", packageNames().?);
    try std.testing.expectEqualStrings("main.selka --lock lock.json", packageFix().?);
}

test "a child root of a directory run hands the warnings it left out to the run, which counts each place once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    defer state = .{};
    state = .{ .allocator = a, .active = true, .counting = true, .hidden = .{ .names = "rex" } };
    const warning = "rex/parse.selka:5:8: warning[W_A]: the package's\n  line\n";
    try hide("rex", warning, header(fix_tally.firstLine(warning)).?);
    const record = state.hidden.records.items;
    try std.testing.expectEqualStrings("@rex\n" ++ warning ++ "\x00", record);
    // The run starts clean, adds a child's counts and the record twice (two children that import the package): one warning.
    const handed = try std.fmt.allocPrint(a, "1 0\n{s}", .{record});
    state = .{ .allocator = a, .active = true, .counting = true };
    absorb(std.testing.io, handed);
    absorb(std.testing.io, handed);
    try std.testing.expectEqual(@as(usize, 2), state.reported);
    try std.testing.expectEqual(@as(usize, 1), state.hidden.counts.get("rex").?);
}

test "the closing line names the command that repairs each kind for a file, and counts both together for a directory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Every repair is an error's: the plain command, as it has always read.
    try std.testing.expectEqualStrings("`selka fix a.selka` repairs 2 of these 9\n", try fixLine(a, "a.selka", .{ .errors = 2, .warnings = 0 }, 9));
    // Every repair is a warning's: the file's plain command repairs none of them, so the line names `--warnings`.
    try std.testing.expectEqualStrings("`selka fix a.selka --warnings` repairs 3 of these 9\n", try fixLine(a, "a.selka", .{ .errors = 0, .warnings = 3 }, 9));
    // A run through `selka packages` names `selka packages fix` with the entry and the lock as given.
    try std.testing.expectEqualStrings(
        "`selka packages fix main.selka --lock lock.json --warnings` repairs 3 of these 3\n",
        try packagesFixLine(a, "main.selka --lock lock.json", true, .{ .errors = 0, .warnings = 3 }, 3),
    );
    try std.testing.expectEqualStrings("`selka packages fix app --lock l.json` repairs 3 of these 4\n", try packagesFixLine(a, "app --lock l.json", false, .{ .errors = 1, .warnings = 2 }, 4));
    // Both: each command with its count, the second counting the errors too.
    try std.testing.expectEqualStrings(
        "`selka fix a.selka` repairs 2 of these 9, and `selka fix a.selka --warnings` repairs 5\n",
        try fixLine(a, "a.selka", .{ .errors = 2, .warnings = 3 }, 9),
    );
    // A directory (or no path) repairs both kinds together: one count, the line unchanged.
    try std.testing.expectEqualStrings("`selka fix src` repairs 5 of these 9\n", try fixLine(a, "src", .{ .errors = 2, .warnings = 3 }, 9));
    try std.testing.expectEqualStrings("`selka fix .` repairs 3 of these 9\n", try fixLine(a, "", .{ .errors = 0, .warnings = 3 }, 9));
}

test "isFixLine recognises each shape fixLine makes and nothing a check prints besides" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expect(isFixLine(try fixLine(a, "a.selka", .{ .errors = 2, .warnings = 0 }, 9)));
    try std.testing.expect(isFixLine(try fixLine(a, "/work/a.selka", .{ .errors = 0, .warnings = 3 }, 9)));
    try std.testing.expect(isFixLine(try fixLine(a, "a.selka", .{ .errors = 2, .warnings = 3 }, 9)));
    try std.testing.expect(isFixLine(try fixLine(a, "", .{ .errors = 1, .warnings = 1 }, 9)));
    try std.testing.expect(isFixLine("`selka fix src` repairs 5 of these 9"));
    try std.testing.expect(!isFixLine("a.selka:1:8: warning[W_UNUSED_IMPORT]: import `strings` is never referenced\n"));
    try std.testing.expect(!isFixLine("fix: left 2 warnings with a repair alone; `selka fix a.selka --warnings` repairs them too\n"));
    try std.testing.expect(!isFixLine("`selka fix a.selka` repairs 2 of these 9\n  indented\n"));
}

test "begin counts the diagnostics a text command prints and none of a json one or of a command the policy does not cover" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    defer state = .{};
    defer fix_tally.enable(false);
    var environment: std.process.Environ.Map = .init(a);
    const text = [_][:0]const u8{ "selka", "check", "nowhere.selka" };
    _ = try begin(a, std.testing.io, &environment, &text);
    try std.testing.expect(state.counting);
    const listed = [_][:0]const u8{ "selka", "check", "nowhere.selka", "--warnings" };
    _ = try begin(a, std.testing.io, &environment, &listed);
    try std.testing.expect(state.counting);
    try std.testing.expect(!state.active);
    const structured = [_][:0]const u8{ "selka", "check", "nowhere.selka", "--diagnostics=json" };
    _ = try begin(a, std.testing.io, &environment, &structured);
    try std.testing.expect(!state.counting);
    const other = [_][:0]const u8{ "selka", "fmt", "nowhere.selka" };
    _ = try begin(a, std.testing.io, &environment, &other);
    try std.testing.expect(!state.counting);
}

test "a child root of a directory run hands its counts over, and the run closes once with the sums" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const base = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer state = .{};
    // A child root that printed three diagnostics, two with a fix, leaves them in the file the run named and prints no line.
    state = .{ .allocator = a, .counting = true, .reported = 3, .fixable = 2 };
    countInto(try std.fs.path.join(a, &.{ base, "0.fixes" }));
    handOver(std.testing.io, true);
    const handed = try temporary.dir.readFileAlloc(std.testing.io, "0.fixes", a, .limited(64));
    try std.testing.expectEqualStrings("3 2\n", handed);
    // One that printed nothing leaves nothing.
    state = .{ .allocator = a, .counting = true, .count_file = try std.fs.path.join(a, &.{ base, "1.fixes" }) };
    handOver(std.testing.io, true);
    try std.testing.expectError(error.FileNotFound, temporary.dir.access(std.testing.io, "1.fixes", .{}));
    // The run adds what its roots handed over to what it printed itself, and ignores text that is not two numbers.
    state = .{ .allocator = a, .counting = true, .entry = "tests", .reported = 1, .fixable = 1 };
    absorb(std.testing.io, handed);
    absorb(std.testing.io, "1 0\n");
    absorb(std.testing.io, "garbage");
    absorb(std.testing.io, "7");
    const line = try fixLine(a, state.entry, .{ .errors = 0, .warnings = state.fixable }, state.reported);
    try std.testing.expectEqualStrings("`selka fix tests` repairs 3 of these 5\n", line);
    // A run that does not count (a JSON report) takes none.
    state = .{ .allocator = a };
    absorb(std.testing.io, handed);
    try std.testing.expectEqual(@as(usize, 0), state.reported);
}

/// A child root of a directory run over `base`, whose `committed.selka` git tracks unmodified, that printed `text`: the file it leaves for the
/// run, or an empty text when it leaves none.
fn childLeaves(a: std.mem.Allocator, directory: std.Io.Dir, base: []const u8, name: []const u8, text: []const u8, denied: bool) ![]const u8 {
    const committed = try std.fs.path.join(a, &.{ base, "committed.selka" });
    const file = try std.fmt.allocPrint(a, "{s}.fixes", .{name});
    state = .{ .allocator = a, .active = true, .counting = true, .base = base, .denied = denied };
    state.count_file = try std.fs.path.join(a, &.{ base, file });
    var tree: Tree = .{ .known = true };
    try tree.unmodified.put(a, committed, {});
    state.tree = tree;
    var out: std.ArrayList(u8) = .empty;
    try filtered(std.testing.io, text, &out);
    // A child that fails in a project that denies warnings prints what it withheld itself, and leaves none of it.
    handOver(std.testing.io, !denied);
    return directory.readFileAlloc(std.testing.io, file, a, .limited(4096)) catch "";
}

test "the warnings a child root withheld ride in its hand-over file, and the run counts each place and code once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "committed.selka", .data = "x\n" });
    const base = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer state = .{};
    const first = "committed.selka:1:1: warning[W_A]: one\n  line\n  ^\n" ++ "committed.selka:2:1: warning[W_B]: two\n  line\n";
    const second = "committed.selka:1:1: warning[W_A]: one\n  line\n  ^\n" ++ "committed.selka:3:1: warning[W_A]: three\n  line\n";
    const left_first = try childLeaves(a, temporary.dir, base, "0", first, false);
    const left_second = try childLeaves(a, temporary.dir, base, "1", second, false);
    // A child that prints nothing leaves nothing; one that fails in a project that denies warnings printed its own and leaves none.
    try std.testing.expectEqualStrings("", try childLeaves(a, temporary.dir, base, "2", "plain text\n", false));
    try std.testing.expectEqualStrings("", try childLeaves(a, temporary.dir, base, "3", first, true));
    // The file holds the two counts, then each warning as its module's absolute path, a line and its text, ended by a zero byte.
    const record = try std.fmt.allocPrint(a, "{s}/committed.selka\ncommitted.selka:1:1: warning[W_A]: one\n  line\n  ^\n\x00", .{base});
    try std.testing.expect(std.mem.startsWith(u8, left_first, "0 0\n"));
    try std.testing.expect(std.mem.indexOf(u8, left_first, record) != null);
    // The run withheld the second warning of the first child itself; the children leave it again, with the places they share.
    const committed = try std.fs.path.join(a, &.{ base, "committed.selka" });
    state = .{ .allocator = a, .active = true, .counting = true, .base = base, .entry = "tests" };
    var tree: Tree = .{ .known = true };
    try tree.unmodified.put(a, committed, {});
    state.tree = tree;
    var out: std.ArrayList(u8) = .empty;
    try filtered(std.testing.io, "committed.selka:2:1: warning[W_B]: two\n  line\n", &out);
    absorb(std.testing.io, left_first);
    absorb(std.testing.io, left_second);
    absorb(std.testing.io, left_second);
    absorb(std.testing.io, "0 0\nno newline, no module\x00another\n");
    try std.testing.expectEqual(@as(usize, 3), state.withheld.count);
    try std.testing.expectEqual(@as(u32, 1), state.withheld.modules.count());
    const line = try summary(a, state.withheld.count, state.withheld.modules.count(), state.withheld.codes);
    try std.testing.expectEqualStrings("warnings: 3 in 1 unmodified module (W_A 2, W_B 1); `selka check --warnings` lists them\n", line);
    // The text kept for a project that denies warnings holds each once, in the order they came.
    try std.testing.expectEqualStrings("committed.selka:2:1: warning[W_B]: two\n  line\ncommitted.selka:1:1: warning[W_A]: one\n  line\n  ^\ncommitted.selka:3:1: warning[W_A]: three\n  line\n", state.withheld.text.items);
    // Codes as common as each other come in name order, whichever order they were counted in.
    var codes: std.array_hash_map.String(usize) = .empty;
    try codes.put(a, "W_Z", 2);
    try codes.put(a, "W_M", 2);
    try std.testing.expectEqualStrings("warnings: 4 in 1 unmodified module (W_M 2, W_Z 2); `selka check --warnings` lists them\n", try summary(a, 4, 1, codes));
}
