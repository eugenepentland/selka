//! The source files one entry's project graph reads, found by loading the graph
//! from disk. `mylang fix` uses it to skip an entry whose modules an earlier
//! entry's check already covered.
const std = @import("std");
const language = @import("mylang");
const project = language.project;
const project_config = language.project_config;

/// Why the graph of an entry could not be listed.
pub const Error = error{ OutOfMemory, InvalidEntry };

/// The absolute paths of every source file loading `entry`'s project graph read,
/// or just the entry itself when the graph does not load. Every path is allocated
/// from `allocator`, which the caller releases as one arena.
pub fn reach(allocator: std.mem.Allocator, io: std.Io, entry: []const u8) Error![]const []const u8 {
    const cwd = std.Io.Dir.cwd().realPathFileAlloc(io, ".", allocator) catch return error.InvalidEntry;
    const absolute = try std.fs.path.resolve(allocator, &.{ cwd, entry });
    var root: []const u8 = std.fs.path.dirname(absolute) orelse return error.InvalidEntry;
    var name: []const u8 = std.fs.path.basename(absolute);
    if (project_config.testEntryLocation(allocator, io, absolute) catch return error.InvalidEntry) |location| {
        root = location.root;
        name = location.relative;
    }
    var provider: DiskProvider = .{ .allocator = allocator, .io = io, .root = root };
    var loaded = project.Project.init(allocator);
    defer loaded.deinit();
    const module_name = try entryModule(allocator, name);
    loaded.load(.{ .context = &provider, .read = DiskProvider.read }, module_name, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {},
    };
    if (provider.paths.items.len == 0) try provider.paths.append(allocator, absolute);
    return provider.paths.items;
}

/// The exit status a finished child reports: its own code, else 2.
pub fn exitCode(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        else => 2,
    };
}

/// The dotted module name of an entry path relative to its project root.
fn entryModule(allocator: std.mem.Allocator, entry: []const u8) Error![]const u8 {
    if (!std.mem.endsWith(u8, entry, ".my")) return error.InvalidEntry;
    const name = try allocator.dupe(u8, entry[0 .. entry.len - 3]);
    for (name) |*byte| {
        if (byte.* == std.fs.path.sep) byte.* = '.';
    }
    return name;
}

/// Reads project sources beneath one root and records each path it served.
const DiskProvider = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    paths: std.ArrayList([]const u8) = .empty,
    fn read(raw: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) project.ReadError![]u8 {
        const self: *DiskProvider = @ptrCast(@alignCast(raw.?));
        const absolute = std.fs.path.join(self.allocator, &.{ self.root, path }) catch return error.OutOfMemory;
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.io, absolute, allocator, .limited(limit + 1)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.FileNotFound => return error.NotFound,
            error.StreamTooLong => return error.TooLarge,
            else => return error.ReadFailed,
        };
        self.paths.append(self.allocator, absolute) catch return error.OutOfMemory;
        return bytes;
    }
};
