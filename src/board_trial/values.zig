//! Trusted nominal snapshot conversion and owned result decoding for the trial ABI.
const std = @import("std");
const language = @import("mylang");
const m = @import("model.zig");
pub const Value = language.vm.Value;
pub const Type = @FieldType(language.host_functions.Parameter, "ty");
const Records = @FieldType(language.bytecode.Program, "records");
const Record = @typeInfo(Records).pointer.child;
pub const Error = error{ SnapshotSchemaMismatch, SnapshotCapacity, OutOfMemory, InvalidAggregateType };
/// Borrows the immutable compilation's nominal definitions.
pub const Meta = struct {
    records: Records,
    /// Resolve an exact qualified nominal type name.
    pub fn find(self: Meta, name: []const u8) Error!Type {
        for (self.records) |record| if (std.mem.eql(u8, record.name, name)) return record.id;
        return error.SnapshotSchemaMismatch;
    }
    /// Validate and borrow a nominal definition by its catalog identity.
    pub fn definition(self: Meta, ty: Type) Error!Record {
        if (!ty.isAggregate() or ty.recordIndex() >= self.records.len) return error.SnapshotSchemaMismatch;
        return self.records[ty.recordIndex()];
    }
    /// Borrow a named field after checking the aggregate shape.
    pub fn field(self: Meta, value: Value, name: []const u8) Error!Value {
        const record = try self.definition(value.typeOf());
        if (value != .aggregate or value.aggregate.fields.len != record.fields.len) return error.SnapshotSchemaMismatch;
        for (record.fields, 0..) |item, index| if (std.mem.eql(u8, item.name, name)) return value.aggregate.fields[index];
        return error.SnapshotSchemaMismatch;
    }
    /// Resolve a named variant and its declared payload type.
    pub fn case(self: Meta, ty: Type, name: []const u8) Error!struct { tag: usize, payload: ?Type } {
        const variants = (try self.definition(ty)).shape.variants orelse return error.SnapshotSchemaMismatch;
        for (variants.cases, 0..) |entry, index| if (std.mem.eql(u8, entry.name, name)) return .{ .tag = index, .payload = entry.payload };
        return error.SnapshotSchemaMismatch;
    }
    /// Decode a validated variant tag to its declared name.
    pub fn tag(self: Meta, value: Value) Error![]const u8 {
        const variants = (try self.definition(value.typeOf())).shape.variants orelse return error.SnapshotSchemaMismatch;
        const index = value.variantTag() catch return error.SnapshotSchemaMismatch;
        if (index >= variants.cases.len) return error.SnapshotSchemaMismatch;
        return variants.cases[index].name;
    }
    /// Construct an owned variant only with its exact declared payload type.
    pub fn variant(self: Meta, allocator: std.mem.Allocator, ty: Type, name: []const u8, value: ?Value) Error!Value {
        const entry = try self.case(ty, name);
        if (entry.payload != if (value) |payload| payload.typeOf() else @as(?Type, null)) return error.SnapshotSchemaMismatch;
        return Value.createVariant(allocator, ty, entry.tag, value);
    }
};
/// Owns the entire ordinary input graph in one arena, including failure paths.
pub const Snapshot = struct {
    arena: std.heap.ArenaAllocator,
    value: Value,
    /// Build a bounded nominal board snapshot in a separately owned arena.
    pub fn init(allocator: std.mem.Allocator, meta: Meta, board: m.Board) Error!Snapshot {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const builder: Builder = .{ .arena = &arena, .meta = meta };
        const value = try builder.build(try meta.find("model::Board"), board);
        return .{ .arena = arena, .value = value };
    }
    /// Release the entire copied snapshot graph and partial construction storage.
    pub fn deinit(self: *Snapshot) void {
        self.arena.deinit();
    }
};
const Builder = struct {
    arena: *std.heap.ArenaAllocator,
    meta: Meta,
    fn build(self: Builder, ty: Type, input: anytype) Error!Value {
        const T = @TypeOf(input);
        const allocator = self.arena.allocator();
        if (T == bool) return if (ty == .bool) .{ .bool = input } else error.SnapshotSchemaMismatch;
        if (@typeInfo(T) == .pointer) {
            const shape = (try self.meta.definition(ty)).shape.array orelse return error.SnapshotSchemaMismatch;
            const count: usize = if (@typeInfo(T).pointer.child == m.Feature) 8 else 4;
            if (shape.length != count) return error.SnapshotSchemaMismatch;
            if (input.len > count) return error.SnapshotCapacity;
            const payload = (try self.meta.case(shape.element, "some")).payload orelse return error.SnapshotSchemaMismatch;
            const fields = try allocator.alloc(Value, count);
            for (fields, 0..) |*field, index| field.* = if (index < input.len)
                try self.meta.variant(allocator, shape.element, "some", try self.build(payload, input[index]))
            else
                try self.meta.variant(allocator, shape.element, "none", null);
            return Value.create(allocator, ty, fields);
        }
        if (ty != try self.meta.find(typeName(T))) return error.SnapshotSchemaMismatch;
        switch (@typeInfo(T)) {
            .@"enum" => |info| {
                if (info.mode == .exhaustive) return self.meta.variant(allocator, ty, @tagName(input), null);
                const backing = (try self.meta.definition(ty)).shape.domain orelse return error.SnapshotSchemaMismatch;
                const expected: Type = if (T == m.Micrometres) .i64 else .u64;
                if (backing != expected) return error.SnapshotSchemaMismatch;
                return Value.create(allocator, ty, &.{Value.number(backing, @backingInt(input))});
            },
            .@"struct" => |info| {
                const record = try self.meta.definition(ty);
                if (!record.isRecord() or record.fields.len != info.field_names.len) return error.SnapshotSchemaMismatch;
                const fields = try allocator.alloc(Value, record.fields.len);
                for (record.fields, fields) |field, *out| {
                    var matched = false;
                    inline for (info.field_names) |native| if (std.mem.eql(u8, field.name, native)) {
                        out.* = try self.build(field.ty, @field(input, native));
                        matched = true;
                    };
                    if (!matched) return error.SnapshotSchemaMismatch;
                }
                return Value.create(allocator, ty, fields);
            },
            .@"union" => return switch (input) {
                inline else => |payload, name| blk: {
                    const entry = try self.meta.case(ty, @tagName(name));
                    break :blk self.meta.variant(allocator, ty, @tagName(name), try self.build(entry.payload orelse return error.SnapshotSchemaMismatch, payload));
                },
            },
            else => @compileError("unsupported native snapshot field"),
        }
    }
};
fn typeName(comptime T: type) []const u8 {
    inline for (.{
        .{ m.ComponentId, "ids::ComponentId" }, .{ m.NetId, "ids::NetId" },     .{ m.Micrometres, "units::Micrometres" },
        .{ m.Rect, "model::Rect" },             .{ m.Face, "model::Face" },     .{ m.RegionFace, "model::RegionFace" },
        .{ m.Layer, "model::Layer" },           .{ m.Blocks, "model::Blocks" }, .{ m.Component, "model::Component" },
        .{ m.Track, "model::Track" },           .{ m.Via, "model::Via" },       .{ m.Feature, "model::Feature" },
        .{ m.Region, "model::Region" },         .{ m.Board, "model::Board" },
    }) |entry| if (T == entry[0]) return entry[1];
    @compileError("native type has no trial schema identity");
}
fn bodyValue(value: Value) Error!Value {
    if (value != .aggregate or value.aggregate.fields.len != 1) return error.SnapshotSchemaMismatch;
    return value.aggregate.fields[0];
}
fn enumeration(comptime T: type, meta: Meta, value: Value) Error!T {
    return std.meta.stringToEnum(T, try meta.tag(value)) orelse error.SnapshotSchemaMismatch;
}
fn number(value: Value) Error!u64 {
    if (value.typeOf() != .u64) return error.SnapshotSchemaMismatch;
    return std.math.cast(u64, value.asInteger() catch return error.SnapshotSchemaMismatch) orelse error.SnapshotSchemaMismatch;
}
/// Decode named result cases and report fields, retaining no borrowed value storage.
pub fn outcome(meta: Meta, value: Value) Error!m.Outcome {
    if (value.typeOf() != try meta.find("model::Validation")) return error.SnapshotSchemaMismatch;
    const name = try meta.tag(value);
    const body = try bodyValue(value);
    if (std.mem.eql(u8, name, "err")) {
        const category = try meta.tag(body);
        if (std.mem.eql(u8, category, "input")) return .{ .err = .{ .input = try enumeration(m.InputProblem, meta, try bodyValue(body)) } };
        if (std.mem.eql(u8, category, "geometry")) return .{ .err = .{ .geometry = try enumeration(m.GeometryFailure, meta, try bodyValue(body)) } };
        return error.SnapshotSchemaMismatch;
    }
    if (!std.mem.eql(u8, name, "ok")) return error.SnapshotSchemaMismatch;
    if ((try meta.definition(body.typeOf())).fields.len != 2) return error.SnapshotSchemaMismatch;
    var report: m.Report = .{ .violations = try number(try meta.field(body, "violations")) };
    const first = try meta.field(body, "first");
    const first_tag = try meta.tag(first);
    if (std.mem.eql(u8, first_tag, "some")) {
        const item = try bodyValue(first);
        if ((try meta.definition(item.typeOf())).fields.len != 3) return error.SnapshotSchemaMismatch;
        const region = try meta.field(item, "region");
        const region_tag = try meta.tag(region);
        var index: ?u64 = null;
        if (std.mem.eql(u8, region_tag, "keepout")) index = try number(try bodyValue(region)) else if (!std.mem.eql(u8, region_tag, "board")) return error.SnapshotSchemaMismatch;
        report.first = .{ .feature = try number(try meta.field(item, "feature")), .kind = try enumeration(m.ViolationKind, meta, try meta.field(item, "kind")), .region = index };
    } else if (!std.mem.eql(u8, first_tag, "none")) return error.SnapshotSchemaMismatch;
    return .{ .ok = report };
}
/// Read one validated ordinary rectangle at the trusted callback boundary.
pub fn rect(meta: Meta, value: Value) Error!m.Rect {
    if (value.typeOf() != try meta.find("model::Rect")) return error.SnapshotSchemaMismatch;
    var result: m.Rect = undefined;
    inline for (@typeInfo(m.Rect).@"struct".field_names) |field| {
        const domain = try meta.field(value, field);
        if (domain.typeOf() != try meta.find("units::Micrometres")) return error.SnapshotSchemaMismatch;
        const raw = try bodyValue(domain);
        if (raw != .i64) return error.SnapshotSchemaMismatch;
        @field(result, field) = @fromBackingInt(raw.i64);
    }
    return result;
}
