//! Owned typed values cross native calls only as bounded copied forests.
const std = @import("std");
const typed = @import("typed.zig");
const abi = @import("native_json_abi.zig");
/// Copy failures retain malformed values and actual allocation errors distinctly.
pub const Error = error{ OutOfMemory, InvalidDataValue, ValueTypeMismatch, InvalidAggregateType, InternalError };
/// Decode a compiler-typed copied forest, allocating an owned value.
pub fn readNodes(allocator: std.mem.Allocator, records: []const typed.Record, ty: typed.Type, nodes: []const abi.Node, cursor: *usize) Error!typed.Value {
    if (cursor.* == nodes.len) return error.InvalidDataValue;
    const node = nodes[cursor.*];
    cursor.* += 1;
    if (!std.mem.eql(u8, std.mem.span(node.name), typed.typeName(ty, records))) return error.ValueTypeMismatch;
    if (ty.isInteger()) {
        var number: i128 = node.bits;
        if (ty.integer().?.signed and node.bits >> 63 != 0) number -= @as(i128, 1) << 64;
        if (!ty.fits(number) or node.children != 0) return error.InvalidDataValue;
        return typed.Value.number(ty, number);
    }
    if (ty == .bool) {
        if (node.bits > 1 or node.children != 0) return error.InvalidDataValue;
        return .{ .bool = node.bits != 0 };
    }
    const record = records[ty.recordIndex()];
    if (record.shape.domain) |backing| {
        if (node.children != 1 or node.bits != 0) return error.InvalidDataValue;
        const child = try readNodes(allocator, records, backing, nodes, cursor);
        defer child.release(allocator);
        return typed.Value.create(allocator, ty, &.{child});
    }
    if (record.shape.variants) |variants| {
        if (node.bits >= variants.cases.len) return error.InvalidDataValue;
        const tag: usize = @intCast(node.bits);
        if (variants.cases[tag].payload) |child| {
            if (node.children != 1) return error.InvalidDataValue;
            const value = try readNodes(allocator, records, child, nodes, cursor);
            defer value.release(allocator);
            return typed.Value.createVariant(allocator, ty, tag, value);
        }
        if (node.children != 0) return error.InvalidDataValue;
        return typed.Value.createVariant(allocator, ty, tag, null);
    }
    if (node.children != record.count() or node.bits != 0) return error.InvalidDataValue;
    const fields = try allocator.alloc(typed.Value, node.children);
    var initialized: usize = 0;
    defer {
        for (fields[0..initialized]) |value| value.release(allocator);
        allocator.free(fields);
    }
    for (fields, 0..) |*field, i| {
        field.* = try readNodes(allocator, records, record.elementType(i), nodes, cursor);
        initialized += 1;
    }
    return typed.Value.create(allocator, ty, fields);
}
/// Copy one owned value into a synchronous ABI forest.
pub fn writeNodes(allocator: std.mem.Allocator, records: []const typed.Record, ty: typed.Type, value: typed.Value, nodes: *std.ArrayList(abi.Node)) Error!void {
    var node: abi.Node = .{ .name = @ptrCast(typed.typeName(ty, records).ptr), .bits = 0, .children = 0 };
    if (ty.isInteger()) {
        node.bits = @truncate(@as(u128, @bitCast(try value.asInteger())));
    } else if (ty == .bool) {
        node.bits = @intFromBool(value.bool);
    } else {
        node.children = value.aggregate.fields.len;
        if (value.aggregate.active_tag) |tag| node.bits = tag;
    }
    try nodes.append(allocator, node);
    if (!ty.isAggregate()) return;
    const record = records[ty.recordIndex()];
    for (value.aggregate.fields, 0..) |field, i| {
        const child = if (record.shape.variants) |variants| variants.cases[@intCast(node.bits)].payload.? else record.shape.domain orelse record.elementType(i);
        try writeNodes(allocator, records, child, field, nodes);
    }
}
