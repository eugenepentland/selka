//! Bundle native runtime build inputs into the installed compiler.
const std = @import("std");
pub fn module(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    b.dependOnDirectory(b.path("src"));
    const files = b.addWriteFiles();
    _ = files.addCopyDirectory(b.path("src"), "src", .{});
    var directory = b.root.openDir(b.graph.io, "src", .{ .iterate = true }) catch @panic("open native assets");
    defer directory.close(b.graph.io);
    var walker = directory.walk(b.allocator) catch @panic("walk native assets");
    defer walker.deinit();
    var paths: std.ArrayList([]const u8) = .empty;
    while (walker.next(b.graph.io) catch @panic("read native assets")) |entry| {
        if (entry.kind == .directory) b.dependOnDirectory(b.path(b.pathJoin(&.{ "src", entry.path })));
        if (entry.kind != .file) continue;
        paths.append(b.allocator, b.dupe(entry.path)) catch @panic("OOM");
    }
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn less(_: void, a: []const u8, c: []const u8) bool {
            return std.mem.lessThan(u8, a, c);
        }
    }.less);
    var text: std.Io.Writer.Allocating = .init(b.allocator);
    text.writer.writeAll("pub const Asset = struct { path: []const u8, bytes: []const u8 };\npub const files = [_]Asset{\n") catch @panic("OOM");
    for (paths.items) |path| text.writer.print(".{{ .path=\"{s}\", .bytes=@embedFile(\"src/{s}\") }},\n", .{ path, path }) catch @panic("OOM");
    text.writer.writeAll("};\npub const zig_version = \"0.17.0-dev.1683+5ceec001b\";\n") catch @panic("OOM");
    return b.createModule(.{ .root_source_file = files.add("assets.zig", text.written()), .target = target, .optimize = optimize });
}
