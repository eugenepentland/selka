//! Core-owned port of the property_types.zig algorithms; no old backend is reached.
//! What a property test's generator sees of a checked type: one `Shape` per
//! `language-schema-v1` definition, and the configuration error for a
//! parameter whose type no generator may build (PROPERTY-TEST-1).
const std = @import("std");
const v = @import("property_value.zig");
const Value = std.json.Value;

/// How the generator, the shrinker and the renderer treat one checked type.
/// `refused` carries the reason no value of the type may be generated.
pub const Shape = union(enum) {
    integer: Integer,
    atom: Atom,
    sequence: Sequence,
    keyed: Keyed,
    record: []const Field,
    cases: Cases,
    refused: []const u8,
};
/// A scalar-like type with no parameters: a Boolean, a float, text or bytes
/// (`bytes`, or a `byte_buffer`, which generates, shrinks and renders as bytes).
pub const Atom = enum { boolean, float, text, bytes };
/// An integer type's width and signedness; `minimum`/`maximum` bound every value.
pub const Integer = struct { bits: u7, signed: bool, minimum: i128, maximum: i128 };
/// A run of elements: a list, a fixed array (`length`), or a set (`distinct`).
pub const Sequence = struct { element: []const u8, length: ?usize = null, distinct: bool = false };
/// A keyed type's key and value types: a dictionary, or an enum-indexed
/// `table` whose keys are every case of its enum.
pub const Keyed = struct { key: []const u8, value: []const u8, table: bool = false };
/// A closed set of named cases: an enum, or a union (`payloads`) whose cases
/// may carry a value.
pub const Cases = struct { cases: []const Value, payloads: bool };
/// One record (or tuple) field and its type.
pub const Field = struct { name: []const u8, type: []const u8 };

/// Checked definitions by name, built once per property test in the run's
/// arena, which owns every value built from it.
pub const Schema = struct {
    arena: std.mem.Allocator,
    definitions: std.StringHashMapUnmanaged(Value) = .empty,

    /// Index the schema's `types` array by name.
    pub fn init(arena: std.mem.Allocator, types: []const Value) error{OutOfMemory}!Schema {
        var schema: Schema = .{ .arena = arena };
        for (types) |item| try schema.definitions.put(arena, v.text(v.get(item, "name")), item);
        return schema;
    }
    /// The definition of one type name, or null when the schema has none.
    pub fn definition(self: Schema, name: []const u8) ?Value {
        return self.definitions.get(name);
    }
    /// Classify one type name. A name the schema does not define is refused.
    pub fn shape(self: Schema, name: []const u8) error{OutOfMemory}!Shape {
        const item = self.definition(name) orelse return .{ .refused = "the checked schema does not describe it" };
        if (atom(name)) |known| return .{ .atom = known };
        const kind = v.text(v.get(item, "kind"));
        if (std.mem.eql(u8, kind, "integer")) return integer(item);
        if (std.mem.eql(u8, kind, "boolean")) return .{ .atom = .boolean };
        if (std.mem.eql(u8, kind, "list")) return listShape(name, item);
        if (std.mem.eql(u8, kind, "array")) return .{ .sequence = .{ .element = v.text(v.get(item, "element")), .length = @intCast(v.number(v.get(item, "length"))) } };
        if (std.mem.eql(u8, kind, "table")) return .{ .keyed = .{ .key = v.text(v.get(item, "key")), .value = v.text(v.get(item, "element")), .table = true } };
        if (std.mem.eql(u8, kind, "record")) return self.recordShape(item);
        if (std.mem.eql(u8, kind, "enumeration")) return .{ .cases = .{ .cases = v.array(v.get(item, "cases")), .payloads = false } };
        const union_kind = std.mem.eql(u8, kind, "tagged_union") or std.mem.eql(u8, kind, "result");
        if (union_kind) return .{ .cases = .{ .cases = v.array(v.get(item, "cases")), .payloads = true } };
        return .{ .refused = refusal(kind) };
    }
    fn recordShape(self: Schema, item: Value) error{OutOfMemory}!Shape {
        const marked = v.get(item, "class");
        if (marked == .bool and marked.bool) return .{ .refused = "a class value has identity, so it is built by its own code rather than generated" };
        const fields = v.array(v.get(item, "fields"));
        const result = try self.arena.alloc(Field, fields.len);
        for (result, fields) |*out, field| out.* = .{ .name = v.text(v.get(field, "name")), .type = v.text(v.get(field, "type")) };
        return .{ .record = result };
    }
};

fn integer(item: Value) Shape {
    const bits: u7 = @intCast(v.number(v.get(item, "bits")));
    const signed = v.boolean(v.get(item, "signed"));
    const bound = @as(i128, 1) << @intCast(bits - @intFromBool(signed));
    return .{ .integer = .{ .bits = bits, .signed = signed, .minimum = if (signed) -bound else 0, .maximum = bound - 1 } };
}

/// The builtin types the generator knows by name.
fn atom(name: []const u8) ?Atom {
    if (std.mem.eql(u8, name, "str")) return .text;
    if (std.mem.eql(u8, name, "bytes") or std.mem.eql(u8, name, "byte_buffer")) return .bytes;
    if (std.mem.eql(u8, name, "float")) return .float;
    return null;
}

/// A `list` definition is a list; one that names its key type is a set
/// (`set<T>`) or a dictionary.
fn listShape(name: []const u8, item: Value) Shape {
    const key = v.get(item, "key");
    const set = std.mem.startsWith(u8, name, "set<");
    if (key == .string) {
        if (set) return .{ .sequence = .{ .element = key.string, .distinct = true } };
        return .{ .keyed = .{ .key = key.string, .value = v.text(v.get(item, "element")) } };
    }
    if (set or std.mem.startsWith(u8, name, "dict<")) return .{ .refused = "the checked schema does not name its key type" };
    return .{ .sequence = .{ .element = v.text(v.get(item, "element")) } };
}

/// Why a definition of this kind is never generated.
fn refusal(kind: []const u8) []const u8 {
    if (std.mem.eql(u8, kind, "domain")) return "a domain is built only through its own constructors";
    if (std.mem.eql(u8, kind, "callback")) return "a function value cannot be generated";
    if (std.mem.eql(u8, kind, "capability")) return "a Host capability is never handed to a test";
    return "values of this kind cannot cross the test boundary";
}

/// The first type reachable from `name` that no generator may build, with
/// the reason, or null when every reachable type is generatable.
pub const Refusal = struct { type: []const u8, reason: []const u8 };

/// Walk every type `name` reaches and report the first refused one.
pub fn refused(schema: Schema, name: []const u8) error{OutOfMemory}!?Refusal {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(schema.arena);
    return walk(schema, name, &seen);
}
fn walk(schema: Schema, name: []const u8, seen: *std.StringHashMapUnmanaged(void)) error{OutOfMemory}!?Refusal {
    if ((try seen.getOrPut(schema.arena, name)).found_existing) return null;
    const shape = try schema.shape(name);
    switch (shape) {
        .refused => |reason| return .{ .type = name, .reason = reason },
        .sequence => |sequence| return walk(schema, sequence.element, seen),
        .keyed => |pair| {
            const key = try walk(schema, pair.key, seen);
            if (key != null) return key;
            return walk(schema, pair.value, seen);
        },
        .record => |fields| for (fields) |field| if (try walk(schema, field.type, seen)) |found| return found,
        .cases => |cases| for (cases.cases) |case| {
            const payload = v.get(case, "payload");
            if (payload == .string) if (try walk(schema, payload.string, seen)) |found| return found;
        },
        .integer, .atom => {},
    }
    return null;
}

/// Whether a value of type `from` can hold a value of type `target`, through
/// fields, payloads and elements. A recursive value type (RECURSIVE-VALUES-3)
/// is one whose case reaches its own union again.
pub fn reaches(schema: Schema, from: []const u8, target: []const u8) error{OutOfMemory}!bool {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(schema.arena);
    var pending: std.ArrayList([]const u8) = .empty;
    defer pending.deinit(schema.arena);
    try pending.append(schema.arena, from);
    while (pending.pop()) |name| {
        if (std.mem.eql(u8, name, target)) return true;
        if ((try seen.getOrPut(schema.arena, name)).found_existing) continue;
        try pending.appendSlice(schema.arena, try parts(schema, name));
    }
    return false;
}

/// The type names type `name`'s shape refers to directly: an element, a key and
/// value, record fields or case payloads.
pub fn parts(schema: Schema, name: []const u8) error{OutOfMemory}![]const []const u8 {
    var found: std.ArrayList([]const u8) = .empty;
    switch (try schema.shape(name)) {
        .sequence => |sequence| try found.append(schema.arena, sequence.element),
        .keyed => |pair| try found.appendSlice(schema.arena, &.{ pair.key, pair.value }),
        .record => |fields| for (fields) |field| try found.append(schema.arena, field.type),
        .cases => |cases| for (cases.cases) |case| {
            const payload = v.get(case, "payload");
            if (payload == .string) try found.append(schema.arena, payload.string);
        },
        .integer, .atom, .refused => {},
    }
    return found.items;
}

/// Whether case `index` of union `name` can hold another `name`.
pub fn recursiveCase(schema: Schema, name: []const u8, cases: []const Value, index: usize) error{OutOfMemory}!bool {
    const payload = v.get(cases[index], "payload");
    return payload == .string and try reaches(schema, payload.string, name);
}

/// The first case of union `name` that holds no other `name`: the leaf a
/// recursive value's generator and shrinker head for. A union with no such
/// case keeps its first case.
pub fn baseCase(schema: Schema, name: []const u8, cases: []const Value) error{OutOfMemory}!usize {
    for (0..cases.len) |index| if (!try recursiveCase(schema, name, cases, index)) return index;
    return 0;
}

/// Whether one checked result type is a property's verdict: `bool`, or a
/// `Result` whose success payload is `bool`.
pub fn verdict(schema: Schema, name: []const u8) bool {
    if (std.mem.eql(u8, name, "bool")) return true;
    const item = schema.definition(name) orelse return false;
    if (!std.mem.eql(u8, v.text(v.get(item, "kind")), "result")) return false;
    const cases = v.array(v.get(item, "cases"));
    return cases.len != 0 and std.mem.eql(u8, v.text(v.get(cases[0], "payload")), "bool");
}

const sample_types =
    \\{"types":[
    \\{"name":"i64","kind":"integer","bits":64,"signed":true},
    \\{"name":"u8","kind":"integer","bits":8,"signed":false},
    \\{"name":"bool","kind":"boolean"},
    \\{"name":"str","kind":"list","opaque":true,"element":"u32"},
    \\{"name":"u32","kind":"integer","bits":32,"signed":false},
    \\{"name":"List<i64>","kind":"list","opaque":true,"element":"i64"},
    \\{"name":"dict<str,i64>","kind":"list","opaque":true,"element":"i64"},
    \\{"name":"main::Box","kind":"record","class":true,"fields":[{"name":"value","type":"i64"}]},
    \\{"name":"main::Point","kind":"record","fields":[{"name":"x","type":"i64"},{"name":"y","type":"u8"}]},
    \\{"name":"List<main::Box>","kind":"list","opaque":true,"element":"main::Box"},
    \\{"name":"main::Meters","kind":"domain","opaque":true},
    \\{"name":"def(i64) -> i64","kind":"callback","opaque":true},
    \\{"name":"host_cap","kind":"capability","opaque":true},
    \\{"name":"Result<bool,str>","kind":"result","cases":[{"name":"ok","payload":"bool"},{"name":"err","payload":"str"}]}]}
;

// spec-case: PROPERTY-TEST-1
test "property types refuse a class, a domain, a function value and Host while data types classify" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try std.json.parseFromSlice(Value, a, sample_types, .{});
    const schema = try Schema.init(a, v.array(v.get(parsed.value, "types")));
    try std.testing.expectEqual(@as(i128, -(1 << 63)), (try schema.shape("i64")).integer.minimum);
    try std.testing.expectEqual(@as(i128, 255), (try schema.shape("u8")).integer.maximum);
    try std.testing.expectEqual(Atom.text, (try schema.shape("str")).atom);
    try std.testing.expectEqualStrings("i64", (try schema.shape("List<i64>")).sequence.element);
    try std.testing.expectEqual(@as(usize, 2), (try schema.shape("main::Point")).record.len);
    try std.testing.expectEqualStrings("main::Box", (try refused(schema, "List<main::Box>")).?.type);
    try std.testing.expect(std.mem.indexOf(u8, (try refused(schema, "main::Box")).?.reason, "class") != null);
    try std.testing.expect(std.mem.indexOf(u8, (try refused(schema, "main::Meters")).?.reason, "domain") != null);
    try std.testing.expect(std.mem.indexOf(u8, (try refused(schema, "def(i64) -> i64")).?.reason, "function value") != null);
    try std.testing.expect(std.mem.indexOf(u8, (try refused(schema, "host_cap")).?.reason, "Host") != null);
    try std.testing.expect(std.mem.indexOf(u8, (try refused(schema, "dict<str,i64>")).?.reason, "key type") != null);
    try std.testing.expectEqual(@as(?Refusal, null), try refused(schema, "main::Point"));
    try std.testing.expect(verdict(schema, "bool"));
    try std.testing.expect(verdict(schema, "Result<bool,str>"));
    try std.testing.expect(!verdict(schema, "i64"));
}
