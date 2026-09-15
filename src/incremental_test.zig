//! Stable identity and interface-fingerprint behavior across body and signature edits.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const incremental = @import("incremental.zig");
const File = struct { path: []const u8, bytes: []const u8 };
const Files = struct {
    entries: []const File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        for (self.entries) |entry| if (std.mem.eql(u8, entry.path, path)) {
            if (entry.bytes.len > limit) return error.TooLarge;
            return allocator.dupe(u8, entry.bytes);
        };
        return error.NotFound;
    }
};
fn describe(entries: []const File, allocator: std.mem.Allocator) !incremental.Report {
    var files: Files = .{ .entries = entries };
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    return incremental.describe(allocator, &compilation);
}
fn declaration(report: incremental.Report, module: []const u8, name: []const u8) incremental.Declaration {
    for (report.modules) |unit| if (std.mem.eql(u8, unit.name, module)) {
        for (unit.declarations) |item| if (std.mem.eql(u8, item.name, name)) return item;
    };
    unreachable;
}

// spec: INCREMENTAL-ID-1
test "module and declaration identities ignore body edits and interface fingerprints follow signatures" {
    var entries = [_]File{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import data
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        },
        .{ .path = "data.my", .bytes =
        \\module data
        \\export value
        \\
        \\
        \\def value() -> i64:
        \\    return 41
        },
    };
    const first = try describe(&entries, t.allocator);
    defer incremental.deinit(first, t.allocator);
    const first_identity = declaration(first, "data", "value").identity;
    const first_body = declaration(first, "data", "value").body_sha256.?;
    const first_interface = first.project_interface_sha256;

    entries[1].bytes =
        \\module data
        \\export value
        \\
        \\
        \\def value() -> i64:
        \\    # a comment in the body
        \\    return 41
    ;
    const second = try describe(&entries, t.allocator);
    defer incremental.deinit(second, t.allocator);
    try t.expectEqualStrings(first_identity, declaration(second, "data", "value").identity);
    try t.expect(!std.mem.eql(u8, first_body, declaration(second, "data", "value").body_sha256.?));
    try t.expectEqualStrings(first_interface, second.project_interface_sha256);

    entries[1].bytes =
        \\module data
        \\export value
        \\
        \\
        \\def value(step: i64) -> i64:
        \\    return 41 + step
    ;
    const third = try describe(&entries, t.allocator);
    defer incremental.deinit(third, t.allocator);
    try t.expect(!std.mem.eql(u8, first_interface, third.project_interface_sha256));
}
