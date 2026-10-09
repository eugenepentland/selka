//! Effects describe language-visible authority, not VM implementation allocation.
const std = @import("std");
pub const Mask = u16;
/// Independent capability effects tracked by source checking and interface reports.
pub const Effect = enum(u4) { filesystem, network, clock, random, environment, host, managed_allocation, output, mutation };
pub const all: Mask = 0b1_1111_1111;
/// `noio` withholds external byte streams: files, sockets and standard output.
pub const io: Mask = bit(.filesystem) | bit(.network) | bit(.output);
/// Declared allowed-effect mask and the source annotation that imposed it.
pub const Bound = struct { allowed: Mask, span: @import("source.zig").Span };
/// Full Core allocation promise is opt-in `noalloc`; legacy effects lists
/// continue to describe guest-level effects, even when allocation is omitted.
pub fn coreAllocationBound(src: @import("source.zig").Source, bound: Bound) bool {
    return std.mem.eql(u8, src.text(bound.span), "noalloc");
}

/// Return the mask bit corresponding to one effect category.
pub fn bit(effect: Effect) Mask {
    return @as(Mask, 1) << @backingInt(effect);
}
/// Write the named effects present in a mask to the supplied writer.
pub fn write(writer: *std.Io.Writer, mask: Mask) std.Io.Writer.Error!void {
    try writer.writeByte('{');
    var separator = false;
    inline for (std.meta.tags(Effect)) |effect| {
        if (mask & bit(effect) != 0) {
            if (separator) try writer.writeAll(", ");
            try writer.writeAll(@tagName(effect));
            separator = true;
        }
    }
    try writer.writeByte('}');
}
