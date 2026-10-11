//! Independent lifetime and budget regressions for bounded body adoption.
const std = @import("std");
const copy = @import("body_owned_copy.zig");
const logical = @import("parser_value.zig");
const body = @import("body_check_value.zig");
const typed = @import("typed.zig");
const signature = "SLKCLN01";
const Sample = struct { text: []const u8, optional: ?[]const u8, choice: union(enum) { none: void, values: []const i64 }, fixed: [2]bool, identity: enum(usize) { _ } };
fn sample() Sample {
    return .{ .text = "é\x00bytes", .optional = "optional", .choice = .{ .values = &.{ -1, 7 } }, .fixed = .{ true, false }, .identity = @fromBackingInt(37) };
}
fn allocationFailure(a: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const output = try copy.clone(arena.allocator(), Sample, sample());
    try std.testing.expectEqualStrings("optional", output.optional.?);
}
fn boundary(a: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const items = try a.alloc(void, logical.ValueProfile.body.rows() - 1);
    defer a.free(items);
    const output = try copy.clone(arena.allocator(), []const void, items);
    try std.testing.expectEqual(items.len, output.len);
    const excess = try a.alloc(void, logical.ValueProfile.body.rows());
    defer a.free(excess);
    try std.testing.expectError(error.ComponentProtocol, copy.clone(arena.allocator(), []const void, excess));
}
// spec: SELFHOST-BODY-OWNED-COPY-1
test "body owned copy preserves all value shapes independently of source lifetime" {
    var input = std.heap.ArenaAllocator.init(std.testing.allocator);
    var output = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer output.deinit();
    const original = try copy.clone(input.allocator(), Sample, sample());
    const cloned = try copy.clone(output.allocator(), Sample, original);
    const before = try logical.encodeTreeProfile(std.testing.allocator, Sample, original, signature, .body);
    defer std.testing.allocator.free(before);
    try std.testing.expect(original.text.ptr != cloned.text.ptr);
    try std.testing.expect(original.choice.values.ptr != cloned.choice.values.ptr);
    input.deinit();
    const after = try logical.encodeTreeProfile(std.testing.allocator, Sample, cloned, signature, .body);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}
// spec-case: SELFHOST-BODY-OWNED-COPY-1
test "body owned copy cleans every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailure, .{});
}
// spec-case: SELFHOST-BODY-OWNED-COPY-1
test "body owned copy exact row ceiling and first excess" {
    try boundary(std.testing.allocator);
}
// spec-case: SELFHOST-BODY-OWNED-COPY-1
test "body owned copy refuses codec integer and wire excess before adoption" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.ComponentProtocol, copy.clone(arena.allocator(), u128, std.math.maxInt(u128)));
    const huge = try std.testing.allocator.alloc(u8, logical.value_wire_limit);
    defer std.testing.allocator.free(huge);
    try std.testing.expectError(error.ComponentProtocol, copy.clone(arena.allocator(), []const u8, huge));
}
// spec-case: SELFHOST-BODY-OWNED-COPY-1
test "body owned copy adopts real batch nested slices and nullable typed metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const nodes: []const typed.Node = &.{.{ .ty = .i64, .span = .{ .start = 3, .end = 4 }, .data = .{ .integer = 7 } }};
    const statements: []const typed.Statement = &.{.{ .span = .{ .start = 0, .end = 4 }, .terminates = true, .data = .{ .ret = @fromBackingInt(0) } }};
    const functions: []const typed.Function = &.{.{ .id = @fromBackingInt(0), .name = "entry", .declaration = .{ .start = 0, .end = 3 }, .scope = .{ .body = @fromBackingInt(0) } }};
    const original: body.Batch = .{ .nodes = nodes, .statements = statements, .functions = functions, .ranges = &.{.{ .nodes = .{ .start = 0, .end = 1 }, .statements = .{ .start = 0, .end = 1 } }} };
    const result = try body.cloneBatch(arena.allocator(), original);
    const lhs = try logical.encodeTreeProfile(std.testing.allocator, body.Batch, original, "SLKBTB01", .body);
    defer std.testing.allocator.free(lhs);
    const rhs = try logical.encodeTreeProfile(std.testing.allocator, body.Batch, result, "SLKBTB01", .body);
    defer std.testing.allocator.free(rhs);
    try std.testing.expectEqualSlices(u8, lhs, rhs);
    try std.testing.expect(original.functions.ptr != result.functions.ptr);
    try std.testing.expect(original.functions[0].name.ptr != result.functions[0].name.ptr);
}

const Nest = struct { children: []const Nest };
fn nestedLimit(a: std.mem.Allocator) !void {
    var nodes: [130]Nest = undefined;
    for (&nodes, 0..) |*node, index| node.* = .{ .children = if (index + 1 < nodes.len) nodes[index + 1 .. index + 2] else &.{} };
    try std.testing.expectError(error.ComponentProtocol, logical.encodeTreeProfile(a, Nest, nodes[0], signature, .body));
    try std.testing.expectError(error.ComponentProtocol, copy.clone(a, Nest, nodes[0]));
}
// spec-case: SELFHOST-BODY-OWNED-COPY-1
test "body owned copy enforces the same recursive depth refusal as the codec" {
    try nestedLimit(std.testing.allocator);
}

fn visitLimit(a: std.mem.Allocator) !void {
    const items = try a.alloc(??u8, 1398102);
    defer a.free(items);
    @memset(items, @as(??u8, @as(?u8, 7)));
    const wire = try logical.encodeTreeProfile(a, []const ??u8, items, signature, .body);
    defer a.free(wire);
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    try std.testing.expectError(error.ComponentProtocol, logical.decodeIntoProfile([]const ??u8, arena.allocator(), wire, signature, .body));
    try std.testing.expectError(error.ComponentProtocol, copy.clone(arena.allocator(), []const ??u8, items));
}
// spec-case: SELFHOST-BODY-OWNED-COPY-1
test "body owned copy preserves independent expansion visit limit" {
    try visitLimit(std.testing.allocator);
}

const Wide = union(enum) { small: void, wide: [4096]u8 };
fn memoryLimit(a: std.mem.Allocator) !void {
    const items = try a.alloc(Wide, 140000);
    defer a.free(items);
    @memset(items, .{ .small = {} });
    const wire = try logical.encodeTreeProfile(a, []const Wide, items, signature, .body);
    defer a.free(wire);
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    try std.testing.expectError(error.ComponentProtocol, logical.decodeIntoProfile([]const Wide, arena.allocator(), wire, signature, .body));
    try std.testing.expectError(error.ComponentProtocol, copy.clone(arena.allocator(), []const Wide, items));
}
// spec-case: SELFHOST-BODY-OWNED-COPY-1
test "body owned copy preserves decoder allocation ceiling for wide union storage" {
    try memoryLimit(std.testing.allocator);
}

fn allocationBytes(a: std.mem.Allocator, direct: bool) !usize {
    var tracking = std.testing.FailingAllocator.init(a, .{});
    var arena = std.heap.ArenaAllocator.init(tracking.allocator());
    defer arena.deinit();
    var items: [256]Sample = undefined;
    @memset(&items, sample());
    if (direct) {
        _ = try copy.clone(arena.allocator(), []const Sample, &items);
    } else {
        const wire = try logical.encodeTreeProfile(arena.allocator(), []const Sample, &items, signature, .body);
        _ = try logical.decodeIntoProfile([]const Sample, arena.allocator(), wire, signature, .body);
    }
    return tracking.allocated_bytes;
}
// spec-case: SELFHOST-BODY-OWNED-COPY-1
test "body owned copy removes intermediary allocations without changing output policy" {
    const direct = try allocationBytes(std.testing.allocator, true);
    const prior = try allocationBytes(std.testing.allocator, false);
    try std.testing.expect(direct < prior);
    std.debug.print("owned-copy allocation diagnostic: direct={d} prior={d} bytes; no timing claim\n", .{ direct, prior });
}
