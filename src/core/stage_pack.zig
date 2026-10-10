//! Durable append journals sealed into immutable, independently compressed packs.
const std = @import("std");
const codec = @import("mylang").persist_codec;
const compression = @import("stage_compression.zig");
const Digest = [32]u8;
const Error = std.mem.Allocator.Error;
const pack_magic = "mylang-pack-v1!\n\x00";
const journal_magic = "mylang-journal-v1";
const lock_magic = "stage-v2";
const pack_header = pack_magic.len + 32 + 8 + 32;
const journal_header = journal_magic.len + 32;
const record_header = 112;
const block_target = 256 << 10;
const body_target = 64 << 10;
const pack_target = 4 << 20;
const maximum_bytes = 256 << 20;
const maximum_block = maximum_bytes + block_target + record_header * 2;
const maximum_index = 32 << 20;
const pack_suffix = ".pack";
const journal_suffix = ".journal";

const Block = struct { offset: u64, encoded: u32, plain: u32, checksum: Digest };
const Record = struct { key: Digest, checksum: Digest, sequence: u64, block: u32 = 0, offset: u64, length: u32 };
const Index = struct { blocks: []const Block, records: []const Record };
const Validation = struct { stat: std.Io.File.Stat, length: u64, digest: Digest };
const File = struct { validation: ?Validation = null, name: []const u8, kind: enum { journal, pack }, scanned: u64 = 0, blocks: []const Block = &.{} };
const Location = struct { file: u32, record: Record };
const CachedBlock = struct { file: u32, block: u32, bytes: []const u8, stat: std.Io.File.Stat };
/// Packed-block work, excluding direct journal reads and ordinary cache metadata.
pub const Statistics = struct {
    packed_bytes_read: u64 = 0,
    decoded_bytes: u64 = 0,
    blocks_decoded: u64 = 0,
    payload_bytes_returned: u64 = 0,
    block_cache_hits: u64 = 0,
};
const Journal = struct { file: u32, length: u64 = journal_header, records: std.ArrayList(Record) = .empty, bytes: usize = 0 };

/// Shallow Store copies share this state; callers own exactly one deinitialization.
pub const State = struct {
    config: struct { a: std.mem.Allocator, io: std.Io, root: []const u8, identity: Digest },
    mutex: std.Io.Mutex = .init,
    catalog: struct { files: std.ArrayList(File) = .empty, entries: std.AutoHashMapUnmanaged(Digest, Location) = .empty, sequence: u64 = 0, max_sequence: u64 = 0, scanned: bool = false } = .{},
    journal: ?Journal = null,
    cached: struct { blocks: [32]?CachedBlock = @splat(null), statistics: Statistics = .{} } = .{},

    /// Allocate shared state without creating or trusting cache files.
    pub fn init(a: std.mem.Allocator, io: std.Io, root: []const u8, identity: Digest) Error!*State {
        const self = try a.create(State);
        self.* = .{ .config = .{ .a = a, .io = io, .root = root, .identity = identity } };
        return self;
    }

    pub fn deinit(self: *State) void {
        _ = self.flush() catch false;
        const a = self.config.a;
        if (self.journal) |*journal| journal.records.deinit(a);
        for (self.catalog.files.items) |file| {
            a.free(file.name);
            a.free(file.blocks);
        }
        for (self.cached.blocks) |cached| if (cached) |block| a.free(block.bytes);
        self.catalog.files.deinit(a);
        self.catalog.entries.deinit(a);
        a.destroy(self);
    }

    fn path(self: *State, a: std.mem.Allocator, name: []const u8) Error![]const u8 {
        return std.fs.path.join(a, &.{ self.config.root, name });
    }

    fn checksum(bytes: []const u8) Digest {
        var digest: Digest = undefined;
        std.crypto.hash.Blake3.hash(bytes, &digest, .{});
        return digest;
    }

    fn counter(self: *State) Error!u64 {
        var buffer: [48]u8 = undefined;
        var scratch = std.heap.ArenaAllocator.init(self.config.a);
        defer scratch.deinit();
        const name = try self.path(scratch.allocator(), "sequence");
        const file = std.Io.Dir.cwd().openFile(self.config.io, name, .{}) catch return 0;
        defer file.close(self.config.io);
        if ((file.readPositionalAll(self.config.io, &buffer, 0) catch return 0) != buffer.len) return 0;
        if (!std.mem.eql(u8, buffer[0..8], lock_magic)) return 0;
        if (!std.mem.eql(u8, buffer[16..48], &checksum(buffer[0..16]))) return 0;
        return std.mem.readInt(u64, buffer[8..16], .little);
    }

    fn refresh(self: *State, a: std.mem.Allocator, force: bool) Error!void {
        const sequence = try self.counter();
        if (!force and self.catalog.scanned and sequence == self.catalog.sequence) return;
        var directory = std.Io.Dir.cwd().openDir(self.config.io, self.config.root, .{ .iterate = true }) catch return;
        defer directory.close(self.config.io);
        var iterator = directory.iterate();
        while (iterator.next(self.config.io) catch null) |entry| {
            if (entry.kind != .file) continue;
            const kind: File = if (std.mem.endsWith(u8, entry.name, pack_suffix)) .{ .name = entry.name, .kind = .pack } else if (std.mem.endsWith(u8, entry.name, journal_suffix)) .{ .name = entry.name, .kind = .journal } else continue;
            const id = try self.fileId(kind);
            if (kind.kind == .pack and self.catalog.files.items[id].scanned != 0) continue;
            const file = directory.openFile(self.config.io, entry.name, .{}) catch continue;
            defer file.close(self.config.io);
            if (kind.kind == .pack) try self.scanPack(a, file, id) else try self.scanJournal(file, id);
        }
        self.catalog.sequence = sequence;
        self.catalog.scanned = true;
    }

    fn fileId(self: *State, file: File) Error!u32 {
        for (self.catalog.files.items, 0..) |known, index| if (std.mem.eql(u8, known.name, file.name)) return @intCast(index);
        const name = try self.config.a.dupe(u8, file.name);
        errdefer self.config.a.free(name);
        try self.catalog.files.append(self.config.a, .{ .name = name, .kind = file.kind });
        return @intCast(self.catalog.files.items.len - 1);
    }

    fn admit(self: *State, id: u32, record: Record) Error!void {
        self.catalog.max_sequence = @max(self.catalog.max_sequence, record.sequence);
        const slot = try self.catalog.entries.getOrPut(self.config.a, record.key);
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

    fn scanPack(self: *State, a: std.mem.Allocator, file: std.Io.File, id: u32) Error!void {
        var header: [pack_header]u8 = undefined;
        if ((file.readPositionalAll(self.config.io, &header, 0) catch return) != header.len) return;
        if (!std.mem.eql(u8, header[0..pack_magic.len], pack_magic) or !std.mem.eql(u8, header[pack_magic.len..][0..32], &self.config.identity)) return;
        const length = std.mem.readInt(u64, header[pack_magic.len + 32 ..][0..8], .little);
        if (length > maximum_index) return;
        const stat = file.stat(self.config.io) catch return;
        const size = stat.size;
        if (size < pack_header or length > size - pack_header) return;
        const bytes = try a.alloc(u8, @intCast(length));
        if ((file.readPositionalAll(self.config.io, bytes, pack_header) catch return) != bytes.len) return;
        if (!std.mem.eql(u8, &checksum(bytes), header[pack_magic.len + 40 ..][0..32])) return;
        if (!validIndexEncoding(bytes)) return;
        var reader = codec.Reader.init(a, bytes);
        const index = reader.read(Index) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return;
        };
        if (!reader.done() or !validIndex(index, size, pack_header + length)) return;
        const blocks = try self.config.a.dupe(Block, index.blocks);
        self.catalog.files.items[id].blocks = blocks;
        self.catalog.files.items[id].scanned = size;
        self.catalog.files.items[id].validation = .{ .stat = stat, .length = length, .digest = checksum(bytes) };
        for (index.records) |record| try self.admit(id, record);
    }

    // Bound fixed-width counts before the generic codec allocates owned slices.
    fn validIndexEncoding(bytes: []const u8) bool {
        if (bytes.len < 16) return false;
        const blocks = std.mem.readInt(u64, bytes[0..8], .little);
        if (blocks > (bytes.len - 16) / 48) return false;
        const position: usize = 8 + @as(usize, @intCast(blocks)) * 48;
        const records = std.mem.readInt(u64, bytes[position..][0..8], .little);
        const remaining = bytes.len - position - 8;
        if (records > remaining / 88) return false;
        return records * 88 == remaining;
    }

    fn validIndex(index: Index, size: u64, start: u64) bool {
        for (index.blocks) |block| {
            if (block.plain > maximum_block or block.encoded > maximum_block + 1) return false;
            if (block.offset < start or block.offset > size) return false;
            if (block.encoded > size - block.offset) return false;
        }
        for (index.records) |record| {
            if (record.block >= index.blocks.len or record.length > maximum_bytes) return false;
            const block = index.blocks[record.block];
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
        const location = self.catalog.entries.get(key) orelse return null;
        if (expected) |digest| if (!std.mem.eql(u8, &digest, &location.record.checksum)) return null;
        const metadata = self.catalog.files.items[location.file];
        const file = std.Io.Dir.cwd().openFile(self.config.io, try self.path(work, metadata.name), .{}) catch return null;
        defer file.close(self.config.io);
        const payload = if (metadata.kind == .journal) try self.loadJournal(work, file, location.record) else try self.loadBlock(work, file, location.file, metadata, location.record);
        const bytes = payload orelse return null;
        if (!std.mem.eql(u8, &checksum(bytes), &location.record.checksum)) return null;
        const owned = try a.dupe(u8, bytes);
        self.cached.statistics.payload_bytes_returned += bytes.len;
        return owned;
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

    fn loadBlock(self: *State, a: std.mem.Allocator, file: std.Io.File, id: u32, metadata: File, record: Record) Error!?[]const u8 {
        if (record.block >= metadata.blocks.len) return null;
        const block = metadata.blocks[record.block];
        const stat = file.stat(self.config.io) catch return null;
        if (!try self.validBacking(a, file, id, metadata, stat)) return null;
        const slot = &self.cached.blocks[(@as(usize, id) * 17 + record.block) % self.cached.blocks.len];
        const hit = if (slot.*) |cached| cached.file == id and cached.block == record.block and sameStat(cached.stat, stat) else false;
        if (hit) self.cached.statistics.block_cache_hits += 1;
        const plain = if (hit) slot.*.?.bytes else blk: {
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
            if (decoded.len <= block_target * 2) {
                const owned = try self.config.a.dupe(u8, decoded);
                if (slot.*) |old| self.config.a.free(old.bytes);
                slot.* = .{ .file = id, .block = record.block, .bytes = owned, .stat = stat };
            }
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
        const location = self.catalog.entries.get(key) orelse return null;
        const owned = try self.path(a, self.catalog.files.items[location.file].name);
        return owned;
    }

    fn sequenceLock(self: *State, a: std.mem.Allocator) Error!?std.Io.File {
        std.Io.Dir.cwd().createDirPath(self.config.io, self.config.root) catch return null;
        return std.Io.Dir.cwd().createFile(self.config.io, try self.path(a, "sequence"), .{ .read = true, .truncate = false, .lock = .exclusive }) catch null;
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
        var seal = false;
        if (!try self.saveRecord(key, payload, &seal)) return false;
        // saveRecord has released both publication locks. Sealing is optional:
        // allocation failure is explicit; I/O failure leaves the journal available.
        if (seal) _ = try self.flush();
        return true;
    }

    fn saveRecord(self: *State, key: Digest, payload: []const u8, seal: *bool) Error!bool {
        if (payload.len > maximum_bytes) return false;
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        var scratch = std.heap.ArenaAllocator.init(self.config.a);
        defer scratch.deinit();
        const a = scratch.allocator();
        const lock = try self.sequenceLock(a) orelse return false;
        defer lock.close(self.config.io);
        try self.refresh(a, false);
        const sequence = std.math.add(u64, @max(self.catalog.sequence, self.catalog.max_sequence), 1) catch return false;
        const file = try self.journalFile(a) orelse return false;
        defer file.close(self.config.io);
        const journal = &self.journal.?;
        // Reserve before publication so OOM cannot leave a successful unindexed save.
        try journal.records.ensureUnusedCapacity(self.config.a, 1);
        try self.catalog.entries.ensureUnusedCapacity(self.config.a, 1);
        const record: Record = .{ .key = key, .checksum = checksum(payload), .sequence = sequence, .offset = journal.length + record_header, .length = @intCast(payload.len) };
        const bytes = try a.alloc(u8, record_header + payload.len);
        std.mem.writeInt(u64, bytes[0..8], payload.len, .little);
        std.mem.writeInt(u64, bytes[8..16], sequence, .little);
        @memcpy(bytes[16..48], &key);
        @memcpy(bytes[48..80], &record.checksum);
        @memcpy(bytes[80..112], &checksum(bytes[0..80]));
        @memcpy(bytes[record_header..], payload);
        file.writePositionalAll(self.config.io, bytes, journal.length) catch return false;
        if (!self.writeCounter(lock, sequence)) return false;
        journal.length += bytes.len;
        journal.bytes += bytes.len;
        journal.records.appendAssumeCapacity(record);
        self.catalog.files.items[journal.file].scanned = journal.length;
        try self.admit(journal.file, record);
        self.catalog.sequence = sequence;
        seal.* = journal.bytes >= pack_target;
        return true;
    }

    /// Seal a bounded journal; failure leaves its durable records available.
    pub fn flush(self: *State) Error!bool {
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        if (self.journal == null or self.journal.?.records.items.len == 0) return true;
        var scratch = std.heap.ArenaAllocator.init(self.config.a);
        defer scratch.deinit();
        const a = scratch.allocator();
        const lock = try self.sequenceLock(a) orelse return false;
        defer lock.close(self.config.io);
        try self.refresh(a, false);
        const journal = &self.journal.?;
        const source_name = self.catalog.files.items[journal.file].name;
        const source = std.Io.Dir.cwd().openFile(self.config.io, try self.path(a, source_name), .{}) catch return false;
        defer source.close(self.config.io);
        var first: usize = 0;
        while (first < journal.records.items.len) {
            var end = first;
            var bytes: usize = 0;
            while (end < journal.records.items.len and (bytes < pack_target or end == first)) : (end += 1) bytes += record_header + journal.records.items[end].length;
            var chunk = std.heap.ArenaAllocator.init(self.config.a);
            defer chunk.deinit();
            if (!try self.publish(chunk.allocator(), source, journal.records.items[first..end])) return false;
            first = end;
        }
        const sequence = std.math.add(u64, @max(self.catalog.sequence, self.catalog.max_sequence), 1) catch return false;
        if (!self.writeCounter(lock, sequence)) return false;
        std.Io.Dir.cwd().deleteFile(self.config.io, try self.path(a, source_name)) catch return false;
        journal.records.deinit(self.config.a);
        self.journal = null;
        self.catalog.sequence = sequence;
        return true;
    }

    fn publish(self: *State, a: std.mem.Allocator, source: std.Io.File, input: []const Record) Error!bool {
        const records = try a.dupe(Record, input);
        std.mem.sort(Record, records, {}, smallerRecord);
        var blocks: std.ArrayList(Block) = .empty;
        var encoded: std.ArrayList([]const u8) = .empty;
        var adjusted: std.ArrayList(Record) = .empty;
        var first: usize = 0;
        while (first < records.len) {
            var end = first;
            var length: usize = 0;
            while (end < records.len and belongsBlock(records[first], records[end], length)) : (end += 1) length += record_header + records[end].length;
            const plain = try a.alloc(u8, length);
            var offset: usize = 0;
            for (records[first..end]) |record| {
                const size = record_header + record.length;
                if ((source.readPositionalAll(self.config.io, plain[offset..][0..size], record.offset - record_header) catch return false) != size) return false;
                const header: *const [record_header]u8 = plain[offset..][0..record_header];
                if (!validRecordHeader(header)) return false;
                if (!std.meta.eql(record, readRecord(header, record.offset))) return false;
                if (!std.mem.eql(u8, &checksum(plain[offset + record_header ..][0..record.length]), &record.checksum)) return false;
                var next = record;
                next.block = @intCast(blocks.items.len);
                next.offset = offset + record_header;
                try adjusted.append(a, next);
                offset += size;
            }
            const bytes = try compression.encode(a, plain);
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
        if (writer.bytes.items.len != index_length or index_length > maximum_index) return false;
        const bytes = try a.alloc(u8, @intCast(offset));
        @memcpy(bytes[0..pack_magic.len], pack_magic);
        @memcpy(bytes[pack_magic.len..][0..32], &self.config.identity);
        std.mem.writeInt(u64, bytes[pack_magic.len + 32 ..][0..8], index_length, .little);
        @memcpy(bytes[pack_magic.len + 40 ..][0..32], &checksum(writer.bytes.items));
        @memcpy(bytes[pack_header..][0..index_length], writer.bytes.items);
        for (blocks.items, encoded.items) |block, content| @memcpy(bytes[@intCast(block.offset)..][0..content.len], content);
        return self.publishBytes(a, bytes, .{ .blocks = blocks.items, .records = adjusted.items });
    }

    fn sameStat(lhs: std.Io.File.Stat, rhs: std.Io.File.Stat) bool {
        if (lhs.inode != rhs.inode or lhs.size != rhs.size) return false;
        return std.meta.eql(lhs.mtime, rhs.mtime) and std.meta.eql(lhs.ctime, rhs.ctime);
    }

    fn belongsBlock(first: Record, next: Record, length: usize) bool {
        if (length == 0) return true;
        const target: usize = if (first.length <= 4096) block_target else body_target;
        if (length >= target or next.length >= target) return false;
        if (record_header + next.length > target - length) return false;
        return (first.length <= 4096) == (next.length <= 4096);
    }

    fn discard(self: *State, path_name: []const u8) void {
        std.Io.Dir.cwd().deleteFile(self.config.io, path_name) catch return;
    }

    fn smallerRecord(_: void, lhs: Record, rhs: Record) bool {
        return if (lhs.length == rhs.length) lhs.sequence < rhs.sequence else lhs.length < rhs.length;
    }

    /// Snapshot physical reads and decoded block work under the shared lock.
    pub fn statistics(self: *State) Statistics {
        self.mutex.lockUncancelable(self.config.io);
        defer self.mutex.unlock(self.config.io);
        return self.cached.statistics;
    }

    fn publishBytes(self: *State, a: std.mem.Allocator, bytes: []const u8, index: Index) Error!bool {
        var nonce: [16]u8 = undefined;
        std.Io.random(self.config.io, &nonce);
        const name = try std.fmt.allocPrint(a, "{s}{s}", .{ std.fmt.bytesToHex(nonce, .lower), pack_suffix });
        const temporary = try std.fmt.allocPrint(a, "{s}.partial", .{name});
        const final_path = try self.path(a, name);
        const temp_path = try self.path(a, temporary);
        defer self.discard(temp_path);
        const id = try self.fileId(.{ .name = name, .kind = .pack });
        const blocks = try self.config.a.dupe(Block, index.blocks);
        var owned = true;
        errdefer if (owned) self.config.a.free(blocks);
        std.Io.Dir.cwd().writeFile(self.config.io, .{ .sub_path = temp_path, .data = bytes }) catch {
            self.config.a.free(blocks);
            return false;
        };
        std.Io.Dir.cwd().rename(temp_path, std.Io.Dir.cwd(), final_path, self.config.io) catch {
            self.config.a.free(blocks);
            return false;
        };
        self.catalog.files.items[id].blocks = blocks;
        owned = false;
        self.catalog.files.items[id].scanned = bytes.len;
        const stat = std.Io.Dir.cwd().statFile(self.config.io, final_path, .{}) catch return false;
        self.catalog.files.items[id].validation = .{ .stat = stat, .length = std.mem.readInt(u64, bytes[pack_magic.len + 32 ..][0..8], .little), .digest = bytes[pack_magic.len + 40 ..][0..32].* };
        for (index.records) |record| try self.admit(id, record);
        return true;
    }
};
