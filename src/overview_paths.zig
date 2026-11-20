//! Deterministic project-relative paths for the generated summary and references.
const std = @import("std");

/// The directory holding one reference file per module, beside the overview.
pub fn referenceDirectory(a: std.mem.Allocator, overview_path: []const u8) std.mem.Allocator.Error![]u8 {
    const parent = std.fs.path.dirname(overview_path) orelse ".";
    if (std.mem.eql(u8, parent, ".")) return a.dupe(u8, "reference");
    return std.fs.path.join(a, &.{ parent, "reference" });
}

/// One module's portable file name: dotted module names stay readable.
pub fn fileName(a: std.mem.Allocator, module: []const u8) std.mem.Allocator.Error![]u8 {
    const result = try a.alloc(u8, module.len + ".md".len);
    for (module, 0..) |byte, i| {
        const portable = std.ascii.isAlphanumeric(byte) or byte == '.' or byte == '-' or byte == '_';
        result[i] = if (portable) byte else '-';
    }
    @memcpy(result[module.len..], ".md");
    return result;
}

/// One module's root-relative reference path, POSIX-spelled.
pub fn referencePath(a: std.mem.Allocator, overview_path: []const u8, module: []const u8) std.mem.Allocator.Error![]u8 {
    return std.fs.path.join(a, &.{ try referenceDirectory(a, overview_path), try fileName(a, module) });
}

/// Whether a root-relative path is inside the generated reference directory.
pub fn inReferenceDirectory(a: std.mem.Allocator, overview_path: []const u8, path: []const u8) std.mem.Allocator.Error!bool {
    const directory = try referenceDirectory(a, overview_path);
    return std.mem.eql(u8, path, directory) or
        (path.len > directory.len and std.mem.startsWith(u8, path, directory) and path[directory.len] == '/');
}

/// One path expressed relative to a directory, for a Markdown link destination.
pub fn relative(a: std.mem.Allocator, from_directory: []const u8, to: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fs.path.relativePosix(a, "/", from_directory, to);
}
