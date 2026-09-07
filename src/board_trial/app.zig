//! Stable-address compilation and registered VM application lifecycle.
const std = @import("std");
const language = @import("mylang");
const values = @import("values.zig");
const m = @import("model.zig");
const Geometry = @import("geometry.zig").Geometry;
/// Owns the project and registrations; initialize in its final address and never copy.
pub const App = struct {
    program: language.embedded_project.Program,
    registry: language.vm_host.Registry,
    geometry: Geometry,
    trap: ?language.diagnostic.Diagnostic = null,
    /// Initialization failures preserve compiler and registration error identities.
    pub const InitError = language.embedded_project.InitError || values.Error || language.vm_host.Error;
    /// Invocation failures are distinct from declared guest validation results.
    pub const RunError = values.Error || language.vm.HostInvokeError || language.project_compile.PublicFunctionError || error{GuestTrap};
    /// Compile the provided source graph and bind the sole trusted geometry operation.
    pub fn init(self: *App, allocator: std.mem.Allocator, provider: language.project.Provider) InitError!void {
        self.trap = null;
        try self.program.init(allocator, provider);
        errdefer self.program.deinit();
        self.registry = try language.vm_host.Registry.init(allocator, self.program.compilation.code.?);
        errdefer self.registry.deinit();
        self.geometry = .{ .meta = .{ .records = self.program.compilation.code.?.records } };
        try self.geometry.install(&self.registry);
    }
    /// Release registrations before the catalog they borrow.
    pub fn deinit(self: *App) void {
        self.registry.deinit();
        self.program.deinit();
    }
    /// Invoke the exported validator with a fresh owned snapshot and callback budget.
    pub fn run(self: *App, allocator: std.mem.Allocator, board: m.Board, unavailable: bool, options: language.vm.HostInvokeOptions) RunError!m.Observation {
        self.trap = null;
        var snapshot = try values.Snapshot.init(allocator, self.geometry.meta, board);
        defer snapshot.deinit();
        self.geometry.kernel = .{ .unavailable = unavailable };
        const result = try self.program.compilation.invokePublicWithHost(allocator, "validation::validate", &.{snapshot.value}, &self.registry, options);
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
    return language.embedded_project.read(allocator, &.{
        .{ .path = "main.my", .bytes = @embedFile("guest/main.my") },
        .{ .path = "units.my", .bytes = @embedFile("guest/units.my") },
        .{ .path = "ids.my", .bytes = @embedFile("guest/ids.my") },
        .{ .path = "model.my", .bytes = @embedFile("guest/model.my") },
        .{ .path = "bounds.my", .bytes = @embedFile("guest/bounds.my") },
        .{ .path = "inventory.my", .bytes = @embedFile("guest/inventory.my") },
        .{ .path = "checks.my", .bytes = @embedFile("guest/checks.my") },
        .{ .path = "policy.my", .bytes = @embedFile("guest/policy.my") },
        .{ .path = "geometry.my", .bytes = @embedFile("guest/geometry.my") },
        .{ .path = "validation.my", .bytes = @embedFile("guest/validation.my") },
    }, path, limit);
}
