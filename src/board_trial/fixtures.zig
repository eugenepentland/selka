//! Immutable guest fixtures for Zig boundary tests only; the executable loads disk sources.
const std = @import("std");
const language = @import("mylang");
/// Read the checked-in guest modules without a dependency on the working directory.
pub fn embedded(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    return language.embedded_project.read(allocator, &.{
        .{ .path = "main.my", .bytes = @embedFile("guest/main.my") },
        .{ .path = "units.my", .bytes = @embedFile("guest/units.my") },
        .{ .path = "ids.my", .bytes = @embedFile("guest/ids.my") },
        .{ .path = "model.my", .bytes = @embedFile("guest/model.my") },
        .{ .path = "bounds.my", .bytes = @embedFile("guest/bounds.my") },
        .{ .path = "inventory.my", .bytes = @embedFile("guest/inventory.my") },
        .{ .path = "checks.my", .bytes = @embedFile("guest/checks.my") },
        .{ .path = "policy.my", .bytes = @embedFile("guest/policy.my") },
        .{ .path = "geometry.my", .bytes = @embedFile("guest/geometry.my") },
        .{ .path = "validation.my", .bytes = @embedFile("guest/validation.my") },
    }, path, limit);
}
