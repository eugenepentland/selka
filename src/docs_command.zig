//! `mylang docs [TOPIC]`: print a user guide built into this executable.
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
    \\usage: mylang docs [TOPIC]
    \\  with no TOPIC, list the user guides built into this executable;
    \\  with one, print that guide (Markdown) to stdout
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

/// The widest topic name, so the listing's summaries line up.
const name_width = width: {
    var widest: usize = 0;
    for (user_docs.topics) |topic| widest = @max(widest, topic.name.len);
    break :width widest;
};

/// What `mylang docs` prints with no topic: one line per guide, primer first.
const listing = listing: {
    @setEvalBranchQuota(100_000);
    const spaces = "                ";
    var text: []const u8 = "The user guides built into this compiler; `mylang docs TOPIC` prints one:\n\n";
    for (user_docs.topics) |topic| {
        text = text ++ "  " ++ topic.name ++ spaces[0 .. name_width + 2 - topic.name.len] ++ topic.summary ++ "\n";
    }
    break :listing text ++ "\nNew to mylang? Start with `mylang docs primer`. `mylang --help` lists the commands.\n";
};

/// The topic names on one line, for the answer to a name that is not one.
const names = names: {
    var text: []const u8 = "";
    for (user_docs.topics, 0..) |topic, index| text = text ++ (if (index == 0) "" else ", ") ++ topic.name;
    break :names text;
};

/// The embedded page for `name`, or null when no topic has that name.
pub fn page(name: []const u8) ?[]const u8 {
    for (user_docs.topics, pages) |topic, text| if (std.mem.eql(u8, topic.name, name)) return text;
    return null;
}

/// Answer `mylang docs ARGS` without writing: the topic list, one page, or a
/// usage error that names the topics. `run` writes what this returns, so a test
/// exercises the whole surface without a process.
pub fn answer(allocator: std.mem.Allocator, args: []const []const u8) error{OutOfMemory}!Outcome {
    if (args.len == 0) return .{ .status = 0, .stdout = listing, .stderr = "" };
    if (args.len == 1 and (std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "-h"))) return .{ .status = 0, .stdout = usage, .stderr = "" };
    if (args.len != 1) return .{ .status = 2, .stdout = "", .stderr = usage };
    if (page(args[0])) |text| return .{ .status = 0, .stdout = text, .stderr = "" };
    const message = try std.fmt.allocPrint(allocator, "mylang docs: no topic `{s}`; the topics are {s}\n", .{ args[0], names });
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

// spec: CLI-DOCS-1
test "docs lists every topic with the primer first and prints each embedded page" {
    const listed = try answer(std.testing.allocator, &.{});
    try std.testing.expectEqual(@as(u8, 0), listed.status);
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "  primer ").? < std.mem.indexOf(u8, listed.stdout, "  syntax ").?);
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "mylang docs primer") != null);
    // Every page is a real Markdown page, not an empty or mislabelled embed.
    for (user_docs.topics) |topic| try std.testing.expect(std.mem.startsWith(u8, page(topic.name).?, "# "));
    try std.testing.expect(std.mem.startsWith(u8, page("primer").?, "# mylang in one page"));
    try std.testing.expect(std.mem.indexOf(u8, (try answer(std.testing.allocator, &.{"build"})).stdout, "--release") != null);
    // A name that is no topic is a usage error that lists the topics.
    const unknown = try answer(std.testing.allocator, &.{"sytnax"});
    defer std.testing.allocator.free(unknown.stderr);
    try std.testing.expectEqual(@as(u8, 2), unknown.status);
    try std.testing.expect(std.mem.indexOf(u8, unknown.stderr, "no topic `sytnax`; the topics are primer, syntax,") != null);
    try std.testing.expectEqual(@as(u8, 2), (try answer(std.testing.allocator, &.{ "primer", "syntax" })).status);
    try std.testing.expectEqualStrings(usage, (try answer(std.testing.allocator, &.{"--help"})).stdout);
}

// spec-case: CLI-DOCS-1
test "docs prints the sets guide under its own topic" {
    try std.testing.expect(std.mem.startsWith(u8, page("sets").?, "# Sets"));
    const listed = try answer(std.testing.allocator, &.{});
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "  sets ") != null);
}

// spec-case: CLI-DOCS-1
test "docs api prints the interface-files guide" {
    const listed = try answer(std.testing.allocator, &.{});
    try std.testing.expect(std.mem.indexOf(u8, listed.stdout, "  api ") != null);
    const guide = try answer(std.testing.allocator, &.{"api"});
    try std.testing.expectEqual(@as(u8, 0), guide.status);
    try std.testing.expect(std.mem.startsWith(u8, guide.stdout, "# Interface files\n"));
}
