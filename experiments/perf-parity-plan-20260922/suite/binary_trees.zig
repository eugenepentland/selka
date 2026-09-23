// binary_trees: perfect binary trees in std.heap.ArenaAllocator storage.
// One arena per depth batch, reset (retaining its capacity) after each tree;
// the stretch tree and the long-lived tree each live in their own arena.
// Children are allocated before their parent, as the other ports do.
// See SUITE.md section 1.
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

pub fn main() void {
    const max_depth = common.opaqueN(16);
    const min_depth: i64 = 4;
    var out: common_a.Lines = .{};

    const stretch = max_depth + 1;
    {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        out.print("stretch tree of depth {d}\t check: {d}\n", .{ stretch, check(make(arena.allocator(), stretch)) });
    }

    var long_lived_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer long_lived_arena.deinit();
    const long_lived = make(long_lived_arena.allocator(), max_depth);

    var depth = min_depth;
    while (depth <= max_depth) : (depth += 2) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const iterations = @as(i64, 1) << @intCast(max_depth - depth + min_depth);
        var total: i64 = 0;
        var i: i64 = 0;
        while (i < iterations) : (i += 1) {
            total += check(make(allocator, depth));
            _ = arena.reset(.retain_capacity);
        }
        out.print("{d}\t trees of depth {d}\t check: {d}\n", .{ iterations, depth, total });
    }

    out.print("long lived tree of depth {d}\t check: {d}\n", .{ max_depth, check(long_lived) });
    out.flush();
}
