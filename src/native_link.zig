//! Explicit native link inputs shared by the build and test drivers.
const std = @import("std");
const library_flag = "--link-library";
const fs = @import("qbe_build_io.zig");
/// Supported link controls always take one value and may be repeated.
pub fn isFlag(flag: []const u8) bool {
    return std.mem.eql(u8, flag, "--link") or std.mem.eql(u8, flag, library_flag) or std.mem.eql(u8, flag, "--library-path");
}
/// Do not let a library name or path become an additional compiler option.
pub fn valid(flag: []const u8, value: []const u8) bool {
    if (value.len == 0 or value[0] == '-') return false;
    if (std.mem.eql(u8, flag, library_flag)) for (value) |c| {
        const punctuation = c == '_' or c == '-' or c == '.';
        if (!std.ascii.isAlphanumeric(c) and !punctuation) return false;
    };
    return true;
}
/// Whether the raw arguments name any explicit native link input. A reuse
/// decision asks this because a link-input file can change without changing the
/// guest objects, so a cached executable cannot be trusted across it.
pub fn hasInputs(raw: []const []const u8) bool {
    var index: usize = 0;
    while (index < raw.len) : (index += 1) {
        const argument = raw[index];
        if (std.mem.eql(u8, argument, "--")) break;
        if (!std.mem.startsWith(u8, argument, "-")) continue;
        const split = std.mem.indexOfScalar(u8, argument, '=') orelse argument.len;
        if (boolean(argument[0..split])) continue;
        if (isFlag(argument[0..split])) return true;
    }
    return false;
}
/// Preserve input order and resolve paths before forwarding to another process.
pub fn append(context: fs.Context, raw: []const []const u8, output: *std.ArrayList([]const u8), forwarding: bool) fs.Error!void {
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        const arg = raw[i];
        if (std.mem.eql(u8, arg, "--")) break;
        if (!std.mem.startsWith(u8, arg, "-")) continue;
        const split = std.mem.indexOfScalar(u8, arg, '=') orelse arg.len;
        const flag = arg[0..split];
        if (boolean(flag)) continue;
        const value = if (split < arg.len) arg[split + 1 ..] else value: {
            i += 1;
            if (i >= raw.len) break;
            break :value raw[i];
        };
        if (!isFlag(flag)) continue;
        const library = std.mem.eql(u8, flag, library_flag);
        const path = if (library) value else try context.absolute(value);
        if (forwarding) {
            try output.appendSlice(context.allocator, &.{ flag, path });
        } else if (std.mem.eql(u8, flag, "--link")) {
            try output.append(context.allocator, path);
        } else {
            try output.append(context.allocator, try std.fmt.allocPrint(context.allocator, "{s}{s}", .{ if (library) "-l" else "-L", path }));
        }
    }
}
fn boolean(flag: []const u8) bool {
    for ([_][]const u8{ "--project", "--library", "--report", "--run", "--force", "--json" }) |name| if (std.mem.eql(u8, flag, name)) return true;
    return false;
}
