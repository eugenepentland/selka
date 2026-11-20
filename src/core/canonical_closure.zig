//! Canonical pre-pass function digests and complete direct call/reference closure.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const ir = @import("ir.zig");
const source_location = @import("source_location.zig");
const canonical = @import("canonical_ir.zig");

/// Canonical digest of one function implementation.
pub const Digest = canonical.Digest;
/// Allocation failure or unsupported canonical metadata.
pub const Error = canonical.Error;
const Canon = canonical.Canon;

/// One shared lowering's canonical function digests and call graph.
pub const Shared = struct {
    digests: []const Digest,
    callees: []const []const u32,

    /// Digest every function of `module` (before passes and before the test entry is
    /// added) and record whom each one calls or takes the address of. Everything is
    /// allocated in the caller's arena `a`.
    pub fn build(a: std.mem.Allocator, module: *const ir.Module, locator: source_location.Locator) Error!Shared {
        return digestAll(a, module, locator, true);
    }

    /// `build` without source positions: each function is digested as its meaning (`Canon.plainDigest`), so a line added
    /// above it, or a function moved within its file, leaves the digest as it was. This is what a test's key reaches: a passing
    /// verdict cannot observe a position (`experiments/test-keys-20261106/DECISIONS.md`, D-T1-1), and a failure is never recorded.
    pub fn plain(a: std.mem.Allocator, module: *const ir.Module, locator: source_location.Locator) Error!Shared {
        return digestAll(a, module, locator, false);
    }

    fn digestAll(a: std.mem.Allocator, module: *const ir.Module, locator: source_location.Locator, positions: bool) Error!Shared {
        var canon = try Canon.prepare(a, module, locator);
        canon.positions = positions;
        const digests = try a.alloc(Digest, module.functions.items.len);
        const callees = try a.alloc([]const u32, module.functions.items.len);
        for (module.functions.items, digests, callees, 0..) |function, *digest, *targets, index| {
            digest.* = try canon.functionDigest(@intCast(index));
            targets.* = try calls(a, function);
            for (targets.*) |target| if (target >= digests.len) return error.UnknownMetadata;
        }
        return .{ .digests = digests, .callees = callees };
    }

    /// Feed `hash` the digests of `roots`, in order, and then of every other function
    /// they reach, sorted, so the key does not depend on the shared module's order.
    pub fn reach(self: Shared, a: std.mem.Allocator, roots: []const u32, hash: *fast_blake3.Blake3) Error!void {
        if (self.callees.len != self.digests.len) return error.UnknownMetadata;
        const seen = try a.alloc(bool, self.digests.len);
        @memset(seen, false);
        var queue: std.ArrayList(u32) = .empty;
        for (roots) |root| {
            if (root >= self.digests.len) return error.UnknownMetadata;
            hash.update(&self.digests[root]);
            if (seen[root]) continue;
            seen[root] = true;
            try queue.append(a, root);
        }
        var reached: std.ArrayList(Digest) = .empty;
        var next: usize = 0;
        while (next < queue.items.len) : (next += 1) {
            for (self.callees[queue.items[next]]) |callee| {
                if (callee >= self.digests.len) return error.UnknownMetadata;
                if (seen[callee]) continue;
                seen[callee] = true;
                try queue.append(a, callee);
                try reached.append(a, self.digests[callee]);
            }
        }
        std.mem.sort(Digest, reached.items, {}, before);
        put(hash, u64, reached.items.len);
        for (reached.items) |digest| hash.update(&digest);
    }
};

/// The distinct functions `function` calls directly or takes the address of.
pub fn calls(a: std.mem.Allocator, function: ir.Function) Error![]const u32 {
    var targets: std.ArrayList(u32) = .empty;
    for (function.insts.items) |inst| {
        const target: u32 = switch (inst.op) {
            .call => @intCast(inst.a.index()),
            .func_ref => @intCast(inst.data),
            else => continue,
        };
        if (std.mem.indexOfScalar(u32, targets.items, target) == null) try targets.append(a, target);
    }
    return targets.items;
}

fn before(_: void, left: Digest, right: Digest) bool {
    return std.mem.order(u8, &left, &right) == .lt;
}

fn put(hash: *fast_blake3.Blake3, comptime T: type, value: T) void {
    var encoded: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &encoded, value, .little);
    hash.update(&encoded);
}
