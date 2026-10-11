//! Closed primitive file/output operations; lexical ownership is checked separately.
const std = @import("std");
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
const lists = @import("body_check_list_validate.zig");
/// Invalid primitive authority or operand metadata.
pub const Error = error{ComponentProtocol};
/// Canonical checked file result authority shared with catalog admission.
pub const fileResult = @import("body_check_resource_authority.zig").fileResult;
fn nodeType(nodes: []const typed.Node, id: typed.NodeId) Error!typed.Type {
    if (@backingInt(id) >= nodes.len) return error.ComponentProtocol;
    return nodes[@backingInt(id)].ty;
}
fn shapes(catalog: value.Catalog, item: typed.FileShapes) Error!void {
    const text = catalog.string orelse return error.ComponentProtocol;
    const bytes = catalog.bytes orelse return error.ComponentProtocol;
    if (item.text != text.id or item.bytes != bytes.id) return error.ComponentProtocol;
    if (lists.listElement(catalog, item.list) != text.id) return error.ComponentProtocol;
}
/// Check native file/open/output operand widths and exact result identities.
pub fn node(catalog: value.Catalog, nodes: []const typed.Node, locals: []const typed.Local, item: typed.Node) Error!void {
    switch (item.data) {
        .file_access => |access| {
            try shapes(catalog, access.shapes);
            if (access.kind != .open or access.arguments.len != 3) return error.ComponentProtocol;
            if (access.mode != 'r' or access.text) return error.ComponentProtocol;
            if (try nodeType(nodes, access.arguments[0]) != .filesystem_cap) return error.ComponentProtocol;
            for (access.arguments[1..]) |argument| if (try nodeType(nodes, argument) != access.shapes.text) return error.ComponentProtocol;
            try mode(nodes, access);
            const handle: typed.Type = if (access.text) .text_file else .file;
            if (item.ty != handle and fileResult(catalog, item.ty) != handle) return error.ComponentProtocol;
        },
        .file_method => |method| {
            try shapes(catalog, method.shapes);
            if (@backingInt(method.owner) >= locals.len or method.kind != .read or method.text) return error.ComponentProtocol;
            const owner = locals[@backingInt(method.owner)];
            const handle: typed.Type = if (method.text) .text_file else .file;
            if (owner.ty != handle or !owner.ownership.scoped_file) return error.ComponentProtocol;
            if (method.argument) |argument| if (try nodeType(nodes, argument) != .i64) return error.ComponentProtocol;
            if (item.ty != (if (method.text) method.shapes.text else method.shapes.bytes)) return error.ComponentProtocol;
        },
        .stream_write => |write| {
            if (item.ty != .i64 or try nodeType(nodes, write.stream) != .stream_cap) return error.ComponentProtocol;
            if (!octets(catalog, try nodeType(nodes, write.text))) return error.ComponentProtocol;
        },
        .print => |print| {
            if (item.ty != .unit or print.debug or print.sink != .stdout) return error.ComponentProtocol;
            const stream = print.stream orelse return error.ComponentProtocol;
            if (try nodeType(nodes, stream) != .stream_cap) return error.ComponentProtocol;
            for (print.arguments) |argument| if (!@import("io_render.zig").printable(try nodeType(nodes, argument), catalog.records)) return error.ComponentProtocol;
            const text = catalog.string orelse return error.ComponentProtocol;
            if (print.separator) |id| if (try nodeType(nodes, id) != text.id) return error.ComponentProtocol;
            if (print.terminator) |id| if (try nodeType(nodes, id) != text.id) return error.ComponentProtocol;
        },
        else => return error.ComponentProtocol,
    }
}
fn octets(catalog: value.Catalog, ty: typed.Type) bool {
    if (catalog.string) |entry| if (entry.id == ty) return true;
    if (catalog.bytes) |entry| if (entry.id == ty) return true;
    if (catalog.templates.byte_buffer.identity) |entry| if (entry.id == ty) return true;
    return false;
}
fn mode(nodes: []const typed.Node, access: typed.FileAccess) Error!void {
    const argument = nodes[@backingInt(access.arguments[2])];
    if (argument.data != .array) return error.ComponentProtocol;
    const characters = argument.data.array;
    if (characters.len == 0 or characters.len > 2) return error.ComponentProtocol;
    var spelling: [2]u8 = undefined;
    for (characters, 0..) |id, index| {
        if (@backingInt(id) >= nodes.len) return error.ComponentProtocol;
        const character = nodes[@backingInt(id)];
        if (character.ty != .u32 or character.data != .integer) return error.ComponentProtocol;
        spelling[index] = std.math.cast(u8, character.data.integer) orelse return error.ComponentProtocol;
    }
    const parsed = @import("file_operations.zig").parseMode(spelling[0..characters.len]) orelse return error.ComponentProtocol;
    if (parsed.letter != access.mode or parsed.text != access.text) return error.ComponentProtocol;
}
