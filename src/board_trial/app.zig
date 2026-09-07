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
        try self.bind(allocator);
    }
    /// Load the current disk project and validate its typed geometry interface.
    pub fn initDisk(self: *App, allocator: std.mem.Allocator, io: std.Io, root: []const u8) InitError!void {
        self.trap = null;
        try self.program.initDisk(allocator, io, root);
        errdefer self.program.deinit();
        try self.bind(allocator);
    }
    fn bind(self: *App, allocator: std.mem.Allocator) InitError!void {
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
