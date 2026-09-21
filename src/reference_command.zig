//! `mylang reference --query TERM [--format=text|json]`: compiler-derived facts.
//!
//! The command is a thin shell over `reference.zig`: it parses two flags,
//! asks the engine for an answer, and writes it. The compiler surface is a
//! comptime parameter for the same reason the engine takes one — a file in the
//! executable's root module may not also import the compiler's own files, and
//! `src/main.zig` reaches the compiler as the `mylang` module.

const std = @import("std");
const reference = @import("reference.zig");

/// Usage text for the `reference` subcommand.
pub const usage =
    "usage: mylang reference --query TERM [--format=text|json]\n" ++
    "  Answers from data embedded in this executable: implemented features and their\n" ++
    "  documentation anchors, supported boundaries, unsupported/excluded/removed names,\n" ++
    "  embedded standard-library declarations with their fact status, builtin and\n" ++
    "  collection-method spellings, and curated syntax examples. Matching is a\n" ++
    "  case-insensitive substring of each fact's slug, name, summary or signature; an\n" ++
    "  unmatched term is a normal answer that says so. The command reads nothing from\n" ++
    "  the filesystem or the environment, so it answers outside a source checkout.\n";

/// Host failures this command reports instead of an answer.
pub const Error = error{ OutOfMemory, WriteFailed };

/// The bytes and exit status one invocation produces.
pub const Outcome = struct {
    /// Process status: 0 for an answer, 2 for a malformed request.
    status: u8,
    /// Bytes for stdout, empty when nothing should be written.
    stdout: []const u8,
    /// Bytes for stderr, empty when nothing should be written.
    stderr: []const u8,
};

/// Parsed `reference` flags.
const Options = struct {
    query: []const u8,
    format: reference.Format = .text,
};

/// Report a malformed request rather than answering it.
const ParseError = error{Usage};

/// Read the value of a `--flag VALUE` or `--flag=VALUE` argument.
fn flagValue(args: []const []const u8, index: *usize, prefix: []const u8) ParseError![]const u8 {
    const arg = args[index.*];
    if (std.mem.eql(u8, arg, prefix)) {
        index.* += 1;
        if (index.* >= args.len) return error.Usage;
        return args[index.*];
    }
    if (std.mem.startsWith(u8, arg, prefix) and arg.len > prefix.len and arg[prefix.len] == '=') return arg[prefix.len + 1 ..];
    return error.Usage;
}

/// Parse the accepted flag set, rejecting anything else.
fn parse(args: []const []const u8) ParseError!Options {
    var query: ?[]const u8 = null;
    var format: reference.Format = .text;
    var seen_format = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--query") or std.mem.startsWith(u8, arg, "--query=")) {
            if (query != null) return error.Usage;
            query = try flagValue(args, &index, "--query");
            continue;
        }
        if (std.mem.eql(u8, arg, "--format") or std.mem.startsWith(u8, arg, "--format=")) {
            if (seen_format) return error.Usage;
            const value = try flagValue(args, &index, "--format");
            format = if (std.mem.eql(u8, value, "text")) .text else if (std.mem.eql(u8, value, "json")) .json else return error.Usage;
            seen_format = true;
            continue;
        }
        return error.Usage;
    }
    return .{ .query = query orelse return error.Usage, .format = format };
}

/// Parse `args`, answer the request, and describe what the process should write.
///
/// This is the whole user-facing surface minus the two writes: `run` calls it
/// and writes `Outcome.stdout`/`Outcome.stderr`, so a test can exercise flag
/// parsing, the engine and the exit status without a process.
pub fn answer(comptime language: type, allocator: std.mem.Allocator, args: []const []const u8) Error!Outcome {
    if (args.len == 1 and std.mem.eql(u8, args[0], "--help")) return .{ .status = 0, .stdout = usage, .stderr = "" };
    const options = parse(args) catch return .{ .status = 2, .stdout = "", .stderr = usage };
    const text = reference.run(language, allocator, .{
        .query = options.query,
        .format = options.format,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.EmptyQuery => return .{ .status = 2, .stdout = "", .stderr = "mylang reference: --query TERM must not be empty\n" ++ usage },
    };
    return .{ .status = 0, .stdout = text, .stderr = "" };
}

/// Run the `reference` subcommand, writing its answer to stdout and returning
/// the process status.
pub fn run(comptime language: type, process: std.process.Init, args: []const []const u8) Error!u8 {
    const outcome = try answer(language, process.arena.allocator(), args);
    if (outcome.stdout.len != 0) std.Io.File.stdout().writeStreamingAll(process.io, outcome.stdout) catch return error.WriteFailed;
    if (outcome.stderr.len != 0) std.Io.File.stderr().writeStreamingAll(process.io, outcome.stderr) catch return error.WriteFailed;
    return outcome.status;
}
