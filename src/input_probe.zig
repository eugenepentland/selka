//! Refusing an unusable command-line input by name. A missing, unreadable or
//! wrong-kind entry path is a usage failure, not a host fault: every command
//! that takes one reports it with the same sentence and exit status instead of
//! a generic host-failure line.
const std = @import("std");

/// The exit status of a command whose input could not be used, the same as
/// every other usage failure.
pub const refused_status: u8 = 2;

/// Everything opening and inspecting one input can fail with.
pub const ProbeError = std.Io.File.OpenError || std.Io.File.StatError;

/// What a readable command-line input path names.
pub const Kind = enum { file, directory };

/// The reason a path could not be used, worded for a person. An error this
/// table does not know is spelled by name so nothing is hidden.
pub fn reason(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => "no such file or directory",
        error.NotDir => "a parent of the path is not a directory",
        error.AccessDenied, error.PermissionDenied => "permission denied",
        error.IsDir => "is a directory, not a file",
        error.FileTooBig, error.StreamTooLong => "the file is too large",
        error.NameTooLong => "the path is too long",
        error.SymLinkLoop => "too many levels of symbolic links",
        error.BadPathName, error.InvalidUtf8 => "the path is not valid",
        else => @errorName(err),
    };
}

/// Open `path` for reading and report whether it names a file or a directory.
/// Fails with the open error, so a caller words it through `reason`.
pub fn probe(io: std.Io, path: []const u8) ProbeError!Kind {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const stat = try file.stat(io);
    return if (stat.kind == .directory) .directory else .file;
}

/// The refusal sentence for one input: `mylang <command>: cannot read '<path>':
/// <reason>`, newline-terminated, in caller-owned memory.
pub fn refusal(allocator: std.mem.Allocator, command: []const u8, path: []const u8, why: []const u8) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(allocator, "mylang {s}: cannot read '{s}': {s}\n", .{ command, path, why });
}

/// Check that `path` can be used as a file input, or, with `allow_directory`,
/// as a directory too. Returns the refusal sentence when it cannot, or null
/// when the command may go on to read it.
pub fn check(allocator: std.mem.Allocator, io: std.Io, command: []const u8, path: []const u8, allow_directory: bool) std.mem.Allocator.Error!?[]u8 {
    const kind = probe(io, path) catch |err| {
        const sentence = try refusal(allocator, command, path, reason(err));
        return sentence;
    };
    if (kind != .directory or allow_directory) return null;
    const sentence = try refusal(allocator, command, path, reason(error.IsDir));
    return sentence;
}
