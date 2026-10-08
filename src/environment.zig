//! Read-only environment authority, explicitly injected per execution.
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

/// Borrowed typed environment lookup, including the checked input and output schemas.
pub const Lookup = struct { output: typed.Type, capability: typed.Value, name: typed.Value, name_type: typed.Type };
