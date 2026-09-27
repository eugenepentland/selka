//! Runtime selector flags are compiler arguments only before the guest delimiter.
const std = @import("std");
const contract = @import("runtime_contract");

/// Remaining arguments and an explicit runtime request, if one was present.
pub const Parsed = struct { args: []const [:0]const u8, explicit: ?contract.Selection };

/// Remove exactly one supported runtime flag, rejecting malformed or duplicate flags.
pub fn parse(a: std.mem.Allocator, args: []const [:0]const u8) error{ OutOfMemory, InvalidRuntimeOption }!Parsed {
    var kept: std.ArrayList([:0]const u8) = .empty;
    errdefer kept.deinit(a);
    var selected: ?contract.Selection = null;
    var guest = false;
    for (args, 0..) |arg, index| {
        if (std.mem.eql(u8, arg, "--")) guest = true;
        const mode = if (index >= 2 and !guest) try option(arg) else null;
        if (mode) |value| {
            if (selected != null) return error.InvalidRuntimeOption;
            selected = value;
        } else try kept.append(a, arg);
    }
    return .{ .args = try kept.toOwnedSlice(a), .explicit = selected };
}

fn option(arg: []const u8) error{InvalidRuntimeOption}!?contract.Selection {
    if (std.mem.eql(u8, arg, "--gc-runtime")) return .gc;
    if (std.mem.eql(u8, arg, "--rc-runtime")) return .rc;
    if (std.mem.eql(u8, arg, "--rc-runtime=stats")) return .rc_counting;
    if (std.mem.startsWith(u8, arg, "--rc-runtime=") or std.mem.startsWith(u8, arg, "--gc-runtime=")) return error.InvalidRuntimeOption;
    return null;
}

// spec-case: RC-RUNTIME-CLI-1
test "runtime options preserve guest flags and reject duplicate and invalid selections" {
    const a = std.testing.allocator;
    const parsed = try parse(a, &.{ "mylang", "run", "--rc-runtime=stats", "main.my", "--", "--gc-runtime" });
    defer a.free(parsed.args);
    try std.testing.expectEqual(contract.Selection.rc_counting, parsed.explicit.?);
    try std.testing.expectEqual(@as(usize, 5), parsed.args.len);
    try std.testing.expectEqualStrings("--gc-runtime", parsed.args[4]);
    try std.testing.expectError(error.InvalidRuntimeOption, parse(a, &.{ "mylang", "check", "main.my", "--rc-runtime", "--gc-runtime" }));
    try std.testing.expectError(error.InvalidRuntimeOption, parse(a, &.{ "mylang", "test", "--rc-runtime=unknown" }));
    try std.testing.expectError(error.InvalidRuntimeOption, parse(a, &.{ "mylang", "build", "--gc-runtime=stats" }));
}
