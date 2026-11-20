//! The literals the type catalog registers before any body is checked, as a fact about the syntax tables.
const std = @import("std");
const ast = @import("ast.zig");
const Source = @import("source.zig").Source;

/// The literal `node` is, if the catalog registers it: a text literal, or a bytes literal that is not spelled `b"..."` (the managed bytes
/// literal needs no array schema) and so has the fixed-array shape of its decoded length. `src` is the source `node`'s span lies in.
pub fn of(src: Source, node: ast.Node) ?ast.Literal {
    return switch (node.data) {
        .text => .{ .span = node.span },
        .bytes => |bytes| blk: {
            const spelling = src.text(node.span);
            if (spelling.len != 0 and spelling[0] == 'b') break :blk null;
            break :blk .{ .span = node.span, .bytes = bytes.len };
        },
        else => null,
    };
}

/// Every literal of `program`, in node order, found by scanning its node table: what a merge records as it copies the nodes and what a
/// program that was not merged from modules is left to ask for. Owned by `allocator`.
pub fn scan(allocator: std.mem.Allocator, src: Source, program: ast.Program) std.mem.Allocator.Error![]ast.Literal {
    var found: std.ArrayList(ast.Literal) = .empty;
    errdefer found.deinit(allocator);
    for (program.nodes.items) |node| if (of(src, node)) |literal| try found.append(allocator, literal);
    return found.toOwnedSlice(allocator);
}

/// Whether two literal lists are the same list.
pub fn same(left: []const ast.Literal, right: []const ast.Literal) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (a.span.start != b.span.start or a.span.end != b.span.end or a.bytes != b.bytes) return false;
    }
    return true;
}
