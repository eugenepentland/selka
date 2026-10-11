//! Structural retained-schema authority and bounded record/list policy closure.
const std = @import("std");
const dictionaries = @import("body_check_dictionary_validate.zig");
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const structural = @import("body_check_structural_validate.zig");
pub const Error = error{ OutOfMemory, ComponentProtocol };
/// Ordinary copyable value records; specialized, boxed and owned schemas require another closure.
pub fn ordinary(record: typed.Record) bool {
    if (!record.isRecord() or record.managed) return false;
    if (record.shape.tuple or record.shape.builtin != .none) return false;
    if (record.contract.callback != null or record.contract.codec != null or record.contract.codec_declared) return false;
    if (record.contract.move_only) return false;
    if (!record.contract.storable and !record.contract.requires_handling) return false;
    for (record.fields) |field| if (field.boxed) return false;
    return true;
}
/// Ordinary closed enums/unions and checked results; ownership is validated separately.
pub fn variant(record: typed.Record) bool {
    const shape = record.shape.variants orelse return false;
    if (record.managed or record.shape.hasRuntimeIdentity() or record.shape.array != null or record.shape.domain != null) return false;
    if (record.shape.builtin != .none or record.shape.tuple or record.fields.len != 0) return false;
    if (record.contract.callback != null or record.contract.codec != null or record.contract.codec_declared or record.contract.move_only) return false;
    for (shape.cases) |item| if (item.boxed) return false;
    return true;
}
fn valueRecord(record: typed.Record) bool {
    return ordinary(record) or variant(record) or structural.tuple(record) or structural.array(record);
}
/// Dense retained prefix remains separate from producer-added list identities.
pub fn catalog(item: value.Catalog) Error!void {
    if (item.records.len > item.base_count or item.base_count > 65536) return error.ComponentProtocol;
    var fields: usize = 0;
    var cases: usize = 0;
    for (item.records, 0..) |record, index| {
        if (@backingInt(record.id) != typed.Type.record_base + index) return error.ComponentProtocol;
        if (record.fields.len > 65536 - fields) return error.ComponentProtocol;
        fields += record.fields.len;
        if (record.shape.tuple and !structural.tupleLayout(record)) return error.ComponentProtocol;
        if (record.shape.array) |shape| {
            if (shape.element.isAggregate() and shape.element.recordIndex() >= item.base_count) return error.ComponentProtocol;
            if (shape.key) |key| {
                if (!key.isAggregate() or key.recordIndex() >= item.records.len) return error.ComponentProtocol;
                const enumeration = item.records[key.recordIndex()];
                if (!enumeration.isEnum()) return error.ComponentProtocol;
                if (shape.length != enumeration.shape.variants.?.cases.len or record.fields.len != shape.length) return error.ComponentProtocol;
                for (record.fields, enumeration.shape.variants.?.cases) |field, entry| {
                    if (field.ty != shape.element) return error.ComponentProtocol;
                    if (!std.mem.eql(u8, field.name, entry.name) or !std.meta.eql(field.declaration, entry.declaration)) return error.ComponentProtocol;
                }
            }
        }
        if (record.shape.variants) |shape| {
            if (shape.cases.len > 65536 - cases) return error.ComponentProtocol;
            cases += shape.cases.len;
            if (shape.fallible and !shape.is_union) return error.ComponentProtocol;
            for (shape.cases) |item_case| if (!shape.is_union and item_case.payload != null) return error.ComponentProtocol;
            for (shape.cases) |item_case| if (item_case.payload) |payload| {
                if (payload.isAggregate() and payload.recordIndex() >= item.base_count) return error.ComponentProtocol;
            };
        }
        for (record.fields) |field| {
            if (field.ty.isAggregate() and field.ty.recordIndex() >= item.base_count) return error.ComponentProtocol;
        }
    }
}
const Edge = struct { parent: usize, next: ?usize };
/// Greatest fixed point: list-backed recursion is permitted; unsupported reachable members propagate backward.
pub fn policy(a: std.mem.Allocator, item: value.Catalog) Error![]bool {
    return policyMode(a, item, false);
}
/// Structural hash-key closure rejects mutable or pending members without rechecking source bodies.
pub fn hashablePolicy(a: std.mem.Allocator, item: value.Catalog) Error![]bool {
    return policyMode(a, item, true);
}
fn policyMode(a: std.mem.Allocator, item: value.Catalog, hashable: bool) Error![]bool {
    try catalog(item);
    const allowed = try a.alloc(bool, item.base_count);
    errdefer a.free(allowed);
    @memset(allowed, false);
    const heads = try a.alloc(?usize, item.base_count);
    defer a.free(heads);
    @memset(heads, null);
    var edges: std.ArrayList(Edge) = .empty;
    defer edges.deinit(a);
    var pending: std.ArrayList(usize) = .empty;
    defer pending.deinit(a);
    for (item.records, 0..) |record, index| {
        allowed[index] = valueRecord(record) or @import("body_check_numeric_validate.zig").floating(item, record.id);
        if (hashable and record.contract.requires_handling) allowed[index] = false;
        if (!hashable and dictionaries.identify(item, record.id) != null) allowed[index] = true;
    }
    if (item.string) |entry| try mark(allowed, entry.id);
    if (item.bytes) |entry| try mark(allowed, entry.id);
    if (!hashable) {
        if (item.templates.byte_buffer.identity) |entry| try mark(allowed, entry.id);
        for (item.lists) |entry| try mark(allowed, entry.id);
    }
    var builder: Builder = .{ .allocator = a, .allowed = allowed, .heads = heads, .edges = &edges };
    for (item.records, 0..) |record, index| {
        const collection = dictionaries.identify(item, record.id);
        if (!valueRecord(record) and collection == null) continue;
        if (collection) |entry| try collectionDependencies(&builder, item, index, entry);
        if (record.shape.array) |shape| try arrayDependencies(&builder, index, shape);
        for (record.fields) |field| try builder.dependency(index, field.ty);
        if (record.shape.variants) |shape| for (shape.cases) |item_case| {
            if (item_case.payload) |payload| {
                const file_result = @import("body_check_resource_authority.zig").fileResult(item, record.id);
                if (file_result != payload) try builder.dependency(index, payload);
            }
        };
    }
    for (item.lists) |entry| {
        try builder.dependency(entry.id.recordIndex(), entry.element);
        if (entry.element.isAggregate() and entry.element.recordIndex() < item.records.len) {
            const schema = item.records[entry.element.recordIndex()];
            if (schema.contract.requires_handling or schema.contract.move_only or !schema.contract.storable) allowed[entry.id.recordIndex()] = false;
        }
    }
    for (allowed, 0..) |accepted, index| if (!accepted) try pending.append(a, index);
    var cursor: usize = 0;
    while (cursor < pending.items.len) : (cursor += 1) {
        var link = heads[pending.items[cursor]];
        while (link) |id| {
            const edge = edges.items[id];
            if (allowed[edge.parent]) {
                allowed[edge.parent] = false;
                try pending.append(a, edge.parent);
            }
            link = edge.next;
        }
    }
    return allowed;
}
fn mark(allowed: []bool, id: typed.Type) Error!void {
    if (!id.isAggregate() or id.recordIndex() >= allowed.len) return error.ComponentProtocol;
    allowed[id.recordIndex()] = true;
}
const Builder = struct {
    allocator: std.mem.Allocator,
    allowed: []bool,
    heads: []?usize,
    edges: *std.ArrayList(Edge),
    fn dependency(self: *Builder, parent: usize, ty: typed.Type) Error!void {
        if (scalar(ty)) return;
        if (!ty.isAggregate()) {
            self.allowed[parent] = false;
            return;
        }
        const child = ty.recordIndex();
        if (child >= self.allowed.len or self.edges.items.len >= 131072) return error.ComponentProtocol;
        try self.edges.append(self.allocator, .{ .parent = parent, .next = self.heads[child] });
        self.heads[child] = self.edges.items.len - 1;
    }
};
/// Full raw authority is checked once; neither unsupported declarations nor contract lowering may disappear.
pub fn success(a: std.mem.Allocator, request: value.Input) Error!void {
    if (request.program.lambdas.len != 0) return error.ComponentProtocol;
    for (request.program.functions) |function| if (function.signature.type_parameters.len != 0) return error.ComponentProtocol;
    for (request.program.attributes) |entry| for (entry.attributes) |attribute| {
        if (attribute.kind.contract()) return error.ComponentProtocol;
    };
    if (request.program.types.domains.len != 0 or request.program.types.resources.len != 0) return error.ComponentProtocol;
    var raw: std.AutoHashMapUnmanaged(source.Span, void) = .empty;
    defer raw.deinit(a);
    for (request.program.types.records) |record| {
        if (record.managed or record.type_parameters.len != 0) return error.ComponentProtocol;
        try raw.put(a, record.name, {});
    }
    for (request.program.types.variants) |item_variant| {
        if (item_variant.type_parameters.len != 0) {
            const result_basis = request.catalog.templates.result;
            const option_basis = request.catalog.templates.option;
            const retained_result = if (result_basis) |basis| std.meta.eql(basis.declaration, item_variant.name) else false;
            const retained_option = if (option_basis) |basis| std.meta.eql(basis.declaration, item_variant.name) else false;
            if (!retained_result and !retained_option) return error.ComponentProtocol;
            continue;
        }
        try raw.put(a, item_variant.name, {});
    }
    const accepted = try policy(a, request.catalog);
    defer a.free(accepted);
    for (request.catalog.records) |record| {
        if (raw.contains(record.declaration) and !accepted[record.id.recordIndex()]) return error.ComponentProtocol;
    }
}
/// Validate nongeneric record identity against its original raw declaration without re-resolving types.
pub fn input(a: std.mem.Allocator, request: value.Input) Error!void {
    if (request.catalog.records.len != request.catalog.base_count) return error.ComponentProtocol;
    try catalog(request.catalog);
    try layouts(a, request.catalog);
    try variants(a, request);
    try @import("parser_value_validate.zig").ranges([]const typed.Record, request.catalog.records, request.context.source.len);
    var declarations: std.AutoHashMapUnmanaged(source.Span, @import("ast.zig").Record) = .empty;
    defer declarations.deinit(a);
    for (request.program.types.records) |record| {
        const result = try declarations.getOrPut(a, record.name);
        if (result.found_existing) return error.ComponentProtocol;
        result.value_ptr.* = record;
    }
    var seen: std.AutoHashMapUnmanaged(source.Span, void) = .empty;
    defer seen.deinit(a);
    for (request.catalog.records) |record| {
        if (!ordinary(record)) continue;
        const raw = declarations.get(record.declaration) orelse continue;
        if (raw.type_parameters.len != 0) continue;
        const identity = try seen.getOrPut(a, raw.name);
        if (identity.found_existing) return error.ComponentProtocol;
        try recordName(request, record, raw.name);
        if (raw.fields.len != record.fields.len) return error.ComponentProtocol;
        var names: std.StringHashMapUnmanaged(void) = .empty;
        defer names.deinit(a);
        for (record.fields, raw.fields) |field, original| {
            if (!std.meta.eql(field.declaration, original.name)) return error.ComponentProtocol;
            if (!std.mem.eql(u8, field.name, request.context.source[original.name.start..original.name.end])) return error.ComponentProtocol;
            if (field.default_value != if (original.default_value) |id| @as(?usize, @backingInt(id)) else null) return error.ComponentProtocol;
            const entry = try names.getOrPut(a, field.name);
            if (entry.found_existing) return error.ComponentProtocol;
        }
    }
}

/// Validate bare or module-qualified source declaration naming.
pub fn recordName(request: value.Input, record: typed.Record, declaration: source.Span) Error!void {
    const bare = request.context.source[declaration.start..declaration.end];
    if (request.modules.len == 0) {
        if (!std.mem.eql(u8, record.name, bare)) return error.ComponentProtocol;
        return;
    }
    for (request.modules) |module| {
        if (declaration.start < module.offset or declaration.end > module.offset + module.context.source.len) continue;
        const prefix = module.context.name;
        if (record.name.len != prefix.len + 2 + bare.len) return error.ComponentProtocol;
        if (!std.mem.eql(u8, record.name[0..prefix.len], prefix)) return error.ComponentProtocol;
        if (!std.mem.eql(u8, record.name[prefix.len..][0..2], "::")) return error.ComponentProtocol;
        if (!std.mem.eql(u8, record.name[prefix.len + 2 ..], bare)) return error.ComponentProtocol;
        return;
    }
    return error.ComponentProtocol;
}

fn layouts(a: std.mem.Allocator, item: value.Catalog) Error!void {
    const counts = try a.alloc(usize, item.records.len);
    defer a.free(counts);
    @memset(counts, 0);
    const heads = try a.alloc(?usize, item.records.len);
    defer a.free(heads);
    @memset(heads, null);
    var edges: std.ArrayList(Edge) = .empty;
    defer edges.deinit(a);
    var pending: std.ArrayList(usize) = .empty;
    defer pending.deinit(a);
    var total: usize = 0;
    for (item.records, 0..) |record, parent| {
        if (!valueRecord(record)) continue;
        total += 1;
        if (record.shape.array) |shape| if (shape.length != 0 and shape.element.isAggregate() and shape.element.recordIndex() < item.records.len) {
            const child = shape.element.recordIndex();
            if (valueRecord(item.records[child])) {
                counts[parent] += 1;
                try edges.append(a, .{ .parent = parent, .next = heads[child] });
                heads[child] = edges.items.len - 1;
            }
        };
        for (record.fields) |field| {
            if (!field.ty.isAggregate() or field.ty.recordIndex() >= item.records.len) continue;
            const child = field.ty.recordIndex();
            if (!valueRecord(item.records[child])) continue;
            counts[parent] += 1;
            try edges.append(a, .{ .parent = parent, .next = heads[child] });
            heads[child] = edges.items.len - 1;
        }
        if (record.shape.variants) |shape| for (shape.cases) |item_case| {
            const payload = item_case.payload orelse continue;
            if (!payload.isAggregate() or payload.recordIndex() >= item.records.len) continue;
            const child = payload.recordIndex();
            if (!valueRecord(item.records[child])) continue;
            counts[parent] += 1;
            try edges.append(a, .{ .parent = parent, .next = heads[child] });
            heads[child] = edges.items.len - 1;
        };
        if (counts[parent] == 0) try pending.append(a, parent);
    }
    var cursor: usize = 0;
    while (cursor < pending.items.len) : (cursor += 1) {
        var link = heads[pending.items[cursor]];
        while (link) |id| {
            const edge = edges.items[id];
            counts[edge.parent] -= 1;
            if (counts[edge.parent] == 0) try pending.append(a, edge.parent);
            link = edge.next;
        }
    }
    if (cursor != total) return error.ComponentProtocol;
}

fn variants(a: std.mem.Allocator, request: value.Input) Error!void {
    const Raw = @import("ast.zig").Variants;
    var declared: std.AutoHashMapUnmanaged(source.Span, Raw) = .empty;
    defer declared.deinit(a);
    for (request.program.types.variants) |raw| {
        const entry = try declared.getOrPut(a, raw.name);
        if (entry.found_existing) return error.ComponentProtocol;
        entry.value_ptr.* = raw;
    }
    var seen: std.AutoHashMapUnmanaged(source.Span, void) = .empty;
    defer seen.deinit(a);
    for (request.catalog.records) |record| {
        const schema = record.shape.variants orelse continue;
        const raw = declared.get(record.declaration) orelse continue;
        if (raw.type_parameters.len != 0) continue;
        const entry = try seen.getOrPut(a, raw.name);
        if (entry.found_existing) return error.ComponentProtocol;
        try recordName(request, record, raw.name);
        if (schema.fallible != raw.fallible or schema.is_union != raw.is_union or schema.cases.len != raw.cases.len) return error.ComponentProtocol;
        for (schema.cases, raw.cases) |item, original| {
            if (!std.meta.eql(item.declaration, original.name)) return error.ComponentProtocol;
            if (!std.mem.eql(u8, item.name, request.context.source[original.name.start..original.name.end])) return error.ComponentProtocol;
            if (item.fielded != (original.fields.len != 0)) return error.ComponentProtocol;
            if ((item.payload != null) != (original.payload != null or original.fields.len != 0)) return error.ComponentProtocol;
            if (!item.fielded) continue;
            const payload = item.payload orelse return error.ComponentProtocol;
            if (!payload.isAggregate() or payload.recordIndex() >= request.catalog.records.len) return error.ComponentProtocol;
            const fields = request.catalog.records[payload.recordIndex()].fields;
            if (fields.len != original.fields.len) return error.ComponentProtocol;
            for (fields, original.fields) |field, parameter| {
                if (!std.meta.eql(field.declaration, parameter.name)) return error.ComponentProtocol;
                if (!std.mem.eql(u8, field.name, request.context.source[parameter.name.start..parameter.name.end])) return error.ComponentProtocol;
                if (field.default_value != if (parameter.default_value) |id| @as(?usize, @backingInt(id)) else null) return error.ComponentProtocol;
            }
        }
    }
}

fn arrayDependencies(builder: *Builder, index: usize, shape: typed.Array) Error!void {
    if (shape.length != 0) try builder.dependency(index, shape.element);
    if (shape.key) |key| try builder.dependency(index, key);
}
fn collectionDependencies(builder: *Builder, item: value.Catalog, index: usize, entry: dictionaries.Descriptor) Error!void {
    if (entry.kind != .dict and entry.kind != .set) return;
    try builder.dependency(index, entry.key);
    try builder.dependency(index, entry.value);
    for ([_]typed.Type{ entry.key, entry.value }) |member| if (member.isAggregate()) {
        if (member.recordIndex() >= item.records.len) return error.ComponentProtocol;
        const contract = item.records[member.recordIndex()].contract;
        if (contract.requires_handling or contract.move_only or !contract.storable) builder.allowed[index] = false;
    };
}

fn scalar(ty: typed.Type) bool {
    return @import("body_check_numeric_validate.zig").scalar(ty);
}
