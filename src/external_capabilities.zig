//! Trusted embedding adapters; guest values carry identity and kind, never pointers.
const std = @import("std");
pub const Kind = enum {
    clock,
    random,
    pub fn effect(self: Kind) @import("effect_set.zig").Effect {
        return switch (self) {
            .clock => .clock,
            .random => .random,
        };
    }
};
pub const Capability = struct { execution: u64, kind: Kind };
pub const CallError = std.mem.Allocator.Error || error{ Unavailable, Denied, Failed };
pub const ReadError = CallError || error{InvalidCapability};
/// Host-owned context must outlive the synchronous run. Returns Unix-epoch
/// nanoseconds; wall-clock adjustments are permitted. The callback is trusted.
pub const Clock = struct { context: *anyopaque, read: *const fn (*anyopaque) CallError!i64 };
/// Returns one full-width entropy word. Sample quality is the host provider
/// contract; deterministic providers are appropriate for tests and replay.
pub const Random = struct { context: *anyopaque, read: *const fn (*anyopaque) CallError!u64 };
pub const Providers = struct { clock: ?Clock = null, random: ?Random = null };
pub const Runtime = struct {
    identity: u64,
    providers: Providers,
    pub fn init(identity: u64, providers: Providers) Runtime {
        std.debug.assert(identity != 0);
        return .{ .identity = identity, .providers = providers };
    }
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
