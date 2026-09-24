//! Deterministic input generation for property tests (PROPERTY-TEST-1). Every
//! input is a typed JSON value built from the checked type alone, drawn from a
//! SplitMix64 stream seeded by the test's seed and the run number, so run N of
//! a property is the same value on every machine and every rerun. Sizes grow
//! from 0 on the first run to `max_size` on the last, and integers lean on
//! their edges (0, ±1, the width's minimum and maximum, powers of two).
const std = @import("std");
const v = @import("qbe_build_value.zig");
const types = @import("property_types.zig");
const Value = std.json.Value;

/// The generator identity a passing property's receipt binds: a change to
/// how inputs are drawn re-executes every property instead of reusing a pass
/// earned against other inputs.
pub const version = "property-generator-v1";
/// The size the last run of a property reaches: a collection holds at most
/// this many elements at the top level, half as many one level down.
pub const max_size = 100;
/// Copied nodes one generated input may use before collections stay empty.
const node_budget = 4096;
/// Variant nesting past which a generator takes a case's minimal value.
const depth_limit = 12;
/// Generation failures: allocation, or a type that cannot be generated.
pub const Error = error{ OutOfMemory, UnsupportedTestType };

/// SplitMix64: a counter-based 64-bit stream. It is a pure function of its
/// state, never of the machine or the clock, so a seed names its inputs.
pub const Stream = struct {
    state: u64,

    /// The stream for one run of one property: the seed and the run number
    /// mixed, so run N can be regenerated without drawing runs 0..N-1.
    pub fn init(seed: u64, run: u64) Stream {
        var stream: Stream = .{ .state = seed ^ (run +% 1) *% 0xd1b54a32d192ed03 };
        _ = stream.next();
        return stream;
    }
    /// The next 64 bits of the stream.
    pub fn next(self: *Stream) u64 {
        self.state +%= 0x9e3779b97f4a7c15;
        var z = self.state;
        z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
        z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
        return z ^ (z >> 31);
    }
    /// A value in `[0, bound)`, or 0 when `bound` is 0.
    pub fn below(self: *Stream, bound: u64) u64 {
        return @intCast((@as(u128, self.next()) * bound) >> 64);
    }
};

/// The size run `run` of `runs` generates at: 0 first and `max_size` last.
/// Runs drawn to replace discarded inputs repeat the same schedule, so a
/// precondition that rejects large inputs still sees small ones.
pub fn sizeOf(run: usize, runs: usize) usize {
    if (runs <= 1) return max_size;
    return (run % runs) * max_size / (runs - 1);
}

/// One input's generation state: the schema, the run's stream and size, and
/// the nodes spent so far. Every value lives in the run's arena.
pub const Generator = struct {
    arena: std.mem.Allocator,
    schema: types.Schema,
    stream: Stream,
    size: usize,
    nodes: usize = 0,

    /// Generate one value of the named type as its typed JSON representation.
    pub fn value(self: *Generator, name: []const u8, depth: usize) Error!Value {
        self.nodes += 1;
        return switch (try self.schema.shape(name)) {
            .integer => |range| self.decimal(self.integer(range)),
            .atom => |kind| self.atom(kind, depth),
            .sequence => |shape| self.sequence(shape, depth),
            .keyed => |pair| if (pair.table) self.table(pair, depth) else self.dict(pair, depth),
            .record => |fields| self.record(fields, depth),
            .cases => |cases| if (cases.payloads) self.variant(cases.cases, depth) else v.get(cases.cases[@intCast(self.stream.below(cases.cases.len))], "name"),
            .refused => error.UnsupportedTestType,
        };
    }
    fn atom(self: *Generator, atom_shape: types.Atom, depth: usize) Error!Value {
        return switch (atom_shape) {
            .boolean => .{ .bool = self.stream.below(2) == 1 },
            .float => .{ .string = try floatText(self.arena, self.float()) },
            .text => self.text(depth),
            .bytes => self.bytes(depth),
        };
    }
    /// A collection length for this depth: uniform up to the size, halved per
    /// level, and zero once the input has spent its node budget.
    fn length(self: *Generator, depth: usize) usize {
        if (self.nodes >= node_budget) return 0;
        const bound = self.size >> @intCast(@min(depth, 16));
        return @intCast(self.stream.below(bound + 1));
    }
    fn integer(self: *Generator, range: types.Integer) i128 {
        const roll = self.stream.below(8);
        if (roll < 3) return edge(range, self.stream.below(8), self.stream.next());
        if (roll == 3) return wrap(range, self.stream.next());
        const reach: i128 = @intCast((self.size + 1) * (self.size + 1));
        const low = @max(range.minimum, -reach);
        const high = @min(range.maximum, reach);
        return low + @as(i128, @intCast(self.stream.below(@intCast(high - low + 1))));
    }
    fn float(self: *Generator) f64 {
        const roll = self.stream.below(8);
        if (roll < 2) return float_edges[@intCast(self.stream.below(float_edges.len))];
        if (roll == 2) return @bitCast(self.stream.next());
        const reach: i64 = @intCast((self.size + 1) * (self.size + 1));
        const whole: i64 = @as(i64, @intCast(self.stream.below(@intCast(2 * reach + 1)))) - reach;
        const scale: f64 = @floatFromInt(@as(u64, 1) << @intCast(self.stream.below(12)));
        return @as(f64, @floatFromInt(whole)) / scale;
    }
    /// A Unicode scalar: mostly printable ASCII, some controls, some
    /// well-known troublemakers and some drawn from the whole range.
    fn scalar(self: *Generator) u21 {
        const roll = self.stream.below(10);
        if (roll < 7) return @intCast(0x20 + self.stream.below(0x5f));
        if (roll == 7) return control[@intCast(self.stream.below(control.len))];
        if (roll == 8) return notable[@intCast(self.stream.below(notable.len))];
        const point: u21 = @intCast(0x80 + self.stream.below(0x10ffff - 0x80 - 0x800 + 1));
        return if (point >= 0xd800) point + 0x800 else point;
    }
    fn text(self: *Generator, depth: usize) Error!Value {
        const count = self.length(depth);
        var bytes_out: std.ArrayList(u8) = .empty;
        for (0..count) |_| {
            var encoded: [4]u8 = undefined;
            const width = std.unicode.utf8Encode(self.scalar(), &encoded) catch return error.UnsupportedTestType;
            try bytes_out.appendSlice(self.arena, encoded[0..width]);
        }
        self.nodes += count;
        return .{ .string = bytes_out.items };
    }
    fn bytes(self: *Generator, depth: usize) Error!Value {
        const count = self.length(depth);
        var items: std.json.Array = .init(self.arena);
        for (0..count) |_| {
            const roll = self.stream.below(4);
            const byte: u8 = if (roll == 0) byte_edges[@intCast(self.stream.below(byte_edges.len))] else @intCast(self.stream.below(256));
            try items.append(try self.decimal(byte));
        }
        self.nodes += count;
        return .{ .array = items };
    }
    /// A list of drawn length, a fixed array of its declared length, or a set,
    /// whose repeated draws are dropped so every element is distinct.
    fn sequence(self: *Generator, sequence_shape: types.Sequence, depth: usize) Error!Value {
        const count = sequence_shape.length orelse self.length(depth);
        var items: std.json.Array = .init(self.arena);
        for (0..count) |_| {
            const item = try self.value(sequence_shape.element, depth + 1);
            if (sequence_shape.distinct and try containsValue(self.arena, items.items, item, false)) continue;
            try items.append(item);
        }
        return .{ .array = items };
    }
    /// A dictionary is a list of distinct `[key, value]` pairs; a drawn key
    /// that repeats an earlier one is dropped rather than overwriting it.
    fn dict(self: *Generator, pair: types.Keyed, depth: usize) Error!Value {
        const count = self.length(depth);
        var items: std.json.Array = .init(self.arena);
        for (0..count) |_| {
            const key = try self.value(pair.key, depth + 1);
            if (try containsValue(self.arena, items.items, key, true)) continue;
            var entry: std.json.Array = .init(self.arena);
            try entry.append(key);
            try entry.append(try self.value(pair.value, depth + 1));
            try items.append(.{ .array = entry });
        }
        return .{ .array = items };
    }
    fn table(self: *Generator, pair: types.Keyed, depth: usize) Error!Value {
        const keys = try self.schema.shape(pair.key);
        if (keys != .cases) return error.UnsupportedTestType;
        var object: std.json.ObjectMap = .empty;
        for (keys.cases.cases) |case| try object.put(self.arena, v.text(v.get(case, "name")), try self.value(pair.value, depth + 1));
        return .{ .object = object };
    }
    fn record(self: *Generator, fields: []const types.Field, depth: usize) Error!Value {
        var object: std.json.ObjectMap = .empty;
        for (fields) |field| try object.put(self.arena, field.name, try self.value(field.type, depth + 1));
        return .{ .object = object };
    }
    /// A case drawn uniformly; past the depth limit the first case's minimal
    /// value, so a recursive union still ends.
    fn variant(self: *Generator, cases: []const Value, depth: usize) Error!Value {
        if (depth > depth_limit or self.nodes >= node_budget) return minimal(self.arena, self.schema, cases, 0, depth);
        const index: usize = @intCast(self.stream.below(cases.len));
        const payload = v.get(cases[index], "payload");
        var object: std.json.ObjectMap = .empty;
        try object.put(self.arena, "case", v.get(cases[index], "name"));
        if (payload == .string) try object.put(self.arena, "value", try self.value(payload.string, depth + 1));
        return .{ .object = object };
    }
    fn decimal(self: *Generator, number: i128) Error!Value {
        return .{ .string = try std.fmt.allocPrint(self.arena, "{d}", .{number}) };
    }
};

/// One integer from the edges of its range: 0, 1, -1, the minimum and
/// maximum and their neighbours, and a power of two, one below it, or its
/// negation, clamped into the range.
fn edge(range: types.Integer, pick: u64, bits: u64) i128 {
    const exponent: u7 = @intCast(1 + bits % (range.bits - @intFromBool(range.signed)));
    const power = @as(i128, 1) << exponent;
    const candidate: i128 = switch (pick) {
        0 => 0,
        1 => 1,
        2 => -1,
        3 => range.minimum,
        4 => range.maximum,
        5 => power,
        6 => power - 1,
        else => -power,
    };
    return std.math.clamp(candidate, range.minimum, range.maximum);
}
/// A uniform value over the whole width: 64 random bits truncated to it.
fn wrap(range: types.Integer, bits: u64) i128 {
    const width: u7 = range.bits;
    const mask: u128 = (@as(u128, 1) << width) - 1;
    const raw: i128 = @intCast(@as(u128, bits) & mask);
    return if (raw > range.maximum) raw - (@as(i128, 1) << width) else raw;
}

/// ASCII controls a string generator draws: the ones programs special-case.
const control = [_]u21{ 0, '\t', '\n', '\r', 0x1b, 0x7f };
/// Non-ASCII scalars that commonly break text handling: two-, three- and
/// four-byte encodings, a combining mark, the byte-order mark, the
/// replacement character, a line separator and the last scalar.
const notable = [_]u21{ 0xe9, 0xdf, 0x3a9, 0x4e2d, 0x1f600, 0x301, 0xfeff, 0xfffd, 0x2028, 0x10ffff };
const byte_edges = [_]u8{ 0, 1, 0x7f, 0x80, 0xff };
/// Floats a generator draws on purpose: both zeros, the units, both
/// infinities, NaN, the extreme finite and subnormal magnitudes.
const float_edges = [_]f64{ 0.0, -0.0, 1.0, -1.0, 0.5, std.math.inf(f64), -std.math.inf(f64), std.math.nan(f64), std.math.floatMax(f64), -std.math.floatMax(f64), std.math.floatMin(f64), std.math.floatTrueMin(f64), 1e-10 };

/// The canonical typed JSON text of a float, shared with the wire codec.
pub const floatText = @import("native_test_wire.zig").floatText;

/// Whether a set's elements, or a dictionary's pairs (`keyed`), already hold
/// this value as an element or a key.
fn containsValue(arena: std.mem.Allocator, items: []const Value, wanted: Value, pairs: bool) error{OutOfMemory}!bool {
    const spelled = try std.json.Stringify.valueAlloc(arena, wanted, .{});
    for (items) |item| {
        const held = if (pairs) item.array.items[0] else item;
        if (std.mem.eql(u8, spelled, try std.json.Stringify.valueAlloc(arena, held, .{}))) return true;
    }
    return false;
}

/// The simplest value of a type: zero, false, empty, the first case with its
/// payload's simplest value, every field and element at its simplest.
pub fn simplest(arena: std.mem.Allocator, schema: types.Schema, name: []const u8, depth: usize) Error!Value {
    if (depth > 2 * depth_limit) return error.UnsupportedTestType;
    return switch (try schema.shape(name)) {
        .integer => .{ .string = "0" },
        .atom => |kind| switch (kind) {
            .boolean => .{ .bool = false },
            .float => .{ .string = "0.0" },
            .text => .{ .string = "" },
            .bytes => .{ .array = .init(arena) },
        },
        .sequence => |sequence| filled(arena, schema, sequence.element, sequence.length orelse 0, depth),
        .keyed => |pair| if (pair.table) keyed(arena, schema, pair, depth) else .{ .array = .init(arena) },
        .record => |fields| fieldwise(arena, schema, fields, depth),
        .cases => |cases| if (cases.payloads) minimal(arena, schema, cases.cases, 0, depth) else v.get(cases.cases[0], "name"),
        .refused => error.UnsupportedTestType,
    };
}
/// The simplest value of one variant case: its name and its payload's simplest value.
pub fn minimal(arena: std.mem.Allocator, schema: types.Schema, cases: []const Value, index: usize, depth: usize) Error!Value {
    var object: std.json.ObjectMap = .empty;
    try object.put(arena, "case", v.get(cases[index], "name"));
    const payload = v.get(cases[index], "payload");
    if (payload == .string) try object.put(arena, "value", try simplest(arena, schema, payload.string, depth + 1));
    return .{ .object = object };
}
fn filled(arena: std.mem.Allocator, schema: types.Schema, element: []const u8, count: usize, depth: usize) Error!Value {
    var items: std.json.Array = .init(arena);
    for (0..count) |_| try items.append(try simplest(arena, schema, element, depth + 1));
    return .{ .array = items };
}
fn keyed(arena: std.mem.Allocator, schema: types.Schema, pair: types.Keyed, depth: usize) Error!Value {
    const keys = try schema.shape(pair.key);
    if (keys != .cases) return error.UnsupportedTestType;
    var object: std.json.ObjectMap = .empty;
    for (keys.cases.cases) |case| try object.put(arena, v.text(v.get(case, "name")), try simplest(arena, schema, pair.value, depth + 1));
    return .{ .object = object };
}
fn fieldwise(arena: std.mem.Allocator, schema: types.Schema, fields: []const types.Field, depth: usize) Error!Value {
    var object: std.json.ObjectMap = .empty;
    for (fields) |field| try object.put(arena, field.name, try simplest(arena, schema, field.type, depth + 1));
    return .{ .object = object };
}

/// A schema covering every generated shape, in the `language-schema-v1`
/// spelling the checked library reports, shared by the property tests.
pub const test_schema =
    \\{"types":[
    \\{"name":"i64","kind":"integer","bits":64,"signed":true},
    \\{"name":"i32","kind":"integer","bits":32,"signed":true},
    \\{"name":"u8","kind":"integer","bits":8,"signed":false},
    \\{"name":"u32","kind":"integer","bits":32,"signed":false},
    \\{"name":"bool","kind":"boolean"},
    \\{"name":"unit","kind":"unit"},
    \\{"name":"float","kind":"domain","opaque":true},
    \\{"name":"str","kind":"list","opaque":true,"element":"u32"},
    \\{"name":"bytes","kind":"list","opaque":true,"element":"u8"},
    \\{"name":"List<i64>","kind":"list","opaque":true,"element":"i64"},
    \\{"name":"List<str>","kind":"list","opaque":true,"element":"str"},
    \\{"name":"dict<str,i64>","kind":"list","opaque":true,"element":"i64","key":"str"},
    \\{"name":"set<i64>","kind":"list","opaque":true,"element":"unit","key":"i64"},
    \\{"name":"tuple<i64,str>","kind":"record","fields":[{"name":"$0","type":"i64"},{"name":"$1","type":"str"}]},
    \\{"name":"main::Point","kind":"record","fields":[{"name":"x","type":"i64"},{"name":"y","type":"u8"}]},
    \\{"name":"main::Shape","kind":"tagged_union","cases":[{"name":"circle","payload":"i64"},{"name":"square","payload":"main::Point"},{"name":"empty"}]},
    \\{"name":"main::Color","kind":"enumeration","cases":[{"name":"red"},{"name":"green"},{"name":"blue"}]},
    \\{"name":"Option<i64>","kind":"tagged_union","cases":[{"name":"none"},{"name":"some","payload":"i64"}]},
    \\{"name":"Result<bool,str>","kind":"result","cases":[{"name":"ok","payload":"bool"},{"name":"err","payload":"str"}]},
    \\{"name":"[3]u8","kind":"array","element":"u8","length":3},
    \\{"name":"[main::Color]i64","kind":"table","key":"main::Color","element":"i64"}]}
;
/// Every data type name `test_schema` defines.
pub const test_names = [_][]const u8{
    "i64",         "i32",         "u8",               "bool",     "float",            "str",         "bytes",
    "List<i64>",   "List<str>",   "dict<str,i64>",    "set<i64>", "tuple<i64,str>",   "main::Point", "main::Shape",
    "main::Color", "Option<i64>", "Result<bool,str>", "[3]u8",    "[main::Color]i64",
};

fn testTypes(arena: std.mem.Allocator) ![]const Value {
    const parsed = try std.json.parseFromSliceLeaky(Value, arena, test_schema, .{});
    return v.array(v.get(parsed, "types"));
}
fn drawn(arena: std.mem.Allocator, name: []const u8, seed: u64, run: usize) ![]const u8 {
    var generator: Generator = .{ .arena = arena, .schema = try types.Schema.init(arena, try testTypes(arena)), .stream = .init(seed, run), .size = sizeOf(run, 100) };
    return std.json.Stringify.valueAlloc(arena, try generator.value(name, 0), .{});
}
/// How 400 drawn `i64` values spread: how many were one of the edges, and
/// whether the width's minimum and maximum both appeared.
const Spread = struct { edges: usize = 0, minimum: bool = false, maximum: bool = false, outside: usize = 0 };
fn spread(arena: std.mem.Allocator, name: []const u8) !Spread {
    const schema = try types.Schema.init(arena, try testTypes(arena));
    const range = (try schema.shape(name)).integer;
    var result: Spread = .{};
    for (0..400) |run| {
        var generator: Generator = .{ .arena = arena, .schema = schema, .stream = .init(7, run), .size = sizeOf(run % 100, 100) };
        const number = try std.fmt.parseInt(i128, (try generator.value(name, 0)).string, 10);
        const edge_value = number == 0 or number == 1 or number == -1 or number == range.minimum or number == range.maximum;
        result.edges += @intFromBool(edge_value);
        result.minimum = result.minimum or number == range.minimum;
        result.maximum = result.maximum or number == range.maximum;
        result.outside += @intFromBool(number < range.minimum or number > range.maximum);
    }
    return result;
}
/// Scalars drawn over 100 strings: all of them, and the ASCII ones.
fn scalars(arena: std.mem.Allocator) !struct { total: usize, ascii: usize } {
    var total: usize = 0;
    var ascii: usize = 0;
    for (0..100) |run| {
        var generator: Generator = .{ .arena = arena, .schema = try types.Schema.init(arena, try testTypes(arena)), .stream = .init(11, run), .size = sizeOf(run, 100) };
        const text_value = (try generator.value("str", 0)).string;
        var view = try std.unicode.Utf8View.init(text_value);
        var iterator = view.iterator();
        while (iterator.nextCodepoint()) |scalar| {
            total += 1;
            ascii += @intFromBool(scalar < 0x80);
        }
    }
    return .{ .total = total, .ascii = ascii };
}
/// Draw 60 values of every test type and flatten each through the wire
/// codec, which rejects any value that does not fit its checked type.
fn encodedEverything(arena: std.mem.Allocator) !usize {
    const all = try testTypes(arena);
    const schema = try types.Schema.init(arena, all);
    var encoded: usize = 0;
    for (test_names) |name| for (0..60) |run| {
        var generator: Generator = .{ .arena = arena, .schema = schema, .stream = .init(3, run), .size = sizeOf(run, 60) };
        const value = try generator.value(name, 0);
        var codec: @import("native_test_wire.zig").Codec = .{ .allocator = arena, .types = all };
        try codec.encode(name, value, 0);
        const back = try codec.decode(name, 0);
        try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(arena, value, .{}), try std.json.Stringify.valueAlloc(arena, back, .{}));
        encoded += 1;
    };
    return encoded;
}

// spec: PROPERTY-TEST-1
test "property inputs are a pure function of the seed and the run, and sizes grow across the runs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings(try drawn(a, "List<str>", 42, 60), try drawn(a, "List<str>", 42, 60));
    try std.testing.expect(!std.mem.eql(u8, try drawn(a, "List<str>", 42, 60), try drawn(a, "List<str>", 42, 61)));
    try std.testing.expect(!std.mem.eql(u8, try drawn(a, "List<str>", 42, 60), try drawn(a, "List<str>", 43, 60)));
    try std.testing.expectEqualStrings("[]", try drawn(a, "List<i64>", 42, 0));
    try std.testing.expectEqual(@as(usize, 0), sizeOf(0, 100));
    try std.testing.expectEqual(@as(usize, 50), sizeOf(50, 101));
    try std.testing.expectEqual(@as(usize, max_size), sizeOf(99, 100));
    try std.testing.expectEqual(@as(usize, 0), sizeOf(100, 100));
    try std.testing.expectEqual(@as(usize, max_size), sizeOf(0, 1));
}

// spec-case: PROPERTY-TEST-1
test "property integers lean on their edges and never leave their width" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const wide = try spread(arena.allocator(), "i64");
    try std.testing.expect(wide.edges >= 60);
    try std.testing.expect(wide.minimum and wide.maximum);
    try std.testing.expectEqual(@as(usize, 0), wide.outside);
    const narrow = try spread(arena.allocator(), "u8");
    try std.testing.expect(narrow.minimum and narrow.maximum);
    try std.testing.expectEqual(@as(usize, 0), narrow.outside);
}

// spec-case: PROPERTY-TEST-1
test "property strings are mostly ASCII with some non-ASCII scalars" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const counted = try scalars(arena.allocator());
    try std.testing.expect(counted.total > 1000);
    try std.testing.expect(counted.ascii * 10 >= counted.total * 7);
    try std.testing.expect(counted.ascii < counted.total);
}

// spec-case: PROPERTY-TEST-1
test "property values of every shape cross the codec and come back unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(test_names.len * 60, try encodedEverything(arena.allocator()));
    try std.testing.expectEqualStrings("-0.0", try floatText(arena.allocator(), -0.0));
    try std.testing.expectEqualStrings("5.0e-324", try floatText(arena.allocator(), std.math.floatTrueMin(f64)));
    try std.testing.expectEqualStrings("1.7976931348623157e308", try floatText(arena.allocator(), std.math.floatMax(f64)));
}
