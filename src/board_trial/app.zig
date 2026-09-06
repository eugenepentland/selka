//! Stable-address compilation and registered VM application lifecycle.
const std = @import("std");
const language = @import("mylang");
const values = @import("values.zig");
const m = @import("model.zig");
const Geometry = @import("geometry.zig").Geometry;
/// Owns the project and registrations; initialize in its final address and never copy.
pub const App = struct {
    project: language.project.Project,
    index: language.interfaces.Index,
    compilation: language.project_compile.Compilation,
    registry: language.vm_host.Registry,
    geometry: Geometry,
    trap: ?language.diagnostic.Diagnostic = null,
    /// Initialization failures preserve compiler and registration error identities.
    pub const InitError = language.project.LoadError || language.diagnostic.Error || language.project_compile.InitError || values.Error || language.vm_host.Error;
    /// Invocation failures are distinct from declared guest validation results.
    pub const RunError = values.Error || language.vm.HostInvokeError || language.project_compile.PublicFunctionError || error{GuestTrap};
    /// Compile the provided source graph and bind the sole trusted geometry operation.
    pub fn init(self: *App, allocator: std.mem.Allocator, provider: language.project.Provider) InitError!void {
        self.trap = null;
        self.project = language.project.Project.init(allocator);
        errdefer self.project.deinit();
        try self.project.load(provider, "main", .{});
        self.index = try language.interfaces.build(&self.project);
        self.compilation = try language.project_compile.Compilation.init(&self.index);
        try self.compilation.emit();
        self.registry = try language.vm_host.Registry.init(allocator, self.compilation.code.?);
        errdefer self.registry.deinit();
        self.geometry = .{ .meta = .{ .records = self.compilation.code.?.records } };
        try self.geometry.install(&self.registry);
    }
    /// Release registrations before the catalog they borrow.
    pub fn deinit(self: *App) void {
        self.registry.deinit();
        self.project.deinit();
    }
    /// Invoke the exported validator with a fresh owned snapshot and callback budget.
    pub fn run(self: *App, allocator: std.mem.Allocator, board: m.Board, unavailable: bool, options: language.vm.HostInvokeOptions) RunError!m.Observation {
        self.trap = null;
        var snapshot = try values.Snapshot.init(allocator, self.geometry.meta, board);
        defer snapshot.deinit();
        self.geometry.kernel = .{ .unavailable = unavailable };
        const result = try self.compilation.invokePublicWithHost(allocator, "validation::validate", &.{snapshot.value}, &self.registry, options);
        switch (result) {
            .trap => |problem| {
                self.trap = problem;
                return error.GuestTrap;
            },
            .value => |value| {
                defer value.release(allocator);
                return .{ .outcome = try values.outcome(self.geometry.meta, value), .calls = self.geometry.kernel.calls };
            },
        }
    }
};
/// Read the checked-in guest modules without a dependency on the working directory.
pub fn embedded(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    inline for (.{ "main", "units", "ids", "model", "bounds", "inventory", "checks", "policy", "geometry", "validation" }) |name| {
        if (std.mem.eql(u8, path, name ++ ".my")) {
            const bytes = @embedFile("guest/" ++ name ++ ".my");
            if (bytes.len > limit) return error.TooLarge;
            return allocator.dupe(u8, bytes);
        }
    }
    return error.NotFound;
}
