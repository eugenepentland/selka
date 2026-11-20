//! The sentence an import cycle is refused with (F-73). The rule stays: modules may not import each other, directly or
//! through others. The message says what each import of the cycle is used for and the way out.
const std = @import("std");

/// How many qualified names an edge lists before it counts the rest.
pub const listed_names = 3;

/// One import of a cycle: the module that writes it, the module it names, and the qualified names the first reads from the
/// second, as written and in the order they first appear. No names means the import is unused.
pub const Edge = struct {
    from: []const u8,
    to: []const u8,
    uses: []const []const u8,
};

/// What each import of the cycle is used for and the way out, in one text after the chain `a -> b -> a`. A module that
/// imports itself, an import nothing reads (removing it breaks the cycle) and a ring of two or more modules each have their
/// own sentence.
pub fn explain(allocator: std.mem.Allocator, edges: []const Edge) error{OutOfMemory}![]const u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    const out = &text.writer;
    if (edges.len == 1) {
        out.print("`{s}` imports itself; remove `import {s}`, because a module's own declarations are in scope without an import", .{ edges[0].from, edges[0].to }) catch return error.OutOfMemory;
        return text.toOwnedSlice();
    }
    var unused: ?Edge = null;
    for (edges, 0..) |edge, at| {
        if (at != 0) out.writeAll("; ") catch return error.OutOfMemory;
        if (edge.uses.len == 0) {
            out.print("`{s}` imports `{s}` and uses nothing from it", .{ edge.from, edge.to }) catch return error.OutOfMemory;
            if (unused == null) unused = edge;
            continue;
        }
        out.print("`{s}` uses ", .{edge.from}) catch return error.OutOfMemory;
        const shown = @min(edge.uses.len, listed_names);
        for (edge.uses[0..shown], 0..) |name, index| {
            const last = index + 1 == shown and edge.uses.len == shown;
            const separator: []const u8 = if (index == 0) "" else if (last) " and " else ", ";
            out.print("{s}`{s}`", .{ separator, name }) catch return error.OutOfMemory;
        }
        if (edge.uses.len > shown) out.print(" and {d} more", .{edge.uses.len - shown}) catch return error.OutOfMemory;
    }
    if (unused) |edge| {
        out.print(". Remove `import {s}` from `{s}`, which never reads it: that breaks the cycle", .{ edge.to, edge.from }) catch return error.OutOfMemory;
    } else if (edges.len == 2) {
        out.writeAll(". Two modules may not import each other: move what both need into a module both import") catch return error.OutOfMemory;
    } else {
        out.writeAll(". Modules may not import each other in a ring: move what they share into a module that each of them imports") catch return error.OutOfMemory;
    }
    return text.toOwnedSlice();
}
