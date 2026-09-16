const std = @import("std");
const timings = @import("timings.zig");

// spec: PHASE-TIMING-2
test "profile add accumulates same-name exclusive phases and never overflows" {
    var profile = timings.Profile.init(std.testing.io, true, .compiler);
    profile.add("same_phase", 10, false);
    profile.add("same_phase", 5, false);
    try std.testing.expectEqual(@as(usize, 1), profile.records.len);
    try std.testing.expectEqual(@as(i96, 15), profile.records.phases[0].duration_ns);
    try std.testing.expect(!profile.records.phases[0].inclusive);

    var names: [100][12]u8 = undefined;
    for (0..100) |index| {
        const name = try std.fmt.bufPrint(&names[index], "phase{d}", .{index});
        profile.add(name, 1, false);
    }
    try std.testing.expect(profile.records.len <= profile.records.phases.len);
}
