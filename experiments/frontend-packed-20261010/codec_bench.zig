const std = @import("std");
const flate = std.compress.flate;
extern "c" fn ZSTD_compressBound(usize) usize;
extern "c" fn ZSTD_compress(?*anyopaque, usize, ?*const anyopaque, usize, c_int) usize;
extern "c" fn ZSTD_decompress(?*anyopaque, usize, ?*const anyopaque, usize) usize;
extern "c" fn ZSTD_isError(usize) c_uint;
const Timespec = extern struct { seconds: isize, nanoseconds: isize };
extern "c" fn clock_gettime(c_int, *Timespec) c_int;
fn now() u64 {
    var t: Timespec = undefined;
    std.debug.assert(clock_gettime(1, &t) == 0);
    return @as(u64, @intCast(t.seconds)) * 1000000000 + @as(u64, @intCast(t.nanoseconds));
}
const Frame = struct { raw: []const u8, deflate: []const u8, zstd: []const u8 };
fn compressDeflate(a: std.mem.Allocator, raw: []const u8) ![]u8 {
    var output = try std.Io.Writer.Allocating.initCapacity(a, raw.len + 1024);
    defer output.deinit();
    var window: [flate.max_window_len]u8 = undefined;
    var compressor = try flate.Compress.init(&output.writer, &window, .raw, .fastest);
    try compressor.writer.writeAll(raw);
    try compressor.finish();
    return output.toOwnedSlice();
}
fn decompressDeflate(encoded: []const u8, output: []u8) !void {
    var input = std.Io.Reader.fixed(encoded);
    var window: [flate.max_window_len]u8 = undefined;
    var decoder = flate.Decompress.init(&input, .raw, &window);
    try decoder.reader.readSliceAll(output);
}
fn decode(frame: Frame, deflate: bool, output: []u8) !void {
    const dst = output[0..frame.raw.len];
    if (deflate) try decompressDeflate(frame.deflate, dst) else {
        const n = ZSTD_decompress(dst.ptr, dst.len, frame.zstd.ptr, frame.zstd.len);
        if (ZSTD_isError(n) != 0 or n != dst.len) return error.InvalidZstd;
    }
}
fn randomDecode(a: std.mem.Allocator, frames: []const Frame, deflate: bool, output: []u8, allocating: bool) !struct { ns: u64, bytes: u64, checksum: u64 } {
    var seed: u64 = 1701;
    var bytes: u64 = 0;
    var checksum: u64 = 0;
    const start = now();
    for (0..2000) |_| {
        seed = seed *% 6364136223846793005 +% 1442695040888963407;
        const frame = frames[seed % frames.len];
        const dst = if (allocating) try a.alloc(u8, frame.raw.len) else output;
        try decode(frame, deflate, dst);
        checksum +%= dst[frame.raw.len / 2];
        bytes += frame.raw.len;
        if (allocating) a.free(dst);
    }
    return .{ .ns = now() - start, .bytes = bytes, .checksum = checksum };
}
pub fn main(init: std.process.Init) !void {
    const a = std.heap.c_allocator;
    var arg_arena = std.heap.ArenaAllocator.init(a);
    defer arg_arena.deinit();
    const args = try init.minimal.args.toSlice(arg_arena.allocator());
    const corpus = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], a, .unlimited);
    defer a.free(corpus);
    var frames: std.ArrayList(Frame) = .empty;
    defer frames.deinit(a);
    var pos: usize = 0;
    var raw_bytes: usize = 0;
    var deflate_bytes: usize = 0;
    var zstd_bytes: usize = 0;
    var deflate_compress_ns: u64 = 0;
    var zstd_compress_ns: u64 = 0;
    var largest: usize = 0;
    while (pos < corpus.len) {
        const n = std.mem.readInt(u64, corpus[pos..][0..8], .little);
        pos += 8;
        const raw = corpus[pos..][0..n];
        pos += n;
        const ds = now();
        const d = try compressDeflate(a, raw);
        deflate_compress_ns += now() - ds;
        const z = try a.alloc(u8, ZSTD_compressBound(n));
        const zs = now();
        const zn = ZSTD_compress(z.ptr, z.len, raw.ptr, raw.len, 1);
        zstd_compress_ns += now() - zs;
        if (ZSTD_isError(zn) != 0) return error.InvalidZstd;
        try frames.append(a, .{ .raw = raw, .deflate = d, .zstd = z[0..zn] });
        raw_bytes += n;
        deflate_bytes += d.len;
        zstd_bytes += zn;
        largest = @max(largest, n);
    }
    const output = try a.alloc(u8, largest);
    defer a.free(output);
    var sequential: [2]u64 = @splat(0);
    for ([_]bool{ true, false }, 0..) |deflate, i| {
        const start = now();
        for (frames.items) |frame| {
            try decode(frame, deflate, output);
            if (!std.mem.eql(u8, frame.raw, output[0..frame.raw.len])) return error.WrongRoundtrip;
        }
        sequential[i] = now() - start;
    }
    const dr = try randomDecode(a, frames.items, true, output, false);
    const zr = try randomDecode(a, frames.items, false, output, false);
    const da = try randomDecode(a, frames.items, true, output, true);
    const za = try randomDecode(a, frames.items, false, output, true);
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try stdout.interface.print("{{\"blocks\":{d},\"raw_bytes\":{d},\"deflate_bytes\":{d},\"zstd_bytes\":{d},\"deflate_compress_ns\":{d},\"zstd_compress_ns\":{d},\"deflate_sequential_ns\":{d},\"zstd_sequential_ns\":{d},\"random_blocks\":2000,\"random_raw_bytes\":{d},\"deflate_random_ns\":{d},\"zstd_random_ns\":{d},\"deflate_alloc_random_ns\":{d},\"zstd_alloc_random_ns\":{d},\"checksum\":{d}}}\n", .{ frames.items.len, raw_bytes, deflate_bytes, zstd_bytes, deflate_compress_ns, zstd_compress_ns, sequential[0], sequential[1], dr.bytes, dr.ns, zr.ns, da.ns, za.ns, dr.checksum +% zr.checksum +% da.checksum +% za.checksum });
    try stdout.interface.flush();
}
