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
/// Whether any `--link` input is one `zig cc` compiles before it links (C
/// source, say) rather than one it hands the linker as it is
/// (BUILD-LINK-SOURCE-1).
pub fn compiles(context: fs.Context, raw: []const []const u8) fs.Error!bool {
    var forwarded: std.ArrayList([]const u8) = .empty;
    try append(context, raw, &forwarded, true);
    var index: usize = 0;
    while (index + 1 < forwarded.items.len) : (index += 2) {
        if (std.mem.eql(u8, forwarded.items[index], "--link") and !linkerInput(forwarded.items[index + 1])) return true;
    }
    return false;
}
/// Whether `zig cc` passes `path` to the linker unchanged: an object, an
/// archive or a shared library, versioned (`libx.so.1.2`) or not. Every other
/// name counts as compiled, so an unfamiliar extension costs a driver link,
/// never a broken one.
pub fn linkerInput(path: []const u8) bool {
    const name = std.fs.path.basename(path);
    for ([_][]const u8{ ".o", ".a", ".so" }) |extension| if (std.mem.endsWith(u8, name, extension)) return true;
    const version = name[(std.mem.indexOf(u8, name, ".so.") orelse return false) + ".so.".len ..];
    if (version.len == 0) return false;
    for (version) |c| if (!std.ascii.isDigit(c) and c != '.') return false;
    return true;
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
/// The bare switches `build` and `test` accept. The scan must not read the
/// argument after one as its value, or a `--link FILE` written next is lost.
fn boolean(flag: []const u8) bool {
    for ([_][]const u8{
        "--project",     "--library",      "--report",          "--run",          "--force",     "--json",         "--release",    "--lto",
        "--no-cache",    "--keep-symbols", "--step-accounting", "--gc-stress",    "--pure-skip", "--affected",     "--bench-only", "--restrict",
        "--allow-clock", "--allow-host",   "--allow-all",       "--allow-random", "--allow-env", "--print-result",
    }) |name| if (std.mem.eql(u8, flag, name)) return true;
    return false;
}
