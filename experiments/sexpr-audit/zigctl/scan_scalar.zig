//! Control for the scan-floor comparison: the byte-at-a-time loop `zig-bench
//! --scan` runs, but as a standalone root so its code can be disassembled
//! without the rest of zig-bench. Same read/print path as `scan_swar.zig`, so
//! the two differ only in the loop and the compiler sees both.
//!
//! Build: zig build-exe -OReleaseFast -femit-bin=zig-scan-scalar scan_scalar.zig

const std = @import("std");

fn scan(source: []const u8) u64 {
    var count: u64 = 0;
    var index: usize = 0;
    while (index < source.len) : (index += 1) {
        if (source[index] == '(' or source[index] == ')') count += 1;
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
