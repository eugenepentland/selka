//! VM adapter for external resource values; all providers are explicitly injected.
const byte_values = @import("byte_values.zig");
/// Failures returned by init; callers must handle these boundary errors.
pub const InitError = error{
    Closed,
    Denied,
    Failed,
    IdentityExhausted,
    InvalidCapability,
    InvalidOwner,
    InvalidProvider,
    OutOfMemory,
    ResourceLimit,
    Unavailable,
};
/// Failures returned by grant; callers must handle these boundary errors.
pub const GrantError = InitError || error{
    CapabilityUnavailable,
};
/// Failures returned by restrict; callers must handle these boundary errors.
pub const RestrictError = GrantError || error{
    InternalError,
};
/// Failures returned by acquire; callers must handle these boundary errors.
pub const AcquireError = RestrictError || error{
    InvalidAggregateType,
};
/// Failures returned by ioSlice; callers must handle these boundary errors.
pub const IoSliceError = AcquireError || error{
    BorrowConflict,
    BorrowSuspended,
    Bounds,
    CapacityLimit,
    ChildrenActive,
    ExpiredBorrow,
    ForeignMemory,
    InvalidAllocation,
    MemoryClosed,
    NoCapacity,
    ReadOnly,
    RegionInUse,
    TypeMismatch,
};

const std = @import("std");
const typed = @import("typed.zig");
const resources = @import("external_resources.zig");
/// Optional filesystem/network providers and bounds for their resource registries.
pub const Options = struct {
    filesystem: ?resources.Provider = null,
    network: ?resources.Provider = null,
    filesystem_permissions: resources.Permissions = resources.all_permissions,
    network_permissions: resources.Permissions = resources.all_permissions,
    max_live_per_kind: usize = 1024,
    statistics: ?*[2]resources.Statistics = null,
};
/// Owns provider stores used to execute typed external-resource operations.
pub const Runtime = struct {
    allocator: std.mem.Allocator,
    permissions: [2]resources.Permissions,
    stores: [2]?resources.Store = .{ null, null },
    statistics: ?*[2]resources.Statistics,
    /// Initialize the configured provider stores and unwind partial initialization on failure.
    pub fn init(allocator: std.mem.Allocator, options: Options) InitError!Runtime {
        if ((options.filesystem_permissions | options.network_permissions) & ~resources.all_permissions != 0) return error.InvalidCapability;
        var runtime: Runtime = .{ .allocator = allocator, .statistics = options.statistics, .permissions = .{ options.filesystem_permissions, options.network_permissions } };
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
    /// Produce typed authority for an available provider family.
    pub fn grant(self: *Runtime, kind: resources.Kind) GrantError!typed.Value {
        const store = try self.storeFor(kind);
        return .{ .capability = .{ .resource_capability = try store.restrict(try store.grant(), self.permissions[if (kind == .filesystem) @as(usize, 0) else 1]) } };
    }
    /// Validate a capability and return a version with reduced permissions.
    pub fn restrict(self: *Runtime, value: typed.Value, permissions: resources.Permissions) RestrictError!typed.Value {
        if (!value.isCapability(.resource_capability)) return error.InternalError;
        return .{ .capability = .{ .resource_capability = try (try self.storeFor(value.capability.resource_capability.kind)).restrict(value.capability.resource_capability, permissions) } };
    }
    /// Convert a typed request, acquire a provider resource, and allocate the declared result.
    pub fn acquire(self: *Runtime, output: typed.Type, records: []const typed.Record, capability: typed.Value, request: typed.Value, request_type: typed.Type) AcquireError!typed.Value {
        if (!capability.isCapability(.resource_capability) or request.typeOf() != request_type) return error.InternalError;
        const shape = typed.resultShape(output, records).?;
        const kind = typed.resourceKind(shape.ok_type, records).?;
        const store = try self.storeFor(kind);
        const bytes = try byte_values.acquisitionBytes(self.allocator, request, request_type, records);
        defer self.allocator.free(bytes);
        const owner = store.acquire(capability.capability.resource_capability, bytes) catch |err| {
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
    /// Execute typed resource IO and construct the operation's result representation.
    pub fn io(self: *Runtime, records: []const typed.Record, request: IoRequest) AcquireError!typed.Value {
        const kind = request.kind;
        const output = request.output;
        const value = request.value;
        const input = request.input;
        const input_type = request.input_type;
        if (!value.isOwned(.external_resource)) return error.InternalError;
        const resource = value.owned.external_resource;
        if (resource.store != try self.storeFor(typed.resourceKind(resource.ty, records) orelse return error.InternalError)) return error.InvalidOwner;
        const owner = resource.owner orelse return error.InvalidOwner;
        const shape = typed.resultShape(output, records).?;
        if (kind == .write) {
            const bytes = try byte_values.toOwnedBytes(self.allocator, input orelse return error.InternalError, input_type orelse return error.InternalError, records);
            defer self.allocator.free(bytes);
            const length = resource.store.write(owner, bytes) catch |err| {
                const code = recoverable(err) orelse return err;
                return typed.Value.createVariant(self.allocator, output, shape.error_tag, .{ .i64 = code });
            };
            return typed.Value.createVariant(self.allocator, output, shape.ok_tag, typed.Value.number(.u64, length));
        }
        const read_shape = typed.resourceReadShape(output, records).?;
        const bytes = try self.allocator.alloc(u8, records[read_shape.bytes_type.recordIndex()].shape.array.?.length);
        defer self.allocator.free(bytes);
        const read = resource.store.read(owner, bytes) catch |err| {
            const code = recoverable(err) orelse return err;
            return typed.Value.createVariant(self.allocator, output, shape.error_tag, .{ .i64 = code });
        };
        const array = try byte_values.fromBytes(self.allocator, bytes, read_shape.bytes_type, records);
        defer array.release(self.allocator);
        var fields: [3]typed.Value = undefined;
        fields[read_shape.bytes_field] = array;
        fields[read_shape.length_field] = typed.Value.number(.u64, read.length);
        fields[read_shape.flag_field] = .{ .bool = read.eof };
        const payload = try typed.Value.create(self.allocator, shape.ok_type, &fields);
        defer payload.release(self.allocator);
        return typed.Value.createVariant(self.allocator, output, shape.ok_tag, payload);
    }
    /// Complete a resource and construct a result that preserves ownership on provider failure.
    pub fn complete(self: *Runtime, output: typed.Type, records: []const typed.Record, value: typed.Value) AcquireError!typed.Value {
        const shape = typed.completionShape(output, records).?;
        if (!value.isOwned(.external_resource) or value.typeOf() != shape.resource_type) return error.InternalError;
        const resource = value.owned.external_resource;
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

/// Borrowed resource operation operands and their checked result/input types.
pub const IoRequest = struct { kind: resources.IoKind, output: typed.Type, value: typed.Value, input: ?typed.Value, input_type: ?typed.Type };
