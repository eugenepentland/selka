//! Ordinary value ABI metadata with canonical names and native byte offsets.
const std = @import("std");
const native = @import("native_types.zig");
const typed = @import("typed.zig");
pub const Error = native.Error;
/// One native field offset and its canonical semantic type name.
pub const Field = struct { type: ?[]const u8, offset: u64 };
/// Aggregate shape: element count, element stride and the field table. A scalar
/// and a capability carry the empty shape.
pub const Aggregate = struct { count: u64 = 0, stride: u64 = 0, fields: []const Field = &.{} };
/// Native byte layout, finite copied-tree shape and the emitter's
/// argument-crossing decision for one value type.
pub const Type = struct {
    name: []const u8,
    kind: []const u8,
    size: u64,
    alignment: u8,
    aggregate: Aggregate = .{},
    by_address: bool = false,

    /// Emit the flat `wire_types` schema: the aggregate shape keeps its former
    /// keys, in their former order, and `by_address` is appended last.
    pub fn jsonStringify(self: Type, writer: anytype) !void {
        try writer.write(.{
            .name = self.name,
            .kind = self.kind,
            .size = self.size,
            .alignment = self.alignment,
            .count = self.aggregate.count,
            .stride = self.aggregate.stride,
            .fields = self.aggregate.fields,
            .by_address = self.by_address,
        });
    }
};

/// Whether the native value is represented in one scalar register. A capability,
/// an open file, a managed reference and a callable code word all are.
pub fn scalar(ty: typed.Type, records: []const typed.Record) bool {
    // An open file and a capability are both one opaque native word.
    const authority = ty.capabilityIndex() != null or ty.isFile();
    if (ty.isInteger() or ty == .bool or ty == .unit or authority) return true;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    if (record.managed or record.contract.callback != null or ownedPointer(record)) return true;
    return if (record.shape.domain) |backing| scalar(backing, records) else false;
}

/// Whether a record is one owned pointer word: a byte buffer or a resource.
pub fn ownedPointer(record: typed.Record) bool {
    return record.shape.buffer != null or record.shape.resource != null;
}

/// The canonical name of the language's one text type.
pub const text_name = "str";

/// The scalar element type of the language's text record, or null when the
/// record is not text. The rule is nominal — the record's canonical name is
/// `str` — and never structural: the checked schema serialises `str` and a
/// user `List<u32>` identically (kind `list`, opaque, a `u32` element), so a
/// shape test would carry a user's list as if it were text, while no user
/// declaration can be named `str` because the prelude owns that name.
pub fn textScalar(record: typed.Record) ?typed.Type {
    if (!std.mem.eql(u8, record.name, text_name)) return null;
    return record.shape.buffer;
}

/// The manifest entry describing one text record as the copied-value codec
/// carries it: a one-word managed pointer whose wire form is one node per
/// scalar. The single `fields` entry names the scalar element type the
/// generated codec reads and writes one node per, so the adapter never has to
/// decide what text is; `count` stays zero because a text has no fixed length.
pub fn textType(allocator: std.mem.Allocator, records: []const typed.Record, layout: native.Layout, record: typed.Record) Error!?Type {
    const element = textScalar(record) orelse return null;
    const fields = try allocator.alloc(Field, 1);
    fields[0] = .{ .type = typed.typeName(element, records), .offset = 0 };
    return .{
        .name = record.name,
        .kind = "text",
        .size = layout.size,
        .alignment = layout.alignment,
        .aggregate = .{ .fields = fields },
        .by_address = false,
    };
}

/// QBE-AGGREF-1's one crossing rule: one argument of this type crosses a call
/// boundary as the address of the caller's storage instead of a value, while a
/// move-only aggregate keeps the by-value boundary and its single owner. The
/// emitter's `argumentType` and this module's manifest both read this answer,
/// so the generated copied-value adapter can never spell the rule a second time.
pub fn byAddress(layout: native.Layout, ty: typed.Type, records: []const typed.Record) bool {
    if (layout.copy == .prohibited) return false;
    return !scalar(ty, records);
}

/// Describe finite ordinary values; runtime identities and domains stay opaque.
pub fn describe(allocator: std.mem.Allocator, catalog: *native.Catalog) Error![]const Type {
    return describeWithDomains(allocator, catalog, false);
}

/// Include codec-owned domain backing nodes only for the normative JSON boundary.
pub fn describeWithDomains(allocator: std.mem.Allocator, catalog: *native.Catalog, codecs: bool) Error![]const Type {
    const flags = try @import("native_wire.zig").supported(allocator, catalog.records, codecs);
    defer allocator.free(flags);
    var types: std.ArrayList(Type) = .empty;
    errdefer types.deinit(allocator);
    for (0..typed.Type.record_base + catalog.records.len) |index| {
        const ty: typed.Type = @fromBackingInt(index);
        const ordinary = ty.isInteger() or ty == .bool;
        const injected_stream = codecs and ty == .stream_cap;
        const layout = try catalog.layout(ty);
        // Text is the one managed value the copied-value codec carries, and it
        // is offered only on the codec boundary: the ordinary `wire_types`
        // manifest keeps exactly the types it had, so nothing that reads it
        // meets a kind it does not know.
        const text: ?Type = if (codecs and ty.isAggregate())
            try textType(allocator, catalog.records, layout, catalog.records[ty.recordIndex()])
        else
            null;
        if (ty.isAggregate()) {
            if (!flags[ty.recordIndex()] and text == null) continue;
        } else if (!ordinary and !injected_stream) continue;
        if ((layout.trace or layout.drop) and text == null) continue;
        if (text) |item| {
            try types.append(allocator, item);
            continue;
        }
        var item: Type = .{
            .name = typed.typeName(ty, catalog.records),
            .kind = "scalar",
            .size = layout.size,
            .alignment = layout.alignment,
            .by_address = byAddress(layout, ty, catalog.records),
        };
        if (ty.isAggregate()) {
            const record = catalog.records[ty.recordIndex()];
            if (record.shape.variants) |variants| {
                const fields = try allocator.alloc(Field, variants.cases.len);
                for (variants.cases, fields) |case, *field| field.* = .{ .type = if (case.payload) |payload| typed.typeName(payload, catalog.records) else null, .offset = layout.payload_offset };
                item.kind = "variant";
                item.aggregate.fields = fields;
            } else {
                const fields = try allocator.alloc(Field, layout.fields.len);
                for (layout.fields, fields) |source, *field| field.* = .{ .type = typed.typeName(source.ty, catalog.records), .offset = source.offset };
                item.aggregate.fields = fields;
                item.kind = if (record.shape.domain != null) "domain" else if (record.shape.array != null) "array" else "record";
                item.aggregate.count = layout.count;
                item.aggregate.stride = layout.stride;
            }
        }
        try types.append(allocator, item);
    }
    return types.toOwnedSlice(allocator);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var catalog = try native.Catalog.initRecords(arena.allocator(), &.{});
    defer catalog.deinit();
    const types = try describeWithDomains(arena.allocator(), &catalog, true);
    try std.testing.expect(types.len > 0);
}
test "describeWithDomains releases temporary metadata on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

/// One manifest entry by canonical name, or null when the slice carries none.
fn findType(types: []const Type, name: []const u8) ?Type {
    for (types) |item| if (std.mem.eql(u8, item.name, name)) return item;
    return null;
}

// spec: QBE-TEXT-1
test "text is the record named str and is offered only on the codec boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    // A user `List<u32>` is structurally identical to `str`: same managed
    // one-word record, same u32 element. Only the name tells them apart.
    var records = [_]typed.Record{
        .{ .id = @fromBackingInt(typed.Type.record_base), .name = text_name, .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = .u32 } },
        .{ .id = @fromBackingInt(typed.Type.record_base + 1), .name = "List<u32>", .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = .u32 } },
    };
    var catalog = try native.Catalog.initRecords(a, &records);
    defer catalog.deinit();
    try std.testing.expectEqual(typed.Type.u32, textScalar(records[0]).?);
    try std.testing.expect(textScalar(records[1]) == null);
    const codec_types = try describeWithDomains(a, &catalog, true);
    const text = findType(codec_types, text_name);
    try std.testing.expect(text != null);
    try std.testing.expectEqualStrings("text", text.?.kind);
    try std.testing.expectEqual(@as(u64, 8), text.?.size);
    try std.testing.expectEqual(@as(u64, 8), text.?.alignment);
    try std.testing.expectEqual(@as(u64, 0), text.?.aggregate.count);
    try std.testing.expectEqual(@as(usize, 1), text.?.aggregate.fields.len);
    try std.testing.expectEqualStrings("u32", text.?.aggregate.fields[0].type.?);
    try std.testing.expect(!text.?.by_address);
    // A user list is not text even though its shape matches, so it keeps the
    // unsupported verdict instead of being carried as one node per scalar.
    try std.testing.expect(findType(codec_types, "List<u32>") == null);
    const ordinary = try describe(a, &catalog);
    try std.testing.expect(findType(ordinary, text_name) == null);
}
