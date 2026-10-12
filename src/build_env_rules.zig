//! The pure half of the `build-env` host tool (`build_env.zig`), which the
//! build graph runs to key and to project the environment of its test steps
//! (ENV-PROJECTION-1, ENV-PROJECTION-2). It parses the tool's command line,
//! projects an environment map and renders the environment manifest; the tool
//! itself only reads the live environment, hashes files and replaces its own
//! process. Both halves classify variables through `environment_identity.zig`
//! with host semantics: the manifest keys the keyed and host classes, and a
//! child receives every variable that is not dropped ("run what you key").
const std = @import("std");
const identity = @import("environment_identity.zig");

/// The digest recorded for a named tool that is not on `PATH` or cannot be read,
/// so a tool that appears or disappears still changes the manifest.
pub const absent_tool = "absent";

/// A parsed `build-env` command line (the arguments after the program name).
pub const Command = union(enum) {
    /// `digest OUT TOOL...`: write the host environment manifest to `out`,
    /// naming each `TOOL` (`NAME=PATH`, or a bare `NAME` resolved on `PATH`).
    digest: struct { out: []const u8, tools: []const []const u8 },
    /// `project -- CMD ARGS...`: replace this process with `CMD ARGS...`,
    /// keeping only the variables a child may receive.
    project: []const []const u8,
};

/// One `TOOL` argument of `build-env digest`: the tool's name and the file to
/// hash, or null when the tool is resolved on the live `PATH`.
pub const ToolRequest = struct { name: []const u8, path: ?[]const u8 };

/// The command `args` spell, or null for a malformed command line: an unknown
/// command, `digest` without an output path or with a malformed tool, or
/// `project` without `--` and a command.
pub fn parse(args: []const []const u8) ?Command {
    if (args.len == 0) return null;
    if (std.mem.eql(u8, args[0], "digest")) {
        if (args.len < 2 or args[1].len == 0) return null;
        for (args[2..]) |tool| if (toolRequest(tool) == null) return null;
        return .{ .digest = .{ .out = args[1], .tools = args[2..] } };
    }
    if (std.mem.eql(u8, args[0], "project")) {
        if (args.len < 3 or !std.mem.eql(u8, args[1], "--") or args[2].len == 0) return null;
        return .{ .project = args[2..] };
    }
    return null;
}

/// Split one `TOOL` argument: `NAME=PATH` names the file, a bare `NAME` asks
/// for a `PATH` search. Null when the name is empty or contains `/`, or the
/// path after `=` is empty.
pub fn toolRequest(argument: []const u8) ?ToolRequest {
    const name, const path = if (std.mem.cutScalar(u8, argument, '=')) |parts| parts else .{ argument, null };
    if (name.len == 0 or std.mem.indexOfScalar(u8, name, '/') != null) return null;
    if (path) |file| if (file.len == 0) return null;
    return .{ .name = name, .path = path };
}

/// Whether a child of the build graph receives the variable `name`: the
/// keyed, host and placement classes, never the dropped one.
pub fn passes(name: []const u8) bool {
    return identity.passedThrough(name);
}

/// Whether `NAME=VALUE` of the variable `name` enters the build graph's
/// environment manifest: the keyed and host classes.
pub fn keys(name: []const u8) bool {
    return identity.hostKeyed(name);
}

/// Copy into `projected` every variable of `live` a child may receive
/// (`passes`); the dropped ones are left out.
pub fn project(live: *const std.process.Environ.Map, projected: *std.process.Environ.Map) std.mem.Allocator.Error!void {
    var entries = live.iterator();
    while (entries.next()) |entry| {
        if (passes(entry.key_ptr.*)) try projected.put(entry.key_ptr.*, entry.value_ptr.*);
    }
}

/// Write the environment manifest of `variables` and `tools`: the host-scope
/// digest (`environment_identity.digest(.host, …)`) on the first line, then
/// one `NAME=VALUE` line for every keyed or host variable and one
/// `tool:NAME=DIGEST` line for every tool, each in bytewise name order. Values
/// escape `\` and line feeds as `\\` and `\n`, so every entry is one line; only
/// the first line is an identity, the rest explains a changed one. Both slices
/// are sorted in place.
pub fn writeManifest(writer: *std.Io.Writer, variables: []identity.Variable, tools: []identity.Tool) std.Io.Writer.Error!void {
    const digest = identity.digest(.host, variables, tools);
    try writer.print("{s}\n", .{&digest});
    for (variables) |variable| {
        if (!keys(variable.name)) continue;
        try writer.print("{s}=", .{variable.name});
        try writeEscaped(writer, variable.value);
        try writer.writeByte('\n');
    }
    for (tools) |tool| try writer.print("tool:{s}={s}\n", .{ tool.name, tool.digest });
}

/// `value` with `\` and line feeds escaped as `\\` and `\n`.
fn writeEscaped(writer: *std.Io.Writer, value: []const u8) std.Io.Writer.Error!void {
    for (value) |byte| switch (byte) {
        '\\' => try writer.writeAll("\\\\"),
        '\n' => try writer.writeAll("\\n"),
        else => try writer.writeByte(byte),
    };
}

/// The variables of `map` as `environment_identity.Variable`s, in `buffer`.
pub fn variablesOf(map: *const std.process.Environ.Map, buffer: []identity.Variable) []identity.Variable {
    std.debug.assert(buffer.len >= map.count());
    for (map.keys(), map.values(), 0..) |name, value, index| buffer[index] = .{ .name = name, .value = value };
    return buffer[0..map.count()];
}
