//! Trusted embedding adapters; guest values carry identity and kind, never pointers.
const std = @import("std");
/// Stateless clock or random provider family exposed through explicit source authority.
pub const Kind = enum {
    clock,
    random,
    /// Return the source effect required to read this provider family.
    pub fn effect(self: Kind) @import("effect_set.zig").Effect {
        return switch (self) {
            .clock => .clock,
            .random => .random,
        };
    }
};
/// Provider authority bound to a single execution identity.
pub const Capability = struct { execution: u64, kind: Kind };
pub const CallError = std.mem.Allocator.Error || error{ Unavailable, Denied, Failed };
pub const ReadError = CallError || error{InvalidCapability};
/// Host-owned context must outlive the synchronous run. Returns Unix-epoch
/// nanoseconds; wall-clock adjustments are permitted. The callback is trusted.
pub const Clock = struct { context: *anyopaque, read: *const fn (*anyopaque) CallError!i64 };
/// Returns one full-width entropy word. Sample quality is the host provider
/// contract; deterministic providers are appropriate for tests and replay.
pub const Random = struct { context: *anyopaque, read: *const fn (*anyopaque) CallError!u64 };
/// Optional clock and random callbacks supplied by the host.
pub const Providers = struct { clock: ?Clock = null, random: ?Random = null };
/// Tracks provider availability and the lifetime of execution-bound capabilities.
pub const Runtime = struct {
    identity: u64,
    providers: Providers,
    /// Create an authority context borrowing the supplied provider callbacks.
    pub fn init(identity: u64, providers: Providers) Runtime {
        std.debug.assert(identity != 0);
        return .{ .identity = identity, .providers = providers };
    }
    /// Invalidate capabilities previously issued by this execution context.
    pub fn close(self: *Runtime) void {
        self.identity = 0;
    }
    /// Provisioning checks availability but does not invoke an external operation.
    pub fn grant(self: *Runtime, kind: Kind) error{ InvalidCapability, CapabilityUnavailable }!Capability {
        if (self.identity == 0) return error.InvalidCapability;
        const available = switch (kind) {
            .clock => self.providers.clock != null,
            .random => self.providers.random != null,
        };
        if (!available) return error.CapabilityUnavailable;
        return .{ .execution = self.identity, .kind = kind };
    }
    /// Validate capability identity and provider kind before requesting a host scalar value.
    pub fn read(self: *Runtime, kind: Kind, capability: Capability) ReadError!i128 {
        if (self.identity == 0 or capability.execution != self.identity or capability.kind != kind) return error.InvalidCapability;
        return switch (kind) {
            .clock => clock: {
                const provider = self.providers.clock orelse return error.Unavailable;
                break :clock try provider.read(provider.context);
            },
            .random => random: {
                const provider = self.providers.random orelse return error.Unavailable;
                break :random try provider.read(provider.context);
            },
        };
    }
};
