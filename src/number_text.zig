//! The pinned base-10 acceptance grammar behind `int(text)` and `float(text)`.
//!
//! One implementation answers for both backends: the VM calls it directly and the
//! native runtime reaches it through `native_format.zig`'s C export, so the two
//! can never disagree about which text is a number or which binary64 it names.
//! Input is a Unicode scalar sequence, exactly how both runtimes already hold a
//! `str`, and the same grammar reads the UTF-8 octets of a byte string directly:
//! every character it accepts is ASCII, so a byte at or above 0x80 is exactly the
//! non-ASCII scalar the scalar form rejects. Nothing here allocates.
const std = @import("std");

/// Significant digits a float keeps before one sticky digit stands in for the
/// rest. Every exact binary64 halfway value has fewer significant decimal
/// digits than this, so nothing past the horizon can change the rounding.
const kept = 768;
/// Room for the kept digits, the sticky digit and an `e<exponent>` suffix.
const canonical_bytes = kept + 32;
/// ASCII whitespace stripped from both ends, matching `isspace`.
const blanks = [_]u32{ ' ', '\t', '\n', '\r', 0x0b, 0x0c };

/// Parse the whole text as one decimal integer, answering null when it is not
/// exactly one number or when the value leaves the signed 64-bit range.
pub fn integer(points: []const u32) ?i64 {
    return integerOf(u32, points);
}

/// Parse the whole byte string as one decimal integer, which is the same
/// grammar read one octet at a time and never decodes a temporary `str`.
pub fn integerBytes(bytes: []const u8) ?i64 {
    return integerOf(u8, bytes);
}

/// Parse the whole text as one binary64 value, answering null when it is not
/// exactly one number. Overflow answers an infinity and underflow a zero, as
/// the correctly rounded decimal-to-binary conversion does.
pub fn floating(points: []const u32) ?f64 {
    return floatingOf(u32, points);
}

/// Parse the whole byte string as one binary64 value, never decoding it.
pub fn floatingBytes(bytes: []const u8) ?f64 {
    return floatingOf(u8, bytes);
}

fn integerOf(comptime Point: type, points: []const Point) ?i64 {
    const body = trimmed(Point, points);
    var at: usize = 0;
    const negative = signed(Point, body, &at);
    if (at == body.len) return null;
    const bound: u64 = @as(u64, std.math.maxInt(i64)) + @intFromBool(negative);
    var magnitude: u64 = 0;
    while (at < body.len) {
        const character = @as(u32, body[at]);
        if (!decimal(character)) return null;
        const digit = character - '0';
        // Validate and accumulate in one pass. The last allowed digit differs
        // only for the signed minimum; the guard proves the following multiply
        // and add cannot overflow even in checked builds.
        if (magnitude > bound / 10 or (magnitude == bound / 10 and digit > bound % 10)) return null;
        magnitude = magnitude * 10 + digit;
        at += 1;
        if (at < body.len and @as(u32, body[at]) == '_') {
            at += 1;
            if (at == body.len) return null;
        }
    }
    if (!negative) return @intCast(magnitude);
    if (magnitude == bound) return std.math.minInt(i64);
    return -@as(i64, @intCast(magnitude));
}

fn floatingOf(comptime Point: type, points: []const Point) ?f64 {
    const body = trimmed(Point, points);
    var at: usize = 0;
    const negative = signed(Point, body, &at);
    if (named(Point, body[at..])) |value| return if (negative) -value else value;
    var buffer: [canonical_bytes]u8 = undefined;
    const rendered = canonical(Point, body, &at, &buffer) orelse return null;
    if (at != body.len) return null;
    const magnitude = std.fmt.parseFloat(f64, rendered) catch return null;
    return if (negative) -magnitude else magnitude;
}

/// One validated `digit ( '_' digit )*` run inside the trimmed text.
const Digits = struct { start: usize, end: usize, count: usize };

/// Significant digits collected for one float, with the decimal shift and sticky
/// digit that stand in for everything past the rounding horizon.
const Mantissa = struct {
    buffer: []u8,
    length: usize = 0,
    shift: i64 = 0,
    significant: bool = false,
    sticky: bool = false,

    /// Append one digit run, dropping leading zeros and folding overflow digits
    /// into the decimal shift and the sticky flag.
    fn take(self: *Mantissa, comptime Point: type, body: []const Point, found: Digits) void {
        for (body[found.start..found.end]) |stored| {
            const character = @as(u32, stored);
            if (character == '_') continue;
            if (!self.significant and character == '0') continue;
            self.significant = true;
            if (self.length < kept) {
                self.buffer[self.length] = @intCast(character);
                self.length += 1;
                continue;
            }
            self.shift = bounded(self.shift, 1);
            self.sticky = self.sticky or character != '0';
        }
    }

    /// Render `<digits>e<exponent>` for the correctly rounded decimal parser.
    fn render(self: *Mantissa, exponent: i64) ?[]const u8 {
        var shift = self.shift;
        if (self.sticky) {
            self.buffer[self.length] = '1';
            self.length += 1;
            shift = bounded(shift, -1);
        }
        if (self.length == 0) {
            self.buffer[0] = '0';
            self.length = 1;
        }
        const rest = std.fmt.bufPrint(self.buffer[self.length..], "e{d}", .{bounded(exponent, shift)}) catch return null;
        return self.buffer[0 .. self.length + rest.len];
    }
};

/// Strip ASCII whitespace from both ends, leaving the candidate number itself.
fn trimmed(comptime Point: type, points: []const Point) []const Point {
    var lower: usize = 0;
    var upper: usize = points.len;
    while (lower < upper and blank(@as(u32, points[lower]))) lower += 1;
    while (upper > lower and blank(@as(u32, points[upper - 1]))) upper -= 1;
    return points[lower..upper];
}

fn blank(point: u32) bool {
    return std.mem.indexOfScalar(u32, &blanks, point) != null;
}

fn decimal(point: u32) bool {
    return point >= '0' and point <= '9';
}

/// Consume an optional sign, reporting whether the value is negative.
fn signed(comptime Point: type, points: []const Point, at: *usize) bool {
    if (at.* == points.len) return false;
    const point = @as(u32, points[at.*]);
    if (point != '+' and point != '-') return false;
    at.* += 1;
    return point == '-';
}

/// Measure `digit ( '_' digit )*`, stopping before a separator that is not
/// between two digits so the caller's whole-text check rejects it.
fn run(comptime Point: type, points: []const Point, at: *usize) ?Digits {
    if (at.* == points.len or !decimal(@as(u32, points[at.*]))) return null;
    const start = at.*;
    var count: usize = 0;
    while (at.* < points.len) {
        if (decimal(@as(u32, points[at.*]))) {
            count += 1;
            at.* += 1;
            continue;
        }
        if (@as(u32, points[at.*]) != '_') break;
        if (at.* + 1 == points.len or !decimal(@as(u32, points[at.* + 1]))) break;
        at.* += 1;
    }
    return .{ .start = start, .end = at.*, .count = count };
}

/// Recognize the case-insensitive spellings that name no finite value.
fn named(comptime Point: type, points: []const Point) ?f64 {
    if (word(Point, points, "inf") or word(Point, points, "infinity")) return std.math.inf(f64);
    if (word(Point, points, "nan")) return std.math.nan(f64);
    return null;
}

fn word(comptime Point: type, points: []const Point, spelling: []const u8) bool {
    if (points.len != spelling.len) return false;
    for (points, spelling) |stored, letter| {
        const point = @as(u32, stored);
        if (point > 127) return false;
        if (std.ascii.toLower(@intCast(point)) != letter) return false;
    }
    return true;
}

/// Build the canonical `<digits>e<exponent>` form of a decimal mantissa.
fn canonical(comptime Point: type, body: []const Point, at: *usize, buffer: []u8) ?[]const u8 {
    var mantissa: Mantissa = .{ .buffer = buffer };
    const whole = run(Point, body, at);
    if (whole) |found| mantissa.take(Point, body, found);
    var fraction: usize = 0;
    if (at.* < body.len and @as(u32, body[at.*]) == '.') {
        at.* += 1;
        if (run(Point, body, at)) |found| {
            mantissa.take(Point, body, found);
            fraction = found.count;
        }
    }
    if (whole == null and fraction == 0) return null;
    var exponent: i64 = 0;
    if (at.* < body.len and (@as(u32, body[at.*]) == 'e' or @as(u32, body[at.*]) == 'E')) {
        at.* += 1;
        const negative = signed(Point, body, at);
        const found = run(Point, body, at) orelse return null;
        exponent = tens(Point, body, found, negative);
    }
    return mantissa.render(bounded(exponent, -@as(i64, @intCast(fraction))));
}

/// Read an explicit exponent, saturating rather than wrapping on absurd input.
fn tens(comptime Point: type, body: []const Point, found: Digits, negative: bool) i64 {
    var value: i64 = 0;
    for (body[found.start..found.end]) |stored| {
        const character = @as(u32, stored);
        if (character == '_') continue;
        value = std.math.mul(i64, value, 10) catch return saturated(negative);
        value = std.math.add(i64, value, character - '0') catch return saturated(negative);
    }
    return if (negative) -value else value;
}

fn saturated(negative: bool) i64 {
    return if (negative) std.math.minInt(i64) else std.math.maxInt(i64);
}

/// Add two decimal exponents, saturating at the signed 64-bit ends.
fn bounded(left: i64, right: i64) i64 {
    return std.math.add(i64, left, right) catch saturated(right < 0);
}
