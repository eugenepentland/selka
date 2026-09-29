//! Image-owned UTF-8 position samples, sharing the runtime's trailing-index ABI.
const std = @import("std");
/// Minimum indexed payload and scalar spacing, asserted against the C runtime.
pub const minimum = 256;
/// Scalars between two image-owned position samples.
pub const stride = 128;
/// Aligned payload storage and the sample entries a literal needs.
pub const Layout = struct { storage: usize, samples: usize };
/// Plan samples only for long non-ASCII literals whose offsets fit in u32.
pub fn layout(bytes: usize, scalars: usize, ascii: bool) ?Layout {
    if (ascii or bytes < minimum or bytes > std.math.maxInt(u32)) return null;
    return .{ .storage = (bytes + 7) & ~@as(usize, 7), .samples = if (scalars == 0) 0 else (scalars - 1) / stride };
}
/// Declare the literal's read-only trailing table and assert its runtime offset.
pub fn declaration(w: *std.Io.Writer, symbol: []const u8, plan: Layout) std.Io.Writer.Error!void {
    try w.print("typedef struct {{ myl_native_object header; myl_native_text value; unsigned char storage[{d}];\n", .{plan.storage});
    try w.print(" const struct {{ uint64_t scalar, octet; uint32_t sample[{d}]; }} index; }} {s}_block;\n", .{ @max(plan.samples, 1), symbol });
    try w.writeAll("_Static_assert(sizeof(myl_native_text_positions)==16, \"text index cursor ABI\");\n");
    try w.print("_Static_assert(MYL_TEXT_INDEX_MIN=={d} && MYL_TEXT_SAMPLE_STRIDE=={d}, \"text index spacing ABI\");\n", .{ minimum, stride });
    try w.print("_Static_assert(offsetof({s}_block,index)-offsetof({s}_block,value)==sizeof(myl_native_text)+{d}, \"text index offset ABI\");\n", .{ symbol, symbol, plan.storage });
}
/// Fill the immutable table in one pass over the literal's encoded UTF-8 octets.
pub fn initializer(w: *std.Io.Writer, hex: []const u8, plan: Layout) std.Io.Writer.Error!void {
    try w.writeAll(" .index = {.scalar=0, .octet=0, .sample={");
    if (plan.samples == 0) try w.writeAll("0");
    var scalar: usize = 0;
    var sample: usize = 0;
    var at: usize = 0;
    while (at + 1 < hex.len) : (at += 2) {
        const high = std.fmt.charToDigit(hex[at], 16) catch 0;
        const low = std.fmt.charToDigit(hex[at + 1], 16) catch 0;
        if ((high * 16 + low) & 0xc0 == 0x80) continue;
        if (scalar != 0 and scalar % stride == 0 and sample < plan.samples) {
            try w.print("{d},", .{at / 2});
            sample += 1;
        }
        scalar += 1;
    }
    try w.writeAll("}},\n");
}
