//! Owned reflective body adoption with the existing logical codec budgets.
const std = @import("std");
const logical = @import("parser_value.zig");
const Budget = struct {
    rows: usize = 0,
    edges: usize = 0,
    wire: usize = 16,
    memory: usize = 0,
    visits: usize = 0,
    output_memory: usize = 0,
    zero_requirement: usize = 0,

    fn allocate(self: *Budget, bytes: usize) logical.Error!void {
        if (bytes > 512 * 1024 * 1024 - self.memory) return error.ComponentProtocol;
        self.memory += bytes;
    }
    fn row(self: *Budget, data: usize, children: usize, names: []const []const u8) logical.Error!void {
        if (self.rows >= logical.ValueProfile.body.rows() or children > logical.max_edges - self.edges) return error.ComponentProtocol;
        self.rows += 1;
        self.edges += children;
        if (data > logical.value_wire_limit) return error.ComponentProtocol;
        var size: usize = 21 + data + children * 4;
        for (names) |name| {
            if (name.len == 0 or name.len > 64) return error.ComponentProtocol;
            size += 4 + name.len;
        }
        if (size > logical.value_wire_limit - self.wire) return error.ComponentProtocol;
        self.wire += size;
        try self.allocate(logical.value_table_row_size + children * @sizeOf(u32) + names.len * @sizeOf([]const u8));
    }
    fn value(self: *Budget, comptime T: type, item: T, depth: usize) logical.Error!void {
        if (depth > 256 or self.visits == 4194304) return error.ComponentProtocol;
        self.visits += 1;
        switch (@typeInfo(T)) {
            .void, .bool => try self.row(0, 0, &.{}),
            .int => {
                if (std.math.cast(i64, item) == null) {
                    if (T != i128 or std.math.cast(u64, item) == null) return error.ComponentProtocol;
                }
                try self.row(0, 0, &.{});
            },
            .@"enum" => |info| {
                if (info.mode == .nonexhaustive) {
                    const integer = std.math.cast(i64, @backingInt(item)) orelse return error.ComponentProtocol;
                    if (integer < 0) return error.ComponentProtocol;
                    try self.row(0, 0, &.{});
                } else try self.row(@tagName(item).len, 0, &.{});
            },
            .optional => |info| {
                if (item) |present| try self.value(info.child, present, depth + 1) else try self.row(0, 0, &.{});
            },
            .pointer => |info| {
                if (info.size != .slice) @compileError("owned body values require slices");
                if (item.len > logical.ValueProfile.body.rows() and info.child != u8) return error.ComponentProtocol;
                if (item.len > (512 * 1024 * 1024) / @max(1, @sizeOf(info.child))) return error.ComponentProtocol;
                if (@sizeOf(info.child) == 0) self.zero_requirement = @max(self.zero_requirement, self.output_memory + item.len);
                const bytes = item.len * @sizeOf(info.child);
                if (bytes > 512 * 1024 * 1024 - self.output_memory) return error.ComponentProtocol;
                self.output_memory += bytes;
                if (info.child == u8) return self.row(item.len, 0, &.{});
                for (item) |child| try self.value(info.child, child, depth + 1);
                try self.row(0, item.len, &.{});
            },
            .array => |info| {
                for (item) |child| try self.value(info.child, child, depth + 1);
                try self.row(0, info.len, &.{});
            },
            .@"struct" => |info| {
                if (info.field_names.len > 8) return error.ComponentProtocol;
                inline for (info.field_names, info.field_types) |name, Field| try self.value(Field, @field(item, name), depth + 1);
                var names: [info.field_names.len][]const u8 = undefined;
                inline for (info.field_names, 0..) |name, index| names[index] = name;
                try self.row(0, info.field_names.len, &names);
            },
            .@"union" => |info| {
                inline for (info.field_names, info.field_types) |name, Field| {
                    if (std.mem.eql(u8, @tagName(item), name)) {
                        try self.value(Field, @field(item, name), depth + 1);
                        return self.row(name.len, 1, &.{});
                    }
                }
                unreachable;
            },
            else => @compileError("unsupported owned body shape " ++ @typeName(T)),
        }
    }
};

fn release(a: std.mem.Allocator, comptime T: type, item: T) void {
    switch (@typeInfo(T)) {
        .pointer => |info| {
            if (info.child != u8) for (item) |child| release(a, info.child, child);
            a.free(item);
        },
        .optional => |info| if (item) |present| {
            release(a, info.child, present);
        },
        .array => |info| for (item) |child| release(a, info.child, child),
        .@"struct" => |info| inline for (info.field_names, info.field_types) |name, Field| release(a, Field, @field(item, name)),
        .@"union" => |info| inline for (info.field_names, info.field_types) |name, Field| {
            if (std.mem.eql(u8, @tagName(item), name)) {
                release(a, Field, @field(item, name));
                return;
            }
        },
        else => {},
    }
}
fn owned(a: std.mem.Allocator, comptime T: type, item: T) logical.Error!T {
    switch (@typeInfo(T)) {
        .pointer => |info| {
            const result = try a.alloc(info.child, item.len);
            if (info.child == u8) {
                @memcpy(result, item);
                return result;
            }
            var initialized: usize = 0;
            errdefer {
                for (result[0..initialized]) |child| release(a, info.child, child);
                a.free(result);
            }
            for (item, result) |child, *out| {
                out.* = try owned(a, info.child, child);
                initialized += 1;
            }
            return result;
        },
        .optional => |info| return if (item) |present| try owned(a, info.child, present) else null,
        .array => |info| {
            var result: T = undefined;
            var initialized: usize = 0;
            errdefer for (result[0..initialized]) |child| release(a, info.child, child);
            for (item, &result) |child, *out| {
                out.* = try owned(a, info.child, child);
                initialized += 1;
            }
            return result;
        },
        .@"struct" => |info| {
            var result: T = undefined;
            var initialized: usize = 0;
            errdefer inline for (info.field_names, info.field_types, 0..) |name, Field, index| {
                if (index < initialized) release(a, Field, @field(result, name));
            };
            inline for (info.field_names, info.field_types) |name, Field| {
                @field(result, name) = try owned(a, Field, @field(item, name));
                initialized += 1;
            }
            return result;
        },
        .@"union" => |info| {
            inline for (info.field_names, info.field_types) |name, Field| {
                if (std.mem.eql(u8, @tagName(item), name)) return @unionInit(T, name, try owned(a, Field, @field(item, name)));
            }
            unreachable;
        },
        else => return item,
    }
}
/// Copy an already validated typed body without changing codec admission limits.
/// Partial allocations are released on failure; successful storage belongs to a.
pub fn clone(a: std.mem.Allocator, comptime T: type, item: T) logical.Error!T {
    @setEvalBranchQuota(200000);
    var budget: Budget = .{};
    try budget.value(T, item, 0);
    if (@max(budget.output_memory, budget.zero_requirement) > 512 * 1024 * 1024 - budget.memory) return error.ComponentProtocol;
    return owned(a, T, item);
}

const FailureSample = struct { name: []const u8, nested: []const ?[]const u8, choice: union(enum) { absent: void, values: []const i64 } };
fn allocationCleanup(a: std.mem.Allocator) !void {
    const item: FailureSample = .{ .name = "owner", .nested = &.{ "first", null, "last" }, .choice = .{ .values = &.{ 1, 2 } } };
    const result = try clone(a, FailureSample, item);
    defer release(a, FailureSample, result);
    try std.testing.expectEqualStrings("last", result.nested[2].?);
}
// spec-case: SELFHOST-BODY-OWNED-COPY-1
test "body owned copy rolls back nested allocations with a general allocator" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCleanup, .{});
}
