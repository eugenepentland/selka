//! Independent BLAKE3 witness for encoded settings preimages; no compiler executes.
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 2) return error.ExpectedPreimagesJson;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], a, .limited(64 << 20));
    const parsed = try std.json.parseFromSlice([]const []const u8, a, bytes, .{});
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    for (parsed.value) |encoded| {
        const preimage = try a.alloc(u8, encoded.len / 2);
        _ = try std.fmt.hexToBytes(preimage, encoded);
        var hash: [32]u8 = undefined;
        std.crypto.hash.Blake3.hash(preimage, &hash, .{});
        try out.interface.print("{s}\n", .{std.fmt.bytesToHex(hash, .lower)});
    }
    try out.interface.flush();
}
