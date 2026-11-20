//! The engine's shared tier over the native test store (C2e1): records of the shared kinds in `native-tests-v3/engine/`,
//! per user, under the store's lease, policy and retention. A lookup takes no lock (records change only by atomic rename
//! or unlink, so a vanished or damaged one is a miss); a publication takes the store's short publication lock, is skipped
//! while a collection holds the store, and never replaces a record whose result differs: that pair is logged in the
//! store's `mismatches.log` and counted, and the record stays.
//!
//! This file is outside every kind's closure: it imports the compiler's store, which the engine's runtime must not.
const std = @import("std");
const shared_store = @import("../test_shared_store.zig");
const tier_rules = @import("shared_tier.zig");
const record_rules = @import("record.zig");
const digest_rules = @import("digest.zig");
const Digest = digest_rules.Digest;

/// The engine's records in a native test store.
pub const Records = struct {
    store: shared_store.Store,

    /// Open (creating or validating) the store under the shared directory `directory`. Failures are the store's:
    /// an unusable explicit store is an error; the caller decides what a default one means.
    pub fn open(a: std.mem.Allocator, io: std.Io, directory: []const u8) shared_store.Error!Records {
        return .{ .store = try shared_store.Store.open(a, io, directory) };
    }

    /// The tier the engine consults and publishes to. The `Records` must outlive the engine.
    pub fn tier(self: *Records) tier_rules.Tier {
        return .{ .context = self, .vtable = &vtable };
    }
};

const vtable: tier_rules.VTable = .{ .fetch = fetch, .contains = contains, .identity = identity, .publish = publish, .forget = forget };

/// The tier is named by the directory its store lives in.
fn identity(raw: *anyopaque) Digest {
    const self: *Records = @ptrCast(@alignCast(raw));
    return digest_rules.hash(self.store.root);
}

/// The store with `a` as its scratch allocator, so a call's reads live in the caller's arena.
fn scratch(raw: *anyopaque, a: std.mem.Allocator) shared_store.Store {
    const self: *Records = @ptrCast(@alignCast(raw));
    var copy = self.store;
    copy.arena = a;
    return copy;
}

fn fetch(raw: *anyopaque, a: std.mem.Allocator, key: Digest) ?[]const u8 {
    const found = scratch(raw, a).recordRead(key) catch return null;
    return found;
}

fn contains(raw: *anyopaque, key: Digest) bool {
    const self: *Records = @ptrCast(@alignCast(raw));
    return self.store.recordPresent(key);
}

fn forget(raw: *anyopaque, key: Digest) void {
    const self: *Records = @ptrCast(@alignCast(raw));
    self.store.recordRemove(key);
}

fn publish(raw: *anyopaque, a: std.mem.Allocator, key: Digest, bytes: []const u8, result: Digest) tier_rules.Outcome {
    const store = scratch(raw, a);
    if (store.recordRead(key) catch null) |held| {
        if (record_rules.decode(a, held)) |existing| {
            if (!std.mem.eql(u8, &existing.result, &result)) {
                store.recordMismatch(key, existing.result, result);
                return .mismatch;
            }
            return .present;
        } else |_| {}
    }
    const saved = store.recordPublish(key, bytes) catch return .failed;
    return switch (saved) {
        .stored => .stored,
        .present => .present,
        .mismatch => .mismatch,
        .skipped => .skipped,
    };
}
