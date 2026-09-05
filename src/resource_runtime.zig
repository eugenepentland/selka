//! VM adapter for external resource values; all providers are explicitly injected.
const std = @import("std");
const typed = @import("typed.zig");
const resources = @import("external_resources.zig");
pub const Options = struct {
    filesystem: ?resources.Provider = null,
    network: ?resources.Provider = null,
    max_live_per_kind: usize = 1024,
    statistics: ?*[2]resources.Statistics = null,
};
pub const Runtime = struct {
    allocator: std.mem.Allocator,
    stores: [2]?resources.Store = .{ null, null },
    statistics: ?*[2]resources.Statistics,
    pub fn init(allocator: std.mem.Allocator, options: Options) !Runtime {
        var runtime: Runtime = .{ .allocator = allocator, .statistics = options.statistics };
        errdefer runtime.deinit();
        for ([_]?resources.Provider{ options.filesystem, options.network }, 0..) |provider, index| {
            if (provider) |p| runtime.stores[index] = try resources.Store.init(allocator, if (index == 0) .filesystem else .network, p, options.max_live_per_kind);
        }
        return runtime;
    }
    pub fn deinit(self: *Runtime) void {
        var index: usize = self.stores.len;
        while (index != 0) {
            index -= 1;
            if (self.stores[index]) |*store| {
                store.deinit();
                if (self.statistics) |statistics| statistics[index] = store.statistics;
            } else if (self.statistics) |statistics| statistics[index] = .{};
        }
    }
    fn storeFor(self: *Runtime, kind: resources.Kind) !*resources.Store {
        return if (self.stores[if (kind == .filesystem) @as(usize, 0) else 1]) |*store| store else error.CapabilityUnavailable;
    }
    pub fn grant(self: *Runtime, kind: resources.Kind) !typed.Value {
        return .{ .resource_capability = try (try self.storeFor(kind)).grant() };
    }
    pub fn acquire(self: *Runtime, output: typed.Type, records: []const typed.Record, capability: typed.Value, request: typed.Value, request_type: typed.Type) !typed.Value {
        if (capability != .resource_capability or request != .aggregate or request.typeOf() != request_type) return error.InternalError;
        const shape = typed.resultShape(output, records).?;
        const kind = typed.resourceKind(shape.ok_type, records).?;
        const store = try self.storeFor(kind);
        const array = records[request_type.recordIndex()].array.?;
        if (request.aggregate.fields.len != array.length) return error.InternalError;
        const bytes = try self.allocator.alloc(u8, array.length);
        defer self.allocator.free(bytes);
        for (request.aggregate.fields, bytes) |value, *byte| {
            if (value.typeOf() != .u8) return error.InternalError;
            byte.* = std.math.cast(u8, try value.asInteger()) orelse return error.InternalError;
        }
        const owner = store.acquire(capability.resource_capability, bytes) catch |err| {
            const code = recoverable(err) orelse return err;
            return typed.Value.createVariant(self.allocator, output, shape.error_tag, .{ .i64 = code });
        };
        const value = typed.Value.ownExternal(self.allocator, shape.ok_type, store, owner) catch |err| {
            try store.release(owner);
            return err;
        };
        defer value.release(self.allocator);
        return typed.Value.createVariant(self.allocator, output, shape.ok_tag, value);
    }
    pub fn complete(self: *Runtime, output: typed.Type, records: []const typed.Record, value: typed.Value) !typed.Value {
        const shape = typed.completionShape(output, records).?;
        if (value != .external_resource or value.typeOf() != shape.resource_type) return error.InternalError;
        const resource = value.external_resource;
        if (resource.store != try self.storeFor(typed.resourceKind(shape.resource_type, records).?)) return error.InvalidOwner;
        const owner = resource.owner orelse return error.InvalidOwner;
        resource.store.complete(owner) catch |err| {
            const code = recoverable(err) orelse return err;
            var fields: [2]typed.Value = undefined;
            fields[shape.resource_field] = value;
            fields[shape.code_field] = .{ .i64 = code };
            const failure = try typed.Value.create(self.allocator, shape.result.error_type, &fields);
            defer failure.release(self.allocator);
            return typed.Value.createVariant(self.allocator, output, shape.result.error_tag, failure);
        };
        resource.owner = null;
        return typed.Value.createVariant(self.allocator, output, shape.result.ok_tag, .{ .bool = true });
    }
};
fn recoverable(err: resources.Error) ?i64 {
    return switch (err) {
        error.Unavailable => 1,
        error.Denied => 2,
        error.Failed => 3,
        error.ResourceLimit => 4,
        else => null,
    };
}
