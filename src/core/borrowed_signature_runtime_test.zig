//! Native destruction and owner retention for results declared with `from`.
const std = @import("std");
const modes = @import("native_language_modes.zig");

test "O3 borrowed signatures preserve wrappers slices final mut owners and more than 64 sources in native modes" {
    try std.testing.expectEqual(@as(usize, 3), try modes.run(std.testing.allocator, .{
        .path = "tests/lang/borrowed_signatures.selka",
        .passed = 12,
        .label = "borrowed signature runtime",
    }));
}
