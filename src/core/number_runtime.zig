//! The Zig number-text runtime. `zig build core` compiles `runtime/core_number_text.zig`
//! once, for x86_64-linux-gnu.2.31 and the baseline CPU (ReleaseFast, PIC, no stack
//! check or protector, with libc), and embeds the object; a build that calls a number
//! helper publishes it in the per-user store and links it. No guest build compiles it.
const std = @import("std");

/// The object `zig build core` compiled.
pub const prebuilt: []const u8 = @embedFile("core_number_text_object");

/// Allocation and filesystem failures share the native driver's errors.
pub const Error = error{ ToolFailed, OutOfMemory, WriteFailed };

/// Whether emitted code actually calls a Zig number helper.
pub fn needed(llvm: []const u8) bool {
    const names = [_][]const u8{ "myl_core_str_from_f64", @import("flags.zig").buffer_float_symbol, "myl_core_format_number", "myl_core_format_float", "myl_core_format_text", "myl_core_parse_float_range", "myl_core_round_float" };
    for (names) |name| if (std.mem.indexOf(u8, llvm, name) != null) return true;
    return false;
}

/// The object's content identity: its store name and its part of a program's key.
pub fn digest() [32]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(prebuilt, &out, .{});
    return out;
}

/// The path of the embedded object in `directory`, written there (a unique partial
/// renamed into place) when it is missing or its bytes differ. No process runs.
pub fn object(allocator: std.mem.Allocator, io: std.Io, directory: []const u8) Error![]const u8 {
    const path = try std.fs.path.join(allocator, &.{ directory, try std.fmt.allocPrint(allocator, "core_number_text-{x}.o", .{digest()}) });
    const cwd = std.Io.Dir.cwd();
    // A missing or unreadable entry is rewritten; a damaged one is never linked.
    const found = cwd.readFileAlloc(io, path, allocator, .limited(prebuilt.len + 1)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
    if (found) |bytes| if (std.mem.eql(u8, bytes, prebuilt)) return path;
    cwd.createDirPath(io, directory) catch return error.WriteFailed;
    var nonce: [16]u8 = undefined;
    std.Io.random(io, &nonce);
    const partial = try std.fmt.allocPrint(allocator, "{s}.{x}.partial", .{ path, nonce });
    defer retireFile(io, partial);
    cwd.writeFile(io, .{ .sub_path = partial, .data = prebuilt }) catch return error.WriteFailed;
    cwd.rename(partial, cwd, path, io) catch return error.WriteFailed;
    return path;
}

fn retireFile(io: std.Io, path: []const u8) void {
    // A published partial already moved away; otherwise discard this invocation's file.
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}
