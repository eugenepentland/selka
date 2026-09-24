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

/// The element type of a user list, or null when the record is not one. Text is
/// excluded nominally even though it is a managed buffer too: a record built
/// without an explicit collection kind keeps the `.list` default, so the shape
/// alone cannot separate the prelude's `str` from a user's `list[u32]`. The
/// other builtin buffers are excluded by kind, which keeps `bytes` and
/// `dict[str,T]` unsupported until their wire encodings are specified.
pub fn listScalar(record: typed.Record) ?typed.Type {
    if (textScalar(record) != null) return null;
    if (!record.isCollection() or record.collection.kind != .list) return null;
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

/// The manifest entry describing one user list as the copied-value codec carries
/// it: a one-word managed pointer whose wire form is one node per element. The
/// single `fields` entry names the element type the generated codec reads and
/// writes one node per, so the adapter never has to decide what a list is;
/// `count` stays zero because a list has no fixed length. The list crosses the
/// copied ABI by value like every other managed pointer, so it never takes the
/// by-address convention that rewrites a copyable aggregate.
pub fn listType(allocator: std.mem.Allocator, records: []const typed.Record, layout: native.Layout, record: typed.Record) Error!?Type {
    const element = listScalar(record) orelse return null;
    const fields = try allocator.alloc(Field, 1);
    fields[0] = .{ .type = typed.typeName(element, records), .offset = 0 };
    return .{
        .name = record.name,
        .kind = "list",
        .size = layout.size,
        .alignment = layout.alignment,
        .aggregate = .{ .fields = fields },
        .by_address = false,
    };
}

/// The one managed value kind this record carries across the copied boundary, or
/// null when the codec has no encoding for it yet. Text, lists, `bytes`,
/// dictionaries and sets share this entry point so the caller never spells the
/// choice twice.
fn managedType(allocator: std.mem.Allocator, records: []const typed.Record, layout: native.Layout, record: typed.Record) Error!?Type {
    if (try textType(allocator, records, layout, record)) |item| return item;
    if (try listType(allocator, records, layout, record)) |item| return item;
    const kind = if (bytesRecord(record)) "bytes" else "dict";
    const key = dictionaryKey(record);
    if (key == null and !bytesRecord(record)) return null;
    const elements: []const typed.Type = if (key) |dictionary_key| &.{ dictionary_key, record.shape.buffer.? } else &.{.u8};
    const entry = try handle(allocator, records, layout, record, kind, elements);
    return entry;
}

/// Whether a record is the builtin `bytes`: a managed octet buffer.
pub fn bytesRecord(record: typed.Record) bool {
    return record.isCollection() and record.collection.kind == .bytes;
}
/// The key type of a dictionary or a set, or null for any other record. A
/// set is a dictionary whose values are unit (`runtime_values.CollectionShape`).
pub fn dictionaryKey(record: typed.Record) ?typed.Type {
    if (!record.isCollection() or record.collection.kind != .dictionary) return null;
    return record.collection.key;
}
/// Whether a record is the builtin `float`: the domain over the IEEE bits.
pub fn floatRecord(record: typed.Record) bool {
    return std.mem.eql(u8, record.name, "float") and record.shape.domain == .u64;
}
/// A managed handle entry of kind `kind` whose fields name the element types
/// the generated codec reads one wire node (or one subtree) per: the octet
/// type for `bytes`, the key and the value for a dictionary. A set's value is
/// unit, which carries no node, so its entry counts one subtree per element.
fn handle(allocator: std.mem.Allocator, records: []const typed.Record, layout: native.Layout, record: typed.Record, kind: []const u8, elements: []const typed.Type) Error!Type {
    const fields = try allocator.alloc(Field, elements.len);
    for (fields, elements) |*field, element| field.* = .{ .type = typed.typeName(element, records), .offset = 0 };
    const set = elements.len == 2 and elements[1] == .unit;
    return .{
        .name = record.name,
        .kind = kind,
        .size = layout.size,
        .alignment = layout.alignment,
        .aggregate = .{ .count = if (elements.len == 2) @as(u64, if (set) 1 else 2) else 0, .fields = fields },
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

/// Whether each record reaches the manifest once the codec's managed values are
/// counted. `native_wire.supported` decides this for the encodings that predate
/// the codec and cannot see text or lists at all, so this closes over just those
/// two: text enters by name and a list enters once its element has, which admits
/// `list[str]` and `list[list[i64]]` while leaving `list[dict[str,i64]]`, `bytes`
/// and a domain without a supported codec out. A record that merely *contains* a
/// text or a list is deliberately still out: the manifest renders a record from
/// its native layout, not from its declared fields, so admitting one needs the
/// layout in hand and a check driven by it. Admitting a record whose child has no
/// entry would produce a manifest the generated adapter cannot resolve, which is
/// a build failure rather than a refusal — the codec must decline instead.
fn includable(allocator: std.mem.Allocator, records: []const typed.Record, flags: []const bool, codecs: bool) Error![]bool {
    const included = try allocator.alloc(bool, records.len);
    errdefer allocator.free(included);
    for (records, 0..) |record, i| included[i] = flags[i] or (codecs and (textScalar(record) != null or bytesRecord(record) or floatRecord(record)));
    var changed = codecs;
    while (changed) {
        changed = false;
        for (records, 0..) |record, i| {
            if (included[i] or record.contract.move_only) continue;
            if (listScalar(record)) |element| {
                if (!carriable(element, included)) continue;
            } else if (dictionaryKey(record)) |key| {
                const value = record.shape.buffer.?;
                const value_carried = value == .unit or carriable(value, included);
                if (!carriable(key, included) or !value_carried) continue;
            } else if (record.shape.hasRuntimeIdentity() or record.shape.domain != null or record.shape.resource != null or record.contract.callback != null) continue else if (!childrenCarriable(record, included)) continue;
            included[i] = true;
            changed = true;
        }
    }
    return included;
}

/// Whether every value one aggregate record reaches can itself cross, read from
/// the record's declared fields. A record with runtime identity is reached only
/// through `listScalar`, which checks the element directly, so the buffer kind
/// itself is never carriable here.
fn childrenCarriable(record: typed.Record, included: []const bool) bool {
    if (record.shape.hasRuntimeIdentity()) return false;
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| {
            if (!carriable(payload, included)) return false;
        };
        return true;
    }
    if (record.shape.array) |array| return carriable(array.element, included);
    for (record.fields) |field| if (!carriable(field.ty, included)) return false;
    return true;
}

/// Whether an admitted set needs the unit entry for its values.
fn needsUnit(records: []const typed.Record, included: []const bool) bool {
    for (records, included) |record, admitted| {
        if (!admitted) continue;
        if (dictionaryKey(record) != null and record.shape.buffer.? == .unit) return true;
    }
    return false;
}

/// Whether one value can cross once the records admitted so far are known.
fn carriable(ty: typed.Type, included: []const bool) bool {
    return if (ty.isAggregate()) included[ty.recordIndex()] else ty.isInteger() or ty == .bool;
}

/// A manifest table and, position by position, the catalog identity each entry
/// describes. A caller that needs the native descriptor symbol for an entry
/// reads `ids` rather than matching names back onto the catalog, which would
/// silently pick the wrong record if two entries ever shared a spelling.
pub const Table = struct {
    /// The serializable manifest entries, in catalog order.
    types: []const Type,
    /// The catalog type whose layout each entry records.
    ids: []const typed.Type,
};

/// Describe finite ordinary values; runtime identities and domains stay opaque.
pub fn describe(allocator: std.mem.Allocator, catalog: *native.Catalog) Error!Table {
    return describeWithDomains(allocator, catalog, false);
}

/// Include codec-owned domain backing nodes only for the normative JSON boundary.
pub fn describeWithDomains(allocator: std.mem.Allocator, catalog: *native.Catalog, codecs: bool) Error!Table {
    const flags = try @import("native_wire.zig").supported(allocator, catalog.records, codecs);
    defer allocator.free(flags);
    const included = try includable(allocator, catalog.records, flags, codecs);
    defer allocator.free(included);
    var types: std.ArrayList(Type) = .empty;
    errdefer types.deinit(allocator);
    var ids: std.ArrayList(typed.Type) = .empty;
    errdefer ids.deinit(allocator);
    for (0..typed.Type.record_base + catalog.records.len) |index| {
        const ty: typed.Type = @fromBackingInt(index);
        // Unit is offered only as a set's value: it carries no wire node, but a
        // set is built with the descriptor the program uses for its values.
        const ordinary = ty.isInteger() or ty == .bool or (ty == .unit and codecs and needsUnit(catalog.records, included));
        // A `Stream` is injected by the codec adapter, and so is every other
        // capability a test may declare except `Host`: `mylang test` hands it
        // a deterministic stand-in (TEST-CAPS-3).
        const injected_stream = codecs and ty != .host_cap and ty.capabilityIndex() != null;
        const ready = !ty.isAggregate() or included[ty.recordIndex()];
        const layout = try catalog.layout(ty);
        // Text and lists are the managed values the copied-value codec carries,
        // and they are offered only on the codec boundary: the ordinary
        // `wire_types` manifest keeps exactly the types it had, so nothing that
        // reads it meets a kind it does not know.
        const managed: ?Type = if (codecs and ty.isAggregate() and ready)
            try managedType(allocator, catalog.records, layout, catalog.records[ty.recordIndex()])
        else
            null;
        if (ty.isAggregate()) {
            if (!ready) continue;
        } else if (!ordinary and !injected_stream) continue;
        if (managed) |item| {
            try types.append(allocator, item);
            try ids.append(allocator, ty);
            continue;
        }
        var item: Type = .{
            .name = typed.typeName(ty, catalog.records),
            .kind = "scalar",
            .size = layout.size,
            .alignment = layout.alignment,
            .by_address = byAddress(layout, ty, catalog.records),
        };
        // A float crosses as its IEEE bits in one scalar word, like the
        // integer backing it is stored as; it has no codec to decode through.
        const float_bits = ty.isAggregate() and floatRecord(catalog.records[ty.recordIndex()]);
        if (ty.isAggregate() and !float_bits) {
            const record = catalog.records[ty.recordIndex()];
            if (record.shape.variants) |variants| {
                const fields = try allocator.alloc(Field, variants.cases.len);
                for (variants.cases, fields) |case, *field| field.* = .{ .type = if (case.payload) |payload| typed.typeName(payload, catalog.records) else null, .offset = layout.payload_offset };
                // QBE-NICHE-1: a niche optional stores no tag word, so the
                // adapter reads its case from whether the reference is null.
                item.kind = if (layout.kind == .niche) "niche" else "variant";
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
        try ids.append(allocator, ty);
    }
    const owned_types = try types.toOwnedSlice(allocator);
    errdefer allocator.free(owned_types);
    const owned_ids = try ids.toOwnedSlice(allocator);
    return .{ .types = owned_types, .ids = owned_ids };
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var catalog = try native.Catalog.initRecords(arena.allocator(), &.{});
    defer catalog.deinit();
    const types = try describeWithDomains(arena.allocator(), &catalog, true);
    try std.testing.expect(types.types.len > 0);
    try std.testing.expectEqual(types.types.len, types.ids.len);
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
    // one-word record, same u32 element. Both records here also leave their
    // collection kind at its `.list` default, so nothing but the prelude's name
    // stops `str` being read as a user list.
    var records = [_]typed.Record{
        .{ .id = @fromBackingInt(typed.Type.record_base), .name = text_name, .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = .u32 } },
        .{ .id = @fromBackingInt(typed.Type.record_base + 1), .name = "List<u32>", .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = .u32 } },
    };
    var catalog = try native.Catalog.initRecords(a, &records);
    defer catalog.deinit();
    try std.testing.expectEqual(typed.Type.u32, textScalar(records[0]).?);
    try std.testing.expect(textScalar(records[1]) == null);
    try std.testing.expect(listScalar(records[0]) == null);
    const codec_types = try describeWithDomains(a, &catalog, true);
    const text = findType(codec_types.types, text_name);
    try std.testing.expect(text != null);
    try std.testing.expectEqualStrings("text", text.?.kind);
    try std.testing.expectEqual(@as(u64, 8), text.?.size);
    try std.testing.expectEqual(@as(u64, 8), text.?.alignment);
    try std.testing.expectEqual(@as(u64, 0), text.?.aggregate.count);
    try std.testing.expectEqual(@as(usize, 1), text.?.aggregate.fields.len);
    try std.testing.expectEqualStrings("u32", text.?.aggregate.fields[0].type.?);
    try std.testing.expect(!text.?.by_address);
    // Text never reaches the ordinary `wire_types` manifest, so a reader that
    // predates the codec boundary keeps seeing exactly the kinds it knew.
    const ordinary = try describe(a, &catalog);
    try std.testing.expect(findType(ordinary.types, text_name) == null);
}

// spec: QBE-LIST-1
test "a user list is carried as one node per element while other buffers stay out" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const base = typed.Type.record_base;
    var records = [_]typed.Record{
        .{ .id = @fromBackingInt(base), .name = "List<i64>", .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = .i64 } },
        .{ .id = @fromBackingInt(base + 1), .name = "bytes", .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = .u8 }, .collection = .{ .kind = .bytes } },
        .{ .id = @fromBackingInt(base + 2), .name = "List<List<i64>>", .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = @fromBackingInt(base) } },
    };
    var catalog = try native.Catalog.initRecords(a, &records);
    defer catalog.deinit();
    try std.testing.expectEqual(typed.Type.i64, listScalar(records[0]).?);
    try std.testing.expect(listScalar(records[1]) == null);
    try std.testing.expectEqual(@as(typed.Type, @fromBackingInt(base)), listScalar(records[2]).?);
    const codec_types = try describeWithDomains(a, &catalog, true);
    const list = findType(codec_types.types, "List<i64>");
    try std.testing.expect(list != null);
    try std.testing.expectEqualStrings("list", list.?.kind);
    try std.testing.expectEqual(@as(u64, 0), list.?.aggregate.count);
    try std.testing.expectEqual(@as(usize, 1), list.?.aggregate.fields.len);
    try std.testing.expectEqualStrings("i64", list.?.aggregate.fields[0].type.?);
    // A managed pointer crosses by value; only a copyable aggregate takes the
    // caller's address, and a list is neither copyable nor an aggregate value.
    try std.testing.expect(!list.?.by_address);
    // A nested list names its element by the element's own canonical name, so
    // the generated codec resolves it to that entry's descriptor.
    const nested = findType(codec_types.types, "List<List<i64>>");
    try std.testing.expect(nested != null);
    try std.testing.expectEqualStrings("List<i64>", nested.?.aggregate.fields[0].type.?);
    // `bytes` is carried under its own kind rather than by the rule that
    // happens to fit lists (PROPERTY-TEST-5).
    try std.testing.expectEqualStrings("bytes", findType(codec_types.types, "bytes").?.kind);
    // The ordinary manifest stays list-free in both directions.
    const ordinary = try describe(a, &catalog);
    try std.testing.expect(findType(ordinary.types, "List<i64>") == null);
    try std.testing.expect(findType(ordinary.types, "bytes") == null);
}

// Also pins the admission rule tagged QBE-LIST-1: a list is carried only when
// its element is, and the allocation that decides it reports failure.
test "a list of an uncarriable element stays out and a failed admission is fatal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const base = typed.Type.record_base;
    var records = [_]typed.Record{
        .{ .id = @fromBackingInt(base), .name = "List<Meters>", .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = @fromBackingInt(base + 1) } },
        .{ .id = @fromBackingInt(base + 1), .name = "Meters", .declaration = span, .fields = &.{}, .shape = .{ .domain = .u32 } },
        .{ .id = @fromBackingInt(base + 2), .name = "List<i64>", .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = .i64 } },
    };
    const flags = try a.alloc(bool, records.len);
    @memset(flags, false);
    const included = try includable(a, &records, flags, true);
    // A list is admitted by its element, so a list of a kind the codec has no
    // encoding for is left out rather than admitted with a dangling element.
    try std.testing.expect(!included[0]);
    try std.testing.expect(!included[1]);
    try std.testing.expect(included[2]);
    // Deciding admission allocates, so a failure must surface to the caller
    // instead of silently shrinking the table.
    try std.testing.expectError(error.OutOfMemory, includable(std.testing.failing_allocator, &records, flags, true));
}

// spec: QBE-LIST-2
test "a record holding text or a list is admitted and one holding a codec-less domain is not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const base = typed.Type.record_base;
    const bucket_fields = [_]typed.Field{
        .{ .name = "label", .declaration = span, .ty = @fromBackingInt(base) },
        .{ .name = "values", .declaration = span, .ty = @fromBackingInt(base + 1) },
    };
    const raw_fields = [_]typed.Field{
        .{ .name = "raw", .declaration = span, .ty = @fromBackingInt(base + 2) },
    };
    var records = [_]typed.Record{
        .{ .id = @fromBackingInt(base), .name = text_name, .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = .u32 } },
        .{ .id = @fromBackingInt(base + 1), .name = "List<i64>", .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = .i64 } },
        .{ .id = @fromBackingInt(base + 2), .name = "Meters", .declaration = span, .fields = &.{}, .shape = .{ .domain = .u32 } },
        .{ .id = @fromBackingInt(base + 3), .name = "Bucket", .declaration = span, .fields = &bucket_fields },
        .{ .id = @fromBackingInt(base + 4), .name = "Raw", .declaration = span, .fields = &raw_fields },
    };
    var catalog = try native.Catalog.initRecords(a, &records);
    defer catalog.deinit();
    const flags = try a.alloc(bool, records.len);
    @memset(flags, false);
    const included = try includable(a, &records, flags, true);
    // A record is admitted by its fields, so one that holds the two managed
    // values the codec carries crosses with them.
    try std.testing.expect(included[3]);
    // One that holds a domain without a codec is still refused: the rule that
    // admits a list does not quietly admit every value beside it.
    try std.testing.expect(!included[4]);
    const codec_types = try describeWithDomains(a, &catalog, true);
    const bucket = findType(codec_types.types, "Bucket");
    try std.testing.expect(bucket != null);
    try std.testing.expectEqualStrings("record", bucket.?.kind);
    try std.testing.expectEqual(@as(usize, 2), bucket.?.aggregate.fields.len);
    try std.testing.expectEqualStrings(text_name, bucket.?.aggregate.fields[0].type.?);
    try std.testing.expectEqualStrings("List<i64>", bucket.?.aggregate.fields[1].type.?);
    // `Raw` is absent, so a record the codec declines still cannot reach the
    // manifest through a field that happened to be admitted.
    try std.testing.expect(findType(codec_types.types, "Raw") == null);
    const ordinary = try describe(a, &catalog);
    try std.testing.expect(findType(ordinary.types, "Bucket") == null);
}

// spec: PROPERTY-TEST-5
test "float, bytes, a dictionary and a set cross the codec boundary under their own kinds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const base = typed.Type.record_base;
    var records = [_]typed.Record{
        .{ .id = @fromBackingInt(base), .name = text_name, .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = .u32 } },
        .{ .id = @fromBackingInt(base + 1), .name = "float", .declaration = span, .fields = &.{}, .shape = .{ .domain = .u64 } },
        .{ .id = @fromBackingInt(base + 2), .name = "bytes", .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = .u8 }, .collection = .{ .kind = .bytes } },
        .{
            .id = @fromBackingInt(base + 3),
            .name = "dict<str,float>",
            .declaration = span,
            .fields = &.{},
            .managed = true,
            .shape = .{ .buffer = @fromBackingInt(base + 1) },
            .collection = .{ .kind = .dictionary, .key = @fromBackingInt(base) },
        },
        .{
            .id = @fromBackingInt(base + 4),
            .name = "set<i64>",
            .declaration = span,
            .fields = &.{},
            .managed = true,
            .shape = .{ .buffer = .unit },
            .collection = .{ .kind = .dictionary, .key = .i64, .set = true },
        },
    };
    var catalog = try native.Catalog.initRecords(a, &records);
    defer catalog.deinit();
    const codec_types = try describeWithDomains(a, &catalog, true);
    // A float is one scalar word of IEEE bits, not a domain waiting for a codec.
    try std.testing.expectEqualStrings("scalar", findType(codec_types.types, "float").?.kind);
    try std.testing.expectEqual(@as(u64, 8), findType(codec_types.types, "float").?.size);
    const bytes = findType(codec_types.types, "bytes").?;
    try std.testing.expectEqualStrings("bytes", bytes.kind);
    try std.testing.expectEqualStrings("u8", bytes.aggregate.fields[0].type.?);
    // A dictionary names its key and value and counts two subtrees per entry;
    // a set's value is unit, which carries no node, so it counts one.
    const dict = findType(codec_types.types, "dict<str,float>").?;
    try std.testing.expectEqualStrings("dict", dict.kind);
    try std.testing.expectEqual(@as(u64, 2), dict.aggregate.count);
    try std.testing.expectEqualStrings(text_name, dict.aggregate.fields[0].type.?);
    try std.testing.expectEqualStrings("float", dict.aggregate.fields[1].type.?);
    const set = findType(codec_types.types, "set<i64>").?;
    try std.testing.expectEqual(@as(u64, 1), set.aggregate.count);
    try std.testing.expectEqualStrings("unit", set.aggregate.fields[1].type.?);
    try std.testing.expect(findType(codec_types.types, "unit") != null);
    // None of them reaches the ordinary manifest.
    const ordinary = try describe(a, &catalog);
    try std.testing.expect(findType(ordinary.types, "set<i64>") == null);
    try std.testing.expect(findType(ordinary.types, "unit") == null);
}
