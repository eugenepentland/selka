//! Shared compilation ownership for interpreter applications hosted in Zig.
const std = @import("std");
const print = std.debug.print;
const project = @import("project.zig");
const interfaces = @import("interfaces.zig");
const project_compile = @import("project_compile.zig");
const disk_files = @import("project_files.zig");
/// Loading and compilation errors retain their originating diagnostic identity.
pub const InitError = project.RenderProblemError || project.LoadError || @import("diagnostic.zig").Error || project_compile.InitError;
/// Stable-address project, interface and bytecode storage; initialize in place and never copy.
pub const Program = struct {
    loaded: project.Project,
    index: interfaces.Index,
    compilation: project_compile.Compilation,
    /// Compile a supplied main module graph, releasing partially initialized storage on failure.
    pub fn init(self: *Program, allocator: std.mem.Allocator, provider: project.Provider) InitError!void {
        try self.initSource(allocator, provider, false);
    }
    /// Compile main.my and its imports from disk, reporting source errors before releasing storage.
    pub fn initDisk(self: *Program, allocator: std.mem.Allocator, io: std.Io, root: []const u8) InitError!void {
        var disk: disk_files.Files = .{ .io = io, .root = root };
        try self.initSource(allocator, disk.provider(), true);
    }
    fn initSource(self: *Program, allocator: std.mem.Allocator, provider: project.Provider, report: bool) InitError!void {
        self.loaded = project.Project.init(allocator);
        errdefer self.loaded.deinit();
        self.loadIndex(provider) catch |err| {
            if (report and self.loaded.problem != null) {
                const message = try self.loaded.renderProblem(allocator);
                defer allocator.free(message);
                print("{s}", .{message});
            }
            return err;
        };
        self.compilation = try project_compile.Compilation.init(&self.index);
        self.compilation.emit() catch |err| {
            if (report) for (self.compilation.diagnostics.items.items) |diag| {
                const message = try diag.render(allocator, self.compilation.src);
                defer allocator.free(message);
                print("{s}", .{message});
            };
            return err;
        };
    }
    fn loadIndex(self: *Program, provider: project.Provider) InitError!void {
        try self.loaded.load(provider, "main", .{});
        self.index = try interfaces.build(&self.loaded);
    }
    /// Release all compilation storage after its consumers have released their borrows.
    pub fn deinit(self: *Program) void {
        self.loaded.deinit();
    }
};
/// A caller-owned immutable source file in an explicit embedded manifest.
pub const File = struct { path: []const u8, bytes: []const u8 };
/// Copy an exact manifest match into caller storage with the same limits as filesystem providers.
pub fn read(allocator: std.mem.Allocator, files: []const File, path: []const u8, limit: usize) project.ReadError![]u8 {
    for (files) |file| {
        if (!std.mem.eql(u8, path, file.path)) continue;
        if (file.bytes.len > limit) return error.TooLarge;
        return allocator.dupe(u8, file.bytes);
    }
    return error.NotFound;
}
