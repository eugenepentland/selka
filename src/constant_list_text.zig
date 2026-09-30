//! Inert text/octet elements serialized without runtime pointer addresses.
const std = @import("std");
const typed = @import("typed.zig");

/// Identify builtin immutable text or bytes, refusing other managed values.
pub fn family(records: []const typed.Record, element: typed.Type) ?bool {
    if (!element.isAggregate() or element.recordIndex() >= records.len) return null;
    const record = records[element.recordIndex()];
    if (!record.managed) return null;
    if (record.collection.kind == .string) return true;
    return if (typed.isByteString(record)) false else null;
}

/// Every list element must itself be a literal of the exact declared family.
pub fn inert(nodes: []const typed.Node, elements: []const typed.NodeId, element: typed.Type, text: bool) bool {
    for (elements) |id| {
        const values = literal(nodes, id, element) orelse return false;
        for (values) |value| if (octets(nodes, value, text) == null) return false;
    }
    return true;
}

/// Encode a count followed by length-prefixed UTF-8/raw octets for each value.
pub fn payload(allocator: std.mem.Allocator, nodes: []const typed.Node, elements: []const typed.NodeId, element: typed.Type, text: bool) error{ OutOfMemory, InternalError }![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try number(&out.writer, elements.len);
    for (elements) |id| {
        const values = literal(nodes, id, element).?;
        var length: usize = 0;
        for (values) |value| length = std.math.add(usize, length, octets(nodes, value, text).?) catch return error.OutOfMemory;
        try number(&out.writer, length);
        for (values) |value| {
            const scalar = nodes[@backingInt(value)].data.integer;
            var bytes: [4]u8 = undefined;
            const width = octets(nodes, value, text).?;
            if (text) _ = std.unicode.utf8Encode(@intCast(scalar), &bytes) catch return error.InternalError else bytes[0] = @intCast(scalar);
            out.writer.writeAll(bytes[0..width]) catch return error.OutOfMemory;
        }
    }
    return out.toOwnedSlice();
}

fn number(writer: *std.Io.Writer, value: usize) error{OutOfMemory}!void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, std.math.cast(u32, value) orelse return error.OutOfMemory, .little);
    writer.writeAll(&bytes) catch return error.OutOfMemory;
}

fn literal(nodes: []const typed.Node, id: typed.NodeId, element: typed.Type) ?[]const typed.NodeId {
    if (@backingInt(id) >= nodes.len) return null;
    const node = nodes[@backingInt(id)];
    if (node.ty != element or node.data != .array) return null;
    return node.data.array;
}

fn octets(nodes: []const typed.Node, id: typed.NodeId, text: bool) ?usize {
    if (@backingInt(id) >= nodes.len) return null;
    const node = nodes[@backingInt(id)];
    if (node.ty != (if (text) typed.Type.u32 else typed.Type.u8) or node.data != .integer) return null;
    const scalar = node.data.integer;
    if (!text) return if (scalar >= 0 and scalar <= 255) 1 else null;
    if (scalar < 0 or scalar > 0x10ffff) return null;
    if (scalar >= 0xd800 and scalar <= 0xdfff) return null;
    return std.unicode.utf8CodepointSequenceLength(@intCast(scalar)) catch null;
}

/// Checked iterator over serialized literal values; rejects truncation/trailing data.
pub const Rows = struct {
    remaining: usize,
    rest: []const u8,
    /// Read the image count without allocating any runtime pointer table.
    pub fn init(bytes: []const u8) ?Rows {
        if (bytes.len < 4) return null;
        return .{ .remaining = std.mem.readInt(u32, bytes[0..4], .little), .rest = bytes[4..] };
    }
    /// Read one complete element, including a valid empty element.
    pub fn next(self: *Rows) error{InvalidPayload}!?[]const u8 {
        if (self.remaining == 0) {
            if (self.rest.len != 0) return error.InvalidPayload;
            return null;
        }
        if (self.rest.len < 4) return error.InvalidPayload;
        const length = std.mem.readInt(u32, self.rest[0..4], .little);
        if (length > self.rest.len - 4) return error.InvalidPayload;
        const value = self.rest[4 .. 4 + length];
        self.rest = self.rest[4 + length ..];
        self.remaining -= 1;
        return value;
    }
};

/// Validate complete framing and UTF-8 before native metadata generation.
pub fn valid(bytes: []const u8, text: bool) bool {
    var rows = Rows.init(bytes) orelse return false;
    if (rows.remaining == 0) return false;
    while (rows.next() catch return false) |value| if (text and !std.unicode.utf8ValidateSlice(value)) return false;
    return true;
}
