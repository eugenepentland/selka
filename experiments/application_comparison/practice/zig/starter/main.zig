const std = @import("std");
const helper = @import("helper.zig");

const nine: i64 = 9;

fn parseDigit(input: []const u8) error{InvalidDigit}!i64 {
    if (input.len != 1 or input[0] < '0' or input[0] > '9') {
        return error.InvalidDigit;
    }
    return input[0] - '0';
}

fn result(input: []const u8) i64 {
    if (std.mem.eql(u8, input, "m")) return helper.multiply(6);
    if (std.mem.eql(u8, input, "d")) return missing_nine;
    if (input.len > 0 and input[0] == 'f') {
        return parseDigit(input[1..]) catch 0;
    }
    return -1;
}

pub fn main(init: std.process.Init) !void {
    // One extra byte distinguishes the exact limit from oversized input.
    var input: [257]u8 = undefined;
    var length: usize = 0;
    while (length < input.len) {
        const count = std.Io.File.stdin().readStreaming(init.io, &.{input[length..]}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        length += count;
    }
    const value = if (length > 256) -1 else result(input[0..length]);
    var output: [32]u8 = undefined;
    const text = try std.fmt.bufPrint(&output, "{d}\n", .{value});
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
}
