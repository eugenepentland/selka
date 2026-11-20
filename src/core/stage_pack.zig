//! Durable append journals sealed into immutable, independently compressed packs.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const codec = @import("selka").persist_codec;
const compression = @import("stage_compression.zig");
const process_slots = @import("selka").process_slots;
const Digest = [32]u8;
/// The catalog's key context: the hash `std.AutoHashMapUnmanaged` uses for a digest (so every iteration order is unchanged),
/// with the digest comparison as one 256-bit compare instead of a byte loop, which dominated the catalog's admissions.
const DigestContext = struct {
    /// The hash of `key`, as `AutoHashMapUnmanaged` computes it.
    pub fn hash(_: DigestContext, key: Digest) u64 {
        return std.hash_map.AutoContext(Digest).hash(.{}, key);
    }
    /// Whether two digests are equal.
    pub fn eql(_: DigestContext, a: Digest, b: Digest) bool {
        return std.mem.readInt(u256, &a, .little) == std.mem.readInt(u256, &b, .little);
    }
};
/// One record of a batch (`State.saveAll`): the key it is stored under and its payload.
/// One record to publish. `replace` says a different payload under a catalogued key is a newer value, not a mismatch: the
/// record is written and the newer sequence wins (`State.unseen`). Only self-validating records set it.
/// One record to publish. `replace` lets a differing payload replace the stored one. `mismatched`, when set, is written true when a check-publishing
/// store held a different payload under the key and kept it (the record was not written), so the caller can keep its own copy elsewhere.
pub const Save = struct { key: Digest, payload: []const u8, replace: bool = false, mismatched: ?*bool = null };
const Error = std.mem.Allocator.Error;
/// The first bytes of every pack file; the 32-byte stage identity, the u64 index length and the index digest follow it.
pub const pack_magic = "selka-pack-v1!\n\x00";
const journal_magic = "selka-journal-v1";
const lock_magic = "stage-v2";
const pack_header = pack_magic.len + 32 + 8 + 32;
const journal_header = journal_magic.len + 32;
const record_header = 112;
const block_target = 256 << 10;
const body_target = 64 << 10;
/// Records up to this many bytes share the `block_target` blocks; larger ones share `body_target` blocks.
const small_record = 4096;
const pack_target = 4 << 20;
const maximum_bytes = 256 << 20;
const maximum_block = maximum_bytes + block_target + record_header * 2;
const maximum_index = 32 << 20;
const pack_suffix = ".pack";
const journal_suffix = ".journal";
/// Decoded block bytes a store keeps for reuse across the loads of one build.
/// A build restores most of its store several times, so the budget must cover
/// the blocks a build touches, not just the blocks of one restore.
const cache_budget = 128 << 20;
/// Record bytes one compaction pass (`State.compactLive`) holds, decoded and re-packed: the default band size. A store
/// larger than a band takes several passes, each reading the blocks its band touches.
pub const default_band_bytes = 64 << 20;
/// Records one compaction pass holds, so a pack's index stays far below `maximum_index`.
const compact_band_records = 1 << 16;

/// The rank of each live record key prefix (`rankKey`), as `stage_roots.zig` orders them: lower ranks are needed first.
pub const Ranks = std.AutoHashMapUnmanaged(u64, u64);

/// The first eight bytes of a key, the form ranks and root manifests name keys by.
pub fn rankKey(key: Digest) u64 {
    return std.mem.readInt(u64, key[0..8], .little);
}

/// What a store holds against a set of ranks: its valid packs, their bytes, and the bytes of the pack records whose key ranks.
pub const Measure = struct { packs: u64 = 0, pack_bytes: u64 = 0, live_bytes: u64 = 0 };

/// What one compaction measured before and after it, and how many bands (passes over the sources) it took.
pub const Compaction = struct { before: Measure, after: Measure, passes: u64 };

/// A pack record a compaction keeps, with the rank of its key.
const Ranked = struct { location: Location, rank: u64 };

const Block = struct { offset: u64, encoded: u32, plain: u32, checksum: Digest };
const Record = struct { key: Digest, checksum: Digest, sequence: u64, block: u32 = 0, offset: u64, length: u32 };
const Index = struct { blocks: []const Block, records: []const Record };
const Validation = struct { stat: std.Io.File.Stat, length: u64, digest: Digest };
const File = struct { validation: ?Validation = null, name: []const u8, kind: enum { journal, pack }, scanned: u64 = 0, blocks: []const Block = &.{}, handle: ?Handle = null };
/// A pack the session keeps open: the file, its status when it was opened (or last touched by this process) and the path it was opened by,
/// which the existence proof of every later load names (`State.packHandle`).
const Handle = struct { file: std.Io.File, stat: std.Io.File.Stat, path: []const u8 };
/// An open file and its status, as a load reads it.
const Opened = struct { file: std.Io.File, stat: std.Io.File.Stat };
const Location = struct { file: u32, record: Record };
/// A decoded block in the cache, keyed by its pack or journal and block index.
const CacheKey = struct { file: u32, block: u32 };
/// Decoded bytes of one block, the file status they were read under, and the
/// last tick at which a load used them.
/// `bytes` is the decoded block; `base` is the allocation that holds it (an uncompressed block is cached where it was read, one byte
/// past the start of its allocation, so the tag is not copied away).
const CachedBlock = struct { bytes: []const u8, base: []const u8, stat: std.Io.File.Stat, used: u64 };
const Prepared = struct { bytes: []const u8, index: Index };
const Pending = struct { prepared: Prepared, name: []const u8, final_path: []const u8, temporary: []const u8 };
const Source = struct { file: std.Io.File, path: []const u8, stat: std.Io.File.Stat };
/// Record bytes read from an open journal, at the offsets its records admitted.
const JournalBytes = struct {
    state: *State,
    file: std.Io.File,

    fn read(self: JournalBytes, record: Record, destination: []u8) bool {
        return (self.file.readPositionalAll(self.state.config.io, destination, record.offset - record_header) catch return false) == destination.len;
    }
};
/// Record bytes already decoded from the packs a merge reads, by key.
const MergedBytes = struct {
    bytes: std.AutoHashMapUnmanaged(Digest, []const u8) = .empty,

    fn read(self: MergedBytes, record: Record, destination: []u8) bool {
        const found = self.bytes.get(record.key) orelse return false;
        if (found.len != destination.len) return false;
        @memcpy(destination, found);
        return true;
    }
};
/// A block whose every record a merge keeps: its compressed bytes are copied as they are.
const Whole = struct { block: Block, bytes: []const u8, records: []const Record };
/// Deterministic publication work; preparation counters exclude the sequence lock.
pub const Publication = struct {
    filename_lookups: u64 = 0,
    /// Records written, one per save of a batch or of a single payload.
    records_saved: u64 = 0,
    refreshes: u64 = 0,
    packs_prepared: u64 = 0,
    pack_bytes_prepared: u64 = 0,
    save_bytes_prepared: u64 = 0,
    sequence_locks: u64 = 0,
};
/// What a check-publishing store decided about its saves (`State.unseen`): records it found already catalogued with the same
/// checksum (`present`, nothing written), and records found with a different checksum (`mismatches`, kept and logged).
pub const Checks = struct {
    present: u64 = 0,
    mismatches: u64 = 0,
    /// The packs this process has read, once each: a read sets the pack's modification time (`touchRead`), which the collector
    /// uses as the read signal.
    read_files: std.AutoHashMapUnmanaged(u32, void) = .empty,
};

/// What the collector needs of one pack: its id, its modification time in nanoseconds, its bytes, and the live records it holds.
pub const PackStat = struct { id: u32, mtime: i96, bytes: u64, live: u64 };
/// Packed-block work, excluding direct journal reads and ordinary cache metadata.
pub const Statistics = struct {
    packed_bytes_read: u64 = 0,
    decoded_bytes: u64 = 0,
    blocks_decoded: u64 = 0,
    payload_bytes_returned: u64 = 0,
    block_cache_hits: u64 = 0,
    /// Pack indexes read from disk (`readIndex`). A store that adopts its process's shared catalog reads none for a pack an
    /// earlier session of the process already indexed.
    indexes_read: u64 = 0,
    publication: Publication = .{},
};
const Journal = struct { file: u32, length: u64 = journal_header, records: std.ArrayList(Record) = .empty, bytes: usize = 0 };

/// Shallow Store copies share this state; callers own exactly one deinitialization.
pub const State = struct {
    /// `check` makes saves publish only records the catalog does not hold (`unseen`): the shared stage store's rule.
    /// `process` marks a store the sessions of one process share (`acquire`): its allocator and root belong to the process,
    /// and it counts no touched keys.
    config: struct { a: std.mem.Allocator, io: std.Io, root: []const u8, identity: Digest, compression: compression.Policy, check: bool = false, process: bool = false },
    mutex: std.Io.Mutex = .init,
    catalog: struct {
        files: std.ArrayList(File) = .empty,
        names: std.StringHashMapUnmanaged(u32) = .empty,
        entries: std.HashMapUnmanaged(Digest, Location, DigestContext, std.hash_map.default_max_load_percentage) = .empty,
        sequence: u64 = 0,
        max_sequence: u64 = 0,
        scanned: bool = false,
        /// The publication counter's file, once it exists, kept open: every load asks whether another process published since the last scan,
        /// and that is a read of the counter (writers update the file in place), not an open, a read and a close.
        sequence_file: ?std.Io.File = null,
    } = .{},
    journal: ?Journal = null,
    cached: struct { blocks: std.AutoHashMapUnmanaged(CacheKey, CachedBlock) = .empty, bytes: usize = 0, tick: u64 = 0, statistics: Statistics = .{} } = .{},
    /// Every key this store was asked for, in order, repeats included: the touches `touchedKeys` de-duplicates.
    touches: std.ArrayList(Digest) = .empty,
    /// The check-publishing decisions this store made (`Checks`); a store that does not check counts nothing.
    checks: Checks = .{},

    /// Allocate shared state without creating or trusting cache files.
    pub fn init(a: std.mem.Allocator, io: std.Io, root: []const u8, identity: Digest, policy: compression.Policy) Error!*State {
        const self = try a.create(State);
        self.* = .{ .config = .{ .a = a, .io = io, .root = root, .identity = identity, .compression = policy } };
        return self;
    }

    /// What `acquire` needs to make the store of a directory the first time the process asks for it.
    const Request = struct { io: std.Io, root: []const u8, identity: Digest, policy: compression.Policy };

    /// The store of `root` that every session of this process shares, brought up to date with its directory. The process
    /// reads each pack's index once and keeps the catalog; a later session lists the directory, scans only the packs it has
    /// not seen and drops the records of packs that vanished (a compaction, a retired directory), so a lookup costs the
    /// session's own queries and not the size of the store. Release it with `deinit`. The store's memory comes from the
    /// process allocator: it outlives the session that first asked for it.
    pub fn acquire(io: std.Io, root: []const u8, identity: Digest, policy: compression.Policy) Error!*State {
        const a = process_slots.allocator();
        const key = try std.fmt.allocPrint(a, "{s}\x00{s}\x00{d}", .{ root, &identity, @backingInt(policy) });
        defer a.free(key);
        const request: Request = .{ .io = io, .root = root, .identity = identity, .policy = policy };
        const value = try process_slots.acquire(io, key, .{ .context = &request, .make = makeShared, .destroy = destroyShared });
        const state: *State = @ptrCast(@alignCast(value));
        errdefer state.deinit();
        try state.adopt();
        return state;
    }

    fn makeShared(context: *const anyopaque) Error!*anyopaque {
        const request: *const Request = @ptrCast(@alignCast(context));
        const a = process_slots.allocator();
        const owned = try a.dupe(u8, request.root);
        // UNTESTED-ERROR: the process allocator cannot be made to fail in a test; this path only frees the root copy.
        const state = init(a, request.io, owned, request.identity, request.policy) catch |err| {
            a.free(owned);
            return err;
        };
        state.config.process = true;
        return state;
    }

    fn destroyShared(value: *anyopaque) void {
        const state: *State = @ptrCast(@alignCast(value));
        const root = state.config.root;
        state.destroy();
        process_slots.allocator().free(root);
    }

    /// Bring a shared store's catalog up to date with its directory: scan the packs it has not indexed and drop the records
    /// of files that vanished. The directory is listed every time; only the packs new to the catalog are read.
    fn adopt(self: *State) Error!void {
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        var scratch = std.heap.ArenaAllocator.init(self.config.a);
        defer scratch.deinit();
        try self.refresh(scratch.allocator(), true);
    }

    /// Release this store. A private store seals its journal and frees everything; a store shared by the process
    /// seals its journal and returns to the process table, which keeps it for the next session.
    pub fn deinit(self: *State) void {
        if (self.config.process) {
            _ = self.flush() catch false;
            process_slots.release(self.config.io, self);
            return;
        }
        self.destroy();
    }

    /// Seal the journal and free the store and everything it indexes.
    fn destroy(self: *State) void {
        _ = self.flush() catch false;
        const a = self.config.a;
        self.checks.read_files.deinit(a);
        _ = self.forgetSequence();
        if (self.journal) |*journal| journal.records.deinit(a);
        for (self.catalog.files.items, 0..) |file, id| {
            self.dropHandle(@intCast(id));
            a.free(file.name);
            a.free(file.blocks);
        }
        var cached = self.cached.blocks.valueIterator();
        while (cached.next()) |block| a.free(block.base);
        self.cached.blocks.deinit(a);
        self.catalog.files.deinit(a);
        self.catalog.names.deinit(a);
        self.catalog.entries.deinit(a);
        self.touches.deinit(a);
        a.destroy(self);
    }

    /// Record `key` as one this store's build needed (`touchedKeys`).
    fn touch(self: *State, key: Digest) Error!void {
        // A store the process shares serves many sessions and names no build's roots: counting would only grow.
        if (self.config.process) return;
        try self.touches.append(self.config.a, key);
    }

    /// Record `keys` as needed by this store's build without loading them: the records a manifest or a header names that a build which
    /// reuses it never reads. A record no build touches is in no generation's roots, and compaction drops it while the manifest still
    /// names it.
    pub fn need(self: *State, keys: []const Digest) Error!void {
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        for (keys) |key| try self.touch(key);
    }

    /// The keys this store touched (loaded, checked or saved), each once, in the order it first needed them.
    pub fn touchedKeys(self: *State, a: std.mem.Allocator) Error![]const Digest {
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        // Sized once for every touch (a build touches most keys several times): the table is not grown and rehashed as it fills.
        var seen: std.HashMapUnmanaged(Digest, void, DigestContext, std.hash_map.default_max_load_percentage) = .empty;
        defer seen.deinit(a);
        try seen.ensureTotalCapacityContext(a, @intCast(self.touches.items.len), DigestContext{});
        var keys: std.ArrayList(Digest) = .empty;
        try keys.ensureTotalCapacity(a, self.touches.items.len);
        for (self.touches.items) |key| {
            const slot = seen.getOrPutAssumeCapacityContext(key, DigestContext{});
            if (!slot.found_existing) keys.appendAssumeCapacity(key);
        }
        return keys.items;
    }

    fn path(self: *State, a: std.mem.Allocator, name: []const u8) Error![]const u8 {
        return std.fs.path.join(a, &.{ self.config.root, name });
    }

    fn checksum(bytes: []const u8) Digest {
        var digest: Digest = undefined;
        fast_blake3.hash(bytes, &digest);
        return digest;
    }

    fn counter(self: *State) Error!u64 {
        var buffer: [48]u8 = undefined;
        const file = self.catalog.sequence_file orelse opened: {
            var scratch = std.heap.ArenaAllocator.init(self.config.a);
            defer scratch.deinit();
            const name = try self.path(scratch.allocator(), "sequence");
            const found = std.Io.Dir.cwd().openFile(self.config.io, name, .{}) catch return 0;
            self.catalog.sequence_file = found;
            break :opened found;
        };
        if ((file.readPositionalAll(self.config.io, &buffer, 0) catch return self.forgetSequence()) != buffer.len) return self.forgetSequence();
        if (!std.mem.eql(u8, buffer[0..8], lock_magic)) return 0;
        if (!std.mem.eql(u8, buffer[16..48], &checksum(buffer[0..16]))) return 0;
        return std.mem.readInt(u64, buffer[8..16], .little);
    }

    /// Close the kept handle on the counter, so the next read opens it by name again; the counter reads as 0, as an unreadable one does.
    fn forgetSequence(self: *State) u64 {
        if (self.catalog.sequence_file) |file| file.close(self.config.io);
        self.catalog.sequence_file = null;
        return 0;
    }

    fn refresh(self: *State, a: std.mem.Allocator, force: bool) Error!void {
        const sequence = try self.counter();
        if (!force and self.catalog.scanned and sequence == self.catalog.sequence) return;
        self.cached.statistics.publication.refreshes += 1;
        var listed: std.ArrayList(u32) = .empty;
        var directory = std.Io.Dir.cwd().openDir(self.config.io, self.config.root, .{ .iterate = true }) catch {
            if (self.config.process) try self.dropVanished(a, listed.items);
            return;
        };
        defer directory.close(self.config.io);
        // The indexes of the packs new to the catalog are read first and admitted together, so the catalog's table is sized once
        // for all their records instead of growing (and rehashing) pack by pack. A journal is admitted as it is found: a record
        // the same journal and pack hold at one sequence is the pack's either way (`admit`).
        var indexed: std.ArrayList(Indexed) = .empty;
        var adopted: usize = 0;
        errdefer for (indexed.items[adopted..]) |found| self.config.a.free(found.blocks);
        var iterator = directory.iterate();
        while (iterator.next(self.config.io) catch null) |entry| {
            if (entry.kind != .file) continue;
            const kind: File = if (std.mem.endsWith(u8, entry.name, pack_suffix)) .{ .name = entry.name, .kind = .pack } else if (std.mem.endsWith(u8, entry.name, journal_suffix)) .{ .name = entry.name, .kind = .journal } else continue;
            const id = try self.fileId(kind);
            if (self.config.process) try listed.append(a, id);
            if (kind.kind == .pack and self.catalog.files.items[id].scanned != 0) continue;
            const file = directory.openFile(self.config.io, entry.name, .{}) catch continue;
            defer file.close(self.config.io);
            if (kind.kind == .pack) {
                if (try self.readIndex(a, file, id)) |found| indexed.append(a, found) catch |err| {
                    self.config.a.free(found.blocks);
                    return err;
                };
            } else try self.scanJournal(file, id);
        }
        var incoming: usize = 0;
        for (indexed.items) |found| incoming += found.shape.records;
        try self.catalog.entries.ensureUnusedCapacity(self.config.a, @intCast(incoming));
        for (indexed.items) |found| {
            adopted += 1;
            try self.admitIndex(found);
        }
        if (self.config.process) try self.dropVanished(a, listed.items);
        self.catalog.sequence = sequence;
        self.catalog.scanned = true;
    }

    /// Forget every file the catalog indexed that `listed` (the ids a directory listing found) does not name, and the
    /// records whose newest copy lived there. A store that lives as long as its process meets compactions and retired
    /// directories that a session-long store never outlasts; a record whose pack is gone reads as absent, as any lost file
    /// does. A compaction publishes its new packs before it removes the old ones, so a record it kept is found in its new pack.
    fn dropVanished(self: *State, a: std.mem.Allocator, listed: []const u32) Error!void {
        const gone = try a.alloc(bool, self.catalog.files.items.len);
        @memset(gone, true);
        for (listed) |id| gone[id] = false;
        var any = false;
        for (gone, 0..) |vanished, id| {
            const file = &self.catalog.files.items[id];
            // A file the catalog never indexed holds no record to drop.
            if (!vanished or (file.scanned == 0 and file.validation == null)) {
                gone[id] = false;
                continue;
            }
            any = true;
            self.forget(@intCast(id));
            file.scanned = 0;
            if (self.journal) |journal| if (journal.file == id) {
                self.journal.?.records.deinit(self.config.a);
                self.journal = null;
            };
        }
        if (!any) return;
        var dead: std.ArrayList(Digest) = .empty;
        var entries = self.catalog.entries.iterator();
        while (entries.next()) |entry| {
            if (gone[entry.value_ptr.file]) try dead.append(a, entry.key_ptr.*);
        }
        for (dead.items) |key| _ = self.catalog.entries.removeContext(key, DigestContext{});
    }

    fn fileId(self: *State, file: File) Error!u32 {
        self.cached.statistics.publication.filename_lookups += 1;
        if (self.catalog.names.get(file.name)) |id| return id;
        try self.catalog.names.ensureUnusedCapacity(self.config.a, 1);
        try self.catalog.files.ensureUnusedCapacity(self.config.a, 1);
        const name = try self.config.a.dupe(u8, file.name);
        const id: u32 = @intCast(self.catalog.files.items.len);
        self.catalog.files.appendAssumeCapacity(.{ .name = name, .kind = file.kind });
        self.catalog.names.putAssumeCapacity(name, id);
        return id;
    }

    fn admit(self: *State, id: u32, record: Record) Error!void {
        self.catalog.max_sequence = @max(self.catalog.max_sequence, record.sequence);
        const slot = try self.catalog.entries.getOrPutContext(self.config.a, record.key, DigestContext{});
        const prefer = if (!slot.found_existing) true else record.sequence > slot.value_ptr.record.sequence or (record.sequence == slot.value_ptr.record.sequence and self.catalog.files.items[id].kind == .pack);
        if (prefer) slot.value_ptr.* = .{ .file = id, .record = record };
    }

    fn scanJournal(self: *State, file: std.Io.File, id: u32) Error!void {
        const size = (file.stat(self.config.io) catch return).size;
        var header: [journal_header]u8 = undefined;
        if ((file.readPositionalAll(self.config.io, &header, 0) catch return) != header.len) return;
        if (!std.mem.eql(u8, header[0..journal_magic.len], journal_magic) or !std.mem.eql(u8, header[journal_magic.len..], &self.config.identity)) return;
        var offset = @max(journal_header, self.catalog.files.items[id].scanned);
        while (offset <= size and size - offset >= record_header) {
            var bytes: [record_header]u8 = undefined;
            if ((file.readPositionalAll(self.config.io, &bytes, offset) catch break) != bytes.len) break;
            if (!validRecordHeader(&bytes)) break;
            const record = readRecord(&bytes, offset + record_header);
            if (record.length > maximum_bytes or record.length > size - offset - record_header) break;
            try self.admit(id, record);
            offset += record_header + record.length;
        }
        self.catalog.files.items[id].scanned = offset;
    }

    fn validRecordHeader(bytes: *const [record_header]u8) bool {
        return std.mem.eql(u8, bytes[80..112], &checksum(bytes[0..80]));
    }

    fn readRecord(bytes: *const [record_header]u8, offset: u64) Record {
        return .{
            .key = bytes[16..48].*,
            .checksum = bytes[48..80].*,
            .sequence = std.mem.readInt(u64, bytes[8..16], .little),
            .offset = offset,
            .length = std.math.cast(u32, std.mem.readInt(u64, bytes[0..8], .little)) orelse std.math.maxInt(u32),
        };
    }

    /// A pack index that passed every check, waiting for its records to be admitted (`admitIndex`): the index bytes (borrowed from the
    /// scan's arena), its blocks, and what the catalog records of the file.
    const Indexed = struct { id: u32, bytes: []const u8, blocks: []const Block, shape: IndexShape, validation: Validation, size: u64 };

    /// Read and check the index of pack `id`: the header names this store's identity, the index is intact, and every block and
    /// record lies within the file. Null for a pack that fails any check, which the catalog does not index.
    fn readIndex(self: *State, a: std.mem.Allocator, file: std.Io.File, id: u32) Error!?Indexed {
        self.cached.statistics.indexes_read += 1;
        var header: [pack_header]u8 = undefined;
        if ((file.readPositionalAll(self.config.io, &header, 0) catch return null) != header.len) return null;
        if (!std.mem.eql(u8, header[0..pack_magic.len], pack_magic) or !std.mem.eql(u8, header[pack_magic.len..][0..32], &self.config.identity)) return null;
        const length = std.mem.readInt(u64, header[pack_magic.len + 32 ..][0..8], .little);
        if (length > maximum_index) return null;
        const stat = file.stat(self.config.io) catch return null;
        const size = stat.size;
        if (size < pack_header or length > size - pack_header) return null;
        const bytes = try a.alloc(u8, @intCast(length));
        if ((file.readPositionalAll(self.config.io, bytes, pack_header) catch return null) != bytes.len) return null;
        const digest = checksum(bytes);
        if (!std.mem.eql(u8, &digest, header[pack_magic.len + 40 ..][0..32])) return null;
        const shape = indexShape(bytes) orelse return null;
        const blocks = try self.config.a.alloc(Block, shape.blocks);
        if (!validIndex(bytes, shape, blocks, size, pack_header + length)) {
            self.config.a.free(blocks);
            return null;
        }
        return .{ .id = id, .bytes = bytes, .blocks = blocks, .shape = shape, .validation = .{ .stat = stat, .length = length, .digest = digest }, .size = size };
    }

    /// Index pack `found.id` and admit its records. The catalog's table has room for them (`refresh`).
    fn admitIndex(self: *State, found: Indexed) Error!void {
        self.catalog.files.items[found.id].blocks = found.blocks;
        self.catalog.files.items[found.id].scanned = found.size;
        self.catalog.files.items[found.id].validation = found.validation;
        var reader = codec.Reader.init(self.config.a, found.bytes);
        reader.at = found.shape.records_at + 8;
        for (0..found.shape.records) |_| try self.admit(found.id, reader.read(Record) catch return);
    }

    /// Where the blocks and records of an encoded index lie: counts, and the offset of the records' own count.
    const IndexShape = struct { blocks: usize, records: usize, records_at: usize };

    // Bound fixed-width counts before anything is allocated for them, and say where the records start.
    fn indexShape(bytes: []const u8) ?IndexShape {
        if (bytes.len < 16) return null;
        const blocks = std.mem.readInt(u64, bytes[0..8], .little);
        if (blocks > (bytes.len - 16) / 48) return null;
        const position: usize = 8 + @as(usize, @intCast(blocks)) * 48;
        const records = std.mem.readInt(u64, bytes[position..][0..8], .little);
        const remaining = bytes.len - position - 8;
        if (records > remaining / 88) return null;
        if (records * 88 != remaining) return null;
        return .{ .blocks = @intCast(blocks), .records = @intCast(records), .records_at = position };
    }

    /// Decode the blocks of an index into `blocks` and check them and every record against the file's `size` and where its index ends
    /// (`start`). The records are read in place: nothing is allocated for them.
    fn validIndex(bytes: []const u8, shape: IndexShape, blocks: []Block, size: u64, start: u64) bool {
        var reader = codec.Reader.init(.failing, bytes);
        reader.at = 8;
        for (blocks) |*block| {
            block.* = reader.read(Block) catch return false;
            if (block.plain > maximum_block or block.encoded > maximum_block + 1) return false;
            if (block.offset < start or block.offset > size) return false;
            if (block.encoded > size - block.offset) return false;
        }
        reader.at = shape.records_at + 8;
        for (0..shape.records) |_| {
            const record = reader.read(Record) catch return false;
            if (record.block >= blocks.len or record.length > maximum_bytes) return false;
            const block = blocks[record.block];
            if (record.offset > block.plain or record.length > block.plain - record.offset) return false;
        }
        return true;
    }

    /// Load current durable bytes, never a retained copy that hides file damage.
    pub fn load(self: *State, a: std.mem.Allocator, key: Digest, expected: ?Digest) Error!?[]u8 {
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        var scratch = std.heap.ArenaAllocator.init(self.config.a);
        defer scratch.deinit();
        const work = scratch.allocator();
        try self.refresh(work, false);
        try self.touch(key);
        const location = self.catalog.entries.getContext(key, DigestContext{}) orelse return null;
        if (expected) |digest| if (!std.mem.eql(u8, &digest, &location.record.checksum)) return null;
        const metadata = self.catalog.files.items[location.file];
        const payload = if (metadata.kind == .journal) try self.loadFromJournal(work, location) else try self.loadFromPack(work, location, metadata);
        const bytes = payload orelse return null;
        // A pack record lies in a block whose checksum `loadBlock` verified when it decoded the block, and a cached block was verified
        // when it was admitted: hashing the payload again would read the same bytes a second time. A journal record has no block and
        // keeps its own check.
        if (metadata.kind == .journal and !std.mem.eql(u8, &checksum(bytes), &location.record.checksum)) return null;
        const owned = try a.dupe(u8, bytes);
        self.cached.statistics.payload_bytes_returned += bytes.len;
        return owned;
    }

    /// The record of a journal, read from the file opened by name for this load.
    fn loadFromJournal(self: *State, a: std.mem.Allocator, location: Location) Error!?[]u8 {
        const file = std.Io.Dir.cwd().openFile(self.config.io, try self.path(a, self.catalog.files.items[location.file].name), .{}) catch return null;
        defer file.close(self.config.io);
        if (self.config.check) _ = try self.touchRead(location.file, file);
        return self.loadJournal(a, file, location.record);
    }

    /// The record of a pack, read through the pack's kept handle.
    fn loadFromPack(self: *State, a: std.mem.Allocator, location: Location, metadata: File) Error!?[]const u8 {
        var opened = (try self.packHandle(location.file)) orelse return null;
        if (self.config.check) if (try self.touchRead(location.file, opened.file)) |touched| {
            opened.stat = touched;
        };
        return self.loadBlock(a, opened, location.file, metadata, location.record);
    }

    /// The open handle of pack `id` and its status. The handle is kept for the session, and every load proves by one `statx` of the pack's
    /// name that the file is still there and is the one the handle was opened on: a pack that was deleted reads as absent, and one that was
    /// replaced or rewritten under a live reader (a different inode, size or time) is opened again by name, as every load once did. The
    /// kept handle never serves a file the name no longer reaches.
    fn packHandle(self: *State, id: u32) Error!?Opened {
        const entry = &self.catalog.files.items[id];
        if (entry.handle) |held| {
            const current = std.Io.Dir.cwd().statFile(self.config.io, held.path, .{}) catch {
                self.dropHandle(id);
                return null;
            };
            if (sameStat(current, held.stat)) return .{ .file = held.file, .stat = held.stat };
            self.dropHandle(id);
        }
        const kept = try self.path(self.config.a, entry.name);
        const file = std.Io.Dir.cwd().openFile(self.config.io, kept, .{}) catch {
            self.config.a.free(kept);
            return null;
        };
        const stat = file.stat(self.config.io) catch {
            file.close(self.config.io);
            self.config.a.free(kept);
            return null;
        };
        entry.handle = .{ .file = file, .stat = stat, .path = kept };
        return .{ .file = file, .stat = stat };
    }

    /// How many packs this store keeps open (`packHandle`): at most one for each pack its catalog lists.
    pub fn openPacks(self: *State) usize {
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        var held: usize = 0;
        for (self.catalog.files.items) |entry| held += @intFromBool(entry.handle != null);
        return held;
    }

    /// Close the kept handle of file `id` and forget it, so the next load opens the file by name.
    fn dropHandle(self: *State, id: u32) void {
        const entry = &self.catalog.files.items[id];
        const held = entry.handle orelse return;
        held.file.close(self.config.io);
        self.config.a.free(held.path);
        entry.handle = null;
    }

    /// The first read of a pack by this process sets its modification time to now (`Checks.read_files`): the collector treats
    /// a pack read since the oldest live lease began as protected. The status the touch left, when there is one, is also the status
    /// the pack's kept handle is proven against from here on.
    fn touchRead(self: *State, id: u32, file: std.Io.File) Error!?std.Io.File.Stat {
        const slot = try self.checks.read_files.getOrPut(self.config.a, id);
        if (slot.found_existing) return null;
        file.setTimestampsNow(self.config.io) catch return null;
        // The touch changed the pack's stat: the catalog's record of it follows, or a later removal of this pack would refuse.
        const stat = file.stat(self.config.io) catch return null;
        if (self.catalog.files.items[id].validation) |*validation| validation.stat = stat;
        if (self.catalog.files.items[id].handle) |*held| held.stat = stat;
        return stat;
    }

    /// Whether a record of `key` is catalogued, without reading its payload. The catalog is scanned once per store and
    /// then kept, so a record another process published after the scan reads as absent: the caller writes it again, and
    /// the newer record wins, which costs bytes and nothing else. A store the process shares is brought up to date each
    /// time a session acquires it (`acquire`), not at each lookup.
    pub fn contains(self: *State, key: Digest) Error!bool {
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        if (!self.catalog.scanned) {
            var scratch = std.heap.ArenaAllocator.init(self.config.a);
            defer scratch.deinit();
            try self.refresh(scratch.allocator(), false);
        }
        try self.touch(key);
        return self.catalog.entries.containsContext(key, DigestContext{});
    }

    /// Whether the catalog holds a record of `key`: no touch, and a refresh only while the catalog was never scanned. A lookup that is
    /// usually a miss (a store that holds only the records it kept back from a shared one) costs a hash probe, not a read of the counter.
    pub fn holds(self: *State, key: Digest) Error!bool {
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        if (!self.catalog.scanned) {
            var scratch = std.heap.ArenaAllocator.init(self.config.a);
            defer scratch.deinit();
            try self.refresh(scratch.allocator(), false);
        }
        return self.catalog.entries.containsContext(key, DigestContext{});
    }

    fn loadJournal(self: *State, a: std.mem.Allocator, file: std.Io.File, record: Record) Error!?[]u8 {
        var identity: [journal_header]u8 = undefined;
        if ((file.readPositionalAll(self.config.io, &identity, 0) catch return null) != identity.len) return null;
        if (!std.mem.eql(u8, identity[0..journal_magic.len], journal_magic) or !std.mem.eql(u8, identity[journal_magic.len..], &self.config.identity)) return null;
        var header: [record_header]u8 = undefined;
        if (record.offset < journal_header + record_header) return null;
        if ((file.readPositionalAll(self.config.io, &header, record.offset - record_header) catch return null) != header.len) return null;
        if (!validRecordHeader(&header) or !std.meta.eql(record, readRecord(&header, record.offset))) return null;
        const bytes = try a.alloc(u8, record.length);
        if ((file.readPositionalAll(self.config.io, bytes, record.offset) catch return null) != bytes.len) return null;
        return bytes;
    }

    fn loadBlock(self: *State, a: std.mem.Allocator, opened: Opened, id: u32, metadata: File, record: Record) Error!?[]const u8 {
        if (record.block >= metadata.blocks.len) return null;
        const block = metadata.blocks[record.block];
        const file = opened.file;
        const stat = opened.stat;
        if (!try self.validBacking(a, file, id, metadata, stat)) return null;
        const key: CacheKey = .{ .file = id, .block = record.block };
        self.cached.tick += 1;
        const cached = self.cached.blocks.getPtr(key);
        const hit = if (cached) |entry| sameStat(entry.stat, stat) else false;
        if (hit) {
            self.cached.statistics.block_cache_hits += 1;
            cached.?.used = self.cached.tick;
        }
        const plain = if (hit) cached.?.bytes else blk: {
            if (block.plain <= block_target * 2 and @as(u64, block.encoded) == @as(u64, block.plain) + 1) switch (try self.readRawBlock(file, key, block, stat)) {
                .cached => |bytes| break :blk bytes,
                .invalid => return null,
                .encoded => {},
            };
            const bytes = try a.alloc(u8, block.encoded);
            if ((file.readPositionalAll(self.config.io, bytes, block.offset) catch return null) != bytes.len) return null;
            self.cached.statistics.packed_bytes_read += bytes.len;
            if (!std.mem.eql(u8, &checksum(bytes), &block.checksum)) return null;
            const decoded = compression.decode(a, bytes, block.plain) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return null;
            };
            self.cached.statistics.blocks_decoded += 1;
            self.cached.statistics.decoded_bytes += decoded.len;
            if (decoded.len <= block_target * 2) try self.remember(key, decoded, stat);
            break :blk decoded;
        };
        if (record.offset < record_header) return null;
        const header: *const [record_header]u8 = plain[@intCast(record.offset - record_header)..][0..record_header];
        if (!validRecordHeader(header)) return null;
        var actual = readRecord(header, record.offset);
        actual.block = record.block;
        if (!std.meta.eql(actual, record)) return null;
        return plain[@intCast(record.offset)..][0..record.length];
    }

    /// What `readRawBlock` found: the block's bytes (now in the cache), a block that failed a check, or a block that is not stored raw.
    const RawBlock = union(enum) { cached: []const u8, invalid, encoded };

    /// Read a block whose encoded size is its plain size plus the tag byte straight into the allocation the cache keeps, and cache it:
    /// an uncompressed block is read once, where the generic path reads it, copies it without the tag, and copies that again for the cache
    /// (three fresh allocations of the block's size, each page of them a fault).
    fn readRawBlock(self: *State, file: std.Io.File, key: CacheKey, block: Block, stat: std.Io.File.Stat) Error!RawBlock {
        const a = self.config.a;
        const owned = try a.alloc(u8, block.encoded);
        errdefer a.free(owned);
        if ((file.readPositionalAll(self.config.io, owned, block.offset) catch return self.invalidRaw(owned)) != owned.len) return self.invalidRaw(owned);
        self.cached.statistics.packed_bytes_read += owned.len;
        if (!std.mem.eql(u8, &checksum(owned), &block.checksum)) return self.invalidRaw(owned);
        // The tag says whether the stream is stored; any other tag takes the generic path, which decodes it.
        if (owned[0] != 0) {
            a.free(owned);
            return .encoded;
        }
        self.cached.statistics.blocks_decoded += 1;
        self.cached.statistics.decoded_bytes += block.plain;
        try self.cacheBlock(key, owned[1..], owned, stat);
        return .{ .cached = owned[1..] };
    }

    /// Free `owned` and say the block is invalid.
    fn invalidRaw(self: *State, owned: []const u8) RawBlock {
        self.config.a.free(owned);
        return .invalid;
    }

    /// Keep a decoded block for later loads, replacing any entry for the same
    /// block and evicting least recently used entries past the byte budget.
    fn remember(self: *State, key: CacheKey, decoded: []const u8, stat: std.Io.File.Stat) Error!void {
        const owned = try self.config.a.dupe(u8, decoded);
        errdefer self.config.a.free(owned);
        try self.cacheBlock(key, owned, owned, stat);
    }

    /// Put `bytes`, which lie in the allocation `base`, in the cache under `key`; the cache owns `base` from here (on an error the
    /// caller still does).
    fn cacheBlock(self: *State, key: CacheKey, bytes: []const u8, base: []const u8, stat: std.Io.File.Stat) Error!void {
        const a = self.config.a;
        const slot = try self.cached.blocks.getOrPut(a, key);
        if (slot.found_existing) {
            self.cached.bytes -= slot.value_ptr.bytes.len;
            a.free(slot.value_ptr.base);
        }
        slot.value_ptr.* = .{ .bytes = bytes, .base = base, .stat = stat, .used = self.cached.tick };
        self.cached.bytes += bytes.len;
        while (self.cached.bytes > cache_budget) self.evictLeastRecent();
    }

    /// Drop the entry with the oldest tick; ticks are unique, so the choice is deterministic.
    fn evictLeastRecent(self: *State) void {
        var oldest: ?CacheKey = null;
        var oldest_used: u64 = std.math.maxInt(u64);
        var entries = self.cached.blocks.iterator();
        while (entries.next()) |entry| {
            if (entry.value_ptr.used < oldest_used) {
                oldest_used = entry.value_ptr.used;
                oldest = entry.key_ptr.*;
            }
        }
        const removed = self.cached.blocks.fetchRemove(oldest orelse return) orelse return;
        self.cached.bytes -= removed.value.bytes.len;
        self.config.a.free(removed.value.base);
    }

    fn validBacking(self: *State, a: std.mem.Allocator, file: std.Io.File, id: u32, metadata: File, stat: std.Io.File.Stat) Error!bool {
        const validation = metadata.validation orelse return false;
        if (sameStat(stat, validation.stat)) return true;
        var header: [pack_header]u8 = undefined;
        if ((file.readPositionalAll(self.config.io, &header, 0) catch return false) != header.len) return false;
        if (!std.mem.eql(u8, header[0..pack_magic.len], pack_magic) or !std.mem.eql(u8, header[pack_magic.len..][0..32], &self.config.identity)) return false;
        if (std.mem.readInt(u64, header[pack_magic.len + 32 ..][0..8], .little) != validation.length) return false;
        if (!std.mem.eql(u8, header[pack_magic.len + 40 ..][0..32], &validation.digest)) return false;
        const bytes = try a.alloc(u8, @intCast(validation.length));
        if ((file.readPositionalAll(self.config.io, bytes, pack_header) catch return false) != bytes.len) return false;
        if (!std.mem.eql(u8, &checksum(bytes), &validation.digest)) return false;
        self.catalog.files.items[id].validation.?.stat = stat;
        return true;
    }

    /// Identify the containing durable file for cache-loss tests and diagnostics.
    pub fn artifactPath(self: *State, a: std.mem.Allocator, key: Digest) Error!?[]const u8 {
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        var scratch = std.heap.ArenaAllocator.init(self.config.a);
        defer scratch.deinit();
        try self.refresh(scratch.allocator(), false);
        const location = self.catalog.entries.getContext(key, DigestContext{}) orelse return null;
        const owned = try self.path(a, self.catalog.files.items[location.file].name);
        return owned;
    }

    fn sequenceLock(self: *State, a: std.mem.Allocator) Error!?std.Io.File {
        // The store's directory is made only when the lock file cannot be created without it: it exists from the first save on, and
        // `createDirPath` of an existing one is a failing `mkdirat` and a `statx` on every journal append (G4c3: 29,654 of each in a fresh
        // build that computes every record).
        const cwd = std.Io.Dir.cwd();
        const sequence = try self.path(a, "sequence");
        const options: std.Io.Dir.CreateFileOptions = .{ .read = true, .truncate = false, .lock = .exclusive };
        const file = cwd.createFile(self.config.io, sequence, options) catch |err| blk: {
            if (err != error.FileNotFound) return null;
            cwd.createDirPath(self.config.io, self.config.root) catch return null;
            break :blk cwd.createFile(self.config.io, sequence, options) catch return null;
        };
        self.cached.statistics.publication.sequence_locks += 1;
        return file;
    }

    fn writeCounter(self: *State, file: std.Io.File, sequence: u64) bool {
        var bytes: [48]u8 = undefined;
        @memcpy(bytes[0..8], lock_magic);
        std.mem.writeInt(u64, bytes[8..16], sequence, .little);
        @memcpy(bytes[16..48], &checksum(bytes[0..16]));
        file.writePositionalAll(self.config.io, &bytes, 0) catch return false;
        return true;
    }

    fn createJournal(self: *State, a: std.mem.Allocator) Error!?std.Io.File {
        var nonce: [16]u8 = undefined;
        std.Io.random(self.config.io, &nonce);
        const name = try std.fmt.allocPrint(a, "{s}{s}", .{ std.fmt.bytesToHex(nonce, .lower), journal_suffix });
        const id = try self.fileId(.{ .name = name, .kind = .journal });
        const file = std.Io.Dir.cwd().createFile(self.config.io, try self.path(a, name), .{ .read = true, .exclusive = true }) catch return null;
        var header: [journal_header]u8 = undefined;
        @memcpy(header[0..journal_magic.len], journal_magic);
        @memcpy(header[journal_magic.len..], &self.config.identity);
        file.writePositionalAll(self.config.io, &header, 0) catch {
            file.close(self.config.io);
            return null;
        };
        self.journal = .{ .file = id };
        return file;
    }

    fn journalFile(self: *State, a: std.mem.Allocator) Error!?std.Io.File {
        if (self.journal) |journal| {
            if (std.Io.Dir.cwd().openFile(self.config.io, try self.path(a, self.catalog.files.items[journal.file].name), .{ .mode = .read_write })) |file| {
                if (self.validJournal(file, journal.length)) return file;
                file.close(self.config.io);
            } else |_| {}
            self.journal.?.records.deinit(self.config.a);
            self.journal = null;
        }
        return self.createJournal(a);
    }

    fn validJournal(self: *State, file: std.Io.File, length: u64) bool {
        if ((file.stat(self.config.io) catch return false).size != length) return false;
        var header: [journal_header]u8 = undefined;
        if ((file.readPositionalAll(self.config.io, &header, 0) catch return false) != header.len) return false;
        return std.mem.eql(u8, header[0..journal_magic.len], journal_magic) and std.mem.eql(u8, header[journal_magic.len..], &self.config.identity);
    }

    /// Successful saves are published durable records before returning.
    pub fn save(self: *State, key: Digest, payload: []const u8) Error!bool {
        if (self.config.check) return self.saveAll(&.{.{ .key = key, .payload = payload }});
        var seal = false;
        if (!try self.saveRecord(key, payload, &seal)) return false;
        // saveRecord has released both publication locks. Sealing is optional:
        // allocation failure is explicit; I/O failure leaves the journal available.
        if (seal) _ = try self.flush();
        return true;
    }

    /// Publish a batch of records as one journal write under one sequence lock. Each record takes its own sequence number,
    /// so a later record of a key wins exactly as separate saves would; the batch is published whole or not at all.
    pub fn saveAll(self: *State, saves: []const Save) Error!bool {
        if (saves.len == 0) return true;
        var seal = false;
        if (!try self.saveBatch(saves, &seal)) return false;
        if (seal) _ = try self.flush();
        return true;
    }

    /// The saves a check-publishing store writes, decided under the sequence lock against the refreshed catalog. A key the
    /// catalog holds with the same payload checksum is present: nothing is written. A different checksum is a mismatch: the
    /// existing record stays and the pair is logged. A key repeated in the batch is compared with its first occurrence.
    /// Only checksums are compared, so a publication costs no read of the records it did not write.
    fn unseen(self: *State, a: std.mem.Allocator, saves: []const Save) Error![]const Save {
        var keep: std.ArrayList(Save) = .empty;
        var first: std.AutoHashMapUnmanaged(Digest, Digest) = .empty;
        try first.ensureTotalCapacity(a, @intCast(saves.len));
        for (saves) |item| {
            const attempted = checksum(item.payload);
            const existing = if (self.catalog.entries.getContext(item.key, DigestContext{})) |location| location.record.checksum else first.get(item.key);
            if (existing) |held| {
                if (std.mem.eql(u8, &held, &attempted)) {
                    self.checks.present += 1;
                } else if (item.replace) {
                    try keep.append(a, item);
                } else {
                    self.checks.mismatches += 1;
                    // A record whose caller keeps its own copy (`Save.mismatched`) is not a determinism bug: nothing is logged for it.
                    if (item.mismatched) |flag| flag.* = true else self.logMismatch(item.key, held, attempted);
                }
                continue;
            }
            first.putAssumeCapacity(item.key, attempted);
            try keep.append(a, item);
        }
        return keep.items;
    }

    /// Append one `mismatch stage` line to `<root>/mismatches.log`, with a single append write. Best effort: a log that
    /// cannot be written never turns the kept record into an error.
    fn logMismatch(self: *const State, key: Digest, held: Digest, attempted: Digest) void {
        var buffer: [320]u8 = undefined;
        const hex = .{ std.fmt.bytesToHex(key, .lower), std.fmt.bytesToHex(held, .lower), std.fmt.bytesToHex(attempted, .lower) };
        const line = std.fmt.bufPrint(&buffer, "mismatch stage {s} existing={s} attempted={s}\n", .{ hex[0], hex[1], hex[2] }) catch return;
        self.appendLog(line);
    }

    /// Append one `unfit stage` line to `<root>/mismatches.log`: a record of `key` this store served did not fit the program a
    /// build restored it into, and the build lowered the function instead (`lowering_cache.Session.restore`). Best effort.
    pub fn logUnfit(self: *const State, key: Digest) void {
        var buffer: [128]u8 = undefined;
        const line = std.fmt.bufPrint(&buffer, "unfit stage {s}\n", .{std.fmt.bytesToHex(key, .lower)}) catch return;
        self.appendLog(line);
    }

    /// Append `line` to `<root>/mismatches.log` with a single append write; a log that cannot be written is skipped.
    fn appendLog(self: *const State, line: []const u8) void {
        var name: [4096]u8 = undefined;
        const text = std.fmt.bufPrint(name[0 .. name.len - 1], "{s}/mismatches.log", .{self.config.root}) catch return;
        name[text.len] = 0;
        const target: [:0]const u8 = name[0..text.len :0];
        const linux = std.os.linux;
        const fd = linux.open(target.ptr, .{ .ACCMODE = .WRONLY, .APPEND = true, .CREAT = true, .CLOEXEC = true, .NOFOLLOW = true, .NONBLOCK = true }, 0o600);
        if (linux.errno(fd) != .SUCCESS) return;
        const file: std.Io.File = .{ .handle = @intCast(fd), .flags = .{ .nonblocking = true } };
        defer file.close(self.config.io);
        file.writeStreamingAll(self.config.io, line) catch return;
    }

    fn saveBatch(self: *State, saves: []const Save, seal: *bool) Error!bool {
        for (saves) |item| if (item.payload.len > maximum_bytes) return false;
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        var scratch = std.heap.ArenaAllocator.init(self.config.a);
        defer scratch.deinit();
        const a = scratch.allocator();
        for (saves) |item| try self.touch(item.key);
        // Catch up with what other processes published before taking the lock: a catalog far behind (a process whose first act on a large
        // store is a save) is read here, where no other writer waits for it, and the refresh under the lock reads only what was written since.
        if (self.config.check) try self.refresh(a, false);
        const lock = try self.sequenceLock(a) orelse return false;
        defer lock.close(self.config.io);
        try self.refresh(a, false);
        const pending = if (self.config.check) try self.unseen(a, saves) else saves;
        if (pending.len == 0) return true;
        var total: usize = 0;
        var payload_total: u64 = 0;
        for (pending) |item| {
            total += record_header + item.payload.len;
            payload_total += item.payload.len;
        }
        const bytes = try a.alloc(u8, total);
        const records = try a.alloc(Record, pending.len);
        self.cached.statistics.publication.save_bytes_prepared += payload_total;
        const first = std.math.add(u64, @max(self.catalog.sequence, self.catalog.max_sequence), 1) catch return false;
        const file = try self.journalFile(a) orelse return false;
        defer file.close(self.config.io);
        const journal = &self.journal.?;
        // Reserve before publication so OOM cannot leave a successful unindexed batch.
        try journal.records.ensureUnusedCapacity(self.config.a, pending.len);
        try self.catalog.entries.ensureUnusedCapacityContext(self.config.a, @intCast(pending.len), DigestContext{});
        var cursor: usize = 0;
        for (pending, records, 0..) |item, *record, index| {
            const frame = bytes[cursor..][0 .. record_header + item.payload.len];
            const sequence = first + index;
            record.* = .{ .key = item.key, .checksum = checksum(item.payload), .sequence = sequence, .offset = journal.length + cursor + record_header, .length = @intCast(item.payload.len) };
            std.mem.writeInt(u64, frame[0..8], item.payload.len, .little);
            std.mem.writeInt(u64, frame[8..16], sequence, .little);
            @memcpy(frame[16..48], &item.key);
            @memcpy(frame[48..80], &record.checksum);
            @memcpy(frame[80..112], &checksum(frame[0..80]));
            @memcpy(frame[record_header..], item.payload);
            cursor += frame.len;
        }
        if (cursor != total) return false;
        const last = first + pending.len - 1;
        file.writePositionalAll(self.config.io, bytes, journal.length) catch return false;
        if (!self.writeCounter(lock, last)) return false;
        journal.length += total;
        journal.bytes += total;
        for (records) |record| {
            journal.records.appendAssumeCapacity(record);
            try self.admit(journal.file, record);
        }
        self.catalog.files.items[journal.file].scanned = journal.length;
        self.catalog.sequence = last;
        self.cached.statistics.publication.records_saved += pending.len;
        seal.* = journal.bytes >= pack_target;
        return true;
    }

    fn saveRecord(self: *State, key: Digest, payload: []const u8, seal: *bool) Error!bool {
        if (payload.len > maximum_bytes) return false;
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        var scratch = std.heap.ArenaAllocator.init(self.config.a);
        defer scratch.deinit();
        const a = scratch.allocator();
        const payload_checksum = checksum(payload);
        try self.touch(key);
        const bytes = try a.alloc(u8, record_header + payload.len);
        @memcpy(bytes[record_header..], payload);
        self.cached.statistics.publication.save_bytes_prepared += payload.len;
        const lock = try self.sequenceLock(a) orelse return false;
        defer lock.close(self.config.io);
        try self.refresh(a, false);
        const sequence = std.math.add(u64, @max(self.catalog.sequence, self.catalog.max_sequence), 1) catch return false;
        const file = try self.journalFile(a) orelse return false;
        defer file.close(self.config.io);
        const journal = &self.journal.?;
        // Reserve before publication so OOM cannot leave a successful unindexed save.
        try journal.records.ensureUnusedCapacity(self.config.a, 1);
        try self.catalog.entries.ensureUnusedCapacityContext(self.config.a, 1, DigestContext{});
        const record: Record = .{ .key = key, .checksum = payload_checksum, .sequence = sequence, .offset = journal.length + record_header, .length = @intCast(payload.len) };
        std.mem.writeInt(u64, bytes[0..8], payload.len, .little);
        std.mem.writeInt(u64, bytes[8..16], sequence, .little);
        @memcpy(bytes[16..48], &key);
        @memcpy(bytes[48..80], &record.checksum);
        @memcpy(bytes[80..112], &checksum(bytes[0..80]));
        file.writePositionalAll(self.config.io, bytes, journal.length) catch return false;
        if (!self.writeCounter(lock, sequence)) return false;
        journal.length += bytes.len;
        journal.bytes += bytes.len;
        journal.records.appendAssumeCapacity(record);
        self.catalog.files.items[journal.file].scanned = journal.length;
        try self.admit(journal.file, record);
        self.catalog.sequence = sequence;
        self.cached.statistics.publication.records_saved += 1;
        seal.* = journal.bytes >= pack_target;
        return true;
    }

    fn openSource(self: *State, a: std.mem.Allocator) Error!?Source {
        const journal = self.journal.?;
        const name = self.catalog.files.items[journal.file].name;
        const path_name = try self.path(a, name);
        const file = std.Io.Dir.cwd().openFile(self.config.io, path_name, .{ .follow_symlinks = false }) catch return null;
        const stat = file.stat(self.config.io) catch {
            file.close(self.config.io);
            return null;
        };
        const source: Source = .{ .file = file, .path = path_name, .stat = stat };
        if (!self.validSource(source) or !self.validJournal(file, journal.length)) {
            file.close(self.config.io);
            return null;
        }
        return source;
    }

    fn validSource(self: *State, source: Source) bool {
        const opened = source.file.stat(self.config.io) catch return false;
        const current = std.Io.Dir.cwd().statFile(self.config.io, source.path, .{ .follow_symlinks = false }) catch return false;
        return current.kind == .file and sameStat(source.stat, opened) and sameStat(source.stat, current) and
            self.validJournal(source.file, source.stat.size);
    }

    fn nextSequence(self: *State) ?u64 {
        return std.math.add(u64, @max(self.catalog.sequence, self.catalog.max_sequence), 1) catch null;
    }

    fn commitPack(self: *State, a: std.mem.Allocator, pending: Pending, source: Source) Error!bool {
        const lock = try self.sequenceLock(a) orelse return false;
        defer lock.close(self.config.io);
        try self.refresh(a, false);
        if (!self.validSource(source)) return false;
        const sequence = self.nextSequence() orelse return false;
        if (!try self.publishBytes(pending)) return false;
        if (!self.writeCounter(lock, sequence)) return false;
        self.catalog.sequence = sequence;
        return true;
    }

    fn finishJournal(self: *State, a: std.mem.Allocator, source: Source) Error!bool {
        const lock = try self.sequenceLock(a) orelse return false;
        defer lock.close(self.config.io);
        try self.refresh(a, false);
        if (!self.validSource(source)) return false;
        const sequence = self.nextSequence() orelse return false;
        if (!self.writeCounter(lock, sequence)) return false;
        std.Io.Dir.cwd().deleteFile(self.config.io, source.path) catch return false;
        self.journal.?.records.deinit(self.config.a);
        self.journal = null;
        self.catalog.sequence = sequence;
        return true;
    }

    /// Prepare bounded packs outside the publication lock; retain the journal until every commit succeeds.
    pub fn flush(self: *State) Error!bool {
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        if (self.journal == null or self.journal.?.records.items.len == 0) return true;
        var scratch = std.heap.ArenaAllocator.init(self.config.a);
        defer scratch.deinit();
        const a = scratch.allocator();
        const source = try self.openSource(a) orelse return false;
        defer source.file.close(self.config.io);
        const journal = &self.journal.?;
        var first: usize = 0;
        while (first < journal.records.items.len) {
            var end = first;
            var bytes: usize = 0;
            while (end < journal.records.items.len and (bytes < pack_target or end == first)) : (end += 1) bytes += record_header + journal.records.items[end].length;
            var chunk = std.heap.ArenaAllocator.init(self.config.a);
            defer chunk.deinit();
            const work = chunk.allocator();
            const prepared = try self.prepare(work, source.file, journal.records.items[first..end]) orelse return false;
            const pending = try self.stageBytes(work, prepared) orelse return false;
            defer self.discard(pending.temporary);
            if (!try self.commitPack(work, pending, source)) return false;
            first = end;
        }
        if (!try self.finishJournal(a, source)) return false;
        return true;
    }

    fn earlierLocation(_: void, lhs: Location, rhs: Location) bool {
        if (lhs.file != rhs.file) return lhs.file < rhs.file;
        if (lhs.record.block != rhs.record.block) return lhs.record.block < rhs.record.block;
        return lhs.record.offset < rhs.record.offset;
    }

    /// The compressed bytes of `block`, if they still match their checksum.
    fn readBlock(self: *State, a: std.mem.Allocator, file: std.Io.File, block: Block) Error!?[]const u8 {
        const encoded = try a.alloc(u8, block.encoded);
        if ((file.readPositionalAll(self.config.io, encoded, block.offset) catch return null) != encoded.len) return null;
        if (!std.mem.eql(u8, &checksum(encoded), &block.checksum)) return null;
        return encoded;
    }

    fn decodeBlock(_: *State, a: std.mem.Allocator, encoded: []const u8, block: Block) Error!?[]const u8 {
        return compression.decode(a, encoded, block.plain) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
    }

    /// Drop a pack that no longer exists from the catalog's block tables; a record of it
    /// that nothing replaced is then a miss, as any lost file is.
    fn forget(self: *State, id: u32) void {
        self.dropHandle(id);
        const file = &self.catalog.files.items[id];
        self.config.a.free(file.blocks);
        file.blocks = &.{};
        file.validation = null;
    }

    /// What this store holds against `ranks`, after reading the indexes of the packs it has not yet read.
    pub fn measure(self: *State, ranks: *const Ranks) Error!Measure {
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        var scratch = std.heap.ArenaAllocator.init(self.config.a);
        defer scratch.deinit();
        try self.refresh(scratch.allocator(), false);
        return self.measureLocked(ranks);
    }

    fn measureLocked(self: *const State, ranks: *const Ranks) Measure {
        var result: Measure = .{};
        for (self.catalog.files.items) |file| {
            if (file.kind != .pack) continue;
            const validation = file.validation orelse continue;
            result.packs += 1;
            result.pack_bytes += validation.stat.size;
        }
        var entries = self.catalog.entries.iterator();
        while (entries.next()) |entry| {
            if (!self.packRecord(entry.value_ptr.*) or !ranks.contains(rankKey(entry.key_ptr.*))) continue;
            result.live_bytes += record_header + entry.value_ptr.record.length;
        }
        return result;
    }

    /// Whether a record lives in a valid pack: the only records compaction moves. Journal records stay where they are.
    fn packRecord(self: *const State, location: Location) bool {
        const file = self.catalog.files.items[location.file];
        return file.kind == .pack and file.validation != null;
    }

    /// Rewrite the live pack records into fresh packs and remove the packs they came from. A record is live when `ranks`
    /// names its key's prefix. Live records go out in rank order, one band of `band_bytes` at a time, so the records
    /// one build needed share blocks. Every band is published by rename before any source is removed, so a reader holding a
    /// source open keeps reading it, and a key whose record is removed is a miss. A record that fails to read or verify is
    /// dropped with its source. A failed publication returns null and keeps every source. Callers hold the work directory's
    /// exclusive lease, so no build is writing this store.
    pub fn compactLive(self: *State, ranks: *const Ranks, band_bytes: u64) Error!?Compaction {
        return self.compactIn(ranks, band_bytes, null);
    }

    /// `compactLive` over the packs named by `scope` (every valid pack when null): only their records move or are dropped, and
    /// only they are removed. The collector passes the packs old enough to be candidates, so a pack inside the lease epoch or
    /// the warm window is never rewritten.
    pub fn compactIn(self: *State, ranks: *const Ranks, band_bytes: u64, scope: ?[]const u32) Error!?Compaction {
        if (ranks.count() == 0) return null;
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        var scratch = std.heap.ArenaAllocator.init(self.config.a);
        defer scratch.deinit();
        const work = scratch.allocator();
        try self.refresh(work, false);
        const before = self.measureLocked(ranks);
        const sources = if (scope) |ids| ids else try self.packIds(work);
        const ranked = try self.rankedRecords(work, ranks, scope);
        var passes: u64 = 0;
        var at: usize = 0;
        while (at < ranked.len) : (passes += 1) {
            // A band's frames, decoded blocks and encoded output are freed once its pack is published, through the store's
            // allocator (`maintainStages` gives it the general-purpose one, which returns memory to the OS).
            var band = std.heap.ArenaAllocator.init(self.config.a);
            defer band.deinit();
            const end = bandEnd(ranked, at, band_bytes);
            if (!try self.publishBand(band.allocator(), ranked[at..end])) return null;
            at = end;
        }
        if (!try self.retireSources(work, sources)) return null;
        return .{ .before = before, .after = self.measureLocked(ranks), .passes = passes };
    }

    /// The valid packs with their times, bytes and live record counts against `ranks`, after reading any packs not yet read.
    pub fn packStats(self: *State, a: std.mem.Allocator, ranks: *const Ranks) Error![]PackStat {
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        var scratch = std.heap.ArenaAllocator.init(self.config.a);
        defer scratch.deinit();
        try self.refresh(scratch.allocator(), false);
        const live = try scratch.allocator().alloc(u64, self.catalog.files.items.len);
        @memset(live, 0);
        var entries = self.catalog.entries.iterator();
        while (entries.next()) |entry| {
            if (self.packRecord(entry.value_ptr.*) and ranks.contains(rankKey(entry.key_ptr.*))) live[entry.value_ptr.file] += 1;
        }
        var stats: std.ArrayList(PackStat) = .empty;
        // A pack another process touched has a newer stat than the catalog recorded: take the current one, so a removal of
        // the pack is checked against what is on disk.
        for (self.catalog.files.items, 0..) |*file, id| {
            if (file.kind != .pack) continue;
            const validation = &(file.validation orelse continue);
            if (std.Io.Dir.cwd().statFile(self.config.io, try self.path(scratch.allocator(), file.name), .{ .follow_symlinks = false })) |current| {
                validation.stat = current;
            } else |_| {}
            try stats.append(a, .{ .id = @intCast(id), .mtime = validation.stat.mtime.nanoseconds, .bytes = validation.stat.size, .live = live[id] });
        }
        return stats.items;
    }

    /// Remove the packs `ids` and every record in them, under the sequence lock, as `compactIn` removes its sources.
    pub fn retire(self: *State, ids: []const u32) Error!bool {
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        var scratch = std.heap.ArenaAllocator.init(self.config.a);
        defer scratch.deinit();
        try self.refresh(scratch.allocator(), false);
        return self.retireSources(scratch.allocator(), ids);
    }

    /// The ids of the valid packs, before a compaction adds its own.
    fn packIds(self: *const State, a: std.mem.Allocator) Error![]const u32 {
        var ids: std.ArrayList(u32) = .empty;
        for (self.catalog.files.items, 0..) |file, id| {
            if (file.kind == .pack and file.validation != null) try ids.append(a, @intCast(id));
        }
        return ids.items;
    }

    /// The pack records whose keys `ranks` names, sorted by rank and then by location.
    fn rankedRecords(self: *const State, a: std.mem.Allocator, ranks: *const Ranks, scope: ?[]const u32) Error![]Ranked {
        var found: std.ArrayList(Ranked) = .empty;
        var entries = self.catalog.entries.iterator();
        while (entries.next()) |entry| {
            if (!self.packRecord(entry.value_ptr.*)) continue;
            if (scope) |ids| if (std.mem.indexOfScalar(u32, ids, entry.value_ptr.file) == null) continue;
            const rank = ranks.get(rankKey(entry.key_ptr.*)) orelse continue;
            try found.append(a, .{ .location = entry.value_ptr.*, .rank = rank });
        }
        std.mem.sort(Ranked, found.items, {}, rankedBefore);
        return found.items;
    }

    fn rankedBefore(_: void, lhs: Ranked, rhs: Ranked) bool {
        if (lhs.rank != rhs.rank) return lhs.rank < rhs.rank;
        return earlierLocation({}, lhs.location, rhs.location);
    }

    fn byLocation(_: void, lhs: Ranked, rhs: Ranked) bool {
        return earlierLocation({}, lhs.location, rhs.location);
    }

    /// The end of the band starting at `at`: as many records as fit `band_bytes`, and at least one.
    fn bandEnd(ranked: []const Ranked, at: usize, band_bytes: u64) usize {
        var end = at;
        var bytes: u64 = 0;
        while (end < ranked.len and end - at < compact_band_records) : (end += 1) {
            const size = record_header + ranked[end].location.record.length;
            if (end > at and bytes + size > band_bytes) break;
            bytes += size;
        }
        return end;
    }

    /// The frames of the records one band keeps, read from their sources, plus the handles opened for them.
    const Gather = struct { buffer: []u8, handles: []?std.Io.File, cursor: usize = 0, frames: MergedBytes = .{} };

    /// Publish one band as a fresh pack holding its records in rank order. False when it cannot be published.
    fn publishBand(self: *State, a: std.mem.Allocator, band: []const Ranked) Error!bool {
        const frames = try self.gatherFrames(a, band);
        var kept: std.ArrayList(Record) = .empty;
        for (band) |item| {
            if (!frames.bytes.contains(item.location.record.key)) continue;
            var moved = item.location.record;
            moved.block = 0;
            moved.offset = record_header;
            try kept.append(a, moved);
        }
        if (kept.items.len == 0) return true;
        const prepared = try self.assemble(a, &.{}, kept.items, frames) orelse return false;
        const pending = try self.stageBytes(a, prepared) orelse return false;
        defer self.discard(pending.temporary);
        return self.publishBytes(pending);
    }

    /// The frames of `band`'s records, read block by block in pack order into one buffer. A record whose block cannot be
    /// read or fails verification gets no frame.
    fn gatherFrames(self: *State, a: std.mem.Allocator, band: []const Ranked) Error!MergedBytes {
        var size: usize = 0;
        for (band) |item| size += record_header + item.location.record.length;
        var collect: Gather = .{ .buffer = try a.alloc(u8, size), .handles = try a.alloc(?std.Io.File, self.catalog.files.items.len) };
        @memset(collect.handles, null);
        defer for (collect.handles) |handle| if (handle) |file| file.close(self.config.io);
        const order = try a.dupe(Ranked, band);
        std.mem.sort(Ranked, order, {}, byLocation);
        var at: usize = 0;
        while (at < order.len) {
            const first = order[at].location;
            var end = at + 1;
            while (end < order.len and order[end].location.file == first.file and order[end].location.record.block == first.record.block) : (end += 1) {}
            try self.gatherBlock(a, &collect, order[at..end]);
            at = end;
        }
        return collect.frames;
    }

    /// Copy the frames of `group`, records of one block of one pack, out of that block. The block's bytes are freed on return:
    /// only the copies, which the band's buffer holds, outlive it.
    fn gatherBlock(self: *State, a: std.mem.Allocator, collect: *Gather, group: []const Ranked) Error!void {
        const first = group[0].location;
        const metadata = self.catalog.files.items[first.file];
        if (first.record.block >= metadata.blocks.len) return;
        const block = metadata.blocks[first.record.block];
        var scratch_arena = std.heap.ArenaAllocator.init(self.config.a);
        defer scratch_arena.deinit();
        const scratch = scratch_arena.allocator();
        const file = try self.openHandle(a, collect, first.file) orelse return;
        const encoded = try self.readBlock(scratch, file, block) orelse return;
        const decoded = try self.decodeBlock(scratch, encoded, block) orelse return;
        for (group) |item| {
            const record = item.location.record;
            if (record.offset < record_header or record.offset > decoded.len or record.length > decoded.len - record.offset) continue;
            const header: *const [record_header]u8 = decoded[@intCast(record.offset - record_header)..][0..record_header];
            if (!validRecordHeader(header)) continue;
            var actual = readRecord(header, record.offset);
            actual.block = record.block;
            if (!std.meta.eql(actual, record)) continue;
            if (!std.mem.eql(u8, &checksum(decoded[@intCast(record.offset)..][0..record.length]), &record.checksum)) continue;
            const size = record_header + record.length;
            const frame = collect.buffer[collect.cursor..][0..size];
            @memcpy(frame, decoded[@intCast(record.offset - record_header)..][0..size]);
            collect.cursor += size;
            try collect.frames.bytes.put(a, record.key, frame);
        }
    }

    /// The handle of pack `id`, opened on first use by this collection.
    fn openHandle(self: *State, a: std.mem.Allocator, collect: *Gather, id: u32) Error!?std.Io.File {
        if (collect.handles[id]) |file| return file;
        const file = std.Io.Dir.cwd().openFile(self.config.io, try self.path(a, self.catalog.files.items[id].name), .{}) catch return null;
        collect.handles[id] = file;
        return file;
    }

    /// Remove the packs the bands were read from, with the records no band kept. Nothing is removed unless the sequence
    /// counter moves on: the counter tells other processes to refresh their catalogs, so none reads a removed pack as current.
    /// False, with nothing removed, when a source changed since the scan.
    fn retireSources(self: *State, a: std.mem.Allocator, sources: []const u32) Error!bool {
        const lock = try self.sequenceLock(a) orelse return false;
        defer lock.close(self.config.io);
        for (sources) |id| {
            const file = self.catalog.files.items[id];
            const stat = std.Io.Dir.cwd().statFile(self.config.io, try self.path(a, file.name), .{ .follow_symlinks = false }) catch return false;
            if (!sameStat(stat, file.validation.?.stat)) return false;
        }
        const sequence = self.nextSequence() orelse return false;
        if (!self.writeCounter(lock, sequence)) return false;
        const removed = try a.alloc(bool, self.catalog.files.items.len);
        @memset(removed, false);
        for (sources) |id| {
            self.discard(try self.path(a, self.catalog.files.items[id].name));
            removed[id] = true;
            self.forget(id);
        }
        var dead: std.ArrayList(Digest) = .empty;
        var entries = self.catalog.entries.iterator();
        while (entries.next()) |entry| {
            if (removed[entry.value_ptr.file]) try dead.append(a, entry.key_ptr.*);
        }
        for (dead.items) |key| _ = self.catalog.entries.removeContext(key, DigestContext{});
        self.catalog.sequence = sequence;
        return true;
    }

    fn prepare(self: *State, a: std.mem.Allocator, source: std.Io.File, input: []const Record) Error!?Prepared {
        return self.assemble(a, &.{}, input, JournalBytes{ .state = self, .file = source });
    }

    /// Build one pack from the blocks `whole` keeps as they are and the records `input`, whose
    /// bytes (a record header and its payload) `fetch` supplies and which are grouped into new blocks.
    fn assemble(self: *State, a: std.mem.Allocator, whole: []const Whole, input: []const Record, fetch: anytype) Error!?Prepared {
        // Small records first, then large ones, each class in the order given. A block holds one class (`belongsBlock`), so the
        // partition keeps every block full, and a build's records of one class stay in the order it needed them.
        const records = try a.alloc(Record, input.len);
        var small: usize = 0;
        for (input) |record| {
            if (record.length > small_record) continue;
            records[small] = record;
            small += 1;
        }
        var large = small;
        for (input) |record| {
            if (record.length <= small_record) continue;
            records[large] = record;
            large += 1;
        }
        var blocks: std.ArrayList(Block) = .empty;
        var encoded: std.ArrayList([]const u8) = .empty;
        var adjusted: std.ArrayList(Record) = .empty;
        for (whole) |kept| {
            const index: u32 = @intCast(blocks.items.len);
            try blocks.append(a, .{ .offset = 0, .encoded = kept.block.encoded, .plain = kept.block.plain, .checksum = kept.block.checksum });
            try encoded.append(a, kept.bytes);
            for (kept.records) |record| {
                var next = record;
                next.block = index;
                try adjusted.append(a, next);
            }
        }
        var first: usize = 0;
        while (first < records.len) {
            var end = first;
            var length: usize = 0;
            while (end < records.len and belongsBlock(records[first], records[end], length)) : (end += 1) length += record_header + records[end].length;
            const plain = try a.alloc(u8, length);
            var offset: usize = 0;
            for (records[first..end]) |record| {
                const size = record_header + record.length;
                if (!fetch.read(record, plain[offset..][0..size])) return null;
                const header: *const [record_header]u8 = plain[offset..][0..record_header];
                if (!validRecordHeader(header)) return null;
                if (!std.meta.eql(record, readRecord(header, record.offset))) return null;
                if (!std.mem.eql(u8, &checksum(plain[offset + record_header ..][0..record.length]), &record.checksum)) return null;
                var next = record;
                next.block = @intCast(blocks.items.len);
                next.offset = offset + record_header;
                try adjusted.append(a, next);
                offset += size;
            }
            const bytes = try compression.encodeWithPolicy(a, plain, self.config.compression);
            try encoded.append(a, bytes);
            try blocks.append(a, .{ .offset = 0, .encoded = @intCast(bytes.len), .plain = @intCast(plain.len), .checksum = checksum(bytes) });
            first = end;
        }
        var writer = codec.Writer.init(a);
        try writer.write(Index, .{ .blocks = blocks.items, .records = adjusted.items });
        const index_length = writer.bytes.items.len;
        var offset: u64 = pack_header + index_length;
        for (blocks.items) |*block| {
            block.offset = offset;
            offset += block.encoded;
        }
        writer.bytes.clearRetainingCapacity();
        try writer.write(Index, .{ .blocks = blocks.items, .records = adjusted.items });
        if (writer.bytes.items.len != index_length or index_length > maximum_index) return null;
        const bytes = try a.alloc(u8, @intCast(offset));
        @memcpy(bytes[0..pack_magic.len], pack_magic);
        @memcpy(bytes[pack_magic.len..][0..32], &self.config.identity);
        std.mem.writeInt(u64, bytes[pack_magic.len + 32 ..][0..8], index_length, .little);
        @memcpy(bytes[pack_magic.len + 40 ..][0..32], &checksum(writer.bytes.items));
        @memcpy(bytes[pack_header..][0..index_length], writer.bytes.items);
        for (blocks.items, encoded.items) |block, content| @memcpy(bytes[@intCast(block.offset)..][0..content.len], content);
        return .{ .bytes = bytes, .index = .{ .blocks = blocks.items, .records = adjusted.items } };
    }

    fn sameStat(lhs: std.Io.File.Stat, rhs: std.Io.File.Stat) bool {
        if (lhs.inode != rhs.inode or lhs.size != rhs.size) return false;
        return std.meta.eql(lhs.mtime, rhs.mtime) and std.meta.eql(lhs.ctime, rhs.ctime);
    }

    fn belongsBlock(first: Record, next: Record, length: usize) bool {
        if (length == 0) return true;
        const target: usize = if (first.length <= small_record) block_target else body_target;
        if (length >= target or next.length >= target) return false;
        if (record_header + next.length > target - length) return false;
        return (first.length <= small_record) == (next.length <= small_record);
    }

    fn discard(self: *State, path_name: []const u8) void {
        std.Io.Dir.cwd().deleteFile(self.config.io, path_name) catch return;
    }

    /// Snapshot physical reads and decoded block work under the shared lock.
    pub fn statistics(self: *State) Statistics {
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        return self.cached.statistics;
    }

    fn stageBytes(self: *State, a: std.mem.Allocator, prepared: Prepared) Error!?Pending {
        var nonce: [16]u8 = undefined;
        std.Io.random(self.config.io, &nonce);
        const name = try std.fmt.allocPrint(a, "{s}{s}", .{ std.fmt.bytesToHex(nonce, .lower), pack_suffix });
        const temporary = try std.fmt.allocPrint(a, "{s}.partial", .{name});
        const final_path = try self.path(a, name);
        const temp_path = try self.path(a, temporary);
        std.Io.Dir.cwd().writeFile(self.config.io, .{ .sub_path = temp_path, .data = prepared.bytes }) catch {
            self.discard(temp_path);
            return null;
        };
        self.cached.statistics.publication.packs_prepared += 1;
        self.cached.statistics.publication.pack_bytes_prepared += prepared.bytes.len;
        return .{ .prepared = prepared, .name = name, .final_path = final_path, .temporary = temp_path };
    }

    fn publishBytes(self: *State, pending: Pending) Error!bool {
        const index = pending.prepared.index;
        const bytes = pending.prepared.bytes;
        const id = try self.fileId(.{ .name = pending.name, .kind = .pack });
        try self.catalog.entries.ensureUnusedCapacityContext(self.config.a, @intCast(index.records.len), DigestContext{});
        const blocks = try self.config.a.dupe(Block, index.blocks);
        var owned = true;
        errdefer if (owned) self.config.a.free(blocks);
        std.Io.Dir.cwd().rename(pending.temporary, std.Io.Dir.cwd(), pending.final_path, self.config.io) catch {
            self.config.a.free(blocks);
            return false;
        };
        self.catalog.files.items[id].blocks = blocks;
        owned = false;
        self.catalog.files.items[id].scanned = bytes.len;
        const stat = std.Io.Dir.cwd().statFile(self.config.io, pending.final_path, .{}) catch return false;
        self.catalog.files.items[id].validation = .{ .stat = stat, .length = std.mem.readInt(u64, bytes[pack_magic.len + 32 ..][0..8], .little), .digest = bytes[pack_magic.len + 40 ..][0..32].* };
        for (index.records) |record| try self.admit(id, record);
        return true;
    }
};
