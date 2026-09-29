//! Packed constant primitive list payloads with bounded domain unwrapping.
const std = @import("std");
const typed = @import("typed.zig");
/// Keep small frequently mutated constructors ordinary; pack large literals.
pub const minimum_elements = 64;

/// Primitive representation of a domain chain, or null for managed/resources.
pub fn primitive(records: []const typed.Record, element: typed.Type) ?typed.Type {
    var ty = element;
    for (0..64) |_| {
        if (ty.integer() != null or ty == .bool) return ty;
        if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
        ty = records[ty.recordIndex()].shape.domain orelse return null;
    }
    return null;
}
/// Native byte stride of a supported primitive or primitive-backed domain.
pub fn width(records: []const typed.Record, element: typed.Type) ?u8 {
    const ty = primitive(records, element) orelse return null;
    return if (ty == .bool) 1 else ty.integer().?.bits / 8;
}
/// Identify a large inert literal before desugaring it into append statements.
pub fn canPack(records: []const typed.Record, nodes: []const typed.Node, elements: []const typed.NodeId, element: typed.Type) bool {
    if (elements.len < minimum_elements or width(records, element) == null) return false;
    for (elements) |id| if (constant(records, nodes, id, element, 0) == null) return false;
    return true;
}
/// Preserve the ordinary constructor unless every element is exactly constant.
/// Nonempty primitive payloads use native little-endian two's-complement bits.
pub fn payload(allocator: std.mem.Allocator, records: []const typed.Record, nodes: []const typed.Node, elements: []const typed.NodeId, element: typed.Type) error{OutOfMemory}!?[]const u8 {
    if (!canPack(records, nodes, elements, element)) return null;
    const stride = width(records, element) orelse return null;
    const length = std.math.mul(usize, elements.len, stride) catch return error.OutOfMemory;
    const bytes = try allocator.alloc(u8, length);
    for (elements, 0..) |id, index| {
        const number = constant(records, nodes, id, element, 0).?;
        const bits: u128 = @bitCast(number);
        for (0..stride) |offset| bytes[index * stride + offset] = @truncate(bits >> @as(u7, @intCast(offset * 8)));
    }
    return bytes;
}

fn constant(records: []const typed.Record, nodes: []const typed.Node, id: typed.NodeId, expected: typed.Type, depth: usize) ?i128 {
    if (depth >= 64 or @backingInt(id) >= nodes.len) return null;
    const node = nodes[@backingInt(id)];
    if (node.ty != expected) return null;
    return switch (node.data) {
        .integer => |number| if (expected.isInteger() and expected.fits(number)) number else null,
        .boolean => |boolean| if (expected == .bool) @intFromBool(boolean) else null,
        .wrap => |child| blk: {
            if (!expected.isAggregate() or expected.recordIndex() >= records.len) break :blk null;
            const backing = records[expected.recordIndex()].shape.domain orelse break :blk null;
            break :blk constant(records, nodes, child, backing, depth + 1);
        },
        else => null,
    };
}
