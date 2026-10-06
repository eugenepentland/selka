//! The generator's checked type graph, ported from schema_graph.definition.
//! This private in-memory graph does not change any published schema format.
const std = @import("std");
const typed = @import("mylang").typed;
const Value = std.json.Value;

/// Build every checked type definition needed by Core property generation.
pub fn definitions(a: std.mem.Allocator, program: typed.Program) error{OutOfMemory}![]const Value {
    var out: std.ArrayList(Value) = .empty;
    for (0..typed.Type.record_base + program.records.len) |index| {
        const ty: typed.Type = @fromBackingInt(@intCast(index));
        try out.append(a, try definition(a, program, ty));
    }
    return out.toOwnedSlice(a);
}

fn definition(a: std.mem.Allocator, p: typed.Program, ty: typed.Type) error{OutOfMemory}!Value {
    var out: std.json.ObjectMap = .empty;
    try text(a, &out, "name", typed.typeName(ty, p.records));
    if (ty.integer()) |integer| {
        try text(a, &out, "kind", "integer");
        try out.put(a, "bits", .{ .integer = integer.bits });
        try out.put(a, "signed", .{ .bool = integer.signed });
    } else if (ty == .unit or ty == .bool or !ty.isAggregate()) {
        try text(a, &out, "kind", if (ty == .unit) "unit" else if (ty == .bool) "boolean" else "capability");
    } else {
        const r = p.records[ty.recordIndex()];
        if (r.contract.callback != null) {
            try text(a, &out, "kind", "callback");
        } else if (r.shape.domain != null or r.shape.hasRuntimeIdentity()) {
            try text(a, &out, "kind", if (r.shape.domain != null) "domain" else if (r.managed) "list" else "handle");
            if (r.shape.buffer) |element| try text(a, &out, "element", typed.typeName(element, p.records));
            if (r.collection.key) |key| try text(a, &out, "key", typed.typeName(key, p.records));
        } else if (r.shape.array) |array| {
            try text(a, &out, "kind", if (array.key != null) "table" else "array");
            try text(a, &out, "element", typed.typeName(array.element, p.records));
            try out.put(a, "length", .{ .integer = @intCast(array.length) });
            if (array.key) |key| try text(a, &out, "key", typed.typeName(key, p.records));
        } else if (r.shape.variants) |variants| {
            try text(a, &out, "kind", if (variants.fallible) "result" else if (variants.is_union) "tagged_union" else "enumeration");
            var cases: std.json.Array = .init(a);
            for (variants.cases) |case| {
                var item: std.json.ObjectMap = .empty;
                try text(a, &item, "name", case.name);
                if (case.payload) |payload| try text(a, &item, "payload", typed.typeName(payload, p.records));
                try cases.append(.{ .object = item });
            }
            try out.put(a, "cases", .{ .array = cases });
        } else {
            try text(a, &out, "kind", "record");
            if (r.isManagedRecord()) try out.put(a, "class", .{ .bool = true });
            var fields: std.json.Array = .init(a);
            for (r.fields) |field| {
                var item: std.json.ObjectMap = .empty;
                try text(a, &item, "name", field.name);
                try text(a, &item, "type", typed.typeName(field.ty, p.records));
                try fields.append(.{ .object = item });
            }
            try out.put(a, "fields", .{ .array = fields });
        }
    }
    return .{ .object = out };
}

fn text(a: std.mem.Allocator, map: *std.json.ObjectMap, key: []const u8, value: []const u8) error{OutOfMemory}!void {
    try map.put(a, key, .{ .string = value });
}
