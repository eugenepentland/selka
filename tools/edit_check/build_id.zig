//! The GNU build id of an amd64 ELF executable, read from its note segments. The coverage
//! runtime reads its own program headers in memory and writes the id into each `.cov`
//! file; the map tool reads a file's id to find the instrumented binary a process ran from
//! when that copy is gone (a test copies the compiler into a scratch tree it then deletes).
//! A copy of a binary shares its build id, so the id names the binary's code.
const std = @import("std");

/// The program header type of a note segment (`PT_NOTE`).
pub const pt_note: u32 = 4;
/// The note type of a GNU build id (`NT_GNU_BUILD_ID`).
pub const nt_gnu_build_id: u32 = 3;
/// Longest build id a caller needs room for (the SHA-1 and the 8-byte fast ids both fit).
pub const max_length = 64;
/// Size of an ELF64 program header entry.
const phdr_size = 56;

/// Copies the description of the first GNU build-id note in `notes` to `out`; its length, or 0 when there is none.
pub fn noteBuildId(notes: []const u8, out: []u8) usize {
    const note_header = 12;
    var pos: usize = 0;
    while (pos + note_header <= notes.len) {
        const name_len = std.mem.readInt(u32, notes[pos..][0..4], .little);
        const desc_len = std.mem.readInt(u32, notes[pos + 4 ..][0..4], .little);
        const kind = std.mem.readInt(u32, notes[pos + 8 ..][0..4], .little);
        const name_at = pos + note_header;
        const desc_at = name_at + ((name_len + 3) & ~@as(usize, 3));
        if (desc_at > notes.len or desc_len > notes.len - desc_at) return 0;
        const is_build_id = kind == nt_gnu_build_id and name_len == 4 and std.mem.eql(u8, notes[name_at..][0..4], "GNU\x00");
        if (is_build_id and desc_len <= out.len) {
            @memcpy(out[0..desc_len], notes[desc_at..][0..desc_len]);
            return desc_len;
        }
        pos = desc_at + ((desc_len + 3) & ~@as(usize, 3));
    }
    return 0;
}

/// Copies the build id of the ELF64 file `bytes` to `out`; its length, or 0 when the file has none.
pub fn fileBuildId(bytes: []const u8, out: []u8) usize {
    if (bytes.len < 64 or !std.mem.eql(u8, bytes[0..4], "\x7fELF") or bytes[4] != 2) return 0;
    const phoff = std.mem.readInt(u64, bytes[32..40], .little);
    const phnum = std.mem.readInt(u16, bytes[56..58], .little);
    for (0..phnum) |index| {
        const at = phoff + index * phdr_size;
        if (at > bytes.len or phdr_size > bytes.len - at) break;
        const header = bytes[@intCast(at)..][0..phdr_size];
        if (std.mem.readInt(u32, header[0..4], .little) != pt_note) continue;
        const offset = std.mem.readInt(u64, header[8..16], .little);
        const size = std.mem.readInt(u64, header[32..40], .little);
        if (offset > bytes.len or size > bytes.len - offset) continue;
        const length = noteBuildId(bytes[@intCast(offset)..][0..@intCast(size)], out);
        if (length != 0) return length;
    }
    return 0;
}

test "a build id note is copied out, and a note of another kind is skipped" {
    const notes = "\x04\x00\x00\x00\x02\x00\x00\x00\x01\x00\x00\x00GNU\x00ab\x00\x00" ++
        "\x04\x00\x00\x00\x04\x00\x00\x00\x03\x00\x00\x00GNU\x00\x01\x02\x03\x04";
    var out: [64]u8 = undefined;
    const length = noteBuildId(notes, &out);
    try std.testing.expectEqual(@as(usize, 4), length);
    try std.testing.expectEqualSlices(u8, "\x01\x02\x03\x04", out[0..length]);
}

test "a file's build id is found in its note segment" {
    var file: [140]u8 = @splat(0);
    @memcpy(file[0..4], "\x7fELF");
    file[4] = 2;
    std.mem.writeInt(u64, file[32..40], 64, .little);
    std.mem.writeInt(u16, file[56..58], 1, .little);
    std.mem.writeInt(u32, file[64..68], pt_note, .little);
    std.mem.writeInt(u64, file[72..80], 120, .little);
    std.mem.writeInt(u64, file[96..104], 20, .little);
    @memcpy(file[120..140], "\x04\x00\x00\x00\x04\x00\x00\x00\x03\x00\x00\x00GNU\x00\x01\x02\x03\x04");
    var out: [64]u8 = undefined;
    const length = fileBuildId(&file, &out);
    try std.testing.expectEqual(@as(usize, 4), length);
    try std.testing.expectEqualSlices(u8, "\x01\x02\x03\x04", out[0..length]);
}

test "a note whose description runs past the segment yields no build id" {
    const notes = "\x04\x00\x00\x00\x40\x00\x00\x00\x03\x00\x00\x00GNU\x00ab";
    var out: [64]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 0), noteBuildId(notes, &out));
}
