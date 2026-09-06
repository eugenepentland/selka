//! Trusted copied-value wrapper for the bounded rectangle kernel.
const std = @import("std");
const language = @import("mylang");
const host = language.host_functions;
const values = @import("values.zig");
const Kernel = @import("kernel.zig").Kernel;
/// Stable callback context borrowing the compiled nominal catalog.
pub const Geometry = struct {
    meta: values.Meta,
    kernel: Kernel = .{},
    /// Require exactly the handwritten wrapper's nominal signature and host authority.
    pub fn install(self: *Geometry, registry: *language.vm_host.Registry) (values.Error || language.vm_host.Error)!void {
        const rect = try self.meta.find("model::Rect");
        const parameters = [_]host.Parameter{ .{ .ty = rect }, .{ .ty = rect } };
        try registry.register("geometry::overlap", .{
            .signature = .{ .parameters = &parameters, .result = .{ .ty = try self.meta.find("model::Overlap") }, .effects = 1 << 6 },
            .context = self,
            .invoke = invoke,
        }, 1 << 6);
    }
    fn invoke(call: *host.Call) host.CallbackError!values.Value {
        const self: *Geometry = @ptrCast(@alignCast(call.context.?));
        try call.consume(2);
        return self.contact(call.allocator(), call.arguments[0], call.arguments[1]) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.HostFailure,
        };
    }
    /// Return an owned declared result, releasing intermediate values on every allocation path.
    pub fn contact(self: *Geometry, allocator: std.mem.Allocator, a: values.Value, b: values.Value) values.Error!values.Value {
        const result = self.kernel.intersect(try values.rect(self.meta, a), try values.rect(self.meta, b));
        const payload = switch (result) {
            .ok => |hit| try self.meta.variant(allocator, try self.meta.find("model::Contact"), if (hit) "intersection" else "clear", null),
            .err => |problem| try self.meta.variant(allocator, try self.meta.find("model::GeometryFailure"), @tagName(problem), null),
        };
        defer payload.release(allocator);
        return self.meta.variant(allocator, try self.meta.find("model::Overlap"), @tagName(result), payload);
    }
};
