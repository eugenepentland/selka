//! Control for the scan-floor comparison: the *same* SWAR algorithm as
//! `qbe/scan_swar.ssa`, but written in Zig and compiled by LLVM at ReleaseFast,
//! through exactly the read/print path `zig-bench --scan` uses.
//!
//! The point is to separate two things the earlier comparison confounded:
//! "QBE IR beat Zig ReleaseFast" could mean QBE generates better code, or it
//! could mean the hand-written IR was given a better algorithm (SWAR) than the
//! byte-at-a-time loop in `zig-bench`. With the algorithm held equal and the
//! runtime held equal, this file answers the codegen question.
//!
//! Build: zig build-exe -OReleaseFast -femit-bin=zig-scan-swar scan_swar.zig

const std = @import("std");

const mask_fe: u64 = 0xFEFEFEFEFEFEFEFE;
const c28: u64 = 0x2828282828282828;
const c7f: u64 = 0x7F7F7F7F7F7F7F7F;
const c80: u64 = 0x8080808080808080;
const c01: u64 = 0x0101010101010101;

/// Count '(' and ')' eight bytes at a time. `(` and `)` are 0x28/0x29, so
/// masking bit 0 collapses both into one comparison; zero bytes are then counted
/// exactly and summed with a multiply.
fn scan(source: []const u8) u64 {
    var count: u64 = 0;
    const words = source.len / 8;
    var i: usize = 0;
    while (i < words) : (i += 1) {
        const word = @as(*align(1) const u64, @ptrCast(source.ptr + i * 8)).*;
        const x = (word & mask_fe) ^ c28;
        const a = x & c7f;
        const b = a +% c7f;
        const nz = b | x;
        const zf = ~nz & c80;
        const bits = zf >> 7;
        count += (bits *% c01) >> 56;
    }
    var j = words * 8;
    while (j < source.len) : (j += 1) {
        const byte = source[j];
        if (byte == '(' or byte == ')') count += 1;
    }
    return count;
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) std.process.exit(2);
    const source = std.Io.Dir.cwd().readFileAlloc(
        init.io, args[1], arena, .limited64(256 * 1024 * 1024)) catch std.process.exit(2);
    var buffer: [64]u8 = undefined;
    const line = try std.fmt.bufPrint(
        &buffer, "bytes={d} delims={d}\n", .{ source.len, scan(source) });
    try std.Io.File.stdout().writeStreamingAll(init.io, line);
}
