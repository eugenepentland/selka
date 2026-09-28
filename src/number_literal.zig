//! Python's numeric literal spellings: the token scanner the lexer runs, the integer
//! and float classifiers, and the digit and underscore validation the checkers share.
//!
//! Integer: `123`, `0xFF`, `0o17`, `0b1010`, each with single underscores between
//! digits (and after the base prefix), then an optional width suffix such as `u8`.
//! Float: `1.5`, `.5`, `5.`, `1e10`, `1.5e-3`, `1_000.5`, `1e1_0`. The scanner keeps a
//! malformed spelling as one token so the checker can name exactly what is wrong.
const std = @import("std");

/// Code for a malformed integer spelling: a bad digit, a misplaced underscore, or
/// missing digits after a base prefix.
pub const integer_code = "E_INTEGER_LITERAL";
/// Code for a malformed floating-point spelling.
pub const float_code = "E_FLOAT_LITERAL";
/// Code for an integer literal too large to represent.
pub const range_code = "E_INTEGER_RANGE";
/// Code for a suffix that names no integer width.
pub const suffix_code = "E_INTEGER_SUFFIX";

const doubled_underscore = "doubled underscore in a number; a single underscore may separate digits";
const trailing_underscore = "an underscore in a number must be followed by a digit; a width suffix goes directly after the last digit (1_000u32)";
const leading_underscore = "an underscore in a number must sit between two digits";
/// Message for an imaginary literal such as `1j`, shared by the integer and float paths.
pub const imaginary_message = "imaginary literals such as 1j are not supported; mylang has no complex numbers";

/// A diagnostic for one malformed spelling: a stable code and a static message.
pub const Problem = struct { code: []const u8, message: []const u8 };

/// Radix named by a `0x`, `0o` or `0b` prefix, or null for a decimal spelling.
pub fn prefixBase(text: []const u8) ?u8 {
    if (text.len < 2 or text[0] != '0') return null;
    return switch (text[1]) {
        'x', 'X' => 16,
        'o', 'O' => 8,
        'b', 'B' => 2,
        else => null,
    };
}

/// Whether a numeric token is a floating spelling: a decimal token holding a point
/// or an exponent marker. A `0x` literal may contain `e`, so prefixed spellings are
/// always integers.
pub fn isFloat(text: []const u8) bool {
    return prefixBase(text) == null and std.mem.indexOfAny(u8, text, ".eE") != null;
}

fn wordEnd(bytes: []const u8, start: usize) usize {
    var at = start;
    while (at < bytes.len and (std.ascii.isAlphanumeric(bytes[at]) or bytes[at] == '_')) at += 1;
    return at;
}

fn digitsEnd(bytes: []const u8, start: usize) usize {
    var at = start;
    while (at < bytes.len and (std.ascii.isDigit(bytes[at]) or bytes[at] == '_')) at += 1;
    return at;
}

/// Whether `bytes[at..]` starts an exponent: `e` or `E`, an optional sign, a digit.
fn exponentAhead(bytes: []const u8, start: usize) bool {
    if (start >= bytes.len or (bytes[start] != 'e' and bytes[start] != 'E')) return false;
    var at = start + 1;
    if (at < bytes.len and (bytes[at] == '+' or bytes[at] == '-')) at += 1;
    return at < bytes.len and std.ascii.isDigit(bytes[at]);
}

/// Whether the `.` at `dot` belongs to the number before it. `5.` and `5.e3` are
/// floats, but `5.name` keeps its dot for field access so that stays a checker error
/// on the integer rather than a malformed float.
fn dotBelongs(bytes: []const u8, dot: usize) bool {
    const next = dot + 1;
    if (next >= bytes.len) return true;
    if (std.ascii.isDigit(bytes[next])) return true;
    if (std.ascii.isAlphabetic(bytes[next]) or bytes[next] == '_') return exponentAhead(bytes, next);
    return true;
}

/// Whether a `.` at `start` begins a leading-dot float such as `.5`: a digit must
/// follow, and `previous_operand` says the dot sits directly after an operand
/// (`x.5`, `f().5`), where it stays field-access punctuation.
pub fn leadingDot(bytes: []const u8, start: usize, previous_operand: bool) bool {
    if (previous_operand) return false;
    return start + 1 < bytes.len and std.ascii.isDigit(bytes[start + 1]);
}

/// One past the last byte of the numeric token starting at `start`, which is a digit
/// or a leading-dot float. Trailing letters, digits and underscores stay in the token
/// so a malformed suffix or digit is diagnosed as one located literal.
pub fn end(bytes: []const u8, start: usize) usize {
    if (bytes[start] == '0' and prefixBase(bytes[start..@min(bytes.len, start + 2)]) != null) return wordEnd(bytes, start + 2);
    var at = digitsEnd(bytes, start);
    if (at < bytes.len and bytes[at] == '.' and dotBelongs(bytes, at)) at = digitsEnd(bytes, at + 1);
    if (at < bytes.len and (bytes[at] == 'e' or bytes[at] == 'E')) {
        at += 1;
        if (at < bytes.len and (bytes[at] == '+' or bytes[at] == '-')) at += 1;
    }
    return wordEnd(bytes, at);
}

/// The pieces of an integer spelling: radix, digit run (with its underscores), and
/// the text of a width suffix when one follows the digits.
pub const Integer = struct { base: u8, digits: []const u8, suffix: []const u8 };
/// Result of splitting an integer spelling.
pub const IntegerResult = union(enum) { ok: Integer, bad: Problem };

fn validDigit(byte: u8, base: u8) bool {
    _ = std.fmt.charToDigit(byte, base) catch return false;
    return true;
}

/// Split an integer token into radix, digits and suffix, applying Python's rules:
/// underscores only between digits (one may follow the base prefix), at least one
/// digit, and digits valid for the radix. Decimal leading zeros stay accepted (`007` is 7).
/// A suffix begins at the first byte that is not a digit of the radix. Suffix letters
/// `i` and `u` are never digits of any radix, so `0xFFu8` is unambiguous.
pub fn integer(text: []const u8) IntegerResult {
    const prefix = prefixBase(text);
    const base = prefix orelse 10;
    var at: usize = if (prefix != null) 2 else 0;
    const begin = at;
    if (prefix != null and at < text.len and text[at] == '_') at += 1;
    const digit_begin = at;
    while (at < text.len and (validDigit(text[at], base) or text[at] == '_')) at += 1;
    const digits = text[begin..at];
    const rest = text[at..];
    if (std.mem.indexOf(u8, digits, "__") != null) return .{ .bad = .{ .code = integer_code, .message = doubled_underscore } };
    if (digits.len != 0 and digits[digits.len - 1] == '_') return .{ .bad = .{ .code = integer_code, .message = trailing_underscore } };
    if (at == digit_begin) return .{ .bad = .{ .code = integer_code, .message = missingDigits(base) } };
    if (rest.len != 0 and std.ascii.isDigit(rest[0])) return .{ .bad = .{ .code = integer_code, .message = invalidDigit(base) } };
    return .{ .ok = .{ .base = base, .digits = digits, .suffix = rest } };
}

fn missingDigits(base: u8) []const u8 {
    return switch (base) {
        16 => "a 0x literal needs at least one hexadecimal digit",
        8 => "a 0o literal needs at least one octal digit (0 through 7)",
        else => "a 0b literal needs at least one binary digit (0 or 1)",
    };
}

fn invalidDigit(base: u8) []const u8 {
    return switch (base) {
        8 => "invalid digit in an octal (0o) literal; octal digits are 0 through 7",
        else => "invalid digit in a binary (0b) literal; binary digits are 0 and 1",
    };
}

/// The value of a validated digit run in `base`, or null when it exceeds 128 bits.
pub fn magnitude(parts: Integer) ?u128 {
    var value: u128 = 0;
    for (parts.digits) |byte| {
        if (byte == '_') continue;
        const digit = std.fmt.charToDigit(byte, parts.base) catch return null;
        value = std.math.mul(u128, value, parts.base) catch return null;
        value = std.math.add(u128, value, digit) catch return null;
    }
    return value;
}

/// Result of parsing a float spelling: its binary64 value, or the located problem.
pub const FloatResult = union(enum) { ok: f64, bad: Problem };

const Run = enum { digits, empty, doubled, trailing, leading };

/// Append the digits of one `digit (_? digit)*` run to `out` and advance `at` past it.
fn digitRun(arena: std.mem.Allocator, text: []const u8, at: *usize, out: *std.ArrayList(u8)) error{OutOfMemory}!Run {
    const begin = at.*;
    var underscore = false;
    while (at.* < text.len) : (at.* += 1) {
        const byte = text[at.*];
        if (byte == '_') {
            if (at.* == begin) return .leading;
            if (underscore) return .doubled;
            underscore = true;
            continue;
        }
        if (!std.ascii.isDigit(byte)) break;
        underscore = false;
        try out.append(arena, byte);
    }
    if (at.* == begin) return .empty;
    return if (underscore) .trailing else .digits;
}

fn runProblem(run: Run) ?Problem {
    return switch (run) {
        .digits, .empty => null,
        .doubled => .{ .code = float_code, .message = doubled_underscore },
        .trailing => .{ .code = float_code, .message = trailing_underscore },
        .leading => .{ .code = float_code, .message = leading_underscore },
    };
}

/// Parse a floating spelling under Python's grammar. `.5` and `5.` read as `0.5` and
/// `5.0`, underscores may separate digits in the mantissa and the exponent, and leading
/// zeros are allowed (`007.5`). `arena` holds the normalized text handed to the
/// binary64 conversion, so the parsed value rounds like any decimal constant.
pub fn float(arena: std.mem.Allocator, text: []const u8) error{OutOfMemory}!FloatResult {
    if (prefixBase(text) != null) return prefixedFloat(text);
    var clean: std.ArrayList(u8) = .empty;
    var at: usize = 0;
    const whole = try digitRun(arena, text, &at, &clean);
    if (runProblem(whole)) |problem| return .{ .bad = problem };
    var fraction: Run = .empty;
    if (at < text.len and text[at] == '.') {
        if (whole == .empty) try clean.append(arena, '0');
        try clean.append(arena, '.');
        at += 1;
        fraction = try digitRun(arena, text, &at, &clean);
        if (runProblem(fraction)) |problem| return .{ .bad = problem };
        if (fraction == .empty) try clean.append(arena, '0');
    }
    if (whole == .empty and fraction == .empty) return .{ .bad = .{ .code = float_code, .message = "invalid decimal floating-point literal" } };
    if (at < text.len and (text[at] == 'e' or text[at] == 'E')) {
        try clean.append(arena, 'e');
        at += 1;
        if (at < text.len and (text[at] == '+' or text[at] == '-')) {
            try clean.append(arena, text[at]);
            at += 1;
        }
        const exponent = try digitRun(arena, text, &at, &clean);
        if (runProblem(exponent)) |problem| return .{ .bad = problem };
        if (exponent == .empty) return .{ .bad = .{ .code = float_code, .message = "a floating-point exponent needs digits after e, as in 1e5 or 2.5e-3" } };
    }
    if (at < text.len) {
        const imaginary = at + 1 == text.len and (text[at] == 'j' or text[at] == 'J');
        return .{ .bad = .{ .code = float_code, .message = if (imaginary) imaginary_message else "invalid decimal floating-point literal; a float literal takes no suffix" } };
    }
    const value = std.fmt.parseFloat(f64, clean.items) catch return .{ .bad = .{ .code = float_code, .message = "invalid decimal floating-point literal" } };
    return .{ .ok = value };
}

/// An integer spelling in a float context (`x: float = 0xFF`) converts exactly like a
/// decimal one; a width suffix has no meaning there.
fn prefixedFloat(text: []const u8) FloatResult {
    const parts = switch (integer(text)) {
        .ok => |parts| parts,
        .bad => |problem| return .{ .bad = problem },
    };
    if (parts.suffix.len != 0) return .{ .bad = .{ .code = float_code, .message = "a float literal takes no integer suffix" } };
    const value = magnitude(parts) orelse return .{ .bad = .{ .code = range_code, .message = "integer literal magnitude is too large" } };
    return .{ .ok = @floatFromInt(value) };
}
