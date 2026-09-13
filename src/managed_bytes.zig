//! Immutable managed byte strings: traced u8 elements with stable GC identity.
const std = @import("std");
const gc = @import("gc_heap.zig");
const values = @import("runtime_values.zig");
const text = @import("managed_text.zig");
const Value = values.Value;
const Type = values.Type;
/// Failures returned by byte-string operations, including located guest traps.
pub const Error = text.Error || error{ ByteRange, InvalidHex };

/// Validate a byte-string value and its execution-local identity.
pub fn object(heap: *gc.Heap, value: Value) Error!*values.ManagedObject {
    if (value != .managed or value.managed.collection.kind != .bytes) return error.TypeMismatch;
    if (value.managed.heap != @as(*anyopaque, @ptrCast(heap))) return error.ForeignMemory;
    return value.managed;
}
fn fromBytes(heap: *gc.Heap, ty: Type, input: []const u8) Error!Value {
    const result = try heap.create(ty, .u8, input.len);
    errdefer result.release(heap.allocator);
    for (input) |byte| try heap.append(result, Value.number(.u8, byte));
    result.managed.collection.kind = .bytes;
    return result;
}
fn fromItems(heap: *gc.Heap, ty: Type, items: []const Value) Error!Value {
    const result = try heap.create(ty, .u8, items.len);
    errdefer result.release(heap.allocator);
    for (items) |item| try heap.append(result, item);
    result.managed.collection.kind = .bytes;
    return result;
}
/// Copy host bytes into a fresh immutable managed byte string.
pub fn create(heap: *gc.Heap, ty: Type, input: []const u8) Error!Value {
    return fromBytes(heap, ty, input);
}
/// Return the byte count shared by every alias.
pub fn len(heap: *gc.Heap, value: Value) Error!usize {
    return (try object(heap, value)).items.items.len;
}
/// Return caller-owned host bytes for an explicit boundary crossing.
pub fn toOwned(heap: *gc.Heap, value: Value) Error![]u8 {
    const input = try object(heap, value);
    const output = try heap.allocator.alloc(u8, input.items.items.len);
    errdefer heap.allocator.free(output);
    for (input.items.items, output) |item, *byte| byte.* = @intCast(item.integer.value);
    return output;
}
/// Compare byte content; aliases and capacity never affect the result.
pub fn equal(heap: *gc.Heap, left: Value, right: Value) Error!bool {
    const a = try object(heap, left);
    const b = try object(heap, right);
    if (a.items.items.len != b.items.items.len) return false;
    for (a.items.items, b.items.items) |x, y| if (x.integer.value != y.integer.value) return false;
    return true;
}
// twin-drift-ok: byte strings store u8 items while text stores u32 code points
/// Concatenate without mutating either operand or any of its aliases.
pub fn concat(heap: *gc.Heap, left: Value, right: Value) Error!Value {
    const a = try object(heap, left);
    const b = try object(heap, right);
    if (a.ty != b.ty) return error.TypeMismatch;
    const count = std.math.add(usize, a.items.items.len, b.items.items.len) catch return error.CapacityLimit;
    const result = try heap.create(a.ty, .u8, count);
    errdefer result.release(heap.allocator);
    for (a.items.items) |byte| try heap.append(result, byte);
    for (b.items.items) |byte| try heap.append(result, byte);
    result.managed.collection.kind = .bytes;
    return result;
}
/// Read one byte as an unsigned scalar, accepting Python-style negative indices.
pub fn at(heap: *gc.Heap, value: Value, index: i128) Error!Value {
    const input = try object(heap, value);
    const offset = if (index < 0) @as(i128, input.items.items.len) + index else index;
    if (offset < 0 or offset >= input.items.items.len) return error.Bounds;
    return input.items.items[@intCast(offset)];
}
/// Copy a byte range with Python-style negative and clamped endpoints.
pub fn slice(heap: *gc.Heap, value: Value, start: i128, end: i128) Error!Value {
    const input = try object(heap, value);
    const count: i128 = input.items.items.len;
    const lower: usize = @intCast(std.math.clamp(if (start < 0) count + start else start, 0, count));
    const upper: usize = @intCast(std.math.clamp(if (end < 0) count + end else end, 0, count));
    return fromItems(heap, input.ty, input.items.items[lower..@max(lower, upper)]);
}
fn matches(haystack: []const Value, needle: []const Value) bool {
    if (haystack.len < needle.len) return false;
    for (haystack[0..needle.len], needle) |a, b| if (a.integer.value != b.integer.value) return false;
    return true;
}
/// Return the first index of a byte subsequence, or -1 when it is absent.
pub fn find(heap: *gc.Heap, value: Value, needle: Value) Error!i64 {
    const input = try object(heap, value);
    const part = try object(heap, needle);
    if (part.items.items.len > input.items.items.len) return -1;
    var start: usize = 0;
    while (start + part.items.items.len <= input.items.items.len) : (start += 1) {
        if (matches(input.items.items[start..], part.items.items)) return @intCast(start);
    }
    return -1;
}
/// Test a leading byte subsequence without allocating a slice.
pub fn startsWith(heap: *gc.Heap, value: Value, prefix: Value) Error!bool {
    const input = try object(heap, value);
    const part = try object(heap, prefix);
    return matches(input.items.items, part.items.items);
}
/// Test a trailing byte subsequence without allocating a slice.
pub fn endsWith(heap: *gc.Heap, value: Value, suffix: Value) Error!bool {
    const input = try object(heap, value);
    const part = try object(heap, suffix);
    if (part.items.items.len > input.items.items.len) return false;
    return matches(input.items.items[input.items.items.len - part.items.items.len ..], part.items.items);
}
/// Membership over a byte scalar or a contiguous byte subsequence.
pub fn contains(heap: *gc.Heap, container: Value, needle: Value) Error!bool {
    const input = try object(heap, container);
    if (needle == .managed) return (try find(heap, container, needle)) >= 0;
    const wanted = needle.asInteger() catch return error.TypeMismatch;
    for (input.items.items) |byte| if (byte.integer.value == wanted) return true;
    return false;
}
// twin-drift-ok: byte separators compare u8 items and rebuild byte pieces
/// Split by a nonempty literal separator, preserving leading and trailing empties.
pub fn split(heap: *gc.Heap, list_type: Type, value: Value, separator: Value) Error!Value {
    const input = try object(heap, value);
    const sep = try object(heap, separator);
    if (sep.ty != input.ty) return error.TypeMismatch;
    if (sep.items.items.len == 0) return error.EmptySeparator;
    const result = try heap.create(list_type, input.ty, 0);
    errdefer result.release(heap.allocator);
    var start: usize = 0;
    var cursor: usize = 0;
    while (cursor <= input.items.items.len) {
        if (cursor == input.items.items.len or matches(input.items.items[cursor..], sep.items.items)) {
            const piece = try fromItems(heap, input.ty, input.items.items[start..cursor]);
            defer piece.release(heap.allocator);
            try heap.append(result, piece);
            if (cursor == input.items.items.len) break;
            cursor += sep.items.items.len;
            start = cursor;
        } else cursor += 1;
    }
    return result;
}
// twin-drift-ok: byte joins size and copy u8 items, not code points
/// Join a list of byte strings using the receiver as separator.
pub fn join(heap: *gc.Heap, separator: Value, list: Value) Error!Value {
    const sep = try object(heap, separator);
    if (list != .managed or list.managed.collection.kind != .list or list.managed.element_type != sep.ty) return error.TypeMismatch;
    if (list.managed.heap != @as(*anyopaque, @ptrCast(heap))) return error.ForeignMemory;
    var count: usize = 0;
    for (list.managed.items.items, 0..) |item, i| {
        const part = try object(heap, item);
        count = std.math.add(usize, count, part.items.items.len) catch return error.CapacityLimit;
        if (i != 0) count = std.math.add(usize, count, sep.items.items.len) catch return error.CapacityLimit;
    }
    const result = try heap.create(sep.ty, .u8, count);
    errdefer result.release(heap.allocator);
    for (list.managed.items.items, 0..) |item, i| {
        if (i != 0) for (sep.items.items) |byte| try heap.append(result, byte);
        for (item.managed.items.items) |byte| try heap.append(result, byte);
    }
    result.managed.collection.kind = .bytes;
    return result;
}
/// Build a byte string from a managed integer list, trapping outside 0..255.
pub fn fromList(heap: *gc.Heap, ty: Type, list: Value) Error!Value {
    if (list != .managed or list.managed.collection.kind != .list) return error.TypeMismatch;
    if (list.managed.heap != @as(*anyopaque, @ptrCast(heap))) return error.ForeignMemory;
    const result = try heap.create(ty, .u8, list.managed.items.items.len);
    errdefer result.release(heap.allocator);
    for (list.managed.items.items) |item| {
        const number = item.asInteger() catch return error.TypeMismatch;
        if (number < 0 or number > 255) return error.ByteRange;
        try heap.append(result, Value.number(.u8, number));
    }
    result.managed.collection.kind = .bytes;
    return result;
}
/// Copy the bytes into a fresh managed list of signed integers.
pub fn toList(heap: *gc.Heap, list_type: Type, value: Value) Error!Value {
    const input = try object(heap, value);
    const result = try heap.create(list_type, .i64, input.items.items.len);
    errdefer result.release(heap.allocator);
    for (input.items.items) |byte| try heap.append(result, .{ .i64 = @intCast(byte.integer.value) });
    return result;
}
/// Encode managed Unicode text as its UTF-8 byte string.
pub fn encode(heap: *gc.Heap, ty: Type, value: Value) Error!Value {
    const encoded = try text.encode(heap, value);
    defer heap.allocator.free(encoded);
    return fromBytes(heap, ty, encoded);
}
/// Decode UTF-8 bytes into managed text, rejecting invalid sequences.
pub fn decode(heap: *gc.Heap, ty: Type, value: Value) Error!Value {
    const owned = try toOwned(heap, value);
    defer heap.allocator.free(owned);
    return text.create(heap, ty, owned);
}
/// Format the bytes as lowercase hexadecimal managed text.
pub fn hex(heap: *gc.Heap, ty: Type, value: Value) Error!Value {
    const owned = try toOwned(heap, value);
    defer heap.allocator.free(owned);
    const digits = try heap.allocator.alloc(u8, owned.len * 2);
    defer heap.allocator.free(digits);
    for (owned, 0..) |byte, i| _ = std.fmt.bufPrint(digits[i * 2 ..][0..2], "{x:0>2}", .{byte}) catch return error.CapacityLimit;
    return text.create(heap, ty, digits);
}
/// Parse an even-length lowercase or uppercase hexadecimal string into bytes.
pub fn fromHex(heap: *gc.Heap, ty: Type, value: Value) Error!Value {
    const encoded = try text.encode(heap, value);
    defer heap.allocator.free(encoded);
    if (encoded.len % 2 != 0) return error.InvalidHex;
    const result = try heap.create(ty, .u8, encoded.len / 2);
    errdefer result.release(heap.allocator);
    var i: usize = 0;
    while (i < encoded.len) : (i += 2) {
        if (!std.ascii.isHex(encoded[i]) or !std.ascii.isHex(encoded[i + 1])) return error.InvalidHex;
        const byte = std.fmt.parseInt(u8, encoded[i .. i + 2], 16) catch return error.InvalidHex;
        try heap.append(result, Value.number(.u8, byte));
    }
    result.managed.collection.kind = .bytes;
    return result;
}

test "fromBytes and fromItems reject capacity growth without leaking partial storage" {
    const t = std.testing;
    var heap = gc.Heap.init(t.allocator);
    defer heap.deinit();
    const ty: Type = @fromBackingInt(@intCast(32));
    heap.max_capacity = 2;
    try t.expectError(error.CapacityLimit, fromBytes(&heap, ty, "abc"));
    const pair = try fromBytes(&heap, ty, "ab");
    defer pair.release(t.allocator);
    const copied = try fromItems(&heap, ty, pair.managed.items.items);
    defer copied.release(t.allocator);
    try t.expect(try equal(&heap, pair, copied));
    try t.expectError(error.Bounds, at(&heap, copied, 2));
}
