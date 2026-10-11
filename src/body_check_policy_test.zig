//! Body-only logical row budgets preserve the syntax profile and shared bounds.
const std = @import("std");
const logical = @import("parser_value.zig");
const wire = @import("body_check_wire_io.zig");
const signature = "SLKLIM01";

fn boundary(a: std.mem.Allocator, profile: logical.ValueProfile) !void {
    const rows = profile.rows();
    const items = try a.alloc(void, rows - 1);
    defer a.free(items);
    const bytes = try logical.encodeTreeProfile(a, []const void, items, signature, profile);
    defer a.free(bytes);
    try std.testing.expectEqual(rows, std.mem.readInt(u32, bytes[8..12], .little));
    var decoded = try logical.decodeTreeProfile([]const void, a, bytes, signature, profile);
    defer decoded.arena.deinit();
    try std.testing.expectEqual(items.len, decoded.value.len);
    if (profile == .body) {
        try std.testing.expectError(error.ComponentProtocol, logical.decodeTree([]const void, a, bytes, signature));
        var owned = try wire.decode(a, []const void, bytes, signature);
        defer owned.arena.deinit();
        try std.testing.expectEqual(items.len, owned.value.len);
    }
    const excess = try a.alloc(void, rows);
    defer a.free(excess);
    try std.testing.expectError(error.ComponentProtocol, logical.encodeTreeProfile(a, []const void, excess, signature, profile));
    std.mem.writeInt(u32, bytes[8..12], rows + 1, .little);
    std.mem.writeInt(u32, bytes[12..16], rows, .little);
    try std.testing.expectError(error.ComponentProtocol, logical.decodeTreeProfile([]const void, a, bytes, signature, profile));
}

// spec: SELFHOST-BODY-VALUES-1
test "body policy exact syntax ceiling and first excess remain unchanged" {
    // spec-case: SELFHOST-BODY-VALUES-1
    try boundary(std.testing.allocator, .syntax);
}

test "body policy exact body ceiling and first excess are isolated" {
    // spec-case: SELFHOST-BODY-VALUES-1
    try boundary(std.testing.allocator, .body);
}

test "body policy wire encoding admits values beyond syntax without changing bytes" {
    // spec-case: SELFHOST-BODY-VALUES-1
    const a = std.testing.allocator;
    const items = try a.alloc(void, logical.max_values);
    defer a.free(items);
    try std.testing.expectError(error.ComponentProtocol, logical.encodeTree(a, []const void, items, signature));
    const bytes = try wire.encode(a, []const void, items, signature);
    defer a.free(bytes);
    try std.testing.expectEqual(@as(u32, logical.max_values + 1), std.mem.readInt(u32, bytes[8..12], .little));
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const decoded = try logical.decodeIntoProfile([]const void, arena.allocator(), bytes, signature, .body);
    try std.testing.expectEqual(items.len, decoded.len);
}

test "body policy retained eight field record schemas roundtrip without syntax relaxation" {
    // spec-case: SELFHOST-BODY-VALUES-1
    const a = std.testing.allocator;
    const typed = @import("typed.zig");
    const value = @import("body_check_value.zig");
    const schema: typed.Record = .{ .id = @fromBackingInt(256), .name = "Pair", .declaration = .{ .start = 3, .end = 7 }, .fields = &.{} };
    const catalog: value.Catalog = .{ .base_count = 1, .records = &.{schema} };
    const bytes = try wire.encode(a, value.Catalog, catalog, signature);
    defer a.free(bytes);
    var owned = try wire.decode(a, value.Catalog, bytes, signature);
    defer owned.arena.deinit();
    try std.testing.expectEqualDeep(catalog, owned.value);
    try std.testing.expectError(error.ComponentProtocol, logical.decodeTree(value.Catalog, a, bytes, signature));
    try std.testing.expectError(error.ComponentProtocol, wire.decode(a, struct { records: []const typed.Record }, bytes, signature));
}

test "body policy nine field logical records remain rejected" {
    // spec-case: SELFHOST-BODY-VALUES-1
    const Nine = struct { a: void, b: void, c: void, d: void, e: void, f: void, g: void, h: void, i: void };
    const a = std.testing.allocator;
    const bytes = try wire.encode(a, Nine, .{ .a = {}, .b = {}, .c = {}, .d = {}, .e = {}, .f = {}, .g = {}, .h = {}, .i = {} }, signature);
    defer a.free(bytes);
    try std.testing.expectError(error.ComponentProtocol, wire.decode(a, Nine, bytes, signature));
}

test "body policy default owned decoding remains syntax bounded" {
    // spec-case: SELFHOST-BODY-VALUES-1
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try logical.encodeTree(a, bool, true, signature);
    try std.testing.expect(try logical.decodeInto(bool, a, bytes, signature));
}
