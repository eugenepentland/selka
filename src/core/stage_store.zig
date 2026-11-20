//! Verified, content-addressed intermediate compiler artifacts. Cache failures
//! lose reuse, never a build: bounded, checked journal records become immutable packs.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const codec = @import("selka").persist_codec;
const unit_cache = @import("unit_cache.zig");
const stage_scopes = @import("stage_scopes.zig");
const stage_tally = @import("stage_tally.zig");
const leases = @import("stage_leases.zig");
/// The collector of the shared namespace, for the cache command.
pub const collector = @import("stage_collector.zig");
const scopes = @import("stage_scopes.zig");
const build_identity = @import("build_identity");

/// A compiler-stage input or artifact digest.
pub const Digest = [32]u8;
/// Cache I/O failures are misses; allocation failures remain explicit.
pub const Error = std.mem.Allocator.Error;

const magic = "selka-stage-v2\n";
/// The pack and journal format bound into every stage store file. Records do not depend on it for identity: each key
/// binds its own stage identity (`StageDigests`), so a pack of another compiler is never served for a key.
const pack_format_text = "selka-stage-pack-format-v2";
/// One digest per stage in `stage_scopes.Stage` order: the identity a record's key binds for its scope's stage.
pub const StageDigests = [scopes.stage_count]Digest;
const packs = @import("stage_pack.zig");
/// One record of a batch: its key and payload (`Store.saveAll`).
pub const Save = packs.Save;

/// Store-local settings; existing blocks retain their encoding. The default writes uncompressed blocks
/// (`stage_compression.default_policy`). `shared` names the per-user stage store's directory (`stage_store_root`), and
/// `publish` says whether this store writes to it or only reads it.
pub const Options = struct {
    compression: @import("stage_compression.zig").Policy = @import("stage_compression.zig").default_policy,
    shared: ?[]const u8 = null,
    publish: bool = true,
    /// The stage identities a key binds. Null is the build's own (`defaultStageDigests`); tests inject others.
    identities: ?StageDigests = null,
    /// Count each scope's loads and saves (`Store.tallies`). Off by default: a build that reports nothing pays nothing.
    observe: bool = false,
    /// Share the directory's catalog with the other stores of this process (`packs.State.acquire`): a session lists the
    /// directory and reads only the packs no earlier session indexed. For a store of content-keyed records that a session
    /// only queries and appends to; the store then names no build's roots (`touchedKeys` is empty).
    process_shared: bool = false,
};

/// The format digest of the stage store files (`pack_format_text`).
fn packFormat() Digest {
    var format: Digest = undefined;
    fast_blake3.hash(pack_format_text, &format);
    return format;
}

/// The identities this build's keys bind: each generated stage identity, then the whole compiler identity for the
/// `whole` stage (`build_identity.zig` renders the stage identities in `stage_scopes.Stage` order).
pub fn defaultStageDigests() StageDigests {
    comptime std.debug.assert(build_identity.stage_identities.len + 1 == scopes.stage_count);
    var out: StageDigests = undefined;
    for (build_identity.stage_identities, 0..) |text, index| fast_blake3.hash(text, &out[index]);
    fast_blake3.hash(build_identity.compiler_identity, &out[scopes.stage_count - 1]);
    return out;
}

/// The directory leaf of the shared store's namespace under the selected root (`shared_cache_policy.Tier.stages`).
pub const shared_leaf = "stage-artifacts-v1";

/// The per-user shared stage store of one `Store`: its packs, whether this process publishes to it, the keys the scope
/// table routes to it, and this process's lease on the namespace. `Store.key` records those keys, so `load`, `save` and
/// `contains` find the store a digest belongs to.
pub const Shared = struct {
    state: *packs.State,
    publish: bool,
    root: []const u8,
    lease: leases.Lease,
    mutex: std.Io.Mutex = .init,
    /// Each key the scope table routes here, with what its scope says of it (`KeyFlags`).
    keys: std.AutoHashMapUnmanaged(Digest, KeyFlags) = .empty,
};

/// What the scope table says of a key of the shared store: whether a differing payload replaces the stored record
/// (`stage_scopes.replaces`) and whether a build reads its work directory's record first (`stage_scopes.privateFirst`).
const KeyFlags = struct { replaces: bool, private_first: bool };

/// The demand-state generations one build reads and writes (`demand_generation.zig`): the current one, the one it
/// publishes, and the last full build's (the highest published), which a lookup consults as a second candidate.
/// Generation 0 is the ungenerated key, which a store without generations uses.
pub const Generations = struct { read: u64 = 0, write: u64 = 0, last: u64 = 0 };

/// Immutable shared store settings. Backing must support concurrent callers when
/// emission workers share this store; each operation uses a private scratch arena.
pub const Store = struct {
    backing: std.mem.Allocator,
    io: std.Io,
    /// The identity each stage binds in a key (`stageOf` picks the stage of a scope).
    stages: StageDigests,
    storage: *packs.State,
    /// Which generation of last-writer demand state this store's build reads and writes.
    generations: Generations = .{},
    /// The shared store, when one was selected and opened; null keeps every record private.
    shared: ?*Shared = null,
    /// The per-scope counts, when the store observes (`Options.observe`); shared by the copies of this store.
    tally: ?*stage_tally.Tally = null,

    /// Prepare a lazily created store bound to the complete compiler identity.
    pub fn init(backing: std.mem.Allocator, io: std.Io, cache_root: []const u8) Error!Store {
        return initWithOptions(backing, io, cache_root, .{});
    }

    /// Select new block encoding while preserving stage keys and read compatibility.
    pub fn initWithOptions(backing: std.mem.Allocator, io: std.Io, cache_root: []const u8, options: Options) Error!Store {
        const root = try std.fs.path.join(backing, &.{ cache_root, "stages-packed-v1" });
        // A process-shared state keeps its own copy of the root; a private one owns this string until `deinit`.
        errdefer if (!options.process_shared) backing.free(root);
        defer if (options.process_shared) backing.free(root);
        const format = packFormat();
        const stages = options.identities orelse defaultStageDigests();
        const storage = if (options.process_shared) try packs.State.acquire(io, root, format, options.compression) else try packs.State.init(backing, io, root, format, options.compression);
        errdefer storage.deinit();
        const shared = if (options.shared) |directory| try openShared(backing, io, directory, format, options) else null;
        const tally = if (options.observe) try newTally(backing) else null;
        return .{ .backing = backing, .io = io, .stages = stages, .storage = storage, .shared = shared, .tally = tally };
    }

    /// Open the shared namespace under `directory`. An unusable directory keeps the store private: the records are then
    /// computed again, which costs warmth and nothing else. Only allocation failures are errors.
    pub fn openShared(backing: std.mem.Allocator, io: std.Io, directory: []const u8, format: Digest, options: Options) Error!?*Shared {
        const root = try std.fs.path.join(backing, &.{ directory, shared_leaf });
        errdefer backing.free(root);
        std.Io.Dir.cwd().createDirPath(io, root) catch {
            backing.free(root);
            return null;
        };
        const state = packs.State.init(backing, io, root, format, options.compression) catch |err| {
            backing.free(root);
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
        errdefer state.deinit();
        state.config.check = true;
        // Without a lease the collector cannot see this process, so the namespace is not used at all.
        const lease = (try leases.register(backing, io, root)) orelse {
            state.deinit();
            backing.free(root);
            return null;
        };
        const shared = try backing.create(Shared);
        shared.* = .{ .state = state, .publish = options.publish, .root = root, .lease = lease };
        return shared;
    }

    /// A tally allocated from `backing`, with its first scope named (`stage_tally.Tally.init`).
    fn newTally(backing: std.mem.Allocator) Error!*stage_tally.Tally {
        const tally = try backing.create(stage_tally.Tally);
        tally.* = try stage_tally.Tally.init(backing);
        return tally;
    }

    /// Release the owned path after all users of the store finish.
    pub fn deinit(self: *Store) void {
        const root = self.storage.config.root;
        const borrowed = self.storage.config.process;
        self.storage.deinit();
        if (self.tally) |tally| {
            tally.deinit(self.backing);
            self.backing.destroy(tally);
        }
        if (self.shared) |shared| closeShared(self.backing, self.io, shared);
        if (!borrowed) self.backing.free(root);
    }

    /// Close a shared namespace: its packs, its lease and its key table.
    fn closeShared(backing: std.mem.Allocator, io: std.Io, shared: *Shared) void {
        shared.state.deinit();
        shared.lease.release(io, backing);
        shared.keys.deinit(backing);
        backing.free(shared.root);
        backing.destroy(shared);
    }

    /// What `selka cache gc` and `selka cache configure --kind stages` ask of the shared stage store: a cap for this run (gc) or to persist
    /// (configure), and whether gc deletes (`apply`) or previews.
    pub const Maintenance = struct { max_bytes: ?u64 = null, apply: bool = false, configure: bool = false };

    /// The policy in force after a maintenance command, and the collection's report (null for `configure`, or when another collector held
    /// the lock).
    pub const Maintained = struct { policy: collector.Policy, report: ?collector.Report };

    /// Run one maintenance command on the shared namespace under `directory` (the root `SELKA_STAGE_SHARED_CACHE` names). Null when the
    /// namespace does not exist or cannot be opened: a first build creates it, and these commands never do.
    pub fn maintain(backing: std.mem.Allocator, io: std.Io, directory: []const u8, request: Maintenance) Error!?Maintained {
        var scratch = std.heap.ArenaAllocator.init(backing);
        defer scratch.deinit();
        const a = scratch.allocator();
        const root = try std.fs.path.join(a, &.{ directory, shared_leaf });
        std.Io.Dir.cwd().access(io, root, .{}) catch return null;
        const shared = (try openShared(backing, io, directory, packFormat(), .{ .publish = false })) orelse return null;
        defer closeShared(backing, io, shared);
        var policy = collector.loadPolicy(a, io, shared.root);
        if (request.max_bytes) |bytes| policy.max_bytes = bytes;
        if (request.configure) {
            collector.savePolicy(a, io, shared.root, policy) catch return null;
            return .{ .policy = policy, .report = null };
        }
        const report = try collector.collectNow(a, io, shared.root, shared.state, .{ .cap = policy.max_bytes, .now = 0, .dry_run = !request.apply });
        return .{ .policy = policy, .report = report };
    }

    /// Whether this store reads a shared namespace (`Options.shared` named a usable directory).
    pub fn readsShared(self: *const Store) bool {
        return self.shared != null;
    }

    /// Whether this store reads a shared namespace and publishes to it (`Options.publish`).
    pub fn publishesShared(self: *const Store) bool {
        const shared = self.shared orelse return false;
        return shared.publish;
    }

    /// The shared store a digest belongs to, when the digest's scope routes it there (`Store.key`).
    fn sharedState(self: *const Store, digest: Digest) ?*packs.State {
        const shared = self.shared orelse return null;
        shared.mutex.lockUncancelable(self.io);
        defer shared.mutex.unlock(self.io);
        return if (shared.keys.contains(digest)) shared.state else null;
    }

    /// What the scope table says of a key of the shared store; null for a key that is not routed there.
    fn flagsOf(self: *const Store, digest: Digest) ?KeyFlags {
        const shared = self.shared orelse return null;
        shared.mutex.lockUncancelable(self.io);
        defer shared.mutex.unlock(self.io);
        return shared.keys.get(digest);
    }

    /// The shared store a digest is published to: routed there, and this store publishes.
    fn publishingState(self: *const Store, digest: Digest) ?*packs.State {
        const shared = self.shared orelse return null;
        if (!shared.publish) return null;
        return self.sharedState(digest);
    }

    /// Publish this build's live root to the shared namespace and collect it when due (`stage_collector.zig`). Best effort:
    /// a failure here costs warmth, never a result. Does nothing when this store has no shared namespace or does not publish.
    pub fn publishShared(self: *const Store, a: std.mem.Allocator) void {
        const shared = self.shared orelse return;
        if (!shared.publish) return;
        _ = self.storage.flush() catch return;
        _ = shared.state.flush() catch return;
        const keys = shared.state.touchedKeys(a) catch return;
        const work = std.fs.path.dirname(self.storage.config.root) orelse return;
        collector.writeRoot(a, self.io, shared.root, work, keys);
        _ = collector.collectIfDue(a, self.io, shared.root, shared.state, collector.loadPolicy(a, self.io, shared.root).max_bytes) catch return;
    }

    /// Remember that a shared scope produced `digest`. A key that cannot be remembered stays private: a miss, never a
    /// record in the wrong store.
    fn noteShared(self: *const Store, shared: *Shared, digest: Digest, scope: []const u8) void {
        shared.mutex.lockUncancelable(self.io);
        defer shared.mutex.unlock(self.io);
        // Out of memory leaves the key out of the map: it stays private, a miss, never a record in the wrong store.
        shared.keys.put(self.backing, digest, .{ .replaces = stage_scopes.replaces(scope), .private_first = stage_scopes.privateFirst(scope) }) catch return;
    }

    /// Bind length-delimited inputs to a stage schema and this compiler.
    pub fn key(self: *const Store, scope: []const u8, parts: []const []const u8) Digest {
        const identity = &self.stages[@as(usize, @backingInt(scopes.stageOf(scope)))];
        const digest = keyDigest(identity, scope, parts);
        if (self.shared) |shared| if (stage_scopes.routeOf(scope) == .shared) self.noteShared(shared, digest, scope);
        if (self.tally) |tally| tally.noteScope(self.io, self.backing, digest, scope);
        return digest;
    }

    /// The bytes of a key's input a stack buffer holds; a longer input is hashed in pieces.
    const key_buffer_bytes = 1024;

    /// The digest of the fields `magic`, the stage `identity`, `scope` and every part, each as a u64 length and its bytes
    /// (`unit_cache.field`). An input that fits the stack buffer is written out and hashed in one call: the incremental form
    /// costs a call into the hash object per length and per field (about 16 for a key of three parts), the one-shot form one.
    /// Both forms hash the same byte stream, so the digest is the same.
    fn keyDigest(identity: *const Digest, scope: []const u8, parts: []const []const u8) Digest {
        var digest: Digest = undefined;
        var buffer: [key_buffer_bytes]u8 = undefined;
        var used: usize = 0;
        var fits = appendField(&buffer, &used, magic) and appendField(&buffer, &used, identity) and appendField(&buffer, &used, scope);
        if (fits) for (parts) |part| {
            if (!appendField(&buffer, &used, part)) {
                fits = false;
                break;
            }
        };
        if (fits) {
            fast_blake3.hash(buffer[0..used], &digest);
            return digest;
        }
        var hash = fast_blake3.Blake3.init(.{});
        unit_cache.field(&hash, magic);
        unit_cache.field(&hash, identity);
        unit_cache.field(&hash, scope);
        for (parts) |part| unit_cache.field(&hash, part);
        hash.final(&digest);
        return digest;
    }

    /// Append `piece` to `buffer` as a u64 length and its bytes; false, and nothing written, when it does not fit.
    fn appendField(buffer: []u8, used: *usize, piece: []const u8) bool {
        if (used.* + 8 + piece.len > buffer.len) return false;
        std.mem.writeInt(u64, buffer[used.*..][0..8], piece.len, .little);
        @memcpy(buffer[used.* + 8 ..][0..piece.len], piece);
        used.* += 8 + piece.len;
        return true;
    }

    /// The key of last-writer demand state this build reads: the generation it reads
    /// (`generations.read`), so a replayed tree's state is found, not the last built one's.
    pub fn readKey(self: *const Store, scope: []const u8, parts: []const []const u8) Digest {
        return self.generationKey(scope, parts, self.generations.read);
    }

    /// The key of last-writer demand state this build publishes (`generations.write`).
    pub fn writeKey(self: *const Store, scope: []const u8, parts: []const []const u8) Digest {
        return self.generationKey(scope, parts, self.generations.write);
    }

    /// Record `keys` as needed by this build though it did not load them (`stage_pack.State.need`): the records a stored manifest or
    /// header names. Best effort: a key that cannot be recorded is a record compaction may drop, which costs a miss.
    pub fn need(self: *const Store, keys: []const Digest) void {
        self.storage.need(keys) catch return;
    }

    /// The keys this store's build touched (loaded, checked or saved), in the order it first needed them: the roots of
    /// its generation (`stage_roots.zig`).
    pub fn touchedKeys(self: *const Store, a: std.mem.Allocator) Error![]const Digest {
        return self.storage.touchedKeys(a);
    }

    /// `key` with the generation as a further part; generation 0 is `key` itself.
    fn generationKey(self: *const Store, scope: []const u8, parts: []const []const u8, generation: u64) Digest {
        if (generation == 0) return self.key(scope, parts);
        var number: [8]u8 = undefined;
        std.mem.writeInt(u64, &number, generation, .little);
        var all: [8][]const u8 = undefined;
        @memcpy(all[0..parts.len], parts);
        all[parts.len] = &number;
        return self.key(scope, all[0 .. parts.len + 1]);
    }

    /// `key` of `scope` and `parts` under an explicit demand-state generation (generation 0 is `key`).
    pub fn keyAt(self: *const Store, scope: []const u8, parts: []const []const u8, generation: u64) Digest {
        return self.generationKey(scope, parts, generation);
    }

    /// Whether a record of `digest` is already stored, so a writer of content-keyed records skips the bytes it has.
    pub fn contains(self: *const Store, digest: Digest) Error!bool {
        const registered = self.sharedState(digest);
        if (registered) |state| if (try state.contains(digest)) return true;
        if (try self.storage.contains(digest)) return true;
        if (registered == null) if (self.shared) |shared| return shared.state.contains(digest);
        return false;
    }

    /// Publish pending journal records as immutable compressed packs, in both stores.
    pub fn flush(self: *const Store) Error!bool {
        const private = try self.storage.flush();
        const shared = if (self.shared) |store| try store.state.flush() else true;
        return private and shared;
    }

    /// The per-scope loads and saves this store counted (`Options.observe`), sorted by scope name and listing only scopes
    /// with a count; empty when the store does not observe. The names are borrowed until `deinit`; the slice is owned by `a`.
    pub fn tallies(self: *const Store, a: std.mem.Allocator) Error![]const stage_tally.ScopeCount {
        const tally = self.tally orelse return &.{};
        return tally.snapshot(self.io, a);
    }

    /// Physical packed reads and block decoding expose warm-path amplification.
    pub fn statistics(self: *const Store) packs.Statistics {
        return self.storage.statistics();
    }

    /// Locate the durable file containing a key for diagnostics and loss tests.
    pub fn artifactPath(self: *const Store, a: std.mem.Allocator, digest: Digest) Error!?[]const u8 {
        return self.storage.artifactPath(a, digest);
    }

    /// Read an owned payload after validating its complete key and checksum.
    /// Absent, oversized, truncated, foreign, and damaged entries are misses.
    pub fn load(self: *const Store, a: std.mem.Allocator, digest: Digest) Error!?[]u8 {
        return self.loadExpected(a, digest, null);
    }

    /// Validate a known canonical payload digest during the ordinary checksum
    /// pass, avoiding a second hash by callers that already know its identity.
    /// A digest this process computed with `key` is read from the store its scope routes it to, then from the other store.
    /// A digest it did not compute (a record names it, as a receipt names its artifact) is read from the work directory and
    /// then from the shared store: a record another process published there is found, never routed away from.
    pub fn loadExpected(self: *const Store, a: std.mem.Allocator, digest: Digest, expected: ?Digest) Error!?[]u8 {
        const bytes = try self.loadFound(a, digest, expected);
        if (self.tally) |tally| tally.count(self.io, digest, if (bytes == null) .miss else .hit);
        return bytes;
    }

    /// `loadExpected` without the count: the shared store the digest is routed to, then the work directory, then the shared store.
    fn loadFound(self: *const Store, a: std.mem.Allocator, digest: Digest, expected: ?Digest) Error!?[]u8 {
        const flags = self.flagsOf(digest);
        const registered = self.sharedState(digest);
        // The artifact of a function this build lowered in another order than the shared store's first writer is kept in the work
        // directory (`saveAll`), and it is the one this build can replay; the shared store's is read when the work directory has none.
        if (flags) |known| if (known.private_first and try self.storage.holds(digest)) {
            if (try self.storage.load(a, digest, expected)) |bytes| return bytes;
        };
        if (registered) |state| if (try state.load(a, digest, expected)) |bytes| return bytes;
        if (try self.storage.load(a, digest, expected)) |bytes| return bytes;
        if (registered == null) if (self.shared) |shared| return shared.state.load(a, digest, expected);
        return null;
    }

    /// Log that the record of `digest` did not fit the program a build restored it into (`packs.State.logUnfit`), in the
    /// store that serves it: the work directory when it holds the key, else the shared store. Best effort.
    pub fn noteUnfit(self: *const Store, digest: Digest) void {
        const state = state: {
            if (self.storage.holds(digest) catch false) break :state self.storage;
            if (self.shared) |shared| break :state shared.state;
            break :state self.storage;
        };
        state.logUnfit(digest);
    }

    /// Publish a complete journal record before returning; cache I/O fails closed.
    pub fn save(self: *const Store, digest: Digest, payload: []const u8) Error!bool {
        if (self.tally) |tally| tally.count(self.io, digest, .save);
        if (self.publishingState(digest)) |state| {
            const flags = self.flagsOf(digest) orelse KeyFlags{ .replaces = false, .private_first = false };
            var kept_back = false;
            const stored = try state.saveAll(&.{.{ .key = digest, .payload = payload, .replace = flags.replaces, .mismatched = if (flags.private_first) &kept_back else null }});
            return (!kept_back or try self.keepBack(digest, payload)) and stored;
        }
        return self.storage.save(digest, payload);
    }

    /// Publish a batch of records: the shared ones to the shared store (which keeps the catalogued copy of a key it holds
    /// with the same checksum, `packs.State.unseen`), the rest to the work directory. The caller decides which records are new.
    pub fn saveAll(self: *const Store, saves: []const packs.Save) Error!bool {
        if (self.tally) |tally| for (saves) |item| tally.count(self.io, item.key, .save);
        if (self.shared == null or !self.shared.?.publish) return self.storage.saveAll(saves);
        var shared_saves: std.ArrayList(packs.Save) = .empty;
        defer shared_saves.deinit(self.backing);
        var private_saves: std.ArrayList(packs.Save) = .empty;
        defer private_saves.deinit(self.backing);
        // One flag per save, set by the shared store when it holds another payload under the key of a record whose scope is read from the
        // work directory first (`stage_scopes.privateFirst`): such a record is kept in the work directory (`keepBack`).
        const refused = try self.backing.alloc(bool, saves.len);
        defer self.backing.free(refused);
        @memset(refused, false);
        for (saves, refused) |item, *flag| {
            if (self.publishingState(item.key) != null) {
                var routed = item;
                const flags = self.flagsOf(item.key) orelse KeyFlags{ .replaces = false, .private_first = false };
                routed.replace = flags.replaces;
                if (flags.private_first) routed.mismatched = flag;
                try shared_saves.append(self.backing, routed);
            } else {
                try private_saves.append(self.backing, item);
            }
        }
        var stored = true;
        if (shared_saves.items.len > 0) {
            stored = (try self.shared.?.state.saveAll(shared_saves.items)) and stored;
            for (shared_saves.items) |routed| {
                if (routed.mismatched) |flag| if (flag.* and !try self.keepBack(routed.key, routed.payload)) {
                    stored = false;
                };
            }
        }
        if (private_saves.items.len > 0) stored = (try self.storage.saveAll(private_saves.items)) and stored;
        return stored;
    }

    /// Keep a record the shared store refused (it holds another payload under the key) in the work directory, when its scope is read
    /// from there first (`stage_scopes.privateFirst`): this build's artifact of a function that the first writer lowered in another order.
    /// True when nothing needed keeping or it was written.
    fn keepBack(self: *const Store, digest: Digest, payload: []const u8) Error!bool {
        const flags = self.flagsOf(digest) orelse return true;
        if (!flags.private_first) return true;
        return self.storage.save(digest, payload);
    }

    /// Decode plain slice-owned data into the caller's arena; invalid schemas miss.
    /// Callers validate stage-specific indices before applying the restored value.
    pub fn loadValue(self: *const Store, arena: std.mem.Allocator, digest: Digest, comptime T: type) Error!?T {
        const bytes = try self.load(self.backing, digest) orelse return null;
        defer self.backing.free(bytes);
        var reader = codec.Reader.init(arena, bytes);
        const value = reader.read(T) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
        if (!reader.done()) return null;
        return value;
    }

    /// Encode and publish plain slice-owned data without retaining encoding scratch.
    pub fn storeValue(self: *const Store, digest: Digest, comptime T: type, value: T) Error!void {
        var scratch = std.heap.ArenaAllocator.init(self.backing);
        defer scratch.deinit();
        var writer = codec.Writer.init(scratch.allocator());
        try writer.write(T, value);
        _ = try self.save(digest, writer.bytes.items);
    }
};
