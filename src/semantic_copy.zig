//! Relocate owned checked function trees into a fresh compilation's source and ID space.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
/// Source interval whose bytes are unchanged at a new offset.
pub const Segment = struct { before: source.Span, after: usize };
/// Contiguous expression/statement IDs belonging to one checked function.
pub const Range = struct { nodes: source.Span, statements: source.Span };
/// Validation failures indicate a cache miss, never a trusted unchecked identity.
pub const Error = error{ OutOfMemory, InternalError, InvalidRelocation };
/// Copy owned metadata, then relocate spans and local typed-table identities.
pub const Mapper = struct {
    segments: []const Segment,
    before: Range,
    after: Range,
    /// Return an independently owned function subtree without borrowing cached storage.
    pub fn copy(self: Mapper, allocator: std.mem.Allocator, comptime T: type, input: T) Error!T {
        const clone: @import("ast_copy.zig").Mapper = .{};
        var output = clone.value(allocator, T, input) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
        try self.relocate(T, &output);
        return output;
    }
    fn relocate(self: Mapper, comptime T: type, value: *T) error{InvalidRelocation}!void {
        if (T == source.Span) {
            var low: usize = 0;
            var high = self.segments.len;
            while (low < high) {
                const middle = low + (high - low) / 2;
                if (self.segments[middle].before.start <= value.start) low = middle + 1 else high = middle;
            }
            if (low == 0) return error.InvalidRelocation;
            const segment = self.segments[low - 1];
            if (value.end < value.start or value.end > segment.before.end) return error.InvalidRelocation;
            value.* = .{ .start = segment.after + value.start - segment.before.start, .end = segment.after + value.end - segment.before.start };
            return;
        }
        if (T == typed.NodeId or T == typed.StatementId) {
            const before = if (T == typed.NodeId) self.before.nodes else self.before.statements;
            const after = if (T == typed.NodeId) self.after.nodes else self.after.statements;
            const id = @backingInt(value.*);
            if (id < before.start or id >= before.end) return error.InvalidRelocation;
            value.* = @fromBackingInt(after.start + id - before.start);
            return;
        }
        switch (@typeInfo(T)) {
            .@"struct" => inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_types) |name, Field| try self.relocate(Field, &@field(value.*, name)),
            .@"union" => inline for (@typeInfo(T).@"union".field_names, @typeInfo(T).@"union".field_types) |name, Field| {
                if (std.meta.activeTag(value.*) == @field(std.meta.Tag(T), name)) try self.relocate(Field, &@field(value.*, name));
            },
            .optional => |optional| if (value.*) |*present| try self.relocate(optional.child, present),
            .pointer => |pointer| {
                if (pointer.size != .slice) @compileError("checked trees require owned slices");
                if (pointer.child != u8) for (@constCast(value.*)) |*item| try self.relocate(pointer.child, item);
            },
            .array => |array| for (value) |*item| try self.relocate(array.child, item),
            .@"enum", .int, .float, .bool, .void => {},
            else => @compileError("checked field needs explicit relocation: " ++ @typeName(T)),
        }
    }
};
/// Map every unchanged source interval, including relocated headers and imported files.
pub fn segments(allocator: std.mem.Allocator, before: []const u8, old: []const source.Span, after: []const u8, current: []const source.Span) error{ OutOfMemory, InternalError }![]const Segment {
    if (old.len != current.len) return error.InternalError;
    const order = try allocator.alloc(usize, old.len);
    defer allocator.free(order);
    for (order, 0..) |*index, i| index.* = i;
    std.mem.sort(usize, order, old, less);
    var result: std.ArrayList(Segment) = .empty;
    var old_start: usize = 0;
    var new_start: usize = 0;
    for (order) |i| {
        try result.append(allocator, .{ .before = .{ .start = old_start, .end = old[i].start }, .after = new_start });
        if (std.mem.eql(u8, before[old[i].start..old[i].end], after[current[i].start..current[i].end]))
            try result.append(allocator, .{ .before = old[i], .after = current[i].start });
        old_start = old[i].end;
        new_start = current[i].end;
    }
    try result.append(allocator, .{ .before = .{ .start = old_start, .end = before.len }, .after = new_start });
    return result.toOwnedSlice(allocator);
}
fn less(bodies: []const source.Span, a: usize, b: usize) bool {
    return bodies[a].start < bodies[b].start;
}
