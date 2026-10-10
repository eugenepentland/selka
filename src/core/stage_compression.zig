//! Portable independently bounded cache blocks; compression is never required for correctness.
const std = @import("std");
pub const Error = std.mem.Allocator.Error || error{InvalidEncoding};

/// Prefix zero preserves incompressible input; prefix one contains a zlib stream.
pub fn encode(a: std.mem.Allocator, input: []const u8) std.mem.Allocator.Error![]u8 {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const work = scratch.allocator();
    var output = std.Io.Writer.Allocating.init(work);
    output.writer.writeByte(1) catch return error.OutOfMemory;
    const compressor = try work.create(std.compress.flate.Compress);
    compressor.* = std.compress.flate.Compress.init(&output.writer, try work.alloc(u8, std.compress.flate.max_window_len), .zlib, .fastest) catch return error.OutOfMemory;
    compressor.writer.writeAll(input) catch return error.OutOfMemory;
    compressor.finish() catch return error.OutOfMemory;
    if (output.written().len < input.len + 1) return a.dupe(u8, output.written());
    const raw = try a.alloc(u8, input.len + 1);
    raw[0] = 0;
    @memcpy(raw[1..], input);
    return raw;
}

/// Decode exactly the admitted size, rejecting short, oversized or trailing streams.
pub fn decode(a: std.mem.Allocator, input: []const u8, size: usize) Error![]u8 {
    if (input.len == 0) return error.InvalidEncoding;
    if (input[0] == 0) {
        if (input.len - 1 != size) return error.InvalidEncoding;
        return a.dupe(u8, input[1..]);
    }
    if (input[0] != 1) return error.InvalidEncoding;
    // streamRemaining uses the direct writer path. readSliceAll instead routes
    // through readVec, which requires a separate full history window.
    const capacity = std.math.add(usize, size, 258) catch return error.InvalidEncoding;
    const output = try a.alloc(u8, capacity);
    errdefer a.free(output);
    var reader = std.Io.Reader.fixed(input[1..]);
    var writer = std.Io.Writer.fixed(output);
    var decoder = std.compress.flate.Decompress.init(&reader, .zlib, &.{});
    const decoded = decoder.reader.streamRemaining(&writer) catch return error.InvalidEncoding;
    if (decoded != size or reader.seek != reader.end) return error.InvalidEncoding;
    if (a.resize(output, size)) return output[0..size];
    const exact = try a.dupe(u8, output[0..size]);
    a.free(output);
    return exact;
}
