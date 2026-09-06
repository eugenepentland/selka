//! Read-only environment authority, explicitly injected per execution.
/// Failures returned by readValue; callers must handle these boundary errors.
pub const ReadValueError = error{
    Denied,
    Failed,
    InternalError,
    InvalidAggregateType,
    InvalidCapability,
    InvalidProvider,
    NoCapacity,
    OutOfMemory,
    Unavailable,
};

const std = @import("std");
const typed = @import("typed.zig");
const byte_values = @import("byte_values.zig");
/// Environment authority tied to a single execution identity.
pub const Capability = @import("value.zig").EnvironmentCapability;
pub const CallError = @import("external_capabilities.zig").CallError || error{NoCapacity};
pub const ReadError = CallError || error{ InvalidCapability, InvalidProvider };
/// A trusted synchronous lookup. Names/outputs are borrowed only during the call.
/// Return null for absent, a complete byte length for present (including zero),
/// or NoCapacity when the whole value cannot fit. Never report truncated success.
/// Context must outlive the execution; returned bytes must not alias later state.
pub const Provider = struct { context: *anyopaque, get: *const fn (*anyopaque, []const u8, []u8) CallError!?usize };
/// Optional environment provider and the lifetime of its execution-bound authority.
pub const Runtime = struct {
    identity: u64,
    provider: ?Provider,
    /// Create an environment authority context borrowing the optional provider.
    pub fn init(identity: u64, provider: ?Provider) Runtime {
        std.debug.assert(identity != 0);
        return .{ .identity = identity, .provider = provider };
    }
    /// Invalidate previously granted environment capabilities.
    pub fn close(self: *Runtime) void {
        self.identity = 0;
    }
    /// Grant execution-bound environment authority only when a provider is available.
    pub fn grant(self: *Runtime) error{ InvalidCapability, CapabilityUnavailable }!Capability {
        if (self.identity == 0) return error.InvalidCapability;
        if (self.provider == null) return error.CapabilityUnavailable;
        return .{ .execution = self.identity };
    }
    /// Validate authority and request an environment value into bounded caller storage.
    pub fn get(self: *Runtime, capability: Capability, name: []const u8, output: []u8) ReadError!?usize {
        if (self.identity == 0 or capability.execution != self.identity) return error.InvalidCapability;
        const provider = self.provider orelse return error.Unavailable;
        @memset(output, 0);
        const length = try provider.get(provider.context, name, output);
        if (length) |n| {
            if (n > output.len) return error.InvalidProvider;
            @memset(output[n..], 0);
        } else @memset(output, 0);
        return length;
    }
};
/// Decode a typed lookup request and allocate its declared result representation.
pub fn readValue(allocator: std.mem.Allocator, runtime: *Runtime, request: Lookup, records: []const typed.Record) ReadValueError!typed.Value {
    const output = request.output;
    const capability = request.capability;
    const name = request.name;
    const name_type = request.name_type;
    if (!capability.isCapability(.environment_capability)) return error.InternalError;
    const shape = typed.environmentShape(output, records).?;
    const key = try byte_values.toOwnedBytes(allocator, name, name_type, records);
    defer allocator.free(key);
    const bytes = try allocator.alloc(u8, records[shape.bytes_type.recordIndex()].shape.array.?.length);
    defer allocator.free(bytes);
    const length = runtime.get(capability.capability.environment_capability, key, bytes) catch |err| {
        const code: i64 = switch (err) {
            error.Unavailable => 1,
            error.Denied => 2,
            error.Failed => 3,
            error.NoCapacity => 4,
            else => return err,
        };
        return typed.Value.createVariant(allocator, output, shape.result.error_tag, .{ .i64 = code });
    };
    const array = try byte_values.fromBytes(allocator, bytes, shape.bytes_type, records);
    defer array.release(allocator);
    var fields: [3]typed.Value = undefined;
    fields[shape.bytes_field] = array;
    fields[shape.length_field] = typed.Value.number(.u64, length orelse 0);
    fields[shape.flag_field] = .{ .bool = length != null };
    const value = try typed.Value.create(allocator, shape.result.ok_type, &fields);
    defer value.release(allocator);
    return typed.Value.createVariant(allocator, output, shape.result.ok_tag, value);
}

/// Borrowed typed environment lookup, including the checked input and output schemas.
pub const Lookup = struct { output: typed.Type, capability: typed.Value, name: typed.Value, name_type: typed.Type };
