//! Core's private copied-value token transport for generated test inputs/results.
//! Values follow the old generator's typed JSON tree; no published wire ABI changes.
const std = @import("std");
const types = @import("property_types.zig");
const v = @import("property_value.zig");
const validate = @import("property_validate.zig");
const Value = std.json.Value;
/// Bad internal transport or allocation stops the trial rather than passing it.
pub const Error = error{ OutOfMemory, InvalidTestValue, UnsupportedTestType };
/// A preorder value tree of two little-endian words per node: bits and child count.
pub const Codec = struct {
    allocator: std.mem.Allocator,
    schema: types.Schema,
    words: std.ArrayList(u64) = .empty,
    cursor: usize = 0,
    /// Release the owned transport buffer; schema definitions belong to the caller.
    pub fn deinit(self: *Codec) void {
        self.words.deinit(self.allocator);
        self.cursor = 0;
    }
    /// Append one typed generated value.
    pub fn encode(self: *Codec, name: []const u8, value: Value) Error!void {
        try validate.validate(self.schema, name, value, self.words.items.len / 2);
        try self.append(name, value);
    }
    fn append(self: *Codec, name: []const u8, value: Value) Error!void {
        const shape = try self.schema.shape(name);
        const slot = self.words.items.len;
        try self.words.appendSlice(self.allocator, &.{ 0, 0 });
        switch (shape) {
            .integer => {
                const n = std.fmt.parseInt(i128, v.text(value), 10) catch return error.InvalidTestValue;
                self.words.items[slot] = @truncate(@as(u128, @bitCast(n)));
            },
            .atom => |atom| switch (atom) {
                .boolean => self.words.items[slot] = @intFromBool(value.bool),
                .float => {
                    const n = std.fmt.parseFloat(f64, v.text(value)) catch return error.InvalidTestValue;
                    self.words.items[slot] = if (std.math.isNan(n)) 0x7ff8000000000000 else @bitCast(n);
                },
                .text => {
                    var view = std.unicode.Utf8View.init(v.text(value)) catch return error.InvalidTestValue;
                    var it = view.iterator();
                    var count: u64 = 0;
                    while (it.nextCodepoint()) |point| {
                        try self.words.appendSlice(self.allocator, &.{ point, 0 });
                        count += 1;
                    }
                    self.words.items[slot + 1] = count;
                },
                .bytes => {
                    self.words.items[slot + 1] = v.array(value).len;
                    for (v.array(value)) |item| try self.append("u8", item);
                },
            },
            .sequence => |sequence| {
                self.words.items[slot + 1] = v.array(value).len;
                for (v.array(value)) |item| try self.append(sequence.element, item);
            },
            .keyed => |pair| {
                if (pair.table) {
                    const keys = (try self.schema.shape(pair.key)).cases.cases;
                    self.words.items[slot + 1] = keys.len;
                    for (keys) |key| try self.append(pair.value, v.get(value, v.text(v.get(key, "name"))));
                } else {
                    self.words.items[slot + 1] = v.array(value).len;
                    for (v.array(value)) |entry| {
                        try self.append(pair.key, entry.array.items[0]);
                        try self.append(pair.value, entry.array.items[1]);
                    }
                }
            },
            .record => |fields| {
                self.words.items[slot + 1] = fields.len;
                for (fields) |field| try self.append(field.type, v.get(value, field.name));
            },
            .cases => |cases| {
                const selected = if (cases.payloads) v.text(v.get(value, "case")) else v.text(value);
                for (cases.cases, 0..) |case, index| if (std.mem.eql(u8, selected, v.text(v.get(case, "name")))) {
                    self.words.items[slot] = index;
                    const payload = v.get(case, "payload");
                    if (payload == .string) {
                        self.words.items[slot + 1] = 1;
                        try self.append(payload.string, v.get(value, "value"));
                    }
                    return;
                };
                return error.InvalidTestValue;
            },
            .refused => return error.UnsupportedTestType,
        }
    }
    fn word(self: *Codec) Error!u64 {
        if (self.cursor >= self.words.items.len) return error.InvalidTestValue;
        defer self.cursor += 1;
        return self.words.items[self.cursor];
    }
    /// Reconstruct one returned typed value, retaining all float bit distinctions.
    pub fn decode(self: *Codec, name: []const u8) Error!Value {
        const bits = try self.word();
        const count = try self.word();
        return switch (try self.schema.shape(name)) {
            .integer => |range| blk: {
                const mask = (@as(u128, 1) << range.bits) - 1;
                var n: i128 = @intCast(@as(u128, bits) & mask);
                if (range.signed and n > range.maximum) n -= @as(i128, 1) << range.bits;
                break :blk .{ .string = try std.fmt.allocPrint(self.allocator, "{d}", .{n}) };
            },
            .atom => |atom| switch (atom) {
                .boolean => .{ .bool = bits != 0 },
                .float => .{ .string = try @import("property_generate.zig").floatText(self.allocator, @bitCast(bits)) },
                .text => blk: {
                    var text: std.ArrayList(u8) = .empty;
                    for (0..count) |_| {
                        const point = std.math.cast(u21, try self.word()) orelse return error.InvalidTestValue;
                        _ = try self.word();
                        var bytes: [4]u8 = undefined;
                        const width = std.unicode.utf8Encode(point, &bytes) catch return error.InvalidTestValue;
                        try text.appendSlice(self.allocator, bytes[0..width]);
                    }
                    break :blk .{ .string = text.items };
                },
                .bytes => self.decodeSequence("u8", count),
            },
            .sequence => |sequence| self.decodeSequence(sequence.element, count),
            .keyed => |pair| if (pair.table) self.table(pair) else self.dict(pair, count),
            .record => |fields| blk: {
                var object: std.json.ObjectMap = .empty;
                for (fields) |field| try object.put(self.allocator, field.name, try self.decode(field.type));
                break :blk .{ .object = object };
            },
            .cases => |cases| blk: {
                if (bits >= cases.cases.len) return error.InvalidTestValue;
                const case = cases.cases[@intCast(bits)];
                if (!cases.payloads) break :blk v.get(case, "name");
                var object: std.json.ObjectMap = .empty;
                try object.put(self.allocator, "case", v.get(case, "name"));
                const payload = v.get(case, "payload");
                if (payload == .string) try object.put(self.allocator, "value", try self.decode(payload.string));
                break :blk .{ .object = object };
            },
            .refused => error.UnsupportedTestType,
        };
    }
    fn decodeSequence(self: *Codec, element: []const u8, count: u64) Error!Value {
        if (count > self.words.items.len) return error.InvalidTestValue;
        var array: std.json.Array = .init(self.allocator);
        for (0..count) |_| try array.append(try self.decode(element));
        return .{ .array = array };
    }
    fn dict(self: *Codec, pair: types.Keyed, count: u64) Error!Value {
        var array: std.json.Array = .init(self.allocator);
        for (0..count) |_| {
            var entry: std.json.Array = .init(self.allocator);
            try entry.append(try self.decode(pair.key));
            try entry.append(try self.decode(pair.value));
            try array.append(.{ .array = entry });
        }
        return .{ .array = array };
    }
    fn table(self: *Codec, pair: types.Keyed) Error!Value {
        var object: std.json.ObjectMap = .empty;
        for ((try self.schema.shape(pair.key)).cases.cases) |key| try object.put(self.allocator, v.text(v.get(key, "name")), try self.decode(pair.value));
        return .{ .object = object };
    }
};

fn roundtrips(a: std.mem.Allocator) !usize {
    const generate = @import("property_generate.zig");
    const parsed = try std.json.parseFromSliceLeaky(Value, a, generate.test_schema, .{});
    const schema = try types.Schema.init(a, v.array(v.get(parsed, "types")));
    var checked: usize = 0;
    for (generate.test_names) |name| for (0..12) |run| {
        var generator: generate.Generator = .{ .arena = a, .schema = schema, .stream = .init(7, run), .size = generate.sizeOf(run, 12) };
        const original = try generator.value(name, 0);
        var copied: Codec = .{ .allocator = a, .schema = schema };
        try copied.encode(name, original);
        const returned = try copied.decode(name);
        try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, original, .{}), try std.json.Stringify.valueAlloc(a, returned, .{}));
        try std.testing.expectEqual(copied.words.items.len, copied.cursor);
        checked += 1;
    };
    return checked;
}
// spec-case: NEW-CORE-S3-RUNNER-1
test "Core copied property values preserve every generated shape and IEEE bits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@import("property_generate.zig").test_names.len * 12, try roundtrips(a));
    var truncated: Codec = .{ .allocator = a, .schema = try types.Schema.init(a, &.{}) };
    try truncated.words.append(a, 1);
    try std.testing.expectError(error.InvalidTestValue, truncated.decode("bool"));
}
