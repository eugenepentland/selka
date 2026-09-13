//! Insertion-ordered dictionaries with traced key/value edges and shared aliases.
const std = @import("std");
const gc = @import("gc_heap.zig");
const values = @import("runtime_values.zig");
const text = @import("managed_text.zig");
const Value = values.Value;
const Type = values.Type;
pub const Error = text.Error || error{ MissingKey, InvalidKey };

/// Validate mapping representation and execution-local identity.
pub fn object(heap: *gc.Heap, value: Value) Error!*values.ManagedObject {
    if (value != .managed or value.managed.collection.kind != .dictionary) return error.TypeMismatch;
    if (value.managed.heap != @as(*anyopaque, @ptrCast(heap))) return error.ForeignMemory;
    return value.managed;
}
/// Create an empty mapping; scalar integer and managed string keys are supported.
pub fn create(heap: *gc.Heap, ty: Type, key_type: Type, value_type: Type) Error!Value {
    const result = try heap.create(ty, value_type, 0);
    result.managed.collection.kind = .dictionary;
    result.managed.collection.key = key_type;
    return result;
}
fn keyEqual(heap: *gc.Heap, left: Value, right: Value) Error!bool {
    if (left.typeOf() != right.typeOf()) return false;
    return switch (left) {
        .i64 => left.i64 == right.i64,
        .integer => left.integer.value == right.integer.value,
        .managed => try text.equal(heap, left, right),
        else => error.InvalidKey,
    };
}
fn validateKey(heap: *gc.Heap, map: *values.ManagedObject, key: Value) Error!void {
    if (key.typeOf() != map.collection.key.?) return error.TypeMismatch;
    if (key == .managed) {
        _ = try text.object(heap, key);
    } else if (!key.typeOf().isInteger()) return error.InvalidKey;
}
fn find(heap: *gc.Heap, map: *values.ManagedObject, key: Value) Error!?usize {
    try validateKey(heap, map, key);
    var i: usize = 0;
    while (i < map.items.items.len) : (i += 2) if (try keyEqual(heap, map.items.items[i], key)) return i;
    return null;
}
/// Return entry count, shared across all aliases.
pub fn len(heap: *gc.Heap, mapping: Value) Error!usize {
    return (try object(heap, mapping)).items.items.len / 2;
}
/// Test membership without allocating or changing insertion order.
pub fn contains(heap: *gc.Heap, mapping: Value, key: Value) Error!bool {
    return (try find(heap, try object(heap, mapping), key)) != null;
}
/// Read a retained value or report a missing key.
pub fn read(heap: *gc.Heap, mapping: Value, key: Value) Error!Value {
    const map = try object(heap, mapping);
    const index = try find(heap, map, key) orelse return error.MissingKey;
    return map.items.items[index + 1].retain();
}
/// Return the caller's default for an absent key, preserving value type checking.
pub fn get(heap: *gc.Heap, mapping: Value, key: Value, fallback: Value) Error!Value {
    const map = try object(heap, mapping);
    if (fallback.typeOf() != map.element_type) return error.TypeMismatch;
    try heap.validateElement(fallback);
    const index = try find(heap, map, key) orelse return fallback.retain();
    return map.items.items[index + 1].retain();
}
/// Update in place or append a new key in insertion order; failure is atomic.
pub fn write(heap: *gc.Heap, mapping: Value, key: Value, value: Value) Error!void {
    const map = try object(heap, mapping);
    if (value.typeOf() != map.element_type) return error.TypeMismatch;
    try heap.validateElement(value);
    try heap.barrier(map, value);
    try heap.barrier(map, key);
    if (try find(heap, map, key)) |index| {
        const retained = value.retain();
        map.items.items[index + 1].release(heap.allocator);
        map.items.items[index + 1] = retained;
        return;
    }
    if (map.items.items.len >= heap.max_capacity or heap.max_capacity - map.items.items.len < 2) return error.CapacityLimit;
    const rooted_map = mapping.retain();
    defer rooted_map.release(heap.allocator);
    const rooted_key = key.retain();
    defer rooted_key.release(heap.allocator);
    const rooted_value = value.retain();
    defer rooted_value.release(heap.allocator);
    if (!heap.regions.suspended and (heap.stress or heap.statistics.live_objects >= heap.next_collection)) try heap.collect();
    const previous = map.items.capacity;
    try map.items.ensureUnusedCapacity(heap.allocator, 2);
    map.items.appendAssumeCapacity(key.retain());
    map.items.appendAssumeCapacity(value.retain());
    heap.statistics.live_capacity += map.items.capacity - previous;
}
/// Snapshot keys or values in insertion order into a newly managed list.
pub fn snapshot(heap: *gc.Heap, mapping: Value, list_type: Type, keys: bool) Error!Value {
    const map = try object(heap, mapping);
    const result = try heap.create(list_type, if (keys) map.collection.key.? else map.element_type, map.items.items.len / 2);
    errdefer result.release(heap.allocator);
    var index: usize = if (keys) 0 else 1;
    while (index < map.items.items.len) : (index += 2) try heap.append(result, map.items.items[index]);
    return result;
}

/// Read an insertion-ordered key by position for bounded dictionary iteration.
pub fn keyAt(heap: *gc.Heap, mapping: Value, index: i128) Error!Value {
    const map = try object(heap, mapping);
    if (index < 0 or index >= map.items.items.len / 2) return error.Bounds;
    return map.items.items[@as(usize, @intCast(index)) * 2].retain();
}
