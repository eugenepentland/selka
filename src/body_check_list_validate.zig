//! Bounded canonical list identities and producer-selected append recipes.
const std = @import("std");
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const records = @import("body_check_record_validate.zig");
const structural = @import("body_check_structural_validate.zig");
pub const Error = error{ OutOfMemory, ComponentProtocol };
pub const limit = 65536;

/// Binary-search a canonical list table without a per-node linear scan.
pub fn listElement(initial: value.Catalog, ty: typed.Type) ?typed.Type {
    var low: usize = 0;
    var high = initial.lists.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const item = initial.lists[mid];
        if (item.id == ty) return item.element;
        if (@backingInt(item.id) < @backingInt(ty)) low = mid + 1 else high = mid;
    }
    return null;
}
fn leaf(initial: value.Catalog, ty: typed.Type) bool {
    if (@import("body_check_numeric_validate.zig").scalar(ty)) return true;
    if (@import("body_check_numeric_validate.zig").floating(initial, ty)) return true;
    if (initial.string) |item| if (item.id == ty) return true;
    if (initial.bytes) |item| if (item.id == ty) return true;
    if (initial.templates.byte_buffer.identity) |item| if (item.id == ty) return true;
    if (@import("body_check_dictionary_validate.zig").identify(initial, ty)) |entry| {
        if (entry.kind == .dict or entry.kind == .set) return true;
    }
    if (ty.isAggregate() and ty.recordIndex() < initial.records.len) {
        const record = initial.records[ty.recordIndex()];
        return records.ordinary(record) or records.variant(record) or structural.tuple(record) or structural.array(record);
    }
    return false;
}
fn descriptor(initial: value.Catalog, item: value.Sequence, expected: typed.Type) Error!void {
    const id = @backingInt(item.id);
    if (id < typed.Type.record_base or id - typed.Type.record_base >= initial.base_count or item.element != expected) return error.ComponentProtocol;
    if (item.id.recordIndex() < initial.records.len) {
        const record = initial.records[item.id.recordIndex()];
        const kind: @import("runtime_values.zig").ManagedKind = if (expected == .u32) .string else .bytes;
        if (!record.isCollection() or record.collection.kind != kind or record.shape.buffer != expected) return error.ComponentProtocol;
    }
}
/// Validate all existing list dependencies, including forward edges, without assuming append topology.
pub fn catalog(a: std.mem.Allocator, item: value.Catalog) Error!void {
    try records.catalog(item);
    try @import("body_check_dictionary_validate.zig").bases(item);
    if (item.base_count > limit or item.lists.len > item.base_count) return error.ComponentProtocol;
    if (item.string) |entry| try descriptor(item, entry, .u32);
    if (item.bytes) |entry| try descriptor(item, entry, .u8);
    try @import("body_check_buffer_validate.zig").basis(item);
    if (item.string) |text| if (item.bytes) |octets| {
        if (text.id == octets.id) return error.ComponentProtocol;
    };
    if (item.lists.len != 0 and !item.list_available) return error.ComponentProtocol;
    var ids: std.AutoHashMapUnmanaged(typed.Type, usize) = .empty;
    defer ids.deinit(a);
    var elements: std.AutoHashMapUnmanaged(typed.Type, void) = .empty;
    defer elements.deinit(a);
    var prior: usize = 0;
    for (item.lists, 0..) |entry, index| {
        const id = @backingInt(entry.id);
        if (id < typed.Type.record_base or id - typed.Type.record_base >= item.base_count or id <= prior or leaf(item, entry.id)) return error.ComponentProtocol;
        if (entry.id.recordIndex() < item.records.len) {
            const schema = item.records[entry.id.recordIndex()];
            if (!schema.isCollection() or schema.collection.kind != .list or schema.shape.buffer != entry.element) return error.ComponentProtocol;
        }
        prior = id;
        const found = try elements.getOrPut(a, entry.element);
        if (found.found_existing) return error.ComponentProtocol;
        try ids.put(a, entry.id, index);
    }
    const accepted = try records.policy(a, item);
    defer a.free(accepted);
    for (item.lists) |entry| if (!accepted[entry.id.recordIndex()]) return error.ComponentProtocol;
    const states = try a.alloc(u8, item.lists.len);
    defer a.free(states);
    const depths = try a.alloc(usize, item.lists.len);
    defer a.free(depths);
    @memset(states, 0);
    @memset(depths, 0);
    for (item.lists, 0..) |_, index| _ = try depth(item, ids, .{ .states = states, .depths = depths }, index, 0);
}
const Walk = struct { states: []u8, depths: []usize };
fn depth(item: value.Catalog, ids: std.AutoHashMapUnmanaged(typed.Type, usize), walk: Walk, index: usize, active: usize) Error!usize {
    if (active >= 256 or walk.states[index] == 1) return error.ComponentProtocol;
    if (walk.states[index] == 2) return walk.depths[index];
    walk.states[index] = 1;
    const ty = item.lists[index].element;
    const result = if (ids.get(ty)) |child| 1 + try depth(item, ids, walk, child, active + 1) else if (leaf(item, ty)) @as(usize, 2) else return error.ComponentProtocol;
    if (result > 256) return error.ComponentProtocol;
    walk.states[index] = 2;
    walk.depths[index] = result;
    return result;
}
/// Validate contiguous unique producer recipes, source association and bounded dependency depth.
pub fn recipes(a: std.mem.Allocator, input: value.Input, items: []const value.ListRecipe) Error!void {
    if (input.catalog.records.len != input.catalog.base_count) return error.ComponentProtocol;
    try catalog(a, input.catalog);
    if (items.len > limit - input.catalog.base_count or (items.len != 0 and !input.catalog.list_available)) return error.ComponentProtocol;
    const accepted = try records.policy(a, input.catalog);
    defer a.free(accepted);
    var known: std.AutoHashMapUnmanaged(typed.Type, void) = .empty;
    defer known.deinit(a);
    for (input.catalog.lists) |item| try known.put(a, item.element, {});
    var sites: std.AutoHashMapUnmanaged(source.Span, void) = .empty;
    defer sites.deinit(a);
    for (input.program.nodes.items) |node| try sites.put(a, node.span, {});
    for (input.program.statements.items) |statement| try sites.put(a, statement.span, {});
    for (items, 0..) |item, index| {
        if (@backingInt(item.id) != typed.Type.record_base + input.catalog.base_count + index) return error.ComponentProtocol;
        if (item.span.start > item.span.end or item.span.end > input.context.source.len or !sites.contains(item.span)) return error.ComponentProtocol;
        const exists = try known.getOrPut(a, item.element);
        if (exists.found_existing) return error.ComponentProtocol;
        if (item.element.isAggregate() and item.element.recordIndex() < accepted.len) {
            if (!accepted[item.element.recordIndex()]) return error.ComponentProtocol;
            continue;
        }
        if (leaf(input.catalog, item.element)) continue;
        const element_id = @backingInt(item.element);
        if (element_id < typed.Type.record_base + input.catalog.base_count or element_id >= @backingInt(item.id)) return error.ComponentProtocol;
    }
    const combined = try expanded(a, input.catalog, items);
    defer a.free(combined.lists);
    try catalog(a, combined);
}
/// Owned combined descriptor table, preserving canonical IDs and native base count.
pub fn expanded(a: std.mem.Allocator, initial: value.Catalog, items: []const value.ListRecipe) Error!value.Catalog {
    if (items.len > limit - @min(initial.base_count, limit)) return error.ComponentProtocol;
    const lists = try a.alloc(value.Sequence, initial.lists.len + items.len);
    @memcpy(lists[0..initial.lists.len], initial.lists);
    for (items, lists[initial.lists.len..]) |item, *entry| entry.* = .{ .id = item.id, .element = item.element };
    var output = initial;
    output.base_count += items.len;
    output.lists = lists;
    return output;
}
