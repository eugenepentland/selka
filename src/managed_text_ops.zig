//! Python string methods over immutable Unicode text.
//! Every operation reads its receiver and allocates a fresh value, so no alias observes a
//! change. Classification and case mapping cover ASCII; other scalars pass through unchanged
//! rather than pretending to implement full Unicode case folding or property tables.
const std = @import("std");
const gc = @import("gc_heap.zig");
const values = @import("runtime_values.zig");
const text = @import("managed_text.zig");
const number_text = @import("number_text.zig");
const Value = values.Value;
const Type = values.Type;

/// Failures shared with the underlying immutable text operations.
pub const Error = text.Error;

/// Which scalar property `isdigit`, `isalpha` and `isspace` test.
pub const Class = enum { digit, alpha, space };

/// Which ends of the text `strip`, `lstrip` and `rstrip` trim.
pub const Ends = enum { both, leading, trailing };

fn point(value: Value) u32 {
    return @intCast(value.integer.value);
}

fn isSpace(scalar: u32) bool {
    return scalar == ' ' or scalar == '\t' or scalar == '\n' or scalar == '\r' or scalar == 0x0b or scalar == 0x0c;
}

fn classify(scalar: u32, kind: Class) bool {
    return switch (kind) {
        .digit => scalar >= '0' and scalar <= '9',
        .alpha => (scalar >= 'a' and scalar <= 'z') or (scalar >= 'A' and scalar <= 'Z'),
        .space => isSpace(scalar),
    };
}

fn at(haystack: []const Value, start: usize, needle: []const Value) bool {
    if (haystack.len - start < needle.len) return false;
    for (haystack[start..][0..needle.len], needle) |a, b| if (a.integer.value != b.integer.value) return false;
    return true;
}

/// Remove leading and/or trailing whitespace scalars, copying the remainder.
pub fn trim(heap: *gc.Heap, value: Value, ends: Ends) Error!Value {
    const input = try text.object(heap, value);
    const items = input.items.items;
    var lower: usize = 0;
    var upper: usize = items.len;
    if (ends != .trailing) while (lower < upper and isSpace(point(items[lower]))) {
        lower += 1;
    };
    if (ends != .leading) while (upper > lower and isSpace(point(items[upper - 1]))) {
        upper -= 1;
    };
    return text.fromPoints(heap, input.ty, items[lower..upper]);
}

/// Replace every non-overlapping occurrence of a nonempty literal needle.
pub fn replace(heap: *gc.Heap, value: Value, needle: Value, replacement: Value) Error!Value {
    const input = try text.object(heap, value);
    const target = try text.object(heap, needle);
    const insert = try text.object(heap, replacement);
    if (target.items.items.len == 0) return error.EmptySeparator;
    var points: std.ArrayList(Value) = .empty;
    defer points.deinit(heap.allocator);
    var cursor: usize = 0;
    while (cursor < input.items.items.len) {
        if (at(input.items.items, cursor, target.items.items)) {
            try points.appendSlice(heap.allocator, insert.items.items);
            cursor += target.items.items.len;
        } else {
            try points.append(heap.allocator, input.items.items[cursor]);
            cursor += 1;
        }
    }
    return text.fromPoints(heap, input.ty, points.items);
}

/// Report whether the text begins or ends with a literal affix; an empty affix matches.
pub fn edge(heap: *gc.Heap, value: Value, affix: Value, leading: bool) Error!bool {
    const input = try text.object(heap, value);
    const part = try text.object(heap, affix);
    if (part.items.items.len > input.items.items.len) return false;
    const start = if (leading) 0 else input.items.items.len - part.items.items.len;
    return at(input.items.items, start, part.items.items);
}

/// Scalar index of the first occurrence of a nonempty needle, or -1 when absent.
pub fn find(heap: *gc.Heap, value: Value, needle: Value) Error!i64 {
    const input = try text.object(heap, value);
    const target = try text.object(heap, needle);
    if (target.items.items.len == 0) return error.EmptySeparator;
    var cursor: usize = 0;
    while (cursor + target.items.items.len <= input.items.items.len) : (cursor += 1) {
        if (at(input.items.items, cursor, target.items.items)) return @intCast(cursor);
    }
    return -1;
}

/// Count non-overlapping occurrences of a nonempty needle.
pub fn count(heap: *gc.Heap, value: Value, needle: Value) Error!i64 {
    const input = try text.object(heap, value);
    const target = try text.object(heap, needle);
    if (target.items.items.len == 0) return error.EmptySeparator;
    var found: i64 = 0;
    var cursor: usize = 0;
    while (cursor + target.items.items.len <= input.items.items.len) {
        if (at(input.items.items, cursor, target.items.items)) {
            found += 1;
            cursor += target.items.items.len;
        } else cursor += 1;
    }
    return found;
}

/// Map ASCII letters to one case, leaving every other scalar unchanged.
pub fn mapCase(heap: *gc.Heap, value: Value, upper: bool) Error!Value {
    const input = try text.object(heap, value);
    var points: std.ArrayList(Value) = .empty;
    defer points.deinit(heap.allocator);
    for (input.items.items) |item| {
        const scalar = point(item);
        const mapped: u32 = if (upper and scalar >= 'a' and scalar <= 'z')
            scalar - 32
        else if (!upper and scalar >= 'A' and scalar <= 'Z') scalar + 32 else scalar;
        try points.append(heap.allocator, .{ .integer = .{ .ty = .u32, .value = mapped } });
    }
    return text.fromPoints(heap, input.ty, points.items);
}

/// Report whether every scalar has one property; empty text is false, as in Python.
pub fn every(heap: *gc.Heap, value: Value, kind: Class) Error!bool {
    const input = try text.object(heap, value);
    if (input.items.items.len == 0) return false;
    for (input.items.items) |item| if (!classify(point(item), kind)) return false;
    return true;
}

/// Split on `\n`, `\r` and `\r\n` without keeping the terminators; empty text yields no lines.
pub fn splitLines(heap: *gc.Heap, list_type: Type, value: Value) Error!Value {
    const input = try text.object(heap, value);
    const items = input.items.items;
    const result = try heap.create(list_type, input.ty, 0);
    errdefer result.release(heap.allocator);
    var start: usize = 0;
    var cursor: usize = 0;
    while (cursor < items.len) {
        const scalar = point(items[cursor]);
        if (scalar != '\n' and scalar != '\r') {
            cursor += 1;
            continue;
        }
        try appendPiece(heap, result, input.ty, items[start..cursor]);
        cursor += 1;
        if (scalar == '\r' and cursor < items.len and point(items[cursor]) == '\n') cursor += 1;
        start = cursor;
    }
    if (start < items.len) try appendPiece(heap, result, input.ty, items[start..]);
    return result;
}

fn appendPiece(heap: *gc.Heap, result: Value, ty: Type, points: []const Value) Error!void {
    const piece = try text.fromPoints(heap, ty, points);
    defer piece.release(heap.allocator);
    try heap.append(result, piece);
}

/// Left-pad with `0` to a minimum scalar width, keeping any leading sign in front.
pub fn zfill(heap: *gc.Heap, value: Value, width: i128) Error!Value {
    const input = try text.object(heap, value);
    const items = input.items.items;
    const target: usize = if (width <= 0) 0 else @intCast(@min(width, @as(i128, std.math.maxInt(u32))));
    if (items.len >= target) return text.fromPoints(heap, input.ty, items);
    const signed = items.len != 0 and (point(items[0]) == '+' or point(items[0]) == '-');
    var points: std.ArrayList(Value) = .empty;
    defer points.deinit(heap.allocator);
    if (signed) try points.append(heap.allocator, items[0]);
    for (0..target - items.len) |_| try points.append(heap.allocator, .{ .integer = .{ .ty = .u32, .value = '0' } });
    try points.appendSlice(heap.allocator, items[@intFromBool(signed)..]);
    return text.fromPoints(heap, input.ty, points.items);
}

/// Parse the whole text as a decimal integer under the pinned grammar, or null
/// when it is not exactly one number or leaves the signed 64-bit range.
pub fn parseInteger(heap: *gc.Heap, value: Value) Error!?i64 {
    const scalars = try pointsOf(heap, value);
    defer heap.allocator.free(scalars);
    return number_text.integer(scalars);
}

/// Parse the whole text as one binary64 value under the pinned grammar, or null
/// when it is not exactly one number. The native runtime calls the same parser.
pub fn parseFloat(heap: *gc.Heap, value: Value) Error!?f64 {
    const scalars = try pointsOf(heap, value);
    defer heap.allocator.free(scalars);
    return number_text.floating(scalars);
}

/// Copy the receiver's scalar values out for the shared grammar to read.
fn pointsOf(heap: *gc.Heap, value: Value) Error![]u32 {
    const input = try text.object(heap, value);
    const scalars = try heap.allocator.alloc(u32, input.items.items.len);
    for (input.items.items, scalars) |item, *scalar| scalar.* = point(item);
    return scalars;
}
