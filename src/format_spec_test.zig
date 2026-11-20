//! The format-specification engine against CPython: every row of
//! `format_spec_cases.tsv` is `format(value, spec)` as CPython 3.14 answers it,
//! or `round(value, n)` under the language's ties-away rule, and the engine
//! must reproduce each one byte for byte through the same parse, resolve,
//! pack and render path the checker and the runtime take.
const std = @import("std");
const t = std.testing;
const format_spec = @import("format_spec.zig");
const debug = std.debug;
const cases = @embedFile("format_spec_cases.tsv");

/// Parse, resolve, pack, unpack and render one value the way a guest does.
fn rendered(buffer: []u8, spec_text: []const u8, family: format_spec.Family, input: format_spec.Input) ![]const u8 {
    const parsed = switch (format_spec.parse(spec_text)) {
        .ok => |value| value,
        .rejected => return error.Rejected,
    };
    const spec = switch (format_spec.resolve(parsed, family)) {
        .ok => |value| value,
        .rejected => return error.Rejected,
    };
    const word = format_spec.pack(spec);
    const unpacked = format_spec.unpack(word) orelse return error.Rejected;
    var measure: format_spec.Out = .{};
    format_spec.render(&measure, unpacked, input);
    var out: format_spec.Out = .{ .buffer = buffer[0..measure.len] };
    format_spec.render(&out, unpacked, input);
    return buffer[0..out.len];
}

/// Check every row of one kind, reporting the first mismatch with its row.
fn checkRows(kind: u8) !usize {
    var checked: usize = 0;
    var lines = std.mem.splitScalar(u8, cases, '\n');
    var buffer: [16384]u8 = undefined;
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] != kind) continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        _ = fields.next();
        const value = fields.next().?;
        const spec = fields.next().?;
        const expected = fields.rest();
        const actual = switch (kind) {
            'T' => try rendered(&buffer, spec, .text, .{ .text = .{ .bytes = value, .scalars = try std.unicode.utf8CountCodepoints(value) } }),
            'F' => try rendered(&buffer, spec, .float, .{ .float = @bitCast(try std.fmt.parseInt(u64, value, 16)) }),
            'I' => try rendered(&buffer, spec, .signed, .{ .signed = @bitCast(try std.fmt.parseInt(u64, value, 16)) }),
            'U' => try rendered(&buffer, spec, .unsigned, .{ .unsigned = try std.fmt.parseInt(u64, value, 16) }),
            else => unreachable,
        };
        if (!std.mem.eql(u8, expected, actual)) debug.print("oracle row `{s}`\n", .{line});
        try t.expectEqualStrings(expected, actual);
        checked += 1;
    }
    return checked;
}

/// Check every `round` row against the language's ties-away rule.
fn checkRounds() !usize {
    var checked: usize = 0;
    var lines = std.mem.splitScalar(u8, cases, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] != 'R') continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        _ = fields.next();
        const value: f64 = @bitCast(try std.fmt.parseInt(u64, fields.next().?, 16));
        const digits = try std.fmt.parseInt(i64, fields.next().?, 10);
        const expected = try std.fmt.parseInt(u64, fields.next().?, 16);
        const actual: u64 = @bitCast(format_spec.roundFloat(value, digits));
        if (expected != actual) debug.print("round row `{s}`\n", .{line});
        try t.expectEqual(expected, actual);
        checked += 1;
    }
    return checked;
}

/// The rejection message a specification draws for one family, or null.
fn rejection(spec_text: []const u8, family: format_spec.Family) ?[]const u8 {
    const parsed = switch (format_spec.parse(spec_text)) {
        .ok => |value| value,
        .rejected => |refused| return refused.message,
    };
    return switch (format_spec.resolve(parsed, family)) {
        .ok => null,
        .rejected => |refused| refused.message,
    };
}

// spec-case: PY-FSTRING-SPEC-1
test "float format specifications render every CPython oracle row exactly" {
    try t.expect(try checkRows('F') > 4000);
}

// spec-case: PY-FSTRING-SPEC-1
test "integer and text format specifications render every CPython oracle row exactly" {
    try t.expect(try checkRows('I') > 600);
    try t.expect(try checkRows('U') > 150);
    try t.expect(try checkRows('T') > 100);
}

// spec-case: PRELUDE-ROUND-2
test "round to n digits rounds the exact binary value with ties away from zero" {
    try t.expect(try checkRounds() > 700);
    try t.expectEqual(@as(f64, 2.67), format_spec.roundFloat(2.675, 2));
    try t.expectEqual(@as(f64, 0.13), format_spec.roundFloat(0.125, 2));
    try t.expectEqual(@as(f64, -3.0), format_spec.roundFloat(-2.5, 0));
    try t.expectEqual(@as(f64, 1200.0), format_spec.roundFloat(1234.5, -2));
    try t.expect(std.math.signbit(format_spec.roundFloat(-0.001, 2)));
}

// spec-case: PY-FSTRING-SPEC-2
test "a specification the value family cannot take is rejected with CPython's reason" {
    try t.expectEqualStrings("Sign not allowed in string format specifier", rejection("+", .text).?);
    try t.expectEqualStrings("Precision not allowed in integer format specifier", rejection(".2d", .signed).?);
    try t.expectEqualStrings("Unknown format code for object of type 'float'", rejection("d", .float).?);
    try t.expectEqualStrings("Format specifier missing precision", rejection(".f", .float).?);
    try t.expectEqualStrings("Invalid format specifier", rejection("abc", .float).?);
    try t.expectEqualStrings("Cannot specify ',' with 'n'.", rejection(",n", .signed).?);
    try t.expect(std.mem.indexOf(u8, rejection(",x", .signed).?, "use '_'") != null);
    try t.expect(std.mem.indexOf(u8, rejection("5000", .float).?, "at most 4095") != null);
    try t.expect(std.mem.indexOf(u8, rejection("c", .signed).?, "chr(value)") != null);
    try t.expect(rejection(">10.3f", .float) == null);
    var buffer: [64]u8 = undefined;
    try t.expectError(error.Rejected, rendered(&buffer, "+", .text, .{ .text = .{ .bytes = "a", .scalars = 1 } }));
    try t.expectError(error.Rejected, rendered(&buffer, "abc", .float, .{ .float = 1.0 }));
}

// spec-case: PY-FSTRING-SPEC-1
test "a packed specification survives the runtime word unchanged" {
    const parsed = format_spec.parse("é^+#012_.3e").ok;
    const spec = format_spec.resolve(parsed, .float).ok;
    try t.expectEqualDeep(spec, format_spec.unpack(format_spec.pack(spec)).?);
    try t.expectEqual(@as(?format_spec.Spec, null), format_spec.unpack(std.math.maxInt(u64)));
}
