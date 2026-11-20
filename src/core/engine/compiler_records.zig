//! The engine's shared tier over the compiler artifact store (G4c): records and the objects their payloads point to,
//! per user, in the `compiler-artifacts-v2` namespace that `SELKA_COMPILER_SHARED_CACHE` (or the per-user default) names.
//! A tree that never compiled a module is served what another tree compiled, the same way `shared_records.zig` serves
//! test results from the native test store: a record is addressed by its key (kind, code identity and argument digested),
//! so the same record in another tree is the same query; it is served only while every read it holds still holds, and an
//! object is taken only when its bytes hash to its name.
//!
//! The artifact store gives each entry a header (key, size and BLAKE3 digest of its bytes) that every reader checks, an
//! exclusive per-key lock around publication, and the namespace's lease, size policy (10 GiB) and retention. A lookup takes
//! no lock: entries change only by atomic rename, so a vanished or damaged one is a miss. Every failure is a miss; the tier
//! is a cache.
//!
//! This file is outside every kind's closure: it imports the compiler's store, which the engine's runtime must not.
const std = @import("std");
const language = @import("selka");
const store_rules = language.shared_artifact_store;
const tier_rules = @import("shared_tier.zig");
const record_rules = @import("record.zig");
const digest_rules = @import("digest.zig");
const Digest = digest_rules.Digest;

/// The engine's records and objects in a compiler artifact store.
pub const Records = struct {
    store: store_rules.Store,

    /// Open (creating or validating) the namespace under the shared directory `directory`. Failures are the store's: an
    /// unusable explicit store is an error; the caller decides what a default one means.
    pub fn open(a: std.mem.Allocator, io: std.Io, directory: []const u8) store_rules.Error!Records {
        return .{ .store = try store_rules.Store.open(a, io, directory) };
    }

    /// Release the store's path.
    pub fn deinit(self: *Records) void {
        self.store.deinit();
    }

    /// The tier the engine consults and publishes to. The `Records` must outlive the engine.
    pub fn tier(self: *Records) tier_rules.Tier {
        return .{ .context = self, .vtable = &vtable };
    }
};

const vtable: tier_rules.VTable = .{
    .fetch = fetch,
    .contains = contains,
    .holds = holds,
    .identity = identity,
    .publish = publish,
    .forget = forget,
    .objects = .{ .fetch = fetchObject, .publish = publishObject },
};

fn fromContext(raw: *anyopaque) *Records {
    return @ptrCast(@alignCast(raw));
}

fn fetch(raw: *anyopaque, a: std.mem.Allocator, key: Digest) ?[]const u8 {
    const found = fromContext(raw).store.load(a, .engine_record, key) catch return null;
    return found;
}

fn contains(raw: *anyopaque, key: Digest) bool {
    return fromContext(raw).store.present(.engine_record, key);
}

fn holds(raw: *anyopaque, key: Digest, bytes: []const u8) bool {
    return fromContext(raw).store.holds(.engine_record, key, bytes);
}

/// The tier is named by the directory its store lives in.
fn identity(raw: *anyopaque) Digest {
    return digest_rules.hash(fromContext(raw).store.root);
}

fn forget(raw: *anyopaque, key: Digest) void {
    fromContext(raw).store.remove(.engine_record, key);
}

/// Publish a record. The store compares bytes, but two trees' encodings of one result differ in the stat tuples of their
/// reads, so the comparison here is the result digest: an existing record with the same result is `present`. Another result
/// is a determinism mismatch, logged, only when the two records read the same things and read something (`disagrees`). The
/// store is offered the bytes without logging (`Store.offer`), so a record another process published between the lookup here
/// and the store's own comparison is judged the same way.
fn publish(raw: *anyopaque, a: std.mem.Allocator, key: Digest, bytes: []const u8, result: Digest) tier_rules.Outcome {
    const self = fromContext(raw);
    if (self.store.load(a, .engine_record, key) catch null) |held| {
        if (record_rules.decode(a, held)) |existing| {
            return judge(self, a, key, existing, .{ .bytes = bytes, .result = result });
        } else |_| {}
        // A damaged record: replace it. The store keeps a valid record of other bytes, so remove this one first.
        self.store.remove(.engine_record, key);
    }
    const offered = self.store.offer(.engine_record, key, bytes) catch return .failed;
    if (offered != .mismatch) return outcome(offered);
    const held = (self.store.load(a, .engine_record, key) catch null) orelse return .skipped;
    const existing = record_rules.decode(a, held) catch return .skipped;
    return judge(self, a, key, existing, .{ .bytes = bytes, .result = result });
}

/// A record being published: its bytes and its result digest.
const Offered = struct { bytes: []const u8, result: Digest };

/// What the tier says of `offered` when the store already holds `existing` under `key`: `present` for the same result,
/// `skipped` for another variant or another table (`disagrees`), and a logged `mismatch` for a determinism failure.
fn judge(self: *Records, a: std.mem.Allocator, key: Digest, existing: record_rules.Record, offered: Offered) tier_rules.Outcome {
    if (std.mem.eql(u8, &existing.result, &offered.result)) return .present;
    if (!disagrees(a, existing, offered.bytes)) return .skipped;
    self.store.mismatch(.engine_record, key, existing.result, offered.result);
    return .mismatch;
}

/// Whether a held record with another result than `bytes` (the record being published) is a determinism mismatch: both read
/// the same things, by `record_rules.readSignature`, and that is something. Two records of one address whose reads differ are
/// two variants of the query, and the second lost a race for the slot to the first (`Engine.variantSlot` chose the address
/// before the first was published, or after another process forgot it); the reader serves each only where its reads hold. A
/// record that reads nothing (`ownership-proof`, whose answer is a table its writer replaces and every reader validates by
/// digest, D-48) is not a function of its reads, so another table under its key says nothing about determinism. A record
/// being published that cannot be decoded is compared as before.
fn disagrees(a: std.mem.Allocator, existing: record_rules.Record, bytes: []const u8) bool {
    const offered = record_rules.decode(a, bytes) catch return true;
    if (existing.reads.len == 0 and offered.reads.len == 0) return false;
    return std.mem.eql(u8, &record_rules.readSignature(existing.reads), &record_rules.readSignature(offered.reads));
}

fn fetchObject(raw: *anyopaque, a: std.mem.Allocator, digest: Digest) ?[]const u8 {
    const found = fromContext(raw).store.load(a, .engine_object, digest) catch return null;
    return found;
}

fn publishObject(raw: *anyopaque, _: std.mem.Allocator, digest: Digest, bytes: []const u8) tier_rules.Outcome {
    return outcome(fromContext(raw).store.save(.engine_object, digest, bytes));
}

fn outcome(saved: store_rules.Error!store_rules.Publication) tier_rules.Outcome {
    const published = saved catch return .failed;
    return switch (published) {
        .stored => .stored,
        .present => .present,
        .mismatch => .mismatch,
        .skipped => .skipped,
    };
}
