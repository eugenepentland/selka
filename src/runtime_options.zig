//! The channel a native executable's runtime options travel in. A built program
//! reads its runtime controls and capability grants from `MYLANG_OPTIONS`, never
//! from its own arguments, so every value after `argv[0]` reaches `main(args)`
//! unchanged. `mylang run`, `mylang build --run`, the test harnesses and host
//! applications translate their own options into that variable here; the native
//! runtime parses it in `src/qbe_grants.c`.
const std = @import("std");

/// The environment variable a native executable reads its runtime options from.
pub const variable = "MYLANG_OPTIONS";

/// A launcher's command tail, divided at its first `--`: the runtime options
/// before it and the program's own arguments after it.
pub const Split = struct { options: []const []const u8, program: []const []const u8 };

/// Divide `arguments` at its first `--`. Without one, every value is an option.
pub fn split(arguments: []const []const u8) Split {
    for (arguments, 0..) |argument, index| {
        if (std.mem.eql(u8, argument, "--")) return .{ .options = arguments[0..index], .program = arguments[index + 1 ..] };
    }
    return .{ .options = arguments, .program = &.{} };
}

/// Spell `options` as one `MYLANG_OPTIONS` value: whitespace-separated, with an
/// option that holds whitespace, a quote or a backslash wrapped in double
/// quotes and its quotes and backslashes escaped, which the runtime undoes.
pub fn encode(allocator: std.mem.Allocator, options: []const []const u8) std.mem.Allocator.Error![]u8 {
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(allocator);
    for (options, 0..) |option, index| {
        if (index != 0) try text.append(allocator, ' ');
        if (option.len != 0 and std.mem.indexOfAny(u8, option, " \t\r\n\"\\") == null) {
            try text.appendSlice(allocator, option);
            continue;
        }
        try text.append(allocator, '"');
        for (option) |byte| {
            if (byte == '"' or byte == '\\') try text.append(allocator, '\\');
            try text.append(allocator, byte);
        }
        try text.append(allocator, '"');
    }
    return text.toOwnedSlice(allocator);
}

/// Make `environment` carry exactly `options` for a child program: set the
/// variable to their spelling, or remove it when there are none, so an
/// inherited value never adds options the launcher did not ask for.
pub fn apply(allocator: std.mem.Allocator, environment: *std.process.Environ.Map, options: []const []const u8) std.mem.Allocator.Error!void {
    if (options.len == 0) {
        _ = environment.swapRemove(variable);
        return;
    }
    try environment.put(variable, try encode(allocator, options));
}

// spec-case: NATIVE-ARGV-1
test "a launcher's tail divides at its first delimiter and later delimiters are the program's" {
    const tail = split(&.{ "--gc-stress", "--", "--print-result", "--", "x" });
    try std.testing.expectEqual(@as(usize, 1), tail.options.len);
    try std.testing.expectEqualStrings("--gc-stress", tail.options[0]);
    try std.testing.expectEqual(@as(usize, 3), tail.program.len);
    try std.testing.expectEqualStrings("--", tail.program[1]);
    try std.testing.expectEqual(@as(usize, 2), split(&.{ "--restrict", "--allow-clock" }).options.len);
    try std.testing.expectEqual(@as(usize, 0), split(&.{ "--restrict", "--allow-clock" }).program.len);
}

// spec-case: NATIVE-ARGV-1
test "options are spelled bare unless whitespace, a quote or a backslash needs quoting" {
    const spelled = try encode(std.testing.allocator, &.{ "--gc-stress", "--allow-read=my notes", "--allow-read=a\"b\\c", "" });
    defer std.testing.allocator.free(spelled);
    try std.testing.expectEqualStrings("--gc-stress \"--allow-read=my notes\" \"--allow-read=a\\\"b\\\\c\" \"\"", spelled);
}

// spec-case: NATIVE-ARGV-1
test "applying no options removes an inherited value" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try environment.put(variable, "--gc-stress");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try apply(arena.allocator(), &environment, &.{});
    try std.testing.expect(environment.get(variable) == null);
    try apply(arena.allocator(), &environment, &.{"--print-result"});
    try std.testing.expectEqualStrings("--print-result", environment.get(variable).?);
}
