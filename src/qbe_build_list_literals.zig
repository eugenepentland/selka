//! Canonical list images containing only already-defined immortal literals.
const std = @import("std");
const units = @import("qbe_build_units.zig");
const Image = struct { symbol: []const u8, element: []const u8, count: usize, children: []const u8 };

/// Emit parents after the canonical literal pool, with order-independent symbols.
pub fn definitions(w: *std.Io.Writer, allocator: std.mem.Allocator, functions: []const std.json.Value) error{ OutOfMemory, WriteFailed }!void {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(allocator);
    var images: std.ArrayList(Image) = .empty;
    defer images.deinit(allocator);
    for (functions) |unit| {
        const facts = units.facts(unit);
        var at: usize = 0;
        while (std.mem.indexOfPos(u8, facts, at, "# myl-list ")) |found| {
            const end = std.mem.indexOfScalarPos(u8, facts, found, '\n') orelse facts.len;
            at = end;
            if (found != 0 and facts[found - 1] != '\n') continue;
            const image = parse(facts[found + 11 .. end]) orelse continue;
            if (seen.contains(image.symbol)) continue;
            try seen.put(allocator, image.symbol, {});
            try images.append(allocator, image);
        }
    }
    std.mem.sort(Image, images.items, {}, before);
    for (images.items) |image| try emit(w, image);
}

fn parse(line: []const u8) ?Image {
    var words = std.mem.tokenizeScalar(u8, line, ' ');
    const symbol = words.next() orelse return null;
    const element = words.next() orelse return null;
    const count = std.fmt.parseInt(usize, words.next() orelse return null, 10) catch return null;
    return .{ .symbol = symbol, .element = element, .count = count, .children = words.rest() };
}

fn before(_: void, a: Image, b: Image) bool {
    return std.mem.lessThan(u8, a.symbol, b.symbol);
}

fn emit(w: *std.Io.Writer, image: Image) error{WriteFailed}!void {
    try w.print("typedef struct {{ myl_native_object header; myl_native_list value; myl_native_object storage_header; void *storage[{d}]; }} {s}_block;\n", .{ image.count, image.symbol });
    try w.print("static {s}_block {s}_instance = {{\n", .{ image.symbol, image.symbol });
    try w.writeAll(" .header = {.mark = MYL_NATIVE_OBJECT_LITERAL_MARK | MYL_NATIVE_OBJECT_SHARED, .element = &myl_native_list_header_descriptor},\n");
    try w.print(" .value = {{.length = {d}, .capacity = {d}, .element = &{s}, .storage = (unsigned char *){s}_instance.storage}},\n", .{ image.count, image.count, image.element, image.symbol });
    try w.print(" .storage_header = {{.mark = MYL_NATIVE_OBJECT_LITERAL_MARK, .element = &{s}}},\n .storage = {{", .{image.element});
    var children = std.mem.tokenizeScalar(u8, image.children, ' ');
    while (children.next()) |child| try w.print("&{s}_instance.value,", .{child});
    try w.print("}}\n}};\nconst void *const {s} = &{s}_instance.value;\n", .{ image.symbol, image.symbol });
}
