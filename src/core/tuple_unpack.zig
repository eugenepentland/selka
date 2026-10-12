//! Validate compiler-only complete tuple staging before any destructive projection.
const std = @import("std");
const typed = @import("mylang").typed;

pub const Error = std.mem.Allocator.Error || error{Invalid};

fn hidden(local: typed.Local) bool {
    return local.usage.temporary and !local.ownership.transfer_available;
}

/// One whole initializer owns the complete tuple; every field has one destination.
/// Validate cached trees as well as fresh producers in work proportional to arity.
pub fn fields(a: std.mem.Allocator, program: typed.Program, function: typed.Function, store: typed.Store, initializing: bool) Error![]const typed.Field {
    const slots = store.unpack orelse return error.Invalid;
    if (!initializing or store.element) return error.Invalid;
    const original = @backingInt(store.slot);
    if (original >= function.scope.locals.len or @backingInt(store.value) >= program.nodes.len) return error.Invalid;
    const whole = function.scope.locals[original];
    if (!hidden(whole) or original < function.signature.parameter_count) return error.Invalid;
    if (program.nodes[@backingInt(store.value)].ty != whole.ty or !whole.ty.isAggregate()) return error.Invalid;
    const index = whole.ty.recordIndex();
    if (index >= program.records.len) return error.Invalid;
    const schema = program.records[index];
    if (!schema.shape.tuple or schema.fields.len != slots.len) return error.Invalid;
    var used: std.AutoHashMapUnmanaged(typed.LocalId, void) = .empty;
    defer used.deinit(a);
    for (schema.fields, slots) |field, optional| {
        const slot = optional orelse continue;
        const binding = @backingInt(slot);
        if (binding >= function.scope.locals.len or binding < function.signature.parameter_count or binding == original) return error.Invalid;
        const local = function.scope.locals[binding];
        if (!hidden(local) or local.ty != field.ty) return error.Invalid;
        const inserted = try used.getOrPut(a, slot);
        if (inserted.found_existing) return error.Invalid;
    }
    return schema.fields;
}
