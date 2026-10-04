//! Mathematical proof boundaries for the optional existing-guard recipe.
const std = @import("std");
const t = std.testing;
const bias = @import("qbe_remainder_bias.zig");

fn identity(bound: u64, divisor: u64) !void {
    const recipe = bias.plan(bound, divisor) orelse return error.TestUnexpectedResult;
    try t.expectEqual(@as(u64, 0), recipe.addend % divisor);
    const edge: i64 = @intCast(bound);
    for ([_]i64{ -edge, -edge + @intFromBool(edge != 0), -1, 0, 1, edge - @intFromBool(edge != 0), edge }) |value| {
        if (@abs(value) > bound) continue;
        const actual = (@as(u64, @bitCast(value)) +% recipe.addend) % divisor;
        const expected: u64 = @intCast(@mod(@as(i128, value), @as(i128, divisor)));
        try t.expectEqual(expected, actual);
        const mathematical = @as(i128, value) + recipe.addend;
        try t.expect(mathematical >= 0 and mathematical <= std.math.maxInt(u64));
    }
}

fn divisors() !void {
    for ([_]u64{ 1, 2, 8, 3, 7, 1009, 100003, 4700000000000000000, std.math.maxInt(i64) }) |divisor| {
        try identity(0, divisor);
        try identity(127, divisor);
        try identity(1 << 59, divisor);
    }
    try identity(15 * (@as(u64, 1) << 59), 1009);
    try identity(6000000000000000000, 4700000000000000000);
}

// spec: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias preserves flooring at every signed endpoint and positive divisor width" {
    try divisors();
    try t.expectEqual(@as(u64, 9400000000000000000), bias.plan(6000000000000000000, 4700000000000000000).?.addend);
    try t.expectEqual(@as(u64, 8646911284551353149), bias.plan(15 * (@as(u64, 1) << 59), 1009).?.addend);
}

fn exhaustive() !void {
    for (1..129) |divisor| {
        const recipe = bias.plan(1024, divisor).?;
        var value: i64 = -1024;
        while (value <= 1024) : (value += 1) {
            const actual = (@as(u64, @bitCast(value)) +% recipe.addend) % divisor;
            try t.expectEqual(@as(u64, @intCast(@mod(value, @as(i64, @intCast(divisor))))), actual);
        }
    }
}

// spec-case: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias covers complete small signed ranges without a runtime sign condition" {
    try exhaustive();
}

// spec-case: QBE-LOOP-REMAINDER-BIAS-1
test "bounded remainder bias refuses infeasible unsigned interval and overflowed magnitude" {
    try t.expect(bias.plan(std.math.maxInt(i64), 1009) == null);
    try t.expect(bias.plan(std.math.maxInt(u64), 1) == null);
    try t.expect(bias.plan(100, 0) == null);
    try t.expect(bias.plan(100, std.math.maxInt(u64)) == null);
    try t.expect(bias.magnitude(1, 255, 60) == null);
    try t.expect(bias.magnitude(std.math.maxInt(u64), 0, 60) == null);
    try t.expect(bias.magnitude(std.math.maxInt(u64), 2, 60) == null);
    try t.expectEqual(@as(?u64, 15 * (@as(u64, 1) << 59)), bias.magnitude(15, 1, 59));
    try t.expectEqual(@as(?u64, 101), bias.magnitude(101, 0, 60));
}
