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

/// The name `build-env digest` resolves through `lakeCandidates` rather than the live `PATH`: the Lean build tool of the
/// ownership proof (`proofs/ownership`), a developer and gate tool that no build or guest needs.
pub const lake_tool = "lake";

/// Where the Lean build tool may be, in order: `SELKA_LAKE`, then `$HOME/.elan/bin/lake`. Fewer than two when a variable is
/// unset; the caller falls back to `PATH` for the last resort.
pub fn lakeCandidates(a: std.mem.Allocator, selka_lake: ?[]const u8, home: ?[]const u8) std.mem.Allocator.Error![]const []const u8 {
    var found: std.ArrayList([]const u8) = .empty;
    if (selka_lake) |path| if (path.len != 0) try found.append(a, path);
    if (home) |directory| if (directory.len != 0) try found.append(a, try std.fs.path.join(a, &.{ directory, ".elan", "bin", "lake" }));
    return found.items;
}

test "the Lean build tool is looked for in SELKA_LAKE first and in the elan directory of HOME second" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const both = try lakeCandidates(arena.allocator(), "/opt/lean/bin/lake", "/home/dev");
    try std.testing.expectEqual(@as(usize, 2), both.len);
    try std.testing.expectEqualStrings("/opt/lean/bin/lake", both[0]);
    try std.testing.expectEqualStrings("/home/dev/.elan/bin/lake", both[1]);
    const home_only = try lakeCandidates(arena.allocator(), null, "/home/dev");
    try std.testing.expectEqual(@as(usize, 1), home_only.len);
    try std.testing.expectEqual(@as(usize, 0), (try lakeCandidates(arena.allocator(), "", null)).len);
    try std.testing.expectEqualStrings(lake_tool, toolRequest("lake").?.name);
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

/// The placement variable that selects the stage store's shared half (`shared_cache_policy.Tier.stages`).
pub const stage_store_variable = "SELKA_STAGE_SHARED_CACHE";

/// Keep the build graph's children out of the per-user stage store (`~/.cache/selka/stage-artifacts`): when `projected` names no
/// stage store, name none, which disables the shared half. Unset, the compiler's default selects the per-user store, so a test
/// that starts a compiler with the graph's environment would write its records there (round 12: 3,600 files in one gate).
/// A caller that names a store, or an empty one, keeps it. A test about the default or about sharing sets its own variable.
pub fn isolateStageStore(projected: *std.process.Environ.Map) std.mem.Allocator.Error!void {
    if (projected.get(stage_store_variable) == null) try projected.put(stage_store_variable, "");
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
