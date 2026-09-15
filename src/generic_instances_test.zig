//! Specialization discovery preserves declaration/type identity and bounded resource use.
const std = @import("std");
const t = std.testing;
const instances = @import("generic_instances.zig");
const typed = @import("typed.zig");
const language = @import("compiler.zig");
const Registry = instances.Registry;
fn insert(registry: *Registry, allocator: std.mem.Allocator, declaration: usize, arguments: []const typed.Type) !instances.InstanceId {
    return registry.intern(allocator, .{ .declaration = @fromBackingInt(declaration), .arguments = arguments });
}
fn scenario(allocator: std.mem.Allocator) !void {
    var registry: Registry = .{};
    defer registry.deinit(allocator);
    var arguments = [_]typed.Type{ .i64, .bool };
    const original = try insert(&registry, allocator, 0, &arguments);
    arguments[0] = .u8;
    const changed = try insert(&registry, allocator, 0, &arguments);
    const reordered = try insert(&registry, allocator, 0, &.{ .bool, .i64 });
    const other_declaration = try insert(&registry, allocator, 1, &.{ .i64, .bool });
    try t.expectEqual(original, try insert(&registry, allocator, 0, &.{ .i64, .bool }));
    try t.expectEqual(@as(usize, 4), registry.entries.items.len);
    try t.expect(original != changed and original != reordered and original != other_declaration);
    try t.expectEqualSlices(typed.Type, &.{ .i64, .bool }, (try registry.get(original)).arguments);
    try t.expectEqual(@as(usize, 0), @backingInt(original));
    try t.expectEqual(@as(usize, 3), @backingInt(other_declaration));
}
// spec: GENERIC-INSTANCE-1
test "generic instances own ordered keys and deduplicate recursive discovery" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "generic instances distinguish nominal types with identical representation" {
    var compilation = try language.Compilation.init(t.allocator, "nominal.my",
        \\domain A: i64:
        \\    pass
        \\
        \\
        \\domain B: i64:
        \\    pass
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.check();
    const records = compilation.program.?.records;
    var first: ?typed.Record = null;
    var second: ?typed.Record = null;
    for (records) |record| {
        if (std.mem.eql(u8, record.name, "A")) first = record;
        if (std.mem.eql(u8, record.name, "B")) second = record;
    }
    const a_record = first orelse return error.TestUnexpectedResult;
    const b_record = second orelse return error.TestUnexpectedResult;
    try t.expectEqual(a_record.shape.domain, b_record.shape.domain);
    var registry: Registry = .{};
    defer registry.deinit(t.allocator);
    const a = try insert(&registry, t.allocator, 0, &.{a_record.id});
    const b = try insert(&registry, t.allocator, 0, &.{b_record.id});
    const builtin = try insert(&registry, t.allocator, 0, &.{.i64});
    try t.expect(a != b and a != builtin and b != builtin);
    try t.expectEqual(a, try insert(&registry, t.allocator, 0, &.{a_record.id}));
}
test "generic instances limits preserve existing identities and ordered traversal" {
    var registry: Registry = .{};
    defer registry.deinit(t.allocator);
    const sixteen: [Registry.max_arguments]typed.Type = @splat(.i64);
    const first = try insert(&registry, t.allocator, 0, &sixteen);
    const saved = try registry.get(first);
    for (1..Registry.max_instances) |index| {
        const id = try insert(&registry, t.allocator, index, &.{});
        try t.expectEqual(index, @backingInt(id));
        try t.expectEqual(index, @backingInt((try registry.get(id)).declaration));
    }
    try t.expectEqual(first, try insert(&registry, t.allocator, 0, &sixteen));
    try t.expectError(error.TooManyInstances, insert(&registry, t.allocator, Registry.max_instances, &.{}));
    const seventeen: [Registry.max_arguments + 1]typed.Type = @splat(.i64);
    try t.expectError(error.TooManyTypeArguments, insert(&registry, t.allocator, 0, &seventeen));
    try t.expectEqual(@as(usize, Registry.max_instances), registry.entries.items.len);
    try t.expectEqualSlices(typed.Type, &sixteen, saved.arguments);
}

test "generic instances reject invalid IDs before and after insertion" {
    var registry: Registry = .{};
    defer registry.deinit(t.allocator);
    try t.expectError(error.InvalidInstance, registry.get(@fromBackingInt(0)));
    _ = try insert(&registry, t.allocator, 0, &.{});
    try t.expectError(error.InvalidInstance, registry.get(@fromBackingInt(1)));
    try t.expectError(error.InvalidInstance, registry.get(@fromBackingInt(std.math.maxInt(usize))));
}
fn recoverFailure(preload: usize) !void {
    var failing = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    const allocator = failing.allocator();
    var registry: Registry = .{};
    defer registry.deinit(allocator);
    for (0..preload) |index| _ = try insert(&registry, allocator, index, &.{.i64});
    failing.fail_index = failing.alloc_index;
    try t.expectError(error.OutOfMemory, insert(&registry, allocator, preload, &.{.bool}));
    try t.expectEqual(preload, registry.entries.items.len);
    for (0..preload) |index| {
        const existing = try insert(&registry, allocator, index, &.{.i64});
        try t.expectEqual(index, @backingInt(existing));
        try t.expectEqualSlices(typed.Type, &.{.i64}, (try registry.get(existing)).arguments);
    }
    failing.fail_index = std.math.maxInt(usize);
    try t.expectEqual(preload, @backingInt(try insert(&registry, allocator, preload, &.{.bool})));
    try t.expectEqual(preload + 1, registry.entries.items.len);
}
test "generic instances intern recovers from allocation failure without losing existing IDs" {
    for (0..40) |preload| try recoverFailure(preload);
}
