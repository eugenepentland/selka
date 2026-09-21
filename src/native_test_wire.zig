//! Typed JSON and copied native value trees share the public language schema.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const build_io = @import("qbe_build_io.zig");
const Value = std.json.Value;
const enumeration_kind = "enumeration";
/// The one checked schema kind that carries a variable-length element run.
const list_kind = "list";
/// The one checked type name that carries immutable Unicode text.
pub const text_name = "str";
/// Whether one checked type name is the language's text type. The rule is
/// nominal — the name is `str` — and never structural: `language-schema-v1`
/// spells `str` and a user `List<u32>` identically (kind `list`, opaque, a
/// `u32` element), so a shape test would carry a user's list as if it were
/// text. The compiler's manifest decides the same question by the same name
/// (`qbe_wire.textScalar`), so both ends of the boundary agree by construction.
pub fn isText(name: []const u8) bool {
    return std.mem.eql(u8, name, text_name);
}
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
    fn definition(self: Codec, name: []const u8) Error!Value {
        for (self.types) |item| if (std.mem.eql(u8, v.text(v.get(item, "name")), name)) return item;
        return error.UnsupportedTestType;
    }
    /// The scalar element type one text definition carries its code points as.
    fn textElement(item: Value) Error![]const u8 {
        const element = v.get(item, "element");
        if (element != .string) return error.UnsupportedTestType;
        return element.string;
    }
    /// The element type one user-list definition carries its items as, or null
    /// when the definition is not a list. Text is excluded nominally: the checked
    /// schema spells `str` with the same `list` kind and the same `u32` element,
    /// so the name is the only thing that separates text from `list[u32]`.
    fn listElement(name: []const u8, item: Value) Error!?[]const u8 {
        if (isText(name)) return null;
        if (!std.mem.eql(u8, v.text(v.get(item, "kind")), list_kind)) return null;
        const element = try textElement(item);
        return element;
    }
    /// Flatten one JSON array into the one-node-per-element list wire form: a
    /// list node whose `children` is the element count, followed by one node per
    /// element. The tree is copied in, so the guest never shares an alias with
    /// the request and a repeated reference arrives as repeated values.
    fn encodeList(self: *Codec, element: []const u8, value: Value, index: usize, depth: usize) Error!void {
        if (value != .array) return error.InvalidTestValue;
        self.nodes.items[index].children = value.array.items.len;
        for (value.array.items) |child| try self.encode(element, child, depth + 1);
    }
    /// Convert one returned list node back to a JSON array, rejecting a node tree
    /// that is not exactly the one-node-per-element list wire form.
    fn decodeList(self: *Codec, element: []const u8, node: Node, depth: usize) Error!Value {
        if (node.bits != 0 or node.children > self.nodes.items.len - self.cursor) return error.InvalidNativeTestResponse;
        var array: std.json.Array = .init(self.allocator);
        for (0..node.children) |_| try array.append(try self.decode(element, depth + 1));
        return .{ .array = array };
    }
    /// Flatten one JSON string into the one-node-per-scalar text wire form: a
    /// text node whose `children` is the scalar count, followed by one node per
    /// Unicode scalar in the declared element type. The string is decoded as
    /// UTF-8, so invalid bytes are refused here rather than reaching the guest,
    /// and an embedded NUL is just scalar zero — a text is length-carrying.
    fn encodeText(self: *Codec, element: []const u8, value: Value, index: usize) Error!void {
        if (value != .string) return error.InvalidTestValue;
        var view = std.unicode.Utf8View.init(value.string) catch return error.InvalidTestValue;
        var iterator = view.iterator();
        var count: usize = 0;
        while (iterator.nextCodepoint()) |scalar| {
            if (self.nodes.items.len >= 65536) return error.TestValueLimit;
            try self.nodes.append(self.allocator, .{ .type = element, .bits = scalar });
            count += 1;
        }
        self.nodes.items[index].children = count;
    }
    /// Convert one returned text node back to a JSON string, rejecting a node
    /// tree that is not exactly the text wire form and any scalar a JSON string
    /// cannot hold (a surrogate half or a code point above U+10FFFF).
    fn decodeText(self: *Codec, element: []const u8, node: Node) Error!Value {
        if (node.bits != 0 or node.children > self.nodes.items.len - self.cursor) return error.InvalidNativeTestResponse;
        var bytes: std.ArrayList(u8) = .empty;
        for (0..node.children) |_| {
            const child = self.nodes.items[self.cursor];
            self.cursor += 1;
            if (!std.mem.eql(u8, child.type, element) or child.children != 0) return error.InvalidNativeTestResponse;
            const scalar = std.math.cast(u21, child.bits) orelse return error.InvalidNativeTestResponse;
            var encoded: [4]u8 = undefined;
            const length = std.unicode.utf8Encode(scalar, &encoded) catch return error.InvalidNativeTestResponse;
            try bytes.appendSlice(self.allocator, encoded[0..length]);
        }
        return .{ .string = bytes.items };
    }
    /// Validate and flatten one typed JSON value without running domain methods.
    pub fn encode(self: *Codec, name: []const u8, value: Value, depth: usize) Error!void {
        if (depth > 64 or self.nodes.items.len >= 65536) return error.TestValueLimit;
        const item = try self.definition(name);
        const kind = v.text(v.get(item, "kind"));
        const index = self.nodes.items.len;
        try self.nodes.append(self.allocator, .{ .type = name });
        if (isText(name)) {
            try self.encodeText(try textElement(item), value, index);
        } else if (try listElement(name, item)) |element| {
            try self.encodeList(element, value, index, depth);
        } else if (std.mem.eql(u8, kind, "integer")) {
            if (value != .string) return error.InvalidTestValue;
            self.nodes.items[index].bits = try decimal(name, value.string);
        } else if (std.mem.eql(u8, kind, "boolean")) {
            if (value != .bool) return error.InvalidTestValue;
            self.nodes.items[index].bits = @intFromBool(value.bool);
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
        if (isText(name)) return self.decodeText(try textElement(item), node);
        if (try listElement(name, item)) |element| return self.decodeList(element, node, depth);
        if (std.mem.eql(u8, kind, "integer")) {
            if (node.children != 0) return error.InvalidNativeTestResponse;
            const number: i128 = if (v.boolean(v.get(item, "signed"))) @as(i64, @bitCast(node.bits)) else node.bits;
            return .{ .string = try std.fmt.allocPrint(self.allocator, "{d}", .{number}) };
        }
        if (std.mem.eql(u8, kind, "boolean")) {
            if (node.children != 0 or node.bits > 1) return error.InvalidNativeTestResponse;
            return .{ .bool = node.bits == 1 };
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

/// The checked definitions one text fixture needs: the element type `str`
/// carries its scalars as, the text type itself, and a structurally identical
/// user `List<u32>` that is deliberately not text.
const text_types =
    \\{"types":[{"name":"u32","kind":"integer","signed":false},{"name":"str","kind":"list","opaque":true,"element":"u32"},{"name":"List<u32>","kind":"list","opaque":true,"element":"u32"}]}
;

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

// spec: QBE-TEXT-2
test "text crosses as one node per scalar and a user list is not text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try std.json.parseFromSlice(Value, a, text_types, .{});
    const types = v.array(v.get(parsed.value, "types"));
    var codec: Codec = .{ .allocator = a, .types = types };
    defer codec.deinit();
    // ASCII, a two-byte scalar, an astral scalar and a combining sequence all
    // flatten to one node per scalar and come back byte for byte.
    const mixed = "a\u{e9}\u{1f600}e\u{301}";
    try codec.encode(text_name, .{ .string = mixed }, 0);
    try std.testing.expectEqual(@as(usize, 5), codec.nodes.items[0].children);
    try std.testing.expectEqual(@as(usize, 6), codec.nodes.items.len);
    try std.testing.expectEqualStrings(text_name, codec.nodes.items[0].type);
    try std.testing.expectEqual(@as(u64, 'a'), codec.nodes.items[1].bits);
    try std.testing.expectEqual(@as(u64, 0x1f600), codec.nodes.items[3].bits);
    try std.testing.expectEqualStrings(mixed, (try codec.decode(text_name, 0)).string);
    // An empty text has no scalar nodes, and an embedded NUL is scalar zero.
    codec.nodes.clearRetainingCapacity();
    codec.cursor = 0;
    try codec.encode(text_name, .{ .string = "" }, 0);
    try std.testing.expectEqual(@as(usize, 1), codec.nodes.items.len);
    try std.testing.expectEqualStrings("", (try codec.decode(text_name, 0)).string);
    codec.nodes.clearRetainingCapacity();
    codec.cursor = 0;
    try codec.encode(text_name, .{ .string = "a\x00b" }, 0);
    try std.testing.expectEqual(@as(usize, 3), codec.nodes.items[0].children);
    try std.testing.expectEqualStrings("a\x00b", (try codec.decode(text_name, 0)).string);
    // A user `List<u32>` has the identical checked shape and is still not text:
    // the name decides, exactly as it does on the compiler's side. It is carried
    // as a list now, so a JSON string is the wrong value for it while a JSON
    // array flattens to one node per element and comes back as an array again.
    try std.testing.expect(isText(text_name));
    try std.testing.expect(!isText("List<u32>"));
    try std.testing.expectError(error.InvalidTestValue, codec.encode("List<u32>", .{ .string = "x" }, 0));
    var items: std.json.Array = .init(a);
    try items.append(.{ .string = "7" });
    try items.append(.{ .string = "9" });
    codec.nodes.clearRetainingCapacity();
    codec.cursor = 0;
    try codec.encode("List<u32>", .{ .array = items }, 0);
    try std.testing.expectEqual(@as(usize, 3), codec.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 2), codec.nodes.items[0].children);
    try std.testing.expectEqual(@as(u64, 7), codec.nodes.items[1].bits);
    const listed = try codec.decode("List<u32>", 0);
    try std.testing.expectEqual(@as(usize, 2), listed.array.items.len);
    try std.testing.expectEqualStrings("9", listed.array.items[1].string);
    try std.testing.expectError(error.InvalidTestValue, codec.encode(text_name, .{ .integer = 1 }, 0));
    try std.testing.expectError(error.InvalidTestValue, codec.encode(text_name, .{ .string = "\xff" }, 0));
    // A text over the node budget is refused, never truncated.
    codec.nodes.clearRetainingCapacity();
    codec.cursor = 0;
    const long = try a.alloc(u8, 70000);
    @memset(long, 'x');
    try std.testing.expectError(error.TestValueLimit, codec.encode(text_name, .{ .string = long }, 0));
}

/// One text round trip on a fixed schema, so every allocation it makes can be
/// failed in turn: an allocation failure while decoding must be reported as
/// `OutOfMemory` and must not leak the nodes or bytes built so far.
fn textScenario(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try std.json.parseFromSlice(Value, a, text_types, .{});
    var codec: Codec = .{ .allocator = a, .types = v.array(v.get(parsed.value, "types")) };
    defer codec.deinit();
    try codec.encode(text_name, .{ .string = "a\u{e9}\u{1f600}" }, 0);
    const decoded = try codec.decode(text_name, 0);
    try std.testing.expectEqualStrings("a\u{e9}\u{1f600}", decoded.string);
}

// spec: QBE-TEXT-3
test "a failed allocation while converting text is reported and released" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, textScenario, .{});
}

/// A schema whose values nest a list inside a list and inside a record, so an
/// allocation failure can land anywhere in a tree instead of on a single node.
const nested_types =
    \\{"types":[
    \\{"name":"u32","kind":"integer","signed":false},
    \\{"name":"i64","kind":"integer","signed":true},
    \\{"name":"str","kind":"list","opaque":true,"element":"u32"},
    \\{"name":"List<i64>","kind":"list","opaque":true,"element":"i64"},
    \\{"name":"List<List<i64>>","kind":"list","opaque":true,"element":"List<i64>"},
    \\{"name":"Bucket","kind":"record","move_only":false,"opaque":false,"fields":[{"name":"label","type":"str"},{"name":"values","type":"List<i64>"}]}]}
;

fn stringArray(allocator: std.mem.Allocator, items: []const []const u8) !Value {
    var array: std.json.Array = .init(allocator);
    for (items) |item| try array.append(.{ .string = item });
    return .{ .array = array };
}

/// A record holding a text and a list: the shape a tool returns, and the one
/// whose decode builds three separate managed values before it can hand back a
/// single node tree.
fn bucketValue(allocator: std.mem.Allocator) !Value {
    var object: std.json.ObjectMap = .empty;
    try object.put(allocator, "label", .{ .string = "x" });
    try object.put(allocator, "values", try stringArray(allocator, &.{ "1", "2" }));
    return .{ .object = object };
}

/// One nested round trip on a fixed schema, so every allocation it makes can be
/// failed in turn: an allocation failure while converting a list or a record
/// must be reported as `OutOfMemory` and must not leak the nodes, the elements
/// or the text built so far.
fn nestedScenario(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try std.json.parseFromSlice(Value, a, nested_types, .{});
    var codec: Codec = .{ .allocator = a, .types = v.array(v.get(parsed.value, "types")) };
    defer codec.deinit();
    var outer: std.json.Array = .init(a);
    try outer.append(try stringArray(a, &.{ "1", "2" }));
    try outer.append(try stringArray(a, &.{"3"}));
    try codec.encode("List<List<i64>>", .{ .array = outer }, 0);
    const lists = try codec.decode("List<List<i64>>", 0);
    // Without this the scenario would pass even if it converted nothing: the
    // assertions are what make a failed allocation the only way to fail.
    try std.testing.expectEqual(@as(usize, 2), lists.array.items.len);
    try std.testing.expectEqual(@as(usize, 2), lists.array.items[0].array.items.len);
    try std.testing.expectEqualStrings("3", lists.array.items[1].array.items[0].string);
    codec.nodes.clearRetainingCapacity();
    codec.cursor = 0;
    try codec.encode("Bucket", try bucketValue(a), 0);
    const record = try codec.decode("Bucket", 0);
    try std.testing.expectEqualStrings("x", record.object.get("label").?.string);
    try std.testing.expectEqual(@as(usize, 2), record.object.get("values").?.array.items.len);
    try std.testing.expectEqualStrings("2", record.object.get("values").?.array.items[1].string);
}

// spec: QBE-LIST-3
test "a failed allocation while converting a nested list or record is released" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, nestedScenario, .{});
}

/// The installed compiler the build names beside `MYLANG_QBE`, plus the project
/// root the three-level install path (`zig-out/bin|focus/qbe`) sits under.
const Tools = struct { compiler: []const u8, root: []const u8 };

fn tools(allocator: std.mem.Allocator) !Tools {
    const qbe = std.testing.environ.getPosix("MYLANG_QBE") orelse return error.ToolNotFound;
    const bin = std.fs.path.dirname(qbe) orelse return error.ToolNotFound;
    const out = std.fs.path.dirname(bin) orelse return error.ToolNotFound;
    const root = std.fs.path.dirname(out) orelse return error.ToolNotFound;
    return .{ .compiler = try std.fs.path.join(allocator, &.{ bin, "mylang" }), .root = try allocator.dupe(u8, root) };
}

/// Run one checked-in case fixture through the installed compiler against a
/// fresh cache, then require the runner's case count and its failure count.
fn runFixture(allocator: std.mem.Allocator, resolved: Tools, stem: []const u8, expected_passes: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const entry = try std.fs.path.join(a, &.{ resolved.root, "tests", "native", try std.fmt.allocPrint(a, "{s}.my", .{stem}) });
    const cases = try std.fs.path.join(a, &.{ resolved.root, "tests", "native", try std.fmt.allocPrint(a, "{s}.cases.json", .{stem}) });
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const cache = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const result = try std.process.run(a, std.testing.io, .{
        .argv = &.{ resolved.compiler, "test", entry, "--cases", cases, "--cache-dir", cache },
        .cwd = .inherit,
    });
    if (build_io.exitCode(result.term) != 0) try std.Io.File.stderr().writeStreamingAll(std.testing.io, result.stderr);
    try std.testing.expectEqual(@as(u8, 0), build_io.exitCode(result.term));
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, expected_passes) != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "0 failed") != null);
}

// spec-case: NATIVE-TEST-13
test "local mutation reuses a receipt while output executes again" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const resolved = try tools(a);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.my", .data =
        \\module main
        \\
        \\def change(xs: list[int]) -> None effects(mutation) mutates(xs):
        \\    xs[0] = 2
        \\
        \\public def test_local_mutation() -> bool effects(mutation, managed_allocation):
        \\    xs: list[int] = [1]
        \\    change(xs)
        \\    return xs[0] == 2
        \\
        \\public def test_external_output(out: Stream) -> bool effects(output):
        \\    out.print("")
        \\    return True
        \\
        \\def main() -> int:
        \\    return 0
    });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const entry = try std.fs.path.join(a, &.{ root, "main.my" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const argv = &.{ resolved.compiler, "test", entry, "--json", "--cache-dir", cache };
    const cold = try std.process.run(a, std.testing.io, .{ .argv = argv });
    try std.testing.expectEqual(@as(u8, 0), build_io.exitCode(cold.term));
    const warm = try std.process.run(a, std.testing.io, .{ .argv = argv });
    try std.testing.expectEqual(@as(u8, 0), build_io.exitCode(warm.term));
    const report = try std.json.parseFromSlice(std.json.Value, a, warm.stdout, .{});
    try std.testing.expectEqual(@as(i64, 1), v.get(report.value, "cached").integer);
    try std.testing.expectEqual(@as(i64, 1), v.get(report.value, "passed").integer);
}

// spec: QBE-AGGREF-5
test "a record, an array, a nested record, a zero-length and a large argument round-trip through mylang test" {
    const a = std.testing.allocator;
    const resolved = try tools(a);
    defer a.free(resolved.compiler);
    defer a.free(resolved.root);
    try runFixture(a, resolved, "aggref_arguments", "7 passed");
    try std.testing.expect(resolved.root.len != 0);
    try std.testing.expect(std.mem.endsWith(u8, resolved.compiler, "mylang"));
}
