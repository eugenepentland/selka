//! The pinned base-10 acceptance grammar behind `int(text)` and `float(text)`.
//!
//! One implementation answers for both backends: the VM calls it directly and the
//! native runtime reaches it through `native_format.zig`'s C export, so the two
//! can never disagree about which text is a number or which binary64 it names.
//! Input is a Unicode scalar sequence, exactly how both runtimes already hold a
//! `str`, and nothing here allocates.
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
    const body = trimmed(points);
    var at: usize = 0;
    const negative = signed(body, &at);
    const found = run(body, &at) orelse return null;
    if (at != body.len) return null;
    var magnitude: u64 = 0;
    for (body[found.start..found.end]) |point| {
        if (point == '_') continue;
        magnitude = std.math.mul(u64, magnitude, 10) catch return null;
        magnitude = std.math.add(u64, magnitude, point - '0') catch return null;
    }
    const bound: u64 = @as(u64, std.math.maxInt(i64)) + @intFromBool(negative);
    if (magnitude > bound) return null;
    if (!negative) return @intCast(magnitude);
    if (magnitude == bound) return std.math.minInt(i64);
    return -@as(i64, @intCast(magnitude));
}

/// Parse the whole text as one binary64 value, answering null when it is not
/// exactly one number. Overflow answers an infinity and underflow a zero, as
/// the correctly rounded decimal-to-binary conversion does.
pub fn floating(points: []const u32) ?f64 {
    const body = trimmed(points);
    var at: usize = 0;
    const negative = signed(body, &at);
    if (named(body[at..])) |value| return if (negative) -value else value;
    var buffer: [canonical_bytes]u8 = undefined;
    const rendered = canonical(body, &at, &buffer) orelse return null;
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
    fn take(self: *Mantissa, body: []const u32, found: Digits) void {
        for (body[found.start..found.end]) |point| {
            if (point == '_') continue;
            if (!self.significant and point == '0') continue;
            self.significant = true;
            if (self.length < kept) {
                self.buffer[self.length] = @intCast(point);
                self.length += 1;
                continue;
            }
            self.shift = bounded(self.shift, 1);
            self.sticky = self.sticky or point != '0';
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
fn trimmed(points: []const u32) []const u32 {
    var lower: usize = 0;
    var upper: usize = points.len;
    while (lower < upper and blank(points[lower])) lower += 1;
    while (upper > lower and blank(points[upper - 1])) upper -= 1;
    return points[lower..upper];
}

fn blank(point: u32) bool {
    return std.mem.indexOfScalar(u32, &blanks, point) != null;
}

fn decimal(point: u32) bool {
    return point >= '0' and point <= '9';
}

/// Consume an optional sign, reporting whether the value is negative.
fn signed(points: []const u32, at: *usize) bool {
    if (at.* == points.len) return false;
    const point = points[at.*];
    if (point != '+' and point != '-') return false;
    at.* += 1;
    return point == '-';
}

/// Measure `digit ( '_' digit )*`, stopping before a separator that is not
/// between two digits so the caller's whole-text check rejects it.
fn run(points: []const u32, at: *usize) ?Digits {
    if (at.* == points.len or !decimal(points[at.*])) return null;
    const start = at.*;
    var count: usize = 0;
    while (at.* < points.len) {
        if (decimal(points[at.*])) {
            count += 1;
            at.* += 1;
            continue;
        }
        if (points[at.*] != '_') break;
        if (at.* + 1 == points.len or !decimal(points[at.* + 1])) break;
        at.* += 1;
    }
    return .{ .start = start, .end = at.*, .count = count };
}

/// Recognize the case-insensitive spellings that name no finite value.
fn named(points: []const u32) ?f64 {
    if (word(points, "inf") or word(points, "infinity")) return std.math.inf(f64);
    if (word(points, "nan")) return std.math.nan(f64);
    return null;
}

fn word(points: []const u32, spelling: []const u8) bool {
    if (points.len != spelling.len) return false;
    for (points, spelling) |point, letter| {
        if (point > 127) return false;
        if (std.ascii.toLower(@intCast(point)) != letter) return false;
    }
    return true;
}

/// Build the canonical `<digits>e<exponent>` form of a decimal mantissa.
fn canonical(body: []const u32, at: *usize, buffer: []u8) ?[]const u8 {
    var mantissa: Mantissa = .{ .buffer = buffer };
    const whole = run(body, at);
    if (whole) |found| mantissa.take(body, found);
    var fraction: usize = 0;
    if (at.* < body.len and body[at.*] == '.') {
        at.* += 1;
        if (run(body, at)) |found| {
            mantissa.take(body, found);
            fraction = found.count;
        }
    }
    if (whole == null and fraction == 0) return null;
    var exponent: i64 = 0;
    if (at.* < body.len and (body[at.*] == 'e' or body[at.*] == 'E')) {
        at.* += 1;
        const negative = signed(body, at);
        const found = run(body, at) orelse return null;
        exponent = tens(body, found, negative);
    }
    return mantissa.render(bounded(exponent, -@as(i64, @intCast(fraction))));
}

/// Read an explicit exponent, saturating rather than wrapping on absurd input.
fn tens(body: []const u32, found: Digits, negative: bool) i64 {
    var value: i64 = 0;
    for (body[found.start..found.end]) |point| {
        if (point == '_') continue;
        value = std.math.mul(i64, value, 10) catch return saturated(negative);
        value = std.math.add(i64, value, point - '0') catch return saturated(negative);
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
