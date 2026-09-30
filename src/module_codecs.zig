//! Canonical codec metadata shared by explicit module links and linked tests.
const std = @import("std");
const Map = std.array_hash_map.String;
const Value = std.json.Value;
const descriptors_key = "descriptors";
const callbacks_key = "callbacks";
/// Malformed or conflicting metadata cannot authorize a copied-value boundary.
pub const Error = error{ OutOfMemory, InvalidNativeManifest };

/// Union codec types, descriptors, callbacks and invariants by semantic identity,
/// rejecting conflicts and assigning method indices after the complete union.
pub fn merge(a: std.mem.Allocator, tables: []const Value) Error!Value {
    var state: Merge = .{};
    var described = false;
    for (tables) |table| if (table != .null) {
        try state.add(a, table);
        described = true;
    };
    if (!described) return .null;
    return finish(a, state.types, state.codecs, state.callbacks, state.validations);
}
const Merge = struct {
    types: Map(Value) = .empty,
    codecs: Map(Value) = .empty,
    callbacks: Map(Value) = .empty,
    validations: Map(Value) = .empty,

    fn add(self: *Merge, a: std.mem.Allocator, table: Value) Error!void {
        if (table != .object) return error.InvalidNativeManifest;
        for ([_][]const u8{ "types", descriptors_key, "codecs", callbacks_key }) |name| {
            if (field(table, name) != .array) return error.InvalidNativeManifest;
        }
        const types = items(field(table, "types"));
        const descriptors = items(field(table, descriptors_key));
        if (types.len != descriptors.len) return error.InvalidNativeManifest;
        for (types, descriptors) |item, descriptor| {
            if (descriptor != .string or descriptor.string.len == 0) return error.InvalidNativeManifest;
            var pair = std.json.Array.init(a);
            try pair.appendSlice(&.{ item, descriptor });
            _ = try insert(a, &self.types, stringOf(field(item, "name")), .{ .array = pair });
        }
        const own = items(field(table, callbacks_key));
        for (items(field(table, "codecs"))) |codec| {
            if (codec != .object) return error.InvalidNativeManifest;
            var named = codec;
            named.object = try codec.object.clone(a);
            for ([_][]const u8{ "decode", "encode" }) |key| {
                const number = field(codec, key);
                if (number != .integer or number.integer < 0 or number.integer >= own.len) return error.InvalidNativeManifest;
                const at: usize = @intCast(number.integer);
                try named.object.put(a, key, field(own[at], "symbol"));
            }
            _ = try insert(a, &self.codecs, stringOf(field(codec, "domain")), named);
        }
        for (own) |callback| _ = try insert(a, &self.callbacks, stringOf(field(callback, "symbol")), try unnumbered(a, callback));
        for (items(field(table, "validations"))) |validation| _ = try insert(a, &self.validations, stringOf(field(validation, "symbol")), try unnumbered(a, validation));
    }
};

/// Insert one semantic identity, returning whether it was new; reject a second
/// definition with different data instead of retaining the first silently.
pub fn insert(a: std.mem.Allocator, map: *Map(Value), name: []const u8, value: Value) Error!bool {
    if (name.len == 0) return error.InvalidNativeManifest;
    const slot = try map.getOrPut(a, name);
    if (!slot.found_existing) {
        slot.value_ptr.* = value;
        return true;
    }
    const previous = try std.json.Stringify.valueAlloc(a, slot.value_ptr.*, .{});
    const next = try std.json.Stringify.valueAlloc(a, value, .{});
    if (!std.mem.eql(u8, previous, next)) return error.InvalidNativeManifest;
    return false;
}
fn unnumbered(a: std.mem.Allocator, value: Value) Error!Value {
    if (value != .object) return error.InvalidNativeManifest;
    var out = value;
    out.object = try value.object.clone(a);
    _ = out.object.orderedRemove("index");
    return out;
}
fn sortedValues(a: std.mem.Allocator, map: Map(Value)) Error![]const Value {
    const keys = try a.dupe([]const u8, map.keys());
    std.mem.sort([]const u8, keys, {}, before);
    const out = try a.alloc(Value, keys.len);
    for (keys, out) |key, *value| value.* = map.get(key).?;
    return out;
}
fn before(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// MODULE-TEST-2: the codec metadata of every module merged the way
/// `qbe_codecs.canonical` orders one program's: types by name with their
/// descriptors, codecs by domain, callbacks by symbol, and every method
/// numbered by its callback's position.
fn finish(allocator: std.mem.Allocator, types: Map(std.json.Value), codecs: Map(std.json.Value), callbacks: Map(std.json.Value), validations: Map(std.json.Value)) Error!std.json.Value {
    const sorted_types = try sortedValues(allocator, types);
    var type_items = std.json.Array.init(allocator);
    var descriptor_items = std.json.Array.init(allocator);
    for (sorted_types) |pair| {
        try type_items.append(pair.array.items[0]);
        try descriptor_items.append(pair.array.items[1]);
    }
    const sorted_callbacks = try sortedValues(allocator, callbacks);
    var callback_items = std.json.Array.init(allocator);
    var positions: Map(usize) = .empty;
    for (sorted_callbacks, 0..) |callback, index| {
        var numbered = callback;
        numbered.object = try callback.object.clone(allocator);
        try numbered.object.put(allocator, "index", .{ .integer = @intCast(index) });
        try callback_items.append(numbered);
        try positions.put(allocator, stringOf(field(callback, "symbol")), index);
    }
    var codec_items = std.json.Array.init(allocator);
    for (try sortedValues(allocator, codecs)) |codec| {
        var numbered = codec;
        numbered.object = try codec.object.clone(allocator);
        for ([_][]const u8{ "decode", "encode" }) |key| {
            const at = positions.get(stringOf(field(codec, key))) orelse return error.InvalidNativeManifest;
            try numbered.object.put(allocator, key, .{ .integer = @intCast(at) });
        }
        try codec_items.append(numbered);
    }
    var table: std.json.ObjectMap = .empty;
    try table.put(allocator, "types", .{ .array = type_items });
    try table.put(allocator, descriptors_key, .{ .array = descriptor_items });
    try table.put(allocator, "codecs", .{ .array = codec_items });
    try table.put(allocator, callbacks_key, .{ .array = callback_items });
    var validation_items = std.json.Array.init(allocator);
    for (try sortedValues(allocator, validations), 0..) |validation, index| {
        var numbered = validation;
        numbered.object = try validation.object.clone(allocator);
        try numbered.object.put(allocator, "index", .{ .integer = @intCast(index) });
        try validation_items.append(numbered);
    }
    try table.put(allocator, "validations", .{ .array = validation_items });
    return .{ .object = table };
}

fn fixture(a: std.mem.Allocator, text: []const u8) !Value {
    return std.json.parseFromSliceLeaky(Value, a, text, .{});
}
// spec-case: MODULE-TEST-2
// spec-case: MODULE-COMPILE-3
test "module codec unions renumber semantic callbacks and preserve invariant validations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first = try fixture(a,
        \\{"types":[],"descriptors":[],"codecs":[{"domain":"Zone","decode":0,"encode":1}],"callbacks":[{"index":0,"symbol":"b","input":"str","output":"Zone"},{"index":1,"symbol":"a","input":"Zone","output":"str"}],"validations":[{"index":7,"symbol":"v","input":"Zone","output":"bool"}]}
    );
    const second = try fixture(a,
        \\{"types":[],"descriptors":[],"codecs":[{"domain":"Zone","decode":1,"encode":0}],"callbacks":[{"index":0,"symbol":"a","input":"Zone","output":"str"},{"index":1,"symbol":"b","input":"str","output":"Zone"}],"validations":[{"index":2,"symbol":"v","input":"Zone","output":"bool"}]}
    );
    const result = try merge(a, &.{ first, second });
    try std.testing.expectEqual(@as(usize, 2), items(field(result, "callbacks")).len);
    try std.testing.expectEqualStrings("a", stringOf(field(items(field(result, "callbacks"))[0], "symbol")));
    try std.testing.expectEqual(@as(i64, 1), field(items(field(result, "codecs"))[0], "decode").integer);
    try std.testing.expectEqual(@as(i64, 0), field(items(field(result, "codecs"))[0], "encode").integer);
    try std.testing.expectEqual(@as(usize, 1), items(field(result, "validations")).len);
    try std.testing.expectEqual(@as(i64, 0), field(items(field(result, "validations"))[0], "index").integer);
    try std.testing.expectEqualStrings("Zone", stringOf(field(items(field(result, "validations"))[0], "input")));
    try std.testing.expect((try merge(a, &.{.null})) == .null);
}
// spec-case: MODULE-COMPILE-3
test "InvalidNativeManifest rejects incompatible codec identities and out of range local methods" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first = try fixture(a, "{\"types\":[],\"descriptors\":[],\"codecs\":[],\"callbacks\":[{\"index\":0,\"symbol\":\"a\",\"input\":\"int\",\"output\":\"bool\"}]}");
    const changed = try fixture(a, "{\"types\":[],\"descriptors\":[],\"codecs\":[],\"callbacks\":[{\"index\":4,\"symbol\":\"a\",\"input\":\"str\",\"output\":\"bool\"}]}");
    try std.testing.expectError(error.InvalidNativeManifest, merge(a, &.{ first, changed }));
    const invalid = try fixture(a, "{\"types\":[],\"descriptors\":[],\"codecs\":[{\"domain\":\"d\",\"decode\":-1,\"encode\":0}],\"callbacks\":[]}");
    try std.testing.expectError(error.InvalidNativeManifest, merge(a, &.{invalid}));
    const missing = try fixture(a, "{\"types\":[{\"name\":\"int\"}],\"descriptors\":[]}");
    try std.testing.expectError(error.InvalidNativeManifest, merge(a, &.{missing}));
}

fn field(value: Value, name: []const u8) Value {
    if (value != .object) return .null;
    return value.object.get(name) orelse .null;
}
fn items(value: Value) []const Value {
    return if (value == .array) value.array.items else &.{};
}
fn stringOf(value: Value) []const u8 {
    return if (value == .string) value.string else "";
}
// spec-case: MODULE-COMPILE-3
test "codec insertion rejects InvalidNativeManifest conflicts rather than accepting first metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var map: Map(Value) = .empty;
    try std.testing.expect(try insert(a, &map, "shape", .{ .string = "first" }));
    try std.testing.expect(!try insert(a, &map, "shape", .{ .string = "first" }));
    try std.testing.expectError(error.InvalidNativeManifest, insert(a, &map, "shape", .{ .string = "second" }));
    try std.testing.expectError(error.InvalidNativeManifest, insert(a, &map, "", .null));
}
