//! The record format of the incremental engine (spec §9): what a query read, what it produced, and the trailer that
//! lets a reader reject a torn file. Little-endian, fixed-width integers, u32-prefixed byte blocks, 32-byte digests.
//! The Selka codec of L1d reads and writes the same bytes.
//!
//! Format 2 (spec §17.3) adds the parts table beside the payload and the projection read (tag 7). Format 1 records are
//! still read, as records with no parts and no part reads; a writer writes format 2.
const std = @import("std");
const digest_rules = @import("digest.zig");
const fast_blake3 = @import("../fast_blake3.zig");
const world = @import("world.zig");
const Digest = digest_rules.Digest;
const Stat = world.Stat;

/// The eight bytes that start a record.
pub const magic = "SLKREC01";
/// The record format version this file writes.
pub const format_version: u32 = 2;
/// The oldest record format version this file still reads.
pub const oldest_format: u32 = 1;
/// The format that has no parts table and no projection read.
pub const format_without_parts: u32 = 1;
/// The longest path, name or value a record holds: a longer one is a malformed record, not an allocation.
pub const max_block = 1 << 30;

/// A file read: the digest of the bytes, or `present = false` for a path looked for and absent (digest zero). The
/// stat tuple is `Stat.none` when the file was absent or too recently changed to trust its tuple.
pub const FileRead = struct { path: []const u8, present: bool, digest: Digest, stat: Stat };
/// An existence test: whether anything was at the path.
pub const ExistsRead = struct { path: []const u8, present: bool };
/// A directory listing: the digest of the sorted names filter number `filter` keeps, when the directory opened.
pub const ListingRead = struct { path: []const u8, filter: u8, opened: bool, digest: Digest };
/// An environment variable: its value when set. A placement variable is recorded and never compared.
pub const VariableRead = struct { name: []const u8, set: bool, value: []const u8, placement: bool };
/// A tool: the identity it had (zero when it could not be found).
pub const ToolRead = struct { path: []const u8, identity: Digest };
/// A query: the dependency's kind and key, and the result digest it had.
pub const QueryRead = struct { kind: []const u8, key: Digest, result: Digest };

/// One part of a query's result: a name and the digest of what that part holds (spec §17.3).
pub const Part = struct { name: []const u8, digest: Digest };
/// What a projection read saw of one named part: its digest, or that the dependency had no part of that name.
pub const PartSight = struct { name: []const u8, present: bool, digest: Digest };
/// A projection read: the dependency's kind and key, and what it saw of each part the reader named, in byte order of the
/// names with none twice. The reader is valid while those parts, and only those, are as it saw them.
pub const PartRead = struct { kind: []const u8, key: Digest, parts: []const PartSight };

/// One read a query made, in the vocabulary of spec §4.
pub const Read = union(enum) {
    file: FileRead,
    exists: ExistsRead,
    listing: ListingRead,
    variable: VariableRead,
    tool: ToolRead,
    query: QueryRead,
    /// Only in format 2.
    part: PartRead,

    /// The wire tag of this read.
    pub fn tag(self: Read) u8 {
        return switch (self) {
            .file => 1,
            .exists => 2,
            .listing => 3,
            .variable => 4,
            .tool => 5,
            .query => 6,
            .part => 7,
        };
    }
};

/// Where a record keeps its payload: inline, or as an object named by its digest.
pub const Payload = union(enum) { inline_bytes: []const u8, object: Digest };

/// One record: the key it is stored under, the query it answers, what it read and what it produced. `parts` is the
/// table of named digests the query published (format 2), in byte order of the names with none twice; a format 1 record
/// has none.
pub const Record = struct {
    kind: []const u8,
    identity: Digest,
    key: Digest,
    argument: []const u8,
    result: Digest,
    payload: Payload,
    reads: []const Read,
    parts: []const Part = &.{},
};

/// Why a record could not be read. Both are a miss for the caller.
pub const DecodeError = error{ OutOfMemory, Malformed, UnknownFormat };

/// Why a record could not be written in the format asked for.
pub const EncodeError = error{ OutOfMemory, NotExpressible };

/// Whether `names` are in strictly ascending byte order: sorted, with none twice.
pub fn strictlyAscending(comptime T: type, items: []const T) bool {
    if (items.len < 2) return true;
    for (items[1..], items[0 .. items.len - 1]) |next, before| {
        if (!std.mem.lessThan(u8, before.name, next.name)) return false;
    }
    return true;
}

const trailer_length = 32;

/// The bytes of `record`, trailer included, in `a`, in the current format.
pub fn encode(a: std.mem.Allocator, record: Record) std.mem.Allocator.Error![]u8 {
    return encodeFormat(a, record, format_version) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.NotExpressible => unreachable,
    };
}

/// The bytes of `record` in format `version`. Format 1 has no parts table and no projection read, so a record that has
/// either is `NotExpressible` there; the frozen format 1 test vectors are written and checked through this.
pub fn encodeFormat(a: std.mem.Allocator, record: Record, version: u32) EncodeError![]u8 {
    if (version < oldest_format or version > format_version) return error.NotExpressible;
    if (version == format_without_parts) {
        if (record.parts.len != 0) return error.NotExpressible;
        for (record.reads) |read| if (read == .part) return error.NotExpressible;
    }
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try out.appendSlice(a, magic);
    try putU32(&out, a, version);
    try putBlock(&out, a, record.kind);
    try out.appendSlice(a, &record.identity);
    try out.appendSlice(a, &record.key);
    try putBlock(&out, a, record.argument);
    try out.appendSlice(a, &record.result);
    switch (record.payload) {
        .inline_bytes => |bytes| {
            try out.append(a, 0);
            try putBlock(&out, a, bytes);
        },
        .object => |object| {
            try out.append(a, 1);
            try out.appendSlice(a, &object);
        },
    }
    if (version >= 2) {
        try putU32(&out, a, @intCast(record.parts.len));
        for (record.parts) |part| {
            try putBlock(&out, a, part.name);
            try out.appendSlice(a, &part.digest);
        }
    }
    try putU32(&out, a, @intCast(record.reads.len));
    for (record.reads) |read| try putRead(&out, a, read);
    const trailer = digest_rules.hash(out.items);
    try out.appendSlice(a, &trailer);
    return out.toOwnedSlice(a);
}

fn putRead(out: *std.ArrayList(u8), a: std.mem.Allocator, read: Read) std.mem.Allocator.Error!void {
    try out.append(a, read.tag());
    switch (read) {
        .file => |file| {
            try putBlock(out, a, file.path);
            try out.append(a, @intFromBool(file.present));
            try out.appendSlice(a, &file.digest);
            try putU64(out, a, file.stat.inode);
            try putU64(out, a, file.stat.size);
            try putU64(out, a, @bitCast(file.stat.mtime));
            try putU64(out, a, @bitCast(file.stat.ctime));
        },
        .exists => |probe| {
            try putBlock(out, a, probe.path);
            try out.append(a, @intFromBool(probe.present));
        },
        .listing => |listing| {
            try putBlock(out, a, listing.path);
            try out.append(a, listing.filter);
            try out.append(a, @intFromBool(listing.opened));
            if (listing.opened) try out.appendSlice(a, &listing.digest);
        },
        .variable => |variable| {
            try putBlock(out, a, variable.name);
            try out.append(a, @intFromBool(variable.set));
            if (variable.set) try putBlock(out, a, variable.value);
            try out.append(a, @intFromBool(variable.placement));
        },
        .tool => |tool| {
            try putBlock(out, a, tool.path);
            try out.appendSlice(a, &tool.identity);
        },
        .query => |query| {
            try putBlock(out, a, query.kind);
            try out.appendSlice(a, &query.key);
            try out.appendSlice(a, &query.result);
        },
        .part => |part| {
            try putBlock(out, a, part.kind);
            try out.appendSlice(a, &part.key);
            try putU32(out, a, @intCast(part.parts.len));
            for (part.parts) |sight| {
                try putBlock(out, a, sight.name);
                try out.append(a, @intFromBool(sight.present));
                if (sight.present) try out.appendSlice(a, &sight.digest);
            }
        },
    }
}

fn putU32(out: *std.ArrayList(u8), a: std.mem.Allocator, value: u32) std.mem.Allocator.Error!void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    try out.appendSlice(a, &bytes);
}

fn putU64(out: *std.ArrayList(u8), a: std.mem.Allocator, value: u64) std.mem.Allocator.Error!void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    try out.appendSlice(a, &bytes);
}

fn putBlock(out: *std.ArrayList(u8), a: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error!void {
    try putU32(out, a, @intCast(bytes.len));
    try out.appendSlice(a, bytes);
}

/// The record `bytes` hold. Strings and payload bytes borrow from `bytes`; the reads and the parts are allocated in `a`.
/// A trailer mismatch, a short file or an out-of-range field is `Malformed`; an unknown magic or version is
/// `UnknownFormat`. A format 1 record has no parts and no part reads (a tag 7 in it is `Malformed`), and so does any
/// record with a read tag this reader does not know.
pub fn decode(a: std.mem.Allocator, bytes: []const u8) DecodeError!Record {
    if (bytes.len < magic.len + 4 + trailer_length) return error.Malformed;
    if (!std.mem.eql(u8, bytes[0..magic.len], magic)) return error.UnknownFormat;
    const version = std.mem.readInt(u32, bytes[magic.len..][0..4], .little);
    if (version < oldest_format or version > format_version) return error.UnknownFormat;
    const body = bytes[0 .. bytes.len - trailer_length];
    const trailer = digest_rules.hash(body);
    if (!std.mem.eql(u8, &trailer, bytes[body.len..][0..trailer_length])) return error.Malformed;
    var reader: Reader = .{ .bytes = body, .position = magic.len + 4, .version = version };
    const kind = try reader.block();
    const identity = try reader.digest();
    const key = try reader.digest();
    const argument = try reader.block();
    const result = try reader.digest();
    const payload: Payload = switch (try reader.byte()) {
        0 => .{ .inline_bytes = try reader.block() },
        1 => .{ .object = try reader.digest() },
        else => return error.Malformed,
    };
    var parts: []Part = &.{};
    errdefer a.free(parts);
    if (version >= 2) {
        const named = try reader.word32();
        if (named > reader.remaining() / 36) return error.Malformed;
        parts = try a.alloc(Part, named);
        for (parts) |*part| part.* = .{ .name = try reader.block(), .digest = try reader.digest() };
        if (!strictlyAscending(Part, parts)) return error.Malformed;
    }
    const count = try reader.word32();
    if (count > reader.remaining()) return error.Malformed;
    const reads = try a.alloc(Read, count);
    errdefer a.free(reads);
    for (reads) |*read| read.* = try reader.read(a);
    if (reader.remaining() != 0) return error.Malformed;
    return .{ .kind = kind, .identity = identity, .key = key, .argument = argument, .result = result, .payload = payload, .reads = reads, .parts = parts };
}

/// A bounds-checked cursor over a record body.
const Reader = struct {
    bytes: []const u8,
    position: usize,
    version: u32,

    fn remaining(self: Reader) usize {
        return self.bytes.len - self.position;
    }

    fn take(self: *Reader, count: usize) error{Malformed}![]const u8 {
        if (count > self.remaining()) return error.Malformed;
        defer self.position += count;
        return self.bytes[self.position..][0..count];
    }

    fn byte(self: *Reader) error{Malformed}!u8 {
        return (try self.take(1))[0];
    }

    fn flag(self: *Reader) error{Malformed}!bool {
        return switch (try self.byte()) {
            0 => false,
            1 => true,
            else => error.Malformed,
        };
    }

    fn word32(self: *Reader) error{Malformed}!u32 {
        return std.mem.readInt(u32, (try self.take(4))[0..4], .little);
    }

    fn word64(self: *Reader) error{Malformed}!u64 {
        return std.mem.readInt(u64, (try self.take(8))[0..8], .little);
    }

    fn digest(self: *Reader) error{Malformed}!Digest {
        return (try self.take(32))[0..32].*;
    }

    fn block(self: *Reader) error{Malformed}![]const u8 {
        const length = try self.word32();
        if (length > max_block) return error.Malformed;
        return self.take(length);
    }

    fn read(self: *Reader, a: std.mem.Allocator) DecodeError!Read {
        switch (try self.byte()) {
            1 => {
                const path = try self.block();
                const present = try self.flag();
                const found = try self.digest();
                const stat: Stat = .{ .inode = try self.word64(), .size = try self.word64(), .mtime = @bitCast(try self.word64()), .ctime = @bitCast(try self.word64()) };
                return .{ .file = .{ .path = path, .present = present, .digest = found, .stat = stat } };
            },
            2 => return .{ .exists = .{ .path = try self.block(), .present = try self.flag() } },
            3 => {
                const path = try self.block();
                const filter = try self.byte();
                const opened = try self.flag();
                const found: Digest = if (opened) try self.digest() else @splat(0);
                return .{ .listing = .{ .path = path, .filter = filter, .opened = opened, .digest = found } };
            },
            4 => {
                const name = try self.block();
                const set = try self.flag();
                const value: []const u8 = if (set) try self.block() else "";
                return .{ .variable = .{ .name = name, .set = set, .value = value, .placement = try self.flag() } };
            },
            5 => return .{ .tool = .{ .path = try self.block(), .identity = try self.digest() } },
            6 => return .{ .query = .{ .kind = try self.block(), .key = try self.digest(), .result = try self.digest() } },
            7 => {
                if (self.version < 2) return error.Malformed;
                const kind = try self.block();
                const key = try self.digest();
                const named = try self.word32();
                // Each named part takes at least a name length and a presence byte.
                if (named > self.remaining() / 5) return error.Malformed;
                const sights = try a.alloc(PartSight, named);
                errdefer a.free(sights);
                for (sights) |*sight| {
                    const name = try self.block();
                    const present = try self.flag();
                    sight.* = .{ .name = name, .present = present, .digest = if (present) try self.digest() else @splat(0) };
                }
                if (!strictlyAscending(PartSight, sights)) return error.Malformed;
                return .{ .part = .{ .kind = kind, .key = key, .parts = sights } };
            },
            else => return error.Malformed,
        }
    }
};

/// The domain string that starts every read signature.
pub const signature_domain = "selka-engine-reads-v1";

/// The signature of what a record read: BLAKE3-256 over the signature domain and every read in order, as the record writes it
/// but with no stat tuple, which belongs to one tree's files, and with no value for a placement variable, which is recorded and
/// never compared. Two records of one key with the same signature read the same things and saw the same of them, so a
/// determinism contract makes their results equal; two with different signatures are two variants of the key, as when two worktrees hold
/// two versions of one module. The shared tier keeps a variant of each (`Engine.shared_variants`).
pub fn readSignature(reads: []const Read) Digest {
    var state = fast_blake3.Blake3.init(.{});
    blockInto(&state, signature_domain);
    for (reads) |read| {
        state.update(&.{read.tag()});
        switch (read) {
            .file => |file| {
                blockInto(&state, file.path);
                state.update(&.{@intFromBool(file.present)});
                state.update(&file.digest);
            },
            .exists => |probe| {
                blockInto(&state, probe.path);
                state.update(&.{@intFromBool(probe.present)});
            },
            .listing => |listing| {
                blockInto(&state, listing.path);
                state.update(&.{ listing.filter, @intFromBool(listing.opened) });
                if (listing.opened) state.update(&listing.digest);
            },
            .variable => |variable| {
                blockInto(&state, variable.name);
                state.update(&.{ @intFromBool(variable.set), @intFromBool(variable.placement) });
                if (variable.set and !variable.placement) blockInto(&state, variable.value);
            },
            .tool => |tool| {
                blockInto(&state, tool.path);
                state.update(&tool.identity);
            },
            .query => |query| {
                blockInto(&state, query.kind);
                state.update(&query.key);
                state.update(&query.result);
            },
            .part => |sighted| {
                blockInto(&state, sighted.kind);
                state.update(&sighted.key);
                var count: [4]u8 = undefined;
                std.mem.writeInt(u32, &count, @intCast(sighted.parts.len), .little);
                state.update(&count);
                for (sighted.parts) |sight| {
                    blockInto(&state, sight.name);
                    state.update(&.{@intFromBool(sight.present)});
                    if (sight.present) state.update(&sight.digest);
                }
            },
        }
    }
    var out: Digest = undefined;
    state.final(&out);
    return out;
}

fn blockInto(state: *fast_blake3.Blake3, bytes: []const u8) void {
    var length: [4]u8 = undefined;
    std.mem.writeInt(u32, &length, @intCast(bytes.len), .little);
    state.update(&length);
    state.update(bytes);
}

/// The kind name and key a record file starts with.
pub const Header = struct { kind: []const u8, key: Digest };

/// The header of a record file, without decoding its reads: enough to see whether a file is the record a lookup
/// wanted. Null for a file that is not a record of this format.
pub fn header(bytes: []const u8) ?Header {
    if (bytes.len < magic.len + 4 + trailer_length) return null;
    if (!std.mem.eql(u8, bytes[0..magic.len], magic)) return null;
    var reader: Reader = .{ .bytes = bytes[0 .. bytes.len - trailer_length], .position = magic.len + 4, .version = format_version };
    const kind = reader.block() catch return null;
    _ = reader.digest() catch return null;
    const key = reader.digest() catch return null;
    return .{ .kind = kind, .key = key };
}

/// The object a record's payload is, without decoding the rest or checking the trailer; null for an inline payload and
/// for bytes that are not a record of this format. Retention uses it to find the objects records name.
pub fn objectOf(bytes: []const u8) ?Digest {
    if (bytes.len < magic.len + 4 + trailer_length or !std.mem.eql(u8, bytes[0..magic.len], magic)) return null;
    var reader: Reader = .{ .bytes = bytes[0 .. bytes.len - trailer_length], .position = magic.len + 4, .version = format_version };
    _ = reader.block() catch return null;
    _ = reader.digest() catch return null;
    _ = reader.digest() catch return null;
    _ = reader.block() catch return null;
    _ = reader.digest() catch return null;
    const tag = reader.byte() catch return null;
    if (tag != 1) return null;
    return reader.digest() catch null;
}

fn sampleRecord(payload: Payload, reads: []const Read) Record {
    return .{ .kind = "test-exec", .identity = @splat(1), .key = @splat(2), .argument = "arg", .result = @splat(3), .payload = payload, .reads = reads };
}

const sample_parts = [_]Part{
    .{ .name = "body:main", .digest = @splat(10) },
    .{ .name = "decl:main", .digest = @splat(11) },
    .{ .name = "imports", .digest = @splat(12) },
};

const sample_sights = [_]PartSight{
    .{ .name = "decl:helper", .present = true, .digest = @splat(13) },
    .{ .name = "decl:missing", .present = false, .digest = @splat(0) },
};

const every_read = [_]Read{
    .{ .file = .{ .path = "/src/a.selka", .present = true, .digest = @splat(4), .stat = .{ .inode = 11, .size = 22, .mtime = -33, .ctime = 44 } } },
    .{ .file = .{ .path = "/src/missing.selka", .present = false, .digest = @splat(0), .stat = Stat.none } },
    .{ .exists = .{ .path = "/src/probe", .present = false } },
    .{ .listing = .{ .path = "/src", .filter = 1, .opened = true, .digest = @splat(5) } },
    .{ .listing = .{ .path = "/nowhere", .filter = 0, .opened = false, .digest = @splat(0) } },
    .{ .variable = .{ .name = "SOURCE_DATE_EPOCH", .set = true, .value = "7", .placement = false } },
    .{ .variable = .{ .name = "TMPDIR", .set = false, .value = "", .placement = true } },
    .{ .tool = .{ .path = "zig", .identity = @splat(6) } },
    .{ .query = .{ .kind = "test-plan", .key = @splat(7), .result = @splat(8) } },
    .{ .part = .{ .kind = "module-syntax", .key = @splat(9), .parts = &sample_sights } },
};

/// The reads that format 1 has.
const format_one_reads = every_read[0..9];

test "a record with every read tag and an inline payload survives its encoding" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var source = sampleRecord(.{ .inline_bytes = "verdict" }, &every_read);
    source.parts = &sample_parts;
    const bytes = try encode(a, source);
    const back = try decode(a, bytes);
    try std.testing.expectEqualStrings("test-exec", back.kind);
    try std.testing.expectEqualStrings("arg", back.argument);
    try std.testing.expectEqualStrings("verdict", back.payload.inline_bytes);
    try std.testing.expectEqual(@as(usize, every_read.len), back.reads.len);
    try std.testing.expectEqual(@as(i64, -33), back.reads[0].file.stat.mtime);
    try std.testing.expect(!back.reads[1].file.present);
    try std.testing.expect(!back.reads[4].listing.opened);
    try std.testing.expectEqualStrings("7", back.reads[5].variable.value);
    try std.testing.expect(back.reads[6].variable.placement);
    try std.testing.expectEqual(@as(Digest, @splat(8)), back.reads[8].query.result);
    try std.testing.expectEqualStrings("module-syntax", back.reads[9].part.kind);
    try std.testing.expectEqual(@as(Digest, @splat(9)), back.reads[9].part.key);
    try std.testing.expectEqual(@as(usize, 2), back.reads[9].part.parts.len);
    try std.testing.expectEqualStrings("decl:helper", back.reads[9].part.parts[0].name);
    try std.testing.expectEqual(@as(Digest, @splat(13)), back.reads[9].part.parts[0].digest);
    try std.testing.expect(!back.reads[9].part.parts[1].present);
    try std.testing.expectEqual(@as(usize, 3), back.parts.len);
    try std.testing.expectEqualStrings("decl:main", back.parts[1].name);
    try std.testing.expectEqual(@as(Digest, @splat(12)), back.parts[2].digest);
    // Encoding what was decoded gives the same bytes.
    try std.testing.expectEqualSlices(u8, bytes, try encode(a, back));
}

test "a record with an object payload keeps the digest, and the header names the key without the reads" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try encode(a, sampleRecord(.{ .object = @splat(9) }, &.{}));
    const back = try decode(a, bytes);
    try std.testing.expectEqual(@as(Digest, @splat(9)), back.payload.object);
    const seen = header(bytes).?;
    try std.testing.expectEqualStrings("test-exec", seen.kind);
    try std.testing.expectEqual(@as(Digest, @splat(2)), seen.key);
    try std.testing.expectEqual(@as(?Digest, @splat(9)), objectOf(bytes));
    try std.testing.expectEqual(@as(?Digest, null), objectOf(try encode(a, sampleRecord(.{ .inline_bytes = "x" }, &.{}))));
    try std.testing.expectEqual(@as(?Digest, null), objectOf("not a record"));
}

/// How many prefixes of `bytes` decode as a record.
fn survivingCuts(a: std.mem.Allocator, bytes: []const u8) usize {
    var survivors: usize = 0;
    for (0..bytes.len) |cut| {
        if (decode(a, bytes[0..cut])) |_| survivors += 1 else |_| {}
    }
    return survivors;
}

/// How many copies of `bytes` with one byte changed still decode as a record.
fn survivingFlips(a: std.mem.Allocator, bytes: []const u8) usize {
    var survivors: usize = 0;
    const damaged = a.dupe(u8, bytes) catch return bytes.len;
    for (0..damaged.len) |at| {
        damaged[at] ^= 1;
        if (decode(a, damaged)) |_| survivors += 1 else |_| {}
        damaged[at] ^= 1;
    }
    return survivors;
}

test "a damaged record is rejected, whichever byte is damaged or wherever it is cut" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var source = sampleRecord(.{ .inline_bytes = "verdict" }, &every_read);
    source.parts = &sample_parts;
    const bytes = try encode(a, source);
    try std.testing.expectEqual(@as(usize, 0), survivingCuts(a, bytes));
    try std.testing.expectEqual(@as(usize, 0), survivingFlips(a, bytes));
    var junk: [48]u8 = @splat(0);
    @memcpy(junk[0..8], "XXXXXXXX");
    try std.testing.expectError(error.UnknownFormat, decode(a, &junk));
    try std.testing.expect(header(bytes[0..20]) == null);
}

test "a record whose trailer is right but whose fields are not is malformed, not a crash" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var body: std.ArrayList(u8) = .empty;
    try body.appendSlice(a, magic);
    try putU32(&body, a, format_version);
    try putBlock(&body, a, "kind");
    try body.appendNTimes(a, 0, 64);
    try putBlock(&body, a, "");
    try body.appendNTimes(a, 0, 32);
    try body.append(a, 7); // no payload tag 7
    const trailer = digest_rules.hash(body.items);
    try body.appendSlice(a, &trailer);
    try std.testing.expectError(error.Malformed, decode(a, body.items));
}

test "a format 1 record is still read, with no parts, and writes the bytes it had" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const old = try encodeFormat(a, sampleRecord(.{ .inline_bytes = "verdict" }, format_one_reads), 1);
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, old[magic.len..][0..4], .little));
    const back = try decode(a, old);
    try std.testing.expectEqual(@as(usize, 0), back.parts.len);
    try std.testing.expectEqual(@as(usize, 9), back.reads.len);
    try std.testing.expectEqualSlices(u8, old, try encodeFormat(a, back, 1));
    // The current format writes the same record with an empty parts table, which is more bytes.
    const current = try encode(a, back);
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, current[magic.len..][0..4], .little));
    try std.testing.expectEqual(old.len + 4, current.len);
    try std.testing.expectEqual(header(old).?.key, header(current).?.key);
}

test "format 1 cannot express a parts table or a projection read" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var with_parts = sampleRecord(.{ .inline_bytes = "x" }, &.{});
    with_parts.parts = &sample_parts;
    try std.testing.expectError(error.NotExpressible, encodeFormat(a, with_parts, 1));
    try std.testing.expectError(error.NotExpressible, encodeFormat(a, sampleRecord(.{ .inline_bytes = "x" }, &every_read), 1));
    try std.testing.expectError(error.NotExpressible, encodeFormat(a, sampleRecord(.{ .inline_bytes = "x" }, &.{}), 3));
}

/// A record body of the given format whose reads are one block of raw bytes after a read count of one, sealed with the
/// right trailer, so a test can state a read the encoder would never write.
fn sealedWithRawRead(a: std.mem.Allocator, version: u32, raw_read: []const u8) std.mem.Allocator.Error![]u8 {
    var body: std.ArrayList(u8) = .empty;
    try body.appendSlice(a, magic);
    try putU32(&body, a, version);
    try putBlock(&body, a, "kind");
    try body.appendNTimes(a, 0, 64);
    try putBlock(&body, a, "");
    try body.appendNTimes(a, 0, 32);
    try body.append(a, 0);
    try putBlock(&body, a, "");
    if (version >= 2) try putU32(&body, a, 0);
    try putU32(&body, a, 1);
    try body.appendSlice(a, raw_read);
    const trailer = digest_rules.hash(body.items);
    try body.appendSlice(a, &trailer);
    return body.toOwnedSlice(a);
}

test "an unknown read tag, a projection read in format 1 and an unknown format are misses, not crashes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var part_read: std.ArrayList(u8) = .empty;
    try part_read.append(a, 7);
    try putBlock(&part_read, a, "k");
    try part_read.appendNTimes(a, 0, 32);
    try putU32(&part_read, a, 0);
    // A projection read is a format 2 read: it decodes there, and it does not exist in format 1.
    try std.testing.expectEqual(@as(usize, 1), (try decode(a, try sealedWithRawRead(a, 2, part_read.items))).reads.len);
    try std.testing.expectError(error.Malformed, decode(a, try sealedWithRawRead(a, 1, part_read.items)));
    // A tag no reader knows is malformed in either format.
    try std.testing.expectError(error.Malformed, decode(a, try sealedWithRawRead(a, 2, &.{8})));
    try std.testing.expectError(error.Malformed, decode(a, try sealedWithRawRead(a, 1, &.{8})));
    // A format later than this reader's is unknown, whatever its trailer.
    try std.testing.expectError(error.UnknownFormat, decode(a, try sealedWithRawRead(a, 3, &.{8})));
    try std.testing.expectError(error.UnknownFormat, decode(a, try sealedWithRawRead(a, 0, &.{8})));
}

test "a parts table or a projection read whose names are out of order or repeated is malformed" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unsorted = [_]Part{ .{ .name = "b", .digest = @splat(1) }, .{ .name = "a", .digest = @splat(2) } };
    const repeated = [_]Part{ .{ .name = "a", .digest = @splat(1) }, .{ .name = "a", .digest = @splat(2) } };
    var record = sampleRecord(.{ .inline_bytes = "x" }, &.{});
    record.parts = &unsorted;
    try std.testing.expectError(error.Malformed, decode(a, try encode(a, record)));
    record.parts = &repeated;
    try std.testing.expectError(error.Malformed, decode(a, try encode(a, record)));
    const crossed = [_]PartSight{ .{ .name = "z", .present = false, .digest = @splat(0) }, .{ .name = "a", .present = false, .digest = @splat(0) } };
    const reads = [_]Read{.{ .part = .{ .kind = "k", .key = @splat(1), .parts = &crossed } }};
    try std.testing.expectError(error.Malformed, decode(a, try encode(a, sampleRecord(.{ .inline_bytes = "x" }, &reads))));
}
