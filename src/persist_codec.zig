//! Little-endian, allocation-bounded codec for plain owned frontend data.
//!
//! The persistent frontend cache stores only plain-old-data trees: every pointer
//! reachable from a serialized value must be an owned slice, never a raw pointer.
//! `write` and `read` therefore refuse (at compile time) any shape that would need
//! pointer fixups, which keeps restored values independent of the bytes they came
//! from. If a shape is ever mis-serialized a checksum check rejects the whole entry
//! and the caller falls back to fresh work; the codec itself is never trusted to
//! repair a mismatch.
const std = @import("std");

/// Malformed or truncated stored bytes; callers treat every case as a cache miss.
pub const DecodeError = error{ InvalidEncoding, Truncated, TooLarge, OutOfMemory };

/// The integrity checksum persisted beside a stored payload: the first eight
/// bytes of its BLAKE3 digest. It replaced XxHash3, whose std implementation
/// runs at about 25 MB/s on this project's hybrid build hosts' efficiency cores
/// and 370 MB/s on the performance cores; BLAKE3 hashes the same payloads at
/// more than 1 GB/s on both, and every build and check verifies each entry.
pub fn checksum(bytes: []const u8) u64 {
    var digest: [8]u8 = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    return std.mem.readInt(u64, &digest, .little);
}

/// Growable little-endian writer for one serialized value.
pub const Writer = struct {
    bytes: std.ArrayList(u8) = .empty,
    allocator: std.mem.Allocator,

    /// Create a writer that grows `bytes` with `allocator`.
    pub fn init(allocator: std.mem.Allocator) Writer {
        return .{ .allocator = allocator };
    }
    /// Release the accumulated byte buffer.
    pub fn deinit(self: *Writer) void {
        self.bytes.deinit(self.allocator);
    }
    /// Append unframed bytes; callers frame variable-length fields themselves.
    pub fn raw(self: *Writer, bytes: []const u8) std.mem.Allocator.Error!void {
        try self.bytes.appendSlice(self.allocator, bytes);
    }
    /// Append one native integer as little-endian bytes.
    pub fn integer(self: *Writer, value: anytype) std.mem.Allocator.Error!void {
        const T = @TypeOf(value);
        var little = std.mem.nativeToLittle(T, value);
        try self.raw(std.mem.asBytes(&little));
    }
    /// Encode one value; the only failure is allocation.
    pub fn write(self: *Writer, comptime T: type, value: T) std.mem.Allocator.Error!void {
        try encode(self, Unmapped, .{}, T, value);
    }
};

/// Exact-length little-endian reader; every over-read is a miss, never a panic.
pub const Reader = struct {
    bytes: []const u8,
    at: usize = 0,
    allocator: std.mem.Allocator,

    /// Create a reader over borrowed bytes; the caller keeps them alive.
    pub fn init(allocator: std.mem.Allocator, bytes: []const u8) Reader {
        return .{ .allocator = allocator, .bytes = bytes };
    }
    /// Whether every input byte was consumed; a trailing byte is corruption.
    pub fn done(self: *const Reader) bool {
        return self.at == self.bytes.len;
    }
    fn take(self: *Reader, count: usize) DecodeError![]const u8 {
        if (count > self.bytes.len - self.at) return error.Truncated;
        const out = self.bytes[self.at..][0..count];
        self.at += count;
        return out;
    }
    /// Read one little-endian native integer, or fail as truncated.
    pub fn integer(self: *Reader, comptime T: type) DecodeError!T {
        const raw = try self.take(@sizeOf(T));
        return std.mem.littleToNative(T, std.mem.bytesToValue(T, raw));
    }
    /// Decode one value; malformed or truncated bytes are `InvalidEncoding`.
    pub fn read(self: *Reader, comptime T: type) DecodeError!T {
        return decode(self, Unmapped, .{}, T) catch |err| return err;
    }
    /// Borrow the next `count` bytes; never allocates and never over-reads.
    pub fn slice(self: *Reader, count: usize) DecodeError![]const u8 {
        return self.take(count);
    }
    /// Allocate exactly `count` items with an overflow-checked byte size.
    pub fn allocate(self: *Reader, comptime T: type, count: usize) DecodeError![]T {
        return self.allocator.alloc(T, count) catch return error.OutOfMemory;
    }
    /// Readers borrow their bytes and allocator; there is no owned state to free.
    pub fn deinit(self: *Reader) void {
        _ = self;
    }
};

const Unmapped = struct {
    /// Ordinary persisted trees have no symbolic reference transformation.
    pub fn handles(comptime _: type) bool {
        return false;
    }
};

fn encode(writer: *Writer, comptime Mapping: type, mapping: Mapping, comptime T: type, value: T) std.mem.Allocator.Error!void {
    if (comptime Mapping.handles(T)) return mapping.encode(writer, T, value);
    const info = @typeInfo(T);
    switch (info) {
        .int, .comptime_int => try writer.integer(value),
        .float => {
            const bits: std.meta.Int(.unsigned, @bitSizeOf(T)) = @bitCast(value);
            try writer.integer(bits);
        },
        .bool => try writer.raw(&.{@intFromBool(value)}),
        .void => {},
        .@"enum" => try writer.integer(@as(@typeInfo(T).@"enum".tag_type, @intCast(@backingInt(value)))),
        .optional => |optional| {
            if (value) |present| {
                try writer.raw(&.{1});
                try encode(writer, Mapping, mapping, optional.child, present);
            } else try writer.raw(&.{0});
        },
        .pointer => |pointer| {
            if (pointer.size != .slice) @compileError("persisted data may only own slices, not " ++ @typeName(T));
            try writer.integer(@as(u64, value.len));
            for (value) |item| try encode(writer, Mapping, mapping, pointer.child, item);
        },
        .array => |array| for (value) |item| try encode(writer, Mapping, mapping, array.child, item),
        .@"struct" => |structure| inline for (structure.field_names, structure.field_types) |name, Field| try encode(writer, Mapping, mapping, Field, @field(value, name)),
        .@"union" => |united| {
            const tag = std.meta.activeTag(value);
            try writer.integer(@as(std.meta.Tag(T), tag));
            inline for (united.field_names, united.field_types) |name, Field| {
                if (tag == @field(std.meta.Tag(T), name)) try encode(writer, Mapping, mapping, Field, @field(value, name));
            }
        },
        else => @compileError("persisted field needs an explicit encoding rule: " ++ @typeName(T)),
    }
}

fn decode(reader: *Reader, comptime Mapping: type, mapping: Mapping, comptime T: type) DecodeError!T {
    if (comptime Mapping.handles(T)) return mapping.decode(reader, T);
    const info = @typeInfo(T);
    switch (info) {
        .int, .comptime_int => {
            if (@bitSizeOf(T) == 0) return 0;
            return reader.integer(T);
        },
        .float => {
            const bits = try reader.integer(std.meta.Int(.unsigned, @bitSizeOf(T)));
            return @bitCast(bits);
        },
        .bool => {
            const byte = (try reader.take(1))[0];
            if (byte > 1) return error.InvalidEncoding;
            return byte == 1;
        },
        .void => {},
        .@"enum" => |enumerated| {
            const Tag = enumerated.tag_type;
            // Read the tag in its full storage byte width before narrowing, so a
            // byte whose high bits are set is malformed rather than silently
            // truncated to a valid case by a sub-byte tag type.
            const Storage = @Int(.unsigned, @sizeOf(Tag) * 8);
            const raw = try reader.integer(Storage);
            const narrowed = std.math.cast(Tag, raw) orelse return error.InvalidEncoding;
            return std.enums.fromInt(T, narrowed) orelse error.InvalidEncoding;
        },
        .optional => |optional| {
            const present = (try reader.take(1))[0];
            if (present > 1) return error.InvalidEncoding;
            return if (present == 1) try decode(reader, Mapping, mapping, optional.child) else null;
        },
        .pointer => |pointer| {
            if (pointer.size != .slice) @compileError("persisted data may only own slices, not " ++ @typeName(T));
            const count = try reader.integer(u64);
            if (count > reader.bytes.len) return error.InvalidEncoding;
            const items = try reader.allocate(pointer.child, std.math.cast(usize, count) orelse return error.InvalidEncoding);
            errdefer reader.allocator.free(items);
            for (items) |*item| item.* = try decode(reader, Mapping, mapping, pointer.child);
            return items;
        },
        .array => |array| {
            var output: T = undefined;
            for (&output) |*item| item.* = try decode(reader, Mapping, mapping, array.child);
            return output;
        },
        .@"struct" => |structure| {
            var output: T = undefined;
            inline for (structure.field_names, structure.field_types) |name, Field| @field(output, name) = try decode(reader, Mapping, mapping, Field);
            return output;
        },
        .@"union" => |united| {
            const Tag = std.meta.Tag(T);
            const tag = try decode(reader, Mapping, mapping, Tag);
            inline for (united.field_names, united.field_types) |name, Field| {
                if (tag == @field(Tag, name)) return @unionInit(T, name, try decode(reader, Mapping, mapping, Field));
            }
            return error.InvalidEncoding;
        },
        else => @compileError("persisted field needs an explicit decoding rule: " ++ @typeName(T)),
    }
}

const Inner = struct { name: []const u8, flag: bool, count: u32 };
const Payload = union(enum) { none, inner: Inner, many: []const Inner };

test "codec round trips nested owned data" {
    var writer = Writer.init(std.testing.allocator);
    defer writer.deinit();
    try writer.write(Payload, .{ .many = &.{ .{ .name = "a", .flag = true, .count = 9 }, .{ .name = "bb", .flag = false, .count = 0 } } });
    var reader = Reader.init(std.testing.allocator, writer.bytes.items);
    const restored = try reader.read(Payload);
    defer freePayload(std.testing.allocator, restored);
    try std.testing.expect(reader.done());
    try std.testing.expectEqual(@as(usize, 2), restored.many.len);
    try std.testing.expectEqualStrings("bb", restored.many[1].name);
    try std.testing.expect(!restored.many[1].flag);
    try std.testing.expectEqual(@as(u32, 9), restored.many[0].count);
    try std.testing.expect(restored == .many);
}

fn freePayload(allocator: std.mem.Allocator, payload: Payload) void {
    switch (payload) {
        .many => |items| {
            for (items) |item| allocator.free(item.name);
            allocator.free(items);
        },
        else => {},
    }
}

test "codec rejects truncated and malformed bytes" {
    var writer = Writer.init(std.testing.allocator);
    defer writer.deinit();
    try writer.write([]const u16, &.{ 1, 2, 3 });
    // A truncated body and a length that exceeds the remaining bytes both miss.
    var truncated = Reader.init(std.testing.allocator, writer.bytes.items[0 .. writer.bytes.items.len - 1]);
    try std.testing.expectError(error.Truncated, truncated.read([]const u16));
    var overlong = Reader.init(std.testing.allocator, &.{0xff});
    try std.testing.expectError(error.Truncated, overlong.read([]const u16));
    // A present flag byte beyond 1, and an enum tag beyond the union's cases, are
    // malformed rather than truncated.
    var bad_option = Reader.init(std.testing.allocator, &.{2});
    try std.testing.expectError(error.InvalidEncoding, bad_option.read(?u8));
    var bad_union = Writer.init(std.testing.allocator);
    defer bad_union.deinit();
    try bad_union.integer(@as(u8, 9));
    var bad_union_reader = Reader.init(std.testing.allocator, bad_union.bytes.items);
    try std.testing.expectError(error.InvalidEncoding, bad_union_reader.read(union(enum) { a, b }));
}

// spec-case: CACHE-CHECKSUM-1
test "the payload checksum is the leading BLAKE3 bytes and sees every byte" {
    var digest: [8]u8 = undefined;
    std.crypto.hash.Blake3.hash("payload", &digest, .{});
    try std.testing.expectEqual(std.mem.readInt(u64, &digest, .little), checksum("payload"));
    try std.testing.expect(checksum("payload") != checksum("payloae"));
    try std.testing.expect(checksum("") != checksum("\x00"));
}
