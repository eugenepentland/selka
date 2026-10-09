//! Shared ownership of one checked project compilation for Zig-hosted tests.
const std = @import("std");
const project = @import("project.zig");
const interfaces = @import("interfaces.zig");
const project_compile = @import("project_compile.zig");
/// Loading and compilation errors retain their originating diagnostic identity.
pub const InitError = project.RenderProblemError || project.LoadError || @import("diagnostic.zig").Error || project_compile.InitError;
/// Stable-address project, interface and checked-program storage; initialize in place and never copy.
pub const Program = struct {
    loaded: project.Project,
    index: interfaces.Index,
    compilation: project_compile.Compilation,
    /// Compile a supplied main module graph, releasing partially initialized storage on failure.
    pub fn init(self: *Program, allocator: std.mem.Allocator, provider: project.Provider) InitError!void {
        self.loaded = project.Project.init(allocator);
        errdefer self.loaded.deinit();
        try self.loadIndex(provider);
        self.compilation = try project_compile.Compilation.init(&self.index);
        try self.compilation.check();
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
