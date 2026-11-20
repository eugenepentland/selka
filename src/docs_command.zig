//! `selka docs [TOPIC]`: print a user guide built into this executable.
//!
//! An agent working in a project outside the compiler repository has no `docs/`
//! directory to read, so the user guides travel inside the compiler: `build.zig`
//! embeds each page `user_docs.topics` names, and this command lists or prints
//! them. It reads nothing from the filesystem or the environment, so it answers
//! the same from any working directory.
const std = @import("std");
const user_docs = @import("user_docs.zig");

/// Usage text for the `docs` subcommand.
pub const usage =
    \\usage: selka docs [TOPIC]
    \\  with no TOPIC, list the user guides built into this executable;
    \\  with one, print that guide (Markdown) to stdout; a page as a guide links to it
    \\  (`tooling/packages.md#local-locked-packages`, `docs/io.md`) names a topic too
    \\
;

/// The bytes and exit status one invocation produces.
pub const Outcome = struct {
    /// Process status: 0 for a list or a page, 2 for a malformed request.
    status: u8,
    /// Bytes for stdout, empty when nothing should be written.
    stdout: []const u8,
    /// Bytes for stderr, empty when nothing should be written.
    stderr: []const u8,
};

/// Each topic's embedded page, in `user_docs.topics` order.
const pages = pages: {
    var texts: [user_docs.topics.len][]const u8 = undefined;
    for (user_docs.topics, 0..) |topic, index| texts[index] = @embedFile(user_docs.import_prefix ++ topic.name);
    break :pages texts;
};

/// The widest name among the topics of one group (`more` or not), and among the extra listing rows when `more` is
/// false, so each group's summaries line up.
fn widthOf(comptime more: bool) usize {
    var widest: usize = if (more) 0 else "operations".len;
    for (user_docs.topics) |topic| {
        if (topic.more == more) widest = @max(widest, topic.name.len);
    }
    return widest;
}

/// One listing line: two spaces, the name padded to `width`, two spaces and the summary.
fn row(comptime name: []const u8, comptime summary: []const u8, comptime width: usize) []const u8 {
    const spaces: [40]u8 = @splat(' ');
    return "  " ++ name ++ spaces[0 .. width + 2 - name.len] ++ summary ++ "\n";
}

/// What `selka docs` prints with no topic: one line per guide, primer first, then the pages the guides point at.
const listing = listing: {
    @setEvalBranchQuota(100_000);
    var text: []const u8 = "The user guides built into this compiler; `selka docs TOPIC` prints one:\n\n";
    for (user_docs.topics) |topic| {
        if (!topic.more) text = text ++ row(topic.name, topic.summary, widthOf(false));
    }
    text = text ++ row("operations", "the generated table of operation homes (stage 2)", widthOf(false));
    text = text ++ "\nMore pages, which the guides and `selka reference` point at:\n\n";
    for (user_docs.topics) |topic| {
        if (topic.more) text = text ++ row(topic.name, topic.summary, widthOf(true));
    }
    break :listing text ++ "\nNew to selka? Read `selka docs card` before you write a program, then `selka docs primer`. `selka --help` lists the commands.\n";
};

/// The topic names on one line, for the answer to a name that is not one.
const names = names: {
    var text: []const u8 = "";
    for (user_docs.topics, 0..) |topic, index| text = text ++ (if (index == 0) "" else ", ") ++ topic.name;
    text = text ++ ", operations";
    break :names text;
};

/// The embedded page for `name`, or null when no topic has that name. A page's path as the guides link to it
/// (`tooling/packages.md#local-locked-packages`, `docs/io.md`) names its topic as well, so a link can be followed as written.
pub fn page(name: []const u8) ?[]const u8 {
    for (user_docs.topics, pages) |topic, text| if (std.mem.eql(u8, topic.name, name)) return text;
    return pageAt(name);
}

/// The embedded page whose file is the path `spelling` names, with or without a leading `docs/` and an `#anchor`.
fn pageAt(spelling: []const u8) ?[]const u8 {
    const file = spelling[0 .. std.mem.indexOfScalar(u8, spelling, '#') orelse spelling.len];
    if (!std.mem.endsWith(u8, file, ".md")) return null;
    const relative = if (std.mem.startsWith(u8, file, "docs/")) file["docs/".len..] else file;
    for (user_docs.topics, pages) |topic, text| {
        if (std.mem.startsWith(u8, topic.path, "docs/") and std.mem.eql(u8, topic.path["docs/".len..], relative)) return text;
    }
    return null;
}

/// Answer `selka docs ARGS` without writing: the topic list, one page, or a
/// usage error that names the topics. `run` writes what this returns, so a test
/// exercises the whole surface without a process.
pub fn answer(allocator: std.mem.Allocator, args: []const []const u8) error{OutOfMemory}!Outcome {
    if (args.len == 0) return .{ .status = 0, .stdout = listing, .stderr = "" };
    if (args.len == 1 and (std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "-h"))) return .{ .status = 0, .stdout = usage, .stderr = "" };
    if (args.len != 1) return .{ .status = 2, .stdout = "", .stderr = usage };
    if (page(args[0])) |text| return .{ .status = 0, .stdout = text, .stderr = "" };
    const message = try std.fmt.allocPrint(allocator, "selka docs: no topic `{s}`; the topics are {s}\n", .{ args[0], names });
    return .{ .status = 2, .stdout = "", .stderr = message };
}

/// Host failures this command reports instead of an answer.
pub const Error = error{ OutOfMemory, WriteFailed };

/// Run the `docs` subcommand, writing its answer and returning the process status.
pub fn run(process: std.process.Init, args: []const []const u8) Error!u8 {
    const outcome = try answer(process.arena.allocator(), args);
    if (outcome.stdout.len != 0) std.Io.File.stdout().writeStreamingAll(process.io, outcome.stdout) catch return error.WriteFailed;
    if (outcome.stderr.len != 0) std.Io.File.stderr().writeStreamingAll(process.io, outcome.stderr) catch return error.WriteFailed;
    return outcome.status;
}

// spec-case: FIX-MIGRATION-1
test "docs fix prints the fix and migration guide wherever the compiler runs" {
    const guide = try answer(std.testing.allocator, &.{"fix"});
    try std.testing.expectEqual(@as(u8, 0), guide.status);
    try std.testing.expect(std.mem.startsWith(u8, guide.stdout, "# Fixes and migrations"));
    try std.testing.expect(std.mem.indexOf(u8, guide.stdout, "selka fix --check") != null);
}

// spec: CLI-DOCS-1
test "docs lists every topic with the primer first and prints each embedded page" {
    const listed = try answer(std.testing.allocator, &.{});
    try std.testing.expectEqual(@as(u8, 0), listed.status);
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "  primer ").? < std.mem.indexOf(u8, listed.stdout, "  syntax ").?);
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "selka docs primer") != null);
    // Every page is a real Markdown page, not an empty or mislabelled embed.
    for (user_docs.topics) |topic| try std.testing.expect(std.mem.startsWith(u8, page(topic.name).?, "# "));
    try std.testing.expect(std.mem.startsWith(u8, page("primer").?, "# selka in one page"));
    try std.testing.expect(std.mem.indexOf(u8, (try answer(std.testing.allocator, &.{"build"})).stdout, "--release") != null);
    // A name that is no topic is a usage error that lists the topics.
    const unknown = try answer(std.testing.allocator, &.{"sytnax"});
    defer std.testing.allocator.free(unknown.stderr);
    try std.testing.expectEqual(@as(u8, 2), unknown.status);
    try std.testing.expect(std.mem.indexOf(u8, unknown.stderr, "no topic `sytnax`; the topics are primer, card, syntax,") != null);
    try std.testing.expectEqual(@as(u8, 2), (try answer(std.testing.allocator, &.{ "primer", "syntax" })).status);
    try std.testing.expectEqualStrings(usage, (try answer(std.testing.allocator, &.{"--help"})).stdout);
}

// spec-case: CLI-DOCS-1
test "docs prints the language card, and the card stays at most 6000 characters" {
    const card = page("card").?;
    try std.testing.expect(std.mem.startsWith(u8, card, "# Selka on a card"));
    try std.testing.expect(card.len <= 6000);
    const listed = try answer(std.testing.allocator, &.{});
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "  card ") != null);
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "read before writing Selka") != null);
    try std.testing.expectEqualStrings(card, (try answer(std.testing.allocator, &.{"card"})).stdout);
}

// spec-case: CLI-DOCS-1
test "docs topic summaries name no retired form" {
    const listed = try answer(std.testing.allocator, &.{});
    try std.testing.expectEqual(@as(u8, 0), listed.status);
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "reference counting") == null);
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "copy-on-write") == null);
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "def, keyword") == null);
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "comprehensions") == null);
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "module headers") == null);
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "effect ceilings") == null);
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "func, keyword arguments") != null);
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "Result, Option, `try`") != null);
}

// spec-case: CLI-DOCS-1
test "docs prints the sets guide under its own topic" {
    try std.testing.expect(std.mem.startsWith(u8, page("sets").?, "# Sets"));
    const listed = try answer(std.testing.allocator, &.{});
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "  sets ") != null);
}

// spec-case: CLI-DOCS-1
test "docs prints the concurrency guide, which opens with the four task rules, and the card points to it" {
    const guide = try answer(std.testing.allocator, &.{"concurrency"});
    try std.testing.expectEqual(@as(u8, 0), guide.status);
    try std.testing.expect(std.mem.startsWith(u8, guide.stdout, "# Concurrency\n"));
    // The rules a first-time writer needs sit before the first section on task groups.
    const opening = guide.stdout[0..std.mem.indexOf(u8, guide.stdout, "## Task groups").?];
    try std.testing.expect(std.mem.indexOf(u8, opening, "E_TASK_CAPABILITY") != null);
    try std.testing.expect(std.mem.indexOf(u8, opening, "E_TASK_MUT") != null);
    try std.testing.expect(std.mem.indexOf(u8, opening, "E_TASK_HANDLE") != null);
    try std.testing.expect(std.mem.indexOf(u8, opening, "parallel.map") != null);
    try std.testing.expect(std.mem.indexOf(u8, opening, "--threads N") != null);
    try std.testing.expect(std.mem.indexOf(u8, opening, "SELKA_THREADS") != null);
    const listed = try answer(std.testing.allocator, &.{});
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "  concurrency ") != null);
    const card = page("card").?;
    try std.testing.expect(std.mem.indexOf(u8, card, "`concurrency`") != null);
    try std.testing.expect(std.mem.indexOf(u8, card, "nothing in a `build --release` executable") != null);
}

// spec-case: CLI-DOCS-1
test "docs prints the logging guide, which names the module's functions, and lists the topic" {
    const guide = try answer(std.testing.allocator, &.{"logging"});
    try std.testing.expectEqual(@as(u8, 0), guide.status);
    try std.testing.expect(std.mem.startsWith(u8, guide.stdout, "# Logging\n"));
    try std.testing.expect(std.mem.indexOf(u8, guide.stdout, "logging.new(err)") != null);
    try std.testing.expect(std.mem.indexOf(u8, guide.stdout, "logging.parse_level") != null);
    const listed = try answer(std.testing.allocator, &.{});
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "  logging ") != null);
}

test "docs prints the change review guide under its own topic" {
    try std.testing.expect(std.mem.startsWith(u8, page("change-review").?, "# Change review\n"));
    const listed = try answer(std.testing.allocator, &.{});
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "  change-review ") != null);
}

// spec-case: CLI-DOCS-1
test "docs api prints the interface-files guide" {
    const listed = try answer(std.testing.allocator, &.{});
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "  api ") != null);
    const guide = try answer(std.testing.allocator, &.{"api"});
    try std.testing.expectEqual(@as(u8, 0), guide.status);
    try std.testing.expect(std.mem.startsWith(u8, guide.stdout, "# Interface files\n"));
}

/// A repository-relative path built one segment at a time, so a link's `..` and `.` resolve against the page it is on.
const PagePath = struct {
    bytes: [256]u8 = undefined,
    len: usize = 0,

    fn push(self: *PagePath, segment: []const u8) void {
        if (segment.len == 0 or std.mem.eql(u8, segment, ".")) return;
        if (std.mem.eql(u8, segment, "..")) {
            self.len = std.mem.lastIndexOfScalar(u8, self.bytes[0..self.len], '/') orelse 0;
            return;
        }
        if (self.len != 0) {
            self.bytes[self.len] = '/';
            self.len += 1;
        }
        @memcpy(self.bytes[self.len..][0..segment.len], segment);
        self.len += segment.len;
    }

    fn slice(self: *const PagePath) []const u8 {
        return self.bytes[0..self.len];
    }
};

/// The repository-relative file a link on the page at `from` names, or null for a link that is not a file of the
/// repository: a URL, a mail address or an anchor inside the page.
fn linkedFile(link: []const u8, from: []const u8) ?PagePath {
    if (link.len == 0 or link[0] == '#') return null;
    if (std.mem.indexOf(u8, link, "://") != null or std.mem.startsWith(u8, link, "mailto:")) return null;
    var path: PagePath = .{};
    var folders = std.mem.splitScalar(u8, from[0 .. std.mem.lastIndexOfScalar(u8, from, '/') orelse 0], '/');
    while (folders.next()) |folder| path.push(folder);
    var segments = std.mem.splitScalar(u8, link[0 .. std.mem.indexOfScalar(u8, link, '#') orelse link.len], '/');
    while (segments.next()) |segment| path.push(segment);
    return path;
}

/// Append the target of every Markdown link on one line of prose: `[text](target)` outside a code span, and a
/// reference definition `[name]: target` that starts the line.
fn linksOnLine(allocator: std.mem.Allocator, found: *std.ArrayList([]const u8), line: []const u8) error{OutOfMemory}!void {
    const trimmed = std.mem.trimStart(u8, line, " ");
    if (std.mem.startsWith(u8, trimmed, "[")) {
        if (std.mem.indexOf(u8, trimmed, "]: ")) |at| {
            var words = std.mem.tokenizeScalar(u8, trimmed[at + 3 ..], ' ');
            if (words.next()) |target| try found.append(allocator, target);
        }
    }
    var in_code = false;
    var index: usize = 0;
    while (index < line.len) : (index += 1) {
        if (line[index] == '`') in_code = !in_code;
        if (in_code or !std.mem.startsWith(u8, line[index..], "](")) continue;
        const close = std.mem.indexOfScalarPos(u8, line, index, ')') orelse return;
        var words = std.mem.tokenizeScalar(u8, line[index + 2 .. close], ' ');
        if (words.next()) |target| try found.append(allocator, target);
    }
}

/// Append the target of every Markdown link in `text`, leaving out fenced code blocks.
fn linksIn(allocator: std.mem.Allocator, found: *std.ArrayList([]const u8), text: []const u8) error{OutOfMemory}!void {
    var in_fence = false;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, line, " "), "```")) in_fence = !in_fence else if (!in_fence) try linksOnLine(allocator, found, line);
    }
}

/// One line, `TOPIC: LINK`, for every link in every embedded guide whose file no topic prints, in topic order; how
/// many links were read goes to `checked`. The file may be missing from the repository as well: that is unreadable too.
fn unreadableLinks(arena: std.mem.Allocator, checked: *usize) error{OutOfMemory}![]const []const u8 {
    var unreadable: std.ArrayList([]const u8) = .empty;
    for (user_docs.topics, pages) |topic, text| {
        var links: std.ArrayList([]const u8) = .empty;
        try linksIn(arena, &links, text);
        for (links.items) |link| {
            const file = linkedFile(link, topic.path) orelse continue;
            checked.* += 1;
            if (user_docs.topicForPath(file.slice()) == null) try unreadable.append(arena, try std.fmt.allocPrint(arena, "{s}: {s}", .{ topic.name, link }));
        }
    }
    return unreadable.items;
}

/// The lines, one to a row, so a test that compares two lists shows the rows that differ.
fn rows(arena: std.mem.Allocator, lines: []const []const u8) error{OutOfMemory}![]const u8 {
    return std.mem.join(arena, "\n", lines);
}

// spec-case: CLI-DOCS-1
test "no guide that selka docs prints links to a file that selka docs cannot print" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var checked: usize = 0;
    const unreadable = try unreadableLinks(arena.allocator(), &checked);
    // The scan reads the file links of every page (the guides hold about 290), not none.
    try std.testing.expect(checked > 250);
    try std.testing.expectEqualStrings("", try rows(arena.allocator(), unreadable));
}

// spec-case: CLI-DOCS-1
test "a link is resolved against its page, and a URL, an anchor or a code span is not a link" {
    try std.testing.expectEqualStrings("docs/tooling/sample.md", linkedFile("sample.md#top", "docs/tooling/guide.md").?.slice());
    try std.testing.expectEqualStrings("docs/sample.md", linkedFile("../sample.md", "docs/tooling/guide.md").?.slice());
    try std.testing.expectEqualStrings("examples/a.selka", linkedFile("../../examples/a.selka", "docs/tooling/guide.md").?.slice());
    try std.testing.expect(linkedFile("#section", "docs/guide.md") == null);
    try std.testing.expect(linkedFile("https://example.com/x.md", "docs/guide.md") == null);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var found: std.ArrayList([]const u8) = .empty;
    try linksIn(arena.allocator(), &found, "see [a](a.md) and `xs[i](b.md)` and [c](c.md#x \"title\")\n```\n[d](d.md)\n```\n[e]: e.md\n");
    try std.testing.expectEqual(@as(usize, 3), found.items.len);
    try std.testing.expectEqualStrings("a.md", found.items[0]);
    try std.testing.expectEqualStrings("c.md#x", found.items[1]);
    try std.testing.expectEqualStrings("e.md", found.items[2]);
}

// spec-case: CLI-DOCS-1
test "docs prints the packages and integer-operations guides, which the guides and the reference point at" {
    const packages = try answer(std.testing.allocator, &.{"packages"});
    try std.testing.expectEqual(@as(u8, 0), packages.status);
    try std.testing.expect(std.mem.startsWith(u8, packages.stdout, "# Local packages\n"));
    const integers = try answer(std.testing.allocator, &.{"integer-operations"});
    try std.testing.expectEqual(@as(u8, 0), integers.status);
    try std.testing.expect(std.mem.indexOf(u8, integers.stdout, "wrapping_add") != null);
    const listed = try answer(std.testing.allocator, &.{});
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "  packages ") != null);
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "  integer-operations ") != null);
    // The pages the guides point at come after the guides, under their own heading.
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "  fix ").? < std.mem.indexOf(u8, listed.stdout, "More pages").?);
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "More pages").? < std.mem.indexOf(u8, listed.stdout, "  value-semantics ").?);
}

/// `path` without its first folder: the spelling of a page as a guide links to it.
fn withoutRoot(path: []const u8) []const u8 {
    return path[(std.mem.indexOfScalar(u8, path, '/') orelse return path) + 1 ..];
}

/// The path of the page `topic` prints, as the topic table names it.
fn pathOf(topic: []const u8) []const u8 {
    for (user_docs.topics) |entry| {
        if (std.mem.eql(u8, entry.name, topic)) return entry.path;
    }
    return "";
}

// spec-case: CLI-DOCS-1
test "docs takes a page as a guide links to it: with or without docs/ and an anchor" {
    const packages = (try answer(std.testing.allocator, &.{"packages"})).stdout;
    const path = pathOf("packages");
    var anchored: [160]u8 = undefined;
    const with_anchor = try std.fmt.bufPrint(&anchored, "{s}#local-locked-packages", .{path});
    try std.testing.expectEqualStrings(packages, (try answer(std.testing.allocator, &.{withoutRoot(path)})).stdout);
    try std.testing.expectEqualStrings(packages, (try answer(std.testing.allocator, &.{with_anchor})).stdout);
    try std.testing.expectEqualStrings(page("syntax").?, (try answer(std.testing.allocator, &.{withoutRoot(pathOf("syntax"))})).stdout);
    // A page with no topic, and a name that is neither, are still refused.
    const missing = try answer(std.testing.allocator, &.{"sample/no-page.md"});
    defer std.testing.allocator.free(missing.stderr);
    try std.testing.expectEqual(@as(u8, 2), missing.status);
}
