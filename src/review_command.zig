//! `selka review`: the change review of one project against a base, and `draft`,
//! which writes the change-note skeleton for the change.
const std = @import("std");
const release_options = @import("release_options.zig");
const loader = @import("release_project_load.zig");
const reports = @import("release_report.zig");
const Context = @import("release_context.zig").Context;
const review_git = @import("review_git.zig");
const review_side = @import("review_side.zig");
const review_core = @import("review_core.zig");
const review_output = @import("review_output.zig");
const review_attention = @import("review_attention.zig");
const review_tests = @import("review_tests.zig");
const review_html = @import("review_html.zig");
const review_index = @import("review_index.zig");

const usage =
    "usage: selka review draft PROJECT --name SLUG\n" ++
    "       selka review index SITE_DIR\n" ++
    "       selka review PROJECT [--against REF] [--head REV | --range A..B] [--check] [--test] [--json FILE] [--html FILE]\n";
const skeleton =
    "# TODO: title of this change\n\n" ++
    "Summary: TODO\n\n" ++
    "<!-- review: in two to four sentences, say what changed for someone who uses this project, and why. -->\n";
/// The reference the change is compared with when `--against` is not given.
const default_reference = "main";

/// A revision range `A..B`: the base and the head, both revisions.
const Range = struct { base: []const u8, head: []const u8 };

/// Parsed `selka review` arguments. `range` excludes `against` and `head`.
const Options = struct {
    project: []const u8,
    against: ?[]const u8 = null,
    head: ?[]const u8 = null,
    range: ?Range = null,
    check: bool = false,
    run_tests: bool = false,
    json: ?[]const u8 = null,
    html: ?[]const u8 = null,
};

/// The two commits a review compares; a null head is the working tree.
const Plan = struct { base: []const u8, head: ?[]const u8 };

/// Run a review operation. `draft` writes a change note skeleton (0), and the review
/// writes the change review (0, or 3 when `--check` refuses). 2 is usage or host failure.
pub fn run(process: std.process.Init, args: []const []const u8) u8 {
    if (args.len != 0 and std.mem.eql(u8, args[0], "index")) return review_index.run(process, args[1..]);
    if (args.len == 0 or !std.mem.eql(u8, args[0], "draft")) return reviewRun(process, args);
    const options = parseDraft(args) orelse return usageFailure(process);
    var source: loader.Failure = .{};
    return draft(process, options, &source) catch |err| {
        if (err == error.SourceError) return sourceFailure(process, source) catch 2;
        var buffer: [256]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "selka review: {s}\n", .{@errorName(err)}) catch "selka review: host failure\n";
        std.Io.File.stderr().writeStreamingAll(process.io, message) catch return 2;
        return 2;
    };
}

/// Parse the review arguments and compare the project with its base.
fn reviewRun(process: std.process.Init, args: []const []const u8) u8 {
    const options = parseReview(args) orelse return usageFailure(process);
    return reviewCommand(process, options) catch |err| return reviewFailure(process, err);
}

/// Report a review that failed on the host: a missing repository, unreadable files or memory.
fn reviewFailure(process: std.process.Init, err: anyerror) u8 {
    var buffer: [256]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, "selka review: {s}\n", .{@errorName(err)}) catch "selka review: host failure\n";
    std.Io.File.stderr().writeStreamingAll(process.io, message) catch return 2;
    return 2;
}

/// Accept exactly the `release draft` shape without `--date`: `draft PROJECT --name SLUG`.
fn parseDraft(args: []const []const u8) ?release_options.Options {
    if (args.len == 0 or !std.mem.eql(u8, args[0], "draft")) return null;
    const options = release_options.parse(args) catch return null;
    if (options.action != .draft or options.date != null) return null;
    return options;
}

/// Parse the review arguments: one PROJECT, then the flags. Null is a usage error.
fn parseReview(args: []const []const u8) ?Options {
    var options: Options = .{ .project = "" };
    var have_project = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--check")) {
            if (options.check) return null;
            options.check = true;
        } else if (std.mem.eql(u8, arg, "--test")) {
            if (options.run_tests) return null;
            options.run_tests = true;
        } else if (flagValue(args, &index, "--against")) |value| {
            if (options.against != null or !usableRevision(value)) return null;
            options.against = value;
        } else if (flagValue(args, &index, "--head")) |value| {
            if (options.head != null or !usableRevision(value)) return null;
            options.head = value;
        } else if (flagValue(args, &index, "--range")) |value| {
            if (options.range != null) return null;
            options.range = parseRange(value) orelse return null;
        } else if (flagValue(args, &index, "--json")) |value| {
            if (options.json != null or value.len == 0) return null;
            options.json = value;
        } else if (flagValue(args, &index, "--html")) |value| {
            if (options.html != null or value.len == 0) return null;
            options.html = value;
        } else if (arg.len == 0 or arg[0] == '-' or have_project) {
            return null;
        } else {
            options.project = arg;
            have_project = true;
        }
    }
    if (!have_project) return null;
    if (options.range != null and (options.against != null or options.head != null)) return null;
    return options;
}

/// The value of `flag`, as `--flag VALUE` or `--flag=VALUE`, advancing `index` past a separate value.
fn flagValue(args: []const []const u8, index: *usize, flag: []const u8) ?[]const u8 {
    const arg = args[index.*];
    if (std.mem.eql(u8, arg, flag)) {
        if (index.* + 1 >= args.len) return null;
        index.* += 1;
        return args[index.*];
    }
    if (arg.len > flag.len and std.mem.startsWith(u8, arg, flag) and arg[flag.len] == '=') return arg[flag.len + 1 ..];
    return null;
}

/// A revision a review may name: non-empty, and never an option.
fn usableRevision(revision: []const u8) bool {
    return revision.len != 0 and revision[0] != '-';
}

/// Split `A..B` into its two revisions; null unless both are usable.
fn parseRange(text: []const u8) ?Range {
    const separator = std.mem.indexOf(u8, text, "..") orelse return null;
    const base = text[0..separator];
    const head = text[separator + 2 ..];
    if (!usableRevision(base) or !usableRevision(head)) return null;
    return .{ .base = base, .head = head };
}

fn usageFailure(process: std.process.Init) u8 {
    std.Io.File.stderr().writeStreamingAll(process.io, usage) catch return 2;
    return 2;
}

/// Report a host failure that is not a Zig error, such as a repository that does not exist.
fn hostFailure(process: std.process.Init, message: []const u8) !u8 {
    try std.Io.File.stderr().writeStreamingAll(process.io, try std.fmt.allocPrint(process.arena.allocator(), "selka review: {s}\n", .{message}));
    return 2;
}

/// Compare the project with its base and print the review; with `--check`, refuse by exit 3.
/// With `--test`, the head's tests run first and their counts join the review.
fn reviewCommand(process: std.process.Init, options: Options) !u8 {
    const a = process.arena.allocator();
    const directory: []const u8 = std.Io.Dir.cwd().realPathFileAlloc(process.io, options.project, a) catch return hostFailure(process, "PROJECT does not exist or cannot be read");
    var git = try review_git.Git.init(a, process.io, process.environ_map);
    defer git.deinit();
    const top = git.toplevel(directory) catch return hostFailure(process, "PROJECT is not inside a git repository");
    const relative = review_git.projectRelative(top, directory) orelse return hostFailure(process, "PROJECT is not inside its git repository");
    const planned = plan(&git, top, options) catch |err| switch (err) {
        error.GitFailed => return hostFailure(process, "cannot resolve the revisions to compare; check --against, --head and --range"),
        else => return err,
    };
    const base_directory = try git.materialize(top, planned.base, relative);
    var base: review_side.Side = if (base_directory) |path| try review_side.load(process.gpa, a, process.io, path) else .{};
    defer base.deinit();
    const head_directory: ?[]const u8 = if (planned.head) |sha| try git.materialize(top, sha, relative) else directory;
    var head: review_side.Side = if (head_directory) |path| try review_side.load(process.gpa, a, process.io, path) else .{};
    defer head.deinit();
    var review = try review_core.compare(a, .{
        .project = options.project,
        .range = .{ .base = planned.base, .head = planned.head orelse "working tree", .working_tree = planned.head == null },
        .base = &base,
        .head = &head,
    });
    if (options.run_tests) {
        if (head_directory) |path| review.facts.tests_run = try testRun(process, a, path);
    }
    review.facts.attention = try review_attention.build(a, review);
    try std.Io.File.stdout().writeStreamingAll(process.io, try review_output.text(a, review));
    if (options.json != null or options.html != null) {
        const bytes = try review_output.json(a, review);
        if (options.json) |path| std.Io.Dir.cwd().writeFile(process.io, .{ .sub_path = path, .data = bytes }) catch return hostFailure(process, "cannot write the --json file");
        if (options.html) |path| {
            const page = try review_html.review(a, bytes);
            std.Io.Dir.cwd().writeFile(process.io, .{ .sub_path = path, .data = page }) catch return hostFailure(process, "cannot write the --html file");
        }
    }
    return if (options.check and review.refusals.len != 0) 3 else 0;
}

/// Run `selka test` over the head project as a child of this compiler. Its verdict counts
/// come from its summary line, and the tail of its output is kept for the JSON reader. The
/// run is not part of the verdict: a failing test still leaves the review's exit status alone.
fn testRun(process: std.process.Init, a: std.mem.Allocator, directory: []const u8) !review_tests.Run {
    const compiler = try std.process.executablePathAlloc(process.io, a);
    const argv = [_][]const u8{ compiler, "test", "." };
    const result = try std.process.run(a, process.io, .{
        .argv = &argv,
        .cwd = .{ .path = directory },
        .environ_map = process.environ_map,
        .stdout_limit = .limited(32 << 20),
        .stderr_limit = .limited(32 << 20),
    });
    var counted = review_tests.summary(result.stdout);
    if (!counted.found) counted = review_tests.summary(result.stderr);
    const combined = try std.fmt.allocPrint(a, "{s}{s}", .{ result.stdout, result.stderr });
    counted.output_tail = review_tests.tail(combined, review_tests.max_tail_lines);
    return counted;
}

/// The base and head commits. Without `--range`, the base is the merge base of the
/// `--against` reference (default `main`) and the head, which is HEAD unless `--head` names one.
fn plan(git: *const review_git.Git, top: []const u8, options: Options) review_git.Error!Plan {
    if (options.range) |range| return .{ .base = try git.commit(top, range.base), .head = try git.commit(top, range.head) };
    const reference = try git.commit(top, options.against orelse default_reference);
    const head = try git.commit(top, options.head orelse "HEAD");
    return .{ .base = try git.mergeBase(top, reference, head), .head = if (options.head == null) null else head };
}

/// Write the change note skeleton for a change: `draft PROJECT --name SLUG`.
fn draft(process: std.process.Init, options: release_options.Options, source: *loader.Failure) !u8 {
    const a = process.arena.allocator();
    var model = try loader.loadWith(process.gpa, process.io, options.project, source);
    defer model.deinit();
    var report: reports.Report = .{ .allocator = a };
    defer report.deinit();
    // The draft runs no compiler child and reads no release metadata.
    var context: Context = .{ .process = process, .options = options, .model = &model, .metadata = .{}, .report = &report, .compiler = "" };
    const path = try std.fs.path.join(a, &.{ model.options.changes, "unreleased", try std.mem.concat(a, u8, &.{ options.name.?, ".md" }) });
    if (try context.exists(path)) {
        try std.Io.File.stderr().writeStreamingAll(process.io, "selka review: change note already exists; draft never overwrites it\n");
        return 3;
    }
    try context.write(path, skeleton, true);
    try std.Io.File.stdout().writeStreamingAll(process.io, try std.fmt.allocPrint(a, "review draft: wrote {s}; replace the title and Summary placeholders\n", .{path}));
    return 0;
}

/// Report a project whose declarations do not load, naming the file and position of the first diagnostic.
/// A diagnostic located in the release loader's synthesized root names no project file, so it says a project module does not load.
fn sourceFailure(process: std.process.Init, source: loader.Failure) !u8 {
    const line: []const u8 = if (source.present and loader.isSynthesizedRoot(source.path))
        try std.fmt.allocPrint(process.arena.allocator(), "selka review: error[{s}]: a project module does not load: {s}; repair the source before writing a change note\n", .{ source.code, source.message })
    else if (source.present)
        try std.fmt.allocPrint(process.arena.allocator(), "{s}:{d}:{d}: error[{s}]: {s}; repair the source before writing a change note\n", .{ source.path, source.line, source.column, source.code, source.message })
    else
        "selka review: the project's declarations do not load; repair the source before writing a change note\n";
    try std.Io.File.stderr().writeStreamingAll(process.io, line);
    try std.Io.File.stderr().writeStreamingAll(process.io, try source.ruleNote(process.arena.allocator()));
    return 3;
}

test "review arguments take one project and the comparison flags" {
    const parsed = parseReview(&.{ ".", "--against", "main", "--check", "--json=out.json" }).?;
    try std.testing.expectEqualStrings(".", parsed.project);
    try std.testing.expectEqualStrings("main", parsed.against.?);
    try std.testing.expect(parsed.check);
    try std.testing.expectEqualStrings("out.json", parsed.json.?);
    const ranged = parseReview(&.{ "ledger", "--range", "HEAD~1..HEAD" }).?;
    try std.testing.expectEqualStrings("HEAD~1", ranged.range.?.base);
    try std.testing.expectEqualStrings("HEAD", ranged.range.?.head);
}

test "review arguments take --html once, as a separate value or with =" {
    const parsed = parseReview(&.{ ".", "--html", "review.html" }).?;
    try std.testing.expectEqualStrings("review.html", parsed.html.?);
    const joined = parseReview(&.{ ".", "--html=page.html", "--json", "r.json" }).?;
    try std.testing.expectEqualStrings("page.html", joined.html.?);
    try std.testing.expectEqualStrings("r.json", joined.json.?);
    try std.testing.expect(parseReview(&.{ ".", "--html", "a.html", "--html", "b.html" }) == null);
    try std.testing.expect(parseReview(&.{ ".", "--html" }) == null);
}

test "review arguments take --test once" {
    const parsed = parseReview(&.{ ".", "--test", "--check" }).?;
    try std.testing.expect(parsed.run_tests);
    try std.testing.expect(parseReview(&.{ ".", "--test", "--test" }) == null);
}

test "review arguments refuse a range with a reference and an unknown flag" {
    try std.testing.expect(parseReview(&.{ ".", "--range", "A..B", "--against", "main" }) == null);
    try std.testing.expect(parseReview(&.{ ".", "--range", "A" }) == null);
    try std.testing.expect(parseReview(&.{ ".", "--frobnicate" }) == null);
    try std.testing.expect(parseReview(&.{ "a", "b" }) == null);
    try std.testing.expect(parseReview(&.{}) == null);
    try std.testing.expect(parseReview(&.{ ".", "--head", "--check" }) == null);
}
