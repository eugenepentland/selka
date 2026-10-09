//! `selka doctest [<repo-root>] [--filter GLOB] [--report PATH] [--jobs N]
//! [--verbose]`: run every fenced `selka` documentation example through this
//! compiler.
//!
//! This is the Zig replacement for the old Python `tests/docs_examples.py`
//! runner. It walks `README.md`, `SPEC.md` and `docs/**/*.md` (excluding
//! `docs/legacy/`), lifts out fenced blocks, applies the leading `# doc:`
//! directives described in `docs/experiments/doc-examples.md`, materialises
//! each example (or grouped project) into a private temporary directory, and
//! invokes this same executable for `check`, `run`, `check-project` or
//! `run-project` with `--diagnostics=json`. It reports per-document tallies,
//! mis-tagged prose fences and failures, and exits non-zero when any example
//! failed, any prose fence still looks like guest source, or no executable
//! block was found. Units are independent, so they run on a bounded pool of
//! workers sized the way `selka test <dir>` sizes its fan-out.
const source_names = @import("compiler_root").compiler_language.source_names;
const std = @import("std");
const budget = @import("memory_budget");

/// Fence info strings whose blocks are executable examples.
const executable_tags = [_][]const u8{"selka"};
/// Fence info strings treated as prose for the mis-tag lint.
const prose_tags = [_][]const u8{ "", "text", "rust", "python", "go" };
/// Directives the runner understands; an unknown name fails its block.
const known_directives = [_][]const u8{
    "expect",       "expect-error", "check",      "project",     "file",
    "skip",         not_selka,      "allow-read", "allow-write", value_semantics,
    legacy_sharing, gc_runtime,
};
/// Directive that checks and runs its unit under `--value-semantics`
/// (`VALUE-SEMANTICS-8`); unmarked units use the default value model.
const value_semantics = "value-semantics";
/// One-release opt-out for examples documenting legacy sharing.
const legacy_sharing = "legacy-sharing";
/// Directive that checks and runs its unit under the tracing collector
/// (`--gc-runtime`), for examples documenting the GC opt-out (`RC-DEFAULT-1`).
const gc_runtime = "gc-runtime";
/// Why a unit documenting legacy sharing or the collector is skipped.
const retired_mode = "documents a mode the new core retired (S5-D4)";
/// Neutral entry point appended to declaration-only examples before checking.
const stub = "func main() -> int:\n    return 0\n";
/// Most bytes the runner reads from one documentation page.
const read_limit: std.Io.Limit = .limited(8 * 1024 * 1024);
/// Seconds one compiler invocation may run before the unit is failed.
const timeout_seconds: i64 = 120;
/// Documentation subtree whose examples are deliberately not executed.
const legacy_prefix = "docs/legacy/";
/// `--filter` option prefix, shared by its spaced and `=` spellings.
const filter_prefix = "--filter=";
/// `--report` option prefix, shared by its spaced and `=` spellings.
const report_prefix = "--report=";
/// `--jobs` option prefix, shared by its spaced and `=` spellings.
const jobs_prefix = "--jobs=";
/// Directive and message spelling that exempts a fence from the mis-tag lint.
const not_selka = "not-selka";
/// JSON key for the mis-tag tally.
const mistagged_key = "mistagged";

/// Usage and directive summary for `selka doctest --help` and bad arguments.
const usage =
    "usage: selka doctest [<repo-root>] [--filter GLOB] [--report PATH] [--jobs N] [--verbose]\n" ++
    "  Runs every fenced ```selka example in README.md, SPEC.md and\n" ++
    "  docs/**/*.md (except docs/legacy/) through this compiler. Leading `# doc:`\n" ++
    "  directives pin expected output, expected diagnostic codes, projects, files,\n" ++
    "  skips, capability grants and value semantics. --filter GLOB limits the scan to matching\n" ++
    "  repository-relative pages, --report PATH writes a doc-examples-v1 JSON\n" ++
    "  report, and --verbose prints each command and diagnostic. --jobs N bounds the\n" ++
    "  worker pool, which otherwise follows cores and free memory. Exits 1 when any\n" ++
    "  example fails, a prose fence looks like guest source, or no executable\n" ++
    "  example was found.\n";

/// Run the documentation example gate, returning the process exit status.
pub fn run(process: std.process.Init, args: []const []const u8) u8 {
    return runCommand(process, args) catch |err| {
        var buffer: [192]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "selka doctest: {s}\n", .{@errorName(err)}) catch "selka doctest: host failure\n";
        std.Io.File.stderr().writeStreamingAll(process.io, message) catch return 2;
        return 2;
    };
}

/// One leading `# doc:` directive, split into its name and its argument text.
const Directive = struct { name: []const u8, rest: []const u8 };

/// One fenced code block lifted out of a documentation page.
const Fence = struct {
    document: []const u8,
    label: []const u8,
    tag: []const u8,
    notest: bool,
    source: []const u8,
    directives: []const Directive,
    error_message: ?[]const u8,
};

/// Whether a unit is one standalone block or a group of project files.
const UnitKind = enum { block, project };

/// Outcome of one executed unit.
const Status = enum { pending, run, checked, skipped, failed };

/// One executable example: a single block or a grouped multi-file project.
const Unit = struct {
    kind: UnitKind,
    label: []const u8,
    document: []const u8,
    members: std.ArrayList(*const Fence),
    status: Status = .pending,
    detail: []const u8 = "",
    command: []const []const u8 = &.{},
};

/// How a unit should be exercised, or why it cannot be.
const Action = enum { invalid, skip, expect_error, check, run };

/// A unit's decided plan, with the expected text and diagnostic codes it carries.
const Plan = struct {
    action: Action,
    detail: []const u8 = "",
    codes: []const []const u8 = &.{},
    expect: []const []const u8 = &.{},
};

/// Per-document tallies printed in the summary and stored in the report.
const Counts = struct {
    blocks: usize = 0,
    run: usize = 0,
    checked: usize = 0,
    skipped: usize = 0,
    mistagged: usize = 0,
    failed: usize = 0,
    skips: std.ArrayList([]const u8) = .empty,
};

/// Aggregate tallies over every scanned document.
const Totals = struct {
    run: usize = 0,
    checked: usize = 0,
    skipped: usize = 0,
    mistagged: usize = 0,
    failed: usize = 0,
};

/// Everything one scan found: the documents, the executable fences and the
/// prose fences that still look like guest source.
const Scan = struct {
    documents: std.ArrayList([]const u8) = .empty,
    executable: std.ArrayList(*const Fence) = .empty,
    suspects: std.ArrayList(*const Fence) = .empty,
    counts: std.StringHashMapUnmanaged(usize) = .empty,
};

/// Command-line options after parsing.
const Options = struct {
    root: []const u8 = ".",
    filter: ?[]const u8 = null,
    report: ?[]const u8 = null,
    jobs: ?usize = null,
    verbose: bool = false,
};

/// Runtime context one unit needs to be executed. Copied into every worker, so
/// the lock it carries is the one standard-output stream they share.
const Session = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    verbose: bool,
    compiler: []const u8,
    fixtures: []const u8,
    output: *std.Io.Mutex,
};

/// Parse the subcommand arguments, rejecting unknown options and extra roots.
fn parseOptions(args: []const []const u8) error{Usage}!Options {
    var options: Options = .{};
    var root_seen = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--verbose")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "--filter")) {
            if (options.filter != null or index + 1 >= args.len) return error.Usage;
            index += 1;
            options.filter = args[index];
        } else if (std.mem.startsWith(u8, arg, filter_prefix)) {
            if (options.filter != null or arg.len == filter_prefix.len) return error.Usage;
            options.filter = arg[filter_prefix.len..];
        } else if (std.mem.eql(u8, arg, "--report")) {
            if (options.report != null or index + 1 >= args.len) return error.Usage;
            index += 1;
            options.report = args[index];
        } else if (std.mem.startsWith(u8, arg, report_prefix)) {
            if (options.report != null or arg.len == report_prefix.len) return error.Usage;
            options.report = arg[report_prefix.len..];
        } else if (std.mem.eql(u8, arg, "--jobs")) {
            if (options.jobs != null or index + 1 >= args.len) return error.Usage;
            index += 1;
            options.jobs = budget.jobs(args[index]) catch return error.Usage;
        } else if (std.mem.startsWith(u8, arg, jobs_prefix)) {
            if (options.jobs != null) return error.Usage;
            options.jobs = budget.jobs(arg[jobs_prefix.len..]) catch return error.Usage;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return error.Usage;
        } else if (root_seen) {
            return error.Usage;
        } else {
            options.root = arg;
            root_seen = true;
        }
    }
    return options;
}

/// The pool width asked for: `--jobs` first, then `SELKA_JOBS`, then none,
/// which leaves the default derived from cores and free memory. Malformed text
/// is a usage error here exactly as it is for `selka test`.
fn resolveJobs(flag: ?usize, environ: *const std.process.Environ.Map) budget.Error!?usize {
    if (flag) |value| return value;
    const text = environ.get(budget.jobs_variable) orelse return null;
    if (text.len == 0) return null;
    const value = try budget.jobs(text);
    return value;
}

/// Workers the unit pool keeps busy: the requested width when there is one,
/// otherwise the machine's cores capped by how many per-child ceilings its free
/// memory holds — the same rule and the same ceiling `selka test <dir>` fans
/// out under, so a doctest run cannot outweigh a guest test run.
fn width(io: std.Io, requested: ?usize, units: usize) usize {
    return budget.workers(.{
        .jobs = requested,
        .programs = units,
        .cores = std.Thread.getCpuCount() catch 1,
        .free = budget.available(io),
        .ceiling = budget.test_default,
    });
}

/// Run the whole command after the `--help` shortcut has been handled.
fn runCommand(process: std.process.Init, args: []const []const u8) !u8 {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try writeOut(process.io, usage);
            return 0;
        }
    }
    const options = parseOptions(args) catch {
        try writeErr(process.io, usage);
        return 2;
    };
    const allocator = process.arena.allocator();
    const root = std.Io.Dir.cwd().realPathFileAlloc(process.io, options.root, allocator) catch {
        try writeErr(process.io, "selka doctest: repository root does not exist\n");
        return 2;
    };
    const compiler = std.process.executablePathAlloc(process.io, allocator) catch {
        try writeErr(process.io, "selka doctest: cannot locate this executable\n");
        return 2;
    };
    const fixtures = try std.fs.path.resolve(allocator, &.{ root, "docs", "fixtures" });
    var scan = Scan{};
    try scanFences(allocator, process.io, root, options.filter, &scan);
    const blocks = try scan.executable.toOwnedSlice(allocator);
    const suspects = try scan.suspects.toOwnedSlice(allocator);
    const units = try group(allocator, blocks);
    const requested = resolveJobs(options.jobs, process.environ_map) catch {
        try writeErr(process.io, usage);
        return 2;
    };
    const workspace = try makeWorkspace(allocator, process.io, workspaceRoot(process.environ_map));
    defer removeTree(process.io, workspace);
    var output: std.Io.Mutex = .init;
    const session: Session = .{ .allocator = allocator, .io = process.io, .verbose = options.verbose, .compiler = compiler, .fixtures = fixtures, .output = &output };
    try runUnits(session, units, workspace, width(process.io, requested, units.len));
    var table: std.StringHashMapUnmanaged(Counts) = .empty;
    try tabulate(allocator, units, suspects, scan.counts, &table);
    var out: std.ArrayList(u8) = .empty;
    const totals = try report(allocator, &out, &table, units, suspects);
    try writeOut(process.io, out.items);
    const executable_units = totals.run + totals.checked + totals.skipped + totals.failed;
    if (executable_units == 0) {
        try writeErr(process.io, "Doc examples: no executable blocks found; the extractor or the filter is wrong\n");
    }
    if (options.report) |path| try writeReport(.{ .process = process, .allocator = allocator, .path = path, .table = &table, .units = units, .suspects = suspects, .totals = totals });
    return if (executable_units != 0 and totals.failed == 0 and totals.mistagged == 0) 0 else 1;
}

fn removeTree(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteTree(io, path) catch return;
}

fn writeOut(io: std.Io, bytes: []const u8) !void {
    try std.Io.File.stdout().writeStreamingAll(io, bytes);
}

fn writeErr(io: std.Io, bytes: []const u8) !void {
    try std.Io.File.stderr().writeStreamingAll(io, bytes);
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn eql(left: []const u8, right: []const u8) bool {
    return std.mem.eql(u8, left, right);
}

fn contains(list: []const []const u8, value: []const u8) bool {
    for (list) |item| if (eql(item, value)) return true;
    return false;
}

/// Append every selected documentation page, README and SPEC first, in order.
fn collectDocuments(allocator: std.mem.Allocator, io: std.Io, root: []const u8, filter: ?[]const u8, out: *std.ArrayList([]const u8)) !void {
    try addDocument(allocator, io, root, filter, "README.md", out);
    try addDocument(allocator, io, root, filter, "SPEC.md", out);
    const first_doc = out.items.len;
    const docs_root = try std.fs.path.join(allocator, &.{ root, "docs" });
    var directory = std.Io.Dir.cwd().openDir(io, docs_root, .{ .iterate = true, .follow_symlinks = false }) catch return;
    defer directory.close(io);
    var walker = try directory.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |item| {
        if (item.kind != .file or !std.mem.endsWith(u8, item.path, ".md")) continue;
        const relative = try std.fmt.allocPrint(allocator, "docs/{s}", .{item.path});
        if (std.mem.startsWith(u8, relative, legacy_prefix)) continue;
        if (filter) |pattern| if (!globMatches(pattern, relative)) continue;
        try out.append(allocator, relative);
    }
    std.mem.sort([]const u8, out.items[first_doc..], {}, lessThan);
}

fn addDocument(allocator: std.mem.Allocator, io: std.Io, root: []const u8, filter: ?[]const u8, relative: []const u8, out: *std.ArrayList([]const u8)) !void {
    if (filter) |pattern| if (!globMatches(pattern, relative)) return;
    const path = try std.fs.path.join(allocator, &.{ root, relative });
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return;
    if (stat.kind != .file) return;
    try out.append(allocator, relative);
}

/// Anchored shell-style glob matching for `--filter`: `*`, `?` and `[...]`.
fn globMatches(pattern: []const u8, text: []const u8) bool {
    if (std.mem.indexOfAny(u8, pattern, "*?[") == null) return eql(pattern, text);
    var p: usize = 0;
    var t: usize = 0;
    var star: ?usize = null;
    var retry: usize = 0;
    while (t < text.len) {
        if (p < pattern.len and pattern[p] == '*') {
            p += 1;
            star = p;
            retry = t;
            continue;
        }
        if (p < pattern.len and globToken(pattern, &p, text[t])) {
            t += 1;
            continue;
        }
        if (star) |restart| {
            retry += 1;
            t = retry;
            p = restart;
        } else return false;
    }
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}

fn globToken(pattern: []const u8, index: *usize, character: u8) bool {
    if (pattern[index.*] == '?') {
        index.* += 1;
        return true;
    }
    if (pattern[index.*] == '[') {
        const negated = index.* + 1 < pattern.len and pattern[index.* + 1] == '!';
        var scan = if (negated) index.* + 2 else index.* + 1;
        if (scan < pattern.len and pattern[scan] == ']') scan += 1;
        const close = std.mem.indexOfScalarPos(u8, pattern, scan, ']') orelse return false;
        const matched = bracketContains(pattern[scan..close], character);
        if (matched == negated) return false;
        index.* = close + 1;
        return true;
    }
    const literal = pattern[index.*];
    index.* += 1;
    return literal == character;
}

// twin-drift-ok: doctest --filter matches repository-relative ASCII paths, so
// this byte-wise bracket matcher deliberately diverges from native_test_cases'
// UTF-8 `classContains`; the shared shape is the shell-glob bracket grammar.
fn bracketContains(pattern: []const u8, character: u8) bool {
    var i: usize = 0;
    while (i < pattern.len) {
        const low = pattern[i];
        i += 1;
        if (i + 1 < pattern.len and pattern[i] == '-') {
            i += 1;
            const high = pattern[i];
            i += 1;
            if (character >= low and character <= high) return true;
        } else if (character == low) return true;
    }
    return false;
}

/// Read every selected page, extract its fences and classify them.
fn scanFences(allocator: std.mem.Allocator, io: std.Io, root: []const u8, filter: ?[]const u8, scan: *Scan) !void {
    try collectDocuments(allocator, io, root, filter, &scan.documents);
    for (scan.documents.items) |document| {
        const path = try std.fs.path.join(allocator, &.{ root, document });
        const text = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, read_limit);
        const found = try fences(allocator, document, text);
        try scan.counts.put(allocator, document, found.len);
        for (found) |*fence| {
            if (isExecutable(fence)) {
                try scan.executable.append(allocator, fence);
            } else if (mistagged(fence)) {
                try scan.suspects.append(allocator, fence);
            }
        }
    }
}

fn isExecutable(fence: *const Fence) bool {
    return contains(&executable_tags, fence.tag) and !fence.notest;
}

fn mistagged(fence: *const Fence) bool {
    if (fence.notest or hasDirective(fence, not_selka)) return false;
    return contains(&prose_tags, fence.tag) and guestShape(fence.source);
}

/// One fence opener: its indentation, tick run and trailing info string.
const Opener = struct { indent: usize, ticks: []const u8, info: []const u8 };

fn opener(line: []const u8) ?Opener {
    var i: usize = 0;
    while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
    const indent = i;
    if (i >= line.len or (line[i] != '`' and line[i] != '~')) return null;
    const start = i;
    const tick = line[i];
    while (i < line.len and line[i] == tick) i += 1;
    if (i - start < 3) return null;
    return .{ .indent = indent, .ticks = line[start..i], .info = line[i..] };
}

fn isCloser(line: []const u8, tick: u8, minimum: usize) bool {
    var i: usize = 0;
    while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
    const start = i;
    while (i < line.len and line[i] == tick) i += 1;
    if (i - start < minimum) return false;
    while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
    return i == line.len;
}

/// Extract every fenced block from one page, stripping its leading directives.
fn fences(allocator: std.mem.Allocator, document: []const u8, text: []const u8) ![]Fence {
    var found: std.ArrayList(Fence) = .empty;
    var lines: std.ArrayList([]const u8) = .empty;
    var split = std.mem.splitScalar(u8, text, '\n');
    while (split.next()) |raw| {
        const line = if (raw.len > 0 and raw[raw.len - 1] == '\r') raw[0 .. raw.len - 1] else raw;
        try lines.append(allocator, line);
    }
    var index: usize = 0;
    while (index < lines.items.len) {
        const opened = opener(lines.items[index]) orelse {
            index += 1;
            continue;
        };
        const start = index;
        var body: std.ArrayList([]const u8) = .empty;
        index += 1;
        while (index < lines.items.len and !isCloser(lines.items[index], opened.ticks[0], opened.ticks.len)) {
            const line = lines.items[index];
            const indent = lines.items[start][0..opened.indent];
            if (std.mem.startsWith(u8, line, indent)) {
                try body.append(allocator, line[opened.indent..]);
            } else {
                try body.append(allocator, line);
            }
            index += 1;
        }
        if (index < lines.items.len) index += 1;
        const body_text = try joinLines(allocator, body.items);
        const info = std.mem.trim(u8, opened.info, " \t\r");
        var fields = std.mem.tokenizeAny(u8, info, " \t");
        const tag = fields.next() orelse "";
        var notest = false;
        while (fields.next()) |flag| {
            if (eql(flag, "notest")) notest = true;
        }
        var directives: std.ArrayList(Directive) = .empty;
        var error_message: ?[]const u8 = null;
        const source = try stripDirectives(allocator, body_text, &directives, &error_message);
        const label = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ document, start + 1 });
        try found.append(allocator, .{
            .document = document,
            .label = label,
            .tag = tag,
            .notest = notest,
            .source = source,
            .directives = try directives.toOwnedSlice(allocator),
            .error_message = error_message,
        });
    }
    return found.toOwnedSlice(allocator);
}

fn joinLines(allocator: std.mem.Allocator, lines: []const []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (lines, 0..) |line, index| {
        if (index > 0) try out.append(allocator, '\n');
        try out.appendSlice(allocator, line);
    }
    return out.toOwnedSlice(allocator);
}

/// Split leading `# doc:` directives from a body, recording unknown names.
fn stripDirectives(allocator: std.mem.Allocator, body: []const u8, out: *std.ArrayList(Directive), error_out: *?[]const u8) ![]const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    var split = std.mem.splitScalar(u8, body, '\n');
    while (split.next()) |line| try lines.append(allocator, line);
    var taken: usize = 0;
    for (lines.items) |line| {
        const parsed = directiveLine(line) orelse {
            if (std.mem.trim(u8, line, " \t\r").len == 0) {
                taken += 1;
                continue;
            }
            break;
        };
        if (!contains(&known_directives, parsed.name)) {
            error_out.* = try std.fmt.allocPrint(allocator, "unknown directive '# doc: {s}'", .{parsed.name});
        }
        try out.append(allocator, parsed);
        taken += 1;
    }
    while (taken > 0 and std.mem.trim(u8, lines.items[taken - 1], " \t\r").len == 0) taken -= 1;
    return joinLines(allocator, lines.items[taken..]);
}

fn directiveLine(line: []const u8) ?Directive {
    var i: usize = 0;
    while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
    if (i >= line.len or line[i] != '#') return null;
    i += 1;
    while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
    if (!std.mem.startsWith(u8, line[i..], "doc:")) return null;
    i += "doc:".len;
    while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
    const name_start = i;
    while (i < line.len and (std.ascii.isAlphabetic(line[i]) or line[i] == '-')) i += 1;
    if (i == name_start) return null;
    const name = line[name_start..i];
    var rest = std.mem.trimStart(u8, line[i..], " \t");
    rest = std.mem.trimEnd(u8, rest, " \t\r");
    // Preserve explicit prose exclusions in historical audit reports.
    return .{ .name = if (eql(name, "not-mylang")) not_selka else name, .rest = rest };
}

fn hasDirective(fence: *const Fence, name: []const u8) bool {
    for (fence.directives) |directive| if (eql(directive.name, name)) return true;
    return false;
}

fn directivesOf(allocator: std.mem.Allocator, fence: *const Fence, name: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (fence.directives) |directive| {
        if (eql(directive.name, name)) try out.append(allocator, directive.rest);
    }
    return out.toOwnedSlice(allocator);
}

fn unitDirectives(allocator: std.mem.Allocator, unit: *const Unit, name: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (unit.members.items) |member| {
        for (member.directives) |directive| {
            if (eql(directive.name, name)) try out.append(allocator, directive.rest);
        }
    }
    return out.toOwnedSlice(allocator);
}

fn unitHasDirective(unit: *const Unit, name: []const u8) bool {
    for (unit.members.items) |member| if (hasDirective(member, name)) return true;
    return false;
}

fn unitHasFile(unit: *const Unit, wanted: []const u8) bool {
    for (unit.members.items) |member| {
        for (member.directives) |directive| {
            if (eql(directive.name, "file") and eql(std.mem.trim(u8, directive.rest, " \t\r"), wanted)) return true;
        }
    }
    return false;
}

/// Fold executable fences into standalone block units and named project units.
fn group(allocator: std.mem.Allocator, blocks: []const *const Fence) ![]*Unit {
    var units: std.ArrayList(*Unit) = .empty;
    var projects: std.StringHashMapUnmanaged(*Unit) = .empty;
    for (blocks) |fence| {
        const names = try directivesOf(allocator, fence, "project");
        if (names.len == 0) {
            const unit = try allocator.create(Unit);
            unit.* = .{ .kind = .block, .label = fence.label, .document = fence.document, .members = .empty };
            try unit.members.append(allocator, fence);
            try units.append(allocator, unit);
            continue;
        }
        const key = try std.fmt.allocPrint(allocator, "{s}#{s}", .{ fence.document, names[0] });
        const entry = try projects.getOrPut(allocator, key);
        if (!entry.found_existing) {
            const unit = try allocator.create(Unit);
            unit.* = .{ .kind = .project, .label = key, .document = fence.document, .members = .empty };
            entry.value_ptr.* = unit;
            try units.append(allocator, unit);
        }
        try entry.value_ptr.*.members.append(allocator, fence);
    }
    return units.toOwnedSlice(allocator);
}

/// Decide how one unit should be exercised, or why it cannot be.
fn plan(allocator: std.mem.Allocator, unit: *const Unit) !Plan {
    var skips: std.ArrayList([]const u8) = .empty;
    var broken: std.ArrayList([]const u8) = .empty;
    var has_not_selka = false;
    var has_main = false;
    for (unit.members.items) |member| {
        if (member.error_message) |message| try broken.append(allocator, message);
        if (hasMain(member.source)) has_main = true;
        for (member.directives) |directive| {
            if (eql(directive.name, "skip")) try skips.append(allocator, directive.rest);
            if (eql(directive.name, not_selka)) has_not_selka = true;
        }
    }
    if (broken.items.len > 0) return .{ .action = .invalid, .detail = try join(allocator, broken.items, "; ") };
    // NEW-CORE-S5-DOCTEST-1: legacy sharing and the collector were retired (S5-D4).
    if (unitHasDirective(unit, legacy_sharing) or unitHasDirective(unit, gc_runtime)) return .{ .action = .skip, .detail = retired_mode };
    if (skips.items.len > 0) {
        var blank = false;
        for (skips.items) |reason| if (std.mem.trim(u8, reason, " \t\r").len == 0) {
            blank = true;
            break;
        };
        if (blank) return .{ .action = .invalid, .detail = "'# doc: skip' requires a reason" };
        return .{ .action = .skip, .detail = try join(allocator, skips.items, "; ") };
    }
    if (has_not_selka) return .{ .action = .invalid, .detail = "'# doc: not-selka' cannot tag an executable block" };
    if (unit.kind == .project and !unitHasFile(unit, source_names.entry)) return .{ .action = .invalid, .detail = "project has no '# doc: file main.selka' entry" };
    const expect = try unitDirectives(allocator, unit, "expect");
    const raw_codes = try unitDirectives(allocator, unit, "expect-error");
    var codes: std.ArrayList([]const u8) = .empty;
    for (raw_codes) |code| try codes.append(allocator, std.mem.trim(u8, code, " \t\r"));
    const forced = unitHasDirective(unit, "check");
    if (codes.items.len > 0 and (expect.len > 0 or forced)) {
        return .{ .action = .invalid, .detail = "'expect-error' cannot combine with 'expect' or 'check'" };
    }
    if (codes.items.len > 0) return .{ .action = .expect_error, .codes = try codes.toOwnedSlice(allocator) };
    if (forced) return .{ .action = .check, .expect = expect };
    if (!has_main) {
        if (expect.len > 0) return .{ .action = .invalid, .detail = "'expect' needs a 'main' to run" };
        return .{ .action = .check, .expect = &.{} };
    }
    return .{ .action = .run, .expect = expect };
}

fn join(allocator: std.mem.Allocator, items: []const []const u8, separator: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (items, 0..) |item, index| {
        if (index > 0) try out.appendSlice(allocator, separator);
        try out.appendSlice(allocator, item);
    }
    return out.toOwnedSlice(allocator);
}

fn hasMain(source: []const u8) bool {
    var split = std.mem.splitScalar(u8, source, '\n');
    while (split.next()) |line| {
        var i = skipSpace(line, 0);
        if (std.mem.startsWith(u8, line[i..], "public") and i + "public".len < line.len and (line[i + "public".len] == ' ' or line[i + "public".len] == '\t')) {
            i = skipSpace(line, i + "public".len);
        }
        if (!std.mem.startsWith(u8, line[i..], "func")) continue;
        var j = i + "func".len;
        if (j >= line.len or (line[j] != ' ' and line[j] != '\t')) continue;
        j = skipSpace(line, j);
        if (!std.mem.startsWith(u8, line[j..], "main")) continue;
        const after = j + "main".len;
        if (after == line.len or !(std.ascii.isAlphanumeric(line[after]) or line[after] == '_')) return true;
    }
    return false;
}

fn skipSpace(line: []const u8, start: usize) usize {
    var i = start;
    while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
    return i;
}

fn moduleLine(source: []const u8) ?[]const u8 {
    var split = std.mem.splitScalar(u8, source, '\n');
    while (split.next()) |line| {
        if (!std.mem.startsWith(u8, line, "module")) continue;
        var i: usize = "module".len;
        if (i >= line.len or (line[i] != ' ' and line[i] != '\t')) continue;
        i = skipSpace(line, i);
        if (i >= line.len or !(std.ascii.isAlphabetic(line[i]) or line[i] == '_')) continue;
        const start = i;
        i += 1;
        while (i < line.len and (std.ascii.isAlphanumeric(line[i]) or line[i] == '_')) i += 1;
        return line[start..i];
    }
    return null;
}

fn guestShape(source: []const u8) bool {
    var split = std.mem.splitScalar(u8, source, '\n');
    while (split.next()) |line| {
        if (std.mem.startsWith(u8, line, "func main") or std.mem.startsWith(u8, line, "module ")) return true;
    }
    return false;
}

fn wordByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '.';
}

fn spaceByte(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\r' or byte == '\n';
}

fn hasPrintCall(source: []const u8) bool {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, source, cursor, "print")) |at| {
        // A bare `print(` or a `stream.print(` method call; `sprint(` and other
        // identifiers that merely end in `print` do not count.
        const before_ok = at == 0 or !wordByte(source[at - 1]) or source[at - 1] == '.';
        var i = at + "print".len;
        while (i < source.len and spaceByte(source[i])) i += 1;
        if (before_ok and i < source.len and source[i] == '(') return true;
        cursor = at + 1;
    }
    return false;
}

/// What materialising one unit produced: its entry path, entry source and
/// whether any member declared a `main`.
const Written = struct { entry: []const u8, entry_source: []const u8, has_main: bool };

fn write(allocator: std.mem.Allocator, io: std.Io, unit: *const Unit, directory: []const u8) !Written {
    try std.Io.Dir.cwd().createDirPath(io, directory);
    var entry: ?[]const u8 = null;
    var entry_source: []const u8 = "";
    var has_main = false;
    for (unit.members.items, 0..) |member, index| {
        if (hasMain(member.source)) has_main = true;
        const name = try fileName(allocator, unit, member, index);
        const path = try std.fs.path.join(allocator, &.{ directory, name });
        const content = try std.fmt.allocPrint(allocator, "{s}\n", .{member.source});
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = content });
        if (eql(name, source_names.entry) or (entry == null and unit.kind == .block)) {
            entry = path;
            entry_source = member.source;
        }
    }
    const entry_path = entry orelse try std.fs.path.join(allocator, &.{ directory, source_names.entry });
    if (!has_main) {
        const stubbed = try std.fmt.allocPrint(allocator, "{s}\n{s}", .{ entry_source, stub });
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = entry_path, .data = stubbed });
    }
    return .{ .entry = entry_path, .entry_source = entry_source, .has_main = has_main };
}

fn fileName(allocator: std.mem.Allocator, unit: *const Unit, member: *const Fence, index: usize) ![]const u8 {
    const named = try directivesOf(allocator, member, "file");
    if (named.len > 0) return std.mem.trim(u8, named[0], " \t\r");
    if (moduleLine(member.source)) |name| return std.fmt.allocPrint(allocator, "{s}.selka", .{name});
    if (unit.members.items.len == 1) return source_names.entry;
    return std.fmt.allocPrint(allocator, "block{d}.selka", .{index});
}

fn commandOptions(allocator: std.mem.Allocator, unit: *const Unit, subcommand: []const u8, fixtures: []const u8) ![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    if (unitHasDirective(unit, value_semantics)) try argv.append(allocator, "--value-semantics");
    if (unitHasDirective(unit, legacy_sharing)) try argv.append(allocator, "--legacy-sharing");
    if (unitHasDirective(unit, gc_runtime)) try argv.append(allocator, "--gc-runtime");
    if (std.mem.startsWith(u8, subcommand, "run")) {
        if (!unitPrints(unit)) try argv.append(allocator, "--print-result");
        const flags = [_][]const u8{ "--allow-read=", "--allow-write=" };
        const names = [_][]const u8{ "allow-read", "allow-write" };
        var grants: std.ArrayList([]const u8) = .empty;
        for (flags, names) |flag, name| {
            for (unit.members.items) |member| {
                for (member.directives) |directive| {
                    if (!eql(directive.name, name)) continue;
                    const path = try std.fs.path.resolve(allocator, &.{ fixtures, std.mem.trim(u8, directive.rest, " \t\r") });
                    try grants.append(allocator, try std.fmt.allocPrint(allocator, "{s}{s}", .{ flag, path }));
                }
            }
        }
        if (grants.items.len > 0) {
            try argv.append(allocator, "--restrict");
            try argv.appendSlice(allocator, grants.items);
        }
    }
    return argv.toOwnedSlice(allocator);
}

/// The options a unit's command is run with: value semantics is always on in the
/// new core, which refuses the retired `--value-semantics` switch (NEW-CORE-S5-DOCTEST-1).
fn invokedOptions(allocator: std.mem.Allocator, options: []const []const u8) ![]const []const u8 {
    var kept: std.ArrayList([]const u8) = .empty;
    for (options) |option| if (!eql(option, "--value-semantics")) try kept.append(allocator, option);
    return kept.toOwnedSlice(allocator);
}

fn unitPrints(unit: *const Unit) bool {
    for (unit.members.items) |member| if (hasPrintCall(member.source)) return true;
    return false;
}

/// One finished child invocation, with its argv retained for the report.
const Invocation = struct {
    term: std.process.Child.Term,
    stdout: []const u8,
    stderr: []const u8,
    argv: []const []const u8,
};

fn invoke(allocator: std.mem.Allocator, io: std.Io, compiler: []const u8, subcommand: []const u8, entry: []const u8, extra: []const []const u8) !Invocation {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(allocator, &.{ compiler, subcommand, entry, "--diagnostics=json" });
    try argv.appendSlice(allocator, extra);
    const cache = try std.fs.path.join(allocator, &.{ std.fs.path.dirname(entry).?, "objects" });
    try argv.append(allocator, try std.fmt.allocPrint(allocator, "--cache-dir={s}", .{cache}));
    const owned = try argv.toOwnedSlice(allocator);
    const result = try std.process.run(allocator, io, .{
        .argv = owned,
        .timeout = .{ .duration = .{ .clock = .awake, .raw = std.Io.Duration.fromSeconds(timeout_seconds) } },
    });
    return .{ .term = result.term, .stdout = result.stdout, .stderr = result.stderr, .argv = owned };
}

fn commandStatus(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        .signal => |signal| @intCast(@min(255, 128 + @as(u32, @backingInt(signal)))),
        else => 2,
    };
}

fn commandFor(action: Action, project: bool) []const u8 {
    return switch (action) {
        .check, .expect_error => if (project) "check-project" else "check",
        .run => if (project) "run-project" else "run",
        else => "check",
    };
}

/// Shared state a bounded pool of workers pulls its next unit from. Every unit
/// owns its directory, its child process and its own status, and the session's
/// arena is threadsafe, so the cursor and the output lock are the only things
/// the workers contend over.
const Pool = struct {
    session: Session,
    units: []*Unit,
    workspace: []const u8,
    next: std.atomic.Value(usize) = .init(0),
    failure: ?anyerror = null,
};

/// Execute every unit across a bounded pool. The dispatching thread is one of
/// the workers, so a machine that refuses more concurrency still makes
/// progress. Statuses land on the units themselves and nothing is reported
/// here, so the summary the caller renders afterwards keeps its serial order
/// however the units finish.
fn runUnits(session: Session, units: []*Unit, workspace: []const u8, workers: usize) !void {
    var pool: Pool = .{ .session = session, .units = units, .workspace = workspace };
    var tasks: std.Io.Group = .init;
    defer tasks.cancel(session.io);
    var spawned: usize = 1;
    while (spawned < workers) : (spawned += 1) {
        tasks.concurrent(session.io, worker, .{&pool}) catch break;
    }
    worker(&pool);
    try tasks.await(session.io);
    if (pool.failure) |err| return err;
}

/// Take units off the shared cursor until it is exhausted. An example that
/// fails its check is a unit status, not an error, so it never reaches here;
/// a host failure is recorded once and retires this worker while the units the
/// other workers hold run to completion.
fn worker(pool: *Pool) void {
    while (true) {
        const index = pool.next.fetchAdd(1, .monotonic);
        if (index >= pool.units.len) return;
        claim(pool, index) catch |err| {
            pool.session.output.lockUncancelable(pool.session.io);
            defer pool.session.output.unlock(pool.session.io);
            if (pool.failure == null) pool.failure = err;
            return;
        };
    }
}

/// Execute one unit in the private directory its index names.
fn claim(pool: *Pool, index: usize) !void {
    const unit_dir = try std.fmt.allocPrint(pool.session.allocator, "{s}/unit{d:0>3}", .{ pool.workspace, index });
    try execute(pool.session, pool.units[index], index, pool.units.len, unit_dir);
}

/// Write one already-terminated line to standard output under the shared lock,
/// so verbose progress from concurrent workers interleaves by line, never by
/// byte.
fn emit(session: Session, line: []const u8) !void {
    session.output.lockUncancelable(session.io);
    defer session.output.unlock(session.io);
    try writeOut(session.io, line);
}

fn execute(session: Session, unit: *Unit, index: usize, total: usize, unit_dir: []const u8) !void {
    const decided = try plan(session.allocator, unit);
    switch (decided.action) {
        .invalid => {
            unit.status = .failed;
            unit.detail = decided.detail;
            return;
        },
        .skip => {
            unit.status = .skipped;
            unit.detail = decided.detail;
            return;
        },
        else => {},
    }
    if (session.verbose) {
        try emit(session, try std.fmt.allocPrint(session.allocator, "[{d}/{d}] {s}\n", .{ index + 1, total, unit.label }));
    }
    const written = try write(session.allocator, session.io, unit, unit_dir);
    const project = unit.members.items.len > 1 or moduleLine(written.entry_source) != null;
    const subcommand = commandFor(decided.action, project);
    const extra = try invokedOptions(session.allocator, try commandOptions(session.allocator, unit, subcommand, session.fixtures));
    const invocation = invoke(session.allocator, session.io, session.compiler, subcommand, written.entry, extra) catch |err| switch (err) {
        error.Timeout => {
            unit.status = .failed;
            unit.detail = try std.fmt.allocPrint(session.allocator, "'{s}' did not finish within {d} seconds", .{ subcommand, timeout_seconds });
            return;
        },
        else => return err,
    };
    unit.command = invocation.argv;
    if (session.verbose and invocation.stderr.len > 0) {
        try emit(session, try std.fmt.allocPrint(session.allocator, "  ! {s}\n", .{std.mem.trim(u8, invocation.stderr, " \t\r\n")}));
    }
    try record(session.allocator, unit, decided, invocation, written.has_main);
}

/// The status the compiler uses for a host failure — a usage error or an I/O
/// fault — as opposed to a source diagnostic, which exits 1.
const host_status: u8 = 2;
/// The CLI's host-failure marker on stderr. It corroborates the machine-readable
/// host status and names the cause in the failure text; a changed wording costs
/// the detail, never the verdict.
const host_failure_marker = "selka: host failure";
/// One finished child's failure inputs, grouped to keep the classifier compact.
const ChildFailure = struct { status: u8, stdout: []const u8, stderr: []const u8, diagnosed: bool };

/// Whether a child died in the host rather than reporting a diagnosed guest
/// error: the host status with no `diagnostic-v1` record, corroborated by the
/// CLI's own marker or by having produced no program output at all. A guest
/// `main` that returns the host status has still printed its recorded result or
/// its own output, so it is never mistaken for the host dying, and a wording
/// change in the marker falls back to the machine-readable signal instead of
/// silently passing a dropped example.
fn hostFailed(child: ChildFailure) bool {
    if (child.status != host_status) return false;
    if (child.diagnosed) return false;
    if (std.mem.indexOf(u8, child.stderr, host_failure_marker) != null) return true;
    return child.stdout.len == 0;
}

fn record(allocator: std.mem.Allocator, unit: *Unit, decided: Plan, invocation: Invocation, has_main: bool) !void {
    const status = commandStatus(invocation.term);
    if (decided.action == .expect_error) {
        const seen = try diagnose(allocator, invocation.stderr);
        if (status == 0) {
            unit.status = .failed;
            unit.detail = try std.fmt.allocPrint(allocator, "expected {s} but the example checked cleanly", .{try formatList(allocator, decided.codes)});
            return;
        }
        var missing: std.ArrayList([]const u8) = .empty;
        for (decided.codes) |code| if (!contains(seen, code)) try missing.append(allocator, code);
        if (missing.items.len > 0) {
            const saw = if (seen.len > 0) try formatList(allocator, seen) else "no JSON diagnostics";
            unit.status = .failed;
            unit.detail = try std.fmt.allocPrint(allocator, "expected {s}, saw {s}", .{ try formatList(allocator, missing.items), saw });
            return;
        }
        unit.status = .checked;
        unit.detail = try std.fmt.allocPrint(allocator, "rejected with {s}", .{try formatList(allocator, decided.codes)});
        return;
    }
    // A run now exits with its entry's `int` result, so a nonzero status is not a
    // failure by itself. A genuine failure is a checker rejection (`check`), a
    // native trap (a `diagnostic-v1` record on stderr), a crash by signal, or the
    // host dying before the guest ever ran.
    const crashed = invocation.term != .exited;
    const diagnosed = try diagnosedError(allocator, invocation.stderr);
    const host_failed = !crashed and hostFailed(.{ .status = status, .stdout = invocation.stdout, .stderr = invocation.stderr, .diagnosed = diagnosed });
    const failed = if (decided.action == .run)
        crashed or diagnosed or host_failed
    else
        status != 0;
    if (failed) {
        const rendered = try normalise(allocator, invocation.stderr);
        const fallback = if (rendered.len > 0) rendered else try normalise(allocator, invocation.stdout);
        unit.status = .failed;
        unit.detail = if (host_failed)
            try std.fmt.allocPrint(allocator, "host failure (exit {d}): {s}", .{ status, fallback })
        else
            try std.fmt.allocPrint(allocator, "exit {d}: {s}", .{ status, fallback });
        return;
    }
    if (decided.action == .check) {
        unit.status = .checked;
        if (!has_main) unit.detail = "generated entry point";
        return;
    }
    if (decided.expect.len > 0) {
        const wanted = try normalise(allocator, try join(allocator, decided.expect, "\n"));
        const actual = try normalise(allocator, invocation.stdout);
        if (!eql(wanted, actual)) {
            unit.status = .failed;
            unit.detail = try std.fmt.allocPrint(allocator, "expected stdout '{s}', saw '{s}'", .{ wanted, actual });
            return;
        }
        unit.status = .run;
        unit.detail = try std.fmt.allocPrint(allocator, "stdout '{s}'", .{wanted});
        return;
    }
    unit.status = .run;
}

/// Whether stderr carries a `diagnostic-v1` record of error severity — a native
/// trap or a checker rejection. A warning is not a failure and never counts.
fn diagnosedError(allocator: std.mem.Allocator, stderr: []const u8) !bool {
    var split = std.mem.splitScalar(u8, stderr, '\n');
    while (split.next()) |line| {
        if (line.len == 0 or line[0] != '{') continue;
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const diagnostic = parsed.value.object.get("diagnostic") orelse continue;
        if (diagnostic != .object) continue;
        const severity = diagnostic.object.get("severity") orelse continue;
        if (severity == .string and std.mem.eql(u8, severity.string, "error")) return true;
    }
    return false;
}

fn diagnose(allocator: std.mem.Allocator, stderr: []const u8) ![]const []const u8 {
    var codes: std.ArrayList([]const u8) = .empty;
    var split = std.mem.splitScalar(u8, stderr, '\n');
    while (split.next()) |line| {
        if (line.len == 0 or line[0] != '{') continue;
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const diagnostic = parsed.value.object.get("diagnostic") orelse continue;
        if (diagnostic != .object) continue;
        const code = diagnostic.object.get("code") orelse continue;
        if (code != .string) continue;
        try codes.append(allocator, try allocator.dupe(u8, code.string));
    }
    return codes.toOwnedSlice(allocator);
}

fn normalise(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n\x0b\x0c");
    var out: std.ArrayList(u8) = .empty;
    var split = std.mem.splitScalar(u8, trimmed, '\n');
    var first = true;
    while (split.next()) |line| {
        if (!first) try out.append(allocator, '\n');
        first = false;
        try out.appendSlice(allocator, std.mem.trimEnd(u8, line, " \t\r\x0b\x0c"));
    }
    return out.toOwnedSlice(allocator);
}

fn formatList(allocator: std.mem.Allocator, items: []const []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.append(allocator, '[');
    for (items, 0..) |item, index| {
        if (index > 0) try out.appendSlice(allocator, ", ");
        try out.append(allocator, '\'');
        try out.appendSlice(allocator, item);
        try out.append(allocator, '\'');
    }
    try out.append(allocator, ']');
    return out.toOwnedSlice(allocator);
}

/// Scratch follows the caller's TMPDIR, including read-only documentation roots.
fn workspaceRoot(environ: *const std.process.Environ.Map) []const u8 {
    const root = environ.get("TMPDIR") orelse "";
    return if (root.len == 0) "/tmp" else root;
}

/// Build one random-named private directory under the caller's scratch root.
fn makeWorkspace(allocator: std.mem.Allocator, io: std.Io, parent: []const u8) ![]const u8 {
    try std.Io.Dir.cwd().createDirPath(io, parent);
    var random: [8]u8 = undefined;
    std.Io.random(io, &random);
    const name = try std.fmt.allocPrint(allocator, "doctest-{s}", .{std.fmt.bytesToHex(random, .lower)});
    const path = try std.fs.path.join(allocator, &.{ parent, name });
    try std.Io.Dir.cwd().createDir(io, path, .default_dir);
    return path;
}

fn tabulate(allocator: std.mem.Allocator, units: []const *Unit, suspects: []const *const Fence, counts: std.StringHashMapUnmanaged(usize), table: *std.StringHashMapUnmanaged(Counts)) !void {
    var counted = counts.iterator();
    while (counted.next()) |entry| {
        const row = try table.getOrPut(allocator, entry.key_ptr.*);
        if (!row.found_existing) row.value_ptr.* = .{};
        row.value_ptr.blocks = entry.value_ptr.*;
    }
    for (units) |unit| {
        const row = try table.getOrPut(allocator, unit.document);
        if (!row.found_existing) row.value_ptr.* = .{};
        switch (unit.status) {
            .run => row.value_ptr.run += 1,
            .checked => row.value_ptr.checked += 1,
            .skipped => {
                row.value_ptr.skipped += 1;
                try row.value_ptr.skips.append(allocator, unit.detail);
            },
            .failed => row.value_ptr.failed += 1,
            .pending => {},
        }
    }
    for (suspects) |fence| {
        const row = try table.getOrPut(allocator, fence.document);
        if (!row.found_existing) row.value_ptr.* = .{};
        row.value_ptr.mistagged += 1;
    }
}

fn appendLine(out: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime format: []const u8, args: anytype) !void {
    try out.appendSlice(allocator, try std.fmt.allocPrint(allocator, format, args));
}

fn report(allocator: std.mem.Allocator, out: *std.ArrayList(u8), table: *std.StringHashMapUnmanaged(Counts), units: []const *Unit, suspects: []const *const Fence) !Totals {
    var names: std.ArrayList([]const u8) = .empty;
    var keys = table.keyIterator();
    while (keys.next()) |key| try names.append(allocator, key.*);
    std.mem.sort([]const u8, names.items, {}, lessThan);
    var totals = Totals{};
    var blocks: usize = 0;
    for (names.items) |name| {
        const row = table.get(name).?;
        blocks += row.blocks;
        if (rowIsEmpty(row)) continue;
        try appendLine(out, allocator, "  {s}: {d} run, {d} checked, {d} skipped, {d} mis-tagged, {d} failed\n", .{ name, row.run, row.checked, row.skipped, row.mistagged, row.failed });
        for (row.skips.items) |reason| try appendLine(out, allocator, "      skip: {s}\n", .{reason});
    }
    for (suspects) |fence| {
        try appendLine(out, allocator, "MIS-TAGGED {s}: '```{s}' block looks like guest source; retag it 'selka' or mark it '# doc: not-selka'\n", .{ fence.label, fence.tag });
        totals.mistagged += 1;
    }
    for (units) |unit| {
        if (unit.status != .failed) continue;
        try appendLine(out, allocator, "FAILED {s}: {s}\n", .{ unit.label, unit.detail });
        totals.failed += 1;
    }
    for (names.items) |name| {
        const row = table.get(name).?;
        totals.run += row.run;
        totals.checked += row.checked;
        totals.skipped += row.skipped;
    }
    try appendLine(out, allocator, "Doc examples: {d} files scanned, {d} blocks found, {d} run, {d} checked, " ++
        "{d} skipped, {d} mis-tagged, {d} failed\n", .{ names.items.len, blocks, totals.run, totals.checked, totals.skipped, totals.mistagged, totals.failed });
    return totals;
}

fn rowIsEmpty(row: Counts) bool {
    if (row.run != 0) return false;
    if (row.checked != 0) return false;
    if (row.skipped != 0) return false;
    if (row.mistagged != 0) return false;
    if (row.failed != 0) return false;
    return true;
}

fn intValue(value: usize) std.json.Value {
    return .{ .integer = @intCast(value) };
}

fn countsValue(allocator: std.mem.Allocator, counts: Counts) !std.json.Value {
    var object: std.json.ObjectMap = .empty;
    try object.put(allocator, "blocks", intValue(counts.blocks));
    try object.put(allocator, "run", intValue(counts.run));
    try object.put(allocator, "checked", intValue(counts.checked));
    try object.put(allocator, "skipped", intValue(counts.skipped));
    try object.put(allocator, mistagged_key, intValue(counts.mistagged));
    try object.put(allocator, "failed", intValue(counts.failed));
    var skips = std.json.Array.init(allocator);
    for (counts.skips.items) |reason| try skips.append(.{ .string = reason });
    try object.put(allocator, "skips", .{ .array = skips });
    return .{ .object = object };
}

fn stringArray(allocator: std.mem.Allocator, items: []const []const u8) !std.json.Value {
    var array = std.json.Array.init(allocator);
    for (items) |item| try array.append(.{ .string = item });
    return .{ .array = array };
}

/// Everything the optional `--report` writer needs, bundled to keep its
/// parameter list within the function-size limit.
const ReportRequest = struct {
    process: std.process.Init,
    allocator: std.mem.Allocator,
    path: []const u8,
    table: *std.StringHashMapUnmanaged(Counts),
    units: []const *Unit,
    suspects: []const *const Fence,
    totals: Totals,
};

fn writeReport(request: ReportRequest) !void {
    const process = request.process;
    const allocator = request.allocator;
    const path = request.path;
    const table = request.table;
    const units = request.units;
    const suspects = request.suspects;
    const totals = request.totals;
    const compiler = try std.process.executablePathAlloc(process.io, allocator);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(process.io, compiler, process.gpa, .unlimited);
    defer process.gpa.free(bytes);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hex = try allocator.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
    var files: std.json.ObjectMap = .empty;
    var names: std.ArrayList([]const u8) = .empty;
    var keys = table.keyIterator();
    while (keys.next()) |key| try names.append(allocator, key.*);
    std.mem.sort([]const u8, names.items, {}, lessThan);
    for (names.items) |name| try files.put(allocator, name, try countsValue(allocator, table.get(name).?));
    var total_object: std.json.ObjectMap = .empty;
    try total_object.put(allocator, "run", intValue(totals.run));
    try total_object.put(allocator, "checked", intValue(totals.checked));
    try total_object.put(allocator, "skipped", intValue(totals.skipped));
    try total_object.put(allocator, mistagged_key, intValue(totals.mistagged));
    try total_object.put(allocator, "failed", intValue(totals.failed));
    var unit_array = std.json.Array.init(allocator);
    for (units) |unit| {
        var object: std.json.ObjectMap = .empty;
        try object.put(allocator, "label", .{ .string = unit.label });
        try object.put(allocator, "kind", .{ .string = if (unit.kind == .block) "block" else "project" });
        try object.put(allocator, "document", .{ .string = unit.document });
        try object.put(allocator, "status", .{ .string = @tagName(unit.status) });
        try object.put(allocator, "detail", .{ .string = unit.detail });
        try object.put(allocator, "command", try stringArray(allocator, unit.command));
        try unit_array.append(.{ .object = object });
    }
    var mistagged_array = std.json.Array.init(allocator);
    for (suspects) |fence| {
        var object: std.json.ObjectMap = .empty;
        try object.put(allocator, "label", .{ .string = fence.label });
        try object.put(allocator, "tag", .{ .string = fence.tag });
        try mistagged_array.append(.{ .object = object });
    }
    var root: std.json.ObjectMap = .empty;
    try root.put(allocator, "version", .{ .string = "doc-examples-v1" });
    try root.put(allocator, "compiler", .{ .string = compiler });
    try root.put(allocator, "compiler_sha256", .{ .string = hex });
    try root.put(allocator, "totals", .{ .object = total_object });
    try root.put(allocator, "files", .{ .object = files });
    try root.put(allocator, "units", .{ .array = unit_array });
    try root.put(allocator, mistagged_key, .{ .array = mistagged_array });
    const rendered = try std.json.Stringify.valueAlloc(allocator, std.json.Value{ .object = root }, .{ .whitespace = .indent_2 });
    if (std.fs.path.dirname(path)) |parent| try std.Io.Dir.cwd().createDirPath(process.io, parent);
    try std.Io.Dir.cwd().writeFile(process.io, .{ .sub_path = path, .data = try std.fmt.allocPrint(allocator, "{s}\n", .{rendered}) });
}

fn executableBlocks(allocator: std.mem.Allocator, found: []const Fence) ![]const *const Fence {
    var blocks: std.ArrayList(*const Fence) = .empty;
    for (found) |*fence| {
        if (isExecutable(fence)) try blocks.append(allocator, fence);
    }
    return blocks.toOwnedSlice(allocator);
}

const testing = std.testing;

/// Eight independent skip units — more units than the pool width the concurrency
/// test bounds itself to, so at least one worker has to take several of them.
const pool_document =
    "```selka\n# doc: skip reason-1\nfunc main() -> int:\n    return 0\n```\n" ++
    "```selka\n# doc: skip reason-2\nfunc main() -> int:\n    return 0\n```\n" ++
    "```selka\n# doc: skip reason-3\nfunc main() -> int:\n    return 0\n```\n" ++
    "```selka\n# doc: skip reason-4\nfunc main() -> int:\n    return 0\n```\n" ++
    "```selka\n# doc: skip reason-5\nfunc main() -> int:\n    return 0\n```\n" ++
    "```selka\n# doc: skip reason-6\nfunc main() -> int:\n    return 0\n```\n" ++
    "```selka\n# doc: skip reason-7\nfunc main() -> int:\n    return 0\n```\n" ++
    "```selka\n# doc: skip reason-8\nfunc main() -> int:\n    return 0\n```\n";

/// The summary those eight units must render, whatever order they finish in.
const pool_report =
    "  docs/pool.md: 0 run, 0 checked, 8 skipped, 0 mis-tagged, 0 failed\n" ++
    "      skip: reason-1\n      skip: reason-2\n      skip: reason-3\n      skip: reason-4\n" ++
    "      skip: reason-5\n      skip: reason-6\n      skip: reason-7\n      skip: reason-8\n" ++
    "Doc examples: 1 files scanned, 8 blocks found, 0 run, 0 checked, 8 skipped, 0 mis-tagged, 0 failed\n";

// spec: DOCTEST-1
test "doctest a fence carries its info tag, flags and directives and strips them from the source" {
    const text =
        "# Intro\n" ++
        "\n" ++
        "```selka extra\n" ++
        "# doc: expect hello\n" ++
        "# doc: allow-read fixtures-dir\n" ++
        "func main() -> int:\n" ++
        "    return 0\n" ++
        "```\n" ++
        "\n" ++
        "~~~\n" ++
        "not a test\n" ++
        "~~~\n";
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const found = try fences(arena.allocator(), "docs/example.md", text);
    try testing.expectEqual(@as(usize, 2), found.len);
    try testing.expectEqualStrings("selka", found[0].tag);
    try testing.expect(found[0].notest == false);
    try testing.expectEqual(@as(usize, 2), found[0].directives.len);
    try testing.expectEqualStrings("expect", found[0].directives[0].name);
    try testing.expectEqualStrings("hello", found[0].directives[0].rest);
    try testing.expectEqualStrings("func main() -> int:\n    return 0", found[0].source);
    try testing.expectEqualStrings("", found[1].tag);
}

test "doctest an unknown directive is reported and a missing skip reason invalidates its unit" {
    const text =
        "```selka\n" ++
        "# doc: skpi because typo\n" ++
        "func main() -> int:\n" ++
        "    return 0\n" ++
        "```\n";
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const found = try fences(allocator, "docs/example.md", text);
    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expect(found[0].error_message != null);
    try testing.expect(std.mem.indexOf(u8, found[0].error_message.?, "unknown directive") != null);
    var blocks: std.ArrayList(*const Fence) = .empty;
    try blocks.append(allocator, &found[0]);
    const units = try group(allocator, blocks.items);
    const decided = try plan(allocator, units[0]);
    try testing.expectEqual(Action.invalid, decided.action);
}

test "doctest grouping folds project fences and plan picks run or check" {
    const text =
        "```selka\n" ++
        "# doc: project greeting\n" ++
        "# doc: file helper.selka\n" ++
        "" ++
        "\n" ++
        "public func answer() -> int:\n" ++
        "    return 42\n" ++
        "```\n" ++
        "```selka\n" ++
        "# doc: project greeting\n" ++
        "# doc: file main.selka\n" ++
        "" ++
        "import helper\n" ++
        "\n" ++
        "func main() -> int:\n" ++
        "    return helper.answer()\n" ++
        "```\n" ++
        "```python\n" ++
        "func main() -> int:\n" ++
        "    return 0\n" ++
        "```\n";
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const found = try fences(allocator, "docs/project.md", text);
    const blocks = try executableBlocks(allocator, found);
    const units = try group(allocator, blocks);
    try testing.expectEqual(@as(usize, 1), units.len);
    try testing.expectEqual(UnitKind.project, units[0].kind);
    try testing.expectEqual(@as(usize, 2), units[0].members.items.len);
    const decided = try plan(allocator, units[0]);
    try testing.expectEqual(Action.run, decided.action);
}

// spec: VALUE-SEMANTICS-8
test "doctest selects explicit value and legacy modes while plain units use the default" {
    const text =
        "```selka\n" ++
        "# doc: value-semantics\n" ++
        "# doc: expect 1\n" ++
        "func main() -> int:\n" ++
        "    return 1\n" ++
        "```\n" ++
        "```selka\n" ++
        "func main() -> int:\n" ++
        "    return 2\n" ++
        "```\n" ++
        "```selka\n" ++
        "# doc: legacy-sharing\n" ++
        "func main() -> int:\n" ++
        "    return 3\n" ++
        "```\n";
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const found = try fences(allocator, "docs/values.md", text);
    try testing.expectEqual(@as(?[]const u8, null), found[0].error_message);
    const units = try group(allocator, try executableBlocks(allocator, found));
    try testing.expectEqual(@as(usize, 3), units.len);
    const switched = try commandOptions(allocator, units[0], "run", "fixtures");
    try testing.expectEqualStrings("--value-semantics", switched[0]);
    const checked = try commandOptions(allocator, units[0], "check", "fixtures");
    try testing.expectEqualStrings("--value-semantics", checked[0]);
    const plain = try commandOptions(allocator, units[1], "run", "fixtures");
    for (plain) |argument| try testing.expect(!std.mem.eql(u8, argument, "--value-semantics"));
    const legacy = try commandOptions(allocator, units[2], "run", "fixtures");
    try testing.expectEqualStrings("--legacy-sharing", legacy[0]);
}

// spec: NEW-CORE-S5-DOCTEST-1
test "doctest skips units of retired modes and runs value-semantics units without the retired switch" {
    const text =
        "```selka\n" ++
        "# doc: value-semantics\n" ++
        "func main() -> int:\n" ++
        "    return 1\n" ++
        "```\n" ++
        "```selka\n" ++
        "# doc: legacy-sharing\n" ++
        "func main() -> int:\n" ++
        "    return 2\n" ++
        "```\n" ++
        "```selka\n" ++
        "# doc: gc-runtime\n" ++
        "func main() -> int:\n" ++
        "    return 3\n" ++
        "```\n";
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const units = try group(allocator, try executableBlocks(allocator, try fences(allocator, "docs/modes.md", text)));
    try testing.expectEqual(@as(usize, 3), units.len);
    try testing.expectEqual(Action.run, (try plan(allocator, units[0])).action);
    const options = try invokedOptions(allocator, try commandOptions(allocator, units[0], "run", "fixtures"));
    for (options) |option| try testing.expect(!eql(option, "--value-semantics"));
    try testing.expectEqual(Action.skip, (try plan(allocator, units[1])).action);
    try testing.expectEqualStrings(retired_mode, (try plan(allocator, units[2])).detail);
}

test "doctest runs a gc-runtime unit under the collector and plain units under the default" {
    const text =
        "```selka\n" ++
        "# doc: gc-runtime\n" ++
        "func main() -> int:\n" ++
        "    return 1\n" ++
        "```\n" ++
        "```selka\n" ++
        "func main() -> int:\n" ++
        "    return 2\n" ++
        "```\n";
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const found = try fences(allocator, "docs/memory.md", text);
    try testing.expectEqual(@as(?[]const u8, null), found[0].error_message);
    const units = try group(allocator, try executableBlocks(allocator, found));
    try testing.expectEqual(@as(usize, 2), units.len);
    const collected = try commandOptions(allocator, units[0], "run", "fixtures");
    try testing.expectEqualStrings("--gc-runtime", collected[0]);
    const checked = try commandOptions(allocator, units[0], "check", "fixtures");
    try testing.expectEqualStrings("--gc-runtime", checked[0]);
    const plain = try commandOptions(allocator, units[1], "run", "fixtures");
    for (plain) |argument| try testing.expect(!std.mem.eql(u8, argument, "--gc-runtime"));
}

test "doctest mis-tagged prose fences look like guest source and not-selka opts out" {
    const text =
        "```python\n" ++
        "func main() -> int:\n" ++
        "    return 0\n" ++
        "```\n" ++
        "```text\n" ++
        "# doc: not-selka\n" ++
        "func main() -> int:\n" ++
        "    return 0\n" ++
        "```\n" ++
        "```text\n" ++
        "# doc: not-mylang\n" ++
        "func historical() -> int:\n" ++
        "    return 0\n" ++
        "```\n";
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const found = try fences(allocator, "docs/mistag.md", text);
    try testing.expectEqual(@as(usize, 3), found.len);
    try testing.expect(mistagged(&found[0]));
    try testing.expect(!mistagged(&found[1]));
    try testing.expect(!mistagged(&found[2]));
}

test "doctest glob filters anchor a wildcard-free pattern but expand a star" {
    try testing.expect(globMatches("docs/arenas.md", "docs/arenas.md"));
    try testing.expect(!globMatches("arenas.md", "docs/arenas.md"));
    try testing.expect(globMatches("docs/*.md", "docs/arenas.md"));
    try testing.expect(globMatches("docs/*.md", "docs/deep/arenas.md"));
    try testing.expect(!globMatches("docs/**/*.md", "docs/arenas.md"));
    try testing.expect(globMatches("docs/**/*.md", "docs/deep/arenas.md"));
}

test "doctest normalise trims a stream the way expect comparison needs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const rendered = try normalise(arena.allocator(), "  hello  \n\nworld\t\n");
    try testing.expectEqualStrings("hello\n\nworld", rendered);
    const empty = try normalise(arena.allocator(), " \n\t\n");
    try testing.expectEqualStrings("", empty);
}

// spec-case: EXIT-STATUS-1
test "doctest a run fails on an error diagnostic but tolerates a warning" {
    // A run now exits with its entry result, so a bare nonzero exit is not a
    // failure; only an error-severity diagnostic (a trap) is. A warning is not.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const err = "{\"version\":\"diagnostic-v1\",\"kind\":\"diagnostic\",\"diagnostic\":{\"code\":\"R_DIVISION_BY_ZERO\",\"severity\":\"error\"}}";
    const warn = "{\"version\":\"diagnostic-v1\",\"kind\":\"diagnostic\",\"diagnostic\":{\"code\":\"W_UNUSED_BINDING\",\"severity\":\"warning\"}}";
    try testing.expect(try diagnosedError(a, err));
    try testing.expect(!(try diagnosedError(a, warn)));
    try testing.expect(!(try diagnosedError(a, "")));
}

// spec: DOCTEST-2
test "doctest a bounded worker pool reports every unit exactly once in document order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const found = try fences(allocator, "docs/pool.md", pool_document);
    const units = try group(allocator, try executableBlocks(allocator, found));
    try testing.expectEqual(@as(usize, 8), units.len);
    var output: std.Io.Mutex = .init;
    const session: Session = .{
        .allocator = allocator,
        .io = testing.io,
        .verbose = false,
        .compiler = "",
        .fixtures = "",
        .output = &output,
    };
    // Two workers for eight units, so the shared cursor, not the loop index,
    // decides who runs what; the report still has to come out in unit order.
    try runUnits(session, units, "workspace", 2);
    var counts: std.StringHashMapUnmanaged(usize) = .empty;
    try counts.put(allocator, "docs/pool.md", found.len);
    var table: std.StringHashMapUnmanaged(Counts) = .empty;
    try tabulate(allocator, units, &.{}, counts, &table);
    var out: std.ArrayList(u8) = .empty;
    const totals = try report(allocator, &out, &table, units, &.{});
    try testing.expectEqual(@as(usize, 8), totals.skipped);
    try testing.expectEqual(@as(usize, 0), totals.failed);
    try testing.expectEqualStrings(pool_report, out.items);
}

// spec-case: DOCTEST-2
test "doctest the pool width follows --jobs, then SELKA_JOBS, then the machine" {
    try testing.expectEqual(@as(?usize, 4), (try parseOptions(&.{ "--jobs", "4" })).jobs);
    try testing.expectEqual(@as(?usize, 4), (try parseOptions(&.{"--jobs=4"})).jobs);
    try testing.expectEqual(@as(?usize, null), (try parseOptions(&.{})).jobs);
    try testing.expectError(error.Usage, parseOptions(&.{"--jobs=0"}));
    try testing.expectError(error.Usage, parseOptions(&.{"--jobs=all"}));
    try testing.expectError(error.Usage, parseOptions(&.{"--jobs"}));
    var environ: std.process.Environ.Map = .init(testing.allocator);
    defer environ.deinit();
    try testing.expectEqual(@as(?usize, null), try resolveJobs(null, &environ));
    try environ.put(budget.jobs_variable, "3");
    try testing.expectEqual(@as(?usize, 3), try resolveJobs(null, &environ));
    try testing.expectEqual(@as(?usize, 5), try resolveJobs(5, &environ));
    try environ.put(budget.jobs_variable, "none");
    try testing.expectError(error.InvalidMemoryLimit, resolveJobs(null, &environ));
    // A width is never zero and never exceeds the units there are to run.
    try testing.expectEqual(@as(usize, 2), width(testing.io, 2, 8));
    try testing.expectEqual(@as(usize, 8), width(testing.io, 99, 8));
    try testing.expect(width(testing.io, null, 168) >= 1);
}

// spec: DOCTEST-3
test "a host-failed child fails its example even when the example expects nothing" {
    // The CLI wraps the host-failure line in a diagnostic-v1 message record;
    // either spelling is a host failure, and an empty run with the host status
    // is one even after the wording changes.
    try testing.expect(hostFailed(.{ .status = 2, .stdout = "", .stderr = "{\"version\":\"diagnostic-v1\",\"kind\":\"message\",\"message\":\"selka: host failure: AccessDenied\\n\"}\n", .diagnosed = false }));
    try testing.expect(hostFailed(.{ .status = 2, .stdout = "", .stderr = "selka: host failure: Unexpected\n", .diagnosed = false }));
    try testing.expect(hostFailed(.{ .status = 2, .stdout = "", .stderr = "", .diagnosed = false }));
    // A located source error is a diagnosed failure, never a host failure.
    try testing.expect(!hostFailed(.{ .status = 1, .stdout = "", .stderr = "{\"diagnostic\":{\"severity\":\"error\"}}", .diagnosed = true }));
    try testing.expect(!hostFailed(.{ .status = 0, .stdout = "", .stderr = "", .diagnosed = false }));
    // A guest `main` that returns the host status still printed its result or its
    // own output, so it keeps its recorded meaning.
    try testing.expect(!hostFailed(.{ .status = 2, .stdout = "2\n", .stderr = "", .diagnosed = false }));
    try testing.expect(!hostFailed(.{ .status = 2, .stdout = "hello\n", .stderr = "", .diagnosed = false }));
}

// spec: CLI-CACHE-ISOLATION-1
test "doctest scratch follows TMPDIR independently of its document root" {
    var environ: std.process.Environ.Map = .init(std.testing.allocator);
    defer environ.deinit();
    try std.testing.expectEqualStrings("/tmp", workspaceRoot(&environ));
    try environ.put("TMPDIR", "scratch");
    try std.testing.expectEqualStrings("scratch", workspaceRoot(&environ));
    try environ.put("TMPDIR", "");
    try std.testing.expectEqualStrings("/tmp", workspaceRoot(&environ));
}
