//! Closed pure octet/text operations and authenticated mutable-buffer authority.
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
const numeric = @import("body_check_numeric_validate.zig");
const operations = @import("buffer_operations.zig");
pub const Error = error{ComponentProtocol};
/// Validate a grouped authority independently of per-use source decisions.
pub fn basis(catalog: value.Catalog) Error!void {
    const authority = catalog.templates.byte_buffer;
    var candidate: ?typed.Type = null;
    for (catalog.records) |record| {
        if (!canonical(record)) continue;
        if (candidate != null) return error.ComponentProtocol;
        candidate = record.id;
    }
    const expected = if (authority.identity) |entry| entry.id else null;
    if (candidate != expected) return error.ComponentProtocol;
    if (authority.identity) |entry| {
        if (!authority.available) return error.ComponentProtocol;
        if (!entry.id.isAggregate() or entry.element != .u8) return error.ComponentProtocol;
        if (entry.id.recordIndex() >= catalog.records.len) return error.ComponentProtocol;
        const record = catalog.records[entry.id.recordIndex()];
        if (record.id != entry.id or !record.managed) return error.ComponentProtocol;
        if (record.collection.kind != .bytes or record.shape.buffer != .u8) return error.ComponentProtocol;
        if (!@import("std").mem.eql(u8, record.name, "byte_buffer")) return error.ComponentProtocol;
        if (catalog.bytes) |bytes| if (bytes.id == entry.id) return error.ComponentProtocol;
        if (catalog.string) |text| if (text.id == entry.id) return error.ComponentProtocol;
    }
}
fn canonical(record: typed.Record) bool {
    if (!record.managed or record.collection.kind != .bytes) return false;
    if (record.shape.buffer != .u8) return false;
    return @import("std").mem.eql(u8, record.name, "byte_buffer");
}
/// Recognize only the projected canonical mutable octet schema.
pub fn mutable(catalog: value.Catalog, ty: typed.Type) bool {
    const entry = catalog.templates.byte_buffer.identity orelse return false;
    return entry.id == ty;
}
fn byteFamily(catalog: value.Catalog, ty: typed.Type) bool {
    if (mutable(catalog, ty)) return true;
    if (catalog.bytes) |entry| return entry.id == ty;
    return false;
}
fn listElement(catalog: value.Catalog, ty: typed.Type) ?typed.Type {
    var low: usize = 0;
    var high = catalog.lists.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const entry = catalog.lists[mid];
        if (entry.id == ty) return entry.element;
        if (@backingInt(entry.id) < @backingInt(ty)) low = mid + 1 else high = mid;
    }
    return null;
}
/// The three exact snapshot/construction cast pairs used by codec libraries.
pub fn cast(catalog: value.Catalog, output: typed.Type, input: typed.Type) bool {
    if (catalog.string) |text| if (output == text.id) return numeric.scalar(input) or numeric.floating(catalog, input);
    const list = listElement(catalog, input);
    if (mutable(catalog, output)) return list == .i64;
    if (catalog.bytes) |entry| if (entry.id == output) return list == .i64 or mutable(catalog, input);
    return false;
}
/// Check a closed pure operation without evaluating bounds or source overloads.
pub fn operation(catalog: value.Catalog, owner: typed.Type, result: typed.Type, kind: operations.Kind, arguments: []const typed.Type, writable: bool) Error!void {
    const text = if (catalog.string) |entry| entry.id == owner else false;
    if (!text and !byteFamily(catalog, owner)) return error.ComponentProtocol;
    if (arguments.len != kind.arity()) return error.ComponentProtocol;
    switch (kind) {
        .length => if (result != .i64) return error.ComponentProtocol,
        .iteration_check => {
            if (mutable(catalog, owner) or result != .unit or arguments[0] != .i64) return error.ComponentProtocol;
        },
        .text_ord => if (!text or result != .i64) return error.ComponentProtocol,
        .join => {
            if (mutable(catalog, owner) or result != owner) return error.ComponentProtocol;
            if (listElement(catalog, arguments[0]) != owner) return error.ComponentProtocol;
        },
        .read => {
            const wanted = if (text) owner else typed.Type.u8;
            if (result != wanted or !arguments[0].isInteger()) return error.ComponentProtocol;
        },
        .slice, .text_tail => {
            if (kind == .text_tail and !text) return error.ComponentProtocol;
            if (result != owner) return error.ComponentProtocol;
            try integers(arguments);
        },
        .buffer_append_float => {
            try mutating(catalog, owner, result, writable);
            if (!numeric.floating(catalog, arguments[0])) return error.ComponentProtocol;
        },
        .buffer_reserve, .buffer_append_byte, .buffer_append_int => {
            try mutating(catalog, owner, result, writable);
            try integers(arguments);
        },
        .buffer_append_range => {
            try mutating(catalog, owner, result, writable);
            if (!byteFamily(catalog, arguments[0])) return error.ComponentProtocol;
            try integers(arguments[1..]);
        },
        else => return error.ComponentProtocol,
    }
}

fn integers(arguments: []const typed.Type) Error!void {
    for (arguments) |ty| if (!ty.isInteger()) return error.ComponentProtocol;
}
fn mutating(catalog: value.Catalog, owner: typed.Type, result: typed.Type, writable: bool) Error!void {
    if (!mutable(catalog, owner) or !writable) return error.ComponentProtocol;
    if (result != .bool) return error.ComponentProtocol;
}
