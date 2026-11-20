//! Dynamic output borrows text only while copying octets into stream staging.
const std = @import("std");
const language = @import("selka");
const build = @import("build.zig");
const zero = @import("zero_rc.zig");
const support = @import("test_support.zig");

// spec-case: RUNTIME-THREADS-1
test "ownership output admits exact staging and borrowed text boundaries" {
    for ([_][]const u8{ "myl_core_output_begin", "myl_core_output_end", "myl_core_stream_write" }) |name| {
        const boundary = zero.contract(name).?;
        try std.testing.expectEqual(.scalar, boundary.result);
        try std.testing.expectEqual(@as(u64, 0), boundary.owned);
        try std.testing.expectEqual(@as(u64, 0), boundary.views);
    }
    try std.testing.expect(zero.contract("myl_core_output_begin_extra") == null);
    try std.testing.expect(zero.contract("myl_core_output_end_extra") == null);
    try std.testing.expect(zero.contract("myl_core_stream_write_extra") == null);
}

// spec-case: RUNTIME-THREADS-1
test "ownership output preserves dynamic separators and terminators without leaks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "ownership-output.selka",
        \\func main(out: Stream) -> int:
        \\    const xs = [1, 2]
        \\    print(out, xs[0], xs[1], sep="|", end="!")
        \\    return 0
    );
    try unit.check();
    var failure: @import("single_owner.zig").Failure = .{};
    try @import("single_owner.zig").check(a, unit.program.?, &failure);
    for ([_]bool{ false, true }) |release| {
        var refusal: build.Refusal = .{};
        var module = try build.buildExecutable(a, .{ .program = unit.program.? }, &refusal);
        const result = try support.runOwned(a, &module, .{ .release = release });
        try std.testing.expectEqual(@as(u8, 0), result.status);
        try std.testing.expectEqualStrings("1|2!", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        try std.testing.expect(std.mem.indexOf(u8, result.llvm, "@myl_core_output_begin") != null);
        try std.testing.expect(std.mem.indexOf(u8, result.llvm, "@myl_core_output_end") != null);
        try std.testing.expect(zero.emittedClean(result.llvm));
    }
}
