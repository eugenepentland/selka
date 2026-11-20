//! One-byte constants: `ord("=")` and `b"="[0]`.
//!
//! A character code in a lexer is a number a reader has to decode (`61` is `=`). Both spellings fold to that number
//! where a compile-time value is needed: a module `const` and a literal `match` arm. The argument is a literal of
//! exactly one byte (`ord` also needs it below 0x80, so the byte is the Unicode scalar `ord` answers), or a
//! literal indexed by an integer literal inside it. Anything else keeps the diagnostic of the position.
const std = @import("std");
const ast = @import("ast.zig");
const number_literal = @import("number_literal.zig");
const source = @import("source.zig");

/// The byte a node spells as `ord("x")` or `LITERAL[N]`, or null when the node is neither: a literal of another
/// length, a computed argument or index, an index past the literal, or a call with named or extra arguments.
pub fn fold(src: source.Source, nodes: []const ast.Node, id: ast.NodeId) ?u8 {
    const node = nodes[@backingInt(id)];
    switch (node.data) {
        .call => |call| {
            if (call.owner != null or call.type_arguments.len != 0 or call.arguments.len != 1) return null;
            for (call.argument_names) |name| if (name != null) return null;
            if (!std.mem.eql(u8, src.text(call.name), "ord")) return null;
            const argument = nodes[@backingInt(call.arguments[0])].data;
            if (argument != .text or argument.text.len != 1 or argument.text[0] >= 0x80) return null;
            return argument.text[0];
        },
        .index => |index| {
            const literal = literalBytes(nodes[@backingInt(index.base)].data) orelse return null;
            const at = nodes[@backingInt(index.index)].data;
            if (at != .integer) return null;
            const position = switch (number_literal.integer(src.text(at.integer))) {
                .ok => |parts| number_literal.magnitude(parts) orelse return null,
                .bad => return null,
            };
            if (position >= literal.len) return null;
            return literal[@intCast(position)];
        },
        else => return null,
    }
}

/// Whether `id` is spelled like one of the two forms, folded or not: the syntax of a byte constant.
pub fn spelled(src: source.Source, nodes: []const ast.Node, id: ast.NodeId) bool {
    const data = nodes[@backingInt(id)].data;
    return switch (data) {
        .call => |call| call.owner == null and call.arguments.len == 1 and std.mem.eql(u8, src.text(call.name), "ord"),
        .index => |index| literalBytes(nodes[@backingInt(index.base)].data) != null,
        else => false,
    };
}

fn literalBytes(data: @FieldType(ast.Node, "data")) ?[]const u8 {
    return switch (data) {
        .bytes => |decoded| decoded,
        .text => |decoded| decoded,
        else => null,
    };
}
