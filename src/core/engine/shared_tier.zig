//! A per-user tier below the work directory's store (C2e1): records of the kinds an engine `share`s are published to it
//! and a local miss consults it. A record is addressed by its key (kind, code identity and argument digested), validated
//! by its reads exactly as a local one is, so what is shared is safe by construction: another worktree at another path
//! finds the same key only for the same code and the same argument, and serves it only while every read still holds.
//!
//! The engine knows only this interface. `shared_records.zig` implements it over the native test store's record tier and
//! `compiler_records.zig` over the compiler artifact store, which also holds the objects a record's payload points to
//! (leased, LRU-bounded, under the store's retention). Every failure is a miss: the tier is a cache.
const std = @import("std");
const digest_rules = @import("digest.zig");
const Digest = digest_rules.Digest;

/// What publishing a record did.
pub const Outcome = enum {
    /// The record was written.
    stored,
    /// The same record was already there; its recency was refreshed.
    present,
    /// A record of the same key holds another result. It is kept, nothing is written, and the pair is logged: a
    /// determinism mismatch is a miss for both sides.
    mismatch,
    /// A collection holds the store, so nothing was written and nothing waited.
    skipped,
    /// The write failed.
    failed,
};

/// What a tier does with the objects a record's payload points to.
pub const ObjectOps = struct {
    /// The bytes of the object named `digest` (the digest of its bytes) in `a`, or null (absent, damaged, unreadable).
    fetch: *const fn (context: *anyopaque, a: std.mem.Allocator, digest: Digest) ?[]const u8,
    /// Publish the object `bytes`, which hash to `digest`.
    publish: *const fn (context: *anyopaque, a: std.mem.Allocator, digest: Digest, bytes: []const u8) Outcome,
};

/// The operations the engine asks of a tier.
pub const VTable = struct {
    /// The bytes of the record under `key` in `a`, or null (absent, damaged, unreadable).
    fetch: *const fn (context: *anyopaque, a: std.mem.Allocator, key: Digest) ?[]const u8,
    /// Whether a record of `key` is there (a stat; no recency change).
    contains: *const fn (context: *anyopaque, key: Digest) bool,
    /// Whether the record under `key` is exactly `bytes`, answered without reading the record's content (from what its header says it
    /// holds). Null in a tier that cannot tell; `Tier.holds` is then false and the caller fetches the record to compare.
    holds: ?*const fn (context: *anyopaque, key: Digest, bytes: []const u8) bool = null,
    /// A digest naming this tier (its directory, say): a stamp made against one tier does not stand for another. Null in a tier that cannot name
    /// itself; the engine then asks it about every record it serves from the work directory (`Tier.identity`).
    identity: ?*const fn (context: *anyopaque) Digest = null,
    /// Publish `bytes`, a record under `key` whose result digest is `result`.
    publish: *const fn (context: *anyopaque, a: std.mem.Allocator, key: Digest, bytes: []const u8, result: Digest) Outcome,
    /// Delete the record under `key`: a caller found it wrong. Absence is success.
    forget: *const fn (context: *anyopaque, key: Digest) void,
    /// The tier's objects, for a tier that keeps them. A tier that keeps records only leaves this null, and then a record whose payload is an
    /// object stays in the work directory.
    objects: ?ObjectOps = null,
};

/// Which queries of a shared kind may use the tier. A kind marked shared with a filter sends and takes only the records
/// whose argument the filter allows; the others stay local. Asked with the argument alone, so a record's eligibility is a
/// function of what the record is a record of.
pub const Filter = struct {
    context: *anyopaque,
    allows: *const fn (context: *anyopaque, argument: []const u8) bool,
};

/// A tier: an opaque context and the operations over it.
pub const Tier = struct {
    context: *anyopaque,
    vtable: *const VTable,

    /// The bytes of the record under `key`, or null.
    pub fn fetch(self: Tier, a: std.mem.Allocator, key: Digest) ?[]const u8 {
        return self.vtable.fetch(self.context, a, key);
    }

    /// Whether a record of `key` is there.
    pub fn contains(self: Tier, key: Digest) bool {
        return self.vtable.contains(self.context, key);
    }

    /// Whether the record under `key` is exactly `bytes`, told without reading the record. False when the tier cannot tell, so a
    /// false answer is "fetch it and look", never "it differs".
    pub fn holds(self: Tier, key: Digest, bytes: []const u8) bool {
        const asked = self.vtable.holds orelse return false;
        return asked(self.context, key, bytes);
    }

    /// The digest naming this tier, or null when it has none. The engine stamps a work directory's partition with it when it has asked the tier about
    /// every record it served, and asks again only when the stamp is old or names another tier (`Engine.sweeping`).
    pub fn identity(self: Tier) ?Digest {
        const named = self.vtable.identity orelse return null;
        return named(self.context);
    }

    /// Publish a record.
    pub fn publish(self: Tier, a: std.mem.Allocator, key: Digest, bytes: []const u8, result: Digest) Outcome {
        return self.vtable.publish(self.context, a, key, bytes, result);
    }

    /// Delete the record under `key`.
    pub fn forget(self: Tier, key: Digest) void {
        self.vtable.forget(self.context, key);
    }

    /// Whether this tier keeps objects, so a record with an object payload can be shared whole.
    pub fn holdsObjects(self: Tier) bool {
        return self.vtable.objects != null;
    }

    /// The bytes of the object named `digest`, or null (absent, damaged, or a tier with no objects). The caller checks them
    /// against the name.
    pub fn fetchObject(self: Tier, a: std.mem.Allocator, digest: Digest) ?[]const u8 {
        const ops = self.vtable.objects orelse return null;
        return ops.fetch(self.context, a, digest);
    }

    /// Publish the object `bytes` under `digest`; `.failed` in a tier with no objects.
    pub fn publishObject(self: Tier, a: std.mem.Allocator, digest: Digest, bytes: []const u8) Outcome {
        const ops = self.vtable.objects orelse return .failed;
        return ops.publish(self.context, a, digest, bytes);
    }
};
