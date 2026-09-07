//! Compile reusable guest modules; each invocation owns a fresh bounded byte-I/O session.
const std = @import("std");
const language = @import("mylang");
const bridge = @import("host.zig");
/// Source loading and guest compilation failures preserve their original error identities.
pub const InitError = language.embedded_project.InitError;
/// Resource failures remain distinct from located DSL errors and VM traps.
pub const RunError = language.vm.RunError || language.vm_host.Error || error{ InvalidSchematic, GuestTrap };
/// Owns compilation storage; initialize in its final address and do not copy.
pub const App = struct {
    program: language.embedded_project.Program,
    issue: ?bridge.Issue = null,
    trap: ?language.diagnostic.Diagnostic = null,
    /// Load the supplied guest project, normally the checked-in embedded modules.
    pub fn init(self: *App, allocator: std.mem.Allocator, provider: language.project.Provider) InitError!void {
        self.issue = null;
        self.trap = null;
        try self.program.init(allocator, provider);
    }
    /// Release all source, syntax, type and bytecode storage.
    pub fn deinit(self: *App) void {
        self.program.deinit();
    }
    /// Return caller-owned SVG only on success; preserve a located issue or trap on failure.
    pub fn run(self: *App, allocator: std.mem.Allocator, documents: *const [3][]const u8, options: language.vm.Options) RunError![]u8 {
        self.issue = null;
        self.trap = null;
        var context: bridge.Context = .{ .allocator = allocator, .documents = documents };
        defer context.deinit();
        if (bridge.validateDocuments(documents)) |issue| {
            self.issue = issue;
            return error.InvalidSchematic;
        }
        var registry = try language.vm_host.Registry.init(allocator, self.program.compilation.code.?);
        defer registry.deinit();
        try context.install(&registry);
        const outcome = try language.vm.runWithHost(allocator, self.program.compilation.code.?, options, &registry, .{ .max_calls = 4_000_000, .max_work = 4_000_000 });
        self.issue = context.issue;
        if (self.issue != null) return error.InvalidSchematic;
        switch (outcome) {
            .trap => |trap| {
                self.trap = trap;
                return error.GuestTrap;
            },
            .value => |value| if (value != 0) {
                self.issue = .{ .code = 24, .file = 0, .position = 0 };
                return error.InvalidSchematic;
            },
        }
        return context.output.toOwnedSlice(allocator);
    }
};
/// Read the guest source without depending on cwd or granting guest filesystem access.
pub fn embedded(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    return language.embedded_project.read(allocator, &.{
        .{ .path = "main.my", .bytes = @embedFile("guest/main.my") },
        .{ .path = "io.my", .bytes = @embedFile("guest/io.my") },
        .{ .path = "text.my", .bytes = @embedFile("guest/text.my") },
        .{ .path = "sexpr.my", .bytes = @embedFile("guest/sexpr.my") },
        .{ .path = "circuit.my", .bytes = @embedFile("guest/circuit.my") },
        .{ .path = "svg.my", .bytes = @embedFile("guest/svg.my") },
        .{ .path = "validate.my", .bytes = @embedFile("guest/validate.my") },
        .{ .path = "ports.my", .bytes = @embedFile("guest/ports.my") },
    }, path, limit);
}
