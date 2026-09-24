//! Render a property's typed JSON input as mylang literal syntax, so a
//! counterexample reads the way a test would write it (PROPERTY-TEST-3):
//! `[100]`, `Point(x=0, y=-1)`, `Shape.circle(3)`, `Some("é")`, `255u8`.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const types = @import("property_types.zig");
const Value = std.json.Value;
/// Rendering failures: allocation, or a value that does not fit its type.
pub const Error = error{ OutOfMemory, UnsupportedTestType, WriteFailed };

/// A renderer for values of one test's module: a type declared there is
/// named without its module, any other with its dotted module path.
pub const Renderer = struct {
    schema: types.Schema,
    module: []const u8,

    /// The literal spelling of `value`, a typed JSON value of type `name`.
    pub fn literal(self: Renderer, allocator: std.mem.Allocator, name: []const u8, value: Value) Error![]const u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();
        try self.write(&out.writer, name, value);
        return out.toOwnedSlice();
    }
    fn write(self: Renderer, w: *std.Io.Writer, name: []const u8, value: Value) Error!void {
        switch (try self.schema.shape(name)) {
            .integer => try integer(w, name, v.text(value)),
            .atom => |kind| switch (kind) {
                .boolean => try w.writeAll(if (value == .bool and value.bool) "True" else "False"),
                .float => try float(w, v.text(value)),
                .text => try text(w, v.text(value)),
                .bytes => try bytes(w, value),
            },
            .sequence => |shape| try self.sequence(w, shape, value),
            .keyed => |pair| if (pair.table) try self.table(w, pair, value) else try self.dict(w, pair, value),
            .record => |fields| try self.record(w, name, fields, value),
            .cases => |cases| if (cases.payloads) try self.variant(w, name, cases.cases, value) else try w.print("{s}.{s}", .{ self.local(name), v.text(value) }),
            .refused => return error.UnsupportedTestType,
        }
    }
    /// A list or an array in brackets; a set in braces, or `set()` when empty.
    fn sequence(self: Renderer, w: *std.Io.Writer, shape: types.Sequence, value: Value) Error!void {
        const items = v.array(value);
        if (shape.distinct and items.len == 0) return w.writeAll("set()");
        try w.writeByte(if (shape.distinct) '{' else '[');
        for (items, 0..) |item, index| {
            if (index != 0) try w.writeAll(", ");
            try self.write(w, shape.element, item);
        }
        try w.writeByte(if (shape.distinct) '}' else ']');
    }
    fn dict(self: Renderer, w: *std.Io.Writer, pair: types.Keyed, value: Value) Error!void {
        try w.writeByte('{');
        for (v.array(value), 0..) |entry, index| {
            if (index != 0) try w.writeAll(", ");
            try self.write(w, pair.key, entry.array.items[0]);
            try w.writeAll(": ");
            try self.write(w, pair.value, entry.array.items[1]);
        }
        try w.writeByte('}');
    }
    fn table(self: Renderer, w: *std.Io.Writer, pair: types.Keyed, value: Value) Error!void {
        if (value != .object) return error.UnsupportedTestType;
        try w.writeByte('{');
        for (value.object.keys(), value.object.values(), 0..) |key, item, index| {
            if (index != 0) try w.writeAll(", ");
            try w.print("{s}.{s}: ", .{ self.local(pair.key), key });
            try self.write(w, pair.value, item);
        }
        try w.writeByte('}');
    }
    /// A record by its constructor with named fields; a tuple in parentheses.
    fn record(self: Renderer, w: *std.Io.Writer, name: []const u8, fields: []const types.Field, value: Value) Error!void {
        const tuple = std.mem.startsWith(u8, name, "tuple<");
        if (!tuple) try w.writeAll(self.local(name));
        try w.writeByte('(');
        for (fields, 0..) |field, index| {
            if (index != 0) try w.writeAll(", ");
            if (!tuple) try w.print("{s}=", .{field.name});
            try self.write(w, field.type, v.get(value, field.name));
        }
        try w.writeByte(')');
    }
    /// `None`/`Some(x)` and `Ok(x)`/`Err(e)` by their prelude spellings;
    /// any other union as `Union.case(payload)` or `Union.case`.
    fn variant(self: Renderer, w: *std.Io.Writer, name: []const u8, cases: []const Value, value: Value) Error!void {
        const case = v.text(v.get(value, "case"));
        const payload = payloadOf(cases, case) orelse return error.UnsupportedTestType;
        const prelude = std.mem.startsWith(u8, name, "Option<") or std.mem.startsWith(u8, name, "Result<");
        if (prelude) {
            try w.writeAll(preludeCase(case));
        } else try w.print("{s}.{s}", .{ self.local(name), case });
        if (payload.len == 0) return;
        try w.writeByte('(');
        try self.write(w, payload, v.get(value, "value"));
        try w.writeByte(')');
    }
    /// A type named from the test's module: `main::Point` in module `main`
    /// is `Point`, and `geo.shapes::Point` elsewhere is `geo.shapes.Point`.
    fn local(self: Renderer, name: []const u8) []const u8 {
        const split = std.mem.lastIndexOf(u8, name, "::") orelse return name;
        if (std.mem.eql(u8, name[0..split], self.module)) return name[split + 2 ..];
        return name;
    }
};

/// The payload type of one named case, "" for a payload-free case, or null
/// when the union has no such case.
fn payloadOf(cases: []const Value, case: []const u8) ?[]const u8 {
    for (cases) |item| if (std.mem.eql(u8, v.text(v.get(item, "name")), case)) {
        const payload = v.get(item, "payload");
        return if (payload == .string) payload.string else "";
    };
    return null;
}
fn preludeCase(case: []const u8) []const u8 {
    if (std.mem.eql(u8, case, "none")) return "None";
    if (std.mem.eql(u8, case, "some")) return "Some";
    if (std.mem.eql(u8, case, "ok")) return "Ok";
    return "Err";
}
/// An `int` as a bare decimal; every other width with its suffix (`255u8`).
fn integer(w: *std.Io.Writer, name: []const u8, digits: []const u8) Error!void {
    try w.writeAll(digits);
    if (!std.mem.eql(u8, name, "i64")) try w.writeAll(name);
}
/// A finite float as its decimal; the non-finite ones as the expressions
/// that make them, since mylang spells no infinity or NaN literal.
fn float(w: *std.Io.Writer, spelled: []const u8) Error!void {
    if (std.mem.eql(u8, spelled, "nan")) return w.writeAll("0.0 / 0.0");
    if (std.mem.eql(u8, spelled, "inf")) return w.writeAll("1.0 / 0.0");
    if (std.mem.eql(u8, spelled, "-inf")) return w.writeAll("-1.0 / 0.0");
    try w.writeAll(spelled);
}
/// A double-quoted string: printable text as itself, the usual escapes,
/// and `\xNN`/`\uNNNN` for every other control scalar.
fn text(w: *std.Io.Writer, value: []const u8) Error!void {
    try w.writeByte('"');
    var view = std.unicode.Utf8View.init(value) catch return error.UnsupportedTestType;
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |scalar| switch (scalar) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        '\n' => try w.writeAll("\\n"),
        '\t' => try w.writeAll("\\t"),
        '\r' => try w.writeAll("\\r"),
        0...8, 0x0b, 0x0c, 0x0e...0x1f, 0x7f => try w.print("\\x{x:0>2}", .{scalar}),
        0x80...0x9f, 0x2028, 0x2029, 0xfeff => try w.print("\\u{x:0>4}", .{scalar}),
        else => try w.print("{u}", .{scalar}),
    };
    try w.writeByte('"');
}
/// A bytes literal: printable ASCII as itself, every other byte escaped.
fn bytes(w: *std.Io.Writer, value: Value) Error!void {
    try w.writeAll("b\"");
    for (v.array(value)) |item| {
        const byte = std.fmt.parseInt(u8, v.text(item), 10) catch return error.UnsupportedTestType;
        switch (byte) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\t' => try w.writeAll("\\t"),
            ' '...'!', '#'...'[', ']'...'~' => try w.writeByte(byte),
            else => try w.print("\\x{x:0>2}", .{byte}),
        }
    }
    try w.writeByte('"');
}

fn spell(arena: std.mem.Allocator, name: []const u8, json: []const u8) ![]const u8 {
    const parsed = try std.json.parseFromSliceLeaky(Value, arena, @import("property_generate.zig").test_schema, .{});
    const renderer: Renderer = .{ .schema = try types.Schema.init(arena, v.array(v.get(parsed, "types"))), .module = "main" };
    return renderer.literal(arena, name, try std.json.parseFromSliceLeaky(Value, arena, json, .{}));
}

// spec-case: PROPERTY-TEST-3
test "property counterexamples render as mylang literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("[100]", try spell(a, "List<i64>", "[\"100\"]"));
    try std.testing.expectEqualStrings("-3i32", try spell(a, "i32", "\"-3\""));
    try std.testing.expectEqualStrings("Point(x=1, y=2u8)", try spell(a, "main::Point", "{\"x\":\"1\",\"y\":\"2\"}"));
    try std.testing.expectEqualStrings("Shape.square(Point(x=0, y=0u8))", try spell(a, "main::Shape", "{\"case\":\"square\",\"value\":{\"x\":\"0\",\"y\":\"0\"}}"));
    try std.testing.expectEqualStrings("Shape.empty", try spell(a, "main::Shape", "{\"case\":\"empty\"}"));
    try std.testing.expectEqualStrings("Color.green", try spell(a, "main::Color", "\"green\""));
    try std.testing.expectEqualStrings("None", try spell(a, "Option<i64>", "{\"case\":\"none\"}"));
    try std.testing.expectEqualStrings("Some(3)", try spell(a, "Option<i64>", "{\"case\":\"some\",\"value\":\"3\"}"));
    try std.testing.expectEqualStrings("Err(\"no\")", try spell(a, "Result<bool,str>", "{\"case\":\"err\",\"value\":\"no\"}"));
    try std.testing.expectEqualStrings("\"\u{e9}\\n\\\"\\x00\\u2028\"", try spell(a, "str", "\"\\u00e9\\n\\\"\\u0000\\u2028\""));
    try std.testing.expectEqualStrings("b\"a\\x00\\xff\"", try spell(a, "bytes", "[\"97\",\"0\",\"255\"]"));
    try std.testing.expectEqualStrings("{1, 2}", try spell(a, "set<i64>", "[\"1\",\"2\"]"));
    try std.testing.expectEqualStrings("set()", try spell(a, "set<i64>", "[]"));
    try std.testing.expectEqualStrings("{\"a\": 1}", try spell(a, "dict<str,i64>", "[[\"a\",\"1\"]]"));
    try std.testing.expectEqualStrings("(1, \"a\")", try spell(a, "tuple<i64,str>", "{\"$0\":\"1\",\"$1\":\"a\"}"));
    try std.testing.expectEqualStrings("[1u8, 2u8, 3u8]", try spell(a, "[3]u8", "[\"1\",\"2\",\"3\"]"));
    try std.testing.expectEqualStrings("{Color.red: 1, Color.green: 2, Color.blue: 3}", try spell(a, "[main::Color]i64", "{\"red\":\"1\",\"green\":\"2\",\"blue\":\"3\"}"));
    try std.testing.expectEqualStrings("0.0 / 0.0", try spell(a, "float", "\"nan\""));
    try std.testing.expectEqualStrings("-1.0 / 0.0", try spell(a, "float", "\"-inf\""));
    try std.testing.expectEqualStrings("True", try spell(a, "bool", "true"));
}
