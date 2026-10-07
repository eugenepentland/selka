//! Stable external C descriptors consumed by the precise native collector.
const std = @import("std");
const native = @import("native_types.zig");
const typed = @import("typed.zig");
pub const Error = native.Error;
const Item = struct { ty: typed.Type, name: []const u8 };
/// Reference descriptor symbols identify semantic types independently of catalog order.
pub fn symbol(allocator: std.mem.Allocator, catalog: *const native.Catalog, ty: typed.Type) Error![]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(try catalog.identity(ty), &digest, .{});
    return std.fmt.allocPrint(allocator, "myl_t_{s}", .{std.fmt.bytesToHex(digest, .lower)});
}
fn lessThan(_: void, a: Item, b: Item) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
/// Emit deterministic definitions for values and managed-record bodies. Generated
/// C owns no mutable state and depends only on the versioned native_heap.h ABI.
pub fn generate(allocator: std.mem.Allocator, catalog: *native.Catalog) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    return render(allocator, try blocks(arena.allocator(), catalog));
}

/// One descriptor's definitions and the symbol they are ordered and merged by.
pub const Block = struct { name: []const u8, text: []const u8 };

/// The C unit `generate` writes for these descriptors, sorted by symbol: the
/// header, a declaration of every descriptor, then each one's definitions. A
/// link renders the union of its modules' blocks (MODULE-COMPILE-1), which is
/// the whole program's text when the modules' types are the program's.
pub fn render(allocator: std.mem.Allocator, items: []const Block) Error![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    const writer = &output.writer;
    writer.writeAll("#include \"native_heap.h\"\n") catch return error.OutOfMemory;
    for (items) |item| {
        writer.print("extern const myl_native_type {s};\n", .{item.name}) catch return error.OutOfMemory;
        if (bodyBlock(item.text)) writer.print("extern const myl_native_type {s}_body;\n", .{item.name}) catch return error.OutOfMemory;
    }
    var next_id: u32 = 0;
    for (items) |item| try writeIds(writer, item.text, &next_id);
    return output.toOwnedSlice();
}

/// Whether this group contains its adjacent separately allocated record body.
fn bodyBlock(text: []const u8) bool {
    return std.mem.indexOf(u8, text, "_body = {.size=") != null;
}

/// Assign dense IDs only after the program-wide symbol union is complete.
fn writeIds(writer: *std.Io.Writer, text: []const u8, next: *u32) Error!void {
    const marker = ".rc_id=MYL_RC_ID_FIRST_GENERATED+";
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, text, cursor, marker)) |at| {
        const number_start = at + marker.len;
        var number_end = number_start;
        while (number_end < text.len and std.ascii.isDigit(text[number_end])) : (number_end += 1) {}
        if (number_end == number_start or next.* == std.math.maxInt(u32)) return error.InvalidType;
        writer.writeAll(text[cursor..number_start]) catch return error.OutOfMemory;
        writer.print("{d}", .{next.*}) catch return error.OutOfMemory;
        next.* += 1;
        cursor = number_end;
    }
    writer.writeAll(text[cursor..]) catch return error.OutOfMemory;
}

/// Every catalog type's descriptor definitions, sorted by symbol, allocated
/// with `allocator`.
pub fn blocks(allocator: std.mem.Allocator, catalog: *native.Catalog) Error![]Block {
    const a = allocator;
    const items = try a.alloc(Item, typed.Type.record_base + catalog.records.len);
    for (items, 0..) |*item, index| {
        const ty: typed.Type = @fromBackingInt(index);
        item.* = .{ .ty = ty, .name = try symbol(a, catalog, ty) };
    }
    std.mem.sort(Item, items, {}, lessThan);
    const out = try a.alloc(Block, items.len);
    for (items, out) |item, *block| {
        var output: std.Io.Writer.Allocating = .init(a);
        const writer = &output.writer;
        const layout = try catalog.layout(item.ty);
        const id: u32 = 0;
        if (layout.kind == .niche) {
            // QBE-NICHE-1: a niche optional's word is its payload reference or
            // null, and every descriptor walk — tracing, the region check, the
            // escape copier, structural equality — already treats a null pointer
            // as no reference. So the runtime sees the payload's own pointer
            // descriptor under this name and needs no kind of its own.
            const payload = layout.fields[0].ty;
            try emit(a, writer, catalog, .{ .name = item.name, .ty = payload, .id = id }, try catalog.layout(payload));
        } else try emit(a, writer, catalog, .{ .name = item.name, .ty = item.ty, .id = id }, layout);
        if (item.ty.isAggregate() and catalog.records[item.ty.recordIndex()].managed) {
            // Collections use their runtime header and typed element descriptors.
            // Nominal managed records can allocate this inline body directly.
            const record = catalog.records[item.ty.recordIndex()];
            if (record.shape.array == null and !record.shape.hasRuntimeIdentity()) {
                const body = try catalog.heapLayout(item.ty);
                defer catalog.releaseLayout(body);
                // QBE-GEN-BARRIER-1: a class body is the one object whose
                // post-construction stores all run the generational barrier.
                try emit(a, writer, catalog, .{ .name = try std.fmt.allocPrint(a, "{s}_body", .{item.name}), .ty = item.ty, .cell = true, .id = 1 }, body);
            }
        }
        block.* = .{ .name = item.name, .text = try output.toOwnedSlice() };
    }
    return out;
}
/// Whether `ty` is a box record of the physical catalog (RECURSIVE-VALUES-2).
fn boxed(catalog: *const native.Catalog, ty: typed.Type) bool {
    return ty.isAggregate() and ty.recordIndex() < catalog.records.len and catalog.records[ty.recordIndex()].collection.box;
}
/// One descriptor to emit: its symbol, the semantic type it describes, whether
/// it is a class body the store barrier watches, and its dense runtime id
/// (RC-TYPE-ID-1) counted from `MYL_RC_ID_FIRST_GENERATED`.
const Target = struct { name: []const u8, ty: typed.Type, cell: bool = false, id: u32 };
fn emit(a: std.mem.Allocator, writer: *std.Io.Writer, catalog: *native.Catalog, target: Target, layout: native.Layout) Error!void {
    const name = target.name;
    const ty = target.ty;
    if (layout.fields.len != 0) {
        writer.print("static const myl_native_field {s}_fields[] = {{\n", .{name}) catch return error.OutOfMemory;
        for (layout.fields) |field| {
            const child = try symbol(a, catalog, field.ty);
            writer.print(" {{.offset={d},.type=&{s},.tag={d}}},\n", .{ field.offset, child, field.tag orelse 0 }) catch return error.OutOfMemory;
        }
        writer.writeAll("};\n") catch return error.OutOfMemory;
    }
    var trace_field_count: usize = 0;
    if (layout.trace) for (layout.fields) |field| {
        if ((try catalog.layout(field.ty)).trace) trace_field_count += 1;
    };
    if (trace_field_count != 0) {
        writer.print("static const myl_native_field {s}_trace_fields[] = {{\n", .{name}) catch return error.OutOfMemory;
        for (layout.fields) |field| {
            if (!(try catalog.layout(field.ty)).trace) continue;
            const child = try symbol(a, catalog, field.ty);
            writer.print(" {{.offset={d},.type=&{s},.tag={d}}},\n", .{ field.offset, child, field.tag orelse 0 }) catch return error.OutOfMemory;
        }
        writer.writeAll("};\n") catch return error.OutOfMemory;
    }
    const described: Described = .{ .ty = ty, .layout = layout };
    const kind = described.kind(catalog);
    // GC-SCAN-PLAN-2: a traced aggregate carries its flat scan plan, so the
    // collector follows it with one load of the descriptor.
    var plan: ScanPlan = .{};
    const planned = layout.trace and (kind == .record or kind == .array or kind == .variant) and
        try flatten(catalog, &plan, described, 0, .{ .offset = 0, .tag_offset = scan_always, .tag = 0 }) and plan.len != 0;
    if (planned) {
        writer.print("static const myl_native_scan_entry {s}_scan[] = {{\n", .{name}) catch return error.OutOfMemory;
        for (plan.entries[0..plan.len]) |entry| {
            if (entry.tag_offset == scan_always)
                writer.print(" {{.offset={d},.tag_offset=MYL_NATIVE_SCAN_ALWAYS,.tag=0}},\n", .{entry.offset}) catch return error.OutOfMemory
            else
                writer.print(" {{.offset={d},.tag_offset={d},.tag={d}}},\n", .{ entry.offset, entry.tag_offset, entry.tag }) catch return error.OutOfMemory;
        }
        writer.writeAll("};\n") catch return error.OutOfMemory;
    }
    const scan = if (planned) try std.fmt.allocPrint(a, "{s}_scan", .{name}) else "NULL";
    const fields = if (layout.fields.len == 0) "NULL" else try std.fmt.allocPrint(a, "{s}_fields", .{name});
    const trace_fields = if (trace_field_count == 0) "NULL" else try std.fmt.allocPrint(a, "{s}_trace_fields", .{name});
    const trace_mode = if (!layout.trace) "MYL_NATIVE_TRACE_NONE" else "MYL_NATIVE_TRACE_FIELDS";
    var collection_kind: usize = 0;
    var element: []const u8 = "NULL";
    var key: []const u8 = "NULL";
    if (layout.kind == .managed and boxed(catalog, ty) and !target.cell) {
        // RECURSIVE-VALUES-2: a box pointer is kind 5, and its element is the
        // body the value lives in, which equality, hashing and escape read.
        collection_kind = 5;
        // A niche optional emits this descriptor under its own name, so the
        // body is named from the box type rather than from `name`.
        element = try std.fmt.allocPrint(a, "&{s}_body", .{try symbol(a, catalog, ty)});
    } else if (layout.kind == .managed and catalog.records[ty.recordIndex()].isCollection()) {
        const record = catalog.records[ty.recordIndex()];
        collection_kind = switch (record.collection.kind) {
            .list => 1,
            .string => 2,
            .dictionary => 3,
            .bytes => 4,
        };
        const element_type: typed.Type = if (record.collection.kind == .string) .u32 else record.shape.buffer orelse return error.InvalidType;
        element = try std.fmt.allocPrint(a, "&{s}", .{try symbol(a, catalog, element_type)});
        if (record.collection.key) |key_type| key = try std.fmt.allocPrint(a, "&{s}", .{try symbol(a, catalog, key_type)});
    }
    writer.print(
        "const myl_native_type {s} = {{.size={d},.alignment={d},.fields={s},.field_count={d}," ++
            ".count={d},.stride={d},.kind={s},.collection_kind={d},.element={s},.key={s}," ++
            ".trace_fields={s},.trace_field_count={d},.trace_mode={s},.cell={d},.rc_id=MYL_RC_ID_FIRST_GENERATED+{d}",
        .{ name, layout.size, layout.alignment, fields, layout.fields.len, layout.count, layout.stride, kind.spelling(), collection_kind, element, key, trace_fields, trace_field_count, trace_mode, @intFromBool(target.cell), target.id },
    ) catch return error.OutOfMemory;
    writer.print(",.scan={s},.scan_count={d}}};\n", .{ scan, if (planned) plan.len else 0 }) catch return error.OutOfMemory;
}
/// The descriptor kinds of native_heap.h's `MYL_NATIVE_*` enumeration.
const Kind = enum {
    plain,
    pointer,
    record,
    array,
    variant,
    owned_buffer,
    owned_pool,
    float,
    resource,
    /// The C enumerator this kind is spelled with.
    fn spelling(kind: Kind) []const u8 {
        return switch (kind) {
            .plain => "MYL_NATIVE_PLAIN",
            .pointer => "MYL_NATIVE_POINTER",
            .record => "MYL_NATIVE_RECORD",
            .array => "MYL_NATIVE_ARRAY",
            .variant => "MYL_NATIVE_VARIANT",
            .owned_buffer => "MYL_NATIVE_OWNED_BUFFER",
            .owned_pool => "MYL_NATIVE_OWNED_POOL",
            .float => "MYL_NATIVE_FLOAT",
            .resource => "MYL_NATIVE_RESOURCE",
        };
    }
};
/// A descriptor as generated code names it: the type it is emitted for and the
/// layout it is emitted from.
const Described = struct {
    ty: typed.Type,
    layout: native.Layout,
    /// The descriptor a field of type `ty` points at. A niche optional's
    /// descriptor is its payload's pointer descriptor (QBE-NICHE-1).
    fn of(catalog: *native.Catalog, ty: typed.Type) Error!Described {
        const layout = try catalog.layout(ty);
        if (layout.kind != .niche) return .{ .ty = ty, .layout = layout };
        const payload = layout.fields[0].ty;
        return .{ .ty = payload, .layout = try catalog.layout(payload) };
    }
    /// The kind `emit` writes for this descriptor.
    fn kind(self: Described, catalog: *native.Catalog) Kind {
        if (@import("numeric_surface.zig").isFloat(self.ty, catalog.records)) return .float;
        return switch (self.layout.kind) {
            .managed => .pointer,
            .owned_buffer => .owned_buffer,
            .owned_pool => .owned_pool,
            .resource => .resource,
            .record, .domain => .record,
            .array => .array,
            .variant => .variant,
            else => .plain,
        };
    }
};
/// One reference slot of a flat scan plan, as `myl_native_scan_entry` spells it.
const ScanEntry = struct { offset: u64, tag_offset: u64, tag: u64 };
/// `MYL_NATIVE_SCAN_ALWAYS`: the tag offset of a slot outside any union case.
const scan_always: u64 = std.math.maxInt(u32);
/// A plan of at most `MYL_NATIVE_SCAN_ENTRIES` slots.
const ScanPlan = struct { entries: [8]ScanEntry = undefined, len: usize = 0 };
/// Append the reference slots of `target` at `base` under `condition`, exactly
/// as `flatten` in src/native_heap.c walks the emitted descriptor: an untraced
/// descriptor adds nothing, a reference adds one slot, an array repeats its
/// element at each stride, a record adds its traced fields in order and a union
/// its traced cases under their tags. False when the shape needs more than
/// eight slots or nests a union inside a union, where the runtime keeps the
/// recursive walk; `--gc-stress` checks every plan against that walk.
fn flatten(catalog: *native.Catalog, plan: *ScanPlan, target: Described, base: u64, condition: ScanEntry) Error!bool {
    const layout = target.layout;
    if (!layout.trace) return true;
    if (base > scan_always -% layout.size) return false;
    const kind = target.kind(catalog);
    switch (kind) {
        .pointer, .owned_buffer, .owned_pool => {
            if (plan.len == plan.entries.len) return false;
            plan.entries[plan.len] = .{ .offset = base, .tag_offset = condition.tag_offset, .tag = condition.tag };
            plan.len += 1;
            return true;
        },
        .array => {
            const element = (try firstTraced(catalog, layout.fields)) orelse return true;
            const child = try Described.of(catalog, element.ty);
            for (0..layout.count) |index| if (!try flatten(catalog, plan, child, base + index * layout.stride, condition)) return false;
            return true;
        },
        .record, .variant => {
            if (kind == .variant and condition.tag_offset != scan_always) return false;
            for (layout.fields) |field| {
                if (!(try catalog.layout(field.ty)).trace) continue;
                const inner: ScanEntry = if (kind == .variant) .{ .offset = 0, .tag_offset = base, .tag = field.tag orelse 0 } else condition;
                if (!try flatten(catalog, plan, try Described.of(catalog, field.ty), base + field.offset, inner)) return false;
            }
            return true;
        },
        else => return true,
    }
}
/// A copy of a descriptor line with its `.rc_id` initializer cut out, for comparing two descriptors' shapes.
fn withoutId(allocator: std.mem.Allocator, line: []const u8) ![]u8 {
    const from = std.mem.indexOf(u8, line, ",.rc_id=") orelse return allocator.dupe(u8, line);
    const to = std.mem.indexOfPos(u8, line, from, ",.scan=") orelse return allocator.dupe(u8, line);
    return std.mem.concat(allocator, u8, &.{ line[0..from], line[to..] });
}
/// The first field whose type is traced: `trace_fields[0]` of the emitted descriptor.
fn firstTraced(catalog: *native.Catalog, fields: []const native.Field) Error!?native.Field {
    for (fields) |field| if ((try catalog.layout(field.ty)).trace) return field;
    return null;
}

test "native descriptors are catalog-order independent" {
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const base = typed.Type.record_base;
    const records_a = [_]typed.Record{
        .{ .id = @fromBackingInt(base), .name = "A", .declaration = span, .fields = &.{}, .shape = .{ .domain = .i64 } },
        .{ .id = @fromBackingInt(base + 1), .name = "B", .declaration = span, .fields = &.{}, .shape = .{ .array = .{ .element = @fromBackingInt(base), .length = 2 } } },
    };
    const records_b = [_]typed.Record{
        .{ .id = @fromBackingInt(base), .name = "B", .declaration = span, .fields = &.{}, .shape = .{ .array = .{ .element = @fromBackingInt(base + 1), .length = 2 } } },
        .{ .id = @fromBackingInt(base + 1), .name = "A", .declaration = span, .fields = &.{}, .shape = .{ .domain = .i64 } },
    };
    var first = try native.Catalog.initRecords(std.testing.allocator, &records_a);
    defer first.deinit();
    var second = try native.Catalog.initRecords(std.testing.allocator, &records_b);
    defer second.deinit();
    const a = try generate(std.testing.allocator, &first);
    defer std.testing.allocator.free(a);
    const b = try generate(std.testing.allocator, &second);
    defer std.testing.allocator.free(b);
    try std.testing.expectEqualStrings(a, b);
    try std.testing.expect(std.mem.indexOf(u8, a, "MYL_NATIVE_ARRAY") != null);
}

test "native descriptors separate GC fields from complete structural fields" {
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const base = typed.Type.record_base;
    const node: typed.Type = @fromBackingInt(base);
    const holder: typed.Type = @fromBackingInt(base + 1);
    const fields = [_]typed.Field{
        .{ .name = "span", .declaration = span, .ty = .u64 },
        .{ .name = "node", .declaration = span, .ty = node },
    };
    const records = [_]typed.Record{
        .{ .id = node, .name = "Node", .declaration = span, .fields = &.{}, .managed = true },
        .{ .id = holder, .name = "Holder", .declaration = span, .fields = &fields },
    };
    var catalog = try native.Catalog.initRecords(std.testing.allocator, &records);
    defer catalog.deinit();
    const output = try generate(std.testing.allocator, &catalog);
    defer std.testing.allocator.free(output);
    const holder_name = try symbol(std.testing.allocator, &catalog, holder);
    defer std.testing.allocator.free(holder_name);
    const node_name = try symbol(std.testing.allocator, &catalog, node);
    defer std.testing.allocator.free(node_name);
    const trace_field = try std.fmt.allocPrint(std.testing.allocator, "static const myl_native_field {s}_trace_fields[] = {{\n {{.offset=8,.type=&{s},.tag=0}},\n}};", .{ holder_name, node_name });
    defer std.testing.allocator.free(trace_field);
    try std.testing.expect(std.mem.indexOf(u8, output, trace_field) != null);
    const holder_mode = try std.fmt.allocPrint(std.testing.allocator, ".trace_fields={s}_trace_fields,.trace_field_count=1,.trace_mode=MYL_NATIVE_TRACE_FIELDS", .{holder_name});
    defer std.testing.allocator.free(holder_mode);
    try std.testing.expect(std.mem.indexOf(u8, output, holder_mode) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".trace_fields=NULL,.trace_field_count=0,.trace_mode=MYL_NATIVE_TRACE_NONE") != null);
}

// spec-case: QBE-NICHE-1
test "a niche optional is described to the runtime exactly as its payload's pointer" {
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const base = typed.Type.record_base;
    const node: typed.Type = @fromBackingInt(base);
    const maybe: typed.Type = @fromBackingInt(base + 1);
    const holder: typed.Type = @fromBackingInt(base + 2);
    const cases = [_]typed.Variant{ .{ .name = "none", .declaration = span, .payload = null }, .{ .name = "some", .declaration = span, .payload = node } };
    const fields = [_]typed.Field{
        .{ .name = "span", .declaration = span, .ty = .u64 },
        .{ .name = "next", .declaration = span, .ty = maybe },
    };
    const records = [_]typed.Record{
        .{ .id = node, .name = "Node", .declaration = span, .fields = &.{}, .managed = true },
        .{ .id = maybe, .name = "Option<Node>", .declaration = span, .fields = &.{}, .shape = .{ .variants = .{ .is_union = true, .cases = &cases } } },
        .{ .id = holder, .name = "Holder", .declaration = span, .fields = &fields },
    };
    var catalog = try native.Catalog.initRecords(std.testing.allocator, &records);
    defer catalog.deinit();
    const output = try generate(std.testing.allocator, &catalog);
    defer std.testing.allocator.free(output);
    const holder_name = try symbol(std.testing.allocator, &catalog, holder);
    defer std.testing.allocator.free(holder_name);
    const node_name = try symbol(std.testing.allocator, &catalog, node);
    defer std.testing.allocator.free(node_name);
    const maybe_name = try symbol(std.testing.allocator, &catalog, maybe);
    defer std.testing.allocator.free(maybe_name);
    // The holder's GC table names the optional's own descriptor at the field's offset.
    const traced = try std.fmt.allocPrint(std.testing.allocator, "static const myl_native_field {s}_trace_fields[] = {{\n {{.offset=8,.type=&{s},.tag=0}},\n}};", .{ holder_name, maybe_name });
    defer std.testing.allocator.free(traced);
    try std.testing.expect(std.mem.indexOf(u8, output, traced) != null);
    // That descriptor is the payload's pointer descriptor under the optional's name.
    const maybe_head = try std.fmt.allocPrint(std.testing.allocator, "const myl_native_type {s} = ", .{maybe_name});
    defer std.testing.allocator.free(maybe_head);
    const node_head = try std.fmt.allocPrint(std.testing.allocator, "const myl_native_type {s} = ", .{node_name});
    defer std.testing.allocator.free(node_head);
    const maybe_at = std.mem.indexOf(u8, output, maybe_head).? + maybe_head.len;
    const node_at = std.mem.indexOf(u8, output, node_head).? + node_head.len;
    const maybe_body = output[maybe_at..std.mem.indexOfScalarPos(u8, output, maybe_at, '\n').?];
    const node_body = output[node_at..std.mem.indexOfScalarPos(u8, output, node_at, '\n').?];
    // Each has its own descriptor, so its own id (RC-TYPE-ID-1); everything else matches.
    const node_shape = try withoutId(std.testing.allocator, node_body);
    defer std.testing.allocator.free(node_shape);
    const maybe_shape = try withoutId(std.testing.allocator, maybe_body);
    defer std.testing.allocator.free(maybe_shape);
    try std.testing.expectEqualStrings(node_shape, maybe_shape);
    try std.testing.expect(!std.mem.eql(u8, node_body, maybe_body));
    try std.testing.expect(std.mem.indexOf(u8, maybe_body, ".size=8,.alignment=8,.fields=NULL,") != null);
    try std.testing.expect(std.mem.indexOf(u8, maybe_body, ".kind=MYL_NATIVE_POINTER,") != null);
}

// spec: GC-SCAN-PLAN-2
test "a traced aggregate descriptor carries the flat scan plan of its references" {
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const base = typed.Type.record_base;
    const node: typed.Type = @fromBackingInt(base);
    const holder: typed.Type = @fromBackingInt(base + 1);
    const slot: typed.Type = @fromBackingInt(base + 2);
    const trio: typed.Type = @fromBackingInt(base + 3);
    const wide: typed.Type = @fromBackingInt(base + 4);
    const fields = [_]typed.Field{
        .{ .name = "span", .declaration = span, .ty = .u64 },
        .{ .name = "first", .declaration = span, .ty = node },
        .{ .name = "count", .declaration = span, .ty = .u32 },
        .{ .name = "second", .declaration = span, .ty = node },
    };
    const cases = [_]typed.Variant{
        .{ .name = "empty", .declaration = span, .payload = null },
        .{ .name = "number", .declaration = span, .payload = .u64 },
        .{ .name = "full", .declaration = span, .payload = node },
    };
    const records = [_]typed.Record{
        .{ .id = node, .name = "Node", .declaration = span, .fields = &.{}, .managed = true },
        .{ .id = holder, .name = "Holder", .declaration = span, .fields = &fields },
        .{ .id = slot, .name = "Slot", .declaration = span, .fields = &.{}, .shape = .{ .variants = .{ .is_union = true, .cases = &cases } } },
        .{ .id = trio, .name = "Trio", .declaration = span, .fields = &.{}, .shape = .{ .array = .{ .element = node, .length = 3 } } },
        .{ .id = wide, .name = "Wide", .declaration = span, .fields = &.{}, .shape = .{ .array = .{ .element = node, .length = 9 } } },
    };
    var catalog = try native.Catalog.initRecords(std.testing.allocator, &records);
    defer catalog.deinit();
    const output = try generate(std.testing.allocator, &catalog);
    defer std.testing.allocator.free(output);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const always = ",.tag_offset=MYL_NATIVE_SCAN_ALWAYS,.tag=0}},\n";
    // A record's plan names its two references and skips the scalars between them.
    const holder_name = try symbol(a, &catalog, holder);
    const holder_plan = try std.fmt.allocPrint(a, "{s}_scan[] = {{\n {{.offset=8" ++ always ++ " {{.offset=24" ++ always ++ "}};\n", .{holder_name});
    try std.testing.expect(std.mem.indexOf(u8, output, holder_plan) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, try std.fmt.allocPrint(a, ".scan={s}_scan,.scan_count=2}};", .{holder_name})) != null);
    // A union's reference is live only under its case's tag, read at the union's start.
    const slot_plan = try std.fmt.allocPrint(a, "{s}_scan[] = {{\n {{.offset=8,.tag_offset=0,.tag=2}},\n}};\n", .{try symbol(a, &catalog, slot)});
    try std.testing.expect(std.mem.indexOf(u8, output, slot_plan) != null);
    // A fixed array repeats its element's slot at every stride.
    const trio_plan = try std.fmt.allocPrint(a, "{s}_scan[] = {{\n {{.offset=0" ++ always ++ " {{.offset=8" ++ always ++ " {{.offset=16" ++ always ++ "}};\n", .{try symbol(a, &catalog, trio)});
    try std.testing.expect(std.mem.indexOf(u8, output, trio_plan) != null);
    // Nine references do not fit a plan, and a reference needs none: both keep the walk.
    const wide_name = try symbol(a, &catalog, wide);
    try std.testing.expect(std.mem.indexOf(u8, output, try std.fmt.allocPrint(a, "{s}_scan[]", .{wide_name})) == null);
    const wide_head = try std.fmt.allocPrint(a, "const myl_native_type {s} = ", .{wide_name});
    const wide_at = std.mem.indexOf(u8, output, wide_head).?;
    try std.testing.expect(std.mem.endsWith(u8, output[wide_at..std.mem.indexOfScalarPos(u8, output, wide_at, '\n').?], ".scan=NULL,.scan_count=0};"));
    const node_head = try std.fmt.allocPrint(a, "const myl_native_type {s} = ", .{try symbol(a, &catalog, node)});
    const node_at = std.mem.indexOf(u8, output, node_head).?;
    try std.testing.expect(std.mem.endsWith(u8, output[node_at..std.mem.indexOfScalarPos(u8, output, node_at, '\n').?], ".scan=NULL,.scan_count=0};"));
}
