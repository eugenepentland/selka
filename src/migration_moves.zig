//! Spell captures introduced by source migrations without turning reads into loans.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");

/// A place read stored by the retired construct needs an explicit snapshot.
/// Written own/copy and fresh operands keep their original spelling; only the
/// generated owning temporary is moved by the emitter. Calls with an unknown
/// declaration are copied conservatively because they may declare from.
pub fn capture(a: std.mem.Allocator, src: source.Source, syntax: ast.Program, id: ast.NodeId, managed: bool) error{OutOfMemory}![]const u8 {
    const node = syntax.nodes.items[@backingInt(id)];
    const text = src.text(node.span);
    if (!managed) return text;
    const snapshot = switch (node.data) {
        .name, .field, .index, .slice => true,
        .call => !freshCall(src, syntax, node),
        .method_call => |call| !std.mem.eql(u8, src.text(call.name), "copy"),
        else => false,
    };
    return if (snapshot) std.fmt.allocPrint(a, "copy({s})", .{text}) else text;
}

/// Only an unqualified declaration in the same source module proves an ordinary
/// call fresh here. Imported/indirect calls need their own snapshot; a written
/// prelude copy remains exactly one copy.
fn freshCall(src: source.Source, syntax: ast.Program, node: ast.Node) bool {
    const call = node.data.call;
    if (call.owner != null) return false;
    const origin: usize = if (src.origins.len == 0) 0 else (src.originalSpan(node.span) catch return false).input;
    var found = false;
    for (syntax.functions) |function| {
        if (function.policy.owner != null or !std.mem.eql(u8, src.text(function.name), src.text(call.name))) continue;
        const declared: usize = if (src.origins.len == 0) 0 else (src.originalSpan(function.name) catch return false).input;
        if (origin != declared) continue;
        if (found or function.signature.borrowing.len != 0) return false;
        found = true;
    }
    return found or std.mem.eql(u8, src.text(call.name), "copy");
}
