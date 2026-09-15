//! Closed Cell content policy and transitive identity restrictions.
const std = @import("std");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");

/// Recognize the unparameterized builtin constructor after ordinary name shadowing.
pub fn constructor(src: @import("source.zig").Source, catalog: @import("type_catalog.zig").Catalog, call: @import("call_arguments.zig").Call, sink: *diagnostic.Sink) diagnostic.Error!?usize {
    if (call.owner != null or call.type_arguments.len != 0 or !std.mem.eql(u8, src.text(call.name), "Cell")) return null;
    if (catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
    const index = catalog.templates.store.?.index;
    const id = index.names.get("Cell") orelse return null;
    if (index.declarations.items[id].builtin_name == null) return null;
    if (call.arguments.len != 1) return sink.fail("E_ARITY", call.name, "Cell requires exactly one value argument");
    if (call.argument_names.len != 1 or call.argument_names[0] == null or !std.mem.eql(u8, src.text(call.argument_names[0].?), "value"))
        return sink.fail("E_UNKNOWN_FIELD", call.name, "construct Cell with value=initial");
    return id;
}

/// Validate Cell contents through records, variants and collection elements.
/// Fixed-point propagation terminates even for graphs closed by managed edges.
pub fn validate(allocator: std.mem.Allocator, records: []typed.Record, sink: *diagnostic.Sink) diagnostic.Error!void {
    const forbidden = try allocator.alloc(bool, records.len);
    defer allocator.free(forbidden);
    const cells = try allocator.alloc(bool, records.len);
    defer allocator.free(cells);
    for (records, forbidden, cells) |record, *bad, *cell| {
        bad.* = !record.contract.storable or record.contract.move_only or record.contract.requires_handling or
            @import("prelude.zig").optionShape(record.id, records) != null;
        cell.* = record.isCell();
    }
    var changed = true;
    while (changed) {
        changed = false;
        for (records, 0..) |record, i| {
            if (!forbidden[i] and children(record, forbidden, true)) {
                forbidden[i] = true;
                changed = true;
            }
            if (!cells[i] and children(record, cells, false)) {
                cells[i] = true;
                changed = true;
            }
        }
    }
    for (records, cells) |*record, cell| {
        record.collection.contains_cell = cell;
        if (!record.isCell()) continue;
        if (record.fields.len != 1 or !std.mem.eql(u8, record.fields[0].name, "value")) return error.InternalError;
        if (carries(record.fields[0].ty, forbidden, true)) return sink.fail("E_CELL_ELEMENT", record.declaration, "Cell contents must be copyable, storable values without Result, Option, resources, capabilities, or result obligations");
    }
}

fn carries(ty: typed.Type, flags: []const bool, reject_capabilities: bool) bool {
    if (reject_capabilities and (ty.capabilityIndex() != null or ty.isFile())) return true;
    return ty.isAggregate() and flags[ty.recordIndex()];
}

fn children(record: typed.Record, flags: []const bool, reject_capabilities: bool) bool {
    for (record.fields) |field| if (carries(field.ty, flags, reject_capabilities)) return true;
    if (record.shape.array) |array| if (carries(array.element, flags, reject_capabilities)) return true;
    if (record.shape.buffer) |element| if (carries(element, flags, reject_capabilities)) return true;
    if (record.collection.key) |key| if (carries(key, flags, reject_capabilities)) return true;
    if (record.shape.variants) |variants| for (variants.cases) |case| {
        if (case.payload) |payload| if (carries(payload, flags, reject_capabilities)) return true;
    };
    return false;
}
