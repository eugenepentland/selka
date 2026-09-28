//! Runtime selector flags are compiler arguments only before the guest delimiter.
const std = @import("std");
const contract = @import("runtime_contract");

/// Remaining arguments, an explicit runtime request if one was present, and
/// whether the command's own options (before `--`) ask for collector stress,
/// which only the tracing collector has (`RC-DEFAULT-1`).
pub const Parsed = struct { args: []const [:0]const u8, explicit: ?contract.Selection, stress: bool = false };

/// Remove exactly one supported runtime flag, rejecting malformed or duplicate flags.
pub fn parse(a: std.mem.Allocator, args: []const [:0]const u8) error{ OutOfMemory, InvalidRuntimeOption }!Parsed {
    var kept: std.ArrayList([:0]const u8) = .empty;
    errdefer kept.deinit(a);
    var selected: ?contract.Selection = null;
    var stress = false;
    var guest = false;
    for (args, 0..) |arg, index| {
        if (std.mem.eql(u8, arg, "--")) guest = true;
        // The stress switch stays in the arguments: the command still runs it.
        if (index >= 2 and !guest and std.mem.eql(u8, arg, "--gc-stress")) stress = true;
        const mode = if (index >= 2 and !guest) try option(arg) else null;
        if (mode) |value| {
            if (selected != null) return error.InvalidRuntimeOption;
            selected = value;
        } else try kept.append(a, arg);
    }
    return .{ .args = try kept.toOwnedSlice(a), .explicit = selected, .stress = stress };
}

fn option(arg: []const u8) error{InvalidRuntimeOption}!?contract.Selection {
    if (std.mem.eql(u8, arg, "--gc-runtime")) return .gc;
    if (std.mem.eql(u8, arg, "--rc-runtime")) return .rc;
    if (std.mem.eql(u8, arg, "--rc-runtime=stats")) return .rc_counting;
    if (std.mem.eql(u8, arg, "--rc-runtime=sites")) return .rc_sites;
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
    const sites = try parse(a, &.{ "mylang", "build", "main.my", "--rc-runtime=sites" });
    defer a.free(sites.args);
    try std.testing.expectEqual(contract.Selection.rc_sites, sites.explicit.?);
    try std.testing.expectError(error.InvalidRuntimeOption, parse(a, &.{ "mylang", "test", "--rc-runtime=unknown" }));
    try std.testing.expectError(error.InvalidRuntimeOption, parse(a, &.{ "mylang", "build", "--gc-runtime=stats" }));
}

// spec-case: RC-DEFAULT-1
test "runtime options notice collector stress among compiler options but not guest arguments" {
    const a = std.testing.allocator;
    const stressed = try parse(a, &.{ "mylang", "test", "suite", "--gc-stress" });
    defer a.free(stressed.args);
    try std.testing.expect(stressed.stress and stressed.explicit == null);
    try std.testing.expectEqualStrings("--gc-stress", stressed.args[3]);
    const guest = try parse(a, &.{ "mylang", "run", "main.my", "--", "--gc-stress" });
    defer a.free(guest.args);
    try std.testing.expect(!guest.stress);
    const both = try parse(a, &.{ "mylang", "run", "main.my", "--gc-runtime", "--gc-stress" });
    defer a.free(both.args);
    try std.testing.expect(both.stress);
    try std.testing.expectEqual(contract.Selection.gc, both.explicit.?);
}
