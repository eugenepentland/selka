//! S3 port of src/format_spec.zig: exact format-specification mini-language for
//! `f"{value:spec}"`, and the exact decimal rounding `round(x, n)` shares.
//!
//! The checker parses and validates a literal specification against the
//! value's family (`parse`, `resolve`) and hands the runtime one packed word
//! (`pack`); the runtime unpacks it and renders the value (`render`). Floats
//! are rendered from their *exact* binary value: every finite binary64 has a
//! finite decimal expansion, which `expand` computes with a small big-integer,
//! so rounding to any precision is exact. Formatting rounds ties to even, as
//! CPython's `_Py_dg_dtoa` does (`f"{0.125:.2f}"` is `0.12`, `f"{2.675:.2f}"`
//! is `2.67` because the binary value lies below the half); `round(x, n)`
//! rounds the same exact value with ties away from zero, the language's
//! declared `round` rule (`PRELUDE-ROUND-2`). `strings.format_float` also
//! rounds the exact value with ties away from zero, so it agrees with
//! `round(x, n)` and differs from a `.nf` specification only on exact ties.
//!
//! Layout follows CPython's `Python/formatter_unicode.c` and the digit layout
//! its `Python/pystrtod.c` `format_float_short`, including sign-aware zero
//! padding that extends grouped digits (`f"{1:08,}"` is `0,000,001`).
const std = @import("std");

/// Where padding goes: none resolves to the family's default.
pub const Align = enum(u3) { none, left, right, center, sign_aware };
/// The sign option: `-` (the default), `+` or a space.
pub const Sign = enum(u2) { minus, plus, space };
/// The thousands-separator option: none, `,` or `_`.
pub const Grouping = enum(u2) { none, comma, underscore };
/// The presentation type, `none` when the specification names none.
pub const Kind = enum(u4) { none, d, b, o, x, X, n, e, E, f, F, g, G, percent, s };
/// The value family a specification formats.
pub const Family = enum(u2) { signed, unsigned, float, text };

/// Fill character, alignment and minimum width in scalars (0 means none).
pub const Layout = struct { fill: u21 = ' ', alignment: Align = .none, width: u16 = 0 };
/// The number options that neither pad nor select the presentation.
pub const Flags = struct { sign: Sign = .minus, alternate: bool = false, no_negative_zero: bool = false, grouping: Grouping = .none };

/// One parsed specification. `resolve` fills the family's defaults in.
pub const Spec = struct {
    layout: Layout = .{},
    flags: Flags = .{},
    precision: ?u16 = null,
    kind: Kind = .none,
    family: Family = .text,
};

/// The widest width and precision a specification may name; the runtime
/// formats into bounded storage.
pub const limit: u16 = 4095;

/// Why a specification was rejected, with CPython's wording where it has one.
pub const Rejection = struct { message: []const u8 };

/// One specification as written, with the two facts the `0` option needs.
pub const Parsed = struct { spec: Spec, zero: bool, fill_given: bool, align_given: bool };

fn alignment(scalar: u21) ?Align {
    return switch (scalar) {
        '<' => .left,
        '>' => .right,
        '^' => .center,
        '=' => .sign_aware,
        else => null,
    };
}

fn kindOf(byte: u8) ?Kind {
    return switch (byte) {
        'd' => .d,
        'b' => .b,
        'o' => .o,
        'x' => .x,
        'X' => .X,
        'n' => .n,
        'e' => .e,
        'E' => .E,
        'f' => .f,
        'F' => .F,
        'g' => .g,
        'G' => .G,
        '%' => .percent,
        's' => .s,
        else => null,
    };
}

/// A decimal field of at most `limit`, null when absent.
fn field(text: []const u8, at: *usize) error{Invalid}!?u16 {
    const start = at.*;
    while (at.* < text.len and std.ascii.isDigit(text[at.*])) at.* += 1;
    if (at.* == start) return null;
    const value = std.fmt.parseInt(u32, text[start..at.*], 10) catch return error.Invalid;
    if (value > limit) return error.Invalid;
    return @intCast(value);
}

/// Parse `[[fill]align][sign][z][#][0][width][grouping][.precision][type]`.
pub fn parse(text: []const u8) union(enum) { ok: Parsed, rejected: Rejection } {
    var parsed: Parsed = .{ .spec = .{}, .zero = false, .fill_given = false, .align_given = false };
    var at: usize = 0;
    const view = std.unicode.Utf8View.init(text) catch return .{ .rejected = .{ .message = "a format specification must be valid UTF-8" } };
    var scalars = view.iterator();
    const first = scalars.nextCodepoint();
    const second_start = scalars.i;
    const second = scalars.nextCodepoint();
    if (first != null and second != null and alignment(second.?) != null) {
        parsed.spec.layout.fill = first.?;
        parsed.spec.layout.alignment = alignment(second.?).?;
        parsed.fill_given = true;
        parsed.align_given = true;
        at = scalars.i;
    } else if (first != null and alignment(first.?) != null) {
        parsed.spec.layout.alignment = alignment(first.?).?;
        parsed.align_given = true;
        at = second_start;
    }
    if (at < text.len and (text[at] == '+' or text[at] == '-' or text[at] == ' ')) {
        parsed.spec.flags.sign = switch (text[at]) {
            '+' => .plus,
            ' ' => .space,
            else => .minus,
        };
        at += 1;
    }
    if (at < text.len and text[at] == 'z') {
        parsed.spec.flags.no_negative_zero = true;
        at += 1;
    }
    if (at < text.len and text[at] == '#') {
        parsed.spec.flags.alternate = true;
        at += 1;
    }
    if (at < text.len and text[at] == '0') {
        parsed.zero = true;
        at += 1;
    }
    const width = field(text, &at) catch return .{ .rejected = .{ .message = "a format width must be at most 4095" } };
    parsed.spec.layout.width = width orelse 0;
    if (at < text.len and (text[at] == ',' or text[at] == '_')) {
        parsed.spec.flags.grouping = if (text[at] == ',') .comma else .underscore;
        at += 1;
        if (at < text.len and (text[at] == ',' or text[at] == '_')) return .{ .rejected = .{ .message = "Cannot specify both ',' and '_'." } };
    }
    if (at < text.len and text[at] == '.') {
        at += 1;
        const precision = field(text, &at) catch return .{ .rejected = .{ .message = "a format precision must be at most 4095" } };
        parsed.spec.precision = precision orelse return .{ .rejected = .{ .message = "Format specifier missing precision" } };
        if (at < text.len and (text[at] == ',' or text[at] == '_')) return .{ .rejected = .{ .message = "grouping the fractional digits (`.4,f`) is not supported; group the integer part with `,.4f`" } };
    }
    if (at + 1 < text.len) return .{ .rejected = .{ .message = "Invalid format specifier" } };
    if (at < text.len) {
        if (text[at] == '{' or text[at] == '}') return .{ .rejected = .{ .message = "a nested `{...}` inside a format specification is not supported; build the specification's value first" } };
        if (text[at] == 'c') return .{ .rejected = .{ .message = "the `c` presentation is not supported; use `chr(value)`" } };
        parsed.spec.kind = kindOf(text[at]) orelse return .{ .rejected = .{ .message = "Invalid format specifier" } };
    }
    return .{ .ok = parsed };
}

fn integerKind(kind: Kind) bool {
    return switch (kind) {
        .d, .b, .o, .x, .X, .n => true,
        else => false,
    };
}

fn floatKind(kind: Kind) bool {
    return switch (kind) {
        .e, .E, .f, .F, .g, .G, .percent, .none => true,
        else => false,
    };
}

/// Validate a parsed specification for one family and fill in its defaults:
/// the presentation type, the alignment, and the `0` option's fill.
pub fn resolve(parsed: Parsed, family: Family) union(enum) { ok: Spec, rejected: Rejection } {
    var spec = parsed.spec;
    spec.family = family;
    const text = family == .text;
    if (spec.kind == .none) spec.kind = switch (family) {
        .text => .s,
        .signed, .unsigned => .d,
        .float => .none,
    };
    if (spec.kind == .n) {
        if (spec.flags.grouping != .none) return .{ .rejected = .{ .message = "Cannot specify ',' with 'n'." } };
        spec.kind = if (family == .float) .g else .d;
    }
    if (text) {
        if (spec.kind != .s) return .{ .rejected = .{ .message = "Unknown format code for object of type 'str'" } };
        if (spec.flags.sign != .minus) return .{ .rejected = .{ .message = "Sign not allowed in string format specifier" } };
        if (spec.flags.no_negative_zero) return .{ .rejected = .{ .message = "Negative zero coercion (z) not allowed in format specifier" } };
        if (spec.flags.alternate) return .{ .rejected = .{ .message = "Alternate form (#) not allowed in string format specifier" } };
        if (spec.layout.alignment == .sign_aware) return .{ .rejected = .{ .message = "'=' alignment not allowed in string format specifier" } };
        if (spec.flags.grouping != .none) return .{ .rejected = .{ .message = "Cannot specify ',' with 's'." } };
    } else if (family == .float) {
        if (!floatKind(spec.kind)) return .{ .rejected = .{ .message = "Unknown format code for object of type 'float'" } };
    } else {
        if (spec.kind == .s) return .{ .rejected = .{ .message = "Unknown format code 's' for object of type 'int'" } };
        if (integerKind(spec.kind)) {
            if (spec.precision != null) return .{ .rejected = .{ .message = "Precision not allowed in integer format specifier" } };
            if (spec.flags.no_negative_zero) return .{ .rejected = .{ .message = "Negative zero coercion (z) not allowed in integer format specifier" } };
        }
    }
    const radix = spec.kind == .b or spec.kind == .o or spec.kind == .x or spec.kind == .X;
    if (radix and spec.flags.grouping == .comma) return .{ .rejected = .{ .message = "Cannot specify ',' with a binary, octal or hexadecimal type; use '_'" } };
    const default_align: Align = if (text) .left else .right;
    if (parsed.zero and !parsed.fill_given) {
        spec.layout.fill = '0';
        if (!parsed.align_given and default_align == .right) spec.layout.alignment = .sign_aware;
    }
    if (spec.layout.alignment == .none) spec.layout.alignment = default_align;
    return .{ .ok = spec };
}

/// Pack one resolved specification into the word the runtime receives.
pub fn pack(spec: Spec) u64 {
    var word: u64 = spec.layout.fill;
    word |= @as(u64, @backingInt(spec.layout.alignment)) << 21;
    word |= @as(u64, @backingInt(spec.flags.sign)) << 24;
    word |= @as(u64, @intFromBool(spec.flags.alternate)) << 26;
    word |= @as(u64, @intFromBool(spec.flags.no_negative_zero)) << 27;
    word |= @as(u64, @backingInt(spec.flags.grouping)) << 28;
    word |= @as(u64, @backingInt(spec.kind)) << 30;
    word |= @as(u64, @backingInt(spec.family)) << 34;
    if (spec.precision) |precision| word |= (@as(u64, 1) << 36) | (@as(u64, precision) << 37);
    word |= @as(u64, spec.layout.width) << 49;
    return word;
}

/// Recover a specification from `pack`'s word; null for a word no `pack` made.
pub fn unpack(word: u64) ?Spec {
    const fill: u21 = @truncate(word);
    const align_bits: u3 = @truncate(word >> 21);
    const sign_bits: u2 = @truncate(word >> 24);
    const grouping_bits: u2 = @truncate(word >> 28);
    const kind_bits: u4 = @truncate(word >> 30);
    const width: u16 = @truncate((word >> 49) & 0xfff);
    const precision: u16 = @truncate((word >> 37) & 0xfff);
    if (align_bits > @backingInt(Align.sign_aware) or sign_bits > @backingInt(Sign.space)) return null;
    if (grouping_bits > @backingInt(Grouping.underscore) or kind_bits > @backingInt(Kind.s)) return null;
    return .{
        .layout = .{ .fill = fill, .alignment = @fromBackingInt(@intCast(align_bits)), .width = width },
        .flags = .{
            .sign = @fromBackingInt(@intCast(sign_bits)),
            .alternate = (word >> 26) & 1 == 1,
            .no_negative_zero = (word >> 27) & 1 == 1,
            .grouping = @fromBackingInt(@intCast(grouping_bits)),
        },
        .precision = if ((word >> 36) & 1 == 1) precision else null,
        .kind = @fromBackingInt(@intCast(kind_bits)),
        .family = @fromBackingInt(@intCast(@as(u2, @truncate(word >> 34)))),
    };
}

/// A byte sink that only counts when it has no storage, so the same render
/// first measures the result and then writes it into storage of that size.
pub const Out = struct {
    buffer: []u8 = &.{},
    len: usize = 0,

    fn put(self: *Out, bytes: []const u8) void {
        if (self.buffer.len != 0) @memcpy(self.buffer[self.len..][0..bytes.len], bytes);
        self.len += bytes.len;
    }
    fn byte(self: *Out, value: u8) void {
        self.put(&.{value});
    }
    fn fill(self: *Out, scalar: u21, count: usize) void {
        var encoded: [4]u8 = undefined;
        const size = std.unicode.utf8Encode(scalar, &encoded) catch 1;
        for (0..count) |_| self.put(encoded[0..size]);
    }
};

/// One value to format: an integer, a float, or a text's UTF-8 and scalar count.
pub const Input = union(enum) { signed: i64, unsigned: u64, float: f64, text: struct { bytes: []const u8, scalars: usize } };

/// Render `input` under one resolved specification.
pub fn render(out: *Out, spec: Spec, input: Input) void {
    switch (input) {
        .text => |text| renderText(out, spec, text.bytes, text.scalars),
        .float => |value| renderFloat(out, spec, value),
        .signed => |value| if (floatKind(spec.kind)) renderFloat(out, spec, @floatFromInt(value)) else renderInteger(out, spec, value < 0, @abs(value)),
        .unsigned => |value| if (floatKind(spec.kind)) renderFloat(out, spec, @floatFromInt(value)) else renderInteger(out, spec, false, value),
    }
}

fn renderText(out: *Out, spec: Spec, bytes: []const u8, scalars: usize) void {
    var kept = bytes;
    var count = scalars;
    if (spec.precision) |precision| if (precision < scalars) {
        var end: usize = 0;
        var taken: usize = 0;
        while (taken < precision) : (taken += 1) end += std.unicode.utf8ByteSequenceLength(bytes[end]) catch 1;
        kept = bytes[0..end];
        count = precision;
    };
    const total = @max(count, spec.layout.width);
    const left: usize = switch (spec.layout.alignment) {
        .right => total - count,
        .center => (total - count) / 2,
        else => 0,
    };
    out.fill(spec.layout.fill, left);
    out.put(kept);
    out.fill(spec.layout.fill, total - count - left);
}

/// The parts of one number CPython lays out: sign, radix prefix, the digits
/// that grouping and zero padding extend, and the remainder after them.
const Number = struct { sign: ?u8, prefix: []const u8, digits: []const u8, remainder: []const u8, uppercase: bool };

fn renderInteger(out: *Out, spec: Spec, negative: bool, magnitude: u64) void {
    var storage: [64]u8 = undefined;
    const base: u8, const prefix: []const u8 = switch (spec.kind) {
        .b => .{ 2, "0b" },
        .o => .{ 8, "0o" },
        .x => .{ 16, "0x" },
        .X => .{ 16, "0X" },
        else => .{ 10, "" },
    };
    var at: usize = storage.len;
    var rest = magnitude;
    while (true) {
        at -= 1;
        storage[at] = "0123456789abcdef"[@intCast(rest % base)];
        rest /= base;
        if (rest == 0) break;
    }
    layOut(out, spec, .{
        .sign = if (negative) '-' else null,
        .prefix = if (spec.flags.alternate) prefix else "",
        .digits = storage[at..],
        .remainder = "",
        .uppercase = spec.kind == .X,
    });
}

/// Lay one number out as CPython's `calc_number_widths` and `fill_number` do.
fn layOut(out: *Out, spec: Spec, number: Number) void {
    const sign: ?u8 = switch (spec.flags.sign) {
        .plus => number.sign orelse '+',
        .space => number.sign orelse ' ',
        .minus => number.sign,
    };
    const fixed = @as(usize, @intFromBool(sign != null)) + number.prefix.len + number.remainder.len;
    const width: isize = spec.layout.width;
    const zero_extended = spec.layout.fill == '0' and spec.layout.alignment == .sign_aware;
    const min_width: isize = if (zero_extended) width - @as(isize, @intCast(fixed)) else 0;
    var grouped_storage: [2 * limit + 400]u8 = undefined;
    const grouped = group(&grouped_storage, number.digits, min_width, spec);
    const padding: usize = @intCast(@max(0, width - @as(isize, @intCast(fixed + grouped.len))));
    const left: usize, const inner: usize = switch (spec.layout.alignment) {
        .left => .{ 0, 0 },
        .center => .{ padding / 2, 0 },
        .sign_aware => .{ 0, padding },
        else => .{ padding, 0 },
    };
    out.fill(spec.layout.fill, left);
    if (sign) |mark| out.byte(mark);
    out.put(number.prefix);
    out.fill(spec.layout.fill, inner);
    for (grouped) |digit| out.byte(if (number.uppercase) std.ascii.toUpper(digit) else digit);
    out.put(number.remainder);
    out.fill(spec.layout.fill, padding - left - inner);
}

/// CPython's `_PyUnicode_InsertThousandsGrouping`: digits grouped from the
/// right, zero-extended to at least `min_width` characters, never starting
/// with a separator (so `f"{1:08,}"` is `0,000,001`, one wider than asked).
fn group(storage: []u8, digits: []const u8, min_width: isize, spec: Spec) []const u8 {
    if (digits.len == 0) return digits;
    const separator: ?u8 = switch (spec.flags.grouping) {
        .none => null,
        .comma => ',',
        .underscore => '_',
    };
    const size: isize = if (separator == null) 0 else if (spec.kind == .b or spec.kind == .o or spec.kind == .x or spec.kind == .X) 4 else 3;
    var reversed: usize = 0;
    var remaining: isize = @intCast(digits.len);
    var width = min_width;
    var first = true;
    while (true) {
        const last = size == 0;
        const length = if (last) @max(@max(remaining, width), 1) else @min(size, @max(@max(remaining, width), 1));
        const zeros: usize = @intCast(@max(0, length - remaining));
        const chars: usize = @intCast(@max(0, @min(remaining, length)));
        if (!first) {
            storage[reversed] = separator.?;
            reversed += 1;
        }
        for (0..chars) |index| storage[reversed + index] = digits[@as(usize, @intCast(remaining)) - 1 - index];
        reversed += chars;
        @memset(storage[reversed..][0..zeros], '0');
        reversed += zeros;
        first = false;
        remaining -= @intCast(chars);
        width -= length;
        if (last or (remaining <= 0 and width <= 0)) break;
        width -= 1;
    }
    std.mem.reverse(u8, storage[0..reversed]);
    return storage[0..reversed];
}

/// How a rounded tie resolves: to the even neighbour (CPython's formatting)
/// or away from zero (the language's `round`).
pub const Ties = enum { even, away };

/// Significant decimal digits of a finite nonnegative binary64, without
/// leading or trailing zeros, and the decimal point's position: the value is
/// `0.d1d2... * 10**point`. Zero has no digits.
pub const Decimal = struct {
    digits: [1100]u8 = undefined,
    len: usize = 0,
    point: i32 = 0,

    /// The kept digits.
    pub fn slice(self: *const Decimal) []const u8 {
        return self.digits[0..self.len];
    }
    fn trim(self: *Decimal) void {
        while (self.len > 0 and self.digits[self.len - 1] == '0') self.len -= 1;
    }
};

/// A little-endian magnitude wide enough for `m * 5**1074` and `m * 2**971`.
const Big = struct {
    limbs: [96]u32 = undefined,
    len: usize = 0,

    fn from(value: u64) Big {
        var big: Big = .{};
        big.limbs[0] = @truncate(value);
        big.limbs[1] = @truncate(value >> 32);
        big.len = if (big.limbs[1] != 0) 2 else if (big.limbs[0] != 0) 1 else 0;
        return big;
    }
    fn multiply(self: *Big, factor: u32) void {
        var carry: u64 = 0;
        for (self.limbs[0..self.len]) |*limb| {
            const product = @as(u64, limb.*) * factor + carry;
            limb.* = @truncate(product);
            carry = product >> 32;
        }
        if (carry != 0) {
            self.limbs[self.len] = @truncate(carry);
            self.len += 1;
        }
    }
    fn shift(self: *Big, bits: u32) void {
        var remaining = bits;
        while (remaining >= 31) : (remaining -= 31) self.multiply(@as(u32, 1) << 31);
        if (remaining > 0) self.multiply(@as(u32, 1) << @intCast(remaining));
    }
    /// Divide in place by `divisor`, answering the remainder.
    fn divide(self: *Big, divisor: u32) u32 {
        var remainder: u64 = 0;
        var index = self.len;
        while (index > 0) {
            index -= 1;
            const current = (remainder << 32) | self.limbs[index];
            self.limbs[index] = @intCast(current / divisor);
            remainder = current % divisor;
        }
        while (self.len > 0 and self.limbs[self.len - 1] == 0) self.len -= 1;
        return @intCast(remainder);
    }
};

/// The exact decimal expansion of `|value|` for a finite `value`.
pub fn expand(value: f64) Decimal {
    var result: Decimal = .{};
    const bits: u64 = @bitCast(value);
    const biased: i32 = @intCast((bits >> 52) & 0x7ff);
    const fraction = bits & ((@as(u64, 1) << 52) - 1);
    if (biased == 0 and fraction == 0) return result;
    const mantissa = if (biased == 0) fraction else fraction | (@as(u64, 1) << 52);
    const exponent: i32 = (if (biased == 0) 1 else biased) - 1075;
    var big = Big.from(mantissa);
    var scale: i32 = 0;
    if (exponent >= 0) big.shift(@intCast(exponent)) else {
        // m * 2**e == m * 5**-e / 10**-e.
        var fives: i32 = -exponent;
        while (fives >= 13) : (fives -= 13) big.multiply(1220703125);
        while (fives > 0) : (fives -= 1) big.multiply(5);
        scale = -exponent;
    }
    var reversed: [1100]u8 = undefined;
    var count: usize = 0;
    while (big.len > 0) {
        var chunk = big.divide(1_000_000_000);
        var produced: usize = 0;
        while (produced < 9 and (big.len > 0 or chunk > 0)) : (produced += 1) {
            reversed[count] = '0' + @as(u8, @intCast(chunk % 10));
            chunk /= 10;
            count += 1;
        }
    }
    for (0..count) |index| result.digits[index] = reversed[count - 1 - index];
    result.len = count;
    result.point = @as(i32, @intCast(count)) - scale;
    result.trim();
    return result;
}

/// Round `decimal` to its first `keep` digits (which may be zero or negative),
/// resolving an exact tie as `ties` says. A value that rounds to zero keeps no
/// digits; a carry out of the first digit moves the point.
pub fn roundDigits(decimal: *Decimal, keep: i32, ties: Ties) void {
    if (keep >= decimal.len) return;
    if (keep < 0) {
        decimal.len = 0;
        return;
    }
    const cut: usize = @intCast(keep);
    const first_dropped = decimal.digits[cut];
    const exact_half = first_dropped == '5' and cut + 1 == decimal.len;
    const odd = cut > 0 and (decimal.digits[cut - 1] - '0') % 2 == 1;
    const up = first_dropped > '5' or (first_dropped == '5' and !exact_half) or (exact_half and (ties == .away or odd));
    decimal.len = cut;
    if (up) {
        var index = cut;
        while (index > 0) {
            index -= 1;
            if (decimal.digits[index] != '9') {
                decimal.digits[index] += 1;
                decimal.len = index + 1;
                decimal.trim();
                return;
            }
        }
        decimal.digits[0] = '1';
        decimal.len = 1;
        decimal.point += 1;
        return;
    }
    decimal.trim();
}

/// `round(value, ndigits)` with ties away from zero on the exact binary value,
/// read back as the nearest binary64, following CPython's `float.__round__`
/// bounds: past 323 digits a value is its own rounding, and below -308 digits
/// every value rounds to a zero of its own sign.
pub fn roundFloat(value: f64, ndigits: i64) f64 {
    if (!std.math.isFinite(value) or ndigits > 323) return value;
    if (ndigits < -308) return std.math.copysign(@as(f64, 0.0), value);
    var decimal = expand(value);
    roundDigits(&decimal, decimal.point + @as(i32, @intCast(ndigits)), .away);
    if (decimal.len == 0) return std.math.copysign(@as(f64, 0.0), value);
    var text: [1200]u8 = undefined;
    const spelled = std.fmt.bufPrint(&text, "{s}e{d}", .{ decimal.slice(), decimal.point - @as(i32, @intCast(decimal.len)) }) catch return value;
    const magnitude = std.fmt.parseFloat(f64, spelled) catch return value;
    return if (std.math.signbit(value)) -magnitude else magnitude;
}

/// CPython `_Py_dg_dtoa` modes: shortest round-trip digits, a number of
/// significant digits, or a number of digits after the point.
const Mode = union(enum) { shortest, significant: u16, fixed: u16 };

/// Digits and point for one mode, rounding ties to even. A zero value, or a
/// fixed value that rounds to zero, is `0` with the point after it.
fn digitsFor(value: f64, mode: Mode) Decimal {
    var decimal: Decimal = undefined;
    switch (mode) {
        .shortest => decimal = shortest(value),
        .significant => |count| {
            decimal = expand(value);
            roundDigits(&decimal, count, .even);
        },
        .fixed => |count| {
            decimal = expand(value);
            roundDigits(&decimal, decimal.point + count, .even);
        },
    }
    if (decimal.len == 0) {
        decimal.digits[0] = '0';
        decimal.len = 1;
        decimal.point = 1;
    }
    return decimal;
}

/// The shortest digits that read back as `value`, from the standard library's
/// round-trip formatter.
fn shortest(value: f64) Decimal {
    var result: Decimal = .{};
    if (value == 0) return result;
    var text: [64]u8 = undefined;
    const spelled = std.fmt.float.render(&text, @abs(value), .{ .mode = .scientific }) catch return expand(value);
    const marker = std.mem.indexOfScalar(u8, spelled, 'e') orelse spelled.len;
    for (spelled[0..marker]) |character| if (std.ascii.isDigit(character)) {
        result.digits[result.len] = character;
        result.len += 1;
    };
    const exponent = if (marker < spelled.len) std.fmt.parseInt(i32, spelled[marker + 1 ..], 10) catch 0 else 0;
    result.point = exponent + 1;
    result.trim();
    return result;
}

/// The presentation `format_float_short` applies after the digits are chosen.
const Style = struct { code: u8, precision: u16, add_dot_zero: bool, alternate: bool, uppercase: bool };

/// Port of CPython's `format_float_short` for a finite magnitude: the digits
/// laid out with leading and trailing zeros, a decimal point, and an exponent.
fn spell(out: *Out, decimal: Decimal, style: Style) void {
    const digits = decimal.slice();
    const length: isize = @intCast(digits.len);
    var point: isize = decimal.point;
    var use_exponent = false;
    var end: isize = length;
    switch (style.code) {
        'e' => {
            use_exponent = true;
            end = style.precision;
        },
        'f' => end = point + style.precision,
        'g' => {
            const bound: isize = if (style.add_dot_zero) @as(isize, style.precision) - 1 else style.precision;
            if (point <= -4 or point > bound) use_exponent = true;
            if (style.alternate) end = style.precision;
        },
        else => if (point <= -4 or point > 16) {
            use_exponent = true;
        },
    }
    var exponent: isize = 0;
    if (use_exponent) {
        exponent = point - 1;
        point = 1;
    }
    const start: isize = if (point <= 0) point - 1 else 0;
    end = if (!use_exponent and style.add_dot_zero) @max(end, point + 1) else @max(end, point);
    var body: [2 * limit + 800]u8 = undefined;
    var spelled: Out = .{ .buffer = &body };
    if (point <= 0) {
        spelled.fill('0', @intCast(point - start));
        spelled.byte('.');
        spelled.fill('0', @intCast(-point));
    } else spelled.fill('0', @intCast(-start));
    if (0 < point and point <= length) {
        spelled.put(digits[0..@intCast(point)]);
        spelled.byte('.');
        spelled.put(digits[@intCast(point)..]);
    } else spelled.put(digits);
    if (length < point) {
        spelled.fill('0', @intCast(point - length));
        spelled.byte('.');
        spelled.fill('0', @intCast(end - point));
    } else spelled.fill('0', @intCast(end - length));
    if (spelled.len > 0 and body[spelled.len - 1] == '.' and !style.alternate) spelled.len -= 1;
    out.put(body[0..spelled.len]);
    if (use_exponent) {
        out.byte(if (style.uppercase) 'E' else 'e');
        out.byte(if (exponent < 0) '-' else '+');
        // A binary64 exponent has at most three digits, and CPython writes two at least.
        const magnitude: u64 = @abs(exponent);
        if (magnitude >= 100) out.byte('0' + @as(u8, @intCast(magnitude / 100)));
        out.byte('0' + @as(u8, @intCast(magnitude / 10 % 10)));
        out.byte('0' + @as(u8, @intCast(magnitude % 10)));
    }
}

/// CPython's `format_float_internal`: choose the digits, spell them, then lay
/// the number out with its sign, grouping and padding.
fn renderFloat(out: *Out, spec: Spec, input: f64) void {
    const uppercase = spec.kind == .E or spec.kind == .F or spec.kind == .G;
    const percent = spec.kind == .percent;
    const value = if (percent) input * 100 else input;
    var body: [2 * limit + 800]u8 = undefined;
    var spelled: Out = .{ .buffer = &body };
    var negative = std.math.signbit(value) and !std.math.isNan(value);
    if (std.math.isNan(value) or std.math.isInf(value)) {
        spelled.put(if (std.math.isNan(value)) (if (uppercase) "NAN" else "nan") else (if (uppercase) "INF" else "inf"));
    } else {
        const magnitude = @abs(value);
        const code: u8, const mode: Mode, const precision: u16 = switch (spec.kind) {
            .e, .E => .{ 'e', .{ .significant = (spec.precision orelse 6) + 1 }, (spec.precision orelse 6) + 1 },
            .f, .F, .percent => .{ 'f', .{ .fixed = spec.precision orelse 6 }, spec.precision orelse 6 },
            .g, .G => .{ 'g', .{ .significant = @max(1, spec.precision orelse 6) }, @max(1, spec.precision orelse 6) },
            else => if (spec.precision) |given| .{ 'g', .{ .significant = @max(1, given) }, @max(1, given) } else .{ 'r', .shortest, 0 },
        };
        const decimal = digitsFor(magnitude, mode);
        const zero = decimal.len == 1 and decimal.digits[0] == '0';
        if (spec.flags.no_negative_zero and zero) negative = false;
        spell(&spelled, decimal, .{ .code = code, .precision = precision, .add_dot_zero = spec.kind == .none, .alternate = spec.flags.alternate, .uppercase = uppercase });
    }
    if (percent) spelled.byte('%');
    const text = body[0..spelled.len];
    var digits_end: usize = 0;
    while (digits_end < text.len and std.ascii.isDigit(text[digits_end])) digits_end += 1;
    layOut(out, spec, .{ .sign = if (negative) '-' else null, .prefix = "", .digits = text[0..digits_end], .remainder = text[digits_end..], .uppercase = false });
}
