//! Native host operations and selected project paths for release commands.
const std = @import("std");
const product = @import("product.zig");
const loader = @import("release_project_load.zig");
const options = @import("release_options.zig");
const reports = @import("release_report.zig");
const store = @import("overview_store.zig");
/// Native execution or filesystem failure; allocation failure remains distinct.
pub const Error = error{ OutOfMemory, HostIo, ChildFailed };
/// Arena-backed command context; all children run this executable in the project.
pub const Context = struct {
    process: std.process.Init,
    options: options.Options,
    model: *loader.Model,
    metadata: store.Store,
    report: *reports.Report,
    compiler: []const u8,
    /// Borrow the command arena.
    pub fn allocator(self: Context) std.mem.Allocator {
        return self.process.arena.allocator();
    }
    /// Run a compiler command without a shell, capturing both output streams.
    pub fn child(self: Context, args: []const []const u8) Error!Child {
        const a = self.allocator();
        const argv = try a.alloc([]const u8, args.len + 1);
        argv[0] = self.compiler;
        @memcpy(argv[1..], args);
        const result = std.process.run(a, self.process.io, .{
            .argv = argv,
            .cwd = .{ .path = self.model.root },
            .environ_map = self.process.environ_map,
            .stdout_limit = .limited(32 << 20),
            .stderr_limit = .limited(32 << 20),
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.HostIo,
        };
        const status = try childStatus(result.term);
        return .{ .status = status, .stdout = result.stdout, .stderr = result.stderr };
    }
    /// Resolve a configured path in the current project.
    pub fn path(self: Context, relative: []const u8) std.mem.Allocator.Error![]const u8 {
        return std.fs.path.join(self.allocator(), &.{ self.model.root, relative });
    }
    /// Write a root-relative file, creating its parent directories.
    pub fn write(self: Context, relative: []const u8, bytes: []const u8, exclusive: bool) Error!void {
        const absolute = try self.path(relative);
        if (std.fs.path.dirname(absolute)) |parent| std.Io.Dir.cwd().createDirPath(self.process.io, parent) catch return error.HostIo;
        const file = std.Io.Dir.cwd().createFile(self.process.io, absolute, .{ .exclusive = exclusive }) catch return error.HostIo;
        defer file.close(self.process.io);
        file.writeStreamingAll(self.process.io, bytes) catch return error.HostIo;
    }
    /// Whether a path exists, preserving host errors instead of treating them as absence.
    pub fn exists(self: Context, relative: []const u8) Error!bool {
        _ = std.Io.Dir.cwd().statFile(self.process.io, try self.path(relative), .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return error.HostIo,
        };
        return true;
    }
};
/// Captured native command result; all bytes belong to the command arena.
pub const Child = struct {
    status: u8,
    stdout: []const u8,
    stderr: []const u8,
    /// Distinguish host/usage failure from a refusing guest check.
    pub fn checkHost(self: Child) error{ChildFailed}!void {
        if (self.status == 2) return error.ChildFailed;
    }
};
/// Decode ordinary process termination; signals cannot certify a completed check.
pub fn childStatus(term: std.process.Child.Term) error{ChildFailed}!u8 {
    return switch (term) {
        .exited => |status| status,
        else => error.ChildFailed,
    };
}
/// Inventory project source or Markdown files using the shared exclusion predicate.
pub fn files(context: Context, kind: enum { source, markdown, api }) Error![]const []const u8 {
    const a = context.allocator();
    var directory = std.Io.Dir.cwd().openDir(context.process.io, context.model.root, .{ .iterate = true }) catch return error.HostIo;
    defer directory.close(context.process.io);
    var walker = try directory.walk(a);
    defer walker.deinit();
    var result: std.ArrayList([]const u8) = .empty;
    while (walker.next(context.process.io) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.HostIo,
    }) |item| {
        if (@import("release_project.zig").excluded(item.path, context.model.options.exclude)) {
            if (item.kind == .directory) walker.leave(context.process.io);
            continue;
        }
        if (item.kind != .file) continue;
        if (kind == .markdown and generatedMetadata(context, item.path)) continue;
        const matches = switch (kind) {
            .source => product.isSource(item.path),
            .api => std.mem.endsWith(u8, item.path, ".api"),
            .markdown => std.mem.eql(u8, item.path, "README.md") or (std.mem.startsWith(u8, item.path, "docs/") and std.mem.endsWith(u8, item.path, ".md")),
        };
        if (matches) try result.append(a, try a.dupe(u8, item.path));
    }
    std.mem.sort([]const u8, result.items, {}, less);
    return result.items;
}
fn less(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn generatedMetadata(context: Context, path: []const u8) bool {
    if (std.mem.eql(u8, path, context.model.options.overview)) return true;
    if (@import("overview_paths.zig").inReferenceDirectory(context.allocator(), context.model.options.overview, path) catch false) return true;
    const directory = context.model.options.decisions;
    return path.len > directory.len and std.mem.startsWith(u8, path, directory) and path[directory.len] == '/';
}
