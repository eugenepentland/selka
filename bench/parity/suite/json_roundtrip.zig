// json_roundtrip: generate a compact JSON text of nested records, parse it into a
// recursive value union, walk the tree into a checksum, and serialize it back
// (SUITE.md section 12). Decimals are parsed with std.fmt.parseFloat and printed
// from their scaled integers.
const std = @import("std");
const common = @import("common.zig");
const common_c = @import("common_c.zig");

const Decimal = struct { scaled: i64, value: f64 };
const Member = struct { key: []const u8, value: Value };
const Value = union(enum) {
    null,
    boolean: bool,
    integer: i64,
    decimal: Decimal,
    string: []const u8,
    array: []Value,
    object: []Member,
};

const alpha = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
const lower = "abcdefghijklmnopqrstuvwxyz";

/// The shared checksum step: `(c * 31 + v) mod 1000000007`, for non-negative `v`.
fn mix(c: u64, v: u64) u64 {
    return (c * 31 + v) % 1000000007;
}

const Gen = struct {
    x: u64 = 88172645463325252,

    fn full(self: *Gen) u64 {
        var x = self.x;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.x = x;
        return x;
    }

    fn draw(self: *Gen) u64 {
        return self.full() >> 33;
    }

    fn pick(self: *Gen, n: u64) u64 {
        return self.draw() % n;
    }
};

/// Writes one signed decimal with exactly three fractional digits; no sign for zero.
fn genDecimal(gpa: std.mem.Allocator, gen: *Gen, text: *std.ArrayList(u8)) !void {
    const mag = gen.pick(2000000);
    const sign = gen.pick(2);
    if (sign == 1 and mag > 0) try text.append(gpa, '-');
    try text.print(gpa, "{d}.{d:0>3}", .{ mag / 1000, mag % 1000 });
}

/// Writes one record at nesting depth `depth`, as SUITE.md section 12 describes.
fn genRecord(gpa: std.mem.Allocator, gen: *Gen, text: *std.ArrayList(u8), depth: u32) !void {
    try text.print(gpa, "{{\"id\":{d}", .{gen.draw()});
    const length = 4 + gen.pick(12);
    try text.appendSlice(gpa, ",\"name\":\"");
    for (0..length) |_| {
        const r = gen.pick(16);
        if (r == 0) {
            try text.appendSlice(gpa, "\\\"");
        } else if (r == 1) {
            try text.appendSlice(gpa, "\\\\");
        } else if (r == 2) {
            try text.appendSlice(gpa, "\\n");
        } else {
            try text.append(gpa, alpha[gen.pick(62)]);
        }
    }
    try text.append(gpa, '"');
    try text.appendSlice(gpa, ",\"pos\":[");
    try genDecimal(gpa, gen, text);
    try text.append(gpa, ',');
    try genDecimal(gpa, gen, text);
    try text.appendSlice(gpa, "],\"tags\":[");
    const tags = gen.pick(5);
    for (0..tags) |t| {
        if (t > 0) try text.append(gpa, ',');
        const letters = 1 + gen.pick(4);
        try text.append(gpa, '"');
        for (0..letters) |_| try text.append(gpa, lower[gen.pick(26)]);
        try text.append(gpa, '"');
    }
    try text.appendSlice(gpa, "],\"child\":");
    if (depth < 3 and gen.pick(3) != 0) {
        try genRecord(gpa, gen, text, depth + 1);
    } else {
        try text.appendSlice(gpa, "null");
    }
    try text.append(gpa, '}');
}

/// The parser's failures: allocation, the number grammar and the escape grammar.
const ParseError = std.mem.Allocator.Error || error{Malformed} || std.fmt.ParseIntError || std.fmt.ParseFloatError;

/// A recursive-descent parser over the generated text; every node lives in the arena.
const Parser = struct {
    arena: std.mem.Allocator,
    scratch: std.ArrayList(u8) = .empty,
    text: []const u8,
    pos: usize = 0,

    fn parseValue(self: *Parser) ParseError!Value {
        const c = self.text[self.pos];
        if (c == 'n') {
            self.pos += 4;
            return .null;
        }
        if (c == 't') {
            self.pos += 4;
            return .{ .boolean = true };
        }
        if (c == 'f') {
            self.pos += 5;
            return .{ .boolean = false };
        }
        if (c == '"') return .{ .string = try self.parseString() };
        if (c == '[') return self.parseArray();
        if (c == '{') return self.parseObject();
        return self.parseNumber();
    }

    fn parseString(self: *Parser) ParseError![]const u8 {
        self.pos += 1;
        self.scratch.clearRetainingCapacity();
        while (self.text[self.pos] != '"') {
            if (self.text[self.pos] == '\\') {
                self.pos += 1;
                const escaped: u8 = switch (self.text[self.pos]) {
                    'n' => '\n',
                    '"' => '"',
                    '\\' => '\\',
                    else => return error.Malformed,
                };
                try self.scratch.append(self.arena, escaped);
            } else {
                try self.scratch.append(self.arena, self.text[self.pos]);
            }
            self.pos += 1;
        }
        self.pos += 1;
        return self.arena.dupe(u8, self.scratch.items);
    }

    fn parseNumber(self: *Parser) ParseError!Value {
        const start = self.pos;
        var has_dot = false;
        while (self.pos < self.text.len) : (self.pos += 1) {
            const c = self.text[self.pos];
            if (c == '.') {
                has_dot = true;
            } else if (c != '-' and (c < '0' or c > '9')) {
                break;
            }
        }
        const token = self.text[start..self.pos];
        if (!has_dot) return .{ .integer = try std.fmt.parseInt(i64, token, 10) };
        const value = try std.fmt.parseFloat(f64, token);
        const negative = token[0] == '-';
        const digits = if (negative) token[1..] else token;
        const dot = std.mem.indexOfScalar(u8, digits, '.') orelse return error.Malformed;
        const whole = try std.fmt.parseInt(i64, digits[0..dot], 10);
        const frac = try std.fmt.parseInt(i64, digits[dot + 1 ..][0..3], 10);
        const magnitude = whole * 1000 + frac;
        return .{ .decimal = .{ .scaled = if (negative) -magnitude else magnitude, .value = value } };
    }

    fn parseArray(self: *Parser) ParseError!Value {
        self.pos += 1;
        var items: std.ArrayList(Value) = .empty;
        if (self.text[self.pos] == ']') {
            self.pos += 1;
            return .{ .array = try items.toOwnedSlice(self.arena) };
        }
        while (true) {
            try items.append(self.arena, try self.parseValue());
            if (self.text[self.pos] == ',') {
                self.pos += 1;
            } else {
                self.pos += 1;
                break;
            }
        }
        return .{ .array = try items.toOwnedSlice(self.arena) };
    }

    fn parseObject(self: *Parser) ParseError!Value {
        self.pos += 1;
        var members: std.ArrayList(Member) = .empty;
        if (self.text[self.pos] == '}') {
            self.pos += 1;
            return .{ .object = try members.toOwnedSlice(self.arena) };
        }
        while (true) {
            const key = try self.parseString();
            self.pos += 1;
            const value = try self.parseValue();
            try members.append(self.arena, .{ .key = key, .value = value });
            if (self.text[self.pos] == ',') {
                self.pos += 1;
            } else {
                self.pos += 1;
                break;
            }
        }
        return .{ .object = try members.toOwnedSlice(self.arena) };
    }
};

/// Folds one value into the walk checksum, in document order.
fn walk(value: Value, c: *u64) void {
    switch (value) {
        .null => c.* = mix(c.*, 1),
        .boolean => |b| c.* = mix(c.*, if (b) 3 else 2),
        .integer => |n| {
            c.* = mix(c.*, 4);
            c.* = mix(c.*, @abs(n));
        },
        .decimal => |d| {
            c.* = mix(c.*, 5);
            const scaled: i64 = @intFromFloat(d.value * 1e9);
            c.* = mix(c.*, @abs(scaled));
        },
        .string => |s| {
            c.* = mix(c.*, 6);
            c.* = mix(c.*, s.len);
        },
        .array => |items| {
            c.* = mix(c.*, 7);
            c.* = mix(c.*, items.len);
            for (items) |item| walk(item, c);
        },
        .object => |members| {
            c.* = mix(c.*, 8);
            c.* = mix(c.*, members.len);
            for (members) |member| {
                c.* = mix(c.*, member.key.len);
                walk(member.value, c);
            }
        },
    }
}

/// Appends the compact JSON form of `value` to `out`.
fn serialize(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: Value) !void {
    switch (value) {
        .null => try out.appendSlice(gpa, "null"),
        .boolean => |b| try out.appendSlice(gpa, if (b) "true" else "false"),
        .integer => |n| try out.print(gpa, "{d}", .{n}),
        .decimal => |d| {
            const magnitude = @abs(d.scaled);
            if (d.scaled < 0) try out.append(gpa, '-');
            try out.print(gpa, "{d}.{d:0>3}", .{ magnitude / 1000, magnitude % 1000 });
        },
        .string => |s| {
            try out.append(gpa, '"');
            for (s) |byte| switch (byte) {
                '"' => try out.appendSlice(gpa, "\\\""),
                '\\' => try out.appendSlice(gpa, "\\\\"),
                '\n' => try out.appendSlice(gpa, "\\n"),
                else => try out.append(gpa, byte),
            };
            try out.append(gpa, '"');
        },
        .array => |items| {
            try out.append(gpa, '[');
            for (items, 0..) |item, i| {
                if (i > 0) try out.append(gpa, ',');
                try serialize(gpa, out, item);
            }
            try out.append(gpa, ']');
        },
        .object => |members| {
            try out.append(gpa, '{');
            for (members, 0..) |member, i| {
                if (i > 0) try out.append(gpa, ',');
                try out.print(gpa, "\"{s}\":", .{member.key});
                try serialize(gpa, out, member.value);
            }
            try out.append(gpa, '}');
        },
    }
}

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    const records: usize = @intCast(common.opaqueN(120000));
    var gen: Gen = .{};
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    try text.append(gpa, '[');
    for (0..records) |r| {
        if (r > 0) try text.append(gpa, ',');
        try genRecord(gpa, &gen, &text, 0);
    }
    try text.append(gpa, ']');

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var parser: Parser = .{ .arena = arena.allocator(), .text = text.items };
    const root = try parser.parseValue();

    var walk_sum: u64 = 0;
    walk(root, &walk_sum);
    var serialized: std.ArrayList(u8) = .empty;
    defer serialized.deinit(gpa);
    try serialize(gpa, &serialized, root);
    var serialized_mix: u64 = 0;
    for (serialized.items) |byte| serialized_mix = mix(serialized_mix, byte);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.print(gpa, "records {d} text {d} walk {d}\n", .{ records, text.items.len, walk_sum });
    try out.print(gpa, "serialized {d} mix {d}\n", .{ serialized.items.len, serialized_mix });
    try out.appendSlice(gpa, if (std.mem.eql(u8, serialized.items, text.items)) "roundtrip ok\n" else "roundtrip mismatch\n");
    common_c.writeStdout(out.items);
}
