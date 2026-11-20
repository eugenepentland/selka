//! The boot stages the compiler holds (MCU-NOC4A): the bytes a chip's ROM loads first, which a device's `boot` key names.
//!
//! A stage is its code, at most 252 bytes, and the compiler seals it: the code padded with zeros to 252 bytes and followed by
//! its CRC-32/MPEG-2 (polynomial 0x04c11db7, initial value 0xffffffff, no reflection, no final xor), little endian, the 256 bytes
//! the RP2040's boot ROM accepts (datasheet 2.8.1.3.1). The same bytes `tools/boot2.py seal` makes in selka-rp.
const std = @import("std");

/// The size of a sealed stage: the code's 252 bytes and the 4 bytes of its checksum.
pub const sealed_size = 256;
/// The most code a stage may hold: what fits before the checksum.
pub const code_size = sealed_size - 4;

/// The name of the RP2040's stage: it sets up execute-in-place with the serial read command 03h (one data line, a 24-bit
/// address, no dummy cycles) and starts the image at 0x10000100 the way a Cortex-M0+ starts.
pub const rp2040_read_03h = "rp2040-read-03h";

/// The names of the stages the compiler holds, as a refusal lists them.
pub const names_text = rp2040_read_03h;

/// The RP2040 stage's code. Source: selka-rp `bringup/selka-flash/boot2.S` (sha256
/// a7ca966439b2915db2ae6d3b210d84bea4fb93f20c6329f8fbfa9ad2b6c3ef24, selka-rp commit aefa45c, 19 November 2026), assembled with
/// `zig cc -target thumb-freestanding-eabi -mcpu=cortex_m0plus -c boot2.S` and `zig objcopy -O binary --only-section=.boot2`
/// (76 bytes). Its words: push {lr}; SSIENR = 0; BAUDR = 4; CTRLR0 = 0x001f0300; CTRLR1 = 0; SPI_CTRLR0 = 0x03000218; SSIENR = 1;
/// pop; return when called from code; else VTOR = 0x10000100, MSP = word 0 of the table, jump to word 1.
const rp2040_read_03h_code = [_]u8{
    0x00, 0xb5, 0x0c, 0x4b, 0x00, 0x21, 0x99, 0x60, 0x04, 0x21, 0x59, 0x61,
    0x0a, 0x49, 0x19, 0x60, 0x00, 0x21, 0x59, 0x60, 0x09, 0x49, 0x0a, 0x48,
    0x01, 0x60, 0x01, 0x21, 0x99, 0x60, 0x01, 0xbc, 0x00, 0x28, 0x00, 0xd0,
    0x00, 0x47, 0x07, 0x48, 0x07, 0x49, 0x08, 0x60, 0x03, 0xc8, 0x80, 0xf3,
    0x08, 0x88, 0x08, 0x47, 0x00, 0x00, 0x00, 0x18, 0x00, 0x03, 0x1f, 0x00,
    0x18, 0x02, 0x00, 0x03, 0xf4, 0x00, 0x00, 0x18, 0x00, 0x01, 0x00, 0x10,
    0x08, 0xed, 0x00, 0xe0,
};

/// The code of the stage `name`, or null when the compiler holds none of that name.
pub fn code(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, rp2040_read_03h)) return &rp2040_read_03h_code;
    return null;
}

/// The CRC-32/MPEG-2 of `bytes`.
pub fn crc32Mpeg2(bytes: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;
    for (bytes) |byte| {
        crc ^= @as(u32, byte) << 24;
        for (0..8) |_| crc = if (crc & 0x80000000 != 0) (crc << 1) ^ 0x04C11DB7 else crc << 1;
    }
    return crc;
}

/// The sealed 256 bytes of a stage whose code is `stage_code` (at most `code_size` bytes).
pub fn seal(stage_code: []const u8) [sealed_size]u8 {
    std.debug.assert(stage_code.len <= code_size);
    var sealed: [sealed_size]u8 = @splat(0);
    @memcpy(sealed[0..stage_code.len], stage_code);
    std.mem.writeInt(u32, sealed[code_size..][0..4], crc32Mpeg2(sealed[0..code_size]), .little);
    return sealed;
}

test "the CRC-32/MPEG-2 check value of the nine digits is the catalogue's" {
    try std.testing.expectEqual(@as(u32, 0x0376E6E7), crc32Mpeg2("123456789"));
}

test "the RP2040 stage seals to the 256 bytes tools/boot2.py seal makes: 76 bytes of code, zeros, and crc 0xe11ef9df" {
    const stage = code(rp2040_read_03h).?;
    try std.testing.expectEqual(@as(usize, 76), stage.len);
    const sealed = seal(stage);
    try std.testing.expectEqualSlices(u8, stage, sealed[0..stage.len]);
    for (sealed[stage.len..code_size]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
    try std.testing.expectEqual(@as(u32, 0xe11ef9df), std.mem.readInt(u32, sealed[code_size..][0..4], .little));
    // The checksum covers the first 252 bytes: the ROM accepts the block.
    try std.testing.expectEqual(crc32Mpeg2(sealed[0..code_size]), std.mem.readInt(u32, sealed[code_size..][0..4], .little));
}

test "an unknown stage name holds no code" {
    try std.testing.expect(code("rp2350") == null);
    try std.testing.expect(code("") == null);
}
