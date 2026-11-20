//! Trusted embedding adapters; guest values carry identity and kind, never pointers.
const std = @import("std");
/// Stateless clock or random provider family exposed through explicit source authority.
pub const Kind = enum {
    clock,
    random,
};
/// One deterministic stand-in operation, reserved to the standard library:
/// building a stand-in of one capability kind (declared in capability-index
/// order, which the native runtime's `myl_qbe_stand_in` kind shares), or
/// moving a simulated clock. None reads a host provider or contributes an effect.
pub const StandIn = enum(u4) {
    clock,
    entropy,
    filesystem,
    network,
    environment,
    advance,
    /// `__clock_monotonic(clock)`: the clock's monotonic reading in nanoseconds, never decreasing.
    monotonic,
    /// `__clock_sleep(clock, count)`: wait `count` nanoseconds on the clock (a simulated clock advances instead).
    sleep,
    /// `__stream_memory(reserved)`: a capturing Stream whose printed text `__stream_text` reads back (the argument is unused).
    stream_memory,
    /// `__stream_text(stream)`: the text printed to a capturing Stream so far.
    stream_text,
    /// `__stand_in[Input](data)`: an in-memory `Input` that reads the octets of `data` once.
    input,
    /// `__stand_fail(capability, count)`: make a stand-in Clock or Entropy answer `count` more reads and then fail, as a
    /// provider that has stopped working does.
    fail,
    /// `__stand_in[Process](script)`: a scripted `Process` holding the packed rules of `script` (`process.scripted`).
    process,
    /// `__stand_in[Stop](reserved)`: a stand-in `Stop` that no signal reaches, not yet requested (`process.simulated_stop`).
    stop,
    /// The building operation for one capability index (the order of
    /// `Type.capabilityIndex`), or null for a stream or host capability.
    pub fn building(capability_index: u4) ?StandIn {
        if (capability_index == 9) return .stop;
        if (capability_index == 8) return .input;
        if (capability_index == 7) return .process;
        return if (capability_index <= @backingInt(StandIn.environment)) @fromBackingInt(@intCast(capability_index)) else null;
    }
    /// Operands the operation pops: the building operand, or a capability and a count.
    pub fn operands(self: StandIn) usize {
        return if (self == .advance or self == .sleep or self == .fail) 2 else 1;
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
