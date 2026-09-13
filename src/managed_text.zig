//! Immutable Unicode text backed by traced scalar values, independent of bytes.
const std = @import("std");
const gc = @import("gc_heap.zig");
const values = @import("runtime_values.zig");
const Value = values.Value;
const Type = values.Type;
pub const Error = gc.Error || error{ InvalidUtf8, EmptySeparator };

/// Validate a text value and its execution-local identity.
pub fn object(heap: *gc.Heap, value: Value) Error!*values.ManagedObject {
    if (value != .managed or value.managed.collection.kind != .string) return error.TypeMismatch;
    if (value.managed.heap != @as(*anyopaque, @ptrCast(heap))) return error.ForeignMemory;
    return value.managed;
}
/// Decode valid UTF-8 into immutable Unicode scalar values.
pub fn create(heap: *gc.Heap, ty: Type, bytes: []const u8) Error!Value {
    const view = std.unicode.Utf8View.init(bytes) catch return error.InvalidUtf8;
    var iter = view.iterator();
    var count: usize = 0;
    while (iter.nextCodepoint() != null) count += 1;
    const result = try heap.create(ty, .u32, count);
    errdefer result.release(heap.allocator);
    iter = view.iterator();
    while (iter.nextCodepoint()) |point| try heap.append(result, .{ .integer = .{ .ty = .u32, .value = point } });
    result.managed.collection.kind = .string;
    return result;
}
/// Return Unicode scalar count; combining marks remain separate codepoints.
pub fn len(heap: *gc.Heap, value: Value) Error!usize {
    return (try object(heap, value)).items.items.len;
}
/// Return caller-owned UTF-8 bytes for an explicit host/byte boundary.
pub fn encode(heap: *gc.Heap, value: Value) Error![]u8 {
    const text = try object(heap, value);
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(heap.allocator);
    for (text.items.items) |point| {
        var buffer: [4]u8 = undefined;
        const size = std.unicode.utf8Encode(@intCast(point.integer.value), &buffer) catch return error.InvalidUtf8;
        try output.appendSlice(heap.allocator, buffer[0..size]);
    }
    return output.toOwnedSlice(heap.allocator);
}
/// Compare codepoints without Unicode normalization or locale folding.
pub fn equal(heap: *gc.Heap, left: Value, right: Value) Error!bool {
    const a = try object(heap, left);
    const b = try object(heap, right);
    if (a.items.items.len != b.items.items.len) return false;
    for (a.items.items, b.items.items) |x, y| if (x.integer.value != y.integer.value) return false;
    return true;
}
fn fromPoints(heap: *gc.Heap, ty: Type, points: []const Value) Error!Value {
    const result = try heap.create(ty, .u32, points.len);
    errdefer result.release(heap.allocator);
    for (points) |point| try heap.append(result, point);
    result.managed.collection.kind = .string;
    return result;
}
/// Concatenate without mutating either operand or any of its aliases.
pub fn concat(heap: *gc.Heap, left: Value, right: Value) Error!Value {
    const a = try object(heap, left);
    const b = try object(heap, right);
    if (a.ty != b.ty) return error.TypeMismatch;
    const count = std.math.add(usize, a.items.items.len, b.items.items.len) catch return error.CapacityLimit;
    const result = try heap.create(a.ty, .u32, count);
    errdefer result.release(heap.allocator);
    for (a.items.items) |point| try heap.append(result, point);
    for (b.items.items) |point| try heap.append(result, point);
    result.managed.collection.kind = .string;
    return result;
}
/// Index text by Unicode scalar, including Python-style negative indices.
pub fn at(heap: *gc.Heap, value: Value, index: i128) Error!Value {
    const text = try object(heap, value);
    const offset = if (index < 0) @as(i128, text.items.items.len) + index else index;
    if (offset < 0 or offset >= text.items.items.len) return error.Bounds;
    const start: usize = @intCast(offset);
    return fromPoints(heap, text.ty, text.items.items[start .. start + 1]);
}
fn matches(haystack: []const Value, needle: []const Value) bool {
    if (haystack.len < needle.len) return false;
    for (haystack[0..needle.len], needle) |a, b| if (a.integer.value != b.integer.value) return false;
    return true;
}
/// Split by a nonempty literal separator, preserving leading/trailing empties.
pub fn split(heap: *gc.Heap, list_type: Type, value: Value, separator: Value) Error!Value {
    const text = try object(heap, value);
    const sep = try object(heap, separator);
    if (sep.ty != text.ty) return error.TypeMismatch;
    if (sep.items.items.len == 0) return error.EmptySeparator;
    const result = try heap.create(list_type, text.ty, 0);
    errdefer result.release(heap.allocator);
    var start: usize = 0;
    var cursor: usize = 0;
    while (cursor <= text.items.items.len) {
        if (cursor == text.items.items.len or matches(text.items.items[cursor..], sep.items.items)) {
            const piece = try fromPoints(heap, text.ty, text.items.items[start..cursor]);
            defer piece.release(heap.allocator);
            try heap.append(result, piece);
            if (cursor == text.items.items.len) break;
            cursor += sep.items.items.len;
            start = cursor;
        } else cursor += 1;
    }
    return result;
}
/// Join a list of strings using the receiver as separator.
pub fn join(heap: *gc.Heap, separator: Value, list: Value) Error!Value {
    const sep = try object(heap, separator);
    if (list != .managed or list.managed.collection.kind != .list or list.managed.element_type != sep.ty) return error.TypeMismatch;
    if (list.managed.heap != @as(*anyopaque, @ptrCast(heap))) return error.ForeignMemory;
    var count: usize = 0;
    for (list.managed.items.items, 0..) |item, i| {
        const text = try object(heap, item);
        count = std.math.add(usize, count, text.items.items.len) catch return error.CapacityLimit;
        if (i != 0) count = std.math.add(usize, count, sep.items.items.len) catch return error.CapacityLimit;
    }
    const result = try heap.create(sep.ty, .u32, count);
    errdefer result.release(heap.allocator);
    for (list.managed.items.items, 0..) |item, i| {
        if (i != 0) for (sep.items.items) |point| try heap.append(result, point);
        for (item.managed.items.items) |point| try heap.append(result, point);
    }
    result.managed.collection.kind = .string;
    return result;
}

/// Format scalar values using Python spellings; float inputs carry native bits.
pub fn convert(heap: *gc.Heap, ty: Type, value: Value, floating: bool) Error!Value {
    if (value == .managed) {
        _ = try object(heap, value);
        if (value.typeOf() != ty) return error.TypeMismatch;
        return value.retain();
    }
    if (value == .unit) return create(heap, ty, "None");
    if (value == .bool) return create(heap, ty, if (value.bool) "True" else "False");
    const bytes = if (floating) formatted: {
        if (value != .aggregate or value.aggregate.fields.len != 1) return error.TypeMismatch;
        const bits = value.aggregate.fields[0].asInteger() catch return error.TypeMismatch;
        const number: f64 = @bitCast(@as(u64, @intCast(bits)));
        if (std.math.isNan(number)) return create(heap, ty, "nan");
        if (std.math.isInf(number)) return create(heap, ty, if (number < 0) "-inf" else "inf");
        break :formatted try std.fmt.allocPrint(heap.allocator, "{d}", .{number});
    } else formatted: {
        const number = value.asInteger() catch return error.TypeMismatch;
        break :formatted try std.fmt.allocPrint(heap.allocator, "{d}", .{number});
    };
    defer heap.allocator.free(bytes);
    if (floating and std.mem.indexOfAny(u8, bytes, ".eE") == null) {
        const suffixed = try std.fmt.allocPrint(heap.allocator, "{s}.0", .{bytes});
        defer heap.allocator.free(suffixed);
        return create(heap, ty, suffixed);
    }
    return create(heap, ty, bytes);
}

/// Copy a Unicode slice with Python-style negative and clamped endpoints.
pub fn slice(heap: *gc.Heap, value: Value, start: i128, end: i128) Error!Value {
    const input = try object(heap, value);
    const count: i128 = input.items.items.len;
    const lower: usize = @intCast(std.math.clamp(if (start < 0) count + start else start, 0, count));
    const upper: usize = @intCast(std.math.clamp(if (end < 0) count + end else end, 0, count));
    return fromPoints(heap, input.ty, input.items.items[lower..@max(lower, upper)]);
}
