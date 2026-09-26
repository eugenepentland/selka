//! Shrinking candidates for property counterexamples (PROPERTY-TEST-3). Each
//! function lists values of one type that are simpler than a given value,
//! simplest first, so a greedy search that keeps the first still-failing
//! candidate walks toward a minimal counterexample: integers toward 0,
//! collections by dropping elements then shrinking the ones left, records
//! field by field, variants toward earlier cases, `Option` toward `None`.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const types = @import("property_types.zig");
const generate = @import("property_generate.zig");
const Value = std.json.Value;
/// Shrinking failures: allocation, or a value that does not fit its type.
pub const Error = generate.Error;

/// Candidate collection for one value, bounded so a huge value cannot build
/// an unbounded list of alternatives.
pub const Candidates = struct {
    arena: std.mem.Allocator,
    schema: types.Schema,
    items: std.ArrayList(Value) = .empty,
    /// Alternatives one value may contribute before the rest are left out;
    /// an integer alone lists at most 66, so a nested one keeps all of them.
    limit: usize = 1024,

    fn add(self: *Candidates, item: Value) Error!void {
        if (self.items.items.len < self.limit) try self.items.append(self.arena, item);
    }
    /// List the simpler alternatives of `value`, a value of type `name`.
    pub fn of(self: *Candidates, name: []const u8, value: Value) Error!void {
        switch (try self.schema.shape(name)) {
            .integer => |range| try self.integer(range, try number(value)),
            .atom => |kind| switch (kind) {
                .boolean => if (value == .bool and value.bool) try self.add(.{ .bool = false }),
                .float => try self.float(value),
                .text => try self.text(value),
                .bytes => try self.sequence("u8", value, false),
            },
            .sequence => |shape| if (shape.length != null) try self.elements(shape.element, value) else try self.sequence(shape.element, value, shape.distinct),
            .keyed => |pair| if (pair.table) try self.fields(value, pair.value, null) else try self.dict(pair, value),
            .record => |declared| try self.fields(value, "", declared),
            .cases => |cases| if (cases.payloads) try self.variant(name, cases.cases, value) else try self.enumeration(cases.cases, value),
            .refused => return error.UnsupportedTestType,
        }
    }
    /// 0 first, then the positive of a negative value, then the values that
    /// halve the remaining distance to the original: 0, v/2, 3v/4, ... v∓1.
    fn integer(self: *Candidates, range: types.Integer, current: i128) Error!void {
        if (current == 0) return;
        try self.add(try decimal(self.arena, 0));
        if (current < 0 and -current <= range.maximum) try self.add(try decimal(self.arena, -current));
        var distance = @divTrunc(current, 2);
        while (distance != 0) : (distance = @divTrunc(distance, 2)) {
            try self.add(try decimal(self.arena, current - distance));
        }
    }
    /// A float shrinks to `0.0`, to its positive, to its whole part, then
    /// toward zero by dividing out halves of its binary exponent (so a huge
    /// magnitude falls in a few steps), and by the integer halving series on
    /// its whole part while that is exact.
    fn float(self: *Candidates, value: Value) Error!void {
        const current = std.fmt.parseFloat(f64, v.text(value)) catch return error.UnsupportedTestType;
        if (current == 0 and !std.math.signbit(current)) return;
        try self.add(.{ .string = "0.0" });
        if (!std.math.isFinite(current)) return self.add(.{ .string = "1.0" });
        if (current < 0) try self.add(.{ .string = try generate.floatText(self.arena, -current) });
        const whole = @trunc(current);
        if (whole != current) try self.add(.{ .string = try generate.floatText(self.arena, whole) });
        if (@abs(current) < 2) return;
        var shift: i32 = @divTrunc(std.math.frexp(current).exponent, 2);
        while (shift >= 1) : (shift = @divTrunc(shift, 2)) {
            try self.add(.{ .string = try generate.floatText(self.arena, @trunc(std.math.ldexp(current, -shift))) });
        }
        if (@abs(whole) > 9007199254740992.0) return;
        var distance = @trunc(whole / 2);
        while (distance != 0) : (distance = @trunc(distance / 2)) {
            try self.add(.{ .string = try generate.floatText(self.arena, whole - distance) });
        }
    }
    /// A string shrinks like a list of scalars: shorter first, then each
    /// scalar toward `a`.
    fn text(self: *Candidates, value: Value) Error!void {
        const scalars = try decodeText(self.arena, v.text(value));
        var removals: std.ArrayList([]const u21) = .empty;
        try removed(u21, self.arena, scalars, &removals);
        for (removals.items) |kept| try self.add(.{ .string = try encodeText(self.arena, kept) });
        for (scalars, 0..) |scalar, index| {
            if (scalar == 'a') continue;
            const changed = try self.arena.dupe(u21, scalars);
            changed[index] = 'a';
            try self.add(.{ .string = try encodeText(self.arena, changed) });
        }
    }
    /// A list shrinks by dropping elements, then (for integers) by moving
    /// one element's value into its neighbour so the next pass can drop it,
    /// then by shrinking each element in place. A set's elements shrink in
    /// place too, except into a value another element already has.
    fn sequence(self: *Candidates, element: []const u8, value: Value, distinct: bool) Error!void {
        if (value != .array) return error.UnsupportedTestType;
        const items = value.array.items;
        var removals: std.ArrayList([]const Value) = .empty;
        try removed(Value, self.arena, items, &removals);
        for (removals.items) |kept| try self.add(try arrayOf(self.arena, kept));
        if (!distinct and (try self.schema.shape(element)) == .integer) try self.merged(element, items);
        const alternatives = try self.arena.alloc([]const Value, items.len);
        for (items, alternatives) |item, *slot| slot.* = try self.alone(element, item);
        try self.interleave(items, alternatives, if (distinct) .element else .none);
    }
    /// Integer lists: for each element, the list with it zeroed and its value
    /// added to its right neighbour, when that fits, so a removal pass can
    /// then drop the zero: `[12, 88]` becomes `[0, 100]`, then `[100]`.
    fn merged(self: *Candidates, element: []const u8, items: []const Value) Error!void {
        const range = (try self.schema.shape(element)).integer;
        if (items.len < 2) return;
        for (items[0 .. items.len - 1], 0..) |item, first| {
            const moved = try number(item);
            const total = try number(items[first + 1]) + moved;
            if (moved == 0 or total < range.minimum or total > range.maximum) continue;
            const changed = try self.arena.dupe(Value, items);
            changed[first] = try decimal(self.arena, 0);
            changed[first + 1] = try decimal(self.arena, total);
            try self.add(try arrayOf(self.arena, changed));
        }
    }
    /// Each element of a fixed array shrunk in place.
    fn elements(self: *Candidates, element: []const u8, value: Value) Error!void {
        if (value != .array) return error.UnsupportedTestType;
        const items = value.array.items;
        const alternatives = try self.arena.alloc([]const Value, items.len);
        for (items, alternatives) |item, *slot| slot.* = try self.alone(element, item);
        try self.interleave(items, alternatives, .none);
    }
    /// The simpler alternatives of one value on its own.
    fn alone(self: *Candidates, name: []const u8, value: Value) Error![]const Value {
        var inner: Candidates = .{ .arena = self.arena, .schema = self.schema, .limit = 128 };
        try inner.of(name, value);
        return inner.items.items;
    }
    /// Each slot shrunk in place, one slot at a time, breadth first: every
    /// slot's boldest alternative before any slot's next one, so a long
    /// collection reaches all of its slots within the candidate limit. A set
    /// (`element`) or a dictionary (`key`) skips an alternative whose element
    /// or key another slot already holds, so no candidate loses an entry.
    fn interleave(self: *Candidates, items: []const Value, alternatives: []const []const Value, distinct: Distinct) Error!void {
        const identities = try self.arena.alloc([]const u8, items.len);
        for (items, identities) |item, *identity| identity.* = try distinct.identity(self.arena, item);
        var deepest: usize = 0;
        for (alternatives) |choices| deepest = @max(deepest, choices.len);
        if (items.len > 1) for (0..deepest) |level| try self.together(items, alternatives, distinct, level);
        for (0..deepest) |level| for (alternatives, 0..) |choices, index| {
            if (level >= choices.len) continue;
            if (distinct != .none and try clashes(self.arena, distinct, choices[level], identities, index)) continue;
            const changed = try self.arena.dupe(Value, items);
            changed[index] = choices[level];
            try self.add(try arrayOf(self.arena, changed));
        };
    }
    /// Every slot at its `level`-th alternative at once (a slot with fewer
    /// keeps its value), so a collection whose slots all shrink alike — a set
    /// that must keep its size — takes one step instead of one per slot. A
    /// candidate that would repeat a set element or a dictionary key is left out.
    fn together(self: *Candidates, items: []const Value, alternatives: []const []const Value, distinct: Distinct, level: usize) Error!void {
        const changed = try self.arena.dupe(Value, items);
        for (alternatives, 0..) |choices, index| if (level < choices.len) {
            changed[index] = choices[level];
        };
        if (distinct != .none) {
            const spelled = try self.arena.alloc([]const u8, changed.len);
            for (changed, spelled) |item, *identity| identity.* = try distinct.identity(self.arena, item);
            if (repeats(spelled)) return;
        }
        try self.add(try arrayOf(self.arena, changed));
    }
    /// A dictionary drops entries, then shrinks each entry in place: its key
    /// (never into another entry's key) and then its value.
    fn dict(self: *Candidates, pair: types.Keyed, value: Value) Error!void {
        if (value != .array) return error.UnsupportedTestType;
        const items = value.array.items;
        var removals: std.ArrayList([]const Value) = .empty;
        try removed(Value, self.arena, items, &removals);
        for (removals.items) |kept| try self.add(try arrayOf(self.arena, kept));
        const alternatives = try self.arena.alloc([]const Value, items.len);
        for (items, alternatives) |entry, *slot| {
            const key = entry.array.items[0];
            const item = entry.array.items[1];
            var entries: std.ArrayList(Value) = .empty;
            for (try self.alone(pair.key, key)) |simpler| try entries.append(self.arena, try arrayOf(self.arena, &.{ simpler, item }));
            for (try self.alone(pair.value, item)) |simpler| try entries.append(self.arena, try arrayOf(self.arena, &.{ key, simpler }));
            slot.* = entries.items;
        }
        try self.interleave(items, alternatives, .key);
    }
    /// A record or an enum-indexed table, one field at a time; a table's
    /// fields all have `element` type, a record's their declared ones.
    fn fields(self: *Candidates, value: Value, element: []const u8, declared: ?[]const types.Field) Error!void {
        if (value != .object) return error.UnsupportedTestType;
        for (value.object.keys(), 0..) |key, index| {
            const field_type = if (declared) |list| typeOf(list, key) orelse return error.UnsupportedTestType else element;
            var inner: Candidates = .{ .arena = self.arena, .schema = self.schema, .limit = 128 };
            try inner.of(field_type, value.object.values()[index]);
            for (inner.items.items) |simpler| {
                var changed = try value.object.clone(self.arena);
                try changed.put(self.arena, key, simpler);
                try self.add(.{ .object = changed });
            }
        }
    }
    fn enumeration(self: *Candidates, cases: []const Value, value: Value) Error!void {
        const current = caseIndex(cases, v.text(value)) orelse return error.UnsupportedTestType;
        for (cases[0..current]) |case| try self.add(v.get(case, "name"));
    }
    /// Every earlier case at its simplest, then the payload shrunk in place.
    fn variant(self: *Candidates, name: []const u8, cases: []const Value, value: Value) Error!void {
        const current = caseIndex(cases, v.text(v.get(value, "case"))) orelse return error.UnsupportedTestType;
        // RECURSIVE-VALUES-3: a recursive value shrinks toward its leaves: the
        // simplest leaf case first, then each value of its own type it holds.
        if (try types.recursiveCase(self.schema, name, cases, current)) {
            try self.add(try generate.minimal(self.arena, self.schema, cases, try types.baseCase(self.schema, name, cases), 0));
            try subtermsOf(self, name, v.text(v.get(cases[current], "payload")), v.get(value, "value"));
        }
        for (0..current) |index| {
            // An earlier case that holds another value of this union is a
            // bigger value, not a simpler one, so it is never a candidate.
            if (try types.recursiveCase(self.schema, name, cases, index)) continue;
            try self.add(try generate.minimal(self.arena, self.schema, cases, index, 0));
        }
        const payload = v.get(cases[current], "payload");
        if (payload != .string) return;
        var inner: Candidates = .{ .arena = self.arena, .schema = self.schema, .limit = 128 };
        try inner.of(payload.string, v.get(value, "value"));
        for (inner.items.items) |simpler| {
            var changed = try value.object.clone(self.arena);
            try changed.put(self.arena, "value", simpler);
            try self.add(.{ .object = changed });
        }
    }
};

/// A value's closest values of type `target`: walking `value`, a value of
/// type `name`, through fields, payloads and elements, each value of type
/// `target` met is a candidate, and the walk does not look inside it.
fn subtermsOf(self: *Candidates, target: []const u8, name: []const u8, value: Value) Error!void {
    if (std.mem.eql(u8, name, target)) return self.add(value);
    switch (try self.schema.shape(name)) {
        .record => |fields| for (fields) |field| try subtermsOf(self, target, field.type, v.get(value, field.name)),
        .cases => |cases| if (cases.payloads) {
            const index = caseIndex(cases.cases, v.text(v.get(value, "case"))) orelse return;
            const payload = v.get(cases.cases[index], "payload");
            if (payload == .string) try subtermsOf(self, target, payload.string, v.get(value, "value"));
        },
        .sequence => |sequence| if (value == .array) for (value.array.items) |item| try subtermsOf(self, target, sequence.element, item),
        else => {},
    }
}
/// What must stay distinct among a collection's slots: nothing (a list), the
/// elements themselves (a set), or the keys of `[key, value]` pairs.
const Distinct = enum {
    none,
    element,
    key,

    /// The spelling two slots are compared by.
    fn identity(self: Distinct, arena: std.mem.Allocator, item: Value) Error![]const u8 {
        return switch (self) {
            .none => "",
            .element => std.json.Stringify.valueAlloc(arena, item, .{}),
            .key => std.json.Stringify.valueAlloc(arena, item.array.items[0], .{}),
        };
    }
};
/// Whether two spellings in the list are equal.
fn repeats(spelled: []const []const u8) bool {
    for (spelled, 0..) |first, index| for (spelled[index + 1 ..]) |second| {
        if (std.mem.eql(u8, first, second)) return true;
    };
    return false;
}
/// Whether putting `candidate` in slot `index` would repeat another slot.
fn clashes(arena: std.mem.Allocator, distinct: Distinct, candidate: Value, identities: []const []const u8, index: usize) Error!bool {
    const spelled = try distinct.identity(arena, candidate);
    for (identities, 0..) |identity, other| {
        if (other != index and std.mem.eql(u8, identity, spelled)) return true;
    }
    return false;
}

/// Every shorter sequence that drops one contiguous run: the empty one, then
/// runs of half the length, a quarter, ... down to single elements.
fn removed(comptime T: type, allocator: std.mem.Allocator, items: []const T, out: *std.ArrayList([]const T)) Error!void {
    if (items.len == 0) return;
    try out.append(allocator, &.{});
    var run = items.len / 2;
    while (run != 0) : (run /= 2) {
        var start: usize = 0;
        while (start < items.len) : (start += run) {
            const end = @min(items.len, start + run);
            const kept = try std.mem.concat(allocator, T, &.{ items[0..start], items[end..] });
            try out.append(allocator, kept);
        }
    }
}
fn typeOf(fields: []const types.Field, name: []const u8) ?[]const u8 {
    for (fields) |field| if (std.mem.eql(u8, field.name, name)) return field.type;
    return null;
}
fn caseIndex(cases: []const Value, name: []const u8) ?usize {
    for (cases, 0..) |case, index| if (std.mem.eql(u8, v.text(v.get(case, "name")), name)) return index;
    return null;
}
fn arrayOf(allocator: std.mem.Allocator, items: []const Value) Error!Value {
    var array: std.json.Array = .init(allocator);
    try array.appendSlice(items);
    return .{ .array = array };
}
fn number(value: Value) Error!i128 {
    if (value != .string) return error.UnsupportedTestType;
    return std.fmt.parseInt(i128, value.string, 10) catch error.UnsupportedTestType;
}
fn decimal(allocator: std.mem.Allocator, value: i128) Error!Value {
    return .{ .string = try std.fmt.allocPrint(allocator, "{d}", .{value}) };
}
fn decodeText(allocator: std.mem.Allocator, text: []const u8) Error![]const u21 {
    var scalars: std.ArrayList(u21) = .empty;
    var view = std.unicode.Utf8View.init(text) catch return error.UnsupportedTestType;
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |scalar| try scalars.append(allocator, scalar);
    return scalars.items;
}
fn encodeText(allocator: std.mem.Allocator, scalars: []const u21) Error![]const u8 {
    var bytes: std.ArrayList(u8) = .empty;
    for (scalars) |scalar| {
        var encoded: [4]u8 = undefined;
        const width = std.unicode.utf8Encode(scalar, &encoded) catch return error.UnsupportedTestType;
        try bytes.appendSlice(allocator, encoded[0..width]);
    }
    return bytes.items;
}

fn testSchema(arena: std.mem.Allocator) !types.Schema {
    const parsed = try std.json.parseFromSliceLeaky(Value, arena, generate.test_schema, .{});
    return types.Schema.init(arena, v.array(v.get(parsed, "types")));
}
/// The candidates of one typed JSON value, each spelled as compact JSON.
fn listed(arena: std.mem.Allocator, name: []const u8, json: []const u8) ![]const []const u8 {
    var candidates: Candidates = .{ .arena = arena, .schema = try testSchema(arena) };
    try candidates.of(name, try std.json.parseFromSliceLeaky(Value, arena, json, .{}));
    const out = try arena.alloc([]const u8, candidates.items.items.len);
    for (out, candidates.items.items) |*slot, item| slot.* = try std.json.Stringify.valueAlloc(arena, item, .{});
    return out;
}
/// Shrink greedily and sequentially, as the runner does in batches: adopt
/// the first candidate for which `fails` still holds until none does.
fn greedy(arena: std.mem.Allocator, name: []const u8, json: []const u8, fails: *const fn (Value) bool) ![]const u8 {
    const schema = try testSchema(arena);
    var current = try std.json.parseFromSliceLeaky(Value, arena, json, .{});
    search: for (0..10_000) |_| {
        var candidates: Candidates = .{ .arena = arena, .schema = schema };
        try candidates.of(name, current);
        for (candidates.items.items) |candidate| if (fails(candidate)) {
            current = candidate;
            continue :search;
        };
        break;
    }
    return std.json.Stringify.valueAlloc(arena, current, .{});
}
fn sumReaches100(value: Value) bool {
    var total: i128 = 0;
    for (value.array.items) |item| total += std.fmt.parseInt(i128, item.string, 10) catch 0;
    return total >= 100;
}
fn holdsThree(value: Value) bool {
    return value.array.items.len >= 3;
}
/// Whether any listed set candidate holds one element twice.
fn anyRepeats(arena: std.mem.Allocator, candidates: []const []const u8) !bool {
    for (candidates) |candidate| {
        const parsed = try std.json.parseFromSliceLeaky(Value, arena, candidate, .{});
        const elements = try arena.alloc([]const u8, parsed.array.items.len);
        for (elements, parsed.array.items) |*slot, item| slot.* = item.string;
        if (repeats(elements)) return true;
    }
    return false;
}

// spec: PROPERTY-TEST-3
test "property integers shrink toward zero by halving the distance, and a sum shrinks to one element" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const halving = try listed(a, "i64", "\"100\"");
    try std.testing.expectEqualStrings("\"0\" \"50\" \"75\" \"88\" \"94\" \"97\" \"99\"", try std.mem.join(a, " ", halving));
    const negative = try listed(a, "i64", "\"-8\"");
    try std.testing.expectEqualStrings("\"0\" \"8\" \"-4\" \"-6\" \"-7\"", try std.mem.join(a, " ", negative));
    try std.testing.expectEqual(@as(usize, 0), (try listed(a, "i64", "\"0\"")).len);
    try std.testing.expectEqualStrings("[\"100\"]", try greedy(a, "List<i64>", "[\"57\",\"88\",\"-3\",\"12\"]", sumReaches100));
    try std.testing.expectEqualStrings("[\"0\",\"0\",\"0\"]", try greedy(a, "List<i64>", "[\"9\",\"-4\",\"77\",\"3\",\"5\"]", holdsThree));
}

// spec-case: PROPERTY-TEST-3
test "property variants shrink toward earlier cases and sets never repeat an element" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const option = try listed(a, "Option<i64>", "{\"case\":\"some\",\"value\":\"5\"}");
    try std.testing.expectEqualStrings("{\"case\":\"none\"}", option[0]);
    try std.testing.expectEqualStrings("{\"case\":\"some\",\"value\":\"0\"}", option[1]);
    const shape = try listed(a, "main::Shape", "{\"case\":\"empty\"}");
    try std.testing.expectEqualStrings("{\"case\":\"circle\",\"value\":\"0\"}", shape[0]);
    try std.testing.expectEqualStrings("{\"case\":\"square\",\"value\":{\"x\":\"0\",\"y\":\"0\"}}", shape[1]);
    try std.testing.expectEqualStrings("\"red\"", (try listed(a, "main::Color", "\"blue\""))[0]);
    try std.testing.expectEqualStrings("{\"x\":\"0\",\"y\":\"9\"}", (try listed(a, "main::Point", "{\"x\":\"4\",\"y\":\"9\"}"))[0]);
    const set = try listed(a, "set<i64>", "[\"0\",\"6\"]");
    try std.testing.expectEqualStrings("[]", set[0]);
    try std.testing.expect(set.len > 3);
    try std.testing.expect(!try anyRepeats(a, set));
    try std.testing.expectEqualStrings("\"\" \"yz\" \"xz\" \"xy\" \"ayz\" \"xaz\" \"xya\"", try std.mem.join(a, " ", try listed(a, "str", "\"xyz\"")));
}
