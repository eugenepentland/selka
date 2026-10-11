//! Structural retained-schema authority and bounded record/list policy closure.
const std = @import("std");
const value = @import("body_check_value.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
pub const Error = error{ OutOfMemory, ComponentProtocol };
/// Ordinary copyable value records; specialized, boxed and owned schemas require another closure.
pub fn ordinary(record: typed.Record) bool {
    if (!record.isRecord() or record.managed) return false;
    if (record.shape.tuple or record.shape.builtin != .none) return false;
    if (record.contract.callback != null or record.contract.codec != null or record.contract.codec_declared) return false;
    if (record.contract.move_only or !record.contract.storable or record.contract.requires_handling) return false;
    for (record.fields) |field| if (field.boxed) return false;
    return true;
}
/// Dense retained prefix remains separate from producer-added list identities.
pub fn catalog(item: value.Catalog) Error!void {
    if (item.records.len > item.base_count or item.base_count > 65536) return error.ComponentProtocol;
    var fields: usize = 0;
    for (item.records, 0..) |record, index| {
        if (@backingInt(record.id) != typed.Type.record_base + index) return error.ComponentProtocol;
        if (record.fields.len > 65536 - fields) return error.ComponentProtocol;
        fields += record.fields.len;
        for (record.fields) |field| {
            if (field.ty.isAggregate() and field.ty.recordIndex() >= item.base_count) return error.ComponentProtocol;
        }
    }
}
const Edge = struct { parent: usize, next: ?usize };
/// Greatest fixed point: list-backed recursion is permitted; unsupported reachable members propagate backward.
pub fn policy(a: std.mem.Allocator, item: value.Catalog) Error![]bool {
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
    for (item.records, 0..) |record, index| allowed[index] = ordinary(record);
    if (item.string) |entry| try mark(allowed, entry.id);
    if (item.bytes) |entry| try mark(allowed, entry.id);
    for (item.lists) |entry| try mark(allowed, entry.id);
    var builder: Builder = .{ .allocator = a, .allowed = allowed, .heads = heads, .edges = &edges };
    for (item.records, 0..) |record, index| {
        if (!ordinary(record)) continue;
        for (record.fields) |field| try builder.dependency(index, field.ty);
    }
    for (item.lists) |entry| try builder.dependency(entry.id.recordIndex(), entry.element);
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
        if (ty == .i64 or ty == .bool or ty == .unit) return;
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
    for (request.program.attributes) |entry| for (entry.attributes) |attribute| {
        if (attribute.kind.contract()) return error.ComponentProtocol;
    };
    if (request.program.types.domains.len != 0 or request.program.types.variants.len != 0 or request.program.types.resources.len != 0) return error.ComponentProtocol;
    var raw: std.AutoHashMapUnmanaged(source.Span, void) = .empty;
    defer raw.deinit(a);
    for (request.program.types.records) |record| {
        if (record.managed or record.type_parameters.len != 0) return error.ComponentProtocol;
        try raw.put(a, record.name, {});
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

fn recordName(request: value.Input, record: typed.Record, declaration: source.Span) Error!void {
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
        if (!ordinary(record)) continue;
        total += 1;
        for (record.fields) |field| {
            if (!field.ty.isAggregate() or field.ty.recordIndex() >= item.records.len) continue;
            const child = field.ty.recordIndex();
            if (!ordinary(item.records[child])) continue;
            counts[parent] += 1;
            try edges.append(a, .{ .parent = parent, .next = heads[child] });
            heads[child] = edges.items.len - 1;
        }
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
