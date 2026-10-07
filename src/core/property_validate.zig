//! Typed cases-file values are checked before entering the copied-value transport.
const std = @import("std");
const types = @import("property_types.zig");
const v = @import("property_value.zig");
const Value = std.json.Value;
/// Malformed values fail their selected case; allocation failure still propagates.
pub const Error = error{ OutOfMemory, InvalidTestValue, UnsupportedTestType };

/// Match the old native transport's bounded typed values, including existing nodes.
pub fn validate(schema: types.Schema, name: []const u8, value: Value, used: usize) Error!void {
    var checker: Checker = .{ .schema = schema, .nodes = used };
    try checker.value(name, value, 0);
}

/// Match the old runner's JSON verdict without normalizing scalar spellings.
pub fn equivalent(left: Value, right: Value) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .null => true,
        .bool => left.bool == right.bool,
        .integer => left.integer == right.integer,
        .float => left.float == right.float,
        .number_string => std.mem.eql(u8, left.number_string, right.number_string),
        .string => std.mem.eql(u8, left.string, right.string),
        .array => arrays(left.array.items, right.array.items),
        .object => objects(left.object, right.object),
    };
}
fn arrays(left: []const Value, right: []const Value) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!equivalent(a, b)) return false;
    return true;
}
fn objects(left: std.json.ObjectMap, right: std.json.ObjectMap) bool {
    if (left.count() != right.count()) return false;
    var fields = left.iterator();
    while (fields.next()) |field| if (!equivalent(field.value_ptr.*, right.get(field.key_ptr.*) orelse return false)) return false;
    return true;
}

const Checker = struct {
    schema: types.Schema,
    nodes: usize,

    fn node(self: *Checker) Error!void {
        if (self.nodes >= 65536) return error.InvalidTestValue;
        self.nodes += 1;
    }
    fn value(self: *Checker, name: []const u8, input: Value, depth: usize) Error!void {
        if (depth > 64) return error.InvalidTestValue;
        try self.node();
        switch (try self.schema.shape(name)) {
            .integer => |range| try integer(range, input),
            .atom => |kind| try self.atom(kind, input, depth),
            .sequence => |sequence_type| try self.sequence(sequence_type, input, depth),
            .keyed => |pair| try self.keyed(pair, input, depth),
            .record => |fields| try self.record(fields, input, depth),
            .cases => |choices| try self.cases(choices, input, depth),
            .refused => return error.UnsupportedTestType,
        }
    }
    fn integer(range: types.Integer, input: Value) Error!void {
        if (input != .string) return error.InvalidTestValue;
        const number = std.fmt.parseInt(i128, input.string, 10) catch return error.InvalidTestValue;
        if (number < range.minimum or number > range.maximum) return error.InvalidTestValue;
    }
    fn atom(self: *Checker, kind: types.Atom, input: Value, depth: usize) Error!void {
        switch (kind) {
            .boolean => if (input != .bool) return error.InvalidTestValue,
            .float => {
                if (input != .string) return error.InvalidTestValue;
                _ = std.fmt.parseFloat(f64, input.string) catch return error.InvalidTestValue;
            },
            .text => {
                if (input != .string) return error.InvalidTestValue;
                var view = std.unicode.Utf8View.init(input.string) catch return error.InvalidTestValue;
                var points = view.iterator();
                while (points.nextCodepoint() != null) try self.node();
            },
            .bytes => try self.sequence(.{ .element = "u8" }, input, depth),
        }
    }
    fn sequence(self: *Checker, sequence_type: types.Sequence, input: Value, depth: usize) Error!void {
        if (input != .array) return error.InvalidTestValue;
        if (sequence_type.length) |length| if (input.array.items.len != length) return error.InvalidTestValue;
        for (input.array.items) |item| try self.value(sequence_type.element, item, depth + 1);
    }
    fn keyed(self: *Checker, pair: types.Keyed, input: Value, depth: usize) Error!void {
        if (pair.table) return self.table(pair, input, depth);
        if (input != .array) return error.InvalidTestValue;
        for (input.array.items) |entry| {
            if (entry != .array or entry.array.items.len != 2) return error.InvalidTestValue;
            try self.value(pair.key, entry.array.items[0], depth + 1);
            try self.value(pair.value, entry.array.items[1], depth + 1);
        }
    }
    fn table(self: *Checker, pair: types.Keyed, input: Value, depth: usize) Error!void {
        const keys = try self.schema.shape(pair.key);
        if (keys != .cases) return error.UnsupportedTestType;
        if (input != .object or input.object.count() != keys.cases.cases.len) return error.InvalidTestValue;
        for (keys.cases.cases) |key| {
            const item = input.object.get(v.text(v.get(key, "name"))) orelse return error.InvalidTestValue;
            try self.value(pair.value, item, depth + 1);
        }
    }
    fn record(self: *Checker, fields: []const types.Field, input: Value, depth: usize) Error!void {
        if (input != .object or input.object.count() != fields.len) return error.InvalidTestValue;
        for (fields) |field| {
            const item = input.object.get(field.name) orelse return error.InvalidTestValue;
            try self.value(field.type, item, depth + 1);
        }
    }
    fn cases(self: *Checker, choices: types.Cases, input: Value, depth: usize) Error!void {
        const selected = if (choices.payloads) v.get(input, "case") else input;
        if (selected != .string) return error.InvalidTestValue;
        for (choices.cases) |case| {
            if (!std.mem.eql(u8, selected.string, v.text(v.get(case, "name")))) continue;
            if (!choices.payloads) return;
            const payload = v.get(case, "payload");
            const count: usize = 1 + @as(usize, @intFromBool(payload == .string));
            if (input != .object or input.object.count() != count) return error.InvalidTestValue;
            if (payload == .string) {
                const item = input.object.get("value") orelse return error.InvalidTestValue;
                try self.value(payload.string, item, depth + 1);
            }
            return;
        }
        return error.InvalidTestValue;
    }
};

// spec-case: NEW-CORE-S4-TEST-4
test "typed case values reject wrong JSON shapes integer overflow and malformed members" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const definitions = try std.json.parseFromSliceLeaky(Value, a, @import("property_generate.zig").test_schema, .{});
    var schema = try types.Schema.init(a, v.array(v.get(definitions, "types")));
    const wide = try std.json.parseFromSliceLeaky(Value, a, "{\"name\":\"u64\",\"kind\":\"integer\",\"bits\":64,\"signed\":false}", .{});
    try schema.definitions.put(a, "u64", wide);
    const Bad = struct { name: []const u8, json: []const u8 };
    const examples = [_]Bad{
        .{ .name = "bool", .json = "\"true\"" },
        .{ .name = "i64", .json = "\"18446744073709551616\"" },
        .{ .name = "i64", .json = "0" },
        .{ .name = "u64", .json = "\"18446744073709551616\"" },
        .{ .name = "u8", .json = "\"256\"" },
        .{ .name = "u8", .json = "\"-1\"" },
        .{ .name = "float", .json = "0" },
        .{ .name = "str", .json = "7" },
        .{ .name = "bytes", .json = "null" },
        .{ .name = "bytes", .json = "[\"256\"]" },
        .{ .name = "List<i64>", .json = "null" },
        .{ .name = "[3]u8", .json = "[\"0\"]" },
        .{ .name = "dict<str,i64>", .json = "[[\"x\"]]" },
        .{ .name = "dict<str,i64>", .json = "[{}]" },
        .{ .name = "main::Point", .json = "{\"x\":\"0\",\"y\":\"0\",\"extra\":true}" },
        .{ .name = "main::Point", .json = "{\"x\":\"0\",\"missing\":\"0\"}" },
        .{ .name = "Option<i64>", .json = "{\"case\":\"some\"}" },
        .{ .name = "Option<i64>", .json = "{\"case\":\"none\",\"value\":\"0\"}" },
        .{ .name = "main::Color", .json = "{\"case\":\"red\"}" },
        .{ .name = "[main::Color]i64", .json = "{}" },
    };
    for (examples) |example| {
        const input = try std.json.parseFromSliceLeaky(Value, a, example.json, .{});
        try std.testing.expectError(error.InvalidTestValue, validate(schema, example.name, input, 0));
    }
    try validate(schema, "i64", .{ .string = "-9223372036854775808" }, 0);
    try validate(schema, "i64", .{ .string = "9223372036854775807" }, 0);
    try validate(schema, "u8", .{ .string = "255" }, 0);
    try validate(schema, "u64", .{ .string = "18446744073709551615" }, 0);
    try std.testing.expectError(error.InvalidTestValue, validate(schema, "str", .{ .string = "\xff" }, 0));
    try std.testing.expectError(error.InvalidTestValue, validate(schema, "bool", .{ .bool = true }, 65536));
}

// spec-case: NEW-CORE-S4-TEST-4
test "case verdicts preserve scalar kinds string bytes and ignore only object order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const left = try std.json.parseFromSliceLeaky(Value, a, "{\"n\":\"0\",\"ok\":true}", .{});
    const reordered = try std.json.parseFromSliceLeaky(Value, a, "{\"ok\":true,\"n\":\"0\"}", .{});
    const spelling = try std.json.parseFromSliceLeaky(Value, a, "{\"n\":\"00\",\"ok\":true}", .{});
    const kind = try std.json.parseFromSliceLeaky(Value, a, "{\"n\":0,\"ok\":true}", .{});
    try std.testing.expect(equivalent(left, reordered));
    try std.testing.expect(!equivalent(left, spelling));
    try std.testing.expect(!equivalent(left, kind));
}

// spec-case: NEW-CORE-S4-TEST-4
test "validate propagates record shape allocation failure instead of grading a malformed value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const definitions = try std.json.parseFromSliceLeaky(Value, a, @import("property_generate.zig").test_schema, .{});
    var schema = try types.Schema.init(a, v.array(v.get(definitions, "types")));
    schema.arena = std.testing.failing_allocator;
    const input = try std.json.parseFromSliceLeaky(Value, a, "{\"x\":\"0\",\"y\":\"0\"}", .{});
    try std.testing.expectError(error.OutOfMemory, validate(schema, "main::Point", input, 0));
}
