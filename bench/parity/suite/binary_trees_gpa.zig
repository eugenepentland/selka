// binary_trees (general-allocator variant): every node is one
// std.heap.smp_allocator create, and every tree is destroyed node by node
// right after its check. Children are allocated before their parent, as the
// other ports do. See SUITE.md section 1.
const std = @import("std");
const common = @import("common.zig");
const common_a = @import("common_a.zig");

const Node = struct {
    left: ?*Node,
    right: ?*Node,
};

fn make(allocator: std.mem.Allocator, depth: i64) *Node {
    var left: ?*Node = null;
    var right: ?*Node = null;
    if (depth > 0) {
        left = make(allocator, depth - 1);
        right = make(allocator, depth - 1);
    }
    const node = allocator.create(Node) catch @panic("out of memory");
    node.* = .{ .left = left, .right = right };
    return node;
}

fn check(node: *const Node) i64 {
    const left = node.left orelse return 1;
    return 1 + check(left) + check(node.right.?);
}

fn destroy(allocator: std.mem.Allocator, node: *Node) void {
    if (node.left) |left| destroy(allocator, left);
    if (node.right) |right| destroy(allocator, right);
    allocator.destroy(node);
}

pub fn main() void {
    const gpa = std.heap.smp_allocator;
    const max_depth = common.opaqueN(16);
    const min_depth: i64 = 4;
    var out: common_a.Lines = .{};

    const stretch = max_depth + 1;
    const stretch_tree = make(gpa, stretch);
    out.print("stretch tree of depth {d}\t check: {d}\n", .{ stretch, check(stretch_tree) });
    destroy(gpa, stretch_tree);

    const long_lived = make(gpa, max_depth);

    var depth = min_depth;
    while (depth <= max_depth) : (depth += 2) {
        const iterations = @as(i64, 1) << @intCast(max_depth - depth + min_depth);
        var total: i64 = 0;
        var i: i64 = 0;
        while (i < iterations) : (i += 1) {
            const tree = make(gpa, depth);
            total += check(tree);
            destroy(gpa, tree);
        }
        out.print("{d}\t trees of depth {d}\t check: {d}\n", .{ iterations, depth, total });
    }

    out.print("long lived tree of depth {d}\t check: {d}\n", .{ max_depth, check(long_lived) });
    destroy(gpa, long_lived);
    out.flush();
}
