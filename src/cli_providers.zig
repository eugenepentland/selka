//! Trusted host adapters behind the command line's explicit capability grants.
//! These run in the compiler process: they are an authority boundary for guest
//! source, never a sandbox against a compromised compiler or host.
const std = @import("std");
const language = @import("mylang");

/// Unix-epoch wall clock; the guest sees nanoseconds and no monotonicity promise.
pub const Clock = struct {
    io: std.Io,
    /// Borrow this stable context as the VM's clock provider.
    pub fn provider(self: *Clock) language.external_capabilities.Clock {
        return .{ .context = self, .read = read };
    }
    fn read(raw: *anyopaque) language.external_capabilities.CallError!i64 {
        const self: *Clock = @ptrCast(@alignCast(raw));
        const now = std.Io.Timestamp.now(self.io, .real);
        return std.math.cast(i64, now.nanoseconds) orelse error.Failed;
    }
};

/// A reproducible pseudorandom stream, seeded by the grant or by the host clock.
/// This is a deterministic generator, not a cryptographic entropy source; a
/// program that needs one must be embedded with its own `Random` provider.
pub const Entropy = struct {
    prng: std.Random.DefaultPrng,
    /// Seed from the grant when it names one, otherwise from the wall clock.
    pub fn init(io: std.Io, seed: ?u64) Entropy {
        const chosen = seed orelse @as(u64, @bitCast(@as(i64, @truncate(std.Io.Timestamp.now(io, .real).nanoseconds))));
        return .{ .prng = .init(chosen) };
    }
    /// Borrow this stable context as the VM's entropy provider.
    pub fn provider(self: *Entropy) language.external_capabilities.Random {
        return .{ .context = self, .read = read };
    }
    fn read(raw: *anyopaque) language.external_capabilities.CallError!u64 {
        const self: *Entropy = @ptrCast(@alignCast(raw));
        return self.prng.next();
    }
};

/// Process environment restricted to an explicit comma-separated name list.
pub const Environment = struct {
    environ: *const std.process.Environ.Map,
    names: []const u8,
    /// Borrow this stable context as the VM's environment provider.
    pub fn provider(self: *Environment) language.environment.Provider {
        return .{ .context = self, .get = get };
    }
    /// An empty allowlist grants every name the host process already holds.
    fn allowed(self: *Environment, name: []const u8) bool {
        if (self.names.len == 0) return true;
        var parts = std.mem.splitScalar(u8, self.names, ',');
        while (parts.next()) |part| if (std.mem.eql(u8, part, name)) return true;
        return false;
    }
    fn get(raw: *anyopaque, name: []const u8, output: []u8) language.environment.CallError!?usize {
        const self: *Environment = @ptrCast(@alignCast(raw));
        if (!self.allowed(name)) return error.Denied;
        const value = self.environ.get(name) orelse return null;
        if (value.len > output.len) return error.NoCapacity;
        @memcpy(output[0..value.len], value);
        return value.len;
    }
};
