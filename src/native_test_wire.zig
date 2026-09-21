//! Typed JSON and copied native value trees share the public language schema.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const Value = std.json.Value;
const enumeration_kind = "enumeration";
/// Failures in typed fixture validation or native result reconstruction.
pub const Error = error{ OutOfMemory, InvalidTestArguments, InvalidTestValue, UnsupportedTestType, TestValueLimit, InvalidNativeTestResponse };
/// One preorder copied value node; no guest pointer enters the parent process.
pub const Node = struct { type: []const u8, bits: u64 = 0, children: usize = 0 };
/// Bounded schema-guided conversion state allocated in the test command arena.
pub const Codec = struct {
    allocator: std.mem.Allocator,
    types: []const Value,
    nodes: std.ArrayList(Node) = .empty,
    cursor: usize = 0,
    /// Release the copied node vector; converted JSON uses the caller's arena.
    pub fn deinit(self: *Codec) void {
        self.nodes.deinit(self.allocator);
        self.nodes = .empty;
    }
    /// Flatten named typed arguments in declaration order, rejecting extras.
    /// A `Stream` parameter is injected by the adapter, so it takes no JSON value.
    pub fn arguments(self: *Codec, function: Value, values: Value) Error!void {
        const parameters = v.array(v.get(function, "parameters"));
        if (v.get(function, "return_reference") != .null) return error.UnsupportedTestType;
        var expected: usize = 0;
        for (parameters) |parameter| if (!streamParameter(parameter)) {
            expected += 1;
        };
        if (values == .null and expected == 0) return;
        if (values != .object or values.object.count() != expected) return error.InvalidTestArguments;
        for (parameters) |parameter| {
            if (streamParameter(parameter)) continue;
            if (!std.mem.eql(u8, v.text(v.get(parameter, "mode")), "value")) return error.UnsupportedTestType;
            const value = values.object.get(v.text(v.get(parameter, "name"))) orelse return error.InvalidTestArguments;
            try self.encode(v.text(v.get(parameter, "type")), value, 0);
        }
    }
    /// The scalar type of a text value, or null when the declared type is not
    /// one. `str` is declared as an opaque list of 32-bit scalars, and that is
    /// the whole of its wire contract: an opaque byte list is deliberately not
    /// text, because `bytes` is staged behind its own encoding.
    fn listElement(self: Codec, item: Value) ?[]const u8 {
        if (!std.mem.eql(u8, v.text(v.get(item, "kind")), "list")) return null;
        if (!v.boolean(v.get(item, "opaque"))) return null;
        // `bytes` has this shape and its encoding is staged separately, so the
        // boundary refuses it here as well as in the wire table; three readers of
        // three different documents have to agree, and this is one of them.
        if (std.mem.eql(u8, v.text(v.get(item, "name")), "bytes")) return null;
        const element = v.text(v.get(item, "element"));
        const scalar = self.definition(element) catch return null;
        const kind = v.text(v.get(scalar, "kind"));
        if (!std.mem.eql(u8, kind, "integer") and !std.mem.eql(u8, kind, "boolean")) return null;
        return element;
    }

    /// Whether one copied managed list reads as a string rather than an array.
    /// `str` is the language's text type and the only list whose scalars spell
    /// characters; every other list, `list[u32]` included, is an array.
    fn stringList(self: Codec, item: Value) bool {
        _ = self;
        return std.mem.eql(u8, v.text(v.get(item, "name")), "str");
    }

    /// Encode one text value as a node with one integer child per Unicode
    /// scalar. The fixed-size node format then carries the whole value with no
    /// byte payload, and the guest rebuilds a managed text of exactly that many
    /// scalars. A byte string that is not UTF-8 is refused here rather than
    /// reaching the guest, which is where the scalar count comes from.
    fn encodeList(self: *Codec, item: Value, element: []const u8, value: Value, index: usize, depth: usize) Error!void {
        if (!self.stringList(item)) {
            if (value != .array) return error.InvalidTestValue;
            if (self.nodes.items.len + value.array.items.len >= 65536) return error.TestValueLimit;
            self.nodes.items[index].children = value.array.items.len;
            for (value.array.items) |child| try self.encode(element, child, depth + 1);
            return;
        }
        if (value != .string) return error.InvalidTestValue;
        try self.encodeText(element, value.string, index);
    }

    fn encodeText(self: *Codec, element: []const u8, bytes: []const u8, index: usize) Error!void {
        var view = std.unicode.Utf8View.init(bytes) catch return error.InvalidTestValue;
        var iterator = view.iterator();
        var count: usize = 0;
        while (iterator.nextCodepoint()) |scalar| {
            if (self.nodes.items.len >= 65536) return error.TestValueLimit;
            try self.nodes.append(self.allocator, .{ .type = element, .bits = scalar });
            count += 1;
        }
        self.nodes.items[index].children = count;
    }

    /// Rebuild the JSON string one text value came from. A child that is not a
    /// Unicode scalar cannot have been produced by a text, so it is a malformed
    /// response rather than a value to repair.
    fn decodeList(self: *Codec, item: Value, element: []const u8, count: usize, depth: usize) Error!Value {
        if (count > 65536) return error.InvalidNativeTestResponse;
        if (!self.stringList(item)) {
            var array: std.json.Array = .init(self.allocator);
            for (0..count) |_| try array.append(try self.decode(element, depth + 1));
            return .{ .array = array };
        }
        return self.decodeText(element, count, depth);
    }

    fn decodeText(self: *Codec, element: []const u8, count: usize, depth: usize) Error!Value {
        var text: std.ArrayList(u8) = .empty;
        errdefer text.deinit(self.allocator);
        for (0..count) |_| {
            const child = try self.decode(element, depth + 1);
            const scalar = std.fmt.parseInt(u32, child.string, 10) catch return error.InvalidNativeTestResponse;
            if (scalar > 0x10FFFF) return error.InvalidNativeTestResponse;
            var buffer: [4]u8 = undefined;
            const length = std.unicode.utf8Encode(@intCast(scalar), &buffer) catch return error.InvalidNativeTestResponse;
            try text.appendSlice(self.allocator, buffer[0..@as(usize, length)]);
        }
        return .{ .string = text.items };
    }

    fn definition(self: Codec, name: []const u8) Error!Value {
        for (self.types) |item| if (std.mem.eql(u8, v.text(v.get(item, "name")), name)) return item;
        return error.UnsupportedTestType;
    }
    /// Validate and flatten one typed JSON value without running domain methods.
    pub fn encode(self: *Codec, name: []const u8, value: Value, depth: usize) Error!void {
        if (depth > 64 or self.nodes.items.len >= 65536) return error.TestValueLimit;
        const item = try self.definition(name);
        const kind = v.text(v.get(item, "kind"));
        const index = self.nodes.items.len;
        try self.nodes.append(self.allocator, .{ .type = name });
        if (std.mem.eql(u8, kind, "integer")) {
            if (value != .string) return error.InvalidTestValue;
            self.nodes.items[index].bits = try decimal(name, value.string);
        } else if (std.mem.eql(u8, kind, "boolean")) {
            if (value != .bool) return error.InvalidTestValue;
            self.nodes.items[index].bits = @intFromBool(value.bool);
        } else if (self.listElement(item)) |element| {
            try self.encodeList(item, element, value, index, depth);
        } else if (std.mem.eql(u8, kind, "domain")) {
            const wire = v.get(v.get(item, "codec"), "wire");
            if (wire != .string) return error.UnsupportedTestType;
            self.nodes.items[index].children = 1;
            try self.encode(v.text(wire), value, depth + 1);
        } else if (variant(kind)) {
            try self.encodeVariant(item, value, index, depth);
        } else try self.encodeFields(item, value, index, depth);
    }
    fn encodeVariant(self: *Codec, item: Value, value: Value, index: usize, depth: usize) Error!void {
        const enumeration = std.mem.eql(u8, v.text(v.get(item, "kind")), enumeration_kind);
        const selected = if (enumeration) value else v.get(value, "case");
        if (selected != .string) return error.InvalidTestValue;
        for (v.array(v.get(item, "cases")), 0..) |case, tag| {
            if (!std.mem.eql(u8, v.text(v.get(case, "name")), selected.string)) continue;
            const payload = v.get(case, "payload");
            const count: usize = @intFromBool(payload != .null);
            if (!enumeration and (value != .object or value.object.count() != 1 + count)) return error.InvalidTestValue;
            self.nodes.items[index].bits = tag;
            self.nodes.items[index].children = count;
            if (count != 0) {
                const child = value.object.get("value") orelse return error.InvalidTestValue;
                try self.encode(v.text(payload), child, depth + 1);
            }
            return;
        }
        return error.InvalidTestValue;
    }
    fn encodeFields(self: *Codec, item: Value, value: Value, index: usize, depth: usize) Error!void {
        const kind = v.text(v.get(item, "kind"));
        if (std.mem.eql(u8, kind, "array")) {
            const count = v.number(v.get(item, "length"));
            if (value != .array or value.array.items.len != count) return error.InvalidTestValue;
            self.nodes.items[index].children = @intCast(count);
            for (value.array.items) |child| try self.encode(v.text(v.get(item, "element")), child, depth + 1);
            return;
        }
        const entries = try self.fields(item);
        if (value != .object or value.object.count() != entries.len) return error.InvalidTestValue;
        self.nodes.items[index].children = entries.len;
        for (entries) |field| {
            const child = value.object.get(field.name) orelse return error.InvalidTestValue;
            try self.encode(field.type, child, depth + 1);
        }
    }
    fn fields(self: Codec, item: Value) Error![]const Field {
        const kind = v.text(v.get(item, "kind"));
        const table = std.mem.eql(u8, kind, "table");
        if (!table and !std.mem.eql(u8, kind, "record")) return error.UnsupportedTestType;
        const entries = if (table) v.array(v.get(try self.definition(v.text(v.get(item, "key"))), "cases")) else v.array(v.get(item, "fields"));
        const result = try self.allocator.alloc(Field, entries.len);
        for (result, entries) |*out, entry| out.* = .{ .name = v.text(v.get(entry, "name")), .type = v.text(if (table) v.get(item, "element") else v.get(entry, "type")) };
        return result;
    }
    /// Convert one returned tree to the canonical typed JSON assertion value.
    pub fn decode(self: *Codec, name: []const u8, depth: usize) Error!Value {
        if (depth > 64 or self.cursor >= self.nodes.items.len) return error.InvalidNativeTestResponse;
        const node = self.nodes.items[self.cursor];
        self.cursor += 1;
        if (!std.mem.eql(u8, node.type, name)) return error.InvalidNativeTestResponse;
        const item = try self.definition(name);
        const kind = v.text(v.get(item, "kind"));
        if (std.mem.eql(u8, kind, "integer")) {
            if (node.children != 0) return error.InvalidNativeTestResponse;
            const number: i128 = if (v.boolean(v.get(item, "signed"))) @as(i64, @bitCast(node.bits)) else node.bits;
            return .{ .string = try std.fmt.allocPrint(self.allocator, "{d}", .{number}) };
        }
        if (std.mem.eql(u8, kind, "boolean")) {
            if (node.children != 0 or node.bits > 1) return error.InvalidNativeTestResponse;
            return .{ .bool = node.bits == 1 };
        }
        if (self.listElement(item)) |element| {
            if (node.bits != 0) return error.InvalidNativeTestResponse;
            return self.decodeList(item, element, node.children, depth);
        }
        if (std.mem.eql(u8, kind, "domain")) {
            if (node.children != 1 or node.bits != 0) return error.InvalidNativeTestResponse;
            const wire = v.get(v.get(item, "codec"), "wire");
            if (wire != .string) return error.UnsupportedTestType;
            return self.decode(v.text(wire), depth + 1);
        }
        if (variant(kind)) return self.decodeVariant(item, node, depth);
        return self.decodeFields(item, node, depth);
    }
    fn decodeVariant(self: *Codec, item: Value, node: Node, depth: usize) Error!Value {
        const cases = v.array(v.get(item, "cases"));
        if (node.bits >= cases.len) return error.InvalidNativeTestResponse;
        const case = cases[@intCast(node.bits)];
        const payload = v.get(case, "payload");
        if (node.children != @intFromBool(payload != .null)) return error.InvalidNativeTestResponse;
        if (std.mem.eql(u8, v.text(v.get(item, "kind")), enumeration_kind)) return .{ .string = v.text(v.get(case, "name")) };
        var object: std.json.ObjectMap = .empty;
        try object.put(self.allocator, "case", v.get(case, "name"));
        if (payload != .null) try object.put(self.allocator, "value", try self.decode(v.text(payload), depth + 1));
        return .{ .object = object };
    }
    fn decodeFields(self: *Codec, item: Value, node: Node, depth: usize) Error!Value {
        if (node.bits != 0) return error.InvalidNativeTestResponse;
        if (std.mem.eql(u8, v.text(v.get(item, "kind")), "array")) {
            if (node.children != v.number(v.get(item, "length"))) return error.InvalidNativeTestResponse;
            var array: std.json.Array = .init(self.allocator);
            for (0..node.children) |_| try array.append(try self.decode(v.text(v.get(item, "element")), depth + 1));
            return .{ .array = array };
        }
        const entries = try self.fields(item);
        if (node.children != entries.len) return error.InvalidNativeTestResponse;
        var object: std.json.ObjectMap = .empty;
        for (entries) |field| try object.put(self.allocator, field.name, try self.decode(field.type, depth + 1));
        return .{ .object = object };
    }
};
/// One declared parameter is an injected `Stream` rather than a JSON argument.
fn streamParameter(parameter: Value) bool {
    return std.mem.eql(u8, v.text(v.get(parameter, "type")), "stream_cap");
}
fn decimal(name: []const u8, text: []const u8) Error!u64 {
    if (name.len < 2) return error.UnsupportedTestType;
    if (name[0] != 'i' and name[0] != 'u') return error.UnsupportedTestType;
    const width = std.fmt.parseInt(u8, name[1..], 10) catch return error.UnsupportedTestType;
    if (width != 8 and width != 16 and width != 32 and width != 64) return error.UnsupportedTestType;
    if (text.len == 0 or text.len > 20) return error.InvalidTestValue;
    const negative = text[0] == '-';
    const digits = text[@intFromBool(negative)..];
    if (digits.len == 0) return error.InvalidTestValue;
    if (digits[0] == '0' and (digits.len != 1 or negative)) return error.InvalidTestValue;
    for (digits) |digit| if (!std.ascii.isDigit(digit)) return error.InvalidTestValue;
    const value = std.fmt.parseInt(i128, text, 10) catch return error.InvalidTestValue;
    const bound = @as(i128, 1) << @as(u7, @intCast(width - @intFromBool(name[0] == 'i')));
    const minimum = if (name[0] == 'i') -bound else 0;
    if (value < minimum or value >= bound) return error.InvalidTestValue;
    return @truncate(@as(u128, @bitCast(value)));
}

const Field = struct { name: []const u8, type: []const u8 };
fn variant(kind: []const u8) bool {
    return std.mem.eql(u8, kind, enumeration_kind) or std.mem.eql(u8, kind, "tagged_union") or std.mem.eql(u8, kind, "result");
}

test "typed fixture integers and nominal trees roundtrip without guest execution" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try std.json.parseFromSlice(Value, a,
        \\{"types":[{"name":"i64","kind":"integer","signed":true},{"name":"u64","kind":"integer","signed":false},{"name":"bool","kind":"boolean"},{"name":"Pair","kind":"record","fields":[{"name":"n","type":"i64"},{"name":"ok","type":"bool"}]},{"name":"Domain","kind":"domain","codec":{"wire":"Pair"}},{"name":"R","kind":"result","cases":[{"name":"ok","payload":"Domain"},{"name":"err","payload":"i64"}]}],"value":{"case":"ok","value":{"n":"-9223372036854775808","ok":true}}}
    , .{});
    var codec: Codec = .{ .allocator = a, .types = v.array(v.get(parsed.value, "types")) };
    defer codec.deinit();
    const value = v.get(parsed.value, "value");
    try codec.encode("R", value, 0);
    const actual = try codec.decode("R", 0);
    try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, value, .{}), try std.json.Stringify.valueAlloc(a, actual, .{}));
    try std.testing.expectError(error.TestValueLimit, codec.encode("i64", .{ .string = "1" }, 65));
    try std.testing.expectError(error.InvalidTestValue, codec.encode("i64", .{ .string = "01" }, 0));
    try std.testing.expectError(error.InvalidTestValue, codec.encode("i64", .{ .integer = 1 }, 0));
    try std.testing.expectError(error.InvalidTestValue, codec.encode("u64", .{ .string = "-1" }, 0));
    try std.testing.expectError(error.UnsupportedTestType, codec.encode("capability", .null, 0));
    try std.testing.expectError(error.InvalidTestArguments, codec.arguments(.null, .{ .integer = 1 }));
}

// spec: WIRE-TEXT-1
test "a text value crosses the wire as one node per Unicode scalar" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try std.json.parseFromSlice(Value, a,
        \\{"types":[{"name":"u32","kind":"integer","signed":false,"bits":32},{"name":"str","kind":"list","opaque":true,"element":"u32"},{"name":"bytes","kind":"list","opaque":true,"element":"u8"},{"name":"u8","kind":"integer","signed":false,"bits":8},{"name":"Texts","kind":"record","fields":[{"name":"label","type":"str"}]}]}
    , .{});
    var codec: Codec = .{ .allocator = a, .types = v.array(v.get(parsed.value, "types")) };
    defer codec.deinit();
    // ASCII, a two-byte scalar, a three-byte scalar and an astral scalar: the
    // node count is the scalar count, not the byte count.
    const label = "h\u{e9}llo \u{4e16}\u{754c} \u{1F600}";
    try codec.encode("str", .{ .string = label }, 0);
    try std.testing.expectEqual(@as(usize, 11), codec.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 10), codec.nodes.items[0].children);
    const actual = try codec.decode("str", 0);
    try std.testing.expectEqualStrings(label, actual.string);
    // A record field of the same type takes the same path.
    try codec.encode("Texts", .{ .object = try textObject(a, label) }, 0);
    const record = try codec.decode("Texts", 0);
    try std.testing.expectEqualStrings(label, v.text(v.get(record, "label")));
}

fn textObject(a: std.mem.Allocator, label: []const u8) !std.json.ObjectMap {
    var object: std.json.ObjectMap = .empty;
    try object.put(a, "label", .{ .string = label });
    return object;
}

// spec: WIRE-TEXT-2
test "a text value is refused when its bytes are not Unicode or its length is unbounded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try std.json.parseFromSlice(Value, a,
        \\{"types":[{"name":"u32","kind":"integer","signed":false,"bits":32},{"name":"u8","kind":"integer","signed":false,"bits":8},{"name":"str","kind":"list","opaque":true,"element":"u32"},{"name":"bytes","kind":"list","opaque":true,"element":"u8"}]}
    , .{});
    var codec: Codec = .{ .allocator = a, .types = v.array(v.get(parsed.value, "types")) };
    defer codec.deinit();
    try std.testing.expectError(error.InvalidTestValue, codec.encode("str", .{ .integer = 1 }, 0));
    try std.testing.expectError(error.InvalidTestValue, codec.encode("str", .{ .string = "\xff\xfe" }, 0));
    // A surrogate encoded as three bytes is exactly what UTF-8 forbids.
    try std.testing.expectError(error.InvalidTestValue, codec.encode("str", .{ .string = "\xed\xa0\x80" }, 0));
    // An opaque byte list is not text: `bytes` keeps its own encoding for later.
    try std.testing.expectError(error.UnsupportedTestType, codec.encode("bytes", .{ .string = "ab" }, 0));
    const long = try a.alloc(u8, 70000);
    @memset(long, 'a');
    try std.testing.expectError(error.TestValueLimit, codec.encode("str", .{ .string = long }, 0));
}

// spec: WIRE-TEXT-3
test "a text response that is not a scalar sequence is rejected and reports allocation failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try std.json.parseFromSlice(Value, a,
        \\{"types":[{"name":"u32","kind":"integer","signed":false,"bits":32},{"name":"str","kind":"list","opaque":true,"element":"u32"}]}
    , .{});
    var codec: Codec = .{ .allocator = a, .types = v.array(v.get(parsed.value, "types")) };
    defer codec.deinit();
    try codec.encode("str", .{ .string = "ok" }, 0);
    codec.cursor = 0;
    codec.nodes.items[0].bits = 1;
    try std.testing.expectError(error.InvalidNativeTestResponse, codec.decode("str", 0));
    codec.nodes.items[0].bits = 0;
    codec.nodes.items[1].bits = 0x110000;
    codec.cursor = 0;
    try std.testing.expectError(error.InvalidNativeTestResponse, codec.decode("str", 0));
    // The nodes are built with a working allocator, then the codec is handed one
    // that fails immediately, so the only allocation left is the string the
    // rebuild needs — which is the path that must report OutOfMemory rather
    // than leave a partial value behind.
    var tight: Codec = .{ .allocator = std.testing.allocator, .types = v.array(v.get(parsed.value, "types")) };
    try tight.encode("str", .{ .string = "ok" }, 0);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    tight.allocator = failing.allocator();
    tight.cursor = 1;
    try std.testing.expectError(error.OutOfMemory, tight.decodeText("u32", 2, 0));
    tight.allocator = std.testing.allocator;
    tight.deinit();
}
