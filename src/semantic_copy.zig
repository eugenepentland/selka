//! Relocate owned checked function trees into a fresh compilation's source,
//! declaration and catalog identity space.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
/// Source interval whose bytes are unchanged at a new offset.
pub const Segment = struct { before: source.Span, after: usize };
/// Contiguous expression/statement IDs belonging to one checked function.
pub const Range = struct { nodes: source.Span, statements: source.Span };
/// Validation failures indicate a cache miss, never a trusted unchecked identity.
pub const Error = error{ OutOfMemory, InternalError, InvalidRelocation };

/// Declaration references found in one checked function tree. Old numeric ids
/// are exchanged for stable identities by the caller; the map only accumulates
/// the ordinal positions that need remapping.
pub const RefSet = struct {
    allocator: std.mem.Allocator,
    functions: std.AutoHashMapUnmanaged(usize, void) = .empty,
    records: std.AutoHashMapUnmanaged(usize, void) = .empty,
    /// True when the tree stores or invokes a callable value, whose inferred
    /// contract is not yet a stable dependency fact for C1.
    callbacks: bool = false,

    /// Initialize an accumulator tied to one allocator.
    pub fn init(allocator: std.mem.Allocator) RefSet {
        return .{ .allocator = allocator };
    }
    /// Release accumulator storage. The caller retains every referenced key.
    pub fn deinit(self: *RefSet) void {
        self.functions.deinit(self.allocator);
        self.records.deinit(self.allocator);
    }
    /// Record one declaration reference, recursing through owned value shapes.
    pub fn collect(self: *RefSet, comptime T: type, value: T) error{OutOfMemory}!void {
        if (T == typed.FunctionId) {
            try self.functions.put(self.allocator, @backingInt(value), {});
            return;
        }
        if (T == typed.Type) {
            if (value.isAggregate()) try self.records.put(self.allocator, value.recordIndex(), {});
            return;
        }
        switch (@typeInfo(T)) {
            .@"struct" => inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_types) |field_name, Field| {
                try self.collect(Field, @field(value, field_name));
            },
            .@"union" => inline for (@typeInfo(T).@"union".field_names, @typeInfo(T).@"union".field_types) |field_name, Field| {
                if (std.meta.activeTag(value) == @field(std.meta.Tag(T), field_name)) try self.collect(Field, @field(value, field_name));
            },
            .optional => |optional| if (value) |present| try self.collect(optional.child, present),
            .pointer => |pointer| {
                if (pointer.size != .slice or pointer.child == u8) return;
                for (value) |item| try self.collect(pointer.child, item);
            },
            .array => |array| for (value) |item| try self.collect(array.child, item),
            else => {},
        }
    }
};

/// Collect every function/type reference from one checked function, its node
/// range and its statement range. The copy mapper visits exactly the same value
/// shape, so a reference that is absent from the set is a relocation miss.
pub fn collectRefs(allocator: std.mem.Allocator, function: typed.Function, nodes: []const typed.Node, statements: []const typed.Statement, refs: *RefSet) error{ OutOfMemory, InternalError }!void {
    refs.allocator = allocator;
    refs.collect(typed.Function, function) catch return error.OutOfMemory;
    refs.collect([]const typed.Node, nodes) catch return error.OutOfMemory;
    refs.collect([]const typed.Statement, statements) catch return error.OutOfMemory;
    for (nodes) |node| switch (node.data) {
        .function_value, .invoke => refs.callbacks = true,
        else => {},
    };
}

/// Copy owned metadata, then relocate spans, local table identities and
/// declaration/catalog references into the fresh compilation.
pub const Mapper = struct {
    segments: []const Segment,
    before: Range,
    after: Range,
    /// Old FunctionId ordinal -> remapped identity, or null when ambiguous.
    functions: []const ?typed.FunctionId = &.{},
    /// Old record ordinal -> remapped aggregate type, or null when ambiguous.
    records: []const ?typed.Type = &.{},
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
        if (T == typed.FunctionId) {
            const id = @backingInt(value.*);
            if (id >= self.functions.len) return error.InvalidRelocation;
            value.* = self.functions[id] orelse return error.InvalidRelocation;
            return;
        }
        if (T == typed.Type) {
            if (!value.isAggregate()) return;
            const index = value.recordIndex();
            if (index >= self.records.len) return error.InvalidRelocation;
            value.* = self.records[index] orelse return error.InvalidRelocation;
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
/// Retained for callers that relocate whole-program syntax snapshots; per-function
/// reuse uses a single declaration-region segment instead.
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
