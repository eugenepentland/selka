//! The Zig number-text runtime. `zig build core` compiles `runtime/core_number_text.zig`
//! once, for x86_64-linux-gnu.2.31 and the skylake CPU model (AVX2, the one supported target, see `target.zig`;
//! ReleaseFast, PIC, no stack check or protector, with libc), and embeds the object; a build that calls a number
//! helper publishes it in the per-user store and links it. No guest build compiles it.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");

/// The object `zig build core` compiled.
pub const prebuilt: []const u8 = @embedFile("core_number_text_object");

/// Allocation and filesystem failures share the native driver's errors.
pub const Error = error{ ToolFailed, OutOfMemory, WriteFailed };

/// Whether emitted code actually calls a Zig number helper. Every helper's name starts with
/// the runtime prefix, and the prefix cannot overlap itself, so one pass over its occurrences
/// finds every occurrence of every name: seven separate scans of a multi-megabyte unit were
/// the largest part of the Debug compiler's emission cost.
pub fn needed(llvm: []const u8) bool {
    return firstNeeded(llvm) != null;
}

/// The first number helper emitted code calls (`needed`), or null when it calls none.
pub fn firstNeeded(llvm: []const u8) ?[]const u8 {
    const prefix = "myl_core_";
    const names = [_][]const u8{
        "myl_core_str_from_f64",           @import("flags.zig").buffer_float_symbol,
        "myl_core_str_from_f32",           "myl_core_format_float32",
        "myl_core_parse_f32_range",        "myl_core_span_parse_f32_range",
        "myl_core_format_number",          "myl_core_format_float",
        "myl_core_format_text",            "myl_core_parse_float_range",
        "myl_core_span_parse_float_range", "myl_core_round_float",
        "myl_core_format_len",             "myl_core_format_append",
        "myl_core_format_print",           "myl_core_format_write",
        "myl_core_print_f64",              "myl_core_str_append_f64",
        "myl_core_format_octets_print",    "myl_core_format_octets_append",
        "myl_core_format_octets_len",      "myl_core_bytes_blake3",
        "myl_core_span_bytes_blake3",
    };
    comptime for (names) |name| std.debug.assert(std.mem.startsWith(u8, name, prefix));
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, llvm, from, prefix)) |at| {
        inline for (names) |name| if (std.mem.startsWith(u8, llvm[at..], name)) return name;
        from = at + prefix.len;
    }
    return null;
}

/// What a program used, in its own terms, when it calls the number helper `symbol` (`firstNeeded`): float text (a float
/// written as text or read from it), BLAKE3, or a format specification.
pub fn describe(symbol: []const u8) []const u8 {
    if (std.mem.indexOf(u8, symbol, "blake3") != null) return "BLAKE3";
    for ([_][]const u8{ "f64", "f32", "float" }) |piece| if (std.mem.indexOf(u8, symbol, piece) != null) return "float text";
    return "a format specification";
}

test "the number helpers name what a program used" {
    try std.testing.expectEqualStrings("myl_core_str_from_f64", firstNeeded("call ptr @myl_core_str_from_f64(double %x)").?);
    try std.testing.expect(firstNeeded("call ptr @myl_core_str_from_i64(i64 %x)") == null);
    try std.testing.expectEqualStrings("float text", describe("myl_core_str_from_f64"));
    try std.testing.expectEqualStrings("BLAKE3", describe("myl_core_span_bytes_blake3"));
    try std.testing.expectEqualStrings("a format specification", describe("myl_core_format_text"));
}

/// The object's content identity: its store name and its part of a program's key.
pub fn digest() [32]u8 {
    var out: [32]u8 = undefined;
    fast_blake3.hash(prebuilt, &out);
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
