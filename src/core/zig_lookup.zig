//! Where the compiler finds the Zig it drives (`zig cc` compiles and links every guest program).
//!
//! The order, first match wins: `--zig PATH` (the command line, handled by the argument parser), `SELKA_ZIG`, the Zig the
//! release bundles at `<install>/lib/selka/zig/zig`, `ZIG`, then `zig` on `PATH`. `<install>` is the parent of the folder
//! that holds the running executable, with symlinks resolved, so a link in `~/.local/bin` still finds the install it
//! points into. A variable that is set and empty counts as not set. Nothing here decides whether a Zig is the reviewed one:
//! `tool_identity.zig` does, from the files, and a bundled official distribution passes it like any other.
const std = @import("std");
const product = @import("selka").product;

/// The bundled Zig, relative to the install prefix.
pub const bundled_subpath = "lib/" ++ product.user_dir ++ "/zig/zig";

/// The line that follows `cannot identify guest toolchain: ToolNotFound`: where Zig comes from.
pub const not_found_hint = "error: no Zig found: install Zig 0.17.1 from https://ziglang.org/download/ and put it on PATH " ++
    "(or name it with --zig PATH or SELKA_ZIG), or use the Selka release that bundles it\n";

/// The extra line for the toolchain error `err`: the hint for a missing Zig, nothing for another failure.
pub fn hintFor(err: anyerror) []const u8 {
    return if (err == error.ToolNotFound) not_found_hint else "";
}

/// The first of the three that is set and not empty, in the order the compiler looks: the `SELKA_ZIG` value, the bundled
/// Zig, the `ZIG` value; `zig` (searched on `PATH`) when none is.
pub fn choose(selka_zig: ?[]const u8, install: ?[]const u8, zig: ?[]const u8) []const u8 {
    for ([_]?[]const u8{ selka_zig, install, zig }) |candidate| if (candidate) |path| if (path.len != 0) return path;
    return "zig";
}

/// The bundled Zig of an install whose executable sits in `executable_dir`, when it is a file that can be run.
pub fn bundledBeside(io: std.Io, a: std.mem.Allocator, executable_dir: []const u8) ?[]const u8 {
    const install = std.fs.path.dirname(executable_dir) orelse return null;
    const path = std.fs.path.join(a, &.{ install, bundled_subpath }) catch return null;
    const info = std.Io.Dir.cwd().statFile(io, path, .{}) catch return null;
    if (info.kind != .file) return null;
    std.Io.Dir.cwd().access(io, path, .{ .execute = true }) catch return null;
    return path;
}

/// The Zig the running compiler's own install bundles, or null (no bundle, or the executable's place is unknown).
pub fn bundled(io: std.Io, a: std.mem.Allocator) ?[]const u8 {
    const executable_dir = std.process.executableDirPathAlloc(io, a) catch return null;
    return bundledBeside(io, a, executable_dir);
}

/// The Zig to drive when `--zig` is not given: `SELKA_ZIG`, the bundled one, `ZIG`, else `zig`.
pub fn fromEnvironment(io: std.Io, a: std.mem.Allocator, environ: *const std.process.Environ.Map) []const u8 {
    const named = environ.get("SELKA_ZIG");
    // An explicit name settles it without looking at the install.
    if (named) |path| if (path.len != 0) return path;
    return choose(null, bundled(io, a), environ.get("ZIG"));
}

test "choose follows SELKA_ZIG, bundled, ZIG, then PATH" {
    try std.testing.expectEqualStrings("/s", choose("/s", "/b", "/z"));
    try std.testing.expectEqualStrings("/b", choose(null, "/b", "/z"));
    try std.testing.expectEqualStrings("/z", choose(null, null, "/z"));
    try std.testing.expectEqualStrings("zig", choose(null, null, null));
}

test "choose treats an empty value as not set" {
    try std.testing.expectEqualStrings("/b", choose("", "/b", "/z"));
    try std.testing.expectEqualStrings("/z", choose("", "", "/z"));
    try std.testing.expectEqualStrings("zig", choose("", "", ""));
}

test "bundledBeside finds lib/selka/zig/zig of the install above the executable's folder" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", a);
    const executable_dir = try std.fs.path.join(a, &.{ root, "bin" });
    try tmp.dir.createDirPath(std.testing.io, "bin");
    try std.testing.expect(bundledBeside(std.testing.io, a, executable_dir) == null);
    try tmp.dir.createDirPath(std.testing.io, "lib/selka/zig");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "lib/selka/zig/zig", .data = "#!/bin/sh\n", .flags = .{ .permissions = .executable_file } });
    const expected = try std.fs.path.join(a, &.{ root, "lib/selka/zig/zig" });
    try std.testing.expectEqualStrings(expected, bundledBeside(std.testing.io, a, executable_dir).?);
}

test "bundledBeside ignores a bundled file that cannot be run and a directory of that name" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", a);
    const executable_dir = try std.fs.path.join(a, &.{ root, "bin" });
    try tmp.dir.createDirPath(std.testing.io, "lib/selka/zig");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "lib/selka/zig/zig", .data = "data", .flags = .{ .permissions = .default_file } });
    try std.testing.expect(bundledBeside(std.testing.io, a, executable_dir) == null);
    try tmp.dir.deleteFile(std.testing.io, "lib/selka/zig/zig");
    try tmp.dir.createDirPath(std.testing.io, "lib/selka/zig/zig");
    try std.testing.expect(bundledBeside(std.testing.io, a, executable_dir) == null);
}

test "hintFor names the install of Zig only for a missing tool" {
    try std.testing.expect(std.mem.indexOf(u8, hintFor(error.ToolNotFound), "Zig 0.17.1") != null);
    try std.testing.expect(std.mem.indexOf(u8, hintFor(error.ToolNotFound), "bundles it") != null);
    try std.testing.expectEqualStrings("", hintFor(error.ReadFailed));
}
