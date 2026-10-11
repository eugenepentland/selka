//! Layout-specialized child destruction; the C runtime owns the count primitive
//! and iterative pending chain. Legacy descriptors retain the interpreted walk.
const std = @import("std");

/// A descriptor's known references and nested union guards, in byte offsets.
pub const Parts = struct {
    refs: []const [2]u32,
    guards: []const [3]u32,
    /// Dictionary entries additionally release just their key or value.
    split: ?u32 = null,
    zero_rc: bool = false,
};

/// Emit one layout descriptor and its specialized whole/key/value destructors.
pub fn emit(a: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, stride: u32, parts: Parts) std.mem.Allocator.Error!void {
    const words = 3 + 2 * parts.refs.len + 3 * parts.guards.len;
    if (parts.zero_rc) {
        try out.print(a, "{s} = private constant [{d} x i32] [i32 {d}, i32 {d}, i32 {d}", .{ name, words, stride, parts.refs.len, parts.guards.len });
        for (parts.refs) |ref| try out.print(a, ", i32 {d}, i32 {d}", .{ ref[0], ref[1] });
        for (parts.guards) |guard| try out.print(a, ", i32 {d}, i32 {d}, i32 {d}", .{ guard[0], guard[1], guard[2] });
        try out.appendSlice(a, "], align 8\n");
        return;
    }
    try out.print(a, "{s} = private constant {{ [{d} x i32], ptr, ptr, ptr }} {{ [{d} x i32] [i32 {d}, i32 {d}, i32 -{d}", .{ name, words, words, stride, parts.refs.len, parts.guards.len + 1 });
    for (parts.refs) |ref| try out.print(a, ", i32 {d}, i32 {d}", .{ ref[0], ref[1] });
    for (parts.guards) |guard| try out.print(a, ", i32 {d}, i32 {d}, i32 {d}", .{ guard[0], guard[1], guard[2] });
    try out.print(a, "], ptr {s}.release, ptr ", .{name});
    if (parts.split != null) try out.print(a, "{s}.release.key, ptr {s}.release.value", .{ name, name }) else try out.appendSlice(a, "null, ptr null");
    try out.appendSlice(a, " }, align 8\n");
    try definition(a, out, name, parts, .all);
    if (parts.split != null) {
        try definition(a, out, name, parts, .key);
        try definition(a, out, name, parts, .value);
    }
}

const Part = enum { all, key, value };

fn definition(a: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, parts: Parts, part: Part) !void {
    const suffix = switch (part) {
        .all => "",
        .key => ".key",
        .value => ".value",
    };
    try out.print(a, "define internal void {s}.release{s}(ptr %element, ptr %pending) nounwind {{\nentry:\n", .{ name, suffix });
    for (parts.refs, 0..) |ref, index| {
        if (part == .key and ref[0] >= parts.split.?) continue;
        if (part == .value and ref[0] < parts.split.?) continue;
        var chain: std.ArrayList([3]u32) = .empty;
        var guard = ref[1];
        while (guard != 0) {
            const g = parts.guards[guard - 1];
            try chain.append(a, g);
            guard = g[2];
        }
        // Check outer arms first: inactive payload bytes need not hold a tag.
        var depth = chain.items.len;
        while (depth > 0) {
            depth -= 1;
            const g = chain.items[depth];
            try out.print(a, "  %tagptr.{d}.{d} = getelementptr inbounds i8, ptr %element, i64 {d}\n  %tag.{d}.{d} = load i64, ptr %tagptr.{d}.{d}, align 8\n", .{ index, depth, g[0], index, depth, index, depth });
            try out.print(a, "  %guard.{d}.{d} = icmp eq i64 %tag.{d}.{d}, {d}\n" ++
                "  br i1 %guard.{d}.{d}, label %guarded.{d}.{d}, label %next.{d}\nguarded.{d}.{d}:\n", .{ index, depth, index, depth, g[1], index, depth, index, depth, index, index, depth });
        }
        try out.print(a, "  %at.{d} = getelementptr inbounds i8, ptr %element, i64 {d}\n" ++
            "  %child.{d} = load ptr, ptr %at.{d}, align 8\n", .{ index, ref[0], index, index });
        if (part == .all) {
            try out.print(a, "  call void @myl_core_release_child_pending(ptr %child.{d}, ptr %pending)\n", .{index});
        } else {
            // A dictionary overwrite/removal finishes each child in descriptor
            // order, as its C fallback does; a whole dying block uses the queue.
            try out.print(a, "  call void @myl_core_release(ptr %child.{d})\n", .{index});
        }
        try out.print(a, "  br label %next.{d}\nnext.{d}:\n", .{ index, index });
    }
    try out.appendSlice(a, "  ret void\n}\n");
}
