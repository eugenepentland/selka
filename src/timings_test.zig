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

test "named sub-regions leave the open phase and a disabled profile records nothing" {
    var profile = timings.Profile.init(std.testing.io, true, .compiler);
    profile.begin("parent", false);
    // A region measured inside the open phase is accumulated, never closes it.
    profile.add("child", 3, false);
    profile.end();
    try std.testing.expectEqual(@as(usize, 2), profile.records.len);
    try std.testing.expectEqualStrings("child", profile.records.phases[0].name);
    try std.testing.expectEqual(@as(i96, 3), profile.records.phases[0].duration_ns);
    try std.testing.expectEqualStrings("parent", profile.records.phases[1].name);

    var quiet = timings.Profile.init(std.testing.io, false, .compiler);
    const mark = quiet.now();
    quiet.addSince("ignored", mark, false);
    try std.testing.expectEqual(@as(usize, 0), quiet.records.len);
}

test "an exclusive window records its wall time less the exclusive phases recorded inside it" {
    var profile = timings.Profile.init(std.testing.io, true, .compiler);
    const window = profile.mark();
    // A nested phase longer than any wall time here leaves the enclosing window empty.
    profile.add("nested", 1 << 60, false);
    profile.addMark("outer", window, false);
    try std.testing.expectEqual(@as(usize, 2), profile.records.len);
    try std.testing.expectEqualStrings("outer", profile.records.phases[1].name);
    try std.testing.expectEqual(@as(i96, 0), profile.records.phases[1].duration_ns);
    try std.testing.expectEqual(@as(i96, 1 << 60), profile.records.exclusive_ns);
}

test "an inclusive window keeps its wall time and an exclusive begin phase drops nested time" {
    var profile = timings.Profile.init(std.testing.io, true, .compiler);
    const window = profile.mark();
    profile.add("nested", 1 << 60, false);
    profile.addMark("total", window, true);
    try std.testing.expectEqualStrings("total", profile.records.phases[1].name);
    try std.testing.expect(profile.records.phases[1].inclusive);
    try std.testing.expect(profile.records.phases[1].duration_ns < 1 << 60);
    profile.begin("parent", false);
    profile.add("child", 1 << 60, false);
    profile.end();
    try std.testing.expectEqualStrings("parent", profile.records.phases[3].name);
    try std.testing.expectEqual(@as(i96, 0), profile.records.phases[3].duration_ns);
}

test "a disabled profile's mark records nothing and reads no clock" {
    var quiet = timings.Profile.init(std.testing.io, false, .compiler);
    const window = quiet.mark();
    quiet.addMark("ignored", window, false);
    try std.testing.expectEqual(@as(usize, 0), quiet.records.len);
    try std.testing.expectEqual(@as(i96, 0), quiet.records.exclusive_ns);
}
