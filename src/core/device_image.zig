//! The image a bare build writes (MCU-C1): the linked ELF as it is, its raw bytes (`.bin`, what `objcopy -O binary`
//! gives: every allocated section with contents, placed at its load address from the lowest one, the gaps zero), or the
//! UF2 form of those bytes (`.uf2`: 512-byte blocks of 256 payload bytes, each with its address and the family id).
//! The compiler writes them itself, with no other program.
const std = @import("std");

/// The form of a bare build's output.
pub const Form = enum { elf, bin, uf2 };

/// The form the output's name asks for (`.elf`, `.bin`, `.uf2`), else `fallback` (a device's `image`).
pub fn formOf(output: []const u8, fallback: Form) Form {
    const extension = std.fs.path.extension(output);
    if (extension.len < 2) return fallback;
    return std.meta.stringToEnum(Form, extension[1..]) orelse fallback;
}

/// The bytes of a raw image and the load address of its first byte.
pub const Raw = struct { bytes: []u8, base: u32 };

/// Why an ELF has no raw image: it is not a 32-bit little-endian ELF, a header points outside the file, it has no
/// allocated section with contents, or its sections span more than `max_image_bytes`.
pub const ImageError = error{ NotElf32, Truncated, Empty, TooLarge, OutOfMemory };

/// The largest raw image the compiler writes: QEMU's layout (a vector table at 0, the rest at 0x20000000) would be 512 MiB
/// of zeros.
pub const max_image_bytes: u64 = 1 << 28;

/// One allocated section with contents: where its bytes are in the file, and the segment that loads it.
const Section = struct { offset: u32, size: u32, segment: ?usize = null };
/// One loadable segment: its file offset and size, and its load (physical) address.
const Segment = struct { offset: u32, size: u32, paddr: u32 };

fn word(bytes: []const u8, at: usize) ImageError!u32 {
    if (at + 4 > bytes.len) return error.Truncated;
    return std.mem.readInt(u32, bytes[at..][0..4], .little);
}

fn half(bytes: []const u8, at: usize) ImageError!u16 {
    if (at + 2 > bytes.len) return error.Truncated;
    return std.mem.readInt(u16, bytes[at..][0..2], .little);
}

/// The raw image of the ELF `elf`, as `zig objcopy -O binary` lays it out: each section that is allocated and not
/// `SHT_NOBITS` goes at its offset in the segment of lowest file offset that holds it, from the load address of the
/// first such section of the lowest-addressed segment.
pub fn raw(allocator: std.mem.Allocator, elf: []const u8) ImageError!Raw {
    if (elf.len < 52 or !std.mem.eql(u8, elf[0..4], "\x7fELF")) return error.NotElf32;
    const class_32 = 1;
    const little_endian = 1;
    if (elf[4] != class_32 or elf[5] != little_endian) return error.NotElf32;
    const sections = try readSections(allocator, elf);
    defer allocator.free(sections);
    const segments = try readSegments(allocator, elf);
    defer allocator.free(segments);
    for (sections) |*section| for (segments, 0..) |segment, index| {
        const segment_end = @as(u64, segment.offset) + segment.size;
        if (segment.offset > section.offset or segment_end < @as(u64, section.offset) + section.size) continue;
        if (section.segment) |held| if (segments[held].offset <= segment.offset) continue;
        section.segment = index;
    };
    // The lowest-addressed segment that holds a section sets the base: the address of its first section's bytes.
    var base_segment: ?usize = null;
    for (segments, 0..) |segment, index| {
        if (firstSection(sections, index) == null) continue;
        if (base_segment == null or segment.paddr < segments[base_segment.?].paddr) base_segment = index;
    }
    const based = base_segment orelse return error.Empty;
    const first = sections[firstSection(sections, based).?];
    const base = segments[based].paddr + (first.offset - segments[based].offset);
    var length: u64 = 0;
    for (sections) |section| length = @max(length, try placeOf(section, segments, base) + section.size);
    if (length > max_image_bytes) return error.TooLarge;
    const bytes = try allocator.alloc(u8, @intCast(length));
    @memset(bytes, 0);
    for (sections) |section| {
        const at: usize = @intCast(try placeOf(section, segments, base));
        @memcpy(bytes[at..][0..section.size], elf[section.offset..][0..section.size]);
    }
    return .{ .bytes = bytes, .base = base };
}

/// Where `section`'s bytes go in the image whose first byte loads at `base`; a section no segment holds goes at 0, as
/// `zig objcopy` places it.
fn placeOf(section: Section, segments: []const Segment, base: u32) ImageError!u64 {
    const index = section.segment orelse return 0;
    const segment = segments[index];
    const address = @as(u64, segment.paddr) + (section.offset - segment.offset);
    if (address < base) return error.Truncated;
    return address - base;
}

/// The section of lowest file offset that `segment` holds (the first `zig objcopy` assigns it), or null.
fn firstSection(sections: []const Section, segment: usize) ?usize {
    var found: ?usize = null;
    for (sections, 0..) |section, index| {
        if (section.segment != segment) continue;
        if (found == null or section.offset < sections[found.?].offset) found = index;
    }
    return found;
}

fn readSections(allocator: std.mem.Allocator, elf: []const u8) ImageError![]Section {
    const table = try word(elf, 32);
    const entry = try half(elf, 46);
    const count = try half(elf, 48);
    var list: std.ArrayList(Section) = .empty;
    errdefer list.deinit(allocator);
    for (0..count) |index| {
        const header = @as(usize, table) + index * entry;
        const kind = try word(elf, header + 4);
        const flags = try word(elf, header + 8);
        const offset = try word(elf, header + 16);
        const size = try word(elf, header + 20);
        const nobits = 8;
        const alloc_flag = 2;
        if (kind == nobits or flags & alloc_flag == 0 or size == 0) continue;
        if (@as(u64, offset) + size > elf.len) return error.Truncated;
        try list.append(allocator, .{ .offset = offset, .size = size });
    }
    return list.toOwnedSlice(allocator);
}

fn readSegments(allocator: std.mem.Allocator, elf: []const u8) ImageError![]Segment {
    const table = try word(elf, 28);
    const entry = try half(elf, 42);
    const count = try half(elf, 44);
    var list: std.ArrayList(Segment) = .empty;
    errdefer list.deinit(allocator);
    for (0..count) |index| {
        const header = @as(usize, table) + index * entry;
        const load = 1;
        if (try word(elf, header) != load) continue;
        try list.append(allocator, .{ .offset = try word(elf, header + 4), .size = try word(elf, header + 16), .paddr = try word(elf, header + 12) });
    }
    return list.toOwnedSlice(allocator);
}

/// The UF2 block's magic numbers and the flag that says a family id is present.
pub const uf2_magic_start0: u32 = 0x0A324655;
pub const uf2_magic_start1: u32 = 0x9E5D5157;
pub const uf2_magic_end: u32 = 0x0AB16F30;
pub const uf2_family_present: u32 = 0x00002000;
/// Payload bytes in each 512-byte UF2 block.
pub const uf2_payload: usize = 256;

/// The UF2 form of `image` with the family id `family`: one 512-byte block for each 256 bytes, the last one padded with
/// zeros, each block naming its address (`image.base` onward), its number, the block count and the family.
pub fn uf2(allocator: std.mem.Allocator, image: Raw, family: u32) error{OutOfMemory}![]u8 {
    const count = @max(1, (image.bytes.len + uf2_payload - 1) / uf2_payload);
    const out = try allocator.alloc(u8, count * 512);
    @memset(out, 0);
    for (0..count) |index| {
        const block = out[index * 512 ..][0..512];
        const fields = [_]u32{ uf2_magic_start0, uf2_magic_start1, uf2_family_present, image.base + @as(u32, @intCast(index * uf2_payload)), uf2_payload, @intCast(index), @intCast(count), family };
        for (fields, 0..) |value, at| std.mem.writeInt(u32, block[at * 4 ..][0..4], value, .little);
        const start = index * uf2_payload;
        const end = @min(image.bytes.len, start + uf2_payload);
        if (start < end) @memcpy(block[32..][0 .. end - start], image.bytes[start..end]);
        std.mem.writeInt(u32, block[508..][0..4], uf2_magic_end, .little);
    }
    return out;
}

/// Why `rewrite` made no image: the ELF has none (`ImageError`), it cannot be read or the image written, or a `.uf2`
/// was asked for with no family id.
pub const RewriteError = ImageError || error{ ReadFailed, WriteFailed, NoFamily };

/// Replace the ELF at `path` with the image `form` asks for (nothing for `.elf`); when it has none, remove it. The new bytes go to a file beside it
/// that is then renamed over it, so a name the build linked to a stored program never writes into the store.
pub fn rewrite(allocator: std.mem.Allocator, io: std.Io, path: []const u8, form: Form, family: ?u32) RewriteError!void {
    if (form == .elf) return;
    const uf2_family = if (form == .uf2) family orelse return error.NoFamily else 0;
    const cwd = std.Io.Dir.cwd();
    // An output that cannot become the image it is named for is removed: an ELF under a `.bin` name would mislead.
    errdefer removeOutput(io, path);
    const elf = cwd.readFileAlloc(io, path, allocator, .limited(1 << 28)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.ReadFailed;
    defer allocator.free(elf);
    const image = try raw(allocator, elf);
    defer allocator.free(image.bytes);
    const bytes = if (form == .uf2) try uf2(allocator, image, uf2_family) else image.bytes;
    defer if (form == .uf2) allocator.free(bytes);
    const temporary = try std.fmt.allocPrint(allocator, "{s}.image-tmp", .{path});
    defer allocator.free(temporary);
    cwd.writeFile(io, .{ .sub_path = temporary, .data = bytes }) catch return error.WriteFailed;
    cwd.rename(temporary, cwd, path, io) catch return error.WriteFailed;
}

/// Remove the output a failed `rewrite` leaves. One already gone needs nothing; one that cannot be removed is still
/// named by the build's refusal, which ends with status 2.
fn removeOutput(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(io, path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => {},
    };
}

test "an output's name chooses its image form, else the device's" {
    try std.testing.expectEqual(Form.bin, formOf("out/blink.bin", .elf));
    try std.testing.expectEqual(Form.uf2, formOf("blink.uf2", .bin));
    try std.testing.expectEqual(Form.elf, formOf("blink.elf", .uf2));
    try std.testing.expectEqual(Form.uf2, formOf("blink", .uf2));
}

/// A 32-bit ELF with two loadable sections, each in a segment of its own, at load addresses 0x10000000 and `second`
/// (0x10000010: a gap of 12 bytes), and a `.bss` that has no contents.
fn sampleElf(allocator: std.mem.Allocator, second: u32) ![]u8 {
    const elf = try allocator.alloc(u8, 0x200);
    @memset(elf, 0);
    @memcpy(elf[0..6], "\x7fELF\x01\x01");
    const put = struct {
        fn at(bytes: []u8, offset: usize, value: u32) void {
            std.mem.writeInt(u32, bytes[offset..][0..4], value, .little);
        }
        fn short(bytes: []u8, offset: usize, value: u16) void {
            std.mem.writeInt(u16, bytes[offset..][0..2], value, .little);
        }
    };
    put.at(elf, 28, 0x40); // program headers
    put.short(elf, 42, 32);
    put.short(elf, 44, 2);
    put.at(elf, 32, 0x100); // section headers
    put.short(elf, 46, 40);
    put.short(elf, 48, 4);
    // Two PT_LOADs: file 0x80..0x90 at paddr 0x10000000 and 0x90..0xa0 at `second` (vaddrs differ, as a RAM copy's would).
    for ([_]u32{ 1, 0x80, 0x20000000, 0x10000000, 0x10, 0x10, 0, 0, 1, 0x90, 0x20000010, second, 0x10, 0x10 }, 0..) |value, index| put.at(elf, 0x40 + index * 4, value);
    // Section 1: .text, 4 bytes at 0x80; section 2: .data, 4 bytes at 0x90; section 3: .bss (NOBITS).
    for ([_][3]u32{ .{ 1, 0x80, 4 }, .{ 1, 0x90, 4 }, .{ 8, 0xa0, 64 } }, 1..) |section, index| {
        const header = 0x100 + index * 40;
        put.at(elf, header + 4, section[0]);
        put.at(elf, header + 8, 2); // SHF_ALLOC
        put.at(elf, header + 16, section[1]);
        put.at(elf, header + 20, section[2]);
    }
    @memcpy(elf[0x80..0x84], "TEXT");
    @memcpy(elf[0x90..0x94], "DATA");
    return elf;
}

test "a raw image places each allocated section at its load address and fills the gaps with zeros" {
    const elf = try sampleElf(std.testing.allocator, 0x10000010);
    defer std.testing.allocator.free(elf);
    const image = try raw(std.testing.allocator, elf);
    defer std.testing.allocator.free(image.bytes);
    try std.testing.expectEqual(@as(u32, 0x10000000), image.base);
    try std.testing.expectEqualSlices(u8, "TEXT\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00DATA", image.bytes);
    try std.testing.expectError(error.NotElf32, raw(std.testing.allocator, "not an elf"));
}

test "a raw image refuses sections that span more than max_image_bytes, an ELF with none, and one cut short" {
    const far = try sampleElf(std.testing.allocator, 0x10000000 + @as(u32, @intCast(max_image_bytes)));
    defer std.testing.allocator.free(far);
    try std.testing.expectError(error.TooLarge, raw(std.testing.allocator, far));
    const none = try sampleElf(std.testing.allocator, 0x10000010);
    defer std.testing.allocator.free(none);
    std.mem.writeInt(u16, none[48..50], 0, .little); // no section headers
    try std.testing.expectError(error.Empty, raw(std.testing.allocator, none));
    try std.testing.expectError(error.Truncated, raw(std.testing.allocator, far[0..0x110]));
}

test "readSections and readSegments refuse a header table that runs past the end of the file" {
    const elf = try sampleElf(std.testing.allocator, 0x10000010);
    defer std.testing.allocator.free(elf);
    try std.testing.expectError(error.Truncated, readSections(std.testing.allocator, elf[0..0x140]));
    try std.testing.expectError(error.Truncated, readSegments(std.testing.allocator, elf[0..0x60]));
    const segments = try readSegments(std.testing.allocator, elf);
    defer std.testing.allocator.free(segments);
    try std.testing.expectEqual(@as(usize, 2), segments.len);
}

test "rewrite replaces an ELF with its raw image or its UF2 form, and refuses what is not an ELF or a UF2 with no family" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const elf = try sampleElf(std.testing.allocator, 0x10000010);
    defer std.testing.allocator.free(elf);
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "prog.bin", .data = elf });
    const path = try temp.dir.realPathFileAlloc(std.testing.io, "prog.bin", std.testing.allocator);
    defer std.testing.allocator.free(path);
    try std.testing.expectError(error.NoFamily, rewrite(std.testing.allocator, std.testing.io, path, .uf2, null));
    try rewrite(std.testing.allocator, std.testing.io, path, .bin, null);
    const written = try temp.dir.readFileAlloc(std.testing.io, "prog.bin", std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(written);
    try std.testing.expectEqual(@as(usize, 20), written.len);
    try std.testing.expectError(error.NotElf32, rewrite(std.testing.allocator, std.testing.io, path, .bin, null));
    try std.testing.expectError(error.FileNotFound, temp.dir.access(std.testing.io, "prog.bin", .{}));
    try std.testing.expectError(error.ReadFailed, rewrite(std.testing.allocator, std.testing.io, "/nonexistent/prog.bin", .bin, null));
}

/// 300 bytes that count up from 0 (`@truncate`d to a byte).
fn countingBytes() [300]u8 {
    var bytes: [300]u8 = undefined;
    for (&bytes, 0..) |*byte, index| byte.* = @truncate(index);
    return bytes;
}

test "a UF2 image holds 256 payload bytes a block, with addresses, block numbers, the family and the magic numbers" {
    var payload = countingBytes();
    const out = try uf2(std.testing.allocator, .{ .bytes = &payload, .base = 0x20000000 }, 0xe48bff56);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(@as(usize, 1024), out.len);
    for (0..2) |index| {
        const block = out[index * 512 ..][0..512];
        try std.testing.expectEqual(uf2_magic_start0, std.mem.readInt(u32, block[0..4], .little));
        try std.testing.expectEqual(uf2_magic_start1, std.mem.readInt(u32, block[4..8], .little));
        try std.testing.expectEqual(@as(u32, 0x20000000 + 256 * @as(u32, @intCast(index))), std.mem.readInt(u32, block[12..16], .little));
        try std.testing.expectEqual(@as(u32, @intCast(index)), std.mem.readInt(u32, block[20..24], .little));
        try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, block[24..28], .little));
        try std.testing.expectEqual(@as(u32, 0xe48bff56), std.mem.readInt(u32, block[28..32], .little));
        try std.testing.expectEqual(uf2_magic_end, std.mem.readInt(u32, block[508..512], .little));
    }
    // The second block carries bytes 256 to 299 (`@truncate`d: 0 to 43), then zeros.
    try std.testing.expectEqual(@as(u8, 43), out[512 + 32 + 43]);
    try std.testing.expectEqual(@as(u8, 0), out[512 + 32 + 44]);
}
