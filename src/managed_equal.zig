//! Structural managed-data equality using an explicit worklist for cycles.
const std = @import("std");
const values = @import("runtime_values.zig");
const gc = @import("gc_heap.zig");
const dict = @import("managed_dict.zig");
const text = @import("managed_text.zig");
const byte_strings = @import("managed_bytes.zig");
const Value = values.Value;
const Record = @import("typed.zig").Record;
const Pair = struct { left: Value, right: Value };
const IdentityPair = struct { left: usize, right: usize };
pub const Error = dict.Error;

/// Compare managed contents, ignoring dictionary insertion order and alias layout.
pub fn equal(heap: *gc.Heap, left: Value, right: Value) Error!bool {
    return equalWithRecords(heap, left, right, &.{});
}

/// Compare contents with the catalog needed to recognize builtin floating domains.
pub fn equalWithRecords(heap: *gc.Heap, left: Value, right: Value, records: []const Record) Error!bool {
    var pending: std.ArrayList(Pair) = .empty;
    defer pending.deinit(heap.allocator);
    var visited: std.AutoHashMapUnmanaged(IdentityPair, void) = .empty;
    defer visited.deinit(heap.allocator);
    try pending.append(heap.allocator, .{ .left = left, .right = right });
    var work: usize = 0;
    while (pending.pop()) |pair| {
        work += 1;
        if (work > 100000) return error.CapacityLimit;
        if (pair.left.typeOf() != pair.right.typeOf()) return false;
        if (std.meta.activeTag(pair.left) != std.meta.activeTag(pair.right)) return false;
        if (floatingPair(pair, records)) |same| {
            if (!same) return false;
            continue;
        }
        switch (pair.left) {
            .unit => {},
            .i64 => if (pair.left.i64 != pair.right.i64) return false,
            .bool => if (pair.left.bool != pair.right.bool) return false,
            .integer => if (pair.left.integer.value != pair.right.integer.value) return false,
            .managed => if (!try managedPair(heap, pair, &pending, &visited)) return false,
            .aggregate => |a| {
                if (pair.right != .aggregate) return false;
                const b = pair.right.aggregate;
                if (a.active_tag != b.active_tag or a.fields.len != b.fields.len) return false;
                if (a.moved_fields != null or b.moved_fields != null) return error.InvalidDataValue;
                if ((try visited.getOrPut(heap.allocator, .{ .left = @intFromPtr(a), .right = @intFromPtr(b) })).found_existing) continue;
                for (a.fields, b.fields) |x, y| try pending.append(heap.allocator, .{ .left = x, .right = y });
            },
            else => return error.InvalidDataValue,
        }
    }
    return true;
}
/// Membership searches dictionary keys, list values, or contiguous string codepoints.
pub fn contains(heap: *gc.Heap, container: Value, needle: Value) Error!bool {
    return containsWithRecords(heap, container, needle, &.{});
}

/// Search contents using the same scalar semantics as catalog-aware equality.
pub fn containsWithRecords(heap: *gc.Heap, container: Value, needle: Value, records: []const Record) Error!bool {
    if (container != .managed) return error.TypeMismatch;
    try heap.validateElement(container);
    switch (container.managed.collection.kind) {
        .dictionary => return dict.contains(heap, container, needle),
        .list => {
            if (needle.typeOf() != container.managed.element_type) return error.TypeMismatch;
            for (container.managed.items.items) |item| if (try equalWithRecords(heap, item, needle, records)) return true;
            return false;
        },
        .bytes => return byte_strings.contains(heap, container, needle) catch |err| switch (err) {
            error.ByteRange, error.InvalidHex => error.InvalidDataValue,
            else => |other| other,
        },
        .string => {
            const part = try text.object(heap, needle);
            const haystack = container.managed.items.items;
            if (part.items.items.len > haystack.len) return false;
            var start: usize = 0;
            while (start <= haystack.len - part.items.items.len) : (start += 1) {
                var matched = true;
                for (part.items.items, haystack[start..][0..part.items.items.len]) |a, b| if (a.integer.value != b.integer.value) {
                    matched = false;
                    break;
                };
                if (matched) return true;
            }
            return false;
        },
    }
}

fn managedPair(heap: *gc.Heap, pair: Pair, pending: *std.ArrayList(Pair), visited: *std.AutoHashMapUnmanaged(IdentityPair, void)) Error!bool {
    const a = pair.left.managed;

    if (pair.right != .managed) return false;
    const b = pair.right.managed;
    try heap.validateElement(pair.left);
    try heap.validateElement(pair.right);
    if (a.collection.kind != b.collection.kind) return false;
    if (a.items.items.len != b.items.items.len) return false;
    if ((try visited.getOrPut(heap.allocator, .{ .left = @intFromPtr(a), .right = @intFromPtr(b) })).found_existing) return true;
    if (a.collection.kind == .dictionary) {
        var index: usize = 0;
        while (index < a.items.items.len) : (index += 2) {
            const other = dict.read(heap, pair.right, a.items.items[index]) catch |err| switch (err) {
                error.MissingKey => return false,
                else => return err,
            };
            defer other.release(heap.allocator);
            try pending.append(heap.allocator, .{ .left = a.items.items[index + 1], .right = other });
        }
    } else for (a.items.items, b.items.items) |x, y| try pending.append(heap.allocator, .{ .left = x, .right = y });
    return true;
}

fn floatingPair(pair: Pair, records: []const Record) ?bool {
    const ty = pair.left.typeOf();
    if (pair.left != .aggregate or ty.recordIndex() >= records.len) return null;
    if (!@import("numeric_surface.zig").isFloat(ty, records)) return null;
    const left: f64 = @bitCast(@as(u64, @intCast(pair.left.aggregate.fields[0].integer.value)));
    const right: f64 = @bitCast(@as(u64, @intCast(pair.right.aggregate.fields[0].integer.value)));
    return left == right;
}
