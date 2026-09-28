//! Exact typed constant pushes used by frozen bytes/text data emission.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
/// Validate the same contiguous literal inputs before proof or static emission.
/// A literal that carries its content as one `payload` (`LITERAL-PAYLOAD-1`) has
/// no pushes to scan: the bytecode validator already checked the payload.
pub fn frozen(code: []const bytecode.Instruction, pc: usize, record: @FieldType(@FieldType(bytecode.Instruction, "op"), "make_record"), element: typed.Type, text: bool) bool {
    if (record.order.len != 0) return false;
    if (record.payload.len != 0) return record.fields == 0;
    if (pc < record.fields or pc > code.len) return false;
    for (code[pc - record.fields .. pc]) |instruction| switch (instruction.op) {
        .push_integer => |number| {
            if (number.ty != element) return false;
            if (text) {
                if (number.value < 0 or number.value > 0x10ffff) return false;
                if (number.value >= 0xd800 and number.value <= 0xdfff) return false;
            }
        },
        else => return false,
    };
    return true;
}
/// The single `payload` a `str` or `bytes` literal's constant elements spell:
/// the UTF-8 octets of the scalars (`text`) or the raw octets, in element order.
/// Null when the literal is empty or any element is not a constant of the
/// element type — a scalar that is not a Unicode scalar value, an octet above
/// 255 — so the caller keeps the element-by-element form. Two passes over the
/// elements size the result exactly, so it is allocated once.
pub fn payload(allocator: std.mem.Allocator, nodes: []const typed.Node, elements: []const typed.NodeId, text: bool) error{ OutOfMemory, InternalError }!?[]const u8 {
    if (elements.len == 0) return null;
    var length: usize = 0;
    for (elements) |id| length += octetsOf(nodes[@backingInt(id)], text) orelse return null;
    const octets = try allocator.alloc(u8, length);
    var at: usize = 0;
    for (elements) |id| {
        const value = nodes[@backingInt(id)].data.integer;
        if (text) at += std.unicode.utf8Encode(@intCast(value), octets[at..]) catch return error.InternalError else {
            octets[at] = @intCast(value);
            at += 1;
        }
    }
    return octets;
}
/// How many octets one literal element contributes, or null when the element
/// is not a constant of the literal's element type.
fn octetsOf(node: typed.Node, text: bool) ?usize {
    if (node.ty != (if (text) typed.Type.u32 else typed.Type.u8) or node.data != .integer) return null;
    const value = node.data.integer;
    if (!text) return if (value >= 0 and value <= 0xff) 1 else null;
    if (value < 0 or value > 0x10ffff or (value >= 0xd800 and value <= 0xdfff)) return null;
    return std.unicode.utf8CodepointSequenceLength(@intCast(value)) catch null;
}
