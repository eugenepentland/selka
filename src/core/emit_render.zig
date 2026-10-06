//! Emit checked-source rendering descriptors from private lowering metadata.
const std = @import("std");
const ir = @import("ir.zig");
const metadata = @import("build_render.zig");
const Out = std.ArrayList(u8);
/// Invalid private metadata or allocation stops emission.
pub const Error = error{ OutOfMemory, UnsupportedInstruction };

/// Source IDs name adapters independently of their erased physical IR type.
pub fn adapter(a: std.mem.Allocator, out: *Out, function: *const ir.Function) Error!bool {
    if (function.signature.linkage != .runtime_c) return false;
    // Metadata declarations carry authority only and have no emitted symbol.
    if (std.mem.startsWith(u8, function.name, metadata.declaration_prefix)) return true;
    const prefix = "myl_core_show_";
    if (!std.mem.startsWith(u8, function.name, prefix)) return false;
    const number = function.name[prefix.len..];
    try out.print(a, "define internal ptr @{s}(ptr %value) nounwind {{\nentry:\n" ++
        "  %at = getelementptr inbounds i8, ptr %value, i64 32\n" ++
        "  %text = call ptr @myl_core_values_render(ptr @myl.render.{s}, ptr %at)\n  ret ptr %text\n}}\n", .{ function.name, number });
    return true;
}

/// Compiler declarations select finite graph nodes; child references may be cyclic.
pub fn descriptors(a: std.mem.Allocator, m: *const ir.Module, out: *Out) Error!void {
    for (m.functions.items) |function| {
        if (function.signature.linkage != .runtime_c) continue;
        if (!std.mem.startsWith(u8, function.name, metadata.declaration_prefix)) continue;
        const authority = function.name[metadata.declaration_prefix.len..];
        const split = std.mem.indexOfScalar(u8, authority, '_') orelse return error.UnsupportedInstruction;
        const index = std.fmt.parseInt(usize, authority[0..split], 10) catch return error.UnsupportedInstruction;
        if (index >= m.strings.items.len) return error.UnsupportedInstruction;
        const id = authority[split + 1 ..];
        const marker = try std.fmt.allocPrint(a, "{s}{s}|", .{ metadata.prefix, id });
        const text = m.strings.items[index];
        if (!std.mem.startsWith(u8, text, marker)) return error.UnsupportedInstruction;
        const parsed = std.json.parseFromSlice(metadata.Shape, a, text[marker.len..], .{}) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.UnsupportedInstruction;
        };
        defer parsed.deinit();
        try descriptor(a, out, id, parsed.value);
    }
}

fn descriptor(a: std.mem.Allocator, out: *Out, id: []const u8, shape: metadata.Shape) Error!void {
    if (shape.children.len != 0) {
        try out.print(a, "@myl.render.children.{s} = private constant [{d} x ptr] [", .{ id, shape.children.len });
        for (shape.children, 0..) |child, i| try out.print(a, "{s}ptr @myl.render.{s}", .{ if (i == 0) "" else ", ", child });
        try out.appendSlice(a, "]\n");
    }
    if (shape.offsets.len != 0) {
        try out.print(a, "@myl.render.offsets.{s} = private constant [{d} x i32] [", .{ id, shape.offsets.len });
        for (shape.offsets, 0..) |offset, i| try out.print(a, "{s}i32 {d}", .{ if (i == 0) "" else ", ", offset });
        try out.appendSlice(a, "]\n");
    }
    try names(a, out, id, shape.names);
    try out.print(a, "@myl.render.{s} = private constant %myl.value {{ i32 {d}, i32 {d}, i32 {d}, i32 {d}, ", .{ id, shape.kind, shape.size, shape.count, shape.aux });
    try reference(a, out, "children", id, shape.children.len);
    try out.appendSlice(a, ", ");
    try reference(a, out, "offsets", id, shape.offsets.len);
    try out.appendSlice(a, ", ");
    try reference(a, out, "names", id, shape.names.len);
    try out.appendSlice(a, " }\n");
}

fn reference(a: std.mem.Allocator, out: *Out, part: []const u8, id: []const u8, count: usize) Error!void {
    if (count == 0) return out.appendSlice(a, "ptr null");
    try out.print(a, "ptr @myl.render.{s}.{s}", .{ part, id });
}

fn names(a: std.mem.Allocator, out: *Out, id: []const u8, labels: []const []const u8) Error!void {
    if (labels.len == 0) return;
    for (labels, 0..) |label, i| {
        try out.print(a, "@myl.render.name.{s}.{d} = private constant [{d} x i8] c\"", .{ id, i, label.len + 1 });
        for (label) |byte| try out.print(a, "\\{X:0>2}", .{byte});
        try out.appendSlice(a, "\\00\"\n");
    }
    try out.print(a, "@myl.render.names.{s} = private constant [{d} x ptr] [", .{ id, labels.len });
    for (labels, 0..) |_, i| try out.print(a, "{s}ptr @myl.render.name.{s}.{d}", .{ if (i == 0) "" else ", ", id, i });
    try out.appendSlice(a, "]\n");
}
