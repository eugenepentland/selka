//! The shared number-grammar vectors, executed against the pinned parser.
//! `tests/qbe_text.py` reads the same table and runs every vector through both
//! backends, so the grammar, the VM and the native runtime move together.
const std = @import("std");
const number = @import("number_text.zig");

/// The one table this test and the native parity driver both read.
const table = @embedFile("number_grammar.txt");
/// Widest vector the table holds, in Unicode scalars.
const widest = 2048;

/// Every line of the shared table, split once at compile time so the test body
/// needs a single `for` and no other control flow.
const rows: []const []const u8 = lines: {
    @setEvalBranchQuota(100000);
    var found: []const []const u8 = &.{};
    var walk = std.mem.splitScalar(u8, table, '\n');
    while (walk.next()) |line| found = found ++ [_][]const u8{line};
    break :lines found;
};

/// One decoded vector: which intrinsic, the input scalars, and the expectation.
const Vector = struct { floating: bool, points: []const u32, outcome: []const u8 };

/// Check one table line, skipping comments and blank lines.
fn check(line: []const u8, buffer: []u32) !void {
    const vector = parse(line, buffer) orelse return;
    if (vector.floating) return checkFloating(vector);
    return checkInteger(vector);
}

fn checkInteger(vector: Vector) !void {
    const actual = number.integer(vector.points);
    if (std.mem.eql(u8, vector.outcome, "none")) return std.testing.expectEqual(@as(?i64, null), actual);
    const expected = try std.fmt.parseInt(i64, vector.outcome, 10);
    return std.testing.expectEqual(@as(?i64, expected), actual);
}

fn checkFloating(vector: Vector) !void {
    const actual = number.floating(vector.points);
    if (std.mem.eql(u8, vector.outcome, "none")) return std.testing.expectEqual(@as(?f64, null), actual);
    try std.testing.expect(actual != null);
    if (std.mem.eql(u8, vector.outcome, "nan")) return std.testing.expect(std.math.isNan(actual.?));
    const expected = try std.fmt.parseFloat(f64, vector.outcome);
    return std.testing.expectEqual(@as(u64, @bitCast(expected)), @as(u64, @bitCast(actual.?)));
}

/// Split one vector line into its kind, decoded input and expected outcome.
fn parse(line: []const u8, buffer: []u32) ?Vector {
    if (line.len == 0) return null;
    if (line[0] == '#') return null;
    var fields = std.mem.splitScalar(u8, line, '|');
    const kind = fields.next() orelse return null;
    const input = fields.next() orelse return null;
    const outcome = fields.next() orelse return null;
    return .{ .floating = std.mem.eql(u8, kind, "float"), .points = decode(input, buffer), .outcome = outcome };
}

/// Expand the table's escapes into the scalar sequence the parser receives.
fn decode(input: []const u8, buffer: []u32) []const u32 {
    var count: usize = 0;
    var at: usize = 0;
    while (at < input.len) {
        if (input[at] != '\\') {
            buffer[count] = input[at];
            count += 1;
            at += 1;
            continue;
        }
        if (input[at + 1] == 'u') {
            buffer[count] = std.fmt.parseInt(u32, input[at + 2 ..][0..4], 16) catch 0;
            count += 1;
            at += 6;
            continue;
        }
        buffer[count] = escaped(input[at + 1]);
        count += 1;
        at += 2;
    }
    return buffer[0..count];
}

fn escaped(marker: u8) u32 {
    return switch (marker) {
        's' => ' ',
        't' => '\t',
        'n' => '\n',
        'r' => '\r',
        'v' => 0x0b,
        'f' => 0x0c,
        else => '\\',
    };
}

// spec: PY-NUM-1
test "every shared vector answers the pinned grammar's value" {
    var buffer: [widest]u32 = undefined;
    for (rows) |line| try check(line, &buffer);
    try std.testing.expect(rows.len > 100);
}

// spec: PY-NUM-2
test "the grammar keeps the rounding horizon, the signed bound and the exponent bound" {
    var wide: [widest]u32 = undefined;
    const digits = repeated(&wide, '7', 900);
    try std.testing.expectEqual(@as(?f64, std.math.inf(f64)), number.floating(digits));
    try std.testing.expectEqual(@as(?i64, null), number.integer(digits));
    try std.testing.expectEqual(@as(?i64, std.math.minInt(i64)), number.integer(&.{ '-', '9', '2', '2', '3', '3', '7', '2', '0', '3', '6', '8', '5', '4', '7', '7', '5', '8', '0', '8' }));
    try std.testing.expectEqual(@as(?f64, 0), number.floating(&.{ '1', 'e', '-', '9', '9', '9', '9', '9', '9', '9', '9', '9', '9', '9', '9', '9', '9', '9', '9', '9', '9', '9', '9', '9' }));
}

fn repeated(buffer: []u32, point: u32, count: usize) []const u32 {
    @memset(buffer[0..count], point);
    return buffer[0..count];
}
