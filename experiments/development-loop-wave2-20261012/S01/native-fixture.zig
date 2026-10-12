const std = @import("std");
test "telemetry fast assertion" {
    try std.testing.expectEqual(@as(u8, 4), 2 + 2);
}
test "telemetry skipped assertion" {
    return error.SkipZigTest;
}
