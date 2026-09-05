//! Effects describe language-visible authority, not VM implementation allocation.
const std = @import("std");
pub const Mask = u8;
pub const Effect = enum(u3) { allocation, filesystem, network, clock, random, environment };
pub const all: Mask = 0b111111;
pub const io: Mask = bit(.filesystem) | bit(.network);
pub const Bound = struct { allowed: Mask, span: @import("source.zig").Span };
pub fn bit(effect: Effect) Mask {
    return @as(Mask, 1) << @backingInt(effect);
}
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
